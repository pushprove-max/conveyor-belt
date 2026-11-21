// SPDX-License-Identifier: Apache-2.0
// The Rules tab's push rule ("Push when a card lands"); on the Control tab's Board, what landed and is not pushed with
// Push landed, and the full test suite with Run full test suite and Push anyway; and a push that failed its check on
// Needs you. Shared setup: dashboard-view.helpers.mjs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { boot, deliver, next, settle, full, act, rulesP, ruled, panel, board, pushP } from './dashboard-view.helpers.mjs';

const A = 'a'.repeat(40);
const RED = { time: '2026-11-14T08:00:00Z', id: '0123456789ab', kind: 'run', push: true, sha: A, state: 'failed', exit: 1, pushed: null, cases: [
  { case: 'code.test: breaks', line: 'FAIL [breaks]: off', runs: ['failed', 'failed', 'failed'], verdict: 'fix', why: null, issue: 101, reused: false },
  { case: 'flaky.test: flips', line: 'FAIL [flips]: at random', runs: ['passed', 'passed', 'passed'], verdict: 'flaky', why: 'failed in the full test suite, passed alone 3 of 3', issue: null, reused: false },
  { case: 'net.test: fetch', line: 'FAIL [fetch]: refused', runs: ['failed', 'failed', 'failed'], verdict: 'declined', why: 'outside the code: the machine or the network: ECONNREFUSED', issue: null, reused: false },
] };
// The Rules part with the push rule as given; the Board part with the landed cards origin lacks and the full test's state.
function data({ push = true, unpushed = [{ card: 'c1-7', issue: 7, since: '2026-11-14T07:00:00Z' }, { card: 'c2-8', issue: 8, since: '2026-11-14T07:30:00Z' }],
  fullTest = { command: true, why: null, running: null, last: null } } = {}) {
  const d = full(), r = d.panels.rules.data;
  r.control = { ...r.control, rules: { ...r.control.rules, ...(push === 'none' ? {} : { push }) } }; // none: a record from before the rule
  Object.assign(d.panels.board.data, { unpushed, fullTest });
  return d;
}
const row = (w, k) => ruled(w).querySelector(`[data-rule="${k}"]`);
// The Board's Push landed and Full test suite, each with what it acts on, in their own panel.
const part = (w, k) => pushP(w).querySelector(`[data-push="${k}"]`);
const sent = async (w, fn) => { fn(); await settle(); return w.posts.splice(0).map((p) => p.body); };

// Bugs this guards: the rule could not be set from the Board, or an engine that does not know it was sent it.
test('Rules: Push when a card lands, on by default, is turned off and on from its row', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data());
  assert.deepEqual(['push-on', 'push-off'].map((a) => act(rulesP(w), a).getAttribute('aria-pressed')), ['true', 'false'], 'on: Conveyor pushes each card when it lands');
  assert.match(row(w, 'push').textContent, /Conveyor pushes each card when it lands/);
  assert.equal(row(w, 'push').querySelector('.rules-off'), null, 'on: nothing says what Off means');
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'push-on').click()), [], 'the choice in force sends nothing');
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'push-off').click()), [{ action: 'rules', args: ['push=off'], repo: 'sample' }]);
  next(w, data({ push: false }));
  assert.deepEqual(['push-on', 'push-off'].map((a) => act(rulesP(w), a).getAttribute('aria-pressed')), ['false', 'true']);
  // Bug (UX38): the words under the name described the Off state while Off was set, so name and words said opposite
  // things. They describe the switch by its name whatever is set; what Off means shows beside it, only while Off.
  assert.equal(row(w, 'push').querySelector('.rules-what').textContent, 'Conveyor pushes each card when it lands');
  assert.equal(row(w, 'push').querySelector('.rules-off').textContent, 'off: land only: cards land on main, and Push landed on the Control tab pushes them');
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'push-on').click()), [{ action: 'rules', args: ['push=on'], repo: 'sample' }]);
  // A record with no rules.push is an engine that does not know the rule: neither choice is sent.
  const old = boot({ tab: 'rules' });
  deliver(old, data({ push: 'none' }));
  assert.ok(act(rulesP(old), 'push-on').disabled && act(rulesP(old), 'push-off').disabled, 'an older engine is sent neither');
  assert.match(row(old, 'push').textContent, /needs a newer Conveyor/);
});

