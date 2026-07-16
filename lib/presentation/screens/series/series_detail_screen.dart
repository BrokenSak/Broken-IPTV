import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/download_support.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/download_item.dart';
import '../../../data/models/series_item.dart';
import '../../../data/repositories/series_repository.dart';
import '../../../state/downloads_providers.dart';
import '../../../state/series_providers.dart';
import '../../../state/watch_progress_providers.dart';
import '../../common/download_button.dart';
import '../../common/glass_dropdown.dart';
import '../../common/tv_focusable.dart';
import '../../common/watch_bar.dart';

class SeriesDetailScreen extends ConsumerStatefulWidget {
  const SeriesDetailScreen({super.key, required this.seriesId});

  final String seriesId;

  @override
  ConsumerState<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends ConsumerState<SeriesDetailScreen> {
  int? _selectedSeason;

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(seriesDetailProvider(widget.seriesId));

    return Scaffold(
      appBar: AppBar(title: const Text('Dettaglio serie')),
      body: detail.when(
        data: (series) {
          final seasons = series.episodesBySeason.keys.toList()..sort();
          if (seasons.isEmpty) {
            return const Center(child: Text('Nessun episodio disponibile.'));
          }
          _selectedSeason ??= seasons.first;
          final episodes = series.episodesBySeason[_selectedSeason] ?? const [];

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // Header: cover image + description.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 150,
                      height: 220,
                      child: series.coverUrl != null
                          ? CachedNetworkImage(imageUrl: series.coverUrl!, fit: BoxFit.cover)
                          : Container(
                              color: AppColors.surface,
                              child: const Icon(Icons.video_library_outlined, size: 40),
                            ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(series.name, style: Theme.of(context).textTheme.headlineMedium),
                        if (series.genre != null) ...[
                          const SizedBox(height: 6),
                          Text(series.genre!, style: const TextStyle(color: AppColors.textSecondary)),
                        ],
                        const SizedBox(height: 12),
                        Text(
                          (series.plot != null && series.plot!.trim().isNotEmpty)
                              ? series.plot!
                              : 'Nessuna descrizione disponibile.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Compact season selector — same style closed and open — with
              // the bulk "download this season" button beside it (phone only).
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _SeasonSelector(
                    seasons: seasons,
                    selected: _selectedSeason!,
                    episodesBySeason: series.episodesBySeason,
                    onChanged: (v) => setState(() => _selectedSeason = v),
                  ),
                  if (downloadsSupported())
                    _SeasonDownloadButton(
                      seriesId: widget.seriesId,
                      seriesName: series.name,
                      episodes: episodes,
                      fallbackImage: series.coverUrl,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              ...episodes.asMap().entries.map((e) => _EpisodeTile(
                    episode: e.value,
                    seriesId: widget.seriesId,
                    seriesName: series.name,
                    fallbackImage: series.coverUrl,
                    autofocus: e.key == 0,
                  )),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Errore: $error')),
      ),
    );
  }
}

/// Builds the download entry for one episode. Shared by the per-episode button
/// and the whole-season one, so both produce identical keys/urls/labels.
DownloadItem episodeDownloadTemplate({
  required SeriesRepository repo,
  required String seriesId,
  required String seriesName,
  required Episode episode,
  required String? image,
}) {
  final label = '${episode.episodeNum}. ${episode.title}';
  return DownloadItem(
    key: DownloadItem.episodeKey(seriesId, episode.id),
    type: DownloadType.series,
    name: '$seriesName — $label',
    remoteUrl: repo.episodeUrl(episode.id, episode.containerExtension),
    containerExtension: episode.containerExtension,
    createdAt: DateTime.now().millisecondsSinceEpoch,
    imageUrl: image,
    seriesId: seriesId,
    episodeId: episode.id,
    episodeLabel: label,
  );
}

/// Bulk-downloads every episode of the selected season (phone only). They go
/// through the same one-at-a-time queue as single downloads.
class _SeasonDownloadButton extends ConsumerWidget {
  const _SeasonDownloadButton({
    required this.seriesId,
    required this.seriesName,
    required this.episodes,
    required this.fallbackImage,
  });

  final String seriesId;
  final String seriesName;
  final List<Episode> episodes;
  final String? fallbackImage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(seriesRepositoryProvider).value;
    if (repo == null || episodes.isEmpty) return const SizedBox.shrink();

    final byKey = {for (final d in ref.watch(downloadsProvider)) d.key: d};
    var done = 0;
    var active = 0;
    for (final e in episodes) {
      final d = byKey[DownloadItem.episodeKey(seriesId, e.id)];
      if (d == null) continue;
      if (d.isCompleted) {
        done++;
      } else if (d.isActive) {
        active++;
      }
    }
    final total = episodes.length;
    final allDone = done == total;

    final String label;
    final IconData icon;
    if (allDone) {
      label = 'Stagione scaricata';
      icon = Icons.download_done;
    } else if (active > 0) {
      label = 'Scarico… $done/$total';
      icon = Icons.downloading;
    } else {
      label = 'Scarica stagione';
      icon = Icons.download_outlined;
    }

    return TvFocusable(
      borderRadius: 14,
      onTap: () async {
        if (allDone) return;
        final notifier = ref.read(downloadsProvider.notifier);
        for (final e in episodes) {
          await notifier.enqueue(episodeDownloadTemplate(
            repo: repo,
            seriesId: seriesId,
            seriesName: seriesName,
            episode: e,
            image: e.imageUrl ?? fallbackImage,
          ));
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: allDone ? Colors.white : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.glassBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: allDone ? Colors.black : AppColors.textPrimary),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: allDone ? Colors.black : AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EpisodeTile extends ConsumerWidget {
  const _EpisodeTile({
    required this.episode,
    required this.seriesId,
    required this.seriesName,
    required this.fallbackImage,
    this.autofocus = false,
  });

  final Episode episode;
  final String seriesId;
  final String seriesName;
  final String? fallbackImage;
  final bool autofocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(watchProgressProvider);
    final progress = ref.read(watchProgressProvider.notifier).forEpisode(seriesId, episode.id);
    final image = episode.imageUrl ?? fallbackImage;
    final label = '${episode.episodeNum}. ${episode.title}';
    final repo = ref.watch(seriesRepositoryProvider).value;

    final playTile = TvFocusable(
        autofocus: autofocus,
        borderRadius: 12,
        onTap: () {
          if (repo == null) return;
          final url = repo.episodeUrl(episode.id, episode.containerExtension);
          context.push(
            Uri(path: '/player', queryParameters: {
              'url': url,
              'name': label,
              'seriesId': seriesId,
              'episodeId': episode.id,
              'epLabel': label,
              // Continue-watching uses the series cover, not the episode still.
              'poster': ?fallbackImage,
              if (progress != null && !progress.finished && progress.positionMs > 5000)
                'resume': '${progress.positionMs}',
            }).toString(),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              // Video-frame style thumbnail preview.
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 128,
                  height: 72,
                  child: image != null
                      ? CachedNetworkImage(
                          imageUrl: image,
                          fit: BoxFit.cover,
                          errorWidget: (_, _, _) => Container(
                            color: AppColors.surface,
                            child: const Icon(Icons.play_circle_outline, color: Colors.white54),
                          ),
                        )
                      : Container(
                          color: AppColors.surface,
                          child: const Icon(Icons.play_circle_outline, color: Colors.white54),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${episode.episodeNum}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            episode.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.textPrimary),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    WatchBar(fraction: progress?.fraction ?? 0),
                    if (progress != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        progress.finished ? 'Visto' : 'Lasciato a ${_fmt(progress.positionMs)}',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.play_circle_outline, color: Colors.white),
            ],
          ),
        ),
      );

    // Downloads (phone/touch APK only): a peer focusable next to the play
    // tile — never nested inside it, so the D-pad gets two clean stops.
    final showDownload = downloadsSupported() && repo != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(child: playTile),
          if (showDownload) ...[
            const SizedBox(width: 8),
            DownloadButton(
              compact: true,
              template: episodeDownloadTemplate(
                repo: repo,
                seriesId: seriesId,
                seriesName: seriesName,
                episode: episode,
                image: image,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _fmt(int ms) {
    final d = Duration(milliseconds: ms);
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}

/// Compact season picker using the shared glass-styled dropdown.
class _SeasonSelector extends StatelessWidget {
  const _SeasonSelector({
    required this.seasons,
    required this.selected,
    required this.episodesBySeason,
    required this.onChanged,
  });

  final List<int> seasons;
  final int selected;
  final Map<int, List<Episode>> episodesBySeason;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return GlassDropdown<int>(
      value: selected,
      leadingIcon: Icons.subscriptions_outlined,
      onChanged: onChanged,
      items: [
        for (final s in seasons)
          GlassDropdownEntry(
            value: s,
            label: 'Stagione $s',
            trailing: '${episodesBySeason[s]!.length} ep.',
          ),
      ],
    );
  }
}
