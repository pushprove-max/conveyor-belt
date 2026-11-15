// SPDX-License-Identifier: Apache-2.0
// The history (#524): the Landed, Metrics, Cost and Declined panels read the older entries the live snapshot no
// longer carries from GET history. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { T0, iso, boot, panel, deliver, next, later, settle, full, clone, P, CARD_METRICS, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const rows = (w, id) => Array.from(panel(w, id).querySelectorAll('.rows > .row .title'), (t) => t.textContent);

// Bug: the snapshot holds only the newest of each list, so a panel drawn from the live part alone loses every older
// card of the day, every older card of the 7 days and every older declined line; and a page that asked for the
// history with every draw would read it every second, as the feed it was cut from.
test('Landed, Metrics, Cost and Declined lay in the older entries from the history, asked for once a minute at most', async () => {
  const w = boot({ query: '?declined=all' });
  const old = { repo: 'sample', card: 'c1-2', issue: 2, title: 'Older card', url: `${P}/2` };
  // The history: each part as the live one, with one older entry, and the live entries again (not drawn twice).
  const h = clone(full().panels);
  h.landed.data.cards.push({ ...old, step: 'landed', time: iso(T0 - 9000000), start: iso(T0 - 9600000), tookSec: 600, usd: 1, reviews: 1, followups: [], sha: 'abd', pushed: true });
  h.metrics.data.cards.push({ ...old, state: 'landed', at: iso(T0 - 1000), metrics: CARD_METRICS });
  h.cost.data.cards.perCard.push({ ...old, todayUsd: 9, weekUsd: 9, state: 'landed' });
  h.declined.data.rest.push({ repo: 'sample', id: 'dold00000000a', time: iso(T0 - 9000000), card: 'c1-2', issue: 2, url: `${P}/2`, finding: '[P2] c.txt:1 an older line', by: 'code', why: 'old', built: null, dismissed: { time: iso(T0), by: 'owner' } });
  w.historyBody = { updatedAt: iso(T0), panels: h };
  deliver(w, full());
  await settle(); await settle();
  assert.equal(w.historyAsks, 1, 'four panels drawn, one ask');
  assert.deepEqual(rows(w, 'landed'), ['Landed one', 'Fixed before', 'Older card'], 'Landed: the older card of the day after the live ones, each once');
  assert.equal(panel(w, 'landed').querySelector('.panel-count').textContent, '3');
  assert.ok(rows(w, 'metrics').includes('Older card'), `Metrics: the older card among its cards: ${rows(w, 'metrics')}`);
  assert.equal(rows(w, 'metrics').length, 3);
  assert.equal(rows(w, 'cost')[0], 'Older card', 'Cost: the older card, the costliest, first');
  assert.equal(rows(w, 'cost').length, 5);
  assert.ok(rows(w, 'declined').includes('[P2] c.txt:1 an older line'), `Declined: the older line under every line: ${rows(w, 'declined')}`);
  // A new live part a moment later draws the panels again, with the history it has: no second ask.
  next(w, full());
  await settle();
  assert.equal(w.historyAsks, 1);
  assert.ok(rows(w, 'landed').includes('Older card'));
});

// Bug: after a failed history read (the server's 502), a part that did not change was never drawn again, so the
// history was never asked for again and the older entries stayed hidden.
test('a failed history read is tried again a minute later, with the live parts unchanged', async () => {
  const w = boot();
  deliver(w, full());
  await settle(); await settle();
  assert.equal(w.historyAsks, 1);
  assert.deepEqual(w.timeouts.map((t) => t.ms), [60000], 'one try again, a minute later');
  const h = clone(full().panels);
  h.landed.data.cards.push({ ...h.landed.data.cards[0], card: 'c1-2', title: 'Older card', time: iso(T0 - 9000000) });
  w.historyBody = { updatedAt: iso(T0), panels: h };
  w.clock += 60000;
  later(w);
  await settle(); await settle();
  assert.equal(w.historyAsks, 2, 'asked again with no new part');
  assert.ok(rows(w, 'landed').includes('Older card'));
  assert.deepEqual(w.timeouts.map((t) => t.ms), [60000], 'a read that came sets the next one, a minute later, and only it');
});

