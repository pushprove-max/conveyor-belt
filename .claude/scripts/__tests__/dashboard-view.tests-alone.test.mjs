// SPDX-License-Identifier: Apache-2.0
// The Tests page's Whole suite only and Wall only statuses (#190). A wholeOnly file says what a change to it costs (the
// newest whole-suite run's CPU seconds) and has Make it run alone, which opens the issue preview with the Done-when its
// card's check proves (aloneproof(), conveyor/lib/speedproof.sh). A Wall only file says why it has no CPU time, names its
// runner (the pack's test.report), and has Record CPU time where the engine can wrap the test command for it, else says
// why not. Shared setup: dashboard-view.helpers.mjs (TA.snap()).
import assert from 'node:assert/strict';
import { boot, deliver, settle, act, cases, TA } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const { MERGE, X, snap, rowOf, opened, open } = TA;
const WHOLE = 'conveyor/conveyor.test.sh', WALL = 'src/a.test.ts';
function show({ suite = { time: '2026-11-16T03:00:00Z', cpu: 812.4 }, report = { runner: 'vitest', format: 'jest-json', path: 'report.json' }, cpuTime = null } = {}) {
  const d = snap(), t = d.panels.tests.data.tests, base = t.files.find((x) => x.file === MERGE);
  t.suite = suite;
  t.settings.report = report;
  t.settings.cpuTime = cpuTime;
  t.files.push({ ...base, file: WHOLE, wholeOnly: true, slower: false, hollow: null, waits: null },
    { ...base, file: WALL, cpu: null, median: null, change: null, runs: [{ cpu: null, sec: 4.2, card: 'c1-509', time: d.updatedAt, issue: 509 }],
      lastRun: { sec: 4.2, cpu: null, clockPerCpu: null }, timedRuns: 0, hollow: null, waits: null });
  const w = boot({ tab: 'tests' });
  deliver(w, d);
  return w;
}
const status = (w, f) => rowOf(w, f).lastElementChild;

// Bug it guards (#190): a Whole suite only file named its status with no cost and no way out. Its row says a change to
// it is tested only by a whole-suite run, with that run's CPU seconds; Make it run alone previews the issue whose title
// the engine knows (MAKERUN + ALONEFIX) and whose Done-when its check proves, and filing it posts one test-issue.
test('Tests alone: a wholeOnly file says its cost, and Make it run alone previews and files its issue', async () => {
  const w = show();
  assert.equal(status(w, WHOLE).querySelector('.tests-whole-cost').textContent,
    'A change to it is tested only by a whole-suite run: 812.4 CPU s for the newest whole-suite run on record.');
  assert.equal(status(w, MERGE).querySelector('.tests-whole-cost'), null, 'a file a card runs has no such cost');
  assert.equal(act(open(w, MERGE), 'make-alone'), null, 'a file a card runs has no Make it run alone');
  act(open(w, WHOLE), 'make-alone').click();
  const more = opened(w, WHOLE), title = act(more, 'issue-title').value, body = act(more, 'issue-body').value;
  assert.equal(title, `Make the test file ${WHOLE} run alone`);
  assert.match(body, /^This test file runs only in whole-suite runs: the pack marks it wholeOnly/);
  assert.match(body, /\nA change to it is tested only by a whole-suite run: 812\.4 CPU s/);
  assert.match(body, /or move what it runs into test files the runner can list\. Keep what it tests\./);
  assert.match(body, /\nDone when:\n- The card's check runs the file alone through the pack's test list \(test\.list\), and it exits 0\..*\n- The pack no longer marks the file wholeOnly\.$/);
  w.reply = TA.reply('https://github.com/example/sample/issues/702');
  act(opened(w, WHOLE), 'issue-file').click();
  await settle();
  assert.deepEqual(w.posts.splice(0).map((p) => [p.body.action, p.body.args[0], p.body.args[1]]), [['test-issue', WHOLE, title]]);
});

