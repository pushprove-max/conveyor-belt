// SPDX-License-Identifier: Apache-2.0
// On the belt while cards run (issue 499): the Overview stuttered, more with more cards on the belt. Each new token
// count of one card drew every card's row again with its whole "Every step" timeline, open or closed, and each beat
// forced one layout a running chip. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { T0, iso, clone, boot, panel, deliver, next, tick, trackOf, timesOf, full, cases, openEvery, pickProject } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

const row = (w, key) => panel(w, 'belt').querySelector(`li[data-key="${key}"]`);
const nodes = (el) => Array.from(el.querySelectorAll('*'));
// Each node is the very node it was (identity, never an equal copy).
const same = (now, was, what) => {
  assert.equal(now.length, was.length, what);
  now.forEach((n, i) => assert.ok(n === was[i], `${what}: node ${i} (${n.tagName}.${n.className}) is a new node`));
};

// Bug it catches: a token count of card A, sent by the live feed as a Belt part, drew card B's row again, and A's
// head, its cost and its live action with it; a live action tapped open lost its popover at the next tick, as the
// update replaced it with a copy (the open popover's aria-describedby made the shown one differ from the copy).
test('a Belt part where only one card\'s tokens changed redraws only that card\'s figures', () => {
  const w = boot({ feed: true });
  const es = w.sources[0], data = full();
  data.panels.belt.data.cards[0].live = { turns: 7, lastOutputAt: iso(T0 - 4000), action: 'Bash: npm test' };
  es.readyState = 1; es.emit('open');
  es.emit('snapshot', data);
  const a = row(w, 'sample:c3-63'), b = row(w, 'widgetshop:c4-5');
  const head = a.querySelector('.row-main'), heads = nodes(head), others = nodes(b);
  const cost = a.querySelector('.live-cost'), action = a.querySelector('.live-action');
  assert.match(cost.textContent, /412k tokens so far/);
  // Issue 598: the live action was a span, out of the keyboard's reach. It is a button that takes focus and opens the
  // full command (Enter on a button clicks it).
  assert.equal(action.tagName, 'BUTTON');
  assert.equal(action.type, 'button');
  action.focus();
  assert.ok(w.document.activeElement === action, 'the live action takes focus');
  // The live action's words tapped open.
  action.click();
  const pop = w.document.getElementById('tip');
  assert.equal(pop.hidden, false, 'the tapped live action shows its words');
  assert.equal(pop.textContent, 'Bash: npm test', 'its words are the full command');
  const renders = panel(w, 'belt').dataset.renders;
  const part = clone(data.panels.belt);
  part.data.cards[0].tokens = { claude: 900000, codex: 12300 };
  es.emit('panel', { id: 'belt', part, updatedAt: iso(T0) });
  tick(w, 1000);
  assert.notEqual(panel(w, 'belt').dataset.renders, renders, 'the belt was drawn with the new part');
  // Each read from the page as it is now: rows the Board replaced would leave the saved ones detached.
  assert.ok(row(w, 'widgetshop:c4-5') === b, 'card B is the same row');
  same(nodes(row(w, 'widgetshop:c4-5')), others, 'card B keeps each of its nodes');
  const a2 = row(w, 'sample:c3-63');
  assert.ok(a2 === a, 'card A is the same row');
  assert.ok(a2.querySelector('.row-main') === head, "card A's head is the same node");
  same(nodes(a2.querySelector('.row-main')), heads, "card A's head holds the same nodes");
  assert.ok(a2.querySelector('.live-cost') === cost, 'the cost is the same node');
  assert.match(a2.querySelector('.live-cost').textContent, /912k tokens so far/, 'with the new figure');
  assert.ok(a2.querySelector('.live-action') === action, 'the live action is the same node');
  assert.equal(pop.hidden, false, 'its words stay open through the update and the tick');
});

// Bug it catches: with one project shown, a token count of a card of another project (not shown) drew every shown row
// again, as the part shown was equal to the one drawn last and was taken for a redraw of the whole panel.
test('a change to a card of a project not shown keeps every shown row as it is', () => {
  const w = boot();
  const data = full();
  data.panels.machine.data.repos = ['sample', 'widgetshop'];
  deliver(w, data);
  pickProject(w, 'sample');
  assert.equal(row(w, 'widgetshop:c4-5'), null, 'the other project is not shown');
  const a = row(w, 'sample:c3-63'), was = nodes(a);
  const card = data.panels.belt.data.cards.find((c) => c.card === 'c4-5');
  card.tokens = { claude: 5000, codex: 0 }; card.reading = true;
  next(w, data);
  same(nodes(row(w, 'sample:c3-63')), was, 'the shown card keeps each of its nodes');
});

