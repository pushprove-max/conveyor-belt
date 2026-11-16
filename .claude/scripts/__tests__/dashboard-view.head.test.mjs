// SPDX-License-Identifier: Apache-2.0
// The Board's head, its panel heads and the pages beside it, as issue 408 made them clear: the restart only where the
// fault is, the head tiles' one colour and their words for a gap or a dash, hide and width in Customize only (never
// hiding Needs you), one project picker, the machine under the login page's name and the Board's own head on the
// account page. Shared
// setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { T0, STORE, OVERVIEW, read, boot, panel, deliver, settle, pending, tick, full, fig, tile, act, cases, pickProject, heading, kept } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

// UX12: "Restart collector" sat in the head on every tab all day, unexplained, while the mark said Live. It is in the
// Health panel, beside the data's age; the head shows it, as "Restart the Board's feed", only while the mark says
// Stale, No data or Feed stopped.
test('the Board\'s feed is restarted from the Health panel, and from the head only while the mark says it is at fault', async () => {
  const w = boot();
  const head = w.document.getElementById('restart');
  assert.equal(head.textContent, 'Restart the Board\'s feed');
  assert.equal(head.hidden, true, 'loading: not in the head');
  deliver(w, full());
  assert.equal(head.hidden, true, 'live: not in the head');
  const inHealth = () => panel(w, 'health').querySelector('[data-act="restart"]');
  assert.equal(inHealth().textContent, 'Restart the Board\'s feed');
  w.reply = { ok: true, status: 202, text: () => Promise.resolve('restarting') };
  // A restart costs the collector's time (issue 407): here too the first click only asks.
  assert.equal(inHealth().dataset.guard, 'spend');
  inHealth().click();
  await settle();
  assert.deepEqual(w.posts, [], 'the first click only asks');
  assert.equal(inHealth().textContent, 'Click again to restart the Board\'s feed');
  inHealth().click();
  await settle(); await settle();
  assert.deepEqual(w.posts, [{ url: 'restart', body: {} }]);
  assert.match(w.document.getElementById('restart-note').textContent, /Restarting/);
  assert.match(inHealth().closest('dd').textContent, /Restarting\. The page catches up/, 'the answer shows beside the button');
  tick(w, 400000);
  assert.equal(w.document.getElementById('status').textContent, 'Stale');
  assert.equal(head.hidden, false, 'stale: in the head');
  w.reply = { ok: false, status: 429, text: () => Promise.resolve('restarted under a minute ago') };
  head.click(); head.click();
  await settle();
  assert.equal(w.document.getElementById('restart-note').textContent, 'Not restarted: restarted under a minute ago');
  const none = boot();
  pending(none, 'data.js').dispatchEvent(new none.Event('error'));
  assert.equal(none.document.getElementById('status').textContent, 'No data');
  assert.equal(none.document.getElementById('restart').hidden, false, 'no data: in the head');
});

// UX13: Today was violet and Landed today green, so colour said nothing in particular; a cost with a gap said why only
// on hover, which a phone has not. Only Needs you has a colour (red above zero); a tap on a figure that leaves
// something out, or on a dash, says why under it, and the next tap opens its panel.
test('the head tiles: only Needs you has a colour, and a tap says in words what a figure leaves out or why it is a dash', () => {
  const w = boot();
  const data = full();
  data.panels.cost.data.cards.todayLeftOut = 2;
  // A cost part that was read: no card landed in the 7 days (snapshot.sh's perLanded is null then), and the 7 days not
  // priced (the price table could not be run). Issue 445: both dashes said "Not read yet".
  Object.assign(data.panels.cost.data.cards, { perLandedUsd: null, weekUsd: null, landedAfter: { 1: 0, 2: 0, 3: 0, more: 0 } });
  delete data.panels.landed;
  deliver(w, data);
  const tones = Object.fromEntries(Array.from(w.document.querySelectorAll('#stats > .stat'), (t) => [t.dataset.stat, t.dataset.tone || null]));
  assert.deepEqual(tones, { today: null, week: null, per: null, belt: null, queued: null, landed: null, needs: 'bad' }, 'red is Needs you above zero alone');
  const gap = (k) => tile(w, k).querySelector('.stat-gap');
  assert.equal(gap('today').hidden, true, 'the words show only once asked for');
  tile(w, 'today').click();
  assert.equal(gap('today').hidden, false);
  assert.equal(gap('today').textContent, '2 steps have no price');
  assert.notEqual(w.document.activeElement, w.document.getElementById('panel-cost'), 'the first tap does not open the panel');
  tile(w, 'today').click();
  assert.equal(w.document.activeElement, w.document.getElementById('panel-cost'), 'the next tap opens its panel');
  assert.equal(fig(w, 'landed'), '—');
  tile(w, 'landed').click();
  assert.equal(gap('landed').textContent, 'Not read yet', 'a dash says it was not read');
  assert.equal(fig(w, 'per'), '—');
  tile(w, 'per').click();
  assert.equal(gap('per').textContent, 'No card landed in 7 days', 'a dash that was read says why, not "not read"');
  assert.match(tile(w, 'per').title, /\(no card landed in 7 days\)/);
  tile(w, 'week').click();
  assert.equal(gap('week').textContent, 'Not priced', 'a cost read without its prices says so');
  tile(w, 'belt').click();
  assert.equal(gap('belt').hidden, true, 'a whole figure has nothing to explain: its tap opens its panel');
  assert.equal(w.document.activeElement, w.document.getElementById('panel-belt'));
});

