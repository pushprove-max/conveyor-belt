// SPDX-License-Identifier: Apache-2.0
// The dashboard page's reporting panels on Overview: Metrics, Cost, Queue, Lanes and Health. Shared setup:
// dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { read, T0, iso, clone, boot, panel, state, deliver, next, key, P, CARD_METRICS, METRIC_TOTALS, METRIC_DAYS, full, EMPTY, act, moreText, settle, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

test('metrics: a card opens to its step timeline and stays open through a redraw; a reading not taken is "—", never 0', () => {
  const w = boot();
  const data = full();
  deliver(w, data);
  const card = (n) => Array.from(panel(w, 'metrics').querySelectorAll('details.card-detail')).find((d) => d.querySelector('.title').textContent === n);
  assert.equal(card('Landed one').open, false, 'a card starts closed');
  card('Landed one').querySelector('summary').click();
  assert.equal(card('Landed one').open, true, 'a click opens it');
  assert.deepEqual(Array.from(card('Landed one').querySelectorAll('.timeline li'), (li) => li.textContent.split(' · ')[0]), ['build', 'review: changes asked', 'test fail']);
  card('Landed one').dispatchEvent(new w.Event('toggle'));
  const again = clone(data); again.panels.metrics.data.cards[0].metrics.usd = 7;
  next(w, again);
  assert.equal(card('Landed one').open, true, 'the redraw keeps it open');
  assert.equal(card('Old record').open, false);
  const old = card('Old record').textContent;
  for (const s of ['lead —', 'cycle —', 'diff —', 'weekly limit —', 'depth —', 'findings —', 'no step finished yet']) assert.ok(old.includes(s), `"${s}" in: ${old}`);
  assert.ok(!/lead 0|diff 0|depth 0/.test(old), 'nothing missing reads as 0');
  // A host whose snapshot is from before the measurements: the panel says so and draws the rest.
  const bare = clone(data); bare.panels.metrics.data = { records: [{ repo: 'sample', today: null, week: null }], cards: null };
  next(w, bare);
  assert.equal(state(w, 'metrics'), 'ready');
  assert.match(panel(w, 'metrics').textContent, /gives no measurements yet.*The build machine did not give measurements per card/);
});

// The owner, on the live Board: Metrics as tiles, sparklines and charts, not two long tables.
const tileOf = (w, k) => panel(w, 'metrics').querySelector(`[data-tile="${k}"]`);
const chartOf = (w, k) => panel(w, 'metrics').querySelector(`[data-chart="${k}"]`);
test('metrics: headline tiles, each with its sparkline and its change on the 7 days before, coloured by whether it is better', () => {
  const w = boot();
  const data = full();
  // Two more landed cards, so the cycle times have a spread to draw.
  data.panels.metrics.data.cards.push(...[1200, 3000].map((c, i) => ({ repo: 'sample', card: `c9-${40 + i}`, issue: 40 + i, title: `Quick ${i}`, url: `${P}/${40 + i}`, state: 'landed', at: iso(T0 - 9000000 - i * 60000),
    metrics: { ...CARD_METRICS, cycleSec: c } })));
  deliver(w, data);
  assert.deepEqual(Array.from(panel(w, 'metrics').querySelectorAll('[data-tile]'), (t) => t.dataset.tile), ['landed', 'cycle', 'go', 'cost']);
  const num = (k) => tileOf(w, k).querySelector('.num').textContent, dl = (k) => tileOf(w, k).querySelector('.delta');
  assert.deepEqual(['landed', 'cycle', 'go', 'cost'].map(num), ['2 / 7', '28 min', '66.7%', '$4.50']);
  // Fewer landed than the 7 days before is worse; faster, more passed first review and cheaper are better.
  assert.deepEqual(['landed', 'cycle', 'go', 'cost'].map((k) => [dl(k).textContent, dl(k).classList.contains('good') ? 'good' : dl(k).classList.contains('bad') ? 'bad' : 'none']),
    [['▼ down 1 vs previous 7 days', 'bad'], ['▼ down 4 min vs previous 7 days', 'good'], ['▲ up 16.7 pts vs previous 7 days', 'good'], ['▼ down $0.50 vs previous 7 days', 'good']]);
  for (const k of ['landed', 'cycle', 'go', 'cost']) {
    const sp = tileOf(w, k).querySelector('svg.spark');
    assert.ok(sp && sp.querySelector('path.spark-line').getAttribute('d').startsWith('M'), `${k} has a sparkline`);
    assert.match(sp.getAttribute('aria-label'), /last 7 days: /, `${k}'s sparkline says its values`);
  }
  // A day with no value breaks the line: the cycle time has two days with none (two moves).
  assert.equal((tileOf(w, 'cycle').querySelector('path.spark-line').getAttribute('d').match(/M/g) || []).length, 3);
  assert.match(tileOf(w, 'cycle').textContent, /90th: 36 min/);
});

test('metrics: a cost with unpriced steps in either period shows no change, so a partial cost never reads as cheaper', () => {
  const w = boot();
  [[{ usd: 0, leftOut: 1 }, { usd: 5, leftOut: 0 }], [{ usd: 4.5, leftOut: 0 }, { usd: 5, leftOut: 2 }]].forEach(([week, prev], i) => {
    const data = full(), r = data.panels.metrics.data.records[0];
    r.week = { ...r.week, perLanded: { ...r.week.perLanded, ...week } };
    r.prev = { ...r.prev, perLanded: { ...r.prev.perLanded, ...prev } };
    (i ? next : deliver)(w, data);
    const dl = tileOf(w, 'cost').querySelector('.delta');
    assert.equal(dl.textContent, '— vs previous 7 days', `week ${JSON.stringify(week)}, previous ${JSON.stringify(prev)}`);
    assert.ok(!dl.classList.contains('good') && !dl.classList.contains('bad'));
  });
});

