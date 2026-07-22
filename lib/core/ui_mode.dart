import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/services/device_mode_service.dart';

/// Test hook: pretend the app runs on Android with this saved device mode,
/// so widget tests (which run on the dev host, where Platform says Windows)
/// can drive the REAL screens as a TV or a phone. Null = real platform.
@visibleForTesting
DeviceMode? debugDeviceModeOverride;

DeviceMode? _savedMode() => debugDeviceModeOverride ?? DeviceModeService().getSaved();

bool get _isAndroidLike => debugDeviceModeOverride != null || Platform.isAndroid;

/// Running on a TV/Firestick: the Android APK with the saved device mode set
/// to [DeviceMode.tv]. Drives TV-only affordances (favourite heart as a badge,
/// focus landing on the player's main control, TV text fields).
bool isTvMode() => _isAndroidLike && _savedMode() == DeviceMode.tv;

/// Running on a phone/tablet: the Android APK in touch mode.
bool isPhoneMode() => _isAndroidLike && _savedMode() == DeviceMode.touch;

/// Whether TvFocusable nodes can take focus at all.
///
/// Any Android build — NOT just TV mode. Gating this on the *saved* mode
/// locked fresh installs out: the device picker shows before a mode exists,
/// `isTvMode()` was false, nothing was focusable, and a remote could not even
/// pick "TV" (the choice needed the very focus it would have enabled). It also
/// left a TV stuck in touch mode with a dead remote and no way to reach the
/// settings that fix it. Focusable-but-unfocused nodes are invisible on a
/// phone: nothing autofocuses there (see below) and taps never focus them.
bool dpadFocusEnabled() => dpadFocusPolicy(isAndroid: _isAndroidLike);

/// Whether `autofocus` requests should be honoured, pre-lighting the first
/// element of a screen. TV mode, plus the first launch **before a mode
/// exists** *on hardware the OS reports as a TV* — that is the device picker
/// on a Firestick, which must come up with a focused card or a remote has
/// nothing to press OK on. Never in touch mode, and never on a phone's picker:
/// an element lighting up on its own there reads as already selected (reported
/// twice — the second time about the picker itself).
bool dpadAutofocusEnabled() => dpadAutofocusPolicy(
      isAndroid: _isAndroidLike,
      savedMode: _savedMode(),
      detectedTv: DeviceModeService.isTvDevice,
    );

/// Pure policy behind [dpadFocusEnabled], separated so tests can exercise it
/// on a host where Platform.isAndroid is false.
bool dpadFocusPolicy({required bool isAndroid}) => isAndroid;

/// Pure policy behind [dpadAutofocusEnabled].
///
/// Two regressions live here, pulling in opposite directions:
/// - `savedMode == null` (fresh install, picker on screen) on a **TV** MUST
///   autofocus, or the remote has nothing to press OK on;
/// - the same case on a **phone** must NOT, or the "TV / Telecomando" card
///   comes up highlighted and looks pre-selected.
/// [detectedTv] is what separates them — the OS's own answer, not a guess.
bool dpadAutofocusPolicy({
  required bool isAndroid,
  required DeviceMode? savedMode,
  required bool detectedTv,
}) =>
    isAndroid && (savedMode == DeviceMode.tv || (savedMode == null && detectedTv));

/// Whether the **persistent focus ring** should be painted on a focused
/// element. Only where a remote drives the UI — TV mode, or a fresh install
/// before a mode is chosen (the device picker, navigated by remote).
///
/// NOT on a phone (touch): there the feedback is the touch itself (a momentary
/// press highlight), and a stuck ring on an element nobody selected reads as a
/// bug. NOT on Windows: the mouse uses hover/click. In both, only the
/// *selected* item (e.g. the current category) stays highlighted — never a
/// stray focus. This is the highlight-mode gate a normal Material app applies
/// automatically; the custom ring bypassed it, hence the phone regression.
bool dpadHighlightVisible() => dpadAutofocusPolicy(
      isAndroid: _isAndroidLike,
      savedMode: _savedMode(),
      detectedTv: DeviceModeService.isTvDevice,
    );
