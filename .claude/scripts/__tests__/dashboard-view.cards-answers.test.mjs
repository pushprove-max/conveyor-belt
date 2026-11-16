// SPDX-License-Identifier: Apache-2.0
// The dashboard page's cards: the answers the owner gives from Needs you, the page's writes to the host and how a
// refusal or an unreadable reply is shown. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { T0, iso, clone, boot, panel, deliver, next, later, settle, key, P, full, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

// ---- the page's writes from Needs you ----
test('an open decision is answered from the page, and what the owner typed survives a refresh', async () => {
  const w = boot();
  deliver(w, full());
  const row = () => panel(w, 'needs').querySelector('li[data-key="decision:bookshop:q-ship@2026-11-09T10:00:00Z"]');
  assert.deepEqual(Array.from(row().querySelectorAll('.answer button')).map((b) => b.textContent), ['Yes (default)', 'No', 'Answer']);
  const field = row().querySelector('input');
  assert.equal(field.getAttribute('aria-label'), 'Answer to q-ship');
  row().querySelector('.btn-primary').click();
  assert.equal(row().querySelector('.answer-note').textContent, 'Type an answer first, or pick one.');
  assert.equal(w.posts.length, 0);
  field.value = 'Ship on Monday';
  field.focus();
  const more = full();
  more.panels.needs.data.decisions.push({ repo: 'bookshop', id: 'q-two', askedAt: '2026-11-09T12:00:00Z', question: 'Another?', options: null, proposedDefault: null, source: 'main' });
  next(w, more);
  assert.equal(row().querySelector('input'), field, 'the row is the same after a refresh that changed the panel');
  assert.equal(field.value, 'Ship on Monday');
  assert.equal(w.document.activeElement, field, 'and the field still has the focus');
  key(w, field, 'Enter');
  await settle();
  assert.deepEqual(w.posts, [{ url: 'answer', body: { id: 'q-ship', answer: 'Ship on Monday', askedAt: '2026-11-09T10:00:00Z', repo: 'bookshop' } }]);
  // Issue 415: the build machine's own reply ("sent to main") is shown only when the answer was not recorded.
  assert.equal(row().querySelector('.answer-note').textContent, 'Answered: it leaves Needs you in about a minute.');
  w.reply = { ok: false, status: 409, text: () => Promise.resolve('decision q-ship is already answered') };
  row().querySelectorAll('.answer button')[1].click();
  await settle();
  assert.deepEqual(w.posts[1].body, { id: 'q-ship', answer: 'No', askedAt: '2026-11-09T10:00:00Z', repo: 'bookshop' });
  assert.equal(row().querySelector('.answer-note').textContent, 'Not recorded: decision q-ship is already answered');
  w.reply = { ok: false, status: 502, text: () => Promise.resolve('recorded, ruling r-1 logged, NOT sent to main: no pane') };
  row().querySelectorAll('.answer button')[0].click();
  await settle();
  assert.equal(row().querySelector('.answer-note').textContent, 'recorded, ruling r-1 logged, NOT sent to main: no pane', 'a host error that says what was recorded is shown as written');
  w.reply = { ok: false, status: 401, text: () => Promise.resolve('log in to answer') };
  row().querySelectorAll('.answer button')[0].click();
  await settle();
  assert.equal(w.navigations, 1, 'a logged-out page goes to the login');
});

// There is no main session any more; an answer that is recorded is done.
test('Needs you lists no answer as not sent to main, and has no button to send one again', () => {
  const w = boot();
  const data = full();
  data.panels.needs.data.unsent = [{ id: 'q-old', askedAt: '2026-11-08T10:00:00Z', answer: 'go', ruling: 'r-20261108-1' }];
  deliver(w, data);
  assert.equal(panel(w, 'needs').querySelector('[data-group="unsent"], li[data-key^="unsent:"]'), null);
  assert.doesNotMatch(panel(w, 'needs').textContent, /not sent to main|Send to main again/);
  assert.equal(panel(w, 'needs').querySelector('.panel-count').textContent, '3', 'and counts none');
});

