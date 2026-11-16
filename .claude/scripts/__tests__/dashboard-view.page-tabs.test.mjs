// SPDX-License-Identifier: Apache-2.0
// The dashboard page as a whole: the tabs and the head line's tiles. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { css, T0, STORE, iso, clone, CONTROL_IDS, RULES_IDS, RULES_SIZES, BELT3D_IDS, TESTS_IDS, OVERVIEW, boot, $, panel, state, order, kept, deliver, next, later, key, full, tabBtn, tiles, tile, fig, shownTiles, cases, setSize } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

// ---- the tabs: Overview reports, Control changes the loop; Rules is a tab of its own ----
test('Overview shows no Board or Rules panel, Control only the machine and the Board\'s panels, and Rules only the Rules panels', () => {
  const w = boot();
  deliver(w, full());
  assert.deepEqual(order(w), OVERVIEW);
  assert.equal(panel(w, 'board'), null, 'the Board is not drawn and takes no space on Overview');
  assert.equal(panel(w, 'rules'), null);
  tabBtn(w, 'control').click();
  assert.deepEqual(order(w), CONTROL_IDS);
  for (const id of OVERVIEW.concat(RULES_IDS)) assert.equal(panel(w, id), null, `${id} is not on Control`);
  assert.equal(state(w, 'board'), 'ready', 'the tab opened is drawn from the data already read');
  tabBtn(w, 'rules').click();
  assert.deepEqual(order(w), RULES_IDS);
  for (const id of OVERVIEW.concat(CONTROL_IDS)) assert.equal(panel(w, id), null, `${id} is not on Rules`);
  for (const id of RULES_IDS) assert.equal(state(w, id), 'ready', `${id} is drawn from the data already read`);
  tabBtn(w, 'control').click();
  // Needs you stays on Overview whatever its cause.
  const paused = full();
  paused.panels.board.data.state = 'paused';
  next(w, paused);
  assert.equal(panel(w, 'needs'), null);
});

test('the tab in view is in the address and survives a reload; Back goes to the tab before', () => {
  const w = boot();
  assert.equal(new w.URL(w.location.href).searchParams.get('tab'), 'overview', 'the address names the tab');
  assert.equal(tabBtn(w, 'overview').getAttribute('aria-selected'), 'true');
  tabBtn(w, 'control').click();
  assert.equal(new w.URL(w.location.href).searchParams.get('tab'), 'control');
  assert.equal(tabBtn(w, 'control').getAttribute('aria-selected'), 'true');
  assert.equal(tabBtn(w, 'overview').getAttribute('aria-selected'), 'false');
  assert.equal(w.document.getElementById('grid').getAttribute('aria-labelledby'), 'tab-control');
  // A reload of the page as it is (the browser keeps the tab too), and a link that names a tab.
  const again = boot({ store: { 'conveyor-board-tab': w.localStorage.getItem('conveyor-board-tab') } });
  assert.deepEqual(order(again), CONTROL_IDS, 'the tab last in view is opened again');
  const link = boot({ tab: 'overview', store: { 'conveyor-board-tab': 'control' } });
  assert.deepEqual(order(link), OVERVIEW, 'a link that names a tab opens that tab');
  tabBtn(w, 'rules').click();
  assert.equal(new w.URL(w.location.href).searchParams.get('tab'), 'rules');
  assert.deepEqual(order(boot({ store: { 'conveyor-board-tab': 'rules' } })), RULES_IDS, 'Rules is kept in the browser too');
  assert.deepEqual(order(boot({ tab: 'rules' })), RULES_IDS, 'and opened by its address');
  assert.deepEqual(order(boot({ tab: 'belt3d' })), BELT3D_IDS, '?tab=belt3d opens 3D View');
  // #520: the Tests page is a tab of its own, and a link to ?tab=tests opens it.
  assert.deepEqual(order(boot({ tab: 'tests' })), TESTS_IDS, '?tab=tests opens Tests');
  // Back: the browser restores the address before, and the page follows it.
  w.history.replaceState(null, '', 'https://dash.test/index.html?tab=overview');
  w.dispatchEvent(new w.PopStateEvent('popstate'));
  assert.deepEqual(order(w), OVERVIEW);
  assert.equal(tabBtn(w, 'overview').getAttribute('aria-selected'), 'true');
});

