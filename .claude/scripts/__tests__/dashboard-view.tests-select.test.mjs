// SPDX-License-Identifier: Apache-2.0
// The Tests page's layout and its selection (issue 73): the checkboxes, the bar of the files selected with Judge,
// Optimize and Run on all of them in one POST, the answer for each file and the files left out with why; the figures
// that filter; the column hints; and the Settings section. Shared setup: dashboard-view.helpers.mjs (TA.snap(): the
// three files of TESTS, with the Tests model and the actions).
import assert from 'node:assert/strict';
import { boot, deliver, next, settle, act, cases, clone, css, TA } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const { MERGE, X, ID1, snap, tp, rowOf, type, reply } = TA;
const E2E = 'conveyor/tests/e2e.test.sh', BIG = 'conveyor/tests/big.test.sh';
// Four files: MERGE and BIG over budget, E2E over its budget but slow on purpose (so not "Over budget"), X under it.
// X is the runner (wholeOnly) when `runner` is set.
function four({ model, runner = false } = {}) {
  const d = snap(model === undefined ? {} : { model }), files = d.panels.tests.data.tests.files;
  files.push({ ...clone(files[1]), file: BIG, cpu: 20, issue: null, flaky: 0, slower: false, failedSteps: 0 });
  if (runner) Object.assign(files.find((f) => f.file === X), { wholeOnly: true, budget: null });
  return d;
}
const show = (o) => { const w = boot({ tab: 'tests' }); deliver(w, four(o)); return w; };
const names = (w) => Array.from(tp(w).querySelectorAll('.tests-row'), (r) => r.dataset.file);
const checked = (w) => Array.from(tp(w).querySelectorAll('.tests-row')).filter((r) => act(r, 'select').checked).map((r) => r.dataset.file);
const pick = (w, f) => act(rowOf(w, f), 'select').click();
const filter = (w, k) => tp(w).querySelector(`[data-act="filter"][data-filter="${k}"]`).click();
const bar = (w) => tp(w).querySelector('.tests-selbar');
const answers = (w) => Array.from(bar(w).querySelectorAll('.tests-selbar-answers li'), (l) => l.textContent);
const results = (list) => ({ ok: true, status: 200, text: () => Promise.resolve(JSON.stringify({ results: list })) });

// Bug it guards (D1): the header checkbox that selected every file, the hidden ones too, or a bar that miscounted.
test('Tests select: with the Over budget filter, the header checkbox selects only the over-budget rows, and the bar says their count', () => {
  const w = show();
  assert.equal(bar(w), null, 'no bar with no file selected');
  filter(w, 'over');
  assert.deepEqual(names(w), [MERGE, BIG]);
  act(tp(w), 'select-all').click();
  filter(w, 'all');
  assert.deepEqual(names(w).length, 4);
  assert.deepEqual(checked(w), [MERGE, BIG], 'the over-budget rows alone');
  assert.equal(tp(w).querySelector('.tests-selected').textContent, '2 selected', 'the header says it');
  assert.equal(bar(w).querySelector('.tests-selbar-count').textContent, '2 selected');
  assert.equal(bar(w).querySelector('.tests-selbar-count').closest('[aria-live]').getAttribute('aria-live'), 'polite', 'the bar is announced');
  assert.equal(act(tp(w), 'select-all').indeterminate, true, 'some of the rows shown are selected');
  act(bar(w), 'bulk-clear').click();
  assert.deepEqual([checked(w), bar(w)], [[], null], 'Clear: none selected, no bar');
});

// Bug it guards (D2): one POST a file (Judge on 20 files, 20 asks), an answer for the selection as a whole that hid the
// file refused, or a started judge its row did not show.
test('Tests select: Judge in the bar posts one testaction with the files selected; the bar shows the answer for each', async () => {
  const w = show();
  pick(w, X); pick(w, MERGE);
  w.reply = results([{ file: MERGE, id: ID1 }, { file: X, refused: `conveyor: testaction: ${X} is not a test file of main` }]);
  act(bar(w), 'bulk-judge').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'testaction', args: ['judge', MERGE, X], repo: 'sample' } }]);
  assert.deepEqual(answers(w), [`${MERGE}: Judge this test, taken: ${ID1}`, `${X}: Judge this test, refused: conveyor: testaction: ${X} is not a test file of main`]);
  act(rowOf(w, MERGE), 'open').click();
  assert.equal(tp(w).querySelector('.tests-open .tests-box').dataset.id, ID1, 'its row shows the judge it started');
});

// Bug it guards: a judge asked for with no Tests model, which the engine refuses for each file; Run needs none.
test('Tests select: with no Tests model, Judge in the bar is disabled and says why; Run posts one testaction run', async () => {
  const w = show({ model: null });
  pick(w, MERGE); pick(w, BIG);
  assert.deepEqual([act(bar(w), 'bulk-judge').disabled, act(bar(w), 'bulk-judge').title], [true, 'Set the Tests model first.']);
  assert.match(bar(w).textContent, /Judge: Set the Tests model first\./);
  w.reply = reply(ID1);
  act(bar(w), 'bulk-run').click();
  await settle();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [['run', MERGE, BIG]]);
});