// The Board reads the ledger of every record that names one: each decision names its project, and a ledger that did
// not read is named beside the decisions of those that did, never hidden behind them or behind "Nothing needs you".
test("Needs you: each open decision names its project, and a ledger that was not read is warned beside the rest", () => {
  const w = boot();
  const data = full();
  const d = data.panels.needs.data;
  d.decisions = [{ repo: 'bookshop', id: 'q-ship', askedAt: '2026-11-09T10:00:00Z', question: 'Ship it?', options: ['Yes', 'No'], proposedDefault: 'Yes', source: 'main' },
    { repo: 'widgetshop', id: 'w-pay', askedAt: '2026-11-09T11:00:00Z', question: 'Take payments?', options: null, proposedDefault: 'No', source: 'main' }];
  deliver(w, data);
  const group = () => panel(w, 'needs').querySelector('[data-group="decisions"]');
  const metaOf = (k) => group().querySelector(`li[data-key="${k}"] .row-meta`).textContent;
  assert.match(metaOf('decision:bookshop:q-ship@2026-11-09T10:00:00Z'), /bookshop/);
  assert.match(metaOf('decision:widgetshop:w-pay@2026-11-09T11:00:00Z'), /widgetshop/);
  assert.equal(group().querySelector('.warn-note').hidden, true, 'every ledger read: no warning');
  const later = full();
  Object.assign(later.panels.needs.data, { cards: { waiting: [], blocked: [], before: [] }, decisions: [d.decisions[0]], decisionsError: 'no ledger for widgetshop at /nowhere/decisions.jsonl' });
  next(w, later);
  const warn = group().querySelector('.warn-note');
  assert.equal(warn.hidden, false, "another project's open decision does not hide the warning");
  // Issue 415 (UX5): the reader's reason names a ledger and its file, so it is on tap only.
  assert.equal(warn.textContent, 'The Board could not read some open decisions, so this list can miss some. It reads them again in about a minute.');
  assert.equal(warn.dataset.tip, 'Details: no ledger for widgetshop at /nowhere/decisions.jsonl');
  assert.deepEqual(Array.from(group().querySelectorAll('li.row')).map((li) => li.dataset.key), ['decision:bookshop:q-ship@2026-11-09T10:00:00Z'], 'and the decision that was read is still listed beside it');
  assert.doesNotMatch(panel(w, 'needs').textContent, /Nothing needs you/, 'a ledger not read is never "nothing"');
});

// An answer goes to its own project's ledger: the page names the record, and two projects' decisions with the same id
// and askedAt are two rows. Bug caught: the answer carried no project, so the server wrote the Board's own ledger;
// and rows keyed by id alone kept one project's row (its question and its answer button) for the other's decision.
test('Needs you: an answer names its project, and the same decision id in two projects is two rows', async () => {
  const w = boot();
  const data = full();
  const same = { id: 'q-ship', askedAt: '2026-11-09T10:00:00Z', options: ['Yes', 'No'], proposedDefault: 'Yes', source: 'main' };
  data.panels.needs.data.decisions = [{ ...same, repo: 'bookshop', question: 'Ship bookshop?' }, { ...same, repo: 'widgetshop', question: 'Ship widgetshop?' }];
  deliver(w, data);
  const rows = () => Array.from(panel(w, 'needs').querySelectorAll('[data-group="decisions"] li.row'));
  assert.deepEqual(rows().map((li) => li.querySelector('.title').textContent), ['Ship bookshop?', 'Ship widgetshop?']);
  rows()[1].querySelector('.answer button').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'answer', body: { id: 'q-ship', answer: 'Yes', askedAt: '2026-11-09T10:00:00Z', repo: 'widgetshop' } }]);
  const later = clone(data);
  later.panels.needs.data.decisions.splice(1, 1);
  next(w, later);
  assert.deepEqual(rows().map((li) => li.querySelector('.title').textContent), ['Ship bookshop?'], "the other project's row leaves with its decision");
  rows()[0].querySelector('.answer button').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'answer', body: { id: 'q-ship', answer: 'Yes', askedAt: '2026-11-09T10:00:00Z', repo: 'bookshop' } }]);
});

