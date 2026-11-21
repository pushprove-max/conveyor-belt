// SPDX-License-Identifier: Apache-2.0
// The Benchmarks tab's Compare, Live run, Task, Task map and Plan a run (#1177, the owner's approved mockup): each
// page's sections in the mockup's order with its headings and the fixture's figures, in the mockup's Sample view
// (BH.study(), 7 arms on 50 tasks; BH.live(), the same arms in a run going) and its "Your data now" view (BH.few(), 2
// runs of 1 task); Compare's four boxes and verdict as the pickers change; Plan a run's slider, cost and Start; Stop.
// Shared setup: dashboard-view.helpers.mjs (BH).
import assert from 'node:assert/strict';
import { boot, settle, act, cases, BH, T0, iso } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const { bp, page, heads, pages, TASKS } = BH;
const text = (el) => el.textContent.replace(/\s+/g, ' ').trim();
const q = (w, s) => page(w).querySelector(s);
const rows = (el) => Array.from(el.querySelectorAll('tbody tr'), (r) => Array.from(r.children, text));
const stats = (w) => Array.from(page(w).querySelectorAll('.bench-stat'), (s) => Array.from(s.children, text));
const box = (w, title) => Array.from(page(w).querySelectorAll('.bench-box')).find((b) => b.querySelector('.bench-h') && b.querySelector('.bench-h').firstChild.textContent.trim() === title);
const fours = (w) => Array.from(page(w).querySelectorAll('.bench-four'), (b) => [b.lastChild.textContent, Number(b.firstChild.textContent)]);
const kv = (el) => Array.from(el.querySelectorAll('dt'), (d) => [d.textContent, text(d.nextElementSibling)]);
const pick = async (w, a, v) => { const s = act(bp(w), a); s.value = v; s.dispatchEvent(new w.Event('change')); await settle(); await settle(); };
async function opened(set, p) {
  const w = boot({ tab: 'bench' });
  BH.open(w, set);
  await settle(); await settle();
  if (p) { BH.go(w, p); await settle(); await settle(); }
  return w;
}

// ---- Compare ----
// Bug it guards: Compare read only the runs ticked and showed a table of totals with no answer. It takes any two arms or
// versions, says which is better against the noise of the tasks both graded, puts every task in one of four boxes,
// lists the flipped tasks with the first step apart (and, once asked, the model's reading, labelled as such) and sets
// cost and time side by side; a flipped task opens the Task page.
test('Compare, Conveyor against Claude alone on 50 tasks: the verdict, the four boxes, the flipped tasks and cost and time', async () => {
  const set = BH.study();
  // Claude alone's result of TASKS[27] is one a run with --again kept apart (show's again): the diff reads only the kept one.
  set.shows[BH.STUDY].tasks[27].cells.find((c) => c.arm === 'solo').again = BH.STUDY;
  // The diff reads each side's kept result. For TASKS[26] it read Claude alone resolved, as a run with --again can make
  // the kept result differ from the one the page shows: that reading explains another result, so it is not shown (E4).
  // For TASKS[27] it read the outcomes shown, but of the kept trial, not the --again one shown: not shown either.
  const w = boot({ tab: 'bench' });
  BH.open(w, set);
  await settle(); await settle();
  w.reply = BH.reply(JSON.stringify({ flipped: [{ task: TASKS[25], a: { resolved: true }, b: { resolved: false }, reading: 'The review caught a missed case, and the fix round handled it.' },
    { task: TASKS[26], a: { resolved: true }, b: { resolved: true }, reading: 'Both resolved it.' }, { task: TASKS[27], a: { resolved: true }, b: { resolved: false }, reading: 'Of the kept trial.' }] }));
  BH.go(w, 'compare');
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [['diff', BH.study().hist.runs[0].cols[0].key, 'solo', '--json']], 'the two arms\' results keys, asked for with no click');
  assert.equal(text(q(w, '.bench-answers')), 'This page answers: Is one arm or version better than another, on the same tasks, and why?');
  assert.deepEqual(heads(w), ['Head to head', 'Where they differ', 'The flipped tasks', 'Cost and time']);
  assert.deepEqual(Array.from(act(bp(w), 'cmp-a').options, (o) => o.textContent), ['Conveyor v1.9.0', 'Conveyor, Codex builds v1.9.0', 'Claude, then a review', 'Codex alone', 'Claude + Superpowers',
    'Claude alone', 'Claude + Caveman', 'Conveyor v1.8.0', 'Conveyor v1.7.0', 'Conveyor v1.6.0', 'Conveyor v1.5.0', 'Conveyor v1.4.0'], 'any arm, or any version of the Conveyor arm');
  assert.equal(text(q(w, '.bench-vv')), 'Conveyor v1.9.0 is better: it resolves 12 more of 50. That is past the noise of 10.');
  assert.equal(text(q(w, '.bench-vw')), 'It costs $96.00 against $15.50 for the 50 tasks, and takes 17.5 h against 2.5 h.');
  assert.deepEqual(fours(w), [['Both resolve', 25], ['Only Conveyor v1.9.0', 12], ['Only Claude alone', 0], ['Neither', 13]]);
  const flips = rows(q(w, '.bench-flips'));
  assert.equal(flips.length, 12);
  assert.deepEqual(flips[0], [TASKS[25], 'Conveyor v1.9.0', 'saved at review', 'not read']);
  assert.deepEqual(Array.from(box(w, 'Cost and time').querySelectorAll('.bench-pair'), (p) => text(p)), ['CostConveyor v1.9.0$96.00Claude alone$15.50', 'Cost per resolved taskConveyor v1.9.0$2.59Claude alone$0.62',
    'Machine timeConveyor v1.9.017.5 hClaude alone2.5 h', 'TokensConveyor v1.9.020.5MClaude alone2.4M', 'Sessions a taskConveyor v1.9.04.0Claude alone1.0']);
  assert.equal(text(box(w, 'Cost and time').querySelector('.bench-callout')), 'Each extra fix of Conveyor v1.9.0 costs $6.71.');
  await settle(); await settle();
  assert.deepEqual(rows(q(w, '.bench-flips')).slice(0, 3).map((r) => [r[0], r[3]]), [[TASKS[25], 'The review caught a missed case, and the fix round handled it.'],
    [TASKS[26], 'not of the result shown (a run again)'], [TASKS[27], 'not of the result shown (a run again)']]);
  assert.match(text(box(w, 'Where they differ').querySelector('.bench-note')), /is one model call's reading of the facts of both runs, and is labelled as such on the Board\.$/);
  page(w).querySelector(`.bench-flips tr[data-task="${TASKS[25]}"]`).click();
  await settle();
  assert.equal(pages(w).find(([, c]) => c === 'page')[0], 'Task');
  assert.equal(text(q(w, '.bench-vk')), `sympy · ${TASKS[25]}`);
});

