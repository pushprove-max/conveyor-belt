// SPDX-License-Identifier: Apache-2.0
// Belt 3D's scene: the factory floor, drawn with three.js (vendor/three/, served from this page's own folder). One belt
// lane a card on the belt, then one red lane a stuck card, each with six pads (Build, Review, Fix, Test, Land, Push) and
// the card's crate on its step, a card that went back with its belt amber back to the step it left (issue 423); four
// bays along the bottom (queued, waiting, held, just landed). panels/belt3d.js
// imports it the first time its panel is shown, owns every word on it (the labels are its HTML elements, placed here
// over the floor by CSS2DRenderer) and hands it, each frame, what to draw as plain data. It decides nothing of its own.
// The canvas is transparent and its ground takes only the floor's shadows, so the stage's deck (panels/belt3d.js,
// app.css .b3-deck) shows behind the floor; the deck is HTML, SVG and CSS, nothing drawn here.
// createScene throws when WebGL cannot be had. A frame says whether the floor has settled (every spring at rest and
// nothing pulsing), so the panel asks for no more frames until something moves it; `wake` asks for them again after
// the host's size changed, as a new size clears the canvas (issue 569).
import * as THREE from './vendor/three/three.module.min.js';
import { RoundedBoxGeometry } from './vendor/three/addons/geometries/RoundedBoxGeometry.js';
import { CSS2DRenderer, CSS2DObject } from './vendor/three/addons/renderers/CSS2DRenderer.js';

// The crates use quieter satin versions of the Board's hues.
const CRATE = { run: '#7d95f0', blocked: '#dc6a62', waiting: '#c9a258', held: '#6d7587', queued: '#4f5c77', landed: '#56b386' };
const PAD = { todo: '#232a38', done: '#2f7a59', now: '#7089f2', skipped: '#1a202b', failed: '#c7564f' };
const PAD_GLOW = { now: '#3f5fe0', failed: '#8a231d' };
const col = (o) => Object.fromEntries(Object.entries(o).map(([k, v]) => [k, new THREE.Color(v)]));
const C_CRATE = col(CRATE), C_PAD = col(PAD), C_GLOW = col(PAD_GLOW), BLACK = new THREE.Color(0), C_ACCENT = new THREE.Color('#93abff'), C_BAD = new THREE.Color('#ff7a70');
// A card that went back (issue 423): the Board's warn colour (app.css --b3-warn).
const C_WARN = new THREE.Color('#f3c46c');

// The floor, in the scene's lengths: a step's pad at SX(i), lane r at RZ(r) (the stuck lanes follow the running ones), the
// column heads above the first lane, the bays below the last.
const SX = (i) => -14 + 6 * i, RZ = (r) => 2.6 * r, HEAD_Z = -2.5;
const BELT_Y = 0.345, PAD_H = 0.24, PAD_TOP = BELT_Y + PAD_H, BAY_TOP = 0.2;
const BAY_X = [-25.5, -8.5, 8.5, 25.5];
const bayEdge = (n) => RZ(n - 1) + 2.2;  // the near edge of the bays, below the last of n lanes
// The floor runs from HEAD_Z - 1 to bayEdge(n) + 9.3: 2.6 n + 12.4 deep with n lanes. panels/belt3d.js sizes the
// stage by that (DEPTH there), or by the window's room below it where that is taller, so the panel's height changes
// only when the number of lanes, or that room, does.

// Critically damped spring: eases in and out, never overshoots, so a crate glides and settles.
const sp = (x = 0) => ({ x, v: 0 });
function spring(s, to, w, dt) {
  const d = s.x - to, k = w * dt, e = 1 / (1 + k + 0.48 * k * k + 0.235 * k * k * k), tmp = (s.v + w * d) * dt;
  s.v = (s.v - w * tmp) * e;
  s.x = to + (d + tmp) * e;
}

