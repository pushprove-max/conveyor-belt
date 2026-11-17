// SPDX-License-Identifier: Apache-2.0
// The Tests page's Benchmarks part (#236): Run SWE-bench with the presets 1, 5, 20, 50 and a number box, a released
// version or Claude alone, the sessions and minutes expected before Start, a bar of the tasks done with Stop while a
// run goes, the results of every version side by side, and Compare. Shared setup: dashboard-view.helpers.mjs (TA.snap()).
import assert from 'node:assert/strict';
import { boot, deliver, next, settle, act, cases, TA } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const { snap, tp, reply } = TA;
const EA = 'a'.repeat(40), EB = 'b'.repeat(40);
// A snapshot whose Benchmarks part is <b>.
const withBench = (b) => { const d = snap(); d.panels.tests.data.bench = b; return d; };
const part = (w) => tp(w).querySelector('.tests-bench');
const plan = (w) => part(w).querySelector('.tests-bench-plan').textContent;
const BASE = { live: null, runs: [], presets: [1, 5, 20, 50], max: 500, keys: [],
  versions: [{ name: 'main', commit: EB }, { name: 'v1.2.0', commit: EA }],
  perTask: { conveyor: { usual: 2.5, worst: 6, minutes: 20 }, solo: { usual: 1, worst: 1, minutes: 8 } } };

// Bug it guards: the owner could not start a run of any n from the Board, nor see what it would cost before Start.
// A preset or the number box sets n; the expected sessions (usual and worst case) and minutes follow it; Start sends
// bench run with the version picked, or --solo for Claude alone.
test('Benchmarks: a preset or the number box sets n, the cost shows before Start, and Start sends the version picked', async () => {
  const w = boot({ tab: 'tests' });
  deliver(w, withBench(BASE));
  assert.match(plan(w), /^Expected for 5 tasks: about 13 sessions \(worst case 30\) and 100 minutes\./);
  act(part(w), 'bench-preset-1').click();
  assert.match(plan(w), /^Expected for 1 task: about 3 sessions \(worst case 6\) and 20 minutes\./);
  const box = act(part(w), 'bench-n');
  box.value = '12'; box.dispatchEvent(new w.Event('change'));
  assert.match(plan(w), /^Expected for 12 tasks: about 30 sessions \(worst case 72\) and 240 minutes\./);
  const pick = act(part(w), 'bench-engine');
  assert.deepEqual(Array.from(pick.options, (o) => o.value), ['main', 'v1.2.0', '--solo']);
  pick.value = 'v1.2.0'; pick.dispatchEvent(new w.Event('change'));
  w.reply = reply('conveyor: the SWE-bench run started');
  act(part(w), 'bench-start').click();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body), [{ action: 'bench', args: ['run', '12', '--engine', 'v1.2.0'], repo: 'sample' }]);
  await settle();
  const solo = act(part(w), 'bench-engine');
  solo.value = '--solo'; solo.dispatchEvent(new w.Event('change'));
  assert.match(plan(w), /^Expected for 12 tasks: about 12 sessions \(worst case 12\) and 96 minutes\./);
  act(part(w), 'bench-start').click();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [['run', '12', '--solo']]);
  await settle();
});

// Bug it guards: the cost before Start counted the tasks the version picked already ran, which the run reuses at no
// cost, so with all of the first 5 run it still showed 5 tasks' sessions where the engine expects none.
test('Benchmarks: the cost before Start leaves out the tasks of the first n that the version picked already ran', async () => {
  const w = boot({ tab: 'tests' });
  const r = { resolved: true, sessions: 2, tokens: 100, minutes: 3 };
  const five = Object.fromEntries(['a', 'b', 'c', 'd', 'e'].map((x) => [`p__${x}`, r]));
  deliver(w, withBench({ ...BASE, soloKey: 'solo-m', keys: [
    { key: EB, arm: 'conveyor', engine: EB, version: 'main', tasks: five, at: [0, 1, 2, 3, 4] },
    { key: 'solo-m', arm: 'solo', engine: null, model: 'm', tasks: { p__a: r }, at: [0] }] }));
  assert.match(plan(w), /^Expected for 5 tasks: about 0 sessions \(worst case 0\) and 0 minutes\. 5 of them already ran on this version and are reused at no cost\./);
  act(part(w), 'bench-preset-20').click();
  assert.match(plan(w), /^Expected for 20 tasks: about 38 sessions \(worst case 90\) and 300 minutes\. 5 of them already ran/);
  const pick = act(part(w), 'bench-engine');
  pick.value = 'v1.2.0'; pick.dispatchEvent(new w.Event('change'));
  assert.match(plan(w), /^Expected for 20 tasks: about 50 sessions \(worst case 120\) and 400 minutes\. Tasks already run/, 'another version reuses none of main\'s');
  const solo = act(part(w), 'bench-engine');
  solo.value = '--solo'; solo.dispatchEvent(new w.Event('change'));
  assert.match(plan(w), /^Expected for 20 tasks: about 19 sessions \(worst case 19\) and 152 minutes\. 1 of them already ran/);
});

