// SPDX-License-Identifier: Apache-2.0
// The Declined panel: how a reason is drawn; what an F<n> of the judge's reason means; when a line leaves the panel; "Dismiss all shown (n)" and "Dismiss all (n)".
// Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { T0, iso, boot, panel, deliver, next, settle, full, tick, P, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const FINDINGS = [{ n: 1, finding: '[P1] a.txt:2 reads the old word. Proof: a.txt:2 still says it' }, { n: 2, finding: '[P1] a.txt:2 the old word again. Proof: none new' }];
const REPO = 'https://github.com/example/sample-project';
const line = (over) => ({ repo: 'sample', repoUrl: REPO, id: 'd00000000000a', time: iso(T0 - 60000), card: 'c3-63', issue: 63, url: `${P}/63`, finding: '[P1] a.txt:2 the old word again',
  by: 'judge', why: 'the same as F1, so this is F1 again with nothing new', built: null, dismissed: null, round: 2, findings: FINDINGS, ...over });
const rowOf = (w, finding) => Array.from(panel(w, 'declined').querySelectorAll('.rows > .row')).find((r) => r.querySelector('.title').textContent === finding);

// Bug: the judge's "this is F1 again" names a finding by its place in the review, and nothing on the panel says which
// finding that is or which review it was in.
test("Declined: an F1 in the judge's reason shows the card's first finding of that review, with its round, on hover and on click", () => {
  const w = boot();
  const data = full();
  data.panels.declined.data.lines = [line()];
  deliver(w, data);
  const row = rowOf(w, '[P1] a.txt:2 the old word again');
  const reason = row.querySelector('.reason');
  assert.equal(reason.querySelector('.why-text').textContent, 'the same as F1, so this is F1 again with nothing new', 'the reason reads as the judge wrote it');
  const refs = Array.from(reason.querySelectorAll('button[data-act="finding"]'));
  assert.deepEqual(refs.map((b) => b.textContent), ['F1', 'F1']);
  const says = 'F1, review round 2: [P1] a.txt:2 reads the old word.';
  assert.equal(refs[0].title, says, 'hover: its file and line, its first sentence and its round');
  const said = row.querySelector('.finding-said');
  assert.equal(said.hidden, true, 'nothing is opened before a click');
  refs[1].click();
  assert.equal(said.hidden, false);
  assert.equal(said.textContent, says, 'click: the same, under the reason');
  assert.equal(refs[1].getAttribute('aria-expanded'), 'true');
  refs[1].click();
  assert.equal(said.hidden, true, 'a second click hides it');
  assert.equal(refs[1].getAttribute('aria-expanded'), 'false');
});

// Bugs: an F<n> whose finding is not in the card's records links to another finding, or is dropped from the reason;
// a reason not the judge's has its F<n> turned into a finding of a review it never read.
test('Declined: an F<n> with no matching finding is shown as written, with "finding not found" on hover', () => {
  const w = boot();
  const data = full();
  data.panels.declined.data.lines = [line({ why: 'F3 said it first; F1 is another', findings: FINDINGS }),
    line({ id: 'd00000000000b', finding: '[P2] b.txt:1 lost round', why: 'this is F1 again', round: null, findings: null }),
    line({ id: 'd00000000000c', finding: '[P2] c.txt:1 by the owner', by: 'owner', why: 'not F1', round: null, findings: null })];
  deliver(w, data);
  const first = rowOf(w, '[P1] a.txt:2 the old word again').querySelector('.reason');
  assert.equal(first.querySelector('.why-text').textContent, 'F3 said it first; F1 is another');
  const missing = first.querySelector('.finding-ref.is-missing');
  assert.equal(missing.textContent, 'F3');
  assert.equal(missing.title, 'finding not found');
  assert.equal(missing.tagName, 'SPAN', 'nothing to open');
  assert.deepEqual(Array.from(first.querySelectorAll('button[data-act="finding"]'), (b) => b.textContent), ['F1'], 'the F<n> that is found still opens');
  const lost = rowOf(w, '[P2] b.txt:1 lost round').querySelector('.reason');
  assert.equal(lost.querySelector('.why-text').textContent, 'this is F1 again');
  assert.equal(lost.querySelector('.is-missing').title, 'finding not found', 'a line whose review was not found');
  assert.equal(rowOf(w, '[P2] b.txt:1 lost round').querySelector('.finding-said'), null);
  const owner = rowOf(w, '[P2] c.txt:1 by the owner').querySelector('.reason');
  assert.equal(owner.querySelector('.why-text').textContent, 'not F1');
  assert.equal(owner.querySelector('.finding-ref'), null, "the owner's reason is not the judge's numbering");
});

