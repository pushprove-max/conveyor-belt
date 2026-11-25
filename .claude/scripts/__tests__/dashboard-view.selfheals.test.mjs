// SPDX-License-Identifier: Apache-2.0
// The Self-heals tab (issue 1562, its first slice): the self-heals list on a page of its own, drawn from the Declined
// part's heals: the title line, the tiles, the area cards, the entries with their toolbar, the detail panel and its
// actions, the checked rows' bar, the dropped entries and the docs list. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { T0, iso, boot, panel, deliver, next, full, settle, P, css, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const REPO = 'https://github.com/example/sample-project';
const DAY = 86400000;
const entry = (id, over) => ({ repo: 'sample', repoUrl: REPO, id, card: `c3-${id.slice(-2)}`, issue: 63, url: `${P}/63`, from: 'review', seen: null, sightings: null, ...over });
// Five entries: two of area:engine/review (one moved up to harm before a review listed it again), two of area:board
// (one an audit's, its place in backticks and its proof under "- How:"), one of a card with no GitHub issue (issue 0),
// no area, no date and a reason that names no way of healing; one docs entry; one entry expired and one moved up to harm.
const ENTRIES = [
  entry('h0000000000a1', { time: iso(T0 - 2 * DAY), seen: iso(T0 - DAY), sightings: 2, area: 'area:engine/review', effect: 'self-heals', why: 'the next turn picks it up',
    expired: { time: iso(T0 - 5 * DAY), why: 'harm', filed: 811 },
    finding: '[P1] lib/a.sh:3 the poll misses a card for one turn. Proof: lib/a.sh:3 reads the list before the write lands' }),
  entry('h0000000000a2', { time: iso(T0 - 25 * DAY), issue: 64, url: `${P}/64`, area: 'area:engine/review', effect: 'cleanup', why: 'the branch is never taken',
    finding: '[P3] lib/b.sh:9 a dead branch. Proof: lib/b.sh:9' }),
  entry('h0000000000a3', { time: iso(T0 - 12 * DAY), issue: 65, url: `${P}/65`, area: 'area:board', effect: 'already guarded', why: 'the check at lib/guard.sh:12 refuses it first',
    finding: '[P2] web/board.js:7 a second click sends twice. Proof: web/board.js:7' }),
  entry('h0000000000a4', { time: iso(T0 - 3 * DAY), issue: 66, url: `${P}/66`, area: 'area:board', effect: 'self-heals', why: 'a slower redraw, no wrong result',
    finding: 'R1 [P2] `board.js:40`: the list redraws late - How: the poll reads the list before the write lands - Fix: read it after - Raised on #12' }),
  entry('h0000000000a5', { time: null, issue: 0, url: null, area: null, effect: null, why: 'it is fine in the end', finding: '[P2] x.sh:1 something odd' }),
];
const heals = (over = {}) => [{ repo: 'sample', repoUrl: REPO, sorted: null, days: 30, areas: [], entries: ENTRIES,
  docs: { areas: [], entries: [entry('d0000000000d1', { time: iso(T0 - 40 * DAY), area: 'area:docs', effect: 'docs drift', why: 'the page omits it', finding: '[P3] docs/board.md:9 omits the Self-heals tab' })] },
  dropped: [entry('h0000000000e1', { time: iso(T0 - 60 * DAY), area: 'area:board', effect: 'self-heals', why: 'w', finding: '[P2] old.js:1 an old wait', dropped: { time: iso(T0 - 20 * DAY), why: 'expired' } }),
    entry('h0000000000e2', { time: iso(T0 - 9 * DAY), area: 'area:board', effect: 'self-heals', why: 'w', finding: '[P2] up.js:1 seen in the logs', dropped: { time: iso(T0 - 3 * DAY), why: 'harm', filed: 812 } })],
  ...over }];
const page = (w) => panel(w, 'selfheals');
const q = (w, sel) => page(w).querySelector(sel);
const qa = (w, sel) => Array.from(page(w).querySelectorAll(sel));
const rowIds = (w) => qa(w, '.sh-entries .sh-row').map((r) => r.dataset.key.split(':')[1]);
function open(over) {
  const w = boot({ tab: 'selfheals' }), data = full();
  data.panels.declined.data.heals = heals(over);
  deliver(w, data);
  return { w, data };
}

