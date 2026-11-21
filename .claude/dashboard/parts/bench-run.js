// SPDX-License-Identifier: Apache-2.0
// The Benchmarks tab's Live run, Task and Task map (#1177, the owner's mockup). Live run: for the run that goes now, the
// verdict (on time, on budget, the usage guard), 4 figures, the grid of tasks by arm with the step of the working cell,
// the score so far with its ranges, the event tail and Stop; with no run going, the last run. Task: one task across every
// arm (its verdict, each arm's result, minutes, hidden tests and note), the Conveyor card's steps as a timeline (width is
// time), its reviews folded, the task across the Conveyor arm's runs, its facts and its buttons. Task map: every task of the set
// (history's order) by repository, one square each, coloured by how many arms resolve it or by one arm's result. Part of
// panels/bench.js, which asks for it by name (DASH_APP.use) and gives it its kit (K).
(() => {
  'use strict';
  let K;
  const h = (...a) => K.h(...a);
  const cap = (s) => s.replace(/^./, (c) => c.toUpperCase());
  // A time with its date, in the Time and Date set in Customize, joined with "at" as the mockup does ("11/20/2026 at 3:04 PM").
  function stampOf(t) {
    const ms = Date.parse(t || '');
    return Number.isNaN(ms) ? K.B.ctx.when(t) : K.B.ctx.stamp(ms, { date: true }).replace(', ', ' at ');
  }

  // ---- Live run ----
  // What a run is planned to cost and take: each arm's usual sessions at its session's price, and its minutes, for the
  // tasks it runs (todo, by arm: a reused result costs nothing); null when an arm has no such figure.
  function estimate(cols, todo) {
    const per = cols.map((c) => K.obj((K.armsOf().find((a) => a.name === c.arm) || {}).perTask));
    if (per.some((p) => !p)) return { usd: null, min: null };
    const u = per.map((p, i) => (K.num(p.session) === null ? null : p.usual * p.session * todo[i]));
    return { usd: u.some((x) => x === null) ? null : K.sum(u), min: K.sum(per.map((p, i) => (K.num(p.minutes) || 0) * todo[i])) };
  }
  // The results an arm of the run reuses, which take no trial: [those it reused on the tasks it reached, those its
  // results key keeps of the tasks it has not reached (history's keys, by the pinned order)]. A run with --again (its
  // line's again) reuses none: it runs each task again.
  function reusedOf(data, c) {
    const order = K.list(K.hist().order), key = K.keysOf().find((x) => x.key === c.key), out = [0, 0];
    const kept = new Set(key && !(K.obj(data.run) && data.run.again === true) ? K.list(key.at).map((i) => order[i]) : []);
    K.list(data.tasks).filter(K.obj).forEach((t) => {
      const x = K.list(t.cells).find((y) => K.obj(y) && y.arm === c.arm);
      if (x && x.reused === true) out[0] += 1;
      else if (x && x.state === 'waiting' && kept.has(t.id)) out[1] += 1;
    });
    return out;
  }
  const guardOf = (c) => (K.armsOf().find((x) => x.name === c.arm) || {}).guard;
  // The mockup's sentence: the share of the week left on the tightest guard of the run's arms (r.weekLeft, kept with the run)
  // and what the run needs: the share its trials so far used (r.weekStart less r.weekLeft) over the trials it ran, times
  // the trials left on arms of that guard (both guards' arms, when they read one login: K.weekPool). A run from before the engine kept the share says it is not kept; so does a need
  // no trial has shown yet.
  function guardSaid(r, cols, data) {
    const g = K.obj(K.hist() && K.hist().guard) || {}, now = K.obj(r.weekLeft) || {}, start = K.obj(r.weekStart) || {};
    if (cols.some((c) => guardOf(c) && g[guardOf(c)] === true)) return 'The usage guard is reached: the run stops at the end of the task it is on.';
    const kinds = [...new Set(cols.map(guardOf).filter((k) => K.num(now[k]) !== null))].sort((a, b) => now[a] - now[b]);
    if (!kinds.length) return `The usage guard's week left: ${K.NOT_KEPT}.`;
    const k = kinds[0], mine = cols.filter((c) => K.weekPool(start, k).includes(guardOf(c))), ran = K.sum(mine.map((c) => K.num(c.ran) || 0)), used = K.num(start[k]) === null ? null : start[k] - now[k];
    const left = K.sum(mine.map((c) => Math.max(0, (K.num(r.n) || 0) - (K.num(c.done) || 0) - reusedOf(data, c)[1])));
    return `The usage guard has ${Math.round(now[k])}% of the week left; ${ran && used > 0 ? `this run needs about ${Math.round(used / ran * left)}% more` : `what this run needs is ${K.NOT_KEPT}`}.`;
  }
  // The run's pace on the trials it runs: the time so far over the trials done (a reused result is none) forecasts the
  // trials left, and the estimate is of those trials alone.
  function pace(r, cols, data) {
    const n = K.num(r.n) || 0, T = n * cols.length, done = K.sum(cols.map((c) => K.num(c.done) || 0)), re = cols.map((c) => reusedOf(data, c));
    const est = estimate(cols, re.map(([a, b]) => Math.max(0, n - a - b))), ran = Math.max(0, done - K.sum(re.map((x) => x[0]))), left = Math.max(0, T - done - K.sum(re.map((x) => x[1])));
    const start = Date.parse(r.started), took = Number.isFinite(start) ? Math.max(0, (K.B.ctx.now() - start) / 60000) : null, spent = K.costOf(r.cost).usd;
    const eta = !left ? 0 : ran && took !== null ? took / ran * left : null, frac = ran + left ? ran / (ran + left) : 1;
    return { n, T, done, est, took, spent, eta, onTime: est.min === null || took === null ? null : took <= est.min * frac * 1.25 + 5, onBudget: est.usd === null || spent === null ? null : spent <= est.usd * frac * 1.25 + 0.5 };
  }
  function liveVerdict(r, cols, p, data) {
    const words = [p.onTime === null ? null : p.onTime ? 'on time' : 'behind time', p.onBudget === null ? null : p.onBudget ? 'on budget' : 'over budget'].filter(Boolean);
    const v = `${words.length ? `${cap(words.join(' and '))}.` : 'No estimate to judge it by.'} ${p.done} of ${p.T} task runs done; about ${K.fmtMin(p.eta)} left.`;
    const tone = words.length && p.onTime !== false && p.onBudget !== false ? 'ok' : words.length ? 'warn' : 'quiet';
    return K.verdict(tone, `${r.id} · ${K.plural(p.n, 'task')} × ${K.plural(cols.length, 'arm')}`, v, `Spent ${K.usd(p.spent)} of the ${K.usd(p.est.usd)} estimate. ${guardSaid(r, cols, data)}`);
  }
  // A task run's "not run: <reason>" (swe_task) in the short words of the mockup's chip; the reason's own words when none fits.
  const CAUSES = [[/image/i, 'image fetch failed'], [/repository/i, 'repository fetch failed'], [/pack/i, 'task pack failed'], [/container/i, 'container failed'], [/grade|harness/i, 'grading failed'],
    [/patch/i, 'patch failed'], [/kept/i, 'saving the result failed']];
  function causesOf(data) {
    const why = K.list(data.tasks).filter(K.obj).flatMap((t) => K.list(t.cells)).filter((c) => K.said(c) === 'nr').map((c) => String(c.result).replace(/^not run:\s*/, ''));
    return Array.from(new Set(why.map((w) => (CAUSES.find(([re]) => re.test(w)) || [0, w])[1])));
  }
  function liveStats(cols, p, data) {
    const notRun = K.sum(cols.map((c) => K.num(c.notRun) || 0)), causes = causesOf(data), ends = p.eta === null ? null : new Date(K.B.ctx.now() + p.eta * 60000).toISOString();
    return K.grid('4', K.stat(`${p.done}/${p.T}`, 'Task runs done', K.bar(p.T ? p.done / p.T : 0)),
      K.stat(K.fmtMin(p.eta), 'Left, at this pace', K.chip(ends ? `ends about ${K.B.ctx.clock(ends)}` : 'no task done yet', 'quiet')),
      K.stat(K.usd(p.spent), 'Spent so far', K.chip(p.est.usd && p.spent !== null ? `${K.pct(p.spent / p.est.usd)} of the estimate` : 'no estimate', p.onBudget === false ? 'warn' : 'ok')),
      K.stat(String(notRun), 'Not run', K.chip(notRun ? `${causes.length ? causes.join(', ') : K.NOT_KEPT} · tried again next run` : 'none', notRun ? 'warn' : 'quiet')));
  }
  const CELL = { yes: ['bench-g-ok', ''], no: ['bench-g-bad', ''], nr: ['bench-g-nr', 'not run'] };
  function cellOf(c, r) {
    const k = K.said(c), d = h('div', 'bench-gc');
    if (CELL[k]) { d.classList.add(CELL[k][0]); d.textContent = CELL[k][1]; d.title = k === 'nr' ? String(c.result) : k === 'yes' ? 'Resolved' : 'Unresolved'; return d; }
    if (c && c.state === 'active') {
      const a = K.obj(r.active), s = a && Date.parse(a.start), m = Number.isFinite(s) ? Math.round((K.B.ctx.now() - s) / 60000) : null;
      d.classList.add('bench-g-work'); d.textContent = `${c.phase || 'Running'}${m === null ? '' : ` · ${m} min`}`; return d;
    }
    d.title = c && c.state === 'interrupted' ? 'Stop ended this work' : 'Waiting';
    return d;
  }
  function cellGrid(data, cols) {
    const g = h('div', 'bench-cellgrid'), r = data.run;
    g.style.gridTemplateColumns = `minmax(10rem, 16rem) repeat(${cols.length}, minmax(4rem, 1fr))`;
    g.append(h('div', 'bench-gh'), ...cols.map((c) => K.add(h('div', 'bench-gh'), [K.dot(c.s), K.colName(c)])));
    K.list(data.tasks).filter(K.obj).forEach((t) => {
      g.append(h('div', 'bench-gt mono', t.id));
      cols.forEach((c) => { const x = cellOf(K.list(t.cells).find((y) => K.obj(y) && y.arm === c.arm), r); x.dataset.task = t.id; x.dataset.arm = c.arm; g.append(x); });
    });
    return g;
  }
  const LEGEND = [['bench-g-ok', 'Resolved'], ['bench-g-bad', 'Unresolved'], ['bench-g-work', 'Working'], ['bench-g-wait', 'Waiting'], ['bench-g-nr', 'Not run (image)']];
  function scoreSoFar(data, cols) {
    const s = h('div'), cell = (t, c) => K.list(t.cells).find((y) => K.obj(y) && y.arm === c.arm);
    // A task an arm did not run (image, sandbox or grade failed) is no loss. It is left out for every arm, so all arms are
    // scored on the same tasks and the gap beside the noise note is a gap on those tasks.
    const shared = K.list(data.tasks).filter((t) => K.obj(t) && cols.every((c) => K.graded(cell(t, c))));
    cols.forEach((c) => {
      const k = shared.filter((t) => K.said(cell(t, c)) === 'yes').length, top = h('div', 'bench-row bench-space');
      top.append(K.add(h('span'), [K.dot(c.s), K.colName(c)]), h('b', null, `${k} of ${shared.length}`));
      s.append(K.add(h('div', 'bench-lrow'), [top, K.ciBar(k, shared.length, c.s)]));
    });
    s.append(K.note(`${K.plural(shared.length, 'task')}: only a difference of ${K.noiseSaid(shared.length)} or more shows.`));
    return s;
  }
  function tail(data, cols) {
    const ul = h('ul', 'bench-list bench-small bench-tail');
    K.list(data.tail).filter(K.obj).slice(-7).reverse().forEach((e) => {
      const c = cols.find((x) => x.arm === e.arm), ev = String(e.event || ''), li = h('li');
      li.append(h('span', 'bench-muted', K.B.ctx.clock(e.at)), ` ${e.arm ? (c ? K.colName(c) : String(e.arm)) : 'Run'}${e.task ? ' · ' : ''}`, e.task ? h('span', 'mono', String(e.task)) : '', ' · ',
        /^Resolved/.test(ev) ? K.chip(ev, 'ok') : /^Unresolved/.test(ev) ? K.chip(ev, 'bad') : ev);
      ul.append(li);
    });
    return ul;
  }
  function going(data) {
    const r = data.run, cols = K.paint(K.colsOf(r).map((c) => ({ ...c }))), p = pace(r, cols, data), leg = h('div', 'bench-legend');
    LEGEND.forEach(([c, l]) => leg.append(K.add(h('span'), [h('i', c), l])));
    const grid = K.add(K.box('Tasks by arm', 'One row a task, one column an arm. Green resolved, red unresolved, blue working now, grey waiting.'), [cellGrid(data, cols), leg]);
    const side = K.add(K.box('Score so far', 'Tasks that every arm finished.'), [scoreSoFar(data, cols), h('h3', 'bench-h', 'Events'), tail(data, cols),
      K.add(h('div', 'bench-row'), [K.stopRun(r.id, typeof r.stopping === 'string'), h('span', 'bench-note', 'Keeps the finished tasks.')]), K.saidAt(`stop-${r.id}`)]);
    return [liveVerdict(r, cols, p, data), liveStats(cols, p, data), K.grid('main', grid, side)];
  }
  function lastLine(r, The, word, took) {
    if (r.state === 'refused') return `${The} run did not start. It was asked for ${stampOf(r.started)}.`;
    if (!r.ended) return `${The} run is ${word}. It started ${stampOf(r.started)}.`;
    return `${The} run ended ${stampOf(r.ended)}, after ${took !== null && took < 90 ? K.plural(Math.round(took), 'minute') : K.fmtMin(took)}.`;
  }
  function lastRun(data) {
    const r = data.run, cols = K.paint(K.colsOf(r).map((c) => ({ ...c }))), n = K.num(r.n) || 0, tasks = K.list(data.tasks).filter(K.obj), took = K.elapsed(r), [word] = K.stateOf(r);
    const all = cols.filter((c) => c.resolved === n && n).length, ran = Math.max(0, ...cols.map((c) => K.num(c.done) || 0)), refused = r.state === 'refused';
    const res = n === 1 ? `${all === cols.length ? `All ${cols.length}` : `${all} of ${cols.length}`} resolved it.` : `${cols.map((c) => `${K.colName(c)} ${K.num(c.resolved) || 0} of ${n}`).join(', ')}.`;
    const v = lastLine(r, 'The last', word, took);
    // A cell with no result was never graded: it says why (not started, stopped), never unresolved.
    const one = (c) => {
      const x = tasks.length === 1 ? K.list(tasks[0].cells).find((y) => K.obj(y) && y.arm === c.arm) : null, k = K.said(x);
      if (!x) return `${K.num(c.resolved) || 0} of ${n} resolved`;
      return k === 'yes' ? K.chip('resolved', 'ok') : k === 'no' ? K.chip('unresolved', 'bad') : k === 'nr' ? K.chip('not run', 'warn') : K.chip(x.state === 'interrupted' ? 'stopped' : 'not started', 'quiet');
    };
    const s = K.box(r.id);
    s.append(K.table(['Arm', 'Result', ['Sessions', 'r'], ['Tokens', 'r'], ['Minutes', 'r'], ['Cost', 'r']], cols.map((c) => [K.armSaid({ s: c.s, label: K.colName(c) }), one(c),
      { v: K.num(c.sessions) === null ? K.NOT_KEPT : String(c.sessions), c: 'r' }, { v: K.kTok(c.tokens), c: 'r' }, { v: K.num(c.minutes) === null ? K.NOT_KEPT : String(c.minutes), c: 'r' },
      { v: K.costSaid(c.cost), c: 'r' }])));
    if (tasks.length) s.append(K.button(tasks.length === 1 ? 'Open the task' : 'Open its first task', '', 'open-task', `Open the task ${tasks[0].id}`, () => K.openTask(tasks[0].id)));
    // A run whose process ended with no end recorded (gone, no ended) says so; the mockup gives it no Stop.
    const gone = r.gone === true && !r.ended;
    const w = refused ? `The build machine refused it: ${typeof r.why === 'string' && r.why ? r.why : 'no reason was kept'}.`.replace(/\.\.$/, '.')
      : `It ran ${ran === n ? K.plural(n, 'task') : `${ran} of ${K.plural(n, 'task')}`} with ${K.plural(cols.length, 'arm')}. ${res}`;
    return [K.verdict(refused ? 'bad' : gone ? 'warn' : 'quiet', 'No run goes now', v, gone ? `${w} Its process ended with no end recorded.` : w), s];
  }
  function liveRun() {
    const top = K.answers('What is the run doing now, will it finish in time, and is it on budget?'), l = K.live();
    if (!K.hist()) return [top, K.reading('the runs')];
    const id = l && l.state === 'running' && typeof l.id === 'string' ? l.id : (K.runsOf().find((x) => x.state !== 'running') || {}).id;
    if (!id) return [top, K.verdict('quiet', 'No run goes now', K.NOT_KEPT)];
    const o = K.readRun(id);
    if (!o || !o.data) return [top, K.reading(`the run ${id}`, o)];
    return [top, ...(o.data.run.state === 'running' ? going(o.data) : lastRun(o.data))];
  }

  // ---- Task ----
  const repoOf = (id) => { const m = /^[^_]+__(.+)-\d+$/.exec(String(id)); return m ? m[1] : String(id).split('__')[0]; };
  // The arms on a task: the study's that ran it, else those of the first run read that has it (a task that flipped
  // between two older versions).
  function armsOn(id, st) {
    const mine = st.arms.filter((a) => a.cells.has(id));
    if (mine.length) return { arms: mine, title: st.titles.get(id) };
    for (const r of K.runsOf()) {
      const o = K.B.runs.get(`${K.B.repo}|${r.id}`), t = o && o.data && K.list(o.data.tasks).find((x) => K.obj(x) && x.id === id);
      if (t) return { arms: K.paint(K.colsOf(o.data.run).map((c) => K.armOf(r, c, o.data))).filter((a) => a.cells.has(id)), title: t.title };
    }
    return { arms: [], title: null };
  }
  // The mockup's Note column says only where a Conveyor arm went wrong.
  function noteOf(a, c) {
    return K.said(c) === 'no' && a.kind === 'conveyor' ? `went wrong at ${K.lossOf(c) || 'a step not kept'}` : '';
  }
  function eachArm(id, arms) {
    const s = K.box('Each arm on this task');
    s.append(K.table(['Arm', 'Result', ['Minutes', 'r'], 'Hidden tests', 'Note'], arms.map((a) => {
      const c = a.cells.get(id), k = K.said(c);
      return [K.armSaid(a), K.chip(k === 'yes' ? 'resolved' : k === 'no' ? 'unresolved' : k === 'nr' ? 'not run' : 'no result', k === 'yes' ? 'ok' : k === 'no' ? 'bad' : 'quiet'),
        { v: K.num(c.minutes) === null ? K.NOT_KEPT : String(Math.round(c.minutes)), c: 'r' }, { v: k === 'nr' ? '–' : K.testsSaid(c), c: 'bench-small' }, { v: noteOf(a, c), c: 'bench-small bench-muted' }];
    }), 'bench-arms'));
    return s;
  }
  const SWIM = { split: 'bench-s7', build: 'bench-s6', review: 'bench-s1', fix: 'bench-s2', rebase: 'bench-s2', test: 'bench-s3', landed: 'bench-s3', blocked: 'bench-fill-bad' };
  function stepLabel(s) {
    const t = K.obj(s.tokens), tok = t ? (K.num(t.claude) || 0) + (K.num(t.codex) || 0) : 0, more = [s.model, tok ? `${K.kTok(tok)} tok` : null].filter(Boolean);
    const word = s.step === 'landed' ? 'land' : s.step;
    return [word, s.step === 'review' || s.step === 'test' ? s.result : null, ...more].filter(Boolean).join(' · ');
  }
  // The card's steps as a timeline: each step as wide as the time from the step before it (the first from the task's
  // start, its minutes before the last step); equal widths when a step has no time kept.
  function swim(c) {
    const steps = K.list(c.steps).filter((s) => K.obj(s) && SWIM[s.step]), t = steps.map((s) => Date.parse(s.time)), d = h('div', 'bench-swim');
    const end = t[t.length - 1], start = Number.isFinite(end) && K.num(c.minutes) !== null ? end - c.minutes * 60000 : null, timed = t.every(Number.isFinite) && start !== null;
    const w = steps.map((s, i) => (timed ? Math.max(0, t[i] - (i ? t[i - 1] : Math.min(start, t[0]))) : 1)), total = K.sum(w) || 1;
    let x = 0;
    steps.forEach((s, i) => {
      const span = h('span', SWIM[s.step], stepLabel(s));
      span.style.left = `${x / total * 100}%`; span.style.width = `calc(${w[i] / total * 100}% - 2px)`; span.title = stepLabel(s); span.dataset.step = s.step;
      x += w[i]; d.append(span);
    });
    return { d, timed };
  }
  function cardSteps(id, arms) {
    const a = arms.find((x) => x.kind === 'conveyor' && K.list((x.cells.get(id) || {}).steps).length);
    if (!a) return [h('h3', 'bench-h', 'Conveyor\'s card, step by step'), h('p', 'bench-small bench-muted', K.NOT_KEPT)];
    const c = a.cells.get(id), sw = swim(c), reviews = K.list(c.steps).filter((s) => K.obj(s) && s.step === 'review');
    const f = K.fold(`review-${id}`, 'The review, in full');
    // The mockup shows the review's own text; a review of which none is kept, or no review, shows as not kept.
    (reviews.length ? reviews : [{}]).forEach((s) => f.append(h('p', 'bench-small', String(s.tail || s.reason || K.NOT_KEPT))));
    return [h('h3', 'bench-h', 'Conveyor\'s card, step by step'), h('p', 'bench-hsub', `From the real run ${(a.from.get(id) || a.run).id} (${a.label}). ${sw.timed ? 'Width is time.' : 'The step times are not kept: each step has the same width.'}`), sw.d, f];
  }
  // This task in each run of the Conveyor arm read (the newest 12 runs with one), oldest first.
  function overTime(id) {
    const row = h('div', 'bench-row bench-dots');
    K.runsOf().filter((r) => K.colsOf(r).some((c) => c.arm === 'conveyor')).slice(0, 12).reverse().forEach((r) => {
      const o = K.readRun(r.id), col = K.colsOf(r).find((c) => c.arm === 'conveyor'), c = o && o.data ? K.armOf(r, col, o.data).cells.get(id) : null;
      if (!K.graded(c)) return;
      const d = h('span', 'bench-vd'), yes = K.said(c) === 'yes';
      d.title = `${K.verOf(col)}: ${yes ? 'resolved' : 'unresolved'} (${r.id})`;
      d.append(h('span', `bench-dot bench-big ${yes ? 'bench-fill-ok' : 'bench-fill-bad'}`), h('span', 'bench-small bench-muted', K.verOf(col).replace(/^v/, '')));
      row.append(d);
    });
    if (!row.children.length) row.append(h('span', 'bench-muted', K.NOT_KEPT));
    return row;
  }
  // The task image's size, as the results keep it (imageBytes, in decimal units, the mockup's "4.1 GB, kept"); a result from
  // before the engine kept it has none.
  function imageSaid(arms, id) {
    const c = arms.map((a) => a.cells.get(id)).find((x) => K.obj(x) && K.num(x.imageBytes) !== null), b = c && c.imageBytes;
    return b === null || b === undefined ? K.NOT_KEPT : `${b >= 1e9 ? `${(b / 1e9).toFixed(1)} GB` : `${Math.round(b / 1e6)} MB`}, kept`;
  }
  function facts(id, arms, n) {
    const c = arms.map((a) => a.cells.get(id)).find((x) => K.obj(x && x.ref)), code = c && K.obj(c.ref.code), m = arms.length;
    return K.kv([['Repository', repoOf(id)], ['Difficulty', `${n >= 0.8 * m ? 'easy' : n >= 0.4 * m ? 'medium' : 'hard'} (resolved by ${n} of ${m} arms)`],
      ['Patch size', code ? `${K.plural(K.num(code.files) || 0, 'file')}, +${K.num(code.added) || 0} −${K.num(code.removed) || 0}` : K.NOT_KEPT],
      ['Task image', imageSaid(arms, id)]]);
  }
  // The task's tools, as the mockup has them. Open the patch shows the patch of the arm that the card's steps are read
  // from (the Conveyor arm, else the first arm with a kept patch). Open the logs shows each arm's kept log of the task
  // (the end of the loop's output: the engine gives the Board no more of it). Run this task again sends
  // `bench swe 1 --arm <arm>... --task <id> [--engine <commit>] --again`: that one task on the arms that reached it, on the
  // engine they ran, and --again keeps each result apart from the saved one. One run takes one engine, so the button is
  // off for arms that ran on two, or on one that is not known. Patch and logs stay open through a redraw.
  function toggle(label, act, key, open) {
    const b = K.button(label, '', act, label, () => { if (open) K.B.folds.delete(key); else K.B.folds.add(key); K.draw(); });
    b.setAttribute('aria-expanded', String(open));
    return b;
  }
  function again(id, all) {
    // An arm whose cell the run never reached (usage guard, Stop) did not run the task: it is not sent.
    const arms = all.filter((a) => !['not reached', 'waiting'].includes((a.cells.get(id) || {}).state));
    const names = Array.from(new Set(arms.map((a) => a.arm))), l = K.live(), inOrder = K.list(K.hist().order).includes(id);
    const eng = Array.from(new Set(arms.filter((a) => a.kind === 'conveyor').map((a) => (/^[0-9a-f]{40}$/.test(String((a.col || {}).engine)) ? a.col.engine : ''))));
    const why = !inOrder ? 'The task is not in the pinned order, so no run can reach it.'
      : !names.length ? 'No arm reached this task, so no arm has run it.'
      : eng.length > 1 || eng.includes('') ? 'The arms ran this task on more than one engine, or on one that is not known, and one run takes one engine.' : '';
    const b = K.button('Run this task again', '', 'run-again', 'Run this task again', () => K.send(`again-${id}`,
      ['run', '1', ...names.flatMap((a) => ['--arm', a]), '--task', id, ...(eng.length ? ['--engine', eng[0]] : []), '--again'],
      (t) => t.replace(/^conveyor: /, ''), () => K.readHist(true)));
    b.disabled = Boolean(why) || K.B.busy || Boolean(l && l.state === 'running');
    b.title = why || `Runs this task alone on ${K.plural(names.length, 'arm')}, and keeps the results apart.`;
    return b;
  }
  function tools(id, arms) {
    const pk = `patch-${id}`, lk = `logs-${id}`, row = h('div', 'bench-row bench-tools'), out = [row, K.saidAt(`again-${id}`)];
    const po = K.B.folds.has(pk), lo = K.B.folds.has(lk);
    row.append(toggle('Open the patch', 'open-patch', pk, po), toggle('Open the logs', 'open-logs', lk, lo), again(id, arms));
    if (po) {
      const a = arms.find((x) => x.kind === 'conveyor' && K.list((x.cells.get(id) || {}).steps).length) || arms.find((x) => Array.isArray(x.cells.get(id).patch)), p = a && a.cells.get(id).patch;
      const files = Array.isArray(p) ? (p.length ? p.map((x) => `${x.path} +${x.added} −${x.removed}`).join(', ') : 'empty') : K.NOT_KEPT;
      out.push(K.add(h('p', 'bench-small bench-patch'), a ? [h('b', null, a.label), `: ${files}`] : [K.NOT_KEPT]));
    }
    if (lo) {
      const logs = arms.filter((a) => typeof a.cells.get(id).log === 'string' && a.cells.get(id).log);
      if (!logs.length) out.push(h('p', 'bench-small bench-log', K.NOT_KEPT));
      logs.forEach((a) => out.push(K.add(h('div', 'bench-small bench-log'), [h('b', null, a.label), h('pre', null, a.cells.get(id).log)])));
    }
    return out.filter(Boolean);
  }
  function task() {
    const top = K.answers('What happened on one task, arm by arm, and is the task itself the problem?');
    if (!K.hist()) return [top, K.reading('the runs')];
    const st = K.studyOf();
    if (st.reading !== undefined) return [top, K.reading(`the run ${st.id}`, st.reading)];
    const id = K.B.task || st.shared[0] || st.ids[0];
    if (!id) return [top, K.verdict('quiet', 'Task', 'No task has a result yet.', 'Plan a run: each task it runs shows here.')];
    const { arms, title } = armsOn(id, st), n = arms.filter((a) => K.said(a.cells.get(id)) === 'yes').length, m = arms.length;
    const what = !m ? 'No arm read has this task.'
      : n === 0 ? 'No arm resolves it: look at the task before you blame an arm.' : n === m ? 'An easy task: it tells the arms apart only on cost and time.' : 'A task that tells the arms apart.';
    const v = K.verdict(n === m && m ? 'ok' : n === 0 ? 'bad' : 'warn', `${repoOf(id)} · ${id}`, title || id, `${n} of ${m} arms resolve it. ${what}`);
    if (!m) return [top, v];
    const left = K.add(eachArm(id, arms), cardSteps(id, arms));
    const right = K.add(K.box('This task over time', 'Each dot is one run of the Conveyor arm on this task.'), [overTime(id), facts(id, arms, n), ...tools(id, arms)]);
    return [top, v, K.grid('main', left, right)];
  }

  // ---- Task map ----
  function mapLegend(by) {
    const d = h('div', 'bench-legend'), items = by === 'all' ? [['bench-sq-all', 'Every arm'], ['bench-sq-some', 'Some arms'], ['bench-sq-none', 'No arm'], ['', 'Not run yet']] : [['bench-sq-all', 'Resolved'], ['bench-sq-none', 'Unresolved'], ['', 'Not run yet']];
    items.forEach(([c, l]) => d.append(K.add(h('span'), [h('i', `bench-sq ${c}`.trim()), l])));
    return d;
  }
  // A task's square: by how many of the arms that graded it resolve it, or by one arm's result; not run yet when none graded it.
  function square(id, st, by) {
    const arms = st.arms.filter((a) => K.graded(a.cells.get(id))), k = arms.filter((a) => K.said(a.cells.get(id)) === 'yes').length, one = st.arms.find((a) => a.arm === by);
    const ran = by === 'all' ? arms.length > 0 : one && K.graded(one.cells.get(id));
    if (!ran) { const s = h('span', 'bench-sq'); s.title = `${id}: not run yet`; s.dataset.t = id; return s; }
    const ok = by === 'all' ? k === arms.length : K.said(one.cells.get(id)) === 'yes', none = by === 'all' ? k === 0 : !ok;
    const b = h('button', `bench-sq ${ok ? 'bench-sq-all' : none ? 'bench-sq-none' : 'bench-sq-some'}`);
    if (!ok && !none) b.style.background = `color-mix(in srgb, var(--ok) ${Math.round(k / arms.length * 100)}%, var(--warn))`;
    b.type = 'button'; b.dataset.t = id; b.dataset.act = `sq-${id}`;
    b.title = `${id}${st.titles.get(id) ? `: ${st.titles.get(id)}` : ''}. ${k} of ${arms.length} arms resolve it. Click to open.`;
    b.setAttribute('aria-label', b.title);
    b.addEventListener('click', () => K.openTask(id));
    return b;
  }
  function groups(ids, st, by) {
    const by2 = new Map();
    ids.forEach((id) => { const r = repoOf(id); if (!by2.has(r)) by2.set(r, []); by2.get(r).push(id); });
    return Array.from(by2.entries()).sort((a, b) => b[1].length - a[1].length).map(([r, ts]) => {
      const g = h('div', 'bench-repo'), head = h('div', 'bench-small'), ran = ts.filter((id) => st.arms.some((a) => K.graded(a.cells.get(id)))).length;
      g.dataset.repo = r;
      head.append(h('b', null, r), ' ', h('span', 'bench-muted', `${K.plural(ts.length, 'task')} · ${ran} run`));
      g.append(head, K.add(h('div', 'bench-tmap'), ts.map((id) => square(id, st, by))));
      return g;
    });
  }
  function taskMap() {
    const size = K.setSize(), top = K.answers(`Where in the ${size} tasks does each arm win or lose, and which tasks have never run?`);
    if (!K.hist()) return [top, K.reading('the runs')];
    const st = K.studyOf();
    if (st.reading !== undefined) return [top, K.reading(`the run ${st.id}`, st.reading)];
    const order = K.list(K.hist().order).filter((x) => typeof x === 'string'), ids = order.length ? order : st.ids;
    const ran = st.ids.filter((id) => st.arms.some((a) => K.graded(a.cells.get(id)))), none = ran.filter((id) => !st.arms.some((a) => K.said(a.cells.get(id)) === 'yes'));
    const reps = new Map(); ids.forEach((id) => reps.set(repoOf(id), (reps.get(repoOf(id)) || 0) + 1));
    const [big, bn] = Array.from(reps.entries()).sort((a, b) => b[1] - a[1])[0] || ['', 0];
    const lean = big ? `${cap(big)} is ${K.pct(bn / ids.length)} of the set, so a run of the first ${K.plural(Math.max(st.n, 1), 'task')} leans on ${cap(big)}.` : '';
    const w = `${lean} The hard tasks are where a new version can gain the most.`.trim();
    if (!K.B.by || (K.B.by !== 'all' && !st.arms.some((a) => a.arm === K.B.by))) K.B.by = 'all';
    const sel = h('select', 'field');
    sel.dataset.act = 'map-by'; sel.setAttribute('aria-label', 'Colour by');
    [['all', 'How many arms resolve it'], ...st.arms.map((a) => [a.arm, a.label])].forEach(([v, l]) => { const o = h('option', null, l); o.value = v; sel.append(o); });
    sel.value = K.B.by; sel.addEventListener('change', () => { K.B.by = sel.value; K.draw(); });
    const head = K.add(h('div', 'bench-row bench-space'), [h('h3', 'bench-h', `All ${size} tasks of SWE-bench Verified, by repository`), K.add(h('span', 'bench-row bench-small'), [h('span', 'bench-muted', 'Colour by'), sel])]);
    const card = K.add(h('section', 'bench-box'), [head, mapLegend(K.B.by), ...groups(ids, st, K.B.by)]);
    return [top, K.verdict('warn', 'Coverage', `${ran.length} of ${size} tasks have results. ${none.length} of them no arm resolves.`, w), card];
  }
  window.DASH_APP.part('bench-run', function (shared) {
    K = shared;
    return { run: liveRun, task, map: taskMap };
  });
})();
