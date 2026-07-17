import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/favorite_item.dart';
import '../../../data/models/vod_item.dart';
import '../../../state/favorites_providers.dart';
import '../../../state/live_providers.dart' show xtreamSessionProvider;
import '../../../state/vod_providers.dart';
import '../../../state/watch_progress_providers.dart';
import '../../common/app_dialogs.dart';
import '../../common/catalog_scaffold.dart';
import '../../common/error_retry.dart';
import '../../common/favorite_button.dart';
import '../../common/grid_metrics.dart';
import '../../common/tv_focusable.dart';
import '../../common/watch_bar.dart';

class VodScreen extends ConsumerStatefulWidget {
  const VodScreen({super.key});

  @override
  ConsumerState<VodScreen> createState() => _VodScreenState();
}

class _VodScreenState extends ConsumerState<VodScreen> {
  String? _selectedCategoryId;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    if (_query.isNotEmpty) {
      return CatalogScaffold(
        title: 'Film',
        initialQuery: _query,
        onSearch: (q) => setState(() => _query = q),
        body: _VodSearchResults(query: _query),
      );
    }

    final categories = ref.watch(vodCategoriesProvider);
    return CatalogScaffold(
      title: 'Film',
      onSearch: (q) => setState(() => _query = q),
      body: categories.when(
        data: (cats) {
          _selectedCategoryId ??= _defaultCategory(cats);
          final counts = ref.watch(vodCategoryCountsProvider).value ?? const {};
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
                    ref.watch(favoritesProvider).where((f) => f.type == FavoriteType.vod).length,
                continueCount:
                    ref.watch(watchProgressProvider).isEmpty
                        ? 0
                        : ref.read(watchProgressRepositoryProvider).continueMovies().length,
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
            ref.invalidate(vodRepositoryProvider);
            ref.invalidate(vodCategoriesProvider);
          },
        ),
      ),
    );
  }

  Widget _content() {
    switch (_selectedCategoryId) {
      case kContinueCategoryId:
        return const _VodContinue();
      case kFavoritesCategoryId:
        return const _VodFavorites();
      case kAllCategoryId:
        return const _VodAll();
      case kRecentCategoryId:
        return const _VodRecent();
      default:
        return _VodGrid(categoryId: _selectedCategoryId!);
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

Widget _posterGrid(List<VodItem> items) {
  return GridView.builder(
    padding: EdgeInsets.all(GridMetrics.gridPadding),
    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: GridMetrics.posterExtent,
      mainAxisSpacing: GridMetrics.spacing,
      crossAxisSpacing: GridMetrics.spacing,
      childAspectRatio: GridMetrics.posterRatio,
    ),
    itemCount: items.length,
    itemBuilder: (context, index) => _VodPoster(item: items[index]),
  );
}

class _VodContinue extends ConsumerWidget {
  const _VodContinue();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(watchProgressProvider);
    final adultIds = ref.watch(adultVodIdsProvider).value ?? const <String>{};
    final items = ref
        .read(watchProgressRepositoryProvider)
        .continueMovies()
        .where((p) => !adultIds.contains(p.vodId))
        .toList();
    if (items.isEmpty) {
      return const Center(child: Text('Niente da riprendere. Guarda un film per vederlo qui.'));
    }
    return GridView.builder(
      padding: EdgeInsets.all(GridMetrics.gridPadding),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: GridMetrics.posterExtent,
        mainAxisSpacing: GridMetrics.spacing,
        crossAxisSpacing: GridMetrics.spacing,
        childAspectRatio: GridMetrics.continueVodRatio,
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
            FavoriteItem(type: FavoriteType.vod, id: p.vodId!, name: p.name, imageUrl: p.imageUrl),
            () => ref.read(watchProgressProvider.notifier).remove(p.key),
          ),
          onTap: () => context.push(
            Uri(path: '/player', queryParameters: {
              'url': p.url,
              'name': p.name,
              'vodId': p.vodId!,
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
                            : const _PosterFallback(),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: _RemoveButton(
                        onRemove: () => _confirmRemoveVod(context, ref, p.key, p.name),
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
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
              ),
            ],
          ),
        );
      },
    );
  }
}

