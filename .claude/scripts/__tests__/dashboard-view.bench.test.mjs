// SPDX-License-Identifier: Apache-2.0
// The Benchmarks tab's Overview (#326, the owner's approved mockup, overview.html): its page row, Newest run (each arm's
// resolved of n side by side with the noise for n, or the run in progress, or how the last run ended), History (every
// run newest first, ticked for Compare and the infographic), Arms and the Drift watch, folded; the tab opened while a
// run goes, on that run's page with Stop run, else on Start a run, each time it is shown, and a run whose process is
// gone (#646); and each place a cost shows, recorded, partial or unknown (#646).
// The runs come from GET bench, not the snapshot. Shared setup: dashboard-view.helpers.mjs (BH).
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { boot, deliver, next, settle, act, cases, full, iso, T0, BH, tick, tabBtn } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const { bp, heads, pages, NEW, OLD } = BH;
const text = (el) => el.textContent.replace(/\s+/g, ' ').trim();
// The Newest run's bars: each arm's name (without its line under it) and its figure.
const bars = (w) => Array.from(bp(w).querySelectorAll('.bench-newest .bench-bar'), (b) => [b.querySelector('.bench-name').firstChild.textContent, b.querySelector('.bench-num').textContent]);

// Bug it guards: the Benchmarks were a small part of the Tests page, with no history, no figures by arm and no run
// to open, where the approved plan gave them a tab of their own. The overview shows the newest run per arm with the
// noise for its n, its figures and its notes, every run in History (read from GET bench, not the snapshot), the arms by
// state and the drift watch; the page row and the sections are the mockup's.
test('Overview: the newest run per arm with its noise, every run in History, the arms and the drift watch, as the mockup has them', async () => {
  const w = boot({ tab: 'bench' });
  BH.open(w);
  assert.match(bp(w).textContent, /Reading the runs…/, 'the runs are read when the tab is shown');
  await settle();
  assert.deepEqual(w.benchAsks, ['bench?repo=sample']);
  assert.deepEqual(pages(w), [['Overview', 'page'], ['A run', null], ['Compare', null], ['Start a run', null], ['Infographic', null]]);
  assert.deepEqual(heads(w), ['Newest run', 'History', 'Arms', 'Drift watch']);
  assert.equal(text(bp(w).querySelector('.bench-headline')), 'Conveyor 1.5.0 resolved 4 of 5; Claude alone (claude-opus-5-5) 2 of 5. With 5 tasks a difference under 4 tasks is within the noise.'
    + ' Conveyor 1.5.0 against Claude alone (claude-opus-5-5) (4 against 2) is not a difference.');
  assert.deepEqual(bars(w), [['Conveyor 1.5.0', '4 of 5'], ['Claude alone (claude-opus-5-5)', '2 of 5'], ['Codex alone (gpt-6.2-sol)', '2 of 5']]);
  const noise = bp(w).querySelector('.bench-newest .bench-noise');
  assert.deepEqual([noise.style.left, noise.style.width, noise.title], ['0%', '100%', 'noise for n=5'], 'the band is 4 tasks either side of 4 of 5, cut at 0 and 5');
  assert.deepEqual(Array.from(bp(w).querySelector('.bench-figures .figure').children, text), ['unknown', 'Conveyor 1.5.0: 13 sessions · 15.3M tokens · 1 h 42 min', 'cost at list prices']);
  assert.match(text(bp(w).querySelector('.bench-care')), /1 task not run for Codex alone \(gpt-6\.2-sol\): .*\(not counted as failed\)/);
  const rows = Array.from(bp(w).querySelectorAll('.bench-history tr[data-run]'), (r) => Array.from(r.children).slice(1).map(text));
  assert.deepEqual(rows, [[NEW, '10:00 AM', '5', 'Conveyor 1.5.0 · Claude alone (claude-opus-5-5) · Codex alone (gpt-6.2-sol)', '4 · 2 · 2', '22', '24.4M', '2 h 50 min', 'unknown', 'Done 1 task not run'],
    [OLD, '11/08/2026, 11:00 AM', '20', 'Conveyor 1.4.0', '8', '30', '40.0M', '4 h 20 min', 'unknown', 'Stopped at the usage guard']], 'every run, newest first');
  assert.deepEqual(Array.from(bp(w).querySelectorAll('.bench-arms tr'), (r) => [text(r.children[0]), ...Array.from(r.children[1].children, text)]),
    [['Ready', '3'], ['Checking', '0'], ['Preflight failing', '1', 'Claude with Superpowers: it did not fire: its output shows no use of its method'], ['Not checked', '1', 'Claude with Chisle'],
      ['Not offered', '1', 'Stub off: it needs an API key']]);
  // Ticking runs shows the bar at the foot of the screen with Compare, Generate infographic, Archive and Delete (#1053).
  for (const id of [NEW, OLD]) { const b = act(bp(w), `pick-${id}`); b.checked = true; b.dispatchEvent(new w.Event('change')); }
  assert.deepEqual(Array.from(bp(w).querySelector('.bench-selbar').children, text),
    ['2 runs selected', 'Up to 6. Runs of different n get their own panel on the infographic.', 'Compare', 'Generate infographic', 'Archive', 'Delete', 'Clear']);
  act(bp(w), 'sel-clear').click();
  assert.equal(bp(w).querySelector('.bench-selbar'), null);
});

