import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
// `Override` is not re-exported by flutter_riverpod 3; it lives here.
import 'package:riverpod/misc.dart' show Override;

import 'package:broken_iptv/core/theme/app_theme.dart';
import 'package:broken_iptv/core/ui_mode.dart';
import 'package:broken_iptv/data/models/series_item.dart';
import 'package:broken_iptv/data/models/vod_item.dart';
import 'package:broken_iptv/data/models/xtream_category.dart';
import 'package:broken_iptv/data/repositories/series_repository.dart';
import 'package:broken_iptv/data/repositories/vod_repository.dart';
import 'package:broken_iptv/data/services/device_mode_service.dart';
import 'package:broken_iptv/data/services/storage_service.dart';
import 'package:broken_iptv/data/services/xtream_session.dart';
import 'package:broken_iptv/presentation/common/catalog_scaffold.dart';
import 'package:broken_iptv/presentation/common/tv_focusable.dart';
import 'package:broken_iptv/presentation/screens/home/home_screen.dart';
import 'package:broken_iptv/presentation/screens/onboarding/device_mode_screen.dart';
import 'package:broken_iptv/presentation/screens/profiles/profiles_screen.dart';
import 'package:broken_iptv/presentation/screens/series/series_detail_screen.dart';
import 'package:broken_iptv/presentation/screens/settings/settings_screen.dart';
import 'package:broken_iptv/presentation/screens/vod/vod_detail_screen.dart';
import 'package:broken_iptv/presentation/screens/vod/vod_screen.dart';
import 'package:broken_iptv/state/series_providers.dart';
import 'package:broken_iptv/state/update_providers.dart';
import 'package:broken_iptv/state/vod_providers.dart';

/// **L'anello non deve mai uscire dallo schermo né dalla lista che lo
/// contiene.**
///
/// Segnalato dall'utente al 79° giro guardando la TV ("molte cose sono
/// tagliate"), e visto negli screenshot del Firestick: l'anello è un overlay
/// disegnato FUORI dall'elemento (§7), quindi due bordi lo tagliavano —
///
///  1. il **bordo dello schermo**, per i pulsanti della barra in alto: stanno
///     negli angoli, e mezzo cerchio finiva oltre il vetro;
///  2. il **bordo della lista**, per ogni riga portata in vista scendendo col
///     telecomando: la lista scorreva quel tanto che bastava all'elemento, non
///     al suo anello, e l'ultima riga aveva l'anello mozzato in basso.
///
/// L'audit del telecomando (`remote_focus_audit_test`) non poteva vederlo: lì
/// si guarda *se* una fermata è visibile, non *dove* finisce il suo anello, e
/// per giunta pompa a una misura da desktop. Qui ogni schermata è pompata alla
/// geometria vera del Firestick — 1920×1080 fisici a densità 2, cioè **960×540
/// logici**, che è il vero motivo per cui su quella TV le cose non ci stanno.
const Size _kFirestickPhysical = Size(1920, 1080);
const double _kFirestickDpr = 2.0;

XtreamSession _fakeSession() =>
    XtreamSession(host: 'http://fake-host', username: 'u', password: 'p');

class _FakeVodRepository extends VodRepository {
  _FakeVodRepository() : super(_fakeSession());

  @override
  Future<VodDetail> getDetail(String vodId) async => VodDetail(
        streamId: vodId,
        name: 'Un film con un titolo abbastanza lungo da andare a capo (2024)',
        plot: 'Trama.',
        containerExtension: 'mp4',
      );

  @override
  Future<List<XtreamCategory>> getCategories() async => const [];

  @override
  Future<List<VodItem>> getAllItems() async => const [];
}

/// Un catalogo vero: categorie + una griglia piena, con nomi lunghi come quelli
/// dei pannelli veri (è lì che le cose si tagliano).
class _FakeCatalogRepository extends VodRepository {
  _FakeCatalogRepository() : super(_fakeSession());

  @override
  Future<List<XtreamCategory>> getCategories() async => const [
        XtreamCategory(id: '1', name: 'Sky PrimaFila OnDemand HD'),
        XtreamCategory(id: '2', name: 'Film FHD 1080p ITA'),
      ];

