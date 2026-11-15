// SPDX-License-Identifier: Apache-2.0
// Issue 407, from the Board's user-experience audit: Needs you is the one home for what needs the owner, every
// button that changes real work follows one guard rule, every action shows its result at once, a blocked card leads
// with why it failed, and a push failing while it is tried again is said under Needs you's tick. Each case names the
// bug it catches. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { boot, panel, deliver, next, settle, full, trackOf, counts, board, bcard, act, note, record, rulesP, clone, cases, pickProject } from './dashboard-view.helpers.mjs';
const test = cases(import.meta.url);

const blockedRow = (w, card = 'c2-13') => panel(w, 'needs').querySelector(`li[data-key="blocked:${card}"]`);
// A blocked card's lines, in order, from the first under its head: what the owner reads first.
const lines = (li) => Array.from(li.children).slice(1).map((x) => (x.tagName === 'DETAILS' ? x.querySelector('summary').textContent : x.textContent));

// Bug: a blocked card's headline was where it stopped ("Failed at Test (step 3 of 6)"); the cause was in hover text,
// in "Every step" or behind "Show output", or raw tool output cut off after about 90 letters before the part that says
// what broke; and the advice was a command ("conveyor.sh retry 12") beside the Retry button.
test('Needs you: a blocked card leads with why it failed in one sentence, then what Retry does; the whole reason opens on a tap', () => {
  const w = boot();
  const d = full();
  const tests = trackOf('+++!..', '', {
    records: [{ name: 'tests failed', state: 'failed', sec: 90, failures: { of: 41, files: [{ file: 'web/pay.test.ts', cases: [{ name: 'pays once', line: 'FAIL [pays once]: expected 1, got 2' }, { name: 'refunds', line: '' }] }], timeout: null } }],
  });
  Object.assign(d.panels.needs.data.cards.blocked[0], { reason: 'tests: the changed tests failed again after their one fix round (exit 1); nothing landed.\nFAIL web/pay.test.ts', track: tests, tail: 'FAIL web/pay.test.ts' });
  const review = trackOf('+!....', '');
  d.panels.needs.data.cards.blocked.push({ repo: 'sample', card: 'c3-14', issue: 14, title: 'Pay page', url: null, since: d.panels.needs.data.cards.blocked[0].since,
    reason: 'review: three rounds said NO-GO; the card stops', track: review, reviews: [1, 2, 3].map((round) => ({ round, verdict: 'NO-GO', counts: counts(0, 1, 0, 0) })) });
  deliver(w, d);
  const t = blockedRow(w);
  assert.deepEqual(lines(t).slice(0, 3), ['2 tests failed: pays once, refunds', 'Retry puts #13 back in the queue, and a new card builds it in its turn.', 'Show output'],
    'the reason first, what Retry does second, the output one click below');
  const why = t.querySelector('details.why');
  assert.equal(why.open, false);
  assert.match(why.querySelector('.why-full').textContent, /^tests: the changed tests failed again after their one fix round \(exit 1\); nothing landed\.\nFAIL web\/pay\.test\.ts$/, 'the reason as recorded, whole, on a tap');
  assert.equal(t.querySelector('.stopped').textContent, 'Failed at Test (step 4 of 6)', 'where it stopped comes after');
  assert.match(t.textContent, /Fix the cause\. Then press Retry\./);
  assert.doesNotMatch(panel(w, 'needs').textContent, /conveyor\.sh/, 'no command where a button does it');
  assert.equal(lines(blockedRow(w, 'c3-14'))[0], 'Review asked for changes three times');
});

