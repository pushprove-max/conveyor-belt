// SPDX-License-Identifier: Apache-2.0
// The Benchmarks tab's other pages (#326, the owner's approved mockup: run.html, compare.html, start.html,
// infographic.html): a run's tasks by arm with one task opened and Export figures; Compare of two arms with the flipped
// tasks; Start a run with the cost before Start and only the arms whose preflight passed; the infographic of the runs
// selected, whose notes a title cannot remove. Shared setup: dashboard-view.helpers.mjs (BH).
import assert from 'node:assert/strict';
import { boot, settle, act, cases, BH } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const { bp, heads, NEW, OLD, EA, EB } = BH;
const text = (el) => el.textContent.replace(/\s+/g, ' ').trim();
const cells = (r) => Array.from(r.children, text);
const pick = (w, a) => { const b = act(bp(w), a); b.checked = !b.checked; b.dispatchEvent(new w.Event('change')); };
const choose = (w, a, v) => { const s = act(bp(w), a); s.value = v; s.dispatchEvent(new w.Event('change')); };
const body = (href) => decodeURIComponent(href.slice(href.indexOf(',') + 1));
async function opened() {
  const w = boot({ tab: 'bench' });
  BH.open(w);
  await settle();
  return w;
}

// Bug it guards: a run could not be opened: there was no page of its tasks by arm, no task's work to read, and no way
// to take the figures out. The run page reads the run from GET bench when opened, shows each arm a column and each
// task a row with the totals, opens a task to each arm's patch, steps and grade, and exports the figures as JSON with
// no code and no names.
test('A run: tasks by arm with the totals, one task opened with each arm\'s patch, steps and grade, and Export with no code or names', async () => {
  const w = await opened();
  act(bp(w), 'open-newest').click();
  await settle();
  assert.deepEqual(w.benchAsks, ['bench?repo=sample', `bench?repo=sample&run=${NEW}`], 'the run is read when it is opened');
  assert.deepEqual(heads(w), [`Run ${NEW}`, 'Tasks by arm']);
  const mat = bp(w).querySelector('.bench-mat');
  assert.deepEqual(Array.from(mat.querySelectorAll('tr')[0].children, (th) => th.firstChild.textContent), ['Task', 'Conveyor 1.5.0', 'Claude alone (claude-opus-5-5)', 'Codex alone (gpt-6.2-sol)']);
  assert.deepEqual(Array.from(mat.querySelectorAll('tr[data-task]'), (r) => [r.dataset.task, ...Array.from(r.querySelectorAll('.bench-cell'), (c) => c.firstChild.textContent)]), [
    ['astropy__astropy-12907', '✓', '✓', '✓'], ['django__django-15347', '✓', '✗', '✓'], ['pydata__xarray-4094', '✓', '✓', '✗'],
    ['sympy__sympy-21614', '✓', '✗', '✗'], ['sphinx-doc__sphinx-8595', '✗', '✗', 'not run']]);
  assert.equal(text(mat.querySelector('tr[data-task] .bench-cell .bench-sub')), '3 sessions · 20 min · –');
  assert.deepEqual(Array.from(mat.querySelectorAll('tfoot tr'), cells), [['Resolved', '4 of 5', '2 of 5', '2 of 5'], ['Sessions · tokens', '13 · 15.3M', '5 · 5.5M', '4 · 3.6M'],
    ['Minutes · cost', '102 · –', '40 · –', '28 · –']]);
  act(bp(w), 'task-django__django-15347').click();
  assert.deepEqual(heads(w), [`Run ${NEW}`, 'Tasks by arm', 'django__django-15347, opened']);
  const task = bp(w).querySelector('.bench-task');
  assert.equal(text(task.querySelector('.bench-head .board-from')), 'Q objects lose their negation when combined with an empty Q · 2 arms resolved, 1 did not');
  const [conv, solo] = task.querySelectorAll('.bench-card');
  assert.equal(text(conv.querySelector('h3')), '✓ Conveyor 1.5.0 resolved');
  assert.deepEqual(Array.from(conv.querySelectorAll('p'), text), ['Patch: 2 files, +38 −6 · django/db/models/sql/query.py, tests/queries/test_q.py',
    'Harness: resolved. FAIL_TO_PASS and PASS_TO_PASS counts are not kept yet.']);
  assert.deepEqual(Array.from(conv.querySelectorAll('.bench-steps li'), text), ['Build 3.1M tokens', 'Review 1 NO-GO · [P1] query.py:9 combine() drops the negation when the right side is empty',
    'Fix 1 900k tokens', 'Review 2 GO', 'Test step fail', 'Fix 2 400k tokens', 'Landed']);
  // Bug it guards: the test step's color must follow its result; a failed test step shows in the failure color.
  assert.equal(Array.from(conv.querySelectorAll('.bench-steps li')).find((li) => text(li).startsWith('Test step')).querySelector('.chip').className, 'chip chip-bad');
  assert.deepEqual(Array.from(solo.querySelectorAll('p'), text), ['Patch: 1 file, +3 −1 · a.py · one session, 8 min, 1.0M tokens',
    'Harness: not resolved. FAIL_TO_PASS and PASS_TO_PASS counts are not kept yet.']);
  act(bp(w), 'export').click();
  assert.equal(w.downloads[0].name, `bench-${NEW}.json`);
  const raw = body(w.downloads[0].href), figs = JSON.parse(raw);
  assert.deepEqual(figs.arms.map((a) => [a.label, a.resolved, a.sessions]), [['Conveyor 1.5.0', 4, 13], ['Claude alone (claude-opus-5-5)', 2, 5], ['Codex alone (gpt-6.2-sol)', 2, 4]]);
  assert.deepEqual(figs.tasks[1], { task: 'django__django-15347', arms: [{ arm: 'conveyor', result: 'resolved', sessions: 3, tokens: 4000000, minutes: 20 },
    { arm: 'solo', result: 'not resolved', sessions: 1, tokens: 1000000, minutes: 8 }, { arm: 'codex-sol', result: 'resolved', sessions: 1, tokens: 1000000, minutes: 8 }] });
  for (const s of ['query.py', 'negation', 'combine()', 'patch', 'steps']) assert.ok(!raw.includes(s), `the export holds no code, finding or title: ${s}`);
});

