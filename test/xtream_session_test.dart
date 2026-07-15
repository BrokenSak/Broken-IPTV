import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:broken_iptv/data/services/catalog_cache.dart';
import 'package:broken_iptv/data/services/epg_store.dart';
import 'package:broken_iptv/data/services/xtream_session.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// Minimal fake transport: hands every request to [handler] (which can also
/// throw a DioException to simulate a network failure).
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  ResponseBody Function(RequestOptions options) handler;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls++;
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

const _catsJson = '[{"category_id":"1","category_name":"Sport"}]';

void main() {
  late Directory tmp;
  late LazyBox<Map> box;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('xtream_session_test');
    Hive.init(tmp.path);
    box = await Hive.openLazyBox<Map>('catalog_cache');
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await tmp.delete(recursive: true);
  });

  XtreamSession session(_FakeAdapter adapter) {
    return XtreamSession(
      host: 'http://panel.test',
      username: 'u',
      password: 'p',
      dio: Dio()..httpClientAdapter = adapter,
      cache: CatalogCache(box),
    );
  }

  test('categories load with the cache enabled (no extra params)', () async {
    // Regression: _cacheKey used to run `..sort()` on a const [] whenever the
    // action had no extra params → "Cannot modify an unmodifiable list" on
    // every catalog load.
    final adapter =
        _FakeAdapter((o) => ResponseBody.fromString(_catsJson, 200));
    final cats = await session(adapter).getLiveCategories();
    expect(cats.single.name, 'Sport');
  });

  test('streams with a category id (extra params) load too', () async {
    final adapter = _FakeAdapter((o) => ResponseBody.fromString(
        '[{"stream_id":7,"name":"Canale Uno","category_id":"5"}]', 200));
    final list = await session(adapter).getLiveStreams(categoryId: '5');
    expect(list.single.name, 'Canale Uno');
    expect(list.single.streamId, '7');
  });

  test('second call is served from the disk cache (no network)', () async {
    final adapter =
        _FakeAdapter((o) => ResponseBody.fromString(_catsJson, 200));
    await session(adapter).getLiveCategories();
    expect(adapter.calls, 1);

    // Fresh session (new launch): must answer from cache without a request.
    adapter.handler =
        (o) => throw DioException.connectionError(requestOptions: o, reason: 'down');
    final cats = await session(adapter).getLiveCategories();
    expect(cats.single.name, 'Sport');
    expect(adapter.calls, 1);
  });

  test('short EPG is disk-cached: no repeat network call', () async {
    final adapter = _FakeAdapter((o) => ResponseBody.fromString(
        '{"epg_listings":[{"title":"UHJvZ3JhbW1h",'
        '"start_timestamp":"1700000000","stop_timestamp":"1700003600"}]}',
        200));
    final s = session(adapter);
    final first = await s.getShortEpg('7');
    expect(first.single.title, 'Programma'); // base64-decoded
    await s.getShortEpg('7');
    expect(adapter.calls, 1); // second answered from cache
  });

  test('bulk EPG store answers tiles without get_short_epg calls', () async {
    String two(int n) => n.toString().padLeft(2, '0');
    String ts(DateTime d) {
      final u = d.toUtc();
      return '${u.year}${two(u.month)}${two(u.day)}'
          '${two(u.hour)}${two(u.minute)}${two(u.second)} +0000';
    }

    final now = DateTime.now();
    final xml = '<tv><programme start="${ts(now.subtract(const Duration(minutes: 5)))}" '
        'stop="${ts(now.add(const Duration(minutes: 55)))}" channel="rai1.it">'
        '<title>Dal bulk</title></programme></tv>';

    final requestedActions = <String>[];
    final adapter = _FakeAdapter((o) {
      final action = o.queryParameters['action'] as String?;
      requestedActions.add(action ?? '');
      if (action == 'get_live_streams') {
        return ResponseBody.fromString(
            '[{"stream_id":7,"name":"Rai 1","category_id":"5",'
            '"epg_channel_id":"rai1.it"}]',
            200);
      }
      return ResponseBody.fromString('{"epg_listings":[]}', 200);
    });

    final s = XtreamSession(
      host: 'http://panel.test',
      username: 'u',
      password: 'p',
      dio: Dio()..httpClientAdapter = adapter,
      cache: CatalogCache(box),
      epgStore: EpgStore(fetch: () async => utf8.encode(xml)),
    );

    final programs = await s.getShortEpg('7');
    expect(programs.single.title, 'Dal bulk');
    // Only the channel list was fetched for the id mapping — the guide came
    // from the single bulk download, not from get_short_epg.
    expect(requestedActions, ['get_live_streams']);
  });

  test('network failure falls back to a stale cache entry', () async {
    // Seed an entry older than the TTL under the real key.
    await box.put('http://panel.test|u|get_live_categories|', {
      'ts': DateTime.now()
          .subtract(const Duration(hours: 30))
          .millisecondsSinceEpoch,
      'body': _catsJson,
    });
    final adapter = _FakeAdapter(
        (o) => throw DioException.connectionError(requestOptions: o, reason: 'down'));
    final cats = await session(adapter).getLiveCategories();
    expect(cats.single.name, 'Sport');
    expect(adapter.calls, 1); // it did try the network first
  });
}
