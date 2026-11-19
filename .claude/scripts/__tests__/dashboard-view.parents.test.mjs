// SPDX-License-Identifier: Apache-2.0
// The parts of a parent issue (its GitHub sub-issues, the snapshot's open.umbrellas) on the Board: one row a parent,
// with its parts done of all and the part in flight, that opens to every part with its state.
// Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { boot, deliver, next, panel, withOpen, P, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

// #90 has three parts: #91 landed (closed, its card the last of six in Landed today, past the column's first page
// of five), #92 building (testing), #93 queued. #95 has the blocked #13 (the fixture's Needs you card), #96, still
// open and not picked, and #97, which waits on #92 (in Queue).
function snap() {
  const d = withOpen({ umbrellas: [
    { repo: 'sample', issue: 90, title: 'Big work', url: `${P}/90`, parts: ['#91', '#92', '#93'], done: 1, all: 3, inFlight: [92], closed: ['#91'] },
    { repo: 'sample', issue: 95, title: 'Other work', url: `${P}/95`, parts: ['#13', '#96', '#97'], done: 0, all: 3, inFlight: [], closed: [] },
  ] });
  const b = d.panels.board.data;
  b.building = [...b.building, { repo: 'sample', card: 'c7-92', issue: 92, title: 'Part two', url: `${P}/92`, step: 'tests', stepAt: b.review[0].stepAt, usd: 1, reading: true }];
  b.queue = [...b.queue, { repo: 'sample', card: null, issue: 93, title: 'Part three', url: `${P}/93`, priority: 'P2', followup: false, retried: false }];
  b.waits = [{ repo: 'sample', card: null, issue: 97, title: 'Part four', url: `${P}/97`, priority: 'P2', followup: false, retried: false, waitsFor: [92] }];
  const day = (i) => ({ repo: 'sample', card: `c9-${80 + i}`, issue: 80 + i, title: `Filler ${i}`, url: `${P}/${80 + i}`, step: 'landed', time: b.landed[0].time, usd: 1, reviews: 1 });
  b.landed = [...b.landed, ...[1, 2, 3].map(day), { ...day(4), card: 'c9-91', issue: 91, title: 'Part one', url: `${P}/91` }];
  return d;
}
const row = (w, n) => panel(w, 'board').querySelector(`.board-parents details.board-parent[data-issue="${n}"]`);
const parts = (det) => Array.from(det.querySelectorAll('.board-part')).map((li) => [li.dataset.part, li.dataset.state]);

// Bug this guards: the parts of a parent were scattered over the columns, with nothing saying how far the whole
// piece of work had got or which part was being built.
test('Board: a parent with three parts is one row: its title, 1 of 3 done with a bar, and the part being built with its step', () => {
  const w = boot({ tab: 'control' });
  deliver(w, snap());
  const det = row(w, 90), head = det.querySelector('summary');
  assert.equal(panel(w, 'board').querySelectorAll('.board-parent[data-issue="90"]').length, 1, 'one row for the parent');
  assert.match(head.textContent, /Big work/);
  assert.match(head.textContent, /1 of 3 done/);
  assert.equal(head.querySelector('.board-parent-fill').style.width, '33%', 'the bar is a third full');
  assert.equal(head.querySelector('.board-parent-now').textContent, '#92 testing');
  assert.equal(det.open, false, 'the row starts closed');
});

// Bug this guards: the row could not be opened to see each part and where it is.
test('Board: opening a parent row lists its three parts with their states and a link to each card on the Board', () => {
  const w = boot({ tab: 'control' });
  deliver(w, snap());
  const det = row(w, 90);
  det.open = true;
  assert.deepEqual(parts(det), [['#91', 'landed'], ['#92', 'building'], ['#93', 'waiting']]);
  const li = (r) => det.querySelector(`.board-part[data-part="${r}"]`);
  assert.match(li('#92').textContent, /Part two.*building: testing/);
  assert.match(li('#93').textContent, /Part three/);
  li('#93').querySelector('[data-act="part-card"]').click();
  const card = panel(w, 'board').querySelector('.board-col[data-col="queue"] .bcard[data-issue="93"]');
  assert.equal(w.document.activeElement, card, 'the link brings the part\'s card in the Queue column to the focus');
});

