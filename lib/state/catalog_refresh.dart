import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/playback_activity.dart';
import '../data/services/storage_service.dart';
import '../data/services/xtream_session.dart';
import 'live_providers.dart';
import 'provisioning_providers.dart' show underFlutterTest;
import 'series_providers.dart';
import 'vod_providers.dart';

/// A che punto è l'aggiornamento, per poterlo **mostrare**.
///
/// L'utente ha chiesto che l'aggiornamento a mano blocchi tutto: "se mi lasci
/// la possibilità di continuare a fare cose l'app mi lagga". Con una sola
/// connessione verso il pannello è vero — mentre scarichi i cataloghi, ogni
/// altra cosa che l'app chiede si mette in coda dietro. Quindi si blocca, ma va
/// detto perché: da qui esce il testo del riquadro.
class CatalogRefreshState {
  const CatalogRefreshState({
    this.inCorso = false,
    this.passo = 0,
    this.totale = 0,
    this.cosa = '',
  });

  final bool inCorso;
  final int passo;
  final int totale;

  /// Cosa sta scaricando adesso, in italiano ("i film", "le serie"…).
  final String cosa;
}

final catalogRefreshingProvider =
    NotifierProvider<_RefreshingNotifier, CatalogRefreshState>(
  _RefreshingNotifier.new,
);

class _RefreshingNotifier extends Notifier<CatalogRefreshState> {
  @override
  CatalogRefreshState build() => const CatalogRefreshState();

  void avvia(int totale) =>
      state = CatalogRefreshState(inCorso: true, totale: totale, cosa: 'la lista');
  void passo(int n, String cosa) =>
      state = CatalogRefreshState(
          inCorso: true, passo: n, totale: state.totale, cosa: cosa);
  void fine() => state = const CatalogRefreshState();
}

/// Aggiornamento dei cataloghi, a mano o ogni 24 ore.
///
/// Dal 75° giro l'aggiornamento **scarica davvero tutto** (canali, film,
/// serie), non solo le categorie TV: prima le liste arrivavano solo quando
/// aprivi quella sezione, ed è il motivo per cui la prima apertura di Film o
/// Serie faceva aspettare. Le **copertine no**: sono una per titolo, cioè
/// migliaia di file e diversi GB su un catalogo vero — continuano ad arrivare
/// mentre scorri.
class CatalogRefresh {
  CatalogRefresh(this._ref) {
    _scheduleAuto();
  }

  final Ref _ref;
  Timer? _timer;
  /// ⚠️ Il precarico vive più a lungo di chi l'ha lanciato: prosegue in
  /// sottofondo, e se intanto il provider viene buttato via (cambio playlist,
  /// ProviderScope ricostruito) leggere `_ref` esplode con UnmountedRef. Va
  /// controllato prima di ogni lettura, non solo all'inizio.
  bool _buttatoVia = false;
  static const _lastKey = 'catalog_last_refresh';
  static const _interval = Duration(hours: 24);

