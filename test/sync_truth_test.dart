import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:broken_iptv/data/models/xtream_profile.dart';
import 'package:broken_iptv/data/repositories/profile_repository.dart';
import 'package:broken_iptv/data/services/storage_service.dart';
import 'package:broken_iptv/data/services/sync_service.dart';
import 'package:broken_iptv/presentation/screens/settings/settings_screen.dart';
import 'package:broken_iptv/state/profile_providers.dart';
import 'package:broken_iptv/state/sync_providers.dart';

import 'profile_flow_test.dart' show FakeSecureCredentialsService;

/// **"Attiva" deve voler dire che funziona.**
///
/// Segnalato dall'utente all'81° giro: «Sincronizzazione dice attiva anche
/// quando non è effettivamente attiva». Diceva Attiva perché il dispositivo
/// aveva un codice salvato — l'unica cosa che non dipende da nessuno — mentre
/// il server poteva rispondere 403 a ogni giro (l'interruttore dell'utenza è
/// spento, oppure il codice non è in elenco).
///
/// Qui si fissano le due metà del rimedio: la regola pura che decide cosa dire,
/// e la reazione al rifiuto — il codice si butta via, perché è il pannello a
/// comandare (§7) e tenerselo vorrebbe dire ripresentarsi a ogni avvio per
/// farsi dire di no un'altra volta.
class _ServizioCheRifiuta extends SyncService {
  _ServizioCheRifiuta(this.reason);

  final String reason;
  int chiamate = 0;

  @override
  Future<Map<String, dynamic>?> fetch({
    required String endpoint,
    required String code,
  }) async {
    chiamate++;
    throw SyncNotAllowedException(reason);
  }
}

class _ServizioRotto extends SyncService {
  @override
  Future<Map<String, dynamic>?> fetch({
    required String endpoint,
    required String code,
  }) async {
    throw const SocketException('niente rete');
  }
}

class _ServizioCheVa extends SyncService {
  @override
  Future<Map<String, dynamic>?> fetch({
    required String endpoint,
    required String code,
  }) async =>
      null;

  @override
  Future<void> push({
    required String endpoint,
    required String code,
    required Map<String, dynamic> blob,
  }) async {}
}

