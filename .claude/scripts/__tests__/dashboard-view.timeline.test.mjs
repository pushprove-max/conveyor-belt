// SPDX-License-Identifier: Apache-2.0
// "Every step", a card's timeline, while the owner reads it. The owner opened it on a card whose step was running and
// the page jumped about once a second, so they could neither scroll nor read: the one-second tick put the axis again,
// every bar's place and length with it, and each bar's time back in its place (a node taken out and put in again), and
// a redraw gave the focus back to the timeline in a way that scrolls it into view. The tick now changes the running
// bar's width and the time texts only; a redraw keeps the timeline open and the reader's place. Shared setup:
// dashboard-view.helpers.mjs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { T0, iso, clone, boot, panel, deliver, next, tick, trackOf, counts, full } from './dashboard-view.helpers.mjs';

// A card picked up 1000 s ago: built, reviewed, and its tests running for the last 5 s.
const P0 = T0 - 1000000;
const at = (s) => iso(P0 + s * 1000);
const DONE = [
  { name: 'queued', state: 'done', sec: 60, at: at(0) }, { name: 'picked', state: 'done', sec: null, at: at(0) },
  { name: 'building', state: 'done', sec: 600, at: at(600) }, { name: 'review 1 (GO)', state: 'done', sec: 395, at: at(995), counts: counts(0, 0, 0, 0) },
];
const running = () => trackOf('++++>.', 'tests', { since: at(995), records: [...clone(DONE), { name: 'tests', state: 'now', sec: null }] });
// The belt with three cards, each with its tests running.
function belt3() {
  const data = full();
  const cards = data.panels.belt.data.cards;
  cards.push({ ...clone(cards[0]), card: 'c8-64', issue: 64, title: 'Third card' });
  cards.forEach((c) => { c.track = running(); });
  return data;
}
const body = (w, id) => panel(w, id).querySelector('.panel-body');
const timelines = (w, id) => Array.from(panel(w, id).querySelectorAll('details.track-detail'));
// What a panel's height and place are made of: its fill, its body's cut, its span and place in the grid, its rows.
const box = (w, id) => { const p = panel(w, id); return [p.style.minHeight, body(w, id).style.maxHeight, p.dataset.span, p.dataset.row, p.dataset.col, p.dataset.rows]; };
// The reader's place: the page scrolled down 300 px and the panel's body 120 px. jsdom lays nothing out, so a focus
// moves the page and the body as a browser does: unless asked not to, it scrolls its element into view (here, to 0).
function reading(w, id) {
  Object.defineProperty(w, 'scrollY', { value: 300, writable: true, configurable: true });
  body(w, id).scrollTop = 120;
  const focus = w.HTMLElement.prototype.focus;
  w.HTMLElement.prototype.focus = function (opt) {
    if (!(opt && opt.preventScroll)) { w.scrollY = 0; body(w, id).scrollTop = 0; }
    return focus.call(this, opt);
  };
}
const place = (w, id) => [w.scrollY, body(w, id).scrollTop];
// Each finished bar's place and length, and where each bar's time sits (on its bar or in its lane), in a panel.
const bars = (p) => Array.from(p.querySelectorAll('.tl-item')).map((li) => {
  const bar = li.querySelector('.tl-bar'), dur = li.querySelector('.tl-dur');
  return [li.dataset.state === 'now' ? 'now' : `${bar.style.left} ${bar.style.width}`, dur.parentNode.className];
});

