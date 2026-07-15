import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/adult_filter.dart';
import '../data/models/series_item.dart';
import '../data/models/xtream_category.dart';
import '../data/repositories/series_repository.dart';
import 'live_providers.dart' show xtreamSessionProvider, NoActivePlaylistException;

final seriesRepositoryProvider = FutureProvider<SeriesRepository?>((ref) async {
  final session = await ref.watch(xtreamSessionProvider.future);
  if (session == null) return null;
  return SeriesRepository(session);
});

final seriesCategoriesProvider = FutureProvider<List<XtreamCategory>>((ref) async {
  final repo = await ref.watch(seriesRepositoryProvider.future);
  if (repo == null) throw const NoActivePlaylistException();
  return repo.getCategories();
});

final seriesItemsProvider = FutureProvider.family<List<SeriesItem>, String>((ref, categoryId) async {
  final repo = await ref.watch(seriesRepositoryProvider.future);
  if (repo == null) return const [];
  return repo.getItems(categoryId);
});

final seriesDetailProvider = FutureProvider.family<SeriesDetail, String>((ref, seriesId) async {
  final repo = await ref.watch(seriesRepositoryProvider.future);
  if (repo == null) throw Exception('Nessun profilo selezionato');
  return repo.getDetail(seriesId);
});

/// All series across categories, for in-catalog search.
final allSeriesProvider = FutureProvider<List<SeriesItem>>((ref) async {
  final repo = await ref.watch(seriesRepositoryProvider.future);
  if (repo == null) throw const NoActivePlaylistException();
  return repo.getAllItems();
});

/// Set of adult series category ids (for filtering aggregate views).
final adultSeriesCategoryIdsProvider = FutureProvider<Set<String>>((ref) async {
  final cats = await ref.watch(seriesCategoriesProvider.future);
  return {for (final c in cats) if (isAdultCategory(c.name)) c.id};
});

/// Set of adult series ids, so Preferiti/Continua can drop porn items. Empty
/// until the catalog is loaded (non-blocking).
final adultSeriesIdsProvider = FutureProvider<Set<String>>((ref) async {
  final adultCats = await ref.watch(adultSeriesCategoryIdsProvider.future);
  if (adultCats.isEmpty) return const {};
  final all = await ref.watch(allSeriesProvider.future);
  return {for (final s in all) if (adultCats.contains(s.categoryId)) s.seriesId};
});

/// Derived from [allSeriesProvider] so the full-catalog download happens once
/// (it used to fire its own parallel getAllItems() on screen open).
final seriesCategoryCountsProvider = FutureProvider<Map<String, int>>((ref) async {
  final List<SeriesItem> all;
  try {
    all = await ref.watch(allSeriesProvider.future);
  } on NoActivePlaylistException {
    return const {};
  }
  final counts = <String, int>{};
  for (final s in all) {
    counts[s.categoryId] = (counts[s.categoryId] ?? 0) + 1;
  }
  return counts;
});