test('metrics: each chart draws from the totals, inline SVG and no library', () => {
  const w = boot();
  // No library: drawing the charts loads no file of code and leaves no new global behind (the page's own files and
  // the page's own reads, data.js and alive.js, are the only scripts).
  const globals = new Set(Object.keys(w));
  const data = full();
  data.panels.metrics.data.cards.push(...[1200, 3000].map((c, i) => ({ repo: 'sample', card: `c9-${40 + i}`, issue: 40 + i, title: `Quick ${i}`, url: `${P}/${40 + i}`, state: 'landed', at: iso(T0 - 9000000 - i * 60000),
    metrics: { ...CARD_METRICS, cycleSec: c } })));
  data.panels.metrics.data.records[0].week.perLanded.byModel['gpt-6.1-sol'] = { usd: 1.5, tokens: 750000 };
  deliver(w, data);
  assert.deepEqual(Array.from(panel(w, 'metrics').querySelectorAll('[data-chart]'), (c) => c.dataset.chart), ['days', 'blocks', 'cycle', 'models', 'slots']);
  // Landed and blocked per day: a column a day, stacked, with a legend; a day of neither draws no bar.
  const days = chartOf(w, 'days');
  assert.equal(days.querySelectorAll('g.bar').length, 7);
  assert.equal(days.querySelectorAll('rect.fill-landed').length, 5);
  assert.equal(days.querySelectorAll('rect.fill-blocked').length, 3);
  assert.deepEqual(Array.from(days.querySelectorAll('.tick:not(.count)'), (t) => t.textContent), ['Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun', 'Mon']);
  assert.deepEqual(Array.from(days.querySelectorAll('.legend li'), (li) => li.textContent), ['Landed', 'Blocked']);
  assert.equal(days.querySelectorAll('g.bar')[6].querySelector('title').textContent, '2026-11-09: 2 landed, 2 blocked');
  // Block reasons: one bar, a segment a reason, each named with its count in the legend.
  const blocks = chartOf(w, 'blocks');
  assert.equal(blocks.querySelectorAll('svg rect').length, 2);
  assert.deepEqual(Array.from(blocks.querySelectorAll('.legend li'), (li) => li.textContent), ['timeout 1', 'visible change 1']);
  // The cycle times of the landed cards (20, 36 and 50 min) in six bins: three bars, ends labelled.
  const cyc = chartOf(w, 'cycle');
  assert.equal(cyc.querySelectorAll('rect.fill-s1').length, 3);
  assert.deepEqual(Array.from(cyc.querySelectorAll('.tick:not(.count)'), (t) => t.textContent), ['20 min', '50 min']);
  // Cost per landed card by model, the costliest first, each with its dollars.
  const models = chartOf(w, 'models');
  assert.deepEqual(Array.from(models.querySelectorAll('g.bar'), (g) => Array.from(g.querySelectorAll('text'), (t) => t.textContent)), [['claude-sonnet-5-5', '$3.00'], ['gpt-6.1-sol', '$1.50']]);
  const bars = Array.from(models.querySelectorAll('rect'), (r) => Number(r.getAttribute('width')));
  assert.ok(bars[0] > bars[1], 'the dearer model has the longer bar');
  // Slots in use today: an area under a line through each hour's mean.
  const slots = chartOf(w, 'slots');
  assert.ok(slots.querySelector('path.area') && slots.querySelector('path.area-line'));
  assert.match(slots.querySelector('svg').getAttribute('aria-label'), /of 4: 0:00 3, 5:00 0\.5, 9:00 2/);
  // Every number stays one click away, closed until asked for, and stays open through a redraw.
  const all = panel(w, 'metrics').querySelector('details.metrics-all');
  assert.equal(all.open, false);
  assert.equal(all.querySelector('summary').textContent, 'All numbers');
  assert.ok(all.querySelector('table.metrics-table'));
  all.open = true; all.dispatchEvent(new w.Event('toggle'));
  // A snapshot that differs, so the panel is drawn again (an equal one leaves it untouched).
  const again = clone(data);
  again.panels.metrics.data.records[0].today.cards += 1;
  next(w, again);
  assert.notEqual(panel(w, 'metrics').querySelector('details.metrics-all'), all, 'the panel was drawn again');
  assert.equal(panel(w, 'metrics').querySelector('details.metrics-all').open, true);
  assert.deepEqual(Array.from(w.document.querySelectorAll('script'), (s) => s.getAttribute('src')).filter((s) => !/^(data|alive)\.js(\?|$)/.test(s)),
    ['app.js', 'head.js', 'panels/index.js', 'boot.js'], 'no script was added');
  // An element with an id (the setup's box, #onboard) is a named property of the window, not a global a script set:
  // a key is skipped only while its value is that element, so a library's global of the same name still fails.
  assert.deepEqual(Object.keys(w).filter((k) => !globals.has(k) && w[k] !== w.document.getElementById(k)), [], 'no new global');
});

test('metrics: a new Conveyor with 3 cards shows "—" and why, never "missing"', () => {
  const w = boot();
  const data = full();
  const none = { p50: null, p90: null };
  const fresh = { cards: 1, landed: 1, blocked: 0, leadSec: none, cycleSec: { p50: 1200, p90: 1200 }, firstReviewPass: null, findingsPerCard: null, followupRate: 0, blockRate: 0, blocks: {},
    rebuildRate: 0, perLanded: null, waitMaxSec: 0, limitPerCard: null, loop: null, pushes: { ok: 0, failed: 0, sec: none, failSec: none }, host: null };
  const empty = { ...fresh, cards: 0, landed: 0, cycleSec: none, followupRate: null, blockRate: null, rebuildRate: null };
  const bare = { ...CARD_METRICS, leadSec: null, cycleSec: null, reviews: 0, firstReview: null, findings: null, diff: null, depth: null, limit: { before: null, after: null, used: null }, usd: null, tokens: null, timeline: [] };
  data.panels.metrics.data = {
    records: [{ repo: 'example', today: fresh, week: fresh, prev: empty,
      days: METRIC_DAYS.map((x) => ({ day: x.day, landed: 0, blocked: 0, cycleSec: null, firstReviewPass: null, perLandedUsd: null })).map((x, i) => (i === 6 ? { ...x, landed: 1, cycleSec: 1200 } : x)),
      slots: [{ hour: 9, slots: 1, cap: 3 }] }],
    cards: [['landed', { ...bare, cycleSec: 1200 }], ['on the belt', bare], ['on the belt', bare]].map(([st, m], i) => ({ repo: 'example', card: `c1-${i + 1}`, issue: i + 1, title: `First ${i + 1}`,
      url: `${P}/${i + 1}`, state: st, at: iso(T0 - i * 60000), metrics: m })),
  };
  deliver(w, data);
  assert.equal(state(w, 'metrics'), 'ready');
  const text = panel(w, 'metrics').textContent;
  assert.doesNotMatch(text, /missing/i, 'never the word missing');
  for (const k of ['go', 'cost']) {
    assert.equal(tileOf(w, k).querySelector('.num').textContent, '—', `${k} has no value yet`);
    assert.match(tileOf(w, k).textContent, /not enough cards yet/);
    assert.equal(tileOf(w, k).querySelector('.delta').textContent, 'no earlier week to compare');
  }
  assert.equal(tileOf(w, 'landed').querySelector('.num').textContent, '1 / 1');
  for (const k of ['cycle', 'models', 'slots']) assert.match(chartOf(w, k).textContent, /—not enough (cards|samples) yet/, `${k} says why it has nothing to draw`);
  assert.match(chartOf(w, 'blocks').textContent, /No card blocked in the last 7 days/);
  assert.ok(Array.from(panel(w, 'metrics').querySelectorAll('.metrics-table td.unknown')).every((td) => td.textContent === '—'), 'every value not there is "—" in All numbers');
});

