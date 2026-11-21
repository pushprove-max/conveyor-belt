// SPDX-License-Identifier: Apache-2.0
// The Benchmarks tab's Scoreboard and Versions (#1177, the owner's approved mockup): each page's sections in the
// mockup's order with its headings and the fixture's figures, in the mockup's Sample view (BH.study(), 7 arms on 50
// tasks) and its "Your data now" view (BH.few(), 2 runs of 1 task kept before the grade's report); the Scoreboard's
// tiers by the noise of sqrt(2n) tasks; and the page the tab opens on. The runs come from GET bench, not the snapshot.
// Shared setup: dashboard-view.helpers.mjs (BH).
import assert from 'node:assert/strict';
import { boot, settle, act, cases, BH, tabBtn, T0, iso } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const { bp, page, heads, pages, TASKS, OLDS } = BH;
const text = (el) => el.textContent.replace(/\s+/g, ' ').trim();
const q = (w, s) => page(w).querySelector(s);
const rows = (el) => Array.from(el.querySelectorAll('tbody tr'), (r) => Array.from(r.children, text));
const stats = (w) => Array.from(page(w).querySelectorAll('.bench-stat'), (s) => Array.from(s.children, text));
const box = (w, title) => Array.from(page(w).querySelectorAll('.bench-box')).find((b) => b.querySelector('.bench-h') && b.querySelector('.bench-h').firstChild.textContent.trim() === title);
async function opened(set, p) {
  const w = boot({ tab: 'bench' });
  BH.open(w, set);
  await settle(); await settle();
  if (p) { BH.go(w, p); await settle(); await settle(); }
  return w;
}

