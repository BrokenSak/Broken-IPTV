import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/adult_filter.dart';
import '../data/models/vod_item.dart';
import '../data/models/xtream_category.dart';
import '../data/repositories/vod_repository.dart';
import 'live_providers.dart' show xtreamSessionProvider, NoActivePlaylistException;

final vodRepositoryProvider = FutureProvider<VodRepository?>((ref) async {
  final session = await ref.watch(xtreamSessionProvider.future);
  if (session == null) return null;
  return VodRepository(session);
});

final vodCategoriesProvider = FutureProvider<List<XtreamCategory>>((ref) async {
  final repo = await ref.watch(vodRepositoryProvider.future);
  if (repo == null) throw const NoActivePlaylistException();
  return repo.getCategories();
});

final vodItemsProvider = FutureProvider.family<List<VodItem>, String>((ref, categoryId) async {
  final repo = await ref.watch(vodRepositoryProvider.future);
  if (repo == null) return const [];
  return repo.getItems(categoryId);
});

final vodDetailProvider = FutureProvider.family<VodDetail, String>((ref, vodId) async {
  final repo = await ref.watch(vodRepositoryProvider.future);
  if (repo == null) throw Exception('Nessun profilo selezionato');
  return repo.getDetail(vodId);
});

/// All movies across categories, for in-catalog search.
final allVodProvider = FutureProvider<List<VodItem>>((ref) async {
  final repo = await ref.watch(vodRepositoryProvider.future);
  if (repo == null) throw const NoActivePlaylistException();
  return repo.getAllItems();
});

/// Set of adult VOD category ids (for filtering aggregate views).
final adultVodCategoryIdsProvider = FutureProvider<Set<String>>((ref) async {
  final cats = await ref.watch(vodCategoriesProvider.future);
  return {for (final c in cats) if (isAdultCategory(c.name)) c.id};
});

/// Set of adult VOD stream ids, so Preferiti/Continua can drop porn items even
/// though they only store an id. Empty until the catalog is loaded (non-blocking).
final adultVodIdsProvider = FutureProvider<Set<String>>((ref) async {
  final adultCats = await ref.watch(adultVodCategoryIdsProvider.future);
  if (adultCats.isEmpty) return const {};
  final all = await ref.watch(allVodProvider.future);
  return {for (final v in all) if (adultCats.contains(v.categoryId)) v.streamId};
});

/// Derived from [allVodProvider] so the full-catalog download happens once
/// (it used to fire its own parallel getAllItems() on screen open).
final vodCategoryCountsProvider = FutureProvider<Map<String, int>>((ref) async {
  final List<VodItem> all;
  try {
    all = await ref.watch(allVodProvider.future);
  } on NoActivePlaylistException {
    return const {};
  }
  final counts = <String, int>{};
  for (final v in all) {
    counts[v.categoryId] = (counts[v.categoryId] ?? 0) + 1;
  }
  return counts;
});
