// SPDX-License-Identifier: Apache-2.0
// The Health panel read at a glance (the Board audit's UX23 and UX31): failing rows first, each with its next step; the
// rows that are fine folded into "N checks fine"; a row's raw output under "Show output". Shared setup:
// dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { T0, iso, clone, boot, panel, deliver, next, tick, full, settle, cases } from './dashboard-view.helpers.mjs';

// A page of the repository (a name with no folder is a page of docs/), its bold marks taken out and its lines joined. Defined in
// this file, not in the helpers: the bug check puts only the card's test files on main's code, where a new helper is missing.
const guide = (name) => readFileSync(new URL(`../../../${name.includes('/') ? name : `docs/${name}`}`, import.meta.url), 'utf8').replace(/\*\*/g, '').replace(/\s+/g, ' ');
const test = cases(import.meta.url);
// A page with only the panel a case reads: every other panel's script is evaluated on each boot (and drawn when it is
// on the tab in view), CPU paid for panels these cases never read and that their own files check.
const page = (id, opt = {}) => boot({ list: [id], ...opt });
// About 25 lines of a pre-push hook's output, as the audit saw poured into the row.
const PUSH_OUT = ['exit 1 (124 is the 900s timeout): push-checks: ok typecheck-backend', ...Array.from({ length: 23 }, (_, i) => `web/src/page${i}.tsx(${i + 1},5): error TS2322: Type 'string' is not assignable to type 'number'.`),
  'push-checks: FAILED typecheck-web'].join('\n');
// Four rows failing at once, as on the audit's live page: a push failing, flaky tests, an old usage limit reading and
// the dashboard code not updated.
function failing() {
  const data = full(), hd = data.panels.health.data;
  Object.assign(hd.records[0], { pushFailingSince: iso(T0 - 480000), pushError: { reason: PUSH_OUT, kind: 'check', check: 'typecheck-web' },
    flaky: [{ case: 'b.test: flaky', count: 3, issue: 16, url: 'https://github.com/example/sample/issues/16' }] });
  hd.limits[0].readAt = iso(T0 - 3600000);
  hd.update = { checkedAt: iso(T0), head: 'bbbbbbbbbbbb', error: 'main has 1 commit(s) that origin/main does not; it is left as it is', moved: null };
  return data;
}
const failingRows = (w) => Array.from(panel(w, 'health').querySelectorAll('.panel-body > dl.checks > dt'), (dt) => dt.dataset.check);
const dd = (w, label) => panel(w, 'health').querySelector(`dt[data-check="${label}"]`).nextElementSibling;

// Bugs (UX23): failing rows were not sorted up, so a warning sat below a dozen rows that were fine, and no row said
// what to do. The failing rows lead, faults before warnings, each with one "Next:" line; every row that is fine is
// folded into "N checks fine", closed, and says no next step.
test('Health: failing rows come first, faults before warnings, each with a next step; the rows that are fine fold into "N checks fine"', () => {
  const w = page('health');
  deliver(w, failing());
  // The row with the Board's feed restart comes last, out of the fold while a check is a fault (issue 115).
  assert.deepEqual(failingRows(w), ['Last push', 'Flaky tests', 'Usage limit', 'Dashboard code', 'Board\'s feed'], 'the fault first, then the warnings in the order drawn');
  for (const label of failingRows(w).slice(0, -1)) assert.match(dd(w, label).querySelector('.check-next')?.textContent ?? '', /^Next: \S/, `${label} says what to do next`);
  assert.match(dd(w, 'Last push').querySelector('.check-next').textContent, /Needs you.*waits until a fix lands on main/);
  const fine = panel(w, 'health').querySelector('details.checks-fine');
  assert.ok(fine && !fine.open, 'the rows that are fine are folded, closed');
  assert.equal(fine.querySelector('summary').textContent, '3 checks fine');
  assert.deepEqual(Array.from(fine.querySelectorAll('dt'), (dt) => dt.dataset.check), ['buildhost', 'Conveyor', 'Codex limit']);
  assert.equal(fine.querySelector('.check-next'), null, 'a row that is fine has no next step');
  // Nothing failing: no failing list, every row folded.
  const ok = page('health');
  deliver(ok, full());
  assert.deepEqual(failingRows(ok), []);
  assert.equal(panel(ok, 'health').querySelector('details.checks-fine summary').textContent, '6 checks fine');
});

// Bugs (UX31): a failing push poured some 25 lines of raw output into its row, the panel grew to about 1,500 px and
// buried the warnings below it; a wait read "retry after 1022 s". The row is one plain line (how long it has failed and
// which check), the output whole under a closed "Show output"; a long error shows its first 100 characters on the row
// and the rest the same way; a wait reads "try again in 17 min".
test('Health: a failing push is one plain line with its output under "Show output"; a long error is cut to its line; a wait reads "try again in"', () => {
  const w = page('health');
  const data = failing();
  data.panels.health.data.accounts = { error: null, list: [{ machine: null, name: 'default', email: 'noreply@example.com', usedPct: null, fiveHourPct: null, resetsAt: null,
    readAt: null, error: 'rate limited (429); retry after 1022 s', usedFor: ['not used by the Conveyor'] }] };
  data.panels.health.data.host.error = `ssh: ${'a very long reason '.repeat(12)}`;
  deliver(w, data);
  const push = dd(w, 'Last push');
  const out = push.querySelector(':scope > details.output');
  assert.ok(out && !out.open, 'the output is under a closed toggle');
  assert.equal(out.querySelector('summary').textContent, 'Show output');
  assert.equal(out.querySelector('.output-text').textContent, PUSH_OUT, 'the output is all there, as the hook printed it');
  const line = Array.from(push.children).filter((n) => n !== out).map((n) => n.textContent).join(' ');
  assert.match(line, /^Failing Push failing for 8 min: typecheck-web failed Next: /);
  assert.ok(!line.includes('error TS2322'), `the row's own line carries none of the output: ${line}`);
  const flaky = dd(w, 'Flaky tests');
  assert.match(flaky.textContent, /^1 case1 case passed only on re-run in the last 7 days/);
  assert.ok(flaky.querySelector(':scope > details.output .issue'), 'each case and its issue under Show output');
  // The row's words, less its closed "Raw error" that holds the error as the host gave it.
  const usage = Array.from(dd(w, 'Account default on this machine').children).filter((n) => !n.matches('details.output')).map((n) => n.textContent).join('');
  assert.ok(usage.includes('the usage server asked for a pause; try again in 17 min') && !/retry after|rate limited/.test(usage), usage);
  const host = dd(w, 'buildhost');
  const cut = host.querySelector(':scope > .detail').textContent;
  assert.equal(cut.length, 100, 'cut to 100 characters');
  assert.ok(cut.endsWith('…'));
  assert.equal(host.querySelector(':scope > details.output .output-text').textContent, data.panels.health.data.host.error.trim(), 'the whole reason under Show output');
});

