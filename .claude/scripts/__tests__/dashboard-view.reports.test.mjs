// SPDX-License-Identifier: Apache-2.0
// The report panels of Overview, as the Board user-experience audit asked (issue 413): on a phone Lanes, Cost and
// Metrics start as their headings (UX26), and Metrics' trends carry their numbers (UX41). Belt 3D's corner readouts
// (UX30) are in dashboard-view.belt3d.test.mjs. No test lays the page out in a browser.
// Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { STORE, iso, T0, P, OVERVIEW, CARD_METRICS, METRIC_TOTALS, boot, panel, saved, kept, deliver, full, later, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

// ---- UX26: on a phone, the report panels start as their headings ----
const REPORTS = ['lanes', 'cost', 'metrics'];
const folded = (w, id) => panel(w, id).querySelector('.panel-body').hidden;

// Bug it catches: on the phone, Overview was one column about 13,600 px tall, every panel open, so Needs you and the
// belt were followed by fifteen screens of reports. At 390 and 600 px (one column) Lanes, Cost and Metrics start
// collapsed, each still its heading with its control to open it; every other panel is open, and nothing is kept until
// the owner changes something.
test('on a phone, Lanes, Cost and Metrics start as their headings and every other Overview panel is open', () => {
  for (const width of [390, 600]) {
    const w = boot({ width });
    deliver(w, full());
    for (const id of REPORTS) {
      const fold = panel(w, id).querySelector('.tool.collapse');
      assert.equal(folded(w, id), true, `${id} starts collapsed at ${width} px`);
      assert.equal(panel(w, id).hidden, false, `${id} is still on the page at ${width} px`);
      assert.ok(panel(w, id).querySelector('h2.panel-title').textContent.length > 0, `${id} keeps its heading at ${width} px`);
      assert.equal(fold.getAttribute('aria-expanded'), 'false');
      assert.match(fold.getAttribute('aria-label'), /^Expand /);
    }
    for (const id of OVERVIEW.filter((x) => !REPORTS.includes(x))) assert.equal(folded(w, id), false, `${id} is open at ${width} px`);
    assert.equal(w.localStorage.getItem(STORE), null, 'a default, not a kept layout');
  }
});

// Bug it catches: the phone's default folding the reports on a laptop too, where there is room for them.
test('on a wider screen every Overview panel starts open', () => {
  for (const width of [701, 1000, 1440]) {
    const w = boot({ width });
    deliver(w, full());
    for (const id of OVERVIEW) assert.equal(folded(w, id), false, `${id} is open at ${width} px`);
  }
});

// Bug it catches: the default overriding the owner: a report opened on the phone folding again on the next visit.
test('on a phone, a report the owner opened stays open on the next visit', () => {
  const w = boot({ width: 390 });
  deliver(w, full());
  panel(w, 'metrics').querySelector('.tool.collapse').click();
  later(w);
  assert.equal(folded(w, 'metrics'), false);
  assert.deepEqual(kept(w).collapsed, ['lanes', 'cost']);
  const again = boot({ width: 390, store: { [STORE]: JSON.stringify(saved(w)) } });
  deliver(again, full());
  assert.deepEqual(REPORTS.map((id) => folded(again, id)), [true, true, false]);
});

// ---- UX41: Metrics' trends with their numbers ----
const tileOf = (w, k) => panel(w, 'metrics').querySelector(`[data-tile="${k}"]`);
const chartOf = (w, k) => panel(w, 'metrics').querySelector(`[data-chart="${k}"]`);
const deltas = (w) => ['landed', 'cycle', 'go', 'cost'].map((k) => tileOf(w, k).querySelector('.delta'));

// Bug it catches: on a Conveyor with no earlier week one tile said "▲ up 326 vs previous 7 days" (the whole week counted
// as a rise) while the other three said "—". The 7 days before ended no card: every tile says there is no earlier
// week, uncoloured. A previous week not read at all is still "—".
test('metrics: with no earlier week, every tile says "no earlier week to compare", never a rise of the whole week', () => {
  const w = boot();
  const data = full(), r = data.panels.metrics.data.records[0];
  r.week = { ...r.week, landed: 326, cards: 330 };
  r.prev = { ...METRIC_TOTALS, cards: 0, landed: 0, blocked: 0, cycleSec: { p50: null, p90: null }, firstReviewPass: null, perLanded: null };
  deliver(w, data);
  for (const d of deltas(w)) {
    assert.equal(d.textContent, 'no earlier week to compare');
    assert.ok(!d.classList.contains('good') && !d.classList.contains('bad'), 'neither better nor worse');
  }
  assert.doesNotMatch(panel(w, 'metrics').textContent, /up 326/);
  const unread = full();
  unread.panels.metrics.data.records[0].prev = null;
  const u = boot();
  deliver(u, unread);
  assert.deepEqual(deltas(u).map((d) => d.textContent), Array(4).fill('— vs previous 7 days'), 'a week not read is a dash');
});

