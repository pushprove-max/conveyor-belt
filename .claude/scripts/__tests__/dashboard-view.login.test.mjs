// SPDX-License-Identifier: Apache-2.0
// The Board's login page (login.html, login.js). Shared setup: dashboard-view.helpers.mjs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { read, css } from './dashboard-view.helpers.mjs';

const { JSDOM, VirtualConsole } = createRequire(import.meta.url)('jsdom');
const settle = () => new Promise((r) => setTimeout(r, 0));

// ---- the login page (login.html, login.js) ----
// Every field labelled; the password, then, when the server asks for it (202), the code step on the same page; a
// refusal is the server's words in the alert line, focus on the field. The page's title, stylesheet and icon, and no
// host project's name, are checked on the served page (dashboard-server.test.sh, login_page_uses_the_boards_style).
test('the login page: Board style, labelled fields, the code step on the same page, a refusal in the alert line', async () => {
  const dom = new JSDOM(read('login.html'), { url: 'https://dash.test/login', runScripts: 'outside-only' });
  const w = dom.window, d = w.document, byId = (id) => d.getElementById(id);
  for (const f of d.querySelectorAll('input')) assert.equal(f.labels.length, 1, `${f.name} has a label`);
  assert.equal(byId('login-error').getAttribute('role'), 'alert');
  const replies = [{ status: 202, text: 'enter the code from your authenticator app' }, { status: 401, text: 'wrong code' }];
  const posts = [];
  w.fetch = (url, opt) => {
    // Another device: GET /me, the page's look for "this device", is a 401, and the page stays.
    if (!opt) return Promise.resolve({ ok: false, status: 401 });
    posts.push([url, JSON.parse(opt.body)]);
    const r = replies.shift();
    return Promise.resolve({ status: r.status, text: () => Promise.resolve(r.text) });
  };
  w.eval(read('login.js'));
  const settle = () => new Promise((r) => setTimeout(r, 0));
  byId('login-user').value = 'ana'; byId('login-secret').value = 'a long password';
  byId('login-password').dispatchEvent(new w.Event('submit', { cancelable: true }));
  await settle();
  assert.deepEqual(posts[0], ['/login', { user: 'ana', password: 'a long password', trust: false, label: '' }]);
  assert.ok(byId('login-password').hidden && !byId('login-code').hidden, 'the code step replaces the password step');
  assert.equal(d.activeElement, byId('login-code-input'));
  assert.equal(byId('login-secret').value, '', 'the password is not kept in the page');
  byId('login-code-input').value = ' 123456 ';
  byId('login-code').dispatchEvent(new w.Event('submit', { cancelable: true }));
  await settle();
  assert.deepEqual(posts[1], ['/login', { code: '123456' }]);
  assert.ok(!byId('login-error').hidden && byId('login-error').textContent === 'wrong code', 'the refusal is shown');
  assert.ok(!byId('login-code').hidden, 'a wrong code keeps the code step');
  assert.equal(d.activeElement, byId('login-code-input'));
  assert.match(css, /\.login-error \{[^}]*background: var\(--bad-bg\); color: var\(--bad\)/, 'the error line is in the Board\'s alert colours');
});

// login(ua) -- the login page with login.js run on it in a browser whose user agent is ua; every POST is kept in posts
// and answered from replies; GET /me is a 401 (another device), so the page stays.
function login(ua, replies = []) {
  const dom = new JSDOM(read('login.html'), { url: 'https://dash.test/login', runScripts: 'outside-only' });
  const w = dom.window, posts = [];
  if (ua !== undefined) Object.defineProperty(w.navigator, 'userAgent', { value: ua });
  w.fetch = (url, opt) => {
    if (!opt) return Promise.resolve({ ok: false, status: 401 });
    posts.push(JSON.parse(opt.body));
    const r = replies.shift() || { status: 200, text: '' };
    return Promise.resolve({ status: r.status, text: () => Promise.resolve(r.text) });
  };
  w.eval(read('login.js'));
  return { w, d: w.document, byId: (id) => w.document.getElementById(id), posts, submit: (id) => w.document.getElementById(id).dispatchEvent(new w.Event('submit', { cancelable: true })) };
}
const SAFARI_IPHONE = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1';
const CHROME_MAC = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
const visible = (el) => !el.closest('[hidden]');

