// SPDX-License-Identifier: Apache-2.0
// The Rules tab's rule "Self-heals expiry": the control record's rules.healsdays, the days an entry of the Self-heals
// list may go unfixed and unseen before it leaves the list, sent as `control rules healsdays=<days>` (issues 1561, 1615).
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
// The row's choices, each as its days and whether it is pressed.
const shown = (w) => [...row(w).querySelectorAll('[data-act^="healsdays-"]')].map((b) => `${b.dataset.act.slice(10)}:${b.getAttribute('aria-pressed')}`);
const heals = (n) => ({ action: 'rules', args: [`healsdays=${n}`], repo: 'sample' });

// Bugs this guards: the Rules tab had no control for the expiry age, so the owner could change it only with the
// command; the days in force were not marked, or a value set with the command (45) was not shown at all; a choice
// sent another rule or number; clicking the days in force sent them again.
test('Rules: Self-heals expiry offers 7 to 90 days, marks the days in force and sends the days chosen', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data(30));
  assert.deepEqual(shown(w), ['7:false', '14:false', '30:true', '60:false', '90:false']);
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'healsdays-30').click()), [], 'the days in force send nothing');
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'healsdays-60').click()), [heals(60)]);
  next(w, data(45));
  assert.deepEqual(shown(w), ['7:false', '14:false', '30:false', '45:true', '60:false', '90:false'], 'the command\'s 45 is shown, in order, and marked');
});

// Bug this guards: Undo sent another rule, the new days or the default 30, not the days the record held before; the
// Undo of that Undo sent no days. 45, not the default 30: Undo falls back to 30 when it reads no days.
test('Rules: Undo of a Self-heals expiry choice sends the earlier days, and its Undo the chosen days', async () => {
  const w = boot({ tab: 'rules' });
  const undo = () => act(rulesP(w).querySelector('.rules-last'), 'undo');
  deliver(w, data(45));
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'healsdays-14').click()), [heals(14)]);
  assert.deepEqual(await sent(w, () => undo().click()), [heals(45)], 'Undo puts the earlier days back');
  assert.deepEqual(await sent(w, () => undo().click()), [heals(14)], 'the Undo of the Undo puts the chosen days back');
});

// Bug this guards: a record from an engine before the rule was sent a setting its engine refuses.
test('Rules: Self-heals expiry, unknown to the record, is disabled and not sent', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data(undefined));
  const choices = [...row(w).querySelectorAll('[data-act^="healsdays-"]')];
  assert.ok(choices.length === 5 && choices.every((b) => b.disabled), 'every choice is disabled');
  assert.match(row(w).textContent, /needs a newer Conveyor/);
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'healsdays-30').click()), [], 'a click sends nothing');
});
