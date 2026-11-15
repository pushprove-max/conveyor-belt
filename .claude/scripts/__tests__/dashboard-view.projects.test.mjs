// SPDX-License-Identifier: Apache-2.0
// The dashboard page with every project on the host: picked under Show in the machine head, which the Board and the
// Rules tab follow, each change sent for that project. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { T0, iso, clone, P, boot, deliver, next, settle, CONTROL, full, tabBtn,
  board, bcard, column, inCol, act, record, dragTo, rulesP, rulesAll, panel, fig, cases, pickProject, heading } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

// ---- every project on the host: picked on the Board and the Rules tab, each change sent for that project ----
// Bug: the Board and the Rules tab showed and steered only the record on the host's main, so a second project's
// issues, queue and rules could not be seen or steered from the page.
const W = 'https://github.com/example/WidgetShop/issues';
const wi = (issue, title, over = {}) => ({ repo: 'widgetshop', card: null, issue, title, url: `${W}/${issue}`, ...over });
const day = (n) => iso(T0 - n * 86400000);
// Two records: sample on the host's main (the part itself), and widgetshop under others.
function two() {
  const data = full();
  const wctl = { ...clone(CONTROL), held: [44], order: [46], rules: { ...CONTROL.rules, never: [] }, guard: null };
  const issues = [
    wi(5, 'Plugin thing', { priority: 'P2', labels: ['P2', 'shop:cart'], created: day(20) }),
    wi(41, 'Blocked middle', { priority: 'P1', labels: ['P1', 'shop:cart'], created: day(40) }),
    wi(42, 'Blocked oldest', { priority: 'P2', labels: ['P2'], created: day(70) }),
    wi(43, 'Blocked newest', { priority: 'P0', labels: ['P0', 'shop:pay'], created: day(10) }),
    wi(44, 'Held widget', { priority: 'P2', labels: ['P2'], created: day(5) }),
    wi(45, 'Label held', { priority: 'P3', labels: ['backlog'], created: day(6) }),
    wi(46, 'Widget next', { priority: 'P1', labels: ['P1', 'shop:pay'], created: day(7) }),
    wi(47, 'Waits on next', { priority: 'P2', labels: ['P2'], created: day(8) }),
    wi(48, 'Skipped one', { priority: 'P2', labels: ['shop:legacy'], created: day(9) }),
    wi(49, 'Widget later', { priority: 'P3', labels: [], created: day(3) }),
  ];
  const held = [
    wi(41, 'Blocked middle', { reasons: [{ kind: 'card', step: 'blocked', card: 'c7-41' }] }), wi(42, 'Blocked oldest', { reasons: [{ kind: 'card', step: 'blocked', card: 'c7-42' }] }),
    wi(43, 'Blocked newest', { reasons: [{ kind: 'card', step: 'blocked', card: 'c7-43' }] }), wi(44, 'Held widget', { labels: ['P2'], reasons: [{ kind: 'you' }] }),
    wi(45, 'Label held', { labels: ['backlog'], reasons: [{ kind: 'label', label: 'backlog' }] }), wi(47, 'Waits on next', { reasons: [{ kind: 'waits', waitsFor: [46] }] }),
    wi(48, 'Skipped one', { reasons: [{ kind: 'rule', rule: 'shop:legacy' }] }),
  ];
  const open = { count: 10, split: { queued: 2, you: 1, labelOrRule: 6, belt: 1 }, held, issues };
  const queue = [wi(46, 'Widget next', { priority: 'P1', followup: false, retried: false, areas: ['shop:pay'] }), wi(49, 'Widget later', { priority: 'P3', followup: false, retried: false, areas: [] })];
  // Blocked for 10, 1 and 100 minutes: the longest blocked is not the first in the column.
  const blocked = [[41, 600000], [42, 60000], [43, 6000000]].map(([n, ms]) => wi(n, `Blocked ${n}`, { card: `c7-${n}`, reason: 'tests failed', since: iso(T0 - ms) }));
  const wboard = { ...clone(data.panels.board.data), repo: 'widgetshop', control: wctl, areaPrefix: 'shop:', held: [wi(44, 'Held widget')], queue, skipped: [wi(48, 'Skipped one', { rule: 'shop:legacy' })],
    waits: [wi(47, 'Waits on next', { waitsFor: [46] })], building: [wi(5, 'Plugin thing', { card: 'c4-5', step: 'build', stepAt: iso(T0 - 60000), usd: null, reading: false })],
    review: [], waiting: [], blocked, landed: [wi(30, 'Landed widget', { card: 'c3-30', step: 'landed', time: iso(T0 - 3600000), usd: 1, reviews: 1 })], open };
  const wrules = { ...clone(data.panels.rules.data), repo: 'widgetshop', control: wctl, areaPrefix: 'shop:', held: [wi(44, 'Held widget')], queue, skipped: wboard.skipped, waits: wboard.waits,
    building: 1, onBelt: [5], blocked, forecast: null, open };
  data.panels.board.data.areaPrefix = 'area:';
  Object.assign(data.panels.board.data, { repos: ['sample', 'widgetshop'], others: { widgetshop: wboard } });
  Object.assign(data.panels.rules.data, { repos: ['sample', 'widgetshop'], others: { widgetshop: wrules } });
  data.panels.needs.data.cards.blocked.push(...blocked.map((x) => ({ ...x })));
  data.panels.machine.data.repos = ['sample', 'widgetshop'];
  return data;
}
const pickRepo = pickProject;
const choose = (w, root, a, value) => { const s = act(root, a); s.value = value; s.dispatchEvent(new w.Event('change')); };
// The Rules tab's Open issues panel.
const listP = (w) => panel(w, 'rules-issues');
const rows = (w) => Array.from(listP(w).querySelectorAll('.rules-issue'), (r) => [Number(r.dataset.issue), r.dataset.state]);

