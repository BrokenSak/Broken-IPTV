import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/channel.dart';
import '../../../data/models/epg_program.dart';
import '../../../data/models/favorite_item.dart';
import '../../../state/favorites_providers.dart';
import '../../../state/live_providers.dart';
import '../../../state/profile_providers.dart';
import '../../common/catalog_scaffold.dart';
import '../../common/error_retry.dart';
import '../../common/favorite_button.dart';
import '../../common/grid_metrics.dart';
import '../../common/tv_focusable.dart';

class LiveTvScreen extends ConsumerStatefulWidget {
  const LiveTvScreen({super.key});

  @override
  ConsumerState<LiveTvScreen> createState() => _LiveTvScreenState();
}

class _LiveTvScreenState extends ConsumerState<LiveTvScreen> {
  String? _selectedCategoryId;
  String _query = '';

  /// First non-adult category (so we never auto-open on an adult one).
  String _defaultCategory(List cats) {
    for (final c in cats) {
      if (!isAdultCategory(c.name)) return c.id as String;
    }
    return cats.isNotEmpty ? cats.first.id as String : kFavoritesCategoryId;
  }

  @override
  Widget build(BuildContext context) {
    final profileId = ref.watch(selectedProfileIdProvider);
    if (profileId == null) {
      return CatalogScaffold(
        title: 'TV',
        onSearch: (q) {},
        body: Center(
          child: ElevatedButton(
            onPressed: () => context.push('/settings'),
            child: const Text('Seleziona una playlist dalle Impostazioni'),
          ),
        ),
      );
    }

    if (_query.isNotEmpty) {
      return CatalogScaffold(
        title: 'TV',
        initialQuery: _query,
        onSearch: (q) => setState(() => _query = q),
        body: _SearchResults(query: _query),
      );
    }

    final categories = ref.watch(liveCategoriesProvider);
    return CatalogScaffold(
      title: 'TV',
      onSearch: (q) => setState(() => _query = q),
      body: categories.when(
        data: (cats) {
          _selectedCategoryId ??= _defaultCategory(cats);
          final counts = ref.watch(liveCategoryCountsProvider).value ?? const {};
          return Row(
            children: [
              CategorySidebar(
                categories: cats,
                selectedId: _selectedCategoryId!,
                counts: counts,
                favoritesCount:
                    ref.watch(favoritesProvider).where((f) => f.type == FavoriteType.live).length,
                onSelect: (id) => setState(() => _selectedCategoryId = id),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: _selectedCategoryId == kFavoritesCategoryId
                    ? const _LiveFavorites()
                    : _ChannelGrid(categoryId: _selectedCategoryId!),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorRetry(
          message: cleanError(error),
          onRetry: () {
            ref.invalidate(xtreamSessionProvider);
            ref.invalidate(liveRepositoryProvider);
            ref.invalidate(liveCategoriesProvider);
          },
        ),
      ),
    );
  }
}

/// Shared channel grid (tile size from [GridMetrics]: denser on Android).
GridView _channelGridView({
  required int itemCount,
  required Widget Function(BuildContext, int) itemBuilder,
}) {
  return GridView.builder(
    padding: EdgeInsets.all(GridMetrics.gridPadding),
    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: GridMetrics.channelExtent,
      mainAxisSpacing: GridMetrics.spacing,
      crossAxisSpacing: GridMetrics.spacing,
      childAspectRatio: GridMetrics.channelRatio,
    ),
    itemCount: itemCount,
    itemBuilder: itemBuilder,
  );
}

class _LiveFavorites extends ConsumerWidget {
  const _LiveFavorites();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adultIds = ref.watch(adultLiveIdsProvider).value ?? const <String>{};
    final favs = ref
        .watch(favoritesProvider)
        .where((f) => f.type == FavoriteType.live && !adultIds.contains(f.id))
        .toList();
    if (favs.isEmpty) {
      return const Center(child: Text('Nessun canale preferito. Tocca il cuore su un canale.'));
    }
    return _channelGridView(
      itemCount: favs.length,
      itemBuilder: (context, index) {
        final f = favs[index];
        return _ChannelTile(
          channel: Channel(streamId: f.id, name: f.name, categoryId: '', logoUrl: f.imageUrl),
        );
      },
    );
  }
}

class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.query});
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(allChannelsProvider);
    return all.when(
      data: (channels) {
        final q = query.toLowerCase();
        final filtered = channels.where((c) => c.name.toLowerCase().contains(q)).toList();
        if (filtered.isEmpty) return const Center(child: Text('Nessun canale trovato.'));
        return _channelGridView(
          itemCount: filtered.length,
          itemBuilder: (context, index) => _ChannelTile(channel: filtered[index]),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => ErrorRetry(
        message: cleanError(error),
        onRetry: () => ref.invalidate(allChannelsProvider),
      ),
    );
  }
}

