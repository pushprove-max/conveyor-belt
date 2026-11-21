// SPDX-License-Identifier: Apache-2.0
// The Benchmarks tab's edge states against the owner's approved mockup (#1224, slice 2 of #1222): where a page has no data,
// it shows the mockup's section with "not kept" in the mockup's place, never a sentence of its own; the plan's buttons
// are on where the mockup has them on, and say why where one is off; Archive, Restore, Delete and the "archived" chip stay,
// also in the few page's history fold. One case for each fixture (BH.study(), 7 arms on 50 tasks; BH.few(), 2 runs of 1
// task; BH.live(), a run going), changed to reach the state. The tests use jsdom only. Shared setup: dashboard-view.helpers.mjs (BH).
import assert from 'node:assert/strict';
import { boot, settle, act, cases, BH, iso, T0 } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const { bp, page, TASKS, STUDY } = BH;
const text = (el) => el.textContent.replace(/\s+/g, ' ').trim();
const q = (w, s) => page(w).querySelector(s);
const rows = (el) => Array.from(el.querySelectorAll('tbody tr'), (r) => Array.from(r.children, text));
const kv = (el) => Array.from(el.querySelectorAll('dt'), (d) => [d.textContent, text(d.nextElementSibling)]);
const box = (w, title) => Array.from(page(w).querySelectorAll('.bench-box')).find((b) => b.querySelector('.bench-h') && b.querySelector('.bench-h').firstChild.textContent.trim() === title);
const stat = (w, label) => Array.from(page(w).querySelectorAll('.bench-stat')).find((s) => text(s.children[1]) === label);
async function opened(set, p) {
  const w = boot({ tab: 'bench' });
  BH.open(w, set);
  await settle(); await settle();
  if (p) { BH.go(w, p); await settle(); await settle(); }
  return w;
}
const go = async (w, p) => { BH.go(w, p); await settle(); await settle(); };
const pickArm = async (w, which, v) => { const s = act(bp(w), `cmp-${which}`); s.value = v; s.dispatchEvent(new w.Event('change')); await settle(); await settle(); };
const tick = (w, id, on) => { const b = act(bp(w), `pick-${id}`); b.checked = on; b.dispatchEvent(new w.Event('change')); };
// A sentence the page must not say, with the page that says it, as a failure message.
const none = (w, p, sentences) => sentences.forEach((s) => assert.ok(!text(page(w)).includes(s), `the ${p} page has no "${s}"`));
// The study with Claude alone the only arm that has results.
function oneArm() {
  const s = BH.study(), run = s.hist.runs.find((r) => r.id === STUDY);
  Object.assign(run, { cols: run.cols.filter((c) => c.arm === 'solo'), arms: ['solo'] });
  s.hist.runs = [run];
  s.hist.keys = s.hist.keys.filter((k) => k.key === 'solo');
  s.shows = { [STUDY]: { ...s.shows[STUDY], tasks: s.shows[STUDY].tasks.map((t) => ({ ...t, cells: t.cells.filter((c) => c.arm === 'solo').map((c) => ({ ...c, cost: null, ref: null })) })) } };
  return s;
}

// ---- Scoreboard ----
// Bug it guards: with one arm the verdict said "One arm has results: there is no other arm to set it against.", the Value
// card said "No arm is priced: the chart needs the cost of each task." and Lines of code said "The size of the reference fix
// is not kept.", sentences of their own where the mockup has its sections: the mockup's place says not kept. Compare with
// one arm said "Compare needs two arms with results." and "Plan a run with two arms or more."
test('Scoreboard and Compare, one arm with results, no price and no reference fix: not kept in the mockup\'s place', async () => {
  const w = await opened(oneArm());
  assert.equal(text(q(w, '.bench-vv')), 'Claude alone resolves 25 of 50.');
  assert.equal(q(w, '.bench-vw'), null, 'no line about another arm');
  assert.equal(text(box(w, 'Value: resolve rate against cost').lastElementChild), 'not kept', 'the chart\'s place');
  assert.equal(text(box(w, 'Lines of code').querySelector('.bench-hsub')), 'Medians over each arm\'s resolved tasks. The reference fix of a median task is not kept.');
  none(w, 'scoreboard', ['no other arm to set it against', 'No arm is priced', 'The size of the reference fix is not kept']);
  await go(w, 'compare');
  assert.deepEqual([text(q(w, '.bench-vk')), text(q(w, '.bench-vv')), q(w, '.bench-vw')], ['Head to head', 'not kept', null]);
  none(w, 'compare', ['Compare needs two arms', 'Plan a run with two arms']);
});

