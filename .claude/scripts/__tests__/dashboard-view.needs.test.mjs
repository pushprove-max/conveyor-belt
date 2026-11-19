// SPDX-License-Identifier: Apache-2.0
// Issue 407, from the Board's user-experience audit: Needs you is the one home for what needs the owner, every
// button that changes real work follows one guard rule, every action shows its result at once, a blocked card leads
// with why it failed, and a push failing while it is tried again is said under Needs you's tick. Each case names the
// bug it catches. Shared setup: dashboard-view.helpers.mjs. A page loads only the panels its case reads (boot's
// `list`): it then evaluates and draws fewer panel scripts than a page of every panel; the every-tab cases load each
// tab's own.
import assert from 'node:assert/strict';
import { boot, panel, deliver, next, settle, full, trackOf, counts, board, loopP, bcard, act, note, record, rulesP, clone, cases, pickProject, P, LIST, TAB } from './dashboard-view.helpers.mjs';
const test = cases(import.meta.url);

const blockedRow = (w, card = 'c2-13') => panel(w, 'needs').querySelector(`li[data-key="blocked:${card}"]`);
// A blocked card's lines, in order, from the first under its head: what the owner reads first.
const lines = (li) => Array.from(li.children).slice(1).map((x) => (x.tagName === 'DETAILS' ? x.querySelector('summary').textContent : x.textContent));

// Bug: a blocked card's headline was where it stopped ("Failed at Test (step 3 of 6)"); the cause was in hover text,
// in "Every step" or behind "Show output", or raw tool output cut off after about 90 letters before the part that says
// what broke; and the advice was a command ("conveyor.sh retry 12") beside the Retry button.
test('Needs you: a blocked card leads with why it failed in one sentence and its first failing test; the rest is one click below', () => {
  const w = boot({ list: ['needs'] });
  const d = full();
  const tests = trackOf('+++!..', '', {
    records: [{ name: 'tests failed', state: 'failed', sec: 90, failures: { of: 41, files: [{ file: 'web/pay.test.ts', cases: [{ name: 'pays once', line: 'FAIL [pays once]: expected 1, got 2' }, { name: 'refunds', line: 'FAIL [refunds]: expected 0, got 1' }] }], timeout: null } }],
  });
  Object.assign(d.panels.needs.data.cards.blocked[0], { reason: 'tests: the changed tests failed again after their one fix round (exit 1); nothing landed.\nFAIL web/pay.test.ts', track: tests, tail: 'FAIL web/pay.test.ts' });
  const review = trackOf('+!....', '');
  d.panels.needs.data.cards.blocked.push({ repo: 'sample', card: 'c3-14', issue: 14, title: 'Pay page', url: null, since: d.panels.needs.data.cards.blocked[0].since,
    reason: 'review: three rounds said NO-GO; the card stops', track: review, reviews: [1, 2, 3].map((round) => ({ round, verdict: 'NO-GO', counts: counts(0, 1, 0, 0) })) });
  d.panels.needs.data.cards.blocked.push({ repo: 'sample', card: 'c4-15', issue: 15, title: 'Pay rules', url: `${P}/15`, since: d.panels.needs.data.cards.blocked[0].since,
    reason: 'build: `make pay` failed at web/pay.ts:12. Nothing landed.' });
  deliver(w, d);
  const t = blockedRow(w);
  assert.equal(lines(t)[0], '2 tests failed: pays once, refunds', 'the reason first');
  assert.equal(t.querySelector('details.why'), null, 'the explanation is not folded');
  // Bug #472: the failing cases and their first failure lines were behind a tap; the first is shown.
  const cases = (el) => Array.from(el.querySelectorAll('.why-block .test-case'), (x) => x.textContent);
  assert.deepEqual(cases(t.querySelector(':scope > .why-block')), ['pays onceexpected 1, got 2'], 'the first failing case, with its first failure line, without a click');
  // Bug #501: the rest of it pushed the buttons down; it is one click below them, what Retry does, then the output.
  const more = t.querySelector(':scope > details.block-more');
  assert.deepEqual(cases(more), ['pays onceexpected 1, got 2', 'refundsexpected 0, got 1'], 'every failing case in the full reason');
  assert.deepEqual(lines(more).slice(1, 3), ['Retry puts #13 back in the queue, and a new card builds it in its turn.', 'Show output']);
  assert.equal(more.querySelector('.stopped').textContent, 'Failed at Test (step 4 of 6)', 'where it stopped comes after');
  assert.doesNotMatch(panel(w, 'needs').textContent, /conveyor\.sh/, 'no command where a button does it');
  assert.equal(lines(blockedRow(w, 'c3-14'))[0], 'Review asked for changes three times');
  // Bug #437: a blocked card's reason showed its raw backticks and its file paths as plain text, unlike a declined
  // finding's reason: its code span and path are set apart, the path links to its line, and the whole reason is in a
  // block labelled "Why it blocked, in full".
  const f = blockedRow(w, 'c4-15'), href = `https://github.com/example/sample-project/blob/HEAD/web/pay.ts#L12`;
  const code = (el) => Array.from(el.querySelectorAll('code.why-code'), (c) => c.textContent);
  assert.deepEqual(code(f.querySelector('.why-said')), ['make pay', 'web/pay.ts:12'], 'the lead sentence sets its code and path apart');
  assert.equal(f.querySelector('.why-said a').getAttribute('href'), href, "the lead sentence's path links to its line");
  const box = f.querySelector('.why-block');
  assert.equal(box.querySelector('.why-label').textContent, 'Why it blocked, in full');
  assert.deepEqual(code(box.querySelector('.why-full')), ['make pay', 'web/pay.ts:12'], 'the whole reason sets its code and path apart');
  assert.equal(box.querySelector('.why-full a').getAttribute('href'), href, "the whole reason's path links to its line");
  assert.equal(box.querySelector('.why-full').textContent, 'build: make pay failed at web/pay.ts:12. Nothing landed.', 'the reason as written, without its backticks');
});

