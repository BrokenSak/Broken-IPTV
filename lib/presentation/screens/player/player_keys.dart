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

  /// Controls are visible with nothing focused: close them (tap/OK toggle).
  toggleControls,

  /// Keep the controls awake and let the focused widget handle the key.
  pokeAndPass,
}

/// Volume keys belong to the OS — the player must never react to them.
bool isVolumeKey(LogicalKeyboardKey k) =>
    k == LogicalKeyboardKey.audioVolumeUp ||
    k == LogicalKeyboardKey.audioVolumeDown ||
    k == LogicalKeyboardKey.audioVolumeMute;

/// OK / Enter / gamepad A — the "select" key across remotes and keyboards.
bool isSelectKey(LogicalKeyboardKey k) =>
    k == LogicalKeyboardKey.select ||
    k == LogicalKeyboardKey.enter ||
    k == LogicalKeyboardKey.numpadEnter ||
    k == LogicalKeyboardKey.gameButtonA;

/// Decides what a key press does in the player.
///
/// [rootHasFocus] is whether the player's root focus node holds the focus,
/// i.e. no control button is focused — only then does OK toggle the menu.
PlayerKeyAction playerKeyAction({
  required LogicalKeyboardKey key,
  required bool isKeyDown,
  required bool controlsVisible,
  required bool rootHasFocus,
}) {
  if (isVolumeKey(key)) return PlayerKeyAction.ignore;
  if (!isKeyDown) return PlayerKeyAction.ignore;
  if (!controlsVisible) return PlayerKeyAction.revealControls;
  if (rootHasFocus && isSelectKey(key)) return PlayerKeyAction.toggleControls;
  return PlayerKeyAction.pokeAndPass;
}
