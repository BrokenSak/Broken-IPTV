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

void main() {
  setUpAll(() async {
    final dir = Directory.systemTemp.createTempSync('broken_iptv_test');
    await StorageService.init(testPath: dir.path);
  });

  testWidgets('Adding the first profile lands on the home screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          secureCredentialsServiceProvider.overrideWithValue(FakeSecureCredentialsService()),
          // The home checks for updates (PackageInfo + network) — pin it off so
          // the test never touches a platform channel or the network.
          updateCheckProvider.overrideWith((ref) async => null),
        ],
        child: const BrokenIptvApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nessuna playlist'), findsOneWidget);

    await tester.tap(find.text('Aggiungi playlist'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Nome Playlist'), 'Test Provider');
    await tester.enterText(find.widgetWithText(TextFormField, 'Username'), 'utente1');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'segreta');
    await tester.enterText(find.widgetWithText(TextFormField, 'Link'), 'server.example.com:8080');

    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(ElevatedButton, 'Salva'));
      await Future.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    // First saved playlist selects itself and enters the app directly.
    expect(find.text('TV'), findsOneWidget);
    expect(find.text('Serie'), findsOneWidget);
    expect(find.text('Film'), findsOneWidget);
  });
}
