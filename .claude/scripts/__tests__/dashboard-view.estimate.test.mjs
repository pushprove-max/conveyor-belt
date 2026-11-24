// SPDX-License-Identifier: Apache-2.0
// A cost that holds a step priced as an estimate (#1585: its usage was read in part, or not at all) is shown with `~`
// before the dollars wherever the page shows it, never as exact dollars. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { boot, deliver, next, full, fig, panel, loopP, column, clone, settle, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const text = (el) => el.textContent.replace(/\s+/g, ' ');

// Bug it catches: the head tiles, the machine head, Cost (its figures, card rows and Pick rows), Metrics (its tiles,
// summary, model chart and its tooltip, comparison with the machine's row, card rows and "this run"), Landed (its cards
// and total) and the Belt showed an estimated cost as exact dollars, a head tile whose cost became an estimate with
// its dollars the same kept the exact figure, and "this run" took its mark from the issue's cost, not the run's own.
test('the overview marks an estimated cost with ~ in the head tiles, Cost, Metrics, Landed and the Belt', () => {
  const w = boot();
  deliver(w, full());
  assert.deepEqual(['today', 'week', 'per'].map((k) => fig(w, k)), ['$4.25', '$14.00', '$1.00'], 'no estimate: exact dollars');
  const data = full();
  const c = data.panels.cost.data.cards;
  Object.assign(c, { todayEstimate: 1, weekEstimate: 2, perLandedEstimate: 1 });
  Object.assign(c.perCard[0], { todayEstimate: 1, weekEstimate: 1 });
  c.picks = [{ repo: 'sample', group: 'small docs', model: 'claude-sonnet-5-5', effort: 'medium', cards: 3, landed: 2, usd: 10, firstTry: 1, reviews: 4, open: 1, estimate: 1 },
    { repo: 'sample', group: 'small code', model: 'claude-sonnet-5-5', effort: 'medium', cards: 2, landed: 1, usd: 3, firstTry: 1, reviews: 1, open: 1, estimate: 0 }];
  data.panels.machine.data.todayEstimate = 1;
  data.panels.landed.data.cards[0].estimate = true;
  data.panels.belt.data.cards[0].estimate = true;
  const m = data.panels.metrics.data.cards[0];
  m.metrics = clone(m.metrics);
  m.metrics.estimate = true;
  m.metrics.timeline[1].estimate = 'the tokens it counted, at its model\'s price';
  // Its own run is exact although its issue's cost is an estimate; the other card's run is an estimate, its issue's not.
  const run = { usd: 0.8, tokens: 400000, runSec: 600, buildSec: 200, reviewSec: 400, reviews: 1, fixes: 0, testRuns: 1 };
  Object.assign(m.metrics, { runs: 2, runSec: 1860, thisRun: { ...run, estimate: false } });
  const old = data.panels.metrics.data.cards[1];
  old.metrics = { ...old.metrics, estimate: false, runs: 2, runSec: 1860, thisRun: { ...run, estimate: true } };
  // The week's cost per landed card and its one model's are estimates; today's, the same figures, stay exact.
  const rec = data.panels.metrics.data.records[0];
  rec.week = clone(rec.week);
  rec.week.perLanded.estimate = 1;
  rec.week.perLanded.byModel['claude-sonnet-5-5'].estimate = 1;
  // The machine's cost holds the estimated project's, so it is an estimate too; the other project's stays exact.
  data.panels.metrics.data.compare = { projects: [{ repo: 'sample', landed: 7, leadSec: 7110, usd: 14, usdEstimate: 1 }, { repo: 'other', landed: 1, leadSec: 600, usd: 6, usdEstimate: 0 }],
    machine: { landed: 8, leadSec: 7110, usd: 20, usdEstimate: 1 } };
  next(w, data);
  assert.deepEqual(['today', 'week', 'per'].map((k) => fig(w, k)), ['~$4.25', '~$14.00', '~$1.00'], 'the same dollars, now an estimate: each tile has ~');
  const cost = panel(w, 'cost');
  assert.deepEqual(['today', 'week', 'per'].map((k) => cost.querySelector(`[data-figure="${k}"] .num`).textContent), ['~$4.25', '~$14.00', '~$1.00'], 'Cost\'s three figures');
  const row = (n) => Array.from(cost.querySelectorAll('ul.per-card li.row')).find((li) => li.querySelector('.issue').textContent === `#${n}`);
  assert.match(text(row(63)), /~\$1\.25 today~\$1\.25 in 7 days$/, 'a card row with an estimated step');
  assert.match(text(row(7)), /[^~]\$2\.50 today\$2\.50 in 7 days$/, 'a card row with none stays exact');
  const pick = (g) => cost.querySelector(`table.picks tr[data-group="${g}"]`).cells[4].textContent;
  assert.deepEqual([pick('small docs'), pick('small code')], ['~$5.00', '$3.00'], 'a Pick row with an estimated step, and one with none');
  assert.equal(w.document.querySelector('#machine-head .machine-cost strong').textContent, '~$4.25', 'the machine head\'s cost today');
  assert.match(text(panel(w, 'landed')), /landed .*~\$2\.50/, 'a Landed card with an estimated step');
  assert.match(text(panel(w, 'landed').querySelector('.foot')), /^2 cards, ~\$3\.00 at list prices$/, 'the Landed total, one of its cards estimated');
  assert.match(text(panel(w, 'belt')), /~\$1\.25/, 'a Belt card with an estimated step');
  const mp = panel(w, 'metrics');
  assert.equal(mp.querySelector('[data-tile="cost"] .num').textContent, '~$4.50', 'Metrics\' cost per landed card tile');
  const sum = (label) => Array.from(mp.querySelectorAll('table.metrics-table:not(.metrics-compare) tbody tr')).find((tr) => tr.firstChild.textContent === label);
  assert.deepEqual(Array.from(sum('Per landed card').cells, (td) => td.textContent).slice(1).map((v) => v.split(',')[0]), ['$4.50', '~$4.50'], 'the summary: today exact, the 7 days an estimate');
  assert.match(sum('Per landed card, by model').cells[2].textContent, /~\$3\.00, /, 'the summary\'s model figure for the 7 days');
  const chart = mp.querySelector('[data-chart="models"]');
  assert.equal(chart.querySelector('.tick.value').textContent, '~$3.00', 'the model chart\'s bar');
  assert.match(chart.querySelector('svg').getAttribute('aria-label'), /~\$3\.00/, 'the model chart\'s words for a screen reader');
  assert.match(chart.querySelector('.bar title').textContent, /: ~\$3\.00 a landed card/, 'the model chart\'s tooltip');
  assert.deepEqual(Array.from(mp.querySelectorAll('.metrics-compare tbody tr'), (tr) => tr.lastChild.textContent), ['~$14.00', '$6.00', '~$20.00'],
    'the comparison: the estimated project, the exact one, the machine over both');
  const metrics = text(mp);
  const card = (title) => text(Array.from(mp.querySelectorAll('li.row')).find((li) => li.textContent.includes(title)));
  assert.match(card('Old record'), /this run: ~\$0\.80, /, 'an estimated "this run" of a card whose issue cost is exact');
  assert.match(card('Landed one'), /this run: \$0\.80, /, 'an exact "this run" of a card whose issue cost is an estimate');
  assert.match(metrics, /Landed one.*~\$6\.00/, 'a Metrics card with an estimated step');
  assert.match(metrics, /review: changes asked.*~\$1\.00 \(an estimate: the tokens it counted, at its model's price\)/, 'the estimated step itself, and how it was made');
  assert.match(metrics, /build.*\$2\.00/, 'the exact step');
  assert.doesNotMatch(metrics, /~\$2\.00/, 'the exact step has no ~');
});

// Bug it catches: the Board's Review card, a Landed card, its Today figure and a project's cost today showed an
// estimated cost as exact dollars.
test('the Control tab marks an estimated cost with ~ on the Board and a project\'s cost today', () => {
  const w = boot({ tab: 'control' });
  const data = full();
  data.panels.board.data.review[0].estimate = true;
  data.panels.board.data.landed[0].estimate = true;
  data.panels.board.data.today.estimate = true;
  data.panels.machine.data.projects[0].todayEstimate = 1;
  deliver(w, data);
  assert.match(loopP(w).querySelector('[data-figure="today"]').textContent, /^Today2 landed~\$3\.00$/, 'the Board\'s Today');
  assert.match(text(column(w, 'review')), /review 2 of 3.*~\$1\.25/, 'a Review card');
  assert.match(text(column(w, 'landed')), /2 reviews · ~\$2\.50/, 'a Landed card');
  assert.match(text(column(w, 'landed')), /already fixed/, 'a closed card has no cost line');
  assert.match(text(panel(w, 'machine')), /~\$4\.25 today/, 'a project\'s cost today');
});

// Bug it catches: a Belt 3D card's details showed an estimated cost so far as exact dollars. jsdom runs no WebGL: a
// stand-in scene takes the panel's pick, as dashboard-view.belt3d.test.mjs does with its fuller one.
test('Belt 3D marks an estimated cost so far with ~ in a card\'s details', async () => {
  const w = boot({ tab: 'belt3d', extra: `HTMLCanvasElement.prototype.getContext = function (k) { return /webgl/.test(k) ? {} : null; };
    window.DASH_BELT3D_SCENE = { createScene(o) { window.scene3d = { o, frame() { return true; }, resize() {} }; return window.scene3d; } };` });
  const data = full();
  data.panels.belt3d.data.belt.find((c) => c.card === 'c7-9').estimate = true;
  deliver(w, data);
  await settle();
  const box = panel(w, 'belt3d').querySelector('.b3-detail');
  w.scene3d.o.pick('sample:c7-9');
  assert.match(box.textContent, /Cost so far ~\$0\.50 · /, 'an estimated card');
  w.scene3d.o.pick('sample:c3-63');
  assert.match(box.textContent, /Cost so far \$1\.25 · /, 'a card with none stays exact');
});
