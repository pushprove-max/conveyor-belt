// SPDX-License-Identifier: Apache-2.0
// The Rules tab's rule "Land as" (the control record's landAs, else the pack's push.landAs, #247): main or pr.
// Shared setup: dashboard-view.helpers.mjs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { boot, deliver, next, settle, full, act, rulesP, ruled } from './dashboard-view.helpers.mjs';

// The Rules part with the record's landAs as given (none: a record from an engine before the rule) and the pack's.
function data(landAs, pack = 'main') {
  const d = full(), r = d.panels.rules.data;
  const c = { ...r.control };
  delete c.landAs;
  r.control = landAs === 'none' ? c : { ...c, landAs };
  r.packLandAs = pack;
  return d;
}
const row = (w) => ruled(w).querySelector('[data-rule="land-as"]');
const pressed = (w) => ['land-as-main', 'land-as-pr'].map((a) => act(rulesP(w), a).getAttribute('aria-pressed'));
const sent = async (w, fn) => { fn(); await settle(); return w.posts.splice(0).map((p) => p.body); };

// Bugs this guards: the owner could not see or set Land as from the Board; a record that leaves it to the pack showed
// Main for a pack that lands as a pull request; a change sent nothing, or the wrong value.
test('Rules: Land as shows the pack\'s value while the record sets none, and is set from its row', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data(null, 'pr'));
  assert.ok(row(w), 'the rule has a row on the Rules tab');
  assert.deepEqual(pressed(w), ['false', 'true'], 'the pack\'s pr is in force');
  assert.match(row(w).textContent, /one pull request from conveyor\/landing collects the cards/);
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'land-as-pr').click()), [], 'the choice in force sends nothing');
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'land-as-main').click()), [{ action: 'land-as', args: ['main'], repo: 'sample' }]);
  // The record the engine keeps after that change wins over the pack.
  next(w, data('main', 'pr'));
  assert.deepEqual(pressed(w), ['true', 'false']);
  assert.doesNotMatch(row(w).textContent, /pull request from/);
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'land-as-pr').click()), [{ action: 'land-as', args: ['pr'], repo: 'sample' }]);
});

// Bug this guards: a record with no landAs (an engine before the rule) was sent an action its `control` refuses.
test('Rules: Land as is not sent to an engine that does not know it', () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data('none'));
  assert.ok(act(rulesP(w), 'land-as-main').disabled && act(rulesP(w), 'land-as-pr').disabled, 'an older engine is sent neither');
  assert.match(row(w).textContent, /needs a newer Conveyor/);
});
