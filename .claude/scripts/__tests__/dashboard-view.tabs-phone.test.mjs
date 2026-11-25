// SPDX-License-Identifier: Apache-2.0
// The tab bar at phone width (issue 1206): the seven tabs are wider than a phone, so the list scrolls inside the page
// and each tab keeps its name on one line. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { boot, css, deliver, full, next, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

// Bug (issue 1206): `.tabs-list` was a flex row with no overflow rule, so on a phone it grew past the screen,
// "Benchmarks" ran off the head, the page scrolled sideways and "3D View" wrapped to two lines. jsdom does no layout,
// so the rules are checked by the computed styles of app.css, loaded into the page here.
test('at 390 px the tab list scrolls inside the page, and no tab name wraps or shrinks', () => {
  const w = boot({ width: 390 });
  deliver(w, full());
  const st = w.document.createElement('style'); st.textContent = css; w.document.head.append(st);
  const list = w.document.querySelector('#tabs .tabs-list');
  assert.equal(list.querySelectorAll('.tab').length, 7);
  const l = w.getComputedStyle(list);
  assert.equal(l.overflowX, 'auto', 'the list scrolls sideways inside itself, not the page');
  for (const tab of list.querySelectorAll('.tab')) {
    const t = w.getComputedStyle(tab);
    assert.equal(t.whiteSpace, 'nowrap', `${tab.textContent}: the name stays on one line`);
    assert.match(t.flex, /^(0 0 auto|none)$/, `${tab.textContent}: the tab does not shrink to fit`);
  }
});

// Bug (issue 1206, review): `overflow-x: auto` clips up and down too, so the list cut off the focus ring drawn outside
// a tab, on every screen width. The list keeps room for it (padding), and a margin of the same size keeps its place.
// jsdom does no layout, so the rule is read from the computed styles.
test('the tab list has room for the focus ring round a tab, and keeps its place', () => {
  const w = boot({ width: 390 });
  deliver(w, full());
  const st = w.document.createElement('style'); st.textContent = css; w.document.head.append(st);
  const l = w.getComputedStyle(w.document.querySelector('#tabs .tabs-list'));
  assert.equal(l.padding, '4px', 'room for the 2px ring and its 2px offset on every side');
  assert.equal(l.margin, '-4px', 'the same size taken back, so the tabs do not move');
});

// jsdom lays nothing out: seven tabs 100 px wide in a list `client` px wide, laid out from the list's scrollLeft.
function lay(w, client, scrollWidth = 700) {
  const room = { client, scrollWidth };
  const list = () => w.document.querySelector('#tabs .tabs-list');
  Object.defineProperty(w.HTMLElement.prototype, 'clientWidth', { configurable: true, get() { return this === list() ? room.client : 0; } });
  Object.defineProperty(w.HTMLElement.prototype, 'scrollWidth', { configurable: true, get() { return this === list() ? room.scrollWidth : 0; } });
  w.HTMLElement.prototype.getBoundingClientRect = function () {
    if (this === list()) return { left: 0, right: room.client, top: 0, bottom: 40, width: room.client, height: 40 };
    const i = Array.from(this.parentNode.children).indexOf(this);
    const left = i * 100 - list().scrollLeft;
    return { left, right: left + 100, top: 0, bottom: 40, width: 100, height: 40 };
  };
  return { room, list };
}

// Bug (issue 1206): once the list scrolls, a selected tab off the right edge (Benchmarks) stayed out of sight.
test('the selected tab is scrolled into view in the list, and a refresh with the same tab does not move it', () => {
  const w = boot({ tab: 'bench', width: 390 });
  const { list } = lay(w, 390);
  deliver(w, full());
  next(w, full());
  assert.equal(list().scrollLeft, 210, 'Benchmarks (500 to 600 px) ends at the list\'s right edge (390 px)');
  list().scrollLeft = 0;
  next(w, full());
  assert.equal(list().scrollLeft, 0, 'a refresh with the same tab and room keeps the reader\'s own scroll');
  list().scrollLeft = 210;
  w.document.getElementById('tab-control').click();
  assert.equal(list().scrollLeft, 200, 'a click on Control (200 to 300 px) scrolls to it');
});

// Bug (issue 1206, review): the first scroll ran before the feed added the Overview count, which pushes the selected
// tab right; a later scroll was blocked because the tab had not changed. The tab list keeps the tab in view when its
// width changes, and when the window narrows.
test('the selected tab stays in view when a count widens the list, and when the window narrows', () => {
  const w = boot({ tab: 'bench', width: 390 });
  const { room, list } = lay(w, 390);
  deliver(w, full());
  next(w, full());
  assert.equal(list().scrollLeft, 210);
  // A count appears on Overview (30 px): Benchmarks now ends 30 px further right.
  room.scrollWidth = 630;
  w.HTMLElement.prototype.getBoundingClientRect = ((was) => function () {
    const r = was.call(this);
    return this.classList.contains('tab') ? { ...r, left: r.left + 30, right: r.right + 30 } : r;
  })(w.HTMLElement.prototype.getBoundingClientRect);
  next(w, full());
  assert.equal(list().scrollLeft, 240, 'the list scrolled on by the 30 px the count added');
  // A turned phone: the list is 300 px wide, so the tab (ending at 630 px) is 90 px past its right edge (540 px).
  room.client = 300;
  w.dispatchEvent(new w.Event('resize'));
  assert.equal(list().scrollLeft, 330, 'a resize brings the tab back to the right edge');
});

// Bug (issue 1206, review): scrollIntoView scrolls the document too, so on a wide Board a key to another tab jumped the
// page up. The list is scrolled itself, and only when the tab is out of it.
test('on a wide screen, where all seven tabs fit, changing tab neither scrolls the page nor the list', () => {
  const w = boot({ width: 1440 });
  let into = 0;
  w.HTMLElement.prototype.scrollIntoView = function () { into += 1; };
  const { list } = lay(w, 1440, 1440);
  deliver(w, full());
  w.document.getElementById('tab-bench').click();
  next(w, full());
  assert.equal(into, 0, 'the page is not scrolled');
  assert.equal(list().scrollLeft, 0, 'the list stays where it is');
});