// The password form asks for what a login needs: the device name only once Trust this device is ticked. A trusted
// device left unnamed is named from its browser and system, shown as the field's hint. Bug: the name was always on
// screen and skipped every time, so every trusted device was called "device" and none could be told apart.
test('the login page: the device name only once Trust this device is ticked, named from the browser when left blank', async () => {
  // Each login is refused, so the page stays to be read (jsdom cannot leave it).
  const no = { status: 401, text: 'wrong user name or password' };
  const { w, byId, posts, submit } = login(SAFARI_IPHONE, [no, no, no]);
  assert.equal(visible(byId('login-label')), false, 'no device name before Trust this device is ticked');
  assert.equal(byId('login-label').labels.length, 1);
  byId('login-trust').checked = true; byId('login-trust').dispatchEvent(new w.Event('change'));
  assert.equal(visible(byId('login-label')), true, 'ticked: the device name shows');
  assert.equal(byId('login-label').placeholder, 'Safari on iPhone', 'the name it gets when left blank');
  byId('login-user').value = 'ana'; byId('login-secret').value = 'a long password';
  submit('login-password');
  await settle();
  assert.deepEqual(posts.pop(), { user: 'ana', password: 'a long password', trust: true, label: 'Safari on iPhone' });
  byId('login-secret').value = 'a long password'; byId('login-label').value = ' Work phone ';
  submit('login-password');
  await settle();
  assert.equal(posts.pop().label, 'Work phone', 'a typed name is kept, trimmed');
  // Unticked again: the field hides and no name is sent, whatever was typed.
  byId('login-trust').checked = false; byId('login-trust').dispatchEvent(new w.Event('change'));
  assert.equal(visible(byId('login-label')), false);
  byId('login-secret').value = 'a long password';
  submit('login-password');
  await settle();
  assert.deepEqual(posts.pop(), { user: 'ana', password: 'a long password', trust: false, label: '' });
  // Other browsers and systems.
  for (const [ua, name] of [[CHROME_MAC, 'Chrome on Mac'],
    ['Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0', 'Edge on Windows'],
    ['Mozilla/5.0 (X11; Linux x86_64; rv:133.0) Gecko/20100101 Firefox/133.0', 'Firefox on Linux'],
    ['Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36', 'Chrome on Android'],
    ['Mozilla/5.0 (iPad; CPU OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/131.0 Mobile/15E148 Safari/604.1', 'Chrome on iPad'],
    ['curl/8.5.0', 'Browser']]) {
    assert.equal(login(ua).byId('login-label').placeholder, name, ua);
  }
});

// The password can be shown and hidden again, by a button with its own name. Bug: on a phone a mistyped password
// could not be checked before it was sent.
test('the login page: Show and Hide on the password', () => {
  const { w, byId } = login(CHROME_MAC);
  const show = byId('login-show'), secret = byId('login-secret');
  assert.deepEqual([secret.type, show.textContent, show.getAttribute('aria-label'), show.type], ['password', 'Show', 'Show password', 'button']);
  show.click();
  assert.deepEqual([secret.type, show.textContent, show.getAttribute('aria-label')], ['text', 'Hide', 'Hide password']);
  show.click();
  assert.deepEqual([secret.type, show.textContent, show.getAttribute('aria-label')], ['password', 'Show', 'Show password']);
  assert.equal(w.document.querySelectorAll('#login-password input').length, 4, 'user, password, trust, device name: no new field');
});

