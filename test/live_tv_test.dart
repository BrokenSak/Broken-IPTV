import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:broken_iptv/core/theme/app_theme.dart';
import 'package:broken_iptv/data/models/channel.dart';
import 'package:broken_iptv/data/models/epg_program.dart';
import 'package:broken_iptv/data/models/xtream_category.dart';
import 'package:broken_iptv/data/repositories/live_repository.dart';
import 'package:broken_iptv/data/services/storage_service.dart';
import 'package:broken_iptv/data/services/xtream_session.dart';
import 'package:broken_iptv/presentation/screens/live_tv/live_tv_screen.dart';
import 'package:broken_iptv/state/live_providers.dart';
import 'package:broken_iptv/state/profile_providers.dart';

class FakeLiveRepository extends LiveRepository {
  FakeLiveRepository() : super(XtreamSession(host: 'http://fake-host', username: 'u', password: 'p'));

  @override
  Future<List<XtreamCategory>> getCategories() async => const [
        XtreamCategory(id: '1', name: 'Sport'),
        XtreamCategory(id: '2', name: 'Notizie'),
      ];

  @override
  Future<List<Channel>> getChannels(String categoryId) async => [
        Channel(streamId: '100', name: 'Canale Test', categoryId: categoryId),
      ];

  // The grid now fills from the full list, filtered by category on the device
  // (panels that ignore category_id returned an empty per-category list).
  @override
  Future<List<Channel>> getAllChannels() async => const [
        Channel(streamId: '100', name: 'Canale Test', categoryId: '1'),
        Channel(streamId: '200', name: 'Altro Canale', categoryId: '2'),
      ];

  @override
  Future<List<EpgProgram>> getShortEpg(String streamId, {int limit = 20}) async => const [];

  @override
  String streamUrl(String streamId) => 'http://fake-host/live/u/p/$streamId.m3u8';
}

class _FixedSelectedProfileId extends SelectedProfileIdNotifier {
  @override
  String? build() => 'test-profile';
}

void main() {
  setUpAll(() async {
    final dir = Directory.systemTemp.createTempSync('broken_iptv_test');
    await StorageService.init(testPath: dir.path);
  });

  testWidgets('Live TV screen shows categories and channels', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          selectedProfileIdProvider.overrideWith(_FixedSelectedProfileId.new),
          liveRepositoryProvider.overrideWith((ref) async => FakeLiveRepository()),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: const LiveTvScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Sidebar shows the pinned Preferiti entry plus the real categories.
    expect(find.text('PREFERITI'), findsOneWidget);
    expect(find.text('Sport'), findsOneWidget);
    expect(find.text('Notizie'), findsOneWidget);

    // Selecting a real category reveals its channels.
    await tester.tap(find.text('Sport'));
    await tester.pumpAndSettle();
    expect(find.text('Canale Test'), findsOneWidget);
  });
}
