// SPDX-License-Identifier: Apache-2.0
// The Board's Time (12-hour or 24-hour) and Date (mm/dd/yyyy or dd/mm/yyyy), set in Customize (issue 458): the times
// and dates the panels write follow them, and a change shows at once. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { STORE, T0, $, boot, panel, deliver, next, full, saved, clone, issuesP, cases, iso, trackOf, settle } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const SENT = 'conveyor-board-time-sent';  // app.js TIME_SENT_KEY: set once this browser has sent a Time

const pick = (w, name, value) => {
  const r = $(w, `#customize input[name="choice-${name}"][value="${value}"]`);
  r.checked = true; r.dispatchEvent(new w.Event('change', { bubbles: true }));
};

// A card picked up on an earlier day shows its date and time; the head's clock its time. Bug it catches: a time or
// date in the browser's own style whatever the owner chose, or one that keeps the old style until the page is reloaded.
test('a card\'s start and the head\'s clock follow Customize\'s Time and Date, and a change redraws them at once', () => {
  const w = boot();
  const data = full();
  Object.assign(data.panels.belt.data.cards[0], { start: '2026-11-08T20:15:00Z', pickedAt: '2026-11-08T20:15:00Z', priorSec: 0 });
  deliver(w, data);
  const times = () => panel(w, 'belt').querySelector('li[data-key="sample:c3-63"] .card-times').textContent;
  const clock = () => w.document.getElementById('clock').textContent;
  assert.match(times(), /^started 11\/08\/2026, 3:15 PM · /, 'by default: mm/dd/yyyy and 12-hour');
  assert.equal(clock(), '12:00:00 PM');
  w.document.getElementById('customize-open').click();
  assert.deepEqual(Array.from(w.document.querySelectorAll('#customize input[name="choice-time"]'), (r) => [r.value, r.checked]), [['12-hour', true], ['24-hour', false]]);
  assert.deepEqual(Array.from(w.document.querySelectorAll('#customize input[name="choice-date"]'), (r) => r.parentNode.textContent), ['mm/dd/yyyy', 'dd/mm/yyyy']);
  pick(w, 'time', '24-hour');
  assert.match(times(), /^started 11\/08\/2026, 15:15 · /, 'redrawn with no new data: 24-hour');
  assert.equal(clock(), '12:00:00');
  pick(w, 'date', 'dd/mm/yyyy');
  assert.match(times(), /^started 08\/11\/2026, 15:15 · /, 'redrawn with no new data: dd/mm/yyyy');
  assert.equal(w.navigations, 0, 'no reload');
  assert.deepEqual([saved(w).time, saved(w).date], ['24-hour', 'dd/mm/yyyy'], 'kept with the layout');
  pick(w, 'time', '12-hour');
  assert.match(times(), /^started 08\/11\/2026, 3:15 PM · /, 'back to 12-hour with dd/mm/yyyy kept');
  // Issue 506. Bug it catches: the Time kept in this browser alone, so the plugin's Build pane wrote AM and PM with 24-hour set.
  assert.deepEqual(w.posts, [{ url: 'time', body: { time: '24-hour' } }, { url: 'time', body: { time: '12-hour' } }],
    'each Time chosen is sent to the server, and the Date is not');
});

// Issue 506. Bugs it catches: a 24-hour Time this browser kept before the page sent it never reaching the server
// (only a click sent it), and Restore putting the Board back to 12-hour while the plugin's Build pane kept 24-hour.
test('a kept Time is sent when the Board opens, and the Time Restore puts back is sent too', async () => {
  const w = boot({ store: { [STORE]: JSON.stringify({ time: '24-hour' }) } });
  await settle();
  assert.deepEqual(w.posts, [{ url: 'time', body: { time: '24-hour', first: true } }], 'sent on opening, with no click, as one kept only if the server has none');
  assert.deepEqual(w.timeJson, { time: '24-hour' }, 'the server, which kept no Time, keeps it');
  // Issue 559. Bug it catches: the send not recorded, so every later visit sends the kept Time again (review E4).
  assert.equal(w.localStorage.getItem(SENT), '1', 'the send is recorded in this browser');
  w.document.getElementById('customize-open').click();
  w.document.getElementById('restore-layout').click();
  assert.deepEqual(w.posts.slice(1), [{ url: 'time', body: { time: '12-hour' } }], 'Restore sends 12-hour');
});

