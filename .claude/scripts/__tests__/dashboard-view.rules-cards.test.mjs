// SPDX-License-Identifier: Apache-2.0
// The Rules tab and the waiting cards with no GitHub issue (the snapshot's queue.cards).
// Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { boot, deliver, settle, panel, P, CONTROL, full, act, produced, figure, heldP, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

const issue = (n) => ({ repo: 'sample', card: null, issue: n, title: `Issue ${n}`, url: `${P}/${n}`, priority: 'P2', followup: false, retried: false, areas: [] });
const card = (k, kind, over = {}) => ({ card: `c20261102T00000${k}-sample-0`, title: `Card ${k}`, kind, priority: 'P2', created: '2026-11-02T00:00:00Z', held: false, waitsFor: [], rule: null, ...over });
// Two ready issues and these cards, with no pin, nothing held and nothing skipped among the issues.
function rules(cards, order = []) {
  const d = full(), r = d.panels.rules.data;
  Object.assign(r, { cards, queue: [issue(20), issue(22)], waits: [], skipped: [], held: [], control: { ...CONTROL, held: [], order }, open: { ...r.open, held: [] } });
  return d;
}
const shown = (d) => { const w = boot({ tab: 'rules' }); deliver(w, d); return w; };
const THREE = () => [card(1, 'Review follow-up of #3'), card(2, 'Docs sweep'), card(3, 'Split part of #2')];
// Next up's rows: an issue's number or a card's kind, then its marks; a folded run by its name and count.
const flow = (w) => Array.from(produced(w).querySelectorAll('.rules-flow > li'), (x) => (x.classList.contains('rules-cards')
  ? x.querySelector('.rules-group-toggle').textContent : [x.querySelector('.issue').textContent, x.querySelector('.rules-marks').textContent]));
const counts = (w) => ['ready', 'waiting', 'held', 'skipped'].map((k) => figure(w, k));
const unread = (w) => Array.from(produced(w).querySelectorAll('.warn-note'), (x) => x.textContent).filter((t) => /no GitHub issue/.test(t));

// Bug (#1714): the Rules tab showed no queued card with no GitHub issue and left them out of "ready to build".
test('Rules: the waiting cards with no GitHub issue show in Next up ahead of the issues, by kind, and are counted', () => {
  const w = shown(rules(THREE()));
  assert.deepEqual(flow(w), [['Review follow-up of #3', 'ready'], ['Docs sweep', 'ready'], ['Split part of #2', 'ready'], ['#20', 'ready'], ['#22', 'ready']]);
  assert.deepEqual(counts(w), ['5', '0', '0', '0']);
  assert.deepEqual(unread(w), []);
});

// Bug: the cards put ahead of a pinned issue, which pick() starts before them.
test('Rules: a pinned issue stays ahead of the cards with no GitHub issue in Next up', () => {
  const w = shown(rules(THREE(), [20]));
  assert.deepEqual(flow(w).map((x) => x[0]), ['#20', 'Review follow-up of #3', 'Docs sweep', 'Split part of #2', '#22']);
});

// Bug: Next up put every pinned issue before every card, so with order [card 2, 20] it showed #20 first while pick()
// starts card 2 first.
test('Rules: a card pinned before an issue shows before it in Next up', () => {
  const w = shown(rules(THREE(), [card(2).card, 20]));
  assert.deepEqual(flow(w).map((x) => x[0]), ['Docs sweep', '#20', 'Review follow-up of #3', 'Split part of #2', '#22'], 'order [card 2, 20]');
});

// Bug: Next up placed a card by its own id alone, not by its pins, so a split part of the ordered umbrella #9 showed
// behind the older cards while pick() starts it first.
test('Rules: a card whose parent umbrella is pinned shows by that pin in Next up', () => {
  const w = shown(rules([...THREE(), card(4, 'Split part of #9', { pins: [card(4).card, 30, 9] })], [9]));
  assert.deepEqual(flow(w).map((x) => x[0]), ['Split part of #9', 'Review follow-up of #3', 'Docs sweep', 'Split part of #2', '#20'], 'order [9], card 4 pins [its id, 30, 9]');
});

// Bug: cards that pick does not take filled Next up, so the issue Conveyor picks next dropped off it.
test('Rules: cards with no GitHub issue that cannot start take no row of Next up', () => {
  const w = shown(rules(Array.from({ length: 5 }, (_, i) => card(i, 'Foreman order', { waitsFor: [99] }))));
  assert.deepEqual(flow(w), [['#20', 'ready'], ['#22', 'ready']]);
  assert.equal(figure(w, 'waiting'), '5');
});

