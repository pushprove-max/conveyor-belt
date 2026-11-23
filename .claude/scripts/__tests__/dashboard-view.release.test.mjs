// SPDX-License-Identifier: Apache-2.0
// The Release panel on Overview (#27, Small by default since #97): one card for each project that releases with Conveyor, its status chip,
// three steps, the version and two buttons, a run button whose label follows the state and Release, disabled with
// what it waits for (each on a second click), and the changes
// since the tag, closed until opened. Shared setup: dashboard-view.helpers.mjs.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { boot, deliver, next, full, panel, act, settle, cases, css } from './dashboard-view.helpers.mjs';

const test = cases(import.meta.url);
const HEAD = 'b'.repeat(40), NEW = 'c'.repeat(40);
const URL = 'https://github.com/example/plugin';
// 26 changes since the tag, newest first, each a finding's subject as Conveyor commits it.
const COMMITS = Array.from({ length: 26 }, (_, i) => ({ sha: (100 + i).toString(16).padStart(40, '0'),
  subject: `fix(plugin): [P1] conveyor/foreman/watch-conveyor.sh:${56 + i} Suite status counts cases ${26 - i}. Proof: .conveyor/project.json:33 runs it (#${126 - i})` }));
// The plugin: docs/releases/1.0.0.md on main and no tag yet. The shop: tags, but no docs/releases/ (it ships by its
// own deploy).
function data(run, plugin = {}, rule = null) {
  const d = full();
  d.panels.release.data.records = [
    { repo: 'plugin', url: URL, suiteMachine: rule, suites: run ? [run] : [], release: { tag: null, count: 26, next: '1.0.0', notes: true, written: ['1.0.0'], head: HEAD, releases: true, commits: COMMITS, ...plugin } },
    { repo: 'shop', url: 'https://github.com/example/shop', suites: [], release: { tag: 'v1.33.0', count: 673, next: '1.34.0', notes: false, head: NEW, releases: false, commits: [] } },
  ];
  return d;
}
const RUN = { kind: 'release', version: '1.0.0', step: 'release-prep', sha: HEAD, since: '2026-11-14T08:00:00Z', moved: false, reasons: [] };
const rel = (w) => panel(w, 'release');
const card = (w) => rel(w).querySelector('[data-project="plugin"]');
const chip = (w) => card(w).querySelector('[data-figure="status"]').textContent;
const stepOf = (w, name) => card(w).querySelector(`[data-step="${name}"]`);
// Shown: neither the element nor a parent of it is hidden or drawn with display: none.
const shown = (w, el) => { for (let e = el; e; e = e.parentElement) if (e.hidden || w.getComputedStyle(e).display === 'none') return false; return true; };
const sent = async (w, fn) => { fn(); await settle(); await settle(); return w.posts.splice(0).map((p) => p.body); };

// Bugs this guards: the panel shows a project that does not release with Conveyor; the
// version is the next minor of no tag (0.1.0) though main holds the 1.0.0 notes; nothing says what to do next.
test('D1: one card, for the project that releases with Conveyor: No release yet, notes done, Suite not run, 1.0.0, Run suite on a second press', async () => {
  const w = boot();
  deliver(w, data(null));
  assert.deepEqual(Array.from(rel(w).querySelectorAll('[data-project]'), (x) => x.dataset.project), ['plugin'], 'the shop, with no docs/releases/, is left out');
  assert.equal(card(w).querySelector('[data-figure="tag"]').textContent, 'No release yet');
  assert.equal(card(w).querySelector('[data-figure="count"]').textContent, '26 changes since');
  assert.equal(stepOf(w, 'release-notes').dataset.state, 'done');
  assert.match(stepOf(w, 'release-notes').textContent, /docs\/releases\/1\.0\.0\.md on main: written/);
  assert.equal(stepOf(w, 'full-suite').dataset.state, 'todo');
  assert.equal(chip(w), 'Suite not run');
  assert.equal(card(w).querySelector('[data-field="version"]').value, '1.0.0');
  assert.equal(act(card(w), 'release-prep').textContent, 'Run suite');
  assert.equal(act(card(w), 'release-stop'), null, 'Stop is hidden when no run is under way or waiting');
  // Bug (#413): with no suite run the panel showed Run suite alone, and Release was hidden, so the owner could not see
  // how to release or what it waits for.
  assert.deepEqual(Array.from(card(w).querySelectorAll('.release-go button'), (b) => b.dataset.act), ['release-prep', 'release']);
  assert.ok(shown(w, act(card(w), 'release-prep')) && shown(w, act(card(w), 'release')), 'both buttons show');
  const release = act(card(w), 'release');
  assert.equal(release.disabled, true);
  assert.equal(release.textContent, 'Release 1.0.0: needs the whole suite to succeed on main\'s head (bbbbbbbbbbbb)');
  assert.deepEqual(await sent(w, () => { release.click(); release.click(); }), [], 'a disabled Release sends nothing');
  assert.equal(card(w).querySelector('[data-figure="version-notes"]'), null, 'no line under the box for a version with notes');
  assert.deepEqual(await sent(w, () => act(card(w), 'release-prep').click()), [], 'one press sends nothing');
  // Bug: Run suite also made the tag and the GitHub release once the suite passed: it sends prep, release-prep alone.
  assert.deepEqual(await sent(w, () => act(card(w), 'release-prep').click()), [], 'the second press asks the suite\'s mode first');
  assert.deepEqual(await sent(w, () => act(card(w), 'mode-serial').click()), [{ action: 'release-run', args: ['prep', '1.0.0', '--serial'], repo: 'plugin' }]);
  // Bug: a version typed in place of 1.0.0 kept 1.0.0's notes step and button, then sent the typed one, whose missing
  // notes made release-prep draft them in place of the suite the button named.
  const field = card(w).querySelector('[data-field="version"]');
  // Bug (#33): the redraw put the focus back without preventScroll, so a reader scrolled away was pulled back to the
  // field. jsdom lays nothing out, so the focus call's options are recorded.
  const focused = [], focus = w.HTMLElement.prototype.focus;
  w.HTMLElement.prototype.focus = function (opt) { focused.push(Boolean(opt && opt.preventScroll)); return focus.call(this, opt); };
  field.value = '1.1.0'; field.dispatchEvent(new w.Event('input'));
  w.HTMLElement.prototype.focus = focus;
  assert.deepEqual(focused, [true], 'the redraw focuses the field without scrolling the page');
  assert.equal(stepOf(w, 'release-notes').dataset.state, 'todo');
  assert.match(stepOf(w, 'release-notes').textContent, /docs\/releases\/1\.1\.0\.md on main: missing/);
  assert.equal(chip(w), 'Notes missing');
  assert.equal(act(card(w), 'release-prep').textContent, 'Draft notes');
  assert.equal(w.document.activeElement, card(w).querySelector('[data-field="version"]'), 'the field keeps the focus as the card is drawn again');
  act(card(w), 'release-prep').click();
  // Draft notes runs no suite, so it asks no mode (#791).
  assert.deepEqual(await sent(w, () => act(card(w), 'release-prep').click()), [{ action: 'release-run', args: ['prep', '1.1.0'], repo: 'plugin' }]);
  assert.equal(card(w).querySelector('[data-figure="mode-ask"]'), null);
  // With no project that releases with Conveyor, one line says so.
  const none = boot(), d = data(null);
  d.panels.release.data.records.splice(0, 1);
  deliver(none, d);
  assert.equal(rel(none).querySelector('.state-title').textContent, 'No project releases with Conveyor.');
});

