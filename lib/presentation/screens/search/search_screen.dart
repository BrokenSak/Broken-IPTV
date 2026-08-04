import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../state/live_providers.dart';
import '../../../state/search_providers.dart';
import '../../common/tv_focusable.dart';
import '../../common/tv_text_field.dart';

/// Small rounded thumbnail for a search result, falling back to [icon] when
/// there is no image (or it fails to load).
Widget _searchThumb(String? url, IconData icon) {
  Widget fallback() => Container(
        color: AppColors.surface,
        alignment: Alignment.center,
        child: Icon(icon, color: AppColors.textSecondary, size: 22),
      );
  return ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: SizedBox(
      width: 46,
      height: 46,
      child: url != null
          ? CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              placeholder: (_, _) => Container(color: AppColors.surface),
              errorWidget: (_, _, _) => fallback(),
            )
          : fallback(),
    ),
  );
}

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _query = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(searchProvider(_query));

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: tvBackButton(context),
        title: TvTextFormField(
          controller: _controller,
          autofocus: true,
          onChanged: _onChanged,
          decoration: const InputDecoration(
            hintText: 'Cerca canali, film, serie...',
            border: InputBorder.none,
          ),
          style: const TextStyle(color: AppColors.textPrimary),
        ),
      ),
      body: _query.trim().isEmpty
          ? const Center(child: Text('Digita per cercare nel catalogo.'))
          : results.when(
              data: (r) {
                if (r.isEmpty) return const Center(child: Text('Nessun risultato.'));
                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (r.channels.isNotEmpty) ...[
                      Text('Canali', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      ...r.channels.map((c) => TvFocusable(
                            onTap: () {
                              final url = ref.read(liveRepositoryProvider).value?.streamUrl(c.streamId);
                              context.push(Uri(path: '/player', queryParameters: {
                                'url': ?url,
                                'streamId': c.streamId,
                                'name': c.name,
                              }).toString());
                            },
                            child: ListTile(
                              leading: _searchThumb(c.logoUrl, Icons.tv),
                              title: Text(c.name),
                            ),
                          )),
                      const SizedBox(height: 16),
                    ],
                    if (r.movies.isNotEmpty) ...[
                      Text('Film', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      ...r.movies.map((m) => TvFocusable(
                            onTap: () => context.push('/vod/${m.streamId}'),
                            child: ListTile(
                              leading: _searchThumb(m.posterUrl, Icons.movie_outlined),
                              title: Text(m.name),
                            ),
                          )),
                      const SizedBox(height: 16),
                    ],
                    if (r.series.isNotEmpty) ...[
                      Text('Serie TV', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      ...r.series.map((s) => TvFocusable(
                            onTap: () => context.push('/series/${s.seriesId}'),
                            child: ListTile(
                              leading: _searchThumb(s.coverUrl, Icons.video_library_outlined),
                              title: Text(s.name),
                            ),
                          )),
                    ],
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('Errore: $error')),
            ),
    );
  }
}
