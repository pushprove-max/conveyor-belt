// SPDX-License-Identifier: Apache-2.0
// The Tests page's other fix actions (#189): Fix hollow cases on a Hollow file, Fix the waiting on a file that Waits,
// and Make it run and Delete it on a file Never run, whose row says why it did not run. Each opens the issue preview
// with its evidence and the Done-when its card's check proves. Shared setup: dashboard-view.helpers.mjs (TA.snap():
// the three files of TESTS, with the Tests model; merge.test.sh waits, 2.5 times its CPU seconds on the clock).
import assert from 'node:assert/strict';
import { boot, deliver, settle, act, cases, iso, TA } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const { MERGE, X, rec, snap, rowOf, opened, open } = TA;
const NEVER = 'tests/never.test.sh', SKIPPED = 'tests/skipped.test.sh';
const HOLLOW = [{ case: 'loads', kind: 'no-assert', reason: 'no expect or assert call' }];
const WAITS = [{ case: 'mergewait', kind: 'polling', at: 'conveyor/tests/merge.test.sh:40', reason: 'it polls the lock file every second' }];
// A file with no run on record, as the snapshot's tests part has it, with why it never ran (null: the engine cannot tell).
const never = (file, neverRun) => ({ file, cpu: null, median: null, change: null, runs: [], lastRun: null, timedRuns: 0, runsOnRecord: 0, failedSteps: 0,
  failures: [], flaky: 0, issue: null, slowOnPurpose: null, usual: null, slower: false, hollow: null, waits: null, neverRun });
function show({ acts = [], waits = WAITS } = {}) {
  const d = snap({ acts }), files = d.panels.tests.data.tests.files, of = (f) => files.find((x) => x.file === f);
  of(X).hollow = HOLLOW;
  of(MERGE).waits = waits;
  files.push(never(NEVER, { kind: 'patterns', reason: 'the pack\'s tests.patterns do not match it' }), never(SKIPPED, null));
  const w = boot({ tab: 'tests' });
  deliver(w, d);
  return w;
}
const status = (w, f) => rowOf(w, f).lastElementChild;
const preview = (w, f, how) => { act(open(w, f), how).click(); const more = opened(w, f); return [act(more, 'issue-title').value, act(more, 'issue-body').value]; };

