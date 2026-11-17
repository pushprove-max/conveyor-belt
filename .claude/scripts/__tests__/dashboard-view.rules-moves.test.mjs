// SPDX-License-Identifier: Apache-2.0
// The Rules tab's moved rows (issue 177): a row Queue, Hold or their Undo moved stays shown as moved until a snapshot
// made after the change shows it. Bug: the row went at once, a snapshot made before the change drew it again as held,
// and the next one took it away. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { T0, boot, deliver, next, settle, full, act, record, rulesP, groupEl, issuesP, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

// A snapshot the collector began at `begun`, with the record holding `held` (76 by default, as full()).
function snap(begun, held = [76]) {
  const d = full(begun + 20000), r = d.panels.rules.data;
  r.control.held = held;
  r.held = r.held.filter((x) => held.includes(x.issue));
  r.open.held = r.open.held.filter((x) => held.includes(x.issue) || !x.reasons.some((y) => y.kind === 'you'));
  r.open.issues = [{ repo: 'sample', issue: 76, title: 'Split the PROD stack', priority: 'P1', labels: ['P1', 'area:infra'], created: '2026-11-01T00:00:00Z' }];
  return d;
}
const row = (w) => { const g = groupEl(w, 'infra'); return g ? g.querySelector('[data-issue="76"]') : null; };
async function queued(w, reply) {
  deliver(w, snap(T0 - 60000));
  act(groupEl(w, 'infra'), 'group').click();
  w.reply = reply;
  act(row(w), 'queue').click();
  await settle();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.action), ['release']);
}

test('Rules: a queued row stays shown as queued through a snapshot made before the change, and goes with one made after that shows it', async () => {
  const w = boot({ tab: 'rules' });
  await queued(w, record({ held: [] }, T0));
  assert.ok(row(w).classList.contains('is-pending'), 'shown as moved, not removed');
  assert.match(row(w).textContent, /Queued: this shows in about a minute/);
  assert.equal(act(row(w), 'queue'), null, 'no second Queue while it waits');
  w.clock = T0 + 30000;
  next(w, snap(T0 - 1000));
  assert.ok(row(w) && row(w).classList.contains('is-pending'), 'a snapshot made before the change does not bring the row back as held');
  next(w, snap(T0 + 5000, []));
  assert.equal(row(w), null, 'a snapshot made after the change that shows it removes the row');
});

test('Rules: when the first snapshot made after a Queue still holds the issue, the row comes back with the error', async () => {
  const w = boot({ tab: 'rules' });
  await queued(w, record({ held: [] }, T0));
  w.clock = T0 + 30000;
  next(w, snap(T0 + 5000));
  assert.ok(!row(w).classList.contains('is-pending'));
  assert.ok(act(row(w), 'queue'), 'it can be queued again');
  assert.match(row(w).querySelector('.rules-refused').textContent, /^Not queued: the first update after the change still shows it held\.$/);
});

test('Rules: a refused Queue brings the row back with the refusal beside it', async () => {
  const w = boot({ tab: 'rules' });
  await queued(w, { ok: false, status: 409, text: () => Promise.resolve('issue 76 is not held'), headers: { get: () => null } });
  assert.ok(!row(w).classList.contains('is-pending'));
  assert.ok(act(row(w), 'queue'));
  assert.match(row(w).querySelector('.rules-refused').textContent, /^Not queued: .*issue 76 is not held/);
});

test('Rules: the Undo of a Queue holds the row again the same way: older snapshots keep it moved, a newer one that holds it ends the wait', async () => {
  const w = boot({ tab: 'rules' });
  await queued(w, record({ held: [] }, T0));
  w.clock = T0 + 30000;
  next(w, snap(T0 + 5000, []));
  const issue = () => issuesP(w).querySelector('[data-issue="76"]');
  w.reply = record({ held: [76] }, T0 + 30000);
  act(rulesP(w), 'undo').click();
  await settle();
  assert.deepEqual(w.posts.splice(0).map((p) => [p.body.action, p.body.args]), [['hold', ['76']]]);
  assert.ok(issue().classList.contains('is-pending'));
  assert.match(issue().textContent, /Held by you.*Held: this shows in about a minute/);
  w.clock = T0 + 60000;
  next(w, snap(T0 + 10000, []));
  assert.ok(issue().classList.contains('is-pending'), 'a snapshot made before the Undo does not show it queued again');
  assert.match(issue().textContent, /Held by you/);
  next(w, snap(T0 + 40000));
  assert.ok(!issue().classList.contains('is-pending'), 'one made after it that holds it ends the wait');
  assert.equal(issue().querySelector('.rules-refused'), null);
});