  @override
  Future<List<VodItem>> getItems(String categoryId) async => getAllItems();

  @override
  Future<List<VodItem>> getAllItems() async => [
        for (var i = 0; i < 24; i++)
          VodItem(
            streamId: '$i',
            name: 'Un film dal titolo lunghissimo numero $i (2024) SUB ITA',
            categoryId: '1',
          ),
      ];
}

class _FakeSeriesRepository extends SeriesRepository {
  _FakeSeriesRepository() : super(_fakeSession());

  @override
  Future<SeriesDetail> getDetail(String seriesId) async => SeriesDetail(
        seriesId: seriesId,
        name: 'Serie Test',
        episodesBySeason: {
          1: [
            const Episode(
              id: 'e1',
              title: 'Uno',
              episodeNum: 1,
              season: 1,
              containerExtension: 'mp4',
            ),
          ],
        },
      );

  @override
  Future<List<XtreamCategory>> getCategories() async => const [];

  @override
  Future<List<SeriesItem>> getAllItems() async => const [];
}

/// Come `remote_focus_audit_test`: route **pushata** (così la barra in alto
/// disegna davvero il pulsante indietro, che è uno dei due casi rotti) e
/// `NavigationMode.directional`, come fa `app.dart` su Android.
Widget _shell(Widget screen) {
  final router = GoRouter(
    initialLocation: '/screen',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('ROOT')),
        routes: [GoRoute(path: 'screen', builder: (_, _) => screen)],
      ),
      for (final path in const ['/live', '/vod', '/series', '/search', '/settings', '/downloads'])
        GoRoute(path: path, builder: (_, state) => Scaffold(body: Text('STUB ${state.uri}'))),
    ],
  );
  return MaterialApp.router(
    theme: AppTheme.dark,
    routerConfig: router,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(navigationMode: NavigationMode.directional),
      child: child ?? const SizedBox.shrink(),
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Il rettangolo dell'anello del nodo focalizzato, in coordinate schermo.
Rect? _ringRect(FocusNode node) {
  final context = node.context;
  if (context == null) return null;
  var insideTvFocusable = false;
  context.visitAncestorElements((element) {
    if (element.widget is TvFocusable) {
      insideTvFocusable = true;
      return false;
    }
    return true;
  });
  if (!insideTvFocusable && context.widget is! TvFocusable) return null;
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  final origin = box.localToGlobal(Offset.zero);
  return (origin & box.size).inflate(TvFocusable.ringSpace);
}

/// I riquadri che tagliano quel nodo: lo schermo e ogni lista che lo contiene.
List<(String, Rect)> _clips(FocusNode node, Size screen) {
  final clips = <(String, Rect)>[('lo schermo', Offset.zero & screen)];
  RenderObject? o = node.context?.findRenderObject();
  while (o != null) {
    if (o is RenderBox && o.hasSize) {
      final RenderBox box = o;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      // (Dart non promuove a due tipi insieme: il rettangolo si calcola prima.)
      if (o is RenderAbstractViewport) clips.add(('la lista', rect));
    }
    o = o.parent;
  }
  return clips;
}

/// Percorre il fuoco come farebbe il telecomando e riporta gli anelli tagliati.
Future<List<String>> _clippedRings(WidgetTester tester, {int maxHops = 60}) async {
  final bad = <String>[];
  final visited = <FocusNode>{};
  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;

  for (var i = 0; i < maxHops; i++) {
    final node = FocusManager.instance.primaryFocus;
    if (node == null || !visited.add(node)) break;

    final ring = _ringRect(node);
    if (ring != null) {
      for (final (what, clip) in _clips(node, screen)) {
        // Mezzo pixel di tolleranza: gli arrotondamenti del layout non sono
        // un difetto, un anello mozzato sì.
        final fits = ring.left >= clip.left - 0.5 &&
            ring.top >= clip.top - 0.5 &&
            ring.right <= clip.right + 0.5 &&
            ring.bottom <= clip.bottom + 0.5;
        if (!fits) {
          bad.add('${_describe(node)}: anello $ring fuori da $what $clip');
        }
      }
    }

    if (!node.nextFocus()) break;
    await tester.pump();
  }
  return bad;
}

String _describe(FocusNode node) {
  final semantics = node.context?.findAncestorWidgetOfExactType<Semantics>();
  return node.debugLabel ?? semantics?.properties.label ?? 'fermata senza nome';
}

Future<void> _auditScreen(
  WidgetTester tester,
  Widget screen, {
  required String name,
  List<Override> overrides = const [],
}) async {
  await tester.pumpWidget(ProviderScope(overrides: overrides, child: _shell(screen)));
  await _settle(tester);

  final bad = await _clippedRings(tester);
  expect(bad, isEmpty,
      reason: '$name: questi anelli finiscono fuori dal loro riquadro e si '
          'vedono mozzati sulla TV:\n${bad.join('\n')}');
}

void main() {
  setUpAll(() async {
    final dir = Directory.systemTemp.createTempSync('broken_iptv_layout_test');
    await StorageService.init(testPath: dir.path);
  });

  setUp(() {
    debugDeviceModeOverride = DeviceMode.tv;
  });

  tearDown(() {
    debugDeviceModeOverride = null;
    debugAndroidSectionOverride = null;
  });

  group('alla misura vera del Firestick (960x540 logici)', () {
    setUp(() {
      // Impostata qui e ripristinata dopo: `tester.view` è condivisa.
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    testWidgets('home', (tester) async {
      tester.view.physicalSize = _kFirestickPhysical;
      tester.view.devicePixelRatio = _kFirestickDpr;
      addTearDown(tester.view.reset);
      await _auditScreen(tester, const HomeScreen(),
          name: 'Home',
          overrides: [updateCheckProvider.overrideWith((ref) async => null)]);
    });

    testWidgets('impostazioni', (tester) async {
      tester.view.physicalSize = _kFirestickPhysical;
      tester.view.devicePixelRatio = _kFirestickDpr;
      addTearDown(tester.view.reset);
      // Su un host Windows la sezione "Modalità dispositivo" non ci sarebbe, ed
      // è proprio quella che spinge giù il resto della lista.
      debugAndroidSectionOverride = true;
      await _auditScreen(tester, const SettingsScreen(), name: 'Impostazioni');
    });

    testWidgets('scelta dispositivo', (tester) async {
      tester.view.physicalSize = _kFirestickPhysical;
      tester.view.devicePixelRatio = _kFirestickDpr;
      addTearDown(tester.view.reset);
      await _auditScreen(tester, const DeviceModeScreen(), name: 'Scelta dispositivo');
    });

    testWidgets('attesa playlist', (tester) async {
      tester.view.physicalSize = _kFirestickPhysical;
      tester.view.devicePixelRatio = _kFirestickDpr;
      addTearDown(tester.view.reset);
      await _auditScreen(tester, const ProfilesScreen(), name: 'Attesa playlist');
    });

    testWidgets('dettaglio film', (tester) async {
      tester.view.physicalSize = _kFirestickPhysical;
      tester.view.devicePixelRatio = _kFirestickDpr;
      addTearDown(tester.view.reset);
      await _auditScreen(tester, const VodDetailScreen(vodId: '10'),
          name: 'Dettaglio film',
          overrides: [vodRepositoryProvider.overrideWith((ref) async => _FakeVodRepository())]);
    });

    testWidgets('dettaglio serie', (tester) async {
      tester.view.physicalSize = _kFirestickPhysical;
      tester.view.devicePixelRatio = _kFirestickDpr;
      addTearDown(tester.view.reset);
      await _auditScreen(tester, const SeriesDetailScreen(seriesId: '20'),
          name: 'Dettaglio serie',
          overrides: [
            seriesRepositoryProvider.overrideWith((ref) async => _FakeSeriesRepository()),
          ]);
    });
  });

  testWidgets('catalogo: barra + griglia, nessun anello mozzato', (tester) async {
    // La schermata su cui si passa il tempo: la barra a sinistra contro il
    // bordo dello schermo e la griglia che scorre. Qui si controlla anche che
    // le tessere non vadano in overflow alla misura della TV (un overflow fa
    // fallire il test da solo).
    tester.view.physicalSize = _kFirestickPhysical;
    tester.view.devicePixelRatio = _kFirestickDpr;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        vodRepositoryProvider.overrideWith((ref) async => _FakeCatalogRepository()),
      ],
      child: _shell(const VodScreen()),
    ));
    await _settle(tester);
    await _settle(tester);

    final bad = await _clippedRings(tester, maxHops: 30);
    expect(bad, isEmpty, reason: 'anelli mozzati nel catalogo:\n${bad.join('\n')}');
  });

  testWidgets('scendendo in una lista lunga, la lista lascia spazio all anello',
      (tester) async {
    // Il caso puro del difetto: una lista più alta dello schermo. Col codice
    // vecchio (anello senza spazio riservato) la riga portata in vista finiva
    // a filo del bordo e l'anello restava tagliato di 6px.
    //
    // ⚠️ Il bordo della lista lo deve pagare la lista: agli estremi non c'è
    // niente da scorrere, quindi una lista di focusabili senza margine avrebbe
    // comunque la prima e l'ultima riga con l'anello mozzato. Da qui il
    // `padding` qui sotto, che è la stessa regola applicata alla barra delle
    // categorie (`CategorySidebar`).
    tester.view.physicalSize = _kFirestickPhysical;
    tester.view.devicePixelRatio = _kFirestickDpr;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: ListView(
          // Il margine della lista è suo: agli estremi non c'è niente da
          // scorrere. Qui se ne lascia un filo in più dell'anello, come fa la
          // barra delle categorie, così anche la prima e l'ultima riga hanno
          // aria intorno.
          padding: EdgeInsets.all(TvFocusable.ringSpace + 6),
          children: [
            for (var i = 0; i < 20; i++)
              TvFocusable(
                autofocus: i == 0,
                onTap: () {},
                child: Container(height: 60, color: AppColors.surface, child: Text('riga $i')),
              ),
          ],
        ),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(navigationMode: NavigationMode.directional),
        child: child ?? const SizedBox.shrink(),
      ),
    ));
    await _settle(tester);

    final viewport = tester.renderObject<RenderBox>(find.byType(Viewport));
    final viewportRect = viewport.localToGlobal(Offset.zero) & viewport.size;

    // Scende fino in fondo, controllando ogni fermata.
    for (var hop = 0; hop < 20; hop++) {
      final node = FocusManager.instance.primaryFocus!;
      final ring = _ringRect(node);
      if (ring != null) {
        // Non "appena dentro": un anello a filo del bordo si legge tagliato
        // lo stesso (visto sul Firestick), quindi si pretende un po' d'aria.
        expect(ring.top, greaterThanOrEqualTo(viewportRect.top + 1),
            reason: 'anello a filo (o mozzato) in alto al passo $hop');
        expect(ring.bottom, lessThanOrEqualTo(viewportRect.bottom - 1),
            reason: 'anello a filo (o mozzato) in basso al passo $hop');
      }
      if (!node.nextFocus()) break;
      await tester.pump();
    }
  });

  testWidgets('barra delle categorie: nessun anello mozzato, nemmeno il primo',
      (tester) async {
    // La barra vive contro il bordo sinistro dello schermo e la sua lista è
    // sempre più lunga dello schermo: è il posto dove il difetto si vedeva di
    // più (la prima categoria è anche il punto d'atterraggio del telecomando).
    tester.view.physicalSize = _kFirestickPhysical;
    tester.view.devicePixelRatio = _kFirestickDpr;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: Row(
          children: [
            CategorySidebar(
              categories: [
                for (var i = 0; i < 25; i++) XtreamCategory(id: '$i', name: 'Categoria $i'),
              ],
              selectedId: '0',
              onSelect: (_) {},
              showContinue: true,
              showAll: true,
              showRecent: true,
            ),
            const Expanded(child: SizedBox()),
          ],
        ),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(navigationMode: NavigationMode.directional),
        child: child ?? const SizedBox.shrink(),
      ),
    ));
    await _settle(tester);

    final bad = await _clippedRings(tester, maxHops: 12);
    expect(bad, isEmpty, reason: 'anelli mozzati nella barra:\n${bad.join('\n')}');
  });
}
