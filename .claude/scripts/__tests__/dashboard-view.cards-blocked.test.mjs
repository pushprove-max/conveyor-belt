// SPDX-License-Identifier: Apache-2.0
// The dashboard page's cards: a blocked card, its failed step, sentence and output, a NO-GO review's findings and the
// failing tests; and what draws the eye: the steps at phone width, numbers that count, a new Needs you item marked once.
// Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { css, T0, SEEN, iso, clone, boot, panel, deliver, next, settle, P, STEPS, trackOf, counts, full, cases } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);

// Bug: a build, fix or landing that failed took the card off the belt, and the blocked card's row showed
// neither the step that failed nor how long it ran.
test('a blocked card shows the step it failed at with its seconds, its track and its reviews', () => {
  const w = boot();
  const data = full();
  const failed = trackOf('++!...', '');
  failed.steps[2].sec = 754; failed.steps[2].n = 1;
  Object.assign(data.panels.needs.data.cards.blocked[0], { reason: 'fix: session failed (exit 124)', track: { ...failed, at: null }, reviews: [{ round: 1, verdict: 'NO-GO', counts: counts(0, 1, 2, 0), sec: 200, fixed: true }] });
  Object.assign(data.panels.needs.data.cards.waiting[0], { track: { ...trackOf('++....', ''), at: null }, reviews: [{ round: 1, verdict: 'GO', counts: counts(0, 0, 0, 0), sec: 60, fixed: false }] });
  deliver(w, data);
  const row = (key) => panel(w, 'needs').querySelector(`li[data-key="${key}"]`);
  const blocked = row('blocked:c2-13');
  assert.equal(blocked.querySelector('.stopped').textContent, 'Failed at Fix (step 3 of 6) after 12 min');
  const steps = Array.from(blocked.querySelectorAll('ol.track6 > li.step6'));
  assert.deepEqual(steps.map((s) => s.querySelector('.step-name').textContent), STEPS, 'the same six steps as on the belt');
  assert.equal(steps.map((s) => ({ done: '+', now: '>', skipped: '-', failed: '!', todo: '.' }[s.dataset.state])).join(''), '++!...');
  assert.equal(steps[2].getAttribute('aria-label'), 'Fix: failed', 'a state is never colour alone');
  assert.equal(steps[2].querySelector('.step-time').textContent, '12 min');
  assert.equal(steps[4].getAttribute('aria-label'), 'Land: to come');
  assert.ok(blocked.querySelector('details.track-detail'), 'every recorded step, on demand');
  assert.match(blocked.querySelector('.reviews').textContent, /R1\s*NO-GO\s*1 P1, 2 P2/);
  // A card that waits for a yes failed no step: its track and its review, and no "Failed at" line.
  const waiting = row('waiting:c1-12');
  assert.equal(waiting.querySelector('.stopped'), null);
  assert.equal(waiting.querySelectorAll('ol.track6 > li.step6').length, 6);
  assert.match(waiting.querySelector('.reviews').textContent, /R1\s*GO/);
  // A record that gives a blocked card no track (an older loop) shows its reason alone.
  const old = boot();
  deliver(old, full());
  assert.equal(panel(old, 'needs').querySelector('.track6, .stopped, .reviews'), null);
});

