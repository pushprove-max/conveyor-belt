// SPDX-License-Identifier: Apache-2.0
// The Benchmarks tab's Archive, Restore and Delete of runs (#1053), in their places on the rebuilt tab (#1177): the
// Scoreboard's run history (folded at its foot of the page, for any number of shared tasks). Each sends `bench swe runs archive |
// restore | delete <id>...`; an archived run leaves the figures and stays in the run history, marked; Delete takes one
// confirm that names the runs; a run that has not ended has both off. Shared setup: dashboard-view.helpers.mjs (BH).
import assert from 'node:assert/strict';
import { boot, settle, act, next, full, cases, BH } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const { bp, page, OLDS, STUDY } = BH;
const text = (el) => el.textContent.replace(/\s+/g, ' ').trim();
const tick = (w, id) => { const b = act(bp(w), `pick-${id}`); b.checked = !b.checked; b.dispatchEvent(new w.Event('change')); };
const V14 = OLDS[4][1];
// The requests sent since the last call, as their args, without the diffs that Versions and Compare ask for by themselves.
const sent = (w) => w.posts.splice(0).map((p) => p.body.args).filter((a) => a[0] !== 'diff');
async function opened(set, p) {
  const w = boot({ tab: 'bench' });
  BH.open(w, set);
  await settle(); await settle();
  if (p) { BH.go(w, p); await settle(); await settle(); }
  return w;
}
// The runs' lines of the set served changed as `over` says (by run id), as the history reads after an action: BH.open
// serves the set's history as it is at each read.
const mark = (set, over) => { set.hist.runs = set.hist.runs.map((r) => ({ ...r, ...(over[r.id] || {}) })); };

// Bug it guards: the rebuilt tab had no History, so a failed or test run stayed in the figures for good. In the
// Scoreboard's run history (folded, kept open through a redraw), Archive of a run ticked sends `bench swe runs archive
// <id>`; once the history reads it archived, it is marked there and leaves the Versions trend, and Restore of it brings it back.
test('Scoreboard run history: Archive takes a run out of the figures and marks it archived; Restore brings it back', async () => {
  const set = BH.study(), w = await opened(set);
  const fold = page(w).querySelector('details.bench-history');
  fold.open = true; fold.dispatchEvent(new w.Event('toggle'));
  tick(w, V14);
  const bar = () => page(w).querySelector('.bench-history .bench-selbar');
  assert.equal(page(w).querySelector('details.bench-history').open, true, 'the fold stays open through the redraw');
  assert.deepEqual(Array.from(bar().children, text), ['1 run selected', 'Archive', 'Delete', 'Clear']);
  w.reply = BH.reply(`conveyor: archived ${V14}.`);
  act(bar(), 'archive-runs').click();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body), [{ action: 'bench', args: ['runs', 'archive', V14], repo: 'sample' }]);
  mark(set, { [V14]: { archived: '2026-11-09T10:00:00Z' } });
  await settle(); await settle();
  assert.equal(text(page(w).querySelector('.bench-history .bench-said')), `Archived ${V14}.`);
  assert.match(text(page(w).querySelector(`.bench-history tr[data-run="${V14}"]`)), /done archived/);
  assert.equal(bar(), null, 'the run archived is no longer ticked');
  BH.go(w, 'versions');
  assert.ok(!Array.from(page(w).querySelectorAll('.bench-versions tbody tr'), (r) => r.firstChild.textContent).includes('v1.4.0'), 'an archived run is in no figure');
  BH.go(w, 'score');
  tick(w, V14);
  w.reply = BH.reply(`conveyor: restored ${V14}.`);
  act(bar(), 'restore-runs').click();
  assert.deepEqual(sent(w), [['runs', 'restore', V14]], 'an archived run offers Restore');
  mark(set, { [V14]: { archived: undefined } });
  await settle(); await settle();
  BH.go(w, 'versions');
  assert.equal(page(w).querySelector('.bench-versions tbody tr').firstChild.textContent, 'v1.4.0', 'the run restored is back in the figures');
});

