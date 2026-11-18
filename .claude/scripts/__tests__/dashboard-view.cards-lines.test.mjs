// SPDX-License-Identifier: Apache-2.0
// The dashboard page's cards, the lines a card shows: what started a fix, its reviews, its cost so far, what it waits on
// or gave way to, and cards that landed in one batch. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { boot, panel, deliver, next, P, trackOf, counts, full, bcard, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

// The owner asked why a card whose review was a GO showed "Fix after review 1": a fix was labelled by the review it
// followed, whatever started it. A card had three fix sessions and none came from the reviewer (two from the reply
// check, one because main moved). Each fix is now named by what started it, in "Every step" and in the step pill, its
// full reason on hover.
test('a fix session is labelled with what started it, its reason on hover, never "Fix after review"', () => {
  const DW = 'the Done-when check failed: D1 not met: no test names the case', MOVED = "main moved since the card's change was made, and the change no longer applied to it";
  const start = [{ name: 'queued', state: 'done', sec: 60 }, { name: 'picked', state: 'done', sec: null }, { name: 'building', state: 'done', sec: 600 }];
  const recs = [...start, { name: 'fix 1', state: 'done', sec: 60, reason: DW }, { name: 'review 1 (NO-GO)', state: 'done', sec: 120 }, { name: 'fix 2', state: 'done', sec: 300 },
    { name: 'review 2 (GO)', state: 'done', sec: 60 }, { name: 'fix 3', state: 'done', sec: 200, reason: MOVED }, { name: 'review 3 (GO)', state: 'done', sec: 60 },
    { name: 'tests failed', state: 'failed', sec: 90, why: 'exit 1' }, { name: 'fix 4', state: 'done', sec: 100 }];
  const w = boot();
  const data = full();
  data.panels.landed.data.cards[0].track = trackOf('++++++', '', { at: null, since: null, records: [...recs, { name: 'tests passed', state: 'done', sec: 60 }] });
  deliver(w, data);
  const fixes = Array.from(panel(w, 'landed').querySelectorAll('.timeline > li.tl-item .tl-label')).filter((l) => /^Fix/.test(l.textContent));
  assert.deepEqual(fixes.map((l) => l.textContent), ['Fix 1: reply check', 'Fix 2: review findings', 'Fix 3: main changed under it', 'Fix 4: tests failed'], 'each fix names what started it, its round kept');
  assert.equal(fixes[0].title, DW, 'the reply check: its full reason on hover');
  assert.equal(fixes[2].title, MOVED, 'main moved: its full reason on hover');
  assert.ok(fixes.every((l) => l.title), 'every fix label has its reason on hover');
  // The fix in progress has no line yet: the step pill and its bar name what started it from the step before it, and
  // name no cause where that step leaves more than one.
  const pillOf = (before, label) => {
    const d = full();
    d.panels.belt.data.cards[0].track = trackOf('++>...', label, { records: [...before, { name: label, state: 'now', sec: null }] });
    next(w, d);
    const row = panel(w, 'belt').querySelector('li[data-key="sample:c3-63"]'), bars = row.querySelectorAll('.timeline > li.tl-item .tl-label');
    const pill = row.querySelector('.row-main .chip');
    assert.equal(bars[bars.length - 1].textContent, pill.textContent, 'the pill and the bar in progress say the same');
    return [pill.textContent, pill.title];
  };
  // After a review the fix may be its findings, the commit trailers (after a GO) or main having moved (after a GO, or a
  // last NO-GO, which still lands): none of them is claimed.
  assert.deepEqual(pillOf([...start, { name: 'review 1 (NO-GO)', state: 'done', sec: 120 }], 'fix after review 1'), ['Fix 1', ''], 'a fix after a NO-GO: no cause claimed');
  assert.deepEqual(pillOf([...start, { name: 'review 1 (GO)', state: 'done', sec: 120 }], 'fix after review 1'), ['Fix 1', ''], 'a fix after a GO: no cause claimed');
  assert.deepEqual(pillOf([...start, { name: 'fix 1', state: 'done', sec: 60, reason: 'missing commit trailers: Spec' }], 'fix after review 0'), ['Fix 2', ''],
    'after a trailer fix: the reply check or main moved, no cause claimed');
  assert.deepEqual(pillOf(start, 'fix after review 0'), ['Fix 1: reply check', 'the Done-when check on the reply failed'], "a fix just after the build's line: the reply check");
  assert.deepEqual(pillOf(recs.slice(0, 6), 'fix after review 1'), ['Fix 3: reply check', 'the Done-when check on the reply failed'], 'just after a findings fix: the reply check');
  assert.deepEqual(pillOf(recs.slice(0, 4), 'fix after review 0'), ['Fix 2: main changed under it', 'main moved after the card made its change, and the change no longer applied to it'],
    'just after a reply-check fix: main moved');
  assert.deepEqual(pillOf([...recs, { name: 'tests passed', state: 'done', sec: 60 }], 'fix after review 3'), ['Fix 5: main changed under it', 'main moved after the card made its change, and the change no longer applied to it'],
    'just after tests that passed: main moved');
  assert.deepEqual(pillOf(recs.slice(0, -1), 'fix after failed tests'), ['Fix 4: tests failed', 'the changed tests failed']);
  assert.ok(!/fix after review/i.test(panel(w, 'belt').textContent + panel(w, 'landed').textContent), 'no fix label reads "Fix after review"');
});

