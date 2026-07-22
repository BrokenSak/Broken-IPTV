import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:broken_iptv/data/models/favorite_item.dart';
import 'package:broken_iptv/data/models/watch_progress.dart';
import 'package:broken_iptv/data/repositories/favorites_repository.dart';
import 'package:broken_iptv/data/repositories/sync_repository.dart';
import 'package:broken_iptv/data/repositories/watch_progress_repository.dart';
import 'package:broken_iptv/data/services/storage_service.dart';
import 'package:broken_iptv/data/services/sync_merge.dart';

/// Fixed clock, so pruning never depends on the day the suite runs.
const _now = 1800000000000;

/// Timestamps must sit near [_now]: a tombstone far in the past is legitimately
/// pruned, which is exactly what the first version of these tests tripped on.
int _ago(Duration d) => _now - d.inMilliseconds;

SyncEntry _entry(int at, {String name = 'x'}) =>
    SyncEntry(updatedAt: at, data: {'name': name, 'updatedAt': at});

/// A real favourite row (the boxes are read back through FavoriteItem, which
/// needs `type`/`id`).
SyncEntry _favEntry(FavoriteType type, String id, String name, int at) => SyncEntry(
      updatedAt: at,
      data: FavoriteItem(type: type, id: id, name: name, updatedAt: at).toMap(),
    );