// Issue 408 (UX7): the Overview tab says the Needs you count ("Overview · 2"), so it is read from every tab.
// #520: Tests, the fifth, after Rules.
// #87: the 3D tab is named 3D View and sits next to Overview; this fails while it is named Belt 3D or comes after Rules.
test('the tabs are Overview, 3D View, Control, Rules and Tests, reached by keyboard, saying which one is selected; Overview counts Needs you, Rules a paused loop', () => {
  const w = boot();
  deliver(w, full());
  const list = w.document.querySelector('#tabs [role="tablist"]');
  assert.ok(list);
  const words = (b) => [b.querySelector('.tab-name').textContent, b.querySelector('.tab-count').textContent].filter(Boolean).join(' ');
  assert.deepEqual(Array.from(list.querySelectorAll('[role="tab"]'), (b) => [words(b), b.tabIndex, b.getAttribute('aria-controls')]), [['Overview · 2', 0, 'grid'], ['3D View', -1, 'grid'], ['Control', -1, 'grid'], ['Rules', -1, 'grid'], ['Tests', -1, 'grid']]);
  assert.equal(fig(w, 'needs'), '2', 'the count is the Needs you tile\'s');
  assert.equal(tabBtn(w, 'overview').getAttribute('aria-label'), 'Overview: 2 things need attention');
  tabBtn(w, 'overview').focus();
  key(w, tabBtn(w, 'overview'), 'ArrowRight');
  assert.equal(w.document.activeElement, tabBtn(w, 'belt3d'));
  assert.deepEqual(order(w), BELT3D_IDS);
  assert.equal(words(tabBtn(w, 'overview')), 'Overview · 2', 'the count stays on the Overview tab from another tab');
  key(w, tabBtn(w, 'belt3d'), 'ArrowRight');
  assert.equal(w.document.activeElement, tabBtn(w, 'control'));
  assert.deepEqual(order(w), CONTROL_IDS);
  key(w, tabBtn(w, 'control'), 'ArrowRight');
  assert.equal(w.document.activeElement, tabBtn(w, 'rules'));
  assert.deepEqual(order(w), RULES_IDS);
  assert.equal(tabBtn(w, 'rules').getAttribute('aria-selected'), 'true');
  assert.equal(w.document.getElementById('grid').getAttribute('aria-labelledby'), 'tab-rules');
  key(w, tabBtn(w, 'rules'), 'ArrowRight');
  assert.equal(w.document.activeElement, tabBtn(w, 'tests'));
  assert.deepEqual(order(w), TESTS_IDS);
  key(w, tabBtn(w, 'tests'), 'ArrowRight');
  assert.equal(w.document.activeElement, tabBtn(w, 'overview'), 'the arrows go round');
  key(w, tabBtn(w, 'overview'), 'End');
  assert.equal(w.document.activeElement, tabBtn(w, 'tests'));
  key(w, tabBtn(w, 'tests'), 'Home');
  assert.deepEqual(order(w), OVERVIEW);
  const none = full();
  none.panels.needs.data.cards.waiting = []; none.panels.needs.data.cards.blocked = [];
  next(w, none);
  assert.equal(words(tabBtn(w, 'overview')), 'Overview', 'nothing stopped for the owner: no count');
  // Running: nothing needs attention. Paused, or paused by the guard: it says so on Rules, where the pause setting is.
  for (const t of ['control', 'rules']) assert.equal(tabBtn(w, t).querySelector('.tab-count').hidden, true);
  for (const st of ['paused', 'paused by guard']) {
    const d = full();
    d.panels.board.data.state = st;
    d.panels.rules.data.state = st;
    next(w, d);
    assert.equal(tabBtn(w, 'rules').querySelector('.tab-count').textContent, '· 1', st);
    assert.equal(tabBtn(w, 'rules').getAttribute('aria-label'), 'Rules: 1 thing needs attention');
    assert.equal(tabBtn(w, 'control').querySelector('.tab-count').hidden, true, 'counted once, on Rules');
  }
});

