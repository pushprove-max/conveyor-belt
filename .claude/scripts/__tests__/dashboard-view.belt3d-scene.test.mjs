// SPDX-License-Identifier: Apache-2.0
// Belt 3D's scene (belt3d-scene.js) itself, with the real three.js: only its WebGL renderer and the environment map
// it bakes with it are stand-ins, since Node has no WebGL. The stand-in renderer keeps the scene it is asked to draw,
// and while globalThis.glLost is set throws as three.js does drawing on a WebGL context the browser has lost.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { register, createRequire } from 'node:module';
import { fileURLToPath, pathToFileURL } from 'node:url';

const VIEW = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../dashboard');
const THREE_URL = pathToFileURL(path.join(VIEW, 'vendor/three/three.module.min.js')).href;
const STUB = `data:text/javascript,${encodeURIComponent(`export * from ${JSON.stringify(THREE_URL)};
export class WebGLRenderer { constructor(o) { globalThis.glOptions = o; this.domElement = document.createElement('canvas'); this.shadowMap = {}; this.capabilities = { getMaxAnisotropy: () => 1 }; }
  setPixelRatio() {} setSize(w, h) { globalThis.sized = [w, h]; }
  render(scene) { globalThis.drawn = scene; if (globalThis.glLost) throw new TypeError("null is not an object (evaluating 'r.getProgramInfoLog(f).trim')"); } }
export class PMREMGenerator { fromScene() { return { texture: null }; } dispose() {} }`)}`;
// Every import of three.js, but the stand-in's own, gets the stand-in.
register(`data:text/javascript,${encodeURIComponent(`export async function resolve(s, c, next) {
  const r = await next(s, c);
  return r.url === ${JSON.stringify(THREE_URL)} && !String(c.parentURL).startsWith('data:') ? { url: ${JSON.stringify(STUB)}, shortCircuit: true } : r; }`)}`);

const { JSDOM } = createRequire(import.meta.url)('jsdom');
const dom = new JSDOM('<!doctype html><body></body>');
Object.assign(globalThis, { window: dom.window, document: dom.window.document, HTMLElement: dom.window.HTMLElement });
// The textures are drawn on a 2D canvas, which jsdom has not got: one that draws nothing stands in.
dom.window.HTMLCanvasElement.prototype.getContext = function () {
  return new Proxy({}, { get: (o, k) => (k in o ? o[k] : () => ({ addColorStop() {} })), set: (o, k, v) => { o[k] = v; return true; } });
};
const { createScene } = await import(pathToFileURL(path.join(VIEW, 'belt3d-scene.js')).href);

// `aside`: the stage's --b3-aside (app.css), the width the open details take off the floor's right. The host's size
// is host.size, which a test can change. s.wakes counts the scene's asks for frames again.
function open(width = 1200, height = 700, aside = '328px') {
  const host = document.createElement('div'), labelsEl = document.createElement('div');
  host.size = { clientWidth: width, clientHeight: height };
  for (const k of ['clientWidth', 'clientHeight']) Object.defineProperty(host, k, { get: () => host.size[k] });
  host.style.setProperty('--b3-aside', aside);
  host.append(labelsEl);
  document.body.append(host);
  const s = createScene({ host, labelsEl, hover() {}, pick() {}, wake() { s.wakes += 1; } });
  s.wakes = 0;
  s.host = host;
  return s;
}
const el = () => document.createElement('div');
const heads = Array.from({ length: 8 }, el), bayEls = Array.from({ length: 4 }, el);
const row = (key, stuck) => ({ key, stuck, live: !stuck, hot: false, at: 0, steps: ['now', 'todo', 'todo', 'todo', 'todo', 'todo'], name: el(), now: el(), marks: Array.from({ length: 6 }, el),
  back: null, label: el() });
const state = (rows, cards) => ({ motion: false, open: false, heads, bays: bayEls, rows, cards });
// The bay slabs on the floor: the 16 by 9 slabs.
const slabs = () => {
  let n = 0;
  globalThis.drawn.traverse((o) => {
    if (!o.geometry) return;
    if (!o.geometry.boundingBox) o.geometry.computeBoundingBox();
    const b = o.geometry.boundingBox;
    if (Math.abs(b.max.x - b.min.x - 16) < 1e-6 && Math.abs(b.max.z - b.min.z - 9) < 1e-6) n += 1;
  });
  return n;
};
const crateOf = (tag) => { let g = null; globalThis.drawn.traverse((o) => { if (o.element === tag) g = o.parent; }); return g; };

