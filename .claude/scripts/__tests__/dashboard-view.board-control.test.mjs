// SPDX-License-Identifier: Apache-2.0
// The dashboard page's Board, on the Control tab: the loop steered from the page, one POST control a change. The
// board-held file holds the rest of what was dashboard-view.board.test.mjs, split so the runner runs the two side by
// side. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { T0, iso, clone, boot, state, deliver, next, tick, later, settle, key, P, CONTROL, full, tabBtn, panel, board, loopP, pushP, bcard, column, inCol, act, note, record, dragTo, ruled, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

// A card whose step the engine ended for making no progress must say so, or the owner cannot tell a card that ran
// twice from one that ran once.
test("the Board's card shows how many times the engine ended a stalled step of it, and nothing when none did", () => {
  const w = boot({ tab: 'control' });
  const data = full();
  data.panels.board.data.building[0].stalls = 1;
  data.panels.board.data.blocked[0].stalls = 2;
  deliver(w, data);
  assert.equal(bcard(w, 5).querySelector('.board-stalls').textContent, 'Stalled once: ended for no progress');
  assert.equal(bcard(w, 13).querySelector('.board-stalls').textContent, 'Stalled 2 times: ended for no progress');
  assert.equal(bcard(w, 63).querySelector('.board-stalls'), null, 'a card with no stall shows none');
});

// #305. A fully met check showed only "Done when: 2 of 2 met", so the owner could not read what each item's evidence
// was or whether the reviewer checked it. Bugs: the line does not open to each item with its text, the builder's
// evidence and the reviewer's answer, each saying who gave it; the items are read before the line is opened (or carried
// in the snapshot) instead of on demand; a redraw closes the open line or reads the items again.
test("the Board's Done-when line opens to each item, its evidence and who gave it, read from the server when opened", async () => {
  const w = boot({ tab: 'control' });
  const data = full();
  data.panels.board.data.landed[0].doneWhen = { items: 2, met: 2, failed: [] };
  w.donewhenReply = { ok: true, status: 200, json: () => Promise.resolve({ card: 'c5-7', items: [
    { n: 1, text: 'the first thing', builder: 'D1 met: lib/t.test.sh case one succeeds', reviewer: 'holds' },
    { n: 2, text: 'the second thing', builder: 'D2 met: a.txt:2 holds it', reviewer: null }] }) };
  deliver(w, data);
  const det = () => bcard(w, 7).querySelector('details.board-donewhen');
  assert.equal(det().querySelector('summary').textContent, 'Done when: 2 of 2 met');
  assert.equal(w.donewhenAsks, undefined, 'nothing is read before the line is opened');
  det().querySelector('summary').focus();
  det().open = true; det().dispatchEvent(new w.Event('toggle'));
  assert.equal(det().querySelector('.board-from').textContent, 'Reading the items…');
  assert.equal(w.document.activeElement, det().querySelector('summary'), 'opening the line by the keyboard keeps the focus on its summary');
  await settle();
  assert.deepEqual(w.donewhenAsks, ['donewhen?repo=sample&card=c5-7'], "the card's own items are asked for, once");
  const items = () => Array.from(det().querySelectorAll('.board-donewhen-items > li'), (li) =>
    [li.querySelector('.board-donewhen-item').textContent, ...Array.from(li.querySelectorAll('.board-donewhen-said > li'), (x) => x.textContent)]);
  const want = [['D1: the first thing', 'Builder: D1 met: lib/t.test.sh case one succeeds', 'Reviewer: the evidence holds'],
    ['D2: the second thing', 'Builder: D2 met: a.txt:2 holds it']];
  assert.deepEqual(items(), want, 'each item: its text, the builder line, and the reviewer line where there is one');
  next(w, data);
  await settle();
  assert.ok(det().open, 'a redraw keeps the line open');
  assert.deepEqual(items(), want, 'and its items');
  assert.equal(w.donewhenAsks.length, 1, 'a redraw of the same check reads nothing again');
  // A review's answer leaves the check's count as it was: the line opened again reads the items again.
  det().open = false; det().dispatchEvent(new w.Event('toggle'));
  w.donewhenReply = { ok: true, status: 200, json: () => Promise.resolve({ card: 'c5-7', items: [
    { n: 1, text: 'the first thing', builder: 'D1 met: lib/t.test.sh case one succeeds', reviewer: '[P1] D1 has no such case' }] }) };
  det().open = true; det().dispatchEvent(new w.Event('toggle'));
  await settle();
  assert.equal(w.donewhenAsks.length, 2, 'the line opened again is read again');
  assert.deepEqual(items(), [['D1: the first thing', 'Builder: D1 met: lib/t.test.sh case one succeeds', 'Reviewer: [P1] D1 has no such case']]);
  // While it is open, a move of the card with the same count reads it again too: its step, the step's start, its time.
  let asks = 2;
  for (const [k, v] of [['step', 'push'], ['stepAt', iso(T0 + 30000)], ['time', iso(T0 + 60000)]]) {
    data.panels.board.data.landed[0][k] = v;
    next(w, data);
    await settle();
    asks += 1;
    assert.equal(w.donewhenAsks.length, asks, `an open line of a card whose ${k} moved is read again`);
    next(w, data);
    await settle();
    assert.equal(w.donewhenAsks.length, asks, `the same ${k} reads nothing again`);
  }
});