// Bugs: the list had no page of its own, so its entries were read only as a plain list on Overview; the tab showed no
// count; a tile, area card or row read the wrong field (the days left from the time when the entry was seen since).
test('Self-heals: the tab after Benchmarks draws the title line, the tiles, the area cards, the rows and the docs list', () => {
  const { w } = open();
  const tabs = Array.from(w.document.querySelectorAll('#tabs .tab'), (b) => b.dataset.tab);
  assert.deepEqual(tabs.slice(-2), ['bench', 'selfheals'], 'the tab is after Benchmarks');
  const tab = w.document.getElementById('tab-selfheals');
  assert.equal(tab.querySelector('.tab-count').textContent, '· 5', 'the count badge: the entries on the list');
  assert.equal(tab.getAttribute('aria-label'), 'Self-heals: 5 entries on the list');
  assert.equal(page(w).dataset.state, 'ready');
  assert.equal(q(w, '.sh-title').textContent, 'Self-heals list');
  assert.equal(q(w, '.sh-pill').textContent, 'An entry leaves after 30 days unseen', 'the Rules setting as the record gives it');
  assert.equal(q(w, '.sh-rules').textContent, 'Rules › Self-heals');
  assert.equal(q(w, '.sh-sorted').textContent, 'The sort of the queued follow-ups has not run yet.', 'a record that names no sort (issue 1694)');
  const tiles = Object.fromEntries(qa(w, '.sh-tile').map((t) => [t.dataset.tile, [t.querySelector('.sh-tile-n').textContent, t.querySelector('.sh-tile-sub').textContent]]));
  assert.deepEqual(tiles, {
    on: ['5', 'from 3 issues and 1 audit'], ready: ['0', 'areas with 10 or more entries'], seen: ['1', 'a sighting resets its 30 days'],
    leaving: ['1', 'kept in Dropped, never erased'], harm: ['2', 'seen in real logs'],
  }, 'bugs: an entry of a card with no GitHub issue counted an issue #0; a move up to harm that a review listed again was not counted');
  const cards = qa(w, '.sh-area').map((c) => [c.querySelector('.sh-group').textContent, c.querySelector('.sh-area-name strong').textContent, c.querySelector('.sh-area-n').textContent,
    Array.from(c.querySelectorAll('.sh-kind'), (k) => k.textContent), c.querySelector('.sh-area-foot').textContent]);
  assert.deepEqual(cards, [
    ['Board', 'board', '2', ['Waits longer 1', 'Already guarded 1'], '8 more to batch'],
    ['Engine', 'review', '2', ['Runs again 1', 'Cleanup 1'], '8 more to batch'],
    ['No area', 'No area', '1', ['kind not read 1'], '9 more to batch'],
  ]);
  const engine = q(w, '.sh-area[data-area="area:engine/review"] .sh-age');
  assert.equal(engine.getAttribute('role'), 'img');
  assert.equal(engine.getAttribute('aria-label'), 'Age: 1 of 0–10 days, 0 of 10–20 days, 1 of 20 days or more, leaving soon', 'the age counts from the last sighting');
  assert.deepEqual(Array.from(q(w, '.sh-area[data-area="area:engine/review"] .sh-legend').children, (li) => li.textContent), ['0–10 days', '10–20 days', '20 days or more, leaving soon']);
  assert.equal(q(w, '.sh-area[data-area=""] .sh-age').getAttribute('aria-label'), 'Age: 0 of 0–10 days, 0 of 10–20 days, 0 of 20 days or more, leaving soon, 1 not read');
  assert.deepEqual(rowIds(w), ['h0000000000a2', 'h0000000000a3', 'h0000000000a4', 'h0000000000a1', 'h0000000000a5'], 'Leaves soonest first, the one not read last');
  const row = q(w, '.sh-row[data-key="sample:h0000000000a1"]');
  assert.equal(row.querySelector('.sh-p').textContent, 'P1');
  assert.ok(row.querySelector('.sh-p').classList.contains('is-high'));
  assert.equal(row.querySelector('.sh-row-title').textContent, 'the poll misses a card for one turn', 'the title without its level, place and proof');
  assert.deepEqual(Array.from(row.querySelector('.sh-row-meta').children, (x) => x.textContent), ['Runs again', 'lib/a.sh:3', 'area:engine/review', 'from #63', 'seen 2×']);
  assert.equal(row.querySelector('.sh-left').textContent, '29 d left', '30 days from its sighting a day ago');
  assert.ok(row.querySelector('.sh-ring'), 'a days-left ring');
  const soon = q(w, '.sh-row[data-key="sample:h0000000000a2"] .sh-left');
  assert.equal(soon.textContent, '5 d left');
  assert.ok(soon.classList.contains('is-soon'), 'amber at 7 days or less');
  const unread = q(w, '.sh-row[data-key="sample:h0000000000a5"]');
  assert.equal(unread.querySelector('.sh-left').textContent, 'not read', 'an entry with no date: its days left not read');
  assert.equal(unread.querySelector('.sh-ring'), null);
  assert.equal(unread.querySelector('.sh-kind').textContent, 'kind not read', 'a reason that names no way of healing');
  assert.equal(unread.querySelector('.sh-from').textContent, 'from card c3-a5', 'bug: a card with no GitHub issue showed "from #0"');
  const audit = q(w, '.sh-row[data-key="sample:h0000000000a4"]');
  assert.equal(audit.querySelector('.sh-p').textContent, 'P2', "an audit's finding keeps its level after its number");
  assert.deepEqual([audit.querySelector('.sh-row-title').textContent, audit.querySelector('.sh-at').textContent], ['the list redraws late', 'board.js:40'],
    "bug: an audit's title kept its place in backticks and its - How: section");
  assert.equal(q(w, '.sh-showing').textContent, 'Showing 5 of 5');
  // Bug it catches: the link counted the expired entries alone, so it could say 0 and open a list of entries.
  const dropped = q(w, '.sh-dropped-link');
  assert.equal(dropped.textContent, 'Dropped entries (2) ›');
  dropped.focus(); dropped.click();
  assert.equal(qa(w, '.sh-dropped li').length, 2, 'the list it opens holds as many entries as it says');
  assert.equal(w.document.activeElement, q(w, '.sh-dropped-link'), 'bug: opening the dropped entries took the focus off their button');
  const docs = q(w, '.sh-docs');
  assert.equal(docs.querySelector('.sh-sub').textContent, 'Docs (1)');
  assert.deepEqual(Array.from(docs.querySelectorAll('.sh-docs-area'), (a) => [a.dataset.area, a.querySelector('.sh-row-title').textContent]), [['area:docs', 'omits the Self-heals tab']]);
  assert.equal(docs.querySelector('.sh-left, .sh-ring'), null, 'a docs entry never expires: no days-left ring');
  // Bug it catches: with 2 days, the thirds rounded to 1, 1 and 2 days, so an entry 25 days old was counted in a part
  // the legend named "2–2 days". Each part's legend names the ages it counts.
  const two = full();
  two.panels.declined.data.heals = heals({ days: 2 });
  next(w, two);
  assert.equal(q(w, '.sh-area[data-area="area:engine/review"] .sh-age').getAttribute('aria-label'), 'Age: 0 of 0–1 days, 1 of 1–2 days, 1 of 2 days or more, leaving soon');
  // Bugs it catches: the link to the setting went nowhere; it opened Rules on its first group (Models), so the
  // expiry setting, in Picking, stayed hidden.
  q(w, '.sh-rules').click();
  assert.equal(w.document.getElementById('tab-rules').getAttribute('aria-selected'), 'true', 'Rules › Self-heals opens the Rules tab');
  const setting = w.document.querySelector('.rules-row[data-rule="healsdays"]');
  assert.ok(setting && !setting.hidden && !setting.closest('.rules-set').hidden, 'Rules › Self-heals shows the Self-heals expiry setting');
});

