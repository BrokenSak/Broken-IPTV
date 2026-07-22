import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/playback_activity.dart';
import '../data/repositories/sync_repository.dart';
import '../data/services/storage_service.dart';
import '../data/services/sync_merge.dart';
import '../data/services/sync_service.dart';
import 'favorites_providers.dart';
import 'watch_progress_providers.dart';

/// Address of the sync backend: our own Cloudflare Worker (source and deploy
/// steps in `sync_worker/`). Not a secret — the data is protected by the sync
/// code, which never leaves the devices — so it ships in the app and a new
/// device only needs the code. Settings can still override it (diagnostics, or
/// pointing a device at a different backend).
const kDefaultSyncEndpoint = 'https://broken-iptv-sync.bknsync.workers.dev';

/// Never hammer the backend: two triggers closer than this do one round trip.
const _kMinInterval = Duration(seconds: 30);

class SyncState {
  const SyncState({
    this.code,
    this.endpoint = '',
    this.running = false,
    this.lastSyncAt,
    this.error,
  });

  /// The shared secret. Null = sync off.
  final String? code;
  final String endpoint;
  final bool running;
  final DateTime? lastSyncAt;
  final String? error;

  bool get enabled => code != null && endpoint.trim().isNotEmpty;

  SyncState copyWith({
    String? code,
    bool clearCode = false,
    String? endpoint,
    bool? running,
    DateTime? lastSyncAt,
    String? error,
    bool clearError = false,
  }) {
    return SyncState(
      code: clearCode ? null : (code ?? this.code),
      endpoint: endpoint ?? this.endpoint,
      running: running ?? this.running,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final syncServiceProvider = Provider<SyncService>((ref) => SyncService());
final syncRepositoryProvider = Provider<SyncRepository>((ref) => SyncRepository());

/// Keeps favourites and "continua a guardare" the same on every device.
///
/// One round trip does the whole job: read the remote blob, merge it with the
/// local one (pure, see `sync_merge.dart`), write back whichever side changed.
/// Uploads are the scarce resource on the free tier, so [syncIfChanged] — the
/// one the app calls automatically — fingerprints the local state first and
/// does nothing at all when it matches what we last pushed.
class SyncNotifier extends Notifier<SyncState> {
  static const _codeKey = 'sync_code';
  static const _endpointKey = 'sync_endpoint';
  static const _lastAtKey = 'sync_last_at';
  static const _fingerprintKey = 'sync_last_fingerprint';

  DateTime? _lastAttempt;

  @override
  SyncState build() {
    final prefs = StorageService.prefsBox;
    final lastAt = (prefs.get(_lastAtKey) as num?)?.toInt();
    // An empty stored value falls back to the shipped default too: an early
    // build had no default, so a device that opened Settings back then could
    // have saved a blank endpoint and would otherwise never pick the new one up.
    final stored = (prefs.get(_endpointKey) as String?)?.trim();
    return SyncState(
      code: prefs.get(_codeKey) as String?,
      endpoint: (stored == null || stored.isEmpty) ? kDefaultSyncEndpoint : stored,
      lastSyncAt: lastAt == null ? null : DateTime.fromMillisecondsSinceEpoch(lastAt),
    );
  }

  String? get _pushedFingerprint => StorageService.prefsBox.get(_fingerprintKey) as String?;

  /// Returns false when [raw] isn't a valid code (the UI says so).
  bool setCode(String raw) {
    final code = normalizeSyncCode(raw);
    if (code == null) return false;
    StorageService.prefsBox.put(_codeKey, code);
    // Another account's data: nothing we pushed before applies to it.
    StorageService.prefsBox.delete(_fingerprintKey);
    state = state.copyWith(code: code, clearError: true);
    return true;
  }

  /// A brand-new code for this device to share with the others.
  String createCode() {
    final code = generateSyncCode();
    setCode(code);
    return code;
  }

  void setEndpoint(String url) {
    final trimmed = url.trim();
    StorageService.prefsBox.put(_endpointKey, trimmed);
    state = state.copyWith(endpoint: trimmed, clearError: true);
  }

  /// Stops syncing on this device. Local favourites/progress stay untouched,
  /// and the blob stays on the server for the other devices.
  void disable() {
    StorageService.prefsBox.delete(_codeKey);
    StorageService.prefsBox.delete(_fingerprintKey);
    state = state.copyWith(clearCode: true, clearError: true);
  }

  /// Full round trip. Used by "Sincronizza ora" and once at startup, where it
  /// also reconciles anything an earlier crash left unpushed.
  Future<void> syncNow() async {
    final code = state.code;
    final endpoint = state.endpoint.trim();
    if (code == null || endpoint.isEmpty || state.running) return;

    _lastAttempt = DateTime.now();
    state = state.copyWith(running: true, clearError: true);
    try {
      final repo = ref.read(syncRepositoryProvider);
      final service = ref.read(syncServiceProvider);

      final local = repo.readLocal();
      final remoteJson = await service.fetch(endpoint: endpoint, code: code);
      final remote = remoteJson == null ? SyncBlob.empty : SyncBlob.fromJson(remoteJson);

      final merged = mergeSyncBlobs(
        local,
        remote,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
      final mergedFp = syncFingerprint(merged);

      if (mergedFp != syncFingerprint(local)) {
        await repo.applyMerged(merged);
        ref.invalidate(favoritesProvider);
        ref.invalidate(watchProgressProvider);
      }
      if (mergedFp != syncFingerprint(remote)) {
        await service.push(endpoint: endpoint, code: code, blob: merged.toJson());
      }

      final now = DateTime.now();
      StorageService.prefsBox.put(_lastAtKey, now.millisecondsSinceEpoch);
      StorageService.prefsBox.put(_fingerprintKey, mergedFp);
      state = state.copyWith(running: false, lastSyncAt: now, clearError: true);
    } catch (_) {
      state = state.copyWith(
        running: false,
        error: 'Sincronizzazione non riuscita. Controlla codice e indirizzo.',
      );
    }
  }

  /// The automatic trigger (app going to background, window closing). Skips
  /// the network entirely when nothing changed since the last push — which is
  /// the common case, and keeps the free tier's write budget for real edits.
  Future<void> syncIfChanged() async {
    if (!state.enabled || state.running) return;
    if (PlaybackActivity.active) return;
    final last = _lastAttempt;
    if (last != null && DateTime.now().difference(last) < _kMinInterval) return;
    final local = ref.read(syncRepositoryProvider).readLocal();
    if (syncFingerprint(local) == _pushedFingerprint) return;
    await syncNow();
  }
}

final syncProvider = NotifierProvider<SyncNotifier, SyncState>(SyncNotifier.new);