// Issue 423: a card that went back from Fix (step 2) to Review (step 1). Its lane, frame by frame (dt seconds each),
// at `at` with `back` its way back; the amber stretch and the ghost the scene drew for it.
function goneBack(motion) {
  const s = open(), lane = row('sample:c3-63', false), tag = el(), badge = el();
  const go = (at, back, n = 1) => {
    for (let i = 0; i < n; i += 1) s.frame({ ...state([{ ...lane, at, back }], [{ key: lane.key, from: null, kind: 'run', row: 0, at, bay: null, slot: null, tag, badge }]), motion }, 0.05);
    const o = { badgeOnCrate: crateOf(badge) !== null && crateOf(badge) === crateOf(tag) };
    globalThis.drawn.traverse((m) => { if (m.name === 'b3-back' || m.name === 'b3-ghost') o[m.name] = m; });
    return o;
  };
  return go;
}
const SX = (i) => -14 + 6 * i;  // belt3d-scene.js: a step's pad
// Bug it catches: a card that went back jumping back on a belt that looks as it always does.
test('belt3d scene: a card gone back from Fix to Review is amber from Review to Fix with the ghost on Fix; its chevrons run back while its crate travels, then stand still', () => {
  const go = goneBack(true);
  go(2, null, 40);
  const first = go(1, { from: 2, to: 1 }), back = first['b3-back'], ghost = first['b3-ghost'];
  assert.ok(back.visible && ghost.visible, 'the stretch and the ghost are drawn');
  assert.deepEqual([back.position.x, back.scale.x, ghost.position.x], [(SX(1) + SX(2)) / 2, 6, SX(2)], 'the stretch spans Review to Fix; the ghost is on Fix');
  assert.ok(ghost.material.isLineDashedMaterial && back.material.emissive.getHexString() === 'f3c46c', 'a dashed ghost; an amber stretch');
  assert.ok(first.badgeOnCrate, 'the round badge rides on the crate');
  const moving = back.material.map.offset.x;
  assert.ok(moving > 0, `its chevrons run right to left while the crate travels back: offset ${moving}`);
  const there = go(1, { from: 2, to: 1 }, 200)['b3-back'].material.map.offset.x;
  assert.equal(go(1, { from: 2, to: 1 }, 20)['b3-back'].material.map.offset.x, there, 'the crate there, they stand still');
  assert.ok(go(1, { from: 2, to: 1 })['b3-back'].visible, 'the stretch stays while the card is in that round');
  // Bug it catches: Review 2 (NO-GO) on to Fix 2 keeps the way back, and its chevrons ran backwards again while the
  // crate went forward.
  assert.equal(go(2, { from: 2, to: 1 }, 20)['b3-back'].material.map.offset.x, there, 'the crate going forward, they stand still');
});
// Done when: with reduced motion the chevrons do not move. Bug it catches: the way back scrolling, or fading in, with motion off.
test('belt3d scene: with motion off a card gone back has its amber stretch and ghost at once and its chevrons never move; moved on, they are gone at once', () => {
  const go = goneBack(false);
  go(2, null);
  const first = go(1, { from: 2, to: 1 });
  assert.ok(first['b3-back'].visible && first['b3-ghost'].visible, 'drawn at once');
  assert.deepEqual([first['b3-back'].material.opacity, first['b3-ghost'].material.opacity], [1, 1], 'at full strength at once, no fade');
  assert.equal(go(1, { from: 2, to: 1 }, 20)['b3-back'].material.map.offset.x, 0, 'the chevrons do not move');
  const on = go(3, null);
  assert.ok(!on['b3-back'].visible && !on['b3-ghost'].visible, 'moved on past Fix, the stretch and the ghost are gone');
});

