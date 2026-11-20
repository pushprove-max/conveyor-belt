// SPDX-License-Identifier: Apache-2.0
// The Benchmarks tab's other pages (#326, the owner's approved mockup: run.html, compare.html, start.html,
// infographic.html): a run's tasks by arm with one task opened and Export figures; Compare of two arms with the flipped
// tasks; Start a run with the cost before Start and only the arms whose preflight passed (#642: its run settings, the
// estimate of each arm ticked, Start held for an arm being checked, and the receipt that opens the run), and its arm editor (#641:
// a Conveyor or agent arm saved as a revision, listed again after a reload, and its checks); the infographic of the runs
// selected, whose notes a title cannot remove. Shared setup: dashboard-view.helpers.mjs (BH).
import assert from 'node:assert/strict';
import { boot, next, tick, settle, act, cases, full, BH } from './dashboard-view.helpers.mjs';

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
  assert.equal(text(mat.querySelector('tr[data-task] .bench-cell .bench-sub')), '3 sessions · 20 min · unknown');
  assert.deepEqual(Array.from(mat.querySelectorAll('tfoot tr'), cells), [['Resolved', '4 of 5', '2 of 5', '2 of 5'], ['Sessions · tokens', '13 · 15.3M', '5 · 5.5M', '4 · 3.6M'],
    ['Minutes · cost', '102 · unknown', '40 · unknown', '28 · unknown']]);
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
  // #632: the export's answer is beside it on the run page, not at the page's foot.
  assert.equal(text(bp(w).querySelector('.bench-run-head .bench-said')), `Exported: bench-${NEW}.json.`);
  const raw = body(w.downloads[0].href), figs = JSON.parse(raw);
  assert.deepEqual(figs.arms.map((a) => [a.label, a.resolved, a.sessions]), [['Conveyor 1.5.0', 4, 13], ['Claude alone (claude-opus-5-5)', 2, 5], ['Codex alone (gpt-6.2-sol)', 2, 4]]);
  const none = { reused: false, cost: { usd: null, state: 'unknown' } };
  assert.deepEqual(figs.tasks[1], { task: 'django__django-15347', arms: [{ arm: 'conveyor', result: 'resolved', sessions: 3, tokens: 4000000, minutes: 20, ...none },
    { arm: 'solo', result: 'not resolved', sessions: 1, tokens: 1000000, minutes: 8, ...none }, { arm: 'codex-sol', result: 'resolved', sessions: 1, tokens: 1000000, minutes: 8, ...none }] });
  for (const s of ['query.py', 'negation', 'combine()', 'patch', 'steps']) assert.ok(!raw.includes(s), `the export holds no code, finding or title: ${s}`);
  // Bug it guards (#632): the export's answer was kept by action only, so another run's page said it was exported.
  w.benchBody = (url) => (url.includes(`&run=${OLD}`) ? { ...BH.run(), run: BH.hist().runs.find((r) => r.id === OLD) } : BH.hist());
  act(bp(w), 'back').click();
  act(bp(w), `run-${OLD}`).click();
  await settle();
  assert.deepEqual(heads(w)[0], `Run ${OLD}`);
  assert.equal(bp(w).querySelector('.bench-said'), null, `no answer about bench-${NEW}.json on run ${OLD}`);
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

// Bug it guards (#643): every cell with no result showed "not reached" and "The run stopped before this arm reached the
// task.", so a run still going looked stopped, and after Stop the task it interrupted looked never reached.
test('A run: a cell with no result shows its step, waiting or interrupted, as `bench swe show` gives its state', async () => {
  const w = boot({ tab: 'bench' });
  BH.open(w, { body: (url) => {
    if (!/&run=/.test(url)) return BH.hist();
    const r = BH.run();
    r.tasks[1].cells = [{ arm: r.tasks[1].cells[0].arm, result: null, reused: false, state: 'active', phase: 'Reviewing' },
      { arm: r.tasks[1].cells[1].arm, result: null, reused: false, state: 'waiting' },
      { arm: r.tasks[1].cells[2].arm, result: null, reused: false, state: 'interrupted', cost: { usd: 0.3, state: 'known' } }];
    // A grade that failed after the trial ran: the run line keeps the trial's cost (a Docker image failure comes
    // before the trial, at a known $0).
    r.tasks[4].cells[2] = { ...r.tasks[4].cells[2], result: 'not run: the harness could not grade it (exit 1)', cost: { usd: 0.7, state: 'known' } };
    return r;
  } });
  await settle();
  act(bp(w), 'open-newest').click();
  await settle();
  const row = bp(w).querySelector('tr[data-task="django__django-15347"]');
  assert.deepEqual(Array.from(row.querySelectorAll('.bench-cell'), text), ['Reviewing', 'waiting', 'interrupted$0.30']);
  // Bug it guards (#646 review E4): the work Stop interrupted, and a task not run after its trial ran, showed no cost,
  // and Export figures said unknown for both, though `bench swe show` gives the cost the run line keeps.
  assert.equal(text(bp(w).querySelector('tr[data-task="sphinx-doc__sphinx-8595"] .bench-cell:last-child .bench-sub')), 'the harness could not grade it (exit 1) · $0.70');
  act(bp(w), 'export').click();
  const figs = JSON.parse(body(w.downloads[0].href));
  assert.deepEqual([figs.tasks[1].arms[2].cost, figs.tasks[4].arms[2].cost], [{ usd: 0.3, state: 'known' }, { usd: 0.7, state: 'known' }]);
  act(bp(w), 'task-django__django-15347').click();
  assert.deepEqual(Array.from(bp(w).querySelectorAll('.bench-task .bench-card p'), text), ['This arm is on the task now: Reviewing.',
    'The run has not reached this task for this arm yet.', 'Stop ended the work of this arm on this task. No result is kept.']);
});

