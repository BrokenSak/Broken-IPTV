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

/// Whether the automatic trigger should actually do a round trip.
///
/// Pure so the rules are testable — they decide when your progress leaves the
/// device, and getting them wrong looks exactly like "sync is broken".
///
/// - [playing] vetoes everything: never compete with a running stream for the
///   network. The player calls this again the moment it closes, which is when
///   the progress is final anyway.
/// - [changed] is the write-budget guard: nothing new, no request at all.
bool shouldAutoSync({
  required bool enabled,
  required bool running,
  required bool playing,
  required Duration? sinceLastAttempt,
  required bool changed,
  Duration minInterval = _kMinInterval,
}) {
  if (!enabled || running) return false;
  if (playing) return false;
  if (sinceLastAttempt != null && sinceLastAttempt < minInterval) return false;
  return changed;
}

/// Com'è finito l'**ultimo tentativo**, ricordato fra un avvio e l'altro.
///
/// Serve perché "ho un codice in tasca" non vuol dire "sto sincronizzando": il
/// server può rifiutarlo (l'interruttore dell'utenza è spento) e la rete può
/// non esserci. Senza memoria, appena riaperta l'app non si saprebbe niente e
/// la schermata direbbe di nuovo la cosa comoda.
enum SyncOutcome {
  /// Nessun tentativo di cui si sappia qualcosa.
  mai,

  /// Giro completo riuscito.
  ok,

  /// Il server ha detto di no (403): codice non in elenco o sincronizzazione
  /// spenta per quell'utenza.
  rifiutata,

  /// Tentativo fallito per altro (rete, server irraggiungibile).
  fallita,
}

/// Cosa è vero della sincronizzazione **adesso**, in una parola.
enum SyncTruth {
  /// Nessuno l'ha accesa su questo dispositivo.
  spenta,

  /// L'ha spenta chi gestisce l'app: il server rifiuta il codice.
  spentaDalPannello,

  /// C'è il codice ma un giro completo non è mai riuscito.
  maiRiuscita,

  /// Ha funzionato in passato, l'ultimo tentativo no.
  nonRiuscita,

  /// Funziona.
  attiva,
}

/// La regola, pura e testata.
///
/// ⚠️ Nasce da una segnalazione dell'utente: «Sincronizzazione dice attiva
/// anche quando non è effettivamente attiva». Diceva **Attiva** perché il
/// dispositivo aveva un codice salvato — cioè l'unica cosa che non dipende da
/// nessuno — mentre il server poteva benissimo rispondere 403 a ogni giro.
/// Adesso "attiva" vuol dire una cosa sola: **l'ultimo giro completo è andato
/// a buon fine**.
SyncTruth syncTruth({
  required bool hasCode,
  required SyncOutcome outcome,
  required DateTime? lastSyncAt,
}) {
  // Il rifiuto vale anche senza codice: quando il server dice di no il codice
  // viene buttato via (è il pannello a comandare), e il motivo va comunque
  // detto, se no sembra che non l'abbia mai accesa nessuno.
  if (outcome == SyncOutcome.rifiutata) return SyncTruth.spentaDalPannello;
  if (!hasCode) return SyncTruth.spenta;
  if (lastSyncAt == null) return SyncTruth.maiRiuscita;
  if (outcome == SyncOutcome.fallita) return SyncTruth.nonRiuscita;
  return SyncTruth.attiva;
}

class SyncState {
  const SyncState({
    this.code,
    this.endpoint = '',
    this.running = false,
    this.lastSyncAt,
    this.error,
    this.outcome = SyncOutcome.mai,
  });

  /// The shared secret. Null = sync off.
  final String? code;
  final String endpoint;
  final bool running;
  final DateTime? lastSyncAt;
  final String? error;

  /// Come è finito l'ultimo tentativo (ricordato fra un avvio e l'altro).
  final SyncOutcome outcome;

  /// C'è un codice e un indirizzo: **configurata**, che non vuol dire
  /// funzionante — per quello c'è [truth].
  bool get enabled => code != null && endpoint.trim().isNotEmpty;

  SyncTruth get truth =>
      syncTruth(hasCode: enabled, outcome: outcome, lastSyncAt: lastSyncAt);

