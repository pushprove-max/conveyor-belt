// SPDX-License-Identifier: Apache-2.0
// The Tests page's results and Optimize history (issue 74): a judge's result formatted in its row, its verdict line
// with Optimize with this verdict, a queued action in its row, Recent actions, and each file's Optimize issues with
// their state and numbers, the run where one landed, and the files an Optimize removed. Shared setup:
// dashboard-view.helpers.mjs (TA.snap(): the three files of TESTS, with the Tests model and the actions).
import assert from 'node:assert/strict';
import { boot, deliver, settle, act, cases, iso, T0, P, TA } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const { MERGE, X, ID1, ID2, rec, snap, tp, rowOf, opened, open, type } = TA;
const OLD = 'conveyor/tests/old.test.sh';
// A judge's text as a model writes it: a bold heading, a numbered list, a `-` list, a backticked path, and a script
// tag that must stay text.
const JUDGED = '**What it tests**\nIt checks the merge of two cards.\n\n1. The first case runs `conveyor/tests/merge.test.sh`.\n'
  + '2. The second case <script>window.ran = 1</script> waits.\n\n- one\n- two\n\nVERDICT: delete\n';
const judged = (verdict, text = JUDGED) => rec({ state: 'done', end: iso(Date.now()), verdict, text });
const show = (d) => { const w = boot({ tab: 'tests' }); deliver(w, d); return w; };

// Bug it guards (D1): a judge's result shown as raw markdown in a monospace box, `**` and backticks as typed; or a
// formatter that set HTML from the text, so a <script> in it became an element. Copy still copies the raw text.
test('Tests results: an ended judge\'s text is formatted, with strong, ol, ul and code, and a script stays text', async () => {
  const w = show(snap({ acts: [judged('delete')] }));
  const copied = [];
  Object.defineProperty(w.navigator, 'clipboard', { value: { writeText: (t) => { copied.push(t); return Promise.resolve(); } } });
  const md = open(w, MERGE).querySelector('.tests-box .tests-md');
  assert.ok(md, 'the text is formatted');
  assert.equal(md.querySelector('strong').textContent, 'What it tests');
  assert.deepEqual(Array.from(md.querySelectorAll('ol > li'), (l) => l.textContent),
    ['The first case runs conveyor/tests/merge.test.sh.', 'The second case <script>window.ran = 1</script> waits.']);
  assert.deepEqual(Array.from(md.querySelectorAll('ul > li'), (l) => l.textContent), ['one', 'two']);
  assert.equal(md.querySelector('code').textContent, 'conveyor/tests/merge.test.sh');
  assert.ok(!md.textContent.includes('**') && !md.textContent.includes('`'), md.textContent);
  assert.equal(md.querySelector('script'), null, 'no script element');
  assert.equal(w.ran, undefined);
  assert.equal(tp(w).querySelector('.tests-box pre'), null, 'no monospace box for a judge');
  act(opened(w, MERGE).querySelector('.tests-box'), 'copy').click();
  await settle();
  assert.deepEqual(copied, [JUDGED], 'Copy copies the raw text');
});