// Bug it guards (#540): arms with no shared grade were set against the noise. In a one-task run where the first arm
// resolved the task and the second did not run it, the headline said 1 against 0 was past the noise, and History
// read its counts the same way. A count of resolved is set against the noise only when every arm was graded on all n.
test('Overview: arms not graded on the same tasks are not compared against the noise, in Newest run or History', async () => {
  const w = boot({ tab: 'bench' });
  const [c, s] = BH.hist().runs[0].cols, one = { ...BH.hist().runs[0], n: 1, cols: [{ ...c, done: 1, resolved: 1, notRun: 0 }, { ...s, done: 1, resolved: 0, notRun: 1 }] };
  const solo = { ...one, id: 'r20261109T140000-3', cols: [{ ...s, done: 1, resolved: 0, notRun: 1 }, { ...c, done: 1, resolved: 0, notRun: 0 }] };
  BH.open(w, { body: () => ({ ...BH.hist(), runs: [one, solo] }) });
  await settle();
  assert.equal(text(bp(w).querySelector('.bench-headline')), 'Conveyor 1.5.0 resolved 1 of 1; Claude alone (claude-opus-5-5) 0 of 1. With 1 task only a total break shows: a difference under 1 is within the noise.'
    + ' Conveyor 1.5.0 against Claude alone (claude-opus-5-5) (1 against 0) is not compared: not every task was graded for both.');
  // The second run's spread is 0, under its noise of 1: without the check History called it within the noise.
  assert.deepEqual(Array.from(bp(w).querySelectorAll('.bench-history tr[data-run]'), (r) => text(r.lastElementChild)), ['Done 1 task not run', 'Done 1 task not run']);
});

// Bug it guards: a run in progress showed one bar for all arms, so an arm far behind the others could not be seen;
// Stop must stop it. Each arm gets its bar of tasks done, with the task now and the sessions so far.
test('Overview: a run in progress shows a bar of tasks done per arm, the task now, the sessions so far, and Stop', async () => {
  const w = boot({ tab: 'bench' });
  const h = BH.hist(), id = 'r20261109T160000-12';
  h.runs.unshift({ ...h.runs[0], id, state: 'running', ended: null, current: 'pydata__xarray-4094', cols: h.runs[0].cols.slice(0, 2).map((c, i) => ({ ...c, sessions: [6, 1][i] })) });
  BH.open(w, { body: () => h });
  const d = full();
  d.panels.bench.data.bench.live = { id, state: 'running', pid: 1, arms: ['conveyor', 'solo'], n: 10, done: 3, resolved: 2, current: 'pydata__xarray-4094',
    cols: h.runs[0].cols.map(({ arm, key, label, kind, engine, version, model }) => ({ arm, key, label, kind, engine, version, model })),
    tasks: [{ id: 'a', arm: 'conveyor', result: 'resolved' }, { id: 'a', arm: 'solo', result: 'resolved' }, { id: 'b', arm: 'conveyor', result: 'unresolved' }] };
  next(w, d);
  await settle();
  const box = bp(w).querySelector('.bench-running');
  assert.match(text(box), /^Running 2 arms on 5 tasks · now pydata__xarray-4094 Stop run/);
  assert.deepEqual(Array.from(box.querySelectorAll('.bench-bar'), (b) => [b.querySelector('.bench-name').textContent, b.querySelector('.bench-num').textContent]),
    [['Conveyor 1.5.0', '2 of 5'], ['Claude alone (claude-opus-5-5)', '1 of 5']]);
  assert.equal(text(box.querySelector('.board-from')), 'tasks done by each arm · 7 sessions so far, usual for the run 18, worst case 45');
  // Bug it guards (#646): Stop sent no run ID, so a Stop that came late stopped the run after the one shown.
  w.reply = BH.reply(`conveyor: run ${id} is stopped. Its finished tasks are kept.`);
  act(bp(w), 'stop-run').click();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body), [{ action: 'bench', args: ['stop', id], repo: 'sample' }]);
  await settle();
  const said = () => { const p = bp(w).querySelector('.bench-running .bench-said'); return p && text(p); };
  assert.equal(said(), 'Run stopped. Finished results are kept.');
  // Bug it guards (#632): a Stop's answer was kept by action only, so the next run's Stop read "Stop sent" unclicked.
  const d2 = full();
  d2.panels.bench.data.bench.live = { ...d.panels.bench.data.bench.live, id: 'r20261109T170000-13' };
  next(w, d2);
  await settle();
  assert.match(text(bp(w).querySelector('.bench-running')), /^Running /);
  assert.equal(said(), null, 'no answer about the last run beside the new run\'s Stop');
});