// Bug it catches (review E4): each visit sent the kept Time again, so a browser that set a Time earlier undid the Time
// set later in another browser. The marker is the one the case above sees written.
test('a browser that has sent a Time sends nothing when the Board opens again', async () => {
  const w = boot({ store: { [STORE]: JSON.stringify({ time: '24-hour' }), [SENT]: '1' } });
  await settle();
  assert.deepEqual(w.posts, [], 'a Time sent on an earlier visit is not sent again');
});

// Bug it catches (#1461 B-R138): a browser that kept 24-hour before the Board sent any Time sent it on its first open
// after the upgrade as a plain Time, so it undid the 12-hour set since in another browser (the last Time you set is
// the one kept). It is sent as first, which the server keeps only with no Time kept (the server's own check, so a Time
// set between a read and this send is safe too: dashboard-server-time.test.sh), and the browser marks its Time sent.
test('a kept Time does not overwrite a Time the server already keeps when the Board opens', async () => {
  const w = boot({ store: { [STORE]: JSON.stringify({ time: '24-hour' }) }, serverTime: { time: '12-hour' } });
  await settle();
  assert.deepEqual(w.posts, [{ url: 'time', body: { time: '24-hour', first: true } }], 'the opening send is the first-only kind');
  assert.deepEqual(w.timeJson, { time: '12-hour' }, 'the kept 24-hour does not overwrite the server\'s 12-hour');
  assert.equal(w.localStorage.getItem(SENT), '1', 'the browser does not send it again on its next visit');
});

// Bug it catches (review E4): a browser whose only change was Density (which saves the default 12-hour) sent that
// default and undid the Time set later in another browser.
test('a browser that kept only the default Time sends nothing when the Board opens', async () => {
  const w = boot({ store: { [STORE]: JSON.stringify({ density: 'compact', time: '12-hour' }) } });
  await settle();
  assert.deepEqual(w.posts, [], 'the default Time that a Density change saved is not sent');
});

// The metrics panel's days are dates in the kept Date: 9 November with dd/mm/yyyy is 09/11/2026. Bug it catches: a
// day written as the collector gives it ("2026-11-09") whatever the owner chose.
test('metrics: with 24-hour Time and dd/mm/yyyy Date kept, its days are written dd/mm/yyyy', () => {
  const w = boot({ store: { [STORE]: JSON.stringify({ time: '24-hour', date: 'dd/mm/yyyy' }) } });
  deliver(w, full());
  const days = panel(w, 'metrics').querySelector('[data-chart="days"]');
  assert.equal(days.querySelectorAll('g.bar')[6].querySelector('title').textContent, '09/11/2026: 2 landed, 2 blocked');
  assert.equal(w.document.getElementById('clock').textContent, '12:00:00', 'the head\'s clock in 24-hour from the first draw');
});

// A row kept through a redraw (Needs you reuses its rows by key) holds the tooltip written when it was made. Bugs it
// catches (review of issue 458): after Time is set to 24-hour, a waiting card's time still reads "11:50:00 AM"; or
// every row is made again for it, so an answer typed in a decision and not sent yet is lost.
test('Needs you: a waiting card\'s time tooltip follows a change of Time at once, and a typed answer stays', () => {
  const w = boot();
  deliver(w, full());
  const tipOf = () => panel(w, 'needs').querySelector('[data-group="waiting"] .rows time.since').title;
  const field = () => panel(w, 'needs').querySelector('li[data-key="decision:bookshop:q-ship@2026-11-09T10:00:00Z"] input');
  assert.equal(tipOf(), '11/09/2026, 11:50:00 AM');
  const typed = field();
  typed.value = 'Ship on Monday';
  w.document.getElementById('customize-open').click();
  pick(w, 'time', '24-hour');
  assert.equal(tipOf(), '11/09/2026, 11:50:00');
  assert.equal(field(), typed, 'the decision\'s row is the same');
  assert.equal(field().value, 'Ship on Monday');
});

