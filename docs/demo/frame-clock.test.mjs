// SPDX-License-Identifier: Apache-2.0
// frame-clock.js, as capture-board.js films the README's Belt 3D clip from the timeline (timeline.js BELT3D), on a page
// in jsdom (no browser runs in a test). The page stands in for the Board's floor as panels/belt3d.js and
// belt3d-scene.js draw it: the feed's snapshot gives each card its step, and each frame callback moves the card's crate
// toward its step's pad by the time since the last frame (Date.now, at most 0.05 s), on the scene's spring.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { JSDOM } from 'jsdom';
import { film, installClock } from './frame-clock.js';
import { BELT3D, createTimeline } from './timeline.js';

const FLOOR = `(() => {
  const PAD = { build: 0, review: 1, fix: 2, tests: 3, landing: 4, push: 5 };
  const crate = { x: null, v: 0, to: null };
  window.crate = crate;
  // The scene's crate spring (belt3d-scene.js spring, w 3.4).
  const spring = (s, to, w, dt) => {
    const d = s.x - to, k = w * dt, e = 1 / (1 + k + 0.48 * k * k + 0.235 * k * k * k), tmp = (s.v + w * d) * dt;
    s.v = (s.v - w * tmp) * e;
    s.x = to + (d + tmp) * e;
  };
  new EventSource('events').addEventListener('snapshot', (m) => {
    const c = JSON.parse(m.data).panels.belt3d.data.belt.find((x) => x.issue === ${BELT3D.click.issue});
    if (c) crate.to = PAD[c.step];
    if (crate.x === null) crate.x = crate.to;
  });
  let last = Date.now();
  const frame = () => {
    const t = Date.now(), dt = Math.min(0.05, Math.max(0, (t - last) / 1000));
    last = t;
    if (crate.to !== null) spring(crate, crate.to, 3.4, dt);
    requestAnimationFrame(frame);
  };
  requestAnimationFrame(frame);
})();`;

// The steps a card jumps more than twice the median of the steps around it (two each side), as [frame, step, median].
// A spring eases in and out, so its steps grow and shrink, but from one frame to the next by little.
function jumps(xs) {
  const d = xs.slice(1).map((x, i) => Math.abs(x - xs[i]));
  const out = [];
  d.forEach((s, i) => {
    if (s < 1e-3) return;
    const near = d.slice(Math.max(0, i - 2), i + 3).filter((x) => x >= 1e-3).sort((a, b) => a - b);
    const med = near[Math.floor(near.length / 2)];
    if (s > 2 * med) out.push([i + 1, s, med]);
  });
  return out;
}

// The browser's EventSource, which jsdom has not: a feed that never connects. The film gives the page its snapshots.
const page = () => {
  const w = new JSDOM('<!doctype html><body></body>', { runScripts: 'outside-only' }).window;
  w.eval('window.EventSource = class extends EventTarget { constructor(u) { super(); this.url = u; this.readyState = 1; } };');
  return w;
};

// Bug caught (#653): the clip's frames were a screencast's, sent when the machine could, so the belt's motion jumped
// where frames were dropped. Filmed on the page's clock, each frame is 1/30 s of the floor's motion: a moving card's
// steps change evenly from frame to frame, and the clip has exactly 30 frames a second of the story's window.
test('Belt 3D film: a moving card steps evenly from frame to frame, 30 frames a second of the window', async () => {
  const w = page();
  const start = Date.UTC(2026, 10, 15, 9);
  w.eval(`(${installClock})(${start})`);
  w.eval(FLOOR);
  const tl = createTimeline(start);
  const at = [];
  const xs = [];
  const f = film({ evaluate: async (fn, ...args) => w.eval(`(${fn})(...${JSON.stringify(args)})`) }, {
    fps: 30, start, t0: BELT3D.from, speed: BELT3D.speed,
    snapshot: (t, ms) => { at.push(ms); return JSON.stringify(tl.snapshot(t)); },
    shoot: async () => { xs.push(w.crate.x); },
  });
  await f.warm(1);
  const warm = at.length;
  await f.until(BELT3D.to);
  assert.equal(xs.length, Math.ceil(((BELT3D.to - BELT3D.from) / BELT3D.speed) * 30), 'one frame for each 1/30 s of the window');
  // The page's clock: 1/30 s a frame, whatever the time the machine took.
  at.slice(1).forEach((ms, i) => assert.ok(Math.abs(ms - at[i] - 1000 / 30) < 1e-3, `frame ${i + 1} is ${ms - at[i]} ms after the last`));
  assert.equal(w.eval('Date.now()'), at.at(-1));
  assert.equal(warm, 30, 'the second the page is stepped before the film starts');
  // #41 goes Review, back to Fix, Review, Test, Land and Push in the window: a move of at least a pad each time.
  const moving = xs.slice(1).filter((x, i) => Math.abs(x - xs[i]) >= 1e-3).length;
  assert.ok(moving > 100, `the card moves in only ${moving} frames`);
  assert.ok(Math.max(...xs) - Math.min(...xs) >= 3, 'the card crosses the floor');
  assert.deepEqual(jumps(xs), [], 'a frame where the card jumps');
  // The check itself: one frame dropped, as a screencast drops them on a busy machine, is a jump.
  const peak = xs.slice(1).reduce((b, x, i) => (Math.abs(x - xs[i]) > Math.abs(xs[b + 1] - xs[b]) ? i : b), 0);
  assert.notDeepEqual(jumps([...xs.slice(0, peak + 1), ...xs.slice(peak + 2)]), [], 'a dropped frame is not seen');
});
