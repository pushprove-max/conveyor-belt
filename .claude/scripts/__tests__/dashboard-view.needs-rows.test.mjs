// SPDX-License-Identifier: Apache-2.0
// Needs you's rows through a new snapshot of the same card: what the owner started in a row (a Close clicked once,
// the focus in a field) is still there after it. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { boot, panel, deliver, next, settle, full, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

// Bug: the blocked row's key changed when the snapshot marked its branch on main, so the row was drawn anew with a
// new Close; the Close clicked once was gone, and the second click only armed the new one.
test('Needs you: a Close clicked once on a blocked card still closes it after the snapshot marks its branch on main', async () => {
  const w = boot({ list: ['needs'] });
  const d = full();
  deliver(w, d);
  const close = () => panel(w, 'needs').querySelector('li[data-key="blocked:c2-13"] button[data-act="close"]');
  close().click();
  await settle();
  assert.deepEqual(w.posts, [], 'the first click sends nothing');
  d.panels.needs.data.cards.blocked[0].onMain = true;
  next(w, d);
  assert.ok(panel(w, 'needs').querySelector('li[data-key="blocked:c2-13"] .on-main'), 'the row says its branch is on main');
  close().click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'close', args: ['13'], repo: 'sample' } }]);
});

// Bug: a card first drawn from its records has a key of its own (':records'); the full snapshot's row replaced it, and
// the focus in its Condition field was dropped with the old row.
test('Needs you: the full snapshot of a card drawn from its records keeps the focus on its Condition field', () => {
  const w = boot({ list: ['needs'] });
  const d = full(), c = d.panels.needs.data.cards.waiting[0];
  const field = () => panel(w, 'needs').querySelector(`li[data-key^="waiting:${c.card}"] input[aria-label="Condition for the yes to #${c.issue}"]`);
  c.fromRecords = true;
  deliver(w, d);
  const was = field();
  was.focus();
  next(w, full());
  assert.notEqual(field(), was, 'the row was drawn anew');
  assert.equal(field().closest('li').dataset.key, `waiting:${c.card}`, 'the full card\'s row');
  assert.equal(w.document.activeElement, field(), 'the focus is on the new row\'s Condition field');
});

// Bug: a records-only blocked row was replaced by the full row when the snapshot first gave the whole card (with
// onMain true); the Close clicked once was on the old row, so the next click on the new row only armed it.
test('Needs you: a Close clicked once on a records-only blocked card still closes it after the full snapshot', async () => {
  const w = boot({ list: ['needs'] });
  const d = full();
  d.panels.needs.data.cards.blocked[0].fromRecords = true;
  deliver(w, d);
  const close = () => panel(w, 'needs').querySelector('li[data-key^="blocked:c2-13"] button[data-act="close"]');
  close().click();
  await settle();
  assert.deepEqual(w.posts, [], 'the first click sends nothing');
  const d2 = full();
  d2.panels.needs.data.cards.blocked[0].onMain = true;
  next(w, d2);
  assert.equal(close().closest('li').dataset.key, 'blocked:c2-13', 'the full card\'s row');
  close().click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'close', args: ['13'], repo: 'sample' } }]);
});

// Bug: the new row's Close was armed by a fresh click, so its five-second window started again when the full snapshot
// came: a Close clicked once, then again six seconds later, closed the card. The window ends five seconds after the first click.
test('Needs you: the full snapshot of a records-only blocked card keeps the end of its Close window', async () => {
  const w = boot({ list: ['needs'] });
  const d = full();
  d.panels.needs.data.cards.blocked[0].fromRecords = true;
  deliver(w, d);
  const close = () => panel(w, 'needs').querySelector('li[data-key^="blocked:c2-13"] button[data-act="close"]');
  close().click();
  w.clock += 4000;
  w.timeouts = [];
  next(w, full());
  assert.equal(close().closest('li').dataset.key, 'blocked:c2-13', 'the full card\'s row');
  assert.ok(close().hasAttribute('data-armed'), 'the new Close is armed');
  const arm = w.timeouts.filter((t) => t.ms === 1000);
  assert.equal(arm.length, 1, `the new Close's window ends one second on, at the first click's end: ${JSON.stringify(w.timeouts.map((t) => t.ms))}`);
  w.clock += 1000;
  arm[0].fn();
  assert.ok(!close().hasAttribute('data-armed'), 'the window ended');
  close().click();
  await settle();
  assert.deepEqual(w.posts, [], 'a click six seconds after the first only arms Close again');
});

// Bug: the focus moved to the new row only from a control with data-act or aria-label, so the issue link of a
// records-only waiting or blocked row lost the focus when the full snapshot replaced the row.
for (const kind of ['waiting', 'blocked']) {
  test(`Needs you: the full snapshot of a ${kind} card drawn from its records keeps the focus on its issue link`, () => {
    const w = boot({ list: ['needs'] });
    const d = full(), c = d.panels.needs.data.cards[kind][0];
    const link = () => panel(w, 'needs').querySelector(`li[data-key^="${kind}:${c.card}"] a.issue`);
    c.fromRecords = true;
    deliver(w, d);
    const was = link();
    was.focus();
    assert.equal(w.document.activeElement, was, 'the link took the focus');
    next(w, full());
    assert.notEqual(link(), was, 'the row was drawn anew');
    assert.equal(w.document.activeElement, link(), 'the focus is on the new row\'s issue link');
  });
}