// A card waiting for the owner's yes is answered in Needs you: the reviewer's sentence, the files it changed, and
// Approve, Approve with a condition and Decline, each asking once before it sends POST /control. Bug: the panel only
// told the owner to add the approval line by hand and run conveyor.sh retry.
test('Needs you: a visible change is approved, approved with a condition or declined from the panel', async () => {
  const w = boot();
  const data = full();
  data.panels.needs.data.cards.waiting[0].files = { count: 3, paths: ['web/pay.ts', 'src/pay.ts'] };
  deliver(w, data);
  const row = (x = w) => panel(x, 'needs').querySelector('li[data-key="waiting:c1-12"]');
  const btn = (k, x = w) => row(x).querySelector(`button[data-act="${k}"]`);
  const note = (x = w) => row(x).querySelector('.yes .answer-note').textContent;
  assert.equal(row().querySelector('.reason').textContent, 'What customers or staff will see: Staff see a new button.');
  assert.deepEqual(['approve', 'condition', 'decline'].map((k) => btn(k).textContent), ['Approve', 'Approve with this condition', 'Decline']);
  assert.ok(row().querySelector('input[aria-label="Condition for the yes to #12"]') && row().querySelector('input[aria-label="Why not, for #12"]'), 'a text field for the condition and one for why');
  assert.doesNotMatch(panel(w, 'needs').querySelector('[data-group="waiting"]').textContent, /Visible change approved:|conveyor\.sh retry/, 'no hand instruction for a waiting card');
  assert.match(panel(w, 'needs').querySelector('li[data-key="blocked:c2-13"]').textContent, /Fix the cause\. Then press Retry\./, 'a blocked card keeps its own');
  assert.doesNotMatch(panel(w, 'needs').textContent, /conveyor\.sh retry/, 'no command where a button does it');
  const files = row().querySelector('.yes-files');
  assert.equal(files.querySelector('summary').textContent, '3 files changed: show the list');
  assert.equal(files.querySelector('details').open, false, 'the list is on demand');
  assert.deepEqual(Array.from(files.querySelectorAll('.paths li'), (li) => li.textContent), ['web/pay.ts', 'src/pay.ts', 'and 1 more']);
  // It asks once before it sends.
  btn('approve').click();
  await settle();
  assert.deepEqual(w.posts, [], 'the first click only asks');
  assert.equal(btn('approve').textContent, 'Click again to approve #12');
  assert.equal(btn('approve').getAttribute('aria-pressed'), 'true');
  w.reply = { ok: true, status: 200, text: () => Promise.resolve('conveyor: issue #12 can be picked again') };
  btn('approve').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'approve', args: ['12'], repo: 'sample' } }]);
  assert.equal(note(), 'Approved: #12 leaves Needs you in about a minute and returns to the belt.', 'no raw reply in brackets after a success (issue 415)');
  assert.ok(['approve', 'condition', 'decline'].every((k) => btn(k).disabled), 'answered once');
  // Bug (issue 407): the answered card stayed as it was, with its buttons, until the next data, so it was pressed twice.
  assert.ok(row().classList.contains('is-pending'), 'the card is greyed in place at once');
  assert.ok(Array.from(row().querySelectorAll('.yes .answer')).every((a) => a.hidden), 'its buttons and fields are gone');
  // The next data no longer lists it: it has left the panel.
  const after = full();
  after.panels.needs.data.cards.waiting = [];
  next(w, after);
  assert.equal(row(), null);
  assert.equal(panel(w, 'needs').querySelector('[data-group="waiting"]').hidden, true);
  assert.equal(panel(w, 'needs').querySelector('.panel-count').textContent, '2');

  // Approve with a condition, from the keyboard: Enter in the field asks, Enter again sends.
  const k = boot();
  deliver(k, full());
  const field = row(k).querySelector('input[aria-label="Condition for the yes to #12"]');
  key(k, field, 'Enter');
  assert.equal(note(k), 'Type the condition first.');
  field.value = '  only for   admins ';
  key(k, field, 'Enter');
  await settle();
  assert.deepEqual(k.posts, []);
  assert.equal(btn('condition', k).textContent, 'Click again to approve #12 with this condition');
  key(k, field, 'Enter');
  await settle();
  assert.deepEqual(k.posts, [{ url: 'control', body: { action: 'approve', args: ['12', 'only for admins'], repo: 'sample' } }]);
  assert.match(note(k), /^Approved with the condition: #12 leaves Needs you in about a minute/);
  // A files count with no list says the count; none at all says so.
  assert.equal(row(k).querySelector('.yes-files').textContent, 'Files changed: not recorded');

  // Decline asks for why, asks once, and a refusal shows the host's answer and can be given again.
  const d = boot();
  const one = full();
  one.panels.needs.data.cards.waiting[0].files = { count: 1, paths: null };
  deliver(d, one);
  assert.equal(row(d).querySelector('.yes-files').textContent, '1 file changed');
  btn('decline', d).click();
  assert.equal(note(d), 'Say why first.');
  row(d).querySelector('input[aria-label="Why not, for #12"]').value = 'not for staff yet';
  btn('decline', d).click();
  await settle();
  assert.deepEqual(d.posts, []);
  d.reply = { ok: false, status: 409, text: () => Promise.resolve('conveyor: #12 is not waiting for your yes; nothing changed') };
  btn('decline', d).click();
  await settle();
  assert.deepEqual(d.posts.splice(0), [{ url: 'control', body: { action: 'decline', args: ['12', 'not for staff yet'], repo: 'sample' } }]);
  assert.equal(note(d), 'Not done: conveyor: #12 is not waiting for your yes; nothing changed');
  assert.equal(btn('decline', d).disabled, false, 'a refused answer can be given again');
  assert.ok(!row(d).classList.contains('is-pending'), 'a refused card is not greyed');
  assert.equal(btn('decline', d).textContent, 'Decline', 'and asks again before it sends');
  d.reply = { ok: true, status: 200, text: () => Promise.resolve('conveyor: issue #12 can be picked again') };
  btn('decline', d).click();
  btn('decline', d).click();
  await settle();
  assert.equal(d.posts.length, 1);
  assert.match(note(d), /^Declined: your reason is on the issue\. #12 leaves Needs you in about a minute\. It stays off the belt, and Conveyor keeps its patch\. To build it, queue it on the Board/);
});