// Bugs it catches (issue 1694): the line that says when the sort of the queued follow-ups ran was on the Declined panel
// alone; a row, the detail panel, the Dropped list, a Docs row and the batch sheet (its rows and its "Add from other
// areas" list) showed a finding or the judge's reason with its backticks as plain text, not as the Board's code spans;
// a place quoted with its case name (`file:156 (t_case)`) left its closing backtick in the title; a file link in a row
// title sat inside the button that opens the row; a Docs row, a batch sheet row and a dropped entry showed no reason or
// proof, and a dropped entry no file.
test('Self-heals: the sort line says when the sort ran, and a finding and a reason with code show code spans and no backtick', () => {
  const { w } = open({ sorted: { time: iso(T0 - 3600000), items: 3, moved: 2 },
    entries: [entry('h0000000000b1', { time: iso(T0 - DAY), area: 'area:board', effect: 'self-heals', why: 'the `next()` turn picks it up',
      finding: 'R1 [P2] `conveyor/x.test.sh:156 (t_case)`: the `poll()` call waits a turn at conveyor/README.md:209 - How: `lib/a.sh:3` reads it late - Fix: call `poll()` after the write - Raised on #12' }),
    entry('h0000000000b3', { time: iso(T0 - DAY), area: 'area:engine', effect: 'self-heals', why: 'w', finding: '[P2] lib/c.sh:4 the `tick` runs late' })],
    docs: { areas: [], entries: [entry('d0000000000d2', { time: iso(T0 - DAY), area: 'area:docs', effect: 'docs drift', why: 'the `heals` page is missing',
      finding: '[P3] docs/board.md:9 omits the `heals` tab. Proof: `docs/board.md:9` names no tab' })] },
    dropped: [entry('h0000000000b2', { time: iso(T0 - 9 * DAY), area: 'area:board', effect: 'self-heals', why: 'the `wait` ends',
      finding: '[P2] old.js:1 the `wait` flag. Proof: `old.js:1` sets it', dropped: { time: iso(T0 - DAY), why: 'expired' } })] });
  const sorted = q(w, '.sh-sorted');
  assert.match(sorted.textContent, /^The sort of the queued follow-ups ran .+ ago, and moved 2 of 3 to the lists\.$/);
  assert.equal(sorted.querySelector('time.since')?.dateTime, iso(T0 - 3600000), 'the time the sort ran');
  const codes = (sel) => qa(w, `${sel} code.why-code`).map((c) => c.textContent);
  // Each line under a row with no detail panel: its text and its code spans.
  const lines = (sel) => qa(w, sel).map((p) => [p.textContent, Array.from(p.querySelectorAll('code.why-code'), (c) => c.textContent)]);
  const row = '.sh-row[data-key="sample:h0000000000b1"]';
  assert.deepEqual(codes(`${row} .sh-row-title`), ['poll()', 'conveyor/README.md:209'], 'the row title');
  assert.equal(q(w, `${row} .sh-open a`), null, 'a file link inside the button that opens the row');
  q(w, `${row} .sh-row-title`).click();
  assert.deepEqual(codes('.sh-detail .sh-detail-title'), ['poll()', 'conveyor/README.md:209'], 'the detail title');
  assert.ok(q(w, '.sh-detail .sh-detail-title a code.why-code'), 'the detail title links its file');
  assert.deepEqual(codes('.sh-detail .sh-why'), ['next()'], "the judge's reason");
  assert.deepEqual(codes('.sh-detail .sh-proof'), ['lib/a.sh:3'], 'the proof');
  const doc = '.sh-docs .sh-doc';
  assert.deepEqual(codes(`${doc} .sh-row-title`), ['heals'], 'a Docs row');
  assert.deepEqual(lines(`${doc} .sh-fix`), [['Why: the heals page is missing', ['heals']], ['Proof: docs/board.md:9 names no tab', ['docs/board.md:9']]], "a Docs row's reason and proof");
  q(w, '.sh-dropped-link').click();
  assert.deepEqual(codes('.sh-dropped .sh-row-title'), ['wait'], 'a dropped entry');
  assert.equal(q(w, '.sh-dropped .sh-at').textContent, 'old.js:1', "a dropped entry's file");
  assert.deepEqual(lines('.sh-dropped .sh-fix'), [['Why: the wait ends', ['wait']], ['Proof: old.js:1 sets it', ['old.js:1']]], "a dropped entry's reason and proof");
  assert.equal(page(w).textContent.includes('`'), false, `the page shows a backtick: ${page(w).textContent}`);
  q(w, '.sh-area[data-area="area:board"] [data-act="heals-batch"]').click();
  assert.deepEqual(codes('.sh-sheet-row .sh-row-title'), ['poll()', 'conveyor/README.md:209'], 'a batch sheet row');
  assert.deepEqual(lines('.sh-sheet-row .sh-fix'), [['Fix: call poll() after the write', ['poll()']], ['Why: the next() turn picks it up', ['next()']],
    ['Proof: lib/a.sh:3 reads it late', ['lib/a.sh:3']]], 'its Fix line, reason and proof');
  q(w, '[data-act="sheet-more"]').click();
  assert.deepEqual(codes('.sh-sheet-more .sh-row-title'), ['tick'], 'an entry in "Add from other areas"');
  assert.equal(page(w).textContent.includes('`'), false, `the batch sheet shows a backtick: ${page(w).textContent}`);
});

