import 'dart:convert';

import 'package:dio/dio.dart';

/// User-Agent sent to panels for API/playlist calls. Many Xtream panels
/// filter out unknown agents (Dart's default is "Dart/x.x (dart:io)") while
/// accepting the ones mainstream IPTV players send; okhttp is the HTTP stack
/// used by most Android IPTV apps, so it is the most widely accepted. This is
/// why a panel could answer the login handshake (expiry) but refuse the
/// catalog actions.
const String kPanelUserAgent = 'okhttp/4.12.0';

/// Dio client for panel calls: player-friendly User-Agent and timeouts sized
/// for big catalogs on slow mobile networks.
Dio createPanelDio({
  Duration connectTimeout = const Duration(seconds: 12),
  Duration receiveTimeout = const Duration(seconds: 40),
}) {
  return Dio(BaseOptions(
    connectTimeout: connectTimeout,
    receiveTimeout: receiveTimeout,
    headers: const {'User-Agent': kPanelUserAgent},
  ));
}

/// Decodes a panel response to JSON regardless of Content-Type or noise.
///
/// Real-world panels return JSON with a text/html Content-Type, with a UTF-8
/// BOM, or with PHP warnings/HTML printed *before* the JSON payload — often
/// only on the catalog actions, which is how a panel can report the expiry
/// fine and still fail on categories. Returns null when no JSON can be
/// extracted at all.
dynamic decodePanelJson(dynamic data) {
  if (data == null) return null;
  if (data is! String) return data; // already decoded by Dio
  var text = data.trim();
  if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) {
    text = text.substring(1).trim();
  }
  if (text.isEmpty) return null;
  try {
    return jsonDecode(text);
  } catch (_) {
    // Fall through and try to extract the JSON payload buried in the noise.
  }
  // A list of objects ("[{"), then an object ("{"), then any list ("[", e.g.
  // an empty catalog "[]"): try the most specific shape first so a stray "["
  // inside a PHP warning doesn't shadow the real payload.
  for (final (open, close) in const [('[{', ']'), ('{', '}'), ('[', ']')]) {
    final start = text.indexOf(open);
    final end = text.lastIndexOf(close);
    if (start < 0 || end <= start) continue;
    try {
      return jsonDecode(text.substring(start, end + 1));
    } catch (_) {}
  }
  return null;
}

/// Returns the response as a List, tolerating panels whose PHP emits a JSON
/// object with numeric keys ({"0": {...}, "1": {...}} — what json_encode does
/// to a non-sequential array) instead of a plain array. Null when the data is
/// neither shape.
List<dynamic>? asPanelList(dynamic data) {
  if (data is List) return data;
  if (data is Map &&
      data.isNotEmpty &&
      data.keys.every((k) => int.tryParse(k.toString()) != null)) {
    return data.values.toList();
  }
  return null;
}