// Bug it guards: the tab's overview was a pile of bars and figures that answered no question. The Scoreboard is the
// mockup's: the question, the verdict on the shared tasks, 4 figures, the leaderboard, the value chart, hidden tests,
// patch quality, lines of code, effort, where Conveyor loses tasks, what the arms agree on, the next run and the run
// history folded at its foot, each with the fixture's figures.
test('Scoreboard, 7 arms on 50 tasks: the mockup\'s sections in its order, with the figures of the study', async () => {
  const w = await opened(BH.study());
  assert.equal(pages(w).find(([, c]) => c === 'page')[0], 'Scoreboard', 'with no run going the tab opens on the Scoreboard');
  assert.deepEqual(pages(w).map(([p]) => p), ['Scoreboard', 'Versions', 'Compare', 'Live run', 'Task', 'Task map', 'Plan a run']);
  assert.equal(text(q(w, '.bench-answers')), 'This page answers: Which way of building a change resolves the most real issues, at what cost, and how sure can you be?');
  assert.deepEqual(heads(w), ['Verdict on the 50 shared tasks', 'Leaderboard', 'Value: resolve rate against cost', 'Hidden tests', 'Patch quality', 'Lines of code',
    'Effort and steadiness', 'Where Conveyor loses tasks', 'What it agrees on', 'Next run to make', 'Run history (7 runs, 1 archived)']);
  assert.equal(text(q(w, '.bench-vv')), 'Conveyor v1.9.0 resolves 37 of 50, 12 more than Claude alone. That gap is larger than the noise (10 tasks), so it is real.');
  assert.equal(text(q(w, '.bench-vw')), 'It ties with Conveyor, Codex builds v1.9.0 (35 of 50): the difference is inside the noise. Per resolved task, Claude + Caveman is the cheapest at $0.61.'
    + ' Conveyor v1.9.0 costs $2.59 per resolved task, 4.2 times as much, for 15 more fixes. 30 of its 37 fixes are clean, against 20 of 25 for Claude alone, and its patches broke other tests in 2 tasks, against 6.');
  assert.deepEqual(stats(w), [['37/50', 'Best resolved (Conveyor v1.9.0)', '+2 on v1.8.0, inside the noise'], ['$2.59', 'Conveyor: cost per resolved task', 'list prices, all sessions'],
    ['21 min', 'Conveyor: minutes a task', 'median, this machine'], ['13', 'Tasks no arm resolves', 'See them on the task map']]);
  const lead = rows(q(w, '.bench-leader'));
  assert.deepEqual(lead[0], ['1', 'Conveyor v1.9.0 Conveyor', '37/50', '', '30', '2', '$2.59', '21', '100%']);
  assert.deepEqual(lead[6], ['2tie', 'Claude + Caveman', '22/50', '', '18', '6', '$0.61from tokens', '3', '92%'], 'Caveman did not fire on 4 of 50 tasks');
  // The value chart: a point an arm, and the line of the arms no other arm beats on both (Superpowers is beaten by Codex alone).
  assert.equal(box(w, 'Value: resolve rate against cost').querySelectorAll('g.bench-pt').length, 7);
  assert.equal(box(w, 'Value: resolve rate against cost').querySelector('polyline.bench-front').getAttribute('points').split(' ').length, 6);
  assert.equal(text(box(w, 'Value: resolve rate against cost').querySelector('.bench-callout')), 'Conveyor v1.9.0 buys its 12 extra fixes at $6.71 each over Claude alone.');
  assert.deepEqual(rows(box(w, 'Hidden tests'))[0], ['Conveyor v1.9.0', '81 of 94 86%', '4 in 2 tasks', '3']);
  assert.deepEqual(rows(box(w, 'Patch quality'))[0], ['Conveyor v1.9.0', '30/37', '100%', '100%', '19%', '100%']);
  assert.deepEqual(rows(box(w, 'Lines of code'))[0], ['Conveyor v1.9.0', '+9 −3', '+14', '2.0', '1.3×']);
  assert.equal(text(box(w, 'Lines of code').querySelector('.bench-hsub')), 'Medians over each arm\'s resolved tasks. The reference fix of a median task is +7 −3 in 1 file.');
  assert.deepEqual(rows(box(w, 'Effort and steadiness')).map((r) => r.slice(1)), [['554k', '4.0', '1.0', '1.0', '0', '90%'], ['514k', '4.0', '1.0', '1.0', '0', '88%'],
    ['153k', '2.0', 'no review', '—', '0', '80%'], ['200k', '1.0', 'no review', '—', '0', '78%'], ['276k', '1.0', 'no review', '—', '2', '74%'], ['96k', '1.0', 'no review', '—', '0', '76%'], ['70k', '2.0', 'no review', '—', '0', '70%']]);
  assert.deepEqual(Array.from(box(w, 'Where Conveyor loses tasks').querySelectorAll('.bench-lrow'), text),
    ['Build: wrong or no change2', 'Review: passed a wrong change3', 'Fix round: broke it again3', 'Test step: tests wrong3', 'Blocked: never landed2']);
  assert.deepEqual(Array.from(box(w, 'What it agrees on').querySelectorAll('.bench-col'), (c) => [c.dataset.arms, c.firstChild.textContent]),
    [['0', '13'], ['1', '2'], ['2', '4'], ['3', '1'], ['4', '1'], ['5', '4'], ['6', '3'], ['7', '22']]);
  assert.deepEqual(Array.from(box(w, 'Next run to make').querySelectorAll('li'), text), [
    // The noise of 150 tasks as the engine says it (SWE_NOISED): sqrt(300) = 17.3, rounded up to 18.
    'Conveyor v1.9.0 against Conveyor, Codex builds v1.9.0: tied at 50 tasks. 100 more tasks (150 in all) show a difference of 18 tasks, 12%. About $330, 65.0 h of machine time. open question',
    'Claude + Caveman fired in only 92% of tasks. Check its arm before the next run. arm problem', 'Tasks 51 to 100 have no result yet for any arm.']);
  const hist = q(w, 'details.bench-history');
  assert.equal(hist.open, false, 'the run history is folded');
  assert.deepEqual(Array.from(hist.querySelectorAll('tbody tr'), (r) => r.dataset.run), [BH.STUDY, ...OLDS.map(([, id]) => id), BH.ARCHIVED]);
  // Clicking an arm opens Compare: the Conveyor arm against it.
  page(w).querySelector('.bench-leader tr[data-cmp="solo"]').click();
  await settle();
  assert.equal(pages(w).find(([, c]) => c === 'page')[0], 'Compare');
  assert.deepEqual([act(bp(w), 'cmp-a').value, act(bp(w), 'cmp-b').value], ['arm:conveyor', 'arm:solo']);
});

