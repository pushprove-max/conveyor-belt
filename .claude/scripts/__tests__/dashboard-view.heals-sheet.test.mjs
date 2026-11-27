// SPDX-License-Identifier: Apache-2.0
// The Self-heals page's batch sheet (issue 1562, its second slice): File a batch card and File docs sweep card, opened
// from an area card, the checked rows' bar, the detail panel and the docs list; the entries kept or left out, the
// card's title and level, and the filing (`heals batch|docs`) with the kept entries alone. Shared setup:
// dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { T0, iso, boot, panel, deliver, next, full, settle, P, css, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const REPO = 'https://github.com/example/sample-project';
const DAY = 86400000;
const entry = (id, over) => ({ repo: 'sample', repoUrl: REPO, id, card: `c3-${id.slice(-2)}`, issue: 63, url: `${P}/63`, from: 'review', seen: null, sightings: null, ...over });
// Two entries of area:engine/review, both in lib/a.sh (28 and 5 days left of 30); two of area:board, one an audit's
// with its "- Fix:" line; one docs entry.
const A1 = 'h0000000000a1', A2 = 'h0000000000a2', A3 = 'h0000000000a3', A4 = 'h0000000000a4', D1 = 'd0000000000d1';
const ENTRIES = [
  entry(A1, { time: iso(T0 - 2 * DAY), area: 'area:engine/review', effect: 'self-heals', why: 'the next turn picks it up', finding: '[P1] lib/a.sh:3 the poll misses a card for one turn. Proof: lib/a.sh:3' }),
  entry(A2, { time: iso(T0 - 25 * DAY), area: 'area:engine/review', effect: 'cleanup', why: 'the branch is never taken', finding: '[P3] lib/a.sh:9 a dead branch. Proof: lib/a.sh:9' }),
  entry(A3, { time: iso(T0 - 12 * DAY), area: 'area:board', effect: 'already guarded', why: 'the check at lib/guard.sh:12 refuses it first', finding: '[P2] web/board.js:7 a second click sends twice. Proof: web/board.js:7' }),
  entry(A4, { time: iso(T0 - 3 * DAY), area: 'area:board', effect: 'self-heals', why: 'a slower redraw, no wrong result',
    finding: 'R1 [P2] `board.js:40`: the list redraws late - How: the poll reads the list before the write lands - Fix: read it after the write - Raised on #12' }),
];
const page = (w) => panel(w, 'selfheals');
const q = (w, sel) => page(w).querySelector(sel);
const qa = (w, sel) => Array.from(page(w).querySelectorAll(sel));
const sheetIds = (w) => qa(w, '.sh-sheet-entries > .sh-rows .sh-sheet-row').map((r) => [r.dataset.key.split(':')[1], r.classList.contains('is-out')]);
const keep = (w, id, on) => { const b = q(w, `.sh-sheet-row[data-key="sample:${id}"] .sh-check`); b.checked = on; b.dispatchEvent(new w.Event('change', { bubbles: true })); };
const act = (w, a) => q(w, `[data-act="${a}"]`);
const DOC1 = entry(D1, { time: iso(T0 - 40 * DAY), area: 'area:docs', effect: 'docs drift', why: 'the page omits it', finding: '[P3] docs/board.md:9 omits the Self-heals tab' });
// The page's lists: the sample project's, with <docs> as its docs entries, then <more> (other projects' lists).
const heals = (docs = [DOC1], more = []) => [{ repo: 'sample', repoUrl: REPO, sorted: null, days: 30, areas: [], entries: ENTRIES, dropped: [], docs: { areas: [], entries: docs } }, ...more];
function open(docs, more) {
  const w = boot({ tab: 'selfheals' }), data = full();
  data.panels.declined.data.heals = heals(docs, more);
  deliver(w, data);
  return w;
}