// Bug it guards: how the last run ended was a word in a line, so a run stopped at the usage guard read like one the
// owner stopped, and a refused run did not say which arm's preflight failed. Each state is the mockup's; the history
// is read again when the run in progress moves on.
test('Overview: nothing yet, stopped at the usage guard, an arm\'s preflight failing and stopped by you each say what happened', async () => {
  const w = boot({ tab: 'bench' });
  let runs = [];
  BH.open(w, { body: () => ({ ...BH.hist(), runs }) });
  await settle();
  assert.equal(text(bp(w).querySelector('.bench-newest .bench-empty')), 'No benchmark has run. Start one with 1 task to check the arms work, or 20 for a first reading.');
  const run = (state, why) => ({ ...BH.hist().runs[0], state, why, cols: BH.hist().runs[0].cols.slice(0, 2).map((c, i) => ({ ...c, done: [5, 3][i] })) });
  const ended = async (state, why) => {
    runs = [run(state, why)];
    const d = full();
    d.panels.bench.data.bench.live = { id: NEW, state, n: 10, done: 8, tasks: [] };
    next(w, d);
    await settle();
    return text(bp(w).querySelector('.bench-ended'));
  };
  assert.equal(await ended('guard'), 'Stopped at the usage guard Claude alone (claude-opus-5-5) did 3 of 5 tasks. Start again later: the rest runs, the done tasks are reused.');
  assert.equal(await ended('refused', 'the arm superpowers cannot run: its preflight failed: it did not fire on the trivial task'),
    'superpowers: preflight failed it did not fire on the trivial task. The arm cannot be picked until its preflight succeeds. See arms');
  assert.equal(await ended('stopped'), 'Stopped by you 3 of 5 tasks done for every arm. The finished tasks are kept and reused.');
  // Bug (#633): a run the build machine refused (no Docker) said its arm could not be picked until a preflight passed.
  assert.equal(await ended('refused', 'Docker did not answer on the build machine. Install or start Docker, check that `docker info` works, then check again.'),
    'Did not start Docker did not answer on the build machine. Install or start Docker, check that `docker info` works, then check again. See arms');
  assert.equal(w.benchAsks.length, 5, 'read again each time the run moved on');
});

