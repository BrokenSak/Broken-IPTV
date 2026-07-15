import 'package:dio/dio.dart';

import 'dio_error_utils.dart';
import 'panel_http.dart';

class XtreamAuthResult {
  const XtreamAuthResult({
    required this.success,
    required this.message,
    this.expiresAt,
    this.maxConnections,
  });

  final bool success;
  final String message;
  final DateTime? expiresAt;
  final int? maxConnections;
}

/// Talks to the Xtream Codes `player_api.php` endpoint.
/// JSON coming back from real-world Xtream panels is notoriously
/// inconsistent (numbers as strings, booleans as "0"/"1"), so every
/// field is parsed defensively.
class XtreamApiService {
  XtreamApiService({Dio? dio})
      : _dio = dio ??
            createPanelDio(receiveTimeout: const Duration(seconds: 20));

  final Dio _dio;

  static String normalizeHost(String host) {
    var h = host.trim();
    if (!h.startsWith('http://') && !h.startsWith('https://')) {
      h = 'http://$h';
    }
    while (h.endsWith('/')) {
      h = h.substring(0, h.length - 1);
    }
    return h;
  }

  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  Future<XtreamAuthResult> testConnection({
    required String host,
    required String username,
    required String password,
  }) async {
    final normalizedHost = normalizeHost(host);
    final url = '$normalizedHost/player_api.php';

    try {
      // Decode JSON ourselves (see XtreamSession._call): panels often send
      // JSON with a non-JSON Content-Type, which would otherwise arrive as a
      // raw String and be misread as "invalid response".
      final response = await _dio.get(
        url,
        queryParameters: {'username': username, 'password': password},
        options: Options(responseType: ResponseType.plain),
      );

      final data = decodePanelJson(response.data);
      if (data is! Map) {
        return const XtreamAuthResult(
          success: false,
          message: 'Risposta del server non valida.',
        );
      }

      final userInfo = data['user_info'];
      if (userInfo is! Map) {
        return const XtreamAuthResult(
          success: false,
          message: 'Credenziali non valide o server non Xtream Codes.',
        );
      }

      final auth = _asInt(userInfo['auth']) ?? 0;
      if (auth != 1) {
        return const XtreamAuthResult(
          success: false,
          message: 'Username o password errati.',
        );
      }

      final expTimestamp = _asInt(userInfo['exp_date']);
      final expiresAt = expTimestamp != null
          ? DateTime.fromMillisecondsSinceEpoch(expTimestamp * 1000)
          : null;
      final maxConnections = _asInt(userInfo['max_connections']);

      return XtreamAuthResult(
        success: true,
        message: 'Connessione riuscita.',
        expiresAt: expiresAt,
        maxConnections: maxConnections,
      );
    } on DioException catch (e) {
      return XtreamAuthResult(success: false, message: messageForDioError(e));
    } catch (_) {
      return const XtreamAuthResult(
        success: false,
        message: 'Errore imprevisto durante il test di connessione.',
      );
    }
  }
}