// Bug: with the open issues not listed, the cards the snapshot still had were neither counted nor shown.
test('Rules: with the open issues not listed, the cards with no GitHub issue still show and are counted', () => {
  const d = rules([card(1, 'Docs sweep'), card(2, 'Foreman order', { held: true }), card(3, 'Tests page', { rule: 'area:infra' })]);
  Object.assign(d.panels.rules.data, { queue: null, skipped: null, waits: null, held: null, open: null, issuesError: 'GitHub did not list the open issues.' });
  const w = shown(d);
  assert.deepEqual(flow(w), [['Docs sweep', 'ready']]);
  assert.deepEqual(counts(w), ['1', '0', '1', '1']);
  assert.match(produced(w).querySelector('.warn-note').textContent, /GitHub did not list the open issues/);
  assert.match(produced(w).querySelector('.rules-skip').textContent, /Tests page/);
  assert.match(heldP(w).querySelector('[data-card]').textContent, /Foreman order.*Card 2.*held/);
});

// Bug: a review follow-up's title, its finding, showed its backticks as text.
test('Rules: text in backticks in a card title is a code span, with no backtick shown', () => {
  const w = shown(rules([card(1, 'Review follow-up of #3', { title: '[P2] `testpick()` takes a held card. It must not.' })]));
  const title = produced(w).querySelector('[data-card] .board-title');
  assert.equal(title.textContent, '[P2] testpick() takes a held card. It must not.');
  assert.deepEqual(Array.from(title.querySelectorAll('code.why-code'), (x) => x.textContent), ['testpick()']);
  // jsdom draws no layout, so that the title's sentences share its line can only be read from the rule of app.css.
  const css = readFileSync(new URL('../../dashboard/app.css', import.meta.url), 'utf8');
  assert.match(css, /\.rules-side \[data-card\] \.declined-line, \.rules-held \[data-card\] \.declined-line \{ display: inline; \}/);
});

// Bug: a held, waiting or skipped card shown as ready, or not shown at all, so nobody sees why it is not built.
test('Rules: a held card shows as held, a waiting one what it waits on, a skipped one its rule', async () => {
  const first = 'c20261101T000000-sample-0';
  const w = shown(rules([card(1, 'Foreman order', { held: true }), card(2, 'Review follow-up of #20', { waitsFor: [20] }), card(3, 'Docs sweep', { rule: 'area:infra' }),
    card(4, 'Tests page', { held: true, waitsFor: [first] })]));
  assert.deepEqual(counts(w), ['2', '2', '2', '1']);
  assert.deepEqual(flow(w), [['#20', 'ready'], ['#22', 'ready']]);
  assert.match(heldP(w).querySelector('.board-head').textContent, /· 2$/);
  assert.match(heldP(w).querySelector('[data-card]').textContent, /Foreman order.*Card 1.*held/);
  assert.match(produced(w).querySelector('.rules-skip').textContent, /Docs sweep.*Conveyor never builds area:infra/);
  act(produced(w), 'waits-open').click();
  await settle();
  const waits = Array.from(produced(w).querySelectorAll('.rules-wait'), (x) => x.textContent);
  assert.match(waits[0], /Review follow-up of #20.*waits on #20 \(queued\)/);
  assert.match(waits[1], new RegExp(`Tests page.*waits on card ${first}also held`));
  // The held search finds a card by its kind, and leaves out the others.
  const search = act(heldP(w), 'held-search');
  search.value = 'foreman';
  search.dispatchEvent(new w.Event('input'));
  assert.deepEqual(Array.from(heldP(w).querySelectorAll('[data-card] .issue'), (x) => x.textContent), ['Foreman order']);
});

// Bug: a hundred follow-ups listed one by one push every issue out of Next up.
test('Rules: a long run of cards with no GitHub issue is one row with its count, which opens', async () => {
  const w = shown(rules(Array.from({ length: 7 }, (_, i) => card(i, `Review follow-up of #${i + 1}`))));
  assert.deepEqual(flow(w), ['▸Cards with no GitHub issue7', ['#20', 'ready'], ['#22', 'ready']]);
  assert.equal(figure(w, 'ready'), '9');
  act(panel(w, 'rules-produce'), 'cards-next').click();
  await settle();
  assert.equal(act(panel(w, 'rules-produce'), 'cards-next').getAttribute('aria-expanded'), 'true');
  assert.equal(produced(w).querySelectorAll('.rules-cards [data-card]').length, 7);
});

// Bug: a record that could not be read shown as no card waiting.
test('Rules: with the record of the cards with no GitHub issue not read, the issues show and one line says so', () => {
  const w = shown(rules(null));
  assert.deepEqual(flow(w), [['#20', 'ready'], ['#22', 'ready']]);
  assert.deepEqual(unread(w), ['Conveyor could not read the cards with no GitHub issue.']);
});
