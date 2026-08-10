/**
 * Broken IPTV — sync + provisioning backend.
 *
 * Stores one JSON blob per sync code (favourites + "continua a guardare") so
 * the phone, the Firestick and the PC see the same lists, plus the owner's
 * **utenze**: an utenza is a real IPTV account (name, host, username,
 * password), the devices hang off it, and correcting its credentials once
 * reaches every one of them. Deliberately tiny:
 *
 *   GET    /v1/blob/<code>     -> the stored blob, 404 when nothing is stored
 *   PUT    /v1/blob/<code>     -> replaces it
 *   DELETE /v1/blob/<code>     -> forgets it
 *   GET    /v1/profile/<code>  -> the device's *casellina*: which utenza it
 *                                 belongs to, encrypted with its own code
 *   GET    /v1/account/<id>    -> that utenza's playlist, encrypted with the
 *                                 utenza's code (which only the panel derives)
 *   GET    /admin              -> the owner's panel (token-gated)
 *   *      /v1/admin/...       -> what the panel calls (token-gated)
 *
 * There are no accounts to log into. A device's code IS its secret, so it is
 * never written to the database: rows are keyed by SHA-256(code), which means a
 * dump of the tables can't be used to read anyone's data back out. Merging
 * happens in the app (both devices run the same pure merge), so the server
 * never needs to understand the sync payload.
 *
 * ⚠️ The playlists are the one place where that stops being absolute. An
 * utenza's code is **derived**, not stored: HMAC-SHA256(ADMIN_TOKEN, id), done
 * in the browser by the panel. So the tables alone still reveal nothing — but
 * whoever holds ADMIN_TOKEN can re-derive every utenza's code and read every
 * playlist. That trade is deliberate: it is what lets the owner fix a password
 * once and have it land on devices whose codes nobody kept.
 *
 * ⚠️ Consequence, worth knowing before touching the secret: **rotating
 * ADMIN_TOKEN orphans every device.** New token = new utenza codes = the
 * caselline already handed out point at a code that no longer decrypts
 * anything, and rebuilding them needs each device's code read out loud again.
 *
 * ⚠️ Every device route is gated on the `codes` allowlist. The endpoint is
 * baked into the app and the app is public, so without the gate anyone could
 * spend the free plan's budget. A code is only in there because the owner
 * added it from the panel.
 */

import ADMIN_HTML from './admin.html.js';

const CODE_RE = /^[A-Z0-9]{12}$/;

/** Row keys: SHA-256 hex. */
const ROW_ID_RE = /^[0-9a-f]{64}$/;

/** An utenza's id: 16 random bytes from the panel. Public, not a secret. */
const ACCOUNT_ID_RE = /^[0-9a-f]{32}$/;

/** D1 rows are cheap but not free — cap a blob at 1 MB. */
const MAX_BYTES = 1024 * 1024;

/** Encrypted playlists and caselline are a few hundred bytes; more is wrong. */
const MAX_PROFILE_BYTES = 8 * 1024;

/** How stale `last_seen` has to be before a read is worth a write. */
const SEEN_EVERY = 5 * 60 * 1000;

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  });

async function sha256Hex(input) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(input));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/** The row key for a code. Same derivation the panel uses, and the only form
 * of the code that ever reaches storage. */
const rowId = (code) => sha256Hex(`broken-iptv-sync:${code}`);

/** Codes are shown grouped (ABCD-EFGH-JKLM); accept either form. */
const normalizeCode = (raw) =>
  decodeURIComponent(raw ?? '').toUpperCase().replace(/[^A-Z0-9]/g, '');

const text = (value, max = 120) => (value ?? '').toString().slice(0, max);

/**
 * Admin authentication: `Authorization: Bearer <ADMIN_TOKEN>`, where the token
 * is a Worker secret (`wrangler secret put ADMIN_TOKEN`) — never a constant in
 * this file, which is checked into a repo.
 *
 * Both sides are hashed before comparing, so a wrong guess reveals nothing
 * through timing and the comparison doesn't leak the token's length either.
 */
async function isAdmin(request, env) {
  const expected = env.ADMIN_TOKEN;
  if (!expected) return false; // no secret set = panel closed, not open.
  const header = request.headers.get('authorization') || '';
  const given = header.startsWith('Bearer ') ? header.slice(7) : '';
  if (!given) return false;
  const [a, b] = await Promise.all([sha256Hex(given), sha256Hex(expected)]);
  return a === b;
}

