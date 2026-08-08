import 'package:flutter_test/flutter_test.dart';

import 'package:broken_iptv/core/fullscreen.dart';

/// Quando la freccia del mouse deve sparire dal video (richiesta utente: "su
/// windows a full screen deve sparire la freccia del mouse").
///
/// La regola è pura perché `PlayerScreen` non si può pompare sull'host (libmpv
/// nativo in initState): il widget si limita a passarla a un `MouseRegion`.
void main() {
  group('freccia del mouse sul video', () {
    test('sparisce su Windows a schermo intero, a controlli chiusi', () {
      expect(
        hidePointerOverVideo(
          isDesktop: true,
          isFullscreen: true,
          uiVisible: false,
        ),
        isTrue,
      );
    });

    test('torna appena si apre qualcosa (controlli o overlay)', () {
      // Altrimenti ci sarebbero pulsanti da cliccare senza vedere il puntatore.
      expect(
        hidePointerOverVideo(
          isDesktop: true,
          isFullscreen: true,
          uiVisible: true,
        ),
        isFalse,
      );
    });

    test('in finestra resta sempre visibile', () {
      // Fuori dal fullscreen la finestra ha bordi, barra e resto del desktop:
      // nascondere il puntatore lì renderebbe l'app inguidabile col mouse.
      for (final ui in [true, false]) {
        expect(
          hidePointerOverVideo(
            isDesktop: true,
            isFullscreen: false,
            uiVisible: ui,
          ),
          isFalse,
        );
      }
    });

    test('su Android non si nasconde nulla (non c\'è puntatore)', () {
      // Android è sempre fullscreen: senza il gate desktop la regola sarebbe
      // sempre vera anche dove non ha senso.
      expect(
        hidePointerOverVideo(
          isDesktop: false,
          isFullscreen: true,
          uiVisible: false,
        ),
        isFalse,
      );
    });
  });
}
