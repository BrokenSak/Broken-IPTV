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
  });

  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double borderRadius;

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
          // over its neighbours and overlap their captions.
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
              // The ring is an OVERLAY that sits OUTSIDE the child, never a
              // border on it — see [_FocusRing]. Clip.none lets it hang past
              // the child's box; it takes no space, so nothing reflows and the
              // neighbours don't move (the sin that got scaling removed).
              child: Stack(
                // ⚠️ passthrough, NOT the default. A Stack hands its
                // non-positioned children LOOSE constraints, so the child
                // shrank to its own content instead of filling the box its
                // parent had sized — the home tiles came out small and the ring
                // (drawn on the real box) ended up larger than the thing it was
                // framing. Reported: "i tre pulsanti sono tutti piccoli e il
                // riquadro è più grande di quello che hai evidenziato".
                // passthrough forwards the parent's constraints untouched,
                // which is what the old AnimatedContainer did.
                fit: StackFit.passthrough,
                clipBehavior: Clip.none,
                children: [
                  // ⚠️ Nothing in here may be a focus stop of its own. Android
                  // runs under `NavigationMode.directional` (app.dart), and in
                  // that mode `InkResponse._canRequestFocus` returns **true
                  // unconditionally** — so every Material ink surface nested
                  // here (a ListTile, a Chip, any button) owns a SECOND focus
                  // node over the same box. It paints no ring with this theme,
                  // and [_handleKey] above bails out unless *this* node holds
                  // the primary focus, so OK on it does nothing: an invisible
                  // dead stop. §7 already forbade putting focusable widgets in
                  // here; this enforces it once instead of asking every call
                  // site to remember an `ExcludeFocus`.
                  // NB no layout cost: Focus adds no render object, so the
                  // Stack still sees exactly one child and `passthrough` keeps
                  // handing it the parent's constraints.
                  ExcludeFocus(child: widget.child),
                  if (showRing || softHint)
                    // Negative insets: the ring hangs outside the child on
                    // every side. `Positioned` allows them; `Padding` asserts.
                    Positioned(
                      left: -_FocusRing.outset(showRing),
                      top: -_FocusRing.outset(showRing),
                      right: -_FocusRing.outset(showRing),
                      bottom: -_FocusRing.outset(showRing),
                      child: IgnorePointer(
                        child: _FocusRing(
                          radius: widget.borderRadius,
                          strong: showRing,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The selection ring: a bright edge **around** the focused element, sitting on
/// its own dark contact shadow.
///
/// Three things were wrong with the old treatment, all reported as "l'anello
/// non è chiaro e non è preciso intorno all'elemento":
///
/// 1. It was a `Border` **inside** the box, so it landed on top of the child's
///    own edge — it ate the card instead of surrounding it.
/// 2. Its radius was whatever the call site passed (16, 14, 12, 24…) while the
///    card underneath had its own, so the corners never agreed. Here the ring
///    is **concentric**: the child's radius plus the gap it stands off by.
/// 3. It carried a **white glow**. On a black catalog that reads fine; on a
///    bright film poster the ring drowned in its own halo. There is no halo
///    now — standing outside the element is what makes it legible, and it is
///    also why per-call-site `ringColor: Colors.black` overrides are gone: the
///    ring lands on the page background, never on a white fill.
///
/// It draws in an overlay with no layout cost, so unlike the scaling that was
/// removed in an earlier round, nothing shifts and no neighbour gets covered.
class _FocusRing extends StatelessWidget {
  const _FocusRing({required this.radius, required this.strong});

  /// The child's own corner radius. The ring adds [_gap] to stay concentric.
  final double radius;

  /// True for D-pad focus; false for the soft mouse-hover hint.
  final bool strong;

  /// How far the ring stands off the element. Small on purpose: the grids sit
  /// on a 10px gutter (GridMetrics.spacing on Android), so a fat offset would
  /// crowd the neighbouring tile.
  static const _gap = 2.0;

  /// Thicker where it is read from the sofa. 4px at three metres is about what
  /// 2px is at a desk.
  static double get _width => Platform.isWindows ? 3 : 4;

  static double widthFor(bool strong) => strong ? _width : 1.5;

  /// How far outside the child the ring's box starts.
  static double outset(bool strong) => _gap + widthFor(strong);

  @override
  Widget build(BuildContext context) {
    final width = widthFor(strong);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius + outset(strong)),
        border: Border.all(
          color: strong ? AppColors.focusRing : Colors.white38,
          width: width,
        ),
        // ⚠️ NO boxShadow here. A BoxShadow is a FILLED rounded rect painted
        // behind the box; with a border-only box its interior is transparent,
        // so the shadow shows straight through and greys out the element it is
        // meant to frame (caught on the Firestick: the focused tile's caption
        // went dim while its neighbours stayed white). It isn't needed either —
        // now that the ring stands outside the child it always lands on the
        // page background, never on the artwork.
      ),
    );
  }
}

/// The AppBar "back" control, visible to a D-pad. Returns null on a route that
/// cannot pop, so it drops out exactly where Material's own would.
///
/// ⚠️ Found on the Firestick itself, 2026-08-04, by driving the real app with
/// the real remote. NOT ONE AppBar in the app set a `leading:`, so every pushed
/// screen got Flutter's automatic [BackButton] — a bare Material [IconButton],
/// the one widget kind §7 forbids, because this theme (transparent
/// `highlightColor` + NoSplash) makes its focus **invisible**. Being top-left it
/// is also the first stop in reading order, so arriving on "Nuova playlist" the
/// screen looked like nothing was selected at all and pressing OK — the obvious
/// thing to do — threw you straight back out of the form.
///
/// Every audit missed it because `remote_focus_audit_test` pumps each screen as
/// the ROOT route: with nothing to pop back to, AppBar draws no back button and
/// the invisible stop does not exist. Pass `automaticallyImplyLeading: false`
/// alongside this, or Material puts its own button back when this returns null.
Widget? tvBackButton(BuildContext context) {
  if (!Navigator.of(context).canPop()) return null;
  return TvIconButton(
    tooltip: 'Indietro',
    icon: const Icon(Icons.arrow_back),
    // maybePop, like Material's BackButton: it goes through PopScope, which the
    // player and the home screen rely on to peel one layer at a time.
    onPressed: () => Navigator.maybePop(context),
  );
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
