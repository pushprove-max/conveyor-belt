// SPDX-License-Identifier: Apache-2.0
// The Tests page's opened row (issue 130, the owner's mockup D): the tabs Overview, Timeline (N), Judge and Mutation;
// Overview's diagnosis box (the state, the judge's verdict in one line, the next step suggested as the primary
// button), its six tiles and its 3 latest events; the Timeline's filters; the judge's report folded on the Judge tab
// with its verdict said once; Optimize with this verdict scrolled to with the cursor in its body; the preview's Last
// runs without "card null". Shared setup: dashboard-view.helpers.mjs (TA.snap(): the three files of TESTS).
import assert from 'node:assert/strict';
import { boot, deliver, next, act, cases, iso, T0, P, TA, css } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const { MERGE, rec, snap, opened, open } = TA;
const show = (d) => { const w = boot({ tab: 'tests' }); deliver(w, d); return w; };
const pane = (w, k) => opened(w, MERGE).querySelector(`.tests-pane[data-pane="${k}"]`);
const words = (els) => Array.from(els, (x) => x.textContent);
const REPORT = '**What it tests**\nIt proves the merge of two cards, which no other test file checks. It is slow.\n\n- one\n\nVERDICT: keep\n';
const judged = (verdict, text) => rec({ state: 'done', end: iso(Date.now()), verdict, text });
// MERGE (12 CPU s, budget 8, three card runs 1 to 3 hours ago) with #600 landed between them (11 → 6 CPU s).
function landed(acts = []) {
  const d = snap({ acts });
  d.panels.tests.data.tests.files.find((f) => f.file === MERGE).optimize = [
    { issue: 600, url: `${P}/600`, time: iso(T0 - 5 * 3600000), state: 'landed', reason: null, sha: 'abc1234def5678', landed: iso(T0 - 2.5 * 3600000),
      fix: 'sped up', into: [], before: 11, after: 6, since: 7.5, sinceRuns: 2 }];
  return d;
}

