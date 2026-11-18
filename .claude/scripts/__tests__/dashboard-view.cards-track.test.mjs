// SPDX-License-Identifier: Apache-2.0
// The dashboard page's cards, how a card moves along its steps: its row and track as its step changes, its Test step,
// its times, the step in progress, and its steps as bars on one time axis. The other cards-* files hold the rest of
// what was dashboard-view.cards.test.mjs, split so the runner runs them side by side. Shared setup:
// dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { css, read, LIST, T0, iso, clone, boot, panel, deliver, next, tick, P, STEPS, DETAIL, trackOf, timesOf, counts, full, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

// ---- motion: a card moves along its steps, numbers count, a new item draws the eye once ----
test('a card keeps its row and each step of its track as its step changes, so only what changed is redrawn', () => {
  const w = boot();
  deliver(w, full());
  const row = panel(w, 'belt').querySelector('li[data-key="sample:c3-63"]');
  const track = row.querySelector('ol.track6'), steps = Array.from(track.children);
  const marks = () => Array.from(track.children, (s) => ({ done: '+', now: '>', skipped: '-', failed: '!', todo: '.' }[s.dataset.state])).join('');
  const names = () => Array.from(track.children, (s) => s.querySelector('.step-name').textContent);
  assert.deepEqual(names(), ['Build', 'Review 2 of 3', 'Fix', 'Test', 'Land', 'Push'], 'the six steps, in order; a step that ran more than once shows its count');
  assert.equal(marks(), '+>+...');
  assert.equal(track.querySelector('[aria-current="step"]').querySelector('.step-name').textContent, 'Review 2 of 3');
  assert.equal(steps[0].getAttribute('aria-label'), 'Build: done, took 30 s', 'a state is never colour alone');
  assert.deepEqual(Array.from(track.children, (s) => s.querySelector('.step-mark').textContent), ['✓', '▶', '✓', '·', '·', '·'], 'each state has a mark of its own shape');
  assert.equal(steps[0].querySelector('.step-time').textContent, '30 s', 'a done step says how long it took');
  assert.equal(steps[1].querySelector('.step-time').textContent, '5 min', 'the step in progress, its running time');
  assert.deepEqual(Array.from(track.children, (s) => s.querySelector('.join').dataset.filled), ['true', 'true', 'true', 'false', 'false', 'false'], 'the joins fill as the card moves on');
  assert.ok(!row.classList.contains('enter'), 'the first cards do not animate in');
  // Every step a card can be at: Fix skipped after a GO; Build skipped for a card landed from a kept patch; a card
  // that landed and is being pushed has Land done and Push current; a failed push is Push failed with its reason.
  // A fix's pill names what started it from its steps (the test below); a track without them says Fix alone.
  for (const [m, label, over, pill] of [['>.....', 'building'], ['++>...', 'fix after review 1', {}, 'Fix'], ['++->..', 'tests'], ['++-+>.', 'landing'], ['-+-+>.', 'landing'],
    ['++-++>', 'pushing'], ['++-++!', 'push failed; it is tried again', { reason: 'pre-push hook refused' }], ['++-++>', 'waiting for GitHub to close the issue']]) {
    const data = full();
    data.panels.belt.data.cards[0].track = trackOf(m, label, over);
    next(w, data);
    const again = panel(w, 'belt').querySelector('li[data-key="sample:c3-63"]');
    assert.equal(again, row, `the card's row is the same element at ${label}`);
    assert.deepEqual(Array.from(track.children), steps, 'and so is each of its steps');
    assert.equal(marks(), m, `the track at ${label}`);
    assert.deepEqual(names().map((n) => n.replace(/ .*/, '')), STEPS, 'the order is Build, Review, Fix, Test, Land, Push at every step');
    assert.ok(row.querySelector('.row-main .chip').textContent.includes(pill || label[0].toUpperCase() + label.slice(1)));
  }
  // A failed push: Push failed, and why.
  assert.equal(track.children[5].dataset.state, 'now');
  const failed = full();
  failed.panels.belt.data.cards[0].track = trackOf('++-++!', 'push failed; it is tried again', { reason: 'pre-push hook refused' });
  next(w, failed);
  assert.equal(track.children[5].dataset.state, 'failed');
  assert.match(track.children[5].getAttribute('aria-label'), /^Push: failed: pre-push hook refused$/);
  assert.match(row.querySelector('.track-now').textContent, /Push failed: pre-push hook refused/);
  // A skipped Fix shows as skipped: its dash, struck through, and the word.
  const skipped = full();
  skipped.panels.belt.data.cards[0].track = trackOf('++->..', 'tests');
  next(w, skipped);
  assert.equal(track.children[2].dataset.state, 'skipped');
  assert.equal(track.children[2].querySelector('.step-mark').textContent, '–');
  assert.equal(track.children[2].getAttribute('aria-label'), 'Fix: skipped');
  // Every recorded step, on demand.
  const det = row.querySelector('details.track-detail');
  assert.equal(det.open, false);
  assert.deepEqual(Array.from(det.querySelectorAll('.timeline > li .tl-label'), (l) => l.textContent),
    ['Setup', 'Build', 'Review 1', 'Fix 1', 'Review 2', 'Fix 2', 'Review 3', 'Tests', 'Rebuild', 'Land', 'Push', 'Issue closed', 'Follow-ups filed'],
    'every recorded step but the queue, the set-up folded into one');
  assert.deepEqual(Array.from(det.querySelectorAll('.tl-parts li'), (li) => li.textContent.split(':')[0]), DETAIL.slice(1, 5));
  const data = full();
  data.panels.belt.data.cards.push({ repo: 'sample', card: 'c7-9', issue: 9, title: 'New card', url: `${P}/9`, step: 'odd-step', review: null, of: 3, stepAt: iso(T0), model: null, tokens: { claude: 0, codex: 0 }, usd: null, reading: true });
  next(w, data);
  const added = panel(w, 'belt').querySelector('li[data-key="sample:c7-9"]');
  assert.ok(added.classList.contains('enter'), 'a card that joins the belt comes in with motion');
  assert.equal(added.querySelector('.track6').hidden, true, 'a card whose snapshot gives no track shows none, and no step of the page\'s own guessing');
  assert.match(added.textContent, /Step: odd-step.*no AI model in this step.*not priced/);
  // A card in the Test step runs no model by design: its line says so, and does not read as an error.
  data.panels.belt.data.cards.push({ repo: 'sample', card: 'c8-10', issue: 10, title: 'Testing card', url: `${P}/10`, step: 'tests', review: null, of: 3, stepAt: iso(T0), model: null, tokens: { claude: 0, codex: 0 }, usd: null, reading: true });
  next(w, data);
  const testing = panel(w, 'belt').querySelector('li[data-key="sample:c8-10"]');
  assert.match(testing.querySelector('.row-meta').textContent, /running tests/);
  assert.doesNotMatch(panel(w, 'belt').textContent, /no model for this step/, 'no card reads as if its step lacked a model');
  data.panels.belt.data.cards.pop();
  data.panels.belt.data.cards.shift();
  next(w, data);
  assert.equal(panel(w, 'belt').querySelector('li[data-key="sample:c3-63"]'), null, 'a card that left the belt leaves the list');
});

