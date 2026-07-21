/// Whether to float the "Prossimo episodio" shortcut over an episode.
///
/// Pure (and so testable) because it is all edge cases: live streams, an
/// unknown duration (the panel hasn't reported it yet), an episode shorter
/// than the credits window, the very first instant of playback.
///
/// NB: the automatic "Salta sigla" was removed on purpose — panels give no
/// chapter markers and intros shift position/length per episode, so any
/// guess (fixed time, remembered point) landed in the wrong place. Only the
/// *end* is reliable: it's derived from the known duration.
bool shouldShowNextEpisode({
  required bool isSeries,
  required bool isLive,
  required bool hasNextEpisode,
  required Duration position,
  required Duration duration,
  Duration creditsWindow = const Duration(seconds: 90),
}) {
  if (!isSeries || isLive || !hasNextEpisode) return false;
  // No duration yet = nothing is known about where we are.
  if (duration <= Duration.zero) return false;
  // The duration guard keeps the prompt off clips shorter than the window,
  // where "the last 90 seconds" would be most of the episode.
  if (duration <= const Duration(minutes: 2)) return false;
  if (position <= Duration.zero) return false;
  return (duration - position) <= creditsWindow;
}
