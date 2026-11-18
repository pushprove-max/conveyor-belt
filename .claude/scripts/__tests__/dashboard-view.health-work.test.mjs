// SPDX-License-Identifier: Apache-2.0
// The Health panel's Work now (#197): what keeps the Conveyor host busy now, read from the page server (GET work) when
// the owner opens it. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { boot, panel, deliver, next, full, settle, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const WORK = { host: 'devbox', groups: [
  { card: 'c20261117T000001-sample-5', issue: 5, project: 'sample', step: 'test', closed: false, cpu: 90, stop: null, processes: [{ pid: 300, cpu: 90, command: 'node --test a.test.js' }] },
  { card: 'c20261117T000002-sample-6', issue: 6, project: 'sample', step: null, closed: true, cpu: 80, stop: 'kill 400 401', processes: [{ pid: 400, cpu: 80, command: 'node leftover.js' }] }],
  other: [{ pid: 500, cpu: 60, command: 'firefox' }, { pid: 501, cpu: 20, command: 'node stray.js' }] };
const view = (w) => panel(w, 'health').querySelector('details.work-now');
const opened = async (w) => { view(w).open = true; view(w).dispatchEvent(new w.Event('toggle')); await settle(); await settle(); };

// Bugs: the Board could not show what slows the machine; the view read the host with every draw of the live feed; a
// leftover of a closed card was not told from a live card's work, nor given the command that stops it; work no card
// owns was left out; the view closed, or lost what it read, when the live feed drew the panel again.
test('Health: Work now reads the host when opened, lists busy work by card and step, marks a closed card\'s leftovers with their stop command, and the work no card owns', async () => {
  const w = boot();
  w.workReply = { ok: true, status: 200, json: () => Promise.resolve(WORK) };
  deliver(w, full());
  assert.ok(view(w) && !view(w).open, 'Work now is there, closed');
  assert.equal(w.workAsks || 0, 0, 'nothing is read before the owner opens it');
  await opened(w);
  assert.equal(w.workAsks, 1, 'opening it reads the host once');
  assert.deepEqual(Array.from(view(w).querySelectorAll('.work-head'), (p) => p.textContent),
    ['Card #5 (sample), test step: 90% of a core', 'Card #6 (sample), closed: left over: 80% of a core', 'No card owns']);
  const left = view(w).querySelector('.work-left');
  assert.equal(left.querySelector('.work-stop code').textContent, 'kill 400 401', 'the leftovers name the command that stops them');
  assert.deepEqual(Array.from(view(w).querySelectorAll('.work-other li'), (li) => li.textContent),
    ['60% of a core  500  firefox', '20% of a core  501  node stray.js']);
  const moved = full();
  moved.panels.health.data.host.error = 'ssh: connection timed out';
  const before = panel(w, 'health').dataset.renders;
  next(w, moved); // the live feed draws the panel again
  assert.notEqual(panel(w, 'health').dataset.renders, before, 'the panel was drawn again');
  assert.ok(view(w).open && view(w).querySelectorAll('.work-group').length === 3, 'a redraw keeps it open with what it read');
  assert.equal(w.workAsks, 1, 'a redraw does not read the host again');
  view(w).querySelector('button').click();
  await settle(); await settle();
  assert.equal(w.workAsks, 2, 'Read again reads the host again');
  w.workReply = { ok: false, status: 502, text: () => Promise.resolve('dashboard: devbox gave no work reading') };
  view(w).querySelector('button').click();
  await settle(); await settle();
  assert.equal(view(w).querySelector('.work-state').textContent, 'The Board could not read the work now: dashboard: devbox gave no work reading',
    'a failed reading says so, and shows no machine as idle');
  assert.equal(view(w).querySelectorAll('.work-group').length, 0);
});