// Bug it guards: a card whose test step failed, then failed again after its fix round, is blocked at the end; the loss was
// counted at Blocked, a later step, not at the Test step where it first went wrong. One blocked task of the study gets that
// card: Blocked drops from 2 to 1 and Test step rises from 3 to 4. A blocked card with no failed test step stays Blocked.
test('Scoreboard: a card blocked after its tests failed twice is lost at the test step, not at Blocked', async () => {
  const set = BH.study(), conv = set.shows[BH.STUDY].tasks.map((t) => t.cells.find((c) => c.arm === 'conveyor')).find((c) => c.steps.some((s) => s.step === 'blocked'));
  const at = (step, result) => ({ step, result, time: conv.steps[0].time });
  conv.steps = [at('build', 'ok'), at('review', 'GO'), at('test', 'fail'), at('fix', 'ok'), at('test', 'fail'), { ...at('blocked', 'blocked'), reason: 'the changed tests failed again after their one fix round (exit 1); nothing landed.' }];
  const w = await opened(set);
  assert.deepEqual(Array.from(box(w, 'Where Conveyor loses tasks').querySelectorAll('.bench-lrow'), text),
    ['Build: wrong or no change2', 'Review: passed a wrong change3', 'Fix round: broke it again3', 'Test step: tests wrong4', 'Blocked: never landed1']);
});

// Bug it guards: two arms a few tasks apart were ranked one above the other, as if 50 tasks could tell them apart. An
// arm closer to the leader of its tier than sqrt(2n) tasks shares that tier: on 50 tasks the noise is 10, so Conveyor
// (37) and Claude alone (25), 12 apart, are told apart, and Claude alone and Caveman (22), 3 apart, are a tie.
test('Scoreboard: the tiers and the verdict follow the sqrt(2n) noise rule: 12 tasks apart on 50 is told apart, 3 apart is a tie', async () => {
  const w = await opened(BH.study());
  const lead = rows(q(w, '.bench-leader')).map(([tier, arm, k]) => [tier, arm, k]);
  assert.deepEqual(lead, [['1', 'Conveyor v1.9.0 Conveyor', '37/50'], ['1tie', 'Conveyor, Codex builds v1.9.0 Conveyor', '35/50'], ['1tie', 'Claude, then a review', '31/50'], ['1tie', 'Codex alone', '30/50'],
    ['1tie', 'Claude + Superpowers', '29/50'], ['2', 'Claude alone', '25/50'], ['2tie', 'Claude + Caveman', '22/50']]);
  assert.match(text(q(w, '.bench-vv')), /12 more than Claude alone\. That gap is larger than the noise \(10 tasks\), so it is real\.$/);
  assert.ok(q(w, '.bench-verdict').classList.contains('bench-verdict-ok'));
  // The same study with Claude alone resolving 9 tasks more (34): 3 under Conveyor, so it shares Conveyor's tier and the
  // verdict says the gap is not proven; Caveman, 15 under, is the next tier.
  const set = BH.study();
  set.shows[BH.STUDY].tasks.forEach((t, i) => { if (i >= 25 && i < 34) Object.assign(t.cells[5], { result: 'resolved', resolved: true, class: 'resolved' }); });
  const v = await opened(set);
  assert.equal(text(page(v).querySelector('.bench-vv')), 'Conveyor v1.9.0 resolves 37 of 50, 3 more than Claude alone. That gap is inside the noise (10 tasks): not proven yet.');
  assert.ok(page(v).querySelector('.bench-verdict').classList.contains('bench-verdict-quiet'));
  assert.deepEqual(rows(page(v).querySelector('.bench-leader')).map(([tier, arm]) => [tier, arm]), [['1', 'Conveyor v1.9.0 Conveyor'], ['1tie', 'Conveyor, Codex builds v1.9.0 Conveyor'],
    ['1tie', 'Claude alone'], ['1tie', 'Claude, then a review'], ['1tie', 'Codex alone'], ['1tie', 'Claude + Superpowers'], ['2', 'Claude + Caveman']]);
});

// Bug it guards (#1195): a task whose only run was archived still counted in "Tasks with a result". History's keys keep it
// in at (a new run reuses its result) but not in live; the Scoreboard counts live.
test('Scoreboard, 2 runs of 1 task: a task with a kept result but only an archived run is not a task with a result', async () => {
  const set = BH.few();
  set.hist.keys.forEach((k) => { k.live = []; });
  const w = await opened(set);
  assert.deepEqual(stats(w)[1], ['0 of 500', 'Tasks with a result', '0.0% of the set']);
});