// Bugs: a card in Needs you and in Landed today at once (its pre-push check failed after it landed) shows two
// stamps; one shared entry made each redraw read the other stamp again, without end, and the focus on the Landed
// today summary went to the same card in Needs you after the first redraw.
test("the Board's Done-when line of a card in two columns reads each stamp once, and keeps the focus in its column", async () => {
  const w = boot({ tab: 'control' });
  const data = full();
  data.panels.board.data.landed[0].doneWhen = { items: 2, met: 2, failed: [] };
  data.panels.board.data.blocked.push({ repo: 'sample', card: 'c5-7', issue: 7, title: 'Landed one', url: `${P}/7`, reason: 'the pre-push check failed',
    since: iso(T0), step: 'push', stepAt: iso(T0), doneWhen: { items: 2, met: 1, failed: ['D2 not met: no case'] } });
  w.donewhenReply = { ok: true, status: 200, json: () => Promise.resolve({ card: 'c5-7', items: [{ n: 1, text: 'the first thing', builder: 'D1 met: a.txt:1', reviewer: null }] }) };
  deliver(w, data);
  const det = (k) => column(w, k).querySelector('.bcard[data-issue="7"] details.board-donewhen');
  det('landed').querySelector('summary').focus();
  det('landed').open = true; det('landed').dispatchEvent(new w.Event('toggle'));
  for (let i = 0; i < 5; i += 1) await settle();
  assert.ok(det('needs').open, 'the line is open by card: the Needs you line of the same card opens too');
  assert.equal(w.donewhenAsks.length, 2, 'each stamp is read once');
  assert.equal(w.document.activeElement, det('landed').querySelector('summary'), 'the focus stays on the Landed today summary');
  next(w, data);
  for (let i = 0; i < 5; i += 1) await settle();
  assert.equal(w.donewhenAsks.length, 2, 'a redraw reads neither stamp again');
  assert.ok(det('landed').querySelector('.board-donewhen-items') && det('needs').querySelector('.board-donewhen-items'), 'each line shows its items');
});

// Bug: the open line was kept by column and card, so a card that moved from Review to Building for its tests drew its
// line shut and never read the reviewer's answer.
test("the Board's open Done-when line stays open when its card moves to another column, and reads the reviewer's answer", async () => {
  const w = boot({ tab: 'control' });
  const data = full(), b = data.panels.board.data;
  b.review[0].doneWhen = { items: 1, met: 1, failed: [] };
  w.donewhenReply = { ok: true, status: 200, json: () => Promise.resolve({ card: 'c3-63', items: [{ n: 1, text: 'the thing', builder: 'D1 met: a.txt:1', reviewer: null }] }) };
  deliver(w, data);
  const det = () => bcard(w, 63).querySelector('details.board-donewhen');
  det().open = true; det().dispatchEvent(new w.Event('toggle'));
  for (let i = 0; i < 5; i += 1) await settle();
  assert.equal(w.donewhenAsks.length, 1);
  w.donewhenReply = { ok: true, status: 200, json: () => Promise.resolve({ card: 'c3-63', items: [{ n: 1, text: 'the thing', builder: 'D1 met: a.txt:1', reviewer: 'holds' }] }) };
  b.building.push({ ...b.review.shift(), step: 'tests', stepAt: iso(T0) });
  next(w, data);
  for (let i = 0; i < 5; i += 1) await settle();
  assert.equal(bcard(w, 63).dataset.col, 'building');
  assert.ok(det().open, 'the line is still open in Building');
  assert.equal(w.donewhenAsks.length, 2, 'the moved card is read again');
  assert.deepEqual(Array.from(det().querySelectorAll('.board-donewhen-said > li'), (x) => x.textContent), ['Builder: D1 met: a.txt:1', 'Reviewer: the evidence holds']);
});

