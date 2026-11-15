// SPDX-License-Identifier: Apache-2.0
// The dashboard page's Tests page, its actions (#521): the marks, Judge this test and its box, the text as it comes,
// Stop and Copy, the result kept, and the Tests model. The rest (no Tests model, the issue preview, Auto-file) is in
// dashboard-view.tests-autofile.test.mjs. Shared setup: dashboard-view.helpers.mjs (TESTS: three files; TA: the
// snapshot with the actions).
import assert from 'node:assert/strict';
import { boot, deliver, next, settle, later, act, cases, iso, T0, TA } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const { MERGE, X, ID1, ID2, rec, snap, tp, rowOf, opened, open, type, pick, said, model, resultRow, reply } = TA;

// Bug it guards: an owner who cannot tell an action that runs now from one that files an issue. Each action button of
// a row has its mark; a button that opens a view (a row's name, View) has none, and the legend says what each means.
test('Tests actions: each action button has its mark, now or issue; a view button has none', () => {
  const w = boot({ tab: 'tests' });
  deliver(w, snap({ acts: [rec({ state: 'done', end: iso(Date.now()), verdict: 'keep' })] }));
  const more = open(w, MERGE);
  const marks = (acts) => acts.map((a) => [a, act(more, a) && act(more, a).dataset.mark]);
  const now = ['judge', 'explain', 'run', 'flaky-back', 'flaky-off', 'close-done'];
  const iss = ['issue-speed', 'issue-split', 'issue-merge', 'issue-delete'];
  assert.deepEqual(marks(now), now.map((a) => [a, 'now']));
  assert.deepEqual(marks(iss), iss.map((a) => [a, 'issue']));
  assert.match(act(more, 'judge').textContent, /^Judge this test now$/);
  assert.match(act(more, 'issue-speed').textContent, /^File an issue: speed up issue$/);
  assert.equal(act(rowOf(w, MERGE), 'open').dataset.mark, undefined, 'the name opens a view: no mark');
  assert.equal(act(resultRow(w, ID1), 'view').dataset.mark, undefined, 'View opens a view: no mark');
  assert.match(model(w).querySelector('.tests-legend').textContent, /"now": the action runs now .* files no issue\. "issue": the action files an issue, because it changes code\. A button with no mark opens a view\./);
});

// Bug it guards (#652): the page is drawn whole at each snapshot; a row's name or an action button drawn anew between
// its press and its release lost the click (the browser gives it to the element pressed, then gone), so the row did not
// open or the action did not start. Pressed, the button stays through a snapshot, which is drawn after the click.
test('Tests actions: a snapshot that comes while a row\'s name or an action is pressed keeps the button, and the click works', async () => {
  const w = boot({ tab: 'tests' });
  deliver(w, snap());
  w.reply = reply(ID1);
  // Each snapshot reads the build machine's load anew.
  const loaded = (load) => { const d = snap(); d.panels.tests.data.machine.load = load; return d; };
  const press = (b, load) => {
    const renders = tp(w).dataset.renders;
    b.dispatchEvent(new w.MouseEvent('pointerdown', { bubbles: true }));
    next(w, loaded(load));
    assert.notEqual(tp(w).dataset.renders, renders, 'the snapshot came while it was pressed');
    assert.ok(b.isConnected, 'the button pressed is still on the page');
    b.dispatchEvent(new w.MouseEvent('pointerup', { bubbles: true }));
    b.click();
  };
  press(act(rowOf(w, MERGE), 'open'), 20);
  assert.ok(opened(w, MERGE), 'the row opened');
  press(act(opened(w, MERGE), 'judge'), 21);
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'testaction', args: ['judge', MERGE], repo: 'sample' } }]);
  // The snapshot held is drawn after the release; then each draws at once again.
  later(w);
  assert.match(tp(w).textContent, /load now 21/);
  const row = rowOf(w, MERGE);
  next(w, loaded(22));
  assert.match(tp(w).textContent, /load now 22/);
  assert.ok(!row.isConnected && opened(w, MERGE), 'drawn anew, the row still open');
});

// Bug it guards: Judge that sent nothing, or another file, or a row that showed nothing until the next snapshot.
test('Tests actions: Judge this test posts the engine action with the file; the row then shows the bar and the box', async () => {
  const w = boot({ tab: 'tests' });
  deliver(w, snap());
  w.reply = reply(ID1);
  act(open(w, MERGE), 'judge').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'testaction', args: ['judge', MERGE], repo: 'sample' } }]);
  const more = opened(w, MERGE), box = more.querySelector('.tests-box');
  assert.ok(box && box.querySelector('progress.tests-progress'), 'the bar shows');
  assert.equal(box.querySelector('progress').max, 900, 'against the time limit');
  assert.match(box.textContent, /Judge this test.*0:00 of the 15:00 time limit/);
  assert.match(box.querySelector('.tests-out').textContent, /Its text shows here as it comes/);
  assert.match(said(w), /Started: Judge this test, conveyor\/tests\/merge\.test\.sh/);
});

