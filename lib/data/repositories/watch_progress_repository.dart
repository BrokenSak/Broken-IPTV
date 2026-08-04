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

  /// One entry per series — the most recently played episode — most recent
  /// first. A series qualifies when *any* of its episodes has real progress.
  ///
  /// ⚠️ The "any episode" part matters. The filter used to be on the latest
  /// entry alone (`positionMs > 5000`), which meant that finishing an episode
  /// removed the whole series: the auto-advance opens the next one, closing the
  /// player records it at ~0s, and that fresh near-zero entry — the newest —
  /// failed the filter. Seven episodes of Yellowstone watched and the series
  /// was simply gone from "Continua a guardare". Pointing at the next episode
  /// at 0:00 is exactly right; hiding the series is not.
  List<WatchProgress> continueSeries() {
    final bySeries = <String, WatchProgress>{};
    final everStarted = <String>{};
    for (final p in getAll()) {
      if (p.kind != WatchKind.series || p.seriesId == null) continue;
      if (p.positionMs > 5000) everStarted.add(p.seriesId!);
      final existing = bySeries[p.seriesId];
      if (existing == null || p.updatedAt > existing.updatedAt) {
        bySeries[p.seriesId!] = p;
      }
    }
    final list = bySeries.values
        .where((p) => everStarted.contains(p.seriesId))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }
}
