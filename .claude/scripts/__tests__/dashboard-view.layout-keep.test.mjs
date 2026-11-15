// SPDX-License-Identifier: Apache-2.0
// The dashboard page's panels keep their columns across a refresh (issue 558): any change in a panel's height packed
// the whole grid again, so the panel being read could move to another column. The panels are placed anew only when
// the owner changes the layout or the column count changes. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { boot, deliver, next, full, panel, OVERVIEW, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

// jsdom lays nothing out: each panel is given its height by hand, w.heights[id] (200 px when not named).
function page(heights, width = 1440) {
  const w = boot({ width });
  w.heights = heights;
  const real = w.Element.prototype.getBoundingClientRect;
  w.Element.prototype.getBoundingClientRect = function () {
    if (!this.classList.contains('panel') || !this.dataset.panel) return real.call(this);
    const h = w.heights[this.dataset.panel] || 200;
    return { left: 0, top: 0, right: 300, bottom: h, width: 300, height: h };
  };
  deliver(w, full());
  return w;
}
const columnsOf = (w) => Object.fromEntries(OVERVIEW.map((id) => [id, panel(w, id).dataset.col]));
const frames = (w) => { while (w.frames.length) w.frames.shift()(); };
// The Queue, in the right column, grown so tall that a fresh packing puts the panels under it in the left columns.
const TALL = { queue: 1500 };

test('a refresh where one panel grows taller keeps every panel in the column it had', () => {
  const w = page({});
  const before = columnsOf(w);
  assert.deepEqual([before.queue, before.release, before.health, before.lanes], ['2', '2', '2', '2'], 'the four start in the right column');
  w.heights = TALL;
  next(w, full());
  frames(w);
  assert.deepEqual(columnsOf(w), before, 'no panel moved to another column');
});

test('moving a panel places the panels again', () => {
  const w = page({});
  w.heights = TALL;
  next(w, full());
  frames(w);
  panel(w, 'metrics').querySelector('.move-up').click();
  frames(w);
  // The same layout drawn fresh at the new heights: the panels are where a first placing puts them.
  const fresh = page(TALL);
  panel(fresh, 'metrics').querySelector('.move-up').click();
  frames(fresh);
  assert.deepEqual(columnsOf(w), columnsOf(fresh));
  assert.notEqual(columnsOf(w).health, '2', 'Health left the right column, beside the tall Queue');
});

test('a change in column count places the panels again', () => {
  const w = page({});
  w.heights = TALL;
  next(w, full());
  frames(w);
  // The window narrows to two columns.
  w.matchMedia = (q) => { const max = /max-width: (\d+)px/.exec(q); return { matches: max !== null && 900 <= Number(max[1]), addEventListener() {} }; };
  w.dispatchEvent(new w.Event('resize'));
  frames(w);
  assert.equal(w.document.getElementById('grid').dataset.cols, '2');
  assert.deepEqual(columnsOf(w), columnsOf(page(TALL, 900)), 'as a page first drawn at two columns places them');
});