// Bug #472: a blocked card showed "Review asked for changes twice" and kept the unresolved finding behind a tap. The
// finding is shown with its level, linked place, claim and proof; a reason over 12 lines shows 12 and "Show all".
test('Needs you: a review block shows its unresolved finding, and a long reason shows 12 lines and Show all', () => {
  const w = boot({ list: ['needs'] });
  const d = full(), b = d.panels.needs.data.cards.blocked, since = b[0].since;
  b[0].reason = 'the fix for [P1] [E1] conveyor/lib/card.sh:52 The loop never stops. Proof: it spins on `x` did not hold after 1 round';
  b.push({ repo: 'sample', card: 'c5-16', issue: 16, title: 'T16', url: `${P}/16`, since, reason: Array.from({ length: 30 }, (_, i) => `line ${i + 1}`).join('\n') });
  deliver(w, d);
  const f = blockedRow(w).querySelector(':scope > .why-block .output-finding');
  assert.equal(f.querySelector('.chip').textContent, 'P1', 'the level badge');
  assert.equal(f.querySelector('.finding-at a').getAttribute('href'), 'https://github.com/example/sample-project/blob/HEAD/conveyor/lib/card.sh#L52', 'the place links to its line');
  assert.equal(f.querySelector('.finding-claim').textContent, 'The loop never stops.');
  assert.equal(f.querySelector('.finding-proof-text').textContent, 'it spins on x', 'the proof, without a click');
  const long = blockedRow(w, 'c5-16'), shown = () => long.querySelector('.why-full').textContent.split('\n').length;
  assert.equal(shown(), 12, 'the first 12 lines');
  long.querySelector('.show-all').click();
  assert.equal(shown(), 30, 'Show all shows the rest');
  assert.equal(long.querySelector('.show-all'), null);
});

