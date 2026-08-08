-- One row per sync code. `id` is SHA-256 of the code, never the code itself:
-- the secret stays on the devices.
CREATE TABLE IF NOT EXISTS blobs (
  id         TEXT PRIMARY KEY,
  data       TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

-- The allowlist. A code exists here only because the owner added it from the
-- admin panel; everything else the Worker offers is refused with 403. Without
-- it, anyone holding the APK could write to this database (the endpoint is
-- baked into the app, and has to be — a new device must work with the code
-- alone), and the free plan is the scarce resource.
--
-- `id` is the same SHA-256 used by `blobs`: the panel hashes the code the
-- owner types, so the plain code is still never stored.
CREATE TABLE IF NOT EXISTS codes (
  id           TEXT PRIMARY KEY,
  note         TEXT,
  sync_enabled INTEGER NOT NULL DEFAULT 0,
  created_at   INTEGER NOT NULL,
  last_seen    INTEGER
);

-- Migration: every code that already had data keeps working, so switching the
-- allowlist on doesn't cut off the devices that are already syncing.
INSERT OR IGNORE INTO codes (id, note, sync_enabled, created_at)
  SELECT id, 'migrato (aveva già dati)', 1, updated_at FROM blobs;

-- The playlist the owner hands to a device from the panel ("mia madre mi dà il
-- suo codice e gli sistemo tutto"). `data` is a base64 blob the panel
-- encrypted with AES-GCM using the code itself: the server stores bytes it
-- cannot read, so a dump of this table exposes nobody's IPTV subscription.
CREATE TABLE IF NOT EXISTS profiles (
  id         TEXT PRIMARY KEY,
  data       TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);
