import 'package:dio/dio.dart';

import '../models/channel.dart';
import '../models/epg_program.dart';
import '../models/json_utils.dart';
import '../models/series_item.dart';
import '../models/vod_item.dart';
import '../models/xtream_category.dart';
import 'catalog_cache.dart';
import 'content_source.dart';
import 'dio_error_utils.dart';
import 'epg_store.dart';
import 'panel_http.dart';
import 'request_throttle.dart';
import 'xtream_api_service.dart';

/// An authenticated Xtream Codes session for a specific profile. Unlike
/// [XtreamApiService] (used only for the stateless "test connection" check),
/// this holds the credentials and is used for every actual data call once a
/// profile has been selected.
class XtreamSession implements ContentSource {
  XtreamSession({
    required String host,
    required this.username,
    required this.password,
    Dio? dio,
    this._cache, // exposed to callers as `cache:`
    this._epgStore, // exposed to callers as `epgStore:`
  })  : host = XtreamApiService.normalizeHost(host),
        _dio = dio ?? createPanelDio();

  final String host;
  final String username;
  final String password;
  final Dio _dio;
  final CatalogCache? _cache;

  /// Bulk EPG (panel xmltv.php): one download for the whole guide, so channel
  /// tiles don't turn into hundreds of per-channel calls. Null → per-channel.
  final EpgStore? _epgStore;

  /// streamId → epg_channel_id, built once from the (disk-cached) full
  /// channel list; memoized as a future so concurrent tiles share the work.
  Future<Map<String, String>>? _epgIdMap;

  /// In-flight de-duplication for cacheable calls: concurrent identical
  /// requests (e.g. counts + search both wanting the full channel list before
  /// the cache is written) share one network hit.
  final _inflight = <String, Future<dynamic>>{};

  /// Catalog actions worth caching on disk: big, slow on some panels, and
  /// stable across a session.
  static const _catalogActions = {
    'get_live_categories',
    'get_live_streams',
    'get_vod_categories',
    'get_vod_streams',
    'get_series_categories',
    'get_series',
  };

  /// Short disk cache for the per-channel EPG too: re-entering a screen (or
  /// relaunching the app) must not re-fire hundreds of `get_short_epg` calls.
  static const _epgTtl = Duration(minutes: 15);

  /// One global pacer for the EPG calls (see [RequestThrottle]): grids fire
  /// them in bursts while scrolling, and panel flood protection blocks
  /// accounts for exactly that pattern. Account info stays always-fresh.
  static final _epgThrottle = RequestThrottle();

  /// How long a cached response for [action] stays valid; null = don't cache.
  Duration? _cacheTtlFor(String action) {
    if (_catalogActions.contains(action)) return CatalogCache.ttl;
    if (action == 'get_short_epg') return _epgTtl;
    return null;
  }

  /// Whether a decoded payload is worth persisting (an error/challenge page
  /// must never poison the cache). Catalogs are list-shaped; the EPG is a
  /// map ({"epg_listings": [...]}) — an empty one is fine to cache too, so
  /// guideless channels don't get re-queried on every visit.
  bool _persistable(String action, dynamic decoded) {
    if (action == 'get_short_epg') return decoded is Map || decoded is List;
    return asPanelList(decoded) != null;
  }

  // No password in the cache key: the box is plain on disk.
  String _cacheKey(String action, Map<String, String>? extra) {
    // NB: build a fresh growable list — `const [] ..sort()` throws
    // "Cannot modify an unmodifiable list" (broke every no-extra call).
    final params = [
      if (extra != null)
        for (final e in extra.entries) '${e.key}=${e.value}',
    ]..sort();
    return '$host|$username|$action|${params.join('&')}';
  }

  /// Drops this profile's cached catalogs ("Aggiorna lista" calls this so the
  /// refresh really hits the panel).
  Future<void> clearCatalogCache() async {
    await _cache?.clearPrefix('$host|$username|');
  }

  Future<dynamic> _call(String action, [Map<String, String>? extra]) {
    final cache = _cache;
    final ttl = _cacheTtlFor(action);
    if (cache == null || ttl == null) {
      return _fetch(action, extra, null, null, '');
    }
    final cacheKey = _cacheKey(action, extra);
    // Single-flight per key: identical concurrent calls share one request.
    // NB: the cleanup callback must have a BLOCK body — `=> map.remove(k)`
    // returns the removed future and whenComplete would then wait for it,
    // i.e. the future would wait for itself (deadlock: every call hung).
    return _inflight[cacheKey] ??=
        _fetch(action, extra, cache, ttl, cacheKey).whenComplete(() {
      _inflight.remove(cacheKey);
    });
  }