// Bug it guards: with 2 runs of 1 task, the tab drew the bars and figures as if they said something, and showed a
// figure the result never kept as 0. The Scoreboard says nothing can be told yet, shows what the runs have, and each
// figure not kept says so (a patch not kept: its lines; the grade's report: hidden tests, lint, proves the fix).
test('Scoreboard, 2 runs of 1 task: nothing can be told yet, and what the results did not keep says not kept', async () => {
  const set = BH.few();
  set.shows[BH.FEW1].tasks[0].cells[1].patch = null;
  const w = await opened(set);
  assert.deepEqual(heads(w), ['Verdict on the tasks you have', 'Leaderboard', 'Hidden tests and patch quality', 'Next run to make', 'Run history (2 runs, 0 archived)']);
  assert.ok(q(w, '.bench-verdict').classList.contains('bench-verdict-quiet'));
  assert.equal(text(q(w, '.bench-vv')), 'Nothing can be told yet. Every arm resolved the one task it ran.');
  assert.equal(text(q(w, '.bench-vw')), `Your 2 runs each ran 1 task, ${BH.FEW_TASK}. With 1 task, only a total break shows: the 95% range of every arm is 21% to 100%. To tell Conveyor from Claude alone, run 50 tasks or more.`);
  assert.deepEqual(stats(w), [['2', 'Runs', 'both 1 task'], ['1 of 500', 'Tasks with a result', '0.2% of the set'], ['$0.49', 'Conveyor: cost of its task', '3 sessions, 77k tokens'],
    ['4 of 15', 'Arms checked and ready', '10 never checked']]);
  const [lead] = page(w).querySelectorAll('.bench-t');
  assert.deepEqual(rows(lead).map((r) => [r[0], r[1], r[3], r[4], r[5]]), [['Conveyor, Codex builds v1.7.0', '1/1', '$0.50', '81k', '3.2'], ['Claude + Ponytail', '1/1', 'not priced', '64k', '0.9'],
    ['Claude, then a review', '1/1', 'not priced', '13k', '0.8'], ['Claude alone', '1/1', 'not priced', '2k', '0.5'], ['Conveyor v1.7.0', '1/1', '$0.49', '77k', '2.9']]);
  // Each arm its own colour whatever its place (review E12): the mockup's Claude + Ponytail is series 5 and Claude alone
  // series 4, on the Scoreboard and on Plan a run alike; by place they took 3 and 2.
  const dots = (el) => Object.fromEntries(Array.from(el.querySelectorAll('tbody tr'), (r) => [text(r).split(/\d/)[0], r.querySelector('.bench-dot').className]));
  assert.deepEqual([dots(lead)['Claude + Ponytail'], dots(lead)['Claude alone']], ['bench-dot bench-s5', 'bench-dot bench-s4']);
  BH.go(w, 'plan');
  assert.equal(page(w).querySelector('.bench-planarms tr[data-arm="solo"] .bench-dot').className, 'bench-dot bench-s4');
  BH.go(w, 'score');
  assert.deepEqual(rows(page(w).querySelectorAll('.bench-t')[1]), [['Conveyor, Codex builds v1.7.0', '+1 −1', '+7', '2'], ['Claude + Ponytail', 'not kept', 'not kept', 'not kept'], ['Claude, then a review', '+1 −1', 'none', '1'],
    ['Claude alone', '+1 −1', 'none', '1'], ['Conveyor v1.7.0', '+1 −1', '+7', '2']], 'the lines come from the patches kept; a patch not kept is not kept, never 0');
  assert.match(text(q(w, '.bench-callout-warn')), /^Every arm passed the task's hidden tests: that is all the results keep\. The run records resolved yes or no and the patch, and the harness report with each fail-to-pass and pass-to-pass test is removed\./);
  assert.deepEqual(Array.from(box(w, 'Next run to make').querySelectorAll('li'), text), ['Is Conveyor better than Claude alone? 50 tasks, 2 arms: about $112 and 20.0 h of machine time. Shows a 10-task difference.',
    'Does v1.7.0 work at all? 5 tasks, Conveyor only: about $9.60 and 1.8 h of machine time.', 'The other 10 arms were never checked. A check costs 1 small task each.']);
});

// Bug it guards: nothing told whether a new engine version made Conveyor better or worse. Versions has the mockup's
// verdict on the newest version against the one before, the resolve rate by version with its band and the Claude alone
// line, the table with each change judged against the noise, the drift watch and the tasks that flipped, whose commits
// are read from `bench swe diff --json`, which the page asks for by itself.
test('Versions, 6 versions of the Conveyor arm: the verdict, the trend, the table, the drift watch and the flipped tasks with their commits', async () => {
  const set = BH.study();
  // v1.9.0's result of TASKS[36] is one a run with --again kept apart (show's again): the diff reads only the kept one.
  set.shows[BH.STUDY].tasks[36].cells.find((c) => c.arm === 'conveyor').again = BH.STUDY;
  const w = boot({ tab: 'bench' });
  BH.open(w, set);
  await settle(); await settle();
  // The diff of TASKS[35] read v1.9.0
  // unresolved, and the one of TASKS[36] read the same outcomes as shown but v1.9.0's shown result is an --again run's,
  // another trial (E4): the commits of neither are shown. Changed steps are the diff's steps, a task flipped or not:
  // v1.7.0 to v1.8.0 flipped no task, and its test step changed (E5); a diff that could not map the files says not known.
  const key = (v) => `conveyor-${v[3].repeat(40)}`, ans = [{ flipped: [{ task: TASKS[34], apart: 'review', a: { resolved: false }, b: { resolved: true }, changes: [{ commit: 'abc1234', title: 'the review reads the test step' }] },
    { task: TASKS[35], apart: 'review', a: { resolved: false }, b: { resolved: false }, changes: [{ commit: 'def5678', title: 'another result' }] },
    { task: TASKS[36], apart: 'fix', a: { resolved: false }, b: { resolved: true }, changes: [{ commit: 'fed9876', title: 'the kept trial' }] }, { task: TASKS[37], apart: 'review', a: { resolved: true }, b: { resolved: false }, changes: [] }],
  steps: ['review'] }, { flipped: [], steps: ['test'] }, { flipped: [], steps: [] }, { flipped: [], steps: null }, { flipped: [], steps: ['build', 'review'] }];
  w.reply = { ok: true, status: 200, text: () => Promise.resolve(JSON.stringify(ans.shift())) };
  BH.go(w, 'versions');
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [['diff', key('v1.8.0'), key('v1.9.0'), '--json']], 'the page asks for the newest pair by itself, and for one at a time');
  assert.equal(text(q(w, '.bench-answers')), 'This page answers: Did a change to the engine make Conveyor better or worse? Two sources: benchmark runs of each version, and the cards the belt builds anyway (the drift watch, at no cost).');
  assert.deepEqual(heads(w), ['v1.9.0 against v1.8.0', 'Resolve rate by engine version', 'Drift watch: the belt\'s own cards', 'Tasks that flipped from v1.8.0 to v1.9.0']);
  assert.equal(text(q(w, '.bench-vv')), 'No regression. v1.9.0 resolves 37 of 50, 2 more than v1.8.0: inside the noise of 10 tasks.');
  assert.equal(text(q(w, '.bench-vw')), 'On the belt, cards on v1.9.0 waited less (4 min against 12 min a card): that moved past its usual range. The other figures stayed in their usual range.');
  const trend = q(w, 'svg.bench-trend');
  assert.deepEqual(Array.from(trend.querySelectorAll('text'), (t) => t.textContent).filter((t) => /^v|Claude/.test(t)), ['v1.4.0', 'v1.5.0', 'v1.6.0', 'v1.7.0', 'v1.8.0', 'v1.9.0', 'Claude alone']);
  assert.equal(trend.querySelectorAll('circle.bench-vdot').length, 6);
  // Each change is judged on the tasks both versions ran (review E3): v1.4.0 ran the first 20, which v1.5.0 resolves all
  // of, against 12: 8 tasks of 20, past the noise of 7. On their rates alone (62% against 60%) it read +2 pts, noise.
  const table = () => rows(q(w, '.bench-versions')).map((r) => [r[0], r[2], r[3], r[4], r[5]]);
  assert.deepEqual(table(), [['v1.4.0', '20', '12', 'first', '—'], ['v1.5.0', '50', '31', '+40 pts, better', '—'],
    ['v1.6.0', '50', '29', '-4 pts, noise', '—'], ['v1.7.0', '50', '34', '+10 pts, noise', '—'], ['v1.8.0', '50', '35', '+2 pts, noise', '—'], ['v1.9.0', '50', '37', '+4 pts, noise', '—']]);
  assert.deepEqual(Array.from(page(w).querySelectorAll('.bench-drow'), (r) => [r.dataset.figure, text(r.querySelector('.chip'))]),
    [['landed', 'In its usual range'], ['tokens', 'In its usual range'], ['minutes', 'In its usual range'], ['reviews', 'In its usual range'], ['fixes', 'In its usual range'], ['waits', 'Moved, better']]);
  const flips = () => rows(q(w, '.bench-flips'));
  assert.deepEqual(flips(), [[TASKS[34], 'now resolved', 'review', 'not read'], [TASKS[35], 'now resolved', 'review', 'not read'], [TASKS[36], 'now resolved', 'review', 'not read'],
    [TASKS[37], 'now unresolved', 'review', 'not read']]);
  // The answers come with no click: each pair's diff, the newest first, one at a time, each its own answer, and the page
  // asks for the next when one comes (E5: the rows before the newest had no changed steps).
  for (let i = 0; i < 30; i += 1) await settle();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [['7', '8'], ['6', '7'], ['5', '6'], ['4', '5']].map(([a, b]) => ['diff', key(`v1.${a}`), key(`v1.${b}`), '--json']),
    'the two versions\' results keys of each older pair, one request each');
  assert.deepEqual(flips().map((r) => r[3]), ['abc1234 the review reads the test step', 'not of the result shown (a run again)', 'not of the result shown (a run again)', 'none']);
  assert.deepEqual(table().map((r) => r[4]), ['—', 'build, review', '—', '—', 'test', 'review'], 'the steps whose files changed, once read, for each version after the first; a dash for none or not known');
  BH.go(w, 'score');
  BH.go(w, 'versions');
  await settle(); await settle();
  assert.deepEqual(w.posts.splice(0), [], 'a redraw, or a return to the page, asks for no diff again: each reading is a model call');
  page(w).querySelector(`.bench-flips tr[data-task="${TASKS[37]}"]`).click();
  await settle();
  assert.equal(text(q(w, '.bench-vk')), `matplotlib · ${TASKS[37]}`, 'a flipped task opens the Task page');
});

