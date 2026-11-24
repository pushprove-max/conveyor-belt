// SPDX-License-Identifier: Apache-2.0
// The Rules tab's rule "Self-heals expiry": the control record's rules.healsdays, the days an entry of the Self-heals
// list may go unfixed and unseen before it leaves the list, sent as `control rules healsdays=<days>` (issue 1561).
// Shared setup: dashboard-view.helpers.mjs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { boot, deliver, next, settle, full, act, rulesP, ruled } from './dashboard-view.helpers.mjs';

// The Rules part with the record's rules.healsdays as given; undefined leaves the key out (an older engine).
function data(days) {
  const d = full(), r = d.panels.rules.data;
  r.control = { ...r.control, rules: { ...r.control.rules } };
  delete r.control.rules.healsdays;
  if (days !== undefined) r.control.rules.healsdays = days;
  return d;
}
const row = (w) => ruled(w).querySelector('[data-rule="healsdays"]');
const sent = async (w, fn) => { fn(); await settle(); return w.posts.splice(0).map((p) => p.body); };

// Bugs this guards: the Rules tab had no control for the expiry age, so the owner could change it only with the
// command; a step sent another rule or number; the steps went past 1 or 3650, which the engine refuses.
test('Rules: Self-heals expiry shows the record\'s days and steps them down and up', async () => {
  const w = boot({ tab: 'rules' });
  // 45, not the default 30: Undo falls back to 30 when it reads no days, so a record of 30 cannot tell the two apart.
  deliver(w, data(45));
  assert.ok(row(w), 'the rule has a row on the Rules tab');
  assert.equal(row(w).querySelector('.board-value').textContent, '45', 'the row shows the record\'s 45');
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'self-heals expiry days-up').click()), [{ action: 'rules', args: ['healsdays=46'], repo: 'sample' }]);
  // Bug this guards: Undo sent another rule, the new days or the default 30, not the 45 the record held before.
  assert.deepEqual(await sent(w, () => act(rulesP(w).querySelector('.rules-note'), 'undo').click()), [{ action: 'rules', args: ['healsdays=45'], repo: 'sample' }], 'Undo puts the earlier days back');
  next(w, data(31));
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'self-heals expiry days-down').click()), [{ action: 'rules', args: ['healsdays=30'], repo: 'sample' }]);
  next(w, data(1));
  assert.ok(act(rulesP(w), 'self-heals expiry days-down').disabled, 'the days cannot go below 1');
  next(w, data(3650));
  assert.ok(act(rulesP(w), 'self-heals expiry days-up').disabled, 'the days cannot go above 3650');
});

// Bug this guards: a record from an engine before the rule was sent a setting its engine refuses.
test('Rules: Self-heals expiry, unknown to the record, is not sent', () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data(undefined));
  assert.equal(row(w).querySelector('.board-value'), null, 'no stepper to press');
  assert.match(row(w).textContent, /needs a newer Conveyor/);
});
