// SPDX-License-Identifier: Apache-2.0
// The Rules tab's rule "Visible changes need your yes" (the control record's rules.visible): on, off and unset.
// Shared setup: dashboard-view.helpers.mjs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { boot, deliver, next, settle, full, act, rulesP, ruled } from './dashboard-view.helpers.mjs';

// The Rules part with the rule as given; none: a record from an engine before the rule.
function data(visible) {
  const d = full(), r = d.panels.rules.data;
  r.control = { ...r.control, rules: { ...r.control.rules, ...(visible === 'none' ? {} : { visible }) } };
  return d;
}
const row = (w) => ruled(w).querySelector('[data-rule="visible"]');
const pressed = (w) => ['visible-on', 'visible-off'].map((a) => act(rulesP(w), a).getAttribute('aria-pressed'));
const sent = async (w, fn) => { fn(); await settle(); return w.posts.splice(0).map((p) => p.body); };

// Bugs this guards: the rule could not be turned off or on from the Board; with it off the Board did not say so beside
// the switch, so a landed visible change read as approved; with it on the Board said it was off.
test('Rules: Visible changes need your yes, on by default, is turned off and on from its row, and says when it is off', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data(true));
  assert.deepEqual(pressed(w), ['true', 'false'], 'on: a visible change waits for the yes');
  assert.match(row(w).textContent, /waits for your yes/);
  assert.doesNotMatch(row(w).textContent, /land without your yes/, 'on: nothing says it is off');
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'visible-on').click()), [], 'the choice in force sends nothing');
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'visible-off').click()), [{ action: 'rules', args: ['visible=off'], repo: 'sample' }]);
  next(w, data(false));
  assert.deepEqual(pressed(w), ['false', 'true']);
  assert.match(row(w).textContent, /off: visible changes land without your yes, and nobody approves them/, 'off: the row says so beside the switch');
  // Bug (UX38): set Off, the words under the name described Off ("cards are built, reviewed and landed with no approval
  // line"), so the name and its words said opposite things. They describe the switch by its name whatever is set.
  assert.equal(row(w).querySelector('.rules-what').textContent, 'a change customers or staff will see waits for your yes');
  assert.doesNotMatch(row(w).textContent, /no approval line/);
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'visible-on').click()), [{ action: 'rules', args: ['visible=on'], repo: 'sample' }]);
});

// Bug this guards: a record with no rules.visible (an engine before the rule) was read as off, or sent a rule it
// refuses. Unset reads as on, and neither choice is sent.
test('Rules: Visible changes need your yes, unset, reads as on and is not sent to an engine that does not know it', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data('none'));
  assert.deepEqual(pressed(w), ['true', 'false'], 'unset: on');
  assert.ok(act(rulesP(w), 'visible-on').disabled && act(rulesP(w), 'visible-off').disabled, 'an older engine is sent neither');
  assert.match(row(w).textContent, /needs a newer Conveyor/);
  assert.doesNotMatch(row(w).textContent, /land without your yes/);
});