// Bug it guards (#571): Run this file showed the session time limit (testActionTimeout, 15:00) in its box and in
// Results of actions; a run is cut at the test run's limit (testTimeout), which its record carries, else none shows.
test('Tests actions: a running Run this file shows its own record\'s limit, never the session limit', () => {
  const w = boot({ tab: 'tests' });
  const run = { action: 'run', cli: undefined, model: undefined, effort: undefined };
  deliver(w, snap({ acts: [rec({ ...run, limit: 3600 })] }));
  assert.match(open(w, MERGE).querySelector('.tests-box').textContent, /Run this file.*of the 60:00 time limit/);
  assert.equal(opened(w, MERGE).querySelector('progress').max, 3600);
  assert.match(resultRow(w, ID1).textContent, /engine command, no session · Runs: \d+:\d\d of 60:00/);
  next(w, snap({ acts: [rec({ ...run, limit: null })], at: T0 + 60000 }));
  assert.doesNotMatch(opened(w, MERGE).querySelector('.tests-box').textContent, /time limit/);
  assert.match(opened(w, MERGE).querySelector('.tests-box').textContent, /\d+:\d\d used/);
  assert.doesNotMatch(resultRow(w, ID1).textContent, /15:00/);
});

// Bug it guards: text that showed only at the end, or a long text whose start was lost when the snapshot sent only
// its end (textCut).
test('Tests actions: new text in the snapshot shows in the box and the text before it stays', () => {
  const w = boot({ tab: 'tests' });
  deliver(w, snap({ acts: [rec({ text: 'line one\nline two\n' })] }));
  assert.equal(open(w, MERGE).querySelector('.tests-out').textContent, 'line one\nline two\n');
  next(w, snap({ acts: [rec({ text: 'line two\nline three\n', textCut: true })], at: T0 + 60000 }));
  assert.equal(opened(w, MERGE).querySelector('.tests-out').textContent, 'line one\nline two\nline three\n');
});

// Bug it guards: a Stop that stopped every action, or one of another file; a Copy that copied nothing.
test('Tests actions: Stop posts the stop of that action alone; Copy puts the box text on the clipboard', async () => {
  const w = boot({ tab: 'tests' });
  const copied = [];
  Object.defineProperty(w.navigator, 'clipboard', { value: { writeText: (t) => { copied.push(t); return Promise.resolve(); } } });
  deliver(w, snap({ acts: [rec(), rec({ id: ID2, file: X, action: 'explain', text: 'other text' })] }));
  const box = open(w, MERGE).querySelector('.tests-box');
  assert.equal(box.dataset.id, ID1);
  act(box, 'stop').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'testaction', args: ['stop', ID1], repo: 'sample' } }]);
  act(opened(w, MERGE).querySelector('.tests-box'), 'copy').click();
  await settle();
  assert.deepEqual(copied, ['first words\n']);
  assert.equal(said(w), 'Copied.');
});

// Bug it guards: a result shown with no time, CLI, model or effort, a verdict lost, or a result gone at the next render.
test('Tests actions: an ended judge shows its result with time, CLI, model, effort and verdict chip, and stays in Results of actions', () => {
  const w = boot({ tab: 'tests' });
  const end = Date.now(), done = rec({ state: 'done', start: iso(end - 125000), end: iso(end), verdict: 'split', text: 'Split it.\nVERDICT: split\n' });
  deliver(w, snap({ acts: [done] }));
  const box = open(w, MERGE).querySelector('.tests-box');
  assert.match(box.querySelector('.tests-result').textContent, /^Done in 2:05 · .+ · claude · claude-sonnet-5-5 · medium$/);
  assert.equal(box.querySelector('.chip-warn').textContent, 'split', 'the verdict word as a chip');
  assert.equal(box.querySelector('progress'), null, 'no bar once it ended');
  for (const at of [T0 + 60000, T0 + 120000]) {
    next(w, snap({ acts: [done], at }));
    const r = resultRow(w, ID1);
    assert.ok(r, 'kept in Results of actions');
    assert.match(r.textContent, /Judge this test.*merge\.test\.sh.*Done in 2:05 · .+ · claude · claude-sonnet-5-5 · medium.*split.*View.*Copy/);
  }
  act(resultRow(w, ID1), 'view').click();
  assert.equal(resultRow(w, ID1).querySelector('.tests-out').textContent, 'Split it.\nVERDICT: split\n', 'View shows its text');
});

