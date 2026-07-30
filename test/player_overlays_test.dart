import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:broken_iptv/core/theme/app_theme.dart';
import 'package:broken_iptv/core/ui_mode.dart';
import 'package:broken_iptv/data/models/channel.dart';
import 'package:broken_iptv/data/models/epg_program.dart';
import 'package:broken_iptv/data/models/series_item.dart';
import 'package:broken_iptv/data/models/watch_progress.dart';
import 'package:broken_iptv/data/models/xtream_category.dart';
import 'package:broken_iptv/data/repositories/live_repository.dart';
import 'package:broken_iptv/data/repositories/series_repository.dart';
import 'package:broken_iptv/data/services/device_mode_service.dart';
import 'package:broken_iptv/data/services/storage_service.dart';
import 'package:broken_iptv/data/services/xtream_session.dart';
import 'package:broken_iptv/presentation/common/tv_focusable.dart';
import 'package:broken_iptv/presentation/common/watch_bar.dart';
import 'package:broken_iptv/presentation/screens/player/channel_list_overlay.dart';
import 'package:broken_iptv/presentation/screens/player/episode_list_overlay.dart';
import 'package:broken_iptv/state/live_providers.dart';
import 'package:broken_iptv/state/series_providers.dart';

/// Simulated-remote drive of the player's list overlays ("Episodi"/"Canali"):
/// arrows + OK only, in TV mode, exactly like a Firestick. Written after the
/// first release of the episode list shipped with bare ListTile/IconButton/
/// MenuItemButton stops whose focus was invisible on TV ("milioni di cose non
/// selezionabili e navigabili").
///
/// The player screen itself can't be widget-tested on the host (native libmpv
/// in initState): the overlays are extracted widgets precisely so the remote
/// path IS testable here.

XtreamSession _fakeSession() =>
    XtreamSession(host: 'http://fake-host', username: 'u', password: 'p');

const _seriesId = '20';

Episode _ep(String id, int num, String title, int season) => Episode(
      id: id,
      title: title,
      episodeNum: num,
      season: season,
      containerExtension: 'mp4',
    );

class FakeSeriesRepository extends SeriesRepository {
  FakeSeriesRepository({this.episodeCount = 2}) : super(_fakeSession());

  /// Season 1 length. A long season makes ListView.builder recycle rows,
  /// which is what broke the focus while scrolling.
  final int episodeCount;

  @override
  Future<SeriesDetail> getDetail(String seriesId) async => SeriesDetail(
        seriesId: seriesId,
        name: 'Serie Test',
        episodesBySeason: {
          1: [
            for (var i = 1; i <= episodeCount; i++)
              _ep('e$i', i, i == 1 ? 'Uno' : (i == 2 ? 'Due' : 'Ep $i'), 1),
          ],
          2: [_ep('s2e1', 1, 'Tre', 2)],
        },
      );
}

class FakeLiveRepository extends LiveRepository {
  FakeLiveRepository() : super(_fakeSession());

  @override
  Future<List<XtreamCategory>> getCategories() async => const [
        XtreamCategory(id: '1', name: 'Sport'),
        XtreamCategory(id: '2', name: 'News'),
      ];

  @override
  Future<List<Channel>> getAllChannels() async => [
        Channel(streamId: '100', name: 'Canale Uno', categoryId: '1'),
        Channel(streamId: '200', name: 'Canale Due', categoryId: '2'),
      ];

  @override
  Future<List<EpgProgram>> getShortEpg(String streamId, {int limit = 20}) async =>
      const [];
}

Future<void> _pressOk(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
  await tester.pumpAndSettle();
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key,
    [int times = 1]) async {
  for (var i = 0; i < times; i++) {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }
}

/// The MaterialApp shell; tests wrap it in their own ProviderScope (the
/// `Override` type isn't exported by flutter_riverpod 3, so the scope lives at
/// the call site).
Widget _shell(Widget overlay) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(body: Stack(children: [overlay])),
  );
}

