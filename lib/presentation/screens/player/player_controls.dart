import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';

import '../../../core/fullscreen.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui_mode.dart';
import '../../../state/live_providers.dart';
import '../../../state/player_settings_providers.dart';
import '../../common/tv_focusable.dart';

/// The player's chrome — top bar, bottom controls panel, seek bar and the
/// floating shortcut — pulled out of PlayerScreen so it can be widget-tested.
///
/// PlayerScreen itself cannot be pumped on the host (it spins up native libmpv
/// in initState), which is exactly why remote-navigation bugs kept surviving
/// here: "la parte destra non e' selezionabile", "impostazioni e indietro non
/// sono selezionabili". These widgets take plain values and callbacks, so a
/// test can drive the whole control surface with a simulated D-pad
/// (player_controls_test.dart).

/// The playback speeds offered by the speed dropdown.
const kPlaybackSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

/// "1x", "1.25x" — trailing zeros trimmed.
String formatSpeed(double rate) {
  final text = rate
      .toStringAsFixed(2)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '');
  return '${text}x';
}

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

class PlayerTopBar extends ConsumerWidget {
  const PlayerTopBar({
    super.key,
    required this.title,
    required this.isLive,
    required this.streamId,
    required this.qualityLabel,
    required this.onBack,
    this.onPip,
    this.onSettings,
  });

  final String? title;
  final bool isLive;
  final String? streamId;
  final String? qualityLabel;
  final VoidCallback onBack;

  /// Enter Picture-in-Picture (phone only); null hides the button.
  final VoidCallback? onPip;

