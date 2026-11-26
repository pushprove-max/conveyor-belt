// SPDX-License-Identifier: Apache-2.0
// Issue 1685: a blocked card the Foreman has (the snapshot's foreman note: conveyor.sh foreman note) on the Board, in
// its Needs you column and in Overview's Needs you panel. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { T0, iso, P, VIEW, boot, panel, deliver, next, settle, full, bcard, column, inCol, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

// The blocked cards of one record's snapshot: #13 the Foreman has (a live note), #14 waits for the owner's answer to
// the Foreman's picker, #15 has no note.
const SNAP_BLOCKED = [
  { card: 'c2-13', issue: 13, title: 'Broken build', reason: 'tests failed twice', since: iso(T0 - 900000),
    foreman: { note: 'traced run in progress, then hand land and retry', ask: false, since: iso(T0 - 300000) } },
  { card: 'c7-14', issue: 14, title: 'Second break', reason: 'tests failed twice', since: iso(T0 - 60000),
    foreman: { note: 'which of two fixes to land', ask: true, since: iso(T0 - 120000) } },
  { card: 'c8-15', issue: 15, title: 'Third break', reason: 'tests failed twice', since: iso(T0 - 60000) },
];
// #16, blocked after the snapshot's build, with the Foreman's note: its records hold it (recordsNow), and the print of
// the snapshot adds it to needsYou.blocked with fromRecords (conveyor.sh snapshot), as it does every noted card.
const FRESH = { card: 'c9-16', issue: 16, title: 'Fourth break', reason: 'tests failed twice', since: iso(T0 - 40000),
  foreman: { note: 'fix card filed', ask: false, since: iso(T0 - 35000) } };
// #17, with a note in the snapshot, retried since: the live feed's retried line names it, and its records no longer
// hold it blocked, but the next snapshot has not come.
const RETRIED = { card: 'c10-17', issue: 17, title: 'Fifth break', reason: 'tests failed twice', since: iso(T0 - 60000),
  foreman: { note: 'hand run in progress', ask: false, since: iso(T0 - 50000) } };

// The Board's part and Overview's Needs you part of those cards, as the collector cuts them from the snapshot: one
// `dashboard.sh --publish` (its panels, PANELS_JQ in dashboard_panels.sh) on a live feed of that snapshot, with no host
// to read. Run here rather than written by hand: a note the collector drops (a part that leaves out foreman) must fail
// these cases, and only the collector's own run shows that. One run, for both cases.
function collected() {
  const t = fs.mkdtempSync(path.join(os.tmpdir(), 'foreman-note-'));
  try {
    const out = path.join(t, 'out'), cache = path.join(out, 'cache'), main = path.join(t, 'main');
    for (const d of [cache, path.join(main, 'conveyor'), path.join(t, 'home'), path.join(t, 'ws'), path.join(t, 'scratch')]) fs.mkdirSync(d, { recursive: true });
    fs.writeFileSync(path.join(main, 'conveyor', 'host.json'), JSON.stringify({ host: 'devbox', ssh: 'devbox', main: '/srv/main', records: [{ repo: 'sample', main: '/srv/main' }] }));
    const now = iso(T0 - 30000);
    // Its records are newer than its build: they hold the three blocked still, and #16, blocked since, with its note.
    const recordsNow = { waiting: [], blocked: [...SNAP_BLOCKED.map(({ card, issue, title, reason, since, foreman }) => ({ card, issue, title, reason, since, ...(foreman ? { foreman } : {}) })), FRESH] };
    const snap = { time: now, day: now.slice(0, 10), needsYou: { waiting: [], blocked: [...SNAP_BLOCKED, RETRIED, { ...FRESH, fromRecords: true }], before: [] }, recordsNewer: true, recordsNow, belt: [], queue: { next: [] }, landed: [], landedCount: 0,
      health: { time: now, loop: true, newest: now, blocked: [], waiting: [], stuck: [], unpushed: [], pushError: null, pushFailingSince: null, gh: true, ghReached: false, diskFreeKb: 500000000, builderCap: 3, models: { claude: 'claude-x', codex: 'gpt-x' } },
      cost: { today: 0, week: 0, perLanded: null, landedAfter: { 1: 0, 2: 0, 3: 0, more: 0 }, unpricedSteps: 0, cards: [] } };
    fs.writeFileSync(path.join(out, 'stream.json'), JSON.stringify({ host: 'devbox', reachable: true, error: null, records: [{ repo: 'sample', snap, retried: [{ card: RETRIED.card, issue: 17, at: now }] }], stream: { live: true, heardAt: now, since: null, error: null } }));
    const parts = { foremen: { foremen: [], error: null }, limit: { limit: { limit: null }, error: null }, decisions: { decisions: [], unsent: [], error: null }, lanes: { records: [], error: null } };
    for (const [k, v] of Object.entries(parts)) fs.writeFileSync(path.join(cache, `part-${k}.json`), JSON.stringify(v));
    const env = { ...process.env, HOME: path.join(t, 'home'), CONVEYOR_HOST_OS: 'Linux', CONVEYOR_MAIN: main, CONVEYOR_WORKSPACES: path.join(t, 'ws'), CONVEYOR_SCRATCH: path.join(t, 'scratch'), CONVEYOR_DASHBOARD_DIR: out };
    delete env.XDG_CONFIG_HOME; delete env.CONVEYOR_HOOK_FIRE_LOG;
    execFileSync('bash', [path.join(VIEW, '..', 'scripts', 'dashboard.sh'), '--publish'], { env, timeout: 30000, stdio: ['ignore', 'ignore', 'pipe'] });
    const data = JSON.parse(fs.readFileSync(path.join(out, 'data.js'), 'utf8').replace(/^window\.DASH = /, '').replace(/;\s*$/, ''));
    // The page's links come from the record's remote, which this record has none of.
    const linked = (xs) => xs.map((x) => ({ ...x, url: `${P}/${x.issue}` }));
    return { board: linked(data.panels.board.data.others.sample.blocked), needs: linked(data.panels.needs.data.cards.blocked) };
  } finally {
    fs.rmSync(t, { recursive: true, force: true });
  }
}
const COLLECTED = collected();

