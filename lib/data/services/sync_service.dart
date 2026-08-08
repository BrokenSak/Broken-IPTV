import 'dart:convert';

import 'package:dio/dio.dart';

/// Talks to the tiny sync backend (a Cloudflare Worker over D1 — see
/// `sync_worker/` in the repo). The protocol is deliberately two calls:
///
/// * `GET  <endpoint>/v1/blob/<code>` → the stored JSON blob, 404 when the
///   code has never been written;
/// * `PUT  <endpoint>/v1/blob/<code>` → replaces it.
///
/// There are no accounts: the sync code IS the secret, and the server only
/// ever sees a hash of it. Nothing here knows what's inside the blob.
/// The server refused the code outright (HTTP 403).
///
/// Kept apart from every other failure because the cure is different: no
/// amount of retrying or checking the address helps, someone has to enable
/// the code on the service. Telling the user "controlla codice e indirizzo"
/// here would send them to fix something that isn't broken.
class SyncNotAllowedException implements Exception {
  const SyncNotAllowedException(this.reason);

  /// The server's machine-readable reason (`unknown_code`, `sync_disabled`).
  final String reason;

  String get message => syncRefusalMessage(reason);

  @override
  String toString() => 'SyncNotAllowedException($reason)';
}

/// What to show for a refusal. Pure so the wording is testable — it is the
/// only thing the user ever sees about this.
String syncRefusalMessage(String? reason) {
  if (reason == 'sync_disabled') {
    return 'La sincronizzazione non è attiva per questo codice. '
        'Chiedi di accenderla a chi gestisce l\'app.';
  }
  return 'Codice non abilitato sul servizio. '
      'Passalo a chi gestisce l\'app per attivarlo.';
}

/// Reads the `{"error": "..."}` a refusal carries, when it carries one.
String? syncErrorCode(String? body) {
  if (body == null || body.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(body);
    return decoded is Map ? decoded['error']?.toString() : null;
  } catch (_) {
    return null;
  }
}

class SyncService {
  SyncService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              sendTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 20),
            ));

  final Dio _dio;

  static Uri blobUri(String endpoint, String code) {
    final base = endpoint.trim().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base/v1/blob/$code');
  }

  /// The stored blob, or null when this code has nothing yet (first device).
  /// Throws on network/server errors — the caller reports them.
  Future<Map<String, dynamic>?> fetch({
    required String endpoint,
    required String code,
  }) async {
    final resp = await _dio.getUri<String>(
      blobUri(endpoint, code),
      options: Options(
        responseType: ResponseType.plain,
        // 404 is a normal answer ("nothing stored"), not a failure. 403 is
        // handled here rather than as a Dio error so the reason survives.
        validateStatus: (s) => s == 200 || s == 404 || s == 403,
        headers: const {'Cache-Control': 'no-cache'},
      ),
    );
    if (resp.statusCode == 403) {
      throw SyncNotAllowedException(syncErrorCode(resp.data) ?? '');
    }
    if (resp.statusCode == 404) return null;
    final raw = resp.data ?? '';
    if (raw.trim().isEmpty) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map ? decoded.cast<String, dynamic>() : null;
  }

  Future<void> push({
    required String endpoint,
    required String code,
    required Map<String, dynamic> blob,
  }) async {
    final resp = await _dio.putUri<String>(
      blobUri(endpoint, code),
      data: jsonEncode(blob),
      options: Options(
        contentType: Headers.jsonContentType,
        responseType: ResponseType.plain,
        // Same as fetch: let 403 through so its reason can be read, everything
        // else keeps throwing as before.
        validateStatus: (s) => s != null && (s < 400 || s == 403),
      ),
    );
    if (resp.statusCode == 403) {
      throw SyncNotAllowedException(syncErrorCode(resp.data) ?? '');
    }
  }
}
