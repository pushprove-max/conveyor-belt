// SPDX-License-Identifier: Apache-2.0
// The dashboard page's layout: motion and reduced motion, the layout the owner arranges (kept in the browser, restored,
// reset), a panel's length, how the panels fill the page, and the five-row long lists. Shared setup:
// dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { html, css, read, T0, STORE, iso, clone, OVERVIEW, CONTROL_IDS, BELT3D_IDS, RULES_IDS, TESTS_IDS, SIZES0, CONTROL_SIZES, RULES_SIZES, boot, $, panel, state, order, saved, kept,
  settle, deliver, next, later, key, P, CARD_METRICS, full, act, moreText, groupEl, rowsOf, heldMany, cases, setSize, hidePanel } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

// ---- reduced motion ----
test('under reduced motion nothing animates', () => {
  const w = boot({ reducedMotion: true, rects: true });
  assert.equal(w.document.documentElement.dataset.motion, 'off');
  deliver(w, full());
  const data = full();
  data.panels.cost.data.cards.todayUsd = 9;
  next(w, data);
  assert.equal(panel(w, 'cost').querySelector('[data-figure="today"] .num').textContent, '$9.00', 'a number shows its new value at once');
  assert.equal(w.frames.length, 0, 'no frame was asked for');
  panel(w, 'belt').querySelector('.move-down').click();
  for (const id of OVERVIEW) assert.equal(panel(w, id).style.transform + panel(w, id).style.transition, '', `${id} is placed, not moved`);
  // The first draw also set the history's minute timer (app.js, HISTORY_MS): only the timers the collapse sets count.
  const before = w.timeouts.length;
  panel(w, 'queue').querySelector('.tool.collapse').click();
  assert.equal(panel(w, 'queue').querySelector('.panel-body').hidden, true, 'a collapsed body is gone at once');
  assert.equal(panel(w, 'queue').querySelector('.panel-body').classList.contains('folding'), false);
  assert.equal(w.timeouts.length, before, 'and no timer was set');
  // The stylesheet turns off what it animates itself, by the system setting and by the page's own switch.
  assert.match(css, /@media \(prefers-reduced-motion: reduce\) \{\s*\*, \*::before, \*::after \{ animation: none !important; transition: none !important; \}\s*\}/);
  assert.match(css, /:root\[data-motion="off"\] \*[^{]*\{ animation: none !important; transition: none !important; \}/);
});

test('with motion on, a moved panel slides from where it was: transform only, under 300 ms', () => {
  const w = boot({ rects: true });
  assert.equal(w.document.documentElement.dataset.motion, 'on');
  deliver(w, full());
  panel(w, 'needs').querySelector('.move-down').click();
  assert.match(panel(w, 'needs').style.transition, /^transform 260ms/);
  assert.match(panel(w, 'belt').style.transition, /^transform 260ms/);
  assert.equal(panel(w, 'cost').style.transition, '', 'a panel that did not move is left alone');
});

test('the stylesheet animates transform and opacity only; outside the name\'s belt, each under 300 ms and none loops', () => {
  for (const [, list] of css.matchAll(/transition:\s*([^;]+);/g)) {
    for (const part of list.split(',')) assert.match(part.trim(), /^(transform|opacity|none)\b/, `a transition of something else: ${part}`);
  }
  for (const [, name, body] of css.matchAll(/@keyframes (\w+) \{((?:[^{}]*\{[^{}]*\})+)\s*\}/g)) {
    for (const [, prop] of body.matchAll(/([a-z-]+)\s*:/g)) assert.ok(['opacity', 'transform'].includes(prop), `@keyframes ${name} animates ${prop}`);
  }
  assert.ok(css.includes('@keyframes rise') && css.includes('@keyframes ring'));
  // The name's belt in the head (issue 343) is the one loop the owner approved; its own tests are in dashboard-view.brand.test.mjs.
  const start = css.indexOf('/* ---- the name\'s belt ---- */'), end = css.indexOf('/* ---- end of the name\'s belt ---- */');
  assert.ok(start > 0 && end > start, 'the name\'s belt is one marked section');
  // Belt 3D's floor keeps the mockup's motion, which the owner approved (issue 345): longer fades, the details' slide
  // and the live status dot's pulse, its one loop. It is one marked section too, holding nothing else that moves.
  const f0 = css.indexOf('/* ---- the floor\'s motion ---- */'), f1 = css.indexOf('/* ---- end of the floor\'s motion ---- */');
  assert.ok(f0 > end && f1 > f0, 'the floor\'s motion is one marked section');
  const floor = css.slice(f0, f1);
  assert.ok(floor.split('\n').filter((l) => /\b(transition|animation):/.test(l)).every((l) => /^\.b3-/.test(l)), 'it moves only the floor\'s own elements');
  assert.deepEqual(Array.from(floor.matchAll(/animation: (\S+)[^;]*infinite/g), (m) => m[1]), ['b3-live'], 'its one loop is the live status dot\'s');
  // The deck behind the floor keeps its mockup's loops, which the owner approved (issue 393): the grid's roll (3 s),
  // the rings' turns (40 s, and 26 s the other way) and the readout's bar (8 s); its scan line is gone (issue 404).
  // One marked section too, moving only the deck's own elements.
  const d0 = css.indexOf('/* ---- the deck\'s motion ---- */'), d1 = css.indexOf('/* ---- end of the deck\'s motion ---- */');
  assert.ok(d0 > f1 && d1 > d0, 'the deck\'s motion is one marked section');
  const deck = css.slice(d0, d1);
  assert.ok(deck.split('\n').filter((l) => /\b(transition|animation):/.test(l)).every((l) => /^\.b3-(grid|ring|ro)\b/.test(l)), 'it moves only the deck\'s own elements');
  assert.deepEqual(Array.from(deck.matchAll(/animation: (\S+) (\S+) [^;]*infinite/g), (m) => `${m[1]} ${m[2]}`), ['b3-roll 3s', 'b3-spin 40s', 'b3-spin 26s', 'b3-bar 8s'],
    'its loops are the approved ones, at their pace');
  const rest = css.slice(0, start) + css.slice(end, f0) + css.slice(f1, d0) + css.slice(d1);
  const times = Array.from(rest.matchAll(/\b(\d+)ms\b/g), (m) => Number(m[1]));
  assert.ok(times.length > 0 && times.every((t) => t < 300), `every duration is under 300 ms: ${times}`);
  assert.doesNotMatch(rest, /\b\d*\.?\d+s\b/, 'no duration is given in seconds');
  assert.doesNotMatch(rest, /infinite/, 'nothing loops');
});

test('a collapsing panel fades its body out, then the panels below slide up; opened again, the body is back', () => {
  const w = boot({ rects: true });
  deliver(w, full());
  const fold = panel(w, 'belt').querySelector('.tool.collapse'), body = panel(w, 'belt').querySelector('.panel-body');
  // The first draw also set the history's minute timer (app.js, HISTORY_MS): only the timers the collapse sets count.
  const before = w.timeouts.length;
  fold.click();
  assert.equal(fold.getAttribute('aria-expanded'), 'false', 'the control says collapsed at once');
  assert.deepEqual(kept(w).collapsed, ['belt']);
  assert.equal(body.hidden, false, 'the body is still there while it fades');
  assert.ok(body.classList.contains('folding'));
  assert.deepEqual(w.timeouts.slice(before).map((t) => t.ms), [140], 'the fade is timed, under 300 ms');
  assert.match(css, /\.panel-body\.folding \{ opacity: 0; transform: translateY\(-6px\);[^}]*transition: transform 140ms var\(--ease\), opacity 140ms var\(--ease\); \}/);
  // A refresh in the middle of the fade does not cut it short.
  next(w, full());
  assert.equal(body.hidden, false);
  // jsdom lays nothing out, so the body's going moves no box here: the panel below is given its new place by hand.
  const queue = panel(w, 'queue');
  queue.getBoundingClientRect = () => { const top = body.hidden ? 120 : 200; return { left: 0, top, right: 300, bottom: top + 90, width: 300, height: 90 }; };
  later(w);
  assert.equal(body.hidden, true);
  assert.equal(body.classList.contains('folding'), false);
  assert.match(queue.style.transition, /^transform 260ms/, 'the panel below slides up to close the gap');
  later(w);
  // Collapsed and opened again before the fade ends: the body stays.
  fold.click();
  assert.equal(body.hidden, false);
  fold.click();
  assert.ok(body.classList.contains('folding'));
  fold.click();
  assert.equal(body.classList.contains('folding'), false);
  later(w);
  assert.equal(body.hidden, false, 'a panel opened again during the fade stays open');
  assert.equal(fold.getAttribute('aria-expanded'), 'true');
});

