import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:broken_iptv/data/models/download_item.dart';
import 'package:broken_iptv/data/services/download_service.dart';
import 'package:broken_iptv/data/services/storage_service.dart';
import 'package:broken_iptv/state/downloads_providers.dart';

/// Fake downloader: no real network/filesystem. Simulates progress, can be
/// told to fail, and records how many transfers run at once (to prove the
/// queue is sequential).
class FakeDownloadService extends DownloadService {
  int active = 0;
  int maxActive = 0;
  final Set<String> failUrls = {};
  final List<String> deleted = [];

  @override
  Future<String> filePathFor(String key, String ext) async => '/tmp/$key.$ext';

  @override
  Future<void> download({
    required String url,
    required String savePath,
    required CancelToken cancelToken,
    required void Function(int received, int total) onProgress,
  }) async {
    active++;
    maxActive = max(maxActive, active);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 2));
      onProgress(500, 1000);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      onProgress(1000, 1000);
      if (failUrls.contains(url)) {
        throw DioException(requestOptions: RequestOptions(path: url));
      }
    } finally {
      active--;
    }
  }

  @override
  Future<void> deleteFile(String? path) async {
    if (path != null) deleted.add(path);
  }
}

DownloadItem _vod(String id, {String? name}) => DownloadItem(
      key: DownloadItem.vodKey(id),
      type: DownloadType.vod,
      name: name ?? 'Film $id',
      remoteUrl: 'http://panel/movie/$id.mp4',
      containerExtension: 'mp4',
      createdAt: DateTime.now().millisecondsSinceEpoch,
      vodId: id,
    );

ProviderContainer _container(FakeDownloadService fake) {
  final c = ProviderContainer(overrides: [
    downloadServiceProvider.overrideWithValue(fake),
  ]);
  addTearDown(c.dispose);
  return c;
}

/// Waits until [test] holds or the timeout elapses (downloads are async).
/// The queue is fire-and-forget, so there is no future to await; the deadline
/// is generous on purpose — a tighter one flaked when the whole suite ran in
/// parallel on a loaded machine.
/// Aspetta che [test] diventi vero, e **fallisce dicendo che è scaduto** se non
/// succede.
///
/// ⚠️ Prima scadeva in silenzio e il test proseguiva ad asserire su uno stato
/// incompleto: a macchina carica (durante una release, con le build in corso)
/// il risultato era un fallimento che indicava la cosa sbagliata. La coda è
/// fire-and-forget, non c'è un future da attendere: qui l'unica difesa è
/// un'attesa generosa e un messaggio onesto quando non basta.
Future<void> _until(
  bool Function() test, {
  Duration timeout = const Duration(seconds: 30),
  String cosa = 'la condizione attesa',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!test()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('scaduti ${timeout.inSeconds}s aspettando: $cosa');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = Directory.systemTemp.createTempSync('broken_iptv_downloads_test');
    await StorageService.init(testPath: dir.path);
  });

  setUp(() async {
    await StorageService.downloadsBox.clear();
  });

  group('DownloadItem', () {
    test('round-trips through a map', () {
      final item = _vod('1').copyWith(status: DownloadStatus.completed, received: 5, total: 10);
      final back = DownloadItem.fromMap(item.toMap());
      expect(back.key, 'vod:1');
      expect(back.type, DownloadType.vod);
      expect(back.status, DownloadStatus.completed);
      expect(back.received, 5);
      expect(back.total, 10);
      expect(back.fraction, 0.5);
      expect(back.vodId, '1');
    });

    test('copyWith can clear the error while other fields keep theirs', () {
      final failed = _vod('1').copyWith(status: DownloadStatus.failed, error: 'boom', total: 10);
      final retried = failed.copyWith(status: DownloadStatus.queued, error: null);
      expect(retried.error, isNull);
      expect(retried.total, 10, reason: 'unspecified fields are preserved');

      final progressed = failed.copyWith(received: 3);
      expect(progressed.error, 'boom', reason: 'error kept when not passed');
    });

    test('episode key matches the watch-progress scheme', () {
      expect(DownloadItem.episodeKey('42', '7'), 'series:42:7');
    });
  });

  group('DownloadsNotifier', () {
    test('a queued item downloads and completes', () async {
      final fake = FakeDownloadService();
      final c = _container(fake);
      await c.read(downloadsProvider.notifier).enqueue(_vod('1'));

      await _until(() => c.read(downloadsProvider).any((d) => d.isCompleted));
      final item = c.read(downloadsProvider).single;
      expect(item.status, DownloadStatus.completed);
      expect(item.total, 1000, reason: 'final byte counts are pinned on completion');
      expect(item.filePath, '/tmp/vod:1.mp4');
    });

    test('multiple downloads run one at a time (sequential queue)', () async {
      final fake = FakeDownloadService();
      final c = _container(fake);
      final n = c.read(downloadsProvider.notifier);
      await n.enqueue(_vod('1'));
      await n.enqueue(_vod('2'));
      await n.enqueue(_vod('3'));

      await _until(
        () => c.read(downloadsProvider).where((d) => d.isCompleted).length == 3,
        cosa: 'tre scaricamenti completati',
      );
      expect(fake.maxActive, 1, reason: 'never more than one active transfer');
    });

    test('a failed download is marked failed and can be retried', () async {
      final fake = FakeDownloadService()..failUrls.add('http://panel/movie/1.mp4');
      final c = _container(fake);
      final n = c.read(downloadsProvider.notifier);
      await n.enqueue(_vod('1'));

      await _until(() => c.read(downloadsProvider).any(
          (d) => d.status == DownloadStatus.failed));
      expect(c.read(downloadsProvider).single.status, DownloadStatus.failed);

      // Now let it succeed on retry.
      fake.failUrls.clear();
      await n.retry('vod:1');
      await _until(() => c.read(downloadsProvider).any((d) => d.isCompleted));
      expect(c.read(downloadsProvider).single.status, DownloadStatus.completed);
    });

    test('remove deletes the entry and its file', () async {
      final fake = FakeDownloadService();
      final c = _container(fake);
      final n = c.read(downloadsProvider.notifier);
      await n.enqueue(_vod('1'));
      await _until(() => c.read(downloadsProvider).any((d) => d.isCompleted));

      await n.remove('vod:1');
      expect(c.read(downloadsProvider), isEmpty);
      expect(fake.deleted, contains('/tmp/vod:1.mp4'));
    });

    test('enqueue ignores an already-completed item', () async {
      final fake = FakeDownloadService();
      final c = _container(fake);
      final n = c.read(downloadsProvider.notifier);
      await n.enqueue(_vod('1'));
      await _until(() => c.read(downloadsProvider).any((d) => d.isCompleted));

      await n.enqueue(_vod('1'));
      expect(c.read(downloadsProvider).length, 1);
      expect(fake.maxActive, 1);
    });

    test('interrupted downloads load back as failed (not stuck downloading)', () async {
      // Simulate a leftover "downloading" row from a killed app run.
      await StorageService.downloadsBox.put('vod:9', _vod('9')
          .copyWith(status: DownloadStatus.downloading, total: 100, received: 40)
          .toMap());

      final fake = FakeDownloadService();
      final c = _container(fake);
      final loaded = c.read(downloadsProvider).single;
      expect(loaded.status, DownloadStatus.failed);
      expect(loaded.error, 'Interrotto');
    });
  });
}
