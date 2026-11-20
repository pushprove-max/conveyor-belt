// SPDX-License-Identifier: Apache-2.0
// Issue 875: with push off, an open issue whose card landed and is not pushed (its held reason is its landed card,
// notPushed) is shown as landed, not pushed. Bug: the Board counted it on the belt, and the Rules tab's open issues
// showed it as Skipped by a rule, so it looked like open work. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { boot, deliver, withOpen, full, board, bcard, OPEN, clone, issuesP, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const P = 'https://github.com/example/sample/issues';
const LANDED = { repo: 'sample', issue: 50, title: 'Landed one', url: `${P}/50`, priority: 'P2', labels: [],
  reasons: [{ kind: 'card', step: 'landed', card: 'c1-50', notPushed: true }] };

test('the Board: a landed, unpushed issue is counted apart in the split and its card says Landed, not pushed', () => {
  const w = boot({ tab: 'control' });
  deliver(w, withOpen({ count: 10, split: { ...OPEN.split, landed: 1 }, held: clone(OPEN.held).concat([LANDED]) }));
  assert.equal(board(w).querySelector('[data-figure="split"]').textContent,
    '10 open3 queued1 held by you3 held by a label or skipped by a rule1 landed, not pushed2 on the belt');
  assert.deepEqual(Array.from(bcard(w, 50).querySelectorAll('.chip[data-reason]'), (c) => c.textContent), ['Landed, not pushed']);
});

// Bug: an empty queue said "Holds keep N issues back" with the landed, unpushed issue counted among them, though
// nothing holds it back: it is done and waits only for the push. The Queue panel's count is the collector's
// (dashboard-cards.test.sh).
test('the Board: an empty queue does not count a landed, unpushed issue among those holds keep back', () => {
  const d = withOpen({ held: clone(OPEN.held).concat([LANDED]) });
  Object.assign(d.panels.board.data, { queue: [], waits: [] });
  const w = boot({ tab: 'control' });
  deliver(w, d);
  const held = Array.from(board(w).querySelectorAll('.board-col[data-col="held"] .bcard'), (c) => Number(c.dataset.issue));
  assert.ok(held.includes(50), 'Held shows the landed, unpushed issue with its chip');
  assert.equal(board(w).querySelector('.board-queue-empty').textContent, `Nothing queued. Holds keep ${held.length - 1} issues back: see Held.`);
});

// Bug: a part that landed on an earlier day and is not pushed was counted done in its parent's row, but listed there
// as waiting: Landed today no longer had it, and the row did not look at Held.
test('the Board: a parent row shows a part that landed on an earlier day and is not pushed as landed', () => {
  const d = withOpen({ held: clone(OPEN.held).concat([LANDED]),
    umbrellas: [{ repo: 'sample', issue: 60, title: 'Big work', url: `${P}/60`, parts: ['#50', '#61'], done: 1, all: 2, inFlight: [], closed: [] }] });
  const w = boot({ tab: 'control' });
  deliver(w, d);
  const det = board(w).querySelector('.board-parents details.board-parent[data-issue="60"]');
  det.open = true;
  assert.deepEqual(Array.from(det.querySelectorAll('.board-part'), (li) => [li.dataset.part, li.dataset.state]), [['#50', 'landed'], ['#61', 'waiting']]);
});

test('Rules: a landed, unpushed issue is Landed, not pushed among the open issues, not Skipped by a rule', () => {
  const w = boot({ tab: 'rules' });
  const d = full(), r = d.panels.rules.data;
  r.open.held = r.open.held.concat([LANDED]);
  r.open.issues = [{ repo: 'sample', issue: 50, title: 'Landed one', priority: 'P2', labels: [], created: '2026-11-01T00:00:00Z' }];
  deliver(w, d);
  const row = issuesP(w).querySelector('[data-issue="50"]');
  assert.ok(row, 'the open issues list #50');
  assert.match(row.textContent, /Landed, not pushed/);
  assert.doesNotMatch(row.textContent, /Skipped by a rule/);
});