test('metrics: a tab a Conveyor, each with its own tiles, charts and cards', () => {
  const w = boot();
  const data = full();
  const other = { ...clone(data.panels.metrics.data.records[0]), repo: 'widgetshop', week: { ...METRIC_TOTALS, cards: 3, landed: 3, blocked: 0 } };
  data.panels.metrics.data.records.push(other);
  data.panels.metrics.data.cards.push({ repo: 'widgetshop', card: 'c1-5', issue: 5, title: 'Widget card', url: `${P}/5`, state: 'landed', at: iso(T0 - 600000), metrics: CARD_METRICS });
  deliver(w, data);
  const tabs = () => Array.from(panel(w, 'metrics').querySelectorAll('[role="tab"]'));
  const titles = () => Array.from(panel(w, 'metrics').querySelectorAll('.rows .title'), (t) => t.textContent);
  assert.deepEqual(tabs().map((t) => [t.textContent, t.getAttribute('aria-selected')]), [['sample', 'true'], ['widgetshop', 'false']]);
  assert.equal(panel(w, 'metrics').querySelectorAll('[data-tile="landed"]').length, 1, 'one Conveyor at a time, not stacked');
  assert.equal(tileOf(w, 'landed').querySelector('.num').textContent, '2 / 7');
  assert.ok(!titles().includes('Widget card'));
  tabs()[1].focus();
  tabs()[1].click();
  assert.deepEqual(tabs().map((t) => t.getAttribute('aria-selected')), ['false', 'true']);
  assert.equal(w.document.activeElement, tabs()[1], 'the keyboard focus stays on the tab picked');
  assert.deepEqual(tabs().map((t) => t.tabIndex), [-1, 0], 'only the tab picked is in the Tab order');
  key(w, tabs()[1], 'ArrowRight');
  assert.deepEqual(tabs().map((t) => t.getAttribute('aria-selected')), ['true', 'false'], 'ArrowRight past the last tab wraps to the first');
  assert.equal(w.document.activeElement, tabs()[0], 'the focus follows the arrow');
  key(w, tabs()[0], 'ArrowLeft');
  assert.deepEqual(tabs().map((t) => t.getAttribute('aria-selected')), ['false', 'true'], 'ArrowLeft before the first tab wraps to the last');
  key(w, tabs()[1], 'Home');
  assert.equal(w.document.activeElement, tabs()[0], 'Home picks the first tab');
  key(w, tabs()[0], 'End');
  assert.equal(w.document.activeElement, tabs()[1], 'End picks the last tab');
  assert.deepEqual(tabs().map((t) => t.getAttribute('aria-selected')), ['false', 'true']);
  assert.equal(tileOf(w, 'landed').querySelector('.num').textContent, '2 / 3');
  assert.deepEqual(titles(), ['Widget card']);
  // A snapshot that differs, so the panel is drawn again (an equal one leaves it untouched).
  const again = clone(data);
  again.panels.metrics.data.cards.find((c) => c.repo === 'widgetshop').title = 'Widget card, renamed';
  const tile = tileOf(w, 'landed');
  next(w, again);
  assert.notEqual(tileOf(w, 'landed'), tile, 'the panel was drawn again');
  assert.equal(tileOf(w, 'landed').querySelector('.num').textContent, '2 / 3', 'the tab picked stays through a redraw');
  assert.deepEqual(titles(), ['Widget card, renamed']);
});

test('metrics: each Conveyor tab pages its own cards, starting at five', () => {
  const w = boot();
  const data = full();
  const m = data.panels.metrics.data;
  m.records.push({ ...clone(m.records[0]), repo: 'widgetshop' });
  m.cards = ['sample', 'widgetshop'].flatMap((repo, r) => Array.from({ length: 12 }, (_, i) => ({ repo, card: `c${r}-${i}`, issue: 100 * (r + 1) + i,
    title: `${repo} ${i}`, url: `${P}/${100 * (r + 1) + i}`, state: 'landed', at: iso(T0 - (i + 1) * 60000), metrics: CARD_METRICS })));
  deliver(w, data);
  const tabs = () => Array.from(panel(w, 'metrics').querySelectorAll('[role="tab"]'));
  const rows = () => panel(w, 'metrics').querySelectorAll('.rows > .row');
  assert.equal(rows().length, 5);
  act(panel(w, 'metrics'), 'list-all').click();
  assert.equal(rows().length, 12);
  tabs()[1].click();
  assert.equal(rows().length, 5, 'the other Conveyor opens at five');
  assert.deepEqual(moreText(panel(w, 'metrics')), ['Show 5 more', 'Show all (12)']);
  tabs()[0].click();
  assert.equal(rows().length, 12, 'the first keeps its own choice');
});

test('cost: the figures are the priced steps, and the steps left out are counted and named with why; a step says why it has no price', () => {
  const w = boot();
  const data = full();
  Object.assign(data.panels.cost.data.cards, { unpricedSteps: 2, todayLeftOut: 1, weekLeftOut: 2, perLandedLeftOut: 0, unpriced: [
    { repo: 'sample', card: 'c1-7', issue: 7, url: `${P}/7`, step: 'build', time: '2026-11-09T01:10:00Z', why: 'no model recorded' },
    { repo: 'sample', card: 'c1-8', issue: 8, url: `${P}/8`, step: 'fix', time: '2026-11-08T02:00:00Z', why: 'its token usage could not be read: the session output holds no token usage' }] });
  const m = data.panels.metrics.data.cards[0].metrics;
  Object.assign(m, { usd: null, unpriced: 1 });
  Object.assign(m.timeline[0], { usd: null, unpriced: 'no model recorded' });
  deliver(w, data);
  const cost = panel(w, 'cost').textContent;
  assert.ok(cost.includes('$4.25') && cost.includes('$14.00'), 'the priced figures are shown, not hidden');
  assert.match(cost, /2 steps have no price, and the figures above do not include them \(1 today, 2 in 7 days\)/);
  assert.ok(cost.includes('no model recorded') && cost.includes('its token usage could not be read'), cost);
  const card = Array.from(panel(w, 'metrics').querySelectorAll('details.card-detail')).find((d) => d.querySelector('.title').textContent === 'Landed one');
  assert.ok(card.textContent.includes('1 step not priced'), card.textContent);
  assert.equal(card.querySelector('.timeline li').textContent.split(' · ')[3], 'not priced: no model recorded');
});

