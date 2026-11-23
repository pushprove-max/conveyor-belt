// SPDX-License-Identifier: Apache-2.0
// The Tests page (#520; the owner chose mockup A, with mockup B's column "against its own median"): a tab of its own,
// after Rules. It shows one project at a time: with more than one on the host, the machine head's Show picks it, as
// on the Rules tab, and the heading names it ("Tests: sample").
// The page, top to bottom (#73, #74, #178): the Test map part, the figures, the table with its search and filters, Test edits by cards (#76),
// Removed by Optimize, the bar of the files selected and Recent actions. Its settings (#1088) are a panel of their own
// on the tab, Test settings: Test actions (the Tests model), Test limits and Auto-file. Each section says once where
// its rows save. One state S draws both panels; each panel has its own note, which says what its own controls did.
// The figures: Timed files, files slower than usual, files that wait more than they work (their
// last run took more than twice its CPU time on the clock: WAITS), and the card test steps of the 7 days: their slot
// wait and their run time. A figure that counts the files of a status is a button that shows that status alone, as
// its filter chip does.
// The table, one row a test file (every test file of main's checkout, run or not): a checkbox and the file, CPU s now,
// median, change against its own median, its last runs as bars (oldest first), clock against CPU, runs on record,
// the clock time its newest run took (Last run took, with that run's date and time on hover), Caught (#75: the card test
// steps it failed whose landed change left it as it was; the times it was edited until it passed, on hover), and its status
// (chips; its issue as a link, "#NN"; Runs other test files, Whole suite only and, for a file with NEVER runs on
// record or more and no catch, Never caught anything as grey text). A file with no CPU or clock time on
// record shows "Not timed yet" in place of its figures and comes after the timed files (by name, it sorts as any
// other); one with clock times only (its runner's report gives no CPU time) shows "Wall only". Each column heading has a hint on hover and on focus. A file the pack marks wholeOnly (a runner that starts
// other test files whole, each of them timed on its own) has "Runs other test files", is never Slower than usual or
// Waits, and has no Optimize. No test file has a CPU budget (#349). A search box over it keeps
// the rows whose path or one of whose case names (casesOf()) holds its text (any case), a row found by a case naming
// it beside the file name; filter chips, each with its count, show one status alone; the two
// apply together. Each column heading sorts the table by that column (file names A to Z, any other highest first; a
// second click reverses it, and an arrow shows which). With no sort picked, the rows that need a look (slower
// than usual, waits, flaky or fails often) come first, then the highest CPU s.
// Selected files: the header checkbox selects every row the search and filters show. With one file or more selected,
// a bar fixed at the foot of the screen (aria-live) says how many, with Judge, Optimize, Run and Clear. Judge and Run
// send one POST for all of them (control {action: testaction, args: [judge | run, file...]}); Optimize opens one
// preview, an issue a file (title and body editable), and its "File N issues" sends one test-issue with them all.
// The bar shows the answer for each file, and each file left out with why: the runner for Optimize, every file for
// Judge with no Tests model. From the click it shows a bar while the POST waits; then each action started shows its
// state there (queued, running with its time, then its result and its text to open), and each Mutation check its file's.
// A row opens (#130, the owner's mockup D) to the tabs Overview (open first), Timeline (N), Judge and Mutation, each
// tied to its pane. Overview: the diagnosis box (its state: its CPU s now, after which Optimize cards and by
// how much each changed it, its trend; the judge's verdict chip with its reason in one line and Full report, which
// opens the Judge tab; the buttons Judge, Optimize (Optimize again once one landed), Fix failures, Fix hollow cases,
// Fix the waiting, Make it run, Delete it (#189), Make it run alone and Record CPU time (#190), Rewrite as a direct
// check (#778: with the verdict indirect, the next step), Run and More, the next step suggested,
// nextStep(), primary), the box of its action, the editors picked, six tiles (CPU
// now with its median, the last 4 runs as bars with their values on hover and on focus, the last Optimize, the clock,
// bugs caught, mutants), its failures (#188: the card changes it caught, apart, then each failed test step with its
// kind, card and cases) and its 3 latest events with a link to the Timeline. Timeline: every event newest first (its
// runs, each with its card's issue or "whole suite" with its result; its Optimize issues; its test edits by their
// issue, Weakened marked; its judge runs), with the filter chips All, Runs, Optimize, Test edits and Judge. Judge: its
// newest ended judge, its verdict once at the top, then its report (without its VERDICT line), its hollow cases and
// the causes of its failures (its CAUSE lines).
// Mutation: its check. A pane is never taller than the window under the page head (app.css). Its Optimize issues
// (#74): each issue the Board filed for it (the snapshot's optimize: Optimize, and older speed-up, issues), with its
// "#NN" link and its state (open, building, blocked with the reason, landed with the commit, closed without landing);
// landed, the fix its card made (sped up, split, merged into <file>, deleted), its proof's CPU s before → after (with
// no after, the median of the runs since it landed) with the change and Helped or Did not help, and the median of
// the runs since it landed. The run where one landed (the first after it) is marked in its Last runs bars and in its runs. A file a landed Optimize deleted or merged (removed) is not
// in the table: Removed by Optimize, after it, shows its last numbers, the issue and the files that took its cases.
// Test edits by cards (#76): what each landed card did to a test file main had (the snapshot's edits, newest first):
// its card's issue as a link (never the card's id, #130), the file, the time and its counts (assertions removed, expected values changed, skip,
// only or todo marks added, timeouts raised, cases deleted), or "Edited, not read" for a kind of file the engine does
// not read. Filters: Weakened (any count above zero; the first view) and All edits. An opened row's Timeline lists its own edits.
// Hollow (#77): a file with hollow cases (hollowOf(): its newest ended judge's, else the engine's cheap check's) has the
// status Hollow, so its filter chip "Hollow N"; an opened row's Judge tab lists them with their kind and reason.
// Proxy checks (#780): a file whose lines start another test file or the suite runner, or poll a real process (the
// snapshot's proxy of the file, found by the engine reading it), has the chip "Proxy checks: line N, M" on its row and
// the filter "Proxy checks N"; beside the chip, each line with what it does and the comment that says why, or that none does.
// The other fix issues (#189), each a button of an opened row's actions with the preview Optimize opens, and a title
// the engine knows its card by: Fix hollow cases on a Hollow file (its HOLLOW lines; a deleted case is named on a
// COVERED-BY line), Fix the waiting on a file that Waits (the clock and CPU of its recent runs, and the WAIT lines its
// newest judge named, the snapshot's waits), and Make it run and Delete it on a file Never run, whose row says why
// it did not run when the engine can tell (the snapshot's neverRun). Each Done-when is what the card's check proves.
// #778: a file whose newest judge's verdict is indirect (it checks what it protects through a proxy) has Rewrite as a
// direct check, its next step: the preview of "Rewrite the test file <file> as direct checks" (REWRITE, lib/speedproof.sh:
// an Optimize card, checked by optproof()), its body built from the judge's DIRECT lines (draftDirect()).
// #190: a wholeOnly file's status says what a change to it costs (the snapshot's suite: the newest whole-suite run's
// CPU seconds), and Make it run alone files the issue speedproof.sh aloneproof() checks; a Wall only file's status names its runner
// (the pack's test.report) and, by the engine's plan (the snapshot's settings.cpuTime), either has Record CPU time,
// which previews the pack's test command wrapped in conveyor/tools/testtime.sh before an admin saves it
// (`conveyor.sh test-settings cpu-time <file>`), or says why no action is shown (wallWhy()).
// Mutation checks (#79): the column Mutants caught ("14 / 20": its newest done check, empty before one; when it ran and
// on which commit on hover; "queued", "running" or "paused" beside it); an opened row's check state (queued with its
// place, running with mutant n of m, paused, failed or done) and surviving mutants (source and line, before and after,
// "tests still passed"). Mutation check, in More and in the bar, is one POST control {action: mutate, args: [file...]}
// (`conveyor.sh mutate ask`: the front of the idle queue; no check starts while a card needs a test slot, and the bar
// says so). Optimize's preview lists the survivors; a landed Optimize shows the mutants caught before and after.
// Its More menu holds Explain the slowdown, Mutation check, Split it (#768: the preview Optimize opens, of an issue to split
// the file; disabled on a runner; a button of the row, primary, when the judge's newest verdict is split), Keep a case off,
// Close its issue as done and Mark as slow on purpose (it asks for the reason).
// Test settings, Test limits. Its rows save to the pack file (this project): the files slow on purpose (a
// list), and, only when the snapshot names them, the hard box of each test file (settings.box: {on}) and "Take a
// file off card runs" (settings.slowIssues, #457). "Test history starts at" (settings.historyStart) saves to the control
// record; the table, the failures and the Fix failures and Fix the waiting drafts count only what is on or after it.
// Every value is typed or picked first: the row says Unsaved, with Save and Cancel, as on the Rules tab, and only Save
// sends it: POST control {action: test-settings, args, repo}
// (`conveyor.sh test-settings`) for a pack setting. A value saved shows until a snapshot names it, or one begun after
// the answer names a value other than the one it replaced. A refused one keeps the value in force, with the refusal
// in its row.
// A project with no file times shows its step figures and one state, "No file times for this project", with what
// starts the record, and no table.
// The actions (#521, #73). The Board calls the control record's tests (`conveyor.sh control tests`) "the Tests
// model": its strip-down test (dashboard-local.test.sh) keeps the engine's retired word for it out of the page. Judge (Judge
// this test) and Explain the slowdown are a session on the Tests model (POST control {action: testaction, args:
// [judge | explain, file]}); Run (Run this file now) is testaction run (no session, no model). Put back a flaky case
// (its flaky issue closed, test-close: the case runs on cards again) shows beside the file's facts; Keep a case off is
// flaky-off (`conveyor.sh flaky off`, which files no issue); Close its issue as done is test-close, with the file's
// before and after numbers as its comment. Optimize shows a preview first (title "Optimize the test file <file>" and
// body, with the measured numbers, the file's hollow cases and the judge's kept verdict with the end of its text, both editable; no Done-when
// line), and files (POST control {action: test-issue, args: [file, title, body]}: `conveyor.sh testissue`, which keeps
// it as the file's issue) only on its second button; Cancel files nothing. With no Tests model, Judge and Explain say
// "Set the Tests model first." beside them, and a click on one says it again in its box, sending nothing.
// "Model for Tests actions": CLI, model (with Other… for a typed name) and effort, as the Rules tab's roles; a pick
// says Unsaved, Save sends POST control {action: tests, args: [cli, model, effort] or [default]}, Cancel puts back the
// one in force.
// An opened row shows its newest action (#74) in a box under its buttons; an ended judge's, on its Judge tab. From the click the box says it is sent, with a
// bar, while the POST waits for the build machine (which answers once the action has started or is queued); refused, why.
// An Optimize filed or a Mutation check asked from the row shows on a line beside it the same way (S.notes). While it
// runs, a bar and the time used against the action's limit, and its text as the snapshot brings it (kept here, so a
// text the snapshot cut to its end loses nothing seen before), with Stop (testaction stop <id>, that action alone) and
// Copy. Queued, a bar, "Queued, N ahead" and Stop. Ended, its
// result with its time, CLI, model and effort; a judge's starts with "Verdict: <word>" and its chip, and, for speed
// up, split, merge, delete or stabilise, "Optimize with this verdict", which opens the Optimize preview (for stabilise,
// the Fix failures preview, #188) with that verdict and its
// text, on Overview, scrolled to, with the cursor at the start of its body; the preview shows the verdict. The text of a judge or explain is formatted (md(): paragraphs, bold, lists, inline code and code blocks; any
// other markup as typed), a run's output as typed; Copy copies the raw text. Recent actions, collapsed until opened,
// counts the running and queued actions in its heading and lists each kept action and each Optimize issue, newest
// first, each with its file (a click opens its row), and Stop on a running or queued action, else Copy.
// Auto-file: the one switch (Off by default; "Turn on" shows the preview, the matches of the rules' last run, each
// with its guard's result, and asks for a second click), the guards and each rule's fields (each Unsaved until Save posts
// `conveyor.sh testrules guard|set`), and the log of what the rules filed and stopped.
// Its part (dashboard.sh, tests): {repo (null: none is steered), tests (the snapshot's: settings, rules, files (each
// with its optimize issues, each with its url, and removed), slower, edits, totals; null from a snapshot without it),
// testActions ({limit, actions, allowed:
// the pack's models by CLI, offered after a CLI's own}), control (the control record: its tests, the Tests model),
// clis (the host's CLIs, {models: null when it lists none, efforts} each), flaky ([{case, count, issue, files}]), testMap
// (conveyor/lib/testmap.sh mapboard(): state, as the map page shows it, with made, seconds and notMapped; tool or toolWhy; suiteSec; build,
// the last build by hand's record; null from a snapshot without it, and the part is not shown), repos, others}.
// The Test map part (#178): the map's state (made: the source and test files mapped, the commits behind main, when it
// was made and how long it took, and the test files it could not map, folded, each with why; not made yet; off;
// failed with its reason). Build the test map (POST control {action:
// testmap, args: [build]}, an admin's alone: the server refuses a member) names the coverage tool and the last
// whole-suite run's time before the click. While a build waits for its test slot or runs, a bar (test files done of
// all) and Stop (testmap stop); at its end, its result in place.
(function () {
  'use strict';
  const PART = 'tests';    // the part both panels draw from: the Tests panel's id; Test settings is `${PART}-settings`
  const REASON_MAX = 300;  // a reason, as dashboard_server.py's said_ok takes it
  const WAITS = 2;         // a file waits more than it works when its last run took more than this times its CPU time
  const FAILS = 2;         // a file fails often when this many test steps or more failed in it, not counting those a card's own change made fail (failsOf())
  const NEVER = 20;        // a file with this many runs on record or more and no catch shows "Never caught anything"
  const PACK = 'Pack file: this project';
  const CONTROL = 'Control record: this project';  // `conveyor.sh control tests`
  // The status chips, in the order of the filters: key, words, tone, whether a row with it needs a look.
  const MARKS = [
    ['slower', 'Slower than usual', 'warn', true], ['faster', 'Faster', 'ok', false],
    ['waits', 'Waits', 'info', true], ['flaky', 'Flaky', 'warn', true], ['fails', 'Fails often', 'bad', true],
    ['hollow', 'Hollow', 'warn', false], ['proxy', 'Proxy checks', 'info', false],
    ['issue', 'Has an issue', 'info', false], ['purpose', 'Slow on purpose', 'quiet', false],
    ['runner', 'Runs other test files', 'quiet', false], ['whole', 'Whole suite only', 'quiet', false], ['never', 'Never run', 'quiet', false],
    ['wall', 'Wall only', 'quiet', false]];
  const S = { el: null, ctx: null, d: null, read: null, repo: undefined, filter: 'all', open: new Set(), busy: false,
    sort: null,          // the column the table is sorted by, {key, dir: asc | desc}; null: rows that need a look first, then the highest CPU s
    edits: 'weakened',   // the filter of Test edits by cards: weakened (any count above zero) or all
    query: '', search: null,  // the text of the search box, and the box: the same node from one draw to the next, so it keeps the caret
    held: false, late: false,  // the pointer is pressed in the panel; a snapshot came meanwhile, to draw on its release
    drafts: new Map(),   // the values typed and not yet saved, by dk(key)
    pending: new Map(),  // the values saved here, by dk(key): {key, v, was, at, read}, until a snapshot names them
    refused: null,       // the last refusal: {dk, text}
    keep: null,          // the control to focus after the next draw: {act, file}
    tmodel: new Map(),   // the Tests model picked and not yet saved, by project: {cli, model, effort, other}
    seatSaved: null,     // the Tests model saved here, until a snapshot names it: {repo, value, was, at, read}
    // The action asked for here, by dk(file): {id, action, file, start, state}. State sending from the click until
    // the answer, then running until the snapshot lists its id; refused (with reason) until the next action asked of the file.
    started: new Map(),
    notes: new Map(),    // the row's line of an Optimize or a Mutation check asked here, by dk(file): {what, state: sending | asked | done | refused, text}
    barText: new Set(),  // the ids of the actions whose text is open in the bar
    texts: new Map(),    // each action's text as seen here, by id: the snapshot holds the end of a long one only
    recentOpen: false,   // the Recent actions section is open
    ask: null,           // a preview open: {kind: issue | close | keep | on | many, file, title, body, case, why; many: items [{file, title, body}]}
    stopping: new Set(),    // the ids of the actions a Stop was sent for
    sel: new Set(),      // the files selected, for the bar's actions
    answers: null,       // the bar's last action: {what, kind: act | mutate | issue, pending (sent, no answer yet), lines: [{file, ok, text}], left, note}
    menu: null,          // the file whose More menu is open
    mapSent: null,       // Build the test map, answered yes, until a snapshot names a build begun since: {was: the last build's start then}
    mapRefused: null,    // why the last Build the test map was refused
    edit: new Set(),     // the editors opened from a More menu: `${dk(file)}|mark`
    mutAsked: new Map(), // the files a Mutation check was asked for here, by dk(file): the time asked, until the snapshot names them
    tabs: new Map(),     // the tab open on an opened row, by dk(file): overview (with none), timeline, judge or mutation
    tl: new Map(),       // the filter of an opened row's Timeline, by dk(file): all (with none), runs, optimize, edits or judge
    older: new Map(),    // a file's older runs and test edits, by dk(file), read when its Timeline is opened: {stamp, busy, data, error}
    uid: 0,              // a counter for the ids that tie a row's tabs to their panes
    setEl: null,         // the Test settings panel's body, once drawn
    from: 'tests' };     // the panel whose control was used last (tests or set): its note says what it did

  const num = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : null);
  const list = (v) => (Array.isArray(v) ? v : []);
  const obj = (v) => (v && typeof v === 'object' && !Array.isArray(v) ? v : null);
  const one = (x) => (num(x) === null ? '—' : (Math.round(x * 10) / 10).toFixed(1));
  const pct = (x) => (num(x) === null ? '—' : `${x > 0 ? '+' : ''}${Math.round(x * 100)}%`);
  const tests = () => obj(S.d && S.d.tests);
  const settings = () => obj(tests() && tests().settings) || {};
  const own = (file) => obj(obj(settings().files) && settings().files[file]) || {};
  const rules = () => obj(tests() && tests().rules) || {};
  // A setting's key: slowIssues, mark:<file> (the project's); dk is the key with the project, so a value typed for
  // one project is never sent for another.
  const dk = (key) => `${S.d.repo}|${key}`;
  function inForce(key) {
    const s = settings();
    if (key === 'slowIssues') return s.slowIssues === true ? 'true' : 'false';
    if (key === 'historyStart') return typeof s.historyStart === 'string' ? s.historyStart : '';
    // Auto-file: rules-on (the switch), guard:<guard>, rule:<setting>:<rule name>.
    const said = (v) => (v === undefined || v === null ? '' : String(v));
    if (key === 'rules-on') return rules().on === true ? 'true' : 'false';
    if (key.startsWith('guard:')) return said(rules()[key.slice(6)]);
    if (key.startsWith('rule:')) {
      const at = key.indexOf(':', 5), name = key.slice(at + 1);
      return said((list(rules().list).find((r) => obj(r) && r.name === name) || {})[key.slice(5, at)]);
    }
    return typeof own(key.slice(5)).slowOnPurpose === 'string' ? own(key.slice(5)).slowOnPurpose : '';
  }
  const shown = (key) => (S.pending.has(dk(key)) ? S.pending.get(dk(key)).v : inForce(key));

  // ---- a file's status ----
  function marks(f) {
    const share = num(obj(settings().slower) && settings().slower.share) === null ? 0.25 : settings().slower.share;
    const last = obj(f.lastRun) || {}, runner = f.wholeOnly === true;
    return MARKS.filter(([k]) => ({
      slower: f.slower === true, faster: num(f.change) !== null && f.change <= -share,
      waits: !runner && num(last.clockPerCpu) !== null && last.clockPerCpu > WAITS, flaky: (num(f.flaky) || 0) > 0,
      fails: notCard(f).length >= FAILS, hollow: hollowOf(f).length > 0, proxy: proxyOf(f).length > 0, issue: f.issue !== null && f.issue !== undefined, purpose: !!f.slowOnPurpose,
      // Never run: no run on record at all. A file whose runs are all before the history start has none since it, but
      // it ran (everRun).
      runner, whole: runner, never: !list(f.runs).length && f.everRun !== true, wall: wallOnly(f),
    })[k]);
  }
  const look = (f) => marks(f).some((m) => m[3]);
  // A file is timed when a run of it on record has a CPU time or a clock time; one that is not shows "Not timed yet"
  // and comes last. One with clock times only (its runner's report gives no CPU time) is Wall only: its CPU columns are empty.
  const cpuTimed = (f) => list(f.runs).some((r) => obj(r) && num(r.cpu) !== null);
  const timed = (f) => cpuTimed(f) || list(f.runs).some((r) => obj(r) && num(r.sec) !== null);
  const wallOnly = (f) => !cpuTimed(f) && timed(f);
  // The clock time of a run: "48 s", "8 min 7 s".
  const clockTook = (s) => { if (num(s) === null) return '—'; const r = Math.round(s); return r < 60 ? `${r} s` : `${Math.floor(r / 60)} min ${r % 60} s`; };
  // The table's columns: key, heading, the value a sort by it reads (null sorts last both ways; a file not timed is
  // null in every column but File), and the hint its heading shows on hover and on focus. A first click sorts the file
  // names A to Z and every other column highest first.
  const COLS = [
    ['file', 'File', (f) => f.file, 'The path of the test file. Click a name to see its runs and its actions.'],
    ['cpu', 'CPU s now', (f) => num(f.cpu), 'CPU seconds of its newest timed run.'],
    ['median', 'Median', (f) => num(f.median), 'The median CPU seconds of its runs on record.'],
    ['change', 'Against its median', (f) => num(f.change), 'CPU s now against its median. Above 0% it is slower than usual.'],
    ['runs', 'Last runs', (f) => { const c = list(f.runs).filter(obj).map((r) => num(r.cpu)).filter((x) => x !== null); return c.length ? Math.max(...c) : null; },
      'The CPU seconds of its last runs, oldest first.'],
    ['clock', 'Clock / CPU', (f) => num((obj(f.lastRun) || {}).clockPerCpu), 'Wall time divided by CPU time. Above 2× the file waits more than it works.'],
    ['count', 'Runs', (f) => (list(f.runs).length ? num(f.timedRuns) || 0 : null), 'The runs on record that have a CPU time.'],
    ['took', 'Last run took', (f) => num((obj(f.lastRun) || {}).sec), 'The clock time of its newest run. Point at a time to see when it ran.'],
    ['caught', 'Caught', (f) => num(f.caught), 'The card test steps it failed whose landed change left it as it was: the fix went into the code. Point at a count to see how often it was edited until it passed.'],
    ['mutants', 'Mutants caught', (f) => { const m = mutDone(f); return m ? m.killed / m.of : null; },
      'Its newest mutation check: the mutants (small changes to the code it tests) it caught, of those made. Point at a count to see when the check ran and on which commit.'],
    ['status', 'Status', (f) => (look(f) ? 100 : 0) + marks(f).length, 'What needs a look first, then the other marks of the file.']];

  function say(text) {
    const at = S.from === 'set' && S.setEl ? S.setEl : S.el, n = at && at.querySelector('.tests-note');
    if (n) n.textContent = text;
  }
  function button(text, cls, act, label, fn) {
    const b = S.ctx.h('button', `btn ${cls || ''}`.trim(), text);
    b.type = 'button'; b.dataset.act = act; b.setAttribute('aria-label', label || text);
    b.addEventListener('click', fn);
    return b;
  }
  function row(key, name, what, where, ...kids) {
    const h = S.ctx.h, el = h('div', 'rules-row'), head = h('div', 'rules-key'), box = h('div', 'rules-ctl');
    el.dataset.limit = key;
    head.append(h('span', 'board-label', name), h('span', 'rules-what', what));
    if (where) head.append(h('span', 'tests-where', `Saves to: ${where}`));
    box.append(...kids.filter(Boolean));
    el.append(head, box);
    return el;
  }
  // A section of Test settings: its heading, then where its rows save, said once.
  function section(cls, name, where) {
    const h = S.ctx.h, el = h('section', `tests-set-part ${cls}`);
    el.append(h('h3', 'tests-set-head', name));
    if (where) el.append(h('p', 'tests-where', `Saves to: ${where}`));
    return el;
  }

  // ---- one value: typed or picked, then Save or Cancel ----
  // o: act (the control's name), label, type (number or text) or choices ([value, words]), placeholder, clear (the
  // words of a button that empties it), ask (true: a value that is empty in force is asked for, so an empty draft of it
  // can be saved, to be told what to type), check(v, set) (why it is not sent, or null), send(v, set) ([path, body]) and
  // said(v) (what was saved, in words).
  function setting(key, o) {
    const h = S.ctx.h, k = dk(key), set = shown(key);
    let input;
    if (o.choices) {
      input = h('select', 'field rules-field tests-field');
      o.choices.forEach(([v, t]) => { const op = h('option', null, t); op.value = v; input.append(op); });
    } else {
      input = h('input', `field rules-field tests-field${o.type === 'number' ? ' rules-load' : ''}`);
      input.type = o.type || 'text';
      if (o.type === 'number') { input.min = '1'; input.step = 'any'; } else input.maxLength = REASON_MAX;
      input.placeholder = o.placeholder || '';
    }
    input.value = S.drafts.has(k) ? S.drafts.get(k) : set;
    input.dataset.act = `${o.act}-field`; input.setAttribute('aria-label', o.label);
    const flag = S.ctx.chip('Unsaved', 'warn');
    const unsaved = () => S.drafts.has(k) && (S.drafts.get(k).trim() !== set || (!!o.ask && set === ''));
    const save = button('Save', 'btn-primary', `${o.act}-save`, `Save: ${o.label}`, () => {
      const v = S.drafts.has(k) ? S.drafts.get(k).trim() : null;
      if (v === null) return;
      const why = o.check(v, set);
      if (why) { say(why); return; }
      if (S.busy) { say('Wait: the build machine did not answer the last change yet.'); return; }
      const [path, body] = o.send(v, set);
      S.busy = true; S.refused = null; draw(); say('Sending…');
      S.ctx.post(path, body).then((r) => r.text().then((t) => {
        const at = Number(r.headers && typeof r.headers.get === 'function' ? r.headers.get('X-Answered-At') : NaN);
        return [r.ok, String(t).trim() || `the build machine answered ${r.status}`, Number.isFinite(at) && at > 0 ? at * 1000 : null];
      }), () => [false, 'the build machine did not answer', null]).then(([ok, said, at]) => {
        S.busy = false;
        const saved = o.type === 'number' && v !== '' ? String(Number(v)) : v;
        if (ok) { S.pending.set(k, { key, v: saved, was: inForce(key), at, read: S.read }); S.drafts.delete(k); } else S.refused = { dk: k, text: S.ctx.refusal(said) };
        draw();
        say(ok ? `Saved: ${o.said(saved)}` : `Not saved: ${S.refused.text}`);
      });
    });
    const cancel = button('Cancel', 'btn-quiet', `${o.act}-cancel`, `Cancel: ${o.label}`, () => { S.drafts.delete(k); draw(); });
    function mark() { const on = unsaved(); [flag, save, cancel].forEach((x) => { x.hidden = !on; }); }
    input.addEventListener(o.choices ? 'change' : 'input', () => { S.drafts.set(k, input.value); mark(); });
    const clear = o.clear && (set !== '' || S.drafts.has(k)) ? button(o.clear, 'btn-quiet', `${o.act}-clear`, `${o.clear}: ${o.label}`, () => { S.drafts.set(k, ''); draw(); }) : null;
    mark();
    const out = [input, clear, flag, save, cancel];
    if (S.refused && S.refused.dk === k) {
      const no = h('p', 'rules-refused', `Not saved: ${S.refused.text}`);
      no.setAttribute('role', 'alert');
      out.push(no);
    }
    return out.filter(Boolean);
  }
  const control = (args) => ['control', { action: 'test-settings', args, repo: S.d.repo }];

  // ---- the actions ----
  const ACTS = { judge: 'Judge this test', explain: 'Explain the slowdown', run: 'Run this file now' };
  const FILES_MAX = 20;  // the most files of one action on a list of them, as dashboard_server.py's TEST_FILES_MAX
  const RUNNER_WHY = 'It runs other test files, and each of them is timed on its own.';
  const ENDED = { done: 'Done', stopped: 'Stopped', failed: 'Failed', 'timed out': 'Timed out' };
  const MODEL = /^[A-Za-z0-9][A-Za-z0-9._:/@[\]-]{0,191}$/;  // a model, as dashboard_server.py's MODEL
  const OTHER = '*other';  // the model list's Other…: a name typed in (no model starts with *)
  const ID = /^[0-9a-f]{12}$/;  // an action's id, as `conveyor.sh testaction` prints it
  const SAID_MAX = 300, TITLE_MAX = 200, BODY_MAX = 2500;  // as dashboard_server.py's said_ok and test-issue (TEST_ISSUE_BODY) take them
  const NO_SEAT = 'Set the Tests model first.';
  const WAIT = 'Wait: the build machine did not answer the last change yet.';
  const SENDING = 'sent to the build machine, waiting for its answer.';
  const ta = () => obj(S.d.testActions) || {};
  const ctlTests = () => (obj(S.d.control) ? S.d.control.tests : null);  // the control record's tests: {cli, model, effort}
  const actions = () => list(ta().actions).filter((a) => obj(a) && typeof a.id === 'string');
  const mmss = (s) => { const t = Math.max(0, Math.floor(s)); return `${Math.floor(t / 60)}:${String(t % 60).padStart(2, '0')}`; };
  // The seconds an action may run: its record's limit, else the snapshot's session limit (testActionTimeout). A run of a
  // file is no session: its limit is the test run's (testTimeout), in its record alone; with none it shows no limit.
  const limitOf = (a) => num(a.limit) || (a.action === 'run' ? 0 : num(ta().limit));
  const used = (a) => { const t0 = Date.parse(a.start || ''); return Number.isNaN(t0) ? 0 : Math.max(0, (S.ctx.now() - t0) / 1000); };
  const seatOf = (s) => (obj(s) && typeof s.cli === 'string' && typeof s.model === 'string' ? { cli: s.cli, model: s.model, effort: typeof s.effort === 'string' ? s.effort : null } : null);
  const sameSeat = (a, b) => JSON.stringify(seatOf(a)) === JSON.stringify(seatOf(b));
  // The Tests model in force: the one saved here and not yet in a snapshot, else the snapshot's.
  const tmodel = () => (S.seatSaved && S.seatSaved.repo === S.d.repo ? S.seatSaved.value : seatOf(ctlTests()));
  // A file's hollow cases (#77), [{case, kind, reason}]: those of its newest Judge this test that ended, once one names
  // them (its record's hollow), else those of the engine's cheap check (the snapshot's hollow of the file).
  const hollowOf = (f) => {
    const j = actions().find((a) => a.file === f.file && a.action === 'judge' && a.state === 'done' && Array.isArray(a.hollow));
    return list(j ? j.hollow : f.hollow).filter((x) => obj(x) && typeof x.case === 'string' && typeof x.kind === 'string');
  };
  // A file's proxy checks (#780), [{line, kind: runs | polls, text, why}]: the snapshot's proxy of the file.
  const proxyOf = (f) => list(f.proxy).filter((x) => obj(x) && num(x.line) !== null && (x.kind === 'runs' || x.kind === 'polls'));
  const proxySaid = (x) => `Line ${x.line} ${x.kind === 'runs' ? 'runs another test file or the suite runner' : 'polls a real process'}: `
    + (typeof x.why === 'string' && x.why ? `why: ${x.why}` : 'no comment says why');
  const hollowSaid = (x) => `${x.case} (${x.kind})${typeof x.reason === 'string' && x.reason ? `: ${x.reason}` : ''}`;
  // The judge's newest verdict for a file, when one is kept.
  const verdictOf = (file) => actions().find((a) => a.file === file && a.action === 'judge' && a.state === 'done' && typeof a.verdict === 'string' && a.verdict !== 'no verdict') || null;
  // The causes of its failures (#188) that its newest judge with a verdict named on CAUSE lines: [{case, kind, reason}].
  const causesOf = (file) => { const v = verdictOf(file); return list(v && v.causes).filter((x) => obj(x) && typeof x.case === 'string' && typeof x.kind === 'string'); };
  const causeSaid = (x) => `${x.case} | ${x.kind} | ${typeof x.reason === 'string' ? x.reason : ''}`;

  // ---- its failures (#188): the snapshot's failures, its failed test steps, newest first, each with its verdict ----
  // A failure the card's own change made (verdict card) is the test doing its job: it never counts for Fails often.
  // flaky (it failed, then passed when run again) and main (it failed on main too) do, and so does one with no verdict
  // on record (a step from before verdicts were kept).
  const failsOf = (f) => list(f.failures).filter((x) => obj(x) && (x.verdict === null || ['card', 'main', 'flaky'].includes(x.verdict)));
  // A failure with only its cases of the verdicts vs, by each case's own verdict (caseVerdicts, machine too; a case with
  // none has the step's), and the verdict of those cases (main before flaky before card); null when none has one of vs.
  // A step whose cases' verdicts differ is a catch for its card cases and a failure to fix for the rest. Bug (R323): the
  // step's one verdict (main) hid the card's catch and put its card case under Fix failures.
  const casesOf = (x) => list(x.cases).filter((c) => typeof c === 'string');
  const caseVerdict = (x, c) => (obj(x.caseVerdicts) && typeof x.caseVerdicts[c] === 'string' ? x.caseVerdicts[c] : x.verdict);
  const partOf = (x, vs) => {
    const cs = casesOf(x), mine = cs.filter((c) => vs.includes(caseVerdict(x, c)));
    if (!cs.length) return vs.includes(x.verdict) ? x : null;
    return mine.length ? { ...x, verdict: ['main', 'flaky', 'card'].find((v) => mine.some((c) => caseVerdict(x, c) === v)) || caseVerdict(x, mine[0]), cases: mine } : null;
  };
  // A failure split by its cases' verdicts (main, flaky, card, then the others), so a list puts each case under its own
  // kind. Bug: the step's one verdict put its card case, and a machine case, under the step's kind.
  const partsOf = (x) => (casesOf(x).length ? [...new Set(['main', 'flaky', 'card', ...casesOf(x).map((c) => caseVerdict(x, c))])].map((v) => partOf(x, [v])).filter(Boolean) : [x]);
  const caughtOf = (f) => failsOf(f).map((x) => partOf(x, ['card'])).filter(Boolean);
  const notCard = (f) => failsOf(f).filter((x) => x.verdict !== 'card');
  // The failures Fix failures acts on: those with a cause outside a card's change, with only those cases.
  const fixable = (f) => failsOf(f).map((x) => partOf(x, ['flaky', 'main'])).filter(Boolean);
  const KIND = { flaky: 'flaky', main: 'failed on main too', card: 'caught a card change', machine: 'a build machine fault' };
  const kindSaid = (v) => KIND[v] || 'no verdict on record';
  const casesSaid = (x) => (list(x.cases).filter((c) => typeof c === 'string').join(', ') || 'no case named');
  const plural = (n, one, many) => `${n} ${n === 1 ? one : many}`;
  // Its failures that count for Fails often, by kind, in words: "2 flaky, 1 failed on main too".
  function failKinds(f) {
    const xs = notCard(f), n = (v) => xs.filter((x) => x.verdict === v).length;
    return [[n('flaky'), 'flaky'], [n('main'), 'failed on main too'], [n(null), 'with no verdict on record']].filter(([k]) => k > 0).map(([k, w]) => `${k} ${w}`).join(', ');
  }
  // ---- Whole suite only and Wall only (#190) ----
  // What a wholeOnly file costs: a card's Test step never runs it, so a change to it is tested by a whole-suite run
  // alone, the newest of which on record (the snapshot's suite) gives the CPU seconds.
  const suite = () => obj(tests() && tests().suite);
  function wholeCost() {
    const s = suite(), cpu = s ? num(s.cpu) : null;
    return cpu === null ? 'A change to it is tested only by a whole-suite run, and no whole-suite run with CPU seconds is on record.'
      : `A change to it is tested only by a whole-suite run: ${one(cpu)} CPU s for the newest whole-suite run on record.`;
  }
  // Make it run alone: its title is the one the engine knows the card by (MAKERUN and ALONEFIX, lib/speedproof.sh
  // aloneproof()), and its Done-when is what that check proves.
  const draftAlone = (f) => drafted('Make it run alone', `Make the test file ${f.file} run alone`, f.file,
    ['This test file runs only in whole-suite runs: the pack marks it wholeOnly (test.files in .conveyor/project.json), as it starts other test files and cannot run alone, so a card\'s Test step never runs it.',
      wholeCost(),
      'Make the file run by itself, or move what it runs into test files the runner can list. Keep what it tests. Then remove its wholeOnly mark from the pack.'], [],
    ['- The card\'s check runs the file alone through the pack\'s test list (test.list), and it exits 0. When the change moves its checks into other test files and removes it, the check runs the test files the change adds.',
      '- The pack no longer marks the file wholeOnly.']);
  // Record CPU time on a Wall only file: the engine's plan (the snapshot's settings.cpuTime, cpuplan() of
  // lib/testfiles.sh), {file, was, command} when the pack's test command can be wrapped in conveyor/tools/testtime.sh
  // for this file, else null.
  function cpuPlan(f) {
    const p = obj(settings().cpuTime);
    return p && p.file === f.file && typeof p.command === 'string' && typeof p.was === 'string' ? p : null;
  }
  // Why a Wall only file has no CPU seconds, with its runner (the pack's test.report), and either what Record CPU time
  // does or why no action is shown: the engine's reason, or the file its test command runs in place of this one.
  function wallWhy(f) {
    const r = obj(settings().report), runner = r && typeof r.runner === 'string' && r.runner ? r.runner : null, p = obj(settings().cpuTime);
    const no = runner ? `No CPU time: its runner, ${runner}, gives clock time only in its report (the pack's test.report).`
      : 'No CPU time: its test command gives a TESTRUN sec line with clock time only.';
    if (cpuPlan(f)) return `${no} Record CPU time wraps the test command in conveyor/tools/testtime.sh.`;
    const why = p && typeof p.why === 'string' ? p.why
      : p && typeof p.file === 'string' ? `The wrapper conveyor/tools/testtime.sh applies only to ${p.file}, the one test file the test command runs.`
        : 'Conveyor cannot tell whether a wrapper can give it.';
    return `${no} No action: ${why}`;
  }
  // What ran a run, in words (#130): a whole-suite run with its result, as the Runs list says it, a time the test-speed
  // survey saved (#1036: no card ran it), or the card's issue; never a card's id, nor "card null".
  const runBy = (r) => (r.whole === true ? `whole suite${r.result === 'fail' ? ', failed' : r.result === 'ok' ? ', passed' : ''}`
    : r.survey === true ? 'test-speed survey' : num(r.issue) !== null ? `card #${r.issue}` : 'a card');
  const asking = (kind, file) => S.ask && S.ask.repo === S.d.repo && S.ask.kind === kind && (file === undefined || S.ask.file === file);
  function field(act, label, value, set, o = {}) {
    const x = S.ctx.h(o.area ? 'textarea' : 'input', `field rules-field tests-field${o.area ? ' tests-body' : ''}`);
    if (!o.area) x.type = 'text';
    if (o.area) x.rows = 12;
    x.maxLength = o.max || SAID_MAX; x.value = value; x.placeholder = o.placeholder || '';
    x.dataset.act = act; x.setAttribute('aria-label', label);
    x.addEventListener('input', () => set(x.value));
    return x;
  }
  // The preview open on a row: an issue's title and body, the comment that closes its issue, or the case to keep off.
  function preview(f) {
    const h = S.ctx.h, a = S.ask, file = f.file;
    if (!a || a.repo !== S.d.repo || a.file !== file || a.kind === 'on') return null;
    const el = h('div', 'tests-preview');
    el.dataset.armed = '';
    const cancel = (act) => button('Cancel', 'btn-quiet', act, 'Cancel: send nothing', () => { S.ask = null; draw(); say('Cancelled. Nothing was sent.'); });
    if (a.kind === 'issue') {
      el.append(h('p', 'board-head', 'Preview of the issue. Edit it, then file it.'));
      if (a.verdict) { const v = h('p', 'tests-fact tests-preview-verdict', 'With the judge\'s verdict: '); v.append(verdictChip(a.verdict)); el.append(v); }
      el.append(
        field('issue-title', 'Title of the issue', a.title, (v) => { a.title = v; }, { max: TITLE_MAX }),
        field('issue-body', 'Text of the issue', a.body, (v) => { a.body = v; }, { area: true, max: BODY_MAX }),
        button('File this issue', 'btn-primary', 'issue-file', `File this issue about ${file}`, () => {
          const t = a.title.trim(), b = a.body.trim(), k = dk(file), note = (state, text = '') => S.notes.set(k, { what: a.what || 'Optimize', state, text });
          const why = !t || /[\r\n]/.test(t) ? 'Type a title of one line first.' : !b ? 'Type the text of the issue first.' : S.busy ? WAIT : null;
          if (why) { note('refused', why); draw(); say(why); return; }
          note('sending');
          send('test-issue', [file, t, b], (url) => `Filed: ${url}`, (url) => { S.ask = null; note('done', `Filed: ${url}`); }, (no) => note('refused', no));
        }), cancel('issue-cancel'));
    } else if (a.kind === 'close') {
      el.append(h('p', 'board-head', `Close #${f.issue} as done, with this comment.`),
        field('close-comment', `Comment that closes #${f.issue}`, a.body, (v) => { a.body = v; }),
        button(`Close #${f.issue}`, 'btn-primary', 'close-confirm', `Close #${f.issue} as done`, () => {
          const c = a.body.trim();
          if (!c) { say('Type the comment first.'); return; }
          send('test-close', [String(f.issue), c], () => `Closed #${f.issue} as done.`, () => { S.ask = null; });
        }), cancel('close-cancel'));
    } else if (a.kind === 'keep') {
      el.append(h('p', 'board-head', 'Keep a case of this file off card test steps. The full suite and the whole test on main still run it.'),
        field('keep-case', `Case of ${file} to keep off`, a.case, (v) => { a.case = v; }, { placeholder: 'The name of the case' }),
        field('keep-why', 'Why it is kept off', a.why, (v) => { a.why = v; }, { placeholder: 'Why it is kept off' }),
        button('Keep it off', 'btn-primary', 'keep-confirm', `Keep the case off: ${file}`, () => {
          const c = `${file}: ${a.case.trim()}`, why = a.why.trim();
          if (!a.case.trim() || !why) { say('Type the case and why first.'); return; }
          if (c.length > SAID_MAX) { say(`The file and case are more than ${SAID_MAX} characters.`); return; }
          send('flaky-off', [c, why], () => `Kept off: ${c}.`, () => { S.ask = null; });
        }), cancel('keep-cancel'));
    } else if (a.kind === 'cpu') {
      // Record CPU time (#190): the pack's test command now and as it will be saved; an admin's to save.
      const code = (act, text) => { const c = h('pre', 'tests-cmd', text); c.dataset.act = act; return c; };
      el.append(h('p', 'board-head', 'Record CPU time changes the pack\'s test command (test.command in .conveyor/project.json). Now:'),
        code('cpu-was', a.was), h('p', 'tests-fact', 'Saved as:'), code('cpu-command', a.command),
        h('p', 'tests-fact', `Proof: the next run of ${file} records its CPU seconds, and Wall only clears. Only an admin can save it.`),
        button('Save the test command', 'btn-primary', 'cpu-save', `Record CPU time: save the test command for ${file}`, () => {
          const k = dk(file), note = (state, text = '') => S.notes.set(k, { what: 'Record CPU time', state, text });
          note('sending');
          send('test-settings', ['cpu-time', file], () => 'Saved the test command.', () => { S.ask = null; note('done', 'Saved the test command. The next run records CPU seconds.'); }, (no) => note('refused', no));
        }), cancel('cpu-cancel'));
    }
    return el;
  }
  // The items of an opened row's More menu: act, words, why it is disabled (null: it is not), and what it does.
  function moreItems(f) {
    const file = f.file, runner = f.wholeOnly === true;
    const edit = (what, act) => () => {
      S.edit.add(`${dk(file)}|${what}`);
      if (what === 'mark' && !S.drafts.has(dk(`mark:${file}`))) S.drafts.set(dk(`mark:${file}`), shown(`mark:${file}`));
      S.keep = { act, file }; draw();
    };
    return [
      ['explain', ACTS.explain, null, () => start('explain', file)],  // with no Tests model, its box says so
      ['mutate', 'Mutation check', null, () => mutAsk([file], false)],
      // Split it is a button of the row while it is the step suggested (stepButtons()).
      ...(nextStep(f) === 'split' ? [] : [['split', 'Split it', runner ? SPLIT_RUNNER_WHY : null, () => askSplit(f)]]),
      ['flaky-off', 'Keep a case off', null, () => { S.ask = { kind: 'keep', repo: S.d.repo, file, case: '', why: '' }; S.keep = { act: 'keep-case', file }; draw(); }],
      ['close-done', 'Close its issue as done', num(f.issue) === null ? 'It has no issue to close.' : null, () => {
        const before = num(f.usual) === null ? f.median : f.usual;
        S.ask = { kind: 'close', repo: S.d.repo, file, body: `Done: ${file} used ${one(before)} CPU s before (its usual) and ${one(f.cpu)} CPU s in its last run. Closed from the Board's Tests page.` };
        S.keep = { act: 'close-comment', file }; draw();
      }],
      // A runner (wholeOnly) is never slower than usual, so a slow-on-purpose mark set here would never apply.
      ['menu-mark', 'Mark as slow on purpose', runner ? RUNNER_WHY : null, edit('mark', 'slow-mark-field')]];
  }
  // The More menu of an opened row: a button that opens it, and its items. Arrow keys move between the items, Escape
  // closes it and puts the focus back on More.
  function moreMenu(f) {
    const h = S.ctx.h, file = f.file, on = S.menu === file, wrap = h('span', 'tests-more-menu');
    const b = button('More', 'btn-quiet tests-act', 'more', `More actions: ${file}`, () => {
      const first = moreItems(f).find((x) => !x[2]);  // opened, the focus goes to its first item that is not disabled
      S.menu = on ? null : file; S.keep = { act: on || !first ? 'more' : first[0], file }; draw();
    });
    b.setAttribute('aria-haspopup', 'menu'); b.setAttribute('aria-expanded', String(on));
    wrap.append(b);
    if (!on) return wrap;
    const m = h('div', 'tests-menu');
    m.setAttribute('role', 'menu'); m.setAttribute('aria-label', `More actions: ${file}`);
    // An item that is off stays in the arrow keys' round (aria-disabled, not disabled) and its reason is its
    // description, a line under the menu: a title alone is out of a keyboard user's reach.
    const whys = [];
    moreItems(f).forEach(([act, words, why, fn]) => {
      const i = button(words, 'btn-quiet', act, `${words}: ${file}`, () => { if (why) return; S.menu = null; fn(); });
      i.setAttribute('role', 'menuitem');
      if (why) {
        const p = h('p', 'tests-fact tests-menu-why', `${words}: ${why}`);
        p.id = `tests-menu-why-${act}`;
        i.setAttribute('aria-disabled', 'true'); i.setAttribute('aria-describedby', p.id); i.title = why;
        whys.push(p);
      }
      m.append(i);
    });
    m.addEventListener('keydown', (e) => {
      const items = Array.from(m.querySelectorAll('[role="menuitem"]')), at = items.indexOf(document.activeElement);
      if (e.key === 'Escape') { e.preventDefault(); S.menu = null; S.keep = { act: 'more', file }; draw(); return; }
      const step = e.key === 'ArrowDown' ? 1 : e.key === 'ArrowUp' ? -1 : 0;
      if (step && items.length) { e.preventDefault(); items[(at + step + items.length) % items.length].focus(); }
    });
    wrap.append(m, ...whys);
    return wrap;
  }
  // The line of an Optimize or a Mutation check asked on a row, beside its buttons: sending, refused with why, the
  // issue filed, or the check's state now (queued, running, ended).
  function noteLine(f) {
    const h = S.ctx.h, n = S.notes.get(dk(f.file));
    if (!n) return null;
    const el = h('p', 'tests-fact tests-note-line');
    el.append(h('span', 'board-label', `${n.what}: `));
    if (n.state === 'sending') el.append(progress(`Sending: ${n.what}`), h('span', 'board-from', SENDING));
    else if (n.state === 'refused') el.append(h('span', 'tests-refused', `Not done: ${n.text}`));
    else if (n.state === 'asked') el.append(...mutNow(f));
    else el.append(h('span', null, n.text));
    return el;
  }
  const askSplit = (f) => askIssue(draftSplit, f);
  // What an action that makes a card does on a click (askIssue()): preview its issue, or, with the rule Tests page
  // issues off, start its card with no issue.
  const asks = () => (noIssue() ? 'start a card with no GitHub issue about' : 'preview an issue about');
  // The next step a row suggests (#130), from its state, its judge's verdict and its Optimize issues: run a file that
  // has no CPU time to judge, or that runs other test files; judge a file that needs a look and has no verdict; else
  // run it. No test file has a CPU budget (#349), so no step follows from one. A verdict indirect (#778) asks for the
  // rewrite as direct checks first, and a verdict split (#768) for Split it, except on a runner (wholeOnly): its card's
  // check (speedproof.sh optproof()) times the file alone, and a card's Test step never runs a runner alone, so Make it run alone
  // comes first; a runner is not split.
  function nextStep(f) {
    if (f.wholeOnly === true) return 'run';
    const v = verdictOf(f.file);
    if (v && v.verdict === 'indirect') return 'rewrite-direct';
    if (v && v.verdict === 'split') return 'split';
    if (!cpuTimed(f)) return 'run';
    return look(f) && !verdictOf(f.file) ? 'judge' : 'run';
  }
  // The buttons of an opened row: Judge, Optimize (Optimize again once one landed), Fix failures (with failures no
  // card's change caused), Fix hollow cases (Hollow), Fix the waiting (Waits), Make it run and Delete it (Never run),
  // Rewrite as a direct check (the verdict indirect), Split it (the verdict split), Run and More; the next step suggested is the primary one.
  function stepButtons(f) {
    const h = S.ctx.h, file = f.file, now = h('div', 'tests-act-row tests-steps'), noSeat = !tmodel(), next = nextStep(f);
    const btn = (key, text, act, label, fn) => button(text, `${key === next ? 'btn-primary' : 'btn-quiet'} tests-act`, act, label, fn);
    const judge = btn('judge', 'Judge', 'judge', `${ACTS.judge}: ${file}`, () => start('judge', file));
    if (noSeat) judge.title = NO_SEAT;
    // A runner (wholeOnly): its time is its files' time, so no issue asks to optimize it.
    const again = optsOf(f).some((o) => o.state === 'landed');
    const opt = btn('optimize', again ? 'Optimize again' : 'Optimize', 'optimize', `Optimize: ${asks()} ${file}`, () => {
      if (f.wholeOnly === true) { S.notes.set(dk(file), { what: 'Optimize', state: 'refused', text: RUNNER_WHY }); draw(); return; }
      askIssue(draftIssue, f);
    });
    if (f.wholeOnly === true) opt.title = RUNNER_WHY;
    // Fix failures (#188), on a file with failures no card's change caused: the same preview as Optimize, of a Fix
    // failures issue (draftFix()).
    const fix = fixable(f).length ? btn('fix', 'Fix failures', 'fix-failures', `Fix failures: ${asks()} ${file}`, () => askIssue(draftFix, f)) : null;
    // The other fix issues (#189), each on a file with its status: the same preview, of its own draft.
    const has = (k) => marks(f).some((m) => m[0] === k);
    const fixes = [[has('hollow'), 'Fix hollow cases', 'fix-hollow', draftHollow], [has('waits'), 'Fix the waiting', 'fix-waits', draftWaits],
      [has('never'), 'Make it run', 'make-run', draftRun], [has('never'), 'Delete it', 'delete-file', draftDelete], [f.wholeOnly === true, 'Make it run alone', 'make-alone', draftAlone],
      [next === 'rewrite-direct', 'Rewrite as a direct check', 'rewrite-direct', draftDirect], [next === 'split', 'Split it', 'split', draftSplit]]
      .filter(([on]) => on).map(([, text, act, draft]) => btn(act, text, act, `${text}: ${asks()} ${file}`, () => askIssue(draft, f)));
    // Record CPU time (#190), on a Wall only file whose test command the engine can wrap: the change, shown first.
    const plan = wallOnly(f) ? cpuPlan(f) : null;
    if (plan) fixes.push(btn('record-cpu', 'Record CPU time', 'record-cpu', `Record CPU time: preview the change to the test command for ${file}`, () => {
      S.notes.delete(dk(file)); S.ask = { kind: 'cpu', repo: S.d.repo, file, was: plan.was, command: plan.command }; S.keep = { act: 'cpu-save', file }; draw();
    }));
    now.append(judge, opt, ...(fix ? [fix] : []), ...fixes, btn('run', 'Run', 'run', `${ACTS.run}: ${file}`, () => start('run', file)), moreMenu(f));
    if (noSeat) now.append(h('span', 'tests-why', `Judge and Explain: ${NO_SEAT}`));
    return now;
  }
  // An ended judge shows on the Judge tab; the box of any other action of the row on its Overview.
  const judged = (a) => a.action === 'judge' && !live(a) && a.state !== 'sending' && a.state !== 'refused';
  // The rest of an opened row's actions, under its buttons: the box of its action and the line of its Optimize or
  // Mutation check, then the preview open on it. One that cannot start says why in its box or line.
  function rowActions(f) {
    const h = S.ctx.h, file = f.file, el = h('div', 'tests-acts');
    const a = rowAction(file), n = noteLine(f);
    if (a && !judged(a)) el.append(box(a, f));
    if (n) el.append(n);
    // A flaky case is kept off until its flaky issue closes: Put back closes it. A case shows on each file it counts for
    // (the snapshot's files: a runner's case on its case file too).
    list(S.d.flaky).filter((c) => obj(c) && typeof c.case === 'string' && c.case.includes(': ') && list(c.files).includes(file)).forEach((c) => {
      const name = c.case.slice(c.case.indexOf(': ') + 2), line = h('p', 'tests-fact tests-flaky', `Kept off as flaky: ${name} `);
      const b = button(`Put back a flaky case: ${name}`, 'btn-quiet', 'flaky-back', `Put back the flaky case ${c.case}`, () => send('test-close',
        [String(c.issue), `Put back from the Board's Tests page: the case "${name}" runs on card test steps again.`.slice(0, SAID_MAX)], () => `Put back: ${c.case}. Its flaky issue #${c.issue} is closed.`));
      if (num(c.issue) === null) { b.disabled = true; b.title = 'It has no flaky issue to close. It stays off until its entries are 30 days old.'; }
      line.append(b);
      el.append(line);
    });
    // A file recorded flaky twice within the flaky days, after its earlier fix (flakyAgain: that fix's issue).
    if (num(f.flakyAgain) !== null) el.append(h('p', 'tests-fact tests-flaky', `Flaky again since its fix #${f.flakyAgain}`));
    const p = preview(f);
    if (p) el.append(p);
    return el.childNodes.length ? el : null;
  }
  const anyIssueUrl = (files) => files.flatMap((x) => list(x.runs)).map((r) => obj(r) && r.url).find((u) => typeof u === 'string' && ISSUE_URL.test(u)) || null;
  // The action and file of the control that has the focus in one of the panels, or null.
  function focusedAction(els) {
    const a = document.activeElement && els.some((x) => x.contains(document.activeElement)) && document.activeElement.dataset ? document.activeElement : null;
    return a && a.dataset.act ? { act: a.dataset.act, file: (a.closest('[data-file]') || { dataset: {} }).dataset.file } : null;
  }
  // Both panels, each that is drawn (only: tests or set, the one panel); then the control focused before, or the one
  // asked for (S.keep), has the focus again.
  function draw(only) {
    if (S.ctx.picking()) return;  // Show at every project: the page shows the project choice, a reply that came back draws no project over it
    const els = [S.el, S.setEl].filter(Boolean);
    const keep = S.keep || focusedAction(els);
    S.keep = null;
    if (S.el && only !== 'set') drawTests();
    if (S.setEl && only !== 'tests') drawSet();
    if (!keep) return;
    const scope = keep.file ? els.flatMap((x) => Array.from(x.querySelectorAll('[data-file]'))).filter((x) => x.dataset.file === keep.file) : els;
    const again = scope.map((x) => x.querySelector(`[data-act="${keep.act}"]`)).find(Boolean);
    if (again && !again.disabled) {
      again.focus({ preventScroll: true });
      // Asked (Optimize with this verdict, #130): the page scrolls to the preview, and the cursor is at the start of its body.
      if (keep.scroll) {
        const to = again.closest('.tests-preview') || again;
        if (typeof to.scrollIntoView === 'function') to.scrollIntoView({ block: 'start' });
        if (typeof again.setSelectionRange === 'function') again.setSelectionRange(0, 0);
      }
    }
  }

  // A value saved here stands until a snapshot names it, or until one begun at or after the Save was answered (with no
  // time, the next one) names a value other than the one it replaced: a change saved since from elsewhere then shows.
  // The live feed republishes the record it last read, so one still naming the replaced value never ends it.
  // Both panels draw from the one part: the first to get a snapshot takes it into S and draws both; the other, given
  // the same snapshot, draws only itself.
  const render = (which) => (el, d, ctx) => {
    const read = typeof ctx.updatedAt === 'function' ? ctx.updatedAt() : null;
    const view = ctx.project(d);
    ctx.title(Array.isArray(view.repos) && view.repos.length > 1 && view.repo ? `${which === 'set' ? 'Test settings' : 'Tests'}: ${view.repo}` : null);
    if (which === 'set') S.setEl = el; else S.el = el;
    if (S.raw === d && S.read === read && S.repo === view.repo) {
      if (S.held) { S.late = true; return; }
      draw(which);
      return;
    }
    take(d, view, read, ctx);
    if (S.held) { S.late = true; return; }
    draw();
  };
  function take(d, view, read, ctx) {
    if (S.repo !== undefined && view.repo !== S.repo) {
      S.open.clear(); S.filter = 'all'; S.query = ''; S.refused = null; S.ask = null;
      S.sel.clear(); S.answers = null; S.menu = null; S.edit.clear(); S.mapSent = null; S.mapRefused = null;
    }
    Object.assign(S, { raw: d, ctx, d: view, read, repo: view.repo });
    if (view.repo !== null) {
      redraft();
      const after = (p) => read !== null && (p.at !== null && p.at !== undefined ? read >= p.at : read !== p.read);
      S.pending.forEach((p, k) => {
        if (k !== dk(p.key)) return;  // another project's
        if (p.v === inForce(p.key) || (after(p) && inForce(p.key) !== p.was)) S.pending.delete(k);
      });
      // The Tests model saved here, until a snapshot names it (or, after the answer, names one other than the one it replaced).
      const ss = S.seatSaved;
      if (ss && ss.repo === view.repo && (sameSeat(ctlTests(), ss.value) || (after(ss) && !sameSeat(ctlTests(), ss.was)))) S.seatSaved = null;
      // Each action's text joined to what was seen of it; an action asked for here leaves its place once listed.
      actions().forEach((a) => { if (typeof a.text === 'string') S.texts.set(a.id, a.textCut === true ? merge(S.texts.get(a.id) || '', a.text) : a.text); });
      // One refused stays until the next action asked of its file; one sending with no POST in flight lost its answer
      // (another project was shown when it came).
      S.started.forEach((s, k) => {
        if ((s.state === 'sending' && !S.busy) || (s.state === 'running' && (!s.id || actions().some((a) => a.id === s.id)))) S.started.delete(k);
      });
      S.notes.forEach((n, k) => { if (n.state === 'sending' && !S.busy) S.notes.delete(k); });
      S.stopping.forEach((id) => { if (!actions().some((a) => a.id === id && live(a))) S.stopping.delete(id); });
    }
  }
  // The panel is drawn whole. A button drawn anew between its press and its release lost the click (the browser gives
  // it to the element pressed, then gone): a row did not open, an action did not start. So a snapshot that comes while
  // the pointer is pressed in the panel is drawn after the release, once its click has run.
  document.addEventListener('pointerdown', (e) => { S.held = [S.el, S.setEl].some((x) => x && x.contains(e.target)); }, true);
  const release = () => {
    if (!S.held) return;
    S.held = false;
    if (S.late) { S.late = false; setTimeout(draw, 0); }
  };
  document.addEventListener('pointerup', release, true);
  document.addEventListener('pointercancel', release, true);
  window.addEventListener('blur', release);
  // What the parts of this file hold (parts/tests-*.js; boot.js loads them before the panels): each is given what
  // it uses from here and from the parts before it, and gives back what the others use.
  const shared = { NEVER, PACK, CONTROL, MARKS, S, num, list, obj, one, pct, tests, settings, rules, dk, inForce,
    shown, marks, look, timed, wallOnly, clockTook, COLS, say, button, row, section, setting, control, ACTS,
    FILES_MAX, RUNNER_WHY, ENDED, MODEL, OTHER, ID, BODY_MAX, TITLE_MAX, NO_SEAT, WAIT, SENDING, ta, ctlTests,
    actions, mmss, limitOf, used, seatOf, tmodel, hollowOf, proxyOf, proxySaid, hollowSaid, verdictOf, causesOf,
    causeSaid, failsOf, caughtOf, partsOf, notCard, fixable, kindSaid, casesSaid, plural, failKinds, wholeCost, wallWhy,
    runBy, asking, field, stepButtons, judged, rowActions, anyIssueUrl, draw };
  Object.assign(shared, window.DASH_APP.use('tests-mutation', shared));
  Object.assign(shared, window.DASH_APP.use('tests-actions', shared));
  Object.assign(shared, window.DASH_APP.use('tests-rows', shared));
  const { mutDone, mutAsk, progress, mutNow, send, merge, start, verdictChip, live, box, rowAction, draftIssue,
    draftFix, drafted, draftHollow, draftWaits, draftRun, draftDirect, draftSplit, SPLIT_RUNNER_WHY, draftDelete,
    noIssue, askIssue, redraft, optsOf, ISSUE_URL, drawSet, drawTests } = shared;

  window.DASH_APP.panel({
    id: PART,
    title: 'Tests',
    size: 'full',
    tab: 'tests',  // a tab of its own
    rows: 'all',
    rowSelector: '.tests-row, .rules-row, .rules-stat',
    isEmpty: (d) => d.repo === null && !(d.others && typeof d.others === 'object' && Object.keys(d.others).length),
    empty(el, ctx) { el.append(ctx.state('empty', 'No tests to show', 'Conveyor did not run on this project on the build machine yet, so it has no test figures. Start Conveyor there, and they show here.')); },
    error(el, message, ctx) { el.append(ctx.state('error', 'The Board could not read the tests', message)); },
    render: render('tests'),
    // A value saved here waits for a snapshot begun after its answer, though the part be the same as the last.
    same(el, d, ctx) {
      const read = typeof ctx.updatedAt === 'function' ? ctx.updatedAt() : null;
      if (S.pending.size && read !== S.read) render('tests')(el, d, ctx);
    },
  });
  // Test settings (#1088): the Tests tab's settings, a panel of their own after the Tests panel, from the same part.
  window.DASH_APP.panel({
    id: `${PART}-settings`,
    title: 'Test settings',
    size: 'full',
    tab: 'tests',
    part: PART,
    rows: 'all',
    rowSelector: '.rules-row',
    isEmpty: (d) => d.repo === null && !(d.others && typeof d.others === 'object' && Object.keys(d.others).length),
    empty(el, ctx) { el.append(ctx.state('empty', 'No test settings to show', 'Conveyor did not run on this project on the build machine yet, so it has no test settings. Start Conveyor there, and they show here.')); },
    error(el, message, ctx) { el.append(ctx.state('error', 'The Board could not read the test settings', message)); },
    render: render('set'),
    same(el, d, ctx) {
      const read = typeof ctx.updatedAt === 'function' ? ctx.updatedAt() : null;
      if (S.pending.size && read !== S.read) render('set')(el, d, ctx);
    },
  });
}());