// Bug: a blocked card showed its whole reason as one paragraph: the test output's line breaks lost, the worktree's
// long path on every line, five identical lines run together with the passing ones. The owner reads the sentence
// first, and the output only when they ask for it.
test('a blocked card shows its sentence, and its output folded, shortened and closed until asked for', async () => {
  const w = boot();
  const copied = [];
  Object.defineProperty(w.navigator, 'clipboard', { value: { writeText: (t) => { copied.push(t); return Promise.resolve(); } } });
  const data = full();
  const stat = "cp: cannot stat '~/cards/c2-13/conveyor/../.conveyor/hooks.json': No such file or directory";
  const tail = ['ok 1 - packs', ...Array(5).fill(stat), 'ok 2 - hooks', 'FAIL conveyor/lib/pack.test.sh', 'not ok 3 - error: pack did not load', 'ok 4 - ~/cards/c2-13.test is kept', ''].join('\n');
  const sentence = 'the changed tests failed again after their one fix round (exit 1); nothing landed.';
  Object.assign(data.panels.needs.data.cards.blocked[0], { reason: sentence, tail });
  Object.assign(data.panels.board.data.blocked[0], { reason: sentence, tail });
  deliver(w, data);
  const row = panel(w, 'needs').querySelector('li[data-key="blocked:c2-13"]');
  assert.equal(row.querySelector('.reason').textContent, sentence, 'the sentence alone is the headline');
  const out = row.querySelector('details.output');
  assert.ok(out, 'the output is there, under a toggle');
  assert.equal(out.open, false, 'closed until the owner opens it');
  assert.equal(out.querySelector('summary').textContent, 'Show output');
  const shown = ['ok 1 - packs', "cp: cannot stat './conveyor/../.conveyor/hooks.json': No such file or directory ×5", 'ok 2 - hooks',
    'FAIL conveyor/lib/pack.test.sh', 'not ok 3 - error: pack did not load', 'ok 4 - ~/cards/c2-13.test is kept'];
  // The file-copy error the issue was raised for is a failure too, folded to one.
  assert.equal(out.querySelector('.output-count').textContent, '3 failures');
  assert.deepEqual(Array.from(out.querySelectorAll('.output-fails li'), (x) => x.textContent), [shown[1], shown[3], shown[4]]);
  const pre = out.querySelector('pre.output-text');
  assert.equal(pre.textContent, shown.join('\n'), 'its line breaks kept, the worktree as ./, five identical lines one line ×5');
  assert.deepEqual(Array.from(pre.querySelectorAll('.output-line.is-fail'), (x) => x.textContent),
    ["cp: cannot stat './conveyor/../.conveyor/hooks.json': No such file or directory ×5", shown[3], shown[4]], 'the failures stand out');
  assert.equal(out.querySelector('a'), null, 'nothing in it is a link');
  out.querySelector('button.output-copy').click();
  await settle();
  assert.deepEqual(copied, [shown.join('\n')], 'Copy takes the output as shown, as plain text');
  assert.equal(out.querySelector('.output-note').textContent, 'Copied.');
  // The Board's Needs you column leads with the same sentence; its output is in Needs you, which the card links to.
  const c = boot({ tab: 'control' });
  deliver(c, data);
  const bc = panel(c, 'board').querySelector('.bcard[data-issue="13"]');
  assert.equal(bc.querySelector('.why-said').textContent, sentence);
  assert.equal(bc.querySelector('details.output'), null, 'the output is one click away in Needs you, not repeated');
  assert.equal(bc.querySelector('a[data-act="needs-open"]').getAttribute('href'), 'index.html?tab=overview#panel-needs');
  // A reason with no output shows its sentence alone.
  const plain = boot();
  deliver(plain, full());
  const p = panel(plain, 'needs').querySelector('li[data-key="blocked:c2-13"]');
  assert.equal(p.querySelector('.reason').textContent, 'tests failed twice');
  assert.equal(p.querySelector('.output'), null);
  const pc = boot({ tab: 'control' });
  deliver(pc, full());
  assert.equal(panel(pc, 'board').querySelector('.bcard[data-issue="13"] .output'), null);
});