// Bug: a step priced from the owner's override (the pack's prices) read as the built-in list price.
test('metrics: a step priced from an override says so on its cost line', () => {
  const w = boot();
  const data = full();
  Object.assign(data.panels.metrics.data.cards[0].metrics.timeline[0], { usd: 3, override: true });
  deliver(w, data);
  const card = Array.from(panel(w, 'metrics').querySelectorAll('details.card-detail')).find((d) => d.querySelector('.title').textContent === 'Landed one');
  const lines = Array.from(card.querySelectorAll('.timeline li'), (li) => li.textContent.split(' · ')[3]);
  assert.equal(lines[0], '$3.00 (priced from your override)');
  assert.ok(lines.slice(1).every((x) => !x.includes('override')), lines.join(' | '));
});

test('the queue lists the issues built and waiting for a PROD deploy on their own, and says nothing of them when there are none', () => {
  const w = boot();
  const data = full();
  deliver(w, data);
  const lists = () => Array.from(panel(w, 'queue').querySelectorAll('.rows')).map((l) => Array.from(l.children, (li) => li.querySelector('.title').textContent));
  assert.deepEqual(lists(), [['Next up', 'Later'], ['Stack split', 'No label time']], 'they are a list apart from the queue');
  assert.equal(panel(w, 'queue').querySelector('.panel-count').textContent.trim(), '2', 'the count is the queue alone');
  assert.ok(!panel(w, 'queue').textContent.includes('time not read'), 'an issue whose label time GitHub did not give shows no time');
  const none = clone(data); none.panels.queue.data.awaitingDeploy = [];
  next(w, none);
  assert.deepEqual(lists(), [['Next up', 'Later']]);
  assert.ok(!panel(w, 'queue').textContent.includes('PROD deploy'), 'an empty list draws nothing');
  const old = clone(data); delete old.panels.queue.data.awaitingDeploy;
  next(w, old);
  assert.ok(!panel(w, 'queue').textContent.includes('PROD deploy'), 'a part without the list draws nothing');
  const only = clone(data); only.panels.queue.data.next = [];
  next(w, only);
  assert.equal(state(w, 'queue'), 'ready', 'an empty queue with issues waiting for a deploy is not the empty panel');
  assert.match(panel(w, 'queue').textContent, /Nothing queued\. Holds keep 2 issues back: see Held\..*Built, waiting for your PROD deploy \(2\):.*Stack split/s);
});

