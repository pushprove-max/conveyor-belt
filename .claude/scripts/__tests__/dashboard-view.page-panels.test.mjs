// SPDX-License-Identifier: Apache-2.0
// The dashboard page as a whole, its panels: one file a panel, one entry of the list, and the first half of the list's
// three states (data, empty, failed to load). The other page-* files hold the rest of what was
// dashboard-view.page.test.mjs, split so the runner runs them side by side. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { VIEW, read, html, LIST, panelState, PANEL_STATES, PANEL_DRAWN, CONTROL_IDS, RULES_IDS, titleOf, BELT3D_IDS, OVERVIEW, boot, $, panel, state, order, deliver, full, SAYS, cases, caseNames, moreText, act, key, next } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

// ---- the panel list: one file and one entry a panel ----
test('every panel is one file in panels/ and one entry of the list', () => {
  const files = fs.readdirSync(path.join(VIEW, 'panels')).filter((f) => f !== 'index.js').map((f) => f.replace(/\.js$/, '')).sort();
  assert.deepEqual(files, LIST.slice().sort(), 'the files in panels/ are exactly the list');
  assert.deepEqual(LIST, ['machine', 'board', 'rules', 'needs', 'belt', 'belt3d', 'tests', 'bench', 'queue', 'landed', 'release', 'declined', 'health', 'lanes', 'cost', 'metrics'], 'the panels the issues name, in their default order');
  const w = boot();
  assert.deepEqual(order(w), OVERVIEW, 'Overview is the tab the page opens on');
  for (const id of OVERVIEW) assert.equal($(w, `#panel-${id} .panel-title`).textContent, SAYS[id].title);
  const c = boot({ tab: 'control' });
  assert.deepEqual(order(c), CONTROL_IDS);
  for (const id of CONTROL_IDS) assert.equal($(c, `#panel-${id} .panel-title`).textContent, titleOf(id));
  const r = boot({ tab: 'rules' });
  assert.deepEqual(order(r), RULES_IDS, 'the Rules tab holds the panels of the Rules part alone');
  for (const id of RULES_IDS) assert.equal($(r, `#panel-${id} .panel-title`).textContent, titleOf(id));
  const b = boot({ tab: 'belt3d' });
  assert.deepEqual(order(b), BELT3D_IDS, 'the Belt 3D tab holds the Belt 3D panel alone');
  assert.equal($(b, '#panel-belt3d .panel-title').textContent, 'Belt 3D');
  assert.equal(panel(b, 'belt3d').dataset.size, 'full', 'and it fills the tab');
  assert.ok(!OVERVIEW.includes('belt3d') && panel(boot(), 'belt3d') === null, 'Overview no longer lists Belt 3D');
  const t = boot({ tab: 'tests' });
  assert.deepEqual(order(t), ['tests'], 'the Tests tab holds the Tests panel alone');
  assert.equal(panel(t, 'tests').dataset.size, 'full');
  const bt = boot({ tab: 'bench' });
  assert.deepEqual(order(bt), ['bench'], 'the Benchmarks tab holds the Benchmarks panel alone');
  assert.equal(panel(bt, 'bench').dataset.size, 'full');
});