// Bug it catches: a floor opened with only queued, waiting, held or landed cards (no lane) had no bays drawn under them.
test('belt3d scene: a floor with no lane still has its four bays, and keeps four when a lane comes', () => {
  const s = open(), tag = el();
  s.frame(state([], [{ key: 'sample#20', from: null, kind: 'queued', row: null, at: -1, bay: 0, slot: 0, tag }]), 0.016);
  assert.equal(slabs(), 4, 'four bays with no lane');
  s.frame(state([row('sample:c1-1', false)], [{ key: 'sample:c1-1', from: 'sample#1', kind: 'run', row: 0, at: 0, bay: null, slot: null, tag: el() },
    { key: 'sample#20', from: null, kind: 'queued', row: null, at: -1, bay: 0, slot: 0, tag }]), 0.016);
  assert.equal(slabs(), 4, 'the bays moved below the lane, not drawn twice');
});

// Bug it catches: a card keyed by its card id losing the crate of the issue it was picked up from, so a picked-up
// issue's crate vanishes from its bay and a new one appears in its lane instead of gliding there.
test('belt3d scene: a card picked up from the queue takes over its queued crate', () => {
  const s = open(), queued = el(), running = el();
  s.frame(state([], [{ key: 'sample#20', from: null, kind: 'queued', row: null, at: -1, bay: 0, slot: 0, tag: queued }]), 0.016);
  const crate = crateOf(queued);
  assert.ok(crate, 'the queued issue has its crate');
  s.frame(state([row('sample:c9-20', false)], [{ key: 'sample:c9-20', from: 'sample#20', kind: 'run', row: 0, at: 0, bay: null, slot: null, tag: running }]), 0.016);
  // By identity: a diff of two three.js groups would take minutes to print.
  assert.ok(crateOf(running) === crate, 'the running card has the same crate');
  assert.ok(crateOf(queued) === null, 'the queued issue\'s tag is off it');
});

// Issue 569: the panel asks for no more frames once a frame says the floor has settled. Bug it catches: a scene that
// never says so (the GPU kept drawing a still floor 60 times a second), or says so while a crate still glides or fades.
// settles(): what each of n frames, a 20th of a second each, says: true once the floor has settled.
const settles = (s, st, n) => Array.from({ length: n }, () => s.frame(st, 0.05));
test('belt3d scene: a queued crate fading in, then gliding to another slot, has the floor settled only once it is there', () => {
  const s = open(), card = (slot) => ({ key: 'sample#20', from: null, kind: 'queued', row: null, at: -1, bay: 0, slot, tag: el() });
  const st = { ...state([], [card(0)]), motion: true };
  const first = settles(s, st, 200), at = first.indexOf(true);
  assert.ok(at > 10, `not settled while it fades in: settled at frame ${at}`);
  assert.ok(first.slice(at).every(Boolean), 'and settled from then on');
  const tag = st.cards[0].tag, z0 = crateOf(tag).position.z;
  st.cards = [{ ...card(1), tag }];
  const glide = settles(s, st, 200), there = glide.indexOf(true);
  assert.ok(there > 10, `not settled while it glides to its new slot: settled at frame ${there}`);
  assert.ok(glide.slice(there).every(Boolean), 'and settled from then on');
  assert.ok(Math.abs(crateOf(tag).position.z - z0 - 2.3) < 0.01, `settled in its new slot, 2.3 on: ${crateOf(tag).position.z - z0}`);
});

// Bug it catches: a running card's belt and lights standing still because the floor was said settled under them.
test('belt3d scene: with motion on a running card keeps the floor moving; with motion off it settles at its first frame', () => {
  const s = open(), lane = row('sample:c1-1', false), cards = [{ key: lane.key, from: null, kind: 'run', row: 0, at: 0, bay: null, slot: null, tag: el() }];
  assert.ok(!settles(s, { ...state([lane], cards), motion: true }, 200).some(Boolean), 'its tread runs and its lights pulse');
  assert.deepEqual(settles(open(), state([lane], cards), 2), [true, true], 'motion off: all at once where it goes, nothing pulses');
});

// Bug it catches: a new size clears the canvas, and a settled floor left it blank until the next refresh.
test('belt3d scene: a new size of the host asks for frames again; the same size does not', () => {
  const s = open();
  s.frame(state([], []), 0.05);
  assert.equal(s.wakes, 1, 'the first size');
  s.host.size = { clientWidth: 900, clientHeight: 600 };
  s.resize();
  assert.equal(s.wakes, 2, 'a new size');
  s.resize();
  assert.equal(s.wakes, 2, 'the same size again');
});