// Bugs: the card's steps showed only names, so a NO-GO review's findings and the blocked step's output were not
// there to open; a worktree under a folder with a space was cut at the space ("/tmp/my ./hooks.json").
test("a card's steps show a NO-GO review's findings and the blocked step's sentence and output; a quoted path with a space is shortened whole", () => {
  const w = boot();
  const data = full();
  const records = [
    { name: 'review 1 (NO-GO)', state: 'done', sec: 60, output: '[P1] a.sh:1 wrong\n[P2] b.sh:2 slow' },
    { name: 'stopped', state: 'failed', sec: 5, why: 'the changed tests failed; nothing landed.',
      output: "cp: cannot stat '/tmp/my cards/c2-13/hooks.json'\ncp: cannot stat '/tmp/my cards/c2-13/hooks.json'\nFAIL x.test\nERROR:/tmp/cards/c2-13/hooks.json\nPATH=/usr/bin:/tmp/cards/c2-13/bin ran" },
  ];
  Object.assign(data.panels.needs.data.cards.blocked[0], { track: { ...trackOf('++!...', ''), at: null, records } });
  deliver(w, data);
  const items = panel(w, 'needs').querySelectorAll('li[data-key="blocked:c2-13"] details.track-detail .timeline > li');
  assert.equal(items.length, 2);
  const [review, stopped] = items;
  assert.equal(review.querySelector('details.output').open, false, 'the review text is closed until asked for');
  // A review's findings are rows (dashboard-view.output-review), on a card's steps too.
  assert.deepEqual(Array.from(review.querySelectorAll('.output-finding'), (x) => [x.querySelector('.chip').textContent, x.querySelector('.finding-text').textContent,
    x.querySelector('.finding-at').textContent]), [['P1', 'wrong', 'a.sh:1'], ['P2', 'slow', 'b.sh:2']]);
  assert.ok(review.querySelector('button.output-copy'));
  assert.equal(stopped.querySelector('.detail-why').textContent, 'the changed tests failed; nothing landed.');
  assert.equal(stopped.querySelector('pre.output-text').textContent, "cp: cannot stat './hooks.json' ×2\nFAIL x.test\nERROR:./hooks.json\nPATH=/usr/bin:./bin ran",
    'the whole quoted worktree path is ./; what stands before an unquoted one stays');
  assert.equal(stopped.querySelector('.output-count').textContent, '3 failures');
});