// Bug it guards: a click on an arm of the Scoreboard opened Compare for another pair, and the reply of the diff asked for
// the pair before, arriving later, showed the model's reading for the wrong arm. A reading belongs to its own pair.
test('Compare: a reading asked for one pair is not shown for the pair a Scoreboard click opens before the reply comes', async () => {
  const w = boot({ tab: 'bench' }), held = [];
  BH.open(w, BH.study());
  await settle(); await settle();
  // Each ask waits for its own answer; this test sends it by hand (held), as a model call takes time.
  w.reply = { ok: true, status: 200, text: () => new Promise((r) => { held.push(r); }) };
  BH.go(w, 'compare');
  await settle();
  BH.go(w, 'score');
  await settle();
  page(w).querySelector('.bench-leader tr[data-cmp="caveman"]').click();
  await settle();
  assert.deepEqual([act(bp(w), 'cmp-a').value, act(bp(w), 'cmp-b').value], ['arm:conveyor', 'arm:caveman'], 'another pair, opened from the Scoreboard');
  assert.equal(held.length, 2, 'the other pair asks at once, whatever the first reply');
  held[0](JSON.stringify({ flipped: [{ task: TASKS[25], a: { resolved: true }, b: { resolved: false }, reading: 'A reading of the old ask.' }] }));
  await settle(); await settle();
  assert.ok(!text(page(w)).includes('A reading of the old ask.'), 'the old ask\'s reading is not shown');
});

// Bug it guards: a page that loads its readings by itself asked the model again on each draw. A reading is a model call
// for each task with none saved: the diff of a pair is asked for once while the Board is open (a redraw, a return to the
// page, a pair seen before use what it has), once more for a new pair, and a diff that failed is shown as missing and
// not asked for again by itself.
test('Compare: the readings are asked for once for a pair, once more when a picker changes, and not again after a failure', async () => {
  const w = boot({ tab: 'bench' }), sent = () => w.posts.splice(0).map((p) => p.body.args), reading = () => rows(q(w, '.bench-flips'))[0][3];
  BH.open(w, BH.study());
  await settle(); await settle();
  w.reply = BH.reply(JSON.stringify({ flipped: [{ task: TASKS[25], a: { resolved: true }, b: { resolved: false }, reading: 'It read the review.' }] }));
  BH.go(w, 'compare');
  await settle(); await settle();
  assert.deepEqual(sent().map((a) => a.slice(0, 1)), [['diff']], 'the first draw asks once');
  assert.equal(reading(), 'It read the review.');
  BH.go(w, 'score'); BH.go(w, 'compare');
  await settle(); await settle();
  assert.deepEqual(sent(), [], 'a second draw of the same pair asks for nothing');
  await pick(w, 'cmp-b', 'arm:caveman');
  assert.deepEqual(sent().map((a) => a.slice(0, 1)), [['diff']], 'a changed picker asks once more');
  await pick(w, 'cmp-b', 'arm:solo');
  assert.deepEqual(sent(), [], 'the pair seen before uses its reading');
  w.reply = { ok: false, status: 502, text: () => Promise.resolve('conveyor: the model did not answer') };
  await pick(w, 'cmp-b', 'arm:conveyor-codex-claude');
  assert.deepEqual(sent().map((a) => a.slice(0, 1)), [['diff']], 'a new pair asks, and the answer is a failure');
  assert.equal(reading(), 'not read', 'a reading the model did not give shows as missing');
  BH.go(w, 'score'); BH.go(w, 'compare');
  await settle(); await settle();
  assert.deepEqual(sent(), [], 'a failed diff is not asked for again on each draw');
  // The engine's answer when the model call fails is not an error: the diff comes with reading: null for each flipped task
  // (swe.sh `diff` saves nothing then), so a check of the data alone would take it for a diff that came. Each ask waits for
  // its answer (held), so the test reads the flipped task of the pair from the page first.
  await pick(w, 'cmp-b', 'arm:solo');
  assert.deepEqual(sent(), [], 'the pair seen before uses its reading');
  let held = null;
  w.reply = { ok: true, status: 200, text: () => new Promise((r) => { held = r; }) };
  await pick(w, 'cmp-b', 'arm:conveyor-codex-claude');
  assert.deepEqual(sent().map((a) => a.slice(0, 1)), [['diff']], 'a picker returning to the failed pair asks once more');
  const first = q(w, '.bench-flips tbody tr'), task = first.dataset.task, aWon = text(first.children[1]) === text(act(bp(w), 'cmp-a').selectedOptions[0]);
  const flip = (r) => JSON.stringify({ flipped: [{ task, a: { resolved: aWon }, b: { resolved: !aWon }, reading: r }] });
  held(flip(null));
  await settle(); await settle();
  assert.equal(reading(), 'no reading', 'a diff that came with no reading shows it as missing');
  BH.go(w, 'score'); BH.go(w, 'compare');
  await settle(); await settle();
  assert.deepEqual(sent(), [], 'a diff with a null reading is not asked for again on each draw');
  await pick(w, 'cmp-b', 'arm:solo');
  w.reply = BH.reply(flip('It read the review.'));
  await pick(w, 'cmp-b', 'arm:conveyor-codex-claude');
  assert.deepEqual(sent().map((a) => a.slice(0, 1)), [['diff']], 'a picker returning to a pair whose reading was null asks once more');
  assert.equal(reading(), 'It read the review.', 'the second ask gave the reading');
  await pick(w, 'cmp-b', 'arm:solo');
  await pick(w, 'cmp-b', 'arm:conveyor-codex-claude');
  assert.deepEqual(sent(), [], 'a reading that came is not asked for again');
});

