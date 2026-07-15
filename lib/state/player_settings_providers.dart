import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/storage_service.dart';

enum VideoAspect { auto, fill, ratio169, ratio43 }

extension VideoAspectLabel on VideoAspect {
  String get label {
    switch (this) {
      case VideoAspect.auto:
        return 'Auto';
      case VideoAspect.fill:
        return 'Riempi';
      case VideoAspect.ratio169:
        return '16:9';
      case VideoAspect.ratio43:
        return '4:3';
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
    var aspect = VideoAspect.auto;
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

  void setVolume(double volume) {
    final v = volume.clamp(0, 100).toDouble();
    StorageService.prefsBox.put(_volumeKey, v);
    state = state.copyWith(volume: v);
  }

  Future<void> setAspect(VideoAspect aspect) async {
    await StorageService.prefsBox.put(_aspectKey, aspect.name);
    state = state.copyWith(aspect: aspect);
  }

  Future<void> setSubtitlesEnabled(bool enabled) async {
    await StorageService.prefsBox.put(_subtitlesKey, enabled);
    state = state.copyWith(subtitlesEnabled: enabled);
  }

  Future<void> setSkipSeconds(int seconds) async {
    await StorageService.prefsBox.put(_skipKey, seconds);
    state = state.copyWith(skipSeconds: seconds);
  }
}

final playerSettingsProvider = NotifierProvider<PlayerSettingsNotifier, PlayerSettings>(
  PlayerSettingsNotifier.new,
);