export function createScene({ host, labelsEl, hover, pick, wake }) {
  const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, powerPreference: 'high-performance' });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  renderer.toneMapping = THREE.NeutralToneMapping;
  renderer.domElement.className = 'b3-canvas';
  host.prepend(renderer.domElement);
  const labels = new CSS2DRenderer({ element: labelsEl });
  const scene = new THREE.Scene();  // no background: the deck behind the canvas is

  // A small studio of soft light panels, baked once into the environment map that lights every surface.
  {
    const room = new THREE.Scene();
    room.add(new THREE.Mesh(new THREE.BoxGeometry(60, 30, 60), new THREE.MeshBasicMaterial({ color: 0x171c27, side: THREE.BackSide })));
    const panel = (color, power, w, h, x, y, z) => {
      const m = new THREE.Mesh(new THREE.PlaneGeometry(w, h), new THREE.MeshBasicMaterial({ color: new THREE.Color(color).multiplyScalar(power), side: THREE.DoubleSide }));
      m.position.set(x, y, z);
      m.lookAt(0, 0, 0);
      room.add(m);
    };
    panel('#ffffff', 7, 26, 14, 0, 14, 0);
    panel('#aebcff', 4, 14, 10, -28, 6, 8);
    panel('#ffdcbc', 3, 12, 8, 26, 5, -14);
    const pm = new THREE.PMREMGenerator(renderer);
    scene.environment = pm.fromScene(room, 0.035).texture;
    scene.environmentIntensity = 0.5;
    pm.dispose();
  }
  scene.add(new THREE.HemisphereLight(0xc4ceff, 0x0c0f15, 0.45));
  const key = new THREE.DirectionalLight(0xfff3e4, 2.3);
  key.castShadow = true;
  key.shadow.mapSize.set(2048, 2048);
  key.shadow.radius = 6;
  key.shadow.bias = -0.0004;
  key.shadow.normalBias = 0.04;
  scene.add(key, key.target);

  const mat = (color, o = {}) => new THREE.MeshStandardMaterial({ color, roughness: 0.6, metalness: 0, ...o });
  const rbox = (w, h, d, r) => new RoundedBoxGeometry(w, h, d, 3, r);
  // shadow: 1 casts, 2 receives, 3 both.
  function solid(geo, material, x, y, z, shadow, parent) {
    const m = new THREE.Mesh(geo, material);
    m.position.set(x, y, z);
    m.castShadow = !!(shadow & 1);
    m.receiveShadow = !!(shadow & 2);
    parent.add(m);
    return m;
  }
  // The ground: clear but for the shadows the lanes and bays cast on it.
  const floor = solid(new THREE.PlaneGeometry(500, 500), new THREE.ShadowMaterial({ opacity: 0.45 }), 0, 0, 0, 2, scene);
  floor.rotation.x = -Math.PI / 2;

  function canvasTexture(w, h, draw) {
    const cv = document.createElement('canvas');
    cv.width = w; cv.height = h;
    draw(cv.getContext('2d'));
    const tex = new THREE.CanvasTexture(cv);
    tex.colorSpace = THREE.SRGBColorSpace;
    return tex;
  }
  // Belt tread: fine cross ribs and a faint arrow per rib, so the motion reads without shouting.
  const tread = canvasTexture(128, 128, (g) => {
    g.fillStyle = '#171b25'; g.fillRect(0, 0, 128, 128);
    for (let x = 0; x < 128; x += 32) {
      g.fillStyle = '#0e1118'; g.fillRect(x, 0, 3, 128);
      g.fillStyle = '#232a38'; g.fillRect(x + 3, 0, 2, 128);
      g.strokeStyle = 'rgba(147,171,255,.13)'; g.lineWidth = 3; g.lineCap = 'round'; g.lineJoin = 'round';
      g.beginPath(); g.moveTo(x + 13, 48); g.lineTo(x + 22, 64); g.lineTo(x + 13, 80); g.stroke();
    }
  });
  // The stretch of belt a card went back along: amber, its chevrons pointing back (right to left).
  const backTread = canvasTexture(128, 128, (g) => {
    g.fillStyle = '#3a2a0c'; g.fillRect(0, 0, 128, 128);
    for (let x = 0; x < 128; x += 32) {
      g.fillStyle = '#241a07'; g.fillRect(x, 0, 3, 128);
      g.strokeStyle = 'rgba(243,196,108,.8)'; g.lineWidth = 4; g.lineCap = 'round'; g.lineJoin = 'round';
      g.beginPath(); g.moveTo(x + 22, 46); g.lineTo(x + 12, 64); g.lineTo(x + 22, 82); g.stroke();
    }
  });
  const glowTex = canvasTexture(128, 128, (g) => {
    const r = g.createRadialGradient(64, 64, 0, 64, 64, 64);
    r.addColorStop(0, 'rgba(255,255,255,1)'); r.addColorStop(0.45, 'rgba(255,255,255,.42)'); r.addColorStop(1, 'rgba(255,255,255,0)');
    g.fillStyle = r; g.fillRect(0, 0, 128, 128);
  });

  const G = {
    slab: rbox(69, 0.2, 2.36, 0.09), rim: rbox(69.14, 0.12, 2.5, 0.05), beltBody: new THREE.BoxGeometry(36.4, 0.14, 1.6), tread: new THREE.PlaneGeometry(36, 1.5),
    rail: new THREE.BoxGeometry(36.8, 0.1, 0.07), roller: new THREE.CylinderGeometry(0.17, 0.17, 1.74, 20), pad: rbox(2.5, PAD_H, 2.0, 0.09), glow: new THREE.PlaneGeometry(5.4, 2.3),
    rowHit: new THREE.BoxGeometry(69, 0.9, 2.5), bay: rbox(16, 0.2, 9, 0.16), bayRim: rbox(16.16, 0.12, 9.16, 0.05), crate: rbox(1.8, 0.86, 1.5, 0.15), lid: rbox(1.94, 0.17, 1.64, 0.075),
    lamp: new THREE.BoxGeometry(0.62, 0.1, 0.05), cardHit: new THREE.BoxGeometry(15.2, 1.3, 2.1),
    // One length long, stretched between the two steps; the ghost is a crate's outline.
    back: new THREE.PlaneGeometry(1, 1.5), backEdge: new THREE.BoxGeometry(1, 0.05, 0.07), ghost: new THREE.EdgesGeometry(new THREE.BoxGeometry(1.8, 0.86, 1.5)),
  };
  const M = {
    beltBody: mat('#0b0d13', { roughness: 0.8 }), metal: mat('#3b4458', { roughness: 0.38, metalness: 0.75 }), rim: mat('#262d3c', { roughness: 0.7 }), rimBad: mat('#5a2b2e', { roughness: 0.7 }),
    bay: mat('#131721', { roughness: 0.86 }), hit: new THREE.MeshBasicMaterial({ visible: false }),
  };
  const maxAniso = renderer.capabilities.getMaxAnisotropy();

  // ---- the labels: the panel's own elements, each placed once ----
  const placed = new Map();  // element -> its CSS2DObject
  function label(el, x, y, z, cx, parent) {
    let o = placed.get(el);
    if (!o) { o = new CSS2DObject(el); placed.set(el, o); }
    o.position.set(x, y, z);
    o.center.set(cx, 0.5);
    if (o.parent !== parent) parent.add(o);
    return o;
  }
  function unlabel(el) { const o = placed.get(el); if (o) { o.removeFromParent(); placed.delete(el); } }

  // ---- the lanes: built again only when how many there are, or which of them are stuck, changes ----
  // shape starts as no shape at all, so the first frame builds the floor (its bays too) even with no lane on it.
  let rows = [], shape = null, lanes = 0;
  const bayGroup = new THREE.Group();
  scene.add(bayGroup);
  function dropRow(row) {
    row.group.removeFromParent();
    for (const m of row.own) m.dispose();
    for (const el of row.els) unlabel(el);
  }
  function makeRow(r, stuck) {
    const z = RZ(r), group = new THREE.Group(), own = [];
    const mine = (m) => { own.push(m); return m; };
    solid(G.rim, stuck ? M.rimBad : M.rim, 0.5, 0.06, z, 1, group);
    const slabMat = mine(mat(stuck ? '#24161a' : '#151922', { roughness: 0.86, emissive: C_ACCENT, emissiveIntensity: 0 }));
    solid(G.slab, slabMat, 0.5, 0.1, z, 2, group);
    solid(G.beltBody, M.beltBody, 1, 0.27, z, 3, group);
    const tex = mine(tread.clone());
    tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
    tex.repeat.set(12, 1);
    tex.anisotropy = maxAniso;
    solid(G.tread, mine(mat('#ffffff', { map: tex, roughness: 0.92 })), 1, BELT_Y, z, 2, group).rotation.x = -Math.PI / 2;
    for (const s of [-1, 1]) solid(G.rail, M.metal, 1, 0.33, z + s * 0.82, 1, group);
    for (const x of [-17.3, 19.3]) solid(G.roller, M.metal, x, 0.24, z, 1, group).rotation.x = Math.PI / 2;
    const pads = [0, 1, 2, 3, 4, 5].map((i) => ({ mesh: solid(G.pad, mine(mat(PAD.todo, { roughness: 0.5, emissive: 0x000000 })), SX(i), BELT_Y + PAD_H / 2, z, 3, group), state: 'todo' }));
    const glow = new THREE.Mesh(G.glow, mine(new THREE.MeshBasicMaterial({ map: glowTex, color: stuck ? C_BAD : C_ACCENT, transparent: true, opacity: 0, blending: THREE.AdditiveBlending, depthWrite: false, toneMapped: false })));
    glow.rotation.x = -Math.PI / 2;
    glow.position.set(0, BELT_Y + 0.015, z);
    group.add(glow);
    // A card that went back: the amber stretch over the tread with amber edges, and the ghost on the pad it left.
    const backTex = mine(backTread.clone());
    backTex.wrapS = backTex.wrapT = THREE.RepeatWrapping;
    backTex.anisotropy = maxAniso;
    const backMat = mine(mat('#ffffff', { map: backTex, roughness: 0.8, emissive: C_WARN, emissiveIntensity: 0.18, transparent: true, opacity: 0 }));
    const back = solid(G.back, backMat, 0, BELT_Y + 0.006, z, 2, group);
    back.rotation.x = -Math.PI / 2;
    back.name = 'b3-back';
    const edgeMat = mine(new THREE.MeshBasicMaterial({ color: C_WARN, transparent: true, opacity: 0, toneMapped: false }));
    const edges = [-1, 1].map((s) => solid(G.backEdge, edgeMat, 0, BELT_Y + 0.03, z + s * 0.76, 0, group));
    const ghostMat = mine(new THREE.LineDashedMaterial({ color: C_WARN, dashSize: 0.16, gapSize: 0.1, transparent: true, opacity: 0, toneMapped: false }));
    const ghost = new THREE.LineSegments(G.ghost, ghostMat);
    ghost.computeLineDistances();
    ghost.position.set(0, PAD_TOP + 0.43, z);
    ghost.name = 'b3-ghost';
    group.add(ghost);
    [back, ...edges, ghost].forEach((m) => { m.visible = false; });
    const hit = solid(G.rowHit, M.hit, 0.5, 0.45, z, 0, group);
    hit.userData.row = true;
    scene.add(group);
    return { z, stuck, group, own, pads, slabMat, tex, glow, hit, els: [], key: null, live: false, hot: 0, isHot: false, speed: 0, glowA: 0, at: -1,
      back, backMat, backTex, edges, edgeMat, ghost, ghostMat, way: null, backA: 0 };
  }
  let bays = null;
  function layout(state) {
    const now = state.rows.map((r) => (r.stuck ? 's' : 'r')).join('');
    if (now !== shape) {
      shape = now;
      rows.forEach(dropRow);
      rows = state.rows.map((r, i) => makeRow(i, r.stuck));
      lanes = rows.length;
      // The bays sit below the last lane.
      bayGroup.clear();
      const edge = bayEdge(lanes);
      BAY_X.forEach((x) => { solid(G.bayRim, M.rim, x, 0.06, edge + 4.5, 1, bayGroup); solid(G.bay, M.bay, x, 0.1, edge + 4.5, 2, bayGroup); });
      bays = null;
      fit.lookAt = null;
      fit();
    }
    // Every element the panel hands over has its place; one it no longer hands over is taken off the floor.
    state.heads.forEach((el, i) => label(el, i === 0 ? -33.6 : i === 7 ? 20.2 : SX(i - 1), 0.3, HEAD_Z, i === 0 || i === 7 ? 0 : 0.5, scene));
    state.rows.forEach((r, i) => {
      const row = rows[i], els = [r.name, r.now, ...r.marks, r.label];
      row.els.filter((el) => !els.includes(el)).forEach(unlabel);
      row.els = els;
      label(r.name, -33.6, 0.3, row.z, 0, scene);
      label(r.now, 20.2, 0.3, row.z, 0, scene);
      r.marks.forEach((el, k) => label(el, SX(k), PAD_TOP + 0.3, row.z, 0.5, scene));
      // "← back to <step>": above the amber stretch, midway between its steps, clear of their pads' marks and the
      // lane above (the panel hides it while its card has not gone back).
      label(r.label, r.back ? (SX(r.back.to) + SX(r.back.from)) / 2 : 0, BELT_Y, row.z - 1.25, 0.5, scene);
    });
    if (!bays) {
      const edge = bayEdge(lanes);
      state.bays.forEach((el, j) => label(el, BAY_X[j] - 7.3, 0.3, edge + 0.95, 0, scene));
      bays = true;
    }
  }

  // ---- cards as crates, one a card, faded out and dropped once the card is gone ----
  const crates = new Map();
  function crate(c) {
    const k = { obj: new THREE.Group(), mat: mat(CRATE[c.kind] || CRATE.queued, { roughness: 0.52, transparent: true }), lamp: mat('#10131a', { roughness: 0.4, emissive: 0x000000, transparent: true }),
      target: new THREE.Vector3(), alpha: 0, px: null, show: false, inBay: false, kind: c.kind };
    solid(G.crate, k.mat, 0, 0.43, 0, 3, k.obj);
    solid(G.lid, k.mat, 0, 0.9, 0, 3, k.obj);
    solid(G.lamp, k.lamp, 0, 0.5, 0.76, 0, k.obj);
    k.hit = solid(G.cardHit, M.hit, 6.4, 0.6, 0, 0, k.obj);
    k.hit.userData.card = c.key;
    k.tag = null; k.badge = null;
    hang(k, 'tag', c.tag);
    hang(k, 'badge', c.badge);
    scene.add(k.obj);
    crates.set(c.key, k);
    return k;
  }
  // A card picked up from the queue takes over the crate of its queued issue (c.from), which then glides to its lane.
  function adopt(c, cards) {
    const k = c.from ? crates.get(c.from) : null;
    if (!k || cards.some((x) => x.key === c.from)) return null;
    crates.delete(c.from);
    crates.set(c.key, k);
    k.hit.userData.card = c.key;
    return k;
  }
  // The crate hangs the tag and the round badge the panel gives its card now: the tag beside it, the badge on its lid's
  // back corner. A card that left the floor and came back before its crate was gone (a refresh without it while the
  // browser tab was in the background and no frame ran, or within its fade) has a new tag; the crate
  // kept the old one, which the panel had taken off the page and the label step put back as it last was: with no words.
  const HANG = { tag: [1.35, 0.5, 0, 0], badge: [0.95, 1.1, -0.7, 0.5] };
  function hang(k, what, el) {
    if (k[what] === el) return;
    if (k[what]) unlabel(k[what]);
    k[what] = el || null;
    const [x, y, z, cx] = HANG[what];
    if (el) label(el, x, y, z, cx, k.obj);
  }
  function place(k, x, y, z, inBay, snap) {
    k.target.set(x, y, z);
    if (!k.px || snap) { k.px = sp(x); k.py = sp(y); k.pz = sp(z); k.lift = sp(0); }
    k.show = true;
    k.inBay = inBay;
  }

  // ---- camera: a slight perspective, framed to the free area (the details panel takes its share) ----
  const cam = new THREE.PerspectiveCamera(22, 1, 10, 500);
  const DIR = new THREE.Vector3(0, 44, 19).normalize(), LOOK = new THREE.Vector3(), v3 = new THREE.Vector3();
  const side = sp(0);
  // aside: the width the open details take off the floor's right, from the stylesheet (--b3-aside, app.css): 0 where
  // they open below the floor instead, as on a phone, where there is no room beside it. top and bottom: the bands
  // above and below the floor (--b3-top: the header strip and the deck's top readouts; --b3-bottom: its bottom ones).
  let W = 0, H = 0, aside = 0, top = 110, bottom = 40, bounds = [];
  const px = (x, y, z) => { v3.set(x, y, z).project(cam); return [(v3.x + 1) * W / 2, (1 - v3.y) * H / 2]; };
  function extent(d) {
    cam.position.copy(LOOK).addScaledVector(DIR, d);
    cam.lookAt(LOOK);
    cam.updateMatrixWorld();
    const e = [Infinity, Infinity, -Infinity, -Infinity];
    for (const b of bounds) { const [x, y] = px(b.x, b.y, b.z); e[0] = Math.min(e[0], x); e[1] = Math.min(e[1], y); e[2] = Math.max(e[2], x); e[3] = Math.max(e[3], y); }
    return e;
  }
  function fit() {
    if (!W || !H) return;
    const z0 = HEAD_Z - 1, z1 = bayEdge(lanes) + 9.3;
    if (fit.lookAt !== lanes) {
      fit.lookAt = lanes;
      LOOK.set(0.5, 0, (z0 + z1) / 2);
      bounds = [[-34.4, z0], [35.4, z0], [-34.4, z1], [35.4, z1]].map(([x, z]) => new THREE.Vector3(x, 0, z));
      key.position.set(-24, 48, LOOK.z + 16);
      key.target.position.copy(LOOK);
      const half = (z1 - z0) / 2 + 4;
      Object.assign(key.shadow.camera, { left: -42, right: 42, top: half, bottom: -half, near: 5, far: 130 });
      key.shadow.camera.updateProjectionMatrix();
    }
    // The header strip and the deck's readouts above and below; the details panel, when open beside the floor, takes its
    // width off the right.
    const L = 20, R = W - 20 - side.x * aside, T = top, B = H - bottom;
    cam.aspect = W / H;
    cam.zoom = 1;
    cam.clearViewOffset();
    cam.updateProjectionMatrix();
    let lo = 20, hi = 480;
    for (let i = 0; i < 22; i++) { const d = (lo + hi) / 2, e = extent(d); if (e[2] - e[0] > R - L || e[3] - e[1] > B - T) lo = d; else hi = d; }
    let e = extent(hi);
    // A stage much taller than it is wide (a phone's window filled, issue 449): from the farthest it stands, the floor
    // is still wider than the stage, so the lens widens (a zoom below 1) until it fits.
    const k = Math.min((R - L) / (e[2] - e[0]), (B - T) / (e[3] - e[1]));
    if (k < 1) { cam.zoom = k; cam.updateProjectionMatrix(); e = extent(hi); }
    cam.setViewOffset(W, H, (e[0] + e[2]) / 2 - (L + R) / 2, (e[1] + e[3]) / 2 - (T + B) / 2, W, H);
    // Text is sized by the floor (--u: the pixels of one length of it at the lanes, --ub at the bays), so it scales
    // with the floor and never crowds it.
    const one = (z) => `${(px(1, 0, z)[0] - px(0, 0, z)[0]).toFixed(3)}px`;
    host.style.setProperty('--u', one(RZ(0)));
    host.style.setProperty('--ub', one(bayEdge(lanes) + 3.1));
  }
  function resize() {
    const w = host.clientWidth, h = host.clientHeight;
    if (!w || !h || (w === W && h === H)) return;
    W = w; H = h;
    const css = window.getComputedStyle(host), len = (k, d) => { const v = parseFloat(css.getPropertyValue(k)); return Number.isFinite(v) ? v : d; };
    aside = len('--b3-aside', 0);
    top = len('--b3-top', 110);
    bottom = len('--b3-bottom', 40);
    renderer.setSize(W, H);
    labels.setSize(W, H);
    fit.lookAt = null;
    fit();
    wake();
  }
  if (typeof window.ResizeObserver === 'function') new window.ResizeObserver(resize).observe(host);

  // ---- hover and click ----
  const ray = new THREE.Raycaster(), ptr = new THREE.Vector2();
  function aim(e) {
    const r = renderer.domElement.getBoundingClientRect();
    ptr.set(((e.clientX - r.left) / r.width) * 2 - 1, -((e.clientY - r.top) / r.height) * 2 + 1);
    ray.setFromCamera(ptr, cam);
    const hits = rows.map((w) => w.hit).concat(Array.from(crates.values(), (k) => k.hit));
    for (const h of ray.intersectObjects(hits, false)) {
      if (h.object.userData.row) { const row = rows.find((w) => w.hit === h.object); if (row && row.key) return row.key; continue; }
      const k = crates.get(h.object.userData.card);
      if (k && k.show && k.inBay) return h.object.userData.card;
    }
    return null;
  }
  renderer.domElement.addEventListener('pointermove', (e) => { const k = aim(e); renderer.domElement.style.cursor = k ? 'pointer' : ''; hover(k, e.clientX, e.clientY); });
  renderer.domElement.addEventListener('pointerleave', () => hover(null, 0, 0));
  renderer.domElement.addEventListener('click', (e) => pick(aim(e)));

  let t = 0;
  return {
    // The host's size changed (the panel went full screen or came back): the floor is fitted to it at once.
    resize,
    // One frame: dt seconds since the last; with motion off, everything is at once where it goes and the treads stand still.
    // Returns true once nothing on the floor moves or pulses: each spring and fade within a 500th of where it goes, no
    // tread running and, with motion on, no running or stuck card's light and no step pad of a running card pulsing.
    frame(state, dt) {
      if (!W) resize();
      layout(state);
      const motion = state.motion;
      t += dt;
      const k = motion ? 1 - Math.exp(-dt * 5) : 1, pulse = motion ? 0.5 + 0.5 * Math.sin(t * 2.6) : 0.75;
      const to = state.open ? 1 : 0;
      if (Math.abs(side.x - to) > 0.0004 || Math.abs(side.v) > 0.0004) { if (motion) spring(side, to, 7, dt); else { side.x = to; side.v = 0; } fit(); }
      let busy = Math.abs(side.x - to) > 0.0004 || Math.abs(side.v) > 0.0004;
      const off = (a, b) => Math.abs(a - b) > 0.002, offC = (a, b) => off(a.r, b.r) || off(a.g, b.g) || off(a.b, b.b);
      const rests = (s, at) => !off(s.x, at) && !off(s.v, 0);
      for (const c of crates.values()) c.show = false;
      const edge = bayEdge(lanes);
      for (const c of state.cards) {
        if (c.row === null && c.bay === null && !crates.has(c.key)) continue;
        const kk = crates.get(c.key) || adopt(c, state.cards) || crate(c);
        hang(kk, 'tag', c.tag);
        hang(kk, 'badge', c.badge);
        kk.kind = c.kind;
        if (c.row !== null) place(kk, SX(c.at), PAD_TOP, rows[c.row].z, false, !motion);
        else if (c.bay !== null) place(kk, BAY_X[c.bay] - 6.4, BAY_TOP, edge + 3.1 + 2.3 * c.slot, true, !motion);
      }
      state.rows.forEach((r, i) => {
        const row = rows[i];
        row.key = r.key; row.live = r.live; row.isHot = r.hot; row.at = r.at; row.way = r.back || null;
        r.steps.forEach((s, j) => { row.pads[j].state = s; });
      });
      for (const [key, c] of crates) {
        if (c.px) {
          if (motion) {
            spring(c.px, c.target.x, 3.4, dt); spring(c.py, c.target.y, 3.4, dt); spring(c.pz, c.target.z, 3.4, dt);
            // A crate lifts off its pad while it has ground to cover, and sets down as it arrives.
            const lift = Math.min(1.5, 0.3 * Math.hypot(c.target.x - c.px.x, c.target.z - c.pz.x));
            spring(c.lift, lift, 6, dt);
            busy ||= !rests(c.px, c.target.x) || !rests(c.py, c.target.y) || !rests(c.pz, c.target.z) || !rests(c.lift, lift);
          }
          c.obj.position.set(c.px.x, c.py.x + c.lift.x, c.pz.x);
        }
        c.alpha += ((c.show ? 1 : 0) - c.alpha) * k;
        if (!c.show && c.alpha < 0.01 && !state.cards.some((x) => x.key === key)) {
          if (c.tag) unlabel(c.tag);
          if (c.badge) unlabel(c.badge);
          c.obj.removeFromParent(); c.mat.dispose(); c.lamp.dispose(); crates.delete(key);
          continue;
        }
        c.obj.visible = c.alpha > 0.01;
        c.mat.opacity = c.lamp.opacity = c.alpha;
        c.mat.color.lerp(C_CRATE[c.kind] || C_CRATE.queued, k);
        const lamp = c.kind === 'run' ? C_ACCENT : c.kind === 'blocked' ? C_BAD : BLACK;
        c.lamp.emissive.lerp(lamp, k);
        c.lamp.emissiveIntensity = 1.1 + 0.5 * pulse;
        busy ||= off(c.alpha, c.show ? 1 : 0) || offC(c.mat.color, C_CRATE[c.kind] || C_CRATE.queued) || offC(c.lamp.emissive, lamp)
          || (motion && c.obj.visible && lamp !== BLACK);
      }
      for (const row of rows) {
        const c = row.key ? crates.get(row.key) : null;
        row.speed += ((row.live && motion ? 1 : 0) - row.speed) * (motion ? 1 - Math.exp(-dt * 1.5) : 1);
        row.tex.offset.x -= dt * 0.16 * row.speed;
        row.hot += ((row.isHot ? 1 : 0) - row.hot) * k;
        row.slabMat.emissiveIntensity = 0.075 * row.hot;
        row.glowA += ((row.key ? 1 : 0) - row.glowA) * k;
        row.glow.material.opacity = row.glowA * (row.live ? 0.42 + 0.2 * pulse : 0.4);
        if (c && c.px) row.glow.position.x = c.px.x;
        // The way back: amber from the step the card went back to to the one it left, the ghost on that one. Its
        // chevrons run back (right to left) while the crate travels back, and stand still once it is there; with motion
        // off they never move. Only a crate moving left travels back: one going forward again (Review 2 on to Fix 2,
        // the way back kept until it moves on past Fix) leaves them still. Fading out, it stays where it was.
        const way = row.way;
        row.backA += ((way ? 1 : 0) - row.backA) * k;
        if (way) {
          const x0 = SX(way.to), x1 = SX(way.from), len = x1 - x0;
          row.back.scale.x = len; row.back.position.x = (x0 + x1) / 2;
          row.backTex.repeat.set(len / 3, 1);
          for (const e of row.edges) { e.scale.x = len; e.position.x = (x0 + x1) / 2; }
          row.ghost.position.x = x1;
          if (motion && c && c.px && c.px.x - c.target.x > 0.05) row.backTex.offset.x += dt * 0.6;
        }
        busy ||= row.speed > 0.002 || off(row.hot, row.isHot ? 1 : 0) || off(row.glowA, row.key ? 1 : 0) || off(row.backA, way ? 1 : 0)
          || (motion && row.live && row.glowA > 0.01) || Boolean(way && motion && c && c.px && c.px.x - c.target.x > 0.05);
        const seen = row.backA > 0.01;
        for (const m of [row.back, ...row.edges, row.ghost]) m.visible = seen;
        row.backMat.opacity = row.edgeMat.opacity = row.ghostMat.opacity = row.backA;
        for (const p of row.pads) {
          const m = p.mesh.material, s = p.state === 'skipped' ? 0.45 : 1;
          m.color.lerp(C_PAD[p.state] || C_PAD.todo, k);
          m.emissive.lerp(C_GLOW[p.state] || BLACK, k);
          m.emissiveIntensity = p.state === 'now' ? 0.7 + 0.35 * pulse : 0.6;
          p.mesh.scale.y += (s - p.mesh.scale.y) * k;
          p.mesh.position.y = BELT_Y + (PAD_H / 2) * p.mesh.scale.y;
          busy ||= offC(m.color, C_PAD[p.state] || C_PAD.todo) || offC(m.emissive, C_GLOW[p.state] || BLACK) || off(p.mesh.scale.y, s)
            || (motion && p.state === 'now');
        }
      }
      if (!W || !H) return false;
      // The words first: a lanes' rebuild above took each lane's label and status off the page, and only this puts them
      // back. Drawn after the floor, a WebGL draw that throws (three.js reading a shader's log from a context Safari
      // has lost, as on an iPad back from the background) left every lane's words off until a draw went through.
      labels.render(scene, cam);
      renderer.render(scene, cam);
      return !busy;
    },
  };
}
