// SPDX-License-Identifier: Apache-2.0
// The dashboard page's Tests page (#520): the figures and the table of test files, its filters, a row opened, and a
// file's budget and "slow on purpose" mark saved from its row. Shared setup: dashboard-view.helpers.mjs (TESTS: three
// files, merge.test.sh slower than usual).
import assert from 'node:assert/strict';
import { P, TESTS, clone, boot, deliver, next, settle, full, act, panel, cases, pickProject } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const tp = (w) => panel(w, 'tests');
const MERGE = 'conveyor/tests/merge.test.sh';
const rows = (w) => Array.from(tp(w).querySelectorAll('.tests-row'));
const cells = (r) => Array.from(r.children, (td) => td.textContent);
const rowOf = (w, f) => rows(w).find((r) => r.dataset.file === f);
const opened = (w, f) => Array.from(tp(w).querySelectorAll('.tests-open')).find((r) => r.dataset.file === f);
const said = (w) => tp(w).querySelector('.tests-note').textContent;
const type = (el, v) => { el.value = v; el.dispatchEvent(new el.ownerDocument.defaultView.Event('input')); };
const figure = (w, k) => { const f = tp(w).querySelector(`[data-figure="${k}"]`); return f && f.querySelector('.rules-big').textContent; };
const open = (w, f) => { act(rowOf(w, f), 'open').click(); return opened(w, f); };
// An item of an opened row's More menu picked (issue 73); the row as it is then.
const menu = (w, f, item) => { act(opened(w, f), 'more').click(); act(opened(w, f), item).click(); return opened(w, f); };