  /// Opens Settings. Injected (instead of pushing the route inline) so the bar
  /// can be driven by a remote in widget tests without a router.
  final VoidCallback? onSettings;

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
              // NB: no autofocus. This used to grab the focus as the player
              // opened, so OK (with the controls up) hit Back and left the
              // player instead of toggling the menu.
              PlayerButton(
                tooltip: 'Indietro',
                onPressed: onBack,
                child: const Icon(Icons.arrow_back, color: Colors.white),
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
            if (onPip != null)
              PlayerButton(
                tooltip: 'Finestra mobile',
                onPressed: onPip!,
                child: const Icon(Icons.picture_in_picture_alt, color: Colors.white),
              ),
            PlayerButton(
              tooltip: 'Impostazioni',
              onPressed: onSettings ?? () => context.push('/settings'),
              child: const Icon(Icons.settings_outlined, color: Colors.white),
            ),
            // Windows only: on Android the app is permanently fullscreen.
            if (fullscreenToggleAvailable)
              Consumer(
                builder: (context, ref, _) {
                  final isFullscreen = ref.watch(fullscreenProvider);
                  return PlayerButton(
                    tooltip: isFullscreen ? 'Esci da schermo intero' : 'Schermo intero',
                    onPressed: () => ref.read(fullscreenProvider.notifier).toggle(),
                    child: Icon(
                      isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                      color: Colors.white,
                    ),
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

/// Floating action over the video ("Salta sigla" / "Prossimo episodio").
///
/// Deliberately shown even while the controls are hidden — that is the whole
/// point. It sits on its own in the Stack (outside the controls' ExcludeFocus)
/// so a remote can focus it: its own key handler then takes OK before the
/// player's root node sees it.
class PlayerFloatingAction extends StatelessWidget {
  const PlayerFloatingAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.focusNode,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      borderRadius: 14,
      focusNode: focusNode,
      // The pill is white: a white focus ring would vanish on it, so this one
      // is black (white glow stays, for the dark video behind).
      ringColor: Colors.black,
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          // Solid white so it reads over any frame of video.
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.black, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

/// A player control a remote can actually land on.
///
/// Material's own focus highlight is invisible in this app (the theme sets
/// `highlightColor: transparent` + `NoSplash`), so on TV the focus was moving
/// between the player buttons with nothing to show for it. Every control goes
/// through [TvFocusable] instead, which paints the same focus ring used across
/// the app.
class PlayerButton extends StatelessWidget {
  const PlayerButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.tooltip,
    this.focusNode,
  });

  final VoidCallback onPressed;
  final Widget child;
  final String? tooltip;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    // [tooltip] is only an accessibility label via Semantics — NO visual
    // tooltip box. The pop-up "explanation" boxes on hover/touch/focus were
    // ugly on the player (user request), so they are gone.
    return Semantics(
      button: true,
      label: tooltip,
      child: TvFocusable(
        borderRadius: 12,
        focusNode: focusNode,
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: child,
        ),
      ),
    );
  }
}

/// Audio-track picker. Same glass menu as [GlassDropdown]: every entry is a
/// [TvFocusable] (visible ring + OK on TV) and the current track autofocuses
/// when the menu opens, so the D-pad lands inside it. The old PopupMenuButton
/// items had invisible focus here (transparent highlight + NoSplash).
class _AudioMenuButton extends StatefulWidget {
  const _AudioMenuButton({
    required this.tracks,
    required this.currentAudioId,
    required this.onSelected,
  });

  final List<AudioTrack> tracks;
  final String? currentAudioId;
  final ValueChanged<AudioTrack> onSelected;

  @override
  State<_AudioMenuButton> createState() => _AudioMenuButtonState();
}

class _AudioMenuButtonState extends State<_AudioMenuButton> {
  final _controller = MenuController();

  @override
  Widget build(BuildContext context) {
    // The entry the D-pad lands on when the menu opens: the current track, or
    // the first one if nothing matches (autofocus must land somewhere).
    final focusId = widget.tracks.any((t) => t.id == widget.currentAudioId)
        ? widget.currentAudioId
        : (widget.tracks.isEmpty ? null : widget.tracks.first.id);

    return MenuAnchor(
      controller: _controller,
      consumeOutsideTap: true,
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(Color(0xF01C1C1E)),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(8),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.glassBorder),
          ),
        ),
        padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 6, horizontal: 4)),
      ),
      menuChildren: [
        for (final t in widget.tracks)
          TvFocusable(
            borderRadius: 10,
            autofocus: t.id == focusId,
            onTap: () {
              _controller.close();
              widget.onSelected(t);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check,
                    size: 18,
                    color: t.id == widget.currentAudioId ? Colors.white : Colors.transparent,
                  ),
                  const SizedBox(width: 8),
                  Text(_audioTrackLabel(t), style: const TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ),
      ],
      builder: (context, controller, _) => PlayerButton(
        tooltip: 'Lingua audio',
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
        child: const Icon(Icons.multitrack_audio, color: Colors.white),
      ),
    );
  }
}

/// Seek bar with its own focus ring: a bare Slider takes focus from the D-pad
/// with no visible sign, which reads as "the focus vanished". Left/Right scrub
/// while it is focused; Up/Down move on to the buttons.
class SeekBar extends StatefulWidget {
  const SeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    required this.formatDuration,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;
  final String Function(Duration) formatDuration;

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  final _node = FocusNode(debugLabel: 'player.seekbar');

  /// Consecutive key-repeat events in the current hold: drives the ramp.
  int _repeats = 0;

  /// Optimistic position while scrubbing. The player's own position lags
  /// behind by a frame or two, so accumulating on it would make a fast hold
  /// jump backwards; this accumulates locally and clears once playback
  /// catches up.
  Duration? _scrubbing;

