import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:broken_iptv/core/theme/app_theme.dart';
import 'package:broken_iptv/core/ui_mode.dart';
import 'package:broken_iptv/data/models/xtream_profile.dart';
import 'package:broken_iptv/data/services/device_mode_service.dart';
import 'package:broken_iptv/data/services/provisioning_service.dart';
import 'package:broken_iptv/data/services/storage_service.dart';
import 'package:broken_iptv/presentation/common/tv_focusable.dart';
import 'package:broken_iptv/presentation/screens/profiles/add_profile_screen.dart';

/// La via d'uscita per chi non sa compilare la playlist da solo: sotto al form
/// deve esserci la frase e il **codice** da leggere a chi gli ha dato l'app.
///
/// Sta lì e non in una schermata a parte perché è lì che la persona si blocca.
Widget _screen({XtreamProfile? existing}) => ProviderScope(
      child: MaterialApp(
        theme: AppTheme.dark,
        home: AddProfileScreen(existingProfile: existing),
      ),
    );

void main() {
  setUpAll(() async {
    final dir = Directory.systemTemp.createTempSync('broken_iptv_provisioning');
    await StorageService.init(testPath: dir.path);
  });

  setUp(() => debugDeviceModeOverride = DeviceMode.tv);
  tearDown(() => debugDeviceModeOverride = null);

  testWidgets('la prima playlist mostra la frase e il codice', (tester) async {
    await tester.pumpWidget(_screen());
    await tester.pump();

    expect(find.textContaining('Non riesci a compilarla da solo'), findsOneWidget);
    expect(find.textContaining('leggigli questo codice'), findsOneWidget);

    // Il codice va letto ad alta voce: deve essere quello vero, a gruppi.
    final code = DeviceCode.read();
    expect(find.text(DeviceCode.grouped(code)), findsOneWidget);
    expect(DeviceCode.grouped(code), matches(RegExp(r'^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$')));
  });

  testWidgets('il codice resta lo stesso a ogni apertura', (tester) async {
    // Se cambiasse, la persona leggerebbe un codice e il pannello ne
    // cercherebbe un altro.
    final first = DeviceCode.read();
    await tester.pumpWidget(_screen());
    await tester.pump();
    expect(find.text(DeviceCode.grouped(first)), findsOneWidget);
  });

  testWidgets('modificando una playlist esistente la frase non c\'è',
      (tester) async {
    // Chi sta modificando una playlist sa già cavarsela: lì sarebbe rumore.
    await tester.pumpWidget(_screen(
      existing: const XtreamProfile(
        id: 'x',
        name: 'La mia',
        host: 'http://esempio.tv',
        username: 'utente',
        kind: PlaylistKind.xtream,
      ),
    ));
    await tester.pump();

    expect(find.textContaining('Non riesci a compilarla da solo'), findsNothing);
  });

  testWidgets('il blocco del codice non è una fermata del telecomando',
      (tester) async {
    // È testo, non un pulsante: se prendesse il focus sarebbe uno stop che non
    // fa niente — il difetto che questo progetto ha già corretto sei volte.
    await tester.pumpWidget(_screen());
    await tester.pump();

    final code = DeviceCode.grouped(DeviceCode.read());
    expect(
      find.ancestor(of: find.text(code), matching: find.byType(TvFocusable)),
      findsNothing,
      reason: 'il codice deve essere testo, non un elemento selezionabile',
    );
    expect(
      find.ancestor(of: find.text(code), matching: find.byType(InkWell)),
      findsNothing,
      reason: 'nemmeno un ink Material: su Android sarebbe una fermata cieca',
    );
  });
}
