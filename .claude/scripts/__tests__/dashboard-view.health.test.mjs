// SPDX-License-Identifier: Apache-2.0
// The Health panel read at a glance (the Board audit's UX23 and UX31): failing rows first, each with its next step; the
// rows that are fine folded into "N checks fine"; a row's raw output under "Show output". Shared setup:
// dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { T0, iso, clone, boot, panel, deliver, tick, full, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
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
  const w = boot();
  deliver(w, failing());
  assert.deepEqual(failingRows(w), ['Last push', 'Flaky tests', 'Usage limit', 'Dashboard code'], 'the fault first, then the warnings in the order drawn');
  for (const label of failingRows(w)) assert.match(dd(w, label).querySelector('.check-next')?.textContent ?? '', /^Next: \S/, `${label} says what to do next`);
  assert.match(dd(w, 'Last push').querySelector('.check-next').textContent, /Needs you.*waits until a fix lands on main/);
  const fine = panel(w, 'health').querySelector('details.checks-fine');
  assert.ok(fine && !fine.open, 'the rows that are fine are folded, closed');
  assert.equal(fine.querySelector('summary').textContent, '4 checks fine');
  assert.deepEqual(Array.from(fine.querySelectorAll('dt'), (dt) => dt.dataset.check), ['buildhost', 'Board\'s feed', 'Conveyor', 'Codex limit']);
  assert.equal(fine.querySelector('.check-next'), null, 'a row that is fine has no next step');
  // Nothing failing: no failing list, every row folded.
  const ok = boot();
  deliver(ok, full());
  assert.deepEqual(failingRows(ok), []);
  assert.equal(panel(ok, 'health').querySelector('details.checks-fine summary').textContent, '6 checks fine');
});

// Bugs (UX31): a failing push poured some 25 lines of raw output into its row, the panel grew to about 1,500 px and
// buried the warnings below it; a wait read "retry after 1022 s". The row is one plain line (how long it has failed and
// which check), the output whole under a closed "Show output"; a long error shows its first 100 characters on the row
// and the rest the same way; a wait reads "try again in 17 min".
test('Health: a failing push is one plain line with its output under "Show output"; a long error is cut to its line; a wait reads "try again in"', () => {
  const w = boot();
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
  const usage = dd(w, 'Account default on this machine').textContent;
  assert.ok(usage.includes('the usage server asked for a pause; try again in 17 min') && !/retry after|rate limited/.test(usage), usage);
  const host = dd(w, 'buildhost');
  const cut = host.querySelector(':scope > .detail').textContent;
  assert.equal(cut.length, 100, 'cut to 100 characters');
  assert.ok(cut.endsWith('…'));
  assert.equal(host.querySelector(':scope > details.output .output-text').textContent, data.panels.health.data.host.error.trim(), 'the whole reason under Show output');
});

// Issue 457: a test file over its CPU budget in two card test runs in a row comes off card test steps. Bug it catches:
// Health did not say so, and the owner could not see which file no card runs, or why. The row lists the file, both
// runs' CPU seconds against the budget, and the issue whose card brings it back.
test('Health: a test file kept off card test steps is listed with why and its issue', () => {
  const w = boot();
  const data = full();
  data.panels.health.data.records[0].slowOff = [{ file: 'conveyor/tests/s.test.sh', issue: 17, url: 'https://github.com/example/sample/issues/17',
    cpu: 10.24, budget: 8, card: 'c2-9', last: { cpu: 9, card: 'c2-8' } }];
  deliver(w, data);
  const row = dd(w, 'Kept off card tests');
  assert.match(row.textContent, /^1 file1 test file over the CPU budget in two card test runs in a row/);
  assert.equal(row.querySelector(':scope > details.output .slow-off-list').textContent,
    "conveyor/tests/s.test.sh2 runs over budget#1710.2 CPU s in c2-9's test run and 9 in c2-8's, over the 8 CPU s budget; runs only in the full test suite until its issue lands");
  assert.equal(row.querySelector(':scope > details.output a.issue').href, 'https://github.com/example/sample/issues/17');
});