// Bug this guards (#413): a version typed with no notes on main gave no word under the box or on Release of the notes
// it lacks.
test('#413: a version typed with no notes: Release names the missing notes file, and a line under the box says so', () => {
  const w = boot();
  deliver(w, data({ ...RUN, ended: '2026-11-14T08:15:00Z', state: 'passed', failed: 0, cases: [] }));
  const field = card(w).querySelector('[data-field="version"]');
  field.value = '1.2.0'; field.dispatchEvent(new w.Event('input'));
  assert.equal(act(card(w), 'release').disabled, true);
  assert.equal(act(card(w), 'release').textContent, 'Release 1.2.0: needs release notes docs/releases/1.2.0.md');
  assert.equal(card(w).querySelector('[data-figure="version-notes"]').textContent, '1.2.0 has no release notes: docs/releases/1.2.0.md is not on main.');
});
// Bug this guards (#1365): release-prep with no notes on main started a card that adds its draft, and its record waits
// on it (state waiting, notes.card), but the panel drew that run as a refused notes step, or as no run at all, so the
// owner could not see that the release goes on by itself once the card lands.
test('#1365: a run waiting on its notes card shows the notes step under way with the card, not a refusal', () => {
  const w = boot();
  const why = 'notes card c20261114T081500-plugin-0 started: the notes draft is $HOME/state/release/1.0.0.md';
  deliver(w, data({ ...RUN, sha: null, ended: '2026-11-14T08:15:00Z', state: 'waiting', reasons: [why],
    notes: { card: 'c20261114T081500-plugin-0', then: 'release', mode: null, machine: null } }, { notes: false, written: [] }));
  const s1 = stepOf(w, 'release-notes');
  assert.equal(s1.dataset.state, 'now', 'the notes step is under way, not failed');
  assert.equal(s1.querySelector('.release-line').textContent, 'docs/releases/1.0.0.md on main: card c20261114T081500-plugin-0 adds the notes draft');
  assert.equal(s1.querySelector('[data-figure="notes-card"]').textContent, 'The suite runs by itself once the card\'s commit is on the branch the suite tests and no other card is open, then the release.');
  assert.equal(s1.querySelector('[data-list="reasons"]'), null, 'the start line is not listed as a reason the run stopped');
  assert.equal(chip(w), 'Notes card under way');
});
// Bug this guards (#1371): every reason of the last run was listed under the version typed in the field, so while 1.0.0
// waited on its notes card, typing 1.1.0 showed "notes card ... started" under the notes step of 1.1.0.
test('#1371: a version typed that the last run was not of shows none of that run\'s reasons', () => {
  const w = boot();
  deliver(w, data({ ...RUN, sha: null, ended: '2026-11-14T08:15:00Z', state: 'waiting', reasons: ['notes card c20261114T081500-plugin-0 started'],
    notes: { card: 'c20261114T081500-plugin-0', then: 'release', mode: null, machine: null } }, { notes: false, written: [] }));
  const field = card(w).querySelector('[data-field="version"]');
  field.value = '1.1.0'; field.dispatchEvent(new w.Event('input'));
  assert.equal(card(w).querySelector('[data-list="reasons"]'), null, 'typed 1.1.0 after a run of 1.0.0: no reasons of that run are listed');
});
// Bug this guards (#1369): a run waiting on its notes card had no Stop, so the owner could not end the wait and the
// card, once landed, started the suite and the release.
test('#1369: a run waiting on its notes card shows Stop in the notes step, and a second click sends the stop', async () => {
  const w = boot();
  const id = 'c20261114T081500-plugin-0';
  deliver(w, data({ ...RUN, sha: null, ended: '2026-11-14T08:15:00Z', state: 'waiting', reasons: [`notes card ${id} started`],
    notes: { card: id, then: 'prep', mode: null, machine: null } }, { notes: false, written: [] }));
  assert.ok(stepOf(w, 'release-notes').querySelector('[data-act="release-stop"]'), 'Stop shows in the notes step');
  assert.deepEqual(await sent(w, () => act(card(w), 'release-stop').click()), []);
  // Follow-up of #1461: the stop names the waiting run's start, so one that arrives after relfixes() started the suite
  // ends nothing. Bug: a bare stop killed that suite.
  assert.deepEqual(await sent(w, () => act(card(w), 'release-stop').click()), [{ action: 'release-run', args: ['stop', RUN.since], repo: 'plugin' }]);
});
// Bug this guards (#1369): the notes reached main while another card was open, the run still waited for that card, and
// the panel (which read the wait from the missing notes) hid Stop, so the owner could not end it.
const WAITING = { ...RUN, sha: null, ended: '2026-11-14T08:15:00Z', state: 'waiting', notes: { card: 'c20261114T081500-plugin-0', then: 'prep', mode: null, machine: null } };
const stopShows = (w) => !!stepOf(w, 'release-notes').querySelector('[data-act="release-stop"]');
for (const [name, patch, shows] of [
  ['shows Stop while the notes are on main and the run still waits for open cards', {}, true],
  ['shows no Stop once the run is stopped', { state: 'stopped', reasons: ['stopped by the owner'] }, false],
  ['shows no Stop once the run is started again', { restarted: '2026-11-14T08:16:00Z' }, false],
]) {
  test(`#1369: ${name}`, () => {
    const w = boot();
    deliver(w, data({ ...WAITING, ...patch }, { notes: true, written: ['1.0.0'] }));
    assert.match(stepOf(w, 'release-notes').textContent, /docs\/releases\/1\.0\.0\.md on main: written/, 'the fixture has the notes on main');
    assert.equal(stopShows(w), shows, `Stop ${shows ? 'shows' : 'is hidden'} for a run record with ${JSON.stringify(patch)}`);
  });
}
// Bug this guards (#1375): the Draft notes tooltip said the suite runs once the notes commit is on the branch, but the
// run also waits while another card is open (relfixes() busy), so the owner saw no reason for the wait.
test('#1375: the Draft notes tooltip says the suite also waits for open cards', () => {
  const w = boot();
  deliver(w, data(null, { notes: false, written: [] }));
  assert.match(act(card(w), 'release-prep').title, /branch the suite tests and no other card is open\./);
});
// Bug this guards (#1365): a notes card closed before it landed (relfixes() records its fixes entry closed) starts no
// run, but the panel still said the suite runs by itself once the card lands.
test('#1365: a run whose notes card was closed shows the notes step failed, not under way', () => {
  const w = boot();
  const id = 'c20261114T081500-plugin-0';
  deliver(w, data({ ...RUN, sha: null, ended: '2026-11-14T08:15:00Z', state: 'waiting', reasons: [`notes card ${id} started`],
    notes: { card: id, then: 'prep', mode: null, machine: null }, fixes: [{ issue: null, card: id, ids: [id], state: 'closed' }] }, { notes: false, written: [] }));
  const s1 = stepOf(w, 'release-notes');
  assert.equal(s1.dataset.state, 'failed', 'the closed card is not shown as a step under way');
  assert.equal(s1.querySelector('.release-line').textContent, `docs/releases/1.0.0.md on main: missing: card ${id} was closed before it landed. Draft notes writes them again`);
  assert.equal(s1.querySelector('[data-figure="notes-card"]'), null, 'the panel does not say the suite runs once the card lands');
  assert.equal(chip(w), 'Notes missing');
});