// A panel states its tab and its default length in its module; the page shows it on that tab, cut to that length.
// A panel's name is in its own file and the list only: the page has no code for one panel by its id. So every real
// panel is given a new id here (one boot a tab serves both checks); one the page knew by its old id would leave its
// tab, its place, its drawing or its length. A file whose part is drawn as more than one panel names every one of
// them from its PART, so its panels are renamed with it.
test('each panel states its tab and its default length: about 5 to 8 rows for a list, the whole content for figures; the page knows no panel by its id', () => {
  const as = (id) => `renamed${id}`;
  const extra = LIST.map((id) => read(`panels/${id}.js`).replace(`id: '${id}'`, `id: '${as(id)}'`).replace(`PART = '${id}'`, `PART = '${as(id)}'`)).join('\n');
  const data = full();
  for (const id of LIST) data.panels[as(id)] = data.panels[id];
  const stated = {};
  for (const [tab, ids] of [['overview', OVERVIEW], ['control', CONTROL_IDS], ['rules', RULES_IDS], ['belt3d', BELT3D_IDS], ['tests', ['tests']], ['bench', ['bench']]]) {
    const w = boot({ tab, list: LIST.map(as), extra });
    deliver(w, data);
    assert.deepEqual(order(w), ids.map(as), `the ${tab} tab holds its panels in their order`);
    for (const id of ids) {
      assert.equal(state(w, as(id)), 'ready', `${id} draws under its new id`);
      assert.equal($(w, `#panel-${as(id)} .panel-title`).textContent, titleOf(id));
      const length = panel(w, as(id)).dataset.length;
      stated[id] = [tab, length === 'all' ? 'all' : Number(length)];
    }
  }
  // A panel with a shared long list (needs, landed, declined, cost, metrics) is cut at its length (5) while that list
  // fits on one page, as each does here; a longer list is then its length control ('all', the cases below).
  assert.deepEqual(stated, {
    machine: ['control', 'all'], 'board-loop': ['control', 'all'], 'board-push': ['control', 'all'], board: ['control', 'all'],
    rules: ['rules', 'all'], 'rules-produce': ['rules', 'all'], 'rules-prices': ['rules', 'all'], 'rules-held': ['rules', 'all'], 'rules-issues': ['rules', 'all'], needs: ['overview', 5], belt: ['overview', 5], belt3d: ['belt3d', 'all'], tests: ['tests', 'all'], bench: ['bench', 'all'], queue: ['overview', 8], landed: ['overview', 5], release: ['overview', 'all'], declined: ['overview', 5],
    health: ['overview', 'all'], lanes: ['overview', 'all'], cost: ['overview', 5], metrics: ['overview', 5],
  });
  for (const [id, [, rows]] of Object.entries(stated)) if (rows !== 'all') assert.ok(rows >= 5 && rows <= 8, `${id} shows ${rows} rows by default`);
});

test('a list entry whose file did not load keeps its place and says so; the others draw', () => {
  const w = boot({ list: ['belt', 'ghost', 'queue'] });
  deliver(w, full());
  assert.deepEqual(order(w), ['belt', 'ghost', 'queue']);
  // Issue 415 (UX5): what to try in words; the file name on tap only.
  assert.match(panel(w, 'ghost').textContent, /This panel is missingIts code did not load\. Reload the page to load it again\./);
  assert.equal(panel(w, 'ghost').querySelector('.state-detail').dataset.tip, 'Details: panels/ghost.js did not load.');
  assert.doesNotMatch(panel(w, 'ghost').textContent, /\.js/);
  assert.equal(state(w, 'belt'), 'ready');
  assert.equal(state(w, 'queue'), 'ready');
});

test('a panel that throws shows its own error and takes no other panel with it', () => {
  const extra = `window.DASH_APP.panel({ id: 'boom', title: 'Boom', isEmpty: () => false, empty() {}, error() {}, render() { throw new Error('kaput'); } });`;
  const w = boot({ list: ['belt', 'boom'], extra });
  const data = full();
  data.panels.boom = { error: null, data: {} };
  deliver(w, data);
  assert.equal(state(w, 'boom'), 'error');
  // Issue 415 (UX5): what to try in words; the thrown error on tap only.
  assert.match(panel(w, 'boom').textContent, /The Board could not draw BoomReload the page to draw it again\./);
  assert.equal(panel(w, 'boom').querySelector('.state-detail').dataset.tip, 'Details: kaput');
  assert.equal(state(w, 'belt'), 'ready');
});

// Bug: a panel with a shared long list had two Show all controls (the list's and its foot's), its foot counted the
// rows drawn ("3 of 5") rather than the items, and the list's step (5) was not the panel's length.
test('a panel whose list uses ctx.more: the step is its length, its foot has no Show all and counts every item', () => {
  const extra = `window.DASH_APP.panel({ id: 'longs', title: 'Longs', rows: 3, isEmpty: () => false, empty() {}, error() {},
    render(el, d, ctx) { const ul = ctx.h('ul', 'rows'); el.replaceChildren(ul, ctx.more('items', d.items, (xs) => ctx.list(ul, xs, String, (x) => ctx.h('li', 'row', x)))); } });`;
  const w = boot({ list: ['belt', 'longs'], extra });
  const data = full();
  data.panels.longs = { error: null, data: { items: Array.from({ length: 20 }, (_, i) => `item ${i}`) } };
  deliver(w, data);
  const p = panel(w, 'longs'), rows = () => p.querySelectorAll('.rows > li').length;
  const foot = () => [p.querySelector('.panel-foot').hidden, p.querySelector('.panel-rows').textContent, p.querySelector('.panel-foot .show-all').hidden];
  assert.equal(rows(), 3, 'the panel length, 3, is the first page');
  assert.deepEqual(moreText(p), ['Show 3 more', 'Show all (20)'], 'and the step');
  assert.deepEqual(foot(), [false, '3 of 20', true], 'the foot counts the 20 items and has no Show all of its own');
  act(p, 'list-more').click();
  assert.equal(rows(), 6);
  assert.equal(p.querySelector('.scrolls'), null, 'the rows the list shows are not cut at the panel length');
  assert.deepEqual(foot(), [false, '6 of 20', true]);
  act(p, 'list-all').click();
  assert.equal(rows(), 20);
  assert.equal(p.querySelector('.panel-foot').hidden, true, 'all shown: nothing to count or show');
});