// Bugs this guards: the owner could not see what landed and is not pushed, nor push it from the Board behind a test
// run; and (UX38) Push landed and Run full test suite sat among the Rules tab's switches, in their style, as if they
// were settings saved on touch: they are on the Control tab's Board, and the Rules tab has neither.
test('Control: the landed cards not pushed are counted and named, and Push landed asks for the run that pushes them', async () => {
  const w = boot({ tab: 'control' });
  deliver(w, data({ push: false }));
  assert.match(part(w, 'landed').textContent, /2 landed, not pushed/);
  assert.deepEqual(Array.from(part(w, 'landed').querySelectorAll('.board-push-item'), (x) => x.textContent), ['#7', '#8']);
  assert.equal(act(pushP(w), 'push-landed').disabled, false);
  assert.equal(part(w, 'landed').querySelector('.board-push-why'), null, 'a button that can work gives no reason');
  // A full run costs time (issue 407): each button acts on a second click, the first saying what it does.
  assert.deepEqual(await sent(w, () => act(pushP(w), 'push-landed').click()), [], 'the first click only asks');
  assert.equal(act(pushP(w), 'push-landed').textContent, 'Click again to run the full suite, then push');
  assert.deepEqual(await sent(w, () => act(pushP(w), 'push-landed').click()), [{ action: 'full-test', args: ['push'], repo: 'sample' }]);
  // Nothing landed to push: Push landed is off, and says why.
  next(w, data({ unpushed: [] }));
  assert.match(part(w, 'landed').textContent, /0 landed, not pushed/);
  assert.equal(act(pushP(w), 'push-landed').disabled, true);
  assert.equal(part(w, 'landed').querySelector('.board-push-why').textContent, 'Cannot work now: nothing that landed waits for a push.');
  // Run full test suite runs it and pushes nothing.
  assert.deepEqual(await sent(w, () => act(pushP(w), 'full-test').click()), [], 'the first click only asks');
  assert.deepEqual(await sent(w, () => act(pushP(w), 'full-test').click()), [{ action: 'full-test', args: [], repo: 'sample' }]);
  // The Rules tab has neither action, nor their rows.
  const r = boot({ tab: 'rules' });
  deliver(r, data());
  for (const a of ['push-landed', 'full-test', 'push-anyway']) assert.equal(act(rulesP(r), a), null, `the Rules tab has no ${a}`);
  assert.equal(ruled(r).querySelector('[data-rule="landed"], [data-rule="full-test"]'), null);
});

// Bugs this guards (issue 25): with the push rule off, the only way to push what landed was Push landed, behind a whole
// suite run; Push now, beside it, pushes with no run, on a second click, and is off with its reason when it cannot work.
test('Control: Push now sits beside Push landed, sends push-now on a second click, and needs no full test suite', async () => {
  const w = boot({ tab: 'control' });
  deliver(w, data({ push: false }));
  const btns = Array.from(part(w, 'landed').querySelectorAll('button'), (b) => b.dataset.act);
  assert.equal(btns.indexOf('push-now'), btns.indexOf('push-landed') + 1, `Push now is next to Push landed: ${btns}`);
  assert.equal(act(pushP(w), 'push-now').disabled, false);
  assert.equal(act(pushP(w), 'push-now').dataset.guard, 'final', 'a push cannot be undone');
  assert.deepEqual(await sent(w, () => act(pushP(w), 'push-now').click()), [], 'the first click only asks');
  assert.equal(act(pushP(w), 'push-now').textContent, 'Click again to push now, with no full suite run');
  assert.deepEqual(await sent(w, () => act(pushP(w), 'push-now').click()), [{ action: 'push-now', args: [], repo: 'sample' }]);
  // No test.full: Push landed is off, Push now still works (it runs no suite).
  next(w, data({ fullTest: { command: false, why: 'the pack names no full test suite (test.full)', running: null, last: null } }));
  assert.ok(act(pushP(w), 'push-landed').disabled && !act(pushP(w), 'push-now').disabled, 'Push now needs no full test suite');
  // A full run under way, or nothing to push: off, with the reason (the host refuses both too).
  next(w, data({ fullTest: { command: true, why: null, running: { since: '2026-11-14T08:00:00Z', sha: A, how: 'push' }, last: null } }));
  assert.equal(act(pushP(w), 'push-now').disabled, true);
  assert.match(part(w, 'landed').querySelector('.board-push-why').textContent, /a full test run is under way/);
  next(w, data({ unpushed: [] }));
  assert.equal(act(pushP(w), 'push-now').disabled, true);
  assert.equal(part(w, 'landed').querySelector('.board-push-why').textContent, 'Cannot work now: nothing that landed waits for a push.');
});