// Issue 650: a fix the Done-when check on the build's reply started runs before the first review. Bug: the strip read
// Build ✓, Review 1 of 3 (running), Fix ✓, as if the fix came after the review. Its tracks are track.jq's for build,
// fix 1 (reply check), review 1 (running); the fix running; and build, review 1 (NO-GO), fix 1 (review findings), review 2.
test('a reply-check fix shows on the Build step, and Fix is ticked only for a fix after a review', () => {
  const w = boot();
  const row = () => panel(w, 'belt').querySelector('li[data-key="sample:c3-63"]');
  const strip = () => Array.from(row().querySelector('ol.track6').children, (s) => [s.querySelector('.step-mark').textContent, s.querySelector('.step-name').textContent]);
  const show = (marks, label, at, build, n) => {
    const data = full(), t = trackOf(marks, label, { at });
    t.steps[1].n = n[0]; t.steps[2].n = n[1];
    if (build) t.steps[0].replyFix = build;
    data.panels.belt.data.cards[0].track = t;
    next(w, data);
    return strip();
  };
  deliver(w, full());
  assert.deepEqual(show('+>....', 'review 1 of 3', 1, 'done', [1, 0]),
    [['✓', 'Build · reply check fixed'], ['▶', 'Review 1 of 3'], ['·', 'Fix'], ['·', 'Test'], ['·', 'Land'], ['·', 'Push']]);
  assert.match(row().querySelector('ol.track6').children[0].getAttribute('aria-label'), /^Build · reply check fixed: done/);
  assert.deepEqual(show('>.....', 'fix after review 0', 0, 'now', [0, 0]).slice(0, 3), [['▶', 'Build · reply check fix'], ['·', 'Review'], ['·', 'Fix']]);
  assert.deepEqual(show('+>+...', 'review 2 of 3', 1, null, [2, 1]).slice(0, 3), [['✓', 'Build'], ['▶', 'Review 2 of 3'], ['✓', 'Fix']]);
});

