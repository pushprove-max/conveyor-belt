// SPDX-License-Identifier: Apache-2.0
// The Tests page's Caught column (#75): how often each test file failed on a card whose landed change left it as it
// was (the engine's caught and changedToPass, testfiles.test.sh tfcaught), and the grey "Never caught anything" fact.
// Shared setup: dashboard-view.helpers.mjs (TESTS: e2e, merge and x, here with their counts).
import assert from 'node:assert/strict';
import { TESTS, clone, boot, deliver, full, act, panel, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const tp = (w) => panel(w, 'tests');
const E2E = 'conveyor/tests/e2e.test.sh', MERGE = 'conveyor/tests/merge.test.sh', X = '.claude/scripts/__tests__/x.test.mjs';
// e2e: 30 runs, none caught (the fact); merge: 3 caught, 2 edited until they passed; x: 19 runs, none caught (too few runs for the fact).
const COUNTS = { [E2E]: { runsOnRecord: 30, caught: 0, changedToPass: 1 }, [MERGE]: { runsOnRecord: 40, caught: 3, changedToPass: 2 }, [X]: { runsOnRecord: 19, caught: 0, changedToPass: 0 } };
const rows = (w) => Array.from(tp(w).querySelectorAll('.tests-row'));
const rowOf = (w, f) => rows(w).find((r) => r.dataset.file === f);
const caughtCell = (w, f) => rowOf(w, f).querySelector('.tests-caught');

// Bug it catches: a page that could not show which test files ever caught a bug, so a file that never fails, and may
// check nothing, looked like any other; or a quiet file shown as a problem chip.
test('Tests caught: the Caught column sorts, shows the edits until it passed on hover, and a file with 20 runs or more and no catch says "Never caught anything"', () => {
  const w = boot({ tab: 'tests' });
  const d = full(), part = clone(TESTS);
  part.files = part.files.map((f) => ({ ...f, ...COUNTS[f.file] }));
  d.panels.tests.data.tests = part;
  deliver(w, d);
  assert.deepEqual([caughtCell(w, MERGE).textContent, caughtCell(w, MERGE).title], ['3', 'Edited until it passed: 2']);
  act(tp(w), 'sort-caught').click();
  assert.deepEqual(rows(w).map((r) => r.dataset.file), [MERGE, E2E, X], 'highest first; equal counts keep their order');
  act(tp(w), 'sort-caught').click();
  assert.deepEqual(rows(w).map((r) => r.dataset.file).slice(-1), [MERGE], 'lowest first');
  const never = (f) => rowOf(w, f).querySelector('.tests-never');
  assert.equal(never(E2E).textContent, 'Never caught anything');
  assert.equal(never(E2E).classList.contains('tests-quiet'), true, 'grey text, not a chip');
  assert.equal(never(X), null, '19 runs: too few');
  assert.equal(never(MERGE), null, 'it caught 3');
  assert.equal(Array.from(tp(w).querySelectorAll('[data-act="filter"]')).some((b) => /Never caught/.test(b.textContent)), false, 'not a problem filter');
});
