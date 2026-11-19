// SPDX-License-Identifier: Apache-2.0
// The Tests page's proxy checks (#780): the Proxy checks chip on a file's row with its lines and the comment that says
// why beside it, and the Proxy checks filter. Shared setup: dashboard-view.helpers.mjs (TA.snap(): the three files of
// TESTS, with the Tests model and the actions).
import assert from 'node:assert/strict';
import { boot, deliver, cases, TA } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const { MERGE, X, snap, tp, rowOf } = TA;
const E2E = 'conveyor/tests/e2e.test.sh';

// Bug it catches: a test file that runs other test files or polls a real process looked like any other on the Tests
// page, so a check through a proxy, and whether a comment says why, could not be found; or the chip or the filter
// showed a file with no proxy line ([] from the engine) too.
test('Tests proxy: the Proxy checks chip names the lines and their why, and the filter shows the marked files only', () => {
  const d = snap();
  const files = d.panels.tests.data.tests.files, of = (f) => files.find((x) => x.file === f);
  of(E2E).proxy = [{ line: 12, kind: 'runs', text: 'bash conveyor/tests/a.test.sh', why: 'only a whole run shows its exit status' },
    { line: 40, kind: 'polls', text: "wait_until '[ -s out ]'", why: null }];
  of(X).proxy = [{ line: 7, kind: 'polls', text: 'wait_until ready', why: null }];
  of(MERGE).proxy = [];
  const w = boot({ tab: 'tests' });
  deliver(w, d);
  const chip = Array.from(tp(w).querySelectorAll('[data-act="filter"]')).find((b) => b.dataset.filter === 'proxy');
  assert.equal(chip.textContent, 'Proxy checks 2');
  assert.equal(rowOf(w, MERGE).querySelector('.tests-proxy'), null, 'a file with no proxy line has no chip');
  assert.equal(rowOf(w, E2E).querySelector('.tests-proxy').textContent, 'Proxy checks: lines 12, 40');
  assert.equal(rowOf(w, X).querySelector('.tests-proxy').textContent, 'Proxy checks: line 7');
  assert.deepEqual(Array.from(rowOf(w, E2E).querySelectorAll('.tests-proxy-why'), (s) => s.textContent),
    ['Line 12 runs another test file or the suite runner: why: only a whole run shows its exit status', 'Line 40 polls a real process: no comment says why']);
  chip.click();
  assert.deepEqual(Array.from(tp(w).querySelectorAll('.tests-row'), (r) => r.dataset.file).sort(), [E2E, X].sort(), 'the Proxy checks filter shows the marked files alone');
});