// An issue that depends on one still open is shown as "Waits on #N" in the queue and on the Board, after
// the issues pick takes and never numbered or moved among them; a dependency cycle is a problem in Health.
test('an issue waiting on another is "Waits on #N" in the queue and on the Board, and a cycle is a Health problem', () => {
  const w = boot();
  const data = full();
  const wait = { repo: 'sample', card: null, issue: 24, title: 'Second half', url: `${P}/24`, priority: 'P1', followup: false, retried: false, waitsFor: [20, 22] };
  data.panels.queue.data.waiting = [wait];
  data.panels.board.data.waits = [wait];
  data.panels.health.data.records[0].cycles = [[40, 41]];
  deliver(w, data);
  const rows = Array.from(panel(w, 'queue').querySelectorAll('.rows')).map((l) => Array.from(l.children, (li) => li.textContent));
  assert.equal(rows.length, 3, 'next, waiting and the PROD deploys are three lists');
  assert.match(rows[1][0], /Second half.*Waiting on #20, #22/);
  assert.equal(panel(w, 'queue').querySelector('.panel-count').textContent.trim(), '3', 'the count is the queue pick takes and the issue waiting on another');
  assert.match(panel(w, 'health').textContent, /Dependency cycles.*1 cycle.*#40 ↔ #41/s);
  const c = boot({ tab: 'control' });
  deliver(c, data);
  const cards = Array.from(panel(c, 'board').querySelectorAll('[data-col="queue"] .bcard'));
  assert.deepEqual(cards.map((x) => x.dataset.issue), ['20', '21', '22', '24'], 'after the pick order (the rule-skipped are in Held)');
  const waiting = cards[3];
  assert.match(waiting.textContent, /Waiting on #20, #22/);
  assert.ok(!waiting.textContent.includes('next:'), 'not numbered in the pick order');
  assert.ok(!waiting.querySelector('[data-act="up"], [data-act="down"]') && !/Move up/.test(waiting.textContent), 'it cannot be moved in the order');
  const none = clone(data); delete none.panels.queue.data.waiting; delete none.panels.board.data.waits;
  next(w, none); next(c, none);
  assert.ok(!panel(w, 'queue').textContent.includes('Waiting on') && !/Waiting on #\d/.test(panel(c, 'board').textContent), 'a part without the list draws none');
});

// A card the machine holds back (its cap or its pause) says so on its Board row, with the count, so the owner sees
// why the next card has not started; a row the machine does not hold says nothing of it.
test('a card the machine holds back says why on its Board row', () => {
  const data = full();
  const why = 'waiting for a machine slot: 2 of the machine cap 2 in use';
  data.panels.board.data.queue[0].room = why;
  const c = boot({ tab: 'control' });
  deliver(c, data);
  const cards = Array.from(panel(c, 'board').querySelectorAll('[data-col="queue"] .bcard'));
  assert.ok(cards[0].textContent.includes(why), `the held-back row says why: ${cards[0].textContent}`);
  assert.ok(cards.slice(1).every((x) => !x.textContent.includes('machine slot')), 'no other row says it');
});

test('a part read only in part says which piece is missing, and is never shown as empty', () => {
  const w = boot();
  const data = full();
  Object.assign(data.panels.needs.data, { cards: null, cardsError: 'buildhost did not answer', decisions: [] });
  Object.assign(data.panels.queue.data, { next: null, held: null, awaitingDeploy: null, issuesError: 'GitHub did not list the open issues on buildhost.' });
  Object.assign(data.panels.cost.data, { cards: null, cardsError: 'buildhost did not answer', sessions: null, sessionsError: 'no reading' });
  Object.assign(data.panels.health.data, { host: { name: 'buildhost', reachable: false, error: 'buildhost did not answer' }, records: null, limit: null, limitError: 'no login token', limits: null });
  data.panels.lanes.data.records[0].fast.landing = null;
  data.panels.lanes.data.cardsError = 'buildhost did not answer';
  deliver(w, data);
  for (const id of ['needs', 'queue', 'cost', 'health', 'lanes']) assert.equal(state(w, id), 'ready', `${id} is neither empty nor failed`);
  // Issue 415 (UX5): each says what is not seen and what to try; the reader's own reason is on tap, never in the text.
  const retry = 'Make sure that the build machine is on. Then press Restart the Board\'s feed in this panel.';
  const note = (id, re) => Array.from(panel(w, id).querySelectorAll('[data-tip]')).find((el) => re.test(el.textContent));
  assert.equal(note('needs', /could not read the cards/).textContent, `The Board could not read the cards, so it shows none. ${retry}`);
  assert.equal(note('needs', /could not read the cards/).dataset.tip, 'Details: buildhost did not answer');
  assert.match(panel(w, 'queue').textContent, /GitHub did not list the open issues/);
  assert.equal(note('cost', /card costs/).textContent, `The Board could not read the card costs, so it shows none. ${retry}`);
  assert.equal(note('cost', /every session/).dataset.tip, 'Details: no reading');
  assert.match(panel(w, 'health').textContent, /Unreachable.*buildhost did not answer.*Usage limit.*Not read.*no reading/);
  assert.match(panel(w, 'lanes').textContent, /Landing not read.*The Board could not read the cards\. Make sure that the build machine is on/);
  assert.equal(note('lanes', /could not read the cards/).dataset.tip, 'Details: buildhost did not answer');
  for (const id of ['needs', 'cost', 'lanes']) assert.doesNotMatch(panel(w, id).textContent, /did not answer|no reading/, `${id} keeps the raw reason off the page`);
  // A host that gave totals but no per-card rows: the panel says so and is never shown as empty.
  const bare = full();
  Object.assign(bare.panels.cost.data.cards, { todayUsd: 0, weekUsd: 0, perCard: null });
  bare.panels.cost.data.sessions = { todayUsd: 0, todayComplete: true, weekUsd: 0 };
  next(w, bare);
  assert.equal(state(w, 'cost'), 'ready');
  assert.match(panel(w, 'cost').textContent, /The build machine did not give costs per card\./);
  assert.ok(!panel(w, 'cost').textContent.includes('Per card, last 7 days'));
  // No card cost on record and a session reading that failed: the failure is said, not "No spend".
  const unread = full();
  unread.panels.cost.data = Object.assign(clone(EMPTY.cost), { sessions: null, sessionsError: 'no reading' });
  next(w, unread);
  assert.equal(state(w, 'cost'), 'ready');
  assert.match(panel(w, 'cost').textContent, /The Board could not read the cost of every session on this machine\. It reads it again in about a minute\./);
  assert.ok(!panel(w, 'cost').textContent.includes('No spend'));
});

// The owner's Board said "The lanes could not be read" for lanes it had no folder for. A project with no lane in the
// host file is no failure: its row says so and names the command that makes one, beside the other projects' lanes.
test('lanes are shown per project: a project with no lanes says "No lanes set up" and the command that makes one, not an error', () => {
  const w = boot();
  const data = full();
  data.panels.lanes.data.records.push({ repo: 'widgetshop', fast: null, research: null });
  deliver(w, data);
  assert.equal(state(w, 'lanes'), 'ready', 'neither failed nor empty');
  const rows = Array.from(panel(w, 'lanes').querySelectorAll('li.row'), (li) => [li.dataset.repo, li.dataset.lane || null]);
  assert.deepEqual(rows, [['sample', 'Fast lane'], ['sample', 'Research lane'], ['widgetshop', null]]);
  const text = panel(w, 'lanes').textContent;
  assert.match(text, /Fast lane \(sample\).*Research lane \(sample\)/, 'with two projects, each lane names its project');
  assert.match(panel(w, 'lanes').querySelector('li[data-repo="widgetshop"]').textContent, /Lanes \(widgetshop\).*No lanes set up.*conveyor\.sh lane fast create/);
  assert.ok(!text.includes('could not read'), text);
  // A project that names one lane shows that lane alone; a named folder that is not there says so.
  data.panels.lanes.data.records[1] = { repo: 'widgetshop', fast: null, research: { present: false } };
  next(w, data);
  assert.match(panel(w, 'lanes').querySelector('li[data-repo="widgetshop"]').textContent, /Research lane \(widgetshop\).*No worktree/);
  assert.equal(panel(w, 'lanes').querySelectorAll('li[data-repo="widgetshop"]').length, 1);
});

// The owner saw "No open change" on a lane a session was working in: the tile says the first thing that is true.
test('a lane says what is happening in it: working, uncommitted files, commits ahead, else idle', () => {
  const w = boot();
  const lanes = (fast, research) => {
    const data = full();
    Object.assign(data.panels.lanes.data.records[0].fast, { ahead: 0, subject: null, dirty: 0, run: null, landing: { state: 'none' } }, fast);
    Object.assign(data.panels.lanes.data.records[0].research, { ahead: 0, subject: null, dirty: 0, run: null }, research);
    next(w, data);
    const tile = (name) => panel(w, 'lanes').querySelector(`[data-lane="${name}"]`).textContent;
    return [tile('Fast lane'), tile('Research lane')];
  };
  const working = { startedAt: iso(T0 - 3600000), lastAt: iso(T0 - 180000), active: true, topic: 'Fix the login copy' };
  const ended = { startedAt: iso(T0 - 3600000), lastAt: iso(T0 - 660000), active: false, topic: 'Fix the login copy' };
  // A session working before its first save: no commit, no changed file.
  for (const t of lanes({ run: working }, { run: working })) {
    assert.match(t, /Working: Fix the login copy, last activity 3 min ago/);
    assert.ok(!/Idle|No open change/.test(t), t);
  }
  // Working comes first, whatever else is true.
  assert.match(lanes({ run: working, dirty: 2, ahead: 1, subject: 'Lane commit' })[0], /Working: Fix the login copy/);
  const [fd, rd] = lanes({ dirty: 3, ahead: 1, subject: 'Lane commit' }, { dirty: 1 });
  assert.match(fd, /3 files changed, not committed/);
  assert.match(rd, /1 file changed, not committed/);
  const [fa, ra] = lanes({ ahead: 2, subject: 'Second lane commit' }, { ahead: 1, subject: 'Notes on OCR' });
  assert.match(fa, /2 commits ahead of main: Second lane commit/);
  assert.match(ra, /1 commit ahead of main: Notes on OCR/);
  for (const t of lanes({}, {})) assert.match(t, /Idle/);
  // A session that ended over 10 minutes ago (the collector reads it as not active) is not working.
  for (const t of lanes({ run: ended }, { run: ended })) {
    assert.ok(!t.includes('Working'), t);
    assert.match(t, /Idle.*last session.*11 min ago/);
  }
});

test('health says what is wrong in words: a stopped loop, a failing push, stuck cards', () => {
  const w = boot();
  const data = full();
  Object.assign(data.panels.health.data.records[0], { loop: false, pushFailingSince: iso(T0 - 600000), pushError: { reason: 'pre-push hook refused' }, stuck: [{ card: 'c1', issue: 44, step: 'build', since: iso(T0 - 3000000) }], gh: false });
  data.panels.health.data.limits[0].pct = 95;
  deliver(w, data);
  const text = panel(w, 'health').textContent;
  for (const s of ['Stopped', 'Failing', 'pre-push hook refused', '1 stuck', '#44 in build', 'Not signed in', 'Nearly used up']) assert.ok(text.includes(s), `health shows "${s}": ${text}`);
  for (const chip of panel(w, 'health').querySelectorAll('.chip')) assert.ok(chip.querySelector('svg') && chip.textContent.trim(), 'every status is a word with an icon, never colour alone');
  // A card stuck waiting on a same-file card names that card's issue and where it is, never the review it waits to begin.
  const wt = clone(data);
  wt.panels.health.data.records[0].stuck = [{ card: 'c2-56', issue: 56, step: 'waiting', since: iso(T0 - 3000000), waitsOn: { card: 'c1-55', issue: 55, state: 'queued' } }];
  const ww = boot();
  deliver(ww, wt);
  const wtext = panel(ww, 'health').textContent;
  assert.ok(wtext.includes('#56 waiting on #55 (queued)') && !wtext.includes('#56 in'), `health names the card a stuck waiter waits on: ${wtext}`);
  // A loop its control record stops is not meant to run: it is off, not a fault.
  const off = clone(data);
  Object.assign(off.panels.health.data.records[0], { loop: false, state: 'stopped' });
  next(w, off);
  const loop = panel(w, 'health').querySelector('dt[data-check="Conveyor"]').nextElementSibling;
  assert.match(loop.textContent, /Off.*not meant to run/);
  assert.ok(loop.querySelector('.chip-quiet') && !loop.querySelector('.chip-bad'), 'shown as off, never as a fault');
  const meant = clone(data);
  Object.assign(meant.panels.health.data.records[0], { loop: false, state: 'running' });
  next(w, meant);
  assert.ok(panel(w, 'health').querySelector('dt[data-check="Conveyor"]').nextElementSibling.querySelector('.chip-bad'), 'a loop meant to run with no process is a fault');
});

test('health says the dashboard restarted on new code, and why a checkout was not brought forward', () => {
  const w = boot();
  const data = full();
  data.panels.health.data.update = { checkedAt: iso(T0), head: 'bbbbbbbbbbbb', error: null, moved: { from: 'aaaaaaaaaaaa', to: 'bbbbbbbbbbbb', at: iso(T0 - 60000), restart: true } };
  deliver(w, data);
  const row = () => panel(w, 'health').querySelector('dt[data-check="Dashboard code"]').nextElementSibling;
  assert.match(row().textContent, /Up to date.*main at bbbbbbbbbbbb.*restarted on new code aaaaaaaaaaaa\.\.bbbbbbbbbbbb/s);
  data.panels.health.data.update = { ...data.panels.health.data.update, error: 'main has 1 commit(s) that origin/main does not; it is left as it is' };
  next(w, data);
  assert.match(row().textContent, /Not updated.*main has 1 commit\(s\) that origin\/main does not/s);
  assert.ok(row().querySelector('.chip-warn'), 'a checkout left behind is a warning');
  data.panels.health.data.update = { ...data.panels.health.data.update, error: 'the checkout moved to new code, but the restart failed; the dashboard still runs the old code', moved: { ...data.panels.health.data.update.moved, restartFailed: true } };
  next(w, data);
  assert.match(row().textContent, /restart failed; the dashboard still runs the old code.*brought forward, restart failed aaaaaaaaaaaa\.\.bbbbbbbbbbbb/s);
  assert.ok(!row().textContent.includes('restarted on new code'), 'a failed restart is never shown as restarted');
  data.panels.health.data.update = null;
  next(w, data);
  assert.ok(!panel(w, 'health').textContent.includes('Dashboard code'), 'no row before the first update check');
});

test('health shows the Codex limit when the Claude reading failed', () => {
  const w = boot();
  const data = full();
  Object.assign(data.panels.health.data, { limit: { usedPct: null, fiveHour: null, codex: { usedPct: 93 }, reading: 'missing' }, limits: [] });
  deliver(w, data);
  assert.match(panel(w, 'health').textContent, /Usage limit.*Not read.*no reading.*Codex limit.*93% used/);
  data.panels.health.data.limit.codex = null;
  next(w, data);
  assert.ok(!panel(w, 'health').textContent.includes('Codex limit'), 'no Codex line without a Codex reading');
});

// The owner, 2026-11-13: a case that fails at random held cards up and nothing showed which. Health's "Flaky tests" line
// names each case that passed only on re-run in the 7 days, with its count and the issue filed for it, linked.
test('health draws a Flaky tests line: each case with its count and its issue number when one is filed', () => {
  const w = boot();
  const data = full();
  data.panels.health.data.records[0].flaky = [{ case: 'b.test: flaky', count: 3, issue: 16, url: `${P}/16` }, { case: 'c.test: other', count: 1, issue: null, url: null }];
  deliver(w, data);
  const dt = panel(w, 'health').querySelector('dt[data-check="Flaky tests"]');
  assert.ok(dt, 'a Flaky tests line');
  const dd = dt.nextElementSibling;
  assert.match(dd.textContent, /2 cases.*b\.test: flaky3 re-runs#16c\.test: other1 re-run$/s);
  const a = dd.querySelector('a.issue');
  assert.equal(a && a.getAttribute('href'), `${P}/16`, 'the issue filed links to it');
  assert.equal(dd.querySelectorAll('.issue').length, 1, 'a case with no issue filed shows none');
  // No case in the 7 days: the line says so; a snapshot from before the record draws none.
  data.panels.health.data.records[0].flaky = [];
  next(w, data);
  assert.match(panel(w, 'health').querySelector('dt[data-check="Flaky tests"]').nextElementSibling.textContent, /None.*no case passed only on re-run/);
  data.panels.health.data.records[0].flaky = null;
  next(w, data);
  assert.equal(panel(w, 'health').querySelector('dt[data-check="Flaky tests"]'), null);
});

// A machine that pays by API has dollars against a weekly cap, and the panel drew only the percent reading.
test('health shows the weekly spending cap and spend of a machine that pays by API', () => {
  const w = boot({ reducedMotion: true }); // a changed figure is its new value at once, not a count on the way to it
  const data = full();
  const api = { limitUsd: 1000, spentUsd: 412.5, goalUsd: 430, underUsd: 17.5, paceSec: 1, timeLeftSec: 259200, complete: true };
  // No subscription reading at all: the spend is the whole limit line, and nothing says "Not read".
  data.panels.health.data.limit = { usedPct: null, billing: 'api', api, reading: 'missing' };
  data.panels.health.data.limits[0].pct = null;
  deliver(w, data);
  let text = panel(w, 'health').textContent;
  for (const s of ['Weekly spend', 'Under pace', '$412.50 of the $1,000.00 weekly cap spent', 'resets in 3 d 0 h']) assert.ok(text.includes(s), `health shows "${s}": ${text}`);
  assert.ok(!text.includes('Not read') && !text.includes('7-day limit'), `no subscription line without a subscription reading: ${text}`);
  assert.equal(panel(w, 'health').querySelector('.meter').getAttribute('aria-label'), '41 percent of the weekly spending cap spent');
  // Each state of the spend, in words; a subscription reading beside it still shows.
  const says = (over, want, not = []) => {
    const d = full();
    Object.assign(d.panels.health.data.limit, { billing: 'api', api: { ...api, ...over } });
    next(w, d);
    text = panel(w, 'health').textContent;
    for (const s of [...want, '44% of the 7-day limit used']) assert.ok(text.includes(s), `health shows "${s}": ${text}`);
    for (const s of not) assert.ok(!text.includes(s), `health does not show "${s}": ${text}`);
  };
  says({ underUsd: -20 }, ['Over pace']);
  says({ spentUsd: 950 }, ['Nearly used up', '$950.00 of the $1,000.00 weekly cap spent']);
  says({ spentUsd: 1200 }, ['Over the cap']);
  says({ complete: false }, ['the Board did not read and price every request']);
  says({ limitUsd: null, goalUsd: null, underUsd: null }, ['No cap set', '$412.50 spent this week'], ['weekly cap spent']);
  says({ spentUsd: null }, ['Weekly spend', 'Not read', 'the weekly cap is $1,000.00, but the Board could not price the spend this week'], ['not priced']);
  // A subscription machine carries billing "subscription" and api null: no spend line.
  const sub = full();
  Object.assign(sub.panels.health.data.limit, { billing: 'subscription', api: null });
  next(w, sub);
  assert.ok(!panel(w, 'health').textContent.includes('Weekly spend'));
});

// Every Claude account, each with its own figures and what it is used for.
test('Health: each Claude account shows with its own usage and use', () => {
  const w = boot({});
  const d = full();
  d.panels.health.data.accounts = { error: null, list: [
    { machine: null, name: 'default', email: 'noreply-a@example.com', usedPct: 30, fiveHourPct: 5, usedFor: ["this machine's Foreman"], error: null },
    { machine: 'devbox', name: 'second', email: 'noreply-b@example.com', usedPct: 95, fiveHourPct: null, usedFor: ['cards of widgetshop: build and fix'], error: null },
    { machine: 'devbox', name: 'spare', email: null, usedPct: null, fiveHourPct: null, usedFor: ['not used by the Conveyor'], error: 'no login token' }] };
  deliver(w, d);
  const row = (label) => { const dt = panel(w, 'health').querySelector(`dt[data-check="${label}"]`); return dt ? dt.nextElementSibling.textContent : null; };
  assert.match(row('Account default on this machine'), /30% used.*noreply-a@example\.com.*5-hour window 5%.*this machine's Foreman/);
  assert.match(row('Account second on devbox'), /95% used.*noreply-b@example\.com.*cards of widgetshop: build and fix/);
  assert.match(row('Account spare on devbox'), /Not read.*not used by the Conveyor.*no login token/);
});

// Declined: the panel shows the lines not dismissed, not built and at most 7 days old (the collector's lines; the rest
// are the others). Bugs: Dismiss leaves the line on the panel or its count as it was, or names another line or
// project to the host; "Dismiss all shown" leaves a line shown, or sends one project's ids as another's; a line over 7
// days old is shown; "Show every line" loses a dismissed, filed or old line, or does not say which it is.
test('Declined: Dismiss and Dismiss all shown take lines off the panel and its count; Show every line shows them all, marked', async () => {
  const w = boot();
  const data = full(), d = data.panels.declined.data;
  d.lines.unshift({ repo: 'widgetshop', id: 'd00000000000c', time: iso(T0 - 60000), card: 'c4-5', issue: 5, url: null, finding: '[P2] c.txt:3 a nit', by: 'owner', why: 'not worth a card', built: null, dismissed: null });
  d.lines.push({ repo: 'sample', id: 'd00000000000d', time: iso(T0 - 3 * 86400000), card: 'c2-4', issue: 4, url: `${P}/4`, finding: '[P3] d.txt:4 a word', by: 'judge', why: 'taste', built: null, dismissed: null });
  d.rest.push({ repo: 'sample', id: 'd00000000000f', time: iso(T0 - 86400000), card: 'c2-4', issue: 4, url: `${P}/4`, finding: '[P1] f.txt:6 put aside', by: 'judge', why: 'out of scope', built: null, dismissed: { time: iso(T0 - 3600000), by: 'Board user owner' } },
    { repo: 'sample', id: 'd00000000000e', time: iso(T0 - 8 * 86400000), card: 'c1-2', issue: 2, url: `${P}/2`, finding: '[P2] e.txt:5 an old nit', by: 'judge', why: 'no proof', built: null, dismissed: null });
  deliver(w, data);
  const titles = () => Array.from(panel(w, 'declined').querySelectorAll('.rows > .row .title'), (n) => n.textContent);
  const count = () => w.document.querySelector('#panel-declined .panel-count').textContent;
  const row = (t) => Array.from(panel(w, 'declined').querySelectorAll('.rows > .row')).find((r) => r.querySelector('.title').textContent === t);
  const button = (a) => panel(w, 'declined').querySelector(`button[data-act="${a}"]`);
  assert.deepEqual(titles(), ['[P2] c.txt:3 a nit', '[P1] b.txt:2 no mark here', '[P3] d.txt:4 a word'], 'not the dismissed, the filed nor the 8-day-old line');
  assert.equal(count(), '3');
  // Dismiss: that line alone, by its id and project, on a second click (issue 407: it cannot be undone, and acted on
  // the first).
  const one = row('[P1] b.txt:2 no mark here').querySelector('button[data-act="dismiss"]');
  assert.equal(one.dataset.guard, 'final');
  one.click();
  await settle();
  assert.deepEqual(w.posts, [], 'the first click sends nothing');
  assert.equal(one.textContent, 'Click again: dismiss it for good');
  one.click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'dismiss', args: ['d0123456789ab'], repo: 'sample' } }]);
  assert.deepEqual(titles(), ['[P2] c.txt:3 a nit', '[P3] d.txt:4 a word']);
  assert.equal(count(), '2', 'the count drops at once');
  // Dismiss all shown, in the heading with its count: the first click only asks, in words that say it is for good
  // (issue 407: it cannot be undone); the second sends every line shown, one request a project.
  assert.ok(button('dismiss-all').closest('.panel-head'), 'in the panel heading');
  assert.equal(button('dismiss-all').textContent, 'Dismiss all shown (2)');
  button('dismiss-all').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [], 'the first click sends nothing');
  assert.equal(button('dismiss-all').textContent, 'Click again to dismiss the 2 lines for good');
  button('dismiss-all').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'dismiss', args: ['d00000000000c'], repo: 'widgetshop' } },
    { url: 'control', body: { action: 'dismiss', args: ['d00000000000d'], repo: 'sample' } }]);
  assert.deepEqual(titles(), []);
  assert.equal(count(), '0');
  assert.match(panel(w, 'declined').textContent, /Nothing to look at/);
  assert.equal(button('dismiss-all'), null, 'nothing left to dismiss');
  // Show every line: the rest too, newest first, each marked; a line not filed keeps "File as issue".
  button('declined-all').click();
  button('list-all').click();
  assert.deepEqual(titles(), ['[P2] c.txt:3 a nit', '[P1] b.txt:2 no mark here', '[P2] a.txt:1 wrong word', '[P1] f.txt:6 put aside', '[P3] d.txt:4 a word', '[P2] e.txt:5 an old nit']);
  assert.match(row('[P1] b.txt:2 no mark here').textContent, /Dismissed by you/);
  assert.match(row('[P1] f.txt:6 put aside').textContent, /Dismissed by Board user owner.*ago/);
  assert.equal(row('[P1] f.txt:6 put aside').querySelector('button'), null, 'a dismissed line is not dismissed again');
  assert.match(row('[P2] a.txt:1 wrong word').textContent, /Filed as #90/);
  assert.equal(row('[P2] a.txt:1 wrong word').querySelector('button[data-act="build"]'), null, 'a finding already filed has no button');
  assert.match(row('[P2] e.txt:5 an old nit').textContent, /More than 7 days old/);
  assert.ok(row('[P2] e.txt:5 an old nit').querySelector('button[data-act="build"]'), 'an old line can still be built');
  assert.deepEqual(['[P1] f.txt:6 put aside', '[P2] a.txt:1 wrong word', '[P2] e.txt:5 an old nit', '[P3] d.txt:4 a word'].map((t) => row(t).querySelector('.done-tag')?.textContent ?? null),
    ['Dismissed', 'Built', 'Expired', 'Dismissed'], 'each line done with is tagged so');
  assert.equal(count(), '0', 'the count is of the panel\'s lines alone');
  button('declined-panel').click();
  assert.deepEqual(titles(), []);
});