// Bug it guards: the few page said "The harness's report is kept for every arm: …" when every result kept its grade, and
// "2 tasks at most each. The ranges show how little so few tasks say." for runs of 2 tasks: the mockup has the one-task
// sentence and the warn callout alone.
test('Scoreboard, 2 runs of 2 tasks, every result kept its grade: no callout and no subtitle of its own', async () => {
  const set = BH.few(), id = BH.ORDER[1], sh = set.shows[BH.FEW1];
  set.hist.runs[0].n = 2;
  sh.tasks.push({ ...sh.tasks[0], id });
  Object.values(set.shows).forEach((x) => x.tasks.forEach((t) => t.cells.forEach((c) => { c.class = 'resolved'; })));
  const w = await opened(set);
  assert.equal(q(w, '.bench-callout'), null, 'no callout when every result kept its grade');
  assert.equal(box(w, 'Leaderboard').querySelector('.bench-hsub'), null, 'the subtitle is the mockup\'s one-task sentence or none');
  none(w, 'scoreboard', ['report is kept for every arm', 'at most each']);
});

// Bug it guards: with no run ended the Scoreboard said "No run has ended yet. Plan a run: its results show here once it
// ends." and Task said "No task has a result yet. Plan a run: each task it runs shows here.", sentences of their own.
test('Scoreboard and Task, no run ended: the mockup\'s verdict says nothing can be told, and Task says not kept', async () => {
  const set = BH.study();
  Object.assign(set.hist, { runs: [], keys: [] });
  set.shows = {};
  const w = await opened(set);
  assert.deepEqual([text(q(w, '.bench-vk')), text(q(w, '.bench-vv')), q(w, '.bench-vw')], ['Verdict on the tasks you have', 'Nothing can be told yet.', null]);
  assert.ok(q(w, 'details.bench-history'), 'the run history stays');
  none(w, 'scoreboard', ['No run has ended yet', 'its results show here']);
  await go(w, 'task');
  assert.deepEqual([text(q(w, '.bench-vk')), text(q(w, '.bench-vv')), q(w, '.bench-vw')], ['Task', 'not kept', null]);
  none(w, 'task', ['No task has a result yet', 'each task it runs shows here']);
});

// Bug it guards: the cost stat said "estimate, from tokens" where the mockup's chip says "list prices, all sessions" (the
// leaderboard's "from tokens" sub carries the estimate); a stopped run's state said "stopped", not the mockup's "stopped
// at 31" with the tasks it reached. A run whose process ended (interrupted) and one the guard stopped keep their words.
test('Scoreboard, 7 arms on 50 tasks, Conveyor priced from tokens, a run stopped at 31: the mockup\'s chip and state', async () => {
  const set = BH.study(), [run, gone, guard] = set.hist.runs;
  set.shows[STUDY].tasks.forEach((t) => t.cells.forEach((c) => { if (/^conveyor/.test(c.arm)) c.cost.state = 'estimate'; }));
  Object.assign(run, { state: 'stopped' });
  run.cols.forEach((c, i) => { c.done = 31 - (i % 2); });
  Object.assign(gone, { state: 'stopped', gone: true });
  Object.assign(guard, { state: 'guard' });
  const w = await opened(set);
  assert.equal(text(stat(w, 'Conveyor: cost per resolved task').children[2]), 'list prices, all sessions');
  const state = (id) => text(q(w, `.bench-history tr[data-run="${id}"] .chip`));
  assert.deepEqual([state(STUDY), state(gone.id), state(guard.id)], ['stopped at 31', 'interrupted', 'stopped at the usage guard']);
  none(w, 'scoreboard', ['estimate, from tokens']);
});