test('each tab keeps its own layout, and restore restores the tab in view', () => {
  const w = boot();
  deliver(w, full());
  setSize(w, 'queue', 'wide');
  tabBtn(w, 'rules').click();
  panel(w, 'rules').querySelector('.tool.collapse').click();
  later(w);
  assert.deepEqual([kept(w, 'overview').sizes.queue, kept(w, 'rules').collapsed, kept(w, 'control').collapsed], ['wide', ['rules'], []]);
  w.document.getElementById('restore-layout').click();
  assert.deepEqual(order(w), RULES_IDS, 'restore restores the tab in view');
  assert.deepEqual(kept(w, 'rules'), { order: RULES_IDS, sizes: RULES_SIZES, lengths: {}, collapsed: [], hidden: [] });
  assert.equal(kept(w, 'overview').sizes.queue, 'wide', 'and leaves the other tabs as they were');
  tabBtn(w, 'overview').click();
  assert.equal(panel(w, 'queue').dataset.size, 'wide');
  // A layout kept when Rules was on Control: Control keeps the Board alone, and Rules has its panel.
  const before = JSON.stringify({ tabs: { overview: kept(w, 'overview'), control: { order: ['rules', 'board'], sizes: { board: 'full', rules: 'full' }, lengths: {}, collapsed: ['rules'], hidden: [] } }, density: 'comfortable', theme: 'system' });
  const c = boot({ tab: 'control', store: { [STORE]: before } });
  assert.deepEqual(order(c), ['board', 'machine', 'board-loop', 'board-push'], 'the Board as kept, then the panels added since, last');
  tabBtn(c, 'rules').click();
  assert.deepEqual(order(c), RULES_IDS);
});

// ---- the head line's tiles ----
test('the head line shows seven tiles in order with the figures of the snapshot, each a link to its panel, on every tab', () => {
  for (const tab of ['overview', 'control', 'rules']) {
    const w = boot({ tab });
    const top = $(w, 'header.top');
    assert.deepEqual(Array.from(top.children, (c) => c.className.split(' ')[0]), ['brand', 'stats', 'top-meta', 'top-actions'], 'between the name and the Live mark');
    deliver(w, full());
    assert.deepEqual(tiles(w).map((t) => t.querySelector('.stat-label').textContent), ['Today', '7 days', 'Per landed card', 'On the belt', 'Queued', 'Landed today', 'Needs you']);
    assert.deepEqual(tiles(w).map((t) => fig(w, t.dataset.stat)), ['$4.25', '$14.00', '$1.00', '2 of 3', '2 · 2 held', '2', '2']);
    assert.deepEqual(tiles(w).map((t) => t.getAttribute('href')), ['cost', 'cost', 'cost', 'belt', 'queue', 'landed', 'needs'].map((id) => `index.html?tab=overview#panel-${id}`));
    for (const t of tiles(w)) assert.equal(t.tagName, 'A', 'a tile is a link, reached by keyboard');
    assert.equal(shownTiles(w).length, 7);
  }
  assert.match(css, /\.stat-label \{[^}]*text-transform: uppercase;/, 'the labels are in capitals');
  assert.match(css, /\.stat \+ \.stat \{ border-left: 1px solid var\(--border\); \}/, 'a thin rule between tiles');
  // Held: the Board's split of the open issues (by the owner, by a label or rule) when the snapshot has it.
  const w = boot();
  const data = full();
  data.panels.board.data.open = { count: 186, split: { queued: 2, you: 3, labelOrRule: 180, belt: 1 }, held: [] };
  deliver(w, data);
  assert.equal(fig(w, 'queued'), '2 · 183 held');
  // The queue lists only the first ten ready issues: the count is the Board's split, not the length of that list.
  const many = full();
  many.panels.queue.data.next = Array.from({ length: 10 }, (_, i) => ({ issue: 500 + i, title: `Ready ${i}`, priority: 'P2', followup: false, retried: false }));
  many.panels.board.data.open = { count: 200, split: { queued: 13, you: 3, labelOrRule: 180, belt: 4 }, held: [] };
  const m = boot();
  deliver(m, many);
  assert.equal(fig(m, 'queued'), '13 · 183 held');
  // Without the Board's split, a list of ten may have been cut short: a dash, not 10. A shorter list is the count.
  delete many.panels.board;
  const cut = boot();
  deliver(cut, many);
  assert.equal(fig(cut, 'queued'), '—', 'ten listed with no total is no count');
  many.panels.queue.data.next = many.panels.queue.data.next.slice(0, 4);
  next(cut, many);
  assert.equal(fig(cut, 'queued').split(' ')[0], '4', 'a list shorter than ten is every ready issue');
});

