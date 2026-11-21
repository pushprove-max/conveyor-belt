// SPDX-License-Identifier: Apache-2.0
// The Benchmarks tab against the owner's approved mockup, the texts and the extras taken out (#1216, slice 1 of #1215):
// on each page, the texts the Board words as the mockup does, with the fixture's figures where the mockup's are made up,
// and the items the mockup does not have gone: the edge-state sentences (a figure not kept says "not kept" in the
// mockup's place), the run tools of Compare, and the Task page's extras (the short Scoreboard keeps its folded run history, so Archive,
// Restore and Delete stay on the Board). The tests use jsdom only. The
// action buttons of the Task page and docs/board.md are the next slice. Shared setup: dashboard-view.helpers.mjs (BH).
import assert from 'node:assert/strict';
import { boot, settle, act, cases, BH } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const { bp, page } = BH;
const text = (el) => el.textContent.replace(/\s+/g, ' ').trim();
const q = (w, s) => page(w).querySelector(s);
const kv = (el) => Array.from(el.querySelectorAll('dt'), (d) => [d.textContent, text(d.nextElementSibling)]);
const box = (w, title) => Array.from(page(w).querySelectorAll('.bench-box')).find((b) => b.querySelector('.bench-h') && b.querySelector('.bench-h').firstChild.textContent.trim() === title);
const notes = (w) => Array.from(page(w).querySelectorAll('.bench-note'), text);
async function opened(set, p) {
  const w = boot({ tab: 'bench' });
  BH.open(w, set);
  await settle(); await settle();
  if (p) { BH.go(w, p); await settle(); await settle(); }
  return w;
}

// Bug it guards: the value chart's cost ticks read "$0.00, $0.71, ..." where the mockup reads "$0, $0.5, $1"; a card
// whose arm kept no grade said so in a note of its own under Hidden tests and Patch quality, where the mockup has none
// (each Not kept cell already says it).
test('Scoreboard, 7 arms on 50 tasks, one arm with results that kept no grade: the chart ticks are the mockup\'s and no note says the results were kept before the grade', async () => {
  const set = BH.study();
  set.shows[BH.STUDY].tasks.flatMap((t) => t.cells).filter((c) => c.arm === 'solo').forEach((c) => Object.assign(c, { class: null, tests: null, ref: null, measures: null }));
  const w = await opened(set);
  const labels = Array.from(box(w, 'Value: resolve rate against cost').querySelectorAll('svg text')).filter((t) => text(t).startsWith('$'));
  const ticks = labels.map(text);
  assert.equal(ticks.length, 5);
  // Each label sits at its price's place on the axis: 5 ticks across the plot (x from 40 to 408 in a 420 wide chart), 92 apart.
  assert.deepEqual(labels.map((t) => Number(t.getAttribute('x'))), [0, 1, 2, 3, 4].map((i) => 40 + i * 92), `the tick labels sit at equal steps along the axis: ${labels.map((t) => t.getAttribute('x')).join(' ')}`);
  // Each label is its tick's exact price: the 4 steps are equal and a round size (1, 2, 2.5 or 5 times a power of ten),
  // so no tick sits at $0.552 under a "$0.6" label (the bug of rounding any tick position to one decimal place).
  const v = ticks.map((t) => Number(t.slice(1))), step = v[1];
  assert.ok(ticks[0] === '$0' && v.every((x, i) => Math.abs(x - step * i) < 1e-9), `the cost ticks are equal steps: ${ticks.join(' ')}`);
  assert.ok([1, 2, 2.5, 5].some((m) => Math.abs(Math.log10(step / m) % 1) < 1e-9), `the step ${step} is a round size`);
  const costs = Array.from(box(w, 'Value: resolve rate against cost').querySelectorAll('title'), (t) => text(t).match(/\$([\d.]+) a task/)).map((m) => Number(m[1]));
  assert.ok(v[4] >= Math.max(...costs) - 0.005, `the axis ends at ${v[4]}, past the dearest arm ${Math.max(...costs)}`);
  // Labels and positions tie to each other through the points: read through the axis (the label price at the point's x),
  // each point's x must give the cost its own title states, so a label that is off by a factor (every label halved, with
  // the positions right) fails here.
  box(w, 'Value: resolve rate against cost').querySelectorAll('g.bench-pt').forEach((g) => {
    const stated = Number(text(g.querySelector('title')).match(/\$([\d.]+) a task/)[1]);
    const read = (Number(g.querySelector('circle').getAttribute('cx')) - 40) / 368 * v[4];
    assert.ok(Math.abs(read - stated) <= 0.006, `${g.dataset.arm}: its title says $${stated} a task, the axis (${ticks.join(' ')}) reads $${read.toFixed(3)} at its place`);
  });
  assert.ok(!notes(w).some((n) => /kept before the grade/.test(n)) && !text(page(w)).includes('kept before the grade'), 'no note on results kept before the grade');
  assert.ok(text(box(w, 'Hidden tests')).includes('not kept'), 'the arm\'s cells say not kept');
});

