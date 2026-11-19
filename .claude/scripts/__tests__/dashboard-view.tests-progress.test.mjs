// SPDX-License-Identifier: Apache-2.0
// The Tests page's actions in progress (#100): each action shows, where it was clicked (its row, or the bar of the
// files selected), that it was sent from the click while the build machine has not answered, then queued (how many
// wait before it), running (its time) and its result, or why it was refused. Shared setup: dashboard-view.helpers.mjs
// (TA.snap(): the three files of TESTS, with the Tests model).
import assert from 'node:assert/strict';
import { boot, deliver, next, settle, act, cases, iso, T0, TA } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const { MERGE, X, ID1, ID2, rec, snap, tp, rowOf, opened, open, reply } = TA;
// The build machine's answer, held until the test lets it go: the page as it is while the POST waits.
function held(w) { let go; w.reply = new Promise((r) => { go = r; }); return (r) => { go(r); return settle(); }; }
const refused = (text) => ({ ok: false, status: 409, text: () => Promise.resolve(text) });
const show = (d = snap()) => { const w = boot({ tab: 'tests' }); deliver(w, d); return w; };
const boxOf = (w) => opened(w, MERGE).querySelector('.tests-box');
const lineOf = (w) => opened(w, MERGE).querySelector('.tests-note-line');
// A bar that only shows that it goes on (no value): sent, or queued.
const goesOn = (el) => { const b = el.querySelector('progress'); return Boolean(b) && !b.hasAttribute('value'); };
const RUN = { cli: undefined, model: undefined, effort: undefined, limit: 3600 };

// Each action of a row: how it is clicked, its record's own fields, how it ends, and what its result shows.
const ROW = [
  ['judge', 'Judge this test', (w) => act(open(w, MERGE), 'judge').click(), {}, { verdict: 'keep', text: 'It is **cheap**.\nVERDICT: keep\n' },
    (b) => { assert.equal(b.querySelector('.tests-verdict .chip-ok').textContent, 'keep'); assert.equal(b.querySelector('.tests-md strong').textContent, 'cheap', 'its text formatted'); }],
  ['explain', 'Explain the slowdown', (w) => { act(open(w, MERGE), 'more').click(); act(opened(w, MERGE), 'explain').click(); }, {}, { text: 'It **waits** on a sleep.\n' },
    (b) => assert.equal(b.querySelector('.tests-md strong').textContent, 'waits', 'its text formatted')],
  ['run', 'Run this file now', (w) => act(open(w, MERGE), 'run').click(), RUN, { result: 'fail', cpu: 2.5, text: 'not ok 1 merges\n' },
    (b) => { assert.equal(b.querySelector('.chip-bad').textContent, 'Failed, 2.5 CPU s'); assert.equal(b.querySelector('pre.tests-out').textContent, 'not ok 1 merges\n'); }],
];
for (const [how, words, click, own, ended, shows] of ROW) {
  // Bug it guards (#100): Judge seemed to do nothing: the build machine answers once the action has started (seconds),
  // and until then nothing showed beside the button; nor did the row show it queued, running or its result.
  test(`Tests progress: ${words} on a row shows in its box from the click: sent, queued, running, then its result`, async () => {
    const w = show();
    const go = held(w);
    click(w);
    assert.match(boxOf(w).textContent, new RegExp(`^${words}Starting: sent to the build machine`), 'at the click, before any answer');
    assert.ok(goesOn(boxOf(w)), 'with a bar');
    // An explain sends the browser's zone (the helpers' TZ) and the Time setting, 12-hour by default (#770).
    assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [how === 'explain' ? [how, '--time', 'America/New_York', '12-hour', MERGE] : [how, MERGE]]);
    await go(reply(ID1));
    assert.match(boxOf(w).textContent, /Running: 0:00/, 'answered: started');
    const r = (o) => rec({ action: how, start: iso(T0 - 100000), ...own, ...o });
    next(w, snap({ acts: [r({ state: 'queued', start: null, asked: iso(T0 - 30000) }), r({ id: ID2, file: X, state: 'queued', start: null, asked: iso(T0 - 60000) })], at: T0 + 1000 }));
    assert.match(boxOf(w).textContent, /Queued, 1 ahead/);
    assert.ok(goesOn(boxOf(w)), 'queued: a bar');
    next(w, snap({ acts: [r({})], at: T0 + 2000 }));
    assert.match(boxOf(w).textContent, /Running: 1:40 of the (15|60):00 time limit/);
    assert.equal(boxOf(w).querySelector('progress').value, 100, 'running: the time used');
    next(w, snap({ acts: [r({ state: 'done', end: iso(T0), ...ended })], at: T0 + 3000 }));
    assert.equal(boxOf(w).querySelector('progress'), null, 'ended: no bar');
    assert.match(boxOf(w).querySelector('.tests-result').textContent, /^Done in 1:40 · /);
    shows(boxOf(w));
  });
}

