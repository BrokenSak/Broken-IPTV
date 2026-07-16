import 'dart:io';

import '../data/services/device_mode_service.dart';

/// Running on a TV/Firestick: the Android APK with the saved device mode set
/// to [DeviceMode.tv]. Drives the D-pad-only affordances — e.g. tiles must not
/// contain small clickable buttons (a remote can only reach them awkwardly),
/// so the favourite heart is hidden there and OK-held on the tile is used
/// instead.
bool isTvMode() =>
    Platform.isAndroid && DeviceModeService().getSaved() == DeviceMode.tv;

/// Running on a phone/tablet: the Android APK in touch mode.
bool isPhoneMode() =>
    Platform.isAndroid && DeviceModeService().getSaved() == DeviceMode.touch;
