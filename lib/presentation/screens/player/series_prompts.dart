/// The floating shortcut to offer over a series episode, if any.
enum SeriesPrompt {
  none,

  /// Early in the episode: jump past the opening titles.
  skipIntro,

  /// Over the end credits: start the next episode.
  nextEpisode,
}

/// Decides which shortcut the player should float over the video.
///
/// Pure (and so testable) because it is all edge cases: live streams, an
/// unknown duration (the panel hasn't reported it yet), an episode shorter
/// than the credits window, the very first instant of playback.
///
/// Panels give no chapter markers, so "skip intro" is a heuristic: [introEnd]
/// is where the intro is assumed to end, measured from the start, and the
/// prompt only shows while the position is before it.
SeriesPrompt seriesPromptFor({
  required bool isSeries,
  required bool isLive,
  required bool hasNextEpisode,
  required Duration position,
  required Duration duration,
  required Duration introEnd,
  Duration creditsWindow = const Duration(seconds: 90),
}) {
  if (!isSeries || isLive) return SeriesPrompt.none;
  // No duration yet = nothing is known about where we are.
  if (duration <= Duration.zero) return SeriesPrompt.none;

  // Credits first: it wins if the windows ever overlap (a very short episode).
  // The duration guard keeps the prompt off clips shorter than the window,
  // where "the last 90 seconds" would be most of the episode.
  if (hasNextEpisode &&
      duration > const Duration(minutes: 2) &&
      position > Duration.zero &&
      (duration - position) <= creditsWindow) {
    return SeriesPrompt.nextEpisode;
  }

  // Never offer to skip past (or nearly to) the end: on anything shorter than
  // the intro mark, "Salta sigla" would seek beyond the episode.
  if (duration <= introEnd + const Duration(seconds: 10)) return SeriesPrompt.none;

  // A couple of seconds of grace so the button doesn't flash at 0:00, and it
  // disappears just before the mark (skipping to where you already are is a
  // no-op that looks broken).
  if (position >= const Duration(seconds: 2) &&
      position < introEnd - const Duration(seconds: 2)) {
    return SeriesPrompt.skipIntro;
  }

  return SeriesPrompt.none;
}
