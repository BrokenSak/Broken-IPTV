-- One row per sync code. `id` is SHA-256 of the code, never the code itself:
-- the secret stays on the devices.
CREATE TABLE IF NOT EXISTS blobs (
  id         TEXT PRIMARY KEY,
  data       TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);
