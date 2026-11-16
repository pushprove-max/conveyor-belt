// SPDX-License-Identifier: Apache-2.0
// The Tests page's Test edits by cards (#76): what each landed card did to a test file main had (the engine's
// testedits, testfiles.test.sh tfedits), its Weakened and All edits filters, and an opened row's own edits.
// Shared setup: dashboard-view.helpers.mjs (TESTS: e2e, merge and x).
import assert from 'node:assert/strict';
import { TESTS, clone, boot, deliver, full, act, panel, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const tp = (w) => panel(w, 'tests');
const E2E = 'conveyor/tests/e2e.test.sh', MERGE = 'conveyor/tests/merge.test.sh', X = '.claude/scripts/__tests__/x.test.mjs';
const zero = { read: true, removedAsserts: 0, changedExpected: 0, skipsAdded: 0, timeoutsRaised: 0, casesDeleted: 0 };
const none = { read: false, removedAsserts: null, changedExpected: null, skipsAdded: null, timeoutsRaised: null, casesDeleted: null };
// Newest first: c-4 weakened merge, c-3 changed x and weakened nothing, c-2 edited e2e (not read), c-1 weakened merge.
const EDITS = [
  { card: 'c-4', issue: 44, time: '2026-11-12T10:00:00Z', file: MERGE, ...zero, removedAsserts: 1, changedExpected: 1, skipsAdded: 1 },
  { card: 'c-3', issue: 43, time: '2026-11-11T10:00:00Z', file: X, ...zero },
  { card: 'c-2', issue: 42, time: '2026-11-10T10:00:00Z', file: E2E, ...none },
  { card: 'c-1', issue: 41, time: '2026-11-09T10:00:00Z', file: MERGE, ...zero, casesDeleted: 2 }];
const shown = (root) => Array.from(root.querySelectorAll('.tests-edit'), (li) => [li.querySelector('.board-from').textContent, li.dataset.file]);
const section = (w) => tp(w).querySelector('.tests-edits');
const filter = (w, k) => Array.from(section(w).querySelectorAll('[data-act="edits-filter"]')).find((b) => b.dataset.filter === k);

// Bug it catches: a card that weakened a test to get green (an assertion removed, an expected value changed, a skip
// added) looked like any other edit, so the pattern across cards did not show; or a file's row did not list its own.
test('Tests edits: Weakened shows only the edits with a count above zero, All edits shows every one, and an opened row lists its own', () => {
  const w = boot({ tab: 'tests' });
  const d = full(), part = clone(TESTS);
  part.edits = EDITS;
  d.panels.tests.data.tests = part;
  deliver(w, d);
  assert.equal(section(w).querySelector('.board-head').textContent, 'Test edits by cards');
  assert.equal(section(w).previousElementSibling.classList.contains('tests-files'), true, 'right after the table');
  assert.deepEqual([filter(w, 'weakened').textContent, filter(w, 'weakened').getAttribute('aria-pressed'), filter(w, 'all').textContent], ['Weakened 2', 'true', 'All edits 4']);
  assert.deepEqual(shown(section(w)), [['c-4', MERGE], ['c-1', MERGE]], 'Weakened: the edits with a count above zero, newest first');
  assert.equal(section(w).querySelector('.tests-edit-counts').textContent, ' · 1 assertion removed, 1 expected value changed, 1 skip, only or todo mark added');
  assert.match(section(w).querySelector('.tests-edit').textContent, /^#44/, 'it names the card\'s issue');
  filter(w, 'all').click();
  assert.deepEqual(shown(section(w)), [['c-4', MERGE], ['c-3', X], ['c-2', E2E], ['c-1', MERGE]]);
  assert.deepEqual(Array.from(section(w).querySelectorAll('.tests-edit-counts'), (s) => s.textContent).slice(1, 3), [' · Edited, nothing weakened', ' · Edited, not read']);
  const row = Array.from(tp(w).querySelectorAll('.tests-row')).find((r) => r.dataset.file === MERGE);
  act(row, 'open').click();
  const more = Array.from(tp(w).querySelectorAll('.tests-open')).find((r) => r.dataset.file === MERGE);
  assert.deepEqual(shown(more), [['c-4', MERGE], ['c-1', MERGE]], 'its own edits alone');
  assert.equal(more.querySelector('.tests-edit-counts').textContent, ' · 1 assertion removed, 1 expected value changed, 1 skip, only or todo mark added');
});
