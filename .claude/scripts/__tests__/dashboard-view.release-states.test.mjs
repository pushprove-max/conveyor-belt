// SPDX-License-Identifier: Apache-2.0
// The Release panel's states that its run record alone does not show plainly: a release refused over a failed suite,
// a full test run that passed on main's head, a version already released, the mode question on a box, and Run suite
// again (issue 1430). The panel's other cases are in dashboard-view.release.test.mjs. Shared setup:
// dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { boot, deliver, next, full, panel, act, settle, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const HEAD = 'b'.repeat(40);
// The plugin: docs/releases/1.0.0.md on main and no tag yet; `run` its suite records, `rule` the control record's suiteMachine.
function data(runs, plugin = {}, rule = null) {
  const d = full();
  d.panels.release.data.records = [{ repo: 'plugin', url: 'https://github.com/example/plugin', suiteMachine: rule, suites: runs,
    release: { tag: null, count: 2, next: '1.0.0', notes: true, written: ['1.0.0'], head: HEAD, releases: true, commits: [], ...plugin } }];
  return d;
}
const RUN = { kind: 'release', version: '1.0.0', step: 'release-prep', sha: HEAD, since: '2026-11-14T08:00:00Z', moved: false, reasons: [] };
const card = (w) => panel(w, 'release').querySelector('[data-project="plugin"]');
const stepOf = (w, name) => card(w).querySelector(`[data-step="${name}"]`);
const sent = async (w, fn) => { fn(); await settle(); await settle(); return w.posts.splice(0).map((p) => p.body); };

// Bug it guards: release-prep keeps its failed suite (mode, failed, cases) on a release it refuses; the panel counted
// that record neither passed nor failed, so step 2 said "Not run" and Release anyway was gone.
test('a release refused over a failed suite: step 2 shows Failed in parallel, and Release anyway stays', () => {
  const w = boot();
  const red = { sha: HEAD, files: ['conveyor/conveyor.test.sh'], cases: ['capwaittests'] };
  deliver(w, data([{ ...RUN, step: 'release', ended: '2026-11-14T08:25:00Z', state: 'refused', mode: 'parallel', failed: 1, cases: ['capwaittests'], red,
    reasons: ['the suite of 1.0.0 failed on bbbbbbbbbbbb'] }]));
  const s2 = stepOf(w, 'full-suite');
  assert.equal(s2.dataset.state, 'failed');
  assert.match(s2.querySelector('.release-line').textContent, /^Failed on bbbbbbbbbbbb/);
  assert.equal(s2.querySelector('[data-figure="suite-mode"]').textContent, 'Ran its test files in parallel');
  assert.doesNotMatch(s2.textContent, /Not run/);
  assert.ok(act(card(w), 'release-anyway'), 'Release anyway goes over the failed suite the refused release kept');
});

// Bug it guards: a full test run that passed on main's head was ignored (only release records counted), so Release said
// it needs the suite though release-prep reuses that run and runs no test. Also: release-prep's earlier failed suite on
// an older commit still disabled Release ("the suite failed") after that full test run passed on the new main. And the
// older run's failed case was listed under the new passed run with no commit, as if that run had failed it.
test('a full test run passed on main\'s head after a failed release suite on an older commit: Release is enabled, with no mode question', async () => {
  const w = boot();
  deliver(w, data([{ ...RUN, sha: 'a'.repeat(40), ended: '2026-11-14T06:00:00Z', state: 'failed', failed: 1, cases: ['capwaittests'],
    reasons: ['the suite failed: capwaittests'] },
    { kind: 'full test', version: null, step: 'run', sha: HEAD, since: null, ended: '2026-11-14T07:40:00Z', state: 'passed', failed: 0, cases: [], moved: false, reasons: [] }]));
  const rel = act(card(w), 'release');
  assert.equal(rel.disabled, false, rel.textContent);
  assert.equal(rel.textContent, 'Release 1.0.0');
  assert.equal(stepOf(w, 'full-suite').dataset.state, 'done');
  assert.equal(stepOf(w, 'full-suite').querySelector('[data-figure="suite-use"]').textContent, 'Uses the full test suite that passed on bbbbbbbbbbbb');
  const from = stepOf(w, 'full-suite').querySelector('[data-figure="reasons-from"]');
  assert.equal(from && from.textContent, 'From the release run on aaaaaaaaaaaa:', 'the older run\'s reasons name its commit');
  assert.equal(from.nextElementSibling.textContent, 'the suite failed: capwaittests');
  assert.deepEqual(await sent(w, () => { rel.click(); act(card(w), 'release').click(); }), [{ action: 'release-run', args: ['1.0.0'], repo: 'plugin' }]);
});

