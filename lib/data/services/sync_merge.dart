// Pure data model + merge rules for the cross-device sync (favourites and
// "continua a guardare"). No Hive, no HTTP: everything here is a plain
// function so it can be unit-tested, which matters because a merge bug
// silently loses the user's data on every device at once.
//
// The synchronised unit is a single JSON blob per sync code:
//   { "v": 1,
//     "favorites": { "vod:12": {...,"updatedAt":1},
//                    "live:3": {"deleted":true,"updatedAt":2} },
//     "progress":  { "vod:12": {...,"updatedAt":3} } }

import 'dart:convert';
import 'dart:math';

const kSyncSchemaVersion = 1;

/// How long a removal is remembered. A tombstone is what stops a deleted
/// favourite from being resurrected by a device that still has it; after this
/// it is pruned so the blob doesn't grow forever. A device offline longer than
/// this can bring an old entry back — acceptable, and the reason it isn't days.
const kSyncTombstoneTtl = Duration(days: 60);

/// Sync codes are generated from an unambiguous alphabet (no O/0, I/1) so they
/// can be read off a screen and typed on a TV remote.
const _kCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const kSyncCodeLength = 12;

/// One entry of a synchronised map: either the item's data, or a tombstone
/// (`data == null`) recording when it was deleted.
class SyncEntry {
  const SyncEntry({required this.updatedAt, this.data});

  /// A removal, remembered until it is pruned (see [kSyncTombstoneTtl]).
  const SyncEntry.tombstone(this.updatedAt) : data = null;

  final int updatedAt;
  final Map<String, dynamic>? data;

  bool get deleted => data == null;

  factory SyncEntry.fromJson(Map<dynamic, dynamic> m) {
    final at = (m['updatedAt'] as num?)?.toInt() ?? 0;
    if (m['deleted'] == true) return SyncEntry.tombstone(at);
    final data = <String, dynamic>{
      for (final e in m.entries) e.key.toString(): e.value,
    };
    data['updatedAt'] = at;
    return SyncEntry(updatedAt: at, data: data);
  }

  Map<String, dynamic> toJson() =>
      deleted ? {'deleted': true, 'updatedAt': updatedAt} : data!;
}

/// The whole synchronised state: the `favorites` and `watch_progress` Hive
/// boxes, keyed exactly as they are locally.
class SyncBlob {
  const SyncBlob({required this.favorites, required this.progress});

  final Map<String, SyncEntry> favorites;
  final Map<String, SyncEntry> progress;

  static const empty = SyncBlob(favorites: {}, progress: {});

  bool get isEmpty => favorites.isEmpty && progress.isEmpty;

  factory SyncBlob.fromJson(Map<dynamic, dynamic> json) => SyncBlob(
        favorites: _sectionFromJson(json['favorites']),
        progress: _sectionFromJson(json['progress']),
      );

  Map<String, dynamic> toJson() => {
        'v': kSyncSchemaVersion,
        'favorites': {for (final e in favorites.entries) e.key: e.value.toJson()},
        'progress': {for (final e in progress.entries) e.key: e.value.toJson()},
      };

  static Map<String, SyncEntry> _sectionFromJson(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, SyncEntry>{};
    for (final e in raw.entries) {
      final v = e.value;
      if (v is Map) out[e.key.toString()] = SyncEntry.fromJson(v);
    }
    return out;
  }
}

/// Merges two blobs entry by entry: the most recently touched version of each
/// key wins, a removal being just another version. Both devices run this on
/// the same pair of blobs, so the result must not depend on which side is
/// "local" — see the tie-break below.
SyncBlob mergeSyncBlobs(
  SyncBlob local,
  SyncBlob remote, {
  required int nowMs,
  Duration tombstoneTtl = kSyncTombstoneTtl,
}) {
  return SyncBlob(
    favorites: _mergeSection(local.favorites, remote.favorites, nowMs, tombstoneTtl),
    progress: _mergeSection(local.progress, remote.progress, nowMs, tombstoneTtl),
  );
}

Map<String, SyncEntry> _mergeSection(
  Map<String, SyncEntry> a,
  Map<String, SyncEntry> b,
  int nowMs,
  Duration tombstoneTtl,
) {
  final cutoff = nowMs - tombstoneTtl.inMilliseconds;
  final out = <String, SyncEntry>{};
  for (final key in <String>{...a.keys, ...b.keys}) {
    final x = a[key];
    final y = b[key];
    final SyncEntry winner;
    if (x == null) {
      winner = y!;
    } else if (y == null) {
      winner = x;
    } else if (x.updatedAt != y.updatedAt) {
      winner = x.updatedAt > y.updatedAt ? x : y;
    } else if (x.deleted != y.deleted) {
      // Same instant, one is a removal: the removal wins, so a delete is never
      // undone by a write stamped in the same millisecond.
      winner = x.deleted ? x : y;
    } else {
      // Same instant, both present: pick by content, NOT by side. Choosing
      // "the local one" would make each device keep its own copy and push it
      // over the other's forever.
      winner = _canonicalJson(x.toJson()).compareTo(_canonicalJson(y.toJson())) <= 0 ? x : y;
    }
    if (winner.deleted && winner.updatedAt < cutoff) continue; // pruned
    out[key] = winner;
  }
  return out;
}

/// Short digest of a blob's content, used to answer "is there anything new to
/// upload?" without comparing the whole thing (and to skip the upload
/// entirely when nothing changed — free-tier writes are the scarce resource).
/// Key order never affects it.
String syncFingerprint(SyncBlob blob) => _fnv1a64(_canonicalJson(blob.toJson()));

/// JSON with map keys sorted, so two equal blobs always produce one string.
String _canonicalJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((k) => k.toString()).toList()..sort();
    final parts = keys.map((k) => '${jsonEncode(k)}:${_canonicalJson(value[k])}');
    return '{${parts.join(',')}}';
  }
  if (value is List) return '[${value.map(_canonicalJson).join(',')}]';
  return jsonEncode(value);
}

String _fnv1a64(String s) {
  // 64-bit FNV-1a: no crypto dependency needed — this only has to detect
  // change, not resist an attacker.
  var hash = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  for (final byte in utf8.encode(s)) {
    hash ^= byte;
    hash = hash * prime; // wraps at 64 bits, which is what we want
  }
  return hash.toUnsigned(64).toRadixString(16).padLeft(16, '0');
}

/// A fresh sync code. This is the only secret protecting the data, so it comes
/// from [Random.secure] (the [random] parameter is for tests).
String generateSyncCode({Random? random}) {
  final rnd = random ?? Random.secure();
  return List.generate(
    kSyncCodeLength,
    (_) => _kCodeAlphabet[rnd.nextInt(_kCodeAlphabet.length)],
  ).join();
}

/// Accepts what a human might type — lowercase, spaces, the dashes we show —
/// and returns the canonical code, or null when it isn't one.
String? normalizeSyncCode(String raw) {
  final cleaned = raw.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
  if (cleaned.length != kSyncCodeLength) return null;
  return cleaned;
}

/// `ABCD-EFGH-JKLM` — only for display; storage always uses the bare code.
String formatSyncCode(String code) {
  final groups = <String>[];
  for (var i = 0; i < code.length; i += 4) {
    groups.add(code.substring(i, min(i + 4, code.length)));
  }
  return groups.join('-');
}