// Bug it guards: the flipped-tasks table was cut to its first 12 rows, so a pair with more flips than 12 (Conveyor against
// Claude + Caveman has 15 in the "Only" boxes) hid the rest while the boxes counted them all.
test('Compare, Conveyor against Claude + Caveman: the table lists every flipped task, more than 12', async () => {
  const w = await opened(BH.study(), 'compare');
  await pick(w, 'cmp-b', 'arm:caveman');
  const flips = fours(w).filter(([name]) => name.startsWith('Only ')).reduce((s, [, v]) => s + v, 0);
  assert.ok(flips > 12, `the pair has more than 12 flipped tasks, has ${flips}`);
  assert.equal(rows(q(w, '.bench-flips')).length, flips, 'one table row for each task in the two "Only" boxes');
});

// Bug it guards: the boxes and the verdict did not follow the pickers. On every pair the four boxes add up to the
// shared tasks, and the verdict changes with the pair: 2 apart is not told apart, a version 10 above Claude alone is.
test('Compare: the four boxes add up to the shared tasks, and the verdict changes when the pickers change', async () => {
  const w = await opened(BH.study(), 'compare');
  const sum = () => fours(w).reduce((s, [, v]) => s + v, 0);
  assert.equal(sum(), 50);
  await pick(w, 'cmp-b', 'arm:conveyor-codex-claude');
  assert.deepEqual(fours(w), [['Both resolve', 35], ['Only Conveyor v1.9.0', 2], ['Only Conveyor, Codex builds v1.9.0', 0], ['Neither', 13]]);
  assert.equal(sum(), 50);
  assert.equal(text(q(w, '.bench-vv')), 'Not told apart yet. The difference is 2 tasks, under the noise of 10.');
  assert.equal(text(q(w, '.bench-vw')), 'If the gap held, about 1250 tasks would show it, more than the set has, so treat the two as equal.');
  await pick(w, 'cmp-a', 'ver:v1.8.0');
  await pick(w, 'cmp-b', 'arm:solo');
  assert.deepEqual(fours(w), [['Both resolve', 25], ['Only Conveyor v1.8.0', 10], ['Only Claude alone', 0], ['Neither', 15]]);
  assert.equal(sum(), 50);
  assert.equal(text(q(w, '.bench-vv')), 'Conveyor v1.8.0 is better: it resolves 10 more of 50. That is past the noise of 10.');
});

// Bug it guards: when the second arm won, the verdict named it the winner but gave it the first arm's cost and time.
test('Compare: with the winner in the second picker, the verdict gives the winner\'s cost and time first', async () => {
  const w = await opened(BH.study(), 'compare');
  await pick(w, 'cmp-a', 'arm:solo');
  await pick(w, 'cmp-b', 'ver:v1.9.0');
  assert.equal(text(q(w, '.bench-vv')), 'Conveyor v1.9.0 is better: it resolves 12 more of 50. That is past the noise of 10.');
  assert.equal(text(q(w, '.bench-vw')), 'It costs $96.00 against $15.50 for the 50 tasks, and takes 17.5 h against 2.5 h.');
});

// Bug it guards: Compare offered older versions only for the arm named conveyor, so a run of conveyor-codex-claude on v1.7.0
// next to its newer v1.9.0 could not be picked. Each Conveyor arm in the study gets its own older versions.
test('Compare: an older version of a Conveyor arm other than conveyor can be picked', async () => {
  const set = BH.study(), src = set.hist.runs.find((r) => r.id === BH.OLDS[1][1]), id = 'r20261106T083000-6', arm = 'conveyor-codex-claude';
  const as = (c) => ({ ...c, arm, label: 'Conveyor, Codex builds', key: c.key.replace(/^conveyor/, arm) });
  set.hist.runs.push({ ...src, id, cols: src.cols.map(as), arms: [arm] });
  set.shows[id] = { ...set.shows[BH.OLDS[1][1]], run: set.hist.runs[set.hist.runs.length - 1], tasks: set.shows[BH.OLDS[1][1]].tasks.map((t) => ({ ...t, cells: t.cells.map((c) => ({ ...c, arm })) })) };
  const w = await opened(set, 'compare'), ids = () => Array.from(act(bp(w), 'cmp-a').options, (o) => o.value);
  assert.ok(ids().includes(`ver:${arm}:v1.7.0`), `the picker offers the older version of ${arm}: ${ids().join(', ')}`);
  assert.ok(ids().includes('ver:v1.8.0'), 'the older versions of the conveyor arm are still offered');
  await pick(w, 'cmp-a', `ver:${arm}:v1.7.0`);
  assert.equal(act(bp(w), 'cmp-a').value, `ver:${arm}:v1.7.0`);
  assert.match(fours(w)[1][0], /^Only Conveyor, Codex builds v1\.7\.0$/);
  // Bug it guards: an older version of another Conveyor arm took the conveyor arm's colour (bench-s1), not its own (bench-s6).
  await pick(w, 'cmp-b', 'arm:solo');
  const dots = Array.from(page(w).querySelectorAll('.bench-flips .bench-arm'), (d) => [d.textContent, d.firstChild.className]);
  const mine = dots.filter(([t]) => t.startsWith('Conveyor, Codex builds'));
  assert.ok(mine.length > 0, `the flipped tasks table has rows won by the older version: ${JSON.stringify(dots)}`);
  assert.ok(mine.every(([, c]) => /bench-s6\b/.test(c)), `the older version of ${arm} is drawn in the colour of ${arm}: ${JSON.stringify(mine)}`);
});

// Bug it guards: with 1 shared task, Compare drew boxes and a verdict as if one task could tell two arms apart.
test('Compare, 2 runs of 1 task: nothing can be told yet, and only cost and time differ on the one task', async () => {
  const w = await opened(BH.few(), 'compare');
  assert.deepEqual(heads(w), ['Head to head', `Cost and time on ${BH.FEW_TASK}`]);
  assert.equal(text(q(w, '.bench-vv')), 'Conveyor v1.7.0 and Claude alone both resolved the one task they share.');
  assert.equal(text(q(w, '.bench-vw')), 'There is no flipped task to explain. The only difference is cost and time: Conveyor v1.7.0 took 3 sessions, 77k tokens and 2.9 minutes;'
    + ' Claude alone took 1 session, 2k tokens and 0.5 minutes.');
  assert.deepEqual(Array.from(page(w).querySelectorAll('.bench-pair'), (p) => text(p)), ['TokensConveyor v1.7.077kClaude alone2k', 'MinutesConveyor v1.7.02.9 minClaude alone0.5 min', 'SessionsConveyor v1.7.03Claude alone1']);
});

