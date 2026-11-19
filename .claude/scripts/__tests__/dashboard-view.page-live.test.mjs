// SPDX-License-Identifier: Apache-2.0
// The dashboard page as a whole: nothing a source wrote becomes markup, a refresh redraws only what changed, one look,
// the top bar and the live feed. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { read, html, css, LIST, T0, iso, clone, CONTROL_IDS, RULES_IDS, BELT3D_IDS, TAB, OVERVIEW, boot, $, panel, state, pending, deliver, refresh, next, tick, later, seen, act, rulesP, groupEl, heldMany, P, full, SAYS, cases, settle } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

// ---- nothing a source wrote becomes markup, and only a GitHub issue address becomes a link ----
test('source text is shown as text, never as markup', () => {
  const w = boot();
  const evil = '<img src=x onerror=alert(1)><b>bold</b>';
  const data = full();
  data.panels.belt.data.cards[0].title = evil;
  data.panels.needs.data.decisions[0].question = evil;
  data.panels.needs.data.cards.blocked[0].reason = evil;
  data.panels.queue.data.next[0].title = evil;
  data.panels.landed.data.cards[0].title = evil;
  data.panels.lanes.data.records[0].research.run.topic = evil;
  data.panels.health.data.host.error = evil;
  data.panels.cost.data.cards.perCard[0].title = evil;
  data.panels.cost = { error: evil, data: null };
  data.panels.board.data.queue[0].title = evil;
  data.panels.board.data.waiting[0].sentence = evil;
  data.panels.board.data.blocked[0].reason = evil;
  data.panels.board.data.open = { count: 1, split: { queued: 0, you: 0, labelOrRule: 1, belt: 0 }, held: [{ issue: 99, title: evil, priority: 'P2', labels: [evil], reasons: [{ kind: 'label', label: evil }] }] };
  deliver(w, data);
  assert.equal(w.document.querySelectorAll('img, b').length, 0, 'no element came from source text');
  assert.ok(panel(w, 'belt').textContent.includes(evil), 'the text itself is shown');
  const c = boot({ tab: 'control' });
  deliver(c, data);
  assert.equal(c.document.querySelectorAll('img, b').length, 0, 'no element came from source text on the Control tab');
  assert.ok(panel(c, 'board').textContent.includes(evil));
});

test('an issue number is a link only to a GitHub issue address', () => {
  const w = boot();
  const data = full();
  data.panels.queue.data.next[0].url = 'javascript:alert(1)';
  data.panels.queue.data.next[1].url = 'https://github.com.evil.example/a/b/issues/21';
  data.panels.queue.data.awaitingDeploy[0].url = 'javascript:alert(1)';
  data.panels.queue.data.awaitingDeploy[1].url = null;
  deliver(w, data);
  // a.issue: the queue's own "see Held" link (issue 415) is not an issue address.
  assert.equal(panel(w, 'queue').querySelectorAll('a.issue').length, 0, 'neither address is a GitHub issue');
  const a = panel(w, 'belt').querySelector('a.issue');
  assert.equal(a.href, `${P}/63`);
  assert.equal(a.rel, 'noopener noreferrer');
  assert.equal(a.textContent, '#63');
  assert.equal(panel(w, 'belt').querySelectorAll('a').length, 1, 'a card with no address shows its number as text');
});

// ---- a refresh leaves a panel alone unless its own data changed ----
test('a refresh re-renders only the panels whose data changed', () => {
  const w = boot();
  deliver(w, full());
  const kept = Object.fromEntries(OVERVIEW.map((id) => [id, panel(w, id).querySelector('.panel-body').firstElementChild]));
  const same = full();
  same.updatedAt = iso(T0 + 15000);
  next(w, same);
  for (const id of OVERVIEW) {
    assert.equal(panel(w, id).dataset.renders, '1', `${id} was not drawn again for the same data`);
    assert.equal(panel(w, id).querySelector('.panel-body').firstElementChild, kept[id], `${id} keeps its nodes`);
  }
  const changed = full();
  changed.panels.queue.data.next.pop();
  next(w, changed);
  assert.equal(panel(w, 'queue').dataset.renders, '2');
  for (const id of OVERVIEW) if (id !== 'queue') assert.equal(panel(w, id).dataset.renders, '1', `${id} did not change, so it was not drawn again`);
});

test('a time keeps counting between refreshes without a re-render: the time in the step and the overall time', () => {
  const w = boot();
  deliver(w, full());
  const row = panel(w, 'belt').querySelector('li[data-key="sample:c3-63"]');
  const t = row.querySelector('.track-now time[data-since]'), all = row.querySelector('.card-times time[data-since]');
  assert.equal(t.textContent, '5 min in this step');
  assert.equal(all.textContent, '40 min overall');
  tick(w, 120000);
  assert.equal(t.textContent, '7 min in this step');
  assert.equal(all.textContent, '42 min overall');
  assert.equal(panel(w, 'belt').dataset.renders, '1');
});

