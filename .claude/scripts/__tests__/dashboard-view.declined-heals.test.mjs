// SPDX-License-Identifier: Apache-2.0
// The Declined panel and the self-heals lists (issue 1694): the part holds each project's self-heals, docs and dropped
// lists for the Self-heals tab, and the panel draws none of them. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { T0, iso, boot, panel, deliver, next, full, P, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const REPO = 'https://github.com/example/sample-project';
const entry = (over) => ({ repo: 'sample', repoUrl: REPO, id: 'h00000000000a', time: iso(T0 - 600000), card: 'c3-63', issue: 63, url: `${P}/63`, area: 'area:engine',
  finding: '[P2] lib/a.sh:3 the poll waits one turn more. Proof: lib/a.sh:3', why: 'a slower turn, no wrong result', effect: 'self-heals', ...over });
const heals = () => [{ repo: 'sample', repoUrl: REPO, sorted: { time: iso(T0 - 3600000), ended: iso(T0 - 3500000), items: 3, moved: 2 },
  areas: [{ area: 'area:engine', count: 1 }], entries: [entry()],
  docs: { areas: [{ area: 'area:board', count: 1 }], entries: [entry({ id: 'd00000000000a', area: 'area:board', effect: 'docs drift', finding: '[P3] docs/board.md:9 omits the tab' })] },
  dropped: [entry({ id: 'h0000000000dd', finding: '[P2] lib/c.sh:9 an old wait', dropped: { time: iso(T0 - 86400000), why: 'expired' }, left: iso(T0 - 86400000) })] }];

// Bugs it catches: the panel opened with the Self-heals list, the Docs list and "Expired from the list" (each entry as
// its raw text, with batch buttons) above its first declined finding, though the Self-heals tab shows them; a project
// with self-heals entries and no declined line showed the panel as ready, with no declined finding in it. It also
// catches a removal that took the lists or the sort line off the Self-heals tab too.
test('Declined: with self-heals, docs and dropped entries, the panel draws its declined findings and none of those lists; the Self-heals tab draws them', () => {
  const w = boot();
  const data = full();
  data.panels.declined.data.heals = heals();
  deliver(w, data);
  const el = panel(w, 'declined');
  assert.equal(el.querySelectorAll('.rows > .row').length, 1, 'the declined line is drawn');
  assert.match(el.querySelector('.rows > .row').textContent, /no mark here/);
  const shown = el.textContent;
  for (const s of ['Self-heals list', 'Docs list', 'Expired from the list', 'the poll waits one turn more', 'omits the tab', 'an old wait', 'The sort of the queued follow-ups'])
    assert.equal(shown.includes(s), false, `the panel shows "${s}"`);
  assert.equal(el.querySelector('[data-act="heals-batch"], [data-act="heals-docs"], [data-part="heals"], [data-part="docs"], .heals-dropped'), null, 'no list, heading or batch button of the self-heals');
  // The same sample on the Self-heals tab: the lists the panel no longer draws are still drawn there, with the sort line.
  const t = boot({ tab: 'selfheals' });
  deliver(t, data);
  const tab = panel(t, 'selfheals'), all = (sel) => Array.from(tab.querySelectorAll(sel));
  assert.equal(tab.dataset.state, 'ready');
  assert.equal(tab.querySelector('.sh-tile[data-tile="on"] .sh-tile-n').textContent, '1', 'the tile of the entries on the list');
  assert.deepEqual(all('.sh-area').map((c) => c.dataset.area), ['area:engine'], 'the area cards');
  assert.deepEqual(all('.sh-entries .sh-row').map((r) => r.dataset.key), ['sample:h00000000000a'], 'the entries');
  assert.match(tab.querySelector('.sh-docs').textContent, /omits the tab/, 'the Docs list');
  assert.match(tab.querySelector('.sh-sorted').textContent, /^The sort of the queued follow-ups ran .+ ago, and moved 2 of 3 to the lists\.$/, 'the sort line');
  // The dropped entry h0000000000dd is still drawn on the tab: Dropped entries counts it and opens it, expired.
  const drop = tab.querySelector('.sh-dropped-link');
  assert.equal(drop && drop.textContent, 'Dropped entries (1) ›', 'the Dropped entries button');
  drop.click();
  assert.deepEqual(all('.sh-dropped li').map((li) => [li.querySelector('.sh-row-title').textContent, li.querySelector('.sh-gone-why').textContent]),
    [['an old wait', 'expired']], 'the dropped entry h0000000000dd, opened from Dropped entries');
  data.panels.declined.data.lines = [];
  data.panels.declined.data.rest = [];
  next(w, data);
  assert.equal(panel(w, 'declined').dataset.state, 'empty', 'with no declined line the panel is empty, self-heals or not');
});
