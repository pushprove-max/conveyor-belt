// SPDX-License-Identifier: Apache-2.0
// The Rules tab says what a switch will do before it takes hold (issue 410, the Board UX audit's UX11): a Build
// choice that would skip queued issues takes a second click with the count in its button, the last change made here
// is a line of its own with Undo, the current choice is the pressed state alone, and the area labels and finding
// kinds are offered to pick from. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { clone, boot, deliver, next, settle, later, full, act, record, rulesP, ruled, CONTROL, cases, pickProject } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const sent = async (w, fn) => { fn(); await settle(); return w.posts.splice(0).map((p) => p.body); };

// Bug: a Build switch that skips queued issues took effect on one click; the warning that said so sat beside it, easy
// to miss. Now the first click arms it and its button names how many it skips; only the second sends. One that skips
// nothing still sends at once, and an armed one forgets the first click after a while.
test('Rules: a Build choice that would skip queued issues takes a second click, its button naming the count', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, full());
  const p2 = () => act(rulesP(w), 'rule-P2');
  assert.equal(p2().textContent, 'P2');
  assert.deepEqual(await sent(w, () => p2().click()), [], 'the first click sends nothing');
  assert.equal(p2().textContent, 'Turn P2 off: skip 2', 'armed, the button names the count');
  assert.equal(p2().getAttribute('aria-label'), 'Confirm: turn P2 off and skip 2 queued issues');
  assert.ok(p2().classList.contains('board-danger'));
  assert.equal(rulesP(w).querySelector('.rules-note').textContent, 'Turning P2 off would skip 2 of the 3 queued issues. Click again to turn it off.');
  assert.deepEqual(await sent(w, () => p2().click()), [{ action: 'rules', args: ['P2=off'], repo: 'sample' }], 'the second click sends');
  // The arm lapses: a later first click arms again and sends nothing.
  const fresh = boot({ tab: 'rules' });
  deliver(fresh, full());
  act(rulesP(fresh), 'rule-followups').click();
  assert.equal(act(rulesP(fresh), 'rule-followups').textContent, 'Turn Follow-ups off: skip 1');
  later(fresh);
  assert.equal(act(rulesP(fresh), 'rule-followups').textContent, 'Follow-ups', 'the arm lapsed');
  assert.deepEqual(await sent(fresh, () => act(rulesP(fresh), 'rule-followups').click()), [], 'a click after it lapsed arms again');
  // P1 skips no queued issue here: one click sends; and turning a choice back on never asks twice.
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'rule-P1').click()), [{ action: 'rules', args: ['P1=off'], repo: 'sample' }]);
  const off = full();
  off.panels.rules.data.control.rules.P2 = false;
  next(w, off);
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'rule-P2').click()), [{ action: 'rules', args: ['P2=on'], repo: 'sample' }]);
});

// Bug (issue 442): Undo skipped the second click. After P2 off was undone from the head, the head's Undo sent P2=off on
// one click, with no count. Now it asks as the switch does: the first click says what it skips, its button names the count.
test('Rules: the head\'s Undo that would turn a Build choice off and skip queued issues takes a second click', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, full());
  const p2 = () => act(rulesP(w), 'rule-P2'), undo = () => act(rulesP(w).querySelector('.rules-last'), 'undo');
  p2().click();
  assert.deepEqual(await sent(w, () => p2().click()), [{ action: 'rules', args: ['P2=off'], repo: 'sample' }]);
  assert.deepEqual(await sent(w, () => undo().click()), [{ action: 'rules', args: ['P2=on'], repo: 'sample' }], 'turning it on asks once');
  assert.deepEqual(await sent(w, () => undo().click()), [], 'the first click sends nothing');
  assert.equal(undo().textContent, 'Undo: skip 2', 'armed, the button names the count');
  assert.ok(undo().classList.contains('board-danger'));
  assert.equal(rulesP(w).querySelector('.rules-note').textContent, 'Turning P2 off would skip 2 of the 3 queued issues. Click Undo again to turn P2 off. Undo: skip 2');
  assert.deepEqual(await sent(w, () => undo().click()), [{ action: 'rules', args: ['P2=off'], repo: 'sample' }], 'the second click sends');
});

