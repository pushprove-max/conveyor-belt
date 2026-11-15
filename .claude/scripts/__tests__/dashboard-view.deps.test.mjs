// SPDX-License-Identifier: Apache-2.0
// The dashboard page and dependencies: what each waiting card waits on, the dependency guard and Queue anyway.
// Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { clone, boot, deliver, settle, later, panel, P, CONTROL, full, bcard, inCol, act, record, rulesP, ruled, produced, nextUp, figure, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

// #24 waits on #20 (queued), #63 (on the belt, testing) and #7 (landed, its push still to come).
const WAITER = { repo: 'sample', card: null, issue: 24, title: 'Second half', url: `${P}/24`, priority: 'P2', followup: false, retried: false, waitsFor: [20, 63, 7] };
function waiting(over = {}) {
  const d = full(), r = d.panels.rules.data;
  r.waits = [clone(WAITER)];
  r.beltSteps = [{ issue: 63, step: 'tests', landed: false }, { issue: 7, step: 'push', landed: true }];
  r.open.held = r.open.held.map((x) => (x.issue === 24 ? { ...x, reasons: [{ kind: 'waits', waitsFor: [20, 63, 7] }] } : x));
  r.control = { ...r.control, ...over };
  return d;
}
const waitRows = (w) => Array.from(produced(w).querySelectorAll('.rules-wait'), (x) => [Number(x.dataset.issue), x.textContent]);

// Bug: the Rules tab said only how many cards wait ("waiting on another card"), never which, on what, nor how far
// that card had come, so cards meant to build in sequence were released together.
test('Rules: "waiting on another card" opens the list of each waiting card, the cards it waits on and where each is', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, waiting());
  assert.equal(figure(w, 'waiting'), '1');
  assert.deepEqual(waitRows(w), [], 'the list starts closed');
  const open = act(produced(w), 'waits-open');
  assert.equal(open.getAttribute('aria-expanded'), 'false');
  open.click();
  await settle();
  assert.equal(act(produced(w), 'waits-open').getAttribute('aria-expanded'), 'true');
  const rows = waitRows(w);
  assert.equal(rows.length, 1);
  assert.equal(rows[0][0], 24);
  assert.match(rows[0][1], /Second half.*waits on #20 \(queued\), #63 \(testing\), #7 \(landed\)/);
  assert.equal(act(produced(w), 'force'), null, 'the guard on: no Build anyway');
  act(produced(w), 'waits-open').click();
  await settle();
  assert.deepEqual(waitRows(w), [], 'a second click closes it');
});