test('the Board: each column with its cards, each one empty, and the queue when GitHub did not list the issues', () => {
  const w = boot({ tab: 'control' });
  const data = full();
  deliver(w, data);
  assert.deepEqual(Array.from(board(w).querySelectorAll('.board-head'), (x) => x.firstChild.textContent), ['Held', 'Queue', 'Building', 'Review', 'Needs you', 'Landed today']);
  // The rule-skipped #23 is not queued: it is in Held, with its rule.
  assert.deepEqual(['held', 'queue', 'building', 'review', 'needs', 'landed'].map((k) => inCol(w, k)), [[76, 23], [20, 21, 22], [5], [63], [12, 13], [7, 8]]);
  assert.deepEqual(Array.from(board(w).querySelectorAll('.board-col > .board-head .panel-count'), (x) => x.textContent), ['2', '3', '1', '1', '2', '2']);
  assert.equal(bcard(w, 76).getAttribute('draggable'), 'true');
  assert.equal(bcard(w, 20).getAttribute('draggable'), 'true');
  for (const n of [5, 63, 12, 7]) assert.equal(bcard(w, n).getAttribute('draggable'), null, `#${n} is not the loop's to reorder`);
  // Issue 407: the Needs you column carries no buttons of its own (it had a plain Yes and No and Retry alone, beside the
  // panel's Approve, Approve with this condition, Decline, Retry and Close): each card links into the Needs you panel.
  // Its Settings and Pick for me (issue 387) are no answer: they set the seats its Retry builds on.
  for (const n of [12, 13]) {
    assert.deepEqual(Array.from(bcard(w, n).querySelectorAll('button'), (b) => b.closest('.board-seats') ? null : b.textContent).filter(Boolean), [], `#${n} in the column has no answer button`);
    assert.equal(act(bcard(w, n), 'needs-open').getAttribute('href'), 'index.html?tab=overview#panel-needs', `#${n} links into Needs you`);
  }
  assert.equal(act(bcard(w, 12), 'needs-open').textContent, 'Answer it in Needs you');
  assert.equal(act(bcard(w, 13), 'needs-open').textContent, 'Retry or close it in Needs you');
  const none = clone(data);
  Object.assign(none.panels.board.data, { held: [], queue: [], skipped: [], building: [], review: [], waiting: [], blocked: [], landed: [], today: { landed: 0, usd: 0 } });
  next(w, none);
  assert.equal(state(w, 'board'), 'ready', 'a board with no card is still the loop to steer');
  assert.deepEqual(Array.from(board(w).querySelectorAll('.board-empty'), (x) => x.textContent),
    ['Drag a card here to hold it.', 'Nothing queued, and nothing holds an issue: each open issue is on the belt, or Conveyor built it.', 'Conveyor builds no card now.', 'Nothing is in review.', 'Nothing needs you.', 'No card landed today.']);
  assert.deepEqual(Array.from(board(w).querySelectorAll('.board-head .panel-count'), (x) => x.textContent), ['0', '0', '0', '0', '0', '0']);
  assert.ok(loopP(w).textContent.includes('0 landed') && act(loopP(w), 'pause'), 'the bar stays');
  const unlisted = clone(data);
  Object.assign(unlisted.panels.board.data, { held: null, queue: null, skipped: null, issuesError: 'GitHub did not list the open issues on buildhost.' });
  next(w, unlisted);
  for (const k of ['held', 'queue']) {
    assert.equal(column(w, k).querySelector('.warn-note').textContent, 'GitHub did not list the open issues on buildhost.', `${k} says why it is not listed`);
    assert.equal(column(w, k).querySelector('.board-empty'), null, `${k} is never shown as empty`);
  }
  assert.deepEqual(inCol(w, 'review'), [63], 'the other columns still draw');
});