class _ChannelGrid extends ConsumerWidget {
  const _ChannelGrid({required this.categoryId});

  final String categoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channels = ref.watch(liveStreamsProvider(categoryId));

    return channels.when(
      data: (list) {
        if (list.isEmpty) {
          return const Center(child: Text('Nessun canale in questa categoria.'));
        }
        return _channelGridView(
          itemCount: list.length,
          itemBuilder: (context, index) {
            final channel = list[index];
            return _ChannelTile(channel: channel);
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('Errore: $error')),
    );
  }
}

class _ChannelTile extends ConsumerWidget {
  const _ChannelTile({required this.channel});

  final Channel channel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TvFocusable(
      onLongPress: longPressFavorite(
        ref,
        FavoriteItem(
          type: FavoriteType.live,
          id: channel.streamId,
          name: channel.name,
          imageUrl: channel.logoUrl,
        ),
      ),
      onTap: () {
        final url = ref.read(liveRepositoryProvider).value?.streamUrl(channel.streamId);
        context.push(
          Uri(path: '/player', queryParameters: {
            'url': ?url,
            'isLive': '1',
            'streamId': channel.streamId,
            'name': channel.name,
          }).toString(),
        );
      },
      child: Card(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: channel.logoUrl != null
                        ? CachedNetworkImage(
                            imageUrl: channel.logoUrl!,
                            fit: BoxFit.contain,
                            errorWidget: (_, _, _) => const Icon(Icons.tv, size: 40),
                          )
                        : const Icon(Icons.tv, size: 40, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  _ChannelEpg(streamId: channel.streamId, channelName: channel.name),
                ],
              ),
            ),
            // On TV this renders as a non-focusable badge (see FavoriteButton).
            Positioned(
              top: 0,
              right: 0,
              child: FavoriteButton(
                type: FavoriteType.live,
                id: channel.streamId,
                name: channel.name,
                imageUrl: channel.logoUrl,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Current EPG program shown under a live channel. If the channel name ends
/// with "+N" (e.g. "Rai 1 +1") it is a timeshift channel N hours behind, so
/// the programme currently airing is offset accordingly.
class _ChannelEpg extends ConsumerWidget {
  const _ChannelEpg({required this.streamId, required this.channelName});

  final String streamId;
  final String channelName;

  int _offsetHours() {
    final m = RegExp(r'\+\s*(\d+)').firstMatch(channelName);
    if (m == null) return 0;
    return int.tryParse(m.group(1)!) ?? 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final epg = ref.watch(shortEpgProvider(streamId)).value;
    // No EPG available (or still loading): don't reserve any empty space below.
    if (epg == null || epg.isEmpty) return const SizedBox.shrink();

    final offset = Duration(hours: _offsetHours());
    // A +N channel is N hours behind, so what's live "now" on it is the base
    // programme from N hours ago.
    final ref0 = DateTime.now().subtract(offset);
    EpgProgram? current;
    for (final p in epg) {
      if (ref0.isAfter(p.start) && ref0.isBefore(p.end)) {
        current = p;
        break;
      }
    }
    current ??= epg.first;

    String two(int n) => n.toString().padLeft(2, '0');
    final shownStart = current.start.add(offset);
    final shownEnd = current.end.add(offset);
    final total = current.end.difference(current.start).inSeconds;
    final elapsed = ref0.difference(current.start).inSeconds;
    final fraction = total > 0 ? (elapsed / total).clamp(0.0, 1.0) : 0.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          current.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          '${two(shownStart.hour)}:${two(shownStart.minute)} - ${two(shownEnd.hour)}:${two(shownEnd.minute)}',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
        ),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 3,
            backgroundColor: Colors.white.withValues(alpha: 0.15),
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      ],
    );
  }
}