// Bug it guards (#633): a run the build machine refused (no Docker) kept its reason, but History showed only "Did not
// start" and the run opened from it never said why, so the repair was nowhere on the Board once the Start reply was gone.
test('A run: a run refused for no Docker says its repair in History and on its own page', async () => {
  const w = boot({ tab: 'bench' });
  const why = 'Docker did not answer on the build machine. Install or start Docker, check that `docker info` works, then check again.';
  const refused = () => ({ ...BH.hist().runs[0], state: 'refused', why, cols: BH.hist().runs[0].cols.map((c) => ({ ...c, done: 0, resolved: 0, notRun: 0 })) });
  BH.open(w, { body: (url) => (/&run=/.test(url) ? { run: refused(), tasks: [] } : { ...BH.hist(), runs: [refused()] }) });
  await settle();
  assert.equal(text(bp(w).querySelector(`tr[data-run="${NEW}"] td:last-child`)), `Did not start${why}`);
  act(bp(w), `run-${NEW}`).click();
  await settle();
  assert.equal(text(bp(w).querySelector('.bench-run-head .bench-ended')), `Did not start ${why} See arms`);
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
  // Bug it guards (#632): Compare's answer was kept by action only, so another pair chosen still read "Compared.".
  const said = () => bp(w).querySelector('.bench-compare .bench-said');
  assert.equal(text(said()), 'Compared.');
  choose(w, 'cmp-a', 'codex-sol');
  assert.equal(said(), null, 'no answer about the last pair beside the new one');
  // Bug it guards (#632 E5): choosing the first pair again cleared its results but brought back "Compared.".
  choose(w, 'cmp-a', EB);
  assert.equal(said(), null, 'no answer beside a pair whose results were dropped');
  assert.equal(bp(w).querySelector('.bench-compare .bench-headline'), null);
  // Bug it guards (#651): a second click while "Sending…" was refused by send, but the click had already taken a new
  // ask, so the first request's reply was dropped and Compare showed no results.
  let answer;
  w.reply = new Promise((res) => { answer = res; });
  act(bp(w), 'compare').click();
  assert.equal(text(said()), 'Sending…');
  act(bp(w), 'compare').click();
  assert.equal(text(said()), 'Wait for the answer to the last action.');
  assert.equal(w.posts.splice(0).length, 1, 'the second click sends nothing');
  // A reply swe_diff can give: with no task flipped, both arms resolved the same tasks, and equal totals are
  // withinNoise: true (swe.sh's swe_diff). Bug it guards (#653): the fixture left withinNoise out, so the page said a
  // difference of 0 was "past the noise", which swe_diff never says.
  answer(BH.reply(JSON.stringify({ a: { version: A, commit: EB, totals: { resolved: 11 } }, b: { version: B2, commit: null, totals: { resolved: 11 } }, tasks: 20, same: [], flipped: [], withinNoise: true })));
  await settle();
  assert.equal(text(said()), 'Compared.');
  assert.equal(text(bp(w).querySelector('.bench-compare .bench-headline')),
    `On the 20 tasks both ran: ${A} resolved 11, ${B2} 11. 0 tasks flipped to ${A}, 0 the other way, 11 resolved by both, 9 by neither.`, 'the first reply is shown');
  assert.equal(text(bp(w).querySelector('.bench-compare > .board-from')),
    'With 20 tasks a difference under 7 tasks is within the noise. This difference is 0: within the noise.');
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
    ['conveyor', false, 'Ready'], ['solo', false, 'Ready'], ['superpowers', false, 'Preflight failed'], ['chisle', false, 'Not checked'], ['codex-sol', false, 'Ready'], ['openhands', true, 'Not offered']]);
  // Bug it guards: every agent arm was said to take one session a task; a method arm's spec can set more (chisle: 4).
  assert.deepEqual(['solo', 'chisle'].map((a) => text(bp(w).querySelector(`.bench-arm[data-arm="${a}"] .bench-sub`))), ['one session a task, headless', '4 sessions a task, headless']);
  assert.deepEqual(['check-superpowers', 'check-chisle', 'check-openhands'].map((a) => (act(bp(w), a) || {}).textContent || null), ['Check again', 'Check', null]);
  const plan = () => Array.from(bp(w).querySelectorAll('.bench-plan tr[data-arm]'), cells);
  // Bug it guards (#326): the cost was a dash everywhere. Each session is priced at the arm's mean session dollars
  // (Conveyor's $1.25: 50 usual sessions $62.50, 160 worst $200.00).
  assert.deepEqual(plan(), [['Conveyor', '0 of 20', '50', '160', '400', '$62.50 · worst $200.00', 'Not reached']], '20 tasks of Conveyor on main: none reused');
  assert.equal(text(bp(w).querySelector('.bench-arm[data-arm="conveyor"] .bench-cost')), '50 sessions (worst 160) · 400 min · $62.50');
  act(bp(w), 'preset-5').click();
  pick(w, 'arm-solo');
  choose(w, 'start-engine', 'v1.2.0');
  assert.deepEqual(plan(), [['Conveyor', '3 of 5', '5', '16', '40', '$6.25 · worst $20.00', 'Not reached'], ['Claude alone', '5 of 5', '0', '0', '0', '$0.00 · worst $0.00', 'Not reached']],
    'the tasks each arm ran on v1.2.0 are reused at no cost');
  const total = () => Array.from(bp(w).querySelectorAll('.bench-before .figure')[2].children, text);
  assert.deepEqual(Array.from(bp(w).querySelectorAll('.bench-before .figure .num'), (n) => n.textContent), ['5', '0.7 h', '$6.25']);
  assert.deepEqual(total(), ['$6.25', 'At list prices. Up to $20.00.']);
  // Bug it guards (#632): a figure's number and captions were spans with no space between, so the page read
  // "5sessions, usualworst case 16". Each figure is a number and one whole caption, as blocks with a real space.
  assert.deepEqual(Array.from(bp(w).querySelectorAll('.bench-before .figure'), (f) => f.textContent),
    ['5 Usually 5 sessions. Up to 16 sessions.', '0.7 h Of session time. The arms build one task at a time.', '$6.25 At list prices. Up to $20.00.']);
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
  assert.deepEqual(plan().map((r) => [r[0], r[6]]), [['Conveyor', 'Not reached'], ['Claude alone', 'Reached']], 'each arm says the guard that holds it');
  pick(w, 'arm-conveyor'); pick(w, 'arm-solo'); pick(w, 'arm-codex-sol');
  assert.equal(act(bp(w), 'start').disabled, false);
  // An arm with no priced session of its model (Codex here) has no cost, and no total stands for part of one.
  // Bug it guards (#642): the guard that can hold each arm was not shown; Codex alone uses no Claude login.
  assert.deepEqual(plan().map((r) => [r[5], r[6]]), [['–', 'None: no Claude login']]);
  assert.deepEqual(total(), ['–', 'Total cost unknown. No price data for Codex alone (gpt-6.2-sol).']);
  act(bp(w), 'start').click();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [['run', '5', '--arm', 'codex-sol']]);
  await settle();
});

