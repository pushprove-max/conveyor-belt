// SPDX-License-Identifier: Apache-2.0
// The Control and Rules tabs as panels (issue 9): each tab's one part is drawn as more than one panel, each in the
// frame every Overview panel has, in the order docs/board.md names them. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { VIEW, clone, iso, T0, boot, deliver, full, panel, state, order, act, cases, settle, CONTROL } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

// The panels docs/board.md names for a tab, in its order: "- **Rules**: the panels **A**, **B** and **C**."
const DOCS = path.join(VIEW, '..', '..', 'docs');
function documented(tab) {
  const doc = fs.readFileSync(path.join(DOCS, 'board.md'), 'utf8').replace(/\n {2}/g, ' ');
  const m = doc.match(new RegExp(`^- \\*\\*${tab}\\*\\*: the panels (.+?)\\.(?: |$)`, 'm'));
  assert.ok(m, `docs/board.md names the panels of ${tab}`);
  return Array.from(m[1].matchAll(/\*\*(.+?)\*\*/g), (x) => x[1]);
}
// The tab's panel titles match the docs where the docs are: an install (closure.test.sh) ships no docs/ folder, so
// there only the panels themselves are checked. A checkout with docs/ but no board.md still fails.
function matchesDocs(titles, tab) {
  if (!fs.existsSync(DOCS)) return;
  assert.deepEqual(titles, documented(tab));
}
// Each panel the tab shows: its heading, and whether it has the frame's collapse control and its own body.
const framed = (w) => order(w).map((id) => {
  const p = panel(w, id);
  assert.ok(p.querySelector('.tool.collapse'), `${id} collapses as an Overview panel does`);
  assert.ok(p.querySelector('.panel-body'), `${id} has the frame's body`);
  return p.querySelector('.panel-title').textContent;
});

// Bug: the Rules tab was one long column, Model prices under the rules with nothing to set it apart or fold it away.
test('Rules: the tab is five panels in the order the docs give, Model prices its own, each with its own section', () => {
  const w = boot({ tab: 'rules' });
  const d = full();
  d.panels.rules.data.prices = { builtIn: [{ model: 'claude-opus-5-5', input: 4, output: 20, cacheRead: 0.2 }], overrides: {} };
  deliver(w, d);
  matchesDocs(framed(w), 'Rules');
  assert.deepEqual(order(w), ['rules', 'rules-produce', 'rules-prices', 'rules-held', 'rules-issues']);
  for (const id of order(w)) assert.equal(state(w, id), 'ready', `${id} is drawn from the Rules part`);
  // Each section is in its panel and in no other.
  const home = { '.rules-row': 'rules', '.rules-produce': 'rules-produce', '.rules-prices': 'rules-prices', '.rules-held': 'rules-held', '.rules-issues': 'rules-issues' };
  for (const [sel, id] of Object.entries(home)) {
    assert.deepEqual(order(w).filter((x) => panel(w, x).querySelector(sel)), [id], `${sel} is in ${id} alone`);
  }
  assert.ok(act(panel(w, 'rules-prices'), 'price-save'), 'Model prices keeps its form');
  // Each panel has its own line, for what an action in it did.
  assert.deepEqual(order(w).filter((x) => panel(w, x).querySelector('.rules-note')), order(w));
});

// Bug: the tab's one line was in the Rules panel alone: with Rules folded away, Save in Model prices said nothing the
// owner could see.
test('Rules: what an action did shows in the panel it was done in, and no other', () => {
  const w = boot({ tab: 'rules' });
  const d = full();
  d.panels.rules.data.prices = { builtIn: [{ model: 'claude-opus-5-5', input: 4, output: 20, cacheRead: 0.2 }], overrides: {} };
  deliver(w, d);
  // Each Rules panel whose line says something: [its id, the line].
  const said = () => order(w).map((x) => [x, panel(w, x).querySelector('.rules-note').textContent]).filter(([, t]) => t);
  act(panel(w, 'rules-prices'), 'price-save').click();
  assert.deepEqual(said(), [['rules-prices', 'Give the model and its three prices.']]);
  const area = act(panel(w, 'rules'), 'area-name');
  area.value = 'two words'; area.dispatchEvent(new w.Event('input'));
  act(panel(w, 'rules'), 'area-off').click();
  assert.deepEqual(said().map(([x]) => x), ['rules'], 'the Model prices line is emptied');
});

// Bug: the tab's one line, and its Undo, was in Board alone: with Board folded away, Pause in Loop said nothing the
// owner could see, and its Undo was out of reach.
test('Control: Pause\'s answer and Undo show in Loop, even when Board is used while it is out', async () => {
  const c = boot({ tab: 'control' });
  deliver(c, full());
  let answer;
  c.reply = { ok: true, status: 200, text: () => new Promise((r) => { answer = r; }) };
  act(panel(c, 'board-loop'), 'pause').click();
  await settle();
  // Typing in Board's filter while Pause is out does not move its answer there.
  const f = panel(c, 'board').querySelector('[data-filter="text"]');
  f.value = '2'; f.dispatchEvent(new c.Event('input'));
  answer(JSON.stringify(CONTROL));
  await settle();
  const lines = order(c).filter((x) => x !== 'machine' && panel(c, x).querySelector('.board-note').textContent);
  assert.deepEqual(lines, ['board-loop']);
  assert.match(panel(c, 'board-loop').querySelector('.board-note').textContent, /^Done\..*Undo$/);
  assert.ok(act(panel(c, 'board-loop').querySelector('.board-note'), 'undo'), 'its Undo is in Loop');
});

// Bug: the Control tab's Board held the loop's controls, the push and the full suite, and the card columns in one panel.
test('Control: the tab is the machine, Loop, Push landed and full test suite, and Board, in the order the docs give', () => {
  const w = boot({ tab: 'control' });
  deliver(w, full());
  matchesDocs(framed(w), 'Control');
  assert.deepEqual(order(w), ['machine', 'board-loop', 'board-push', 'board']);
  // Projects and Foremen has a Pause of its own for each project: where each of the Board part's controls is.
  const where = (a) => order(w).filter((x) => x !== 'machine' && act(panel(w, x), a));
  assert.deepEqual(['pause', 'stop', 'push-landed', 'full-test'].map(where), [['board-loop'], ['board-loop'], ['board-push'], ['board-push']],
    'Pause and Stop now in Loop; Push landed and Run full test suite in their own panel');
  assert.deepEqual(order(w).filter((x) => panel(w, x).querySelector('.board-col')), ['board'], 'the cards in their columns in Board');
});

// Bug: a part the live feed sends is drawn in every panel drawn from it, not in the part's own panel alone.
test('the live feed: a new Rules part redraws each Rules panel, Model prices too', () => {
  const w = boot({ tab: 'rules', feed: true });
  const es = w.sources[0];
  es.readyState = 0; es.emit('error');
  deliver(w, full());
  es.readyState = 1; es.emit('open');
  const part = clone(full().panels.rules);
  part.data.prices = { builtIn: [{ model: 'claude-new-9', input: 3, output: 15, cacheRead: 0.3 }], overrides: {} };
  es.emit('panel', { id: 'rules', part, updatedAt: iso(T0 + 60000) });
  const models = Array.from(panel(w, 'rules-prices').querySelectorAll('.rules-price'), (r) => r.dataset.model);
  assert.deepEqual(models, ['claude-new-9']);
});