// The page's data with the collected blocked cards in place of the fixture's, in the Board's column (less #17, which
// the case below checks) and Overview's panel; retried: the cards the host already gave back (the Needs you part's retried).
function withNotes(retried = []) {
  const d = full();
  d.panels.board.data.blocked = COLLECTED.board.filter((x) => x.card !== RETRIED.card).map((x) => ({ ...x }));
  d.panels.needs.data.cards.blocked = COLLECTED.needs.map((x) => ({ ...x }));
  d.panels.needs.data.retried = retried;
  return d;
}

// Bugs it catches: the collector drops the note, so the card shows its bare block reason; the card the Foreman took
// shows no note, no age and no sign that it is the Foreman's; it is mixed in with the cards that wait for the owner; a
// card that waits for the owner's answer does not say so; a card with no note does not show as before.
test("the Board's Needs you column shows a blocked card's live Foreman note with its age, apart from the cards that wait for the owner", () => {
  const w = boot({ tab: 'control' });
  deliver(w, withNotes());
  assert.deepEqual(inCol(w, 'needs'), [12, 14, 15, 13, 16], 'the Foreman\'s #13 and #16 come after the cards that wait for the owner');
  assert.deepEqual(Array.from(column(w, 'needs').querySelectorAll('.board-apart'), (x) => x.textContent), ['Foreman has it'], 'one heading sets it apart');
  assert.equal(bcard(w, 13).previousElementSibling.className, 'board-apart', 'the heading is right above #13');
  assert.ok(bcard(w, 13).classList.contains('is-foreman') && !bcard(w, 13).classList.contains('is-blocked'), '#13 is marked the Foreman\'s');
  assert.equal(bcard(w, 13).querySelector(':scope > .chip').textContent, 'Foreman has it');
  assert.equal(bcard(w, 13).querySelector('.board-foreman').textContent, 'Foreman: traced run in progress, then hand land and retry · 5 min ago', 'the note and its age');
  assert.equal(bcard(w, 13).querySelector('.why-said'), null, 'the note is in place of the block reason');
  // #16, blocked after the build, comes in needsYou.blocked from the print of the snapshot (conveyor/tests/
  // snapblock.test.sh t_foremannote checks that it is added). Bug it catches: the column dropped such a card's note.
  assert.match(bcard(w, 16).querySelector('.board-foreman').textContent, /^Foreman: fix card filed · /, '#16, blocked after the build, shows its note');
  assert.equal(bcard(w, 14).querySelector('.board-foreman.is-ask').textContent, 'Waits for your answer: which of two fixes to land · 2 min ago');
  assert.ok(bcard(w, 14).classList.contains('is-blocked'), '#14 waits for the owner');
  // With no note, the card is as before: Blocked, its reason, no note.
  assert.ok(bcard(w, 15).classList.contains('is-blocked'));
  assert.equal(bcard(w, 15).querySelector(':scope > .chip').textContent, 'Blocked');
  assert.equal(bcard(w, 15).querySelector('.board-foreman'), null);
  assert.match(bcard(w, 15).querySelector('.why-said').textContent, /tests failed twice/);
});

