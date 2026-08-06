import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'tv_focusable.dart';

/// A small icon action (modifica/elimina and similar) that is its own D-pad
/// focus stop, so a TV remote can reach it — a Material [IconButton] nested
/// inside a [TvFocusable] tile is unreachable by directional navigation. Used
/// by the playlist rows in Impostazioni and the profiles screen.
class IconAction extends StatelessWidget {
  const IconAction({
    super.key,
    required this.icon,
    required this.onTap,
    this.color = AppColors.textSecondary,
    this.tooltip,
    this.autofocus = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final String? tooltip;

  /// Only honoured where a D-pad is expected (see [dpadAutofocusEnabled]).
  /// Used when this icon is the first focusable thing on a screen.
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: TvFocusable(
        borderRadius: 12,
        autofocus: autofocus,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: color),
        ),
      ),
    );
  }
}
