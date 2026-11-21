// SPDX-License-Identifier: Apache-2.0
// A card's timeline shows the changed lines no test reached (#309), from the coverage report its test run wrote (the
// test record's coverage, testlist.sh uncovered()). Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { T0, iso, boot, panel, deliver, trackOf, full, cases, openEvery } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const at = (s) => iso(T0 - 1000000 + s * 1000);

// Bug it guards (#309): the step showed which tests ran, never which changed lines no test reached, so the reviewer
// could not see new code that ran in no test. A run whose report fits the patch lists them by file with the count; a
// run whose report does not fit says the coverage is unknown and why, and lists no lines.
test('a test step lists the changed lines no test reached by file, and says unknown when the report does not fit', () => {
  const w = boot();
  const data = full();
  const card = data.panels.belt.data.cards[0];
  card.track = trackOf('+++>..', 'review', { since: at(900), records: [
    { name: 'picked', state: 'done', sec: null, at: at(0) }, { name: 'building', state: 'done', sec: 600, at: at(600) },
    { name: 'tests failed', state: 'failed', sec: 100, at: at(700), why: 'exit 1',
      coverage: { unknown: 'the coverage report names line 9 of src/a.js, which has 2 lines in the tested patch' } },
    { name: 'fix 1', state: 'done', sec: 100, at: at(800) },
    { name: 'tests passed', state: 'done', sec: 100, at: at(900),
      coverage: { uncovered: [{ file: 'src/a.js', lines: '5-6' }, { file: 'src/b.js', lines: '12' }], count: 3, checked: 7 } },
    { name: 'review 1', state: 'now', sec: null }] });
  deliver(w, data);
  const row = panel(w, 'belt').querySelector(`li[data-key="sample:${card.card}"]`);
  const boxes = Array.from(openEvery(w, row.querySelector('details.track-detail')).querySelectorAll('.test-coverage'));
  assert.equal(boxes.length, 2, 'each test step shows its coverage');
  assert.equal(boxes[0].querySelector('.test-sum').textContent,
    'Changed lines no test reached: unknown (the coverage report names line 9 of src/a.js, which has 2 lines in the tested patch)');
  assert.equal(boxes[0].querySelector('.test-file'), null, 'an unknown coverage lists no line');
  assert.equal(boxes[1].querySelector('.test-sum').textContent, 'Changed lines no test reached: 3 of 7');
  assert.deepEqual(Array.from(boxes[1].querySelectorAll('.test-file'), (li) => li.textContent), ['src/a.js: lines 5-6', 'src/b.js: line 12']);
});
