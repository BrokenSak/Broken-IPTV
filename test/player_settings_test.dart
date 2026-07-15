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

  test('volume stays on the 0–100 UI scale', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(playerSettingsProvider.notifier);

    notifier.setVolume(80);
    expect(container.read(playerSettingsProvider).volume, 80);

    // Out-of-range values (e.g. a 0–200 volume saved by an older build)
    // must clamp back into the UI scale.
    notifier.setVolume(180);
    expect(container.read(playerSettingsProvider).volume, 100);

    notifier.setVolume(-5);
    expect(container.read(playerSettingsProvider).volume, 0);
  });

  test('volume survives a reload from prefs', () {
    final first = ProviderContainer();
    addTearDown(first.dispose);
    first.read(playerSettingsProvider.notifier).setVolume(65);

    // A fresh container re-runs build(), reading back from the prefs box.
    final second = ProviderContainer();
    addTearDown(second.dispose);
    expect(second.read(playerSettingsProvider).volume, 65);
  });
}
