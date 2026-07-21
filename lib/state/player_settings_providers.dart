import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/storage_service.dart';

/// Two modes only (user request): keep the original aspect (letterbox where
/// needed) or stretch to fill the whole screen.
enum VideoAspect { original, fill }

extension VideoAspectLabel on VideoAspect {
  String get label {
    switch (this) {
      case VideoAspect.original:
        return 'Originale';
      case VideoAspect.fill:
        return 'Riempi';
    }
  }
}

class PlayerSettings {
  const PlayerSettings({
    required this.aspect,
    required this.subtitlesEnabled,
    required this.skipSeconds,
    required this.volume,
  });

  final VideoAspect aspect;
  final bool subtitlesEnabled;

  /// Seek step for the skip forward/back buttons (10, 30 or 60 seconds).
  final int skipSeconds;

  /// Last used player volume (0–100 UI scale), remembered across sessions.
  /// The desktop gain boost on top of it lives in the player screen.
  final double volume;

  PlayerSettings copyWith({
    VideoAspect? aspect,
    bool? subtitlesEnabled,
    int? skipSeconds,
    double? volume,
  }) {
    return PlayerSettings(
      aspect: aspect ?? this.aspect,
      subtitlesEnabled: subtitlesEnabled ?? this.subtitlesEnabled,
      skipSeconds: skipSeconds ?? this.skipSeconds,
      volume: volume ?? this.volume,
    );
  }
}

const kSkipOptions = [10, 30, 60];

class PlayerSettingsNotifier extends Notifier<PlayerSettings> {
  static const _aspectKey = 'default_aspect';
  static const _subtitlesKey = 'subtitles_enabled';
  static const _skipKey = 'skip_seconds';
  static const _volumeKey = 'player_volume';

  @override
  PlayerSettings build() {
    final rawAspect = StorageService.prefsBox.get(_aspectKey) as String?;
    // Default original; an unknown/old stored value (e.g. the removed
    // 'auto'/'ratio169') just falls back to it.
    var aspect = VideoAspect.original;
    for (final a in VideoAspect.values) {
      if (a.name == rawAspect) aspect = a;
    }
    final subtitles = StorageService.prefsBox.get(_subtitlesKey) as bool? ?? false;
    final skip = (StorageService.prefsBox.get(_skipKey) as num?)?.toInt() ?? 10;
    final volume = (StorageService.prefsBox.get(_volumeKey) as num?)?.toDouble() ?? 100.0;
    return PlayerSettings(
      aspect: aspect,
      subtitlesEnabled: subtitles,
      skipSeconds: kSkipOptions.contains(skip) ? skip : 10,
      volume: volume.clamp(0, 100),
    );
  }

  // NB: every setter updates state FIRST and lets the disk flush trail
  // behind (Hive applies the value to memory synchronously). Awaiting the
  // write before `state =` made the UI wait on flash IO — and froze the
  // remote-driven widget tests, where fake-clock code awaiting real IO
  // never resumes (same lesson as the device picker).
  void setVolume(double volume) {
    final v = volume.clamp(0, 100).toDouble();
    StorageService.prefsBox.put(_volumeKey, v);
    state = state.copyWith(volume: v);
  }

  Future<void> setAspect(VideoAspect aspect) async {
    final flushed = StorageService.prefsBox.put(_aspectKey, aspect.name);
    state = state.copyWith(aspect: aspect);
    await flushed;
  }

  Future<void> setSubtitlesEnabled(bool enabled) async {
    final flushed = StorageService.prefsBox.put(_subtitlesKey, enabled);
    state = state.copyWith(subtitlesEnabled: enabled);
    await flushed;
  }

  Future<void> setSkipSeconds(int seconds) async {
    final flushed = StorageService.prefsBox.put(_skipKey, seconds);
    state = state.copyWith(skipSeconds: seconds);
    await flushed;
  }
}

final playerSettingsProvider = NotifierProvider<PlayerSettingsNotifier, PlayerSettings>(
  PlayerSettingsNotifier.new,
);
