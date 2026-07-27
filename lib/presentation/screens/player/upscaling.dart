import '../../../state/player_settings_providers.dart';

/// The mpv properties behind each [VideoUpscaling] level.
///
/// Pure (no media_kit) so the mapping is testable. Every level defines the
/// SAME set of keys: switching levels mid-playback always overrides what the
/// previous level set, with no leftovers.
///
/// Two mechanisms, on purpose:
/// - `scale`/`cscale` are the GPU upscalers. They only matter when the video
///   is actually being enlarged (an HD stream shown ~1:1 bypasses them) and
///   depend on the renderer honouring shader options — cheap, so kept, but
///   NOT what makes the difference visible.
/// - `vf` is a lavfi filter chain applied in the DECODE path: it works on
///   every platform and renderer, on every stream (HD included), and is the
///   visible part — unsharp masking (and, at max, light denoise first, so the
///   sharpening doesn't amplify compression noise). This replaced the vo_gpu
///   `sharpen` option of the first attempt, which the bundled libmpv could
///   silently not support ("non vedo differenza", 49° giro).
///
/// `off` restores exactly media_kit's own defaults (it sets scale/dscale to
/// bilinear at init, for performance) and clears the filter chain.
///
/// `hwdec` is part of the contract because of the 50°-giro black screen: the
/// lavfi filters are SOFTWARE filters, but media_kit decodes to HARDWARE
/// frames (`auto` on desktop, `auto-safe` → mediacodec direct on Android)
/// that unsharp/hqdn3d cannot touch — the filter chain failed at runtime and
/// live channels went black. With a level active the decoder switches to
/// `auto-copy` (still hardware decoding, but frames are copied to system
/// memory — the same mode mpv-android ships as its default), which every
/// software filter accepts. `off` puts the platform default back.
///
/// `deinterlace=auto` only kicks in on content flagged interlaced; if the
/// bundled libmpv is too old to accept 'auto' the caller ignores the error
/// (per-property try/catch), leaving deinterlacing off rather than forcing it
/// on progressive video.
Map<String, String> upscalingMpvProperties(
  VideoUpscaling level, {
  required bool isAndroid,
}) {
  switch (level) {
    case VideoUpscaling.off:
      return {
        // media_kit's own defaults: 'auto-safe' on Android, 'auto' elsewhere.
        'hwdec': isAndroid ? 'auto-safe' : 'auto',
        'scale': 'bilinear',
        'cscale': 'bilinear',
        'vf': '',
        'deinterlace': 'no',
      };
    case VideoUpscaling.enhanced:
      return const {
        'hwdec': 'auto-copy',
        'scale': 'spline36',
        'cscale': 'spline36',
        // Moderate unsharp mask, luma only (sharpening chroma adds fringes).
        'vf': 'lavfi=[unsharp=5:5:0.5:5:5:0.0]',
        'deinterlace': 'auto',
      };
    case VideoUpscaling.max:
      return const {
        'hwdec': 'auto-copy',
        'scale': 'ewa_lanczossharp',
        'cscale': 'ewa_lanczossharp',
        // Light spatial denoise first (IPTV streams are heavily compressed;
        // sharpening raw would amplify the block noise), then a strong
        // unsharp mask. CPU-side: fine on PC, heavy on a stick — documented.
        'vf': 'lavfi=[hqdn3d=1.5:1.5:4:4,unsharp=5:5:0.9:5:5:0.0]',
        'deinterlace': 'auto',
      };
  }
}
