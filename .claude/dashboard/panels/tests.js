// SPDX-License-Identifier: Apache-2.0
// The Tests page (#520; the owner chose mockup A, with mockup B's column "against its own median"): a tab of its own,
// after Rules. It shows one project at a time: with more than one on the host, the machine head's Show picks it, as
// on the Rules tab, and the heading names it ("Tests: sample").
// The page, top to bottom (#73, #74, #178): the Test map part, the figures, the table with its search and filters, Test edits by cards (#76),
// Removed by Optimize, the bar of the files selected, Recent actions, and one section "Settings", collapsed until
// opened, with the Tests model, Test limits and Auto-file.
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
// the rows whose path holds its text (any case); filter chips, each with its count, show one status alone; the two
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
// Fix the waiting, Make it run, Delete it (#189), Make it run alone and Record CPU time (#190), Run and More, the next step suggested,
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
// The other fix issues (#189), each a button of an opened row's actions with the preview Optimize opens, and a title
// the engine knows its card by: Fix hollow cases on a Hollow file (its HOLLOW lines; a deleted case is named on a
// COVERED-BY line), Fix the waiting on a file that Waits (the clock and CPU of its recent runs, and the WAIT lines its
// newest judge named, the snapshot's waits), and Make it run and Delete it on a file Never run, whose row says why
// it did not run when the engine can tell (the snapshot's neverRun). Each Done-when is what the card's check proves.
// #190: a wholeOnly file's status says what a change to it costs (the snapshot's suite: the newest whole-suite run's
// CPU seconds), and Make it run alone files the issue aloneproof() checks; a Wall only file's status names its runner
// (the pack's test.report) and, by the engine's plan (the snapshot's settings.cpuTime), either has Record CPU time,
// which previews the pack's test command wrapped in conveyor/tools/testtime.sh before an admin saves it
// (`conveyor.sh test-settings cpu-time <file>`), or says why no action is shown (wallWhy()).
// Mutation checks (#79): the column Mutants caught ("14 / 20": its newest done check, empty before one; when it ran and
// on which commit on hover; "queued", "running" or "paused" beside it); an opened row's check state (queued with its
// place, running with mutant n of m, paused, failed or done) and surviving mutants (source and line, before and after,
// "tests still passed"). Mutation check, in More and in the bar, is one POST control {action: mutate, args: [file...]}
// (`conveyor.sh mutate ask`: the front of the idle queue; no check starts while a card needs a test slot, and the bar
// says so). Optimize's preview lists the survivors; a landed Optimize shows the mutants caught before and after.
// Its More menu holds Explain the slowdown, Mutation check, Keep a case off, Close its issue as done and Mark as slow on purpose (it asks for the reason).
// Settings, Test limits. Each row names where it saves: Load limit in the host file (this machine, all
// projects; moved from the Rules tab's Machine section, #462, with the same behaviour), and in the pack file (this
// project): the files slow on purpose (a list), and, only when the snapshot names them, the hard box of each test file (settings.box: {on}) and "Take a
// file off card runs" (settings.slowIssues, #457).
// Every value is typed or picked first: the row says Unsaved, with Save and Cancel, as on the Rules tab, and only Save
// sends it: POST machine {action: load, value} for the Load limit, POST control {action: test-settings, args, repo}
// (`conveyor.sh test-settings`) for a pack setting. A value saved shows until a snapshot names it, or one begun after
// the answer names a value other than the one it replaced. A refused one keeps the value in force, with the refusal
// in its row.
// A project with no file times shows its step figures and one state, "No file times for this project", with what
// starts the record, and no table.
// The actions (#521, #73). The Board calls the control record's tests (`conveyor.sh control tests`) "the Tests
// model": its strip-down test (dashboard.test.sh) keeps the engine's retired word for it out of the page. Judge (Judge
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
// machine ({maxLoad, unread, cores, load}), testActions ({limit, actions, allowed:
// the pack's models by CLI, offered for a CLI that lists none}), control (the control record: its tests, the Tests model),
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
  const LOAD = /^[0-9]{1,6}(\.[0-9]{1,3})?$/;  // a load limit, as dashboard_server.py's LOAD and `conveyor.sh machine load` take it (1 or more)
  const REASON_MAX = 300;  // a reason, as dashboard_server.py's said_ok takes it
  const WAITS = 2;         // a file waits more than it works when its last run took more than this times its CPU time
  const FAILS = 2;         // a file fails often when this many test steps or more failed in it, not counting those a card's own change made fail (failsOf())
  const NEVER = 20;        // a file with this many runs on record or more and no catch shows "Never caught anything"
  const HOST = 'Host file: this machine, all projects';
  const PACK = 'Pack file: this project';
  // The status chips, in the order of the filters: key, words, tone, whether a row with it needs a look.
  const MARKS = [
    ['slower', 'Slower than usual', 'warn', true], ['faster', 'Faster', 'ok', false],
    ['waits', 'Waits', 'info', true], ['flaky', 'Flaky', 'warn', true], ['fails', 'Fails often', 'bad', true],
    ['hollow', 'Hollow', 'warn', false],
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
    settingsOpen: false };  // the Settings section is open

  const num = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : null);
  const list = (v) => (Array.isArray(v) ? v : []);
  const obj = (v) => (v && typeof v === 'object' && !Array.isArray(v) ? v : null);
  const one = (x) => (num(x) === null ? '—' : (Math.round(x * 10) / 10).toFixed(1));
  const pct = (x) => (num(x) === null ? '—' : `${x > 0 ? '+' : ''}${Math.round(x * 100)}%`);
  const tests = () => obj(S.d && S.d.tests);
  const settings = () => obj(tests() && tests().settings) || {};
  const own = (file) => obj(obj(settings().files) && settings().files[file]) || {};
  const rules = () => obj(tests() && tests().rules) || {};
  // A setting's key: load (the machine's), slowIssues, mark:<file> (the project's); dk is
  // the key with the project, so a value typed for one project is never sent for another.
  const dk = (key) => (key === 'load' ? key : `${S.d.repo}|${key}`);
  function inForce(key) {
    const m = obj(S.d.machine) || {}, s = settings();
    if (key === 'load') return num(m.maxLoad) === null ? '' : String(m.maxLoad);
    if (key === 'slowIssues') return s.slowIssues === true ? 'true' : 'false';
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
      fails: notCard(f).length >= FAILS, hollow: hollowOf(f).length > 0, issue: f.issue !== null && f.issue !== undefined, purpose: !!f.slowOnPurpose,
      runner, whole: runner, never: !list(f.runs).length, wall: wallOnly(f),
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

  function say(text) { const n = S.el && S.el.querySelector('.tests-note'); if (n) n.textContent = text; }
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
  const caughtOf = (f) => failsOf(f).filter((x) => x.verdict === 'card');
  const notCard = (f) => failsOf(f).filter((x) => x.verdict !== 'card');
  // The failures Fix failures acts on: those with a cause outside a card's change.
  const fixable = (f) => failsOf(f).filter((x) => x.verdict === 'flaky' || x.verdict === 'main');
  const KIND = { flaky: 'flaky', main: 'failed on main too', card: 'caught a card change' };
  const kindSaid = (v) => KIND[v] || 'no verdict on record';
  const casesSaid = (x) => (list(x.cases).filter((c) => typeof c === 'string').join(', ') || 'no case named');
  const plural = (n, one, many) => `${n} ${n === 1 ? one : many}`;
  // Its failures that count for Fails often, by kind, in words: "2 flaky, 1 failed on main too".
  function failKinds(f) {
    const xs = notCard(f), n = (v) => xs.filter((x) => x.verdict === v).length;
    return [[n('flaky'), 'flaky'], [n('main'), 'failed on main too'], [n(null), 'with no verdict on record']].filter(([k]) => k > 0).map(([k, w]) => `${k} ${w}`).join(', ');
  }

  // ---- mutation checks (#79): the snapshot's mutation (a file's newest check) and mutationPlace (its place in the asked list) ----
  const MUT_WHY = 'A check starts only when no card needs a test slot.';
  const mutOf = (f) => obj(f.mutation);
  // Its newest check, when it ended done with a mutant or more.
  const mutDone = (f) => { const m = mutOf(f); return m && m.state === 'done' && num(m.killed) !== null && num(m.of) ? m : null; };
  // The mutants of its newest check that its tests did not catch.
  const survivors = (f) => list((mutOf(f) || {}).survived).filter((x) => obj(x) && typeof x.source === 'string' && num(x.line) !== null);
  const trimmed = (s) => String(typeof s === 'string' ? s : '').replace(/\p{C}/gu, ' ').trim();
  // Its place in the asked list (1 first); 0 when it was asked here and the snapshot does not name it yet; null when
  // not queued. A file asked here leaves that state when the snapshot names its place, or a check of it began after.
  function mutQueued(f) {
    const k = dk(f.file), t = S.mutAsked.get(k), m = mutOf(f);
    if (num(f.mutationPlace) !== null) { S.mutAsked.delete(k); return f.mutationPlace; }
    if (t === undefined) return null;
    if (m && Date.parse(m.at) >= t) { S.mutAsked.delete(k); return null; }
    return 0;
  }
  // The state of its check, in words: running (mutant n of m), queued (its place), paused, failed, done, or none.
  function mutState(f) {
    const m = mutOf(f), q = mutQueued(f), of = m ? num(m.of) || 0 : 0, tried = m ? num(m.tried) || 0 : 0;
    const why = m && typeof m.reason === 'string' ? m.reason : '';
    if (m && m.state === 'running') return of ? `Running: mutant ${Math.min(tried + 1, of)} of ${of}.` : 'Running: it makes its mutants.';
    if (q !== null) return `Queued${q ? `: place ${q} in the idle queue, ${q - 1} ahead` : ''}. ${MUT_WHY}`;
    if (!m) return 'No check yet. Mutation check, in More, puts it at the front of the idle queue.';
    if (m.state === 'stopped') return `Paused${/\bcard\b|test slot/.test(why) ? ' for a card' : ''}: ${why || 'no reason recorded'}. It goes on from mutant ${Math.min(tried + 1, of)} of ${of} later.`;
    if (m.state === 'failed') return `Failed: ${why || 'no reason recorded'}.`;
    return `Done ${S.ctx.when(m.end || m.at)}: ${num(m.killed) || 0} of ${of} mutants caught.`;
  }
  // The column's text: its newest done check's "caught / made", and what its check does now.
  function mutCell(f) {
    const d = mutDone(f), m = mutOf(f), q = mutQueued(f);
    const now = m && m.state === 'running' ? 'running' : q !== null ? 'queued' : m && m.state === 'stopped' ? 'paused' : '';
    return [d ? `${d.killed} / ${d.of}` : '', now].filter(Boolean).join(' · ');
  }
  // A survivor in a line of text: its source and line, its kind and its change.
  const survivorSaid = (x) => `${x.source}:${x.line}${typeof x.kind === 'string' ? ` (${x.kind})` : ''}: \`${trimmed(x.before)}\` → \`${trimmed(x.after)}\``;
  // A Mutation check asked for files: one POST, `conveyor.sh mutate ask`, which puts them at the front of the idle
  // queue; their rows show them queued. inBar: the bar's action, whose answer shows in the bar.
  // Not inBar: the row's (one file), whose state shows on its row's line (S.notes).
  function mutAsk(files, inBar) {
    const what = 'Mutation check', kind = 'mutate';
    const note = (state, text = '') => { if (!inBar) S.notes.set(dk(files[0]), { what, state, text }); };
    if (files.length > FILES_MAX) { S.answers = { what, kind, lines: [], left: [], note: `At most ${FILES_MAX} files at a time: ${files.length} are selected. Select fewer.` }; draw(); return; }
    if (S.busy) { if (inBar) S.answers = { what, kind, lines: [], left: [], note: WAIT }; else note('refused', WAIT); draw(); return; }
    const at = S.ctx.now();
    if (inBar) S.answers = { what, kind, pending: true, lines: [], left: [], note: null }; else note('sending');
    send('mutate', files, () => `Mutation check queued: ${files.length} ${files.length === 1 ? 'file' : 'files'} at the front of the idle queue. ${MUT_WHY}`, (text) => {
      files.forEach((file) => S.mutAsked.set(dk(file), at));
      if (inBar) S.answers = { what, kind, lines: files.map((file) => ({ file, ok: true, text: 'queued' })), left: [], note: null, said: text.replace(/^conveyor: /, '') };
      else note('asked');
    }, (why) => { if (inBar) S.answers = { what, kind, lines: files.map((file) => ({ file, ok: false, text: why })), left: [], note: null }; else note('refused', why); });
  }
  // A bar of progress: value of max, or with no max one that shows only that it goes on.
  function progress(label, value, max) {
    const b = S.ctx.h('progress', 'tests-progress');
    if (max) { b.max = max; b.value = Math.min(value, max); }
    b.setAttribute('aria-label', label);
    return b;
  }
  // A file's mutation check now, as a bar and words: running, its mutants tried of all and the time since it began;
  // queued, a bar that goes on; else its state alone.
  function mutNow(f) {
    const h = S.ctx.h, m = mutOf(f), q = mutQueued(f), out = [];
    let text = mutState(f);
    if (m && m.state === 'running') {
      out.push(progress(`Mutation check: ${f.file}`, num(m.tried) || 0, num(m.of) || 0));
      const t0 = Date.parse(m.at || '');
      if (!Number.isNaN(t0)) text += ` ${mmss((S.ctx.now() - t0) / 1000)} so far.`;
    } else if (q !== null) out.push(progress(`Mutation check: ${f.file}`));
    out.push(h('span', null, text));
    return out;
  }

  const actBtn = (text, act, label, fn) => button(text, 'btn-quiet tests-act', act, label, fn);
  // One action sent: POST control {action, args, repo}; then(text, at) on a yes, no(refusal) on a no, and the answer or
  // the refusal said.
  function send(action, args, said, then, no) {
    if (S.busy) { say(WAIT); return; }
    const repo = S.d.repo;
    S.busy = true; draw(); say('Sending…');
    S.ctx.post('control', { action, args, repo }).then((r) => r.text().then((t) => {
      const at = Number(r.headers && typeof r.headers.get === 'function' ? r.headers.get('X-Answered-At') : NaN);
      return [r.ok, String(t).trim() || `the build machine answered ${r.status}`, Number.isFinite(at) && at > 0 ? at * 1000 : null];
    }), () => [false, 'the build machine did not answer', null]).then(([ok, text, at]) => {
      S.busy = false;
      if (ok && then && repo === S.d.repo) then(text, at);
      if (!ok && no && repo === S.d.repo) no(S.ctx.refusal(text));
      draw();
      say(ok ? said(text) : `Not done: ${S.ctx.refusal(text)}`);
    });
  }
  // The text of an action as seen here, with the snapshot's text added: a whole text replaces it; the end of a long
  // one (textCut) is joined to it where the two meet, so the text seen before stays.
  function merge(was, t) {
    if (!t || !was) return t || was;
    const head = t.slice(0, 64);
    for (let p = was.indexOf(head, Math.max(0, was.length - t.length)); p >= 0; p = was.indexOf(head, p + 1)) if (t.startsWith(was.slice(p))) return was.slice(0, p) + t;
    for (let k = Math.min(head.length - 1, was.length); k > 0; k -= 1) if (was.endsWith(t.slice(0, k))) return was + t.slice(k);
    return `${was}\n[…]\n${t}`;
  }
  function copy(text) {
    const clip = window.navigator.clipboard;
    (clip && clip.writeText ? clip.writeText(text) : Promise.reject(new Error('no clipboard')))
      .then(() => say('Copied.'), () => say('Not copied: the browser gave no clipboard.'));
  }
  // An action of a row: its box shows at once, beside its buttons: sending until the build machine answers, then
  // running (or why it was refused); one that cannot be sent says why there.
  function start(how, file) {
    const k = dk(file), now = () => new Date(S.ctx.now()).toISOString();
    const why = how !== 'run' && !tmodel() ? NO_SEAT : S.busy ? WAIT : null;
    S.open.add(file);
    if (why) { S.started.set(k, { id: '', action: how, file, state: 'refused', reason: why }); draw(); say(`Not started: ${why}`); return; }
    S.started.set(k, { id: '', action: how, file, start: now(), state: 'sending' });
    send('testaction', [how, file], () => `Started: ${ACTS[how]}, ${file}.`, (text) => {
      const id = text.split('\n').pop().trim();
      S.started.set(k, { id: ID.test(id) ? id : '', action: how, file, start: now(), state: 'running' });
    }, (reason) => S.started.set(k, { id: '', action: how, file, state: 'refused', reason }));
  }
  const stop = (a) => send('testaction', ['stop', a.id], (t) => `Stop sent: ${ACTS[a.action] || a.action}, ${a.file}. ${t}`, () => S.stopping.add(a.id));
  const verdictChip = (v) => S.ctx.chip(v, v === 'keep' ? 'ok' : v === 'no verdict' ? 'quiet' : 'warn');
  // How an action ended: its state and time, when, its CLI, model and effort (a run has none), and its verdict (unless
  // its box shows it on the verdict line: chip false) or result.
  function result(a, chip = true) {
    const h = S.ctx.h, t0 = Date.parse(a.start || ''), t1 = Date.parse(a.end || '');
    const took = Number.isNaN(t0) || Number.isNaN(t1) ? '' : ` in ${mmss((t1 - t0) / 1000)}`;
    const out = [h('span', 'tests-result', `${ENDED[a.state] || String(a.state)}${took} · ${S.ctx.when(a.end || a.start)} · ${a.action === 'run' ? 'engine command, no session' : `${a.cli} · ${a.model} · ${a.effort}`}`)];
    if (chip && a.action === 'judge' && typeof a.verdict === 'string') out.push(verdictChip(a.verdict));
    if (a.action === 'run' && typeof a.result === 'string') {  // the run's result: fail, or its other value
      const bad = a.result === 'fail';
      out.push(S.ctx.chip(`${bad ? 'Failed' : 'Passed'}${num(a.cpu) !== null ? `, ${one(a.cpu)} CPU s` : ''}`, bad ? 'bad' : 'ok'));
    }
    if (typeof a.reason === 'string' && a.reason) out.push(h('span', 'board-from', a.reason));
    return out;
  }
  const running = (a) => a.state === 'running';
  const queued = (a) => a.state === 'queued';
  const live = (a) => running(a) || queued(a);
  // A queued action waits for a free place; the engine starts them in the order asked.
  const ahead = (a) => actions().filter((x) => queued(x) && x.id !== a.id && String(x.asked || '') < String(a.asked || '')).length;
  const queuedSaid = (a) => `Queued, ${ahead(a)} ahead`;
  // An action now, as a bar and words: queued, how many wait before it; running, the time used (against its limit);
  // ended, its result.
  function actNow(a, chip = true) {
    const h = S.ctx.h, name = ACTS[a.action] || String(a.action);
    if (queued(a)) return [progress(`Waiting: ${name}`), h('span', 'board-from', queuedSaid(a))];
    if (!running(a)) return result(a, chip);
    const lim = limitOf(a), u = used(a);
    return [progress(`Time used: ${name}`, u, lim), h('span', 'board-from', lim ? `Running: ${mmss(u)} of the ${mmss(lim)} time limit` : `Running: ${mmss(u)} used`)];
  }
  // The text of a judge or explain action as formatted text (#74): paragraphs, **bold**, `code`, lists ("- ", "* ",
  // "1. ") and ``` code blocks. It builds nodes and never sets HTML from the text: any other markup shows as typed.
  function inline(s) {
    const h = S.ctx.h, out = [], re = /\*\*(\S(?:[^*\n]*?\S)?)\*\*|`([^`\n]+)`/g;
    let at = 0, m;
    while ((m = re.exec(s))) {
      if (m.index > at) out.push(document.createTextNode(s.slice(at, m.index)));
      if (m[1] !== undefined) { const b = h('strong'); b.append(...inline(m[1])); out.push(b); } else out.push(h('code', null, m[2]));
      at = re.lastIndex;
    }
    if (at < s.length) out.push(document.createTextNode(s.slice(at)));
    return out;
  }
  function md(text) {
    const h = S.ctx.h, el = h('div', 'tests-md'), lines = String(text).replace(/\r\n?/g, '\n').split('\n');
    let para = [], ul = null;
    const flush = () => {
      if (!para.length) return;
      const p = h('p');
      para.forEach((l, i) => { if (i) p.append(h('br')); p.append(...inline(l)); });
      el.append(p); para = [];
    };
    for (let i = 0; i < lines.length; i += 1) {
      const l = lines[i], item = /^\s*([-*]|(\d{1,4})[.)])\s+(.*)$/.exec(l);
      if (/^\s*```/.test(l)) {
        flush(); ul = null;
        const code = [];
        for (i += 1; i < lines.length && !/^\s*```/.test(lines[i]); i += 1) code.push(lines[i]);
        const pre = h('pre', 'tests-md-code');
        pre.append(h('code', null, code.join('\n')));
        el.append(pre);
      } else if (item) {
        flush();
        const kind = item[2] === undefined ? 'ul' : 'ol';
        if (!ul || ul.tagName.toLowerCase() !== kind) {
          ul = h(kind); el.append(ul);
          if (kind === 'ol' && Number(item[2]) !== 1) ul.start = Number(item[2]);
        }
        const li = h('li'); li.append(...inline(item[3])); ul.append(li);
      } else if (!l.trim()) { flush(); ul = null; } else if (ul && /^\s+\S/.test(l)) {
        ul.lastChild.append(document.createTextNode(' '), ...inline(l.trim()));  // a list item's next line
      } else { ul = null; para.push(l.trim()); }
    }
    flush();
    return el;
  }
  // The verdicts that Optimize acts on: each is one of the fixes an Optimize card picks; stabilise (#188) is Fix
  // failures' (draftFix()).
  const ACTIONABLE = ['speed up', 'split', 'merge', 'delete', 'stabilise'];
  // A judge's text without its last line when that is its VERDICT line (as lib/testaction.sh reads it): the verdict
  // line above the text says it once (#130). Copy still copies the text as written.
  const unverdict = (text) => {
    const lines = String(text).replace(/\s+$/, '').split('\n');
    return /^[\s*`_>-]*VERDICT:/i.test(lines[lines.length - 1]) ? lines.slice(0, -1).join('\n') : text;
  };
  // The judge's reason in one line (#130): the first sentence of its text that is not a heading, a list's title, a
  // HOLLOW or the VERDICT line, without its markup; cut to 160 characters.
  function reasonOf(text) {
    const l = String(text || '').split('\n').map((x) => x.replace(/\*\*|`/g, '').replace(/^\s*(?:#+|[-*]|\d{1,4}[.)])\s*/, '').trim())
      .find((x) => x.split(/\s+/).length > 3 && !/:$/.test(x) && !/^(VERDICT|HOLLOW):/i.test(x));
    if (!l) return '';
    const s = (/^(.+?[.!?])(\s|$)/.exec(l) || [null, l])[1];
    return s.length > 160 ? `${s.slice(0, 159)}…` : s;
  }
  // The box of one action: running, a bar and the time used against its limit, its text so far, Stop and Copy;
  // queued, how many wait before it, and Stop; ended, its result (a judge's verdict line first, with Optimize with this
  // verdict when Optimize acts on it), its text (formatted, but a run's output) and Copy.
  function box(a, f) {
    const h = S.ctx.h, el = h('div', 'tests-box'), head = h('div', 'tests-box-head'), name = ACTS[a.action] || String(a.action);
    el.dataset.id = a.id;
    head.append(h('span', 'board-label', name));
    if (a.state === 'sending') head.append(progress(`Sending: ${name}`), h('span', 'board-from', `Starting: ${SENDING}`));
    if (a.state === 'refused') head.append(h('span', 'tests-refused', `Not started: ${a.reason}`));
    if (a.state === 'sending' || a.state === 'refused') { el.append(head); return el; }
    const text = S.texts.get(a.id) || '', btns = h('div', 'tests-box-btns'), parts = [head];
    if (live(a) && ID.test(a.id)) btns.append(button(S.stopping.has(a.id) ? 'Stopping…' : 'Stop', 'btn-quiet', 'stop', `Stop: ${name}, ${a.file}`, () => stop(a)));
    head.append(...actNow(a, false));
    if (queued(a)) {
      el.append(head, btns);
      return el;
    }
    if (!running(a) && a.action === 'judge' && typeof a.verdict === 'string') {
      const line = h('p', 'tests-verdict', 'Verdict: ');
      line.append(verdictChip(a.verdict));
      if (ACTIONABLE.includes(a.verdict)) {
        // The preview is on the Overview tab: it opens there, scrolled to, with the cursor in its body (#130).
        const fix = a.verdict === 'stabilise';
        const b = button('Optimize with this verdict', 'btn-quiet tests-act', 'optimize-verdict', `${fix ? 'Fix failures' : 'Optimize'} ${a.file}: preview an issue with this verdict`, () => {
          S.ask = fix ? draftFix(f, a) : draftIssue(f, a); S.tabs.set(dk(f.file), 'overview'); S.keep = { act: 'issue-body', file: f.file, scroll: true }; draw();
        });
        // A runner's time is its files' time, so no Optimize; its failures are its own, so Fix failures holds.
        if (f.wholeOnly === true && !fix) { b.disabled = true; b.title = RUNNER_WHY; }
        line.append(' ', b);
      }
      parts.push(line);
    }
    let out;
    if (running(a) || a.action === 'run') {
      out = h('pre', 'tests-out', text || (running(a) ? 'Started. Its text shows here as it comes.' : 'No text.'));
      out.setAttribute('aria-live', 'polite');
    } else out = text ? md(a.action === 'judge' ? unverdict(text) : text) : h('p', 'board-from', 'No text.');
    btns.append(button('Copy', 'btn-quiet', 'copy', `Copy the text: ${name}, ${a.file}`, () => copy(text)));
    el.append(...parts, out, btns);
    if (a.textCut === true && !text) el.append(h('p', 'board-from', 'The text is long: the build machine sends its end only.'));
    return el;
  }
  // The action a row's box shows: the one started here until the snapshot lists it, else the file's newest.
  const rowAction = (file) => S.started.get(dk(file)) || actions().find((a) => a.file === file) || null;
  // An Optimize issue's draft: the title the engine knows it by (OPTIMIZE, lib/testrun.sh), the measured numbers, and
  // a judge's verdict (the one given, else the file's newest kept) with as much of the end of its text as the body
  // holds. Each line is printable (the server refuses a body with a tab or another control character in a line).
  function draftIssue(f, given) {
    const file = f.file, v = given || verdictOf(file), runs = list(f.runs).filter(obj), last = obj(f.lastRun) || {};
    const lines = ['Optimize this test file: speed it up, split it, merge it into another test file, or delete it. Keep what it tests.', '', 'What the Board measured:',
      `- CPU s in its last run: ${one(f.cpu)}`,
      `- Median of its runs: ${one(f.median)} CPU s (${pct(f.change)} against its median)`,
      `- Clock / CPU in its last run: ${num(last.clockPerCpu) === null ? '—' : `${one(last.clockPerCpu)}×`}`,
      `- Runs on record: ${num(f.timedRuns) || 0}. Test steps that failed in it: ${num(f.failedSteps) || 0}. Flaky entries: ${num(f.flaky) || 0}.`,
      `- Last runs, newest first: ${runs.map((r) => `${one(r.cpu)} CPU s (${runBy(r)})`).join(', ') || 'none'}`];
    // A list of items under its heading: as many as the body holds with room for a line that counts the rest.
    const add = (head, items, said) => {
      if (!items.length) return;
      lines.push('', head);
      const at = items.findIndex((x) => { const l = `- ${said(x)}`.replace(/\p{C}/gu, ' '); if (lines.join('\n').length + l.length + 40 > BODY_MAX) return true; lines.push(l); return false; });
      if (at >= 0) lines.push(`- and ${items.length - at} more`);
    };
    // Its hollow cases, and the mutants its tests did not catch (#79), so the card fixes them too.
    add('Hollow cases (they prove nothing): fix each one or delete it.', hollowOf(f), hollowSaid);
    add('Surviving mutants (the code it tests was changed, and its tests still passed): add the assertions that catch each one.', survivors(f), survivorSaid);
    if (v) {
      lines.push('', `The judge's verdict (${v.end || v.start}, ${v.cli} · ${v.model} · ${v.effort}): ${v.verdict}.`);
      const text = (S.texts.get(v.id) || '').split('\n').map((l) => l.replace(/[\p{C}\p{Z}]/gu, ' ').trimEnd()).join('\n').trim();
      const room = BODY_MAX - lines.join('\n').length - 40, chars = Array.from(text);
      if (text && room > 0) lines.push('', 'The end of its text:', chars.length > room ? `…${chars.slice(-room).join('')}` : text);
    }
    return { kind: 'issue', repo: S.d.repo, file, title: `Optimize the test file ${file}`, body: lines.join('\n'), verdict: v ? v.verdict : null };
  }
  // A Fix failures issue's draft (#188): the title the engine knows it by (FIXFAILS, lib/testrun.sh), what to do, its
  // failures that no card's change caused (flaky or main) with their failing cases, the cause lines of a judge (the one
  // given, else the file's newest with a verdict), the end of each failure's output as far as the body holds, and the
  // Done-when that the card's check (steadyproof()) holds it to. Each line is printable, as in draftIssue().
  function draftFix(f, given) {
    const file = f.file, v = given || verdictOf(file), xs = fixable(f), line = (l) => l.replace(/\p{C}/gu, ' ').trimEnd();
    const names = [...new Set(xs.flatMap((x) => list(x.cases).filter((c) => typeof c === 'string')))];
    const causes = list(v && v.causes).filter((x) => obj(x) && typeof x.case === 'string' && typeof x.kind === 'string');
    const done = ['', 'Done when:', names.length
      ? line(`- The cases that failed (${names.slice(0, 10).join(', ')}${names.length > 10 ? ` and ${names.length - 10} more` : ''}) succeed in 10 runs in a row of this file alone on a test slot.`)
      : '- The file succeeds in 10 runs in a row alone on a test slot.',
    `- ${names.length ? 'They succeed' : 'It succeeds'} in a run beside the other files of the suite.`];
    const head = ['Make this test file succeed reliably, and keep what it tests. Fix the cause of its failures, in the test or in the code it tests; do not delete, skip or weaken a case so that it succeeds.',
      '', 'Its failures that no card\'s change caused, newest first (flaky: it failed, then passed when run again; failed on main too: it failed on main as well):'];
    // A list of items: as many as the body holds with the Done-when, with room for a line that counts the rest.
    const add = (items, said) => {
      const at = items.findIndex((x) => { const l = line(said(x)); if (head.concat(l, done).join('\n').length + 40 > BODY_MAX) return true; head.push(l); return false; });
      if (at >= 0) head.push(`- and ${items.length - at} more`);
    };
    add(xs, (x) => `- ${x.time}, card ${num(x.issue) ? `#${x.issue}` : x.card}: ${kindSaid(x.verdict)}. Failing cases: ${casesSaid(x)}.`);
    if (causes.length) { head.push('', 'The causes the judge named:'); add(causes, (x) => `- CAUSE: ${causeSaid(x)}`); }
    // The end of each failure's output, newest first, while the body holds it; the last one cut to its end.
    const tails = [];
    let room = BODY_MAX - head.concat(done).join('\n').length - 40;
    for (const x of xs.filter((y) => typeof y.tail === 'string' && y.tail.trim())) {
      const top = `The end of the output of card ${num(x.issue) ? `#${x.issue}` : x.card} (${x.time}):`, text = x.tail.split('\n').map(line).join('\n').trim();
      const need = top.length + text.length + 2;
      if (room < top.length + 40) break;
      if (need <= room) { tails.push('', top, text); room -= need; continue; }
      tails.push('', top, `…${Array.from(text).slice(-(room - top.length - 3)).join('')}`);
      break;
    }
    return { kind: 'issue', what: 'Fix failures', repo: S.d.repo, file, title: `Fix the failures of the test file ${file}`, body: head.concat(tails, done).join('\n'), verdict: v && v.verdict === 'stabilise' ? v.verdict : null };
  }
  // ---- the other fix issues (#189): Fix hollow cases, Fix the waiting, Make it run and Delete it ----
  // Each draft's title is the one the engine knows its card by (HOLLOWFIX, WAITFIX, MAKERUN and DELFILE,
  // lib/testrun.sh), and its Done-when is how the card's check proves it fixed. A list is cut, as in draftFix(), so the
  // body with its Done-when fits BODY_MAX, with a line that counts the rest; each line is printable.
  const printable = (l) => l.replace(/\p{C}/gu, ' ').trimEnd();
  function drafted(what, title, file, head, lists, done) {
    const lines = head.map(printable);
    lists.forEach(([top, items, said]) => {
      if (!items.length) { if (top) lines.push('', top); return; }
      lines.push('', top);
      const at = items.findIndex((x) => { const l = printable(said(x)); if (lines.concat(l, '', done).join('\n').length + 40 > BODY_MAX) return true; lines.push(l); return false; });
      if (at >= 0) lines.push(`- and ${items.length - at} more`);
    });
    return { kind: 'issue', what, repo: S.d.repo, file, title, body: lines.concat('', 'Done when:', done).join('\n'), verdict: null };
  }
  // Its waits (#189): the WAIT lines its newest judge named (the snapshot's waits), [{case, kind, at, reason}].
  const waitsOf = (f) => list(f.waits).filter((x) => obj(x) && typeof x.case === 'string' && typeof x.kind === 'string');
  const waitSaid = (x) => `${x.case} | ${x.kind} | ${typeof x.at === 'string' ? x.at : ''} | ${typeof x.reason === 'string' ? x.reason : ''}`;
  // Why it never ran, when the engine can tell (the snapshot's neverRun: {kind, reason}), else null.
  const neverWhy = (f) => (obj(f.neverRun) && typeof f.neverRun.reason === 'string' && f.neverRun.reason ? f.neverRun.reason : null);
  // Fix hollow cases: each hollow case (hollowOf()) as a HOLLOW line the card's check reads (hollowproof()).
  const draftHollow = (f) => drafted('Fix hollow cases', `Fix the hollow cases of the test file ${f.file}`, f.file,
    ['Make each hollow case of this test file prove something: a hollow case succeeds without proving anything. Make each case below assert the behaviour it names.',
      'Or delete a case when another test already proves that behaviour, and name that test in your reply, on a line of its own: COVERED-BY: <test file>: <its case> | <the deleted case>.'],
    [['Its hollow cases (case | kind | reason):', hollowOf(f), (x) => `- HOLLOW: ${x.case} | ${x.kind} | ${typeof x.reason === 'string' && x.reason.trim() ? x.reason : 'no reason given'}`]],
    ['- The judge\'s hollow check of the changed file, run by the card\'s check on a model of another family than the builder\'s where one is set up, names no hollow case.',
      '- Each deleted case has its COVERED-BY line, naming a test file that is kept.']);
  // Fix the waiting: the clock and CPU seconds of its recent runs, and the waits its judge named.
  function draftWaits(f) {
    const last = obj(f.lastRun) || {}, runs = list(f.runs).filter((r) => obj(r) && num(r.sec) !== null && num(r.cpu));
    const w = waitsOf(f);
    return drafted('Fix the waiting', `Fix the waiting of the test file ${f.file}`, f.file,
      [`This test file waits more than it works: its last run took ${num(last.clockPerCpu) === null ? 'more than 2' : one(last.clockPerCpu)} times its CPU seconds on the clock. Remove or shorten its waits, and keep what its cases test: do not cut a wait so that a case no longer checks what it waited for.`],
      [['Its recent runs, newest first (clock, CPU):', runs, (r) => `- ${one(r.sec)} s on the clock for ${one(r.cpu)} CPU s (${one(r.sec / r.cpu)}×), ${runBy(r)}`],
        [w.length ? 'The waits the judge named (case | kind | file:line | reason):' : 'The judge has named no wait of it yet: find the waits in the file (sleep, polling, timeout, lock, network).', w, (x) => `- WAIT: ${waitSaid(x)}`]],
      ['- The file succeeds in 3 runs in a row alone on a test slot, and each run takes at most 2 times its CPU seconds on the clock.']);
  }
  // Make it run and Delete it, on a file that never ran: why, when the engine can tell.
  const neverSaid = (f) => `This test file has never run: no card's test step and no whole-suite run has a run of it on record. ${neverWhy(f) ? `Why, as the engine can tell: ${neverWhy(f)}.` : 'The engine cannot tell why.'}`;
  const draftRun = (f) => drafted('Make it run', `Make the test file ${f.file} run`, f.file,
    [neverSaid(f), 'Make the test command run it (or the pack\'s tests.patterns match it), or fix what stops it loading or skips it. Keep what it tests.'], [],
    ['- The card\'s test step runs this file, and it succeeds.']);
  const draftDelete = (f) => drafted('Delete it', `Delete the test file ${f.file}`, f.file,
    [neverSaid(f), 'Delete it. For each of its cases that matters, name the test that already proves its behaviour, on a line of its own: COVERED-BY: <test file>: <its case>. When no other test proves a case that matters, make the file run instead.'], [],
    ['- The file is deleted, and each of its cases that matters has a COVERED-BY line naming a test that proves it.']);
  // ---- Whole suite only and Wall only (#190) ----
  // What a wholeOnly file costs: a card's Test step never runs it, so a change to it is tested by a whole-suite run
  // alone, the newest of which on record (the snapshot's suite) gives the CPU seconds.
  const suite = () => obj(tests() && tests().suite);
  function wholeCost() {
    const s = suite(), cpu = s ? num(s.cpu) : null;
    return cpu === null ? 'A change to it is tested only by a whole-suite run, and no whole-suite run with CPU seconds is on record.'
      : `A change to it is tested only by a whole-suite run: ${one(cpu)} CPU s for the newest whole-suite run on record.`;
  }
  // Make it run alone: its title is the one the engine knows the card by (MAKERUN and ALONEFIX, lib/testrun.sh
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
  // What ran a run, in words (#130): a whole-suite run with its result, as the Runs list says it, or the card's issue;
  // never a card's id, nor "card null".
  const runBy = (r) => (r.whole === true ? `whole suite${r.result === 'fail' ? ', failed' : r.result === 'ok' ? ', passed' : ''}`
    : num(r.issue) !== null ? `card #${r.issue}` : 'a card');
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
    const el = h('div', 'tests-preview'), cancel = (act) => button('Cancel', 'btn-quiet', act, 'Cancel: send nothing', () => { S.ask = null; draw(); say('Cancelled. Nothing was sent.'); });
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
    moreItems(f).forEach(([act, words, why, fn]) => {
      const i = button(words, 'btn-quiet', act, `${words}: ${file}`, () => { S.menu = null; fn(); });
      i.setAttribute('role', 'menuitem');
      if (why) { i.disabled = true; i.title = why; }
      m.append(i);
    });
    m.addEventListener('keydown', (e) => {
      const items = Array.from(m.querySelectorAll('[role="menuitem"]:not(:disabled)')), at = items.indexOf(document.activeElement);
      if (e.key === 'Escape') { e.preventDefault(); S.menu = null; S.keep = { act: 'more', file }; draw(); return; }
      const step = e.key === 'ArrowDown' ? 1 : e.key === 'ArrowUp' ? -1 : 0;
      if (step && items.length) { e.preventDefault(); items[(at + step + items.length) % items.length].focus(); }
    });
    wrap.append(m);
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
  // The next step a row suggests (#130), from its state, its judge's verdict and its Optimize issues: run a file that
  // has no CPU time to judge, or that runs other test files; judge a file that needs a look and has no verdict; else
  // run it. No test file has a CPU budget (#349), so no step follows from one.
  function nextStep(f) {
    if (f.wholeOnly === true || !cpuTimed(f)) return 'run';
    return look(f) && !verdictOf(f.file) ? 'judge' : 'run';
  }
  // The buttons of an opened row: Judge, Optimize (Optimize again once one landed), Fix failures (with failures no
  // card's change caused), Fix hollow cases (Hollow), Fix the waiting (Waits), Make it run and Delete it (Never run),
  // Run and More; the next step suggested is the primary one.
  function stepButtons(f) {
    const h = S.ctx.h, file = f.file, now = h('div', 'tests-act-row tests-steps'), noSeat = !tmodel(), next = nextStep(f);
    const btn = (key, text, act, label, fn) => button(text, `${key === next ? 'btn-primary' : 'btn-quiet'} tests-act`, act, label, fn);
    const judge = btn('judge', 'Judge', 'judge', `${ACTS.judge}: ${file}`, () => start('judge', file));
    if (noSeat) judge.title = NO_SEAT;
    // A runner (wholeOnly): its time is its files' time, so no issue asks to optimize it.
    const again = optsOf(f).some((o) => o.state === 'landed');
    const opt = btn('optimize', again ? 'Optimize again' : 'Optimize', 'optimize', `Optimize: preview an issue about ${file}`, () => {
      if (f.wholeOnly === true) { S.notes.set(dk(file), { what: 'Optimize', state: 'refused', text: RUNNER_WHY }); draw(); return; }
      S.notes.delete(dk(file)); S.ask = draftIssue(f); S.keep = { act: 'issue-title', file }; draw();
    });
    if (f.wholeOnly === true) opt.title = RUNNER_WHY;
    // Fix failures (#188), on a file with failures no card's change caused: the same preview as Optimize, of a Fix
    // failures issue (draftFix()).
    const fix = fixable(f).length ? btn('fix', 'Fix failures', 'fix-failures', `Fix failures: preview an issue about ${file}`, () => {
      S.notes.delete(dk(file)); S.ask = draftFix(f); S.keep = { act: 'issue-title', file }; draw();
    }) : null;
    // The other fix issues (#189), each on a file with its status: the same preview, of its own draft.
    const has = (k) => marks(f).some((m) => m[0] === k);
    const fixes = [[has('hollow'), 'Fix hollow cases', 'fix-hollow', draftHollow], [has('waits'), 'Fix the waiting', 'fix-waits', draftWaits],
      [has('never'), 'Make it run', 'make-run', draftRun], [has('never'), 'Delete it', 'delete-file', draftDelete], [f.wholeOnly === true, 'Make it run alone', 'make-alone', draftAlone]]
      .filter(([on]) => on).map(([, text, act, draft]) => btn(act, text, act, `${text}: preview an issue about ${file}`, () => {
        S.notes.delete(dk(file)); S.ask = draft(f); S.keep = { act: 'issue-title', file }; draw();
      }));
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
    const p = preview(f);
    if (p) el.append(p);
    return el.childNodes.length ? el : null;
  }

  // ---- the Tests model: CLI, model (Other… for a typed name) and effort, as the Rules tab's roles ----
  function seatCtl() {
    const h = S.ctx.h, repo = S.d.repo, clis = obj(S.d.clis) || {}, inForce = tmodel();
    const set = { cli: inForce ? inForce.cli : '', model: inForce ? inForce.model : '', effort: inForce && inForce.effort ? inForce.effort : '' };
    const v = S.tmodel.get(repo) || Object.assign({ other: false }, set);
    const of = v.cli ? obj(clis[v.cli]) : null;
    // An installed CLI offers its own models, or, when it lists none (Claude Code), the pack's models for it
    // (testActions.allowed), as the Rules tab's roles do; then Other… for a name typed in.
    const listed = list(!of ? null : Array.isArray(of.models) ? of.models : (obj(ta().allowed) || {})[v.cli]).filter((m) => typeof m === 'string' && m);
    const typed = !!v.cli && (v.other || (v.model !== '' && !listed.includes(v.model)) || !listed.length);
    const unsaved = () => { const d = S.tmodel.get(repo); return !!d && (d.cli !== set.cli || d.model.trim() !== set.model || d.effort !== set.effort); };
    const edit = (o) => {
      const d = Object.assign({}, S.tmodel.get(repo) || v, o);
      if (d.cli === set.cli && d.model.trim() === set.model && d.effort === set.effort && !d.other) S.tmodel.delete(repo); else S.tmodel.set(repo, d);
      draw();
    };
    const select = (act, label, opts, value, fn) => {
      const s = h('select', 'field board-select');
      opts.forEach(([x, t]) => { const o = h('option', null, t); o.value = x; o.selected = x === value; s.append(o); });
      s.dataset.act = act; s.setAttribute('aria-label', label);
      s.addEventListener('change', () => fn(s.value));
      return s;
    };
    const cli = select('tmodel-cli', 'Tests model: CLI', [['', 'Default (none)']].concat(Object.keys(clis).map((c) => [c, c])), v.cli,
      (x) => edit({ cli: x, model: '', effort: '', other: false }));
    const model = select('tmodel-model', 'Tests model: model', v.cli ? [['', 'Pick a model']].concat(listed.map((m) => [m, m]), [[OTHER, 'Other…']]) : [['', 'No model']],
      typed ? OTHER : v.model, (x) => (x === OTHER ? edit({ other: true, model: listed.includes(v.model) ? '' : v.model }) : edit({ model: x, other: false })));
    model.disabled = !v.cli;
    const out = [cli, model];
    if (typed) {
      out.push(field('tmodel-model-other', 'Tests model: model, not listed', v.model, (x) => { S.tmodel.set(repo, Object.assign({}, S.tmodel.get(repo) || v, { model: x, other: true })); mark(); },
        { placeholder: `a ${v.cli} model`, max: 192 }));
    }
    const effort = select('tmodel-effort', 'Tests model: effort', [['', 'Default effort']].concat(list(of && of.efforts).filter((e) => typeof e === 'string').map((e) => [e, e])), v.effort, (x) => edit({ effort: x }));
    effort.disabled = !v.cli;
    const flag = S.ctx.chip('Unsaved', 'warn');
    const save = button('Save', 'btn-primary', 'tmodel-save', 'Save the Tests model: CLI, model and effort', () => {
      const d = S.tmodel.get(repo);
      if (!d) return;
      const m = d.model.trim();
      if (d.cli && !m) { say('Pick a model first.'); return; }
      if (d.cli && !MODEL.test(m)) { say('A model is one word of letters, digits and . _ : / @ [ ] -, starting with a letter or a digit.'); return; }
      const args = d.cli ? [d.cli, m].concat(d.effort ? [d.effort] : []) : ['default'];
      send('tests', args, () => `Saved: the Tests model is now ${d.cli ? `${d.cli} · ${m} · ${d.effort || 'default effort'}` : 'not set'}.`, (t, at) => {
        S.tmodel.delete(repo);
        S.seatSaved = { repo, value: d.cli ? { cli: d.cli, model: m, effort: d.effort || null } : null, was: seatOf(ctlTests()), at, read: S.read };
      });
    });
    const cancel = button('Cancel', 'btn-quiet', 'tmodel-cancel', 'Put the Tests model back as it is in force', () => { S.tmodel.delete(repo); draw(); });
    function mark() { const on = unsaved(); [flag, save, cancel].forEach((x) => { x.hidden = !on; }); }
    mark();
    out.push(effort, flag, save, cancel, h('span', 'board-from', `In force: ${inForce ? `${inForce.cli} · ${inForce.model} · ${inForce.effort || 'default effort'}` : 'none'}`));
    return out;
  }
  function actionsHead() {
    const h = S.ctx.h, el = h('section', 'tests-actions');
    el.append(h('h3', 'board-head', 'Test actions'),
      row('tmodel', 'Model for Tests actions', 'The CLI, model and effort of Judge and Explain the slowdown. Run needs none.', null, ...seatCtl()));
    return el;
  }

  // ---- the bar of the files selected: Judge, Optimize, Run and Clear, and the answer for each file ----
  // The files an action of the bar acts on, in the table's order, and those it leaves out with why.
  function chosen(files, how) {
    const out = { files: [], left: [] };
    files.filter((f) => S.sel.has(f.file)).forEach((f) => {
      const why = how === 'judge' && !tmodel() ? NO_SEAT : how === 'optimize' && f.wholeOnly === true ? RUNNER_WHY : null;
      if (why) out.left.push({ file: f.file, why }); else out.files.push(f);
    });
    return out;
  }
  // One answer a file: the server answers {results: [{file, id} or {file, refused}]} for a list of files, and the text
  // of the one action (its id or address on the last line) for a single file.
  function answersOf(files, text) {
    let r = null;
    try { r = JSON.parse(text); } catch (e) { r = null; }
    if (obj(r) && Array.isArray(r.results)) {
      return r.results.filter(obj).map((x) => (typeof x.id === 'string' ? { file: String(x.file), ok: true, text: x.id } : { file: String(x.file), ok: false, text: String(x.refused || 'refused') }));
    }
    const last = String(text).split('\n').pop().trim();
    return files.map((file) => ({ file, ok: true, text: last }));
  }
  // An action of the bar on its files: Judge or Run (testaction, then each action started shows on its row as one
  // started there does) or the issues of Optimize (test-issue). The bar says it is sent at once; then each file's
  // answer (an action started shows its state there until it ends, then its result), and those left out, show in it.
  function bulk(what, action, args, files, left, done) {
    const kind = action === 'testaction' ? 'act' : 'issue';
    if (files.length > FILES_MAX) { S.answers = { what, kind, lines: [], left, note: `At most ${FILES_MAX} files at a time: ${files.length} are selected. Select fewer.` }; draw(); return; }
    if (S.busy) { S.answers = { what, kind, lines: [], left, note: WAIT }; draw(); return; }
    S.answers = { what, kind, pending: true, lines: [], left, note: null };
    send(action, args, (t) => { const a = answersOf(files, t); return `${what}: ${a.filter((x) => x.ok).length} of ${a.length} taken.`; }, (t) => {
      const lines = answersOf(files, t);
      S.answers = { what, kind, lines, left, note: null };
      if (done) done(lines);
    }, (why) => { S.answers = { what, kind, lines: files.map((file) => ({ file, ok: false, text: why })), left, note: null }; });
  }
  // A line of the bar's answer: an action started, its state now (its record, else as started here) and, once it
  // ended, its text to open; a Mutation check, its file's check now; else what the build machine answered.
  function answerLine(a, l, files) {
    const h = S.ctx.h, li = h('li', l.ok ? null : 'tests-refused'), f = files.find((x) => x.file === l.file);
    li.dataset.file = l.file;
    const s = S.started.get(dk(l.file)), x = a.kind === 'act' && l.ok ? actions().find((y) => y.id === l.text) || (s && s.id === l.text ? s : null) : null;
    if (x) {
      li.append(`${l.file}: ${a.what}: `, ...actNow(x));
      const text = S.texts.get(x.id) || '';
      if (!live(x) && text) {
        const d = h('details', 'tests-bar-text');
        d.open = S.barText.has(x.id);
        d.addEventListener('toggle', () => { if (d.open) S.barText.add(x.id); else S.barText.delete(x.id); });
        d.append(h('summary', null, 'Its text'), x.action === 'run' ? h('pre', 'tests-out', text) : md(text));
        li.append(d);
      }
    } else if (a.kind === 'mutate' && l.ok && f) li.append(`${l.file}: ${a.what}: `, ...mutNow(f));
    else li.textContent = `${l.file}: ${l.ok ? `${a.what}, taken: ${l.text}` : `${a.what}, refused: ${l.text}`}`;
    return li;
  }
  function startMany(how, files) {
    const { files: fs, left } = chosen(files, how), names = fs.map((f) => f.file);
    if (!names.length) { S.answers = { what: ACTS[how], kind: 'act', lines: [], left, note: 'No file to act on.' }; draw(); return; }
    bulk(ACTS[how], 'testaction', [how, ...names], names, left, (lines) => lines.forEach((l) => {
      if (!l.ok || !ID.test(l.text)) return;
      S.started.set(dk(l.file), { id: l.text, action: how, file: l.file, start: new Date(S.ctx.now()).toISOString(), state: 'running' });
    }));
  }
  function selBar(files) {
    const h = S.ctx.h, el = h('section', 'tests-selbar'), n = files.filter((f) => S.sel.has(f.file)).length;
    el.setAttribute('aria-label', 'Selected test files');
    const status = h('div', 'tests-selbar-status');
    status.setAttribute('aria-live', 'polite');
    status.append(h('p', 'board-label tests-selbar-count', `${n} selected`));
    const btns = h('div', 'tests-act-row');
    // With no Tests model (or every file a runner, for Optimize) a click says why in the bar: each file left out.
    const judge = actBtn('Judge', 'bulk-judge', `Judge the ${n} selected files`, () => startMany('judge', files));
    if (!tmodel()) judge.title = NO_SEAT;
    const opt = actBtn('Optimize', 'bulk-optimize', `Optimize: preview an issue for each of the ${n} selected files`, () => {
      const { files: fs, left } = chosen(files, 'optimize');
      S.answers = null;  // the preview names the files left out
      if (!fs.length) { S.answers = { what: 'Optimize', lines: [], left, note: 'No file to act on.' }; draw(); return; }
      if (fs.length > FILES_MAX) { S.answers = { what: 'Optimize', lines: [], left, note: `At most ${FILES_MAX} files at a time: ${fs.length} are selected. Select fewer.` }; draw(); return; }
      S.ask = { kind: 'many', repo: S.d.repo, items: fs.map((f) => { const d = draftIssue(f); return { file: f.file, title: d.title, body: d.body }; }), left };
      S.keep = { act: 'many-title', file: fs[0].file }; draw();
    });
    if (!chosen(files, 'optimize').files.length) opt.title = RUNNER_WHY;
    const mut = actBtn('Mutation check', 'bulk-mutate', `Mutation check of the ${n} selected files: at the front of the idle queue. ${MUT_WHY}`,
      () => mutAsk(files.filter((f) => S.sel.has(f.file)).map((f) => f.file), true));
    mut.title = MUT_WHY;
    btns.append(judge, opt, actBtn('Run', 'bulk-run', `Run the ${n} selected files now`, () => startMany('run', files)), mut,
      actBtn('Clear', 'bulk-clear', 'Clear the selection', () => {
        S.sel.clear(); S.answers = null; if (asking('many')) S.ask = null; draw(); say('Selection cleared.');
      }));
    if (!tmodel()) btns.append(h('span', 'tests-why', `Judge: ${NO_SEAT}`));
    const a = S.answers;
    if (a) {
      const ul = h('ul', 'tests-selbar-answers');
      if (a.pending) { const li = h('li', 'tests-sending'); li.append(progress(`Sending: ${a.what}`), `${a.what}: ${SENDING}`); ul.append(li); }
      a.lines.forEach((l) => ul.append(answerLine(a, l, files)));
      a.left.forEach((l) => { const li = h('li', 'tests-why', `${l.file}: left out of ${a.what}: ${l.why}`); li.dataset.file = l.file; ul.append(li); });
      if (a.note) ul.append(h('li', 'tests-refused', a.note));
      if (a.said) ul.append(h('li', 'tests-why tests-said', a.said));
      status.append(ul);
    }
    el.append(status, btns);
    if (asking('many')) el.append(manyPreview());
    return el;
  }
  // Optimize's preview for the files selected: one issue a file, its title and body editable; "File N issues" sends
  // them all in one test-issue, and Cancel files nothing.
  function manyPreview() {
    const h = S.ctx.h, a = S.ask, el = h('div', 'tests-preview tests-selbar-preview'), n = a.items.length;
    el.append(h('p', 'board-head', `Preview of ${n} ${n === 1 ? 'issue' : 'issues'}, one a file. Edit them, then file them.`));
    a.items.forEach((it) => {
      const item = h('div', 'tests-preview');
      item.dataset.file = it.file;
      item.append(h('p', 'board-label', it.file),
        field('many-title', `Title of the issue about ${it.file}`, it.title, (v) => { it.title = v; }, { max: TITLE_MAX }),
        field('many-body', `Text of the issue about ${it.file}`, it.body, (v) => { it.body = v; }, { area: true, max: BODY_MAX }));
      el.append(item);
    });
    a.left.forEach((l) => el.append(h('p', 'tests-why', `Left out: ${l.file}: ${l.why}`)));
    el.append(button(`File ${n} ${n === 1 ? 'issue' : 'issues'}`, 'btn-primary', 'bulk-file', `File ${n} ${n === 1 ? 'issue' : 'issues'}`, () => {
      const bad = a.items.find((it) => !it.title.trim() || /[\r\n]/.test(it.title.trim()) || !it.body.trim());
      // The bar shows why, by the button clicked; the preview already names the files left out.
      if (bad) { const why = `Type a title of one line and a text for the issue about ${bad.file} first.`; S.answers = { what: 'Optimize', lines: [], left: [], note: why }; draw(); say(why); return; }
      bulk('Optimize', 'test-issue', a.items.flatMap((it) => [it.file, it.title.trim(), it.body.trim()]), a.items.map((it) => it.file), a.left, () => { S.ask = null; });
    }), button('Cancel', 'btn-quiet', 'bulk-cancel', 'Cancel: file nothing', () => { S.ask = null; draw(); say('Cancelled. Nothing was filed.'); }));
    return el;
  }
  // ---- Optimize: each issue the Board filed for a file, as its cards left it (the snapshot's optimize) ----
  const optsOf = (f) => list(f.optimize).filter((o) => obj(o) && num(o.issue) !== null)
    .sort((x, y) => (Date.parse(y.time) || 0) - (Date.parse(x.time) || 0));
  function stateSaid(o) {
    if (o.state === 'blocked') return `blocked: ${typeof o.reason === 'string' && o.reason ? o.reason : 'no reason recorded'}`;
    if (o.state === 'landed') return `landed${typeof o.sha === 'string' && o.sha ? ` as ${o.sha.slice(0, 7)}` : ''}`;
    return o.state === 'closed' ? 'closed without landing' : String(o.state || 'open');
  }
  const intoSaid = (o) => list(o.into).filter((x) => typeof x === 'string').join(', ');
  // The fix its card made: sped up, split into <files>, merged into <files> or deleted.
  const fixSaid = (o) => ((o.fix === 'split' || o.fix === 'merged') && intoSaid(o) ? `${o.fix} into ${intoSaid(o)}` : typeof o.fix === 'string' ? o.fix : null);
  // What a landed Optimize did (#130): its proof's CPU s before and after (with no after, the median of the file's runs
  // since it landed), the change, and whether it helped (the file got faster); null when its numbers are not on record.
  function gainOf(o) {
    const b = num(o.before), a = num(o.after) !== null ? o.after : num(o.since);
    if (!b || a === null) return null;
    const change = (a - b) / b;
    return { before: b, after: a, change, helped: Math.round(change * 100) < 0 };
  }
  const gainSaid = (g) => `${one(g.before)} → ${one(g.after)} CPU s (${pct(g.change)})`;
  const helpedSaid = (g) => (g.helped ? 'helped' : 'did not help');
  const helpedChip = (g) => S.ctx.chip(g.helped ? 'Helped' : 'Did not help', g.helped ? 'ok' : 'warn');
  // Its numbers in a line: before → after with the change, and the median of the file's runs since it landed.
  function numbersSaid(o, withHelped = true) {
    const g = gainOf(o);
    if (!g) return null;
    const n = num(o.sinceRuns) || 0, since = num(o.since) === null || num(o.after) === null ? '' : ` · since it landed: ${one(o.since)} CPU s, the median of ${n} ${n === 1 ? 'run' : 'runs'}`;
    return `${gainSaid(g)}${withHelped ? `, ${helpedSaid(g)}` : ''}${since}`;
  }
  // The mutants its file's tests caught before it landed and after (#79): the newest done mutation check of each, when
  // both are on record.
  function mutantsSaid(o) {
    const b = obj(o.mutantsBefore), a = obj(o.mutantsAfter), ok = (m) => m && num(m.killed) !== null && num(m.of) !== null;
    return ok(b) && ok(a) ? `Mutants caught before: ${b.killed} / ${b.of}, after: ${a.killed} / ${a.of}` : null;
  }
  // The runs where a landed Optimize took effect: the first timed run of the file after it landed, to its issue. The
  // row keeps only the last runs: when fewer of them come after it than its sinceRuns (all the timed runs since it
  // landed), that first run is no longer kept and no run is marked.
  function optRuns(f) {
    const out = new Map(), runs = list(f.runs).filter((r) => obj(r) && !Number.isNaN(Date.parse(r.time))).sort((x, y) => Date.parse(x.time) - Date.parse(y.time));
    optsOf(f).filter((o) => o.state === 'landed' && !Number.isNaN(Date.parse(o.landed))).forEach((o) => {
      const after = runs.filter((x) => Date.parse(x.time) > Date.parse(o.landed) && num(x.cpu) !== null), r = after[0];
      if (r && after.length >= (num(o.sinceRuns) ?? Infinity) && !out.has(r)) out.set(r, o);
    });
    return out;
  }
  const optRunSaid = (o) => `first run after Optimize #${o.issue} landed`;

  // ---- Recent actions: each kept action and each Optimize issue, newest first, collapsed until opened ----
  // A file named there opens its row: the search and the filter let it show.
  function goto(file) {
    const f = list(tests() && tests().files).find((x) => obj(x) && x.file === file), q = S.query.trim().toLowerCase();
    if (f && ((S.filter !== 'all' && !marks(f).some((m) => m[0] === S.filter)) || (q && !file.toLowerCase().includes(q)))) { S.filter = 'all'; S.query = ''; }
    S.open.add(file); S.keep = { act: 'open', file }; draw();
    const tr = Array.from(S.el.querySelectorAll('.tests-row')).find((r) => r.dataset.file === file);
    if (tr && typeof tr.scrollIntoView === 'function') tr.scrollIntoView({ block: 'nearest' });
    say(`Opened: ${file}`);
  }
  function recent(files, gone) {
    const h = S.ctx.h, el = h('details', 'tests-results'), all = actions(), rows = new Set(files.map((f) => f.file));
    el.open = S.recentOpen;
    el.addEventListener('toggle', () => { S.recentOpen = el.open; });
    el.append(h('summary', 'board-head', `Recent actions: ${all.filter(running).length} running, ${all.filter(queued).length} queued`));
    const items = all.map((a) => ({ t: a.start || a.asked, a, file: String(a.file) }))
      .concat(files.concat(gone).flatMap((f) => optsOf(f).map((o) => ({ t: o.time, o, file: f.file }))))
      .sort((x, y) => (Date.parse(y.t) || 0) - (Date.parse(x.t) || 0));
    if (!items.length) { el.append(h('p', 'board-from', 'No action ran yet. An action that you start on a row shows here.')); return el; }
    const ul = h('ul', 'tests-results-list');
    items.forEach(({ t, a, o, file }) => {
      const li = h('li', 'tests-result-row'), line = h('div', 'tests-result-line'), name = a ? ACTS[a.action] || String(a.action) : 'Optimize';
      const ref = rows.has(file) ? button(file, 'btn-quiet tests-result-file', 'goto', `Open the row of ${file}`, () => goto(file)) : h('span', 'tests-result-file', file);
      line.append(h('span', 'board-from', S.ctx.when(t)), h('span', 'board-label', name), ref);
      if (o) {
        li.dataset.issue = String(o.issue);
        line.append(S.ctx.issueLink(o), h('span', null, [stateSaid(o), o.state === 'landed' ? fixSaid(o) : null, numbersSaid(o)].filter(Boolean).join(' · ')));
      } else {
        li.dataset.id = a.id;
        if (running(a)) {
          const lim = limitOf(a);
          line.append(h('span', 'board-from', `${a.action === 'run' ? 'engine command, no session' : `${a.cli} · ${a.model} · ${a.effort}`} · Runs: ${mmss(used(a))}${lim ? ` of ${mmss(lim)}` : ''}`));
        } else if (queued(a)) line.append(h('span', 'board-from', queuedSaid(a)));
        else line.append(...result(a));
        if (live(a) && ID.test(a.id)) line.append(button(S.stopping.has(a.id) ? 'Stopping…' : 'Stop', 'btn-quiet', 'stop', `Stop: ${name}, ${a.file}`, () => stop(a)));
        else line.append(button('Copy', 'btn-quiet', 'copy', `Copy the text: ${name}, ${a.file}`, () => copy(S.texts.get(a.id) || '')));
      }
      li.append(line);
      ul.append(li);
    });
    el.append(ul);
    return el;
  }
  // ---- Removed by Optimize: each file a landed Optimize deleted or merged, with its last numbers ----
  function removed(gone) {
    const h = S.ctx.h, el = h('section', 'tests-removed'), ul = h('ul', 'tests-list');
    el.append(h('h3', 'board-head', 'Removed by Optimize'));
    gone.forEach((f) => {
      const o = optsOf(f).find((x) => x.state === 'landed' && (x.fix === 'deleted' || x.fix === 'merged')) || {}, li = h('li', 'tests-gone');
      li.dataset.file = f.file;
      li.append(h('span', 'board-label', f.file), h('span', null, ` · its last run ${one(f.cpu)} CPU s, its median ${one(f.median)} CPU s · `), num(o.issue) === null ? '' : S.ctx.issueLink(o),
        h('span', null, ` · ${o.fix || 'removed'}${o.landed ? ` ${S.ctx.when(o.landed)}` : ''} · ${intoSaid(o) ? `its cases are now in ${intoSaid(o)}` : 'no test file is on record for its cases'}`));
      ul.append(li);
    });
    el.append(ul);
    return el;
  }

  // ---- Test edits by cards (#76): what each landed card did to the test files main had ----
  // The five counts of an edit (the engine's testedits()), with their words for one and for more.
  const EDITS = [['removedAsserts', 'assertion removed', 'assertions removed'], ['changedExpected', 'expected value changed', 'expected values changed'],
    ['skipsAdded', 'skip, only or todo mark added', 'skip, only or todo marks added'], ['timeoutsRaised', 'timeout raised', 'timeouts raised'],
    ['casesDeleted', 'case deleted', 'cases deleted']];
  const weakened = (e) => EDITS.some(([k]) => (num(e[k]) || 0) > 0);
  const editsOf = () => list((tests() || {}).edits).filter((e) => obj(e) && typeof e.file === 'string');
  function editSaid(e) {
    if (e.read === false) return 'Edited, not read';
    const said = EDITS.filter(([k]) => (num(e[k]) || 0) > 0).map(([k, one1, more1]) => `${e[k]} ${e[k] === 1 ? one1 : more1}`);
    return said.length ? said.join(', ') : 'Edited, nothing weakened';
  }
  // An edit's card by its issue, "#NN" (a link to it), never by the card's id (#130): "a card" when it has none.
  const editIssue = (e, any) => (num(e.issue) !== null ? S.ctx.issueLink({ issue: e.issue, url: any ? any.replace(/\d+$/, String(e.issue)) : null }) : S.ctx.h('span', 'issue', 'a card'));
  // One edit: its card's issue, the file (withFile), its time and its counts.
  function editLine(e, withFile, any) {
    const h = S.ctx.h, li = h('li', 'tests-edit');
    li.dataset.file = e.file;
    li.append(editIssue(e, any));
    if (withFile) li.append(h('span', null, ' · '), h('span', 'board-label', e.file));
    li.append(h('span', 'board-from', ` · ${S.ctx.when(e.time)}`), h('span', 'tests-edit-counts', ` · ${editSaid(e)}`));
    return li;
  }
  function editsList(edits, label, withFile, any) {
    const ul = S.ctx.h('ul', 'tests-runs tests-edits-list');
    ul.setAttribute('aria-label', label);
    edits.forEach((e) => ul.append(editLine(e, withFile, any)));
    return ul;
  }
  function editsSection(files) {
    const h = S.ctx.h, el = h('section', 'tests-edits'), all = editsOf(), weak = all.filter(weakened), any = anyIssueUrl(files);
    el.append(h('h3', 'board-head', 'Test edits by cards'));
    const bar = h('div', 'tests-filters');
    bar.setAttribute('role', 'group'); bar.setAttribute('aria-label', 'Show the test edits');
    [['weakened', 'Weakened', weak.length], ['all', 'All edits', all.length]].forEach(([k, name, n]) => {
      const b = button(`${name} ${n}`, 'rules-tog', 'edits-filter', `${name}: ${n} ${n === 1 ? 'edit' : 'edits'}`, () => { S.edits = k; draw(); say(`Showing: ${name}`); });
      b.dataset.filter = k; b.setAttribute('aria-pressed', String(S.edits === k));
      bar.append(b);
    });
    const shown = S.edits === 'all' ? all : weak;
    el.append(bar, shown.length ? editsList(shown, 'Test edits by cards, newest first', true, any)
      : h('p', 'board-from', S.edits === 'all' ? 'No landed card changed a test file that main had.' : 'No landed card weakened a test file that main had.'));
    return el;
  }

  // ---- Auto-file: the switch, the preview, the guards, the rules and the log ----
  const rulesCmd = (args) => ['control', { action: 'testrules', args, repo: S.d.repo }];
  const WHOLE1 = /^[1-9][0-9]{0,5}$/, WHOLE0 = /^[0-9]{1,6}$/, LIMIT = /^[0-9]{1,6}(\.[0-9]{1,3})?$/;
  const ONOFF = [['true', 'On'], ['false', 'Off']];
  const MEASURES = [['usual', 'CPU s over its usual'], ['clock', 'Clock s over its CPU s'], ['flaky', 'Kept off as flaky'], ['failed', 'Failed test steps']];
  // A setting's check: why the value is not sent, or null.
  const checkBy = (re, words) => (v) => (re.test(v) ? null : words);
  function matchSaid(m) {
    const v = obj(m.values) || {};
    return Object.entries(v).map(([k, x]) => `${k} ${Array.isArray(x) ? x.map((y) => (num(y) === null ? String(y) : one(y))).join(', ') : x}`).join('; ');
  }
  function resultSaid(m) {
    if (m.result === 'filed') return `Filed #${m.issue}`;
    if (m.result === 'stopped') return `Stopped by ${m.guard}: ${m.why}`;
    if (m.result === 'not filed') return 'Not filed: GitHub did not take it';
    return 'Would file';
  }
  function previewTable(r) {
    const h = S.ctx.h, last = obj(r.last), matches = list(last && last.matches).filter(obj), el = h('div', 'tests-auto-preview');
    el.append(h('p', 'board-head', last ? `Preview: what the rules matched at ${S.ctx.when(last.time)}, with the result of the guards for each match` : 'Preview: the rules did not run yet'));
    if (!matches.length) { el.append(h('p', 'board-from', last ? 'The rules matched no file.' : 'The rules run after each card test step.')); return el; }
    const t = h('table', 'tests-table tests-auto-table'), head = h('tr'), body = h('tbody'), thead = h('thead');
    ['Rule', 'File', 'Measured', 'Result'].forEach((x) => { const th = h('th', null, x); th.scope = 'col'; head.append(th); });
    matches.forEach((m) => {
      const tr = h('tr', 'tests-auto-match');
      [m.rule, m.file, matchSaid(m), resultSaid(m)].forEach((x) => tr.append(h('td', null, String(x))));
      body.append(tr);
    });
    thead.append(head); t.append(thead, body);
    el.append(t);
    return el;
  }
  function autofile() {
    const h = S.ctx.h, r = rules(), el = h('section', 'tests-auto');
    el.append(h('h3', 'board-head', 'Auto-file'));
    if (!obj(tests() && tests().rules)) { el.append(h('p', 'board-from', 'The build machine names no auto-file rules. It runs an older Conveyor.')); return el; }
    const on = shown('rules-on') === 'true', confirm = asking('on');
    const sw = on
      ? actBtn('Turn off', 'auto-off', 'Turn auto-file off', () => sendRule('rules-on', ['off'], 'false', 'Auto-file is now Off.'))
      : actBtn('Turn on', 'auto-on', 'Turn auto-file on: shows the preview first', () => { S.ask = { kind: 'on', repo: S.d.repo }; S.keep = { act: 'auto-on-confirm' }; draw(); say('Check the preview. Then click "Turn on: confirm".'); });
    el.append(row('auto-switch', 'Auto-file test issues', 'One switch for all rules. Off: the rules file no issue.', PACK, h('span', 'board-value', on ? 'On' : 'Off'), confirm ? null : sw));
    if (confirm && !on) {
      const c = h('div', 'tests-preview');
      c.append(h('p', 'board-head', 'Check the preview below. With the switch on, the rules file such issues after each card test step.'),
        button('Turn on: confirm', 'btn-primary', 'auto-on-confirm', 'Turn auto-file on', () => { S.ask = null; sendRule('rules-on', ['on'], 'true', 'Auto-file is now On.'); }),
        button('Cancel', 'btn-quiet', 'auto-on-cancel', 'Cancel: keep auto-file off', () => { S.ask = null; draw(); say('Cancelled. Auto-file stays Off.'); }));
      el.append(c);
    }
    el.append(previewTable(r));
    // The guards.
    const g = h('div', 'tests-auto-guards');
    g.append(h('p', 'board-head', 'Guards for all rules'));
    [['perDay', 'Most issues in one day', WHOLE1, 'a whole number of 1 or more'], ['maxOpen', 'Most issues open at one time', WHOLE1, 'a whole number of 1 or more'],
      ['quietDays', 'Days with no issue for a file after its last issue closed', WHOLE0, 'a whole number of 0 or more']].forEach(([k, words, re, what]) => {
      g.append(row(`guard-${k}`, words, k, PACK, ...setting(`guard:${k}`, { act: `guard-${k}`, label: words, type: 'number',
        check: checkBy(re, `${words} is ${what}.`), send: (v) => rulesCmd(['guard', k, v]), said: (v) => `${words}: now ${v}` })));
    });
    g.append(row('guard-burst', 'Stop a burst', 'When one run of the rules matches more files than one day may file, that run files nothing.', PACK, ...setting('guard:burst', { act: 'guard-burst', label: 'Stop a burst', choices: ONOFF,
      check: () => null, send: (v) => rulesCmd(['guard', 'burst', v]), said: (v) => `Stop a burst is now ${v === 'true' ? 'On' : 'Off'}` })));
    el.append(g);
    // The rules, each with its fields.
    const rs = h('div', 'tests-auto-rules');
    rs.append(h('p', 'board-head', 'Rules'));
    const all = list(r.list).filter((x) => obj(x) && typeof x.name === 'string');
    if (!all.length) rs.append(h('p', 'board-from', 'No rule. Add one with conveyor.sh testrules add on the build machine.'));
    all.forEach((x) => {
      const box2 = h('div', 'tests-rule'), name = x.name;
      box2.dataset.rule = name;
      box2.append(h('p', 'board-label', `Rule: ${name}`));
      const fld = (k, words, o) => box2.append(row(`rule-${k}`, words, k, null, ...setting(`rule:${k}:${name}`, Object.assign({ act: `rule-${k}`, label: `${words} of rule ${name}`,
        send: (v) => rulesCmd(['set', name, k, v]), said: (v) => `rule ${name}: ${k} now ${v}` }, o))));
      fld('on', 'On', { choices: ONOFF, check: () => null });
      fld('measure', 'Measure', { choices: MEASURES, check: () => null });
      fld('limit', 'Limit (times, or a count)', { type: 'number', check: checkBy(LIMIT, 'The limit is a number of 0 or more, as 1 or 1.5.') });
      fld('runs', 'Runs in a row', { type: 'number', check: checkBy(WHOLE1, 'Runs in a row is a whole number of 1 or more.') });
      fld('minRuns', 'Least runs on record', { type: 'number', check: checkBy(WHOLE0, 'Least runs on record is a whole number of 0 or more.') });
      if (x.measure === 'flaky' || x.measure === 'failed') fld('days', 'Days', { type: 'number', check: checkBy(WHOLE1, 'Days is a whole number of 1 or more.') });
      if (x.measure === 'clock') fld('minClock', 'Least clock s of a run', { type: 'number', check: checkBy(LIMIT, 'Least clock s is a number of 0 or more.') });
      rs.append(box2);
    });
    el.append(rs);
    // What auto-file did.
    const log = list(r.log).filter(obj), ul = h('ul', 'tests-auto-log');
    log.forEach((l) => ul.append(h('li', 'tests-auto-line', `${S.ctx.when(l.time)} · ${l.event === 'filed' ? `Filed #${l.issue}` : `Stopped by ${l.guard}`} · rule ${l.rule} · ${l.file}${l.why ? ` · ${l.why}` : ''}`)));
    if (!log.length) ul.append(h('li', 'board-from', 'Auto-file filed nothing and stopped nothing yet.'));
    el.append(h('p', 'board-head', 'What auto-file did'), ul);
    return el;
  }
  // The switch, saved as the other settings are: it shows as saved until a snapshot names it.
  function sendRule(key, args, v, said) {
    const was = inForce(key);
    send('testrules', args, () => said, (t, at) => { S.pending.set(dk(key), { key, v, was, at, read: S.read }); });
  }

  // ---- the figures ----
  // A figure that counts the files of a status is a button that shows that status alone, as its filter chip does
  // (disabled when no file has the status that the chip counts).
  function figures(files, counts) {
    const h = S.ctx.h, t = obj(tests().totals) || {}, st = obj(t.steps) || {}, el = h('div', 'rules-stats tests-figs');
    const fig = (key, value, label) => {
      const by = MARKS.find(([k]) => k === key), x = h(by ? 'button' : 'div', by ? 'rules-stat rules-stat-open' : 'rules-stat');
      x.dataset.figure = key; x.append(h('span', 'rules-big', value), h('span', 'rules-what', label));
      if (by) {
        x.type = 'button'; x.dataset.act = `figure-${key}`; x.setAttribute('aria-pressed', String(S.filter === key));
        x.setAttribute('aria-label', `${label}: ${value}. Show them.`);
        x.disabled = !counts[key];
        x.addEventListener('click', () => { S.filter = key; S.keep = { act: `figure-${key}` }; draw(); say(`Showing: ${by[1]}`); });
      }
      return x;
    };
    const steps = num(st.count) || 0, took = (s) => (num(s) === null ? '—' : S.ctx.took(s));
    if (files.length) {
      el.append(fig('files', String(num(t.files) === null ? files.length : t.files), 'Timed files'),
        fig('slower', String(num(t.slower) || 0), 'Files slower than usual'),
        fig('waits', String(files.filter((f) => marks(f).some((m) => m[0] === 'waits')).length), 'Files that wait more than they work'));
    }
    el.append(fig('wait', took(st.waitSec), `Slot wait, ${steps} test ${steps === 1 ? 'step' : 'steps'} in 7 days`),
      fig('run', took(st.runSec), `Run time, the same ${steps === 1 ? 'step' : 'steps'}`));
    return el;
  }

  // ---- the table of test files ----
  function bars(f) {
    const h = S.ctx.h, runs = list(f.runs).filter((r) => obj(r) && num(r.cpu) !== null).slice().reverse(), el = h('span', 'tests-bars');
    const top = Math.max(...runs.map((r) => r.cpu), 0), opt = optRuns(f);
    // The run where a landed Optimize took effect has a mark (app.css) and says so on hover.
    runs.forEach((r) => {
      const b = h('span', opt.has(r) ? 'tests-bar tests-bar-opt' : 'tests-bar');
      b.style.transform = `scaleY(${top > 0 ? Math.max(0.04, r.cpu / top) : 0})`;
      if (opt.has(r)) b.title = `${one(r.cpu)} CPU s: the ${optRunSaid(opt.get(r))}`;
      el.append(b);
    });
    el.setAttribute('role', 'img');
    el.setAttribute('aria-label', runs.length ? `Last runs, oldest first: ${runs.map((r) => `${one(r.cpu)}${opt.has(r) ? ` (the ${optRunSaid(opt.get(r))})` : ''}`).join(', ')} CPU s` : 'No runs');
    return el;
  }
  // ---- an opened row (#130, the owner's mockup D): the tabs Overview, Timeline (N), Judge and Mutation ----
  const TABS = [['overview', 'Overview'], ['timeline', 'Timeline'], ['judge', 'Judge'], ['mutation', 'Mutation']];
  const tabOf = (file) => S.tabs.get(dk(file)) || 'overview';
  const showTab = (file, k) => {
    if (k === 'timeline' && (S.older.get(dk(file)) || {}).error) S.older.delete(dk(file));  // a failed read is tried again
    S.tabs.set(dk(file), k); S.keep = { act: `tab-${k}`, file }; draw();
  };
  const COUNT = ['no', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine'];
  // Its landed Optimize issues whose numbers are on record, oldest first, each with what it did.
  const gains = (f) => optsOf(f).filter((o) => o.state === 'landed').reverse().map((o) => ({ o, g: gainOf(o) })).filter((x) => x.g);
  // Its state in one paragraph: its CPU s now, after which Optimize cards, and its trend.
  function stateOf(f) {
    if (f.wholeOnly === true) return 'This file runs only in whole-suite runs (wholeOnly in the pack): a card\'s Test step never runs it. It runs other test files, and each of them is timed on its own.';
    if (!timed(f)) return 'Not timed yet: no run of it is on record.';
    if (wallOnly(f)) return `Wall only: no CPU time is on record. Its last run took ${clockTook((obj(f.lastRun) || {}).sec)}. ${wallWhy(f)}`;
    const done = gains(f), mark = shown(`mark:${f.file}`);
    const after = done.length ? ` after ${COUNT[done.length] || done.length} Optimize ${done.length === 1 ? 'card' : 'cards'} (${done.map((x) => pct(x.g.change)).join(', then ')})` : '';
    const s = mark ? `Slow on purpose: ${mark}.` : `${one(f.cpu)} CPU s${after}.`;
    const k = marks(f).map((m) => m[0]);
    const trend = k.includes('slower') ? `It is slower than usual: ${pct(f.change)} against its median.` : k.includes('faster') ? `It is faster than usual: ${pct(f.change)} against its median.`
      : num(f.change) !== null ? `Its runs are steady: ${pct(f.change)} against its median.` : '';
    return trend ? `${s} ${trend}` : s;
  }
  // The diagnosis box (#130): the state, the judge's verdict with its reason in one line (its full report on the
  // Judge tab), and the next steps, the suggested one primary.
  function diagnosis(f) {
    const h = S.ctx.h, el = h('div', 'tests-diag'), v = verdictOf(f.file), line = h('p', 'tests-diag-verdict');
    line.append(h('span', 'board-label', 'Judge: '));
    if (v) {
      const why = reasonOf(S.texts.get(v.id) || '');
      line.append(verdictChip(v.verdict));
      if (why) line.append(h('span', 'tests-diag-why', why));
      line.append(button('Full report', 'btn-quiet tests-act', 'judge-report', `The judge's full report on ${f.file}`, () => showTab(f.file, 'judge')));
    } else line.append(h('span', 'board-from', 'Not judged yet.'));
    el.append(h('p', 'tests-diag-state', stateOf(f)), line, stepButtons(f));
    return el;
  }
  // A tile of the Overview: its label, its value and the lines under it.
  function tile(key, label, value, ...sub) {
    const h = S.ctx.h, t = h('div', 'tests-tile');
    t.dataset.tile = key;
    t.append(h('span', 'tests-tile-label', label), typeof value === 'string' ? h('span', 'tests-tile-big', value) : value);
    sub.filter(Boolean).forEach((s) => t.append(typeof s === 'string' ? h('span', 'tests-tile-sub', s) : s));
    return t;
  }
  // Its last 4 timed runs as bars, oldest first: each bar takes the focus and shows its value on hover and on focus (app.css).
  function lastBars(f) {
    const h = S.ctx.h, runs = list(f.runs).filter((r) => obj(r) && num(r.cpu) !== null).slice(0, 4).reverse();
    if (!runs.length) return h('span', 'tests-tile-big', '—');
    const el = h('span', 'tests-bars tests-tile-bars'), top = Math.max(...runs.map((r) => r.cpu));
    el.setAttribute('role', 'group'); el.setAttribute('aria-label', 'Last runs, oldest first');
    runs.forEach((r) => {
      const b = h('span', 'tests-bar'), said = `${one(r.cpu)} CPU s, ${runBy(r)}, ${S.ctx.when(r.time)}`;
      b.style.height = `${top > 0 ? Math.max(4, Math.round((r.cpu / top) * 100)) : 4}%`;
      b.tabIndex = 0; b.dataset.value = one(r.cpu); b.title = said;
      b.setAttribute('role', 'img'); b.setAttribute('aria-label', said);
      el.append(b);
    });
    return el;
  }
  // The six tiles: CPU now with its median, the last 4 runs, the last Optimize, the clock, the bugs caught and the mutants.
  function tiles(f) {
    const h = S.ctx.h, el = h('div', 'tests-tiles'), last = obj(f.lastRun) || {}, lo = gains(f).pop(), m = mutDone(f), n = num(f.runsOnRecord) || 0;
    let opt = tile('optimize', 'Last Optimize', '—', 'No Optimize landed.');
    if (lo) {
      const sub = h('span', 'tests-tile-sub');
      sub.append(S.ctx.issueLink(lo.o), ` · ${one(lo.g.before)} → ${one(lo.g.after)} CPU s `, helpedChip(lo.g));
      opt = tile('optimize', 'Last Optimize', pct(lo.g.change), sub);
    }
    el.append(tile('cpu', 'CPU now', num(f.cpu) === null ? '—' : `${one(f.cpu)} CPU s`, num(f.median) === null ? null : `Median: ${one(f.median)} CPU s.`),
      tile('runs', 'Last 4 runs', lastBars(f)), opt,
      tile('clock', 'Clock', clockTook(last.sec), num(last.clockPerCpu) === null ? null : `${one(last.clockPerCpu)}× clock / CPU`),
      tile('caught', 'Bugs caught', String(num(f.caught) || 0), `in ${n} ${n === 1 ? 'run' : 'runs'}`),
      tile('mutants', 'Mutants', m ? `${m.killed} / ${m.of}` : 'not checked', m ? 'caught' : null));
    return el;
  }
  // ---- its events: runs, Optimize issues, test edits and judge runs, newest first ----
  const KINDS = [['all', 'All'], ['runs', 'Runs'], ['optimize', 'Optimize'], ['edits', 'Test edits'], ['judge', 'Judge']];
  const EVENT = { runs: 'Run', optimize: 'Optimize', edits: 'Test edit', judge: 'Judge' };
  // A file's runs and test edits are its newest few (runs, the snapshot's edits) and the older ones on record, which
  // the snapshot does not carry (#251): read from the page server (GET older: `conveyor.sh history test <file>` on the
  // build machine) when its Timeline is opened, and again when a newer run or edit pushes one of the newest out (the
  // stamp: its runs on record and the cards of its newest edits). A failed read is tried again when the Timeline is
  // opened again.
  const olderStamp = (f) => [f.runsOnRecord].concat(editsOf().filter((e) => e.file === f.file).map((e) => e.card)).join('|');
  function readOlder(f) {
    const key = dk(f.file), repo = S.d.repo, was = S.older.get(key), stamp = olderStamp(f);
    if (typeof repo !== 'string' || (was && (was.busy || was.stamp === stamp))) return;
    const o = { stamp, busy: true, data: was ? was.data : null, error: null };
    S.older.set(key, o);
    window.fetch(`older?repo=${encodeURIComponent(repo)}&file=${encodeURIComponent(f.file)}`)
      .then((r) => (r.ok ? r.json() : r.text().then((t) => Promise.reject(new Error(String(t).trim() || `the server answered ${r.status}`)))))
      .then((x) => { if (obj(x)) o.data = x; else o.error = 'the answer did not read'; }, (e) => { o.error = e && e.message ? e.message : 'no answer'; })
      .then(() => { o.busy = false; if (S.older.get(key) === o) draw(); });
  }
  function events(f) {
    const od = obj((S.older.get(dk(f.file)) || {}).data) || {};
    return list(f.runs).concat(list(od.olderRuns)).filter(obj).map((r) => ({ kind: 'runs', t: r.time, r }))
      .concat(optsOf(f).map((o) => ({ kind: 'optimize', t: o.state === 'landed' && o.landed ? o.landed : o.time, o })),
        editsOf().filter((e) => e.file === f.file).concat(list(od.olderEdits).filter((e) => obj(e) && e.file === f.file))
          .map((e) => ({ kind: 'edits', t: e.time, e })),
        actions().filter((a) => a.file === f.file && judged(a)).map((a) => ({ kind: 'judge', t: a.end || a.start, a })))
      .sort((x, y) => (Date.parse(y.t) || 0) - (Date.parse(x.t) || 0));
  }
  // One event: when, its kind and what it was. A run: its CPU and clock time and what ran it, marked when it is the
  // first after an Optimize landed (opt: optRuns()). An Optimize issue: its link and state; landed, its fix, before →
  // after with the change, Helped or Did not help, and its mutants. A test edit: its card's issue and its counts,
  // Weakened marked. A judge run: how it ended and its verdict. full: on the Timeline (its kind's class and data).
  function eventLine(x, opt, any, full) {
    const h = S.ctx.h, li = h('li', 'tests-tl-item'), what = h('span', 'tests-tl-what');
    li.dataset.kind = x.kind;
    li.append(h('span', 'board-from tests-tl-when', S.ctx.when(x.t)), h('span', 'board-label tests-tl-kind', EVENT[x.kind]), what);
    if (x.kind === 'runs') {
      const r = x.r;
      if (full) li.classList.add(...(opt.has(r) ? ['tests-run', 'tests-run-opt'] : ['tests-run']));
      what.append(`${num(r.cpu) === null ? 'CPU not recorded' : `${one(r.cpu)} CPU s`} · ${num(r.sec) === null ? 'clock not recorded' : `${one(r.sec)} s on the clock`} · `);
      if (r.whole === true || num(r.issue) === null) what.append(runBy(r)); else what.append('card ', S.ctx.issueLink(r));
      if (opt.has(r)) what.append(h('span', 'tests-run-mark', ` · the ${optRunSaid(opt.get(r))}`));
    } else if (x.kind === 'optimize') {
      const o = x.o, landed = o.state === 'landed', g = landed ? gainOf(o) : null;
      if (full) { li.classList.add('tests-opt'); li.dataset.issue = String(o.issue); }
      what.append(S.ctx.issueLink(o), ` · ${[landed ? stateSaid(o) : `filed, ${stateSaid(o)}`].concat(landed ? [fixSaid(o), numbersSaid(o, false), mutantsSaid(o)] : []).filter(Boolean).join(' · ')}`);
      if (g) what.append(' ', helpedChip(g));
    } else if (x.kind === 'edits') {
      const e = x.e;
      if (full) { li.classList.add('tests-edit'); li.dataset.file = e.file; }
      what.append(editIssue(e, any), h('span', 'tests-edit-counts', ` · ${editSaid(e)}`));
      if (weakened(e)) what.append(' ', S.ctx.chip('Weakened', 'bad'));
    } else {
      const a = x.a;
      what.append(`${ENDED[a.state] || String(a.state)} · ${a.cli} · ${a.model} · ${a.effort}`);
      if (typeof a.verdict === 'string') what.append(' ', verdictChip(a.verdict));
    }
    return li;
  }
  // The Timeline tab: every event, newest first, with filter chips All, Runs, Optimize, Test edits and Judge.
  function timeline(f, all, opt, any) {
    const h = S.ctx.h, el = h('div', 'tests-timeline'), on = S.tl.get(dk(f.file)) || 'all', bar = h('div', 'tests-filters');
    bar.setAttribute('role', 'group'); bar.setAttribute('aria-label', `Show the events of ${f.file}`);
    KINDS.forEach(([k, words]) => {
      const n = k === 'all' ? all.length : all.filter((x) => x.kind === k).length;
      const b = button(`${words} ${n}`, 'rules-tog', `tl-${k}`, `${words}: ${n} ${n === 1 ? 'event' : 'events'}`, () => { S.tl.set(dk(f.file), k); S.keep = { act: `tl-${k}`, file: f.file }; draw(); });
      b.dataset.filter = k; b.setAttribute('aria-pressed', String(on === k));
      bar.append(b);
    });
    const picked = on === 'all' ? all : all.filter((x) => x.kind === on), ul = h('ul', 'tests-runs tests-tl');
    ul.setAttribute('aria-label', `Events of ${f.file}, newest first`);
    picked.forEach((x) => ul.append(eventLine(x, opt, any, true)));
    el.append(bar, picked.length ? ul : h('p', 'board-from', all.length ? 'No event of this kind on record.' : 'No event on record.'));
    const o = S.older.get(dk(f.file));
    if (o && o.busy) el.append(h('p', 'board-from tests-tl-older', 'Reading the older runs and test edits…'));
    else if (o && o.error) el.append(h('p', 'board-from tests-tl-older', `The Board could not read the older runs and test edits: ${o.error}`));
    return el;
  }
  // The Judge tab: the judge behind Overview's verdict (verdictOf()), else the file's newest ended judge, its verdict
  // said once at the top, then its full report (box()); a note when a newer judge ended with no verdict; and its hollow
  // cases, each with its kind and reason.
  function judgePane(f) {
    const h = S.ctx.h, el = h('div', 'tests-acts tests-judge'), newest = actions().find((x) => x.file === f.file && judged(x)), now = rowAction(f.file);
    const a = verdictOf(f.file) || newest;
    if (now && now.action === 'judge' && !judged(now)) el.append(h('p', 'board-from', 'A judge of this file is under way: it shows on Overview until it ends.'));
    if (newest && newest !== a) el.append(h('p', 'board-from tests-judge-newer', `A newer judge ended with no verdict (${ENDED[newest.state] || newest.state}). It shows on Timeline.`));
    if (a) el.append(box(a, f));
    else el.append(h('p', 'board-from', 'Not judged yet. Judge, on Overview, asks the Tests model whether this file is worth what it costs.'));
    const hollow = hollowOf(f);
    if (hollow.length) {
      const ul = h('ul', 'tests-runs tests-hollow');
      ul.setAttribute('aria-label', `Hollow cases of ${f.file}`);
      hollow.forEach((x) => ul.append(h('li', 'tests-hollow-case', hollowSaid(x))));
      el.append(h('p', 'board-head', 'Hollow cases'), ul);
    }
    // The causes of its failures the judge named (#188), each as its CAUSE line gave it.
    const causes = causesOf(f.file);
    if (causes.length) {
      const ul = h('ul', 'tests-runs tests-causes');
      ul.setAttribute('aria-label', `Causes of the failures of ${f.file}`);
      causes.forEach((x) => ul.append(h('li', 'tests-cause', causeSaid(x))));
      el.append(h('p', 'board-head', 'Causes of its failures'), ul);
    }
    return el;
  }
  // Its failures (#188), on Overview: the card changes it caught, apart, with their cards; then each failed test step,
  // newest first: when, its kind, its card and its failing cases. null with none.
  function failures(f) {
    const h = S.ctx.h, xs = failsOf(f), caught = caughtOf(f);
    if (!xs.length) return null;
    const el = h('div', 'tests-failures');
    el.append(h('p', 'board-head', 'Failures'));
    if (caught.length) {
      const p = h('p', 'tests-fact tests-caught-list', `Caught ${plural(caught.length, 'card change', 'card changes')} (the test did its job; not counted as Fails often): `);
      caught.forEach((x, i) => p.append(...(i ? [', '] : []), S.ctx.issueLink(x)));
      el.append(p);
    }
    const ul = h('ul', 'tests-runs tests-fail-list');
    ul.setAttribute('aria-label', `Failed test steps of ${f.file}, newest first`);
    xs.forEach((x) => {
      const li = h('li', 'tests-fail');
      li.dataset.verdict = x.verdict === null ? 'none' : x.verdict;
      li.append(h('span', 'board-from', S.ctx.when(x.time)), ' · ', h('span', 'board-label', kindSaid(x.verdict)), ' · card ', S.ctx.issueLink(x), ` · ${casesSaid(x)}`);
      ul.append(li);
    });
    el.append(ul);
    return el;
  }
  function more(f) {
    if (tabOf(f.file) === 'timeline') readOlder(f);
    const h = S.ctx.h, el = h('div', 'tests-more'), file = f.file, on = tabOf(file), all = events(f), opt = optRuns(f), any = anyIssueUrl([f]);
    // Overview: the diagnosis, the rest of its actions, the editors picked, the tiles, its failures and the 3 latest events.
    const ov = h('div', 'tests-overview'), acts = rowActions(f), fl = failures(f);
    ov.append(diagnosis(f));
    if (acts) ov.append(acts);
    ov.append(...editors(f), tiles(f));
    if (fl) ov.append(fl);
    const latest = h('div', 'tests-latest'), ul = h('ul', 'tests-runs tests-tl');
    ul.setAttribute('aria-label', `The latest events of ${file}`);
    all.slice(0, 3).forEach((x) => ul.append(eventLine(x, opt, any, false)));
    latest.append(h('p', 'board-head', 'Latest'), all.length ? ul : h('p', 'board-from', 'No event on record.'),
      button(`Timeline (${all.length})`, 'btn-quiet tests-act', 'timeline-all', `Every event of ${file}: Timeline (${all.length})`, () => showTab(file, 'timeline')));
    ov.append(latest);
    // Mutation: its check's state, and each mutant its tests did not catch, with its line and change.
    const mut = h('div', 'tests-mutation');
    mut.append(h('p', 'tests-fact tests-mut-state', mutState(f)));
    const surv = survivors(f);
    if (surv.length) {
      const ul = h('ul', 'tests-runs tests-survivors');
      ul.setAttribute('aria-label', `Surviving mutants of ${file}`);
      surv.forEach((x) => {
        const li = h('li', 'tests-survivor');
        li.append(h('span', 'board-label', `${x.source}:${x.line}`), h('span', 'board-from', typeof x.kind === 'string' ? ` (${x.kind}) ` : ' '),
          h('code', 'tests-mut-before', trimmed(x.before)), h('span', null, ' → '), h('code', 'tests-mut-after', trimmed(x.after)),
          h('span', 'board-from', ' · tests still passed'));
        ul.append(li);
      });
      mut.append(ul);
    }
    // The tabs, each tied to its pane; only the open one's pane shows. Left and right arrows move between them.
    const panes = { overview: ov, timeline: timeline(f, all, opt, any), judge: judgePane(f), mutation: mut };
    const bar = h('div', 'tests-tabs'), id = `tests-row-${S.uid += 1}`;
    bar.setAttribute('role', 'tablist'); bar.setAttribute('aria-label', `${file}: views`);
    el.append(bar);
    TABS.forEach(([k, words], i) => {
      const t = button(k === 'timeline' ? `${words} (${all.length})` : words, 'btn-quiet tests-tab', `tab-${k}`, null, () => showTab(file, k));
      t.id = `${id}-tab-${k}`; t.tabIndex = k === on ? 0 : -1;
      t.setAttribute('role', 'tab'); t.setAttribute('aria-selected', String(k === on)); t.setAttribute('aria-controls', `${id}-${k}`);
      t.addEventListener('keydown', (e) => {
        const step = e.key === 'ArrowRight' ? 1 : e.key === 'ArrowLeft' ? -1 : 0;
        if (step) { e.preventDefault(); showTab(file, TABS[(i + step + TABS.length) % TABS.length][0]); }
      });
      bar.append(t);
      const p = h('section', 'tests-pane');
      p.id = `${id}-${k}`; p.dataset.pane = k; p.hidden = k !== on;
      p.setAttribute('role', 'tabpanel'); p.setAttribute('aria-labelledby', t.id);
      p.append(panes[k]);
      el.append(p);
    });
    return el;
  }
  // The editor of its mark, shown once picked (from More), and while a value typed, refused or saved here is in it. A
  // runner (wholeOnly) is never slower than usual, so a slow-on-purpose mark set here would never apply: it has none.
  function editors(f) {
    const file = f.file, out = [];
    if (f.wholeOnly === true) return out;
    const editing = (what, key) => S.edit.has(`${dk(file)}|${what}`) || S.drafts.has(dk(key)) || S.pending.has(dk(key)) || (S.refused && S.refused.dk === dk(key));
    if (editing('mark', `mark:${file}`)) {
      out.push(row('mark', 'Mark as slow on purpose', 'No CPU test rule files an issue about this file', PACK, ...setting(`mark:${file}`, {
        act: 'slow-mark', file, label: `Why ${file} is slow on purpose`, placeholder: 'Why it is slow on purpose', clear: 'Clear', ask: true,
        check: (v, set) => (v === '' ? (set === '' ? 'Type why the file is slow on purpose first.' : null) : null),
        send: (v) => control(v === '' ? ['slow-mark-clear', file] : ['slow-mark', file, v]),
        said: (v) => (v === '' ? `${file} is no longer marked slow on purpose` : `${file} is marked slow on purpose`) })));
    }
    return out;
  }
  // The files of each status, by its key.
  const countsOf = (files) => Object.fromEntries(MARKS.map(([k]) => [k, files.filter((f) => marks(f).some((m) => m[0] === k)).length]));
  // A file's issue as a link, "#NN": the snapshot gives its number, and the project's issue address is that of a run's
  // card issue (each run is this project's): any, one such address, read once a draw. With no such run, "#NN" as text.
  const ISSUE_URL = /^https:\/\/github\.com\/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\/issues\/\d+$/;
  const anyIssueUrl = (files) => files.flatMap((x) => list(x.runs)).map((r) => obj(r) && r.url).find((u) => typeof u === 'string' && ISSUE_URL.test(u)) || null;
  function issueOf(f, any) {
    const a = S.ctx.issueLink({ issue: f.issue, url: any ? any.replace(/\d+$/, String(f.issue)) : null });
    a.title = 'Its issue';
    return a;
  }
  function table(files, counts) {
    const h = S.ctx.h, el = h('section', 'tests-files'), any = anyIssueUrl(files);
    const bar = h('div', 'tests-filters');
    bar.setAttribute('role', 'group'); bar.setAttribute('aria-label', 'Show the files');
    [['all', 'All', files.length]].concat(MARKS.filter(([k]) => counts[k]).map(([k, name]) => [k, name, counts[k]])).forEach(([k, name, n]) => {
      const b = button(`${name} ${n}`, 'rules-tog', 'filter', `${name}: ${n} ${n === 1 ? 'file' : 'files'}`, () => { S.filter = k; draw(); say(`Showing: ${name}`); });
      b.dataset.filter = k; b.setAttribute('aria-pressed', String(S.filter === k));
      bar.append(b);
    });
    // The search box: any part of the path, in any case, with the filter chip picked.
    if (!S.search) {
      const s = h('input', 'field tests-search');
      s.type = 'search'; s.placeholder = 'Search test files'; s.dataset.act = 'search'; s.setAttribute('aria-label', 'Search the test files by name');
      s.addEventListener('input', () => { S.query = s.value; draw(); });
      S.search = s;
    }
    S.search.value = S.query;
    const find = h('div', 'tests-filters'); find.append(S.search);
    const q = S.query.trim().toLowerCase();
    // With no sort picked, the timed files first, then the rows that need a look; the snapshot's order (the highest CPU s
    // first) inside each. A sort keeps that order among equal values.
    let shownFiles = files.map((f, i) => [f, i]).filter(([f]) => (S.filter === 'all' || marks(f).some((m) => m[0] === S.filter)) && (!q || f.file.toLowerCase().includes(q)))
      .sort((a, b) => (timed(b[0]) - timed(a[0])) || (look(b[0]) - look(a[0])) || (a[1] - b[1])).map(([f]) => f);
    const col = S.sort && COLS.find((c) => c[0] === S.sort.key);
    if (col) {
      const by = (f) => (col[0] !== 'file' && !timed(f) ? null : col[2](f)), up = S.sort.dir === 'asc' ? 1 : -1;
      shownFiles = shownFiles.slice().sort((a, b) => {
        const x = by(a), y = by(b);
        if (x === null || y === null) return (x === null) - (y === null);
        return up * (typeof x === 'string' ? x.localeCompare(y) : x - y);
      });
    }
    const t = h('table', 'tests-table'), head = h('tr');
    COLS.forEach(([key, words, , hint]) => {
      const th = h('th'), on = col && col[0] === key, dir = on ? S.sort.dir : null;
      th.scope = 'col';
      th.setAttribute('aria-sort', on ? (dir === 'asc' ? 'ascending' : 'descending') : 'none');
      // The header checkbox selects every row shown (the search and the filter), or, when all of them are, clears them.
      if (key === 'file') {
        const n = shownFiles.filter((f) => S.sel.has(f.file)).length, all = h('input', 'tests-check');
        all.type = 'checkbox'; all.dataset.act = 'select-all';
        all.checked = n > 0 && n === shownFiles.length; all.indeterminate = n > 0 && n < shownFiles.length;
        all.disabled = !shownFiles.length;
        all.setAttribute('aria-label', `Select the ${shownFiles.length} files shown`);
        all.addEventListener('change', () => {
          const on2 = n < shownFiles.length;
          shownFiles.forEach((f) => (on2 ? S.sel.add(f.file) : S.sel.delete(f.file)));
          S.keep = { act: 'select-all' }; draw();
          say(on2 ? `${S.sel.size} selected.` : 'Selection cleared for the files shown.');
        });
        th.append(all);
        if (S.sel.size) th.append(h('span', 'tests-selected', `${S.sel.size} selected`));
      }
      const b = button(`${words}${on ? (dir === 'asc' ? ' ▲' : ' ▼') : ''}`, 'btn-quiet tests-sort', `sort-${key}`, `Sort by ${words}`, () => {
        S.sort = { key, dir: on ? (dir === 'asc' ? 'desc' : 'asc') : key === 'file' ? 'asc' : 'desc' };
        S.keep = { act: `sort-${key}` }; draw();
        say(`Sorted by ${words}, ${S.sort.dir === 'asc' ? (key === 'file' ? 'A to Z' : 'lowest first') : key === 'file' ? 'Z to A' : 'highest first'}`);
      });
      // The hint shows on hover and on focus (app.css), and is read with the heading.
      const tip = h('span', 'tests-hint', hint);
      tip.id = `tests-hint-${key}`; tip.setAttribute('role', 'tooltip');
      b.setAttribute('aria-describedby', tip.id);
      th.append(b, tip); head.append(th);
    });
    const thead = h('thead'); thead.append(head);
    const body = h('tbody');
    if (!shownFiles.length) { const tr = h('tr', 'tests-none'), td = h('td', 'board-from', 'No test file matches'); td.colSpan = COLS.length; tr.append(td); body.append(tr); }
    shownFiles.forEach((f) => {
      const open = S.open.has(f.file), tr = h('tr', 'tests-row'), last = obj(f.lastRun) || {};
      tr.dataset.file = f.file;
      const name = button(f.file, 'btn-quiet tests-name', 'open', `${f.file}: ${open ? 'close' : 'open'} its runs`, () => { if (S.open.has(f.file)) S.open.delete(f.file); else S.open.add(f.file); S.keep = { act: 'open', file: f.file }; draw(); });
      name.setAttribute('aria-expanded', String(open));
      const check = h('input', 'tests-check');
      check.type = 'checkbox'; check.dataset.act = 'select'; check.checked = S.sel.has(f.file);
      check.setAttribute('aria-label', `Select ${f.file}`);
      check.addEventListener('change', () => { if (check.checked) S.sel.add(f.file); else S.sel.delete(f.file); S.keep = { act: 'select', file: f.file }; draw(); });
      const cell = (x, cls) => { const td = h('td', cls); td.append(x); return td; };
      // The status: chips; its issue as a link; Runs other test files and Whole suite only as grey text.
      const chips = h('span', 'rules-marks');
      // The kinds of its failures (#188) follow the place of Fails often: those that count for it, and apart, the card
      // changes it caught, with their cards on hover.
      const at = MARKS.findIndex((m) => m[0] === 'fails');
      let told = false;
      const tell = () => {
        if (told) return;
        told = true;
        if (notCard(f).length) chips.append(h('span', 'tests-quiet tests-fail-kinds', `Failed: ${failKinds(f)}`));
        if (caughtOf(f).length) {
          const c = h('span', 'tests-quiet tests-caught-cards', `caught ${plural(caughtOf(f).length, 'card change', 'card changes')}`);
          c.title = `Its test did its job: ${caughtOf(f).map((x) => (num(x.issue) ? `#${x.issue}` : String(x.card))).join(', ')}`;
          chips.append(c);
        }
      };
      marks(f).forEach(([k, words, tone]) => {
        if (MARKS.findIndex((m) => m[0] === k) > at) tell();
        chips.append(k === 'issue' ? issueOf(f, any) : k === 'runner' || k === 'whole' ? h('span', 'tests-quiet', words) : S.ctx.chip(words, tone));
      });
      tell();
      // Why a file never ran (#189), when the engine can tell.
      if (marks(f).some((m) => m[0] === 'never') && neverWhy(f)) chips.append(h('span', 'tests-quiet tests-never-why', `Not run: ${neverWhy(f)}`));
      // What a whole-only file costs, and why a Wall only file has no CPU time, with what can record it (#190).
      if (f.wholeOnly === true) chips.append(h('span', 'tests-quiet tests-whole-cost', wholeCost()));
      if (wallOnly(f)) chips.append(h('span', 'tests-quiet tests-wall-why', wallWhy(f)));
      // A grey fact, not a problem chip: a file that never fails may check nothing.
      if ((num(f.runsOnRecord) || 0) >= NEVER && num(f.caught) === 0) chips.append(h('span', 'tests-quiet tests-never', 'Never caught anything'));
      const fileCell = cell(check, 'tests-file');
      fileCell.append(name);
      if (!timed(f)) {
        // A file never timed: one cell in place of its figures.
        const none = cell('Not timed yet', 'tests-untimed');
        none.colSpan = COLS.length - 2;
        tr.append(fileCell, none, cell(chips));
      } else {
        // The newest run's clock time, with its date and time on hover.
        const took = cell(clockTook(last.sec), 'tests-num');
        if (num(last.sec) !== null && typeof last.time === 'string' && !Number.isNaN(Date.parse(last.time))) {
          took.title = `${new Date(last.time).toLocaleString()}, ${last.whole === true ? 'whole suite' : 'card'}`;
        }
        const count = COLS.find((c) => c[0] === 'count')[2](f);
        const caught = cell(num(f.caught) === null ? '—' : String(f.caught), 'tests-num tests-caught');
        if (num(f.caught) !== null) caught.title = `Edited until it passed: ${num(f.changedToPass) || 0}`;
        // Mutants caught: empty before a check; when and on which commit its newest done check ran, on hover.
        const mut = cell(mutCell(f), 'tests-num tests-mutants'), md = mutDone(f);
        if (md) mut.title = `Checked ${S.ctx.when(md.at)} on commit ${String(md.sha || 'not recorded').slice(0, 7)}`;
        tr.append(fileCell, cell(one(f.cpu), 'tests-num'), cell(one(f.median), 'tests-num'), cell(pct(f.change), 'tests-num'),
          cell(bars(f)), cell(num(last.clockPerCpu) === null ? '—' : `${one(last.clockPerCpu)}×`, 'tests-num'), cell(count === null ? '—' : String(count), 'tests-num'), took, caught, mut, cell(chips));
      }
      body.append(tr);
      if (open) { const more2 = h('tr', 'tests-open'), td = h('td'); td.colSpan = COLS.length; td.append(more(f)); more2.dataset.file = f.file; more2.append(td); body.append(more2); }
    });
    t.append(thead, body);
    const wrap = h('div', 'tests-scroll'); wrap.append(t);
    el.append(find, bar, wrap);
    return el;
  }

  // ---- Test limits ----
  function limits() {
    const h = S.ctx.h, el = h('section', 'tests-limits'), m = obj(S.d.machine), t = tests(), s = settings();
    el.append(h('h3', 'board-head', 'Test limits'));
    if (m && m.unread === true) {
      el.append(row('load', 'Load limit', 'machine-wide', HOST, h('p', 'warn-note', 'Conveyor could not read the build machine\'s host file, so the Board does not know its load limit. Fix the host file there.')));
    } else if (m) {
      const set = shown('load');
      const now = h('span', 'board-from', `In force: ${set === '' ? 'Off' : set} · ${num(m.cores) === null ? 'cores not read' : `${m.cores} ${m.cores === 1 ? 'core' : 'cores'}`}`
        + ` · load now ${num(m.load) === null ? 'not read' : m.load}`);
      el.append(row('load', 'Load limit', 'No new card starts while the load is above this. Conveyor never stops the cards that already run.', HOST,
        ...setting('load', { act: 'load', label: 'Load limit', type: 'number', placeholder: 'Off', clear: 'Off',
          check: (v) => (v !== '' && !(LOAD.test(v) && Number(v) >= 1) ? 'A load limit is a number of 1 or more, as 20, or Off.' : null),
          send: (v) => ['machine', { action: 'load', value: v === '' ? 'off' : v }], said: (v) => `load limit now ${v === '' ? 'Off' : v}` }), now));
    }
    if (!t) return el;
    const files = Object.entries(obj(s.files) || {}).filter(([, v]) => obj(v));
    const items = (pick, words) => {
      const ul = h('ul', 'tests-list'), got = files.filter(([, v]) => pick(v) !== null && pick(v) !== undefined);
      got.forEach(([f, v]) => ul.append(h('li', null, `${f}: ${words(pick(v))}`)));
      if (!got.length) ul.append(h('li', 'board-from', 'None'));
      return ul;
    };
    el.append(row('purpose', 'Files slow on purpose', 'No CPU test rule files an issue about them. Each has a reason.', PACK, items((v) => (typeof v.slowOnPurpose === 'string' ? v.slowOnPurpose : null), (r) => r)));
    // #457's rows, only when the snapshot names them.
    const box = obj(s.box);
    if (box) el.append(row('box', 'Hard box for each test file', 'A test file cannot use more CPU or memory than its test slot gives.', 'the engine (no setting)', h('span', 'board-value', box.on === false ? 'Off' : 'On')));
    if (typeof s.slowIssues === 'boolean') {
      el.append(row('off-card-runs', 'Take a file off card runs', 'It files nothing and takes no file off card runs: the Auto-file rules file issues about test files.', PACK,
        ...setting('slowIssues', { act: 'slow-issues', label: 'Take a file off card runs', choices: [['true', 'On'], ['false', 'Off']],
          check: () => null, send: (v) => control(['slow-issues', v]), said: (v) => `Take a file off card runs is now ${v === 'true' ? 'On' : 'Off'}` })));
    }
    return el;
  }

  // ---- the Test map part (#178), at the top of the page ----
  const MAPS = { made: 'Made', failed: 'Failed', stopped: 'Stopped' };
  const at = (sec) => (num(sec) === null ? null : new Date(sec * 1000).toISOString());
  const mapLive = (b) => b && (b.state === 'running' || b.state === 'waiting');
  // The map's state, as the map page shows it; while a run makes it, a bar of its test files done of all; the last build by
  // hand's result; and Build the test map (with the tool and the last whole-suite run's time named), or Stop.
  function mapPart(m) {
    const h = S.ctx.h, el = h('section', 'tests-map'), b = obj(m.build), live = mapLive(b);
    el.append(h('h3', 'board-head', 'Test map'));
    // A Build sent here shows as starting until a snapshot names a build begun since.
    if (S.mapSent && (live || (b && b.start !== S.mapSent.was))) S.mapSent = null;
    const line = h('p', 'tests-map-state');
    if (m.state === 'running') {
      line.append(progress(`Test map: ${m.done} of ${m.of} test files`, num(m.done) || 0, num(m.of) || 0),
        h('span', null, ` Being made: ${m.done} of ${m.of} test files run${num(m.started) === null ? '' : `, ${mmss(S.ctx.now() / 1000 - m.started)} so far`}.`));
    } else if (live) {
      line.append(progress('Test map: waiting for a test slot'), h('span', null, ' Waiting for a test slot on the build machine.'));
    } else if (S.mapSent) {
      line.append(progress('Test map: starting'), h('span', null, ` Starting: ${SENDING}`));
    } else if (m.state === 'made') {
      const age = num(m.age) === null ? '' : m.age ? ` · ${m.age} ${m.age === 1 ? 'commit' : 'commits'} behind main` : ' · up to date with main';
      const when = typeof m.made === 'string' ? ` · made ${S.ctx.when(m.made)}` : '';
      const took = num(m.seconds) === null ? '' : `, in ${mmss(m.seconds)}`;
      const nm = Array.isArray(m.notMapped) ? m.notMapped.length : 0;
      const not = nm ? `, ${nm} test ${nm === 1 ? 'file' : 'files'} not mapped` : '';
      line.append(S.ctx.chip('Made', 'ok'), ` ${m.sources} source files and ${m.tests} test files mapped${not}${age}${when}${took}.`);
    } else if (m.state === 'off') {
      line.append(S.ctx.chip('Off', 'quiet'), ' The pack\'s test.map is "off": a card\'s tests are found by name. To turn it on, remove test.map from the pack, then build the map here or run setup.');
    } else if (m.state === 'failed') {
      line.append(S.ctx.chip('Failed', 'bad'), ` ${m.why || 'no reason given'}`);
    } else {
      line.append(S.ctx.chip('Not made yet', 'warn'), ' A card\'s tests are found by name until the map is made.');
    }
    el.append(line);
    // The test files the made map could not map, each with why, folded.
    if (m.state === 'made' && Array.isArray(m.notMapped) && m.notMapped.length) {
      const d = h('details', 'tests-map-not');
      d.append(h('summary', null, `Test files not mapped: ${m.notMapped.length}. The map does not use them to pick a card's tests.`));
      const ul = h('ul', 'tests-list');
      m.notMapped.forEach((x) => { const li = h('li', null, `${x.file}: `); li.append(h('pre', 'tests-out', String(x.why || 'no reason given'))); ul.append(li); });
      d.append(ul);
      el.append(d);
    }
    // The last build's result, in place, once it has ended.
    if (b && !live && MAPS[b.state]) {
      const said = [num(b.start) !== null && num(b.end) !== null ? `in ${mmss(b.end - b.start)}` : null,
        num(b.end) !== null ? S.ctx.when(at(b.end)) : null, typeof b.reason === 'string' && b.reason ? b.reason : null].filter(Boolean).join(' · ');
      const res = h('p', 'tests-map-result');
      res.append(S.ctx.chip(`Last build: ${MAPS[b.state]}`, b.state === 'made' ? 'ok' : b.state === 'failed' ? 'bad' : 'quiet'), h('span', 'board-from', ` ${said}`));
      el.append(res);
    }
    const ctl = h('div', 'tests-act-row');
    if (live) {
      ctl.append(button('Stop', 'btn-quiet', 'map-stop', 'Stop the build of the test map', () => send('testmap', ['stop'], (t) => `Stop sent: the build of the test map. ${t}`)));
    } else if (m.state !== 'running' && m.state !== 'off' && !S.mapSent) {
      if (m.tool) {
        ctl.append(button('Build the test map', 'btn-primary', 'map-build', 'Build the test map', () => {
          S.mapRefused = null;
          const was = b ? b.start : null;
          send('testmap', ['build'], (t) => `Started: ${t.replace(/^conveyor: /, '')}`, () => { S.mapSent = { was }; }, (why) => { S.mapRefused = why; });
        }));
        ctl.append(h('span', 'board-from', `Runs the whole suite once with ${m.tool}. ${num(m.suiteSec) === null
          ? 'No whole-suite run is recorded: it takes about as long as the whole suite, or more.'
          : `The last whole-suite run took ${mmss(m.suiteSec)}: it takes about that long, or more.`} Admins only.`));
      } else {
        ctl.append(h('span', 'board-from', `No test map can be made: ${m.toolWhy || 'no coverage tool'}.`));
      }
    }
    if (ctl.childNodes.length) el.append(ctl);
    if (S.mapRefused) { const no = h('p', 'rules-refused', `Not started: ${S.mapRefused}`); no.setAttribute('role', 'alert'); el.append(no); }
    return el;
  }

  // Benchmarks: the latest drift watch of the project (`conveyor.sh bench drift`, the snapshot's drift): the ended cards
  // of the latest engine commit against those of the one before, a mean a card of each figure, and a group of fewer
  // than 5 cards called too small to mean anything.
  function driftPart(dr) {
    const h = S.ctx.h, el = h('section', 'tests-bench'), b = obj(dr.before) || {}, a = obj(dr.after) || {};
    const v = (x) => (typeof x === 'number' ? String(x) : '-');
    const sha = (g) => String(g.engine || '').slice(0, 8);
    const figs = [['tokens a card', 'tokens'], ['minutes a card', 'minutes'], ['reviews to land', 'reviews'], ['fix rounds a card', 'fixes'],
      ['blocked', 'blocked'], ['minutes waited a card', 'waits']].map(([n, k]) => `${n} ${v(b[k])} to ${v(a[k])}`);
    const cards = (g) => `${v(g.cards)} ${g.cards === 1 ? 'card' : 'cards'}`;
    el.append(h('h3', 'board-head', 'Benchmarks'),
      h('p', 'tests-drift', `Drift watch, engine ${sha(b)} (${cards(b)}) against ${sha(a)} (${cards(a)}): ${figs.join(', ')}.`));
    (Array.isArray(dr.small) ? dr.small : []).filter((k) => k === 'before' || k === 'after').forEach((k) => {
      el.append(h('p', 'warn-note', `The ${k} group holds ${cards(k === 'before' ? b : a)}: too small to mean anything (fewer than 5 cards).`));
    });
    return el;
  }

  // ---- the Benchmarks part (#236): SWE-bench Verified run through Conveyor (conveyor.sh bench swe) ----
  // The snapshot's bench is the run's board.json (bench/swe.sh swe_board()): live (the run in progress or the last
  // one), versions, presets, max, perTask (each arm's usual and worst-case sessions and minutes a task), soloKey (the
  // key a Claude alone run takes now) and keys (each engine commit's, Claude alone's or another arm's results by task, and at: their
  // places in the pinned order). Before Start the part shows the sessions and minutes expected for the tasks of the n
  // chosen that the version picked has not run yet; while a run goes, a bar of its tasks done with Stop; then the results side by side, one
  // column a version or arm, and Compare, which shows `bench swe diff` of two columns.
  const BENCH = { n: 5, solo: false, engine: 'main', a: '', b: '', diff: null };  // the n, version and Compare pair picked, the last Compare's text
  // Another arm (bench/arms/, `bench swe <n> --arm`) shows by its label, with its model when it keeps each model's
  // results under a key of their own (an arm on the builder's model: its key is not its name; an arm of a fixed model
  // has the model in its label already), and its engine version when it runs one.
  const otherArm = (x) => typeof x.arm === 'string' && x.arm !== 'conveyor' && x.arm !== 'solo';
  const keyName = (k) => (otherArm(k) ? `${k.label || k.arm}${k.model && k.key !== k.arm ? ` (${k.model})` : ''}${k.engine ? ` ${k.version || 'commit'} ${String(k.engine).slice(0, 12)}` : ''}`
    : k.arm === 'solo' ? `Claude alone${k.model ? ` (${k.model})` : ''}` : `${k.version || 'commit'} ${String(k.engine || '').slice(0, 12)}`);
  // A run's arms: its label (each arm's name, bench/swe.sh swe_run()) when it runs another arm or more than one.
  const runArms = (l) => (otherArm(l) || list(l.arms).length > 1 ? String(l.label || l.arm) : null);
  // How many tasks a difference must reach to be told from run-to-run noise (swe_noise(), bench/swe.sh).
  function noise(n) {
    const d = Math.ceil(Math.sqrt(2 * n));
    return d >= n ? `With ${n} ${n === 1 ? 'task' : 'tasks'} only a total break shows: a difference under ${n} is within the noise.`
      : `With ${n} tasks a difference under ${d} tasks is within the noise.`;
  }
  function benchPart(b) {
    const h = S.ctx.h, el = h('section', 'tests-bench'), live = obj(b.live), max = num(b.max) || 500;
    el.append(h('h3', 'board-head', 'Benchmarks: SWE-bench Verified'));
    const running = live && live.state === 'running';
    if (running) {
      const line = h('p', 'tests-bench-state');
      line.append(progress(`SWE-bench: ${live.done} of ${live.n} tasks`, num(live.done) || 0, num(live.n) || 0),
        h('span', null, ` Running: ${live.done} of ${live.n} tasks done, ${live.resolved} resolved${live.current ? `, now ${live.current}` : ''} · ${runArms(live) || (live.arm === 'solo' ? 'Claude alone' : `engine ${live.version || String(live.engine || '').slice(0, 12)}`)}.`));
      el.append(line, button('Stop', 'btn-quiet', 'bench-stop', 'Stop the SWE-bench run', () => send('bench', ['stop'], (t) => `Stop sent: the SWE-bench run. ${t}`)));
    } else {
      // A run refused after the Board's answer (an arm's preflight failed) shows why it did not start.
      if (live && live.state === 'refused') el.append(h('p', 'tests-bench-last', `Last run: did not start · ${live.why || 'no reason recorded'}`));
      else if (live && live.state) {
        const tasks = list(live.tasks), notRun = tasks.filter((t) => String(t.result).startsWith('not run')).length;
        el.append(h('p', 'tests-bench-last', `Last run: ${live.state === 'done' ? 'ended' : live.state === 'guard' ? 'stopped at the usage guard' : 'stopped'} · ${live.resolved} of ${live.n} resolved${notRun ? `, ${notRun} not run` : ''} · ${runArms(live) || (live.arm === 'solo' ? 'Claude alone' : `engine ${live.version || ''} ${String(live.engine || '').slice(0, 12)}`.trim())}.`));
      }
      const ctl = h('div', 'tests-act-row');
      list(b.presets).concat(b.presets ? [] : [1, 5, 20, 50]).forEach((p) => {
        ctl.append(button(String(p), p === BENCH.n ? 'btn-primary' : 'btn-quiet', `bench-preset-${p}`, `${p} ${p === 1 ? 'task' : 'tasks'}`, () => { BENCH.n = p; draw(); }));
      });
      const box = h('input', 'tests-bench-n');
      box.type = 'number'; box.min = '1'; box.max = String(max); box.value = String(BENCH.n); box.dataset.act = 'bench-n'; box.setAttribute('aria-label', 'Number of tasks');
      box.addEventListener('change', () => { const v = Number(box.value); if (Number.isInteger(v) && v >= 1 && v <= max) BENCH.n = v; draw(); });
      const pick = h('select', 'tests-bench-engine');
      pick.dataset.act = 'bench-engine'; pick.setAttribute('aria-label', 'Engine version');
      const versions = list(b.versions).filter((v) => obj(v) && typeof v.name === 'string');
      (versions.some((v) => v.name === 'main') ? versions : [{ name: 'main' }].concat(versions)).forEach((v) => {
        const o = h('option', null, v.name); o.value = v.name; pick.append(o);
      });
      const solo = h('option', null, 'Claude alone (no review or fix rounds)'); solo.value = '--solo'; pick.append(solo);
      pick.value = BENCH.solo ? '--solo' : BENCH.engine;
      pick.addEventListener('change', () => { BENCH.solo = pick.value === '--solo'; if (!BENCH.solo) BENCH.engine = pick.value; draw(); });
      ctl.append(box, pick);
      // Offered also once a list is kept: main's commit in it is the one read when it was listed, and moves on.
      ctl.append(button('List versions', 'btn-quiet', 'bench-versions', 'List the released versions', () => send('bench', ['versions'], () => 'The versions are listed.')));
      el.append(ctl);
      const per = obj(obj(b.perTask) && b.perTask[BENCH.solo ? 'solo' : 'conveyor']) || (BENCH.solo ? { usual: 1, worst: 1, minutes: 8 } : { usual: 2, worst: 12, minutes: 20 });
      // The tasks of the first n that the version picked (or Claude alone) already ran are reused: only the rest cost.
      // Not for main: Start sends --engine main, which the engine reads again, and main may have moved past the commit
      // in the kept list, so a quote from that commit could say 0 sessions for a run that builds every task.
      const main = !BENCH.solo && BENCH.engine === 'main';
      const commit = main ? null : (versions.find((v) => v.name === BENCH.engine) || {}).commit;
      const mine = list(b.keys).find((k) => obj(k) && (BENCH.solo ? k.key === b.soloKey : k.arm !== 'solo' && typeof commit === 'string' && k.engine === commit));
      const reused = mine ? list(mine.at).filter((i) => Number.isInteger(i) && i < BENCH.n).length : 0, todo = BENCH.n - reused;
      const reuse = main ? 'Main\'s commit is read when the run starts: tasks that commit already ran are reused at no cost.'
        : reused ? `${reused} of them already ran on this version and are reused at no cost.` : 'Tasks already run on this version are reused and cost nothing.';
      el.append(h('p', 'tests-bench-plan', `Expected for ${BENCH.n} ${BENCH.n === 1 ? 'task' : 'tasks'}: about ${Math.ceil(todo * per.usual)} sessions (worst case ${todo * per.worst}) and ${todo * per.minutes} minutes. ${reuse} A run does not start while the usage guard is reached.`));
      const go = button('Start', 'btn-primary', 'bench-start', `Run SWE-bench: ${BENCH.n} tasks`, () => {
        send('bench', ['run', String(BENCH.n)].concat(BENCH.solo ? ['--solo'] : ['--engine', BENCH.engine]), (t) => `Started: ${t.replace(/^conveyor: /, '')}`);
      });
      el.append(go);
    }
    // The results, side by side: one row a task, one column a version (or Claude alone), the resolved count of each.
    const keys = list(b.keys).filter((k) => obj(k) && obj(k.tasks));
    if (keys.length) {
      const ids = Array.from(new Set(keys.flatMap((k) => Object.keys(k.tasks)))).sort();
      const t = h('table', 'tests-bench-table'), head = h('tr');
      head.append(h('th', null, 'Task'), ...keys.map((k) => h('th', null, keyName(k))));
      t.append(head);
      ids.forEach((id) => {
        const r = h('tr');
        r.append(h('td', null, id), ...keys.map((k) => {
          const x = obj(k.tasks[id]);
          return h('td', null, x ? `${x.resolved ? 'Resolved' : 'Not resolved'} · ${x.sessions} sessions · ${x.tokens} tokens · ${x.minutes} min` : '—');
        }));
        t.append(r);
      });
      const tot = h('tr');
      tot.append(h('th', null, 'Resolved'), ...keys.map((k) => { const xs = Object.values(k.tasks); return h('th', null, `${xs.filter((x) => obj(x) && x.resolved).length} of ${xs.length}`); }));
      t.append(tot);
      const wrap = h('div', 'tests-scroll');
      wrap.append(t);
      el.append(wrap);
      const common = ids.filter((id) => keys.every((k) => k.tasks[id]));
      if (keys.length > 1 && common.length) el.append(h('p', 'board-from', `On the ${common.length} tasks every column ran: ${noise(common.length)}`));
      // Any two columns: each sends its results key, so two arms on one engine commit, or an arm with no engine, are
      // each read as their own column.
      const cols = keys.filter((k) => typeof k.key === 'string');
      if (cols.length > 1) {
        const cmp = h('div', 'tests-act-row');
        const choose = (which, label) => {
          const s = h('select', null);
          s.dataset.act = `bench-${which}`; s.setAttribute('aria-label', label);
          cols.forEach((k) => { const o = h('option', null, keyName(k)); o.value = k.key; s.append(o); });
          if (!cols.some((k) => k.key === BENCH[which])) BENCH[which] = cols[which === 'a' ? 0 : 1].key;
          s.value = BENCH[which];
          s.addEventListener('change', () => { BENCH[which] = s.value; });
          return s;
        };
        cmp.append(choose('a', 'Version A'), choose('b', 'Version B'), button('Compare', 'btn-quiet', 'bench-compare', 'Compare the two versions', () => {
          BENCH.diff = null;
          send('bench', ['diff', BENCH.a, BENCH.b], () => 'Compared.', (text) => { BENCH.diff = text; });
        }));
        el.append(cmp);
        if (BENCH.diff) el.append(h('pre', 'tests-bench-diff', BENCH.diff));
      }
    }
    return el;
  }

  function draw() {
    const el = S.el, h = S.ctx.h;
    if (S.d.repo === null) {
      el.replaceChildren(S.ctx.state('empty', 'No tests to show', 'Conveyor did not run on this project on the build machine yet. Pick a project under Show, above the tabs.'));
      return;
    }
    const a = document.activeElement && el.contains(document.activeElement) && document.activeElement.dataset ? document.activeElement : null;
    const keep = S.keep || (a && a.dataset.act ? { act: a.dataset.act, file: (a.closest('[data-file]') || { dataset: {} }).dataset.file } : null);
    S.keep = null;
    const t = tests(), every = list(t && t.files).filter((f) => obj(f) && typeof f.file === 'string');
    // A file a landed Optimize deleted or merged (removed) is not in the table: it shows under Removed by Optimize.
    const files = every.filter((f) => f.removed !== true), gone = every.filter((f) => f.removed === true);
    // A file selected that the snapshot no longer lists is no longer selected; with none selected, the bar's answers go.
    S.sel.forEach((x) => { if (!files.some((f) => f.file === x)) S.sel.delete(x); });
    if (!S.sel.size) { S.answers = null; if (asking('many')) S.ask = null; }
    const parts = [];
    if (obj(S.d.testMap)) parts.push(mapPart(S.d.testMap));
    // The Benchmarks part, also before any run (the snapshot's bench is null then); not from an engine older than it.
    if ('bench' in S.d) parts.push(benchPart(obj(S.d.bench) || {}));
    // Settings: the Tests model, Test limits and Auto-file, collapsed until opened; it stays as it was from one draw to
    // the next.
    const wasSet = el.querySelector('.tests-settings');
    if (wasSet) S.settingsOpen = wasSet.open;
    const wasRecent = el.querySelector('.tests-results');
    if (wasRecent) S.recentOpen = wasRecent.open;
    const set = h('details', 'tests-settings');
    set.open = S.settingsOpen;
    set.addEventListener('toggle', () => { S.settingsOpen = set.open; });
    set.append(h('summary', 'board-head', 'Settings'));
    if (!t) {
      parts.push(h('p', 'warn-note', 'Conveyor could not read the test figures of this project. Its pack does not read, or the build machine runs an older Conveyor.'));
      set.append(limits());
    } else {
      const counts = countsOf(files);
      if (S.filter !== 'all' && !counts[S.filter]) S.filter = 'all';
      parts.push(figures(files, counts));
      parts.push(files.length ? table(files, counts) : S.ctx.state('empty', 'No file times for this project',
        'Conveyor records the times of each test file from the test runner\'s own report (the pack\'s test.report), or when the test command prints a "TESTRUN sec" line for it. The helper conveyor/tools/testtime.sh prints this line. The table starts when the first card with file times runs its tests.'));
      parts.push(editsSection(files));
      if (gone.length) parts.push(removed(gone));
      if (S.sel.size) parts.push(selBar(files));
      parts.push(recent(files, gone));
      set.append(actionsHead(), limits(), autofile());
    }
    if (obj(S.d.drift)) parts.push(driftPart(S.d.drift));
    parts.push(set);
    const note = h('p', 'board-note tests-note');
    note.setAttribute('aria-live', 'polite');
    const was = el.querySelector('.tests-note');
    if (was) note.textContent = was.textContent;
    const root = h('div', S.sel.size ? 'tests tests-has-selbar' : 'tests');
    root.append(...parts);
    // The table scrolls sideways when wider than the panel (app.css): a new snapshot keeps its place.
    const side = el.querySelector('.tests-scroll'), left = side ? side.scrollLeft : 0;
    // An opened row's tab pane scrolls inside (app.css): a new snapshot keeps the place read in it, by file and tab.
    const paneKey = (p) => `${(p.closest('[data-file]') || { dataset: {} }).dataset.file}|${p.dataset.pane}`;
    const read = new Map(Array.from(el.querySelectorAll('.tests-pane'), (p) => [paneKey(p), p.scrollTop]));
    el.replaceChildren(root, note);
    const wide = root.querySelector('.tests-scroll');
    if (wide) wide.scrollLeft = left;
    root.querySelectorAll('.tests-pane').forEach((p) => { const top = read.get(paneKey(p)); if (top) p.scrollTop = top; });
    if (S.busy) {
      root.querySelectorAll('button, input, select, textarea').forEach((b) => {
        if (!['filter', 'edits-filter', 'open', 'goto', 'copy', 'search', 'select', 'select-all', 'more', 'timeline-all', 'judge-report'].includes(b.dataset.act) && !/^(sort|figure|tab|tl)-/.test(b.dataset.act || '')) b.disabled = true;
      });
    }
    if (keep) {
      const scope = keep.file ? Array.from(el.querySelectorAll('[data-file]')).filter((x) => x.dataset.file === keep.file) : [el];
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
  }

  // A value saved here stands until a snapshot names it, or until one begun at or after the Save was answered (with no
  // time, the next one) names a value other than the one it replaced: a change saved since from elsewhere then shows.
  // The live feed republishes the record it last read, so one still naming the replaced value never ends it.
  function render(el, d, ctx) {
    const read = typeof ctx.updatedAt === 'function' ? ctx.updatedAt() : null;
    const view = ctx.project(d);
    ctx.title(Array.isArray(view.repos) && view.repos.length > 1 && view.repo ? `Tests: ${view.repo}` : null);
    if (S.repo !== undefined && view.repo !== S.repo) {
      S.open.clear(); S.filter = 'all'; S.query = ''; S.refused = null; S.ask = null;
      S.sel.clear(); S.answers = null; S.menu = null; S.edit.clear(); S.mapSent = null; S.mapRefused = null;
    }
    Object.assign(S, { el, ctx, d: view, read, repo: view.repo });
    if (view.repo !== null) {
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
    if (S.held) { S.late = true; return; }
    draw();
  }
  // The panel is drawn whole. A button drawn anew between its press and its release lost the click (the browser gives
  // it to the element pressed, then gone): a row did not open, an action did not start. So a snapshot that comes while
  // the pointer is pressed in the panel is drawn after the release, once its click has run.
  document.addEventListener('pointerdown', (e) => { S.held = Boolean(S.el && S.el.contains(e.target)); }, true);
  const release = () => {
    if (!S.held) return;
    S.held = false;
    if (S.late) { S.late = false; setTimeout(draw, 0); }
  };
  document.addEventListener('pointerup', release, true);
  document.addEventListener('pointercancel', release, true);
  window.addEventListener('blur', release);

  window.DASH_APP.panel({
    id: 'tests',
    title: 'Tests',
    size: 'full',
    tab: 'tests',  // a tab of its own
    rows: 'all',
    rowSelector: '.tests-row, .rules-row, .rules-stat',
    isEmpty: (d) => d.repo === null && !(d.others && typeof d.others === 'object' && Object.keys(d.others).length),
    empty(el, ctx) { el.append(ctx.state('empty', 'No tests to show', 'Conveyor did not run on this project on the build machine yet, so it has no test figures. Start Conveyor there, and they show here.')); },
    error(el, message, ctx) { el.append(ctx.state('error', 'The Board could not read the tests', message)); },
    render,
    // A value saved here waits for a snapshot begun after its answer, though the part be the same as the last.
    same(el, d, ctx) {
      const read = typeof ctx.updatedAt === 'function' ? ctx.updatedAt() : null;
      if (S.pending.size && read !== S.read) render(el, d, ctx);
    },
  });
}());
