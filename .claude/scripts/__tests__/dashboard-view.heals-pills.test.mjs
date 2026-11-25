// SPDX-License-Identifier: Apache-2.0
// The Self-heals page's area cards (issue 1692): a kind pill shows its kind and its count as two parts spaced by the
// layout, and a click on it filters the entries to that area's entries of that kind, pressed and named above the rows
// with a clear control. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { T0, iso, boot, panel, deliver, next, full, css, P, cases, pickProject } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const REPO = 'https://github.com/example/sample-project';
const DAY = 86400000;
const entry = (id, area, ago, why, finding) => ({ repo: 'sample', repoUrl: REPO, id: `h0000000000${id}`, card: `c3-${id}`, issue: 63, url: `${P}/63`, from: 'review',
  seen: null, sightings: null, area, time: iso(T0 - ago * DAY), effect: 'self-heals', why, finding });
// Of 30 days, by days left: b1 10, b3 15, n1 18, b2 20, n2 22, e1 25. Kinds: wait in board (b1, b2), engine (e1) and
// no area (n2); b3 runs again; n1's reason names no way of healing (kind not read).
const ENTRIES = [
  entry('0b1', 'area:board', 20, 'a slower redraw', '[P2] a.js:1 the badge is late'),
  entry('0b2', 'area:board', 10, 'a slower redraw', '[P2] b.js:1 the count lags'),
  entry('0b3', 'area:board', 15, 'the next turn picks it up', '[P2] c.js:1 the poll skips one turn'),
  entry('0e1', 'area:engine/review', 5, 'a slower redraw', '[P2] d.js:1 the lock lags'),
  entry('0n1', null, 12, 'w', '[P3] e.js:1 no way named'),
  entry('0n2', null, 8, 'a slower redraw', '[P3] f.js:1 no area'),
];
const ALL = ['b1', 'b3', 'n1', 'b2', 'n2', 'e1'];
const data = (entries = ENTRIES) => { const d = full(); d.panels.declined.data.heals = [{ repo: 'sample', repoUrl: REPO, sorted: null, days: 30, areas: [], entries, dropped: [] }]; return d; };
const page = (w) => panel(w, 'selfheals');
const q = (w, sel) => page(w).querySelector(sel);
const qa = (w, sel) => Array.from(page(w).querySelectorAll(sel));
const rowIds = (w) => qa(w, '.sh-entries .sh-row').map((r) => r.dataset.key.split(':')[1].slice(-2));
const pill = (w, area, kind) => q(w, `.sh-area[data-area="${area}"] .sh-kind[data-kind="${kind}"]`);
const pressed = (w) => qa(w, '.sh-area .sh-kind[aria-pressed="true"]').map((p) => `${p.closest('.sh-area').dataset.area}/${p.dataset.kind}`);
const chips = (w) => qa(w, '.sh-chip[aria-pressed="true"]').map((c) => c.dataset.kind);
const filterSaid = (w) => { const f = q(w, '.sh-filter'); return f.hidden ? null : f.textContent; };
const search = (w, v) => { const s = q(w, '.sh-search'); s.value = v; s.dispatchEvent(new w.Event('input')); };
const rule = (sel) => (css.match(new RegExp(`(?:^|\\n)${sel.replace(/[.[\]"=]/g, (m) => `\\${m}`)} \\{([^}]*)\\}`)) || [])[1] || '';
function open() {
  const w = boot({ tab: 'selfheals' });
  deliver(w, data());
  return w;
}

// Bugs: the pill drew "Runs again6": its count was a span whose only gap was a space at the start of its text, which a
// flex item drops; the pills were spans, so a click showed nothing; the filter must keep the area apart (e1 is a wait
// of another area) and hold with the search, the sort and a redraw.
test('Self-heals area pills: a click on a kind pill shows that area\'s entries of that kind, with the search, the sort and a redraw', () => {
  const w = open();
  const p = pill(w, 'area:board', 'wait');
  assert.deepEqual(Array.from(p.children, (c) => [c.className, c.textContent]), [['sh-kind-name', 'Waits longer'], ['sh-kind-n', '2']], 'the kind and the count are two parts, no space in their text');
  // jsdom draws no layout, so the gap can only be read from the rule of app.css that spaces the count.
  assert.match(rule('.sh-kind-n'), /margin-left: var\(--sp-1\)/, 'the layout spaces the count from the kind');
  assert.equal(p.tagName, 'BUTTON');
  assert.equal(filterSaid(w), null, 'no filter line with no pill pressed');
  p.focus(); p.click();
  assert.deepEqual(rowIds(w), ['b1', 'b2'], 'only the board area\'s waits: not e1 (engine) nor n2 (no area)');
  assert.deepEqual(pressed(w), ['area:board/wait']);
  assert.deepEqual(chips(w), ['wait'], 'the toolbar\'s kind chip of that kind is pressed too');
  assert.equal(filterSaid(w), 'Showing: board, Waits longer × clear');
  assert.equal(w.document.activeElement, pill(w, 'area:board', 'wait'), 'a pill pressed from the keyboard keeps the focus');
  search(w, 'lags');
  assert.deepEqual(rowIds(w), ['b2'], 'the search narrows the pill filter (e1 also lags, in another area)');
  search(w, '');
  const sort = q(w, '.sh-sort'); sort.value = 'newest'; sort.dispatchEvent(new w.Event('change'));
  assert.deepEqual(rowIds(w), ['b2', 'b1'], 'the sort orders the filtered entries');
  next(w, data(ENTRIES.concat(entry('0b4', 'area:board', 1, 'a slower redraw', '[P2] g.js:1 a new wait'))));
  assert.deepEqual(rowIds(w), ['b4', 'b2', 'b1'], 'the filter holds through a redraw and applies to the new entries');
  assert.deepEqual(pressed(w), ['area:board/wait']);
  assert.equal(pill(w, 'area:board', 'wait').querySelector('.sh-kind-n').textContent, '3');
  assert.equal(filterSaid(w), 'Showing: board, Waits longer × clear');
  pill(w, 'area:board', 'wait').focus();
  q(w, '.sh-filter-clear').click();
  assert.equal(rowIds(w).length, 7, 'the clear control brings every entry back');
  assert.deepEqual(pressed(w), []);
  assert.deepEqual(chips(w), ['all']);
  assert.equal(filterSaid(w), null);
  assert.equal(w.document.activeElement, pill(w, 'area:board', 'wait'), 'the focus goes to the pill it cleared');
});

