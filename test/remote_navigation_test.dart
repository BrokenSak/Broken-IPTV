import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:broken_iptv/core/theme/app_theme.dart';
import 'package:broken_iptv/core/ui_mode.dart';
import 'package:broken_iptv/data/models/channel.dart';
import 'package:broken_iptv/data/models/epg_program.dart';
import 'package:broken_iptv/data/models/series_item.dart';
import 'package:broken_iptv/data/models/vod_item.dart';
import 'package:broken_iptv/data/models/xtream_category.dart';
import 'package:broken_iptv/data/repositories/live_repository.dart';
import 'package:broken_iptv/data/repositories/series_repository.dart';
import 'package:broken_iptv/data/repositories/vod_repository.dart';
import 'package:broken_iptv/data/services/device_mode_service.dart';
import 'package:broken_iptv/data/services/storage_service.dart';
import 'package:broken_iptv/data/services/xtream_session.dart';
import 'package:broken_iptv/presentation/screens/home/home_screen.dart';
import 'package:broken_iptv/presentation/screens/live_tv/live_tv_screen.dart';
import 'package:broken_iptv/presentation/screens/series/series_detail_screen.dart';
import 'package:broken_iptv/presentation/screens/series/series_screen.dart';
import 'package:broken_iptv/presentation/screens/settings/settings_screen.dart';
import 'package:broken_iptv/presentation/screens/vod/vod_detail_screen.dart';
import 'package:broken_iptv/presentation/screens/vod/vod_screen.dart';
import 'package:broken_iptv/state/live_providers.dart';
import 'package:broken_iptv/state/player_settings_providers.dart';
import 'package:broken_iptv/state/profile_providers.dart';
import 'package:broken_iptv/state/series_providers.dart';
import 'package:broken_iptv/state/vod_providers.dart';

/// Simulated-remote drive of the REAL screens (home, TV, film, serie,
/// impostazioni): arrows + OK only, no taps. Runs with the app forced into TV
/// mode via [debugDeviceModeOverride], so hearts are badges, autofocus is on,
/// and traversal matches what a Firestick sees.
///
/// The player screen itself cannot be widget-tested on the host (it spins up
/// the native libmpv player in initState); its key rules live in
/// player_keys_test.dart / series_prompts_test.dart instead.

XtreamSession _fakeSession() =>
    XtreamSession(host: 'http://fake-host', username: 'u', password: 'p');

class FakeLiveRepository extends LiveRepository {
  FakeLiveRepository() : super(_fakeSession());

  @override
  Future<List<XtreamCategory>> getCategories() async =>
      const [XtreamCategory(id: '1', name: 'Sport')];

  @override
  Future<List<Channel>> getChannels(String categoryId) async =>
      [Channel(streamId: '100', name: 'Canale Test', categoryId: categoryId)];

  @override
  Future<List<Channel>> getAllChannels() async => getChannels('1');

  @override
  Future<List<EpgProgram>> getShortEpg(String streamId, {int limit = 20}) async =>
      const [];

  @override
  String streamUrl(String streamId) => 'http://fake-host/live/u/p/$streamId.ts';
}

class FakeVodRepository extends VodRepository {
  FakeVodRepository() : super(_fakeSession());

  @override
  Future<List<XtreamCategory>> getCategories() async =>
      const [XtreamCategory(id: '1', name: 'Azione')];

  @override
  Future<List<VodItem>> getItems(String categoryId) async =>
      [VodItem(streamId: '10', name: 'Film Test', categoryId: categoryId)];

  @override
  Future<List<VodItem>> getAllItems() async => getItems('1');

  @override
  Future<VodDetail> getDetail(String vodId) async => VodDetail(
        streamId: vodId,
        name: 'Film Test',
        containerExtension: 'mp4',
      );
}

class FakeSeriesRepository extends SeriesRepository {
  FakeSeriesRepository() : super(_fakeSession());

  @override
  Future<List<XtreamCategory>> getCategories() async =>
      const [XtreamCategory(id: '1', name: 'Drama')];

