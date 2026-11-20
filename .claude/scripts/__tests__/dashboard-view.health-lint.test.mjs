// SPDX-License-Identifier: Apache-2.0
// The Health panel's Lint check row (#261): the landed cards whose last lint line skipped a command for a missing tool
// (the record's unchecked, conveyor/lib/views.sh). Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { boot, panel, deliver, full, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

// Bug: a card that landed with a lint command skipped (its tool missing) landed unchecked, and Health did not say so.
// The row counts them; a record with none shows no row.
test('Health: the cards that landed with a skipped lint command are counted on a Lint check row', () => {
  const at = (n) => {
    const data = full();
    data.panels.health.data.records[0].unchecked = n;
    const w = boot({ list: ['health'] });
    deliver(w, data);
    return panel(w, 'health').querySelector('dt[data-check="Lint check"]');
  };
  const row = at(2);
  assert.ok(row, 'two unchecked cards show the row');
  assert.equal(row.nextElementSibling.querySelector(':scope > .chip').textContent, '2 unchecked');
  assert.match(row.nextElementSibling.textContent, /2 cards landed with a lint command skipped for a missing tool/);
  assert.equal(at(0), null, 'no card landed unchecked: no row');
});
