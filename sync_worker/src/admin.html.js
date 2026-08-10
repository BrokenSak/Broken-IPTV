/**
 * The owner's panel, served at /admin.
 *
 * Design brief: this page is a phone call. Somebody reads you twelve
 * characters and you set their device up while they wait — so the page opens
 * with the code field, sized like the thing you're transcribing, and the list
 * of devices is history underneath it. Greyscale and glass, like the app.
 *
 * The page is public HTML; nothing behind it loads without the admin token,
 * which the browser keeps in localStorage and sends as a bearer header.
 *
 * ⚠️ This module is a plain template string: do NOT use backticks or ${...}
 * inside the panel's own script — string concatenation only.
 */
export default `<!doctype html>
<html lang="it">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="color-scheme" content="dark">
<title>Broken IPTV · pannello</title>
<style>
  :root {
    --ink: #000;
    --panel: #0e0e0f;
    --glass: rgba(255,255,255,.055);
    --glass-hi: rgba(255,255,255,.085);
    --edge: rgba(255,255,255,.12);
    --edge-hi: rgba(255,255,255,.28);
    --text: #f5f5f7;
    --muted: #8a8a8e;
    --sans: ui-sans-serif, -apple-system, "Segoe UI Variable Display", "Segoe UI", system-ui, sans-serif;
    --mono: ui-monospace, "Cascadia Mono", "SF Mono", Consolas, monospace;
    --r: 16px;
  }
  * { box-sizing: border-box; }
  html, body { margin: 0; background: var(--ink); }
  body {
    font-family: var(--sans);
    color: var(--text);
    -webkit-font-smoothing: antialiased;
    min-height: 100dvh;
    /* One soft light behind the code field: the app's glass needs something
       to catch, and a flat black page has nothing. */
    background:
      radial-gradient(120% 60% at 50% -10%, rgba(255,255,255,.09), transparent 60%),
      var(--ink);
  }
  .wrap { max-width: 720px; margin: 0 auto; padding: 0 20px 80px; }

  header {
    display: flex; align-items: center; gap: 10px;
    padding: 18px 0; margin-bottom: 34px;
    border-bottom: 1px solid var(--edge);
  }
  .mark {
    width: 26px; height: 26px; border-radius: 8px; background: #fff;
    display: grid; place-items: center; flex: none;
  }
  .mark svg { width: 12px; height: 12px; fill: #000; margin-left: 1px; }
  header h1 { font-size: 15px; font-weight: 600; letter-spacing: -.01em; margin: 0; }
  header .sp { flex: 1; }

  .eyebrow {
    font-size: 12px; color: var(--muted); letter-spacing: .04em;
    margin: 0 0 12px;
  }

  /* ---- the dial: twelve slots, grouped like the app prints the code ---- */
  .dial-shell { position: relative; }
  .dial {
    display: flex; align-items: center; gap: 4px; flex-wrap: nowrap;
    padding: 14px 12px;
    background: var(--glass);
    border: 1px solid var(--edge);
    border-radius: var(--r);
    backdrop-filter: blur(20px);
    transition: border-color .18s ease, background .18s ease;
  }
  .dial-shell:focus-within .dial { border-color: var(--edge-hi); background: var(--glass-hi); }
  .cell {
    flex: 1 1 0; min-width: 0;
    text-align: center;
    font-family: var(--mono);
    font-size: clamp(17px, 5.2vw, 28px);
    line-height: 1.5;
    color: var(--text);
    border-radius: 8px;
    background: rgba(255,255,255,.04);
  }
  .cell.empty { color: transparent; }
  .cell.active { box-shadow: inset 0 0 0 1.5px #fff; }
  .sep { flex: none; width: 12px; text-align: center; color: var(--muted); }
  .dial-shell input {
    position: absolute; inset: 0; width: 100%; height: 100%;
    opacity: 0; border: 0; padding: 0; font-size: 16px; /* 16px: iOS won't zoom */
    background: transparent; color: transparent;
  }
  .hash {
    font-family: var(--mono); font-size: 11.5px; color: var(--muted);
    margin: 10px 2px 0; min-height: 16px;
  }

  /* ---- forms ---- */
  .card {
    background: var(--panel);
    border: 1px solid var(--edge);
    border-radius: var(--r);
    padding: 18px;
    margin-top: 14px;
  }
  .card h2 { font-size: 13px; font-weight: 600; margin: 0 0 4px; letter-spacing: -.005em; }
  .card p.hint { font-size: 12.5px; color: var(--muted); margin: 0 0 16px; line-height: 1.5; }
  label { display: block; font-size: 12px; color: var(--muted); margin: 0 0 6px; }
  .field + .field { margin-top: 12px; }
  input[type=text], input[type=password] {
    width: 100%; padding: 11px 13px;
    background: rgba(255,255,255,.04);
    border: 1px solid var(--edge);
    border-radius: 11px;
    color: var(--text); font: inherit; font-size: 14px;
  }
  input[type=text]:focus, input[type=password]:focus {
    outline: none; border-color: var(--edge-hi); background: rgba(255,255,255,.07);
  }
  .row2 { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
  @media (max-width: 520px) { .row2 { grid-template-columns: 1fr; gap: 12px; } }

  button {
    font: inherit; font-size: 14px; font-weight: 600;
    padding: 11px 18px; border-radius: 11px; cursor: pointer;
    background: #fff; color: #000; border: 1px solid #fff;
    transition: opacity .15s ease;
  }
  button:hover { opacity: .86; }
  button.ghost { background: transparent; color: var(--text); border-color: var(--edge); }
  button.ghost:hover { background: var(--glass); opacity: 1; }
  button:disabled { opacity: .35; cursor: default; }
  .actions { display: flex; gap: 10px; align-items: center; margin-top: 18px; flex-wrap: wrap; }

  /* State is shape, not colour: filled = on, hairline = off (same language as
     the selected playlist in the app). */
  .switch { display: flex; align-items: center; gap: 12px; cursor: pointer; user-select: none; }
  .switch input { position: absolute; opacity: 0; width: 0; height: 0; }
  .track {
    width: 44px; height: 26px; border-radius: 999px; flex: none;
    border: 1px solid var(--edge); background: rgba(255,255,255,.04);
    position: relative; transition: background .18s ease, border-color .18s ease;
  }
  .knob {
    position: absolute; top: 3px; left: 3px; width: 18px; height: 18px;
    border-radius: 50%; background: var(--muted);
    transition: transform .18s cubic-bezier(.2,.8,.2,1), background .18s ease;
  }
  .switch input:checked + .track { background: #fff; border-color: #fff; }
  .switch input:checked + .track .knob { transform: translateX(18px); background: #000; }
  .switch input:focus-visible + .track { box-shadow: 0 0 0 3px rgba(255,255,255,.35); }
  .switch .lbl { font-size: 13.5px; }
  .switch .lbl small { display: block; color: var(--muted); font-size: 12px; margin-top: 2px; }

  /* ---- device list ---- */
  .list-head {
    display: flex; align-items: baseline; gap: 10px;
    margin: 40px 0 12px; padding-top: 26px; border-top: 1px solid var(--edge);
  }
  .list-head h2 { font-size: 13px; font-weight: 600; margin: 0; }
  .list-head span { font-size: 12px; color: var(--muted); }
  .dev {
    display: flex; align-items: center; gap: 14px;
    padding: 14px 16px; margin-bottom: 8px;
    background: var(--glass); border: 1px solid var(--edge); border-radius: 13px;
    transition: background .15s ease;
  }
  .dev:hover { background: var(--glass-hi); }
  .dev .who { flex: 1; min-width: 0; }
  .dev .name { font-size: 14px; font-weight: 600; }
  .dev .meta { font-size: 11.5px; color: var(--muted); margin-top: 3px; font-family: var(--mono); }
  .tag {
    font-size: 11px; padding: 4px 9px; border-radius: 999px;
    border: 1px solid var(--edge); color: var(--muted); white-space: nowrap;
  }
  .tag.on { background: #fff; color: #000; border-color: #fff; font-weight: 600; }
  .acc { margin-bottom: 22px; }
  .acc-head { display: flex; align-items: baseline; gap: 10px; margin: 0 2px 10px; }
  .acc-name { font-size: 14px; font-weight: 600; }
  .acc-count { font-size: 11.5px; color: var(--muted); }
  button.small { padding: 6px 12px; font-size: 12px; border-radius: 9px; }
  .editor {
    display: flex; flex-direction: column; gap: 10px;
    padding: 14px 16px; margin: -4px 0 10px;
    background: rgba(255,255,255,.03);
    border: 1px solid var(--edge); border-top: 0;
    border-radius: 0 0 13px 13px;
  }
  .editor .actions { margin-top: 4px; }
  .empty-state { color: var(--muted); font-size: 13.5px; padding: 22px 2px; line-height: 1.6; }

  .toast {
    position: fixed; left: 50%; bottom: 26px; transform: translate(-50%, 20px);
    background: #fff; color: #000; font-size: 13.5px; font-weight: 600;
    padding: 11px 18px; border-radius: 999px;
    opacity: 0; pointer-events: none; transition: opacity .2s ease, transform .2s ease;
  }
  .toast.show { opacity: 1; transform: translate(-50%, 0); }
  .hidden { display: none !important; }

  /* Login */
  .gate { max-width: 380px; margin: 22vh auto 0; padding: 0 20px; text-align: center; }
  .gate .mark { width: 44px; height: 44px; border-radius: 13px; margin: 0 auto 20px; }
  .gate .mark svg { width: 19px; height: 19px; }
  .gate h1 { font-size: 19px; font-weight: 600; margin: 0 0 6px; letter-spacing: -.01em; }
  .gate p { color: var(--muted); font-size: 13px; margin: 0 0 22px; line-height: 1.5; }
  .gate button { width: 100%; margin-top: 12px; }
  .err { color: var(--text); font-size: 12.5px; margin-top: 12px; min-height: 18px; }

  @media (prefers-reduced-motion: reduce) { * { transition: none !important; animation: none !important; } }
  :focus-visible { outline: 2px solid #fff; outline-offset: 2px; }
</style>
</head>
<body>

<!-- Login -->
<div class="gate" id="gate">
  <div class="mark"><svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg></div>
  <h1>Pannello Broken IPTV</h1>
  <p>Serve il token di amministrazione.</p>
  <input type="password" id="token" placeholder="Token" autocomplete="current-password">
  <button id="enter">Entra</button>
  <div class="err" id="gate-err"></div>
</div>

<!-- Panel -->
<div class="wrap hidden" id="panel">
  <header>
    <div class="mark"><svg viewBox="0 0 24 24"><path d="M8 5v14l11-7z"/></svg></div>
    <h1>Broken IPTV · pannello</h1>
    <div class="sp"></div>
    <button class="ghost" id="logout">Esci</button>
  </header>

  <p class="eyebrow">Codice del dispositivo</p>
  <div class="dial-shell">
    <div class="dial" id="dial"></div>
    <input id="code" inputmode="latin" autocapitalize="characters" autocomplete="off"
           spellcheck="false" maxlength="20" aria-label="Codice del dispositivo">
  </div>
  <div class="hash" id="hash"></div>

  <div class="card">
    <h2>Dispositivo</h2>
    <p class="hint">L'utenza raggruppa i dispositivi di una persona; il nome del dispositivo
      serve a distinguerli. Nell'elenco i codici non si possono leggere.</p>
    <div class="row2">
      <div class="field" style="margin:0">
        <label for="account">Utenza (la persona)</label>
        <input type="text" id="account" placeholder="mamma" autocomplete="off" list="accounts">
        <datalist id="accounts"></datalist>
      </div>
      <div class="field" style="margin:0">
        <label for="note">Dispositivo</label>
        <input type="text" id="note" placeholder="Firestick salotto">
      </div>
    </div>
    <div class="actions">
      <label class="switch">
        <input type="checkbox" id="sync">
        <span class="track"><span class="knob"></span></span>
        <span class="lbl">Sincronizzazione
          <small>Preferiti e Continua a guardare fra i suoi dispositivi</small>
        </span>
      </label>
    </div>
    <div class="actions">
      <button id="save" disabled>Salva dispositivo</button>
      <button class="ghost hidden" id="forget">Rimuovi</button>
    </div>
  </div>

  <div class="card">
    <h2>Playlist</h2>
    <p class="hint">Arriva cifrata con il codice: il server non può leggerla, e serve il codice
      per inviarla — dall'elenco qui sotto non si può.</p>
    <div class="field">
      <label for="host">Indirizzo del pannello</label>
      <input type="text" id="host" placeholder="http://esempio.tv:8080" autocomplete="off">
    </div>
    <div class="field">
      <label for="plname">Nome della playlist sul dispositivo</label>
      <input type="text" id="plname" placeholder="Playlist" autocomplete="off">
    </div>
    <div class="row2" style="margin-top:12px">
      <div class="field" style="margin:0">
        <label for="user">Utente</label>
        <input type="text" id="user" autocomplete="off">
      </div>
      <div class="field" style="margin:0">
        <label for="pass">Password</label>
        <input type="text" id="pass" autocomplete="off">
      </div>
    </div>
    <div class="field" style="margin-top:12px">
      <label for="group">Sincronizza con (codice di un altro suo dispositivo) — opzionale</label>
      <input type="text" id="group" placeholder="ABCD-EFGH-JKLM" autocomplete="off"
             autocapitalize="characters" spellcheck="false">
    </div>
    <p class="hint" style="margin:8px 0 0">Con lo stesso codice su due dispositivi, preferiti e
      Continua a guardare si allineano. La sincronizzazione segue quel codice: accendila sulla
      sua riga qui sotto.</p>
    <div class="actions">
      <button id="send" disabled>Invia al dispositivo</button>
    </div>
  </div>

  <div class="list-head">
    <h2>Dispositivi</h2>
    <span id="count"></span>
  </div>
  <div id="list"></div>
</div>

<div class="toast" id="toast"></div>

<script>
(function () {
  var $ = function (id) { return document.getElementById(id); };
  var TOKEN_KEY = 'brokeniptv.admin.token';
  var token = localStorage.getItem(TOKEN_KEY) || '';
  var codes = [];

  /* ---------- transport ---------- */
  function api(path, options) {
    options = options || {};
    var headers = { 'authorization': 'Bearer ' + token };
    if (options.body) headers['content-type'] = 'application/json';
    return fetch('/v1/admin/' + path, {
      method: options.method || 'GET',
      headers: headers,
      body: options.body ? JSON.stringify(options.body) : undefined
    }).then(function (r) {
      if (r.status === 401) { signOut(); throw new Error('Token rifiutato.'); }
      return r.json().then(function (b) {
        if (!r.ok) throw new Error(b && b.error ? b.error : 'Errore ' + r.status);
        return b;
      });
    });
  }

  function toast(text) {
    var t = $('toast');
    t.textContent = text;
    t.classList.add('show');
    clearTimeout(t._timer);
    t._timer = setTimeout(function () { t.classList.remove('show'); }, 2600);
  }

  /* ---------- login ---------- */
  function signOut() {
    token = '';
    localStorage.removeItem(TOKEN_KEY);
    $('panel').classList.add('hidden');
    $('gate').classList.remove('hidden');
  }

  function signIn(value) {
    token = value;
    return api('codes').then(function (data) {
      localStorage.setItem(TOKEN_KEY, token);
      $('gate').classList.add('hidden');
      $('panel').classList.remove('hidden');
      render(data.codes || []);
      $('code').focus();
    });
  }

  $('enter').addEventListener('click', function () {
    var value = $('token').value.trim();
    if (!value) { $('gate-err').textContent = 'Scrivi il token.'; return; }
    $('gate-err').textContent = '';
    signIn(value).catch(function (e) { $('gate-err').textContent = e.message; });
  });
  $('token').addEventListener('keydown', function (e) {
    if (e.key === 'Enter') $('enter').click();
  });
  $('logout').addEventListener('click', signOut);

  /* ---------- the dial ---------- */
  var ALPHABET = /[A-Z0-9]/;

  function currentCode() {
    return $('code').value.toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 12);
  }

  function drawDial() {
    var code = currentCode();
    var dial = $('dial');
    dial.textContent = '';
    for (var i = 0; i < 12; i++) {
      if (i === 4 || i === 8) {
        var sep = document.createElement('span');
        sep.className = 'sep';
        sep.textContent = '–';
        dial.appendChild(sep);
      }
      var cell = document.createElement('span');
      var filled = i < code.length;
      cell.className = 'cell' + (filled ? '' : ' empty') +
        (i === code.length && document.activeElement === $('code') ? ' active' : '');
      cell.textContent = filled ? code[i] : '·';
      dial.appendChild(cell);
    }
  }

  /* Shows the row key for the typed code — the only form of it the server ever
     sees, and what identifies the device in the list below. */
  function drawHash() {
    var code = currentCode();
    var out = $('hash');
    if (code.length !== 12) { out.textContent = ''; return; }
    rowId(code).then(function (id) {
      out.textContent = 'Sul server finisce solo questo: ' + id.slice(0, 12) + '…';
      var known = findByHash(id);
      $('note').value = known ? (known.note || '') : $('note').value;
      $('account').value = known ? (known.account || '') : $('account').value;
      $('sync').checked = known ? !!known.sync_enabled : $('sync').checked;
      $('forget').classList.toggle('hidden', !known);
    });
  }

  function findByHash(id) {
    for (var i = 0; i < codes.length; i++) if (codes[i].id === id) return codes[i];
    return null;
  }

  function refreshButtons() {
    var ready = currentCode().length === 12;
    $('save').disabled = !ready;
    $('send').disabled = !ready;
  }

  $('code').addEventListener('input', function () {
    var code = currentCode();
    // Keep the field's own value canonical, so a pasted "abcd-efgh-jklm" and a
    // typed one behave the same.
    $('code').value = code;
    drawDial(); drawHash(); refreshButtons();
  });
  $('code').addEventListener('focus', drawDial);
  $('code').addEventListener('blur', drawDial);
  $('dial').addEventListener('click', function () { $('code').focus(); });

  /* ---------- crypto ----------
     key = SHA-256("broken-iptv-provision:" + code). The code is 12 chars from
     a 32-symbol alphabet (~60 bits), so stretching buys nothing a brute force
     could not already ignore; what matters is that the key never leaves this
     page and the device derives the same one. */
  function bytes(text) { return new TextEncoder().encode(text); }

  function hex(buffer) {
    var view = new Uint8Array(buffer), out = '';
    for (var i = 0; i < view.length; i++) out += ('0' + view[i].toString(16)).slice(-2);
    return out;
  }

  function rowId(code) {
    return crypto.subtle.digest('SHA-256', bytes('broken-iptv-sync:' + code)).then(hex);
  }

  function encrypt(code, payload) {
    return crypto.subtle.digest('SHA-256', bytes('broken-iptv-provision:' + code))
      .then(function (raw) {
        return crypto.subtle.importKey('raw', raw, 'AES-GCM', false, ['encrypt']);
      })
      .then(function (key) {
        var iv = crypto.getRandomValues(new Uint8Array(12));
        return crypto.subtle.encrypt({ name: 'AES-GCM', iv: iv }, key, bytes(payload))
          .then(function (cipher) {
            var joined = new Uint8Array(iv.length + cipher.byteLength);
            joined.set(iv, 0);
            joined.set(new Uint8Array(cipher), iv.length);
            var binary = '';
            for (var i = 0; i < joined.length; i++) binary += String.fromCharCode(joined[i]);
            return btoa(binary);
          });
      });
  }

  /* ---------- actions ---------- */
  $('save').addEventListener('click', function () {
    api('codes', { method: 'POST', body: {
      code: currentCode(), note: $('note').value.trim(),
      account: $('account').value.trim(), syncEnabled: $('sync').checked
    } }).then(function () {
      toast('Dispositivo salvato');
      return reload();
    }).catch(function (e) { toast(e.message); });
  });

  $('forget').addEventListener('click', function () {
    if (!confirm('Rimuovere il dispositivo? Perde la playlist e i dati sincronizzati.')) return;
    api('forget', { method: 'POST', body: { code: currentCode() } })
      .then(function () { toast('Dispositivo rimosso'); return reload(); })
      .catch(function (e) { toast(e.message); });
  });

  $('send').addEventListener('click', function () {
    var host = $('host').value.trim();
    var user = $('user').value.trim();
    var pass = $('pass').value;
    if (!host || !user) { toast('Servono indirizzo e utente.'); return; }
    var group = $('group').value.toUpperCase().replace(/[^A-Z0-9]/g, '');
    if (group && group.length !== 12) { toast('Il codice del gruppo ha 12 caratteri.'); return; }
    var payload = JSON.stringify({
      host: host, username: user, password: pass,
      name: $('plname').value.trim() || 'Playlist',
      syncCode: group || undefined,
      at: Date.now()
    });
    var code = currentCode();
    encrypt(code, payload)
      .then(function (data) { return api('profile', { method: 'POST', body: { code: code, data: data } }); })
      .then(function () {
        toast('Playlist inviata');
        $('pass').value = '';
        return reload();
      })
      .catch(function (e) {
        toast(e.message === 'unknown_code' ? 'Salva prima il dispositivo.' : e.message);
      });
  });

  /* ---------- list ---------- */
  function ago(ms) {
    if (!ms) return 'mai';
    var s = Math.floor((Date.now() - ms) / 1000);
    if (s < 90) return 'poco fa';
    if (s < 5400) return Math.round(s / 60) + ' min fa';
    if (s < 172800) return Math.round(s / 3600) + ' ore fa';
    return Math.round(s / 86400) + ' giorni fa';
  }

  /* Modifica in riga di un dispositivo GIA' registrato. Passa per l'hash e non
     per il codice: quello non ce l'ha piu' nessuno, e per rinominare, spostare
     di utenza o rimuovere non serve — serve solo per cifrare una playlist. */
  function editorFor(row) {
    var box = document.createElement("div");
    box.className = "editor";

    var acc = document.createElement("input");
    acc.type = "text"; acc.value = row.account || ""; acc.placeholder = "Utenza";
    acc.setAttribute("list", "accounts");

    var name = document.createElement("input");
    name.type = "text"; name.value = row.note || ""; name.placeholder = "Dispositivo";

    var save = document.createElement("button");
    save.textContent = "Salva";
    save.addEventListener("click", function () {
      api("device", { method: "POST", body: {
        id: row.id, note: name.value.trim(), account: acc.value.trim(),
        syncEnabled: !!row.sync_enabled
      } }).then(function () { toast("Dispositivo aggiornato"); return reload(); })
        .catch(function (e) { toast(e.message); });
    });

    var del = document.createElement("button");
    del.className = "ghost";
    del.textContent = "Rimuovi";
    del.addEventListener("click", function () {
      if (!confirm("Rimuovere questo dispositivo? Perde playlist e dati sincronizzati.")) return;
      api("forget-device", { method: "POST", body: { id: row.id } })
        .then(function () { toast("Dispositivo rimosso"); return reload(); })
        .catch(function (e) { toast(e.message); });
    });

    var actions = document.createElement("div");
    actions.className = "actions";
    actions.appendChild(save); actions.appendChild(del);

    box.appendChild(acc); box.appendChild(name); box.appendChild(actions);
    return box;
  }

  function deviceRow(row) {
    var el = document.createElement("div");
    el.className = "dev";

    var who = document.createElement("div");
    who.className = "who";
    var name = document.createElement("div");
    name.className = "name";
    name.textContent = row.note || "senza nome";
    var meta = document.createElement("div");
    meta.className = "meta";
    meta.textContent = row.id.slice(0, 12) + " · " + ago(row.last_seen);
    who.appendChild(name); who.appendChild(meta);

    var playlist = document.createElement("span");
    playlist.className = "tag" + (row.has_profile ? " on" : "");
    playlist.textContent = row.has_profile ? "playlist" : "senza playlist";

    var sync = document.createElement("span");
    sync.className = "tag" + (row.sync_enabled ? " on" : "");
    sync.textContent = row.sync_enabled ? "sync" : "sync off";

    var edit = document.createElement("button");
    edit.className = "ghost small";
    edit.textContent = "Modifica";

    el.appendChild(who); el.appendChild(playlist); el.appendChild(sync); el.appendChild(edit);

    var wrap = document.createElement("div");
    wrap.appendChild(el);
    var open = false;
    edit.addEventListener("click", function () {
      open = !open;
      if (open) { wrap.appendChild(editorFor(row)); edit.textContent = "Chiudi"; }
      else { wrap.removeChild(wrap.lastChild); edit.textContent = "Modifica"; }
    });
    return wrap;
  }

  function accountBlock(account, rows) {
    var head = document.createElement("div");
    head.className = "acc-head";

    var title = document.createElement("div");
    title.className = "acc-name";
    title.textContent = account || "Senza utenza";

    var count = document.createElement("span");
    count.className = "acc-count";
    count.textContent = rows.length + (rows.length === 1 ? " dispositivo" : " dispositivi");

    /* Un solo interruttore per tutta l'utenza: lo accendi una volta e vale per
       ogni dispositivo che le hai registrato sotto. */
    var allOn = rows.every(function (r) { return r.sync_enabled; });
    var toggle = document.createElement("button");
    toggle.className = allOn ? "small" : "ghost small";
    toggle.textContent = allOn ? "Sync acceso" : "Accendi sync";
    toggle.disabled = !account;
    toggle.addEventListener("click", function () {
      api("account-sync", { method: "POST", body: { account: account, syncEnabled: !allOn } })
        .then(function (r) {
          toast((allOn ? "Sync spento su " : "Sync acceso su ") + r.changed + " dispositivi");
          return reload();
        })
        .catch(function (e) { toast(e.message); });
    });

    head.appendChild(title); head.appendChild(count);
    var sp = document.createElement("div"); sp.style.flex = "1";
    head.appendChild(sp); head.appendChild(toggle);

    var block = document.createElement("div");
    block.className = "acc";
    block.appendChild(head);
    rows.forEach(function (r) { block.appendChild(deviceRow(r)); });
    return block;
  }

  function render(rows) {
    codes = rows;
    $("count").textContent = rows.length ? rows.length + " registrati" : "";

    var names = [];
    rows.forEach(function (r) {
      if (r.account && names.indexOf(r.account) < 0) names.push(r.account);
    });
    var dl = $("accounts");
    dl.textContent = "";
    names.forEach(function (n) {
      var o = document.createElement("option"); o.value = n; dl.appendChild(o);
    });

    var list = $("list");
    list.textContent = "";
    if (!rows.length) {
      var empty = document.createElement("div");
      empty.className = "empty-state";
      empty.textContent = "Nessun dispositivo. Scrivi qui sopra il codice che ti hanno letto e salvalo.";
      list.appendChild(empty);
      return;
    }

    var groups = {};
    var order = [];
    rows.forEach(function (r) {
      var key = r.account || "";
      if (!groups[key]) { groups[key] = []; order.push(key); }
      groups[key].push(r);
    });
    order.sort(function (a, b) {
      if (!a) return 1;
      if (!b) return -1;
      return a.localeCompare(b);
    });
    order.forEach(function (k) { list.appendChild(accountBlock(k, groups[k])); });
  }

  function reload() {
    return api('codes').then(function (data) {
      render(data.codes || []);
      drawHash();
    });
  }

  /* ---------- boot ---------- */
  drawDial();
  if (token) {
    signIn(token).catch(function () { signOut(); });
  } else {
    $('token').focus();
  }
})();
</script>
</body>
</html>`;
