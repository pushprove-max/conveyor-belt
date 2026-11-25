// SPDX-License-Identifier: Apache-2.0
// The Self-heals page's tiles as filters (issue 1691): a click on Seen again or Leave in 7 days shows the entries the
// tile counts, pressed and named above the rows, with a clear control; a click on Moved up to harm opens the dropped
// entries with its entries alone. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { T0, iso, boot, panel, deliver, next, full, P, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const REPO = 'https://github.com/example/sample-project';
const DAY = 86400000;
const entry = (id, over) => ({ repo: 'sample', repoUrl: REPO, id, card: `c3-${id.slice(-2)}`, issue: 63, url: `${P}/63`, from: 'review', seen: null, sightings: null, area: 'area:board', ...over });
// Of 30 days: s1 and s2 seen again in the last 7 days; s3 seen again 10 days ago (and moved up to harm before a review
// listed it again); s4 has sightings but no sighting date (stale data) and 4 days left; l1 5 days left; n1 no date.
// Kinds: s1 and s4 wait, s2 and l1 run again.
const ENTRIES = [
  entry('h00000000000s1', { time: iso(T0 - 20 * DAY), seen: iso(T0 - 2 * DAY), sightings: 1, effect: 'self-heals', why: 'a slower redraw', finding: '[P2] a.js:1 the badge is late' }),
  entry('h00000000000s2', { time: iso(T0 - 15 * DAY), seen: iso(T0 - 3 * DAY), sightings: 3, effect: 'self-heals', why: 'the next turn picks it up', finding: '[P2] b.js:1 the poll skips one turn' }),
  entry('h00000000000s3', { time: iso(T0 - 25 * DAY), seen: iso(T0 - 10 * DAY), sightings: 2, effect: 'self-heals', why: 'a slower redraw', finding: '[P3] c.js:1 an old sighting',
    expired: { time: iso(T0 - 10 * DAY), why: 'harm', filed: 811 } }),
  entry('h00000000000s4', { time: iso(T0 - 26 * DAY), seen: null, sightings: 1, effect: 'self-heals', why: 'a slower redraw', finding: '[P3] d.js:1 no sighting date' }),
  entry('h00000000000l1', { time: iso(T0 - 25 * DAY), effect: 'self-heals', why: 'the next turn picks it up', finding: '[P2] e.js:1 leaves soon' }),
  entry('h00000000000n1', { time: null, effect: 'self-heals', why: 'a slower redraw', finding: '[P2] f.js:1 no date' }),
];
// Dropped: one moved up to harm 3 days ago, one moved up 40 days ago (out of the 30 days), one expired.
const DROPPED = [
  entry('h00000000000d1', { time: iso(T0 - 9 * DAY), effect: 'self-heals', why: 'w', finding: '[P2] up.js:1 seen in the logs', dropped: { time: iso(T0 - 3 * DAY), why: 'harm', filed: 812 } }),
  entry('h00000000000d2', { time: iso(T0 - 60 * DAY), effect: 'self-heals', why: 'w', finding: '[P2] old.js:1 moved up long ago', dropped: { time: iso(T0 - 40 * DAY), why: 'harm', filed: 700 } }),
  entry('h00000000000d3', { time: iso(T0 - 60 * DAY), effect: 'self-heals', why: 'w', finding: '[P2] gone.js:1 an old wait', dropped: { time: iso(T0 - 20 * DAY), why: 'expired' } }),
];
const data = () => { const d = full(); d.panels.declined.data.heals = [{ repo: 'sample', repoUrl: REPO, sorted: null, days: 30, areas: [], entries: ENTRIES, dropped: DROPPED }]; return d; };
const page = (w) => panel(w, 'selfheals');
const q = (w, sel) => page(w).querySelector(sel);
const qa = (w, sel) => Array.from(page(w).querySelectorAll(sel));
const rowIds = (w) => qa(w, '.sh-entries .sh-row').map((r) => r.dataset.key.split(':')[1].slice(-2));
const ALL = ['s4', 'l1', 's3', 's2', 's1', 'n1'];
const tile = (w, k) => q(w, `.sh-tile[data-tile="${k}"]`);
const pressed = (w) => qa(w, '.sh-tile[aria-pressed="true"]').map((t) => t.dataset.tile);
const filterSaid = (w) => { const f = q(w, '.sh-filter'); return f.hidden ? null : f.textContent; };
function open() {
  const w = boot({ tab: 'selfheals' });
  deliver(w, data());
  return w;
}

