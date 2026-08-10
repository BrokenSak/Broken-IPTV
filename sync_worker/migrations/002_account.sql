-- 69° giro: i dispositivi si raggruppano per "utenza" (la persona: mamma,
-- papà…). È un'etichetta scritta dal proprietario, come `note`, non un
-- segreto: serve solo a leggere l'elenco del pannello per persona invece che
-- come una lista piatta di hash.
--
-- Va eseguita UNA VOLTA (D1 non ha ADD COLUMN IF NOT EXISTS: rilanciarla
-- fallisce con "duplicate column name", ed è innocuo).
--
--   npx wrangler d1 execute broken-iptv-sync --remote --file=./migrations/002_account.sql
ALTER TABLE codes ADD COLUMN account TEXT;
