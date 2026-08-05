import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:broken_iptv/core/format.dart';
import 'package:broken_iptv/core/theme/app_theme.dart';
import 'package:broken_iptv/core/ui_mode.dart';
import 'package:broken_iptv/data/services/device_mode_service.dart';
import 'package:broken_iptv/presentation/screens/player/player_controls.dart';
import 'package:broken_iptv/state/player_settings_providers.dart';

/// Simulated-remote tests for the player chrome.
///
/// PlayerScreen itself can't be pumped on the host (native libmpv in
/// initState), which is why these bugs shipped: "la parte destra del player non
/// e' selezionabile (riempi, sottotitoli, velocita')" and "in alto impostazioni
/// e tornare indietro non sono selezionabili". The chrome now lives in
/// player_controls.dart precisely so a D-pad can be driven over it here.

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key,
    [int times = 1]) async {
  for (var i = 0; i < times; i++) {
    await tester.sendKeyEvent(key);
    await tester.pump();
  }
}

Future<void> _pressOk(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
  await tester.pump();
}

/// The label of the control the remote is currently on (its Semantics label,
/// which every PlayerButton sets), or null when the focus is elsewhere.
String? _focusedLabel() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return null;
  final semantics = context.findAncestorWidgetOfExactType<Semantics>();
  return semantics?.properties.label;
}

/// Walks the whole focus ring and collects every reachable control label.
Future<Set<String>> _reachableLabels(WidgetTester tester,
    {int maxHops = 40}) async {
  final labels = <String>{};
  final visited = <FocusNode>{};
  for (var i = 0; i < maxHops; i++) {
    final node = FocusManager.instance.primaryFocus;
    if (node == null || !visited.add(node)) break;
    final label = _focusedLabel();
    if (label != null) labels.add(label);
    if (!node.nextFocus()) break;
    await tester.pump();
  }
  return labels;
}