test('every project: the Board shows the picked project\'s cards and rules, and a hold from it is sent for that project alone', async () => {
  const w = boot({ tab: 'control' });
  deliver(w, two());
  assert.equal(act(board(w), 'repo'), null, 'the Board has no picker of its own');
  assert.deepEqual(Array.from(w.document.querySelectorAll('#machine-head [data-act="project"] option'), (o) => o.value), ['', 'sample', 'widgetshop'], 'Show lists every record of the host file');
  assert.equal(heading(board(w)), 'Board: sample', 'it opens on the main record, and says so');
  assert.deepEqual(inCol(w, 'building'), [5]);
  pickRepo(w, 'widgetshop');
  assert.equal(new URL(w.location.href).searchParams.get('repo'), 'widgetshop', 'the choice is kept in the address');
  assert.deepEqual(['queue', 'building', 'needs'].map((k) => inCol(w, k)), [[46, 49], [5], [41, 42, 43]], 'its queue, its belt and its blocked cards');
  assert.deepEqual(inCol(w, 'held').sort((a, b) => a - b), [41, 42, 43, 44, 45, 47, 48], 'its open issues not queued, each with why');
  assert.equal(heading(board(w)), 'Board: widgetshop');
  act(bcard(w, 46), 'hold').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'hold', args: ['46'], repo: 'widgetshop' } }], 'the hold names the project picked, never main');
  // Its blocked card is answered in Needs you (which names the card's own repository), the column linking there.
  assert.ok(act(column(w, 'needs').querySelector('.bcard[data-issue="41"]'), 'needs-open'), 'the blocked card links into Needs you');
  // The Rules tab shows the same project: its rules, and its changes go to it.
  w.document.getElementById('tab-rules').click();
  assert.ok(rulesAll(w).every((p) => act(p, 'repo') === null), 'the Rules have no picker of their own');
  assert.equal(heading(rulesP(w)), 'Rules: widgetshop');
  assert.equal(rulesP(w).querySelector('.rules-row[data-rule="order"]').textContent.includes('#46 Widget next'), true, 'its pinned order');
  act(rulesP(w), 'rule-P1').click();
  act(rulesP(w), 'rule-P1').click();  // P1 skips its queued issues: the second click turns it off
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'rules', args: ['P1=off'], repo: 'widgetshop' } }]);
  // A reload, or a link, keeps the project.
  const again = boot({ query: '?tab=rules&repo=widgetshop' });
  deliver(again, two());
  assert.equal(heading(rulesP(again)), 'Rules: widgetshop');
  assert.deepEqual(rows(again).map((r) => r[0]).sort((a, b) => a - b), [5, 41, 42, 43, 44, 45, 46, 47, 48, 49]);
});

