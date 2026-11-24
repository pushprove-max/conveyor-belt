// SPDX-License-Identifier: Apache-2.0
// The Rules tab's rule "Only the Test step runs tests": the control record's rules.teststeponly, sent as
// `control rules teststeponly=<on|off>`. Shared setup: dashboard-view.helpers.mjs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { boot, deliver, next, settle, full, act, rulesP, ruled } from './dashboard-view.helpers.mjs';

// The Rules part with the record's rules.teststeponly as given; undefined leaves the field out.
function data(on) {
  const d = full(), r = d.panels.rules.data;
  r.control = { ...r.control, rules: { ...r.control.rules } };
  delete r.control.rules.teststeponly;
  if (on !== undefined) r.control.rules.teststeponly = on;
  return d;
}
const row = (w) => ruled(w).querySelector('[data-rule="teststeponly"]');
const sent = async (w, fn) => { fn(); await settle(); return w.posts.splice(0).map((p) => p.body); };

// Bug this guards: the Board had no switch for the rule, so the owner could not keep a card's sessions from running
// tests; the row was outside the Capacity group beside the other test rules; the rule showed On while the record
// (and the engine's default) had it off; a choice sent the wrong word, or Undo did not put the earlier setting back.
test('Rules: Only the Test step runs tests is in Capacity beside the other test rule, Off by default, and a choice sends it', async () => {
  const dflt = JSON.parse(readFileSync(new URL('../../../conveyor/lib/control-defaults.json', import.meta.url), 'utf8')).rules.teststeponly;
  assert.equal(dflt, false, 'the rule starts off');
  const w = boot({ tab: 'rules' });
  deliver(w, data(dflt));
  assert.ok(ruled(w).querySelector('[data-set="capacity"] [data-rule="failfast"] + [data-rule="teststeponly"]'), 'the row is in Capacity, right after Stop a card\'s tests at the first failure');
  assert.match(row(w).textContent, /Only the Test step runs tests/);
  assert.equal(act(rulesP(w), 'teststeponly-off').getAttribute('aria-pressed'), 'true');
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'teststeponly-on').click()), [{ action: 'rules', args: ['teststeponly=on'], repo: 'sample' }]);
  assert.deepEqual(await sent(w, () => act(rulesP(w).querySelector('.rules-note'), 'undo').click()), [{ action: 'rules', args: ['teststeponly=off'], repo: 'sample' }], 'Undo puts Off back');
  next(w, data(true));
  assert.equal(act(rulesP(w), 'teststeponly-on').getAttribute('aria-pressed'), 'true');
  assert.match(row(w).textContent, /on: a session reads the last Test step's result/);
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'teststeponly-on').click()), [], 'the setting in force is not sent again');
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'teststeponly-off').click()), [{ action: 'rules', args: ['teststeponly=off'], repo: 'sample' }]);
});

// Bug this guards: a record from an engine before the rule was sent a rule its engine refuses.
test('Rules: Only the Test step runs tests, unknown to the record, is not sent', () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data(undefined));
  assert.match(row(w).textContent, /needs a newer Conveyor/);
  assert.ok(Array.from(row(w).querySelectorAll('button')).every((b) => b.disabled), 'no choice is offered');
});
