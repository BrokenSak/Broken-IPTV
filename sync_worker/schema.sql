-- Schema completo, per un database nuovo. Su quello già in produzione si
-- applicano invece le migrazioni in `migrations/` (una per giro): questo file
-- descrive il punto d'arrivo, non il percorso.

-- Un blob JSON per codice di sincronizzazione (preferiti + "Continua a
-- guardare"). `id` è lo SHA-256 del codice, mai il codice: il segreto resta
-- sui dispositivi.
CREATE TABLE IF NOT EXISTS blobs (
  id         TEXT PRIMARY KEY,
  data       TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

-- L'allowlist. Un codice è qui solo perché il proprietario l'ha aggiunto dal
-- pannello; tutto il resto il Worker lo rifiuta con 403. Senza, chiunque avesse
-- l'APK potrebbe scrivere su questo database (l'indirizzo è dentro l'app, e
-- deve esserci — un dispositivo nuovo funziona col solo codice) e il budget del
-- piano free è la risorsa scarsa.
--
-- `id` è lo stesso SHA-256 usato da `blobs`: il pannello hasha il codice che il
-- proprietario digita, quindi il codice in chiaro non arriva mai qui.
CREATE TABLE IF NOT EXISTS codes (
  id           TEXT PRIMARY KEY,
  note         TEXT,
  sync_enabled INTEGER NOT NULL DEFAULT 0,
  created_at   INTEGER NOT NULL,
  last_seen    INTEGER,
  -- A quale utenza appartiene il dispositivo (NULL = nessuna).
  account_id   TEXT,
  -- 'account' = riga che autorizza la sincronizzazione condivisa di un'utenza,
  -- non un dispositivo. NULL/'device' = un'installazione vera.
  kind         TEXT
);

-- Migrazione: ogni codice che aveva già dei dati continua a funzionare, così
-- accendere l'allowlist non taglia fuori i dispositivi che già sincronizzavano.
INSERT OR IGNORE INTO codes (id, note, sync_enabled, created_at)
  SELECT id, 'migrato (aveva già dati)', 1, updated_at FROM blobs;

-- La **casellina** del dispositivo: `data` è base64 di un blob AES-GCM cifrato
-- col codice del dispositivo, e dice a quale utenza appartiene. La riceve una
-- volta, quando il proprietario lo registra dal pannello.
-- (Prima del 70° giro conteneva direttamente la playlist: l'app legge ancora
-- quel formato, così i dispositivi già configurati non si fermano.)
CREATE TABLE IF NOT EXISTS profiles (
  id         TEXT PRIMARY KEY,
  data       TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

-- Un'utenza = l'abbonamento IPTV vero (nome, indirizzo, utente, password).
-- `id` è pubblico (sta nell'URL che chiama il dispositivo); il **codice**
-- dell'utenza — quello che cifra `data` — non è salvato da nessuna parte: il
-- pannello lo ricalcola con HMAC-SHA256(ADMIN_TOKEN, id). Un dump di questa
-- tabella non apre nessuna playlist; chi ha il token le apre tutte.
CREATE TABLE IF NOT EXISTS accounts (
  id         TEXT PRIMARY KEY,
  name       TEXT NOT NULL,
  -- SHA-256('broken-iptv-sync:' + codice dell'utenza): la riga di `codes` che
  -- autorizza il blob di sincronizzazione condiviso dai suoi dispositivi.
  sync_id    TEXT,
  data       TEXT,
  updated_at INTEGER,
  created_at INTEGER NOT NULL
);