SyncBlob _favs(Map<String, SyncEntry> favorites) =>
    SyncBlob(favorites: favorites, progress: const {});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('merge', () {
    test('takes the union when the two sides know different things', () {
      final merged = mergeSyncBlobs(
        _favs({'vod:1': _entry(_ago(const Duration(hours: 2)))}),
        _favs({'vod:2': _entry(_ago(const Duration(hours: 1)))}),
        nowMs: _now,
      );
      expect(merged.favorites.keys, unorderedEquals(['vod:1', 'vod:2']));
    });

    test('the most recent version of an entry wins, from either side', () {
      final older = _favs({'vod:1': _entry(_ago(const Duration(days: 2)), name: 'vecchio')});
      final newer = _favs({'vod:1': _entry(_ago(const Duration(days: 1)), name: 'nuovo')});

      expect(mergeSyncBlobs(older, newer, nowMs: _now).favorites['vod:1']!.data!['name'],
          'nuovo');
      expect(mergeSyncBlobs(newer, older, nowMs: _now).favorites['vod:1']!.data!['name'],
          'nuovo');
    });

    test('a removal propagates instead of being undone by the other device', () {
      // The classic failure: device A deletes, device B still has the item —
      // without tombstones B would simply put it back.
      final removed = _favs({'vod:1': SyncEntry.tombstone(_ago(const Duration(hours: 1)))});
      final stillThere = _favs({'vod:1': _entry(_ago(const Duration(days: 3)))});

      expect(mergeSyncBlobs(removed, stillThere, nowMs: _now).favorites['vod:1']!.deleted,
          isTrue);
      expect(mergeSyncBlobs(stillThere, removed, nowMs: _now).favorites['vod:1']!.deleted,
          isTrue);
    });

    test('re-adding after a removal wins over the older tombstone', () {
      final merged = mergeSyncBlobs(
        _favs({'vod:1': SyncEntry.tombstone(_ago(const Duration(days: 2)))}),
        _favs({'vod:1': _entry(_ago(const Duration(days: 1)))}),
        nowMs: _now,
      );
      expect(merged.favorites['vod:1']!.deleted, isFalse);
    });

    test('same timestamp: the removal wins', () {
      final at = _ago(const Duration(hours: 5));
      final merged = mergeSyncBlobs(
        _favs({'vod:1': SyncEntry.tombstone(at)}),
        _favs({'vod:1': _entry(at)}),
        nowMs: _now,
      );
      expect(merged.favorites['vod:1']!.deleted, isTrue);
    });

    test('same timestamp, both present: both devices pick the SAME winner', () {
      // Tie-break by content, not by side: picking "the local one" would make
      // the two devices push over each other forever.
      final at = _ago(const Duration(hours: 5));
      final a = _favs({'vod:1': _entry(at, name: 'alfa')});
      final b = _favs({'vod:1': _entry(at, name: 'beta')});

      expect(syncFingerprint(mergeSyncBlobs(a, b, nowMs: _now)),
          syncFingerprint(mergeSyncBlobs(b, a, nowMs: _now)));
    });

    test('old tombstones are pruned so the blob stops growing', () {
      final merged = mergeSyncBlobs(
        _favs({'vod:1': SyncEntry.tombstone(_ago(const Duration(days: 90)))}),
        SyncBlob.empty,
        nowMs: _now,
      );
      expect(merged.favorites, isEmpty);
    });

    test('a fresh tombstone is kept', () {
      final merged = mergeSyncBlobs(
        _favs({'vod:1': SyncEntry.tombstone(_ago(const Duration(days: 1)))}),
        SyncBlob.empty,
        nowMs: _now,
      );
      expect(merged.favorites['vod:1']!.deleted, isTrue);
    });

    test('progress is merged with the same rules as favourites', () {
      final merged = mergeSyncBlobs(
        SyncBlob(favorites: const {}, progress: {'vod:9': _entry(_ago(const Duration(days: 2)))}),
        SyncBlob(favorites: const {}, progress: {'vod:9': _entry(_ago(const Duration(minutes: 1)))}),
        nowMs: _now,
      );
      expect(merged.progress['vod:9']!.updatedAt, _ago(const Duration(minutes: 1)));
    });

    test('merging is stable: a second pass changes nothing', () {
      final a = _favs({
        'vod:1': _entry(_ago(const Duration(days: 2))),
        'vod:2': SyncEntry.tombstone(_ago(const Duration(days: 1))),
      });
      final b = _favs({
        'vod:2': _entry(_ago(const Duration(days: 3))),
        'vod:3': _entry(_ago(const Duration(hours: 1))),
      });

      final once = mergeSyncBlobs(a, b, nowMs: _now);
      final twice = mergeSyncBlobs(once, once, nowMs: _now);
      expect(syncFingerprint(twice), syncFingerprint(once));
      expect(once.favorites['vod:2']!.deleted, isTrue);
    });
  });

  group('fingerprint', () {
    test('ignores key order but notices content', () {
      final one = _favs({'a': _entry(1), 'b': _entry(2)});
      final other = _favs({'b': _entry(2), 'a': _entry(1)});
      expect(syncFingerprint(one), syncFingerprint(other));

      expect(syncFingerprint(_favs({'a': _entry(1)})),
          isNot(syncFingerprint(_favs({'a': _entry(2)}))));
    });

    test('an empty blob has a stable fingerprint', () {
      expect(syncFingerprint(SyncBlob.empty), syncFingerprint(SyncBlob.empty));
    });
  });

  group('json', () {
    test('round-trips entries and tombstones', () {
      final blob = SyncBlob(
        favorites: {
          'vod:1': _entry(_now, name: 'film'),
          'live:2': SyncEntry.tombstone(_now),
        },
        progress: {'vod:1': _entry(_now)},
      );
      final back = SyncBlob.fromJson(blob.toJson());
      expect(syncFingerprint(back), syncFingerprint(blob));
      expect(back.favorites['live:2']!.deleted, isTrue);
      expect(back.favorites['vod:1']!.data!['name'], 'film');
    });

    test('garbage from the server never throws', () {
      expect(SyncBlob.fromJson({'favorites': 'nope', 'progress': 42}).isEmpty, isTrue);
      expect(SyncBlob.fromJson(const {}).isEmpty, isTrue);
    });
  });

  group('codes', () {
    test('generated codes are 12 unambiguous characters', () {
      final code = generateSyncCode(random: Random(1));
      expect(code.length, kSyncCodeLength);
      expect(RegExp(r'^[A-Z0-9]+$').hasMatch(code), isTrue);
      // No 0/O/1/I: they get mistyped off a TV screen.
      expect(code, isNot(matches(RegExp('[01IO]'))));
    });

    test('accepts what a human types, rejects the wrong length', () {
      expect(normalizeSyncCode('abcd-efgh-jklm'), 'ABCDEFGHJKLM');
      expect(normalizeSyncCode(' ABCD EFGH JKLM '), 'ABCDEFGHJKLM');
      expect(normalizeSyncCode('ABCD-EFGH'), isNull);
      expect(normalizeSyncCode(''), isNull);
    });

    test('display grouping round-trips', () {
      expect(formatSyncCode('ABCDEFGHJKLM'), 'ABCD-EFGH-JKLM');
      expect(normalizeSyncCode(formatSyncCode('ABCDEFGHJKLM')), 'ABCDEFGHJKLM');
    });

    test('the field groups the code while it is still being typed', () {
      String typed(String s) => syncCodeAsTyped(s);

      expect(typed(''), '');
      expect(typed('ab'), 'AB');
      // The separator appears on the FOURTH character, not the fifth: waiting
      // for the fifth hides that it is automatic, and people type their own.
      expect(typed('abcd'), 'ABCD-');
      expect(typed('abcde'), 'ABCD-E');
      expect(typed('abcdefgh'), 'ABCD-EFGH-');
      // Complete: no dangling separator, there is nothing left to type.
      expect(typed('abcdefghjklm'), 'ABCD-EFGH-JKLM');
      // Pasting an already-grouped code must not double the dashes.
      expect(typed('ABCD-EFGH-JKLM'), 'ABCD-EFGH-JKLM');
      // Junk and overflow are dropped rather than rejected.
      expect(typed('ab!c d/e'), 'ABCD-E');
      expect(typed('ABCDEFGHJKLMNOPQ'), 'ABCD-EFGH-JKLM');
    });

    test('deleting can get past the automatic separator', () {
      // Without this the field is a trap: backspace removes the dash, the
      // formatter puts it straight back, and the 4th character is unreachable.
      expect(syncCodeAsTyped('ABCD', deleting: true), 'ABCD');
      expect(syncCodeAsTyped('ABC', deleting: true), 'ABC');
      expect(syncCodeAsTyped('ABCD-EFGH', deleting: true), 'ABCD-EFGH');
      // Typing again re-adds it.
      expect(syncCodeAsTyped('ABCD'), 'ABCD-');
    });
  });

  group('local store', () {
    setUpAll(() async {
      final dir = Directory.systemTemp.createTempSync('broken_iptv_sync_test');
      await StorageService.init(testPath: dir.path);
    });

    setUp(() async {
      await StorageService.favoritesBox.clear();
      await StorageService.watchProgressBox.clear();
      await StorageService.tombstonesBox.clear();
    });

    test('removing a favourite leaves a tombstone in the local blob', () async {
      final repo = FavoritesRepository();
      await repo.add(const FavoriteItem(type: FavoriteType.vod, id: '1', name: 'Film'));

      var local = SyncRepository().readLocal();
      expect(local.favorites['vod:1']!.deleted, isFalse);
      // add() stamps the entry, otherwise it would lose every conflict.
      expect(local.favorites['vod:1']!.updatedAt, greaterThan(0));

      await repo.remove(FavoriteType.vod, '1');
      local = SyncRepository().readLocal();
      expect(local.favorites['vod:1']!.deleted, isTrue);
      expect(repo.getAll(), isEmpty);
    });

    test('re-adding clears the tombstone', () async {
      final repo = FavoritesRepository();
      const item = FavoriteItem(type: FavoriteType.live, id: '7', name: 'Rai 1');
      await repo.add(item);
      await repo.remove(FavoriteType.live, '7');
      await repo.add(item);

      expect(SyncRepository().readLocal().favorites['live:7']!.deleted, isFalse);
    });

    test('applying a merged blob writes entries and honours removals', () async {
      final favs = FavoritesRepository();
      final progress = WatchProgressRepository();
      await favs.add(const FavoriteItem(type: FavoriteType.vod, id: 'keep', name: 'Resta'));
      await progress.save(const WatchProgress(
        kind: WatchKind.vod,
        vodId: 'old',
        seriesId: null,
        episodeId: null,
        episodeLabel: null,
        name: 'Vecchio',
        imageUrl: null,
        url: 'http://x/1',
        positionMs: 60000,
        durationMs: 600000,
        updatedAt: _now,
      ));

      await SyncRepository().applyMerged(SyncBlob(
        favorites: {
          'vod:keep': _favEntry(FavoriteType.vod, 'keep', 'Resta', _now),
          'vod:new': _favEntry(FavoriteType.vod, 'new', 'Arrivato dal cloud', _now),
        },
        // The other device removed this one.
        progress: {'vod:old': SyncEntry.tombstone(_now)},
      ));

      expect(favs.getAll().map((f) => f.id), unorderedEquals(['keep', 'new']));
      expect(progress.getAll(), isEmpty);
      // The removal must survive locally, or the next sync would resurrect it.
      expect(SyncRepository().readLocal().progress['vod:old']!.deleted, isTrue);
    });

    test('a pruned tombstone is dropped locally too', () async {
      await FavoritesRepository().remove(FavoriteType.vod, 'gone');
      expect(SyncRepository().readLocal().favorites.containsKey('vod:gone'), isTrue);

      // The merge pruned it (too old): applying must forget it here as well.
      await SyncRepository().applyMerged(SyncBlob.empty);
      expect(SyncRepository().readLocal().favorites, isEmpty);
    });

    test('local changes move the fingerprint (the "anything to upload?" test)', () async {
      final before = syncFingerprint(SyncRepository().readLocal());
      await FavoritesRepository()
          .add(const FavoriteItem(type: FavoriteType.series, id: '3', name: 'Serie'));
      expect(syncFingerprint(SyncRepository().readLocal()), isNot(before));
    });

    test('a full round trip between two devices converges', () async {
      // Device A's state, as it would leave this machine.
      final favs = FavoritesRepository();
      await favs.add(const FavoriteItem(type: FavoriteType.vod, id: 'a', name: 'Solo su A'));
      final deviceA = SyncRepository().readLocal();

      // What device B had pushed earlier.
      final deviceB = SyncBlob(
        favorites: {'vod:b': _favEntry(FavoriteType.vod, 'b', 'Solo su B', _now)},
        progress: const {},
      );

      final merged = mergeSyncBlobs(
        deviceA,
        deviceB,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
      await SyncRepository().applyMerged(merged);

      expect(favs.getAll().map((f) => f.id), unorderedEquals(['a', 'b']));
      // Applying the merge leaves nothing further to push.
      expect(syncFingerprint(SyncRepository().readLocal()), syncFingerprint(merged));
    });
  });
}
