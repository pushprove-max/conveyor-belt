// SPDX-License-Identifier: Apache-2.0
// The Rules tab's rule "Test before a push" (#395): the pack's push.check, as the snapshot gives it, unless the control
// record's pushCheck sets one; sent as `control push-check on|off`. Shared setup: dashboard-view.helpers.mjs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { boot, deliver, next, settle, full, act, rulesP, ruled } from './dashboard-view.helpers.mjs';

// The Rules part with the pack's push.check and the record's pushCheck as given; undefined leaves the field out.
function data(pack, record) {
  const d = full(), r = d.panels.rules.data;
  r.control = { ...r.control };
  delete r.control.pushCheck;
  delete r.pushCheck;
  if (pack !== undefined) r.pushCheck = pack;
  if (record !== undefined) r.control.pushCheck = record;
  return d;
}
const row = (w) => ruled(w).querySelector('[data-rule="push-check"]');
const pressed = (w) => ['push-check-on', 'push-check-off'].map((a) => act(rulesP(w), a).getAttribute('aria-pressed'));
const sent = async (w, fn) => { fn(); await settle(); return w.posts.splice(0).map((p) => p.body); };

// Bugs this guards: the owner could not turn the push check off from the Board; the row showed the pack's value when
// the control record had set another (the record wins, as the engine reads it); a change sent nothing, or the wrong
// action.
test('Rules: Test before a push shows the pack value, then the record over it, and is turned off and on from its row', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data(false, null));
  assert.ok(row(w), 'the rule has a row on the Rules tab');
  assert.deepEqual(pressed(w), ['false', 'true'], 'the pack sets it off and the record sets nothing');
  assert.match(row(w).textContent, /off: a push runs no test first/);
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'push-check-on').click()), [{ action: 'push-check', args: ['on'], repo: 'sample' }]);
  next(w, data(false, true));
  assert.deepEqual(pressed(w), ['true', 'false'], 'the record set on wins over the pack set off');
  assert.doesNotMatch(row(w).textContent, /off: a push runs no test first/);
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'push-check-off').click()), [{ action: 'push-check', args: ['off'], repo: 'sample' }]);
});

// Bug: Undo of On/Off sent the opposite value, so with no record value (the pack's push.check holds) it left a permanent
// override of the pack. With no record value, Undo sends `default`; with one, it sends that value back.
test('Rules: Undo of Test before a push puts the record back as it was, no value when it had none', async () => {
  const w = boot({ tab: 'rules' });
  const undo = () => act(rulesP(w).querySelector('.rules-last'), 'undo');
  deliver(w, data(false, null));
  await sent(w, () => act(rulesP(w), 'push-check-on').click());
  assert.deepEqual(await sent(w, () => undo().click()), [{ action: 'push-check', args: ['default'], repo: 'sample' }], 'the record had none: Undo clears it');
  next(w, data(false, true));
  await sent(w, () => act(rulesP(w), 'push-check-off').click());
  assert.deepEqual(await sent(w, () => undo().click()), [{ action: 'push-check', args: ['on'], repo: 'sample' }], 'the record had on: Undo sends on');
});

// Bug this guards: a snapshot with no pushCheck (an engine before the rule) was sent an action its engine refuses.
test('Rules: Test before a push, unknown to the snapshot, is not sent', () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data(undefined, undefined));
  assert.ok(act(rulesP(w), 'push-check-on').disabled && act(rulesP(w), 'push-check-off').disabled, 'an older engine is sent neither');
  assert.match(row(w).textContent, /needs a newer Conveyor/);
});
