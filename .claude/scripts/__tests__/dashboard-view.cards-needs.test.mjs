// SPDX-License-Identifier: Apache-2.0
// The dashboard page's cards: the rest of Needs you (an answer names its card's repository, a whole test failing on
// main, a plugin commit not taken, an issue waiting for the yes, a held pipeline change), Declined, a review's judge
// line, a card passed on re-run, a slow-test note, and Needs you and the belt from a snapshot behind the card records.
// Shared setup: dashboard-view.helpers.mjs.
// Its cases run one after another in one thread, not in cases()'s workers: each worker loads jsdom and warms its code
// again, and for these 14 cases that cost about twice the CPU of one thread (#586).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { T0, iso, clone, boot, panel, deliver, next, settle, P, trackOf, counts, full, openEvery, tabBtn, fig } from './dashboard-view.helpers.mjs';

// Needs you lists the cards of every record, so the answer carries the card's repository with its number.
// Bug: only the number was sent, and the host acted on main's issue of that number: approving another repository's
// #12 approved and resumed the main record's #12.
test("Needs you: an answer names the card's repository, and a card that names none is not sent", async () => {
  const w = boot();
  const data = full();
  data.panels.needs.data.cards.waiting.push({ repo: 'widgetshop', card: 'c9-12', issue: 12, title: 'Other button', sentence: 'Users see a toggle.', since: data.panels.needs.data.cards.waiting[0].since, url: null });
  deliver(w, data);
  const btn = (card, k) => panel(w, 'needs').querySelector(`li[data-key="waiting:${card}"] button[data-act="${k}"]`);
  w.reply = { ok: true, status: 200, text: () => Promise.resolve('conveyor: issue #12 can be picked again') };
  btn('c9-12', 'approve').click();
  btn('c9-12', 'approve').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'approve', args: ['12'], repo: 'widgetshop' } }]);
  const n = boot();
  const none = full();
  delete none.panels.needs.data.cards.waiting[0].repo;
  deliver(n, none);
  const row = panel(n, 'needs').querySelector('li[data-key="waiting:c1-12"]');
  row.querySelector('button[data-act="approve"]').click();
  row.querySelector('button[data-act="approve"]').click();
  await settle();
  assert.deepEqual(n.posts, [], 'nothing is sent without the repository');
  assert.equal(row.querySelector('.yes .answer-note').textContent, 'Not sent: the Board does not know which repository #12 is in.');
});