// A long check run holds the loop paused: without its tile the Board looks as if nothing runs.
test('the Board: a check run shows its counts, failed and running lanes, every lane five at a time, and the loop paused for it', () => {
  const w = boot({ tab: 'control' });
  const data = full();
  const lane = (name, st, more = {}) => ({ name, state: st, started: null, sec: null, ...more });
  const lanes = [lane('p0', 'passed', { sec: 60 }), lane('p1', 'passed', { sec: 60 }), lane('p2', 'passed', { sec: 60 }), lane('broken-0', 'failed', { sec: 120 }),
    lane('busy-0', 'running', { started: iso(T0 - 90000) }), lane('busy-1', 'running', { started: iso(T0 - 30000) }),
    lane('q0', 'queued'), lane('q1', 'queued'), lane('q2', 'queued'), lane('q3', 'queued')];
  const run = { repo: 'sample', name: 'nightly', sha: '0123456789ab', started: iso(T0 - 600000), ended: null, result: null, lanes,
    counts: { passed: 3, failed: 1, running: 2, queued: 4, reused: 0 }, done: 4, all: 10, leftSec: 225 };
  Object.assign(data.panels.board.data, { state: 'paused', control: { ...clone(CONTROL), mode: 'pause' }, checkRuns: [run] });
  deliver(w, data);
  const tile = () => pushP(w).querySelector('[data-figure="checkrun"]');
  const t = tile().textContent;
  for (const s of ['nightly', '0123456', '10 min', '4/10 lanes', '~3 min left', '3 passed', '1 failed', '2 running', '4 queued', 'Failed: broken-0', 'Running: busy-0 (1 min), busy-1 (30 s)']) {
    assert.ok(t.includes(s), `the tile says ${s}: ${t}`);
  }
  assert.ok(!t.includes('0123456789ab'), 'the commit is short');
  assert.equal(tile().querySelector('.meter-fill').style.transform, 'scaleX(0.4)', 'the bar is the lanes done of all');
  assert.match(loopP(w).querySelector('.board-state').textContent, /Paused for nightly/);
  // The same snapshot a minute on: the run's time and its running lanes' times count on.
  tick(w, 60000);
  next(w, clone(data));
  for (const s of ['11 min', 'Running: busy-0 (2 min), busy-1 (1 min)']) assert.ok(tile().textContent.includes(s), `a minute on, the tile says ${s}: ${tile().textContent}`);
  const items = () => tile().querySelectorAll('.board-check-list li').length;
  assert.equal(items(), 5, 'every lane, five at first');
  act(tile(), 'lanes-more').click();
  assert.equal(items(), 10, 'Show more shows the rest');
  assert.equal(act(tile(), 'lanes-more'), null, 'no Show more once every lane is shown');
  // Fewer than a quarter done: the host gives no estimate, and none is drawn.
  next(w, Object.assign(clone(data), { panels: { ...clone(data.panels), board: { error: null, data: { ...clone(data.panels.board.data), checkRuns: [{ ...run, done: 2, leftSec: null }] } } } }));
  assert.ok(!tile().textContent.includes('left'), 'no time left without an estimate');
  const bad = clone(data); bad.panels.board.data.checkRuns = [{ repo: 'sample', error: 'check run: progress unreadable: jq: parse error' }];
  next(w, bad);
  assert.ok(tile().textContent.includes('check run: progress unreadable: jq: parse error'), 'an unreadable run is said');
  assert.deepEqual(inCol(w, 'review'), [63], 'the rest of the Board still draws');
  assert.match(loopP(w).querySelector('.board-state .chip').textContent, /Paused$/,'paused, and not for a run it cannot read');
  // A record the Board does not steer: its run is drawn, named by its repo, and the loop is not paused for it.
  const other = clone(data); other.panels.board.data.checkRuns = [{ ...run, repo: 'widgetshop' }];
  next(w, other);
  assert.ok(tile().textContent.includes('Check run, widgetshop'), `the run of another record names it: ${tile().textContent}`);
  assert.match(loopP(w).querySelector('.board-state .chip').textContent, /Paused$/,'paused, and not for another record\'s run');
  // No record steered: the Board says so, and another record's run is still drawn, its lanes still five at a time.
  const unsteered = clone(data); unsteered.panels.board = { error: null, data: { repo: null, checkRuns: [{ ...run, repo: 'widgetshop' }] } };
  next(w, unsteered);
  assert.match(board(w).textContent, /Nothing to steer here/);
  assert.ok(tile().textContent.includes('Check run, widgetshop'), `the run with no record steered: ${board(w).textContent}`);
  act(tile(), 'lanes-more').click();
  assert.equal(items(), 10, 'Show more shows the rest with no record steered');
  const none = clone(data); delete none.panels.board.data.checkRuns;
  next(w, none);
  assert.equal(tile(), null, 'a part without a check run draws no tile');
});