// Bug it guards: a version still typed after its release kept Release enabled (a released record counts as passed),
// though release-prep refuses a tag that exists.
test('after 1.5.1 is released with 1.5.1 still typed, Release is disabled and says it is released', () => {
  const w = boot();
  deliver(w, data([], { tag: 'v1.5.0', next: '1.5.1', written: ['1.5.0', '1.5.1'] }));
  const field = card(w).querySelector('[data-field="version"]');
  field.value = '1.5.1'; field.dispatchEvent(new w.Event('input'));
  next(w, data([{ ...RUN, version: '1.5.1', step: 'release', ended: '2026-11-14T08:25:00Z', state: 'released' }], { tag: 'v1.5.1', next: '1.6.0', notes: false, written: ['1.5.0', '1.5.1'] }));
  assert.equal(card(w).querySelector('[data-field="version"]').value, '1.5.1', 'the typed version is kept');
  const rel = act(card(w), 'release');
  assert.deepEqual([rel.disabled, rel.textContent], [true, 'Release 1.5.1: v1.5.1 is already released']);
});

// Bug it guards: the mode question said "load on the build machine" even with the rule's devbox chosen.
test('with the rule on a devbox, the mode lines name the devbox; with This machine chosen, the build machine', () => {
  const w = boot();
  deliver(w, data([], {}, { kind: 'devbox', size: 'XL', tag: 'conveyor-suite-plugin', idleStop: '15m' }));
  act(card(w), 'release-prep').click(); act(card(w), 'release-prep').click();
  const line = (m) => act(card(w), `mode-${m}`).querySelector('.board-from').textContent;
  assert.equal(line('serial'), 'Slower, the least load on Namespace Devbox XL.');
  assert.equal(line('parallel'), 'Faster, more load on Namespace Devbox XL.');
  act(card(w), 'machine-local').click();
  assert.equal(line('parallel'), 'Faster, more load on the build machine. The belt is slower meanwhile.');
});

// Bug it guards: no case pressed Run suite again (a passed suite) to check that it asks the mode before it sends.
test('Run suite again after a passed suite asks the mode; nothing is sent until In parallel, which sends --parallel', async () => {
  const w = boot();
  deliver(w, data([{ ...RUN, ended: '2026-11-14T08:15:00Z', state: 'passed', failed: 0, cases: [] }]));
  assert.equal(act(card(w), 'release-prep').textContent, 'Run suite again');
  assert.deepEqual(await sent(w, () => { act(card(w), 'release-prep').click(); act(card(w), 'release-prep').click(); }), [], 'two presses send nothing');
  assert.ok(card(w).querySelector('[data-figure="mode-ask"]'), 'the mode question shows');
  assert.deepEqual(await sent(w, () => act(card(w), 'mode-parallel').click()), [{ action: 'release-run', args: ['prep', '1.0.0', '--parallel'], repo: 'plugin' }]);
});

