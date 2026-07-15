import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../core/fullscreen.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/channel.dart';
import '../../../data/models/series_item.dart';
import '../../../data/models/watch_progress.dart';
import '../../../state/live_providers.dart';
import '../../common/glass_dropdown.dart';
import '../../../state/player_settings_providers.dart';
import '../../../state/series_providers.dart';
import '../../../state/watch_progress_providers.dart';

const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

/// Desktop-only software gain on top of the 0–100 UI volume: IPTV streams are
/// often encoded quiet, so UI 100% maps to mpv 150 (the UI keeps its normal
/// 0–100 scale). Android stays at 1.0 — volume belongs to the hardware keys.
final double _volumeBoost = Platform.isAndroid ? 1.0 : 1.5;

/// Human-readable label for an audio track (language name, else title, else id).
String _audioTrackLabel(AudioTrack t) {
  final lang = (t.language ?? '').trim().toLowerCase();
  const names = {
    'ita': 'Italiano', 'it': 'Italiano',
    'eng': 'Inglese', 'en': 'Inglese',
    'spa': 'Spagnolo', 'es': 'Spagnolo',
    'fra': 'Francese', 'fre': 'Francese', 'fr': 'Francese',
    'deu': 'Tedesco', 'ger': 'Tedesco', 'de': 'Tedesco',
    'por': 'Portoghese', 'pt': 'Portoghese',
    'rus': 'Russo', 'ru': 'Russo',
    'ara': 'Arabo', 'ar': 'Arabo',
    'jpn': 'Giapponese', 'ja': 'Giapponese',
    'zho': 'Cinese', 'chi': 'Cinese', 'zh': 'Cinese',
  };
  if (names.containsKey(lang)) return names[lang]!;
  final title = (t.title ?? '').trim();
  if (title.isNotEmpty) return title;
  if (lang.isNotEmpty) return lang.toUpperCase();
  return 'Traccia ${t.id}';
}

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({
    super.key,
    this.streamUrl,
    this.isLive = false,
    this.streamId,
    this.channelName,
    this.seriesId,
    this.episodeId,
    this.episodeLabel,
    this.vodId,
    this.posterUrl,
    this.resumeMs = 0,
  });

  final String? streamUrl;

  /// True for live TV channels: no seek bar, no speed, never stops.
  final bool isLive;

  /// Live channel id, used to show the current EPG program.
  final String? streamId;
  final String? channelName;

  /// Set only when playing a series episode; enables "next episode" + progress.
  final String? seriesId;
  final String? episodeId;
  final String? episodeLabel;

  /// Set only when playing a movie; enables progress tracking.
  final String? vodId;

  final String? posterUrl;
  final int resumeMs;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  final List<StreamSubscription> _subscriptions = [];

  String? _error;
  String? _title;
  String? _currentEpisodeId;
  String? _currentEpisodeLabel;
  String? _currentStreamId;
  String _currentUrl = '';

  bool _controlsVisible = true;
  Timer? _hideTimer;

  bool _playing = false;
  bool _buffering = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 100;
  double _volumeBeforeMute = 100;
  double _rate = 1.0;
  bool _subtitlesOn = false;
  late VideoAspect _aspect;

  // Playback resilience: auto-reconnect with a ts↔m3u8 fallback for live.
  int _retry = 0;
  bool _reconnecting = false;
  String _liveExt = 'ts';
  Timer? _retryTimer;
  int? _videoWidth;
  int? _videoHeight;

  // Live channel-list overlay (zap without leaving the player).
  bool _channelListOpen = false;

  // Audio tracks (multi-language). We try to auto-select Italian per media.
  List<AudioTrack> _audioTracks = const [];
  String? _currentAudioId;
  bool _autoAudioApplied = false;

  int? _pendingResumeMs;
  int _lastSavedMs = 0;

  // Cached at init so the final save in dispose() never touches `ref` (using
  // `ref` during dispose can throw — which previously aborted teardown on
  // VOD/series and left audio playing).
  late final WatchProgressNotifier _watchProgress;

  bool get _isSeries => widget.seriesId != null;
  bool get _isVod => widget.vodId != null;
  bool get _isLive => widget.isLive;

  @override
  void initState() {
    super.initState();
    // Only the player is landscape-only on Android: the rest of the app
    // rotates freely. Restored in dispose().
    if (Platform.isAndroid) {
      unawaited(SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]));
    }
    final settings = ref.read(playerSettingsProvider);
    _aspect = settings.aspect;
    _subtitlesOn = settings.subtitlesEnabled;
    // On Android the volume is the system one, driven by the phone/remote
    // hardware keys: keep the software volume at 100 (a remembered low/zero
    // value would silently cap the hardware keys) and hide the in-app controls.
    _volume = Platform.isAndroid ? 100 : settings.volume;
    _volumeBeforeMute = _volume > 0 ? _volume : 100;
    _title = widget.channelName;
    _currentEpisodeId = widget.episodeId;
    _currentEpisodeLabel = widget.episodeLabel;
    _currentStreamId = widget.streamId;
    _pendingResumeMs = widget.resumeMs > 0 ? widget.resumeMs : null;
    _watchProgress = ref.read(watchProgressProvider.notifier);

    _player = Player();
    _controller = VideoController(_player);
    // The desktop boost needs headroom above mpv's default `volume-max` of
    // 130: raise the ceiling to UI 100% × boost, then re-apply the remembered
    // volume — a set issued before the new ceiling landed would have been
    // clamped to the old one.
    final native = _player.platform;
    if (!Platform.isAndroid && native is NativePlayer) {
      unawaited(native
          .setProperty('volume-max', (100 * _volumeBoost).round().toString())
          .then((_) {
        if (mounted) _applyVolume(_volume);
      }).catchError((_) {}));
    }

    _subscriptions.addAll([
      _player.stream.error.listen((message) {
        if (mounted) _handlePlaybackError(message);
      }),
      _player.stream.buffering.listen((buffering) {
        if (mounted) setState(() => _buffering = buffering);
      }),
      _player.stream.width.listen((w) {
        if (mounted && w != _videoWidth) setState(() => _videoWidth = w);
      }),
      _player.stream.height.listen((h) {
        if (mounted && h != _videoHeight) setState(() => _videoHeight = h);
      }),
      _player.stream.playing.listen((playing) {
        // A successful (re)start clears the reconnect state.
        if (playing) {
          _retry = 0;
          _reconnecting = false;
        }
        if (mounted) setState(() => _playing = playing);
      }),
      _player.stream.position.listen((position) {
        if (mounted) setState(() => _position = position);
        _maybeSaveProgress();
      }),
      _player.stream.duration.listen((duration) {
        if (mounted) setState(() => _duration = duration);
        // Seek to the saved resume point once the media is ready.
        if (_pendingResumeMs != null && duration.inMilliseconds > 0) {
          final target = _pendingResumeMs!;
          _pendingResumeMs = null;
          if (target < duration.inMilliseconds - 5000) {
            _player.seek(Duration(milliseconds: target));
          }
        }
      }),
      _player.stream.volume.listen((volume) {
        // mpv reports the boosted value: bring it back to the 0–100 UI scale.
        final ui = (volume / _volumeBoost).clamp(0.0, 100.0);
        if (mounted) setState(() => _volume = ui);
      }),
      // New media resets track selection: re-apply the subtitle preference and
      // pick up the available audio tracks (auto-selecting Italian) each time
      // the track list changes.
      _player.stream.tracks.listen((tracks) {
        if (!_subtitlesOn) _player.setSubtitleTrack(SubtitleTrack.no());
        final audios =
            tracks.audio.where((a) => a.id != 'auto' && a.id != 'no').toList();
        if (mounted) setState(() => _audioTracks = audios);
        _maybeApplyItalianAudio(audios);
      }),
      _player.stream.track.listen((track) {
        if (mounted) setState(() => _currentAudioId = track.audio.id);
      }),
    ]);

    final url = widget.streamUrl;
    if (url != null) {
      _open(url);
    } else {
      _error = 'Nessuno stream da riprodurre.';
    }
    _scheduleHide();
  }

  void _open(String url) {
    _currentUrl = url;
    _autoAudioApplied = false;
    setState(() {
      _error = null;
      _buffering = true;
    });
    _player.open(Media(url));
    _player.setRate(_rate);
    // Apply the remembered volume to the new media.
    _applyVolume(_volume);
    if (!_subtitlesOn) _player.setSubtitleTrack(SubtitleTrack.no());
  }

  /// Auto-reconnect a dropped stream a few times before giving up. For live we
  /// also alternate the container (.ts ↔ .m3u8) as a format fallback, since a
  /// panel may only serve one of them reliably.
  void _handlePlaybackError(String message) {
    if (_retry >= 4) {
      setState(() {
        _error = message;
        _reconnecting = false;
        _buffering = false;
      });
      return;
    }
    _retry++;
    setState(() {
      _error = null;
      _reconnecting = true;
      _buffering = true;
    });
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(milliseconds: 800 + 700 * _retry), () {
      if (!mounted) return;
      if (_isLive && _currentStreamId != null) {
        // Flip format on odd attempts to try the other container.
        if (_retry.isEven) _liveExt = _liveExt == 'ts' ? 'm3u8' : 'ts';
        final url = _liveUrl(_currentStreamId!, _liveExt);
        if (url != null) {
          _open(url);
          return;
        }
      }
      _open(_currentUrl);
    });
  }

  String? _liveUrl(String streamId, String ext) {
    final source = ref.read(xtreamSessionProvider).value;
    return source?.liveStreamUrl(streamId, ext: ext);
  }

  void _switchChannel(String streamId, String name) {
    final url = _liveUrl(streamId, 'ts');
    if (url == null) return;
    setState(() {
      _channelListOpen = false;
      _currentStreamId = streamId;
      _title = name;
      _liveExt = 'ts';
      _retry = 0;
      _reconnecting = false;
    });
    _open(url);
    _poke();
  }

  String? get _qualityLabel {
    final h = _videoHeight ?? 0;
    if (h <= 0) return null;
    if (h >= 2000) return '4K';
    if (h >= 1400) return '1440p';
    if (h >= 1000) return '1080p';
    if (h >= 700) return '720p';
    if (h >= 460) return '480p';
    return 'SD';
  }

  void _maybeSaveProgress({bool force = false}) {
    if (_isLive || (!_isVod && !_isSeries)) return;
    final pos = _position.inMilliseconds;
    final dur = _duration.inMilliseconds;
    if (dur <= 0) return;
    // Throttle to roughly one write every 5 seconds.
    if (!force && (pos - _lastSavedMs).abs() < 5000) return;
    _lastSavedMs = pos;

    final progress = _isVod
        ? WatchProgress(
            kind: WatchKind.vod,
            vodId: widget.vodId,
            seriesId: null,
            episodeId: null,
            episodeLabel: null,
            name: widget.channelName ?? '',
            imageUrl: widget.posterUrl,
            url: _currentUrl,
            positionMs: pos,
            durationMs: dur,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          )
        : WatchProgress(
            kind: WatchKind.series,
            vodId: null,
            seriesId: widget.seriesId,
            episodeId: _currentEpisodeId,
            episodeLabel: _currentEpisodeLabel,
            name: widget.channelName ?? '',
            imageUrl: widget.posterUrl,
            url: _currentUrl,
            positionMs: pos,
            durationMs: dur,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          );
    _watchProgress.save(progress);
  }

  @override
  void dispose() {
    // Leaving the player: give rotation back to the system (empty list =
    // platform default, i.e. free rotation).
    if (Platform.isAndroid) {
      unawaited(SystemChrome.setPreferredOrientations(const []));
    }
    // Silence immediately, then tear the native player down defensively.
    // NB: the "audio keeps playing after exit" bug only ever showed on
    // VOD/series — for live, progress-save is skipped so the teardown always
    // ran; on VOD/series a throwing save could abort dispose *before* stop(),
    // leaving audio playing. So guard the save and never let it block teardown.
    final player = _player;
    player.setVolume(0);
    try {
      _maybeSaveProgress(force: true);
    } catch (_) {}
    _hideTimer?.cancel();
    _retryTimer?.cancel();
    for (final s in _subscriptions) {
      s.cancel();
    }
    // stop() must fully apply before dispose(), otherwise audio can linger on
    // Windows. dispose() can't be async, so run the ordered teardown on the
    // captured instance after super.dispose().
    unawaited(() async {
      try {
        await player.stop();
      } catch (_) {}
      await player.dispose();
    }());
    super.dispose();
  }

  void _skip(int seconds) {
    var target = _position.inSeconds + seconds;
    if (target < 0) target = 0;
    final maxS = _duration.inSeconds;
    if (maxS > 0 && target > maxS) target = maxS;
    _player.seek(Duration(seconds: target));
    _poke();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      // Keep controls (and the bottom-left "Canali" button) visible while the
      // channel list is open.
      if (mounted && _playing && !_channelListOpen) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _poke() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  void _togglePlayPause() {
    _player.playOrPause();
    _poke();
  }

  void _toggleSubtitles() {
    setState(() => _subtitlesOn = !_subtitlesOn);
    _player.setSubtitleTrack(_subtitlesOn ? SubtitleTrack.auto() : SubtitleTrack.no());
    _poke();
  }

  void _selectAudio(AudioTrack track) {
    _player.setAudioTrack(track);
    setState(() => _currentAudioId = track.id);
    _poke();
  }

  static bool _isItalianAudio(AudioTrack a) {
    final lang = (a.language ?? '').toLowerCase();
    final title = (a.title ?? '').toLowerCase();
    return lang.startsWith('it') ||
        lang.contains('ita') ||
        title.contains('ita') ||
        title.contains('italian');
  }

  /// Once per media, prefer the Italian audio track when one is available.
  void _maybeApplyItalianAudio(List<AudioTrack> audios) {
    if (_autoAudioApplied || audios.isEmpty) return;
    _autoAudioApplied = true;
    for (final a in audios) {
      if (_isItalianAudio(a)) {
        _player.setAudioTrack(a);
        if (mounted) setState(() => _currentAudioId = a.id);
        return;
      }
    }
  }

  void _cycleAspect() {
    final next = VideoAspect
        .values[(VideoAspect.values.indexOf(_aspect) + 1) % VideoAspect.values.length];
    setState(() => _aspect = next);
    _poke();
  }

  void _cycleSpeed() {
    final index = _speeds.indexWhere((s) => (s - _rate).abs() < 0.01);
    final next = _speeds[(index + 1) % _speeds.length];
    setState(() => _rate = next);
    _player.setRate(next);
    _poke();
  }

  /// Sends a 0–100 UI volume to the player, applying the desktop gain boost.
  void _applyVolume(double uiVolume) {
    _player.setVolume(uiVolume * _volumeBoost);
  }

  void _toggleMute() {
    if (_volume > 0) {
      _volumeBeforeMute = _volume;
      _applyVolume(0);
    } else {
      _applyVolume(_volumeBeforeMute > 0 ? _volumeBeforeMute : 100);
    }
    _poke();
  }

  Episode? _findNextEpisode() {
    final seriesId = widget.seriesId;
    if (seriesId == null || _currentEpisodeId == null) return null;
    final detail = ref.read(seriesDetailProvider(seriesId)).value;
    if (detail == null) return null;

    final seasons = detail.episodesBySeason.keys.toList()..sort();
    final ordered = <Episode>[
      for (final season in seasons) ...detail.episodesBySeason[season]!,
    ];
    final index = ordered.indexWhere((e) => e.id == _currentEpisodeId);
    if (index < 0 || index + 1 >= ordered.length) return null;
    return ordered[index + 1];
  }

  void _playNextEpisode() {
    final next = _findNextEpisode();
    if (next == null) return;
    final repo = ref.read(seriesRepositoryProvider).value;
    if (repo == null) return;
    _maybeSaveProgress(force: true);
    setState(() {
      _currentEpisodeId = next.id;
      _currentEpisodeLabel = '${next.episodeNum}. ${next.title}';
      _title = _currentEpisodeLabel;
      _lastSavedMs = 0;
      _position = Duration.zero;
      _duration = Duration.zero;
    });
    _open(repo.episodeUrl(next.id, next.containerExtension));
    _poke();
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  Widget _buildVideo() {
    switch (_aspect) {
      case VideoAspect.auto:
        return Video(controller: _controller, fit: BoxFit.contain, controls: NoVideoControls);
      case VideoAspect.fill:
        // "Riempi" = stretch to the screen in BOTH directions: the whole frame
        // stays visible (nothing cropped like BoxFit.cover) and there are no
        // black bars — at the cost of distorting the aspect ratio.
        return Video(controller: _controller, fit: BoxFit.fill, controls: NoVideoControls);
      case VideoAspect.ratio169:
        return Center(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Video(controller: _controller, fit: BoxFit.fill, controls: NoVideoControls),
          ),
        );
      case VideoAspect.ratio43:
        return Center(
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: Video(controller: _controller, fit: BoxFit.fill, controls: NoVideoControls),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasNext = _isSeries && _findNextEpisode() != null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          _poke();
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          onHover: (_) => _poke(),
          child: Stack(
            children: [
              Positioned.fill(
                child: _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.white),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : _buildVideo(),
              ),
              // Opaque tap catcher above the video (media_kit's Video otherwise
              // swallows taps); it sits below the controls layer so buttons
              // still receive their taps when the controls are visible.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _poke,
                ),
              ),
              // Buffering / auto-reconnect indicator.
              if (_error == null && (_buffering || _reconnecting))
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 46, height: 46,
                            child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                          ),
                          if (_reconnecting) ...[
                            const SizedBox(height: 14),
                            Text(
                              'Riconnessione… (tentativo $_retry)',
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              AnimatedOpacity(
                opacity: _controlsVisible ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: Column(
                    children: [
                      _TopBar(
                        title: _title,
                        isLive: _isLive,
                        streamId: _currentStreamId,
                        qualityLabel: _qualityLabel,
                        onBack: () => context.pop(),
                      ),
                      const Spacer(),
                      _ControlsPanel(
                        playing: _playing,
                        isLive: _isLive,
                        channelListOpen: _channelListOpen,
                        onChannelList: _isLive
                            ? () => setState(() => _channelListOpen = !_channelListOpen)
                            : null,
                        audioTracks: _audioTracks,
                        currentAudioId: _currentAudioId,
                        onSelectAudio: _selectAudio,
                        showVolume: !Platform.isAndroid,
                        position: _position,
                        duration: _duration,
                        volume: _volume,
                        rate: _rate,
                        subtitlesOn: _subtitlesOn,
                        aspect: _aspect,
                        hasNext: hasNext,
                        skipSeconds: ref.watch(playerSettingsProvider).skipSeconds,
                        formatDuration: _formatDuration,
                        onSkipBack: () => _skip(-ref.read(playerSettingsProvider).skipSeconds),
                        onSkipForward: () => _skip(ref.read(playerSettingsProvider).skipSeconds),
                        onPlayPause: _togglePlayPause,
                        onSeek: (d) {
                          _player.seek(d);
                          _poke();
                        },
                        onVolume: (v) {
                          _applyVolume(v);
                          ref.read(playerSettingsProvider.notifier).setVolume(v);
                          _poke();
                        },
                        onMute: _toggleMute,
                        onSubtitles: _toggleSubtitles,
                        onAspect: _cycleAspect,
                        onSpeed: _cycleSpeed,
                        onNext: _playNextEpisode,
                      ),
                    ],
                  ),
                ),
              ),
              // Live channel list overlay (zap without leaving the player).
              if (_channelListOpen)
                _ChannelListOverlay(
                  currentStreamId: _currentStreamId,
                  onClose: () => setState(() => _channelListOpen = false),
                  onSelect: _switchChannel,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({
    required this.title,
    required this.isLive,
    required this.streamId,
    required this.qualityLabel,
    required this.onBack,
  });

  final String? title;
  final bool isLive;
  final String? streamId;
  final String? qualityLabel;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String? epgLine;
    if (streamId != null) {
      final epg = ref.watch(shortEpgProvider(streamId!)).value;
      if (epg != null && epg.isNotEmpty) {
        final live = epg.where((p) => p.isLive).toList();
        if (live.isNotEmpty) epgLine = live.first.title;
      }
    }

    return SafeArea(
      bottom: false,
      child: Padding(
        // Same translucent black surface as the bottom controls, so the top and
        // bottom bars match and stay readable over any content.
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              IconButton(
                autofocus: true,
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: onBack,
              ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title != null)
                    Text(
                      title!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (epgLine != null)
                    Text(
                      epgLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                ],
              ),
            ),
            if (qualityLabel != null)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white24),
                ),
                child: Text(
                  qualityLabel!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            if (isLive)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'LIVE',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
            IconButton(
              tooltip: 'Impostazioni',
              icon: const Icon(Icons.settings_outlined, color: Colors.white),
              onPressed: () => context.push('/settings'),
            ),
            Consumer(
              builder: (context, ref, _) {
                final isFullscreen = ref.watch(fullscreenProvider);
                return IconButton(
                  tooltip: isFullscreen ? 'Esci da schermo intero' : 'Schermo intero',
                  icon: Icon(
                    isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                    color: Colors.white,
                  ),
                  onPressed: () => ref.read(fullscreenProvider.notifier).toggle(),
                );
              },
            ),
          ],
          ),
        ),
      ),
    );
  }
}

