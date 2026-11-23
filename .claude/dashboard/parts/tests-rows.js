// SPDX-License-Identifier: Apache-2.0
// The Tests panel's figures, its table, an opened row and its events, Test limits, the Test map part, and the draws
// of the Tests and Test settings panels (drawTests, drawSet). Part of panels/tests.js, which asks for it by name
// (DASH_APP.use) and gives it what it uses; boot.js loads it before the panels.
(() => {
  'use strict';
  // What this part uses of panels/tests.js, set when tests.js asks for the part (DASH_APP.part, at the end).
  let NEVER, PACK, CONTROL, MARKS, S, num, list, obj, one, pct, tests, settings, dk, shown, marks, look, timed, wallOnly,
    clockTook, COLS, say, button, row, section, setting, control, ENDED, SENDING, actions, mmss, hollowOf, proxyOf,
    proxySaid, hollowSaid, verdictOf, causesOf, causeSaid, failsOf, caughtOf, partsOf, notCard, kindSaid, casesSaid, plural,
    failKinds, mutDone, survivors, trimmed, mutState, mutCell, progress, send, verdictChip, reasonOf, box, rowAction,
    caseHit, shows, neverWhy, wholeCost, wallWhy, runBy, asking, stepButtons, judged, rowActions, actionsHead,
    selBar, optsOf, stateSaid, fixSaid, gainOf, helpedChip, numbersSaid, mutantsSaid, optRuns, optRunSaid, recent,
    removed, weakened, editsOf, editSaid, editIssue, editsSection, autofile, anyIssueUrl, draw;

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
  // stamp: its runs on record, the times of its newest runs, and the cards of its newest edits; #1036: a new survey
  // time replaces the last one, so the count of runs stays and only the newest runs' times change). A failed read is
  // tried again when the Timeline is opened again.
  const olderStamp = (f) => [f.runsOnRecord].concat(list(f.runs).map((r) => (obj(r) ? r.time : '')),
    editsOf().filter((e) => e.file === f.file).map((e) => e.card)).join('|');
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
  // newest first: when, its kind, its card and its failing cases, a line for each verdict its cases have (partsOf()).
  // null with none.
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
    xs.flatMap(partsOf).forEach((x) => {
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
    const mut = mutationPane(f);
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
  // Mutation (more): its check's state, and each mutant its tests did not catch, with its line and change.
  function mutationPane(f) {
    const h = S.ctx.h, file = f.file, mut = h('div', 'tests-mutation');
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
    return mut;
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
  function issueOf(f, any) {
    const a = S.ctx.issueLink({ issue: f.issue, url: any ? any.replace(/\d+$/, String(f.issue)) : null });
    a.title = 'Its issue';
    return a;
  }
  function table(files, counts) {
    const h = S.ctx.h, el = h('section', 'tests-files'), any = anyIssueUrl(files);
    const bar = filterBar(files, counts), find = searchBox();
    const q = S.query.trim().toLowerCase();
    const { shownFiles, col } = shownOf(files, q);
    const t = h('table', 'tests-table'), head = headRow(shownFiles, col);
    const thead = h('thead'); thead.append(head);
    const body = h('tbody');
    if (!shownFiles.length) { const tr = h('tr', 'tests-none'), td = h('td', 'board-from', 'No test file matches'); td.colSpan = COLS.length; tr.append(td); body.append(tr); }
    shownFiles.forEach((f) => body.append(...fileRow(f, q, any)));
    t.append(thead, body);
    const wrap = h('div', 'tests-scroll'); wrap.append(t);
    el.append(find, bar, wrap);
    return el;
  }
  // The filter chips over the table (table): All, and each status with its count of files.
  function filterBar(files, counts) {
    const h = S.ctx.h, bar = h('div', 'tests-filters');
    bar.setAttribute('role', 'group'); bar.setAttribute('aria-label', 'Show the files');
    [['all', 'All', files.length]].concat(MARKS.filter(([k]) => counts[k]).map(([k, name]) => [k, name, counts[k]])).forEach(([k, name, n]) => {
      const b = button(`${name} ${n}`, 'rules-tog', 'filter', `${name}: ${n} ${n === 1 ? 'file' : 'files'}`, () => { S.filter = k; draw(); say(`Showing: ${name}`); });
      b.dataset.filter = k; b.setAttribute('aria-pressed', String(S.filter === k));
      bar.append(b);
    });
    return bar;
  }
  // The search box: any part of the path or of a case name, in any case, with the filter chip picked. It is the same
  // node from one draw to the next.
  function searchBox() {
    const h = S.ctx.h;
    if (!S.search) {
      const s = h('input', 'field tests-search');
      s.type = 'search'; s.placeholder = 'Search test files'; s.dataset.act = 'search'; s.setAttribute('aria-label', 'Search the test files by path or case name');
      s.addEventListener('input', () => { S.query = s.value; draw(); });
      S.search = s;
    }
    S.search.value = S.query;
    const find = h('div', 'tests-filters'); find.append(S.search);
    return find;
  }
  // The files the table shows (shownFiles), in their order, and the column they are sorted by (col), or null. q: the
  // search text.
  function shownOf(files, q) {
    // With no sort picked, the timed files first, then the rows that need a look; the snapshot's order (the highest CPU s
    // first) inside each. A sort keeps that order among equal values.
    let shownFiles = files.map((f, i) => [f, i]).filter(([f]) => (S.filter === 'all' || marks(f).some((m) => m[0] === S.filter)) && shows(f, q))
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
    return { shownFiles, col };
  }
  // The table's head row: a sort button a column, and the header checkbox over the files shown.
  function headRow(shownFiles, col) {
    const h = S.ctx.h, head = h('tr');
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
    return head;
  }
  const cell = (x, cls) => { const td = S.ctx.h('td', cls); td.append(x); return td; };
  // The row of file f in the table, and under it its open runs (more) when it is open. q: the search text; any: the
  // project's issue address (issueOf).
  function fileRow(f, q, any) {
    const h = S.ctx.h, open = S.open.has(f.file), tr = h('tr', 'tests-row');
    tr.dataset.file = f.file;
    const name = button(f.file, 'btn-quiet tests-name', 'open', `${f.file}: ${open ? 'close' : 'open'} its runs`, () => { if (S.open.has(f.file)) S.open.delete(f.file); else S.open.add(f.file); S.keep = { act: 'open', file: f.file }; draw(); });
    name.setAttribute('aria-expanded', String(open));
    const check = h('input', 'tests-check');
    check.type = 'checkbox'; check.dataset.act = 'select'; check.checked = S.sel.has(f.file);
    check.setAttribute('aria-label', `Select ${f.file}`);
    check.addEventListener('change', () => { if (check.checked) S.sel.add(f.file); else S.sel.delete(f.file); S.keep = { act: 'select', file: f.file }; draw(); });
    const chips = fileChips(f, any);
    const fileCell = cell(check, 'tests-file');
    fileCell.append(name);
    // A row the search found by a case name, not by its path, names that case beside the file name.
    const hit = caseHit(f, q);
    if (hit) fileCell.append(h('span', 'tests-quiet tests-matched', `Case: ${hit}`));
    if (!timed(f)) {
      // A file never timed: one cell in place of its figures.
      const none = cell('Not timed yet', 'tests-untimed');
      none.colSpan = COLS.length - 2;
      tr.append(fileCell, none, cell(chips));
    } else tr.append(fileCell, ...figureCells(f), cell(chips));
    if (!open) return [tr];
    const more2 = h('tr', 'tests-open'), td = h('td'); td.colSpan = COLS.length; td.append(more(f)); more2.dataset.file = f.file; more2.append(td);
    return [tr, more2];
  }
  // The status of file f (fileRow): chips; its issue as a link; Runs other test files and Whole suite only as grey text.
  function fileChips(f, any) {
    const h = S.ctx.h, chips = h('span', 'rules-marks');
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
      if (k === 'proxy') {
        const p = proxyOf(f), c = S.ctx.chip(`${words}: ${p.length === 1 ? 'line' : 'lines'} ${p.map((x) => x.line).join(', ')}`, tone);
        c.classList.add('tests-proxy');
        c.title = p.map((x) => `${x.line}: ${x.text}`).join('\n');
        chips.append(c, ...p.map((x) => h('span', 'tests-quiet tests-proxy-why', proxySaid(x))));
        return;
      }
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
    return chips;
  }
  // The figures of a timed file f (fileRow), a cell each, from CPU s to Mutants caught.
  function figureCells(f) {
    const last = obj(f.lastRun) || {};
    // The newest run's clock time, with its date and time on hover.
    const took = cell(clockTook(last.sec), 'tests-num');
    if (num(last.sec) !== null && typeof last.time === 'string' && !Number.isNaN(Date.parse(last.time))) {
      took.title = `${S.ctx.stamp(Date.parse(last.time), { date: true, seconds: true })}, ${last.whole === true ? 'whole suite' : last.survey === true ? 'test-speed survey' : 'card'}`;
    }
    const count = COLS.find((c) => c[0] === 'count')[2](f);
    const caught = cell(num(f.caught) === null ? '—' : String(f.caught), 'tests-num tests-caught');
    if (num(f.caught) !== null) caught.title = `Edited until it passed: ${num(f.changedToPass) || 0}`;
    // Mutants caught: empty before a check; when and on which commit its newest done check ran, on hover.
    const mut = cell(mutCell(f), 'tests-num tests-mutants'), md = mutDone(f);
    if (md) mut.title = `Checked ${S.ctx.when(md.at)} on commit ${String(md.sha || 'not recorded').slice(0, 7)}`;
    return [cell(one(f.cpu), 'tests-num'), cell(one(f.median), 'tests-num'), cell(pct(f.change), 'tests-num'),
      cell(bars(f)), cell(num(last.clockPerCpu) === null ? '—' : `${one(last.clockPerCpu)}×`, 'tests-num'), cell(count === null ? '—' : String(count), 'tests-num'), took, caught, mut];
  }

  // ---- Test limits ----
  const UTC = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;  // a time as `test-settings history-start` takes it
  function limits() {
    const h = S.ctx.h, el = section('tests-limits', 'Test limits', PACK), t = tests(), s = settings();
    if (!t) return el;
    const files = Object.entries(obj(s.files) || {}).filter(([, v]) => obj(v));
    const items = (pick, words) => {
      const ul = h('ul', 'tests-list'), got = files.filter(([, v]) => pick(v) !== null && pick(v) !== undefined);
      got.forEach(([f, v]) => ul.append(h('li', null, `${f}: ${words(pick(v))}`)));
      if (!got.length) ul.append(h('li', 'board-from', 'None'));
      return ul;
    };
    el.append(row('purpose', 'Files slow on purpose', 'The CPU test rules file no issue about these files. Mark a file in its row, under More.', null, items((v) => (typeof v.slowOnPurpose === 'string' ? v.slowOnPurpose : null), (r) => r)));
    // #457's rows, only when the snapshot names them.
    const box = obj(s.box);
    if (box) el.append(row('box', 'Hard box for each test file', 'A test file gets no more CPU or memory than its test slot. The engine sets this. You cannot change it.', null, h('span', 'board-value', box.on === false ? 'Off' : 'On')));
    if (typeof s.slowIssues === 'boolean') {
      el.append(row('off-card-runs', 'Take a file off card runs', 'This setting has no effect now, On or Off. The Auto-file rules file the issues about test files.', null,
        ...setting('slowIssues', { act: 'slow-issues', label: 'Take a file off card runs', choices: [['true', 'On'], ['false', 'Off']],
          check: () => null, send: (v) => control(['slow-issues', v]), said: (v) => `Take a file off card runs is now ${v === 'true' ? 'On' : 'Off'}` })));
    }
    return el;
  }
  // Test history: "Test history starts at", the control record's testsFrom, which the snapshot gives as
  // settings.historyStart. The figures, failures, card steps, whole-suite run and drafts count only the runs on or after
  // it; nothing is deleted. A section of its own: it saves to the control record, the Test limits to the pack file.
  function history() {
    const el = section('tests-history', 'Test history', CONTROL);
    el.append(row('history-start', 'Test history starts at', 'Only the runs, failed steps and flaky entries on or after this time count on this page, in its drafts and for the Tests judge. Older ones are kept, not counted. Empty: every run counts.', null,
      ...setting('historyStart', { act: 'history-start', label: 'Test history starts at', placeholder: '2026-11-21T00:00:00Z', clear: 'Count every run',
        check: (v) => (v === '' || UTC.test(v) ? null : 'Type a UTC time like 2026-11-21T00:00:00Z, or leave it empty.'),
        send: (v) => control(['history-start', v === '' ? 'clear' : v]),
        said: (v) => (v === '' ? 'Every run counts again' : `Test history starts at ${v}`) })));
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
    el.append(mapLine(m, live));
    const not = notMapped(m), res = lastBuild(b, live), ctl = mapCtl(m, b, live);
    if (not) el.append(not);
    if (res) el.append(res);
    if (ctl.childNodes.length) el.append(ctl);
    if (S.mapRefused) { const no = h('p', 'rules-refused', `Not started: ${S.mapRefused}`); no.setAttribute('role', 'alert'); el.append(no); }
    return el;
  }
  // The map's state line (mapPart).
  function mapLine(m, live) {
    const h = S.ctx.h, line = h('p', 'tests-map-state');
    if (m.state === 'running') {
      line.append(progress(`Test map: ${m.done} of ${m.of} test files`, num(m.done) || 0, num(m.of) || 0),
        h('span', null, ` Being made: ${m.done} of ${m.of} test files run${num(m.started) === null ? '' : `, ${mmss(S.ctx.now() / 1000 - m.started)} so far`}.`));
    } else if (live) {
      line.append(progress('Test map: waiting for a test slot'), h('span', null, ' Waiting for a test slot on the build machine.'));
    } else if (S.mapSent) {
      line.append(progress('Test map: starting'), h('span', null, ` Starting: ${SENDING}`));
    } else if (m.state === 'made') {
      line.append(S.ctx.chip('Made', 'ok'), madeSaid(m));
    } else if (m.state === 'off') {
      line.append(S.ctx.chip('Off', 'quiet'), ' The pack\'s test.map is "off": a card\'s tests are found by name. To turn it on, remove test.map from the pack, then build the map here or run setup.');
    } else if (m.state === 'failed') {
      line.append(S.ctx.chip('Failed', 'bad'), ` ${m.why || 'no reason given'}`);
    } else {
      line.append(S.ctx.chip('Not made yet', 'warn'), ' A card\'s tests are found by name until the map is made.');
    }
    return line;
  }
  // A made map's line (mapLine): how many files it maps, and how old it is.
  function madeSaid(m) {
    const age = num(m.age) === null ? '' : m.age ? ` · ${m.age} ${m.age === 1 ? 'commit' : 'commits'} behind main` : ' · up to date with main';
    const when = typeof m.made === 'string' ? ` · made ${S.ctx.when(m.made)}` : '';
    const took = num(m.seconds) === null ? '' : `, in ${mmss(m.seconds)}`;
    const nm = Array.isArray(m.notMapped) ? m.notMapped.length : 0;
    const not = nm ? `, ${nm} test ${nm === 1 ? 'file' : 'files'} not mapped` : '';
    return ` ${m.sources} source files and ${m.tests} test files mapped${not}${age}${when}${took}.`;
  }
  // The test files the made map could not map, each with why, folded; null for none.
  function notMapped(m) {
    if (!(m.state === 'made' && Array.isArray(m.notMapped) && m.notMapped.length)) return null;
    const h = S.ctx.h, d = h('details', 'tests-map-not');
    d.append(h('summary', null, `Test files not mapped: ${m.notMapped.length}. The map does not use them to pick a card's tests.`));
    const ul = h('ul', 'tests-list');
    m.notMapped.forEach((x) => { const li = h('li', null, `${x.file}: `); li.append(h('pre', 'tests-out', String(x.why || 'no reason given'))); ul.append(li); });
    d.append(ul);
    return d;
  }
  // The last build's result (b), in place, once it has ended; null while one runs or with none.
  function lastBuild(b, live) {
    if (!(b && !live && MAPS[b.state])) return null;
    const said = [num(b.start) !== null && num(b.end) !== null ? `in ${mmss(b.end - b.start)}` : null,
      num(b.end) !== null ? S.ctx.when(at(b.end)) : null, typeof b.reason === 'string' && b.reason ? b.reason : null].filter(Boolean).join(' · ');
    const res = S.ctx.h('p', 'tests-map-result');
    res.append(S.ctx.chip(`Last build: ${MAPS[b.state]}`, b.state === 'made' ? 'ok' : b.state === 'failed' ? 'bad' : 'quiet'), S.ctx.h('span', 'board-from', ` ${said}`));
    return res;
  }
  // Build the test map, with the tool and the last whole-suite run's time named, or Stop (mapPart).
  function mapCtl(m, b, live) {
    const h = S.ctx.h, ctl = h('div', 'tests-act-row');
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
    return ctl;
  }

  // A control that is used tells which panel's note says what it did (say()).
  const hooked = new WeakSet();
  function hook(el, from) {
    if (hooked.has(el)) return;
    hooked.add(el);
    ['click', 'change', 'input', 'keydown'].forEach((e) => el.addEventListener(e, () => { S.from = from; }, true));
  }
  // A panel's note, which keeps the text it said over a new draw.
  function noteOf(el) {
    const note = S.ctx.h('p', 'board-note tests-note'), was = el.querySelector('.tests-note');
    note.setAttribute('aria-live', 'polite');
    if (was) note.textContent = was.textContent;
    return note;
  }
  // While a change waits for its answer, the panel's controls wait too, except those that only show or pick.
  function still(root) {
    if (!S.busy) return;
    root.querySelectorAll('button, input, select, textarea').forEach((b) => {
      if (!['filter', 'edits-filter', 'open', 'goto', 'copy', 'search', 'select', 'select-all', 'more', 'timeline-all', 'judge-report'].includes(b.dataset.act) && !/^(sort|figure|tab|tl)-/.test(b.dataset.act || '')) b.disabled = true;
    });
  }
  // The Test settings panel (#1088): Test actions, Test limits, Test history and Auto-file. With no test figures (the pack does not
  // read: tests is null) it says so and holds none of them: Test limits and Auto-file read the figures, and the Tests
  // model is only for Judge and Explain the slowdown, which act on the table's files, and there is no table then.
  function drawSet() {
    const el = S.setEl, h = S.ctx.h;
    hook(el, 'set');
    if (S.d.repo === null) {
      el.replaceChildren(S.ctx.state('empty', 'No test settings to show', 'Conveyor did not run on this project on the build machine yet. Pick a project under Show, above the tabs.'));
      return;
    }
    const root = h('div', 'tests tests-set');
    if (!tests()) root.append(h('p', 'warn-note', 'Conveyor could not read the test settings of this project. Its pack does not read, or the build machine runs an older Conveyor.'));
    else root.append(actionsHead(), limits(), history(), autofile());
    el.replaceChildren(root, noteOf(el));
    still(root);
  }
  function drawTests() {
    const el = S.el, h = S.ctx.h;
    hook(el, 'tests');
    if (S.d.repo === null) {
      el.replaceChildren(S.ctx.state('empty', 'No tests to show', 'Conveyor did not run on this project on the build machine yet. Pick a project under Show, above the tabs.'));
      return;
    }
    const t = tests(), every = list(t && t.files).filter((f) => obj(f) && typeof f.file === 'string');
    // A file a landed Optimize deleted or merged (removed) is not in the table: it shows under Removed by Optimize.
    const files = every.filter((f) => f.removed !== true), gone = every.filter((f) => f.removed === true);
    // A file selected that the snapshot no longer lists is no longer selected; with none selected, the bar's answers go.
    S.sel.forEach((x) => { if (!files.some((f) => f.file === x)) S.sel.delete(x); });
    if (!S.sel.size) { S.answers = null; if (asking('many')) S.ask = null; }
    const parts = [];
    if (obj(S.d.testMap)) parts.push(mapPart(S.d.testMap));
    const wasRecent = el.querySelector('.tests-results');
    if (wasRecent) S.recentOpen = wasRecent.open;
    if (!t) {
      parts.push(h('p', 'warn-note', 'Conveyor could not read the test figures of this project. Its pack does not read, or the build machine runs an older Conveyor.'));
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
    }
    const note = noteOf(el);
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
    still(root);
  }
  window.DASH_APP.part('tests-rows', function (shared) {
    ({ NEVER, PACK, CONTROL, MARKS, S, num, list, obj, one, pct, tests, settings, dk, shown, marks, look, timed, wallOnly,
      clockTook, COLS, say, button, row, section, setting, control, ENDED, SENDING, actions, mmss, hollowOf, proxyOf,
      proxySaid, hollowSaid, verdictOf, causesOf, causeSaid, failsOf, caughtOf, partsOf, notCard, kindSaid, casesSaid, plural,
      failKinds, mutDone, survivors, trimmed, mutState, mutCell, progress, send, verdictChip, reasonOf, box,
      rowAction, caseHit, shows, neverWhy, wholeCost, wallWhy, runBy, asking, stepButtons, judged, rowActions,
      actionsHead, selBar, optsOf, stateSaid, fixSaid, gainOf, helpedChip, numbersSaid, mutantsSaid, optRuns,
      optRunSaid, recent, removed, weakened, editsOf, editSaid, editIssue, editsSection, autofile, anyIssueUrl,
      draw } = shared);
    return { ISSUE_URL, drawSet, drawTests };
  });
})();