test('the Board: a card dragged between Held and Queue, or onto a queued card, sends that one change', async () => {
  const w = boot({ tab: 'control' });
  deliver(w, full());
  assert.equal(dragTo(w, bcard(w, 21), column(w, 'held')), true, 'Held takes a queued card');
  await settle();
  assert.deepEqual(w.posts.pop(), { url: 'control', body: { action: 'hold', args: ['21'], repo: 'sample' } });
  dragTo(w, bcard(w, 22), bcard(w, 20));
  await settle();
  assert.deepEqual(w.posts.pop(), { url: 'control', body: { action: 'order', args: ['22'], repo: 'sample' } }, 'dropped on #20, #22 goes first');
  // Released onto a queued card: put before it while still held, then released, so the loop never picks it out of
  // place between the two; the issues the record already put first keep their place.
  dragTo(w, bcard(w, 76), bcard(w, 21));
  await settle(); await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'order', args: ['20', '76'], repo: 'sample' } }, { url: 'control', body: { action: 'release', args: ['76'], repo: 'sample' } }]);
  w.reply = { ok: false, status: 400, text: () => Promise.resolve('bad issue') };
  dragTo(w, bcard(w, 76), bcard(w, 21));
  await settle(); await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'order', args: ['20', '76'], repo: 'sample' } }], 'an order the host refused releases nothing');
  w.reply = null;
  dragTo(w, bcard(w, 76), column(w, 'queue'));
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'release', args: ['76'], repo: 'sample' } }], 'released where the loop puts it');
  dragTo(w, bcard(w, 76), column(w, 'held'));
  dragTo(w, bcard(w, 20), bcard(w, 20));
  assert.equal(dragTo(w, bcard(w, 76), column(w, 'review')), false, 'no other column takes a drop');
  await settle();
  assert.deepEqual(w.posts, [], 'a drop that changes nothing sends nothing');
  // The host's answer moves the card at once; the next snapshot is the loop as it stands.
  w.reply = record({ held: [76, 21] });
  dragTo(w, bcard(w, 21), column(w, 'held'));
  await settle();
  assert.deepEqual([inCol(w, 'held'), inCol(w, 'queue')], [[76, 21, 23], [20, 22]]);
  assert.match(note(w), /^Done\./);
  w.reply = record({ order: [22, 20] });
  dragTo(w, bcard(w, 22), bcard(w, 20));
  await settle();
  assert.deepEqual(inCol(w, 'queue'), [22, 20, 21]);
  assert.equal(bcard(w, 22).textContent.includes('Next in the queue'), true);
  const later2 = full(T0 + 60000); later2.panels.board.data.landed.pop();  // begun after the answers
  next(w, later2);
  assert.deepEqual([inCol(w, 'held'), inCol(w, 'queue')], [[76, 23], [20, 21, 22]], 'the snapshot replaces what the host answered');
});

test('the Board at phone width: Hold, Release, Move up and Move down on each card, and the arrow keys', async () => {
  const w = boot({ tab: 'control' });
  deliver(w, full());
  const cases = [
    [() => act(bcard(w, 20), 'hold').click(), { action: 'hold', args: ['20'] }],
    [() => act(bcard(w, 76), 'release').click(), { action: 'release', args: ['76'] }],
    [() => act(bcard(w, 21), 'up').click(), { action: 'order', args: ['21'] }],
    [() => act(bcard(w, 20), 'down').click(), { action: 'order', args: ['21', '20'] }],
    [() => key(w, bcard(w, 22), 'ArrowUp'), { action: 'order', args: ['20', '22'] }],
    [() => key(w, bcard(w, 21), 'ArrowLeft'), { action: 'hold', args: ['21'] }],
    [() => key(w, bcard(w, 76), 'ArrowRight'), { action: 'release', args: ['76'] }],
  ];
  for (const [fn, body] of cases) {
    fn();
    await settle();
    assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { ...body, repo: 'sample' } }]);
  }
  act(bcard(w, 20), 'up').click();
  act(bcard(w, 22), 'down').click();
  key(w, bcard(w, 76), 'ArrowLeft');
  key(w, bcard(w, 23), 'ArrowUp');
  dragTo(w, bcard(w, 23), bcard(w, 20));
  await settle();
  assert.deepEqual(w.posts, [], 'the first cannot go up, the last cannot go down, a held card is held already, and a rule-skipped card has no place in the order');
  assert.equal(act(bcard(w, 76), 'hold'), null, 'a held card has Release only');
  assert.deepEqual([act(bcard(w, 23), 'up'), act(bcard(w, 23), 'down')], [null, null], 'a rule-skipped card is not moved');
  for (const b of board(w).querySelectorAll('.board-moves button')) assert.ok(b.type === 'button' && /#\d+/.test(b.getAttribute('aria-label')), 'each names its card');
  assert.match(bcard(w, 20).getAttribute('aria-label'), /the up and down arrows move it/);
});