// Bug it guards: a run going could not be seen or ended from the Board. It shows a bar of its tasks done with Stop
// (bench stop), and no Start meanwhile.
test('Benchmarks: a run going shows a bar of its tasks done, and Stop sends bench stop', async () => {
  const w = boot({ tab: 'tests' });
  deliver(w, withBench({ ...BASE, live: { state: 'running', pid: 7, arm: 'conveyor', engine: EB, version: 'main', n: 5, done: 2, resolved: 1, current: 'proj__x-3', tasks: [] } }));
  const bar = part(w).querySelector('progress');
  assert.deepEqual([bar.value, bar.max, bar.getAttribute('aria-label')], [2, 5, 'SWE-bench: 2 of 5 tasks']);
  assert.match(part(w).textContent, /Running: 2 of 5 tasks done, 1 resolved, now proj__x-3 · engine main\./);
  assert.equal(act(part(w), 'bench-start'), null, 'no Start while a run goes');
  w.reply = reply('conveyor: the SWE-bench run is stopped');
  act(part(w), 'bench-stop').click();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [['stop']]);
  await settle();
  next(w, withBench({ ...BASE, live: { state: 'stopped', arm: 'conveyor', engine: EB, version: 'main', n: 5, done: 2, resolved: 1, tasks: [{ id: 'a', result: 'resolved' }, { id: 'b', result: 'not run: its Docker image could not be fetched or built' }] } }));
  assert.match(part(w).querySelector('.tests-bench-last').textContent, /^Last run: stopped · 1 of 5 resolved, 1 not run · engine main b{12}\.$/);
  assert.ok(act(part(w), 'bench-start'), 'Start is offered again');
});

// Bug it guards: the results of two versions could not be read side by side, nor told from noise, nor compared. The
// table has a column a version, a resolved count each, the noise line, and Compare sends bench diff of the two picked
// and shows its answer.
test('Benchmarks: results show side by side with the noise line, and Compare shows the diff of two versions', async () => {
  const w = boot({ tab: 'tests' });
  const r = (resolved) => ({ resolved, sessions: 2, tokens: 100, minutes: 3 });
  deliver(w, withBench({ ...BASE, keys: [
    { key: EA, arm: 'conveyor', engine: EA, version: 'v1.2.0', tasks: { 'p__a-1': r(true), 'p__b-2': r(true) } },
    { key: EB, arm: 'conveyor', engine: EB, version: 'main', tasks: { 'p__a-1': r(false), 'p__b-2': r(true) } }] }));
  const rows = Array.from(part(w).querySelectorAll('.tests-bench-table tr'), (x) => Array.from(x.children, (c) => c.textContent));
  assert.deepEqual(rows[0], ['Task', `v1.2.0 ${'a'.repeat(12)}`, `main ${'b'.repeat(12)}`]);
  assert.deepEqual(rows[1], ['p__a-1', 'Resolved · 2 sessions · 100 tokens · 3 min', 'Not resolved · 2 sessions · 100 tokens · 3 min']);
  assert.deepEqual(rows[3], ['Resolved', '2 of 2', '1 of 2']);
  assert.match(part(w).textContent, /On the 2 tasks every column ran: With 2 tasks only a total break shows: a difference under 2 is within the noise\./);
  w.reply = reply('v1.2.0 against main on the 2 tasks both ran:\np__a-1: resolved by v1.2.0 only; the runs went apart at: review');
  act(part(w), 'bench-compare').click();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [['diff', EA, EB]]);
  await settle();
  assert.match(part(w).querySelector('.tests-bench-diff').textContent, /p__a-1: resolved by v1\.2\.0 only; the runs went apart at: review/);
});