// Bug (issue 442): the Undo on the line that says a change was done sent P2=off on one click too.
test('Rules: the done line\'s Undo that would turn a Build choice off and skip queued issues takes a second click', async () => {
  const w = boot({ tab: 'rules' });
  const off = full();
  off.panels.rules.data.control.rules.P2 = false;
  deliver(w, off);
  const undo = () => act(rulesP(w).querySelector('.rules-note'), 'undo');
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'rule-P2').click()), [{ action: 'rules', args: ['P2=on'], repo: 'sample' }]);
  assert.deepEqual(await sent(w, () => undo().click()), [], 'the first click sends nothing');
  assert.equal(rulesP(w).querySelector('.rules-note').textContent, 'Turning P2 off would skip 2 of the 3 queued issues. Click Undo again to turn P2 off. Undo: skip 2');
  assert.ok(undo().classList.contains('board-danger'));
  assert.deepEqual(await sent(w, () => undo().click()), [{ action: 'rules', args: ['P2=off'], repo: 'sample' }], 'the second click sends');
});

// Bug (issue 442 review): the done line's Undo counted what it would skip in the project shown, not the one it undoes.
// With another project picked whose queue skips nothing, one click sent P2=off to the first project unasked.
test('Rules: the done line\'s Undo kept after another project is picked does not send to the first project', async () => {
  const w = boot({ tab: 'rules' });
  const d = full();
  d.panels.rules.data.control.rules.P2 = false;
  d.panels.machine.data.repos = ['sample', 'widgetshop'];
  Object.assign(d.panels.rules.data, { repos: ['sample', 'widgetshop'], others: { widgetshop: { ...clone(d.panels.rules.data), repo: 'widgetshop', queue: [] } } });
  deliver(w, d);
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'rule-P2').click()), [{ action: 'rules', args: ['P2=on'], repo: 'sample' }]);
  pickProject(w, 'widgetshop'); // the one project picker, in the machine head (issue 408)
  assert.deepEqual(await sent(w, () => act(rulesP(w).querySelector('.rules-note'), 'undo').click()), [], 'nothing is sent to sample');
  assert.equal(rulesP(w).querySelector('.rules-note').textContent, 'Not done: that Undo is for sample; pick it to undo the change there.');
});

// Bug (issue 448): an Undo that turns no Build choice off, kept after another project is picked, was sent to the first
// project; the shown project is not the one it undoes, so it is refused the same way.
test('Rules: the done line\'s Undo of a guard change kept after another project is picked is not sent', async () => {
  const w = boot({ tab: 'rules' });
  const d = full();
  d.panels.machine.data.repos = ['sample', 'widgetshop'];
  Object.assign(d.panels.rules.data, { repos: ['sample', 'widgetshop'], others: { widgetshop: { ...clone(d.panels.rules.data), repo: 'widgetshop' } } });
  deliver(w, d);
  w.reply = record({ guard: 95 });
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'guard-95').click()), [{ action: 'guard', args: ['95'], repo: 'sample' }]);
  pickProject(w, 'widgetshop');
  assert.deepEqual(await sent(w, () => act(rulesP(w).querySelector('.rules-note'), 'undo').click()), [], 'nothing is sent to sample');
  assert.equal(rulesP(w).querySelector('.rules-note').textContent, 'Not done: that Undo is for sample; pick it to undo the change there.');
});