// Bug: a waiting card also held by you, or also skipped by a rule, was left out of the waiting list, so what it waits
// on and where each is could not be seen; Build anyway is not offered on one, as something else still keeps it.
test('Rules: the waiting list shows a waiting card also held or skipped, with what else keeps it', async () => {
  const d = waiting({ held: [76, 24], depGuard: false }), r = d.panels.rules.data;
  r.waits.push({ ...clone(WAITER), issue: 23, title: 'Infra thing', url: `${P}/23`, waitsFor: [20] });
  r.open.held = r.open.held.map((x) => (x.issue === 23 ? { ...x, reasons: [...x.reasons, { kind: 'waits', waitsFor: [20] }] } : x));
  const w = boot({ tab: 'rules' });
  deliver(w, d);
  assert.equal(figure(w, 'waiting'), '2', 'the count matches the list it opens');
  act(produced(w), 'waits-open').click();
  await settle();
  const rows = waitRows(w);
  assert.deepEqual(rows.map((x) => x[0]), [24, 23]);
  assert.match(rows[0][1], /waits on #20 \(queued\), #63 \(testing\), #7 \(landed\)also held by you/);
  assert.match(rows[1][1], /waits on #20 \(queued\)also skipped: Conveyor never builds area:infra/);
  assert.equal(act(produced(w), 'force'), null, 'no Build anyway on a card something else keeps');
  assert.ok(!Array.from(produced(w).querySelectorAll('.rules-flow li'), (x) => x.textContent).some((t) => /Second half|Infra thing/.test(t)),
    'Next up still leaves them out');
});

// Bug: the guard off, the owner had no way to build one waiting card before its dependency lands; and a Queue anyway
// that sent at once would build a card early on one stray click. Issue 407: it was "Build anyway" (one of five words
// for queueing) and asked in a browser dialog, unlike every other guard on the page.
test('Rules: Queue anyway is drawn only with the dependency guard off, and sends force on a second click', async () => {
  const on = boot({ tab: 'rules' });
  deliver(on, waiting());
  act(produced(on), 'waits-open').click();
  await settle();
  assert.equal(act(produced(on), 'force'), null, 'the guard on: no Queue anyway');
  const w = boot({ tab: 'rules' });
  deliver(w, waiting({ depGuard: false }));
  act(produced(w), 'waits-open').click();
  await settle();
  w.confirm = () => { throw new Error('no browser dialog'); };
  assert.equal(act(produced(w), 'force').textContent, 'Queue anyway');
  assert.equal(act(produced(w), 'force').dataset.guard, 'spend');
  act(produced(w), 'force').click();
  await settle();
  assert.equal(act(produced(w), 'force').textContent, 'Click again: build #24 before #20, #63 and #7 land');
  assert.deepEqual(w.posts, [], 'the first click only asks');
  later(w);
  assert.equal(act(produced(w), 'force').textContent, 'Queue anyway', 'unanswered, it is forgotten');
  w.reply = record({ depGuard: false, forced: [24] });
  act(produced(w), 'force').click();
  act(produced(w), 'force').click();
  await settle();
  assert.deepEqual(w.posts, [{ url: 'control', body: { action: 'force', args: ['24'], repo: 'sample' } }]);
});

// Bug: the guard could not be seen or set from the Board; and a project on an older pinned engine was sent actions
// its `control` refuses.
test('Rules: the dependency guard is On or Off, and drawn disabled for an engine that does not know it', async () => {
  const w = boot({ tab: 'rules' });
  deliver(w, waiting());
  const row = ruled(w).querySelector('[data-rule="dep-guard"]');
  assert.match(row.textContent, /Dependency guard/);
  assert.deepEqual(['dep-guard-on', 'dep-guard-off'].map((a) => act(rulesP(w), a).getAttribute('aria-pressed')), ['true', 'false'], 'On, the default');
  assert.doesNotMatch(row.textContent, /needs a newer Conveyor/);
  w.reply = record({ depGuard: false });
  act(rulesP(w), 'dep-guard-off').click();
  await settle();
  assert.deepEqual(w.posts, [{ url: 'control', body: { action: 'dep-guard', args: ['off'], repo: 'sample' } }]);
  assert.equal(act(rulesP(w), 'dep-guard-off').getAttribute('aria-pressed'), 'true');

  const old = boot({ tab: 'rules' });
  const d = waiting();
  delete d.panels.rules.data.control.depGuard; delete d.panels.rules.data.control.forced;
  deliver(old, d);
  const gOn = act(rulesP(old), 'dep-guard-on'), gOff = act(rulesP(old), 'dep-guard-off');
  assert.ok(gOn.disabled && gOff.disabled, 'both choices disabled');
  assert.match(ruled(old).querySelector('[data-rule="dep-guard"]').textContent, /needs a newer Conveyor/);
  gOff.click();
  await settle();
  act(produced(old), 'waits-open').click();
  await settle();
  assert.equal(act(produced(old), 'force'), null, 'no Build anyway for an engine that does not know force');
  assert.deepEqual(old.posts, [], 'nothing sent to an older engine');
});

// Bug: a card in Held did not say it waits on another, and releasing it gave no sign that it still would not be built.
test('the Board: a waiting card in Held carries "Waits on #N"; released, it says at once it still waits', async () => {
  const w = boot({ tab: 'control' });
  const d = full(), b = d.panels.board.data;
  b.control = { ...clone(CONTROL), held: [76, 44] };
  b.held = b.held.concat([{ repo: 'sample', card: null, issue: 44, title: 'Second half', url: `${P}/44` }]);
  b.open = { count: 9, split: { queued: 3, you: 2, labelOrRule: 2, belt: 2 }, held: [
    { repo: 'sample', issue: 76, title: 'Split the PROD stack', url: `${P}/76`, priority: 'P2', labels: [], reasons: [{ kind: 'you' }] },
    { repo: 'sample', issue: 44, title: 'Second half', url: `${P}/44`, priority: 'P2', labels: [], reasons: [{ kind: 'you' }, { kind: 'waits', waitsFor: [20] }] },
  ] };
  deliver(w, d);
  assert.ok(inCol(w, 'held').includes(44));
  assert.deepEqual(Array.from(bcard(w, 44).querySelectorAll('.chip[data-reason]'), (c) => c.textContent), ['Held by you', 'Waiting on #20']);
  w.reply = record({ held: [76] });
  act(bcard(w, 44), 'release').click();
  await settle(); await settle();
  assert.deepEqual(w.posts, [{ url: 'control', body: { action: 'release', args: ['44'], repo: 'sample' } }]);
  assert.ok(inCol(w, 'held').includes(44), 'still in Held: it waits');
  assert.match(bcard(w, 44).textContent, /Released from hold\. Still waits on #20\./);
  // One that waits on nothing says nothing of the kind.
  w.reply = record({ held: [] });
  act(bcard(w, 76), 'release').click();
  await settle(); await settle();
  assert.ok(!bcard(w, 76) || !/Still waits/.test(bcard(w, 76).textContent));
});

// Bug: a card forced past its wait (`control force`, the guard off) lost what it waits on once queued: Next up drew it
// "ready", the Board's queue drew it with no tag, and the Queue panel dropped its waiting row and tagged nothing.
test('a forced card keeps its dependency tag: "forced past #N" in Next up, "Forced past #N" on the Board and in the Queue', async () => {
  const forced = { ...clone(WAITER), waitsFor: [20], forced: true };
  const d = waiting({ depGuard: false, forced: [24] }), r = d.panels.rules.data;
  r.waits = [clone(forced)];
  r.queue = [clone(forced)].concat(r.queue);
  r.open.held = r.open.held.filter((x) => x.issue !== 24);
  d.panels.board.data.queue = [clone(forced)].concat(d.panels.board.data.queue);
  d.panels.board.data.waits = [clone(forced)];
  d.panels.board.data.control = { ...d.panels.board.data.control, depGuard: false, forced: [24] };
  d.panels.queue.data.next = [clone(forced)].concat(d.panels.queue.data.next);
  d.panels.queue.data.waiting = [clone(forced)];

  const rules = boot({ tab: 'rules' });
  deliver(rules, d);
  assert.deepEqual(nextUp(rules).find(([n]) => n === 24), [24, 'forced past #20'], 'not "ready", not "waits on"');
  assert.equal(figure(rules, 'waiting'), '0', 'not counted as waiting');

  const c = boot({ tab: 'control' });
  deliver(c, d);
  assert.ok(inCol(c, 'queue').includes(24));
  const chips = Array.from(bcard(c, 24).querySelectorAll('.board-tags .chip'), (x) => x.textContent);
  assert.ok(chips.includes('Forced past #20') && !chips.some((t) => /^Waits on/.test(t)), `its tags: ${chips.join(' | ')}`);

  const q = boot();
  deliver(q, d);
  const lists = Array.from(panel(q, 'queue').querySelectorAll('.rows'), (l) => Array.from(l.children, (li) => li.textContent));
  assert.match(lists[0][0], /Second half.*Forced past #20/, 'its next row says what it was forced past');
  assert.ok(!lists.slice(1).some((l) => l.some((t) => /Second half/.test(t))), 'not listed again as waiting');
});

// Bug (issue 605): a dependency in another repository ("other/repo#600" in waitsFor and dependsOn) was drawn as
// "#other/repo#600" or as a link to this project's #600, and the Depends on… control offered a × the host refuses.
test('another repository\'s dependency is said as owner/repo#N on the Board, in Depends on… (no ×) and in the Queue', async () => {
  const d = full(), b = d.panels.board.data;
  b.open = { count: 1, split: { queued: 0, you: 0, labelOrRule: 1, belt: 0 },
    held: [{ repo: 'sample', issue: 76, title: 'Split the PROD stack', url: `${P}/76`, priority: 'P2', labels: [], reasons: [{ kind: 'waits', waitsFor: [20, 'other/repo#600'] }] }],
    issues: [{ issue: 76, title: 'Split the PROD stack', priority: 'P2', labels: [], dependsOn: [20, 'other/repo#600'] }] };
  d.panels.queue.data.waiting = [{ repo: 'sample', card: null, issue: 76, title: 'Split the PROD stack', url: `${P}/76`, waitsFor: [20, 'other/repo#600'] }];
  const w = boot({ tab: 'control' });
  deliver(w, d);
  const chip = bcard(w, 76).querySelector('.chip[data-reason="waits"]');
  assert.equal(chip.textContent, 'Waiting on #20, other/repo#600');
  assert.deepEqual(Array.from(chip.querySelectorAll('a'), (a) => a.textContent), ['#20'], 'only this project\'s issue is a link to it');
  act(bcard(w, 76), 'depends').click();
  await settle();
  assert.deepEqual(Array.from(bcard(w, 76).querySelectorAll('[data-act="dep-remove"]'), (x) => x.textContent), ['× #20']);
  assert.match(bcard(w, 76).querySelector('.board-deps').textContent, /other\/repo#600in another repository/);
  const q = boot();
  deliver(q, d);
  assert.ok(Array.from(panel(q, 'queue').querySelectorAll('.rows li'), (li) => li.textContent).some((t) => /Split the PROD stack.*Waiting on #20, other\/repo#600/.test(t)));
});

// The host's answer to depends: a line of text, not a record; ok false is its refusal.
const said = (ok, text) => ({ ok, status: ok ? 200 : 409, text: () => Promise.resolve(text), headers: { get: () => null } });

// Bug: a dependency could be set only by editing the issue on GitHub; the Board showed the wait but had no way to add
// one, and an answered add left the card looking as if nothing had changed until the next snapshot.
test('the Board: "Depends on…" on an open issue sends depends <issue> add <n>, and the card then says it waits on #<n>', async () => {
  const w = boot({ tab: 'control' });
  deliver(w, full());
  const n = inCol(w, 'queue')[0];
  assert.equal(act(bcard(w, n), 'dep-input'), null, 'the field starts closed');
  act(bcard(w, n), 'depends').click();
  await settle();
  const type = (win, text) => { const f = act(bcard(win, n), 'dep-input'); f.value = text; f.dispatchEvent(new win.Event('input')); };
  type(w, String(n));
  act(bcard(w, n), 'dep-add').click();
  await settle();
  assert.deepEqual(w.posts, [], 'a self-dependency is not sent');
  type(w, '76');
  w.reply = said(true, `conveyor: #${n} now waits on #76`);
  act(bcard(w, n), 'dep-add').click();
  await settle(); await settle();
  assert.deepEqual(w.posts, [{ url: 'control', body: { action: 'depends', args: [String(n), 'add', '76'], repo: 'sample' } }]);
  assert.match(bcard(w, n).textContent, /waits on #76/);
  assert.equal(act(bcard(w, n), 'dep-input'), null, 'the field closes once it is answered');
  // A refused add says the host's reason and claims no wait.
  const r = boot({ tab: 'control' });
  deliver(r, full());
  act(bcard(r, n), 'depends').click();
  await settle();
  type(r, '76');
  r.reply = said(false, 'conveyor: it would make a dependency cycle (#76, #20); nothing changed');
  act(bcard(r, n), 'dep-add').click();
  await settle(); await settle();
  assert.doesNotMatch(bcard(r, n).textContent, /waits on #76/);
  assert.match(panel(r, 'board').querySelector('.board-note').textContent, /Not done: .*dependency cycle/);
});

// Bug: the Rules waiting list named what each card waits on but could not take a dependency off it or add one. And
// the × came from waitsFor, which adds the open follow-ups of a dependency (#63 here) and leaves out a closed one
// (#50): the host refuses removing a number the issue's Depends on: lines do not name, and #50 could not be removed.
test('Rules: the × on a dependency in the waiting list sends depends <issue> remove <n>; Add dependency sends add', async () => {
  const d = waiting();
  d.panels.rules.data.open.issues = [{ issue: 24, title: 'Second half', priority: 'P2', labels: [], dependsOn: [7, 20, 50] }];
  const w = boot({ tab: 'rules' });
  deliver(w, d);
  act(produced(w), 'waits-open').click();
  await settle();
  const row = () => produced(w).querySelector('.rules-wait[data-issue="24"]');
  const xs = Array.from(row().querySelectorAll('[data-act="dep-remove"]'));
  assert.deepEqual(xs.map((b) => b.textContent), ['× #7', '× #20', '× #50'], 'the numbers its Depends on: lines name, not what it waits on');
  w.reply = said(true, 'conveyor: #24 no longer depends on #50');
  xs[2].click();
  await settle(); await settle();
  assert.deepEqual(w.posts, [{ url: 'control', body: { action: 'depends', args: ['24', 'remove', '50'], repo: 'sample' } }]);
  act(row(), 'depends').click();
  await settle();
  const f = act(row(), 'dep-input');
  f.value = '#21, 22'; f.dispatchEvent(new w.Event('input'));
  act(row(), 'dep-add').click();
  await settle(); await settle();
  assert.deepEqual(w.posts[1], { url: 'control', body: { action: 'depends', args: ['24', 'add', '21', '22'], repo: 'sample' } });
});

// Bug: the Board's × came from what the card waits on (waitsFor), which names the open follow-ups of a dependency and
// leaves out a closed one: each × sent a removal the host refuses, and the number the issue's Depends on: line names
// (#50 here) had no ×.
test('the Board: "Depends on…" offers a × for each number the issue\'s Depends on: lines name, and sends depends <issue> remove <n>', async () => {
  const d = full();
  d.panels.board.data.open = { count: 1, split: { queued: 0, you: 1, labelOrRule: 0, belt: 0 },
    held: [{ repo: 'sample', issue: 76, title: 'Split the PROD stack', url: `${P}/76`, priority: 'P2', labels: [], reasons: [{ kind: 'you' }, { kind: 'waits', waitsFor: [100101, 100102] }] }],
    issues: [{ issue: 76, title: 'Split the PROD stack', priority: 'P2', labels: [], dependsOn: [50] }] };
  const w = boot({ tab: 'control' });
  deliver(w, d);
  act(bcard(w, 76), 'depends').click();
  await settle();
  const xs = Array.from(bcard(w, 76).querySelectorAll('[data-act="dep-remove"]'));
  assert.deepEqual(xs.map((b) => b.textContent), ['× #50'], 'the numbers its Depends on: line names, not the follow-ups it waits on');
  w.reply = said(true, 'conveyor: #76 no longer depends on #50');
  xs[0].click();
  await settle(); await settle();
  assert.deepEqual(w.posts, [{ url: 'control', body: { action: 'depends', args: ['76', 'remove', '50'], repo: 'sample' } }]);
});
