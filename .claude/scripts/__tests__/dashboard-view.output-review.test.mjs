// SPDX-License-Identifier: Apache-2.0
// A review's "Show output" is its findings as rows, not a mono block. Bug it catches: a NO-GO review's findings drew as
// one wall of monospace text, so the owner could not pick out one finding or see how serious it was. The rows come
// from output() in app.js, which On the belt, Landed today and Needs you all use; Needs you's blocked card is the
// fixture here. A test step's output keeping its mono block and failures list is in dashboard-view.cards-blocked.
// Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { boot, panel, deliver, settle, full, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

const LINES = [
  '[P1] .claude/dashboard/panels/release.js:214 "Run suite" also publishes the release. Proof: this button sends `release-run`.',
  '[P2] .claude/dashboard/panels/release.js:166 The notes step is skipped. Proof: notes() returns early when empty.',
  '[P3] docs/board.md:12 The page names the old button. Proof: line 12 says "Run".',
  '[P1] a/b.sh:12 The `x` call fails. Proof: `c/d.sh:5` sets `y`.',
  'VERDICT: NO-GO, three findings',
];

const draw = () => {
  const w = boot();
  const copied = [];
  Object.defineProperty(w.navigator, 'clipboard', { value: { writeText: (t) => { copied.push(t); return Promise.resolve(); } } });
  const data = full();
  const blocked = data.panels.needs.data.cards.blocked[0];
  blocked.tail = LINES.join('\n');
  deliver(w, data);
  const out = panel(w, 'needs').querySelector(`li[data-key="blocked:${blocked.card}"] details.output`);
  return { out, copied, rows: Array.from(out.querySelectorAll('.output-findings > li.output-finding')) };
};

test('a review output draws one row per finding, in order: chip, bold sentence, place, closed Proof:; code spans and line links; a plain line whole; Copy copies the raw lines', async () => {
  const { out, copied, rows: r } = draw();
  assert.equal(out.querySelector('pre.output-text'), null, 'no mono block for a review');
  assert.equal(out.querySelector('.output-fails'), null, 'no failures list for a review');
  assert.equal(r.length, 5, 'four findings and the plain line, each a row');
  const want = [
    ['P1', 'chip-warn', '"Run suite" also publishes the release.', '.claude/dashboard/panels/release.js:214', 'this button sends release-run.'],
    ['P2', 'chip-quiet', 'The notes step is skipped.', '.claude/dashboard/panels/release.js:166', 'notes() returns early when empty.'],
    ['P3', 'chip-quiet', 'The page names the old button.', 'docs/board.md:12', 'line 12 says "Run".'],
    ['P1', 'chip-warn', 'The x call fails.', 'a/b.sh:12', 'c/d.sh:5 sets y.'],
  ];
  want.forEach(([p, tone, sentence, at, proof], i) => {
    const row = r[i], c = row.querySelector('.finding-head > .chip');
    assert.equal(c.textContent, p, `row ${i + 1} is the ${p} finding`);
    assert.ok(c.classList.contains(tone), `${p} is ${tone}`);
    assert.equal(row.querySelector('.finding-text').textContent, sentence, 'the sentence without its place or proof');
    assert.equal(row.querySelector('.finding-at').textContent, at, 'the place on its own line');
    const fold = row.querySelector('details.finding-proof');
    assert.equal(fold.open, false, 'the proof is closed');
    assert.equal(fold.querySelector('summary.finding-proof-label').textContent, 'Proof:', '"Proof:" is the label of the toggle');
    assert.ok(row.querySelector('.finding-text > strong.finding-claim'), 'the sentence is in bold');
    assert.equal(fold.querySelector('.finding-proof-text').textContent, proof);
  });
  // Bug #437: a finding's code spans showed their raw backticks and its file paths were plain text, unlike a declined
  // finding: `x` is a code span, and the place and the proof's path link to their lines in the card's repository.
  const f = r[3], code = (el) => Array.from(el.querySelectorAll('code.why-code'), (c) => c.textContent);
  assert.deepEqual(code(f.querySelector('.finding-text')), ['x'], 'the sentence sets x apart as code');
  assert.deepEqual(code(f.querySelector('.finding-proof-text')), ['c/d.sh:5', 'y'], 'the proof sets its spans apart as code');
  const blob = 'https://github.com/example/sample-project/blob/HEAD';
  assert.equal(f.querySelector('.finding-at a').getAttribute('href'), `${blob}/a/b.sh#L12`, 'the place links to its line');
  assert.equal(f.querySelector('.finding-proof-text a').getAttribute('href'), `${blob}/c/d.sh#L5`, "the proof's path links to its line");
  assert.equal(r[2].querySelector('.finding-text code, .finding-proof-text code'), null, 'a text with no code span or path draws as plain text');
  // D2: a line with no [Pn] prefix is a plain row of its whole text.
  const plain = r[4];
  assert.equal(plain.querySelector('.chip'), null);
  assert.equal(plain.querySelector('.finding-at'), null);
  assert.equal(plain.querySelector('details'), null);
  assert.equal(plain.textContent, LINES[4]);
  // D4: Copy output puts the raw lines on the clipboard, unchanged.
  out.querySelector('button.output-copy').click();
  await settle();
  assert.deepEqual(copied, [LINES.join('\n')]);
});
