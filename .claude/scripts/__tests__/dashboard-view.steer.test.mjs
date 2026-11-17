// SPDX-License-Identifier: Apache-2.0
// The Rules tab's "Card work yields to you" (issue 194): the machine's steer, the host file's, set from the Board.
// Shared setup: dashboard-view.helpers.mjs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { boot, deliver, next, settle, full, act, rulesP, ruled } from './dashboard-view.helpers.mjs';

// The Rules part with the machine's steer as given; none: a snapshot from an engine before it.
function data(steer) {
  const d = full();
  if (steer !== 'none') d.panels.rules.data.steer = steer;
  return d;
}
const row = (w) => ruled(w).querySelector('[data-rule="steer"]');
const pressed = (w) => ['steer-on', 'steer-off'].map((a) => act(rulesP(w), a).getAttribute('aria-pressed'));
const sent = async (w, fn) => { fn(); await settle(); return w.posts.splice(0); };

// Bugs this guards: the setting could not be turned off or on from the Board (only by editing the host file); it was
// sent as a project's control action, which no project's record holds; with it off the row did not say so.
test('Rules: Card work yields to you is turned off and on from its row, as a machine setting, and says when it is off', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data(true));
  assert.deepEqual(pressed(w), ['true', 'false'], 'on');
  assert.doesNotMatch(row(w).textContent, /normal priority/, 'on: nothing says it is off');
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'steer-on').click()), [], 'the choice in force sends nothing');
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'steer-off').click()), [{ url: 'machine', body: { action: 'steer', value: 'off' } }]);
  // The host took it: the row shows Off before a snapshot says so, with Undo on the line that says it was done.
  assert.deepEqual(pressed(w), ['false', 'true'], 'the answer shows at once');
  assert.match(rulesP(w).querySelector('.rules-note').textContent, /Card work yields to you is off/);
  next(w, data(false));
  assert.deepEqual(pressed(w), ['false', 'true']);
  assert.match(row(w).textContent, /off: card work runs at normal priority/, 'off: the row says so beside the switch');
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'steer-on').click()), [{ url: 'machine', body: { action: 'steer', value: 'on' } }]);
});

// Bug this guards: a snapshot from an engine with no steer was read as off, or sent a machine action it refuses.
test('Rules: Card work yields to you, not said by the snapshot, reads as on and is sent to no engine', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data('none'));
  assert.deepEqual(pressed(w), ['true', 'false'], 'unsaid: on');
  assert.ok(act(rulesP(w), 'steer-on').disabled && act(rulesP(w), 'steer-off').disabled, 'an older engine is sent neither');
  assert.match(row(w).textContent, /needs a newer Conveyor/);
});
