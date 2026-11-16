// SPDX-License-Identifier: Apache-2.0
// The Board on one machine (issue 112): Conveyor runs on the machine the Board runs on, and the host file names no
// build machine (the collector marks it: Health's host.local). Bug caught: every panel told the owner to make sure
// that the build machine was on, and Health said "this project must name its build machine", on an install that has
// none. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { boot, panel, state, deliver, full, cases, OVERVIEW } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const one = () => {
  const data = full();
  data.panels.health.data.host = { name: 'devbox', local: true, reachable: true, error: null };
  return data;
};
const overviewText = (w) => OVERVIEW.map((id) => panel(w, id).textContent).join('\n');

test('One machine: every Overview panel shows its data, Health shows this machine, and no text names a build machine', () => {
  const w = boot();
  deliver(w, one());
  for (const id of OVERVIEW) assert.equal(state(w, id), 'ready', `${id} shows its data`);
  const row = panel(w, 'health').querySelector('dt[data-check="This machine (devbox)"]');
  assert.ok(row, `Health has no row for this machine: ${panel(w, 'health').textContent}`);
  assert.match(row.nextElementSibling.textContent, /Conveyor read/);
  assert.doesNotMatch(overviewText(w), /build machine|Build machine/);
});

test('One machine: a panel the Board cannot read says why on tap and what to do, and names no build machine', () => {
  const w = boot();
  const data = one(), why = 'conveyor/host.json records are not understood: each needs a repo name and the path of its main checkout';
  data.panels.belt = { error: why, data: null };
  Object.assign(data.panels.needs.data, { cards: null, cardsError: why });
  deliver(w, data);
  assert.equal(state(w, 'belt'), 'error');
  const belt = panel(w, 'belt').textContent;
  assert.ok(belt.includes('The Board could not get this panel from Conveyor, so it cannot show it. Press Restart the Board\'s feed in Health. If this continues, the details say what to correct.'), belt);
  assert.equal(panel(w, 'belt').querySelector('.state-detail').dataset.tip, `Details: ${why}`);
  assert.match(panel(w, 'needs').textContent, /The Board could not read the cards, so it shows none\. Press Restart the Board's feed in Health\./);
  assert.doesNotMatch(overviewText(w), /build machine|Build machine/);
});
