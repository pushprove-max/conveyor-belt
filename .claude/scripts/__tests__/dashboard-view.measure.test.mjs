// SPDX-License-Identifier: Apache-2.0
// One measure round a frame (issue 498): a read of the layout after a write lays the page out again, so each read the
// page makes is a layout the owner waits for while they scroll. A refresh measures each cut panel once, in arrange();
// the feed's events of one version draw the tabs and the head once, at the next frame; the head is measured only when
// what it shows changed; a feed that opens or closes draws Health alone. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { boot, deliver, next, full, withOpen, panel, key, iso, clone, tick, T0, OVERVIEW, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

// Every getBoundingClientRect the page makes, by the element it was asked of.
function counted(w) {
  const asked = [];
  w.Element.prototype.getBoundingClientRect = function () {
    asked.push(this);
    return { left: 0, top: 0, right: 300, bottom: 90, width: 300, height: 90 };
  };
  return asked;
}
const frame = (w) => { for (const f of w.frames.splice(0)) f(); };
const body = (w, id) => panel(w, id).querySelector('.panel-body');

test('a refresh measures the rows of each cut panel once, in arrange(), not also when the panel is drawn', () => {
  const w = boot({ reducedMotion: true });
  deliver(w, full());
  const cut = ['needs', 'queue', 'cost'];
  for (const id of cut) key(w, panel(w, id).querySelector('.panel-length'), 'Home');
  for (const id of cut) assert.equal(body(w, id).classList.contains('scrolls'), true, `${id} is cut to one row`);
  const asked = counted(w);
  const renders = () => cut.reduce((s, id) => s + Number(panel(w, id).dataset.renders), 0);
  const before = renders();
  // At each read of a row, how many of the three panels had been drawn again.
  const seen = [];
  const plain = w.Element.prototype.getBoundingClientRect;
  w.Element.prototype.getBoundingClientRect = function () { if (cut.some((id) => body(w, id) !== this && body(w, id).contains(this))) seen.push(renders() - before); return plain.call(this); };
  const d = full();
  d.panels.needs.data.decisions[0].question = 'Which port does the page server use?';
  d.panels.queue.data.next[0].title = 'A new title';
  d.panels.cost.data.cards.perCard[0].title = 'A new title';
  next(w, d);
  assert.equal(renders() - before, 3, 'the three panels were drawn again');
  // A clip() in draw() measured each panel's rows once more, each one between two panels' writes (a layout each).
  for (const id of cut) {
    const rows = asked.filter((el) => el !== body(w, id) && body(w, id).contains(el)).length;
    assert.equal(rows, 1, `${id}'s rows are measured once: ${rows}`);
  }
  assert.deepEqual(seen, [3, 3, 3], 'each read comes after all three panels were drawn: the arrange() round');
});

// Bug it guards: the Board's draw ended with relength(), which cut (measured) its panels at once, and the page's
// arrange() after the part cut them again: a changed board part paid two layout reads for each panel.
test('a changed board part measures the Board panel\'s rows once, in arrange(), not also when the Board draws', () => {
  const w = boot({ tab: 'control', reducedMotion: true });
  deliver(w, withOpen());
  frame(w);
  key(w, panel(w, 'board').querySelector('.panel-length'), 'Home');
  assert.equal(body(w, 'board').classList.contains('scrolls'), true, 'the Board is cut to one row');
  const asked = counted(w);
  next(w, JSON.parse(JSON.stringify(withOpen()).replaceAll('Split the PROD stack', 'A new title')));
  frame(w);
  assert.match(body(w, 'board').textContent, /A new title/, 'the Board was drawn again');
  const rows = asked.filter((el) => el.matches('.bcard') && body(w, 'board').contains(el)).length;
  assert.equal(rows, 1, `the Board's rows are measured once: ${rows}`);
});

