import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:broken_iptv/presentation/screens/player/player_keys.dart';

/// Rules for keys inside the player. The volume case is a real regression:
/// the player used to swallow the first key press to reveal its controls,
/// which ate the volume key too — the volume only moved from the 2nd press.
void main() {
  const volumeKeys = [
    LogicalKeyboardKey.audioVolumeUp,
    LogicalKeyboardKey.audioVolumeDown,
    LogicalKeyboardKey.audioVolumeMute,
  ];

  group('volume keys', () {
    test('are always passed to the OS, whatever the player state', () {
      for (final key in volumeKeys) {
        for (final visible in [true, false]) {
          for (final rootFocus in [true, false]) {
            expect(
              playerKeyAction(
                key: key,
                isKeyDown: true,
                controlsVisible: visible,
                rootHasFocus: rootFocus,
              ),
              PlayerKeyAction.ignore,
              reason: 'volume must never be consumed nor open the menu',
            );
          }
        }
      }
    });
  });

  group('OK / tap toggle', () {
    test('OK opens the controls when hidden', () {
      expect(
        playerKeyAction(
          key: LogicalKeyboardKey.select,
          isKeyDown: true,
          controlsVisible: false,
          rootHasFocus: true,
        ),
        PlayerKeyAction.revealControls,
      );
    });

    test('OK closes the controls when they are open and nothing is focused', () {
      expect(
        playerKeyAction(
          key: LogicalKeyboardKey.select,
          isKeyDown: true,
          controlsVisible: true,
          rootHasFocus: true,
        ),
        PlayerKeyAction.toggleControls,
      );
    });

    test('enter and gamepad A behave like OK', () {
      for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.gameButtonA]) {
        expect(
          playerKeyAction(
            key: key,
            isKeyDown: true,
            controlsVisible: true,
            rootHasFocus: true,
          ),
          PlayerKeyAction.toggleControls,
        );
      }
    });

    test('OK on a focused control button is left to that button', () {
      expect(
        playerKeyAction(
          key: LogicalKeyboardKey.select,
          isKeyDown: true,
          controlsVisible: true,
          rootHasFocus: false,
        ),
        PlayerKeyAction.pokeAndPass,
      );
    });
  });

  group('other keys', () {
    test('reveal hidden controls without acting', () {
      expect(
        playerKeyAction(
          key: LogicalKeyboardKey.arrowDown,
          isKeyDown: true,
          controlsVisible: false,
          rootHasFocus: true,
        ),
        PlayerKeyAction.revealControls,
      );
    });

    test('keep the controls awake and pass through when visible', () {
      expect(
        playerKeyAction(
          key: LogicalKeyboardKey.arrowDown,
          isKeyDown: true,
          controlsVisible: true,
          rootHasFocus: true,
        ),
        PlayerKeyAction.pokeAndPass,
      );
    });

    test('key-up events are never acted on (only key-down drives the UI)', () {
      expect(
        playerKeyAction(
          key: LogicalKeyboardKey.select,
          isKeyDown: false,
          controlsVisible: true,
          rootHasFocus: true,
        ),
        PlayerKeyAction.ignore,
      );
    });
  });
}
