import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/favorite_item.dart';
import '../../../data/models/series_item.dart';
import '../../../state/favorites_providers.dart';
import '../../../state/live_providers.dart' show xtreamSessionProvider;
import '../../../state/series_providers.dart';
import '../../../state/watch_progress_providers.dart';
import '../../common/app_dialogs.dart';
import '../../common/catalog_scaffold.dart';
import '../../common/error_retry.dart';
import '../../common/favorite_button.dart';
import '../../common/grid_metrics.dart';
import '../../common/tv_focusable.dart';
import '../../common/watch_bar.dart';

class SeriesScreen extends ConsumerStatefulWidget {
  const SeriesScreen({super.key});

  @override
  ConsumerState<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends ConsumerState<SeriesScreen> {
  String? _selectedCategoryId;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    if (_query.isNotEmpty) {
      return CatalogScaffold(
        title: 'Serie',
        initialQuery: _query,
        onSearch: (q) => setState(() => _query = q),
        body: _SeriesSearchResults(query: _query),
      );
    }

    final categories = ref.watch(seriesCategoriesProvider);
    return CatalogScaffold(
      title: 'Serie',
      onSearch: (q) => setState(() => _query = q),
      body: categories.when(
        data: (cats) {
          _selectedCategoryId ??= _defaultCategory(cats);
          final counts = ref.watch(seriesCategoryCountsProvider).value ?? const {};
          final adultCatIds = {for (final c in cats) if (isAdultCategory(c.name)) c.id};
          final total = counts.entries
              .where((e) => !adultCatIds.contains(e.key))
              .fold<int>(0, (a, e) => a + e.value);
          return Row(
            children: [
              CategorySidebar(
                categories: cats,
                selectedId: _selectedCategoryId!,
                counts: counts,
                showContinue: true,
                showAll: true,
                showRecent: true,
                allCount: total,
                recentCount: total > 100 ? 100 : total,
                favoritesCount:
                    ref.watch(favoritesProvider).where((f) => f.type == FavoriteType.series).length,
                continueCount:
                    ref.watch(watchProgressProvider).isEmpty
                        ? 0
                        : ref.read(watchProgressRepositoryProvider).continueSeries().length,
                onSelect: (id) => setState(() => _selectedCategoryId = id),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: _content()),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorRetry(
          message: cleanError(error),
          onRetry: () {
            ref.invalidate(xtreamSessionProvider);
            ref.invalidate(seriesRepositoryProvider);
            ref.invalidate(seriesCategoriesProvider);
          },
        ),
      ),
    );
  }

  Widget _content() {
    switch (_selectedCategoryId) {
      case kContinueCategoryId:
        return const _SeriesContinue();
      case kFavoritesCategoryId:
        return const _SeriesFavorites();
      case kAllCategoryId:
        return const _SeriesAll();
      case kRecentCategoryId:
        return const _SeriesRecent();
      default:
        return _SeriesGrid(categoryId: _selectedCategoryId!);
    }
  }

  /// First non-adult category (so we never auto-open on an adult one).
  String _defaultCategory(List cats) {
    for (final c in cats) {
      if (!isAdultCategory(c.name)) return c.id as String;
    }
    return cats.isNotEmpty ? cats.first.id as String : kFavoritesCategoryId;
  }
}

Widget _posterGrid(List<SeriesItem> items) {
  return GridView.builder(
    padding: EdgeInsets.all(GridMetrics.gridPadding),
    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: GridMetrics.posterExtent,
      mainAxisSpacing: GridMetrics.spacing,
      crossAxisSpacing: GridMetrics.spacing,
      childAspectRatio: GridMetrics.posterRatio,
    ),
    itemCount: items.length,
    itemBuilder: (context, index) => _SeriesPoster(item: items[index]),
  );
}

class _SeriesContinue extends ConsumerWidget {
  const _SeriesContinue();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(watchProgressProvider);
    final adultIds = ref.watch(adultSeriesIdsProvider).value ?? const <String>{};
    final items = ref
        .read(watchProgressRepositoryProvider)
        .continueSeries()
        .where((p) => !adultIds.contains(p.seriesId))
        .toList();
    if (items.isEmpty) {
      return const Center(child: Text('Niente da riprendere. Guarda un episodio per vederlo qui.'));
    }
    return GridView.builder(
      padding: EdgeInsets.all(GridMetrics.gridPadding),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: GridMetrics.posterExtent,
        mainAxisSpacing: GridMetrics.spacing,
        crossAxisSpacing: GridMetrics.spacing,
        childAspectRatio: GridMetrics.continueSeriesRatio,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final p = items[index];
        return TvFocusable(
          // Android/TV: long-press opens the add-to-favorites / remove sheet.
          // Windows: disabled (null) — the × button removes instead.
          onLongPress: longPressContinueOptions(
            context,
            ref,
            FavoriteItem(type: FavoriteType.series, id: p.seriesId!, name: p.name, imageUrl: p.imageUrl),
            () => ref.read(watchProgressProvider.notifier).removeSeries(p.seriesId!),
          ),
          onTap: () => context.push(
            Uri(path: '/player', queryParameters: {
              'url': p.url,
              'name': p.episodeLabel ?? p.name,
              'seriesId': p.seriesId!,
              'episodeId': p.episodeId!,
              'epLabel': p.episodeLabel ?? '',
              if (p.imageUrl != null) 'poster': p.imageUrl!,
              'resume': '${p.positionMs}',
            }).toString(),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox.expand(
                        child: p.imageUrl != null
                            ? CachedNetworkImage(imageUrl: p.imageUrl!, fit: BoxFit.cover)
                            : const _CoverFallback(),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: _RemoveButton(
                        onRemove: () => _confirmRemove(context, ref, p.seriesId!, p.name),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              WatchBar(fraction: p.fraction),
              const SizedBox(height: 4),
              Text(
                p.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
              ),
              Text(
                p.episodeLabel ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
            ],
          ),
        );
      },
    );
  }
}

Future<void> _confirmRemove(BuildContext context, WidgetRef ref, String seriesId, String name) async {
  final ok = await showAppConfirmDialog(
    context,
    title: 'Rimuovere da Continua a guardare?',
    message: '"$name" verrà rimossa da Continua a guardare.',
    confirmLabel: 'Rimuovi',
  );
  if (ok) {
    await ref.read(watchProgressProvider.notifier).removeSeries(seriesId);
  }
}

/// Small circular "×" overlay used to remove an item from Continua a guardare.
/// Works with mouse/touch; long-press on the card is the D-pad/touch fallback.
class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.onRemove});

  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Material(
        color: Colors.black.withValues(alpha: 0.6),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onRemove,
          child: const Padding(
            padding: EdgeInsets.all(5),
            child: Icon(Icons.close, color: Colors.white, size: 18),
          ),
        ),
      ),
    );
  }
}