test('the Board: a rule-skipped card is in Held with its rule, shown once, and a drag does not queue it', async () => {
  const w = boot({ tab: 'control' });
  deliver(w, full());
  assert.deepEqual([inCol(w, 'held'), inCol(w, 'queue')], [[76, 23], [20, 21, 22]], 'it is not queued, so it is held');
  assert.ok(bcard(w, 23).textContent.includes('Skipped by a rule: area:infra'));
  assert.equal(act(bcard(w, 23), 'release'), null, 'no one but the rule holds it: there is nothing to release');
  assert.match(bcard(w, 23).textContent, /change it in Rules to queue it/);
  dragTo(w, bcard(w, 23), column(w, 'queue'));
  await settle();
  assert.deepEqual(w.posts, [], 'a drag alone does not queue it');
  assert.match(note(w), /A rule skips #23\. To queue it, change the rule in Rules\./);
  // The next snapshot lists it under holding and under skipped: it is one card, in Held, held by you and by the rule.
  const later = full();
  later.panels.board.data.control.held = [76, 23];
  later.panels.board.data.held.push({ repo: 'sample', card: null, issue: 23, title: 'Infra thing', url: `${P}/23` });
  next(w, later);
  assert.deepEqual([inCol(w, 'held'), inCol(w, 'queue')], [[76, 23], [20, 21, 22]]);
  assert.deepEqual(Array.from(bcard(w, 23).querySelectorAll('.chip[data-reason]'), (c) => c.dataset.reason), ['you', 'rule']);
  w.reply = record({ held: [76] });
  act(bcard(w, 23), 'release').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'release', args: ['23'], repo: 'sample' } }]);
  assert.deepEqual([inCol(w, 'held'), inCol(w, 'queue')], [[76, 23], [20, 21, 22]], 'released by you, the rule still holds it');
});

test('the Board: a card released with no place in the order goes where pick puts it, not first', async () => {
  const released = async (priority, followup, over, dates) => {
    const w = boot({ tab: 'control' }), d = full();
    Object.assign(d.panels.board.data.held[0], { priority, followup, retried: false });
    d.panels.board.data.queue[0].priority = 'P0';
    if (dates) [d.panels.board.data.held[0], ...d.panels.board.data.queue].forEach((x, i) => { x.created = dates[i]; });
    deliver(w, d);
    w.reply = record({ held: [], ...over });
    act(bcard(w, 76), 'release').click();
    await settle();
    assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'release', args: ['76'], repo: 'sample' } }]);
    return inCol(w, 'queue');
  };
  assert.deepEqual(await released('P2', false), [20, 21, 22, 76], 'a P2 beside queued P0 work is not shown next; the older P2s go first');
  assert.deepEqual(await released('P0', false), [20, 76, 21, 22], 'a P0 goes before the P2s, after the follow-up');
  assert.deepEqual(await released('P3', true), [20, 76, 21, 22], 'a P3 follow-up goes before the P2s that are not, after the P0 follow-up');
  assert.deepEqual(await released('P1', false, { order: [22] }), [22, 20, 76, 21], 'the ordered issues keep the front');
  const dates = ['2026-01-01T00:00:00Z', '2026-01-15T00:00:00Z', '2026-02-01T00:00:00Z', '2026-03-01T00:00:00Z'];
  assert.deepEqual(await released('P2', false, {}, dates), [20, 76, 21, 22], 'an older issue with a higher number (moved in) goes before the newer P2s, by its createdAt');
  assert.deepEqual(await released('P2', false, {}, [dates[3], ...dates.slice(0, 3)]), [20, 21, 22, 76], 'a newer one goes after them');
});

