// SPDX-License-Identifier: Apache-2.0
// The work a refresh does, counted (#562): a read of the layout after a write lays the page out again, and a scroll
// over a page laid out many times each second stutters. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { boot, deliver, next, full, settle, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

// Keeps, in order, each read of a panel's box (['read', panel id]) and each write of a panel's place or height
// (['write', property]) the page makes.
function watchLayout(w) {
  const log = [];
  const rect = w.Element.prototype.getBoundingClientRect;
  w.Element.prototype.getBoundingClientRect = function () {
    if (this.classList.contains('panel')) log.push(['read', this.id]);
    return rect.call(this);
  };
  // The prototype an element's style has, which holds these properties (CSSStyleProperties from jsdom 31 on).
  const S = Object.getPrototypeOf(w.document.body.style);
  for (const k of ['gridRow', 'gridColumn', 'minHeight', 'maxHeight']) {
    const d = Object.getOwnPropertyDescriptor(S, k);
    Object.defineProperty(S, k, { ...d, set(v) { log.push(['write', k]); d.set.call(this, v); } });
  }
  return log;
}

// Bug it catches: the grid wrote one panel's size and read the next one's height, one panel at a time, so the browser
// laid out the page once a panel at each refresh.
test('a grid layout round reads every panel\'s height before it writes any panel\'s place or height', () => {
  const w = boot();
  const data = full();
  deliver(w, data);
  const log = watchLayout(w);
  data.panels.needs.data.cards.blocked[0].reason = 'tests failed three times';
  next(w, data);
  for (const f of w.frames.splice(0)) f();
  const shown = Array.from(w.document.querySelectorAll('.panel'), (p) => p.id).filter((id) => !w.document.getElementById(id).hidden);
  // Each run of panel reads with no write between them: one round reads all the panels in one run.
  const runs = [];
  log.forEach(([kind, id], i) => {
    if (kind !== 'read') return;
    if (i > 0 && log[i - 1][0] === 'read') runs[runs.length - 1].push(id); else runs.push([id]);
  });
  assert.ok(runs.length > 0, 'the refresh laid the grid out');
  for (const run of runs) assert.deepEqual(run.slice().sort(), shown.slice().sort(), 'every shown panel is read in one run, with no write between two reads');
  const lastRead = log.map((x) => x[0]).lastIndexOf('read');
  assert.ok(log.slice(lastRead).some(([kind, k]) => kind === 'write' && k === 'gridRow'), 'the panels are placed after they are all read');
});

// Bug it catches: Belt 3D measured the room below its stage at each animation frame, a layout read 60 times a second.
test('Belt 3D reads no layout in an animation frame unless the window was resized', async () => {
  const w = boot({ tab: 'belt3d', extra: `HTMLCanvasElement.prototype.getContext = function (k) { return /webgl/.test(k) ? {} : null; };
    window.DASH_BELT3D_SCENE = { createScene() { return { frame() {}, resize() {} }; } };` });
  deliver(w, full());
  await settle();
  for (const f of w.frames.splice(0)) f();
  let reads = 0;
  const count = (proto, name) => { const f = proto[name]; proto[name] = function (...a) { reads += 1; return f.apply(this, a); }; };
  count(w.Element.prototype, 'getBoundingClientRect');
  count(w.Element.prototype, 'getClientRects');
  const off = Object.getOwnPropertyDescriptor(w.HTMLElement.prototype, 'offsetHeight');
  Object.defineProperty(w.HTMLElement.prototype, 'offsetHeight', { ...off, get() { reads += 1; return off.get.call(this); } });
  const frames = (n) => { for (let i = 0; i < n; i += 1) { w.clock += 16; const fs = w.frames.splice(0); assert.ok(fs.length, 'the floor keeps drawing'); fs.forEach((f) => f()); } };
  frames(3);
  assert.equal(reads, 0, 'no layout read in a frame with the window as it was');
  w.dispatchEvent(new w.Event('resize'));
  frames(1);
  assert.ok(reads > 0, 'a resized window is measured at the next frame');
  reads = 0;
  frames(2);
  assert.equal(reads, 0, 'and only once');
});

// Bug it catches: a refresh ran the path pattern (built from the card's name) over a card's output again when the
// output was the same as before.
test('a refresh with the same output text runs no path pattern on it', () => {
  const w = boot();
  const data = full();
  const blocked = data.panels.needs.data.cards.blocked[0];
  blocked.tail = `not ok 1 - pays once at /work/${blocked.card}/test.js`;
  deliver(w, data);
  let built = 0;
  const R = w.RegExp;
  w.RegExp = new Proxy(R, { construct(t, args) { if (String(args[0]).includes(blocked.card)) built += 1; return Reflect.construct(t, args); } });
  // Needs you takes each blocked card's output box out and puts it back at each draw: counted, to know it drew it.
  let redrawn = 0;
  const remove = w.Element.prototype.remove;
  w.Element.prototype.remove = function () { if (this.matches('details.output')) redrawn += 1; return remove.call(this); };
  blocked.reason = 'tests failed three times';  // the panel is drawn again only when its data changed
  next(w, data);
  assert.ok(redrawn > 0, 'the output was drawn again');
  assert.equal(built, 0, 'the same output runs no path pattern');
  blocked.tail += '\nnot ok 2 - refunds';
  next(w, data);
  assert.ok(built > 0, 'new output runs the pattern, so the count above counts it');
});
