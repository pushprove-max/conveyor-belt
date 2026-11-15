// SPDX-License-Identifier: Apache-2.0
// The account page (account.html): the logged-in user's own password, authenticator codes and trusted devices (GET and
// POST /me) and, for an admin only, the Users panel (GET and POST /users): every user with when they were created and
// last logged in, their authenticator codes and devices; add a user (a one-time setup link, 24 h, so no password is
// shown or sent), make a user admin or member, reset a password (a new setup link; ends their sessions), turn off
// their authenticator codes, revoke a device or all of them, remove a user; and, in a panel of its own, the "No login
// on this device" switch. Opened as "this device" (no login), the account shows its name alone and the Users panel
// leads. Make member and Remove are not offered on your own row or on the last admin, and turning "No login on this
// device" off takes a second click: these are the controls that can lock you out. Every Users action acts on a second
// click that names its consequence, never a browser dialog. Times are local, as on the Board.
// The server refuses a member every /users route (403); the panels are asked for only when /me says admin, so a
// member is never shown them. Everything the server sent reaches the page as text, never as markup.
(function () {
  'use strict';
  const byId = (id) => document.getElementById(id);
  function h(tag, cls, text) {
    const el = document.createElement(tag);
    if (cls) el.className = cls;
    if (text !== undefined && text !== null) el.textContent = String(text);
    return el;
  }
  const chip = (text, tone) => h('span', `chip chip-${tone}`, text);
  // A stored time, in local time as the Board's main page shows it: the time of day, with the date when it is not
  // today (and the year when it is not this year).
  function when(t) {
    const ms = typeof t === 'string' ? Date.parse(t) : NaN;
    if (Number.isNaN(ms)) return 'never';
    const d = new Date(ms), today = new Date();
    const time = d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
    if (d.toDateString() === today.toDateString()) return time;
    return `${d.toLocaleDateString([], { month: 'short', day: 'numeric', ...(d.getFullYear() === today.getFullYear() ? {} : { year: 'numeric' }) })}, ${time}`;
  }
  const note = (text) => { byId('note').textContent = text; };
  function button(text, label, onClick, cls) {
    const b = h('button', `btn ${cls || 'btn-quiet'}`, text);
    b.type = 'button'; b.setAttribute('aria-label', label);
    b.addEventListener('click', onClick);
    return b;
  }
  function field(name, type) {
    const f = h('input', 'field');
    f.name = name; f.type = type; f.required = true;
    if (type === 'password') { f.minLength = 8; f.autocomplete = 'new-password'; }
    return f;
  }
  // A field with its name shown above it, which stays while the field is typed in.
  function labelled(text, input) {
    const l = h('label', 'field-label');
    l.append(h('span', null, text), input);
    return l;
  }
  function loggedOut(r) { if (r.status === 401) window.location.assign('/login'); return r; }
  function get(path) { return window.fetch(path).then(loggedOut).then((r) => (r.ok ? r.json() : r.text().then((t) => Promise.reject(new Error(t.trim() || `the server answered ${r.status}`))))); }
  // A write; then(ok, text, data): the server's answer.
  function send(path, body) {
    return window.fetch(path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }).then(loggedOut)
      .then((r) => (/json/.test(r.headers.get('Content-Type') || '') ? r.json().then((d) => ({ ok: r.ok, data: d, text: '' })) : r.text().then((t) => ({ ok: r.ok, data: null, text: t.trim() }))))
      .catch(() => ({ ok: false, data: null, text: 'the server did not answer' }));
  }
  // Trusted devices, one a line: its name, when it was trusted and last used, and its own Revoke. With ask (another
  // user's device), Revoke acts on a second click whose words are ask(device).
  function devices(list, revoke, ask) {
    if (!list.length) return h('p', 'foot', 'No trusted device.');
    const ul = h('ul', 'rows compact devices');
    list.forEach((d) => {
      const li = h('li', 'row'), main = h('div', 'row-main');
      main.append(h('span', 'title', d.label || 'device'), h('span', 'foot', `trusted ${when(d.created)}, last used ${d.used ? when(d.used) : 'not recorded'}`),
        ask ? final('Revoke', `Revoke the device ${d.label || d.id}`, ask(d), () => revoke(d)) : button('Revoke', `Revoke the device ${d.label || d.id}`, () => revoke(d)));
      li.append(main);
      ul.append(li);
    });
    return ul;
  }
  function facts(u) {
    const meta = h('p', 'row-meta');
    meta.append(chip(u.role === 'admin' ? 'Admin' : 'Member', u.role === 'admin' ? 'info' : 'quiet'), chip(u.mfa ? 'Authenticator codes on' : 'Authenticator codes off', u.mfa ? 'ok' : 'quiet'));
    if (!u.password) meta.append(chip('Waiting for its setup link', 'warn'));
    meta.append(h('span', null, `Created ${when(u.created)}`), h('span', null, `Last login ${when(u.lastLogin)}`),
      h('span', null, `${u.devices.length} ${u.devices.length === 1 ? 'device' : 'devices'}`));
    return meta;
  }

  // ---- Your account ----
  function drawMe(u) {
    const body = byId('me-body');
    const head = h('div', 'row-main');
    head.append(h('span', 'title', u.user));
    // "this device" (the Board's own machine, let in with no login) has no password, authenticator or devices.
    if (u.local) {
      const meta = h('p', 'row-meta');
      meta.append(chip('Admin', 'info'));
      body.replaceChildren(head, meta, h('p', 'foot', 'Opened on the machine the Board runs on: no login is needed here.'));
      return;
    }
    const pw = h('form', 'row-meta'), old = field('old', 'password'), nw = field('new', 'password'), again = field('again', 'password');
    old.autocomplete = 'current-password';
    const save = h('button', 'btn btn-primary', 'Change password');
    save.type = 'submit';
    pw.append(labelled('Current password', old), labelled('New password', nw), labelled('New password again', again), save);
    pw.addEventListener('submit', (e) => {
      e.preventDefault();
      if (nw.value !== again.value) { note('The two new passwords differ.'); return; }
      send('me', { action: 'password', old: old.value, new: nw.value }).then((r) => {
        // A new password ends this user's sessions, this one too: log in again with it.
        if (r.ok) window.location.assign('/login'); else note(`Password not changed: ${r.text}`);
      });
    });
    const info = facts(u);
    const parts = [head, info, h('p', 'foot', 'Your trusted devices:'),
      devices(u.devices, (d) => send('me', { action: 'revoke', device: d.id }).then((r) => { note(r.ok ? 'Device revoked.' : `Not revoked: ${r.text}`); load(); }))];
    if (u.mfa) parts.push(button('Turn off authenticator codes', 'Turn off your authenticator codes', () => send('me', { action: 'mfa-off' }).then((r) => { note(r.ok ? 'Authenticator codes are off.' : `Authenticator codes not changed: ${r.text}`); load(); })));
    else {
      const mfa = h('div', 'mfa');
      mfa.append(h('p', 'foot', 'Authenticator codes are optional: with them on, a login asks for a code from an authenticator app (Google Authenticator or any other) after your password.'),
        button('Turn on authenticator codes', 'Turn on authenticator codes for your account', () => send('me', { action: 'mfa-setup' }).then((r) => {
          // Once the codes are on, the user's facts (and their row in the Users panel) say so while the recovery codes
          // are still on screen; a full reload would lose the codes.
          if (r.ok) mfaSetup(mfa, r.data, () => { info.replaceWith(facts({ ...u, mfa: true })); if (u.role === 'admin') loadUsers(); }); else note(`Authenticator codes not set up: ${r.text}`);
        })));
      parts.push(mfa);
    }
    parts.push(h('p', 'foot', 'Change your password (at least 8 characters). Your sessions end; your trusted devices stay.'), pw);
    body.replaceChildren(...parts);
  }

  // Authenticator setup: the QR of the new secret (GET /me/qr, an image of this host) and the secret as text, then one
  // code from the app turns the codes on; the 10 recovery codes are shown this once. The server keeps neither in a form
  // it shows again.
  function mfaSetup(box, d, turnedOn) {
    const qr = h('img', 'mfa-qr');
    qr.src = `me/qr?t=${Date.now()}`; qr.alt = 'QR code for your authenticator app'; qr.width = 216; qr.height = 216;
    const key = h('p', 'foot');
    key.append('Or enter this key in the app: ', h('code', 'mfa-key', d.secret.replace(/(.{4})/g, '$1 ').trim()));
    const form = h('form', 'row-meta'), code = field('code', 'text');
    code.inputMode = 'numeric'; code.autocomplete = 'one-time-code'; code.maxLength = 6; code.pattern = '[0-9]{6}';
    const on = h('button', 'btn btn-primary', 'Turn on authenticator codes');
    on.type = 'submit';
    form.append(labelled('Code from the app', code), on);
    form.addEventListener('submit', (e) => {
      e.preventDefault();
      send('me', { action: 'mfa-on', code: code.value.trim() }).then((r) => {
        if (!r.ok) { note(`Authenticator codes not turned on: ${r.text}`); code.value = ''; code.focus(); return; }
        note('Authenticator codes are on.');
        turnedOn();
        const list = h('ul', 'mfa-codes');
        r.data.recovery.forEach((c) => list.append(h('li', null, c)));
        box.replaceChildren(h('p', 'warn-note', 'Your recovery codes. Each one works once in place of a code, if you lose your phone. Keep them somewhere safe: they are not shown again.'),
          list, button('Done', 'Done: I have kept my recovery codes', load, 'btn-primary'));
      });
    });
    box.replaceChildren(h('p', 'foot', 'Scan this QR code with your authenticator app, then enter the 6-digit code it shows. The codes turn on once it is right.'),
      qr, key, form);
    code.focus();
  }

  // ---- Users (admin) ----
  // A change to a user cannot be undone from here: as on the Board, it acts on a second
  // click within ARM_MS, the first turning the button to its consequence. No browser dialog.
  const ARM_MS = 5000;
  function twice(b, ask, go) {
    const label = b.textContent;
    let timer = null;
    b.classList.add('btn-final');
    b.dataset.guard = 'final';
    const reset = () => { window.clearTimeout(timer); timer = null; b.textContent = label; b.setAttribute('aria-pressed', 'false'); };
    b.setAttribute('aria-pressed', 'false');
    b.addEventListener('click', () => {
      if (timer === null) { b.textContent = ask; b.setAttribute('aria-pressed', 'true'); timer = window.setTimeout(reset, ARM_MS); return; }
      reset();
      go();
    });
    return b;
  }
  const final = (text, label, ask, go) => twice(button(text, label, () => {}), ask, go);
  function act(body, done) {
    // Whether it was done.
    return send('users', body).then((r) => {
      if (!r.ok) { note(`Not done: ${r.text || 'refused'}`); return false; }
      note(done(r.data));
      // Your own reset ended your sessions: a reload would go to /login and lose the only copy of your setup link, so
      // the panel is drawn again from what it last showed, with the link.
      if (body.action === 'reset' && body.user === me) drawUsers(last); else load();
      return true;
    });
  }
  let me = null, last = null, armed = false;
  // The setup links given this visit, by user: each is the only copy, so it stays in a box under its user, with
  // Copy, until it is dismissed. The page never shows a password. No prototype: a user may be named `__proto__` or
  // `constructor`, which on a plain object would lose the link or show a box for a link never given.
  const links = Object.create(null);
  const linkMade = (who) => (d) => { links[who] = `${window.location.origin}${d.link}`; return `The setup link for ${who} is under their name.`; };
  function linkBox(who) {
    const box = h('div', 'setup-link'), url = h('code', 'setup-link-url', links[who]);
    const copy = () => {
      const clip = window.navigator && window.navigator.clipboard;
      (clip ? clip.writeText(links[who]) : Promise.reject(new Error('no clipboard'))).then(() => note(`The setup link for ${who} is copied.`), () => {
        // No clipboard (or it was refused): the link is selected, for the browser's own copy.
        const range = document.createRange(); range.selectNodeContents(url);
        window.getSelection().removeAllRanges(); window.getSelection().addRange(range);
        note('The link is selected: copy it.');
      });
    };
    box.append(h('p', 'setup-link-say', `Setup link for ${who}: give it to them. It works once, for 24 hours.`), url,
      button('Copy', `Copy the setup link for ${who}`, copy, 'btn-primary'),
      button('Dismiss', `Dismiss the setup link for ${who}: it is not shown again`, () => { delete links[who]; box.remove(); }));
    return box;
  }
  function drawUsers(d) {
    me = d.me; last = d;
    const body = byId('users-body');
    const ul = h('ul', 'rows');
    const admins = d.users.filter((u) => u.role === 'admin').length;
    d.users.forEach((u) => {
      const li = h('li', 'row'), main = h('div', 'row-main');
      main.append(h('span', 'title', u.user + (u.user === d.me ? ' (you)' : '')));
      const tools = h('p', 'row-meta');
      const other = u.role === 'admin' ? 'member' : 'admin';
      // Your own row and the last admin offer neither: either could shut you, or every admin, out.
      const guarded = u.user === d.me || (u.role === 'admin' && admins === 1);
      if (!guarded) tools.append(final(`Make ${other}`, `Make ${u.user} ${other}`, `Click again: make ${u.user} ${other}; their sessions end`, () => act({ action: 'role', user: u.user, role: other }, () => `${u.user} is now ${other}.`)));
      tools.append(final('Reset password', `Reset the password of ${u.user}`, `Click again: reset the password of ${u.user}; their sessions end`, () => act({ action: 'reset', user: u.user }, linkMade(u.user))));
      if (u.mfa) tools.append(final('Turn off authenticator codes', `Turn off the authenticator codes of ${u.user}`, `Click again: turn off the authenticator codes of ${u.user}`, () => act({ action: 'mfa-off', user: u.user }, () => `Authenticator codes are off for ${u.user}.`)));
      if (u.devices.length) tools.append(final('Revoke devices', `Revoke every device of ${u.user}`, `Click again: revoke every trusted device of ${u.user}`, () => act({ action: 'revoke', user: u.user, device: 'all' }, () => `Every device of ${u.user} is revoked.`)));
      if (!guarded) tools.append(final('Remove', `Remove ${u.user}`, `Click again: remove ${u.user}; their sessions and devices end at once`, () => act({ action: 'remove', user: u.user }, () => `${u.user} is removed.`)));
      const devs = devices(u.devices, (x) => act({ action: 'revoke', user: u.user, device: x.id }, () => `The device ${x.label || x.id} of ${u.user} is revoked.`),
        (x) => `Click again: revoke the device ${x.label || x.id} of ${u.user}`);
      li.append(main, facts(u), devs, tools);
      if (links[u.user]) li.append(linkBox(u.user));
      ul.append(li);
    });
    const add = h('form', 'row-meta'), name = field('user', 'text'), role = h('select', 'field');
    name.maxLength = 40; name.pattern = '[A-Za-z0-9._\\-]{1,40}'; name.autocomplete = 'off';
    ['member', 'admin'].forEach((r) => { const o = h('option', null, r[0].toUpperCase() + r.slice(1)); o.value = r; role.append(o); });
    const go = h('button', 'btn btn-primary', 'Add user');
    go.type = 'submit';
    add.append(labelled('New user name', name), labelled('Role', role), go);
    add.addEventListener('submit', (e) => { e.preventDefault(); act({ action: 'add', user: name.value, role: role.value }, linkMade(name.value)); });
    const count = byId('users-count');
    count.textContent = String(d.users.length); count.hidden = false;
    body.replaceChildren(ul, h('p', 'foot', 'Add a user: they get a one-time setup link to set their own password.'), add);
    byId('here-body').replaceChildren(noLoginHere(d.noLoginHere !== false));
    byId('panel-here').hidden = false;
  }
  // "No login on this device": on unless the server says false. Turning it off takes a second click, the first says
  // what it means. Turned off from this device, the reload that follows is a 401 and goes to /login.
  function noLoginHere(on) {
    armed = false;
    const box = h('div', 'row'), label = h('label', 'title'), sw = h('input'), warn = h('p', 'warn-note');
    const where = me !== 'this device' ? 'the machine the Board runs on'
      : /Mac/.test((window.navigator && window.navigator.platform) || '') ? 'this Mac' : 'this machine';
    warn.hidden = true;
    sw.type = 'checkbox'; sw.setAttribute('role', 'switch'); sw.checked = on; sw.dataset.guard = 'final';
    label.append(sw, ' No login on this device');
    sw.addEventListener('change', () => {
      if (!sw.checked && !armed) {
        armed = true; sw.checked = true;
        warn.textContent = `You will need your password and code on ${where} from now on. Click the switch again to turn it off.`;
        warn.hidden = false;
        return;
      }
      armed = false; warn.hidden = true;
      act({ action: 'no-login-here', on: sw.checked },
        () => (sw.checked ? 'This device opens the Board with no login.' : 'This device now logs in like any other.'))
        .then((done) => { if (!done) sw.checked = !sw.checked; });
    });
    box.append(label, warn, h('p', 'foot', 'Opening the Board on the machine it runs on needs no login. Other devices on the network always log in.'));
    return box;
  }

  function loadUsers() {
    get('users').then(drawUsers, (e) => byId('users-body').replaceChildren(h('p', 'warn-note', `The users could not be read: ${e.message}`)));
  }
  function load() {
    get('me').then((u) => {
      drawMe(u);
      const panel = byId('panel-users');
      if (u.role !== 'admin') { for (const p of [panel, byId('panel-here')]) if (p) p.remove(); return; }
      panel.hidden = false;
      // On the machine the Board runs on, "this device" has no account to manage: the Users panel leads.
      if (u.local) { const mine = byId('panel-me'); mine.parentNode.append(mine); }
      loadUsers();
    }, (e) => byId('me-body').replaceChildren(h('p', 'warn-note', `Your account could not be read: ${e.message}`)));
  }
  load();
}());