// Bug it catches: the floor always making room for a 328px details panel, so on a phone's stage (narrower than the
// panel, which opens below the floor there) opening a card's details shrank the floor to a speck.
test('belt3d scene: the floor makes room for the details only as wide as the stylesheet says, none on a phone', () => {
  const lane = [row('sample:c1-1', false)], cards = [{ key: 'sample:c1-1', from: null, kind: 'run', row: 0, at: 0, bay: null, slot: null, tag: el() }];
  const u = (width, height, aside) => {
    const s = open(width, height, aside), host = document.body.lastChild;
    s.frame(state(lane, cards), 0.016);
    const shut = parseFloat(host.style.getPropertyValue('--u'));
    s.frame({ ...state(lane, cards), open: true }, 0.016);
    return [shut, parseFloat(host.style.getPropertyValue('--u'))];
  };
  const [wide, wideOpen] = u(1200, 700, '328px');
  assert.ok(wideOpen < wide * 0.9, `beside the floor, the details take their width off it: ${wide} -> ${wideOpen}`);
  // A phone's stage for one lane, as app.css sizes it: 156px of bands and 256 * 15 * 0.0132 of floor.
  const [phone, phoneOpen] = u(296, 210, '0px');
  assert.ok(phone > 2, `the floor fills a phone's stage: --u ${phone}px`);
  assert.equal(phoneOpen, phone, 'on a phone the details open below the floor, which keeps its size');
});

// Issue 393: the deck behind the floor shows only through a clear canvas. Bug it catches: a canvas drawn opaque (no
// alpha), a scene background, or a ground plane painted over the deck; and a floor fitted over the deck's readouts
// (the bands above and below it the stylesheet gives: --b3-top, --b3-bottom).
test('belt3d scene: the canvas is clear but for the floor and its shadows, and the floor keeps out of the deck\'s bands', () => {
  const s = open(1200, 520), host = document.body.lastChild, labelsEl = host.lastChild;
  host.style.setProperty('--b3-top', '200px');
  host.style.setProperty('--b3-bottom', '90px');
  const lanes = [row('sample:c1-1', false), row('sample:c2-2', true)], tag = el();
  s.frame(state(lanes, [{ key: 'sample#20', from: null, kind: 'queued', row: null, at: -1, bay: 0, slot: 0, tag }]), 0.016);
  assert.equal(globalThis.glOptions.alpha, true, 'the canvas has an alpha channel');
  assert.equal(globalThis.drawn.background, null, 'the scene paints no background');
  let ground = null;
  globalThis.drawn.traverse((o) => { if (o.geometry && o.geometry.parameters && o.geometry.parameters.width === 500) ground = o; });
  assert.ok(ground && ground.material.isShadowMaterial && ground.receiveShadow, 'the ground takes the shadows and nothing else');
  const ys = Array.from(labelsEl.children, (e) => Number((/translate\(([-\d.]+)px,\s*([-\d.]+)px\)/.exec(e.style.transform) || [])[2]));
  assert.ok(ys.length >= 8 + 2 * 8 + 4 && ys.every((y) => y >= 200 && y <= 520 - 90), `every word of the floor lies between the bands: ${ys.map(Math.round)}`);
});

// Bug it catches: the floor left at the size it had when the panel goes full screen (drawn small in a corner of the
// screen) or when it comes back (cut off), as where no ResizeObserver tells the scene.
test('belt3d scene: resize() fits the floor to the host\'s new size, going full screen and back', () => {
  const lane = [row('sample:c1-1', false)], cards = [{ key: 'sample:c1-1', from: null, kind: 'run', row: 0, at: 0, bay: null, slot: null, tag: el() }];
  const s = open(1200, 700), host = document.body.lastChild, u = () => parseFloat(host.style.getPropertyValue('--u'));
  s.frame(state(lane, cards), 0.016);
  const before = u();
  host.size = { clientWidth: 1920, clientHeight: 1080 };
  s.resize();
  assert.deepEqual(globalThis.sized, [1920, 1080], 'drawn at the full screen\'s size');
  assert.ok(u() > before * 1.2, `the floor and its words grow with it: --u ${before} -> ${u()}`);
  host.size = { clientWidth: 1200, clientHeight: 700 };
  s.resize();
  assert.deepEqual(globalThis.sized, [1200, 700], 'back at the panel\'s size');
  assert.equal(u(), before, 'the floor as it was');
});

