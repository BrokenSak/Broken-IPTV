import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/xtream_profile.dart';
import '../data/services/provisioning_service.dart';
import '../data/services/storage_service.dart';
import '../data/services/xtream_api_service.dart';
import 'profile_providers.dart';
import 'sync_providers.dart';

/// True while `flutter test` runs (the runner sets the variable).
///
/// Screens skip their *automatic* check then: a real HTTP call under the fake
/// clock leaves Dio's timer pending and fails suites that only meant to look
/// at a screen. What the check does is covered without any widget, by driving
/// [provisioningProvider] over a fake service — see provisioning_apply_test.
final bool underFlutterTest = Platform.environment.containsKey('FLUTTER_TEST');

/// The code this installation shows — read once, it never changes.
final deviceCodeProvider = Provider<String>((ref) => DeviceCode.read());

final provisioningServiceProvider =
    Provider<ProvisioningService>((ref) => ProvisioningService());

const _appliedAtKey = 'provision_applied_at';
const _provisionedProfileKey = 'provision_profile_id';

/// Looks for a playlist the owner left for this device and applies it.
///
/// Returns true when something was applied, so the caller can leave the setup
/// screen. Never throws: it runs on the first screen and at startup, where a
/// flaky network must be a non-event.
///
/// Applying **replaces the same profile** it created last time instead of
/// piling up copies: correcting a panel's address from the web page is meant
/// to fix every device, and it would be useless if each fix added a playlist.
class ProvisioningNotifier extends Notifier<void> {
  @override
  void build() {}

  Future<bool> checkAndApply() => _apply(ref);
}

final provisioningProvider =
    NotifierProvider<ProvisioningNotifier, void>(ProvisioningNotifier.new);

Future<bool> _apply(Ref ref) async {
  final code = ref.read(deviceCodeProvider);
  final endpoint = ref.read(syncProvider).endpoint;
  if (endpoint.trim().isEmpty) return false;

  final remote = await ref
      .read(provisioningServiceProvider)
      .fetch(endpoint: endpoint, code: code);
  if (remote == null) return false;

  final prefs = StorageService.prefsBox;
  final appliedAt = (prefs.get(_appliedAtKey) as num?)?.toInt();
  if (!shouldApplyProvisioned(
    remoteUpdatedAt: remote.updatedAt,
    appliedAt: appliedAt,
  )) {
    return false;
  }

  final repo = ref.read(profileRepositoryProvider);
  final previousId = prefs.get(_provisionedProfileKey) as String?;
  final existing = ref
      .read(profilesProvider)
      .where((p) => p.id == previousId)
      .firstOrNull;

  final profile = XtreamProfile(
    id: existing?.id ?? repo.newId(),
    name: remote.name,
    host: XtreamApiService.normalizeHost(remote.host),
    username: remote.username,
    kind: PlaylistKind.xtream,
  );
  await ref
      .read(profilesProvider.notifier)
      .upsert(profile, password: remote.password);
  ref.read(selectedProfileIdProvider.notifier).select(profile.id);

  // A shared code means "these devices are the same person's": adopting it is
  // what makes their favourites line up without anyone typing it twice.
  //
  // ⚠️ E l'interruttore dell'utenza decide anche il contrario: se il
  // proprietario spegne i preferiti condivisi, il dispositivo deve SMETTERE.
  // Senza questo resterebbe con un codice che il server rifiuta (403
  // sync_disabled) e mostrerebbe un errore per una cosa che nessuno ha
  // chiesto — e dal 72° giro nell'app non c'è più modo di togliersi quel
  // codice a mano. Vale solo per le utenze: in un invio vecchio l'assenza del
  // codice non vuol dire "spento", vuol dire "non pervenuto".
  final syncCode = remote.syncCode;
  final sync = ref.read(syncProvider);
  if (syncCode != null && syncCode != sync.code) {
    ref.read(syncProvider.notifier).setCode(syncCode);
  } else if (syncCode == null && remote.fromAccount && sync.code != null) {
    ref.read(syncProvider.notifier).disable();
  }

  await prefs.put(_appliedAtKey, remote.updatedAt);
  await prefs.put(_provisionedProfileKey, profile.id);
  return true;
}
