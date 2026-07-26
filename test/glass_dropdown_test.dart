import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:broken_iptv/core/theme/app_theme.dart';
import 'package:broken_iptv/presentation/common/glass_dropdown.dart';
import 'package:broken_iptv/presentation/common/tv_focusable.dart';

/// Simulated-remote tests for the glass dropdown (season picker in the player
/// overlays, category picker in the channel list, seasons in series detail).
///
/// Regression: the first version used InkWell + MenuItemButton — on TV the
/// focus was invisible (transparent highlight + NoSplash) and the D-pad could
/// not visibly land on the menu entries, which read as "not selectable".
void main() {
  Future<void> pressOk(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
  }

  Widget harness({required ValueChanged<int> onChanged}) {
    return MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TvFocusable(
                autofocus: true,
                onTap: () {},
                child: const SizedBox(width: 200, height: 40, child: Text('sopra')),
              ),
              const SizedBox(height: 8),
              _DropdownHost(onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }

  group('TV (D-pad)', () {
    setUp(() => TvFocusable.debugDpadOverride = true);
    tearDown(() => TvFocusable.debugDpadOverride = null);

    testWidgets('OK opens the menu and the focus lands on the current entry',
        (tester) async {
      int? picked;
      await tester.pumpWidget(harness(onChanged: (v) => picked = v));
      await tester.pumpAndSettle();

      // Down from the tile above: the dropdown trigger takes focus.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      // OK: the menu opens (the current label now appears twice: trigger + entry).
      await pressOk(tester);
      expect(find.text('Stagione 2'), findsNWidgets(2),
          reason: 'OK on the trigger must open the menu');
      expect(find.text('Stagione 1'), findsOneWidget);
      expect(find.text('Stagione 3'), findsOneWidget);

      // The current entry (Stagione 2) autofocuses: OK re-picks it and closes.
      await pressOk(tester);
      expect(picked, 2,
          reason: 'the focus must land on the CURRENT entry when the menu opens');
      expect(find.text('Stagione 1'), findsNothing,
          reason: 'picking an entry must close the menu');
    });

    testWidgets('arrows move between the entries, OK picks one', (tester) async {
      int? picked;
      await tester.pumpWidget(harness(onChanged: (v) => picked = v));
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // → trigger
      await tester.pump();
      await pressOk(tester); // menu open, focus on "Stagione 2"

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown); // → Stagione 3
      await tester.pumpAndSettle();
      await pressOk(tester);

      expect(picked, 3);
      // The trigger label follows the selection.
      expect(find.text('Stagione 3'), findsOneWidget);
      expect(find.text('Stagione 2'), findsNothing);
    });
  });

  group('mouse/touch (no D-pad)', () {
    setUp(() => TvFocusable.debugDpadOverride = false);
    tearDown(() => TvFocusable.debugDpadOverride = null);

    testWidgets('tap opens the menu, tap on an entry picks it', (tester) async {
      int? picked;
      await tester.pumpWidget(harness(onChanged: (v) => picked = v));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Stagione 2'));
      await tester.pumpAndSettle();
      expect(find.text('Stagione 1'), findsOneWidget, reason: 'menu open');

      await tester.tap(find.text('Stagione 1'));
      await tester.pumpAndSettle();
      expect(picked, 1);
      expect(find.text('Stagione 3'), findsNothing, reason: 'menu closed');
    });
  });
}

/// Keeps the selected value in local state so the trigger label updates,
/// like the real callers do.
class _DropdownHost extends StatefulWidget {
  const _DropdownHost({required this.onChanged});

  final ValueChanged<int> onChanged;

  @override
  State<_DropdownHost> createState() => _DropdownHostState();
}

class _DropdownHostState extends State<_DropdownHost> {
  int _value = 2;

  @override
  Widget build(BuildContext context) {
    return GlassDropdown<int>(
      value: _value,
      onChanged: (v) {
        setState(() => _value = v);
        widget.onChanged(v);
      },
      items: [
        for (final s in const [1, 2, 3])
          GlassDropdownEntry(value: s, label: 'Stagione $s', trailing: '$s ep.'),
      ],
    );
  }
}
