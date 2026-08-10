# Backend di sincronizzazione (Cloudflare Worker + D1)

Fa due cose. Tiene allineati **preferiti** e **"Continua a guardare"** tra
telefono, Firestick e PC — e permette al proprietario di **configurare la
playlist di qualcun altro a distanza**, dal pannello `/admin`. I dispositivi non
si scambiano playlist né password fra loro: quella strada è a senso unico, dal
proprietario verso un dispositivo.

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

Il pannello è organizzato per **utenze**. Un'utenza è un abbonamento IPTV vero
(nome, indirizzo, utente, password) e i dispositivi si agganciano a lei: le
credenziali stanno in **un solo posto**, quindi correggerle una volta le manda a
tutti i suoi dispositivi, senza toccarli e senza sapere i loro codici.
C'è anche **Cambia indirizzo**, che riscrive il dominio su *tutte* le utenze in
un colpo (utente e password di ognuna restano quelli che sono): serve quando è
il pannello IPTV a cambiare indirizzo.

Il **codice che il dispositivo mostra** — te lo legge la persona a cui stai
sistemando l'app — serve **una volta sola**, per agganciarlo a un'utenza:
"Aggiungi dispositivo" scrive nel suo slot una **casellina** cifrata con quel
codice, che dice a quale utenza appartiene. Da lì in poi il dispositivo si
arrangia. Rinominare, rimuovere o spegnere qualcosa si fa dall'elenco, senza
codice; **spostare** un dispositivo su un'altra utenza no: quello riscrive la
casellina, e la casellina si cifra solo col codice.

### Chi può leggere cosa

La playlist di un'utenza è cifrata (AES-GCM) con il **codice dell'utenza**, che
non è salvato da nessuna parte: il pannello lo ricalcola nel browser con
**HMAC-SHA256(ADMIN_TOKEN, id dell'utenza)**. Quindi un dump del database non
apre niente — ma **chi ha il token apre tutte le playlist**. È un compromesso
voluto: è esattamente ciò che permette di correggere una password una volta e
vederla arrivare su dispositivi i cui codici non ha più nessuno. (Ed è anche il
motivo per cui il pannello può rimostrarti le credenziali quando le modifichi.)

⚠️ **Non cambiare `ADMIN_TOKEN` a cuor leggero**: token nuovo = codici delle
utenze nuovi = le caselline già consegnate non aprono più niente, e per
rifarle serve di nuovo il codice di ogni dispositivo.

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
| GET    | `/v1/profile/<code>`  | la **casellina** del dispositivo, o `404`      |
| GET    | `/v1/account/<id>`    | la playlist dell'utenza, o `404`              |
| GET    | `/admin`              | il pannello (HTML)                            |
| GET    | `/health`             | `{"ok":true}`                                 |

`/v1/profile` e `/v1/account` rispondono `{"data":"<cifrato>","updatedAt":…}`
(l'utenza aggiunge `"sync":0|1`, che dice al dispositivo se adottare il codice
dell'utenza anche come codice di sincronizzazione).

Dietro al token (`Authorization: Bearer <ADMIN_TOKEN>`):

| Metodo | Percorso                   | Cosa fa                                          |
| ------ | -------------------------- | ------------------------------------------------ |
| GET    | `/v1/admin/state`          | utenze + dispositivi, in una chiamata sola        |
| POST   | `/v1/admin/account`        | crea/aggiorna `{id, name, syncId, syncEnabled, data?}` |
| POST   | `/v1/admin/forget-account` | cancella utenza, playlist, blob e caselline       |
| POST   | `/v1/admin/device`         | aggancia `{code, accountId, note, casellina}`     |
| POST   | `/v1/admin/device-edit`    | rinomina `{id, note}` (per hash, senza codice)    |
| POST   | `/v1/admin/forget-device`  | cancella `{id}`: riga, casellina e blob           |

Il codice è di 12 caratteri `A-Z0-9`; i trattini con cui l'app lo mostra
(`ABCD-EFGH-JKLM`) vengono ignorati. Blob oltre 1 MB → `413`.

## Migrazioni

`schema.sql` è il punto d'arrivo, per un database **nuovo**. Su quello già in
produzione si applicano i file in `migrations/`, **uno alla volta e una volta
sola** (D1 non ha `ADD COLUMN IF NOT EXISTS`: rilanciarne una fallisce con
"duplicate column name", ed è innocuo):

```bash
npx wrangler d1 execute broken-iptv-sync --remote --file=./migrations/003_accounts.sql
```

## Note

- La fusione dei dati avviene **nell'app** (stessa funzione pura su ogni
  dispositivo, vince la modifica più recente, le rimozioni viaggiano come
  tombstone): il Worker non guarda dentro al payload.
- Non c'è rate limiting: il servizio è per uso personale e l'indirizzo non è
  pubblicizzato. Se dovesse servire, Cloudflare offre le Rate Limiting Rules
  sul dominio del Worker.
- Per azzerare tutto: `npx wrangler d1 execute broken-iptv-sync --remote
  --command "DELETE FROM blobs"`.