// Bugs it guards: a task of a run stopped between two arms showed the arm it never reached as a harness failure
// (`bench swe show` gives that arm a null result), and an agent arm's detail said one session whatever it took.
test('A run: an opened task says an arm was not reached, not that it failed, and an agent arm\'s own sessions', async () => {
  const w = boot({ tab: 'bench' });
  BH.open(w, { body: (url) => {
    if (!/&run=/.test(url)) return BH.hist();
    const r = BH.run();
    r.tasks[1].cells[1].sessions = 4;
    r.tasks[1].cells[2] = { arm: 'codex-sol', result: null, reused: false };
    return r;
  } });
  await settle();
  act(bp(w), 'open-newest').click();
  await settle();
  act(bp(w), 'task-django__django-15347').click();
  const [, solo, codex] = bp(w).querySelectorAll('.bench-task .bench-card');
  assert.equal(text(solo.querySelector('p')), 'Patch: 1 file, +3 −1 · a.py · 4 sessions, 8 min, 1.0M tokens');
  assert.equal(text(codex.querySelector('h3')), '– Codex alone (gpt-6.2-sol) not reached');
  assert.deepEqual(Array.from(codex.querySelectorAll('p'), text), ['The run stopped before this arm reached the task.']);
});

// Bug it guards: Compare showed `bench swe diff` as one block of text, with no way to see which tasks flipped and
// where the two went apart. It sends two arms' results keys for JSON and shows the flipped tasks, each with the facts
// read by code beside the model's reading.
test('Compare: two arms of the runs selected, the flipped tasks with where they went apart, the facts and the model\'s reading', async () => {
  const w = await opened();
  pick(w, `pick-${NEW}`);
  act(bp(w), 'sel-compare').click();
  assert.deepEqual(heads(w), ['Compare']);
  assert.deepEqual(Array.from(act(bp(w), 'cmp-a').options, (o) => [o.value, o.textContent]),
    [[EB, 'Conveyor 1.5.0'], ['solo-claude-opus-5-5', 'Claude alone (claude-opus-5-5)'], ['codex-sol', 'Codex alone (gpt-6.2-sol)']]);
  const A = `v1.5.0 ${EB.slice(0, 12)}`, B2 = 'Claude alone (claude-opus-5-5)';
  const fact = (resolved, sessions, fixRounds, test, findings) => ({ resolved, sessions, tokens: 1, minutes: 1, fixRounds, test, blocked: null, findings });
  w.reply = BH.reply(JSON.stringify({ a: { version: A, commit: EB, totals: { resolved: 4, sessions: 13, tokens: 15300000, minutes: 102 } },
    b: { version: B2, commit: null, totals: { resolved: 2, sessions: 5, tokens: 5500000, minutes: 40 } }, tasks: 5, same: ['astropy__astropy-12907', 'pydata__xarray-4094', 'sphinx-doc__sphinx-8595'],
    flipped: [{ task: 'django__django-15347', apart: 'review', a: fact(true, 3, 1, 'ok', ['[P1] query.py:9 the negation is dropped']), b: fact(false, 1, 0, null, []), changes: null, versions: [A, B2],
      reading: 'The review round caught the edge case the single session missed.' },
    { task: 'sympy__sympy-21614', apart: 'build', a: fact(true, 2, 0, 'ok', []), b: fact(false, 1, 0, null, []), changes: null, versions: [A, B2], reading: null }],
    noise: 'with 5 tasks a difference under 4 tasks is within the noise', withinNoise: true }));
  act(bp(w), 'compare').click();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body), [{ action: 'bench', args: ['diff', EB, 'solo-claude-opus-5-5', '--json'], repo: 'sample' }]);
  await settle();
  assert.equal(text(bp(w).querySelector('.bench-compare .bench-headline')),
    `On the 5 tasks both ran: ${A} resolved 4, ${B2} 2. 2 tasks flipped to ${A}, 0 the other way, 2 resolved by both, 1 by neither.`);
  assert.equal(text(bp(w).querySelector('.bench-compare > .board-from')),
    'With 5 tasks a difference under 4 tasks is within the noise. This difference is 2: within the noise. Run about 15 tasks to tell a difference of this size.');
  assert.equal(text(bp(w).querySelector('.bench-flipped summary')), 'The 2 flipped tasks');
  assert.deepEqual(heads(w), ['Compare', 'django__django-15347', 'sympy__sympy-21614']);
  const flip = bp(w).querySelector('.bench-flip');
  assert.equal(text(flip.querySelector('.chip')), `${A} ✓ · ${B2} ✗`);
  assert.equal(text(flip.querySelector('.bench-head > .board-from')), 'Went apart at: Review');
  const [facts, reading] = flip.querySelectorAll('.bench-card');
  assert.deepEqual(Array.from(facts.children, text), ['Facts, read from the records by code',
    `${A}: 3 sessions, 1 fix round, test ok, findings: [P1] query.py:9 the negation is dropped. ${B2}: 1 session, 0 fix rounds, test none.`,
    'Engine changes that touch that step: none to show (they are not two versions of the engine)']);
  assert.deepEqual(Array.from(reading.children, text), ['The model\'s reading written by one model call from the facts only', 'The review round caught the edge case the single session missed.']);
  assert.equal(text(bp(w).querySelectorAll('.bench-flip')[1].querySelector('.bench-reading p')), 'None: the model call failed.');
  // Bug it guards (#541): the count to run was 2 / rate², capped at 500, so a difference of 1 in 20 asked for 500 tasks,
  // where the same rate gives 25 and the noise is 32. Above, 2 of 5 asked for 13 (5.2 against a noise of 6): it is 15.
  // A count that cannot tell is never named; the reading says even the whole set cannot.
  w.reply = BH.reply(JSON.stringify({ a: { version: A, commit: EB, totals: { resolved: 11 } }, b: { version: B2, commit: null, totals: { resolved: 10 } }, tasks: 20, same: [],
    flipped: [{ task: 'django__django-15347', apart: 'review', a: fact(true, 3, 1, 'ok', []), b: fact(false, 1, 0, null, []), changes: null, versions: [A, B2], reading: null }], withinNoise: true }));
  act(bp(w), 'compare').click();
  w.posts.splice(0);
  await settle();
  assert.equal(text(bp(w).querySelector('.bench-compare > .board-from')),
    'With 20 tasks a difference under 7 tasks is within the noise. This difference is 1: within the noise. Even all 500 tasks cannot tell a difference of this size.');
});