// Bug it guards (#190): with no whole-suite run on record the row showed no figure, or a made-up one. It says none is on record.
test('Tests alone: with no whole-suite run on record the cost says so', () => {
  assert.match(status(show({ suite: null }), WHOLE).querySelector('.tests-whole-cost').textContent, /no whole-suite run with CPU seconds is on record\.$/);
});

// Bug it guards (#190): a Wall only file did not say why it had no CPU time, and had no way to record it. Its row names
// its runner; where the engine's plan (settings.cpuTime) can wrap the test command for this file, Record CPU time shows
// the command now and as it will be saved, and only Save sends `test-settings cpu-time <file>`; a file with CPU time
// says nothing of it.
test('Tests alone: Record CPU time previews the wrapped test command and saves it', async () => {
  const cmd = `conveyor_cputime() { local o r; o=$(mktemp); "$CONVEYOR_TEST_TIME" ${WALL} -- vitest run ${WALL} "$@" > "$o" 2>&1; r=$?; }; conveyor_cputime`;
  const w = show({ cpuTime: { file: WALL, was: `vitest run ${WALL}`, command: cmd } });
  assert.match(status(w, WALL).querySelector('.tests-wall-why').textContent,
    /^No CPU time: its runner, vitest, gives clock time only in its report \(the pack's test\.report\)\. Record CPU time wraps the test command in conveyor\/tools\/testtime\.sh\.$/);
  assert.equal(status(w, X).querySelector('.tests-wall-why'), null, 'a file with CPU time has no such reason');
  assert.equal(act(open(w, X), 'record-cpu'), null, 'a file with CPU time has no Record CPU time');
  assert.match(open(w, WALL).textContent, /Wall only: no CPU time is on record\. Its last run took 4 s\. No CPU time: its runner, vitest/);
  act(open(w, WALL), 'record-cpu').click();
  const more = opened(w, WALL);
  assert.equal(act(more, 'cpu-was').textContent, `vitest run ${WALL}`);
  assert.equal(act(more, 'cpu-command').textContent, cmd);
  assert.match(more.textContent, /Proof: the next run of src\/a\.test\.ts records its CPU seconds, and Wall only clears\./);
  assert.deepEqual(w.posts, [], 'the preview sends nothing');
  w.reply = TA.reply('ok');
  act(opened(w, WALL), 'cpu-save').click();
  await settle();
  assert.deepEqual(w.posts.splice(0).map((p) => [p.body.action, ...p.body.args]), [['test-settings', 'cpu-time', WALL]]);
});

// Bug it guards (#190): where no wrapper can apply, a Record CPU time that cannot work was shown, or no reason was. The
// row gives the engine's reason, or the one file the test command runs, and no action.
test('Tests alone: a Wall only file the wrapper cannot time says why and has no action', () => {
  const w = show({ cpuTime: { why: 'No report option gives CPU time: the test command is given the test files of each card\'s change (test.list args).' } });
  assert.match(status(w, WALL).querySelector('.tests-wall-why').textContent, /No action: No report option gives CPU time: .*\(test\.list args\)\.$/);
  assert.equal(act(open(w, WALL), 'record-cpu'), null);
  assert.match(status(show({ cpuTime: { file: 'src/b.test.ts', was: 'x', command: 'y' } }), WALL).querySelector('.tests-wall-why').textContent,
    /No action: The wrapper conveyor\/tools\/testtime\.sh applies only to src\/b\.test\.ts, the one test file the test command runs\.$/);
});

// With no test.report, the clock time came from the test command's own TESTRUN sec line: the reason says that.
test('Tests alone: a Wall only file with no test.report blames the TESTRUN sec line', () => {
  assert.match(status(show({ report: null }), WALL).querySelector('.tests-wall-why').textContent,
    /^No CPU time: its test command gives a TESTRUN sec line with clock time only\. No action:/);
});
