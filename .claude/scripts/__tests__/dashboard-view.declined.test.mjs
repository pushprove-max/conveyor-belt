// SPDX-License-Identifier: Apache-2.0
// The Declined panel: what an F<n> of the judge's reason means; when a line leaves the panel; "Dismiss all shown (n)".
// Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { T0, iso, boot, panel, deliver, next, settle, full, tick, P, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const FINDINGS = [{ n: 1, finding: '[P1] a.txt:2 reads the old word. Proof: a.txt:2 still says it' }, { n: 2, finding: '[P1] a.txt:2 the old word again. Proof: none new' }];
const line = (over) => ({ repo: 'sample', id: 'd00000000000a', time: iso(T0 - 60000), card: 'c3-63', issue: 63, url: `${P}/63`, finding: '[P1] a.txt:2 the old word again',
  by: 'judge', why: 'the same as F1, so this is F1 again with nothing new', built: null, dismissed: null, round: 2, findings: FINDINGS, ...over });
const rowOf = (w, finding) => Array.from(panel(w, 'declined').querySelectorAll('.rows > .row')).find((r) => r.querySelector('.title').textContent === finding);

// Bug: the judge's "this is F1 again" names a finding by its place in the review, and nothing on the panel says which
// finding that is or which review it was in.
test("Declined: an F1 in the judge's reason shows the card's first finding of that review, with its round, on hover and on click", () => {
  const w = boot();
  const data = full();
  data.panels.declined.data.lines = [line()];
  deliver(w, data);
  const row = rowOf(w, '[P1] a.txt:2 the old word again');
  const reason = row.querySelector('.reason');
  assert.equal(reason.textContent, 'Why: the same as F1, so this is F1 again with nothing new', 'the reason reads as the judge wrote it');
  const refs = Array.from(reason.querySelectorAll('button[data-act="finding"]'));
  assert.deepEqual(refs.map((b) => b.textContent), ['F1', 'F1']);
  const says = 'F1, review round 2: [P1] a.txt:2 reads the old word.';
  assert.equal(refs[0].title, says, 'hover: its file and line, its first sentence and its round');
  const said = row.querySelector('.finding-said');
  assert.equal(said.hidden, true, 'nothing is opened before a click');
  refs[1].click();
  assert.equal(said.hidden, false);
  assert.equal(said.textContent, says, 'click: the same, under the reason');
  assert.equal(refs[1].getAttribute('aria-expanded'), 'true');
  refs[1].click();
  assert.equal(said.hidden, true, 'a second click hides it');
  assert.equal(refs[1].getAttribute('aria-expanded'), 'false');
});

// Bugs: an F<n> whose finding is not in the card's records links to another finding, or is dropped from the reason;
// a reason not the judge's has its F<n> turned into a finding of a review it never read.
test('Declined: an F<n> with no matching finding is shown as written, with "finding not found" on hover', () => {
  const w = boot();
  const data = full();
  data.panels.declined.data.lines = [line({ why: 'F3 said it first; F1 is another', findings: FINDINGS }),
    line({ id: 'd00000000000b', finding: '[P2] b.txt:1 lost round', why: 'this is F1 again', round: null, findings: null }),
    line({ id: 'd00000000000c', finding: '[P2] c.txt:1 by the owner', by: 'owner', why: 'not F1', round: null, findings: null })];
  deliver(w, data);
  const first = rowOf(w, '[P1] a.txt:2 the old word again').querySelector('.reason');
  assert.equal(first.textContent, 'Why: F3 said it first; F1 is another');
  const missing = first.querySelector('.finding-ref.is-missing');
  assert.equal(missing.textContent, 'F3');
  assert.equal(missing.title, 'finding not found');
  assert.equal(missing.tagName, 'SPAN', 'nothing to open');
  assert.deepEqual(Array.from(first.querySelectorAll('button[data-act="finding"]'), (b) => b.textContent), ['F1'], 'the F<n> that is found still opens');
  const lost = rowOf(w, '[P2] b.txt:1 lost round').querySelector('.reason');
  assert.equal(lost.textContent, 'Why: this is F1 again');
  assert.equal(lost.querySelector('.is-missing').title, 'finding not found', 'a line whose review was not found');
  assert.equal(rowOf(w, '[P2] b.txt:1 lost round').querySelector('.finding-said'), null);
  const owner = rowOf(w, '[P2] c.txt:1 by the owner').querySelector('.reason');
  assert.equal(owner.textContent, 'Why: not F1');
  assert.equal(owner.querySelector('.finding-ref'), null, "the owner's reason is not the judge's numbering");
});

