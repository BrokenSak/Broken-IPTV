import 'package:flutter_test/flutter_test.dart';

import 'package:broken_iptv/core/ui_mode.dart';
import 'package:broken_iptv/data/services/device_mode_service.dart';

/// Focus policies for the D-pad. These are the rules that, when wrong, locked
/// real devices out — both cases below shipped once:
/// - focusability gated on TV mode → fresh install stuck on the device picker
///   (no mode saved yet → nothing focusable → the remote couldn't choose one);
/// - autofocus allowed on phones → the first tile of every grid lit up on its
///   own ("buttons lit that I never clicked").
void main() {
  group('dpadFocusPolicy (can anything take focus?)', () {
    test('any Android build: yes — even before a mode is chosen', () {
      expect(dpadFocusPolicy(isAndroid: true), isTrue);
    });

    test('Windows: never', () {
      expect(dpadFocusPolicy(isAndroid: false), isFalse);
    });
  });

  group('dpadAutofocusPolicy (may a screen pre-light its first element?)', () {
    test('REGRESSION: picker on a TV must autofocus (fresh-install deadlock)', () {
      // The picker is the screen where the mode gets chosen, so it cannot
      // depend on a chosen mode: on a Firestick it must come up focused or the
      // remote has nothing to press OK on.
      expect(dpadAutofocusPolicy(isAndroid: true, savedMode: null, detectedTv: true),
          isTrue);
    });

    test('REGRESSION: picker on a PHONE must NOT autofocus', () {
      // Reported: installing on the phone showed "TV / Telecomando" already
      // highlighted, which reads as pre-selected. Same screen, same missing
      // saved mode — only the detected hardware tells them apart.
      expect(dpadAutofocusPolicy(isAndroid: true, savedMode: null, detectedTv: false),
          isFalse);
    });

    test('TV mode: yes', () {
      expect(
          dpadAutofocusPolicy(
              isAndroid: true, savedMode: DeviceMode.tv, detectedTv: false),
          isTrue,
          reason: 'the saved choice wins over detection: a TV stick that '
              'reports itself as a phone must still work with a remote');
    });

    test('phone (touch) mode: never — nothing may light up on its own', () {
      expect(
          dpadAutofocusPolicy(
              isAndroid: true, savedMode: DeviceMode.touch, detectedTv: true),
          isFalse,
          reason: 'an explicit touch choice beats detection too');
    });

    test('Windows: never', () {
      expect(dpadAutofocusPolicy(isAndroid: false, savedMode: null, detectedTv: true),
          isFalse);
      expect(
          dpadAutofocusPolicy(
              isAndroid: false, savedMode: DeviceMode.tv, detectedTv: true),
          isFalse);
    });
  });
}