// Bug it guards (#1216, kept by #1224): the owner keeps Archive, Restore, Delete and the "archived" chip, also in the few
// page's history fold: the fold had only Archive tested, so a Restore or Delete lost there would go unseen.
test('Scoreboard, 2 runs of 1 task, one archived: its row has the archived chip, and ticked it offers Restore and Delete in the fold', async () => {
  const set = BH.few(), id = BH.FEW2;
  set.hist.runs[1].archived = iso(T0 - 3600000);
  const w = await opened(set);
  assert.deepEqual(Array.from(q(w, `.bench-history tr[data-run="${id}"]`).querySelectorAll('.chip'), text), ['done', 'archived']);
  tick(w, id, true);
  assert.deepEqual(Array.from(q(w, '.bench-history .bench-selbar').children, text), ['1 run selected', 'Restore', 'Delete', 'Clear']);
  const sent = () => w.posts.splice(0).map((p) => p.body.args).filter((a) => a[0] === 'runs');
  w.reply = BH.reply(`conveyor: restored ${id}.`);
  act(q(w, '.bench-selbar'), 'restore-runs').click();
  assert.deepEqual(sent(), [['runs', 'restore', id]]);
  await settle(); await settle();
  tick(w, id, true);
  const del = act(q(w, '.bench-selbar'), 'delete-runs');
  del.click(); w.reply = BH.reply(`conveyor: deleted ${id}.`); del.click();
  assert.deepEqual(sent(), [['runs', 'delete', id]], 'Delete sends its request after the second click');
});

// ---- Versions and Compare ----
// Bug it guards: with no drift watch read, the verdict's belt line said "The drift watch has not run." where the mockup has
// its belt line: it says not kept, and the card keeps its heading with not kept under it.
test('Versions, 6 versions on 50 tasks, no drift watch read: the belt line and the card say not kept', async () => {
  const set = BH.study();
  set.drift = null;
  const w = await opened(set, 'versions');
  assert.equal(text(q(w, '.bench-vw')), 'not kept');
  assert.equal(text(box(w, 'Drift watch: the belt\'s own cards').querySelector('.bench-hsub')), 'not kept');
  none(w, 'versions', ['The drift watch has not run', 'could be read']);
});

// Bug it guards: two versions that ran no task in common said "Not told yet: v1.7.0 and v1.6.0 ran no task in common." and
// "no task both ran" in the table; the older one's date said "not read" when its run has no start. Each is not kept.
test('Versions, two versions that ran no task in common, one with no start kept: the verdict, the table cell and the date say not kept', async () => {
  const set = BH.few(), l2 = set.hist.runs[1], s2 = set.shows[BH.FEW2], id = 'r20261107T100000-5', six = '6'.repeat(40);
  const line = { ...l2, id, started: 'not a time', ended: iso(T0 - 47 * 3600000), cols: l2.cols.map((c) => ({ ...c, key: `conveyor-${six}`, engine: six, version: 'v1.6.0', resolved: 0 })) };
  set.hist.runs.push(line);
  set.shows[id] = { run: line, tasks: [{ ...s2.tasks[0], id: BH.ORDER[1], cells: s2.tasks[0].cells.map((c) => ({ ...c, result: 'unresolved', resolved: false })) }], tail: [] };
  const w = await opened(set, 'versions');
  assert.equal(text(q(w, '.bench-vk')), 'v1.7.0 against v1.6.0');
  assert.equal(text(q(w, '.bench-vv')), 'not kept');
  assert.deepEqual(rows(q(w, '.bench-versions')).map((r) => [r[0], r[1] === 'not kept', r[4]]), [['v1.6.0', true, 'first'], ['v1.7.0', false, 'not kept']]);
  none(w, 'versions', ['ran no task in common', 'no task both ran', 'Not told yet']);
});

