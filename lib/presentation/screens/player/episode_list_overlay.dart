import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/series_item.dart';
import '../../../state/series_providers.dart';
import '../../../state/watch_progress_providers.dart';
import '../../common/glass_dropdown.dart';
import '../../common/tv_focusable.dart';
import '../../common/watch_bar.dart';

/// Bottom-left overlay listing the episodes of the series being played, so you
/// can switch episode — or season — without leaving the player. The on-demand
/// twin of [ChannelListOverlay].
///
/// The season selector is the same glass dropdown as the channel list's
/// category picker; each row carries a watch bar (empty / partial / full) so
/// you can see, at a glance, what you've finished and where you left off.
///
/// Every stop is a [TvFocusable] (rows, dropdown, close button): the bare
/// ListTile/IconButton the first version used had invisible focus on TV
/// (the theme zeroes `highlightColor`), which read as "not selectable".
class EpisodeListOverlay extends ConsumerStatefulWidget {
  const EpisodeListOverlay({
    super.key,
    required this.seriesId,
    required this.currentEpisodeId,
    required this.fallbackImage,
    required this.onClose,
    required this.onSelect,
  });

  final String seriesId;
  final String? currentEpisodeId;
  final String? fallbackImage;
  final VoidCallback onClose;
  final void Function(Episode episode) onSelect;

  @override
  ConsumerState<EpisodeListOverlay> createState() => _EpisodeListOverlayState();
}

class _EpisodeListOverlayState extends ConsumerState<EpisodeListOverlay> {
  int? _season;

  /// First row of the list, so a season change can drop the D-pad straight
  /// back into the (rebuilt) list instead of leaving the focus stranded.
  final _firstRowNode = FocusNode(debugLabel: 'episodes.first');

  @override
  void dispose() {
    _firstRowNode.dispose();
    super.dispose();
  }

  int? _seasonOf(SeriesDetail detail, String? episodeId) {
    if (episodeId == null) return null;
    for (final entry in detail.episodesBySeason.entries) {
      if (entry.value.any((e) => e.id == episodeId)) return entry.key;
    }
    return null;
  }

  void _selectSeason(int season) {
    setState(() => _season = season);
    // After the menu closes and the re-keyed list mounts, land on episode 1.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _firstRowNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final panelW = (size.width * 0.9).clamp(260.0, 460.0);
    // Sit above the bottom controls (bottomOffset) and below the top bar.
    const bottomOffset = 140.0;
    final panelH = (size.height - bottomOffset - 96).clamp(220.0, 560.0);

    final detailAsync = ref.watch(seriesDetailProvider(widget.seriesId));
    // Rebuild the tiles' watch bars as progress is saved while playing.
    ref.watch(watchProgressProvider);
    final progressBy = ref.read(watchProgressProvider.notifier);

    return Positioned.fill(
      child: Stack(
        children: [
          // Tap outside the panel to dismiss.
          Positioned.fill(
            child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onClose),
          ),
          Positioned(
            left: 12,
            bottom: bottomOffset,
            width: panelW,
            height: panelH,
            child: detailAsync.when(
              loading: () => _panel(const Center(child: CircularProgressIndicator())),
              error: (e, _) => _panel(Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('$e', style: const TextStyle(color: AppColors.textSecondary)),
                ),
              )),
              data: (detail) {
                final seasons = detail.episodesBySeason.keys.toList()..sort();
                if (seasons.isEmpty) {
                  return _panel(const Center(
                    child: Text('Nessun episodio.',
                        style: TextStyle(color: AppColors.textSecondary)),
                  ));
                }
                // Open on the season of the episode being watched; fall back to
                // the first if it's not found (or nothing is playing yet).
                _season ??= _seasonOf(detail, widget.currentEpisodeId) ?? seasons.first;
                final season = seasons.contains(_season) ? _season! : seasons.first;
                final episodes = detail.episodesBySeason[season] ?? const <Episode>[];

                return _panel(Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header: season dropdown (same as the channel list's) + close.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 6, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: GlassDropdown<int>(
                              value: season,
                              expand: true,
                              leadingIcon: Icons.subscriptions_outlined,
                              onChanged: _selectSeason,
                              items: [
                                for (final s in seasons)
                                  GlassDropdownEntry<int>(
                                    value: s,
                                    label: 'Stagione $s',
                                    trailing: '${detail.episodesBySeason[s]!.length} ep.',
                                  ),
                              ],
                            ),
                          ),
                          TvIconButton(
                            tooltip: 'Chiudi',
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: widget.onClose,
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.builder(
                        // Re-keyed per season so changing season rebuilds the
                        // list from scratch — resetting the scroll to the top
                        // and re-firing the first row's autofocus (D-pad).
                        key: ValueKey(season),
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                        itemCount: episodes.length,
                        itemBuilder: (context, index) {
                          final Episode e = episodes[index];
                          final selected = e.id == widget.currentEpisodeId;
                          final image = e.imageUrl ?? widget.fallbackImage;
                          final progress = progressBy.forEpisode(widget.seriesId, e.id);
                          return TvFocusable(
                            borderRadius: 12,
                            // D-pad: enter the list right away when the
                            // overlay opens (policy-gated: TV only).
                            autofocus: index == 0,
                            focusNode: index == 0 ? _firstRowNode : null,
                            onTap: () => widget.onSelect(e),
                            child: ListTile(
                              // Uniform row height (and top-aligned thumbnail)
                              // whether or not there's a "left off at" line.
                              isThreeLine: true,
                              selected: selected,
                              selectedTileColor: Colors.white.withValues(alpha: 0.08),
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: SizedBox(
                                  width: 64,
                                  height: 40,
                                  child: image != null
                                      ? CachedNetworkImage(
                                          imageUrl: image,
                                          fit: BoxFit.cover,
                                          errorWidget: (_, _, _) => const ColoredBox(
                                            color: AppColors.surface,
                                            child: Icon(Icons.play_circle_outline,
                                                color: Colors.white54, size: 20),
                                          ),
                                        )
                                      : const ColoredBox(
                                          color: AppColors.surface,
                                          child: Icon(Icons.play_circle_outline,
                                              color: Colors.white54, size: 20),
                                        ),
                                ),
                              ),
                              title: Text(
                                '${e.episodeNum}. ${e.title}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: selected ? Colors.white : AppColors.textPrimary,
                                  fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                                ),
                              ),
                              // "La classica barra sotto": how much of the
                              // episode you've watched, with where you left off
                              // or "Visto".
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    WatchBar(fraction: progress?.fraction ?? 0),
                                    if (progress != null) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        progress.finished
                                            ? 'Visto'
                                            : 'Lasciato a ${formatHms(Duration(milliseconds: progress.positionMs))}',
                                        style: const TextStyle(
                                            color: AppColors.textSecondary, fontSize: 11),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              trailing: selected
                                  ? const Icon(Icons.equalizer, color: Colors.white, size: 18)
                                  : null,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ));
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel(Widget child) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      // ListTile paints its selected background on the nearest Material: give
      // it a transparent one INSIDE the decorated panel (without it, Flutter
      // asserts in debug and the selected highlight can vanish).
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}
