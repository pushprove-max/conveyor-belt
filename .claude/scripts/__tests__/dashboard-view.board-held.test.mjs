// SPDX-License-Identifier: Apache-2.0
// The dashboard page's Board, on the Control tab: the host's answer against the snapshots, and every open issue in its
// column, Held with its reasons and filters, and a long column. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { T0, iso, clone, boot, deliver, next, later, settle, P, CONTROL, full, board, loopP, pushP, bcard, column, inCol, act, note, record, dragTo, OPEN, withOpen, moreText, rulesP, groupEl, rowsOf, heldMany, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

// The loop's state as the bar shows it: running, or what the host's answer set.
const loopShown = (w) => loopP(w).querySelector('.board-state').dataset.state;
const pausedAt = (t) => { const d = full(t); Object.assign(d.panels.board.data, { state: 'paused', control: { ...CONTROL, mode: 'pause' } }); return d; };

test('the Board: a snapshot collected before the host answered does not take the answer back', async () => {
  const w = boot({ tab: 'control' });
  deliver(w, full());
  w.reply = record({ mode: 'pause' });
  act(loopP(w), 'pause').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'pause', args: [], repo: 'sample' } }]);
  assert.equal(loopShown(w), 'paused');
  // A snapshot begun before the answer (the loop still running) arrives after it, however late: the answer stands.
  const older = full(T0 - 5000); older.panels.board.data.landed.pop();
  w.clock += 180000;
  next(w, older);
  assert.equal(loopShown(w), 'paused', 'the snapshot from before the answer does not erase it');
  assert.ok(act(loopP(w), 'resume'), 'so the bar offers Start, not a second Pause');
  w.reply = record({ mode: 'run' }, w.clock);
  act(loopP(w), 'resume').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'resume', args: [], repo: 'sample' } }]);
  // One begun a second before that answer, even showing another record, is still older than it.
  const before = pausedAt(w.clock - 1000 + 20000); before.panels.board.data.landed.pop();
  next(w, before);
  assert.equal(loopShown(w), 'running');
  // One begun at or after the answer is the loop as it stands, whatever it shows: a change made elsewhere rules.
  next(w, pausedAt(w.clock + 20000));
  assert.equal(loopShown(w), 'paused', 'a change made elsewhere after the answer shows');
  // The answer is gone from the overlay now, but a snapshot begun before it that arrives after still cannot bring
  // the old record back.
  const stale = full(w.clock - 5000 + 20000); stale.panels.board.data.landed.pop();
  next(w, stale);
  assert.equal(loopShown(w), 'paused', 'a snapshot older than the answer is turned away even after the overlay cleared');
  w.clock += 60000;
  next(w, full(w.clock + 20000));
  assert.equal(loopShown(w), 'running');
  // An answer that came with no time is replaced by the next snapshot.
  w.reply = record({ mode: 'pause' }, null);
  act(loopP(w), 'pause').click();
  await settle();
  assert.equal(loopShown(w), 'paused');
  w.clock += 60000;
  next(w, full(w.clock + 20000));
  assert.equal(loopShown(w), 'running', 'the snapshot\'s record rules again');
});

test('the Board: a fresh snapshot whose part equals one it turned away still settles the answer', async () => {
  const w = boot({ tab: 'control' });
  deliver(w, full());
  const at = (t) => { const d = full(t); d.panels.board.data.landed.pop(); return d; };
  w.reply = record({ mode: 'pause' });
  act(loopP(w), 'pause').click();
  await settle();
  w.posts.splice(0);
  // Pause answered; a running snapshot begun before the answer arrives, then one begun after it, its board part the
  // same (the loop was started again elsewhere). app.js does not draw an equal part again; the Board still weighs it.
  w.clock += 60000;
  next(w, at(T0 - 5000));
  assert.equal(loopShown(w), 'paused', 'the older snapshot does not take the answer back');
  next(w, at(T0 - 5000));
  assert.equal(loopShown(w), 'paused', 'nor does the same snapshot read again');
  next(w, at(w.clock + 20000));
  assert.equal(loopShown(w), 'running', 'the fresh snapshot, equal to the older one, rules');
  w.reply = record({ mode: 'pause' }, w.clock);
  act(loopP(w), 'pause').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'pause', args: [], repo: 'sample' } }]);
  // With the answer settled, a snapshot begun before it is turned away; a fresh one equal to it is then taken.
  next(w, pausedAt(w.clock + 20000));
  assert.equal(loopShown(w), 'paused');
  next(w, at(w.clock - 5000 + 20000));
  assert.equal(loopShown(w), 'paused', 'the snapshot from before the answer is turned away');
  w.clock += 60000;
  next(w, at(w.clock + 20000));
  assert.equal(loopShown(w), 'running', 'a fresh snapshot equal to the turned-away one is the loop as it stands');
});