test('the feed\'s events of one version draw the head once, at the next frame; an event for another tab measures nothing; a new Density fits it again', () => {
  const w = boot({ feed: true, reducedMotion: true });
  // jsdom lays nothing out: the head line is given a width, so the head is fitted (and measured) as in a browser.
  Object.defineProperty(w.document.getElementById('stats'), 'clientWidth', { configurable: true, get: () => 2000 });
  const es = w.sources[0];
  es.readyState = 1; es.emit('open');
  es.emit('snapshot', full());
  frame(w);
  // The data grows old: the mark says Stale and the Restart button shows in the head line.
  tick(w, 400000);
  const restart = w.document.getElementById('restart');
  assert.equal(restart.hidden, false, 'Stale shows Restart');
  const asked = counted(w);
  const top = w.document.querySelector('.top');
  const inHead = () => asked.filter((el) => top.contains(el));
  const version = iso(w.clock), d = full();
  d.panels.queue.data.next = d.panels.queue.data.next.slice(0, 1);
  d.panels.belt.data.cards[0].title = 'A new title';
  d.panels.landed.data.cards[0].title = 'A new title';
  // Today and 7 days both rise: with no motion a count lands at once, and a fit there comes before 7 days is written.
  d.panels.cost.data.cards.todayUsd = 6.25;
  d.panels.cost.data.cards.weekUsd = 16;
  for (const id of ['queue', 'belt', 'landed', 'cost']) es.emit('panel', { id, part: clone(d.panels[id]), updatedAt: version });
  // An event that clears Stale hides Restart: a fit at once measures the head before the queued draw.
  assert.equal(restart.hidden, true, 'the new data clears Stale');
  assert.equal(inHead().length, 0, 'nothing in the head is measured before the frame');
  // One frame for the panels' arrange() and one for the tabs and the head, not one for each event.
  assert.equal(w.frames.length, 2, `the four events ask for two frames: ${w.frames.length}`);
  assert.equal(w.document.querySelector('#stats > .stat[data-stat="queued"]').textContent.startsWith('2'), true, 'nor drawn');
  frame(w);
  assert.match(w.document.querySelector('#stats > .stat[data-stat="queued"]').textContent, /^1/, 'the frame draws the head');
  assert.equal(inHead().filter((el) => el === top).length, 1, 'the head is measured once, after the frame');
  const tiles = w.document.querySelectorAll('#stats > .stat');
  for (const t of tiles) assert.equal(inHead().filter((el) => el === t).length, 1, `${t.dataset.stat} is measured once`);
  assert.equal(w.frames.length, 0, 'and the frame asks for no other');
  // A part of the Rules tab changes nothing on Overview and nothing in the head: no read of the layout at all.
  asked.length = 0;
  const rules = clone(d.panels.rules);
  rules.data.state = 'paused';
  es.emit('panel', { id: 'rules', part: rules, updatedAt: iso(w.clock) });
  frame(w);
  assert.equal(w.document.getElementById('tab-rules').querySelector('.tab-count').textContent, '· 1', 'the tabs were drawn');
  assert.deepEqual(asked.map((el) => el.className), [], 'nothing was measured');
  // Compact changes the tiles' padding and figures (app.css): the head is fitted again at the same window width.
  w.document.getElementById('customize-open').click();
  const compact = w.document.querySelector('#customize input[name="choice-density"][value="compact"]');
  compact.checked = true;
  compact.dispatchEvent(new w.Event('change', { bubbles: true }));
  frame(w);
  assert.equal(inHead().filter((el) => el === top).length, 1, 'a new Density fits the head again');
});

// Bug it guards: every resize fitted the head again, so a change of the window's height alone (a phone's address bar
// shown or hidden) measured every head tile though nothing in the head changed.
test('a resize of the window\'s height alone measures nothing in the head; a new width fits it again', () => {
  const w = boot({ feed: true, reducedMotion: true });
  Object.defineProperty(w.document.getElementById('stats'), 'clientWidth', { configurable: true, get: () => 2000 });
  const es = w.sources[0];
  es.readyState = 1; es.emit('open');
  es.emit('snapshot', full());
  frame(w);
  const asked = counted(w);
  const top = w.document.querySelector('.top');
  Object.defineProperty(w, 'innerHeight', { configurable: true, value: w.innerHeight - 120 });
  w.dispatchEvent(new w.Event('resize'));
  assert.deepEqual(asked.filter((el) => top.contains(el)).map((el) => el.className), [], 'a height-only resize measures no head tile');
  Object.defineProperty(w, 'innerWidth', { configurable: true, value: w.innerWidth - 200 });
  w.dispatchEvent(new w.Event('resize'));
  assert.ok(asked.some((el) => el.matches('#stats > .stat')), 'a new width fits the head again');
});

test('a drag of a panel\'s length grip cuts it at once, with the new count in its foot', () => {
  const w = boot({ rects: true });
  const d = full();
  d.panels.queue.data.next = Array.from({ length: 23 }, (_, i) => ({ repo: 'sample', issue: 100 + i, title: `Issue ${i}`, priority: 'P2', followup: false, retried: false, url: null }));
  d.panels.queue.data.awaitingDeploy = [];
  deliver(w, d);
  const g = panel(w, 'queue').querySelector('.panel-length');
  g.dispatchEvent(Object.assign(new w.Event('pointerdown', { bubbles: true }), { button: 0, clientY: 500 }));
  w.document.dispatchEvent(Object.assign(new w.Event('pointerup'), { clientY: 300 }));
  const v = JSON.parse(w.localStorage.getItem('conveyor-board-layout')).tabs.overview.lengths.queue;
  assert.ok(Number.isInteger(v) && v < 23, `the drag set a length: ${v}`);
  // No frame is run: the cut is made at once (draw() no longer cuts, the length change still does).
  assert.equal(panel(w, 'queue').querySelector('.panel-rows').textContent, `${v} of 23`);
  assert.equal(body(w, 'queue').classList.contains('scrolls'), true);
});

test('a feed that closes and opens again draws Health again; every other panel keeps its nodes', () => {
  const w = boot({ feed: true });
  const es = w.sources[0];
  es.readyState = 1; es.emit('open');
  es.emit('snapshot', full());
  frame(w);
  const others = OVERVIEW.filter((id) => id !== 'health');
  const nodes = Object.fromEntries(others.map((id) => [id, Array.from(body(w, id).querySelectorAll('*'))]));
  const renders = Object.fromEntries(OVERVIEW.map((id) => [id, Number(panel(w, id).dataset.renders)]));
  es.readyState = 0; es.emit('error');
  assert.equal(Number(panel(w, 'health').dataset.renders), renders.health + 1, 'a close draws Health again');
  es.readyState = 1; es.emit('open');
  assert.equal(Number(panel(w, 'health').dataset.renders), renders.health + 2, 'an open draws Health again');
  frame(w);
  for (const id of others) {
    assert.equal(Number(panel(w, id).dataset.renders), renders[id], `${id} is not drawn again`);
    const now = Array.from(body(w, id).querySelectorAll('*'));
    assert.ok(now.length === nodes[id].length && now.every((n, i) => n === nodes[id][i]), `${id} keeps the same nodes`);
  }
});