// Bug it guards (D2): nothing turned a judge's verdict into the next step. A verdict that Optimize acts on has
// "Optimize with this verdict", which opens the Optimize preview with the verdict and the result's text in its body.
test('Tests results: a delete verdict shows "Verdict: delete" and Optimize with this verdict opens the preview with its text', () => {
  const w = show(snap({ acts: [judged('delete')] }));
  const line = open(w, MERGE).querySelector('.tests-verdict');
  assert.match(line.textContent, /^Verdict: delete/);
  assert.equal(line.querySelector('.chip').textContent, 'delete');
  act(line, 'optimize-verdict').click();
  const body = act(opened(w, MERGE), 'issue-body').value;
  assert.equal(act(opened(w, MERGE), 'issue-title').value, `Optimize the test file ${MERGE}`);
  assert.match(body, /The judge's verdict \(.+\): delete\./);
  assert.ok(body.includes('It checks the merge of two cards.') && body.includes('VERDICT: delete'), body);
});

// Bug it guards (D2): a keep verdict, which asks for no change, offered to file an Optimize issue.
test('Tests results: a keep verdict shows "Verdict: keep" and no Optimize with this verdict', () => {
  const w = show(snap({ acts: [judged('keep', 'Keep it.\nVERDICT: keep\n')] }));
  const line = open(w, MERGE).querySelector('.tests-verdict');
  assert.match(line.textContent, /^Verdict: keep/);
  assert.equal(act(line, 'optimize-verdict'), null);
});

// Bug it guards (D3): a queued action showed nowhere in its row, or as running with no way to take it off. Its row
// shows its newest action: queued, how many wait before it, and Stop.
test('Tests results: an opened row with a queued action shows "Queued, 1 ahead" and Stop', () => {
  const ahead = rec({ id: ID2, file: X, state: 'queued', start: null, asked: iso(T0 - 60000) });
  const mine = rec({ id: 'fedcba987654', state: 'queued', start: null, asked: iso(T0 - 30000) });
  const w = show(snap({ acts: [mine, ahead, judged('keep', 'Keep it.\n')] }));
  const box = open(w, MERGE).querySelector('.tests-box');
  assert.equal(box.dataset.id, 'fedcba987654', 'the newest action of the file');
  assert.match(box.textContent, /Queued, 1 ahead/);
  assert.ok(act(box, 'stop'), 'Stop');
  // #100: queued shows a bar too, one with no value (it goes on), not the time used.
  assert.equal(box.querySelector('progress').hasAttribute('value'), false, 'no time bar before it runs');
});

// Bug it guards (D4): the results sat open under all the rows, far from their files, with no count of what runs.
// Recent actions starts collapsed, counts the running and queued actions, and a click on a file opens its row, also
// when the search hides it.
test('Tests results: Recent actions starts collapsed, counts running and queued, and a file in it opens its row', () => {
  const w = show(snap({ acts: [rec({ id: ID2, file: X, state: 'queued', start: null, asked: iso(T0) }), rec({ file: MERGE }), judged('keep')] }));
  const sec = tp(w).querySelector('.tests-results');
  assert.equal(sec.tagName, 'DETAILS');
  assert.equal(sec.open, false, 'collapsed');
  assert.equal(sec.querySelector('summary').textContent, 'Recent actions: 1 running, 1 queued');
  type(tp(w).querySelector('[data-act="search"]'), 'x.test');
  assert.equal(rowOf(w, MERGE), undefined, 'the search hides it');
  const row = Array.from(tp(w).querySelectorAll('.tests-results .tests-result-row')).find((r) => r.dataset.id === ID1);
  act(row, 'goto').click();
  assert.ok(opened(w, MERGE), 'its row is open');
  assert.equal(w.document.activeElement, act(rowOf(w, MERGE), 'open'));
});

// MERGE has two Optimize issues: #600, landed between its runs of 3 and 2 hours ago (sped up, 11 CPU s before, 6
// after, a median of 7.5 since), and #610, filed after it and open. OLD was merged into MERGE by #620.
function history() {
  const d = snap(), files = d.panels.tests.data.tests.files, merge = files.find((f) => f.file === MERGE);
  merge.optimize = [
    { issue: 600, url: `${P}/600`, time: iso(T0 - 5 * 3600000), state: 'landed', reason: null, sha: 'abc1234def5678', landed: iso(T0 - 2.5 * 3600000),
      fix: 'sped up', into: [], before: 11, after: 6, since: 7.5, sinceRuns: 2 },
    { issue: 610, url: `${P}/610`, time: iso(T0 - 1800000), state: 'open', reason: null, sha: null, landed: null, fix: null, into: [], before: null, after: null, since: null, sinceRuns: 0 }];
  files.push({ file: OLD, cpu: 5, median: 6, change: null, runs: [{ cpu: 5, sec: 6, card: 'c9-500', time: iso(T0 - 9 * 3600000) }], timedRuns: 3, removed: true,
    optimize: [{ issue: 620, url: `${P}/620`, time: iso(T0 - 8 * 3600000), state: 'landed', sha: 'fed4321', landed: iso(T0 - 7 * 3600000), fix: 'merged', into: [MERGE],
      before: 6, after: null, since: null, sinceRuns: 0 }] });
  return d;
}

// Bug it guards (D5): Optimize's results were not seen: what each issue did, and whether the file got faster.
test('Tests history: an opened row lists its Optimize issues newest first, the landed one with its commit, fix, numbers and median since', () => {
  const w = show(history());
  const items = Array.from(open(w, MERGE).querySelectorAll('.tests-opts .tests-opt'));
  assert.deepEqual(items.map((i) => i.dataset.issue), ['610', '600'], 'newest first');
  assert.match(items[0].textContent, /^Filed .+ · #610 · open$/);
  assert.equal(items[0].querySelector('a').href, `${P}/610`);
  assert.match(items[1].textContent, /^Filed .+ · #600 · landed as abc1234 · sped up · CPU s before: 11\.0 \(since it landed: 7\.5 CPU s, the median of 2 runs\), after: 6\.0$/);
});

// Bug it guards (D6): the run where an Optimize took effect was not seen, so the change in time could not be read.
test('Tests history: the first run after the landed Optimize is marked in the row\'s bars and in its runs', () => {
  const w = show(history());
  const bars = Array.from(rowOf(w, MERGE).querySelectorAll('.tests-bar'));
  assert.deepEqual(bars.map((b) => b.classList.contains('tests-bar-opt')), [false, true, false], 'oldest first: the run of 2 hours ago');
  assert.match(bars[1].title, /^11\.5 CPU s: the first run after Optimize #600 landed$/);
  const runs = Array.from(open(w, MERGE).querySelectorAll('.tests-runs .tests-run'));
  assert.deepEqual(runs.map((r) => r.classList.contains('tests-run-opt')), [false, true, false], 'newest first');
  assert.match(runs[1].textContent, /the first run after Optimize #600 landed/);
});

// Bug it guards (D6): once the first run after the landing left the row's kept runs, a later run was marked as the
// first run after Optimize. Here 5 timed runs came after #600 landed, and the row keeps only 2 of them.
test('Tests history: no run is marked when the first run after the landed Optimize is no longer kept', () => {
  const d = history();
  d.panels.tests.data.tests.files.find((f) => f.file === MERGE).optimize[0].sinceRuns = 5;
  const w = show(d);
  assert.equal(rowOf(w, MERGE).querySelector('.tests-bar-opt'), null);
  assert.equal(open(w, MERGE).querySelector('.tests-run-opt'), null);
});

// Bug it guards (D7): a file an Optimize merged away lost its history, or stayed in the table as if main had it.
test('Tests history: a file an Optimize merged shows under Removed by Optimize with its issue and the file that took its cases', () => {
  const w = show(history());
  assert.equal(rowOf(w, OLD), undefined, 'not in the table');
  const sec = tp(w).querySelector('.tests-removed');
  assert.equal(sec.querySelector('h3').textContent, 'Removed by Optimize');
  const item = sec.querySelector('.tests-gone');
  assert.equal(item.dataset.file, OLD);
  assert.match(item.textContent, new RegExp(`^${OLD} · its last run 5\\.0 CPU s, its median 6\\.0 CPU s · #620 · merged .+ · its cases are now in ${MERGE}$`));
  assert.ok(tp(w).querySelector('.tests-files').compareDocumentPosition(sec) & 4, 'after the table');
});