// Bug it catches (issue 381): on an iPad, lanes' card labels and statuses blank while the column and bay heads stayed.
// A lanes' rebuild takes every lane's words off the page and only the label step puts them back; that step ran after
// the WebGL draw, so a draw that threw (three.js on a context Safari lost while the page was in the background) left
// them off. Each event in turn: the page hidden while a card comes and another gets stuck, shown again with its
// context lost, the context restored, a turn of the iPad, and full screen.
test('belt3d scene: every lane\'s label and status are on the floor after hide and show, a lost context, a resize', () => {
  const s = open(1180, 820), host = document.body.lastChild, labelsEl = host.lastChild;
  const one = row('sample:c1-1', false), two = [one, row('sample:c2-2', true)];
  const shown = (rows, when) => rows.forEach((r, i) => [['label', r.name], ['status', r.now]].forEach(([what, e]) => {
    assert.ok(e.parentNode === labelsEl, `${when}: lane ${i}'s ${what} is on the page`);
    assert.notEqual(e.style.display, 'none', `${when}: lane ${i}'s ${what} is shown`);
    const at = /translate\(([-\d.]+)px,\s*([-\d.]+)px\)/.exec(e.style.transform), { clientWidth: w, clientHeight: h } = host.size;
    assert.ok(at && +at[1] >= 0 && +at[1] <= w && +at[2] >= 0 && +at[2] <= h, `${when}: lane ${i}'s ${what} is placed on the stage: ${e.style.transform}`);
  }));
  try {
    s.frame(state([one], []), 0.016);
    shown([one], 'first drawn');
    // Hidden, nothing is drawn; shown again, the first frame rebuilds the lanes and its WebGL draw throws.
    globalThis.glLost = true;
    assert.throws(() => s.frame(state(two, []), 0.016), TypeError);
    shown(two, 'shown again, the WebGL context lost');
    globalThis.glLost = false;
    s.frame(state(two, []), 0.016);
    shown(two, 'the context restored');
    host.size = { clientWidth: 820, clientHeight: 1180 };
    s.resize();
    s.frame(state(two, []), 0.016);
    shown(two, 'turned upright');
    host.size = { clientWidth: 1180, clientHeight: 820 };
    s.resize();
    s.frame(state(two, []), 0.016);
    shown(two, 'full screen');
  } finally { globalThis.glLost = false; }
});

