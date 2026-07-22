import 'storage_service.dart';

/// Records *when* something was deleted, so the deletion can travel between
/// devices. Deleting a row from a box only removes it here: without a
/// tombstone the next sync would see the other device's copy as "an entry we
/// don't have yet" and put it straight back.
///
/// Writes are fire-and-forget on purpose — the caller already awaited the box
/// write that matters, and Hive applies values to memory synchronously.
class SyncTombstones {
  static const favorites = 'fav';
  static const progress = 'prog';

  static String _key(String section, String key) => '$section:$key';

  static void mark(String section, String key, {int? atMs}) {
    StorageService.tombstonesBox
        .put(_key(section, key), atMs ?? DateTime.now().millisecondsSinceEpoch);
  }

  /// The item is back (re-added): drop its tombstone or the next merge would
  /// see a removal newer than nothing and delete it again.
  static void clear(String section, String key) {
    StorageService.tombstonesBox.delete(_key(section, key));
  }

  /// Deleted keys of one section with their timestamps.
  static Map<String, int> all(String section) {
    final prefix = '$section:';
    final out = <String, int>{};
    for (final k in StorageService.tombstonesBox.keys) {
      final key = k.toString();
      if (!key.startsWith(prefix)) continue;
      final at = StorageService.tombstonesBox.get(key);
      if (at != null) out[key.substring(prefix.length)] = at;
    }
    return out;
  }

  /// Drops tombstones of [section] whose key is not in [keep] (they aged out
  /// of the merged blob).
  static void retainOnly(String section, Set<String> keep) {
    final prefix = '$section:';
    final doomed = <String>[];
    for (final k in StorageService.tombstonesBox.keys) {
      final key = k.toString();
      if (key.startsWith(prefix) && !keep.contains(key.substring(prefix.length))) {
        doomed.add(key);
      }
    }
    StorageService.tombstonesBox.deleteAll(doomed);
  }
}