  Future<dynamic> _fetch(
    String action,
    Map<String, String>? extra,
    CatalogCache? cache,
    Duration? ttl,
    String cacheKey,
  ) async {
    final cacheable = cache != null;

    // Fresh cache hit → skip the network entirely (slow panels take tens of
    // seconds per catalog call; see CatalogCache).
    if (cacheable) {
      final hit = await cache.fresh(cacheKey, maxAge: ttl);
      if (hit != null) return decodePanelJson(hit);
    }

    dynamic body;
    try {
      // Force a plain-string response and decode JSON ourselves: many Xtream
      // panels return JSON with a non-JSON Content-Type (e.g. text/html), and
      // Dio would then hand back the raw String instead of a Map/List. That
      // made expiry/account come back empty and catalogs look empty — all
      // silently. decodePanelJson also survives BOMs and PHP warnings printed
      // before the payload.
      Future<Response<dynamic>> doGet() => _dio.get(
            '$host/player_api.php',
            queryParameters: {
              'username': username,
              'password': password,
              if (action.isNotEmpty) 'action': action,
              ...?extra,
            },
            options: Options(responseType: ResponseType.plain),
          );
      // EPG bursts get paced; everything else goes straight out.
      final response = action == 'get_short_epg'
          ? await _epgThrottle.run(doGet)
          : await doGet();
      body = response.data;
    } on DioException catch (e) {
      // Network failure with any cached copy (even stale): serve the cache
      // instead of an empty catalog / error screen.
      if (cacheable) {
        final stale = await cache.anyAge(cacheKey);
        if (stale != null) return decodePanelJson(stale);
      }
      throw XtreamSessionException(messageForDioError(e));
    }

    final decoded = decodePanelJson(body);
    if (cacheable) {
      if (body is String && _persistable(action, decoded)) {
        await cache.put(cacheKey, body);
      } else if (!_persistable(action, decoded)) {
        // Invalid response (block page, connection-limit error): prefer the
        // stale cached copy over surfacing an error.
        final stale = await cache.anyAge(cacheKey);
        if (stale != null) return decodePanelJson(stale);
      }
    }
    return decoded;
  }

  /// Coerces a "list" endpoint response to a List (tolerating the numeric-keys
  /// object shape some panels emit). A response with neither shape means the
  /// panel returned an error/HTML page instead of data — usually a temporary
  /// block or a connection-limit hit — so surface it rather than show empty.
  List<dynamic> _requireList(dynamic data) {
    final list = asPanelList(data);
    if (list == null) {
      throw XtreamSessionException(
        'Il server non ha restituito dati validi. '
        'Potrebbe aver raggiunto il limite di connessioni o bloccato '
        'temporaneamente l\'accesso. Riprova tra qualche minuto.',
      );
    }
    return list;
  }

