// SPDX-License-Identifier: Apache-2.0
// The Rules tab's Judge row, "May decline as a rare case": the control record's judgeRare, the levels (P0 to P3) at
// which the judge may decline a finding as a rare case, sent whole as `control judge rare <level>...` (none: `rare none`).
// Shared setup: dashboard-view.helpers.mjs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { boot, deliver, next, settle, full, ruled, rulesP, act } from './dashboard-view.helpers.mjs';

// The Rules part with the record's judgeRare as given; undefined leaves the field out, as a record from before it.
function data(rare) {
  const d = full(), r = d.panels.rules.data;
  r.control = { ...r.control };
  delete r.control.judgeRare;
  if (rare !== undefined) r.control.judgeRare = rare;
  return d;
}
const row = (w) => ruled(w).querySelector('[data-rule="judge"]');
const pressed = (w) => ['P0', 'P1', 'P2', 'P3'].filter((p) => row(w).querySelector(`[data-act="judge-rare-${p}"]`).getAttribute('aria-pressed') === 'true');
const posts = async (w, b) => { b.click(); await settle(); return w.posts.splice(0); };
const click = (w, p) => posts(w, row(w).querySelector(`[data-act="judge-rare-${p}"]`));
const undo = (w) => posts(w, act(rulesP(w).querySelector('.rules-note'), 'undo'));
const judge = (...args) => [{ url: 'control', body: { action: 'judge', args, repo: 'sample' } }];

// Bugs this guards: the owner could not see or set the levels from the Board; a switch showed a level the record does
// not hold, or none said "no level"; a click sent a list other than the record's with that one level turned, sent it
// anywhere but the control address, or sent an empty list (a usage error from `control judge rare`) in place of
// `rare none`; the switches kept the old levels until the next snapshot; Undo did not send the levels back.
test('Rules: the Judge row shows the record\'s rare-case levels and a click sends the new list whole', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data(undefined));
  assert.deepEqual(pressed(w), [], 'a record without the setting shows no level pressed');
  assert.match(row(w).textContent, /may decline as a rare case at no level/, 'a record without the setting says no level');
  next(w, data(['P3']));
  assert.deepEqual(pressed(w), ['P3'], 'the record\'s P3 is pressed, and only it');
  assert.doesNotMatch(row(w).textContent, /no level/, 'a record with a level does not say no level');
  assert.deepEqual(await click(w, 'P2'), judge('rare', 'P2', 'P3'), 'clicking P2 with P3 set sends P2 P3 to control');
  assert.deepEqual(pressed(w), ['P2', 'P3'], 'P2 shows pressed before the next snapshot');
  assert.deepEqual(await undo(w), judge('rare', 'P3'), 'Undo after adding P2 sends the record\'s P3 back');
  next(w, data(['P2', 'P3']));
  assert.deepEqual(await click(w, 'P2'), judge('rare', 'P3'), 'clicking a pressed P2 takes it out');
  next(w, data(['P3']));
  assert.deepEqual(await click(w, 'P3'), judge('rare', 'none'), 'taking out the last level sends none');
  assert.deepEqual(pressed(w), [], 'no level shows pressed before the next snapshot');
  assert.deepEqual(await undo(w), judge('rare', 'P3'), 'Undo after taking out the last level sends P3 back');
});
