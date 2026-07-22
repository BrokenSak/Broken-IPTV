import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'storage_service.dart';

enum DeviceMode { tv, touch }

/// Detects (Android only, via a native UiModeManager check) whether the app
/// is running on a TV/Firestick, and persists the user's chosen UI mode —
/// auto-detection is only a suggestion, the user can always override it.
class DeviceModeService {
  static const _channel = MethodChannel('com.brokeniptv/device');
  static const _prefsKey = 'device_mode';

  /// What the OS says this hardware is, resolved once in `main()`.
  ///
  /// Cached because the focus policy has to answer synchronously while
  /// building, and [detectIsTv] is a platform channel. It is what lets the
  /// device picker — the one screen shown *before* a mode exists — pre-light a
  /// card on a Firestick (a remote needs a target) without doing the same on a
  /// phone, where a card lit on its own reads as already selected.
  static bool detectedIsTv = false;

  /// Test hook: pretend the hardware is (or isn't) a TV.
  @visibleForTesting
  static bool? debugDetectedIsTvOverride;

  static bool get isTvDevice => debugDetectedIsTvOverride ?? detectedIsTv;

  Future<bool> detectIsTv() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isTv') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  DeviceMode? getSaved() {
    final raw = StorageService.prefsBox.get(_prefsKey) as String?;
    if (raw == null) return null;
    for (final mode in DeviceMode.values) {
      if (mode.name == raw) return mode;
    }
    return null;
  }

  Future<void> save(DeviceMode mode) {
    return StorageService.prefsBox.put(_prefsKey, mode.name);
  }
}