// Bug: a reason was one plain paragraph after "Why: ", its backticks shown as raw text, its file and line not linked,
// and nothing said whether the judge or the code declined it.
test("Declined: a reason is its own block, led by who declined it, a line a sentence, backticked text as code, a file and line linked", () => {
  const w = boot();
  const data = full();
  const why = 'In `t_stackfixround`, #7 is away. The remaining point repeats the declined finding at `conveyor/lib/claim.sh:99`.';
  data.panels.declined.data.lines = [
    line({ why, findings: FINDINGS.concat({ n: 3, finding: '[P3] conveyor/lib/claim.sh:99 drops the wait. Proof: none' }) }),
    line({ id: 'd00000000000d', finding: '[P2] d.txt:1 by the code', by: 'code', why: 'follow-up of a follow-up', round: null, findings: null })];
  deliver(w, data);
  const judge = rowOf(w, '[P1] a.txt:2 the old word again').querySelector('.reason');
  assert.equal(judge.querySelector('strong.why-label').textContent, 'Why the judge declined it');
  assert.equal(judge.dataset.by, 'judge', 'the rule is in the colour of who declined it');
  const lines = Array.from(judge.querySelectorAll('.why-line'), (l) => l.textContent);
  assert.deepEqual(lines, ['In t_stackfixround, #7 is away. ', 'The remaining point repeats the declined finding at conveyor/lib/claim.sh:99.'], 'a line a sentence');
  assert.deepEqual(Array.from(judge.querySelectorAll('code'), (c) => c.textContent), ['t_stackfixround', 'conveyor/lib/claim.sh:99']);
  assert.ok(!judge.textContent.includes('`'), 'no backtick is shown');
  assert.equal(judge.querySelector('.why-text').textContent, why.replaceAll('`', ''), 'the text is never changed');
  const at = judge.querySelector('a.why-at');
  assert.equal(at.href, 'https://github.com/example/sample-project/blob/HEAD/conveyor/lib/claim.sh#L99', 'the file and line on GitHub');
  assert.equal(at.querySelector('code').textContent, 'conveyor/lib/claim.sh:99');
  assert.equal(at.title, 'F3, review round 2: [P3] conveyor/lib/claim.sh:99 drops the wait.', 'hover: the finding it names');
  const code = rowOf(w, '[P2] d.txt:1 by the code').querySelector('.reason');
  assert.equal(code.querySelector('strong.why-label').textContent, 'Why the code declined it');
  assert.equal(code.dataset.by, 'code');
});

