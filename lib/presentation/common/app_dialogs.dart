import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'tv_focusable.dart';

/// App confirmation dialog: uses the global glass [DialogThemeData] and is
/// D-pad friendly — the cancel button starts focused so a TV remote can act
/// right away (a dialog with no focused node ignores the OK key), and both
/// buttons are [TvFocusable] so the remote can SEE which one it is on (bare
/// TextButtons had invisible focus with this theme: transparent highlight +
/// NoSplash).
///
/// Returns true when [confirmLabel] is chosen.
Future<bool> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Annulla',
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title, style: const TextStyle(color: AppColors.textPrimary)),
      content: Text(message, style: const TextStyle(color: AppColors.textSecondary)),
      actions: [
        _DialogButton(
          // First focus lands on the safe choice for D-pad users.
          autofocus: true,
          label: cancelLabel,
          onTap: () => Navigator.pop(context, false),
        ),
        _DialogButton(
          label: confirmLabel,
          bold: true,
          onTap: () => Navigator.pop(context, true),
        ),
      ],
    ),
  );
  return ok == true;
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.onTap,
    this.autofocus = false,
    this.bold = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool autofocus;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      borderRadius: 12,
      autofocus: autofocus,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Text(
          label,
          style: TextStyle(
            color: bold ? Colors.white : AppColors.textPrimary,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