// Bug it guards (#629): every arm's box was disabled until its preflight passed, so with every arm Not checked no box
// could be ticked and a click on one did nothing. Ticking an arm not ready sends its preflight (as Check does), shows
// it being checked, picks it once the arms read again show it Ready, and clears it when its preflight comes back
// failed; a Not offered arm's box stays disabled.
test('Start: ticking an arm not ready runs its preflight and picks it once it succeeds; one that fails is cleared; Not offered stays off', async () => {
  const w = await opened();
  act(bp(w), 'to-start').click();
  const arm = (a) => bp(w).querySelector(`.bench-arm[data-arm="${a}"]`);
  const state = (a) => [arm(a).querySelector('input').checked, arm(a).querySelector('.chip').textContent];
  assert.equal(act(bp(w), 'arm-openhands').disabled, true, 'a Not offered arm cannot be ticked');
  pick(w, 'arm-conveyor');
  // Bug it guards (#632): with no arm picked the estimate still showed a table head with no row and "$0.00".
  const est = () => bp(w).querySelector('.bench-before');
  assert.equal(est().querySelector('.bench-plan, th, .figure'), null, 'no estimate table, head or figure');
  assert.ok(!est().textContent.includes('$'), est().textContent);
  assert.equal(text(est().querySelector('.bench-no-estimate')), 'Choose an arm to see the estimate.');
  w.reply = BH.reply('conveyor: the arms\' preflights started');
  pick(w, 'arm-chisle');
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [['arms', 'check', 'chisle']]);
  await settle();
  pick(w, 'arm-superpowers');
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [['arms', 'check', 'superpowers']]);
  await settle();
  assert.deepEqual(['chisle', 'superpowers'].map(state), [[true, 'Checking its preflight…'], [true, 'Checking its preflight…']]);
  assert.equal(act(bp(w), 'start').disabled, true, 'no picked arm is Ready yet');
  assert.equal(est().querySelector('.bench-plan, th, .figure'), null, 'no estimate while the arms picked are being checked');
  assert.equal(text(est().querySelector('.bench-no-estimate')), 'Waiting for the check of Claude with Superpowers, Claude with Chisle. The estimate and Start wait for them.');
  const now = (a) => ({ chisle: { state: 'ready', at: '2026-11-19T06:20:00Z' }, superpowers: { state: 'failed', why: 'it is not logged in', at: '2026-11-19T06:20:00Z' } })[a.name];
  w.benchBody = () => { const x = BH.hist(); return { ...x, arms: x.arms.map((a) => ({ ...a, ...now(a) })) }; };
  act(bp(w), 'arms-again').click();
  await settle();
  assert.deepEqual(['chisle', 'superpowers'].map(state), [[true, 'Ready'], [false, 'Preflight failed']]);
  assert.match(text(arm('superpowers')), /it is not logged in/);
  assert.equal(act(bp(w), 'start').disabled, false);
  assert.equal(text(act(bp(w), 'start')), 'Start · 1 arm on 20 tasks');
});

// Bug it guards (#642): with one arm ready and another ticked while its check ran, Start was on and sent the ready arm
// alone, and the estimate read as the whole run. Start sends each arm ticked or none: it waits for the check, and for
// an arm ticked that is no longer ready.
test('Start: an arm ticked while its check runs, or no longer ready, holds Start and the estimate; then Start sends each arm shown', async () => {
  const w = await opened();
  act(bp(w), 'to-start').click();
  const why = () => text(bp(w).querySelector('.bench-before .bench-why'));
  const read = async (now) => { w.benchBody = (url) => (/&run=/.test(url) ? BH.run() : { ...BH.hist(), arms: BH.hist().arms.map((a) => ({ ...a, ...now[a.name] })) }); act(bp(w), 'arms-again').click(); await settle(); };
  w.reply = BH.reply('chisle: checking k-r20261119T130000-1');
  pick(w, 'arm-chisle');
  w.posts.splice(0);
  await settle();
  assert.deepEqual(Array.from(bp(w).querySelectorAll('.bench-arm input:checked'), (b) => b.dataset.act), ['arm-conveyor', 'arm-chisle']);
  assert.deepEqual([act(bp(w), 'start').disabled, why()], [true, 'Start waits for the check of Claude with Chisle.']);
  assert.equal(bp(w).querySelector('.bench-before .figure, .bench-plan'), null, 'no total that leaves the arm out');
  const chisle = { state: 'ready', at: '2026-11-19T06:20:00Z' };
  await read({ chisle, conveyor: { state: 'expired' } });
  assert.deepEqual([act(bp(w), 'start').disabled, why(), act(bp(w), 'arm-conveyor').checked], [true, 'Start waits for Conveyor, not ready.', true], 'an arm ticked is never dropped unseen');
  assert.equal(text(bp(w).querySelector('.bench-no-estimate')), 'Conveyor is not ready: check it, or untick it. The estimate and Start wait for it.');
  await read({ chisle });
  const rows = Array.from(bp(w).querySelectorAll('.bench-plan tr[data-arm]'), (r) => r.dataset.arm);
  assert.deepEqual([rows, text(act(bp(w), 'start'))], [['conveyor', 'chisle'], 'Start · 2 arms on 20 tasks']);
  act(bp(w), 'start').click();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [['run', '20', ...rows.flatMap((a) => ['--arm', a]), '--engine', 'main']]);
  await settle();
});

