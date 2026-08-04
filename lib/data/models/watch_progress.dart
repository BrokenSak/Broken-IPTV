enum WatchKind { vod, series }

/// Below this a position is not a resume point, it's noise: the first seconds
/// of playback, or a title opened and closed straight away.
///
/// ⚠️ It exists because a low position used to be written *over* a real one.
/// Open a film you were 1h20m into, back out before it starts (a slow panel on
/// the Firestick makes that easy), and dispose()'s forced save stamped
/// `positionMs ≈ 0` on top: the film then "always restarted from the
/// beginning". The user's own data had five such entries — one of them the
/// newest episode of a series, which took the whole series out of "Continua a
/// guardare". See [WatchProgress.resumable] and `_maybeSaveProgress`.
const kMinResumeMs = 10000;

/// Whether a progress write at [positionMs] should go through, given what is
/// already stored for that item ([existingPositionMs], null when nothing is).
///
/// Pure so the rule can be tested — it decides whether the user keeps their
/// place, and getting it wrong looks exactly like "non salva niente".
///
/// A position at or above [kMinResumeMs] always wins: it is real progress,
/// including a deliberate rewind. Below it, the write only lands when it isn't
/// destroying something better — which lets "you're on the next episode now"
/// be recorded while stopping a title that was opened and abandoned in the
/// first seconds from erasing where you actually were.
bool shouldWriteProgress({required int positionMs, required int? existingPositionMs}) {
  if (positionMs >= kMinResumeMs) return true;
  return existingPositionMs == null || existingPositionMs <= positionMs;
}

/// A resume point for a movie or a series episode. Series progress is stored
/// per episode (so each episode gets its own bar); "Continua a guardare"
/// groups by series and shows the most recently watched episode.
class WatchProgress {
  const WatchProgress({
    required this.kind,
    required this.vodId,
    required this.seriesId,
    required this.episodeId,
    required this.episodeLabel,
    required this.name,
    required this.imageUrl,
    required this.url,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAt,
  });

  final WatchKind kind;
  final String? vodId;
  final String? seriesId;
  final String? episodeId;
  final String? episodeLabel;
  final String name;
  final String? imageUrl;
  final String url;
  final int positionMs;
  final int durationMs;
  final int updatedAt;

  static String vodKey(String id) => 'vod:$id';
  static String seriesKey(String seriesId, String episodeId) => 'series:$seriesId:$episodeId';

  String get key => kind == WatchKind.vod
      ? vodKey(vodId!)
      : seriesKey(seriesId!, episodeId!);

  double get fraction {
    if (durationMs <= 0) return 0;
    return (positionMs / durationMs).clamp(0.0, 1.0);
  }

  bool get finished => fraction >= 0.95;
  bool get started => positionMs > 5000 && !finished;

  /// Whether this entry is worth *seeking* to. Anything else must be opened
  /// from the start — and, crucially, must not be advertised as "Riprendi".
  ///
  /// A finished entry is the trap: passing its position to the player asked it
  /// to seek past the end, the player quietly declined, and playback began at
  /// zero. That is the "premo Riprendi e ricomincia da capo" report.
  bool get resumable => !finished && positionMs >= kMinResumeMs;

  Map<String, dynamic> toMap() => {
        'kind': kind.name,
        'vodId': vodId,
        'seriesId': seriesId,
        'episodeId': episodeId,
        'episodeLabel': episodeLabel,
        'name': name,
        'imageUrl': imageUrl,
        'url': url,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'updatedAt': updatedAt,
      };

  factory WatchProgress.fromMap(Map<dynamic, dynamic> m) => WatchProgress(
        kind: WatchKind.values.firstWhere((k) => k.name == m['kind']),
        vodId: m['vodId'] as String?,
        seriesId: m['seriesId'] as String?,
        episodeId: m['episodeId'] as String?,
        episodeLabel: m['episodeLabel'] as String?,
        name: m['name'] as String? ?? '',
        imageUrl: m['imageUrl'] as String?,
        url: m['url'] as String? ?? '',
        positionMs: (m['positionMs'] as num?)?.toInt() ?? 0,
        durationMs: (m['durationMs'] as num?)?.toInt() ?? 0,
        updatedAt: (m['updatedAt'] as num?)?.toInt() ?? 0,
      );
}