// Bug it guards: Start offered Conveyor or Claude alone only, with no arm's preflight state, so an arm that cannot run
// could be started, and the cost before Start was one arm's. It offers only the arms whose preflight passed (one not
// checked can be checked), shows each arm's usual and worst-case sessions and minutes for the tasks it has not run on
// the version picked, sends the arms picked, and is off while the usage guard holds an arm picked back.
test('Start: only the arms whose preflight passed can be picked; the cost before Start follows n, the arms and the version; the usage guard holds it', async () => {
  const w = await opened();
  act(bp(w), 'to-start').click();
  assert.deepEqual(heads(w), ['Start a run', 'Arms', 'Before you start']);
  assert.deepEqual(Array.from(bp(w).querySelectorAll('.bench-seg button'), (b) => [b.textContent, b.getAttribute('aria-pressed')]), [['1', 'false'], ['5', 'false'], ['20', 'true'], ['50', 'false']]);
  assert.deepEqual(Array.from(bp(w).querySelectorAll('.bench-arm-pick > .board-label'), text), ['Conveyor', 'Claude, plain', 'Claude + a plugin or method', 'Codex', 'Other agents']);
  assert.deepEqual(Array.from(bp(w).querySelectorAll('.bench-arm'), (l) => [l.dataset.arm, l.querySelector('input').disabled, l.querySelector('.chip').textContent]), [
    ['conveyor', false, 'Ready'], ['solo', false, 'Ready'], ['superpowers', true, 'Preflight failed'], ['chisle', true, 'Not checked'], ['codex-sol', false, 'Ready'], ['openhands', true, 'Not offered']]);
  // Bug it guards: every agent arm was said to take one session a task; a method arm's spec can set more (chisle: 4).
  assert.deepEqual(['solo', 'chisle'].map((a) => text(bp(w).querySelector(`.bench-arm[data-arm="${a}"] .bench-sub`))), ['one session a task, headless', '4 sessions a task, headless']);
  assert.deepEqual(['check-superpowers', 'check-chisle', 'check-openhands'].map((a) => (act(bp(w), a) || {}).textContent || null), ['Check again', 'Check', null]);
  const plan = () => Array.from(bp(w).querySelectorAll('.bench-plan tr[data-arm]'), cells);
  // Bug it guards (#326): the cost was a dash everywhere. Each session is priced at the arm's mean session dollars
  // (Conveyor's $1.25: 50 usual sessions $62.50, 160 worst $200.00).
  assert.deepEqual(plan(), [['Conveyor', '50', '160', '400', '$62.50 · worst $200.00']], '20 tasks of Conveyor on main: none reused');
  assert.equal(text(bp(w).querySelector('.bench-arm[data-arm="conveyor"] .bench-cost')), '50 sessions (worst 160) · 400 min · $62.50');
  act(bp(w), 'preset-5').click();
  pick(w, 'arm-solo');
  choose(w, 'start-engine', 'v1.2.0');
  assert.deepEqual(plan(), [['Conveyor', '5', '16', '40', '$6.25 · worst $20.00'], ['Claude alone', '0', '0', '0', '$0.00 · worst $0.00']], 'the tasks each arm ran on v1.2.0 are reused at no cost');
  const total = () => Array.from(bp(w).querySelectorAll('.bench-before .figure')[2].children, text);
  assert.deepEqual(Array.from(bp(w).querySelectorAll('.bench-before .figure .num'), (n) => n.textContent), ['5', '0.7 h', '$6.25']);
  assert.deepEqual(total(), ['$6.25', 'at list prices', 'worst case $20.00']);
  assert.equal(text(act(bp(w), 'start')), 'Start · 2 arms on 5 tasks');
  w.reply = BH.reply('conveyor: the SWE-bench run started');
  act(bp(w), 'start').click();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [['run', '5', '--arm', 'conveyor', '--arm', 'solo', '--engine', 'v1.2.0']]);
  await settle();
  w.reply = BH.reply('conveyor: the arms\' preflights started');
  act(bp(w), 'check-chisle').click();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [['arms', 'check', 'chisle']]);
  await settle();
  // The Claude login at its usage guard: a run with Claude alone does not start; one of Codex alone, which uses no
  // Claude login, does, and takes no version (it runs no engine).
  w.benchBody = () => ({ ...BH.hist(), guard: { conveyor: false, agent: true } });
  act(bp(w), 'arms-again').click();
  await settle();
  assert.equal(act(bp(w), 'start').disabled, true);
  assert.equal(text(bp(w).querySelector('.bench-why')), 'The usage guard is reached for Claude alone: no run starts while it stands.');
  pick(w, 'arm-conveyor'); pick(w, 'arm-solo'); pick(w, 'arm-codex-sol');
  assert.equal(act(bp(w), 'start').disabled, false);
  // An arm with no priced session of its model (Codex here) has no cost, and no total stands for part of one.
  assert.deepEqual(plan().map((r) => r[4]), ['–']);
  assert.deepEqual(total(), ['–', 'at list prices', 'not priced: Codex alone (gpt-6.2-sol)']);
  act(bp(w), 'start').click();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [['run', '5', '--arm', 'codex-sol']]);
  await settle();
});