// Bugs it guards (#642): Start had no run settings: the task order and each container's limits were swe.json's alone,
// with no word that they apply to every arm; a result kept on other settings counted as reused; and an arm with no
// price made the total unknown even when it reused each task and ran no session.
test('Start: the run settings every arm shares show their defaults, refuse a value that does not read, and are sent only when changed', async () => {
  const w = boot({ tab: 'bench' });
  const x = BH.hist(), body = { ...x, set: { ...x.set, seed: 'conveyor-swe-1' }, limits: { cpus: 4, memory: '8g', taskTimeout: 14400 }, keys: x.keys.concat({ key: 'codex-sol', at: [0, 1, 2, 3, 4] }) };
  BH.open(w, { body: (url) => (/&run=/.test(url) ? BH.run() : body) });
  await settle();
  act(bp(w), 'to-start').click();
  assert.deepEqual(['revision', 'seed', 'cpus', 'memory', 'taskTimeout'].map((k) => act(bp(w), `set-${k}`).value), [x.set.revision, 'conveyor-swe-1', '4', '8g', '14400']);
  assert.match(text(bp(w).querySelector('.bench-settings > .board-from')), /^These apply to every arm: /);
  assert.deepEqual(['memory', 'taskTimeout'].map((k) => text(act(bp(w), `set-${k}`).nextElementSibling).replace(/^.* Default/, 'Default')), ['Default: 8g.', 'Default: 14400.']);
  // Bug it guards (#642 review E1): a refresh while a setting was typed (no change yet) put back the value last
  // changed, so the text typed was lost, and its caret with it.
  const seed = act(bp(w), 'set-seed');
  seed.focus(); seed.value = 'my-se ed'; seed.setSelectionRange(5, 5); seed.dispatchEvent(new w.Event('input'));
  const moved = full();
  moved.panels.bench.data.bench.versions.push({ name: 'v1.3.0', commit: 'c'.repeat(40) });  // an update the panel draws
  next(w, moved);
  await settle();
  const typed =act(bp(w), 'set-seed');
  assert.notEqual(typed, seed, 'the refresh drew the field again');
  assert.deepEqual([typed.value, w.document.activeElement === typed, typed.selectionStart], ['my-se ed', true, 5], 'the text typed, its focus and caret survive a refresh');
  // Bug it guards (#1014): a version new in the snapshot (a release since the last run) must be a choice at once, with no reload.
  assert.deepEqual(Array.from(act(bp(w), 'start-engine').options, (o) => o.value), ['main', 'v1.2.0', 'v1.3.0', 'commit']);
  choose(w, 'set-seed', 'conveyor-swe-1');
  const plan =() => Array.from(bp(w).querySelectorAll('.bench-plan tr[data-arm]'), cells);
  const total = () => Array.from(bp(w).querySelectorAll('.bench-before .figure')[2].children, text);
  act(bp(w), 'preset-5').click(); pick(w, 'arm-solo'); pick(w, 'arm-codex-sol');
  assert.deepEqual(plan().map((r) => [r[1], r[5]]), [['0 of 5', '$16.25 · worst $50.00'], ['5 of 5', '$0.00 · worst $0.00'], ['5 of 5', '$0.00 · worst $0.00']]);
  assert.deepEqual(total(), ['$16.25', 'At list prices. Up to $50.00.'], 'an arm with no price that runs no session leaves the total known');
  choose(w, 'set-memory', '256m');
  assert.equal(text(bp(w).querySelector('[data-why="memory"]')), 'Type <n>m or <n>g, 512m or more.');
  assert.deepEqual([act(bp(w), 'start').disabled, text(bp(w).querySelector('.bench-before .bench-why'))], [true, 'A run setting does not read: correct it beside its field.']);
  choose(w, 'set-memory', '4g'); choose(w, 'set-seed', 'my-seed');
  assert.equal(bp(w).querySelector('[data-why]'), null);
  // Results kept on the default settings are not this run's: reuse is not known and each task is counted.
  assert.deepEqual(plan().map((r) => [r[1], r[2]]), [['not known', '13'], ['not known', '5'], ['not known', '5']]);
  assert.deepEqual(total(), ['–', 'Total cost unknown. No price data for Codex alone (gpt-6.2-sol).']);
  assert.match(text(bp(w).querySelector('.bench-arm[data-arm="solo"]').parentElement.querySelector('.bench-stale')), /^Checked on the default run settings\./);
  act(bp(w), 'start').click();
  const [sent] = w.posts.splice(0).map((p) => p.body.args);
  assert.deepEqual([sent.slice(0, -1), JSON.parse(sent.at(-1))], [['run', '5', '--arm', 'conveyor', '--arm', 'solo', '--arm', 'codex-sol', '--engine', 'main', '--settings'], { seed: 'my-seed', memory: '4g' }]);
  await settle();
  // A default typed back, or a field left blank, is no change: no settings are sent and the reuse is known again.
  choose(w, 'set-memory', '8g'); choose(w, 'set-seed', '');
  assert.deepEqual([plan().map((r) => r[1]), bp(w).querySelector('.bench-stale')], [['0 of 5', '5 of 5', '5 of 5'], null]);
  act(bp(w), 'start').click();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [['run', '5', '--arm', 'conveyor', '--arm', 'solo', '--arm', 'codex-sol', '--engine', 'main']]);
  await settle();
});

// Bug it guards (#642): Start's answer named the run it started, but nothing opened it, and a run that reused each
// task's result ended with no way to its results. The receipt stays beside Start and opens its own run (not the
// newest); a run that ended before its answer opens at once.
test('Start: the receipt opens its own run and stays beside Start; a run that ended at once opens its results', async () => {
  const R1 = 'r20261119T130000-77', R2 = 'r20261119T131000-78';
  const w = boot({ tab: 'bench' });
  BH.open(w, { body: (url) => { const m = /&run=([^&]+)/.exec(url); return m ? { run: { ...BH.hist().runs[0], id: decodeURIComponent(m[1]) }, tasks: [] } : BH.hist(); } });
  await settle();
  act(bp(w), 'to-start').click();
  const said = () => text(bp(w).querySelector('[data-said="start"]'));
  w.reply = BH.reply(`conveyor: run ${R1} started`);
  act(bp(w), 'start').click();
  await settle();
  act(bp(w), 'preset-5').click();
  assert.equal(said(), `Run ${R1} started. Watch run`);
  act(bp(w), 'watch-run').click();
  await settle();
  assert.equal(heads(w)[0], `Run ${R1}`);
  act(bp(w), 'page-start').click();
  assert.equal(said(), `Run ${R1} started. Watch run`, 'the receipt stays in the draft');
  w.reply = BH.reply(`1/5 ${BH.TASKS[0]}: resolved (reused)\nResolved 5 of 5 with Conveyor; not run: 0.\nconveyor: run ${R2} ended`);
  act(bp(w), 'start').click();
  await settle();
  assert.equal(heads(w)[0], `Run ${R2}`, 'the run that ended opens at once');
  act(bp(w), 'page-start').click();
  assert.equal(said(), `Run ${R2} ended: it reused the saved result of each task. Open its results`);
});