// Bug it guards (#189): a Hollow file named its problem with no way to resolve it. Fix hollow cases previews an issue
// that lists each case as a HOLLOW line (as the card's check reads them), asks to assert or delete with a COVERED-BY
// line, and holds the Done-when the check proves; filing it posts one test-issue with the title the engine knows.
test('Tests fixes: Fix hollow cases previews each case with its kind and reason, COVERED-BY and the Done-when, and files it', async () => {
  const w = show();
  assert.equal(act(open(w, MERGE), 'fix-hollow'), null, 'a file with no hollow case has no Fix hollow cases');
  const [title, body] = preview(w, X, 'fix-hollow');
  assert.equal(title, `Fix the hollow cases of the test file ${X}`);
  assert.match(body, /\nIts hollow cases \(case \| kind \| reason\):\n- HOLLOW: loads \| no-assert \| no expect or assert call\n/);
  assert.match(body, /COVERED-BY: <test file>: <its case> \| <the deleted case>/);
  assert.match(body, /\nDone when:\n- The judge's hollow check of the changed file, run by the card's check on a model of another family than the builder's where one is set up, names no hollow case\.\n- Each deleted case has its COVERED-BY line, naming a test file that is kept\.$/);
  w.reply = TA.reply('https://github.com/example/sample/issues/701');
  act(opened(w, X), 'issue-file').click();
  await settle();
  assert.deepEqual(w.posts.splice(0).map((p) => [p.body.action, p.body.args[0], p.body.args[1]]), [['test-issue', X, title]]);
  assert.match(opened(w, X).textContent, /Fix hollow cases: Filed: https:\/\/github\.com\/example\/sample\/issues\/701/);
});

// Bug it guards (#189): a fixed file stayed Hollow. Once a later judge names no hollow case, the status clears and
// Fix hollow cases is gone.
test('Tests fixes: a later judge that names no hollow case clears Hollow and its Fix hollow cases', () => {
  const w = show({ acts: [rec({ file: X, state: 'done', end: iso(Date.now()), verdict: 'keep', hollow: [] })] });
  assert.doesNotMatch(status(w, X).textContent, /Hollow/);
  assert.equal(act(open(w, X), 'fix-hollow'), null);
});

// Bug it guards (#189): a file marked Waits had no way to resolve it. Fix the waiting previews an issue with the clock
// and CPU of its recent runs and the WAIT lines its judge named, and the Done-when of the card's 3 runs.
test('Tests fixes: Fix the waiting previews the clock and CPU of its runs and its WAIT lines, with the Done-when', () => {
  const w = show();
  assert.equal(act(open(w, X), 'fix-waits'), null, 'a file that does not wait has no Fix the waiting');
  const [title, body] = preview(w, MERGE, 'fix-waits');
  assert.equal(title, `Fix the waiting of the test file ${MERGE}`);
  assert.match(body, /^This test file waits more than it works: its last run took 2\.5 times its CPU seconds on the clock\./);
  assert.match(body, /\nIts recent runs, newest first \(clock, CPU\):\n- 30\.0 s on the clock for 12\.0 CPU s \(2\.5×\), card #509\n- 14\.0 s on the clock for 11\.5 CPU s \(1\.2×\), card #451\n\n/);
  assert.match(body, /\nThe waits the judge named \(case \| kind \| file:line \| reason\):\n- WAIT: mergewait \| polling \| conveyor\/tests\/merge\.test\.sh:40 \| it polls the lock file every second\n/);
  assert.match(body, /\nDone when:\n- The file succeeds in 3 runs in a row alone on a test slot, and each run takes at most 2 times its CPU seconds on the clock\.$/);
});

// Bug it guards (#189): with no judge's WAIT lines the body showed an empty list. It says no wait is named yet.
test('Tests fixes: Fix the waiting with no WAIT lines says the judge named none', () => {
  const [, body] = preview(show({ waits: null }), MERGE, 'fix-waits');
  assert.match(body, /\nThe judge has named no wait of it yet: find the waits in the file/);
  assert.doesNotMatch(body, /WAIT:/);
});

// Bug it guards (#189): a file Never run gave no reason and no action. Its row says why when the engine can tell, and
// Make it run and Delete it preview their issues with that reason and their Done-when.
test('Tests fixes: a Never run file shows why in its row, and Make it run and Delete it preview their issues', () => {
  const w = show();
  assert.match(status(w, NEVER).textContent, /Never run/);
  assert.equal(status(w, NEVER).querySelector('.tests-never-why').textContent, 'Not run: the pack\'s tests.patterns do not match it');
  assert.equal(status(w, SKIPPED).querySelector('.tests-never-why'), null, 'no reason when the engine cannot tell');
  assert.equal(act(open(w, MERGE), 'make-run'), null, 'a file with runs has no Make it run');
  let [title, body] = preview(w, NEVER, 'make-run');
  assert.equal(title, `Make the test file ${NEVER} run`);
  assert.match(body, /Why, as the engine can tell: the pack's tests\.patterns do not match it\./);
  assert.match(body, /\nDone when:\n- The card's test step runs this file, and it succeeds\.$/);
  [title, body] = preview(w, NEVER, 'delete-file');
  assert.equal(title, `Delete the test file ${NEVER}`);
  assert.match(body, /COVERED-BY: <test file>: <its case>/);
  assert.match(body, /\nDone when:\n- The file is deleted, and each of its cases that matters has a COVERED-BY line naming a test that proves it\.$/);
  [, body] = preview(w, SKIPPED, 'make-run');
  assert.match(body, /The engine cannot tell why\./);
});