// Bugs: an area had no way to file its batch card from the page; the sheet filed every entry of the area, also one the
// owner left out (it left the list, unfixed); an entry added from another area was not sent; the title did not follow
// the entries kept; after filing, a left-out entry left the list or lost its days.
test('Batch sheet: Review batch on an area card keeps and leaves out entries, adds one of another area, and files the kept ones', async () => {
  const w = open();
  q(w, '.sh-area[data-area="area:engine/review"] [data-act="heals-batch"]').click();
  assert.equal(q(w, '.sh-entries'), null, 'the sheet is drawn in place of the page');
  assert.equal(w.document.activeElement, q(w, '.sh-sheet-title'), 'the focus goes to the sheet');
  assert.equal(q(w, '.sh-crumb').textContent, 'Self-heals list › Engine › review');
  assert.equal(q(w, '.sh-sheet-title').textContent, 'File a batch card');
  assert.deepEqual(qa(w, '.sh-sheet-head .sh-acts button').map((b) => b.textContent), ['Cancel', 'File held', 'File and queue · 2 entries']);
  assert.equal(q(w, '.sh-sheet-n').textContent, 'Entries in this card 2 of 2');
  assert.deepEqual(sheetIds(w), [[A2, false], [A1, false]], 'the area\'s entries, leaving soonest first, each kept');
  const row2 = q(w, `.sh-sheet-row[data-key="sample:${A2}"]`);
  assert.deepEqual([row2.querySelector('.sh-key').textContent, row2.querySelector('.sh-row-title').textContent, row2.querySelector('.sh-kind').textContent,
    row2.querySelector('.sh-at').textContent, row2.querySelector('.sh-left-n').textContent], [A2, 'a dead branch', 'Cleanup', 'lib/a.sh:9', '5 d left']);
  assert.equal(q(w, '.sh-sheet-name').value, 'Self-heals batch: review (2 entries)');
  assert.deepEqual(qa(w, '.sh-sheet-prio option').map((o) => [o.value, o.selected]), [['P3', true], ['P2', false]], 'P3 by default, or P2');
  assert.equal(q(w, '.sh-sheet-card .sh-facts dd').textContent, 'area:engine/review');
  assert.deepEqual(qa(w, '.sh-files li').map((li) => li.textContent), ['lib/a.sh2 entries'], 'bug it catches: each line of a file counted as a file of its own');
  assert.match(q(w, '.sh-how').textContent, /^How this card is reviewedEach entry is done when its Proof no longer holds\./);
  assert.match(q(w, '.sh-sheet-card .sh-hint').textContent, /^When the card lands, its entries leave the list as fixed\./);
  assert.equal(q(w, '.sh-sheet-foot').textContent, 'An entry you leave out stays on the list with its days left.');
  // Phone width is a stylesheet rule (jsdom lays nothing out): the sheet's two sides are the page's .sh-split, whose
  // rule puts them in one column, the card under the entries.
  assert.deepEqual(Array.from(q(w, '.sh-sheet-split').classList), ['sh-split', 'sh-sheet-split']);
  assert.match(css, /\.sh-how \{[^}]*background: var\(--info-bg\);/, 'the How box uses the theme\'s info colours, set in both themes');

  keep(w, A2, false);
  assert.deepEqual(sheetIds(w), [[A2, true], [A1, false]], 'the entry left out stays in the sheet, dimmed');
  // Bug it catches: the left-out row was dimmed with opacity, which blends each tag's text into its badge (the light
  // P1 tag fell to about 2.5:1, under 4.5:1). The row is marked apart from a kept row with no opacity on it or in it.
  const st = w.document.createElement('style'); st.textContent = css; w.document.head.append(st);
  const out = q(w, `.sh-sheet-row[data-key="sample:${A2}"]`), kept = q(w, `.sh-sheet-row[data-key="sample:${A1}"]`);
  for (const el of [out, ...out.querySelectorAll('*')]) assert.equal(w.getComputedStyle(el).opacity, '1', `opacity of ${el.className || el.tagName} in the left-out row`);
  assert.notEqual(w.getComputedStyle(out).backgroundColor, w.getComputedStyle(kept).backgroundColor, 'a left-out row looks apart from a kept one');
  assert.equal(q(w, '.sh-sheet-n').textContent, 'Entries in this card 1 of 2');
  assert.equal(act(w, 'sheet-queue').textContent, 'File and queue · 1 entry');
  assert.equal(q(w, '.sh-sheet-name').value, 'Self-heals batch: review (1 entry)', 'the title follows the entries kept until it is edited');
  assert.deepEqual(qa(w, '.sh-files li').map((li) => li.textContent), ['lib/a.sh1 entry'], 'a left-out entry touches no file');
  act(w, 'sheet-keep-all').click();
  assert.deepEqual(sheetIds(w), [[A2, false], [A1, false]], 'Keep all keeps each again');
  keep(w, A2, false);
  act(w, 'sheet-more').click();
  assert.deepEqual(qa(w, '.sh-sheet-more li').map((li) => li.dataset.key.split(':')[1]), [A3, A4], 'the entries of the other areas, not the docs entry');
  q(w, `.sh-sheet-more li[data-key="sample:${A4}"] [data-act="sheet-add"]`).click();
  const row4 = q(w, `.sh-sheet-row[data-key="sample:${A4}"]`);
  assert.equal(row4.querySelector('.sh-fix').textContent, 'Fix: read it after the write', "an audit entry's Fix: line");
  assert.equal(q(w, '.sh-sheet-n').textContent, 'Entries in this card 2 of 3');

  act(w, 'sheet-queue').click();
  await settle();
  assert.equal(w.posts.length, 0, 'the first click only asks');
  act(w, 'sheet-queue').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'heals', repo: 'sample',
    args: ['batch', 'area:engine/review', '--queue', '--prio', 'P3', '--title', 'Self-heals batch: review (2 entries)', A1, A4] } }], 'the kept entries alone, of both areas');
  assert.equal(q(w, '.sh-sheet'), null, 'filed, the sheet closes');
  assert.equal(q(w, '.sh-note').textContent, 'Filed: sent to main');
  assert.equal(q(w, `.sh-entries .sh-row[data-key="sample:${A2}"] .sh-left`).textContent, '5 d left', 'the entry left out is still on the list with its days left');
});