  /// Seconds per key event, ramping up the longer the key is held: taps stay
  /// precise, a hold sweeps. (Material's Slider did neither — it jumped a
  /// fixed *fraction* of the whole video, i.e. 6 minutes on a 2h film, and
  /// ignored key repeats entirely.)
  static int stepSecondsFor(int repeats) {
    if (repeats < 3) return 5;
    if (repeats < 8) return 15;
    if (repeats < 16) return 30;
    return 60;
  }

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocus);
  }

  void _onFocus() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(SeekBar old) {
    super.didUpdateWidget(old);
    // Playback reached (or nearly reached) the point we scrubbed to: hand the
    // display back to the real position.
    final target = _scrubbing;
    if (target != null && (widget.position - target).abs() < const Duration(seconds: 2)) {
      _scrubbing = null;
    }
  }

  @override
  void dispose() {
    _node.removeListener(_onFocus);
    _node.dispose();
    super.dispose();
  }

  Duration get _shown => _scrubbing ?? widget.position;

  void _seekBy(int seconds) {
    var target = _shown + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (widget.duration > Duration.zero && target > widget.duration) {
      target = widget.duration;
    }
    setState(() => _scrubbing = target);
    widget.onSeek(target);
  }

  /// Left/Right scrub (with the ramp); everything else — Up/Down above all —
  /// is left alone so the D-pad can move off the bar onto the buttons.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final left = event.logicalKey == LogicalKeyboardKey.arrowLeft;
    final right = event.logicalKey == LogicalKeyboardKey.arrowRight;
    if (!left && !right) return KeyEventResult.ignored;

    if (event is KeyUpEvent) {
      _repeats = 0;
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent) {
      _repeats = 0;
    } else if (event is KeyRepeatEvent) {
      _repeats++;
    } else {
      return KeyEventResult.ignored;
    }
    _seekBy(stepSecondsFor(_repeats) * (left ? -1 : 1));
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final maxMs = widget.duration.inMilliseconds.clamp(1, double.maxFinite.toInt());
    return Row(
      children: [
        Text(
          widget.formatDuration(_shown),
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
        Expanded(
          child: Focus(
            focusNode: _node,
            onKeyEvent: _onKey,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 130),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  // D-pad only, like every other control: on touch the slider
                  // thumb is feedback enough (see dpadHighlightVisible).
                  color: _node.hasFocus && dpadHighlightVisible()
                      ? AppColors.focusRing
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              // The Slider must not be a focus stop of its own: ours is the
              // wrapper above, which owns the ring AND the key handling.
              child: ExcludeFocus(
                child: Slider(
                  value: _shown.inMilliseconds.clamp(0, maxMs).toDouble(),
                  max: maxMs.toDouble(),
                  onChanged: (v) {
                    final target = Duration(milliseconds: v.round());
                    setState(() => _scrubbing = target);
                    widget.onSeek(target);
                  },
                ),
              ),
            ),
          ),
        ),
        Text(
          widget.formatDuration(widget.duration),
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ],
    );
  }
}

class PlayerControlsPanel extends StatelessWidget {
  const PlayerControlsPanel({
    super.key,
    required this.playing,
    required this.isLive,
    required this.position,
    required this.duration,
    required this.volume,
    required this.rate,
    required this.subtitlesOn,
    required this.aspect,
    required this.skipSeconds,
    required this.formatDuration,
    required this.onSkipBack,
    required this.onSkipForward,
    required this.onPlayPause,
    required this.onSeek,
    required this.onVolume,
    required this.onMute,
    required this.onSubtitlesChanged,
    required this.onAspect,
    required this.onRate,
    required this.channelListOpen,
    required this.onChannelList,
    required this.episodeListOpen,
    required this.onEpisodeList,
    required this.onNextEpisode,
    required this.audioTracks,
    required this.currentAudioId,
    required this.onSelectAudio,
    required this.showVolume,
    required this.primaryFocusNode,
  });

  /// Where the D-pad focus lands when the menu opens.
  final FocusNode primaryFocusNode;

  final bool playing;
  final bool isLive;
  final Duration position;
  final Duration duration;
  final double volume;
  final double rate;
  final bool subtitlesOn;
  final VideoAspect aspect;
  final int skipSeconds;
  final String Function(Duration) formatDuration;
  final VoidCallback onSkipBack;
  final VoidCallback onSkipForward;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<double> onVolume;
  final VoidCallback onMute;
  /// Sets subtitles on/off from the dropdown.
  final ValueChanged<bool> onSubtitlesChanged;
  final VoidCallback onAspect;

  /// Sets the playback speed from the dropdown.
  final ValueChanged<double> onRate;

  /// Live channel list (only for live). Null hides the "Canali" button.
  final bool channelListOpen;
  final VoidCallback? onChannelList;