// Bug it guards (#632): every action's answer went to one line at the foot of the page, so a Check showed nothing
// near its arm and the next action's answer replaced it. A Check's answer (sending, refused, passed) shows inside the
// arm it checks and stays through a redraw; List versions keeps its own answer beside it.
test('Start: a Check\'s answer shows in its arm through a redraw, pending, refused and passed; another action keeps its own', async () => {
  const w = await opened();
  act(bp(w), 'to-start').click();
  const inArm = (a) => { const p = bp(w).querySelector(`.bench-arm[data-arm="${a}"]`).parentElement.querySelector('.bench-said'); return p && text(p); };
  const versions = () => { const p = bp(w).querySelector('[data-said="versions"]'); return p && text(p); };
  let answer;
  w.reply = { ok: false, status: 403, text: () => new Promise((r) => { answer = r; }) };
  act(bp(w), 'check-chisle').click();
  act(bp(w), 'preset-5').click();  // a redraw while the check waits for its answer
  assert.equal(inArm('chisle'), 'Sending…');
  await settle();  // the host's reply has come; its text has not
  assert.equal(inArm('chisle'), 'Sending…');
  answer('only an admin can check an arm');
  await settle();
  act(bp(w), 'preset-20').click();
  assert.equal(inArm('chisle'), 'Not done: only an admin can check an arm');
  assert.equal(inArm('superpowers'), null, 'the answer is in the arm checked only');
  w.reply = BH.reply('conveyor: v1.5.0 v1.4.0');
  act(bp(w), 'versions').click();
  await settle();
  assert.equal(versions(), 'The versions are listed.');
  assert.equal(inArm('chisle'), 'Not done: only an admin can check an arm', 'another action leaves the check\'s answer');
  w.reply = BH.reply('conveyor: the arms\' preflights started');
  act(bp(w), 'check-chisle').click();
  await settle();
  act(bp(w), 'arms-again').click();
  await settle();
  // Still not checked when read again: the check is pending, and its answer says so.
  assert.equal(inArm('chisle'), 'the arms\' preflights started. Read the arms again in a few minutes.');
  assert.equal(versions(), 'The versions are listed.', 'the check\'s answer leaves List versions\' own');
  // Bug it guards (review E1): once the arm reads ready, its answer still said the check had started.
  w.benchBody = () => { const x = BH.hist(); return { ...x, arms: x.arms.map((a) => (a.name === 'chisle' ? { ...a, state: 'ready', at: '2026-11-19T06:20:00Z' } : a)) }; };
  act(bp(w), 'arms-again').click();
  await settle();
  assert.equal(inArm('chisle'), 'Check passed. Claude with Chisle is ready.');
  // A failed arm checked again reads failed with a new check time: its answer is the failure and why, not "started".
  act(bp(w), 'check-superpowers').click();
  await settle();
  w.benchBody = () => { const x = BH.hist(); return { ...x, arms: x.arms.map((a) => (a.name === 'superpowers' ? { ...a, why: 'it is not logged in', at: '2026-11-19T06:30:00Z' } : a)) }; };
  act(bp(w), 'arms-again').click();
  await settle();
  assert.equal(inArm('superpowers'), 'Check failed. it is not logged in. Edit the arm or fix its setup, then choose Check again.');
});

// Bug it guards (#639 review E2): the arms were read again only when the Board sent the panel an update, and a check
// alone moves no run, so the Board sends none: a check that ran showed neither its step nor its end until Read the
// arms again was pressed. The Overview's Checking row did not say the step. An arm whose check had expired had no
// Check again. While an arm reads checking, the panel's clock reads the arms again, with no update of the Board.
test('Start: a check that runs shows its step and is read again on the clock until it ends; the Overview says its step; an expired arm offers Check again', async () => {
  const w = await opened();
  const arm = (a) => bp(w).querySelector(`.bench-arm[data-arm="${a}"]`);
  const shown = (a) => [arm(a).querySelector('.chip').textContent, text(arm(a).querySelector('.bench-sub'))];
  let step = 'Running the trivial task';
  const now = (a) => ({ chisle: step ? { state: 'checking', step, at: '2026-11-19T06:20:00Z' } : { state: 'ready', at: '2026-11-19T06:25:00Z' },
    solo: { state: 'expired', at: '2026-11-17T06:00:00Z' } })[a.name];
  w.benchBody = () => { const x = BH.hist(); return { ...x, arms: x.arms.map((a) => ({ ...a, ...now(a) })) }; };
  act(bp(w), 'to-start').click();
  act(bp(w), 'arms-again').click();
  await settle();
  assert.deepEqual(shown('chisle'), ['Checking', 'Running the trivial task.']);
  assert.equal(arm('chisle').querySelector('.bench-sub').getAttribute('aria-live'), 'polite');
  assert.deepEqual([arm('solo').querySelector('.chip').textContent, text(act(bp(w), 'check-solo'))], ['Check expired', 'Check again']);
  // The clock alone, with no update of the Board, one second at a time for up to a minute: the test holds the panel
  // to reading again on its clock, not to one interval (#719).
  const clock = async () => { const n = w.benchAsks.length; for (let s = 0; s < 60 && w.benchAsks.length === n; s += 1) tick(w, 1000); await settle(); };
  const asks = w.benchAsks.length;
  step = 'Reading its change';
  await clock();
  assert.equal(w.benchAsks.length, asks + 1, 'the clock reads the arms again while one checks');
  assert.deepEqual(shown('chisle'), ['Checking', 'Reading its change.']);
  act(bp(w), 'back').click();
  const row = Array.from(bp(w).querySelectorAll('.bench-arms tr')).find((r) => text(r.children[0]) === 'Checking');
  assert.equal(text(row.children[1].querySelector('.bench-sub')), 'Claude with Chisle: Reading its change','the Overview says the step the check is at');
  step = null;
  await clock();
  act(bp(w), 'see-every-arm').click();
  assert.equal(shown('chisle')[0], 'Ready', 'the end of the check shows with no press');
  const done = w.benchAsks.length;
  await clock();
  assert.equal(w.benchAsks.length, done, 'once no check runs, the clock reads nothing');
});