// Audit UX14. Bug: a line left the panel 7 days after its time with no word before, and said "More than 7 days old"
// only after it had gone. An open line with 2 days or less left says when it goes; one with more, or one dismissed or
// filed (it has already left), says nothing of it.
test('Declined: an open line with 2 days or less left says "Expires in …" before it leaves the panel; others do not', () => {
  const w = boot({ query: '?declined=all' });
  const data = full();
  const DAY = 86400000;
  data.panels.declined.data.lines = [line({ id: 'd00000000001a', finding: '[P2] soon.txt:1 going', time: iso(T0 - 5.5 * DAY) }),
    line({ id: 'd00000000001b', finding: '[P2] fresh.txt:1 staying', time: iso(T0 - 3 * DAY) })];
  data.panels.declined.data.rest = [line({ id: 'd00000000001c', finding: '[P2] gone.txt:1 dismissed', time: iso(T0 - 6 * DAY), dismissed: { time: iso(T0 - DAY), by: 'owner' } }),
    line({ id: 'd00000000001d', finding: '[P2] filed.txt:1 filed', time: iso(T0 - 6 * DAY), built: 91 })];
  deliver(w, data);
  const expires = (f) => rowOf(w, f).querySelector('.expires')?.textContent ?? null;
  assert.equal(expires('[P2] soon.txt:1 going'), 'Expires in 1 d 12 h');
  assert.equal(expires('[P2] fresh.txt:1 staying'), null, 'more than 2 days left: no note');
  assert.equal(expires('[P2] gone.txt:1 dismissed'), null, 'a dismissed line has already left');
  assert.equal(expires('[P2] filed.txt:1 filed'), null, 'a filed line has already left');
});

// Audit UX14. Bug: a line is unchanged in the snapshot until it leaves, and the Board does not draw a panel again for
// an unchanged part, so a line that crossed into its last 2 days with the page open never said it was going, and a
// note shown counted nothing down. The clock alone, with no new snapshot, brings the note in and moves it on.
test('Declined: the clock brings in "Expires in …" when a line comes within 2 days of leaving, and counts it down', () => {
  const w = boot();
  const data = full();
  const DAY = 86400000, HOUR = 3600000;
  data.panels.declined.data.lines = [line({ id: 'd00000000003a', finding: '[P2] later.txt:1 going later', time: iso(T0 - 4.5 * DAY) })];
  deliver(w, data);
  const expires = () => rowOf(w, '[P2] later.txt:1 going later').querySelector('.expires')?.textContent ?? null;
  assert.equal(expires(), null, '2 days 12 h left: no note yet');
  tick(w, 0.5 * DAY + HOUR);
  assert.equal(expires(), 'Expires in 1 d 23 h', 'within 2 days now: the note comes with no new snapshot');
  tick(w, 12 * HOUR);
  assert.equal(expires(), 'Expires in 1 d 11 h', 'and counts down');
});

// Audit UX14. Bugs: "Dismiss all shown" carried no count and looked like "Show every line", the harmless button
// beside it, and took every line on one click. It is in the heading, coloured as a warning, names its count and sends
// on a second click; a click armed for some lines never sends others: when a snapshot brings a new line between the
// two clicks, the button disarms and names the new count, and sends nothing until clicked twice again.
test('Declined: "Dismiss all shown (n)" sits in the heading as a warning, asks once, and never dismisses lines its count did not name', async () => {
  const w = boot();
  const data = full();
  deliver(w, data);
  const all = () => panel(w, 'declined').querySelector('.panel-head button[data-act="dismiss-all"]');
  assert.equal(all().textContent, 'Dismiss all shown (1)');
  assert.ok(all().classList.contains('btn-warn'), 'coloured as a warning');
  assert.ok(!panel(w, 'declined').querySelector('button[data-act="declined-all"]').classList.contains('btn-warn'), 'Show every line is not');
  all().click();
  await settle();
  assert.equal(w.posts.length, 0, 'the first click only asks');
  assert.equal(all().textContent, 'Click again to dismiss the line for good', 'the second click names that it cannot be undone (issue 407)');
  assert.equal(all().getAttribute('aria-pressed'), 'true');
  assert.match(panel(w, 'declined').querySelector('.foot .answer-note').textContent, /Click again to dismiss the line shown/);
  // A new line arrives before the second click.
  const more = full();
  more.panels.declined.data.lines.unshift(line({ id: 'd00000000002a', finding: '[P2] new.txt:1 a new line', round: null, findings: null, by: 'owner', why: 'not now' }));
  next(w, more);
  assert.equal(all().textContent, 'Dismiss all shown (2)', 'disarmed, with the new count');
  all().click();
  await settle();
  assert.equal(w.posts.length, 0, 'the click after the change only asks again');
  all().click();
  await settle();
  assert.deepEqual(w.posts.splice(0).flatMap((p) => p.body.args).sort(), ['d00000000002a', 'd0123456789ab']);
  assert.equal(all(), null, 'nothing left to dismiss: no button in the heading');
});

// Issue 141. Bug: a main-red fix card has no issue (issue 0), so its declined lines, opened from its declined count,
// said "Showing the line of #0 only"; the note and the line's head show the card's name.
test('Declined: a main-red fix card\'s lines are shown by its name, never as "#0"', () => {
  const w = boot({ query: '?declined=c9-mainred' });
  const data = full();
  data.panels.declined.data.lines = [line({ card: 'c9-mainred', issue: 0, name: 'Main is red (0123456789ab)', url: null })];
  deliver(w, data);
  const text = panel(w, 'declined').textContent;
  assert.match(text, /Showing the line of Main is red \(0123456789ab\) only/);
  assert.doesNotMatch(text, /#0\b/);
  assert.equal(rowOf(w, '[P1] a.txt:2 the old word again').querySelector('.issue').textContent, 'Main is red (0123456789ab)');
});
