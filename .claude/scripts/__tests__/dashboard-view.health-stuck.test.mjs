// SPDX-License-Identifier: Apache-2.0
// The Health panel's Stuck cards row: its next step says what to do for each stuck card (issue 1430). Shared setup:
// dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { boot, panel, deliver, full, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const next = (w) => panel(w, 'health').querySelector('dt[data-check="Stuck cards"]').nextElementSibling.querySelector('.check-next').textContent;

// Bug it guards: health lists a card at once when its engine (or its own process) is stopped by a signal, but the row
// said Conveyor stops the session and retries it by itself; nothing retries a stopped process, it needs a SIGCONT.
// Also: the command named the engine's pid alone, and left the stopped wrapper under it (engineStopped.pids, 4322)
// holding the card.
test('Health: a card stuck because its engine is stopped by a signal says so and names the SIGCONT, not a retry', () => {
  const w = boot({ list: ['health'] }), data = full();
  data.panels.health.data.records[0].engineStopped = { pid: 4321, since: '2026-11-09T16:55:00Z', pids: [4321, 4322, 4400] };
  data.panels.health.data.records[0].stuck = [
    { card: 'c1-12', issue: 12, step: 'build', since: '2026-11-09T16:50:00Z', stopped: { pid: 4321, of: 'engine', since: '2026-11-09T16:55:00Z', own: { pid: 4400, since: '2026-11-09T16:55:00Z', pids: [4400, 4401] } } },
    { card: 'c2-13', issue: 13, step: 'review', since: '2026-11-09T16:40:00Z' }];
  deliver(w, data);
  const said = next(w);
  assert.match(said, /#12: Conveyor's engine is stopped by a signal, and nothing retries it\. Send it SIGCONT: kill -CONT 4321 4322 4400 4401\./, said);
  assert.match(said, /tries it again by itself/, 'the card stuck for another reason keeps the retry sentence');
});
