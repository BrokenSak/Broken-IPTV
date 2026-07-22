import '../models/watch_progress.dart';
import '../services/storage_service.dart';
import '../services/sync_tombstones.dart';

class WatchProgressRepository {
  List<WatchProgress> getAll() {
    return StorageService.watchProgressBox.values
        .map(WatchProgress.fromMap)
        .toList(growable: false);
  }

  WatchProgress? get(String key) {
    final m = StorageService.watchProgressBox.get(key);
    return m == null ? null : WatchProgress.fromMap(m);
  }

  Future<void> save(WatchProgress p) {
    // Watching something again undoes a previous "rimuovi da Continua".
    SyncTombstones.clear(SyncTombstones.progress, p.key);
    return StorageService.watchProgressBox.put(p.key, p.toMap());
  }

  Future<void> remove(String key) {
    SyncTombstones.mark(SyncTombstones.progress, key);
    return StorageService.watchProgressBox.delete(key);
  }

  /// Movies in progress (not finished), most recent first.
  List<WatchProgress> continueMovies() {
    final list = getAll()
        .where((p) => p.kind == WatchKind.vod && !p.finished && p.positionMs > 5000)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  /// One entry per series (latest watched episode), not-finished-or-latest,
  /// most recent first.
  List<WatchProgress> continueSeries() {
    final bySeries = <String, WatchProgress>{};
    for (final p in getAll()) {
      if (p.kind != WatchKind.series) continue;
      final existing = bySeries[p.seriesId];
      if (existing == null || p.updatedAt > existing.updatedAt) {
        bySeries[p.seriesId!] = p;
      }
    }
    final list = bySeries.values.where((p) => p.positionMs > 5000).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }
}