// Bug it catches: a new model name came in the same refresh as another card's new tokens; card A, its own part as it
// was, kept its old model name.
test('a new model name redraws a card whose part is as it was, when another card changed with it', () => {
  const w = boot();
  const data = full();
  deliver(w, data);
  const meta = () => row(w, 'sample:c3-63').querySelector('.row-meta').textContent;
  assert.ok(!meta().includes('Sol (proxy)'), meta());
  data.panels.rules.data.prices = { ...data.panels.rules.data.prices, overrides: { 'gpt-6.1-sol': { name: 'Sol (proxy)', aliases: ['gpt-x'] } } };
  data.panels.belt.data.cards.find((c) => c.card === 'c4-5').tokens = { claude: 5000, codex: 0 };
  next(w, data);
  assert.ok(meta().includes('Sol (proxy)'), `card A shows the new model name: ${meta()}`);
});

// Bug it catches (issue 1085): a running card showed its step's model alone, so with Pick settings giving each seat its
// own effort the belt did not say how the step runs. A card with no effort known still shows the model alone.
test('a running card shows the effort beside its model, and the model alone when no effort is known', () => {
  const w = boot();
  const data = full();
  Object.assign(data.panels.belt.data.cards.find((c) => c.card === 'c4-5'), { model: 'claude-opus-5-5', effort: 'high' });
  deliver(w, data);
  const meta = (key) => row(w, key).querySelector('.row-meta').textContent;
  // The fixture's prices give this model no display name, so the Board names it by its ID.
  assert.ok(meta('widgetshop:c4-5').includes('claude-opus-5-5 at high'), `the effort beside the model: ${meta('widgetshop:c4-5')}`);
  assert.ok(!/ at /.test(meta('sample:c3-63')), `no effort known, the model alone: ${meta('sample:c3-63')}`);
  assert.ok(meta('sample:c3-63').includes('gpt-x'), `the model is still shown: ${meta('sample:c3-63')}`);
});

// Bug it catches (issue 1334): a card picked since the kept snapshot was on no belt until a new snapshot build ended.
// The snapshot reader now adds it from the card records (fromRecords), with no model or cost yet: the belt shows it,
// its title and step, and says its details come with the next snapshot, not "no AI model in this step".
test('a card the snapshot reader added from the card records shows on the belt, marked as not yet in a full snapshot', () => {
  const w = boot();
  const data = full();
  data.panels.belt.data.cards.push({ repo: 'sample', card: 'c9-70', issue: 70, name: null, title: 'Picked since the snapshot', step: 'build', stepAt: iso(T0 - 5000), landed: false, fromRecords: true });
  deliver(w, data);
  const r = row(w, 'sample:c9-70');
  assert.ok(r, 'the card from the records has a row on the belt');
  assert.match(r.textContent, /Picked since the snapshot/, `its title is shown: ${r.textContent}`);
  assert.match(r.textContent, /Building/, `its step is shown: ${r.textContent}`);
  const meta = r.querySelector('.row-meta').textContent;
  assert.match(meta, /details come with the next snapshot/, `it is marked as in no full snapshot yet: ${meta}`);
  assert.ok(!/no AI model in this step/.test(meta), `it does not say its step runs no model: ${meta}`);
});