test('every project: a host file with one record shows no picker and steers that record as today', async () => {
  const w = boot({ tab: 'control' });
  deliver(w, full());
  assert.equal(act(board(w), 'repo'), null, 'no picker');
  const r = boot({ tab: 'rules' });
  deliver(r, full());
  assert.ok(rulesAll(r).every((p) => act(p, 'repo') === null), 'no picker on Rules either');
  assert.deepEqual([heading(board(w)), heading(rulesP(r))], ['Board', 'Rules'], 'one project: the heading names none');
  act(bcard(w, 21), 'hold').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'hold', args: ['21'], repo: 'sample' } }]);
});

test('every project: the Rules list shows every open issue with its state; blocked sorted by age is oldest first', () => {
  const w = boot({ query: '?tab=rules&repo=widgetshop' });
  deliver(w, two());
  assert.deepEqual(rows(w).sort((a, b) => a[0] - b[0]), [[5, 'building'], [41, 'blocked'], [42, 'blocked'], [43, 'blocked'], [44, 'you'], [45, 'label'], [46, 'next'], [47, 'waits'], [48, 'rule'], [49, 'next']]);
  const row = (n) => listP(w).querySelector(`.rules-issue[data-issue="${n}"]`);
  assert.match(row(47).textContent, /Waiting on #46/);
  assert.match(row(41).textContent, /Blocked middle.*P1.*cart.*40 d 0 h old.*Blocked/s, 'number, title, priority, area, age and state');
  assert.match(row(45).textContent, /backlog.*Held by a label/s, 'its labels');
  choose(w, listP(w),'istate', 'blocked');
  choose(w, listP(w),'isort', 'age');
  assert.deepEqual(rows(w).map((r) => r[0]), [42, 41, 43], 'oldest first');
  const u = new URL(w.location.href).searchParams;
  assert.deepEqual([u.get('repo'), u.get('istate'), u.get('isort')], ['widgetshop', 'blocked', 'age'], 'kept in the address with the project');
  choose(w, listP(w),'idir', 'asc');
  assert.deepEqual(rows(w).map((r) => r[0]), [43, 41, 42]);
  // Filters by priority, area and label, and the search by number or title.
  choose(w, listP(w),'istate', '');
  choose(w, listP(w),'iarea', 'shop:pay');
  assert.deepEqual(rows(w).map((r) => r[0]).sort((a, b) => a - b), [43, 46]);
  choose(w, listP(w),'iarea', '');
  choose(w, listP(w),'ilabel', 'backlog');
  assert.deepEqual(rows(w).map((r) => r[0]), [45]);
  choose(w, listP(w),'ilabel', '');
  choose(w, listP(w),'iprio', 'P0');
  assert.deepEqual(rows(w).map((r) => r[0]), [43]);
  choose(w, listP(w),'iprio', '');
  const s = act(listP(w), 'iq'); s.value = 'widget'; s.dispatchEvent(new w.Event('input'));
  assert.deepEqual(rows(w).map((r) => r[0]).sort((a, b) => a - b), [44, 46, 49]);
});

test('every project: three filtered rows held at once, for that project only; select all takes only the rows shown', async () => {
  const w = boot({ query: '?tab=rules&repo=widgetshop' });
  deliver(w, two());
  const pick = (n) => { const b = listP(w).querySelector(`.rules-issue[data-issue="${n}"] [data-act="pick"]`); b.checked = true; b.dispatchEvent(new w.Event('change')); };
  // Select all takes only the filtered rows: the three blocked ones.
  choose(w, listP(w),'istate', 'blocked');
  const all = act(listP(w), 'pick-all'); all.checked = true; all.dispatchEvent(new w.Event('change'));
  assert.equal(act(listP(w), 'bulk-hold').textContent, 'Hold 3', 'the action names its count before it runs');
  assert.equal(act(listP(w), 'bulk-retry').textContent, 'Retry 3');
  act(listP(w), 'bulk-hold').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'hold', args: ['41', '42', '43'], repo: 'widgetshop' } }], 'exactly those three, for this project');
  assert.equal(act(listP(w), 'bulk-hold').textContent, 'Hold 0', 'the selection is cleared once done');
  // Picked one at a time, across filters; Queue takes the ones held by you, Retry the blocked ones, one a request, on
  // a second click (a retry costs a build).
  choose(w, listP(w),'istate', '');
  [44, 41, 42].forEach(pick);
  assert.equal(act(listP(w), 'bulk-release').textContent, 'Queue 1');
  act(listP(w), 'bulk-retry').click();
  await settle();
  assert.deepEqual(w.posts, [], 'the first click of Retry only asks');
  assert.equal(act(listP(w), 'bulk-retry').textContent, 'Click again to retry 2');
  act(listP(w), 'bulk-retry').click();
  await settle();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body), [{ action: 'retry', args: ['41'], repo: 'widgetshop' }, { action: 'retry', args: ['42'], repo: 'widgetshop' }]);
});