test('the head tiles: a count moves through whole numbers only', () => {
  const w = boot();
  const data = full();
  data.panels.landed.data.cards = data.panels.landed.data.cards.slice(0, 1);
  deliver(w, data);
  assert.equal(fig(w, 'landed'), '1');
  next(w, full());
  const seen = [];
  for (let i = 0; i < 6; i += 1) {
    w.clock += 60;
    for (const f of w.frames.splice(0)) f();
    seen.push(fig(w, 'landed'));
  }
  for (const s of seen) assert.match(s, /^[12]$/, `no fraction on the way: ${s}`);
  assert.equal(seen[seen.length - 1], '2');
});

test('the head tiles: a figure that is missing shows a dash, never 0', () => {
  const w = boot();
  assert.deepEqual(tiles(w).map((t) => fig(w, t.dataset.stat)), Array(7).fill('—'), 'before any data');
  const data = full();
  data.panels.cost.data.cards = null;
  data.panels.cost.data.cardsError = 'no cards.jsonl';
  data.panels.belt = { error: 'the belt was not read', data: null };
  data.panels.queue.data = { next: null, held: null, awaitingDeploy: null, issuesError: 'GitHub did not list' };
  data.panels.needs.data.cards = null;
  delete data.panels.landed;
  deliver(w, data);
  assert.deepEqual(tiles(w).map((t) => fig(w, t.dataset.stat)), Array(7).fill('—'));
  for (const t of tiles(w)) assert.equal(t.dataset.known, 'false');
  assert.equal(tile(w, 'needs').dataset.tone, undefined, 'a Needs you not read is neither red nor green');
  const again = full();
  again.panels.cost.data.cards.perLandedUsd = null;
  again.panels.belt.data.cap = null;
  next(w, again);
  assert.equal(fig(w, 'per'), '—', 'no card landed: no average');
  assert.equal(fig(w, 'belt'), '2', 'no cap read: no "of"');
  assert.equal(fig(w, 'today'), '$4.25');
});

test('the head tiles: Needs you is red when not zero and green at zero', () => {
  const w = boot();
  deliver(w, full());
  assert.equal(tile(w, 'needs').dataset.tone, 'bad');
  assert.match(tile(w, 'needs').textContent, /2 cards are stopped for you/, 'said to a screen reader, not colour alone');
  const data = full();
  data.panels.needs.data.cards = { waiting: [], blocked: [] };
  next(w, data);
  w.clock += 400;
  while (w.frames.length) w.frames.shift()();
  assert.equal(fig(w, 'needs'), '0');
  assert.equal(tile(w, 'needs').dataset.tone, 'ok');
  assert.match(css, /\.stat\[data-tone="bad"\] \.stat-value \{ color: var\(--bad\); \}/);
  assert.match(css, /\.stat\[data-tone="ok"\] \.stat-value \{ color: var\(--ok\); \}/);
});