test('a tick moves no finished bar, and a running bar that grows past a quarter of the axis leaves its time where it was', () => {
  const w = boot();
  const data = full();
  // Its tests have run 300 s of a 1300 s card: under a quarter of the axis at the draw, its time beside it in the lane.
  const p0 = T0 - 1300000, ago = (s) => iso(p0 + s * 1000);
  data.panels.belt.data.cards[0].track = trackOf('++++>.', 'tests', { since: ago(1000), records: [
    { name: 'picked', state: 'done', sec: null, at: ago(0) }, { name: 'building', state: 'done', sec: 600, at: ago(600) },
    { name: 'review 1 (GO)', state: 'done', sec: 400, at: ago(1000) }, { name: 'tests', state: 'now', sec: null }] });
  deliver(w, data);
  const p = panel(w, 'belt'), row = p.querySelector('li[data-key="sample:c3-63"]');
  row.querySelector('details.track-detail').open = true;
  const now = row.querySelector('.tl-item[data-state="now"]');
  assert.equal(now.querySelector('.tl-dur').parentNode.className, 'tl-lane');
  const before = bars(p);
  const seen = new w.MutationObserver(() => {});
  seen.observe(p, { childList: true, subtree: true });
  // Two minutes on: past a quarter of the axis drawn (1300 s and a tenth), then on to its end.
  for (let i = 0; i < 120; i += 1) tick(w, 1000);
  assert.ok(parseFloat(now.querySelector('.tl-bar').style.width) > 25, `it grew past a quarter: ${now.querySelector('.tl-bar').style.width}`);
  assert.deepEqual(bars(p), before, 'the finished bars kept their places and lengths, and every time where it was');
  assert.equal(seen.takeRecords().filter((r) => [...r.addedNodes, ...r.removedNodes].some((n) => n.nodeType === 1)).length, 0, 'no node moved');
  assert.equal(now.querySelector('.tl-dur').textContent, '7 min');
  // Past the axis's end it grows no further, to the next draw.
  for (let i = 0; i < 120; i += 1) tick(w, 1000);
  const bar = now.querySelector('.tl-bar').style;
  assert.equal((parseFloat(bar.left) + parseFloat(bar.width)).toFixed(2), '100.00', 'it stops at the axis end');
  assert.deepEqual(bars(p), before);
});

test('the one-second tick moves the running bar and its time texts only: no node added, removed or moved, no height changed, no arrange', () => {
  const w = boot();
  deliver(w, belt3());
  timelines(w, 'belt').forEach((d) => { d.open = true; });
  reading(w, 'belt');
  const p = panel(w, 'belt');
  const nodes = p.querySelectorAll('*').length, was = box(w, 'belt'), where = place(w, 'belt'), drawn = bars(p);
  const now = p.querySelector('li[data-key="sample:c3-63"] .tl-item[data-state="now"]');
  assert.equal(now.querySelector('.tl-dur').textContent, '5 s');
  const width = now.querySelector('.tl-bar').style.width;
  // Every node added to or taken from the panel (a text replaced in place is not one), and every arrange: each one
  // measures every panel, and arrangeSoon asks for a frame.
  const seen = new w.MutationObserver(() => {});
  seen.observe(p, { childList: true, subtree: true });
  const gbcr = w.Element.prototype.getBoundingClientRect;
  let measured = 0;
  w.Element.prototype.getBoundingClientRect = function () { if (this.classList.contains('panel')) measured += 1; return gbcr.call(this); };
  const frames = w.frames.length;
  for (let i = 0; i < 10; i += 1) tick(w, 1000);
  const moved = seen.takeRecords().filter((r) => [...r.addedNodes, ...r.removedNodes].some((n) => n.nodeType === 1));
  assert.deepEqual(moved.map((r) => r.target.className), [], 'no element is added, removed or put back by the tick');
  assert.equal(p.querySelectorAll('*').length, nodes, 'the count of nodes in the panel');
  assert.deepEqual(box(w, 'belt'), was, "the panel's height and place");
  assert.deepEqual(bars(p), drawn, 'every finished bar keeps its place and length');
  assert.deepEqual(place(w, 'belt'), where, "the page's and the body's scroll");
  assert.equal(measured, 0, 'the tick never calls the panel arrange');
  assert.equal(w.frames.length, frames, 'nor asks for one');
  assert.ok(timelines(w, 'belt').every((d) => d.open), 'every timeline stays open');
  // What does move: the running bar and its time.
  assert.equal(now.querySelector('.tl-dur').textContent, '15 s', "the running bar's time counts on");
  assert.notEqual(now.querySelector('.tl-bar').style.width, width, 'and its bar grows');
});