// Bug: a card whose tests failed, and whose fix of them then failed ("fix: …"), led with the earlier run's failing
// test names, as if they were why it stopped; and Control's blocked card had no track or reviews to name them at all.
test('Needs you and Control: a blocked card leads with why it stopped, not with an earlier test run\'s names', () => {
  const track = trackOf('+++!..', '', {
    records: [{ name: 'tests failed', state: 'failed', sec: 90, failures: { of: 41, files: [{ file: 'web/pay.test.ts', cases: [{ name: 'pays once', line: '' }] }], timeout: null } },
      { name: 'stopped', state: 'failed', sec: 5, why: 'fix: the session ended with no commit.' }],
  });
  const w = boot();
  const d = full();
  Object.assign(d.panels.needs.data.cards.blocked[0], { reason: 'fix: the session ended with no commit.', track });
  deliver(w, d);
  assert.equal(lines(blockedRow(w))[0], 'fix: the session ended with no commit.', 'the fix that failed is the cause');
  // Control's column, from the Board's own part: the same sentence as Needs you, from its track.
  const c = boot({ tab: 'control' });
  const e = full();
  Object.assign(e.panels.board.data.blocked[0], { reason: 'tests: the changed tests failed again after their one fix round (exit 1); nothing landed.', track: { ...track, records: track.records.slice(0, 1) } });
  deliver(c, e);
  assert.equal(bcard(c, 13).querySelector('.why-said').textContent, '1 test failed: pays once');
});

// Bug: a card whose first review said NO-GO and whose second review session then failed ("review 2: review failed
// (exit 3; …)", track at Review) led with "Review said NO-GO once", hiding that the review itself broke.
test('Needs you and Control: a review session that failed after an earlier NO-GO leads with its own failure', () => {
  const reason = 'review 2: review failed (exit 3; 124 is the 900s timeout)\nerror: the model refused';
  const blocked = { reason, track: trackOf('+!....', ''), reviews: [{ round: 1, verdict: 'NO-GO', counts: counts(0, 1, 0, 0) }] };
  const w = boot();
  const d = full();
  Object.assign(d.panels.needs.data.cards.blocked[0], blocked);
  deliver(w, d);
  assert.equal(lines(blockedRow(w))[0], 'review 2: review failed (exit 3; 124 is the 900s timeout)');
  const c = boot({ tab: 'control' });
  const e = full();
  Object.assign(e.panels.board.data.blocked[0], blocked);
  deliver(c, e);
  assert.equal(bcard(c, 13).querySelector('.why-said').textContent, 'review 2: review failed (exit 3; 124 is the 900s timeout)');
});

// Bug: raw tool output was the headline, cut at the card's edge ("Push failed: exit 1 (124 is t…" on a phone) before
// the part that says what broke. A reason with no known shape leads with its first sentence, cut at a word.
test('Needs you: a long reason with no known shape leads with its first sentence, cut at a word, and keeps the rest on a tap', () => {
  const w = boot();
  const d = full();
  const long = `build: the session ended with no commit ${'and it said nothing more about the files it read '.repeat(4)}before it stopped. It ran 41 minutes.`;
  Object.assign(d.panels.needs.data.cards.blocked[0], { reason: long });
  deliver(w, d);
  const said = blockedRow(w).querySelector('.why-said').textContent;
  assert.ok(said.length <= 141 && said.endsWith('…') && long.startsWith(said.slice(0, -1)), `cut at a word: ${said}`);
  assert.equal(blockedRow(w).querySelector('.why-full').textContent, long);
});

// Bug: with a push failing and being retried, Health said "Failing" while Needs you showed a green tick and "Nothing
// needs you", and the card was on the belt and in Landed today at once (the collector's side is dashboard.test.sh).
test('Needs you: with nothing to answer, a push failing while it is retried is said under the tick, with its fix card', () => {
  const quiet = () => {
    const d = full();
    Object.assign(d.panels.needs.data, { cards: { waiting: [], blocked: [], before: [], pipeline: [] }, tests: [], engines: [], decisions: [] });
    return d;
  };
  const w = boot();
  const d = quiet();
  d.panels.needs.data.retrying = [{ repo: 'sample', card: 'c4-65', issue: 65, title: 'Pay page', url: null, fix: 69 }];
  deliver(w, d);
  assert.equal(panel(w, 'needs').dataset.state, 'empty');
  assert.match(panel(w, 'needs').textContent, /Nothing needs you/);
  assert.equal(panel(w, 'needs').querySelector('.needs-retrying').textContent, 'Nothing needs you. One push fails, and Conveyor tries again. A fix card (#69) is on the belt.');
  const two = quiet();
  two.panels.needs.data.retrying = [{ repo: 'sample', card: 'c4-65', issue: 65, fix: null }, { repo: 'widgetshop', card: 'c5-7', issue: 7, fix: null }];
  next(w, two);
  assert.equal(panel(w, 'needs').querySelector('.needs-retrying').textContent, 'Nothing needs you. 2 pushes fail, and Conveyor tries again.');
  next(w, quiet());
  assert.equal(panel(w, 'needs').querySelector('.needs-retrying'), null, 'nothing failing: the tick alone');
});