// Bug it guards: the few-task Scoreboard's patch note named no test file where the mockup says "only Conveyor added a test
// (7 lines in <the test file>)".
test('Scoreboard, 2 runs of 1 task, one arm adding a test: the patch note names its test file', async () => {
  const set = BH.few();
  set.shows[BH.FEW2].tasks[0].cells[0].patch = [{ path: 'django/db/models/fields/reverse_related.py', added: 1, removed: 1 }];
  const w = await opened(set);
  assert.ok(notes(w).includes('Real, from the patches the results keep. All five changed the same file by one line; only Conveyor, Codex builds v1.7.0 added a test (7 lines in tests/model_fields/test_manytomanyfield.py).'), notes(w).join(' | '));
});

// Bug it guards: with the history taken off the page of fewer than 3 shared tasks, Archive, Restore and Delete were
// nowhere on the Board for such runs (Live run and Compare have no run tools). The page keeps the history, folded.
test('Scoreboard, 2 runs of 1 task: the run history is folded at the foot, and Archive of a run ticked sends its request', async () => {
  const w = await opened(BH.few());
  const fold = q(w, 'details.bench-history'), id = BH.few().hist.runs[0].id;
  assert.ok(fold && !fold.open, 'the few page has a folded run history');
  const pick = act(bp(w), `pick-${id}`); pick.checked = true; pick.dispatchEvent(new w.Event('change'));
  w.reply = BH.reply(`conveyor: archived ${id}.`);
  act(q(w, '.bench-selbar'), 'archive-runs').click();
  assert.deepEqual(w.posts.map((p) => p.body.args).filter((a) => a[0] === 'runs'), [['runs', 'archive', id]]);
});

test('Scoreboard, 2 runs of 1 task, no Conveyor arm ran: the stat of its cost is not there', async () => {
  const set = BH.few(), [l1] = set.hist.runs;
  const gone = 'conveyor-codex-claude';
  set.hist.runs = [l1];
  Object.assign(l1, { arms: l1.arms.filter((a) => a !== gone), cols: l1.cols.filter((c) => c.arm !== gone) });
  set.shows[BH.FEW1].tasks[0].cells = set.shows[BH.FEW1].tasks[0].cells.filter((c) => c.arm !== gone);
  const w = await opened(set);
  assert.deepEqual(Array.from(page(w).querySelectorAll('.bench-stat'), (s) => text(s.children[1])), ['Runs', 'Tasks with a result', 'Arms checked and ready']);
  assert.ok(!text(page(w)).includes('no Conveyor arm ran'));
});

// Bug it guards: Compare kept a row of run tools (Archive and Delete of the runs of the two sides) and, for 2 runs of 1
// task with a flipped task, a sentence about the table of the full page, neither of which the mockup has.
test('Compare, 2 runs of 1 task with a flipped task: no run tools and no sentence about the full page', async () => {
  const set = BH.few();
  Object.assign(set.shows[BH.FEW1].tasks[0].cells[3], { resolved: false, result: 'unresolved' });
  const w = await opened(set, 'compare');
  const s = act(bp(w), 'cmp-b'); s.value = 'arm:solo'; s.dispatchEvent(new w.Event('change'));
  await settle(); await settle();
  assert.match(text(q(w, '.bench-vv')), /^On 1 task: Conveyor v1\.7\.0 resolved 1, Claude alone 0\.$/);
  assert.ok(!/table of the full page|There is no flipped task/.test(text(q(w, '.bench-vw'))), text(q(w, '.bench-vw')));
  assert.equal(q(w, '.bench-runacts'), null, 'no run tools');
  assert.ok(!text(page(w)).includes('These runs:'));
});

// Bug it guards: the Live run page kept a Stop for a run that is not going and a row of run tools, and worded its
// "Score so far" subtitle "graded" where the mockup says "finished".
test('Live run, 7 arms on 50 tasks going: the Score so far subtitle says finished, and there are no run tools', async () => {
  const w = await opened(BH.live());
  assert.equal(text(box(w, 'Score so far').querySelector('.bench-hsub')), 'Tasks that every arm finished.');
  assert.equal(q(w, '.bench-runacts'), null, 'no run tools');
  assert.equal(act(bp(w), 'stop-run').textContent, 'Stop the run', 'the run going keeps its Stop');
});

// Bug it guards: with no run at all the Live run page said "No run has started yet. Plan a run: it shows here while it
// goes", a sentence the mockup does not have; a figure the page cannot give says "not kept" in its place.
test('Live run, no run: the verdict says not kept in the place of the last run', async () => {
  const set = BH.few();
  set.hist.runs = [];
  const w = await opened(set, 'run');
  assert.deepEqual([text(q(w, '.bench-vk')), text(q(w, '.bench-vv')), q(w, '.bench-vw')], ['No run goes now', 'not kept', null]);
});

