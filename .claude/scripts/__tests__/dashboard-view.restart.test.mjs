// SPDX-License-Identifier: Apache-2.0
// Issue 115: the panels' error texts said to press "Restart the Board's feed" in Health, while the mark said Live:
// the head's button was hidden and Health's was folded under "N checks fine". Each text that names the button now
// has one visible where it says. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { boot, panel, state, deliver, next, full, settle, tick, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const LABEL = 'Restart the Board\'s feed';
// Seen on the page: no hidden ancestor, and not inside a closed <details> (other than its summary).
function visible(el) {
  for (let n = el; n; n = n.parentElement) {
    if (n.hidden) return false;
    if (n.tagName === 'DETAILS' && !n.open && !(el.closest('summary') && el.closest('summary').parentElement === n)) return false;
  }
  return true;
}
const buttons = (root) => Array.from(root.querySelectorAll('button')).filter((b) => b.textContent === LABEL && visible(b));
const restartIn = (w, id) => buttons(panel(w, id));
// Every text shown on the page that tells the owner to press the restart, and where it says the button is.
function pressTexts(w) {
  const out = [], walk = w.document.createTreeWalker(w.document.body, 4);
  for (let t = walk.nextNode(); t; t = walk.nextNode()) if (/press Restart the Board's feed/i.test(t.data) && visible(t.parentElement)) out.push(t.parentElement);
  return out;
}
// A shown text that names the button with no visible button where it points (in its panel, or beside the mark above).
function unbacked(w) {
  return pressTexts(w).filter((el) => {
    if (/beside the mark above/.test(el.textContent)) return !visible(w.document.getElementById('restart'));
    const p = el.closest('.panel');
    return !p || !/in this panel|below/.test(el.textContent) || buttons(p).length === 0;
  }).map((el) => el.textContent);
}

// The bug: Belt failed while the mark said Live, and its text sent the owner to a button that was not shown.
test('a panel that could not read its data while the mark says Live has its own restart, and pressing it restarts in place', async () => {
  const w = boot();
  const data = full();
  data.panels.belt = { error: 'buildhost did not answer: timed out', data: null };
  deliver(w, data);
  assert.equal(w.document.getElementById('status').textContent, 'Live');
  assert.equal(w.document.getElementById('restart').hidden, true, 'the head shows no restart while Live');
  assert.equal(state(w, 'belt'), 'error');
  assert.match(panel(w, 'belt').textContent, /press Restart the Board's feed in this panel\./);
  const [b] = restartIn(w, 'belt');
  assert.ok(b && b.closest('.state-error'), 'the restart is in the error, next to its text');
  w.reply = { ok: true, status: 202, text: () => Promise.resolve('restarting') };
  b.click();
  assert.deepEqual(w.posts, [], 'a restart asks for a second click');
  b.click();
  const said = b.parentElement.querySelector('[role="status"]');
  assert.equal(said.textContent, 'Asking the build machine to restart the Board\'s feed…', 'it says in place that it is restarting');
  await settle(); await settle();
  assert.deepEqual(w.posts, [{ url: 'restart', body: {} }]);
  assert.equal(said.textContent, 'Restarting. The page catches up in about a minute.', 'and then the result, in place');
});

// The bug: Health's restart sat in a row that folded into "N checks fine", so the owner sent there saw none.
test('Health\'s Data row shows the restart while a panel is in error, and folds with the fine checks when none is', () => {
  const w = boot();
  const data = full();
  deliver(w, data);
  // The fixture names no stream, so the row is named for its restart, not "Data" (health.js).
  const dataRow = () => panel(w, 'health').querySelector('dt[data-check="Board\'s feed"]');
  assert.ok(dataRow().closest('details.checks-fine'), 'all fine: the Data row is folded');
  data.panels.belt = { error: 'buildhost did not answer: timed out', data: null };
  next(w, data);
  assert.equal(dataRow().closest('details.checks-fine'), null, 'a panel in error: the Data row is out of the fold');
  assert.equal(restartIn(w, 'health').length, 1, 'with its restart shown');
  assert.ok(dataRow().nextElementSibling.contains(restartIn(w, 'health')[0]), 'in the row');
  data.panels.belt = full().panels.belt;
  next(w, data);
  assert.ok(dataRow().closest('details.checks-fine'), 'the panel reads again: the Data row folds again');
});

// The rule the issue asks for: a text that names the restart has a visible button where it says, in each kind of
// failure (a panel's error, its note over the data it read last, a part it could not read, a fault of the mark).
test('every shown text that says to press Restart the Board\'s feed has a visible button where it says', () => {
  const w = boot();
  const data = full();
  data.panels.landed = { error: 'buildhost did not answer', data: null };
  deliver(w, data);
  data.panels.belt = { error: 'buildhost did not answer', data: null };
  Object.assign(data.panels.needs.data, { cards: null, cardsError: 'buildhost did not answer' });
  Object.assign(data.panels.cost.data, { cards: null, cardsError: 'buildhost did not answer' });
  data.panels.lanes.data.records[0].fast.landing = null;
  data.panels.lanes.data.cardsError = 'buildhost did not answer';
  next(w, data);
  assert.equal(state(w, 'landed'), 'error');
  assert.ok(panel(w, 'belt').querySelector('.panel-note'), 'Belt keeps its data with a note');
  for (const id of ['landed', 'belt', 'needs', 'cost', 'lanes']) assert.ok(pressTexts(w).some((el) => panel(w, id).contains(el)), `${id} names the restart`);
  assert.deepEqual(unbacked(w), []);
  tick(w, 400000);
  assert.equal(w.document.getElementById('status').textContent, 'Stale');
  assert.ok(pressTexts(w).some((el) => el.id === 'banner'), 'the mark\'s fault names the head\'s restart');
  assert.deepEqual(unbacked(w), []);
});