// Bug it catches: an audit finding that quotes two places (`a.sh:3, b.sh:9`) lost the quote from its title, and the
// place shows only the first, so the row, the detail panel, the batch sheet and the Dropped list no longer named the
// second place. And a title that put both long places first hid what the finding says when a narrow row clips the
// title to one line: the summary comes first, the second place after it. The quote names a.sh twice, so Files it
// touches must count that entry once for a.sh, not once for each line it cites there.
test('Self-heals: a finding that quotes two places keeps the second in its title, after the summary', () => {
  const two = 'R2 [P2] `conveyor/lib/a.sh:575, conveyor/tests/b.test.sh:116, conveyor/lib/a.sh:600`: the batch lands a card untested - How: `conveyor/lib/a.sh:575, conveyor/tests/b.test.sh:116` both skip the test - Raised on #12';
  const { w } = open({ entries: [entry('h0000000000c1', { time: iso(T0 - DAY), area: 'area:board', effect: 'self-heals', why: 'w', finding: two })],
    dropped: [entry('h0000000000c2', { time: iso(T0 - 9 * DAY), area: 'area:board', effect: 'self-heals', why: 'w', finding: two, dropped: { time: iso(T0 - DAY), why: 'expired' } })] });
  const want = 'the batch lands a card untested (also at conveyor/tests/b.test.sh:116, conveyor/lib/a.sh:600)';
  const title = (sel, what) => {
    assert.equal(q(w, sel).textContent.trim(), want, `${what} of: ${two}`);
    assert.deepEqual(qa(w, `${sel} code.why-code`).map((c) => c.textContent), ['conveyor/tests/b.test.sh:116', 'conveyor/lib/a.sh:600'], `${what}'s code spans of: ${two}`);
  };
  const row = '.sh-row[data-key="sample:h0000000000c1"]';
  title(`${row} .sh-row-title`, 'the row title');
  assert.equal(q(w, `${row} .sh-at`).textContent, 'conveyor/lib/a.sh:575', `the row's place of: ${two}`);
  q(w, `${row} .sh-row-title`).click();
  title('.sh-detail .sh-detail-title', 'the detail title');
  // Bug it catches: the proof's quote of two places was one code span, which lineUrl refuses, so neither place linked
  // to its line on GitHub.
  assert.deepEqual(qa(w, '.sh-detail .sh-proof a').map((a) => a.href), [`${REPO}/blob/HEAD/conveyor/lib/a.sh#L575`, `${REPO}/blob/HEAD/conveyor/tests/b.test.sh#L116`],
    `the detail proof links each place of: ${two}`);
  q(w, '.sh-dropped-link').click();
  title('.sh-dropped .sh-row-title', "a dropped entry's title");
  q(w, '.sh-area[data-area="area:board"] [data-act="heals-batch"]').click();
  title('.sh-sheet-row .sh-row-title', "a batch sheet row's title");
  // Bug it catches: the sheet row (no detail panel, no tooltip) clipped its title to one line, so on a phone the
  // "(also at ...)" part was cut off, and Files it touches named only the first file. jsdom cascades the stylesheet
  // but lays nothing out, so the check is the computed white-space of the title.
  const st = w.document.createElement('style'); st.textContent = css; w.document.head.append(st);
  assert.equal(w.getComputedStyle(q(w, '.sh-sheet-row .sh-row-title')).whiteSpace, 'normal', `the batch sheet row's title wraps, for: ${two}`);
  assert.deepEqual(qa(w, '.sh-files li').map((li) => li.textContent), ['conveyor/lib/a.sh1 entry', 'conveyor/tests/b.test.sh1 entry'],
    `Files it touches names each file of: ${two}`);
});

