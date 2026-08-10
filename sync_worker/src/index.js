/**
 * Broken IPTV — sync + provisioning backend.
 *
 * Stores one JSON blob per sync code (favourites + "continua a guardare") so
 * the phone, the Firestick and the PC see the same lists, plus one encrypted
 * playlist slot per code so the owner can configure someone else's device from
 * the admin panel. Deliberately tiny:
 *
 *   GET    /v1/blob/<code>     -> the stored blob, 404 when nothing is stored
 *   PUT    /v1/blob/<code>     -> replaces it
 *   DELETE /v1/blob/<code>     -> forgets it
 *   GET    /v1/profile/<code>  -> the encrypted playlist the panel left here
 *   GET    /admin              -> the owner's panel (token-gated)
 *   *      /v1/admin/...       -> what the panel calls (token-gated)
 *
 * There are no accounts. The code IS the secret, so it is never written to the
 * database: rows are keyed by SHA-256(code), which means a dump of the tables
 * can't be used to read anyone's data back out. Merging happens in the app
 * (both devices run the same pure merge), so the server never needs to
 * understand the sync payload — and it *cannot* read the playlist one, which
 * the panel encrypts with the code before sending it here.
 *
 * ⚠️ Every device route is gated on the `codes` allowlist. The endpoint is
 * baked into the app and the app is public, so without the gate anyone could
 * spend the free plan's budget. A code is only in there because the owner
 * added it from the panel.
 */

import ADMIN_HTML from './admin.html.js';

const CODE_RE = /^[A-Z0-9]{12}$/;

/** D1 rows are cheap but not free — cap a blob at 1 MB. */
const MAX_BYTES = 1024 * 1024;

/** The encrypted playlist is a few hundred bytes; anything bigger is wrong. */
const MAX_PROFILE_BYTES = 8 * 1024;

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
        // Only on writes: a "last seen" refreshed by every read would double
        // the write budget for nothing.
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
 * What the panel calls. Everything here needs the admin token; the code itself
 * is typed by the owner (the device read it out loud) and hashed on arrival,
 * so this never stores it either.
 */
