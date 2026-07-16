import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';

/// Wraps a child so it works with both pointer (mouse/touch) and D-pad input.
///
/// On Windows only mouse+keyboard are used, so the node never takes focus and
/// only the hover highlight shows. On Android the widget is a single focus
/// node (a previous version nested two nodes, so the D-pad focus landed on a
/// node without the key handler and OK did nothing): OK activates on key-up,
/// and holding OK (key repeat) triggers [onLongPress] — the D-pad equivalent
/// of a touch long-press.
class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.borderRadius = 16,
    this.autofocus = false,
    this.focusNode,
  });

  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double borderRadius;
  final bool autofocus;
  final FocusNode? focusNode;

  /// Test hook: forces desktop/TV behavior regardless of the host platform
  /// (widget tests run on the dev machine, where Platform says Windows).
  @visibleForTesting
  static bool? debugIsDesktopOverride;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  bool _hovered = false;
  bool _selectDown = false;
  bool _longPressFired = false;

  static bool get _isDesktop =>
      TvFocusable.debugIsDesktopOverride ?? Platform.isWindows;

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
      return KeyEventResult.handled;
    }
    if (event is KeyRepeatEvent) {
      // Holding OK = long-press (used by "Continua a guardare" tiles on TV).
      if (widget.onLongPress != null && !_longPressFired) {
        _longPressFired = true;
        widget.onLongPress!();
      }
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent) {
      final shouldTap = _selectDown && !_longPressFired;
      _selectDown = false;
      _longPressFired = false;
      if (shouldTap) widget.onTap();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      // Never grab focus on desktop: arrow-key navigation is Windows-disabled
      // and Enter must not activate tiles there.
      autofocus: widget.autofocus && !_isDesktop,
      canRequestFocus: !_isDesktop,
      skipTraversal: _isDesktop,
      onKeyEvent: _handleKey,
      child: Builder(
        builder: (context) {
          // Focus.of registers a dependency, so this subtree rebuilds when
          // the focus state changes.
          final focused = Focus.of(context).hasPrimaryFocus;

          // NB: no scaling. A focused tile used to grow, which made it spill
          // over its neighbours and overlap their captions. The ring + glow
          // carries the focus on its own, and the border width is constant
          // (only the colour changes) so nothing shifts when focus moves.
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              onTap: widget.onTap,
              onLongPress: widget.onLongPress,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 130),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  border: Border.all(
                    // Focus (remote/keyboard) must be unmistakable; hover is
                    // only a soft hint.
                    color: focused
                        ? AppColors.focusRing
                        : (_hovered ? Colors.white38 : Colors.transparent),
                    width: 3,
                  ),
                  boxShadow: focused
                      ? [
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.28),
                            blurRadius: 16,
                            spreadRadius: 1,
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