// Bugs: a `file:line` naming a declined finding of an earlier card showed nothing on hover (only the same review's
// findings were searched); a main-red fix card's reason (issue 0, no issue url) linked no file:line; a short
// `issues.sh:636` linked the repository root's issues.sh, not the conveyor/lib/issues.sh the findings name; when two
// declined findings start at the same file:line, hover named only the first one found, which can be the wrong one.
test('Declined: a reason links a file:line on a main-red fix card, finds the full path of a short one, and names the findings of another card', () => {
  const w = boot();
  const data = full();
  data.panels.declined.data.lines = [
    line({ why: 'This repeats the declined finding at `conveyor/lib/claim.sh:99`. Also `issues.sh:636` and `nowhere.sh:3`.',
      finding: '[P2] conveyor/lib/issues.sh:630 reads the old list', round: 1, findings: [{ n: 1, finding: '[P2] conveyor/lib/issues.sh:630 reads the old list' }] }),
    line({ id: 'd00000000000e', time: iso(T0 - 120000), card: 'c4-red', issue: 0, name: 'Main is red (0123456789ab)', url: null, finding: '[P3] e.txt:1 a red nit',
      by: 'code', why: 'The proof needs `conveyor/lib/snapshot.sh:525`.', round: null, findings: null }),
    line({ id: 'd000000000010', finding: '[P1] conveyor/lib/rules.sh:80 one switch resets its row', why: 'Earlier cards declined this finding at `conveyor/lib/rules.sh:20`.',
      round: null, findings: null })];
  const old = (id, finding) => line({ id, time: iso(T0 - 9 * 86400000), card: 'c1-250', issue: 250, url: `${P}/250`, finding, round: 1, findings: null });
  data.panels.declined.data.rest = [line({ id: 'd00000000000f', time: iso(T0 - 9 * 86400000), card: 'c1-380', issue: 380, url: `${P}/380`,
    finding: '[P2] conveyor/lib/claim.sh:99 shows a ready card waiting. Proof: none', round: 1, findings: null }),
    old('d000000000011', '[P1] conveyor/lib/rules.sh:20 a default leaves the rule unset. Proof: none'),
    old('d000000000012', '[P1] conveyor/lib/rules.sh:20 a click changes its row. Proof: none'),
    // Declined after the reason below was written (#409), so it cannot be the finding the reason names.
    line({ id: 'd000000000013', time: iso(T0 - 30000), card: 'c1-260', issue: 260, url: `${P}/260`,
      finding: '[P1] conveyor/lib/rules.sh:20 a later finding. Proof: none', round: 1, findings: null })];
  deliver(w, data);
  const judge = rowOf(w, '[P2] conveyor/lib/issues.sh:630 reads the old list').querySelector('.reason');
  const links = Array.from(judge.querySelectorAll('a.why-at'));
  assert.deepEqual(links.map((a) => a.href), [`${REPO}/blob/HEAD/conveyor/lib/claim.sh#L99`, `${REPO}/blob/HEAD/conveyor/lib/issues.sh#L636`],
    'the short path is the full one the findings name; one no finding names is not linked');
  assert.equal(links[0].title, 'Declined on #380: [P2] conveyor/lib/claim.sh:99 shows a ready card waiting.', "hover: the earlier card's finding it names");
  assert.equal(judge.querySelectorAll('code').length, 3, 'the unlinked span is still code');
  const red = rowOf(w, '[P3] e.txt:1 a red nit').querySelector('.reason a.why-at');
  assert.equal(red.href, `${REPO}/blob/HEAD/conveyor/lib/snapshot.sh#L525`, "a main-red fix card's reason links to its repository");
  const both = rowOf(w, '[P1] conveyor/lib/rules.sh:80 one switch resets its row').querySelector('.reason a.why-at');
  assert.equal(both.title, '2 findings start at conveyor/lib/rules.sh:20: Declined on #250: [P1] conveyor/lib/rules.sh:20 a default leaves the rule unset.'
    + ' Declined on #250: [P1] conveyor/lib/rules.sh:20 a click changes its row.', 'hover names every finding at that line declined before the reason, not one picked of them, and none declined after it');
});

// Bug (#412): a finding was one long bold paragraph with its backticks shown raw, and in it and in its reason code and
// file paths read like the prose round them; a bare path (no backticks) was not linked.
const LONG = '[P2] src/services/fold-cutover-preflight.ts:338 The hash check accepts a box count the manifest refuses. Proof: Set `componentInnerBoxes: 2` in the fixture. '
  + 'The manifest at shared/taxonomy/verification-pipeline-capture-fields.ts:239 allows only 0 and 1.';
