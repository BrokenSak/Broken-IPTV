import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../core/format.dart';
import '../../../core/pip.dart';
import '../../../core/playback_activity.dart';
import '../../../data/models/series_item.dart';
import '../../../data/models/watch_progress.dart';
import '../../../state/live_providers.dart';
import '../../../core/ui_mode.dart';
import 'channel_list_overlay.dart';
import 'episode_list_overlay.dart';
import 'player_controls.dart';
import 'player_keys.dart';
import 'series_prompts.dart';
import '../../../state/player_settings_providers.dart';
import '../../../state/series_providers.dart';
import '../../../state/watch_progress_providers.dart';

const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

/// Desktop-only software gain on top of the 0–100 UI volume: IPTV streams are
/// often encoded quiet, so UI 100% maps to mpv 150 (the UI keeps its normal
/// 0–100 scale). Android stays at 1.0 — volume belongs to the hardware keys.
final double _volumeBoost = Platform.isAndroid ? 1.0 : 1.5;


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
    this.progressUrl,
  });

  final String? streamUrl;

  /// What to record in "continua a guardare" instead of [streamUrl].
  ///
  /// Set only when playing a **downloaded file**: playback reads the local
  /// path, but that path means nothing on the phone's other devices (nor here
  /// once the download is deleted), so the resume point stores the streamable
  /// URL and syncs across devices like any other.
  final String? progressUrl;

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

  /// URL to store in the resume point. Normally what is playing, but a
  /// downloaded file plays from disk and that path is meaningless elsewhere —
  /// there we save the stream URL so "continua a guardare" works on every
  /// device. Only while still on the item we were opened with: moving to the
  /// next episode makes [_currentUrl] the truth again.
  String get _resumeUrl {
    final override = widget.progressUrl;
    if (override != null && override.isNotEmpty && _currentUrl == widget.streamUrl) {
      return override;
    }
    return _currentUrl;
  }

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

  // Playback resilience: auto-reconnect with a ts↔m3u8 fallback for live.
  int _retry = 0;
  bool _reconnecting = false;
  String _liveExt = 'ts';
  Timer? _retryTimer;
  int? _videoWidth;
  int? _videoHeight;

  /// True once the device has confirmed it can do Picture-in-Picture (phone
  /// only). Until then the PiP button stays hidden.
  bool _pipSupported = false;

  // Live channel-list overlay (zap without leaving the player).
  bool _channelListOpen = false;

  // Series episode-list overlay: switch episode / season without leaving the
  // player. The on-demand equivalent of the live channel list.
  bool _episodeListOpen = false;

  /// The control the D-pad lands on when the menu opens (play/pause, or the
  /// channel list button on live, which has no play/pause).
  final FocusNode _primaryControlNode = FocusNode(debugLabel: 'player.primary');

  /// The floating shortcut ("Prossimo episodio" / "Ricomincia da capo").
  /// Focused on TV as soon as it appears (with the controls down), so OK
  /// presses it.
  final FocusNode _floatingActionNode = FocusNode(debugLabel: 'player.floating');
  bool _floatingFocusRequested = false;

  /// How close to the end the credits button appears.
  static const _creditsWindow = Duration(seconds: 90);

  /// "Ricomincia da capo": flashed for a few seconds right after a resume, so
  /// you can start over instead of continuing (playback resumes on its own).
  bool _showRestart = false;
  Timer? _restartTimer;

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
    // Tells the cross-device sync to keep off the network while a stream is
    // playing (see PlaybackActivity). Cleared in dispose().
    PlaybackActivity.active = true;
    // Only the player is landscape-only on Android: the rest of the app
    // rotates freely. Restored in dispose().
    if (Platform.isAndroid) {
      unawaited(SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]));
    }
    final settings = ref.read(playerSettingsProvider);
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
    // NB: no render/filter tweaking here. The upscaling feature (1.6.0→1.6.2)
    // was removed: its lavfi software filters black-screened live channels
    // against media_kit's hardware decoding (HANDOFF §7).

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
        // Seek to the saved resume point once the media is ready, then flash
        // the "Ricomincia da capo" shortcut for a few seconds.
        if (_pendingResumeMs != null && duration.inMilliseconds > 0) {
          final target = _pendingResumeMs!;
          _pendingResumeMs = null;
          if (target < duration.inMilliseconds - 5000) {
            _player.seek(Duration(milliseconds: target));
            _flashRestart();
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

    // Phone only: allow Picture-in-Picture while a video is playing — pressing
    // Home drops into a floating window instead of just backgrounding. Never on
    // TV. The listener strips the controls overlay in the tiny PiP window.
    // The button only appears once the device confirms it supports PiP, so it
    // can never be a control that silently does nothing.
    if (isPhoneMode()) {
      PipService.instance.addModeListener(_onPipModeChanged);
      PipService.instance.setAllowed(true);
      unawaited(PipService.instance.isSupported().then((ok) {
        if (mounted && ok) setState(() => _pipSupported = true);
      }));
    }

    // TV: the controls start visible, but the root Focus (autofocus) would
    // hold the focus with nothing highlighted and OK doing nothing until you
    // press an arrow. Land the focus on the main control right away, so the
    // ring shows and OK works from the first press.
    if (isTvMode()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Focus the main control (play/pause, or "Canali" on live). The
        // "Ricomincia"/"Prossimo episodio" floating shortcut, when shown, is a
        // step away with an arrow, or takes the focus itself once the controls
        // auto-hide.
        if (mounted && _controlsVisible) _primaryControlNode.requestFocus();
      });
    }
  }

  /// Shows the "Ricomincia da capo" shortcut, auto-hiding after 6s.
  void _flashRestart() {
    _restartTimer?.cancel();
    if (mounted) setState(() => _showRestart = true);
    _restartTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _showRestart = false);
    });
  }

  void _restartFromStart() {
    _restartTimer?.cancel();
    if (mounted) setState(() => _showRestart = false);
    _player.seek(Duration.zero);
  }

  void _open(String url) {
    _currentUrl = url;
    _autoAudioApplied = false;
    _restartTimer?.cancel();
    setState(() {
      _error = null;
      _buffering = true;
      _showRestart = false;
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
    _refocusPrimary();
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
            url: _resumeUrl,
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
            url: _resumeUrl,
            positionMs: pos,
            durationMs: dur,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          );
    _watchProgress.save(progress);
  }

  /// PiP started/ended: in the tiny window there's no room for the controls
  /// overlay or the channel list, so drop them on the way in.
  void _onPipModeChanged(bool inPip) {
    if (inPip && mounted) {
      _hideControls();
      if (_channelListOpen || _episodeListOpen) {
        setState(() {
          _channelListOpen = false;
          _episodeListOpen = false;
        });
      }
    }
  }

  /// Explicit PiP button. The system refuses when the per-app
  /// "Picture-in-picture" permission is off in Android Settings — say so
  /// instead of leaving the user pressing a dead button.
  Future<void> _enterPip() async {
    final ok = await PipService.instance.enter();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Finestra mobile non disponibile: attivala in Impostazioni Android '
            '→ App → Broken IPTV → Picture-in-picture.',
          ),
        ),
      );
    }
  }

  void _closeChannelList() {
    setState(() => _channelListOpen = false);
    _refocusPrimary();
  }

  void _closeEpisodeList() {
    setState(() => _episodeListOpen = false);
    _refocusPrimary();
  }

  /// After an overlay closes on TV, the node that had the focus is gone: land
  /// the D-pad back on the main control, or OK would have no target.
  void _refocusPrimary() {
    if (!isTvMode()) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controlsVisible) _primaryControlNode.requestFocus();
    });
  }

  @override
  void dispose() {
    PlaybackActivity.active = false;
    PipService.instance.setAllowed(false);
    PipService.instance.removeModeListener(_onPipModeChanged);
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
    _restartTimer?.cancel();
    _primaryControlNode.dispose();
    _floatingActionNode.dispose();
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
    _hideTimer = Timer(const Duration(seconds: 5), () {
      // Keep controls (and the bottom-left "Canali"/"Episodi" button) visible
      // while a list overlay is open, and while paused (you want the play
      // button).
      if (mounted && _playing && !_channelListOpen && !_episodeListOpen) {
        _hideControls();
      }
    });
  }

  void _hideControls() {
    _hideTimer?.cancel();
    if (_controlsVisible) setState(() => _controlsVisible = false);
  }

  void _showControls() {
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
      // On TV, land the focus on the main control straight away: otherwise the
      // focus sits on the root node and OK would have no target (the ring is
      // also the "you are here" the remote needs). Not on phone/desktop, where
      // a focus ring appearing on a tap would just look odd.
      if (isTvMode()) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _controlsVisible) _primaryControlNode.requestFocus();
        });
      }
    }
    _scheduleHide();
  }

  void _poke() => _showControls();

  /// Screen tap: open the controls, tap again to close them.
  void _toggleControls() {
    if (_controlsVisible) {
      _hideControls();
    } else {
      _showControls();
    }
  }

  /// Executes the decision made by [playerKeyAction].
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    final skip = ref.read(playerSettingsProvider).skipSeconds;
    switch (playerKeyAction(
      key: event.logicalKey,
      isKeyDown: event is KeyDownEvent,
      controlsVisible: _controlsVisible,
      isDesktop: Platform.isWindows,
      isLive: _isLive,
    )) {
      case PlayerKeyAction.ignore:
        return KeyEventResult.ignored;
      case PlayerKeyAction.revealControls:
        _poke();
        return KeyEventResult.handled;
      case PlayerKeyAction.pokeAndPass:
        _poke();
        return KeyEventResult.ignored;
      case PlayerKeyAction.playPause:
        _togglePlayPause(); // pokes the controls itself
        return KeyEventResult.handled;
      case PlayerKeyAction.seekForward:
        _skip(skip);
        return KeyEventResult.handled;
      case PlayerKeyAction.seekBackward:
        _skip(-skip);
        return KeyEventResult.handled;
    }
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

  /// Toggle Originale ↔ Riempi and persist it, so the choice is remembered
  /// (whether changed here or from Settings). The video reads the provider.
  void _toggleAspect() {
    final current = ref.read(playerSettingsProvider).aspect;
    final next =
        current == VideoAspect.fill ? VideoAspect.original : VideoAspect.fill;
    ref.read(playerSettingsProvider.notifier).setAspect(next);
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
    if (next != null) _playEpisode(next);
  }

  /// Switches playback to [episode] in place — from the floating "Prossimo
  /// episodio" shortcut, the inline control, or the episode-list overlay.
  ///
  /// [resume] restores that episode's own saved position: the list may be
  /// re-opening a half-watched one, so it passes true; the automatic "next
  /// episode" at the end of one starts the following from the beginning.
  void _playEpisode(Episode episode, {bool resume = false}) {
    final repo = ref.read(seriesRepositoryProvider).value;
    if (repo == null) return;
    _maybeSaveProgress(force: true);
    int? pending;
    if (resume && widget.seriesId != null) {
      final p = _watchProgress.forEpisode(widget.seriesId!, episode.id);
      if (p != null && !p.finished && p.positionMs > 5000) pending = p.positionMs;
    }
    setState(() {
      _episodeListOpen = false;
      _currentEpisodeId = episode.id;
      _currentEpisodeLabel = '${episode.episodeNum}. ${episode.title}';
      _title = _currentEpisodeLabel;
      _lastSavedMs = 0;
      _pendingResumeMs = pending;
      _position = Duration.zero;
      _duration = Duration.zero;
    });
    _open(repo.episodeUrl(episode.id, episode.containerExtension));
    _poke();
    _refocusPrimary();
  }

  Widget _buildVideo(VideoAspect aspect) {
    switch (aspect) {
      case VideoAspect.original:
        // Keep the source aspect: letterbox where the video and screen shapes
        // differ, no distortion.
        return Video(controller: _controller, fit: BoxFit.contain, controls: NoVideoControls);
      case VideoAspect.fill:
        // "Riempi" = stretch to the screen in BOTH directions so it fills
        // edge to edge (no bars from a shape mismatch), at the cost of some
        // distortion.
        return Video(controller: _controller, fit: BoxFit.fill, controls: NoVideoControls);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasNext = _isSeries && _findNextEpisode() != null;
    final aspect = ref.watch(playerSettingsProvider).aspect;

    // "Prossimo episodio" floats over the end credits (see series_prompts).
    // NB: the automatic "Salta sigla" was removed — a panel gives no chapter
    // markers and intros shift per episode, so any guess was wrong.
    // Two floating shortcuts (bottom-right, over the video, independent of the
    // controls bar): "Prossimo episodio" near the end, "Ricomincia da capo"
    // just after a resume. They can't coincide (end vs start); next wins.
    final showNext = shouldShowNextEpisode(
      isSeries: _isSeries,
      isLive: _isLive,
      hasNextEpisode: hasNext,
      position: _position,
      duration: _duration,
      creditsWindow: _creditsWindow,
    );
    final overlayOpen = _channelListOpen || _episodeListOpen;
    final showRestart = _showRestart && !showNext;
    // No floating shortcut while a list overlay is open: it would be an extra
    // D-pad stop *outside* the panel, stranding the focus behind it.
    final showFloating = (showNext || showRestart) && !overlayOpen;

    // The inline "Prossimo episodio" control lives in the bar as a fallback for
    // whenever the floating one isn't up (i.e. not near the end) — otherwise
    // there's no way to jump to the next episode mid-play (user request).
    final showInlineNext = hasNext && !showNext;

    // On TV, auto-focus ONLY "Prossimo episodio" (so it's a one-press action
    // at the end). NOT "Ricomincia": auto-focusing it would mean that when the
    // controls hide after 5s, a stray OK restarts the video by mistake. The
    // Ricomincia chip is still reachable with an arrow / tap.
    if (isTvMode()) {
      if (showNext && !_floatingFocusRequested && !_controlsVisible) {
        _floatingFocusRequested = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_controlsVisible) _floatingActionNode.requestFocus();
        });
      } else if (!showNext) {
        _floatingFocusRequested = false;
      }
    }

    return PopScope(
      // Back (TV remote / Android) peels one layer at a time: channel overlay,
      // then the controls — closing the menu is Back's job, since OK now
      // presses the focused button. Only with nothing open does it leave.
      canPop: !_channelListOpen && !_episodeListOpen && !_controlsVisible,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_channelListOpen) {
          _closeChannelList();
          return;
        }
        if (_episodeListOpen) {
          _closeEpisodeList();
          return;
        }
        if (_controlsVisible) _hideControls();
      },
      child: Scaffold(
      backgroundColor: Colors.black,
      // PlayerRootFocus, not a bare Focus: it must stay OUT of the traversal
      // ring (see its doc) or the D-pad lands on this screen-sized node and
      // gets stuck, which is what made the top bar and the right-hand controls
      // unreachable on TV.
      body: PlayerRootFocus(
        onKeyEvent: _handleKey,
        // NB: no MouseRegion onHover. The controls used to pop up on every
        // mouse move, which made the floating shortcuts pointless. They now
        // open only on an explicit action — tap, click, or OK (see _handleKey
        // and the tap catcher) — and close on tap again or after 5s idle.
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
                    : _buildVideo(aspect),
              ),
              // Opaque tap catcher above the video (media_kit's Video otherwise
              // swallows taps); it sits below the controls layer so buttons
              // still receive their taps when the controls are visible.
              // Tap = open the controls, tap again = close them.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleControls,
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
                  // Hidden controls must not keep the focus either: otherwise a
                  // D-pad press acts on an invisible button, and the root node
                  // never gets the key that should reveal the menu. Same while
                  // a list overlay is open: the D-pad must stay inside the
                  // panel, not wander onto the buttons behind it.
                  child: ExcludeFocus(
                    excluding: !_controlsVisible || overlayOpen,
                    child: Column(
                    children: [
                      PlayerTopBar(
                        title: _title,
                        isLive: _isLive,
                        streamId: _currentStreamId,
                        qualityLabel: _qualityLabel,
                        onBack: () => context.pop(),
                        onPip: _pipSupported ? _enterPip : null,
                      ),
                      const Spacer(),
                      PlayerControlsPanel(
                        playing: _playing,
                        isLive: _isLive,
                        channelListOpen: _channelListOpen,
                        onChannelList: _isLive
                            ? () => setState(() => _channelListOpen = !_channelListOpen)
                            : null,
                        episodeListOpen: _episodeListOpen,
                        onEpisodeList: _isSeries
                            ? () => setState(() => _episodeListOpen = !_episodeListOpen)
                            : null,
                        onNextEpisode: showInlineNext ? _playNextEpisode : null,
                        audioTracks: _audioTracks,
                        currentAudioId: _currentAudioId,
                        onSelectAudio: _selectAudio,
                        primaryFocusNode: _primaryControlNode,
                        showVolume: !Platform.isAndroid,
                        position: _position,
                        duration: _duration,
                        volume: _volume,
                        rate: _rate,
                        subtitlesOn: _subtitlesOn,
                        aspect: aspect,
                        skipSeconds: ref.watch(playerSettingsProvider).skipSeconds,
                        formatDuration: formatHms,
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
                        onAspect: _toggleAspect,
                        onSpeed: _cycleSpeed,
                      ),
                    ],
                  ),
                  ),
                ),
              ),
              // Floating shortcuts, above the controls layer and outside its
              // ExcludeFocus: they must stay usable with the menu down.
              if (showFloating)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  right: 20,
                  // Sit clear of the controls box when it is up.
                  bottom: _controlsVisible ? 150 : 40,
                  child: PlayerFloatingAction(
                    focusNode: _floatingActionNode,
                    icon: showNext ? Icons.skip_next : Icons.replay,
                    label: showNext ? 'Prossimo episodio' : 'Ricomincia da capo',
                    onPressed: showNext ? _playNextEpisode : _restartFromStart,
                  ),
                ),
              // Live channel list overlay (zap without leaving the player).
              if (_channelListOpen)
                ChannelListOverlay(
                  currentStreamId: _currentStreamId,
                  onClose: _closeChannelList,
                  onSelect: _switchChannel,
                ),
              // Series episode list overlay (switch episode / season in place).
              if (_episodeListOpen && widget.seriesId != null)
                EpisodeListOverlay(
                  seriesId: widget.seriesId!,
                  currentEpisodeId: _currentEpisodeId,
                  fallbackImage: widget.posterUrl,
                  onClose: _closeEpisodeList,
                  onSelect: (e) => _playEpisode(e, resume: true),
                ),
            ],
          ),
      ),
      ),
    );
  }
}