void main() {
  setUpAll(() async {
    final dir = Directory.systemTemp.createTempSync('broken_iptv_overlay_test');
    await StorageService.init(testPath: dir.path);
  });

  setUp(() {
    debugDeviceModeOverride = DeviceMode.tv;
  });

  tearDown(() {
    debugDeviceModeOverride = null;
  });

  // NB: Hive writes must run under tester.runAsync — awaiting real IO inside
  // the widget-test fake clock hangs forever (HANDOFF lesson, burned twice).
  Future<void> seedProgress() async {
    await StorageService.watchProgressBox.clear();
    // e1 watched to the end ("Visto"), e2 left midway ("Lasciato a 0:30:00").
    await StorageService.watchProgressBox.put(
      WatchProgress.seriesKey(_seriesId, 'e1'),
      const WatchProgress(
        kind: WatchKind.series,
        vodId: null,
        seriesId: _seriesId,
        episodeId: 'e1',
        episodeLabel: '1. Uno',
        name: 'Serie Test',
        imageUrl: null,
        url: 'http://fake/e1',
        positionMs: 59 * 60 * 1000,
        durationMs: 60 * 60 * 1000,
        updatedAt: 1,
      ).toMap(),
    );
    await StorageService.watchProgressBox.put(
      WatchProgress.seriesKey(_seriesId, 'e2'),
      const WatchProgress(
        kind: WatchKind.series,
        vodId: null,
        seriesId: _seriesId,
        episodeId: 'e2',
        episodeLabel: '2. Due',
        name: 'Serie Test',
        imageUrl: null,
        url: 'http://fake/e2',
        positionMs: 30 * 60 * 1000,
        durationMs: 60 * 60 * 1000,
        updatedAt: 2,
      ).toMap(),
    );
  }

  group('EpisodeListOverlay (TV remote)', () {
    testWidgets('shows the watch bar per episode: full = Visto, partial = left off',
        (tester) async {
      await tester.runAsync(seedProgress);
      final selected = <String>[];
      await tester.pumpWidget(ProviderScope(
        overrides: [
          seriesRepositoryProvider.overrideWith((ref) async => FakeSeriesRepository()),
        ],
        child: _shell(
        EpisodeListOverlay(
          seriesId: _seriesId,
          currentEpisodeId: 'e2',
          fallbackImage: null,
          onClose: () {},
          onSelect: (e) => selected.add(e.id),
        ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('1. Uno'), findsOneWidget);
      expect(find.text('2. Due'), findsOneWidget);
      // Every row carries the classic progress bar underneath.
      expect(find.byType(WatchBar), findsNWidgets(2));
      expect(find.text('Visto'), findsOneWidget);
      // e2 IS the episode playing: its line says so instead of "Lasciato a"
      // (that's how you tell where you are in the series).
      expect(find.text('In riproduzione'), findsOneWidget);
    });

    testWidgets('OK plays the focused row; arrows move between episodes',
        (tester) async {
      final selected = <String>[];
      await tester.pumpWidget(ProviderScope(
        overrides: [
          seriesRepositoryProvider.overrideWith((ref) async => FakeSeriesRepository()),
        ],
        child: _shell(
        EpisodeListOverlay(
          seriesId: _seriesId,
          currentEpisodeId: 'e1',
          fallbackImage: null,
          onClose: () {},
          onSelect: (e) => selected.add(e.id),
        ),
        ),
      ));
      await tester.pumpAndSettle();

      // The first row autofocuses when the overlay opens: OK plays it.
      await _pressOk(tester);
      expect(selected, ['e1'],
          reason: 'the D-pad must land on the list as the overlay opens');

      // Down: second episode; OK plays it.
      await _press(tester, LogicalKeyboardKey.arrowDown);
      await _pressOk(tester);
      expect(selected, ['e1', 'e2']);
    });

    testWidgets('season dropdown: reachable with arrows, OK switches season, '
        'focus lands back on episode 1', (tester) async {
      final selected = <String>[];
      await tester.pumpWidget(ProviderScope(
        overrides: [
          seriesRepositoryProvider.overrideWith((ref) async => FakeSeriesRepository()),
        ],
        child: _shell(
        EpisodeListOverlay(
          seriesId: _seriesId,
          currentEpisodeId: 'e2',
          fallbackImage: null,
          onClose: () {},
          onSelect: (e) => selected.add(e.id),
        ),
        ),
      ));
      await tester.pumpAndSettle();

      // Climb out of the list into the header. The overlay now opens ON the
      // episode being played (e2, the 2nd row), so this walks up until the
      // season dropdown is reachable, then Left off the X onto the trigger.
      await _press(tester, LogicalKeyboardKey.arrowUp, 3);
      await _press(tester, LogicalKeyboardKey.arrowLeft);

      // OK opens the season menu: current entry (Stagione 1) + Stagione 2.
      await _pressOk(tester);
      expect(find.text('Stagione 2'), findsOneWidget,
          reason: 'OK on the trigger must open the season menu');

      // Focus is on the current entry: one Down reaches "Stagione 2", OK picks.
      await _press(tester, LogicalKeyboardKey.arrowDown);
      await _pressOk(tester);

      expect(find.text('1. Tre'), findsOneWidget, reason: 'season switched');
      expect(find.text('1. Uno'), findsNothing);

      // After the switch the focus must land back on the list: OK plays S2E1.
      await _pressOk(tester);
      expect(selected, ['s2e1'],
          reason: 'after a season change OK must act on the first episode');
    });

    testWidgets('the X closes the overlay from the remote', (tester) async {
      var closed = 0;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          seriesRepositoryProvider.overrideWith((ref) async => FakeSeriesRepository()),
        ],
        child: _shell(
        EpisodeListOverlay(
          seriesId: _seriesId,
          currentEpisodeId: 'e1',
          fallbackImage: null,
          onClose: () => closed++,
          onSelect: (_) {},
        ),
        ),
      ));
      await tester.pumpAndSettle();

      // Up to the header, then Right until the X (right-most stop).
      await _press(tester, LogicalKeyboardKey.arrowUp);
      await _press(tester, LogicalKeyboardKey.arrowRight, 2);
      await _pressOk(tester);
      expect(closed, 1, reason: 'OK on the X must close the overlay');
    });
  });

  group('overlay aperti dal player (composizione reale)', _compositionTests);

  group('scorrimento lista episodi', _scrollFocusTests);

  group('ChannelListOverlay (TV remote)', () {
    testWidgets('OK zaps to the focused channel; category filter works',
        (tester) async {
      final selected = <String>[];
      await tester.pumpWidget(ProviderScope(
        overrides: [
          liveRepositoryProvider.overrideWith((ref) async => FakeLiveRepository()),
        ],
        child: _shell(
        ChannelListOverlay(
          currentStreamId: '100',
          onClose: () {},
          onSelect: (id, name) => selected.add(id),
        ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Canale Uno'), findsOneWidget);
      expect(find.text('Canale Due'), findsOneWidget);

      // First row autofocuses: OK zaps to it.
      await _pressOk(tester);
      expect(selected, ['100']);

      // Up to the header, Left onto the category dropdown, OK opens it.
      await _press(tester, LogicalKeyboardKey.arrowUp);
      await _press(tester, LogicalKeyboardKey.arrowLeft);
      await _pressOk(tester);
      expect(find.text('News'), findsOneWidget, reason: 'menu open');

      // Current entry is "Tutti i canali": two Downs reach "News", OK filters.
      await _press(tester, LogicalKeyboardKey.arrowDown, 2);
      await _pressOk(tester);

      expect(find.text('Canale Due'), findsOneWidget);
      expect(find.text('Canale Uno'), findsNothing,
          reason: 'the category filter must apply app-side');

      // Focus is back on the (rebuilt) list: OK zaps to the filtered channel.
      await _pressOk(tester);
      expect(selected, ['100', '200']);
    });
  });
}

/// The composition bug: an overlay opened FROM the player mounts while the
/// controls behind it still hold the focus. Flutter honours `autofocus` only
/// when the scope has no focused child, so the D-pad stayed on the "Episodi"
/// button and the list showed no selection at all — "non mi fa vedere cosa
/// seleziono o su che episodio sono". The earlier tests pumped the overlay
/// alone, where autofocus works, so they never caught it.
void _compositionTests() {
  testWidgets('EpisodeListOverlay: aperto sopra i controlli, il focus entra '
      'nella lista e parte dall\'episodio in riproduzione', (tester) async {
    final behind = FocusNode(debugLabel: 'controls.episodi');
    addTearDown(behind.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        seriesRepositoryProvider.overrideWith((ref) async => FakeSeriesRepository()),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Stack(
            children: [
              // Stands in for the player's controls bar: it has the focus when
              // the overlay appears, exactly like the real "Episodi" button.
              Positioned(
                bottom: 0,
                child: TvFocusable(
                  focusNode: behind,
                  autofocus: true,
                  onTap: () {},
                  child: const SizedBox(width: 100, height: 40, child: Text('Episodi')),
                ),
              ),
              EpisodeListOverlay(
                seriesId: _seriesId,
                currentEpisodeId: 'e2', // second episode is playing
                fallbackImage: null,
                onClose: () {},
                onSelect: (_) {},
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(behind.hasPrimaryFocus, isFalse,
        reason: 'the focus must leave the control behind the panel');

    final focused = FocusManager.instance.primaryFocus;
    expect(focused?.debugLabel, 'episodes.current',
        reason: 'the remote must land on the episode being played');

    // And that row is the one marked "In riproduzione".
    expect(find.text('In riproduzione'), findsOneWidget);
  });

  testWidgets('ChannelListOverlay: idem — il focus entra e parte dal canale '
      'in onda', (tester) async {
    final behind = FocusNode(debugLabel: 'controls.canali');
    addTearDown(behind.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        liveRepositoryProvider.overrideWith((ref) async => FakeLiveRepository()),
      ],
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                bottom: 0,
                child: TvFocusable(
                  focusNode: behind,
                  autofocus: true,
                  onTap: () {},
                  child: const SizedBox(width: 100, height: 40, child: Text('Canali')),
                ),
              ),
              ChannelListOverlay(
                currentStreamId: '200', // second channel is on air
                onClose: () {},
                onSelect: (_, _) {},
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(behind.hasPrimaryFocus, isFalse);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'channels.current');
    expect(find.text('In riproduzione'), findsOneWidget);
  });
}

/// Scrolling a long episode list with the D-pad.
///
/// Reported: "gli episodi non rimangono sempre focussati se scorro su e giu".
/// ListView.builder destroys rows that leave the viewport — and with them any
/// focus node the row itself created — so the ring vanished mid-scroll and the
/// arrows hit a wall at the last built row. The nodes now live in the state.
void _scrollFocusTests() {
  testWidgets("scorrendo giu' e su il focus resta sempre su un episodio",
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        seriesRepositoryProvider
            .overrideWith((ref) async => FakeSeriesRepository(episodeCount: 30)),
      ],
      child: _shell(
        EpisodeListOverlay(
          seriesId: _seriesId,
          currentEpisodeId: 'e1',
          fallbackImage: null,
          onClose: () {},
          onSelect: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Walk far enough down that the early rows are recycled away.
    for (var i = 0; i < 20; i++) {
      await _press(tester, LogicalKeyboardKey.arrowDown);
      final node = FocusManager.instance.primaryFocus;
      expect(node, isNotNull, reason: 'focus lost after $i steps down');
      expect(node!.debugLabel, startsWith('episode'),
          reason: 'after $i steps down the focus left the list '
              '(landed on ${node.debugLabel})');
    }

    // And back up again.
    for (var i = 0; i < 20; i++) {
      await _press(tester, LogicalKeyboardKey.arrowUp);
      final node = FocusManager.instance.primaryFocus;
      expect(node, isNotNull, reason: 'focus lost after $i steps up');
      expect(node!.debugLabel, startsWith('episode'),
          reason: 'after $i steps up the focus left the list '
              '(landed on ${node.debugLabel})');
    }
  });

  testWidgets("OK dopo lo scorrimento apre l'episodio giusto", (tester) async {
    final picked = <String>[];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        seriesRepositoryProvider
            .overrideWith((ref) async => FakeSeriesRepository(episodeCount: 30)),
      ],
      child: _shell(
        EpisodeListOverlay(
          seriesId: _seriesId,
          currentEpisodeId: 'e1',
          fallbackImage: null,
          onClose: () {},
          onSelect: (e) => picked.add(e.id),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Three rows down = episode 4, even after the list has scrolled.
    await _press(tester, LogicalKeyboardKey.arrowDown, 3);
    await _pressOk(tester);
    expect(picked, ['e4']);
  });
}
