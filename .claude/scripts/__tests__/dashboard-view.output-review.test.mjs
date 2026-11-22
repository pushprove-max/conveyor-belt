// SPDX-License-Identifier: Apache-2.0
// A review's "Show output" is its findings as rows, not a mono block. Bug it catches: a NO-GO review's findings drew as
// one wall of monospace text, so the owner could not pick out one finding or see how serious it was. The rows come
// from output() in app.js, which On the belt, Landed today and Needs you all use; Needs you's blocked card is the
// fixture here. A test step's output keeping its mono block and failures list is in dashboard-view.cards-blocked.
// Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { boot, panel, deliver, settle, full, cases, trackOf, openEvery } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

const LINES = [
  '[P1] .claude/dashboard/panels/release.js:214 "Run suite" also publishes the release. Proof: this button sends `release-run`.',
  '[P2] .claude/dashboard/panels/release.js:166 The notes step is skipped. Proof: notes() returns early when empty.',
  '[P3] docs/board.md:12 The page names the old button. Proof: line 12 says "Run".',
  '[P1] a/b.sh:12 The `x` call fails. Proof: `c/d.sh:5` sets `y`.',
  // Bug: a finding with the reviewer's no-behaviour mark after its level (prompts.sh REVIEWT) lost its place line.
  '[P3][cleanup] a.txt:1 The second check is redundant. Proof: line 2 makes it.',
  // Bug (issue 1430): nor did one with a fix review's id before its place, the [E1] met first by the place's pattern.
  '[P2] [E1] conveyor/lib/snapshot.sh:716 Claim. Proof: x',
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
  assert.equal(r.length, 7, 'six findings and the plain line, each a row');
  const want = [
    ['P1', 'chip-warn', '"Run suite" also publishes the release.', '.claude/dashboard/panels/release.js:214', 'this button sends release-run.'],
    ['P2', 'chip-quiet', 'The notes step is skipped.', '.claude/dashboard/panels/release.js:166', 'notes() returns early when empty.'],
    ['P3', 'chip-quiet', 'The page names the old button.', 'docs/board.md:12', 'line 12 says "Run".'],
    ['P1', 'chip-warn', 'The x call fails.', 'a/b.sh:12', 'c/d.sh:5 sets y.'],
    ['P3', 'chip-quiet', 'The second check is redundant.', 'a.txt:1', 'line 2 makes it.'],
    ['P2', 'chip-quiet', 'Claim.', 'conveyor/lib/snapshot.sh:716', 'x'],
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
  assert.equal(r[5].querySelector('.finding-at a').getAttribute('href'), `${blob}/conveyor/lib/snapshot.sh#L716`, 'the place after [E1] links to its line');
  const plain = r[6];
  assert.equal(plain.querySelector('.chip'), null);
  assert.equal(plain.querySelector('.finding-at'), null);
  assert.equal(plain.querySelector('details'), null);
  assert.equal(plain.textContent, LINES[6]);
  // D4: Copy output puts the raw lines on the clipboard, unchanged.
  out.querySelector('button.output-copy').click();
  await settle();
  assert.deepEqual(copied, [LINES.join('\n')]);
});

// Bug (issue 1430): a card with no GitHub issue (a main-red fix; a Fast lane branch not named as a card) has no issue
// url to take its repository from, and the Fast lane passed no repository to its landing's output, so their review's
// file paths were plain text. The part now carries each row's repoUrl (dashboard-cards.test.sh checks the row, and
// dashboard-local.test.sh the Fast lane's blocked landing).
test('a review output of a card with no issue links its place to the record\'s repository, On the belt and in the Fast lane', () => {
  const w = boot();
  const data = full(), repoUrl = 'https://github.com/example/sample-project', tail = '[P2] conveyor/lib/card.sh:52 Claim. Proof: x';
  const card = data.panels.belt.data.cards[0];
  Object.assign(card, { issue: 0, url: null, repoUrl, track: { ...trackOf('++>...', 'review 2 of 3'),
    records: [{ name: 'review 1 (NO-GO)', state: 'done', sec: 60, at: '2026-01-01T00:01:00Z', output: tail }] } });
  data.panels.lanes.data.records[0].fast.landing = { state: 'blocked', card: 'c0-red', reason: 'review NO-GO', tail, since: null, repoUrl };
  deliver(w, data);
  const belt = () => panel(w, 'belt').querySelector(`li[data-key="sample:${card.card}"]`);
  openEvery(w, belt().querySelector('details.track-detail'));
  const href = (el) => { const a = el && el.querySelector('li.output-finding .finding-at a'); return a ? a.getAttribute('href') : null; };
  const want = `${repoUrl}/blob/HEAD/conveyor/lib/card.sh#L52`;
  assert.equal(href(belt()), want, 'On the belt: the place links to its line in the record\'s repository');
  assert.equal(href(panel(w, 'lanes').querySelector('li[data-lane="Fast lane"] > details.output')), want, 'the Fast lane landing: the same');
});