// The whole test runs on main after landings, not in each card: its failure is no card's, so it has a row of its own.
test('Needs you: a whole test failing on main shows its issue, the failing cases and the commits it failed between', () => {
  const w = boot();
  const data = full();
  const since = data.panels.needs.data.cards.waiting[0].since;
  data.panels.needs.data.tests = [{ repo: 'sample', issue: 15, url: `${P}/15`, cases: ['alpha', 'beta'], from: 'a'.repeat(40), to: 'b'.repeat(40), since }];
  const count = () => Number(panel(w, 'needs').querySelector('.panel-count').textContent);
  deliver(w, data);
  const with1 = count();
  const group = panel(w, 'needs').querySelector('[data-group="tests"]');
  assert.equal(group.hidden, false);
  assert.equal(group.querySelector('.group-title').textContent, 'Tests failing on main');
  const row = group.querySelector('li[data-key="tests:sample"]');
  assert.match(row.querySelector('.row-main').textContent, /#15.*The whole test fails on main.*Tests failing/s);
  assert.equal(row.querySelector('a.issue').href, `${P}/15`);
  assert.deepEqual([...row.querySelectorAll('.reason')].map((p) => p.textContent),
    ['Failing cases: alpha, beta', `Failed at ${'b'.repeat(12)}. It last passed at ${'a'.repeat(12)}.`]);
  // A record with none has no group, and one less to count.
  data.panels.needs.data.tests = [];
  next(w, data);
  assert.equal(count(), with1 - 1, 'it is counted with the rest while it fails');
  assert.equal(panel(w, 'needs').querySelector('[data-group="tests"]').hidden, true);
});

// A project that follows the plugin's main and did not take its newest commit stays on its old engine: no card says so,
// so it has a row of its own. Bug: the project ran old code for good, and nothing on the Board said why.
test('Needs you: a commit of the plugin main a project did not take shows the commit and why', () => {
  const w = boot();
  const data = full();
  const since = data.panels.needs.data.cards.waiting[0].since;
  data.panels.needs.data.engines = [{ repo: 'sample', commit: 'c'.repeat(40), reason: 'it lacks hooks .claude/settings.json runs through shim.sh: .claude/hooks/x.sh', since }];
  const count = () => Number(panel(w, 'needs').querySelector('.panel-count').textContent);
  deliver(w, data);
  const with1 = count();
  const group = panel(w, 'needs').querySelector('[data-group="engines"]');
  assert.equal(group.hidden, false);
  assert.equal(group.querySelector('.group-title').textContent, 'Engine updates not taken');
  const row = group.querySelector(`li[data-key="engine:sample@${'c'.repeat(40)}"]`);
  assert.match(row.querySelector('.row-main').textContent, new RegExp(`The project did not take Conveyor commit ${'c'.repeat(12)}.*Engine update refused`, 's'));
  assert.equal(row.querySelector('.reason').textContent, 'it lacks hooks .claude/settings.json runs through shim.sh: .claude/hooks/x.sh');
  data.panels.needs.data.engines = [];
  next(w, data);
  assert.equal(count(), with1 - 1, 'it is counted with the rest until a later commit is taken');
  assert.equal(panel(w, 'needs').querySelector('[data-group="engines"]').hidden, true);
});

// Issue 519: a run of the test rules that matched more files than one day's cap filed none of them (the burst guard).
// Bug it catches: the run was held and the Board said nothing, so the rules waited for the owner unseen.
test('Needs you: a run of the test rules held by the burst guard shows one line with the counts', () => {
  const w = boot();
  const data = full();
  const time = data.panels.needs.data.cards.waiting[0].since;
  data.panels.needs.data.testRules = [{ repo: 'sample', time, matched: 5, cap: 3 }];
  const count = () => Number(panel(w, 'needs').querySelector('.panel-count').textContent);
  deliver(w, data);
  const with1 = count();
  const group = panel(w, 'needs').querySelector('[data-group="testRules"]');
  assert.equal(group.hidden, false);
  assert.equal(group.querySelector('.group-title').textContent, 'Test issues held');
  assert.equal(group.querySelectorAll('li').length, 1);
  assert.match(group.querySelector(`li[data-key="testrules:sample@${time}"] .row-main`).textContent,
    /The test rules matched 5 test files in one run, more than the 3 a day\. Conveyor filed none of them\..*Nothing filed/s);
  data.panels.needs.data.testRules = [];
  next(w, data);
  assert.equal(count(), with1 - 1, 'it is counted with the rest while the run is held');
  assert.equal(panel(w, 'needs').querySelector('[data-group="testRules"]').hidden, true);
});

// Bug (#1074): Conveyor filed a held issue in the project's repository for each model with no price. It files none
// now, so Needs you is where the owner learns of them: one line a project that counts them, with a link that opens
// the list in Model prices; with the prices added (no model left) the line goes. Bug (review of #1074): with every
// project shown and the Rules tab drawn for sample, the link for widgetshop set ?repo= but the Rules panel, its part
// unchanged, kept sample's Model prices.
test('Needs you: the models with no price show as one line that counts them and opens Model prices', async () => {
  const w = boot();
  const data = full();
  data.panels.machine.data.repos = ['sample', 'widgetshop'];
  Object.assign(data.panels.rules.data, { repos: ['sample', 'widgetshop'], others: { widgetshop: { ...clone(data.panels.rules.data), repo: 'widgetshop' } } });
  data.panels.needs.data.prices = [{ repo: 'widgetshop', models: ['claude-new-9', 'm'] }];
  const count = () => Number(panel(w, 'needs').querySelector('.panel-count').textContent);
  deliver(w, data);
  const with1 = count();
  const group = panel(w, 'needs').querySelector('[data-group="prices"]');
  assert.equal(group.hidden, false);
  assert.equal(group.querySelector('.group-title').textContent, 'Models with no price');
  assert.equal(group.querySelectorAll('li').length, 1, 'one line, not one a model');
  const row = group.querySelector('li[data-key="prices:widgetshop:claude-new-9,m"]');
  assert.equal(row.querySelector('.row-main').textContent, '2 models have no price, so the Board cannot show what they cost.');
  assert.match(row.querySelector('a[data-act="prices-see"]').getAttribute('href'), /\?tab=rules&repo=widgetshop#panel-rules-prices$/);
  data.panels.needs.data.prices = [{ repo: 'widgetshop', models: [] }];
  next(w, data);
  assert.equal(count(), with1 - 1, 'it is counted with the rest until the prices are added');
  assert.equal(panel(w, 'needs').querySelector('[data-group="prices"]').hidden, true);
  data.panels.needs.data.prices = [{ repo: 'widgetshop', models: ['claude-new-9', 'm'] }];
  next(w, data);
  tabBtn(w, 'rules').click();
  await settle();
  assert.equal(panel(w, 'rules').querySelector('.panel-title').textContent, 'Rules: sample', 'the Rules tab is drawn for sample first');
  tabBtn(w, 'overview').click();
  panel(w, 'needs').querySelector('a[data-act="prices-see"]').click();
  await settle();
  assert.equal(tabBtn(w, 'rules').getAttribute('aria-selected'), 'true', 'the link opens the Rules tab');
  assert.equal(w.document.activeElement, panel(w, 'rules-prices'), 'on Model prices');
  assert.match(panel(w, 'rules').querySelector('.panel-title').textContent, /widgetshop/, 'of the row\'s project');
  assert.equal(new URL(w.location.href).searchParams.get('repo'), 'widgetshop');
});

// An issue whose section "What customers or staff will see" names a change waits for the owner's yes before it is
// built. Bug: it was built first, and only then did it stop for their yes, so a no wasted the build and the reviews.
test('Needs you: an issue waiting for the yes before its build shows its section and the three actions', async () => {
  const w = boot();
  const data = full();
  const section = 'The Pay page: today a grey Pay button.\nIt will show a green one.';
  data.panels.needs.data.cards.before = [{ repo: 'sample', issue: 14, title: 'Green Pay', section, since: data.panels.needs.data.cards.waiting[0].since, url: `${P}/14` }];
  deliver(w, data);
  const group = panel(w, 'needs').querySelector('[data-group="before"]');
  assert.equal(group.hidden, false);
  assert.equal(group.querySelector('.group-title').textContent, 'Approve before build');
  const row = group.querySelector('li[data-key="before:sample#14"]');
  assert.ok(row, 'the issue is listed');
  assert.match(row.querySelector('.row-main').textContent, /#14.*Green Pay.*Approve before build/s);
  assert.equal(row.querySelector('pre.seen').textContent, section, 'the section as the issue says it, line breaks kept');
  const btn = (k) => row.querySelector(`button[data-act="${k}"]`);
  assert.deepEqual(['approve', 'condition', 'decline'].map((k) => btn(k).textContent), ['Approve', 'Approve with this condition', 'Decline']);
  assert.equal(row.querySelector('.yes-files'), null, 'nothing is built yet: no files');
  assert.equal(panel(w, 'needs').querySelector('.panel-count').textContent, '4', 'counted with the rest');
  const note = () => row.querySelector('.yes .answer-note').textContent;
  btn('approve').click();
  assert.match(note(), /the approval goes on the issue, and Conveyor builds the issue in its turn/);
  w.reply = { ok: true, status: 200, text: () => Promise.resolve('conveyor: issue #14 is approved before its build; it is picked in its turn') };
  btn('approve').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'approve', args: ['14'], repo: 'sample' } }]);
  assert.match(note(), /^Approved: #14 leaves Needs you in about a minute, and Conveyor builds it in its turn\.$/);
  // With a condition, and declined with why, from their own rows.
  const c = boot();
  deliver(c, data);
  const crow = panel(c, 'needs').querySelector('li[data-key="before:sample#14"]');
  crow.querySelector('input[aria-label="Condition for the yes to #14"]').value = 'staff only';
  crow.querySelector('button[data-act="condition"]').click();
  crow.querySelector('button[data-act="condition"]').click();
  await settle();
  assert.deepEqual(c.posts.splice(0), [{ url: 'control', body: { action: 'approve', args: ['14', 'staff only'], repo: 'sample' } }]);
  const d = boot();
  deliver(d, data);
  const drow = panel(d, 'needs').querySelector('li[data-key="before:sample#14"]');
  drow.querySelector('input[aria-label="Why not, for #14"]').value = 'not now';
  drow.querySelector('button[data-act="decline"]').click();
  assert.match(drow.querySelector('.yes .answer-note').textContent, /the reason goes on the issue, and the issue stays held/);
  drow.querySelector('button[data-act="decline"]').click();
  await settle();
  assert.deepEqual(d.posts.splice(0), [{ url: 'control', body: { action: 'decline', args: ['14', 'not now'], repo: 'sample' } }]);
  assert.match(drow.querySelector('.yes .answer-note').textContent, /^Declined: your reason is on the issue\. #14 leaves Needs you in about a minute\. It stays held, and Conveyor does not build it\. To build it, queue it on the Board/);
  // None: the group is hidden. Not read: it says so, never nothing.
  // Each on the next data of the first page, as the owner's page gets them.
  next(w, full());
  assert.equal(panel(w, 'needs').querySelector('[data-group="before"]').hidden, true);
  const u = full();
  u.panels.needs.data.cards.before = null;
  next(w, u);
  const ug = panel(w, 'needs').querySelector('[data-group="before"]');
  assert.equal(ug.hidden, false);
  assert.match(ug.querySelector('.warn-note').textContent, /The Board could not read the issues that wait for your yes/);
  // Not read, with nothing else waiting: still not "Nothing needs you".
  const b = full();
  Object.assign(b.panels.needs.data.cards, { before: null, waiting: [], blocked: [] });
  b.panels.needs.data.decisions = [];
  next(w, b);
  assert.doesNotMatch(panel(w, 'needs').textContent, /Nothing needs you/);
  assert.match(panel(w, 'needs').querySelector('[data-group="before"] .warn-note').textContent, /The Board could not read the issues that wait for your yes/);
});

// Bugs: the Declined panel lists the findings in another order than the collector's newest first, or without who
// declined one and why; "File as issue" sends on the first click, sends another line's id or another project's, or is
// still offered for a finding already filed (dashboard-view.overview.test.mjs: Declined, Show every line).
test('Declined: the findings newest first with who and why; "File as issue", confirmed, asks the host to file that finding once', async () => {
  const w = boot();
  const data = full();
  data.panels.declined.data.lines.unshift({ repo: 'widgetshop', id: 'd00000000000c', time: iso(T0 - 60000), card: 'c4-5', issue: 5, url: null, finding: '[P2] c.txt:3 a nit', by: 'owner', why: 'not worth a card', built: null });
  deliver(w, data);
  const rows = () => Array.from(panel(w, 'declined').querySelectorAll('.rows > .row'));
  assert.deepEqual(rows().map((r) => r.querySelector('.title').textContent), ['[P2] c.txt:3 a nit', '[P1] b.txt:2 no mark here'], 'newest first, as the collector gives them');
  assert.deepEqual(rows().map((r) => [r.querySelector('.reason .why-label').textContent, r.querySelector('.reason .why-text').textContent]),
    [['Why the owner declined it', 'not worth a card'], ['Why the judge declined it', 'its proof needs a stub built to misbehave']], 'who declined it, then why');
  assert.match(rows()[0].textContent, /declined by the owner/);
  const b = rows()[1].querySelector('button[data-act="build"]');
  assert.equal(b.textContent, 'File as issue', 'it says what it does: it files an issue, it builds nothing now');
  b.click();
  await settle();
  assert.equal(w.posts.length, 0, 'the first click only asks');
  assert.equal(b.textContent, 'Click again to file it as an issue', 'armed, it says what the next click does');
  b.click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'build', args: ['d0123456789ab'], repo: 'sample' } }]);
  assert.match(rows()[1].querySelector('.answer-note').textContent, /^Filed as an issue: Conveyor builds it in its turn\. The line shows this in about a minute\.$/);
  assert.ok(rows()[1].classList.contains('is-pending') && b.hidden, 'filed, the line is greyed in place and its button gone');
  b.click();
  await settle();
  assert.equal(w.posts.length, 0, 'once sent, the same line is not sent again');
  // The host refuses: the line says why and can be asked again.
  w.reply = { ok: false, status: 502, text: () => Promise.resolve('buildhost did not answer') };
  const o = rows()[0].querySelector('button[data-act="build"]');
  o.click(); o.click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'build', args: ['d00000000000c'], repo: 'widgetshop' } }]);
  assert.match(rows()[0].querySelector('.answer-note').textContent, /^Not filed: buildhost did not answer/);
  assert.equal(o.disabled, false);
});