// ---- Live run ----
// Bug it guards: a run going showed a table of counts with no answer to whether it ends in time or on budget. The
// Live run has the verdict (time, budget, usage guard), 4 figures, the grid of tasks by arm with the working cell's
// step, the score so far with its ranges, the event tail, and Stop, which names the run.
test('Live run, 7 arms on 50 tasks going: the verdict, the figures, the grid with the working step, the score so far, the events and Stop', async () => {
  const w = await opened(BH.live());
  assert.equal(text(q(w, '.bench-answers')), 'This page answers: What is the run doing now, will it finish in time, and is it on budget?');
  assert.deepEqual(heads(w), [`${BH.LIVE} · 50 tasks × 7 arms`, 'Tasks by arm', 'Score so far', 'Events']);
  assert.equal(text(q(w, '.bench-vv')), 'On time and on budget. 73 of 350 task runs done; about 7.6 h left.');
  assert.equal(text(q(w, '.bench-vw')), 'Spent $61.24 of the $293 estimate. The usage guard is not reached.');
  assert.deepEqual(stats(w).map((s) => s.slice(0, 2)), [['73/350', 'Task runs done'], ['7.6 h', 'Left, at this pace'], ['$61.24', 'Spent so far'], ['0', 'Not run']]);
  assert.equal(stats(w)[2][2], '21% of the estimate');
  const cell = (t, a) => page(w).querySelector(`.bench-gc[data-task="${t}"][data-arm="${a}"]`), LT = BH.LIVE_TASKS;
  assert.deepEqual([cell(LT[10], 'codex-sol').className, cell(LT[10], 'codex-sol').textContent], ['bench-gc bench-g-work', 'Running agent · 4 min'], 'the working cell says its step and minutes');
  assert.equal(cell(LT[0], 'conveyor').className, 'bench-gc bench-g-ok');
  assert.equal(cell(LT[11], 'conveyor').className, 'bench-gc', 'a task not reached waits');
  assert.equal(page(w).querySelectorAll('.bench-gt').length, 50);
  assert.deepEqual(Array.from(box(w, 'Score so far').querySelectorAll('.bench-lrow'), text).slice(0, 2), ['Conveyor v1.9.010 of 10', 'Conveyor, Codex builds v1.9.010 of 10']);
  // The engine's noise of 10 tasks (SWE_NOISED): sqrt(20) = 4.5, rounded up to 5; rounded to 4, a difference of 4 read as shown.
  assert.equal(text(box(w, 'Score so far').querySelector('.bench-note')), '10 tasks: only a difference of 5 or more shows.');
  assert.deepEqual(Array.from(page(w).querySelectorAll('.bench-tail li'), (li) => text(li).replace(/^\S+ \S+ /, '')),
    [`Codex alone · ${LT[10]} · Running agent`, `Claude, then a review · ${LT[10]} · Unresolved`, `Conveyor v1.9.0 · ${LT[10]} · Resolved`], 'the newest event first');
  act(bp(w), 'stop-run').click();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [['stop', BH.LIVE]]);
  assert.equal(act(bp(w), 'stop-run').textContent, 'Stopping the run');
});

// Bug it guards (review E9): a reused result takes no trial, yet the forecast counted it as work done (so the time left
// came from its near-zero time) and the estimate priced it. Here the run reused tasks 0 to 9 of every arm, so the only
// trials done are task 10's 3, and Claude alone's results key keeps the run's last task, which it reuses too: 276
// trials are left, at 40 minutes each, and the estimate prices 40 tasks of each arm (39 of Claude alone).
test('Live run: reused results are no trial in the time left, and cost nothing in the estimate', async () => {
  const set = BH.live(), LT = BH.LIVE_TASKS;
  set.shows[BH.LIVE].tasks.slice(0, 10).forEach((t) => t.cells.forEach((c) => { c.reused = true; }));
  set.hist.keys.find((k) => k.key === 'solo').at.push(BH.ORDER.indexOf(LT[49]));
  const w = await opened(set);
  // 120 minutes over 3 trials, for 350 - 73 - 1 = 276 left: 11040 minutes. Counting the 70 reused: 120 / 73 * 277 = 7.6 h.
  // The 2 hours and $61.24 spent are the set's, for 73 trials: on 3 trials they are behind time and over budget.
  assert.equal(text(q(w, '.bench-vv')), 'Behind time and over budget. 73 of 350 task runs done; about 184.0 h left.');
  // (1.92 + 1.38 + 0.61 + 0.44 + 0.93 + 0.31 + 0.27) * 40 - 0.31 = $234; pricing every task: $293.
  assert.equal(text(q(w, '.bench-vw')), 'Spent $61.24 of the $234 estimate. The usage guard is not reached.');
});

// Bug it guards (review E9): a run with --again runs every task again, yet its tasks with a kept result were counted as
// reused, so the time left and the estimate left them out. Every arm's results key keeps tasks 21 to 50 of the run; the
// run is --again (its line's again), so the time left and the estimate are those of the run with none kept: 7.6 h and
// $293 (counting the 210 kept as reused: 1.8 h and $117).
test('Live run: a run with --again counts no kept result as reused', async () => {
  const set = BH.live(), LT = BH.LIVE_TASKS, line = set.hist.runs[0];
  line.cols.forEach((c) => set.hist.keys.find((k) => k.key === c.key).at.push(...LT.slice(20).map((t) => BH.ORDER.indexOf(t))));
  line.again = true; set.shows[BH.LIVE].run.again = true;
  const w = await opened(set);
  assert.equal(text(q(w, '.bench-vv')), 'On time and on budget. 73 of 350 task runs done; about 7.6 h left.');
  assert.equal(text(q(w, '.bench-vw')), 'Spent $61.24 of the $293 estimate. The usage guard is not reached.');
});

