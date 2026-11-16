// SPDX-License-Identifier: Apache-2.0
// The Tests page's hollow tests (#77): the Hollow filter chip, an opened row's hollow cases with their kind and reason
// (a judge's, once one ended with them, in place of the engine's cheap check), and the Optimize preview body naming
// them. Shared setup: dashboard-view.helpers.mjs (TA.snap(): the three files of TESTS, with the Tests model and the
// actions).
import assert from 'node:assert/strict';
import { boot, deliver, act, cases, iso, TA } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const { MERGE, X, rec, snap, tp, rowOf, open } = TA;
const E2E = 'conveyor/tests/e2e.test.sh';

// Bug it catches: a test that passes without proving anything looked like any other on the Tests page, and the
// Optimize issue did not name it, so its card left it as it was; the cheap check's guess still showed after a judge
// had read the file; or a file with many hollow cases made a body longer than the server takes.
test('Tests hollow: the Hollow chip counts the files with hollow cases, a row lists them (the judge\'s over the cheap check\'s), and Optimize names them', () => {
  const d = snap({ acts: [rec({ state: 'done', end: iso(Date.now()), verdict: 'keep',
    hollow: [{ case: 'merges two cards', kind: 'mock-echo', reason: 'it checks the stub returns what the stub was given' }] })] });
  const files = d.panels.tests.data.tests.files, of = (f) => files.find((x) => x.file === f);
  of(X).hollow = [{ case: 'loads', kind: 'no-assert', reason: 'no expect or assert call' }, { case: 'has a value', kind: 'defined-only', reason: 'its only assertions are toBeDefined or toBeTruthy' }];
  of(MERGE).hollow = [{ case: 'the cheap guess', kind: 'no-assert', reason: 'no expect or assert call' }];
  // So many hollow cases that the issue body (at most 2500 characters) holds some and counts the rest.
  of(E2E).hollow = Array.from({ length: 80 }, (_, i) => ({ case: `case number ${i} of the long list`, kind: 'no-assert', reason: 'no expect or assert call' }));
  const w = boot({ tab: 'tests' });
  deliver(w, d);
  const chip = Array.from(tp(w).querySelectorAll('[data-act="filter"]')).find((b) => b.dataset.filter === 'hollow');
  assert.equal(chip.textContent, 'Hollow 3');
  chip.click();
  assert.deepEqual(Array.from(tp(w).querySelectorAll('.tests-row'), (r) => r.dataset.file).sort(), [E2E, MERGE, X].sort(), 'the Hollow filter shows the files with hollow cases alone');
  const cases = (f) => Array.from(open(w, f).querySelectorAll('.tests-hollow-case'), (li) => li.textContent);
  assert.deepEqual(cases(X), ['loads (no-assert): no expect or assert call', 'has a value (defined-only): its only assertions are toBeDefined or toBeTruthy']);
  assert.deepEqual(cases(MERGE), ['merges two cards (mock-echo): it checks the stub returns what the stub was given'], 'the judge\'s hollow cases replace the cheap check\'s');
  act(open(w, X), 'optimize').click();
  const body = act(open(w, X), 'issue-body').value;
  assert.ok(body.includes('Hollow cases (they pass without proving anything)') && body.includes('- loads (no-assert): no expect or assert call')
    && body.includes('- has a value (defined-only): its only assertions are toBeDefined or toBeTruthy'), body);
  act(open(w, E2E), 'optimize').click();
  const long = act(open(w, E2E), 'issue-body').value, listed = long.split('\n').filter((l) => l.startsWith('- case number ')).length;
  assert.ok(long.length <= 2500 && listed > 0 && long.endsWith(`- and ${80 - listed} more`), long);
  assert.ok(rowOf(w, X).querySelector('.rules-marks').textContent.includes('Hollow'), 'the row\'s status says Hollow');
});
