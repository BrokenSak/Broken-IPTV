import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
// `Override` is not re-exported by flutter_riverpod 3; it lives here.
import 'package:riverpod/misc.dart' show Override;

import 'package:broken_iptv/core/theme/app_theme.dart';
import 'package:broken_iptv/core/ui_mode.dart';
import 'package:broken_iptv/data/models/download_item.dart';
import 'package:broken_iptv/data/models/series_item.dart';
import 'package:broken_iptv/data/models/vod_item.dart';
import 'package:broken_iptv/data/models/xtream_category.dart';
import 'package:broken_iptv/data/models/xtream_profile.dart';
import 'package:broken_iptv/data/repositories/series_repository.dart';
import 'package:broken_iptv/data/repositories/vod_repository.dart';
import 'package:broken_iptv/data/services/device_mode_service.dart';
import 'package:broken_iptv/data/services/storage_service.dart';
import 'package:broken_iptv/data/services/xtream_session.dart';
import 'package:broken_iptv/presentation/common/tv_focusable.dart';
import 'package:broken_iptv/presentation/common/tv_text_field.dart';
import 'package:broken_iptv/presentation/screens/downloads/downloads_screen.dart';
import 'package:broken_iptv/presentation/screens/home/home_screen.dart';
import 'package:broken_iptv/presentation/screens/onboarding/device_mode_screen.dart';
import 'package:broken_iptv/presentation/screens/profiles/add_profile_screen.dart';
import 'package:broken_iptv/presentation/screens/profiles/profiles_screen.dart';
import 'package:broken_iptv/presentation/screens/series/series_detail_screen.dart';
import 'package:broken_iptv/presentation/screens/settings/settings_screen.dart';
import 'package:broken_iptv/presentation/screens/settings/sync_settings_screen.dart';
import 'package:broken_iptv/presentation/screens/vod/vod_detail_screen.dart';
import 'package:broken_iptv/state/series_providers.dart';
import 'package:broken_iptv/state/update_providers.dart';
import 'package:broken_iptv/state/vod_providers.dart';

/// Whole-app remote audit.
///
/// Instead of hand-listing buttons, each screen is pumped in TV mode and its
/// focus ring is walked node by node (`nextFocus()`), exactly like a remote
/// tabbing through it. Two things are then asserted for every screen:
///
///  1. **something is focused on arrival** — a screen where the D-pad has no
///     landing spot is a dead end (OK does nothing);
///  2. **every focus stop is a visible one** — it must live inside a
///     [TvFocusable] (white/black ring) or a [TvTextFormField]. A bare
///     Material button (IconButton, ElevatedButton, FAB, ListTile with onTap,
///     InkWell…) that takes focus is INVISIBLE with this app's theme
///     (`highlightColor: transparent` + `NoSplash`) — that is precisely the
///     "milioni di cose non selezionabili" the user reported, so it fails here.
///
/// This is the regression net for the whole app: a new screen that forgets
/// TvFocusable fails this test without anyone having to remember the rule.

XtreamSession _fakeSession() =>
    XtreamSession(host: 'http://fake-host', username: 'u', password: 'p');

class _FakeVodRepository extends VodRepository {
  _FakeVodRepository() : super(_fakeSession());

  @override
  Future<VodDetail> getDetail(String vodId) async => VodDetail(
        streamId: vodId,
        name: 'Film Test',
        plot: 'Trama.',
        containerExtension: 'mp4',
      );

  @override
  Future<List<XtreamCategory>> getCategories() async => const [];

  @override
  Future<List<VodItem>> getAllItems() async => const [];
}

class _FakeSeriesRepository extends SeriesRepository {
  _FakeSeriesRepository() : super(_fakeSession());

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

  @override
  Future<List<XtreamCategory>> getCategories() async => const [];

  @override
  Future<List<SeriesItem>> getAllItems() async => const [];
}

/// Audits the screen as a **pushed** route, not as the root one.
///
/// ⚠️ That difference is the whole reason this audit missed the back button.
/// Every AppBar in the app relied on Flutter's automatic [BackButton] — a bare
/// Material IconButton, whose focus is INVISIBLE with this theme — and it is
/// the first stop in reading order. But `AppBar` only draws it when the route
/// can pop, so pumping a screen at `/` hid the bug completely: on the real
/// Firestick, arriving at "Nuova playlist" showed no selection anywhere and OK
/// threw you out of the form. Nesting the screen under `/` gives the audit the
/// same stack the app has.
///
/// ⚠️ The shell also installs `NavigationMode.directional`, exactly as
/// `app.dart` does on Android — and that is not cosmetic. In directional mode
/// `InkResponse._canRequestFocus` returns **true unconditionally**, so every
/// Material ink surface in the tree becomes a D-pad stop *even with no
/// `onTap`*: a label-only `ListTile` included. Under the default
/// `traditional` mode those same nodes are unfocusable, so this audit used to
/// pass while the real Firestick stopped the ring on plain captions — the
/// "il focus deve essere solo su elementi cliccabili" the user reported.
Widget _shell(Widget screen) {
  final router = GoRouter(
    initialLocation: '/screen',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('ROOT')),
        routes: [GoRoute(path: 'screen', builder: (_, _) => screen)],
      ),
      for (final path in const [
        '/player',
        '/live',
        '/vod',
        '/series',
        '/search',
        '/settings',
        '/settings/sync',
        '/downloads',
        '/profiles',
        '/profiles/add',
        '/vod/:id',
        '/series/:id',
      ])
        GoRoute(
          path: path,
          builder: (_, state) => Scaffold(body: Text('STUB ${state.uri}')),
        ),
    ],
  );
  return MaterialApp.router(
    theme: AppTheme.dark,
    routerConfig: router,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(navigationMode: NavigationMode.directional),
      child: child ?? const SizedBox.shrink(),
    ),
  );
}