// Bug it catches: each card's timeline and its earlier attempts were built at every change, though "Every step" was
// closed; and an open one must still follow each change with the keyboard where it was.
test('"Every step" holds no steps while closed, draws them and its earlier attempts on open, and follows a change while open', () => {
  const w = boot();
  const data = full();
  const card = data.panels.belt.data.cards[0];
  const at = (s) => iso(T0 - 1000000 + s * 1000);
  const records = [{ name: 'picked', state: 'done', sec: null, at: at(0) }, { name: 'building', state: 'done', sec: 600, at: at(600) },
    { name: 'review 1 (GO)', state: 'done', sec: 300, at: at(900) }, { name: 'tests', state: 'now', sec: null }];
  const prior = { card: 'c3-60', start: iso(T0 - 3600000), end: iso(T0 - 2400000), sec: 1200, reason: 'tests failed', track: trackOf('++++!.', '', { at: null, since: null }) };
  Object.assign(card, timesOf(T0, 1200), { earlier: [prior], track: trackOf('+++>..', 'tests', { since: at(900), records }) });
  deliver(w, data);
  const r = row(w, 'sample:c3-63');
  const closed = r.querySelector('.more > details.track-detail');
  assert.equal(closed.open, false);
  assert.equal(closed.hidden, false, 'it is shown, to be opened');
  assert.deepEqual(Array.from(closed.children, (n) => n.tagName), ['SUMMARY'], 'closed, it is its summary alone');
  assert.equal(r.querySelector('.tl-item'), null, 'no step is drawn');
  const det = openEvery(w, closed);
  assert.equal(det.open, true);
  assert.equal(det.querySelectorAll(':scope > ol.timeline > li.tl-item').length, 4, 'opened, it shows the steps');
  assert.equal(det.querySelectorAll(':scope > details.tl-earlier').length, 1, 'and the earlier attempt');
  // The keyboard on the Review bar; a change adds a step.
  const items = () => Array.from(r.querySelectorAll('.more > details.track-detail > ol.timeline > li.tl-item'));
  items()[2].focus();
  card.track = trackOf('++++>.', 'landing', { since: iso(T0), records: [...clone(records.slice(0, 3)),
    { name: 'tests passed', state: 'done', sec: 100, at: iso(T0) }, { name: 'landing', state: 'now', sec: null }] });
  next(w, data);
  assert.deepEqual(items().map((li) => li.querySelector('.tl-label').firstChild.textContent),['Setup', 'Build', 'Review 1', 'Tests', 'Land'], 'its steps follow the change');
  assert.equal(w.document.activeElement, items()[2], 'the focus stays on the same step');
  // Closed again, its steps are dropped; opened again, the earlier attempt opened inside it is still open (it once
  // started closed, as the closed one kept only its summary).
  const open = r.querySelector('.more > details.track-detail');
  open.querySelector(':scope > details.tl-earlier').open = true;
  open.open = false;
  open.dispatchEvent(new w.Event('toggle'));
  assert.equal(r.querySelector('.tl-item'), null, 'closed again, no step is drawn');
  const again = openEvery(w, r.querySelector('.more > details.track-detail'));
  assert.equal(again.querySelector(':scope > details.tl-earlier').open, true, 'reopened, the earlier attempt is still open');
});

// Bug it catches: each running chip's beat forced a layout of its own (a read of offsetWidth between its class off and on).
test('one beat of three running chips reads offsetWidth once', () => {
  const w = boot();
  const data = full();
  const cards = data.panels.belt.data.cards;
  cards.push({ ...clone(cards[0]), card: 'c8-64', issue: 64, title: 'Third card' });
  deliver(w, data);
  const chips = panel(w, 'belt').querySelectorAll('.step6[data-state="now"] .step-chip');
  assert.equal(chips.length, 3);
  // Each chip beating from an earlier beat: the one read must come with the class off from all, or no beat restarts.
  chips.forEach((c) => c.classList.add('beat'));
  let reads = 0, offAtRead = null;
  Object.defineProperty(w.HTMLElement.prototype, 'offsetWidth', { configurable: true, get() {
    reads += 1; offAtRead = Array.from(chips).every((c) => !c.classList.contains('beat')); return 0;
  } });
  tick(w, 5000);
  assert.equal(reads, 1, 'one forced layout for the beat');
  assert.equal(offAtRead, true, 'read with the class off from every chip');
  assert.ok(Array.from(chips).every((c) => c.classList.contains('beat')), 'every running chip beats');
});

// Bug it catches (issue 1430): when an earlier card left the belt, ctx.list moved the kept card's row into its new place
// with insertBefore, and a moved node is blurred: the focus on the second card's control fell to the page's body.
test('a Belt part without the first card leaves the focus on the control of the second card that had it', () => {
  const w = boot({ feed: true });
  const es = w.sources[0], data = full();
  data.panels.belt.data.cards[1].live = { turns: 3, lastOutputAt: iso(T0 - 4000), action: 'Bash: npm run lint' };
  es.readyState = 1; es.emit('open');
  es.emit('snapshot', data);
  const action = row(w, 'widgetshop:c4-5').querySelector('.live-action');
  action.focus();
  const part = clone(data.panels.belt);
  part.data.cards = part.data.cards.filter((c) => c.card !== data.panels.belt.data.cards[0].card);
  es.emit('panel', { id: 'belt', part, updatedAt: iso(T0) });
  tick(w, 1000);
  assert.equal(row(w, 'sample:c3-63'), null, 'the first card left the belt');
  assert.ok(row(w, 'widgetshop:c4-5').querySelector('.live-action') === action, 'the second card keeps its control');
  assert.equal(w.document.activeElement, action, `the focus stays on it, not on ${w.document.activeElement.tagName}`);
});
