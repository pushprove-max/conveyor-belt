// SPDX-License-Identifier: Apache-2.0
// The Benchmarks tab (#326; rebuilt to the owner's approved mockup, #1177): SWE-bench Verified runs (`conveyor.sh bench
// swe`) and their arms, on a tab of its own after Tests, for one project at a time. The snapshot's part holds the run in
// progress, the versions and the drift watch; the runs, the arms, each results key's figures and the pinned task order
// (GET bench?repo=…: `bench swe history`) and a run's tasks (GET bench?repo=…&run=…: `bench swe show <run>`) are read
// from the page server when shown, and read again when the run in progress moves on.
// Seven pages, picked from the row of page buttons at its top, each with the question it answers and a verdict first:
//   Scoreboard (parts/bench-score.js): each arm's ended runs on its results key, judged on the tasks every arm graded (the noise of
//     sqrt(2n) tasks), with the run history folded at its foot (Archive, Restore, Delete).
//   Versions and Compare (parts/bench-versions.js): the Conveyor arm's resolve rate by engine version, the drift watch and
//     the tasks that flipped; any two arms or versions head to head.
//   Live run, Task and Task map (parts/bench-run.js): the run that goes now (else the last run), one task across every
//     arm, and every task of the set by repository.
//   Plan a run (parts/bench-plan.js): the question first, then the arms, the tasks and the cost; Start.
// This file holds what the pages share: the reads, the actions (POST control {action: bench}, an admin's: the server
// refuses a member), the study (studyOf), the figures of a cell and the page's building blocks. A figure a result has
// not kept (one kept before the grade's report was, #1176) shows "not kept", never 0. The tab opens on the Live run
// when a run goes, else on the Scoreboard, each time it is shown.
(function () {
  'use strict';
  const PAGES = [['score', 'Scoreboard'], ['versions', 'Versions'], ['compare', 'Compare'], ['run', 'Live run'], ['task', 'Task'], ['map', 'Task map'], ['plan', 'Plan a run']];
  const B = {
    el: null, ctx: null, d: null, repo: undefined,
    page: 'score',
    hist: null,         // the history read: {repo, stamp, busy, data, error, read (when it ended, by the Board's clock)}
    runs: new Map(),    // each run's tasks read, by `${repo}|${id}`: {stamp, busy, data, error}
    task: null,         // the task the Task page shows (null: the first shared task)
    sel: [],            // the runs ticked in the run history
    cmp: { a: '', b: '', n: 0 },   // Compare's two sides, and how many times they changed (a diff that failed is asked again once after a change)
    diffs: new Map(),   // each pair of results keys' diff (`bench swe diff`), asked once while the Board is open and again when a later run adds a flipped task, all asked again once a run is deleted (parts/bench-versions.js)
    plan: null,         // Plan a run: the question, the tasks and the arms ticked
    by: 'all',          // what the Task map is coloured by
    folds: new Set(),   // the folds opened (fold), by their key, so a redraw keeps them open
    busy: false, held: false, late: false, keep: null,
    checks: false,      // a check was sent and no read of the arms has answered since: the arms are read again until one does
    landed: false,      // the page the tab opens on was chosen for this showing of the tab
    said: new Map(),    // each action's answer, by its key: {text, tone}, shown beside that action (saidAt)
  };
  function planNew() { return { q: 'better', n: 50, arms: null }; }
  B.plan = planNew();
  const num = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : null);
  const list = (v) => (Array.isArray(v) ? v : []);
  const obj = (v) => (v && typeof v === 'object' && !Array.isArray(v) ? v : null);
  const plural = (k, one, many) => `${k} ${k === 1 ? one : many || `${one}s`}`;
  const NOT_KEPT = 'not kept';
  const pct = (x) => (num(x) === null ? NOT_KEPT : `${Math.round(x * 100)}%`);
  const usd = (x) => (num(x) === null ? 'not priced' : `$${x >= 100 ? x.toFixed(0) : x.toFixed(2)}`);
  const fmtMin = (m) => (num(m) === null ? NOT_KEPT : m >= 90 ? `${(m / 60).toFixed(1)} h` : `${Math.round(m)} min`);
  const kTok = (t) => (num(t) === null ? NOT_KEPT : t >= 1e6 ? `${(t / 1e6).toFixed(1)}M` : `${Math.round(t / 1e3)}k`);
  // The 95% range of k of n (Wilson), and the noise of docs/benchmarks.md: with n shared tasks, a difference under about
  // sqrt(2n) tasks is run-to-run noise.
  function wilson(k, n) {
    if (!n) return [0, 1];
    const z = 1.96, p = k / n, d = 1 + z * z / n, c = p + z * z / (2 * n), m = z * Math.sqrt(p * (1 - p) / n + z * z / (4 * n * n));
    return [Math.max(0, (c - m) / d), Math.min(1, (c + m) / d)];
  }
  const noise = (n) => Math.sqrt(2 * n);
  // The noise in whole tasks, as the engine says it (bench/swe.sh SWE_NOISED): sqrt(2n) rounded up, at most n.
  const noised = (n) => Math.min(Math.ceil(noise(n)), n);
  const noiseSaid = (n) => String(noised(n));
  const told = (d, n) => n > 0 && Math.abs(d) >= noised(n);
  // The noise as a share of n tasks, in whole points: rounded up where a gap of it "shows" (rounded down, a gap of it
  // can be under the noise: 6% of 500 is 30 tasks, under 32), rounded down where arms "closer than" it share a tier.
  const noisePct = (n, down) => `${(down ? Math.floor : Math.ceil)(noised(n) * 100 / n)}%`;
  const median = (xs) => { const s = xs.slice().sort((a, b) => a - b); return s.length ? (s[(s.length - 1) >> 1] + s[s.length >> 1]) / 2 : null; };
  const mean = (xs) => (xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : null);
  // f of each cell, or null (not kept) when one cell has not kept it.
  function kept(cells, f) { const v = cells.map(f); return v.some((x) => x === null || x === undefined) ? null : v; }
  const sum = (xs) => (xs === null ? null : xs.reduce((a, b) => a + b, 0));

  // ---- a cell of `bench swe show` (one arm on one task) ----
  // Its result: yes (resolved), no (graded, not resolved), nr (not run), or null (no result yet).
  const said = (c) => (!obj(c) ? null : c.result === 'resolved' || c.resolved === true ? 'yes' : typeof c.result === 'string' && c.result.startsWith('not run') ? 'nr' : c.result || c.resolved === false ? 'no' : null);
  const graded = (c) => ['yes', 'no'].includes(said(c));
  // A cost `bench swe` recorded: {usd, state}, known, estimate (an agent arm's tokens at its model's list price), partial
  // or unknown; anything else (a result from before costs were recorded) is unknown, never $0.
  const costOf = (c) => { const o = obj(c); return o && ['known', 'estimate', 'partial'].includes(o.state) && num(o.usd) !== null ? { usd: o.usd, state: o.state } : { usd: null, state: 'unknown' }; };
  // A cost as a cell shows it: the figure alone, as the mockup does, whatever its state.
  const costSaid = (c) => usd(costOf(c).usd);
  // The cost of several cells: usd null when one is not priced in whole (a total that left it out would read as the whole).
  function costSum(cells) {
    let total = 0, est = false;
    for (const c of cells) {
      const k = costOf(c.cost);
      if (k.state !== 'known' && k.state !== 'estimate') return { usd: null, est };
      total += k.usd; est = est || k.state === 'estimate';
    }
    return { usd: total, est };
  }
  // The steps of a Conveyor arm's card that tell where two runs went apart (bench/swe.sh SWE_STAGE), and the stage each is.
  const SEQ = ['build', 'review', 'fix', 'rebase', 'test', 'landed', 'blocked'];
  const STAGE_SAID = { build: 'build', review: 'review', fix: 'fix round', test: 'test step', land: 'landing' };
  function stageOf(s) {
    if (s.step === 'blocked') { const m = /^(build|review|fix|test|land)/.exec(String(s.reason || '')); return m ? m[1] : 'land'; }
    return s.step === 'landed' ? 'land' : s.step === 'rebase' ? 'fix' : s.step;
  }
  // The first step where two runs of a task went apart, as `bench swe diff` finds it: build when their steps are the same.
  function apart(a, b) {
    const x = list(a).filter((s) => obj(s) && SEQ.includes(s.step)), y = list(b).filter((s) => obj(s) && SEQ.includes(s.step));
    for (let i = 0; i < Math.max(x.length, y.length); i += 1) {
      if (!x[i] || !y[i] || x[i].step !== y[i].step || x[i].result !== y[i].result) return STAGE_SAID[stageOf(x[i] || y[i])] || 'build';
    }
    return 'build';
  }
  // Where a Conveyor arm's unresolved task first went wrong, read from its card's steps: test step (a test step failed,
  // also when the card was blocked after its fix round), blocked (never landed, with no test step failed), build (no
  // change to review), fix round (a fix round changed it and it is still wrong), else review (a review passed a wrong
  // change). null when the result keeps no steps.
  function lossOf(c) {
    const steps = list(c && c.steps).filter(obj);
    if (!steps.length) return null;
    if (steps.some((s) => s.step === 'test' && s.result === 'fail')) return 'test step';
    if (steps.some((s) => s.step === 'blocked')) return 'blocked';
    if (!steps.some((s) => s.step === 'review')) return 'build';
    return steps.some((s) => s.step === 'fix') ? 'fix round' : 'review';
  }
  // The hidden tests of a cell: [failToPass passed, of, passToPass passed, of], or null when its grade is not kept.
  function testsOf(c) {
    const t = obj(c && c.tests), f = obj(t && t.failToPass), p = obj(t && t.passToPass);
    if (!f || !p || num(f.passed) === null || num(p.passed) === null) return null;
    return [f.passed, f.passed + (num(f.failed) || 0), p.passed, p.passed + (num(p.failed) || 0)];
  }
  const testsSaid = (c) => { const t = testsOf(c); return t ? `${t[0]} of ${t[1]} fail-to-pass · ${t[2]} of ${t[3]} pass-to-pass` : NOT_KEPT; };
  // A file of a patch is a test file as docs/benchmarks.md says: under a test or tests folder, or test_*.py, *_test.py, conftest.py.
  const isTest = (p) => /(^|\/)tests?\//.test(p) || /(^|\/)(test_[^/]*\.py|[^/]*_test\.py|conftest\.py)$/.test(p);
  // A cell's lines: {code: [added, removed], test, files}, from its measures, else from the patch it keeps; null when neither is kept.
  function linesOf(c) {
    const m = obj(c && c.measures);
    if (m && num(m.codeAdded) !== null) return { add: m.codeAdded, del: num(m.codeRemoved) || 0, test: num(m.testAdded) || 0, files: num(m.files) || 0 };
    if (!Array.isArray(c && c.patch)) return null;
    const code = c.patch.filter((f) => !isTest(String(f.path))), tests = c.patch.filter((f) => isTest(String(f.path)));
    const add = (fs, k) => fs.reduce((x, f) => x + (num(f[k]) || 0), 0);
    return { add: add(code, 'added'), del: add(code, 'removed'), test: add(tests, 'added'), files: c.patch.length };
  }

  // ---- an arm as a run's column names it ----
  const commit7 = (c) => String(c.engine || '').slice(0, 7);
  const isConveyor = (c) => c.kind === 'conveyor' || c.arm === 'conveyor';
  const verOf = (c) => (c.version && c.version !== 'main' ? `v${String(c.version).replace(/^v/, '')}` : `main ${commit7(c)}`.trim());
  function colName(c) {
    const label = c.label || c.arm || '?';
    if (isConveyor(c) || c.engine) return `${label} ${verOf(c)}`;
    return `${label}${c.model && c.key && c.key !== c.arm && !label.includes(c.model) ? ` (${c.model})` : ''}`;
  }
  // Each arm its own colour, the same on every page whatever arms are beside it (the mockup's): the Conveyor arm the
  // first series, another Conveyor arm the sixth, Claude alone the fourth, Claude then a review the third, a Codex arm
  // the second, Caveman the seventh, and any other arm (Claude with a plugin or method) the fifth.
  const SERIES = { conveyor: 1, solo: 4, 'solo-review': 3, caveman: 7 };
  const seriesOf = (a) => SERIES[a.arm] || (isConveyor(a) ? 6 : /^codex/.test(String(a.arm)) ? 2 : 5);
  function paint(arms) { arms.forEach((a) => { a.s = seriesOf(a); }); return arms; }

  // ---- the page's building blocks ----
  function h(tag, cls, text) { return B.ctx.h(tag, cls, text); }
  const chip = (word, tone) => B.ctx.chip(word, tone);
  function button(text, cls, act, label, fn) {
    const b = h('button', `btn ${cls || ''}`.trim(), text);
    b.type = 'button'; b.dataset.act = act; b.setAttribute('aria-label', label || text);
    b.addEventListener('click', fn);
    return b;
  }
  const add = (el, x) => { [].concat(x).forEach((v) => { if (v !== null && v !== undefined && v !== '') el.append(v); }); return el; };
  // The line under the page row: the question the page answers, and how it answers it.
  function answers(q, how) {
    const p = h('p', 'bench-answers');
    p.append(h('b', null, 'This page answers:'), ` ${q}`);
    if (how) p.append(' ', h('span', null, how));
    return p;
  }
  // The verdict at the top of a page: its tone (ok, warn, bad, quiet), what it judges, the verdict and why.
  function verdict(tone, k, v, w) {
    const d = h('div', `bench-verdict bench-verdict-${tone}`);
    d.append(h('div', 'bench-vk', k), add(h('div', 'bench-vv'), v));
    if (w) d.append(add(h('div', 'bench-vw'), w));
    return d;
  }
  // A card of the page: its heading (a text, or a text and a chip), the line under it, then what is appended to it.
  function box(title, sub, cls) {
    const s = h('section', `bench-box${cls ? ` ${cls}` : ''}`);
    if (title) s.append(add(h('h3', 'bench-h'), title));
    if (sub) s.append(add(h('p', 'bench-hsub'), sub));
    return s;
  }
  const grid = (kind, ...kids) => add(h('div', `bench-grid bench-g-${kind}`), kids);
  function stat(n, l, d) {
    const s = h('div', 'bench-box bench-stat');
    s.append(h('div', 'bench-stat-n', n), h('div', 'bench-stat-l', l), add(h('div', 'bench-stat-d'), d));
    return s;
  }
  const note = (text) => add(h('p', 'bench-note'), text);
  const callout = (text, tone) => add(h('div', `bench-callout${tone ? ` bench-callout-${tone}` : ''}`), text);
  const dot = (s) => h('span', `bench-dot bench-s${s || 7}`);
  const armSaid = (a) => add(h('span', 'bench-arm'), [dot(a.s), a.label]);
  // A table: each head a text, or [text, 'r' for a figure, its title]; each row an array of cells, each a text, a node,
  // an array of them, or {v, c}: its content and class. on(tr, i) is given each row.
  function table(heads, rows, cls, on) {
    const t = h('table', `bench-t${cls ? ` ${cls}` : ''}`), hr = h('tr'), body = h('tbody'), head = h('thead');
    heads.forEach((x) => { const [text, c, title] = [].concat(x); const th = h('th', c || null, text); if (title) th.title = title; hr.append(th); });
    head.append(hr); t.append(head, body);
    rows.forEach((r, i) => {
      const tr = h('tr');
      r.forEach((x) => { const o = obj(x) && !(x instanceof window.Node) ? x : { v: x }; tr.append(add(h('td', o.c || null), o.v)); });
      if (on) on(tr, i);
      body.append(tr);
    });
    return t;
  }
  // A fold (details) that a redraw keeps open or shut as it was left.
  function fold(key, summary, cls) {
    const d = h('details', cls || null), s = h('summary');
    add(s, summary);
    d.dataset.fold = key; d.open = B.folds.has(key); d.append(s);
    d.addEventListener('toggle', () => { if (d.open) B.folds.add(key); else B.folds.delete(key); });
    return d;
  }
  const kv = (pairs) => { const dl = h('dl', 'bench-kv'); pairs.forEach(([k, v]) => dl.append(h('dt', null, k), add(h('dd'), v))); return dl; };
  // A bar of a share (0 to 1), its fill in a tone or series class.
  function bar(frac, cls) {
    const b = h('div', 'bench-bar'), f = h('span', cls || 'bench-fill');
    f.style.width = `${Math.max(0, Math.min(1, num(frac) || 0)) * 100}%`;
    b.append(f);
    return b;
  }
  // The resolve rate of k of n with its 95% range (Wilson), in the arm's colour.
  function ciBar(k, n, s) {
    const [lo, hi] = wilson(k, n), d = h('div', 'bench-ci'), band = h('span', `bench-ci-band bench-s${s || 7}`), pt = h('span', `bench-ci-pt bench-s${s || 7}`);
    d.title = `95% range ${pct(lo)} to ${pct(hi)}`;
    band.style.left = `${lo * 100}%`; band.style.width = `${(hi - lo) * 100}%`;
    pt.style.left = `calc(${(n ? k / n : 0) * 100}% - 1px)`;
    d.append(band, pt);
    return d;
  }
  const SVG = 'http://www.w3.org/2000/svg';
  function svg(tag, attrs, text) {
    const el = document.createElementNS(SVG, tag);
    Object.entries(attrs || {}).forEach(([k, v]) => el.setAttribute(k, String(v)));
    if (text !== undefined) el.textContent = String(text);
    return el;
  }
  // Each action's answer stays beside its own control until that action is used again; one given for one project does
  // not show on another's page.
  const saidKey = (key, repo) => `${repo === undefined ? B.repo : repo}\n${key}`;
  function say(key, text, tone, repo, more) { B.said.set(saidKey(key, repo), { ...more, text, tone: tone || 'quiet' }); draw(); }
  function saidAt(key) {
    const m = B.said.get(saidKey(key));
    if (!m) return '';
    const p = h('p', `bench-said bench-said-${m.tone}`, m.text);
    p.dataset.said = key; p.setAttribute('role', 'status');
    return p;
  }
  // The mockup has no line of receipt under Start, Check the arms first or Stop: only a refusal shows, so a failed action is not silent.
  function refusedAt(key) { const p = saidAt(key); return p && p.classList.contains('bench-said-bad') ? p : ''; }
  const go = (page) => { B.page = page; draw(); };
  const openTask = (id) => { B.task = id; go('task'); };

  // ---- reads from the page server ----
  const live = () => obj(obj(B.d && B.d.bench) && B.d.bench.live);
  // `seq`, the read revision, goes up when the active step changes and `done` stays the same.
  const liveStamp = () => { const l = live(); return l ? `${l.id}|${l.state}|${l.done}|${l.seq}` : ''; };
  function getJSON(url) {
    return window.fetch(url).then((r) => (r.ok ? r.json() : r.text().then((t) => Promise.reject(new Error(String(t).trim() || `the server answered ${r.status}`)))));
  }
  // The history's stamp: the run in progress, and the control record's guard (`control guard` changes the history's
  // guard and weekLeft.stop with no run moved).
  function readHist(again) {
    const repo = B.repo, stamp = `${liveStamp()}|${JSON.stringify(B.d && B.d.guard !== undefined ? B.d.guard : null)}`, was = B.hist;
    if (typeof repo !== 'string' || (!again && was && was.repo === repo && (was.busy || was.stamp === stamp))) return;
    const o = { repo, stamp, busy: true, data: was && was.repo === repo ? was.data : null, error: null };
    B.hist = o;
    getJSON(`bench?repo=${encodeURIComponent(repo)}`).then((x) => {
      if (!obj(x)) { o.error = 'the answer did not read'; return; }
      // A run gone from the history was deleted (on the build machine, too): a new run can write its results under its
      // results key, so a diff kept from before is of results gone.
      const ids = new Set(list(x.runs).filter(obj).map((r) => r.id));
      if (list(o.data && o.data.runs).some((r) => obj(r) && !ids.has(r.id))) B.diffs = new Map();
      o.data = x; B.checks = false;
    },
      (e) => { o.error = e && e.message ? e.message : 'no answer'; }).then(() => { o.busy = false; o.read = B.ctx.now(); if (B.hist === o) draw(); });
  }
  // A run's tasks: read once, and again while it is the run in progress and the snapshot says it moved on.
  function readRun(id) {
    const repo = B.repo, k = `${repo}|${id}`, was = B.runs.get(k), l = live();
    const stamp = l && l.id === id ? liveStamp() : '';
    if (typeof repo !== 'string' || (was && (was.busy || was.stamp === stamp))) return was;
    const o = { stamp, busy: true, data: was ? was.data : null, error: null };
    B.runs.set(k, o);
    getJSON(`bench?repo=${encodeURIComponent(repo)}&run=${encodeURIComponent(id)}`).then((x) => { if (obj(x) && obj(x.run)) o.data = x; else o.error = 'the answer did not read'; },
      (e) => { o.error = e && e.message ? e.message : 'no answer'; }).then(() => { o.busy = false; if (B.runs.get(k) === o) draw(); });
    return o;
  }
  const hist = () => obj(B.hist && B.hist.data) || null;
  const allRuns = () => list(hist() && hist().runs).filter((r) => obj(r) && typeof r.id === 'string');
  // An archived run (bench swe's archived, its time) is in the run history alone: in no figure, Compare or plan.
  const runsOf = () => allRuns().filter((r) => typeof r.archived !== 'string');
  const armsOf = () => list(hist() && hist().arms).filter((a) => obj(a) && typeof a.name === 'string');
  const colsOf = (r) => list(r && r.cols).filter(obj);
  const keysOf = () => list(hist() && hist().keys).filter(obj);
  const benchOf = () => obj(B.d && B.d.bench) || {};
  const setSize = () => list(hist() && hist().order).length || num(benchOf().max) || 500;
  // While the history (or a run) is read, or why it could not be.
  function reading(what, o) {
    const x = o || B.hist;
    if (x && x.error && !x.data) {
      const st = B.ctx.state('error', `The Board could not read ${what}`, x.error);
      st.append(button('Read again', 'btn-quiet', 'read-again', 'Read the benchmarks again', () => { if (o) o.stamp = null; readHist(true); draw(); }));
      return st;
    }
    return B.ctx.state('empty', `Reading ${what}…`, 'The runs and their figures are read from the build machine when this tab is shown.');
  }

  // The guards whose arms' trials used the share of the week that a guard's reading shows in run r: both when they read
  // one login (the run's weekStart or its weekLeft keeps shared: true; a login that became shared during the run has it in
  // weekLeft alone), else the guard alone.
  const weekPool = (r, kind) => (obj(r) && [r.weekStart, r.weekLeft].some((w) => obj(w) && w.shared === true) ? ['conveyor', 'agent'] : [kind]);
  // The share of the week left at run r's start for a guard's pool (weekPool): one reading for a shared pool, the larger
  // of its guards' (a login that became shared during the run read apart at the start; each guard's own start made
  // Plan and Live run give the pool a use that hung on the guard asked); else the guard's own. Null when none is kept.
  const weekFrom = (r, kind) => {
    const start = obj(r) && obj(r.weekStart) ? r.weekStart : {};
    const xs = weekPool(r, kind).map((k) => num(start[k])).filter((x) => x !== null);
    return xs.length ? Math.max(...xs) : null;
  };

  // ---- the study: what the Scoreboard, Task, Task map and Compare read ----
  // The runs that ended (not archived, not going, not refused), the newest first.
  const ended = () => runsOf().filter((r) => r.state !== 'running' && r.state !== 'refused');
  // Each arm's results: its newest ended run with a task done names the arm's results key, and every ended run of the
  // arm on that key adds its tasks (a short run after a long one keeps the long one's other tasks).
  function sources() {
    const seen = new Map();
    ended().forEach((r) => colsOf(r).forEach((c) => {
      if (typeof c.arm !== 'string' || (num(c.done) || 0) <= 0) return;
      const s = seen.get(c.arm);
      if (!s) seen.set(c.arm, { run: r, col: c, runs: [r] });
      else if (typeof c.key === 'string' && c.key === s.col.key && !s.runs.includes(r)) s.runs.push(r);
    }));
    return Array.from(seen.values());
  }
  // The runs given read (`bench swe show`), by ID; else wait, the read of the first one not read yet, and its id.
  function showsOf(runs) {
    const reads = runs.map((r) => [r.id, readRun(r.id)]), wait = reads.find(([, o]) => !o || !o.data);
    return wait ? { wait: wait[1] || null, id: wait[0] } : { shows: new Map(reads.map(([id, o]) => [id, o.data])) };
  }
  // One arm of the runs read (the newest first): its cells by task, each from the newest run that graded it (else the
  // newest that has it), and from, the run of each cell.
  function armOf(run, col, show, older) {
    const cells = new Map(), from = new Map();
    [[run, show]].concat(older || []).forEach(([r, d]) => list(d && d.tasks).filter(obj).forEach((t) => {
      const c = list(t.cells).find((x) => obj(x) && x.arm === col.arm), was = cells.get(t.id);
      if (c && (!was || (!graded(was) && graded(c)))) { cells.set(t.id, c); from.set(t.id, r); }
    }));
    return { arm: col.arm, key: col.key, col, run, runs: [run].concat((older || []).map(([r]) => r)), from, label: colName(col), kind: isConveyor(col) ? 'conveyor' : 'agent', cells };
  }
  const armOfRuns = (s, shows) => armOf(s.run, s.col, shows.get(s.run.id), s.runs.slice(1).map((r) => [r, shows.get(r.id)]));
  // Each arm's results (sources), and the shared tasks, those every arm graded. reading: a run not read yet.
  function studyOf() {
    const src = sources(), titles = new Map(), all = Array.from(new Set(src.flatMap((s) => s.runs))), { shows, wait, id } = showsOf(all);
    if (!shows) return { reading: wait, id, arms: [], shared: [], n: 0 };
    const arms = paint(src.map((s) => armOfRuns(s, shows)));
    shows.forEach((d) => list(d.tasks).filter(obj).forEach((t) => { if (!titles.has(t.id)) titles.set(t.id, t.title || null); }));
    const ids = Array.from(titles.keys()), shared = arms.length ? ids.filter((x) => arms.every((a) => graded(a.cells.get(x)))) : [];
    return { arms, shared, n: shared.length, titles, ids, runs: all };
  }
  // The arm's figures on the tasks given: resolved, cost (null when one cell is not priced), minutes and the rest.
  function figsOf(a, ids) {
    const cs = ids.map((id) => a.cells.get(id)).filter(obj), ok = cs.filter((c) => said(c) === 'yes'), cost = costSum(cs);
    const mins = kept(cs, (c) => num(c.minutes)), toks = kept(cs, (c) => num(c.tokens)), sess = kept(cs, (c) => num(c.sessions));
    return { a, cs, ok, k: ok.length, n: cs.length, cost: cost.usd, est: cost.est, minutes: mins && median(mins), wall: sum(mins),
      tokens: sum(toks), sessions: sess && mean(sess) };
  }
  // The engine versions of the Conveyor arm in the order of their releases (vX.Y.Z; a version named by a commit comes
  // after the releases, by its newest run's start), each with its newest run's column, its runs on that results key and,
  // once they are read, arm (armOf: its cells), n (tasks graded) and k (resolved); else wait, the read not done yet.
  const relOf = (e) => { const m = /^v(\d+)\.(\d+)\.(\d+)/.exec(e.v); return m ? m.slice(1).map(Number) : null; };
  function byRelease(a, b) {
    const x = relOf(a), y = relOf(b);
    if (x && y) return x[0] - y[0] || x[1] - y[1] || x[2] - y[2];
    return x || y ? (x ? -1 : 1) : String(a.date || '').localeCompare(String(b.date || ''));
  }
  // arm: the Conveyor arm to read (the one named conveyor unless Compare asks for another, as conveyor-codex-claude).
  function versionsOf(arm) {
    const seen = new Map(), which = arm || 'conveyor';
    ended().forEach((r) => colsOf(r).filter((c) => c.arm === which).forEach((c) => {
      const v = verOf(c), s = seen.get(v);
      if (!s && (num(c.done) || 0) - (num(c.notRun) || 0) > 0) seen.set(v, { v, run: r, col: c, date: r.started, runs: [r] });
      else if (s && typeof c.key === 'string' && c.key === s.col.key && !s.runs.includes(r)) s.runs.push(r);
    }));
    const vs = Array.from(seen.values()).sort(byRelease);
    vs.forEach((e) => {
      const { shows, wait, id } = showsOf(e.runs);
      if (!shows) { Object.assign(e, { wait: { o: wait, id }, arm: null, n: 0, k: 0 }); return; }
      const arm = armOfRuns(e, shows), g = Array.from(arm.cells.values()).filter(graded);
      Object.assign(e, { arm, n: g.length, k: g.filter((c) => said(c) === 'yes').length });
    });
    return vs.filter((e) => !e.arm || e.n > 0);
  }
  // The change from one version to another on the tasks both graded (another seed or size grades other tasks), in
  // tasks and in points of the resolve rate, and whether it is past the noise of those tasks; null while one is read.
  // few: fewer than 3 tasks both graded (the Scoreboard's few), where nothing is told, though 1 of 1 is past the noise.
  function moved(p, v) {
    if (!p.arm || !v.arm) return null;
    const ids = Array.from(v.arm.cells.keys()).filter((id) => graded(v.arm.cells.get(id)) && graded(p.arm.cells.get(id)));
    const k = (e) => ids.filter((id) => said(e.arm.cells.get(id)) === 'yes').length, kp = k(p), kv = k(v), d = kv - kp, shared = ids.length, few = shared < 3;
    return { d, kp, kv, shared, few, pts: shared ? Math.round(d / shared * 100) : 0, sig: !few && told(d, shared) };
  }

  // ---- actions (POST control, action bench) ----
  // While the answer is out, the action's message is `sending` (else "Sending…") and has out: true.
  function send(key, args, done, then, no, more, sending) {
    if (B.busy) { say(key, 'Wait for the answer to the last action.', 'warn'); return; }
    const repo = B.repo;
    B.busy = true; say(key, sending || 'Sending…', 'quiet', repo, { ...more, out: true });
    B.ctx.post('control', { action: 'bench', args, repo }).then((r) => r.text().then((t) => [r.ok, String(t).trim() || `the build machine answered ${r.status}`]),
      () => [false, 'the build machine did not answer']).then(([ok, text]) => {
      B.busy = false;
      if (ok && then && repo === B.repo) then(text);
      if (!ok && no) no();
      say(key, ok ? done(text) : `Not done: ${B.ctx.refusal(text)}`, ok ? 'ok' : 'bad', repo, more);
    });
  }
  // A read that the page starts by itself (the diff of a pair): the text of the answer, or null when it did not come. It
  // shares nothing with `send`: it takes no part in B.busy (a click is never refused for it) and says nothing, as the page
  // has no button to say it by.
  function ask(args) {
    const repo = B.repo;
    return B.ctx.post('control', { action: 'bench', args, repo }).then((r) => r.text().then((t) => (r.ok && repo === B.repo ? String(t) : null)), () => null);
  }
  // Stop the run: it names the run (`bench swe stop <id>`: a Stop that comes late never stops the run after it) and stays
  // off until the build machine answers, once the run and its containers ended (swe_stop). The mockup's page has the
  // button and no answer line, so the label stays; only a refusal is shown (refusedAt), by the page that has the button.
  function stopRun(id, stopping) {
    const key = `stop-${id}`, m = B.said.get(saidKey(key)), out = Boolean(m && m.out) || Boolean(stopping);
    const b = button('Stop the run', '', 'stop-run', `Stop the run ${id}`, () => send(key, ['stop', id], (t) => t.replace(/^conveyor: /, ''),
      () => { readHist(true); const o = B.runs.get(`${B.repo}|${id}`); if (o) o.stamp = null; }, null, null, `Stopping run ${id}. Finished results are kept.`));
    b.disabled = out;
    return b;
  }
  // Archive (Restore, for runs archived) and Delete of the runs given: `bench swe runs archive | restore | delete
  // <id>...`, one request for them all. Delete takes a second click (ctx.twice) whose words name the runs and say how
  // many of their results stay because a run not deleted with them shows them too (history's shared). A run that has not
  // ended (going, or its process gone with no end written) has both off, with the reason. The answer is kept under RUNS_SAID.
  const RUNS_SAID = 'runs';
  const unended = (r) => r.state === 'running' || (r.gone === true && !r.ended);
  // A run's state in words: one whose process ended with no end written (gone) was interrupted, never stopped by you.
  const STATE = { done: ['done', 'ok'], stopped: ['stopped', 'warn'], guard: ['stopped at the usage guard', 'warn'], refused: ['did not start', 'bad'], running: ['running', 'info'] };
  const stateOf = (r) => (r.state === 'stopped' && r.gone === true ? ['interrupted', 'warn'] : STATE[r.state] || [String(r.state || 'not read'), 'quiet']);
  // A run's wall time in minutes, from its start to its end; null when not read (or not ended).
  const elapsed = (r) => { const a = Date.parse(r.started), b = Date.parse(r.ended); return Number.isFinite(a) && Number.isFinite(b) ? Math.max(0, (b - a) / 60000) : null; };
  function runActs(runs) {
    const ids = runs.map((r) => r.id), names = ids.join(' and '), back = runs.every((r) => typeof r.archived === 'string');
    const stays = new Set(runs.flatMap((r) => Object.entries(obj(r.shared) || {}).filter(([, by]) => list(by).some((x) => !ids.includes(x))).map(([k]) => k)));
    const shared = stays.size, going = runs.filter(unended);
    const verb = back ? 'restore' : 'archive', word = back ? 'Restore' : 'Archive';
    const arch = button(word, 'btn-quiet btn-sm', `${verb}-runs`, `${word} ${names}`, () => changeRuns(verb, ids));
    const del = button('Delete', 'btn-quiet btn-sm', 'delete-runs', `Delete ${names}`, () => {});
    B.ctx.twice(del, 'final', `Click again: delete ${names}${shared ? ` (${plural(shared, 'result')} another run shows ${shared === 1 ? 'stays' : 'stay'}; the rest goes)` : ''}`, () => changeRuns('delete', ids));
    if (!going.length) return [arch, del];
    arch.disabled = true; del.disabled = true;
    return [arch, del, h('span', 'bench-note', `${going.map((r) => r.id).join(' and ')} ${going.length === 1 ? 'has' : 'have'} not ended: stop ${going.length === 1 ? 'it' : 'them'} first to archive or delete.`)];
  }
  function changeRuns(verb, ids) {
    send(RUNS_SAID, ['runs', verb, ...ids], (t) => t.replace(/^conveyor: /, '').replace(/^./, (c) => c.toUpperCase()), () => {
      ids.forEach((id) => { const o = B.runs.get(`${B.repo}|${id}`); if (o) o.stamp = null; });
      B.sel = B.sel.filter((x) => !ids.includes(x));
      if (verb === 'delete') {
        ids.forEach((id) => B.runs.delete(`${B.repo}|${id}`));
        // The page does not ask for a run just deleted before the history is read again.
        if (hist()) hist().runs = allRuns().filter((r) => !ids.includes(r.id));
        // A new run can write its results under a deleted run's results key: a diff kept from before is of results gone.
        B.diffs = new Map();
      }
      readHist(true);
    });
  }

  // ---- the page row and the panel ----
  function pages() {
    const nav = h('nav', 'bench-pnav');
    nav.setAttribute('aria-label', 'Benchmark pages');
    PAGES.forEach(([p, t]) => {
      const b = button(t, 'btn-quiet', `page-${p}`, t, () => go(p));
      b.setAttribute('aria-current', B.page === p ? 'page' : 'false');
      nav.append(b);
    });
    return nav;
  }
  const K = { B, PAGES, NOT_KEPT, num, list, obj, plural, pct, usd, fmtMin, kTok, wilson, noise, noised, noiseSaid, noisePct, told, median, mean, kept, sum,
    said, graded, costOf, costSaid, costSum, apart, lossOf, testsOf, testsSaid, linesOf, isTest, isConveyor, colName, verOf, paint, h, chip, button, add,
    answers, verdict, box, grid, stat, note, callout, dot, armSaid, table, fold, kv, bar, ciBar, svg, say, saidAt, refusedAt, go, openTask, live, readHist,
    readRun, hist, allRuns, runsOf, armsOf, colsOf, keysOf, benchOf, setSize, reading, studyOf, armOf, figsOf, versionsOf, moved, send, ask,
    stopRun, runActs, RUNS_SAID, stateOf, elapsed, weekPool, weekFrom, draw: () => draw() };
  const P = {};
  ['bench-score', 'bench-versions', 'bench-run', 'bench-plan'].forEach((name) => Object.assign(P, window.DASH_APP.use(name, K)));
  function draw() {
    const el = B.el;
    if (!el || B.ctx.picking()) return;  // Show at every project: the page shows the project choice, a reply that came back draws no project over it
    if (B.d.repo === null) { el.replaceChildren(B.ctx.state('empty', 'No benchmarks to show', 'Conveyor did not run on this project on the build machine yet. Pick a project under Show, above the tabs.')); return; }
    readHist(false);
    const a = document.activeElement && el.contains(document.activeElement) && document.activeElement.dataset ? document.activeElement.dataset.act : null;
    const root = h('div', 'bench'), page = h('div', 'bench-page');
    page.dataset.page = B.page;
    page.append(...P[B.page]());
    root.append(pages(), page);
    el.replaceChildren(root);
    // A control that is off while an answer is out (Start, Check the arms first: K.B.busy) cannot take the focus: its key
    // is kept until the answer's draw turns it on again.
    const keep = B.keep || a;
    B.keep = null;
    if (keep) {
      const k = Array.from(el.querySelectorAll('[data-act]')).find((x) => x.dataset.act === keep);
      if (k && !k.disabled) k.focus({ preventScroll: true });
      else if (B.busy) B.keep = keep;
    }
  }
  function render(el, d, ctx) {
    const view = ctx.project(d);
    ctx.title(Array.isArray(view.repos) && view.repos.length > 1 && view.repo ? `Benchmarks: ${view.repo}` : null);
    if (B.repo !== undefined && view.repo !== B.repo) {
      Object.assign(B, { sel: [], task: null, cmp: { a: '', b: '', n: 0 }, diffs: new Map(), plan: planNew(), landed: false });
      B.runs.clear();
    }
    Object.assign(B, { el, ctx, d: view, repo: view.repo });
    watchOut();
    // The tab opens on the work that needs attention, each time it is shown: the Live run while a run goes, else the
    // Scoreboard. A run that starts while the tab is shown does not move the page.
    if (!B.landed && typeof view.repo === 'string') {
      B.landed = true;
      const l = live();
      B.page = l && l.state === 'running' && typeof l.id === 'string' ? 'run' : 'score';
    }
    if (B.held) { B.late = true; return; }
    draw();
  }
  // The panel taken out of the page (another tab shown: the Board removes the other tabs' panels) makes the next draw
  // choose the page again. The Board draws a panel shown again with a part equal to the last one through same().
  let watched = null;
  function watchOut() {
    const el = B.el && B.el.closest('[data-panel]'), parent = el && el.parentNode;
    if (!parent || parent === watched || typeof window.MutationObserver !== 'function') return;
    watched = parent;
    new window.MutationObserver(() => { if (B.el && !B.el.isConnected) B.landed = false; }).observe(parent, { childList: true });
  }
  function same(el, d, ctx) { if (!B.landed) render(el, d, ctx); }
  // While an arm's check runs, or a read after a check sent was lost, the arms are read again on the Board's clock, one read at a time and at most one each
  // CHECK_MS after the last one ended: a check alone moves no run, so the Board sends the panel no update for it.
  const CHECK_MS = 5000;
  function tick() {
    const was = B.hist;
    if (!was || was.repo !== B.repo || was.busy || !(B.checks || armsOf().some((x) => x.state === 'checking'))) return;
    if (B.ctx.now() - (was.read || 0) >= CHECK_MS) readHist(true);
  }
  // The panel is drawn whole. A control drawn anew between its press and its release lost the click, so a part that
  // comes while the pointer is pressed in the panel is drawn after the release (as on the Tests page).
  document.addEventListener('pointerdown', (e) => { B.held = Boolean(B.el && B.el.contains(e.target)); }, true);
  const release = () => { if (!B.held) return; B.held = false; if (B.late) { B.late = false; setTimeout(draw, 0); } };
  document.addEventListener('pointerup', release, true);
  document.addEventListener('pointercancel', release, true);
  window.addEventListener('blur', release);

  window.DASH_APP.panel({
    id: 'bench',
    title: 'Benchmarks',
    size: 'full',
    tab: 'bench',  // a tab of its own, after Tests
    rows: 'all',
    rowSelector: '.bench-t tbody tr',
    isEmpty: (d) => d.repo === null && !(d.others && typeof d.others === 'object' && Object.keys(d.others).length),
    empty(el, ctx) { el.append(ctx.state('empty', 'No benchmarks to show', 'Conveyor did not run on this project on the build machine yet. Start Conveyor there, and its benchmarks show here.')); },
    error(el, message, ctx) { el.append(ctx.state('error', 'The Board could not read the benchmarks', message)); },
    render,
    same,
    tick,
  });
}());
