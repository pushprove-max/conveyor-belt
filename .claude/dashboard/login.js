// SPDX-License-Identifier: Apache-2.0
// The login page (login.html, served at /login): the password, then, for a user with MFA on (the server answers
// 202), the code from their authenticator app or a recovery code, on the same page. A refused step shows the
// server's answer as text in the alert line and puts the focus back on the field to correct. Light or dark follows
// the system, as the Board does by default. On the Board's own machine with no login needed, it goes to the Board.
// The password can be shown; the device name is asked for only once Trust this device is ticked, and a trusted device
// left unnamed is named from its browser and system ("Safari on iPhone"), so a user's devices can be told apart. The
// code step takes the app's code on the number keypad, or, through "Use a recovery code", a recovery code on the
// full keyboard.
(function () {
  'use strict';
  const byId = (id) => document.getElementById(id);
  const pw = byId('login-password'), code = byId('login-code'), err = byId('login-error');
  // Signed in: on to the Board. What the Board keeps through a reload (app.js, KEPT_KEY: unsent answers, list lengths,
  // the filter) is in each tab's own sessionStorage, and is the last user's. A new login mark in localStorage, which
  // every tab of this browser reads, tells the Board in each tab, at its next start, to show none of it.
  function signedIn() {
    try { window.localStorage.setItem('conveyor-board-login', `${Date.now()}-${Math.random()}`); } catch (e) { /* the Board then shows nothing kept */ }
    window.location.assign('/');
  }
  function say(text) { err.textContent = text; err.hidden = !text; }
  // The name a trusted device gets when none is typed, from the browser's user agent: "<browser> on <system>".
  function deviceName(ua) {
    const browser = /Edg(A|iOS)?\//.test(ua) ? 'Edge' : /Firefox\/|FxiOS\//.test(ua) ? 'Firefox' : /OPR\//.test(ua) ? 'Opera'
      : /Chrome\/|CriOS\//.test(ua) ? 'Chrome' : /Safari\//.test(ua) ? 'Safari' : 'Browser';
    const system = /iPhone/.test(ua) ? 'iPhone' : /iPad/.test(ua) ? 'iPad' : /Android/.test(ua) ? 'Android' : /CrOS/.test(ua) ? 'ChromeOS'
      : /Macintosh|Mac OS X/.test(ua) ? 'Mac' : /Windows/.test(ua) ? 'Windows' : /Linux/.test(ua) ? 'Linux' : '';
    return system ? `${browser} on ${system}` : browser;
  }
  const autoName = deviceName(navigator.userAgent || '');
  byId('login-label').placeholder = autoName;
  const trust = byId('login-trust'), labelRow = byId('login-label-row');
  trust.addEventListener('change', () => { labelRow.hidden = !trust.checked; });
  const show = byId('login-show');
  show.addEventListener('click', () => {
    const secret = byId('login-secret'), shown = secret.type === 'password';
    secret.type = shown ? 'text' : 'password';
    show.textContent = shown ? 'Hide' : 'Show';
    show.setAttribute('aria-label', `${shown ? 'Hide' : 'Show'} password`);
  });
  // The code field: the app's 6-digit code on the number keypad, or a recovery code on the full keyboard.
  function recoveryMode(on) {
    const input = byId('login-code-input');
    input.inputMode = on ? 'text' : 'numeric';
    input.autocomplete = on ? 'off' : 'one-time-code';
    input.value = '';
    byId('login-code-label').textContent = on ? 'Recovery code' : 'Authenticator code';
    byId('login-code-hint').textContent = on ? 'Enter one of your recovery codes. Each one works once.'
      : 'Enter the 6-digit code your authenticator app shows for Conveyor.';
    byId('login-recovery').textContent = on ? 'Use a code from the app' : 'Use a recovery code';
    code.dataset.recovery = on ? 'on' : 'off';
  }
  // Which machine's Board this is, under its name: the machine's name from the address the page was opened at
  // (studio.local, or studio.example.com: "studio"), an address as it is, and "this machine" for the machine itself.
  // The page is shown before any login, so it says nothing the address bar does not.
  const host = window.location.hostname.replace(/^\[|\]$/g, '');
  const ip = /^[\d.]+$/.test(host) || host.includes(':');
  const machine = host === 'localhost' || host === '127.0.0.1' || host === '::1' ? 'this machine' : ip ? host : host.split('.')[0];
  byId('login-machine').textContent = machine ? `on ${machine}` : '';
  function post(body, form) {
    const go = form.querySelector('.login-go');
    go.disabled = true;
    return window.fetch('/login', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })
      .then((r) => r.text().then((t) => ({ status: r.status, text: t.trim() })))
      .catch(() => ({ status: 0, text: 'The server did not answer. Try again.' }))
      .finally(() => { go.disabled = false; });
  }
  function codeStep(on) {
    if (on) recoveryMode(false);
    pw.hidden = on; code.hidden = !on;
    byId(on ? 'login-code-input' : 'login-secret').focus();
  }
  pw.addEventListener('submit', (e) => {
    e.preventDefault();
    const user = byId('login-user'), secret = byId('login-secret');
    if (!user.value || !secret.value) { say('Enter your user name and password.'); (user.value ? secret : user).focus(); return; }
    const label = byId('login-label').value.trim();
    post({ user: user.value, password: secret.value, trust: trust.checked, label: trust.checked ? label || autoName : '' }, pw).then((r) => {
      if (r.status === 200) { signedIn(); return; }
      secret.value = '';
      if (r.status === 202) { say(''); codeStep(true); return; }
      say(r.text || `The server answered ${r.status}.`); secret.focus();
    });
  });
  code.addEventListener('submit', (e) => {
    e.preventDefault();
    const input = byId('login-code-input');
    if (!input.value.trim()) { say('Enter the code.'); input.focus(); return; }
    post({ code: input.value.trim() }, code).then((r) => {
      if (r.status === 200) { signedIn(); return; }
      input.value = '';
      say(r.text || `The server answered ${r.status}.`);
      // The code step is gone (expired, or the password changed): back to the password.
      if (r.status === 401 && /log in again/.test(r.text)) codeStep(false); else input.focus();
    });
  });
  byId('login-back').addEventListener('click', () => { say(''); codeStep(false); });
  // The press takes the focus to the button; it goes back to the field, so a phone opens the keyboard it now asks for.
  byId('login-recovery').addEventListener('click', () => {
    recoveryMode(code.dataset.recovery !== 'on');
    byId('login-code-input').focus();
  });
  // A browser the server already lets in (GET /me names a user: a trusted device, a live session, or "this device"
  // on the machine the Board runs on) goes straight to the Board. Otherwise /me is a 401 and the page stays.
  window.fetch('/me').then((r) => (r.ok ? r.json() : null)).then((me) => { if (me && me.user) window.location.replace('/'); }, () => {});
}());
