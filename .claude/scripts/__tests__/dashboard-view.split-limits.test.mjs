// SPDX-License-Identifier: Apache-2.0
// The four limits of the rule Split large issues on the Rules tab: a row each under the rule's switch, from the
// snapshot's packSplit ({doneWhen, files, areas, chars}, each {n, from}), set with the action split-limits
// (`conveyor.sh split-limits`). Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { boot, deliver, next, settle, full, act, ruled, rulesP, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

const LIMITS = { doneWhen: { n: 4, from: 'default', default: 4 }, files: { n: 7, from: 'pack', default: 6 }, areas: { n: 3, from: 'default', default: 3 },
  chars: { n: 3000, from: 'default', default: 3000 } };
const KEYS = ['split-donewhen', 'split-files', 'split-areas', 'split-chars'];
// The Rules part with the rule Split large issues at split, and the pack's limits (none: a snapshot with no packSplit).
function snap(split, limits = LIMITS) {
  const d = full(), r = d.panels.rules.data;
  r.control = { ...r.control, rules: { ...r.control.rules, split } };
  if (limits) r.packSplit = structuredClone(limits);
  else delete r.packSplit;
  return d;
}
const rowOf = (w, k) => ruled(w).querySelector(`[data-rule="${k}"]`);
const pressed = (w, k) => Array.from(rowOf(w, k).querySelectorAll('[aria-pressed="true"]'), (b) => b.textContent);
const sent = async (w, fn) => { fn(); await settle(); return w.posts.splice(0).map((p) => p.body); };

// Bugs this guards: the owner could not see or set the limits from the Board; a row showed a limit not in force, or
// did not say whether the pack sets it; a limit the pack sets that no choice lists (7 files) had no choice pressed;
// the rows showed only for one setting of the rule; a click sent nothing, or a word `conveyor.sh split-limits` does
// not take, or the row went on showing the old value until the next snapshot; Use default left the row with no number
// pressed until the next snapshot; a row said an issue that reaches a limit goes to the Judge with the rule Off, which
// checks no issue; a search for Split large issues hid the four rows.
test('Rules: Split large issues shows its four limits in force and a click sets one', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, snap('on'));
  const order = Array.from(ruled(w).querySelectorAll('.rules-row'), (x) => x.dataset.rule);
  assert.deepEqual(order.slice(order.indexOf('split'), order.indexOf('split') + 5), ['split', ...KEYS], 'the four rows are under Split large issues');
  assert.deepEqual(KEYS.map((k) => pressed(w, k)), [['4'], ['7'], ['3'], ['3000']], 'each row has the limit in force pressed');
  assert.match(rowOf(w, 'split-files').textContent, /set in the pack/);
  assert.match(rowOf(w, 'split-chars').textContent, /default/);
  assert.equal(act(rowOf(w, 'split-chars'), 'split-chars-default'), null, 'a default limit has no Use default');
  assert.deepEqual(await sent(w, () => act(rowOf(w, 'split-files'), 'split-files-10').click()), [{ action: 'split-limits', args: ['files=10'], repo: 'sample' }]);
  await settle();
  assert.deepEqual(pressed(w, 'split-files'), ['10'], 'the saved limit shows before the next snapshot');
  assert.deepEqual(await sent(w, () => act(rowOf(w, 'split-files'), 'split-files-default').click()), [{ action: 'split-limits', args: ['files=default'], repo: 'sample' }]);
  await settle();
  assert.doesNotMatch(rowOf(w, 'split-files').textContent, /set in the pack/, 'Use default shows the default before the next snapshot');
  assert.deepEqual(pressed(w, 'split-files'), ['6'], 'Use default presses the default number before the next snapshot');
  assert.equal(act(rowOf(w, 'split-files'), 'split-files-default'), null, 'a limit set to default has no Use default');
  for (const split of ['off', 'shadow']) {
    next(w, snap(split, { ...LIMITS, doneWhen: { n: 2, from: 'pack', default: 4 } }));
    assert.ok(KEYS.every((k) => rowOf(w, k)), `the four rows show with the rule ${split}`);
    assert.deepEqual(pressed(w, 'split-donewhen'), ['2'], `the row shows a new snapshot's limit with the rule ${split}`);
    assert.match(rowOf(w, 'split-files').textContent, /with the rule On or Shadow, an issue/, `the row says when the limit counts, with the rule ${split}`);
  }
  const f = act(rulesP(w), 'rules-find');
  f.value = 'Split large issues';
  f.dispatchEvent(new w.Event('input'));
  assert.deepEqual(['split', ...KEYS].filter((k) => !rowOf(w, k).closest('[hidden]')), ['split', ...KEYS], 'a search for "Split large issues" shows the rule and its four limits');
});

// Bug this guards: a snapshot from an engine with no packSplit drew rows with no value, or the tab failed to draw.
test('Rules: Split large issues shows no limit rows for a snapshot with no packSplit', () => {
  const w = boot({ tab: 'rules' });
  deliver(w, snap('on', null));
  assert.ok(rowOf(w, 'split'), 'the rule row is still drawn');
  assert.ok(KEYS.every((k) => !rowOf(w, k)), 'no limit row');
  // A draw that threw would stop before the rows after Split large issues: Self-heals expiry is drawn after the limits.
  assert.ok(rowOf(w, 'healsdays'), 'no error: the rows after it are drawn');
});
