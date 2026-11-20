// SPDX-License-Identifier: Apache-2.0
// The dashboard page's Tests page (#520): the panel Test limits, the pack's test settings; the Rules tab keeps one
// line where its Machine section was. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { boot, deliver, next, settle, full, act, panel, rulesP, cases, T0 } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const sec = (w) => panel(w, 'tests').querySelector('.tests-limits');
const lim = (w, k) => sec(w).querySelector(`[data-limit="${k}"]`);
const shown = (w, a) => !act(sec(w), a).hidden;
const type = (w, a, v) => { const f = act(sec(w), a); f.value = v; f.dispatchEvent(new w.Event(f.tagName === 'SELECT' ? 'change' : 'input')); };
// A snapshot whose pack sets "Take a file off card runs" (slowIssues) to <on>, taken at <now>.
const issues = (on = false, now = T0) => { const d = full(now); d.panels.tests.data.tests.settings.slowIssues = on; return d; };

// Issue 346. Bug: the machine room is removed, so no card waits for the load, yet a snapshot that still carries the
// machine's load drew a Load limit row whose Save sends an action the build machine refuses.
test('Tests: no Load limit row, even from a snapshot that still carries the machine\'s load', () => {
  const w = boot({ tab: 'tests' });
  const d = full();
  d.panels.tests.data.machine = { maxLoad: 30, unread: false, cores: 16, load: 31.5 };
  deliver(w, d);
  assert.match(sec(w).textContent, /^Test limits/);
  assert.equal(lim(w, 'load'), null);
  assert.doesNotMatch(sec(w).textContent, /Load limit|load now/);
});

// Bugs (each row's Save works alike; the Load limit's case, removed with it by issue 346, is here on the one row left
// with a Save, Take a file off card runs): a value picked was sent before Save, a new snapshot lost it, and a refusal
// from the build machine lost the value picked.
test('Tests: Take a file off card runs picked sends nothing until Save, a new snapshot keeps it, and a refusal keeps it unsaved', async () => {
  const w = boot({ tab: 'tests' });
  deliver(w, issues());
  assert.ok(!shown(w, 'slow-issues-save'), 'nothing to save before a change');
  type(w, 'slow-issues-field', 'true');
  assert.ok(shown(w, 'slow-issues-save') && lim(w, 'off-card-runs').textContent.includes('Unsaved'), 'picked: Unsaved, with Save');
  next(w, issues());
  assert.deepEqual(w.posts, [], 'picking sent nothing');
  assert.equal(act(sec(w), 'slow-issues-field').value, 'true', 'a new snapshot keeps the value picked');
  w.reply = { ok: false, status: 409, text: () => Promise.resolve('conveyor: the pack does not read') };
  act(sec(w), 'slow-issues-save').click();
  await settle();
  assert.equal(w.posts.length, 1);
  assert.match(lim(w, 'off-card-runs').querySelector('.rules-refused').textContent, /Not saved: conveyor: the pack does not read/);
  assert.equal(act(sec(w), 'slow-issues-field').value, 'true', 'refused: the value picked stays');
  assert.ok(shown(w, 'slow-issues-save'), 'and still unsaved');
});

// Issue 392. Bug: when the pack does not read, the snapshot sends tests: null, and the page still drew a Settings
// control that opened on only the Test limits heading.
test('Tests: no Settings control when the snapshot has no test figures', () => {
  const w = boot({ tab: 'tests' });
  const d = full();
  d.panels.tests.data.tests = null;
  deliver(w, d);
  assert.match(panel(w, 'tests').querySelector('.warn-note').textContent, /could not read the test figures/);
  assert.equal(panel(w, 'tests').querySelector('.tests-settings'), null);
  assert.equal(sec(w), null);
});

// Two places for one setting drift apart: the Rules tab keeps no Load limit, and says where the test limits are.
test('Rules: no Load limit field, and one line that says test limits are on the Tests page', () => {
  const w = boot({ tab: 'rules' });
  const d = full();
  d.panels.rules.data.machine = { maxLoad: 30, unread: false, cores: 16, load: 31.5 };  // as the collector gave it before #520: still not drawn
  deliver(w, d);
  assert.equal(rulesP(w).querySelector('[data-act^="load"]'), null, 'no Load limit control on Rules');
  assert.doesNotMatch(rulesP(w).textContent, /Load limit|In force: 30/);
  const line = rulesP(w).querySelector('.rules-limits');
  assert.equal(line.textContent, 'Test limits are on the Tests page.');
  assert.ok(line.closest('[data-rule="cores"]'), 'in the Reserved cores row, with the other machine limit');
  act(line, 'tests-page').click();
  assert.equal(new w.URL(w.location.href).searchParams.get('tab'), 'tests', 'its link opens the Tests page');
  assert.ok(panel(w, 'tests'));
});

// #349: no test file has a CPU budget. Bug caught: Test limits still has a CPU budget for a test file, or a list of the
// budgets of single files, though the engine holds no file to one.
test('Tests: the pack row of the files slow on purpose names the pack file and the files; no row sets a CPU budget', () => {
  const w = boot({ tab: 'tests' });
  deliver(w, full());
  assert.match(lim(w, 'purpose').textContent, /Saves to: Pack file: this project/);
  assert.match(lim(w, 'purpose').textContent, /conveyor\/tests\/e2e\.test\.sh: runs the whole loop/);
  assert.equal(lim(w, 'budget'), null, 'no CPU budget for a test file');
  assert.equal(lim(w, 'budgets'), null, 'no budgets of single files');
  assert.equal(act(sec(w), 'budget-field'), null);
});

// #457's hard box and "take a file off card runs" are shown only when the snapshot names them: a row for a setting the
// engine does not have would save nothing.
test('Tests: the #457 rows show when the snapshot names them and not when it does not', async () => {
  const w = boot({ tab: 'tests' });
  const d = full();
  delete d.panels.tests.data.tests.settings.slowIssues;
  deliver(w, d);
  assert.equal(lim(w, 'box'), null);
  assert.equal(lim(w, 'off-card-runs'), null);
  const named = full();
  named.panels.tests.data.tests.settings.box = { on: true };
  next(w, named);
  assert.match(lim(w, 'box').textContent, /Hard box for each test file.*On/);
  assert.match(lim(w, 'off-card-runs').textContent, /Take a file off card runs.*Saves to: Pack file: this project/);
  assert.equal(act(sec(w), 'slow-issues-field').value, 'false');
  type(w, 'slow-issues-field', 'true');
  act(sec(w), 'slow-issues-save').click();
  await settle();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [['slow-issues', 'true']]);
});