test('the head tiles: 7 days says when steps are left out for want of a price', () => {
  const w = boot();
  deliver(w, full());
  assert.equal(tile(w, 'week').querySelector('.stat-mark').hidden, true, 'nothing left out: no mark');
  const data = full();
  Object.assign(data.panels.cost.data.cards, { unpricedSteps: 29, todayLeftOut: 0, weekLeftOut: 29, perLandedLeftOut: 0, unpriced: [] });
  next(w, data);
  const week = tile(w, 'week');
  assert.equal(week.querySelector('.stat-mark').hidden, false, 'a mark beside the figure');
  assert.equal(week.querySelector('.sr-only').textContent, ', 29 steps have no price', 'said to a screen reader');
  assert.match(week.title, /29 steps have no price/, 'and on hover');
  assert.equal(tile(w, 'today').querySelector('.stat-mark').hidden, true, 'today leaves none out');
  // A host from before the priced-steps figures gives no figure with an unpriced step in it: a dash, with the mark.
  const old = full();
  Object.assign(old.panels.cost.data.cards, { weekUsd: null, unpricedSteps: 3 });
  next(w, old);
  assert.equal(fig(w, 'week'), '—');
  assert.equal(week.querySelector('.stat-mark').hidden, false);
  assert.match(week.querySelector('.sr-only').textContent, /3 steps have no price/);
});

test('the head tiles: at a narrow width tiles drop from the right end of the order, Today and Needs you remain, nothing wraps', () => {
  const w = boot();
  deliver(w, full());
  const box = $(w, '#stats');
  let room = 250;
  Object.defineProperty(box, 'clientWidth', { get: () => room });
  for (const t of tiles(w)) t.getBoundingClientRect = () => ({ left: 0, top: 0, right: 100, bottom: 40, width: 100, height: 40 });
  w.dispatchEvent(new w.Event('resize'));
  assert.deepEqual(shownTiles(w), ['today', 'needs']);
  assert.equal(box.style.minWidth, '200px', 'the two that always show are the least room the tiles take');
  room = 450;
  w.dispatchEvent(new w.Event('resize'));
  assert.deepEqual(shownTiles(w), ['today', 'belt', 'queued', 'needs'], '7 days, per landed card and landed today go first');
  room = 520;
  w.dispatchEvent(new w.Event('resize'));
  assert.deepEqual(shownTiles(w), ['today', 'belt', 'queued', 'landed', 'needs']);
  room = 100;
  w.dispatchEvent(new w.Event('resize'));
  assert.deepEqual(shownTiles(w), ['today', 'needs'], 'never fewer than the two');
  room = 2000;
  next(w, full());
  w.dispatchEvent(new w.Event('resize'));
  assert.equal(shownTiles(w).length, 7, 'room again: all seven');
  assert.match(css, /\.stats \{[^}]*flex-wrap: nowrap;[^}]*white-space: nowrap;/, 'the tiles never wrap onto a second line');
  // The head line is a grid row, not a wrapping flex line: the tiles' min-width widens their column and never pushes
  // them below the name, at any width; on a phone the times and buttons go below instead.
  assert.match(css, /\.top \{[^}]*display: grid;[^}]*grid-template-columns: auto 1fr auto auto;/);
  assert.doesNotMatch(css.match(/\.top \{[^}]*\}/)[0], /flex-wrap: wrap/);
  const phone = css.slice(css.indexOf('@media (max-width: 700px)'));
  // Issue 414 (UX27): two lines on a phone, not three: the times and Menu (which holds the buttons) share the second.
  assert.match(phone, /\.top \{[^}]*grid-template-columns: auto 1fr auto auto;/, 'a phone keeps name, tiles and Live on the head line');
  assert.match(phone, /\.status \{ grid-row: 1; grid-column: 4; \}/);
  assert.match(phone, /\.top-meta \.meta \{ grid-row: 2;/);
  assert.match(phone, /\.top-actions \{ grid-row: 2; grid-column: 4;/);
  // At 320px with Today at $1,234.50 the two tiles' least room, the name, the Live mark, the gaps and the
  // padding were wider than the screen. A small phone tightens them, and the name's column gives way before the tiles'.
  const small = css.slice(css.indexOf('@media (max-width: 420px)'));
  assert.match(small, /\.top \{[^}]*grid-template-columns: minmax\(0, auto\) 1fr auto auto;/, 'the name\'s column may shrink below its text; the tiles\' may not');
  assert.match(small, /\.top \{[^}]*padding: var\(--sp-3\) var\(--sp-2\);[^}]*column-gap: var\(--sp-2\);/);
  assert.match(small, /\.brand \{ min-width: 0; \}/);
  assert.match(small, /h1 \{[^}]*min-width: 0;[^}]*overflow: hidden;[^}]*text-overflow: ellipsis;[^}]*white-space: nowrap;/, 'a name with no room shortens, it does not push the tiles');
  assert.match(small, /\.stat \{ padding: 2px var\(--sp-1\); \}/);
});

