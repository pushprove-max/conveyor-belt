// SPDX-License-Identifier: Apache-2.0
// The Rules tab's rule "Stop a card's tests at the first failure": the control record's rules.failfast, sent as
// `control rules failfast=<on|off>`. Shared setup: dashboard-view.helpers.mjs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { boot, deliver, next, settle, full, act, rulesP, ruled } from './dashboard-view.helpers.mjs';

// The Rules part with the record's rules.failfast as given; undefined leaves the field out.
function data(on) {
  const d = full(), r = d.panels.rules.data;
  r.control = { ...r.control, rules: { ...r.control.rules } };
  delete r.control.rules.failfast;
  if (on !== undefined) r.control.rules.failfast = on;
  return d;
}
const row = (w) => ruled(w).querySelector('[data-rule="failfast"]');
const sent = async (w, fn) => { fn(); await settle(); return w.posts.splice(0).map((p) => p.body); };

// Bug this guards (#1616): the Board had no switch for the rule, so the owner could not let a card's test step run
// every case; the row was outside the Capacity group beside the test rules; a choice sent the wrong word, or Undo
// did not put the earlier setting back.
test('Rules: Stop a card\'s tests at the first failure is in Capacity, On by default, and a choice sends it', async () => {
  const dflt = JSON.parse(readFileSync(new URL('../../../conveyor/lib/control-defaults.json', import.meta.url), 'utf8')).rules.failfast;
  assert.equal(dflt, true, 'the rule starts on');
  const w = boot({ tab: 'rules' });
  deliver(w, data(dflt));
  assert.ok(ruled(w).querySelector('[data-set="capacity"] [data-rule="failfast"]'), 'the rule has a row in the Capacity group');
  assert.match(row(w).textContent, /Stop a card's tests at the first failure/);
  assert.equal(act(rulesP(w), 'failfast-on').getAttribute('aria-pressed'), 'true');
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'failfast-off').click()), [{ action: 'rules', args: ['failfast=off'], repo: 'sample' }]);
  assert.deepEqual(await sent(w, () => act(rulesP(w).querySelector('.rules-note'), 'undo').click()), [{ action: 'rules', args: ['failfast=on'], repo: 'sample' }], 'Undo puts On back');
  next(w, data(false));
  assert.equal(act(rulesP(w), 'failfast-off').getAttribute('aria-pressed'), 'true');
  assert.match(row(w).textContent, /off: a card's test step runs every case it selects/);
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'failfast-off').click()), [], 'the setting in force is not sent again');
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'failfast-on').click()), [{ action: 'rules', args: ['failfast=on'], repo: 'sample' }]);
});

// Bug this guards: a record from an engine before the rule was sent a rule its engine refuses.
test('Rules: Stop a card\'s tests at the first failure, unknown to the record, is not sent', () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data(undefined));
  assert.match(row(w).textContent, /needs a newer Conveyor/);
  assert.ok(Array.from(row(w).querySelectorAll('button')).every((b) => b.disabled), 'no choice is offered');
});