// Bug: the live feed rewrites the stream every 10 s and the panel is drawn again on each write, so an opened "Show
// output" or "checks fine" closed under the owner while they read it. What was open stays open; what was not, stays shut.
// Bug (#557): the push's output was a new box at each draw, so a reader scrolled in it went back to its top.
test('Health: an opened "Show output" and "checks fine" stay open when the live feed draws the panel again', async () => {
  const w = boot({ feed: true });
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
  const w = boot({ feed: true });
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
  assert.match(dd(w, 'Data').textContent, /91 s old.*the live feed stopped.*Next: Reload the page/);
});

// Issue 407 (UX3). Bug: three words for the same wait ("the next snapshot", "the next reading", "within a minute");
// Health's next steps still said "The next snapshot reads it again". Each says "in about a minute".
test('Health: a row not read or not checked says it is tried again "in about a minute", never "the next snapshot"', () => {
  const w = boot();
  const data = full(), hd = data.panels.health.data;
  hd.host.reachable = null;
  hd.accounts = { list: [], error: 'ssh: no answer' };
  deliver(w, data);
  assert.match(dd(w, 'buildhost').textContent, /Next: The Board checks it again in about a minute\. Before that check, this project must name its build machine\./);
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
    const w = boot();
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
  const w = boot();
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
  const w = boot();
  deliver(w, data);
  assert.match(dd(w, 'Usage limit of sample: builder').textContent, /^Fine40% of the 7-day limit usedaccount builder, noreply-a@example\.com: build and fix$/);
  const rev = dd(w, 'Usage limit of sample: reviewer');
  assert.match(rev.textContent, /^Nearly used up95% of the 7-day limit usedaccount reviewer, noreply-c@example\.com: reviewsNext: Wait for the reset/);
  assert.match(dd(w, 'Usage limit of sample: third').textContent, /^Not readno reading yetaccount third, no email recorded: reviewsNext: Conveyor reads it again before its next pick\.$/);
  assert.equal(panel(w, 'health').querySelector('dt[data-check="Usage limit"]'), null, 'no row without its account');
});

// Issue 515. Bug: a project whose test command prints no `TESTRUN sec` lines recorded no test times on any card, and
// Health said nothing. The record's untimed (the last card test runs with no times) is a warning row that names the
// README section on how to add them; 0 shows no row.
test('Health: card test runs that recorded no test times are a warning that names the README section', () => {
  const at = (n) => {
    const data = full();
    data.panels.health.data.records[0].untimed = n;
    const w = boot();
    deliver(w, data);
    return w;
  };
  const none = at(3);
  assert.deepEqual(failingRows(none), ['Test times']);
  const row = dd(none, 'Test times');
  assert.equal(row.querySelector(':scope > .chip.chip-warn').textContent, 'Not recorded');
  assert.match(row.textContent, /the last 3 card test runs recorded no test times.*Next: .*"The CPU budget of a test file" in conveyor\/README\.md/);
  assert.equal(panel(at(0), 'health').querySelector('dt[data-check="Test times"]'), null, 'runs that recorded times show no row');
});

// Issue 629. Bug: Health told the owner to "Move this account's work to another on the Rules tab" for a 92% account
// no card runs on, and for one the cards use when the host file listed no other account to move to; a failed read
// showed "HTTP 401". Each fixture is one Claude account on the build machine.
const account = (over) => {
  const data = full();
  data.panels.health.data.accounts = { error: null, list: [{ machine: 'devbox', name: 'default', email: 'noreply@example.com', usedPct: 92, fiveHourPct: 40,
    resetsAt: iso(T0 + 2 * 3600000), readAt: iso(T0 - 60000), error: null, usedFor: ['cards of sample: build and fix'], cards: true, others: false, ...over }] };
  const w = boot();
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
test('Health: a read refused with HTTP 401 says the login has expired and where to sign in again', () => {
  const row = account({ usedPct: null, readAt: null, error: 'HTTP 401' });
  assert.match(row.textContent, /this login has expired: sign in again on devbox/);
  assert.doesNotMatch(row.textContent, /HTTP 401/);
});