test('the Board: cards glide to their new place, transform only; never under reduced motion', async () => {
  for (const reducedMotion of [false, true]) {
    const w = boot({ rects: true, reducedMotion, tab: 'control' });
    deliver(w, full());
    w.reply = record({ held: [76, 20] });
    act(bcard(w, 20), 'hold').click();
    await settle();
    assert.deepEqual(inCol(w, 'held'), [76, 20, 23]);
    if (reducedMotion) {
      for (const c of board(w).querySelectorAll('.bcard')) assert.equal(c.style.transform + c.style.transition, '', 'placed, not moved');
      assert.equal(board(w).querySelectorAll('.bcard.enter').length, 0);
    } else {
      assert.match(bcard(w, 20).style.transition, /^transform 260ms/, 'the card that moved glides');
      assert.equal(bcard(w, 76).style.transition, '', 'one that stayed is left alone');
      assert.match(bcard(w, 21).style.transition, /^transform 260ms/, 'the one that moved up behind it glides too');
    }
  }
});

// Issue 558: every card glided on each refresh when anything above the cards changed height, so the Board moved
// under the reader. A card's box: its column across, and down by the push test's height plus its index in the column.
test('the Board: a refresh where only the push test above the cards grows moves no card', () => {
  const w = boot({ tab: 'control' });
  w.Element.prototype.getBoundingClientRect = function () {
    const col = this.closest('.board-col'), above = 60 + 40 * this.ownerDocument.querySelectorAll('.board-push-item').length;
    if (!col || !this.classList.contains('bcard')) return { left: 0, top: 0, right: 300, bottom: 90, width: 300, height: 90 };
    const x = Array.from(col.parentNode.children).indexOf(col) * 300, y = above + Array.from(col.querySelectorAll('.bcard')).indexOf(this) * 100;
    return { left: x, top: y, right: x + 300, bottom: y + 90, width: 300, height: 90 };
  };
  deliver(w, full());
  const d = full();
  d.panels.board.data.unpushed = [{ card: 'c1-7', issue: 7, since: '2026-11-14T07:00:00Z' }, { card: 'c2-8', issue: 8, since: '2026-11-14T07:30:00Z' }];
  next(w, d);
  assert.equal(pushP(w).querySelectorAll('.board-push-item').length, 2, 'the push test grew above the cards');
  for (const c of board(w).querySelectorAll('.bcard')) assert.equal(c.style.transform + c.style.transition, '', `#${c.dataset.issue} kept its column and place: it does not glide`);
});

// ---- the Board shows every open issue ----
test('the Board: an open issue with a held-back label is in Held with that label as its reason; the head says how the open issues split', () => {
  const w = boot({ tab: 'control' });
  deliver(w, withOpen());
  // Issue 415: a rule and a standing rule of Conveyor's own are one state, Skipped by a rule, in one group.
  assert.deepEqual(inCol(w, 'held'), [76, 40, 41, 42, 23], 'grouped by reason: you, each label, the rules');
  assert.deepEqual(Array.from(column(w, 'held').querySelectorAll('.board-group'), (g) => [g.dataset.group, g.querySelector('summary').textContent]),
    [['you', 'Held by you1'], ['label:backlog', 'Held by a label: backlog2'], ['rule', 'Skipped by a rule2']]);
  assert.deepEqual(Array.from(bcard(w, 41).querySelectorAll('.chip[data-reason]'), (c) => c.textContent), ['Held by a label: backlog', 'Held by a label: ux-change'], 'an issue can carry more than one reason');
  const split = board(w).querySelector('[data-figure="split"]').textContent;
  assert.equal(split, '9 open3 queued1 held by you3 held by a label or skipped by a rule2 on the belt');
  const s = OPEN.split;
  assert.equal(s.queued + s.you + s.labelOrRule + s.belt, OPEN.count, 'the four add up to the open issues');
  assert.equal(column(w, 'held').querySelector('.board-head .panel-count').textContent, '5');
});

