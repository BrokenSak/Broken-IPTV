import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/xtream_profile.dart';
import '../../data/services/storage_service.dart';
import '../../presentation/common/app_background.dart';
import '../../presentation/screens/onboarding/device_mode_screen.dart';
import '../../presentation/screens/profiles/profiles_screen.dart';
import '../../presentation/screens/profiles/add_profile_screen.dart';
import '../../presentation/screens/home/home_screen.dart';
import '../../presentation/screens/live_tv/live_tv_screen.dart';
import '../../presentation/screens/epg/epg_screen.dart';
import '../../presentation/screens/vod/vod_screen.dart';
import '../../presentation/screens/vod/vod_detail_screen.dart';
import '../../presentation/screens/series/series_screen.dart';
import '../../presentation/screens/series/series_detail_screen.dart';
import '../../presentation/screens/player/player_screen.dart';
import '../../presentation/screens/search/search_screen.dart';
import '../../presentation/screens/settings/settings_screen.dart';
import '../../presentation/screens/downloads/downloads_screen.dart';

/// Startup routing: on Android the very first launch goes through the
/// TV/phone picker; after that the app always boots straight to Home with
/// the persisted playlist. Only when no playlist exists at all does it fall
/// back to the profiles screen to add one.
String? _rootRedirect(BuildContext context, GoRouterState state) {
  final loc = state.matchedLocation;
  if (Platform.isAndroid &&
      loc != '/device-mode' &&
      StorageService.prefsBox.get('device_mode') == null) {
    return '/device-mode';
  }
  if (StorageService.profilesBox.isEmpty &&
      loc != '/profiles' &&
      loc != '/profiles/add' &&
      loc != '/device-mode') {
    return '/profiles';
  }
  return null;
}

// Each screen is wrapped so it paints its own opaque abstract background;
// that makes a pushed page fully cover the previous one during transitions.
Widget _bg(Widget child) => AppBackground(child: child);

final appRouter = GoRouter(
  initialLocation: '/home',
  redirect: _rootRedirect,
  routes: [
    GoRoute(
      path: '/device-mode',
      builder: (context, state) => _bg(const DeviceModeScreen()),
    ),
    GoRoute(
      path: '/profiles',
      builder: (context, state) => _bg(const ProfilesScreen()),
      routes: [
        GoRoute(
          path: 'add',
          builder: (context, state) => _bg(AddProfileScreen(
            existingProfile: state.extra as XtreamProfile?,
          )),
        ),
      ],
    ),
    GoRoute(
      path: '/home',
      builder: (context, state) => _bg(const HomeScreen()),
    ),
    GoRoute(
      path: '/live',
      builder: (context, state) => _bg(const LiveTvScreen()),
    ),
    GoRoute(
      path: '/epg',
      builder: (context, state) => _bg(EpgScreen(
        streamId: state.uri.queryParameters['streamId'] ?? '',
        channelName: state.uri.queryParameters['name'] ?? '',
      )),
    ),
    GoRoute(
      path: '/vod',
      builder: (context, state) => _bg(const VodScreen()),
      routes: [
        GoRoute(
          path: ':id',
          builder: (context, state) => _bg(VodDetailScreen(vodId: state.pathParameters['id']!)),
        ),
      ],
    ),
    GoRoute(
      path: '/series',
      builder: (context, state) => _bg(const SeriesScreen()),
      routes: [
        GoRoute(
          path: ':id',
          builder: (context, state) => _bg(SeriesDetailScreen(seriesId: state.pathParameters['id']!)),
        ),
      ],
    ),
    GoRoute(
      path: '/player',
      builder: (context, state) {
        final q = state.uri.queryParameters;
        return PlayerScreen(
          streamUrl: q['url'],
          isLive: q['isLive'] == '1',
          streamId: q['streamId'],
          channelName: q['name'],
          seriesId: q['seriesId'],
          episodeId: q['episodeId'],
          episodeLabel: q['epLabel'],
          vodId: q['vodId'],
          posterUrl: q['poster'],
          resumeMs: int.tryParse(q['resume'] ?? '') ?? 0,
          progressUrl: q['progressUrl'],
        );
      },
    ),
    GoRoute(
      path: '/search',
      builder: (context, state) => _bg(const SearchScreen()),
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => _bg(const SettingsScreen()),
    ),
    GoRoute(
      path: '/downloads',
      builder: (context, state) => _bg(const DownloadsScreen()),
    ),
  ],
);