// #307. A landed card's worktree is gone, and the place's link opens main, which may hold other code there. Bugs: a
// finding's place does not open the lines the review read; they are read before it is opened (or carried in the
// snapshot) instead of on demand; a place shows another place's lines, or another review's of the same place (a later
// one's under an earlier review); a citation of a deleted line shows only the staged line at that number, or a line a
// fix round deleted is labelled as main's; a failed
// read is shown as a place with no lines.
test("a landed card's finding opens the lines its own review read, from the server when opened, both sides of a deletion", async () => {
  const w = boot();
  const data = full();
  const T1 = '2026-01-01T00:01:00Z', T2 = '2026-01-01T00:02:00Z';
  const records = [{ name: 'review 1 (NO-GO)', state: 'done', sec: 60, at: T1, output: '[P2] a.sh:2–3 slow' },
    { name: 'review 2 (NO-GO)', state: 'done', sec: 60, at: T2, output: '[P1] ./gone.sh:4 still read\n[P2] a.sh:2–3 slow\n[P3] c.sh:9 none kept' }];
  Object.assign(data.panels.landed.data.cards[0], { track: { ...trackOf('+++++++', ''), at: null, records } });
  // Needs you's own box shows a blocked card's last output: its places open the card's last review's lines.
  Object.assign(data.panels.needs.data.cards.blocked[0], { tail: '[P2] a.sh:2–3 slow', track: { ...trackOf('++!...', ''), at: null, records } });
  deliver(w, data);
  const rows = () => Array.from(panel(w, 'landed').querySelectorAll('li.output-finding'));
  // Bug it catches: the test fired its own toggle and jsdom queued one more, so under load the page read the card's lines
  // twice. A reader's toggle is the one jsdom fires on a later turn: wait for that one, as the page's listener runs first.
  const flip = (d, on) => { const fired = new Promise((r) => d.addEventListener('toggle', r, { once: true })); d.open = on; return fired; };
  const open = async (row) => { const d = row.querySelector('details.finding-lines'); await flip(d, true); return d; };
  const notes = (d) => Array.from(d.querySelectorAll('.finding-lines-note'), (x) => x.textContent);
  const texts = (d) => Array.from(d.querySelectorAll('pre.finding-lines-text'), (x) => x.textContent);
  assert.equal(rows().length, 4);
  assert.equal(w.excerptsAsks, undefined, 'nothing is read before a place is opened');
  let d = await open(rows()[1]);
  await settle();
  assert.deepEqual(w.excerptsAsks, ['excerpts?repo=sample&card=c5-7'], "the card's own lines are asked for");
  assert.deepEqual(notes(d), ['The reviewed lines did not come: no reviewed lines'], 'a failed read says so');
  w.excerptsReply = { ok: true, status: 200, json: () => Promise.resolve({ card: 'c5-7', excerpts: [
    { review: T1, at: 'a.sh:2-3', side: 'new', from: 2, lines: ['old two', 'old three'] },
    { review: T2, at: 'gone.sh:4', side: 'old', from: 4, lines: ['deleted line'] },
    { review: T2, at: 'a.sh:2-3', side: 'new', from: 2, lines: ['two', 'three'] },
    { review: T2, at: 'a.sh:2-3', side: 'old', from: 2, lines: ['deleted two'] },
    { review: T2, at: 'a.sh:2-3', side: 'fix', from: 2, lines: ['fixed away'] }] }) };
  await flip(d, false);
  d = await open(rows()[1]);
  await settle();
  assert.equal(w.excerptsAsks.length, 2, 'a failed read is asked again at the next open');
  assert.deepEqual(notes(d), ["Main's side: lines the change deleted"]);
  assert.deepEqual(texts(d), ['4 deleted line']);
  d = await open(rows()[2]);
  await settle();
  assert.equal(w.excerptsAsks.length, 2, "a review's lines are read once for all its places");
  assert.deepEqual(notes(d), ["The change's side", "Main's side: lines the change deleted", 'Before the fix: lines the fix deleted'],
    'a cited deleted line is shown beside the staged one, a line a fix round deleted as the fix\'s, not as main\'s');
  assert.deepEqual(texts(d), ['2 two\n3 three', '2 deleted two', '2 fixed away']);
  d = await open(rows()[0]);
  await settle();
  assert.deepEqual(texts(d), ['2 old two\n3 old three'], "an earlier review shows its own lines, not a later review's of the same place");
  d = await open(rows()[3]);
  await settle();
  assert.deepEqual(notes(d), ['The review kept no lines for this place.']);
  d = await open(panel(w, 'needs').querySelector('li[data-key="blocked:c2-13"] > details.block-more > details.output li.output-finding'));
  await settle();
  assert.deepEqual(texts(d), ['2 two\n3 three', '2 deleted two', '2 fixed away'], "a blocked card's output shows its last review's lines");
});
