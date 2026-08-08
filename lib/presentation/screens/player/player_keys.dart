import 'package:flutter/services.dart';

/// What a key press should do in the player.
///
/// Kept out of the widget (and away from media_kit) so the rules are pure and
/// testable: the volume-key bug below shipped once already.
enum PlayerKeyAction {
  /// Not ours: let it through untouched. Volume keys land here so the OS
  /// changes the volume — consuming them is exactly what broke them before.
  ignore,

  /// Controls are hidden: reveal them and consume the key, so it can't
  /// blind-activate a button that is invisible but still focusable.
  revealControls,

  /// Keep the controls awake and let the focused widget handle the key: with
  /// the controls up, OK belongs to the focused button, and the arrows to the
  /// focus traversal. Closing is Back's job (and the auto-hide timer's).
  pokeAndPass,

  /// Desktop keyboard media controls (space / arrows) — see [playerKeyAction].
  playPause,
  seekForward,
  seekBackward,

  /// Windows ↑/↓: one step of the player's own 0–100 volume. Unlike the OS
  /// volume keys above these are ours to consume — the arrows are dead on
  /// Windows anyway (suppressed in app.dart).
  volumeUp,
  volumeDown,
}

/// Volume keys belong to the OS — the player must never react to them.
bool isVolumeKey(LogicalKeyboardKey k) =>
    k == LogicalKeyboardKey.audioVolumeUp ||
    k == LogicalKeyboardKey.audioVolumeDown ||
    k == LogicalKeyboardKey.audioVolumeMute;

/// Back belongs to navigation, never to the controls.
///
/// ⚠️ It used to fall through to the catch-all below, so with the controls
/// hidden a Back press was **swallowed to reopen them** instead of leaving.
/// Pressing it again hid them, again reopened them… the player flip-flopped and
/// wouldn't exit, and holding the button made it strobe on key repeat
/// ("premendo back apre e chiude il player, fa robe strane"). Back is the
/// business of `PopScope`, which already peels one layer at a time: overlay →
/// controls → exit. The key handler must keep its hands off it.
bool isBackKey(LogicalKeyboardKey k) =>
    k == LogicalKeyboardKey.goBack ||
    k == LogicalKeyboardKey.browserBack ||
    k == LogicalKeyboardKey.escape;

/// OK / Enter / gamepad A — the "select" key across remotes and keyboards.
bool isSelectKey(LogicalKeyboardKey k) =>
    k == LogicalKeyboardKey.select ||
    k == LogicalKeyboardKey.enter ||
    k == LogicalKeyboardKey.numpadEnter ||
    k == LogicalKeyboardKey.gameButtonA;

/// Decides what a key press does in the player.
///
/// On **desktop** (Windows: mouse + keyboard) the arrows are otherwise dead
/// (globally suppressed in app.dart so they can't drive focus traversal), so
/// the player repurposes them: Space toggles play/pause, ←/→ seek, **↑/↓
/// volume**. Not on TV, where the arrows are the D-pad and would clash with
/// navigation.
///
/// ↑/↓ work on **live too** — only pause and seek are meaningless there, the
/// volume is not (user request: "su windows freccia su e giu devono alzare e
/// abbassare volume"). That's why the volume check sits outside the `!isLive`
/// block.
///
/// Otherwise: once the controls are up every key belongs to them (OK presses
/// the focused button, arrows traverse); when hidden, any key reveals them.
/// There is no "close" here — that's Back's job and the inactivity timer's.
PlayerKeyAction playerKeyAction({
  required LogicalKeyboardKey key,
  required bool isKeyDown,
  required bool controlsVisible,
  bool isDesktop = false,
  bool isLive = false,
}) {
  // Volume is the OS's, Back is the navigator's. Never ours, in any state.
  if (isVolumeKey(key) || isBackKey(key)) return PlayerKeyAction.ignore;
  if (!isKeyDown) return PlayerKeyAction.ignore;

  if (isDesktop) {
    if (key == LogicalKeyboardKey.arrowUp) return PlayerKeyAction.volumeUp;
    if (key == LogicalKeyboardKey.arrowDown) return PlayerKeyAction.volumeDown;
    if (!isLive) {
      if (key == LogicalKeyboardKey.space) return PlayerKeyAction.playPause;
      if (key == LogicalKeyboardKey.arrowRight) {
        return PlayerKeyAction.seekForward;
      }
      if (key == LogicalKeyboardKey.arrowLeft) {
        return PlayerKeyAction.seekBackward;
      }
    }
  }

  if (!controlsVisible) return PlayerKeyAction.revealControls;
  return PlayerKeyAction.pokeAndPass;
}
