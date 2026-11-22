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
// look, yet comes last: it has no time) and with issue #77. The snapshot's order: highest CPU s first. CARD defines
// the cases capwaittests and libcheck (its cases).
const file = (o) => ({ cpu: null, median: null, change: null, runs: [], lastRun: null, timedRuns: 0, wholeOnly: false, failedSteps: 0, flaky: 0,
  issue: null, slowOnPurpose: null, usual: null, slower: false, ...o });
const PART = { ...clone(TESTS), settings: { ...clone(TESTS.settings), files: { [WHOLE]: { wholeOnly: true, slowOnPurpose: 'runs every engine case' } } }, slower: [],
  totals: { files: 2, slower: 0, steps: { count: 1, waitSec: 0, runSec: 600 } },
  files: [
    file({ file: WHOLE, cpu: 400, median: 400, change: 0, wholeOnly: true, timedRuns: 1, slowOnPurpose: 'runs every engine case',
      runs: [{ cpu: 400, sec: 487, card: null, time: at(2), whole: true, result: 'fail', issue: null, repo: 'sample', url: null }],
      lastRun: { sec: 487, cpu: 400, clockPerCpu: 1.218, time: at(2), whole: true } }),
    file({ file: CARD, cpu: 2, median: 2, change: 0, timedRuns: 1, flaky: 1, cases: ['capwaittests', 'libcheck'],
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
  assert.equal(more.querySelector('.tests-run .tests-tl-what').textContent, '400.0 CPU s · 487.0 s on the clock · whole suite, failed');
  assert.equal(more.querySelector('.tests-run a.issue'), null, 'a whole-suite run links no card');
});

// Bug: conveyor/conveyor.test.sh, a runner (wholeOnly) whose CPU is the sum of its case files', was flagged for ever
// and offered "File an issue: speed up", an issue no change can meet. WHOLE here is as the engine now gives such a
// file (testfiles.test.sh, tfslower): not slow on purpose, 900 CPU s, not slower; its last run took 3 times its CPU
// time on the clock, which the Board would show as Waits.
test('Tests: a wholeOnly runner has "Runs other test files", no Slower than usual or Waits, and no speed-up action', () => {
  const part = clone(PART);
  part.settings.files[WHOLE] = { wholeOnly: true };
  Object.assign(part.files[0], { cpu: 900, median: 900, slowOnPurpose: null, slower: false,
    lastRun: { ...part.files[0].lastRun, cpu: 900, sec: 2700, clockPerCpu: 3 } });
  const w = boot({ tab: 'tests' }), d = full(); d.panels.tests.data.tests = part; deliver(w, d);
  const chips = cells(rowOf(w, WHOLE)).at(-1);
  assert.match(chips, /Runs other test files/);
  assert.doesNotMatch(chips, /budget|Slower than usual|Waits|Slow on purpose/i);
  assert.doesNotMatch(cells(rowOf(w, CARD)).at(-1), /Runs other test files/);
  act(rowOf(w, WHOLE), 'open').click();
  const more = Array.from(tp(w).querySelectorAll('.tests-open')).find((r) => r.dataset.file === WHOLE);
  assert.match(more.textContent, /It runs other test files, and each of them is timed on its own\./);
  // No Optimize issue for a runner (#100: a click says why on its row, rather than a disabled button that does nothing).
  act(more, 'optimize').click();
  const shut = Array.from(tp(w).querySelectorAll('.tests-open')).find((r) => r.dataset.file === WHOLE);
  assert.equal(act(shut, 'issue-title'), null, 'no Optimize issue for a runner');
  assert.match(shut.querySelector('.tests-note-line').textContent, /^Optimize: Not done: It runs other test files, and each of them is timed on its own\.$/);
  assert.equal(act(shut, 'slow-mark-field'), null, 'no slow-on-purpose mark for a runner');
  act(shut, 'more').click();
  const menu = Array.from(tp(w).querySelectorAll('.tests-open')).find((r) => r.dataset.file === WHOLE);
  assert.equal(act(menu, 'menu-mark').getAttribute('aria-disabled'), 'true', 'nor from its More menu');
  act(rowOf(w, CARD), 'open').click();
  const card = Array.from(tp(w).querySelectorAll('.tests-open')).find((r) => r.dataset.file === CARD);
  act(card, 'optimize').click();
  assert.ok(act(tp(w), 'issue-title'), 'a file a card runs keeps its Optimize');
});

// The clock time of the newest run, card or whole suite, and when it ran on hover.
test('Tests: Last run took shows each file\'s newest run\'s clock time, with its date and time on hover', () => {
  const w = show();
  assert.deepEqual(rows(w).slice(0, 2).map((r) => cells(r)[7]), ['10 min 0 s', '8 min 7 s']);
  const took = rowOf(w, WHOLE).children[7];
  // T0 less 2 h is 10:00 in New York, in the Board's default Time and Date (issue 458).
  assert.equal(took.title, '11/09/2026, 10:00:00 AM, whole suite');
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

// Bug it catches (#272): a search for the case capwaittests found nothing, as the search matched file paths alone.
// A row found by a case name says which case; a row its path matched names none, even when a case matches too.
// WHOLE's other case names come from the snapshot's other parts that name a file's cases: a failure's cases, a
// hollow case, a wait and a flaky entry; each is searched for, so a part the search leaves out fails its own line.
test('Tests: the search finds a file by one of its case names, and names the case that matched', () => {
  const w = boot({ tab: 'tests' }), d = full(), part = clone(PART);
  Object.assign(part.files[0], { failures: [{ card: 'c-9', issue: 9, time: at(3), verdict: 'main', cases: ['failedone'], tail: null }],
    hollow: [{ case: 'hollowone', kind: 'no assert', reason: 'r' }], waits: [{ case: 'waitone', kind: 'sleep', at: 'x.sh:3', reason: 'r' }] });
  d.panels.tests.data.tests = part;
  d.panels.tests.data.flaky = [{ case: `${WHOLE}: flakyone`, count: 2, issue: null, files: [WHOLE] }];
  deliver(w, d);
  const matched = (f) => { const m = rowOf(w, f).querySelector('.tests-matched'); return m && m.textContent; };
  for (const c of ['failedone', 'hollowone', 'waitone', 'flakyone']) {
    search(w, c);
    assert.deepEqual([names(w), matched(WHOLE)], [[WHOLE], `Case: ${c}`], `a case named by the snapshot's ${c}`);
  }
  search(w, 'CapWait');
  assert.deepEqual(names(w), [CARD], 'a case name, in any case');
  assert.equal(matched(CARD), 'Case: capwaittests');
  search(w, 'lib');
  assert.deepEqual(names(w), [CARD, NEVER], 'a path search as before');
  assert.deepEqual([matched(CARD), matched(NEVER)], [null, null], 'no case named for a path match');
  search(w, 'nosuchcase');
  assert.equal(tp(w).querySelector('.tests-table tbody').textContent, 'No test file matches');
});