test('a layout control keeps the keyboard focus after it is used', () => {
  const w = boot();
  deliver(w, full());
  // The width controls are in the Customize sheet: open it, as the owner does, since a control in a closed (hidden)
  // sheet cannot take the focus (jsdom 31, as a browser).
  w.document.getElementById('customize-open').click();
  for (const id of ['needs', 'landed', 'cost']) {
    const fold = panel(w, id).querySelector('.tool.collapse');
    fold.focus(); fold.click();
    assert.equal(w.document.activeElement, fold, `${id}: collapse keeps the focus`);
    later(w);
    assert.equal(w.document.activeElement, fold, `${id}: and still has it once the body is gone`);
    fold.click();
    assert.equal(w.document.activeElement, fold, `${id}: expand keeps the focus`);
    // Customize is drawn again at each change: its width control keeps the focus all the same.
    w.document.getElementById(`size-${id}`).focus();
    setSize(w, id, 'full');
    assert.equal(w.document.activeElement, w.document.getElementById(`size-${id}`), `${id}: resize keeps the focus`);
    assert.equal(panel(w, id).isConnected, true);
  }
  // No panel left its place, so none was taken out of the page and put back.
  const grid = w.document.getElementById('grid');
  let moved = 0;
  new w.MutationObserver((list) => { moved += list.length; }).observe(grid, { childList: true });
  setSize(w, 'queue', 'wide');
  panel(w, 'queue').querySelector('.tool.collapse').click();
  return settle().then(() => assert.equal(moved, 0, 'a resize and a collapse move no panel in the page'));
});

// ---- the layout the owner arranges: kept in the browser, restored, reset ----
test('the default layout is the list, at each panel\'s own width, comfortable, with the system theme', () => {
  const w = boot();
  const root = w.document.documentElement;
  assert.deepEqual(order(w), OVERVIEW);
  assert.deepEqual(OVERVIEW.map((id) => panel(w, id).dataset.size), OVERVIEW.map((id) => SIZES0[id]));
  const c = boot({ tab: 'control' });
  assert.deepEqual(CONTROL_IDS.map((id) => panel(c, id).dataset.size), CONTROL_IDS.map((id) => CONTROL_SIZES[id]));
  const r = boot({ tab: 'rules' });
  assert.deepEqual(RULES_IDS.map((id) => panel(r, id).dataset.size), RULES_IDS.map((id) => RULES_SIZES[id]));
  assert.equal(root.dataset.density, 'comfortable');
  assert.equal(root.dataset.theme, undefined, 'no theme chosen follows the system');
  assert.equal(w.localStorage.getItem(STORE), null, 'nothing is kept until the owner changes something');
  assert.equal(w.posts.length, 0);
});

