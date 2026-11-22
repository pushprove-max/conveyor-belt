// SPDX-License-Identifier: Apache-2.0
// The Benchmarks tab's Plan a run, what its other files do not cover (issue 1430): the history read again when the
// control record's guard changes, and Start keeping the keyboard focus through its answer. Shared setup:
// dashboard-view.helpers.mjs (BH).
import assert from 'node:assert/strict';
import { boot, settle, act, next, full, cases, BH } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const { bp, page } = BH;
const text = (el) => el.textContent.replace(/\s+/g, ' ').trim();
const kv = (el) => Array.from(el.querySelectorAll('dt'), (d) => [d.textContent, text(d.nextElementSibling)]);
async function opened(set) {
  const w = boot({ tab: 'bench' });
  BH.open(w, set);
  await settle(); await settle();
  BH.go(w, 'plan'); await settle(); await settle();
  return w;
}
const histAsks = (w) => w.benchAsks.filter((u) => !/&run=/.test(u)).length;

// Bug it guards: the history was read again only when the run in progress moved, so `conveyor.sh control guard off` or
// `guard 1` (no run moved) left Plan's guard chip on the old history.
test('Plan a run, a snapshot whose control guard changed and no run moved: the history is read again and the chip follows it', async () => {
  const set = BH.study(), w = await opened(set);
  const guard = () => kv(page(w).querySelector('.bench-before')).find(([k]) => k === 'Usage guard')[1];
  assert.equal(guard(), 'not kept', 'the history keeps no share of the week left');
  const asked = histAsks(w);
  set.hist.guard = { conveyor: true, agent: true };
  const d = full();
  Object.assign(d.panels.bench.data.bench, { live: set.live, versions: set.versions });
  d.panels.bench.data.drift = set.drift;
  d.panels.bench.data.guard = 1;
  next(w, d);
  await settle(); await settle();
  assert.equal(histAsks(w), asked + 1, 'a new guard reads the history again');
  assert.equal(guard(), 'would reach the guard; the run stops there');
});

// Bug it guards: Start is off while its answer is out (K.B.busy), so the redraw could not give it the focus back and the
// focus fell to the page's body; the answer's redraw then found no control to focus.
test('Plan a run, Start pressed from the keyboard: after the answer the focus is on Start again', async () => {
  const w = await opened(BH.few());
  w.reply = BH.reply('conveyor: started r20261109T160000-1');
  const start = act(bp(w), 'start');
  start.focus();
  start.click();
  assert.equal(act(bp(w), 'start').disabled, true, 'Start is off while the answer is out');
  await settle(); await settle();
  const now = act(bp(w), 'start');
  assert.equal(now.disabled, false, 'Start is on again');
  assert.equal(w.document.activeElement, now, `the focus is on Start, not ${w.document.activeElement.tagName}`);
});
