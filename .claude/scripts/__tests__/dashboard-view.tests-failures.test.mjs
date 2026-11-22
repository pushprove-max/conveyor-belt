// SPDX-License-Identifier: Apache-2.0
// The Tests page's failures (#188): "Fails often" counts the failures no card's change caused, those a card's change
// caused show apart as "caught N card changes", each failure says its kind in the row and its detail, and Fix failures
// previews an issue that asks a card to make the file succeed reliably. Shared setup: dashboard-view.helpers.mjs (TA.snap():
// the three files of TESTS with the Tests model; fail(): one failed test step).
import assert from 'node:assert/strict';
import { boot, deliver, next, settle, act, cases, iso, P, TA, fail, T0 } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const { MERGE, X, rec, snap, tp, rowOf, opened, open } = TA;
const TAIL = 'ok one\nnot ok mergeclean: the lock file was left by another case';
// merge.test.sh failed on main once and flaked once, and caught one card change; x.test.mjs caught three card changes
// and nothing else. The acts given are the actions of the snapshot.
function show(acts = []) {
  const d = snap({ acts }), files = d.panels.tests.data.tests.files, of = (f) => files.find((x) => x.file === f);
  of(MERGE).failures = [fail(509, 1, 'main', ['mergeclean'], TAIL), fail(451, 2, 'card', ['mergeorder']), fail(435, 3, 'flaky', ['mergeclean', 'mergewait'])];
  of(X).failures = [fail(601, 1, 'card', ['one']), fail(602, 2, 'card', ['two']), fail(603, 3, 'card', ['one'])];
  of(X).failedSteps = 3;
  const w = boot({ tab: 'tests' });
  deliver(w, d);
  return w;
}
const status = (w, f) => rowOf(w, f).lastElementChild;
const judged = (verdict, o = {}) => rec({ state: 'done', end: iso(Date.now()), verdict, text: `It shares a lock file.\nVERDICT: ${verdict}\n`, ...o });
const CAUSES = [{ case: 'mergeclean', kind: 'shared state', reason: 'two cases write the same lock file' }];

// Bug it guards (#188): a ratchet guard that failed because 3 cards broke the ratchet showed "Fails often", though it
// did its job each time. Its card failures show apart, as caught card changes with their cards; the file with a flaky
// and a main failure is the one that fails often, and its row says which kinds.
test('Tests failures: card failures never set Fails often and show as caught card changes; flaky and main ones do', () => {
  const w = show();
  assert.doesNotMatch(status(w, X).textContent, /Fails often/);
  const caught = status(w, X).querySelector('.tests-caught-cards');
  assert.equal(caught.textContent, 'caught 3 card changes');
  assert.equal(caught.title, 'Its test did its job: #601, #602, #603');
  assert.equal(status(w, X).querySelector('.tests-fail-kinds'), null, 'no failure of it counts');
  assert.match(status(w, MERGE).textContent, /Fails often/);
  assert.equal(status(w, MERGE).querySelector('.tests-fail-kinds').textContent, 'Failed: 1 flaky, 1 failed on main too');
  assert.equal(status(w, MERGE).querySelector('.tests-caught-cards').textContent, 'caught 1 card change');
  const chip = Array.from(tp(w).querySelectorAll('[data-act="filter"]')).find((b) => b.dataset.filter === 'fails');
  assert.equal(chip.textContent, 'Fails often 1');
});

