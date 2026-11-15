// SPDX-License-Identifier: Apache-2.0
// The Tests page lists every test file (issue 34): a file a card ran, a whole-only file that only a whole-suite run
// ran, and a file never run; its Last run took column, its sortable columns and its search box. Shared setup:
// dashboard-view.helpers.mjs; the tests part is the one the engine makes for such a project (testfiles.test.sh,
// tfeveryfile).
import assert from 'node:assert/strict';
import { P, TESTS, T0, clone, boot, deliver, full, act, panel, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const tp = (w) => panel(w, 'tests');
const CARD = 'lib/c.test.sh', WHOLE = 'conveyor/conveyor.test.sh', NEVER = 'lib/n.test.sh';
const at = (h) => new Date(T0 - h * 3600000).toISOString();
// CARD: one card run, flaky (so it needs a look and comes first with no sort), 2 CPU s in 600 s of clock. WHOLE:
// wholeOnly and slow on purpose, one whole-suite run that failed, 400 CPU s in 487 s. NEVER: no run. The snapshot's
// order: highest CPU s first.
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
    file({ file: NEVER }),
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
  assert.deepEqual(names(w), [CARD, WHOLE, NEVER], 'with no sort: the file that needs a look first, then the snapshot\'s order');
  assert.match(cells(rowOf(w, WHOLE))[8], /Whole suite only/);
  assert.doesNotMatch(cells(rowOf(w, CARD))[8], /Whole suite only|Never run/);
  assert.deepEqual(cells(rowOf(w, NEVER)).slice(1, 9), ['—', '—', '—', '', '—', '—', '—', 'Never run'], 'dashes in its figures');
  act(rowOf(w, WHOLE), 'open').click();
  const more = Array.from(tp(w).querySelectorAll('.tests-open')).find((r) => r.dataset.file === WHOLE);
  assert.match(more.textContent, /runs only in whole-suite runs/);
  assert.match(more.querySelector('.tests-run').textContent, /^400\.0 CPU s · 487\.0 s on the clock · whole suite, failed · /);
  assert.equal(more.querySelector('.tests-run a.issue'), null, 'a whole-suite run links no card');
});

// The clock time of the newest run, card or whole suite, and when it ran on hover.
test('Tests: Last run took shows each file\'s newest run\'s clock time, with its date and time on hover', () => {
  const w = show();
  assert.deepEqual(rows(w).map((r) => cells(r)[7]), ['10 min 0 s', '8 min 7 s', '—']);
  const took = rowOf(w, WHOLE).children[7];
  assert.equal(took.title, `${new Date(at(2)).toLocaleString()}, whole suite`);
  assert.equal(rowOf(w, NEVER).children[7].title, '');
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