test('a card shows one line a finished review: none, one, three, and one recorded before findings were counted', () => {
  const w = boot();
  const lines = (reviews) => {
    const data = full();
    data.panels.belt.data.cards[0].reviews = reviews;
    next(w, data);
    const ul = panel(w, 'belt').querySelector('li[data-key="sample:c3-63"] .reviews');
    return ul.hidden ? null : Array.from(ul.children, (li) => Array.from(li.children, (n) => n.textContent).join(' ').trim());
  };
  const r = (round, verdict, c) => ({ round, verdict, counts: c, sec: 60, fixed: false });
  deliver(w, full());
  assert.equal(lines([]), null);
  // Spelled out, never "R1 GO" (issue 415).
  assert.deepEqual(lines([r(1, 'GO', counts(0, 0, 0, 0))]), ['Review 1: passed']);
  // A review recorded with no counts shows its verdict alone.
  assert.deepEqual(lines([r(1, 'NO-GO', counts(1, 0, 2, 1)), r(2, 'NO-GO', null), r(3, 'GO', null)]),
    ['Review 1: changes asked 1 P0, 2 P2, 1 P3', 'Review 2: changes asked', 'Review 3: passed']);
  assert.doesNotMatch(panel(w, 'belt').textContent, /counts not recorded/);
  // Issue 306: a finding that came back after its fix rounds (the review's survived) showed as one more finding.
  const back = { ...r(3, 'NO-GO', counts(0, 1, 0, 0)), survived: [{ id: 'E2', rounds: 2 }] };
  assert.deepEqual(lines([back]), ['Review 3: changes asked 1 P1 E2 came back after 2 fix rounds']);
  // A landed card: its reviews, how many findings became follow-ups, and an issue GitHub did not close.
  const data = full();
  Object.assign(data.panels.landed.data.cards[0], { reviews: 3, followups: [31, 32], rounds: [r(1, 'NO-GO', counts(0, 2, 0, 0)), r(2, 'NO-GO', null), { ...r(3, 'NO-GO', counts(0, 1, 1, 0)), survived: [{ id: 'E1', rounds: 2 }] }],
    track: trackOf('+++++!', '', { reason: 'GitHub did not close the issue' }) });
  next(w, data);
  const text = Array.from(panel(w, 'landed').querySelector('li').querySelectorAll('.row-meta span'), (n) => n.textContent).join(' | ');
  assert.ok(text.includes('Review 1: changes asked, 2 P1 | Review 2: changes asked | Review 3: changes asked, 1 P1, 1 P2, E1 came back after 2 fix rounds | 2 became follow-ups'), text);
  assert.ok(panel(w, 'landed').querySelector('li').textContent.includes('Issue still open'));
  assert.doesNotMatch(panel(w, 'landed').textContent, /counts not recorded/);
  assert.ok(!panel(w, 'landed').querySelectorAll('li')[1].textContent.includes('Review 1'), 'a landed card with no review listed shows none');
});