/** The allowlist row for a code, or null when the owner never added it. */
const codeRow = (env, id) =>
  env.DB.prepare('SELECT id, note, sync_enabled FROM codes WHERE id = ?').bind(id).first();

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === '/health') return json({ ok: true });
    if (url.pathname === '/admin') {
      // The page itself is public HTML — it asks for the token and keeps it in
      // the browser. Every byte of data behind it is gated on /v1/admin.
      return new Response(ADMIN_HTML, {
        headers: { 'content-type': 'text/html; charset=utf-8' },
      });
    }

    if (url.pathname.startsWith('/v1/admin/')) return adminRoutes(request, env, url);

    // The utenza's playlist. Not gated on the allowlist: the id is 16 random
    // bytes that only a device holding the right casellina can know, and what
    // comes back is ciphertext this server cannot read anyway.
    const accountMatch = url.pathname.match(/^\/v1\/account\/([0-9a-f]{32})$/);
    if (accountMatch) {
      if (request.method !== 'GET') return json({ error: 'method_not_allowed' }, 405);
      const row = await env.DB.prepare(
        `SELECT a.data, a.updated_at,
                (SELECT c.sync_enabled FROM codes c WHERE c.id = a.sync_id) AS sync
           FROM accounts a WHERE a.id = ?`,
      )
        .bind(accountMatch[1])
        .first();
      if (!row || !row.data) return json({ error: 'empty' }, 404);
      return json({ data: row.data, updatedAt: row.updated_at, sync: row.sync ? 1 : 0 });
    }

    const blobMatch = url.pathname.match(/^\/v1\/blob\/([^/]+)$/);
    const profileMatch = url.pathname.match(/^\/v1\/profile\/([^/]+)$/);
    if (!blobMatch && !profileMatch) return json({ error: 'not_found' }, 404);

    const code = normalizeCode((blobMatch ?? profileMatch)[1]);
    if (!CODE_RE.test(code)) return json({ error: 'bad_code' }, 400);
    const id = await rowId(code);

    const allowed = await codeRow(env, id);
    if (!allowed) return json({ error: 'unknown_code' }, 403);

    if (profileMatch) {
      if (request.method !== 'GET') return json({ error: 'method_not_allowed' }, 405);
      const row = await env.DB.prepare('SELECT data, updated_at FROM profiles WHERE id = ?')
        .bind(id)
        .first();
      // This is the one call a device makes even when nothing is waiting for
      // it, so it is where "when did I last hear from it" comes from. Throttled
      // to one write per device every few minutes: the setup screen polls every
      // 10s while somebody waits in front of it.
      const now = Date.now();
      await env.DB.prepare(
        'UPDATE codes SET last_seen = ? WHERE id = ? AND (last_seen IS NULL OR last_seen < ?)',
      )
        .bind(now, id, now - SEEN_EVERY)
        .run();
      if (!row) return json({ error: 'empty' }, 404);
      return json({ data: row.data, updatedAt: row.updated_at });
    }

    // Sync is the part that costs: it is off until the owner turns it on.
    if (!allowed.sync_enabled) return json({ error: 'sync_disabled' }, 403);

    if (request.method === 'GET') {
      const row = await env.DB.prepare('SELECT data FROM blobs WHERE id = ?').bind(id).first();
      if (!row) return json({ error: 'empty' }, 404);
      return new Response(row.data, {
        headers: {
          'content-type': 'application/json; charset=utf-8',
          'cache-control': 'no-store',
        },
      });
    }

    if (request.method === 'PUT') {
      const body = await request.text();
      if (body.length > MAX_BYTES) return json({ error: 'too_large' }, 413);
      try {
        JSON.parse(body);
      } catch {
        return json({ error: 'bad_json' }, 400);
      }
      await env.DB.batch([
        env.DB.prepare(
          `INSERT INTO blobs (id, data, updated_at) VALUES (?, ?, ?)
           ON CONFLICT(id) DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at`,
        ).bind(id, body, Date.now()),
        env.DB.prepare('UPDATE codes SET last_seen = ? WHERE id = ?').bind(Date.now(), id),
      ]);
      return json({ ok: true });
    }

    if (request.method === 'DELETE') {
      await env.DB.prepare('DELETE FROM blobs WHERE id = ?').bind(id).run();
      return json({ ok: true });
    }

    return json({ error: 'method_not_allowed' }, 405);
  },
};