const LONG_WHY = 'The proof runs with `componentInnerBoxes: 2`, and the manifest range at shared/taxonomy/verification-pipeline-capture-fields.ts:239 (`[1, 0, 1, \'integer\']`) says no.';
// A finding the review gave an id ("[E1]") between its level and its file, as the fix reviews do.
const TAGGED = '[P2] [E1] conveyor/lib/snapshot.sh:716 The snapshot drops a line. Proof: Run it twice.';
// One case, so one Board render: cases share no state, as the runner (dashboard-view.helpers.mjs) gives each case to
// whichever of its workers is free, and these checks only read the rows.
test('Declined: a finding and its reason draw a level badge, a file link, a bold claim, a Proof label, and code and paths as code', () => {
  const w = boot();
  const data = full();
  data.panels.declined.data.lines = [line({ finding: LONG, why: LONG_WHY, by: 'owner', round: null, findings: null }),
    line({ id: 'd00000000000b', finding: TAGGED, why: 'not worth it', by: 'owner', round: null, findings: null })];
  // Bug #437: the panel kept its own copy of this formatting, so a review's output and a blocked card's reason drew the
  // same kind of text another way. It draws through the Board's shared helper (app.js findingText), and draws as before.
  const used = new Set();
  for (const k of ['fill', 'codeEl', 'proofAt']) {
    const was = w.DASH_APP.text[k];
    w.DASH_APP.text[k] = (...a) => { used.add(k === 'proofAt' ? k : `${k}:${a[a.length - 1]}`); return was(...a); };
  }
  deliver(w, data);
  for (const k of ['codeEl:declined-at', 'codeEl:why-at', 'fill:declined', 'proofAt']) assert.ok(used.has(k), `the finding, its file and its reason draw through the shared helper: ${k}`);
  const long = rowOf(w, LONG.replaceAll('`', ''));
  const f = long.querySelector('.declined-finding');
  const badge = f.querySelector('.declined-head .declined-level');
  assert.equal(badge.textContent, '[P2]');
  assert.equal(badge.dataset.level, 'P2', 'the badge takes the P2 colour');
  const file = f.querySelector('.declined-head a.declined-at');
  assert.equal(file.href, `${REPO}/blob/HEAD/src/services/fold-cutover-preflight.ts#L338`, 'the file and line link to that line');
  assert.equal(f.querySelector('strong.declined-claim').textContent, 'The hash check accepts a box count the manifest refuses. ', 'the claim alone is bold');
  const proof = f.querySelector('.declined-proof');
  assert.equal(proof.querySelector('.declined-proof-label').textContent, 'Proof: ');
  assert.equal(proof.querySelectorAll('.declined-line').length, 2, 'a proof sentence a line');
  const codes = Array.from(proof.querySelectorAll('code'), (c) => c.textContent);
  assert.deepEqual(codes, ['componentInnerBoxes: 2', 'shared/taxonomy/verification-pipeline-capture-fields.ts:239'], 'backticked text and the bare path are code, without backticks');
  assert.deepEqual(Array.from(proof.querySelectorAll('a.declined-at'), (a) => a.href), [`${REPO}/blob/HEAD/shared/taxonomy/verification-pipeline-capture-fields.ts#L239`],
    'the bare manifest path links to its line');
  // Bug (#435): a finding's code spans also took a declined-code class that no stylesheet, script or test used.
  assert.deepEqual(Array.from(f.querySelectorAll('code'), (c) => c.className), Array(f.querySelectorAll('code').length).fill('why-code'),
    'each code span takes only the shared why-code style');
  // Bug: the Declined styles took the class names of the review rows in Show output and Health (.finding-head,
  // .finding-at, .finding-proof), so each one's rules changed the other's layout.
  assert.equal(f.querySelector('.finding-head, .finding-at, .finding-proof'), null, "the review rows' class names are not used");
  // The reason: its backticked spans are code and a bare file path is a code link.
  const r = long.querySelector('.reason');
  assert.deepEqual(Array.from(r.querySelectorAll('code:not(a code)'), (c) => c.textContent), ['componentInnerBoxes: 2', "[1, 0, 1, 'integer']"]);
  assert.deepEqual(Array.from(r.querySelectorAll('a.why-at'), (a) => [a.href, a.textContent]),
    [[`${REPO}/blob/HEAD/shared/taxonomy/verification-pipeline-capture-fields.ts#L239`, 'shared/taxonomy/verification-pipeline-capture-fields.ts:239']]);
  // The finding and its reason, drawn, are the stored text without its backticks.
  assert.equal(f.textContent, LONG.replaceAll('`', ''));
  assert.equal(long.querySelector('.why-text').textContent, LONG_WHY.replaceAll('`', ''));
  // Bug: a finding with a review id after its level ("[P2] [E1] <file>:<line>") lost its badge, bold claim and Proof.
  const t = rowOf(w, TAGGED).querySelector('.declined-finding');
  assert.equal(t.querySelector('.declined-level').dataset.level, 'P2', 'a review id after the level: the badge is kept');
  assert.equal(t.querySelector('.declined-ids').textContent, '[E1] ');
  assert.equal(t.querySelector('.declined-head a.declined-at').href, `${REPO}/blob/HEAD/conveyor/lib/snapshot.sh#L716`);
  assert.equal(t.querySelector('strong.declined-claim').textContent, 'The snapshot drops a line. ');
  assert.equal(t.querySelector('.declined-proof-label').textContent, 'Proof: ');
  assert.equal(t.textContent, TAGGED, 'the text is the finding as written');
});