// Bug it guards (#237, moved from the Tests page): the drift watch was a line of figures, unfolded; a group of 2 cards
// read as if it meant something. It is folded under its summary, one row a figure, and a small group is called small.
test('Overview: the drift watch is folded, one row a figure, and a group of 2 cards is called too small', () => {
  const w = boot({ tab: 'bench' });
  const g = (engine, cards, x) => ({ engine, cards, landed: cards, blocked: 0, tokens: x, minutes: 14, reviews: 1, fixes: 0.2, waits: null });
  const d = full();
  d.panels.bench.data.drift = { before: g('aaaaaaaa1111', 5, 1320), after: g('bbbbbbbb2222', 2, 3000), small: ['after'] };
  w.benchBody = () => BH.hist();
  deliver(w, d);
  act(bp(w), 'page-overview').click();
  const box = bp(w).querySelector('.bench-drift details');
  assert.equal(box.open, false, 'folded');
  assert.equal(box.querySelector('summary').textContent, 'Engine aaaaaaa → bbbbbbb · 5 cards before, 2 since');
  assert.deepEqual(Array.from(box.querySelectorAll('tr'), (r) => Array.from(r.children, text)), [['Figure, a card', 'Before', 'Since', ''], ['Tokens', '1320', '3000', 'Too few cards'],
    ['Minutes', '14', '14', 'Too few cards'], ['Reviews to land', '1', '1', 'Too few cards'], ['Fix rounds', '0.2', '0.2', 'Too few cards'], ['Blocked', '0', '0', 'Too few cards'],
    ['Minutes waited', '-', '-', 'Too few cards']]);
  assert.deepEqual(Array.from(box.querySelectorAll('.warn-note'), (p) => p.textContent), ['The after group holds 2 cards: too small to mean anything (fewer than 5 cards).']);
  // Bug it guards (#326): the mockup's status column was left out, so a figure that moved read the same as one in
  // its usual range. A figure moved when its means are more than two standard errors apart (minutes: 9 apart, 2.8 a
  // standard error); with no spread read (minutes waited before), it says so.
  const sp = (tokens, minutes, reviews, fixes, waits) => ({ tokens, minutes, reviews, fixes, waits });
  d.panels.bench.data.drift = {
    before: { engine: 'aaaaaaaa1111', cards: 20, landed: 18, blocked: 2, tokens: 1320, minutes: 31, reviews: 1.6, fixes: 0.7, waits: 6, spread: sp(400, 8, 0.5, 0.5, null) },
    after: { engine: 'bbbbbbbb2222', cards: 18, landed: 16, blocked: 2, tokens: 1250, minutes: 22, reviews: 1.5, fixes: 0.6, waits: 5, spread: sp(380, 9, 0.6, 0.5, 3) }, small: [] };
  next(w, d);
  const box2 = bp(w).querySelector('.bench-drift details');
  assert.equal(box2.querySelector('summary').textContent, 'Engine aaaaaaa → bbbbbbb · 20 cards before, 18 since · 1 figure moved');
  assert.deepEqual(Array.from(box2.querySelectorAll('tr'), (r) => [text(r.children[0]), text(r.children[3])]).slice(1), [['Tokens', 'In its usual range'], ['Minutes', 'Moved'],
    ['Reviews to land', 'In its usual range'], ['Fix rounds', 'In its usual range'], ['Blocked', 'In its usual range'], ['Minutes waited', 'Not read']]);
});