  @override
  Future<List<SeriesItem>> getItems(String categoryId) async =>
      [SeriesItem(seriesId: '20', name: 'Serie Test', categoryId: categoryId)];

  @override
  Future<List<SeriesItem>> getAllItems() async => getItems('1');

  @override
  Future<SeriesDetail> getDetail(String seriesId) async => SeriesDetail(
        seriesId: seriesId,
        name: 'Serie Test',
        episodesBySeason: {
          1: [
            const Episode(
              id: 'e1',
              title: 'Uno',
              episodeNum: 1,
              season: 1,
              containerExtension: 'mp4',
            ),
          ],
        },
      );
}

class _FixedSelectedProfileId extends SelectedProfileIdNotifier {
  @override
  String? build() => 'test-profile';
}

Future<void> _pressDown(WidgetTester tester, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
  }
}

Future<void> _pressOk(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
  // Handlers that await a Hive write before updating state (e.g. setAspect)
  // need the real event loop to run — the fake test clock never resumes them.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 120)));
  await tester.pumpAndSettle();
}

/// App shell: the screen under test at `/`, plus stub routes that echo the
/// URI they were opened with, so a test can assert WHERE the remote landed.
/// Tests wrap this in their own ProviderScope when they need overrides.
Widget _shell(Widget screen) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => screen),
      for (final path in const [
        '/player',
        '/live',
        '/search',
        '/settings',
        '/downloads',
        '/vod/:id',
        '/series/:id',
        '/epg',
      ])
        GoRoute(
          path: path,
          builder: (_, state) => Scaffold(body: Text('STUB ${state.uri}')),
        ),
    ],
  );
  return MaterialApp.router(theme: AppTheme.dark, routerConfig: router);
}