// Issue 139: a plugin problem a Foreman noted needs the owner, who alone can fix or file it in the plugin's repository.
// Bug it catches: the note sat in the Foreman's folder and Health never said so. The row is a warning that says how
// many and links the file. Bug (review): the link was file://, which a browser does not open from the https Board: it
// is the Board's served copy. Bug (review): a grouped Foreman's notes come once a project (so the project filter keeps
// them), and were drawn as one row each.
test('Health: the plugin problems a Foreman noted are a warning row, "N plugin problems noted", with a link to the file', () => {
  const w = page('health');
  const data = full();
  const note = { projects: ['sample', 'widgetshop'], count: 2, file: '/srv/sample/conveyor/state/foreman/plugin-bugs.md', url: 'plugin-bugs/sample.txt' };
  data.panels.health.data.pluginBugs = [{ repo: 'sample', ...note }, { repo: 'widgetshop', ...note }];
  deliver(w, data);
  assert.ok(failingRows(w).includes('Plugin problems'), `a failing row: ${failingRows(w)}`);
  assert.equal(failingRows(w).filter((t) => t.startsWith('Plugin problems')).length, 1, `one row a file: ${failingRows(w)}`);
  const row = dd(w, 'Plugin problems');
  assert.match(row.textContent, /2 plugin problems noted in \/srv\/sample\/conveyor\/state\/foreman\/plugin-bugs\.md/);
  assert.equal(row.querySelector('a').getAttribute('href'), 'plugin-bugs/sample.txt');
  assert.match(row.querySelector('.check-next').textContent, /conveyor-belt repo/);
  // Bug (#1436): the step said "Then dismiss it" after "file it", but a note filed with File on GitHub leaves the list, so it has no Dismiss.
  assert.match(row.querySelector('.check-next').textContent, /Dismiss, unless you filed it with File on GitHub, which removes the note/);
  // The server keeps the note when the issue is filed but the file cannot be written ("filed as ..., but the note could not be removed"), so the step must still tell to dismiss it then.
  assert.match(row.querySelector('.check-next').textContent, /filed the issue but could not remove the note, click Dismiss/);
  assert.ok(guide('board.md').includes('unless you filed it with File on GitHub, which removes the note'), 'docs/board.md says the same as the Health step');
  assert.ok(guide('board.md').includes('filed the issue but could not remove the note, click Dismiss'), 'docs/board.md names the failed removal too');
  // Bug: the filing guide said the note always leaves the list once filed; it stays when plugin-bugs.md cannot be written. A doc has no behaviour to run, so its text is checked.
  assert.ok(guide('board.md').includes('files the issue but cannot change `plugin-bugs.md`, the note stays, and the preview says so. Then click Dismiss'), 'docs/board.md filing guide names the kept note');
});

// Issue 1042: the owner could only read the notes in the file. Bugs it catches: no pane listing each note with its time,
// card and text; a pane drawn with no note; a Dismiss that posts anything but that one note's file and line (the
// server removes that line and runs no gh); a dismissed note drawn again before the next snapshot drops it.
test('Health: the Plugin problems pane lists each note with its time, card and text, and Dismiss removes only that note', async () => {
  const w = page('health');
  const data = full();
  const file = '/srv/sample/conveyor/state/foreman/plugin-bugs.md';
  const notes = [
    { at: '2026-11-09T16:00:00Z', card: 'c20261109T150000-sample-12', text: 'setup never sets linkFromMain · evidence: -', line: '- 2026-11-09T16:00:00Z · card c20261109T150000-sample-12 · setup never sets linkFromMain · evidence: -' },
    { at: '2026-11-09T16:10:00Z', card: '-', text: 'npm ci runs twice · evidence: -', line: '- 2026-11-09T16:10:00Z · card - · npm ci runs twice · evidence: -' }];
  data.panels.health.data.pluginBugs = [{ repo: 'sample', projects: ['sample'], count: 2, file, url: 'plugin-bugs/sample.txt', notes }];
  deliver(w, data);
  const pane = () => panel(w, 'health').querySelector('section.plugin-problems');
  assert.equal(pane().querySelector('h3').textContent, 'Plugin problems');
  const rows = () => Array.from(pane().querySelectorAll('li.row'));
  assert.equal(rows().length, 2);
  assert.equal(rows()[0].querySelector('.title').textContent, 'setup never sets linkFromMain · evidence: -');
  const meta = (li) => Array.from(li.querySelectorAll('.row-meta > span'), (s) => s.textContent);
  assert.match(meta(rows()[0])[0], /^\d{1,2}:00/, `its time: ${meta(rows()[0])}`);
  assert.equal(meta(rows()[0])[1], 'card c20261109T150000-sample-12');
  assert.match(meta(rows()[1])[0], /^\d{1,2}:10/, `its time: ${meta(rows()[1])}`);
  assert.equal(meta(rows()[1])[1], 'no card');
  rows()[1].querySelector('[data-act="plugin-dismiss"]').click();
  await settle(); await settle();
  assert.deepEqual(w.posts, [{ url: 'plugin-dismiss', body: { file, line: notes[1].line } }], 'one post, of that note alone');
  assert.deepEqual(rows().map((li) => li.querySelector('.title').textContent), ['setup never sets linkFromMain · evidence: -'], 'the dismissed note is gone, the other stays');
  // A failed dismiss keeps the note and says why.
  w.reply = { ok: false, status: 409, text: () => Promise.resolve('that note is no longer in the file; nothing was changed') };
  rows()[0].querySelector('[data-act="plugin-dismiss"]').click();
  await settle(); await settle();
  assert.equal(rows().length, 1);
  assert.match(rows()[0].querySelector('.warn-note').textContent, /^Not dismissed: that note is no longer in the file/);
  // With an empty list, there is no pane.
  const none = clone(data);
  none.panels.health.data.pluginBugs = [];
  next(w, none);
  assert.equal(pane(), null);
});