// Bug: Hold, Release and Move acted on one click with no way back, and their line said "within a minute" where
// others said "with the next snapshot" or "at the next reading". Each now acts on one click; its line says "in about a
// minute" and has Undo, which sends the opposite change once.
test('the Board: Hold, Queue, Move and Pause act on one click, and the line that says so has Undo', async () => {
  const w = boot({ tab: 'control' });
  const d = full();
  deliver(w, d);
  const undo = async (body) => { act(board(w), 'undo').click(); await settle(); assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { ...body, repo: 'sample' } }]); };
  act(bcard(w, 21), 'hold').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'hold', args: ['21'], repo: 'sample' } }]);
  // The build machine's reply is shown only when the action failed (issue 415).
  assert.equal(note(w), 'Done. The Board shows it in about a minute. Undo');
  await undo({ action: 'release', args: ['21'] });
  // Release is "Queue", the one word for an issue joining the queue.
  assert.equal(act(bcard(w, 76), 'release').textContent, 'Queue');
  w.reply = record({ held: [] });
  act(bcard(w, 76), 'release').click();
  await settle();
  w.posts.splice(0);
  assert.equal(note(w), 'Done. The Board shows it in about a minute. Undo');
  w.reply = null;
  await undo({ action: 'hold', args: ['76'] });
  // A move: Undo sends the order as the record had it.
  next(w, full());
  const was = (d.panels.board.data.control.order || []).map(String);
  act(bcard(w, 22), 'up').click();
  await settle();
  assert.equal(w.posts.splice(0)[0].body.action, 'order');
  await undo({ action: 'order', args: was });
  act(board(w), 'pause').click();
  await settle();
  w.posts.splice(0);
  await undo({ action: 'resume', args: [] });
  assert.equal(act(board(w), 'stop').dataset.guard, undefined, 'Stop now has its own second click');
  assert.ok(act(board(w), 'stop').classList.contains('btn-final'), 'and looks like a button that cannot be undone');
});