// Bug: a card in its Test step showed only its turns (always 0: a test run has no model) and when it last printed,
// and a run of one test file with 205 cases read "0 of 1" until it ended. Its live line and its "Every step" say how
// many tests have run of how many and how many failed (track.tests); with no case count, its test files (track.files).
test('a card in its Test step shows its tests run of how many and those failed, else its test files, and no turns', () => {
  const w = boot();
  const data = full(), c = data.panels.belt.data.cards[0];
  Object.assign(c, { step: 'tests', model: null, live: { turns: 4, lastOutputAt: iso(T0 - 4000), action: null } });
  c.track = trackOf('++-+..', 'tests', { at: 3, files: { run: 3, of: 6 }, tests: { done: 3, of: 5, failed: 1 } });
  c.track.steps[3].state = 'now';
  c.track.detail[11].state = 'now'; c.track.detailAt = 11;
  deliver(w, data);
  const row = () => panel(w, 'belt').querySelector('li[data-key="sample:c3-63"]');
  const live = () => row().querySelector('.track-now').textContent;
  const detail = () => Array.from(row().querySelectorAll('.track-detail .tl-tests'), (p) => p.textContent);
  assert.match(live(), /3 of 5 tests · 1 failed/, `the live line counts the tests: ${live()}`);
  assert.doesNotMatch(live(), /test files/, 'the files are not drawn beside the tests');
  assert.doesNotMatch(live(), /turn/, `a test run, which runs no model, shows no turns count: ${live()}`);
  assert.deepEqual(detail(), ['3 of 5 tests · 1 failed'], 'the step in progress in "Every step" says it too, once');
  const none = clone(data);
  none.panels.belt.data.cards[0].track.tests = { done: 2, of: 5, failed: 0 };
  next(w, none);
  assert.match(live(), /2 of 5 tests(?! ·)/, `no failed count while none failed: ${live()}`);
  const files = clone(data);
  files.panels.belt.data.cards[0].track.tests = null;
  next(w, files);
  assert.match(live(), /3 of 6 test files/, `with no case count, the test files: ${live()}`);
  assert.doesNotMatch(live(), /turn/);
  assert.deepEqual(detail(), ['3 of 6 test files']);
  // Bug (#15): a run of one file read "1 of 1 test files".
  const one = clone(files);
  one.panels.belt.data.cards[0].track.files = { run: 1, of: 1 };
  next(w, one);
  assert.match(live(), /1 of 1 test file(?!s)/, `one file is singular: ${live()}`);
  // Bug (#360): a run that ran more test files than it selected read "101 of 86". The engine counts it 86 of 86 with
  // over: the extra files are said apart.
  const over = clone(files);
  over.panels.belt.data.cards[0].track.files = { run: 86, of: 86, over: 15 };
  next(w, over);
  assert.match(live(), /86 of 86 test files · 15 more files than selected/, `the extra files are their own warning: ${live()}`);
  // A build session's turns are still drawn.
  const build = full();
  build.panels.belt.data.cards[0].live = { turns: 4, lastOutputAt: iso(T0 - 4000), action: null };
  next(w, build);
  assert.match(live(), /4 model replies/);
  assert.deepEqual(detail(), [], 'a card in no test run says nothing of tests');
});

// Bug it catches (#281): while a bug card's new tests ran on main's code without its fix (mainrun/<card>.unfixed.live),
// the Board named the review that comes after it ("Review 1 of 3", its Codex model) and no review ran. The snapshot
// gives that card as conveyor/tests/snapshot.test.sh t_snapproof checks: step proof, no review, its track on Build,
// labelled "proof run", with the run's files; the card says that step, its count and that tests run, not a review.
test("a bug card's proof run shows as its own step with its files run, not as a review", () => {
  const w = boot();
  const data = full(), c = data.panels.belt.data.cards[0];
  Object.assign(c, { step: 'proof', review: null, of: 3, model: null, live: null });
  c.track = trackOf('>.....', 'proof run', { at: 0, files: { run: 297, of: 1161 }, tests: null });
  c.track.detail[5].state = 'now'; c.track.detailAt = 5;
  deliver(w, data);
  const row = panel(w, 'belt').querySelector('li[data-key="sample:c3-63"]');
  const head = row.querySelector('.row-main').textContent, live = row.querySelector('.track-now').textContent;
  assert.match(head, /Proof run/, `the card names its step: ${head}`);
  assert.doesNotMatch(head, /Review/, `no review is named while none runs: ${head}`);
  assert.match(live, /297 of 1161 test files/, `the step says how far the run has got: ${live}`);
  assert.match(row.querySelector('.row-meta').textContent, /running tests/, 'the card runs tests, not an AI model');
  // Bug it catches (#281 review): a proof run that waits for a test slot (testrun.sh: its live action, files run 0)
  // read "running tests" though none ran. The snapshot gives that action as the card's live action.
  const wait = clone(data), wc = wait.panels.belt.data.cards[0];
  wc.live = { turns: 0, lastOutputAt: null, action: 'waiting for a test slot (2 of 2 in use)', at: iso(T0 - 4000) };
  wc.track.files = { run: 0, of: null };
  next(w, wait);
  const waiting = panel(w, 'belt').querySelector('li[data-key="sample:c3-63"]');
  assert.match(waiting.querySelector('.track-now').textContent, /now: waiting for a test slot \(2 of 2 in use\)/, 'the card says it waits for a slot');
  assert.doesNotMatch(waiting.querySelector('.row-meta').textContent, /running tests/, `no tests run while it waits: ${waiting.querySelector('.row-meta').textContent}`);
});