test('every project: Retry armed for one selection does not retry another: changing the cards asks again', async () => {
  // The bug: the armed key was the same for any selection, so a Retry armed for #41 retried #42 at once.
  const w = boot({ query: '?tab=rules&repo=widgetshop' });
  deliver(w, two());
  const pick = (n, on) => { const b = listP(w).querySelector(`.rules-issue[data-issue="${n}"] [data-act="pick"]`); b.checked = on; b.dispatchEvent(new w.Event('change')); };
  pick(41, true);
  act(listP(w), 'bulk-retry').click();
  assert.equal(act(listP(w), 'bulk-retry').textContent, 'Click again to retry 1');
  pick(41, false); pick(42, true);
  assert.equal(act(listP(w), 'bulk-retry').textContent, 'Retry 1', 'a new selection is not shown as armed');
  act(listP(w), 'bulk-retry').click();
  await settle();
  assert.deepEqual(w.posts, [], 'the first click for #42 only asks');
  act(listP(w), 'bulk-retry').click();
  await settle();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body), [{ action: 'retry', args: ['42'], repo: 'widgetshop' }]);
});

test('every project: a held issue that is also blocked can be released from the list', () => {
  const w = boot({ query: '?tab=rules&repo=widgetshop' });
  const d = two();
  d.panels.rules.data.others.widgetshop.control.held = [44, 41];
  deliver(w, d);
  const b = listP(w).querySelector('.rules-issue[data-issue="41"] [data-act="pick"]'); b.checked = true; b.dispatchEvent(new w.Event('change'));
  assert.deepEqual(['bulk-release', 'bulk-hold', 'bulk-retry'].map((a) => act(listP(w), a).textContent), ['Queue 1', 'Hold 0', 'Retry 1']);
});

// The host's answer, held back until `open` is called: another project can be picked while it is out.
function gated(w) {
  let open = null;
  w.reply = { ok: true, status: 200, text: () => new Promise((r) => { open = () => r('done'); }) };
  return () => { w.reply = null; open(); };
}

test('every project: a change in several requests names the project it began in, whichever is picked before they are answered', async () => {
  // The Board: a held card dropped on a queued one is ordered, then released, both in its project.
  const w = boot({ query: '?tab=control&repo=widgetshop' });
  deliver(w, two());
  const open = gated(w);
  dragTo(w, bcard(w, 44), bcard(w, 46));
  pickRepo(w, 'sample');
  await settle(); open();
  await settle(); await settle(); await settle();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body), [{ action: 'order', args: ['44', '46'], repo: 'widgetshop' }, { action: 'release', args: ['44'], repo: 'widgetshop' }]);
  // Rules: two retries, one a request.
  const r = boot({ query: '?tab=rules&repo=widgetshop' });
  deliver(r, two());
  [41, 42].forEach((n) => { const b = listP(r).querySelector(`.rules-issue[data-issue="${n}"] [data-act="pick"]`); b.checked = true; b.dispatchEvent(new r.Event('change')); });
  const go = gated(r);
  act(listP(r), 'bulk-retry').click();
  act(listP(r), 'bulk-retry').click();
  pickRepo(r, 'sample');
  await settle(); go();
  await settle(); await settle(); await settle();
  assert.deepEqual(r.posts.splice(0).map((p) => p.body), [{ action: 'retry', args: ['41'], repo: 'widgetshop' }, { action: 'retry', args: ['42'], repo: 'widgetshop' }]);
});