test('reordering, resizing, collapsing and hiding persist in the browser and are restored on the next visit', async () => {
  const w = boot();
  deliver(w, full());
  key(w, panel(w, 'needs').querySelector('.drag'), 'ArrowDown');
  assert.deepEqual(order(w).slice(0, 3), ['belt', 'needs', 'queue'], 'an arrow key on the handle moves the panel');
  assert.equal(w.document.activeElement, panel(w, 'needs').querySelector('.drag'), 'and the handle keeps the focus');
  assert.match(w.document.getElementById('announce').textContent, /Needs you moved to place 2 of 10/);
  key(w, panel(w, 'needs').querySelector('.drag'), 'ArrowUp');
  assert.deepEqual(order(w), OVERVIEW);
  panel(w, 'cost').querySelector('.move-up').click();
  assert.deepEqual(order(w).slice(-4), ['health', 'cost', 'lanes', 'metrics']);
  const size = () => w.document.getElementById('size-queue');
  assert.equal(size().value, 'small');
  assert.equal(size().getAttribute('aria-label'), 'Width of Queue');
  assert.deepEqual(Array.from(size().options, (o) => o.textContent), ['Small', 'Wide', 'Full']);
  setSize(w, 'queue', 'wide');
  assert.equal(panel(w, 'queue').dataset.size, 'wide');
  assert.equal(size().value, 'wide');
  setSize(w, 'queue', 'full');
  assert.equal(panel(w, 'queue').dataset.size, 'full');
  const fold = panel(w, 'landed').querySelector('.tool.collapse');
  fold.click();
  later(w);
  assert.equal(panel(w, 'landed').querySelector('.panel-body').hidden, true);
  assert.equal(fold.getAttribute('aria-expanded'), 'false');
  assert.equal(fold.getAttribute('aria-label'), 'Expand Landed today');
  hidePanel(w, 'belt');
  assert.equal(panel(w, 'belt').hidden, true);
  assert.equal($(w, '#customize-open .label').textContent, 'Customize (1 hidden)');
  assert.deepEqual(saved(w), {
    tabs: {
      overview: { order: ['needs', 'belt', 'queue', 'landed', 'release', 'declined', 'health', 'cost', 'lanes', 'metrics'], sizes: { ...SIZES0, queue: 'full' }, lengths: {}, collapsed: ['landed'], hidden: ['belt'] },
      belt3d: { order: BELT3D_IDS, sizes: { belt3d: 'full' }, lengths: {}, collapsed: [], hidden: [] },
      control: { order: CONTROL_IDS, sizes: CONTROL_SIZES, lengths: {}, collapsed: [], hidden: [] },
      rules: { order: RULES_IDS, sizes: RULES_SIZES, lengths: {}, collapsed: [], hidden: [] },
      tests: { order: TESTS_IDS, sizes: { tests: 'full' }, lengths: {}, collapsed: [], hidden: [] },
    },
    density: 'comfortable', theme: 'system' });
  await settle();
  assert.equal(w.posts.length, 0, 'the layout is kept in the browser: nothing was sent to the host');

  const again = boot({ store: { [STORE]: w.localStorage.getItem(STORE) } });
  assert.deepEqual(order(again), ['needs', 'queue', 'landed', 'release', 'declined', 'health', 'cost', 'lanes', 'metrics']);
  assert.equal(panel(again, 'belt').hidden, true);
  assert.equal(panel(again, 'queue').dataset.size, 'full');
  assert.equal(panel(again, 'landed').querySelector('.panel-body').hidden, true);
  deliver(again, full());
  assert.equal(panel(again, 'landed').querySelector('.panel-body').hidden, true, 'a collapsed panel stays collapsed when its data arrives');
  assert.equal(state(again, 'landed'), 'ready', 'and is drawn, ready for when it is opened');
});

test('a hidden panel stays hidden after a refresh, and Customize brings it back', () => {
  const w = boot();
  deliver(w, full());
  hidePanel(w, 'queue');
  const changed = full();
  changed.panels.queue.data.next.pop();
  next(w, changed);
  next(w, full());
  assert.equal(panel(w, 'queue').hidden, true, 'new data does not show a hidden panel');
  assert.ok(!order(w).includes('queue'));
  w.document.getElementById('customize-open').click();
  assert.equal(w.document.getElementById('customize').hidden, false);
  const box = w.document.getElementById('show-queue');
  assert.equal(box.checked, false);
  assert.equal(w.document.getElementById('show-board'), null, 'Customize lists the panels of the tab in view');
  w.document.getElementById('show-queue').click();
  assert.equal(panel(w, 'queue').hidden, false);
  assert.deepEqual(kept(w).hidden, []);
  assert.equal(state(w, 'queue'), 'ready', 'it comes back with the data it was given while hidden');
  key(w, w.document.body, 'Escape');
  assert.equal(w.document.getElementById('customize').hidden, true, 'Escape closes Customize');
});