// Bug it catches (#147): a card's test step ran the whole suite or only the tests its change touched, and the Board
// did not say which, so a 20-minute step read as stuck. The live line gives the list the run was given (track.list:
// "changed: 7 files", "whole suite") and how many test files ran.
test('a card in its Test step shows whether it runs the changed tests or the whole suite, and how many files ran', () => {
  const w = boot();
  const data = full(), c = data.panels.belt.data.cards[0];
  Object.assign(c, { step: 'tests', model: null, live: { turns: 0, lastOutputAt: iso(T0 - 4000), action: null } });
  c.track = trackOf('++-+..', 'tests', { at: 3, files: { run: 2, of: null }, tests: null, list: { mode: 'changed', files: 7 } });
  c.track.steps[3].state = 'now';
  deliver(w, data);
  const live = () => panel(w, 'belt').querySelector('li[data-key="sample:c3-63"] .track-now').textContent;
  assert.match(live(), /changed: 7 files · 2 test files/, `the mode and the files run: ${live()}`);
  const whole = clone(data);
  whole.panels.belt.data.cards[0].track.list = { mode: 'whole', why: 'package.json: shared setup or config' };
  next(w, whole);
  assert.match(live(), /whole suite: package\.json: shared setup or config · 2 test files/, `the whole suite and why: ${live()}`);
  assert.doesNotMatch(live(), /changed:/);
});

// Bug it catches (#150): the Board did not say whether a card's tests came from the test map or were guessed by name,
// nor how old the map was, so a card that ran too few tests read like any other. The list's by and age say so.
test('a card in its Test step says whether its tests came from the test map or by name, and the map\'s age', () => {
  const w = boot();
  const data = full(), c = data.panels.belt.data.cards[0];
  Object.assign(c, { step: 'tests', model: null, live: { turns: 0, lastOutputAt: iso(T0 - 4000), action: null } });
  c.track = trackOf('++-+..', 'tests', { at: 3, files: { run: 2, of: null }, tests: null, list: { mode: 'changed', files: 3, by: 'map', age: 12 } });
  c.track.steps[3].state = 'now';
  deliver(w, data);
  const live = () => panel(w, 'belt').querySelector('li[data-key="sample:c3-63"] .track-now').textContent;
  assert.match(live(), /changed: 3 files \(map\) · map 12 commits old · 2 test files/, `from the map, with its age: ${live()}`);
  const byName = clone(data);
  byName.panels.belt.data.cards[0].track.list = { mode: 'changed', files: 1, by: 'name' };
  next(w, byName);
  assert.match(live(), /changed: 1 file \(by name\) · 2 test files/, `by name: ${live()}`);
  assert.doesNotMatch(live(), /map/);
});

// Bug: the running card's "now:" text wrapped onto a second and third line as the action streamed, so the card, the
// panel and the page grew and shrank under the reader. The line is one line high and cuts the text (app.css,
// .track-now): the cut text must still be readable in full, on hover, and the rule that keeps it to one line must hold.
test('the "now:" text carries its full action as its title and the step line never wraps', () => {
  const w = boot();
  const data = full(), action = `Reading ${'.claude/dashboard/panels/belt.js and app.css, '.repeat(9)}to the end`.slice(0, 400);
  data.panels.belt.data.cards[0].live = { turns: 4, lastOutputAt: iso(T0 - 4000), action };
  data.panels.belt.data.cards[0].track.reason = 'pre-push hook refused';
  deliver(w, data);
  const line = panel(w, 'belt').querySelector('li[data-key="sample:c3-63"] .track-now');
  const now = line.querySelector('.live-action');
  assert.equal(now.textContent, `now: ${action}`);
  assert.equal(now.title, action, 'the hover title holds the whole action, not the cut text');
  assert.equal(line.querySelector('.failed').title, 'Push failed: pre-push hook refused', 'a push failure, cut the same way, keeps its full text too');
  const rule = (sel) => (css.match(new RegExp(`(?:^|\\n)${sel.replace(/[.>]/g, (m) => `\\${m}`)}[^{]*\\{([^}]*)\\}`)) || [])[1] || '';
  assert.match(rule('.track-now'), /flex-wrap: nowrap/, 'the line\'s parts never wrap onto a second line');
  assert.match(rule('.track-now'), /white-space: nowrap/, 'no part\'s text wraps inside it');
  assert.match(rule('.track-now > .live-action'), /min-width: 0;[^}]*text-overflow: ellipsis/, 'the action shrinks to the width left and ends in "…"');
});