// Bug it catches: an opened row was one long column of plain text that said neither what state the file was in nor
// what to do next; its runs were sentences with no trend; its budget a loose line; and its Optimize numbers a run of
// text that did not say whether the Optimize helped.
test('Tests row: Overview opens first with the diagnosis, the next step as the primary button, six tiles and the 3 latest events', () => {
  const w = show(landed());
  const more = open(w, MERGE);
  assert.deepEqual(words(more.querySelectorAll('[role="tab"]')), ['Overview', 'Timeline (4)', 'Judge', 'Mutation']);
  assert.deepEqual(Array.from(more.querySelectorAll('.tests-pane'), (p) => [p.dataset.pane, p.hidden]),
    [['overview', false], ['timeline', true], ['judge', true], ['mutation', true]], 'Overview open, the others folded');
  const diag = pane(w, 'overview').querySelector('.tests-diag');
  assert.equal(diag.querySelector('.tests-diag-state').textContent,
    'Still 50% over budget after one Optimize card (-45%): 12.0 CPU s against a budget of 8.0. It is slower than usual: +100% against its median.');
  assert.equal(diag.querySelector('.tests-diag-verdict').textContent, 'Judge: Not judged yet.');
  // Over budget, an Optimize landed and none open, no keep verdict: Optimize again is the step suggested.
  const primary = diag.querySelectorAll('.btn-primary');
  assert.deepEqual(words(primary), ['Optimize again']);
  assert.deepEqual(Array.from(pane(w, 'overview').querySelectorAll('.tests-tile'), (t) => [t.dataset.tile, t.querySelector('.tests-tile-label').textContent]),
    [['cpu', 'CPU now'], ['runs', 'Last 4 runs'], ['optimize', 'Last Optimize'], ['clock', 'Clock'], ['caught', 'Bugs caught'], ['mutants', 'Mutants']]);
  const tile = (k) => pane(w, 'overview').querySelector(`[data-tile="${k}"]`);
  assert.deepEqual(words(tile('cpu').children).slice(1), ['12.0 CPU s', 'Budget: 8.0 CPU s, the project budget.']);
  assert.deepEqual(words(tile('optimize').children).slice(1), ['-45%', '#600 · 11.0 → 6.0 CPU s Helped']);
  assert.deepEqual(words(tile('clock').children).slice(1), ['30 s', '2.5× clock / CPU']);
  assert.equal(tile('mutants').querySelector('.tests-tile-big').textContent, 'not checked');
  // The runs as a trend: a bar a run, oldest first, its value on hover (title) and on focus (focusable, named).
  const bars = Array.from(tile('runs').querySelectorAll('.tests-bar'));
  assert.deepEqual(bars.map((b) => [b.dataset.value, b.tabIndex]), [['11.0', 0], ['11.5', 0], ['12.0', 0]]);
  assert.match(bars[2].getAttribute('aria-label'), /^12\.0 CPU s, card #509, /);
  assert.equal(bars[2].title, bars[2].getAttribute('aria-label'));
  const latest = Array.from(pane(w, 'overview').querySelectorAll('.tests-latest .tests-tl-item'));
  assert.deepEqual(latest.map((li) => li.dataset.kind), ['runs', 'runs', 'optimize'], 'the 3 newest');
  assert.doesNotMatch(more.textContent, /c\d-\d{3}/, 'no card id anywhere in the row');
  act(pane(w, 'overview'), 'timeline-all').click();
  assert.equal(pane(w, 'timeline').hidden, false);
  assert.equal(w.document.activeElement, act(opened(w, MERGE), 'tab-timeline'));
});

// Bug it catches: the next step did not follow from the file's state and its judge's verdict.
test('Tests row: a keep verdict on a file over budget suggests Raise this file\'s budget…, which opens its budget editor', () => {
  const w = show(landed([judged('keep', REPORT)]));
  const diag = open(w, MERGE).querySelector('.tests-diag');
  assert.deepEqual(words(diag.querySelectorAll('.btn-primary')), ['Raise this file\'s budget…']);
  act(diag, 'raise-budget').click();
  assert.equal(w.document.activeElement, act(opened(w, MERGE), 'file-budget-field'));
});

// Bug it catches: the judge's text, about 60 lines, was shown whole and open and pushed the rest off the screen; it
// said its verdict three times.
test('Tests row: the judge\'s report is folded under its one-line verdict, and the Judge tab says its verdict once', () => {
  const w = show(snap({ acts: [judged('keep', REPORT)] }));
  open(w, MERGE);
  assert.equal(pane(w, 'overview').querySelector('.tests-md'), null, 'no report on Overview');
  const line = pane(w, 'overview').querySelector('.tests-diag-verdict');
  assert.equal(line.querySelector('.chip').textContent, 'keep');
  assert.equal(line.querySelector('.tests-diag-why').textContent, 'It proves the merge of two cards, which no other test file checks.');
  assert.equal(pane(w, 'judge').hidden, true, 'folded');
  act(line, 'judge-report').click();
  const judge = pane(w, 'judge');
  assert.equal(judge.hidden, false);
  assert.equal(pane(w, 'overview').hidden, true);
  assert.ok(judge.querySelector('.tests-md').textContent.includes('no other test file checks'));
  assert.equal((judge.textContent.match(/keep/gi) || []).length, 1, `the verdict once: ${judge.textContent}`);
});

// Bug it catches (#219): after a judge with a verdict and a newer one that failed, Overview said the first one's verdict
// but Full report opened the failed one, so the report behind that verdict could not be read.
test('Tests row: Full report opens the judge behind Overview\'s verdict when a newer judge failed', () => {
  const failed = rec({ id: TA.ID2, state: 'failed', end: iso(Date.now()), verdict: null, text: 'the model stopped\n' });
  const w = show(snap({ acts: [failed, judged('keep', REPORT)] }));
  open(w, MERGE);
  const line = pane(w, 'overview').querySelector('.tests-diag-verdict');
  assert.equal(line.querySelector('.chip').textContent, 'keep');
  act(line, 'judge-report').click();
  const judge = pane(w, 'judge');
  assert.deepEqual(Array.from(judge.querySelectorAll('.tests-box'), (b) => b.dataset.id), [TA.ID1], 'the report behind the verdict');
  assert.ok(judge.querySelector('.tests-md').textContent.includes('no other test file checks'));
  assert.equal(judge.querySelector('.tests-judge-newer').textContent, 'A newer judge ended with no verdict (Failed). It shows on Timeline.');
});

// Bug it catches: each snapshot built the panes new, so a reader part way down the Judge report was put back at its top.
test('Tests row: a new snapshot keeps the place read in the opened tab\'s pane', () => {
  const d = snap({ acts: [judged('keep', REPORT)] });
  const w = show(d);
  open(w, MERGE);
  act(opened(w, MERGE), 'tab-judge').click();
  const was = pane(w, 'judge');
  was.scrollTop = 300;
  d.panels.tests.data.tests.files.find((f) => f.file === MERGE).cpu += 1;
  next(w, d);
  assert.notEqual(pane(w, 'judge'), was, 'the pane is built new');
  assert.equal(pane(w, 'judge').hidden, false);
  assert.equal(pane(w, 'judge').scrollTop, 300);
});

// Bug it catches (owner, 2026-11-16): Optimize with this verdict opened a preview off the screen, with
// the cursor in its title, and the preview did not show the verdict.
test('Tests row: Optimize with this verdict scrolls to the preview, puts the cursor in its body, and shows the verdict', () => {
  const w = show(snap({ acts: [judged('delete', REPORT.replace('keep', 'delete'))] }));
  const scrolled = [];
  w.HTMLElement.prototype.scrollIntoView = function (o) { scrolled.push([this.className, JSON.stringify(o)]); };
  open(w, MERGE);
  act(pane(w, 'judge').querySelector('.tests-verdict'), 'optimize-verdict').click();
  const body = act(opened(w, MERGE), 'issue-body');
  assert.equal(pane(w, 'overview').hidden, false, 'the preview is on Overview, open');
  assert.equal(w.document.activeElement, body);
  assert.deepEqual([body.selectionStart, body.selectionEnd], [0, 0]);
  assert.deepEqual(scrolled, [['tests-preview', '{"block":"start"}']]);
  assert.equal(opened(w, MERGE).querySelector('.tests-preview-verdict .chip').textContent, 'delete');
});

// Bug it catches (owner, 2026-11-16): a whole-suite run was "card null" in the preview's Last runs.
test('Tests row: the preview\'s Last runs say "whole suite, passed" or "whole suite, failed", and a card run its issue', () => {
  const d = snap();
  d.panels.tests.data.tests.files.find((f) => f.file === MERGE).runs = [
    { cpu: 12, sec: 30, card: null, time: iso(T0 - 3600000), whole: true, result: 'ok' },
    { cpu: 11, sec: 28, card: null, time: iso(T0 - 7200000), whole: true, result: 'fail' },
    { cpu: 10, sec: 20, card: 'c3-509', issue: 509, url: `${P}/509`, time: iso(T0 - 10800000), whole: false }];
  const w = show(d);
  act(open(w, MERGE), 'optimize').click();
  const body = act(opened(w, MERGE), 'issue-body').value;
  assert.ok(body.includes('- Last runs, newest first: 12.0 CPU s (whole suite, passed), 11.0 CPU s (whole suite, failed), 10.0 CPU s (card #509)'), body);
  assert.doesNotMatch(body, /card null|c3-509/);
});

// Bug it catches: the Timeline's filter chips did not show one kind of event alone; the left and right arrows did
// not move between the tabs (the left arrow from the first tab goes round to the last).
test('Tests row: the arrows move between the tabs; the Timeline lists every event newest first, and a filter chip shows one kind alone', () => {
  const w = show(landed([judged('keep', REPORT)]));
  open(w, MERGE);
  const key = (k, name) => act(opened(w, MERGE), `tab-${k}`).dispatchEvent(new w.KeyboardEvent('keydown', { key: name, bubbles: true }));
  key('overview', 'ArrowLeft');
  assert.equal(pane(w, 'mutation').hidden, false);
  key('mutation', 'ArrowRight');
  key('overview', 'ArrowRight');
  assert.deepEqual(Array.from(opened(w, MERGE).querySelectorAll('.tests-pane'), (p) => p.hidden), [true, false, true, true]);
  const tl = pane(w, 'timeline');
  assert.deepEqual(words(tl.querySelectorAll('[data-filter]')), ['All 5', 'Runs 3', 'Optimize 1', 'Test edits 0', 'Judge 1']);
  assert.deepEqual(Array.from(tl.querySelectorAll('.tests-tl-item'), (li) => li.dataset.kind), ['judge', 'runs', 'runs', 'optimize', 'runs']);
  act(tl, 'tl-judge').click();
  const only = Array.from(pane(w, 'timeline').querySelectorAll('.tests-tl-item'));
  assert.deepEqual(only.map((li) => li.dataset.kind), ['judge']);
  assert.equal(only[0].querySelector('.chip').textContent, 'keep');
});

// jsdom lays nothing out, so this reads the rule. Bug it catches: the page head, which stays at the top of the
// window, covered the opened row's text as the page scrolled; a pane is at most the window under the head, and scrolls inside.
test('Tests row: a tab\'s pane is never taller than the window under the page head, and scrolls inside', () => {
  const rule = /(?:^|\})\s*\.tests-pane\s*\{([^}]*)\}/.exec(css.replace(/\/\*[\s\S]*?\*\//g, ''));
  assert.ok(rule, 'a rule of its own for .tests-pane');
  assert.match(rule[1], /max-height:\s*calc\(100vh - var\(--head-h, 64px\)/);
  assert.match(rule[1], /overflow-y:\s*auto/);
});