test('every project: Order first pins the picked issues in that project\'s order; Move up and down reorder the pins; Unpin removes one', async () => {
  const w = boot({ query: '?tab=rules&repo=widgetshop' });
  deliver(w, two());
  const pick = (n) => { const b = listP(w).querySelector(`.rules-issue[data-issue="${n}"] [data-act="pick"]`); b.checked = true; b.dispatchEvent(new w.Event('change')); };
  pick(49);
  assert.equal(act(listP(w), 'bulk-order').textContent, 'Order first 1');
  act(listP(w), 'bulk-order').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'order', args: ['49', '46'], repo: 'widgetshop' } }], 'first, ahead of the pin already there');
  w.reply = record({ held: [44], order: [49, 46], rules: { ...CONTROL.rules, never: [] }, guard: null });
  const pins = () => rulesP(w).querySelector('.rules-row[data-rule="order"]');
  const pin = (n, a) => pins().querySelector(`[data-issue="${n}"] [data-act="${a}"]`);
  // The answer is not in yet; a snapshot with the two pins.
  const d = two();
  d.panels.rules.data.others.widgetshop.control.order = [49, 46];
  next(w, d);
  // Bug (UX38): the first pin offered Move up and the last Move down, greyed; neither is shown.
  assert.equal(pin(49, 'pin-up'), null, 'the first offers no Move up');
  assert.equal(pin(46, 'pin-down'), null, 'the last offers no Move down');
  pin(49, 'pin-down').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'order', args: ['46', '49'], repo: 'widgetshop' } }]);
  next(w, d);
  pin(46, 'pin-up').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'order', args: ['46', '49'], repo: 'widgetshop' } }]);
  next(w, d);
  pin(46, 'unpin').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'unpin', args: ['46'], repo: 'widgetshop' } }]);
});