// Bug it guards (review E2): answers were kept by action only, so List versions in one project replaced the answer
// another project's List versions had; and an answer given for one project showed on another project's page.
test('Start: an action\'s answer belongs to its project: another project\'s same action leaves it, and it shows on its own page only', async () => {
  const w = await opened();
  act(bp(w), 'to-start').click();
  const versions = () => { const p = bp(w).querySelector('.bench-said'); return p && text(p); };
  w.reply = BH.reply('conveyor: v1.5.0 v1.4.0');
  act(bp(w), 'versions').click();
  await settle();
  assert.equal(versions(), 'The versions are listed.');
  const other = full();
  other.panels.bench.data.repo = 'other';
  next(w, other);
  await settle();
  assert.equal(versions(), null, 'sample\'s answer is not on other\'s page');
  w.reply = { ok: false, status: 403, text: () => Promise.resolve('only an admin can list versions') };
  act(bp(w), 'versions').click();
  await settle();
  assert.equal(versions(), 'Not done: only an admin can list versions');
  next(w, full());
  await settle();
  assert.equal(versions(), 'The versions are listed.', 'sample keeps its own answer');
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
  assert.equal(text(bp(w).querySelector('.bench-infographic .bench-said')), 'Downloaded: ig-20261109-1700.svg and ig-20261109-1700.csv.');
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
  // Bug it guards (review E3): a download's answer was kept by action only, so other runs picked read as downloaded.
  act(bp(w), 'back').click();
  pick(w, `pick-${OLD}`);
  act(bp(w), 'sel-infographic').click();
  assert.equal(bp(w).querySelector('.bench-infographic .bench-said'), null, 'no answer about the last selection');
});

// The arm editor's history (#641), as `bench swe history` gives it: the models the project allows each pool by CLI
// (choices: no Codex builder), the seats a sandbox runs for a seat an arm leaves out (defaults: the judge follows the
// reviewer, fix and test repair the builder), each arm's spec and recipe facts, and the saved revisions given.
const EFF = { claude: ['low', 'medium', 'high', 'xhigh', 'max'], codex: ['minimal', 'low', 'medium', 'high', 'xhigh'], opencode: ['minimal', 'low', 'medium', 'high', 'xhigh', 'max'] };
const CHOICES = { source: 'project', builder: { claude: ['claude-opus-5-5', 'claude-sonnet-5-5'], codex: [], opencode: [] }, reviewer: { codex: ['gpt-6.1-sol', 'gpt-6-astra'], claude: ['claude-opus-5-5'], opencode: [] },
  agent: { claude: ['claude-opus-5-5', 'claude-sonnet-5-5'], codex: ['gpt-6.1-sol', 'gpt-6-astra'] }, efforts: EFF };
const DEFAULTS = { seats: { model: { model: 'claude-opus-5-5', effort: 'high', agent: 'claude' }, reviewer: { model: 'gpt-6.1-sol', effort: 'medium', agent: 'codex' },
  judge: { model: 'claude-opus-5-5', effort: 'medium', agent: 'claude' }, fix: null, testFix: null }, judgeOwn: false, judgeOn: true, judgeAlways: ['style'] };
const ARM = 'Claude builds, Codex reviews';
const saved = (id, spec, state = 'unchecked') => ({ name: id, label: ARM, kind: 'conveyor', state, why: null, at: state === 'ready' ? '2026-11-19T06:20:00Z' : null, guard: 'conveyor',
  perTask: { usual: 2.5, worst: 8, minutes: 20, session: 1.25 }, key: null, keyPrefix: '', revision: { id, name: ARM, at: '2026-11-19T06:00:00Z', recipe: 'conveyor' }, spec, sessions: null, effort: false });
const RECIPE = (model, sessions) => ({ sessions, effort: true, model });
function eh(revs = []) {
  const x = BH.hist(), more = { conveyor: { spec: { kind: 'conveyor' } }, solo: RECIPE('claude-opus-5-5', 1), chisle: RECIPE('claude-opus-5-5', 4), 'codex-sol': RECIPE('gpt-6.2-sol', 1) };
  const facts = (a) => { const m = more[a.name]; return !m ? {} : m.spec ? m : { sessions: m.sessions, effort: m.effort, spec: { kind: 'agent', recipe: a.name, cli: /^codex/.test(a.name) ? 'codex' : 'claude', model: m.model } }; };
  return { ...x, choices: CHOICES, defaults: DEFAULTS, arms: x.arms.map((a) => ({ ...a, ...facts(a) })).concat(revs) };
}
const opts = (w, a) => Array.from(act(bp(w), a).options, (o) => (o.disabled ? `${o.textContent} [off]` : o.textContent));
const seatsNow = (w) => Array.from(bp(w).querySelectorAll('.bench-seat'), (r) => (r.querySelector('.bench-seat-now') ? text(r.querySelector('.bench-seat-now'))
  : Array.from(r.querySelectorAll('select'), (s) => s.value).join(' · ')));
const named = (w, n) => { const f = act(bp(w), 'edit-name'); f.value = n; f.dispatchEvent(new w.Event('input')); };
const saveSent = (w) => w.posts.splice(0).map((p) => [...p.body.args.slice(0, 3), JSON.parse(p.body.args[3])]);
async function editing(body) {
  const w = boot({ tab: 'bench' });
  BH.open(w, { body });
  await settle();
  act(bp(w), 'to-start').click();
  return w;
}
// The Conveyor arm the editor saves, and a saved arm whose Codex builder this project does not allow.
const ID = 'arm-0123456789ab', spec = { kind: 'conveyor', rules: 'project', policy: { judgeOn: true }, seats: { model: { cli: 'claude', model: 'claude-sonnet-5-5', effort: 'max' },
  reviewer: { cli: 'claude', model: 'claude-opus-5-5', effort: 'medium' }, judge: { cli: 'codex', model: 'gpt-6-astra', effort: 'medium' },
  fix: { cli: 'claude', model: 'claude-sonnet-5-5', effort: 'low' }, testFix: { cli: 'claude', model: 'claude-opus-5-5', effort: 'max' } } };
const CX = 'arm-0000000000cd', cx = { kind: 'conveyor', seats: { model: { cli: 'codex', model: 'gpt-6.2-sol', effort: 'high' } } };