// Bug it guards (#188): the detail of a file gave no failure, so the owner could not tell a flaky one from one that did
// its job. Overview lists each failed step with its kind, card and cases, and the caught card changes apart with links.
test('Tests failures: an opened row lists each failure with its kind, card and cases, and the caught card changes apart', () => {
  const w = show();
  const more = open(w, MERGE);
  const items = Array.from(more.querySelectorAll('.tests-fail-list > li'));
  assert.deepEqual(items.map((li) => li.dataset.verdict), ['main', 'card', 'flaky']);
  assert.match(items[0].textContent, /failed on main too · card #509 · mergeclean$/);
  assert.match(items[1].textContent, /caught a card change · card #451 · mergeorder$/);
  assert.match(items[2].textContent, /flaky · card #435 · mergeclean, mergewait$/);
  const caught = more.querySelector('.tests-caught-list');
  assert.match(caught.textContent, /^Caught 1 card change \(the test did its job; not counted as Fails often\): #451$/);
  assert.equal(caught.querySelector('a').href, `${P}/451`);
});

// Bug it guards (#188): a failure from before verdicts were kept vanished from the count, or was taken for the card's.
// It counts for Fails often and says it has no verdict on record; with no flaky or main failure, no Fix failures.
test('Tests failures: a failure with no verdict on record counts for Fails often, says so, and offers no Fix failures', () => {
  const w = boot({ tab: 'tests' });
  deliver(w, snap());
  assert.equal(status(w, MERGE).querySelector('.tests-fail-kinds').textContent, 'Failed: 2 with no verdict on record');
  assert.match(status(w, MERGE).textContent, /Fails often/);
  const more = open(w, MERGE);
  assert.match(more.querySelector('.tests-fail-list > li').textContent, /no verdict on record/);
  assert.equal(act(more, 'fix-failures'), null);
});

// Bug it guards (#188): "Fails often" had no means to resolve it. Fix failures opens the issue preview with the failing
// cases, their kinds and output ends, the judge's causes and the Done-when the card's check holds; filing it posts one
// test-issue with the title the engine knows. A file whose every failure is a card's has no Fix failures.
test('Tests failures: Fix failures previews the issue with cases, kinds, output, causes and Done-when, and files it', async () => {
  const w = show([judged('keep', { causes: CAUSES })]);
  assert.equal(act(open(w, X), 'fix-failures'), null, 'a file that only caught card changes has nothing to fix');
  let more = open(w, MERGE);
  act(more, 'fix-failures').click();
  more = opened(w, MERGE);
  const title = act(more, 'issue-title').value, body = act(more, 'issue-body').value;
  assert.equal(title, `Fix the failures of the test file ${MERGE}`);
  assert.match(body, /^Make this test file succeed reliably, and keep what it tests\./);
  assert.match(body, /- .+, card #509: failed on main too\. Failing cases: mergeclean\.\n- .+, card #435: flaky\. Failing cases: mergeclean, mergewait\./);
  assert.doesNotMatch(body, /#451|mergeorder/, 'the failure a card caused is not one to fix');
  assert.match(body, /The causes the judge named:\n- CAUSE: mergeclean \| shared state \| two cases write the same lock file/);
  assert.match(body, /\nThe end of the output of card #509 \(.+\):\nok one\nnot ok mergeclean: the lock file was left by another case\n/);
  assert.match(body, /\n\nDone when:\n- The cases that failed \(mergeclean, mergewait\) succeed in 10 runs in a row of this file alone on a test slot\.\n- They succeed in a run beside the other files of the suite\.$/);
  assert.equal(more.querySelector('.tests-preview-verdict'), null, 'a keep verdict is no verdict of this issue');
  assert.deepEqual(w.posts, [], 'the preview files nothing');
  w.reply = TA.reply('https://github.com/example/sample/issues/700');
  act(more, 'issue-file').click();
  await settle();
  const posts = w.posts.splice(0);
  assert.deepEqual(posts.map((p) => [p.body.action, p.body.args[0], p.body.args[1], p.body.args[2] === body.trim()]), [['test-issue', MERGE, title, true]]);
  assert.match(opened(w, MERGE).textContent, /Fix failures: Filed: https:\/\/github\.com\/example\/sample\/issues\/700/);
});

// Bug it guards (#1384, R8): the Fix failures preview was made once, when opened, so after a later "Test history starts
// at" was saved it still showed, and filed, the failures before the new start. A snapshot under another start makes the
// draft again from the failures it counts (the engine leaves out the older ones); with none left to fix it closes.
test('Tests failures: an open Fix failures preview is made again when the test history start changes', () => {
  const w = show();
  act(open(w, MERGE), 'fix-failures').click();
  assert.match(act(opened(w, MERGE), 'issue-body').value, /card #435: flaky/);
  const later = (start, failures) => { const d = snap(); Object.assign(d.panels.tests.data.tests.settings, { historyStart: start }); d.panels.tests.data.tests.files.find((x) => x.file === MERGE).failures = failures; return d; };
  // A start 2 hours back: #435 (3 hours back) is before it, #509 (1 hour back) after.
  next(w, later(iso(T0 - 2 * 3600000), [fail(509, 1, 'main', ['mergeclean'], TAIL)]));
  const body = act(opened(w, MERGE), 'issue-body').value;
  assert.doesNotMatch(body, /#435/, `the failure before the new start is not in the preview:\n${body}`);
  assert.match(body, /card #509: failed on main too\. Failing cases: mergeclean\./);
  next(w, later(iso(T0), []));
  assert.equal(act(opened(w, MERGE), 'issue-body'), null, 'with no failure left to fix the preview closes');
});

// Bug it guards (#188): a file with many failures gave a Fix failures body over the 2500 characters the server takes,
// so the issue could not be filed, or its Done-when was cut off. The list stops with "and N more" and Done-when stays.
test('Tests failures: with 40 flaky failures the Fix failures body stays within 2500 characters and keeps its Done-when', () => {
  const d = snap(), f = d.panels.tests.data.tests.files.find((x) => x.file === MERGE);
  f.failures = Array.from({ length: 40 }, (_, i) => fail(700 + i, i + 1, 'flaky', [`case${i}`], 'x'.repeat(300)));
  const w = boot({ tab: 'tests' });
  deliver(w, d);
  act(open(w, MERGE), 'fix-failures').click();
  const body = act(opened(w, MERGE), 'issue-body').value;
  assert.ok(body.length <= 2500, `${body.length} characters`);
  assert.match(body, /\n- and \d+ more\n/);
  assert.match(body, /Done when:\n- The cases that failed \(case0, .+, case9 and 30 more\) succeed in 10 runs in a row of this file alone on a test slot\.\n- They succeed in a run beside the other files of the suite\.$/);
});

// Bug it guards (#188): the judge's stabilise verdict led nowhere, and its causes were lost in its text. The Judge tab
// lists the causes, and "Optimize with this verdict" opens the Fix failures preview, with the verdict.
test('Tests failures: a stabilise verdict lists its causes and Optimize with this verdict opens the Fix failures preview', () => {
  const w = show([judged('stabilise', { causes: CAUSES })]);
  open(w, MERGE);
  act(opened(w, MERGE), 'tab-judge').click();
  const pane = opened(w, MERGE).querySelector('[data-pane="judge"]');
  assert.deepEqual(Array.from(pane.querySelectorAll('.tests-causes > li'), (li) => li.textContent), ['mergeclean | shared state | two cases write the same lock file']);
  act(pane.querySelector('.tests-verdict'), 'optimize-verdict').click();
  const more = opened(w, MERGE);
  assert.equal(act(more, 'issue-title').value, `Fix the failures of the test file ${MERGE}`);
  assert.match(act(more, 'issue-body').value, /CAUSE: mergeclean \| shared state/);
  assert.equal(more.querySelector('.tests-preview-verdict .chip').textContent, 'stabilise');
});
