// SPDX-License-Identifier: Apache-2.0
// The Declined panel's Self-heals list (issue 1559): the findings the judge sorted as self-heals, by area, each area
// with "File a batch card". Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { T0, iso, boot, panel, deliver, next, full, settle, P, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const REPO = 'https://github.com/example/sample-project';
const entry = (over) => ({ repo: 'sample', repoUrl: REPO, id: 'h00000000000a', time: iso(T0 - 600000), card: 'c3-63', issue: 63, url: `${P}/63`, area: 'area:engine',
  finding: '[P2] lib/a.sh:3 the poll waits one turn more. Proof: lib/a.sh:3', why: 'a slower turn, no wrong result', effect: 'self-heals', ...over });
const heals = () => [{ repo: 'sample', repoUrl: REPO, sorted: { time: iso(T0 - 3600000), ended: iso(T0 - 3500000), items: 3, moved: 2 },
  areas: [{ area: 'area:engine', count: 2 }, { area: null, count: 1 }],
  entries: [entry(), entry({ id: 'h00000000000b', card: 'c4-64', issue: 64, url: `${P}/64`, finding: '[P3] lib/b.sh:1 a stale label until the next poll. Proof: lib/b.sh:1' }),
    entry({ id: 'h00000000000c', area: null, effect: null, finding: '[P2] docs/x.md:1 extra work, same result. Proof: docs/x.md:1', why: 'more cost, no wrong result' })] }];
const box = (w) => panel(w, 'declined').querySelector('[data-part="heals"]');
const area = (w, a) => box(w).querySelector(`.heals-area[data-area="${a}"]`);

// Bugs: the list is not on the Board, so a self-heals finding leaves the belt with no trace; an area's batch card is
// filed for another area or with no second click (it costs a build); an entry with no kind shows one; the time of
// the sort of the queued follow-ups is not shown.
test('Declined: the Self-heals list shows each area with its count and entries, and "File a batch card" files that area\'s entries on a second click', async () => {
  const w = boot();
  const data = full();
  data.panels.declined.data.heals = heals();
  deliver(w, data);
  assert.ok(box(w), 'the panel shows the self-heals list');
  assert.equal(box(w).querySelector('.heals-title').textContent, 'Self-heals list (3)');
  assert.match(box(w).querySelector('.heals-sorted').textContent, /^The sort of the queued follow-ups ran, and moved 2 of 3 to the lists:/);
  assert.equal(box(w).querySelector('.heals-sorted time.since')?.dateTime, iso(T0 - 3600000), 'the time the sort ran');
  assert.deepEqual(Array.from(box(w).querySelectorAll('.heals-area'), (a) => [a.dataset.area, a.querySelectorAll('.heals-rows > .row').length]), [['area:engine', 2], ['', 1]]);
  assert.match(area(w, 'area:engine').querySelector('.row-main').textContent, /^area:engine 2 entries File a batch card/);
  const first = area(w, 'area:engine').querySelector('.heals-rows > .row');
  assert.equal(first.querySelector('.title').textContent, entry().finding);
  assert.match(first.querySelector('.row-meta').textContent, /from card c3-63 #63/);
  assert.equal(first.querySelector('.heals-kind').textContent, 'self-heals', "the judge's kind");
  assert.equal(first.querySelector('.heals-why').textContent, 'The judge: a slower turn, no wrong result');
  assert.equal(area(w, '').querySelector('.heals-kind'), null, 'an entry with no kind shows none');
  assert.match(area(w, '').querySelector('.row-main').textContent, /^No area 1 entry/);
  const file = () => area(w, 'area:engine').querySelector('button[data-act="heals-batch"]');
  file().click();
  await settle();
  assert.equal(w.posts.length, 0, 'the first click only asks');
  assert.equal(file().textContent, 'Click again to file one card with these 2 findings');
  file().click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'heals', args: ['batch', 'area:engine'], repo: 'sample' } }], "the area's entries, by its label");
  assert.equal(area(w, 'area:engine').querySelector('.answer-note').textContent, 'Filed: sent to main. The list leaves these entries in about a minute.');
  const none = () => area(w, '').querySelector('button[data-act="heals-batch"]');
  none().click();
  none().click();
  await settle();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [['batch', '-']], 'the entries with no area, as -');
});

