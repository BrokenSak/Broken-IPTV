import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:broken_iptv/core/theme/app_theme.dart';
import 'package:broken_iptv/core/ui_mode.dart';
import 'package:broken_iptv/data/models/xtream_profile.dart';
import 'package:broken_iptv/data/services/device_mode_service.dart';
import 'package:broken_iptv/data/services/storage_service.dart';
import 'package:broken_iptv/presentation/common/tv_focusable.dart';
import 'package:broken_iptv/presentation/screens/settings/settings_screen.dart';

/// The persistent focus ring must appear ONLY where a remote drives the UI.
/// The reported bug: on the phone the first item stayed ringed and touch
/// couldn't clear it. A node may still take focus on a phone (the remote has
/// to work even if the mode is wrong), but it must look no different.
/// The ring is an overlay drawn OUTSIDE the child, and it is only built while
/// focus is actually shown — so "no ring" now means "no ring widget at all",
/// not "a transparent border".
Color? _ringColor(WidgetTester tester) {
  for (final box in tester.widgetList<DecoratedBox>(
      find.descendant(
        of: find.byType(TvFocusable),
        matching: find.byType(DecoratedBox),
      ))) {
    final d = box.decoration;
    if (d is BoxDecoration && d.border != null) return (d.border as Border).top.color;
  }
  return null;
}

Widget _wrap(FocusNode node) => MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: Center(
          child: TvFocusable(
            focusNode: node,
            autofocus: true,
            onTap: () {},
            child: const SizedBox(width: 80, height: 40),
          ),
        ),
      ),
    );

/// The rect of the first [DecoratedBox] under [scope] whose decoration passes
/// [matches] — used to compare the ring with the surface it is framing.
///
/// With [self] the scope IS the set of boxes (e.g. a `find.ancestor` result)
/// rather than a subtree to search.
Rect _decoratedRect(
  WidgetTester tester,
  Finder scope, {
  required bool Function(BoxDecoration) matches,
  String describe = 'decorated box',
  bool self = false,
}) {
  final boxes = self
      ? scope
      : find.descendant(of: scope, matching: find.byType(DecoratedBox));
  final widgets = tester.widgetList<DecoratedBox>(boxes).toList();
  for (var i = 0; i < widgets.length; i++) {
    final decoration = widgets[i].decoration;
    if (decoration is BoxDecoration && matches(decoration)) {
      return tester.getRect(boxes.at(i));
    }
  }
  fail('no $describe found');
}

void main() {
  // ⚠️ Outside testWidgets: init does real file IO, and awaiting that under the
  // widget tests' fake clock never resumes (the test just hangs).
  setUpAll(() async {
    final dir = Directory.systemTemp.createTempSync('broken_iptv_ring_test');
    await StorageService.init(testPath: dir.path);
  });

  tearDown(() => debugDeviceModeOverride = null);

  testWidgets('TV mode: a focused tile shows the focus ring', (tester) async {
    debugDeviceModeOverride = DeviceMode.tv;
    final node = FocusNode();
    addTearDown(node.dispose);

    await tester.pumpWidget(_wrap(node));
    await tester.pumpAndSettle();

    expect(node.hasPrimaryFocus, isTrue, reason: 'autofocus lands on TV');
    expect(_ringColor(tester), AppColors.focusRing);
  });

  testWidgets('phone (touch): a focused tile shows NO ring', (tester) async {
    debugDeviceModeOverride = DeviceMode.touch;
    final node = FocusNode();
    addTearDown(node.dispose);

    await tester.pumpWidget(_wrap(node));
    await tester.pumpAndSettle();
    // Autofocus is off on touch; focus it by hand to prove that even a
    // genuinely-focused node stays invisible.
    node.requestFocus();
    await tester.pumpAndSettle();

    expect(node.hasPrimaryFocus, isTrue);
    expect(_ringColor(tester), isNull,
        reason: 'no persistent ring on a phone — only touch feedback');
  });

  testWidgets('playlist: the ring frames exactly the box it highlights',
      (tester) async {
    // Reported: "il quadrato dell'highlight della playlist è più piccolo del
    // quadrato stesso". The white surface was the whole ROW while the select
    // stop covered only the name — modifica/elimina sat on the same fill — so
    // the ring came out narrower than the thing it was supposed to frame.
    debugDeviceModeOverride = DeviceMode.tv;
    // Hive writes go through runAsync: real IO never resumes under the widget
    // tests' fake clock (a HANDOFF lesson, learned twice).
    await tester.runAsync(() => StorageService.profilesBox.put(
          'p1',
          const XtreamProfile(
            id: 'p1',
            name: 'Casa',
            host: 'http://fake-host',
            username: 'u',
          ).toMap(),
        ));
    addTearDown(() => StorageService.profilesBox.clear());

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: AppTheme.dark,
        home: const SettingsScreen(),
        // As on Android (app.dart).
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(navigationMode: NavigationMode.directional),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    ));
    // Bounded settle: the account section keeps a spinner alive forever here.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    final selectStop =
        find.ancestor(of: find.text('Casa'), matching: find.byType(TvFocusable));
    expect(selectStop, findsOneWidget,
        reason: 'the playlist name must sit in its own focus stop');
    expect(Focus.of(tester.element(find.text('Casa'))).hasPrimaryFocus, isFalse,
        reason: 'sanity: the text itself is not the focus node');

    // The visible surface behind the name: its innermost filled ancestor.
    // Deliberately searched from the TEXT outwards, not inside the focus stop —
    // in the broken layout that surface was the whole row, an ANCESTOR of the
    // stop, and this is what makes the mismatch measurable here.
    final surface = _decoratedRect(
      tester,
      find.ancestor(of: find.text('Casa'), matching: find.byType(DecoratedBox)),
      matches: (d) => d.color != null,
      describe: 'the playlist surface',
      self: true,
    );
    final ring = _decoratedRect(
      tester,
      selectStop,
      // The ring is border-only — no fill (a BoxShadow/fill would leak inside).
      matches: (d) => d.color == null && d.border != null,
      describe: 'the focus ring',
    );

    expect(ring.center.dx, moreOrLessEquals(surface.center.dx, epsilon: 0.5));
    expect(ring.center.dy, moreOrLessEquals(surface.center.dy, epsilon: 0.5));
    final outsetX = (ring.width - surface.width) / 2;
    final outsetY = (ring.height - surface.height) / 2;
    expect(outsetX, greaterThan(0),
        reason: 'the ring stands OUTSIDE the element, never on its edge');
    expect(outsetY, moreOrLessEquals(outsetX, epsilon: 0.5),
        reason: 'same stand-off on every side, or the corners never agree');
  });
}