// Bug it guards: with a gap of 0 the verdict said "They resolve the same number of these tasks." where the mockup says how
// many tasks the gap would need. A tie has no such number (a figure of 5000 came from a made-up gap of 1, and a tie on 10
// tasks would have shown 200, under the set), so it says that no number of tasks would show it.
test('Compare, two arms that resolve the same tasks: the mockup\'s sentence for a gap of 0', async () => {
  const set = BH.study();
  set.shows[STUDY].tasks.forEach((t, i) => { const c = t.cells.find((x) => x.arm === 'conveyor-codex-claude'); if (i < 37) Object.assign(c, { resolved: true, result: 'resolved', class: 'resolved' }); });
  const w = await opened(set, 'compare');
  await pickArm(w, 'b', 'arm:conveyor-codex-claude');
  assert.equal(text(q(w, '.bench-vv')), 'Not told apart yet. The difference is 0 tasks, under the noise of 10.');
  assert.equal(text(q(w, '.bench-vw')), 'If the gap held, no number of tasks would show it, so treat the two as equal.');
  none(w, 'compare', ['They resolve the same number']);
});

// Bug it guards: two arms that share no graded task said "<A> and <B> share no task they both graded." in the verdict.
test('Compare, 2 runs of 1 task, the two arms share no graded task: the verdict says not kept', async () => {
  const set = BH.few();
  Object.assign(set.shows[BH.FEW1].tasks[0].cells.find((c) => c.arm === 'solo'), { result: null, state: 'not reached', resolved: undefined });
  const w = await opened(set, 'compare');
  await pickArm(w, 'a', 'arm:conveyor-codex-claude');
  await pickArm(w, 'b', 'arm:solo');
  assert.equal(text(q(w, '.bench-vv')), 'not kept');
  none(w, 'compare', ['share no task']);
});

// ---- Live run and Task ----
// Bug it guards: a run with no estimate said "No estimate to judge it by." and its chips said "no estimate"; a run with no
// task run left out of the count had a "none" chip in place of the mockup's chip. The mockup's places say not kept, and
// the Not run figure has no chip when no task run was left out.
test('Live run, 7 arms on 50 tasks going with no usual figure for any arm: not kept in the mockup\'s places, and no Not run chip', async () => {
  const set = BH.live();
  set.hist.arms.forEach((a) => { a.perTask = null; });
  const w = await opened(set, 'run');
  assert.match(text(q(w, '.bench-vv')), /^Not kept\. 73 of 350 task runs done; about /);
  assert.equal(text(stat(w, 'Spent so far').children[2]), 'not kept');
  assert.equal(text(stat(w, 'Not run').children[2]), '', 'no chip when no task run was left out');
  none(w, 'run', ['No estimate to judge', 'no estimate', 'no task done yet']);
});

// Bug it guards (review E5): the "Left, at this pace" chip said "no task done yet" before the first task run ended, a
// sentence the mockup does not have. The case above starts with 73 task runs done, so it never reached that state.
test('Live run, 7 arms on 50 tasks, no task run done yet: the time left has not kept in the mockup\'s place', async () => {
  const set = BH.live(), live = set.shows[BH.LIVE];
  set.hist.runs.find((r) => r.id === BH.LIVE).cols.forEach((c) => { c.done = 0; c.resolved = 0; });
  Object.assign(set.live, { done: 0, resolved: 0 });
  live.tail = [];
  live.tasks.forEach((t) => t.cells.forEach((c) => { Object.keys(c).forEach((k) => { if (!['arm', 'state'].includes(k)) delete c[k]; }); c.result = null; c.state = 'waiting'; }));
  const w = await opened(set, 'run');
  assert.equal(stat(w, 'Task runs done').children[0].textContent, '0/350');
  assert.equal(text(stat(w, 'Left, at this pace').children[2]), 'not kept');
  assert.equal(text(stat(w, 'Left, at this pace').children[0]), 'not kept');
  none(w, 'run', ['no task done yet', 'no estimate']);
});