// Bug: Undo was sent to the project on screen when it was pressed: a card held in one project, another project
// picked, and Undo released that number in the other project. On the Board it goes to the project the change was made
// in; on Rules it is refused until that project is picked again.
// picked, and Undo released that number in the other project. It goes to the project the change was made in; on
// Rules, it is sent once that project is picked again. This file tests the Undo of .claude/dashboard/panels/rules.js
// too, so a change to it selects this file (.conveyor/test-changed.sh).
test('the Board and Rules: Undo pressed after another project is picked goes to the project the change was made in', async () => {
  const two = () => {
    const d = full();
    d.panels.machine.data.repos = ['sample', 'widgetshop'];
    Object.assign(d.panels.board.data, { repos: ['sample', 'widgetshop'], others: { widgetshop: { ...clone(d.panels.board.data), repo: 'widgetshop' } } });
    Object.assign(d.panels.rules.data, { repos: ['sample', 'widgetshop'], others: { widgetshop: { ...clone(d.panels.rules.data), repo: 'widgetshop' } } });
    return d;
  };
  // The one project picker, Show in the machine head (issue 408).
  const pick = (w) => pickProject(w, 'widgetshop');
  const w = boot({ tab: 'control' });
  deliver(w, two());
  act(bcard(w, 21), 'hold').click();
  await settle();
  w.posts.splice(0);
  pick(w, board(w));
  act(board(w), 'undo').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'release', args: ['21'], repo: 'sample' } }]);
  const r = boot({ tab: 'rules' });
  deliver(r, two());
  act(rulesP(r), 'judge-on').click();
  await settle();
  r.posts.splice(0);
  pick(r, rulesP(r));
  // Rules does not send it from another project (issue 448): it says which project to pick, and sends nothing.
  act(rulesP(r), 'undo').click();
  await settle(); await settle();
  // Rules refuses it rather than sending it (issue 448): nothing goes to widgetshop, and the line says where to undo it.
  assert.deepEqual(r.posts.splice(0), [], 'nothing is sent to the project on screen');
  assert.equal(rulesP(r).querySelector('.rules-note').textContent, 'Not done: that Undo is for sample; pick it to undo the change there.');
  assert.deepEqual(r.posts.splice(0), []);
  assert.equal(rulesP(r).querySelector('.rules-note').textContent, 'Not done: that Undo is for sample; pick it to undo the change there.');
  // With that project picked again, its last change's Undo goes to it.
  pickProject(r, 'sample');
  act(rulesP(r).querySelector('.rules-top .rules-last'), 'undo').click();
  await settle(); await settle();
  assert.deepEqual(r.posts.splice(0), [{ url: 'control', body: { action: 'judge', args: ['off'], repo: 'sample' } }]);
});

// Bug: a project's Pause said "The page shows it at the next reading" and could not be taken back from the line.
test('the machine: a project paused here says "in about a minute", and Undo resumes it', async () => {
  const w = boot({ tab: 'control' });
  deliver(w, full());
  const sec = () => panel(w, 'machine').querySelector('.project[data-project="sample"]');
  act(sec(), 'pause').click();
  await settle(); await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'pause', args: [], repo: 'sample' } }]);
  assert.equal(sec().querySelector('.project-note').textContent, 'Paused. The page shows it in about a minute. Undo');
  assert.equal(act(sec(), 'pause'), null, 'the button gives way to the line while the change waits for the loop');
  act(sec(), 'undo').click();
  await settle(); await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'resume', args: [], repo: 'sample' } }]);
});

// Bug: five labels sent an issue to the queue (Release, Build this, Queue again, Queue all, Build anyway) and "Build
// this" in Declined meant "file this finding as an issue". The visible words now say Queue for every one, and File as
// issue for the finding; none of the old words is on any tab.
test('every tab: one word, Queue, for an issue joining the queue, and File as issue in Declined', async () => {
  const d = full();
  d.panels.needs.data.cards.pipeline = [{ repo: 'sample', issue: 41, title: 'a slow gate', cost: 'not assessed', parent: 30, since: d.panels.needs.data.cards.waiting[0].since, url: null }];
  d.panels.rules.data.control = { ...d.panels.rules.data.control, depGuard: false };
  for (const tab of ['overview', 'control', 'rules']) {
    const w = boot({ tab });
    deliver(w, d);
    if (tab === 'rules') { const open = act(rulesP(w), 'waits-open'); if (open && !open.disabled) open.click(); await settle(); }
    const words = Array.from(w.document.querySelectorAll('#grid button'), (b) => b.textContent);
    for (const old of ['Release', 'Build this', 'Queue again', 'Build anyway']) assert.ok(!words.some((x) => x === old || x.startsWith(`${old} `)), `${tab}: no "${old}" button: ${words.join(' | ')}`);
    if (tab === 'overview') assert.ok(words.includes('Queue') && words.includes('File as issue'), `${tab}: ${words.join(' | ')}`);
    if (tab === 'control') assert.ok(words.includes('Queue'), `${tab}: ${words.join(' | ')}`);
    if (tab === 'rules') assert.ok(words.includes('Queue all') && words.includes('Queue anyway'), `${tab}: ${words.join(' | ')}`);
  }
});
