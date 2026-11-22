// SPDX-License-Identifier: Apache-2.0
// Landed today's record of a card with no GitHub issue (#1346): its text, and File on GitHub, which sends
// card-issue (`conveyor.sh cardissue <card id>`: an issue filed with the card's title and body), then its link once
// filed. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { boot, deliver, next, settle, full, panel, act, iso, T0, cases, TA } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const CARD = 'c20261109T100000-sample-0', URL = 'https://github.com/example/sample/issues/90';
// The Landed part with a card of no issue that landed, its record as given (filed and filedUrl once filed).
function withCard(more) {
  const d = full();
  d.panels.landed.data.cards.unshift({ repo: 'sample', card: CARD, issue: 0, title: 'Optimize the test file f.test.sh', url: null, step: 'landed',
    time: iso(T0 - 600000), start: iso(T0 - 1200000), tookSec: 600, usd: 1, reviews: 1, followups: [], sha: 'abd', pushed: true,
    body: 'Make it cheaper.', filed: null, filedUrl: null, ...more });
  return d;
}
const rowOf = (w) => Array.from(panel(w, 'landed').querySelectorAll('li.row')).find((li) => li.textContent.includes('Optimize the test file f.test.sh'));

// Bugs this guards (#1346 D7): a landed card with no issue lost its text on the Board; File on GitHub was missing,
// sent another action or card, or showed nothing of what the build machine answered; once filed, the row still
// offered File on GitHub (a second issue) in place of the issue's link; a card of an issue offered it too.
test('Landed today: File on GitHub on a landed card with no issue sends card-issue with its card id, then links the issue filed', async () => {
  const w = boot({ tab: 'overview' });
  deliver(w, withCard({}));
  const row = rowOf(w);
  assert.ok(row, 'the card with no issue has its row');
  assert.equal(row.querySelector('.row-body-text').textContent, 'Make it cheaper.', 'its record keeps its text');
  assert.equal(Array.from(panel(w, 'landed').querySelectorAll('[data-act="card-issue"]')).length, 1, 'only the card with no issue offers File on GitHub');
  w.reply = TA.reply(URL);
  act(row, 'card-issue').click();
  await settle();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body), [{ action: 'card-issue', args: [CARD], repo: 'sample' }]);
  assert.match(rowOf(w).textContent, new RegExp(`Filed: ${URL}`));
  next(w, withCard({ filed: 90, filedUrl: URL }));
  const link = rowOf(w).querySelector('a.issue-link[href="' + URL + '"]');
  assert.ok(link && link.textContent === 'Filed as #90', `the row links #90: ${rowOf(w).innerHTML}`);
  assert.equal(act(rowOf(w), 'card-issue'), null, 'a filed card offers File on GitHub no more');
});

// Bug this guards: a refusal of the build machine (the card has not landed, GitHub refused the filing) showed nothing,
// so the owner could not tell the issue was not filed.
test('Landed today: a refused File on GitHub says why, and the button stays', async () => {
  const w = boot({ tab: 'overview' });
  deliver(w, withCard({}));
  w.reply = { ok: false, status: 400, text: () => Promise.resolve('conveyor: card c20261109T100000-sample-0 has not landed; nothing filed') };
  act(rowOf(w), 'card-issue').click();
  await settle();
  assert.match(rowOf(w).textContent, /Not filed: conveyor: card c20261109T100000-sample-0 has not landed; nothing filed/);
  assert.ok(act(rowOf(w), 'card-issue') && !act(rowOf(w), 'card-issue').disabled, 'File on GitHub can be asked again');
});

// Bug this guards: a card with no issue closed as already fixed (step closed: it landed no commit) offered File on
// GitHub, which `cardissue` always refuses, as it files only for a card that landed.
test('Landed today: a card with no issue closed as already fixed keeps its text and offers no File on GitHub', () => {
  const w = boot({ tab: 'overview' });
  deliver(w, withCard({ step: 'closed', sha: null }));
  const row = rowOf(w);
  assert.ok(row && /Already fixed/.test(row.textContent), 'the closed card has its row, marked Already fixed');
  assert.equal(row.querySelector('.row-body-text').textContent, 'Make it cheaper.', 'its record keeps its text');
  assert.equal(act(row, 'card-issue'), null, `the closed card offers no File on GitHub: ${row.innerHTML}`);
});
