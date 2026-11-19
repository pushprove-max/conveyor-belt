// SPDX-License-Identifier: Apache-2.0
// The Benchmarks tab (#326, the owner's approved mockup): SWE-bench Verified runs (`conveyor.sh bench swe`) and their
// arms (#325), on a tab of its own after Tests. It shows one project at a time, as the Tests page does, from its part
// (each record's bench, the snapshot's run in progress and versions, and drift, the drift watch). The runs, each arm's
// figures and a run's tasks are not in the snapshot (its size): they are read from the page server when shown (GET
// bench?repo=…: `bench swe history`; GET bench?repo=…&run=…: `bench swe show <run>`), and read again when the run in
// progress moves on.
// Its pages, picked from the row of page buttons at its top:
//   Overview: Newest run (resolved of n for each arm side by side with the noise band for n, each arm's figures, the
//     notes to read it with; or the run in progress with a bar of tasks done a arm, the task now and Stop run; or how the
//     last run ended: stopped, at the usage guard, an arm's preflight failed; or nothing yet), History (every run newest
//     first, grouped by task set, each with a box to tick: up to 6, for Compare and the infographic), Arms (how many are
//     ready, checking with its step, failing their preflight, not checked, not offered) and Drift watch, folded. With runs ticked, a bar at the
//     foot of the screen offers Compare, Generate infographic and Clear.
//   A run: its first line (state, wall time and, while it goes, Stop run, with Stop's answer under it); while it goes,
//     the arm, task and step now, the pairs finished, resolved, reused and not run, the cost so far and each arm's;
//     each arm a column and each task a row (resolved or not, sessions, minutes, cost; or the step, waiting,
//     interrupted), totals a arm, Export figures (one JSON file of the figures: no code, no names, no machine names);
//     a task opened shows each arm's patch, its steps (a Conveyor arm's build, reviews, fix rounds, test step, block)
//     and the harness's grade; and the run's recent log.
//   Compare: two arms or versions of the runs ticked (else the run open, else the newest), sent as `bench swe diff
//     <A> <B> --json`: the tasks that flipped, where the two went apart, the facts read from the records and, beside
//     them, the model's reading.
//   Start a run: n (the presets, or any n), the Conveyor version, the run settings every arm shares (`--settings`: the
//     dataset revision, the order seed and each container's limits, each shown with its default), the arms (only
//     those whose preflight passed can be picked; ticking one not checked, changed or failed runs its preflight, and
//     picks it once the arms read again show it ready) and, before Start, each arm's tasks reused, usual and
//     worst-case sessions, minutes, cost for the tasks it has not run yet (each session at perTask.session, the mean
//     dollars of this project's own priced sessions) and the usage guard that can hold it. Start sends each arm ticked
//     or none: it is off while one is being checked or not ready, and while the usage guard holds an arm picked back.
//     Its answer, the run's receipt, opens that run (Watch run), or opens it at once when it has ended. New Conveyor arm, New agent
//     arm and an arm's Edit a copy open the arm editor (a Conveyor arm's rules and five seats, or an agent arm's CLI,
//     model, effort and method), whose Save arm keeps a new revision on the build machine (`bench swe arms save`); the
//     saved revisions are listed under Saved arms, each its own arm with its own check, by its revision ID.
//   Infographic: the runs ticked (up to 6) on a fixed template filled by code (SVG, no library; no model writes or picks
//     anything), with its notes on how to read it, which a title typed cannot remove; Download SVG and Download PNG,
//     each with the table of its figures beside it (<id>.csv).
// Each time it is shown, the tab opens on the run in progress when there is one (its page, with Stop run on its first
// line), else on Start a run; both have Latest result beside their heading. The other pages have Watch run in their
// page row while a run goes. A run's cost is the list price `bench swe` recorded ({usd, state}):
// recorded, recorded in part (the rest unknown) or unknown, never $0 for one not recorded (costSaid). The harness's
// FAIL_TO_PASS and PASS_TO_PASS counts are not kept (only resolved).
// Every action is POST control {action: bench} (an admin's: the server refuses a member).
(function () {
  'use strict';
  const PAGES = [['overview', 'Overview'], ['run', 'A run'], ['compare', 'Compare'], ['start', 'Start a run'], ['infographic', 'Infographic']];
  const MAX_SEL = 6;
  const IG_TITLE = 'Conveyor against other ways to build, on SWE-bench Verified';
  const B = {
    el: null, ctx: null, d: null, repo: undefined,
    page: 'overview',
    hist: null,         // the history read: {repo, stamp, busy, data, error, read (when it ended, by the Board's clock)}
    runs: new Map(),    // each run's tasks read, by `${repo}|${id}`: {stamp, busy, data, error}
    open: null,         // the run the run page shows (null: the newest)
    task: null,         // the task opened on the run page
    sel: [],            // the runs ticked, in the order ticked
    older: false,       // History shows every run, not the newest 20
    start: { n: 20, arms: new Set(['conveyor']), engine: 'main', commit: '', checking: new Map(), set: {} },  // set: each run setting typed (runSet)
    cmp: { a: '', b: '', data: null, text: null, all: false, ask: null, n: 0 },
    edit: null,         // the arm editor's form while it is open (blank, copyOf), else null
    title: IG_TITLE,
    busy: false, held: false, late: false, keep: null,
    landed: false,      // the page the tab opens on was chosen for this showing of the tab (land)
    said: new Map(),    // each action's answer, by its key: {repo, text, tone}, shown beside that action (saidAt)
  };
  const num = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : null);
  const list = (v) => (Array.isArray(v) ? v : []);
  const obj = (v) => (v && typeof v === 'object' && !Array.isArray(v) ? v : null);
  const plural = (k, one, many) => `${k} ${k === 1 ? one : many || `${one}s`}`;
  // An agent arm's sessions as its spec or its result gives them (a method can take several); null when unknown.
  const sessionsWord = (k) => (num(k) === null ? null : k === 1 ? 'one session' : plural(k, 'session'));
  // How many tasks a difference must reach to be told from run-to-run noise with n tasks (swe_noise, bench/swe.sh).
  const noiseOf = (n) => Math.min(Math.ceil(Math.sqrt(2 * n)), n);
  const noiseSaid = (n) => (noiseOf(n) >= n ? `With ${plural(n, 'task')} only a total break shows: a difference under ${n} is within the noise.`
    : `With ${n} tasks a difference under ${noiseOf(n)} tasks is within the noise.`);
  // An arm graded on all n tasks. Only such arms can be set against the noise: a task not run (or not done) has no
  // grade, so that arm's count of resolved is not of the same tasks as another arm's.
  const gradedAll = (c, n) => n > 0 && num(c.done) === n && num(c.notRun) === 0;
  const tokens = (t) => (num(t) === null ? '–' : t >= 1e6 ? `${(t / 1e6).toFixed(1)}M` : t >= 1e3 ? `${Math.round(t / 1e3)}k` : String(t));
  const took = (m) => { if (num(m) === null) return '–'; const r = Math.round(m); return r < 60 ? `${r} min` : `${Math.floor(r / 60)} h${r % 60 ? ` ${String(r % 60).padStart(2, '0')} min` : ''}`; };
  const COST = '–';  // an estimate with no price data (Start a run)
  // A cost `bench swe` recorded: {usd, state} with state known (every session priced), partial (usd the priced part)
  // or unknown; anything else (null: a run or result from before costs were recorded) is unknown, never $0.
  const costOf = (c) => { const o = obj(c); return o && (o.state === 'known' || o.state === 'partial') && num(o.usd) !== null ? { usd: o.usd, state: o.state } : { usd: null, state: 'unknown' }; };
  function costSaid(c) {
    const k = costOf(c);
    return k.state === 'unknown' ? 'unknown' : k.state === 'partial' ? `${B.ctx.money(k.usd)} recorded, part unknown` : B.ctx.money(k.usd);
  }
  const COST_WHY = 'Costs are at list prices. "Part unknown": some sessions have no usage that can be priced.';
  // An arm as a run's column names it: a Conveyor arm with its version (main with its commit), another with its model
  // when each model's results are kept apart (its key is not its name).
  const commit7 = (c) => String(c.engine || '').slice(0, 7);
  const isConveyor = (c) => c.kind === 'conveyor' || c.arm === 'conveyor';
  const verOf = (c) => (c.version && c.version !== 'main' ? String(c.version).replace(/^v/, '') : `main ${commit7(c)}`.trim());
  function colName(c) {
    const label = c.label || c.arm || c.name || '?';
    if (isConveyor(c) || c.engine) return `${label} ${verOf(c)}`;
    return `${label}${c.model && c.key && c.key !== c.arm && !label.includes(c.model) ? ` (${c.model})` : ''}`;
  }
  const colSub = (c) => (isConveyor(c) || c.engine ? (commit7(c) ? `engine ${commit7(c)}` : '') : c.model ? `model ${c.model}` : '');
  // Each kind of arm has its colour (the legend): Conveyor, Conveyor with other agents, Claude plain, Codex, Claude with a method.
  function group(c) {
    const a = c.arm || c.name || '';
    if (isConveyor(c)) return a === 'conveyor' ? 1 : 3;
    if (/^codex/.test(a)) return 4;
    return a === 'solo' || a === 'solo-review' ? 2 : 5;
  }
  const LEGEND = [[1, 'Conveyor versions'], [3, 'Conveyor, other agents'], [2, 'Claude plain'], [5, 'Claude + plugin or method'], [4, 'Codex']];

  function h(tag, cls, text) { return B.ctx.h(tag, cls, text); }
  function button(text, cls, act, label, fn) {
    const b = h('button', `btn ${cls || ''}`.trim(), text);
    b.type = 'button'; b.dataset.act = act; b.setAttribute('aria-label', label || text);
    b.addEventListener('click', fn);
    return b;
  }
  function section(cls, title, count, foot) {
    const s = h('section', `bench-sec ${cls}`), head = h('div', 'bench-head');
    head.append(h('h3', 'board-head', title));
    if (count !== null && count !== undefined) head.append(h('span', 'bench-count', String(count)));
    if (foot) head.append(h('span', 'board-from', foot));
    s.append(head);
    return s;
  }
  // Each action's answer stays beside its own control until that action is used again: a redraw keeps it, another
  // action's answer does not replace it, and an answer given for one project does not show on another's page. A key
  // names the action and what it acts on (stop-<run>, export-<run>, compare-<n>-<a>-<b>, check-<arm>), so an answer about
  // one run, pair or selection does not show beside the control for another. `more` keeps facts the answer needs later.
  const saidKey = (key, repo) => `${repo === undefined ? B.repo : repo}\n${key}`;
  function say(key, text, tone, repo, more) { B.said.set(saidKey(key, repo), { ...more, text, tone: tone || 'quiet' }); draw(); }
  function saidAt(key) {
    const m = B.said.get(saidKey(key));
    if (!m) return '';
    const p = h('p', `bench-said bench-said-${m.tone}`, m.text);
    p.dataset.said = key; p.setAttribute('role', 'status');
    return p;
  }
  const go = (page) => { B.page = page; draw(); };

  // ---- reads from the page server ----
  const live = () => obj(obj(B.d && B.d.bench) && B.d.bench.live);
  // `seq`, the read revision, goes up when the active step changes and `done` stays the same.
  const liveStamp = () => { const l = live(); return l ? `${l.id}|${l.state}|${l.done}|${l.seq}` : ''; };
  function getJSON(url) {
    return window.fetch(url).then((r) => (r.ok ? r.json() : r.text().then((t) => Promise.reject(new Error(String(t).trim() || `the server answered ${r.status}`)))));
  }
  function readHist(again) {
    const repo = B.repo, stamp = liveStamp(), was = B.hist;
    if (typeof repo !== 'string' || (!again && was && was.repo === repo && (was.busy || was.stamp === stamp))) return;
    const o = { repo, stamp, busy: true, data: was && was.repo === repo ? was.data : null, error: null };
    B.hist = o;
    getJSON(`bench?repo=${encodeURIComponent(repo)}`).then((x) => { if (obj(x)) o.data = x; else o.error = 'the answer did not read'; },
      (e) => { o.error = e && e.message ? e.message : 'no answer'; }).then(() => { o.busy = false; o.read = B.ctx.now(); if (B.hist === o) draw(); });
  }
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
  const runsOf = () => list(hist() && hist().runs).filter((r) => obj(r) && typeof r.id === 'string');
  const armsOf = () => list(hist() && hist().arms).filter((a) => obj(a) && typeof a.name === 'string');
  const colsOf = (r) => list(r && r.cols).filter(obj);
  // A run's place while the history is read, or why it could not be.
  function reading(what) {
    const o = B.hist;
    if (o && o.error && !o.data) {
      const box = B.ctx.state('error', `The Board could not read ${what}`, o.error);
      box.append(button('Read again', 'btn-quiet', 'read-again', 'Read the benchmarks again', () => readHist(true)));
      return box;
    }
    return B.ctx.state('empty',`Reading ${what}…`, 'The runs and their figures are read from the build machine when this tab is shown.');
  }

  // ---- actions (POST control, action bench) ----
  // While the answer is out, the action's message is `sending` (else "Sending…") and has out: true.
  function send(key, args, said, then, no, more, sending) {
    if (B.busy) { say(key, 'Wait for the answer to the last action.', 'warn'); return; }
    const repo = B.repo;
    B.busy = true; say(key, sending || 'Sending…', 'quiet', repo, { ...more, out: true });
    B.ctx.post('control', { action: 'bench', args, repo }).then((r) => r.text().then((t) => [r.ok, String(t).trim() || `the build machine answered ${r.status}`]),
      () => [false, 'the build machine did not answer']).then(([ok, text]) => {
      B.busy = false;
      if (ok && then && repo === B.repo) then(text);
      if (!ok && no) no();
      say(key, ok ? said(text) : `Not done: ${B.ctx.refusal(text)}`, ok ? 'ok' : 'bad', repo, more);
    });
  }

  // ---- shared pieces: the bars of a run, the page row ----
  // One bar an arm: its resolved tasks of n, with the noise band for n around it (a difference inside it is not one).
  function bars(cols, n, done) {
    const box = h('div', 'bench-bars'), d = noiseOf(n);
    cols.forEach((c) => {
      const v = done ? c.done : c.resolved, row = h('div', 'bench-bar'), name = h('span', 'bench-name', colName(c)), track = h('span', 'bench-track');
      if (!done && colSub(c)) name.append(h('span', 'bench-sub', colSub(c)));
      const fill = h('span', `bench-fill bench-s${group(c)}`);
      fill.style.width = `${n ? Math.min(100, (100 * (num(v) || 0)) / n) : 0}%`;
      track.append(fill);
      if (!done && n) {
        const z = h('span', 'bench-noise'), lo = Math.max(0, (num(v) || 0) - d), hi = Math.min(n, (num(v) || 0) + d);
        z.style.left = `${(100 * lo) / n}%`; z.style.width = `${(100 * (hi - lo)) / n}%`; z.title = `noise for n=${n}`;
        track.append(z);
      }
      const fig = h('span', 'bench-num');
      fig.append(h('strong', null, String(num(v) || 0)), ` of ${n}`);
      row.append(name, track, fig);
      box.append(row);
    });
    return box;
  }
  function legend(n) {
    const ul = h('ul', 'bench-legend');
    LEGEND.forEach(([g, t]) => { const li = h('li'); li.append(h('span', `bench-sw bench-s${g}`), t); ul.append(li); });
    const li = h('li'); li.append(h('span', 'bench-sw bench-sw-noise'), `the noise band for n = ${n}`); ul.append(li);
    return ul;
  }
  function pages() {
    const nav = h('nav', 'bench-pnav');
    nav.setAttribute('aria-label', 'Benchmarks pages');
    PAGES.forEach(([p, t]) => {
      const b = button(t, 'btn-quiet', `page-${p}`, t, () => go(p));
      if (B.page === p) b.setAttribute('aria-current', 'page');
      nav.append(b);
    });
    // While a run goes, every other view links to it.
    const l = live();
    if (l && l.state === 'running' && typeof l.id === 'string' && !(B.page === 'run' && (B.open || (runsOf()[0] && runsOf()[0].id)) === l.id)) {
      nav.append(button('Watch run', 'btn-link', 'watch-live', `Watch the run ${l.id}`, () => { openRun(l.id); draw(); }));
    }
    return nav;
  }
  const span = (r) => {
    const a = r.started ? B.ctx.when(r.started) : 'not read';
    return r.ended ? `${a} to ${B.ctx.when(r.ended)}` : a;
  };
  const STATE = { done: ['Done', 'ok'], stopped: ['Stopped', 'quiet'], guard: ['Stopped at the usage guard', 'warn'], refused: ['Did not start', 'bad'], running: ['Running', 'info'] };
  // A run whose process ended with no end written (bench swe's gone, kept on the end a Stop then records) was
  // interrupted, never stopped by you.
  const stateOf = (r) => (r.state === 'stopped' && r.gone === true ? ['Interrupted', 'warn'] : STATE[r.state] || [String(r.state || 'not read'), 'quiet']);

  // ---- Overview ----
  function newest() {
    const s = section('bench-newest', 'Newest run'), l = live(), runs = runsOf(), r = runs[0];
    const tools = h('div', 'bench-tools');
    if (r && r.state !== 'running') tools.append(button('Open the run', '', 'open-newest', `Open the run ${r.id}`, () => { B.open = r.id; B.task = null; go('run'); }));
    tools.append(button('Start a run', 'btn-primary', 'to-start', 'Start a run', () => go('start')));
    s.querySelector('.bench-head').append(tools);
    if (l && l.state === 'running') { s.append(running(l, r)); return s; }
    if (!hist()) { s.append(reading('the runs')); return s; }
    if (!r) {
      s.append(h('p', 'bench-empty', 'No benchmark has run. Start one with 1 task to check the arms work, or 20 for a first reading.'));
      return s;
    }
    const cols = colsOf(r), n = num(r.n) || 0;
    s.querySelector('.bench-head').append(h('span', 'board-from', `${r.id} · ${span(r)} · SWE-bench Verified, the first ${n} of the pinned order · ${plural(cols.length, 'arm')}, each task in its own Docker container`));
    if (r.state !== 'done') s.append(ended(r));
    if (!cols.length) return s;
    const head = h('p', 'bench-headline'), [a] = cols, other = cols.slice(1).sort((x, y) => (num(y.resolved) || 0) - (num(x.resolved) || 0))[0];
    head.append(`${colName(a)} resolved `, h('span', 'ok', `${a.resolved} of ${n}`), other ? `; ${colName(other)} ${other.resolved} of ${n}.` : '.');
    const versus = cols[1] ? ` ${colName(cols[0])} against ${colName(cols[1])} (${cols[0].resolved} against ${cols[1].resolved}) is ${!gradedAll(cols[0], n) || !gradedAll(cols[1], n) ? 'not compared: not every task was graded for both' : Math.abs(cols[0].resolved - cols[1].resolved) < noiseOf(n) ? 'not a difference' : 'past the noise'}.` : '';
    head.append(' ', h('span', 'board-from', `${noiseSaid(n)}${versus}`));
    s.append(head, bars(cols, n), legend(n));
    const figs = h('div', 'figures bench-figures');
    cols.forEach((c) => {
      const f = h('div', 'figure');
      f.append(h('span', costOf(c.cost).state === 'unknown' ? 'num unknown' : 'num', costSaid(c.cost)), h('span', 'figure-label', `${colName(c)}: ${num(c.sessions) === null ? '–' : c.sessions} sessions · ${tokens(c.tokens)} tokens · ${took(c.minutes)}`),
        h('span', 'figure-label', 'cost at list prices'));
      figs.append(f);
    });
    s.append(figs, care(cols));
    return s;
  }
  // The notes to read a run's figures with.
  function care(cols) {
    const row = h('div', 'bench-care');
    row.append(h('span', 'board-label', 'Read with care'), B.ctx.chip('Graded by the official SWE-bench harness: FAIL_TO_PASS and PASS_TO_PASS', 'quiet'));
    cols.filter((c) => c.notRun > 0).forEach((c) => row.append(B.ctx.chip(`${plural(c.notRun, 'task')} not run for ${colName(c)}: its harness image, sandbox or grade failed (not counted as failed)`, 'quiet')));
    row.append(B.ctx.chip('Python tasks only; the models may have seen these repositories', 'quiet'), B.ctx.chip(COST_WHY, 'quiet'));
    return row;
  }
  // How the newest run ended when it did not end done: stopped by the owner, at the usage guard, refused (an arm's
  // preflight failed before it started, or the build machine had no Docker or harness to run it), or interrupted (its
  // process gone with no end written: gone; once a Stop recorded its end, gone stays and ended is set).
  function ended(r) {
    const p = h('p', 'bench-ended'), cols = colsOf(r), n = num(r.n) || 0, least = cols.length ? Math.min(...cols.map((c) => num(c.done) || 0)) : 0;
    if (r.state === 'refused') {
      const m = /the arm ([a-z0-9-]+) cannot run: its preflight failed: (.*)/.exec(String(r.why || ''));
      p.append(B.ctx.chip(m ? `${m[1]}: preflight failed` : 'Did not start', 'bad'), ` ${String(m ? m[2] : r.why || 'no reason recorded').replace(/\.?$/, '.')} ${m ? 'The arm cannot be picked until its preflight succeeds. ' : ''}`,
        button('See arms', 'btn-quiet btn-sm', 'see-arms', 'See the arms', () => go('start')));
    } else if (r.state === 'guard') {
      const behind = cols.filter((c) => (num(c.done) || 0) < n).map(colName);
      p.append(B.ctx.chip('Stopped at the usage guard', 'warn'), ` ${behind.length ? behind.join(' and ') : 'Every arm'} did ${least} of ${n} tasks. Start again later: the rest runs, the done tasks are reused.`);
    } else if (r.gone === true && r.ended) {
      p.append(B.ctx.chip('Run interrupted', 'warn'), ` Its process ended before Stop, after ${least} of ${n} tasks for every arm. Stop recorded its end and removed its containers. The finished tasks are kept and reused.`);
    } else if (r.gone === true) {
      p.append(B.ctx.chip('Run interrupted', 'warn'), ` Its process ended with no end recorded, after ${least} of ${n} tasks for every arm. Stop run, on the page of the run, records its end and removes its containers. The finished tasks are kept and reused.`);
    } else {
      p.append(B.ctx.chip('Stopped by you', 'quiet'), ` ${least} of ${n} tasks done for every arm. The finished tasks are kept and reused.`);
    }
    return p;
  }
  // Stop run: it names the run shown (`bench swe stop <id>`: a Stop that comes late never stops the run after it), says
  // "Stopping" and stays off until the build machine answers, which it does once the run and its containers ended
  // (swe_stop), with how the run ended (swe_said). Its answer is kept by run, so it shows on that run's page after.
  const STOPPED = [[/ is stopped\./, 'Run stopped. Finished results are kept.'], [/ was interrupted: /, 'Run interrupted: its process had ended. Its end is recorded, its containers are removed and its finished results are kept.'],
    [/ finished before Stop\./, 'Run finished before Stop.'], [/ at the usage guard before Stop\./, 'Run had stopped at the usage guard before Stop.'], [/ did not start, before Stop\./, 'Run did not start, before Stop.']];
  function stopRun(id, stopping) {
    const key = `stop-${id}`, m = B.said.get(saidKey(key)), out = Boolean(m && m.out) || Boolean(stopping);
    const b = button(out ? 'Stopping run' : 'Stop run', 'btn-sm', 'stop-run', `Stop the run ${id}`, () => send(key, ['stop', id], (t) => { const s = STOPPED.find(([re]) => re.test(t)); return s ? s[1] : t.replace(/^conveyor: /, ''); },
      () => { readHist(true); const o = B.runs.get(`${B.repo}|${id}`); if (o) o.stamp = null; }, null, null, `Stopping run ${id}. Finished results are kept.`));
    b.disabled = out;
    return b;
  }
  // The run in progress: the snapshot's live record (tasks done a arm, the task now) with Stop run.
  function running(l, r) {
    const box = h('div', 'bench-running'), arms = list(l.arms).length ? list(l.arms) : [l.arm], n = Math.floor((num(l.n) || 0) / Math.max(arms.length, 1));
    const cols = (list(l.cols).length ? list(l.cols) : arms.map((a) => ({ arm: a, label: a }))).map((c) => ({ ...c, done: list(l.tasks).filter((t) => obj(t) && t.arm === c.arm).length }));
    const line = h('p', 'bench-state');
    line.append(B.ctx.chip('Running', 'info'), ` ${plural(cols.length, 'arm')} on ${plural(n, 'task')}${l.current ? ` · now ${l.current}` : ''} `, stopRun(l.id, typeof l.stopping === 'string'));
    box.append(line, saidAt(`stop-${l.id}`), bars(cols, n, true));
    const so = r && r.state === 'running' ? colsOf(r).reduce((s, c) => s + (num(c.sessions) || 0), 0) : null;
    const per = (c) => obj((armsOf().find((a) => a.name === c.arm) || {}).perTask);
    const usual = cols.every(per) ? Math.ceil(cols.reduce((s, c) => s + n * per(c).usual, 0)) : null, worst = cols.every(per) ? cols.reduce((s, c) => s + n * per(c).worst, 0) : null;
    box.append(h('span', 'board-from', `tasks done by each arm${so === null ? '' : ` · ${so} sessions so far`}${usual === null ? '' : `, usual for the run ${usual}, worst case ${worst}`}`));
    return box;
  }
  function history() {
    const runs = runsOf(), s = section('bench-history', 'History', runs.length, 'Every run, newest first. Tick runs, then Compare or Generate infographic. Runs of the same task set and n can be read side by side.');
    if (!hist()) { s.append(reading('the runs')); return s; }
    if (!runs.length) { s.append(h('p', 'board-from', 'No run yet.')); return s; }
    const shown = B.older ? runs : runs.slice(0, 20), sets = new Map();
    shown.forEach((r) => { const k = obj(r.set) ? `${r.set.dataset} at ${String(r.set.revision || '').slice(0, 7)}` : 'task set not recorded'; if (!sets.has(k)) sets.set(k, []); sets.get(k).push(r); });
    sets.forEach((rs, k) => {
      if (sets.size > 1 || k === 'task set not recorded') s.append(h('p', 'bench-set', k));
      const wrap = h('div', 'tests-scroll'), t = h('table', 'tests-table bench-table'), head = h('tr');
      ['', 'Run', 'When', 'Tasks', 'Arms and versions', 'Resolved, by arm', 'Sessions', 'Tokens', 'Took', 'Cost', 'State'].forEach((x, i) => head.append(h('th', i >= 3 && i !== 4 && i !== 10 ? 'r' : null, x)));
      t.append(head);
      rs.forEach((r) => {
        const tr = h('tr', B.sel.includes(r.id) ? 'picked' : null), cols = colsOf(r), box = h('input');
        tr.dataset.run = r.id;
        box.type = 'checkbox'; box.checked = B.sel.includes(r.id); box.dataset.act = `pick-${r.id}`; box.setAttribute('aria-label', `Select ${r.id}`);
        box.disabled = !box.checked && B.sel.length >= MAX_SEL;
        box.addEventListener('change', () => { B.sel = box.checked ? B.sel.concat(r.id).slice(-MAX_SEL) : B.sel.filter((x) => x !== r.id); draw(); });
        const link = button(r.id, 'btn-link mono', `run-${r.id}`, `Open the run ${r.id}`, () => { B.open = r.id; B.task = null; go('run'); });
        const sum = (k) => (cols.some((c) => num(c[k]) === null) ? null : cols.reduce((x, c) => x + c[k], 0));
        const [word, tone] = stateOf(r);
        const state = h('td'), n = num(r.n) || 0, res = cols.map((c) => num(c.resolved) || 0), notRun = cols.reduce((x, c) => x + (num(c.notRun) || 0), 0);
        const spread = res.length > 1 ? Math.max(...res) - Math.min(...res) : null;
        state.append(B.ctx.chip(word, tone), [notRun ? ` ${plural(notRun, 'task')} not run` : '', r.state === 'done' && spread !== null && cols.every((c) => gradedAll(c, n)) && spread < noiseOf(n) ? ` within the noise${noiseOf(n) >= n ? `: only a total break shows at ${n}` : ` (${noiseOf(n)})`}` : ''].join(''));
        if (r.state === 'refused' && r.why) state.append(h('span', 'bench-sub', String(r.why)));
        const cells = [h('td'), h('td'), h('td', null, B.ctx.when(r.started)), h('td', 'r', String(n)), h('td', 'bench-arms-cell', cols.map(colName).join(' · ')), h('td', 'r', res.join(' · ')),
          h('td', 'r', sum('sessions') === null ? '–' : String(sum('sessions'))), h('td', 'r', tokens(sum('tokens'))), h('td', 'r', took(sum('minutes'))), h('td', 'r', costSaid(r.cost)), state];
        cells[0].append(box); cells[1].append(link);
        tr.append(...cells);
        t.append(tr);
      });
      wrap.append(t);
      s.append(wrap);
    });
    const foot = h('p', 'board-from');
    if (runs.length > 20) foot.append(button(B.older ? 'Show fewer' : 'Show older', 'btn-link', 'older', B.older ? 'Show the newest 20 runs' : 'Show every run', () => { B.older = !B.older; draw(); }), ' · ');
    foot.append(button('Infographic', 'btn-link', 'to-infographic', 'Open the infographic page', () => go('infographic')), ' · Results of the same arm, version and task are reused, never run again.');
    s.append(foot);
    return s;
  }
  function armsPart() {
    const arms = armsOf(), s = section('bench-arms', 'Arms', hist() ? arms.length : null, 'An arm is one way to build a task, with a preflight: a file in conveyor/bench/arms/, or an arm saved on Start a run.');
    if (!hist()) { s.append(reading('the arms')); return s; }
    const t = h('table', 'tests-table'), rows = [['Ready', (a) => a.state === 'ready', 'ok'], ['Checking', (a) => a.state === 'checking', 'quiet'], ['Preflight failing', (a) => a.state === 'failed', 'bad'],
      ['Not checked', (a) => a.state === 'unchecked' || a.state === 'changed' || a.state === 'expired', 'quiet'], ['Not offered', (a) => a.state === 'not offered', 'quiet']];
    rows.forEach(([name, is, tone]) => {
      const these = arms.filter(is), tr = h('tr'), v = h('td', 'r');
      v.append(h('span', tone === 'bad' && these.length ? 'bad' : tone === 'quiet' ? 'muted' : null, String(these.length)));
      // A check that runs says the step it is at; another state, why.
      const why = (a) => (a.state === 'checking' ? String(a.step || 'Starting the test container') : a.why);
      if (these.length && name !== 'Ready') v.append(h('span', 'bench-sub', these.map((a) => `${a.label}${why(a) ? `: ${why(a)}` : ''}`).join(' · ')));
      tr.append(h('td', 'bench-name', name), v);
      t.append(tr);
    });
    s.append(t, button('See every arm', 'btn-quiet btn-sm', 'see-every-arm', 'See every arm on Start a run', () => go('start')));
    return s;
  }
  // The drift watch (`conveyor.sh bench drift`, the snapshot's drift): the ended cards of the latest engine commit
  // against those of the one before, a mean a card of each figure; a group of fewer than 5 cards is too small to mean anything.
  function drift() {
    const dr = obj(B.d && B.d.drift), s = section('bench-drift', 'Drift watch', null, 'The project\'s own cards before and after the last engine change. It says "moved", never better or worse.');
    if (!dr) { s.append(h('p', 'board-from', 'No drift watch yet: it needs cards on two engine commits.')); return s; }
    const b = obj(dr.before) || {}, a = obj(dr.after) || {}, v = (x) => (num(x) === null ? '-' : String(x)), sha = (g) => String(g.engine || '').slice(0, 7);
    const small = list(dr.small).some((k) => k === 'before' || k === 'after');
    // A figure moved when the two means are more than two standard errors apart (each group's spread a card, from
    // drift.sh; Blocked is the share of cards blocked). With a group too small, or no spread read, it is not judged.
    const status = (k) => {
      const nb = num(k === 'reviews' ? b.landed : b.cards), na = num(k === 'reviews' ? a.landed : a.cards);
      if (small) return ['Too few cards', 'quiet'];
      let d, se;
      if (k === 'blocked') {
        if (!nb || !na || num(b.blocked) === null || num(a.blocked) === null) return ['Not read', 'quiet'];
        const pb = b.blocked / nb, pa = a.blocked / na;
        d = Math.abs(pa - pb); se = Math.sqrt(pb * (1 - pb) / nb + pa * (1 - pa) / na);
      } else {
        const sb = num((obj(b.spread) || {})[k]), sa = num((obj(a.spread) || {})[k]);
        if (!nb || !na || sb === null || sa === null || num(b[k]) === null || num(a[k]) === null) return ['Not read', 'quiet'];
        d = Math.abs(a[k] - b[k]); se = Math.sqrt(sb * sb / nb + sa * sa / na);
      }
      return d > 2 * se ? ['Moved', 'warn'] : ['In its usual range', 'quiet'];
    };
    const rows = [['Tokens', 'tokens'], ['Minutes', 'minutes'], ['Reviews to land', 'reviews'], ['Fix rounds', 'fixes'], ['Blocked', 'blocked'], ['Minutes waited', 'waits']].map(([n, k]) => [n, k, status(k)]);
    const moved = rows.filter(([, , [w]]) => w === 'Moved').length;
    const box = h('details', 'bench-drift-box'), sum = h('summary', null, `Engine ${sha(b)} → ${sha(a)} · ${plural(num(b.cards) || 0, 'card')} before, ${num(a.cards) || 0} since${small ? '' : ` · ${plural(moved, 'figure')} moved`}`);
    box.append(sum);
    const t = h('table', 'tests-table'), head = h('tr');
    ['Figure, a card', 'Before', 'Since', ''].forEach((x, i) => head.append(h('th', i === 1 || i === 2 ? 'r' : null, x)));
    t.append(head);
    rows.forEach(([n, k, [word, tone]]) => {
      const tr = h('tr'), st = h('td'); st.append(B.ctx.chip(word, tone)); tr.append(h('td', 'bench-name', n), h('td', 'r', v(b[k])), h('td', 'r', v(a[k])), st); t.append(tr);
    });
    box.append(t);
    list(dr.small).filter((k) => k === 'before' || k === 'after').forEach((k) => {
      box.append(h('p', 'warn-note', `The ${k} group holds ${plural(num((k === 'before' ? b : a).cards) || 0, 'card')}: too small to mean anything (fewer than 5 cards).`));
    });
    s.append(box);
    return s;
  }
  function selbar() {
    const bar = h('div', 'bench-selbar');
    bar.setAttribute('role', 'status');
    bar.append(h('strong', null, `${plural(B.sel.length, 'run')} selected`), h('span', 'board-from', `Up to ${MAX_SEL}. Runs of different n get their own panel on the infographic.`),
      button('Compare', '', 'sel-compare', 'Compare arms of the runs selected', () => { dropCmp(); go('compare'); }),
      button('Generate infographic', 'btn-primary', 'sel-infographic', 'Generate the infographic of the runs selected', () => go('infographic')),
      button('Clear', 'btn-quiet', 'sel-clear', 'Clear the selection', () => { B.sel = []; draw(); }));
    return bar;
  }

  // ---- A run ----
  function runPage() {
    const runs = runsOf(), id = B.open || (runs[0] && runs[0].id);
    if (!hist() && !B.open) return [reading('the runs')];
    if (!id) return [B.ctx.state('empty', 'No run to show', 'Start a run: its tasks and each arm\'s results show here.')];
    const o = readRun(id);
    if (!o || !o.data) return [o && o.error ? B.ctx.state('error', `The Board could not read the run ${id}`, o.error) : B.ctx.state('empty',`Reading the run ${id}…`, 'Its tasks are read from the build machine when it is opened.')];
    const r = o.data.run, tasks = list(o.data.tasks).filter(obj), cols = colsOf(r), n = num(r.n) || 0, going = r.state === 'running';
    const s = section('bench-run-head', `Run ${r.id}`), hd = s.querySelector('.bench-head');
    // Its first line: its state, its wall time (setup and grading with it) and, while it goes, Stop run. Once it ended,
    // the same line gives how it ended, and Stop's answer stays under it.
    // A run whose process is gone with no end written (gone, no ended) keeps Stop run: it records the end and removes
    // the containers. Once recorded, it still reads Interrupted (stateOf).
    const unended = r.state === 'stopped' && r.gone === true && !r.ended;
    const [word, tone] = going && r.stopping ? ['Stopping', 'warn'] : stateOf(r);
    // While it goes, its wall time counts on the Board's clock (ctx.since): an agent in one phase sends no update.
    const wall = h('span', 'board-from bench-wall', 'Elapsed ');
    wall.append(going && Number.isFinite(Date.parse(r.started)) ? B.ctx.since(r.started, '') : took(elapsed(r)));
    hd.append(B.ctx.chip(word, tone), wall);
    if (going || unended) hd.append(stopRun(r.id, typeof r.stopping === 'string'));
    const last = latest(r.id);
    if (last) hd.append(last);
    const tools = h('div', 'bench-tools');
    tools.append(button('Back', 'btn-quiet', 'back', 'Back to the overview', () => go('overview')),
      button('Compare two arms', '', 'run-compare', 'Compare two arms of this run', () => { B.sel = B.sel.includes(r.id) ? B.sel : [r.id]; dropCmp(); go('compare'); }),
      button('Export figures', '', 'export', 'Export the figures as one JSON file', () => exportRun(o.data)));
    hd.append(tools);
    s.append(saidAt(`stop-${r.id}`));
    if (going) s.append(...progress(r, tasks, cols, n));
    // A read that got no answer keeps the last update on the page, and says so.
    if (o.error) {
      const p = h('p', 'warn-note bench-lost', `The last read of this run got no answer: ${o.error}. The page shows ${typeof r.updated === 'string' ? `the update of ${B.ctx.clock(r.updated)}` : 'the last update read'}. `);
      p.append(button('Read again', 'btn-quiet btn-sm', 'run-read-again', `Read the run ${r.id} again`, () => { o.stamp = null; draw(); }));
      s.append(p);
    }
    s.append(h('p', 'board-from', `${span(r)} · SWE-bench Verified (dataset revision pinned in conveyor/bench/swe.json) · the first ${n} tasks of the pinned order · ${plural(cols.length, 'arm')} · each task in its own Docker container`),
      saidAt(`export-${r.id}`), h('p', 'board-from', `${noiseSaid(n)} Export writes the figures as one JSON file: no code, no names, no machine names.`));
    if (r.state === 'stopped' || r.state === 'guard' || r.state === 'refused') s.append(ended(r));
    s.append(bars(cols, n));
    const m = section('bench-matrix', 'Tasks by arm', `${plural(tasks.length, 'task')} · ${plural(cols.length, 'arm')}`, '✓ resolved · ✗ not resolved · not run: the harness image, sandbox or grade failed. Each cell: sessions · minutes · cost at list prices. A reused result adds no cost. A task not run or interrupted shows the cost of its work. Open a task to see each arm\'s work.');
    const wrap = h('div', 'tests-scroll'), t = h('table', 'tests-table bench-mat'), head = h('tr');
    head.append(h('th', null, 'Task'));
    cols.forEach((c) => { const th = h('th', null, colName(c)); if (colSub(c)) th.append(h('span', 'bench-sub', colSub(c))); head.append(th); });
    t.append(head);
    tasks.forEach((x) => {
      const tr = h('tr', B.task === x.id ? 'open' : null), first = h('td');
      tr.dataset.task = x.id;
      first.append(button(x.id, 'btn-link mono', `task-${x.id}`, `Open the task ${x.id}`, () => { B.task = B.task === x.id ? null : x.id; draw(); }));
      tr.append(first, ...list(x.cells).map((c) => cell(c)));
      t.append(tr);
    });
    const tot = [['Resolved', (c) => `${c.resolved} of ${n}`], ['Sessions · tokens', (c) => `${num(c.sessions) === null ? '–' : c.sessions} · ${tokens(c.tokens)}`],
      ['Minutes · cost', (c) => `${num(c.minutes) === null ? '–' : Math.round(c.minutes)} · ${costSaid(c.cost)}`]];
    const foot = h('tfoot');
    tot.forEach(([name, f]) => { const tr = h('tr'); tr.append(h('td', 'bench-name', name), ...cols.map((c) => h('td', null, f(c)))); foot.append(tr); });
    t.append(foot);
    wrap.append(t);
    m.append(wrap);
    const out = [s, m];
    const open = tasks.find((x) => x.id === B.task);
    if (open) out.push(taskPart(open, cols));
    // The run's event log (`bench swe show`'s tail), its last LOGN lines, kept after the run ends.
    const tail = list(o.data.tail).filter(obj).slice(-LOGN);
    if (tail.length) {
      const lg = section('bench-log', 'Recent log', null, `The last ${LOGN} events at most. They stay with the run.`), ol = h('ol', 'bench-loglines');
      tail.forEach((e) => {
        const li = h('li'), c = cols.find((x) => x.arm === e.arm);
        li.append(h('span', 'mono', B.ctx.clock(e.at)), h('span', null, e.arm ? (c ? colName(c) : String(e.arm)) : 'Run'), h('span', 'mono', e.task ? String(e.task) : ''), h('span', null, String(e.event || '')));
        ol.append(li);
      });
      lg.append(ol);
      out.push(lg);
    }
    return out;
  }
  const LOGN = 20;
  // A run's wall time in minutes, from its start to its end; null when not read (or not ended).
  const elapsed = (r) => { const a = Date.parse(r.started), b = Date.parse(r.ended); return Number.isFinite(a) && Number.isFinite(b) ? Math.max(0, (b - a) / 60000) : null; };
  // Latest result, beside a page's heading: the newest run that is not going, unless it is the run shown.
  function latest(shown) {
    const r = runsOf().find((x) => x.state !== 'running');
    return r && r.id !== shown ? button('Latest result', 'btn-link', 'latest', `Open the run ${r.id}`, () => { openRun(r.id); draw(); }) : null;
  }
  // A run that goes, under its first line: the arm, task and step it is at; the arm and task pairs finished of all it
  // plans (a not run among them), resolved, reused, not run and its cost so far; then each arm's.
  function progress(r, tasks, cols, n) {
    const a = obj(r.active), at = a && cols.find((c) => c.arm === a.arm), sum = (k) => cols.reduce((x, c) => x + (num(c[k]) || 0), 0);
    const work = (x) => [typeof x.task === 'string' ? x.task : null, typeof x.phase === 'string' && x.phase ? x.phase : 'Running'].filter(Boolean).join(' · ');
    const now = h('p', 'bench-now');
    now.append(a ? `Now: ${at ? colName(at) : String(a.arm)} · ${work(a)}` : 'Now: between two tasks.');
    if (a && typeof a.since === 'string') now.append(' ', h('span', 'board-from', `since ${B.ctx.clock(a.since)}`));
    // Each arm's cells: reused counts its results taken from an earlier run. Active time is the wall minutes of the
    // arm's work in this run (bench swe's wall: each task it ran, a task not run included; a reused result adds none)
    // and, for the arm at work, the time since its task began (active.start), counted on the Board's clock (ctx.since).
    const of = (c) => tasks.flatMap((t) => list(t.cells).filter((x) => obj(x) && x.arm === c.arm));
    const reusedOf = (c) => of(c).filter((x) => x.reused === true).length;
    const activeOf = (c) => (a && a.arm === c.arm && Number.isFinite(Date.parse(a.start)) ? B.ctx.since(a.start, '', (num(c.wall) || 0) * 60) : took(num(c.wall)));
    // The active session's cost is unknown only once it has one: a task still preparing its image has no session yet.
    const k = costOf(r.cost), price = k.state === 'known' ? `Recorded list price ${B.ctx.money(k.usd)}.`
      : k.state === 'partial' ? `${B.ctx.money(k.usd)} recorded. ${a && obj(a.cost) && costOf(a.cost).state !== 'known' ? 'Cost for the active session is unknown.' : 'Part of the cost is unknown.'}` : 'Cost unknown.';
    const figs = h('p', 'bench-sofar', `${sum('done')} of ${n * cols.length} arm results finished · ${sum('resolved')} resolved · ${cols.reduce((x, c) => x + reusedOf(c), 0)} reused · ${sum('notRun')} not run · ${price}`);
    if (typeof r.updated === 'string') figs.append(' ', h('span', 'board-from', `Last update ${B.ctx.clock(r.updated)}`));
    const t = h('table', 'tests-table bench-live'), hr = h('tr');
    ['Arm', 'Finished', 'Resolved', 'Reused', 'Not run', 'Current work', 'Active time', 'Cost so far'].forEach((x, i) => hr.append(h('th', i && i !== 5 ? 'r' : null, x)));
    t.append(hr);
    cols.forEach((c) => {
      const tr = h('tr'), d = num(c.done) || 0, act = h('td', 'r');
      tr.dataset.arm = c.arm; act.append(activeOf(c));
      tr.append(h('td', 'bench-name', colName(c)), h('td', 'r', `${d} of ${n}`), h('td', 'r', String(num(c.resolved) || 0)), h('td', 'r', String(reusedOf(c))),
        h('td', 'r', String(num(c.notRun) || 0)), h('td', null, a && a.arm === c.arm ? work(a) : d >= n ? 'Finished' : 'Waiting'), act, h('td', 'r', costSaid(c.cost)));
      t.append(tr);
    });
    const wrap = h('div', 'tests-scroll');
    wrap.append(t);
    return [now, figs, wrap];
  }
  const said = (c) => (c.result === 'resolved' || c.resolved === true ? 'yes' : typeof c.result === 'string' && c.result.startsWith('not run') ? 'nr' : c.result || c.resolved === false ? 'no' : null);
  // A cell with no result yet, by the state `bench swe show` gives it: the step of the arm's work on the task now, waiting
  // (the run goes and has not reached it), interrupted (Stop ended it) or not reached (a line with no state, or the run ended first).
  const pend = (c) => (c.state === 'active' ? (typeof c.phase === 'string' && c.phase ? c.phase : 'active') : c.state === 'waiting' || c.state === 'interrupted' ? c.state : 'not reached');
  const PENDSAID = { waiting: 'The run has not reached this task for this arm yet.', interrupted: 'Stop ended the work of this arm on this task. No result is kept.' };
  function cell(c) {
    const td = h('td', 'bench-cell'), k = said(c);
    // A task not run, and the work Stop interrupted, show the cost of the work done on them (bench swe show's cost).
    if (k === null) { td.append(h('span', 'muted', pend(c))); if (c.state === 'interrupted') td.append(h('span', 'bench-sub', costSaid(c.cost))); return td; }
    td.append(h('span', k, k === 'yes' ? '✓' : k === 'no' ? '✗' : 'not run'));
    td.append(h('span', 'bench-sub', k === 'nr' ? `${String(c.result).replace(/^not run: /, '')} · ${costSaid(c.cost)}` : `${plural(num(c.sessions) || 0, 'session')} · ${took(c.minutes)} · ${c.reused ? 'reused, no new cost' : costSaid(c.cost)}`));
    return td;
  }
  // One task opened: each arm's card, its patch, its steps and the harness's grade.
  function taskPart(x, cols) {
    const cells = list(x.cells), yes = cells.filter((c) => said(c) === 'yes').length, no = cells.filter((c) => said(c) === 'no').length;
    const s = section('bench-task', `${x.id}, opened`, null, `${x.title ? `${x.title} · ` : ''}${yes} ${yes === 1 ? 'arm' : 'arms'} resolved, ${no} did not`);
    s.querySelector('.bench-head').append(button('Close', 'btn-quiet btn-sm', 'task-close', 'Close the task', () => { B.task = null; draw(); }));
    const cards = h('div', 'bench-cards');
    cells.forEach((c, i) => {
      const col = cols[i] || { arm: c.arm }, k = said(c), card = h('div', 'bench-card'), h3 = h('h3');
      h3.append(h('span', k || 'muted', k === 'yes' ? '✓' : k === 'no' ? '✗' : '–'), ` ${colName(col)} `, B.ctx.chip(k === 'yes' ? 'resolved' : k === 'no' ? 'not resolved' : k === 'nr' ? 'not run' : pend(c), k === 'yes' ? 'ok' : k === 'no' ? 'bad' : 'quiet'));
      card.append(h3);
      if (k === 'nr') { card.append(h('p', 'board-from', String(c.result))); cards.append(card); return; }
      // An arm with no result on this task has no patch and no harness result to show: it is on the task now, waits,
      // was interrupted by Stop, or the run ended before it reached the task.
      if (k === null) {
        card.append(h('p', 'board-from', c.state === 'active' ? `This arm is on the task now: ${pend(c).replace(/\.$/, '')}.` : Object.hasOwn(PENDSAID, c.state) ? PENDSAID[c.state] : 'The run stopped before this arm reached the task.'));
        cards.append(card); return;
      }
      const files = Array.isArray(c.patch) ? c.patch : null;
      const add = files ? files.reduce((a, f) => a + (num(f.added) || 0), 0) : 0, del = files ? files.reduce((a, f) => a + (num(f.removed) || 0), 0) : 0;
      const steps = list(c.steps).filter(obj);
      const kind = isConveyor(col) || steps.length ? '' : ` · ${sessionsWord(c.sessions) ? `${sessionsWord(c.sessions)}, ` : ''}${took(c.minutes)}, ${tokens(c.tokens)} tokens${c.fired === false ? ` · the method did not fire${c.why ? `: ${c.why}` : ''}` : ''}`;
      card.append(h('p', 'board-from', files === null ? `Patch: none kept${kind}` : files.length ? `Patch: ${plural(files.length, 'file')}, +${add} −${del} · ${files.map((f) => f.path).join(', ')}${kind}` : `Patch: empty${kind}`));
      if (steps.length) card.append(stepList(steps));
      card.append(h('p', 'board-from', `Harness: ${c.resolved === true ? 'resolved' : c.fired === false ? 'not graded: the arm did not fire' : 'not resolved'}. FAIL_TO_PASS and PASS_TO_PASS counts are not kept yet.`));
      cards.append(card);
    });
    s.append(cards);
    return s;
  }
  // A Conveyor arm's steps from its card's records: the build, each review with its verdict and first finding, each fix
  // round, the test step and how the card ended.
  function stepList(steps) {
    const ol = h('ol', 'bench-steps'), n = { review: 0, fix: 0 };
    const tok = (s) => { const t = obj(s.tokens); const v = t ? (num(t.claude) || 0) + (num(t.codex) || 0) : 0; return v ? ` · ${tokens(v)} tokens` : ''; };
    steps.forEach((s) => {
      let chip = null, text = '';
      if (s.step === 'build') { chip = ['Build', 'quiet']; text = tok(s).replace(/^ · /, ''); }
      else if (s.step === 'review') { n.review += 1; const go2 = s.result === 'GO'; chip = [`Review ${n.review}`, go2 ? 'ok' : 'bad']; text = `${s.result || ''}${s.tail || s.reason ? ` · ${String(s.tail || s.reason).split('\n')[0].slice(0, 160)}` : ''}`; }
      else if (s.step === 'fix') { n.fix += 1; chip = [`Fix ${n.fix}`, 'quiet']; text = tok(s).replace(/^ · /, ''); }
      else if (s.step === 'rebase') chip = ['Rebase', 'quiet'];
      else if (s.step === 'test') { chip = ['Test step', s.result === 'fail' ? 'bad' : 'ok']; text = String(s.result || ''); }
      else if (s.step === 'blocked') { chip = ['Blocked', 'bad']; text = String(s.reason || '').slice(0, 200); }
      else if (s.step === 'landed') chip = ['Landed', 'ok'];
      if (!chip) return;
      const li = h('li');
      li.append(B.ctx.chip(chip[0], chip[1]), text ? ` ${text}` : '');
      ol.append(li);
    });
    return ol;
  }
  // Export figures: one JSON file of the run's figures, with no code (no patch, no steps), no names (no task title,
  // no finding, no reason) and no machine names.
  function exportRun(data) {
    const r = data.run, cols = colsOf(r);
    const figs = { run: r.id, benchmark: 'SWE-bench Verified', set: obj(r.set) ? { dataset: r.set.dataset, revision: r.set.revision } : null, started: r.started || null, ended: r.ended || null,
      tasksPerArm: r.n, state: r.state, cost: costOf(r.cost),
      arms: cols.map((c) => ({ arm: c.arm, label: colName(c), version: c.version || null, engine: c.engine || null, model: c.model || null, done: c.done, resolved: c.resolved, notRun: c.notRun, sessions: c.sessions, tokens: c.tokens, minutes: c.minutes,
        cost: costOf(c.cost) })),
      // Each cost is {usd, state} (costOf): a reused result's is the known $0 it added to this run.
      tasks: list(data.tasks).filter(obj).map((x) => ({ task: x.id, arms: list(x.cells).map((c) => ({ arm: c.arm, result: said(c) === 'yes' ? 'resolved' : said(c) === 'no' ? 'not resolved' : said(c) === 'nr' ? 'not run' : null,
        sessions: num(c.sessions), tokens: num(c.tokens), minutes: num(c.minutes), reused: c.reused === true, cost: c.reused === true ? { usd: 0, state: 'known' } : costOf(c.cost) })) })) };
    download(`bench-${r.id}.json`, `data:application/json;charset=utf-8,${encodeURIComponent(JSON.stringify(figs, null, 2))}`);
    say(`export-${r.id}`, `Exported: bench-${r.id}.json.`, 'ok');
  }
  function download(name, href) {
    const a = h('a');
    a.href = href; a.download = name; a.hidden = true;
    document.body.append(a); a.click(); a.remove();
  }

  // ---- Compare ----
  // Compare's answer belongs to one request (ask, keyed compare-<n>-<a>-<b>): dropping the results drops the answer with
  // them, so a pair chosen again, or a reply that comes after the pair changed, never reads "Compared." beside no results.
  function dropCmp() { B.cmp.data = null; B.cmp.text = null; B.cmp.ask = null; }
  function sidesOf() {
    const runs = runsOf(), picked = B.sel.length ? runs.filter((r) => B.sel.includes(r.id)) : runs.filter((r) => r.id === (B.open || (runs[0] && runs[0].id)));
    const seen = new Map();
    picked.forEach((r) => colsOf(r).forEach((c) => { if (typeof c.key === 'string' && c.key && !seen.has(c.key)) seen.set(c.key, c); }));
    return Array.from(seen.values());
  }
  // A side's cost for each task it resolved (`bench swe diff`'s totals.cost), recorded, in part or unknown as its cost is.
  const perResolved = (x) => { const k = costOf(x.cost); return !num(x.resolved) ? '–' : costSaid(k.usd === null ? k : { ...k, usd: k.usd / x.resolved }); };
  function comparePage() {
    if (!hist()) return [reading('the runs')];
    const sides = sidesOf(), s = section('bench-compare', 'Compare');
    const tools = h('div', 'bench-tools');
    tools.append(button('Back', 'btn-quiet', 'back', 'Back to the overview', () => go('overview')));
    if (sides.length < 2) {
      s.querySelector('.bench-head').append(tools);
      s.append(h('p', 'board-from', 'Compare needs two arms with results: tick runs on the Overview\'s History, or open a run with two arms or more.'));
      return [s];
    }
    const choose = (which) => {
      const l = h('label', 'board-from'), sel = h('select', 'field');
      sel.dataset.act = `cmp-${which}`; sel.setAttribute('aria-label', which.toUpperCase());
      sides.forEach((c) => { const o = h('option', null, colName(c)); o.value = c.key; sel.append(o); });
      if (!sides.some((c) => c.key === B.cmp[which])) B.cmp[which] = sides[which === 'a' ? 0 : 1].key;
      sel.value = B.cmp[which];
      sel.addEventListener('change', () => { B.cmp[which] = sel.value; dropCmp(); draw(); });
      l.append(`${which.toUpperCase()} `, sel);
      return l;
    };
    tools.append(choose('a'), choose('b'), button('Compare', 'btn-primary', 'compare', 'Compare A and B', () => {
      // A click while an action is out is refused before anything changes: the request in flight keeps its ask, so its
      // reply is still read; with none (another action is out) the refusal gets an ask of its own to be shown by.
      if (B.busy) { B.cmp.ask = B.cmp.ask || `compare-${B.cmp.n += 1}-${B.cmp.a}-${B.cmp.b}`; say(B.cmp.ask, 'Wait for the answer to the last action.', 'warn'); return; }
      dropCmp(); B.cmp.all = false;
      const ask = `compare-${B.cmp.n += 1}-${B.cmp.a}-${B.cmp.b}`;
      B.cmp.ask = ask;
      send(ask, ['diff', B.cmp.a, B.cmp.b, '--json'], () => 'Compared.', (text) => { if (B.cmp.ask !== ask) return; try { B.cmp.data = JSON.parse(text); } catch (e) { B.cmp.text = text; } });
    }));
    s.querySelector('.bench-head').append(tools);
    if (B.cmp.ask) s.append(saidAt(B.cmp.ask));
    const d = obj(B.cmp.data);
    if (!d) {
      s.append(h('p', 'board-from', B.cmp.text || 'Compare reads the results of the tasks both ran; for each task that flipped it writes one reading with one model call. No task is run again.'));
      return [s];
    }
    const A = String(obj(d.a) ? d.a.version : 'A'), Bn = String(obj(d.b) ? d.b.version : 'B'), ta = obj(d.a && d.a.totals) || {}, tb = obj(d.b && d.b.totals) || {};
    const flips = list(d.flipped).filter(obj), toA = flips.filter((f) => obj(f.a) && f.a.resolved).length, toB = flips.length - toA, n = num(d.tasks) || 0;
    const both = (num(ta.resolved) || 0) - toA, neither = n - both - flips.length, diff = Math.abs((num(ta.resolved) || 0) - (num(tb.resolved) || 0));
    const head = h('p', 'bench-headline');
    head.append(`On the ${n} tasks both ran: ${A} resolved ${ta.resolved}, ${Bn} ${tb.resolved}. `, h('span', 'ok', `${plural(toA, 'task')} flipped to ${A}`), `, ${toB} the other way, ${both} resolved by both, ${neither} by neither.`);
    // The fewest tasks, up to the benchmark's whole set, at which the same rate of difference is past noiseOf: an
    // estimate such as 2 / rate² can still leave it within the noise, and capping it would name a count that cannot tell.
    const rate = n ? diff / n : 0, max = num(obj(B.d && B.d.bench) && B.d.bench.max) || 500;
    let need = null;
    for (let m = n + 1; rate > 0 && m <= max && need === null; m += 1) if (rate * m >= noiseOf(m)) need = m;
    const foot = h('p', 'board-from');
    foot.append(`${String(d.noise || noiseSaid(n)).replace(/^w/, 'W').replace(/\.?$/, '.')} This difference is ${diff}: `, h('strong', null, d.withinNoise ? 'within the noise' : 'past the noise'),
      !d.withinNoise || !rate || n >= max ? '.' : need ? `. Run about ${need} tasks to tell a difference of this size.` : `. Even all ${max} tasks cannot tell a difference of this size.`);
    const t = h('table', 'tests-table'), hr = h('tr');
    ['', 'Resolved', 'Sessions', 'Tokens', 'Minutes', 'Cost', 'Cost a resolved task'].forEach((x, i) => hr.append(h('th', i ? 'r' : null, x)));
    t.append(hr);
    [[A, ta], [Bn, tb]].forEach(([name, x]) => { const tr = h('tr'); tr.append(h('td', 'bench-name', name), h('td', 'r', `${x.resolved} of ${n}`), h('td', 'r', String(x.sessions ?? '–')), h('td', 'r', tokens(x.tokens)), h('td', 'r', String(x.minutes ?? '–')), h('td', 'r', costSaid(x.cost)),
      h('td', 'r', perResolved(x))); t.append(tr); });
    const wrap = h('div', 'tests-scroll'); wrap.append(t);
    const fold = h('details', 'bench-flipped'); fold.append(h('summary', null, `The ${plural(flips.length, 'flipped task')}`), h('p', 'board-from mono', flips.map((f) => f.task).join(' · ') || 'none'));
    s.append(head, foot, wrap, fold);
    const out = [s], shown = B.cmp.all ? flips : flips.slice(0, 3);
    shown.forEach((f) => out.push(flipPart(f, A, Bn)));
    const end = h('section', 'bench-sec bench-compare-foot'), p = h('p', 'board-from');
    if (flips.length > shown.length) p.append(`${flips.length - shown.length} more flipped ${flips.length - shown.length === 1 ? 'task is' : 'tasks are'} folded: `, button(`show all ${flips.length}`, 'btn-link', 'cmp-all', 'Show every flipped task', () => { B.cmp.all = true; draw(); }), '. ');
    p.append('The written readings are labelled as the model\'s; the facts beside them are what counts. No task is run again to compare.');
    end.append(p); out.push(end);
    return out;
  }
  const STAGE = { build: 'Build', review: 'Review', fix: 'Fix', test: 'Test step', land: 'Land' };
  function flipPart(f, A, Bn) {
    const a = obj(f.a) || {}, b = obj(f.b) || {}, s = section('bench-flip', f.task);
    s.querySelector('.board-head').classList.add('mono');
    const hd = s.querySelector('.bench-head'), apart = h('span', 'board-from');
    apart.append('Went apart at: ', h('strong', null, STAGE[f.apart] || String(f.apart || 'not read')));
    hd.append(B.ctx.chip(`${A} ${a.resolved ? '✓' : '✗'} · ${Bn} ${b.resolved ? '✓' : '✗'}`, 'info'), apart);
    const fact = (name, x) => `${name}: ${plural(num(x.sessions) || 0, 'session')}, ${plural(num(x.fixRounds) || 0, 'fix round')}, test ${x.test || 'none'}${x.blocked ? `, blocked: ${x.blocked}` : ''}${list(x.findings).length ? `, findings: ${list(x.findings).join(' | ')}` : ''}.`;
    const ch = f.changes === null || f.changes === undefined ? 'none to show (they are not two versions of the engine)' : !list(f.changes).length ? 'none'
      : list(f.changes).map((c) => `${c.commit} ${c.title}`).join('; ');
    const cards = h('div', 'bench-cards'), facts = h('div', 'bench-card'), read = h('div', 'bench-card bench-reading'), rh = h('h3', null, 'The model\'s reading ');
    facts.append(h('h3', null, 'Facts, read from the records by code'), h('p', null, `${fact(A, a)} ${fact(Bn, b)}`), h('p', 'board-from', `Engine changes that touch that step: ${ch}`));
    rh.append(B.ctx.chip('written by one model call from the facts only', 'quiet'));
    read.append(rh, h('p', null, f.reading || 'None: the model call failed.'));
    cards.append(facts, read);
    s.append(cards);
    return s;
  }

  // ---- Start a run ----
  // A saved revision (`bench swe arms save`: history gives it a revision) is in Saved arms, whatever it builds with.
  const armGroup = (a) => (obj(a.revision) ? 'Saved arms' : a.state === 'not offered' ? 'Other agents' : { 1: 'Conveyor', 3: 'Conveyor', 2: 'Claude, plain', 5: 'Claude + a plugin or method', 4: 'Codex' }[group(a)]);
  const GROUPS = ['Saved arms', 'Conveyor', 'Claude, plain', 'Claude + a plugin or method', 'Codex', 'Other agents'];
  const ARM_STATE = { ready: ['Ready', 'ok'], checking: ['Checking', 'quiet'], failed: ['Preflight failed', 'bad'], unchecked: ['Not checked', 'quiet'], changed: ['Changed since its check', 'warn'],
    expired: ['Check expired', 'warn'], 'not offered': ['Not offered', 'quiet'] };
  const versionsOf = () => list(obj(B.d && B.d.bench) && B.d.bench.versions).filter((v) => obj(v) && typeof v.name === 'string');
  function engineOf() { return B.start.engine === 'commit' ? B.start.commit : B.start.engine; }
  // ---- Run settings: the task set and the limits every arm of the run shares (`--settings`, swe_settings). Each is
  // its key, its label, what it sets, why a value typed does not read (null when it reads, as swe_settings checks its
  // shape; the build machine still refuses more CPUs or memory than it has) and the value sent. ----
  const SETTINGS = [
    ['revision', 'Dataset revision', 'The dataset revision the tasks and their grade are read from.', (v) => (/^[0-9a-f]{40}$/.test(v) ? null : 'Type the full 40-character commit ID.'), String],
    ['seed', 'Order seed', 'The seed that puts the tasks in order.', (v) => (v.length <= 80 && !/[\u0000-\u001f\u007f]/.test(v) ? null : 'Type 1 to 80 characters, with no control character.'), String],
    ['cpus', 'CPUs', 'The CPUs of each task\'s container.', (v) => (/^[0-9]*\.?[0-9]+$/.test(v) && Number(v) > 0 ? null : 'Type a number above 0.'), Number],
    ['memory', 'Memory', 'The memory of each task\'s container, such as 600m or 4g.', (v) => { const m = /^([1-9][0-9]{0,6})([mg])$/.exec(v); return m && Number(m[1]) * (m[2] === 'g' ? 1024 : 1) >= 512 ? null : 'Type <n>m or <n>g, 512m or more.'; }, String],
    ['taskTimeout', 'Time limit', 'Seconds. The install of an arm and its run on one task can each take this long.', (v) => (/^[0-9]+$/.test(v) && Number(v) >= 60 && Number(v) <= 86400 ? null : 'Type a whole number of seconds from 60 to 86400.'), Number]];
  const setDefaults = () => ({ ...(obj(hist() && hist().set) || {}), ...(obj(hist() && hist().limits) || {}) });
  // The settings Start sends: each one typed that is not its default (a blank field is its default), or null while one
  // does not read. {} when each is its default: Start then sends no settings.
  function runSet() {
    const d = setDefaults(), out = {};
    for (const [k, , , why, as] of SETTINGS) {
      const v = B.start.set[k] === undefined ? undefined : B.start.set[k].trim();
      if (v === undefined || v === '' || (d[k] !== undefined && v === String(d[k]))) continue;
      if (why(v)) return null;
      out[k] = as(v);
    }
    return out;
  }
  const setChanged = () => { const s = runSet(); return !s || Object.keys(s).length > 0; };
  function settingsPart() {
    const d = setDefaults(), box = h('div', 'bench-settings');
    box.append(h('p', 'board-label', 'Run settings'),
      h('p', 'board-from', `These apply to every arm: the tasks of ${d.dataset || 'SWE-bench Verified'} in the order of the seed, and the limits of each task's container. A blank field takes its default. The preflight command has a fixed time limit of its own, and the official harness always grades.`));
    SETTINGS.forEach(([k, label, what, why]) => {
      const row = h('div', 'bench-row'), f = h('input', k === 'revision' ? 'field mono' : 'field'), v = B.start.set[k], no = v && v.trim() ? why(v.trim()) : null;
      f.value = v === undefined ? String(d[k] === undefined ? '' : d[k]) : v; f.dataset.act = `set-${k}`; f.setAttribute('aria-label', label);
      if (no) f.setAttribute('aria-invalid', 'true');
      // Each key typed is kept in the draft at once, so a redraw while it is typed (an update, a check's answer) puts
      // the text back as it was; change reads it and redraws.
      f.addEventListener('input', () => { B.start.set[k] = f.value; });
      f.addEventListener('change', () => { B.start.set[k] = f.value.trim(); draw(); });
      row.append(h('span', 'board-label', label), f, h('span', 'board-from', `${what}${d[k] === undefined ? '' : ` Default: ${d[k]}.`}`));
      if (no) { const p = h('span', 'warn-note bench-set-why', no); p.dataset.why = k; row.append(p); }
      box.append(row);
    });
    return box;
  }
  // The tasks of the first n the arm has run on the version picked are reused: only the rest cost. Not for main: the
  // run reads main again, and it may have moved past the commit listed. null (not known) with run settings changed:
  // the results keys and the task order read are those of the default settings.
  function reused(a) {
    const n = B.start.n;
    if (setChanged()) return null;
    let key = a.key;
    if (a.kind === 'conveyor') {
      const e = engineOf(), v = versionsOf().find((x) => x.name === e);
      const c = /^[0-9a-f]{40}$/.test(e) ? e : e !== 'main' && v ? v.commit : null;
      key = c && typeof a.keyPrefix === 'string' ? `${a.keyPrefix}${c}` : null;
    }
    const k = list(hist() && hist().keys).find((x) => obj(x) && x.key === key);
    return k ? list(k.at).filter((i) => Number.isInteger(i) && i < n).length : 0;
  }
  function plan(a) {
    const p = obj(a.perTask) || { usual: 1, worst: 1, minutes: 10 }, re = reused(a), todo = B.start.n - (re || 0);
    const usual = Math.ceil(todo * (num(p.usual) || 0)), worst = todo * (num(p.worst) || 0), one = num(p.session);
    // The dollars: each session at the mean list price of this project's own priced sessions (swe_pertask's session);
    // null when there are none to take it from, unless every task is reused: no session runs, at $0.00.
    const usd = (k) => (todo === 0 ? 0 : one === null ? null : k * one);
    return { reused: re, todo, usual, worst, minutes: todo * (num(p.minutes) || 0), usd: usd(usual), worstUsd: usd(worst) };
  }
  function startPage() {
    const s = section('bench-start', 'Start a run', null, 'SWE-bench Verified run through each arm, graded by the official harness.'), bench = obj(B.d && B.d.bench) || {};
    s.querySelector('.bench-head').append(button('Back', 'btn-quiet', 'back', 'Back to the overview', () => go('overview')));
    const last = latest(null);
    if (last) s.querySelector('.bench-head').append(last);
    const max = num(bench.max) || 500, row = h('div', 'bench-row'), seg = h('div', 'bench-seg');
    row.append(h('span', 'board-label', 'How many tasks'));
    (list(bench.presets).length ? list(bench.presets) : [1, 5, 20, 50]).forEach((p) => {
      const b = button(String(p), '', `preset-${p}`, plural(p, 'task'), () => { B.start.n = p; draw(); });
      b.setAttribute('aria-pressed', String(B.start.n === p));
      seg.append(b);
    });
    const box = h('input', 'field bench-n'), lab = h('label', 'board-from');
    box.type = 'number'; box.min = '1'; box.max = String(max); box.value = String(B.start.n); box.dataset.act = 'start-n'; box.setAttribute('aria-label', 'Number of tasks');
    box.addEventListener('change', () => { const v = Number(box.value); if (Number.isInteger(v) && v >= 1 && v <= max) B.start.n = v; draw(); });
    lab.append('or any number ', box);
    row.append(seg, lab, h('span', 'board-from', 'The task list is fixed: 5 is always the first 5 of 20. Tasks an arm already ran on the same version are reused at no cost.'));
    const vrow = h('div', 'bench-row'), pick = h('select', 'field');
    pick.dataset.act = 'start-engine'; pick.setAttribute('aria-label', 'Conveyor version');
    const vs = versionsOf();
    (vs.some((v) => v.name === 'main') ? vs : [{ name: 'main' }].concat(vs)).forEach((v) => {
      const o = h('option', null, v.name === 'main' && v.commit ? `main (${String(v.commit).slice(0, 7)})` : v.name); o.value = v.name; pick.append(o);
    });
    const other = h('option', null, 'a commit…'); other.value = 'commit'; pick.append(other);
    pick.value = B.start.engine;
    pick.addEventListener('change', () => { B.start.engine = pick.value; draw(); });
    vrow.append(h('span', 'board-label', 'Conveyor version'), pick);
    if (B.start.engine === 'commit') {
      const c = h('input', 'field mono');
      c.value = B.start.commit; c.dataset.act = 'start-commit'; c.setAttribute('aria-label', 'Full commit id'); c.placeholder = '40-character commit id';
      c.addEventListener('change', () => { B.start.commit = c.value.trim(); draw(); });
      vrow.append(c);
    }
    vrow.append(button('List versions', 'btn-sm', 'versions', 'List the released versions', () => send('versions', ['versions'], () => 'The versions are listed.')),
      saidAt('versions'), h('span', 'board-from', 'The version is the one every Conveyor arm of the run builds with.'));
    s.append(row, vrow);
    if (!hist()) return [s, reading('the arms')];
    s.append(settingsPart());
    return [s, armPick(), ...(B.edit ? [editor()] : []), before()];
  }
  // An arm ticked while not ready waits in B.start.checking (name -> its check time then) for its preflight: picked once
  // it reads ready, cleared once it reads failed with a newer check time.
  const atOf = (a) => (a.at === undefined ? null : a.at);
  function settleChecks(arms) {
    arms.forEach((a) => {
      if (!B.start.checking.has(a.name)) return;
      if (a.state === 'ready') B.start.checking.delete(a.name);
      else if (a.state === 'not offered' || (a.state === 'failed' && atOf(a) !== B.start.checking.get(a.name))) { B.start.checking.delete(a.name); B.start.arms.delete(a.name); }
    });
  }
  function armPick() {
    const arms = armsOf();
    settleChecks(arms);
    const picked = arms.filter((a) => a.state !== 'not offered' && B.start.arms.has(a.name));
    const s = section('bench-arm-pick', 'Arms', `${picked.length} picked`, 'An arm can be picked once its preflight succeeds: installed, logged in, and it runs one trivial task headless. Ticking an arm not ready runs its preflight. A check runs a session of its own, which the estimate does not count.');
    GROUPS.forEach((g) => {
      // Saved arms by name, each name's newest revision first.
      const these = arms.filter((a) => armGroup(a) === g)
        .sort((x, y) => (g !== 'Saved arms' ? 0 : String(x.label).localeCompare(String(y.label)) || String(y.revision.at || '').localeCompare(String(x.revision.at || ''))));
      if (!these.length) return;
      const grid = h('div', 'bench-armgrid');
      s.append(h('p', 'board-label', g), grid);
      these.forEach((a) => {
        const ready = a.state === 'ready', offered = a.state !== 'not offered', checking = !ready && B.start.checking.has(a.name);
        const lab = h('label', ready ? 'bench-arm' : 'bench-arm off'), box = h('input'), text = h('span');
        lab.dataset.arm = a.name;
        // A box shows what Start sends: an arm ticked stays ticked whatever its state, and Start waits for it to be ready.
        box.type = 'checkbox'; box.checked = offered && B.start.arms.has(a.name); box.disabled = !offered; box.dataset.act = `arm-${a.name}`; box.setAttribute('aria-label', a.label);
        box.addEventListener('change', () => {
          if (!box.checked) { B.start.arms.delete(a.name); B.start.checking.delete(a.name); draw(); return; }
          if (ready) { B.start.arms.add(a.name); draw(); return; }
          // Not ready: the box sends the arm's preflight, as its Check button does, and picks the arm once it succeeds.
          if (B.busy) { box.checked = false; say(`check-${a.name}`, 'Wait for the answer to the last action.', 'warn'); return; }
          B.start.checking.set(a.name, atOf(a)); B.start.arms.add(a.name);
          send(`check-${a.name}`, ['arms', 'check', a.name], (t) => `${t.replace(/^conveyor: /, '')}. Read the arms again in a few minutes.`, () => readHist(true),
            () => { B.start.checking.delete(a.name); B.start.arms.delete(a.name); }, { at: atOf(a) });
        });
        const [word, tone] = checking && a.state !== 'checking' ? ['Checking its preflight…', 'quiet'] : ARM_STATE[a.state] || [String(a.state), 'quiet'];
        // A check that runs shows the step it is at, in a polite live region (the arms are read again while it runs: recheck).
        const sub = a.state === 'checking' ? h('span', 'bench-sub', String(a.step || 'Starting the test container').replace(/\.?$/, '.'))
          : h('span', 'bench-sub', a.why || (obj(a.revision) ? `Saved ${B.ctx.when(a.revision.at)} as ${a.name}: ${specSaid(a.spec)}`
            : a.kind === 'conveyor' ? 'the engine\'s loop builds each task: build, reviews, fix rounds, test step' : `${sessionsWord(a.perTask && a.perTask.worst) || 'its own sessions'} a task, headless`));
        if (a.state === 'checking') sub.setAttribute('aria-live', 'polite');
        text.append(h('span', 'bench-name', a.label), ' ', B.ctx.chip(word, tone), sub);
        const p = plan(a);
        lab.append(box, text, h('span', 'bench-cost', a.perTask && a.state !== 'not offered' ? `${p.usual} sessions (worst ${p.worst}) · ${p.minutes} min · ${p.usd === null ? COST : B.ctx.money(p.usd)}` : ''));
        const cell = h('div', 'bench-arm-cell');
        cell.append(lab);
        if (a.state === 'unchecked' || a.state === 'changed' || a.state === 'failed' || a.state === 'expired') {
          cell.append(button(a.state === 'failed' || a.state === 'expired' ? 'Check again' : 'Check', 'btn-quiet btn-sm', `check-${a.name}`, `Run the preflight of ${a.label}`,
            () => send(`check-${a.name}`, ['arms', 'check', a.name], (t) => `${t.replace(/^conveyor: /, '')}. Read the arms again in a few minutes.`, () => readHist(true), null, { at: atOf(a) })));
        }
        // Its pass was on the default run settings (the arms' states are read on them): the run checks it again first.
        if (ready && B.start.arms.has(a.name) && setChanged()) cell.append(h('p', 'warn-note bench-stale', 'Checked on the default run settings. The run checks it again on yours before its first task.'));
        if (obj(a.spec)) cell.append(button('Edit a copy', 'btn-quiet btn-sm', `copy-${a.name}`, `Edit a copy of ${a.label}`, () => openEdit(copyOf(a))));
        // The answer to this arm's check (its box or its Check button) shows in the arm, not at the foot of the page. Once
        // the arms are read again, a check the host took is answered by the arm's state: passed when the arm reads ready,
        // failed when it reads failed with a check time other than the one it had when the check was sent.
        const ck = saidKey(`check-${a.name}`), m = B.said.get(ck);
        if (m && m.tone === 'ok' && 'at' in m && (ready || (a.state === 'failed' && atOf(a) !== m.at))) {
          B.said.set(ck, ready ? { text: `Check passed. ${a.label} is ready.`, tone: 'ok' }
            : { text: `Check failed. ${String(a.why || 'No reason was recorded').replace(/\.?$/, '.')} Edit the arm or fix its setup, then choose Check again.`, tone: 'bad' });
        }
        cell.append(saidAt(`check-${a.name}`));
        grid.append(cell);
      });
    });
    const tools = h('div', 'bench-row');
    tools.append(button('New Conveyor arm', 'btn-sm', 'new-conveyor', 'New Conveyor arm', () => openEdit(blank('conveyor'))),
      button('New agent arm', 'btn-sm', 'new-agent', 'New agent arm', () => openEdit(blank('agent'))),
      button('Read the arms again', 'btn-quiet btn-sm', 'arms-again', 'Read the arms and their preflights again', () => readHist(true)));
    s.append(tools);
    return s;
  }
  // ---- the arm editor (Start a run): a Conveyor arm's rules and seats, or an agent arm's CLI, model, effort and method,
  // saved as a new revision on the build machine (`bench swe arms save <name> <spec>`, the revision's ID its answer).
  // Its choices are history's: choices (the models the project allows each pool, by CLI, and each CLI's efforts),
  // defaults (what a sandbox runs for a seat the arm leaves out) and each arm's spec (what a copy starts from). ----
  // Each seat of a Conveyor arm: its key in the spec, its title, the pool it takes its models from, and what it runs.
  const SEATS = [['model', 'Builder', 'builder', 'The session that writes the first patch.'], ['reviewer', 'Reviewer', 'reviewer', 'Each review of the patch.'],
    ['judge', 'Judge', 'reviewer', 'Reads the reviews and decides which findings stand.'], ['fix', 'Fix', 'builder', 'The session that repairs review findings.'],
    ['testFix', 'Test repair', 'builder', 'The session that repairs a failed test. The test it repairs is the task\'s own test command, from the harness.']];
  const AGENT_CLIS = ['claude', 'codex'];  // the CLIs whose login a benchmark container is given (swe_logins)
  const choicesOf = () => obj(hist() && hist().choices);
  const defaultsOf = () => obj(hist() && hist().defaults);
  const poolOf = (pool) => obj(choicesOf() && choicesOf()[pool]) || {};
  const seatOf = (v) => (obj(v) && typeof v.model === 'string' ? { cli: v.cli || v.agent, model: v.model, effort: v.effort || null } : null);
  const seatSaid = (v) => (v ? [v.cli, v.model, v.effort].filter(Boolean).join(' · ') : 'not known');
  // The efforts a seat takes on a CLI: none for an OpenCode seat of the builder pool (swe_armsave refuses one).
  const effortsOf = (pool, cli) => (pool === 'builder' && cli === 'opencode' ? [] : list(obj(choicesOf() && choicesOf().efforts) && choicesOf().efforts[cli]));
  // A seat's choice made one its pool allows: its CLI when the pool has models on it (else the CLI that has its model,
  // else the first with any), its model when allowed on that CLI (else the first), its effort when the CLI takes it
  // (else medium, else the first). null when the pool has no model at all.
  function fit(pool, v) {
    const p = poolOf(pool), clis = Object.keys(p).filter((c) => list(p[c]).length);
    if (!clis.length) return null;
    const cli = v && clis.includes(v.cli) ? v.cli : (v && clis.find((c) => list(p[c]).includes(v.model))) || clis[0], ms = list(p[cli]), es = effortsOf(pool, cli);
    return { cli, model: v && ms.includes(v.model) ? v.model : ms[0], effort: !es.length ? null : v && es.includes(v.effort) ? v.effort : es.includes('medium') ? 'medium' : es[0] };
  }
  // Why the project does not allow a seat's choice in its pool, or null. A copy keeps a supplied arm's seat the project
  // does not allow as it is, shown as not allowed, and Save waits until another is chosen: never replaced unseen.
  function seatWhy(pool, v) {
    if (!v) return null;
    return !list(poolOf(pool)[v.cli]).includes(v.model) ? `this project does not allow ${v.model} on ${v.cli} here`
      : v.effort && !effortsOf(pool, v.cli).includes(v.effort) ? `${v.cli} takes no effort ${v.effort} here` : null;
  }
  const kept = (pool, v) => (v && seatWhy(pool, v) ? v : fit(pool, v));
  // A picker's options with the value it holds added, as not allowed, when the options do not have it.
  const withOwn = (opts, v) => (v && !opts.some(([x]) => x === v) ? opts.concat([[v, `${v} (not allowed here)`, true]]) : opts);
  // A draft opened (new or a copy) shows no answer to the Save of the one before it.
  function openEdit(e) { B.said.delete(saidKey('save-arm')); B.edit = e; draw(); }
  // The judge model the project's setting gives the arm: the project's own judge, else (one that follows the reviewer)
  // the first model the project allows the review on another CLI than the arm's reviewer, at medium (judgenow).
  function projectJudge(e) {
    const d = defaultsOf();
    if (!d) return null;
    if (d.judgeOwn || !e.seats.reviewer) return seatOf(obj(d.seats) && d.seats.judge);
    const p = poolOf('reviewer'), c = Object.keys(p).find((x) => x !== e.seats.reviewer.cli && list(p[x]).length);
    return c ? { cli: c, model: p[c][0], effort: 'medium' } : null;
  }
  // Whether the arm's judge reads the reviews: null when the project's setting is not known.
  const judgeOn = (e) => (obj(e.judge) || e.judge === 'on' ? true : e.judge === 'off' ? false : defaultsOf() ? defaultsOf().judgeOn === true : null);
  // What a seat runs on: the arm's own choice, else the project's; fix and test repair follow the arm's builder unless
  // the project sets its own.
  function resolved(e, k) {
    const ds = obj(defaultsOf() && defaultsOf().seats) || {};
    if (k === 'judge') return obj(e.judge) ? e.judge : projectJudge(e);
    if (e.seats[k]) return e.seats[k];
    return (k === 'fix' || k === 'testFix') ? seatOf(ds[k]) || resolved(e, 'model') : seatOf(ds[k]);
  }
  // The recipes an agent arm may run on a CLI: host agent arms offered that take a model on that CLI alone (their spec).
  const recipesOf = (cli) => armsOf().filter((a) => !obj(a.revision) && a.kind === 'agent' && a.state !== 'not offered' && obj(a.spec) && a.spec.cli === cli);
  // Method None: the CLI's plain recipe, one session and no method (Claude alone, Codex alone).
  const plainOf = (cli) => { const rs = recipesOf(cli); return rs.find((a) => a.sessions === 1 && [2, 4].includes(group(a))) || rs[0] || null; };
  const recipeOf = (e) => recipesOf(e.cli).find((a) => a.name === e.recipe) || null;
  function blank(kind) {
    if (kind === 'conveyor') return { kind, name: '', rules: 'engine', seats: {}, judge: 'project', policy: {} };
    const ag = obj(choicesOf() && choicesOf().agent) || {}, cli = AGENT_CLIS.find((c) => list(ag[c]).length && plainOf(c)) || AGENT_CLIS[0];
    return { kind, name: '', cli, recipe: (plainOf(cli) || {}).name || '', model: list(ag[cli])[0] || '', effort: '' };
  }
  // The editor on a copy of an arm: a saved revision keeps its name (Save then makes a new revision of it), a host arm's
  // copy is named apart from it. A review policy the copy holds beside the judge (judgeAlways, P0 to P3) is kept, and so
  // is a seat the project does not allow (kept).
  function copyOf(a) {
    const s = a.spec, name = obj(a.revision) ? String(a.label) : `${a.label} (copy)`;
    if (s.kind === 'agent') return { kind: 'agent', name, cli: s.cli, recipe: s.recipe, model: s.model, effort: s.effort || '' };
    const seats = obj(s.seats) || {}, policy = { ...(obj(s.policy) || {}) }, mine = {};
    SEATS.forEach(([k, , pool]) => { if (k !== 'judge' && obj(seats[k])) mine[k] = kept(pool, seatOf(seats[k])); });
    const judge = obj(seats.judge) ? kept('reviewer', seatOf(seats.judge)) : policy.judgeOn === false ? 'off' : policy.judgeOn === true ? 'on' : 'project';
    delete policy.judgeOn;
    return { kind: 'conveyor', name, rules: s.rules === 'project' ? 'project' : 'engine', seats: mine, judge, policy };
  }
  // The spec Save sends: a Conveyor arm's own seats only (a seat left out is the project's), the judge's off or on as
  // judgeOn; an agent arm's effort only when one is chosen and its recipe gives it to the CLI.
  function specOf(e) {
    const one = (v) => ({ cli: v.cli, model: v.model, ...(v.effort ? { effort: v.effort } : {}) });
    if (e.kind === 'agent') return { kind: 'agent', recipe: e.recipe, cli: e.cli, model: e.model, ...(e.effort && recipeOf(e) && recipeOf(e).effort ? { effort: e.effort } : {}) };
    const seats = {}, policy = { ...e.policy };
    SEATS.forEach(([k]) => { const v = k === 'judge' ? (obj(e.judge) ? e.judge : null) : e.seats[k]; if (v) seats[k] = one(v); });
    if (e.judge !== 'project') policy.judgeOn = e.judge !== 'off';
    return { kind: 'conveyor', rules: e.rules, ...(Object.keys(seats).length ? { seats } : {}), ...(Object.keys(policy).length ? { policy } : {}) };
  }
  // What a saved arm runs, in one line.
  function specSaid(s) {
    if (!obj(s)) return '';
    if (s.kind === 'agent') { const r = armsOf().find((a) => a.name === s.recipe); return `${r ? r.label : s.recipe} on ${seatSaid(seatOf(s))}`; }
    const seats = obj(s.seats) || {}, own = SEATS.filter(([k]) => obj(seats[k])).map(([k, t]) => `${t} ${seatSaid(seatOf(seats[k]))}`);
    return [own.length ? own.join('; ') : 'the project\'s seats', s.policy && s.policy.judgeOn === false ? 'judge off' : '', s.rules === 'project' ? 'engine and project rules' : 'engine rules'].filter(Boolean).join('; ');
  }
  // Why a name cannot be saved (swe_armsave's rule), or null.
  const nameWhy = (n) => (!n ? 'Name the arm to save it.' : n.length > 80 ? 'A name has at most 80 characters.' : n !== n.trim() ? 'A name has no space at either end.'
    : Array.from(n).some((c) => c.charCodeAt(0) < 32 || c.charCodeAt(0) === 127) ? 'A name has no control character.' : null);
  function picker(act, label, opts, value, fn) {
    const s = h('select', 'field');
    s.dataset.act = act; s.setAttribute('aria-label', label);
    opts.forEach(([v, t, off]) => { const o = h('option', null, t); o.value = v; o.disabled = Boolean(off); s.append(o); });
    s.value = value;
    s.addEventListener('change', () => { fn(s.value); draw(); });
    return s;
  }
  // One seat's row: the CLI, model and effort it runs on. A seat that follows another shows those values beside Use
  // another model; one of the arm's own has a picker each, the models and efforts those its CLI allows the pool.
  function seatRow(e, [k, title, pool, what]) {
    const row = h('div', 'bench-row bench-seat'), d = defaultsOf(), own = k === 'judge' ? (obj(e.judge) ? e.judge : null) : e.seats[k];
    const set = (v) => { if (k === 'judge') e.judge = v; else e.seats[k] = v; };
    row.dataset.seat = k;
    row.append(h('span', 'board-label', title));
    if (k === 'judge') {
      row.append(picker('seat-judge-mode', 'Judge', [['project', 'Project judge setting'], ['off', 'Off'], ['on', 'On, the project\'s judge model'], ['own', 'Choose a model']], own ? 'own' : e.judge,
        (v) => { e.judge = v === 'own' ? fit(pool, projectJudge(e)) || 'project' : v; }));
    }
    if (own) {
      const p = poolOf(pool), es = effortsOf(pool, own.cli), why = seatWhy(pool, own);
      row.append(picker(`seat-${k}-cli`, `${title} CLI`, withOwn(Object.keys(p).map((c) => [c, list(p[c]).length ? c : `${c} (the project allows it no model here)`, !list(p[c]).length]), own.cli), own.cli,
        (v) => set(fit(pool, { ...own, cli: v }))),
      picker(`seat-${k}-model`, `${title} model`, withOwn(list(p[own.cli]).map((m) => [m, m]), own.model), own.model, (v) => set({ ...own, model: v })),
      es.length ? picker(`seat-${k}-effort`, `${title} effort`, withOwn(es.map((x) => [x, x]), own.effort), own.effort, (v) => set({ ...own, effort: v })) : h('span', 'board-from', `${own.cli} takes no effort for this seat`));
      if (why) row.append(h('span', 'warn-note bench-seat-why', `Not allowed: ${why}. Choose another.`));
      if (k !== 'judge') row.append(button(k === 'fix' || k === 'testFix' ? 'Follow again' : 'Use the project\'s', 'btn-quiet btn-sm', `seat-${k}-follow`, `Use the project's ${title.toLowerCase()} again`, () => { delete e.seats[k]; draw(); }));
    } else if (k === 'judge') {
      row.append(h('span', 'bench-seat-now', judgeOn(e) === false ? 'Off: no judge reads the reviews.' : seatSaid(resolved(e, k))));
    } else {
      const follows = { model: 'Project builder', reviewer: 'Project reviewer' }[k] || (seatOf(d && obj(d.seats) && d.seats[k]) ? `Project ${title.toLowerCase()} seat` : 'Follow builder');
      row.append(h('span', 'bench-seat-now', `${follows}: ${seatSaid(resolved(e, k))}`),
        button('Use another model', 'btn-quiet btn-sm', `seat-${k}-own`, `Use another model for the ${title.toLowerCase()}`, () => { set(fit(pool, resolved(e, k))); draw(); }));
    }
    const always = list(e.policy.judgeAlways || (d && d.judgeAlways));
    row.append(h('span', 'bench-sub', k !== 'judge' || judgeOn(e) === false ? what
      : `${what} It always accepts ${always.length ? `the findings of kind ${always.join(', ')}` : 'no kind of finding'} without weighing it.`));
    return row;
  }
  function conveyorPart(e, box) {
    const c = choicesOf();
    box.append(h('p', 'board-from', c.source === 'project' ? 'The models are those this project allows in models.allowed.' : 'The models are the engine\'s defaults: this project sets no models.allowed.'));
    const rules = h('div', 'bench-row');
    rules.append(h('span', 'board-label', 'Rules'), picker('edit-rules', 'Rules', [['engine', 'Engine rules'], ['project', 'Engine and project rules']], e.rules, (v) => { e.rules = v; }),
      h('span', 'board-from', e.rules === 'project' ? 'The core card and review rules of the engine, and this project\'s card rules and the area rules of each task\'s card.' : 'The core card and review rules of the engine that the run builds with.'));
    box.append(rules);
    if (!defaultsOf()) box.append(h('p', 'warn-note', 'The project\'s seats could not be read on the build machine: a seat that follows the project shows "not known".'));
    SEATS.forEach((x) => box.append(seatRow(e, x)));
    box.append(h('p', 'info-note', 'Fixed in the sandbox for every arm: no follow-up issues, no approval of visible changes, and the push goes to the sandbox. The engine is the Conveyor version of the run.'));
  }
  const agentSeat = (e) => ({ cli: e.cli, model: e.model, effort: e.effort || null });
  function agentPart(e, box) {
    const c = choicesOf(), ag = obj(c.agent) || {}, clis = Array.from(new Set(AGENT_CLIS.concat(Object.keys(obj(c.efforts) || {})))), r = recipeOf(e);
    const cliWhy = (x) => (!AGENT_CLIS.includes(x) ? 'not available: a benchmark container cannot sign in to it yet' : !list(ag[x]).length ? 'the project allows it no model'
      : !recipesOf(x).length ? 'no recipe on this machine runs it' : null);
    const row = (label, ...xs) => { const p = h('div', 'bench-row'); p.append(h('span', 'board-label', label), ...xs); box.append(p); };
    row('CLI', picker('edit-cli', 'CLI', clis.map((x) => [x, cliWhy(x) ? `${x} (${cliWhy(x)})` : x, cliWhy(x)]), e.cli, (v) => {
      const p = plainOf(v), ms = list(ag[v]);
      Object.assign(e, { cli: v, recipe: p ? p.name : '', model: ms.includes(e.model) ? e.model : ms[0] || '', effort: effortsOf('agent', v).includes(e.effort) ? e.effort : '' });
    }));
    const why = seatWhy('agent', agentSeat(e));
    row('Model', picker('edit-model', 'Model', withOwn(list(ag[e.cli]).map((m) => [m, m]), e.model), e.model, (v) => { e.model = v; }),
      ...(why ? [h('span', 'warn-note bench-seat-why', `Not allowed: ${why}. Choose another.`)] : []));
    row('Effort', r && r.effort ? picker('edit-effort', 'Effort', withOwn([['', 'the CLI\'s own']].concat(effortsOf('agent', e.cli).map((x) => [x, x])), e.effort), e.effort, (v) => { e.effort = v; })
      : h('span', 'board-from', 'This method does not give an effort to its CLI.'));
    row('Method', picker('edit-method', 'Method', recipesOf(e.cli).map((a) => [a.name, `${a === plainOf(e.cli) ? `None (${a.label})` : a.label} · ${sessionsWord(a.sessions) || 'its own sessions'} a task`]), e.recipe,
      (v) => { e.recipe = v; const x = recipeOf(e); if (!x || !x.effort) e.effort = ''; }),
    h('span', 'board-from', r ? `${sessionsWord(r.sessions) || 'Its own sessions'} a task.` : 'Choose a method.'));
  }
  function editor() {
    const e = B.edit, s = section('bench-edit', e.kind === 'conveyor' ? 'Conveyor arm' : 'Agent arm', null, 'Choose what builds each task, then Save arm. Saving starts no session.');
    s.querySelector('.bench-head').append(button('Close', 'btn-quiet btn-sm', 'edit-close', 'Close the arm editor', () => { B.edit = null; draw(); }));
    if (!choicesOf()) {
      s.append(h('p', 'warn-note', 'The models this project allows could not be read on the build machine, so no arm can be saved now.'), saidAt('save-arm'));
      return s;
    }
    const nrow = h('div', 'bench-row'), name = h('input', 'field'), note = h('span', 'board-from bench-why');
    name.value = e.name; name.dataset.act = 'edit-name'; name.setAttribute('aria-label', 'Name'); name.maxLength = 120; name.placeholder = 'Claude builds, Codex reviews';
    nrow.append(h('span', 'board-label', 'Name'), name, note);
    s.append(nrow);
    if (e.kind === 'conveyor') conveyorPart(e, s); else agentPart(e, s);
    const save = button('Save arm', 'btn-primary', 'save-arm', 'Save the arm', () => {
      send('save-arm', ['arms', 'save', e.name, JSON.stringify(specOf(e))], (t) => `Saved as ${t}. It is under Saved arms: tick it to check it and use it.`, () => readHist(true));
    });
    // The name is checked as it is typed, beside its field, with no redraw (the field keeps its caret).
    // A seat the project does not allow (a copy keeps one as it is) holds Save until another is chosen.
    const bad = e.kind === 'agent' ? (seatWhy('agent', agentSeat(e)) ? 'Model' : null)
      : (SEATS.find(([k, , pool]) => seatWhy(pool, k === 'judge' ? (obj(e.judge) ? e.judge : null) : e.seats[k])) || [])[1];
    const check = () => { const why = nameWhy(e.name) || (e.kind === 'agent' && !recipeOf(e) ? 'Choose a CLI and a method.' : null)
      || (bad ? `${bad}: this project does not allow the choice. Choose another.` : null); note.textContent = why || ''; save.disabled = Boolean(why) || B.busy; };
    name.addEventListener('input', () => { e.name = name.value; check(); });
    check();
    s.append(save, saidAt('save-arm'));
    return s;
  }
  // A run's receipt in Start's answer: `conveyor: run <id> started` once the run is recorded, or `... ended` as the last
  // line of a run that reused each task's saved result and so ended before it answered.
  const RECEIPT = /^conveyor: run (r[0-9]{8}T[0-9]{6}-[0-9]+) (started|ended)$/m;
  const openRun = (id) => { B.open = id; B.task = null; B.page = 'run'; };
  const names = (as) => as.map((a) => a.label).join(', ');
  function before() {
    const n = B.start.n, s = section('bench-before', 'Before you start'), g = obj(hist().guard) || {}, set = runSet();
    // The arms ticked, in the order the run takes them. Start sends each of them or none: while one is being checked
    // or is not ready, there is no estimate (a total without it would read as the whole) and Start waits.
    const chosen = armsOf().filter((a) => a.state !== 'not offered' && B.start.arms.has(a.name));
    const waiting = chosen.filter((a) => a.state === 'checking' || (a.state !== 'ready' && B.start.checking.has(a.name)));
    const unready = chosen.filter((a) => a.state !== 'ready' && !waiting.includes(a));
    const plans = waiting.length || unready.length ? [] : chosen.map((a) => [a, plan(a)]), sum = (k) => plans.reduce((x, [, p]) => x + p[k], 0);
    // Each figure is its number and one whole caption, as block elements with spaces between, so they never run
    // together as words. With no estimate there are no figures and no table head with no row under it.
    const figs = h('div', 'figures'), fig = (v, caption) => { const f = h('div', 'figure'); f.append(h('div', 'num', v), ' ', h('div', 'figure-label', caption)); return f; };
    const them = (k) => (k > 1 ? 'them' : 'it');
    const wait = waiting.length ? `Waiting for the check of ${names(waiting)}.` : unready.length ? `${names(unready)} ${unready.length > 1 ? 'are' : 'is'} not ready: check ${them(unready.length)}, or untick ${them(unready.length)}.` : null;
    if (!chosen.length) s.append(h('p', 'board-from bench-no-estimate', 'Choose an arm to see the estimate.'));
    else if (wait) s.append(h('p', 'board-from bench-no-estimate', `${wait} The estimate and Start wait for ${them(waiting.length + unready.length)}.`));
    else {
      // A total that leaves an arm out would read as the whole cost: with one arm not priced, the total is unknown.
      const unpriced = plans.filter(([, p]) => p.usd === null).map(([a]) => a.label);
      figs.append(fig(String(sum('usual')), `Usually ${plural(sum('usual'), 'session')}. Up to ${plural(sum('worst'), 'session')}.`),
        fig(`${(sum('minutes') / 60).toFixed(1)} h`, 'Of session time. The arms build one task at a time.'),
        unpriced.length ? fig(COST, `Total cost unknown. No price data for ${unpriced.join(', ')}.`) : fig(B.ctx.money(sum('usd')), `At list prices. Up to ${B.ctx.money(sum('worstUsd'))}.`));
      // Each arm's row: the tasks reused at no cost, its sessions, minutes and cost for the rest, and the usage guard
      // that can hold it (swe_guards: none for an arm with no Claude login).
      const t = h('table', 'tests-table bench-plan'), hr = h('tr');
      ['Arm', 'Reused', 'Usual', 'Worst', 'Minutes', 'Cost', 'Usage guard'].forEach((x, i) => hr.append(h('th', i && i < 6 ? 'r' : null, x)));
      t.append(hr);
      plans.forEach(([a, p]) => {
        const tr = h('tr'); tr.dataset.arm = a.name;
        tr.append(h('td', null, a.label), h('td', 'r', p.reused === null ? 'not known' : `${p.reused} of ${n}`), h('td', 'r', String(p.usual)), h('td', 'r', String(p.worst)), h('td', 'r', String(p.minutes)),
          h('td', 'r', p.usd === null ? COST : `${B.ctx.money(p.usd)} · worst ${B.ctx.money(p.worstUsd)}`), h('td', null, !a.guard ? 'None: no Claude login' : g[a.guard] === true ? 'Reached' : 'Not reached'));
        t.append(tr);
      });
      s.append(figs, t);
      if (plans.some(([, p]) => p.reused === null)) s.append(h('p', 'board-from', 'With run settings changed, the Board cannot tell which results the run reuses: the estimate counts each task.'));
      s.append(h('p', 'board-from', 'A cost is an estimate: each session at the mean list price of this project\'s own card sessions, those of the arm\'s model for an arm with one.'));
    }
    s.append(h('p', 'warn-note', 'A run does not start while a login is at the usage guard, and it stops there. Done tasks are kept.'),
      h('p', 'info-note', 'Each task runs in its own Docker container, from the same image, with the same run settings for every arm. Logins are copied in at start only.'));
    const held = chosen.filter((a) => a.guard && g[a.guard] === true), l = live(), e = engineOf(), conv = chosen.some((a) => a.kind === 'conveyor');
    const why = l && l.state === 'running' ? 'A run is going: stop it on the Overview, or wait for its end.'
      : !chosen.length ? null
        : waiting.length ? `Start waits for the check of ${names(waiting)}.`
          : unready.length ? `Start waits for ${names(unready)}, not ready.`
            : held.length ? `The usage guard is reached for ${names(held)}: no run starts while it stands.`
              : !set ? 'A run setting does not read: correct it beside its field.'
                : conv && B.start.engine === 'commit' && !/^[0-9a-f]{40}$/.test(e) ? 'A commit is named by its full 40-character id.' : null;
    const startBtn = button(`Start · ${plural(chosen.length, 'arm')} on ${plural(n, 'task')}`, 'btn-primary', 'start', `Start: ${plural(chosen.length, 'arm')} on ${plural(n, 'task')}`, () => {
      // What the page shows, and nothing else: n, each arm ticked, the version (for a Conveyor arm) and each setting changed.
      const args = ['run', String(n)].concat(...chosen.map((a) => ['--arm', a.name]), conv ? ['--engine', e] : [], Object.keys(set).length ? ['--settings', JSON.stringify(set)] : []);
      const more = {};  // the receipt's run, kept with the answer (beside Start until the next Start)
      send('start', args, (t) => {
        const m = RECEIPT.exec(t);
        if (!m) return t.replace(/^conveyor: /, '');
        Object.assign(more, { run: m[1], ended: m[2] === 'ended' });
        return m[2] === 'ended' ? `Run ${m[1]} ended: it reused the saved result of each task.` : `Run ${m[1]} started.`;
      }, (t) => { readHist(true); const m = RECEIPT.exec(t); if (m && m[2] === 'ended') openRun(m[1]); }, null, more);
    });
    startBtn.disabled = Boolean(why) || !chosen.length || B.busy;
    if (why) { const no = h('p', 'warn-note bench-why', why); no.setAttribute('role', 'alert'); s.append(no); }
    // The receipt opens its own run, by its ID (not the newest), whether it goes on or has ended.
    const rc = B.said.get(saidKey('start')), said = saidAt('start');
    if (said && rc && rc.run) said.append(' ', button(rc.ended ? 'Open its results' : 'Watch run', 'btn-sm', 'watch-run', `Open the run ${rc.run}`, () => { openRun(rc.run); draw(); }));
    s.append(startBtn, said);
    return s;
  }

  // ---- Infographic: a fixed template, filled by code ----
  const PALETTE = { 1: '#2a78d6', 2: '#eb6834', 3: '#1baf7a', 4: '#eda100', 5: '#e87ba4' };
  const FONT = { title: [28, 700, '#14171f'], sub: [15, 400, '#4a5262'], head: [19, 700, '#14171f'], body: [16, 400, '#14171f'], big: [20, 700, '#14171f'], warn: [16, 700, '#a8201a'] };
  const NOTES = ['A task is resolved when its FAIL_TO_PASS and PASS_TO_PASS tests all succeed in the official harness on the arm\'s final patch.',
    'A difference inside the noise band is not a difference. Tasks are Python only, and the models may have seen these repositories.',
    'Each task ran in its own Docker container with the same limits for every arm. A task whose image did not build is "not run", never failed.'];
  const WARN = 'This does not show that one way is better on your code.';
  // The template's marks, top to bottom: the title (as typed, else the default), the line under it, each run's panel
  // (its bars with the noise lines, its sessions, tokens and minutes), then the notes, which the title cannot remove.
  function template(runs, title, id) {
    const m = [], W = 1200, text = (x, y, k, s) => m.push({ t: 'text', x, y, k, s }), rect = (x, y, w, h2, f, s) => m.push({ t: 'rect', x, y, w, h: h2, f, s }),
      line = (x1, y1, x2, y2, s, dash) => m.push({ t: 'line', x1, y1, x2, y2, s, dash });
    const date = (iso) => { const t = Date.parse(iso); return Number.isFinite(t) ? new Date(t).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' }) : 'date not read'; };
    text(40, 56, 'title', String(title || '').trim().slice(0, 90) || IG_TITLE);
    text(40, 82, 'sub', `Conveyor Bench · SWE-bench Verified, pinned order · graded by the official harness · ${runs.map((r) => date(r.started)).filter((v, i, a) => a.indexOf(v) === i).join(', ')}`);
    line(40, 98, W - 40, 98, '#c9ced8');
    let y = 98;
    const n0 = num(runs[0] && runs[0].n) || 0;
    runs.forEach((r) => {
      const cols = colsOf(r), n = num(r.n) || 0, d = noiseOf(n);
      y += 36; text(40, y, 'head', `Run ${r.id} · ${plural(n, 'task')} · ${plural(cols.length, 'arm')}${n !== n0 ? ' · a different n: its own panel, no line across' : ''}`);
      y += 22; text(40, y, 'sub', `Resolved tasks, one bar an arm. Dashed lines: the noise band for ${n} tasks (a difference under ${d} is within it).`);
      const top = y + 14, hgt = cols.length * 40 + 50;
      rect(40, top, W - 80, hgt, '#f4f5f8', '#c9ced8');
      cols.forEach((c, i) => {
        const by = top + 22 + i * 40, v = num(c.resolved) || 0, x0 = 310, tw = 470, at = (k) => x0 + (n ? (tw * Math.max(0, Math.min(n, k))) / n : 0);
        text(60, by + 16, 'body', colName(c).slice(0, 30));
        rect(x0, by, tw, 22, '#eceef3', null);
        rect(x0, by, at(v) - x0, 22, PALETTE[group(c)], null);
        line(at(v - d), by - 3, at(v - d), by + 25, '#4a5262', true);
        line(at(v + d), by - 3, at(v + d), by + 25, '#4a5262', true);
        text(794, by + 19, 'big', `${v} of ${n}`);
      });
      const nr = cols.reduce((x, c) => x + (num(c.notRun) || 0), 0);
      text(60, top + hgt - 16, 'sub', `Sessions ${cols.map((c) => (num(c.sessions) === null ? '–' : c.sessions)).join(' · ')} · tokens ${cols.map((c) => tokens(c.tokens)).join(' · ')} · minutes ${cols.map((c) => (num(c.minutes) === null ? '–' : Math.round(c.minutes))).join(' · ')}${nr ? ` · ${plural(nr, 'task')} not run` : ''}`);
      y = top + hgt + 30;
      line(40, y, W - 40, y, '#c9ced8');
    });
    y += 32; text(40, y, 'head', 'How to read this');
    NOTES.forEach((t) => { y += 26; text(40, y, 'body', t); });
    y += 28; text(40, y, 'warn', WARN);
    const models = Array.from(new Set(runs.flatMap((r) => colsOf(r).map((c) => c.model)).filter((x) => typeof x === 'string' && x)));
    const versions = Array.from(new Set(runs.flatMap((r) => colsOf(r).filter((c) => isConveyor(c) || c.engine).map(verOf))));
    y += 32; text(40, y, 'sub', `Made by code from ${plural(runs.length, 'stored run')} with a fixed template; no model wrote or chose anything · models: ${models.join(', ') || 'the models each arm set'}${versions.length ? ` · Conveyor ${versions.join(', ')}` : ''}`);
    y += 22; text(40, y, 'sub', `Export ${id} · figures only: no code, no names.`);
    return { w: W, h: y + 28, marks: m };
  }
  const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  function svgText(t) {
    const out = [`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${t.w} ${t.h}" width="${t.w}" height="${t.h}"><rect width="${t.w}" height="${t.h}" fill="#ffffff"/>`];
    t.marks.forEach((k) => {
      if (k.t === 'text') { const [size, weight, fill] = FONT[k.k]; out.push(`<text x="${k.x}" y="${k.y}" font-family="system-ui, sans-serif" font-size="${size}" font-weight="${weight}" fill="${fill}">${esc(k.s)}</text>`); }
      if (k.t === 'rect') out.push(`<rect x="${k.x}" y="${k.y}" width="${Math.max(0, k.w)}" height="${k.h}" rx="4" fill="${k.f}"${k.s ? ` stroke="${k.s}"` : ''}/>`);
      if (k.t === 'line') out.push(`<line x1="${k.x1}" y1="${k.y1}" x2="${k.x2}" y2="${k.y2}" stroke="${k.s}" stroke-width="2"${k.dash ? ' stroke-dasharray="5 4"' : ''}/>`);
    });
    out.push('</svg>');
    return out.join('');
  }
  function svgNode(t) {
    const NS = 'http://www.w3.org/2000/svg', svg = document.createElementNS(NS, 'svg');
    svg.setAttribute('viewBox', `0 0 ${t.w} ${t.h}`); svg.setAttribute('class', 'bench-ig'); svg.setAttribute('role', 'img');
    svg.setAttribute('aria-label', 'Infographic of the runs selected');
    const add = (tag, attrs, text) => { const e = document.createElementNS(NS, tag); Object.entries(attrs).forEach(([k, v]) => e.setAttribute(k, String(v))); if (text !== undefined) e.textContent = text; svg.append(e); };
    add('rect', { width: t.w, height: t.h, fill: '#ffffff' });
    t.marks.forEach((k) => {
      if (k.t === 'text') { const [size, weight, fill] = FONT[k.k]; add('text', { x: k.x, y: k.y, 'font-size': size, 'font-weight': weight, fill, 'font-family': 'system-ui, sans-serif', 'data-k': k.k }, k.s); }
      if (k.t === 'rect') add('rect', Object.assign({ x: k.x, y: k.y, width: Math.max(0, k.w), height: k.h, rx: 4, fill: k.f }, k.s ? { stroke: k.s } : {}));
      if (k.t === 'line') add('line', Object.assign({ x1: k.x1, y1: k.y1, x2: k.x2, y2: k.y2, stroke: k.s, 'stroke-width': 2 }, k.dash ? { 'stroke-dasharray': '5 4' } : {}));
    });
    return svg;
  }
  // The PNG: the same marks drawn on a canvas (the page's rules let it load no image of its own making).
  function png(t, name, key) {
    const c = document.createElement('canvas'), x = c.getContext && c.getContext('2d');
    if (!x) { say(key,'Not made: this browser cannot draw a PNG here. Download SVG works.', 'bad'); return false; }
    c.width = t.w * 2; c.height = t.h * 2; x.scale(2, 2);
    x.fillStyle = '#ffffff'; x.fillRect(0, 0, t.w, t.h);
    t.marks.forEach((k) => {
      if (k.t === 'text') { const [size, weight, fill] = FONT[k.k]; x.font = `${weight} ${size}px system-ui, sans-serif`; x.fillStyle = fill; x.fillText(k.s, k.x, k.y); }
      if (k.t === 'rect') { x.fillStyle = k.f; x.fillRect(k.x, k.y, Math.max(0, k.w), k.h); if (k.s) { x.strokeStyle = k.s; x.strokeRect(k.x, k.y, k.w, k.h); } }
      if (k.t === 'line') { x.strokeStyle = k.s; x.lineWidth = 2; x.setLineDash(k.dash ? [5, 4] : []); x.beginPath(); x.moveTo(k.x1, k.y1); x.lineTo(k.x2, k.y2); x.stroke(); }
    });
    download(name, c.toDataURL('image/png'));
    return true;
  }
  function infographicPage() {
    if (!hist()) return [reading('the runs')];
    const runs = runsOf().filter((r) => B.sel.includes(r.id));
    const s = section('bench-infographic', 'Infographic');
    const tools = h('div', 'bench-tools');
    tools.append(button('Back', 'btn-quiet', 'back', 'Back to the overview', () => go('overview')));
    if (!runs.length) {
      s.querySelector('.bench-head').append(tools);
      s.append(h('p', 'board-from', `Tick up to ${MAX_SEL} runs on the Overview's History, then Generate infographic.`));
      return [s];
    }
    const stamp = new Date(B.ctx.now()).toISOString().replace(/[-:]/g, '').replace(/^(\d{8})T(\d{4}).*$/, '$1-$2'), id = `ig-${stamp}`;
    const t = template(runs, B.title, id);
    s.querySelector('.bench-head').append(h('span', 'board-from', `Made by code from ${plural(runs.length, 'stored run')}, with a fixed template. No model wrote or chose anything. Export id ${id}.`));
    const lab = h('label', 'board-from'), title = h('input', 'field bench-title');
    title.value = B.title; title.dataset.act = 'ig-title'; title.setAttribute('aria-label', 'Title');
    title.addEventListener('input', () => { B.title = title.value; const was = s.querySelector('svg.bench-ig'); if (was) was.replaceWith(svgNode(template(runs, B.title, id))); });
    lab.append('Title ', title);
    // The same figures as a table, saved beside the picture as <id>.csv by either download.
    const head = ['Run', 'Arm', 'Resolved', 'Noise for n', 'Sessions', 'Tokens', 'Cost'];
    const figs = runs.flatMap((r) => colsOf(r).map((c) => [r.id, colName(c), `${c.resolved} of ${r.n}`, String(noiseOf(num(r.n) || 0)),
      num(c.sessions) === null ? '–' : String(c.sessions), tokens(c.tokens), costSaid(c.cost)]));
    const csv = [head].concat(figs).map((row) => row.map((v) => `"${String(v).replace(/"/g, '""')}"`).join(',')).join('\r\n') + '\r\n';
    const table = () => download(`${id}.csv`, `data:text/csv;charset=utf-8,${encodeURIComponent(csv)}`);
    // A download's answer belongs to the runs it was made from: a new selection shows no answer about the last one.
    const of = runs.map((r) => r.id).join(','), svgKey = `ig-svg-${of}`, pngKey = `ig-png-${of}`;
    tools.append(lab, button('Download SVG', '', 'ig-svg', 'Download the infographic as SVG', () => {
      download(`${id}.svg`, `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svgText(template(runs, B.title, id)))}`); table(); say(svgKey, `Downloaded: ${id}.svg and ${id}.csv.`, 'ok');
    }),
      button('Download PNG', '', 'ig-png', 'Download the infographic as PNG', () => { if (png(template(runs, B.title, id), `${id}.png`, pngKey)) { table(); say(pngKey, `Downloaded: ${id}.png and ${id}.csv.`, 'ok'); } }));
    s.querySelector('.bench-head').append(tools);
    s.append(saidAt(svgKey), saidAt(pngKey));
    s.append(h('p', 'board-from', `Selected: ${runs.map((r) => `${r.id} (${plural(num(r.n) || 0, 'task')})`).join(' and ')}. Up to ${MAX_SEL} runs. Runs of different n get their own panel. The title can change; the notes on the graphic cannot be removed.`),
      svgNode(t));
    const tab = section('bench-ig-table', 'The same figures as a table', null, 'Saved beside the SVG.'), wrap = h('div', 'tests-scroll'), tt = h('table', 'tests-table'), hr = h('tr');
    head.forEach((x, i) => hr.append(h('th', i > 1 ? 'r' : null, x)));
    tt.append(hr);
    figs.forEach((row) => { const tr = h('tr'); row.forEach((v, i) => tr.append(h('td', i === 0 ? 'mono' : i === 1 ? null : 'r', v))); tt.append(tr); });
    wrap.append(tt); tab.append(wrap);
    return [s, tab];
  }

  // ---- the panel ----
  function draw() {
    const el = B.el;
    if (!el) return;
    if (B.d.repo === null) { el.replaceChildren(B.ctx.state('empty', 'No benchmarks to show', 'Conveyor did not run on this project on the build machine yet. Pick a project under Show, above the tabs.')); return; }
    readHist(false);
    const a = document.activeElement && el.contains(document.activeElement) && document.activeElement.dataset ? document.activeElement.dataset.act : null;
    // The caret of a text field being typed in, put back with its focus (a number field has none).
    const at = a && typeof document.activeElement.selectionStart === 'number' ? [document.activeElement.selectionStart, document.activeElement.selectionEnd] : null;
    const root = h('div', B.sel.length && B.page === 'overview' ? 'bench bench-has-selbar' : 'bench');
    root.append(pages());
    if (B.page === 'overview') {
      root.append(newest(), history(), armsPart(), drift());
      if (B.sel.length) root.append(selbar());
    } else if (B.page === 'run') root.append(...runPage());
    else if (B.page === 'compare') root.append(...comparePage());
    else if (B.page === 'start') root.append(...startPage());
    else root.append(...infographicPage());
    el.replaceChildren(root);
    const keep = B.keep || a;
    B.keep = null;
    if (keep) { const k = Array.from(el.querySelectorAll('[data-act]')).find((x) => x.dataset.act === keep); if (k) { k.focus({ preventScroll: true }); if (at && keep === a && typeof k.selectionStart === 'number') k.setSelectionRange(...at); } }
  }
  function render(el, d, ctx) {
    const view = ctx.project(d);
    ctx.title(Array.isArray(view.repos) && view.repos.length > 1 && view.repo ? `Benchmarks: ${view.repo}` : null);
    if (B.repo !== undefined && view.repo !== B.repo) { B.sel = []; B.open = null; B.task = null; B.cmp = { a: '', b: '', data: null, text: null, all: false, ask: null, n: B.cmp.n }; B.runs.clear(); B.edit = null; B.landed = false; }
    Object.assign(B, { el, ctx, d: view, repo: view.repo });
    watchOut();
    // The tab opens on the work that needs attention, each time it is shown: the page of the project's run in
    // progress, else Start a run. A run that starts while the tab is shown does not move the page: Watch run, in the
    // page row, opens it.
    if (!B.landed && typeof view.repo === 'string') {
      B.landed = true;
      const l = live();
      if (l && l.state === 'running' && typeof l.id === 'string') openRun(l.id); else B.page = 'start';
    }
    if (B.held) { B.late = true; return; }
    draw();
  }
  // The panel taken out of the page (another tab shown: the Board removes the other tabs' panels) makes the next draw
  // choose the page again. The Board draws a panel shown again with a part equal to the last one through same().
  let watched = null;
  function watchOut() {
    const box = B.el && B.el.closest('[data-panel]'), grid = box && box.parentNode;
    if (!grid || grid === watched || typeof window.MutationObserver !== 'function') return;
    watched = grid;
    new window.MutationObserver(() => { if (B.el && !B.el.isConnected) B.landed = false; }).observe(grid, { childList: true });
  }
  function same(el, d, ctx) { if (!B.landed) render(el, d, ctx); }
  // While an arm's check runs, the arms are read again on the Board's clock (its tick), one read at a time and at most
  // one each CHECK_MS after the last one ended: a check alone moves no run, so the Board sends the panel no update for
  // it, yet its step and its end show with no press, after a reload too (the arms read checking then).
  const CHECK_MS = 5000;
  function tick() {
    const was = B.hist;
    if (!was || was.repo !== B.repo || was.busy || !armsOf().some((a) => a.state === 'checking')) return;
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
    rowSelector: '.bench-table tr, .bench-mat tr',
    isEmpty: (d) => d.repo === null && !(d.others && typeof d.others === 'object' && Object.keys(d.others).length),
    empty(el, ctx) { el.append(ctx.state('empty', 'No benchmarks to show', 'Conveyor did not run on this project on the build machine yet. Start Conveyor there, and its benchmarks show here.')); },
    error(el, message, ctx) { el.append(ctx.state('error', 'The Board could not read the benchmarks', message)); },
    render,
    same,
    tick,
  });
}());
