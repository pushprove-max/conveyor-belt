// SPDX-License-Identifier: Apache-2.0
// The Tests page's mutation checks (#79): the Mutants caught column, an opened row's check state and surviving mutants,
// Mutation check in the bar (one ask for the files selected), the survivors in Optimize's preview, and the mutants
// caught before and after a landed Optimize. The snapshot's mutation and mutationPlace come from the engine
// (testfiles.test.sh tfoptimize, mutate.test.sh mutask). Shared setup: dashboard-view.helpers.mjs (TA.snap(): the three
// files of TESTS, with the Tests model).
import assert from 'node:assert/strict';
import { boot, deliver, next, settle, act, cases, iso, T0, TA } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const { MERGE, X, snap, tp, rowOf, open, reply } = TA;
const E2E = 'conveyor/tests/e2e.test.sh';
const SHA = 'abc1234def5678abc1234def5678abc1234def56';
// Six mutants of the code merge.test.sh tests that it did not catch, each with its line and change.
const SIX = [12, 20, 31, 44, 57, 63].map((line, i) => ({ source: 'conveyor/lib/merge.sh', line, kind: i % 2 ? 'number' : 'flip',
  before: `  [ "$n" -lt ${i} ]`, after: `  [ "$n" -ge ${i} ]` }));
const check = (o) => ({ file: null, at: iso(T0 - 86400000), sha: SHA, seed: 7, state: 'done', reason: null, of: 20, tried: 20, killed: 0,
  survived: [], noresult: 0, notMutated: [], end: iso(T0 - 82800000), ...o });
// merge.test.sh: done, 14 of 20 caught, 6 survivors, and a landed Optimize with the mutants caught before and after it;
// x.test.mjs: done, 3 of 4; e2e.test.sh: a check that runs, its fourth mutant now (none done: its column is empty).
function snapshot() {
  const d = snap(), files = d.panels.tests.data.tests.files, of = (f) => files.find((x) => x.file === f);
  of(MERGE).mutation = check({ file: MERGE, killed: 14, survived: SIX });
  of(MERGE).optimize = [{ issue: 81, time: iso(T0 - 7 * 86400000), state: 'landed', sha: 'fed4321', landed: iso(T0 - 6 * 86400000), fix: 'sped up', into: [],
    before: 12, after: 6, since: null, sinceRuns: 0, mutantsBefore: { at: iso(T0 - 8 * 86400000), killed: 9, of: 20 }, mutantsAfter: { at: iso(T0 - 86400000), killed: 14, of: 20 } }];
  of(X).mutation = check({ file: X, of: 4, tried: 4, killed: 3 });
  of(E2E).mutation = check({ file: E2E, state: 'running', tried: 3, end: null });
  return d;
}
const show = (d = snapshot()) => { const w = boot({ tab: 'tests' }); deliver(w, d); return w; };
const cellOf = (w, f) => rowOf(w, f).querySelector('.tests-mutants');
const names = (w) => Array.from(tp(w).querySelectorAll('.tests-row'), (r) => r.dataset.file);
const stateOf = (w, f) => open(w, f).querySelector('.tests-mut-state').textContent;

// Bug it guards (D1): a page with no way to see how many mutants a file's tests caught, a column that did not sort by
// it, or an opened row that did not say which mutants survived, where and what changed; an Optimize history that hid
// the mutants caught before and after it landed; a running check shown as no check.
test('Tests mutants: the column shows "14 / 20" with when and which commit on hover, and sorts; an opened row lists 6 survivors with their line and change', () => {
  const w = show();
  assert.equal(cellOf(w, MERGE).textContent, '14 / 20');
  assert.match(cellOf(w, MERGE).title, /^Checked .+ on commit abc1234$/);
  assert.equal(cellOf(w, E2E).textContent, 'running', 'no check done: no count');
  act(tp(w), 'sort-mutants').click();
  assert.deepEqual(names(w), [X, MERGE, E2E], '3 / 4 before 14 / 20; a file with no check done last');
  act(tp(w), 'sort-mutants').click();
  assert.deepEqual(names(w), [MERGE, X, E2E], 'lowest first; no check done still last');
  const row = open(w, MERGE), lis = Array.from(row.querySelectorAll('.tests-survivors .tests-survivor'));
  assert.equal(lis.length, 6);
  assert.equal(lis[0].textContent, 'conveyor/lib/merge.sh:12 (flip) [ "$n" -lt 0 ] → [ "$n" -ge 0 ] · tests still passed');
  assert.deepEqual(lis.map((l) => [l.querySelector('.board-label').textContent, l.querySelector('.tests-mut-before').textContent, l.querySelector('.tests-mut-after').textContent]),
    SIX.map((x) => [`conveyor/lib/merge.sh:${x.line}`, x.before.trim(), x.after.trim()]));
  assert.match(stateOf(w, MERGE), /^Done .+: 14 of 20 mutants caught\.$/);
  assert.match(row.querySelector('.tests-opts li').textContent, /Mutants caught before: 9 \/ 20, after: 14 \/ 20/);
  assert.equal(stateOf(w, E2E), 'Running: mutant 4 of 20.');
});