// Bug it catches: the bar chart of landed and blocked per day had day names but no counts, and the cycle-time chart had
// only its two ends. Each day's bar carries its landed count and, when any, "+" its blocked count, over the bar; each
// cycle-time bar its number of cards.
test('metrics: each bar carries its count, over the bar', () => {
  const w = boot();
  const data = full();
  data.panels.metrics.data.cards.push(...[1200, 3000].map((c, i) => ({ repo: 'sample', card: `c9-${40 + i}`, issue: 40 + i, title: `Quick ${i}`, url: `${P}/${40 + i}`, state: 'landed', at: iso(T0 - 9000000 - i * 60000),
    metrics: { ...CARD_METRICS, cycleSec: c } })));
  deliver(w, data);
  const bars = Array.from(chartOf(w, 'days').querySelectorAll('g.bar'));
  // The days: 1 landed; none; 2 and 1 blocked; 1; 1; 1 blocked; 2 and 2 blocked.
  assert.deepEqual(bars.map((g) => g.querySelector('text.count').textContent), ['1', '0', '2 +1', '1', '1', '0 +1', '2 +2']);
  for (const g of bars) {
    const y = Number(g.querySelector('text.count').getAttribute('y')), tops = Array.from(g.querySelectorAll('rect:not(.hit)'), (r) => Number(r.getAttribute('y')));
    assert.ok(tops.every((t) => y < t) && y > 0, `the count sits over its bar, inside the chart: ${y} over ${tops}`);
  }
  assert.equal(bars[6].querySelector('text.count .fill-blocked').textContent, ' +2', 'the blocked count in the blocked colour');
  // The cycle times (20, 36 and 50 min): each drawn bar its count, and the counts are the bins' own.
  const cyc = Array.from(chartOf(w, 'cycle').querySelectorAll('g.bar')).filter((g) => g.querySelector('rect.fill-s1'));
  assert.deepEqual(cyc.map((g) => g.querySelector('text.count').textContent), ['1', '1', '1']);
  assert.deepEqual(cyc.map((g) => g.querySelector('title').textContent.replace(/^.*: (\d+) cards?$/, '$1')), ['1', '1', '1']);
});

// Bug it catches: a restarted card showed its last run's price only. Its metrics, as the snapshot gives them for a
// first run of $1.20 (retried) and a second of $0.80 (engine case metricsruns), show the issue's $2.00 and 3 reviews,
// its fixes and test runs over both runs, "2 runs" and the run's own $0.80 as "this run"; its cost row says it is 2 runs.
test('metrics: a restarted card shows the total of its runs, "2 runs" and "this run"', () => {
  const w = boot();
  const data = full();
  const own = { usd: 0.8, tokens: 400000, unpriced: 0, buildSec: 200, reviewSec: 400, fixSec: null, testSec: null, rebuildSec: null, landSec: null, runSec: 600, reviews: 1, fixes: 0, testRuns: 1 };
  data.panels.metrics.data.cards.unshift({ repo: 'sample', card: 'c10', issue: 9, title: 'Restarted', url: `${P}/9`, state: 'on the belt', at: iso(T0),
    metrics: { ...CARD_METRICS, usd: 2, reviews: 3, fixes: 1, testRuns: 2, buildSec: 500, runs: 2, runSec: 1860, thisRun: own } });
  data.panels.cost.data.cards.perCard.unshift({ repo: 'sample', card: 'c10', issue: 9, title: 'Restarted', url: `${P}/9`, state: 'on the belt', runs: 2, todayUsd: 2, weekUsd: 2 });
  deliver(w, data);
  const row = Array.from(panel(w, 'metrics').querySelectorAll('details.card-detail')).find((d) => d.querySelector('summary').textContent.includes('Restarted'));
  assert.ok(row, 'the restarted card has its row');
  assert.match(row.querySelector('summary').textContent, /\$2\.00/);
  const meta = row.querySelector('.row-meta').textContent;
  // The fixes and test runs of every run, not the run's own (0 fixes, 1 test run) alone.
  assert.match(meta, /^lead .*building 8 min.*3 reviews\s*1 fixes\s*2 test runs/);
  assert.match(meta, /2 runs, 31 min in all/);
  assert.match(meta, /this run: \$0\.80, 10 min, building 3 min, .* 1 reviews, 0 fixes, 1 test runs/);
  const cost = Array.from(panel(w, 'cost').querySelectorAll('li.row')).find((li) => li.textContent.includes('Restarted'));
  assert.ok(cost && /2 runs/.test(cost.textContent), 'the cost row says the card is 2 runs');
});