// Bug: a file that got three times slower showed no change when it was over the one budget from the start. Each row
// compares the file with its own median, and the files that need a look come first.
test('Tests: a snapshot with 3 files gives 3 rows with now, median and change; the file slower than usual has that chip and comes first', () => {
  const w = boot({ tab: 'tests' });
  deliver(w, full());
  assert.deepEqual(rows(w).map((r) => cells(r).slice(0, 4)), [
    [MERGE, '12.0', '6.0', '+100%'],
    ['conveyor/tests/e2e.test.sh', '40.0', '39.0', '+3%'],
    ['.claude/scripts/__tests__/x.test.mjs', '2.0', '4.0', '-50%']], 'merge needs a look: first; then the highest CPU s');
  assert.deepEqual(cells(rowOf(w, MERGE)).slice(5, 7), ['2.5×', '7']);
  assert.match(cells(rowOf(w, MERGE)).at(-1), /Over budget.*Slower than usual.*Waits.*Flaky.*Fails often.*#480$/);
  assert.doesNotMatch(cells(rowOf(w, 'conveyor/tests/e2e.test.sh')).at(-1), /Slower than usual|Over budget/, 'over its budget but slow on purpose: not "Over budget"');
  assert.match(cells(rowOf(w, 'conveyor/tests/e2e.test.sh')).at(-1), /Slow on purpose/);
  assert.match(cells(rows(w)[2]).at(-1), /Faster/);
  assert.equal(rowOf(w, MERGE).querySelector('.tests-bars').getAttribute('aria-label'), 'Last runs, oldest first: 11.0, 11.5, 12.0 CPU s');
  assert.deepEqual(['files', 'over', 'slower', 'waits', 'wait', 'run'].map((k) => figure(w, k)), ['3', '1', '1', '1', '2 min', '1 h 00 min']);
});

test('Tests: a filter chip shows only its rows, and its count matches', () => {
  const w = boot({ tab: 'tests' });
  deliver(w, full());
  const chips = () => Array.from(tp(w).querySelectorAll('[data-act="filter"]'), (b) => b.textContent);
  assert.deepEqual(chips(), ['All 3', 'Over budget 1', 'Slower than usual 1', 'Faster 1', 'Waits 1', 'Flaky 1', 'Fails often 1', 'Has an issue 1', 'Slow on purpose 1'],
    'a status no file has gets no chip');
  const pick = (k) => Array.from(tp(w).querySelectorAll('[data-act="filter"]')).find((b) => b.dataset.filter === k).click();
  pick('purpose');
  assert.deepEqual(rows(w).map((r) => r.dataset.file), ['conveyor/tests/e2e.test.sh']);
  assert.equal(tp(w).querySelector('[data-filter="purpose"]').getAttribute('aria-pressed'), 'true');
  pick('faster');
  assert.deepEqual(rows(w).map((r) => r.dataset.file), ['.claude/scripts/__tests__/x.test.mjs']);
  pick('all');
  assert.equal(rows(w).length, 3);
});

test('Tests: a row opens to list its runs, each with a link to its card, its budget and its mark', () => {
  const w = boot({ tab: 'tests' });
  deliver(w, full());
  const more = open(w, MERGE);
  assert.equal(act(rowOf(w, MERGE), 'open').getAttribute('aria-expanded'), 'true');
  assert.deepEqual(Array.from(more.querySelectorAll('.tests-run a.issue'), (a) => [a.textContent, a.getAttribute('href')]),
    [['#509', `${P}/509`], ['#451', `${P}/451`], ['#435', `${P}/435`]], 'the cards that ran it, newest first');
  assert.match(more.querySelector('.tests-run').textContent, /^12\.0 CPU s · 30\.0 s on the clock · card #509/);
  assert.match(more.querySelectorAll('.tests-run')[2].textContent, /clock not recorded/);
  assert.match(more.textContent, /Budget: 8\.0 CPU s, the project budget\.Slow on purpose: none\./);
  // Issue 73: the budget and the mark are set from the More menu; each editor shows once picked there, with where it saves.
  assert.equal(more.querySelector('.rules-row'), null, 'no editor until picked from More');
  menu(w, MERGE, 'menu-budget');
  menu(w, MERGE, 'menu-mark');
  assert.deepEqual(Array.from(opened(w, MERGE).querySelectorAll('.rules-row'), (r) => [r.querySelector('.board-label').textContent, r.querySelector('.tests-where').textContent]),
    [['Set a budget for this file', 'Saves to: Pack file: this project'], ['Mark as slow on purpose', 'Saves to: Pack file: this project']]);
  act(rowOf(w, MERGE), 'open').click();
  assert.equal(opened(w, MERGE), undefined, 'and closes again');
});

// The budget saves through `conveyor.sh test-settings` (POST control), as a Rules value does: typing sends nothing,
// and a refusal keeps the value in force. Bug it guards: a value sent as typed, or a refusal shown as saved.
test('Tests: Set a budget shows Unsaved; a refusal shows the reason and keeps the old value; Save posts the file and value', async () => {
  const w = boot({ tab: 'tests' });
  deliver(w, full());
  open(w, MERGE);
  let more = menu(w, MERGE, 'menu-budget');
  assert.ok(act(more, 'file-budget-save').hidden, 'nothing to save yet');
  type(act(more, 'file-budget-field'), '40');
  assert.ok(!act(more, 'file-budget-save').hidden && more.textContent.includes('Unsaved'), 'typed: Unsaved, with Save and Cancel');
  assert.deepEqual(w.posts, [], 'typing sent nothing');
  w.reply = { ok: false, status: 409, text: () => Promise.resolve(`conveyor: test-settings file-budget: "${MERGE}" is not a file of main's checkout; nothing changed`) };
  act(more, 'file-budget-save').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'test-settings', args: ['file-budget', MERGE, '40'], repo: 'sample' } }]);
  more = opened(w, MERGE);
  assert.match(more.querySelector('.rules-refused').textContent, /^Not saved: conveyor: test-settings file-budget: .* is not a file of main's checkout/);
  assert.match(more.textContent, /Budget: 8\.0 CPU s, the project budget\./, 'refused: the old value stays');
  assert.equal(act(more, 'file-budget-field').value, '40', 'and the value typed stays, unsaved');
  w.reply = null;
  type(act(more, 'file-budget-field'), '30');
  act(more, 'file-budget-save').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'test-settings', args: ['file-budget', MERGE, '30'], repo: 'sample' } }]);
  more = opened(w, MERGE);
  assert.match(more.textContent, /Budget: 30\.0 CPU s, its own\./);
  assert.match(said(w), /Saved: budget of conveyor\/tests\/merge\.test\.sh now 30 CPU s/);
  // Clear empties it; Save sends the clear.
  act(more, 'file-budget-clear').click();
  act(opened(w, MERGE), 'file-budget-save').click();
  await settle();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [['file-budget-clear', MERGE]]);
});