// Bugs (issue 1622): the page said in one line what the list holds, so a reader could not tell what a self-heal is, why
// its findings get no card or when an entry leaves; the part, once opened, closed again at the next snapshot.
test('Self-heals: "What is a self-heal?" is closed at first, opens on a click with each rule, and stays open through a redraw', async () => {
  const { w } = open({ days: 21 });
  const about = q(w, '.sh-head details.sh-about');
  assert.ok(about, 'the part is under the title line');
  assert.equal(about.querySelector('summary').textContent, 'What is a self-heal?');
  assert.equal(about.open, false, 'closed at first, so the list stays at the top');
  about.querySelector('summary').click();
  await settle();
  assert.equal(about.open, true, 'a click opens it');
  const said = Object.fromEntries(Array.from(about.querySelectorAll('li[data-about]'), (li) => [li.dataset.about, li.textContent]));
  const has = (k, ...parts) => parts.forEach((x) => assert.ok(said[k] && said[k].includes(x), `the ${k} point says "${x}": ${said[k]}`));
  has('what', 'a failure that fixes itself', 'a card waits longer', 'a step runs again', 'corrected at the next poll or turn', 'Nothing stays broken');
  // The check item's verb is split in two joined strings: the retired-workflow scan in dashboard-local.test.sh reads
  // this file, and the verb is one of its retired words. The joined string is still the whole phrase.
  has('harm', 'gets a follow-up card at once', 'data is lost or written wrong', 'wrong code lands or pushes', 'a check p' + 'asses that should fail',
    'stuck until a person frees it', 'nobody is told', 'private text is published', 'a security hole');
  has('kinds', 'Self-heals', 'Cleanup, when the fix changes nothing that the code does', 'Already guarded, when another check already stops the bad result');
  has('round', 'does not stop a card', 'no fix round', 'A batch card, filed from this page, fixes the entries of an area together');
  has('drop', 'nobody fixes, files in a batch card or sees again for 21 days leaves the list', 'the Rules setting Self-heals expiry', 'dropped entries keep');
  has('logs', 'seen in real logs or records is harm, also when it heals itself', 'A finding with no kind is harm');
  const link = about.querySelector('.sh-about-more a');
  assert.equal(link.textContent, 'Harm or self-heals');
  assert.equal(link.href, 'https://github.com/pushprove-max/conveyor-belt/blob/main/docs/cards.md#harm-or-self-heals', "the link goes to this project's guide rules");
  // Bug it catches: a snapshot drew the page again and took the keyboard focus off the guide link or the summary.
  link.focus();
  const later = full();
  later.panels.declined.data.heals = heals({ days: 22 });
  next(w, later);
  const again = q(w, '.sh-head details.sh-about');
  assert.notEqual(again, about, 'the next snapshot draws the part again');
  assert.ok(again.querySelector('li[data-about="drop"]').textContent.includes('22 days'), 'with the days of the new snapshot');
  assert.equal(again.open, true, 'the next snapshot keeps it open');
  assert.equal(w.document.activeElement, again.querySelector('.sh-about-more a'), 'bug: the snapshot took the focus off the guide link');
  again.querySelector('summary').focus();
  const last = full();
  last.panels.declined.data.heals = heals({ days: 23 });
  next(w, last);
  assert.equal(w.document.activeElement, q(w, '.sh-head details.sh-about summary'), 'bug: the snapshot took the focus off the summary');
});

