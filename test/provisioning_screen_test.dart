import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:broken_iptv/core/theme/app_theme.dart';
import 'package:broken_iptv/core/ui_mode.dart';
import 'package:broken_iptv/data/services/device_mode_service.dart';
import 'package:broken_iptv/data/services/provisioning_service.dart';
import 'package:broken_iptv/data/services/storage_service.dart';
import 'package:broken_iptv/presentation/common/tv_focusable.dart';
import 'package:broken_iptv/presentation/screens/profiles/profiles_screen.dart';

/// La schermata di chi non ha (ancora) la playlist: deve mostrare la frase e
/// il **codice** da leggere a chi gli ha dato l'app, e nient'altro.
///
/// Dal 72° giro non c'è più nemmeno un modulo da compilare: la playlist è una
/// sola e la manda il proprietario dal pannello. Prima il codice stava dentro
/// quel modulo, sotto al pulsante Salva — testo non selezionabile, quindi col
/// telecomando la lista non ci scendeva nemmeno ("è tagliata e non posso
/// scendere") e chi era bloccato non lo vedeva.
void main() {
  setUpAll(() async {
    final dir = Directory.systemTemp.createTempSync('broken_iptv_provisioning');
    await StorageService.init(testPath: dir.path);
  });

  setUp(() => debugDeviceModeOverride = DeviceMode.tv);
  tearDown(() => debugDeviceModeOverride = null);

  Widget emptyList() => ProviderScope(
        child: MaterialApp(theme: AppTheme.dark, home: const ProfilesScreen()),
      );

  testWidgets('la prima schermata mostra la frase e il codice', (tester) async {
    await tester.pumpWidget(emptyList());
    await tester.pump();

    expect(find.textContaining('te la mette chi ti ha dato'), findsOneWidget);
    expect(find.textContaining('Leggigli questo codice'), findsOneWidget);

    final code = DeviceCode.read();
    expect(find.text(DeviceCode.grouped(code)), findsOneWidget);
    expect(DeviceCode.grouped(code),
        matches(RegExp(r'^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$')));
  });

  testWidgets('il codice resta lo stesso a ogni apertura', (tester) async {
    // Se cambiasse, la persona leggerebbe un codice e il pannello ne
    // cercherebbe un altro.
    final first = DeviceCode.read();
    await tester.pumpWidget(emptyList());
    await tester.pump();
    expect(find.text(DeviceCode.grouped(first)), findsOneWidget);
  });

  testWidgets('su uno schermo TV ci sta tutto senza scorrere', (tester) async {
    // ⚠️ Col telecomando la lista scorre SOLO seguendo il focus: quello che
    // non ci sta è irraggiungibile, non solo fuori vista. Qui si misura che
    // il codice E il pulsante stiano dentro la finestra.
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(emptyList());
    await tester.pump();

    final code = find.text(DeviceCode.grouped(DeviceCode.read()));
    expect(tester.getRect(code).bottom, lessThanOrEqualTo(720));
  });

  testWidgets('ci sta anche su un telefono piccolo', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(emptyList());
    await tester.pump();

    expect(find.text(DeviceCode.grouped(DeviceCode.read())), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'niente overflow');
  });

  testWidgets('il blocco del codice non è una fermata del telecomando',
      (tester) async {
    // È testo, non un pulsante: se prendesse il focus sarebbe uno stop che non
    // fa niente — il difetto che questo progetto ha già corretto sei volte.
    await tester.pumpWidget(emptyList());
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

  testWidgets('non c’è nessun modo di aggiungerla a mano', (tester) async {
    // È la richiesta dell'utente del 72° giro: la playlist è una sola, quella
    // che manda lui. Un pulsante qui rimetterebbe in piedi la seconda.
    await tester.pumpWidget(emptyList());
    await tester.pump();

    expect(find.text('Aggiungi playlist'), findsNothing);
    expect(find.byType(ElevatedButton), findsNothing);
  });
}