// Bug this guards (#97): Release offered Wide and Full only, and started Wide; the owner wants it Small by default, and
// a Small card must still show its three steps and its button, laid out in one column.
test('D2: Release offers Small, Wide and Full, starts Small, and at Small shows each card\'s steps and next button in one column', async () => {
  const w = boot();
  deliver(w, data(null));
  const size = rel(w).querySelector('.panel-head select.size');
  assert.deepEqual(Array.from(size.options, (o) => o.value), ['small', 'wide', 'full']);
  assert.equal(rel(w).dataset.size, 'small', 'a new layout starts Small');
  assert.equal(size.value, 'small');
  assert.deepEqual(Array.from(card(w).querySelectorAll('.release-steps > [data-step]'), (s) => s.dataset.step), ['release-notes', 'full-suite', 'release']);
  assert.equal(act(card(w), 'release-prep').textContent, 'Run suite');
  assert.deepEqual(await sent(w, () => { act(card(w), 'release-prep').click(); act(card(w), 'release-prep').click(); act(card(w), 'mode-parallel').click(); }),
    [{ action: 'release-run', args: ['prep', '1.0.0', '--parallel'], repo: 'plugin' }], 'the button works at Small');
  // jsdom lays nothing out: the rule that puts each step's chip above its line, and the field above its button, is read.
  assert.match(css, /\.panel\[data-panel="release"\]\[data-size="small"\] \.release-steps \.row-main,\s*\.panel\[data-panel="release"\]\[data-size="small"\] \.release-go \{ flex-direction: column;/);
  size.value = 'wide'; size.dispatchEvent(new w.Event('change'));
  assert.equal(rel(w).dataset.size, 'wide', 'and it can be set Wide again');
});

// Bugs this guards: a run under way shows no progress and cannot be stopped from the Board, or a second run is offered.
// Bug: it counted the cases and named the failed cases, not the test files.
test('D2: a run under way shows a progress bar of files done of all, the failed files\' names, Suite running and Stop', async () => {
  const w = boot();
  deliver(w, data({ ...RUN, ended: null, state: 'running', done: 120, of: 1400, failed: 2, cases: ['code.test: breaks', 'code.test: flips'],
    files: { done: 12, of: 140, failed: ['code.test'] } }));
  const bar = stepOf(w, 'full-suite').querySelector('progress');
  assert.deepEqual([bar.value, bar.max], [12, 140]);
  assert.match(stepOf(w, 'full-suite').querySelector('[data-figure="progress"]').textContent, /12 of 140 files done · 1 failed/);
  assert.deepEqual(Array.from(stepOf(w, 'full-suite').querySelectorAll('[data-list="failed"] li'), (x) => x.textContent), ['code.test']);
  assert.equal(chip(w), 'Suite running');
  // #31: the line, a span with a time in it, showed as "[object HTMLSpanElement]".
  const going = stepOf(w, 'full-suite').querySelector('.release-line');
  assert.match(going.textContent, /^Running on bbbbbbbbbbbb · .+ so far$/);
  assert.ok(going.querySelector('time.since'), 'the time is a live time element');
  assert.equal(act(card(w), 'release-prep').disabled, true, 'no second run beside the one under way');
  assert.deepEqual(await sent(w, () => { act(card(w), 'release-prep').click(); act(card(w), 'release-prep').click(); }), []);
  // Bug (#413): Release was hidden while the suite ran; it shows, disabled, with the run's progress in its text.
  assert.equal(act(card(w), 'release').textContent, 'Release 1.0.0: the suite is running (12 of 140 files)');
  assert.equal(act(card(w), 'release').disabled, true);
  assert.ok(shown(w, act(card(w), 'release')) && shown(w, act(card(w), 'release-prep')), 'both buttons show while the suite runs');
  assert.deepEqual(await sent(w, () => act(card(w), 'release-stop').click()), []);
  // Bug: Stop sent no version, so a late second click stopped whatever run was under way by then, of any version. It
  // sends the version of the run it shows, and the engine stops no run of another one.
  assert.deepEqual(await sent(w, () => act(card(w), 'release-stop').click()), [{ action: 'release-run', args: ['stop', '1.0.0'], repo: 'plugin' }]);
});

// Bug (#1240): while the failed cases ran again, the row kept the first run's bar with no sign of the rerun. The
// rerun's round, case, bar and last move show; the first run's counts are a plain line under it, not the progress.
test('#1240: while the failed cases run again, the row shows that round\'s case, bar and last move, the first run as a plain line', () => {
  const w = boot();
  deliver(w, data({ ...RUN, ended: null, state: 'running', failed: 2, cases: ['code.test: breaks', 'code.test: flips'],
    files: { done: 140, of: 140, failed: ['code.test'] },
    rerun: { round: 2, of: 6, case: 'code.test: breaks', since: '2026-11-14T08:20:00Z', at: '2026-11-14T08:21:00Z', done: 3, failed: 1, files: { done: 1, of: 4, failed: ['code.test'] } } }));
  const re = stepOf(w, 'full-suite').querySelector('[data-figure="rerun"]');
  assert.match(re.textContent, /^Running the failed cases again: round 2 of 6, code\.test: breaks · last moved .+ ago$/);
  assert.ok(re.querySelector('time.since'), 'the last move is a live time element');
  const bars = stepOf(w, 'full-suite').querySelectorAll('progress');
  assert.deepEqual(Array.from(bars, (b) => [b.value, b.max]), [[1, 4]], 'the one bar is the rerun\'s, not the first run\'s 140 of 140');
  assert.match(stepOf(w, 'full-suite').querySelector('[data-figure="first-run"]').nextElementSibling.textContent, /^140 files done · 1 failed$/);
});

// Bug this guards (#791): a press that starts the suite sent no mode, so every release suite ran its files one by one,
// or sent one the owner did not choose.
test('#791: Run suite asks one by one or in parallel; in parallel sends --parallel, one by one --serial, Cancel nothing', async () => {
  const w = boot();
  deliver(w, data(null));
  const press = () => { act(card(w), 'release-prep').click(); act(card(w), 'release-prep').click(); };
  assert.deepEqual(await sent(w, press), [], 'nothing is sent before the mode is chosen');
  const ask = card(w).querySelector('[data-figure="mode-ask"]');
  assert.equal(ask.querySelector('p').textContent, 'Run the test files one by one or in parallel?');
  assert.match(act(ask, 'mode-serial').textContent, /^One by one.*Slower, the least load/);
  assert.match(act(ask, 'mode-parallel').textContent, /^In parallel.*Faster, more load on the build machine\. The belt is slower meanwhile/);
  assert.deepEqual(await sent(w, () => act(card(w), 'mode-parallel').click()), [{ action: 'release-run', args: ['prep', '1.0.0', '--parallel'], repo: 'plugin' }]);
  assert.equal(card(w).querySelector('[data-figure="mode-ask"]'), null, 'the question closes once answered');
  press();
  assert.deepEqual(await sent(w, () => act(card(w), 'mode-serial').click()), [{ action: 'release-run', args: ['prep', '1.0.0', '--serial'], repo: 'plugin' }]);
  press();
  assert.deepEqual(await sent(w, () => act(card(w), 'mode-cancel').click()), []);
  assert.equal(card(w).querySelector('[data-figure="mode-ask"]'), null);
  // Bug: a question left open while a run began elsewhere started a second run beside it.
  press();
  next(w, data({ ...RUN, ended: null, state: 'running' }));
  assert.equal(card(w).querySelector('[data-figure="mode-ask"]'), null, 'no question while a run is under way');
});
// Bug this guards (#791): Release that runs the suite first started it with no mode chosen.
test('#791: Release that runs the suite first asks the mode and sends it after the version', async () => {
  const w = boot();
  deliver(w, data({ ...RUN, step: 'release', ended: '2026-11-14T08:25:00Z', state: 'refused', failed: 0, cases: [], reasons: [] }));
  assert.deepEqual(await sent(w, () => { act(card(w), 'release').click(); act(card(w), 'release').click(); }), []);
  assert.deepEqual(await sent(w, () => act(card(w), 'mode-parallel').click()), [{ action: 'release-run', args: ['1.0.0', '--parallel'], repo: 'plugin' }]);
});
// Bug this guards (#1364): the mode question gave no sign of the project's rule, so the owner chose against it, and
// Draft notes (which sends no mode) was recorded and shown as one by one whatever the rule said.
const withRule = (run, mode, plugin) => { const d = data(run, plugin); d.panels.release.data.records[0].suiteMode = mode; return d; };
test('#1364 D3: the mode question presets the record\'s suiteMode and marks it the rule\'s choice; a choice still sends its own mode', async () => {
  const w = boot();
  deliver(w, withRule(null, 'parallel'));
  act(card(w), 'release-prep').click(); act(card(w), 'release-prep').click();
  const ask = card(w).querySelector('[data-figure="mode-ask"]');
  assert.equal(act(ask, 'mode-parallel').getAttribute('aria-pressed'), 'true');
  assert.equal(act(ask, 'mode-serial').getAttribute('aria-pressed'), 'false');
  assert.match(act(ask, 'mode-parallel').textContent, /The rule's choice\.$/);
  assert.doesNotMatch(act(ask, 'mode-serial').textContent, /rule's choice/);
  assert.deepEqual(await sent(w, () => act(card(w), 'mode-serial').click()), [{ action: 'release-run', args: ['prep', '1.0.0', '--serial'], repo: 'plugin' }], 'the flag given wins for the run');
  next(w, withRule(null, 'serial'));
  act(card(w), 'release-prep').click(); act(card(w), 'release-prep').click();
  assert.equal(act(card(w), 'mode-serial').getAttribute('aria-pressed'), 'true', 'the preset follows the rule');
  assert.equal(act(card(w), 'mode-parallel').getAttribute('aria-pressed'), 'false');
  // A record with no suiteMode (an older engine) presets nothing.
  next(w, data(null));
  act(card(w), 'release-prep').click(); act(card(w), 'release-prep').click();
  assert.deepEqual(['mode-serial', 'mode-parallel'].map((a) => act(card(w), a).getAttribute('aria-pressed')), ['false', 'false']);
  assert.doesNotMatch(card(w).querySelector('[data-figure="mode-ask"]').textContent, /rule's choice/);
});
// Also guards: the Draft notes run (main has no notes, so no suite runs and its record has no mode) was shown as the
// rule's mode, a false line. The mode of a run that starts its suite is covered by the #791 case below.
test('#1364 D3: Draft notes sends no mode, and step 2 shows no mode for that run, not the rule\'s guess', async () => {
  const w = boot();
  const mode = () => { const p = stepOf(w, 'full-suite').querySelector('[data-figure="suite-mode"]'); return p && p.textContent; };
  deliver(w, withRule(null, 'parallel', { notes: false, written: [] }));
  assert.equal(act(card(w), 'release-prep').textContent, 'Draft notes');
  act(card(w), 'release-prep').click();
  assert.deepEqual(await sent(w, () => act(card(w), 'release-prep').click()), [{ action: 'release-run', args: ['prep', '1.0.0'], repo: 'plugin' }], 'Draft notes sends no mode');
  assert.equal(card(w).querySelector('[data-figure="mode-ask"]'), null);
  const draft = { notes: false, written: [] };
  next(w, withRule({ ...RUN, ended: null, state: 'running', mode: null }, 'parallel', draft));
  assert.equal(mode(), null, 'the draft run has no mode: the rule does not say how a suite would run');
  next(w, withRule({ ...RUN, ended: '2026-11-14T08:15:00Z', state: 'passed', mode: null, failed: 0, cases: [] }, 'parallel', draft));
  assert.equal(mode(), null, 'a run that ended with no mode says none');
});
// Bug this guards (#791): step 2 did not say whether the suite runs, or ran, its files one by one or in parallel.
test('#791: step 2 shows the mode of the run under way and of the last run, from its record', () => {
  const w = boot();
  const mode = () => { const p = stepOf(w, 'full-suite').querySelector('[data-figure="suite-mode"]'); return p && p.textContent; };
  deliver(w, data({ ...RUN, ended: null, state: 'running', mode: 'parallel', files: { done: 1, of: 9 } }));
  assert.equal(mode(), 'Runs its test files in parallel');
  next(w, data({ ...RUN, ended: '2026-11-14T08:15:00Z', state: 'passed', mode: 'serial', failed: 0, cases: [] }));
  assert.equal(mode(), 'Ran its test files one by one');
  next(w, data({ ...RUN, ended: '2026-11-14T08:15:00Z', state: 'passed', mode: null, failed: 0, cases: [] }));
  assert.equal(mode(), null, 'a record with no mode says none');
  // Bug this guards: step 2 said the files ran in a mode when the run reused a green run and ran no file.
  next(w, data({ ...RUN, ended: '2026-11-14T08:15:00Z', state: 'passed', mode: 'parallel', failed: 0, cases: [], reused: { sha: HEAD, time: '2026-11-14T07:00:00Z', ran: [], kept: 9 } }));
  assert.equal(mode(), null, 'a run that reused the earlier green run ran no file itself');
  assert.equal(mode(), null, 'a reused result ran no file');
  // Bug this guards (#820): a run that reran only some files and kept the other green results ran those files in its mode.
  next(w, data({ ...RUN, ended: '2026-11-14T08:15:00Z', state: 'passed', mode: 'parallel', failed: 0, cases: [], reused: { sha: HEAD, time: '2026-11-14T07:00:00Z', ran: ['a.test.sh'], kept: 8 } }));
  assert.equal(mode(), 'Ran its test files in parallel', 'a run that reran some files says its mode');
  // Bug this guards: step 2 hid the mode while `conveyor.sh release` ran the suite itself (its record's mode is its
  // own; a release that runs no suite has none: t_relreuse).
  next(w, data({ ...RUN, step: 'release', ended: null, state: 'running', mode: 'parallel', failed: 0, cases: [], files: { done: 1, of: 9 } }));
  assert.equal(mode(), 'Runs its test files in parallel', 'release running the suite says its mode');
});

// Bug this guards (#820): docs/board.md said a run keeps every earlier green result only when it runs no files, so a
// run that reran some files and kept the other green results (the case above) read as having no mode. A text check: a guide page has no
// behaviour to run.
test('#820: the guide says a run that reruns some files and keeps the other green results shows its mode', () => {
  const guide = readFileSync(new globalThis.URL('../../../docs/board.md', import.meta.url), 'utf8').replace(/\s+/g, ' ');
  assert.doesNotMatch(guide, /keeps every [p]ass of an earlier run, because that run runs no test files/);
  // E1: a run with no files may keep the green results of an earlier commit, so the guide must not limit it to the same commit.
  assert.doesNotMatch(guide, /passed every file on the same commit/);
  assert.match(guide, /no mode for a run that runs no test files and keeps the [p]asses of an earlier run, on the same commit or an earlier one\./);
  assert.match(guide, /A run that runs only some files again, and keeps the [p]asses of the other files, shows its mode\./);
});

// Bug this guards (#253): a case stopped at its file's `# timeout:` limit showed only as a failed file, so a hung case
// read as a plain failure.
test('a failed run names each case that timed out as timed out, beside the failed files', async () => {
  const w = boot();
  deliver(w, data({ ...RUN, ended: '2026-11-14T08:15:00Z', state: 'failed', done: 140, of: 140, failed: 2, cases: ['stall', 'metrics'], timedout: ['metrics'],
    files: { done: 140, of: 140, failed: ['conveyor/conveyor.test.sh'] } }));
  assert.equal(stepOf(w, 'full-suite').dataset.state, 'failed');
  assert.deepEqual(Array.from(stepOf(w, 'full-suite').querySelectorAll('[data-list="timedout"] li'), (x) => x.textContent), ['metrics: timed out']);
});

// Bug this guards (#789): a suite that passed because each failed case passed alone, or a red one with a flaky case
// beside the one that blocks it, did not say which cases were judged flaky, so the owner could not tell what was passed over.
test('#789: a passed suite names each case judged flaky under step 2, and a case that failed alone is not one', () => {
  const w = boot();
  deliver(w, data({ ...RUN, ended: '2026-11-14T08:15:00Z', state: 'passed', done: 140, of: 140, failed: 0, cases: [],
    alone: [{ case: 'a.test: flips', runs: ['passed', 'passed', 'passed'], verdict: 'flaky' }, { case: 'b.test: breaks', runs: ['failed'], verdict: 'failed' }] }));
  assert.equal(stepOf(w, 'full-suite').dataset.state, 'done');
  assert.deepEqual(Array.from(stepOf(w, 'full-suite').querySelectorAll('[data-list="flaky"] li'), (x) => x.textContent), ['a.test: flips: judged flaky, passed alone']);
});

// Bugs this guards (#760): a red run showed its failed files but not its fix cards, how many had landed, or that the
// release waited on them; a fix closed with no landed card read as if the suite would run again by itself.
const RED = { ...RUN, ended: '2026-11-14T08:15:00Z', state: 'failed', failed: 1, cases: ['a.test: breaks'], files: { done: 9, of: 9, failed: ['a.test'] } };
const fixLines = (w) => Array.from(stepOf(w, 'full-suite').querySelectorAll('[data-list="fixes"] li'), (x) => x.textContent);
const fixNext = (w) => stepOf(w, 'full-suite').querySelector('[data-figure="fixes-next"]').textContent;
test('#760 D1: a red run with two fixes, one landed: both with their states and the line that the suite runs again when every fix has landed', () => {
  const w = boot();
  deliver(w, data({ ...RED, fixes: [{ issue: 753, state: 'landed' }, { issue: 754, state: 'open' }] }));
  assert.deepEqual(fixLines(w), ['#753: landed', '#754: open']);
  assert.equal(stepOf(w, 'full-suite').querySelector('[data-list="fixes"] a').href, `${URL}/issues/753`);
  assert.match(stepOf(w, 'full-suite').querySelector('[data-list="fixes"]').textContent, /1 of 2 landed/);
  assert.equal(fixNext(w), 'The suite runs again when every fix has landed.');
  // Every fix landed but relfixes() has not started the run (restarted null: a push owed, a pull request not merged or
  // another open card holds it): the Board must not say it runs now.
  const all = [{ issue: 753, state: 'landed' }, { issue: 754, state: 'landed' }];
  next(w, data({ ...RED, fixes: all, restarted: null }));
  assert.equal(fixNext(w), 'Every fix has landed. The suite runs again when their commits are on the branch it tests and no other card is open.');
  // Started (restarted set): it runs again now.
  next(w, data({ ...RED, fixes: all, restarted: '2026-11-14T09:00:00Z' }));
  assert.equal(fixNext(w), 'The suite runs again now.');
});

// Bug it catches (#1347): a fix card with no GitHub issue (issue null, its card id) was left out of the list, so a red run
// showed fewer fixes than the suite waits for.
test('#1347: a fix card with no GitHub issue is listed by its card id, with its state', () => {
  const w = boot();
  deliver(w, data({ ...RED, fixes: [{ issue: 753, state: 'landed' }, { issue: null, card: 'c20261122T120000-sample-0', ids: ['c20261122T120000-sample-0'], state: 'open' }] }));
  assert.deepEqual(fixLines(w), ['#753: landed', 'c20261122T120000-sample-0: open']);
  assert.match(stepOf(w, 'full-suite').querySelector('[data-list="fixes"]').textContent, /1 of 2 landed/);
});

test('#760 D2: a fix closed with no landed card is named, and the release waits for the Foreman', () => {
  const w = boot();
  deliver(w, data({ ...RED, fixes: [{ issue: 753, state: 'landed' }, { issue: 755, state: 'closed' }] }));
  assert.deepEqual(fixLines(w), ['#753: landed', '#755: closed with no landed card']);
  assert.equal(fixNext(w), '#755 was closed with no landed card: the release waits for the Foreman.');
});

test('#760 D3: a red run with no fixes shows no fixes part', () => {
  const w = boot();
  deliver(w, data({ ...RED, fixes: [] }));
  assert.equal(stepOf(w, 'full-suite').dataset.state, 'failed');
  assert.equal(card(w).querySelector('[data-list="fixes"]'), null);
  assert.equal(card(w).querySelector('[data-figure="fixes-next"]'), null);
});

// Bugs this guards (#274): a red suite on main's head offers no honest way to release, or Release anyway goes on one
// click, with a confirm that does not name the failures it releases over, or is offered over a suite of an older main.
test('#274: release-prep\'s red run on main\'s head offers Release anyway, on a second click that names the failed files and cases', async () => {
  const w = boot();
  const red = { ...RUN, ended: '2026-11-14T08:15:00Z', state: 'failed', done: 140, of: 140, failed: 1, cases: ['capwaittests'], files: { done: 140, of: 140, failed: ['conveyor/conveyor.test.sh'] } };
  deliver(w, data(red));
  assert.equal(chip(w), 'Suite failed');
  assert.deepEqual([act(card(w), 'release').textContent, act(card(w), 'release').disabled], ['Release 1.0.0: the suite failed: 1 failure', true]);
  assert.ok(stepOf(w, 'full-suite').contains(act(card(w), 'release-anyway')), 'Release anyway is beside the red result');
  assert.deepEqual(await sent(w, () => act(card(w), 'release-anyway').click()), [], 'one press sends nothing');
  assert.equal(act(card(w), 'release-anyway').textContent,
    'Click again: release 1.0.0 over this failed suite, with no new run. Failed files: conveyor/conveyor.test.sh. Failed cases: capwaittests.');
  assert.deepEqual(await sent(w, () => act(card(w), 'release-anyway').click()), [{ action: 'release-run', args: ['anyway', '1.0.0'], repo: 'plugin' }]);
  next(w, data(red, { head: NEW }));
  assert.equal(act(card(w), 'release-anyway'), null, 'no Release anyway over a suite of an older main');
});

// Bugs this guards: a suite passed on main's head offers no release; once a card lands it still offers one, of a main
// the suite never tested; a release made shows as still to do.
test('D3: passed on main\'s head, Release 1.0.0; a card lands, Main moved and Run again on the new main; released, Released', async () => {
  const w = boot();
  const passed = { ...RUN, ended: '2026-11-14T08:15:00Z', state: 'passed', done: 140, of: 140, failed: 0, cases: [] };
  deliver(w, data(passed));
  assert.equal(chip(w), 'Ready to release');
  assert.equal(stepOf(w, 'full-suite').dataset.state, 'done');
  // #31: the result, commit and time showed as "[object HTMLSpanElement]".
  assert.match(stepOf(w, 'full-suite').querySelector('.release-line').textContent, /^Passed on bbbbbbbbbbbb · .+ ago$/);
  assert.equal(act(card(w), 'release').textContent, 'Release 1.0.0');
  // #413: once the suite passed on main's head with the notes written, Release is enabled and the run button says again.
  assert.equal(act(card(w), 'release').disabled, false);
  assert.equal(act(card(w), 'release-prep').textContent, 'Run suite again');
  // Release alone sends release-run <version>, the one that makes the tag and the GitHub release.
  act(card(w), 'release').click();
  assert.deepEqual(await sent(w, () => act(card(w), 'release').click()), [{ action: 'release-run', args: ['1.0.0'], repo: 'plugin' }]);
  next(w, data(passed, { head: NEW, count: 27 }));
  assert.equal(chip(w), 'Main moved since the suite');
  assert.match(stepOf(w, 'full-suite').querySelector('.release-line').textContent, /^Passed on bbbbbbbbbbbb · .+ ago · main has moved since$/);
  assert.equal(act(card(w), 'release-prep').textContent, 'Run again on the new main');
  assert.equal(act(card(w), 'release').disabled, true, 'no release of a main the suite never tested');
  assert.deepEqual(await sent(w, () => act(card(w), 'release-prep').click()), []);
  assert.deepEqual(await sent(w, () => { act(card(w), 'release-prep').click(); act(card(w), 'mode-serial').click(); }), [{ action: 'release-run', args: ['prep', '1.0.0', '--serial'], repo: 'plugin' }]);
  next(w, data({ ...passed, step: 'release', state: 'released' }, { tag: 'v1.0.0', count: 2, head: NEW, next: '1.1.0', notes: false }));
  assert.equal(chip(w), 'Released');
  assert.equal(stepOf(w, 'release').dataset.state, 'done');
});

// Bug this guards (#35): Release gave no sign whether it reuses the suite that passed on main's head or runs it again
// first (release-run reuses a passed release-prep of that version on main's head).
test('#35: a passed release-prep on main\'s head: step 2 and Release\'s confirm say "Uses the suite that passed"', async () => {
  const w = boot();
  deliver(w, data({ ...RUN, ended: '2026-11-14T08:15:00Z', state: 'passed', done: 140, of: 140, failed: 0, cases: [] }));
  assert.match(stepOf(w, 'full-suite').querySelector('[data-figure="suite-use"]').textContent, /^Uses the suite that passed at .+ on bbbbbbbbbbbb$/);
  act(card(w), 'release').click();
  assert.match(act(card(w), 'release').textContent, /^Click again to release 1\.0\.0\. Uses the suite that passed at .+ on bbbbbbbbbbbb\.$/);
});
// Bug this guards (#43): a release-prep that reran only the failed and changed files and reused the files that passed
// before looked like a whole suite run on the panel, so the owner could not tell what the green run covers.
test('#43: a run that reused an earlier run says "Reran 1 file, reused 2 passed files from" its commit on step 2; a whole one says so', () => {
  const w = boot();
  const passed = { ...RUN, ended: '2026-11-14T08:15:00Z', state: 'passed', failed: 0, cases: [] };
  deliver(w, data({ ...passed, reused: { sha: NEW, ran: ['t/f1.test.sh'], kept: 2 } }));
  assert.equal(stepOf(w, 'full-suite').querySelector('[data-figure="suite-scope"]').textContent, 'Reran 1 file, reused 2 passed files from cccccccccccc');
  next(w, data({ ...passed, reused: null }));
  assert.equal(stepOf(w, 'full-suite').querySelector('[data-figure="suite-scope"]').textContent, 'Ran the whole suite');
  // Bug this guards (#44): a release-prep that ran no test, taking a green full test run on the same commit, read as
  // "Reran 0 files", which does not say whose run it took or when.
  next(w, data({ ...passed, reused: { sha: HEAD, time: '2026-11-14T07:40:00Z', ran: [], kept: 3 } }));
  assert.match(stepOf(w, 'full-suite').querySelector('[data-figure="suite-scope"]').textContent, /^Reused the green run of \d.* on bbbbbbbbbbbb$/);
});
// Bug this guards (#35): a release refused after the green suite run is no green release-prep run, so release-run runs the suite first;
// the panel must not say it reuses one.
test('#35: a refused release on main\'s head: step 2 and Release\'s confirm say "Runs the suite first (about 25 min)"', async () => {
  const w = boot();
  deliver(w, data({ ...RUN, step: 'release', ended: '2026-11-14T08:25:00Z', state: 'refused', failed: 0, cases: [], reasons: ['the checkout has uncommitted changes'] }));
  assert.equal(stepOf(w, 'full-suite').querySelector('[data-figure="suite-use"]').textContent, 'Runs the suite first (about 25 min)');
  act(card(w), 'release').click();
  assert.equal(act(card(w), 'release').textContent, 'Click again to release 1.0.0. Runs the suite first (about 25 min).');
});

// Bug this guards: every change since the tag was listed open, as a raw subject with its hash, a finding's file:line
// and its "Proof:" text.
test('D4: the changes are closed under "Show 26 changes"; open, each is its issue\'s title, linked, no hash or Proof:, 10 at a time', () => {
  const w = boot();
  deliver(w, data(null));
  const box = card(w).querySelector('details[data-list="changes"]');
  assert.equal(box.open, false);
  assert.equal(box.querySelector('summary').textContent, 'Show 26 changes');
  box.open = true;
  const lines = () => Array.from(box.querySelectorAll('.release-change'));
  assert.equal(lines().length, 10);
  assert.equal(lines()[0].textContent, '#126 Suite status counts cases 26.', 'newest first, the title alone');
  assert.equal(lines()[0].querySelector('a').href, `${URL}/issues/126`);
  for (const l of lines()) assert.doesNotMatch(l.textContent, /Proof:|watch-conveyor\.sh|[0-9a-f]{7}|\(#/, l.textContent);
  box.querySelector('[data-act="list-more"]').click();
  assert.equal(lines().length, 20);
  // The snapshot lists only the newest changes (100): those it does not list are counted, not left out unsaid.
  next(w, data(null, { count: 130 }));
  assert.match(card(w).querySelector('details[data-list="changes"]').textContent, /Show 130 changes[\s\S]*\b104 older changes are not listed here\./);
});

// Bug this guards: a refusal's reasons were one list under the run, so the owner could not tell which step to fix.
test('D5: a refused release shows each reason under the step it belongs to', () => {
  const w = boot();
  deliver(w, data({ ...RUN, step: 'release', ended: '2026-11-14T08:15:00Z', state: 'refused', done: 140, failed: 0, cases: [], moved: true,
    reasons: ['docs/releases/1.0.0.md breaks the release notes style', 'main moved while the suite ran, from bbbbbbbbbbbb to cccccccccccc', 'the privacy check found 1 hit in the changes since the first commit'] }));
  const reasons = (name) => Array.from(stepOf(w, name).querySelectorAll('[data-list="reasons"] li'), (x) => x.textContent);
  assert.deepEqual(reasons('release-notes'), ['docs/releases/1.0.0.md breaks the release notes style']);
  assert.deepEqual(reasons('full-suite'), ['main moved while the suite ran, from bbbbbbbbbbbb to cccccccccccc']);
  assert.deepEqual(reasons('release'), ['the privacy check found 1 hit in the changes since the first commit']);
  assert.equal(stepOf(w, 'release').dataset.state, 'failed');
});

// The suite's machine (#1270). The rule is the control record's suiteMachine; the run's record names where it went.
const DEVBOX = { kind: 'devbox', size: 'XL', tag: 'conveyor-suite-plugin', idleStop: '15m' };
const BOX = { kind: 'devbox', name: 'Namespace Devbox XL', target: null, dir: null, lease: 'lease-7f3a', step: 'checkout', secs: { start: 0, setup: 0 }, reason: null };
const steps = (w) => Array.from(card(w).querySelectorAll('[data-list="machine-steps"] li'), (li) => [li.dataset.step, li.dataset.state, li.textContent.trim()]);

// Bug this guards: a run on a devbox looked like any other run, so the owner could not see which box held the suite,
// what it was doing, or what Stop would do to it.
test('#1270 D1: a run on a devbox shows the machine line, the six steps in order with done and now, and what Stop does', () => {
  const w = boot();
  deliver(w, data({ ...RUN, ended: null, state: 'running', machine: BOX }, {}, DEVBOX));
  const line = card(w).querySelector('[data-figure="machine"]');
  assert.match(line.textContent, /^On Namespace Devbox XL \(lease-7f3a\) · commit bbbbbbb · leased /);
  assert.deepEqual(steps(w).map(([k, s]) => [k, s]),
    [['start', 'done'], ['setup', 'done'], ['checkout', 'now'], ['run', 'todo'], ['results', 'todo'], ['done', 'todo']]);
  assert.deepEqual(steps(w).map(([, , t]) => t), ['Start · reused', 'Set up · not needed', 'Check out', 'Run', 'Bring back results', 'Give back the box']);
  const chips = Array.from(card(w).querySelectorAll('[data-list="machine-steps"] .chip'), (c) => c.className);
  assert.deepEqual(chips, ['chip chip-ok', 'chip chip-ok', 'chip chip-info', 'chip chip-quiet', 'chip chip-quiet', 'chip chip-quiet']);
  assert.equal(card(w).querySelector('[data-figure="stop-line"]').textContent, 'Stops the run on the devbox and gives the box back.');
  assert.ok(act(card(w), 'release-stop'), 'Stop shows beside its line');
  // The results step covers two chips: the results are back, the box is being given back.
  next(w, data({ ...RUN, ended: null, state: 'running', machine: { ...BOX, step: 'results', secs: { start: 12, setup: 0, checkout: 30, run: 600 } } }, {}, DEVBOX));
  assert.deepEqual(steps(w).map(([, s]) => s), ['done', 'done', 'done', 'done', 'done', 'now']);
  assert.equal(steps(w)[0][2], 'Start · under a minute');
});

// Bug this guards: a run on this machine showed a machine line and steps that only a remote run has.
test('#1270 D4: a run on this machine shows no machine line, steps or Stop line', () => {
  const w = boot();
  deliver(w, data({ ...RUN, ended: null, state: 'running', machine: { kind: 'local', name: 'this machine', target: null, dir: null, lease: null, step: 'run', secs: {}, reason: null } }, {}, DEVBOX));
  assert.equal(card(w).querySelector('[data-figure="machine"]'), null);
  assert.equal(card(w).querySelector('[data-list="machine-steps"]'), null);
  assert.equal(card(w).querySelector('[data-figure="stop-line"]'), null);
  next(w, data({ ...RUN, ended: null, state: 'running', machine: null }, {}, DEVBOX));
  assert.equal(card(w).querySelector('[data-figure="machine"]'), null, 'a record with no machine shows none');
});

const NOT_STARTED = { ...RUN, ended: '2026-11-14T08:01:00Z', state: 'not started', machine: { ...BOX, lease: null, step: 'start', secs: { start: 3 }, reason: 'Not logged in to Namespace' }, reasons: ['Not logged in to Namespace'] };
// Bug this guards: a devbox that could not start left "Suite not run" with no reason and no way on; the owner could not
// tell a login to fix from a broken suite.
test('#1270 D2: a run that did not start shows its chip, the failed step with its reason, one fix line and both buttons; Run on this machine instead sends --machine local', async () => {
  const w = boot();
  deliver(w, data(NOT_STARTED, {}, DEVBOX));
  assert.equal(chip(w), 'Suite not started');
  assert.equal(stepOf(w, 'full-suite').dataset.state, 'failed');
  assert.deepEqual(steps(w)[0], ['start', 'failed', 'Start · not logged in to Namespace']);
  assert.deepEqual(steps(w).slice(1).map(([, s]) => s), ['todo', 'todo', 'todo', 'todo', 'todo']);
  assert.equal(card(w).querySelector('[data-figure="machine-fix"]').textContent, 'Run devbox login once in a terminal on the build machine, then press Run suite again.');
  assert.equal(card(w).querySelector('[data-list="reasons"]'), null, 'the reason shows once, in the failed step\'s chip');
  assert.equal(act(card(w), 'release-prep').textContent, 'Run suite again');
  assert.equal(act(card(w), 'run-here').textContent, 'Run on this machine instead');
  assert.deepEqual(await sent(w, () => act(card(w), 'run-here').click()), [], 'one press sends nothing');
  assert.deepEqual(await sent(w, () => act(card(w), 'run-here').click()), [{ action: 'release-run', args: ['prep', '1.0.0', '--machine', 'local'], repo: 'plugin' }]);
});

// Bug this guards: the suite's start could fail for a reason other than the login and still be told to log in.
test('#1270 D2: another reason for a run that did not start gets the general fix line', () => {
  const w = boot();
  deliver(w, data({ ...NOT_STARTED, machine: { ...NOT_STARTED.machine, step: 'setup', reason: 'its .conveyor/test-machine.sh failed: no space left' } }, {}, DEVBOX));
  assert.deepEqual(steps(w).map(([, s]) => s), ['done', 'failed', 'todo', 'todo', 'todo', 'todo']);
  assert.equal(steps(w)[1][2], 'Set up · its .conveyor/test-machine.sh failed: no space left');
  assert.match(card(w).querySelector('[data-figure="machine-fix"]').textContent, /^Fix the cause named in the failed step, then press Run suite again\.$/);
});

// Bug this guards: the owner could not choose the machine for one run, or the rule's choice was not the one preset.
test('#1270 D3: the machine question presets the rule; the press sends the chosen machine, and This machine sends --machine local', async () => {
  const w = boot();
  const last = { ...RUN, ended: '2026-11-14T08:25:00Z', state: 'passed', machine: BOX };
  deliver(w, data(last, {}, DEVBOX));
  const press = () => { act(card(w), 'release-prep').click(); act(card(w), 'release-prep').click(); };
  assert.deepEqual(await sent(w, press), []);
  const ask = card(w).querySelector('[data-figure="machine-ask"]');
  assert.equal(ask.querySelector('p').textContent, 'On which machine?');
  assert.match(act(ask, 'machine-local').textContent, /^This machine.*The belt is slower meanwhile\./);
  assert.match(act(ask, 'machine-rule').textContent, /^Namespace Devbox XL.*the rule's choice · last run /);
  assert.equal(act(ask, 'machine-rule').getAttribute('aria-pressed'), 'true', 'the rule\'s machine is preset');
  assert.equal(act(ask, 'machine-local').getAttribute('aria-pressed'), 'false');
  assert.equal(card(w).querySelector('[data-figure="mode-ask"] > p').textContent, 'Run the test files one by one or in parallel?', 'the mode question stays');
  // The preset sends no machine: the rule applies.
  assert.deepEqual(await sent(w, () => act(card(w), 'mode-parallel').click()), [{ action: 'release-run', args: ['prep', '1.0.0', '--parallel'], repo: 'plugin' }]);
  press();
  act(card(w), 'machine-local').click();
  assert.equal(act(card(w), 'machine-local').getAttribute('aria-pressed'), 'true');
  assert.equal(act(card(w), 'machine-rule').getAttribute('aria-pressed'), 'false');
  assert.deepEqual(await sent(w, () => act(card(w), 'mode-serial').click()), [{ action: 'release-run', args: ['prep', '1.0.0', '--serial', '--machine', 'local'], repo: 'plugin' }]);
  // The choice is for one run: the next question starts on the rule again.
  press();
  assert.equal(act(card(w), 'machine-rule').getAttribute('aria-pressed'), 'true');
  act(card(w), 'machine-local').click();
  act(card(w), 'mode-cancel').click();
  press();
  assert.equal(act(card(w), 'machine-rule').getAttribute('aria-pressed'), 'true', 'Cancel drops the choice');
});

// Bug this guards: a rule of this machine asked a machine question with nothing to choose.
for (const [name, rule] of [['none', null], ['on this machine', { kind: 'local' }]]) {
  test(`#1270 D3: with the rule ${name}, the question asks no machine`, () => {
    const w = boot();
    deliver(w, data(null, {}, rule));
    act(card(w), 'release-prep').click(); act(card(w), 'release-prep').click();
    assert.ok(card(w).querySelector('[data-figure="mode-ask"]'));
    assert.equal(card(w).querySelector('[data-figure="machine-ask"]'), null);
  });
}

// Bug this guards: the question showed the last run's time under another box's name, or after a run here, as if that box had run it.
const ENDED = { ended: '2026-11-14T08:25:00Z', state: 'passed' };
const SSH_RULE = { kind: 'ssh', target: 'ci@box-b.example.com' };
const onSsh = (host) => ({ ...BOX, kind: 'ssh', name: `${host}.example.com`, target: `ci@${host}.example.com`, lease: null });
for (const [name, machine, rule, want] of [
  ['the rule\'s machine ran it', BOX, DEVBOX, /last run /],
  ['another box ran it', onSsh('box-a'), SSH_RULE, /the rule's choice$/],
  ['the same ssh box ran it', onSsh('box-b'), SSH_RULE, /last run /],
  ['a run here', { ...BOX, kind: 'local', name: 'this machine' }, DEVBOX, /the rule's choice$/],
]) {
  test(`#1270 D3: the last run time, when ${name}`, () => {
    const w = boot();
    deliver(w, data({ ...RUN, ...ENDED, machine }, {}, rule));
    act(card(w), 'release-prep').click(); act(card(w), 'release-prep').click();
    assert.match(act(card(w), 'machine-rule').textContent, want);
  });
}

// Bug this guards: the machine line said "commit " with nothing after it while the machine started, or when its start failed
// (the record gets its commit after the machine starts).
test('#1270 D1: a run with no commit yet shows the machine line without one', () => {
  const w = boot();
  deliver(w, data({ ...RUN, sha: null, ended: null, state: 'running', machine: { ...BOX, step: 'start', secs: {} } }, {}, DEVBOX));
  const text = card(w).querySelector('[data-figure="machine"]').textContent;
  assert.match(text, /^On Namespace Devbox XL \(lease-7f3a\) · leased /);
  assert.doesNotMatch(text, /commit/);
});

// Bug this guards: a worktree that could not be made on this machine (a not started run with a local machine) showed no
// reason and offered to run on this machine, the one that failed.
test('#1270 D2: a run not started on this machine shows its reason and Run suite again, and no offer to run here', () => {
  const w = boot();
  const reason = 'the worktree of bbbbbbbbbbbb could not be made: no space left';
  const machine = { kind: 'local', name: 'this machine', target: null, dir: null, lease: null, step: 'checkout', secs: {}, reason };
  deliver(w, data({ ...NOT_STARTED, machine, reasons: [reason] }, {}, null));
  assert.equal(chip(w), 'Suite not started');
  assert.deepEqual(Array.from(card(w).querySelectorAll('[data-list="reasons"] li'), (li) => li.textContent), [reason]);
  assert.equal(card(w).querySelector('[data-list="machine-steps"]'), null);
  assert.equal(card(w).querySelector('[data-act="run-here"]'), null);
  assert.equal(act(card(w), 'release-prep').textContent, 'Run suite again');
});

// Bug this guards: the pressed machine looked like the other one (aria-pressed alone shows a sighted owner nothing).
// jsdom lays nothing out: the rule that marks the pressed choice is read.
test('#1270 D3: the pressed machine choice has its own style', () => {
  assert.match(css, /\.release-machine \.release-mode-pick\[aria-pressed="true"\] \{[^}]*border: 2px solid var\(--accent\)/);
});
