// SPDX-License-Identifier: Apache-2.0
// A card's review step shows one findings list (#1374), from the record's review text. Shared setup:
// dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { T0, iso, boot, panel, deliver, next, trackOf, full, cases, openEvery, counts } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const at = (s) => iso(T0 - 1000000 + s * 1000);

const ACCEPTED = '[P3] .claude/dashboard/panels/belt.js:76 The label wraps. Proof: `tl-label` is narrow.';
const DECLINED = '[P2] .claude/scripts/__tests__/dashboard-local.test.sh:501 The retired-workflow check is too wide. Proof: it scans all files.';
const REASON = 'rare case, because the check names `one` word only.';
const TEXT = `${ACCEPTED}\nDECLINED: ${DECLINED} (judge: ${REASON})`;

// The Every step detail of a card whose review 1 is the given record, as the Board draws it.
function shown(rec) {
  const w = boot();
  const data = full();
  const card = data.panels.belt.data.cards[0];
  card.track = trackOf('+>....', 'review', { since: at(900), records: [
    { name: 'picked', state: 'done', sec: null, at: at(0) }, { name: 'review 1 (NO-GO)', state: 'done', sec: 60, at: at(10), ...rec },
    { name: 'fix 1', state: 'now', sec: null }] });
  deliver(w, data);
  const row = () => panel(w, 'belt').querySelector(`li[data-key="sample:${card.card}"]`);
  return { w, d: openEvery(w, row().querySelector('details.track-detail')), row, data };
}

// Bug it guards (#1374): the verdict chip, the findings count and the judge's counts were in the narrow label, five lines
// beside a thin bar; and a declined finding showed as one DECLINED: paragraph. Now the label is the name, one line holds
// the chips, and the findings are two rows, the declined one dimmed with the judge's reason in its own block.
test('a review with one accepted and one declined finding: name only in the label, one line of chips, two rows', () => {
  const { d } = shown({ output: TEXT, counts: counts(0, 0, 0, 1), judge: { ran: true, accepted: 1, declined: 1, go: false } });
  const item = Array.from(d.querySelectorAll('.timeline > li.tl-item')).find((li) => li.querySelector('.tl-label').textContent.startsWith('Review'));
  assert.equal(item.querySelector('.tl-label').textContent, 'Review 1', 'the label holds the name only');
  const line = item.querySelector(':scope > .tl-review');
  assert.deepEqual(Array.from(line.children, (c) => c.textContent), ['changes asked', '1 P3', 'judge: 1 accepted, 1 declined']);
  assert.equal(line.querySelector('button.judged-open').textContent, '1 declined', 'the declined count is the link');
  const rows = Array.from(item.querySelectorAll(':scope > .review-findings > .output-finding'));
  assert.equal(rows.length, 2, 'one row each, accepted and declined');
  assert.deepEqual(rows.map((r) => r.querySelector('.finding-head > .chip').textContent), ['P3', 'P2']);
  assert.equal(rows[0].classList.contains('is-declined'), false);
  assert.equal(rows[0].querySelector('.why-block'), null, 'an accepted finding has no reason block');
  assert.equal(rows[0].querySelector('.finding-text').textContent, 'The label wraps.');
  assert.equal(rows[0].querySelector('.finding-at').textContent, '.claude/dashboard/panels/belt.js:76');
  assert.ok(rows[0].querySelector('details.finding-lines'), 'Reviewed lines is kept');
  assert.equal(rows[1].classList.contains('is-declined'), true, 'the declined row is dimmed');
  assert.deepEqual(Array.from(rows[1].querySelectorAll('.finding-head > .chip'), (c) => c.textContent), ['P2', 'Declined']);
  assert.equal(rows[1].querySelector('.finding-text').textContent, 'The retired-workflow check is too wide.');
  assert.equal(rows[1].querySelector('details.finding-proof').open, false, 'its proof is under a toggle');
  const why = rows[1].querySelector('.why-block');
  assert.equal(why.querySelector('.why-label').textContent, 'Why the judge declined it');
  assert.equal(why.querySelector('.why-text').textContent, REASON.replaceAll('`', ''), 'the reason, its code span drawn without backticks');
  assert.equal(why.querySelector('code.why-code').textContent, 'one');
  // The raw text is under Show output, closed, in monospace; no DECLINED: paragraph is anywhere else.
  const out = item.querySelector(':scope > details.output');
  assert.equal(out.open, false);
  assert.equal(out.querySelector('pre.output-text').textContent, TEXT);
  const outside = Array.from(item.querySelectorAll('*')).filter((el) => !out.contains(el) && el.children.length === 0 && el.textContent.includes('DECLINED:'));
  assert.deepEqual(outside, [], 'no DECLINED: text outside Show output');
});

// Bug it guards (#1374): a review whose text holds no finding must keep showing its text under Show output.
test('a review with no parsed findings shows its text under Show output, and no list', () => {
  const { d } = shown({ output: 'The change looks right.\nNothing to report.' });
  const item = Array.from(d.querySelectorAll('.timeline > li.tl-item')).find((li) => li.querySelector('.tl-label').textContent.startsWith('Review'));
  assert.equal(item.querySelector('.review-findings'), null);
  assert.equal(item.querySelector('.tl-review').textContent, 'changes asked', 'the verdict still shows under the bar');
  const out = item.querySelector(':scope > details.output');
  assert.equal(out.open, false);
  assert.equal(out.querySelector('pre.output-text').textContent, 'The change looks right.\nNothing to report.');
});