// Bugs: Add to the <area> batch in the detail panel did nothing; File held queued the card; an edited title or level was
// not sent; a blank title could be filed; a refusal closed the sheet, so the owner lost what was chosen.
test('Batch sheet: from the detail panel, File held sends the edited title and level, and a refusal keeps the sheet', async () => {
  const w = open();
  q(w, `.sh-row[data-key="sample:${A3}"]`).click();
  const add = q(w, '.sh-detail [data-act="heals-batch"]');
  assert.equal(add.textContent, 'Add to the board batch');
  add.click();
  assert.deepEqual(sheetIds(w), [[A3, false], [A4, false]]);
  const name = q(w, '.sh-sheet-name');
  name.value = '  '; name.dispatchEvent(new w.Event('input'));
  assert.ok(act(w, 'sheet-held').disabled && act(w, 'sheet-queue').disabled, 'no filing with a blank title');
  name.value = 'Board: two late redraws'; name.dispatchEvent(new w.Event('input'));
  assert.ok(!act(w, 'sheet-held').disabled && !act(w, 'sheet-queue').disabled, 'bug it catches: a title typed after a blank one left both buttons off');
  const prio = q(w, '.sh-sheet-prio');
  prio.value = 'P2'; prio.dispatchEvent(new w.Event('change'));
  w.reply = { ok: false, status: 502, text: () => Promise.resolve('conveyor: the self-heals list has no open entry h0000000000a3; nothing filed') };
  act(w, 'sheet-held').click(); act(w, 'sheet-held').click();
  await settle();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [['batch', 'area:board', '--held', '--prio', 'P2', '--title', 'Board: two late redraws', A3, A4]]);
  assert.equal(q(w, '.sh-sheet .sh-note').textContent, 'Not filed: conveyor: the self-heals list has no open entry h0000000000a3; nothing filed');
  assert.equal(q(w, '.sh-sheet-name').value, 'Board: two late redraws', 'the sheet keeps what was chosen');
  act(w, 'sheet-cancel').click();
  assert.equal(q(w, '.sh-sheet'), null);
  assert.ok(q(w, `.sh-entries .sh-row[data-key="sample:${A3}"]`), 'Cancel goes back to the page');
});

// Bugs: the checked rows' bar had no File a batch card, or its sheet held other entries than those checked; the sheet
// was labelled with an area that held fewer of them.
test('Batch sheet: File a batch card on the checked rows holds the rows checked, under the area of most of them', () => {
  const w = open();
  for (const id of [A1, A3, A4]) { const b = q(w, `.sh-row[data-key="sample:${id}"] .sh-check`); b.checked = true; b.dispatchEvent(new w.Event('change', { bubbles: true })); }
  q(w, '.sh-bar [data-act="heals-batch"]').click();
  assert.equal(q(w, '.sh-crumb').textContent, 'Self-heals list › Board › board');
  assert.deepEqual(sheetIds(w), [[A1, false], [A3, false], [A4, false]]);
  assert.equal(q(w, '.sh-sheet-card .sh-facts dd').textContent, 'area:board');
});

// Bug: the No area sheet said the card gets no area label ("none: the entries have no area"), but it sends '-', and
// `heals batch -` labels the card with the area of the file its first entry names, else the map's other (lib/heals.sh).
test('Batch sheet: the No area sheet says the engine sets the area label when it files, and sends -', async () => {
  const N1 = 'h0000000000n1', w = boot({ tab: 'selfheals' }), data = full();
  data.panels.declined.data.heals = [{ repo: 'sample', repoUrl: REPO, sorted: null, days: 30, areas: [], dropped: [], docs: { areas: [], entries: [] },
    entries: [entry(N1, { time: iso(T0 - 2 * DAY), area: null, effect: 'cleanup', why: 'x', finding: '[P3] the poll names no file' })] }];
  deliver(w, data);
  q(w, '.sh-area[data-area=""] [data-act="heals-batch"]').click();
  assert.equal(q(w, '.sh-sheet-card .sh-facts dd').textContent,
    'Set when filed: the area of the file that the entry added first names, else the other area of the pack\'s area map. With no map, none.');
  act(w, 'sheet-queue').click(); await settle(); act(w, 'sheet-queue').click(); await settle();
  assert.equal(w.posts.splice(0)[0].body.args[1], '-', 'the No area sheet sends - for the engine to label the card');
});

