// SPDX-License-Identifier: Apache-2.0
// The Rules tab turns each standing kind of routine yes (the pack's auto.standing) on or off: one row a kind, On or
// Off, the snapshot's list the pressed state. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { boot, deliver, next, settle, full, act, rulesP, cases, T0 } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const sent = async (w, fn) => { fn(); await settle(); return w.posts.splice(0).map((p) => p.body); };
const pressed = (w, a) => act(rulesP(w), a).getAttribute('aria-pressed');

// Bugs: the owner could not turn a kind on or off from the Board, so the pack's list stayed as setup wrote it; a kind
// that is on showed as off, so a click sent the wrong change; a kind saved here showed its old state until the next
// snapshot.
test('Rules: each standing kind is On or Off as the pack says, and a click sends that kind on or off', async () => {
  const w = boot({ tab: 'rules' });
  const d = full();
  d.panels.rules.data.standing = ['asked-fix'];
  deliver(w, d);
  assert.equal(pressed(w, 'standing-asked-fix-on'), 'true');
  assert.equal(pressed(w, 'standing-fixed-block-off'), 'true');
  assert.ok(rulesP(w).querySelector('[data-rule="standing-fixed-block"]').textContent.includes('off: the Foreman asks you first'));
  // Bug (#1589): the review-retry row said every review block is tried again, but an issue is tried again one time.
  assert.match(rulesP(w).querySelector('[data-rule="standing-review-retry"]').textContent, /tried again one time for each issue.*the next block comes to you/);
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'standing-fixed-block-on').click()), [{ action: 'standing', args: ['fixed-block', 'on'], repo: 'sample' }]);
  assert.equal(pressed(w, 'standing-fixed-block-on'), 'true', 'the kind saved shows as on before the next snapshot');
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'standing-asked-fix-off').click()), [{ action: 'standing', args: ['asked-fix', 'off'], repo: 'sample' }]);
  assert.equal(pressed(w, 'standing-asked-fix-off'), 'true');
  assert.equal(pressed(w, 'standing-fixed-block-on'), 'true', 'turning one kind off leaves the other on');
});

// Issue 1034: the pack is not an input of the snapshot, so the snapshot kept from before a save is served for a while
// after it. Bug: the next frame of that old snapshot showed the kind saved On as Off again. It stays On until a snapshot
// read at or after the host's answer, which then shows what it holds; a refused save shows the old value and the error.
test('Rules: a standing kind saved On stays On through frames read before the save, and a frame read after shows the snapshot', async () => {
  const w = boot({ tab: 'rules' });
  const frame = (readAt) => { const d = full(); Object.assign(d.panels.rules.data, { standing: [], readAt: new Date(readAt).toISOString() }); return d; };
  const answer = (ok) => ({ ok, status: ok ? 200 : 409, headers: { get: (k) => (k === 'X-Answered-At' ? String(T0 / 1000) : null) },
    text: () => Promise.resolve(ok ? 'conveyor: review-retry is on' : 'conveyor: auto standing: the pack is not writable') });
  deliver(w, frame(T0 - 20000));
  w.reply = answer(false);
  await sent(w, () => act(rulesP(w), 'standing-review-retry-on').click());
  assert.equal(pressed(w, 'standing-review-retry-off'), 'true', 'refused: the old value shows');
  assert.match(rulesP(w).querySelector('.rules-note').textContent, /^Not done: .*the pack is not writable/);
  w.reply = answer(true);
  await sent(w, () => act(rulesP(w), 'standing-review-retry-on').click());
  assert.equal(pressed(w, 'standing-review-retry-on'), 'true');
  next(w, frame(T0 - 10000));
  assert.equal(pressed(w, 'standing-review-retry-on'), 'true', 'a frame of the snapshot read before the save keeps it On');
  next(w, frame(T0 + 1000));
  assert.equal(pressed(w, 'standing-review-retry-off'), 'true', 'a snapshot read after the save shows what it holds');
});

// Bug: a Conveyor whose snapshot names no standing kinds was sent a change it cannot make.
test('Rules: with no standing list in the snapshot, the kinds cannot be changed', () => {
  const w = boot({ tab: 'rules' });
  deliver(w, full());
  assert.equal(act(rulesP(w), 'standing-asked-fix-on').disabled, true);
  assert.equal(act(rulesP(w), 'standing-asked-fix-off').disabled, true);
});
