import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/playback_activity.dart';
import '../data/services/storage_service.dart';
import '../data/services/xtream_session.dart';
import 'live_providers.dart';
import 'provisioning_providers.dart' show underFlutterTest;
import 'series_providers.dart';
import 'vod_providers.dart';

final catalogRefreshingProvider = NotifierProvider<_RefreshingNotifier, bool>(
  _RefreshingNotifier.new,
);

class _RefreshingNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  void set(bool v) => state = v;
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
          if (!_buttatoVia) refreshNow();
        });
      }
    }
    // Then keep refreshing on a 24h cadence while the app runs.
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => refreshNow());
  }

  void _markRefreshed() {
    StorageService.prefsBox.put(_lastKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// Rebuilds the session/catalog providers and forces a real re-fetch so we
  /// actually know whether the playlist is reachable. Returns null on success
  /// or a human-readable message when the refresh failed.
  Future<String?> refreshNow() async {
    _ref.read(catalogRefreshingProvider.notifier).set(true);
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
      // Actually hit the panel so a failure (unreachable host, wrong
      // credentials, connection limit) surfaces instead of silently "refreshing".
      await _ref.read(liveCategoriesProvider.future);
    } on NoActivePlaylistException {
      // No playlist selected yet — nothing to refresh, not a failure to report.
    } catch (e) {
      error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
    }

    _ref.read(catalogRefreshingProvider.notifier).set(false);

    // Il resto scende in sottofondo: chi ha premuto "Aggiorna lista" ha già
    // la sua risposta (il pannello risponde o no), e può usare l'app mentre
    // il grosso arriva.
    if (error == null) unawaited(_scaricaTutteLeListe());
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
  Future<void> _scaricaTutteLeListe() async {
    Future<void> passo(Future<void> Function() scarica) async {
      if (PlaybackActivity.active || _buttatoVia) return;
      try {
        await scarica();
      } catch (_) {
        // Un catalogo che non risponde non deve rompere gli altri né far
        // comparire un errore: qui si sta solo scaldando la cache.
      }
    }

    await passo(() => _ref.read(allChannelsProvider.future));
    await passo(() => _ref.read(vodCategoriesProvider.future));
    await passo(() => _ref.read(allVodProvider.future));
    await passo(() => _ref.read(seriesCategoriesProvider.future));
    await passo(() => _ref.read(allSeriesProvider.future));
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
