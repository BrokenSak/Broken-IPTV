import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/channel.dart';
import '../models/epg_program.dart';
import '../models/series_item.dart';
import '../models/vod_item.dart';
import '../models/xtream_category.dart';
import 'content_source.dart';
import 'epg_store.dart';
import 'panel_http.dart';

/// A [ContentSource] backed by a plain **M3U** playlist plus an optional
/// **XMLTV** EPG. Live channels and movies are parsed from the M3U (grouped by
/// `group-title`); the M3U entry URL *is* the stream URL. Series are not
/// modelled by flat M3U playlists, so that section stays empty.
///
/// The playlist is fetched and parsed once, lazily, via [ensureLoaded].
class M3uSource implements ContentSource {
  M3uSource({required this.m3uUrl, this.epgUrl, Dio? dio})
      : _dio = dio ??
            createPanelDio(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 60),
            );

  final String m3uUrl;
  final String? epgUrl;
  final Dio _dio;

  bool _loaded = false;

  final List<XtreamCategory> _liveCategories = [];
  final Map<String, List<Channel>> _channelsByCat = {};
  final List<Channel> _allChannels = [];
  final Map<String, String> _channelUrl = {};

  final List<XtreamCategory> _vodCategories = [];
  final Map<String, List<VodItem>> _vodByCat = {};
  final List<VodItem> _allVod = [];
  final Map<String, String> _vodUrl = {};
  final Map<String, VodItem> _vodById = {};
  final Map<String, String> _vodContainerById = {};

  // XMLTV programmes keyed by channel id (tvg-id).
  final Map<String, List<EpgProgram>> _epgByChannel = {};

  /// Fetches and parses the playlist (and EPG) exactly once.
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    await _loadM3u();
    // EPG is best-effort: a failure here must not break the catalog.
    try {
      await _loadEpg();
    } catch (_) {}
    _loaded = true;
  }

  Future<void> _loadM3u() async {
    final resp = await _dio.get<String>(
      m3uUrl,
      options: Options(responseType: ResponseType.plain),
    );
    final text = resp.data ?? '';
    final lines = const LineSplitter().convert(text);

    var liveIndex = 0;
    var vodIndex = 0;
    String? pendingExtInf;

    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#EXTM3U')) continue;
      if (line.startsWith('#EXTINF')) {
        pendingExtInf = line;
        continue;
      }
      if (line.startsWith('#')) continue; // other directives
      if (pendingExtInf == null) continue;

      final info = _parseExtInf(pendingExtInf);
      pendingExtInf = null;
      final url = line;

      final group = info.group.isNotEmpty ? info.group : 'Senza categoria';
      if (_isVodUrl(url)) {
        final id = 'm3u_vod_$vodIndex';
        vodIndex++;
        final item = VodItem(
          streamId: id,
          name: info.name,
          categoryId: group,
          posterUrl: info.logo,
        );
        _vodById[id] = item;
        _vodUrl[id] = url;
        _vodContainerById[id] = _extensionOf(url);
        _allVod.add(item);
        (_vodByCat[group] ??= []).add(item);
      } else {
        // Prefer the EPG id (tvg-id) as the stream id so short-EPG lookups work.
        final id = info.tvgId?.isNotEmpty == true ? info.tvgId! : 'm3u_ch_$liveIndex';
        liveIndex++;
        final channel = Channel(
          streamId: id,
          name: info.name,
          categoryId: group,
          logoUrl: info.logo,
          epgChannelId: info.tvgId,
        );
        _channelUrl[id] = url;
        _allChannels.add(channel);
        (_channelsByCat[group] ??= []).add(channel);
      }
    }

    _liveCategories
      ..clear()
      ..addAll(_channelsByCat.keys.map((g) => XtreamCategory(id: g, name: g)));
    _vodCategories
      ..clear()
      ..addAll(_vodByCat.keys.map((g) => XtreamCategory(id: g, name: g)));
  }

  static bool _isVodUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('/movie/') || lower.contains('/series/')) return true;
    final noQuery = lower.split('?').first;
    return RegExp(r'\.(mp4|mkv|avi|m4v|mov|flv)$').hasMatch(noQuery);
  }

  static String _extensionOf(String url) {
    final noQuery = url.split('?').first;
    final dot = noQuery.lastIndexOf('.');
    if (dot < 0 || dot < noQuery.length - 5) return 'mp4';
    final ext = noQuery.substring(dot + 1);
    return ext.isEmpty ? 'mp4' : ext;
  }

  static _ExtInf _parseExtInf(String line) {
    String? attr(String key) {
      final m = RegExp('$key="([^"]*)"').firstMatch(line);
      return m?.group(1);
    }

    // Display name is everything after the last comma.
    final comma = line.lastIndexOf(',');
    final name = comma >= 0 ? line.substring(comma + 1).trim() : 'Canale';
    return _ExtInf(
      name: name.isEmpty ? 'Canale' : name,
      tvgId: attr('tvg-id'),
      logo: attr('tvg-logo'),
      group: attr('group-title') ?? '',
    );
  }

  Future<void> _loadEpg() async {
    final url = epgUrl;
    if (url == null || url.trim().isEmpty) return;

    final resp = await _dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = resp.data ?? const [];
    if (bytes.isEmpty) return;

    // Only keep programmes for channels present in the playlist (the shared
    // parser already bounds the time window to now-6h … now+36h).
    final wantIds = _allChannels
        .map((c) => c.epgChannelId)
        .whereType<String>()
        .toSet();
    if (wantIds.isEmpty) return;

    _epgByChannel
      ..clear()
      ..addAll(parseXmltvBytes(bytes, onlyChannels: wantIds));
  }

  // ---- ContentSource ----

  @override
  Future<List<XtreamCategory>> getLiveCategories() async {
    await ensureLoaded();
    return List.unmodifiable(_liveCategories);
  }

  @override
  Future<List<Channel>> getLiveStreams({String? categoryId}) async {
    await ensureLoaded();
    if (categoryId == null) return List.unmodifiable(_allChannels);
    return List.unmodifiable(_channelsByCat[categoryId] ?? const []);
  }

  @override
  Future<List<EpgProgram>> getShortEpg(String streamId, {int limit = 20}) async {
    await ensureLoaded();
    final all = _epgByChannel[streamId];
    if (all == null || all.isEmpty) return const [];
    // Return the currently-airing programme plus the next few.
    final now = DateTime.now();
    final upcoming = all.where((p) => p.end.isAfter(now)).take(limit).toList();
    return upcoming.isNotEmpty ? upcoming : all.take(limit).toList();
  }

  @override
  String liveStreamUrl(String streamId, {String ext = 'ts'}) {
    // The M3U entry URL is the stream URL; ext is ignored.
    return _channelUrl[streamId] ?? '';
  }

  @override
  String timeshiftUrl(String streamId, DateTime start, Duration duration, {String ext = 'ts'}) {
    // Catch-up is not available for generic M3U playlists.
    return _channelUrl[streamId] ?? '';
  }

  @override
  Future<List<XtreamCategory>> getVodCategories() async {
    await ensureLoaded();
    return List.unmodifiable(_vodCategories);
  }

  @override
  Future<List<VodItem>> getVodStreams({String? categoryId}) async {
    await ensureLoaded();
    if (categoryId == null) return List.unmodifiable(_allVod);
    return List.unmodifiable(_vodByCat[categoryId] ?? const []);
  }

  @override
  Future<VodDetail> getVodInfo(String vodId) async {
    await ensureLoaded();
    final item = _vodById[vodId];
    return VodDetail(
      streamId: vodId,
      name: item?.name ?? 'Film',
      posterUrl: item?.posterUrl,
      containerExtension: _vodContainerById[vodId] ?? 'mp4',
    );
  }

  @override
  String vodStreamUrl(String streamId, String containerExtension) {
    return _vodUrl[streamId] ?? '';
  }

  // Series are not supported for flat M3U playlists.
  @override
  Future<List<XtreamCategory>> getSeriesCategories() async => const [];

  @override
  Future<List<SeriesItem>> getSeries({String? categoryId}) async => const [];

  @override
  Future<SeriesDetail> getSeriesInfo(String seriesId) async {
    throw Exception('Le serie non sono disponibili per le playlist M3U.');
  }

  @override
  String seriesEpisodeUrl(String episodeId, String containerExtension) => '';

  @override
  Future<DateTime?> getExpiryDate() async => null;

  @override
  Future<AccountInfo?> getAccountInfo() async {
    await ensureLoaded();
    return AccountInfo(
      status: 'Playlist M3U',
      serverUrl: Uri.tryParse(m3uUrl)?.host ?? m3uUrl,
    );
  }
}

class _ExtInf {
  const _ExtInf({required this.name, required this.tvgId, required this.logo, required this.group});
  final String name;
  final String? tvgId;
  final String? logo;
  final String group;
}