test('restore default layout puts everything back and keeps it that way', () => {
  // A layout kept before the tabs was the one page's: it is Overview's now; the Control tab starts at its default.
  const store = { [STORE]: JSON.stringify({ order: ['cost', 'belt', 'needs', 'board'], sizes: { belt: 'small', board: 'small' }, lengths: { queue: 3 }, collapsed: ['cost'], hidden: ['belt', 'queue'], density: 'compact', theme: 'dark' }) };
  const w = boot({ store });
  const root = w.document.documentElement;
  assert.deepEqual(order(w), ['cost', 'needs', 'landed', 'release', 'declined', 'health', 'lanes', 'metrics'], 'a kept order comes first; a panel it does not name follows in the default order');
  assert.equal(root.dataset.density, 'compact');
  assert.equal(root.dataset.theme, 'dark');
  w.document.getElementById('customize-open').click();
  w.document.getElementById('restore-layout').click();
  assert.deepEqual(order(w), OVERVIEW);
  for (const id of OVERVIEW) {
    assert.equal(panel(w, id).hidden, false);
    assert.equal(panel(w, id).querySelector('.panel-body').hidden, false);
  }
  assert.equal(panel(w, 'belt').dataset.size, 'wide');
  assert.equal(root.dataset.density, 'comfortable');
  assert.equal(root.dataset.theme, undefined);
  assert.deepEqual(saved(w), { tabs: { overview: { order: OVERVIEW, sizes: SIZES0, lengths: {}, collapsed: [], hidden: [] }, belt3d: { order: BELT3D_IDS, sizes: { belt3d: 'full' }, lengths: {}, collapsed: [], hidden: [] }, control: { order: CONTROL_IDS, sizes: CONTROL_SIZES, lengths: {}, collapsed: [], hidden: [] }, rules: { order: RULES_IDS, sizes: RULES_SIZES, lengths: {}, collapsed: [], hidden: [] }, tests: { order: TESTS_IDS, sizes: { tests: 'full' }, lengths: {}, collapsed: [], hidden: [] } }, density: 'comfortable', theme: 'system' });
  assert.deepEqual(order(boot({ store: { [STORE]: w.localStorage.getItem(STORE) } })), OVERVIEW);
});

test('a kept layout the page cannot use is ignored piece by piece, never a broken page', () => {
  for (const bad of ['{not json', 'null', '"text"', JSON.stringify({ order: ['ghost', 'belt', 'belt', 7], sizes: { belt: 'huge', queue: 4 }, lengths: { belt: -1, queue: 'many' }, collapsed: 'all', hidden: ['ghost'], density: 'tiny', theme: 'neon' }),
    JSON.stringify({ tabs: { overview: { order: 'x', lengths: null }, control: 7, ghost: {} }, density: 3 })]) {
    const w = boot({ store: { [STORE]: bad } });
    assert.equal(order(w).length, OVERVIEW.length, `every panel shows for ${bad}`);
    assert.equal(panel(w, 'belt').dataset.length, '5', 'a length the page cannot use is the default');
    assert.equal(panel(w, 'belt').dataset.size, 'wide');
    assert.equal(w.document.documentElement.dataset.density, 'comfortable');
    assert.equal(w.document.documentElement.dataset.theme, undefined);
  }
});

test('density and theme are chosen in Customize and kept', () => {
  const w = boot();
  const root = w.document.documentElement;
  w.document.getElementById('customize-open').click();
  const pick = (name, value) => { const r = $(w, `#customize input[name="choice-${name}"][value="${value}"]`); r.checked = true; r.dispatchEvent(new w.Event('change', { bubbles: true })); };
  assert.deepEqual(Array.from(w.document.querySelectorAll('#customize input[name="choice-theme"]')).map((r) => r.value), ['system', 'light', 'dark']);
  assert.deepEqual(Array.from(w.document.querySelectorAll('#customize input[name="choice-density"]')).map((r) => r.value), ['comfortable', 'compact']);
  pick('density', 'compact');
  assert.equal(root.dataset.density, 'compact');
  pick('theme', 'dark');
  assert.equal(root.dataset.theme, 'dark');
  assert.equal($(w, '#customize input[name="choice-theme"][value="dark"]').checked, true);
  pick('theme', 'light');
  assert.equal(root.dataset.theme, 'light');
  assert.deepEqual([saved(w).density, saved(w).theme], ['compact', 'light']);
  pick('theme', 'system');
  assert.equal(root.dataset.theme, undefined, 'system is no theme of the page\'s own');
});

test('dragging a panel by its handle makes room as it goes and keeps the order on drop', () => {
  const w = boot();
  deliver(w, full());
  const handle = panel(w, 'needs').querySelector('.drag');
  assert.equal(handle.getAttribute('draggable'), 'true');
  handle.dispatchEvent(new w.Event('dragstart', { bubbles: true }));
  assert.ok(panel(w, 'needs').classList.contains('dragging'));
  const over = new w.Event('dragover', { bubbles: true, cancelable: true });
  Object.assign(over, { clientX: 10, clientY: 10 });
  panel(w, 'queue').dispatchEvent(over);
  assert.equal(over.defaultPrevented, true, 'the panel under the pointer takes the drop');
  assert.deepEqual(order(w).slice(0, 4), ['belt', 'queue', 'needs', 'landed'], 'the dragged panel is placed past the one it is over');
  assert.equal(w.localStorage.getItem(STORE), null, 'nothing is kept until the drop');
  handle.dispatchEvent(new w.Event('dragend', { bubbles: true }));
  assert.ok(!panel(w, 'needs').classList.contains('dragging'));
  assert.deepEqual(kept(w).order.slice(0, 4), ['belt', 'queue', 'needs', 'landed']);
});

