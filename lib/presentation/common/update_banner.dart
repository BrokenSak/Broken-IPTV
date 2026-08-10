import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../state/update_providers.dart';
import 'tv_focusable.dart';

/// Shown when a newer release is published (checked on open, see
/// updateCheckProvider).
///
/// ⚠️ It used to live ONLY on the home screen — which someone without a
/// playlist never reaches, so the very people who most need a fix could not
/// be offered one (found the day 1.9.1 shipped: "non mi dice aggiorna").
/// It is on the playlist screen too now. Tapping "Aggiorna" downloads the artifact
/// in-app and hands it to the OS to install (one system confirmation on
/// Android; the installer runs on Windows).
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(updateCheckProvider).value;
    if (info == null) return const SizedBox.shrink();
    final download = ref.watch(updateDownloadProvider);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.system_update, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Aggiornamento disponibile (${info.version})',
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                if (download.error != null)
                  Text(download.error!,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12))
                else if (info.notes.isNotEmpty)
                  Text(info.notes,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (download.downloading)
            _DownloadProgress(progress: download.progress)
          else
            TvFocusable(
              borderRadius: 12,
              // White button → black ring (a white one would vanish on it).
              onTap: () => ref.read(updateDownloadProvider.notifier).downloadAndInstall(info),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('Aggiorna',
                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
    );
  }
}

class _DownloadProgress extends StatelessWidget {
  const _DownloadProgress({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: progress > 0 ? progress : null,
            strokeWidth: 3,
            color: Colors.white,
            backgroundColor: Colors.white24,
          ),
          Text('${(progress * 100).round()}',
              style: const TextStyle(color: Colors.white, fontSize: 10)),
        ],
      ),
    );
  }
}