// The owner read a landed card shown "pushing", with push off and nothing pushed, as Conveyor pushing against the rule.
// With push off the snapshot gives it no running step (at null) and the label of what it waits for.
test('with push off a landed, unpushed card says it waits for Push landed, with no running Push step', () => {
  const w = boot();
  const data = full();
  Object.assign(data.panels.landed.data.cards[0], { pushed: false, track: trackOf('+++++.', 'Landed, waiting for Push landed') });
  next(w, data);
  const li = panel(w, 'landed').querySelector('li');
  assert.ok(li.textContent.includes('Landed, waiting for Push landed'), li.textContent);
  assert.doesNotMatch(li.textContent, /Pushing|not pushed yet/, 'its Push step is not shown running');
});

test('a card with no token read yet says no reading yet, never $0; one with a reading shows its dollars so far', () => {
  const w = boot();
  const cost = (over) => {
    const data = full();
    Object.assign(data.panels.belt.data.cards[0], over);
    next(w, data);
    return panel(w, 'belt').querySelector('li[data-key="sample:c3-63"] .row-meta').lastChild.textContent;
  };
  deliver(w, full());
  assert.equal(cost({}), '$1.25 · 412k tokens so far');
  assert.equal(cost({ tokens: { claude: 1250000, codex: 0 } }), '$1.25 · 1.3M tokens so far');
  assert.equal(cost({ tokens: null }), '$1.25 so far');
  assert.equal(cost({ usd: null, reading: false }), 'no reading yet');
  assert.equal(cost({ usd: 0, reading: false }), 'no reading yet');
  assert.equal(cost({ usd: null, reading: true }), 'not priced · 412k tokens so far');
  // Bug (#391): a build whose route streams every answer with usage 0 read "no reading yet" for its whole step, which
  // reads as a fault; the snapshot marks it atEnd, and the belt (here) and the Board (below) say when the cost comes.
  assert.equal(cost({ usd: null, reading: false, atEnd: true }), 'cost shown when the step ends');
});

test('the Board\'s building column says a card\'s cost is shown when the step ends, when its route streams usage 0 (#391)', () => {
  const w = boot({ tab: 'control' });
  const data = full();
  Object.assign(data.panels.board.data.building[0], { atEnd: true });
  deliver(w, data);
  const col = panel(w, 'board').querySelector('.board-col[data-col="building"]');
  assert.ok(col.textContent.includes('cost shown when the step ends') && !col.textContent.includes('no reading yet'), col.textContent);
});

// Bug: a card waiting on a same-file card showed as a running review on the Board and the belt, though no reviewer
// ran and the card it waited on was blocked or queued, so a deadlocked belt looked busy.
test('a card waiting on a same-file card reads "waiting on #N (state)" on the belt and the Board, never review', () => {
  const w = boot();
  const data = full();
  // The belt card keeps the review track it waits to begin.
  Object.assign(data.panels.belt.data.cards[0], { step: 'waiting', waitsOn: { card: 'c1-55', issue: 55, state: 'queued' } });
  deliver(w, data);
  const chip = panel(w, 'belt').querySelector('li[data-key="sample:c3-63"] .row-main .chip').textContent;
  assert.ok(chip.includes('Waiting on #55 (queued)') && !/Review/.test(chip), `the belt chip: ${chip}`);
  const b = boot({ tab: 'control' });
  const bd = full();
  Object.assign(bd.panels.board.data.building[0], { step: 'waiting', waitsOn: { card: 'c1-55', issue: 55, state: 'blocked' } });
  deliver(b, bd);
  const meta = bcard(b, 5).querySelector('.row-meta').textContent;
  assert.ok(meta.includes('waiting on #55 (blocked)') && !/review/.test(meta), `the Board card: ${meta}`);
});