// The owner's audit of 186 test runs: one number held a test's wait for a slot and its run together, so nobody could
// say how long a card waited for a slot. A card's Test step shows the two apart where it shows the step's time; a
// track whose test lines give no split (recorded before it was) shows the one time as before.
test("a card's test time is drawn as its wait for a test slot and its run, apart", () => {
  const w = boot();
  const data = full();
  data.panels.belt.data.cards[0].track = trackOf('++-+>.', 'landing', {});
  Object.assign(data.panels.belt.data.cards[0].track.steps[3], { sec: 350, wait: 300, run: 45 });
  deliver(w, data);
  const step = () => panel(w, 'belt').querySelector('li[data-key="sample:c3-63"] ol.track6').children[3];
  assert.equal(step().querySelector('.step-time').textContent, 'wait 5 min · run 45 s');
  assert.equal(step().getAttribute('aria-label'), 'Test: done, wait 5 min · run 45 s','a screen reader hears the two apart too');
  const old = full();
  old.panels.belt.data.cards[0].track = trackOf('++-+>.', 'landing', {});
  next(w, old);
  assert.equal(step().querySelector('.step-time').textContent, '33 s', 'a test step with no split shows the time it took');
});

// No time is estimated from past cards. A card shows what was measured: the time in its
// step, the time each finished step took, when it was picked up and its overall time. The Tests page's "slower than
// usual" (#520) is no estimate: it compares a test file's measured runs with its own measured median. That median is
// the engine's "usual" (lib/testfiles.sh, the usual measure of lib/testrules.sh): the Tests page reads it as f.usual,
// sends it as 'usual' and names it "its usual" (#521). A card's usual time, or a bare "usual", still fails.
// Every tab is drawn, with a card hours into its step (one an estimate would call late): no panel prints an
// estimate, and no card's row fills a bar against a usual time.
test('no view prints an estimate of time, on any tab, for a card long in its step', () => {
  const data = full();
  data.panels.belt.data.cards[0].track = trackOf('+++>..', 'tests', { since: iso(T0 - 5 * 3600000) });
  for (const tab of ['overview', 'control', 'rules', 'belt3d', 'tests']) {
    const w = boot({ tab });
    deliver(w, data);
    for (const el of w.document.querySelectorAll('#grid > [data-panel]')) {
      // Only the Tests page may say "usual": a test file's "slower than usual" and "its usual", its measured median.
      const estimate = el.dataset.panel === 'tests' ? /(?<![Ss]lower than |its )usual|to landing|no estimate yet/ : /usual|to landing|no estimate yet/;
      assert.doesNotMatch(el.textContent, estimate, `${el.dataset.panel} prints no estimate`);
      for (const t of el.querySelectorAll('.track6')) assert.equal((t.closest('li') || t.parentNode).querySelector('.meter, .meter-fill'), null, `${el.dataset.panel}: no bar fills on a card's track`);
    }
  }
});

test('a card shows its time in the step, its start and its overall time so far', () => {
  const w = boot();
  const data = full();
  data.panels.belt.data.cards[0].track.files = { run: 3, of: 12 };
  deliver(w, data);
  const row = panel(w, 'belt').querySelector('li[data-key="sample:c3-63"]');
  assert.doesNotMatch(panel(w, 'belt').textContent, /usual|to landing|estimate/);
  assert.equal(row.querySelector('.meter'), null, 'no bar fills against a usual time');
  assert.equal(row.querySelector('.track-now').textContent, '5 min in this step3 of 12 test files');
  assert.equal(row.querySelector('.card-times').textContent, 'started 11:20 AM · 40 min overall', 'in its head line: when it was picked up and its overall time');
  // A card resumed from a kept patch counts the earlier card's time and shows its first start.
  const resumed = full();
  Object.assign(resumed.panels.belt.data.cards[0], timesOf(T0, 1200));
  next(w, resumed);
  assert.equal(row.querySelector('.card-times').textContent, 'started 11:00 AM · 1 h 00 min overall');
  // Picked up on an earlier day: the date is given with the time.
  const old = full();
  Object.assign(old.panels.belt.data.cards[0], { start: '2026-11-08T20:15:00Z', pickedAt: '2026-11-08T20:15:00Z', priorSec: 0 });
  next(w, old);
  assert.match(row.querySelector('.card-times').textContent, /^started Nov 8, 3:15 PM · 20 h 45 min overall$/);
  // A card that has landed stays on the belt until it is pushed and its issue is closed. It holds no builder slot:
  // the count against the cap is the cards still being built.
  const after = full();
  Object.assign(after.panels.belt.data.cards[0], { landed: true, step: 'push', model: null, track: trackOf('++-++>', 'pushing') });
  next(w, after);
  assert.equal(panel(w, 'belt').querySelector('.panel-count').textContent.trim(), '1 of 3');
  assert.equal(panel(w, 'belt').querySelectorAll('li.belt-card').length, 2, 'the landed card is still shown');
  // A landed card shows its start and its overall time from pick-up to landing.
  assert.match(panel(w, 'landed').querySelector('li').textContent, /started 10:30 AM.*30 min overall.*landed 11:00 AM/);
});