// Bugs it guards (#646): the run in progress was a line on the Overview: opening the tab showed no step and no figures
// so far, its page had no Stop, and Stop named no run. The tab opens on the run going. Its first line has its state,
// its time and Stop run; a step change with the same done count shows; a read with no answer keeps the last update;
// Stop says Stopping and stays off until the build machine answers; the page then says how the run ended.
test('A run going: the tab opens on it, its step moves with the same done count, a lost read keeps it, Stop run ends it from its first line', async () => {
  const w = boot({ tab: 'bench' });
  const id = 'r20261109T164200-12', [t1, t2, t3, ...rest] = BH.TASKS, [C, S] = BH.hist().runs[0].cols;
  let phase = 'Building', state = 'running', lost = false, acost = { usd: null, state: 'unknown' }, atask = t3, rcost = { usd: 2, state: 'partial' };
  const going = () => state === 'running', usd = (v, s = 'known') => ({ usd: v, state: s });
  const c = (arm, result, o = {}) => ({ arm, result, reused: false, state: result ? 'finished' : going() ? 'waiting' : 'not reached', sessions: 1, minutes: 8, ...o });
  const show = () => ({
    run: { id, state, started: iso(T0 - 1080000), ended: going() ? null : iso(T0), updated: iso(T0 - 60000), n: 5, cost: rcost,
      active: going() ? { arm: 'conveyor', task: atask, phase, since: iso(T0 - 120000), start: iso(T0 - 300000), ...(acost ? { cost: acost } : {}) } : null,
      cols: [{ ...C, done: 2, resolved: 2, notRun: 0, cost: usd(1.2, 'partial'), wall: 8 }, { ...S, done: 2, resolved: 1, notRun: 0, cost: usd(0.8), wall: 16 }] },
    tasks: [{ id: t1, cells: [c('conveyor', 'resolved', { reused: true, cost: usd(3) }), c('solo', 'resolved', { cost: usd(0.4) })] },
      { id: t2, cells: [c('conveyor', 'resolved', { cost: usd(1.2) }), c('solo', 'unresolved', { cost: usd(0.4) })] },
      { id: t3, cells: [going() ? { arm: 'conveyor', result: null, reused: false, state: 'active', phase } : { arm: 'conveyor', result: null, reused: false, state: 'interrupted', cost: usd(0.4, 'partial') }, c('solo', null)] },
      ...rest.map((t) => ({ id: t, cells: [c('conveyor', null), c('solo', null)] }))],
    tail: [{ at: iso(T0 - 1080000), arm: null, task: null, event: 'Run started' }, { at: iso(T0 - 900000), arm: 'conveyor', task: t1, event: 'Reused: Resolved' },
      { at: iso(T0 - 120000), arm: 'conveyor', task: t3, event: phase }] });
  w.benchBody = (url) => (!/&run=/.test(url) ? BH.hist() : lost ? null : show());
  const snap = (seq) => { const d = full(); d.panels.bench.data.bench.live = { id, state, pid: 1, arms: ['conveyor', 'solo'], n: 10, done: 4, resolved: 3, seq, started: iso(T0 - 1080000), tasks: [] }; return d; };
  deliver(w, snap(1));
  await settle();
  assert.deepEqual(heads(w), [`Run ${id}`, 'Tasks by arm', 'Recent log'], 'the tab opens on the run going');
  assert.equal(pages(w).find(([p]) => p === 'A run')[1], 'page');
  const head = () => Array.from(bp(w).querySelector('.bench-run-head > .bench-head').children, text).slice(0, 4);
  assert.deepEqual(head(), [`Run ${id}`, 'Running', 'Elapsed 18 min', 'Stop run']);
  const now = () => text(bp(w).querySelector('.bench-now'));
  assert.match(now(), new RegExp(`^Now: Conveyor 1\\.5\\.0 · ${t3} · Building since `));
  assert.match(text(bp(w).querySelector('.bench-sofar')), /^4 of 10 arm results finished · 3 resolved · 1 reused · 0 not run · \$2\.00 recorded\. Cost for the active session is unknown\. Last update /);
  // Bug it guards (#646 review E3): the table for each arm had no reused or not run count and no active time, and
  // then an active time of the finished tasks only. Conveyor's 13 min is its wall of 8 min (bench swe's: a reused
  // result adds none) and the 5 min since its task in progress began; Claude alone's is its wall.
  assert.deepEqual(Array.from(bp(w).querySelectorAll('.bench-live tr'), (r) => Array.from(r.children, text)),
    [['Arm', 'Finished', 'Resolved', 'Reused', 'Not run', 'Current work', 'Active time', 'Cost so far'],
      ['Conveyor 1.5.0', '2 of 5', '2', '1', '0', `${t3} · Building`, '13 min', '$1.20 recorded, part unknown'], ['Claude alone (claude-opus-5-5)', '2 of 5', '1', '0', '0', 'Waiting', '16 min', '$0.80']]);
  // Bug it guards (#646 review E5): an agent in one phase sends no update, and its elapsed time stood still. It counts
  // on the Board's clock with no new read, as does the active time of the arm at work.
  tick(w, 120000);
  assert.equal(head()[2], 'Elapsed 20 min');
  assert.equal(text(bp(w).querySelector('.bench-live tr[data-arm="conveyor"]').children[6]), '15 min');
  assert.equal(act(bp(w), 'latest').textContent, 'Latest result', 'Latest result beside the heading');
  assert.equal(text(bp(w).querySelector(`tr[data-task="${t1}"] .bench-cell .bench-sub`)), '1 session · 8 min · reused, no new cost');
  assert.deepEqual(Array.from(bp(w).querySelectorAll('.bench-loglines li'), (li) => Array.from(li.children, text).slice(1)),
    [['Run', '', 'Run started'], ['Conveyor 1.5.0', t1, 'Reused: Resolved'], ['Conveyor 1.5.0', t3, 'Building']]);
  // The step moves on and no result comes: done stays 4, seq goes up.
  // Bug it guards (#643): the run page read the run again only when the live run's `done` changed, so a step change
  // (Building to Reviewing, `seq` up, `done` the same) kept the cached Building cell until a result arrived.
  const cell = () => text(bp(w).querySelector(`tr[data-task="${t3}"] .bench-cell`));
  assert.equal(cell(), 'Building');
  phase = 'Reviewing';
  next(w, snap(2));
  await settle();
  assert.match(now(), / · Reviewing since /, 'the step change read the run again');
  assert.equal(cell(), 'Reviewing', 'the step change redrew the matrix cell');
  assert.match(text(bp(w).querySelector('.bench-sofar')), /^4 of 10 arm results finished/);
  // A read with no answer keeps the last update and says so; Read again reads it.
  phase = 'Testing'; lost = true;
  next(w, snap(3));
  await settle();
  assert.match(now(), / · Reviewing since /, 'the last update stays');
  assert.match(text(bp(w).querySelector('.bench-lost')), /^The last read of this run got no answer: no benchmarks\. The page shows the update of .*\. Read again$/);
  lost = false;
  act(bp(w), 'run-read-again').click();
  await settle();
  assert.match(now(), / · Testing since /);
  assert.equal(bp(w).querySelector('.bench-lost'), null);
  // Bug it guards (#646 review E6): a task preparing its image has no session yet, and the line said the cost of the
  // active session was unknown.
  phase = 'Preparing image'; acost = null;
  next(w, snap(4));
  await settle();
  assert.match(text(bp(w).querySelector('.bench-sofar')), /\$2\.00 recorded\. Part of the cost is unknown\. Last update /);
  // Bug it guards (#750): an arm checking its preflight (active with no task) counted its active time up from the
  // check's start, then dropped back to its wall, which has task work only, once Checking moved to the next arm.
  // Bug it guards: a run whose cost is an agent arm's estimate said "Cost unknown." on its line.
  phase = 'Checking'; atask = null; rcost = usd(2, 'estimate');
  next(w, snap(5));
  await settle();
  assert.match(now(), /^Now: Conveyor 1\.5\.0 · Checking since /);
  assert.match(text(bp(w).querySelector('.bench-sofar')), / · Estimated list price \$2\.00\. Last update /);
  assert.equal(text(bp(w).querySelector('.bench-live tr[data-arm="conveyor"]').children[6]), '8 min', 'a preflight adds no active time');
  atask = t3;
  // Bug it guards (#646 review E1): the tab chose its page once, so a person back from another tab saw the page they
  // left, not the run going.
  act(bp(w), 'page-overview').click();
  tabBtn(w, 'overview').click();
  await settle();
  tabBtn(w, 'bench').click();
  await settle();
  assert.equal(pages(w).find(([p]) => p === 'A run')[1], 'page', 'the tab shown again opens on the run going');
  // Stop run, from the run's first line: it names the run and stays off until the build machine answers.
  let answer;
  w.reply = new Promise((res) => { answer = res; });
  act(bp(w), 'stop-run').click();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body), [{ action: 'bench', args: ['stop', id], repo: 'sample' }]);
  const stop = act(bp(w), 'stop-run'), said = () => text(bp(w).querySelector('.bench-run-head .bench-said'));
  assert.deepEqual([stop.textContent, stop.disabled, said()], ['Stopping run', true, `Stopping run ${id}. Finished results are kept.`]);
  state = 'stopped';
  answer(BH.reply(`conveyor: run ${id} is stopped. Its finished tasks are kept.`));
  await settle();
  assert.deepEqual(head().slice(0, 3), [`Run ${id}`, 'Stopped', 'Elapsed 18 min'], 'how it ended');
  assert.equal(act(bp(w), 'stop-run'), null, 'no Stop run once it ended');
  assert.equal(said(), 'Run stopped. Finished results are kept.');
  assert.equal(text(bp(w).querySelector('.bench-run-head .bench-ended')), 'Stopped by you 2 of 5 tasks done for every arm. The finished tasks are kept and reused.');
  assert.equal(text(bp(w).querySelector(`tr[data-task="${t3}"] .bench-cell`)), 'interrupted$0.40 recorded, part unknown');
  assert.equal(bp(w).querySelector('.bench-now'), null);
});