// A blocked card is retried or closed from Needs you, through POST /control with its repository. Bugs: only the
// Foreman could clear a blocked card, by an engine command; (issue 407) Retry, which costs a new build, sent on the
// first click while Close asked in a browser dialog unlike anything else on the page; and a retried card stayed as it
// was, with its buttons, until the next data.
test('Needs you: a blocked card has Retry and Close, each on a second click; a taken one greys the card and a refusal is shown beside it', async () => {
  const w = boot();
  const data = full();
  data.panels.needs.data.cards.blocked.push({ repo: 'sample', card: 'c9-15', issue: 15, title: 'Push fails', reason: 'push rejected', since: iso(T0), url: `${P}/15`, push: true });
  deliver(w, data);
  const row = (k) => panel(w, 'needs').querySelector(`li[data-key="${k}"]`);
  const btn = (k) => row('blocked:c2-13').querySelector(`button[data-act="${k}"]`);
  const note = () => row('blocked:c2-13').querySelector('.answer-note').textContent;
  assert.deepEqual(['retry', 'close'].map((k) => btn(k).textContent), ['Retry', 'Close']);
  assert.deepEqual(['retry', 'close'].map((k) => btn(k).dataset.guard), ['spend', 'final'], 'Retry costs a build; Close cannot be undone');
  for (const k of ['waiting:c1-12', 'blocked:c9-15']) {
    assert.equal(row(k).querySelector('button[data-act="retry"], button[data-act="close"]'), null, `${k}: a card that is not blocked, or has landed, has neither`);
  }
  // Retry asks on its first click, and sends on the second.
  btn('retry').click();
  await settle();
  assert.deepEqual(w.posts, [], 'the first click only asks');
  assert.equal(btn('retry').textContent, 'Click again to retry #13');
  btn('retry').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'retry', args: ['13'], repo: 'sample' } }]);
  assert.match(note(), /^Retried: #13 leaves Needs you in about a minute\./);
  assert.ok(row('blocked:c2-13').classList.contains('is-pending'), 'the card is greyed in place at once');
  assert.ok(['retry', 'close'].every((k) => btn(k).hidden), 'its buttons are gone');
  // Close says on its first click what the second does, and forgets it after a while.
  const c = boot();
  deliver(c, full());
  const crow = () => panel(c, 'needs').querySelector('li[data-key="blocked:c2-13"]');
  const close = () => crow().querySelector('button[data-act="close"]');
  close().click();
  await settle();
  assert.equal(close().textContent, 'Click again: close #13 for good. Conveyor never builds it');
  assert.deepEqual(c.posts, [], 'the first click sends nothing');
  later(c);
  assert.equal(close().textContent, 'Close', 'unanswered, the second click is forgotten');
  // Sent, the host's refusal is shown beside the card, its buttons back, and it can be tried again.
  c.reply = { ok: false, status: 409, text: () => Promise.resolve('conveyor: privacy: the check could not be made; nothing posted') };
  close().click(); close().click();
  await settle();
  assert.deepEqual(c.posts.splice(0), [{ url: 'control', body: { action: 'close', args: ['13'], repo: 'sample' } }]);
  assert.equal(crow().querySelector('.answer-note').textContent, 'Not done: conveyor: privacy: the check could not be made; nothing posted');
  assert.equal(close().disabled, false);
  assert.equal(close().hidden, false);
  assert.ok(!crow().classList.contains('is-pending'), 'a refused card is not greyed');
  // The next snapshot no longer lists it: it has left the panel.
  const after = full();
  after.panels.needs.data.cards.blocked = [];
  next(w, after);
  assert.equal(row('blocked:c2-13'), null);
});