class _ControlsPanel extends StatelessWidget {
  const _ControlsPanel({
    required this.playing,
    required this.isLive,
    required this.position,
    required this.duration,
    required this.volume,
    required this.rate,
    required this.subtitlesOn,
    required this.aspect,
    required this.hasNext,
    required this.skipSeconds,
    required this.formatDuration,
    required this.onSkipBack,
    required this.onSkipForward,
    required this.onPlayPause,
    required this.onSeek,
    required this.onVolume,
    required this.onMute,
    required this.onSubtitles,
    required this.onAspect,
    required this.onSpeed,
    required this.onNext,
    required this.channelListOpen,
    required this.onChannelList,
    required this.audioTracks,
    required this.currentAudioId,
    required this.onSelectAudio,
    required this.showVolume,
  });

  final bool playing;
  final bool isLive;
  final Duration position;
  final Duration duration;
  final double volume;
  final double rate;
  final bool subtitlesOn;
  final VideoAspect aspect;
  final bool hasNext;
  final int skipSeconds;
  final String Function(Duration) formatDuration;
  final VoidCallback onSkipBack;
  final VoidCallback onSkipForward;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<double> onVolume;
  final VoidCallback onMute;
  final VoidCallback onSubtitles;
  final VoidCallback onAspect;
  final VoidCallback onSpeed;
  final VoidCallback onNext;