// Bug #501: a blocked row showed every finding with its full proof, where it stopped, its track and its reviews before
// its next step and buttons, so the owner scrolled to act on each card. The first finding, the next step and Retry
// come first; the other findings are in one closed <details> under them, which a new part leaves as the owner set it.
test('Needs you: a blocked card shows its first finding, next step and Retry before one <details> with the other findings, kept open through a new part', () => {
  const w = boot({ list: ['needs'] });
  const d = full();
  d.panels.needs.data.cards.blocked[0].reason = 'the fix for [P1] a.sh:1 First wrong. Proof: p1 holds. The long rest of the proof.\n[P2] b.sh:2 Second wrong. Proof: p2\n[P2] c.sh:3 Third wrong. Proof: p3 did not hold after 1 round';
  deliver(w, d);
  const t = blockedRow(w), more = t.querySelector(':scope > details.block-more');
  const first = t.querySelector(':scope > .why-block .output-finding'), step = t.querySelector(':scope > .block-step'), retry = t.querySelector(':scope > .answer button[data-act="retry"]');
  assert.equal(first.querySelector('.finding-claim').textContent, 'First wrong.');
  assert.equal(first.querySelector('.finding-proof-text').textContent, 'p1 holds.', 'the first sentence of its proof above the buttons');
  const order = [first, step, retry, more];
  order.slice(1).forEach((x, i) => assert.ok(order[i].compareDocumentPosition(x) & w.Node.DOCUMENT_POSITION_FOLLOWING, `${order[i].className} comes before ${x.className}`));
  const claims = (el) => Array.from(el.querySelectorAll('.finding-claim'), (x) => x.textContent);
  assert.deepEqual(claims(more).slice(1), ['Second wrong.', 'Third wrong.'], 'the second and third findings are in the <details>');
  assert.equal(more.querySelector('.finding-proof-text').textContent, 'p1 holds. The long rest of the proof.', 'with the full proof');
  assert.deepEqual(Array.from(t.querySelectorAll('.finding-claim')).filter((x) => !more.contains(x)).map((x) => x.textContent), ['First wrong.'], 'and not above it');
  assert.equal(more.open, false, 'closed at first');
  more.open = true;
  // The new part says the host took its Retry: the row's key changes, so the row is drawn anew (a part equal to the
  // last one is not drawn at all, and a row of the same key is reused, so neither proves the state is carried).
  d.panels.needs.data.retried = [{ repo: 'sample', card: 'c2-13', issue: 13 }];
  next(w, d);
  const again = blockedRow(w, 'c2-13:retried');
  assert.notEqual(again, t, 'the row is drawn anew');
  assert.equal(again.querySelector(':scope > details.block-more').open, true, 'a new part for the same card keeps it open');
});

// Bug #456: every block ended "Fix the cause. Then press Retry.", though for a review, test or no-result block Retry is
// the fix and nothing on the Board fixes anything first. Each kind's last line names its step; the review block's
// finding holds words of other kinds ("sign-in", "depends on"), which do not change its kind.
test('Needs you: a blocked card\'s last line names the step its kind of block takes', () => {
  const w = boot({ list: ['needs'] });
  const d = full(), b = d.panels.needs.data.cards.blocked, since = b[0].since;
  const add = (card, issue, reason) => b.push({ repo: 'sample', card, issue, title: `T${issue}`, url: `${P}/${issue}`, since, reason });
  b.length = 0;
  add('c1-21', 21, 'the fix for [P1] web/pay.ts:3 the total depends on the sign-in state did not hold after 2 rounds');
  add('c1-22', 22, 'tests: the changed tests failed again after their one fix round (exit 1); nothing landed.\nFAIL sign-in.test.ts');
  add('c1-23', 23, 'its process ended without a result in its build step');
  add('c1-24', 24, "build: Claude Code's own sign-in expired (exit 1): run claude /login, then conveyor.sh control resume");
  deliver(w, d);
  const step = (card) => blockedRow(w, card).querySelector('.block-step').textContent;
  const retry = 'Retry: a new session gets the open finding (or the failing tests) and starts from the kept work.';
  assert.equal(step('c1-21'), retry, 'a review block: Retry is the fix');
  assert.doesNotMatch(blockedRow(w, 'c1-21').textContent, /Fix the cause/, 'nothing to fix before Retry on a review block');
  assert.equal(step('c1-22'), retry, 'a test block: Retry is the fix');
  assert.equal(step('c1-23'), retry, 'a no-result block: Retry is the fix');
  assert.equal(step('c1-24'), 'Sign in again on the build machine, as the reason says. Then press Retry.', 'a sign-in block: what to do, then Retry');
  // Bug: these two got the fallback, which told the owner to wait for the conflict to clear (Retry ports the kept
  // patch while it stands) and gave a review's NO-GO of ALREADY-DONE no review step. (Five rows show at a time.)
  b.length = 0;
  add('c1-25', 25, 'rebase onto main conflicts: error: patch failed: a.txt:1');
  add('c1-26', 26, 'the session made no change and said that main already fixes the issue. The reviewer says that main does not do what the issue asks. [P1] a.txt:1 wrong word');
  add('c1-27', 27, 'push: the remote refused the branch.');
  next(w, d);
  assert.equal(step('c1-25'), 'Retry: a new session brings the kept change onto main as it is now.', 'a landing conflict: Retry is the fix');
  // Bug: both promised kept work, which an ALREADY-DONE session, or a block before any change, does not leave.
  assert.equal(step('c1-26'), "Retry: a new session gets the reviewer's finding and builds the issue.", 'a review that rejects ALREADY-DONE is a review block, with no kept work');
  assert.match(step('c1-27'), /^Blocked because: .+\. Retry starts a new card, from the kept work if there is any\.$/, 'any other block names its reason');
  assert.doesNotMatch(step('c1-27'), /no longer stands|wait|first/i, 'the fallback asks for nothing before Retry');
});

