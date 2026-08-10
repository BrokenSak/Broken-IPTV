/**
 * The owner's panel, served at /admin.
 *
 * Design brief: the page has two jobs and they are not symmetric, so the layout
 * says so.
 *   * "Papà ha cambiato password" — fix an **utenza** once and it lands on
 *     every device hanging off it. No code needed, doable months later. This is
 *     the body of the page.
 *   * "Mia madre mi legge dodici caratteri" — register a device. This needs the
 *     code read out loud, because the casellina that tells a device which
 *     utenza it belongs to can only be encrypted with it. So the dial isn't a
 *     hero block any more: you pull it out **inside** the utenza you are adding
 *     the device to, which is also why the page never asks "which utenza?".
 *
 * Greyscale and glass, like the app. The page is public HTML; nothing behind it
 * loads without the admin token, which the browser keeps in localStorage and
 * sends as a bearer header.
 *
 * ⚠️ The token is also the **master key**: every utenza's code is
 * HMAC-SHA256(ADMIN_TOKEN, utenza id), derived here in the browser and stored
 * nowhere. That is what lets this page decrypt a playlist to show it back, and
 * it is why changing the secret orphans every device already configured.
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
    background:
      radial-gradient(120% 55% at 50% -10%, rgba(255,255,255,.08), transparent 60%),
      var(--ink);
  }
  .wrap { max-width: 760px; margin: 0 auto; padding: 0 20px 90px; }

  header {
    display: flex; align-items: center; gap: 10px;
    padding: 18px 0; margin-bottom: 30px;
    border-bottom: 1px solid var(--edge);
  }
  .mark {
    width: 26px; height: 26px; border-radius: 8px; background: #fff;
    display: grid; place-items: center; flex: none;
  }
  .mark svg { width: 12px; height: 12px; fill: #000; margin-left: 1px; }
  header h1 { font-size: 15px; font-weight: 600; letter-spacing: -.01em; margin: 0; }
  header .sp { flex: 1; }

  .section-head {
    display: flex; align-items: center; gap: 12px; margin: 0 2px 14px;
  }
  .section-head h2 {
    font-size: 12px; font-weight: 600; letter-spacing: .08em;
    text-transform: uppercase; color: var(--muted); margin: 0;
  }
  .section-head .sp { flex: 1; }
  .section-head + .section-head { margin-top: 46px; }
  .section-gap { margin-top: 46px; }

  /* ---- buttons ---- */
  button {
    font: inherit; font-size: 14px; font-weight: 600;
    padding: 11px 18px; border-radius: 11px; cursor: pointer;
    background: #fff; color: #000; border: 1px solid #fff;
    transition: opacity .15s ease, background .15s ease;
  }
  button:hover { opacity: .86; }
  button.ghost { background: transparent; color: var(--text); border-color: var(--edge); }
  button.ghost:hover { background: var(--glass); opacity: 1; }
  button.small { padding: 7px 13px; font-size: 12.5px; border-radius: 9px; }
  button:disabled { opacity: .35; cursor: default; }
  .actions { display: flex; gap: 10px; align-items: center; flex-wrap: wrap; }

  /* ---- utenza card ---- */
  .acct {
    background: var(--panel);
    border: 1px solid var(--edge);
    border-radius: var(--r);
    padding: 18px;
    margin-bottom: 14px;
  }
  .acct-top { display: flex; align-items: flex-start; gap: 14px; }
  .acct-id { flex: 1; min-width: 0; }
  .acct-name { font-size: 17px; font-weight: 600; letter-spacing: -.01em; }
  .acct-creds {
    font-family: var(--mono); font-size: 12px; color: var(--muted);
    margin-top: 5px; overflow-wrap: anywhere;
  }
  .acct-creds.none { font-family: var(--sans); font-style: italic; }

  .tag {
    font-size: 11px; padding: 4px 9px; border-radius: 999px;
    border: 1px solid var(--edge); color: var(--muted); white-space: nowrap;
  }
  .tag.on { background: #fff; color: #000; border-color: #fff; font-weight: 600; }

  /* ---- devices inside a card ---- */
  .devs { margin-top: 16px; border-top: 1px solid var(--edge); padding-top: 6px; }
  .dev {
    display: flex; align-items: center; gap: 12px;
    padding: 11px 2px;
  }
  .dev + .dev { border-top: 1px solid rgba(255,255,255,.06); }
  .dev .who { flex: 1; min-width: 0; }
  .dev .name { font-size: 14px; }
  .dev .meta { font-size: 11.5px; color: var(--muted); margin-top: 3px; font-family: var(--mono); }
  /* The name is a field, but a row of fields reads as a form and this is a
     list. So it looks like text until you go near it. */
  .dev input[type=text] {
    max-width: 280px; padding: 6px 9px; margin-left: -9px;
    background: transparent; border-color: transparent;
  }
  .dev input[type=text]:hover { border-color: var(--edge); }
  .dev input[type=text]:focus { background: rgba(255,255,255,.06); }
  .dev-none { font-size: 13px; color: var(--muted); padding: 12px 2px; }

  /* ---- forms ---- */
  .editor {
    margin-top: 16px; padding-top: 16px;
    border-top: 1px solid var(--edge);
    display: flex; flex-direction: column; gap: 13px;
  }
  label { display: block; font-size: 12px; color: var(--muted); margin: 0 0 6px; }
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
  .row2 { display: grid; grid-template-columns: 1fr 1fr; gap: 13px; }
  @media (max-width: 560px) { .row2 { grid-template-columns: 1fr; } }
  .pw { display: flex; gap: 8px; align-items: center; }
  .pw input { flex: 1; }
  .note {
    font-size: 12.5px; color: var(--muted); line-height: 1.5; margin: 0;
  }

  /* State is shape, not colour: filled = on, hairline = off (the same language
     as the selected playlist in the app). */
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

  /* ---- the dial: twelve slots, grouped like the app prints the code ---- */
  .dial-shell { position: relative; }
  .dial {
    display: flex; align-items: center; gap: 4px; flex-wrap: nowrap;
    padding: 13px 11px;
    background: var(--glass);
    border: 1px solid var(--edge);
    border-radius: 13px;
    backdrop-filter: blur(20px);
    transition: border-color .18s ease, background .18s ease;
  }
  .dial-shell:focus-within .dial { border-color: var(--edge-hi); background: var(--glass-hi); }
  .cell {
    flex: 1 1 0; min-width: 0;
    text-align: center;
    font-family: var(--mono);
    font-size: clamp(16px, 4.4vw, 25px);
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
  .dial-said { font-size: 12.5px; color: var(--muted); min-height: 17px; line-height: 1.4; }

  .empty-state { color: var(--muted); font-size: 13.5px; padding: 6px 2px 22px; line-height: 1.6; }

  .toast {
    position: fixed; left: 50%; bottom: 26px; transform: translate(-50%, 20px);
    background: #fff; color: #000; font-size: 13.5px; font-weight: 600;
    padding: 11px 18px; border-radius: 999px;
    opacity: 0; pointer-events: none; transition: opacity .2s ease, transform .2s ease;
    max-width: calc(100% - 40px); text-align: center;
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
    <button class="ghost small" id="logout">Esci</button>
  </header>

  <div class="section-head">
    <h2>Utenze</h2>
    <div class="sp"></div>
    <button class="ghost small" id="move-host">Cambia indirizzo</button>
    <button class="small" id="new-account">Nuova utenza</button>
  </div>
  <div id="accounts"></div>

  <div id="loose"></div>
</div>

<div class="toast" id="toast"></div>

<script>
(function () {
  var $ = function (id) { return document.getElementById(id); };
  var TOKEN_KEY = 'brokeniptv.admin.token';
  var token = localStorage.getItem(TOKEN_KEY) || '';

  /* The alphabet the app uses for codes: no O/0, no I/1, so a code can be read
     off a screen and typed on a remote. 32 symbols, and 256 % 32 === 0, so
     taking a byte modulo 32 is unbiased. */
  var ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  var state = { accounts: [], devices: [] };
  /* Which card is expanded, so a reload doesn't collapse what you were doing.
     'edit:<id>' | 'add:<id>' | 'new' */
  var open = '';

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
        if (!r.ok) throw new Error(message(b && b.error));
        return b;
      });
    });
  }

  function message(code) {
    if (code === 'unknown_account') return 'Questa utenza non esiste più. Ricarica la pagina.';
    if (code === 'unknown_code') return 'Questo dispositivo non è registrato.';
    if (code === 'bad_code') return 'Il codice ha dodici caratteri.';
    if (code === 'bad_name') return 'Serve il nome dell’utenza.';
    return code || 'Qualcosa non ha funzionato.';
  }

  function toast(text) {
    var t = $('toast');
    t.textContent = text;
    t.classList.add('show');
    clearTimeout(t._timer);
    t._timer = setTimeout(function () { t.classList.remove('show'); }, 3000);
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
    return reload().then(function () {
      localStorage.setItem(TOKEN_KEY, token);
      $('gate').classList.add('hidden');
      $('panel').classList.remove('hidden');
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

  /* ---------- crypto ----------
     Two derivations, both from things this page already has:

       utenza code = HMAC-SHA256(token, 'broken-iptv-account:' + id) -> 12
         symbols of the app's alphabet. Never stored, recomputed on every
         render: the database alone opens nothing, the token opens everything.
       payload key = SHA-256('broken-iptv-provision:' + code)
         The app derives the same one. Codes are 12 chars of a 32-symbol
         alphabet (~60 bits) from a secure generator, so stretching buys
         nothing a brute force could not already ignore — and a Firestick
         doesn't spend a second of CPU at every launch. */
  function bytes(text) { return new TextEncoder().encode(text); }

  function hex(buffer) {
    var view = new Uint8Array(buffer), out = '';
    for (var i = 0; i < view.length; i++) out += ('0' + view[i].toString(16)).slice(-2);
    return out;
  }

  function rowId(code) {
    return crypto.subtle.digest('SHA-256', bytes('broken-iptv-sync:' + code)).then(hex);
  }

  function newAccountId() {
    return hex(crypto.getRandomValues(new Uint8Array(16)));
  }

  function accountCode(accountId) {
    return crypto.subtle
      .importKey('raw', bytes(token), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'])
      .then(function (key) {
        return crypto.subtle.sign('HMAC', key, bytes('broken-iptv-account:' + accountId));
      })
      .then(function (mac) {
        var view = new Uint8Array(mac), out = '';
        for (var i = 0; i < 12; i++) out += ALPHABET[view[i] % 32];
        return out;
      });
  }

  function keyFor(code, usage) {
    return crypto.subtle.digest('SHA-256', bytes('broken-iptv-provision:' + code))
      .then(function (raw) {
        return crypto.subtle.importKey('raw', raw, 'AES-GCM', false, [usage]);
      });
  }

  function encrypt(code, payload) {
    return keyFor(code, 'encrypt').then(function (key) {
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

  /* Reading a playlist back is not a bonus feature, it is what makes the card
     editable: without it "cambia solo l'indirizzo" would mean retyping the
     password from memory. It works because the token is the master key. */
  function decrypt(code, base64) {
    return keyFor(code, 'decrypt').then(function (key) {
      var binary = atob(base64);
      var raw = new Uint8Array(binary.length);
      for (var i = 0; i < binary.length; i++) raw[i] = binary.charCodeAt(i);
      return crypto.subtle.decrypt(
        { name: 'AES-GCM', iv: raw.slice(0, 12) }, key, raw.slice(12)
      );
    }).then(function (clear) {
      return JSON.parse(new TextDecoder().decode(clear));
    }).catch(function () { return null; });
  }

  /* ---------- small helpers ---------- */
  function el(tag, className, text) {
    var node = document.createElement(tag);
    if (className) node.className = className;
    if (text != null) node.textContent = text;
    return node;
  }

  function field(labelText, input) {
    var box = el('div');
    var lab = el('label', null, labelText);
    lab.setAttribute('for', input.id || '');
    box.appendChild(lab);
    box.appendChild(input);
    return box;
  }

  function textInput(value, placeholder) {
    var input = document.createElement('input');
    input.type = 'text';
    input.value = value || '';
    input.placeholder = placeholder || '';
    input.autocomplete = 'off';
    return input;
  }

  function ago(ms) {
    if (!ms) return 'mai';
    var s = Math.floor((Date.now() - ms) / 1000);
    if (s < 90) return 'poco fa';
    if (s < 5400) return Math.round(s / 60) + ' min fa';
    if (s < 172800) return Math.round(s / 3600) + ' ore fa';
    return Math.round(s / 86400) + ' giorni fa';
  }

  function devicesOf(accountId) {
    return state.devices.filter(function (d) { return d.account_id === accountId; });
  }

  function plural(n, one, many) { return n + ' ' + (n === 1 ? one : many); }

  /* ---------- the dial ---------- */
  /* Twelve slots, grouped the way the app prints the code, so what you type
     looks like what is being read to you. */
  function dial(onReady) {
    var shell = el('div', 'dial-shell');
    var cells = el('div', 'dial');
    var input = document.createElement('input');
    input.setAttribute('inputmode', 'latin');
    input.setAttribute('autocapitalize', 'characters');
    input.setAttribute('spellcheck', 'false');
    input.autocomplete = 'off';
    input.maxLength = 20;
    input.setAttribute('aria-label', 'Codice del dispositivo');

    function value() {
      return input.value.toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 12);
    }

    function draw() {
      var code = value();
      cells.textContent = '';
      for (var i = 0; i < 12; i++) {
        if (i === 4 || i === 8) cells.appendChild(el('span', 'sep', '–'));
        var filled = i < code.length;
        var cell = el('span', 'cell' + (filled ? '' : ' empty') +
          (i === code.length && document.activeElement === input ? ' active' : ''),
          filled ? code[i] : '·');
        cells.appendChild(cell);
      }
    }

    input.addEventListener('input', function () {
      input.value = value();
      draw();
      onReady(value());
    });
    input.addEventListener('focus', draw);
    input.addEventListener('blur', draw);
    cells.addEventListener('click', function () { input.focus(); });

    shell.appendChild(cells);
    shell.appendChild(input);
    draw();
    shell.focusField = function () { input.focus(); };
    shell.value = value;
    return shell;
  }

  /* ---------- utenza: the editor ---------- */
  /* One form for "nuova" and "modifica": the difference is only whether we
     already have an id, and whether the fields arrive from the stored blob. */
  function accountEditor(account) {
    var isNew = !account;
    var id = isNew ? newAccountId() : account.id;

    var box = el('div', 'editor');
    var name = textInput(isNew ? '' : account.name, 'mamma');
    var host = textInput('', 'http://esempio.tv:8080');
    var user = textInput('', 'utente');

    var pass = document.createElement('input');
    pass.type = 'password';
    pass.autocomplete = 'new-password';
    pass.placeholder = 'password';
    var reveal = el('button', 'ghost small', 'Mostra');
    reveal.type = 'button';
    reveal.addEventListener('click', function () {
      var hidden = pass.type === 'password';
      pass.type = hidden ? 'text' : 'password';
      reveal.textContent = hidden ? 'Nascondi' : 'Mostra';
    });
    var pwRow = el('div', 'pw');
    pwRow.appendChild(pass);
    pwRow.appendChild(reveal);

    var sync = document.createElement('input');
    sync.type = 'checkbox';
    sync.checked = !isNew && !!account.sync_enabled;
    var track = el('span', 'track');
    track.appendChild(el('span', 'knob'));
    var switchBox = el('label', 'switch');
    var lbl = el('span', 'lbl', 'Preferiti condivisi');
    lbl.appendChild(el('small', null,
      'I suoi dispositivi vedono gli stessi preferiti e lo stesso "Continua a guardare".'));
    switchBox.appendChild(sync);
    switchBox.appendChild(track);
    switchBox.appendChild(lbl);

    var save = el('button', null, isNew ? 'Crea utenza' : 'Salva e invia ai dispositivi');
    var cancel = el('button', 'ghost', 'Annulla');
    var actions = el('div', 'actions');
    actions.appendChild(save);
    actions.appendChild(cancel);

    if (!isNew) {
      // Pushed away from Salva/Annulla: it is the one button here you cannot
      // undo, and it should not sit under the thumb that reaches for Annulla.
      var spacer = el('div');
      spacer.style.flex = '1';
      actions.appendChild(spacer);
      var remove = el('button', 'ghost', 'Rimuovi utenza');
      remove.addEventListener('click', function () {
        var n = devicesOf(id).length;
        if (!confirm('Rimuovere ' + account.name + '? ' +
          (n ? plural(n, 'dispositivo resta', 'dispositivi restano') + ' senza playlist.'
             : 'Non ha dispositivi.'))) return;
        api('forget-account', { method: 'POST', body: { id: id } })
          .then(function () { open = ''; toast('Utenza rimossa'); return reload(); })
          .catch(function (e) { toast(e.message); });
      });
      actions.appendChild(remove);
    }

    box.appendChild(field('Nome dell’utenza', name));
    box.appendChild(field('Indirizzo del pannello', host));
    var creds = el('div', 'row2');
    creds.appendChild(field('Utente', user));
    creds.appendChild(field('Password', pwRow));
    box.appendChild(creds);
    box.appendChild(switchBox);
    box.appendChild(el('p', 'note',
      'Salvando, la playlist riparte verso tutti i dispositivi di questa utenza: la ' +
      'ricevono alla prima apertura dell’app.'));
    box.appendChild(actions);

    /* Prefill from what is stored. The blob is encrypted with the utenza's
       code, which this page can derive — so the form opens on the real
       credentials instead of asking for them again. */
    if (!isNew && account.data) {
      accountCode(id)
        .then(function (code) { return decrypt(code, account.data); })
        .then(function (payload) {
          if (!payload) {
            toast('La playlist di ' + account.name + ' non si apre con questo token.');
            return;
          }
          host.value = payload.host || '';
          user.value = payload.username || '';
          pass.value = payload.password || '';
        });
    }

    save.addEventListener('click', function () {
      var label = name.value.trim();
      if (!label) { toast('Serve il nome dell’utenza.'); return; }
      var address = host.value.trim();
      var username = user.value.trim();
      if ((address || username) && !(address && username)) {
        toast('Servono sia l’indirizzo sia l’utente.');
        return;
      }
      save.disabled = true;
      accountCode(id).then(function (code) {
        return Promise.all([
          rowId(code),
          address ? encrypt(code, JSON.stringify({
            host: address, username: username, password: pass.value,
            name: label, at: Date.now()
          })) : null
        ]);
      }).then(function (parts) {
        return api('account', { method: 'POST', body: {
          id: id, name: label, syncId: parts[0],
          syncEnabled: sync.checked, data: parts[1]
        } });
      }).then(function () {
        open = '';
        toast(isNew ? 'Utenza creata' : 'Playlist inviata ai dispositivi');
        return reload();
      }).catch(function (e) {
        save.disabled = false;
        toast(e.message);
      });
    });

    cancel.addEventListener('click', function () { open = ''; render(); });
    setTimeout(function () { name.focus(); }, 0);
    return box;
  }

  /* ---------- utenza: adding a device ---------- */
  /* The only flow that needs the code read out loud, so it is the only place
     with a dial. What gets written is the *casellina*: which utenza this
     device belongs to, encrypted with its own code. */
  function deviceAdder(account) {
    var box = el('div', 'editor');
    var said = el('div', 'dial-said', 'Fattelo leggere dallo schermo del dispositivo.');
    var name = textInput('', 'Firestick del salotto');
    var link = el('button', null, 'Collega a ' + account.name);
    link.disabled = true;
    var cancel = el('button', 'ghost', 'Annulla');

    var pad = dial(function (code) {
      link.disabled = code.length !== 12;
      if (code.length !== 12) {
        said.textContent = 'Fattelo leggere dallo schermo del dispositivo.';
        return;
      }
      /* Say something true about the code as soon as it is complete: the same
         hash the server stores is what tells us we already know this device. */
      rowId(code).then(function (id) {
        var known = state.devices.filter(function (d) { return d.id === id; })[0];
        if (!known) { said.textContent = 'Dispositivo nuovo.'; return; }
        var owner = state.accounts.filter(function (a) { return a.id === known.account_id; })[0];
        if (!owner) {
          said.textContent = 'Già registrato (' + (known.note || 'senza nome') + '), senza utenza.';
        } else if (owner.id === account.id) {
          said.textContent = 'È già di ' + account.name + ': lo aggiorni.';
        } else {
          said.textContent = 'Ora è di ' + owner.name + ': passa a ' + account.name + '.';
        }
        if (known.note && !name.value) name.value = known.note;
      });
    });

    link.addEventListener('click', function () {
      var code = pad.value();
      link.disabled = true;
      accountCode(account.id).then(function (shared) {
        return encrypt(code, JSON.stringify({
          account: shared, accountId: account.id, at: Date.now()
        }));
      }).then(function (casellina) {
        return api('device', { method: 'POST', body: {
          code: code, accountId: account.id,
          note: name.value.trim(), casellina: casellina
        } });
      }).then(function () {
        open = '';
        toast('Dispositivo collegato a ' + account.name);
        return reload();
      }).catch(function (e) { link.disabled = false; toast(e.message); });
    });
    cancel.addEventListener('click', function () { open = ''; render(); });

    box.appendChild(field('Codice del dispositivo', pad));
    box.appendChild(said);
    box.appendChild(field('Come si chiama', name));
    box.appendChild(el('p', 'note',
      'Il codice serve solo adesso: da qui in poi il dispositivo si riconosce da solo, e ' +
      'le correzioni alla playlist gli arrivano senza chiederglielo di nuovo.'));
    var actions = el('div', 'actions');
    actions.appendChild(link);
    actions.appendChild(cancel);
    box.appendChild(actions);

    setTimeout(function () { pad.focusField(); }, 0);
    return box;
  }

  /* ---------- moving everybody to a new address ---------- */
  /* When the provider changes domain, every utenza on it is wrong at once —
     and editing them one card at a time is exactly the work this panel exists
     to avoid. Possible because this page can open all of them: it re-encrypts
     each playlist with the new address and leaves its own utente e password
     alone. */
  function hostChanger() {
    var box = el('div', 'editor');
    var found = el('p', 'note', 'Apro le playlist...');
    var from = textInput('', 'vuoto = tutte');
    var to = textInput('', 'http://nuovo.tv:8080');
    var apply = el('button', null, 'Aggiorna');
    var cancel = el('button', 'ghost', 'Annulla');
    apply.disabled = true;

    /* [{ account, code, payload }] for every utenza whose playlist opens. */
    var opened = [];

    function matching() {
      var wanted = from.value.trim();
      return opened.filter(function (o) { return !wanted || o.payload.host === wanted; });
    }

    function refresh() {
      var n = matching().length;
      apply.disabled = !to.value.trim() || !n;
      apply.textContent = n === 1 ? 'Aggiorna 1 utenza' : 'Aggiorna ' + n + ' utenze';
    }
    from.addEventListener('input', refresh);
    to.addEventListener('input', refresh);

    Promise.all(state.accounts.filter(function (a) { return a.data; }).map(function (a) {
      return accountCode(a.id)
        .then(function (code) {
          return decrypt(code, a.data).then(function (payload) {
            return payload ? { account: a, code: code, payload: payload } : null;
          });
        });
    })).then(function (rows) {
      opened = rows.filter(Boolean);
      var counts = {}, order = [];
      opened.forEach(function (o) {
        if (!counts[o.payload.host]) { counts[o.payload.host] = 0; order.push(o.payload.host); }
        counts[o.payload.host]++;
      });
      if (!order.length) {
        found.textContent = 'Nessuna playlist da spostare.';
        return;
      }
      order.sort(function (a, b) { return counts[b] - counts[a]; });
      found.textContent = 'In uso: ' + order.map(function (h) {
        return h + ' (' + counts[h] + ')';
      }).join(' · ');
      from.value = order[0];
      refresh();
    });

    apply.addEventListener('click', function () {
      var address = to.value.trim();
      var rows = matching();
      apply.disabled = true;
      /* One at a time: a handful of utenze, and a failure halfway through
         should say which ones already moved. */
      var done = 0;
      rows.reduce(function (chain, o) {
        return chain.then(function () {
          return encrypt(o.code, JSON.stringify({
            host: address,
            username: o.payload.username,
            password: o.payload.password,
            name: o.payload.name || o.account.name,
            at: Date.now()
          })).then(function (data) {
            return api('account', { method: 'POST', body: {
              id: o.account.id, name: o.account.name, syncId: o.account.sync_id,
              syncEnabled: !!o.account.sync_enabled, data: data
            } });
          }).then(function () { done++; });
        });
      }, Promise.resolve()).then(function () {
        open = '';
        toast('Indirizzo aggiornato su ' + done + (done === 1 ? ' utenza' : ' utenze'));
        return reload();
      }).catch(function (e) {
        toast('Aggiornate ' + done + ' su ' + rows.length + '. ' + e.message);
        apply.disabled = false;
      });
    });
    cancel.addEventListener('click', function () { open = ''; render(); });

    box.appendChild(found);
    var pair = el('div', 'row2');
    pair.appendChild(field('Indirizzo da sostituire', from));
    pair.appendChild(field('Nuovo indirizzo', to));
    box.appendChild(pair);
    box.appendChild(el('p', 'note',
      'Utente e password di ognuna restano quelli che sono: cambia solo l’indirizzo. ' +
      'Ogni dispositivo lo riceve alla prima apertura.'));
    var actions = el('div', 'actions');
    actions.appendChild(apply);
    actions.appendChild(cancel);
    box.appendChild(actions);
    setTimeout(function () { to.focus(); }, 0);
    return box;
  }

  /* ---------- rows ---------- */
  function deviceRow(device) {
    var row = el('div', 'dev');
    var who = el('div', 'who');
    var name = textInput(device.note || '', 'Senza nome');
    name.addEventListener('change', function () {
      api('device-edit', { method: 'POST', body: { id: device.id, note: name.value.trim() } })
        .then(function () { toast('Nome aggiornato'); return reload(); })
        .catch(function (e) { toast(e.message); });
    });
    who.appendChild(name);
    who.appendChild(el('div', 'meta',
      device.id.slice(0, 12) + ' · visto ' + ago(device.last_seen) +
      (device.has_casellina ? '' : ' · senza casellina')));

    var forget = el('button', 'ghost small', 'Rimuovi');
    forget.addEventListener('click', function () {
      if (!confirm('Rimuovere "' + (device.note || 'questo dispositivo') +
        '"? Torna com’era appena installato.')) return;
      api('forget-device', { method: 'POST', body: { id: device.id } })
        .then(function () { toast('Dispositivo rimosso'); return reload(); })
        .catch(function (e) { toast(e.message); });
    });

    row.appendChild(who);
    row.appendChild(forget);
    return row;
  }

  function accountCard(account) {
    var card = el('div', 'acct');
    var devices = devicesOf(account.id);

    var top = el('div', 'acct-top');
    var idBox = el('div', 'acct-id');
    idBox.appendChild(el('div', 'acct-name', account.name));

    /* The summary line is the credentials, in mono, because that is what you
       came to check. The password is not shown until you open the editor. */
    var summary = el('div', 'acct-creds');
    if (account.data) {
      summary.textContent = 'playlist inviata ' + ago(account.updated_at);
      accountCode(account.id)
        .then(function (code) { return decrypt(code, account.data); })
        .then(function (payload) {
          if (!payload) { summary.textContent = 'playlist illeggibile con questo token'; return; }
          summary.textContent = payload.host + ' · ' + payload.username;
        });
    } else {
      summary.className = 'acct-creds none';
      summary.textContent = 'Nessuna playlist: i suoi dispositivi restano fermi.';
    }
    idBox.appendChild(summary);
    top.appendChild(idBox);

    // Only the state you can't see anywhere else: how many devices there are
    // is the list right below.
    if (account.sync_enabled) top.appendChild(el('span', 'tag on', 'preferiti condivisi'));
    card.appendChild(top);

    var devBox = el('div', 'devs');
    if (devices.length) {
      devices.forEach(function (d) { devBox.appendChild(deviceRow(d)); });
    } else {
      devBox.appendChild(el('div', 'dev-none',
        'Nessun dispositivo. Serve il codice che mostra la sua app.'));
    }
    card.appendChild(devBox);

    if (open === 'edit:' + account.id) {
      card.appendChild(accountEditor(account));
    } else if (open === 'add:' + account.id) {
      card.appendChild(deviceAdder(account));
    } else {
      var actions = el('div', 'actions');
      actions.style.marginTop = '14px';
      var edit = el('button', 'ghost small', 'Playlist e nome');
      edit.addEventListener('click', function () { open = 'edit:' + account.id; render(); });
      var add = el('button', 'small', 'Aggiungi dispositivo');
      add.addEventListener('click', function () { open = 'add:' + account.id; render(); });
      actions.appendChild(add);
      actions.appendChild(edit);
      card.appendChild(actions);
    }
    return card;
  }

  /* Devices registered before utenze existed, or left behind when one was
     removed. They can't be moved from here: hooking a device to an utenza
     means writing its casellina, and that needs its code. */
  function looseSection(devices) {
    var box = el('div');
    var head = el('div', 'section-head section-gap');
    head.appendChild(el('h2', null, 'Senza utenza'));
    box.appendChild(head);

    var card = el('div', 'acct');
    card.appendChild(el('p', 'note',
      'Per collegarli serve di nuovo il loro codice: aprilo da "Aggiungi dispositivo" ' +
      'nell’utenza giusta. Finché restano qui non ricevono nessuna playlist.'));
    var devBox = el('div', 'devs');
    devices.forEach(function (d) { devBox.appendChild(deviceRow(d)); });
    card.appendChild(devBox);
    box.appendChild(card);
    return box;
  }

  /* ---------- render ---------- */
  function render() {
    var list = $('accounts');
    list.textContent = '';

    if (open === 'new') {
      var fresh = el('div', 'acct');
      fresh.appendChild(el('div', 'acct-name', 'Nuova utenza'));
      fresh.appendChild(accountEditor(null));
      list.appendChild(fresh);
    }

    if (open === 'host') {
      var moving = el('div', 'acct');
      moving.appendChild(el('div', 'acct-name', 'Cambia indirizzo'));
      moving.appendChild(el('div', 'acct-creds none',
        'Il pannello ha cambiato dominio? Riscrivilo su tutte le utenze in un colpo.'));
      moving.appendChild(hostChanger());
      list.appendChild(moving);
    }

    if (!state.accounts.length && open !== 'new') {
      list.appendChild(el('div', 'empty-state',
        'Nessuna utenza. Creane una con il nome della persona e i dati del suo ' +
        'abbonamento: i dispositivi si agganciano dopo, uno alla volta.'));
    }

    state.accounts.forEach(function (a) { list.appendChild(accountCard(a)); });

    var loose = $('loose');
    loose.textContent = '';
    var orphans = state.devices.filter(function (d) { return !d.account_id; });
    if (orphans.length) loose.appendChild(looseSection(orphans));
  }

  $('new-account').addEventListener('click', function () {
    open = 'new';
    render();
  });

  $('move-host').addEventListener('click', function () {
    open = open === 'host' ? '' : 'host';
    render();
  });

  function reload() {
    return api('state').then(function (data) {
      state.accounts = data.accounts || [];
      state.devices = data.devices || [];
      render();
    });
  }

  /* ---------- boot ---------- */
  if (token) {
    signIn(token).catch(function () { signOut(); });
  } else {
    $('token').focus();
  }
})();
</script>
</body>
</html>`;