test('every project: the Board filters every column by priority, area and label and sorts it, the choice kept in the address', async () => {
  const w = boot({ query: '?tab=control&repo=widgetshop' });
  // Two cards building: #5 picked up two hours ago and in its tests for a minute, #50 picked up an hour ago and still
  // in its build. Time in Building is from the pick-up, not the step in progress.
  const d = two();
  d.panels.board.data.others.widgetshop.building = [
    wi(5, 'Plugin thing', { card: 'c4-5', step: 'tests', pickedAt: iso(T0 - 7200000), stepAt: iso(T0 - 60000), usd: null, reading: false }),
    wi(50, 'Still building', { card: 'c4-50', step: 'build', priority: 'P2', labels: ['P2', 'shop:pay'], pickedAt: iso(T0 - 3600000), stepAt: iso(T0 - 3600000), usd: null, reading: false })];
  // Time in Held or Queue is the snapshot's since, against the order the issues were opened in: #42, the oldest
  // issue, came to Held a day ago, #43, the newest, 30 days ago; #49 was opened after #46 and queued before it.
  const wb = d.panels.board.data.others.widgetshop;
  const since = { 41: day(5), 42: day(1), 43: day(30), 44: day(1), 46: day(1), 49: day(2) };
  wb.open.held.concat(wb.queue).forEach((x) => { if (since[x.issue]) x.since = since[x.issue]; });
  deliver(w, d);
  choose(w, board(w), 'bsort', 'number');
  choose(w, board(w), 'bdir', 'desc');
  assert.deepEqual(inCol(w, 'needs'), [43, 42, 41], 'sorted by number, highest first');
  choose(w, board(w), 'bsort', 'time');
  assert.deepEqual(inCol(w, 'needs'), [42, 41, 43], 'by time in the column, descending: the shortest blocked first');
  assert.deepEqual(inCol(w, 'queue'), [46, 49], 'the queue, the latest queued first, not the newest issue');
  assert.deepEqual(inCol(w, 'held'), [44, 45, 48, 42, 41, 43, 47], 'held, in its groups, the latest held first in each (#42, #41, #43 the blocked), not the newest issue');
  assert.deepEqual(inCol(w, 'building'), [50, 5], 'building, the latest picked up first');
  choose(w, board(w), 'bdir', 'asc');
  assert.deepEqual(inCol(w, 'needs'), [43, 41, 42], 'by time in the column: the longest there first');
  assert.deepEqual(['queue', 'held', 'building'].map((k) => inCol(w, k)), [[49, 46], [44, 45, 48, 43, 41, 42, 47], [5, 50]], 'the longest held or queued first, not the oldest issue');
  // #49, queued two days ago, held now (the host answers at T0) beside #44, held a day ago: it came to Held when the
  // hold was answered, not when it came to the Queue, so #44 has been held longer.
  w.reply = record({ ...wb.control, held: [44, 49] });
  act(bcard(w, 49), 'hold').click();
  await settle();
  assert.deepEqual(['queue', 'held'].map((k) => inCol(w, k)), [[46], [44, 49, 45, 48, 43, 41, 42, 47]], 'a card held since the snapshot sorts by when it was held, not by its time in the Queue');
  // Each answer dates only the cards it moves: #46 held a minute later leaves #49 held at T0, so #49 stays first.
  const answer = async (n, a, held, at) => { w.reply = record({ ...wb.control, held }, at); act(bcard(w, n), a).click(); await settle(); };
  await answer(46, 'hold', [44, 49, 46], T0 + 60000);
  assert.deepEqual(inCol(w, 'held'), [44, 49, 46, 45, 48, 43, 41, 42, 47], 'a later answer does not redate a card it did not move');
  // #44, held a day ago, released and held again: held since the second hold, not the snapshot's day.
  await answer(44, 'release', [49, 46], T0 + 120000);
  await answer(44, 'hold', [49, 46, 44], T0 + 180000);
  assert.deepEqual(inCol(w, 'held'), [49, 46, 44, 45, 48, 43, 41, 42, 47], 'released and held again: held since the hold, not the snapshot\'s time');
  // #46 (queued a day ago) and #49 (two days ago) held and released again, #46 first: each is queued since its
  // release, so #46 has waited longer, against the snapshot's Queue times.
  await answer(46, 'release', [49, 44], T0 + 240000);
  await answer(49, 'release', [44], T0 + 300000);
  assert.deepEqual(['queue', 'held'].map((k) => inCol(w, k)), [[46, 49], [44, 45, 48, 43, 41, 42, 47]], 'held and released again: queued since the release, not the snapshot\'s time');
  choose(w, board(w), 'barea', 'shop:cart');
  assert.deepEqual(['building', 'needs', 'queue'].map((k) => inCol(w, k)), [[5], [41], []]);
  choose(w, board(w), 'barea', '');
  choose(w, board(w), 'bprio', 'P0');
  assert.deepEqual(inCol(w, 'needs'), [43]);
  assert.deepEqual(inCol(w, 'landed'), [], 'a landed card, its issue closed and its priority not known, matches no priority: the filter hides it');
  choose(w, board(w), 'bprio', '');
  assert.deepEqual(inCol(w, 'landed'), [30], 'with no filter the landed card shows');
  choose(w, board(w), 'blabel', 'backlog');
  assert.deepEqual(inCol(w, 'held'), [45]);
  assert.deepEqual(inCol(w, 'landed'), [], 'nor a label filter: every filter applies to Landed');
  const u = new URL(w.location.href).searchParams;
  assert.deepEqual([u.get('repo'), u.get('blabel'), u.get('bsort'), u.get('bdir')], ['widgetshop', 'backlog', 'time', 'asc']);
  const again = boot({ query: `?${u.toString()}` });
  deliver(again, two());
  assert.deepEqual(inCol(again, 'held'), [45], 'a reload keeps the filter');
});

test('every project: a stopped card waiting for the owner\'s yes is not blocked and is not offered Retry', () => {
  const w = boot({ query: '?tab=rules&repo=widgetshop' });
  const d = two();
  // #42's card stopped for the owner's yes: Needs you lists it as waiting, not blocked.
  d.panels.rules.data.others.widgetshop.blocked = d.panels.rules.data.others.widgetshop.blocked.filter((x) => x.issue !== 42);
  deliver(w, d);
  assert.equal(listP(w).querySelector('.rules-issue[data-issue="42"]').dataset.state, 'approve');
  const b = listP(w).querySelector('.rules-issue[data-issue="42"] [data-act="pick"]'); b.checked = true; b.dispatchEvent(new w.Event('change'));
  assert.equal(act(listP(w), 'bulk-retry').textContent, 'Retry 0');
  assert.equal(act(listP(w), 'bulk-retry').disabled, true);
});