// Bug it catches: "Block reasons" ended in "other 24" and "the rest 29", two buckets that sound the same. The
// snapshot's own "other" and the reasons past the fourth are one "other", last; no "the rest" anywhere.
test('metrics: block reasons have one "other", never "the rest" beside it', () => {
  const legend = (blocks) => {
    const w = boot();
    const data = full();
    data.panels.metrics.data.records[0].week = { ...data.panels.metrics.data.records[0].week, blocked: 60, blocks };
    deliver(w, data);
    return Array.from(chartOf(w, 'blocks').querySelectorAll('.legend li'), (li) => li.textContent);
  };
  assert.deepEqual(legend({ timeout: 9, 'visible change': 7, tests: 5, review: 4, setup: 3, other: 24 }), ['timeout 9', 'visible change 7', 'tests 5', 'review 4', 'other 27']);
  assert.deepEqual(legend({ a: 9, b: 8, c: 7, d: 6, e: 5, f: 4, g: 3 }), ['a 9', 'b 8', 'c 7', 'd 6', 'other 12']);
  assert.deepEqual(legend({ other: 4, a: 3, b: 2 }), ['a 3', 'b 2', 'other 4'], 'a few reasons: each its own, "other" last');
  assert.deepEqual(legend({ a: 3, b: 2, c: 1, d: 1, e: 1 }), ['a 3', 'b 2', 'c 1', 'd 1', 'e 1'], 'five reasons: no bucket');
});

// Bug it catches: a test failure's verdict (the card's, main's or flaky: issue 456) was recorded and never shown, so the
// owner could not see how many fix rounds a red main or a flaky case would have cost. All numbers has its row, and a
// record from before the verdicts says "—".
test('metrics: All numbers counts the test failures by verdict, with the time spent running them on main', () => {
  const data = full(), r = data.panels.metrics.data.records[0];
  r.week = { ...r.week, testFailures: { card: 3, main: 2, flaky: 4, mainSec: 150 } };
  const w = boot();
  deliver(w, data);
  const row = Array.from(panel(w, 'metrics').querySelectorAll('details.metrics-all tr')).find((tr) => tr.querySelector('th').textContent === 'Test failures');
  assert.ok(row, 'All numbers has a Test failures row');
  const [today, week] = Array.from(row.querySelectorAll('td'), (td) => td.textContent);
  assert.equal(today, '—');
  assert.match(week, /^3 the card's \(to fix\), 2 failing on main too \(waited\), 4 flaky; .+ running them on main$/);
  assert.doesNotMatch(week, /—/);
});

// Bug it catches: "First-review GO 52%" used the reviewer's GO code (UX15). The tile, its sparkline and All numbers say
// "Passed first review".
test('metrics: the first-review figure is "Passed first review", not the GO code', () => {
  const w = boot();
  deliver(w, full());
  const go = tileOf(w, 'go');
  assert.equal(go.querySelector('.figure-label').textContent, 'Passed first review');
  assert.match(go.querySelector('svg.spark').getAttribute('aria-label'), /^Passed first review, last 7 days/);
  const table = panel(w, 'metrics').querySelector('details.metrics-all');
  assert.ok(Array.from(table.querySelectorAll('th'), (th) => th.textContent).includes('Passed first review'));
  for (const el of [panel(w, 'metrics').querySelector('.metric-tiles'), table]) assert.doesNotMatch(el.textContent, /\bGO\b/);
});