// Bug it guards: with one version run, the page drew a trend of one point and a drift watch that never ran as if it
// meant something. It says no version can be compared yet, how to run the drift watch, and what the page will show.
test('Versions, 2 runs of 1 task: no version can be compared yet, the drift watch has not run, and what the page will show', async () => {
  const w = await opened(BH.few(), 'versions');
  assert.deepEqual(heads(w), ['Versions with results', 'What this page will show']);
  assert.equal(text(q(w, '.bench-vv')), 'Only v1.7.0 has a result, on 1 task. No version can be compared yet.');
  assert.equal(text(q(w, '.bench-vw')), 'The drift watch needs no benchmark run: it reads the cards your belt builds. Today it has not run. Run conveyor.sh bench drift on the build machine, or let the Board run it after each release.');
  assert.equal(page(w).querySelectorAll('.bench-list li').length, 3);
});

// Bug it guards (review): with two versions on the one task both ran, the noise of 1 task is 1, so the newer version
// resolving it read "Better." from one task. Under 3 tasks both ran, nothing is told, in the verdict and the table.
test('Versions, two versions on 1 task: nothing can be told yet, though only the newer one resolves it', async () => {
  const set = BH.few(), l2 = set.hist.runs[1], s2 = set.shows[BH.FEW2], id = 'r20261107T100000-5', six = '6'.repeat(40);
  const line = { ...l2, id, started: iso(T0 - 48 * 3600000), ended: iso(T0 - 47 * 3600000), cols: l2.cols.map((c) => ({ ...c, key: `conveyor-${six}`, engine: six, version: 'v1.6.0', resolved: 0 })) };
  set.hist.runs.push(line);
  set.shows[id] = { run: line, tasks: [{ ...s2.tasks[0], cells: s2.tasks[0].cells.map((c) => ({ ...c, result: 'unresolved', resolved: false })) }], tail: [] };
  const w = await opened(set, 'versions');
  assert.equal(text(q(w, '.bench-vk')), 'v1.7.0 against v1.6.0');
  assert.equal(text(q(w, '.bench-vv')), 'Nothing can be told yet from 1 task both ran: v1.7.0 resolves 1, v1.6.0 0.');
  assert.ok(q(w, '.bench-verdict').classList.contains('bench-verdict-quiet'));
  assert.deepEqual(rows(q(w, '.bench-versions')).map((r) => r[4]), ['first', '+1 of 1, too few tasks']);
});

