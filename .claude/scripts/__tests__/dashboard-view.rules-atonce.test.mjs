// SPDX-License-Identifier: Apache-2.0
// The Rules tab's rule "Test files at once": the control record's suiteAtOnce, the most test files a parallel release
// suite runs together, sent as `control atonce <n>`. Shared setup: dashboard-view.helpers.mjs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { boot, deliver, next, settle, full, act, rulesP, ruled } from './dashboard-view.helpers.mjs';

// The Rules part with the record's suiteAtOnce and the machine's test slots as given; undefined leaves the field out.
function data(atOnce, slots) {
  const d = full(), r = d.panels.rules.data;
  r.control = { ...r.control };
  delete r.control.suiteAtOnce;
  if (atOnce !== undefined) r.control.suiteAtOnce = atOnce;
  r.cores = { reserved: [], slots, unavailable: null };
  return d;
}
const row = (w) => ruled(w).querySelector('[data-rule="atonce"]');
const sent = async (w, fn) => { fn(); await settle(); return w.posts.splice(0).map((p) => p.body); };

// Bug this guards: the setting's default in control-defaults.json (what a record without the number gets) moves off 2,
// which the docs and the issue state. The tab shows the record's number as it is, so this feeds it the file's default
// and checks that default is 2 and that the row shows it.
test('Rules: Test files at once shows the default, 2, of control-defaults.json', () => {
  const dflt = JSON.parse(readFileSync(new URL('../../../conveyor/lib/control-defaults.json', import.meta.url), 'utf8')).suiteAtOnce;
  assert.equal(dflt, 2, 'the default of the setting is 2');
  const w = boot({ tab: 'rules' });
  deliver(w, data(dflt, 4));
  assert.equal(row(w).querySelector('.board-value').textContent, '2', 'a record with the default shows 2');
});

// Bugs this guards: the owner could not set the number from the Board; the row showed a number other than the
// record's; a step sent the wrong action or value; the up step stopped at 100 while the setting takes 999.
test('Rules: Test files at once shows the record\'s number and steps it down and up', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data(2, 4));
  assert.ok(row(w), 'the rule has a row on the Rules tab');
  assert.equal(row(w).querySelector('.board-value').textContent, '2', 'the row shows the record\'s 2');
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'test files at once-up').click()), [{ action: 'atonce', args: ['3'], repo: 'sample' }]);
  next(w, data(3, 4));
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'test files at once-down').click()), [{ action: 'atonce', args: ['2'], repo: 'sample' }]);
  next(w, data(1, 4));
  assert.ok(act(rulesP(w), 'test files at once-down').disabled, 'the number cannot go below 1, which the engine refuses');
  next(w, data(100, 4));
  assert.ok(!act(rulesP(w), 'test files at once-up').disabled, 'a number of 100, which the setting takes, can go up');
  next(w, data(999, 4));
  assert.ok(act(rulesP(w), 'test files at once-up').disabled, 'the number cannot go above 999, which the engine refuses');
});

// Bug this guards: a number above the machine's test slots showed as if it ran, when the suite runs at the slots.
test('Rules: Test files at once says when the number is above the machine\'s test slots', () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data(6, 4));
  assert.match(row(w).textContent, /Runs at 4: the machine has 4 test slots/);
  next(w, data(4, 4));
  assert.doesNotMatch(row(w).textContent, /Runs at/, 'a number the slots hold says nothing');
});

// Bug this guards: a record from an engine before the setting was sent an action its engine refuses.
test('Rules: Test files at once, unknown to the record, is not sent', () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data(undefined, 4));
  assert.match(row(w).textContent, /needs a newer Conveyor/);
  assert.equal(row(w).querySelector('button'), null, 'no step is offered');
});
