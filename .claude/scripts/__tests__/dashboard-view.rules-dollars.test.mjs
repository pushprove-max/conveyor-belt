// SPDX-License-Identifier: Apache-2.0
// The Rules tab's rows "Card dollar limit" and "Issue dollar limit": the control record's rules.cardusd and
// rules.issueusd (0 for off), sent as `control rules cardusd=<dollars|off>` and `issueusd=<dollars|off>`.
// Shared setup: dashboard-view.helpers.mjs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { boot, deliver, next, settle, full, act, rulesP, ruled } from './dashboard-view.helpers.mjs';

// The Rules part with the record's two limits as given; a key left out is left out of the record (an older engine).
function data(limits) {
  const d = full(), r = d.panels.rules.data;
  r.control = { ...r.control, rules: { ...r.control.rules } };
  delete r.control.rules.cardusd;
  delete r.control.rules.issueusd;
  Object.assign(r.control.rules, limits);
  return d;
}
const row = (w, key) => ruled(w).querySelector(`[data-rule="${key}"]`);
const sent = async (w, fn) => { fn(); await settle(); return w.posts.splice(0).map((p) => p.body); };
// A row's choices, each by its words and whether it is pressed.
const shown = (w, key) => [...row(w, key).querySelectorAll(`[data-act^="${key}-"]`)].map((b) => `${b.textContent}:${b.getAttribute('aria-pressed')}`);
const rules = (arg) => ({ action: 'rules', args: [arg], repo: 'sample' });

// Bugs this guards: the Rules tab had no row for a dollar limit; the limit in force was not marked, or one set with
// the command ($35) was not shown at all; a choice sent another rule or number, or Off sent 0, which the host refuses.
test('Rules: the dollar limit rows mark the limit in force and send the choice clicked', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data({ cardusd: 10, issueusd: 35 }));
  assert.deepEqual(shown(w, 'cardusd'), ['Off:false', '$5:false', '$10:true', '$20:false', '$50:false', '$100:false']);
  assert.deepEqual(shown(w, 'issueusd'), ['Off:false', '$5:false', '$10:false', '$20:false', '$35:true', '$50:false', '$100:false']);
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'cardusd-10').click()), [], 'the limit in force sends nothing');
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'issueusd-20').click()), [rules('issueusd=20')]);
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'issueusd-0').click()), [rules('issueusd=off')]);
  next(w, data({ cardusd: 0, issueusd: 25 }));
  assert.equal(shown(w, 'cardusd')[0], 'Off:true', 'the record\'s 0 is Off');
});

// Bug this guards: Undo of a dollar limit sent `cardusd=on` (the on or off rules' Undo), which the host refuses,
// both back to a number and back to Off.
test('Rules: Undo of a dollar limit choice sends the earlier limit, Off too', async () => {
  const w = boot({ tab: 'rules' });
  const undo = () => act(rulesP(w).querySelector('.rules-last'), 'undo');
  deliver(w, data({ cardusd: 0, issueusd: 25 }));
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'cardusd-50').click()), [rules('cardusd=50')]);
  assert.deepEqual(await sent(w, () => undo().click()), [rules('cardusd=off')], 'Undo puts Off back');
  assert.deepEqual(await sent(w, () => undo().click()), [rules('cardusd=50')], 'the Undo of the Undo puts $50 back');
});

// Bug this guards: a snapshot from an engine without the two rules drew rows with no value, or broke the tab.
test('Rules: with no dollar limits in the record, neither row shows and the tab has no error', () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data({}));
  assert.ok(row(w, 'healsdays'), 'the group is drawn');
  assert.equal(row(w, 'cardusd'), null);
  assert.equal(row(w, 'issueusd'), null);
  assert.doesNotMatch(rulesP(w).textContent, /dollar limit/i);
});
