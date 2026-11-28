// SPDX-License-Identifier: Apache-2.0
// The Rules tab's rule "Skip the Test step": the control record's rules.testskip, sent as
// `control rules testskip=<on|off>`. Shared setup: dashboard-view.helpers.mjs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { boot, deliver, next, settle, full, act, rulesP, ruled } from './dashboard-view.helpers.mjs';

// The Rules part with the record's rules.testskip as given; undefined leaves the field out.
function data(on) {
  const d = full(), r = d.panels.rules.data;
  r.control = { ...r.control, rules: { ...r.control.rules } };
  delete r.control.rules.testskip;
  if (on !== undefined) r.control.rules.testskip = on;
  return d;
}
const row = (w) => ruled(w).querySelector('[data-rule="testskip"]');
const sent = async (w, fn) => { fn(); await settle(); return w.posts.splice(0).map((p) => p.body); };

// Bug this guards: the Board had no switch for the rule, so the owner could not have cards land without their Test
// step; the row was outside the Capacity group beside the other test rules; the rule showed On while the record (and
// the engine's default) had it off, so cards looked untested when they were tested; a choice sent the wrong word, or
// Undo did not put the earlier setting back; or the row did not say that a card's sessions keep their own test runs.
test('Rules: Skip the Test step is in Capacity beside Only the Test step runs tests, Off by default, and a choice sends it', async () => {
  const dflt = JSON.parse(readFileSync(new URL('../../../conveyor/lib/control-defaults.json', import.meta.url), 'utf8')).rules.testskip;
  assert.equal(dflt, false, 'the rule starts off');
  const w = boot({ tab: 'rules' });
  deliver(w, data(dflt));
  assert.ok(ruled(w).querySelector('[data-set="capacity"] [data-rule="teststeponly"] + [data-rule="testskip"]'), 'the row is in Capacity, right after Only the Test step runs tests');
  assert.match(row(w).textContent, /Skip the Test step/);
  assert.match(row(w).textContent, /a card's Test step runs no tests; lint, review and land still run/);
  assert.equal(act(rulesP(w), 'testskip-off').getAttribute('aria-pressed'), 'true');
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'testskip-on').click()), [{ action: 'rules', args: ['testskip=on'], repo: 'sample' }]);
  assert.deepEqual(await sent(w, () => act(rulesP(w).querySelector('.rules-note'), 'undo').click()), [{ action: 'rules', args: ['testskip=off'], repo: 'sample' }], 'Undo puts Off back');
  next(w, data(true));
  assert.equal(act(rulesP(w), 'testskip-on').getAttribute('aria-pressed'), 'true');
  assert.match(row(w).textContent, /on: a card's sessions still run their own tests/);
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'testskip-on').click()), [], 'the setting in force is not sent again');
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'testskip-off').click()), [{ action: 'rules', args: ['testskip=off'], repo: 'sample' }]);
  assert.deepEqual(await sent(w, () => act(rulesP(w).querySelector('.rules-note'), 'undo').click()), [{ action: 'rules', args: ['testskip=on'], repo: 'sample' }], 'Undo puts On back');
});

// Bug this guards: a record from an engine before the rule was sent a rule its engine refuses.
test('Rules: Skip the Test step, unknown to the record, is not sent', () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data(undefined));
  assert.match(row(w).textContent, /needs a newer Conveyor/);
  assert.ok(Array.from(row(w).querySelectorAll('button')).every((b) => b.disabled), 'no choice is offered');
});