// Bug: a ctx.more list that fits on one page (its control hidden) still took the panel's default length to all, so
// Needs you with five blocked cards, one waiting card and one decision showed all seven, uncut and with no foot.
test('a panel whose ctx.more list fits on one page keeps its default length: Needs you with five blocked cards is cut', () => {
  const w = boot();
  const data = full();
  const P = 'https://github.com/example/example/issues';
  data.panels.needs.data.cards.blocked = Array.from({ length: 5 }, (_, i) => ({ repo: 'example', card: `c${i}-${300 + i}`, issue: 300 + i, title: `Card ${i}`, reason: 'tests failed', since: '2026-11-09T01:00:00Z', url: `${P}/${300 + i}` }));
  deliver(w, data);
  const p = panel(w, 'needs');
  assert.equal(p.querySelectorAll('.show-more:not([hidden])').length, 0, 'five blocked cards: one page, no list control');
  assert.equal(p.dataset.length, '5', 'the default length, not all');
  assert.ok(p.querySelector('.scrolls'), 'the body is cut');
  assert.deepEqual([p.querySelector('.panel-foot').hidden, p.querySelector('.panel-rows').textContent, p.querySelector('.panel-foot .show-all').hidden], [false, `5 of ${p.dataset.rows}`, false]);
});

// Bug: with a length the owner set (Home on the handle), the list's Show all showed the list whole but left the panel
// cut at one row, "1 of 20", and with the list's controls gone the panel had no Show all at all.
test('a panel whose list uses ctx.more, cut at a length the owner set: the list\'s Show all shows the whole panel', () => {
  const extra = `window.DASH_APP.panel({ id: 'longs', title: 'Longs', rows: 3, isEmpty: () => false, empty() {}, error() {},
    render(el, d, ctx) { const ul = ctx.h('ul', 'rows'); el.replaceChildren(ul, ctx.more('items', d.items, (xs) => ctx.list(ul, xs, String, (x) => ctx.h('li', 'row', x)))); } });`;
  const w = boot({ list: ['belt', 'longs'], extra });
  const data = full();
  data.panels.longs = { error: null, data: { items: Array.from({ length: 20 }, (_, i) => `item ${i}`) } };
  deliver(w, data);
  const p = panel(w, 'longs'), footAll = p.querySelector('.panel-foot .show-all');
  key(w, p.querySelector('.panel-length'), 'Home');
  assert.equal(p.querySelector('.panel-rows').textContent, '1 of 20', 'cut at one row');
  assert.equal(footAll.hidden, true, 'the list\'s Show all is the one shown');
  act(p, 'list-all').click();
  assert.equal(p.querySelector('.scrolls'), null, 'the panel is no longer cut');
  assert.equal(p.querySelector('.panel-foot').hidden, true, 'all 20 shown');
  // Cut again with the list whole: the foot's Show all is then the panel's one Show all.
  key(w, p.querySelector('.panel-length'), 'Home');
  assert.deepEqual([p.querySelector('.panel-rows').textContent, footAll.hidden, p.querySelectorAll('.show-more:not([hidden])').length], ['1 of 20', false, 0]);
  footAll.click();
  assert.equal(p.querySelector('.scrolls'), null);
});

