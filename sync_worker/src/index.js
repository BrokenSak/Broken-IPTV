/**
 * Broken IPTV — sync backend.
 *
 * Stores one JSON blob per sync code (favourites + "continua a guardare") so
 * the phone, the Firestick and the PC see the same lists. Deliberately tiny:
 *
 *   GET    /v1/blob/<code>  -> the stored blob, 404 when nothing is stored yet
 *   PUT    /v1/blob/<code>  -> replaces it
 *   DELETE /v1/blob/<code>  -> forgets it
 *
 * There are no accounts. The sync code IS the secret, so it is never written
 * to the database: rows are keyed by SHA-256(code), which means a dump of the
 * table can't be used to read anyone's data back out. Merging happens in the
 * app (both devices run the same pure merge), so the server never needs to
 * understand the payload.
 */

const CODE_RE = /^[A-Z0-9]{12}$/;

/** D1 rows are cheap but not free — cap a blob at 1 MB. */
const MAX_BYTES = 1024 * 1024;

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  });

async function rowId(code) {
  const bytes = new TextEncoder().encode(`broken-iptv-sync:${code}`);
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === '/health') return json({ ok: true });

    const match = url.pathname.match(/^\/v1\/blob\/([^/]+)$/);
    if (!match) return json({ error: 'not_found' }, 404);

    // Codes are shown grouped (ABCD-EFGH-JKLM); accept either form.
    const code = decodeURIComponent(match[1]).toUpperCase().replace(/[^A-Z0-9]/g, '');
    if (!CODE_RE.test(code)) return json({ error: 'bad_code' }, 400);
    const id = await rowId(code);

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
      await env.DB.prepare(
        `INSERT INTO blobs (id, data, updated_at) VALUES (?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET data = excluded.data, updated_at = excluded.updated_at`,
      )
        .bind(id, body, Date.now())
        .run();
      return json({ ok: true });
    }

    if (request.method === 'DELETE') {
      await env.DB.prepare('DELETE FROM blobs WHERE id = ?').bind(id).run();
      return json({ ok: true });
    }

    return json({ error: 'method_not_allowed' }, 405);
  },
};
