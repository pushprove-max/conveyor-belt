// SPDX-License-Identifier: Apache-2.0
// Health's lists, Health's one-line errors and a blocked Fast lane landing read as plain rows and lines, not one block
// of text. Bug it catches: the Flaky tests and Kept off card tests lists ran their cases together in one paragraph, a
// git error showed as git printed it, and a blocked landing's reason ran on beside its chip, so the owner had to read
// raw text to find what failed. A test step's log keeping its mono block is in dashboard-view.cards-blocked. Shared
// setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { boot, panel, deliver, full, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const P = 'https://github.com/example/sample/issues';
const dd = (w, label) => panel(w, 'health').querySelector(`dt[data-check="${label}"]`).nextElementSibling;
// A row's name, its count chip and its issue link (null when none).
const row = (li) => [li.querySelector('.finding-text').textContent, li.querySelector('.chip').textContent, li.querySelector('a.issue')?.getAttribute('href') ?? null];

test('Health: each flaky case and each kept-off file is one row with its name, count chip and issue link, with no mono block', () => {
  const data = full(), r = data.panels.health.data.records[0];
  r.flaky = [{ case: 'b.test: flaky', count: 3, issue: 16, url: `${P}/16` }, { case: 'c.test: other', count: 1, issue: null, url: null }];
  r.slowOff = [{ file: 'conveyor/tests/s.test.sh', issue: 17, url: `${P}/17`, cpu: 10.24, budget: 8, card: 'c2-9', last: { cpu: 9, card: 'c2-8' } }];
  const w = boot();
  deliver(w, data);
  const flaky = Array.from(dd(w, 'Flaky tests').querySelectorAll(':scope > details.output li.output-finding'));
  assert.deepEqual(flaky.map(row), [['b.test: flaky', '3 re-runs', `${P}/16`], ['c.test: other', '1 re-run', null]]);
  const off = Array.from(dd(w, 'Kept off card tests').querySelectorAll(':scope > details.output li.output-finding'));
  assert.deepEqual(off.map(row), [['conveyor/tests/s.test.sh', 'Kept off', `${P}/17`]]);
  assert.equal(off[0].querySelector('.detail').textContent,
    "10.2 CPU s in c2-9's test run and 9 in c2-8's; runs only in the full test suite until its issue lands", 'why it is kept off, under its name');
  for (const li of [...flaky, ...off]) assert.equal(li.querySelector('pre.output-text'), null, 'no mono block in a row');
});

test('Health: a one-line git error is a plain sentence, the raw line under a closed "Raw error"; a one-line raw error has no failures list', () => {
  const data = full(), hd = data.panels.health.data;
  const git = 'origin/main could not be fetched: fatal: Could not read from remote repository.';
  hd.update = { checkedAt: null, head: 'abc1234', error: git, moved: null };
  hd.accounts = { list: [], error: 'could not read the host file: Permission denied' };
  hd.stream = { live: false, heardAt: null, since: null, error: 'the snapshot of buildhost failed: jq: parse error', writtenAt: null };
  const w = boot();
  deliver(w, data);
  const code = dd(w, 'Dashboard code'), raw = code.querySelector(':scope > details.output');
  assert.equal(code.querySelector(':scope > .detail').textContent, 'The Board could not get main from GitHub.');
  assert.ok(raw && !raw.open, 'the raw error is folded, closed');
  assert.equal(raw.querySelector('summary').textContent, 'Raw error');
  assert.equal(raw.querySelector('pre.output-text').textContent, git, 'the raw line, as git gave it, in mono');
  const host = dd(w, 'Host accounts');
  assert.equal(host.querySelector(':scope > .detail').textContent, 'Could not read the host file.');
  assert.equal(host.querySelector(':scope > details.output .output-fails'), null, 'the only line is not said twice as a failure');
  const feed = dd(w, 'Data');
  assert.equal(feed.querySelector(':scope > .detail').textContent, 'The snapshot of buildhost failed.');
  assert.equal(feed.querySelector(':scope > details.output > summary').textContent, 'Raw error');
  assert.equal(feed.querySelector(':scope > details.output pre.output-text').textContent, 'the snapshot of buildhost failed: jq: parse error');
});

// Bug it catches: an error with no ": " (its sentence is the whole line) and an expired login (HTTP 401, said in the
// Board's own sentence) showed no "Raw error" and no Copy output, so the owner could not copy the host's error.
test('Health: a one-line error its sentence says whole, and an expired login, still keep the raw error with Copy output', () => {
  const data = full(), hd = data.panels.health.data;
  const merge = 'a merge is in progress in the checkout; it is left as it is', expired = 'HTTP 401 Unauthorized';
  hd.update = { checkedAt: null, head: 'abc1234', error: merge, moved: null };
  hd.accounts = { error: null, list: [{ machine: null, name: 'default', email: 'noreply@example.com', usedPct: null, fiveHourPct: null,
    resetsAt: null, readAt: null, error: expired, usedFor: ['build'] }] };
  const w = boot();
  deliver(w, data);
  for (const [label, sentence, raw] of [['Dashboard code', 'a merge is in progress in the checkout; it is left as it is', merge],
    ['Account default on this machine', 'this login has expired: sign in again on this machine', expired]]) {
    const row = dd(w, label), out = row.querySelector(':scope > details.output');
    assert.ok(Array.from(row.querySelectorAll(':scope > .detail'), (s) => s.textContent).includes(sentence), label);
    assert.equal(out && out.querySelector('summary').textContent, 'Raw error', `${label}: the raw error is folded under it`);
    assert.equal(out.querySelector('pre.output-text').textContent, raw, `${label}: as the host gave it`);
    assert.ok(out.querySelector('button.output-copy'), `${label}: Copy output`);
  }
});

test('Lanes: a blocked Fast lane landing shows its reason as one plain line, then its log under "Show output" in mono', () => {
  const data = full();
  const reason = 'the changed tests failed again after their one fix round (exit 1); nothing landed.\nsecond line of the reason';
  data.panels.lanes.data.records[0].fast.landing = { state: 'blocked', card: 'c9-123', reason, tail: 'not ok 1 - pays once\nnot ok 2 - refunds' };
  const w = boot();
  deliver(w, data);
  const li = panel(w, 'lanes').querySelector('li[data-lane="Fast lane"]');
  const why = li.querySelector('.landing-reason'), out = li.querySelector(':scope > details.output');
  assert.equal(why.textContent, 'the changed tests failed again after their one fix round (exit 1); nothing landed.');
  assert.equal(why.title, reason, 'the whole reason on hover');
  assert.ok(why.compareDocumentPosition(out) & 4, 'the reason line comes before the log');
  assert.equal(out.querySelector('summary').textContent, 'Show output');
  assert.equal(out.querySelector('pre.output-text').textContent, 'not ok 1 - pays once\nnot ok 2 - refunds');
  assert.equal(why.previousElementSibling.textContent, 'Landing: blocked', 'the chip line above it carries no reason');
});
