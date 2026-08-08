import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

/// Whether a fullscreen toggle should be offered at all.
///
/// On **Android the app is permanently fullscreen** (immersive) — there is no
/// button and no way to leave it. On Windows the toggle is real: a desktop
/// window must stay windowed by default.
bool get fullscreenToggleAvailable => !Platform.isAndroid;

/// Whether the mouse pointer must be hidden over the player's video.
///
/// Windows only — Android has no pointer. Watching **fullscreen** with the
/// controls down, the arrow just sits on top of the picture (user request: "su
/// windows a full screen deve sparire la freccia del mouse").
///
/// It comes back as soon as any UI is up ([uiVisible]: the controls bar or a
/// list overlay), and *anything* brings that up — a click, a key press — so
/// there is no state where the pointer is both gone and unreachable.
/// Deliberately NOT driven by mouse movement: the player must not react to
/// hover at all (a `MouseRegion.onHover` used to pop the controls open on every
/// twitch of the mouse, which is why it was removed — see player_screen).
bool hidePointerOverVideo({
  required bool isDesktop,
  required bool isFullscreen,
  required bool uiVisible,
}) =>
    isDesktop && isFullscreen && !uiVisible;

/// (Re)applies Android's permanent immersive mode. Called at startup and again
/// on every resume: the system restores the bars after dialogs, the keyboard
/// or an app switch, and fullscreen here must not be defeatable.
Future<void> applyAndroidImmersive() async {
  if (!Platform.isAndroid) return;
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
}

/// Fullscreen state: window_manager on Windows desktop; on Android always on
/// (see [applyAndroidImmersive]).
class FullscreenController extends Notifier<bool> {
  // Whether the window was maximized before we entered fullscreen, so we can
  // restore that exact state on exit.
  bool _wasMaximized = false;

  @override
  bool build() => Platform.isAndroid; // Android: always fullscreen.

  Future<void> toggle() => set(!state);

  Future<void> set(bool value) async {
    if (Platform.isAndroid) {
      // Always-on: ignore any request to leave fullscreen, just re-assert it.
      await applyAndroidImmersive();
      state = true;
      return;
    }
    if (Platform.isWindows) {
      if (value) {
        // window_manager can't transition cleanly straight from a *maximized*
        // window into fullscreen (it ends up stuck/half-covered), so drop the
        // maximized state first and remember it for the way back.
        _wasMaximized = await windowManager.isMaximized();
        if (_wasMaximized) {
          await windowManager.unmaximize();
          // Give Windows a moment to apply the restore before going fullscreen,
          // otherwise the fullscreen bounds are computed from the stale
          // maximized frame and the window looks broken.
          await Future<void>.delayed(const Duration(milliseconds: 120));
        }
        await windowManager.setFullScreen(true);
      } else {
        await windowManager.setFullScreen(false);
        // Restore the maximized state we came from.
        if (_wasMaximized) {
          await Future<void>.delayed(const Duration(milliseconds: 120));
          await windowManager.maximize();
          _wasMaximized = false;
        }
      }
    }
    state = value;
  }
}

final fullscreenProvider = NotifierProvider<FullscreenController, bool>(
  FullscreenController.new,
);
