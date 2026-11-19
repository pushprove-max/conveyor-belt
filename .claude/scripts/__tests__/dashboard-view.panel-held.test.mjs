// SPDX-License-Identifier: Apache-2.0
// One failed read of a panel's part (#559). The Board emptied the panel at once: it shrank to a short message, all below
// it moved up, and the next good read built it anew, so each open "Every step", output and inner scroll was closed or
// reset. A panel that shows data now keeps it, with a short note above it; one that never had data shows the error alone.
// Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { T0, iso, boot, panel, state, deliver, next, trackOf, full, clone, cases, openEvery } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const at = (s) => iso(T0 - 1000000 + s * 1000);

test('a panel with data keeps it through a failed read, with a note, and the next good read keeps what was open', () => {
  const w = boot();
  const data = full();
  const card = data.panels.belt.data.cards[0];
  card.track = trackOf('++!>..', 'fix', { since: at(700), records: [
    { name: 'picked', state: 'done', sec: null, at: at(0) }, { name: 'building', state: 'done', sec: 600, at: at(600) },
    { name: 'tests failed', state: 'failed', sec: 100, at: at(700), why: 'exit 1', output: 'not ok 1 - pays once' }, { name: 'fix 1', state: 'now', sec: null }] });
  deliver(w, data);
  const good = clone(data.panels.belt);
  const row = () => panel(w, 'belt').querySelector(`li[data-key="sample:${card.card}"]`);
  const steps = openEvery(w, row().querySelector('details.track-detail'));
  const out = row().querySelector('details.output');
  out.open = true;
  out.querySelector('pre.output-text').scrollTop = 120;
  const note = () => panel(w, 'belt').querySelector('.panel-note');

  // D1: the read fails; the data, its open "Every step" and its output stay, the error is a note above them.
  data.panels.belt = { error: 'buildhost did not answer: timed out', data: null };
  next(w, data);
  assert.equal(state(w, 'belt'), 'ready', 'the panel still shows its data');
  assert.equal(row()?.querySelector('details.track-detail'), steps, 'the card\'s row is still drawn, the same one');
  assert.equal(steps.open, true, 'the open "Every step" stays open');
  assert.equal(panel(w, 'belt').querySelector('.state-error'), null, 'no error block in place of the data');
  assert.match(note().textContent, /^The Board could not read .+ just now, so it shows what it read last\./);
  assert.equal(note().querySelector('.warn-note').dataset.tip, 'Details: buildhost did not answer: timed out', 'the raw reply on tap only');
  assert.equal(panel(w, 'belt').querySelector('.panel-body').firstChild, note(), 'the note is above the data');

  // D2: the next good read takes the note away and draws as a refresh: the same rows, open, scrolled where they were.
  data.panels.belt = good;
  next(w, data);
  assert.equal(note(), null, 'the note is gone');
  assert.equal(state(w, 'belt'), 'ready');
  assert.equal(row().querySelector('details.track-detail').open, true, '"Every step" is still open');
  assert.equal(row().querySelector('details.output').open, true, 'the output is still open');
  assert.equal(row().querySelector('pre.output-text').scrollTop, 120, 'the output keeps its scroll');
});

test('a panel that never had data shows the error state alone, with no note', () => {
  const w = boot();
  const data = full();
  data.panels.belt = { error: 'buildhost did not answer: timed out', data: null };
  deliver(w, data);
  assert.equal(state(w, 'belt'), 'error');
  assert.ok(panel(w, 'belt').querySelector('.state-error'), 'the error state is drawn');
  assert.equal(panel(w, 'belt').querySelector('.panel-note'), null, 'no note: there is no data for it to stand above');
  assert.equal(panel(w, 'belt').querySelector('li[data-key]'), null, 'and no rows');
});
