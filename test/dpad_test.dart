import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:broken_iptv/presentation/common/tv_focusable.dart';
import 'package:broken_iptv/presentation/common/tv_text_field.dart';

/// Simulated D-pad tests: widget tests run on the dev host (Windows), so the
/// TV behavior is forced through the debug overrides.
void main() {
  setUp(() {
    TvFocusable.debugDpadOverride = true; // behave like Android TV
    TvTextFormField.debugTvModeOverride = true;
  });

  tearDown(() {
    TvFocusable.debugDpadOverride = null;
    TvTextFormField.debugTvModeOverride = null;
  });

  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  testWidgets('TvFocusable: OK (select) activates the focused tile',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(wrap(TvFocusable(
      autofocus: true,
      onTap: () => taps++,
      child: const SizedBox(width: 100, height: 40, child: Text('tile')),
    )));
    await tester.pump();

    // DPAD_CENTER arrives as LogicalKeyboardKey.select: down then up = tap.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(taps, 1);

    // Enter must work too (some remotes/gamepads report it).
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(taps, 2);
  });

  testWidgets('TvFocusable: holding OK fires onLongPress, not onTap',
      (tester) async {
    var taps = 0;
    var longPresses = 0;
    await tester.pumpWidget(wrap(TvFocusable(
      autofocus: true,
      onTap: () => taps++,
      onLongPress: () => longPresses++,
      child: const SizedBox(width: 100, height: 40, child: Text('tile')),
    )));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    for (var i = 0; i < 6; i++) {
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(longPresses, 1, reason: 'one long-press per hold');
    expect(taps, 0, reason: 'a hold must not also fire the tap');
  });

  testWidgets('TvFocusable: a firm press (one key repeat) is still a TAP',
      (tester) async {
    // Regression: Android starts repeating ~400ms into a press, so a normal
    // firm press on a TV remote emitted ONE repeat — which used to fire the
    // long-press and swallow the tap. On a catalog tile that meant OK
    // silently toggled the favourite and the player never opened
    // ("se premo ok da telecomando non apre il player, non reagisce").
    var taps = 0;
    var longPresses = 0;
    await tester.pumpWidget(wrap(TvFocusable(
      autofocus: true,
      onTap: () => taps++,
      onLongPress: () => longPresses++,
      child: const SizedBox(width: 100, height: 40, child: Text('tile')),
    )));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(taps, 1, reason: 'a firm press must still open the item');
    expect(longPresses, 0, reason: 'one repeat is not a deliberate hold');
  });

  testWidgets('TvFocusable: without D-pad support (Windows) nothing takes focus',
      (tester) async {
    // On Windows arrows are disabled app-wide and tiles are mouse-only: the
    // node must be invisible to the focus system. (Phone touch mode instead
    // keeps nodes focusABLE but ignores autofocus — covered by the policy
    // tests in ui_mode_test.dart.)
    TvFocusable.debugDpadOverride = false;
    final node = FocusNode();
    addTearDown(node.dispose);

    await tester.pumpWidget(wrap(TvFocusable(
      focusNode: node,
      autofocus: true,
      onTap: () {},
      child: const SizedBox(width: 100, height: 40),
    )));
    await tester.pumpAndSettle();
    expect(node.hasFocus, isFalse, reason: 'autofocus must be ignored');

    node.requestFocus();
    await tester.pumpAndSettle();
    expect(node.hasFocus, isFalse, reason: 'the node must not be focusable at all');
  });

  testWidgets('TvFocusable: a focused tile does not grow', (tester) async {
    // Focus used to scale the tile up, which made it spill over its
    // neighbours and overlap their captions (reported on TV).
    final node = FocusNode();
    addTearDown(node.dispose);
    const childKey = Key('tile-child');

    await tester.pumpWidget(wrap(TvFocusable(
      focusNode: node,
      onTap: () {},
      child: const SizedBox(key: childKey, width: 120, height: 60),
    )));
    await tester.pump();
    final unfocused = tester.getRect(find.byKey(childKey));

    node.requestFocus();
    await tester.pumpAndSettle();

    expect(tester.getRect(find.byKey(childKey)), unfocused,
        reason: 'the focus ring must not resize/move the tile');
  });

  testWidgets(
      'TvFocusable: a widget nested inside it can never take the focus',
      (tester) async {
    // This asserted the OPPOSITE until the 64th round: a nested IconButton kept
    // its own focus and OK went to it. That design is gone — an inner Material
    // control is a stop the D-pad cannot see (no ring with this theme) and, on
    // Android's `NavigationMode.directional`, ink surfaces are focusable even
    // with no callbacks at all, so the nesting produced dead stops on plain
    // captions. Actions that must be reachable are SIBLINGS now (see
    // IconAction and the playlist rows), and TvFocusable excludes its subtree.
    var tileTaps = 0;
    var buttonTaps = 0;
    final tileFocus = FocusNode();
    final buttonFocus = FocusNode();
    addTearDown(tileFocus.dispose);
    addTearDown(buttonFocus.dispose);

    await tester.pumpWidget(wrap(MediaQuery(
      // As on Android, where this is what makes bare ink surfaces focusable.
      data: const MediaQueryData(navigationMode: NavigationMode.directional),
      child: TvFocusable(
        focusNode: tileFocus,
        onTap: () => tileTaps++,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('tile'),
          IconButton(
            focusNode: buttonFocus,
            icon: const Icon(Icons.edit),
            onPressed: () => buttonTaps++,
          ),
        ]),
      ),
    )));

    buttonFocus.requestFocus();
    await tester.pump();
    expect(buttonFocus.hasPrimaryFocus, isFalse,
        reason: 'an inner control must not be able to hold the D-pad focus');

    // OK therefore always reaches the tile, wherever the ring happens to be.
    tileFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(tileTaps, 1);
    expect(buttonTaps, 0);

    // ...and the pointer still works: ExcludeFocus takes focus away, not taps.
    await tester.tap(find.byIcon(Icons.edit));
    await tester.pump();
    expect(buttonTaps, 1);
  });

  testWidgets(
      'TvTextFormField: arrows skip over the field, OK enters editing, '
      'Down leaves it', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final tileFocus = FocusNode();
    addTearDown(tileFocus.dispose);

    await tester.pumpWidget(wrap(Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TvFocusable(
          autofocus: true,
          focusNode: tileFocus,
          onTap: () {},
          child: const SizedBox(width: 100, height: 40, child: Text('above')),
        ),
        TvTextFormField(controller: controller),
      ],
    )));
    await tester.pump();
    expect(tileFocus.hasPrimaryFocus, isTrue);

    // Down from the tile: focus lands on the field's NAVIGATION wrapper, not
    // inside the editable text (no keyboard popping up while browsing).
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    expect(editable.widget.focusNode.hasPrimaryFocus, isFalse,
        reason: 'browsing must not enter the editable field');

    // OK: now we are editing.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(editable.widget.focusNode.hasPrimaryFocus, isTrue,
        reason: 'OK must start editing');

    // Down while editing: back to navigation (field loses primary focus).
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(editable.widget.focusNode.hasPrimaryFocus, isFalse,
        reason: 'Down must leave editing and resume navigation');
  });
}