// Bug it catches: the "Foreman has it" heading is an item of the column's list, and "Show 100 more" focuses the item
// at the old count: with 100 cards that wait for the owner before the Foreman's #13, the heading took the focus, not #13.
test("the Board's Needs you column focuses the first new card, not the Foreman heading, after Show more", () => {
  const w = boot({ tab: 'control' });
  const d = withNotes();
  // #12 waits for the owner's yes; 99 more blocked with no note make 100 cards that wait for the owner, then #13.
  const none = COLLECTED.board.find((x) => x.card === 'c8-15');
  d.panels.board.data.blocked = [...Array.from({ length: 99 }, (_, i) => ({ ...none, card: `c${100 + i}-${2000 + i}`, issue: 2000 + i })), { ...COLLECTED.board.find((x) => x.card === 'c2-13') }];
  deliver(w, d);
  assert.equal(inCol(w, 'needs').length, 100, 'the first page holds the 100 cards that wait for the owner');
  column(w, 'needs').querySelector('[data-act="list-more"]').click();
  assert.equal(w.document.activeElement, bcard(w, 13), `the focus is on #13, not on ${w.document.activeElement.className}`);
});

test("Overview's Needs you panel shows a blocked card's live Foreman note with its age, after the cards that wait for the owner", () => {
  const w = boot({ list: ['needs'] });
  deliver(w, withNotes());
  const rows = Array.from(panel(w, 'needs').querySelectorAll('[data-group="blocked"] .rows > li'));
  assert.deepEqual(rows.map((li) => li.dataset.card.split('\n')[1]), ['c7-14', 'c8-15', 'c9-16', 'c2-13'], 'the Foreman\'s c9-16 and c2-13 come after the cards that wait for the owner');
  const [asks, none, fresh, mine] = rows;
  assert.ok(mine.classList.contains('is-foreman') && !asks.classList.contains('is-foreman') && !none.classList.contains('is-foreman'));
  assert.equal(mine.querySelector('.row-main .chip').textContent, 'Foreman has it');
  assert.equal(mine.querySelector('.foreman-note').textContent, 'Foreman: traced run in progress, then hand land and retry · 5 min ago', 'the note and its age');
  // A card blocked after the build, which the records alone hold, carries its note too.
  assert.ok(fresh.classList.contains('is-foreman'), 'c9-16, from the records, is marked the Foreman\'s');
  assert.match(fresh.querySelector('.foreman-note').textContent, /^Foreman: fix card filed · /);
  assert.equal(asks.querySelector('.row-main .chip').textContent, 'Blocked');
  assert.equal(asks.querySelector('.foreman-note.is-ask').textContent, 'Waits for your answer: which of two fixes to land · 2 min ago');
  // With no note, the row is as before: Blocked, its reason, no note.
  assert.equal(none.querySelector('.row-main .chip').textContent, 'Blocked');
  assert.equal(none.querySelector('.foreman-note'), null);
  assert.match(none.textContent, /tests failed twice/);
});

