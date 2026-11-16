// SPDX-License-Identifier: Apache-2.0
// The Tests page (#520; the owner chose mockup A, with mockup B's column "against its own median"): a tab of its own,
// after Rules. It shows one project at a time: with more than one on the host, the machine head's Show picks it, as
// on the Rules tab, and the heading names it ("Tests: sample").
// The page, top to bottom (#73, #74): the figures, the table with its search and filters, Removed by Optimize, the bar
// of the files selected, Recent actions, and one section "Settings", collapsed until opened, with the Tests model, Test
// limits and Auto-file.
// The figures: Timed files, files over budget, files slower than usual, files that wait more than they work (their
// last run took more than twice its CPU time on the clock: WAITS), and the card test steps of the 7 days: their slot
// wait and their run time. A figure that counts the files of a status is a button that shows that status alone, as
// its filter chip does.
// The table, one row a test file (every test file of main's checkout, run or not): a checkbox and the file, CPU s now,
// median, change against its own median, its last runs as bars (oldest first), clock against CPU, runs on record,
// the clock time its newest run took (Last run took, with that run's date and time on hover), Caught (#75: the card test
// steps it failed whose landed change left it as it was; the times it was changed to pass on hover), and its status
// (chips; its issue as a link, "#NN"; Runs other test files, Whole suite only and, for a file with NEVER runs on
// record or more and no catch, Never caught anything as grey text). A file with no CPU time on
// record shows "Not timed yet" in place of its figures and comes after the timed files (by name, it sorts as any
// other). Each column heading has a hint on hover and on focus. A file the pack marks wholeOnly (a runner that starts
// other test files whole, each of them with its own budget) is held to no budget: it has "Runs other test files" in
// place of a budget, is never Over budget, Slower than usual or Waits, and has no Optimize. A search box over it keeps
// the rows whose path holds its text (any case); filter chips, each with its count, show one status alone; the two
// apply together. Each column heading sorts the table by that column (file names A to Z, any other highest first; a
// second click reverses it, and an arrow shows which). With no sort picked, the rows that need a look (over budget
// and not slow on purpose, slower than usual, waits, flaky or fails often) come first, then the highest CPU s.
// Selected files: the header checkbox selects every row the search and filters show. With one file or more selected,
// a bar fixed at the foot of the screen (aria-live) says how many, with Judge, Optimize, Run and Clear. Judge and Run
// send one POST for all of them (control {action: testaction, args: [judge | run, file...]}); Optimize opens one
// preview, an issue a file (title and body editable), and its "File N issues" sends one test-issue with them all.
// The bar shows the answer for each file, and each file left out with why: the runner for Optimize, every file for
// Judge with no Tests model.
// A row opens to show its runs, each with a link to its card's issue or marked "whole suite" with its result, its
// budget and its mark, its Optimize issues, and three actions: Judge, Optimize and Run. Its Optimize issues (#74): each
// issue the Board filed for it (the snapshot's optimize: Optimize, and older speed-up, issues), newest first, with the
// date filed, its "#NN" link and its state (open, building, blocked with the reason, landed with the commit, closed
// without landing); landed, the fix its card made (sped up, split, merged into <file>, deleted) and its proof's CPU s
// before and after, with the median of the runs since it landed beside before. The run where one landed (the first
// after it) is marked in its Last runs bars and in its runs. A file a landed Optimize deleted or merged (removed) is not
// in the table: Removed by Optimize, after it, shows its last numbers, the issue and the files that took its cases.
// Its More menu holds Explain the slowdown, Keep a case off, Close its issue as done, Set a budget for this file and Mark as slow on purpose (it asks for the reason).
// Settings, Test limits. Each row names where it saves: Load limit in the host file (this machine, all
// projects; moved from the Rules tab's Machine section, #462, with the same behaviour), and in the pack file (this
// project): CPU budget for a test file (test.fileBudget), the budgets of single files and the files slow on purpose
// (lists), and, only when the snapshot names them, the hard box of each test file (settings.box: {on}) and "Take a
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
// body, with the measured numbers and the judge's kept verdict with the end of its text, both editable; no Done-when
// line), and files (POST control {action: test-issue, args: [file, title, body]}: `conveyor.sh testissue`, which keeps
// it as the file's issue) only on its second button; Cancel files nothing. With no Tests model, Judge and Explain are
// disabled and say "Set the Tests model first."
// "Model for Tests actions": CLI, model (with Other… for a typed name) and effort, as the Rules tab's roles; a pick
// says Unsaved, Save sends POST control {action: tests, args: [cli, model, effort] or [default]}, Cancel puts back the
// one in force.
// An opened row shows its newest action (#74). While it runs, a bar and the time used against the action's limit, and
// a box with its text as the snapshot brings it (kept here, so a text the snapshot cut to its end loses nothing seen
// before), with Stop (testaction stop <id>, that action alone) and Copy. Queued, "Queued, N ahead" and Stop. Ended, its
// result with its time, CLI, model and effort; a judge's starts with "Verdict: <word>" and its chip, and, for speed
// up, split, merge or delete, "Optimize with this verdict", which opens the Optimize preview with that verdict and its
// text. The text of a judge or explain is formatted (md(): paragraphs, bold, lists, inline code and code blocks; any
// other markup as typed), a run's output as typed; Copy copies the raw text. Recent actions, collapsed until opened,
// counts the running and queued actions in its heading and lists each kept action and each Optimize issue, newest
// first, each with its file (a click opens its row), and Stop on a running or queued action, else Copy.
// Auto-file: the one switch (Off by default; "Turn on" shows the preview, the matches of the rules' last run, each
// with its guard's result, and asks for a second click), the guards and each rule's fields (each Unsaved until Save posts
// `conveyor.sh testrules guard|set`), and the log of what the rules filed and stopped.
// Its part (dashboard.sh, tests): {repo (null: none is steered), tests (the snapshot's: settings, rules, files (each
// with its optimize issues, each with its url, and removed), slower, totals; null from a snapshot without it),
// machine ({maxLoad, unread, cores, load}), testActions ({limit, actions, allowed:
// the pack's models by CLI, offered for a CLI that lists none}), control (the control record: its tests, the Tests model),
// clis (the host's CLIs, {models: null when it lists none, efforts} each), flaky ([{case, count, issue, files}]), repos, others}.
(function () {
  'use strict';
  const LOAD = /^[0-9]{1,6}(\.[0-9]{1,3})?$/;  // a load limit, as dashboard_server.py's LOAD and `conveyor.sh machine load` take it (1 or more)
  const BUDGET = /^[1-9][0-9]{0,5}(\.[0-9]{1,3})?$/;  // CPU seconds, as dashboard_server.py's BUDGET and `conveyor.sh test-settings` take them
  const REASON_MAX = 300;  // a reason, as dashboard_server.py's said_ok takes it
  const WAITS = 2;         // a file waits more than it works when its last run took more than this times its CPU time
  const FAILS = 2;         // a file fails often when this many test steps or more failed in it
  const NEVER = 20;        // a file with this many runs on record or more and no catch shows "Never caught anything"
  const HOST = 'Host file: this machine, all projects';
  const PACK = 'Pack file: this project';
  // The status chips, in the order of the filters: key, words, tone, whether a row with it needs a look.
  const MARKS = [
    ['over', 'Over budget', 'bad', true], ['slower', 'Slower than usual', 'warn', true], ['faster', 'Faster', 'ok', false],
    ['waits', 'Waits', 'info', true], ['flaky', 'Flaky', 'warn', true], ['fails', 'Fails often', 'bad', true],
    ['issue', 'Has an issue', 'info', false], ['purpose', 'Slow on purpose', 'quiet', false],
    ['runner', 'Runs other test files', 'quiet', false], ['whole', 'Whole suite only', 'quiet', false], ['never', 'Never run', 'quiet', false]];
  const S = { el: null, ctx: null, d: null, read: null, repo: undefined, filter: 'all', open: new Set(), busy: false,
    sort: null,          // the column the table is sorted by, {key, dir: asc | desc}; null: rows that need a look first, then the highest CPU s
    query: '', search: null,  // the text of the search box, and the box: the same node from one draw to the next, so it keeps the caret
    held: false, late: false,  // the pointer is pressed in the panel; a snapshot came meanwhile, to draw on its release
    drafts: new Map(),   // the values typed and not yet saved, by dk(key)
    pending: new Map(),  // the values saved here, by dk(key): {key, v, was, at, read}, until a snapshot names them
    refused: null,       // the last refusal: {dk, text}
    keep: null,          // the control to focus after the next draw: {act, file}
    tmodel: new Map(),   // the Tests model picked and not yet saved, by project: {cli, model, effort, other}
    seatSaved: null,     // the Tests model saved here, until a snapshot names it: {repo, value, was, at, read}
    started: new Map(),  // the action asked for here, by dk(file), until the snapshot lists it: {id, action, file, at}
    texts: new Map(),    // each action's text as seen here, by id: the snapshot holds the end of a long one only
    recentOpen: false,   // the Recent actions section is open
    ask: null,           // a preview open: {kind: issue | close | keep | on | many, file, title, body, case, why; many: items [{file, title, body}]}
    stopping: new Set(),    // the ids of the actions a Stop was sent for
    sel: new Set(),      // the files selected, for the bar's actions
    answers: null,       // the bar's last action: {what, lines: [{file, ok, text}], note}
    menu: null,          // the file whose More menu is open
    edit: new Set(),     // the editors opened from a More menu: `${dk(file)}|budget` or `${dk(file)}|mark`
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
  // A setting's key: load (the machine's), fileBudget, slowIssues, budget:<file>, mark:<file> (the project's); dk is
  // the key with the project, so a value typed for one project is never sent for another.
  const dk = (key) => (key === 'load' ? key : `${S.d.repo}|${key}`);
  function inForce(key) {
    const m = obj(S.d.machine) || {}, s = settings();
    if (key === 'load') return num(m.maxLoad) === null ? '' : String(m.maxLoad);
    if (key === 'fileBudget') return num(s.fileBudget) === null ? '' : String(s.fileBudget);
    if (key === 'slowIssues') return s.slowIssues === true ? 'true' : 'false';
    if (key.startsWith('budget:')) return num(own(key.slice(7)).budget) === null ? '' : String(own(key.slice(7)).budget);
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
      over: f.over === true && !f.slowOnPurpose, slower: f.slower === true, faster: num(f.change) !== null && f.change <= -share,
      waits: !runner && num(last.clockPerCpu) !== null && last.clockPerCpu > WAITS, flaky: (num(f.flaky) || 0) > 0,
      fails: (num(f.failedSteps) || 0) >= FAILS, issue: f.issue !== null && f.issue !== undefined, purpose: !!f.slowOnPurpose,
      runner, whole: runner, never: !list(f.runs).length,
    })[k]);
  }
  const look = (f) => marks(f).some((m) => m[3]);
  // A file is timed when a run of it on record has a CPU time; one that is not shows "Not timed yet" and comes last.
  const timed = (f) => list(f.runs).some((r) => obj(r) && num(r.cpu) !== null);
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
    ['caught', 'Caught', (f) => num(f.caught), 'The card test steps it failed whose landed change left it as it was: the fix went into the code. Point at a count to see how often it was changed to pass.'],
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
  const budgetCheck = (v, set) => (v === '' ? (set === '' ? 'Type a budget first.' : null) : BUDGET.test(v) ? null : 'A budget is CPU seconds: a number of 1 or more, as 8 or 12.5.');

  // ---- the actions ----
  const ACTS = { judge: 'Judge this test', explain: 'Explain the slowdown', run: 'Run this file now' };
  const FILES_MAX = 20;  // the most files of one action on a list of them, as dashboard_server.py's TEST_FILES_MAX
  const RUNNER_WHY = 'It runs other test files, and each of them has its own budget.';
  const ENDED = { done: 'Done', stopped: 'Stopped', failed: 'Failed', 'timed out': 'Timed out' };
  const MODEL = /^[A-Za-z0-9][A-Za-z0-9._:/@[\]-]{0,191}$/;  // a model, as dashboard_server.py's MODEL
  const OTHER = '*other';  // the model list's Other…: a name typed in (no model starts with *)
  const ID = /^[0-9a-f]{12}$/;  // an action's id, as `conveyor.sh testaction` prints it
  const SAID_MAX = 300, TITLE_MAX = 200, BODY_MAX = 2500;  // as dashboard_server.py's said_ok and test-issue (TEST_ISSUE_BODY) take them
  const NO_SEAT = 'Set the Tests model first.';
  // The engine's runner runs each of its case files and names their cases as its own: a flaky entry and the `off` line
  // a card's run reads (.conveyor/test-changed.sh, lib/flaky.sh flakyoff()) name the runner, not the case file.
  const RUNNER = 'conveyor/conveyor.test.sh', CASE_FILE = /^conveyor\/tests\/[^/]+\.test\.sh$/;
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
  // The judge's newest verdict for a file, when one is kept.
  const verdictOf = (file) => actions().find((a) => a.file === file && a.action === 'judge' && a.state === 'done' && typeof a.verdict === 'string' && a.verdict !== 'no verdict') || null;

  const actBtn = (text, act, label, fn) => button(text, 'btn-quiet tests-act', act, label, fn);
  // One action sent: POST control {action, args, repo}; then(text, at) on a yes, no(refusal) on a no, and the answer or
  // the refusal said.
  function send(action, args, said, then, no) {
    if (S.busy) { say('Wait: the build machine did not answer the last change yet.'); return; }
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
  function start(how, file) {
    send('testaction', [how, file], () => `Started: ${ACTS[how]}, ${file}.`, (text) => {
      const id = text.split('\n').pop().trim();
      S.started.set(dk(file), { id: ID.test(id) ? id : '', action: how, file, start: new Date(S.ctx.now()).toISOString(), state: 'running' });
      S.open.add(file);
    });
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
  // The verdicts that Optimize acts on: each is one of the fixes an Optimize card picks.
  const ACTIONABLE = ['speed up', 'split', 'merge', 'delete'];
  // The box of one action: running, a bar and the time used against its limit, its text so far, Stop and Copy;
  // queued, how many wait before it, and Stop; ended, its result (a judge's verdict line first, with Optimize with this
  // verdict when Optimize acts on it), its text (formatted, but a run's output) and Copy.
  function box(a, f) {
    const h = S.ctx.h, el = h('div', 'tests-box'), head = h('div', 'tests-box-head'), name = ACTS[a.action] || String(a.action);
    el.dataset.id = a.id;
    head.append(h('span', 'board-label', name));
    const text = S.texts.get(a.id) || '', btns = h('div', 'tests-box-btns'), parts = [head];
    if (live(a) && ID.test(a.id)) btns.append(button(S.stopping.has(a.id) ? 'Stopping…' : 'Stop', 'btn-quiet', 'stop', `Stop: ${name}, ${a.file}`, () => stop(a)));
    if (queued(a)) {
      head.append(h('span', 'board-from', queuedSaid(a)));
      el.append(head, btns);
      return el;
    }
    if (running(a)) {
      const lim = limitOf(a), u = used(a), bar = h('progress', 'tests-progress');
      if (lim) { bar.max = lim; bar.value = Math.min(u, lim); }
      bar.setAttribute('aria-label', `Time used: ${name}`);
      head.append(bar, h('span', 'board-from', lim ? `${mmss(u)} of the ${mmss(lim)} time limit` : `${mmss(u)} used`));
    } else head.append(...result(a, false));
    if (!running(a) && a.action === 'judge' && typeof a.verdict === 'string') {
      const line = h('p', 'tests-verdict', 'Verdict: ');
      line.append(verdictChip(a.verdict));
      if (ACTIONABLE.includes(a.verdict)) {
        const b = button('Optimize with this verdict', 'btn-quiet tests-act', 'optimize-verdict', `Optimize ${a.file}: preview an issue with this verdict`, () => {
          S.ask = draftIssue(f, a); S.keep = { act: 'issue-title', file: f.file }; draw();
        });
        if (f.wholeOnly === true) { b.disabled = true; b.title = RUNNER_WHY; }
        line.append(' ', b);
      }
      parts.push(line);
    }
    let out;
    if (running(a) || a.action === 'run') {
      out = h('pre', 'tests-out', text || (running(a) ? 'Started. Its text shows here as it comes.' : 'No text.'));
      out.setAttribute('aria-live', 'polite');
    } else out = text ? md(text) : h('p', 'board-from', 'No text.');
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
      `- Budget: ${one(f.budget)} CPU s`,
      `- Clock / CPU in its last run: ${num(last.clockPerCpu) === null ? '—' : `${one(last.clockPerCpu)}×`}`,
      `- Runs on record: ${num(f.timedRuns) || 0}. Test steps that failed in it: ${num(f.failedSteps) || 0}. Flaky entries: ${num(f.flaky) || 0}.`,
      `- Last runs, newest first: ${runs.map((r) => `${one(r.cpu)} CPU s (card ${r.card})`).join(', ') || 'none'}`];
    if (v) {
      lines.push('', `The judge's verdict (${v.end || v.start}, ${v.cli} · ${v.model} · ${v.effort}): ${v.verdict}.`);
      const text = (S.texts.get(v.id) || '').split('\n').map((l) => l.replace(/[\p{C}\p{Z}]/gu, ' ').trimEnd()).join('\n').trim();
      const room = BODY_MAX - lines.join('\n').length - 40, chars = Array.from(text);
      if (text && room > 0) lines.push('', 'The end of its text:', chars.length > room ? `…${chars.slice(-room).join('')}` : text);
    }
    return { kind: 'issue', repo: S.d.repo, file, title: `Optimize the test file ${file}`, body: lines.join('\n') };
  }
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
      el.append(h('p', 'board-head', 'Preview of the issue. Edit it, then file it.'),
        field('issue-title', 'Title of the issue', a.title, (v) => { a.title = v; }, { max: TITLE_MAX }),
        field('issue-body', 'Text of the issue', a.body, (v) => { a.body = v; }, { area: true, max: BODY_MAX }),
        button('File this issue', 'btn-primary', 'issue-file', `File this issue about ${file}`, () => {
          const t = a.title.trim(), b = a.body.trim();
          if (!t || /[\r\n]/.test(t)) { say('Type a title of one line first.'); return; }
          if (!b) { say('Type the text of the issue first.'); return; }
          send('test-issue', [file, t, b], (url) => `Filed: ${url}`, () => { S.ask = null; });
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
          const c = `${CASE_FILE.test(file) ? RUNNER : file}: ${a.case.trim()}`, why = a.why.trim();
          if (!a.case.trim() || !why) { say('Type the case and why first.'); return; }
          if (c.length > SAID_MAX) { say(`The file and case are more than ${SAID_MAX} characters.`); return; }
          send('flaky-off', [c, why], () => `Kept off: ${c}.`, () => { S.ask = null; });
        }), cancel('keep-cancel'));
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
      ['explain', ACTS.explain, tmodel() ? null : NO_SEAT, () => start('explain', file)],
      ['flaky-off', 'Keep a case off', null, () => { S.ask = { kind: 'keep', repo: S.d.repo, file, case: '', why: '' }; S.keep = { act: 'keep-case', file }; draw(); }],
      ['close-done', 'Close its issue as done', num(f.issue) === null ? 'It has no issue to close.' : null, () => {
        const before = num(f.usual) === null ? f.median : f.usual;
        S.ask = { kind: 'close', repo: S.d.repo, file, body: `Done: ${file} used ${one(before)} CPU s before (its usual) and ${one(f.cpu)} CPU s in its last run. Closed from the Board's Tests page.` };
        S.keep = { act: 'close-comment', file }; draw();
      }],
      // A runner (wholeOnly) is held to no budget, so a budget or a slow-on-purpose mark set here would never apply.
      ['menu-budget', 'Set a budget for this file', runner ? RUNNER_WHY : null, edit('budget', 'file-budget-field')],
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
  // The actions of an opened row (Judge, Optimize, Run and More), the preview open on it, and the box of its action.
  function rowActions(f) {
    const h = S.ctx.h, file = f.file, el = h('div', 'tests-acts'), noSeat = !tmodel();
    const now = h('div', 'tests-act-row');
    const judge = actBtn('Judge', 'judge', `${ACTS.judge}: ${file}`, () => start('judge', file));
    if (noSeat) { judge.disabled = true; judge.title = NO_SEAT; }
    // A runner (wholeOnly) is held to no budget: its time is its files' time, so no issue asks to optimize it.
    const opt = actBtn('Optimize', 'optimize', `Optimize: preview an issue about ${file}`, () => { S.ask = draftIssue(f); S.keep = { act: 'issue-title', file }; draw(); });
    if (f.wholeOnly === true) { opt.disabled = true; opt.title = RUNNER_WHY; }
    now.append(judge, opt, actBtn('Run', 'run', `${ACTS.run}: ${file}`, () => start('run', file)), moreMenu(f));
    if (noSeat) now.append(h('span', 'tests-why', `Judge and Explain: ${NO_SEAT}`));
    el.append(h('p', 'board-head', 'Actions'), now);
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
    const a = rowAction(file);
    if (a) el.append(box(a, f));
    return el;
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
  // started there does) or the issues of Optimize (test-issue). Each file's answer, and those left out, show in the bar.
  function bulk(what, action, args, files, left, done) {
    if (files.length > FILES_MAX) { S.answers = { what, lines: [], left, note: `At most ${FILES_MAX} files at a time: ${files.length} are selected. Select fewer.` }; draw(); return; }
    send(action, args, (t) => { const a = answersOf(files, t); return `${what}: ${a.filter((x) => x.ok).length} of ${a.length} taken.`; }, (t) => {
      const lines = answersOf(files, t);
      S.answers = { what, lines, left, note: null };
      if (done) done(lines);
    }, (why) => { S.answers = { what, lines: files.map((file) => ({ file, ok: false, text: why })), left, note: null }; });
  }
  function startMany(how, files) {
    const { files: fs, left } = chosen(files, how), names = fs.map((f) => f.file);
    if (!names.length) { S.answers = { what: ACTS[how], lines: [], left, note: 'No file to act on.' }; draw(); return; }
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
    const judge = actBtn('Judge', 'bulk-judge', `Judge the ${n} selected files`, () => startMany('judge', files));
    if (!tmodel()) { judge.disabled = true; judge.title = NO_SEAT; }
    const opt = actBtn('Optimize', 'bulk-optimize', `Optimize: preview an issue for each of the ${n} selected files`, () => {
      const { files: fs, left } = chosen(files, 'optimize');
      S.answers = null;  // the preview names the files left out
      if (!fs.length) { S.answers = { what: 'Optimize', lines: [], left, note: 'No file to act on.' }; draw(); return; }
      if (fs.length > FILES_MAX) { S.answers = { what: 'Optimize', lines: [], left, note: `At most ${FILES_MAX} files at a time: ${fs.length} are selected. Select fewer.` }; draw(); return; }
      S.ask = { kind: 'many', repo: S.d.repo, items: fs.map((f) => { const d = draftIssue(f); return { file: f.file, title: d.title, body: d.body }; }), left };
      S.keep = { act: 'many-title', file: fs[0].file }; draw();
    });
    if (!chosen(files, 'optimize').files.length) { opt.disabled = true; opt.title = RUNNER_WHY; }
    btns.append(judge, opt, actBtn('Run', 'bulk-run', `Run the ${n} selected files now`, () => startMany('run', files)),
      actBtn('Clear', 'bulk-clear', 'Clear the selection', () => {
        S.sel.clear(); S.answers = null; if (asking('many')) S.ask = null; draw(); say('Selection cleared.');
      }));
    if (!tmodel()) btns.append(h('span', 'tests-why', `Judge: ${NO_SEAT}`));
    const a = S.answers;
    if (a) {
      const ul = h('ul', 'tests-selbar-answers');
      a.lines.forEach((l) => { const li = h('li', l.ok ? null : 'tests-refused', `${l.file}: ${l.ok ? `${a.what}, taken: ${l.text}` : `${a.what}, refused: ${l.text}`}`); li.dataset.file = l.file; ul.append(li); });
      a.left.forEach((l) => { const li = h('li', 'tests-why', `${l.file}: left out of ${a.what}: ${l.why}`); li.dataset.file = l.file; ul.append(li); });
      if (a.note) ul.append(h('li', 'tests-refused', a.note));
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
      if (bad) { say(`Type a title of one line and a text for the issue about ${bad.file} first.`); return; }
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
  // Its proof's CPU s before and after, and, beside before, the median of the file's runs since it landed.
  function numbersSaid(o) {
    if (num(o.before) === null && num(o.after) === null) return null;
    const n = num(o.sinceRuns) || 0, since = num(o.since) === null ? '' : ` (since it landed: ${one(o.since)} CPU s, the median of ${n} ${n === 1 ? 'run' : 'runs'})`;
    return `CPU s before: ${one(o.before)}${since}${num(o.after) === null ? '' : `, after: ${one(o.after)}`}`;
  }
  // One Optimize issue of a row: when it was filed, its link, its state and, landed, its fix and numbers.
  function optLine(o) {
    const h = S.ctx.h, li = h('li', 'tests-opt');
    li.dataset.issue = String(o.issue);
    li.append(h('span', 'board-from', `Filed ${S.ctx.when(o.time)} · `), S.ctx.issueLink(o),
      h('span', null, ` · ${[stateSaid(o)].concat(o.state === 'landed' ? [fixSaid(o), numbersSaid(o)] : []).filter(Boolean).join(' · ')}`));
    return li;
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

  // ---- Auto-file: the switch, the preview, the guards, the rules and the log ----
  const rulesCmd = (args) => ['control', { action: 'testrules', args, repo: S.d.repo }];
  const WHOLE1 = /^[1-9][0-9]{0,5}$/, WHOLE0 = /^[0-9]{1,6}$/, LIMIT = /^[0-9]{1,6}(\.[0-9]{1,3})?$/;
  const ONOFF = [['true', 'On'], ['false', 'Off']];
  const MEASURES = [['budget', 'CPU s over its budget'], ['usual', 'CPU s over its usual'], ['clock', 'Clock s over its CPU s'], ['flaky', 'Kept off as flaky'], ['failed', 'Failed test steps']];
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
        fig('over', String(num(t.overBudget) || 0), 'Files over budget'),
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
  function more(f) {
    const h = S.ctx.h, el = h('div', 'tests-more'), file = f.file;
    const runs = h('ul', 'tests-runs');
    runs.setAttribute('aria-label', `Runs of ${file}`);
    const opt = optRuns(f);
    list(f.runs).filter(obj).forEach((r) => {
      const li = h('li', opt.has(r) ? 'tests-run tests-run-opt' : 'tests-run');
      const cpu = num(r.cpu) === null ? 'CPU not recorded' : `${one(r.cpu)} CPU s`;
      li.append(h('span', null, `${cpu} · ${num(r.sec) === null ? 'clock not recorded' : `${one(r.sec)} s on the clock`} · `));
      if (r.whole === true) li.append(h('span', null, `whole suite${r.result === 'fail' ? ', failed' : r.result === 'ok' ? ', passed' : ''}`));
      else li.append(h('span', null, 'card '), r.issue ? S.ctx.issueLink(r) : h('span', 'issue', String(r.card || 'a card')));
      li.append(h('span', 'board-from', ` · ${S.ctx.when(r.time)}`));
      if (opt.has(r)) li.append(h('span', 'tests-run-mark', ` · the ${optRunSaid(opt.get(r))}`));
      runs.append(li);
    });
    if (!runs.children.length) runs.append(h('li', 'board-from', 'No run on record.'));
    if (f.wholeOnly === true) el.append(h('p', 'tests-fact', 'This file runs only in whole-suite runs (wholeOnly in the pack): a card\'s Test step never runs it.'));
    // As in force, or as saved here and not yet in a snapshot.
    const mine = shown(`budget:${file}`), all = shown('fileBudget'), reason = shown(`mark:${file}`) || 'none';
    const budget = f.wholeOnly === true ? 'none, it runs other test files and each of them has its own'
      : mine !== '' ? `${one(Number(mine))} CPU s, its own` : all !== '' ? `${one(Number(all))} CPU s, the project budget` : 'not known';
    el.append(h('p', 'board-head', 'Runs'), runs, h('p', 'tests-fact', `Budget: ${budget}.`), h('p', 'tests-fact', `Slow on purpose: ${reason}.`));
    // Every Optimize (and older speed-up) issue filed for it, newest first.
    const opts = optsOf(f);
    if (opts.length) {
      const ul = h('ul', 'tests-runs tests-opts');
      ul.setAttribute('aria-label', `Optimize issues of ${file}`);
      opts.forEach((o) => ul.append(optLine(o)));
      el.append(h('p', 'board-head', 'Optimize issues'), ul);
    }
    el.append(rowActions(f));
    // A runner (wholeOnly) is held to no budget, so a budget or a slow-on-purpose mark set here would never apply.
    if (f.wholeOnly === true) return el;
    // The editor of the budget, or of the mark, shows once picked from More, and while a value typed, refused or saved
    // here is in it.
    const editing = (what, key) => S.edit.has(`${dk(file)}|${what}`) || S.drafts.has(dk(key)) || S.pending.has(dk(key)) || (S.refused && S.refused.dk === dk(key));
    if (editing('budget', `budget:${file}`)) {
      el.append(row('budget', 'Set a budget for this file', 'CPU s in place of the project budget', PACK, ...setting(`budget:${file}`, {
        act: 'file-budget', file, label: `Budget of ${file}`, type: 'number', placeholder: 'None', clear: 'Clear',
        check: budgetCheck, send: (v) => control(v === '' ? ['file-budget-clear', file] : ['file-budget', file, v]),
        said: (v) => (v === '' ? `${file} has no budget of its own` : `budget of ${file} now ${v} CPU s`) })));
    }
    if (editing('mark', `mark:${file}`)) {
      el.append(row('mark', 'Mark as slow on purpose', 'No budget holds this file', PACK, ...setting(`mark:${file}`, {
        act: 'slow-mark', file, label: `Why ${file} is slow on purpose`, placeholder: 'Why it is slow on purpose', clear: 'Clear', ask: true,
        check: (v, set) => (v === '' ? (set === '' ? 'Type why the file is slow on purpose first.' : null) : null),
        send: (v) => control(v === '' ? ['slow-mark-clear', file] : ['slow-mark', file, v]),
        said: (v) => (v === '' ? `${file} is no longer marked slow on purpose` : `${file} is marked slow on purpose`) })));
    }
    return el;
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
      marks(f).forEach(([k, words, tone]) => chips.append(k === 'issue' ? issueOf(f, any) : k === 'runner' || k === 'whole' ? h('span', 'tests-quiet', words) : S.ctx.chip(words, tone)));
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
        if (num(f.caught) !== null) caught.title = `Changed to pass: ${num(f.changedToPass) || 0}`;
        tr.append(fileCell, cell(one(f.cpu), 'tests-num'), cell(one(f.median), 'tests-num'), cell(pct(f.change), 'tests-num'),
          cell(bars(f)), cell(num(last.clockPerCpu) === null ? '—' : `${one(last.clockPerCpu)}×`, 'tests-num'), cell(count === null ? '—' : String(count), 'tests-num'), took, caught, cell(chips));
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
    el.append(row('budget', 'CPU budget for a test file', 'A file over this shows as "Over budget".', PACK,
      ...setting('fileBudget', { act: 'budget', label: 'CPU budget for a test file', type: 'number', placeholder: '8',
        check: (v) => (BUDGET.test(v) ? null : 'A budget is CPU seconds: a number of 1 or more, as 8 or 12.5.'),
        send: (v) => control(['budget', v]), said: (v) => `CPU budget for a test file now ${v} CPU s` })));
    const files = Object.entries(obj(s.files) || {}).filter(([, v]) => obj(v));
    const items = (pick, words) => {
      const ul = h('ul', 'tests-list'), got = files.filter(([, v]) => pick(v) !== null && pick(v) !== undefined);
      got.forEach(([f, v]) => ul.append(h('li', null, `${f}: ${words(pick(v))}`)));
      if (!got.length) ul.append(h('li', 'board-from', 'None'));
      return ul;
    };
    el.append(row('budgets', 'Budgets of single files', 'Set them on a row of the table.', PACK, items((v) => num(v.budget), (b) => `${one(b)} CPU s`)));
    el.append(row('purpose', 'Files slow on purpose', 'No budget holds them. Each has a reason.', PACK, items((v) => (typeof v.slowOnPurpose === 'string' ? v.slowOnPurpose : null), (r) => r)));
    // #457's rows, only when the snapshot names them.
    const box = obj(s.box);
    if (box) el.append(row('box', 'Hard box for each test file', 'A test file cannot use more CPU or memory than its test slot gives.', 'the engine (no setting)', h('span', 'board-value', box.on === false ? 'Off' : 'On')));
    if (typeof s.slowIssues === 'boolean') {
      el.append(row('off-card-runs', 'Take a file off card runs', 'A file over its budget in 2 card runs in a row runs only in the full test suite, and Conveyor files an issue for it.', PACK,
        ...setting('slowIssues', { act: 'slow-issues', label: 'Take a file off card runs', choices: [['true', 'On'], ['false', 'Off']],
          check: () => null, send: (v) => control(['slow-issues', v]), said: (v) => `Take a file off card runs is now ${v === 'true' ? 'On' : 'Off'}` })));
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
        'Conveyor records the CPU time of each test file when the test command prints a "TESTRUN sec" line for it. The helper conveyor/tools/testtime.sh prints this line. The table starts when the first card with file times runs its tests.'));
      if (gone.length) parts.push(removed(gone));
      if (S.sel.size) parts.push(selBar(files));
      parts.push(recent(files, gone));
      set.append(actionsHead(), limits(), autofile());
    }
    parts.push(set);
    const note = h('p', 'board-note tests-note');
    note.setAttribute('aria-live', 'polite');
    const was = el.querySelector('.tests-note');
    if (was) note.textContent = was.textContent;
    const root = h('div', S.sel.size ? 'tests tests-has-selbar' : 'tests');
    root.append(...parts);
    // The table scrolls sideways when wider than the panel (app.css): a new snapshot keeps its place.
    const side = el.querySelector('.tests-scroll'), left = side ? side.scrollLeft : 0;
    el.replaceChildren(root, note);
    const wide = root.querySelector('.tests-scroll');
    if (wide) wide.scrollLeft = left;
    if (S.busy) {
      root.querySelectorAll('button, input, select, textarea').forEach((b) => {
        if (!['filter', 'open', 'goto', 'copy', 'search', 'select', 'select-all', 'more'].includes(b.dataset.act) && !/^(sort|figure)-/.test(b.dataset.act || '')) b.disabled = true;
      });
    }
    if (keep) {
      const scope = keep.file ? Array.from(el.querySelectorAll('[data-file]')).filter((x) => x.dataset.file === keep.file) : [el];
      const again = scope.map((x) => x.querySelector(`[data-act="${keep.act}"]`)).find(Boolean);
      if (again && !again.disabled) again.focus({ preventScroll: true });
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
      S.sel.clear(); S.answers = null; S.menu = null; S.edit.clear();
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
      S.started.forEach((s, k) => { if (!s.id || actions().some((a) => a.id === s.id)) S.started.delete(k); });
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