// Bug it guards: there was no picture of the results to share, and a picture made by hand or by a model can drop the
// limits. The infographic is filled by code from the runs selected on a fixed template; a title typed changes the
// title only, and the notes on how to read it stay on the SVG downloaded.
test('Infographic: made from 2 selected runs on the fixed template; a title typed cannot remove its notes', async () => {
  const w = await opened();
  pick(w, `pick-${NEW}`); pick(w, `pick-${OLD}`);
  act(bp(w), 'sel-infographic').click();
  assert.deepEqual(heads(w), ['Infographic', 'The same figures as a table']);
  const words = () => Array.from(bp(w).querySelectorAll('svg.bench-ig text'), (t) => t.textContent);
  const notes = ['How to read this', 'A task is resolved when its FAIL_TO_PASS and PASS_TO_PASS tests all succeed in the official harness on the arm\'s final patch.',
    'A difference inside the noise band is not a difference. Tasks are Python only, and the models may have seen these repositories.',
    'Each task ran in its own Docker container with the same limits for every arm. A task whose image did not build is "not run", never failed.',
    'This does not show that one way is better on your code.'];
  const w0 = words();
  assert.equal(w0[0], 'Conveyor against other ways to build, on SWE-bench Verified');
  for (const s of [`Run ${NEW} · 5 tasks · 3 arms`, `Run ${OLD} · 20 tasks · 1 arm · a different n: its own panel, no line across`, 'Conveyor 1.5.0', '4 of 5', 'Conveyor 1.4.0', '8 of 20', ...notes]) {
    assert.ok(w0.includes(s), `the graphic shows "${s}"`);
  }
  assert.ok(w0.some((s) => /^Made by code from 2 stored runs with a fixed template; no model wrote or chose anything · models: claude-opus-5-5, gpt-6\.2-sol · Conveyor 1\.5\.0, 1\.4\.0$/.test(s)), w0.join('\n'));
  assert.equal(bp(w).querySelectorAll('.bench-ig-table tr').length, 5, 'the same figures as a table: one row an arm of each run');
  const title = act(bp(w), 'ig-title');
  title.value = 'Conveyor wins';
  title.dispatchEvent(new w.Event('input'));
  assert.equal(words()[0], 'Conveyor wins');
  for (const s of notes) assert.ok(words().includes(s), `a title typed leaves "${s}"`);
  act(bp(w), 'ig-svg').click();
  assert.equal(w.downloads[0].name, 'ig-20261109-1700.svg');
  const svg = body(w.downloads[0].href);
  assert.match(svg, /^<svg xmlns="http:\/\/www\.w3\.org\/2000\/svg"/);
  for (const s of ['Conveyor wins', 'How to read this', 'This does not show that one way is better on your code.']) assert.ok(svg.includes(s), `the SVG downloaded holds "${s}"`);
  assert.ok(!/<script|<foreignObject/.test(svg), 'figures and text only');
  // Bug it guards (#326): the table said it was saved beside the SVG, and only the SVG was downloaded.
  assert.equal(w.downloads[1].name, 'ig-20261109-1700.csv');
  const csv = body(w.downloads[1].href).trim().split('\r\n');
  assert.equal(csv[0], '"Run","Arm","Resolved","Noise for n","Sessions","Tokens","Cost"');
  assert.equal(csv.length, 5, 'one line an arm of each run, as the table on the page');
  assert.ok(csv.some((l) => l.startsWith(`"${NEW}","Conveyor 1.5.0","4 of 5",`)), csv.join('\n'));
});