// Bugs it guards (#641): a benchmark arm's seats were a list someone picked in a file, with no way to say which model
// does what; and a Conveyor builder could be offered a Codex review model where the project lists no Codex builder.
// Each seat shows what runs; its own choice offers only what its pool allows on the CLI picked (a CLI changed changes
// both lists); and the saved spec holds exactly the seats chosen.
test('Arm editor: a Conveyor arm shows each seat\'s values, takes its own model for each, follows the CLI\'s models and efforts, and is saved', async () => {
  const w = await editing(() => eh());
  act(bp(w), 'new-conveyor').click();
  assert.deepEqual(heads(w), ['Start a run', 'Arms', 'Conveyor arm', 'Before you start']);
  assert.deepEqual(seatsNow(w), ['Project builder: claude · claude-opus-5-5 · high', 'Project reviewer: codex · gpt-6.1-sol · medium', 'claude · claude-opus-5-5 · medium',
    'Follow builder: claude · claude-opus-5-5 · high', 'Follow builder: claude · claude-opus-5-5 · high']);
  assert.match(text(bp(w).querySelector('[data-seat="judge"] .bench-sub')), /always accepts the findings of kind style/);
  act(bp(w), 'seat-model-own').click();
  assert.deepEqual(opts(w, 'seat-model-cli'), ['claude', 'codex (the project allows it no model here) [off]', 'opencode (the project allows it no model here) [off]']);
  choose(w, 'seat-model-model', 'claude-sonnet-5-5'); choose(w, 'seat-model-effort', 'max');
  assert.equal(seatsNow(w)[3], 'Follow builder: claude · claude-sonnet-5-5 · max', 'fix follows the arm\'s builder');
  act(bp(w), 'seat-reviewer-own').click();
  choose(w, 'seat-reviewer-effort', 'minimal');
  choose(w, 'seat-reviewer-cli', 'claude');
  assert.deepEqual([opts(w, 'seat-reviewer-model'), opts(w, 'seat-reviewer-effort'), act(bp(w), 'seat-reviewer-effort').value], [['claude-opus-5-5'], EFF.claude, 'medium'], 'the CLI changed its models and efforts');
  assert.equal(seatsNow(w)[2], 'codex · gpt-6.1-sol · medium', 'the project\'s judge follows the arm\'s reviewer onto another CLI');
  choose(w, 'seat-judge-mode', 'own'); choose(w, 'seat-judge-model', 'gpt-6-astra');
  act(bp(w), 'seat-fix-own').click(); choose(w, 'seat-fix-effort', 'low');
  act(bp(w), 'seat-testFix-own').click(); choose(w, 'seat-testFix-model', 'claude-opus-5-5');
  choose(w, 'edit-rules', 'project');
  assert.deepEqual([text(bp(w).querySelector('.bench-edit .bench-why')), act(bp(w), 'save-arm').disabled], ['Name the arm to save it.', true]);
  named(w, `${ARM} `);
  assert.deepEqual([text(bp(w).querySelector('.bench-edit .bench-why')), act(bp(w), 'save-arm').disabled], ['A name has no space at either end.', true], 'checked as typed, beside the field');
  named(w, ARM);
  w.reply = BH.reply(ID);
  act(bp(w), 'save-arm').click();
  assert.deepEqual(saveSent(w), [['arms', 'save', ARM, spec]]);
  await settle();
  assert.equal(text(bp(w).querySelector('[data-said="save-arm"]')), `Saved as ${ID}. It is under Saved arms: tick it to check it and use it.`);
});

// Bug it guards (#641): a saved arm was not offered on a later visit. After a reload the build machine lists the
// revision; it is checked, picked and started by its ID, and a copy reads its seats.
test('Arm editor: a saved Conveyor arm is listed after a reload, checked, started by its ID and copied with its seats', async () => {
  const v = await editing(() => eh([saved(ID, spec), saved(CX, cx)]));
  assert.equal(text(bp(v).querySelector('.bench-arm-pick > .board-label')), 'Saved arms');
  assert.equal(bp(v).querySelector(`.bench-arm[data-arm="${ID}"] .chip`).textContent, 'Not checked');
  assert.match(text(bp(v).querySelector(`.bench-arm[data-arm="${ID}"] .bench-sub`)), new RegExp(`^Saved .* as ${ID}: Builder claude · claude-sonnet-5-5 · max; Reviewer claude · claude-opus-5-5 · medium; Judge codex · gpt-6-astra · medium; Fix .*; engine and project rules`));
  v.reply = BH.reply(`${ID}: checking c1`);
  pick(v, `arm-${ID}`);
  assert.deepEqual(v.posts.splice(0).map((p) => p.body.args), [['arms', 'check', ID]]);
  await settle();
  v.benchBody = () => eh([saved(ID, spec, 'ready'), saved(CX, cx)]);
  act(bp(v), 'arms-again').click();
  await settle();
  act(bp(v), 'start').click();
  assert.deepEqual(v.posts.splice(0).map((p) => p.body.args), [['run', '20', '--arm', 'conveyor', '--arm', ID, '--engine', 'main']]);
  act(bp(v), `copy-${ID}`).click();
  assert.deepEqual([act(bp(v), 'edit-name').value, seatsNow(v)[0]], [ARM, 'claude · claude-sonnet-5-5 · max']);
  // Bug it guards (#641 review): a copy of an arm whose builder this project does not allow (a Codex builder, with no
  // Codex builder list) replaced it with the first Claude model unseen. It is kept, shown as not allowed, and holds Save.
  await settle();
  act(bp(v), `copy-${CX}`).click();
  assert.deepEqual([seatsNow(v)[0], opts(v, 'seat-model-model')], ['codex · gpt-6.2-sol · high', ['gpt-6.2-sol (not allowed here) [off]']]);
  assert.equal(text(bp(v).querySelector('[data-seat="model"] .bench-seat-why')), 'Not allowed: this project does not allow gpt-6.2-sol on codex here. Choose another.');
  assert.deepEqual([text(bp(v).querySelector('.bench-edit .bench-why')), act(bp(v), 'save-arm').disabled], ['Builder: this project does not allow the choice. Choose another.', true]);
  choose(v, 'seat-model-cli', 'claude');
  assert.deepEqual([seatsNow(v)[0], act(bp(v), 'save-arm').disabled], ['claude · claude-opus-5-5 · high', false], 'a choice the project allows frees Save');
});