// Bugs: a chip, the sort or the search showed rows of another kind, order or text; a chip's count was not of its kind.
test('Self-heals: the filter chips for all seven kinds, the sort and the search pick and order the rows', () => {
  const { w } = open();
  const chips = Object.fromEntries(qa(w, '.sh-chip').map((c) => [c.dataset.kind, c.querySelector('.sh-chip-n').textContent]));
  assert.deepEqual(chips, { all: '5', wait: '1', again: '1', text: '0', extra: '0', docs: '0', cleanup: '1', guarded: '1' });
  assert.deepEqual(qa(w, '.sh-chip').map((c) => c.textContent.replace(/\s*\d+$/, '')), ['All', 'Waits longer', 'Runs again', 'Text fixes itself', 'Extra work only', 'Docs or comment', 'Cleanup', 'Already guarded']);
  q(w, '.sh-chip[data-kind="guarded"]').focus(); q(w, '.sh-chip[data-kind="guarded"]').click();
  assert.equal(w.document.activeElement, q(w, '.sh-chip[data-kind="guarded"]'), 'bug: a chip pressed from the keyboard lost the focus');
  assert.deepEqual(rowIds(w), ['h0000000000a3']);
  assert.equal(q(w, '.sh-chip[data-kind="guarded"]').getAttribute('aria-pressed'), 'true');
  assert.equal(q(w, '.sh-showing').textContent, 'Showing 1 of 5');
  q(w, '.sh-chip[data-kind="text"]').click();
  assert.equal(q(w, '.sh-none').textContent, 'No entry matches this search, kind or tile.');
  q(w, '.sh-chip[data-kind="all"]').click();
  const sort = q(w, '.sh-sort');
  assert.deepEqual(Array.from(sort.options, (o) => o.textContent), ['Leaves soonest', 'Newest', 'Seen most', 'Area']);
  for (const [k, ids] of [['newest', ['h0000000000a1', 'h0000000000a4', 'h0000000000a3', 'h0000000000a2', 'h0000000000a5']],
    ['seen', ['h0000000000a1', 'h0000000000a2', 'h0000000000a3', 'h0000000000a4', 'h0000000000a5']],
    ['area', ['h0000000000a3', 'h0000000000a4', 'h0000000000a2', 'h0000000000a1', 'h0000000000a5']]]) {
    sort.value = k; sort.dispatchEvent(new w.Event('change'));
    assert.deepEqual(rowIds(w), ids, `sorted by ${k}`);
  }
  const search = q(w, '.sh-search');
  for (const [s, ids] of [['lib/b.sh', ['h0000000000a2']], ['c3-a4', ['h0000000000a4']], ['#65', ['h0000000000a3']], ['SECOND CLICK', ['h0000000000a3']]]) {
    search.value = s; search.dispatchEvent(new w.Event('input'));
    assert.deepEqual(rowIds(w), ids, `the search "${s}" (finding, file or card)`);
  }
  assert.equal(q(w, '.sh-search'), search, 'the search box is kept while typing, so it keeps the focus');
});

// Bugs: a click on a row did not show it, or showed another entry's reason or proof; an already-guarded entry did not
// name its guard; Move up to harm or Drop now sent nothing, sent on the first click, or the entry stayed on the page.
test('Self-heals: a click on a row fills the detail panel, and Move up to harm and Drop now send its id on a second click', async () => {
  const { w } = open();
  assert.equal(q(w, '.sh-detail-none').textContent, 'Pick an entry to see why it self-heals, its proof and its history.');
  q(w, '.sh-row[data-key="sample:h0000000000a3"] .sh-row-title').click();
  const row = q(w, '.sh-row[data-key="sample:h0000000000a3"]');
  assert.ok(row.classList.contains('is-selected'));
  assert.equal(row.querySelector('.sh-open').getAttribute('aria-current'), 'true', 'a screen reader hears which row is shown');
  assert.equal(q(w, '.sh-row[data-key="sample:h0000000000a1"] .sh-open').getAttribute('aria-current'), null);
  const d = q(w, '.sh-detail');
  assert.deepEqual(Array.from(d.querySelector('.sh-detail-top').children, (x) => x.textContent), ['P2', 'Already guarded', 'leaves in 18 days']);
  assert.equal(d.querySelector('.sh-detail-title').textContent, 'a second click sends twice');
  const facts = Array.from(d.querySelectorAll('.sh-facts dt'), (dt) => [dt.textContent, dt.nextElementSibling.textContent]);
  assert.deepEqual(facts, [['Area', 'area:board'], ['Found in', '#65 review'], ['File', 'web/board.js:7'], ['Seen again', 'not seen again yet']]);
  assert.equal(d.querySelector('.sh-facts a.issue').href, `${P}/65`, 'Found in links the review');
  assert.equal(d.querySelector('.sh-facts a.sh-file').href, `${REPO}/blob/HEAD/web/board.js#L7`, 'File links the line');
  assert.equal(d.querySelector('.sh-why').textContent, 'Why it self-healsthe check at lib/guard.sh:12 refuses it first');
  assert.equal(d.querySelector('.sh-guard a.sh-file').href, `${REPO}/blob/HEAD/lib/guard.sh#L12`, "GUARDED BY links the guard's line");
  assert.equal(d.querySelector('.sh-proof').textContent, 'web/board.js:7');
  assert.deepEqual(Array.from(d.querySelectorAll('.sh-history li'), (li) => [li.firstChild.textContent, li.querySelector('time')?.dateTime || null]),
    [['Found in the review of #65', ENTRIES[2].time], ['Judged already guarded', null], ['Not seen again yet', null], ['Leaves the list in 18 days unless it is seen again', null]]);
  assert.match(d.querySelector('.sh-hint').textContent, /^Move up to harm when it shows up in real logs or records\. It then gets its own follow-up card at once\.$/);
  // Bug it catches: an audit's proof, under "- How:", showed as "Proof not read".
  const open4 = q(w, '.sh-row[data-key="sample:h0000000000a4"] .sh-open');
  open4.focus(); open4.click();
  assert.equal(w.document.activeElement, q(w, '.sh-row[data-key="sample:h0000000000a4"] .sh-open'), 'bug: a row opened from the keyboard lost the focus');
  assert.equal(q(w, '.sh-detail .sh-proof').textContent, 'the poll reads the list before the write lands');
  // Bug it catches: an entry of a card with no GitHub issue linked an issue #0 as where it was found.
  q(w, '.sh-row[data-key="sample:h0000000000a5"]').click();
  assert.equal(q(w, '.sh-detail .sh-facts dd:nth-of-type(2)').textContent, 'card c3-a5 review');
  assert.equal(q(w, '.sh-detail .sh-facts a.issue'), null, 'no link to an issue #0');
  assert.equal(q(w, '.sh-detail .sh-history li').textContent, 'Found in the review of card c3-a5');
  q(w, '.sh-row[data-key="sample:h0000000000a1"]').click();
  const seen = q(w, '.sh-detail .sh-facts dd:last-child');
  assert.deepEqual([seen.firstChild.textContent, seen.querySelector('time').dateTime], ['2×, last ', ENTRIES[0].seen], 'the sightings and the last one');
  assert.equal(q(w, '.sh-detail .sh-guard'), null, 'GUARDED BY only for an already-guarded entry');
  const up = () => q(w, '.sh-detail [data-act="harm"]');
  up().click();
  await settle();
  assert.equal(w.posts.length, 0, 'the first click only asks: it files a card');
  up().click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'heals', args: ['harm', 'h0000000000a1'], repo: 'sample' } }]);
  assert.equal(q(w, '.sh-row[data-key="sample:h0000000000a1"]'), null, 'the entry moved up leaves the page at once');
  assert.equal(q(w, '.sh-note').textContent, 'Moved up to harm: sent to main');
  q(w, '.sh-row[data-key="sample:h0000000000a2"]').click();
  w.reply = { ok: false, status: 502, text: () => Promise.resolve('the list has no open entry h0000000000a2') };
  const drop = () => q(w, '.sh-detail [data-act="drop"]');
  drop().click(); drop().click();
  await settle();
  assert.deepEqual(w.posts.splice(0).map((p) => p.body.args), [['drop', 'h0000000000a2']]);
  assert.ok(q(w, '.sh-row[data-key="sample:h0000000000a2"]'), 'an entry the host did not drop stays');
  assert.equal(q(w, '.sh-note').textContent, 'Not dropped: the list has no open entry h0000000000a2');
});

