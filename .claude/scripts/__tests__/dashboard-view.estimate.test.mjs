// SPDX-License-Identifier: Apache-2.0
// A cost that holds a step priced as an estimate (#1585: its usage was read in part, or not at all) is shown with `~`
// before the dollars wherever the page shows it, never as exact dollars. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { boot, deliver, next, full, fig, panel, loopP, column, clone, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const text = (el) => el.textContent.replace(/\s+/g, ' ');

// Bug it catches: the head tiles, Cost, Metrics, Landed and the Belt showed an estimated cost as exact dollars, and a
// head tile whose cost became an estimate with its dollars the same kept the exact figure.
test('the overview marks an estimated cost with ~ in the head tiles, Cost, Metrics, Landed and the Belt', () => {
  const w = boot();
  deliver(w, full());
  assert.deepEqual(['today', 'week', 'per'].map((k) => fig(w, k)), ['$4.25', '$14.00', '$1.00'], 'no estimate: exact dollars');
  const data = full();
  const c = data.panels.cost.data.cards;
  Object.assign(c, { todayEstimate: 1, weekEstimate: 2, perLandedEstimate: 1 });
  Object.assign(c.perCard[0], { todayEstimate: 1, weekEstimate: 1 });
  data.panels.landed.data.cards[0].estimate = true;
  data.panels.belt.data.cards[0].estimate = true;
  const m = data.panels.metrics.data.cards[0];
  m.metrics = clone(m.metrics);
  m.metrics.estimate = true;
  m.metrics.timeline[1].estimate = 'the tokens it counted, at its model\'s price';
  next(w, data);
  assert.deepEqual(['today', 'week', 'per'].map((k) => fig(w, k)), ['~$4.25', '~$14.00', '~$1.00'], 'the same dollars, now an estimate: each tile has ~');
  const cost = panel(w, 'cost');
  assert.deepEqual(['today', 'week', 'per'].map((k) => cost.querySelector(`[data-figure="${k}"] .num`).textContent), ['~$4.25', '~$14.00', '~$1.00'], 'Cost\'s three figures');
  const row = (n) => Array.from(cost.querySelectorAll('ul.per-card li.row')).find((li) => li.querySelector('.issue').textContent === `#${n}`);
  assert.match(text(row(63)), /~\$1\.25 today~\$1\.25 in 7 days$/, 'a card row with an estimated step');
  assert.match(text(row(7)), /[^~]\$2\.50 today\$2\.50 in 7 days$/, 'a card row with none stays exact');
  assert.match(text(panel(w, 'landed')), /landed .*~\$2\.50/, 'a Landed card with an estimated step');
  assert.match(text(panel(w, 'belt')), /~\$1\.25/, 'a Belt card with an estimated step');
  const metrics = text(panel(w, 'metrics'));
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
