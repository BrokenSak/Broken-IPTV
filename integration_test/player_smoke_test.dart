// The test that has been missing for 58 rounds: the REAL player, with the REAL
// native libmpv, on the REAL Firestick.
//
// ⚠️ Why it matters more than the 176 widget tests put together: PlayerScreen
// starts libmpv in initState, so it cannot be pumped on the dev host at all —
// and that is exactly why its bugs kept surviving every audit (HANDOFF, 54°
// giro). Everything below is a defect that actually shipped:
//
//   * the video not starting at all (the upscaling rounds: live channels stayed
//     black on the Firestick and nothing here could see it);
//   * OK not reopening the controls once they auto-hide (58° giro: with the
//     controls in an ExcludeFocus the key never reached the root handler, so
//     five seconds in the player went deaf);
//   * the resume point being wiped by the forced save on close (58° giro).
//
// 🛑 NEVER RUN THIS AGAINST A DEVICE THAT HAS THE REAL APP ON IT.
//
// `flutter test integration_test/` **removes the app under test from the device
// when it finishes**, and it targets the package from the manifest namespace —
// so the user's own install is what disappears, data and all. Verified the hard
// way on 2026-08-04, on the user's daily Firestick, TWICE:
//   * `applicationIdSuffix = ".debug"` on the debug build type — the test app
//     installed as `…broken_iptv.debug` and `…broken_iptv` was wiped anyway;
//   * a product flavour with `applicationId = "com.brokeniptv.itest"` — the
//     test app installed under its own id and `…broken_iptv` was STILL wiped,
//     this time without even logging the uninstall.
// Neither Gradle-side trick protects it. And `android:allowBackup="false"`
// (deliberate, HANDOFF §7) means nothing comes back: the playlist and its
// password do not sync, so they have to be typed in again by remote.
//
// Run it on a throwaway target — an emulator, or a device with no real install:
//   flutter test integration_test/player_smoke_test.dart -d emulator-5554
//
// On the Firestick only as a deliberate, announced act, accepting that cost.
//
// The clip is a small public sample so the test needs no panel credentials and
// stays deterministic; override it with
//   --dart-define=TEST_VIDEO_URL=<url>
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:broken_iptv/core/theme/app_theme.dart';
import 'package:broken_iptv/data/services/device_mode_service.dart';
import 'package:broken_iptv/data/services/storage_service.dart';
import 'package:broken_iptv/data/models/watch_progress.dart';
import 'package:broken_iptv/data/repositories/watch_progress_repository.dart';
import 'package:broken_iptv/presentation/common/app_background.dart';
import 'package:broken_iptv/presentation/common/dpad_focus_guard.dart';
import 'package:broken_iptv/presentation/screens/player/player_screen.dart';
import 'package:broken_iptv/state/watch_progress_providers.dart';

const _videoUrl = String.fromEnvironment(
  'TEST_VIDEO_URL',
  defaultValue:
      'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
);

/// Real time, not the widget-test fake clock: libmpv runs on its own threads
/// and the UI only learns about it through platform messages.
Future<void> _wait(WidgetTester tester, Duration d) async {
  final end = DateTime.now().add(d);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }
}

/// Pumps until [predicate] holds, or fails with [reason].
Future<void> _until(
  WidgetTester tester,
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 30),
  required String reason,
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    if (predicate()) return;
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 60));
  }
  fail(reason);
}

/// The player exactly as the app builds it: same route wrapper (which carries
/// DpadFocusGuard) and same query parameters.
Widget _playerApp(String query, ProviderContainer container) {
  final router = GoRouter(
    initialLocation: '/player?$query',
    routes: [
      GoRoute(
        path: '/player',
        builder: (context, state) {
          final q = state.uri.queryParameters;
          return PlayerScreen(
            streamUrl: q['url'],
            isLive: q['isLive'] == '1',
            channelName: q['name'],
            vodId: q['vodId'],
            resumeMs: int.tryParse(q['resume'] ?? '') ?? 0,
          );
        },
      ),
      GoRoute(
        path: '/back',
        builder: (_, _) => DpadFocusGuard(
          child: AppBackground(
            child: Scaffold(body: Center(child: Text('CATALOGO'))),
          ),
        ),
      ),
    ],
  );
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      theme: AppTheme.dark,
      debugShowCheckedModeBanner: false,
      // The same directional-navigation flag app.dart sets on Android: without
      // it a focused Slider eats Up/Down and traps the D-pad on the seek bar.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(navigationMode: NavigationMode.directional),
        child: child ?? const SizedBox.shrink(),
      ),
      routerConfig: router,
    ),
  );
}

