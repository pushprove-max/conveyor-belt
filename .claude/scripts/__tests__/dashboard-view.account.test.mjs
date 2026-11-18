// SPDX-License-Identifier: Apache-2.0
// The account page (account.html, account.js): "No login on this device" in a panel of its own, the account of
// "this device", the setup link's box, visible field names, local times, the guarded controls and one line per
// trusted device. Shared setup: dashboard-view.helpers.mjs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { read } from './dashboard-view.helpers.mjs';

const { JSDOM, VirtualConsole } = createRequire(import.meta.url)('jsdom');
const settle = () => new Promise((r) => setTimeout(r, 0));
const json = (d, status = 200) => Promise.resolve({ ok: status < 400, status, headers: { get: () => 'application/json' }, json: () => Promise.resolve(d) });
const LINE = 'Opening the Board on the machine it runs on needs no login. Other devices on the network always log in.';

// page(me, users, layout) -- account.html with app.js (its shared time formatter) and account.js run on it; GET me and
// users answer these, every POST is kept in w.posts and answered by w.answer (200 by default). layout: the Board's kept
// layout and settings (Customize) in this browser. w.navigations counts the page leaving (jsdom does not navigate).
// A browser dialog (confirm()) throws: the page has none (issue 407).
async function page(me, users, layout) {
  const virtualConsole = new VirtualConsole();
  const dom = new JSDOM(read('account.html'), { url: 'https://localhost:8443/account.html', runScripts: 'outside-only', virtualConsole });
  const w = dom.window;
  if (layout) w.localStorage.setItem('conveyor-board-layout', JSON.stringify(layout));
  w.navigations = 0;
  virtualConsole.on('jsdomError', (e) => { if (/navigation/.test(e.message)) w.navigations += 1; else throw e; });
  w.posts = [];
  w.answer = () => json({ done: 'no-login-here' });
  w.fetch = (url, opt) => {
    if (opt && opt.method === 'POST') { w.posts.push([url, JSON.parse(opt.body)]); return w.answer(); }
    return url === 'me' ? me() : json(users());
  };
  w.confirm = () => { throw new Error('no browser dialog'); };
  w.eval(read('app.js'));
  w.eval(read('account.js'));
  await settle(); await settle();
  return w;
}
const sw = (w) => w.document.querySelector('#here-body input[role="switch"]');
const flip = async (w, s, on) => { s.checked = on; s.dispatchEvent(new w.Event('change')); await settle(); await settle(); };
const admin = { user: 'max', role: 'admin', created: null, lastLogin: null, mfa: false, password: true, devices: [] };
const buttons = (el) => Array.from(el.querySelectorAll('button'), (b) => b.textContent);
const rowOf = (w, name) => Array.from(w.document.querySelectorAll('#users-body > ul > li')).find((li) => li.querySelector('.title').textContent.startsWith(name));

// The Users panel is hidden as served, and account.js shows it only to an admin: a member never sees it while /me is
// on its way. Bug: a page that drew the panel before /me answered showed every member the users' controls.
test('the Users panel stays hidden until /me answers', async () => {
  const w = await page(() => new Promise(() => {}), () => ({ me: 'max', users: [] }));
  assert.equal(w.document.getElementById('panel-users').hidden, true);
});

