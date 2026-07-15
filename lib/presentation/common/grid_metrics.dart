import 'dart:io';

import 'package:flutter/widgets.dart';

/// Catalog grid sizing. Android (phone/TV — the APK) uses denser grids —
/// smaller tiles, tighter gaps, a narrower sidebar — so more items fit on
/// screen; on desktop Windows the pointer wants bigger targets, so tiles stay
/// larger. Keep every catalog grid on these values so density stays uniform.
abstract final class GridMetrics {
  static final bool _dense = Platform.isAndroid;

  /// Live channel tiles (logo + name + EPG line).
  static double get channelExtent => _dense ? 150 : 220;
  static double get channelRatio => _dense ? 0.82 : 0.85;

  /// VOD/series poster tiles.
  static double get posterExtent => _dense ? 112 : 160;
  static double get posterRatio => _dense ? 0.58 : 0.62;

  /// "Continua a guardare" tiles (poster + progress bar + extra text lines).
  static double get continueVodRatio => _dense ? 0.52 : 0.55;
  static double get continueSeriesRatio => _dense ? 0.47 : 0.5;

  static double get spacing => _dense ? 10 : 16;
  static double get gridPadding => _dense ? 12 : 20;

  /// Left category sidebar width. On Android: 230 in landscape (190 made the
  /// category names unreadable), but only 160 in portrait, where the screen
  /// is so narrow that a wide sidebar would leave no room for the grid.
  /// Reads MediaQuery, so the sidebar resizes with the device rotation.
  static double sidebarWidth(BuildContext context) {
    if (!_dense) return 250;
    final portrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;
    return portrait ? 160 : 230;
  }
}
