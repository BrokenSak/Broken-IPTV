import 'package:flutter_test/flutter_test.dart';

import 'package:broken_iptv/presentation/screens/player/upscaling.dart';
import 'package:broken_iptv/state/player_settings_providers.dart';

/// The upscaling → mpv property mapping is pure on purpose: the visual result
/// needs eyes on real hardware, but the contract that makes level switching
/// safe is testable here.
void main() {
  test('every level defines the same property keys', () {
    // Switching levels mid-playback overrides by re-setting the same keys: a
    // level that forgot one would leave the previous level's value behind.
    final keySets = [
      for (final level in VideoUpscaling.values)
        upscalingMpvProperties(level).keys.toSet(),
    ];
    for (final keys in keySets.skip(1)) {
      expect(keys, keySets.first);
    }
  });

  test('off is exactly the mpv vo=gpu defaults (pre-feature rendering)', () {
    expect(upscalingMpvProperties(VideoUpscaling.off), {
      'scale': 'bilinear',
      'cscale': 'bilinear',
      'sharpen': '0',
      'deinterlace': 'no',
    });
  });

  test('enhanced and max use progressively better scalers + sharpening', () {
    final enhanced = upscalingMpvProperties(VideoUpscaling.enhanced);
    expect(enhanced['scale'], 'spline36');
    expect(enhanced['cscale'], 'spline36');
    expect(double.parse(enhanced['sharpen']!), greaterThan(0));
    expect(enhanced['deinterlace'], 'auto',
        reason: 'SD live channels are often interlaced');

    final max = upscalingMpvProperties(VideoUpscaling.max);
    expect(max['scale'], 'ewa_lanczossharp');
    expect(max['cscale'], 'ewa_lanczossharp');
    expect(double.parse(max['sharpen']!), greaterThan(0));
    expect(max['deinterlace'], 'auto');
  });

  test('labels: settings names and the compact player-bar forms', () {
    expect(VideoUpscaling.off.label, 'Off');
    expect(VideoUpscaling.enhanced.label, 'Migliorato');
    expect(VideoUpscaling.max.label, 'Massimo');
    expect(VideoUpscaling.enhanced.shortLabel, 'HQ');
    expect(VideoUpscaling.max.shortLabel, 'Max');
  });
}
