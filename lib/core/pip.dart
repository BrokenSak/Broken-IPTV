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

  /// Whether this device supports PiP at all (cached after the first ask).
  /// A phone with the feature missing — or an Android older than 8 — must not
  /// show a button that silently does nothing.
  bool? _supported;

  Future<bool> isSupported() async {
    if (!Platform.isAndroid) return false;
    final cached = _supported;
    if (cached != null) return cached;
    try {
      final ok = await _channel.invokeMethod<bool>('isSupported') ?? false;
      _supported = ok;
      return ok;
    } catch (_) {
      _supported = false;
      return false;
    }
  }

  /// Marks PiP as allowed (a phone video is playing) or not. When allowed,
  /// leaving the app (Home) enters PiP — on Android 12+ this also arms the
  /// system's auto-enter, which is what makes the *gesture* home work.
  Future<void> setAllowed(bool allowed) async {
    if (!Platform.isAndroid) return;
    _ensureWired();
    try {
      await _channel.invokeMethod('setAllowed', allowed);
    } catch (_) {}
  }

  /// Enters PiP now (explicit button). Returns false when the system refuses —
  /// typically because the per-app "Picture-in-picture" permission is off in
  /// Android Settings — so the caller can say so instead of doing nothing.
  Future<bool> enter() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('enter') ?? false;
    } catch (_) {
      return false;
    }
  }

  void addModeListener(void Function(bool) listener) {
    _ensureWired();
    _modeListeners.add(listener);
  }

  void removeModeListener(void Function(bool) listener) {
    _modeListeners.remove(listener);
  }
}