// Bugs: stale data: a pill of "kind not read" or of the No area card must filter to entries whose kind or area is
// missing, not to none or to all; a second click must end the filter.
test('Self-heals area pills: the No area card\'s kind not read pill filters to its entry, and a second click clears it', () => {
  const w = open();
  pill(w, '', '').click();
  assert.deepEqual(rowIds(w), ['n1'], 'the entry with no area and no kind read');
  assert.deepEqual(pressed(w), ['/']);
  assert.deepEqual(chips(w), [], 'no chip names the kind not read');
  assert.equal(filterSaid(w), 'Showing: No area, kind not read × clear');
  pill(w, '', 'wait').click();
  assert.deepEqual(rowIds(w), ['n2'], 'a pill of the No area card filters to the entries with no area alone');
  assert.deepEqual(pressed(w), ['/wait']);
  pill(w, '', 'wait').click();
  assert.deepEqual(rowIds(w), ALL, 'a second click brings every entry back');
  assert.deepEqual(pressed(w), []);
  assert.equal(filterSaid(w), null);
});

// Bug: a tile pressed before a pill stayed on, so the pill showed fewer entries than it counts (no entry of this list
// is seen again, so Seen again with the board's waits showed none), and clearing the pill left the tile's filter.
test('Self-heals area pills: a pill ends a pressed tile and a tile ends a pressed pill, so clearing shows every entry', () => {
  const w = open();
  const seen = () => q(w, '.sh-tile[data-tile="seen"]');
  seen().click();
  assert.deepEqual(rowIds(w), [], 'Seen again counts none of these entries');
  pill(w, 'area:board', 'wait').click();
  assert.deepEqual(rowIds(w), ['b1', 'b2'], 'the pill shows the two entries it counts, not the tile\'s none');
  assert.equal(seen().getAttribute('aria-pressed'), 'false');
  assert.equal(filterSaid(w), 'Showing: board, Waits longer × clear');
  q(w, '.sh-filter-clear').click();
  assert.deepEqual(rowIds(w), ALL, 'the clear control brings every entry back, with no tile left on');
  pill(w, 'area:board', 'wait').click();
  seen().click();
  assert.deepEqual(pressed(w), [], 'the tile ends the pill');
  assert.deepEqual(chips(w), ['all'], 'and the pill\'s kind');
  assert.equal(filterSaid(w), 'Showing: seen again, last 7 days × clear');
});

// Bug: a pill pressed in one project stayed on when Show picked another, whose entries it could never match: the list
// showed none of them, with no pill on the page to press again.
test('Self-heals area pills: a pill of one project ends when Show picks another', () => {
  const w = boot({ tab: 'selfheals' });
  const d = data();
  d.panels.machine.data.repos = ['sample', 'widgetshop'];
  d.panels.declined.data.heals.push({ repo: 'widgetshop', repoUrl: 'https://github.com/example/widgetshop', sorted: null, days: 30, areas: [], dropped: [],
    entries: [{ ...ENTRIES[0], repo: 'widgetshop', repoUrl: 'https://github.com/example/widgetshop', id: 'h00000000000w1' }] });
  deliver(w, d);
  pickProject(w, 'sample');
  pill(w, 'area:board', 'wait').click();
  assert.deepEqual(rowIds(w), ['b1', 'b2']);
  pickProject(w, 'widgetshop');
  assert.deepEqual(rowIds(w), ['w1'], 'the other project\'s entries show');
  assert.equal(filterSaid(w), null, 'no filter line names the first project\'s pill');
  assert.deepEqual(chips(w), ['all'], 'the pill\'s kind ends with it');
});