// Bug it guards: a model typed under Other… that was never sent, or a Cancel that kept the pick.
test('Tests actions: the Tests model: Other… shows a text field and Save posts CLI, the typed model and effort; Cancel puts back the one in force', async () => {
  const w = boot({ tab: 'tests' });
  deliver(w, snap());
  // Cancel: the one in force again, nothing sent.
  pick(act(model(w), 'tmodel-cli'), 'codex');
  assert.ok(!act(model(w), 'tmodel-cancel').hidden && act(model(w), 'tmodel-cli').value === 'codex');
  act(model(w), 'tmodel-cancel').click();
  assert.deepEqual([act(model(w), 'tmodel-cli').value, act(model(w), 'tmodel-model').value, act(model(w), 'tmodel-effort').value], ['claude', 'claude-sonnet-5-5', 'medium']);
  assert.ok(act(model(w), 'tmodel-save').hidden);
  pick(act(model(w), 'tmodel-model'), '*other');
  const other = act(model(w), 'tmodel-model-other');
  assert.ok(other, 'Other… shows a text field');
  type(other, 'claude-new-model');
  assert.ok(!act(model(w), 'tmodel-save').hidden && model(w).textContent.includes('Unsaved'));
  assert.deepEqual(w.posts, [], 'a pick sends nothing');
  act(model(w), 'tmodel-save').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'tests', args: ['claude', 'claude-new-model', 'medium'], repo: 'sample' } }]);
  assert.match(model(w).textContent, /In force: claude · claude-new-model · medium/);
  assert.ok(act(model(w), 'tmodel-save').hidden, 'saved: no longer Unsaved');
});

// The Tests model's snapshot with no Tests model in force, Claude Code's own models as given, and the pack allowing two.
function packSnap(models) {
  const d = snap({ model: null }), t = d.panels.tests.data;
  t.clis.claude.models = models;
  t.testActions.allowed = { claude: ['claude-opus-5-5', 'claude-sonnet-5-5'], opencode: [], codex: [] };
  return d;
}
const choices = (w) => Array.from(act(model(w), 'tmodel-model').options).map((o) => o.textContent);

// Bug it guards (#594): Claude Code lists no models on the host (models null), and the Tests model offered none, only a
// typed name; it offers the pack's models for that CLI, as the Rules tab does, and a pick saves as a typed name does.
test('Tests actions: the Tests model offers the pack\'s models for a CLI that lists none, and saves the one picked', async () => {
  const w = boot({ tab: 'tests' });
  deliver(w, packSnap(null));
  pick(act(model(w), 'tmodel-cli'), 'claude');
  assert.deepEqual(choices(w), ['Pick a model', 'claude-opus-5-5', 'claude-sonnet-5-5', 'Other…']);
  assert.equal(act(model(w), 'tmodel-model-other'), null, 'no typed name until Other… is picked');
  pick(act(model(w), 'tmodel-model'), 'claude-sonnet-5-5');
  pick(act(model(w), 'tmodel-effort'), 'medium');
  act(model(w), 'tmodel-save').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'tests', args: ['claude', 'claude-sonnet-5-5', 'medium'], repo: 'sample' } }]);
});

// Bug it guards: the pack's list put in place of, or beside, the models a CLI lists of its own.
test('Tests actions: the Tests model offers a CLI\'s own models, not the pack\'s, when it lists some', () => {
  const w = boot({ tab: 'tests' });
  deliver(w, packSnap(['m1']));
  pick(act(model(w), 'tmodel-cli'), 'claude');
  assert.deepEqual(choices(w), ['Pick a model', 'm1', 'Other…']);
});

// Bug it guards: a runner's flaky case that showed no Put back on its case file's row, as the row's file is not the
// name the entry holds; or one that showed on another file's row. The snapshot's files name the files it counts for.
test('Tests actions: Put back shows a runner-named flaky case on its case file alone, and closes its flaky issue', async () => {
  const w = boot({ tab: 'tests' });
  deliver(w, snap());
  assert.equal(act(open(w, X), 'flaky-back'), null, 'not on a file the case does not count for');
  const b = act(open(w, MERGE), 'flaky-back');
  assert.match(b.textContent, /^Put back a flaky case: mergeclean now$/);
  b.click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'test-close', repo: 'sample',
    args: ['490', 'Put back from the Board\'s Tests page: the case "mergeclean" runs on card test steps again.'] } }]);
});

// Bug it guards: Keep off on an engine case file recorded the case file, while a card's run reads the cases kept off
// only under the runner's name (.conveyor/test-changed.sh): the case still ran. Any other file keeps its own name.
for (const [file, entry] of [[MERGE, 'conveyor/conveyor.test.sh: mergeclean'], [X, `${X}: mergeclean`]]) {
  test(`Tests actions: Keep a case off of ${file} records ${entry}`, async () => {
    const w = boot({ tab: 'tests' });
    deliver(w, snap());
    act(open(w, file), 'flaky-off').click();
    type(act(opened(w, file), 'keep-case'), 'mergeclean');
    type(act(opened(w, file), 'keep-why'), 'fails one run in ten');
    act(opened(w, file), 'keep-confirm').click();
    await settle();
    assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'flaky-off', args: [entry, 'fails one run in ten'], repo: 'sample' } }]);
  });
}