test('the head tiles: a figure that lands wider after its count is fitted again when the count ends', () => {
  const w = boot();
  const data = full();
  data.panels.landed.data.cards = data.panels.landed.data.cards.slice(0, 1);
  deliver(w, data);
  const box = $(w, '#stats');
  Object.defineProperty(box, 'clientWidth', { get: () => 640 });
  // A tile is 100 px wide, the Today tile as wide as its figure's text in 20 px characters.
  for (const t of tiles(w)) t.getBoundingClientRect = () => ({ width: t.dataset.stat === 'today' ? fig(w, 'today').length * 20 : 100 });
  w.dispatchEvent(new w.Event('resize'));
  assert.equal(shownTiles(w).length, 6, '$4.25 (100) and five more fit; the seventh does not');
  const wide = full();
  wide.panels.landed.data.cards = data.panels.landed.data.cards;
  wide.panels.cost.data.cards.todayUsd = 1234.5;
  w.frames.length = 0;
  next(w, wide);
  w.clock += 400;
  while (w.frames.length) w.frames.shift()();
  assert.ok(fig(w, 'today').length > 5, `the figure landed wider: ${fig(w, 'today')}`);
  assert.equal(shownTiles(w).length, 5, 'the landed figure was measured: one more tile gives way');
});

test('the head tiles: a tile opens its panel on that panel\'s tab; a click with a modifier is left to the browser', () => {
  const w = boot({ tab: 'control' });
  deliver(w, full());
  tile(w, 'today').click();
  assert.equal(new URL(w.location.href).searchParams.get('tab'), 'overview');
  assert.ok(order(w).includes('cost'));
  assert.equal(w.document.activeElement, panel(w, 'cost'), 'the focus goes to the panel');
  const c = boot({ tab: 'control' });
  deliver(c, full());
  tile(c, 'needs').dispatchEvent(new c.MouseEvent('click', { bubbles: true, cancelable: true, ctrlKey: true }));
  assert.equal(new URL(c.location.href).searchParams.get('tab'), 'control', 'ctrl-click is left to the browser');
});

test('the head tiles move with the live feed, counting with motion on and at once under reduced motion', () => {
  const w = boot({ feed: true });
  w.sources[0].emit('open');
  w.sources[0].emit('snapshot', full());
  assert.equal(fig(w, 'today'), '$4.25');
  const part = clone(full().panels.cost);
  part.data.cards.todayUsd = 6.25;
  w.frames.length = 0;
  w.sources[0].emit('panel', { id: 'cost', part, updatedAt: iso(T0) });
  assert.equal(fig(w, 'today'), '$4.25', 'the count starts from the value shown');
  w.clock += 400;
  while (w.frames.length) w.frames.shift()();
  assert.equal(fig(w, 'today'), '$6.25');
  const r = boot({ reducedMotion: true });
  deliver(r, full());
  const d = full();
  d.panels.landed.data.cards.pop();
  next(r, d);
  assert.equal(fig(r, 'landed'), '1', 'the new value at once');
  assert.equal(r.frames.length, 0, 'no frame was asked for');
});
