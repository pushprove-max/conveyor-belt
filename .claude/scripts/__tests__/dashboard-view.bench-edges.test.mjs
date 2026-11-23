// SPDX-License-Identifier: Apache-2.0
// The Benchmarks tab's edge states against the owner's approved mockup (#1224, slice 2 of #1222): where a page has no data,
// it shows the mockup's section with "not kept" in the mockup's place, never a sentence of its own; the plan's buttons
// are on where the mockup has them on, and say why where one is off; Archive, Restore, Delete and the "archived" chip stay,
// also in the few page's history fold. One case for each fixture (BH.study(), 7 arms on 50 tasks; BH.few(), 2 runs of 1
// task; BH.live(), a run going), changed to reach the state. The tests use jsdom only. Shared setup: dashboard-view.helpers.mjs (BH).
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { boot, settle, act, cases, BH, iso, T0, tick as clockTick } from './dashboard-view.helpers.mjs';

// A page of the repository (a name with no folder is a page of docs/), its bold marks taken out and its lines joined. Defined in
// this file, not in the helpers: the bug check puts only the card's test files on main's code, where a new helper is missing.
const guide = (name) => readFileSync(new URL(`../../../${name.includes('/') ? name : `docs/${name}`}`, import.meta.url), 'utf8').replace(/\*\*/g, '').replace(/\s+/g, ' ');
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
// Bug it guards: with one arm the verdict said "Claude alone resolves 25 of 50." (earlier "One arm has results: there is no other arm to set it against."), the Value
// card said "No arm is priced: the chart needs the cost of each task." and Lines of code said "The size of the reference fix
// is not kept.", sentences of their own where the mockup has its sections: the mockup's place says not kept. Compare with
// one arm said "Compare needs two arms with results." and "Plan a run with two arms or more."
test('Scoreboard and Compare, one arm with results, no price and no reference fix: not kept in the mockup\'s place', async () => {
  const w = await opened(oneArm());
  assert.equal(text(q(w, '.bench-vv')), 'not kept', 'the verdict\'s place');
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
// many tasks the gap would need. A tie has no such number, so the mockup's cap applies: the number is the set's size, and
// the sentence says the set has fewer than it would take (#1231; it said "no number of tasks would show it" before).
test('Compare, two arms that resolve the same tasks: the mockup\'s sentence for a gap of 0', async () => {
  const set = BH.study();
  set.shows[STUDY].tasks.forEach((t, i) => { const c = t.cells.find((x) => x.arm === 'conveyor-codex-claude'); if (i < 37) Object.assign(c, { resolved: true, result: 'resolved', class: 'resolved' }); });
  const w = await opened(set, 'compare');
  await pickArm(w, 'b', 'arm:conveyor-codex-claude');
  assert.equal(text(q(w, '.bench-vv')), 'Not told apart yet. The difference is 0 tasks, under the noise of 10.');
  assert.equal(text(q(w, '.bench-vw')), 'If the gap held, about 500 tasks would show it, more than the set has, so treat the two as equal.');
  none(w, 'compare', ['They resolve the same number', 'no number of tasks would show it']);
});

// Bug it guards (#1231): the number was capped at the set's size even where the gap needs fewer tasks than the set has;
// then the sentence gives the number it needs and has no "more than the set has" (the case above has the cap).
test('Compare, two arms 9 tasks apart: the sentence gives the tasks the gap needs, under the size of the set', async () => {
  const set = BH.study();
  set.shows[STUDY].tasks.forEach((t, i) => { const c = t.cells.find((x) => x.arm === 'conveyor-codex-claude'); Object.assign(c, i < 28 ? { resolved: true, result: 'resolved', class: 'resolved' } : { resolved: false, result: 'unresolved', class: 'unresolved' }); });
  const w = await opened(set, 'compare');
  await pickArm(w, 'b', 'arm:conveyor-codex-claude');
  assert.equal(text(q(w, '.bench-vv')), 'Not told apart yet. The difference is 9 tasks, under the noise of 10.');
  assert.equal(text(q(w, '.bench-vw')), 'If the gap held, about 62 tasks would show it.');
});

// Bug it guards (#1231): the verdict's belt line said "On the belt, every figure stayed in its usual range." (or "N of 6
// figures could be judged, and each stayed…") where the mockup has the line only for a figure that moved: with none moved
// it says not kept.
test('Versions, 6 versions on 50 tasks, no drift figure moved: the belt line says not kept', async () => {
  const still = BH.study();
  still.drift.after = { ...still.drift.before };
  const w = await opened(still, 'versions');
  assert.equal(text(q(w, '.bench-vw')), 'not kept');
  none(w, 'versions', ['every figure stayed', 'could be judged']);
});

// Bug it guards (#1231, review E1): with a figure moved and another one not judged (the review figure is null),
// the line said "The other figures stayed in their usual range.", a range the Board never judged the review figure by.
test('Versions, 6 versions on 50 tasks, one drift figure moved and one not judged: the belt line does not say the others stayed in range', async () => {
  const some = BH.study();
  some.drift.after = { ...some.drift.after, reviews: null };
  const w = await opened(some, 'versions');
  assert.equal(text(q(w, '.bench-vw')), 'On the belt, cards on v1.9.0 waited less (4 min against 12 min a card): that moved past its usual range.');
});

// The 12 tasks of the Conveyor arm's resolved ones that the newest version, v1.9.0, resolves no more, or the unresolved ones it resolves.
const turn = (set, n, to) => set.shows[STUDY].tasks.filter((t) => t.cells.some((c) => c.arm === 'conveyor' && c.resolved === !to)).slice(0, n)
  .forEach((t) => Object.assign(t.cells.find((c) => c.arm === 'conveyor'), { resolved: to, result: to ? 'resolved' : 'unresolved', class: to ? 'resolved' : 'unresolved' }));

// Bug it guards (#1231): the verdict's first word was "A regression." for a drop past the noise and "No regression shown."
// for a small drop, where the mockup's one word is "No regression.". A drop past the noise has no such word (it is a
// regression), and the sentence and the red tone say it.
test('Versions, 6 versions on 50 tasks, v1.9.0 drops past the noise: the verdict has no "No regression." and is red', async () => {
  const drop = BH.study();
  turn(drop, 12, false);
  const w = await opened(drop, 'versions');
  assert.equal(text(q(w, '.bench-vv')), 'v1.9.0 resolves 25 of 50, 10 fewer than v1.8.0: past the noise of 10 tasks.');
  assert.ok(q(w, '.bench-verdict').className.includes('bad'), 'the red tone');
  none(w, 'versions', ['A regression.', 'Better.', 'No regression shown.', 'No regression.']);
});

// Bug it guards (#1231): a drop inside the noise said "No regression shown." in place of the mockup's "No regression.".
test('Versions, 6 versions on 50 tasks, v1.9.0 drops inside the noise: the verdict says No regression.', async () => {
  const drop = BH.study();
  turn(drop, 3, false);
  const w = await opened(drop, 'versions');
  assert.equal(text(q(w, '.bench-vv')), 'No regression. v1.9.0 resolves 34 of 50, 1 fewer than v1.8.0: inside the noise of 10 tasks.');
  assert.ok(!q(w, '.bench-verdict').className.includes('bad'), 'not the red tone');
  none(w, 'versions', ['No regression shown.']);
});

// Bug it guards (#1231): a gain past the noise said "Better." where the mockup's one word is "No regression.".
test('Versions, 6 versions on 50 tasks, v1.9.0 gains past the noise: the verdict says No regression., not Better.', async () => {
  const gain = BH.study();
  turn(gain, 12, true);
  const w = await opened(gain, 'versions');
  assert.equal(text(q(w, '.bench-vv')), 'No regression. v1.9.0 resolves 49 of 50, 14 more than v1.8.0: past the noise of 10 tasks.');
  none(w, 'versions', ['Better.']);
});

// Bug it guards (#1231): a flipped task with no commits that changed its step said "none" in the table, and a version
// list with no version said "No version has a result yet.": each is a sentence the mockup does not have; its place says not kept.
test('Versions, no version with a result: the verdict says not kept', async () => {
  const set = BH.study();
  set.hist.runs = [];
  const w = await opened(set, 'versions');
  assert.ok(!text(page(w)).includes('No version has a result yet'), text(page(w)));
  assert.equal(text(q(w, '.bench-vv')), 'not kept');
});

// Bug it guards: two arms that share no graded task said "<A> and <B> share no task they both graded." in the verdict.
// Also (issue 1430): its line said "The only difference is cost and time: … took 0 sessions", which nothing supports.
test('Compare, 2 runs of 1 task, the two arms share no graded task: the verdict and its line say not kept', async () => {
  const set = BH.few();
  Object.assign(set.shows[BH.FEW1].tasks[0].cells.find((c) => c.arm === 'solo'), { result: null, state: 'not reached', resolved: undefined });
  const w = await opened(set, 'compare');
  await pickArm(w, 'a', 'arm:conveyor-codex-claude');
  await pickArm(w, 'b', 'arm:solo');
  assert.equal(text(q(w, '.bench-vv')), 'not kept');
  assert.equal(text(q(w, '.bench-vw')), 'not kept');
  none(w, 'compare', ['share no task', 'The only difference is cost and time']);
});

// Bug it guards (#1231): while the page has not read the run of an older version picked as a side, Compare said its own
// sentence or drew a verdict from nothing; the mockup's place says not kept.
test('Compare, 6 versions on 50 tasks, the run of v1.8.0 is not read: the verdict says not kept', async () => {
  const set = BH.study();
  delete set.shows[BH.OLDS[0][1]];
  const w = await opened(set, 'compare');
  await pickArm(w, 'a', 'ver:v1.8.0');
  assert.deepEqual([text(q(w, '.bench-vk')), text(q(w, '.bench-vv'))], ['Head to head', 'not kept']);
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
// Bug it guards: the arm table showed the engine's other state words ("unchecked"), where the mockup has ready, changed
// and expired: an arm in any other state has no state kept, but for one being checked, a state known (issue 1430: it
// read "not kept", the page's word for a figure a result did not keep). Start and Check the
// arms first are on where the mockup has them on (ticked arms ready: Check runs again for them), off only with a word of
// why; the Belt row says not kept when the limits are not kept.
test('Plan a run, 2 runs of 1 task: the arm table shows the mockup\'s states, both buttons are on, and no why shows', async () => {
  const set = BH.few();
  set.hist.arms[5].state = 'not offered'; set.hist.arms[6].state = 'checking';
  set.hist.limits = {};
  const w = await opened(set, 'plan');
  const arms = rows(q(w, '.bench-planarms'));
  // Bug it guards (#1233): the arm not offered had no row; the mockup lists every arm. Its row shows "not kept" for the
  // state, and its box is off, so no run or check is sent for an arm the project does not offer.
  assert.equal(arms.length, 15, 'every arm has a row, the arm not offered too');
  assert.deepEqual(Array.from(new Set(arms.map((r) => r[2]))), ['ready', 'expired', 'not kept', 'checking']);
  assert.equal(q(w, `.bench-planarms tr[data-arm="${set.hist.arms[6].name}"]`).children[2].textContent, 'checking', 'the arm being checked says so');
  const row = q(w, `.bench-planarms tr[data-arm="${set.hist.arms[5].name}"]`);
  assert.ok(row, 'the row of the arm not offered');
  assert.equal(row.querySelector('input[type="checkbox"]').disabled, true, 'the arm not offered cannot be ticked');
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
  // Bug (#1436): the guide lists each reason a Plan a run button is off; a reason the page shows and the guide leaves out is the gap.
  assert.ok(guide('board.md').includes('with no arm picked, while an arm that you picked is not ready, while the usage guard holds an arm that you picked, and while an action'), 'docs/board.md lists the reasons Start the run is off');
  assert.ok(guide('board.md').includes('It stays off with no arm picked, while the arms that you picked are being checked, and while an action'), 'docs/board.md lists the reasons Check the arms first is off');
});

// Bug it guards: with the usage guard reached, Start was off with no word of why.
test('Plan a run, the usage guard reached: Start is off and says why, Check the arms first stays on', async () => {
  const set = BH.study();
  set.hist.guard = { conveyor: true, agent: false };
  const w = await opened(set, 'plan');
  assert.deepEqual(['start', 'check-arms'].map((a) => act(bp(w), a).disabled), [true, false]);
  assert.equal(text(q(w, '.bench-why')), 'Start is off: the usage guard is reached.');
  assert.ok(guide('board.md').includes('while the usage guard holds an arm that you picked'), 'docs/board.md lists the usage guard as a reason Start the run is off');
});

// Bug it guards: with a run going, Start was off with no word of why; Check the arms first is on all the same.
test('Plan a run, a run going: Start is off and says a run goes now, Check the arms first stays on', async () => {
  const w = await opened(BH.live(), 'plan');
  assert.deepEqual(['start', 'check-arms'].map((a) => act(bp(w), a).disabled), [true, false]);
  assert.equal(text(q(w, '.bench-why')), 'Start is off: a run goes now.');
  assert.ok(guide('board.md').includes('It stays off while a run goes, with no arm picked'), 'docs/board.md lists a run going as a reason Start the run is off');
});

// Bug it guards: the Check button's read of the arms was lost (the page server did not answer). The arms read stayed as it
// was, with no arm checking, so the page never asked again and showed the old states for good, though the checks ran.
test('Plan a run, Check the arms first, the first read of the arms lost: the page asks again after CHECK_MS and shows the arms being checked', async () => {
  const set = BH.few();
  const w = await opened(set, 'plan');
  const answer = w.benchBody;
  w.benchBody = () => null;
  w.reply = BH.reply('conveyor: checking c1');
  act(bp(w), 'check-arms').click();
  await settle(); await settle();
  const asked = w.benchAsks.length;
  w.benchBody = (url) => { const b = answer(url); if (b && b.arms) b.arms.forEach((a) => { if (a.name === 'conveyor' || a.name === 'solo') a.state = 'checking'; }); return b; };
  clockTick(w, 4000);
  assert.equal(w.benchAsks.length, asked, 'no ask before CHECK_MS has passed');
  clockTick(w, 1000);
  await settle(); await settle();
  assert.equal(w.benchAsks.length, asked + 1, 'the page asked for the arms again');
  assert.match(text(q(w, '.bench-why')), /Check the arms first is off: the ticked arms are being checked\.$/);
  assert.equal(act(bp(w), 'check-arms').disabled, true, 'the arms read shows the ticked arms being checked');
  // Bug (#1436): the guide said the Board reads the arms again "until a read answers"; it reads on while an arm is being checked, and stops when none is.
  clockTick(w, 5000);
  await settle(); await settle();
  assert.equal(w.benchAsks.length, asked + 2, 'a read that answers with an arm still being checked is followed by another');
  // The read above changed the arms' objects in place, so the arms are set back to ready here, as a finished check leaves them.
  w.benchBody = (url) => { const b = answer(url); if (b && b.arms) b.arms.forEach((a) => { if (a.state === 'checking') a.state = 'ready'; }); return b; };
  clockTick(w, 5000);
  await settle(); await settle();
  assert.equal(w.benchAsks.length, asked + 3, 'a read that shows no arm being checked is the last');
  clockTick(w, 5000);
  await settle(); await settle();
  assert.equal(w.benchAsks.length, asked + 3, 'no read follows it');
  const page = guide('board.md');
  assert.ok(page.includes('After a check, the Board reads the arms again, so the arms show their new state, until a read answers and no arm is being checked'), 'docs/board.md says when the re-read after a check ends');
  assert.ok(page.includes('while the arms that you picked are being checked'), 'docs/board.md lists the checking arms as a reason Check the arms first is off');
});

// Bug it guards: while the answer to Check the arms first was out, both buttons were off with no word of why.
test('Plan a run, Check the arms first sent and not answered: both buttons are off and the page says why', async () => {
  const w = await opened(BH.few(), 'plan');
  w.reply = { ok: true, status: 200, text: () => new Promise(() => {}) };
  act(bp(w), 'check-arms').click();
  await settle(); await settle();
  assert.deepEqual(['start', 'check-arms'].map((a) => act(bp(w), a).disabled), [true, true]);
  assert.equal(text(q(w, '.bench-why')), 'Both buttons are off: the last action has no answer yet.');
  // Bug (#1436): the guide gave the off reasons of Start the run and Check the arms first without the wait for an answer.
  assert.equal(guide('board.md').split('while an action that you sent has no answer yet').length - 1, 2, 'docs/board.md gives the wait as a reason for both buttons');
});
