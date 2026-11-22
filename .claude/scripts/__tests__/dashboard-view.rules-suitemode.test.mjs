// SPDX-License-Identifier: Apache-2.0
// The Rules tab's rule "Release suite mode": the control record's suiteMode, how a release's suite runs its test files
// when the press names no mode, sent as `control suite-mode <serial | parallel>`. Shared setup: dashboard-view.helpers.mjs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { boot, deliver, next, settle, full, act, rulesP, ruled } from './dashboard-view.helpers.mjs';

// The Rules part with the record's suiteMode as given; undefined leaves the field out.
function data(mode) {
  const d = full(), r = d.panels.rules.data;
  r.control = { ...r.control };
  delete r.control.suiteMode;
  if (mode !== undefined) r.control.suiteMode = mode;
  return d;
}
const row = (w) => ruled(w).querySelector('[data-rule="suite-mode"]');
const sent = async (w, fn) => { fn(); await settle(); return w.posts.splice(0).map((p) => p.body); };

// Bug this guards (#1364): the Rules tab had no row for the mode, so the owner could not make parallel the project's
// choice from the Board; the row showed the other mode as pressed; a choice sent the wrong action or word.
test('Rules: Release suite mode shows the record\'s mode, and a choice sends it', async () => {
  const dflt = JSON.parse(readFileSync(new URL('../../../conveyor/lib/control-defaults.json', import.meta.url), 'utf8')).suiteMode;
  assert.equal(dflt, 'serial', 'the default of the rule is one by one');
  const w = boot({ tab: 'rules' });
  deliver(w, data(dflt));
  assert.ok(row(w), 'the rule has a row on the Rules tab');
  assert.equal(act(rulesP(w), 'suite-mode-serial').getAttribute('aria-pressed'), 'true');
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'suite-mode-parallel').click()), [{ action: 'suite-mode', args: ['parallel'], repo: 'sample' }]);
  // The line that says it was done offers Undo, which sends the mode the record held before.
  assert.deepEqual(await sent(w, () => act(rulesP(w).querySelector('.rules-note'), 'undo').click()), [{ action: 'suite-mode', args: ['serial'], repo: 'sample' }], 'Undo puts the earlier mode back');
  next(w, data('parallel'));
  assert.equal(act(rulesP(w), 'suite-mode-parallel').getAttribute('aria-pressed'), 'true');
  assert.equal(act(rulesP(w), 'suite-mode-serial').getAttribute('aria-pressed'), 'false');
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'suite-mode-parallel').click()), [], 'the mode in force is not sent again');
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'suite-mode-serial').click()), [{ action: 'suite-mode', args: ['serial'], repo: 'sample' }]);
});

// Bug this guards: a record from an engine before the rule was sent an action its engine refuses.
test('Rules: Release suite mode, unknown to the record, is not sent', () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data(undefined));
  assert.match(row(w).textContent, /needs a newer Conveyor/);
  assert.ok(Array.from(row(w).querySelectorAll('button')).every((b) => b.disabled), 'no choice is offered');
});