// Needs you keeps a blocked card's row through a redraw, and with it its "Every step". Bug it catches (review of issue
// 458): after Time is set to 24-hour, its steps' tips, its line and its earlier attempt's line still say AM or PM; or it
// is drawn again closed, so the reader loses the step they had open.
test('Needs you: a blocked card\'s open "Every step" follows a change of Time at once, and stays open', () => {
  const w = boot();
  const data = full();
  const records = [{ name: 'building', state: 'done', sec: 600, at: iso(T0 - 1500000) }, { name: 'stopped', state: 'failed', sec: 5, at: iso(T0 - 900000), why: 'the tests failed' }];
  const prior = { card: 'c2-10', start: iso(T0 - 3600000), end: iso(T0 - 2400000), sec: 1200, reason: 'tests failed', track: trackOf('++++!.', '', { at: null, since: null }) };
  Object.assign(data.panels.needs.data.cards.blocked[0], { track: { ...trackOf('++!...', ''), at: null, records }, earlier: [prior] });
  deliver(w, data);
  const det = () => panel(w, 'needs').querySelector('li[data-key="blocked:c2-13"] details.track-detail');
  const said = () => [det().querySelector(':scope > details.tl-earlier > summary').textContent, det().querySelector(':scope > .tl-total').textContent,
    det().querySelector(':scope > ol.timeline > li .tl-tip').textContent];
  det().open = true;
  det().querySelector(':scope > details.tl-earlier').open = true;
  assert.deepEqual(said(), ['Earlier attempt: 11:00 AM to 11:20 AM, 20 min, ended: tests failed', '20 min from 11:25 AM to 11:45 AM, 10 min of it in steps',
    'Build: done, 10 min, 11:25 AM to 11:35 AM']);
  w.document.getElementById('customize-open').click();
  pick(w, 'time', '24-hour');
  assert.deepEqual(said(), ['Earlier attempt: 11:00 to 11:20, 20 min, ended: tests failed', '20 min from 11:25 to 11:45, 10 min of it in steps',
    'Build: done, 10 min, 11:25 to 11:35']);
  assert.equal(det().open, true, '"Every step" stays open');
  assert.equal(det().querySelector(':scope > details.tl-earlier').open, true, 'its earlier attempt stays open');
});

// Rules draws nothing for a refresh that changes only readAt (issue 294). Bug it catches (review of issue 458): a
// change of Date after such a refresh drew nothing either, so an open issue's age tooltip kept mm/dd/yyyy.
test('Rules: after a refresh that changes only readAt, a change of Date redraws an open issue\'s age tooltip', () => {
  const w = boot({ tab: 'rules' });
  const d = full(T0 - 40000);
  d.panels.rules.data.open.issues = [{ repo: 'sample', issue: 76, title: 'Split the PROD stack', priority: 'P1', labels: ['P1', 'area:infra'], created: '2026-11-01T00:00:00Z' }];
  d.panels.rules.data.readAt = new Date(T0 - 70000).toISOString();
  deliver(w, d);
  const again = clone(d);
  again.updatedAt = new Date(T0 - 20000).toISOString();
  again.panels.rules.data.readAt = new Date(T0 - 30000).toISOString();
  next(w, again);
  const tipOf = () => issuesP(w).querySelector('[data-issue="76"] .rules-age time').title;
  assert.equal(tipOf(), '10/31/2026, 8:00:00 PM');
  w.document.getElementById('customize-open').click();
  pick(w, 'date', 'dd/mm/yyyy');
  assert.equal(tipOf(), '31/10/2026, 8:00:00 PM');
});