  SyncState copyWith({
    String? code,
    bool clearCode = false,
    String? endpoint,
    bool? running,
    DateTime? lastSyncAt,
    String? error,
    bool clearError = false,
    SyncOutcome? outcome,
  }) {
    return SyncState(
      code: clearCode ? null : (code ?? this.code),
      endpoint: endpoint ?? this.endpoint,
      running: running ?? this.running,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      error: clearError ? null : (error ?? this.error),
      outcome: outcome ?? this.outcome,
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
  static const _outcomeKey = 'sync_last_outcome';

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
      outcome: _readOutcome(prefs.get(_outcomeKey) as String?),
    );
  }

  static SyncOutcome _readOutcome(String? stored) {
    for (final o in SyncOutcome.values) {
      if (o.name == stored) return o;
    }
    return SyncOutcome.mai;
  }

  void _rememberOutcome(SyncOutcome outcome) {
    StorageService.prefsBox.put(_outcomeKey, outcome.name);
  }

  String? get _pushedFingerprint => StorageService.prefsBox.get(_fingerprintKey) as String?;

  /// Returns false when [raw] isn't a valid code (the UI says so).
  bool setCode(String raw) {
    final code = normalizeSyncCode(raw);
    if (code == null) return false;
    StorageService.prefsBox.put(_codeKey, code);
    // Another account's data: nothing we pushed before applies to it.
    StorageService.prefsBox.delete(_fingerprintKey);
    // E nemmeno l'esito di prima: è un codice nuovo, non si sa ancora niente.
    _rememberOutcome(SyncOutcome.mai);
    state = state.copyWith(
      code: code,
      clearError: true,
      outcome: SyncOutcome.mai,
    );
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
  ///
  /// [refused] quando a spegnerla è stato il server: l'esito va ricordato,
  /// altrimenti la schermata direbbe "nessuno l'ha accesa" a chi invece l'ha
  /// vista spegnere da sotto i piedi.
  void disable({bool refused = false}) {
    StorageService.prefsBox.delete(_codeKey);
    StorageService.prefsBox.delete(_fingerprintKey);
    final outcome = refused ? SyncOutcome.rifiutata : SyncOutcome.mai;
    _rememberOutcome(outcome);
    state = state.copyWith(clearCode: true, clearError: true, outcome: outcome);
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
      _rememberOutcome(SyncOutcome.ok);
      state = state.copyWith(
        running: false,
        lastSyncAt: now,
        clearError: true,
        outcome: SyncOutcome.ok,
      );
    } on SyncNotAllowedException catch (e) {
      // Il server dice di no: non è un guasto, è l'interruttore dell'utenza.
      // Il codice si butta via — il pannello comanda anche al contrario (§7),
      // e tenerselo vorrebbe dire ripresentarsi a ogni avvio per farsi dire di
      // no un'altra volta, mentre la schermata continua a dire "Attiva".
      // Se il proprietario la riaccende, il dispositivo ri-adotta il codice al
      // primo invio che riceve, senza che nessuno digiti niente.
      disable(refused: true);
      state = state.copyWith(running: false, error: e.message);
    } catch (_) {
      _rememberOutcome(SyncOutcome.fallita);
      state = state.copyWith(
        running: false,
        outcome: SyncOutcome.fallita,
        error: 'Sincronizzazione non riuscita. Controlla codice e indirizzo.',
      );
    }
  }

  /// The automatic trigger (app going to background, window closing). Skips
  /// the network entirely when nothing changed since the last push — which is
  /// the common case, and keeps the free tier's write budget for real edits.
  Future<void> syncIfChanged() async {
    final local = ref.read(syncRepositoryProvider).readLocal();
    final last = _lastAttempt;
    if (!shouldAutoSync(
      enabled: state.enabled,
      running: state.running,
      playing: PlaybackActivity.active,
      sinceLastAttempt: last == null ? null : DateTime.now().difference(last),
      changed: syncFingerprint(local) != _pushedFingerprint,
    )) {
      return;
    }
    await syncNow();
  }
}

final syncProvider = NotifierProvider<SyncNotifier, SyncState>(SyncNotifier.new);