  static int? _asIntStatic(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  /// Account expiry date (from user_info.exp_date), or null if unlimited/unknown.
  @override
  Future<DateTime?> getExpiryDate() async {
    final data = await _call('');
    if (data is! Map) return null;
    final userInfo = data['user_info'];
    if (userInfo is! Map) return null;
    final ts = _asIntStatic(userInfo['exp_date']);
    if (ts == null || ts == 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ts * 1000);
  }

  /// Full account/subscription info for the Account panel (expiry, connection
  /// limits, trial flag, server) from user_info + server_info.
  @override
  Future<AccountInfo?> getAccountInfo() async {
    final data = await _call('');
    if (data is! Map) return null;
    final u = asStringMapOrNull(data['user_info']);
    final s = asStringMapOrNull(data['server_info']);
    if (u == null) return null;

    DateTime? toDate(dynamic v) {
      final n = _asIntStatic(v);
      if (n == null || n == 0) return null;
      return DateTime.fromMillisecondsSinceEpoch(n * 1000);
    }

    bool? toBool(dynamic v) {
      if (v == null) return null;
      final n = _asIntStatic(v);
      if (n != null) return n == 1;
      final str = v.toString().toLowerCase();
      if (str == 'true') return true;
      if (str == 'false') return false;
      return null;
    }

    return AccountInfo(
      status: u['status']?.toString(),
      expiresAt: toDate(u['exp_date']),
      isTrial: toBool(u['is_trial']),
      activeConnections: _asIntStatic(u['active_cons']),
      maxConnections: _asIntStatic(u['max_connections']),
      createdAt: toDate(u['created_at']),
      serverUrl: s?['url']?.toString() ?? host,
      timezone: s?['timezone']?.toString(),
    );
  }

  @override
  Future<List<XtreamCategory>> getLiveCategories() async {
    final data = await _call('get_live_categories');
    return _requireList(data)
        .whereType<Map>()
        .map((e) => XtreamCategory.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<List<Channel>> getLiveStreams({String? categoryId}) async {
    final data = await _call(
      'get_live_streams',
      categoryId != null ? {'category_id': categoryId} : null,
    );
    return (asPanelList(data) ?? const [])
        .whereType<Map>()
        .map((e) => Channel.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<List<EpgProgram>> getShortEpg(String streamId, {int limit = 20}) async {
    // Preferred path: the bulk guide (xmltv.php), downloaded once for ALL
    // channels — the way mainstream IPTV apps do it. Falls back to the
    // per-channel call (throttled + cached) when the panel has no usable
    // XMLTV or this channel isn't in it.
    final store = _epgStore;
    if (store != null && await store.ensureLoaded()) {
      final epgId = await _epgChannelIdOf(streamId);
      if (epgId != null) {
        final programs = store.programsFor(epgId, limit: limit);
        if (programs != null && programs.isNotEmpty) return programs;
      }
    }

    final data = await _call('get_short_epg', {
      'stream_id': streamId,
      'limit': limit.toString(),
    });
    if (data is! Map) return const [];
    final listings = asPanelList(data['epg_listings']);
    if (listings == null) return const [];
    return listings
        .whereType<Map>()
        .map((e) => EpgProgram.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  /// Maps a live stream id to its `epg_channel_id` using the (disk-cached)
  /// full channel list; memoized so concurrent tiles share one lookup.
  Future<String?> _epgChannelIdOf(String streamId) {
    final future = _epgIdMap ??= () async {
      try {
        final channels = await getLiveStreams();
        return {
          for (final c in channels)
            if (c.epgChannelId != null && c.epgChannelId!.isNotEmpty)
              c.streamId: c.epgChannelId!,
        };
      } catch (_) {
        return <String, String>{};
      }
    }();
    return future.then((map) => map[streamId]);
  }

  @override
  Future<List<XtreamCategory>> getVodCategories() async {
    final data = await _call('get_vod_categories');
    return _requireList(data)
        .whereType<Map>()
        .map((e) => XtreamCategory.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<List<VodItem>> getVodStreams({String? categoryId}) async {
    final data = await _call(
      'get_vod_streams',
      categoryId != null ? {'category_id': categoryId} : null,
    );
    return (asPanelList(data) ?? const [])
        .whereType<Map>()
        .map((e) => VodItem.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<VodDetail> getVodInfo(String vodId) async {
    final data = await _call('get_vod_info', {'vod_id': vodId});
    if (data is! Map) {
      throw XtreamSessionException('Dettagli film non disponibili.');
    }
    return VodDetail.fromJson(vodId, data.cast<String, dynamic>());
  }

  @override
  Future<List<XtreamCategory>> getSeriesCategories() async {
    final data = await _call('get_series_categories');
    return _requireList(data)
        .whereType<Map>()
        .map((e) => XtreamCategory.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<List<SeriesItem>> getSeries({String? categoryId}) async {
    final data = await _call(
      'get_series',
      categoryId != null ? {'category_id': categoryId} : null,
    );
    return (asPanelList(data) ?? const [])
        .whereType<Map>()
        .map((e) => SeriesItem.fromJson(e.cast<String, dynamic>()))
        .toList();
  }

  @override
  Future<SeriesDetail> getSeriesInfo(String seriesId) async {
    final data = await _call('get_series_info', {'series_id': seriesId});
    if (data is! Map) {
      throw XtreamSessionException('Dettagli serie non disponibili.');
    }
    return SeriesDetail.fromJson(seriesId, data.cast<String, dynamic>());
  }

  @override
  String vodStreamUrl(String streamId, String containerExtension) {
    return '$host/movie/$username/$password/$streamId.$containerExtension';
  }

  @override
  String seriesEpisodeUrl(String episodeId, String containerExtension) {
    return '$host/series/$username/$password/$episodeId.$containerExtension';
  }

  // Raw MPEG-TS is a continuous live stream (the .m3u8 variant is often a
  // short VOD-like window that stops after ~30s), so default live playback
  // to .ts to keep it running indefinitely.
  @override
  String liveStreamUrl(String streamId, {String ext = 'ts'}) {
    return '$host/live/$username/$password/$streamId.$ext';
  }

  /// Xtream Codes catch-up/timeshift URL. Format and availability vary
  /// between panels — only usable when the channel reports `tv_archive`.
  @override
  String timeshiftUrl(String streamId, DateTime start, Duration duration, {String ext = 'ts'}) {
    final durationMinutes = duration.inMinutes.clamp(1, 1 << 30);
    String two(int n) => n.toString().padLeft(2, '0');
    final startToken =
        '${start.year}-${two(start.month)}-${two(start.day)}:${two(start.hour)}-${two(start.minute)}';
    return '$host/timeshift/$username/$password/$durationMinutes/$startToken/$streamId.$ext';
  }
}

class XtreamSessionException implements Exception {
  XtreamSessionException(this.message);
  final String message;

  @override
  String toString() => message;
}