// Bug: Add from other areas offered the rows of the sheet's own area that were not checked, under a control that
// names other areas.
test('Batch sheet: Add from other areas offers no row of the sheet\'s own area', () => {
  const w = open();
  const b = q(w, `.sh-row[data-key="sample:${A3}"] .sh-check`); b.checked = true; b.dispatchEvent(new w.Event('change', { bubbles: true }));
  q(w, '.sh-bar [data-act="heals-batch"]').click();
  act(w, 'sheet-more').click();
  assert.deepEqual(qa(w, '.sh-sheet-more li').map((li) => li.dataset.key.split(':')[1]), [A1, A2], `the sheet of area:board offered ${A4} of area:board`);
});

// Bug: with rows checked in two projects, File a batch card opened a sheet of one project and dropped the other's rows
// with no word to the owner.
test('Batch sheet: rows checked in two projects file no batch card, and the bar says why', () => {
  const B1 = 'h0000000000b1';
  const w = open(undefined, [{ repo: 'other', repoUrl: 'https://github.com/example/other', sorted: null, days: 30, areas: [], dropped: [], docs: { areas: [], entries: [] },
    entries: [entry(B1, { repo: 'other', repoUrl: 'https://github.com/example/other', time: iso(T0 - 2 * DAY), area: 'area:board', effect: 'cleanup', why: 'x', finding: '[P3] x.js:1 a dead line' })] }]);
  for (const k of [`sample:${A3}`, `other:${B1}`]) { const b = q(w, `.sh-row[data-key="${k}"] .sh-check`); b.checked = true; b.dispatchEvent(new w.Event('change', { bubbles: true })); }
  const file = q(w, '.sh-bar [data-act="heals-batch"]');
  assert.ok(file.disabled, 'File a batch card is off for rows of two projects');
  assert.equal(q(w, '.sh-bar .sh-hint').textContent, 'A batch card is for one project. Check the entries of one project only.');
  file.click();
  assert.equal(q(w, '.sh-sheet'), null, 'no sheet opens');
});

// Bug: a sheet open when its last entry left the list stayed set behind the empty view, and the next nonempty read
// drew that old sheet in place of the page.
test('Batch sheet: a sheet whose list empties is closed, and a later entry shows the page', () => {
  const w = open();
  q(w, '.sh-docs-area[data-area="area:docs"] [data-act="heals-docs"]').click();
  assert.ok(q(w, '.sh-sheet'));
  const empty = full();
  empty.panels.declined.data.heals = [{ repo: 'sample', repoUrl: REPO, sorted: null, days: 30, areas: [], entries: [], dropped: [], docs: { areas: [], entries: [] } }];
  next(w, empty);
  assert.equal(q(w, '.sh-sheet'), null, 'the empty view');
  const back = full();
  back.panels.declined.data.heals = heals();
  next(w, back);
  assert.equal(q(w, '.sh-sheet'), null, 'the old sheet came back');
  assert.ok(q(w, '.sh-entries'), 'the page is drawn');
});

// Bugs: a docs area had no File docs sweep card; its sheet filed a self-heals batch card, or showed days left for
// entries that never expire; a docs entry left out was filed too (the docs sweep filed its whole area).
test('Batch sheet: File docs sweep card files a docs sweep card of the docs entries kept', async () => {
  const D2 = 'd0000000000d2';
  const w = open([DOC1, entry(D2, { time: iso(T0 - 5 * DAY), area: 'area:docs', effect: 'docs drift', why: 'the page omits it', finding: '[P3] docs/commands.md:4 omits heals' })]);
  q(w, '.sh-docs-area[data-area="area:docs"] [data-act="heals-docs"]').click();
  assert.equal(q(w, '.sh-sheet-title').textContent, 'File a docs sweep card');
  assert.equal(q(w, '.sh-sheet-name').value, 'Docs sweep: docs (2 entries)');
  assert.deepEqual(sheetIds(w), [[D2, false], [D1, false]]);
  assert.equal(q(w, '.sh-sheet-row .sh-left-n, .sh-sheet-row .sh-kind'), null, 'no days left and no kind for a docs entry');
  assert.equal(q(w, '.sh-sheet-foot').textContent, 'An entry you leave out stays on the docs list.');
  keep(w, D2, false);
  act(w, 'sheet-queue').click(); act(w, 'sheet-queue').click();
  await settle();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [['docs', 'area:docs', '--queue', '--prio', 'P3', '--title', 'Docs sweep: docs (1 entry)', D1]]);
});