// Bug it guards: a task one arm could not run (its harness could not grade it) counted as a loss in that arm's score and
// 95% range, so "Score so far" read 1 of 1 and 0 of 1; docs/benchmarks.md says such a task is not run, never failed.
// And the arms were then scored on different tasks, so the gap beside the noise note was not a gap on one set of tasks.
test('Live run: a task an arm did not run is left out for every arm, so all are scored on the same tasks', async () => {
  const s = BH.live(), cells = s.shows[BH.LIVE].tasks[0].cells;
  cells[1].result = 'not run: the harness could not grade it'; cells[1].resolved = false;
  const w = await opened(s), rows = Array.from(box(w, 'Score so far').querySelectorAll('.bench-lrow'), text);
  assert.equal(rows[0], 'Conveyor v1.9.09 of 9', 'the arm that ran every task drops the task the other did not run');
  assert.equal(rows[1], 'Conveyor, Codex builds v1.9.09 of 9', 'the arm with one task not run counts 9 shared tasks, not 10');
  assert.equal(text(box(w, 'Score so far').querySelector('.bench-note')), '9 tasks: only a difference of 5 or more shows.');
  assert.equal(box(w, 'Score so far').querySelectorAll('.bench-ci')[1].title, '95% range 70% to 100%', 'the range is of 9 tasks, not 10');
});

// Bug it guards: with no run going the page was empty. It shows the last run, as the mockup's "Your data now" does: how
// it ended, each arm's result, sessions, tokens, minutes and cost (not priced when none was kept), and its task.
test('Live run, 2 runs of 1 task and none going: the last run, each arm on its task, and its task to open', async () => {
  const w = await opened(BH.few(), 'run');
  assert.deepEqual(heads(w), ['No run goes now', BH.FEW1]);
  assert.match(text(q(w, '.bench-vv')), /^The last run ended \d{2}\/\d{2}\/\d{4}, \d{1,2}:\d{2} [AP]M, after 9 minutes\.$/);
  assert.equal(text(q(w, '.bench-vw')), 'It ran 1 task with 4 arms. All 4 resolved it.');
  assert.deepEqual(rows(q(w, '.bench-t')), [['Conveyor, Codex builds v1.7.0', 'resolved', '3', '81k', '3.2', '$0.50'], ['Claude + Ponytail', 'resolved', '2', '64k', '0.9', 'not priced'],
    ['Claude, then a review', 'resolved', '2', '13k', '0.8', 'not priced'], ['Claude alone', 'resolved', '1', '2k', '0.5', 'not priced']]);
  act(bp(w), 'open-task').click();
  await settle();
  assert.equal(text(q(w, '.bench-vk')), `django · ${BH.FEW_TASK}`);
});

// Bug it guards (#646 review E2): a run whose process was gone with no end written read as ended, with no Stop, so its
// end was never recorded and its containers stayed. It says interrupted and keeps Stop, which records its end.
test('Live run: a run whose process is gone keeps Stop, which records its end', async () => {
  const set = BH.few(), r = set.hist.runs[0];
  Object.assign(r, { state: 'stopped', gone: true, ended: null });
  set.shows[BH.FEW1].run = r;
  const w = await opened(set, 'run');
  assert.match(text(q(w, '.bench-vv')), /^The last run is interrupted\./);
  assert.match(text(q(w, '.bench-vw')), /Its process ended with no end recorded\.$/);
  w.reply = BH.reply(`conveyor: run ${BH.FEW1} was interrupted: its process had ended.`);
  act(bp(w), 'stop-run').click();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [['stop', BH.FEW1]]);
  Object.assign(r, { ended: iso(T0) });
  await settle(); await settle();
  assert.equal(act(bp(w), 'stop-run'), null, 'no Stop once its end is recorded');
  assert.match(text(q(w, '.bench-said')), /^Run interrupted: its process had ended\./);
});

// Bug it guards (review E10): a run the build machine refused (no Docker: swe_run records state refused and why) read
// "It ran 1 task", with its cell that never started labelled unresolved, and the reason was not shown.
test('Live run: a refused run says it did not start and why, and its cell is not started, never unresolved', async () => {
  const set = BH.few(), id = 'r20261109T010000-77', why = 'docker is not running on the build machine';
  const line = { id, state: 'refused', started: iso(T0 - 3600000), ended: iso(T0 - 3600000), n: 1, set: set.hist.runs[0].set, arms: ['conveyor'], current: null, shared: {}, cost: null, why,
    cols: [{ arm: 'conveyor', key: null, label: 'Conveyor', kind: 'conveyor', engine: null, version: 'main', done: 0, resolved: 0, notRun: 0, sessions: null, tokens: null, minutes: null, classes: null, cost: null, wall: 0 }] };
  set.hist.runs.unshift(line);
  set.shows[id] = { run: line, tasks: [{ id: BH.FEW_TASK, title: BH.TITLE, cells: [{ arm: 'conveyor', result: null, reused: false, state: 'not reached' }] }], tail: [] };
  const w = await opened(set, 'run');
  assert.ok(q(w, '.bench-verdict').classList.contains('bench-verdict-bad'));
  assert.match(text(q(w, '.bench-vv')), /^The last run did not start\./);
  assert.equal(text(q(w, '.bench-vw')), `The build machine refused it: ${why}.`);
  assert.deepEqual(rows(q(w, '.bench-t')).map((r) => r.slice(0, 2)), [['Conveyor main', 'not started']]);
});