// Bug it guards (#100): a refused action said why only at the foot of the page, far from the button clicked.
test('Tests progress: a Judge the build machine refuses says why in its box, and it stays', async () => {
  const w = show();
  const go = held(w);
  act(open(w, MERGE), 'judge').click();
  await go(refused('conveyor: claude is not logged in; no session started'));
  assert.equal(boxOf(w).textContent, 'Judge this testNot started: conveyor: claude is not logged in; no session started');
  assert.equal(boxOf(w).querySelector('progress'), null);
  next(w, snap({ at: T0 + 1000 }));
  assert.match(boxOf(w).textContent, /Not started: .*not logged in/, 'through the next snapshot');
});

// Bug it guards (#100): Mutation check from a row's More menu said nothing on the row while sent, queued or running.
test('Tests progress: Mutation check on a row shows on its line: sent, queued with how many ahead, running with its time, done', async () => {
  const w = show();
  const go = held(w);
  act(open(w, MERGE), 'more').click();
  act(opened(w, MERGE), 'mutate').click();
  assert.match(lineOf(w).textContent, /^Mutation check: sent to the build machine/);
  assert.ok(goesOn(lineOf(w)));
  await go(reply('conveyor: mutation check asked of 1 file(s), at the front of the idle queue.'));
  assert.match(lineOf(w).textContent, /^Mutation check: Queued\. A check starts/);
  const at = (mutation, place, t) => {
    const d = snap({ at: t }), f = d.panels.tests.data.tests.files.find((x) => x.file === MERGE);
    Object.assign(f, { mutation, mutationPlace: place });
    return d;
  };
  const check = (o) => ({ file: MERGE, at: iso(T0 - 65000), sha: 'abc1234', state: 'running', reason: null, of: 20, tried: 3, killed: 2, survived: [], end: null, ...o });
  next(w, at(null, 3, T0 + 1000));
  assert.match(lineOf(w).textContent, /Queued: place 3 in the idle queue, 2 ahead\./);
  next(w, at(check({}), null, T0 + 2000));
  assert.equal(lineOf(w).textContent, 'Mutation check: Running: mutant 4 of 20. 1:05 so far.');
  assert.deepEqual([lineOf(w).querySelector('progress').value, lineOf(w).querySelector('progress').max], [3, 20]);
  next(w, at(check({ state: 'done', tried: 20, killed: 14, end: iso(T0) }), null, T0 + 3000));
  assert.match(lineOf(w).textContent, /^Mutation check: Done .+: 14 of 20 mutants caught\.$/);
  assert.equal(lineOf(w).querySelector('progress'), null);
});

