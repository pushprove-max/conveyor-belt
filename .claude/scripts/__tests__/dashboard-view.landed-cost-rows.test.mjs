// SPDX-License-Identifier: Apache-2.0
// Landed and Cost keep their rows by card (issue 547): each new part drew every row anew, so the focus, a selection
// and an open tip in a row were lost at each change. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { T0, iso, clone, boot, panel, tick, later, settle, full, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

const nodes = (el) => Array.from(el.querySelectorAll('*'));
// Each node is the very node it was (identity, never an equal copy).
const same = (now, was, what) => {
  assert.equal(now.length, was.length, what);
  now.forEach((n, i) => assert.ok(n === was[i], `${what}: node ${i} (${n.tagName}.${n.className}) is a new node`));
};

// Bug it catches: a new Landed part with one more card drew every card's row again; the overall time's tip the owner
// had tapped open closed, and the Cost link they had focused lost the focus, at the next part.
test('a new Landed and Cost part or history with one more card keeps the other rows as the same nodes', async () => {
  const w = boot({ feed: true });
  const es = w.sources[0], data = full();
  data.panels.landed.data.cards[0].earlier = [{ card: 'c5-6', start: iso(T0 - 9000000), end: iso(T0 - 8000000) }];
  es.readyState = 1; es.emit('open');
  es.emit('snapshot', data);
  const landed = panel(w, 'landed'), cost = panel(w, 'cost');
  // A card's row found by its issue, as the page shows it now.
  const rowOf = (p, n) => Array.from(p.querySelectorAll('li.row')).find((li) => li.querySelector(':scope > .row-main > .issue').textContent === `#${n}`);
  const lrow = (n) => rowOf(landed, n), crow = (n) => rowOf(cost, n);
  const l1 = lrow(7), l2 = lrow(8), lnodes = [nodes(l1), nodes(l2)];
  const c1 = crow(63), c2 = crow(7), cnodes = [nodes(c1), nodes(c2)];
  assert.ok(l1 && l2 && c1 && c2, 'each row is drawn under its key');
  // The overall time's tip tapped open, and a Cost row's issue link focused.
  const overall = l1.querySelector('[data-tip]');
  // jsdom lays nothing out: the overall time is 50 px lower for each row above its own, 20 px high.
  overall.getBoundingClientRect = () => {
    const top = Array.from(l1.parentNode.children).indexOf(l1) * 50;
    return { left: 0, top, right: 100, bottom: top + 20, width: 100, height: 20 };
  };
  const frames = () => { for (const f of w.frames.splice(0)) f(); };
  overall.click();
  const pop = w.document.getElementById('tip');
  assert.equal(pop.hidden, false, 'the tapped overall time shows its tip');
  assert.equal(pop.style.top, '24px', 'the tip opens under the overall time of the first row');
  const link = c1.querySelector('a.issue');
  link.focus();
  assert.ok(w.document.activeElement === link, 'the Cost link has the focus');
  // After a new part or history (by: what came, n: the issue of the card it brought): each other row and its nodes kept.
  const kept = (by, n) => {
    assert.ok(lrow(n), `Landed draws the new card after ${by}`);
    assert.ok(crow(n), `Cost draws the new card after ${by}`);
    assert.ok(lrow(7) === l1 && lrow(8) === l2, `Landed keeps each other row after ${by}`);
    same(nodes(l1), lnodes[0], `Landed card c5-7 keeps each of its nodes after ${by}`);
    same(nodes(l2), lnodes[1], `Landed card c6-8 keeps each of its nodes after ${by}`);
    assert.ok(crow(63) === c1 && crow(7) === c2, `Cost keeps each other row after ${by}`);
    same(nodes(c1), cnodes[0], `Cost card c3-63 keeps each of its nodes after ${by}`);
    same(nodes(c2), cnodes[1], `Cost card c5-7 keeps each of its nodes after ${by}`);
    assert.ok(l1.isConnected && c1.isConnected, `the kept rows are still on the page after ${by}`);
    assert.equal(pop.hidden, false, `the open tip stays open after ${by}`);
    assert.ok(w.document.activeElement === link, `the Cost link keeps the focus after ${by}`);
  };

  const lpart = clone(data.panels.landed);
  lpart.data.cards.unshift({ repo: 'sample', card: 'c9-11', issue: 11, title: 'Landed last', url: null, step: 'landed', time: iso(T0 - 60000), start: iso(T0 - 600000), tookSec: 540, usd: 0.25, reviews: 1, followups: [], sha: 'def', pushed: true });
  es.emit('panel', { id: 'landed', part: lpart, updatedAt: iso(T0) });
  const cpart = clone(data.panels.cost);
  cpart.data.cards.perCard.push({ repo: 'sample', card: 'c9-11', issue: 11, title: 'Landed last', url: null, todayUsd: 0.25, weekUsd: 0.25, state: 'landed' });
  es.emit('panel', { id: 'cost', part: cpart, updatedAt: iso(T0) });
  tick(w, 1000);
  frames();
  kept('a new live part', 11);
  // Bug it catches: the tip stayed where the row was when it opened, over the new row now drawn there.
  assert.equal(pop.style.top, '74px', 'the open tip follows its row down one place');

  // Bug it catches: a newer history drew Landed and Cost whole, so it drew every row again, though only one card came.
  const hist = clone(full().panels);
  hist.landed.data.cards.push({ repo: 'sample', card: 'c4-12', issue: 12, title: 'Landed early', url: null, step: 'landed', time: iso(T0 - 9000000), start: iso(T0 - 9600000), tookSec: 600, usd: 0.5, reviews: 1, followups: [], sha: 'fed', pushed: true });
  hist.cost.data.cards.perCard.push({ repo: 'sample', card: 'c4-12', issue: 12, title: 'Landed early', url: null, todayUsd: 0.5, weekUsd: 0.5, state: 'landed' });
  w.historyBody = { updatedAt: iso(T0), panels: hist };
  w.clock += 60000;
  later(w);
  await settle(); await settle();
  frames();
  kept('a newer history', 12);
});