test('every project: Order first is not offered when the order would be longer than the host takes in one request', () => {
  const w = boot({ query: '?tab=rules&repo=widgetshop' });
  const d = two();
  d.panels.rules.data.others.widgetshop.control.order = Array.from({ length: 500 }, (_, i) => 1000 + i);
  deliver(w, d);
  const b = listP(w).querySelector('.rules-issue[data-issue="49"] [data-act="pick"]'); b.checked = true; b.dispatchEvent(new w.Event('change'));
  assert.equal(act(listP(w), 'bulk-order').disabled, true, '501 issues in one order: the host refuses it');
  act(listP(w), 'bulk-order').click();
  assert.deepEqual(w.posts, [], 'nothing is sent');
});

test('every project: a name in the address that is no record of the host file shows the main record', () => {
  const w = boot({ query: '?tab=control&repo=__proto__' });
  deliver(w, two());
  assert.equal(heading(board(w)), 'Board: sample');
  assert.deepEqual(inCol(w, 'building'), [5]);
});

test('every project: Back to an address with another project shows that project again', () => {
  const w = boot({ tab: 'control' });
  deliver(w, two());
  tabBtn(w, 'rules').click();
  pickRepo(w, 'widgetshop');
  tabBtn(w, 'control').click();
  assert.equal(heading(board(w)), 'Board: widgetshop');
  // Back twice: the Board for the main record, as it was first opened.
  w.history.replaceState(null, '', 'https://dash.test/index.html?tab=control');
  w.dispatchEvent(new w.PopStateEvent('popstate'));
  assert.equal(heading(board(w)), 'Board: sample', 'the project the address names');
  assert.deepEqual(inCol(w, 'needs').length, 2, 'its own cards');
});

test('every project: the head says how many cards need the owner in each project', () => {
  const w = boot();
  deliver(w, two());
  assert.equal(fig(w, 'needs'), '5 · sample 2 · widgetshop 3', 'a block in the project not on screen is seen');
  const one = boot();
  deliver(one, full());
  assert.equal(fig(one, 'needs'), '2', 'one project: the count alone');
});

// Bug: the Board kept the released cards by issue number alone and never forgot them, so a card released in one
// project said "Released from hold" on the card with the same number in another project picked after it.
test('every project: a card released in one project gives no release notice to the same number in another', async () => {
  const w = boot({ tab: 'control' });
  const d = two(), b = d.panels.board.data, wb = b.others.widgetshop;
  b.control = { ...clone(CONTROL), held: [76, 44] };
  b.held = b.held.concat([{ repo: 'sample', card: null, issue: 44, title: 'Second half', url: `${P}/44` }]);
  b.open = { ...b.open, held: [
    { repo: 'sample', issue: 76, title: 'Split the PROD stack', url: `${P}/76`, priority: 'P2', labels: [], reasons: [{ kind: 'you' }] },
    { repo: 'sample', issue: 44, title: 'Second half', url: `${P}/44`, priority: 'P2', labels: [], reasons: [{ kind: 'you' }, { kind: 'waits', waitsFor: [20] }] },
  ] };
  // In widgetshop #44 is held by nobody and waits on #46.
  wb.control = { ...wb.control, held: [] };
  wb.held = [];
  wb.open = { ...wb.open, held: wb.open.held.map((x) => (x.issue === 44 ? { ...x, reasons: [{ kind: 'waits', waitsFor: [46] }] } : x)) };
  deliver(w, d);
  w.reply = record({ held: [76] });
  act(bcard(w, 44), 'release').click();
  await settle(); await settle();
  assert.match(bcard(w, 44).textContent, /Released from hold\. Still waits on #20\./, 'released here: it says so');
  pickRepo(w, 'widgetshop');
  assert.equal(heading(board(w)), 'Board: widgetshop');
  assert.ok(bcard(w, 44), 'widgetshop #44 is drawn');
  assert.doesNotMatch(bcard(w, 44).textContent, /Released from hold/, 'nothing was released in widgetshop');
});
