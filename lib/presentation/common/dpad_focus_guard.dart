import 'package:flutter/material.dart';

import '../../core/ui_mode.dart';
// ignore: unused_import — referenced from the doc comments below.
import 'tv_focusable.dart';

/// Safety net that keeps the remote alive when the focused element disappears.
///
/// ⚠️ The bug this exists for (reported as "da TV premo OK e non succede
/// niente, da qualsiasi schermata"): when the widget holding the focus is
/// removed from the tree, Flutter does **not** hand the focus to a neighbour —
/// it leaves the enclosing scope with no focused child at all. Pointer input
/// doesn't care, so Windows and the phone never notice. A D-pad has nothing
/// left to aim at: **OK does nothing**, and it stays that way even after the
/// list comes back, until an arrow press happens to seed the focus again.
///
/// It is easy to hit because a pane can empty out on its own: closing the
/// player writes progress, which can take the very tile you were on out of
/// "Continua a guardare" (a film crossing 95% is *finished*, so it leaves), and
/// the post-player sync then invalidates the favourites/progress providers on
/// top of that. You come back from a video and the remote is dead.
///
/// So: whenever this route holds the primary focus with nothing focused inside
/// it, put the focus back on the first thing the traversal can find — exactly
/// where an arrow press would have put it. Only where a D-pad is expected
/// ([dpadAutofocusEnabled]); on a phone a focus appearing by itself is the old
/// "tasti illuminati da soli" bug.
class DpadFocusGuard extends StatefulWidget {
  const DpadFocusGuard({super.key, required this.child});

  final Widget child;

  /// Test hook, mirroring [TvFocusable.debugDpadOverride]: widget tests run on
  /// the dev machine, where the platform says Windows and the guard would
  /// always stand down.
  @visibleForTesting
  static bool? debugEnabledOverride;

  @override
  State<DpadFocusGuard> createState() => _DpadFocusGuardState();
}

class _DpadFocusGuardState extends State<DpadFocusGuard> {
  bool _scheduled = false;

  /// Whether this route ever had a focused child.
  ///
  /// ⚠️ The guard must only put back a focus that was **lost**, never hand out
  /// the first one. Without this it fired while a screen was still loading —
  /// when the only focusable thing on it is the AppBar back button — and took
  /// the focus there; the real target's `autofocus` was then ignored, because
  /// Flutter honours autofocus only while the scope has no focused child.
  /// Caught on the Firestick: arriving on a film's page the ring sat on
  /// "indietro" instead of "Guarda", so OK left the page instead of playing.
  bool _everHadFocus = false;

  /// Same gate as [TvFocusable]'s autofocus: the guard must only ever act
  /// where that widget would have honoured one.
  static bool get _enabled =>
      DpadFocusGuard.debugEnabledOverride ?? dpadAutofocusEnabled();

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChanged);
    super.dispose();
  }

  void _onFocusChanged() {
    if (!mounted || _scheduled || !_enabled) return;
    _scheduled = true;
    // Post-frame: mid-rebuild the tree is allowed to be momentarily focus-less
    // (a route transition, a dialog going up), and requesting focus there would
    // fight whoever is about to claim it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _recover();
    });
  }

  void _recover() {
    final scope = FocusScope.of(context);
    if (scope.focusedChild != null) {
      _everHadFocus = true;
      return;
    }
    // Nothing focused here yet: leave it alone. Whatever this screen declared
    // `autofocus` on is still on its way (catalogs and detail pages build their
    // real content only once the network answers) and must get there first.
    if (!_everHadFocus) return;
    // Act only when THIS route's scope is itself the primary focus: that is
    // precisely "we are on top and the focus we had is gone". If a dialog or
    // another route holds it, the focus is somebody else's business.
    if (!identical(FocusManager.instance.primaryFocus, scope)) return;
    final first = FocusTraversalGroup.of(context).findFirstFocus(scope, ignoreCurrentFocus: true);
    if (first != null && first != scope) first.requestFocus();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
