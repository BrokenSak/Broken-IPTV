import 'package:dio/dio.dart';

import '../models/channel.dart';
import '../models/epg_program.dart';
import '../models/json_utils.dart';
import '../models/series_item.dart';
import '../models/vod_item.dart';
import '../models/xtream_category.dart';
import 'content_source.dart';
import 'dio_error_utils.dart';
import 'panel_http.dart';
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
  })  : host = XtreamApiService.normalizeHost(host),
        _dio = dio ?? createPanelDio();

  final String host;
  final String username;
  final String password;
  final Dio _dio;

  Future<dynamic> _call(String action, [Map<String, String>? extra]) async {
    try {
      // Force a plain-string response and decode JSON ourselves: many Xtream
      // panels return JSON with a non-JSON Content-Type (e.g. text/html), and
      // Dio would then hand back the raw String instead of a Map/List. That
      // made expiry/account come back empty and catalogs look empty — all
      // silently. decodePanelJson also survives BOMs and PHP warnings printed
      // before the payload.
      final response = await _dio.get(
        '$host/player_api.php',
        queryParameters: {
          'username': username,
          'password': password,
          if (action.isNotEmpty) 'action': action,
          ...?extra,
        },
        options: Options(responseType: ResponseType.plain),
      );
      return decodePanelJson(response.data);
    } on DioException catch (e) {
      throw XtreamSessionException(messageForDioError(e));
    }
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