// Bugs: a card's review steps say nothing of the judge, so the owner cannot tell a GO the judge made from the
// reviewer's own (a GO only because every finding was declined read as a clean review); a review the judge did not
// read carries a judge line, so it reads as one the judge looked at; the declined count leads nowhere, or to every
// card's lines; Landed today has no totals for the day, or adds every project's into one.
test("a review step says what the judge made of it, in flight and landed, and one it did not read has no judge line; its declined count opens that card's lines in Declined; Landed today totals the day for each project", () => {
  const w = boot();
  const data = full();
  const r = (round, verdict, fixed, judge) => ({ round, verdict, counts: counts(0, verdict === 'GO' ? 0 : 1, 0, 0), sec: 60, fixed, judge });
  const rounds = [r(1, 'NO-GO', true, { ran: true, accepted: 1, declined: 2, go: false }), r(2, 'GO', false, { ran: true, accepted: 0, declined: 1, go: true }),
    r(3, 'NO-GO', true, { ran: false, why: 'the judge call failed (exit 1)' })];
  // Each review's judge line; '' for review 3, which the judge did not read: it has none.
  const SAID = ['judge: 1 accepted, 2 declined', 'passed (the judge declined all 1)', ''];
  const LINES = SAID.filter(Boolean);
  const said = (el) => Array.from(el.querySelectorAll('.judged'), (n) => n.textContent);
  // In flight: the card's review lines, and each review step of its timeline.
  const flying = data.panels.belt.data.cards[0];
  flying.reviews = rounds;
  flying.track.records = rounds.map((x) => ({ name: `review ${x.round} (${x.verdict})`, state: 'done', sec: 60, at: iso(T0 - 600000 + x.round * 60000), counts: x.counts, judge: x.judge }));
  // Landed: two cards of one project and one of another.
  const [one, two] = data.panels.landed.data.cards;
  // A card's fix rounds are its fixes, a fix before its first review too: two was fixed once before it was reviewed.
  Object.assign(one, { reviews: 3, rounds, fixes: 2, track: { ...trackOf('++++++', ''), records: flying.track.records } });
  Object.assign(two, { rounds: [r(1, 'NO-GO', true, { ran: true, accepted: 2, declined: 1, go: false })], fixes: 2 });
  data.panels.landed.data.cards.push({ ...clone(two), repo: 'widgetshop', card: 'c9-9', issue: 9, fixes: 1, rounds:[r(1, 'NO-GO', true, { ran: true, accepted: 2, declined: 0, go: false }), r(2, 'GO', false, { ran: false, why: 'the review had no finding' })] });
  deliver(w, data);
  const row = panel(w, 'belt').querySelector('li[data-key="sample:c3-63"]');
  openEvery(w, row.querySelector('details.track-detail'));
  assert.deepEqual(said(row.querySelector('.reviews')), LINES, 'each finished review of a card in flight');
  assert.deepEqual(Array.from(row.querySelectorAll('.tl-item'), (li) => said(li).join('')), SAID, 'each review step of its timeline');
  const landed = panel(w, 'landed').querySelector('.rows > li');
  // Its reviews line (its rollout lines stand between it and the first line).
  const reviewed = Array.from(landed.querySelectorAll(':scope > .row-meta')).find((p) => p.textContent.startsWith('Review 1:'));
  assert.deepEqual(said(reviewed), LINES, 'each review of a landed card');
  assert.doesNotMatch(panel(w, 'belt').textContent + panel(w, 'landed').textContent, /judge did not run|judge call failed|review had no finding/,
    'a review the judge did not read says nothing of the judge');
  assert.deepEqual(Array.from(landed.querySelectorAll('.tl-item'), (li) => said(li).join('')), SAID, 'each review step of a landed card');
  // The day's totals, a line a project: the judge's accepted and declined findings, and the fix rounds.
  assert.deepEqual(Array.from(panel(w, 'landed').querySelectorAll('.day-totals > p'), (li) => Array.from(li.children, (n) => n.textContent).join(': ')),
    ['sample: 3 findings accepted, 4 declined, 4 fix rounds', 'widgetshop: 2 findings accepted, 0 declined, 1 fix round']);
  // A count of none declined opens nothing; the declined count opens that card's lines in the Declined panel, alone.
  assert.equal(panel(w, 'landed').querySelectorAll('.rows > li')[2].querySelector('button[data-act="declined-of"]'), null, 'nothing declined: nothing to open');
  const titles = () => Array.from(panel(w, 'declined').querySelectorAll('.rows > .row .title'), (n) => n.textContent);
  assert.equal(titles().length, 1, 'the panel shows the line not filed; the filed one (of c5-7) is in the rest');
  const open = row.querySelector('.reviews button[data-act="declined-of"]');
  assert.equal(open.textContent, '2 declined');
  open.click();
  assert.deepEqual(titles(), ['[P1] b.txt:2 no mark here'], "the card's own lines, no other card's");
  assert.match(panel(w, 'declined').textContent, /Showing the line of #63 only/);
  assert.equal(new URL(w.location.href).searchParams.get('declined'), 'c3-63', 'the address keeps it through a reload');
  // It stays through a new snapshot, until the owner asks for every line again.
  next(w, data);
  assert.deepEqual(titles(), ['[P1] b.txt:2 no mark here']);
  panel(w, 'declined').querySelector('button[data-act="declined-all"]').click();
  assert.equal(titles().length, 2, 'every line, the filed one too');
  assert.doesNotMatch(panel(w, 'declined').textContent, /only/);
});

// Bug (issue 605): an issue whose Depends on: line names another repository's issue that gh cannot read waits as if it
// were open, and nothing said why: it sat out of the queue with no sign of the line or of what gh said.
test('Needs you: a dependency in another repository that cannot be read names the issue, the line and why', () => {
  const w = boot();
  const data = full();
  deliver(w, data);
  const count = () => Number(panel(w, 'needs').querySelector('.panel-count').textContent.trim());
  const was = count();
  data.panels.needs.data.cards.farDeps = [{ repo: 'sample', issue: 42, title: 'Use the new tool', url: `${P}/42`, ref: 'other/repo#600',
    line: 'Depends on: other/repo#600 landing', reason: "GraphQL: Could not resolve to a Repository with the name 'other/repo'. (repository)" }];
  next(w, data);
  const group = panel(w, 'needs').querySelector('[data-group="farDeps"]');
  assert.equal(group.hidden, false);
  const row = group.querySelector('li[data-key="fardep:sample#42:other/repo#600"]');
  assert.ok(row, 'the waiting issue is listed');
  assert.match(row.querySelector('.row-main').textContent, /#42.*Use the new tool.*Waits on other\/repo#600/s);
  assert.equal(row.querySelector('.seen').textContent, 'Depends on: other/repo#600 landing');
  assert.match(row.querySelector('.reason').textContent, /Could not resolve to a Repository with the name 'other\/repo'/);
  assert.equal(count(), was + 1, 'it counts as one thing that needs the owner');
});

// The owner approves every change to how cards are built, reviewed, fixed, tested, landed or pushed. Bug: a follow-up
// filed held for such a change was shown nowhere the owner looks, so it waited unseen, or was counted as nothing.
test('Needs you: a follow-up held because it changes a pipeline file shows its cost line until it is released', () => {
  const w = boot();
  const data = full();
  deliver(w, data);
  const count = () => Number(panel(w, 'needs').querySelector('.panel-count').textContent.trim());
  const was = count();
  data.panels.needs.data.cards.pipeline = [{ repo: 'sample', issue: 41, title: '[P1] conveyor/conveyor.sh:9 a slow gate', cost: 'not assessed', parent: 30, since: data.panels.needs.data.cards.waiting[0].since, url: `${P}/41` }];
  next(w, data);
  const group = panel(w, 'needs').querySelector('[data-group="pipeline"]');
  assert.equal(group.hidden, false);
  assert.equal(group.querySelector('.group-title').textContent, 'Pipeline changes held for you');
  const row = group.querySelector('li[data-key="pipeline:sample#41"]');
  assert.ok(row, 'the held follow-up is listed');
  assert.match(row.querySelector('.row-main').textContent, /#41.*a slow gate.*Pipeline change: held/s);
  assert.equal(row.querySelector('.reason').textContent, 'Cost to every card: not assessed');
  assert.match(row.querySelector('.hint').textContent, /^A follow-up of #30 that changes how Conveyor builds, reviews.*Conveyor does not build it until you choose Queue\.$/);
  assert.equal(count(), was + 1, 'it counts as one thing that needs the owner');
  // None, or a snapshot from before the list: the group is hidden.
  next(w, full());
  assert.equal(panel(w, 'needs').querySelector('[data-group="pipeline"]').hidden, true);
});

// Bug (#617): the Board and the Foreman watcher kept two lists of the kinds of Needs you, so a kind on one could be
// missing from the other. The page's groups come from the one list (kinds, .claude/scripts/dashboard_needs.json): a kind added
// to it is a group, with its entries (entries[kind]) and in the count, with no change to the page.
test('Needs you: a kind added to the shared list of kinds is shown with its entries and counted', () => {
  const w = boot();
  const data = full();
  deliver(w, data);
  const count = () => Number(panel(w, 'needs').querySelector('.panel-count').textContent.trim());
  const was = count();
  Object.assign(data.panels.needs.data, { kinds: [...data.panels.needs.data.kinds, { kind: 'newKind', from: ['needsYou', 'newKind'], title: 'A new kind' }],
    entries: { newKind: [{ repo: 'sample', issue: 40, title: 'a new kind of wait', reason: 'it waits on the owner', since: data.panels.needs.data.cards.waiting[0].since, url: `${P}/40` }] } });
  next(w, data);
  const group = panel(w, 'needs').querySelector('[data-group="newKind"]');
  assert.ok(group && !group.hidden, 'the new kind has its group');
  assert.equal(group.querySelector('.group-title').textContent, 'A new kind');
  assert.equal(group.nextElementSibling.dataset.group, 'decisions', 'the open decisions stay last');
  const row = group.querySelector('li');
  assert.match(row.querySelector('.row-main').textContent, /#40.*a new kind of wait/s);
  assert.equal(row.querySelector('.reason').textContent, 'it waits on the owner');
  assert.equal(count(), was + 1, 'it counts as one thing that needs the owner');
  // Bug: the row was kept by its since alone, so an entry whose reason changed under the same since (a Pick settings
  // decision whose counts grew) kept showing the old reason.
  data.panels.needs.data.entries.newKind[0].reason = 'it still waits on the owner';
  next(w, data);
  assert.equal(group.querySelector('li .reason').textContent, 'it still waits on the owner', 'the new reason is shown');
});

// Bugs: a held pipeline change had no button, so the owner had to find it on the Rules tab to release it and could not
// close it from the Board at all; or Queue releases another issue, or into another project; or Close sends on its
// first click; or a refusal is lost, the buttons stay disabled, or the entry is dropped though the host did nothing.
// Issue 407: its button said "Build this" (one of five words for queueing), and a queued entry stayed as it was,
// with its buttons, until the next data, with no way back.
test('Needs you: a held pipeline change has Queue (one click, with Undo) and Close (on a second click); a refusal is shown on the entry', async () => {
  const held = () => {
    const data = full();
    data.panels.needs.data.cards.pipeline = [{ repo: 'sample', issue: 41, title: '[P1] conveyor/conveyor.sh:9 a slow gate', cost: 'not assessed', parent: 30, since: data.panels.needs.data.cards.waiting[0].since, url: `${P}/41` }];
    return data;
  };
  const w = boot();
  deliver(w, held());
  const row = (x) => panel(x, 'needs').querySelector('li[data-key="pipeline:sample#41"]');
  const btn = (x, k) => row(x).querySelector(`button[data-act="${k}"]`);
  const note = (x) => row(x).querySelector('.answer-note').textContent;
  assert.deepEqual(Array.from(row(w).querySelectorAll('button'), (b) => b.textContent), ['Queue', 'Close']);
  // Queue releases that issue in its own project, at once; the entry is greyed, its buttons gone, with Undo.
  btn(w, 'release').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'release', args: ['41'], repo: 'sample' } }]);
  assert.equal(note(w), 'Queued: #41 leaves Needs you in about a minute. Undo');
  assert.ok(row(w).classList.contains('is-pending') && btn(w, 'release').hidden && btn(w, 'close').hidden);
  // Undo holds it again: the entry is back as it was.
  btn(w, 'undo').click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'hold', args: ['41'], repo: 'sample' } }]);
  assert.equal(note(w), 'Undone: the hold on #41 is back.');
  assert.ok(!row(w).classList.contains('is-pending') && !btn(w, 'release').hidden && !btn(w, 'release').disabled);
  // The next data no longer lists it: it has left the panel.
  next(w, full());
  assert.equal(row(w), null);

  // Close says on its first click what the second does; only the second sends.
  const c = boot();
  deliver(c, held());
  btn(c, 'close').click();
  await settle();
  assert.equal(btn(c, 'close').textContent, 'Click again: close #41 for good. Conveyor never builds it');
  assert.deepEqual(c.posts, [], 'the first click sends nothing');
  btn(c, 'close').click();
  await settle();
  assert.deepEqual(c.posts.splice(0), [{ url: 'control', body: { action: 'close', args: ['41'], repo: 'sample' } }]);
  assert.match(note(c), /^Closed: #41 leaves Needs you in about a minute\./);

  // A refusal, of either button, is shown on the entry; the entry stays and both buttons can be pressed again (Close
  // is pressed after Queue's refusal, on the same entry; each refusal has its own text, so a note left from Queue's
  // is not taken for Close's).
  const r = boot();
  deliver(r, held());
  for (const k of ['release', 'close']) {
    const refused = `conveyor: privacy: the check could not be made; nothing posted (${k})`;
    r.reply = { ok: false, status: 409, text: () => Promise.resolve(refused) };
    btn(r, k).click();
    if (k === 'close') btn(r, k).click();
    await settle();
    assert.deepEqual(r.posts.splice(0).map((p) => p.body.action), [k]);
    assert.equal(note(r), `Not done: ${refused}`, k);
    assert.deepEqual([btn(r, 'release').disabled, btn(r, 'close').disabled], [false, false], `${k}: refused, both can be pressed again`);
    next(r, held());
    assert.ok(row(r), `${k}: the entry stays while the snapshot still lists it`);
    assert.equal(note(r), `Not done: ${refused}`, `${k}: the refusal stays on the entry`);
  }
});