// A blocked main-red fix card has no issue (issue 0): Retry and Close name it, and send it, by its card id. Bug: both
// sent "0", which the host refuses, so such a card could not be retried or closed from the Board.
test('Needs you: a blocked main-red fix card is retried and closed by its card id', async () => {
  const w = boot();
  const data = full();
  const card = 'c20261115T120000-sample-0';
  data.panels.needs.data.cards.blocked.push({ repo: 'sample', card, issue: 0, title: 'Main is red: a.test', reason: 'build: it failed', since: iso(T0), url: null });
  deliver(w, data);
  const btn = (k) => panel(w, 'needs').querySelector(`li[data-key="blocked:${card}"] button[data-act="${k}"]`);
  btn('retry').click();
  await settle();
  assert.equal(btn('retry').textContent, `Click again to retry ${card}`);
  btn('retry').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'retry', args: [card], repo: 'sample' } }]);
  const c = boot();
  deliver(c, data);
  const close = () => panel(c, 'needs').querySelector(`li[data-key="blocked:${card}"] button[data-act="close"]`);
  close().click(); close().click();
  await settle();
  assert.deepEqual(c.posts.splice(0), [{ url: 'control', body: { action: 'close', args: [card], repo: 'sample' } }]);
});

// Issue 141: a main-red fix card has no issue (issue 0); the snapshot names it "Main is red (<commit>)". Bug: the Board
// showed it as "branch", and the Foreman's views as "#0". Its name is on its card in Needs you and On the belt and in
// what Retry asks; Retry still sends its card id.
test('a main-red fix card shows its name, not #0, in Needs you and On the belt, and is retried by its card id', async () => {
  const w = boot();
  const data = full();
  const card = 'c20261115T120000-sample-0', name = 'Main is red (0123456789ab)';
  data.panels.needs.data.cards.blocked.push({ repo: 'sample', card, issue: 0, name, title: 'Main is red: a.test', reason: 'build: it failed', since: iso(T0), url: null });
  const belt = data.panels.belt.data.cards;
  belt.push({ ...clone(belt[1]), repo: 'sample', card: 'c20261115T130000-sample-0', issue: 0, name: 'Main is red (fedcba987654)', title: 'Main is red: b.test' });
  deliver(w, data);
  const row = panel(w, 'needs').querySelector(`li[data-key="blocked:${card}"]`);
  assert.equal(row.querySelector('.issue').textContent, name);
  const on = Array.from(panel(w, 'belt').querySelectorAll('.issue'), (e) => e.textContent);
  assert.ok(on.includes('Main is red (fedcba987654)'), `On the belt: ${on.join(', ')}`);
  assert.ok(!/#0\b/.test(panel(w, 'needs').textContent + panel(w, 'belt').textContent), 'no card is called #0');
  const btn = () => row.querySelector('button[data-act="retry"]');
  btn().click();
  await settle();
  assert.equal(btn().textContent, `Click again to retry ${name}`);
  btn().click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'retry', args: [card], repo: 'sample' } }]);
});