// Bug: a failed Tests step showed one wall of text: the end of the test log cut mid-word, a note on exit 124 beside an
// exit 1, cleanup warnings and dozens of `ok` case names run together, with the failing test named nowhere. The step
// names the failing files and cases; the log is under a closed toggle, a line a line.
test('a failed Tests step names the failing files and cases, and keeps its output under a closed "Show full output"', () => {
  const w = boot();
  const data = full();
  const log = '== tests/a.test.sh\nok alpha\n== conveyor/conveyor.test.sh\nok lane\nFAIL [views]: the snapshot lacks its steps\nconveyor: left 2 stubs running\n'
    + '== tests/b.test.sh\nFAIL [beta]: expected 2, got 3\nok gamma';
  const records = [
    { name: 'tests failed', state: 'failed', sec: 60, why: 'exit 1', output: log, failures: { of: 41, timeout: null, files: [
      { file: 'conveyor/conveyor.test.sh', cases: [{ name: 'views', line: 'FAIL [views]: the snapshot lacks its steps' }, { name: 'track', line: 'FAIL [track]: no bar' }] },
      { file: 'tests/b.test.sh', cases: [{ name: 'beta', line: 'FAIL [beta]: expected 2, got 3' }] }] } },
    { name: 'fix 1', state: 'done', sec: 60 },
    { name: 'tests failed', state: 'failed', sec: 3600, why: 'exit 124: timed out after 3600s in conveyor/conveyor.test.sh', output: '== conveyor/conveyor.test.sh\nok lane',
      failures: { of: 1, files: [], timeout: { sec: 3600, file: 'conveyor/conveyor.test.sh' } } },
    { name: 'stopped', state: 'failed', sec: 5, why: 'the changed tests failed again; nothing landed.', output: 'ok lane' },
  ];
  Object.assign(data.panels.needs.data.cards.blocked[0], { track: { ...trackOf('++!...', ''), at: null, records } });
  deliver(w, data);
  const [failed, , timed, stopped] = panel(w, 'needs').querySelectorAll('li[data-key="blocked:c2-13"] details.track-detail .timeline > li');
  assert.equal(failed.querySelector('.test-sum').textContent, '2 of 41 test files failed');
  const rows = Array.from(failed.querySelectorAll('.test-files > li'));
  assert.deepEqual(rows.map((r) => r.querySelector('.test-file-name').textContent), ['conveyor/conveyor.test.sh', 'tests/b.test.sh'], 'one row a failing file, no passing one');
  assert.deepEqual(rows.map((r) => Array.from(r.querySelectorAll('.test-cases > li'), (c) => [c.querySelector('.test-case-name').textContent, c.querySelector('.test-case-line').textContent])),
    [[['views', 'the snapshot lacks its steps'], ['track', 'no bar']], [['beta', 'expected 2, got 3']]], 'each failing case on a line of its own, with its first failure line');
  // Outside the toggle: no ok name, no cleanup warning, and no note on an exit that did not happen.
  const toggle = failed.querySelector('details.output');
  const outside = Array.from(failed.children).filter((el) => el !== toggle).map((el) => el.textContent).join('\n');
  for (const s of ['ok ', 'alpha', 'gamma', 'left 2 stubs', '124', 'exit 1']) assert.ok(!outside.includes(s), `"${s}" shows outside the toggle: ${outside}`);
  assert.equal(failed.querySelector('.detail-why'), null, 'the rows stand in place of the raw reason');
  assert.equal(failed.querySelector('.tl-tip').textContent, 'Tests: failed, 1 min: 2 of 41 test files failed');
  assert.equal(toggle.open, false, 'the full output is closed until asked for');
  assert.equal(toggle.querySelector('summary').textContent, 'Show full output');
  assert.equal(toggle.querySelector('pre.output-text').textContent, log, 'the full output keeps its lines as lines');
  // A run that timed out says so, with the file that was still running.
  assert.equal(timed.querySelector('.test-sum').textContent, 'Timed out after 60 min in conveyor/conveyor.test.sh');
  assert.equal(timed.querySelector('.test-files'), null);
  // Another step's output keeps its own words.
  assert.equal(stopped.querySelector('details.output summary').textContent, 'Show output');
  assert.match(css, /\.tl-item > \.test-fails,/);
});

// Bug this guards (#1616): a card's test step that stopped at its first failure named its failed case, but not the
// test files it did not run (the record's failures.notRun), so a reader took them as passed.
test('a failed Tests step that stopped at its first failure names the test files it did not run', () => {
  const w = boot();
  const data = full();
  const records = [{ name: 'tests failed', state: 'failed', sec: 5, why: 'exit 1', output: '== a.test.sh\nFAIL [first]: broken',
    failures: { of: 2, timeout: null, files: [{ file: 'a.test.sh', cases: [{ name: 'first', line: 'FAIL [first]: broken' }] }], notRun: ['b.test.sh'] } }];
  Object.assign(data.panels.needs.data.cards.blocked[0], { track: { ...trackOf('++!...', ''), at: null, records } });
  deliver(w, data);
  const [failed] = panel(w, 'needs').querySelectorAll('li[data-key="blocked:c2-13"] details.track-detail .timeline > li');
  assert.deepEqual(Array.from(failed.querySelectorAll('.test-case-name'), (c) => c.textContent), ['first'], 'the failed case is named, as before');
  const said = failed.querySelector('.test-notrun');
  assert.ok(said, `the step does not name the files not run: ${failed.textContent}`);
  assert.equal(said.textContent, 'Not run, as the run stopped at its first failure: b.test.sh');
});

