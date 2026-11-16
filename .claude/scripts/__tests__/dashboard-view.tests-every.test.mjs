// SPDX-License-Identifier: Apache-2.0
// The Tests page lists every test file (issue 34): a file a card ran, a whole-only file that only a whole-suite run
// ran, and a file never run; its Last run took column, its sortable columns and its search box. Shared setup:
// dashboard-view.helpers.mjs; the tests part is the one the engine makes for such a project (testfiles.test.sh,
// tfrunner).
import assert from 'node:assert/strict';
import { P, TESTS, T0, clone, boot, deliver, full, act, panel, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const tp = (w) => panel(w, 'tests');
const CARD = 'lib/c.test.sh', WHOLE = 'conveyor/conveyor.test.sh', NEVER = 'lib/n.test.sh';
const at = (h) => new Date(T0 - h * 3600000).toISOString();
// CARD: one card run, flaky (so it needs a look and comes first with no sort), 2 CPU s in 600 s of clock. WHOLE:
// wholeOnly and slow on purpose, one whole-suite run that failed, 400 CPU s in 487 s. NEVER: no run, flaky (it needs a
// look, yet comes last: it has no time) and with issue #77. The snapshot's order: highest CPU s first.
const file = (o) => ({ cpu: null, median: null, change: null, runs: [], lastRun: null, timedRuns: 0, wholeOnly: false, failedSteps: 0, flaky: 0,
  issue: null, budget: 8, budgetFrom: 'project', slowOnPurpose: null, over: false, usual: null, slower: false, ...o });
const PART = { ...clone(TESTS), settings: { ...clone(TESTS.settings), files: { [WHOLE]: { wholeOnly: true, slowOnPurpose: 'runs every engine case' } } }, slower: [],
  totals: { files: 2, overBudget: 0, slower: 0, steps: { count: 1, waitSec: 0, runSec: 600 } },
  files: [
    file({ file: WHOLE, cpu: 400, median: 400, change: 0, wholeOnly: true, timedRuns: 1, over: true, slowOnPurpose: 'runs every engine case',
      runs: [{ cpu: 400, sec: 487, card: null, time: at(2), whole: true, result: 'fail', issue: null, repo: 'sample', url: null }],
      lastRun: { sec: 487, cpu: 400, clockPerCpu: 1.218, time: at(2), whole: true } }),
    file({ file: CARD, cpu: 2, median: 2, change: 0, timedRuns: 1, flaky: 1,
      runs: [{ cpu: 2, sec: 600, card: 'c-12', time: at(1), whole: false, issue: 12, repo: 'sample', url: `${P}/12` }],
      lastRun: { sec: 600, cpu: 2, clockPerCpu: 300, time: at(1), whole: false } }),
    file({ file: NEVER, flaky: 1, issue: 77 }),
  ] };
const show = () => { const w = boot({ tab: 'tests' }); const d = full(); d.panels.tests.data.tests = clone(PART); deliver(w, d); return w; };
const rows = (w) => Array.from(tp(w).querySelectorAll('.tests-row'));
const names = (w) => rows(w).map((r) => r.dataset.file);
const cells = (r) => Array.from(r.children, (td) => td.textContent);
const rowOf = (w, f) => rows(w).find((r) => r.dataset.file === f);
const head = (w, key) => act(tp(w), `sort-${key}`);
const search = (w, v) => { const s = act(tp(w), 'search'); s.value = v; s.dispatchEvent(new s.ownerDocument.defaultView.Event('input')); };

// Bug: the page listed only the files a card had timed, so conveyor/conveyor.test.sh (wholeOnly) and a file never run
// were missing, and a whole-suite run of a file showed nowhere.
test('Tests: every test file has a row: the card run, the whole-only file with its chip and whole-suite run, the never-run file', () => {
  const w = show();
  assert.deepEqual(names(w), [CARD, WHOLE, NEVER], 'with no sort: the file that needs a look first, then the snapshot\'s order; the file never timed last');
  assert.match(cells(rowOf(w, WHOLE)).at(-1), /Whole suite only/);
  assert.doesNotMatch(cells(rowOf(w, CARD)).at(-1), /Whole suite only|Never run/);
  // Bug (issue 73): a file never timed showed 0.0, dashes and 0 s, as if it had a time of none.
  assert.deepEqual(cells(rowOf(w, NEVER)).slice(1), ['Not timed yet', 'Flaky#77Never run'], 'one cell in place of its figures');
  // Bug (issue 73): "Has an issue" was a chip with no way to the issue.
  const link = rowOf(w, NEVER).querySelector('a.issue');
  assert.deepEqual([link.textContent, link.getAttribute('href')], ['#77', `${P}/77`]);
  act(rowOf(w, WHOLE), 'open').click();
  const more = Array.from(tp(w).querySelectorAll('.tests-open')).find((r) => r.dataset.file === WHOLE);
  assert.match(more.textContent, /runs only in whole-suite runs/);
  assert.match(more.querySelector('.tests-run').textContent, /^400\.0 CPU s · 487\.0 s on the clock · whole suite, failed · /);
  assert.equal(more.querySelector('.tests-run a.issue'), null, 'a whole-suite run links no card');
});

// Bug: conveyor/conveyor.test.sh, a runner (wholeOnly) whose CPU is the sum of its case files', showed Over budget for
// ever and offered "File an issue: speed up", an issue no change can meet. WHOLE here is as the engine now gives such
// a file (testfiles.test.sh, tfslower): not slow on purpose, 900 CPU s, no budget; its last run took 3 times its
// CPU time on the clock, which the Board would show as Waits.
test('Tests: a wholeOnly runner has "Runs other test files" in place of a budget, no Over budget or Waits, and no speed-up action', () => {
  const part = clone(PART);
  part.settings.files[WHOLE] = { wholeOnly: true };
  Object.assign(part.files[0], { cpu: 900, median: 900, slowOnPurpose: null, budget: null, budgetFrom: null, over: false, slower: false,
    lastRun: { ...part.files[0].lastRun, cpu: 900, sec: 2700, clockPerCpu: 3 } });
  const w = boot({ tab: 'tests' }), d = full(); d.panels.tests.data.tests = part; deliver(w, d);
  const chips = cells(rowOf(w, WHOLE)).at(-1);
  assert.match(chips, /Runs other test files/);
  assert.doesNotMatch(chips, /Over budget|Slower than usual|Waits|Slow on purpose/);
  assert.doesNotMatch(cells(rowOf(w, CARD)).at(-1), /Runs other test files/);
  act(rowOf(w, WHOLE), 'open').click();
  const more = Array.from(tp(w).querySelectorAll('.tests-open')).find((r) => r.dataset.file === WHOLE);
  assert.match(more.textContent, /Budget: none, it runs other test files/);
  // No Optimize issue for a runner (#100: a click says why on its row, rather than a disabled button that does nothing).
  act(more, 'optimize').click();
  const shut = Array.from(tp(w).querySelectorAll('.tests-open')).find((r) => r.dataset.file === WHOLE);
  assert.equal(act(shut, 'issue-title'), null, 'no Optimize issue for a runner');
  assert.match(shut.querySelector('.tests-note-line').textContent, /^Optimize: Not done: It runs other test files, and each of them has its own budget\.$/);
  // Bug: the budget editor saved a budget for the runner and said "budget of ... now 8 CPU s", which never applies.
  assert.equal(act(shut, 'file-budget-field'), null, 'no budget editor for a runner');
  assert.equal(act(shut, 'slow-mark-field'), null, 'no slow-on-purpose mark for a runner');
  act(shut, 'more').click();
  const menu = Array.from(tp(w).querySelectorAll('.tests-open')).find((r) => r.dataset.file === WHOLE);
  assert.deepEqual(['menu-budget', 'menu-mark'].map((a) => act(menu, a).disabled), [true, true], 'nor from its More menu');
  act(rowOf(w, CARD), 'open').click();
  const card = Array.from(tp(w).querySelectorAll('.tests-open')).find((r) => r.dataset.file === CARD);
  act(card, 'optimize').click();
  assert.ok(act(tp(w), 'issue-title'), 'a file with a budget keeps its Optimize');
});

// The clock time of the newest run, card or whole suite, and when it ran on hover.
test('Tests: Last run took shows each file\'s newest run\'s clock time, with its date and time on hover', () => {
  const w = show();
  assert.deepEqual(rows(w).slice(0, 2).map((r) => cells(r)[7]), ['10 min 0 s', '8 min 7 s']);
  const took = rowOf(w, WHOLE).children[7];
  assert.equal(took.title, `${new Date(at(2)).toLocaleString()}, whole suite`);
});

test('Tests: a column heading sorts the rows, a second click reverses them, and an arrow shows the sort', () => {
  const w = show();
  assert.equal(head(w, 'cpu').closest('th').getAttribute('aria-sort'), 'none');
  head(w, 'cpu').click();
  assert.deepEqual(names(w), [WHOLE, CARD, NEVER], 'CPU s, highest first; a file with none last');
  assert.equal(head(w, 'cpu').textContent, 'CPU s now ▼');
  assert.equal(head(w, 'cpu').closest('th').getAttribute('aria-sort'), 'descending');
  head(w, 'cpu').click();
  assert.deepEqual(names(w), [CARD, WHOLE, NEVER], 'lowest first');
  assert.equal(head(w, 'cpu').textContent, 'CPU s now ▲');
  head(w, 'took').click();
  assert.deepEqual(names(w), [CARD, WHOLE, NEVER], 'Last run took, longest first (600 s, 487 s)');
  assert.equal(head(w, 'cpu').textContent, 'CPU s now', 'only the sorted column has an arrow');
  head(w, 'took').click();
  assert.deepEqual(names(w), [WHOLE, CARD, NEVER]);
  head(w, 'file').click();
  assert.deepEqual(names(w), [WHOLE, CARD, NEVER], 'file names A to Z');
  head(w, 'file').click();
  assert.deepEqual(names(w), [NEVER, CARD, WHOLE], 'Z to A');
});

test('Tests: the search box keeps the rows whose path holds its text, with the filter chip, and says when none match', () => {
  const w = show();
  search(w, 'LIB/');
  assert.deepEqual(names(w), [CARD, NEVER], 'any part of the path, in any case');
  Array.from(tp(w).querySelectorAll('[data-act="filter"]')).find((b) => b.dataset.filter === 'never').click();
  assert.deepEqual(names(w), [NEVER], 'the chip and the search together');
  search(w, 'conveyor');
  assert.deepEqual(names(w), []);
  assert.equal(tp(w).querySelector('.tests-table tbody').textContent, 'No test file matches');
  search(w, 'zzz');
  assert.equal(tp(w).querySelector('.tests-table tbody').textContent, 'No test file matches');
  search(w, '');
  assert.deepEqual(names(w), [NEVER]);
});
