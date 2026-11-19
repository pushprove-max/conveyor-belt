// SPDX-License-Identifier: Apache-2.0
// The Benchmarks tab's Overview (#326, the owner's approved mockup, overview.html): its page row, Newest run (each arm's
// resolved of n side by side with the noise for n, or the run in progress, or how the last run ended), History (every
// run newest first, ticked for Compare and the infographic), Arms and the Drift watch, folded. The runs come from GET
// bench, not the snapshot. Shared setup: dashboard-view.helpers.mjs (BH).
import assert from 'node:assert/strict';
import { boot, deliver, next, settle, act, cases, full, iso, T0, BH } from './dashboard-view.helpers.mjs';

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
  assert.deepEqual(Array.from(bp(w).querySelector('.bench-figures .figure').children, text), ['–', 'Conveyor 1.5.0: 13 sessions · 15.3M tokens · 1 h 42 min', 'cost: not kept yet']);
  assert.match(text(bp(w).querySelector('.bench-care')), /1 task not run for Codex alone \(gpt-6\.2-sol\): .*\(not counted as failed\)/);
  const rows = Array.from(bp(w).querySelectorAll('.bench-history tr[data-run]'), (r) => Array.from(r.children).slice(1).map(text));
  assert.deepEqual(rows, [[NEW, '10:00 AM', '5', 'Conveyor 1.5.0 · Claude alone (claude-opus-5-5) · Codex alone (gpt-6.2-sol)', '4 · 2 · 2', '22', '24.4M', '2 h 50 min', '–', 'Done 1 task not run'],
    [OLD, '11/08/2026, 11:00 AM', '20', 'Conveyor 1.4.0', '8', '30', '40.0M', '4 h 20 min', '–', 'Stopped at the usage guard']], 'every run, newest first');
  assert.deepEqual(Array.from(bp(w).querySelectorAll('.bench-arms tr'), (r) => [text(r.children[0]), ...Array.from(r.children[1].children, text)]),
    [['Ready', '3'], ['Preflight failing', '1', 'Claude with Superpowers: it did not fire: its output shows no use of its method'], ['Not checked', '1', 'Claude with Chisle'],
      ['Not offered', '1', 'OpenHands: it needs an API key']]);
  // Ticking runs shows the bar at the foot of the screen with Compare and Generate infographic.
  for (const id of [NEW, OLD]) { const b = act(bp(w), `pick-${id}`); b.checked = true; b.dispatchEvent(new w.Event('change')); }
  assert.deepEqual(Array.from(bp(w).querySelector('.bench-selbar').children, text),
    ['2 runs selected', 'Up to 6. Runs of different n get their own panel on the infographic.', 'Compare', 'Generate infographic', 'Clear']);
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
  assert.match(text(box), /^Running 2 arms on 5 tasks · now pydata__xarray-4094 Stop/);
  assert.deepEqual(Array.from(box.querySelectorAll('.bench-bar'), (b) => [b.querySelector('.bench-name').textContent, b.querySelector('.bench-num').textContent]),
    [['Conveyor 1.5.0', '2 of 5'], ['Claude alone (claude-opus-5-5)', '1 of 5']]);
  assert.equal(text(box.querySelector('.board-from')), 'tasks done by each arm · 7 sessions so far, usual for the run 18, worst case 45');
  w.reply = BH.reply('conveyor: the SWE-bench run is stopped');
  act(bp(w), 'stop').click();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body), [{ action: 'bench', args: ['stop'], repo: 'sample' }]);
  await settle();
  const said = () => { const p = bp(w).querySelector('.bench-running .bench-said'); return p && text(p); };
  assert.equal(said(), 'Stop sent: the benchmark run. conveyor: the SWE-bench run is stopped');
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
  assert.equal(w.benchAsks.length, 4, 'read again each time the run moved on');
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
