import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:broken_iptv/core/theme/app_theme.dart';
import 'package:broken_iptv/data/models/series_item.dart';
import 'package:broken_iptv/data/models/vod_item.dart';
import 'package:broken_iptv/data/models/xtream_category.dart';
import 'package:broken_iptv/data/repositories/series_repository.dart';
import 'package:broken_iptv/data/repositories/vod_repository.dart';
import 'package:broken_iptv/data/services/storage_service.dart';
import 'package:broken_iptv/data/services/xtream_session.dart';
import 'package:broken_iptv/presentation/screens/series/series_screen.dart';
import 'package:broken_iptv/presentation/screens/vod/vod_screen.dart';
import 'package:broken_iptv/state/series_providers.dart';
import 'package:broken_iptv/state/vod_providers.dart';

XtreamSession _fakeSession() => XtreamSession(host: 'http://fake-host', username: 'u', password: 'p');

class FakeVodRepository extends VodRepository {
  FakeVodRepository() : super(_fakeSession());

  @override
  Future<List<XtreamCategory>> getCategories() async => const [
        XtreamCategory(id: '1', name: 'Azione'),
      ];

  @override
  Future<List<VodItem>> getItems(String categoryId) async => [
        VodItem(streamId: '10', name: 'Film Test', categoryId: categoryId),
      ];

  // The grid fills from the full list, filtered by category on the device.
  @override
  Future<List<VodItem>> getAllItems() async => const [
        VodItem(streamId: '10', name: 'Film Test', categoryId: '1'),
      ];
}

class FakeSeriesRepository extends SeriesRepository {
  FakeSeriesRepository() : super(_fakeSession());

  @override
  Future<List<XtreamCategory>> getCategories() async => const [
        XtreamCategory(id: '1', name: 'Drama'),
      ];

  @override
  Future<List<SeriesItem>> getItems(String categoryId) async => [
        SeriesItem(seriesId: '20', name: 'Serie Test', categoryId: categoryId),
      ];

  // The grid fills from the full list, filtered by category on the device.
  @override
  Future<List<SeriesItem>> getAllItems() async => const [
        SeriesItem(seriesId: '20', name: 'Serie Test', categoryId: '1'),
      ];
}

void main() {
  setUpAll(() async {
    final dir = Directory.systemTemp.createTempSync('broken_iptv_test');
    await StorageService.init(testPath: dir.path);
  });

  testWidgets('VOD screen shows categories and movies', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vodRepositoryProvider.overrideWith((ref) async => FakeVodRepository()),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const VodScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PREFERITI'), findsOneWidget);
    expect(find.text('Azione'), findsOneWidget);
    await tester.tap(find.text('Azione'));
    await tester.pumpAndSettle();
    expect(find.text('Film Test'), findsOneWidget);
  });

  testWidgets('Series screen shows categories and series', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          seriesRepositoryProvider.overrideWith((ref) async => FakeSeriesRepository()),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const SeriesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PREFERITI'), findsOneWidget);
    expect(find.text('Drama'), findsOneWidget);
    await tester.tap(find.text('Drama'));
    await tester.pumpAndSettle();
    expect(find.text('Serie Test'), findsOneWidget);
  });
}
