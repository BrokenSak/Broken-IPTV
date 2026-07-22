import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../services/storage_service.dart';
import '../services/sync_merge.dart';
import '../services/sync_tombstones.dart';

/// The Hive side of the sync: turns the local boxes into a [SyncBlob] and
/// writes a merged blob back. All the decision-making lives in
/// `sync_merge.dart` (pure); this file only moves data.
class SyncRepository {
  /// Local state as the sync sees it: every stored entry, plus one tombstone
  /// per thing the user deleted here.
  SyncBlob readLocal() => SyncBlob(
        favorites: _readSection(
          StorageService.favoritesBox.toMap(),
          SyncTombstones.all(SyncTombstones.favorites),
        ),
        progress: _readSection(
          StorageService.watchProgressBox.toMap(),
          SyncTombstones.all(SyncTombstones.progress),
        ),
      );

  static Map<String, SyncEntry> _readSection(
    Map<dynamic, dynamic> box,
    Map<String, int> tombstones,
  ) {
    final out = <String, SyncEntry>{};
    for (final e in box.entries) {
      final value = e.value;
      if (value is! Map) continue;
      final data = <String, dynamic>{
        for (final f in value.entries) f.key.toString(): f.value,
      };
      final at = (data['updatedAt'] as num?)?.toInt() ?? 0;
      data['updatedAt'] = at;
      out[e.key.toString()] = SyncEntry(updatedAt: at, data: data);
    }
    for (final t in tombstones.entries) {
      // A tombstone always wins over a stale row: if both exist, the row was
      // deleted from the box and only a race could leave it behind.
      out[t.key] = SyncEntry.tombstone(t.value);
    }
    return out;
  }

  /// Applies the merge result to the boxes. Only touches what actually
  /// changed, so untouched entries keep their identity in Hive.
  Future<void> applyMerged(SyncBlob merged) async {
    await _applySection(
      StorageService.favoritesBox,
      merged.favorites,
      SyncTombstones.favorites,
    );
    await _applySection(
      StorageService.watchProgressBox,
      merged.progress,
      SyncTombstones.progress,
    );
  }

  static Future<void> _applySection(
    Box<Map> box,
    Map<String, SyncEntry> section,
    String tombstoneSection,
  ) async {
    final liveTombstones = <String>{};
    for (final e in section.entries) {
      if (e.value.deleted) {
        liveTombstones.add(e.key);
        SyncTombstones.mark(tombstoneSection, e.key, atMs: e.value.updatedAt);
        await box.delete(e.key);
      } else {
        SyncTombstones.clear(tombstoneSection, e.key);
        await box.put(e.key, e.value.data!);
      }
    }
    // Tombstones the merge pruned (too old) must go too, or they'd keep
    // deleting an entry that everyone has since forgotten about.
    SyncTombstones.retainOnly(tombstoneSection, liveTombstones);
  }
}