// Audit UX14. Bug: a line left the panel 7 days after its time with no word before, and said "More than 7 days old"
// only after it had gone. An open line with 2 days or less left says when it goes; one with more, or one dismissed or
// filed (it has already left), says nothing of it.
test('Declined: an open line with 2 days or less left says "Expires in …" before it leaves the panel; others do not', () => {
  const w = boot({ query: '?declined=all' });
  const data = full();
  const DAY = 86400000;
  data.panels.declined.data.lines = [line({ id: 'd00000000001a', finding: '[P2] soon.txt:1 going', time: iso(T0 - 5.5 * DAY) }),
    line({ id: 'd00000000001b', finding: '[P2] fresh.txt:1 staying', time: iso(T0 - 3 * DAY) })];
  data.panels.declined.data.rest = [line({ id: 'd00000000001c', finding: '[P2] gone.txt:1 dismissed', time: iso(T0 - 6 * DAY), dismissed: { time: iso(T0 - DAY), by: 'owner' } }),
    line({ id: 'd00000000001d', finding: '[P2] filed.txt:1 filed', time: iso(T0 - 6 * DAY), built: 91 })];
  deliver(w, data);
  const expires = (f) => rowOf(w, f).querySelector('.expires')?.textContent ?? null;
  assert.equal(expires('[P2] soon.txt:1 going'), 'Expires in 1 d 12 h');
  assert.equal(expires('[P2] fresh.txt:1 staying'), null, 'more than 2 days left: no note');
  assert.equal(expires('[P2] gone.txt:1 dismissed'), null, 'a dismissed line has already left');
  assert.equal(expires('[P2] filed.txt:1 filed'), null, 'a filed line has already left');
});

// Audit UX14. Bug: a line is unchanged in the snapshot until it leaves, and the Board does not draw a panel again for
// an unchanged part, so a line that crossed into its last 2 days with the page open never said it was going, and a
// note shown counted nothing down. The clock alone, with no new snapshot, brings the note in and moves it on.
test('Declined: the clock brings in "Expires in …" when a line comes within 2 days of leaving, and counts it down', () => {
  const w = boot();
  const data = full();
  const DAY = 86400000, HOUR = 3600000;
  data.panels.declined.data.lines = [line({ id: 'd00000000003a', finding: '[P2] later.txt:1 going later', time: iso(T0 - 4.5 * DAY) })];
  deliver(w, data);
  const expires = () => rowOf(w, '[P2] later.txt:1 going later').querySelector('.expires')?.textContent ?? null;
  assert.equal(expires(), null, '2 days 12 h left: no note yet');
  tick(w, 0.5 * DAY + HOUR);
  assert.equal(expires(), 'Expires in 1 d 23 h', 'within 2 days now: the note comes with no new snapshot');
  tick(w, 12 * HOUR);
  assert.equal(expires(), 'Expires in 1 d 11 h', 'and counts down');
});

// Audit UX14. Bugs: "Dismiss all shown" carried no count and looked like "Show every line", the harmless button
// beside it, and took every line on one click. It is in the heading, coloured as a warning, names its count and sends
// on a second click; a click armed for some lines never sends others: when a snapshot brings a new line between the
// two clicks, the button disarms and names the new count, and sends nothing until clicked twice again.
test('Declined: "Dismiss all shown (n)" sits in the heading as a warning, asks once, and never dismisses lines its count did not name', async () => {
  const w = boot();
  const data = full();
  deliver(w, data);
  const all = () => panel(w, 'declined').querySelector('.panel-head button[data-act="dismiss-all"]');
  assert.equal(all().textContent, 'Dismiss all shown (1)');
  assert.ok(all().classList.contains('btn-warn'), 'coloured as a warning');
  assert.ok(!panel(w, 'declined').querySelector('button[data-act="declined-all"]').classList.contains('btn-warn'), 'Show every line is not');
  all().click();
  await settle();
  assert.equal(w.posts.length, 0, 'the first click only asks');
  assert.equal(all().textContent, 'Click again to dismiss the line for good', 'the second click names that it cannot be undone (issue 407)');
  assert.equal(all().getAttribute('aria-pressed'), 'true');
  assert.match(panel(w, 'declined').querySelector('.foot .answer-note').textContent, /Click again to dismiss the line shown/);
  // A new line arrives before the second click.
  const more = full();
  more.panels.declined.data.lines.unshift(line({ id: 'd00000000002a', finding: '[P2] new.txt:1 a new line', round: null, findings: null, by: 'owner', why: 'not now' }));
  next(w, more);
  assert.equal(all().textContent, 'Dismiss all shown (2)', 'disarmed, with the new count');
  all().click();
  await settle();
  assert.equal(w.posts.length, 0, 'the click after the change only asks again');
  all().click();
  await settle();
  assert.deepEqual(w.posts.splice(0).flatMap((p) => p.body.args).sort(), ['d00000000002a', 'd0123456789ab']);
  assert.equal(all(), null, 'nothing left to dismiss: no button in the heading');
});