// Bug (R1): the project's checks failing before any test file ran is recorded as {of: 0, files: [{file: <the command>,
// cases: []}]}; the step history called that command "1 test file failed" in place of the recorded reason.
test('a Tests step the project\'s checks failed shows its recorded reason, not a failed test file', () => {
  const w = boot();
  const data = full();
  const records = [{ name: 'tests failed', state: 'failed', sec: 3, why: 'the project\'s checks failed; no test file ran', failures: { of: 0, timeout: null, files: [{ file: 'bash .conveyor/test-changed.sh', cases: [] }] } }];
  Object.assign(data.panels.needs.data.cards.blocked[0], { track: { ...trackOf('++!...', ''), at: null, records } });
  deliver(w, data);
  const [step] = panel(w, 'needs').querySelectorAll('li[data-key="blocked:c2-13"] details.track-detail .timeline > li');
  assert.equal(step.querySelector('.test-sum'), null, 'no "test file failed" line');
  assert.equal(step.querySelector('.detail-why').textContent, 'the project\'s checks failed; no test file ran');
});

// Bug: a URL naming the card was taken for its worktree, so two different URLs both became "https:./log" and were
// folded into one line ×2, losing which host each named; a protocol-relative //host URL likewise became "?path=./log",
// and a quoted one became "'./log'".
test("a URL that names the card is not shortened as its worktree, so different URLs stay apart", () => {
  const w = boot();
  const data = full();
  const records = [{ name: 'stopped', state: 'failed', sec: 5, why: 'the changed tests failed; nothing landed.',
    output: 'https://example.com/cards/c2-13/log\nhttps://other.example.com/cards/c2-13/log\n'
      + 'https://example.com/?path=/one/c2-13/log\nhttps://example.com/?path=/two/c2-13/log\n'
      + "https://example.com/?path='/one/c2-13/log'\nhttps://example.com/?path='/two/c2-13/log'\n"
      + '//example.com/?path=/one/c2-13/log\n//example.com/?path=/two/c2-13/log\n'
      + "'//example.com/?path=/one/c2-13/log'\n'//example.com/?path=/two/c2-13/log'\nsee /tmp/cards/c2-13/log" }];
  Object.assign(data.panels.needs.data.cards.blocked[0], { track: { ...trackOf('++!...', ''), at: null, records } });
  deliver(w, data);
  const stopped = panel(w, 'needs').querySelector('li[data-key="blocked:c2-13"] details.track-detail .timeline > li');
  assert.equal(stopped.querySelector('pre.output-text').textContent,
    'https://example.com/cards/c2-13/log\nhttps://other.example.com/cards/c2-13/log\n'
      + 'https://example.com/?path=/one/c2-13/log\nhttps://example.com/?path=/two/c2-13/log\n'
      + "https://example.com/?path='/one/c2-13/log'\nhttps://example.com/?path='/two/c2-13/log'\n"
      + '//example.com/?path=/one/c2-13/log\n//example.com/?path=/two/c2-13/log\n'
      + "'//example.com/?path=/one/c2-13/log'\n'//example.com/?path=/two/c2-13/log'\nsee ./log",
    'each URL kept whole and on its own line; a worktree path is still ./');
});