Duration _position(WidgetTester tester) {
  final state = tester.state(find.byType(PlayerScreen));
  // ignore: avoid_dynamic_calls
  return (state as dynamic).currentPositionForTest as Duration;
}

bool _controlsVisible(WidgetTester tester) {
  final state = tester.state(find.byType(PlayerScreen));
  // ignore: avoid_dynamic_calls
  return (state as dynamic).controlsVisibleForTest as bool;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    MediaKit.ensureInitialized();
    await StorageService.init();
    DeviceModeService.detectedIsTv = await DeviceModeService().detectIsTv();
    // Drive everything as a TV, whatever mode this device has saved.
    await DeviceModeService().save(DeviceMode.tv);
  });

  testWidgets('the video actually starts playing', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
        _playerApp('url=$_videoUrl&name=Test&vodId=itest-1', container));
    await tester.pump();

    // Not "no exception thrown" — the position has to MOVE. A black screen with
    // a happy widget tree is the failure mode that shipped three times.
    await _until(
      tester,
      () => _position(tester) > Duration.zero,
      timeout: const Duration(seconds: 45),
      reason: 'playback never started: the position stayed at zero '
          '(this is the "schermo nero" failure)',
    );

    final first = _position(tester);
    await _wait(tester, const Duration(seconds: 3));
    expect(_position(tester), greaterThan(first),
        reason: 'playback stalled after the first frame');
  });

  testWidgets('OK reopens the controls after they auto-hide', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
        _playerApp('url=$_videoUrl&name=Test&vodId=itest-2', container));
    await tester.pump();
    await _until(tester, () => _position(tester) > Duration.zero,
        timeout: const Duration(seconds: 45), reason: 'playback never started');

    expect(_controlsVisible(tester), isTrue,
        reason: 'the controls start visible');

    // The 5s inactivity timer.
    await _until(
      tester,
      () => !_controlsVisible(tester),
      timeout: const Duration(seconds: 15),
      reason: 'the controls never auto-hid',
    );

    // ⚠️ THE regression: with the controls inside an ExcludeFocus the focus sits
    // on the enclosing scope, which is an ANCESTOR of the player's root key
    // catcher — so no key reached it and the remote was dead from here on.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await _wait(tester, const Duration(milliseconds: 500));

    expect(_controlsVisible(tester), isTrue,
        reason: 'REGRESSION: five seconds in, the player stopped answering the '
            'remote — OK could not even bring the menu back');
  });

  testWidgets('the resume point survives opening and leaving straight away',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(watchProgressProvider.notifier);
    // Somewhere real: 4 minutes into the clip.
    await notifier.save(WatchProgress(
      kind: WatchKind.vod,
      vodId: 'itest-3',
      seriesId: null,
      episodeId: null,
      episodeLabel: null,
      name: 'Test',
      imageUrl: null,
      url: _videoUrl,
      positionMs: 240000,
      durationMs: 600000,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    ));

    await tester.pumpWidget(_playerApp(
        'url=$_videoUrl&name=Test&vodId=itest-3&resume=240000', container));
    await tester.pump();
    // Leave almost immediately — before playback can reach the saved point.
    // This is what wiped the resume point: dispose() forces a save, and the
    // position was still ~0.
    await _wait(tester, const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox.shrink());
    await _wait(tester, const Duration(seconds: 1));

    // Straight from Hive: the widget tree is gone, so is its provider state.
    final after = WatchProgressRepository().get(WatchProgress.vodKey('itest-3'));
    expect(after, isNotNull, reason: 'the resume point disappeared entirely');
    expect(after!.positionMs, greaterThan(60000),
        reason: 'REGRESSION: backing out of a film before playback reached the '
            'saved point stamped ~0s over it — "riprende sempre dall\'inizio"');
  });
}