// Bug it catches: a card retried (its host gave it back, before the snapshot that drops it) still drawn with the
// Foreman's note, though the retry ended the note.
test("Overview's Needs you panel shows no Foreman note on a card its host already retried", () => {
  const w = boot({ list: ['needs'] });
  deliver(w, withNotes([{ repo: 'sample', card: 'c2-13' }]));
  const rows = Array.from(panel(w, 'needs').querySelectorAll('[data-group="blocked"] .rows > li'));
  const again = rows.find((li) => li.dataset.card.split('\n')[1] === 'c2-13');
  assert.equal(again.querySelector('.row-main .chip').textContent, 'Retried, waiting for its turn');
  assert.equal(again.querySelector('.foreman-note'), null, 'the retried card shows no note');
  assert.ok(!again.classList.contains('is-foreman'));
});

// Bug it catches: a new Foreman note changes the row's key, so the row is drawn anew; only a row first drawn from its
// records (':records') got its focus and a button clicked once back, so a Retry clicked once was cancelled and the
// focus was lost when the note changed.
test("Overview's Needs you panel keeps a Retry clicked once, and the focus on it, when the card's Foreman note changes", async () => {
  const w = boot({ list: ['needs'] });
  deliver(w, withNotes());
  const row = () => Array.from(panel(w, 'needs').querySelectorAll('[data-group="blocked"] .rows > li')).find((li) => li.dataset.card.split('\n')[1] === 'c2-13');
  const retry = () => row().querySelector('button[data-act="retry"]');
  const was = row();
  retry().focus();
  retry().click();
  await settle();
  assert.deepEqual(w.posts, [], 'the first click only asks');
  const d = withNotes();
  d.panels.needs.data.cards.blocked.find((x) => x.card === 'c2-13').foreman = { note: 'fix card filed', ask: false, since: iso(T0 - 10000) };
  next(w, d);
  assert.notEqual(row(), was, 'the row was drawn anew for the new note');
  assert.match(row().querySelector('.foreman-note').textContent, /^Foreman: fix card filed · /);
  assert.equal(w.document.activeElement, retry(), 'the focus is on the new row\'s Retry');
  retry().click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'retry', args: ['13'], repo: 'sample' } }], 'the second click retries');
});

// Bugs it catches: a card the owner held (Hold gives it back as retry does, its issue held: the retried line's held)
// kept the Foreman's note, which the Hold ended, until the next snapshot; and a held row drawn anew, which loses the
// Undo of the Hold.
test("Overview's Needs you panel takes the Foreman note off a card its host gave back held, in the same row", () => {
  const w = boot({ list: ['needs'] });
  deliver(w, withNotes());
  const row = () => Array.from(panel(w, 'needs').querySelectorAll('[data-group="blocked"] .rows > li')).find((li) => li.dataset.card.split('\n')[1] === 'c2-13');
  const was = row();
  // The page's next refresh asks for data.js again; next() answers that request.
  next(w, withNotes([{ repo: 'sample', card: 'c2-13', issue: 13, held: true }]));
  assert.equal(row(), was, 'the held row is the same node, so the Undo of its Hold stays');
  assert.equal(row().querySelector('.foreman-note'), null, 'the held card shows no note');
  assert.ok(!row().classList.contains('is-foreman'));
  assert.equal(row().querySelector('.row-main .chip').textContent, 'Blocked', 'held is not "Retried, waiting for its turn" nor the Foreman\'s');
});

// Bug it catches: the Board's Needs you column, drawn from the snapshot alone, keeps the Foreman's note on a card the
// live feed already says was retried (#17), where Overview's panel shows it retried, until the next snapshot comes.
test("the Board's Needs you column shows no Foreman note on a card its host already retried", () => {
  const got = COLLECTED.board.find((x) => x.card === RETRIED.card);
  assert.ok(got, `the Board's part has no ${RETRIED.card}: ${JSON.stringify(COLLECTED.board.map((x) => x.card))}`);
  assert.equal(got.foreman, null, `the Board's part of ${RETRIED.card}, retried with the note ${JSON.stringify(RETRIED.foreman)}, keeps it: ${JSON.stringify(got.foreman)}`);
  assert.deepEqual(COLLECTED.board.find((x) => x.card === 'c2-13').foreman, SNAP_BLOCKED[0].foreman, 'a card not retried keeps its note');
});
