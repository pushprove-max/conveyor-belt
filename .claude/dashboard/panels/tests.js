// SPDX-License-Identifier: Apache-2.0
// The Tests page (#520; the owner chose mockup A, with mockup B's column "against its own median"): a tab of its own,
// after Belt 3D. It shows one project at a time: with more than one on the host, the machine head's Show picks it, as
// on the Rules tab, and the heading names it ("Tests: sample").
// First, the figures: files with a CPU time, files over budget, files slower than usual, files that wait more than
// they work (their last run took more than twice its CPU time on the clock: WAITS), and the card test steps of the
// 7 days: their slot wait and their run time.
// Then the table, one row a test file (every test file of main's checkout, run or not): file, CPU s now, median,
// change against its own median, its last runs as bars (oldest first), clock against CPU, runs on record, the clock
// time its newest run took (Last run took, with that run's date and time on hover), and its status chips (Over
// budget, Slower than usual, Faster, Waits, Flaky, Fails often, Has an issue, Slow on purpose, Runs other test files,
// Whole suite only, Never run). A file the pack marks wholeOnly (a runner that starts other test files whole, each of
// them with its own budget) is held to no budget: it has "Runs other test files" in place of a budget, is never Over
// budget, Slower than usual or Waits, and has no "File an issue: speed up". A search box over it keeps the rows whose path holds its text (any case); filter chips, each with its count,
// show one status alone; the two apply together. Each column heading sorts the table by that column (file names A to
// Z, any other highest first; a second click reverses it, and an arrow shows which). With no sort picked, the rows
// that need a look (over budget and not slow on purpose, slower than usual, waits, flaky or fails often) come first,
// then the highest CPU s. A row opens to show its runs, each with a link to its card's issue or marked "whole suite"
// with its result, its budget and its mark, and the actions that run at once ("now"): Set a budget for this file,
// Mark as slow on purpose (it asks for the reason) and Clear for each.
// Last, the panel Test limits. Each row names where it saves: Load limit in the host file (this machine, all
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
// The actions (#521; mockup A for the row's actions, the Tests model, the box and the results, mockup C for
// Auto-file). The Board calls the control record's tests (`conveyor.sh control tests`) "the Tests model": its
// strip-down test (dashboard.test.sh) keeps the engine's retired word for it out of the page. Each
// action button has a mark: "now" (it runs now and files no issue) or "issue" (it files an issue, as it changes code);
// a button that only opens a view has none, and one legend line says so. An opened row has, marked "now": Judge this
// test and Explain the slowdown (a session on the Tests model: POST control {action: testaction, args: [judge |
// explain, file]}), Run this file now (testaction run: no session, no model), Put back a flaky case (its flaky issue
// closed, test-close: the case runs on cards again), Keep a case off (flaky-off: `conveyor.sh flaky off`, which files no issue), and Close its
// issue as done (test-close, with the file's before and after numbers as its comment); marked "issue": File an issue:
// speed up, split the file, merge with a second file, delete the test. Each of these shows a preview first (title and
// body, with the measured numbers and the judge's kept verdict, both editable; no Done-when line), and files (POST
// control {action: test-issue, args: [file, title, body]}: `conveyor.sh testissue`, which keeps it as the file's issue) only on its second button; Cancel files nothing. With no Tests
// model, Judge and Explain are disabled and say "Set the Tests model first."
// "Model for Tests actions": CLI, model (with Other… for a typed name) and effort, as the Rules tab's roles; a pick
// says Unsaved, Save sends POST control {action: tests, args: [cli, model, effort] or [default]}, Cancel puts back the
// one in force.
// While an action runs, its row shows a bar and the time used against the action's limit, and a box with its text
// as the snapshot brings it (kept here, so a text the snapshot cut to its end loses nothing seen before), with Stop
// (testaction stop <id>, that action alone) and Copy. Ended, the box shows its result with its time, CLI, model and
// effort, and a judge's verdict word as a chip. Results of actions lists each kept action, newest first, with View
// and Copy, and Stop on a running one.
// Auto-file: the one switch (Off by default; "Turn on" shows the preview, the matches of the rules' last run, each
// with its guard's result, and asks for a second click), the guards and each rule's fields (each Unsaved until Save posts
// `conveyor.sh testrules guard|set`), and the log of what the rules filed and stopped.
// Its part (dashboard.sh, tests): {repo (null: none is steered), tests (the snapshot's: settings, rules, files, slower,
// totals; null from a snapshot without it), machine ({maxLoad, unread, cores, load}), testActions ({limit, actions, allowed:
// the pack's models by CLI, offered for a CLI that lists none}), control (the control record: its tests, the Tests model),
// clis (the host's CLIs, {models: null when it lists none, efforts} each), flaky ([{case, count, issue, files}]), repos, others}.
(function () {
  'use strict';
  const LOAD = /^[0-9]{1,6}(\.[0-9]{1,3})?$/;  // a load limit, as dashboard_server.py's LOAD and `conveyor.sh machine load` take it (1 or more)
  const BUDGET = /^[1-9][0-9]{0,5}(\.[0-9]{1,3})?$/;  // CPU seconds, as dashboard_server.py's BUDGET and `conveyor.sh test-settings` take them
  const REASON_MAX = 300;  // a reason, as dashboard_server.py's said_ok takes it
  const WAITS = 2;         // a file waits more than it works when its last run took more than this times its CPU time
  const FAILS = 2;         // a file fails often when this many test steps or more failed in it
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
    shown: new Map(),    // the action a row's box shows, by dk(file): its id
    viewed: null,        // the result opened under Results of actions: its id
    ask: null,           // a preview open: {kind: issue | close | keep | on, file, title, body, case, why}
    stopping: new Set() };  // the ids of the actions a Stop was sent for

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
  // The clock time of a run: "48 s", "8 min 7 s".
  const clockTook = (s) => { if (num(s) === null) return '—'; const r = Math.round(s); return r < 60 ? `${r} s` : `${Math.floor(r / 60)} min ${r % 60} s`; };
  // The table's columns: key, heading, and the value a sort by it reads (null sorts last both ways). A first click
  // sorts the file names A to Z and every other column highest first.
  const COLS = [
    ['file', 'File', (f) => f.file],
    ['cpu', 'CPU s now', (f) => num(f.cpu)],
    ['median', 'Median', (f) => num(f.median)],
    ['change', 'Against its median', (f) => num(f.change)],
    ['runs', 'Last runs', (f) => { const c = list(f.runs).filter(obj).map((r) => num(r.cpu)).filter((x) => x !== null); return c.length ? Math.max(...c) : null; }],
    ['clock', 'Clock / CPU', (f) => num((obj(f.lastRun) || {}).clockPerCpu)],
    ['count', 'Runs', (f) => (list(f.runs).length ? num(f.timedRuns) || 0 : null)],
    ['took', 'Last run took', (f) => num((obj(f.lastRun) || {}).sec)],
    ['status', 'Status', (f) => (look(f) ? 100 : 0) + marks(f).length]];

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
  // words of a button that empties it), ask (a value that is empty in force is asked for by this button first), check(v,
  // set) (why it is not sent, or null), send(v, set) ([path, body]) and said(v) (what was saved, in words).
  function setting(key, o) {
    const h = S.ctx.h, k = dk(key), set = shown(key);
    if (o.ask && set === '' && !S.drafts.has(k)) {
      return [button(o.ask, 'btn-quiet', o.act, o.ask, () => { S.drafts.set(k, ''); S.keep = { act: `${o.act}-field`, file: o.file }; draw(); })];
    }
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
  const KINDS = [['speed', 'File an issue: speed up'], ['split', 'File an issue: split the file'], ['merge', 'File an issue: merge with a second file'], ['delete', 'File an issue: delete the test']];
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

  // A button with its mark: now (it runs now and files no issue) or issue (it files an issue).
  function marked(text, mark, act, label, fn) {
    const b = button(text, 'btn-quiet tests-act', act, label, fn), c = S.ctx.chip(mark, mark === 'now' ? 'ok' : 'info');
    c.classList.add('tests-mark');
    b.dataset.mark = mark;
    b.append(' ', c);
    return b;
  }
  // One action sent: POST control {action, args, repo}; then(text, at) on a yes, and the answer or the refusal said.
  function send(action, args, said, then) {
    if (S.busy) { say('Wait: the build machine did not answer the last change yet.'); return; }
    const repo = S.d.repo;
    S.busy = true; draw(); say('Sending…');
    S.ctx.post('control', { action, args, repo }).then((r) => r.text().then((t) => {
      const at = Number(r.headers && typeof r.headers.get === 'function' ? r.headers.get('X-Answered-At') : NaN);
      return [r.ok, String(t).trim() || `the build machine answered ${r.status}`, Number.isFinite(at) && at > 0 ? at * 1000 : null];
    }), () => [false, 'the build machine did not answer', null]).then(([ok, text, at]) => {
      S.busy = false;
      if (ok && then && repo === S.d.repo) then(text, at);
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
      if (ID.test(id)) S.shown.set(dk(file), id);
      S.open.add(file);
    });
  }
  const stop = (a) => send('testaction', ['stop', a.id], (t) => `Stop sent: ${ACTS[a.action] || a.action}, ${a.file}. ${t}`, () => S.stopping.add(a.id));
  // How an action ended: its state and time, when, its CLI, model and effort (a run has none), and its verdict or result.
  function result(a) {
    const h = S.ctx.h, t0 = Date.parse(a.start || ''), t1 = Date.parse(a.end || '');
    const took = Number.isNaN(t0) || Number.isNaN(t1) ? '' : ` in ${mmss((t1 - t0) / 1000)}`;
    const out = [h('span', 'tests-result', `${ENDED[a.state] || String(a.state)}${took} · ${S.ctx.when(a.end || a.start)} · ${a.action === 'run' ? 'engine command, no session' : `${a.cli} · ${a.model} · ${a.effort}`}`)];
    if (a.action === 'judge' && typeof a.verdict === 'string') out.push(S.ctx.chip(a.verdict, a.verdict === 'keep' ? 'ok' : a.verdict === 'no verdict' ? 'quiet' : 'warn'));
    if (a.action === 'run' && typeof a.result === 'string') {  // the run's result: fail, or its other value
      const bad = a.result === 'fail';
      out.push(S.ctx.chip(`${bad ? 'Failed' : 'Passed'}${num(a.cpu) !== null ? `, ${one(a.cpu)} CPU s` : ''}`, bad ? 'bad' : 'ok'));
    }
    if (typeof a.reason === 'string' && a.reason) out.push(h('span', 'board-from', a.reason));
    return out;
  }
  const running = (a) => a.state === 'running';
  // The box of one action: running, a bar and the time used against its limit, its text so far, Stop and Copy; ended,
  // its result, its text and Copy.
  function box(a) {
    const h = S.ctx.h, el = h('div', 'tests-box'), head = h('div', 'tests-box-head'), name = ACTS[a.action] || String(a.action);
    el.dataset.id = a.id;
    head.append(h('span', 'board-label', name));
    if (running(a)) {
      const lim = limitOf(a), u = used(a), bar = h('progress', 'tests-progress');
      if (lim) { bar.max = lim; bar.value = Math.min(u, lim); }
      bar.setAttribute('aria-label', `Time used: ${name}`);
      head.append(bar, h('span', 'board-from', lim ? `${mmss(u)} of the ${mmss(lim)} time limit` : `${mmss(u)} used`));
    } else head.append(...result(a));
    const text = S.texts.get(a.id) || '';
    const out = h('pre', 'tests-out', text || (running(a) ? 'Started. Its text shows here as it comes.' : 'No text.'));
    out.setAttribute('aria-live', 'polite');
    const btns = h('div', 'tests-box-btns');
    if (running(a) && ID.test(a.id)) {
      const b = button(S.stopping.has(a.id) ? 'Stopping…' : 'Stop', 'btn-quiet', 'stop', `Stop: ${name}, ${a.file}`, () => stop(a));
      btns.append(b);
    }
    btns.append(button('Copy', 'btn-quiet', 'copy', `Copy the text: ${name}, ${a.file}`, () => copy(text)));
    el.append(head, out, btns);
    if (a.textCut === true && !text) el.append(h('p', 'board-from', 'The text is long: the build machine sends its end only.'));
    return el;
  }
  // The action a row's box shows: the one started here, else one of the file's that runs, else its newest.
  function rowAction(file) {
    const all = actions().filter((a) => a.file === file), want = S.shown.get(dk(file));
    const st = S.started.get(dk(file));
    return (want && all.find((a) => a.id === want)) || st || all.find(running) || all[0] || null;
  }
  function draftIssue(f, kind) {
    const file = f.file, v = verdictOf(file), runs = list(f.runs).filter(obj), last = obj(f.lastRun) || {};
    const title = { speed: `Speed up the test file ${file}`, split: `Split the test file ${file}`, merge: `Merge the test file ${file} with a second test file`, delete: `Delete the test file ${file}` }[kind];
    const ask = { speed: 'Make this test file faster. Keep what it tests.', split: 'Split this test file into smaller files. Keep what it tests.',
      merge: 'Merge this test file with a second test file that tests the same behaviour. Second file: (name it here)', delete: 'Delete this test file. Name here the test that proves what it tests.' }[kind];
    const lines = [ask, '', 'What the Board measured:',
      `- CPU s in its last run: ${one(f.cpu)}`,
      `- Median of its runs: ${one(f.median)} CPU s (${pct(f.change)} against its median)`,
      f.wholeOnly === true ? '- Budget: none, it runs other test files' : `- Budget: ${one(f.budget)} CPU s`,
      `- Clock / CPU in its last run: ${num(last.clockPerCpu) === null ? '—' : `${one(last.clockPerCpu)}×`}`,
      `- Runs on record: ${num(f.timedRuns) || 0}. Test steps that failed in it: ${num(f.failedSteps) || 0}. Flaky entries: ${num(f.flaky) || 0}.`,
      `- Last runs, newest first: ${runs.map((r) => `${one(r.cpu)} CPU s (card ${r.card})`).join(', ') || 'none'}`];
    if (v) lines.push('', `The judge's verdict (${v.end || v.start}, ${v.cli} · ${v.model} · ${v.effort}): ${v.verdict}.`);
    return { kind: 'issue', repo: S.d.repo, file, title, body: lines.join('\n') };
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
        marked('File this issue', 'issue', 'issue-file', `File this issue about ${file}`, () => {
          const t = a.title.trim(), b = a.body.trim();
          if (!t || /[\r\n]/.test(t)) { say('Type a title of one line first.'); return; }
          if (!b) { say('Type the text of the issue first.'); return; }
          send('test-issue', [file, t, b], (url) => `Filed: ${url}`, () => { S.ask = null; });
        }), cancel('issue-cancel'));
    } else if (a.kind === 'close') {
      el.append(h('p', 'board-head', `Close #${f.issue} as done, with this comment.`),
        field('close-comment', `Comment that closes #${f.issue}`, a.body, (v) => { a.body = v; }),
        marked(`Close #${f.issue}`, 'now', 'close-confirm', `Close #${f.issue} as done`, () => {
          const c = a.body.trim();
          if (!c) { say('Type the comment first.'); return; }
          send('test-close', [String(f.issue), c], () => `Closed #${f.issue} as done.`, () => { S.ask = null; });
        }), cancel('close-cancel'));
    } else if (a.kind === 'keep') {
      el.append(h('p', 'board-head', 'Keep a case of this file off card test steps. The full suite and the whole test on main still run it.'),
        field('keep-case', `Case of ${file} to keep off`, a.case, (v) => { a.case = v; }, { placeholder: 'The name of the case' }),
        field('keep-why', 'Why it is kept off', a.why, (v) => { a.why = v; }, { placeholder: 'Why it is kept off' }),
        marked('Keep it off', 'now', 'keep-confirm', `Keep the case off: ${file}`, () => {
          const c = `${CASE_FILE.test(file) ? RUNNER : file}: ${a.case.trim()}`, why = a.why.trim();
          if (!a.case.trim() || !why) { say('Type the case and why first.'); return; }
          if (c.length > SAID_MAX) { say(`The file and case are more than ${SAID_MAX} characters.`); return; }
          send('flaky-off', [c, why], () => `Kept off: ${c}.`, () => { S.ask = null; });
        }), cancel('keep-cancel'));
    }
    return el;
  }
  // The actions of an opened row, the preview open on it, and the box of its action.
  function rowActions(f) {
    const h = S.ctx.h, file = f.file, el = h('div', 'tests-acts'), noSeat = !tmodel();
    const now = h('div', 'tests-act-row'), iss = h('div', 'tests-act-row');
    ['judge', 'explain', 'run'].forEach((how) => {
      const b = marked(ACTS[how], 'now', how, `${ACTS[how]}: ${file}`, () => start(how, file));
      if (how !== 'run' && noSeat) { b.disabled = true; b.title = NO_SEAT; }
      now.append(b);
    });
    if (noSeat) now.append(h('span', 'tests-why', `Judge and Explain: ${NO_SEAT}`));
    // A flaky case is kept off until its flaky issue closes: Put back closes it. A case shows on each file it counts for
    // (the snapshot's files: a runner's case on its case file too).
    list(S.d.flaky).filter((c) => obj(c) && typeof c.case === 'string' && c.case.includes(': ') && list(c.files).includes(file)).forEach((c) => {
      const name = c.case.slice(c.case.indexOf(': ') + 2);
      const b = marked(`Put back a flaky case: ${name}`, 'now', 'flaky-back', `Put back the flaky case ${c.case}`, () => send('test-close',
        [String(c.issue), `Put back from the Board's Tests page: the case "${name}" runs on card test steps again.`.slice(0, SAID_MAX)], () => `Put back: ${c.case}. Its flaky issue #${c.issue} is closed.`));
      if (num(c.issue) === null) { b.disabled = true; b.title = 'It has no flaky issue to close. It stays off until its entries are 30 days old.'; }
      now.append(b);
    });
    now.append(marked('Keep a case off', 'now', 'flaky-off', `Keep a case of ${file} off card test steps`, () => {
      S.ask = { kind: 'keep', repo: S.d.repo, file, case: '', why: '' }; S.keep = { act: 'keep-case', file }; draw();
    }));
    if (num(f.issue) !== null) {
      now.append(marked('Close its issue as done', 'now', 'close-done', `Close #${f.issue} as done`, () => {
        const before = num(f.usual) === null ? f.median : f.usual;
        S.ask = { kind: 'close', repo: S.d.repo, file, body: `Done: ${file} used ${one(before)} CPU s before (its usual) and ${one(f.cpu)} CPU s in its last run. Closed from the Board's Tests page.` };
        S.keep = { act: 'close-comment', file }; draw();
      }));
    }
    // A runner (wholeOnly) is held to no budget: its time is its files' time, so no issue asks to speed it up.
    KINDS.filter(([k]) => !(k === 'speed' && f.wholeOnly === true)).forEach(([k, words]) => iss.append(marked(words, 'issue', `issue-${k}`, `${words}: ${file}`, () => { S.ask = draftIssue(f, k); S.keep = { act: 'issue-title', file }; draw(); })));
    el.append(h('p', 'board-head', 'Actions'), now, iss);
    const p = preview(f);
    if (p) el.append(p);
    const a = rowAction(file);
    if (a) el.append(box(a));
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
      h('p', 'tests-legend', 'Marks: "now": the action runs now on the build machine and files no issue. "issue": the action files an issue, because it changes code. A button with no mark opens a view.'),
      row('tmodel', 'Model for Tests actions', 'The CLI, model and effort of Judge this test and Explain the slowdown. Run this file now needs none.', null, ...seatCtl()));
    return el;
  }
  // ---- Results of actions: each kept action, newest first ----
  function results() {
    const h = S.ctx.h, el = h('section', 'tests-results'), all = actions();
    el.append(h('h3', 'board-head', 'Results of actions'));
    if (!all.length) { el.append(h('p', 'board-from', 'No action ran yet. An action that you start on a row shows here, and stays here.')); return el; }
    const ul = h('ul', 'tests-results-list');
    all.forEach((a) => {
      const li = h('li', 'tests-result-row'), line = h('div', 'tests-result-line'), name = ACTS[a.action] || String(a.action);
      li.dataset.id = a.id;
      line.append(h('span', 'board-from', S.ctx.when(a.start)), h('span', 'board-label', name), h('span', 'tests-result-file', String(a.file)));
      if (running(a)) {
        const lim = limitOf(a);
        line.append(h('span', 'board-from', `${a.action === 'run' ? 'engine command, no session' : `${a.cli} · ${a.model} · ${a.effort}`} · Runs: ${mmss(used(a))}${lim ? ` of ${mmss(lim)}` : ''}`));
      } else line.append(...result(a));
      line.append(button(S.viewed === a.id ? 'Hide' : 'View', 'btn-quiet', 'view', `${S.viewed === a.id ? 'Hide' : 'View'}: ${name}, ${a.file}`, () => { S.viewed = S.viewed === a.id ? null : a.id; draw(); }));
      if (running(a) && ID.test(a.id)) line.append(button(S.stopping.has(a.id) ? 'Stopping…' : 'Stop', 'btn-quiet', 'stop', `Stop: ${name}, ${a.file}`, () => stop(a)));
      else line.append(button('Copy', 'btn-quiet', 'copy', `Copy the text: ${name}, ${a.file}`, () => copy(S.texts.get(a.id) || '')));
      li.append(line);
      if (S.viewed === a.id) li.append(box(a));
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
      ? marked('Turn off', 'now', 'auto-off', 'Turn auto-file off', () => sendRule('rules-on', ['off'], 'false', 'Auto-file is now Off.'))
      : marked('Turn on', 'now', 'auto-on', 'Turn auto-file on: shows the preview first', () => { S.ask = { kind: 'on', repo: S.d.repo }; S.keep = { act: 'auto-on-confirm' }; draw(); say('Check the preview. Then click "Turn on: confirm".'); });
    el.append(row('auto-switch', 'Auto-file test issues', 'One switch for all rules. Off: the rules file no issue.', PACK, h('span', 'board-value', on ? 'On' : 'Off'), confirm ? null : sw));
    if (confirm && !on) {
      const c = h('div', 'tests-preview');
      c.append(h('p', 'board-head', 'Check the preview below. With the switch on, the rules file such issues after each card test step.'),
        marked('Turn on: confirm', 'now', 'auto-on-confirm', 'Turn auto-file on', () => { S.ask = null; sendRule('rules-on', ['on'], 'true', 'Auto-file is now On.'); }),
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
  function figures(files) {
    const h = S.ctx.h, t = obj(tests().totals) || {}, st = obj(t.steps) || {}, el = h('div', 'rules-stats tests-figs');
    const fig = (key, value, label) => { const x = h('div', 'rules-stat'); x.dataset.figure = key; x.append(h('span', 'rules-big', value), h('span', 'rules-what', label)); return x; };
    const steps = num(st.count) || 0, took = (s) => (num(s) === null ? '—' : S.ctx.took(s));
    if (files.length) {
      el.append(fig('files', String(num(t.files) === null ? files.length : t.files), 'Files with a CPU time'),
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
    const top = Math.max(...runs.map((r) => r.cpu), 0);
    runs.forEach((r) => { const b = h('span', 'tests-bar'); b.style.transform = `scaleY(${top > 0 ? Math.max(0.04, r.cpu / top) : 0})`; el.append(b); });
    el.setAttribute('role', 'img');
    el.setAttribute('aria-label', runs.length ? `Last runs, oldest first: ${runs.map((r) => one(r.cpu)).join(', ')} CPU s` : 'No runs');
    return el;
  }
  function more(f) {
    const h = S.ctx.h, el = h('div', 'tests-more'), file = f.file;
    const runs = h('ul', 'tests-runs');
    runs.setAttribute('aria-label', `Runs of ${file}`);
    list(f.runs).filter(obj).forEach((r) => {
      const li = h('li', 'tests-run');
      const cpu = num(r.cpu) === null ? 'CPU not recorded' : `${one(r.cpu)} CPU s`;
      li.append(h('span', null, `${cpu} · ${num(r.sec) === null ? 'clock not recorded' : `${one(r.sec)} s on the clock`} · `));
      if (r.whole === true) li.append(h('span', null, `whole suite${r.result === 'fail' ? ', failed' : r.result === 'ok' ? ', passed' : ''}`));
      else li.append(h('span', null, 'card '), r.issue ? S.ctx.issueLink(r) : h('span', 'issue', String(r.card || 'a card')));
      li.append(h('span', 'board-from', ` · ${S.ctx.when(r.time)}`));
      runs.append(li);
    });
    if (!runs.children.length) runs.append(h('li', 'board-from', 'No run on record.'));
    if (f.wholeOnly === true) el.append(h('p', 'tests-fact', 'This file runs only in whole-suite runs (wholeOnly in the pack): a card\'s Test step never runs it.'));
    // As in force, or as saved here and not yet in a snapshot.
    const mine = shown(`budget:${file}`), all = shown('fileBudget'), reason = shown(`mark:${file}`) || 'none';
    const budget = f.wholeOnly === true ? 'none, it runs other test files and each of them has its own'
      : mine !== '' ? `${one(Number(mine))} CPU s, its own` : all !== '' ? `${one(Number(all))} CPU s, the project budget` : 'not known';
    el.append(h('p', 'board-head', 'Runs'), runs, h('p', 'tests-fact', `Budget: ${budget}.`), h('p', 'tests-fact', `Slow on purpose: ${reason}.`));
    const now = () => S.ctx.chip('now', 'info');
    // A runner (wholeOnly) is held to no budget, so a budget or a slow-on-purpose mark set here would never apply.
    if (f.wholeOnly === true) { el.append(rowActions(f)); return el; }
    el.append(row('budget', 'Set a budget for this file', 'CPU s in place of the project budget', PACK, now(), ...setting(`budget:${file}`, {
      act: 'file-budget', file, label: `Budget of ${file}`, type: 'number', placeholder: 'None', clear: 'Clear',
      check: budgetCheck, send: (v) => control(v === '' ? ['file-budget-clear', file] : ['file-budget', file, v]),
      said: (v) => (v === '' ? `${file} has no budget of its own` : `budget of ${file} now ${v} CPU s`) })));
    el.append(row('mark', 'Mark as slow on purpose', 'No budget holds this file', PACK, now(), ...setting(`mark:${file}`, {
      act: 'slow-mark', file, label: `Why ${file} is slow on purpose`, placeholder: 'Why it is slow on purpose', clear: 'Clear', ask: 'Mark as slow on purpose',
      check: (v, set) => (v === '' ? (set === '' ? 'Type why the file is slow on purpose first.' : null) : null),
      send: (v) => control(v === '' ? ['slow-mark-clear', file] : ['slow-mark', file, v]),
      said: (v) => (v === '' ? `${file} is no longer marked slow on purpose` : `${file} is marked slow on purpose`) })));
    el.append(rowActions(f));
    return el;
  }
  function table(files) {
    const h = S.ctx.h, el = h('section', 'tests-files');
    const counts = Object.fromEntries(MARKS.map(([k]) => [k, files.filter((f) => marks(f).some((m) => m[0] === k)).length]));
    if (S.filter !== 'all' && !counts[S.filter]) S.filter = 'all';
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
    // With no sort picked, the rows that need a look first; the snapshot's order (the highest CPU s first) inside each.
    // A sort keeps that order among equal values.
    let shownFiles = files.map((f, i) => [f, i]).filter(([f]) => (S.filter === 'all' || marks(f).some((m) => m[0] === S.filter)) && (!q || f.file.toLowerCase().includes(q)))
      .sort((a, b) => (look(b[0]) - look(a[0])) || (a[1] - b[1])).map(([f]) => f);
    const col = S.sort && COLS.find((c) => c[0] === S.sort.key);
    if (col) {
      const by = col[2], up = S.sort.dir === 'asc' ? 1 : -1;
      shownFiles = shownFiles.slice().sort((a, b) => {
        const x = by(a), y = by(b);
        if (x === null || y === null) return (x === null) - (y === null);
        return up * (typeof x === 'string' ? x.localeCompare(y) : x - y);
      });
    }
    const t = h('table', 'tests-table'), head = h('tr');
    COLS.forEach(([key, words]) => {
      const th = h('th'), on = col && col[0] === key, dir = on ? S.sort.dir : null;
      th.scope = 'col';
      th.setAttribute('aria-sort', on ? (dir === 'asc' ? 'ascending' : 'descending') : 'none');
      const b = button(`${words}${on ? (dir === 'asc' ? ' ▲' : ' ▼') : ''}`, 'btn-quiet tests-sort', `sort-${key}`, `Sort by ${words}`, () => {
        S.sort = { key, dir: on ? (dir === 'asc' ? 'desc' : 'asc') : key === 'file' ? 'asc' : 'desc' };
        S.keep = { act: `sort-${key}` }; draw();
        say(`Sorted by ${words}, ${S.sort.dir === 'asc' ? (key === 'file' ? 'A to Z' : 'lowest first') : key === 'file' ? 'Z to A' : 'highest first'}`);
      });
      th.append(b); head.append(th);
    });
    const thead = h('thead'); thead.append(head);
    const body = h('tbody');
    if (!shownFiles.length) { const tr = h('tr', 'tests-none'), td = h('td', 'board-from', 'No test file matches'); td.colSpan = COLS.length; tr.append(td); body.append(tr); }
    shownFiles.forEach((f) => {
      const open = S.open.has(f.file), tr = h('tr', 'tests-row'), last = obj(f.lastRun) || {};
      tr.dataset.file = f.file;
      const name = button(f.file, 'btn-quiet tests-name', 'open', `${f.file}: ${open ? 'close' : 'open'} its runs`, () => { if (S.open.has(f.file)) S.open.delete(f.file); else S.open.add(f.file); S.keep = { act: 'open', file: f.file }; draw(); });
      name.setAttribute('aria-expanded', String(open));
      const cell = (x, cls) => { const td = h('td', cls); td.append(x); return td; };
      const chips = h('span', 'rules-marks');
      marks(f).forEach(([, words, tone]) => chips.append(S.ctx.chip(words, tone)));
      // The newest run's clock time, with its date and time on hover.
      const took = cell(clockTook(last.sec), 'tests-num');
      if (num(last.sec) !== null && typeof last.time === 'string' && !Number.isNaN(Date.parse(last.time))) {
        took.title = `${new Date(last.time).toLocaleString()}, ${last.whole === true ? 'whole suite' : 'card'}`;
      }
      const count = COLS.find((c) => c[0] === 'count')[2](f);
      tr.append(cell(name, 'tests-file'), cell(one(f.cpu), 'tests-num'), cell(one(f.median), 'tests-num'), cell(pct(f.change), 'tests-num'),
        cell(bars(f)), cell(num(last.clockPerCpu) === null ? '—' : `${one(last.clockPerCpu)}×`, 'tests-num'), cell(count === null ? '—' : String(count), 'tests-num'), took, cell(chips));
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
    const t = tests(), files = list(t && t.files).filter((f) => obj(f) && typeof f.file === 'string');
    const parts = [];
    if (!t) parts.push(h('p', 'warn-note', 'Conveyor could not read the test figures of this project. Its pack does not read, or the build machine runs an older Conveyor.'));
    else {
      parts.push(figures(files), actionsHead());
      parts.push(files.length ? table(files) : S.ctx.state('empty', 'No file times for this project',
        'Conveyor records the CPU time of each test file when the test command prints a "TESTRUN sec" line for it. The helper conveyor/tools/testtime.sh prints this line. The table starts when the first card with file times runs its tests.'));
      parts.push(results(), autofile());
    }
    parts.push(limits());
    const note = h('p', 'board-note tests-note');
    note.setAttribute('aria-live', 'polite');
    const was = el.querySelector('.tests-note');
    if (was) note.textContent = was.textContent;
    const root = h('div', 'tests');
    root.append(...parts);
    // The table scrolls sideways when wider than the panel (app.css): a new snapshot keeps its place.
    const side = el.querySelector('.tests-scroll'), left = side ? side.scrollLeft : 0;
    el.replaceChildren(root, note);
    const wide = root.querySelector('.tests-scroll');
    if (wide) wide.scrollLeft = left;
    if (S.busy) root.querySelectorAll('button, input, select, textarea').forEach((b) => { if (!['filter', 'open', 'view', 'copy', 'search'].includes(b.dataset.act) && !(b.dataset.act || '').startsWith('sort-')) b.disabled = true; });
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
    if (S.repo !== undefined && view.repo !== S.repo) { S.open.clear(); S.filter = 'all'; S.query = ''; S.refused = null; S.ask = null; S.viewed = null; }
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
      S.stopping.forEach((id) => { if (!actions().some((a) => a.id === id && running(a))) S.stopping.delete(id); });
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
