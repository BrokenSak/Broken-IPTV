# Backend di sincronizzazione (Cloudflare Worker + D1)

Serve a tenere allineati **preferiti** e **"Continua a guardare"** tra telefono,
Firestick e PC. Non sincronizza playlist né password.

È volutamente minuscolo: un blob JSON per *codice di sync*, nessun account,
nessun login Google (deve funzionare sul Firestick). Il **codice è il segreto**:
sul database finisce solo il suo SHA-256, quindi nemmeno leggendo la tabella si
risale ai dati di qualcuno.

Sta comodamente nel **piano gratuito**: l'app scrive solo quando qualcosa è
davvero cambiato (confronto per impronta del contenuto), e solo quando va in
background o alla chiusura della finestra.

## Deploy (una volta sola, ~5 minuti)

Serve un account Cloudflare (gratuito) e Node.js installato.

1. **Login**

   ```bash
   npx wrangler login
   ```

2. **Crea il database D1** — il comando stampa un `database_id`:

   ```bash
   npx wrangler d1 create broken-iptv-sync
   ```

3. **Copia `wrangler.toml.example` in `wrangler.toml`** e incolla quell'id al
   posto di `PASTE_DATABASE_ID_HERE`. Il file `wrangler.toml` è gitignorato di
   proposito: l'id è legato al tuo account Cloudflare e non va sul repo pubblico.

4. **Crea la tabella** (in remoto, non solo in locale):

   ```bash
   npx wrangler d1 execute broken-iptv-sync --remote --file=./schema.sql
   ```

5. **Pubblica**:

   ```bash
   npx wrangler deploy
   ```

   Alla fine stampa l'indirizzo, del tipo
   `https://broken-iptv-sync.<tuo-sottodominio>.workers.dev`.

6. **Verifica** che risponda:

   ```bash
   curl https://broken-iptv-sync.<tuo-sottodominio>.workers.dev/health
   ```

   Deve rispondere `{"ok":true}`.

7. Nell'app: **Impostazioni → Sincronizzazione**, incolla quell'indirizzo in
   "Indirizzo del servizio", premi **Genera codice**, poi **Salva e sincronizza**.
   Sugli altri dispositivi metti lo **stesso indirizzo e lo stesso codice**.

## Il pannello (`/admin`)

Da qui il proprietario **abilita i dispositivi** e **configura le playlist**.
Serve un token, che è un *secret* del Worker e non sta nel repo:

```bash
npx wrangler secret put ADMIN_TOKEN
```

Poi si apre `https://<il-tuo-worker>.workers.dev/admin` e lo si incolla. Per
provare in locale, `sync_worker/.dev.vars` (gitignorato) con
`ADMIN_TOKEN = "..."`, e `npx wrangler dev`.

Nel pannello si scrive il **codice che il dispositivo mostra** — te lo legge la
persona a cui stai sistemando l'app — gli si dà un nome, si accende o spegne la
sincronizzazione e gli si può inviare la playlist. La playlist viene **cifrata
nel browser con il codice stesso** (AES-GCM, chiave = SHA-256 del codice): sul
database finiscono byte illeggibili, e solo quel dispositivo può aprirli.
Per la stessa ragione la playlist si può inviare **solo avendo il codice**:
dall'elenco, che contiene solo hash, non si può.

## Allowlist (perché esiste)

L'indirizzo del servizio è dentro l'app, e l'app è pubblica: senza un filtro
chiunque potrebbe scrivere qui e bruciare il piano gratuito. Quindi **ogni**
percorso del dispositivo è chiuso a chiave:

- codice non presente nella tabella `codes` → `403 unknown_code`;
- codice presente ma con la sincronizzazione spenta → `403 sync_disabled`
  (la playlist invece si legge lo stesso: quella non costa scritture).

L'app distingue i due casi e mostra la frase giusta, invece di "controlla
codice e indirizzo".

Applicando `schema.sql` su un database già in uso, i codici che **avevano già
dati** vengono abilitati automaticamente: chi sincronizzava prima continua.

## API

| Metodo | Percorso              | Risposta                                     |
| ------ | --------------------- | -------------------------------------------- |
| GET    | `/v1/blob/<code>`     | il blob JSON, oppure `404` se non c'è nulla   |
| PUT    | `/v1/blob/<code>`     | `{"ok":true}` (sostituisce il blob)           |
| DELETE | `/v1/blob/<code>`     | `{"ok":true}` (dimentica quel codice)         |
| GET    | `/v1/profile/<code>`  | `{"data":"<cifrato>","updatedAt":…}` o `404`  |
| GET    | `/admin`              | il pannello (HTML)                            |
| GET    | `/health`             | `{"ok":true}`                                 |

Dietro al token (`Authorization: Bearer <ADMIN_TOKEN>`):

| Metodo | Percorso            | Cosa fa                                        |
| ------ | ------------------- | ---------------------------------------------- |
| GET    | `/v1/admin/codes`   | elenco dispositivi (hash, nome, stato)          |
| POST   | `/v1/admin/codes`   | aggiunge o aggiorna `{code, note, syncEnabled}` |
| POST   | `/v1/admin/profile` | salva `{code, data}` (playlist già cifrata)     |
| POST   | `/v1/admin/forget`  | cancella codice, blob e playlist                |

Il codice è di 12 caratteri `A-Z0-9`; i trattini con cui l'app lo mostra
(`ABCD-EFGH-JKLM`) vengono ignorati. Blob oltre 1 MB → `413`.

## Note

- La fusione dei dati avviene **nell'app** (stessa funzione pura su ogni
  dispositivo, vince la modifica più recente, le rimozioni viaggiano come
  tombstone): il Worker non guarda dentro al payload.
- Non c'è rate limiting: il servizio è per uso personale e l'indirizzo non è
  pubblicizzato. Se dovesse servire, Cloudflare offre le Rate Limiting Rules
  sul dominio del Worker.
- Per azzerare tutto: `npx wrangler d1 execute broken-iptv-sync --remote
  --command "DELETE FROM blobs"`.
