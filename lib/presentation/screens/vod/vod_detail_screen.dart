import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/download_support.dart';
import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/download_item.dart';
import '../../../data/models/vod_item.dart';
import '../../../state/vod_providers.dart';
import '../../../state/watch_progress_providers.dart';
import '../../common/download_button.dart';
import '../../common/tv_focusable.dart';
import '../../common/watch_bar.dart';

class VodDetailScreen extends ConsumerWidget {
  const VodDetailScreen({super.key, required this.vodId});

  final String vodId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(vodDetailProvider(vodId));
    ref.watch(watchProgressProvider);
    final progress = ref.read(watchProgressProvider.notifier).forVod(vodId);
    // A finished (or barely started) entry is not something to seek to: asking
    // the player to jump past the end made it start at zero while the button
    // still said "Riprendi".
    final resumeMs = (progress != null && progress.resumable) ? progress.positionMs : 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Dettaglio film')),
      body: detail.when(
        data: (movie) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 200,
                        height: 290,
                        child: movie.posterUrl != null
                            ? CachedNetworkImage(imageUrl: movie.posterUrl!, fit: BoxFit.cover)
                            : Container(
                                color: AppColors.surface,
                                child: const Icon(Icons.movie_outlined, size: 40),
                              ),
                      ),
                    ),
                    if (progress != null) ...[
                      const SizedBox(height: 10),
                      SizedBox(width: 200, child: WatchBar(fraction: progress.fraction)),
                      const SizedBox(height: 4),
                      Text(
                        progress.finished
                            ? 'Visto'
                            : 'Ripreso al ${formatHms(Duration(milliseconds: progress.positionMs))}',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ],
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(movie.name, style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        children: [
                          if (movie.rating != null)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star_rounded, size: 16, color: Colors.white),
                                const SizedBox(width: 3),
                                Text(movie.rating!.toStringAsFixed(1)),
                              ],
                            ),
                          if (movie.releaseDate != null) Text(movie.releaseDate!),
                          if (movie.genre != null) Text(movie.genre!),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text('Descrizione', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 6),
                      Text(
                        (movie.plot != null && movie.plot!.trim().isNotEmpty)
                            ? movie.plot!
                            : 'Nessuna descrizione disponibile.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 10),
                      if (movie.director != null) Text('Regia: ${movie.director}'),
                      if (movie.cast != null) Text('Cast: ${movie.cast}'),
                      const SizedBox(height: 24),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          // TvFocusable + ExcludeFocus inner button: one D-pad
                          // stop with a visible ring (bare Material buttons
                          // have invisible focus with this theme). The play
                          // button is white → black ring.
                          TvFocusable(
                            borderRadius: 14,
                            autofocus: true,
                            ringColor: Colors.black,
                            onTap: () => _play(context, ref, movie,
                                resumeMs: resumeMs),
                            child: ExcludeFocus(
                              child: ElevatedButton.icon(
                                onPressed: () => _play(context, ref, movie,
                                    resumeMs: resumeMs),
                                icon: const Icon(Icons.play_arrow),
                                // "Riprendi" only when it really will resume.
                                label: Text(resumeMs > 0 ? 'Riprendi' : 'Guarda'),
                              ),
                            ),
                          ),
                          if (resumeMs > 0)
                            TvFocusable(
                              borderRadius: 14,
                              onTap: () => _play(context, ref, movie, resumeMs: 0),
                              child: ExcludeFocus(
                                child: OutlinedButton.icon(
                                  onPressed: () => _play(context, ref, movie, resumeMs: 0),
                                  icon: const Icon(Icons.replay),
                                  label: const Text('Dall\'inizio'),
                                ),
                              ),
                            ),
                          // Downloads: phone (touch) mode on the APK only.
                          if (downloadsSupported()) _downloadButton(ref, movie),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Errore: $error')),
      ),
    );
  }

  Widget _downloadButton(WidgetRef ref, VodDetail movie) {
    final repo = ref.watch(vodRepositoryProvider).value;
    if (repo == null) return const SizedBox.shrink();
    return DownloadButton(
      template: DownloadItem(
        key: DownloadItem.vodKey(movie.streamId),
        type: DownloadType.vod,
        name: movie.name,
        remoteUrl: repo.streamUrl(movie.streamId, movie.containerExtension),
        containerExtension: movie.containerExtension,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        imageUrl: movie.posterUrl,
        vodId: vodId,
      ),
    );
  }

  void _play(BuildContext context, WidgetRef ref, dynamic movie, {required int resumeMs}) {
    final repo = ref.read(vodRepositoryProvider).value;
    if (repo == null) return;
    final url = repo.streamUrl(movie.streamId, movie.containerExtension);
    context.push(
      Uri(path: '/player', queryParameters: {
        'url': url,
        'name': movie.name,
        'vodId': vodId,
        if (movie.posterUrl != null) 'poster': movie.posterUrl as String,
        if (resumeMs > 0) 'resume': '$resumeMs',
      }).toString(),
    );
  }

}