// Hold on a blocked card (issue 96). Bugs: there is no way to take a blocked card off the belt and keep its issue open;
// Hold posts another action or issue, asks a second time, or leaves the card in Needs you with its buttons; Undo does
// not release the issue; a main-red fix card, which has no issue to hold, offers Hold.
test('Needs you: a blocked card has Hold, one click with Undo: the card leaves Needs you, and Undo releases its issue', async () => {
  const w = boot();
  const data = full();
  data.panels.needs.data.cards.blocked.push({ repo: 'sample', card: 'c20261115T120000-sample-0', issue: 0, title: 'Main is red: a.test', reason: 'build: it failed', since: iso(T0), url: null });
  deliver(w, data);
  const row = () => panel(w, 'needs').querySelector('li[data-key="blocked:c2-13"]');
  const btn = (k) => row().querySelector(`button[data-act="${k}"]`);
  const note = () => row().querySelector('.answer-note').textContent;
  assert.deepEqual(Array.from(row().querySelectorAll('button'), (b) => b.textContent), ['Retry', 'Hold', 'Close']);
  assert.equal(panel(w, 'needs').querySelector('li[data-key="blocked:c20261115T120000-sample-0"] button[data-act="unblock"]'), null, 'a main-red fix card has no issue to hold');
  btn('unblock').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'unblock', args: ['13'], repo: 'sample' } }], 'one click holds it');
  assert.equal(note(), 'Held: #13 leaves Needs you in about a minute. Undo');
  assert.ok(row().classList.contains('is-pending') && ['retry', 'unblock', 'close'].every((k) => btn(k).hidden), 'greyed, its buttons gone');
  btn('undo').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'release', args: ['13'], repo: 'sample' } }]);
  assert.equal(note(), 'Undone: #13 is released. Conveyor builds it in its turn, from its kept work.');
  assert.ok(row().classList.contains('is-pending') && btn('retry').hidden, 'released, its card is still off the belt: nothing to retry');
  // The next data no longer lists it as blocked: it has left Needs you.
  const after = full();
  after.panels.needs.data.cards.blocked = [];
  next(w, after);
  assert.equal(row(), null);
});

// Fix on a blocked card whose reason has a fix Conveyor runs itself (issue 96). Bugs: no such card offers Fix, or one
// whose reason has no runnable fix does; Fix does not say what it does, sends on the first click, or posts a plain
// retry, which takes up the kept patch that stopped the card again.
test('Needs you: a blocked card whose reason has a runnable fix shows Fix, which says what it does and posts it; others show none', async () => {
  const w = boot();
  const data = full();
  data.panels.needs.data.cards.blocked.push({ repo: 'sample', card: 'c3-14', issue: 14, title: 'Kept patch', reason: 'worktree: the kept patch of card c1-14 could not be taken out of the worktree', since: iso(T0), url: `${P}/14` },
    { repo: 'sample', card: 'c4-16', issue: 16, title: 'Port', reason: 'review 1: the engine could not compare the port with the kept patch', since: iso(T0), url: `${P}/16` });
  deliver(w, data);
  const row = (k) => panel(w, 'needs').querySelector(`li[data-key="blocked:${k}"]`);
  assert.equal(row('c2-13').querySelector('button[data-act="fix"], .fix-does'), null, '"tests failed twice" has no fix Conveyor can run');
  for (const [k, n] of [['c3-14', 14], ['c4-16', 16]]) {
    const fix = () => row(k).querySelector('button[data-act="fix"]');
    assert.deepEqual(Array.from(row(k).querySelectorAll('button'), (b) => b.textContent), ['Retry', 'Fix', 'Hold', 'Close'], k);
    assert.equal(row(k).querySelector('.fix-does').textContent, `Fix builds #${n} again from nothing, without its kept work, which Conveyor cannot use. That work moves to kept-dropped/ in the state folder.`);
    fix().click();
    await settle();
    assert.deepEqual(w.posts, [], `${k}: the first click only asks`);
    assert.equal(fix().textContent, `Click again to fix #${n}`);
    fix().click();
    await settle();
    assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'retry', args: [String(n), '--fresh'], repo: 'sample' } }], k);
    assert.match(row(k).querySelector('.answer-note').textContent, new RegExp(`^Fixed: #${n} leaves Needs you in about a minute\\.`));
  }
});

