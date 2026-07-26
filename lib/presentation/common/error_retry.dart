import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'tv_focusable.dart';

/// Full-screen error placeholder with a Retry action, used by the catalog
/// screens so a transient panel error (or missing playlist) is clear and
/// recoverable instead of an ambiguous blank state.
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(height: 24),
            TvFocusable(
              autofocus: true,
              borderRadius: 14,
              // The button is white: black ring (white would vanish on it).
              ringColor: Colors.black,
              onTap: onRetry,
              // ExcludeFocus: the inner button must not be a SECOND, invisible
              // focus stop nested in the TvFocusable (mouse clicks still land).
              child: ExcludeFocus(
                child: ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Riprova'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Strips the Dart "Exception:" prefix for cleaner display of our
/// exception messages.
String cleanError(Object error) {
  final text = error.toString();
  return text.replaceFirst(RegExp(r'^Exception:\s*'), '');
}
