/// Whether a video is open in the player right now.
///
/// The cross-device sync uses it as a veto: backgrounding the app mid-episode
/// (or the phone locking) must not start an upload that competes with the
/// stream for the connection. The pending changes go up on the next trigger.
///
/// A plain flag rather than a provider: the player sets it from initState /
/// dispose, and nothing needs to rebuild when it changes.
class PlaybackActivity {
  static bool active = false;
}
