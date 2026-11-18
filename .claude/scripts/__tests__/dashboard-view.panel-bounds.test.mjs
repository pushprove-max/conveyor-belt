// SPDX-License-Identifier: Apache-2.0
// A panel's content stays inside its own panel: a row is never wider than the panel, and a panel's grid rows cover
// what it draws. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { P, boot, css, deliver, full, panel, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

// Bug (issue 496): at Small, the rows under "Waiting on another card (11)" were drawn about 1.4 times the Queue's width,
// over the panel in the next column: `.rows` is a grid with no column template, and its implicit auto column grows to
// the widest row's unwrapped content (the "Waiting on #N" chip does not wrap). jsdom does no layout, so the widths are
// checked by the computed styles of app.css, loaded into the page here.
test('at Small, 11 waiting rows with long titles and chips shrink to the Queue panel, and their titles and chips wrap', () => {
  const w = boot();
  const d = full();
  const long = 'A very long issue title that names a panel, a setting, a file path and the bug it fixes in many words';
  d.panels.queue.data = {
    next: [], held: 0, awaitingDeploy: [], issuesError: null, byRepo: { sample: { held: 0 } },
    waiting: Array.from({ length: 11 }, (_, i) => ({ repo: 'sample', card: null, issue: 100 + i, title: `${long} (${i})`, url: `${P}/${100 + i}`,
      waitsFor: [7, 8, 9, 10, 11, 12], waitsOn: [7, 8, 9, 10, 11, 12].map((n) => ({ issue: n, state: 'blocked by the owner' })), forced: false })),
  };
  deliver(w, d);
  const st = w.document.createElement('style'); st.textContent = css; w.document.head.append(st);
  const q = panel(w, 'queue');
  assert.equal(q.dataset.size, 'small');
  const lists = Array.from(q.querySelectorAll('.panel-body ul.rows'));
  assert.equal(lists.length, 1);
  assert.equal(w.getComputedStyle(lists[0]).gridTemplateColumns, 'minmax(0, 1fr)', 'the list\'s one column is no wider than the list');
  const rows = Array.from(lists[0].children);
  assert.equal(rows.length, 11);
  const zero = (v) => /^0(px)?$/.test(v);
  for (const row of rows) {
    const r = w.getComputedStyle(row);
    assert.ok(['', 'auto'].includes(r.width), `no fixed width: ${r.width}`);
    assert.ok(!/content/.test(`${r.width} ${r.minWidth}`), 'no max-content or min-content width');
    assert.ok(zero(r.minWidth), `the row shrinks to its list: min-width ${r.minWidth}`);
    for (const part of row.querySelectorAll('.row-main > *, .row-meta > *')) {
      assert.ok(zero(w.getComputedStyle(part).minWidth), `${part.className} shrinks inside its flex line`);
    }
    for (const flex of row.querySelectorAll('.row-main, .row-meta')) assert.equal(w.getComputedStyle(flex).flexWrap, 'wrap');
    assert.equal(w.getComputedStyle(row.querySelector('.title')).overflowWrap, 'anywhere', 'the title wraps');
    const chip = row.querySelector('.chip'), c = w.getComputedStyle(chip);
    assert.match(chip.textContent, /^Waiting on #7 \(blocked by the owner\), /);
    assert.equal(c.whiteSpace, 'normal', 'the chip wraps');
    assert.equal(c.overflowWrap, 'anywhere');
    assert.equal(c.maxWidth, '100%');
    for (const part of chip.children) assert.ok(zero(w.getComputedStyle(part).minWidth), 'the chip\'s text shrinks inside it');
  }
});

// Bug (issue 496): the Release body was drawn lower than its panel's grid rows, over the heads of Health and Lanes
// under it: arrange() gave a panel the rows of its own box only, never of a body drawn past that box.
test('arrange() gives a panel whose body reaches past its box grid rows to its body\'s end, and the next panel in its column starts below', () => {
  const w = boot();
  let end = 150;  // where the Release body ends, from the panel's top: inside its 200 px box first, then far past it
  const real = w.Element.prototype.getBoundingClientRect;
  // Every other panel is 300 px tall, so that the columns fill and a panel is placed under Release.
  w.Element.prototype.getBoundingClientRect = function () {
    const rel = w.document.getElementById('panel-release');
    if (this === rel) return { left: 0, right: 300, width: 300, top: 0, bottom: 200, height: 200 };
    if (rel && this === rel.querySelector('.panel-body')) return { left: 0, right: 300, width: 300, top: 60, bottom: end, height: end - 60 };
    if (this.matches('.panel')) return { left: 0, right: 300, width: 300, top: 0, bottom: 300, height: 300 };
    return real.call(this);
  };
  deliver(w, full());
  while (w.frames.length) w.frames.shift()();
  const rel = panel(w, 'release'), span = () => Number(rel.dataset.span);
  assert.equal(span(), Math.ceil((200 + 16) / 8), 'first: the rows of its box');
  end = 900;
  w.dispatchEvent(new w.Event('resize'));
  while (w.frames.length) w.frames.shift()();
  assert.ok(span() * 8 - 16 >= 900, `its rows (${span()}) cover the body's 900 px`);
  assert.match(rel.style.gridRow, new RegExp(`^${Number(rel.dataset.row) + 1} / span ${span()}$`));
  const col = rel.dataset.col, row = Number(rel.dataset.row);
  const under = Array.from(w.document.querySelectorAll('.panel[data-col]')).filter((p) => p !== rel && !p.hidden && p.dataset.col === col && Number(p.dataset.row) > row);
  assert.ok(under.length, 'a panel is under Release in its column');
  for (const p of under) assert.ok(Number(p.dataset.row) >= row + span(), `${p.id} starts below Release's rows`);
});