// Bug this guards: a closed part, and a part that waits on another issue, had no link though their cards were on the
// Board; and Show its card did nothing when the filter or the column's first page hid the card.
test('Board: Show its card on a closed part and on a waiting part shows the card that a page or the filter hid', () => {
  const w = boot({ tab: 'control' });
  deliver(w, snap());
  const board = panel(w, 'board'), link = (n, r) => row(w, n).querySelector(`.board-part[data-part="${r}"] [data-act="part-card"]`);
  assert.equal(board.querySelector('.board-col[data-col="landed"] .bcard[data-issue="91"]'), null, 'the closed part\'s card is past the first page');
  link(90, '#91').click();
  assert.equal(w.document.activeElement, board.querySelector('.board-col[data-col="landed"] .bcard[data-issue="91"]'), 'the closed part\'s card in Landed today');
  // On a phone app.css hides a folded Landed today (or Held) but its heading: the link opens the column, as its button does.
  assert.ok(board.querySelector('.board-col[data-col="landed"]').classList.contains('open'), 'Landed today is unfolded');
  assert.equal(board.querySelector('[data-act="fold-landed"]').getAttribute('aria-expanded'), 'true', 'its button says it is open');
  const text = board.querySelector('[data-filter="text"]');
  text.value = '93'; text.dispatchEvent(new w.Event('input'));
  assert.equal(board.querySelector('.board-col[data-col="queue"] .bcard[data-issue="97"]'), null, 'the filter hides the waiting part');
  link(95, '#97').click();
  assert.equal(text.value, '', 'the filter is cleared');
  assert.equal(w.document.activeElement, board.querySelector('.board-col[data-col="queue"] .bcard[data-issue="97"]'), 'the waiting part\'s card in Queue');
});

// Bug this guards: a new snapshot drew the row again and the focus left its summary, or went to the first part's link.
test('Board: a new snapshot keeps the focus on a parent row\'s summary and on the same part\'s link', () => {
  const w = boot({ tab: 'control' });
  deliver(w, snap());
  const det = () => row(w, 90);
  det().open = true;
  // Each snapshot differs from the one before (a part's step changes), so the Board draws the row again each time
  // rather than skipping an equal snapshot.
  const steps = ['merge', 'review'];
  const again = () => { const d = snap(); d.panels.board.data.building.at(-1).step = steps.shift(); return d; };
  const was = det().querySelector('.board-part[data-part="#93"] [data-act="part-card"]');
  was.focus();
  next(w, again());
  assert.notEqual(det().querySelector('.board-part[data-part="#93"] [data-act="part-card"]'), was, 'the row was drawn again');
  assert.equal(w.document.activeElement, det().querySelector('.board-part[data-part="#93"] [data-act="part-card"]'), 'the same part\'s link');
  const head = det().querySelector('summary');
  head.focus();
  next(w, again());
  assert.notEqual(det().querySelector('summary'), head, 'the row was drawn again');
  assert.equal(w.document.activeElement, det().querySelector('summary'), 'the row\'s summary');
});

// Bug this guards: a blocked part folded into its parent's row was no longer in Needs you, where it is answered.
test('Board: a blocked part shows in its parent\'s row and in Needs you', () => {
  const w = boot({ tab: 'control' });
  deliver(w, snap());
  assert.deepEqual(parts(row(w, 95)), [['#13', 'blocked'], ['#96', 'waiting'], ['#97', 'waiting']]);
  assert.match(row(w, 95).querySelector('summary').textContent, /0 of 3 done.*no part being built/);
  assert.match(panel(w, 'board').querySelector('.board-col[data-col="needs"] .bcard[data-issue="13"]').textContent, /Blocked/, 'the blocked part is in the Needs you column');
});