// Bug: the foot counted every row drawn, nested ones too: a batch of eight cards counted eight ("13 of 14" beside
// "Show all (6)"), and a closed list inside a row (Release's changes) added its items ("1 of 3" with all shown).
test('a panel whose list uses ctx.more counts an item with rows in it once, and a list inside a row as part of that row', () => {
  const extra = `window.DASH_APP.panel({ id: 'longs', title: 'Longs', rows: 3, isEmpty: () => false, empty() {}, error() {},
    render(el, d, ctx) {
      const h = ctx.h, top = h('ul', 'rows'), row = h('li', 'row', 'project'), det = h('details'), inner = h('ul', 'rows');
      det.append(h('summary', null, 'changes'), inner, ctx.more('changes', ['c1', 'c2', 'c3'], (xs) => inner.replaceChildren(...xs.map((x) => h('li', 'row', x))), 1));
      row.append(det); top.append(row);
      const ul = h('ul', 'rows');
      const item = (x) => { if (!Array.isArray(x)) return h('li', 'row', x); const li = h('li', 'row batch'), u = h('ul', 'rows'); u.append(...x.map((c) => h('li', 'row', c))); li.append(u); return li; };
      el.replaceChildren(top, ul, ctx.more('items', d.items, (xs) => ul.replaceChildren(...xs.map(item))));
    } });`;
  const w = boot({ list: ['belt', 'longs'], extra });
  const data = full();
  data.panels.longs = { error: null, data: { items: [['a1', 'a2', 'a3', 'a4', 'a5', 'a6', 'a7', 'a8'], 'b1', 'b2', 'b3', 'b4', 'b5'] } };
  deliver(w, data);
  const p = panel(w, 'longs');
  // The project row and the first 3 of the 6 items: the batch, b1 and b2.
  assert.equal(p.querySelector('.panel-rows').textContent, '4 of 7');
  p.querySelector('[data-list="longs:items"] [data-act="list-all"]').click();
  assert.equal(p.querySelector('.panel-foot').hidden, true, 'every item shown: no count');
});

// Bug: a panel whose only list is inside a row (Release: a project's changes) counted the changes as its rows: cut at
// one row by Home, its foot said "1 of 21" for one project, with a Show all beside the list's Show all (26). And the
// list's Show all, which shows that project's changes, cleared the length the owner set for the whole panel.
test('a panel whose only ctx.more list is inside a row counts its rows, not the list\'s, and that list\'s Show all keeps the panel\'s length', () => {
  const extra = `window.DASH_APP.panel({ id: 'longs', title: 'Longs', rows: 3, isEmpty: () => false, empty() {}, error() {},
    render(el, d, ctx) {
      const h = ctx.h, top = h('ul', 'rows');
      for (const name of d.projects) {
        const row = h('li', 'row', name), inner = h('ul', 'rows');
        row.append(inner, ctx.more(\`changes:\${name}\`, d.changes, (xs) => inner.replaceChildren(...xs.map((x) => h('li', 'row', x))), 10));
        top.append(row);
      }
      el.replaceChildren(top);
    } });`;
  const w = boot({ list: ['belt', 'longs'], extra });
  const data = full();
  data.panels.longs = { error: null, data: { projects: ['one'], changes: Array.from({ length: 26 }, (_, i) => `change ${i}`) } };
  deliver(w, data);
  const p = panel(w, 'longs'), foot = p.querySelector('.panel-foot');
  p.querySelector('[data-act="list-more"]').click();
  key(w, p.querySelector('.panel-length'), 'Home');
  assert.deepEqual([foot.hidden, p.querySelector('.panel-rows').textContent], [true, ''], 'one project, shown: nothing to count or show');
  // Two projects, cut at one: the foot counts the projects, and its Show all is the one that shows the second.
  data.panels.longs.data.projects = ['one', 'two'];
  next(w, data);
  key(w, p.querySelector('.panel-length'), 'Home');
  assert.deepEqual([p.querySelector('.panel-rows').textContent, p.querySelector('.panel-foot .show-all').hidden], ['1 of 2', false]);
  p.querySelector('[data-list="longs:changes:one"] [data-act="list-all"]').click();
  assert.equal(p.querySelector('.panel-rows').textContent, '1 of 2', 'the panel stays at the length the owner set');
  assert.ok(p.querySelector('.scrolls'));
});