// Bug it guards (#752): docs/board.md said the active time counts on while the run goes, though the preflight check
// before the first task adds none (the case above). A text check, as a guide page has no behaviour to run.
test('The guide says a preflight adds no active time, as the run page counts it', () => {
  const guide = readFileSync(new URL('../../../docs/board.md', import.meta.url), 'utf8').replace(/\s+/g, ' ');
  assert.doesNotMatch(guide, /active time counts? on while the run goes/, 'active time does not count on during the preflight check');
  assert.match(guide, /the run checks the preflight of each arm, and this check adds no active time/);
  assert.match(guide, /The active time of an arm counts on only while the arm works on a task\./);
});

// Bug it guards (#646 review E1): with no run going the tab opened on the Overview, so Start a run was a click away,
// and a person back from another tab saw the page they had left; neither heading linked to the latest result.
test('No run going: the tab opens on Start a run with Latest result beside its heading, and again when shown again', async () => {
  const w = boot({ tab: 'bench' });
  w.benchBody = (url) => (/&run=/.test(url) ? BH.run() : BH.hist());
  deliver(w, full());
  await settle();
  assert.equal(pages(w).find(([p]) => p === 'Start a run')[1], 'page');
  assert.equal(heads(w)[0], 'Start a run');
  act(bp(w), 'latest').click();
  await settle();
  assert.equal(heads(w)[0], `Run ${NEW}`, 'Latest result opens the newest run that ended');
  assert.equal(act(bp(w), 'latest'), null, 'no link to the run shown');
  tabBtn(w, 'overview').click();
  await settle();
  tabBtn(w, 'bench').click();
  await settle();
  assert.equal(heads(w)[0], 'Start a run', 'the tab shown again opens on Start a run');
});