// ---- Task ----
// Bug it guards: a task opened showed each arm's card side by side with no answer to whether the task or an arm was the
// problem. The Task page has the verdict, each arm's result, minutes, hidden tests and note, the Conveyor card's steps
// with width as time, the reviews folded, the task across the Conveyor arm's versions and its facts.
test('Task, 7 arms on one task of the study: the verdict, each arm, the card\'s timeline, the review, the versions and the facts', async () => {
  const w = await opened(BH.study(), 'task');
  assert.equal(text(q(w, '.bench-answers')), 'This page answers: What happened on one task, arm by arm, and is the task itself the problem?');
  assert.deepEqual(heads(w), [`django · ${TASKS[0]}`, 'Each arm on this task', 'Conveyor\'s card, step by step', 'The review, in full', 'This task over time']);
  assert.equal(text(q(w, '.bench-vv')), BH.TITLE);
  assert.equal(text(q(w, '.bench-vw')), '7 of 7 arms resolve it. An easy task: it tells the arms apart only on cost and time.');
  assert.deepEqual(rows(q(w, '.bench-arms'))[0], ['Conveyor v1.9.0', 'resolved', '21', '2 of 2 FAIL_TO_PASS · 40 of 40 PASS_TO_PASS', '']);
  const spans = Array.from(page(w).querySelectorAll('.bench-swim span'));
  assert.deepEqual(spans.map((s) => s.dataset.step), ['build', 'review', 'fix', 'review', 'test', 'landed']);
  assert.deepEqual(spans.map((s) => Math.round(parseFloat(s.style.left))), [0, 52, 62, 71, 81, 90], 'the build took 11 of the 21 minutes, each step after it 2');
  assert.equal(spans[0].textContent, 'build · 300k tok');
  assert.match(text(q(w, 'details[data-fold^="review-"]')), /Review 1: NO-GO\. \[P1\] reverse_related\.py:310 through_fields is not made hashable/);
  assert.deepEqual(Array.from(page(w).querySelectorAll('.bench-vd'), (d) => d.textContent), ['1.4.0', '1.5.0', '1.6.0', '1.7.0', '1.8.0', '1.9.0']);
  assert.deepEqual(kv(box(w, 'This task over time')), [['Repository', 'django'], ['Difficulty', 'easy (resolved by 7 of 7 arms)'], ['Patch size', '1 file, +7 −3'], ['Task image', 'not kept'], ['Hidden tests', '2 FAIL_TO_PASS, 40 PASS_TO_PASS']]);
});

// Bug it guards: a result kept before the grade's report showed its hidden tests as 0 of 0, and with 1 task run the
// page called the task easy (review E13). The verdict says nothing can be told yet, and each figure not kept says so.
test('Task, 2 runs of 1 task: nothing can be told yet of the task, and the hidden tests and the reference fix say not kept', async () => {
  const w = await opened(BH.few(), 'task');
  assert.ok(q(w, '.bench-verdict').classList.contains('bench-verdict-quiet'));
  assert.equal(text(q(w, '.bench-vw')), '5 of 5 arms resolve it. Nothing can be told yet: with 1 task run, there is no other task to set this one against.');
  assert.deepEqual(rows(q(w, '.bench-arms')).map((r) => r[3]), ['not kept', 'not kept', 'not kept', 'not kept', 'not kept']);
  assert.deepEqual(kv(box(w, 'This task over time')).slice(1), [['Difficulty', 'not told yet (resolved by 5 of 5 arms)'], ['Patch size', 'not kept'], ['Task image', 'not kept'], ['Hidden tests', 'not kept']]);
});

// Bug it guards (review): with 2 tasks every arm graded, the verdict said there was no other task to set this one
// against. It says the 2 tasks are too few to tell an easy task from a hard one.
test('Task, 2 runs of 2 tasks: nothing can be told yet, as 2 tasks are too few, not as there is no other', async () => {
  const set = BH.few();
  [BH.FEW1, BH.FEW2].forEach((id) => { const t = set.shows[id].tasks; t.push({ ...t[0], id: 'django__django-11001' }); });
  const w = await opened(set, 'task');
  assert.equal(text(q(w, '.bench-vw')), '5 of 5 arms resolve it. Nothing can be told yet: 2 tasks every arm graded are too few to tell an easy task from a hard one.');
});

// ---- Task map ----
// Bug it guards: nothing showed which of the set's 500 tasks ran or which no arm resolves. The Task map has one square a
// task, by repository, coloured by how many arms resolve it or by one arm's result, or not run yet; a click opens it.
test('Task map, 50 of 500 tasks run: the coverage verdict, one square a task by repository, coloured by arms or by one arm', async () => {
  const w = await opened(BH.study(), 'map');
  assert.deepEqual(heads(w), ['Coverage', 'All 500 tasks of SWE-bench Verified, by repository']);
  assert.equal(text(q(w, '.bench-vv')), '50 of 500 tasks have results. 13 of them no arm resolves.');
  assert.equal(text(q(w, '.bench-vw')), 'Django is 46% of the set, so a run of the first 50 tasks leans on Django. The hard tasks are where a new version can gain the most.');
  assert.deepEqual(Array.from(page(w).querySelectorAll('.bench-repo'), (g) => text(g.firstChild)).slice(0, 3), ['django 231 tasks · 24 run', 'sympy 75 tasks · 7 run', 'sphinx 44 tasks · 4 run']);
  assert.equal(page(w).querySelectorAll('.bench-sq[data-t]').length, 500);
  assert.equal(page(w).querySelectorAll('button.bench-sq').length, 50);
  const sq = (t) => page(w).querySelector(`.bench-sq[data-t="${t}"]`);
  assert.deepEqual([sq(TASKS[0]).className, sq(TASKS[30]).className, sq(TASKS[40]).className, sq(BH.ORDER[60]).tagName], ['bench-sq bench-sq-all', 'bench-sq bench-sq-some', 'bench-sq bench-sq-none', 'SPAN']);
  assert.equal(sq(TASKS[30]).title, `${TASKS[30]}: Task 31 of the study. 3 of 7 arms resolve it. Click to open.`);
  await pick(w, 'map-by', 'solo');
  assert.deepEqual([sq(TASKS[0]).className, sq(TASKS[30]).className], ['bench-sq bench-sq-all', 'bench-sq bench-sq-none'], 'by Claude alone, which resolves the first 25');
  assert.deepEqual(Array.from(page(w).querySelectorAll('.bench-legend span'), text), ['Resolved', 'Unresolved', 'Not run yet']);
  sq(TASKS[30]).click();
  await settle();
  assert.equal(text(q(w, '.bench-vw')), '3 of 7 arms resolve it. A task that tells the arms apart.');
});