// Bug it guards: the owner keeps Archive, Restore, Delete and the "archived" chip on the run history (#1216); a run
// already archived shows the chip, and ticked it offers Restore and Delete (not Archive), each sending its request.
test('Scoreboard, a run archived: its row shows the archived chip, and ticked it offers Restore and Delete, each sending its request', async () => {
  const w = await opened(BH.study()), id = BH.ARCHIVED;
  assert.deepEqual(Array.from(page(w).querySelectorAll(`.bench-history tr[data-run="${id}"] .chip`), text), ['done', 'archived']);
  assert.equal(Array.from(page(w).querySelectorAll('.bench-history tbody .chip'), text).filter((t) => t === 'archived').length, 1, 'only the run archived has the chip');
  tick(w, id);
  const bar = () => page(w).querySelector('.bench-history .bench-selbar');
  assert.deepEqual(Array.from(bar().children, text), ['1 run selected', 'Restore', 'Delete', 'Clear']);
  w.reply = BH.reply(`conveyor: restored ${id}.`);
  act(bar(), 'restore-runs').click();
  assert.deepEqual(sent(w), [['runs', 'restore', id]]);
  await settle(); await settle();
  tick(w, id);
  const del = act(bar(), 'delete-runs');
  del.click(); w.reply = BH.reply(`conveyor: deleted ${id}.`); del.click();
  assert.deepEqual(sent(w), [['runs', 'delete', id]], 'Delete sends its request after the second click');
});

// Bug it guards: runs could not be deleted, one or several at once. Delete of two runs ticked asks once, in words that
// name both and say a result another run shows stays (history's shared), then sends one request for both. A result only
// the runs ticked show is not counted as staying.
test('Scoreboard run history: Delete of two runs ticked takes one confirm that names them and the result that stays', async () => {
  const set = BH.study(), [a, b] = [OLDS[3][1], V14];
  mark(set, { [a]: { shared: { 'k/t-1': [b], 'k/t-2': [STUDY] } }, [b]: { shared: { 'k/t-1': [a] } } });
  const w = await opened(set);
  tick(w, a); tick(w, b);
  const del = page(w).querySelector('.bench-history .bench-selbar [data-act="delete-runs"]');
  del.click();
  assert.deepEqual(w.posts, [], 'the first click sends nothing');
  assert.equal(del.textContent, `Click again: delete ${a} and ${b} (1 result another run shows stays; the rest goes)`);
  // Bug it guards: the button's own aria-label ('Delete <runs>') hid the confirm, so a screen reader never heard the
  // shared-result warning.
  assert.equal(del.getAttribute('aria-label'), del.textContent, 'a screen reader hears the confirm, not "Delete <runs>"');
  w.reply = BH.reply(`conveyor: deleted ${a}, ${b}; 1 result stays: another run shows it.`);
  del.click();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [['runs', 'delete', a, b]], 'one request deletes both');
  set.hist.runs = set.hist.runs.filter((r) => r.id !== a && r.id !== b);
  await settle(); await settle();
  assert.equal(text(page(w).querySelector('.bench-history .bench-said')), `Deleted ${a}, ${b}; 1 result stays: another run shows it.`);
  assert.deepEqual(Array.from(page(w).querySelectorAll('.bench-history tbody tr'), (r) => r.dataset.run), [STUDY, ...OLDS.slice(0, 3).map(([, id]) => id), BH.ARCHIVED]);
});

// Bug it guards: Compare kept the diff of a pair while the Board was open, through a Delete of the run whose results it
// read, so a new run under the same results key showed the deleted run's reading. After a Delete, Compare asks again.
test('Scoreboard run history: after a Delete, Compare asks for the diff of a pair it read before', async () => {
  const set = BH.study(), w = await opened(set, 'compare');
  const diffs = () => w.posts.splice(0).map((p) => p.body.args).filter((a) => a[0] === 'diff');
  assert.equal(diffs().length, 1, 'Compare asks for its pair once');
  BH.go(w, 'score'); BH.go(w, 'compare'); await settle(); await settle();
  assert.deepEqual(diffs(), [], 'a second draw of the pair asks for nothing');
  BH.go(w, 'score');
  tick(w, V14);
  const del = act(page(w).querySelector('.bench-history .bench-selbar'), 'delete-runs');
  del.click(); w.reply = BH.reply(`conveyor: deleted ${V14}.`); del.click();
  set.hist.runs = set.hist.runs.filter((r) => r.id !== V14);
  await settle(); await settle();
  BH.go(w, 'compare'); await settle(); await settle();
  assert.equal(diffs().length, 1, 'the pair read before the Delete is asked for again');
});