// Bug #456: a card already retried stayed Blocked, with Retry, until its new card was picked (the snapshot that drops
// it can take long after a retry). Its own card in the retried records shows it waiting, with no Retry; an issue whose
// earlier card was retried and whose newer card blocked again stays Blocked.
test('Needs you: a blocked card its host gave back shows "Retried, waiting for its turn" and no Retry', () => {
  const w = boot({ list: ['needs'] });
  const d = full(), n = d.panels.needs.data;
  n.cards.blocked.push({ repo: 'sample', card: 'c5-14', issue: 14, title: 'Again', url: `${P}/14`, since: n.cards.blocked[0].since, reason: 'tests failed twice' });
  n.retried = [{ repo: 'sample', card: 'c2-13', issue: 13 }, { repo: 'sample', card: 'c4-14', issue: 14 }];
  deliver(w, d);
  const gone = panel(w, 'needs').querySelector('li[data-key="blocked:c2-13:retried"]');
  assert.ok(gone, 'the retried card is drawn as retried');
  assert.equal(gone.querySelector('.row-main .chip').textContent, 'Retried, waiting for its turn');
  assert.doesNotMatch(gone.querySelector('.row-main').textContent, /Blocked/);
  assert.equal(gone.querySelector('button[data-act="retry"]'), null, 'no Retry for a card already retried');
  const again = blockedRow(w, 'c5-14');
  assert.equal(again.querySelector('.row-main .chip').textContent, 'Blocked', 'a newer card of a retried issue is blocked');
  assert.ok(again.querySelector('button[data-act="retry"]'));
});

// Bug: a card whose tests failed, and whose fix of them then failed ("fix: …"), led with the earlier run's failing
// test names, as if they were why it stopped; and Control's blocked card had no track or reviews to name them at all.
test('Needs you and Control: a blocked card leads with why it stopped, not with an earlier test run\'s names', () => {
  const track = trackOf('+++!..', '', {
    records: [{ name: 'tests failed', state: 'failed', sec: 90, failures: { of: 41, files: [{ file: 'web/pay.test.ts', cases: [{ name: 'pays once', line: '' }] }], timeout: null } },
      { name: 'stopped', state: 'failed', sec: 5, why: 'fix: the session ended with no commit.' }],
  });
  const w = boot({ list: ['needs'] });
  const d = full();
  Object.assign(d.panels.needs.data.cards.blocked[0], { reason: 'fix: the session ended with no commit.', track });
  deliver(w, d);
  assert.equal(lines(blockedRow(w))[0], 'fix: the session ended with no commit.', 'the fix that failed is the cause');
  // Control's column, from the Board's own part: the same sentence as Needs you, from its track.
  const c = boot({ tab: 'control', list: ['board'] });
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
  const w = boot({ list: ['needs'] });
  const d = full();
  Object.assign(d.panels.needs.data.cards.blocked[0], blocked);
  deliver(w, d);
  assert.equal(lines(blockedRow(w))[0], 'review 2: review failed (exit 3; 124 is the 900s timeout)');
  const c = boot({ tab: 'control', list: ['board'] });
  const e = full();
  Object.assign(e.panels.board.data.blocked[0], blocked);
  deliver(c, e);
  assert.equal(bcard(c, 13).querySelector('.why-said').textContent, 'review 2: review failed (exit 3; 124 is the 900s timeout)');
});

// Bug: raw tool output was the headline, cut at the card's edge ("Push failed: exit 1 (124 is t…" on a phone) before
// the part that says what broke. A reason with no known shape leads with its first sentence, cut at a word.
test('Needs you: a long reason with no known shape leads with its first sentence, cut at a word, and shows the rest without a tap', () => {
  const w = boot({ list: ['needs'] });
  const d = full();
  const long = `build: the session ended with no commit ${'and it said nothing more about the files it read '.repeat(4)}before it stopped. It ran 41 minutes.`;
  Object.assign(d.panels.needs.data.cards.blocked[0], { reason: long });
  deliver(w, d);
  const said = blockedRow(w).querySelector('.why-said').textContent;
  assert.ok(said.length <= 141 && said.endsWith('…') && long.startsWith(said.slice(0, -1)), `cut at a word: ${said}`);
  assert.equal(blockedRow(w).querySelector('.why-full').textContent, long, 'the whole reason, shown without a tap');
});