// The switch an admin uses to turn it off or on, with its one line, in its own panel (not under Add user, where it read
// as part of adding a user); on when the store has no value for it. Turning it off takes a second click: the first
// says what it means and sends nothing. Bugs: a switch drawn off when nothing is stored, so the page says a login is
// asked here when it is not; a single slip of the switch locking the owner out of the Board on its own machine.
test('"No login on this device": its own panel, on when no value is stored, a second click to turn it off, sends the change', async () => {
  let setting;
  const w = await page(() => json(admin), () => ({ me: 'max', users: [admin], ...(setting === undefined ? {} : { noLoginHere: setting }) }));
  const s = sw(w), d = w.document;
  assert.ok(s, 'the switch is drawn in its own panel');
  assert.equal(d.getElementById('panel-here').hidden, false);
  assert.equal(d.getElementById('panel-here-title').textContent, 'No login on this device');
  assert.equal(d.querySelector('#users-body input[role="switch"]'), null, 'not in the Users panel');
  assert.equal(s.type, 'checkbox');
  assert.equal(s.closest('label').textContent.trim(), 'No login on this device');
  assert.ok(s.closest('.row').textContent.includes(LINE), 'its line is under it');
  assert.equal(s.checked, true, 'no value stored reads as on');
  // Issue 407: it cannot be undone from here (this device is then logged out), so it is marked as a final control and
  // acts on a second click whose words name the consequence; no browser dialog.
  assert.equal(s.dataset.guard, 'final');
  const warn = s.closest('.row').querySelector('.warn-note');
  assert.equal(warn.hidden, true, 'no warning before the switch is touched');
  await flip(w, s, false);
  assert.deepEqual(w.posts, [], 'the first click sends nothing');
  assert.equal(s.checked, true, 'and leaves the switch on');
  assert.equal(warn.hidden, false);
  assert.match(warn.textContent, /^You will need your password and code on the machine the Board runs on from now on\./);
  setting = false;
  await flip(w, s, false);
  assert.deepEqual(w.posts, [['users', { action: 'no-login-here', on: false }]], 'the second click sends the change to /users');
  assert.equal(sw(w).checked, false, 'drawn again from the server: off');
  // Turning it on needs no second click. A refused change puts the switch back as it was, with the refusal in the note.
  w.answer = () => Promise.resolve({ ok: false, status: 403, headers: { get: () => 'text/plain' }, text: () => Promise.resolve('only an admin manages users') });
  const off = sw(w);
  await flip(w, off, true);
  assert.deepEqual(w.posts[1], ['users', { action: 'no-login-here', on: true }]);
  assert.equal(off.checked, false, 'a refused change is undone on the page');
  assert.match(w.document.getElementById('note').textContent, /only an admin manages users/);
});

// "this device" has no password, authenticator or devices: its account is its name, the Users panel leads the page, and
// turning the setting off (two clicks, the warning naming this machine) sends it to the login (its next request is a
// 401). Bug: on the Board's own machine the page led with an account that has nothing to manage.
test('Account of this device: the Users panel leads, its name only, and the login once the setting is off', async () => {
  let off = false;
  const local = { user: 'this device', role: 'admin', local: true };
  const w = await page(() => (off ? Promise.resolve({ ok: false, status: 401, text: () => Promise.resolve('log in') }) : json(local)), () => ({ me: 'this device', users: [admin] }));
  const me = w.document.getElementById('me-body');
  assert.deepEqual(Array.from(w.document.querySelectorAll('main > section'), (p) => p.id), ['panel-users', 'panel-here', 'panel-me'], 'Users first');
  assert.equal(me.querySelector('.title').textContent, 'this device');
  assert.equal(me.querySelectorAll('input, button').length, 0, 'no password, authenticator or device controls');
  assert.doesNotMatch(me.textContent, /password|MFA|authenticator|device:/i);
  assert.equal(w.document.getElementById('panel-users').hidden, false, 'an admin: the Users panel is shown');
  off = true;
  const s = sw(w);
  await flip(w, s, false);
  assert.match(s.closest('.row').querySelector('.warn-note').textContent, /on this machine from now on/, 'jsdom is no Mac: "this machine"');
  await flip(w, s, false);
  assert.equal(w.navigations, 1, 'sent to the login');
});

// A member is shown neither the Users panel nor the switch's panel.
test('A member sees neither the Users panel nor "No login on this device"', async () => {
  const w = await page(() => json({ ...admin, user: 'ana', role: 'member' }), () => { throw new Error('a member never asks for /users'); });
  assert.equal(w.document.getElementById('panel-users'), null);
  assert.equal(w.document.getElementById('panel-here'), null);
});