test('the Board: Stop now asks for a second click, and forgets the first after a while', async () => {
  const w = boot({ tab: 'control' });
  deliver(w, full());
  act(loopP(w), 'stop').focus();
  act(loopP(w), 'stop').click();
  await settle();
  assert.deepEqual(w.posts, [], 'one click stops nothing');
  assert.equal(act(loopP(w), 'stop').textContent, 'Click again: stop and requeue 2 cards', 'its second click names what it ends');
  assert.equal(act(loopP(w), 'stop').getAttribute('aria-pressed'), 'true');
  assert.equal(w.document.activeElement, act(loopP(w), 'stop'), 'the focus stays on it');
  act(loopP(w), 'stop').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'stop', args: [], repo: 'sample' } }]);
  assert.equal(act(loopP(w), 'stop').textContent, 'Stop now and requeue 2 cards');
  act(loopP(w), 'stop').click();
  later(w);
  assert.equal(act(loopP(w), 'stop').textContent, 'Stop now and requeue 2 cards', 'the first click is forgotten');
  act(loopP(w), 'stop').click();
  await settle();
  assert.deepEqual(w.posts, [], 'so the next click is a first one again');
});

// Issue 407: Needs you had two homes with different buttons. The column's card leads with why it stopped (a blocked
// card's reason in one sentence, the whole reason on a tap) and its link opens Overview on the Needs you panel, where
// it is answered; it sends nothing itself.
test('the Board: a Needs you card leads with why it stopped and links into the Needs you panel', async () => {
  const w = boot({ tab: 'control' });
  const data = full();
  Object.assign(data.panels.board.data.blocked[0], { push: true, reason: 'Push failed: exit 1 (124 is the 900s timeout): push-checks: ok typecheck-backend push-checks: FAILED typecheck-web web/pay.ts(3,7): error TS2322' });
  deliver(w, data);
  assert.equal(bcard(w, 12).querySelector('.board-why').textContent, 'Visible change: Staff see a new button.');
  const why = bcard(w, 13).querySelector('.why-said');
  assert.equal(why.textContent, 'Push refused: the check typecheck-web failed', 'the reason in one plain sentence first');
  assert.match(bcard(w, 13).querySelector('.why-block .why-full').textContent, /^Push failed: exit 1 .*error TS2322$/, 'the whole reason, without a tap');
  assert.equal(bcard(w, 13).firstElementChild.nextElementSibling.nextElementSibling.nextElementSibling, why, 'right under the issue, the title and the chip');
  act(bcard(w, 13), 'needs-open').click();
  await settle();
  assert.equal(tabBtn(w, 'overview').getAttribute('aria-selected'), 'true', 'the link opens Overview');
  assert.equal(w.document.activeElement, panel(w, 'needs'), 'on the Needs you panel');
  assert.deepEqual(w.posts, [], 'it sends nothing');
});

