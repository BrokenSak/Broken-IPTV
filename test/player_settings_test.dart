import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:broken_iptv/data/services/storage_service.dart';
import 'package:broken_iptv/state/player_settings_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final dir = Directory.systemTemp.createTempSync('broken_iptv_settings_test');
    await StorageService.init(testPath: dir.path);
  });

  test('volume allows amplification above 100 up to kMaxPlayerVolume', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(playerSettingsProvider.notifier);

    notifier.setVolume(150);
    expect(container.read(playerSettingsProvider).volume, 150);

    notifier.setVolume(9999);
    expect(container.read(playerSettingsProvider).volume, kMaxPlayerVolume);

    notifier.setVolume(-5);
    expect(container.read(playerSettingsProvider).volume, 0);
  });

  test('amplified volume survives a reload from prefs', () {
    final first = ProviderContainer();
    addTearDown(first.dispose);
    first.read(playerSettingsProvider.notifier).setVolume(180);

    // A fresh container re-runs build(), reading back from the prefs box:
    // the old code clamped the loaded value to 100.
    final second = ProviderContainer();
    addTearDown(second.dispose);
    expect(second.read(playerSettingsProvider).volume, 180);
  });
}