// Bug: with a push failing and being retried, Health said "Failing" while Needs you showed a green tick and "Nothing
// needs you", and the card was on the belt and in Landed today at once (the collector's side is dashboard.test.sh).
test('Needs you: with nothing to answer, a push failing while it is retried is said under the tick, with its fix card', () => {
  const quiet = () => {
    const d = full();
    Object.assign(d.panels.needs.data, { cards: { waiting: [], blocked: [], before: [], pipeline: [] }, tests: [], engines: [], decisions: [] });
    return d;
  };
  const w = boot({ list: ['needs'] });
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
  const w = boot({ tab: 'control', list: ['board'] });
  const d = full();
  deliver(w, d);
  // at: the panel the action was done in, whose line has its Undo.
  const undo = async (body, at = board(w)) => { act(at, 'undo').click(); await settle(); assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { ...body, repo: 'sample' } }]); };
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
  act(loopP(w), 'pause').click();
  await settle();
  w.posts.splice(0);
  await undo({ action: 'resume', args: [] }, loopP(w));
  assert.equal(act(loopP(w), 'stop').dataset.guard, undefined, 'Stop now has its own second click');
  assert.ok(act(loopP(w), 'stop').classList.contains('btn-final'), 'and looks like a button that cannot be undone');
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
  const w = boot({ tab: 'control', list: ['machine', 'board'] });
  deliver(w, two());
  act(bcard(w, 21), 'hold').click();
  await settle();
  w.posts.splice(0);
  pick(w, board(w));
  act(board(w), 'undo').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'release', args: ['21'], repo: 'sample' } }]);
  const r = boot({ tab: 'rules', list: ['machine', 'rules'] });
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
  const w = boot({ tab: 'control', list: ['machine'] });
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
// issue for the finding; none of the old words is on any tab. One case a tab, each loading only its tab's panels (the
// grid's buttons are the same as with every panel loaded). Each case is its own test() line, as the Test step counts
// cases by those lines (.conveyor/test-changed.sh filecases()).
const queueWords = (tab) => async () => {
    const d = full();
    d.panels.needs.data.cards.pipeline = [{ repo: 'sample', issue: 41, title: 'a slow gate', cost: 'not assessed', parent: 30, since: d.panels.needs.data.cards.waiting[0].since, url: null }];
    d.panels.rules.data.control = { ...d.panels.rules.data.control, depGuard: false };
    const w = boot({ tab, list: LIST.filter((id) => TAB(id) === tab) });
    deliver(w, d);
    if (tab === 'rules') { const open = act(panel(w, 'rules-produce'), 'waits-open'); if (open && !open.disabled) open.click(); await settle(); }
    // The Release panel's "Release <version>" button makes a project release, and the Merge PR rule's "Release" choice
    // means the release merges the pull request: neither is a card joining the queue.
    const words = Array.from(w.document.querySelectorAll('#grid button')).filter((b) => !b.closest('#panel-release, [data-rule="pr-merge"]')).map((b) => b.textContent);
    for (const old of ['Release', 'Build this', 'Queue again', 'Build anyway']) assert.ok(!words.some((x) => x === old || x.startsWith(`${old} `)), `${tab}: no "${old}" button: ${words.join(' | ')}`);
    if (tab === 'overview') assert.ok(words.includes('Queue') && words.includes('File as issue'), `${tab}: ${words.join(' | ')}`);
    if (tab === 'control') assert.ok(words.includes('Queue'), `${tab}: ${words.join(' | ')}`);
    if (tab === 'rules') assert.ok(words.includes('Queue all') && words.includes('Queue anyway'), `${tab}: ${words.join(' | ')}`);
};
test('every tab (overview): one word, Queue, for an issue joining the queue, and File as issue in Declined', queueWords('overview'));
test('every tab (control): one word, Queue, for an issue joining the queue', queueWords('control'));
test('every tab (rules): one word, Queue, for an issue joining the queue', queueWords('rules'));