// A new user's setup link, and a reset's, is the only copy: it is shown in a box of its own under that user, saying it
// works once for 24 hours, with Copy, and stays through the reload that follows and later ones until Dismiss. Bug: the
// link was a sentence in the one-line note, gone at the next message, with no way to copy it on a phone.
test('Users panel: a setup link in its own box under the user, with Copy, kept until dismissed', async () => {
  let users = [admin];
  const w = await page(() => json(admin), () => ({ me: 'max', users }));
  w.answer = () => { users = [{ ...admin, user: 'ana', role: 'member', password: false }, admin]; return json({ link: '/setup#tok-ana' }); };
  const copied = [];
  Object.defineProperty(w.navigator, 'clipboard', { value: { writeText: (t) => { copied.push(t); return Promise.resolve(); } } });
  const add = w.document.querySelector('#users-body form');
  add.querySelector('input[name="user"]').value = 'ana';
  add.dispatchEvent(new w.Event('submit', { cancelable: true }));
  await settle(); await settle(); await settle();
  assert.deepEqual(w.posts, [['users', { action: 'add', user: 'ana', role: 'member' }]]);
  const box = rowOf(w, 'ana').querySelector('.setup-link');
  assert.ok(box, 'the link is in a box in the new user\'s row');
  assert.equal(box.querySelector('.setup-link-url').textContent, 'https://localhost:8443/setup#tok-ana');
  assert.match(box.textContent, /works once, for 24 hours/);
  assert.deepEqual(buttons(box), ['Copy', 'Dismiss']);
  assert.doesNotMatch(w.document.getElementById('note').textContent, /setup#/, 'the note does not carry the link');
  box.querySelector('button').click();
  await settle();
  assert.deepEqual(copied, ['https://localhost:8443/setup#tok-ana'], 'Copy puts the link on the clipboard');
  assert.match(w.document.getElementById('note').textContent, /copied/);
  // Another action (the switch turned on again) reloads the panel: the box is still there.
  w.answer = () => json({ done: 'no-login-here' });
  w.document.querySelector('#here-body input').dispatchEvent(new w.Event('change'));
  await settle(); await settle(); await settle();
  assert.equal(w.posts.length, 2, 'the other action was sent');
  assert.ok(rowOf(w, 'ana').querySelector('.setup-link'), 'kept through a reload');
  rowOf(w, 'ana').querySelector('.setup-link button[aria-label^="Dismiss"]').click();
  assert.equal(rowOf(w, 'ana').querySelector('.setup-link'), null, 'Dismiss takes it away');
  w.document.querySelector('#here-body input').dispatchEvent(new w.Event('change'));
  await settle(); await settle(); await settle();
  assert.equal(rowOf(w, 'ana').querySelector('.setup-link'), null, 'and it does not come back');
});

// The links are kept by user name, and a name the server allows can be an Object.prototype name. Bugs: `__proto__`'s
// link went to the prototype setter and its box read "[object Object]"; `constructor` got a box with no link given.
test('Users panel: a user named __proto__ gets its own setup link, and constructor gets no box', async () => {
  const proto = { ...admin, user: '__proto__', role: 'member', password: false };
  const ctor = { ...admin, user: 'constructor', role: 'member', password: false };
  let users = [admin, ctor];
  const w = await page(() => json(admin), () => ({ me: 'max', users }));
  assert.equal(rowOf(w, 'constructor').querySelector('.setup-link'), null, 'no link was given to constructor');
  w.answer = () => { users = [admin, ctor, proto]; return json({ link: '/setup#tok-proto' }); };
  const add = w.document.querySelector('#users-body form');
  add.querySelector('input[name="user"]').value = '__proto__';
  add.dispatchEvent(new w.Event('submit', { cancelable: true }));
  await settle(); await settle(); await settle();
  const box = rowOf(w, '__proto__').querySelector('.setup-link');
  assert.ok(box, 'the box is under __proto__');
  assert.equal(box.querySelector('.setup-link-url').textContent, 'https://localhost:8443/setup#tok-proto');
  assert.equal(rowOf(w, 'constructor').querySelector('.setup-link'), null, 'still none for constructor');
});

// Every field has its name shown beside it, not only as grey hint text that goes on typing; the page says
// "Authenticator codes" as the login page does, never "MFA". Bug: password and add-user fields named only by their
// placeholder, which a phone user loses on the first key.
test('Account page: each field has a visible name, and the words are "authenticator codes", not "MFA"', async () => {
  const w = await page(() => json(admin), () => ({ me: 'max', users: [admin, { ...admin, user: 'ana', role: 'member', mfa: true }] }));
  const d = w.document;
  const named = Array.from(d.querySelectorAll('main input:not([role="switch"]), main select'), (f) => [f.name || f.tagName, f.closest('label.field-label')?.firstChild.textContent]);
  assert.deepEqual(named, [['old', 'Current password'], ['new', 'New password'], ['again', 'New password again'], ['user', 'New user name'], ['SELECT', 'Role']]);
  for (const f of d.querySelectorAll('main input, main select')) assert.equal(f.placeholder || '', '', `${f.name} has no hint text in place of its name`);
  assert.doesNotMatch(d.querySelector('main').textContent, /MFA/);
  assert.match(d.getElementById('me-body').textContent, /Authenticator codes off/);
  assert.ok(buttons(d).includes('Turn on authenticator codes'));
  assert.ok(buttons(rowOf(w, 'ana')).includes('Turn off authenticator codes'));
});

// Times are local, as on the Board's main page: no "UTC", the time of day in the Board's default Time (12-hour), the
// date when it is not today in its default Date (mm/dd/yyyy). Bug: every time on the page was a UTC stamp that
// disagreed with the rest of the Board.
const today = new Date(); today.setHours(9, 5, 0, 0);
const older = new Date(today.getFullYear(), today.getMonth(), today.getDate() - 40, 14, 49);
const timed = { ...admin, created: older.toISOString(), lastLogin: today.toISOString() };
const p2 = (n) => String(n).padStart(2, '0');
const [mm, dd, yyyy] = [p2(older.getMonth() + 1), p2(older.getDate()), older.getFullYear()];
test('Account page: times in local time, with the date when not today', async () => {
  const w = await page(() => json(timed), () => ({ me: 'max', users: [timed] }));
  const text = w.document.querySelector('main').textContent;
  assert.doesNotMatch(text, /UTC|T\d\d:\d\d/);
  assert.ok(text.includes('Last login 9:05 AM'), `today: the time alone (${text})`);
  assert.ok(text.includes(`Created ${mm}/${dd}/${yyyy}, 2:49 PM`), 'another day: the date and time');
});

// Issue 458: the Time and Date set in Customize (kept with the Board's layout in this browser) are the account page's
// too. Bug it catches: a page that writes its own times in the browser's style, whatever the owner chose.
test('Account page: times and dates follow Customize\'s 24-hour Time and dd/mm/yyyy Date', async () => {
  const w = await page(() => json(timed), () => ({ me: 'max', users: [timed] }), { time: '24-hour', date: 'dd/mm/yyyy' });
  const text = w.document.querySelector('main').textContent;
  assert.ok(text.includes('Last login 09:05'), `today: the time alone, 24-hour (${text})`);
  assert.ok(text.includes(`Created ${dd}/${mm}/${yyyy}, 14:49`), `another day: dd/mm/yyyy and 24-hour (${text})`);
});

// Make member and Remove can shut you, or every admin, out: neither is on your own row or on the last admin's. Bug:
// both were offered on every row, your own included, behind a browser dialog alone.
test('Users panel: no Make member or Remove on your own row or on the last admin', async () => {
  const ana = { ...admin, user: 'ana', role: 'member' }, bo = { ...admin, user: 'bo' };
  let w = await page(() => json(admin), () => ({ me: 'max', users: [ana, admin] }));
  assert.deepEqual(buttons(rowOf(w, 'max')), ['Reset password'], 'your own row (and the last admin)');
  assert.deepEqual(buttons(rowOf(w, 'ana')), ['Make admin', 'Reset password', 'Remove'], 'a member');
  w = await page(() => json(admin), () => ({ me: 'max', users: [ana, bo, admin] }));
  assert.deepEqual(buttons(rowOf(w, 'bo')), ['Make member', 'Reset password', 'Remove'], 'another admin, not the last');
  assert.deepEqual(buttons(rowOf(w, 'max')), ['Reset password'], 'your own row, with another admin');
  w = await page(() => json({ user: 'this device', role: 'admin', local: true }), () => ({ me: 'this device', users: [ana, admin] }));
  assert.deepEqual(buttons(rowOf(w, 'max')), ['Reset password'], 'the last admin, seen from this device');
});

// Each trusted device on a line of its own: its name, when it was trusted and last used (local time), and a Revoke of
// its own that revokes that device alone. Bug: nine devices all named "device" in one sentence, with only "Revoke
// devices" for all of them.
test('Users panel: one line per trusted device, with its last use and its own Revoke', async () => {
  const at = (h) => { const d = new Date(); d.setHours(h, 0, 0, 0); return d.toISOString(); };
  const devs = [{ id: 'd1', label: 'Safari on iPhone', created: at(8), used: at(10) }, { id: 'd2', label: 'Chrome on Mac', created: at(9), used: null }];
  const ana = { ...admin, user: 'ana', role: 'member', devices: devs };
  const w = await page(() => json(admin), () => ({ me: 'max', users: [ana, admin] }));
  const lines = Array.from(rowOf(w, 'ana').querySelectorAll('ul.devices > li'));
  const time = (iso) => new Date(iso).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
  assert.deepEqual(lines.map((li) => [li.querySelector('.title').textContent, li.querySelector('.foot').textContent, buttons(li)]), [
    ['Safari on iPhone', `trusted ${time(devs[0].created)}, last used ${time(devs[0].used)}`, ['Revoke']],
    ['Chrome on Mac', `trusted ${time(devs[1].created)}, last used not recorded`, ['Revoke']]]);
  // Revoke acts on a second click that names the device and its user (issue 407: no browser dialog).
  const revoke = lines[1].querySelector('button');
  assert.equal(revoke.dataset.guard, 'final');
  revoke.click();
  await settle();
  assert.deepEqual(w.posts, [], 'the first click sends nothing');
  assert.equal(revoke.textContent, 'Click again: revoke the device Chrome on Mac of ana');
  revoke.click();
  await settle();
  assert.deepEqual(w.posts, [['users', { action: 'revoke', user: 'ana', device: 'd2' }]], 'that device alone');
  assert.ok(buttons(rowOf(w, 'ana')).includes('Revoke devices'), 'Revoke for all of them stays');
});

// Bug (issue 407): every Users action asked in a browser dialog, which looks like nothing else on the Board and blocks
// the page. Each acts on a second click whose words say what it ends; the first sends nothing.
test('Users panel: Remove and the other user actions act on a second click that names the consequence', async () => {
  const other = { user: 'kim', role: 'member', created: null, lastLogin: null, mfa: true, password: true, devices: [{ id: 'd1', label: 'phone', created: null }] };
  const w = await page(() => json(admin), () => ({ me: 'max', users: [admin, other] }));
  w.confirm = () => { throw new Error('no browser dialog'); };
  const row = () => Array.from(w.document.querySelectorAll('#users-body .row')).find((r) => r.querySelector('.title') && r.querySelector('.title').textContent === 'kim');
  const btn = (label) => row().querySelector(`button[aria-label="${label}"]`);
  const asks = {
    'Make kim admin': 'Click again: make kim admin; their sessions end',
    'Reset the password of kim': 'Click again: reset the password of kim; their sessions end',
    'Turn off the authenticator codes of kim': 'Click again: turn off the authenticator codes of kim',
    'Revoke every device of kim': 'Click again: revoke every trusted device of kim',
    'Remove kim': 'Click again: remove kim; their sessions and devices end at once',
  };
  for (const [label, ask] of Object.entries(asks)) {
    assert.equal(btn(label).dataset.guard, 'final', label);
    btn(label).click();
    await settle();
    assert.deepEqual(w.posts, [], `${label}: the first click sends nothing`);
    assert.equal(btn(label).textContent, ask);
  }
  btn('Remove kim').click();
  await settle(); await settle();
  assert.deepEqual(w.posts, [['users', { action: 'remove', user: 'kim' }]], 'the second click sends it');
  // The other armed buttons forget their first click after a while (their timers end with the page).
  w.close();
});
