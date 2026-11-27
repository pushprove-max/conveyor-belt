// SPDX-License-Identifier: Apache-2.0
// The Rules tab's rule "Serena (code search in card sessions)" (Models): the control record's rules.serena, a checkbox
// a role, sent as `control rules serena=<roles>|off`, with the snapshot's serena (what the build machine found) under
// it. Shared setup: dashboard-view.helpers.mjs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { boot, deliver, next, settle, full, act, rulesP, ruled } from './dashboard-view.helpers.mjs';

const ROLES = ['build', 'fix', 'testfix', 'review', 'judge'];
// The Rules part with the rule Serena naming <roles>, and the snapshot's serena <found> (undefined: the key left out).
function data(roles, found) {
  const d = full(), r = d.panels.rules.data;
  r.control = { ...r.control, rules: { ...r.control.rules, serena: roles } };
  if (found === undefined) delete r.serena; else r.serena = found;
  return d;
}
const row = (w) => ruled(w).querySelector('[data-rule="serena"]');
const box = (w, k) => act(rulesP(w), `serena-${k}`);
const sent = async (w, fn) => { fn(); await settle(); return w.posts.splice(0).map((p) => p.body); };
const undo = (w) => act(rulesP(w).querySelector('.rules-note'), 'undo').click();
const check = (w, k) => { const b = box(w, k); b.checked = !b.checked; b.dispatchEvent(new w.Event('change')); };
const INSTALLED = { installed: true, path: '/opt/example/bin/serena', version: 'Serena 9.9.9' };

// Bug this guards (#1823): the Board had no rule for which card sessions use Serena and did not show whether the
// build machine has it; a role's box sent the wrong roles, or Undo did not put the earlier rule back.
test('Rules: Serena is in Models with one box a role, its detection line, and a box sends the roles', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data(['build'], INSTALLED));
  assert.ok(ruled(w).querySelector('[data-set="models"] [data-rule="review-account"] + [data-rule="serena"]'), 'the row is in Models, after Review account');
  assert.match(row(w).textContent, /Serena \(code search in card sessions\)/);
  assert.match(row(w).textContent, /Installed: Serena 9\.9\.9 at \/opt\/example\/bin\/serena/);
  assert.deepEqual(ROLES.map((k) => [k, box(w, k).checked, box(w, k).disabled]),
    ROLES.map((k) => [k, k === 'build', false]), 'build is on, and every box can be changed');
  assert.deepEqual(await sent(w, () => check(w, 'fix')), [{ action: 'rules', args: ['serena=build,fix'], repo: 'sample' }]);
  assert.deepEqual(await sent(w, () => undo(w)), [{ action: 'rules', args: ['serena=build'], repo: 'sample' }], 'Undo puts build alone back');
  next(w, data(['build'], INSTALLED));
  assert.deepEqual(await sent(w, () => check(w, 'build')), [{ action: 'rules', args: ['serena=off'], repo: 'sample' }], 'the last role off turns the rule off');
});

// Bug this guards (#1823): with no Serena on the build machine the Board let the owner turn on a rule that does
// nothing, and said nothing of it; a rule already on gave no way back.
test('Rules: Serena not installed says so, disables the boxes that are off, and warns of a rule that is on', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data([], { installed: false, path: null, version: null }));
  assert.match(row(w).textContent, /Not installed on the build machine: setup can install it/);
  assert.doesNotMatch(row(w).textContent, /Serena rule on/);
  assert.deepEqual(ROLES.map((k) => [k, box(w, k).disabled]), ROLES.map((k) => [k, true]), 'every box is disabled');
  next(w, data(['review'], { installed: false, path: null, version: null }));
  assert.match(row(w).textContent, /Serena rule on, but serena is not installed/);
  assert.deepEqual(ROLES.map((k) => [k, box(w, k).disabled]), ROLES.map((k) => [k, k !== 'review']), 'only the box that is on can be changed');
  assert.deepEqual(await sent(w, () => check(w, 'review')), [{ action: 'rules', args: ['serena=off'], repo: 'sample' }]);
});