async function adminRoutes(request, env, url) {
  if (!(await isAdmin(request, env))) return json({ error: 'unauthorized' }, 401);

  const route = url.pathname.slice('/v1/admin/'.length);

  // The whole list, newest first. Only hashes and notes — there is nothing
  // here that could reconstruct a code.
  if (route === 'codes' && request.method === 'GET') {
    const { results } = await env.DB.prepare(
      `SELECT c.id, c.note, c.account, c.sync_enabled, c.created_at, c.last_seen,
              (SELECT 1 FROM blobs    b WHERE b.id = c.id) AS has_blob,
              (SELECT 1 FROM profiles p WHERE p.id = c.id) AS has_profile,
              (SELECT p.updated_at FROM profiles p WHERE p.id = c.id) AS profile_at
         FROM codes c
        ORDER BY c.created_at DESC`,
    ).all();
    return json({ codes: results ?? [] });
  }

  // Add a device, or edit its note / sync switch. Idempotent on purpose: the
  // panel sends the whole row every time.
  if (route === 'codes' && request.method === 'POST') {
    const body = await readJson(request);
    if (!body) return json({ error: 'bad_json' }, 400);
    const code = normalizeCode(body.code);
    if (!CODE_RE.test(code)) return json({ error: 'bad_code' }, 400);
    const id = await rowId(code);
    const note = (body.note ?? '').toString().slice(0, 120);
    const account = (body.account ?? '').toString().slice(0, 120);
    const sync = body.syncEnabled ? 1 : 0;
    await env.DB.prepare(
      `INSERT INTO codes (id, note, account, sync_enabled, created_at) VALUES (?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET note = excluded.note, account = excluded.account,
                                     sync_enabled = excluded.sync_enabled`,
    )
      .bind(id, note, account, sync, Date.now())
      .run();
    return json({ ok: true, id });
  }

  // The encrypted playlist for one device. The panel does the encryption: what
  // arrives here is opaque base64 and stays that way.
  if (route === 'profile' && request.method === 'POST') {
    const body = await readJson(request);
    if (!body) return json({ error: 'bad_json' }, 400);
    const code = normalizeCode(body.code);
    if (!CODE_RE.test(code)) return json({ error: 'bad_code' }, 400);
    const data = (body.data ?? '').toString();
    if (!data || data.length > MAX_PROFILE_BYTES) return json({ error: 'bad_data' }, 400);
    const id = await rowId(code);
    if (!(await codeRow(env, id))) return json({ error: 'unknown_code' }, 404);
    await env.DB.prepare(
      `INSERT INTO profiles (id, data, updated_at) VALUES (?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at`,
    )
      .bind(id, data, Date.now())
      .run();
    return json({ ok: true });
  }

  // Edit a device already in the list. Keyed by its **hash**, not by the code:
  // the owner no longer has the code in hand (nobody stores it), and none of
  // these changes need it — only encrypting a playlist does.
  if (route === 'device' && request.method === 'POST') {
    const body = await readJson(request);
    if (!body) return json({ error: 'bad_json' }, 400);
    const id = (body.id ?? '').toString();
    if (!/^[0-9a-f]{64}$/.test(id)) return json({ error: 'bad_id' }, 400);
    if (!(await codeRow(env, id))) return json({ error: 'unknown_code' }, 404);
    await env.DB.prepare(
      'UPDATE codes SET note = ?, account = ?, sync_enabled = ? WHERE id = ?',
    )
      .bind(
        (body.note ?? '').toString().slice(0, 120),
        (body.account ?? '').toString().slice(0, 120),
        body.syncEnabled ? 1 : 0,
        id,
      )
      .run();
    return json({ ok: true });
  }

  // Same, for the whole utenza: one switch that covers every device the owner
  // registered under that name — "una volta che clicco il pulsante e' attiva
  // per tutti i dispositivi che ho registrato io".
  if (route === 'account-sync' && request.method === 'POST') {
    const body = await readJson(request);
    if (!body) return json({ error: 'bad_json' }, 400);
    const account = (body.account ?? '').toString();
    const result = await env.DB.prepare(
      'UPDATE codes SET sync_enabled = ? WHERE account = ?',
    )
      .bind(body.syncEnabled ? 1 : 0, account)
      .run();
    return json({ ok: true, changed: result.meta?.changes ?? 0 });
  }

  if (route === 'forget-device' && request.method === 'POST') {
    const body = await readJson(request);
    if (!body) return json({ error: 'bad_json' }, 400);
    const id = (body.id ?? '').toString();
    if (!/^[0-9a-f]{64}$/.test(id)) return json({ error: 'bad_id' }, 400);
    await env.DB.batch([
      env.DB.prepare('DELETE FROM profiles WHERE id = ?').bind(id),
      env.DB.prepare('DELETE FROM blobs WHERE id = ?').bind(id),
      env.DB.prepare('DELETE FROM codes WHERE id = ?').bind(id),
    ]);
    return json({ ok: true });
  }

  // Remove a device entirely: allowlist row, its sync blob and its playlist.
  if (route === 'forget' && request.method === 'POST') {
    const body = await readJson(request);
    if (!body) return json({ error: 'bad_json' }, 400);
    const code = normalizeCode(body.code);
    if (!CODE_RE.test(code)) return json({ error: 'bad_code' }, 400);
    const id = await rowId(code);
    await env.DB.batch([
      env.DB.prepare('DELETE FROM profiles WHERE id = ?').bind(id),
      env.DB.prepare('DELETE FROM blobs WHERE id = ?').bind(id),
      env.DB.prepare('DELETE FROM codes WHERE id = ?').bind(id),
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
