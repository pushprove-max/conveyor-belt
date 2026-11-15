// SPDX-License-Identifier: Apache-2.0
// A page in a background tab (#567): it keeps what comes and draws nothing until it is shown again.
// Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { T0, iso, clone, OVERVIEW, boot, panel, deliver, tick, seen, full, cases } from './dashboard-view.helpers.mjs';

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
  for (const id of OVERVIEW) assert.equal(Number(panel(w, id).dataset.renders), before[id] + 1, `${id} drawn once when shown`);
  assert.ok(panel(w, 'belt').textContent.includes('9 model replies'), 'the belt shows the last update');
  assert.ok(!panel(w, 'queue').textContent.includes(gone), 'the queue shows the snapshot kept');
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
