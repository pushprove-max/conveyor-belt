// SPDX-License-Identifier: Apache-2.0
// The status mark says Live only while the feed is open, and the tab title counts the cards stopped for you (#597).
// Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { clone, boot, deliver, seen, full, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const word = (w) => w.document.getElementById('status').textContent;

// Bug: the mark said Live for fresh data read from data.js every 15 s, with the feed closed.
test('fresh data with the feed closed is Polling; the feed open is Live, and closed again is Polling', () => {
  const w = boot({ feed: true });
  const es = w.sources[0];
  es.emit('error');  // the feed did not open: the page reads data.js
  deliver(w, full());
  assert.equal(word(w), 'Polling');
  assert.equal(w.document.getElementById('updated').textContent, 'under a minute ago', 'the data age is shown with it');
  es.readyState = 1; es.emit('open');
  assert.equal(word(w), 'Live');
  es.emit('error');
  assert.equal(word(w), 'Polling', 'a feed that closes is not Live, with no new data to say so');
});

// Bug: a Board in a background tab did not show that cards were stopped for you; a part that came while it was hidden
// left the title as it was.
test('the tab title counts the cards stopped for you, also from a part that came while the page was hidden', () => {
  const w = boot({ feed: true });
  const es = w.sources[0];
  const needs = (n) => {
    const part = clone(full().panels.needs);
    part.data.cards.waiting = [];
    part.data.cards.blocked = Array.from({ length: n }, (_, i) => ({ ...full().panels.needs.data.cards.blocked[0], card: `c${i}-9${i}`, issue: 90 + i }));
    return part;
  };
  const snap = (n) => { const d = full(); d.panels.needs = needs(n); return d; };
  es.readyState = 1; es.emit('open');
  es.emit('snapshot', snap(2));
  assert.equal(w.document.title, '(2) Conveyor Board');
  seen(w, false);
  es.emit('snapshot', snap(0));
  assert.equal(w.document.title, 'Conveyor Board', 'a snapshot while hidden sets the title; none stopped has no count');
  es.emit('panel', { id: 'needs', part: needs(2), updatedAt: full().updatedAt });
  assert.equal(w.document.title, '(2) Conveyor Board', 'a part while hidden sets the title');
});
