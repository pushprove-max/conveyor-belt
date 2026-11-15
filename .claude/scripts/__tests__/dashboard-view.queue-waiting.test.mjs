// SPDX-License-Identifier: Apache-2.0
// The Queue panel's waiting list: the issues that wait on another open issue (the snapshot's queue.waiting), each
// "Waiting on #N", on the whole Board and on the page filtered to one project. Shared setup: dashboard-view.helpers.mjs.
// Bug (issue 19): a queued issue waiting on another ("Depends on: #N") was listed as waiting outside the Board but not in the Queue panel.
import assert from 'node:assert/strict';
import { P, boot, deliver, full, panel, pickProject, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

// Two projects on the host; sample's #16 waits on #7, widgetshop has none waiting. next: sample's queue (or none).
function part(next) {
  const d = full();
  d.panels.machine.data.repos = ['sample', 'widgetshop'];
  d.panels.queue.data = {
    next, held: 0, awaitingDeploy: [], issuesError: null,
    waiting: [{ repo: 'sample', card: null, issue: 16, title: 'Second half', url: `${P}/16`, waitsFor: [7], forced: false }],
    byRepo: { sample: { held: 0 }, widgetshop: { held: 0 } },
  };
  return d;
}
const NEXT = [{ repo: 'sample', issue: 20, title: 'Next up', priority: 'P1', followup: false, retried: false, url: `${P}/20` }];
const foots = (w) => Array.from(panel(w, 'queue').querySelectorAll('.foot'), (p) => p.textContent);
const chips = (w) => Array.from(panel(w, 'queue').querySelectorAll('.chip'), (c) => c.textContent);
const count = (w) => panel(w, 'queue').querySelector('.panel-count')?.textContent;

for (const [name, next] of [['next empty', []], ['next non-empty', NEXT]]) {
  test(`the Queue lists a waiting issue under "Waiting on another card (1)" with "Waiting on #7" (${name}), and counts it`, () => {
    const w = boot();
    deliver(w, part(next));
    assert.equal(panel(w, 'queue').dataset.state, 'ready', 'a queue with only waiting issues is not drawn as empty');
    assert.ok(foots(w).includes('Waiting on another card (1):'), foots(w).join(' | '));
    assert.ok(chips(w).includes('Waiting on #7'), chips(w).join(' | '));
    assert.equal(count(w), String(next.length + 1), 'the count has the waiting issue too');
  });
}

test('the Queue filtered to the other project shows no waiting row', () => {
  const w = boot();
  deliver(w, part([]));
  pickProject(w, 'widgetshop');
  assert.ok(!foots(w).some((t) => /Waiting on another card/.test(t)));
  assert.ok(!chips(w).some((t) => /Waiting on/.test(t)));
  pickProject(w, 'sample');
  assert.ok(foots(w).includes('Waiting on another card (1):'), 'filtered to its own project, it is listed');
});
