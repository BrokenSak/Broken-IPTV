import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';

import 'storage_service.dart';
import 'sync_merge.dart';

/// Remote setup: the owner fills a device's playlist in from the admin panel,
/// so whoever installed the app doesn't have to type a host, a username and a
/// password read out over the phone.
///
/// The device shows a **code** on the very first screen; the person reads it to
/// whoever set the app up for them; that person types it in the panel and sends
/// the playlist down. What travels is encrypted **with the code itself**, so
/// the server stores bytes it cannot read — the same property the sync blob
/// already had, where the code is the only secret and the database only ever
/// sees its hash.

/// The device's own code: its identity in the panel, and (when the owner turns
/// sync on) the sync secret too.
///
/// One code per installation, not two: a device that already had a sync code
/// keeps it, otherwise a device that had been syncing for months would suddenly
/// start showing a different code from the one its data lives under.
class DeviceCode {
  static const _key = 'device_code';
  static const _syncKey = 'sync_code';

  /// Reads it, creating it the first time. Safe to call on every build.
  static String read() {
    final prefs = StorageService.prefsBox;
    final existing = (prefs.get(_key) as String?)?.trim();
    if (existing != null && existing.length == kSyncCodeLength) return existing;

    final fromSync = (prefs.get(_syncKey) as String?)?.trim();
    final code = (fromSync != null && fromSync.length == kSyncCodeLength)
        ? fromSync
        : generateSyncCode();
    prefs.put(_key, code);
    return code;
  }

  /// `ABCD-EFGH-JKLM` — how the code is shown and how it's read out loud.
  static String grouped(String code) {
    final chunks = <String>[];
    for (var i = 0; i < code.length; i += 4) {
      chunks.add(code.substring(i, i + 4 > code.length ? code.length : i + 4));
    }
    return chunks.join('-');
  }
}

/// What the panel sent down for this device.
class ProvisionedProfile {
  const ProvisionedProfile({
    required this.host,
    required this.username,
    required this.password,
    required this.updatedAt,
    this.name = 'Playlist',
    this.syncCode,
  });

  /// What the playlist is called in the app. The panel can set it; when it
  /// doesn't, "Playlist" is a better answer than an empty row.
  final String name;

  final String host;
  final String username;
  final String password;

  /// When the panel wrote it — the device applies it only when it's newer than
  /// what it applied last, so a corrected playlist reaches every device but
  /// the same one isn't re-applied at every launch.
  final int updatedAt;

  /// Set when the owner puts several devices of the same person together: the
  /// device adopts it as its sync code, so nobody has to type a code twice.
  final String? syncCode;
}

/// Whether [remoteUpdatedAt] is worth applying over what was applied before.
///
/// Pure, because getting it wrong is silent in both directions: too eager and
/// the app overwrites a playlist the user fixed by hand at every launch; too
/// lazy and a corrected panel never arrives.
bool shouldApplyProvisioned({
  required int remoteUpdatedAt,
  required int? appliedAt,
}) =>
    remoteUpdatedAt > 0 && (appliedAt == null || remoteUpdatedAt > appliedAt);

/// AES-GCM with the key derived from the code: `SHA-256("broken-iptv-
/// provision:" + code)`. The panel does the same in the browser (WebCrypto).
///
/// No stretching on purpose: the code is 12 characters of a 32-symbol alphabet
/// (~60 bits) drawn from a secure generator, so an attacker who can't guess it
/// gains nothing from a slow KDF, and a Firestick doesn't spend a second of
/// CPU on every launch.
Future<Map<String, dynamic>?> decryptProvisioning(
  String base64Payload,
  String code,
) async {
  try {
    final joined = base64Decode(base64Payload.trim());
    // 12-byte nonce, then ciphertext, then the 16-byte GCM tag.
    if (joined.length < 12 + 16 + 1) return null;
    final nonce = joined.sublist(0, 12);
    final body = joined.sublist(12);
    final cipherText = body.sublist(0, body.length - 16);
    final mac = Mac(body.sublist(body.length - 16));

    final keyBytes =
        await Sha256().hash(utf8.encode('broken-iptv-provision:$code'));
    final algorithm = AesGcm.with256bits();
    final clear = await algorithm.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: mac),
      secretKey: SecretKey(keyBytes.bytes),
    );
    final decoded = jsonDecode(utf8.decode(clear));
    return decoded is Map ? decoded.cast<String, dynamic>() : null;
  } catch (_) {
    // A wrong code, a truncated blob or garbage all mean the same thing here:
    // there is nothing to apply. Never throws — this runs on a startup path.
    return null;
  }
}

class ProvisioningService {
  ProvisioningService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 15),
            ));

  final Dio _dio;

  static Uri profileUri(String endpoint, String code) {
    final base = endpoint.trim().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base/v1/profile/$code');
  }

  /// The playlist waiting for this device, or null when there is none (the
  /// normal case). Never throws: the screen that polls this must not turn a
  /// flaky network into an error message.
  Future<ProvisionedProfile?> fetch({
    required String endpoint,
    required String code,
  }) async {
    try {
      final resp = await _dio.getUri<String>(
        profileUri(endpoint, code),
        options: Options(
          responseType: ResponseType.plain,
          // 404 (nothing waiting) and 403 (code not in the panel) are both
          // "no playlist", not failures.
          validateStatus: (s) => s == 200 || s == 404 || s == 403,
          headers: const {'Cache-Control': 'no-cache'},
        ),
      );
      if (resp.statusCode != 200) return null;
      final envelope = jsonDecode(resp.data ?? '');
      if (envelope is! Map) return null;
      final payload = await decryptProvisioning(
        envelope['data']?.toString() ?? '',
        code,
      );
      if (payload == null) return null;

      final host = payload['host']?.toString().trim() ?? '';
      final username = payload['username']?.toString().trim() ?? '';
      if (host.isEmpty || username.isEmpty) return null;

      final syncCode = normalizeSyncCode(payload['syncCode']?.toString() ?? '');
      final name = payload['name']?.toString().trim() ?? '';
      return ProvisionedProfile(
        name: name.isEmpty ? 'Playlist' : name,
        host: host,
        username: username,
        password: payload['password']?.toString() ?? '',
        updatedAt: (envelope['updatedAt'] as num?)?.toInt() ?? 0,
        syncCode: syncCode,
      );
    } catch (_) {
      return null;
    }
  }
}