// Issue 1043: File on GitHub. Bugs it catches: a note filed with no preview or with the proposed text, not the owner's
// edits; edits lost when the live feed draws the panel again; a second note filed with the first; a refused or failed
// filing that dropped the note or its preview with no reason; a filed note left in the list, or its link not shown.
test('Health: File on GitHub previews the issue, files only the confirmed note with its edits, and keeps it on a refusal', async () => {
  const w = page('health');
  const data = full(), file = '/srv/sample/conveyor/state/foreman/plugin-bugs.md';
  const notes = [
    { at: '2026-11-09T16:00:00Z', card: '-', text: 'setup never sets linkFromMain · evidence: -', line: '- 2026-11-09T16:00:00Z · card - · setup never sets linkFromMain · evidence: -' },
    { at: '2026-11-09T16:10:00Z', card: '-', text: 'npm ci runs twice · evidence: -', line: '- 2026-11-09T16:10:00Z · card - · npm ci runs twice · evidence: -' },
    { at: '2026-11-09T16:20:00Z', card: '-', text: 'running cards keep the old engine code, filed as #449 · evidence: -', line: '- 2026-11-09T16:20:00Z · card - · running cards keep the old engine code, filed as #449 · evidence: -' }];
  data.panels.health.data.pluginBugs = [{ repo: 'sample', projects: ['sample'], count: 3, file, url: 'plugin-bugs/sample.txt', notes }];
  deliver(w, data);
  const pane = () => panel(w, 'health').querySelector('section.plugin-problems');
  const rows = () => Array.from(pane().querySelectorAll('li.row'));
  // Bug (E2): a note the Foreman marked "filed as #<n>" offered File on GitHub, so it could be filed a second time.
  assert.deepEqual(rows().map((li) => !!li.querySelector('[data-act="plugin-file-open"]')), [true, true, false], 'a note that names its issue is not offered for filing');
  assert.ok(rows()[2].querySelector('[data-act="plugin-dismiss"]'), 'it can still be dismissed');
  const answer = (status, text) => ({ ok: status === 200, status, text: () => Promise.resolve(text) });
  w.replies = { 'plugin-preview': answer(200, JSON.stringify({ title: 'npm ci runs twice', body: 'npm ci runs twice · evidence: -\n\nPlugin version: 1.7.0\n', repo: 'owner/plugin' })) };
  rows()[1].querySelector('[data-act="plugin-file-open"]').click();
  await settle(); await settle();
  assert.deepEqual(w.posts, [{ url: 'plugin-preview', body: { file, line: notes[1].line } }], 'the preview is asked for that note; nothing is filed yet');
  assert.equal(rows()[0].querySelector('.plugin-preview'), null, 'the other note has no preview');
  const title = () => rows()[1].querySelector('input.plugin-title'), body = () => rows()[1].querySelector('textarea.plugin-body');
  assert.equal(title().value, 'npm ci runs twice');
  assert.match(body().value, /Plugin version: 1\.7\.0/);
  assert.match(rows()[1].querySelector('.plugin-preview').textContent, /owner\/plugin on GitHub/);
  title().value = 'npm ci runs twice in setup';
  body().value = 'npm ci runs twice in setup, edited\n';
  next(w, clone(data));
  assert.equal(title().value, 'npm ci runs twice in setup', 'an edit stays when the panel is drawn again');
  assert.equal(body().value, 'npm ci runs twice in setup, edited\n', 'a body edit stays when the panel is drawn again');
  // Refused by the privacy check: the preview stays, and names the hit.
  w.replies['plugin-file'] = answer(422, 'nothing was filed: the privacy check found body line 3: home path');
  rows()[1].querySelector('[data-act="plugin-file"]').click();
  await settle(); await settle();
  assert.equal(rows().length, 3);
  assert.match(rows()[1].querySelector('.plugin-preview .warn-note').textContent, /^Not filed: .*body line 3: home path\.$/);
  // gh failed: the note stays, with gh's error.
  w.replies['plugin-file'] = answer(502, 'nothing was filed: gh issue create failed: HTTP 401');
  rows()[1].querySelector('[data-act="plugin-file"]').click();
  await settle(); await settle();
  assert.equal(rows().length, 3);
  assert.match(rows()[1].querySelector('.plugin-preview .warn-note').textContent, /gh issue create failed: HTTP 401/);
  // Filed, but the note could not be removed: it says so, not "Not filed".
  w.replies['plugin-file'] = answer(500, 'filed as https://github.com/owner/plugin/issues/8, but the note could not be removed: Permission denied');
  rows()[1].querySelector('[data-act="plugin-file"]').click();
  await settle(); await settle();
  assert.match(rows()[1].querySelector('.plugin-preview .warn-note').textContent, /^Filed as https:\/\/github\.com\/owner\/plugin\/issues\/8, but the note could not be removed/);
  w.replies['plugin-file'] = answer(200, 'https://github.com/owner/plugin/issues/9');
  rows()[1].querySelector('[data-act="plugin-file"]').click();
  await settle(); await settle();
  const filed = w.posts.filter((p) => p.url === 'plugin-file');
  assert.equal(filed.length, 4);
  // Bug (E3): the proposed body was sent in place of the owner's edited one.
  assert.ok(filed.every((p) => p.body.line === notes[1].line && p.body.title === 'npm ci runs twice in setup'
    && p.body.body === 'npm ci runs twice in setup, edited\n'), 'only that note, with the edited title and body');
  assert.deepEqual(rows().map((li) => li.querySelector('.title').textContent), [notes[0].text, notes[2].text], 'the filed note leaves; the other notes stay');
  assert.ok(rows()[0].querySelector('[data-act="plugin-file-open"]'), 'the note not approved stays unfiled: it is still offered for filing');
  assert.equal(pane().querySelector('.plugin-filed a').getAttribute('href'), 'https://github.com/owner/plugin/issues/9');
  next(w, clone(data));
  assert.equal(pane().querySelector('.plugin-filed a').getAttribute('href'), 'https://github.com/owner/plugin/issues/9', 'the link stays for the session');
});