void main() {
  setUpAll(() async {
    final dir = Directory.systemTemp.createTempSync('broken_iptv_remote_test');
    await StorageService.init(testPath: dir.path);
  });

  setUp(() {
    debugDeviceModeOverride = DeviceMode.tv;
  });

  tearDown(() {
    debugDeviceModeOverride = null;
  });

  testWidgets('home: OK on the autofocused TV tile opens the live catalog',
      (tester) async {
    await tester.pumpWidget(ProviderScope(child: _shell(const HomeScreen())));
    await tester.pumpAndSettle();

    await _pressOk(tester);
    expect(find.text('STUB /live'), findsOneWidget,
        reason: 'the TV tile must be focused on arrival and react to OK');
  });

  testWidgets('home: Back asks to exit; OK on the focused "Annulla" stays',
      (tester) async {
    await tester.pumpWidget(ProviderScope(child: _shell(const HomeScreen())));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute(); // system Back
    await tester.pumpAndSettle();
    expect(find.text('Uscire da Broken IPTV?'), findsOneWidget);

    // "Annulla" starts focused (D-pad dialogs): OK dismisses, app stays.
    await _pressOk(tester);
    expect(find.text('Uscire da Broken IPTV?'), findsNothing);
    expect(find.text('TV'), findsOneWidget);
  });

  testWidgets('live TV: opens on Preferiti; remote reaches a category → player',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        selectedProfileIdProvider.overrideWith(_FixedSelectedProfileId.new),
        liveRepositoryProvider.overrideWith((ref) async => FakeLiveRepository()),
      ],
      child: _shell(const LiveTvScreen()),
    ));
    await tester.pumpAndSettle();

    // Default pane = Preferiti (empty here). Sidebar: PREFERITI[0], Sport[1].
    expect(find.textContaining('Nessun canale preferito'), findsOneWidget);
    expect(find.text('Canale Test'), findsNothing);

    await _pressDown(tester, 1); // → Sport
    await _pressOk(tester); // select it
    expect(find.text('Canale Test'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight); // into the grid
    await tester.pumpAndSettle();
    await _pressOk(tester);

    expect(find.textContaining('STUB /player'), findsOneWidget);
    expect(find.textContaining('isLive=1'), findsOneWidget);
    expect(find.textContaining('streamId=100'), findsOneWidget);
  });

  testWidgets('film: opens on Continua; remote reaches a category → detail',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        vodRepositoryProvider.overrideWith((ref) async => FakeVodRepository()),
      ],
      child: _shell(const VodScreen()),
    ));
    await tester.pumpAndSettle();

    // Default pane = Continua (empty). Sidebar: CONTINUA, PREFERITI, TUTTI,
    // ULTIMI, Azione → 4 downs to the first real category.
    expect(find.textContaining('Niente da riprendere'), findsOneWidget);

    await _pressDown(tester, 4); // → Azione
    await _pressOk(tester);
    expect(find.text('Film Test'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await _pressOk(tester);

    expect(find.text('STUB /vod/10'), findsOneWidget);
  });

  testWidgets('serie: opens on Continua; remote reaches a category → detail',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        seriesRepositoryProvider.overrideWith((ref) async => FakeSeriesRepository()),
      ],
      child: _shell(const SeriesScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Niente da riprendere'), findsOneWidget);

    await _pressDown(tester, 4); // → Drama
    await _pressOk(tester);
    expect(find.text('Serie Test'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await _pressOk(tester);

    expect(find.text('STUB /series/20'), findsOneWidget);
  });

  testWidgets('dettaglio film: "Guarda" è focusato all\'arrivo, OK apre il player',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        vodRepositoryProvider.overrideWith((ref) async => FakeVodRepository()),
      ],
      child: _shell(const VodDetailScreen(vodId: '10')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Guarda'), findsOneWidget);

    // The play button (TvFocusable, black ring on the white pill) autofocuses:
    // OK must start playback with no arrow pressed first.
    await _pressOk(tester);
    expect(find.textContaining('STUB /player'), findsOneWidget,
        reason: 'OK on the focused Guarda button must open the player');
  });

  testWidgets('dettaglio serie: OK sul primo episodio apre il player',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        seriesRepositoryProvider.overrideWith((ref) async => FakeSeriesRepository()),
      ],
      child: _shell(const SeriesDetailScreen(seriesId: '20')),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Uno'), findsOneWidget);

    // The first episode tile autofocuses: OK plays it.
    await _pressOk(tester);
    expect(find.textContaining('STUB /player'), findsOneWidget);
    expect(find.textContaining('episodeId=e1'), findsOneWidget);
  });

  testWidgets('impostazioni: arrows reach the aspect chips, OK applies one',
      (tester) async {
    await tester.pumpWidget(ProviderScope(child: _shell(const SettingsScreen())));
    await tester.pumpAndSettle();

    // Arrival: dal 78° giro OGNI riquadro è una fermata del telecomando, anche
    // quelli che non fanno niente (senza, col D-pad non si possono rileggere).
    // Si atterra quindi sulla riga della playlist, in cima: due Giù per
    // arrivare alle chip del rapporto d'aspetto — playlist, codice, chip — e
    // due Destra che si fermano sull'ultima, "Riempi".
    await _pressDown(tester, 2);
    for (var i = 0; i < 2; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
    }
    await _pressOk(tester);

    final context = tester.element(find.byType(SettingsScreen));
    final container = ProviderScope.containerOf(context, listen: false);
    expect(container.read(playerSettingsProvider).aspect, VideoAspect.fill,
        reason: 'OK on the focused chip must apply the setting');
  });

  testWidgets('impostazioni: il telecomando scende fino alle chip del salto',
      (tester) async {
    await tester.pumpWidget(ProviderScope(child: _shell(const SettingsScreen())));
    await tester.pumpAndSettle();

    // Dalla riga della playlist: codice, chip dell'aspetto, interruttore dei
    // sottotitoli, chip del salto. Quelle righe stanno sotto la piega, quindi
    // ogni salto del focus fa scorrere la lista (ensureVisible) — esattamente
    // come col telecomando vero. Le frecce a destra si fermano su "60 s".
    await _pressDown(tester, 4);
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
    }
    await _pressOk(tester);

    final context = tester.element(find.byType(SettingsScreen));
    final container = ProviderScope.containerOf(context, listen: false);
    expect(container.read(playerSettingsProvider).skipSeconds, kSkipOptions.last,
        reason: 'OK on the focused skip chip must apply it');
  });
}