class _SeriesFavorites extends ConsumerWidget {
  const _SeriesFavorites();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adultIds = ref.watch(adultSeriesIdsProvider).value ?? const <String>{};
    final favs = ref
        .watch(favoritesProvider)
        .where((f) => f.type == FavoriteType.series && !adultIds.contains(f.id))
        .toList();
    if (favs.isEmpty) {
      return const Center(child: Text('Nessuna serie preferita. Tocca il cuore su una serie.'));
    }
    return _posterGrid(
      favs.map((f) => SeriesItem(seriesId: f.id, name: f.name, categoryId: '', coverUrl: f.imageUrl)).toList(),
    );
  }
}

class _SeriesAll extends ConsumerWidget {
  const _SeriesAll();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(allSeriesProvider);
    final adultCats = ref.watch(adultSeriesCategoryIdsProvider).value ?? const <String>{};
    return all.when(
      data: (items) {
        final visible = items.where((i) => !adultCats.contains(i.categoryId)).toList();
        return visible.isEmpty
            ? const Center(child: Text('Nessuna serie.'))
            : _posterGrid(visible);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => ErrorRetry(
        message: cleanError(error),
        onRetry: () => ref.invalidate(allSeriesProvider),
      ),
    );
  }
}

class _SeriesRecent extends ConsumerWidget {
  const _SeriesRecent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(allSeriesProvider);
    final adultCats = ref.watch(adultSeriesCategoryIdsProvider).value ?? const <String>{};
    return all.when(
      data: (items) {
        final sorted = items.where((i) => !adultCats.contains(i.categoryId)).toList()
          ..sort((a, b) {
            final byAdded = b.added.compareTo(a.added);
            if (byAdded != 0) return byAdded;
            return (int.tryParse(b.seriesId) ?? 0).compareTo(int.tryParse(a.seriesId) ?? 0);
          });
        final recent = sorted.take(100).toList();
        if (recent.isEmpty) return const Center(child: Text('Nessuna serie.'));
        return _posterGrid(recent);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => ErrorRetry(
        message: cleanError(error),
        onRetry: () => ref.invalidate(allSeriesProvider),
      ),
    );
  }
}

class _SeriesSearchResults extends ConsumerWidget {
  const _SeriesSearchResults({required this.query});
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(allSeriesProvider);
    return all.when(
      data: (items) {
        final q = query.toLowerCase();
        final filtered = items.where((s) => s.name.toLowerCase().contains(q)).toList();
        if (filtered.isEmpty) return const Center(child: Text('Nessuna serie trovata.'));
        return _posterGrid(filtered);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => ErrorRetry(
        message: cleanError(error),
        onRetry: () => ref.invalidate(allSeriesProvider),
      ),
    );
  }
}

class _SeriesGrid extends ConsumerWidget {
  const _SeriesGrid({required this.categoryId});

  final String categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(seriesItemsProvider(categoryId));

    return items.when(
      data: (list) {
        if (list.isEmpty) {
          return const Center(child: Text('Nessuna serie in questa categoria.'));
        }
        return _posterGrid(list);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Errore: $error')),
    );
  }
}

class _SeriesPoster extends ConsumerWidget {
  const _SeriesPoster({required this.item});

  final SeriesItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TvFocusable(
      onLongPress: longPressFavorite(
        ref,
        FavoriteItem(type: FavoriteType.series, id: item.seriesId, name: item.name, imageUrl: item.coverUrl),
      ),
      onTap: () => context.push('/series/${item.seriesId}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox.expand(
                    child: item.coverUrl != null
                        ? CachedNetworkImage(
                            imageUrl: item.coverUrl!,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) => const _CoverFallback(),
                          )
                        : const _CoverFallback(),
                  ),
                ),
                // On TV this renders as a non-focusable badge (see FavoriteButton).
                Positioned(
                  top: 0,
                  right: 0,
                  child: FavoriteButton(
                    type: FavoriteType.series,
                    id: item.seriesId,
                    name: item.name,
                    imageUrl: item.coverUrl,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      alignment: Alignment.center,
      child: const Icon(Icons.video_library_outlined, size: 32, color: AppColors.textSecondary),
    );
  }
}