// Bug it guards (#646 review E2): a run whose process was gone with no end written read as stopped by you, with no
// Stop run, so its end was never recorded and its containers stayed. It says interrupted and keeps Stop run.
test('A run whose process is gone: its page says interrupted and keeps Stop run, which records its end', async () => {
  const w = boot({ tab: 'bench' });
  const id = 'r20261109T164200-13', r0 = BH.hist().runs[0];
  let recorded = false;
  // As bench swe gives it: gone with no ended, then the end Stop recorded, which keeps gone.
  const run = () => ({ ...r0, id, state: 'stopped', gone: true, ended: recorded ? iso(T0) : null, interrupted: recorded ? { arm: 'conveyor', task: BH.TASKS[0] } : undefined });
  BH.open(w, { body: (url) => (/&run=/.test(url) ? { run: run(), tasks: [] } : { ...BH.hist(), runs: [run(), ...BH.hist().runs] }) });
  await settle();
  assert.match(text(bp(w).querySelector('.bench-newest .bench-ended')), /^Run interrupted Its process ended with no end recorded/);
  act(bp(w), 'open-newest').click();
  await settle();
  const head = () => Array.from(bp(w).querySelector('.bench-run-head > .bench-head').children, text).slice(1, 3);
  assert.deepEqual(head(), ['Interrupted', 'Elapsed –']);
  w.reply = BH.reply(`conveyor: run ${id} was interrupted: its process had ended. Its end is recorded, its containers are removed, and its finished tasks are kept.`);
  act(bp(w), 'stop-run').click();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [['stop', id]]);
  recorded = true;
  await settle();
  assert.match(text(bp(w).querySelector('.bench-run-head .bench-said')), /^Run interrupted: its process had ended\./);
  assert.equal(act(bp(w), 'stop-run'), null, 'no Stop run once its end is recorded');
  // Bug it guards (#646 review E2, again): once Stop recorded its end, the page said "Stopped by you". It still says
  // interrupted, on its first line, under it and in History.
  assert.equal(head()[0], 'Interrupted');
  assert.match(text(bp(w).querySelector('.bench-run-head .bench-ended')), /^Run interrupted Its process ended before Stop, after \d+ of \d+ tasks for every arm\. Stop recorded its end/);
  act(bp(w), 'back').click();
  await settle();
  assert.match(text(bp(w).querySelector(`.bench-history tr[data-run="${id}"]`).lastElementChild), /^Interrupted/);
});