// Bug (R28): a reply line ending ",filed as #449" (no space) left a note that was offered for filing a second time.
test('Health: a note ending ",filed as #449" with no space is not offered for filing', () => {
  const w = page('health');
  const data = full(), line = '- 2026-11-09T16:20:00Z · card - · running cards keep the old engine code,filed as #449 · evidence: -';
  data.panels.health.data.pluginBugs = [{ repo: 'sample', projects: ['sample'], count: 1, file: '/srv/sample/conveyor/state/foreman/plugin-bugs.md', url: 'plugin-bugs/sample.txt',
    notes: [{ at: '2026-11-09T16:20:00Z', card: '-', text: 'running cards keep the old engine code,filed as #449 · evidence: -', line }] }];
  deliver(w, data);
  const li = panel(w, 'health').querySelector('section.plugin-problems li.row');
  assert.equal(li.querySelector('[data-act="plugin-file-open"]'), null, `no File on GitHub for: ${line}`);
  assert.ok(li.querySelector('[data-act="plugin-dismiss"]'), 'it can still be dismissed');
});

// Bug: the live feed rewrites the stream every 10 s and the panel is drawn again on each write, so an opened "Show
// output" or "checks fine" closed under the owner while they read it. What was open stays open; what was not, stays shut.
// Bug (#557): the push's output was a new box at each draw, so a reader scrolled in it went back to its top.
test('Health: an opened "Show output" and "checks fine" stay open when the live feed draws the panel again', async () => {
  const w = page('health', { feed: true });
  const es = w.sources[0];
  const data = failing();
  data.panels.health.data.stream = { live: true, heardAt: iso(T0), since: null, error: null, writtenAt: iso(T0) };
  es.readyState = 0; es.emit('error'); // the feed opens after a first failed try: the page is drawn from data.js meanwhile
  deliver(w, data);
  es.readyState = 1; es.emit('open');
  const out = dd(w, 'Last push').querySelector(':scope > details.output');
  out.open = true;
  out.querySelector('pre.output-text').scrollTop = 120;
  panel(w, 'health').querySelector('details.checks-fine').open = true;
  const before = dd(w, 'Last push');
  const part = clone(data.panels.health);
  part.data.stream.writtenAt = iso(T0 + 10000);
  es.emit('panel', { id: 'health', part, updatedAt: iso(T0 + 10000) });
  assert.notEqual(dd(w, 'Last push'), before, 'the panel was drawn again');
  assert.ok(dd(w, 'Last push').querySelector(':scope > details.output').open, "the push's output stays open");
  await Promise.resolve();
  assert.equal(dd(w, 'Last push').querySelector(':scope > details.output'), out, 'the same output keeps the same box');
  assert.equal(out.querySelector('pre.output-text').scrollTop, 120, 'and its scroll');
  assert.ok(panel(w, 'health').querySelector('details.checks-fine').open, '"checks fine" stays open');
  assert.equal(dd(w, 'Flaky tests').querySelector(':scope > details.output').open, false, 'a toggle not opened stays shut');
});