test('the step in progress beats now and then with motion on, and never under reduced motion', () => {
  for (const [reducedMotion, beats] of [[false, true], [true, false]]) {
    const w = boot({ reducedMotion });
    deliver(w, full());
    tick(w, 5000);
    const now = panel(w, 'belt').querySelector('.step6[data-state="now"] .step-chip');
    assert.equal(now.classList.contains('beat'), beats);
  }
  assert.match(css, /\.step-chip\.beat \{ animation: beat 260ms/);
});

// The owner could not read a card's 13-17 step lines at a glance: how long each step took against the others, where the
// rounds went, what failed. Every step is a bar on one time axis, as long as it ran; the queue is said apart so a long
// wait squashes no bar; the set-up is one bar that opens; the step in progress pulses and a finished card has none.
test("a card's steps are bars in order on one time axis, the set-up folded, a review with its verdict, failed tests red, the step in progress pulsing", () => {
  const P0 = T0 - 3600000;
  const at = (s) => iso(P0 + s * 1000);
  const steps = [
    { name: 'queued', state: 'done', sec: 1800, at: at(0) }, { name: 'picked', state: 'done', sec: null, at: at(0) },
    { name: 'worktree ready', state: 'done', sec: 10, at: at(10) }, { name: 'dependencies linked', state: 'done', sec: 5, at: at(15) },
    { name: 'brief written', state: 'done', sec: 45, at: at(60) }, { name: 'building', state: 'done', sec: 600, at: at(660) },
    { name: 'review 1 (NO-GO)', state: 'done', sec: 120, at: at(780), counts: counts(0, 1, 2, 0) }, { name: 'fix 1', state: 'done', sec: 300, at: at(1080) },
    { name: 'review 2 (NO-GO)', state: 'done', sec: 120, at: at(1200), counts: counts(0, 0, 1, 0) }, { name: 'fix 2', state: 'done', sec: 240, at: at(1440) },
    { name: 'review 3 (GO)', state: 'done', sec: 60, at: at(1500), counts: counts(0, 0, 0, 0) }, { name: 'tests failed', state: 'failed', sec: 180, at: at(1680), why: 'exit 124: timeout' },
    { name: 'fix 3', state: 'done', sec: 300, at: at(1980) }, { name: 'review 4 (GO)', state: 'done', sec: 60, at: at(2040), counts: counts(0, 0, 0, 0) },
  ];
  const open = [...steps, { name: 'tests again', state: 'now', sec: null }];
  for (const [reducedMotion, beats] of [[false, true], [true, false]]) {
    const w = boot({ reducedMotion });
    const data = full();
    data.panels.belt.data.cards[0].track = trackOf('++++>.', 'tests again', { since: at(2040), records: open });
    deliver(w, data);
    const items = Array.from(panel(w, 'belt').querySelectorAll('li[data-key="sample:c3-63"] details.track-detail .timeline > li.tl-item'));
    assert.deepEqual(items.map((li) => li.querySelector('.tl-label').firstChild.textContent),
      ['Setup', 'Build', 'Review 1', 'Fix 1: review findings', 'Review 2', 'Fix 2: review findings', 'Review 3', 'Tests', 'Fix 3: tests failed', 'Review 4', 'Tests again'], 'in order, the queue not among them');
    // Each bar as long as its step ran, on an axis from the pick-up to now (3600 s) and a tenth more for the running
    // step to grow into (3960 s), one after the other with no gap.
    const secs = [60, 600, 120, 300, 120, 240, 60, 180, 300, 60, 1560];
    let off = 0;
    items.forEach((li, i) => {
      const bar = li.querySelector('.tl-bar');
      assert.ok(Math.abs(parseFloat(bar.style.left) - (off / 3960) * 100) < 0.01, `the start of ${i}: ${bar.style.left}`);
      assert.ok(Math.abs(parseFloat(bar.style.width) - (secs[i] / 3960) * 100) < 0.01, `the length of ${i}: ${bar.style.width}`);
      off += secs[i];
    });
    // A bar a quarter of the axis or longer has its time on it; a shorter one, just after it in its lane.
    assert.equal(items[10].querySelector('.tl-bar > .tl-dur').textContent, '26 min', 'the time is on a long bar');
    assert.equal(items[1].querySelector('.tl-bar > .tl-dur'), null, 'a short bar has no room for its time');
    assert.equal(items[1].querySelector('.tl-lane > .tl-dur').textContent, '10 min');
    assert.equal(items[1].querySelector('.tl-lane > .tl-dur').style.left, '16.67%', 'its time starts where the bar ends');
    assert.equal(items[1].querySelector('.tl-tip').textContent, 'Build: done, 10 min, 11:01 AM to 11:11 AM', 'clock times in local time');
    assert.equal(panel(w, 'belt').querySelector('.tl-total').textContent, '1 h 00 min from 11:00 AM to now · waited 30 min in the queue before',
      'the wait is said apart from the axis');
    // The set-up is one bar that opens to its four steps.
    assert.deepEqual(Array.from(items[0].querySelectorAll('.tl-parts li'), (li) => li.textContent), ['picked: done', 'worktree ready: done, 10 s', 'dependencies linked: done, 5 s', 'brief written: done, 45 s']);
    assert.equal(items[0].querySelector('.tl-parts').open, false);
    // A review's verdict chip and its findings.
    assert.equal(items[2].querySelector('.chip').textContent, 'changes asked');
    assert.equal(items[2].querySelector('.tl-findings').textContent, '1 P1, 2 P2');
    assert.equal(items[6].querySelector('.chip').textContent, 'passed');
    // The failed tests: red (failed), with the run's recorded reason in its text, read on hover or focus; each item is focusable.
    assert.equal(items[7].dataset.state, 'failed');
    assert.equal(items[7].querySelector('.tl-tip').textContent, 'Tests: failed, 3 min, 11:25 AM to 11:28 AM: exit 124: timeout');
    assert.ok(items.every((li) => li.tabIndex === 0));
    // The step in progress, and only it, is current and pulses now and then, never under reduced motion.
    assert.deepEqual(items.map((li) => li.dataset.state === 'now'), [...Array(10).fill(false), true]);
    assert.equal(items[10].getAttribute('aria-current'), 'step');
    tick(w, 5000);
    assert.equal(items[10].querySelector('.tl-bar').classList.contains('beat'), beats);
    // A minute on with no new snapshot: the step in progress has grown into the axis's room; the axis and the bars
    // before it stay as drawn (3960 s).
    tick(w, 55000);
    assert.equal(items[10].querySelector('.tl-bar').style.width, `${((1620 / 3960) * 100).toFixed(2)}%`);
    assert.equal(items[10].querySelector('.tl-dur').textContent, '27 min');
    assert.equal(items[1].querySelector('.tl-bar').style.width, `${((600 / 3960) * 100).toFixed(2)}%`);
    // A redraw (the tokens counted on) keeps the set-up open and the keyboard on the bar it was on.
    const row = panel(w, 'belt').querySelector('li[data-key="sample:c3-63"]');
    row.querySelector('details.track-detail').open = true;
    row.querySelector('.tl-parts').open = true;
    row.querySelectorAll('.tl-item')[2].focus();
    data.panels.belt.data.cards[0].tokens = { claude: 2000000, codex: 1000000 };
    next(w, data);
    assert.equal(row.querySelector('details.track-detail').open, true);
    assert.equal(row.querySelector('.tl-parts').open, true, 'the set-up stays open');
    assert.equal(w.document.activeElement, row.querySelectorAll('.tl-item')[2], 'the focus stays on Review 1');
  }
  assert.match(css, /\.tl-item\[data-state="now"\] \.tl-bar\.beat \{ animation: pulse 260ms/);
  assert.match(css, /\.tl-item\[data-state="failed"\] \.tl-bar \{ background: var\(--bad\); \}/);
  // A landed card: its steps end at its landing, and none pulses. Its tests began 10 minutes after its last review
  // ended (a pause, as when a review is restarted): the pause is a gap on the axis, never a step stretched over it.
  const w = boot();
  const data = full();
  const done = [...steps, { name: 'tests passed', state: 'done', sec: 120, at: at(2760) }, { name: 'landing', state: 'done', sec: 30, at: at(2790) }, { name: 'pushed', state: 'done', sec: 5, at: at(2795) },
    { name: 'issue not closed', state: 'failed', sec: 5, at: at(2800), why: 'permission denied' }, { name: 'follow-ups filed', state: 'done', sec: 9, at: at(2809), n: 4 }];
  data.panels.landed.data.cards[0].track = trackOf('++++++', '', { at: null, since: null, records: done });
  deliver(w, data);
  const landed = Array.from(panel(w, 'landed').querySelectorAll('.timeline > li.tl-item'));
  assert.deepEqual(landed.slice(-5).map((li) => li.querySelector('.tl-label').textContent), ['Tests', 'Land', 'Push', 'Issue not closed', 'Follow-ups filed (4)'], 'the filing with its count');
  assert.equal(landed[landed.length - 2].querySelector('.tl-tip').textContent, 'Issue not closed: failed, 5 s, 11:46 AM to 11:46 AM: permission denied', 'the failed close with its reason');
  assert.ok(landed.every((li) => li.dataset.state !== 'now' && !li.hasAttribute('aria-current')), 'a landed card has no step in progress');
  assert.ok(Math.abs(parseFloat(landed[landed.length - 1].querySelector('.tl-bar').style.width) - (9 / 2809) * 100) < 0.01, 'its axis ends at its end');
  assert.ok(Math.abs(parseFloat(landed[landed.length - 5].querySelector('.tl-bar').style.left) - (2640 / 2809) * 100) < 0.01, 'the tests start after the pause');
  assert.equal(panel(w, 'landed').querySelector('.tl-total').textContent, '46 min from 11:00 AM to 11:46 AM, 36 min of it in steps · waited 30 min in the queue before');
  // A push that failed after the landing: its red bar says the push's error, and every bar keeps its clock times and
  // the pause (one bar without a time once put them all end to end, with no clock times).
  const w2 = boot();
  const data2 = full();
  const pushfail = [...done.slice(0, -3), { name: 'push failed; it is tried again', state: 'failed', sec: null, at: at(2790), why: 'pre-push hook refused' }];
  data2.panels.belt.data.cards[0].track = trackOf('+++++!', 'push failed; it is tried again', { since: at(2790), records: pushfail });
  deliver(w2, data2);
  const failed = Array.from(panel(w2, 'belt').querySelectorAll('li[data-key="sample:c3-63"] .timeline > li.tl-item'));
  assert.equal(failed[failed.length - 1].querySelector('.tl-tip').textContent, 'Push failed; it is tried again: failed, 0 s, 11:46 AM to 11:46 AM: pre-push hook refused');
  assert.equal(failed[1].querySelector('.tl-tip').textContent, 'Build: done, 10 min, 11:01 AM to 11:11 AM');
  assert.ok(Math.abs(parseFloat(failed[failed.length - 3].querySelector('.tl-bar').style.left) - (2640 / 2790) * 100) < 0.01, 'the pause is still a gap');
});

// Bug (#545): a retried card's overall time counted its earlier card's seconds, but "Every step" showed only its own
// steps, so the two did not add up and nothing said why. The earlier attempt is a closed line above its steps, with
// its times and why it ended, opening to its own steps; the overall time says on hover that it includes it.
test('a card with an earlier attempt shows it above its steps, and its overall time is both attempts added', () => {
  const w = boot();
  const data = full();
  const prior = { card: 'c3-60', start: iso(T0 - 3600000), end: iso(T0 - 2400000), sec: 1200, reason: 'a follow-up could not be held, so nothing landed', track: trackOf('++++!.', '', { at: null, since: null }) };
  Object.assign(data.panels.belt.data.cards[0], timesOf(T0, 1200), { earlier: [prior] });
  deliver(w, data);
  const row = panel(w, 'belt').querySelector('li[data-key="sample:c3-63"]');
  const all = row.querySelector('.card-times time');
  assert.equal(all.textContent, '1 h 00 min overall', 'the overall time is the earlier 20 min and the 40 min since its own pick-up');
  assert.match(all.title, /^Includes the earlier attempt/);
  const det = row.querySelector('details.track-detail'), earlier = det.querySelectorAll(':scope > details.tl-earlier');
  assert.equal(earlier.length, 1);
  assert.equal(earlier[0].querySelector('summary').textContent, 'Earlier attempt: 11:00 AM to 11:20 AM, 20 min, ended: a follow-up could not be held, so nothing landed');
  assert.equal(earlier[0].open, false, 'closed by default');
  assert.ok(earlier[0].compareDocumentPosition(det.querySelector(':scope > ol.timeline')) & w.Node.DOCUMENT_POSITION_FOLLOWING, 'above the current steps');
  assert.equal(earlier[0].querySelectorAll('.timeline > li.tl-item').length, 13, 'it opens to its own steps');
  // A card with no earlier attempt shows no such line, and its overall time says nothing of one.
  next(w, full());
  assert.equal(row.querySelector('details.tl-earlier'), null);
  assert.doesNotMatch(row.querySelector('.card-times time').title, /earlier/);
});

// Bug (#561): the belt row is keyed by the card id and a retry starts a new card id, so the retried card's row was new
// and drew "Every step" and its earlier attempts closed: the card got shorter under the reader. The new row takes what
// was open from the row of its earlier card id.
test('a retried card keeps "Every step" and its earlier attempt open when its card id changes', () => {
  const w = boot();
  const data = full();
  const card = data.panels.belt.data.cards[0];
  const first = { card: 'c3-60', start: iso(T0 - 3600000), end: iso(T0 - 2400000), sec: 1200, reason: 'tests failed', track: trackOf('++++!.', '', { at: null, since: null }) };
  Object.assign(card, timesOf(T0, 1200), { earlier: [first] });
  deliver(w, data);
  const det = panel(w, 'belt').querySelector('li[data-key="sample:c3-63"] details.track-detail');
  det.open = true;
  det.querySelector(':scope > details.tl-earlier').open = true;
  const second = { card: 'c3-63', start: iso(T0 - 2400000), end: iso(T0 - 600000), sec: 1800, reason: 'review said NO-GO', track: trackOf('++!...', '', { at: null, since: null }) };
  Object.assign(card, { card: 'c3-64', earlier: [first, second] });
  next(w, data);
  assert.equal(panel(w, 'belt').querySelector('li[data-key="sample:c3-63"]'), null, 'the old row is gone');
  const now = panel(w, 'belt').querySelector('li[data-key="sample:c3-64"] details.track-detail');
  assert.equal(now.open, true, '"Every step" is still open');
  const [a, b] = now.querySelectorAll(':scope > details.tl-earlier');
  assert.equal(a.dataset.card, 'c3-60');
  assert.equal(a.open, true, 'the earlier attempt the reader opened is still open');
  assert.equal(b.dataset.card, 'c3-63');
  assert.equal(b.open, false, 'the attempt that was the card itself starts closed');
});
