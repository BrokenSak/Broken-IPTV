import 'dart:convert';
import 'dart:io';

import '../models/epg_program.dart';

/// Parses an XMLTV document (plain or gzipped bytes) into programmes per
/// channel id, keeping only a now−6h … now+36h window (and optionally only
/// [onlyChannels]) to bound memory on huge guides. Extracted from the M3U
/// source so the Xtream bulk EPG can reuse it.
Map<String, List<EpgProgram>> parseXmltvBytes(
  List<int> bytes, {
  Set<String>? onlyChannels,
  DateTime? from,
  DateTime? to,
}) {
  if (bytes.isEmpty) return const {};
  // Gunzip if needed (magic bytes 0x1f 0x8b), common for XMLTV feeds.
  if (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
    bytes = GZipCodec().decode(bytes);
  }
  final xml = utf8.decode(bytes, allowMalformed: true);
  return parseXmltv(xml, onlyChannels: onlyChannels, from: from, to: to);
}

Map<String, List<EpgProgram>> parseXmltv(
  String xml, {
  Set<String>? onlyChannels,
  DateTime? from,
  DateTime? to,
}) {
  final fromT = from ?? DateTime.now().subtract(const Duration(hours: 6));
  final toT = to ?? DateTime.now().add(const Duration(hours: 36));

  final byChannel = <String, List<EpgProgram>>{};
  final progRe = RegExp(r'<programme\b([^>]*)>(.*?)</programme>', dotAll: true);
  final titleRe = RegExp(r'<title[^>]*>(.*?)</title>', dotAll: true);
  final descRe = RegExp(r'<desc[^>]*>(.*?)</desc>', dotAll: true);

  for (final m in progRe.allMatches(xml)) {
    final attrs = m.group(1) ?? '';
    final body = m.group(2) ?? '';
    final channel = _attr(attrs, 'channel');
    if (channel == null) continue;
    if (onlyChannels != null && !onlyChannels.contains(channel)) continue;
    final start = parseXmltvTime(_attr(attrs, 'start'));
    final stop = parseXmltvTime(_attr(attrs, 'stop'));
    if (start == null || stop == null) continue;
    if (stop.isBefore(fromT) || start.isAfter(toT)) continue;
    final title = _unescape((titleRe.firstMatch(body)?.group(1) ?? '').trim());
    final desc = _unescape((descRe.firstMatch(body)?.group(1) ?? '').trim());
    (byChannel[channel] ??= []).add(EpgProgram(
      title: title.isEmpty ? 'Programma' : title,
      description: desc,
      start: start,
      end: stop,
    ));
  }
  for (final list in byChannel.values) {
    list.sort((a, b) => a.start.compareTo(b.start));
  }
  return byChannel;
}

String? _attr(String attrs, String key) {
  final m = RegExp('$key="([^"]*)"').firstMatch(attrs);
  return m?.group(1);
}

/// Parses an XMLTV timestamp like `20240101203000 +0100`.
DateTime? parseXmltvTime(String? s) {
  if (s == null || s.length < 14) return null;
  try {
    final y = int.parse(s.substring(0, 4));
    final mo = int.parse(s.substring(4, 6));
    final d = int.parse(s.substring(6, 8));
    final h = int.parse(s.substring(8, 10));
    final mi = int.parse(s.substring(10, 12));
    final se = int.parse(s.substring(12, 14));
    var dt = DateTime.utc(y, mo, d, h, mi, se);
    final tz = RegExp(r'([+-])(\d{2})(\d{2})').firstMatch(s);
    if (tz != null) {
      final sign = tz.group(1) == '-' ? 1 : -1; // convert to UTC
      final offH = int.parse(tz.group(2)!);
      final offM = int.parse(tz.group(3)!);
      dt = dt.add(Duration(hours: sign * offH, minutes: sign * offM));
    }
    return dt.toLocal();
  } catch (_) {
    return null;
  }
}

String _unescape(String s) {
  return s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('<![CDATA[', '')
      .replaceAll(']]>', '');
}

/// Bulk EPG for an Xtream profile: downloads the panel's whole guide ONCE
/// (`xmltv.php`) and answers every channel lookup locally — the way
/// mainstream IPTV apps (TiviMate & co.) do it. One request instead of one
/// per visible channel tile, which panels read as flooding.
///
/// The raw guide is also cached on a file for [ttl], so app relaunches don't
/// re-download it. When the guide is unavailable or lacks a channel, callers
/// fall back to the per-channel short-EPG (throttled + cached).
class EpgStore {
  EpgStore({
    required this._fetch, // exposed to callers as `fetch:`
    this._cacheFile, // exposed to callers as `cacheFile:`
    this.ttl = const Duration(hours: 12),
  });

  final Future<List<int>?> Function() _fetch;
  final File? _cacheFile;
  final Duration ttl;

  Future<bool>? _loading;
  Map<String, List<EpgProgram>>? _byChannel;

  /// Loads the guide once (single-flight). False = bulk EPG unavailable.
  Future<bool> ensureLoaded() => _loading ??= _load();

  Future<bool> _load() async {
    // 1. Fresh file cache.
    try {
      final f = _cacheFile;
      if (f != null && await f.exists()) {
        final age = DateTime.now().difference(await f.lastModified());
        if (age < ttl) {
          final parsed = parseXmltvBytes(await f.readAsBytes());
          if (parsed.isNotEmpty) {
            _byChannel = parsed;
            return true;
          }
        }
      }
    } catch (_) {}

    // 2. Network (one request for the whole guide).
    List<int>? bytes;
    try {
      bytes = await _fetch();
    } catch (_) {
      bytes = null;
    }
    if (bytes == null || bytes.isEmpty) return false;
    final parsed = parseXmltvBytes(bytes);
    if (parsed.isEmpty) return false;
    _byChannel = parsed;
    try {
      await _cacheFile?.writeAsBytes(bytes, flush: true);
    } catch (_) {}
    return true;
  }

  /// Current + upcoming programmes for [epgChannelId], or null when the bulk
  /// guide has nothing for that channel (caller decides whether to fall back).
  List<EpgProgram>? programsFor(String epgChannelId, {int limit = 20}) {
    final all = _byChannel?[epgChannelId];
    if (all == null || all.isEmpty) return null;
    final now = DateTime.now();
    final upcoming = all.where((p) => p.end.isAfter(now)).take(limit).toList();
    return upcoming.isNotEmpty ? upcoming : null;
  }
}