test('at phone width, and in a panel set small, the six steps keep their marks and names; the times are in their labels', () => {
  const phone = css.slice(css.indexOf('@media (max-width: 700px)'));
  assert.match(phone, /\.step-time \{ display: none; \}/);
  assert.match(css, /\.panel\[data-size="small"\] \.step-time \{ display: none; \}/);
  assert.doesNotMatch(css, /\.track-short|\.progress \{/, 'no 17-step line and no bar against a usual time');
});

test('a number counts from the value shown to the new one', () => {
  const w = boot();
  deliver(w, full());
  const figure = () => panel(w, 'cost').querySelector('[data-figure="today"] .num');
  assert.equal(figure().textContent, '$4.25', 'the first value is shown at once');
  assert.equal(w.frames.length, 0);
  const data = full();
  data.panels.cost.data.cards.todayUsd = 6.25;
  next(w, data);
  assert.equal(figure().textContent, '$4.25', 'the count starts from the value shown');
  // The head line's Today tile counts the same figure in frames of its own.
  w.clock += 130;
  for (const f of w.frames.splice(0)) f();
  const mid = Number(figure().textContent.slice(1));
  assert.ok(mid > 4.25 && mid < 6.25, `half way it is in between: ${mid}`);
  w.clock += 200;
  for (const f of w.frames.splice(0)) f();
  assert.equal(figure().textContent, '$6.25', 'it ends on the new value, inside 300 ms');
  assert.equal(w.frames.length, 0, 'and stops');
  data.panels.cost.data.cards.todayUsd = null;
  next(w, clone(data));
  assert.equal(figure().textContent, 'not priced', 'an unknown total is said, never counted to');
});

test('a new "Needs you" item is marked once, in this browser', () => {
  const w = boot();
  deliver(w, full());
  assert.equal(panel(w, 'needs').querySelectorAll('.is-new').length, 0, 'what is there on a first visit is not new');
  const data = full();
  data.panels.needs.data.cards.blocked.push({ repo: 'sample', card: 'c8-14', issue: 14, title: 'Second break', reason: 'landing conflict twice', since: iso(T0), url: `${P}/14` });
  next(w, data);
  const fresh = Array.from(panel(w, 'needs').querySelectorAll('.is-new'));
  assert.deepEqual(fresh.map((li) => li.dataset.key), ['blocked:c8-14'], 'only the item that just arrived is marked');
  const later = clone(data);
  later.panels.needs.data.decisions.push({ repo: 'bookshop', id: 'q-two', askedAt: '2026-11-09T12:00:00Z', question: 'Another?', options: null, proposedDefault: null, source: 'main' });
  next(w, later);
  assert.deepEqual(Array.from(panel(w, 'needs').querySelectorAll('.is-new')).map((li) => li.dataset.key), ['decision:bookshop:q-two@2026-11-09T12:00:00Z'], 'the earlier item is marked once, not again');
  const again = boot({ store: { [SEEN]: w.localStorage.getItem(SEEN) } });
  deliver(again, later);
  assert.equal(panel(again, 'needs').querySelectorAll('.is-new').length, 0, 'a reload does not mark what this browser has shown');
});

// Bug: a card that the Test step blocked after its fix rounds ("the changed tests failed again after their 3 fix
// rounds") led on the Board and in Needs you with the failed cases or the timeout only ("The tests timed out in
// a.test.sh"): the owner could not see that the card had used its fix rounds, though the issue comment says it.
test('a card the Test step blocked after its fix rounds says the round count beside its failed cases or its timeout', () => {
  const w = boot();
  const data = full();
  const ran = (failures) => ({ ...trackOf('+++!..', ''), at: null, records: [{ name: 'tests failed', state: 'failed', sec: 60, failures }] });
  const blocked = data.panels.needs.data.cards.blocked;
  Object.assign(blocked[0], { reason: 'the changed tests failed again after their 3 fix rounds (exit 124); nothing landed.',
    track: ran({ of: 1, files: [], timeout: { sec: 600, file: 'a.test.sh' } }) });
  blocked.push({ ...clone(blocked[0]), card: 'c8-14', issue: 14, reason: 'the changed tests failed again after their 1 fix round (exit 1); nothing landed.',
    track: ran({ of: 4, timeout: null, files: [{ file: 'b.test.sh', cases: [{ name: 'beta', line: 'FAIL [beta]' }] }] }) });
  deliver(w, data);
  const said = (card) => panel(w, 'needs').querySelector(`li[data-key="blocked:${card}"] .why-said`).textContent;
  assert.equal(said('c2-13'), 'The tests timed out in a.test.sh after 3 fix rounds', `a timeout, for the reason: ${blocked[0].reason}`);
  assert.equal(said('c8-14'), '1 test failed after 1 fix round: beta', `a failed case, for the reason: ${blocked[1].reason}`);
});