// Issue 394. The Belt 3D panel (panels/belt3d.js) with this scene, at the stage sizes of a 1700, 1280, 1000 and 600 px
// wide window, in the panel (as tall as app.css makes a floor with no lane) and full screen. Bug it catches: the Just
// landed bay showed its three crates with no words beside them. A card that left the snapshot and came back (here, a
// refresh without it while the Board's browser tab was in the background: the page still refreshes, but the floor
// draws no frame, so the crate never faded out) kept the crate it had, and the crate kept the
// tag the panel had dropped: the label step put that old tag back, still hidden as a lane card's, and never placed
// the new one. Each of the three landed cards' tags must be the one on the page for its issue, placed on the stage
// beside its crate, and say its number, title and when it landed: on load, when the cards move from their lanes into
// Just landed, and when they come back after a refresh without them.
const helpers = await import('./dashboard-view.helpers.mjs');
test('belt3d scene: each Just landed card has its number, title and landed line beside its crate, on the stage, at every width and full screen', async () => {
  const { boot, deliver, next, settle, full, iso, T0 } = helpers;
  const N = [[7, 'c5-7', 'Landed one'], [8, 'c6-8', 'Fixed before'], [11, 'c9-11', 'Third landed']];
  const snap = (where) => {
    const d = full(), b = d.panels.belt3d.data;
    b.belt = where === 'lanes' ? N.map(([n, card, title]) => ({ repo: 'sample', card, issue: n, title, url: null, step: 'tests', stepAt: iso(T0 - 60000), landed: false,
      waitsOn: null, usd: null, turns: null, reviews: [], track: null })) : [];
    b.needs = [];
    b.landed = where === 'landed' ? N.map(([n, card, title], i) => ({ repo: 'sample', card, issue: n, title, url: null, time: iso(T0 - (i + 1) * 600000), usd: null, reviews: [] })) : [];
    return d;
  };
  const floorH = (w) => 96 + (w - 40) * 12.4 * 0.0132;  // app.css .b3-stage with no lane
  const sizes = [['in the panel at 1700 px', 1618, floorH(1618)], ['in the panel at 1280 px', 1198, floorH(1198)], ['in the panel at 1000 px', 918, floorH(918)],
    ['in the panel at 600 px', 542, floorH(542)], ['full screen at 1700 px', 1668, 910], ['full screen at 1280 px', 1248, 910], ['full screen at 1000 px', 968, 910], ['full screen at 600 px', 568, 810]];
  const ways = [['loaded with them landed', ['landed']], ['moved from their lanes', ['lanes', 'landed']], ['back after a refresh without them', ['lanes', 'none', 'landed']]];
  const keep = { window: globalThis.window, document: globalThis.document, HTMLElement: globalThis.HTMLElement, Element: globalThis.Element };
  try {
    for (const [where, width, height] of sizes) {
      for (const [how, steps] of ways) {
        const at = `${how}, ${where}`;
        const w = boot({ tab: 'belt3d' });
        // The scene runs on this page: three.js and the scene read the page's window and document.
        Object.assign(globalThis, { window: w, document: w.document, HTMLElement: w.HTMLElement, Element: w.Element });
        const ctx2d = new Proxy({}, { get: (o, k) => (k in o ? o[k] : () => ({ addColorStop() {} })), set: (o, k, v) => { o[k] = v; return true; } });
        w.HTMLCanvasElement.prototype.getContext = (k) => (/webgl/.test(k) ? {} : ctx2d);
        w.DASH_BELT3D_SCENE = { createScene };
        const frame = () => { w.clock += 16; for (const f of w.frames.splice(0)) f(); };
        for (const [i, s] of steps.entries()) {
          if (i === 0) deliver(w, snap(s)); else next(w, snap(s));
          await settle();
          const stage = w.document.querySelector('.b3-stage');
          if (stage && !Object.hasOwn(stage, 'clientWidth')) for (const [k, v] of [['clientWidth', width], ['clientHeight', height]]) Object.defineProperty(stage, k, { value: v });
          // A refresh without the cards comes while the browser tab is in the background: no frame runs until they are back.
          if (s !== 'none') frame();
        }
        const stage = w.document.querySelector('.b3-stage'), labelsEl = stage.querySelector('.b3-labels'), ub = parseFloat(stage.style.getPropertyValue('--ub'));
        assert.ok(ub > 0, `${at}: the bays' text is sized`);
        for (const [n, , title] of N) {
          const tags = labelsEl.querySelectorAll(`.b3-bc[data-issue="${n}"]`), tag = tags[0];
          assert.equal(tags.length, 1, `${at}: #${n} has one tag on the page, not an old one beside it`);
          assert.ok(!tag.classList.contains('off') && tag.style.display !== 'none', `${at}: #${n}'s tag is shown: ${tag.className}, display ${tag.style.display}`);
          assert.equal(tag.querySelector('b').textContent, `#${n}`, `${at}: #${n}'s number`);
          assert.equal(tag.querySelector('.b3-t span').textContent, title, `${at}: #${n}'s title`);
          assert.match(tag.querySelector('.b3-s').textContent, /^Landed \d+ min ago$/, `${at}: #${n} says when it landed`);
          assert.ok(crateOf(tag), `${at}: #${n}'s tag hangs on its crate`);
          // Placed by its left edge and middle (belt3d-scene.js label()), 12.6 by 1.95 of --ub (app.css .b3-bc).
          const p = /translate\(([-\d.]+)px,\s*([-\d.]+)px\)/.exec(tag.style.transform);
          assert.ok(p, `${at}: #${n}'s tag is placed: "${tag.style.transform}"`);
          const [x, y] = [+p[1], +p[2]];
          assert.ok(x >= 0 && x + 12.6 * ub <= width && y - 0.975 * ub >= 0 && y + 0.975 * ub <= height,
            `${at}: #${n}'s tag lies inside the ${width} by ${Math.round(height)} stage: left ${x}, right ${x + 12.6 * ub}, middle ${y}`);
        }
      }
    }
  } finally { Object.assign(globalThis, keep); }
});