// Bugs this guards (issue 1078): for the whole pre-push hook the Board showed nothing of the push, so a slow push could
// not be told from a stuck one; a push whose process was gone, a failed push and a Push now that left main ahead of the
// remote looked the same. Under the Push buttons: the hook running with its commit, process, elapsed time and newest
// line; a stale push with its log; a failure with its failed test and log; main still ahead.
test('Control: the push in progress shows its hook, time and newest line; a stale or failed push and main still ahead say so', () => {
  const w = boot({ tab: 'control' }), log = '/s/pushlogs/1.log', state = () => part(w, 'landed').querySelector('.board-push-state');
  const with_ = (o) => { const d = data(); Object.assign(d.panels.board.data, o); return d; };
  deliver(w, with_({ pushing: { pid: 42, since: '2026-11-14T08:00:00Z', sha: A, log, sec: 9, line: '3/9 passed', stale: false }, pushLast: null }));
  assert.equal(state().dataset.state, 'running');
  assert.match(state().textContent, new RegExp(`^Pre-push hook running on ${A.slice(0, 12)} since .+ · pid 42 · .+3/9 passedLog: ${log}$`));
  assert.ok(state().querySelector('time.since'), 'the elapsed time keeps counting');
  // Review of issue 1078: the Board said the hook ran while the tests before the push ran and after the remote held the commit.
  // It said so too while the push waited for its test slot, and after git push ended.
  for (const [stage, what] of [['tests', 'Tests before the push running'], ['ready', 'Getting the push ready \\(worktree, dependencies, test slot\\)'],
    ['push', 'Push running with no pre-push hook'], ['ended', 'git push ended, finishing the push'], ['pushed', 'Pushed, waiting for GitHub']]) {
    next(w, with_({ pushing: { pid: 42, since: '2026-11-14T08:00:00Z', sha: A, stage, log, sec: 9, line: '', stale: false }, pushLast: null }));
    assert.match(state().textContent, new RegExp(`^${what} on ${A.slice(0, 12)} since `), stage);
  }
  // Issue 1279: a push whose hook wrote nothing showed only its stage, so the owner could not see which cards it
  // carried nor how long the whole push had run (the stage's time starts again at each stage).
  next(w, with_({ pushing: { pid: 42, since: '2026-11-14T08:01:30Z', started: '2026-11-14T08:00:00Z', sha: A, stage: 'push', log, sec: 9, line: null, stale: false,
    cards: [{ card: 'c7-7', issue: 7 }, { card: 'c-red', issue: 0 }] }, pushLast: null }));
  assert.match(state().textContent, /Cards in this push: #7, c-red · Push started .+ · .+Log: /, 'a push with no hook output names its cards and its start');
  // Both keep counting, the stage's from since and the whole push's from started: a timer on the wrong one shows the other's time.
  assert.deepEqual([...state().querySelectorAll('time.since')].map((t) => t.dataset.since), ['2026-11-14T08:01:30Z', '2026-11-14T08:00:00Z'],
    'the stage counts from since and the whole push from started');
  next(w, with_({ pushing: { pid: 42, since: '2026-11-14T08:00:00Z', sha: A, log, sec: 9, line: '3/9 passed', stale: true }, pushLast: null }));
  assert.equal(state().textContent, `The push on ${A.slice(0, 12)} is stale: its process (pid 42) is gone and the push did not end.Log: ${log}`);
  next(w, with_({ pushing: null, pushLast: { time: '2026-11-14T08:00:00Z', by: 'now', started: true, sha: A, ok: false, ahead: 1, check: 'fast-checks', log } }));
  assert.equal(state().dataset.state, 'failed');
  assert.match(state().textContent, new RegExp(`^Push now on ${A.slice(0, 12)} failed: fast-checks failed\\. .+ agoLog: ${log}Main is still 1 commit ahead of the remote\\.$`));
  next(w, with_({ pushing: null, pushLast: { time: '2026-11-14T08:00:00Z', by: 'now', started: false, why: 'the push lock could not be taken', sha: null, ok: false, ahead: 2 } }));
  assert.match(state().textContent, /^Push now started no push: the push lock could not be taken\. .+ agoMain is still 2 commits ahead of the remote\.$/);
});

// Bugs this guards: a project with no full test suite was offered both buttons, and a second press during a run started
// another (the host refuses it too; its refusal is shown); (UX38) the reason sat under both buttons while neither
// looked off: each button is disabled, and says why beside it in a sentence.
test('Control: no test.full, or a run under way, turns both buttons off with the reason', async () => {
  const w = boot({ tab: 'control' });
  deliver(w, data({ fullTest: { command: false, why: 'the pack names no full test suite (test.full)', running: null, last: null } }));
  assert.ok(act(pushP(w), 'push-landed').disabled && act(pushP(w), 'full-test').disabled, 'both are off');
  // In the Board's words, never the setting's file key (issue 415).
  for (const k of ['landed', 'full-test']) assert.equal(part(w, k).querySelector('.board-push-why').textContent, 'Cannot work now: this project has no full test suite set up for Conveyor.');
  next(w, data({ fullTest: { command: true, why: null, running: { since: '2026-11-14T08:00:00Z', sha: A, how: 'push' }, last: null } }));
  assert.ok(act(pushP(w), 'push-landed').disabled && act(pushP(w), 'full-test').disabled, 'one run at a time');
  assert.match(part(w, 'full-test').textContent, new RegExp(`running on ${A.slice(0, 12)}, to push it if green`));
  assert.match(part(w, 'landed').textContent, /a full test run is under way/);
  // A press the host refuses (a run another page started) shows the host's words.
  next(w, data());
  w.reply = { ok: false, status: 409, text: () => Promise.resolve('conveyor: a full test run is already running (push, since 2026-11-14T08:00:00Z); this one is not started') };
  act(pushP(w), 'full-test').click(); act(pushP(w), 'full-test').click(); await settle();
  assert.match(pushP(w).querySelector('.board-note').textContent, /^Not done: conveyor: a full test run is already running/);
});

// Bugs this guards: a red run did not say what failed and what was done with each case; Push anyway pushed with no
// confirm, or one that did not name the failed cases, or was sent without the id of the red run the confirm named (the
// host then pushed over whichever red run was last, one with cases the owner was not shown). Issue 407: it asked in a
// browser dialog, unlike every other guard on the page; now its second click's words name the cases.
test('Control: a red run lists each failed case and its outcome, and Push anyway asks first, naming them', async () => {
  const w = boot({ tab: 'control' });
  deliver(w, data({ push: false, fullTest: { command: true, why: null, running: null, last: RED } }));
  const box = part(w, 'full-test').querySelector('.board-push-last');
  assert.equal(box.dataset.state, 'failed');
  assert.match(box.textContent, new RegExp(`Failed on ${A.slice(0, 12)}: 3 cases failed, and Conveyor pushed nothing\\. When main is green, press Push landed again\\.`));
  assert.deepEqual(Array.from(box.querySelectorAll('.board-push-case'), (x) => [x.dataset.verdict, x.textContent]), [
    ['fix', 'code.test: breaksfix card #101'],
    ['flaky', 'flaky.test: flipsflaky: passed alone every time'],
    ['declined', 'net.test: fetchdeclined: outside the code: the machine or the network: ECONNREFUSED'],
  ]);
  w.confirm = () => { throw new Error('no browser dialog'); };
  assert.equal(act(pushP(w), 'push-anyway').dataset.guard, 'final', 'a push cannot be undone');
  assert.deepEqual(await sent(w, () => act(pushP(w), 'push-anyway').click()), [], 'the first click sends nothing');
  assert.equal(act(pushP(w), 'push-anyway').textContent, 'Click again: push 2 landed cards over a red suite, with no new run. These cases failed: code.test: breaks, flaky.test: flips, net.test: fetch.');
  assert.deepEqual(await sent(w, () => act(pushP(w), 'push-anyway').click()), [{ action: 'full-test', args: ['anyway', '0123456789ab'], repo: 'sample' }]);
  // A red run line with no id to name offers no Push anyway (the host would refuse it).
  next(w, data({ fullTest: { command: true, why: null, running: null, last: { ...RED, id: undefined } } }));
  assert.equal(act(pushP(w), 'push-anyway'), null);
  // Nothing landed to push, or a green run: no Push anyway.
  next(w, data({ unpushed: [], fullTest: { command: true, why: null, running: null, last: RED } }));
  assert.equal(act(pushP(w), 'push-anyway'), null);
  next(w, data({ fullTest: { command: true, why: null, running: null, last: { ...RED, state: 'passed', exit: 0, cases: [], pushed: { ok: true, reason: null } } } }));
  assert.equal(act(pushP(w), 'push-anyway'), null);
  assert.match(part(w, 'full-test').textContent, new RegExp(`Passed on ${A.slice(0, 12)}; pushed ${A.slice(0, 12)}`));
  // The push over a red suite is shown as the owner's.
  next(w, data({ fullTest: { command: true, why: null, running: null, last: { ...RED, kind: 'anyway', by: 'Board user owner', pushed: { ok: true, reason: null } } } }));
  assert.match(part(w, 'full-test').textContent, new RegExp(`Board user owner pushed over a red suite: pushed ${A.slice(0, 12)}`));
});

// Bug this guards (#44): a Push landed or Run full test suite that reused an earlier whole-suite run read as a whole
// suite run, so the owner could not tell that no test ran, or that only some files reran.
test('Control: a run that reused an earlier run says "Reused the green run of" its time and commit, or how many files reran', () => {
  const w = boot({ tab: 'control' });
  const green = { ...RED, state: 'passed', exit: 0, cases: [], pushed: { ok: true, reason: null } };
  deliver(w, data({ fullTest: { command: true, why: null, running: null, last: { ...green, reused: { sha: A, time: '2026-11-14T07:40:00Z', ran: [], kept: 3 } } } }));
  const scope = () => part(w, 'full-test').querySelector('[data-figure="suite-scope"]');
  assert.match(scope().textContent, new RegExp(`^Reused the green run of \\d.* on ${A.slice(0, 12)}$`));
  next(w, data({ fullTest: { command: true, why: null, running: null, last: { ...green, reused: { sha: 'b'.repeat(40), time: '2026-11-14T07:40:00Z', ran: ['t/f1.test.sh'], kept: 2 } } } }));
  assert.equal(scope().textContent, 'Reran 1 file, reused 2 passed files from bbbbbbbbbbbb');
  next(w, data({ fullTest: { command: true, why: null, running: null, last: { ...green, reused: null } } }));
  assert.equal(scope(), null, 'a whole suite run names no reuse');
});

// Bugs this guards: a push that failed its check reached the owner only after a retry failed too, and Needs you then
// said the loop pushes again by itself, which it does not until a fix lands on main. It is listed at its first failure
// (the snapshot's push item with check) with the check's name, its failing lines, and what moves it on.
test('Needs you: a push that failed its check names the check, shows its failing lines and says a fix on main moves it on', () => {
  const w = boot();
  const d = full();
  d.panels.needs.data.cards.blocked.push({ repo: 'sample', card: 'c9-15', issue: 15, title: 'Pay page', since: '2026-11-14T08:00:00Z', push: true, check: 'typecheck-web',
    reason: 'push blocked: typecheck-web failed after #15; a retry fails the same way, so the push waits for a fix to land on main; not pushed: #15',
    tail: "exit 1 (124 is the 600s timeout): web/pay.ts(3,7): error TS2322: Type 'string' is not assignable to type 'number'.\npush-checks: FAILED typecheck-web\nerror: failed to push some refs to 'origin'" });
  deliver(w, d);
  const item = panel(w, 'needs').querySelector('li[data-key="blocked:c9-15"]');
  // Issue 407: it leads with one plain sentence; the reason as recorded is shown whole, with no tap (no hover on a phone).
  assert.equal(item.querySelector('.why-said').textContent, 'Push refused: the check typecheck-web failed');
  assert.equal(item.querySelector('.why-block details'), null, 'the whole reason is shown, not folded');
  assert.match(item.querySelector('.why-block .why-full').textContent, /^push blocked: typecheck-web failed after #15; a retry fails the same way/);
  assert.deepEqual(Array.from(item.querySelectorAll('.output-fails li'), (x) => x.textContent), [
    "exit 1 (124 is the 600s timeout): web/pay.ts(3,7): error TS2322: Type 'string' is not assignable to type 'number'.", 'push-checks: FAILED typecheck-web', "error: failed to push some refs to 'origin'"]);
  assert.equal(item.querySelector('.hint').textContent, 'Land a fix for typecheck-web on main. Conveyor then pushes again by itself. It does not retry until main moves.');
  assert.equal(item.querySelector('button[data-act="retry"]'), null, 'its card has landed: nothing to retry');
});