/**
 * What the panel calls. Everything here needs the admin token.
 *
 * Two kinds of write live here, and the difference is the whole shape of the
 * page: anything that has to *reach a device* needs that device's code (it is
 * the only key its casellina can be encrypted with), and nobody keeps device
 * codes — so everything else is keyed by hash and can be done from the list
 * months later.
 */
async function adminRoutes(request, env, url) {
  if (!(await isAdmin(request, env))) return json({ error: 'unauthorized' }, 401);

  const route = url.pathname.slice('/v1/admin/'.length);

  // Everything the panel draws, in one round trip. Only hashes, labels and
  // ciphertext: there is nothing here that could reconstruct a device code.
  if (route === 'state' && request.method === 'GET') {
    const [accounts, devices] = await Promise.all([
      env.DB.prepare(
        `SELECT a.id, a.name, a.sync_id, a.data, a.updated_at, a.created_at,
                (SELECT c.sync_enabled FROM codes c WHERE c.id = a.sync_id) AS sync_enabled,
                (SELECT c.last_seen    FROM codes c WHERE c.id = a.sync_id) AS sync_seen
           FROM accounts a
          ORDER BY a.name COLLATE NOCASE`,
      ).all(),
      env.DB.prepare(
        `SELECT c.id, c.note, c.account_id, c.sync_enabled, c.created_at, c.last_seen,
                (SELECT 1 FROM blobs    b WHERE b.id = c.id) AS has_blob,
                (SELECT 1 FROM profiles p WHERE p.id = c.id) AS has_casellina
           FROM codes c
          WHERE COALESCE(c.kind, 'device') <> 'account'
          ORDER BY c.created_at DESC`,
      ).all(),
    ]);
    return json({ accounts: accounts.results ?? [], devices: devices.results ?? [] });
  }

  // Create or edit an utenza. The panel sends the whole row every time, so
  // this is idempotent; `data` is omitted when only the name changed.
  //
  // `updated_at` moves on every save on purpose — it is what the devices
  // compare against what they applied last, so a save is what makes a
  // correction travel.
  if (route === 'account' && request.method === 'POST') {
    const body = await readJson(request);
    if (!body) return json({ error: 'bad_json' }, 400);
    const id = text(body.id, 32);
    if (!ACCOUNT_ID_RE.test(id)) return json({ error: 'bad_id' }, 400);
    const syncId = text(body.syncId, 64);
    if (!ROW_ID_RE.test(syncId)) return json({ error: 'bad_sync_id' }, 400);
    const name = text(body.name).trim();
    if (!name) return json({ error: 'bad_name' }, 400);
    const data = body.data == null ? null : body.data.toString();
    if (data && data.length > MAX_PROFILE_BYTES) return json({ error: 'bad_data' }, 400);
    const now = Date.now();

    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO accounts (id, name, sync_id, data, updated_at, created_at)
              VALUES (?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
              name = excluded.name,
              sync_id = excluded.sync_id,
              -- A rename must not wipe the playlist: keep what's stored when
              -- the panel didn't send one.
              data = COALESCE(excluded.data, accounts.data),
              updated_at = excluded.updated_at`,
      ).bind(id, name, syncId, data, now, now),
      // The allowlist row that authorises the utenza's shared sync blob. It
      // lives in `codes` like everything else the Worker gates on, marked so
      // the device list doesn't show it as an installation.
      env.DB.prepare(
        `INSERT INTO codes (id, note, sync_enabled, created_at, account_id, kind)
              VALUES (?, ?, ?, ?, ?, 'account')
         ON CONFLICT(id) DO UPDATE SET sync_enabled = excluded.sync_enabled,
                                       account_id = excluded.account_id,
                                       kind = 'account'`,
      ).bind(syncId, name, body.syncEnabled ? 1 : 0, now, id),
    ]);
    return json({ ok: true });
  }

  // Register a device, or move it to another utenza. This is the one route
  // that needs the code read out loud: the casellina — which utenza this
  // device belongs to — can only be encrypted with it.
  if (route === 'device' && request.method === 'POST') {
    const body = await readJson(request);
    if (!body) return json({ error: 'bad_json' }, 400);
    const code = normalizeCode(body.code);
    if (!CODE_RE.test(code)) return json({ error: 'bad_code' }, 400);
    const accountId = text(body.accountId, 32);
    if (!ACCOUNT_ID_RE.test(accountId)) return json({ error: 'bad_id' }, 400);
    if (!(await env.DB.prepare('SELECT id FROM accounts WHERE id = ?').bind(accountId).first())) {
      return json({ error: 'unknown_account' }, 404);
    }
    const casellina = (body.casellina ?? '').toString();
    if (!casellina || casellina.length > MAX_PROFILE_BYTES) return json({ error: 'bad_data' }, 400);
    const id = await rowId(code);
    const now = Date.now();

    await env.DB.batch([
      env.DB.prepare(
        `INSERT INTO codes (id, note, sync_enabled, created_at, account_id, kind)
              VALUES (?, ?, 0, ?, ?, 'device')
         ON CONFLICT(id) DO UPDATE SET note = excluded.note,
                                       account_id = excluded.account_id,
                                       kind = 'device'`,
      ).bind(id, text(body.note), now, accountId),
      env.DB.prepare(
        `INSERT INTO profiles (id, data, updated_at) VALUES (?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at`,
      ).bind(id, casellina, now),
    ]);
    return json({ ok: true, id });
  }

  // Rename a device already in the list. Keyed by its **hash**, not by the
  // code: the owner no longer has the code in hand, and a label never has to
  // reach the device.
  if (route === 'device-edit' && request.method === 'POST') {
    const body = await readJson(request);
    if (!body) return json({ error: 'bad_json' }, 400);
    const id = text(body.id, 64);
    if (!ROW_ID_RE.test(id)) return json({ error: 'bad_id' }, 400);
    if (!(await codeRow(env, id))) return json({ error: 'unknown_code' }, 404);
    await env.DB.prepare('UPDATE codes SET note = ? WHERE id = ?')
      .bind(text(body.note), id)
      .run();
    return json({ ok: true });
  }

  // Remove a device entirely: allowlist row, its casellina and any sync blob
  // it still owned from before it joined an utenza.
  if (route === 'forget-device' && request.method === 'POST') {
    const body = await readJson(request);
    if (!body) return json({ error: 'bad_json' }, 400);
    const id = text(body.id, 64);
    if (!ROW_ID_RE.test(id)) return json({ error: 'bad_id' }, 400);
    await env.DB.batch([
      env.DB.prepare('DELETE FROM profiles WHERE id = ?').bind(id),
      env.DB.prepare('DELETE FROM blobs WHERE id = ?').bind(id),
      env.DB.prepare('DELETE FROM codes WHERE id = ?').bind(id),
    ]);
    return json({ ok: true });
  }

  // Remove an utenza: its playlist, its shared sync blob, and the caselline of
  // its devices — which are left registered but pointing nowhere, because
  // hooking them up again needs their codes.
  if (route === 'forget-account' && request.method === 'POST') {
    const body = await readJson(request);
    if (!body) return json({ error: 'bad_json' }, 400);
    const id = text(body.id, 32);
    if (!ACCOUNT_ID_RE.test(id)) return json({ error: 'bad_id' }, 400);
    const account = await env.DB.prepare('SELECT sync_id FROM accounts WHERE id = ?')
      .bind(id)
      .first();
    if (!account) return json({ error: 'unknown_account' }, 404);
    await env.DB.batch([
      env.DB.prepare(
        'DELETE FROM profiles WHERE id IN (SELECT id FROM codes WHERE account_id = ?)',
      ).bind(id),
      env.DB.prepare('UPDATE codes SET account_id = NULL WHERE account_id = ?').bind(id),
      env.DB.prepare('DELETE FROM blobs WHERE id = ?').bind(account.sync_id ?? ''),
      env.DB.prepare('DELETE FROM codes WHERE id = ?').bind(account.sync_id ?? ''),
      env.DB.prepare('DELETE FROM accounts WHERE id = ?').bind(id),
    ]);
    return json({ ok: true });
  }

  return json({ error: 'not_found' }, 404);
}

async function readJson(request) {
  try {
    const body = await request.json();
    return body && typeof body === 'object' ? body : null;
  } catch {
    return null;
  }
}