// Bug it guards (D2): one POST a file, a check started at once, rows that did not show the files queued, a bar that
// did not say that a check waits while a card needs a test slot, or a paused check shown as done.
test('Tests mutants: Mutation check on 3 selected files posts one ask with those files; the rows show "queued", then their place', async () => {
  const d = snapshot(), files = d.panels.tests.data.tests.files;
  files.find((f) => f.file === X).mutation = check({ file: X, state: 'stopped', reason: 'card c1-57 is in its test step', of: 4, tried: 1, killed: 1, end: null });
  const w = show(d);
  assert.equal(stateOf(w, X), 'Paused for a card: card c1-57 is in its test step. It goes on from mutant 2 of 4 later.');
  assert.equal(cellOf(w, X).textContent, 'paused');
  [MERGE, X, E2E].forEach((f) => act(rowOf(w, f), 'select').click());
  const said = 'conveyor: mutation check asked of 3 file(s), at the front of the idle queue. A check starts only when no card needs a test slot; now card c1-57 is in its test step.';
  w.reply = reply(said);
  act(tp(w).querySelector('.tests-selbar'), 'bulk-mutate').click();
  await settle();
  const posts = w.posts.splice(0);
  assert.equal(posts.length, 1, 'one ask');
  assert.deepEqual([posts[0].url, posts[0].body.action, posts[0].body.repo, posts[0].body.args.slice().sort()], ['control', 'mutate', 'sample', [E2E, MERGE, X].sort()]);
  assert.deepEqual([cellOf(w, MERGE).textContent, cellOf(w, X).textContent], ['14 / 20 · queued', 'queued']);
  assert.equal(stateOf(w, X), 'Queued. A check starts only when no card needs a test slot.');
  assert.equal(tp(w).querySelector('.tests-selbar .tests-said').textContent, said.replace(/^conveyor: /, ''), 'the bar says a card holds it back');
  // The snapshot names their places: each row says its own.
  const d2 = snapshot();
  d2.panels.tests.data.tests.files.forEach((f, i) => { f.mutationPlace = i + 1; if (f.file === E2E) f.mutation = null; });
  next(w, d2);
  const at = d2.panels.tests.data.tests.files.findIndex((f) => f.file === X) + 1;
  assert.equal(stateOf(w, X), `Queued: place ${at} in the idle queue, ${at - 1} ahead. A check starts only when no card needs a test slot.`);
});

// Bug it guards (D3): an Optimize issue whose body did not name the mutants its tests did not catch, so its card could not
// add the assertions that catch them.
test('Tests mutants: the Optimize preview of a file with survivors names each one in its body', () => {
  const w = show();
  act(open(w, MERGE), 'optimize').click();
  const body = tp(w).querySelector('[data-act="issue-body"]').value;
  assert.match(body, /Surviving mutants \(the code it tests was changed, and its tests still passed\): add the assertions that catch each one\./);
  SIX.forEach((x) => assert.ok(body.includes(`- conveyor/lib/merge.sh:${x.line} (${x.kind}): \`${x.before.trim()}\` → \`${x.after.trim()}\``), `line ${x.line}: ${body}`));
  act(tp(w), 'issue-cancel').click();
  act(open(w, X), 'optimize').click();
  assert.ok(!tp(w).querySelector('[data-act="issue-body"]').value.includes('Surviving mutants'), 'a file with no survivor has no such list');
});
