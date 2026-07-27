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

  test('off restores the media_kit defaults and clears the filter chain', () {
    // media_kit itself sets scale/dscale=bilinear at init: off must put back
    // exactly that baseline, and drop every lavfi filter.
    expect(upscalingMpvProperties(VideoUpscaling.off), {
      'scale': 'bilinear',
      'cscale': 'bilinear',
      'vf': '',
      'deinterlace': 'no',
    });
  });

  test('enhanced and max sharpen via the lavfi DECODE chain, not vo_gpu only',
      () {
    // Regression ("non vedo differenza"): the first version relied on the
    // vo_gpu `sharpen` option, which the bundled libmpv can silently ignore,
    // and on scalers that do nothing when the video isn't being enlarged.
    // The visible part must be a `vf` lavfi chain: renderer-independent and
    // active on every stream.
    final enhanced = upscalingMpvProperties(VideoUpscaling.enhanced);
    expect(enhanced['scale'], 'spline36');
    expect(enhanced['cscale'], 'spline36');
    expect(enhanced['vf'], contains('unsharp'));
    expect(enhanced['deinterlace'], 'auto',
        reason: 'SD live channels are often interlaced');

    final max = upscalingMpvProperties(VideoUpscaling.max);
    expect(max['scale'], 'ewa_lanczossharp');
    expect(max['cscale'], 'ewa_lanczossharp');
    expect(max['vf'], contains('unsharp'));
    expect(max['vf'], contains('hqdn3d'),
        reason: 'max denoises before sharpening (compressed IPTV streams)');
    // Max must sharpen harder than enhanced (that's the visible ladder).
    double amount(String vf) =>
        double.parse(RegExp(r'unsharp=\d+:\d+:([\d.]+)').firstMatch(vf)!.group(1)!);
    expect(amount(max['vf']!), greaterThan(amount(enhanced['vf']!)));
  });

  test('labels: settings names and the compact player-bar forms', () {
    expect(VideoUpscaling.off.label, 'Off');
    expect(VideoUpscaling.enhanced.label, 'Migliorato');
    expect(VideoUpscaling.max.label, 'Massimo');
    expect(VideoUpscaling.enhanced.shortLabel, 'HQ');
    expect(VideoUpscaling.max.shortLabel, 'Max');
  });
}