// Bug it guards: with 1 task run, the map read as if nothing was there. The one task is a square that opens it, and the
// other 499 say not run yet.
test('Task map, 2 runs of 1 task: 1 of 500 tasks has results, its square opens it, the rest are not run yet', async () => {
  const w = await opened(BH.few(), 'map');
  assert.equal(text(q(w, '.bench-vv')), '1 of 500 tasks have results. 0 of them no arm resolves.');
  assert.equal(text(q(w, '.bench-vw')), 'Nothing can be told yet of where an arm wins or loses. Django is 46% of the set, so a run of the first 1 task leans on Django.');
  assert.deepEqual(Array.from(page(w).querySelectorAll('button.bench-sq'), (b) => [b.dataset.t, b.className]), [[BH.FEW_TASK, 'bench-sq bench-sq-all']]);
  assert.equal(page(w).querySelectorAll('span.bench-sq[data-t]').length, 499);
});

// ---- Plan a run ----
// Bug it guards: Start a run asked for a number of tasks first, with no word of what that number can tell. Plan a run
// takes the question first, which sets the tasks and arms, and shows the arms' state, cost and kept results, what the
// size can show and, before Start, the cost, time, sessions, the usage guard and the command it runs.
test('Plan a run, the study\'s arms: the questions set the tasks and arms, and Before you start shows the cost and the command', async () => {
  const w = await opened(BH.study(), 'plan');
  assert.equal(text(q(w, '.bench-answers')), 'This page answers: Which run answers my question, and what will it cost? Pick the question first. The planner sets the tasks and arms, and shows the cost before you start.');
  assert.deepEqual(heads(w), ['Arms', 'Tasks', 'Before you start']);
  assert.deepEqual(Array.from(page(w).querySelectorAll('.bench-q'), (x) => [x.dataset.q, x.getAttribute('aria-pressed')]), [['works', 'false'], ['better', 'true'], ['value', 'false']]);
  assert.deepEqual(rows(q(w, '.bench-planarms')).map((r) => r.slice(1)), [['Conveyor', 'ready', '$1.92', '21', '50'], ['Conveyor, Codex builds', 'ready', '$1.38', '18', '50'], ['Claude, then a review', 'ready', '$0.61', '6', '50'],
    ['Codex alone', 'ready', '$0.44', '5', '50'], ['Claude + Superpowers', 'expired', '$0.93', '9', '50'], ['Claude alone', 'ready', '$0.31', '3', '50'], ['Claude + Caveman', 'changed', '$0.27', '3', '50']]);
  assert.equal(text(q(w, '.bench-pdet')), 'Shows a difference of 10 tasks (20%) or more');
  assert.equal(text(q(w, '.bench-before .bench-hsub')), '2 arms × 50 tasks');
  assert.equal(text(q(w, '.bench-before .bench-callout')), 'Good for arms: a gap of 20% or more shows, and Conveyor against Claude alone was 24 points in the last study. Two Conveyor versions differed by 2 to 40 points in the last study: a 2-point gap needs 5000 tasks.');
  assert.deepEqual(kv(q(w, '.bench-before')), [['Cost', '$0.00 at list prices'], ['Machine time', '0 min tasks run one after another'], ['Sessions', '0 usual, 0 at worst'],
    ['Kept results', '100 task runs reused at no cost'], ['Usage guard', 'not reached'], ['Belt', 'Cards and the run share the machine. Each task\'s container gets 4 CPUs and 8g.']]);
  assert.equal(q(w, '.bench-cmd').textContent, 'conveyor.sh bench swe 50 --arm conveyor --arm solo');
  act(bp(w), 'q-works').click();
  assert.equal(q(w, '.bench-cmd').textContent, 'conveyor.sh bench swe 5 --arm conveyor');
  assert.equal(text(q(w, '.bench-before .bench-callout')), 'Right size: enough to see a break, cheap.');
  act(bp(w), 'q-value').click();
  assert.equal(q(w, '.bench-cmd').textContent, 'conveyor.sh bench swe 30 --arm conveyor --arm conveyor-codex-claude --arm solo-review --arm codex-sol --arm solo', 'every ready arm');
  assert.equal(text(q(w, '.bench-before .bench-callout')), 'Ranks 5 arms. Arms closer than 26% share a tier.', 'the noise of 30 tasks is 8 (SWE_NOISED), 26.7%: rounded down, as 8 apart (27%) are told apart');
});

// Bug it guards: the size of a run and what it can tell were apart, and Start could send other arguments than the page
// said. Moving the slider changes the difference the run can show and its cost; Start sends the command the page shows.
// A drag is many input events on the one slider: a slider drawn anew on the first lost the drag (review E7). The
// difference is the engine's noise, sqrt(200) = 14.1 rounded up to 15 (SWE_NOISED): 14 promised one it does not tell (E8).
// Its share is rounded up too: at 500 tasks the noise is 32, 6.4%, and 6% (30 tasks) promised a gap under it (E8).
test('Plan a run: the slider changes the difference it can show and the cost, and Start runs the command the page shows', async () => {
  const w = await opened(BH.study(), 'plan');
  const range = act(bp(w), 'plan-n');
  range.value = '500'; range.dispatchEvent(new w.Event('input'));
  assert.equal(text(q(w, '.bench-pdet')), 'Shows a difference of 32 tasks (7%) or more');
  assert.match(text(q(w, '.bench-before .bench-callout')), /^Good for arms: a gap of 7% or more shows[.,]/);
  range.value = '120'; range.dispatchEvent(new w.Event('input'));
  assert.equal(act(bp(w), 'plan-n'), range, 'the slider dragged is still the one on the page');
  assert.equal(text(q(w, '.bench-pdet')), 'Shows a difference of 16 tasks (14%) or more');
  range.value = '100'; range.dispatchEvent(new w.Event('input'));
  assert.equal(act(bp(w), 'plan-n'), range);
  assert.equal(text(q(w, '.bench-pdet')), 'Shows a difference of 15 tasks (15%) or more');
  assert.deepEqual(kv(q(w, '.bench-before')).slice(0, 4), [['Cost', '$112 at list prices'], ['Machine time', '20.0 h tasks run one after another'], ['Sessions', '250 usual, 500 at worst'],
    ['Kept results', '100 task runs reused at no cost']], 'tasks 51 to 100 have no kept result: 50 of each arm cost');
  const shown = q(w, '.bench-cmd').textContent;
  w.reply = BH.reply('conveyor: run r20261109T170000-9 started');
  act(bp(w), 'start').click();
  const [sent] = w.posts.splice(0);
  assert.deepEqual(sent.body, { action: 'bench', args: ['run', '100', '--arm', 'conveyor', '--arm', 'solo'], repo: 'sample' });
  assert.equal(shown, `conveyor.sh bench swe ${sent.body.args.slice(1).join(' ')}`, 'the command shown is the one sent');
  await settle();
  // An arm not ready holds Start, and Check the arms first sends its preflight.
  act(bp(w), 'arm-caveman').click();
  assert.equal(act(bp(w), 'start').disabled, true);
  w.reply = BH.reply('caveman: checking c1');
  act(bp(w), 'check-arms').click();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [['arms', 'check', 'caveman']]);
});

