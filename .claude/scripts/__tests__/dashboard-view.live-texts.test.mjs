// SPDX-License-Identifier: Apache-2.0
// Bug (#560, like #337): a text the Board rewrites in place each second (a timer, a count, a cost) wrapped onto a new
// line and back as it ticked, so its card grew and shrank by a line and the page under it moved. Each live text is
// one unwrapped run of fixed-width digits (white-space: nowrap, tabular-nums), and the per-second update writes to no
// other text. jsdom does no layout, so the rules are read from app.css, as the other Board layout tests do.
import assert from 'node:assert/strict';
import { css as raw, T0, iso, boot, panel, deliver, tick, full, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const css = raw.replace(/\/\*[\s\S]*?\*\//g, '');

// Every live text, as app.css names it. A Belt view label is written inside .b3-lb or .b3-ro, which hold it unwrapped.
const LIVE = ['.since', '.live-quiet', '.live-cost', '.board-took', '.tl-total', '.tl-dur', '.tl-tip', '.expires', '[data-age-from]', '#clock', '#updated', '.b3-lb', '.b3-ro', '.b3-row-min'];

// The declarations of every rule whose selector list names `sel` exactly, merged in order (a later one wins).
function decls(sel) {
  const out = {};
  for (const [, sels, body] of css.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
    if (!sels.split(',').map((s) => s.trim()).includes(sel)) continue;
    for (const d of body.split(';')) {
      const i = d.indexOf(':');
      if (i > 0) out[d.slice(0, i).trim()] = d.slice(i + 1).trim();
    }
  }
  return out;
}

// The page as the tests draw it, with every live text in it: a card whose review is running (its "Every step" open to
// draw, its last output 5 s ago), a Needs-you decision asked 3 min ago, a declined line 29 min from leaving, the
// Board's feed down 30 s, and a check run going for 10 min.
function data() {
  const d = full();
  const card = d.panels.belt.data.cards[0];
  card.live = { turns: 3, lastOutputAt: iso(T0 - 5000), action: 'Bash: npm test' };
  card.track.detail.forEach((s, i) => { s.state = i < 8 ? 'done' : i === 8 ? 'now' : 'todo'; s.sec = i < 8 ? 60 : null; });
  card.track.detailAt = 8;
  d.panels.needs.data.decisions = [{ repo: 'sample', id: 'q-ship', askedAt: iso(T0 - 180000), question: 'Ship it?', options: ['Yes', 'No'], proposedDefault: 'Yes', source: 'main' }];
  d.panels.declined.data.lines[0].time = iso(T0 - 7 * 86400000 + 1800000 - 30000);
  d.panels.health.data.stream = { live: false, heardAt: iso(T0 - 30000), since: null, error: 'the live stream is down', writtenAt: iso(T0 - 30000) };
  d.panels.board.data.checkRuns = [{ repo: 'sample', name: 'nightly', sha: '0123456789ab', started: iso(T0 - 600000), ended: null, result: null,
    lanes: [{ name: 'busy-0', state: 'running', started: iso(T0 - 90000), sec: null }], counts: { passed: 0, failed: 0, running: 1, queued: 0, reused: 0 }, done: 0, all: 1, leftSec: null }];
  return d;
}

test('each live text never wraps and has digits all one width; where its row wraps it holds its width', () => {
  for (const sel of LIVE) {
    const r = decls(sel);
    assert.equal(r['white-space'], 'nowrap', `${sel}: a tick must not wrap it onto a new line`);
    assert.equal(r['font-variant-numeric'], 'tabular-nums', `${sel}: a tick must not change its width digit by digit`);
  }
  // The overall timer in the card's head row, a Needs-you "… ago" and the cost in a meta row, a phone's Belt list time
  // (rows that wrap): each holds room for its longest usual text, all of it. A width that fits only part of the text (the
  // cost's dollars, not its "999k tokens so far") still lets a tick that adds a digit push the text onto a new line.
  const held = { '.card-times .since': '10 h 05 min overall', '.row-meta > .since': '10 h 05 min ago', '.live-cost': '$100.00 · 999k tokens so far', '.b3-row-min': '10 h 05 min' };
  for (const [sel, text] of Object.entries(held)) {
    const m = /^(\d+)ch$/.exec(decls(sel)['min-width'] || '');
    assert.ok(m, `${sel}: holds its width`);
    assert.ok(Number(m[1]) >= text.length, `${sel}: ${m[1]}ch has no room for "${text}"`);
  }
  // The "Every step" total is a sentence: one line, cut to the card's width, its full text on hover and tap.
  const total = decls('.track-detail .tl-total');
  assert.equal(total['text-overflow'], 'ellipsis');
  assert.equal(total.overflow, 'hidden');
  assert.equal(total.contain, 'inline-size', 'the unwrapped line must not widen the card');
});

test('the four texts the audit found are live texts: the card\'s overall timer, its cost, the "Every step" total and a decision\'s "… ago"', () => {
  const w = boot();
  deliver(w, data());
  const live = (el, what) => { assert.ok(el, `${what} is drawn`); assert.ok(el.matches(LIVE.join(', ')), `${what} (${el.className}) is a live text`); };
  const belt = panel(w, 'belt');
  live(belt.querySelector('.row-main .card-times .since'), 'the "N overall" timer');
  live(belt.querySelector('.row-meta .num').parentElement, 'the cost counter');
  const total = belt.querySelector('.track-detail .tl-total');
  live(total, 'the "Every step" total');
  tick(w, 61000);
  assert.equal(total.dataset.tip, total.textContent, 'the cut total carries its full text, as it is now');
  const decision = Array.from(panel(w, 'needs').querySelectorAll('.row')).find((r) => r.textContent.includes('Ship it?'));
  live(decision && decision.querySelector('.row-meta > .since'), 'the decision\'s "… ago"');
});

// Each element with text of its own, keyed by its place (tag and index from the body), so a row drawn again in its
// place is the same text written again.
function texts(w) {
  const out = new Map();
  const walk = (el, path) => {
    const own = Array.from(el.childNodes).filter((n) => n.nodeType === 3).map((n) => n.data).join('');
    if (own.trim()) out.set(path, { el, own });
    Array.from(el.children).forEach((c, i) => walk(c, `${path}/${c.tagName}${i}`));
  };
  walk(w.document.body, 'BODY');
  return out;
}
// What the per-second update writes, over a second, another, then a minute (a text in minutes changes once a minute).
function written(w) {
  const out = new Set();
  let was = texts(w);
  for (const ms of [1000, 1000, 61000]) {
    tick(w, ms);
    const now = texts(w);
    now.forEach((t, path) => { const old = was.get(path); if (!old || old.own !== t.own) out.add(t.el); });
    was = now;
  }
  return Array.from(out);
}
const outside = (els) => els.filter((el) => !el.closest(LIVE.join(', '))).map((el) => `${el.tagName}.${el.className}: ${el.textContent}`);
const named = (els) => (sel) => els.some((el) => el.closest(sel));

for (const [tab, expect] of [
  ['overview', ['.card-times .since', '.track-now > .since', '.live-quiet', '.tl-total', '.tl-dur', '.row-meta > .since', '.expires', '[data-age-from]', '#clock', '#updated']],
  ['control', ['.board-took']],
  ['belt3d', ['.b3-lb', '.b3-ro', '.b3-row-min']],
]) {
  test(`the ${tab} tab: each text the per-second update writes is a live text`, () => {
    const w = boot({ tab });
    deliver(w, data());
    const els = written(w);
    assert.deepEqual(outside(els), [], 'a text that ticks but may wrap');
    // The fixture draws every live text of the tab, so a new one is caught.
    for (const sel of expect) assert.ok(named(els)(sel), `${sel} ticks in this fixture`);
  });
}