  /// Live channel list (only for live). Null hides the "Canali" button.
  final bool channelListOpen;
  final VoidCallback? onChannelList;

  final List<AudioTrack> audioTracks;
  final String? currentAudioId;
  final ValueChanged<AudioTrack> onSelectAudio;

  /// False on Android: volume is handled by the hardware keys there.
  final bool showVolume;

  @override
  Widget build(BuildContext context) {
    // A translucent black surface behind the controls keeps them readable over
    // any content underneath (bright films/series included) while still letting
    // the video show through.
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
          // Live streams have no seek bar (and can't be scrubbed).
          if (!isLive)
            Row(
              children: [
                Text(
                  formatDuration(position),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                Expanded(
                  child: Slider(
                    value: position.inMilliseconds
                        .clamp(0, duration.inMilliseconds)
                        .toDouble(),
                    max: duration.inMilliseconds
                        .clamp(1, double.maxFinite.toInt())
                        .toDouble(),
                    onChanged: (v) => onSeek(Duration(milliseconds: v.round())),
                  ),
                ),
                Text(
                  formatDuration(duration),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          Row(
            children: [
              // Live channel list opener, at the bottom-left of the controls box.
              if (onChannelList != null)
                TextButton.icon(
                  onPressed: onChannelList,
                  icon: Icon(
                    channelListOpen ? Icons.close : Icons.playlist_play,
                    color: Colors.white,
                    size: 22,
                  ),
                  label: const Text('Canali',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                ),
              // Skip back/forward (on-demand content only).
              if (!isLive)
                _SkipButton(
                  seconds: skipSeconds,
                  forward: false,
                  onPressed: onSkipBack,
                ),
              // Live streams can't be paused, so there's no play/pause button.
              if (!isLive)
                IconButton(
                  iconSize: 34,
                  icon: Icon(
                    playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
                    color: Colors.white,
                  ),
                  tooltip: playing ? 'Pausa' : 'Play',
                  onPressed: onPlayPause,
                ),
              if (!isLive)
                _SkipButton(
                  seconds: skipSeconds,
                  forward: true,
                  onPressed: onSkipForward,
                ),
              // On Android the hardware keys (phone/remote) drive the system
              // volume, so the in-app mute + slider only exist on desktop.
              if (showVolume) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(
                    volume > 0 ? Icons.volume_up : Icons.volume_off,
                    color: Colors.white,
                  ),
                  tooltip: volume > 0 ? 'Muto' : 'Riattiva audio',
                  onPressed: onMute,
                ),
                SizedBox(
                  width: 110,
                  child: Slider(
                    value: volume.clamp(0, 100),
                    max: 100,
                    onChanged: onVolume,
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '${volume.round()}%',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              // Speed only makes sense for on-demand content, not live.
              if (!isLive)
                TextButton(
                  onPressed: onSpeed,
                  child: Text(
                    '${rate.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '')}x',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              IconButton(
                icon: Icon(
                  subtitlesOn ? Icons.subtitles : Icons.subtitles_off_outlined,
                  color: subtitlesOn ? Colors.white : Colors.white54,
                ),
                tooltip: 'Sottotitoli',
                onPressed: onSubtitles,
              ),
              // Audio-track / language selector (only when there is a choice).
              if (audioTracks.length > 1)
                PopupMenuButton<AudioTrack>(
                  tooltip: 'Lingua audio',
                  icon: const Icon(Icons.multitrack_audio, color: Colors.white),
                  color: const Color(0xF01C1C1E),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: AppColors.glassBorder),
                  ),
                  onSelected: onSelectAudio,
                  itemBuilder: (context) => [
                    for (final t in audioTracks)
                      PopupMenuItem<AudioTrack>(
                        value: t,
                        child: Row(
                          children: [
                            Icon(
                              Icons.check,
                              size: 18,
                              color: t.id == currentAudioId ? Colors.white : Colors.transparent,
                            ),
                            const SizedBox(width: 8),
                            Text(_audioTrackLabel(t), style: const TextStyle(color: Colors.white)),
                          ],
                        ),
                      ),
                  ],
                ),
              TextButton.icon(
                onPressed: onAspect,
                icon: const Icon(Icons.aspect_ratio, color: Colors.white, size: 20),
                label: Text(
                  aspect.label,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              if (hasNext)
                IconButton(
                  icon: const Icon(Icons.skip_next, color: Colors.white, size: 30),
                  tooltip: 'Prossimo episodio',
                  onPressed: onNext,
                ),
            ],
          ),
          ],
        ),
      ),
    );
  }
}

class _SkipButton extends StatelessWidget {
  const _SkipButton({required this.seconds, required this.forward, required this.onPressed});

  final int seconds;
  final bool forward;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // Plain fast-forward/rewind glyph (no baked-in number) with the chosen
    // step written *below* it as +N / -N, so nothing overlaps the icon.
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(forward ? Icons.fast_forward : Icons.fast_rewind, color: Colors.white, size: 30),
            const SizedBox(height: 2),
            Text(
              '${forward ? '+' : '-'}$seconds',
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom-left overlay listing live channels so you can zap without leaving the
/// player. It also lets you navigate between categories. A tap on the dim area
/// closes it; picking a channel switches playback in place.
class _ChannelListOverlay extends ConsumerStatefulWidget {
  const _ChannelListOverlay({
    required this.currentStreamId,
    required this.onClose,
    required this.onSelect,
  });

  final String? currentStreamId;
  final VoidCallback onClose;
  final void Function(String streamId, String name) onSelect;

  @override
  ConsumerState<_ChannelListOverlay> createState() => _ChannelListOverlayState();
}

class _ChannelListOverlayState extends ConsumerState<_ChannelListOverlay> {
  // null = "Tutti i canali" (all channels across categories).
  String? _catId;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final panelW = (size.width * 0.9).clamp(260.0, 420.0);
    // Sit above the bottom controls (bottomOffset) and below the top bar.
    const bottomOffset = 140.0;
    final panelH = (size.height - bottomOffset - 96).clamp(220.0, 560.0);

    final cats = ref.watch(liveCategoriesProvider).value ?? const [];
    final channelsAsync =
        _catId == null ? ref.watch(allChannelsProvider) : ref.watch(liveStreamsProvider(_catId!));

    return Positioned.fill(
      child: Stack(
        children: [
          // Tap outside the panel to dismiss.
          Positioned.fill(
            child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onClose),
          ),
          Positioned(
            left: 12,
            bottom: bottomOffset,
            width: panelW,
            height: panelH,
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header: category dropdown (categories can be many) + close.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 6, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: GlassDropdown<String?>(
                            value: _catId,
                            expand: true,
                            onChanged: (v) => setState(() => _catId = v),
                            items: [
                              const GlassDropdownEntry<String?>(
                                value: null,
                                label: 'Tutti i canali',
                              ),
                              for (final c in cats)
                                GlassDropdownEntry<String?>(value: c.id, label: c.name),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: widget.onClose,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: channelsAsync.when(
                      data: (list) {
                        if (list.isEmpty) {
                          return const Center(
                            child: Text('Nessun canale.',
                                style: TextStyle(color: AppColors.textSecondary)),
                          );
                        }
                        return ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: list.length,
                          itemBuilder: (context, index) {
                            final Channel c = list[index];
                            final selected = c.streamId == widget.currentStreamId;
                            return ListTile(
                              dense: true,
                              selected: selected,
                              selectedTileColor: Colors.white.withValues(alpha: 0.08),
                              leading: SizedBox(
                                width: 42,
                                height: 42,
                                child: c.logoUrl != null
                                    ? CachedNetworkImage(
                                        imageUrl: c.logoUrl!,
                                        fit: BoxFit.contain,
                                        errorWidget: (_, _, _) =>
                                            const Icon(Icons.tv, color: Colors.white54),
                                      )
                                    : const Icon(Icons.tv, color: Colors.white54),
                              ),
                              title: Text(
                                c.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: selected ? Colors.white : AppColors.textPrimary,
                                  fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                                ),
                              ),
                              trailing: selected
                                  ? const Icon(Icons.equalizer, color: Colors.white, size: 18)
                                  : null,
                              onTap: () => widget.onSelect(c.streamId, c.name),
                            );
                          },
                        );
                      },
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text('$e', style: const TextStyle(color: AppColors.textSecondary)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