// Bugs it guards (#641): an agent arm's model and method were fixed in its recipe file, its effort never chosen, and
// a CLI a container cannot sign in to could be offered. It starts on one session with Method None; each method shows
// its sessions; a CLI changed changes the models, efforts and methods offered; and the spec saved is what is shown.
const AID = 'arm-00000000000a', aspec = { kind: 'agent', recipe: 'codex-sol', cli: 'codex', model: 'gpt-6-astra', effort: 'minimal' };
test('Arm editor: an agent arm starts on Method None, shows each method\'s sessions, follows its CLI, and saves the choices shown', async () => {
  const w = await editing(() => eh());
  act(bp(w), 'new-agent').click();
  assert.deepEqual(heads(w), ['Start a run', 'Arms', 'Agent arm', 'Before you start']);
  assert.deepEqual(opts(w, 'edit-cli'), ['claude', 'codex', 'opencode (not available: a benchmark container cannot sign in to it yet) [off]']);
  assert.deepEqual(opts(w, 'edit-method'), ['None (Claude alone) · one session a task', 'Claude with Chisle · 4 sessions a task']);
  assert.deepEqual(['edit-method', 'edit-model', 'edit-effort'].map((a) => act(bp(w), a).value), ['solo', 'claude-opus-5-5', '']);
  choose(w, 'edit-method', 'chisle'); choose(w, 'edit-effort', 'high');
  choose(w, 'edit-cli', 'codex');
  assert.deepEqual([opts(w, 'edit-method'), opts(w, 'edit-model'), opts(w, 'edit-effort')], [['None (Codex alone (gpt-6.2-sol)) · one session a task'], CHOICES.agent.codex, ['the CLI\'s own', ...EFF.codex]]);
  assert.deepEqual(['edit-method', 'edit-model', 'edit-effort'].map((a) => act(bp(w), a).value), ['codex-sol', 'gpt-6.1-sol', 'high'], 'an effort the new CLI takes is kept');
  choose(w, 'edit-model', 'gpt-6-astra'); choose(w, 'edit-effort', 'minimal');
  named(w, 'Codex on astra');
  w.reply = BH.reply(AID);
  act(bp(w), 'save-arm').click();
  assert.deepEqual(saveSent(w), [['arms', 'save', 'Codex on astra', aspec]]);
  await settle();
  assert.equal(text(bp(w).querySelector('[data-said="save-arm"]')), `Saved as ${AID}. It is under Saved arms: tick it to check it and use it.`);
  // Bug it guards (#641 review): a new draft showed the last arm's save receipt, as if it were saved.
  act(bp(w), 'new-conveyor').click();
  assert.equal(bp(w).querySelector('[data-said="save-arm"]'), null, 'a new draft shows no receipt of the arm saved before it');
});

// Bug it guards (#641): a saved agent arm was not offered on a later visit. After a reload the revision is listed
// with its choices, checked, started by its ID, and a copy reads its choices.
test('Arm editor: a saved agent arm is listed after a reload with its choices, checked, started by its ID and copied', async () => {
  const rev =(state) => ({ ...saved(AID, aspec, state), kind: 'agent', label: 'Codex on astra', guard: 'codex', revision: { id: AID, name: 'Codex on astra', at: '2026-11-19T06:00:00Z', recipe: 'codex-sol' } });
  const v = await editing(() => eh([rev()]));
  assert.match(text(bp(v).querySelector(`.bench-arm[data-arm="${AID}"] .bench-sub`)), new RegExp(`^Saved .* as ${AID}: .* on codex · gpt-6-astra · minimal$`));
  v.reply = BH.reply(`${AID}: checking c1`);
  pick(v, `arm-${AID}`);
  assert.deepEqual(v.posts.splice(0).map((p) => p.body.args), [['arms', 'check', AID]]);
  await settle();
  v.benchBody = () => eh([rev('ready')]);
  act(bp(v), 'arms-again').click();
  await settle();
  act(bp(v), 'start').click();
  assert.deepEqual(v.posts.splice(0).map((p) => p.body.args), [['run', '20', '--arm', 'conveyor', '--arm', AID, '--engine', 'main']]);
  act(bp(v), `copy-${AID}`).click();
  assert.deepEqual(['edit-name', 'edit-cli', 'edit-model', 'edit-effort', 'edit-method'].map((a) => act(bp(v), a).value), ['Codex on astra', 'codex', 'gpt-6-astra', 'minimal', 'codex-sol']);
});

// Bugs it guards (#641): a check is of one revision; an edit saved while it runs is another, with an ID of its own,
// and a late success of the old one must not pick it. Unticking an arm while its check runs withdraws it: the
// success that comes after must not pick it again.
test('Saved arms: an old revision\'s check cannot pick its edited copy; an arm unticked during its check stays unpicked after it succeeds', async () => {
  const R1 = 'arm-aaaaaaaaaaaa', R2 = 'arm-bbbbbbbbbbbb', s1 = { kind: 'conveyor', seats: { model: { cli: 'claude', model: 'claude-opus-5-5', effort: 'high' } } };
  const s2 = { kind: 'conveyor', rules: 'engine', seats: { model: { ...s1.seats.model, effort: 'max' } } };
  const w = await editing(() => eh([saved(R1, s1)]));
  const arm = (id) => bp(w).querySelector(`.bench-arm[data-arm="${id}"]`);
  const shown = (id) => [arm(id).querySelector('input').checked, arm(id).querySelector('.chip').textContent];
  const read = async (...revs) => { w.benchBody = () => eh(revs); act(bp(w), 'arms-again').click(); await settle(); };
  w.reply = BH.reply(`${R1}: checking c1`);
  pick(w, `arm-${R1}`);
  await settle();
  act(bp(w), `copy-${R1}`).click();
  choose(w, 'seat-model-effort', 'max');
  w.reply = BH.reply(R2);
  act(bp(w), 'save-arm').click();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args.slice(0, 3)), [['arms', 'check', R1], ['arms', 'save', ARM]]);
  await settle();
  await read(saved(R1, s1, 'ready'), saved(R2, s2));
  assert.deepEqual([shown(R1), shown(R2)], [[true, 'Ready'], [false, 'Not checked']], 'the old revision\'s success picks the old revision only');
  assert.equal(arm(R2).parentElement.querySelector('.bench-said'), null, 'no answer of the old check beside the edited copy');
  w.reply = BH.reply(`${R2}: checking c2`);
  pick(w, `arm-${R2}`);
  await settle();
  await read(saved(R1, s1, 'ready'), { ...saved(R2, s2), state: 'checking', step: 'Running the trivial task' });
  pick(w, `arm-${R2}`);
  assert.deepEqual(shown(R2), [false, 'Checking']);
  await read(saved(R1, s1, 'ready'), saved(R2, s2, 'ready'));
  assert.deepEqual(shown(R2), [false, 'Ready'], 'the success after the untick does not pick it');
  w.posts.splice(0);
  act(bp(w), 'start').click();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [['run', '20', '--arm', 'conveyor', '--arm', R1, '--engine', 'main']]);
});
