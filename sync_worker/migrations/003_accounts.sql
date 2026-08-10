-- 70° giro: l'utenza smette di essere un'etichetta e diventa **l'account IPTV
-- vero** (nome, indirizzo, utente, password). I dispositivi si agganciano a
-- un'utenza, e le credenziali stanno in UN solo posto: correggerle una volta
-- le manda a tutti i suoi dispositivi.
--
-- Cosa cambia rispetto al 69° giro (`002_account.sql`, superata):
--   * `codes.account` era il NOME della persona scritto su ogni riga. Ora c'è
--     `codes.account_id`, che punta a una riga di `accounts`. La vecchia
--     colonna resta lì inutilizzata: in D1 rimuovere una colonna è più
--     rischioso che ignorarla.
--   * `profiles.data` non è più la playlist del dispositivo ma la **casellina**
--     (cifrata col codice del dispositivo) che dice a quale utenza appartiene.
--     Le righe vecchie continuano a funzionare: l'app riconosce entrambi i
--     formati.
--
-- Va eseguita UNA VOLTA (D1 non ha ADD COLUMN IF NOT EXISTS: rilanciarla
-- fallisce con "duplicate column name", ed è innocuo).
--
--   npx wrangler d1 execute broken-iptv-sync --remote --file=./migrations/003_accounts.sql

-- Un'utenza. `id` è pubblico (sta nell'URL che chiama il dispositivo); il
-- **codice** dell'utenza — quello che cifra `data` — non è qui e non è da
-- nessuna parte: il pannello lo ricalcola con HMAC-SHA256(ADMIN_TOKEN, id).
-- Quindi un dump di questa tabella non apre nessuna playlist, ma chi ha il
-- token le apre tutte (compromesso accettato).
CREATE TABLE IF NOT EXISTS accounts (
  id         TEXT PRIMARY KEY,
  name       TEXT NOT NULL,
  -- SHA-256('broken-iptv-sync:' + codice dell'utenza): la riga di `codes` che
  -- autorizza il blob di sincronizzazione condiviso dai suoi dispositivi.
  sync_id    TEXT,
  -- base64(AES-GCM col codice dell'utenza) di {host, username, password, name}.
  data       TEXT,
  updated_at INTEGER,
  created_at INTEGER NOT NULL
);

-- A quale utenza appartiene un dispositivo. NULL = nessuna (i dispositivi
-- registrati prima di questo giro, o quelli a sé stanti).
ALTER TABLE codes ADD COLUMN account_id TEXT;

-- 'account' = riga che esiste solo per autorizzare la sincronizzazione
-- condivisa di un'utenza, non è un dispositivo e non va elencata come tale.
-- NULL/'device' = un'installazione vera.
ALTER TABLE codes ADD COLUMN kind TEXT;