test('the Board: a held-back card is not queued by a drag; "Remove the label and queue it" asks once, then removes the label and releases it', async () => {
  const w = boot({ tab: 'control' });
  deliver(w, withOpen());
  dragTo(w, bcard(w, 40), column(w, 'queue'));
  dragTo(w, bcard(w, 40), bcard(w, 20));
  await settle();
  assert.deepEqual(w.posts, [], 'a drag alone does not queue it');
  assert.match(note(w), /A label holds #40 \(backlog\): use "Remove the label and queue it"/);
  const b = act(bcard(w, 40), 'unlabel');
  assert.equal(b.textContent, 'Remove the label backlog and queue it', 'it names the label');
  b.click();
  await settle();
  assert.deepEqual(w.posts, [], 'the first click only asks');
  assert.equal(act(bcard(w, 40), 'unlabel').textContent, 'Click again: remove the label backlog from #40 on GitHub');
  w.reply = record({ held: [76] });
  act(bcard(w, 40), 'unlabel').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'unlabel', args: ['40', 'backlog'], repo: 'sample' } }]);
  assert.match(bcard(w, 40).textContent, /Label removed: the issue goes into the queue in about a minute/);
  assert.ok(bcard(w, 40).classList.contains('is-pending'), 'greyed in place until the loop takes it');
  // Two labels: both are removed by the one action.
  w.reply = null;
  act(bcard(w, 41), 'unlabel').click();
  act(bcard(w, 41), 'unlabel').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'unlabel', args: ['41', 'backlog', 'ux-change'], repo: 'sample' } }]);
  // The first click is forgotten after a while.
  act(bcard(w, 76), 'release');
  const fresh = boot({ tab: 'control' });
  deliver(fresh, withOpen());
  act(bcard(fresh, 40), 'unlabel').click();
  later(fresh);
  assert.equal(act(bcard(fresh, 40), 'unlabel').textContent, 'Remove the label backlog and queue it');
});

