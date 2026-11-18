// SPDX-License-Identifier: Apache-2.0
// The Rules tab's rule "Whole suite in a card" (the control record's rules.wholeSuite, #293): off, on and unset.
// Shared setup: dashboard-view.helpers.mjs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { boot, deliver, next, settle, full, act, rulesP, ruled } from './dashboard-view.helpers.mjs';

// The Rules part with the rule as given; none: a record from an engine before the rule.
function data(wholeSuite) {
  const d = full(), r = d.panels.rules.data;
  const rules = { ...r.control.rules };
  delete rules.wholeSuite;
  r.control = { ...r.control, rules: { ...rules, ...(wholeSuite === 'none' ? {} : { wholeSuite }) } };
  return d;
}
const row = (w) => ruled(w).querySelector('[data-rule="wholeSuite"]');
const pressed = (w) => ['whole-suite-on', 'whole-suite-off'].map((a) => act(rulesP(w), a).getAttribute('aria-pressed'));
const sent = async (w, fn) => { fn(); await settle(); return w.posts.splice(0).map((p) => p.body); };

// Bugs this guards: the owner could not stop cards from running the whole suite from the Board; the rule's row did not
// show Off, its default, with what Off means; a change sent nothing, or sent a rule the engine does not know.
test('Rules: Whole suite in a card, off by default, says what off means and is turned on and off from its row', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data(false));
  assert.ok(row(w), 'the rule has a row on the Rules tab');
  assert.deepEqual(pressed(w), ['false', 'true'], 'off: a card runs only its own tests');
  assert.match(row(w).textContent, /off: a card runs only the test files it adds or changes \(with none, 5 linked to its change\), the test files linked to the landings run before each push, and the whole suite runs only in a release/);
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'whole-suite-off').click()), [], 'the choice in force sends nothing');
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'whole-suite-on').click()), [{ action: 'rules', args: ['wholeSuite=on'], repo: 'sample' }]);
  // The record the engine keeps after that change: the row shows On, and nothing says it is off.
  next(w, data(true));
  assert.deepEqual(pressed(w), ['true', 'false']);
  assert.doesNotMatch(row(w).textContent, /off: /, 'on: nothing says it is off');
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'whole-suite-off').click()), [{ action: 'rules', args: ['wholeSuite=off'], repo: 'sample' }]);
});

// Bug this guards: a record with no rules.wholeSuite (an engine before the rule) was sent a rule it refuses.
test('Rules: Whole suite in a card, unset, is not sent to an engine that does not know it', () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data('none'));
  assert.ok(act(rulesP(w), 'whole-suite-on').disabled && act(rulesP(w), 'whole-suite-off').disabled, 'an older engine is sent neither');
  assert.match(row(w).textContent, /needs a newer Conveyor/);
});
