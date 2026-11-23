// SPDX-License-Identifier: Apache-2.0
// The Declined panel's Self-heals list (issue 1559): the findings the judge sorted as self-heals, by area, each area
// with "File a batch card". Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { T0, iso, boot, panel, deliver, full, settle, P, cases } from './dashboard-view.helpers.mjs';

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
  assert.match(box(w).querySelector('.heals-sorted').textContent, /^The sort of the queued follow-ups ran, and moved 2 of 3 to this list:/);
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
  data.panels.declined.data.heals = heals().map((x) => ({ ...x, sorted: null }));
  deliver(w, data);
  assert.equal(panel(w, 'declined').dataset.state, 'ready');
  assert.equal(box(w).querySelector('.heals-title').textContent, 'Self-heals list (3)');
  assert.equal(box(w).querySelector('.heals-sorted').textContent, 'The sort of the queued follow-ups has not run yet.');
});