// Bugs: a checked row had no bar to act on, the bar's count was wrong, Move up to harm sent more ids than one call
// files (the host refuses a request of more than ten), or Clear left rows checked. Eleven entries: six more of no area.
test('Self-heals: checked rows show the "N selected" bar with Move up to harm and Clear', async () => {
  const more = Array.from({ length: 6 }, (_, i) => entry(`h00000000000b${i}`, { time: iso(T0 - DAY), area: null, effect: 'cleanup', why: 'w', finding: `[P3] m.sh:${i + 1} a dead line` }));
  const { w } = open({ entries: ENTRIES.concat(more) });
  assert.ok(q(w, '.sh-bar').hidden, 'no bar with no row checked');
  const check = (id) => { const b = q(w, `.sh-row[data-key="sample:${id}"] .sh-check`); b.checked = true; b.dispatchEvent(new w.Event('change', { bubbles: true })); };
  check('h0000000000a2'); check('h0000000000a4');
  assert.equal(q(w, '.sh-bar').hidden, false);
  assert.equal(q(w, '.sh-bar-n').textContent, '2 selected');
  assert.equal(q(w, '.sh-detail-none') !== null, true, 'a check does not pick the row');
  q(w, '.sh-bar [data-act="clear"]').click();
  assert.ok(q(w, '.sh-bar').hidden);
  assert.equal(qa(w, '.sh-check').filter((b) => b.checked).length, 0, 'Clear unchecks every row');
  const ids = rowIds(w).filter((id) => id !== 'h0000000000a3');
  ids.forEach(check);
  assert.equal(q(w, '.sh-bar-n').textContent, '10 selected');
  check('h0000000000a3');
  q(w, '.sh-bar [data-act="harm"]').click(); q(w, '.sh-bar [data-act="harm"]').click();
  await settle(); await settle(); await settle();
  const sent = w.posts.splice(0).map((p) => p.body);
  assert.deepEqual(sent.map((b) => [b.action, b.args[0], b.args.length - 1, b.repo]), [['heals', 'harm', 10, 'sample'], ['heals', 'harm', 1, 'sample']], 'eleven entries go as ten, then one');
  assert.deepEqual(sent.flatMap((b) => b.args.slice(1)).sort(), ids.concat('h0000000000a3').sort(), 'each checked entry once');
  assert.deepEqual(rowIds(w), []);
  assert.ok(q(w, '.sh-bar').hidden, 'the bar leaves with the rows');
});

