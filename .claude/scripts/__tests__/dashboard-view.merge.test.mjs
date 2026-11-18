// SPDX-License-Identifier: Apache-2.0
// The rule "Merge PR" on the Rules tab (the control record's prMerge, else the pack's push.prMerge) and the Control
// tab's Merge of the open pull request of Land as pr (health's landingPr, #248). Shared setup: dashboard-view.helpers.mjs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { boot, deliver, next, settle, full, act, rulesP, ruled, pushP } from './dashboard-view.helpers.mjs';

// The Rules part with the record's prMerge as given (none: a record from an engine before the rule) and the pack's;
// the Board part with the open pull request as given.
function data({ prMerge = null, pack = 'button', pr = null } = {}) {
  const d = full(), r = d.panels.rules.data;
  const c = { ...r.control };
  delete c.prMerge;
  r.control = prMerge === 'none' ? c : { ...c, prMerge };
  r.packPrMerge = pack;
  d.panels.board.data.landingPr = pr;
  return d;
}
const PR = { number: 12, url: 'https://github.com/o/r/pull/12', cards: 3, merge: null };
const part = (w) => pushP(w).querySelector('[data-push="merge"]');
const pressed = (w) => ['pr-merge-button', 'pr-merge-release', 'pr-merge-idle'].map((a) => act(rulesP(w), a).getAttribute('aria-pressed'));
const sent = async (w, fn) => { fn(); await settle(); return w.posts.splice(0).map((p) => p.body); };

// Bugs this guards: the owner could not see or set Merge PR from the Board; a record that leaves it to the pack showed
// Button for a pack that merges when idle; a change sent nothing, or the wrong value; an older engine was sent it.
test('Rules: Merge PR shows the pack\'s value while the record sets none, and is set from its row', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data({ pack: 'idle' }));
  assert.deepEqual(pressed(w), ['false', 'false', 'true'], 'the pack\'s idle is in force');
  assert.match(ruled(w).querySelector('[data-rule="pr-merge"]').textContent, /merged when Conveyor is idle/);
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'pr-merge-idle').click()), [], 'the choice in force sends nothing');
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'pr-merge-release').click()), [{ action: 'pr-merge', args: ['release'], repo: 'sample' }]);
  next(w, data({ prMerge: 'release', pack: 'idle' }));
  assert.deepEqual(pressed(w), ['false', 'true', 'false'], 'the record wins over the pack');
  const old = boot({ tab: 'rules' });
  deliver(old, data({ prMerge: 'none' }));
  assert.ok(['pr-merge-button', 'pr-merge-release', 'pr-merge-idle'].every((a) => act(rulesP(old), a).disabled), 'an older engine is sent none');
});

// Bugs this guards (D1): the Merge button did not show while a pull request is open, without its card count and link,
// merged on one click (a merge cannot be undone), or sent nothing; it showed with no pull request open.
test('Control: Merge shows the open pull request with its cards and link, and merges on a second click', async () => {
  const w = boot({ tab: 'control' });
  deliver(w, data({ pr: PR }));
  assert.match(part(w).textContent, /#12/);
  assert.match(part(w).textContent, /3 cards/);
  assert.equal(part(w).querySelector('a').getAttribute('href'), PR.url);
  assert.equal(act(pushP(w), 'merge-pr').dataset.guard, 'final');
  assert.deepEqual(await sent(w, () => act(pushP(w), 'merge-pr').click()), [], 'the first click only asks');
  assert.match(act(pushP(w), 'merge-pr').textContent, /Click again to merge pull request #12/);
  assert.deepEqual(await sent(w, () => act(pushP(w), 'merge-pr').click()), [{ action: 'merge-pr', args: [], repo: 'sample' }]);
  next(w, data());
  assert.equal(part(w), null, 'no pull request open: no Merge');
});

// Bug this guards (D4): a merge GitHub refused left the owner with no reason why the pull request is still open.
test('Control: a refused merge shows GitHub\'s reason beside Merge', () => {
  const w = boot({ tab: 'control' });
  deliver(w, data({ pr: { ...PR, merge: { time: '2026-11-18T12:00:00Z', by: 'button', sha: 'a'.repeat(40), result: 'refused', reason: 'Pull request is not mergeable: required checks failed' } } }));
  assert.match(part(w).textContent, /GitHub refused the last merge: Pull request is not mergeable: required checks failed/);
  assert.equal(act(pushP(w), 'merge-pr').disabled, false, 'the owner can try again');
});