// Bug it guards: a run deleted on the build machine (`bench swe runs delete`, not the Board's Delete) left Compare's
// diffs kept, so a new run under the same results key showed the deleted run's reading. A history read that finds a
// run gone asks again; one that finds every run still there asks for nothing.
test('Compare: a history read with a run gone from the build machine asks for the diff again', async () => {
  const set = BH.study(), w = await opened(set, 'compare');
  const diffs = () => w.posts.splice(0).map((p) => p.body.args).filter((a) => a[0] === 'diff');
  assert.equal(diffs().length, 1, 'Compare asks for its pair once');
  const reread = async (guard) => {
    const d = full();
    Object.assign(d.panels.bench.data.bench, { live: set.live, versions: set.versions });
    Object.assign(d.panels.bench.data, { drift: set.drift, guard });
    next(w, d);
    await settle(); await settle();
  };
  await reread(1);
  assert.deepEqual(diffs(), [], 'a history read with every run still there asks for nothing');
  // A new object, as each read of the server's history is: the Board's kept history must not change with it.
  set.hist = { ...set.hist, runs: set.hist.runs.filter((r) => r.id !== V14) };
  await reread(2);
  assert.equal(diffs().length, 1, `the history read without ${V14} asks for the pair again`);
});

// Bug it guards: Compare kept a diff of a pair that had every reading, and a later run that added a flipped task under the
// same results keys showed that task's reading as "not kept" until a picker changed: the diff read before the run has no
// entry for it. A flipped task no ask of the pair named asks once more; a redraw after that asks for nothing.
test('Compare: a later run that adds a flipped task under keys already read asks for the diff again', async () => {
  const set = BH.study(), w = await opened(set, 'compare'), arms = ['conveyor', 'conveyor-codex-claude'], [NEW, NEW2] = BH.ORDER.slice(50, 52);
  const diffs = () => w.posts.splice(0).map((p) => p.body.args).filter((a) => a[0] === 'diff');
  const flipsTable = () => Array.from(page(w).querySelectorAll('.bench-flips tbody tr'), (r) => [r.dataset.task, text(r.lastElementChild)]);
  const answer = (ids) => BH.reply(JSON.stringify({ flipped: ids.map((task) => ({ task, a: { resolved: true }, b: { resolved: false }, reading: `Read ${task}.` })) }));
  diffs();
  w.reply = answer([BH.TASKS[35], BH.TASKS[36]]);
  const b = act(bp(w), 'cmp-b'); b.value = 'arm:conveyor-codex-claude'; b.dispatchEvent(new w.Event('change'));
  await settle(); await settle();
  assert.equal(diffs().length, 1, 'the picked pair is asked for once');
  assert.deepEqual(flipsTable(), [[BH.TASKS[35], `Read ${BH.TASKS[35]}.`], [BH.TASKS[36], `Read ${BH.TASKS[36]}.`]], 'the pair\'s two flips have their readings');
  // A later run: both arms on one more task, under the same results keys, Conveyor resolving it and Codex builds not
  // (the cells of TASKS[35], which flipped the same way), then a poll that reads it (a new guard stamp makes the tab read
  // the history again).
  const later = async (task, id, guard) => {
    const show = structuredClone(set.shows[STUDY]), src = show.tasks[35];
    const line = { ...show.run, id, n: 1, arms, cols: show.run.cols.filter((c) => arms.includes(c.arm)).map((c) => ({ ...c, done: 1, resolved: c.arm === 'conveyor' ? 1 : 0 })) };
    set.shows[id] = { run: line, tasks: [{ id: task, title: 'A later task', cells: src.cells.filter((c) => arms.includes(c.arm)) }], tail: [] };
    set.hist = { ...set.hist, runs: [line, ...set.hist.runs] };
    const d = full();
    Object.assign(d.panels.bench.data.bench, { live: set.live, versions: set.versions });
    Object.assign(d.panels.bench.data, { drift: set.drift, guard });
    next(w, d);
    await settle(); await settle(); await settle();
  };
  // That ask fails (the Board's time limit): the complete answer read before stays, with no entry for the new task.
  w.reply = { ok: false, status: 504, text: () => Promise.resolve('conveyor: the request took too long') };
  await later(NEW, 'r20261109T180000-6', 1);
  assert.deepEqual(flipsTable().map(([id]) => id).sort(), [BH.TASKS[35], BH.TASKS[36], NEW].sort(), 'the later run\'s task is shown as flipped');
  assert.equal(diffs().length, 1, `the flipped task ${NEW}, not in the diff read before, asks for the pair again`);
  assert.equal(new Map(flipsTable()).get(NEW), 'not kept', 'a failed ask leaves the new task\'s reading missing');
  BH.go(w, 'score'); BH.go(w, 'compare'); await settle(); await settle();
  assert.deepEqual(diffs(), [], 'a failed ask is not asked again on each draw');
  // Bug it guards: a failed ask blocked every later automatic ask of the pair, so a flip a later run added under the same
  // pickers stayed "not kept" too. Its ask fails again, and a redraw after it asks for nothing.
  await later(NEW2, 'r20261109T190000-7', 2);
  assert.ok(new Map(flipsTable()).has(NEW2), `the second later run's task ${NEW2} is shown as flipped`);
  assert.equal(diffs().length, 1, `the flipped task ${NEW2}, which no ask named, asks for the pair again after a failed ask`);
  BH.go(w, 'score'); BH.go(w, 'compare'); await settle(); await settle();
  assert.deepEqual(diffs(), [], 'that failed ask is not asked again on each draw');
  // Bug it guards: the failed ask marked the new task as asked, and the answer read before had every reading, so a picker
  // that came back to the pair asked for nothing and the task stayed "not kept".
  w.reply = answer([]);
  b.value = 'arm:solo'; b.dispatchEvent(new w.Event('change'));
  await settle(); await settle();
  diffs();
  w.reply = answer([BH.TASKS[35], BH.TASKS[36], NEW, NEW2]);
  const b2 = act(bp(w), 'cmp-b'); b2.value = 'arm:conveyor-codex-claude'; b2.dispatchEvent(new w.Event('change'));
  await settle(); await settle();
  assert.equal(diffs().length, 1, `a picker back on the pair asks again: its diff has no entry for ${NEW} or ${NEW2}`);
  assert.equal(new Map(flipsTable()).get(NEW), `Read ${NEW}.`, 'the new answer gives its reading');
  assert.equal(new Map(flipsTable()).get(NEW2), `Read ${NEW2}.`, 'the new answer gives the second task\'s reading');
  BH.go(w, 'score'); BH.go(w, 'compare'); await settle(); await settle();
  assert.deepEqual(diffs(), [], 'a redraw after that asks for nothing');
});