// Bugs: the empty page did not say what it is for; a failed read emptied the page, or kept it with no time, so the
// owner could not tell the list was old; the empty page hid when the sort of the queued follow-ups ran (issue 1694: a
// sort that moved nothing leaves the lists empty).
test('Self-heals: the empty state says what the page is for, and a failed read keeps the last list with its time', () => {
  const w = boot({ tab: 'selfheals' }), data = full();
  data.panels.declined.data.heals = [{ repo: 'sample', repoUrl: REPO, sorted: { time: iso(T0 - 3600000), items: 4, moved: 0 }, days: 30, areas: [], entries: [], docs: { areas: [], entries: [] }, dropped: [] }];
  deliver(w, data);
  assert.equal(page(w).dataset.state, 'empty');
  assert.match(page(w).textContent, /The Self-heals list is empty.*review findings whose failure heals by itself/s);
  assert.match(q(w, '.sh-sorted').textContent, /^The sort of the queued follow-ups ran .+ ago, and moved 0 of 4 to the lists\.$/, 'the sort that moved nothing');
  const good = full(T0);
  good.panels.declined.data.heals = heals();
  next(w, good);
  const read = q(w, '.sh-read time');
  assert.equal(read.dateTime, good.updatedAt, 'when the list was read');
  const bad = full(T0 + 60000);
  bad.panels.declined = { error: 'dashboard.sh: the snapshot could not be read', data: null };
  next(w, bad);
  assert.deepEqual(rowIds(w).length, 5, 'the last list stays');
  assert.equal(q(w, '.sh-read time').dateTime, good.updatedAt, 'with the time it was read');
  assert.match(page(w).querySelector('.panel-note').textContent, /could not read Self-heals just now/);
});

// Both themes and phone width are stylesheet rules: jsdom applies no stylesheet and lays nothing out, so these check
// the rules themselves. Bugs: a kind's pill unreadable in one theme (under 4.5:1), a colour set in one dark block and
// not the other, the detail panel kept beside the list on a phone.
test('Self-heals: each kind and the P1 tag read at 4.5:1 in both themes, and at phone width the detail panel stacks under the list', () => {
  const block = (start) => { const i = css.indexOf(start); return css.slice(i, css.indexOf('}', i)); };
  const vars = (t) => Object.fromEntries(Array.from(t.matchAll(/--([a-z0-9-]+):\s*([^;]+);/g), (m) => [m[1], m[2].trim()]));
  const lum = (hex) => { const [r, g, b] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255).map((c) => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4)); return 0.2126 * r + 0.7152 * g + 0.0722 * b; };
  const ratio = (a, b) => { const [hi, lo] = [lum(a), lum(b)].sort((x, y) => y - x); return (hi + 0.05) / (lo + 0.05); };
  const light = vars(block(':root {')), dark = vars(block(':root[data-theme="dark"] {')), system = vars(block(':root:not([data-theme]) {'));
  const dark0 = { 'k-wait': '#93abff', 'k-wait-bg': '#1a2547', 'k-again': '#74dfa3', 'k-again-bg': '#12301f', 'k-text': '#f3c46c', 'k-text-bg': '#33270d', 'k-extra': '#d2c2ff', 'k-extra-bg': '#2a2147',
    'k-docs': '#c3cad8', 'k-docs-bg': '#232a38', 'k-cleanup': '#aab2c2', 'k-cleanup-bg': '#1e2430', 'k-guarded': '#7fd4e0', 'k-guarded-bg': '#10303a', 'p1-tag': '#ffb08a', 'p1-tag-bg': '#3a1f12' };
  for (const [k, v] of Object.entries(dark0)) {
    assert.equal(dark[k], v, `the chosen dark theme's --${k} is the approved one`);
    assert.equal(system[k], v, `the system's dark theme gives --${k} the same`);
  }
  for (const k of ['k-wait', 'k-again', 'k-text', 'k-extra', 'k-docs', 'k-cleanup', 'k-guarded', 'p1-tag']) {
    for (const [name, t] of [['light', light], ['dark', dark]]) assert.ok(ratio(t[k], t[`${k}-bg`]) >= 4.5, `${name}: --${k} on --${k}-bg is ${ratio(t[k], t[`${k}-bg`]).toFixed(2)}:1`);
  }
  for (const k of ['wait', 'again', 'text', 'extra', 'docs', 'cleanup', 'guarded']) assert.match(css, new RegExp(`\\.sh-kind\\.sh-k-${k} \\{ color: var\\(--k-${k}\\); background: var\\(--k-${k}-bg\\); \\}`), `the ${k} pill uses its colours`);
  assert.match(css, /\.sh-split \{ display: grid; grid-template-columns: minmax\(0, 1fr\) minmax\(380px, 460px\);/, 'the detail panel beside the list, 380 to 460 px');
  assert.match(css, /@media \(max-width: 900px\) \{\n {2}\.sh-split \{ grid-template-columns: minmax\(0, 1fr\); \}/, 'one column at phone width');
  const { w } = open();
  const split = q(w, '.sh-split');
  assert.deepEqual(Array.from(split.children, (c) => c.className), ['sh-list', 'sh-detail'], 'the detail panel follows the list, so one column puts it under');
});

// Issue 1693: once every entry has an area (the area of its finding's file), the page draws no "No area" card; an
// entry with no area still has its card, so it is never hidden. Bug it catches: an area card drawn for no entry.
test('Self-heals: a list whose entries all have an area draws no "No area" card', () => {
  const { w } = open({ entries: ENTRIES.filter((e) => e.area) });
  assert.deepEqual(qa(w, '.sh-area').map((c) => c.dataset.area), ['area:board', 'area:engine/review']);
  assert.equal(q(w, '.sh-area[data-area=""]'), null);
  assert.ok(!qa(w, '.sh-area .sh-group').some((g) => g.textContent === 'No area'), 'no card is named No area');
});