test('at phone width the page is one column, and move up and move down replace dragging', () => {
  const phone = css.slice(css.indexOf('@media (max-width: 700px)'));
  assert.match(phone, /\.grid \{ grid-template-columns: minmax\(0, 1fr\);/, 'one column');
  assert.match(phone, /\.panel, \.panel\[data-size="wide"\], \.panel\[data-size="full"\] \{ grid-column: 1 \/ -1; \}/, 'every width is the full column');
  assert.match(phone, /\.drag, \.custom-size \{ display: none; \}/, 'no drag handle, and no width to change');
  assert.match(phone, /\.move \{ display: inline-flex; \}/, 'the move buttons show');
  assert.match(css.slice(0, css.indexOf('@media (max-width: 1080px)')), /\.move \{ display: none; \}/, 'which are off at desktop width');
  assert.match(html, /<meta name="viewport" content="width=device-width, initial-scale=1">/);
  const w = boot();
  const up = (id) => panel(w, id).querySelector('.move-up'), down = (id) => panel(w, id).querySelector('.move-down');
  assert.equal(up('needs').disabled, true, 'the first panel cannot move up');
  assert.equal(down('metrics').disabled, true, 'the last cannot move down');
  assert.equal(up('belt').getAttribute('aria-label'), 'Move On the belt up');
  down('needs').click();
  down('needs').click();
  assert.deepEqual(order(w).slice(0, 3), ['belt', 'queue', 'needs']);
  up('landed').click();
  up('landed').click();
  up('landed').click();
  up('landed').click();
  assert.deepEqual(order(w).slice(0, 4), ['landed', 'belt', 'queue', 'needs']);
  assert.equal(up('landed').disabled, true);
  assert.equal(w.document.activeElement, down('landed'), 'the focus stays on the panel that moved');
  hidePanel(w, 'landed');
  assert.equal(up('belt').disabled, true, 'a hidden panel is not a place to move past');
  assert.deepEqual(kept(w).order.slice(0, 4), ['landed', 'belt', 'queue', 'needs']);
  // The Board is one list there, with buttons on its cards in place of dragging them.
  assert.match(phone, /\.board \{ grid-template-columns: minmax\(0, 1fr\);/, 'the Board is one list');
  assert.match(phone, /\.board-moves \{ display: flex; \}/, 'its cards show Hold, Release, Move up and Move down');
  assert.match(css.slice(0, css.indexOf('@media (max-width: 1080px)')), /\.board-moves \{ display: none; \}/, 'which are off at desktop width');
});

// ---- a panel's length ----
const queueOf = (n) => { const d = full(); d.panels.queue.data.next = Array.from({ length: n }, (_, i) => ({ repo: 'sample', issue: 100 + i, title: `Issue ${i}`, priority: 'P2', followup: false, retried: false, url: null })); d.panels.queue.data.awaitingDeploy = []; return d; };
const foot = (w, id) => panel(w, id).querySelector('.panel-foot');
const grip = (w, id) => panel(w, id).querySelector('.panel-length');
const lengthOk = (v) => v === 'all' || (Number.isInteger(v) && v >= 1);
test('a long list scrolls inside its panel, says how many rows there are, and shows all with one control', () => {
  const w = boot();
  deliver(w, queueOf(23));
  const body = panel(w, 'queue').querySelector('.panel-body');
  assert.ok(body.classList.contains('scrolls'), 'the body scrolls; the head stays');
  assert.match(body.style.maxHeight, /^\d+px$/, 'cut at its length');
  assert.equal(foot(w, 'queue').hidden, false);
  assert.equal(foot(w, 'queue').querySelector('.panel-rows').textContent, '8 of 23', 'the default length of the queue is 8 rows');
  assert.equal(panel(w, 'queue').querySelector('.panel-head').parentNode, panel(w, 'queue'), 'the head is outside the scrolling body');
  const all = foot(w, 'queue').querySelector('.show-all');
  assert.equal(all.textContent, 'Show all');
  all.click();
  assert.equal(body.classList.contains('scrolls'), false);
  assert.equal(body.style.maxHeight, '');
  assert.equal(foot(w, 'queue').querySelector('.panel-rows').textContent, 'All 23');
  assert.equal(all.textContent, 'Show fewer');
  assert.equal(kept(w).lengths.queue, 'all');
  all.click();
  assert.equal(foot(w, 'queue').querySelector('.panel-rows').textContent, '8 of 23');
  assert.deepEqual(kept(w).lengths, {}, 'back to the default, nothing kept');
  // A list that fits says nothing and has nothing to show.
  next(w, queueOf(3));
  assert.equal(foot(w, 'queue').hidden, true);
  assert.equal(body.classList.contains('scrolls'), false);
});

test('a panel\'s length is changed with its handle by keyboard, kept, and cleared by restore', () => {
  const w = boot();
  deliver(w, queueOf(23));
  const g = grip(w, 'queue');
  assert.equal(g.getAttribute('role'), 'slider');
  assert.equal(g.tabIndex, 0);
  assert.equal(g.getAttribute('aria-valuetext'), '8 of 23 rows shown');
  g.focus();
  key(w, g, 'ArrowUp');
  assert.equal(foot(w, 'queue').querySelector('.panel-rows').textContent, '7 of 23');
  assert.equal(w.document.activeElement, g, 'the handle keeps the focus');
  key(w, g, 'PageDown');
  assert.equal(foot(w, 'queue').querySelector('.panel-rows').textContent, '12 of 23');
  assert.equal(kept(w).lengths.queue, 12);
  key(w, g, 'Home');
  assert.equal(foot(w, 'queue').querySelector('.panel-rows').textContent, '1 of 23');
  key(w, g, 'End');
  assert.equal(kept(w).lengths.queue, 'all');
  key(w, g, 'Home');
  // Kept: a reload opens the panel at the length the owner set.
  const again = boot({ store: { [STORE]: w.localStorage.getItem(STORE) } });
  deliver(again, queueOf(23));
  assert.equal(foot(again, 'queue').querySelector('.panel-rows').textContent, '1 of 23');
  again.document.getElementById('restore-layout').click();
  assert.equal(foot(again, 'queue').querySelector('.panel-rows').textContent, '8 of 23', 'restore clears it');
  assert.deepEqual(kept(again).lengths, {});
  // Dragging the lower edge: the rows that end above where it is let go.
  const d = boot({ rects: true });
  deliver(d, queueOf(23));
  const h = d.document.getElementById('panel-queue').querySelector('.panel-length');
  h.dispatchEvent(Object.assign(new d.Event('pointerdown', { bubbles: true }), { button: 0, clientY: 500 }));
  d.document.dispatchEvent(Object.assign(new d.Event('pointerup'), { clientY: 500 }));
  assert.ok(lengthOk(kept(d).lengths.queue), `a drag sets a length: ${JSON.stringify(kept(d).lengths)}`);
});

test('a panel with none of its rows (Cost: figures, empty lists) keeps its length handle, by keyboard and by drag', () => {
  const d = full();
  d.panels.cost.data.cards.perCard = [];
  d.panels.cost.data.cards.unpriced = [];
  const w = boot();
  deliver(w, d);
  const g = grip(w, 'cost');
  assert.equal(g.hidden, false, 'the handle is there');
  assert.equal(g.getAttribute('aria-valuetext'), '3 of 3 rows shown', 'the blocks of its body are its rows: figures, landed line, sessions line');
  g.focus();
  key(w, g, 'ArrowUp');
  assert.equal(kept(w).lengths.cost, 2, 'the keyboard sets its length');
  assert.equal(foot(w, 'cost').querySelector('.panel-rows').textContent, '2 of 3');
  const r = boot({ rects: true });
  deliver(r, d);
  const h = grip(r, 'cost');
  h.dispatchEvent(Object.assign(new r.Event('pointerdown', { bubbles: true }), { button: 0, clientY: 500 }));
  r.document.dispatchEvent(Object.assign(new r.Event('pointerup'), { clientY: 500 }));
  assert.ok(lengthOk(kept(r).lengths.cost), `a drag sets a length: ${JSON.stringify(kept(r).lengths)}`);
});

test('a resize of the window cuts a panel to its length again at the height its rows wrap to', () => {
  const w = boot();
  // Each row of the queue is rowH tall from the top of its body; a narrower window wraps them taller.
  w.rowH = 20;
  const real = w.Element.prototype.getBoundingClientRect;
  w.Element.prototype.getBoundingClientRect = function () {
    const body = this.closest && this.closest('#panel-queue .panel-body');
    if (body && this.matches('.rows > li')) {
      const i = Array.from(body.querySelectorAll('.rows > li')).indexOf(this);
      return { left: 0, right: 300, width: 300, top: i * w.rowH, bottom: (i + 1) * w.rowH, height: w.rowH };
    }
    return real.call(this);
  };
  deliver(w, queueOf(23));
  const body = panel(w, 'queue').querySelector('.panel-body');
  const at = (h) => `${Math.max(48, Math.ceil(8 * h + 16))}px`;
  assert.equal(body.style.maxHeight, at(20), 'cut after its eighth row');
  w.rowH = 45;
  w.dispatchEvent(new w.Event('resize'));
  while (w.frames.length) w.frames.shift()();
  assert.equal(body.style.maxHeight, at(45), 'cut again after its eighth row, now taller');
  assert.equal(foot(w, 'queue').querySelector('.panel-rows').textContent, '8 of 23');
});

// ---- the panels fill the page ----
const { pack } = (() => { const w = boot({ list: [] }); return w.DASH_APP; })();
// The cells left empty with a panel under them in the same column, each with the largest free block there: one that
// a panel lower on the page could fill is a hole that should not be. (A panel above it that fits would only leave a
// hole of its own where it was.)
function holes(placed, items, cols) {
  const at = (r, c) => placed.some((p) => r >= p.row && r < p.row + p.h && c >= p.col && c < p.col + p.w);
  const bad = [];
  for (let c = 0; c < cols; c++) {
    for (let r = 0; r < Math.max(...placed.map((p) => p.row + p.h)); r++) {
      if (at(r, c) || !placed.some((p) => p.col <= c && c < p.col + p.w && p.row > r)) continue;
      let down = 0; while (!at(r + down, c) && placed.some((p) => p.col <= c && c < p.col + p.w && p.row > r + down)) down++;
      let left = c, right = c; while (left > 0 && !at(r, left - 1)) left--; while (right < cols - 1 && !at(r, right + 1)) right++;
      const lower = placed.filter((p) => p.row >= r + down).map((p) => items.find((it) => it.id === p.id));
      if (lower.some((it) => Math.min(it.w, cols) <= right - left + 1 && Math.ceil(it.h) <= down)) bad.push([r, c]);
    }
  }
  return bad;
}
const MIXES = {
  'the live page: Needs you and On the belt wide, Queue and Landed long': [['needs', 2, 12], ['belt', 2, 18], ['queue', 1, 40], ['landed', 2, 45], ['health', 1, 22], ['lanes', 1, 10], ['cost', 2, 25], ['metrics', 2, 30]],
  'small, wide and full mixed': [['a', 3, 20], ['b', 2, 30], ['c', 1, 10], ['d', 3, 15], ['e', 1, 40], ['f', 1, 5], ['g', 2, 8], ['h', 1, 33]],
  'collapsed ones among tall ones': [['a', 2, 6], ['b', 1, 50], ['c', 1, 6], ['d', 2, 44], ['e', 1, 6], ['f', 3, 6], ['g', 1, 21]],
  'one tall beside many short': [['a', 1, 80], ['b', 1, 9], ['c', 1, 9], ['d', 1, 9], ['e', 1, 9], ['f', 2, 9], ['g', 1, 9]],
};
test('for a layout of mixed short and tall panels at three, two and one column, no panel has an empty block above it that another could fill', () => {
  for (const [name, mix] of Object.entries(MIXES)) {
    for (const cols of [3, 2, 1]) {
      const items = mix.map(([id, w, h]) => ({ id, w: Math.min(w, cols), h }));
      const placed = pack(items, cols);
      assert.deepEqual(placed.map((p) => p.id), items.map((x) => x.id), 'every panel is placed, once');
      for (const p of placed) {
        assert.ok(p.col >= 0 && p.col + p.w <= cols, `${name} at ${cols}: ${p.id} is in the grid`);
        assert.ok(p.h >= Math.ceil(items.find((x) => x.id === p.id).h), `${p.id} keeps its own height at least`);
        for (const q of placed) if (q !== p) assert.ok(p.row + p.h <= q.row || q.row + q.h <= p.row || p.col + p.w <= q.col || q.col + q.w <= p.col, `${name} at ${cols}: ${p.id} and ${q.id} do not overlap`);
      }
      assert.deepEqual(holes(placed, items, cols), [], `${name} at ${cols} columns: no hole another panel could fill`);
    }
  }
  // The live page (2026-11-10): Needs you, wide, left the third column empty beside it; the Queue fills it now.
  const live = pack(MIXES['the live page: Needs you and On the belt wide, Queue and Landed long'].map(([id, w, h]) => ({ id, w, h })), 3);
  assert.deepEqual(['needs', 'queue'].map((id) => { const p = live.find((x) => x.id === id); return [p.row, p.col]; }), [[0, 0], [0, 2]]);
});

test('panels that share a row end at the same line when their lengths allow it', () => {
  const near = pack([{ id: 'a', w: 1, h: 20 }, { id: 'b', w: 1, h: 24 }, { id: 'c', w: 1, h: 23 }, { id: 'd', w: 3, h: 10 }], 3);
  assert.deepEqual(near.slice(0, 3).map((p) => p.row + p.h), [24, 24, 24]);
  const far = pack([{ id: 'a', w: 1, h: 10 }, { id: 'b', w: 2, h: 40 }], 3);
  assert.deepEqual(far.map((p) => p.h), [10, 40], 'a short one beside a much taller one keeps its own length when nothing is under it');
  // At two columns, a short or collapsed panel beside a tall one, then a full one: the short one is not stretched to
  // the tall one's height (an empty box that defeats its length); a gap of SNAP rows or less is still closed.
  for (const h of [6, 12]) {
    const two = pack([{ id: 'a', w: 1, h }, { id: 'b', w: 1, h: 60 }, { id: 'c', w: 2, h: 10 }], 2);
    assert.deepEqual(two.map((p) => [p.row, p.h]), [[0, h], [0, 60], [60, 10]], `a panel of ${h} rows beside one of 60 keeps its length`);
  }
  const close = pack([{ id: 'a', w: 1, h: 20 }, { id: 'b', w: 1, h: 26 }, { id: 'c', w: 2, h: 10 }], 2);
  assert.deepEqual(close.map((p) => p.row + p.h), [26, 26, 36]);
});

test('the page places every panel on the grid at three, two and one column; hidden and other-tab panels take no place', () => {
  for (const [width, cols] of [[1440, '3'], [900, '2'], [400, '1']]) {
    const w = boot({ width });
    deliver(w, full());
    const grid = w.document.getElementById('grid');
    assert.equal(grid.dataset.cols, cols);
    for (const id of OVERVIEW) {
      const el = panel(w, id), span = Number(cols) === 1 ? 1 : el.dataset.size === 'small' ? 1 : el.dataset.size === 'full' ? Number(cols) : Math.min(2, Number(cols));
      assert.match(el.style.gridColumn, new RegExp(`^\\d / span ${span}$`), `${id} at ${width}px`);
      assert.match(el.style.gridRow, /^\d+ \/ span \d+$/);
    }
  }
  const w = boot();
  deliver(w, full());
  hidePanel(w, 'queue');
  assert.equal(panel(w, 'queue').hidden, true);
  const rows =OVERVIEW.filter((id) => id !== 'queue').map((id) => [Number(panel(w, id).dataset.row), Number(panel(w, id).dataset.col)]);
  assert.equal(new Set(rows.map(String)).size, rows.length, 'no two panels in one place');
});

// ---- a long list: the first five, then "Show 5 more" and "Show all (N)" (the owner, on the live Board) ----
// A list of hundreds drowns the page: each long list shows the most relevant five first, and the owner asks for more.
// Each list with k items, given in the order a host could send them (oldest or cheapest first where the page sorts);
// rows(w) is that list's rows on the page, by issue number; top is the issue the page must show first.
const LONG_LISTS = {
  cost: {
    fill: (d, k) => { d.panels.cost.data.cards.perCard = Array.from({ length: k }, (_, i) => ({ repo: 'example', card: `c${i}-${300 + i}`, issue: 300 + i, title: `Card ${i}`, url: `${P}/${300 + i}`, todayUsd: 0, weekUsd: i + 0.5, state: 'landed' })); },
    rows: (w) => panel(w, 'cost').querySelectorAll('.row'), box: (w) => panel(w, 'cost'), top: (k) => 300 + k - 1, why: 'the costliest first',
  },
  metrics: {
    fill: (d, k) => { d.panels.metrics.data.cards = Array.from({ length: k }, (_, i) => ({ repo: 'example', card: `c${i}-${300 + i}`, issue: 300 + i, title: `Card ${i}`, url: `${P}/${300 + i}`, state: 'landed', at: iso(T0 - (k - i) * 60000), metrics: CARD_METRICS })); },
    rows: (w) => panel(w, 'metrics').querySelectorAll('.rows > .row'), box: (w) => panel(w, 'metrics'), top: (k) => 300 + k - 1, why: 'the newest first',
  },
  landed: {
    fill: (d, k) => { const c = d.panels.landed.data.cards[0]; d.panels.landed.data.cards = Array.from({ length: k }, (_, i) => ({ ...clone(c), card: `c${i}-${300 + i}`, issue: 300 + i, url: `${P}/${300 + i}`, time: iso(T0 - (i + 1) * 60000) })); },
    rows: (w) => panel(w, 'landed').querySelectorAll('.rows > .row'), box: (w) => panel(w, 'landed'), top: () => 300, why: 'the newest first, as the collector gives them',
  },
  needs: {
    fill: (d, k) => { d.panels.needs.data.cards.blocked = Array.from({ length: k }, (_, i) => ({ repo: 'example', card: `c${i}-${300 + i}`, issue: 300 + i, title: `Card ${i}`, reason: 'tests failed', since: iso(T0 - (k - i) * 60000), url: `${P}/${300 + i}` })); },
    rows: (w) => panel(w, 'needs').querySelectorAll('[data-group="blocked"] .rows > .row'), box: (w) => panel(w, 'needs').querySelector('[data-group="blocked"]'), top: (k) => 300 + k - 1, why: 'the newest first',
  },
};
const issueOf = (row) => Number(row.querySelector('.issue').textContent.slice(1));

test('a long list shows five, then five more, then all; a list of four has no control', () => {
  for (const [id, L] of Object.entries(LONG_LISTS)) {
    const w = boot();
    const d = full();
    L.fill(d, 12);
    deliver(w, d);
    assert.equal(L.rows(w).length, 5, `${id}: five of twelve before a click`);
    assert.equal(issueOf(L.rows(w)[0]), L.top(12), `${id}: ${L.why}`);
    assert.deepEqual(moreText(L.box(w)), ['Show 5 more', 'Show all (12)'], id);
    act(L.box(w), 'list-more').click();
    assert.equal(L.rows(w).length, 10, `${id}: ten after Show 5 more`);
    assert.deepEqual(moreText(L.box(w)), ['Show 5 more', 'Show all (12)'], `${id}: the wording stays on the last page`);
    // The choice is kept for the page's life: a new snapshot of the same list still shows ten.
    const again = clone(d);
    again.updatedAt = iso(T0);
    L.fill(again, 12);
    again.panels.cost.data.cards.todayUsd = 4.5;
    again.panels.landed.data.day = '2026-11-10';
    again.panels.metrics.data.records[0].repo = 'example-2';
    again.panels.needs.data.decisions = [];
    next(w, again);
    assert.equal(L.rows(w).length, 10, `${id}: the choice survives a redraw`);
    act(L.box(w), 'list-all').click();
    assert.equal(L.rows(w).length, 12, `${id}: all twelve`);
    assert.deepEqual(moreText(L.box(w)), [], `${id}: all shown, no control`);
    const short = boot();
    const s = full();
    L.fill(s, 4);
    deliver(short, s);
    assert.equal(L.rows(short).length, 4, `${id}: a list of four shows four`);
    assert.deepEqual(moreText(L.box(short)), [], `${id}: and no control`);
  }
});

// Fails if a panel draws a long list whole: every list above, and an open Rules group, shows at most five before a click.
test('every long list goes through the shared helper: no panel shows more than five of a longer list before a click', () => {
  const w = boot();
  const d = full();
  for (const L of Object.values(LONG_LISTS)) L.fill(d, 40);
  deliver(w, d);
  for (const [id, L] of Object.entries(LONG_LISTS)) {
    assert.equal(L.rows(w).length, 5, `${id} shows five of 40`);
    assert.deepEqual(moreText(L.box(w)), ['Show 5 more', 'Show all (40)'], id);
  }
  const r = boot({ tab: 'rules' });
  deliver(r, heldMany());
  for (const name of ['web', 'No area', 'backend']) {
    groupEl(r, name).querySelector('[data-act="group"]').click();
    assert.equal(rowsOf(groupEl(r, name)).length, 5, `Rules: ${name} opens to five`);
  }
});
