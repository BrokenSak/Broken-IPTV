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
/// whoever set the app up for them; that person types it in the panel and hooks
/// the device to an **utenza** — the IPTV account itself, with its address, its
/// username and its password.
///
/// So there are two steps, and the split is the point:
///
///  1. `/v1/profile/<device code>` holds a **casellina**, written once, that
///     says which utenza this device belongs to. It is encrypted with the
///     device's own code, which is why registering needs somebody to read it
///     out loud.
///  2. `/v1/account/<utenza id>` holds the playlist, encrypted with the
///     **utenza's** code. That one blob is shared by every device of that
///     person, so correcting a password reaches all of them at once — nobody
///     has to dig their codes up again.
///
/// Either way the server stores bytes it cannot read. The utenza's code is
/// derived by the panel from the admin token (HMAC), never stored: a dump of
/// the database opens nothing, while whoever holds the token opens everything.
/// That trade is what buys step 2.

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

  static Uri profileUri(String endpoint, String code) =>
      _uri(endpoint, '/v1/profile/$code');

  static Uri accountUri(String endpoint, String accountId) =>
      _uri(endpoint, '/v1/account/$accountId');

  static Uri _uri(String endpoint, String path) =>
      Uri.parse('${endpoint.trim().replaceAll(RegExp(r'/+$'), '')}$path');

  /// The playlist waiting for this device, or null when there is none (the
  /// normal case). Never throws: the screen that polls this must not turn a
  /// flaky network into an error message.
  Future<ProvisionedProfile?> fetch({
    required String endpoint,
    required String code,
  }) async {
    try {
      final envelope = await _envelope(profileUri(endpoint, code));
      if (envelope == null) return null;
      final payload = await decryptProvisioning(
        envelope['data']?.toString() ?? '',
        code,
      );
      if (payload == null) return null;
      final writtenAt = (envelope['updatedAt'] as num?)?.toInt() ?? 0;

      final account = normalizeSyncCode(payload['account']?.toString() ?? '');
      final accountId = payload['accountId']?.toString().trim() ?? '';
      if (account != null && accountId.isNotEmpty) {
        return _fromAccount(
          endpoint: endpoint,
          accountId: accountId,
          accountCode: account,
          casellinaAt: writtenAt,
        );
      }

      // Before utenze existed the panel wrote the playlist straight into the
      // device's slot. Still read it, so a device configured back then doesn't
      // stop working the day this app updates.
      return _profileFrom(payload, updatedAt: writtenAt);
    } catch (_) {
      return null;
    }
  }

  /// Step two: the utenza's playlist, shared by all of its devices.
  ///
  /// The date that matters is the **newest** of the two: the account blob moves
  /// when the owner corrects the credentials (that is how a fix reaches
  /// everybody), and the casellina moves when the device is hooked to a
  /// different utenza — whose playlist may well be older than what this device
  /// last applied, and would otherwise be ignored.
  Future<ProvisionedProfile?> _fromAccount({
    required String endpoint,
    required String accountId,
    required String accountCode,
    required int casellinaAt,
  }) async {
    final envelope = await _envelope(accountUri(endpoint, accountId));
    if (envelope == null) return null;
    final payload = await decryptProvisioning(
      envelope['data']?.toString() ?? '',
      accountCode,
    );
    if (payload == null) return null;
    final accountAt = (envelope['updatedAt'] as num?)?.toInt() ?? 0;

    return _profileFrom(
      payload,
      updatedAt: accountAt > casellinaAt ? accountAt : casellinaAt,
      // The utenza's code doubles as the sync code of its devices, so the same
      // person's phone and TV line up on their own — but only when the owner
      // asked for it: the server says so next to the playlist, because the
      // switch can be flipped long after the playlist was written.
      syncCode: (envelope['sync'] as num?)?.toInt() == 1 ? accountCode : null,
    );
  }

  ProvisionedProfile? _profileFrom(
    Map<String, dynamic> payload, {
    required int updatedAt,
    String? syncCode,
  }) {
    final host = payload['host']?.toString().trim() ?? '';
    final username = payload['username']?.toString().trim() ?? '';
    if (host.isEmpty || username.isEmpty) return null;
    final name = payload['name']?.toString().trim() ?? '';
    return ProvisionedProfile(
      name: name.isEmpty ? 'Playlist' : name,
      host: host,
      username: username,
      password: payload['password']?.toString() ?? '',
      updatedAt: updatedAt,
      syncCode: syncCode ??
          normalizeSyncCode(payload['syncCode']?.toString() ?? ''),
    );
  }

  /// A `{data, updatedAt}` envelope from the Worker, or null when there is
  /// nothing to read. 404 (nothing waiting) and 403 (the code isn't in the
  /// panel) are both "no playlist", not failures.
  Future<Map<String, dynamic>?> _envelope(Uri uri) async {
    final resp = await _dio.getUri<String>(
      uri,
      options: Options(
        responseType: ResponseType.plain,
        validateStatus: (s) => s == 200 || s == 404 || s == 403,
        headers: const {'Cache-Control': 'no-cache'},
      ),
    );
    if (resp.statusCode != 200) return null;
    final decoded = jsonDecode(resp.data ?? '');
    return decoded is Map ? decoded.cast<String, dynamic>() : null;
  }
}