// ---- one look: variables, contrast, focus, skeletons ----
const block = (start) => { const i = css.indexOf(start); assert.ok(i >= 0, `no ${start}`); return css.slice(i, css.indexOf('}', i)); };
const vars = (text) => Object.fromEntries(Array.from(text.matchAll(/--([a-z0-9-]+):\s*([^;]+);/g), (m) => [m[1], m[2].trim()]));
function luminance(hex) {
  const [r, g, b] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255).map((c) => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4));
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}
const contrast = (a, b) => { const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x); return (hi + 0.05) / (lo + 0.05); };

test('text meets AA contrast on every surface it is used on, in both themes', () => {
  const light = vars(block(':root {')), dark = vars(block(':root[data-theme="dark"] {'));
  const system = vars(block(':root:not([data-theme]) {'));
  for (const [k, v] of Object.entries(dark)) assert.equal(system[k], v, `the system's dark theme and the chosen one give --${k} the same value`);
  const pairs = [['text', 'bg'], ['text', 'surface'], ['text', 'surface-2'], ['muted', 'bg'], ['muted', 'surface'], ['muted', 'surface-2'], ['accent', 'surface'], ['accent', 'bg'],
    ['on-accent', 'accent'], ['ok', 'ok-bg'], ['warn', 'warn-bg'], ['bad', 'bad-bg'], ['info', 'info-bg'], ['quiet', 'quiet-bg'], ['ok', 'surface'], ['bad', 'surface'], ['warn', 'surface']];
  for (const [name, theme] of [['light', light], ['dark', dark]]) {
    for (const [fg, bg] of pairs) {
      const ratio = contrast(theme[fg], theme[bg]);
      assert.ok(ratio >= 4.5, `${name}: --${fg} on --${bg} is ${ratio.toFixed(2)}:1`);
    }
    // A control's edge and the focus ring are seen against the surface: 3:1.
    for (const fg of ['focus']) assert.ok(contrast(theme[fg], theme.surface) >= 3, `${name}: --${fg} on the surface`);
  }
});