// Bug: a card that gave up its land turn to a ready same-file card showed as a plain fix, so nobody could tell why
// a card behind it landed first. A row a step it can be at after giving way: the Board column, what its card is
// given, its issue, and the plain words that must not show instead.
// Issue 415: spelled "Waiting behind #N", what it does meanwhile on hover and tap.
test('a card that gave up its land turn reads "Waiting behind #N" on the Board', () => {
  for (const [col, over, issue, not, what] of [
    ['building', { step: 'fix', gaveWay: 92 }, 5, 'fixing', 'the Board card'],
    // Reviewed again after its fit, it still reads as having given way.
    ['review', { gaveWay: 92 }, 63, 'review 2 of 3', 'the Board card in review'],
    // Waiting again on the card it gave way to, it still reads as having given way, not as a plain wait.
    ['building', { step: 'waiting', gaveWay: 92, waitsOn: { card: 'c1-92', issue: 92, state: 'landing' } }, 5, 'waiting on #92', 'the waiting Board card'],
  ]) {
    const b = boot({ tab: 'control' });
    const bd = full();
    Object.assign(bd.panels.board.data[col][0], over);
    deliver(b, bd);
    const meta = bcard(b, issue).querySelector('.row-meta');
    assert.ok(meta.textContent.includes('Waiting behind #92') && !meta.textContent.includes(not), `${what}: ${meta.textContent}`);
    assert.equal(meta.firstChild.dataset.tip, 'It let #92 land first. While it waits, it fits its change onto main.', `${what}: the long form on tap`);
  }
});

// The owner: "why are other cards waiting for it? can't they go in front". A card whose tests failed lets a ready
// card land while it is fixed: the Board says so, not that it is being fitted onto main.
test('a card that gave up its land turn for the fix of its failed tests says on tap that it is fixing them', () => {
  const b = boot({ tab: 'control' });
  const bd = full();
  Object.assign(bd.panels.board.data.building[0], { step: 'fix', gaveWay: 92, gaveWayFixing: true });
  deliver(b, bd);
  const meta = bcard(b, 5).querySelector('.row-meta');
  assert.ok(meta.textContent.includes('Waiting behind #92'), `the Board card: ${meta.textContent}`);
  assert.equal(meta.firstChild.dataset.tip, 'It let #92 land first. While it waits, it fixes its failed tests.', 'not that it is being fitted onto main');
});

// Issue 612: a main-red fix the loop started with the cap reached runs in one slot beyond it. Without the tag the
// owner sees one card more than the cap on the Board and no reason; a card that took no such slot shows none.
test('a main-red fix in a slot beyond the cap reads "beyond the cap: main is red" on the Board', () => {
  const b = boot({ tab: 'control' });
  const bd = full();
  Object.assign(bd.panels.board.data.building[0], { beyond: 'main is red' });
  deliver(b, bd);
  assert.ok(bcard(b, 5).textContent.includes('beyond the cap: main is red'), `the Board card: ${bcard(b, 5).textContent}`);
  assert.ok(!bcard(b, 63).textContent.includes('beyond the cap'), `a card in its slot: ${bcard(b, 63).textContent}`);
});