// A card's declined count opens the panel on that card's lines, dismissed or not. Bugs: a dismissed line there looks
// like a live one with no way to dismiss it, or a live one looks dismissed; the view has no way back to the list.
test('Declined: one card\'s lines mark a dismissed line greyed and tagged, and "Back to the list" returns to the panel\'s lines', () => {
  const w = boot({ query: '?declined=c2-4' });
  const data = full(), d = data.panels.declined.data;
  d.lines.push({ repo: 'sample', id: 'd00000000000d', time: iso(T0 - 3 * 86400000), card: 'c2-4', issue: 4, url: `${P}/4`, finding: '[P3] d.txt:4 a word', by: 'judge', why: 'taste', built: null, dismissed: null });
  d.rest.push({ repo: 'sample', id: 'd00000000000f', time: iso(T0 - 86400000), card: 'c2-4', issue: 4, url: `${P}/4`, finding: '[P1] f.txt:6 put aside', by: 'judge', why: 'out of scope', built: null, dismissed: { time: iso(T0 - 3600000), by: 'Board user owner' } });
  deliver(w, data);
  const titles = () => Array.from(panel(w, 'declined').querySelectorAll('.rows > .row .title'), (n) => n.textContent);
  const row = (t) => Array.from(panel(w, 'declined').querySelectorAll('.rows > .row')).find((r) => r.querySelector('.title').textContent === t);
  assert.match(panel(w, 'declined').textContent, /Showing the 2 lines of #4 only/);
  assert.deepEqual(titles(), ['[P1] f.txt:6 put aside', '[P3] d.txt:4 a word']);
  const gone = row('[P1] f.txt:6 put aside'), live = row('[P3] d.txt:4 a word');
  assert.equal(gone.querySelector('.row-main .done-tag').textContent, 'Dismissed', 'the tag sits at the top, beside the issue number');
  assert.ok(gone.classList.contains('is-done'), 'a dismissed line is greyed');
  assert.equal(gone.querySelector('button[data-act="dismiss"]'), null);
  assert.equal(gone.querySelector('button[data-act="build"]'), null);
  assert.equal(live.querySelector('.done-tag'), null, 'a live line is not tagged');
  assert.ok(!live.classList.contains('is-done'), 'a live line is not greyed');
  assert.ok(live.querySelector('button[data-act="dismiss"]'));
  assert.ok(live.querySelector('button[data-act="build"]'));
  // Back to the list: the panel's own lines, every card's, not dismissed, and no card filter left in the address.
  const back = panel(w, 'declined').querySelector('button[data-act="declined-list"]');
  assert.equal(back.textContent, 'Back to the list');
  back.click();
  assert.deepEqual(titles(), ['[P1] b.txt:2 no mark here', '[P3] d.txt:4 a word']);
  assert.doesNotMatch(panel(w, 'declined').textContent, /only/);
  assert.equal(new URL(w.location.href).searchParams.get('declined'), null);
  assert.equal(panel(w, 'declined').querySelector('button[data-act="declined-list"]'), null, 'the list has no way back to itself');
});

// The host takes at most 400 ids in one dismiss (dashboard_server.py control_ok). Bug: "Dismiss all shown" over 401
// lines of one project sends them in one request, which the host refuses whole, and none is dismissed.
test('Declined: Dismiss all shown over 401 lines of one project sends them 400 at most a request', async () => {
  const w = boot();
  const data = full(), d = data.panels.declined.data;
  d.lines = Array.from({ length: 401 }, (_, i) => ({ repo: 'sample', id: `d${i.toString(16).padStart(12, '0')}`, time: iso(T0 - (i + 1) * 60000), card: 'c2-4', issue: 4, url: `${P}/4`, finding: `[P3] f${i}.txt:1 a nit`, by: 'judge', why: 'taste', built: null, dismissed: null }));
  d.rest = [];
  deliver(w, data);
  panel(w, 'declined').querySelector('button[data-act="list-all"]').click();
  assert.equal(panel(w, 'declined').querySelectorAll('.rows > .row').length, 401);
  const all = panel(w, 'declined').querySelector('button[data-act="dismiss-all"]');
  assert.equal(all.textContent, 'Dismiss all shown (401)');
  all.click(); all.click();
  await settle();
  const posts = w.posts.splice(0);
  assert.deepEqual(posts.map((p) => [p.body.repo, p.body.args.length]), [['sample', 400], ['sample', 1]]);
  assert.deepEqual(posts.flatMap((p) => p.body.args), d.lines.map((x) => x.id), 'every line, each once');
  assert.equal(w.document.querySelector('#panel-declined .panel-count').textContent, '0');
});
