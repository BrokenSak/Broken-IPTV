/// Formats a [Duration] as `h:mm:ss` (or `m:ss` under an hour). Shared by the
/// film/series detail screens and the player, which all showed the same clock.
String formatHms(Duration d) {
  final h = d.inHours;
  final m = (d.inMinutes % 60).toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}
