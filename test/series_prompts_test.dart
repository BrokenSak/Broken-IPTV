import 'package:flutter_test/flutter_test.dart';

import 'package:broken_iptv/presentation/screens/player/series_prompts.dart';

/// Rules for the floating "Prossimo episodio" shortcut. (The automatic
/// "Salta sigla" was removed — intros shift per episode, so it always guessed
/// wrong; only the end is reliable, from the known duration.)
void main() {
  const episode = Duration(minutes: 42);

  bool nextAt(
    Duration position, {
    bool isSeries = true,
    bool isLive = false,
    bool hasNext = true,
    Duration duration = episode,
  }) {
    return shouldShowNextEpisode(
      isSeries: isSeries,
      isLive: isLive,
      hasNextEpisode: hasNext,
      position: position,
      duration: duration,
    );
  }

  test('shows over the end credits', () {
    expect(nextAt(episode - const Duration(seconds: 30)), isTrue);
    expect(nextAt(episode), isTrue);
  });

  test('stays hidden before the credits window', () {
    expect(nextAt(episode - const Duration(minutes: 5)), isFalse);
  });

  test('needs a next episode to exist', () {
    expect(nextAt(episode - const Duration(seconds: 30), hasNext: false), isFalse);
  });

  test('not offered on clips shorter than the credits window', () {
    // "The last 90 seconds" of a 1-minute clip is the whole thing.
    expect(nextAt(const Duration(seconds: 50), duration: const Duration(minutes: 1)), isFalse);
  });

  test('never for movies, live, or an unknown duration', () {
    expect(nextAt(episode - const Duration(seconds: 30), isSeries: false), isFalse);
    expect(nextAt(const Duration(seconds: 10), isLive: true), isFalse);
    expect(nextAt(const Duration(seconds: 10), duration: Duration.zero), isFalse);
  });
}