// Bug it guards (#646): every cost of a run read "–" (not kept), so a cost recorded in full, one recorded in part and
// one never recorded looked the same in History, on a run's page, in its export, in Compare and in the infographic's
// table. A cost never recorded is unknown, never $0.
test('Costs: History, a run, its export, Compare and the infographic table tell a recorded, a partial and an unknown cost apart', async () => {
  const w = boot({ tab: 'bench' });
  // Bug it guards: an agent arm's cost, state "estimate", fell through to unknown in each place.
  const h = BH.hist(), [r0, r1] = h.runs, known = { usd: 2.5, state: 'known' }, part = { usd: 1.2, state: 'partial' }, est = { usd: 0.2, state: 'estimate' };
  h.runs = [{ ...r0, cost: part, cols: r0.cols.map((x, i) => ({ ...x, cost: [known, part, null][i] })) }, { ...r1, cost: known }, { ...r1, id: 'r20261107T100000-5', cost: null }, { ...r1, id: 'r20261106T100000-4', cost: est }];
  const run = BH.run();
  run.run = h.runs[0];
  run.tasks[0].cells = run.tasks[0].cells.map((x, i) => ({ ...x, cost: [{ usd: 0.5, state: 'known' }, { usd: 0.1, state: 'partial' }, est][i] }));
  BH.open(w, { body: (url) => (/&run=/.test(url) ? run : h) });
  await settle();
  assert.deepEqual(Array.from(bp(w).querySelectorAll('.bench-history tr[data-run]'), (r) => text(r.children[9])), ['$1.20 recorded, part unknown', '$2.50', 'unknown', '$0.20 estimate']);
  act(bp(w), `run-${NEW}`).click();
  await settle();
  assert.deepEqual(Array.from(bp(w).querySelector(`tr[data-task="${BH.TASKS[0]}"]`).querySelectorAll('.bench-cell .bench-sub'), text),
    ['3 sessions · 20 min · $0.50', '1 session · 8 min · $0.10 recorded, part unknown', '1 session · 8 min · $0.20 estimate']);
  assert.deepEqual(Array.from(bp(w).querySelector('.bench-mat tfoot tr:last-child').children, text), ['Minutes · cost', '102 · $2.50', '40 · $1.20 recorded, part unknown', '28 · unknown']);
  act(bp(w), 'export').click();
  const figs = JSON.parse(decodeURIComponent(w.downloads[0].href.slice(w.downloads[0].href.indexOf(',') + 1)));
  assert.deepEqual([figs.cost, ...figs.arms.map((a) => a.cost), ...figs.tasks[0].arms.map((a) => a.cost)],
    [part, known, part, { usd: null, state: 'unknown' }, { usd: 0.5, state: 'known' }, { usd: 0.1, state: 'partial' }, est]);
  act(bp(w), 'back').click();
  const box = act(bp(w), `pick-${NEW}`); box.checked = true; box.dispatchEvent(new w.Event('change'));
  act(bp(w), 'sel-compare').click();
  w.reply = BH.reply(JSON.stringify({ a: { version: 'A', commit: null, totals: { resolved: 4, sessions: 13, tokens: 1, minutes: 102, cost: part } },
    b: { version: 'B', commit: null, totals: { resolved: 2, sessions: 5, tokens: 1, minutes: 40, cost: { usd: null, state: 'unknown' } } }, tasks: 5, same: [], flipped: [], withinNoise: true }));
  act(bp(w), 'compare').click();
  await settle();
  assert.deepEqual(Array.from(bp(w).querySelectorAll('.bench-compare tr'), (r) => Array.from(r.children, text).slice(5)).slice(1),
    [['$1.20 recorded, part unknown', '$0.30 recorded, part unknown'], ['unknown', 'unknown']]);
  act(bp(w), 'back').click();
  act(bp(w), 'sel-infographic').click();
  act(bp(w), 'ig-svg').click();
  const csv = decodeURIComponent(w.downloads[2].href.slice(w.downloads[2].href.indexOf(',') + 1)).trim().split('\r\n');
  assert.deepEqual(csv.slice(1).map((l) => /"([^"]*)"$/.exec(l)[1]), ['$2.50', '$1.20 recorded, part unknown', 'unknown']);
});
