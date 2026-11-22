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
function show({ acts = [], waits = WAITS, whole = null } = {}) {
  const d = snap({ acts }), files = d.panels.tests.data.tests.files, of = (f) => files.find((x) => x.file === f);
  of(X).hollow = HOLLOW;
  if (whole) of(whole).wholeOnly = true;
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
  assert.match(body, /\n## Done when\n- The judge's hollow check of the changed file, run by the card's check on a model of another family than the builder's where one is set up, names no hollow case among the cases above and the cases the change adds or changes\.\n- Each deleted case has its COVERED-BY line, naming a test file that is kept\.$/);
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
  assert.match(body, /\n## Done when\n- The file succeeds in 3 runs in a row alone on a test slot, and each run takes at most 2 times its CPU seconds on the clock\.$/);
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
  assert.match(body, /\n## Done when\n- The card's test step runs this file, and it succeeds\.$/);
  [title, body] = preview(w, NEVER, 'delete-file');
  assert.equal(title, `Delete the test file ${NEVER}`);
  assert.match(body, /COVERED-BY: <test file>: <its case>/);
  assert.match(body, /\n## Done when\n- The file is deleted, and each of its cases that matters has a COVERED-BY line naming a test that proves it\.$/);
  [, body] = preview(w, SKIPPED, 'make-run');
  assert.match(body, /The engine cannot tell why\./);
});

// Bug it guards (issue 1430): a tracked file whose runs are all before the history start has no runs since it, so it
// showed Never run and offered Make it run and Delete it, though it has runs on record (the engine's everRun).
test('Tests fixes: a file run only before the history start is not Never run, and offers no Make it run or Delete it', () => {
  const OLD = 'tests/old.test.sh', d = snap();
  Object.assign(d.panels.tests.data.tests.settings, { historyStart: iso(Date.now() - 3600000) });
  d.panels.tests.data.tests.files.push({ ...never(OLD, null), everRun: true });
  const w = boot({ tab: 'tests' });
  deliver(w, d);
  assert.doesNotMatch(status(w, OLD).textContent, /Never run/);
  const more = open(w, OLD);
  assert.deepEqual([act(more, 'make-run'), act(more, 'delete-file')], [null, null]);
});

// Bug it guards (#778): a judge found that merge.test.sh checks what it protects through a proxy (the verdict
// indirect, with a DIRECT line), and its row still suggested Run, with no way to file the rewrite. Rewrite as a direct
// check is the one primary step; its preview's title is the one the engine checks as an Optimize card (REWRITE,
// speedproof.sh optproof()), its body the DIRECT line as that check reads it, and filing it posts one test-issue. Bug it guards too:
// a runner (wholeOnly, here X) with the verdict indirect was offered the rewrite, whose card's check times the file
// alone, which a card's Test step never does for a runner, so that card was always refused.
test('Tests fixes: an indirect verdict makes Rewrite as a direct check the primary step, its preview holding the file and its DIRECT lines', async () => {
  const direct = [{ protects: 'the install holds the right files', check: 'compare the installed list with the manifest', cases: ['relfiles', 'relpins'] }];
  const done = { state: 'done', end: iso(Date.now()), verdict: 'indirect', direct, text: 'It runs the suite again.\nVERDICT: indirect\n' };
  const w = show({ acts: [rec(done), rec({ ...done, id: 'judge-x', file: X })], whole: X });
  assert.equal(act(open(w, SKIPPED), 'rewrite-direct'), null, 'a file with no indirect verdict has no Rewrite as a direct check');
  assert.equal(act(open(w, X), 'rewrite-direct'), null, 'a runner with the verdict indirect has no Rewrite as a direct check');
  assert.ok(act(opened(w, X), 'make-alone'), 'a runner with the verdict indirect keeps Make it run alone');
  const steps = open(w, MERGE).querySelector('.tests-steps');
  assert.deepEqual(Array.from(steps.querySelectorAll('.btn-primary'), (b) => b.textContent), ['Rewrite as a direct check']);
  const [title, body] = preview(w, MERGE, 'rewrite-direct');
  assert.equal(title, `Rewrite the test file ${MERGE} as direct checks`);
  assert.match(body, /\nIts proxy parts \(what it protects \| the direct check \| the cases that must keep passing\):\n- DIRECT: the install holds the right files \| compare the installed list with the manifest \| relfiles, relpins\n/);
  assert.match(body, /\n- Last runs, newest first: 12\.0 CPU s \(card #509\), /);
  assert.match(body, /\nThe judge's verdict \(.+\): indirect\.\n/);
  w.reply = TA.reply('https://github.com/example/sample/issues/702');
  act(opened(w, MERGE), 'issue-file').click();
  await settle();
  assert.deepEqual(w.posts.splice(0).map((p) => [p.body.action, p.body.args[0], p.body.args[1], p.body.args[2]]), [['test-issue', MERGE, title, body]]);
  assert.match(opened(w, MERGE).textContent, /Rewrite as a direct check: Filed: https:\/\/github\.com\/example\/sample\/issues\/702/);
});

// Bug it guards (#827): a judge's check text held a | (control rules P3=off | on), the draft wrote it as it was, and
// the card's check, which splits a DIRECT line at |, read the words after it as cases the file must keep. The draft
// writes a | inside a field as /, so its DIRECT line has exactly three fields.
test('Tests fixes: Rewrite as a direct check writes a | inside a DIRECT field as /, so the line keeps three fields', () => {
  const direct = [{ protects: 'the stop is clean', check: 'control rules P3=off | on', cases: ['relstop'] }];
  const w = show({ acts: [rec({ state: 'done', end: iso(Date.now()), verdict: 'indirect', direct, text: 'VERDICT: indirect\n' })] });
  const line = preview(w, MERGE, 'rewrite-direct')[1].split('\n').find((l) => l.startsWith('- DIRECT: '));
  assert.equal(line, '- DIRECT: the stop is clean | control rules P3=off / on | relstop');
  assert.equal(line.split('|').length, 3);
});

// Bug it guards (#1384, R7): a judge report with more DIRECT lines than the body held was cut to '- and N more', and
// the card's check, which reads only the DIRECT lines in the issue, never asked or checked the parts cut off. The
// draft keeps every DIRECT line (the verdict line goes first); one that cannot hold them all is not made. Bug it
// guards too: dropping the runs line made the card's check hold the file to its old median, not its recent runs
// (recentcpu() and slowestrun(), lib/speedproof.sh read the "Last runs, newest first" line).
const parts = (n) => Array.from({ length: n }, (_, i) => ({ protects: `the part ${i} of the install holds its files`, check: `compare list ${i} with the manifest`, cases: [`relpart${i}`] }));
const indirect = (n) => show({ acts: [rec({ state: 'done', end: iso(Date.now()), verdict: 'indirect', direct: parts(n), text: 'VERDICT: indirect\n' })] });
test('Tests fixes: Rewrite as a direct check past the body limit keeps every DIRECT line and the runs line, dropping the verdict line', () => {
  // 18 DIRECT lines: past the limit with the runs and verdict lines, inside it with the runs line alone.
  const body = preview(indirect(18), MERGE, 'rewrite-direct')[1];
  assert.ok(body.length <= 2500, `the body fits the limit: ${body.length}`);
  assert.equal(body.split('\n').filter((l) => l.startsWith('- DIRECT: ')).length, 18, `every DIRECT line is in the body:\n${body}`);
  assert.ok(!/- and \d+ more/.test(body), `no DIRECT line is cut:\n${body}`);
  assert.match(body, /\n- Last runs, newest first: \d/, `the runs line, which the card's CPU limit comes from, stays:\n${body}`);
  assert.ok(!body.includes("The judge's verdict ("), `the verdict line went to make room:\n${body}`);
});
test('Tests fixes: Rewrite as a direct check whose DIRECT lines alone go over the body limit makes no draft and says why', async () => {
  const w = indirect(40);
  act(open(w, MERGE), 'rewrite-direct').click();
  await settle();
  const more = opened(w, MERGE);
  assert.equal(act(more, 'issue-body'), null, 'no preview opens');
  assert.match(more.textContent, /Not drafted: the judge's 40 proxy parts \(DIRECT lines\) do not fit in one issue of 2500 characters/);
  assert.deepEqual(w.posts, [], 'nothing is sent');
});

// Bug it guards (#768): the owner could not ask for a test file to be split. More has Split it, whose preview is titled
// "Split the test file <file>" and says how to split it; File posts one test-issue with that title and the body as the
// owner edited it. Bug it guards too: a runner (wholeOnly, here X) is the sum of other test files, so splitting it
// splits nothing; its Split it is disabled, with why.
test('Tests fixes: Split it under More previews the split issue and files the edited body; a runner has it disabled', async () => {
  const w = show({ whole: X });
  act(open(w, X), 'more').click();
  const off = act(opened(w, X), 'split');
  assert.equal(off.getAttribute('aria-disabled'), 'true', 'a runner\'s Split it is disabled');
  assert.equal(off.title, 'It runs other test files: split one of those, not the runner.');
  // Bug it guards (issue 1430): the item was :disabled with its reason in its title alone, so the arrow keys skipped it
  // and a keyboard user never heard why. It stays in the arrow keys' round, its reason its description, shown under the menu.
  const why = w.document.getElementById(off.getAttribute('aria-describedby'));
  assert.equal(why && why.textContent, 'Split it: It runs other test files: split one of those, not the runner.');
  const items = Array.from(opened(w, X).querySelectorAll('[role="menuitem"]')), before = items[items.indexOf(off) - 1];
  before.focus();
  before.dispatchEvent(new w.KeyboardEvent('keydown', { key: 'ArrowDown', bubbles: true, cancelable: true }));
  assert.equal(w.document.activeElement, off, 'ArrowDown reaches the disabled Split it');
  off.click();
  assert.deepEqual([act(opened(w, X), 'issue-title'), w.posts.length], [null, 0], 'a click on it does nothing');
  act(open(w, MERGE), 'more').click();
  act(opened(w, MERGE), 'split').click();
  const more = opened(w, MERGE);
  assert.equal(act(more, 'issue-title').value, `Split the test file ${MERGE}`);
  const body = act(more, 'issue-body').value;
  assert.match(body, /^Split this test file into two or more test files of the same area\. Keep each of its cases once, and unchanged\.\n/);
  assert.match(body, /\n## Done when\n- Each case of the file is in exactly one of the new test files, unchanged\.\n- Each new test file is under 600 lines\.\n- \.conveyor\/engine-areas\.json and the test map name the new test files\.$/);
  assert.doesNotMatch(body, /verdict/, 'with no split verdict, no judge\'s reason');
  TA.type(act(more, 'issue-body'), `${body}\nKeep the fixtures in one helper.`);
  w.reply = TA.reply('https://github.com/example/sample/issues/703');
  act(opened(w, MERGE), 'issue-file').click();
  await settle();
  assert.deepEqual(w.posts.splice(0).map((p) => [p.body.action, p.body.args[0], p.body.args[1], p.body.args[2]]),
    [['test-issue', MERGE, `Split the test file ${MERGE}`, `${body}\nKeep the fixtures in one helper.`]]);
  assert.match(opened(w, MERGE).textContent, /Split it: Filed: https:\/\/github\.com\/example\/sample\/issues\/703/);
});

// Bug it guards (#768): the judge's newest verdict split was a verdict no action acted on, and its row still suggested
// Run. Split it is then the one primary step (and so not in More too), and its preview names the judge's reason.
test('Tests fixes: the newest verdict split makes Split it the primary step, its preview holding the judge\'s reason', () => {
  const w = show({ acts: [rec({ state: 'done', end: iso(Date.now()), verdict: 'split', text: 'Its cases test two unrelated features.\nVERDICT: split\n' })] });
  const steps = open(w, MERGE).querySelector('.tests-steps');
  assert.deepEqual(Array.from(steps.querySelectorAll('.btn-primary'), (b) => b.textContent), ['Split it']);
  act(opened(w, MERGE), 'more').click();
  assert.equal(opened(w, MERGE).querySelector('[role="menu"] [data-act="split"]'), null, 'not in More while it is the step');
  act(opened(w, MERGE), 'split').click();
  assert.equal(act(opened(w, MERGE), 'issue-title').value, `Split the test file ${MERGE}`);
  assert.match(act(opened(w, MERGE), 'issue-body').value, /\n\nThe judge's newest verdict is split: Its cases test two unrelated features\.\n/);
});