// Same-file cards that are ready land in batches, on one test run: the owner reads a batch as one landing, its cards
// listed in it, never as cards that each landed on their own.
test('cards that landed in one batch are one landing in Landed today, with each of its cards listed', () => {
  const w = boot();
  const data = full();
  const cards = data.panels.landed.data.cards;
  const batch = ['c5-7', 'c9-9'];
  cards.splice(1, 0, { ...cards[0], card: 'c9-9', issue: 9, title: 'Batch mate', url: `${P}/9`, followups: [], batch });
  cards[0].batch = batch;
  deliver(w, data);
  const top = Array.from(panel(w, 'landed').querySelectorAll('ul.rows > li')).filter((li) => !li.parentElement.closest('li'));
  assert.equal(top.length, 2, 'one landing for the batch and one row for the card that closed on its own');
  assert.ok(top[0].querySelector('.row-main').textContent.includes('One landing of 2 cards'), top[0].textContent);
  const inside = Array.from(top[0].querySelectorAll('li.row')).map((li) => li.querySelector('.title').textContent);
  assert.deepEqual(inside, ['Landed one', 'Batch mate'], 'the batch lists its cards, in order');
  assert.ok(top[1].textContent.includes('Fixed before') && !top[1].classList.contains('batch'), 'a card on its own is its own row');
});

// A batch of 8 is one landing of 8 cards: the list's first page (5) never cuts it short, and two repos whose batches
// name the same card ids are two landings, never one.
test('a batch larger than a page lists all its cards, and batches of two repos stay apart', () => {
  const w = boot();
  const data = full();
  const first = data.panels.landed.data.cards[0];
  const eight = Array.from({ length: 8 }, (_, i) => `c${i}-${20 + i}`);
  const big = eight.map((card, i) => ({ ...first, card, issue: 20 + i, title: `Big ${i}`, url: `${P}/${20 + i}`, followups: [], batch: eight }));
  const pair = ['c1-40', 'c2-41'];
  const two = ['alpha', 'beta'].flatMap((repo) => pair.map((card, i) => ({ ...first, repo, card, issue: 40 + i, title: `${repo} ${i}`, url: `${P}/${40 + i}`, followups: [], batch: pair })));
  data.panels.landed.data.cards = [...big, ...two];
  deliver(w, data);
  const top = Array.from(panel(w, 'landed').querySelectorAll('ul.rows > li')).filter((li) => !li.parentElement.closest('li'));
  assert.equal(top.length, 3, 'one landing for the batch of 8 and one for each repo\'s batch of 2');
  assert.equal(top[0].querySelectorAll('li.row').length, 8, `the batch of 8 lists all 8 cards: ${top[0].textContent}`);
  [1, 2].forEach((i) => {
    assert.ok(top[i].querySelector('.row-main').textContent.includes('One landing of 2 cards'), top[i].textContent);
    assert.equal(top[i].querySelectorAll('li.row').length, 2, `a repo's batch of 2 lists its own 2 cards: ${top[i].textContent}`);
  });
});

// The Board's Landed today reads a batch the same way: one landing that lists its cards, never cards that each
// landed on their own; its count is still every card.
test('the Board shows cards that landed in one batch as one landing in Landed today', () => {
  const w = boot({ tab: 'control' });
  const data = full();
  const landed = data.panels.board.data.landed;
  const batch = ['c5-7', 'c9-9'];
  landed.splice(1, 0, { ...landed[0], card: 'c9-9', issue: 9, title: 'Batch mate', url: `${P}/9`, batch });
  landed[0].batch = batch;
  deliver(w, data);
  const col = panel(w, 'board').querySelector('.board-col[data-col="landed"]');
  const top = Array.from(col.querySelectorAll('.board-cards > li')).filter((li) => !li.parentElement.closest('li'));
  assert.equal(top.length, 2, 'one landing for the batch and one card for the one that closed on its own');
  assert.ok(top[0].classList.contains('board-batch') && top[0].textContent.includes('One landing of 2 cards'), top[0].textContent);
  assert.deepEqual(Array.from(top[0].querySelectorAll('.bcard'), (c) => Number(c.dataset.issue)), [7, 9], 'the batch lists its cards, in order');
  assert.ok(top[1].classList.contains('bcard') && top[1].dataset.issue === '8', 'a card on its own is its own card');
  assert.equal(col.querySelector('.board-head .panel-count').textContent, '3', 'the column counts every card');
});