// ---- each panel: data, empty, failed to load; the second half is in dashboard-view.page-states ----
// One `test(` line a case: .conveyor/test-changed.sh counts a file's cases by those lines, so a case registered in a
// loop or a helper is left out of the Board's test progress and failure counts.
test('every panel of the list has its four state cases, each on its own test line, in page-panels or page-states', async () => {
  const named = new Map();
  const ran = [];
  // test-changed.sh's own filecases(), run on each file: it must count every case the file registers. It is the host
  // project's runner (.conveyor/), which an install of the release set (closure.test.sh) does not hold: counted only
  // where it is (issue 769).
  const counter = fileURLToPath(new URL('../../../.conveyor/test-changed.sh', import.meta.url));
  const counts = fs.existsSync(counter);
  for (const f of ['dashboard-view.page-panels.test.mjs', 'dashboard-view.page-states.test.mjs']) {
    const file = new URL(f, import.meta.url);
    const names = await caseNames(file.href);
    ran.push(...names);
    if (counts) {
      const counted = execFileSync('bash', ['-c', 'eval "$(grep "^filecases()" "$1")"; filecases "$2"', '_', counter, fileURLToPath(file)], { encoding: 'utf8' });
      assert.equal(Number(counted), names.length, `${f}: test-changed.sh counts each of its ${names.length} cases`);
    }
    const src = fs.readFileSync(file, 'utf8');
    for (const [, id, says, key, arg, drawn] of src.matchAll(/^test\('([a-z0-9]+): ([a-z ]+)', \(\) => assert\.equal\(panelState\.([a-z]+)\('([a-z0-9]+)'\), '([a-z]+)'\)\);$/gm)) {
      assert.equal(PANEL_STATES[key], says, `${f}: "${id}: ${says}" runs the ${key} case`);
      assert.equal(arg, id, `${f}: "${id}: ${says}" runs on ${id}`);
      assert.equal(drawn, PANEL_DRAWN[key], `${f}: "${id}: ${says}" asserts the state the ${key} case leaves`);
      assert.ok(!named.has(`${id}:${key}`), `${id}: ${says} is named once`);
      named.set(`${id}:${key}`, f);
    }
  }
  assert.deepEqual([...named.keys()].sort(), LIST.flatMap((id) => Object.keys(PANEL_STATES).map((k) => `${id}:${k}`)).sort());
  // The two files, loaded, register each panel's four cases once between them.
  for (const id of LIST) for (const says of Object.values(PANEL_STATES)) {
    assert.equal(ran.filter((n) => n === `${id}: ${says}`).length, 1, `"${id}: ${says}" is registered once`);
  }
});
test('machine: with data', () => assert.equal(panelState.data('machine'), 'ready'));
test('machine: empty', () => assert.equal(panelState.empty('machine'), 'empty'));
test('machine: failed to load', () => assert.equal(panelState.failed('machine'), 'error'));
test('machine: draws from its own part alone', () => assert.equal(panelState.own('machine'), 'ready'));
test('board: with data', () => assert.equal(panelState.data('board'), 'ready'));
test('board: empty', () => assert.equal(panelState.empty('board'), 'empty'));
test('board: failed to load', () => assert.equal(panelState.failed('board'), 'error'));
test('board: draws from its own part alone', () => assert.equal(panelState.own('board'), 'ready'));
test('rules: with data', () => assert.equal(panelState.data('rules'), 'ready'));
test('rules: empty', () => assert.equal(panelState.empty('rules'), 'empty'));
test('rules: failed to load', () => assert.equal(panelState.failed('rules'), 'error'));
test('rules: draws from its own part alone', () => assert.equal(panelState.own('rules'), 'ready'));
test('needs: with data', () => assert.equal(panelState.data('needs'), 'ready'));
test('needs: empty', () => assert.equal(panelState.empty('needs'), 'empty'));
test('needs: failed to load', () => assert.equal(panelState.failed('needs'), 'error'));
test('needs: draws from its own part alone', () => assert.equal(panelState.own('needs'), 'ready'));
test('belt: with data', () => assert.equal(panelState.data('belt'), 'ready'));
test('belt: empty', () => assert.equal(panelState.empty('belt'), 'empty'));
test('belt: failed to load', () => assert.equal(panelState.failed('belt'), 'error'));
test('belt: draws from its own part alone', () => assert.equal(panelState.own('belt'), 'ready'));
test('belt3d: with data', () => assert.equal(panelState.data('belt3d'), 'ready'));
test('belt3d: empty', () => assert.equal(panelState.empty('belt3d'), 'empty'));
test('belt3d: failed to load', () => assert.equal(panelState.failed('belt3d'), 'error'));
test('belt3d: draws from its own part alone', () => assert.equal(panelState.own('belt3d'), 'ready'));
