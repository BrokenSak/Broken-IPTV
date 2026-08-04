// Regression tests for "da TV premo OK e non succede niente, da qualsiasi
// schermata".
//
// Both cases are the same Flutter behaviour: when the widget holding the focus
// leaves the tree, the focus is NOT handed to a neighbour — the enclosing scope
// keeps it with no focused child. A mouse or a finger doesn't care, so this is
// invisible on Windows and on the phone; a D-pad has nothing to aim at and OK
// stops doing anything at all.
//
// It happens for real in two places:
//   1. a catalog pane empties out on its own (closing the player writes
//      progress, which can take the very tile you were on out of "Continua a
//      guardare" — a film crossing 95% is finished, so it leaves — and the
//      post-player sync then invalidates those providers on top);
//   2. the player's own controls auto-hide into an ExcludeFocus.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:broken_iptv/presentation/common/dpad_focus_guard.dart';
import 'package:broken_iptv/presentation/common/tv_focusable.dart';
import 'package:broken_iptv/presentation/screens/player/player_controls.dart';

// ─────────────────────────── a catalog pane ───────────────────────────

class _Pane extends StatefulWidget {
  const _Pane({super.key, required this.guard});
  final bool guard;
  @override
  State<_Pane> createState() => _PaneState();
}

class _PaneState extends State<_Pane> {
  List<String> items = ['A', 'B', 'C'];
  String? tapped;

  void setItems(List<String> next) => setState(() => items = next);

  @override
  Widget build(BuildContext context) {
    // Mirrors _VodContinue / _VodFavorites: an empty list replaces the whole
    // grid with a message, so every tile (and its focus node) is destroyed.
    final body = items.isEmpty
        ? const Center(child: Text('Niente da riprendere.'))
        : Column(
            children: [
              if (tapped != null) Text('TAPPED $tapped'),
              for (final i in items)
                TvFocusable(
                    onTap: () => setState(() => tapped = i), child: Text(i)),
            ],
          );
    return Scaffold(body: widget.guard ? DpadFocusGuard(child: body) : body);
  }
}

Future<void> _ok(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

// ─────────────────────────── the player shell ───────────────────────────

class _PlayerShell extends StatefulWidget {
  const _PlayerShell({super.key});
  @override
  State<_PlayerShell> createState() => _PlayerShellState();
}

class _PlayerShellState extends State<_PlayerShell> {
  final FocusNode primary = FocusNode(debugLabel: 'player.primary');
  final FocusNode root = FocusNode(debugLabel: 'player.root');
  bool controlsVisible = true;
  int rootKeys = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => primary.requestFocus());
  }

  @override
  void dispose() {
    primary.dispose();
    root.dispose();
    super.dispose();
  }

  /// The real _hideControls + _claimRootFocus pair.
  void hideControls() {
    setState(() => controlsVisible = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !controlsVisible && !root.hasPrimaryFocus) root.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PlayerRootFocus(
        focusNode: root,
        onKeyEvent: (_, e) {
          if (e is KeyDownEvent) setState(() => rootKeys++);
          return KeyEventResult.handled;
        },
        child: Stack(
          children: [
            Text('rootKeys=$rootKeys'),
            ExcludeFocus(
              excluding: !controlsVisible,
              child: TvFocusable(
                focusNode: primary,
                onTap: () {},
                child: const Text('play'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  setUp(() {
    TvFocusable.debugDpadOverride = true;
    DpadFocusGuard.debugEnabledOverride = true;
  });
  tearDown(() {
    TvFocusable.debugDpadOverride = null;
    DpadFocusGuard.debugEnabledOverride = null;
  });

  group('a pane that empties out must not kill the remote', () {
    testWidgets('without the guard OK is dead (the reported bug)',
        (tester) async {
      final key = GlobalKey<_PaneState>();
      await tester.pumpWidget(MaterialApp(home: _Pane(key: key, guard: false)));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      key.currentState!.setItems(const []);
      await tester.pump();
      key.currentState!.setItems(['A', 'B', 'C']); // the list comes back
      await tester.pump();

      await _ok(tester);
      expect(find.textContaining('TAPPED'), findsNothing,
          reason: 'this is the behaviour DpadFocusGuard exists to fix');
    });

    testWidgets('with the guard OK keeps working', (tester) async {
      final key = GlobalKey<_PaneState>();
      await tester.pumpWidget(MaterialApp(home: _Pane(key: key, guard: true)));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      key.currentState!.setItems(const []);
      await tester.pump();
      key.currentState!.setItems(['A', 'B', 'C']);
      await tester.pump();
      await tester.pump();

      expect(FocusManager.instance.primaryFocus, isNot(isA<FocusScopeNode>()),
          reason: 'the guard must re-home the focus');
      await _ok(tester);
      expect(find.textContaining('TAPPED'), findsOneWidget,
          reason: 'REGRESSION: OK dead after the pane emptied out');
    });

    testWidgets('losing only the focused tile keeps the focus alive',
        (tester) async {
      final key = GlobalKey<_PaneState>();
      await tester.pumpWidget(MaterialApp(home: _Pane(key: key, guard: true)));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // A -> B
      await tester.pump();

      key.currentState!.setItems(['A', 'C']);
      await tester.pump();
      await tester.pump();

      await _ok(tester);
      expect(find.textContaining('TAPPED'), findsOneWidget);
    });
  });

  group('the player must stay reachable once the controls hide', () {
    testWidgets('a key still reaches the root handler', (tester) async {
      final key = GlobalKey<_PlayerShellState>();
      await tester.pumpWidget(MaterialApp(home: _PlayerShell(key: key)));
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'player.primary');

      key.currentState!.hideControls(); // the 5s auto-hide
      await tester.pump();
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pump();

      expect(key.currentState!.rootKeys, greaterThan(0),
          reason: 'REGRESSION: with the controls hidden the player went deaf — '
              'OK could not even bring the menu back');
    });
  });
}
