import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:broken_iptv/data/services/provisioning_service.dart';
import 'package:broken_iptv/data/services/storage_service.dart';
import 'package:broken_iptv/state/profile_providers.dart';
import 'package:broken_iptv/state/provisioning_providers.dart';
import 'package:broken_iptv/state/sync_providers.dart';

import 'profile_flow_test.dart' show FakeSecureCredentialsService;

/// Cosa succede quando la playlist mandata dal pannello arriva sul
/// dispositivo. Senza widget: qui interessa l'effetto sui dati.
class _FakeProvisioning implements ProvisioningService {
  _FakeProvisioning(this.answer);

  ProvisionedProfile? answer;
  int calls = 0;

  @override
  Future<ProvisionedProfile?> fetch({
    required String endpoint,
    required String code,
  }) async {
    calls++;
    return answer;
  }
}

ProvisionedProfile _profile({
  int updatedAt = 1000,
  String host = 'http://esempio.tv:8080',
  String name = 'Casa',
  String? syncCode,
}) =>
    ProvisionedProfile(
      name: name,
      host: host,
      username: 'mamma',
      password: 'segreta',
      updatedAt: updatedAt,
      syncCode: syncCode,
    );

void main() {
  setUpAll(() async {
    final dir = Directory.systemTemp.createTempSync('broken_iptv_apply');
    await StorageService.init(testPath: dir.path);
  });

  setUp(() async {
    // Ogni test parte da un dispositivo vergine.
    await StorageService.prefsBox.clear();
    for (final p in StorageService.profilesBox.keys.toList()) {
      await StorageService.profilesBox.delete(p);
    }
  });

  ProviderContainer containerWith(_FakeProvisioning service) {
    final container = ProviderContainer(overrides: [
      provisioningServiceProvider.overrideWithValue(service),
      secureCredentialsServiceProvider
          .overrideWithValue(FakeSecureCredentialsService()),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  test('la playlist arrivata diventa il profilo attivo', () async {
    final container = containerWith(_FakeProvisioning(_profile()));

    final applied =
        await container.read(provisioningProvider.notifier).checkAndApply();

    expect(applied, isTrue);
    final profiles = container.read(profilesProvider);
    expect(profiles, hasLength(1));
    expect(profiles.single.name, 'Casa');
    expect(profiles.single.username, 'mamma');
    expect(container.read(selectedProfileIdProvider), profiles.single.id);
  });

  test('lo stesso invio non si riapplica al secondo giro', () async {
    final service = _FakeProvisioning(_profile());
    final container = containerWith(service);
    final notifier = container.read(provisioningProvider.notifier);

    expect(await notifier.checkAndApply(), isTrue);
    expect(await notifier.checkAndApply(), isFalse);
    expect(container.read(profilesProvider), hasLength(1));
    expect(service.calls, 2, reason: 'chiede comunque: è il confronto a fermarlo');
  });

  test('una correzione dal pannello sostituisce la stessa playlist, non ne aggiunge una',
      () async {
    // È il motivo per cui il pannello serve: cambi l'indirizzo una volta e
    // ogni dispositivo si allinea. Se ne aggiungesse una seconda, l'utente si
    // ritroverebbe due playlist e una rotta.
    final service = _FakeProvisioning(_profile(host: 'http://vecchio.tv:8080'));
    final container = containerWith(service);
    final notifier = container.read(provisioningProvider.notifier);
    await notifier.checkAndApply();
    final firstId = container.read(profilesProvider).single.id;

    service.answer = _profile(host: 'http://nuovo.tv:8080', updatedAt: 2000);
    expect(await notifier.checkAndApply(), isTrue);

    final profiles = container.read(profilesProvider);
    expect(profiles, hasLength(1));
    expect(profiles.single.id, firstId);
    expect(profiles.single.host, contains('nuovo.tv'));
  });

  test('il codice di gruppo diventa il codice di sincronizzazione', () async {
    // Così i due dispositivi della stessa persona si allineano senza che
    // nessuno digiti niente.
    final container = containerWith(
      _FakeProvisioning(_profile(syncCode: 'MNPQRSTUVWXY')),
    );

    await container.read(provisioningProvider.notifier).checkAndApply();

    expect(container.read(syncProvider).code, 'MNPQRSTUVWXY');
  });

  test('senza codice di gruppo la sincronizzazione resta com era', () async {
    final container = containerWith(_FakeProvisioning(_profile()));

    await container.read(provisioningProvider.notifier).checkAndApply();

    expect(container.read(syncProvider).code, isNull);
  });

  test('niente in attesa: non tocca nulla', () async {
    final container = containerWith(_FakeProvisioning(null));

    expect(
      await container.read(provisioningProvider.notifier).checkAndApply(),
      isFalse,
    );
    expect(container.read(profilesProvider), isEmpty);
  });
}