// The owner: a test run that failed and passed only when its failing cases ran again is never shown as a plain success.
// The card's line says "Test passed on re-run", and so does its Tests bar in "Every step"; a plain success says Test alone.
test('a card whose tests passed on re-run is drawn with "passed on re-run", never as a plain success', () => {
  const w = boot();
  const data = full();
  const t = trackOf('++++>.', 'landing', { records: [{ name: 'tests passed', state: 'done', sec: 60, at: iso(T0 - 60000), rerun: true }] });
  t.steps[3].rerun = true;
  data.panels.belt.data.cards[0].track = t;
  deliver(w, data);
  const row = panel(w, 'belt').querySelector('li[data-key="sample:c3-63"]');
  const test6 = row.querySelectorAll('ol.track6 > li.step6')[3];
  assert.equal(test6.querySelector('.step-name').textContent, 'Test passed on re-run');
  assert.match(test6.getAttribute('aria-label'), /^Test passed on re-run: done/);
  const bar = openEvery(w, row.querySelector('details.track-detail')).querySelector('.timeline > li.tl-item .tl-label');
  assert.equal(bar.firstChild.textContent, 'Tests');
  assert.ok(Array.from(bar.querySelectorAll('.chip'), (c) => c.textContent).includes('passed on re-run'), 'the Tests bar says it passed on re-run');
  // A plain success: Test, with no such words.
  const plain = full();
  plain.panels.belt.data.cards[0].track = trackOf('++++>.', 'landing', { records: [{ name: 'tests passed', state: 'done', sec: 60, at: iso(T0 - 60000) }] });
  next(w, plain);
  assert.equal(row.querySelectorAll('ol.track6 > li.step6')[3].querySelector('.step-name').textContent, 'Test');
  assert.doesNotMatch(row.textContent, /re-run/);
});