// Bug it guards (follow-up of #1461): while 1.0.0 waited on its notes card, Conveyor refused Draft notes for 1.1.0 and
// said to stop 1.0.0 first, but the panel read the wait only from a run of the typed version, so with 1.1.0 typed it
// hid Stop until the owner typed 1.0.0 again. Stop shows, names the waiting version, and sends the stop.
const WAITING = { ...RUN, sha: null, ended: '2026-11-14T08:15:00Z', state: 'waiting', notes: { card: 'c20261114T081500-plugin-0', then: 'prep', mode: null, machine: null } };
test('with 1.1.0 typed while 1.0.0 waits on its notes card, Stop shows in the notes step, names 1.0.0 and sends the stop', async () => {
  const w = boot();
  deliver(w, data([WAITING], { notes: false, written: [] }));
  const field = card(w).querySelector('[data-field="version"]');
  field.value = '1.1.0'; field.dispatchEvent(new w.Event('input'));
  const s1 = stepOf(w, 'release-notes');
  assert.match(s1.querySelector('.release-line').textContent, /^docs\/releases\/1\.1\.0\.md on main/, 'the typed version is 1.1.0');
  assert.ok(s1.querySelector('[data-act="release-stop"]'), 'Stop shows with 1.1.0 typed');
  assert.equal(s1.querySelector('[data-figure="stop-other"]').textContent,
    'Release 1.0.0 waits on its notes card. Conveyor runs no other version until that wait ends. Stop ends it.');
  assert.deepEqual(await sent(w, () => { act(card(w), 'release-stop').click(); act(card(w), 'release-stop').click(); }), [{ action: 'release-run', args: ['stop', '1.0.0'], repo: 'plugin' }]);
});

// Bug it guards (follow-up of #1461): a run whose notes card its fixes entry says is closed still waits, and Conveyor
// refuses another version while it does (that entry can be older than a retry of the card), but the panel hid Stop for
// it, so the owner could not end the wait from the Board. Stop shows beside the closed card, with no other-version line.
test('a run waiting on a notes card its fixes entry says is closed shows Stop in the notes step', () => {
  const w = boot();
  const id = WAITING.notes.card;
  deliver(w, data([{ ...WAITING, fixes: [{ issue: null, card: id, ids: [id], state: 'closed' }] }], { notes: false, written: [] }));
  const s1 = stepOf(w, 'release-notes');
  assert.match(s1.querySelector('.release-line').textContent, /was closed before it landed/, 'the fixture is the closed-card state');
  assert.ok(s1.querySelector('[data-act="release-stop"]'), 'Stop shows beside the closed card');
  assert.equal(s1.querySelector('[data-figure="stop-other"]'), null, 'the run is of the typed version: no other-version line');
});

// Bug it guards (review of the follow-up of #1461): with 1.1.0 typed while the suite of 1.0.0 ran, the suite step showed
// only Stop under the typed 1.1.0, so the owner could not see that Stop stops the run of 1.0.0. The step names 1.0.0, and
// Stop sends that version; with 1.0.0 typed, no such line shows.
test('with 1.1.0 typed while the suite of 1.0.0 runs, the suite step says Stop stops 1.0.0, and Stop sends 1.0.0', async () => {
  const w = boot();
  deliver(w, data([{ ...RUN, ended: null, state: 'running' }]));
  assert.equal(stepOf(w, 'full-suite').querySelector('[data-figure="stop-other"]'), null, 'the run is of the typed version: no other-version line');
  const field = card(w).querySelector('[data-field="version"]');
  field.value = '1.1.0'; field.dispatchEvent(new w.Event('input'));
  const s2 = stepOf(w, 'full-suite');
  assert.equal(s2.querySelector('[data-figure="stop-other"]').textContent, 'The suite of release 1.0.0 runs. Stop stops it.');
  assert.deepEqual(await sent(w, () => { act(card(w), 'release-stop').click(); act(card(w), 'release-stop').click(); }), [{ action: 'release-run', args: ['stop', '1.0.0'], repo: 'plugin' }]);
});