// Bugs: the tiles were numbers only, so nothing showed which entries a tile counts; a filter that read another test
// than the count would show entries the tile does not count (s3's old sighting, s4 with no sighting date); a redraw
// dropped the pressed tile; the tile filter replaced the kind chip or the search instead of working with them.
test('Self-heals tiles: Seen again shows the entries it counts, pressed and named, with the kind chip, the search and a redraw', () => {
  const w = open();
  assert.deepEqual(rowIds(w), ALL);
  assert.deepEqual(qa(w, 'button.sh-tile').map((t) => t.dataset.tile), ['seen', 'leaving', 'harm'], 'the three tiles are buttons; On the list and Ready to batch are not');
  assert.equal(filterSaid(w), null, 'no filter line with no tile pressed');
  tile(w, 'seen').focus(); tile(w, 'seen').click();
  assert.equal(tile(w, 'seen').querySelector('.sh-tile-n').textContent, '2');
  assert.deepEqual(rowIds(w), ['s2', 's1'], 'only the entries seen again in the last 7 days');
  assert.deepEqual(pressed(w), ['seen']);
  assert.equal(filterSaid(w), 'Showing: seen again, last 7 days × clear');
  assert.equal(w.document.activeElement, tile(w, 'seen'), 'a tile pressed from the keyboard keeps the focus');
  const search = q(w, '.sh-search');
  // 'at' matches s1 ("late"), s4 and n1 ("date"), not s2: the search keeps s2 out, the tile filter keeps s4 and n1 out.
  search.value = 'at'; search.dispatchEvent(new w.Event('input'));
  assert.deepEqual(rowIds(w), ['s1'], 'the search narrows the tile filter, and the tile filter holds with a search');
  search.value = ''; search.dispatchEvent(new w.Event('input'));
  q(w, '.sh-chip[data-kind="again"]').click();
  assert.deepEqual(rowIds(w), ['s2'], 'the tile filter and the kind chip together');
  // New data, so the page is drawn again (the same data is not): x1 is seen again and runs again, x2 runs again only.
  const d = data();
  d.panels.declined.data.heals[0].entries = ENTRIES.concat(
    entry('h00000000000x1', { time: iso(T0 - 5 * DAY), seen: iso(T0 - 1 * DAY), sightings: 1, effect: 'self-heals', why: 'the next turn picks it up', finding: '[P2] x.js:1 new' }),
    entry('h00000000000x2', { time: iso(T0 - 5 * DAY), effect: 'self-heals', why: 'the next turn picks it up', finding: '[P2] y.js:1 new' }));
  const before = tile(w, 'seen');
  assert.equal(w.document.activeElement, before, 'the tile has the focus before the redraw');
  next(w, d);
  assert.deepEqual(rowIds(w), ['s2', 'x1'], 'the tile and the chip hold through a redraw, and apply to the new entries');
  assert.deepEqual(pressed(w), ['seen']);
  // Bug: a redraw replaces the tiles, and the focused tile lost the focus to the page.
  assert.notEqual(tile(w, 'seen'), before, 'the redraw draws the tiles again');
  assert.equal(w.document.activeElement, tile(w, 'seen'), 'the focused tile keeps the focus through a redraw');
  assert.equal(filterSaid(w), 'Showing: seen again, last 7 days × clear');
  q(w, '.sh-chip[data-kind="all"]').click();
  tile(w, 'seen').click();
  // Days left, soonest first: s4 4, l1 5, s3 20, x2 25, s2 27, s1 28, x1 29, n1 none.
  assert.deepEqual(rowIds(w), ['s4', 'l1', 's3', 'x2', 's2', 's1', 'x1', 'n1'], 'a second click on the tile shows every entry again, the new ones too');
  assert.deepEqual(pressed(w), []);
  assert.equal(filterSaid(w), null);
});

// Bugs: the leave tile counted the entries with 7 days or less left, but nothing showed them; an entry with no days
// left (n1, no date) would get through a filter that read "not more than 7" from a missing number; the filter had no way out;
// the clear control, removed with the filter line, took the keyboard focus with it.
test('Self-heals tiles: Leave in 7 days shows the entries it counts, and its clear control shows all again', () => {
  const w = open();
  tile(w, 'leaving').click();
  q(w, '.sh-filter-clear').focus();
  assert.equal(w.document.activeElement, q(w, '.sh-filter-clear'));
  assert.equal(tile(w, 'leaving').querySelector('.sh-tile-n').textContent, '2');
  assert.deepEqual(rowIds(w), ['s4', 'l1'], 'only the entries with 7 days or less left');
  assert.deepEqual(pressed(w), ['leaving']);
  assert.equal(q(w, '.sh-showing').textContent, 'Showing 2 of 6');
  assert.equal(filterSaid(w), 'Showing: leave in 7 days × clear');
  q(w, '.sh-filter-clear').click();
  assert.deepEqual(rowIds(w), ALL, 'the clear control shows every entry again');
  assert.deepEqual(pressed(w), []);
  assert.equal(filterSaid(w), null);
  assert.equal(w.document.activeElement, tile(w, 'leaving'), 'the focus goes to the tile the clear control cleared');
});

