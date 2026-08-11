import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:broken_iptv/core/playback_activity.dart';
import 'package:broken_iptv/data/models/channel.dart';
import 'package:broken_iptv/data/models/series_item.dart';
import 'package:broken_iptv/data/models/vod_item.dart';
import 'package:broken_iptv/data/models/xtream_category.dart';
import 'package:broken_iptv/data/repositories/live_repository.dart';
import 'package:broken_iptv/data/repositories/series_repository.dart';
import 'package:broken_iptv/data/repositories/vod_repository.dart';
import 'package:broken_iptv/data/services/storage_service.dart';
import 'package:broken_iptv/state/catalog_refresh.dart';
import 'package:broken_iptv/state/live_providers.dart';
import 'package:broken_iptv/state/series_providers.dart';
import 'package:broken_iptv/state/vod_providers.dart';

/// Repository che contano le chiamate: quello che interessa qui non è *cosa*
/// torna, è **se** l'aggiornamento è andato a prendere tutto.
class _FakeLive implements LiveRepository {
  int categorie = 0;
  int tutti = 0;

  @override
  Future<List<XtreamCategory>> getCategories() async {
    categorie++;
    return const [XtreamCategory(id: '1', name: 'Sport')];
  }

  @override
  Future<List<Channel>> getAllChannels() async {
    tutti++;
    return const [];
  }

  @override
  Future<List<Channel>> getChannels(String categoryId) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeVod implements VodRepository {
  int categorie = 0;
  int tutti = 0;

  @override
  Future<List<XtreamCategory>> getCategories() async {
    categorie++;
    return const [XtreamCategory(id: '1', name: 'Azione')];
  }

  @override
  Future<List<VodItem>> getAllItems() async {
    tutti++;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSeries implements SeriesRepository {
  int categorie = 0;
  int tutti = 0;

  @override
  Future<List<XtreamCategory>> getCategories() async {
    categorie++;
    return const [XtreamCategory(id: '1', name: 'Drammatiche')];
  }

  @override
  Future<List<SeriesItem>> getAllItems() async {
    tutti++;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// L'aggiornamento della playlist deve scaldare **tutte** le liste.
///
/// Prima scaricava solo le categorie TV e il resto arrivava all'apertura della
/// sezione: era il motivo per cui la prima volta che entravi in Film o Serie
/// toccava aspettare (richiesta dell'utente, 75° giro).
void main() {
  setUpAll(() async {
    final dir = Directory.systemTemp.createTempSync('broken_iptv_prefetch');
    await StorageService.init(testPath: dir.path);
  });

  tearDown(() {
    PlaybackActivity.active = false;
  });

  ({ProviderContainer container, _FakeLive live, _FakeVod vod, _FakeSeries serie})
      ambiente() {
    final live = _FakeLive();
    final vod = _FakeVod();
    final serie = _FakeSeries();
    final container = ProviderContainer(overrides: [
      liveRepositoryProvider.overrideWith((ref) async => live),
      vodRepositoryProvider.overrideWith((ref) async => vod),
      seriesRepositoryProvider.overrideWith((ref) async => serie),
    ]);
    addTearDown(container.dispose);
    return (container: container, live: live, vod: vod, serie: serie);
  }

  test('aggiornare scarica canali, film e serie, non solo le categorie TV',
      () async {
    final a = ambiente();
    await a.container.read(catalogRefreshProvider).refreshNow();
    // Il download vero prosegue in sottofondo: qui si aspetta che finisca.
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(a.live.categorie, greaterThan(0), reason: 'categorie TV');
    expect(a.live.tutti, greaterThan(0), reason: 'elenco canali');
    expect(a.vod.categorie, greaterThan(0), reason: 'categorie film');
    expect(a.vod.tutti, greaterThan(0), reason: 'elenco film');
    expect(a.serie.categorie, greaterThan(0), reason: 'categorie serie');
    expect(a.serie.tutti, greaterThan(0), reason: 'elenco serie');
  });

  test('con un video aperto non scarica niente in sottofondo', () async {
    // ⚠️ L'abbonamento consente UNA connessione: scaricare mentre si guarda
    // vuol dire schermo nero. Stessa regola del sync, stesso motivo.
    final a = ambiente();
    PlaybackActivity.active = true;

    await a.container.read(catalogRefreshProvider).refreshNow();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(a.vod.tutti, 0, reason: 'i film non devono partire durante un video');
    expect(a.serie.tutti, 0, reason: 'né le serie');
  });

  test('l aggiornamento a mano ASPETTA: quando torna, ha gia scaricato tutto',
      () async {
    // È la condizione perché il riquadro che blocca la schermata abbia senso:
    // se `refreshNow` tornasse subito lasciando il lavoro in sottofondo, il
    // riquadro si chiuderebbe mentre l'app sta ancora scaricando — cioè
    // esattamente il "mi lagga" segnalato dall'utente.
    final a = ambiente();
    await a.container.read(catalogRefreshProvider).refreshNow();

    expect(a.vod.tutti, greaterThan(0), reason: 'i film prima di tornare');
    expect(a.serie.tutti, greaterThan(0), reason: 'le serie prima di tornare');
    expect(a.container.read(catalogRefreshingProvider).inCorso, isFalse,
        reason: 'a fine corsa lo stato deve dire che non sta più aggiornando');
  });

  test('quella automatica invece non fa aspettare', () async {
    // Se bloccasse anche quella delle 24 ore, l'app si inchioderebbe da sola
    // all'avvio senza che nessuno abbia chiesto niente.
    final a = ambiente();
    await a.container.read(catalogRefreshProvider).refreshNow(inSottofondo: true);

    expect(a.vod.tutti, 0, reason: 'torna prima di scaricare il resto');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(a.vod.tutti, greaterThan(0), reason: 'ma il resto arriva lo stesso');
  });
}
