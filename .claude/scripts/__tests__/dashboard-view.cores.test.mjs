// SPDX-License-Identifier: Apache-2.0
// The Rules tab's "Reserved cores" (issue 196): the machine's reserveCores, shown with the test slots left.
// Shared setup: dashboard-view.helpers.mjs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { boot, deliver, next, full, ruled } from './dashboard-view.helpers.mjs';

// Bugs this guards: the Board did not show which cores card work leaves to the user, nor how many test slots the
// cores left hold; on macOS the setting read as in force where no core can be kept.
test('Rules: Reserved cores names the kept cores and the slots left, or why this machine cannot keep cores', () => {
  const w = boot({ tab: 'rules' });
  const cores = (c) => { const d = full(); if (c) d.panels.rules.data.cores = c; return d; };
  const text = () => ruled(w).querySelector('[data-rule="cores"]').textContent;
  deliver(w, cores({ reserved: [14, 15], slots: 14, unavailable: null }));
  assert.match(text(), /Cores 14, 15 · 14 test slots left/);
  next(w, cores({ reserved: [], slots: 4, unavailable: 'macOS lets no program keep a process off a core' }));
  assert.match(text(), /Not available on this machine: macOS lets no program keep a process off a core/);
  next(w, cores({ reserved: [], slots: 16, unavailable: null }));
  assert.match(text(), /None · 16 test slots/);
  next(w, cores(null));
  assert.match(text(), /needs a newer Conveyor/, 'an engine that does not say');
});