test('one type scale, one spacing scale and one colour set, all variables', () => {
  const root = vars(block(':root {'));
  for (const k of ['fs-xs', 'fs-sm', 'fs-md', 'fs-lg', 'fs-xl', 'fs-2xl', 'sp-1', 'sp-2', 'sp-3', 'sp-4', 'sp-5', 'sp-6', 'motion', 'font']) assert.ok(root[k], `--${k} is defined`);
  const rules = css.slice(css.indexOf('* { box-sizing'));
  // Issue 575: a comment that names an issue as '#521' reads as a hex colour below, so comments write 'issue 521'.
  for (const [c] of css.matchAll(/\/\*[\s\S]*?\*\//g)) assert.doesNotMatch(c, /#\d/, `a comment names an issue as #N, not 'issue N': ${c}`);
  assert.doesNotMatch(rules, /#[0-9a-fA-F]{3,8}\b/, 'no colour is written outside the variables');
  for (const [, size] of rules.matchAll(/font-size:\s*([^;]+);/g)) assert.match(size, /^var\(--fs-[a-z0-9]+\)$|^16px$/, `a font size off the scale: ${size}`);
  assert.match(rules, /:focus-visible \{ outline: 2px solid var\(--focus\); outline-offset: 2px;/, 'focus is visible on everything that takes it');
});

test('the page loads only its own files and is never blank', () => {
  assert.match(html, /<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'self'; style-src 'self';[^"]*connect-src 'self'[^"]*">/);
  assert.deepEqual(Array.from(html.matchAll(/<script src="([^"]+)">/g), (m) => m[1]), ['app.js', 'head.js', 'panels/index.js', 'boot.js']);
  assert.doesNotMatch(html, /<script>|<style|style="|https?:\/\//, 'no inline code or style, and nothing from another host');
  assert.ok((html.match(/class="skeleton"/g) || []).length >= 3, 'placeholders show before the page\'s code has run');
  for (const tab of ['overview', 'control', 'rules']) {
    const w = boot({ tab });
    for (const id of LIST.filter((x) => TAB(x) === tab)) {
      assert.equal(state(w, id), 'loading');
      assert.ok(panel(w, id).querySelector('.panel-body .skeleton'), `${id} shows a skeleton until its data arrives`);
      assert.equal(panel(w, id).getAttribute('aria-labelledby'), `panel-${id}-title`);
      for (const b of panel(w, id).querySelectorAll('button')) assert.ok(b.getAttribute('aria-label') && b.type === 'button', `every control of ${id} has a name and is reachable by keyboard`);
    }
    assert.equal(w.document.getElementById('grid').getAttribute('aria-busy'), 'true');
    deliver(w, full());
    assert.equal(w.document.getElementById('grid').getAttribute('aria-busy'), 'false');
  }
});

// The other cases load the panels themselves (helpers.mjs boot): this one runs the page's own loader, boot.js. A
// loader that took its files from anywhere but the list, or started the page before every file had loaded or
// failed, draws panels with no code behind them or never starts at all.
test('the loader adds one file per listed panel and starts the page once each has loaded or failed', () => {
  const { JSDOM, VirtualConsole } = createRequire(import.meta.url)('jsdom');
  const w = new JSDOM('<!doctype html><head></head><body></body>', { runScripts: 'outside-only', virtualConsole: new VirtualConsole() }).window;
  let started = 0;
  w.DASH_APP = { start: () => { started += 1; } };
  w.DASH_PANELS = ['belt', 'ghost'];
  w.eval(read('boot.js'));
  const files = Array.from(w.document.head.querySelectorAll('script'));
  assert.deepEqual(files.map((s) => s.getAttribute('src')), ['panels/belt.js', 'panels/ghost.js'], 'one file per entry of the list, in its order');
  assert.equal(started, 0, 'the page waits for its panels');
  files[0].dispatchEvent(new w.Event('load'));
  assert.equal(started, 0, 'one panel loaded is not all of them');
  files[1].dispatchEvent(new w.Event('error'));
  assert.equal(started, 1, 'a file that fails does not hold the page');
});

// ---- the top bar: is this live ----
test('the status says whether the data is fresh, stale or missing', () => {
  const w = boot();
  const word = () => w.document.getElementById('status').textContent;
  assert.equal(word(), 'Loading');
  deliver(w, full());
  assert.equal(word(), 'Polling', 'fresh data from data.js, with no feed');
  assert.equal(w.document.getElementById('updated').textContent, 'under a minute ago');
  tick(w, 400000);
  assert.equal(word(), 'Stale', 'a snapshot over five minutes old is stale');
  assert.equal(w.document.getElementById('updated').textContent, '7 min ago');
  // Issue 415: Stale has a short line that says what it means and the one thing to try.
  assert.equal(w.document.getElementById('banner').hidden, false);
  assert.equal(w.document.getElementById('banner').textContent,
    "Stale: the newest data is 7 min old, so what you see can be out of date. If it stays old, press Restart the Board's feed, beside the mark above (in Menu on a phone).");
});

test('a first load that fails says so in every panel; a later one keeps the last snapshot', () => {
  const w = boot();
  pending(w, 'data.js').dispatchEvent(new w.Event('error'));
  assert.equal(w.document.getElementById('status').textContent, 'No data');
  assert.equal(w.document.getElementById('banner').hidden, false);
  // #112: before any data the page does not know of a build machine, so it names none.
  assert.match(w.document.getElementById('banner').textContent, /^No data: the page could not load the Board's data, so there is nothing to show\. Press Restart/);
  for (const id of OVERVIEW) {
    assert.equal(state(w, id), 'error', `${id} is not left as a skeleton`);
    assert.ok(panel(w, id).textContent.includes(SAYS[id].failed));
  }
  // The other tab, opened before any data: its panels say so too.
  w.document.getElementById('tab-belt3d').click();
  for (const id of BELT3D_IDS) assert.equal(state(w, id), 'error', `${id} is not left as a skeleton`);
  w.document.getElementById('tab-control').click();
  for (const id of CONTROL_IDS) assert.equal(state(w, id), 'error', `${id} is not left as a skeleton`);
  w.document.getElementById('tab-rules').click();
  for (const id of RULES_IDS) assert.equal(state(w, id), 'error', `${id} is not left as a skeleton`);
  w.document.getElementById('tab-overview').click();
  next(w, full());
  assert.equal(w.document.getElementById('status').textContent, 'Polling');
  assert.equal(w.document.getElementById('banner').hidden, true);
  for (const id of OVERVIEW) assert.equal(state(w, id), 'ready');
  for (let i = 0; i < 2; i += 1) { refresh(w); pending(w, 'data.js').dispatchEvent(new w.Event('error')); }
  for (const id of OVERVIEW) assert.equal(state(w, id), 'ready', `${id} keeps the last snapshot`);
  assert.equal(w.document.getElementById('status').textContent, 'Stale');
  assert.match(w.document.getElementById('banner').textContent, /^Stale: the last refreshes could not reach the build machine\. This is the last data that loaded/);
  next(w, { nonsense: true });
  assert.equal(state(w, 'belt'), 'ready', 'a data.js that is not the collector\'s shape is a failed load');
  assert.equal(w.document.getElementById('status').textContent, 'Stale');
});

test('a heartbeat that stops is a stopped collector, and a changed page reloads itself', async () => {
  const w = boot();
  const beat = (at, view) => { w.DASH_ALIVE = { at: iso(at), view, snapshotAgeSec: 5, cycleStartedAt: iso(at), lastCycleSec: 3 }; pending(w, 'alive.js').dispatchEvent(new w.Event('load')); };
  deliver(w, full());
  await settle();  // the page's history read is answered: no request in flight
  beat(T0, 'v1');
  tick(w, 30000);
  assert.equal(w.document.getElementById('status').textContent, 'Polling');
  refresh(w);
  beat(T0, 'v1');
  deliver(w, full());
  tick(w, 30000);
  assert.equal(w.document.getElementById('status').textContent, 'Feed stopped', 'the same heartbeat for over 45 s is no heartbeat');
  assert.match(w.document.getElementById('banner').textContent, /^Feed stopped: .*Press Restart the Board's feed/);
  refresh(w);
  beat(w.clock, 'v1');
  tick(w, 1000);
  assert.notEqual(w.document.getElementById('status').textContent, 'Feed stopped');
  assert.equal(w.navigations, 0);
  refresh(w);
  beat(w.clock, 'v2');
  assert.equal(w.navigations, 1, 'a new copy of the page files reloads an idle page');
  tick(w, 1000);
  assert.equal(w.navigations, 1, 'once: the next tick does not reload it again');
  assert.equal(w.document.getElementById('new-view').hidden, true, 'an idle page shows no notice');
});

// Issue 509: a new copy of the page waits while the owner is at work on it, as a reload loses what they typed, an armed
// button or a question, or a request's answer. jsdom forbids replacing location.reload: each call of it is counted as w.navigations.
const newCopy = (w) => {
  const beat = (view) => { w.DASH_ALIVE = { at: iso(w.clock), view, snapshotAgeSec: 5, cycleStartedAt: iso(w.clock), lastCycleSec: 3 }; pending(w, 'alive.js').dispatchEvent(new w.Event('load')); };
  beat('v1');
  refresh(w);
  beat('v2');
};
const answerField = (w) => panel(w, 'needs').querySelector('input[aria-label="Answer to q-ship"]');
const type = (w, field, text) => { field.value = text; field.dispatchEvent(new w.Event('input', { bubbles: true })); };

test('a new copy waits while a Needs you answer has text, says so beside the status mark, and reloads once the field is cleared', async () => {
  const w = boot();
  deliver(w, full());
  await settle();
  type(w, answerField(w), 'Ship on Monday');
  newCopy(w);
  tick(w, 1000);
  assert.equal(w.navigations, 0, 'the typed answer is not lost to a reload');
  const note = w.document.getElementById('new-view');
  assert.equal(note.hidden, false);
  assert.equal(note.textContent, 'New version. Reload');
  assert.equal(note.previousElementSibling.id, 'status', 'the notice is beside the status mark');
  assert.equal(note.querySelector('button').textContent, 'Reload');
  type(w, answerField(w), '');
  assert.equal(w.navigations, 1, 'an emptied field leaves nothing to lose');
  tick(w, 1000);
  assert.equal(w.navigations, 1, 'once');
});

test('a new copy that waits on a typed answer reloads once the page is hidden', async () => {
  const w = boot();
  deliver(w, full());
  await settle();  // the history read is answered: the draft alone holds the reload
  type(w, answerField(w), 'Ship on Monday');
  newCopy(w);
  assert.equal(w.navigations, 0);
  seen(w, false);
  assert.equal(w.navigations, 1, 'a hidden page is not being read');
});

test('the notice\'s Reload button reloads the page', () => {
  const w = boot();
  deliver(w, full());
  type(w, answerField(w), 'Ship on Monday');
  newCopy(w);
  w.document.querySelector('#new-view button').click();
  assert.equal(w.navigations, 1);
});

test('a new copy waits while a field has the focus', async () => {
  const w = boot();
  deliver(w, full());
  await settle();
  answerField(w).focus();
  newCopy(w);
  tick(w, 1000);
  assert.equal(w.navigations, 0, 'the owner is about to type');
  answerField(w).blur();
  tick(w, 1000);
  assert.equal(w.navigations, 1);
});

test('a new copy waits while a two-click button is armed', async () => {
  const w = boot();
  deliver(w, full());
  await settle();
  w.document.getElementById('restart').click();
  newCopy(w);
  tick(w, 1000);
  assert.equal(w.navigations, 0, 'the second click would land on a new page');
  later(w);  // the button disarms
  await settle();  // and the history read the timers sent again is answered
  tick(w, 1000);
  assert.equal(w.navigations, 1);
});

// Bug: the arm was found by a "Click again" label, so a panel's own two-click button with another label (Rules' "Turn
// P2 off: skip 2") reloaded the page between its two clicks.
test('a new copy waits while a panel\'s own two-click button is armed, whatever its label says', () => {
  const w = boot({ tab: 'rules' });
  deliver(w, full());
  act(rulesP(w), 'rule-P2').click();
  assert.equal(act(rulesP(w), 'rule-P2').textContent, 'Turn P2 off: skip 2');
  newCopy(w);
  tick(w, 1000);
  assert.equal(w.navigations, 0);
  later(w);  // the arm lapses
  tick(w, 1000);
  assert.equal(w.navigations, 1);
});

// Bug: a question that waits for its confirm with no time limit (Rules' Queue all) was not seen, and the page reloaded
// under it.
test('a new copy waits while a question waits for its confirm, until it is cancelled', () => {
  const w = boot({ tab: 'rules' });
  deliver(w, heldMany());
  act(groupEl(w, 'web'), 'queue-all').click();
  newCopy(w);
  later(w);
  tick(w, 1000);
  assert.equal(w.navigations, 0, 'the question stays open');
  act(groupEl(w, 'web'), 'queue-all-no').click();
  tick(w, 1000);
  assert.equal(w.navigations, 1);
});

// Bug: a panel drew a typed field again as a new element (Release's version), and the new one was not known as typed:
// the page reloaded and lost the draft.
const releaseRec = (repo) => ({ repo, url: `https://github.com/example/${repo}`, suites: [],
  release: { tag: null, count: 1, next: '1.0.0', notes: true, written: ['1.0.0'], head: 'b'.repeat(40), releases: true, commits: [] } });
const versions = (w) => Array.from(panel(w, 'release').querySelectorAll('[data-field="version"]'));
test('a new copy waits while a draft the panel drew again has text', async () => {
  const w = boot();
  const d = full();
  d.panels.release.data.records = [releaseRec('plugin')];
  deliver(w, d);
  await settle();  // the history read is answered: the draft alone holds the reload
  const was = versions(w)[0];
  type(w, was, '1.1.0');
  assert.notEqual(versions(w)[0], was, 'the panel drew the field again');
  versions(w)[0].blur();
  newCopy(w);
  tick(w, 1000);
  assert.equal(w.navigations, 0, 'the draft 1.1.0 is not lost');
  type(w, versions(w)[0], '');
  versions(w)[0].blur();
  tick(w, 1000);
  assert.equal(w.navigations, 1, 'the cleared field holds it no more');
});

// Bug (E5): a typed field was known by its panel and label only, and each project in Release has a "Version to
// release" field: after one was typed in and cleared, the other's untouched version counted as typed and held the
// reload; and a draft in one must still hold it after the other is cleared.
test('a typed field cleared no longer holds a new copy, though another field has its label and a value', async () => {
  const w = boot();
  const d = full();
  d.panels.release.data.records = [releaseRec('plugin'), releaseRec('widgets'), releaseRec('tools')];
  deliver(w, d);
  await settle();
  assert.equal(versions(w).length, 3);
  type(w, versions(w)[0], '1.1.0');
  type(w, versions(w)[1], '2.0.0');
  type(w, versions(w)[1], '');
  versions(w)[1].blur();
  newCopy(w);
  tick(w, 1000);
  assert.equal(w.navigations, 0, 'the draft 1.1.0 of the first project is not lost');
  type(w, versions(w)[0], '');
  versions(w)[0].blur();
  assert.equal(versions(w)[2].value, '1.0.0', 'the third project shows its own version, untouched');
  tick(w, 1000);
  assert.equal(w.navigations, 1, 'nothing typed is left');
});

// Bug: only the fields in the page were looked at: a Needs you draft left on Overview while the owner looked at
// another tab was lost to a reload.
test('a new copy waits while a draft has text in a panel of another tab', async () => {
  const w = boot();
  deliver(w, full());
  const needs = panel(w, 'needs');
  type(w, answerField(w), 'Ship on Monday');
  w.document.getElementById('tab-control').click();
  assert.equal(needs.isConnected, false, 'Needs you is out of the page');
  await settle();  // every read the page sent is answered: the draft alone holds the reload
  newCopy(w);
  tick(w, 1000);
  assert.equal(w.navigations, 0);
  w.document.getElementById('tab-overview').click();
  await settle();
  type(w, answerField(w), '');
  tick(w, 1000);
  assert.equal(w.navigations, 1, 'the draft was what held it');
});

// Bug (E4): Rules' Undo on the note line kept its armed mark after its arm lapsed (the note is not drawn again), and
// the page never reloaded.
test('a new copy waits while the Rules note\'s Undo is armed, and reloads once its arm lapses', async () => {
  const w = boot({ tab: 'rules' });
  const off = full();
  off.panels.rules.data.control.rules.P2 = false;
  deliver(w, off);
  act(rulesP(w), 'rule-P2').click();
  await settle();
  const undo = () => act(rulesP(w).querySelector('.rules-note'), 'undo');
  undo().click();
  await settle();
  assert.equal(undo().textContent, 'Undo: skip 2', 'armed');
  newCopy(w);
  tick(w, 1000);
  assert.equal(w.navigations, 0, 'the second click would land on a new page');
  later(w);  // the arm lapses
  await settle();
  tick(w, 1000);
  assert.equal(undo().textContent, 'Undo', 'the button no longer says it is armed');
  assert.equal(w.navigations, 1);
});

// Bug: a request a panel sent itself (Health's Work now) was not counted, and a counted one stopped counting at its
// answer's headers, before its body was read: a reload lost the answer.
test('a new copy waits while a request is in flight, until its answer\'s body is read', async () => {
  const w = boot();
  let body;
  w.workReply = { ok: true, status: 200, json: () => new Promise((r) => { body = r; }) };
  deliver(w, full());
  const work = panel(w, 'health').querySelector('details.work-now');
  work.open = true;
  work.dispatchEvent(new w.Event('toggle'));
  await settle();
  newCopy(w);
  tick(w, 1000);
  assert.equal(w.workAsks, 1);
  assert.equal(w.navigations, 0, 'the answer is still being read');
  body({ host: 'devbox', groups: [], other: [] });
  await settle();
  tick(w, 1000);
  assert.equal(w.navigations, 1);
});

// Issue 407: a restart costs the collector's time, so it acts on a second click like every such button, and looks it.
test('the collector can be restarted from the page, on a second click', async () => {
  const w = boot();
  const restart = w.document.getElementById('restart');
  assert.equal(restart.dataset.guard, 'spend');
  w.reply = { ok: true, status: 202, text: () => Promise.resolve('restarting') };
  restart.click();
  await settle();
  assert.deepEqual(w.posts, [], 'the first click only asks');
  assert.equal(restart.textContent, 'Click again to restart the Board\'s feed');
  restart.click();
  await settle();
  assert.deepEqual(w.posts, [{ url: 'restart', body: {} }]);
  assert.equal(restart.textContent, 'Restart the Board\'s feed');
  assert.match(w.document.getElementById('restart-note').textContent, /Restarting/);
  w.reply = { ok: false, status: 429, text: () => Promise.resolve('restarted under a minute ago') };
  restart.click(); restart.click();
  await settle();
  assert.equal(w.document.getElementById('restart-note').textContent, 'Not restarted: restarted under a minute ago');
});

// ---- the live feed: the page server's /events ----
test('the live feed: its snapshot draws the page, a change redraws only its own panel, and data.js is read only while it is closed', () => {
  const w = boot({ feed: true });
  assert.deepEqual(w.sources.map((s) => s.url), ['events'], 'the page opens one feed, at its own address');
  const es = w.sources[0];
  // Issue 565: the feed's first message is the whole of data.js, so a page with a feed does not read data.js too at start.
  assert.equal(pending(w, 'data.js'), null, 'data.js is not read at start while the feed is opening');
  assert.ok(pending(w, 'alive.js'), 'the heartbeat is still read at start');
  es.readyState = 1; es.emit('open');
  es.emit('snapshot', full());
  // Only the tab in view is drawn: Overview's panels.
  for (const id of OVERVIEW) assert.equal(state(w, id), 'ready');
  const before = Object.fromEntries(OVERVIEW.map((id) => [id, Number(panel(w, id).dataset.renders)]));
  const part = clone(full().panels.belt);
  part.data.cards[0].live = { turns: 7, lastOutputAt: iso(T0 - 4000), action: 'Bash: npm test' };
  es.emit('panel', { id: 'belt', part, updatedAt: iso(T0) });
  const belt = panel(w, 'belt').textContent;
  for (const s of ['now: running a command', '7 model replies', '4 s since its last output']) assert.ok(belt.includes(s), `the belt shows "${s}": ${belt}`);
  assert.equal(panel(w, 'belt').querySelector('.live-action').dataset.tip, 'Bash: npm test', 'the command itself on tap');
  assert.equal(Number(panel(w, 'belt').dataset.renders), before.belt + 1, 'the panel the change is for is drawn again');
  for (const id of OVERVIEW) if (id !== 'belt') assert.equal(Number(panel(w, id).dataset.renders), before[id], `${id} is not drawn again`);
  assert.equal($(w, '#updated').textContent, 'under a minute ago', 'the change carries when it was published');
  refresh(w);
  assert.equal(pending(w, 'data.js'), null, 'no data.js is read while the feed is open');
  // The server refuses the feed for good (a lost login, too many pages): data.js again, and the feed asked for later.
  es.readyState = 2; es.emit('error');
  refresh(w);
  assert.ok(pending(w, 'data.js'), 'data.js is read again once the feed is closed');
  later(w);
  assert.equal(w.sources.length, 2, 'a feed closed for good is asked for again later');
});

test('the live feed: a feed that does not open at start has the page read data.js at once, and once', () => {
  const w = boot({ feed: true });
  const es = w.sources[0];
  assert.equal(pending(w, 'data.js'), null);
  // The feed fails before it opens (the browser tries again): the page does not wait for the next refresh to draw.
  es.readyState = 0; es.emit('error');
  assert.ok(pending(w, 'data.js'), 'data.js is read when the feed does not open');
  es.emit('error');
  assert.equal(w.document.head.querySelectorAll('script[src^="data.js"]').length, 1, 'a second failed try does not ask for data.js again');
  deliver(w, full());
  for (const id of OVERVIEW) assert.equal(state(w, id), 'ready', `${id} is drawn from data.js`);
});

test('the live feed: a data.js asked for before the feed\'s snapshot, answering after it, is not drawn over it', () => {
  const w = boot({ feed: true });
  const es = w.sources[0];
  es.readyState = 0; es.emit('error');
  deliver(w, full());
  // The page's feed is down a moment: data.js is asked for, and is slow to answer.
  refresh(w);
  // Issue 550: each poll asks for the same address, so the browser revalidates by ETag (a 304 while unchanged) and
  // does not keep a new cached copy per poll; a query string added again fails here.
  assert.equal(pending(w, 'data.js')?.getAttribute('src'), 'data.js', 'data.js is polled at one stable address');
  assert.equal(pending(w, 'alive.js')?.getAttribute('src'), 'alive.js', 'alive.js is polled at one stable address');
  // The feed opens and its snapshot is newer: a running step's live fields.
  const newer = full(T0 + 5000);
  newer.panels.belt.data.cards[0].live = { turns: 2, lastOutputAt: iso(T0), action: 'Bash: newer' };
  es.readyState = 1; es.emit('open');
  es.emit('snapshot', newer);
  assert.ok(panel(w, 'belt').querySelector('.live-action')?.dataset.tip === 'Bash: newer');
  // The old data.js answers now: it is dropped, and every panel stays the feed's.
  const renders = Object.fromEntries(OVERVIEW.map((id) => [id, Number(panel(w, id).dataset.renders)]));
  deliver(w, full());
  assert.ok(panel(w, 'belt').querySelector('.live-action')?.dataset.tip === 'Bash: newer', 'the older data.js did not draw over the feed\'s snapshot');
  for (const id of OVERVIEW) assert.equal(Number(panel(w, id).dataset.renders), renders[id], `${id} is not drawn again from the old data.js`);
  // The same when the feed opened and closed again before data.js answered: its snapshot is newer all the same.
  es.readyState = 0; es.emit('error');
  refresh(w);
  es.readyState = 1; es.emit('open');
  es.emit('snapshot', newer);
  es.readyState = 0; es.emit('error');
  deliver(w, full());
  assert.ok(panel(w, 'belt').querySelector('.live-action')?.dataset.tip === 'Bash: newer');
});

test('health says how old what the page shows is: Live, or the seconds since the host was last heard, counting', () => {
  const w = boot({ feed: true });
  const es = w.sources[0];
  const data = full();
  data.panels.health.data.stream = { live: false, heardAt: iso(T0 - 12000), since: iso(T0 - 9000), error: 'buildhost: no line in 30 s' };
  es.readyState = 0; es.emit('error'); // the feed does not open: the page is drawn from data.js
  deliver(w, data);
  const text = () => panel(w, 'health').textContent;
  assert.match(text(), /Data.*12 s old.*buildhost: no line in 30 s/, 'a stream that is down: its age and why');
  assert.ok(panel(w, 'health').querySelector('dd .chip-warn'), 'stale is a warning');
  tick(w, 5000);
  assert.match(text(), /Data.*17 s old/, 'the age counts each second, with no new data');
  tick(w, 120000);
  assert.match(text(), /Data.*2 min old/, 'past two minutes it is minutes');
  // The stream is up again and this page's feed is open: Live.
  es.readyState = 1; es.emit('open');
  const up = clone(data.panels.health);
  up.data.stream = { live: true, heardAt: iso(w.clock), since: null, error: null, writtenAt: iso(w.clock) };
  es.emit('panel', { id: 'health', part: up, updatedAt: iso(w.clock) });
  assert.match(text(), /Data.*Live.*each change as it happens/);
  assert.doesNotMatch(text(), /s old/);
  // This page's own feed drops: the host's stream is still live, but what the page shows is as old as data.js.
  es.readyState = 0; es.emit('error');
  tick(w, 3000);
  assert.match(text(), /Data.*3 s old.*this page asks the build machine for news every 15 s/);
});

test('health stops saying Live when the live feed stops writing, with no new data to say so', () => {
  const w = boot({ feed: true });
  const es = w.sources[0];
  const data = full();
  data.panels.health.data.stream = { live: true, heardAt: iso(T0), since: null, error: null, writtenAt: iso(T0) };
  es.readyState = 0; es.emit('error'); // the feed opens after a first failed try: the page is drawn from data.js meanwhile
  deliver(w, data);
  es.readyState = 1; es.emit('open');
  es.emit('panel', { id: 'health', part: clone(data.panels.health), updatedAt: iso(T0) });
  const text = () => panel(w, 'health').textContent;
  assert.match(text(), /Data.*Live/);
  // A quiet feed builds data.js again only every 45 s (dashboard_stream.py KEEP), so its writtenAt can be about 60 s
  // old: still live then. Bug caught: a 30 s window called a quiet live feed stopped between those builds.
  tick(w, 89000);
  assert.match(text(), /Data.*Live/, 'within the feed\'s rewrite window it is still live');
  tick(w, 2000);
  assert.doesNotMatch(text(), /Live/);
  assert.match(text(), /Data.*91 s old.*the live feed stopped/, 'its age counts from when the host was last heard');
  // A live stream that names no write time is not taken as live.
  const old = clone(data.panels.health);
  old.data.stream = { live: true, heardAt: iso(w.clock), since: null, error: null };
  es.emit('panel', { id: 'health', part: old, updatedAt: iso(w.clock) });
  assert.match(text(), /Data.*0 s old.*the live feed stopped/);
});

test('the live feed: a change to a panel of the other tab is kept and drawn when that tab opens; its count on the tab moves at the next frame', () => {
  const w = boot({ feed: true });
  const es = w.sources[0];
  es.readyState = 0; es.emit('error'); // the feed opens after a first failed try: the page is drawn from data.js meanwhile
  deliver(w, full());
  es.readyState = 1; es.emit('open');
  const part = clone(full().panels.rules);
  part.data.state = 'paused';
  es.emit('panel', { id: 'rules', part, updatedAt: iso(T0) });
  assert.equal(panel(w, 'rules'), null, 'the Rules panel is not drawn on Overview');
  // The tabs are drawn at most once a frame, after every event that came before that frame (issue 498).
  for (const f of w.frames.splice(0)) f();
  assert.equal(w.document.getElementById('tab-rules').querySelector('.tab-count').textContent, '· 1', 'Rules counts the pause');
  w.document.getElementById('tab-rules').click();
  assert.equal(state(w, 'rules'), 'ready');
  // Its figures are in What these rules produce, a panel drawn from the same part.
  assert.equal(panel(w, 'rules-produce').querySelector('[data-figure]') !== null, true);
});

test('the seconds since a running step\'s last output count each second', () => {
  const w = boot({ feed: true });
  const es = w.sources[0];
  es.readyState = 0; es.emit('error'); // the feed opens after a first failed try: the page is drawn from data.js meanwhile
  deliver(w, full());
  es.readyState = 1; es.emit('open');
  const part = clone(full().panels.belt);
  part.data.cards[0].live = { turns: 1, lastOutputAt: iso(w.clock - 6000), action: 'Read' };
  es.emit('panel', { id: 'belt', part, updatedAt: iso(w.clock) });
  assert.ok(panel(w, 'belt').textContent.includes('6 s since its last output'));
  tick(w, 3000);
  assert.ok(panel(w, 'belt').textContent.includes('9 s since its last output'));
});

test('health has no age line for a reading that names no stream', () => {
  const w = boot();
  deliver(w, full());
  assert.doesNotMatch(panel(w, 'health').textContent, /Data|s old|Live/);
});
