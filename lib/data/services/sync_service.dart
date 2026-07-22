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
        // 404 is a normal answer ("nothing stored"), not a failure.
        validateStatus: (s) => s == 200 || s == 404,
        headers: const {'Cache-Control': 'no-cache'},
      ),
    );
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
    await _dio.putUri<void>(
      blobUri(endpoint, code),
      data: jsonEncode(blob),
      options: Options(
        contentType: Headers.jsonContentType,
        responseType: ResponseType.plain,
      ),
    );
  }
}