// Bug: a Live data row that goes stale between snapshots stayed folded among the rows that are fine.
test('Health: the Data row that turns stale on a tick leaves "checks fine" and leads the panel with its next step', () => {
  const w = page('health', { feed: true });
  const es = w.sources[0];
  const data = full();
  data.panels.health.data.stream = { live: true, heardAt: iso(T0), since: null, error: null, writtenAt: iso(T0) };
  es.readyState = 0; es.emit('error'); // the feed opens after a first failed try: the page is drawn from data.js meanwhile
  deliver(w, data);
  es.readyState = 1; es.emit('open');
  es.emit('panel', { id: 'health', part: clone(data.panels.health), updatedAt: iso(T0) });
  assert.ok(panel(w, 'health').querySelector('details.checks-fine dt[data-check="Data"]'), 'Live is fine');
  tick(w, 91000); // past health.js STREAM_EXPIRE_MS (90 s)
  assert.deepEqual(failingRows(w), ['Data']);
  assert.match(dd(w, 'Data').textContent, /91 s old.*the live feed stopped.*Next: Reload the page.*press Restart the Board's feed, below\./);
  // Issue 115: the restart its next step names is in the row, also once the tick has drawn the row again.
  assert.equal(dd(w, 'Data').querySelector('[data-act="restart"]')?.textContent, 'Restart the Board\'s feed');
});

// Issue 407 (UX3). Bug: three words for the same wait ("the next snapshot", "the next reading", "within a minute");
// Health's next steps still said "The next snapshot reads it again". Each says "in about a minute".
test('Health: a row not read or not checked says it is tried again "in about a minute", never "the next snapshot"', () => {
  const w = page('health');
  const data = full(), hd = data.panels.health.data;
  hd.host.reachable = null;
  hd.accounts = { list: [], error: 'ssh: no answer' };
  deliver(w, data);
  // #112: a host not checked says to correct the host file as its error says, never that a build machine is needed.
  assert.match(dd(w, 'buildhost').textContent, /Next: The Board checks it again in about a minute\. Before that check, correct the host file as the error says\./);
  assert.match(dd(w, 'Host accounts').textContent, /Next: The Board reads them again in about a minute\./);
  assert.doesNotMatch(panel(w, 'health').textContent, /snapshot|next reading/i);
});

// Issue 440. Bug: every usage read was refused (429) from 09:00 and Health went on showing 53% from 09:00 as a row
// that is fine, with only "showing the last reading" and no age; the account row the same. A reading older than 15
// min says when it was read and how long ago, and its row is a warning with a next step; a fresh one says neither.
test('Health: a usage or account reading 6 h old shows its age and a warning chip; a fresh one shows neither', () => {
  const at = (ms) => {
    const data = full(), hd = data.panels.health.data;
    hd.limits[0].readAt = iso(T0 - ms);
    hd.accounts = { error: null, list: [{ machine: null, name: 'default', email: 'noreply@example.com', usedPct: 53, fiveHourPct: 10, resetsAt: null,
      readAt: iso(T0 - ms), error: 'rate limited (429)', usedFor: ['cards of sample: build and fix'], cards: true, others: true }] };
    const w = page('health');
    deliver(w, data);
    return w;
  };
  const stale = at(6 * 3600000);
  assert.deepEqual(failingRows(stale), ['Usage limit', 'Account default on this machine']);
  const usage = dd(stale, 'Usage limit');
  assert.equal(usage.querySelector(':scope > .chip').textContent, 'Old reading');
  assert.match(usage.textContent, /from \d{1,2}:\d{2}.*, 6 h 00 min ago/);
  assert.match(usage.textContent, /Next: Conveyor reads it again before its next pick\./);
  const acct = dd(stale, 'Account default on this machine');
  assert.ok(acct.querySelector(':scope > .chip.chip-warn'), 'the account row is a warning');
  assert.match(acct.textContent, /53% used.*from \d{1,2}:\d{2}.*, 6 h 00 min ago.*the usage server asked for a pause.*Next: The Board reads it again by itself/);
  const fresh = at(60000);
  assert.deepEqual(failingRows(fresh), [], 'a reading a minute old is fine');
  assert.doesNotMatch(panel(fresh, 'health').textContent, /Old reading| ago\b/);
});

// Issue 623. Bug: the Usage limit row showed this machine's own login (its ~/.claude.json still named the old account
// B, at 92%) while the build machine's guard read the cards' account A at 3%. The row is the snapshot's reading of the
// account the cards run on, with that machine's login; this machine's own reading and account are not in it.
test('Health: the usage limit is the reading of the account the cards run on, not this machine\'s own login', () => {
  const data = full(), hd = data.panels.health.data;
  Object.assign(hd.limit, { usedPct: 92, fiveHour: { usedPct: 70 } });
  hd.accounts = { error: null, list: [{ machine: null, name: 'default', email: 'noreply-b@example.com', usedPct: 92, fiveHourPct: 70, resetsAt: null,
    readAt: iso(T0 - 60000), error: null, usedFor: ['not used by the Conveyor'] }] };
  hd.limits = [{ repo: 'sample', account: null, uses: ['build', 'review'], pct: 3, readAt: iso(T0 - 60000), email: 'noreply-a@example.com' }];
  const w = page('health');
  deliver(w, data);
  const usage = dd(w, 'Usage limit');
  assert.match(usage.textContent, /^Fine3% of the 7-day limit usedaccount default, noreply-a@example\.com: build and fix and reviews$/);
  assert.equal(usage.querySelector('.meter').getAttribute('aria-label'), '3 percent of the 7-day limit used');
  assert.equal(panel(w, 'health').querySelector('dt[data-check="5-hour window"]'), null, "this machine's 5-hour window is not shown as the cards' account's");
});

// Issue 623: a project whose builder and reviewer run on two accounts shows the reading of each, named, and one not
// read yet says so. Bug it catches: one figure for the project, hiding the account at its limit.
test('Health: a builder account and a reviewer account each show their own reading', () => {
  const data = full();
  data.panels.health.data.limits = [
    { repo: 'sample', account: 'builder', uses: ['build'], pct: 40, readAt: iso(T0 - 60000), email: 'noreply-a@example.com' },
    { repo: 'sample', account: 'reviewer', uses: ['review'], pct: 95, readAt: iso(T0 - 60000), email: 'noreply-c@example.com' },
    { repo: 'sample', account: 'third', uses: ['review'], pct: null, readAt: null, email: null }];
  const w = page('health');
  deliver(w, data);
  assert.match(dd(w, 'Usage limit of sample: builder').textContent, /^Fine40% of the 7-day limit usedaccount builder, noreply-a@example\.com: build and fix$/);
  const rev = dd(w, 'Usage limit of sample: reviewer');
  assert.match(rev.textContent, /^Nearly used up95% of the 7-day limit usedaccount reviewer, noreply-c@example\.com: reviewsNext: Wait for the reset/);
  assert.match(dd(w, 'Usage limit of sample: third').textContent, /^Not readno reading yetaccount third, no email recorded: reviewsNext: Conveyor reads it again before its next pick\.$/);
  assert.equal(panel(w, 'health').querySelector('dt[data-check="Usage limit"]'), null, 'no row without its account');
});

// Issue 636. Bug: with a Codex builder and a Claude fix or testFix seat, the Claude account only repairs, yet its row
// said "build and fix". The snapshot names that use "fix", and the row says so.
test('Health: an account that only repairs says fix, not build and fix', () => {
  const data = full();
  data.panels.health.data.limits = [{ repo: 'sample', account: 'repairs', uses: ['fix'], pct: 40, readAt: iso(T0 - 60000), email: 'noreply-a@example.com' }];
  const w = page('health');
  deliver(w, data);
  assert.match(dd(w, 'Usage limit').textContent, /^Fine40% of the 7-day limit usedaccount repairs, noreply-a@example\.com: fix$/);
  // Issue 707: a `fix: 'fix'` entry in USES draws the same text as the `USES[s] || s` fallback, so no rendered behaviour
  // can tell it apart; only the source can. The row above proves the fallback still says "fix" without it.
  const src = readFileSync(new URL('../../dashboard/panels/health.js', import.meta.url), 'utf8');
  assert.match(src, /const USES = \{ build: 'build and fix', review: 'reviews' \};/, 'USES maps only the uses it renames');
});

// Issue 151. Bug: on a machine whose every role runs on an API route (billed per token, no subscription), Health warned
// for ever that the usage limit was not read and that the default account, used by no card, had a pause from the usage
// server. The record's routes name no role on the subscription, the engine reads no account for it (limits empty), and
// the Usage limit row is a fine check that gives the day's cost from the session logs. That cost (limit.today) counts
// the Board's own project's sessions alone, so it was wrong to give it as the machine's: it shows, named for its
// project, on the row of the record on the host's main (steered) only, and each record on the API has its own row.
test('Health: with every role on an API route, no usage or account warning, and a fine Usage limit row with the cost', () => {
  const data = full(), hd = data.panels.health.data;
  const routes = { subscription: { state: 'not used', roles: [] }, proxy: { state: 'works', baseUrl: 'http://192.0.2.1:4141', roles: { builder: 'proxy', reviewer: 'proxy' }, route: 'proxy' } };
  hd.records = [{ ...hd.records[0], steered: true, routes }, { ...hd.records[0], repo: 'widgetshop', steered: false, routes }];
  hd.limits = [];
  hd.limit.today = { spentUsd: 4.25 };
  hd.host.local = true;
  hd.accounts ={ error: null, list: [{ machine: null, name: 'default', email: 'noreply@example.com', usedPct: null, fiveHourPct: null, resetsAt: null,
    readAt: null, error: 'rate limited (429)', usedFor: ["this machine's Foreman"], cards: false, others: false }] };
  const w = page('health');
  deliver(w, data);
  assert.deepEqual(failingRows(w), [], 'no warning');
  assert.match(dd(w, 'Usage limit of sample').textContent, /^FineAPI route: no usage limit \(billed per token\)\$4\.25 spent today on sample on this machine, from the session logs$/);
  assert.equal(dd(w, 'Usage limit of widgetshop').textContent, 'FineAPI route: no usage limit (billed per token)');
});

// Issue 151. Bug: the API row gave this machine's cost (limit.today, read from its own session logs) once for every
// record on an API route, even with the cards built on a build machine apart, whose cost those logs do not hold. The
// record on the host's main, on a build machine: a fine row, and no cost.
test('Health: an API route on a build machine apart gives a fine row and not this machine\'s cost', () => {
  const data = full(), hd = data.panels.health.data;
  hd.records[0].steered = true;
  hd.records[0].routes = { subscription: { state: 'not used', roles: [] }, proxy: { state: 'works', baseUrl: 'http://192.0.2.1:4141', roles: { builder: 'proxy', reviewer: 'proxy' }, route: 'proxy' } };
  hd.limits = [];
  hd.limit.today = { spentUsd: 4.25 };
  const w = page('health');
  deliver(w, data);
  assert.deepEqual(failingRows(w), [], 'no warning');
  assert.equal(dd(w, 'Usage limit').textContent, 'FineAPI route: no usage limit (billed per token)');
  assert.doesNotMatch(panel(w, 'health').textContent, /spent today/);
});

// Issue 151: with mixed routes (the builder on the API, the reviewer on a subscription), the subscription role's
// reading is the only Usage limit row: no API row stands beside it, and a missing reading of it still warns.
test('Health: with mixed routes, only the subscription role\'s usage limit shows', () => {
  const data = full(), hd = data.panels.health.data;
  hd.records[0].routes = { subscription: { state: 'works', roles: ['reviewer'] }, proxy: { state: 'works', baseUrl: 'http://192.0.2.1:4141', roles: { builder: 'proxy', reviewer: 'subscription' }, route: 'proxy' } };
  hd.limits = [{ repo: 'sample', account: 'second', uses: ['review'], pct: null, readAt: null, email: null }];
  const w = page('health');
  deliver(w, data);
  assert.deepEqual(failingRows(w), ['Usage limit']);
  assert.match(dd(w, 'Usage limit').textContent, /^Not readno reading yetaccount second, no email recorded: reviewsNext:/);
  assert.doesNotMatch(panel(w, 'health').textContent, /API route/);
});

// Issue 515. Bug: a project whose test command prints no `TESTRUN sec` lines recorded no test times on any card, and
// Health said nothing. The record's untimed (the last card test runs with no times) is a warning row that names the
// README section on how to add them; 0 shows no row.
test('Health: card test runs that recorded no test times are a warning that names the README section', () => {
  const at = (n) => {
    const data = full();
    data.panels.health.data.records[0].untimed = n;
    const w = page('health');
    deliver(w, data);
    return w;
  };
  const none = at(3);
  assert.deepEqual(failingRows(none), ['Test times']);
  const row = dd(none, 'Test times');
  assert.equal(row.querySelector(':scope > .chip.chip-warn').textContent, 'Not recorded');
  assert.match(row.textContent, /the last 3 card test runs recorded no test times.*Next: .*"Test file times" in conveyor\/README\.md/);
  assert.equal(panel(at(0), 'health').querySelector('dt[data-check="Test times"]'), null, 'runs that recorded times show no row');
});

// Issue 157. Bug: a record line the check refused stopped the loop and the snapshot; now it is set aside, and Health
// must name it, or the owner never learns a line left the records. Each line set aside is a warning row naming its
// line and the field refused; none shows no row.
test('Health: a card record line set aside names its line and the field the check refused', () => {
  const at = (q) => {
    const data = full();
    data.panels.health.data.records[0].quarantined = q;
    const w = page('health');
    deliver(w, data);
    return w;
  };
  const w = at([{ line: 2518, field: 'list', time: iso(T0) }]);
  assert.deepEqual(failingRows(w), ['Records set aside']);
  const row = dd(w, 'Records set aside');
  assert.equal(row.querySelector(':scope > .chip.chip-warn').textContent, '1 line');
  assert.match(row.textContent, /line 2518: list refused.*Next: .*quarantined\.jsonl/);
  assert.equal(panel(at([]), 'health').querySelector('dt[data-check="Records set aside"]'), null, 'nothing set aside shows no row');
});

// #152. Bug: on a project whose runner setup found (the record's report, the pack's test.report) but whose output
// Conveyor cannot read, the row said only to print TESTRUN lines. It names the runner and the report option to add.
test('Health: no test times from a runner Conveyor cannot read names the runner and its report option', () => {
  const data = full();
  Object.assign(data.panels.health.data.records[0], { untimed: 5, report: { runner: 'jest', option: '--json --outputFile=<file>' } });
  const w = page('health');
  deliver(w, data);
  const row = dd(w, 'Test times');
  assert.match(row.textContent, /the last 5 card test runs recorded no test times; the test command runs jest, and Conveyor cannot read its output/);
  assert.match(row.textContent, /Next: Add the report option --json --outputFile=<file> to the test command, then run setup again/);
});

// #1355. Bug: the Test times warning only pointed at the README, whatever the test command was. With the engine's plan
// (timesPlan, one kind for each kind of test command) it says what the plan does and its button sends
// `test-settings record-times` for that project; the row has no README pointer. A refusal (a member) is shown, not lost.
const TIMES_PLANS = {
  report: [{ kind: 'report', report: { runner: 'node --test', format: 'junit' } }, /sets test\.report in the pack to the report of node --test, so Conveyor reads each test file's times from it/],
  wrap: [{ kind: 'wrap', file: 'w.test.sh', was: 'bash w.test.sh', command: 'wrapped bash w.test.sh' }, /wraps the test command, which runs only w\.test\.sh, in the helper that prints test times, and saves wrapped bash w\.test\.sh as test\.command/],
  // Bug: the wrap words left out test.fileCommand, which the engine's plan also saves, so an admin did not see it.
  'wrap with a file command': [{ kind: 'wrap', file: 'w.test.sh', was: 'bash w.test.sh', command: 'wrapped bash w.test.sh', fileCommand: 'wrapped bash' }, /saves wrapped bash w\.test\.sh as test\.command, and wrapped bash as test\.fileCommand in the pack/],
  card: [{ kind: 'card', file: 'run-all.sh', title: 'Record test times: wrap each test file\'s run in run-all.sh', body: 'steps' }, /files a held card, with no GitHub issue, to wrap each test file's run in run-all\.sh: that script is yours\. Release the card when you agree/],
};
for (const [kind, [plan, words]] of Object.entries(TIMES_PLANS)) {
  test(`Health: the Test times warning for a ${kind} plan says what it does and its button records the times`, async () => {
    const data = full();
    Object.assign(data.panels.health.data.records[0], { untimed: 2, timesPlan: plan });
    const w = page('health');
    deliver(w, data);
    const row = dd(w, 'Test times');
    assert.match(row.querySelector('.check-next').textContent, words);
    assert.doesNotMatch(row.textContent, /README/, 'the row has no README pointer');
    row.querySelector('[data-act="record-times"]').click();
    await settle(); await settle();
    assert.deepEqual(w.posts, [{ url: 'control', body: { action: 'test-settings', args: ['record-times'], repo: data.panels.health.data.records[0].repo } }]);
    assert.match(dd(w, 'Test times').textContent, /Done: sent to main/);
  });
}
test('Health: a refused Record test times says why and keeps its button', async () => {
  const data = full();
  Object.assign(data.panels.health.data.records[0], { untimed: 2, timesPlan: TIMES_PLANS.report[0] });
  const w = page('health');
  deliver(w, data);
  w.reply = { ok: false, status: 403, text: () => Promise.resolve('only an admin changes the test command') };
  dd(w, 'Test times').querySelector('[data-act="record-times"]').click();
  await settle(); await settle();
  assert.match(dd(w, 'Test times').textContent, /Not recorded:\s*only an admin changes the test command/);
  assert.ok(dd(w, 'Test times').querySelector('[data-act="record-times"]:not([disabled])'), 'the button can be pressed again');
});

// Issue 629. Bug: Health told the owner to "Move this account's work to another on the Rules tab" for a 92% account
// no card runs on, and for one the cards use when the host file listed no other account to move to; a failed read
// showed "HTTP 401". Each fixture is one Claude account on the build machine.
const account = (over) => {
  const data = full();
  data.panels.health.data.accounts = { error: null, list: [{ machine: 'devbox', name: 'default', email: 'noreply@example.com', usedPct: 92, fiveHourPct: 40,
    resetsAt: iso(T0 + 2 * 3600000), readAt: iso(T0 - 60000), error: null, usedFor: ['cards of sample: build and fix'], cards: true, others: false, ...over }] };
  const w = page('health');
  deliver(w, data);
  return dd(w, 'Account default on devbox');
};
test('Health: an account no card runs on, at 92%, is a dim row with its reading and no next step', () => {
  const row = account({ usedFor: ['not used by the Conveyor'], cards: false });
  assert.ok(row.querySelector(':scope > .chip.chip-quiet'), 'a dim chip, not a fault');
  assert.match(row.textContent, /92% used.*not used by the Conveyor/);
  assert.equal(row.querySelector('.check-next'), null, 'no next step: there is no work to move');
});
test('Health: a used account at 92% with no other account listed is told to wait for its reset and where accounts are added', () => {
  const next = account({}).querySelector('.check-next');
  assert.ok(next.textContent.startsWith('Next: Wait for its reset at '), next.textContent);
  assert.match(next.textContent, /add one to accounts in the build machine's host file/);
  assert.doesNotMatch(next.textContent, /Rules tab/);
  assert.match(next.querySelector('a').href, /conveyor\/README\.md#accounts$/, 'linked to the page that explains the host file accounts');
});
test('Health: a used account at 92% with another account to move to names the Rules tab', () => {
  assert.match(account({ others: true }).querySelector('.check-next').textContent, /^Next: Move this account's work to another on the Rules tab, or wait for its reset at /);
});
// Bug: on a machine whose Claude subscription login had expired, Health showed nothing of it, nor of the API proxy that
// could carry the sessions, so every card was blocked with no row saying why. Each route is a row with its state: a
// failed login is a fault with no proxy to fall back on, and a warning while a fallback proxy works.
const routes = (r) => {
  const data = full();
  data.panels.health.data.records[0].routes = r;
  const w = page('health');
  deliver(w, data);
  return w;
};
test('Health: an expired subscription login with no proxy set is a fault that says to sign in or set a proxy', () => {
  const w = routes({ subscription: { state: 'expired', at: iso(T0 - 60000) }, proxy: { state: 'not set' } });
  const sub = dd(w, 'Claude route: subscription login');
  assert.equal(sub.querySelector(':scope > .chip.chip-bad').textContent, 'Expired');
  assert.match(sub.querySelector('.check-next').textContent, /run claude, then \/login.*\/conveyor-belt:setup/);
  assert.equal(dd(w, 'Claude route: API proxy').querySelector(':scope > .chip').textContent, 'Not set');
});
// Each role has its own route, so the proxy row says when each one uses it.
test('Health: an expired subscription login while the fallback proxy works is a warning; the proxy row names its URL and each role\'s route', () => {
  const w = routes({ subscription: { state: 'expired', at: iso(T0 - 60000) },
    proxy: { state: 'works', at: iso(T0 - 30000), baseUrl: 'http://127.0.0.1:4141', route: 'fallback', roles: { builder: 'fallback', reviewer: 'proxy' } } });
  assert.equal(dd(w, 'Claude route: subscription login').querySelector(':scope > .chip.chip-warn').textContent, 'Expired');
  const px = dd(w, 'Claude route: API proxy');
  assert.equal(px.querySelector(':scope > .chip.chip-ok').textContent, 'Works');
  assert.match(px.textContent, /http:\/\/127\.0\.0\.1:4141, the builder when its subscription login fails, the reviewer always/);
});
// A card's timeline says which route each Claude step took, so a build that ran through the proxy is told from one on
// the subscription login.
test('Metrics: a step that ran through the API proxy says so in the card timeline, and one on the subscription login says that', () => {
  const data = full(), card = data.panels.metrics.data.cards.find((c) => c.title === 'Landed one');
  card.metrics = { ...card.metrics, timeline: card.metrics.timeline.map((s, i) => (i === 0 ? { ...s, route: 'proxy' } : i === 1 ? { ...s, route: 'subscription' } : s)) };
  const w = page('metrics');
  deliver(w, data);
  const det = Array.from(panel(w, 'metrics').querySelectorAll('details.card-detail')).find((d) => d.querySelector('.title').textContent === 'Landed one');
  det.querySelector('summary').click();
  const lines = Array.from(det.querySelectorAll('.timeline li'), (li) => li.textContent);
  // '<model> at <effort>', as the Board says it elsewhere: the timeline said 'claude-sonnet-5-5 medium'.
  assert.match(lines[0], /^build · .* · claude-sonnet-5-5 at medium · through the API proxy · /);
  assert.match(lines[1], / · on the subscription login( · |$)/);
  assert.doesNotMatch(lines[2], /API proxy|subscription/, 'a step with no route names none');
});
// Issue 410. Bug it catches: gh signed in while its check with GitHub failed (ghReached false) showed no GitHub row,
// so the Board gave no sign of it; signed out is still the "Not signed in" fault.
test('Health: gh signed in but GitHub not reached is a warning row, never "Not signed in"', () => {
  const data = full();
  Object.assign(data.panels.health.data.records[0], { gh: true, ghReached: false });
  const w = page('health');
  deliver(w, data);
  const dt = Array.from(panel(w, 'health').querySelectorAll('dt[data-check]')).find((d) => d.dataset.check.startsWith('GitHub'));
  assert.ok(dt, 'a GitHub row');
  assert.equal(dt.nextElementSibling.querySelector(':scope > .chip.chip-warn').textContent, 'Not reached');
  assert.doesNotMatch(panel(w, 'health').textContent, /Not signed in/);
});
// Issue 1655. Bug it catches: a running loop that picks nothing because the card folder's free disk is under the floor
// showed "Running", and the Disk row "Low", with no word that picks had paused.
test('Health: a running loop paused by the free disk floor is a "Paused" warning that says why', () => {
  const data = full(), state = 'paused: free disk 2.5 GB under the 3 GB floor';
  Object.assign(data.panels.health.data.records[0], { loop: true, state, diskFreeKb: 2621440 });
  const w = page('health');
  deliver(w, data);
  const row = dd(w, 'Conveyor');
  assert.equal(row.querySelector(':scope > .chip.chip-warn')?.textContent, 'Paused', `the loop row with state "${state}": ${row.textContent}`);
  assert.match(row.textContent, /paused: free disk 2\.5 GB under the 3 GB floor/, `the loop row with state "${state}"`);
});
test('Health: a proxy that fails is a fault with a next step', () => {
  const w = routes({ subscription: { state: 'expired' }, proxy: { state: 'fails', baseUrl: 'http://127.0.0.1:4141', route: 'fallback' } });
  assert.equal(dd(w, 'Claude route: subscription login').querySelector(':scope > .chip.chip-bad').textContent, 'Expired');
  assert.match(dd(w, 'Claude route: API proxy').querySelector('.check-next').textContent, /Start the proxy on the build machine/);
});
test('Health: a read refused with HTTP 401 says the login has expired and where to sign in again', () => {
  const row = account({ usedPct: null, readAt: null, error: 'HTTP 401' });
  assert.match(row.textContent, /this login has expired: sign in again on devbox/);
  // The host's words only under the closed "Raw error".
  assert.doesNotMatch(Array.from(row.children).filter((n) => !n.matches('details.output')).map((n) => n.textContent).join(''), /HTTP 401/);
});
// Issue 185. Bug it catches: the machine's Conveyor ran an older commit that refused a pack field it did not know, and
// Health showed no sign of it. The row is a fault that names the commit, the field and what to run; none without it.
test("Health: the machine's Conveyor on an older commit that refuses the pack names the field and what to run", () => {
  const w = page('health');
  const data = full();
  data.panels.health.data.records[0].serviceOld = { commit: `090ab497${'0'.repeat(32)}`, refused: '.tests', project: `c4bc952b${'1'.repeat(32)}` };
  deliver(w, data);
  assert.equal(failingRows(w)[0], "Conveyor's version", 'a fault, first');
  const row = dd(w, "Conveyor's version");
  assert.match(row.textContent, /^Too old for the pack.*Conveyor 090ab4970000 on the build machine refuses the pack: \.tests/);
  assert.match(row.querySelector('.check-next').textContent, /^Next: Run conveyor\.sh install-service in the project's checkout on the build machine\. It starts Conveyor again on the project's commit c4bc952b1111\.$/);
  const ok = page('health');
  deliver(ok, full());
  assert.equal(panel(ok, 'health').querySelector('dt[data-check="Conveyor\'s version"]'), null, 'no row while the machine reads the pack');
});
// Issue 346. Bug it catches: the machine room is removed, so no card or test waits for the machine's pressure, yet a
// snapshot from an engine that still sends it drew a Strained "Machine room" warning that holds nothing back.
test('Health: no Machine room row, even from a snapshot that still carries the pressure', () => {
  const w = page('health');
  const data = full();
  data.panels.health.data.records[0].pressure = { state: 'Strained', cpu: 85.5, memory: 1.5, wakeMs: 0.2, freeMB: null, why: 'CPU pressure 85.5% is at or above 80%', gates: true };
  deliver(w, data);
  assert.equal(panel(w, 'health').querySelector('dt[data-check="Machine room"]'), null);
  assert.doesNotMatch(panel(w, 'health').textContent, /Machine room|Strained|wake delay/);
});
// Issue 398. Bug it catches: readers print the kept snapshot, which can be older than what the page shows it as; a
// snapshot over a minute old says so (its age) with what to do, and a newer one adds no row. One shown at 30 s that
// grows over a minute old with no new data (an equal part draws nothing) turns into the warning on a tick.
test('Health: a kept snapshot turns into a warning with its age on the tick it is over a minute old, with no new data', () => {
  const w = page('health');
  const data = full();
  data.panels.health.data.records[0].snapshotAt = iso(T0 - 30000);
  deliver(w, data);
  assert.equal(panel(w, 'health').querySelector('dt[data-check="Snapshot"]'), null, 'no row for a snapshot 30 s old');
  tick(w, 25000);
  assert.equal(panel(w, 'health').querySelector('dt[data-check="Snapshot"]'), null, 'still no row at 55 s');
  tick(w, 35000);
  assert.ok(failingRows(w).includes('Snapshot'), 'the snapshot now 90 s old is a failing row');
  const row = dd(w, 'Snapshot');
  assert.match(row.textContent, /^Old.*made.*1 min.*ago/);
  assert.match(row.querySelector('.check-next').textContent, /^Next: .*conveyor\.sh snapshot --fresh/);
});

// Bug: a landed card not pushed sent the owner to the Rules tab for Push landed, which is on the Control tab.
test('Health: cards not pushed name Push landed on the Control tab', () => {
  const w = page('health');
  const data = full();
  data.panels.health.data.records[0].unpushed = [{ card: 'c1-7', issue: 7, since: iso(T0 - 600000) }];
  deliver(w, data);
  assert.match(dd(w, 'Last push').querySelector('.check-next').textContent, /Push landed on the Control tab pushes them\.$/);
});