Future<void> _confirmRemoveVod(BuildContext context, WidgetRef ref, String key, String name) async {
  final ok = await showAppConfirmDialog(
    context,
    title: 'Rimuovere da Continua a guardare?',
    message: '"$name" verrà rimosso da Continua a guardare.',
    confirmLabel: 'Rimuovi',
  );
  if (ok) {
    await ref.read(watchProgressProvider.notifier).remove(key);
  }
}

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

class _VodFavorites extends ConsumerWidget {
  const _VodFavorites();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adultIds = ref.watch(adultVodIdsProvider).value ?? const <String>{};
    final favs = ref
        .watch(favoritesProvider)
        .where((f) => f.type == FavoriteType.vod && !adultIds.contains(f.id))
        .toList();
    if (favs.isEmpty) {
      return const Center(child: Text('Nessun film preferito. Tocca il cuore su un film.'));
    }
    return _posterGrid(
      favs.map((f) => VodItem(streamId: f.id, name: f.name, categoryId: '', posterUrl: f.imageUrl)).toList(),
    );
  }
}

class _VodAll extends ConsumerWidget {
  const _VodAll();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(allVodProvider);
    final adultCats = ref.watch(adultVodCategoryIdsProvider).value ?? const <String>{};
    return all.when(
      data: (items) {
        final visible = items.where((i) => !adultCats.contains(i.categoryId)).toList();
        return visible.isEmpty
            ? const Center(child: Text('Nessun film.'))
            : _posterGrid(visible);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => ErrorRetry(
        message: cleanError(error),
        onRetry: () => ref.invalidate(allVodProvider),
      ),
    );
  }
}

class _VodRecent extends ConsumerWidget {
  const _VodRecent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(allVodProvider);
    final adultCats = ref.watch(adultVodCategoryIdsProvider).value ?? const <String>{};
    return all.when(
      data: (items) {
        final sorted = items.where((i) => !adultCats.contains(i.categoryId)).toList()
          ..sort((a, b) {
            final byAdded = b.added.compareTo(a.added);
            if (byAdded != 0) return byAdded;
            return (int.tryParse(b.streamId) ?? 0).compareTo(int.tryParse(a.streamId) ?? 0);
          });
        final recent = sorted.take(100).toList();
        if (recent.isEmpty) return const Center(child: Text('Nessun film.'));
        return _posterGrid(recent);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => ErrorRetry(
        message: cleanError(error),
        onRetry: () => ref.invalidate(allVodProvider),
      ),
    );
  }
}

class _VodSearchResults extends ConsumerWidget {
  const _VodSearchResults({required this.query});
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(allVodProvider);
    return all.when(
      data: (items) {
        final q = query.toLowerCase();
        final filtered = items.where((m) => m.name.toLowerCase().contains(q)).toList();
        if (filtered.isEmpty) return const Center(child: Text('Nessun film trovato.'));
        return _posterGrid(filtered);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => ErrorRetry(
        message: cleanError(error),
        onRetry: () => ref.invalidate(allVodProvider),
      ),
    );
  }
}

class _VodGrid extends ConsumerWidget {
  const _VodGrid({required this.categoryId});

  final String categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(vodItemsProvider(categoryId));

    return items.when(
      data: (list) {
        if (list.isEmpty) {
          return const Center(child: Text('Nessun film in questa categoria.'));
        }
        return _posterGrid(list);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Errore: $error')),
    );
  }
}

class _VodPoster extends ConsumerWidget {
  const _VodPoster({required this.item});

  final VodItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TvFocusable(
      onLongPress: longPressFavorite(
        ref,
        FavoriteItem(type: FavoriteType.vod, id: item.streamId, name: item.name, imageUrl: item.posterUrl),
      ),
      onTap: () => context.push('/vod/${item.streamId}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox.expand(
                    child: item.posterUrl != null
                        ? CachedNetworkImage(
                            imageUrl: item.posterUrl!,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) => const _PosterFallback(),
                          )
                        : const _PosterFallback(),
                  ),
                ),
                // On TV this renders as a non-focusable badge (see FavoriteButton).
                Positioned(
                  top: 0,
                  right: 0,
                  child: FavoriteButton(
                    type: FavoriteType.vod,
                    id: item.streamId,
                    name: item.name,
                    imageUrl: item.posterUrl,
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

class _PosterFallback extends StatelessWidget {
  const _PosterFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      alignment: Alignment.center,
      child: const Icon(Icons.movie_outlined, size: 32, color: AppColors.textSecondary),
    );
  }
}