// #349: no test file has a CPU budget, so a passing test run flags no file. Bug caught: a Tests bar in "Every step"
// still shows an "N slow files" chip, and its list of files over the budget, from a step that holds an old slow list.
test('a passing test run flags no slow file, though its step holds an old slow list', () => {
  const w = boot();
  const data = full();
  const rec = (sec, slow) => ({ name: 'tests passed', state: 'done', sec, at: iso(T0 - sec * 1000), ...(slow === undefined ? {} : { slow }) });
  data.panels.belt.data.cards[0].track = trackOf('++++>.', 'landing', { records: [rec(240, [{ file: 's.test', cpu: 10.24, budget: 8 }]), rec(60)] });
  deliver(w, data);
  openEvery(w, panel(w, 'belt').querySelector('li[data-key="sample:c3-63"] details.track-detail'));
  const items = Array.from(panel(w, 'belt').querySelectorAll('li[data-key="sample:c3-63"] details.track-detail .timeline > li.tl-item'));
  assert.ok(items.length >= 2);
  for (const li of items) {
    assert.doesNotMatch(li.textContent, /slow file|budget/i);
    assert.equal(li.querySelector('.tl-slow, .tl-slow-open'), null, 'no slow list and no button for it');
  }
});

// Bug (#1101): while a new snapshot took minutes, Needs you and the belt showed the old one with nothing to say it was
// old, and the belt counted its cards, or said it was empty, while the loop built more. A part's behind names the
// project whose snapshot is behind its card records: each panel says so under what it shows, and the belt counts the
// loop's own figure (building); once none is behind, the line goes and the belt counts its cards again.
test('Needs you and the belt say when a snapshot is behind the card records, and the belt counts what builds now', () => {
  const w = boot();
  const data = full(), at = iso(T0 - 120000);
  const said = (id) => Array.from(panel(w, id).querySelectorAll('.behind p'), (p) => p.textContent);
  const count = () => panel(w, 'belt').querySelector('.panel-count').textContent;
  deliver(w, data);
  const before = count();
  data.panels.needs.data.behind = [{ repo: 'sample', at }];
  // The blocked card as the records give it (fromRecords): no track and no reviews.
  delete data.panels.needs.data.cards.blocked[0].track;
  data.panels.needs.data.cards.blocked[0].fromRecords = true;
  Object.assign(data.panels.belt.data, { behind: [{ repo: 'sample', at }], building: 2, cards: [] });
  next(w, data);
  const stopsAt = () => panel(w, 'needs').querySelector('li[data-key^="blocked:c2-13"] .track6');
  assert.equal(stopsAt(), null, 'the card the records give has no track');
  for (const id of ['needs', 'belt']) {
    assert.equal(said(id).length, 1, `${id} says its snapshot is behind`);
    assert.match(said(id)[0], /^sample As of .+, the belt has changed since\.$/);
  }
  assert.equal(panel(w, 'belt').dataset.state, 'ready', 'a belt with no card shown is not called empty while it is behind');
  assert.equal(count(), '2 of 3', "the belt counts the loop's figure, not the cards it shows");
  assert.equal(fig(w, 'belt'), '2 of 3', "the head's On the belt tile counts as the belt does");
  // Bug: the row the records gave had the key of the whole card, so it was kept, with no track or reviews, once a new
  // snapshot gave them.
  const fresh = full();
  fresh.panels.needs.data.cards.blocked[0].track = { ...trackOf('++!...', ''), at: null };
  next(w, fresh);
  assert.ok(stopsAt(), 'the whole card from the new snapshot is drawn anew, with its track');
  assert.deepEqual([said('needs'), said('belt')], [[], []], 'the line goes once no project is behind');
  assert.equal(count(), before);
  assert.equal(fig(w, 'belt'), before);
});
