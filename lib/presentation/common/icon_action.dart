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
    this.ringColor,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final String? tooltip;

  /// Focus ring override: pass black when the action sits on a white surface
  /// (e.g. the selected, white-filled playlist row), where the default white
  /// ring would be invisible.
  final Color? ringColor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: TvFocusable(
        borderRadius: 12,
        ringColor: ringColor,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: color),
        ),
      ),
    );
  }
}
