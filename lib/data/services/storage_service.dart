import 'package:hive_ce_flutter/hive_ce_flutter.dart';

/// Thin wrapper around the local Hive boxes used across the app.
/// Boxes hold plain Map data — no generated type adapters needed.
class StorageService {
  static const profilesBoxName = 'profiles';
  static const prefsBoxName = 'prefs';
  static const favoritesBoxName = 'favorites';
  static const watchProgressBoxName = 'watch_progress';
  static const credentialsBoxName = 'credentials';
  static const catalogCacheBoxName = 'catalog_cache';
  static const downloadsBoxName = 'downloads';
  static const tombstonesBoxName = 'sync_tombstones';

  static late Box<Map> profilesBox;
  static late Box prefsBox;
  static late Box<Map> favoritesBox;
  static late Box<Map> watchProgressBox;

  /// Offline downloads metadata (see DownloadItem). The media files live on the
  /// filesystem; this box only tracks their state/progress/paths.
  static late Box<Map> downloadsBox;

  /// Raw catalog responses (see CatalogCache). Lazy: payloads can be several
  /// MB per profile, so they are read from disk on demand, never kept in RAM.
  static late LazyBox<Map> catalogCacheBox;

  /// When a favourite or a "continua a guardare" entry was deleted, keyed
  /// `fav:<key>` / `prog:<key>` → epoch ms. Without these a removal would be
  /// undone by the first device that still has the item (see [SyncTombstones]).
  static late Box<int> tombstonesBox;

  /// Reliable local store for profile passwords (obfuscated). Kept in Hive
  /// because flutter_secure_storage has proven unreliable across platforms for
  /// this app (Windows backward-compat, and v10 failing to read back on some
  /// Android devices) — see [SecureCredentialsService].
  static late Box<String> credentialsBox;

  /// [testPath] lets tests point Hive at a plain temp directory instead of
  /// going through [Hive.initFlutter], which needs path_provider's platform
  /// channel and isn't available in a widget-test host.
  static Future<void> init({String? testPath}) async {
    if (testPath != null) {
      Hive.init(testPath);
    } else {
      await Hive.initFlutter();
    }
    profilesBox = await Hive.openBox<Map>(profilesBoxName);
    prefsBox = await Hive.openBox(prefsBoxName);
    favoritesBox = await Hive.openBox<Map>(favoritesBoxName);
    watchProgressBox = await Hive.openBox<Map>(watchProgressBoxName);
    credentialsBox = await Hive.openBox<String>(credentialsBoxName);
    catalogCacheBox = await Hive.openLazyBox<Map>(catalogCacheBoxName);
    downloadsBox = await Hive.openBox<Map>(downloadsBoxName);
    tombstonesBox = await Hive.openBox<int>(tombstonesBoxName);
  }
}