// UX39: a panel head carried a width word and an ×; the × read as "close", and one stray tap on a phone took Needs you
// off the page until Customize brought it back. Hiding is in Customize, which has no switch to hide Needs you, and a
// layout kept with Needs you hidden shows it. Bug (#97): width was in Customize only, a sheet away from the panel; the
// head's width control sets it there and saves it, and Customize has no width setting left.
test('D1: a panel head\'s width control sets its width and the saved layout; Customize hides panels, sets no width, and never hides Needs you', () => {
  const w = boot();
  deliver(w, full());
  for (const id of OVERVIEW) {
    const tools = Array.from(panel(w, id).querySelectorAll('.panel-head .tool'), (t) => t.className.replace('tool ', ''));
    assert.deepEqual(tools, ['drag', 'size', 'move move-up', 'move move-down', 'collapse'], `${id}: the head sizes, moves and collapses, nothing else`);
  }
  const size = panel(w, 'belt').querySelector('.panel-head select.size');
  assert.equal(size.id, 'size-belt');
  assert.equal(size.value, 'wide');
  size.value = 'small'; size.dispatchEvent(new w.Event('change'));
  assert.equal(panel(w, 'belt').dataset.size, 'small', 'the panel takes the width');
  assert.equal(kept(w).sizes.belt, 'small', 'and the layout keeps it');
  assert.equal(panel(w, 'belt').hidden, false, 'the width control hides nothing');
  const sheet = w.document.getElementById('customize-body');
  assert.equal(sheet.querySelector('select'), null, 'Customize has no width setting');
  assert.equal(sheet.querySelector('#size-belt'), null);
  const row = (id) => w.document.getElementById(`show-${id}`).closest('.custom-row');
  assert.equal(w.document.getElementById('show-needs').disabled, true, 'no switch hides Needs you');
  assert.equal(row('needs').querySelector('label').textContent, 'Needs you (always shown)');
  assert.ok(w.document.getElementById('show-belt'), 'another panel can be hidden');
  const again = boot({ store: { [STORE]: JSON.stringify({ tabs: { overview: { hidden: ['needs', 'belt'] } } }) } });
  assert.equal(panel(again, 'needs').hidden, false, 'a kept layout that hid Needs you shows it');
  assert.equal(panel(again, 'belt').hidden, true, 'and keeps the other panel hidden');
});

// UX34: the bar said "All projects" while the Board and the Rules each showed one project from a picker of their own,
// so a figure could not be told apart from another. Show in the machine head is the one picker; the Board and the
// Rules show the project it picks and, showing one while Show says every project, name it in their heading.
test('one project picker: the Board and the Rules have none, follow Show, and name the project they show', () => {
  const d = full();
  const two = ['sample', 'widgetshop'];
  d.panels.machine.data.repos = two;
  Object.assign(d.panels.board.data, { repos: two, others: { widgetshop: { ...d.panels.board.data, repo: 'widgetshop' } } });
  Object.assign(d.panels.rules.data, { repos: two, others: { widgetshop: { ...d.panels.rules.data, repo: 'widgetshop' } } });
  const w = boot({ tab: 'control' });
  deliver(w, d);
  const show = w.document.querySelector('#machine-head [data-act="project"]');
  assert.equal(show.value, '', 'Show says every project');
  assert.equal(w.document.querySelectorAll('#grid select[data-act="repo"]').length, 0, 'no picker in a panel');
  assert.equal(heading(panel(w, 'board')), 'Board: sample', 'the Board names the one project it shows');
  pickProject(w, 'widgetshop');
  assert.equal(heading(panel(w, 'board')), 'Board: widgetshop');
  w.document.getElementById('tab-rules').click();
  assert.equal(act(panel(w, 'rules'), 'repo'), null);
  assert.equal(heading(panel(w, 'rules')), 'Rules: widgetshop');
});

// UX25: the login page said nothing of which machine's Board it was, which matters with more than one.
test('the login page names the machine under "Conveyor Board", from the address it was opened at', () => {
  const { JSDOM } = createRequire(import.meta.url)('jsdom');
  const at = (url) => {
    const w = new JSDOM(read('login.html'), { url, runScripts: 'outside-only' }).window;
    w.fetch = () => Promise.resolve({ ok: false, status: 401 });
    w.eval(read('login.js'));
    const p = w.document.getElementById('login-machine');
    assert.equal(p.previousElementSibling.textContent, 'Conveyor Board', 'under the name');
    return p.textContent;
  };
  assert.equal(at('https://studio.local:8443/login'), 'on studio');
  assert.equal(at('https://192.0.2.7:8443/login'), 'on 192.0.2.7', 'an address is shown as it is');
  assert.equal(at('https://localhost:8443/login'), 'on this machine');
});

