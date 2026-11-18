// SPDX-License-Identifier: Apache-2.0
// The dashboard page's Tests page (#520): the panel Test limits. Load limit moved here from the Rules tab's Machine
// section (#462) with the same behaviour; the Rules tab keeps one line in its place. Shared setup:
// dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { boot, deliver, next, settle, full, act, panel, rulesP, cases, T0 } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const sec = (w) => panel(w, 'tests').querySelector('.tests-limits');
const lim = (w, k) => sec(w).querySelector(`[data-limit="${k}"]`);
const shown = (w, a) => !act(sec(w), a).hidden;
const type = (w, a, v) => { const f = act(sec(w), a); f.value = v; f.dispatchEvent(new w.Event(f.tagName === 'SELECT' ? 'change' : 'input')); };
const said = (w) => panel(w, 'tests').querySelector('.tests-note').textContent;
// The machine of the snapshot: the host file's maxLoad 30, and its 16 cores at a load of 31.5.
const snap = (maxLoad = 30, now = T0) => { const d = full(now); d.panels.tests.data.machine = { maxLoad, unread: false, cores: 16, load: 31.5 }; return d; };

// Bugs: the engine holds back new cards above the host file's maxLoad, but it could be set only by editing that file
// by hand, so a 16-core machine ran at a load of 60 to 94 for hours with none set. A value typed must send nothing
// until Save (as a role's, #419), a new snapshot must not lose it, and Off must reach the engine as off, not as an
// empty value.
test('Tests: Load limit shows its value, the cores and the load; typing sends nothing, Save sends machine load 20, Off sends machine load off', async () => {
  const w = boot({ tab: 'tests' });
  deliver(w, snap());
  assert.match(sec(w).textContent, /^Test limits/);
  assert.match(lim(w, 'load').textContent, /Saves to: Host file: this machine, all projects/, 'the row names where it saves');
  assert.equal(act(sec(w), 'load-field').value, '30', 'the limit in force');
  assert.match(sec(w).textContent, /In force: 30 · 16 cores · load now 31\.5/, 'the cores and the 1-minute load beside it');
  assert.match(sec(w).textContent, /No new card starts while the load is above this\. Conveyor never stops the cards that already run\./);
  assert.ok(!shown(w, 'load-save'), 'nothing to save before a change');
  type(w, 'load-field', '20');
  assert.ok(shown(w, 'load-save') && lim(w, 'load').textContent.includes('Unsaved'), 'typed: Unsaved, with Save');
  next(w, snap());
  assert.deepEqual(w.posts, [], 'typing sent nothing');
  assert.equal(act(sec(w), 'load-field').value, '20', 'a new snapshot keeps the value typed');
  assert.match(sec(w).textContent, /In force: 30/, 'and the value in force is still the host file\'s');
  w.reply = { ok: true, status: 200, text: () => Promise.resolve('conveyor: the machine\'s load limit is 20') };
  act(sec(w), 'load-save').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'machine', body: { action: 'load', value: '20' } }]);
  assert.match(sec(w).textContent, /In force: 20/);
  assert.ok(!shown(w, 'load-save'), 'saved: no Save left');
  assert.match(said(w), /Saved: load limit now 20/);
  next(w, snap(20));
  assert.equal(act(sec(w), 'load-field').value, '20');
  act(sec(w), 'load-clear').click();
  assert.equal(act(sec(w), 'load-clear').textContent, 'Off');
  assert.equal(act(sec(w), 'load-field').value, '');
  assert.deepEqual(w.posts, [], 'Off alone sends nothing');
  act(sec(w), 'load-save').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'machine', body: { action: 'load', value: 'off' } }]);
  assert.match(sec(w).textContent, /In force: Off/);
  // One below 1 is not sent; a refusal from the build machine says so in the row, and the value stays unsaved.
  type(w, 'load-field', '0.5');
  act(sec(w), 'load-save').click();
  await settle();
  assert.deepEqual(w.posts, [], 'a limit below 1 is not sent');
  assert.match(said(w), /a number of 1 or more/);
  type(w, 'load-field', '25');
  w.reply = { ok: false, status: 409, text: () => Promise.resolve('conveyor: the host file does not read as one object') };
  act(sec(w), 'load-save').click();
  await settle();
  assert.equal(w.posts.length, 1);
  assert.match(lim(w, 'load').querySelector('.rules-refused').textContent, /Not saved: conveyor: the host file does not read/);
  assert.equal(act(sec(w), 'load-field').value, '25', 'refused: the value typed stays');
  assert.ok(shown(w, 'load-save'), 'and still unsaved');
});

// Bug: a value saved here stood until a snapshot named it, so when another Board saved 25 just after this one's 20,
// every snapshot said 25 and the row said "In force: 20" for good. A snapshot begun before the Save was answered still
// shows the value saved; one begun after shows what the host file holds, whatever it is.
test('Tests: a snapshot begun after the Save shows the load limit in force, even one changed elsewhere since', async () => {
  const w = boot({ tab: 'tests' });
  deliver(w, snap(30, T0));
  type(w, 'load-field', '20');
  w.reply = { ok: true, status: 200, headers: { get: (k) => (k === 'X-Answered-At' ? String(T0 / 1000) : null) }, text: () => Promise.resolve('conveyor: the machine\'s load limit is 20') };
  act(sec(w), 'load-save').click();
  await settle();
  next(w, snap(30, T0 + 10000));
  assert.match(sec(w).textContent, /In force: 20/, 'a snapshot begun before the answer did not read the change');
  // The live feed republishes the record it last read with a new time: one still naming 30 does not undo the Save.
  next(w, snap(30, T0 + 30000));
  assert.match(sec(w).textContent, /In force: 20/, 'a republished snapshot still naming the value replaced does not undo the Save');
  next(w, snap(25, T0 + 40000));
  assert.match(sec(w).textContent, /In force: 25/, 'one begun after it shows the value saved elsewhere since');
  assert.equal(act(sec(w), 'load-field').value, '25');
});

// A host file the build machine cannot read: its limit is not known, so it is never shown as Off nor offered to save.
test('Tests: a host file that does not read shows no Load limit to change', () => {
  const w = boot({ tab: 'tests' });
  const d = full();
  d.panels.tests.data.machine = { maxLoad: null, unread: true, cores: null, load: null };
  deliver(w, d);
  assert.match(sec(w).textContent, /Conveyor could not read the build machine's host file, so the Board does not know its load limit/);
  assert.equal(act(sec(w), 'load-field'), null);
});

// Two places for one setting drift apart: the Rules tab keeps no Load limit, and says where it went.
test('Rules: no Load limit field, and one line that says test limits are on the Tests page', () => {
  const w = boot({ tab: 'rules' });
  const d = snap();
  d.panels.rules.data.machine = d.panels.tests.data.machine;  // as the collector gave it before #520: still not drawn
  deliver(w, d);
  assert.equal(rulesP(w).querySelector('[data-act^="load"]'), null, 'no Load limit control on Rules');
  assert.doesNotMatch(rulesP(w).textContent, /Load limit|In force: 30/);
  const line = rulesP(w).querySelector('.rules-limits');
  assert.equal(line.textContent, 'Test limits are on the Tests page.');
  assert.equal(rulesP(w).querySelector('.rules').firstChild, line, 'where the Machine section was');
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
