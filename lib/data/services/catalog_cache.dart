import 'package:hive_ce/hive.dart';

/// Disk cache for the panel catalog responses (categories and stream lists).
///
/// Some panels (behind Cloudflare, or just overloaded) take tens of seconds to
/// answer the catalog actions. Caching the raw JSON per profile makes every
/// launch after the first one instant, and doubles as an offline fallback:
/// when the network call fails (or returns an error page) and an entry exists
/// — even a stale one — we serve it instead of an empty catalog.
///
/// Freshness is [ttl]; "Aggiorna lista" clears the profile's entries first so
/// a manual refresh always hits the network. Backed by a [LazyBox] so the
/// (potentially large) payloads live on disk, not in RAM.
class CatalogCache {
  CatalogCache(this._box);

  final LazyBox<Map> _box;

  static const ttl = Duration(hours: 24);

  /// Hive keys must be ASCII and ≤255 chars: strip the rest and, for very
  /// long keys, keep a prefix (so [clearPrefix] still matches) plus a hash.
  static String _safeKey(String raw) {
    final ascii = raw.replaceAll(RegExp(r'[^\x20-\x7E]'), '_');
    if (ascii.length <= 200) return ascii;
    return '${ascii.substring(0, 160)}#${ascii.hashCode.toRadixString(16)}';
  }

  /// Cached body for [key] if present and younger than [maxAge] (defaults to
  /// [ttl]; the short-lived EPG entries pass their own).
  Future<String?> fresh(String key, {Duration? maxAge}) async {
    final entry = await _box.get(_safeKey(key));
    if (entry == null) return null;
    final ts = entry['ts'] as int? ?? 0;
    final age = DateTime.now().millisecondsSinceEpoch - ts;
    if (age > (maxAge ?? ttl).inMilliseconds) return null;
    return entry['body'] as String?;
  }

  /// Cached body for [key] regardless of age (network-failure fallback).
  Future<String?> anyAge(String key) async {
    final entry = await _box.get(_safeKey(key));
    return entry?['body'] as String?;
  }

  Future<void> put(String key, String body) {
    return _box.put(_safeKey(key), {
      'ts': DateTime.now().millisecondsSinceEpoch,
      'body': body,
    });
  }

  /// Removes every entry whose key starts with [keyPrefix] (one profile's
  /// scope), so a manual "Aggiorna lista" really re-fetches from the panel.
  Future<void> clearPrefix(String keyPrefix) async {
    final prefix = _safeKey(keyPrefix);
    final keys =
        _box.keys.where((k) => k.toString().startsWith(prefix)).toList();
    await _box.deleteAll(keys);
  }
}
