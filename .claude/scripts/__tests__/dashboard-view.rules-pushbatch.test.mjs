// SPDX-License-Identifier: Apache-2.0
// The Rules tab's rule "Push after a combined test run" (Landing and push): the control record's rules.pushbatch,
// sent as `control rules pushbatch=<on|off>`, with when its run starts (rules.pushbatchwhen: a number of landings or
// a UTC time HH:MM) and which tests it runs (rules.pushbatchtests: linked or all). Shared setup: dashboard-view.helpers.mjs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { boot, deliver, next, settle, full, act, rulesP, ruled } from './dashboard-view.helpers.mjs';

const DEFAULTS = JSON.parse(readFileSync(new URL('../../../conveyor/lib/control-defaults.json', import.meta.url), 'utf8')).rules;
const KEYS = ['pushbatch', 'pushbatchwhen', 'pushbatchtests'];
// The Rules part with the record's rules as the engine's defaults, over them those given; a key given as undefined is
// left out. pushCheck, when given, is Test before a push, as the pack and the record both set it.
function data(given = {}, pushCheck) {
  const d = full(), r = d.panels.rules.data;
  r.control = { ...r.control, rules: { ...r.control.rules } };
  KEYS.forEach((k) => {
    const v = Object.prototype.hasOwnProperty.call(given, k) ? given[k] : DEFAULTS[k];
    if (v === undefined) delete r.control.rules[k]; else r.control.rules[k] = v;
  });
  if (pushCheck !== undefined) r.pushCheck = r.control.pushCheck = pushCheck;
  return d;
}
const row = (w) => ruled(w).querySelector('[data-rule="pushbatch"]');
const sent = async (w, fn) => { fn(); await settle(); return w.posts.splice(0).map((p) => p.body); };
const undo = (w) => act(rulesP(w).querySelector('.rules-note'), 'undo').click();

// Bug this guards: the Board had no switch for the rule, so the owner could not have landed cards pushed together
// after one combined test run; the row was outside Landing and push; it showed On while the record (and the engine's
// default) had it off; a choice sent the wrong word, or Undo did not put the earlier setting back.
test('Rules: Push after a combined test run is in Landing and push after Test before a push, Off by default, and a choice sends it', async () => {
  assert.equal(DEFAULTS.pushbatch, false, 'the rule starts off');
  const w = boot({ tab: 'rules' });
  deliver(w, data());
  assert.ok(ruled(w).querySelector('[data-set="landing"] [data-rule="push-check"] + [data-rule="pushbatch"]'), 'the row is in Landing and push, right after Test before a push');
  assert.match(row(w).textContent, /Push after a combined test run/);
  assert.equal(act(rulesP(w), 'pushbatch-off').getAttribute('aria-pressed'), 'true');
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'pushbatch-on').click()), [{ action: 'rules', args: ['pushbatch=on'], repo: 'sample' }]);
  assert.deepEqual(await sent(w, () => undo(w)), [{ action: 'rules', args: ['pushbatch=off'], repo: 'sample' }], 'Undo puts Off back');
  next(w, data({ pushbatch: true }));
  assert.equal(act(rulesP(w), 'pushbatch-on').getAttribute('aria-pressed'), 'true');
  assert.match(row(w).textContent, /on: the tests run even when Test before a push is Off/);
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'pushbatch-on').click()), [], 'the setting in force is not sent again');
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'pushbatch-off').click()), [{ action: 'rules', args: ['pushbatch=off'], repo: 'sample' }]);
});

// Bug this guards (E1 of the review): the owner could not set when the combined run starts or which tests it runs, so
// the engine's fixed choice held. A count, a UTC time and the tests each send their setting, and Undo sends the
// earlier one back; a time the record holds shows in the time field with no count pressed.
test('Rules: Push after a combined test run sets when its run starts and which tests it runs', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data({ pushbatch: true, pushbatchwhen: 2, pushbatchtests: 'linked' }));
  assert.equal(act(rulesP(w), 'pushbatchwhen-2').getAttribute('aria-pressed'), 'true');
  assert.equal(act(rulesP(w), 'pushbatchtests-linked').getAttribute('aria-pressed'), 'true');
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'pushbatchwhen-5').click()), [{ action: 'rules', args: ['pushbatchwhen=5'], repo: 'sample' }]);
  assert.deepEqual(await sent(w, () => undo(w)), [{ action: 'rules', args: ['pushbatchwhen=2'], repo: 'sample' }], 'Undo puts 2 landings back');
  next(w, data({ pushbatch: true, pushbatchwhen: 2, pushbatchtests: 'linked' }));
  const at = act(rulesP(w), 'pushbatchwhen-at');
  at.value = '02:30';
  assert.deepEqual(await sent(w, () => at.dispatchEvent(new w.Event('change'))), [{ action: 'rules', args: ['pushbatchwhen=02:30'], repo: 'sample' }]);
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'pushbatchtests-all').click()), [{ action: 'rules', args: ['pushbatchtests=all'], repo: 'sample' }]);
  assert.deepEqual(await sent(w, () => undo(w)), [{ action: 'rules', args: ['pushbatchtests=linked'], repo: 'sample' }], 'Undo puts Linked files back');
  next(w, data({ pushbatch: true, pushbatchwhen: '02:30', pushbatchtests: 'all' }));
  assert.equal(act(rulesP(w), 'pushbatchwhen-at').value, '02:30');
  assert.ok(Array.from(row(w).querySelectorAll('[data-act^="pushbatchwhen-"][aria-pressed="true"]')).length === 0, 'no count is pressed for a time of day');
  assert.equal(act(rulesP(w), 'pushbatchtests-all').getAttribute('aria-pressed'), 'true');
});

// Bug this guards (E4 of the review): with Test before a push Off and this rule On, the Test before a push row said a
// push runs no test first, while this rule runs its tests before every push.
test('Rules: Test before a push Off says the combined run still tests while Push after a combined test run is On', () => {
  const pc = (w) => ruled(w).querySelector('[data-rule="push-check"]').textContent;
  const w = boot({ tab: 'rules' });
  deliver(w, data({ pushbatch: false }, false));
  assert.match(pc(w), /off: a push runs no test first/);
  next(w, data({ pushbatch: true }, false));
  assert.match(pc(w), /off: Push after a combined test run is On, so its tests still run before each push/);
  assert.doesNotMatch(pc(w), /runs no test first/);
});

// Bug this guards: a record from an engine before the rule, or before its settings, was sent a rule its engine refuses.
test('Rules: Push after a combined test run, unknown to the record, is not sent', () => {
  for (const given of [{ pushbatch: undefined }, { pushbatchwhen: undefined }, { pushbatchtests: undefined }]) {
    const w = boot({ tab: 'rules' });
    deliver(w, data(given));
    assert.match(row(w).textContent, /needs a newer Conveyor/, `the record without ${Object.keys(given)[0]}`);
  }
  const w = boot({ tab: 'rules' });
  deliver(w, data({ pushbatch: undefined, pushbatchwhen: undefined, pushbatchtests: undefined }));
  assert.ok(Array.from(row(w).querySelectorAll('button, input')).every((b) => b.disabled), 'no choice is offered');
});