test('the Board: a card excluded by a standing rule with no label says so and is not queued from the Board; one held only by you is released', async () => {
  const w = boot({ tab: 'control' });
  deliver(w, withOpen());
  const card42 = bcard(w, 42);
  assert.equal(act(card42, 'unlabel'), null);
  assert.equal(act(card42, 'release'), null);
  assert.match(card42.textContent, /Skipped by a rule of Conveyor's own \(area:prism verification-integrity issues are never built by the loop\): you cannot queue it from the Board\./);
  dragTo(w, card42, column(w, 'queue'));
  await settle();
  assert.deepEqual(w.posts, []);
  assert.match(note(w), /A rule of Conveyor's own skips #42/);
  dragTo(w, bcard(w, 76), column(w, 'queue'));
  await settle();
  assert.deepEqual(w.posts, [{ url: 'control', body: { action: 'release', args: ['76'], repo: 'sample' } }], 'held only by you: released as before');
});

// Issue 453: an issue someone outside the project opened starts held; the Board said only "Held by you", so the
// owner could not tell it from one they held themselves. Its chip says why, and Queue releases it as before.
test('the Board: an issue opened by someone outside the project says so in Held, and Queue releases it', async () => {
  const held = clone(OPEN.held); held[0].reasons = [{ kind: 'you', outside: true }];
  const w = boot({ tab: 'control' });
  deliver(w, withOpen({ held }));
  assert.deepEqual(Array.from(bcard(w, 76).querySelectorAll('.chip[data-reason]'), (c) => c.textContent),
    ['Opened by someone outside the project: release it to build it']);
  act(bcard(w, 76), 'release').click();
  await settle();
  assert.deepEqual(w.posts, [{ url: 'control', body: { action: 'release', args: ['76'], repo: 'sample' } }]);
});

// Issue 1674: a split whose slices are cards with no GitHub issue holds its umbrella, but the Board called that hold
// "Held by you" and offered Queue, which would clear the hold and build nothing. The chip names the split's hold, the
// slice cards not landed yet and a shut one as shut, and the card has no Queue. It was also grouped under "Held by
// you", the group of its first reason: the split's hold (split: true) goes with its closed card. Once each slice landed,
// the chip said "waits for" and no card until the loop's next turn closed it: it says each slice landed.
test('the Board: the umbrella of a split into cards with no GitHub issue is held by the split, names its slice cards, and has no Queue', () => {
  const held = clone(OPEN.held);
  held[0].reasons = [{ kind: 'you', split: true }, { kind: 'card', step: 'closed', card: 'c76' }];
  held[0].sliceCards = [{ card: 'c20261124T230045-sample-0', state: 'landed' }, { card: 'c20261124T230046-sample-0', state: 'shut' }, { card: 'c20261124T230047-sample-0', state: 'waiting' }];
  const w = boot({ tab: 'control' });
  deliver(w, withOpen({ held }));
  assert.equal(bcard(w, 76).querySelector('.chip[data-reason="you"]').textContent,
    'Held as the umbrella of a split: waits for c20261124T230046-sample-0 (shut), c20261124T230047-sample-0');
  assert.equal(act(bcard(w, 76), 'release'), null, 'a split umbrella offers no Queue');
  assert.equal(bcard(w, 76).closest('.board-group').dataset.group, 'card', 'a split umbrella is not in the group Held by you');
  held[0].sliceCards.forEach((c) => { c.state = 'landed'; });
  next(w, withOpen({ held }));
  assert.equal(bcard(w, 76).querySelector('.chip[data-reason="you"]').textContent,
    'Held as the umbrella of a split: each slice landed; the loop closes it at its next turn');
});

test('the Board: an issue held only by an issue it waits on is in Held, counted there, and can still be held by you', async () => {
  const wait = { repo: 'sample', issue: 44, title: 'Second half', url: `${P}/44`, priority: 'P2', labels: [], reasons: [{ kind: 'waits', waitsFor: [20] }] };
  const w = boot({ tab: 'control' });
  deliver(w, withOpen({ count: 10, split: { ...OPEN.split, labelOrRule: 4 }, held: clone(OPEN.held).concat([wait]) }));
  assert.ok(inCol(w, 'held').includes(44) && !inCol(w, 'queue').includes(44), 'in Held, not in the queue');
  assert.equal(board(w).querySelector('[data-figure="split"]').textContent, '10 open3 queued1 held by you4 held by a label or skipped by a rule2 on the belt');
  assert.deepEqual(Array.from(bcard(w, 44).querySelectorAll('.chip[data-reason]'), (c) => c.textContent), ['Waiting on #20']);
  // A drag to the queue names what holds it, with a space after the colon (a text rewrite once lost it: "held:Waiting").
  dragTo(w, bcard(w, 44), column(w, 'queue'));
  await settle();
  assert.equal(note(w), 'Other holds also keep #44 held: Waiting on #20.');
  act(bcard(w, 44), 'hold').click();
  await settle();
  assert.deepEqual(w.posts, [{ url: 'control', body: { action: 'hold', args: ['44'], repo: 'sample' } }]);
});

// Issue 409 (UX20): Held had a second set of filters of its own beside the row over every column, ten view controls on
// one screen. The one row filters Held too; Held has none of its own.
test('the Board: the one filter row filters Held by text, label and priority; a group opens and closes, and a long one starts closed', () => {
  const many = Array.from({ length: 30 }, (_, i) => ({ repo: 'sample', issue: 500 + i, title: `Dormant ${i}`, url: null, priority: i % 2 ? 'P2' : 'P3', labels: ['dormant'], reasons: [{ kind: 'label', label: 'dormant' }] }));
  const w = boot({ tab: 'control' });
  deliver(w, withOpen({ held: OPEN.held.concat(many) }));
  const group = (k) => column(w, 'held').querySelector(`.board-group[data-group="${k}"]`);
  assert.equal(group('label:dormant').open, false, '30 cards start closed, so they do not flood the page');
  assert.equal(group('label:backlog').open, true, 'a short group starts open');
  assert.equal(group('label:dormant').querySelector('summary .panel-count').textContent, '30');
  group('label:dormant').open = true;
  group('label:dormant').dispatchEvent(new w.Event('toggle'));
  next(w, withOpen({ held: OPEN.held.concat(many.slice(1)) }));
  assert.equal(group('label:dormant').open, true, 'a group the owner opened stays open through a refresh');
  assert.equal(column(w, 'held').querySelector('input, select'), null, 'Held has no filter of its own');
  const text = (win, v) => { const el = board(win).querySelector('.board-viewbar [data-filter="text"]'); el.value = v; el.dispatchEvent(new win.Event('input')); };
  text(w, 'Dormant 1');
  assert.deepEqual(inCol(w, 'held'), [501, 510, 511, 512, 513, 514, 515, 516, 517, 518, 519]);
  assert.equal(group('label:dormant').querySelector('summary .panel-count').textContent, '11 of 29', 'the count says how many match');
  text(w, '#42');
  assert.deepEqual(inCol(w, 'held'), [42]);
  text(w, 'nothing like it');
  assert.match(column(w, 'held').textContent, /No held card matches the filter · Clear/);
  act(column(w, 'held'), 'filter-clear').click();
  assert.equal(inCol(w, 'held').length, 34, 'Clear shows every held card again');
  assert.equal(board(w).querySelector('.board-viewbar [data-filter="text"]').value, '', 'and empties the text');
  // The row's label and priority, as the address keeps them.
  const l = boot({ query: '?tab=control&blabel=backlog' });
  deliver(l, withOpen({ held: OPEN.held.concat(many) }));
  assert.deepEqual(inCol(l, 'held'), [40, 41]);
  const p = boot({ query: '?tab=control&blabel=backlog&bprio=P1' });
  deliver(p, withOpen({ held: OPEN.held.concat(many) }));
  assert.deepEqual(inCol(p, 'held'), [41]);
});

// Review finding: the cards of a closed Held group have no box, yet were counted as rows shown, so a Board cut to one
// row could clip above every card while it claimed "1 of N".
test('the Board: the cards of a closed Held group are not counted as its rows', () => {
  const many = Array.from({ length: 30 }, (_, i) => ({ repo: 'sample', issue: 500 + i, title: `Dormant ${i}`, url: null, priority: 'P3', labels: ['dormant'], reasons: [{ kind: 'label', label: 'dormant' }] }));
  const w = boot({ tab: 'control' });
  deliver(w, withOpen({ held: OPEN.held.concat(many) }));
  const group = column(w, 'held').querySelector('.board-group[data-group="label:dormant"]');
  assert.equal(group.open, false);
  const all = board(w).querySelectorAll('.bcard').length;
  assert.equal(Number(board(w).dataset.rows), all - 30, 'the 30 closed cards are not rows shown');
  group.open = true;
  group.dispatchEvent(new w.Event('toggle'));
  assert.equal(Number(board(w).dataset.rows), all, 'opened, they are');
});

// ---- a long column: the Board is the one exception to the five-row lists ----
// A column shows 100, then 100 more, then all; its count is every card throughout.
const queueOfBoard = (k) => {
  const d = full();
  d.panels.board.data.queue = Array.from({ length: k }, (_, i) => ({ repo: 'example', card: null, issue: 1000 + i, title: `Queued ${i}`, url: `${P}/${1000 + i}`, priority: 'P2', followup: false, retried: false }));
  return d;
};
const colCount = (w, k) => column(w, k).querySelector('.board-head .panel-count').textContent;

test('the Board: a column of 30 shows 30; one of 279 shows 100, then 200, then all, with its count 279 throughout', () => {
  const w = boot({ tab: 'control' });
  deliver(w, queueOfBoard(30));
  assert.equal(inCol(w, 'queue').length, 30);
  assert.deepEqual(moreText(column(w, 'queue')), [], 'no control under 100');
  const many = queueOfBoard(279);
  next(w, many);
  assert.equal(inCol(w, 'queue').length, 100);
  assert.deepEqual(inCol(w, 'queue').slice(0, 3), [1000, 1001, 1002], 'in pick order');
  assert.equal(colCount(w, 'queue'), '279');
  assert.deepEqual(moreText(column(w, 'queue')), ['Show 100 more', 'Show all (279)']);
  act(column(w, 'queue'), 'list-more').click();
  assert.equal(inCol(w, 'queue').length, 200);
  assert.equal(colCount(w, 'queue'), '279');
  assert.deepEqual(moreText(column(w, 'queue')), ['Show 100 more', 'Show all (279)'], 'the wording stays on the last page');
  // A new snapshot keeps the choice.
  const again = clone(many);
  again.panels.board.data.queue[0].title = 'Queued, renamed';
  next(w, again);
  assert.equal(inCol(w, 'queue').length, 200, 'the choice survives a redraw');
  act(column(w, 'queue'), 'list-all').click();
  assert.equal(inCol(w, 'queue').length, 279);
  assert.equal(colCount(w, 'queue'), '279');
  assert.deepEqual(moreText(column(w, 'queue')), []);
});

test('the Board: the Held filter searches every held issue, not only the 100 shown', () => {
  const many = Array.from({ length: 275 }, (_, i) => ({ repo: 'example', issue: 1000 + i, title: `Dormant ${i}`, url: null, priority: 'P3', labels: ['dormant'], reasons: [{ kind: 'label', label: 'dormant' }] }));
  const w = boot({ tab: 'control' });
  deliver(w, withOpen({ held: OPEN.held.concat(many) }));
  const total = colCount(w, 'held');
  assert.ok(Number(total) > 275, `every held issue is counted: ${total}`);
  assert.equal(inCol(w, 'held').length, 100);
  assert.equal(bcard(w, 1250), null, '#1250 is past the first 100');
  const text = board(w).querySelector('.board-viewbar [data-filter="text"]');
  text.value = '1250'; text.dispatchEvent(new w.Event('input'));
  assert.deepEqual(inCol(w, 'held'), [1250]);
  assert.equal(colCount(w, 'held'), `1 of ${total}`, 'the count still names every held issue, and how many match');
});

// A page shown while a change is out is as locked as the rest: its cards cannot send a second change.
test('the Board and Rules: a page shown while a change is out has its controls off', async () => {
  const many = Array.from({ length: 275 }, (_, i) => ({ repo: 'example', issue: 1000 + i, title: `Dormant ${i}`, url: null, priority: 'P3', labels: ['dormant'], reasons: [{ kind: 'label', label: 'dormant' }] }));
  const d = withOpen({ held: OPEN.held.concat(many) });
  d.panels.board.data.queue = queueOfBoard(279).panels.board.data.queue;
  const w = boot({ tab: 'control' });
  deliver(w, d);
  w.reply = { ok: true, status: 200, text: () => new Promise(() => {}) };
  act(loopP(w), 'pause').click();
  await settle();
  for (const k of ['queue', 'held']) {
    act(column(w, k), 'list-more').click();
    const on = Array.from(column(w, k).querySelectorAll('.bcard button')).filter((b) => !b.disabled);
    assert.equal(on.length, 0, `${k}: no card control is on after Show 100 more while the change is out`);
  }
  const r = boot({ tab: 'rules' });
  deliver(r, heldMany());
  groupEl(r, 'web').querySelector('[data-act="group"]').click();
  r.reply = { ok: true, status: 200, text: () => new Promise(() => {}) };
  act(rulesP(r), 'rule-P0').click();
  await settle();
  act(groupEl(r, 'web'), 'list-more').click();
  assert.ok(rowsOf(groupEl(r, 'web')).length > 5);
  const on = Array.from(groupEl(r, 'web').querySelectorAll('.rules-held-row button, .rules-held-row input, .rules-held-row select')).filter((b) => !b.disabled && b.dataset.act !== 'held-link');
  assert.deepEqual(on.map((b) => b.dataset.act), [], 'no held-row control is on after Show 5 more while the change is out');
});

// Bug (#320): a card whose test run had ended and whose live record said fix was shown in Building as "testing", timed
// from the build's end. The card reads the step the snapshot names (the live record's: snapshot.test.sh t_snapfixlive)
// and times it from that step's start; a test run says how far it has got (its files and tests reach the Board from
// the track: dashboard-cards.test.sh, "a card in Building carries its test run's files and tests from its track").
test("Building shows a fix after failed tests as fixing, timed from the fix's start, and a test run's progress", () => {
  const w = boot({ tab: 'control' });
  const data = full();
  Object.assign(data.panels.board.data.building[0], { step: 'fix', stepAt: iso(T0 - 2 * 60000), files: { run: 6, of: 6 }, tests: null });
  deliver(w, data);
  const meta = () => bcard(w, 5).querySelector('.row-meta');
  assert.equal(meta().firstChild.textContent, 'fixing', 'a fix is no test run, and shows no test files');
  assert.equal(meta().querySelector('time.since').dateTime, iso(T0 - 2 * 60000), "its time counts from the fix's own start");
  const testing = clone(data);
  Object.assign(testing.panels.board.data.building[0], { step: 'tests', stepAt: iso(T0 - 60000), files: { run: 4, of: 6 } });
  next(w, testing);
  assert.equal(meta().firstChild.textContent, 'testing, 4 of 6 test files');
  // Bug (issue 1430): a run of one test file at a time said its running file's cases, "25 of 25 tests", as if the run
  // were done; it says the file that runs and which of how many, as Belt 3D does.
  const one = clone(testing);
  Object.assign(one.panels.board.data.building[0], { files: { run: 19, of: 50, now: { file: 'conveyor/tests/b.test.sh', at: iso(T0 - 60000) } }, tests: { done: 25, of: 25, failed: 0 } });
  next(w, one);
  assert.equal(meta().firstChild.textContent, 'testing, file 20 of 50: conveyor/tests/b.test.sh');
});