// Bug it guards (review E1): each arm read only its newest run, so a short run after the study (Conveyor and Claude
// alone on its first task again, the same results keys) hid their other 49 tasks: the shared tasks fell to 1, and the
// Task map by Claude alone showed 49 tasks not run yet. Every run of an arm on its results key adds its tasks.
test('A short run after the study keeps the arms\' other tasks on the Scoreboard and the Task map', async () => {
  const set = BH.study(), study = set.hist.runs[0], show = set.shows[BH.STUDY], id = 'r20261109T160000-11', two = ['conveyor', 'solo'];
  const line = { ...study, id, started: iso(T0 - 3600000), ended: iso(T0 - 1800000), n: 1, arms: two, cols: study.cols.filter((c) => two.includes(c.arm)).map((c) => ({ ...c, done: 1, resolved: 1 })) };
  set.hist.runs.unshift(line);
  set.shows[id] = { run: line, tasks: [{ ...show.tasks[0], cells: show.tasks[0].cells.filter((c) => two.includes(c.arm)) }], tail: [] };
  const w = await opened(set);
  assert.equal(text(q(w, '.bench-vk')), 'Verdict on the 50 shared tasks');
  BH.go(w, 'map');
  const s = act(bp(w), 'map-by');
  s.value = 'solo'; s.dispatchEvent(new w.Event('change'));
  assert.equal(page(w).querySelectorAll('button.bench-sq').length, 50, 'Claude alone has a result on each of the 50 tasks');
});

