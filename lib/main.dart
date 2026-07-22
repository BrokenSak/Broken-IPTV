import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/fullscreen.dart';
import 'data/services/device_mode_service.dart';
import 'data/services/storage_service.dart';
import 'state/sync_providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await StorageService.init();

  // Ask the OS once whether this is a TV, and cache it: the focus policy needs
  // the answer synchronously while building, and it decides whether the device
  // picker comes up with a pre-focused card (Firestick: yes, a remote needs a
  // target) or with nothing lit (phone: a lit card looks already selected).
  DeviceModeService.detectedIsTv = await DeviceModeService().detectIsTv();

  // Android is fullscreen for good: no toggle anywhere, re-asserted on every
  // resume (see BrokenIptvApp).
  await applyAndroidImmersive();

  // Orientation is free everywhere on Android (portrait + landscape); only
  // the player pins landscape, see PlayerScreen.initState/dispose.

  // Owned here rather than by a plain ProviderScope so the Windows close hook
  // below can reach the providers (a window closing isn't a widget lifecycle
  // event, and by the time it fires there is no context left to read from).
  final container = ProviderContainer();

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      title: 'Broken IPTV',
      minimumSize: Size(640, 420),
      titleBarStyle: TitleBarStyle.normal,
    );
    windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
    // Closing the window is the desktop equivalent of Android's "app went to
    // background": the last chance to push pending favourites/progress.
    await windowManager.setPreventClose(true);
    windowManager.addListener(_SyncOnWindowClose(container));
  }

  runApp(UncontrolledProviderScope(
    container: container,
    child: const BrokenIptvApp(),
  ));
}

/// Uploads pending sync changes when the user closes the window, then really
/// closes it.
///
/// ⚠️ `setPreventClose(true)` means the window ONLY closes when
/// [WindowManager.destroy] is called — so every path through here must reach
/// it. Hence the timeout and the bare catch: a slow or broken backend can
/// delay the close by a few seconds at most, never block it.
class _SyncOnWindowClose with WindowListener {
  _SyncOnWindowClose(this._container);

  final ProviderContainer _container;
  bool _closing = false;

  @override
  void onWindowClose() async {
    if (_closing) return;
    _closing = true;
    try {
      await _container
          .read(syncProvider.notifier)
          .syncIfChanged()
          .timeout(const Duration(seconds: 4));
    } catch (_) {}
    try {
      await windowManager.destroy();
    } catch (_) {
      // Never leave the guard latched on a failed destroy: the user would be
      // left with a window that ignores every further close.
      _closing = false;
      rethrow;
    }
  }
}
