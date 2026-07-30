import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../core/ui_mode.dart';

/// Wraps a child so it works with pointer (mouse/touch) *and* D-pad input.
///
/// Focus rules (each learned the hard way):
/// - **Focusable on any Android build** ([dpadFocusEnabled]), never on
///   Windows. Gating focusability on the saved TV mode locked fresh installs
///   out — the device picker shows *before* a mode exists, so nothing was
///   focusable and the remote couldn't even choose "TV".
/// - **Autofocus only where a D-pad is expected** ([dpadAutofocusEnabled]):
///   TV mode or no mode chosen yet. Honouring it on phones lit up the first
///   tile of every grid on its own.
/// - **The focus RING shows only in D-pad mode** ([dpadHighlightVisible]).
///   Android nodes stay focusable everywhere (so the remote always works), but
///   on a phone a focused node must look no different — the feedback there is a
///   momentary press highlight, and on Windows the mouse hover. Otherwise a
///   stray focus leaves a ring that touch can't clear ("la prima voce resta
///   evidenziata").
///
/// The widget is a single focus node (a previous version nested two, so the
/// D-pad focus landed on the node without the key handler and OK did
/// nothing): OK activates on key-up, and holding OK (key repeat) triggers
/// [onLongPress] — the D-pad equivalent of a touch long-press.
class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.borderRadius = 16,
    this.autofocus = false,
    this.focusNode,
    this.ringColor,
  });

  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double borderRadius;

  /// Focus ring colour override. The default white ring disappears on a
  /// white-filled child (selected playlist, floating player pill): those pass
  /// black here — "se lo sfondo è bianco, il quadrato è nero" (user rule).
  final Color? ringColor;

  /// Only honoured where a D-pad is expected (see [dpadAutofocusEnabled]).
  final bool autofocus;
  final FocusNode? focusNode;

  /// Test hook: forces D-pad (TV) behaviour regardless of the host platform
  /// (widget tests run on the dev machine, where Platform says Windows).
  /// true = TV (focusable + autofocus), false = Windows (no focus at all).
  @visibleForTesting
  static bool? debugDpadOverride;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  bool _hovered = false;
  bool _pressed = false;
  bool _selectDown = false;
  bool _longPressFired = false;

  /// Key-repeat events seen in the current OK press.
  int _repeats = 0;

  /// How many repeats make a hold. Android's first repeat lands ~400ms in and
  /// the rest ~50ms apart, so this is roughly 0.6s of deliberate holding —
  /// comfortably above a firm press, which must still be a plain tap.
  static const _repeatsForLongPress = 4;

  /// Whether this element takes part in D-pad focus at all.
  static bool get _focusable => TvFocusable.debugDpadOverride ?? dpadFocusEnabled();

  /// Whether autofocus requests are honoured.
  static bool get _autofocusEnabled =>
      TvFocusable.debugDpadOverride ?? dpadAutofocusEnabled();

  /// Whether a focused node paints the ring (D-pad in use).
  static bool get _ringVisible =>
      TvFocusable.debugDpadOverride ?? dpadHighlightVisible();

  /// Hover highlight is a mouse thing, i.e. Windows only.
  static bool get _hoverEnabled => Platform.isWindows;

  static bool _isSelectKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA;
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    // Only act when this very node is focused: when a focusable descendant
    // (e.g. an IconButton inside the tile) has the focus, its own action must
    // win, so let the event bubble up to the app-level shortcuts.
    if (!node.hasPrimaryFocus) return KeyEventResult.ignored;
    if (!_isSelectKey(event.logicalKey)) return KeyEventResult.ignored;

    if (event is KeyDownEvent) {
      _selectDown = true;
      _longPressFired = false;
      _repeats = 0;
      return KeyEventResult.handled;
    }
    if (event is KeyRepeatEvent) {
      // Holding OK = long-press (used by "Continua a guardare" tiles on TV).
      //
      // ⚠️ NOT on the first repeat. Android starts repeating ~400ms into a
      // press, so a normally firm press on a TV remote produced one repeat →
      // long-press → and the tap was swallowed: OK "did nothing" and the tile
      // never opened (it silently toggled the favourite instead). A real hold
      // has to keep going: repeats land ~50ms apart, so this is ~0.6s.
      _repeats++;
      if (widget.onLongPress != null &&
          !_longPressFired &&
          _repeats >= _repeatsForLongPress) {
        _longPressFired = true;
        widget.onLongPress!();
      }
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      final shouldTap = _selectDown && !_longPressFired;
      _selectDown = false;
      _longPressFired = false;
      _repeats = 0;
      if (shouldTap) widget.onTap();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      // On Windows this node is invisible to the focus system entirely. On
      // Android it is always focusable (a remote must work even in the wrong
      // mode), but only pre-lights itself where a D-pad is expected.
      autofocus: widget.autofocus && _autofocusEnabled,
      canRequestFocus: _focusable,
      skipTraversal: !_focusable,
      onKeyEvent: _handleKey,
      child: Builder(
        builder: (context) {
          // Focus.of registers a dependency, so this subtree rebuilds when
          // the focus state changes.
          final focused = Focus.of(context).hasPrimaryFocus;
          // The ring (persistent) is D-pad only. Hover (mouse) and press
          // (touch/click) are momentary soft hints for the other platforms.
          final showRing = focused && _ringVisible;
          final softHint = !showRing && (_hovered || _pressed);

          // NB: no scaling. A focused tile used to grow, which made it spill
          // over its neighbours and overlap their captions. The ring + glow
          // carries the focus on its own, and the border width is constant
          // (only the colour changes) so nothing shifts when focus moves.
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: _hoverEnabled ? (_) => setState(() => _hovered = true) : null,
            onExit: _hoverEnabled ? (_) => setState(() => _hovered = false) : null,
            child: GestureDetector(
              onTap: widget.onTap,
              onLongPress: widget.onLongPress,
              // Momentary press feedback (touch on phone, click on Windows).
              onTapDown: (_) => setState(() => _pressed = true),
              onTapUp: (_) => setState(() => _pressed = false),
              onTapCancel: () => setState(() => _pressed = false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 130),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  border: Border.all(
                    color: showRing
                        ? (widget.ringColor ?? AppColors.focusRing)
                        : (softHint ? Colors.white38 : Colors.transparent),
                    width: 3,
                  ),
                  boxShadow: showRing
                      ? [
                          // Kept tight: a wide/bright glow bleeds onto the
                          // neighbours and makes them look selected too.
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.22),
                            blurRadius: 12,
                          ),
                        ]
                      : null,
                ),
                child: widget.child,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// An icon button for app bars / toolbars that goes through [TvFocusable], so a
/// D-pad focuses it with the same white ring as the rest of the app. A plain
/// Material [IconButton] only shows a faint focus highlight here (the theme
/// zeroes `highlightColor` + uses `NoSplash`), which on TV looked like the
/// button couldn't be reached. Tap, click and OK all fire [onPressed]; the
/// [tooltip] is an accessibility label only (no pop-up box).
class TvIconButton extends StatelessWidget {
  const TvIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final Widget icon;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: TvFocusable(
        borderRadius: 24,
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: icon,
        ),
      ),
    );
  }
}