// Bug: the try again of a failed read came while the owner was on another tab; it found no such panel to draw, and the
// Overview shown again with unchanged parts drew nothing, so the history was never asked for again.
test('a failed history read is tried again when the Overview is shown again after its timer found it hidden', async () => {
  const w = boot();
  deliver(w, full());
  await settle(); await settle();
  assert.equal(w.historyAsks, 1);
  w.document.getElementById('tab-rules').click();
  const h = clone(full().panels);
  h.landed.data.cards.push({ ...h.landed.data.cards[0], card: 'c1-2', title: 'Older card', time: iso(T0 - 9000000) });
  w.historyBody = { updatedAt: iso(T0), panels: h };
  w.clock += 60000;
  later(w);
  await settle();
  assert.equal(w.historyAsks, 1, 'no ask for panels not shown');
  w.document.getElementById('tab-overview').click();
  await settle(); await settle();
  assert.equal(w.historyAsks, 2, 'the Overview shown again asks again');
  assert.ok(rows(w, 'landed').includes('Older card'));
});

// Bug: an older declined line filed as an issue changes only the history (the live part, its newest lines, stays the
// same), so a page that read the history once never showed "Filed as #n" on it, which the Filed note promises.
test('the history is read again each minute with the live parts unchanged, and a changed older entry is drawn', async () => {
  const w = boot({ query: '?declined=all' });
  const line = { repo: 'sample', id: 'dold00000000a', time: iso(T0 - 9000000), card: 'c1-2', issue: 2, url: `${P}/2`, finding: '[P2] c.txt:1 an older line', by: 'code', why: 'old', built: null, dismissed: null };
  const h = clone(full().panels);
  h.declined.data.rest.push(line);
  w.historyBody = { updatedAt: iso(T0), panels: h };
  deliver(w, full());
  await settle(); await settle();
  assert.equal(w.historyAsks, 1);
  assert.ok(!panel(w, 'declined').textContent.includes('Filed as #77'));
  const h2 = clone(h);
  h2.declined.data.rest.find((x) => x.id === line.id).built = 77;
  w.historyBody = { updatedAt: iso(T0 + 60000), panels: h2 };
  w.clock += 60000;
  later(w);
  await settle(); await settle();
  assert.equal(w.historyAsks, 2, 'read again a minute later with no new part');
  assert.ok(panel(w, 'declined').textContent.includes('Filed as #77'), 'the older line now says it was filed');
});

// Bug (#567): the history panels were drawn twice each minute, when the minute was up and when the history came,
// though the history had not changed.
test('a history read equal to the last one draws nothing', async () => {
  const w = boot();
  const h = clone(full().panels);
  h.landed.data.cards.push({ ...h.landed.data.cards[0], card: 'c1-2', title: 'Older card', time: iso(T0 - 9000000) });
  w.historyBody = { updatedAt: iso(T0), panels: h };
  deliver(w, full());
  await settle(); await settle();
  const ids = ['landed', 'metrics', 'cost', 'declined'];
  const renders = () => ids.map((id) => panel(w, id).dataset.renders);
  const before = renders();
  w.historyBody = { updatedAt: iso(T0 + 60000), panels: clone(h) };
  w.clock += 60000;
  later(w);
  await settle(); await settle();
  assert.equal(w.historyAsks, 2, 'read again a minute later');
  assert.deepEqual(renders(), before, 'no history panel drawn again');
  assert.ok(rows(w, 'landed').includes('Older card'));
});

// Bug: a history read before midnight laid yesterday's cards into today's Landed and Cost.
test("Landed and Cost leave out a history of another day", async () => {
  const w = boot();
  const h = clone(full().panels);
  h.landed.data.day = '2026-11-08';
  h.landed.data.cards.push({ ...h.landed.data.cards[0], card: 'c1-2', title: 'Yesterday' });
  h.cost.data.cards.day = '2026-11-08';
  h.cost.data.cards.perCard.push({ ...h.cost.data.cards.perCard[0], card: 'c1-2', title: 'Yesterday' });
  w.historyBody = { updatedAt: iso(T0), panels: h };
  deliver(w, full());
  await settle(); await settle();
  assert.equal(w.historyAsks, 1);
  assert.ok(!rows(w, 'landed').includes('Yesterday'));
  assert.ok(!rows(w, 'cost').includes('Yesterday'));
});
