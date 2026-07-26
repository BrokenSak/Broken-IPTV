import 'dart:io';

import 'package:flutter/services.dart';

/// Thin wrapper over the native Android Picture-in-Picture support (phone only;
/// the native side ignores it on TV). The player marks itself "allowed" while a
/// video is playing, so pressing Home drops into a floating window instead of
/// just backgrounding — and it can trigger PiP explicitly from a button.
///
/// No-op on every non-Android platform.
class PipService {
  PipService._();
  static final PipService instance = PipService._();

  static const MethodChannel _channel = MethodChannel('com.brokeniptv/pip');

  bool _wired = false;
  final List<void Function(bool)> _modeListeners = [];

  void _ensureWired() {
    if (_wired) return;
    _wired = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onPipModeChanged') {
        final inPip = call.arguments == true;
        for (final l in List<void Function(bool)>.of(_modeListeners)) {
          l(inPip);
        }
      }
    });
  }

  /// Marks PiP as allowed (a phone video is playing) or not. When allowed,
  /// leaving the app (Home) enters PiP.
  Future<void> setAllowed(bool allowed) async {
    if (!Platform.isAndroid) return;
    _ensureWired();
    try {
      await _channel.invokeMethod('setAllowed', allowed);
    } catch (_) {}
  }

  /// Enters PiP now (explicit button). Returns quietly if unsupported.
  Future<void> enter() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('enter');
    } catch (_) {}
  }

  void addModeListener(void Function(bool) listener) {
    _ensureWired();
    _modeListeners.add(listener);
  }

  void removeModeListener(void Function(bool) listener) {
    _modeListeners.remove(listener);
  }
}
