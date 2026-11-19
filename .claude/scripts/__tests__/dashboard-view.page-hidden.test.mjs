// SPDX-License-Identifier: Apache-2.0
// A page in a background tab (#567): it keeps what comes and draws nothing until it is shown again.
// Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { T0, iso, clone, OVERVIEW, boot, panel, pending, deliver, refresh, tick, seen, full, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
// Every change to the page's DOM from now on: takeRecords() gives the ones made so far, at once.
const watch = (w) => { const o = new w.MutationObserver(() => {}); o.observe(w.document, { subtree: true, childList: true, attributes: true, characterData: true }); return o; };

// Bug: a page left open in a background tab drew each live update as if it were in view, all day.
test('a hidden page draws none of ten updates, and draws the last once when shown again', () => {
  const w = boot({ feed: true });
  const es = w.sources[0];
  es.readyState = 1; es.emit('open');
  es.emit('snapshot', full());
  const before = Object.fromEntries(OVERVIEW.map((id) => [id, Number(panel(w, id).dataset.renders)]));
  seen(w, false);
  const o = watch(w);
  const snap = full();
  const gone = snap.panels.queue.data.next.pop().title;
  assert.ok(panel(w, 'queue').textContent.includes(gone));
  es.emit('snapshot', snap);
  for (let i = 1; i <= 9; i += 1) {
    const part = clone(full().panels.belt);
    part.data.cards[0].live = { turns: i, lastOutputAt: iso(T0 - 4000), action: 'Bash: npm test' };
    es.emit('panel', { id: 'belt', part, updatedAt: iso(T0) });
  }
  es.emit('error'); es.emit('open');
  assert.deepEqual(o.takeRecords(), [], 'nothing on the page changed while it was hidden');
  seen(w, true);
  assert.ok(es.readyState === 1 && w.sources.length === 1, 'the feed stayed open while hidden, and no other was opened');
  // Issue 599: only the panels whose part changed while hidden (the queue, the belt; Health, as the feed closed and
  // opened) are drawn again, once; every other panel keeps its render count, not drawn again whole by redrawAll().
  const changed = ['queue', 'belt', 'health'];
  for (const id of OVERVIEW) {
    assert.equal(Number(panel(w, id).dataset.renders), before[id] + (changed.includes(id) ? 1 : 0), `${id} ${changed.includes(id) ? 'drawn once' : 'not drawn'} when shown`);
  }
  assert.ok(panel(w, 'belt').textContent.includes('9 model replies'), 'the belt shows the last update');
  assert.ok(!panel(w, 'queue').textContent.includes(gone), 'the queue shows the snapshot kept');
});

// Bug (issue 599): a page in a background tab read alive.js and data.js every refresh period, all day, and when shown
// again drew every panel anew, the ones whose part had not changed too.
test('a hidden page reads nothing on refresh, and runs one refresh when shown that draws only what changed', () => {
  const w = boot();
  deliver(w, full());
  pending(w, 'alive.js').dispatchEvent(new w.Event('load'));
  const reads = () => Array.from(w.document.head.querySelectorAll('script[src^="alive.js"], script[src^="data.js"]'), (s) => s.getAttribute('src'));
  assert.deepEqual(reads(), []);
  const before = Object.fromEntries(OVERVIEW.map((id) => [id, Number(panel(w, id).dataset.renders)]));
  seen(w, false);
  refresh(w); refresh(w);
  assert.deepEqual(reads(), [], 'two refresh periods while hidden read nothing');
  seen(w, true);
  assert.deepEqual(reads().sort(), ['alive.js', 'data.js'], 'one refresh runs when shown');
  const snap = full();
  snap.panels.queue.data.next.pop();
  deliver(w, snap);
  for (const id of OVERVIEW) {
    assert.equal(Number(panel(w, id).dataset.renders), before[id] + (id === 'queue' ? 1 : 0), `${id} ${id === 'queue' ? 'drawn once' : 'keeps its render count'}`);
  }
});

// Bug (issue 599): a page hidden for over 45 s, with no heartbeat read while hidden, said "Feed stopped" when shown,
// judging the heartbeat it read before it was hidden, before the refresh run then read the new one.
test('a page shown after a long hide does not say Feed stopped before it reads the heartbeat again', () => {
  const w = boot();
  const status = () => w.document.getElementById('status').textContent;
  const beat = (at) => { w.DASH_ALIVE = { at: iso(at), view: 'v1' }; pending(w, 'alive.js').dispatchEvent(new w.Event('load')); };
  deliver(w, full());
  beat(T0);
  tick(w, 1000);
  assert.equal(status(), 'Polling');
  seen(w, false);
  tick(w, 30000); refresh(w); tick(w, 30000); refresh(w);
  seen(w, true);
  assert.notEqual(status(), 'Feed stopped', 'the old heartbeat is not judged before alive.js is read again');
  beat(w.clock);
  tick(w, 1000);
  assert.equal(status(), 'Polling', 'a new heartbeat: the feed is live');
  refresh(w); beat(w.clock - 1000);
  tick(w, 46000);
  assert.equal(status(), 'Feed stopped', 'a heartbeat that stops is still reported');
});

// Bug: a heartbeat read that fails when the page is shown left the old heartbeat unjudged, so a feed that stopped
// while the page was hidden was never reported.
test('a page shown after a long hide says Feed stopped when its heartbeat read fails', () => {
  const w = boot();
  const status = () => w.document.getElementById('status').textContent;
  deliver(w, full());
  w.DASH_ALIVE = { at: iso(T0), view: 'v1' };
  pending(w, 'alive.js').dispatchEvent(new w.Event('load'));
  seen(w, false);
  tick(w, 30000); refresh(w); tick(w, 30000); refresh(w);
  seen(w, true);
  pending(w, 'alive.js').dispatchEvent(new w.Event('error'));
  tick(w, 1000);
  assert.equal(status(), 'Feed stopped', 'the failed read ends the wait: the old heartbeat is judged');
});

// Bug: the 1 s timer read the page and drew the status and the times each second in a background tab.
test('the 1 s timer changes nothing while the page is hidden, and the times catch up when shown', () => {
  const w = boot();
  deliver(w, full());
  const t = () => panel(w, 'belt').querySelector('li[data-key="sample:c3-63"] .track-now time[data-since]').textContent;
  assert.equal(t(), '5 min in this step');
  seen(w, false);
  const o = watch(w);
  tick(w, 60000); tick(w, 60000);
  assert.deepEqual(o.takeRecords(), [], 'the timer changed nothing on the page');
  seen(w, true);
  assert.equal(t(), '7 min in this step');
});