// Bug: with only dropped entries left, a zero-count tile said "No entry is on the list now." and not that no entry
// matches its filter.
test('Self-heals tiles: a list tile with no entries on the list says that no entry matches', () => {
  const w = boot({ tab: 'selfheals' });
  const d = data();
  d.panels.declined.data.heals[0].entries = [];
  deliver(w, d);
  assert.equal(q(w, '.sh-none').textContent, 'No entry is on the list now.', 'with no tile pressed');
  tile(w, 'seen').click();
  assert.equal(tile(w, 'seen').querySelector('.sh-tile-n').textContent, '0');
  assert.equal(q(w, '.sh-none').textContent, 'No entry matches this search, kind or tile.', 'with Seen again pressed');
});

// Bugs: a zero-count tile left the entries it does not count on the list; the harm tile with no harm move to show
// opened the dropped entries as an empty list, with no word that no entry matches.
test('Self-heals tiles: a zero-count tile hides the entries on the list, and a zero-count harm tile says that no entry matches', () => {
  const w = boot({ tab: 'selfheals' });
  const d = data();
  // l1 and n1 are not seen again; d2 moved up to harm out of the 30 days and d3 expired, so both tiles count 0.
  d.panels.declined.data.heals[0].entries = ENTRIES.filter((e) => /l1$|n1$/.test(e.id));
  d.panels.declined.data.heals[0].dropped = DROPPED.filter((e) => /d2$|d3$/.test(e.id));
  deliver(w, d);
  assert.deepEqual(rowIds(w), ['l1', 'n1']);
  tile(w, 'seen').click();
  assert.equal(tile(w, 'seen').querySelector('.sh-tile-n').textContent, '0');
  assert.deepEqual(rowIds(w), [], 'Seen again at 0 hides the entries on the list');
  assert.equal(q(w, '.sh-none').textContent, 'No entry matches this search, kind or tile.');
  tile(w, 'harm').click();
  assert.equal(tile(w, 'harm').querySelector('.sh-tile-n').textContent, '0');
  assert.deepEqual(pressed(w), ['harm']);
  assert.deepEqual(qa(w, '.sh-dropped li').map((li) => li.textContent), ['No entry matches this tile.'],
    'the harm tile at 0 shows neither the old harm move nor the expired entry, and says that no entry matches');
});

// Bugs: the harm tile counted entries that the list does not hold, with no way to see them; the dropped entries it
// opens would show the expired entry or the move up to harm of 40 days ago, which the tile does not count.
test('Self-heals tiles: Moved up to harm opens the dropped entries with the harm moves of the last 30 days alone', () => {
  const w = open();
  assert.equal(q(w, '.sh-dropped'), null, 'the dropped entries are closed at first');
  tile(w, 'harm').click();
  assert.equal(tile(w, 'harm').querySelector('.sh-tile-n').textContent, '2');
  assert.deepEqual(qa(w, '.sh-dropped li .sh-row-title').map((t) => t.textContent), ['seen in the logs', 'an old sighting'],
    'the harm moves of the last 30 days, newest first: the dropped one and the one a review listed again');
  assert.deepEqual(qa(w, '.sh-dropped li .sh-gone-why').map((t) => t.textContent), ['moved up to harm as #812', 'moved up to harm as #811']);
  assert.equal(q(w, '.sh-dropped-link').textContent, 'Dropped entries (2) ›', 'the link counts what it opens');
  assert.deepEqual(pressed(w), ['harm']);
  assert.equal(filterSaid(w), 'Showing: moved up to harm, last 30 days, in Dropped entries × clear');
  assert.deepEqual(rowIds(w), ALL, 'the entries on the list do not change');
  tile(w, 'harm').click();
  assert.equal(qa(w, '.sh-dropped li').length, 3, 'a second click shows every dropped entry again');
  assert.deepEqual(pressed(w), []);
});

// Bug: with no dropped entries, the Dropped entries button that the harm tile shows went away when it closed the list,
// and the keyboard focus went with it.
test('Self-heals tiles: closing the harm tile\'s Dropped entries with no dropped entries gives the focus to the harm tile', () => {
  const w = boot({ tab: 'selfheals' });
  const d = data();
  d.panels.declined.data.heals[0].dropped = [];
  deliver(w, d);
  assert.equal(q(w, '.sh-dropped-link'), null, 'no Dropped entries button with no dropped entries');
  tile(w, 'harm').click();
  const link = q(w, '.sh-dropped-link');
  assert.equal(link.textContent, 'Dropped entries (1) ›', 'the harm tile shows the entry a review listed again (s3)');
  link.focus(); link.click();
  assert.equal(q(w, '.sh-dropped-link'), null, 'closing the list ends the harm filter, and the button goes');
  assert.deepEqual(pressed(w), []);
  assert.equal(w.document.activeElement, tile(w, 'harm'), 'the focus goes to the harm tile');
});
