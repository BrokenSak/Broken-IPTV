import '../models/favorite_item.dart';
import '../services/storage_service.dart';
import '../services/sync_tombstones.dart';

class FavoritesRepository {
  List<FavoriteItem> getAll() {
    return StorageService.favoritesBox.values
        .map(FavoriteItem.fromMap)
        .toList(growable: false);
  }

  bool isFavorite(FavoriteType type, String id) {
    return StorageService.favoritesBox.containsKey('${type.name}:$id');
  }

  /// Stamped with "now" and any pending tombstone dropped: both are what let
  /// the cross-device sync tell this add apart from an older removal.
  Future<void> add(FavoriteItem item) {
    SyncTombstones.clear(SyncTombstones.favorites, item.key);
    final stamped = item.stamped(DateTime.now().millisecondsSinceEpoch);
    return StorageService.favoritesBox.put(item.key, stamped.toMap());
  }

  Future<void> remove(FavoriteType type, String id) {
    final key = '${type.name}:$id';
    SyncTombstones.mark(SyncTombstones.favorites, key);
    return StorageService.favoritesBox.delete(key);
  }

  Future<void> toggle(FavoriteItem item) async {
    if (isFavorite(item.type, item.id)) {
      await remove(item.type, item.id);
    } else {
      await add(item);
    }
  }
}
