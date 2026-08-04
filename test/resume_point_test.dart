// Regression tests for "non riprende dal punto giusto, riprende sempre
// dall'inizio". All three rules were found by dumping the user's real
// watch_progress box, which contained five entries stamped at ~0s — one of
// them the newest episode of a series they were seven episodes into.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:broken_iptv/data/models/watch_progress.dart';
import 'package:broken_iptv/data/repositories/watch_progress_repository.dart';
import 'package:broken_iptv/data/services/storage_service.dart';

WatchProgress _vod(String id, {required int pos, int dur = 6000000, int at = 1000}) =>
    WatchProgress(
      kind: WatchKind.vod,
      vodId: id,
      seriesId: null,
      episodeId: null,
      episodeLabel: null,
      name: 'Film $id',
      imageUrl: null,
      url: 'http://x/$id.mp4',
      positionMs: pos,
      durationMs: dur,
      updatedAt: at,
    );

WatchProgress _ep(String series, String ep,
        {required int pos, int dur = 2400000, required int at}) =>
    WatchProgress(
      kind: WatchKind.series,
      vodId: null,
      seriesId: series,
      episodeId: ep,
      episodeLabel: 'Ep $ep',
      name: 'Ep $ep',
      imageUrl: null,
      url: 'http://x/$ep.mkv',
      positionMs: pos,
      durationMs: dur,
      updatedAt: at,
    );

void main() {
  setUpAll(() async {
    final dir = Directory.systemTemp.createTempSync('broken_iptv_resume_test');
    await StorageService.init(testPath: dir.path);
  });

  setUp(() async {
    await StorageService.watchProgressBox.clear();
  });

  group('shouldWriteProgress: a fresh open must not erase where you were', () {
    test('~0s does NOT overwrite a real resume point', () {
      // Open a film you were 1h20m into, back out before playback gets there:
      // dispose() forces a save at ~0. This is the whole bug.
      expect(
        shouldWriteProgress(positionMs: 300, existingPositionMs: 4800000),
        isFalse,
      );
    });

    test('~0s DOES create a first entry (the "next episode" marker)', () {
      expect(shouldWriteProgress(positionMs: 0, existingPositionMs: null), isTrue);
    });

    test('real progress always wins, including a rewind to the start', () {
      expect(
        shouldWriteProgress(positionMs: kMinResumeMs, existingPositionMs: 4800000),
        isTrue,
      );
      expect(
        shouldWriteProgress(positionMs: 5000000, existingPositionMs: 4800000),
        isTrue,
      );
    });

    test('a low position may still move forward from a lower one', () {
      expect(shouldWriteProgress(positionMs: 4000, existingPositionMs: 1000), isTrue);
    });
  });

  group('resumable: "Riprendi" must never mean "ricomincia"', () {
    test('a finished entry is not resumable', () {
      // Its position used to be handed to the player, which then declined to
      // seek past the end and silently started at zero.
      expect(_vod('1', pos: 5900000).finished, isTrue);
      expect(_vod('1', pos: 5900000).resumable, isFalse);
    });

    test('the first seconds are not a resume point', () {
      expect(_vod('1', pos: 3000).resumable, isFalse);
    });

    test('a half-watched entry is resumable', () {
      expect(_vod('1', pos: 3000000).resumable, isTrue);
    });
  });

  group('continueSeries: finishing an episode must not hide the series', () {
    test('keeps a series whose newest episode sits at 0s', () async {
      final repo = WatchProgressRepository();
      // Seven episodes watched, the last one finished; the auto-advance then
      // opened the next and closing the player recorded it at 0s.
      await repo.save(_ep('8767', 'e1', pos: 2400000, at: 100));
      await repo.save(_ep('8767', 'e2', pos: 2380000, at: 200));
      await repo.save(_ep('8767', 'e3', pos: 0, at: 300));

      final list = repo.continueSeries();
      expect(list, hasLength(1), reason: 'the series vanished from Continua');
      expect(list.single.episodeId, 'e3',
          reason: 'it must point at the episode you are now on');
    });

    test('a series only ever poked for a few seconds stays out', () async {
      final repo = WatchProgressRepository();
      await repo.save(_ep('8731', 'e1', pos: 4000, at: 100));
      expect(repo.continueSeries(), isEmpty);
    });

    test('one entry per series, newest first', () async {
      final repo = WatchProgressRepository();
      await repo.save(_ep('A', 'a1', pos: 600000, at: 100));
      await repo.save(_ep('A', 'a2', pos: 700000, at: 400));
      await repo.save(_ep('B', 'b1', pos: 600000, at: 200));

      final list = repo.continueSeries();
      expect(list.map((p) => p.seriesId), ['A', 'B']);
      expect(list.first.episodeId, 'a2');
    });
  });

  group('continueMovies is unchanged', () {
    test('drops finished and barely-started films', () async {
      final repo = WatchProgressRepository();
      await repo.save(_vod('done', pos: 5900000, at: 300));
      await repo.save(_vod('poked', pos: 2000, at: 200));
      await repo.save(_vod('watching', pos: 3000000, at: 100));

      expect(repo.continueMovies().map((p) => p.vodId), ['watching']);
    });
  });
}