/// Pumps a few frames without waiting for the tree to go quiet: several
/// screens keep an indeterminate progress indicator alive, and pumpAndSettle
/// would block on it until its 10-minute timeout.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// A focus stop that a remote user can actually SEE.
///
/// Sitting *somewhere under* a [TvFocusable] is not enough: a Material ink
/// surface nested inside one (a [ListTile], an [InkWell], any button) owns a
/// **second** focus node over the very same box, and it paints nothing with
/// this theme. Worse, `TvFocusable._handleKey` bails out unless it holds the
/// primary focus, so OK on that inner node does nothing at all. Those belong in
/// `ExcludeFocus`. Hence: walk up and take whichever comes FIRST — the ink
/// surface (invisible) or the TvFocusable/TvTextFormField that owns it.
bool _isVisibleStop(FocusNode node) {
  final context = node.context;
  if (context == null) return false;
  var visible = false;
  context.visitAncestorElements((element) {
    final widget = element.widget;
    if (widget is TvFocusable || widget is TvTextFormField) {
      visible = true;
      return false;
    }
    // InkWell extends InkResponse, so this covers every Material ink surface.
    if (widget is InkResponse) return false;
    return true;
  });
  return visible;
}

/// Walks the whole focus ring like a remote would, returning the stops that
/// are invisible (a bug) — described by their nearest widget, for the message.
Future<List<String>> _invisibleStops(WidgetTester tester, {int maxHops = 60}) async {
  final bad = <String>[];
  final visited = <FocusNode>{};

  for (var i = 0; i < maxHops; i++) {
    final node = FocusManager.instance.primaryFocus;
    if (node == null) break;
    if (!visited.add(node)) break; // looped back to the start: done

    // The app's root/scope nodes are plumbing, not user-facing stops.
    final isPlumbing = node.context?.widget is! Focus ||
        node.debugLabel == 'player.root' ||
        node is FocusScopeNode;
    if (!isPlumbing && !_isVisibleStop(node)) {
      final w = node.context?.findAncestorWidgetOfExactType<Semantics>();
      bad.add('${node.debugLabel ?? node.context?.widget.runtimeType} '
          '(${w?.properties.label ?? 'no label'})');
    }

    if (!node.nextFocus()) break;
    await tester.pump();
  }
  return bad;
}

/// Pumps [screen] in TV mode and audits it.
Future<void> _auditScreen(
  WidgetTester tester,
  Widget screen, {
  required String name,
  List<Override> overrides = const [],
  bool expectAutofocus = true,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: overrides,
    child: _shell(screen),
  ));
  // Bounded settle: pumpAndSettle never returns on a screen that keeps a
  // spinner spinning (loading states, sync progress), which is most of them
  // here. A few frames are enough for autofocus + the async fakes to land.
  await _settle(tester);

  if (expectAutofocus) {
    final focused = FocusManager.instance.primaryFocus;
    expect(focused != null && _isVisibleStop(focused), isTrue,
        reason: '$name: on arrival the remote must sit on a VISIBLE control '
            '(otherwise OK does nothing and nothing looks selected)');
  }

  final bad = await _invisibleStops(tester);
  expect(bad, isEmpty,
      reason: '$name: these focus stops are invisible on TV — wrap them in '
          'TvFocusable (or ExcludeFocus if pointer-only): $bad');
}