// Bug it guards (#100): an Optimize issue filed from a row showed neither that it was sent nor where it was filed.
test('Tests progress: Optimize filed from a row shows on its line: sent, then why it was refused, then the issue filed', async () => {
  const w = show();
  act(open(w, MERGE), 'optimize').click();
  let go = held(w);
  act(tp(w), 'issue-file').click();
  assert.match(lineOf(w).textContent, /^Optimize: sent to the build machine/);
  await go(refused('conveyor: the issue about conveyor/tests/merge.test.sh could not be filed: HTTP 502'));
  assert.equal(lineOf(w).textContent, 'Optimize: Not done: conveyor: the issue about conveyor/tests/merge.test.sh could not be filed: HTTP 502');
  assert.ok(act(tp(w), 'issue-title'), 'refused: the preview stays');
  go = held(w);
  act(tp(w), 'issue-file').click();
  await go(reply('https://github.com/example/sample/issues/601'));
  assert.equal(lineOf(w).textContent, 'Optimize: Filed: https://github.com/example/sample/issues/601');
});

// Bug it guards (#100): Run from the bar said "taken" and an id, and nothing more: not that it was sent, nor queued,
// running or its result.
test('Tests progress: Run from the bar shows sent at the click, then each file\'s run: running, then passed or failed with its output', async () => {
  const w = show();
  [MERGE, X].forEach((f) => act(rowOf(w, f), 'select').click());
  const bar = () => tp(w).querySelector('.tests-selbar-answers'), line = (f) => Array.from(bar().children).find((l) => l.dataset.file === f);
  const go = held(w);
  act(tp(w).querySelector('.tests-selbar'), 'bulk-run').click();
  assert.match(bar().textContent, /^Run this file now: sent to the build machine/);
  assert.ok(goesOn(bar()));
  await go(reply(JSON.stringify({ results: [{ file: MERGE, id: ID1 }, { file: X, id: ID2 }] })));
  assert.match(line(MERGE).textContent, /^conveyor\/tests\/merge\.test\.sh: Run this file now: Running: 0:00/);
  const r = (o) => rec({ action: 'run', start: iso(T0 - 100000), ...RUN, ...o });
  next(w, snap({ acts: [r({}), r({ id: ID2, file: X, state: 'queued', start: null })], at: T0 + 1000 }));
  assert.match(line(MERGE).textContent, /Running: 1:40 of the 60:00 time limit/);
  assert.match(line(X).textContent, /Queued, 0 ahead/);
  next(w, snap({ acts: [r({ state: 'done', end: iso(T0), result: 'ok', cpu: 1.2, text: 'ok 1 merges\n' }), r({ id: ID2, file: X, state: 'failed', end: iso(T0), reason: 'the copy of main could not be made' })], at: T0 + 2000 }));
  assert.equal(line(MERGE).querySelector('.chip-ok').textContent, 'Passed, 1.2 CPU s');
  assert.equal(line(MERGE).querySelector('details pre').textContent, 'ok 1 merges\n', 'its output, to open');
  assert.match(line(X).textContent, /: Run this file now: Failed in 1:40 · .*the copy of main could not be made/, 'a failed run says why');
  assert.equal(bar().querySelector('progress'), null, 'ended: no bar');
});

// Bug it guards (#100): Mutation check from the bar said "queued" and nothing more as its files' checks ran.
test('Tests progress: Mutation check from the bar shows sent at the click, then each file\'s check as it runs', async () => {
  const w = show();
  act(rowOf(w, MERGE), 'select').click();
  const bar = () => tp(w).querySelector('.tests-selbar-answers');
  const go = held(w);
  act(tp(w).querySelector('.tests-selbar'), 'bulk-mutate').click();
  assert.match(bar().textContent, /^Mutation check: sent to the build machine/);
  await go(reply('conveyor: mutation check asked of 1 file(s), at the front of the idle queue.'));
  assert.match(bar().children[0].textContent, /^conveyor\/tests\/merge\.test\.sh: Mutation check: Queued\./);
  const d = snap({ at: T0 + 1000 });
  d.panels.tests.data.tests.files.find((x) => x.file === MERGE).mutation = { file: MERGE, at: iso(T0 - 5000), state: 'running', of: 10, tried: 0, killed: 0, survived: [], end: null };
  next(w, d);
  assert.equal(bar().children[0].textContent, 'conveyor/tests/merge.test.sh: Mutation check: Running: mutant 1 of 10. 0:05 so far.');
});
