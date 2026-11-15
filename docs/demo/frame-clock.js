// SPDX-License-Identifier: Apache-2.0
// Frame by frame recording for capture-board.js (the README's Belt 3D clip): the page's clock is the script's, so each
// frame is exactly 1/fps s of the page's motion however long the machine takes to draw and shoot it.
// installClock runs in the page before its own scripts (page.evaluateOnNewDocument): Date.now, performance.now and
// requestAnimationFrame then move only when the script steps them, and the CSS transitions and animations are held and
// set to that clock's time at each step. film drives it from Node: one step, one snapshot of the timeline and one shot a
// frame.

// In the page: it reads nothing from outside the function, as Puppeteer sends its text alone. start: the page's
// Date.now when it loads (ms).
export function installClock(start) {
  let now = start, queue = [], id = 0;
  const seen = new WeakMap();  // each CSS animation: the clock's time it started at
  Date.now = () => now;
  window.performance.now = () => now - start;
  window.requestAnimationFrame = (fn) => { id += 1; queue.push([id, fn]); return id; };
  window.cancelAnimationFrame = (n) => { queue = queue.filter(([k]) => k !== n); };
  // The feed: each EventSource the page opens, so a step gives the page its snapshot before the frame is drawn.
  const feeds = [];
  if (typeof window.EventSource === 'function') {
    const Source = window.EventSource;
    window.EventSource = class extends Source { constructor(...a) { super(...a); feeds.push(this); } };
  }
  // One frame: the clock moves on to at (ms, the frame's own time, so no rounding adds up), the page is given the
  // snapshot (a JSON text, or null for none), the CSS motion is set to the new time, then each frame callback asked for
  // since the last step runs once.
  window.demoClock = {
    step(at, snapshot) {
      const was = now;
      now = at;
      if (snapshot !== null) for (const es of feeds) if (es.readyState !== 2) es.dispatchEvent(new window.MessageEvent('snapshot', { data: snapshot }));
      if (typeof document.getAnimations === 'function') {
        for (const a of document.getAnimations()) {
          if (!seen.has(a)) { seen.set(a, was); a.pause(); }
          a.currentTime = now - seen.get(a);
        }
      }
      const run = queue;
      queue = [];
      for (const [, fn] of run) fn(now - start);
    },
  };
}

// In Node: the frames of one recording. page: a Puppeteer page with installClock(start) in it. Story second t0 at its
// first frame, moving speed story seconds a frame second. snapshot(t, at): the feed's text at story second t with the
// page's Date.now at (ms). shoot(): takes the frame. warm(sec) steps the page without shooting, the story held at t0;
// wait(sec) and until(t) shoot each frame; mark(name) keeps the clip's second of the next frame.
export function film(page, { fps = 30, start, t0, speed = 1, snapshot, shoot }) {
  let steps = 0, shots = 0;
  const marks = {};
  const story = () => t0 + (shots / fps) * speed;
  async function step(shot) {
    steps += 1;
    const at = start + (steps * 1000) / fps;
    await page.evaluate((a, s) => window.demoClock.step(a, s), at, snapshot(story(), at));
    if (!shot) return;
    await shoot();
    shots += 1;
  }
  return {
    marks,
    story,
    get shots() { return shots; },
    async warm(sec) { for (let i = 0; i < Math.round(sec * fps); i += 1) await step(false); },
    async wait(sec) { const end = shots + Math.round(sec * fps); while (shots < end) await step(true); },
    async until(t) { while (story() < t) await step(true); },
    mark(name) { marks[name] = Math.round((shots / fps) * 1000) / 1000; },
  };
}