// The mark asks for the reason: the engine refuses a mark with none, so the page sends none.
test('Tests: Mark as slow on purpose with no reason does not post; with one it posts the reason', async () => {
  const w = boot({ tab: 'tests' });
  deliver(w, full());
  open(w, MERGE);
  let more = menu(w, MERGE, 'menu-mark');
  assert.ok(act(more, 'slow-mark-field'), 'it asks for the reason');
  act(more, 'slow-mark-save').click();
  await settle();
  assert.deepEqual(w.posts, [], 'no reason: nothing sent');
  assert.equal(said(w), 'Type why the file is slow on purpose first.');
  type(act(more, 'slow-mark-field'), '  merges 40 branches  ');
  act(more, 'slow-mark-save').click();
  await settle();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body), [{ action: 'test-settings', args: ['slow-mark', MERGE, 'merges 40 branches'], repo: 'sample' }]);
});

test('Tests: a project with no file times shows its step figures and the state, and no table', () => {
  const w = boot({ tab: 'tests' });
  const d = full();
  d.panels.tests.data.tests = { ...clone(TESTS), files: [], slower: [], totals: { files: 0, overBudget: 0, slower: 0, steps: { count: 4, waitSec: 30, runSec: 600 } } };
  deliver(w, d);
  assert.match(tp(w).textContent, /No file times for this project/);
  assert.match(tp(w).textContent, /conveyor\/tools\/testtime\.sh prints this line/, 'with what starts the record');
  assert.equal(tp(w).querySelector('.tests-table'), null);
  assert.deepEqual([figure(w, 'files'), figure(w, 'wait'), figure(w, 'run')], [null, '30 s', '10 min']);
  assert.match(tp(w).textContent, /Slot wait, 4 test steps in 7 days/);
});

test('Tests: the project switch changes the rows to that project\'s', () => {
  const w = boot({ tab: 'tests' });
  const d = full();
  d.panels.machine.data.repos = ['sample', 'widgetshop'];
  const shop = { ...clone(TESTS), files: [{ ...clone(TESTS.files[2]), file: 'tests/shop.test.sh' }] };
  Object.assign(d.panels.tests.data, { repos: ['sample', 'widgetshop'], others: { widgetshop: { repo: 'widgetshop', tests: shop, machine: d.panels.tests.data.machine } } });
  deliver(w, d);
  assert.equal(rows(w).length, 3);
  assert.equal(tp(w).querySelector('.panel-title').textContent, 'Tests: sample');
  pickProject(w, 'widgetshop');
  assert.deepEqual(rows(w).map((r) => r.dataset.file), ['tests/shop.test.sh']);
  assert.equal(tp(w).querySelector('.panel-title').textContent, 'Tests: widgetshop');
});

// Bug (#557): the table was built new with each snapshot and its sideways scroll went back to the left edge, under a
// reader who had scrolled right to read a file's chips.
test('Tests: a new snapshot keeps the table\'s sideways scroll', () => {
  const w = boot({ tab: 'tests' });
  const data = full();
  deliver(w, data);
  const wide = () => tp(w).querySelector('.tests-scroll');
  const was = wide();
  was.scrollLeft = 240;
  data.panels.tests.data.tests.files[0].cpu += 1;
  next(w, data);
  assert.notEqual(wide(), was, 'the table is built new');
  assert.equal(wide().scrollLeft, 240);
});
