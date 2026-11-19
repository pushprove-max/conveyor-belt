// SPDX-License-Identifier: Apache-2.0
// "Show output" stays open through a refresh. The owner opened a step's output on a card's timeline and it closed again
// each time the step's output grew: the redraw made every output toggle new and closed. Needs you kept its row but never
// drew a longer output into it, and Lanes drew its rows anew, its output closed. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { T0, iso, boot, panel, deliver, next, trackOf, full, cases, openEvery } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const at = (s) => iso(T0 - 1000000 + s * 1000);
// The text inside an output toggle, as shown.
const text = (det) => det.querySelector('pre.output-text').textContent;

test('a step\'s "Show output" on the timeline stays open, with the longer output, when the timeline is redrawn', () => {
  const w = boot();
  const data = full();
  const card = data.panels.belt.data.cards[0];
  const track = (tail) => trackOf('++!>..', 'fix', { since: at(700), records: [
    { name: 'picked', state: 'done', sec: null, at: at(0) }, { name: 'building', state: 'done', sec: 600, at: at(600) },
    { name: 'tests failed', state: 'failed', sec: 100, at: at(700), why: 'exit 1', output: tail }, { name: 'fix 1', state: 'now', sec: null }] });
  card.track = track('not ok 1 - pays once');
  deliver(w, data);
  const row = () => panel(w, 'belt').querySelector(`li[data-key="sample:${card.card}"]`);
  openEvery(w, row().querySelector('details.track-detail'));
  row().querySelector('details.output').open = true;
  card.track = track('not ok 1 - pays once\nnot ok 2 - refunds');
  next(w, data);
  const out = row().querySelector('details.output');
  assert.equal(out.querySelector('summary').textContent, 'Show full output');
  assert.equal(out.open, true, 'the output the owner opened is still open');
  assert.equal(text(out), 'not ok 1 - pays once\nnot ok 2 - refunds', 'with the new output inside');
});

test('a blocked card\'s "Show output" in Needs you stays open, with the longer output, through a refresh', () => {
  const w = boot();
  const data = full();
  const blocked = data.panels.needs.data.cards.blocked[0];
  blocked.tail = 'not ok 1 - pays once';
  deliver(w, data);
  const out = () => panel(w, 'needs').querySelector(`li[data-key="blocked:${blocked.card}"] details.output`);
  out().open = true;
  blocked.tail = 'not ok 1 - pays once\nnot ok 2 - refunds';
  next(w, data);
  assert.equal(out().open, true, 'the output the owner opened is still open');
  assert.equal(text(out()), 'not ok 1 - pays once\nnot ok 2 - refunds', 'with the new output inside');
});

// Bug (#557): the box was built new at each refresh, so a reader who scrolled up in a card's output went back to the
// top about every second. The same output keeps the same box; more output puts the new box where the old one was.
test('an open "Show output" keeps its scroll through a refresh: the same box with the same output, its place with more', async () => {
  const w = boot();
  const data = full();
  const blocked = data.panels.needs.data.cards.blocked[0];
  blocked.tail = 'not ok 1 - pays once';
  deliver(w, data);
  const out = () => panel(w, 'needs').querySelector(`li[data-key="blocked:${blocked.card}"] details.output`);
  const was = out();
  was.open = true;
  was.querySelector('pre.output-text').scrollTop = 120;
  // The reader selected "pays" to copy it: the box is taken out and put back by the redraw, which ended the selection.
  const words = was.querySelector('pre.output-text .output-line').firstChild;
  w.getSelection().setBaseAndExtent(words, 11, words, 15);
  blocked.reason = 'tests failed three times';  // the panel is drawn again only when its data changed
  next(w, data);
  await Promise.resolve();
  assert.equal(out(), was, 'the same output keeps the same box');
  assert.equal(out().querySelector('pre.output-text').scrollTop, 120);
  assert.equal(String(w.getSelection()), 'pays', 'the text selected in it stays selected');
  blocked.tail = 'not ok 1 - pays once\nnot ok 2 - refunds';
  next(w, data);
  await Promise.resolve();
  assert.notEqual(out(), was, 'more output is a new box');
  assert.equal(text(out()), 'not ok 1 - pays once\nnot ok 2 - refunds');
  assert.equal(out().querySelector('pre.output-text').scrollTop, 120, 'scrolled where the old box was');
});

test('a blocked landing\'s "Show output" in Lanes stays open through a refresh, and a new card\'s output starts closed', () => {
  const w = boot();
  const data = full();
  const fast = data.panels.lanes.data.records[0].fast;
  fast.landing = { state: 'blocked', card: 'c9-123', reason: 'tests failed', tail: 'not ok 1 - pays once' };
  deliver(w, data);
  const out = () => panel(w, 'lanes').querySelector('li[data-lane="Fast lane"] > details.output');
  out().open = true;
  fast.landing.tail = 'not ok 1 - pays once\nnot ok 2 - refunds';
  next(w, data);
  assert.equal(out().open, true, 'the output the owner opened is still open');
  assert.equal(text(out()), 'not ok 1 - pays once\nnot ok 2 - refunds', 'with the new output inside');
  // Another card blocked in the lane: its output is not the one the owner opened.
  fast.landing = { ...fast.landing, card: 'c9-124', tail: 'not ok 3 - ships' };
  next(w, data);
  assert.equal(out().open, false, "another card's output starts closed");
});
