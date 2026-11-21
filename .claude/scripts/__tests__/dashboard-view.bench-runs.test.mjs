// SPDX-License-Identifier: Apache-2.0
// The Benchmarks tab's Archive, Restore and Delete of runs (#1053), in their places on the rebuilt tab (#1177): the
// Scoreboard's run history (folded at its foot of the page, for any number of shared tasks). Each sends `bench swe runs archive |
// restore | delete <id>...`; an archived run leaves the figures and stays in the run history, marked; Delete takes one
// confirm that names the runs; a run that has not ended has both off. Shared setup: dashboard-view.helpers.mjs (BH).
import assert from 'node:assert/strict';
import { boot, settle, act, cases, BH } from './dashboard-view.helpers.mjs';

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
  w.reply = BH.reply(`conveyor: deleted ${a}, ${b}; 1 result stays: another run shows it.`);
  del.click();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [['runs', 'delete', a, b]], 'one request deletes both');
  set.hist.runs = set.hist.runs.filter((r) => r.id !== a && r.id !== b);
  await settle(); await settle();
  assert.equal(text(page(w).querySelector('.bench-history .bench-said')), `Deleted ${a}, ${b}; 1 result stays: another run shows it.`);
  assert.deepEqual(Array.from(page(w).querySelectorAll('.bench-history tbody tr'), (r) => r.dataset.run), [STUDY, ...OLDS.slice(0, 3).map(([, id]) => id), BH.ARCHIVED]);
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