// Bug: "Last change here" showed only once a change was made, as grey small print, with no way back. It is a line of
// its own at all times, and a setting changed here has Undo, which sends the value the record held before.
test('Rules: the last change here is always shown, with Undo that puts the setting back', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, full());
  const last = () => rulesP(w).querySelector('.rules-top .rules-last');
  assert.equal(last().textContent, 'Last change here: none yet', 'shown at rest');
  assert.equal(act(last(), 'undo'), null, 'nothing to undo');
  w.reply = record({ guard: 95 });
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'guard-95').click()), [{ action: 'guard', args: ['95'], repo: 'sample' }]);
  assert.equal(last().querySelector('.rules-last-what').textContent, 'Last change here: pause at 95%, 12:00 PM');
  assert.equal(act(last(), 'undo').getAttribute('aria-label'), 'Undo the last change here: pause at 95%');
  w.reply = record({ guard: 90 });
  assert.deepEqual(await sent(w, () => act(last(), 'undo').click()), [{ action: 'guard', args: ['90'], repo: 'sample' }], 'Undo sends the value it replaced');
  assert.equal(act(rulesP(w), 'guard-90').getAttribute('aria-pressed'), 'true');
  assert.equal(last().querySelector('.rules-last-what').textContent, 'Last change here: pause at 90%, 12:00 PM', 'the undo is the last change now');
  // Each kind of setting puts back what the record held, on a page of its own.
  const undoes = [
    ['rule-P1', { action: 'rules', args: ['P1=on'] }],
    ['area-on', { action: 'rules', args: ['area:infra=off'] }],
    ['judge-on', { action: 'judge', args: ['off'] }],
    ['start-held', { action: 'start', args: ['queue'] }],
    ['cards at once-up', { action: 'cap', args: ['off'] }],
    ['dep-guard-off', { action: 'dep-guard', args: ['on'] }],
  ];
  for (const [a, undo] of undoes) {
    const p = boot({ tab: 'rules' });
    deliver(p, full());
    assert.equal((await sent(p, () => act(rulesP(p), a).click())).length, 1, `${a} sent`);
    assert.deepEqual(await sent(p, () => act(rulesP(p).querySelector('.rules-last'), 'undo').click()), [{ ...undo, repo: 'sample' }], `undo of ${a}`);
  }
  // An unpin is undone (issue 407) by the pinned order as it was, from this line too.
  const u = boot({ tab: 'rules' });
  deliver(u, full());
  await sent(u, () => act(rulesP(u), 'unpin').click());
  assert.match(rulesP(u).querySelector('.rules-last').textContent, /unpinned #21/);
  assert.deepEqual(await sent(u, () => act(rulesP(u).querySelector('.rules-last'), 'undo').click()), [{ action: 'order', args: ['21'], repo: 'sample' }], 'undo of unpin');
  // Another project shows none of this one's last change.
  const other = full();
  other.panels.rules.data = { ...other.panels.rules.data, repo: 'widgetshop' };
  const again = boot({ tab: 'rules', store: { 'conveyor-board-rules-last': w.localStorage.getItem('conveyor-board-rules-last') } });
  deliver(again, other);
  assert.equal(rulesP(again).querySelector('.rules-last').textContent, 'Last change here: none yet', 'another project\'s change is not shown, nor undone, here');
});

// Bug: the current choice was named "(set)" in each switch's label; the pressed state says it, as any toggle's does.
test('Rules: no switch says "(set)"; the choice in force is the pressed one', () => {
  const w = boot({ tab: 'rules' });
  const d = full();
  d.panels.rules.data.control = { ...CONTROL, judgeOn: true, start: 'held', depGuard: false, rules: { ...CONTROL.rules, push: false, visible: false } };
  deliver(w, d);
  const tog = Array.from(ruled(w).querySelectorAll('.rules-tog'));
  assert.ok(tog.length > 15);
  for (const b of tog) assert.doesNotMatch(`${b.textContent} ${b.getAttribute('aria-label')}`, /\(set\)/, b.dataset.act);
  assert.doesNotMatch(ruled(w).textContent, /\(set\)/);
  const on = tog.filter((b) => b.getAttribute('aria-pressed') === 'true').map((b) => b.dataset.act);
  assert.deepEqual(on.filter((a) => /^(judge|start|dep-guard|push|visible)-/.test(a)), ['judge-on', 'start-held', 'dep-guard-off', 'push-off', 'visible-off']);
});

// Bug: Never build and the judge's always-accepted kinds were free-text boxes whose only hint was grey example text.
// Each offers the values it knows to pick from: the area labels of the open issues not already never built, and the
// finding kinds the review prompt names that are not already accepted.
test('Rules: Never build offers the open issues\' area labels, and the judge\'s kinds field the known kinds, to pick from', async () => {
  const w = boot({ tab: 'rules' });
  const d = full();
  d.panels.rules.data.control = { ...CONTROL, judgeOn: true, judgeAlways: ['security'] };
  deliver(w, d);
  const offered = (act) => { const f = act(); const l = f.getAttribute('list'); return Array.from(w.document.getElementById(l).options, (o) => o.value); };
  const area = () => act(rulesP(w), 'area-name'), kind = () => act(rulesP(w), 'judge-kind');
  assert.deepEqual(offered(area), ['area:web'], 'the area labels of the issues, area:infra left out as it is never built already');
  assert.deepEqual(offered(kind), ['data', 'bypass', 'behaviour', 'tests'], 'security is accepted already');
  // A picked value is sent as it is.
  area().value = 'area:web'; area().dispatchEvent(new w.Event('input'));
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'area-off').click()), [{ action: 'rules', args: ['area:web=off'], repo: 'sample' }]);
  kind().value = 'data'; kind().dispatchEvent(new w.Event('input'));
  assert.deepEqual(await sent(w, () => act(rulesP(w), 'judge-kind-add').click()), [{ action: 'judge', args: ['always', 'security', 'data'], repo: 'sample' }]);
});
