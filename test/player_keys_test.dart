import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:broken_iptv/presentation/screens/player/player_keys.dart';

/// Rules for keys inside the player. The volume case is a real regression:
/// the player used to swallow the first key press to reveal its controls,
/// which ate the volume key too — the volume only moved from the 2nd press.
void main() {
  _backKeyRules();
  const volumeKeys = [
    LogicalKeyboardKey.audioVolumeUp,
    LogicalKeyboardKey.audioVolumeDown,
    LogicalKeyboardKey.audioVolumeMute,
  ];

  group('volume keys', () {
    test('are always passed to the OS, whatever the player state', () {
      for (final key in volumeKeys) {
        for (final visible in [true, false]) {
          expect(
            playerKeyAction(key: key, isKeyDown: true, controlsVisible: visible),
            PlayerKeyAction.ignore,
            reason: 'volume must never be consumed nor open the menu',
          );
        }
      }
    });
  });

  group('OK', () {
    test('opens the controls when they are hidden', () {
      expect(
        playerKeyAction(
          key: LogicalKeyboardKey.select,
          isKeyDown: true,
          controlsVisible: false,
        ),
        PlayerKeyAction.revealControls,
      );
    });

    test('goes to the focused button once the controls are up (never closes)', () {
      // Closing is Back's job / the inactivity timer's: with the controls open
      // OK must press whatever the remote has selected.
      for (final key in [
        LogicalKeyboardKey.select,
        LogicalKeyboardKey.enter,
        LogicalKeyboardKey.gameButtonA,
      ]) {
        expect(
          playerKeyAction(key: key, isKeyDown: true, controlsVisible: true),
          PlayerKeyAction.pokeAndPass,
        );
      }
    });
  });

  group('other keys', () {
    test('reveal hidden controls without acting', () {
      expect(
        playerKeyAction(
          key: LogicalKeyboardKey.arrowDown,
          isKeyDown: true,
          controlsVisible: false,
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
        ),
        PlayerKeyAction.ignore,
      );
    });
  });

  group('desktop keyboard media controls (Windows)', () {
    test('space toggles play/pause, arrows seek — whatever the controls state', () {
      for (final visible in [true, false]) {
        expect(
          playerKeyAction(
            key: LogicalKeyboardKey.space,
            isKeyDown: true,
            controlsVisible: visible,
            isDesktop: true,
          ),
          PlayerKeyAction.playPause,
        );
        expect(
          playerKeyAction(
            key: LogicalKeyboardKey.arrowRight,
            isKeyDown: true,
            controlsVisible: visible,
            isDesktop: true,
          ),
          PlayerKeyAction.seekForward,
        );
        expect(
          playerKeyAction(
            key: LogicalKeyboardKey.arrowLeft,
            isKeyDown: true,
            controlsVisible: visible,
            isDesktop: true,
          ),
          PlayerKeyAction.seekBackward,
        );
      }
    });

    test('not on live (no pause/seek there)', () {
      expect(
        playerKeyAction(
          key: LogicalKeyboardKey.space,
          isKeyDown: true,
          controlsVisible: false,
          isDesktop: true,
          isLive: true,
        ),
        PlayerKeyAction.revealControls,
      );
      expect(
        playerKeyAction(
          key: LogicalKeyboardKey.arrowRight,
          isKeyDown: true,
          controlsVisible: true,
          isDesktop: true,
          isLive: true,
        ),
        PlayerKeyAction.pokeAndPass,
      );
    });

    test('NOT on TV: arrows stay D-pad navigation, space is not a media key', () {
      // isDesktop defaults to false (TV/phone): arrows must not seek.
      expect(
        playerKeyAction(
          key: LogicalKeyboardKey.arrowRight,
          isKeyDown: true,
          controlsVisible: true,
        ),
        PlayerKeyAction.pokeAndPass,
      );
      expect(
        playerKeyAction(
          key: LogicalKeyboardKey.arrowLeft,
          isKeyDown: true,
          controlsVisible: false,
        ),
        PlayerKeyAction.revealControls,
      );
    });

    test('only key-down acts (holding does not thrash play/pause)', () {
      expect(
        playerKeyAction(
          key: LogicalKeyboardKey.space,
          isKeyDown: false,
          controlsVisible: true,
          isDesktop: true,
        ),
        PlayerKeyAction.ignore,
      );
    });
  });
}

void _backKeyRules() {
  group('Back non è mai roba del player', () {
    // ⚠️ Regressione segnalata sul Firestick: "premendo back durante la
    // riproduzione apre e chiude il player, fa robe strane". Back cadeva nel
    // caso "qualsiasi tasto", quindi a controlli nascosti veniva CONSUMATO per
    // riaprirli invece di uscire; premuto ancora li richiudeva, e tenuto
    // premuto faceva apri/chiudi a raffica sui key-repeat. Back è di PopScope,
    // che sbuccia già un livello per volta: overlay → controlli → uscita.
    for (final key in [
      LogicalKeyboardKey.goBack,
      LogicalKeyboardKey.browserBack,
      LogicalKeyboardKey.escape,
    ]) {
      test('${key.debugName}: ignorato a controlli nascosti', () {
        expect(
          playerKeyAction(key: key, isKeyDown: true, controlsVisible: false),
          PlayerKeyAction.ignore,
        );
      });

      test('${key.debugName}: ignorato a controlli visibili', () {
        expect(
          playerKeyAction(key: key, isKeyDown: true, controlsVisible: true),
          PlayerKeyAction.ignore,
        );
      });

      test('${key.debugName}: ignorato anche su desktop e sul live', () {
        expect(
          playerKeyAction(
              key: key,
              isKeyDown: true,
              controlsVisible: false,
              isDesktop: true,
              isLive: true),
          PlayerKeyAction.ignore,
        );
      });
    }
  });
}