void main() {
  setUpAll(() async {
    final dir = Directory.systemTemp.createTempSync('broken_iptv_audit_test');
    await StorageService.init(testPath: dir.path);
  });

  setUp(() {
    debugDeviceModeOverride = DeviceMode.tv;
  });

  tearDown(() {
    debugDeviceModeOverride = null;
  });

  testWidgets('home', (tester) async {
    await _auditScreen(tester, const HomeScreen(),
        name: 'Home',
        // No update banner in tests: the check provider would hit the network.
        overrides: [updateCheckProvider.overrideWith((ref) async => null)]);
  });

  testWidgets('scelta dispositivo (primo avvio)', (tester) async {
    await _auditScreen(tester, const DeviceModeScreen(), name: 'Device picker');
  });

  testWidgets('impostazioni', (tester) async {
    await _auditScreen(tester, const SettingsScreen(), name: 'Impostazioni');
  });

  testWidgets('sincronizzazione', (tester) async {
    // ⚠️ This used to pass `expectAutofocus: false` with a comment claiming the
    // screen "opens on a text field wrapper". It did not: on the Firestick it
    // opened with NOTHING focused — OK did nothing and the first arrow jumped
    // up to the back button. The exemption hid it, so the assertion is on now
    // (the first field asks for navigation focus).
    await _auditScreen(tester, const SyncSettingsScreen(),
        name: 'Sincronizzazione');
  });

  testWidgets('playlist: vuota e con una playlist salvata', (tester) async {
    await _auditScreen(tester, const ProfilesScreen(), name: 'Playlist (vuota)');

    // With a saved playlist the screen grows the FAB + edit/delete icons: the
    // FAB used to be a bare (invisible on TV) focus stop.
    // NB: Hive writes MUST run inside runAsync — awaiting real IO under the
    // widget-test fake clock never resumes (HANDOFF lesson, hit again here).
    await tester.runAsync(() => StorageService.profilesBox.put('p1', const XtreamProfile(
          id: 'p1',
          name: 'Casa',
          host: 'http://fake-host',
          username: 'u',
        ).toMap()));
    addTearDown(() => StorageService.profilesBox.clear());

    await _auditScreen(tester, const ProfilesScreen(), name: 'Playlist (piena)');
  });

  testWidgets('aggiungi playlist (campi + salva)', (tester) async {
    await _auditScreen(tester, const AddProfileScreen(),
        name: 'Aggiungi playlist',
        // Lands on the first text field's navigation wrapper.
        expectAutofocus: false);
  });

  testWidgets('dettaglio film', (tester) async {
    await _auditScreen(tester, const VodDetailScreen(vodId: '10'),
        name: 'Dettaglio film',
        overrides: [
          vodRepositoryProvider.overrideWith((ref) async => _FakeVodRepository()),
        ]);
  });

  testWidgets('dettaglio serie', (tester) async {
    await _auditScreen(tester, const SeriesDetailScreen(seriesId: '20'),
        name: 'Dettaglio serie',
        overrides: [
          seriesRepositoryProvider.overrideWith((ref) async => _FakeSeriesRepository()),
        ]);
  });

  testWidgets('scaricati: play e azioni sono stop separati e visibili',
      (tester) async {
    // A completed item (play + elimina) and a failed one (riprova + elimina):
    // the action icons used to be nested INSIDE the row's TvFocusable, where a
    // D-pad can never reach them.
    // Hive writes inside runAsync (fake clock would never resume them).
    await tester.runAsync(() async {
      await StorageService.downloadsBox.put('vod:1', DownloadItem(
        key: 'vod:1',
        type: DownloadType.vod,
        name: 'Film scaricato',
        remoteUrl: 'http://fake/1.mp4',
        containerExtension: 'mp4',
        createdAt: 1,
        filePath: '/tmp/1.mp4',
        status: DownloadStatus.completed,
      ).toMap());
      await StorageService.downloadsBox.put('vod:2', DownloadItem(
        key: 'vod:2',
        type: DownloadType.vod,
        name: 'Film fallito',
        remoteUrl: 'http://fake/2.mp4',
        containerExtension: 'mp4',
        createdAt: 2,
        status: DownloadStatus.failed,
        error: 'Interrotto',
      ).toMap());
    });
    addTearDown(() => StorageService.downloadsBox.clear());

    await _auditScreen(tester, const DownloadsScreen(), name: 'Scaricati');

    // And the actions are really reachable: 1 play + 3 icons = 4 stops.
    var stops = 0;
    final visited = <FocusNode>{};
    for (var i = 0; i < 20; i++) {
      final node = FocusManager.instance.primaryFocus;
      if (node == null || !visited.add(node)) break;
      if (_isVisibleStop(node)) stops++;
      if (!node.nextFocus()) break;
      await tester.pump();
    }
    expect(stops, greaterThanOrEqualTo(4),
        reason: 'play + elimina (completato) + riprova/elimina (fallito) must '
            'each be their own reachable stop');
  });

  testWidgets('dialog di conferma: Annulla è focusato e visibile', (tester) async {
    // A dialog with no focused node ignores OK entirely on a remote.
    await tester.pumpWidget(ProviderScope(
      overrides: [updateCheckProvider.overrideWith((ref) async => null)],
      child: _shell(const HomeScreen()),
    ));
    await _settle(tester);

    await tester.binding.handlePopRoute(); // system Back → exit dialog
    await _settle(tester);
    expect(find.text('Uscire da Broken IPTV?'), findsOneWidget);

    final focused = FocusManager.instance.primaryFocus;
    expect(focused != null && _isVisibleStop(focused), isTrue,
        reason: 'the dialog must open with a VISIBLY focused button');

    final bad = await _invisibleStops(tester, maxHops: 10);
    expect(bad, isEmpty, reason: 'dialog buttons must be visible stops: $bad');
  });
}