// Bug it guards: a list of 21 files sent, which the server refuses whole (TEST_FILES_MAX), with no word of why.
test('Tests select: more than 20 files selected sends nothing and says to select fewer', async () => {
  const w = boot({ tab: 'tests' }), d = four(), files = d.panels.tests.data.tests.files;
  for (let i = files.length; i < 21; i += 1) files.push({ ...clone(files[2]), file: `lib/t${i}.test.sh` });
  deliver(w, d);
  act(tp(w), 'select-all').click();
  act(bar(w), 'bulk-run').click();
  act(bar(w), 'bulk-optimize').click();
  await settle();
  assert.deepEqual(w.posts, []);
  assert.equal(bar(w).querySelector('.tests-selbar-preview'), null, 'no preview of 21 issues');
  assert.match(bar(w).textContent, /At most 20 files at a time: 21 are selected\. Select fewer\./);
});

// Bug it guards (D2): issues filed with no look at them, a Cancel that filed, an Optimize issue for the runner (which
// no change can make faster), or an edit lost before the filing.
test('Tests select: Optimize previews one issue a file and leaves the runner out with why; "File N issues" posts one test-issue', async () => {
  const w = show({ runner: true });
  pick(w, MERGE); pick(w, X); pick(w, BIG);
  act(bar(w), 'bulk-optimize').click();
  const items = () => Array.from(bar(w).querySelectorAll('.tests-selbar-preview [data-file]'));
  assert.deepEqual(items().map((i) => [i.dataset.file, act(i, 'many-title').value]),
    [[MERGE, `Optimize the test file ${MERGE}`], [BIG, `Optimize the test file ${BIG}`]]);
  assert.match(bar(w).querySelector('.tests-selbar-preview').textContent, new RegExp(`Left out: ${X.replace(/[.]/g, '\\.')}: It runs other test files`));
  assert.equal(act(bar(w), 'bulk-file').textContent, 'File 2 issues');
  act(bar(w), 'bulk-cancel').click();
  assert.deepEqual([w.posts, bar(w).querySelector('.tests-selbar-preview')], [[], null], 'Cancel files nothing');
  act(bar(w), 'bulk-optimize').click();
  type(act(items()[1], 'many-body'), 'Split it in two.');
  const first = act(items()[0], 'many-body').value;
  w.reply = results([{ file: MERGE, id: 'https://github.com/example/sample/issues/601' }, { file: BIG, id: 'https://github.com/example/sample/issues/602' }]);
  act(bar(w), 'bulk-file').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'test-issue', repo: 'sample',
    args: [MERGE, `Optimize the test file ${MERGE}`, first.trim(), BIG, `Optimize the test file ${BIG}`, 'Split it in two.'] } }]);
  assert.deepEqual(answers(w), [`${MERGE}: Optimize, taken: https://github.com/example/sample/issues/601`, `${BIG}: Optimize, taken: https://github.com/example/sample/issues/602`,
    `${X}: left out of Optimize: It runs other test files, and each of them has its own budget.`]);
});

// Bug it guards: a figure that counted the files over budget, with no way to see which ones.
test('Tests select: a figure that counts files is a button that shows them alone, as its chip does', () => {
  const w = show();
  const fig = (k) => tp(w).querySelector(`[data-figure="${k}"]`);
  assert.equal(fig('files').querySelector('.rules-what').textContent, 'Timed files');
  assert.equal(fig('files').tagName, 'DIV', 'all the files: no filter to set');
  fig('over').click();
  assert.deepEqual(names(w), [MERGE, BIG]);
  assert.deepEqual([fig('over').getAttribute('aria-pressed'), tp(w).querySelector('[data-filter="over"]').getAttribute('aria-pressed')], ['true', 'true']);
  fig('waits').click();
  assert.deepEqual(names(w), [MERGE, BIG], 'both last ran 2.5 times their CPU time');
  assert.equal(tp(w).querySelector('[data-filter="waits"]').getAttribute('aria-pressed'), 'true');
});

// Bug it guards: a column named "Clock / CPU" that the owner could not read without asking. Each heading has a hint,
// read with it (aria-describedby).
test('Tests select: each column heading has a hint, tied to its button', () => {
  const w = show();
  const hint = (k) => { const b = act(tp(w), `sort-${k}`); return w.document.getElementById(b.getAttribute('aria-describedby')); };
  for (const k of ['file', 'cpu', 'median', 'change', 'runs', 'clock', 'count', 'took', 'caught', 'status']) assert.ok(hint(k) && hint(k).textContent.length > 10, k);
  assert.equal(hint('clock').textContent, 'Wall time divided by CPU time. Above 2× the file waits more than it works.');
  // jsdom lays nothing out, so the stylesheet is read: the hint shows on hover and on keyboard focus of its heading.
  assert.match(css, /\.tests-table th:hover \.tests-hint, \.tests-table th:focus-within \.tests-hint \{ display: block; \}/);
});

// Bug it guards (D5): the settings above the table, pushing the files the owner came for off the screen; or a section
// that closed again at each snapshot.
test('Tests select: Settings comes after the table, starts collapsed, holds the Tests model, Test limits and Auto-file, and stays open', () => {
  const w = show();
  const set = () => tp(w).querySelector('details.tests-settings');
  assert.equal(set().open, false);
  assert.equal(set().querySelector('summary').textContent, 'Settings');
  assert.deepEqual(['.tests-actions', '.tests-limits', '.tests-auto'].map((s) => !!set().querySelector(s)), [true, true, true]);
  const order = ['.tests-figs', '.tests-files', '.tests-results', '.tests-settings'].map((s) => tp(w).querySelector(s));
  order.slice(1).forEach((el, i) => assert.ok(order[i].compareDocumentPosition(el) & w.Node.DOCUMENT_POSITION_FOLLOWING, `${i}`));
  set().open = true;
  next(w, four());
  assert.equal(set().open, true, 'a new snapshot keeps it open');
});