// Bug it guards (review E2): Versions put the versions in the order their runs started, so v1.8.0 run after v1.9.0
// read as the newer release. They go in the order of their releases, whatever order they ran in.
test('Versions: the versions go in their release order, not the order their runs started', async () => {
  const set = BH.study(), v18 = set.hist.runs.find((r) => r.id === OLDS[0][1]);
  v18.started = iso(T0 - 3600000);
  set.hist.runs = [v18, ...set.hist.runs.filter((r) => r !== v18)];
  const w = await opened(set, 'versions');
  assert.equal(text(q(w, '.bench-vk')), 'v1.9.0 against v1.8.0');
  assert.deepEqual(rows(q(w, '.bench-versions')).map((r) => r[0]), ['v1.4.0', 'v1.5.0', 'v1.6.0', 'v1.7.0', 'v1.8.0', 'v1.9.0']);
});

// Bug it guards (review E11): with a group of fewer than 5 cards (drift.sh's small), no figure is judged, yet the
// verdict said every figure stayed in its usual range.
test('Versions: with too few cards in the drift watch, the verdict says no figure is judged', async () => {
  const set = BH.study();
  set.drift.small = ['after'];
  const w = await opened(set, 'versions');
  assert.equal(text(q(w, '.bench-vw')), 'On the belt, a group has fewer than 5 cards: no figure is judged yet.');
  assert.deepEqual(Array.from(page(w).querySelectorAll('.bench-drow .chip'), text), Array(6).fill('Too few cards'));
});

// Bug it guards (#646): the tab opened on the page left last, so a run going was a click away. It opens on the Live
// run while a run goes, else on the Scoreboard, each time it is shown.
test('The tab opens on the Live run while a run goes, else on the Scoreboard, each time it is shown', async () => {
  const w = await opened(BH.live());
  assert.equal(pages(w).find(([, c]) => c === 'page')[0], 'Live run');
  BH.go(w, 'map');
  tabBtn(w, 'overview').click();
  await settle();
  tabBtn(w, 'bench').click();
  await settle();
  assert.equal(pages(w).find(([, c]) => c === 'page')[0], 'Live run', 'shown again, it opens on the run going');
  const v = await opened(BH.study(), 'plan');
  tabBtn(v, 'overview').click();
  await settle();
  tabBtn(v, 'bench').click();
  await settle();
  assert.equal(pages(v).find(([, c]) => c === 'page')[0], 'Scoreboard');
});
