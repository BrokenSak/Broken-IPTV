import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:broken_iptv/app.dart';
import 'package:broken_iptv/data/services/secure_credentials_service.dart';
import 'package:broken_iptv/data/services/storage_service.dart';
import 'package:broken_iptv/state/profile_providers.dart';
import 'package:broken_iptv/state/update_providers.dart';

/// Real credential storage touches platform channels/FFI (Windows DPAPI via
/// path_provider) that aren't wired up in a widget-test host, so tests use
/// an in-memory stand-in instead.
class FakeSecureCredentialsService extends SecureCredentialsService {
  FakeSecureCredentialsService() : super(const FlutterSecureStorage());

  final Map<String, String> _store = {};

  @override
  Future<void> savePassword(String profileId, String password) async {
    _store[profileId] = password;
  }

  @override
  Future<String?> getPassword(String profileId) async => _store[profileId];

  @override
  Future<void> deletePassword(String profileId) async {
    _store.remove(profileId);
  }
}

/// Avvio dell'app su un dispositivo senza playlist.
///
/// ⚠️ Dal 72° giro non esiste più un modulo per aggiungerla: la playlist è una
/// sola e la manda il proprietario dal pannello. Questo test difende ciò che
/// resta: chi è senza playlist **vede il codice da dettare** e non un pulsante
/// che non deve più esistere. La consegna vera è in `provisioning_apply_test`,
/// e l'ingresso nell'app con una playlist in `remote_navigation_test` (che usa
/// repo finti: far partire la home vera qui significherebbe chiamate di rete
/// coi timer appesi sotto il finto orologio).
void main() {
  setUpAll(() async {
    final dir = Directory.systemTemp.createTempSync('broken_iptv_test');
    await StorageService.init(testPath: dir.path);
  });

  // ⚠️ Niente pulizia di Hive nei teardown: `await box.clear()` fuori da
  // `tester.runAsync` è IO vero sotto il finto orologio e non torna MAI (il
  // test resta appeso finché non scade — ci sono ricascato scrivendo questo).
  // La cartella temporanea muore col file.
  Widget app() => ProviderScope(
        overrides: [
          secureCredentialsServiceProvider
              .overrideWithValue(FakeSecureCredentialsService()),
          // The home checks for updates (PackageInfo + network) — pin it off so
          // the test never touches a platform channel or the network.
          updateCheckProvider.overrideWith((ref) async => null),
        ],
        child: const BrokenIptvApp(),
      );

  testWidgets('senza playlist: si aspetta, e si vede il codice da dettare',
      (WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('Nessuna playlist'), findsOneWidget);
    // Il codice è mostrato a gruppi di quattro: è quello che la persona legge
    // al telefono a chi le configura l'app.
    expect(find.textContaining(RegExp(r'^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$')),
        findsOneWidget);

    // Nessun modo di aggiungerne una a mano: è il punto della schermata.
    expect(find.text('Aggiungi playlist'), findsNothing);
  });
}