// Bug it guards: the Note column was empty for an arm that did not fire, where the mockup says "did not fire"; an arm
// with no result showed "no result" and a card with no step times said "The step times are not kept: each step has the same
// width.", sentences of their own.
test('Task, 7 arms on a task the Caveman arm did not fire on: the Note says did not fire, and not kept stands for what is missing', async () => {
  const set = BH.study(), id = TASKS[28];
  const cells = set.shows[STUDY].tasks.find((t) => t.id === id).cells;
  cells.find((c) => c.arm === 'conveyor').steps.forEach((s) => { s.time = null; });
  Object.assign(cells.find((c) => c.arm === 'superpowers'), { result: null, state: 'waiting', resolved: undefined });
  const w = await opened(set, 'map');
  act(bp(w), `sq-${id}`).click();
  await settle(); await settle();
  const arm = (label) => rows(q(w, '.bench-arms')).find((r) => r[0] === label);
  assert.equal(arm('Claude + Caveman')[4], 'did not fire');
  assert.equal(arm('Claude alone')[4], '', 'an arm that fired and lost has no note');
  assert.equal(arm('Claude + Superpowers')[1], 'not kept');
  assert.ok(Array.from(page(w).querySelectorAll('.bench-hsub'), text).some((t) => /Width is time: not kept\.$/.test(t)));
  none(w, 'task', ['no result', 'step times are not kept']);
});

// ---- Plan a run ----
// Bug it guards: the arm table showed the engine's other state words ("unchecked", "checking") and the arms it does not
// offer, where the mockup has ready, changed and expired: an arm in any other state has no state kept. Start and Check the
// arms first are on where the mockup has them on (ticked arms ready: Check runs again for them), off only with a word of
// why; the Belt row says not kept when the limits are not kept.
test('Plan a run, 2 runs of 1 task: the arm table shows the mockup\'s states, both buttons are on, and no why shows', async () => {
  const set = BH.few();
  set.hist.arms[5].state = 'not offered'; set.hist.arms[6].state = 'checking';
  set.hist.limits = {};
  const w = await opened(set, 'plan');
  const arms = rows(q(w, '.bench-planarms'));
  assert.equal(arms.length, 14, 'the arm not offered has no row');
  assert.deepEqual(Array.from(new Set(arms.map((r) => r[2]))), ['ready', 'expired', 'not kept']);
  assert.equal(kv(q(w, '.bench-before')).find(([k]) => k === 'Belt')[1], 'not kept');
  assert.deepEqual(['start', 'check-arms'].map((a) => act(bp(w), a).disabled), [false, false]);
  assert.equal(q(w, '.bench-why'), null, 'with both on, the page says nothing of why');
  w.reply = BH.reply('conveyor: checking c1');
  act(bp(w), 'check-arms').click();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [['arms', 'check', 'conveyor', 'solo']], 'with the ticked arms ready, the check runs for them again');
  await settle();
  for (const arm of ['conveyor', 'solo']) { const b = act(bp(w), `arm-${arm}`); b.checked = false; b.dispatchEvent(new w.Event('change')); }
  assert.deepEqual(['start', 'check-arms'].map((a) => act(bp(w), a).disabled), [true, true]);
  assert.equal(text(q(w, '.bench-why')), 'Start is off: no arm is ticked. Check the arms first is off: no arm is ticked.');
});

// Bug it guards: with the usage guard reached, Start was off with no word of why.
test('Plan a run, the usage guard reached: Start is off and says why, Check the arms first stays on', async () => {
  const set = BH.study();
  set.hist.guard = { conveyor: true, agent: false };
  const w = await opened(set, 'plan');
  assert.deepEqual(['start', 'check-arms'].map((a) => act(bp(w), a).disabled), [true, false]);
  assert.equal(text(q(w, '.bench-why')), 'Start is off: the usage guard is reached.');
});

// Bug it guards: with a run going, Start was off with no word of why; Check the arms first is on all the same.
test('Plan a run, a run going: Start is off and says a run goes now, Check the arms first stays on', async () => {
  const w = await opened(BH.live(), 'plan');
  assert.deepEqual(['start', 'check-arms'].map((a) => act(bp(w), a).disabled), [true, false]);
  assert.equal(text(q(w, '.bench-why')), 'Start is off: a run goes now.');
});
