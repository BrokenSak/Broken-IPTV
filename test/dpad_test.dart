import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:broken_iptv/presentation/common/tv_focusable.dart';
import 'package:broken_iptv/presentation/common/tv_text_field.dart';

/// Simulated D-pad tests: widget tests run on the dev host (Windows), so the
/// TV behavior is forced through the debug overrides.
void main() {
  setUp(() {
    TvFocusable.debugIsDesktopOverride = false; // behave like Android TV
    TvTextFormField.debugTvModeOverride = true;
  });

  tearDown(() {
    TvFocusable.debugIsDesktopOverride = null;
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
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(longPresses, 1, reason: 'one long-press per hold');
    expect(taps, 0, reason: 'a hold must not also fire the tap');
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
      'TvFocusable: OK on an inner focused button activates the button, '
      'not the tile', (tester) async {
    var tileTaps = 0;
    var buttonTaps = 0;
    final buttonFocus = FocusNode();
    addTearDown(buttonFocus.dispose);

    await tester.pumpWidget(wrap(TvFocusable(
      onTap: () => tileTaps++,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Text('tile'),
        IconButton(
          focusNode: buttonFocus,
          icon: const Icon(Icons.edit),
          onPressed: () => buttonTaps++,
        ),
      ]),
    )));
    buttonFocus.requestFocus();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(buttonTaps, 1);
    expect(tileTaps, 0);
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