// Bug it guards (#1197, the owner: none of the extras stay): Plan a run kept a Conveyor version pick and a Run settings
// fold that the approved mockup does not have, and a Start that could send --engine and --settings. The page has
// neither, and Start sends the command the page shows, with the engine's default settings.
test('Plan a run: no Conveyor version pick and no Run settings fold, and Start sends the command the page shows', async () => {
  const w = await opened(BH.study(), 'plan');
  assert.equal(q(w, '[data-act="plan-engine"]'), null, 'no Conveyor version pick');
  assert.equal(q(w, '[data-act="plan-commit"]'), null, 'no commit field');
  assert.equal(q(w, '[data-fold="plan-settings"]'), null, 'no Run settings fold');
  assert.equal(page(w).querySelectorAll('input[data-act^="set-"]').length, 0, 'no run setting field');
  const shown = q(w, '.bench-cmd').textContent;
  assert.equal(shown, 'conveyor.sh bench swe 50 --arm conveyor --arm solo');
  w.reply = BH.reply('conveyor: run r20261109T170000-9 started');
  act(bp(w), 'start').click();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [['run', '50', '--arm', 'conveyor', '--arm', 'solo']], 'the default settings: no --engine and no --settings');
  await settle();
  assert.match(text(q(w, '[data-said="start"]')), /run r20261109T170000-9 started/, 'the answer to Start shows beside it');
  assert.equal(q(w, '.bench-why'), null, 'no why-not note under Start');
  // Bug it guards: a Start the build machine refuses before it records a run (the usage guard moved since the page read it)
  // showed nothing, as the page had no place for its answer.
  w.reply = { ok: false, status: 409, text: () => Promise.resolve('conveyor: the usage guard is reached') };
  act(bp(w), 'start').click();
  await settle();
  assert.match(text(q(w, '[data-said="start"]')), /Not done: .*usage guard is reached/, 'a refused Start says why');
  act(bp(w), 'arm-caveman').click();
  assert.equal(act(bp(w), 'start').disabled, true, 'an arm not ready still holds Start');
});

// Bug it guards: with no kept result on the engine now, the plan counted none to run, and a cost it could not price
// read as $0. The Conveyor arm has no result on main's commit (0, new engine), Claude alone has its 1, and the cost is
// that of the rest.
test('Plan a run, 2 runs of 1 task: the arms with their state and kept results, and the cost of the tasks not kept', async () => {
  const w = await opened(BH.few(), 'plan');
  const arms = rows(q(w, '.bench-planarms'));
  assert.equal(arms.length, 15);
  assert.deepEqual(arms.slice(0, 5).map((r) => [r[1], r[2], r[5]]), [['conveyor', 'ready', '0 (new engine)'], ['conveyor-codex-claude', 'ready', '0 (new engine)'], ['solo-review', 'ready', '1'], ['solo', 'ready', '1'], ['ponytail', 'expired', '1']]);
  assert.equal(text(q(w, '.bench-before .bench-callout')), 'Good for arms: a gap of 20% or more shows. A 10-point gap needs 200 tasks.');
  assert.deepEqual(kv(q(w, '.bench-before')).slice(0, 4), [['Cost', '$111 at list prices'], ['Machine time', '19.9 h tasks run one after another'], ['Sessions', '249 usual, 449 at worst'], ['Kept results', '1 task runs reused at no cost']]);
});

// Bug it guards (#1197, the owner: none of the extras stay): the tab kept buttons, notes and states that the approved
// mockup does not have: Read the commits, Ask for the readings, the Conveyor version pick, the Run settings fold, the
// Start receipt and why-not note, and notes such as "Left out, not priced". No page of any fixture has one; Versions and
// Compare load their commits and readings by themselves. One case for each fixture, as each is paid for once.
const NOT_THERE = ['Read the commits', 'Ask for the readings', 'builds with it', 'Run settings', 'Left out, not priced', 'Steps not kept', 'No Conveyor arm ran', 'none run twice',
  'No event yet', 'The task list of the set is not read', 'Nothing can be told yet from 1 task', 'Watch run', 'Open its results'];
const NO_CONTROL = ['[data-act="read-commits"]', '[data-act="cmp-read"]', '[data-act="plan-engine"]', '[data-act^="set-"]', '[data-fold="plan-settings"]', '[data-act="watch-run"]', '.bench-why'];
async function noExtras(set) {
  const w = await opened(set);
  for (const p of ['score', 'versions', 'compare', 'run', 'task', 'map', 'plan']) {
    BH.go(w, p);
    await settle(); await settle();
    NOT_THERE.forEach((t) => assert.ok(!text(page(w)).includes(t), `the ${p} page has no "${t}"`));
    NO_CONTROL.forEach((c) => assert.equal(q(w, c), null, `the ${p} page has no ${c}`));
  }
}
test('No extras on any page, 7 arms on 50 tasks', async () => { await noExtras(BH.study()); });
test('No extras on any page, 2 runs of 1 task', async () => { await noExtras(BH.few()); });
test('No extras on any page, 7 arms on 50 tasks going', async () => { await noExtras(BH.live()); });
// The states that the three fixtures above never reach, each of which once drew a note: a run going with no event yet, a
// set whose task list is not read, an arm with no priced result, a lost task whose steps are not kept.
test('No extras on any page, with no event, no task list, an unpriced arm and no steps kept', async () => {
  const set = BH.live();
  set.hist.order = [];
  Object.values(set.shows).forEach((s) => { if (s.tail) s.tail = []; s.tasks.forEach((t) => t.cells.forEach((c) => { if (c.arm === 'solo') c.cost = null; if (/^conveyor/.test(c.arm)) c.steps = []; })); });
  await noExtras(set);
});