// Bug it guards: the same on Versions. Its newest pair's diff was asked for once while the Board was open, so a later run
// of each version on a task that flipped showed that task's commits as "not kept" for good.
test('Versions: later runs that add a flipped task under keys already read ask for the newest pair\'s diff again', async () => {
  const set = BH.study(), w = await opened(set), NEW = BH.ORDER[50], [V18] = OLDS[0], key = (v) => `conveyor-${v[3].repeat(40)}`;
  const diffs = () => w.posts.splice(0).map((p) => p.body.args).filter((a) => a[0] === 'diff');
  const commits = () => new Map(Array.from(page(w).querySelectorAll('.bench-flips tbody tr'), (r) => [r.dataset.task, text(r.lastElementChild)]));
  const answer = (ids) => BH.reply(JSON.stringify({ flipped: ids.map((task) => ({ task, a: { resolved: false }, b: { resolved: true }, changes: [{ commit: 'abc1234', title: `fixed ${task}` }] })), steps: ['review'] }));
  w.reply = answer([]);
  BH.go(w, 'versions');
  for (let i = 0; i < 30; i += 1) await settle();
  assert.equal(diffs().length, 5, 'each pair of the 6 versions is asked for once');
  // A later run of each version on one more task: v1.8.0 does not resolve it and v1.9.0 does (the cells of TASKS[35], which
  // flipped the same way).
  const later = (from, id, at) => {
    const show = structuredClone(set.shows[from]), line = { ...show.run, id, n: 1, arms: ['conveyor'], started: at, cols: show.run.cols.filter((c) => c.arm === 'conveyor').map((c) => ({ ...c, done: 1, resolved: from === STUDY ? 1 : 0 })) };
    set.shows[id] = { run: line, tasks: [{ id: NEW, title: 'A later task', cells: show.tasks[35].cells.filter((c) => c.arm === 'conveyor') }], tail: [] };
    return line;
  };
  set.hist = { ...set.hist, runs: [later(STUDY, 'r20261109T180000-6', set.hist.runs[0].started), later(OLDS[0][1], 'r20261108T180000-6', set.hist.runs[1].started), ...set.hist.runs] };
  w.reply = answer([NEW]);
  const d = full();
  Object.assign(d.panels.bench.data.bench, { live: set.live, versions: set.versions });
  Object.assign(d.panels.bench.data, { drift: set.drift, guard: 1 });
  next(w, d);
  for (let i = 0; i < 10; i += 1) await settle();
  assert.ok(commits().has(NEW), `the later runs' task ${NEW} is shown as flipped from ${V18}`);
  assert.deepEqual(diffs(), [['diff', key(V18), key('v1.9.0'), '--json']], `the flipped task ${NEW}, not in the diff read before, asks for the newest pair again`);
  assert.equal(commits().get(NEW), `abc1234 fixed ${NEW}`, 'the new answer gives its commits');
  BH.go(w, 'score'); BH.go(w, 'versions'); await settle(); await settle();
  assert.deepEqual(diffs(), [], 'a redraw after that asks for nothing');
});

