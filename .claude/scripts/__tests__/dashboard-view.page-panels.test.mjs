// SPDX-License-Identifier: Apache-2.0
// The dashboard page as a whole, its panels: one file a panel, one entry of the list, and the first half of the list's
// three states (data, empty, failed to load). The other page-* files hold the rest of what was
// dashboard-view.page.test.mjs, split so the runner runs them side by side. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { VIEW, read, html, LIST, panelState, PANEL_STATES, CONTROL_IDS, RULES_IDS, titleOf, BELT3D_IDS, OVERVIEW, boot, $, panel, state, order, deliver, full, SAYS, cases } from './dashboard-view.helpers.mjs';

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
  assert.deepEqual(stated, {
    machine: ['control', 'all'], 'board-loop': ['control', 'all'], 'board-push': ['control', 'all'], board: ['control', 'all'],
    rules: ['rules', 'all'], 'rules-produce': ['rules', 'all'], 'rules-prices': ['rules', 'all'], 'rules-held': ['rules', 'all'], 'rules-issues': ['rules', 'all'], needs: ['overview', 6], belt: ['overview', 5], belt3d: ['belt3d', 'all'], tests: ['tests', 'all'], bench: ['bench', 'all'], queue: ['overview', 8], landed: ['overview', 6], release: ['overview', 'all'], declined: ['overview', 6],
    health: ['overview', 'all'], lanes: ['overview', 'all'], cost: ['overview', 8], metrics: ['overview', 8],
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

// ---- each panel: data, empty, failed to load; the second half is in dashboard-view.page-states ----
// One `test(` line a case: .conveyor/test-changed.sh counts a file's cases by those lines, so a case registered in a
// loop or a helper is left out of the Board's test progress and failure counts.
test('every panel of the list has its four state cases, each on its own test line, in page-panels or page-states', () => {
  const named = new Map();
  for (const f of ['dashboard-view.page-panels.test.mjs', 'dashboard-view.page-states.test.mjs']) {
    const src = fs.readFileSync(new URL(f, import.meta.url), 'utf8');
    for (const [, id, says, key, arg] of src.matchAll(/^test\('([a-z0-9]+): ([a-z ]+)', \(\) => panelState\.([a-z]+)\('([a-z0-9]+)'\)\);$/gm)) {
      assert.equal(PANEL_STATES[key], says, `${f}: "${id}: ${says}" runs the ${key} case`);
      assert.equal(arg, id, `${f}: "${id}: ${says}" runs on ${id}`);
      assert.ok(!named.has(`${id}:${key}`), `${id}: ${says} is named once`);
      named.set(`${id}:${key}`, f);
    }
  }
  assert.deepEqual([...named.keys()].sort(), LIST.flatMap((id) => Object.keys(PANEL_STATES).map((k) => `${id}:${k}`)).sort());
});
test('machine: with data', () => panelState.data('machine'));
test('machine: empty', () => panelState.empty('machine'));
test('machine: failed to load', () => panelState.failed('machine'));
test('machine: draws from its own part alone', () => panelState.own('machine'));
test('board: with data', () => panelState.data('board'));
test('board: empty', () => panelState.empty('board'));
test('board: failed to load', () => panelState.failed('board'));
test('board: draws from its own part alone', () => panelState.own('board'));
test('rules: with data', () => panelState.data('rules'));
test('rules: empty', () => panelState.empty('rules'));
test('rules: failed to load', () => panelState.failed('rules'));
test('rules: draws from its own part alone', () => panelState.own('rules'));
test('needs: with data', () => panelState.data('needs'));
test('needs: empty', () => panelState.empty('needs'));
test('needs: failed to load', () => panelState.failed('needs'));
test('needs: draws from its own part alone', () => panelState.own('needs'));
test('belt: with data', () => panelState.data('belt'));
test('belt: empty', () => panelState.empty('belt'));
test('belt: failed to load', () => panelState.failed('belt'));
test('belt: draws from its own part alone', () => panelState.own('belt'));
test('belt3d: with data', () => panelState.data('belt3d'));
test('belt3d: empty', () => panelState.empty('belt3d'));
test('belt3d: failed to load', () => panelState.failed('belt3d'));
test('belt3d: draws from its own part alone', () => panelState.own('belt3d'));