// Issue 141. Bug: a main-red fix card has no issue (issue 0), so its declined lines, opened from its declined count,
// said "Showing the line of #0 only"; the note and the line's head show the card's name.
test('Declined: a main-red fix card\'s lines are shown by its name, never as "#0"', () => {
  const w = boot({ query: '?declined=c9-mainred' });
  const data = full();
  data.panels.declined.data.lines = [line({ card: 'c9-mainred', issue: 0, name: 'Main is red (0123456789ab)', url: null })];
  deliver(w, data);
  const text = panel(w, 'declined').textContent;
  assert.match(text, /Showing the line of Main is red \(0123456789ab\) only/);
  assert.doesNotMatch(text, /#0\b/);
  assert.equal(rowOf(w, '[P1] a.txt:2 the old word again').querySelector('.issue').textContent, 'Main is red (0123456789ab)');
});

// Issue 457: "Dismiss all (n)" takes every line the panel counts, drawn or not. n open lines of one project, the
// newest first, the panel at its own size (it draws fewer).
const many = (n) => Array.from({ length: n }, (_, i) => line({ id: `d${i.toString(16).padStart(12, '0')}`, time: iso(T0 - (i + 1) * 60000), finding: `[P3] f${i}.txt:1 a nit`, round: null, findings: null }));
const every = (w) => panel(w, 'declined').querySelector('.panel-head button[data-act="dismiss-every"]');
const count = (w) => w.document.querySelector('#panel-declined .panel-count').textContent;

// Bug: the only bulk button dismissed the lines drawn (5 at Small), so a panel of 111 took one click a screenful.
test('Declined: "Dismiss all (n)" sends every open line, drawn or not, in one request, and the count drops to 0', async () => {
  const w = boot();
  const data = full();
  data.panels.declined.data.lines = many(12);
  deliver(w, data);
  assert.ok(panel(w, 'declined').querySelectorAll('.rows > .row').length < 12, 'the panel draws fewer lines than it counts');
  assert.equal(count(w), '12');
  assert.equal(every(w).textContent, 'Dismiss all (12)');
  assert.ok(every(w).classList.contains('btn-warn'), 'coloured as a warning');
  every(w).click();
  await settle();
  assert.equal(w.posts.length, 0, 'the first click only asks');
  assert.equal(every(w).textContent, 'Click again to dismiss the 12 lines for good');
  every(w).click();
  await settle();
  assert.deepEqual(w.posts.splice(0), [{ url: 'control', body: { action: 'dismiss', args: many(12).map((x) => x.id), repo: 'sample' } }]);
  assert.equal(count(w), '0');
  assert.equal(every(w), null, 'nothing left to dismiss');
});

// The host takes at most 400 ids in one dismiss (dashboard_server.py control_ok). Bug: 401 lines in one request are
// refused whole, and none is dismissed.
test('Declined: "Dismiss all (n)" over 401 lines sends them 400 at most a request, each id once', async () => {
  const w = boot();
  const data = full();
  data.panels.declined.data.lines = many(401);
  deliver(w, data);
  every(w).click(); every(w).click();
  await settle();
  const posts = w.posts.splice(0);
  assert.deepEqual(posts.map((p) => [p.body.repo, p.body.args.length]), [['sample', 400], ['sample', 1]]);
  assert.deepEqual(posts.flatMap((p) => p.body.args), many(401).map((x) => x.id), 'every line, each once');
  assert.equal(count(w), '0');
});

// Bug: a line that arrives between the two clicks is dismissed though the count the owner confirmed did not name it.
test('Declined: "Dismiss all (n)" never dismisses a line that arrived between its two clicks', async () => {
  const w = boot();
  const data = full();
  data.panels.declined.data.lines = many(8);
  deliver(w, data);
  every(w).click();
  await settle();
  const more = full();
  more.panels.declined.data.lines = [line({ id: 'd00000000002a', finding: '[P2] new.txt:1 a new line', round: null, findings: null })].concat(many(8));
  next(w, more);
  assert.equal(every(w).textContent, 'Dismiss all (9)', 'disarmed, with the new count');
  every(w).click();
  await settle();
  assert.equal(w.posts.length, 0, 'the click after the change only asks again');
  assert.equal(count(w), '9', 'the new line is not dismissed');
});