void main() {
  setUpAll(() async {
    final dir = Directory.systemTemp.createTempSync('broken_iptv_sync_truth');
    await StorageService.init(testPath: dir.path);
  });

  setUp(() async {
    await StorageService.prefsBox.clear();
    for (final k in StorageService.profilesBox.keys.toList()) {
      await StorageService.profilesBox.delete(k);
    }
  });

  group('la regola (pura)', () {
    test('un codice in tasca NON basta a dirla attiva', () {
      // È esattamente il difetto segnalato: codice salvato, nessun giro
      // riuscito, e la schermata diceva "Attiva".
      expect(
        syncTruth(hasCode: true, outcome: SyncOutcome.mai, lastSyncAt: null),
        SyncTruth.maiRiuscita,
      );
    });

    test('rifiutata dal server = spenta dal pannello, anche dopo aver perso il codice', () {
      for (final hasCode in [true, false]) {
        expect(
          syncTruth(
            hasCode: hasCode,
            outcome: SyncOutcome.rifiutata,
            lastSyncAt: DateTime(2026, 8, 11),
          ),
          SyncTruth.spentaDalPannello,
          reason: 'il motivo va detto anche quando il codice è già stato buttato',
        );
      }
    });

    test('senza codice e senza rifiuti: non l\'ha accesa nessuno', () {
      expect(
        syncTruth(hasCode: false, outcome: SyncOutcome.mai, lastSyncAt: null),
        SyncTruth.spenta,
      );
    });

    test('ha funzionato ma l\'ultimo tentativo no: non è attiva', () {
      expect(
        syncTruth(
          hasCode: true,
          outcome: SyncOutcome.fallita,
          lastSyncAt: DateTime(2026, 8, 11),
        ),
        SyncTruth.nonRiuscita,
      );
    });

    test('attiva solo con un giro completo riuscito', () {
      expect(
        syncTruth(
          hasCode: true,
          outcome: SyncOutcome.ok,
          lastSyncAt: DateTime(2026, 8, 11),
        ),
        SyncTruth.attiva,
      );
    });
  });

  group('reazione del dispositivo', () {
    ProviderContainer containerCon(SyncService servizio) {
      final container = ProviderContainer(overrides: [
        syncServiceProvider.overrideWithValue(servizio),
      ]);
      addTearDown(container.dispose);
      return container;
    }

    test('un 403 spegne la sincronizzazione e se ne ricorda il motivo', () async {
      final container = containerCon(_ServizioCheRifiuta('sync_disabled'));
      container.read(syncProvider.notifier).setCode('ABCDEFGHJKLM');
      expect(container.read(syncProvider).enabled, isTrue);

      await container.read(syncProvider.notifier).syncNow();

      final state = container.read(syncProvider);
      expect(state.enabled, isFalse, reason: 'il codice si butta: comanda il pannello');
      expect(state.truth, SyncTruth.spentaDalPannello);
      expect(state.error, isNotNull);
    });

    test('il motivo sopravvive al riavvio dell\'app', () async {
      final primo = containerCon(_ServizioCheRifiuta('sync_disabled'));
      primo.read(syncProvider.notifier).setCode('ABCDEFGHJKLM');
      await primo.read(syncProvider.notifier).syncNow();

      // Un container nuovo = l'app riaperta: legge solo quello che è stato
      // scritto nelle prefs.
      final dopo = ProviderContainer();
      addTearDown(dopo.dispose);
      expect(dopo.read(syncProvider).truth, SyncTruth.spentaDalPannello);
    });

    test('una caduta di rete NON butta il codice, ma non la dice attiva', () async {
      final container = containerCon(_ServizioRotto());
      container.read(syncProvider.notifier).setCode('ABCDEFGHJKLM');

      await container.read(syncProvider.notifier).syncNow();

      final state = container.read(syncProvider);
      expect(state.enabled, isTrue, reason: 'la rete torna, il codice serve ancora');
      expect(state.truth, SyncTruth.maiRiuscita);
    });

    test('un giro riuscito la dice attiva', () async {
      final container = containerCon(_ServizioCheVa());
      container.read(syncProvider.notifier).setCode('ABCDEFGHJKLM');

      await container.read(syncProvider.notifier).syncNow();

      expect(container.read(syncProvider).truth, SyncTruth.attiva);
    });
  });

  testWidgets('Impostazioni: si legge il nome utente, mai il nome del pannello',
      (tester) async {
    // Richiesta dell'utente (81° giro): «Il nome che do io sul pannello non
    // deve apparire, deve apparire solo il nome dell'utenza che usano».
    // Il nome del profilo è un'etichetta scritta dal proprietario e arriva sul
    // dispositivo insieme alla playlist: sullo schermo di chi guarda non ci
    // deve stare.
    // ⚠️ Dentro runAsync: una scrittura Hive attesa sotto l'orologio finto dei
    // widget test non riprende più e il test resta appeso (ci è cascato anche
    // questo, 10 minuti di timeout).
    await tester.runAsync(() async {
      await StorageService.prefsBox.clear();
      final repo = ProfileRepository(FakeSecureCredentialsService());
      await repo.save(
        const XtreamProfile(
          id: 'p1',
          name: 'Enrico Hoffman - Firestick Salone',
          host: 'http://esempio.tv:8080',
          username: 'utente123',
        ),
        password: 'segreta',
      );
    });
    addTearDown(() {
      for (final k in StorageService.profilesBox.keys.toList()) {
        StorageService.profilesBox.delete(k);
      }
    });

    // Schermo alto: la scheda Account sta in fondo alla lista, e una ListView
    // costruisce solo quello che si vede.
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        secureCredentialsServiceProvider
            .overrideWithValue(FakeSecureCredentialsService()),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(find.text('Utenza attiva: '), findsOneWidget);
    expect(find.text('utente123'), findsOneWidget);
    expect(find.textContaining('Enrico Hoffman'), findsNothing,
        reason: 'il nome scritto nel pannello non deve comparire da nessuna parte');
    expect(find.textContaining('esempio.tv'), findsNothing,
        reason: 'e nemmeno l\'indirizzo (79° giro)');
  });
}