// The Control tab repeated the settings the Rules tab has (cards at once, pause at, the build, review and judge
// models), so the owner had two places for one setting; they are on Rules only. The bar keeps what steers the loop
// now and what it reads: the loop's state with its two buttons, the weekly limit and today's totals.
test('the Board: the bar pauses and starts the loop and shows the weekly limit and today; the settings are on the Rules tab only', async () => {
  const w = boot({ tab: 'control' });
  deliver(w, full());
  const sends = async (fn, body) => { fn(); await settle(); assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { ...body, repo: 'sample' } }]); };
  const SETTINGS = ['cards at once-up', 'cards at once-down', 'cap-off', 'guard-up', 'guard-down', 'guard-off', 'guard-on', 'builder-model', 'builder-effort',
    'reviewer-model', 'reviewer-effort', 'judge-on', 'judge-off', 'judge-model', 'judge-effort', 'judge-kind'];
  const bar = () => loopP(w).querySelector('.board-bar');
  // A control anywhere on the Board part's three panels.
  const onTab = (a) => [loopP(w), pushP(w), board(w)].map((p) => act(p, a)).find(Boolean) || null;
  for (const a of SETTINGS) assert.equal(onTab(a), null, `the Control tab draws no ${a}`);
  assert.equal(bar().querySelector('.board-stepper, .board-models, .board-model, [data-role]'), null, 'no stepper, and no Build, Review or Judge row');
  assert.doesNotMatch(bar().textContent, /At once|Pause at|pause at/, 'neither cards at once nor pause at is named');
  assert.ok(bar().querySelector('.board-state').textContent.includes('Running'), 'the loop state');
  assert.ok(act(loopP(w), 'pause') && act(loopP(w), 'stop'), 'Pause after current and Stop now');
  assert.equal(act(loopP(w), 'pause').textContent, 'Pause sample after current');
  assert.equal(act(loopP(w), 'stop').textContent, 'Stop now and requeue 2 cards');
  const meter = loopP(w).querySelector('.board-meter');
  assert.equal(meter.querySelector('.board-guard').style.left, '90%', 'the guard is marked on the meter');
  assert.equal(meter.querySelector('.meter-fill').style.transform, 'scaleX(0.44)');
  assert.match(meter.getAttribute('aria-label'), /44 percent of the weekly limit used, Conveyor pauses when the weekly limit reaches 90 percent/);
  assert.equal(loopP(w).querySelector('[data-figure="limit"] .board-value').textContent, '44%', 'the weekly limit with its percentage');
  assert.match(loopP(w).querySelector('[data-figure="today"]').textContent, /^Today2 landed\$3\.00$/, 'today\'s landed count and cost');
  // The Rules tab still draws every one of them.
  tabBtn(w, 'rules').click();
  for (const a of ['cards at once-up', 'cards at once-down', 'guard-off', 'guard-90', 'guard-95', 'guard-98', 'builder-model', 'builder-effort', 'reviewer-model', 'reviewer-effort',
    'judge-on', 'judge-off', 'judge-model', 'judge-effort', 'judge-kind', 'rule-P0', 'rule-P1', 'rule-P2', 'rule-P3', 'rule-followups']) assert.ok(act(ruled(w), a), `the Rules tab draws ${a}`);
  for (const k of ['build', 'cap', 'guard', 'builder', 'reviewer', 'judge']) assert.ok(ruled(w).querySelector(`[data-rule="${k}"]`), `the Rules tab has its ${k} row`);
  tabBtn(w, 'control').click();
  w.reply = record({ mode: 'pause' });
  await sends(() => act(loopP(w), 'pause').click(), { action: 'pause', args: [] });
  assert.ok(loopP(w).querySelector('.board-state').textContent.includes('Paused'), 'the host\'s answer shows at once');
  w.reply = record({ mode: 'run' });
  await sends(() => act(loopP(w), 'resume').click(), { action: 'resume', args: [] });
  assert.ok(act(loopP(w), 'pause'));
  w.reply = undefined;
  const guarded = full(T0 + 60000);
  Object.assign(guarded.panels.board.data, { state: 'paused by guard', limit: { pct: 92, from: 'loop' }, control: { ...CONTROL, guard: null, cap: 5 }, cap: 5 });
  next(w, guarded);
  assert.ok(loopP(w).textContent.includes('Paused by guard') && loopP(w).textContent.includes('no guard'));
  assert.equal(loopP(w).querySelector('.board-guard'), null);
  assert.equal(loopP(w).querySelector('[data-figure="limit"] .board-value').textContent, '92%');
  for (const a of SETTINGS) assert.equal(onTab(a), null, `with no guard set either, the Control tab draws no ${a}`);
});

test('the Board: while a change is out its controls are off, and a second click sends nothing', async () => {
  const w = boot({ tab: 'control' });
  deliver(w, full());
  let answer;
  w.reply = { ok: true, status: 200, text: () => new Promise((r) => { answer = r; }) };
  const pause = act(loopP(w), 'pause');
  pause.focus();
  pause.click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'pause', args: [], repo: 'sample' } }]);
  const off = [...loopP(w).querySelectorAll('.board-top button, .board-top select'), ...board(w).querySelectorAll('.board-cards button')];
  assert.ok(off.length > 2, 'the bar\'s controls and the cards\' are there');
  for (const b of off) assert.equal(b.disabled, true, `${b.dataset.act} is off while the change is out`);
  act(loopP(w), 'pause').click();
  key(w, bcard(w, 20), 'ArrowLeft');
  await settle();
  assert.deepEqual(w.posts, [], 'nothing more is sent until the host answers');
  assert.match(note(w), /^Wait/);
  answer(JSON.stringify(CONTROL));
  await settle();
  assert.equal(act(loopP(w), 'pause').disabled, false, 'the answer turns the controls back on');
  assert.equal(w.document.activeElement, act(loopP(w), 'pause'), 'and gives the focus back');
  w.reply = record({ mode: 'pause' });
  act(loopP(w), 'pause').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'pause', args: [], repo: 'sample' } }]);
  assert.ok(act(loopP(w), 'resume'), 'the host\'s answer is what the bar offers next');
});