test('with three timelines open, a refresh with the same cards and steps keeps all three open, the focus and both scroll positions', () => {
  const w = boot();
  const data = belt3();
  deliver(w, data);
  const dets = timelines(w, 'belt');
  assert.equal(dets.length, 3);
  dets.forEach((d) => { d.open = true; });
  // The owner clicked "Every step" on the second card: the focus is on it.
  dets[1].querySelector('summary').focus();
  reading(w, 'belt');
  const was = box(w, 'belt'), where = place(w, 'belt');
  // The same cards and steps, the tokens counted on: the belt is drawn again.
  data.panels.belt.data.cards.forEach((c) => { c.tokens = { claude: c.tokens.claude + 1000, codex: c.tokens.codex }; });
  const renders = panel(w, 'belt').dataset.renders;
  next(w, data);
  assert.notEqual(panel(w, 'belt').dataset.renders, renders, 'the belt was drawn again');
  assert.deepEqual(timelines(w, 'belt').map((d) => d.open), [true, true, true], 'all three stay open');
  assert.equal(w.document.activeElement, timelines(w, 'belt')[1].querySelector('summary'), 'the focus stays where it was');
  assert.deepEqual(place(w, 'belt'), where, "the page's and the body's scroll are where they were");
  assert.deepEqual(box(w, 'belt'), was, 'no height changed: no row did');
});

test('a refresh that adds a step to an open timeline keeps it open and the reader in place; only that timeline grows', () => {
  const w = boot();
  const data = belt3();
  deliver(w, data);
  timelines(w, 'belt').forEach((d) => { d.open = true; d.querySelector('summary').focus(); });
  reading(w, 'belt');
  const bars = () => timelines(w, 'belt').map((d) => d.querySelectorAll('.tl-item').length);
  const before = bars(), where = place(w, 'belt');
  // The third card's tests passed and it is landing.
  data.panels.belt.data.cards[2].track = trackOf('+++++.', 'landing', { since: iso(T0), records: [...clone(DONE),
    { name: 'tests passed', state: 'done', sec: 5, at: iso(T0) }, { name: 'landing', state: 'now', sec: null }] });
  next(w, data);
  assert.deepEqual(bars(), [before[0], before[1], before[2] + 1], "only that card's timeline grows, by the new step");
  assert.deepEqual(timelines(w, 'belt').map((d) => d.open), [true, true, true], 'it and the others stay open');
  assert.deepEqual(place(w, 'belt'), where, "the page's and the body's scroll are where they were");
});

// Landed today draws its rows anew from each new part: an open "Every step" there was closed by each refresh that
// changed the panel. Needs you keeps its rows.
test('"Every step" on Landed today and Needs you stays open through a refresh', () => {
  const w = boot();
  const data = full();
  const done = trackOf('++++++', '', { at: null, since: null, records: [...clone(DONE), { name: 'tests passed', state: 'done', sec: 5, at: at(1000) }] });
  data.panels.landed.data.cards.forEach((c) => { c.track = clone(done); });
  data.panels.needs.data.cards.blocked[0].track = trackOf('+++!..', '', { records: [...clone(DONE), { name: 'tests failed', state: 'failed', sec: 5, at: at(1000), why: 'exit 1' }] });
  deliver(w, data);
  const [, second] = timelines(w, 'landed');
  second.open = true;
  timelines(w, 'needs')[0].open = true;
  data.panels.landed.data.cards[0].usd = 3;
  data.panels.needs.data.cards.blocked[0].reason = 'tests failed three times';
  next(w, data);
  assert.deepEqual(timelines(w, 'landed').map((d) => d.open), [false, true], "Landed: that card's timeline stays open, the other closed");
  assert.equal(timelines(w, 'needs')[0].open, true, 'Needs you: it stays open');
});