// The code step: the app's code on the number keypad, and "Use a recovery code" switches the field to the full
// keyboard (and back); its buttons are "Log in" and "Back". Bug: recovery codes were asked for in a field that gives a
// phone the number keypad, and the step's buttons read "Verify" and "Start again".
test('the login page: the code step\'s buttons, and "Use a recovery code" switching to the full keyboard', async () => {
  const ask = { status: 202, text: 'enter the code from your authenticator app' };
  const { d, byId, posts, submit } = login(SAFARI_IPHONE, [ask, { status: 401, text: 'wrong code' }, ask]);
  byId('login-user').value = 'ana'; byId('login-secret').value = 'a long password';
  submit('login-password');
  await settle();
  const code = byId('login-code'), input = byId('login-code-input');
  assert.deepEqual(Array.from(code.querySelectorAll('button'), (b) => b.textContent), ['Log in', 'Use a recovery code', 'Back']);
  assert.deepEqual([input.inputMode, input.autocomplete, byId('login-code-label').textContent], ['numeric', 'one-time-code', 'Authenticator code']);
  assert.match(byId('login-code-hint').textContent, /6-digit code your authenticator app shows/);
  byId('login-recovery').click();
  assert.deepEqual([input.inputMode, input.autocomplete, byId('login-code-label').textContent, byId('login-recovery').textContent],
    ['text', 'off', 'Recovery code', 'Use a code from the app']);
  assert.match(byId('login-code-hint').textContent, /one of your recovery codes/);
  assert.equal(d.activeElement, input, 'the focus is back on the field, so the phone opens the full keyboard');
  input.value = '1234-5678-9012-3456';
  submit('login-code');
  await settle();
  assert.deepEqual(posts.pop(), { code: '1234-5678-9012-3456' }, 'the recovery code is sent as the code');
  assert.equal(input.inputMode, 'text', 'a wrong code keeps the recovery field');
  byId('login-recovery').click();
  assert.deepEqual([input.inputMode, byId('login-code-label').textContent], ['numeric', 'Authenticator code'], 'and back to the app\'s code');
  byId('login-recovery').click();
  byId('login-back').click();
  assert.ok(!byId('login-password').hidden && code.hidden, 'Back goes to the password');
  byId('login-secret').value = 'a long password';
  submit('login-password');
  await settle();
  assert.equal(input.inputMode, 'numeric', 'a new code step starts on the app\'s code');
});

// When /me answers with any logged-in user, "this device" (local) or a user of a trusted device or live session,
// the login page goes straight to the Board. A refusal, or no answer, leaves the form.
// Bugs: the owner, on that machine, met a login form the server would not have asked for; and a trusted device
// that came to /login (its Strict cookie left off a link from another app) was asked to log in again.
test('the login page of a logged-in browser goes straight to the Board', async () => {
  const settle = () => new Promise((r) => setTimeout(r, 0));
  const opened = async (me) => {
    const virtualConsole = new VirtualConsole();
    const dom = new JSDOM(read('login.html'), { url: 'https://localhost:8443/login', runScripts: 'outside-only', virtualConsole });
    const w = dom.window, asked = [];
    let left = 0;
    virtualConsole.on('jsdomError', (e) => { if (/navigation/.test(e.message)) left += 1; else throw e; });
    w.fetch = (url, opt) => { asked.push([url, opt]); return me; };
    w.eval(read('login.js'));
    await settle(); await settle();
    return [asked, left];
  };
  const json = (d) => Promise.resolve({ ok: true, status: 200, json: () => Promise.resolve(d) });
  assert.deepEqual(await opened(json({ user: 'this device', role: 'admin', local: true })), [[['/me', undefined]], 1], 'this device: to the Board');
  assert.deepEqual(await opened(json({ user: 'ana', role: 'member', devices: [] })), [[['/me', undefined]], 1], 'a trusted device or live session: to the Board');
  assert.deepEqual(await opened(Promise.resolve({ ok: false, status: 401 })), [[['/me', undefined]], 0], 'no login: the form stays');
  assert.deepEqual(await opened(Promise.reject(new Error('down'))), [[['/me', undefined]], 0], 'no answer: the form stays');
});