  void _scheduleAuto() {
    final lastMs = StorageService.prefsBox.get(_lastKey) as int?;
    final last = lastMs != null ? DateTime.fromMillisecondsSinceEpoch(lastMs) : null;
    if (last == null || DateTime.now().difference(last) >= _interval) {
      // ⚠️ Qui prima c'era solo `_markRefreshed()`: il commento diceva
      // "refresh on startup if more than 24h have passed" ma l'unica cosa che
      // succedeva era che la data veniva spostata avanti. I dati si
      // rinfrescavano lo stesso, ma solo perché la cache scadeva da sé alla
      // prima apertura di ogni sezione.
      // Fuori dal costruttore: `refreshNow` legge provider, e leggerli mentre
      // questo provider si sta ancora costruendo è un rientro.
      //
      // ⚠️ Mai sotto `flutter test`: una schermata che monta la home farebbe
      // partire un aggiornamento vero, e `pumpAndSettle` aspetterebbe per
      // sempre qualcosa che sotto il finto orologio non finisce mai. Il
      // comportamento è coperto chiamando `refreshNow()` a mano
      // (catalog_prefetch_test), che è anche più onesto.
      if (!underFlutterTest) {
        Future.microtask(() {
          if (!_buttatoVia) refreshNow(inSottofondo: true);
        });
      }
    }
    // Then keep refreshing on a 24h cadence while the app runs.
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => refreshNow(inSottofondo: true));
  }

  void _markRefreshed() {
    StorageService.prefsBox.put(_lastKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// Rifa i cataloghi dal pannello. Torna null se è andata, oppure il motivo.
  ///
  /// [inSottofondo] distingue le due chiamate: quella automatica delle 24 ore
  /// scende zitta e si ferma se è aperto un video; quella a mano invece
  /// **blocca la schermata** finché non ha finito, e per farlo aspetta tutto.
  Future<String?> refreshNow({bool inSottofondo = false}) async {
    final avanzamento = _ref.read(catalogRefreshingProvider.notifier);
    avanzamento.avvia(6);
    // Drop the profile's cached catalogs first: a manual/24h refresh must hit
    // the panel for real, not be answered by the disk cache.
    try {
      final source = await _ref.read(xtreamSessionProvider.future);
      if (source is XtreamSession) await source.clearCatalogCache();
    } catch (_) {}
    _ref.invalidate(xtreamSessionProvider);
    _ref.invalidate(liveRepositoryProvider);
    _ref.invalidate(vodRepositoryProvider);
    _ref.invalidate(seriesRepositoryProvider);
    _ref.invalidate(liveCategoriesProvider);
    _ref.invalidate(vodCategoriesProvider);
    _ref.invalidate(seriesCategoriesProvider);
    _markRefreshed();

    String? error;
    try {
      // La prima chiamata è anche la prova del nove: se il pannello non
      // risponde (irraggiungibile, credenziali sbagliate, troppe connessioni)
      // si scopre qui, non alla fine.
      avanzamento.passo(1, 'le categorie TV');
      await _ref.read(liveCategoriesProvider.future);
    } on NoActivePlaylistException {
      // No playlist selected yet — nothing to refresh, not a failure to report.
    } catch (e) {
      error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
    }

    if (error == null) {
      if (inSottofondo) {
        // L'automatica non fa aspettare nessuno.
        unawaited(_scaricaTutteLeListe().whenComplete(avanzamento.fine));
        return null;
      }
      await _scaricaTutteLeListe(avanzamento: avanzamento);
    }

    avanzamento.fine();
    return error;
  }

  /// Scarica canali, film e serie, uno dopo l'altro.
  ///
  /// ⚠️ **In sequenza, mai in parallelo**: l'abbonamento consente una sola
  /// connessione e il pannello risponde 458 quando gliene apri troppe (§6) —
  /// tre download insieme sono il modo più rapido per farsi bloccare.
  ///
  /// ⚠️ E si ferma se parte un video: con una connessione sola, scaricare
  /// mentre si guarda vuol dire schermo nero. Stessa regola del sync
  /// (`PlaybackActivity`), stesso motivo.
  Future<void> _scaricaTutteLeListe({_RefreshingNotifier? avanzamento}) async {
    var n = 1;
    Future<void> passo(String cosa, Future<void> Function() scarica) async {
      n++;
      if (PlaybackActivity.active || _buttatoVia) return;
      avanzamento?.passo(n, cosa);
      try {
        await scarica();
      } catch (_) {
        // Un catalogo che non risponde non deve rompere gli altri né far
        // comparire un errore: qui si sta solo scaldando la cache.
      }
    }

    await passo('i canali', () => _ref.read(allChannelsProvider.future));
    await passo('le categorie dei film', () => _ref.read(vodCategoriesProvider.future));
    await passo('i film', () => _ref.read(allVodProvider.future));
    await passo('le categorie delle serie', () => _ref.read(seriesCategoriesProvider.future));
    await passo('le serie', () => _ref.read(allSeriesProvider.future));
  }

  void dispose() {
    _buttatoVia = true;
    _timer?.cancel();
  }
}

final catalogRefreshProvider = Provider<CatalogRefresh>((ref) {
  final refresher = CatalogRefresh(ref);
  ref.onDispose(refresher.dispose);
  return refresher;
});