/// The player chrome as the screen assembles it: top bar, spacer, controls.
/// [seekCalls] records every seek the bar asks for.
Widget _chrome({
  required FocusNode primaryNode,
  bool isLive = false,
  List<Duration>? seekCalls,
  Duration position = const Duration(minutes: 30),
  Duration duration = const Duration(hours: 2),
  VoidCallback? onSettings,
  VoidCallback? onBack,
  List<double>? rateCalls,
  List<bool>? subtitleCalls,
  double rate = 1.0,
  bool subtitlesOn = false,
}) {
  return ProviderScope(
    child: MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        backgroundColor: Colors.black,
        // NavigationMode.directional mirrors what app.dart installs on
        // Android: without it a focused Slider eats Up/Down and traps the
        // D-pad on the seek bar.
        body: Builder(
          builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(navigationMode: NavigationMode.directional),
          // Mirrors PlayerScreen's real tree: the SAME PlayerRootFocus the
          // screen uses (so this test guards it), a Stack with the video + tap
          // catcher underneath, and the chrome inside
          // AnimatedOpacity/IgnorePointer/ExcludeFocus. The reported bugs only
          // reproduce with this structure.
          child: PlayerRootFocus(
            onKeyEvent: (_, _) => KeyEventResult.ignored,
            child: Stack(
              children: [
                const Positioned.fill(child: ColoredBox(color: Colors.black)),
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                  ),
                ),
                AnimatedOpacity(
                  opacity: 1,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: false,
                    child: ExcludeFocus(
                      excluding: false,
                      child: Column(
            children: [
              PlayerTopBar(
                title: 'Titolo',
                isLive: isLive,
                streamId: null,
                qualityLabel: '1080p',
                onBack: onBack ?? () {},
                onSettings: onSettings,
              ),
              const Spacer(),
              PlayerControlsPanel(
                playing: true,
                isLive: isLive,
                position: position,
                duration: duration,
                volume: 100,
                rate: rate,
                subtitlesOn: subtitlesOn,
                aspect: VideoAspect.original,
                skipSeconds: 10,
                formatDuration: formatHms,
                onSkipBack: () {},
                onSkipForward: () {},
                onPlayPause: () {},
                onSeek: (d) => seekCalls?.add(d),
                onVolume: (_) {},
                onMute: () {},
                onSubtitlesChanged: (v) => subtitleCalls?.add(v),
                onAspect: () {},
                onRate: (v) => rateCalls?.add(v),
                channelListOpen: false,
                onChannelList: isLive ? () {} : null,
                episodeListOpen: false,
                onEpisodeList: null,
                onNextEpisode: null,
                audioTracks: const [],
                currentAudioId: null,
                onSelectAudio: (_) {},
                showVolume: false, // Android: hardware keys own the volume
                primaryFocusNode: primaryNode,
              ),
            ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    debugDeviceModeOverride = DeviceMode.tv;
  });

  tearDown(() {
    debugDeviceModeOverride = null;
  });

  testWidgets('ogni controllo del player e\' raggiungibile col telecomando',
      (tester) async {
    // The reported bug: the right-hand side (velocita', sottotitoli, aspetto)
    // and the whole top bar (indietro, impostazioni) could not be reached.
    final node = FocusNode(debugLabel: 'primary');
    addTearDown(node.dispose);

    await tester.pumpWidget(_TestHost(
      builder: (_) => _chrome(primaryNode: node, onSettings: () {}),
    ));
    await tester.pump();

    node.requestFocus();
    await tester.pump();

    final labels = await _reachableLabels(tester);
    expect(
      labels,
      containsAll(<String>[
        'Indietro',
        'Impostazioni',
        'Pausa',
        'Velocità',
        'Sottotitoli',
        'Rapporto d\'aspetto',
      ]),
      reason: 'top bar and right-hand controls must all be reachable; '
          'reached: $labels',
    );
  });

  testWidgets('destra: dal play/pausa la freccia DESTRA arriva ai controlli '
      'di destra', (tester) async {
    final node = FocusNode(debugLabel: 'primary');
    addTearDown(node.dispose);

    await tester.pumpWidget(_TestHost(
      builder: (_) => _chrome(primaryNode: node, onSettings: () {}),
    ));
    await tester.pump();
    node.requestFocus();
    await tester.pump();
    expect(_focusedLabel(), 'Pausa');

    // Walk right across the bar: it must end on the right-hand controls.
    final seen = <String?>{};
    for (var i = 0; i < 8; i++) {
      await _press(tester, LogicalKeyboardKey.arrowRight);
      seen.add(_focusedLabel());
    }
    expect(seen, contains('Velocità'));
    expect(seen, contains('Sottotitoli'));
    expect(seen, contains('Rapporto d\'aspetto'));
  });

  testWidgets('alto: dai controlli la freccia SU arriva alla barra superiore',
      (tester) async {
    var back = 0;
    final node = FocusNode(debugLabel: 'primary');
    addTearDown(node.dispose);

    await tester.pumpWidget(_TestHost(
      builder: (_) => _chrome(
        primaryNode: node,
        onSettings: () {},
        onBack: () => back++,
      ),
    ));
    await tester.pump();
    node.requestFocus();
    await tester.pump();

    // Up from the controls: seek bar, then into the top bar.
    final seen = <String?>{};
    for (var i = 0; i < 4; i++) {
      await _press(tester, LogicalKeyboardKey.arrowUp);
      seen.add(_focusedLabel());
    }
    expect(seen, contains('Impostazioni'),
        reason: 'the top bar must be reachable going up; reached: $seen');

    // Then Left along the bar reaches Back — and OK on it actually fires.
    for (var i = 0; i < 4 && _focusedLabel() != 'Indietro'; i++) {
      await _press(tester, LogicalKeyboardKey.arrowLeft);
    }
    expect(_focusedLabel(), 'Indietro',
        reason: 'Left along the top bar must reach the back button');
    await _pressOk(tester);
    expect(back, 1);
  });

  group('funzioni e highlight', _functionAndHighlightTests);

  group('barra temporale', () {
    testWidgets('uno scattino sposta di pochi secondi, non a salti enormi',
        (tester) async {
      final seeks = <Duration>[];
      final node = FocusNode(debugLabel: 'primary');
      addTearDown(node.dispose);

      await tester.pumpWidget(_TestHost(
        builder: (_) => _chrome(
          primaryNode: node,
          seekCalls: seeks,
          position: const Duration(minutes: 30),
          duration: const Duration(hours: 2),
        ),
      ));
      await tester.pump();
      node.requestFocus();
      await tester.pump();

      // Up onto the seek bar.
      await _press(tester, LogicalKeyboardKey.arrowUp);
      expect(find.byType(SeekBar), findsOneWidget);

      // A single tap of Right: a fine step, NOT a percentage of a 2h film
      // (Slider's own key handling jumped ~12 minutes).
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();

      expect(seeks, isNotEmpty, reason: 'Right on the seek bar must seek');
      final delta = seeks.last - const Duration(minutes: 30);
      expect(delta.inSeconds, greaterThan(0));
      expect(delta.inSeconds, lessThanOrEqualTo(10),
          reason: 'a single press must be a small, precise step');
    });

    testWidgets('tenendo premuto accelera', (tester) async {
      final seeks = <Duration>[];
      final node = FocusNode(debugLabel: 'primary');
      addTearDown(node.dispose);

      await tester.pumpWidget(_TestHost(
        builder: (_) => _chrome(
          primaryNode: node,
          seekCalls: seeks,
          position: const Duration(minutes: 30),
          duration: const Duration(hours: 2),
        ),
      ));
      await tester.pump();
      node.requestFocus();
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.arrowUp);

      // Hold: key down + a run of repeats, like a remote held down.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      final firstStep = (seeks.last - const Duration(minutes: 30)).inSeconds;

      for (var i = 0; i < 12; i++) {
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();

      final steps = <int>[];
      for (var i = 1; i < seeks.length; i++) {
        steps.add((seeks[i] - seeks[i - 1]).inSeconds);
      }
      expect(steps.last, greaterThan(firstStep),
          reason: 'holding the key must speed the scrubbing up; steps: $steps');
    });

    testWidgets('la barra non esce dai limiti del video', (tester) async {
      final seeks = <Duration>[];
      final node = FocusNode(debugLabel: 'primary');
      addTearDown(node.dispose);

      await tester.pumpWidget(_TestHost(
        builder: (_) => _chrome(
          primaryNode: node,
          seekCalls: seeks,
          position: const Duration(seconds: 2),
          duration: const Duration(minutes: 10),
        ),
      ));
      await tester.pump();
      node.requestFocus();
      await tester.pump();
      await _press(tester, LogicalKeyboardKey.arrowUp);

      // Rewind past the start: must clamp at zero, never go negative.
      for (var i = 0; i < 6; i++) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
      }
      expect(seeks.every((d) => d >= Duration.zero), isTrue,
          reason: 'no negative seeks: $seeks');
    });

    testWidgets('su/giu\' lasciano la barra invece di restarci incastrati',
        (tester) async {
      final node = FocusNode(debugLabel: 'primary');
      addTearDown(node.dispose);

      await tester.pumpWidget(_TestHost(
        builder: (_) => _chrome(primaryNode: node, onSettings: () {}),
      ));
      await tester.pump();
      node.requestFocus();
      await tester.pump();

      await _press(tester, LogicalKeyboardKey.arrowUp); // onto the bar
      await _press(tester, LogicalKeyboardKey.arrowDown); // and off again
      expect(_focusedLabel(), isNotNull,
          reason: 'Down must move the focus back onto a labelled control');
    });
  });

  testWidgets('live: niente barra temporale ne\' velocita\'', (tester) async {
    final node = FocusNode(debugLabel: 'primary');
    addTearDown(node.dispose);

    await tester.pumpWidget(_TestHost(
      builder: (_) => _chrome(primaryNode: node, isLive: true, onSettings: () {}),
    ));
    await tester.pump();

    expect(find.byType(SeekBar), findsNothing);
    final labels = await _reachableLabels(tester);
    expect(labels, isNot(contains('Velocità')));
    expect(labels, contains('Impostazioni'));
  });
}

/// Gives the tree a TV-sized viewport so the bar layout matches a real screen.
class _TestHost extends StatelessWidget {
  const _TestHost({required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: const MediaQueryData(size: Size(1280, 720)),
      child: Builder(builder: builder),
    );
  }
}

/// Functions + highlighting of the player controls, driven by the remote.
/// Added on request ("crea un test per funzioni e highlight del player, ogni
/// volta ci sta un problema"): every control must (a) be reachable, (b) show
/// the white ring while the D-pad is on it, and (c) actually fire.
void _functionAndHighlightTests() {
  /// True when a focus ring is currently painted anywhere in the tree.
  bool ringVisible(WidgetTester tester) {
    for (final c in tester.widgetList<DecoratedBox>(
        find.byType(DecoratedBox))) {
      final d = c.decoration;
      if (d is BoxDecoration && d.border != null) {
        final side = (d.border as Border).top;
        if (side.color == AppColors.focusRing && side.width > 0) return true;
      }
    }
    return false;
  }

  testWidgets('ogni controllo mostra l\'anello bianco quando ci sei sopra',
      (tester) async {
    final node = FocusNode(debugLabel: 'primary');
    addTearDown(node.dispose);
    await tester.pumpWidget(_TestHost(
      builder: (_) => _chrome(primaryNode: node, onSettings: () {}),
    ));
    await tester.pump();
    node.requestFocus();
    await tester.pump();

    // Walk the whole bar; the ring must be painted at every single stop.
    // NB: the ring lands one frame after the focus does (the Focus widget
    // rebuilds its dependents on the next pump), so settle before looking.
    for (var i = 0; i < 6; i++) {
      await tester.pump();
      expect(ringVisible(tester), isTrue,
          reason: 'no focus ring on "${_focusedLabel()}" — on TV that reads as '
              '"non si capisce cosa ho selezionato"');
      await _press(tester, LogicalKeyboardKey.arrowRight);
    }
  });

  testWidgets('velocita\': e\' un menu a tendina e applica il valore scelto',
      (tester) async {
    final rates = <double>[];
    final node = FocusNode(debugLabel: 'primary');
    addTearDown(node.dispose);
    await tester.pumpWidget(_TestHost(
      builder: (_) => _chrome(primaryNode: node, rateCalls: rates, onSettings: () {}),
    ));
    await tester.pump();
    node.requestFocus();
    await tester.pump();

    // Reach the speed dropdown and open it with OK.
    for (var i = 0; i < 8 && _focusedLabel() != 'Velocità'; i++) {
      await _press(tester, LogicalKeyboardKey.arrowRight);
    }
    expect(_focusedLabel(), 'Velocità');
    await _pressOk(tester);
    await tester.pumpAndSettle();

    // A real menu, not a cycle button: every speed is listed.
    expect(find.text('0.5x'), findsOneWidget);
    expect(find.text('2x'), findsOneWidget);

    // The focus opens on the CURRENT value (1x); Down picks the next one.
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _pressOk(tester);
    await tester.pumpAndSettle();
    expect(rates, isNotEmpty, reason: 'picking an entry must set the speed');
    expect(rates.last, greaterThan(1.0));
  });

  testWidgets('sottotitoli: menu a tendina on/off', (tester) async {
    final subs = <bool>[];
    final node = FocusNode(debugLabel: 'primary');
    addTearDown(node.dispose);
    await tester.pumpWidget(_TestHost(
      builder: (_) =>
          _chrome(primaryNode: node, subtitleCalls: subs, onSettings: () {}),
    ));
    await tester.pump();
    node.requestFocus();
    await tester.pump();

    for (var i = 0; i < 8 && _focusedLabel() != 'Sottotitoli'; i++) {
      await _press(tester, LogicalKeyboardKey.arrowRight);
    }
    expect(_focusedLabel(), 'Sottotitoli');
    await _pressOk(tester);
    await tester.pumpAndSettle();

    expect(find.text('Sottotitoli on'), findsOneWidget);
    expect(find.text('Sottotitoli off'), findsWidgets);

    // Currently off → the focus sits on "off"; Down reaches "on".
    await _press(tester, LogicalKeyboardKey.arrowDown);
    await _pressOk(tester);
    await tester.pumpAndSettle();
    expect(subs.last, isTrue);
  });

  testWidgets('play/pausa, salti e aspetto sparano davvero', (tester) async {
    var play = 0, back = 0, fwd = 0, aspect = 0;
    final node = FocusNode(debugLabel: 'primary');
    addTearDown(node.dispose);

    await tester.pumpWidget(_TestHost(
      builder: (_) => ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(navigationMode: NavigationMode.directional),
                child: PlayerRootFocus(
                  onKeyEvent: (_, _) => KeyEventResult.ignored,
                  child: PlayerControlsPanel(
                    playing: true,
                    isLive: false,
                    position: const Duration(minutes: 1),
                    duration: const Duration(minutes: 10),
                    volume: 100,
                    rate: 1.0,
                    subtitlesOn: false,
                    aspect: VideoAspect.original,
                    skipSeconds: 10,
                    formatDuration: formatHms,
                    onSkipBack: () => back++,
                    onSkipForward: () => fwd++,
                    onPlayPause: () => play++,
                    onSeek: (_) {},
                    onVolume: (_) {},
                    onMute: () {},
                    onSubtitlesChanged: (_) {},
                    onAspect: () => aspect++,
                    onRate: (_) {},
                    channelListOpen: false,
                    onChannelList: null,
                    episodeListOpen: false,
                    onEpisodeList: null,
                    onNextEpisode: null,
                    audioTracks: const [],
                    currentAudioId: null,
                    onSelectAudio: (_) {},
                    showVolume: false,
                    primaryFocusNode: node,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    node.requestFocus();
    await tester.pump();

    // Play/pause is where the remote lands.
    await _pressOk(tester);
    expect(play, 1);

    // Left = rewind, right = forward.
    await _press(tester, LogicalKeyboardKey.arrowLeft);
    expect(_focusedLabel(), 'Indietro 10 s');
    await _pressOk(tester);
    expect(back, 1);

    await _press(tester, LogicalKeyboardKey.arrowRight, 2);
    expect(_focusedLabel(), 'Avanti 10 s');
    await _pressOk(tester);
    expect(fwd, 1);

    // And the aspect toggle at the far right.
    for (var i = 0; i < 6 && _focusedLabel() != 'Rapporto d\'aspetto'; i++) {
      await _press(tester, LogicalKeyboardKey.arrowRight);
    }
    await _pressOk(tester);
    expect(aspect, 1);
  });
}