// Bug: a reply whose body could not be read (the connection dropped after the status) left Retry, Close, Approve
// and Decline disabled under "Sending…" until the page was reloaded. The status is the host's answer.
test('Needs you: a reply whose body cannot be read is answered by its status, and a refusal frees the buttons', async () => {
  const unread = (ok, status) => ({ ok, status, text: () => Promise.reject(new TypeError('Failed to fetch')) });
  const w = boot();
  deliver(w, full());
  const row = (k) => panel(w, 'needs').querySelector(`li[data-key="${k}"]`);
  const blocked = (k) => row('blocked:c2-13').querySelector(`button[data-act="${k}"]`);
  w.reply = unread(false, 502);
  blocked('retry').click(); blocked('retry').click();
  await settle();
  assert.equal(row('blocked:c2-13').querySelector('.answer-note').textContent, 'Not done: the build machine answered 502');
  assert.deepEqual(['retry', 'close'].map((k) => blocked(k).disabled), [false, false], 'Retry and Close can be pressed again');
  w.reply = unread(true, 200);
  blocked('retry').click(); blocked('retry').click();
  await settle();
  assert.match(row('blocked:c2-13').querySelector('.answer-note').textContent, /^Retried: #13 leaves Needs you in about a minute\.$/);

  const yes = (k) => row('waiting:c1-12').querySelector(`.yes button[data-act="${k}"]`);
  w.reply = unread(false, 502);
  yes('approve').click();
  yes('approve').click();
  await settle();
  assert.equal(row('waiting:c1-12').querySelector('.yes .answer-note').textContent, 'Not done: the build machine answered 502');
  assert.equal(yes('approve').disabled, false, 'Approve can be pressed again');
});

// A follow-up whose change goes beyond its parent's yes says what goes beyond it, as the snapshot's `beyond`
// gives it. Bug: the row showed only the sentence, so the owner approved without seeing what exceeds the earlier yes.
test('Needs you: a waiting follow-up that goes beyond its parent\'s yes says what goes beyond it', () => {
  const w = boot();
  const data = full();
  data.panels.needs.data.cards.waiting[0].beyond = { from: 7, what: 'guests see the Pay button too' };
  data.panels.needs.data.cards.blocked[0].beyond = { from: 7, what: 'not shown on a blocked card' };
  deliver(w, data);
  const row = (x, key = 'waiting:c1-12') => panel(x, 'needs').querySelector(`li[data-key="${key}"]`);
  assert.equal(row(w).querySelector('.beyond').textContent, 'Goes beyond the yes of #7: guests see the Pay button too');
  assert.equal(row(w, 'blocked:c2-13').querySelector('.beyond'), null, 'only a card waiting for the yes says it');
  const noFrom = boot();
  const d2 = full();
  d2.panels.needs.data.cards.waiting[0].beyond = { from: null, what: ' guests pay ' };
  deliver(noFrom, d2);
  assert.equal(row(noFrom).querySelector('.beyond').textContent, "Goes beyond its parent's yes: guests pay");
  for (const beyond of [null, undefined, {}, { from: 7, what: '  ' }, 'beyond']) {
    const x = boot();
    const d = full();
    d.panels.needs.data.cards.waiting[0].beyond = beyond;
    deliver(x, d);
    assert.equal(row(x).querySelector('.beyond'), null, `no line for ${JSON.stringify(beyond)}`);
  }
});
