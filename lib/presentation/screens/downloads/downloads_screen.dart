import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/download_item.dart';
import '../../../state/downloads_providers.dart';
import '../../../data/models/watch_progress.dart';
import '../../../state/watch_progress_providers.dart';
import '../../common/icon_action.dart';
import '../../common/tv_focusable.dart';
import '../../common/watch_bar.dart';

/// Offline library. Reads only from the local Hive box (no network), so it
/// works with no connection: completed items play straight from the saved
/// file. Phone-only — reached from the home download button.
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(downloadsProvider);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: tvBackButton(context),
        title: const Text('Scaricati'),
      ),
      body: items.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Nessun download.\nScarica un film o un episodio per guardarlo offline.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) =>
                  _DownloadTile(item: items[index], autofocus: index == 0),
            ),
    );
  }
}

class _DownloadTile extends ConsumerWidget {
  const _DownloadTile({required this.item, this.autofocus = false});

  final DownloadItem item;
  final bool autofocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(downloadsProvider.notifier);
    final canPlay = item.isCompleted;

    final card = Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 108,
              height: 64,
              child: item.imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: item.imageUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => const _Thumb(),
                    )
                  : const _Thumb(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                _statusLine(),
              ],
            ),
          ),
        ],
      ),
    );

    // The action icons are SIBLINGS of the play area, never nested inside its
    // TvFocusable: a D-pad cannot move focus into a node that sits within the
    // currently focused one (same lesson as the playlist rows in Impostazioni).
    // A row that can't be played has no focusable play area: its FIRST action
    // icon takes the autofocus instead, so the screen always has a landing
    // spot for the D-pad (a list starting with a queued/failed download used
    // to leave the remote with nothing focused at all).
    final actions = _actions(notifier, autofocus: autofocus && !canPlay);

    return Row(
      children: [
        Expanded(
          // Only completed items are playable; the rest is just a card.
          child: canPlay
              ? TvFocusable(
                  autofocus: autofocus,
                  borderRadius: 12,
                  onTap: () => _play(context, ref),
                  child: card,
                )
              : card,
        ),
        ...actions,
      ],
    );
  }

  Widget _statusLine() {
    switch (item.status) {
      case DownloadStatus.completed:
        return Row(
          children: [
            const Icon(Icons.play_circle_outline, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              item.total > 0 ? 'Pronto • ${_fmtBytes(item.total)}' : 'Pronto per la visione offline',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        );
      case DownloadStatus.downloading:
        final pct = item.total > 0 ? (item.fraction * 100).round() : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            WatchBar(fraction: item.fraction),
            const SizedBox(height: 4),
            Text(
              pct != null
                  ? 'Scarico… $pct%  (${_fmtBytes(item.received)} / ${_fmtBytes(item.total)})'
                  : 'Scarico… ${_fmtBytes(item.received)}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        );
      case DownloadStatus.queued:
        return const Text('In coda…', style: TextStyle(color: AppColors.textSecondary, fontSize: 12));
      case DownloadStatus.failed:
        return Text(
          item.error ?? 'Download non riuscito.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        );
    }
  }

  /// Row actions as [IconAction]s (own focus ring, OK works): plain
  /// IconButtons had invisible focus with this theme.
  List<Widget> _actions(DownloadsNotifier notifier, {bool autofocus = false}) {
    switch (item.status) {
      case DownloadStatus.downloading:
      case DownloadStatus.queued:
        return [
          IconAction(
            icon: Icons.close,
            tooltip: 'Annulla',
            autofocus: autofocus,
            onTap: () => notifier.remove(item.key),
          ),
        ];
      case DownloadStatus.failed:
        return [
          IconAction(
            icon: Icons.refresh,
            color: Colors.white,
            tooltip: 'Riprova',
            autofocus: autofocus,
            onTap: () => notifier.retry(item.key),
          ),
          IconAction(
            icon: Icons.delete_outline,
            tooltip: 'Elimina',
            onTap: () => notifier.remove(item.key),
          ),
        ];
      case DownloadStatus.completed:
        return [
          IconAction(
            icon: Icons.delete_outline,
            tooltip: 'Elimina',
            onTap: () => notifier.remove(item.key),
          ),
        ];
    }
  }

  void _play(BuildContext context, WidgetRef ref) {
    final wp = ref.read(watchProgressProvider.notifier);
    final params = <String, String>{
      'url': item.filePath ?? '',
      // Plays from disk, but the resume point records the stream URL: the
      // local path means nothing on the TV or the PC, and "continua a
      // guardare" is synced across devices.
      'progressUrl': item.remoteUrl,
      'name': item.episodeLabel ?? item.name,
      if (item.imageUrl != null) 'poster': item.imageUrl!,
    };
    WatchProgress? progress;
    if (item.type == DownloadType.vod && item.vodId != null) {
      params['vodId'] = item.vodId!;
      progress = wp.forVod(item.vodId!);
    } else if (item.seriesId != null && item.episodeId != null) {
      params['seriesId'] = item.seriesId!;
      params['episodeId'] = item.episodeId!;
      params['epLabel'] = item.episodeLabel ?? item.name;
      progress = wp.forEpisode(item.seriesId!, item.episodeId!);
    }
    // Only a real resume point: a finished one asked the player to seek past
    // the end, which it declined — and playback started from zero instead.
    if (progress != null && progress.resumable) {
      params['resume'] = '${progress.positionMs}';
    }
    context.push(Uri(path: '/player', queryParameters: params).toString());
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      child: const Icon(Icons.movie_outlined, color: Colors.white54),
    );
  }
}

String _fmtBytes(int bytes) {
  if (bytes <= 0) return '0 MB';
  const mb = 1024 * 1024;
  if (bytes >= 1024 * mb) return '${(bytes / (1024 * mb)).toStringAsFixed(2)} GB';
  return '${(bytes / mb).toStringAsFixed(0)} MB';
}