// Bug it guards: a run that has not ended (its process may still write its results) could be archived or deleted. With a
// run going ticked in the run history, Archive and Delete are off with the reason; ticked with an ended run, one request
// archives both runs.
test('Scoreboard run history: a run going ticked has Archive and Delete off with the reason; two ended runs archive in one request', async () => {
  const v = await opened(BH.live(), 'score');
  tick(v, BH.LIVE);
  const acts = page(v).querySelector('.bench-history .bench-selbar');
  assert.deepEqual(['archive-runs', 'delete-runs'].map((x) => act(acts, x).disabled), [true, true]);
  assert.match(text(acts), new RegExp(`${BH.LIVE} has not ended: stop it first to archive or delete\\.`));
  const w = await opened(BH.study());
  tick(w, OLDS[0][1]); tick(w, STUDY);
  w.reply = BH.reply(`conveyor: archived ${OLDS[0][1]}, ${STUDY}.`);
  act(page(w).querySelector('.bench-history .bench-selbar'), 'archive-runs').click();
  assert.deepEqual(sent(w), [['runs', 'archive', STUDY, OLDS[0][1]]]);
});

// Bug it guards: the run history showed the subtotal of a run only some of whose work could be priced (state "partial")
// or priced from tokens (state "estimate") with a word after the figure; the mockup's Cost cell is the figure alone.
test('Scoreboard run history: the cost of a run priced in part or from tokens is the figure alone', async () => {
  const set = BH.study(), [a, b, c] = [OLDS[0][1], OLDS[1][1], OLDS[2][1]];
  mark(set, { [a]: { cost: { usd: 3.5, state: 'partial' } }, [b]: { cost: { usd: 4.25, state: 'known' } }, [c]: { cost: { usd: 5.75, state: 'estimate' } } });
  const w = await opened(set);
  const cost = (id) => text(page(w).querySelector(`.bench-history tr[data-run="${id}"]`).lastElementChild);
  assert.deepEqual([cost(a), cost(b), cost(c)], ['$3.50', '$4.25', '$5.75']);
});
