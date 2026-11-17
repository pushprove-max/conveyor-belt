// SPDX-License-Identifier: Apache-2.0
// The Rules tab turns each standing kind of routine yes (the pack's auto.standing) on or off: one row a kind, On or
// Off, the snapshot's list the pressed state. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { boot, deliver, settle, full, act, rulesP, cases } from './dashboard-view.helpers.mjs';

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
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'standing-fixed-block-on').click()), [{ action: 'standing', args: ['fixed-block', 'on'], repo: 'sample' }]);
  assert.equal(pressed(w, 'standing-fixed-block-on'), 'true', 'the kind saved shows as on before the next snapshot');
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'standing-asked-fix-off').click()), [{ action: 'standing', args: ['asked-fix', 'off'], repo: 'sample' }]);
  assert.equal(pressed(w, 'standing-asked-fix-off'), 'true');
  assert.equal(pressed(w, 'standing-fixed-block-on'), 'true', 'turning one kind off leaves the other on');
});

// Bug: a Conveyor whose snapshot names no standing kinds was sent a change it cannot make.
test('Rules: with no standing list in the snapshot, the kinds cannot be changed', () => {
  const w = boot({ tab: 'rules' });
  deliver(w, full());
  assert.equal(act(rulesP(w), 'standing-asked-fix-on').disabled, true);
  assert.equal(act(rulesP(w), 'standing-asked-fix-off').disabled, true);
});