  /// Series episode list (only for series). Null hides the "Episodi" button.
  final bool episodeListOpen;
  final VoidCallback? onEpisodeList;

  /// One-tap "Prossimo episodio" in the bar. Null hides it — it only shows
  /// when the floating shortcut isn't up (see showInlineNext in the player).
  final VoidCallback? onNextEpisode;

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
            SeekBar(
              position: position,
              duration: duration,
              onSeek: onSeek,
              formatDuration: formatDuration,
            ),
          Row(
            children: [
              // Live channel list opener, at the bottom-left of the controls box.
              if (onChannelList != null)
                PlayerButton(
                  // Live has no play/pause, so this is the main control.
                  focusNode: isLive ? primaryFocusNode : null,
                  onPressed: onChannelList!,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        channelListOpen ? Icons.close : Icons.playlist_play,
                        color: Colors.white,
                        size: 22,
                      ),
                      const SizedBox(width: 6),
                      const Text('Canali',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              // Series episode list opener (bottom-left, mirrors "Canali").
              if (onEpisodeList != null)
                PlayerButton(
                  onPressed: onEpisodeList!,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        episodeListOpen ? Icons.close : Icons.video_library_outlined,
                        color: Colors.white,
                        size: 22,
                      ),
                      const SizedBox(width: 6),
                      const Text('Episodi',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    ],
                  ),
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
                PlayerButton(
                  focusNode: primaryFocusNode,
                  tooltip: playing ? 'Pausa' : 'Play',
                  onPressed: onPlayPause,
                  child: Icon(
                    playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
              if (!isLive)
                _SkipButton(
                  seconds: skipSeconds,
                  forward: true,
                  onPressed: onSkipForward,
                ),
              // One-tap next episode: the in-bar fallback for when the floating
              // "Prossimo episodio" isn't showing (not near the end).
              if (onNextEpisode != null)
                PlayerButton(
                  tooltip: 'Prossimo episodio',
                  onPressed: onNextEpisode!,
                  child: const Icon(Icons.skip_next, color: Colors.white, size: 30),
                ),
              // On Android the hardware keys (phone/remote) drive the system
              // volume, so the in-app mute + slider only exist on desktop.
              if (showVolume) ...[
                const SizedBox(width: 4),
                PlayerButton(
                  tooltip: volume > 0 ? 'Muto' : 'Riattiva audio',
                  onPressed: onMute,
                  child: Icon(
                    volume > 0 ? Icons.volume_up : Icons.volume_off,
                    color: Colors.white,
                  ),
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
              // Speed and subtitles are DROPDOWNS, not cycle buttons: you pick
              // the value you want instead of pressing OK until it comes round.
              // GlassDropdown is the TV-ready one — ring on the trigger, ring
              // on every entry, and the focus lands on the CURRENT value when
              // the menu opens (see glass_dropdown.dart).
              //
              // Speed only makes sense for on-demand content, not live.
              if (!isLive)
                PlayerMenuButton<double>(
                  tooltip: 'Velocità',
                  value: kPlaybackSpeeds.contains(rate) ? rate : 1.0,
                  onSelected: onRate,
                  entries: [
                    for (final s in kPlaybackSpeeds)
                      PlayerMenuEntry(value: s, label: formatSpeed(s)),
                  ],
                  child: Text(
                    formatSpeed(rate),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              PlayerMenuButton<bool>(
                tooltip: 'Sottotitoli',
                value: subtitlesOn,
                onSelected: onSubtitlesChanged,
                entries: const [
                  PlayerMenuEntry(value: false, label: 'Sottotitoli off'),
                  PlayerMenuEntry(value: true, label: 'Sottotitoli on'),
                ],
                child: Icon(
                  subtitlesOn ? Icons.subtitles : Icons.subtitles_off_outlined,
                  color: subtitlesOn ? Colors.white : Colors.white54,
                ),
              ),
              // Audio-track / language selector (only when there is a choice).
              if (audioTracks.length > 1)
                _AudioMenuButton(
                  tracks: audioTracks,
                  currentAudioId: currentAudioId,
                  onSelected: onSelectAudio,
                ),
              PlayerButton(
                tooltip: 'Rapporto d\'aspetto',
                onPressed: onAspect,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.aspect_ratio, color: Colors.white, size: 20),
                    const SizedBox(width: 6),
                    Text(
                      aspect.label,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ],
                ),
              ),
              // "Prossimo episodio" is NOT here: it lives only as the floating
              // shortcut over the video (user request — it was a duplicate).
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
    return PlayerButton(
      tooltip: forward ? 'Avanti $seconds s' : 'Indietro $seconds s',
      onPressed: onPressed,
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
    );
  }
}

/// The player's root key catcher.
///
/// ⚠️ `skipTraversal: true` is the whole point. This node wraps the entire
/// screen, so while it stayed in the traversal ring the D-pad kept LANDING on
/// it — and from a node whose rect is the whole screen, "the nearest widget to
/// the right / above" is meaningless, so the focus got stuck there. That is
/// what made the top bar (indietro, impostazioni) and the right-hand controls
/// (velocità, sottotitoli, aspetto) unreachable on TV.
///
/// It still takes focus on arrival (`autofocus`) and still receives every key
/// event, because key events bubble from the focused descendant up to here.
class PlayerRootFocus extends StatelessWidget {
  const PlayerRootFocus({
    super.key,
    required this.onKeyEvent,
    required this.child,
  });

  final FocusOnKeyEventCallback onKeyEvent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      skipTraversal: true,
      onKeyEvent: onKeyEvent,
      child: child,
    );
  }
}

/// One choice in a [PlayerMenuButton].
class PlayerMenuEntry<T> {
  const PlayerMenuEntry({required this.value, required this.label});

  final T value;
  final String label;
}

/// A compact player control that opens a **dropdown** instead of cycling
/// through values (user request for speed and subtitles: "deve essere un menu
/// a tendina, ricordati il focus").
///
/// The trigger stays icon-sized so the controls bar doesn't overflow — a
/// full-width dropdown in that Row blew the layout on a TV screen. Every entry
/// is a [TvFocusable] (visible ring, OK activates) and the menu **opens with
/// the focus on the current value**, so a remote can go straight up or down
/// from where it already is.
class PlayerMenuButton<T> extends StatefulWidget {
  const PlayerMenuButton({
    super.key,
    required this.tooltip,
    required this.value,
    required this.entries,
    required this.onSelected,
    required this.child,
  });

  final String tooltip;
  final T value;
  final List<PlayerMenuEntry<T>> entries;
  final ValueChanged<T> onSelected;

  /// What the trigger shows (an icon, or the current speed).
  final Widget child;

  @override
  State<PlayerMenuButton<T>> createState() => _PlayerMenuButtonState<T>();
}

class _PlayerMenuButtonState<T> extends State<PlayerMenuButton<T>> {
  final _controller = MenuController();

  @override
  Widget build(BuildContext context) {
    // Autofocus has to land somewhere: the current value, else the first.
    final focusValue = widget.entries.any((e) => e.value == widget.value)
        ? widget.value
        : (widget.entries.isEmpty ? null : widget.entries.first.value);

    return MenuAnchor(
      controller: _controller,
      consumeOutsideTap: true,
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(Color(0xF01C1C1E)),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(8),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.glassBorder),
          ),
        ),
        padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 6, horizontal: 4)),
      ),
      menuChildren: [
        for (final e in widget.entries)
          TvFocusable(
            borderRadius: 10,
            autofocus: e.value == focusValue,
            onTap: () {
              _controller.close();
              widget.onSelected(e.value);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check,
                    size: 18,
                    color: e.value == widget.value ? Colors.white : Colors.transparent,
                  ),
                  const SizedBox(width: 8),
                  Text(e.label, style: const TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ),
      ],
      builder: (context, controller, _) => PlayerButton(
        tooltip: widget.tooltip,
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
        child: widget.child,
      ),
    );
  }
}