// Bug it guards: the Task page showed the "reached the time limit" and "did not fire" notes, a Hidden tests fact beside the
// size and image, and, with no card steps or no review kept, a sentence of its own, where the mockup's Note column says only
// where Conveyor went wrong, and its card and review show "not kept" when the results do not keep them.
test('Task, 7 arms on one task: the Note column says only where a Conveyor arm went wrong, and the card and review say not kept when they are not', async () => {
  const set = BH.study();
  const cells = set.shows[BH.STUDY].tasks[0].cells;
  Object.assign(cells.find((c) => c.arm === 'superpowers'), { timedOut: true, fired: false, why: 'it did not fire: its output shows no use of its method' });
  const conv = cells.find((c) => c.arm === 'conveyor');
  conv.steps = conv.steps.filter((s) => s.step !== 'review');
  const w = await opened(set, 'task');
  const arm = (label) => Array.from(q(w, '.bench-arms').querySelectorAll('tbody tr')).map((r) => Array.from(r.children, text)).find((r) => r[0].startsWith(label));
  assert.equal(arm('Claude + Superpowers')[4], '', 'no "reached the time limit" and no "did not fire" note');
  assert.deepEqual(kv(box(w, 'This task over time')).map(([k]) => k), ['Repository', 'Difficulty', 'Patch size', 'Task image']);
  assert.deepEqual(Array.from(q(w, 'details[data-fold^="review-"]').querySelectorAll('p'), text), ['not kept'], 'no review kept');
  cells.filter((c) => /^conveyor/.test(c.arm)).forEach((c) => { c.steps = []; });
  act(bp(w), 'page-compare').click(); act(bp(w), 'page-task').click();
  await settle();
  const head = Array.from(page(w).querySelectorAll('h3')).find((h) => text(h) === 'Conveyor\'s card, step by step');
  assert.equal(text(head.nextElementSibling), 'not kept', 'no card steps kept');
  assert.ok(!/The card's steps are not kept|No review is kept|No Conveyor arm ran/.test(text(page(w))));
});

// Bug it guards: a task no run of the Conveyor arm has said "No run of the Conveyor arm has this task." in the place of the
// dots, a sentence the mockup does not have.
test('Task, a task no Conveyor run has: the dots say not kept', async () => {
  const set = BH.study();
  set.hist.runs = set.hist.runs.map((r) => ({ ...r, cols: r.cols.map((c) => (c.arm === 'conveyor' ? { ...c, arm: 'conveyor-x', kind: 'agent' } : c)) }));
  const w = await opened(set, 'task');
  assert.equal(text(q(w, '.bench-dots')), 'not kept');
  assert.ok(!text(page(w)).includes('No run of the Conveyor arm has this task'));
});

// Bug it guards: with no drift watch read, Versions drew a box with a sentence about running the command; the mockup's box
// has its title and says not kept where its figures would be. A group of cards too small to judge had a note of its own.
test('Versions, 6 versions with no drift read: the drift box says not kept, and no sentence about running the command', async () => {
  const set = BH.study();
  set.drift = null;
  const w = await opened(set, 'versions');
  const b = box(w, 'Drift watch: the belt\'s own cards');
  assert.equal(text(b.querySelector('.bench-hsub')), 'not kept');
  assert.ok(!text(page(w)).includes('conveyor.sh bench drift on the build machine.') && !text(page(w)).includes('A group of fewer than 5 cards'));
});

// Bug it guards: Plan a run's arm table showed the engine's reason under the state chip and states the mockup does not
// have, and the "Too small" text kept "in the last study" where the mockup says the points without it.
test('Plan a run, 50 tasks of one arm changed with a reason: no reason under the chip; 10 tasks say Too small in the mockup\'s words', async () => {
  const set = BH.study();
  set.hist.arms.find((a) => a.state === 'changed').why = 'its file changed since its check';
  const w = await opened(set, 'plan');
  assert.deepEqual(Array.from(q(w, '.bench-planarms').querySelectorAll('tbody tr'), (r) => text(r.children[2])).slice(0, 7), ['ready', 'ready', 'ready', 'ready', 'expired', 'ready', 'changed']);
  assert.equal(q(w, '.bench-tie'), null, 'no reason line');
  assert.ok(!text(q(w, '.bench-planarms')).includes('its file changed'));
  const range = act(bp(w), 'plan-n');
  range.value = '10'; range.dispatchEvent(new w.Event('input'));
  assert.equal(text(q(w, '.bench-before .bench-callout')), 'Too small: only a gap of 50% or more shows. Conveyor against Claude alone was 24 points. Try 50 tasks or more.');
});