// UX25: the account page had a bare head of its own, "Conveyor · Account and users" and one button back, with no
// tiles, no status mark and no tabs. It has the Board's head, drawn from the same data, its tabs links back.
test('the account page has the Board\'s head: the name, the tiles, the status mark and the tabs, each a link to the Board', () => {
  const page = read('account.html'), board = read('index.html');
  const headOf = (html) => /<header class="top">[\s\S]*?<div class="top-meta">/.exec(html)[0].replace(/ *<!--[\s\S]*?-->\n/g, '');
  assert.equal(headOf(page), headOf(board), 'the same name and tiles');
  const { JSDOM, VirtualConsole } = createRequire(import.meta.url)('jsdom');
  const w = new JSDOM(page, { url: 'https://dash.test/account.html', runScripts: 'outside-only', virtualConsole: new VirtualConsole() }).window;
  w.setInterval = () => 0;
  w.Date.now = () => T0;  // the snapshot's time: it is live
  w.matchMedia = () => ({ matches: false, addEventListener() {} });
  w.fetch = () => new Promise(() => {});
  Object.defineProperty(w.document, 'hidden', { get: () => false });  // jsdom's page is hidden: this one is in view
  w.eval(read('app.js')); w.eval(read('head.js')); w.eval(read('boot.js'));
  assert.deepEqual(Array.from(w.document.querySelectorAll('#tabs a.tab'), (a) => [a.textContent, a.getAttribute('href')]),
    [['Overview', 'index.html?tab=overview'], ['3D View', 'index.html?tab=belt3d'], ['Control', 'index.html?tab=control'], ['Rules', 'index.html?tab=rules'], ['Tests', 'index.html?tab=tests']]);
  assert.equal(w.document.querySelectorAll('#stats > .stat').length, 7, 'the seven tiles');
  assert.equal(w.document.querySelector('#stats .stat[data-stat="needs"]').getAttribute('href'), 'index.html?tab=overview#panel-needs', 'a tile opens its panel on the Board');
  assert.equal(w.document.getElementById('status').textContent, 'Loading', 'the status mark');
  w.DASH = full();
  w.document.head.querySelector('script[src^="data.js"]').dispatchEvent(new w.Event('load'));
  assert.equal(w.document.getElementById('status').textContent, 'Live');
  assert.equal(w.document.querySelector('#stats .stat[data-stat="needs"] .stat-value').textContent, '2', 'drawn from the Board\'s data');
  assert.equal(w.document.querySelector('.top-actions [aria-current="page"]').textContent, 'Account');
  assert.equal(w.location.search, '', 'the account page\'s address is left as it is');
});

// The account page has no panels, and the feed's later changes come one panel at a time: they were dropped as for no
// panel of the page, so its tiles stayed at the snapshot's figures while its mark said Live.
test('the account page\'s head follows the live feed\'s changes, not only its snapshot', () => {
  const { JSDOM, VirtualConsole } = createRequire(import.meta.url)('jsdom');
  const w = new JSDOM(read('account.html'), { url: 'https://dash.test/account.html', runScripts: 'outside-only', virtualConsole: new VirtualConsole() }).window;
  w.setInterval = () => 0;
  w.Date.now = () => T0;
  w.matchMedia = () => ({ matches: false, addEventListener() {} });
  w.fetch = () => new Promise(() => {});
  const sources = [];
  w.EventSource = class {
    constructor(url) { this.url = url; this.on = {}; sources.push(this); }
    addEventListener(type, fn) { (this.on[type] = this.on[type] || []).push(fn); }
    close() {}
    emit(type, data) { for (const fn of this.on[type] || []) fn(data === undefined ? { type } : { type, data: JSON.stringify(data) }); }
  };
  Object.defineProperty(w.document, 'hidden', { get: () => false });  // jsdom's page is hidden: this one is in view
  w.eval(read('app.js')); w.eval(read('head.js')); w.eval(read('boot.js'));
  assert.equal(sources.length, 1, 'the account page follows the feed');
  const es = sources[0], needs = () => w.document.querySelector('#stats .stat[data-stat="needs"] .stat-value').textContent;
  es.emit('open');
  es.emit('snapshot', full());
  assert.equal(needs(), '2');
  const part = JSON.parse(JSON.stringify(full().panels.needs));
  part.data.cards.waiting = [];
  part.data.cards.blocked = [];
  es.emit('panel', { id: 'needs', part, updatedAt: new Date(T0).toISOString() });
  assert.equal(needs(), '0', 'the change redraws the tile');
  assert.equal(w.document.getElementById('status').textContent, 'Live');
});
