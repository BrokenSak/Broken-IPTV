import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/adult_filter.dart';
import '../data/models/channel.dart';
import '../data/models/epg_program.dart';
import '../data/models/xtream_category.dart';
import '../data/models/xtream_profile.dart';
import '../data/repositories/live_repository.dart';
import '../data/services/catalog_cache.dart';
import '../data/services/content_source.dart';
import '../data/services/m3u_source.dart';
import '../data/services/storage_service.dart';
import '../data/services/xtream_session.dart';
import 'profile_providers.dart';

/// Thrown by catalog providers when there is no active playlist/session, so
/// the UI can show a clear message instead of an ambiguous "empty" state.
class NoActivePlaylistException implements Exception {
  const NoActivePlaylistException();
  @override
  String toString() => 'Nessuna playlist attiva. Selezionane una dalle Impostazioni.';
}

/// Builds the content source (Xtream session or M3U playlist) for whichever
/// profile is currently selected. Resolves to null if nothing is selected yet.
/// Kept named `xtreamSessionProvider` for continuity across the app.
final xtreamSessionProvider = FutureProvider<ContentSource?>((ref) async {
  final profileId = ref.watch(selectedProfileIdProvider);
  if (profileId == null) return null;

  final profiles = ref.watch(profilesProvider);
  XtreamProfile? profile;
  for (final p in profiles) {
    if (p.id == profileId) {
      profile = p;
      break;
    }
  }
  if (profile == null) return null;

  if (profile.isM3u) {
    final source = M3uSource(m3uUrl: profile.m3uUrl ?? profile.host, epgUrl: profile.epgUrl);
    await source.ensureLoaded();
    return source;
  }

  final password = await ref.watch(profileRepositoryProvider).getPassword(profileId);
  if (password == null) return null;

  return XtreamSession(
    host: profile.host,
    username: profile.username,
    password: password,
    // Disk cache for the catalog calls: instant loads on slow panels and an
    // offline fallback (see CatalogCache).
    cache: CatalogCache(StorageService.catalogCacheBox),
  );
});

/// Full account/subscription info for the Account panel (null if unavailable).
final accountInfoProvider = FutureProvider<AccountInfo?>((ref) async {
  final source = await ref.watch(xtreamSessionProvider.future);
  if (source == null) return null;
  try {
    return await source.getAccountInfo();
  } catch (_) {
    return null;
  }
});

final liveRepositoryProvider = FutureProvider<LiveRepository?>((ref) async {
  final session = await ref.watch(xtreamSessionProvider.future);
  if (session == null) return null;
  return LiveRepository(session);
});

final liveCategoriesProvider = FutureProvider<List<XtreamCategory>>((ref) async {
  final repo = await ref.watch(liveRepositoryProvider.future);
  if (repo == null) throw const NoActivePlaylistException();
  return repo.getCategories();
});

final liveStreamsProvider = FutureProvider.family<List<Channel>, String>((ref, categoryId) async {
  final repo = await ref.watch(liveRepositoryProvider.future);
  if (repo == null) return const [];
  return repo.getChannels(categoryId);
});

final shortEpgProvider = FutureProvider.family<List<EpgProgram>, String>((ref, streamId) async {
  final repo = await ref.watch(liveRepositoryProvider.future);
  if (repo == null) return const [];
  return repo.getShortEpg(streamId);
});

/// All live channels across categories, for in-catalog search.
final allChannelsProvider = FutureProvider<List<Channel>>((ref) async {
  final repo = await ref.watch(liveRepositoryProvider.future);
  if (repo == null) throw const NoActivePlaylistException();
  return repo.getAllChannels();
});

/// Subscription expiry date for the active profile (null if unknown/unlimited).
final expiryDateProvider = FutureProvider<DateTime?>((ref) async {
  final session = await ref.watch(xtreamSessionProvider.future);
  if (session == null) return null;
  try {
    return await session.getExpiryDate();
  } catch (_) {
    return null;
  }
});

/// Set of adult live channel ids, so live Preferiti can drop porn channels.
final adultLiveIdsProvider = FutureProvider<Set<String>>((ref) async {
  final cats = await ref.watch(liveCategoriesProvider.future);
  final adultCats = {for (final c in cats) if (isAdultCategory(c.name)) c.id};
  if (adultCats.isEmpty) return const {};
  final all = await ref.watch(allChannelsProvider.future);
  return {for (final c in all) if (adultCats.contains(c.categoryId)) c.streamId};
});

/// Per-category channel counts (categoryId -> count) for the live sidebar.
/// Derived from [allChannelsProvider] so the full-catalog download happens
/// once — this used to call getAllChannels() itself, firing a second parallel
/// full download every time the TV screen opened.
final liveCategoryCountsProvider = FutureProvider<Map<String, int>>((ref) async {
  final List<Channel> all;
  try {
    all = await ref.watch(allChannelsProvider.future);
  } on NoActivePlaylistException {
    return const {};
  }
  final counts = <String, int>{};
  for (final c in all) {
    counts[c.categoryId] = (counts[c.categoryId] ?? 0) + 1;
  }
  return counts;
});
