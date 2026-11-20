// SPDX-License-Identifier: Apache-2.0
// The Rules tab's rule "Lint check" (#261, the control record's rules.lint), sent as `control rules lint=on|off`, and
// the pack's lint commands listed under it, read-only (the snapshot's lintCommands). Shared setup:
// dashboard-view.helpers.mjs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { boot, deliver, next, settle, full, act, rulesP, ruled } from './dashboard-view.helpers.mjs';

const CMDS = [{ run: 'shellcheck {files}', files: ['*.sh', 'hooks/*.sh'] }, { run: 'npm run lint', files: ['*.js'] }];
// The Rules part with the rule and the pack's commands as given; 'none' leaves the rule out (an engine before it).
function data(lint, cmds = CMDS) {
  const d = full(), r = d.panels.rules.data;
  r.control = { ...r.control, rules: { ...r.control.rules, ...(lint === 'none' ? {} : { lint }) } };
  r.lintCommands = cmds;
  return d;
}
const row = (w) => ruled(w).querySelector('[data-rule="lint"]');
const pressed = (w) => ['lint-on', 'lint-off'].map((a) => act(rulesP(w), a).getAttribute('aria-pressed'));
const sent = async (w, fn) => { fn(); await settle(); return w.posts.splice(0).map((p) => p.body); };

// Bugs this guards: the owner could not turn the lint check off from the Board, or Off sent nothing or the wrong rule;
// with it off the row did not say so.
test('Rules: Lint check, on by default, is turned off and on from its row, and says when it is off', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data(true));
  assert.deepEqual(pressed(w), ['true', 'false']);
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'lint-off').click()), [{ action: 'rules', args: ['lint=off'], repo: 'sample' }]);
  next(w, data(false));
  assert.deepEqual(pressed(w), ['false', 'true']);
  assert.match(row(w).textContent, /off: no lint command runs/);
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'lint-on').click()), [{ action: 'rules', args: ['lint=on'], repo: 'sample' }]);
});

// Bugs this guards: the tab did not show what the rule runs; or it offered a way to change the pack's commands, which
// only the pack's lint field sets (a change of lint policy needs the owner's yes on a card).
test('Rules: Lint check lists the pack\'s lint commands, with no control to edit them', () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data(true));
  const items = Array.from(row(w).querySelectorAll('ul.rules-lint > li'));
  assert.deepEqual(items.map((li) => li.textContent), ['shellcheck {files} on *.sh, hooks/*.sh', 'npm run lint on *.js']);
  assert.equal(row(w).querySelectorAll('input, textarea, select, [contenteditable]').length, 0, 'no field edits a command');
  assert.deepEqual(Array.from(row(w).querySelectorAll('button'), (b) => b.dataset.act), ['lint-on', 'lint-off'], 'its only buttons are On and Off');
  next(w, data(true, []));
  assert.match(row(w).textContent, /the pack sets no lint command/);
});

// Bug this guards: a record with no rules.lint (an engine before the rule) was sent a rule it refuses.
test('Rules: Lint check, unknown to the record, is not sent', () => {
  const w = boot({ tab: 'rules' });
  deliver(w, data('none'));
  assert.ok(act(rulesP(w), 'lint-on').disabled && act(rulesP(w), 'lint-off').disabled, 'an older engine is sent neither');
  assert.match(row(w).textContent, /needs a newer Conveyor/);
});
