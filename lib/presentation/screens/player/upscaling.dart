import '../../../state/player_settings_providers.dart';

/// The mpv render properties behind each [VideoUpscaling] level.
///
/// Pure (no media_kit) so the mapping is testable. Every level defines the
/// SAME set of keys: switching levels mid-playback always overrides what the
/// previous level set, with no leftovers.
///
/// - `off` is mpv's own vo=gpu defaults — i.e. exactly how the app rendered
///   before this feature existed.
/// - `enhanced` uses spline36 (a good quality/cost middle ground, chosen to
///   stay watchable on a Firestick GPU) plus a mild unsharp mask, and
///   deinterlacing for the flagged-interlaced SD live channels.
/// - `max` uses ewa_lanczossharp, mpv's high-quality polar scaler: great on a
///   PC GPU, may drop frames on a weak stick — that's why it's a choice.
///
/// `deinterlace=auto` only kicks in on content flagged interlaced; if the
/// bundled libmpv is too old to accept 'auto' the caller ignores the error
/// (per-property try/catch), leaving deinterlacing off rather than forcing it
/// on progressive video.
Map<String, String> upscalingMpvProperties(VideoUpscaling level) {
  switch (level) {
    case VideoUpscaling.off:
      return const {
        'scale': 'bilinear',
        'cscale': 'bilinear',
        'sharpen': '0',
        'deinterlace': 'no',
      };
    case VideoUpscaling.enhanced:
      return const {
        'scale': 'spline36',
        'cscale': 'spline36',
        'sharpen': '0.2',
        'deinterlace': 'auto',
      };
    case VideoUpscaling.max:
      return const {
        'scale': 'ewa_lanczossharp',
        'cscale': 'ewa_lanczossharp',
        'sharpen': '0.3',
        'deinterlace': 'auto',
      };
  }
}