// Bugs: a project with self-heals entries and no declined line showed the empty state, which hid its list; the
// panel did not say that the sort of the queued follow-ups has not run.
test('Declined: with no declined line, the panel still shows the Self-heals list, and says when the sort has not run', () => {
  const w = boot();
  const data = full();
  data.panels.declined.data.lines = [];
  data.panels.declined.data.rest = [];
  // The entry with no area came from an issue the sort read (its card is "#23").
  data.panels.declined.data.heals = heals().map((x) => ({ ...x, sorted: null, entries: x.entries.map((e) => (e.area ? e : { ...e, card: '#23', issue: 23, url: `${P}/23` })) }));
  deliver(w, data);
  assert.equal(panel(w, 'declined').dataset.state, 'ready');
  assert.equal(box(w).querySelector('.heals-title').textContent, 'Self-heals list (3)');
  assert.equal(box(w).querySelector('.heals-sorted').textContent, 'The sort of the queued follow-ups has not run yet.');
  // Bug it catches (issue 1614): an entry from an issue said "from card #23 #23".
  assert.match(area(w, '').querySelector('.heals-rows > .row .row-meta').textContent, /^from issue #23/);
});

// Bug it catches (issue 1561): the Board kept no trace of an entry that expired off the list, so the owner could not see
// what dropped; with expired entries and no live one the panel showed the empty state.
test('Declined: the Self-heals list shows the entries that expired, with when, and when one was seen again', () => {
  const w = boot();
  const data = full();
  data.panels.declined.data.lines = [];
  data.panels.declined.data.rest = [];
  const gone = (over) => entry({ id: 'h0000000000dd', finding: '[P2] lib/a.sh:9 an old wait', dropped: { time: iso(T0 - 86400000), why: 'expired' }, left: iso(T0 - 86400000), ...over });
  // Bug it catches (issue 1562): entries the owner dropped or moved up to harm on the Self-heals tab were listed here as expired.
  const byOwner = [gone({ id: 'h0000000000f1', dropped: { time: iso(T0), why: 'harm', filed: 812 }, left: iso(T0) }), gone({ id: 'h0000000000f2', dropped: { time: iso(T0), why: 'dropped' }, left: iso(T0) })];
  // The record holds them in the order they left, the oldest first; the panel shows the latest first (issue 1614).
  const older = gone({ id: 'h0000000000ee', card: '#23', issue: 23, url: `${P}/23`, finding: '[P3] lib/c.sh:2 an older wait',
    dropped: { time: iso(T0 - 2 * 86400000), why: 'expired' }, left: iso(T0 - 2 * 86400000), seen: iso(T0 - 3600000) });
  data.panels.declined.data.heals = [{ repo: 'sample', repoUrl: REPO, sorted: null, areas: [], entries: [], dropped: [older, gone(), ...byOwner] }];
  deliver(w, data);
  assert.equal(panel(w, 'declined').dataset.state, 'ready', 'a project with expired entries alone is not empty');
  const rows = Array.from(box(w).querySelectorAll('.heals-dropped .row'));
  assert.equal(box(w).querySelector('.heals-dropped summary').textContent, 'Expired from the list (2)', 'the expired entries alone');
  // Bug it catches (issue 1614): the expired entries were drawn in the record's order, the oldest first.
  assert.deepEqual(rows.map((r) => r.querySelector('.row-main').textContent), ['[P2] lib/a.sh:9 an old wait', '[P3] lib/c.sh:2 an older wait'], 'the latest to leave first');
  assert.match(rows[0].querySelector('.row-meta').textContent, /^from card c3-63 #63 expired /);
  assert.equal(rows[0].querySelector('time.since')?.dateTime, iso(T0 - 86400000), 'when it expired (left)');
  assert.equal(rows[0].textContent.includes('seen again'), false, 'an entry nobody saw again says nothing of it');
  assert.match(rows[1].querySelector('.row-meta').textContent, /and was seen again /);
  // Bug it catches (issue 1614): an entry the sort read from an issue (card "#23") said "from card #23 #23".
  assert.match(rows[1].querySelector('.row-meta').textContent, /^from issue #23 expired /);
  // Bug it catches (issue 1614): an expired entry offered a button that files a card; the list is read only.
  assert.equal(box(w).querySelectorAll('.heals-dropped button').length, 0, 'no button among the expired entries');
  // Bug it catches: new data drew the panel again and closed the expired list the owner had open.
  const list = box(w).querySelector('.heals-dropped');
  assert.equal(list.open, false, 'the expired list starts closed');
  list.open = true;
  list.dispatchEvent(new w.Event('toggle'));
  data.panels.declined.data.heals[0].dropped.unshift(gone({ id: 'h0000000000ff' }));
  next(w, data);
  assert.equal(box(w).querySelector('.heals-dropped summary').textContent, 'Expired from the list (3)', 'the new data was drawn');
  assert.equal(box(w).querySelector('.heals-dropped').open, true, 'the expired list the owner opened stays open');
});

// Bugs (issue 1563): the docs list is not on the Board, so a docs drift finding leaves the belt with no trace and no
// docs sweep card can be filed by hand; its "File a docs sweep card" files a self-heals batch card, or another area's;
// a project with docs entries alone shows the empty state.
test('Declined: the Docs list shows each area with its entries, and "File a docs sweep card" files that area\'s docs sweep card on a second click', async () => {
  const w = boot();
  const data = full();
  data.panels.declined.data.lines = [];
  data.panels.declined.data.rest = [];
  data.panels.declined.data.heals = [{ repo: 'sample', repoUrl: REPO, sorted: null, areas: [], entries: [],
    docs: { areas: [{ area: 'area:board', count: 1 }], entries: [entry({ id: 'd00000000000a', area: 'area:board', effect: 'docs drift', finding: '[P3] docs/board.md:9 does not name the Docs list. Proof: docs/board.md:9', why: 'the page omits it' })] } }];
  deliver(w, data);
  const docs = panel(w, 'declined').querySelector('[data-part="docs"]');
  assert.equal(panel(w, 'declined').dataset.state, 'ready', 'a project with docs entries alone is not empty');
  assert.equal(box(w), null, 'no self-heals list with no entry and no sort');
  assert.equal(docs?.querySelector('.heals-title').textContent, 'Docs list (1)');
  const one = docs.querySelector('.heals-area[data-area="area:board"]');
  assert.equal(one.querySelector('.heals-kind').textContent, 'docs drift', "the judge's kind");
  const file = () => panel(w, 'declined').querySelector('[data-part="docs"] .heals-area[data-area="area:board"] button[data-act="heals-docs"]');
  assert.equal(file().textContent, 'File a docs sweep card');
  file().click();
  await settle();
  assert.equal(w.posts.length, 0, 'the first click only asks');
  file().click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'heals', args: ['docs', 'area:board'], repo: 'sample' } }], "the area's docs sweep card, by its label");
});