// Bug it guards (#1374): a redraw of the card (a live update) drew the list again and closed a Proof the reader had opened.
test('an open Proof stays open when the card is drawn again', () => {
  const { w, d, row, data } = shown({ output: TEXT });
  const proof = d.querySelectorAll('.review-findings details.finding-proof')[1];
  proof.open = true;
  const card = data.panels.belt.data.cards[0];
  card.track.records.push({ name: 'fix 1', state: 'now', sec: null });
  next(w, data);
  const again = row().querySelectorAll('.review-findings details.finding-proof');
  assert.deepEqual(Array.from(again, (x) => x.open), [false, true]);
});

// Bug it guards (#1424): a real finding the judge found outside the card's change (an OUTSIDE: line) showed as no
// finding at all, or as declined, though the card files it as a follow-up; its row did not name the follow-up's issue,
// and a redraw after the filing kept the row drawn before it; before the card landed, the judge line and the row said
// the finding was filed already, though no follow-up existed yet.
test('a finding the judge found outside the change shows as filed as a follow-up, with its issue', () => {
  const OUT = '[P1] .claude/dashboard/panels/belt.js:12 The count skips the last card. Proof: open the Belt with two cards.';
  const why = 'real: the count is wrong on main; the card did not change belt.js.';
  const { w, row, data } = shown({ name: 'review 1 (GO)', output: `OUTSIDE: ${OUT} (judge: ${why})`, judge: { ran: true, accepted: 0, declined: 0, outside: 1, go: true } });
  const item = () => Array.from(row().querySelectorAll('.timeline > li.tl-item')).find((li) => li.querySelector('.tl-label').textContent.startsWith('Review'));
  const finding = () => item().querySelector(':scope > .review-findings > .output-finding');
  assert.equal(item().querySelector(':scope > .tl-review .judged').textContent, 'judge: 0 accepted, 0 declined, 1 outside the change', 'the judge line counts it apart from the declined, and not as filed before any filing');
  assert.equal(finding().classList.contains('is-declined'), false, 'it is not drawn as declined');
  assert.deepEqual(Array.from(finding().querySelectorAll('.finding-head > .chip'), (c) => c.textContent), ['P1', 'To be filed as a follow-up'], 'before the card lands');
  assert.equal(finding().querySelector('.why-block .why-label').textContent, 'Why the judge found it outside the change', 'the reason does not say it was filed before any filing');
  // The card lands: its filed line names the follow-up of the finding, and the redraw shows it.
  data.panels.belt.data.cards[0].track.records.push({ name: 'follow-ups filed', state: 'done', sec: 2, n: 1, outside: [{ finding: OUT, issue: 100101 }] });
  next(w, data);
  assert.deepEqual(Array.from(finding().querySelectorAll('.finding-head > .chip'), (c) => c.textContent), ['P1', 'Filed as a follow-up']);
  const link = finding().querySelector('.finding-head > .issue');
  assert.equal(link && link.textContent, '#100101', 'the row names the follow-up issue');
  assert.match(link.getAttribute('href') || '', /\/issues\/100101$/, 'and links it');
});

// Bug it guards (#1424): a retry that lands from a kept patch (after a yes) writes no review of its own and files the
// outside findings of the review it kept, so the filed line is on the retry and the review on its earlier attempt;
// that review's row still said "To be filed as a follow-up" after the filing.
test('an earlier attempt\'s outside finding names the follow-up the retry filed', () => {
  const OUT = '[P2] .claude/dashboard/panels/belt.js:12 The count skips the last card. Proof: open the Belt with two cards.';
  const w = boot();
  const data = full();
  const card = data.panels.belt.data.cards[0];
  const prior = { card: 'c3-60', start: iso(T0 - 3600000), end: iso(T0 - 2400000), sec: 1200, reason: 'waits for a yes', track: trackOf('++....', '', { at: null, since: null, records: [
    { name: 'picked', state: 'done', sec: null, at: at(0) },
    { name: 'review 1 (GO)', state: 'done', sec: 60, at: at(10), output: `OUTSIDE: ${OUT} (judge: real: the count is wrong on main.)`, judge: { ran: true, accepted: 0, declined: 0, outside: 1, go: true } }] }) };
  card.track = trackOf('+++++>', 'push', { since: at(900), records: [
    { name: 'picked', state: 'done', sec: null, at: at(100) }, { name: 'follow-ups filed', state: 'done', sec: 2, at: at(200), n: 1, outside: [{ finding: OUT, issue: 100102 }] }] });
  card.earlier = [prior];
  deliver(w, data);
  const det = openEvery(w, panel(w, 'belt').querySelector(`li[data-key="sample:${card.card}"] details.track-detail`));
  const finding = det.querySelector(':scope > details.tl-earlier .review-findings > .output-finding');
  assert.deepEqual(Array.from(finding.querySelectorAll('.finding-head > .chip'), (c) => c.textContent), ['P2', 'Filed as a follow-up'], 'the earlier attempt\'s review row');
  const link = finding.querySelector('.finding-head > .issue');
  assert.equal(link && link.textContent, '#100102', 'it names the issue the retry filed');
});
