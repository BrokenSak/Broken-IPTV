import 'package:flutter_test/flutter_test.dart';

import 'package:broken_iptv/presentation/screens/player/series_prompts.dart';

/// Rules for the floating "Salta sigla" / "Prossimo episodio" shortcuts.
void main() {
  const introEnd = Duration(seconds: 90);
  const episode = Duration(minutes: 42);

  SeriesPrompt promptAt(
    Duration position, {
    bool isSeries = true,
    bool isLive = false,
    bool hasNext = true,
    Duration duration = episode,
  }) {
    return seriesPromptFor(
      isSeries: isSeries,
      isLive: isLive,
      hasNextEpisode: hasNext,
      position: position,
      duration: duration,
      introEnd: introEnd,
    );
  }

  group('salta sigla', () {
    test('shows while inside the intro', () {
      expect(promptAt(const Duration(seconds: 5)), SeriesPrompt.skipIntro);
      expect(promptAt(const Duration(seconds: 60)), SeriesPrompt.skipIntro);
    });

    test('does not flash at the very first instant', () {
      expect(promptAt(Duration.zero), SeriesPrompt.none);
    });

    test('goes away at (and after) the intro mark', () {
      // Skipping to where you already are would look broken.
      expect(promptAt(const Duration(seconds: 89)), SeriesPrompt.none);
      expect(promptAt(const Duration(seconds: 95)), SeriesPrompt.none);
      expect(promptAt(const Duration(minutes: 20)), SeriesPrompt.none);
    });
  });

  group('prossimo episodio', () {
    test('shows over the end credits', () {
      expect(promptAt(episode - const Duration(seconds: 30)), SeriesPrompt.nextEpisode);
      expect(promptAt(episode), SeriesPrompt.nextEpisode);
    });

    test('stays hidden before the credits window', () {
      expect(promptAt(episode - const Duration(minutes: 5)), SeriesPrompt.none);
    });

    test('needs a next episode to exist', () {
      expect(
        promptAt(episode - const Duration(seconds: 30), hasNext: false),
        SeriesPrompt.none,
      );
    });

    test('is not offered on clips shorter than the credits window', () {
      // "The last 90 seconds" of a 1-minute clip is the whole thing.
      expect(
        promptAt(const Duration(seconds: 50), duration: const Duration(minutes: 1)),
        SeriesPrompt.none,
      );
    });

    test('wins over skip-intro if the windows ever overlap', () {
      // A 2:30 episode: 0:05 is both inside the intro and inside the credits
      // window — the credits prompt is the useful one there.
      expect(
        promptAt(const Duration(seconds: 65), duration: const Duration(minutes: 2, seconds: 30)),
        SeriesPrompt.nextEpisode,
      );
    });
  });

  group('never for', () {
    test('movies', () {
      expect(promptAt(const Duration(seconds: 10), isSeries: false), SeriesPrompt.none);
    });

    test('live channels', () {
      expect(promptAt(const Duration(seconds: 10), isLive: true), SeriesPrompt.none);
    });

    test('an unknown duration (panel has not reported it yet)', () {
      expect(promptAt(const Duration(seconds: 10), duration: Duration.zero), SeriesPrompt.none);
    });
  });
}
