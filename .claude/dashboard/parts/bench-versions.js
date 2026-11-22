// SPDX-License-Identifier: Apache-2.0
// The Benchmarks tab's Versions and Compare (#1177, the owner's mockup). Versions: the verdict on the newest engine
// version of the Conveyor arm against the one before (versions in their release order, each change on the tasks both
// ran), its resolve rate by version with each 95% band and the Claude alone line, the table of versions with the change
// against the one before (noise or not) and the steps that changed, the drift watch (the belt's
// own cards before and after, each figure moved better, moved worse or in its usual range) and the tasks that flipped
// between the two newest versions, each with the first step apart and the commits that changed that step (`bench swe diff
// --json`, which the page asks for by itself). Compare: any two arms or versions, head to head on the tasks both graded: the
// verdict, the four boxes, the flipped tasks (each with the model's short reading, asked for by itself) and cost and time side by side. Part of
// panels/bench.js, which asks for it by name (DASH_APP.use) and gives it its kit (K).
(() => {
  'use strict';
  let K;
  const h = (...a) => K.h(...a);

  // ---- the drift watch (`conveyor.sh bench drift`, the snapshot's drift) ----
  // Each figure: its label, its key, what follows its number, and whether up is better. A figure moved when the two means are more
  // than two standard errors apart (each group's spread a card; Landed is the share of cards that landed).
  // The belt line says what a moved figure did: its words when it fell and when it rose, and what its number counts.
  const DRIFT = [['Landed', 'landed', '%', true, ['landed less', 'landed more'], ''], ['Tokens a card', 'tokens', 'k', false, ['used fewer tokens', 'used more tokens'], ' a card'],
    ['Minutes a card', 'minutes', ' min', false, ['took less time', 'took more time'], ' a card'], ['Reviews to land', 'reviews', '', false, ['needed fewer reviews', 'needed more reviews'], ' a card'],
    ['Fix rounds a card', 'fixes', '', false, ['needed fewer fix rounds', 'needed more fix rounds'], ' a card'], ['Minutes waited a card', 'waits', ' min', false, ['waited less', 'waited more'], ' a card']];
  function meanOf(g, k) {
    const n = K.num(k === 'reviews' ? g.landed : g.cards), v = k === 'landed' ? (n && K.num(g.landed) !== null ? g.landed / n : null) : K.num(g[k]);
    const sd = k === 'landed' ? (v === null ? null : Math.sqrt(v * (1 - v))) : K.num((K.obj(g.spread) || {})[k]);
    return { n, v, se: !n || sd === null ? null : sd / Math.sqrt(n) };
  }
  function driftRow([label, k, after, up, said, per], dr) {
    const b = meanOf(K.obj(dr.before) || {}, k), a = meanOf(K.obj(dr.after) || {}, k), small = K.list(dr.small).some((x) => x === 'before' || x === 'after');
    const ok = !small && b.v !== null && a.v !== null && b.se !== null && a.se !== null, se = ok ? Math.sqrt(b.se * b.se + a.se * a.se) : null;
    const isMoved = ok && Math.abs(a.v - b.v) > 2 * se, better = (a.v > b.v) === up;
    const word = !ok ? [K.NOT_KEPT, 'quiet'] : isMoved ? (better ? ['Moved, better', 'ok'] : ['Moved, worse', 'bad']) : ['In its usual range', 'quiet'];
    const fmt = (x) => (x.v === null ? K.NOT_KEPT : k === 'landed' ? `${Math.round(x.v * 100)}${after}` : k === 'tokens' ? `${Math.round(x.v / 1000)}${after}` : `${Math.round(x.v * 10) / 10}${after}`);
    return { label, k, word, b, a, se, fmt, isMoved, better, judged: ok, did: ok ? `${said[a.v > b.v ? 1 : 0]} (${fmt(a)} against ${fmt(b)}${per})` : '' };
  }
  function spark(r) {
    const el = K.svg('svg', { viewBox: '0 0 100 14', preserveAspectRatio: 'none', class: 'bench-svg bench-spark', 'aria-hidden': 'true' });
    if (r.b.v === null || r.a.v === null) return el;
    const s = r.se || 0, lo = Math.min(r.b.v, r.a.v) - 2 * s, hi = Math.max(r.b.v, r.a.v) + 2 * s, x = (v) => (hi > lo ? (v - lo) / (hi - lo) * 100 : 50);
    el.append(K.svg('rect', { x: x(r.b.v - 2 * s), y: 4, width: Math.max(0, x(r.b.v + 2 * s) - x(r.b.v - 2 * s)), height: 6, rx: 3, class: 'bench-usual' }),
      K.svg('line', { x1: x(r.b.v), x2: x(r.a.v), y1: 7, y2: 7, class: 'bench-gl' }), K.svg('circle', { cx: x(r.b.v), cy: 7, r: 3, class: 'bench-was' }), K.svg('circle', { cx: x(r.a.v), cy: 7, r: 3.5, class: 'bench-now' }));
    return el;
  }
  const sha = (g) => String((K.obj(g) || {}).engine || '').slice(0, 7);
  // A group of cards by the engine version it ended on (the version whose commit it is), else by the commit.
  function groupName(g) {
    const e = String((K.obj(g) || {}).engine || ''), v = e && K.list(K.benchOf().versions).find((x) => K.obj(x) && x.name !== 'main' && x.commit === e);
    return v ? v.name : `engine ${sha(g)}`;
  }
  function driftBox() {
    const dr = K.obj(K.B.d && K.B.d.drift);
    if (!dr) return null;
    const b = K.obj(dr.before) || {}, a = K.obj(dr.after) || {};
    const s = K.box('Drift watch: the belt\'s own cards', `Cards that ended on the engine commit before (${K.plural(K.num(b.cards) || 0, 'card')}) and on ${groupName(a)} (${K.plural(K.num(a.cards) || 0, 'card')}).`, 'bench-drift');
    DRIFT.map((x) => driftRow(x, dr)).forEach((r) => {
      const row = h('div', 'bench-drow'), top = h('div', 'bench-row bench-space'), line = h('div', 'bench-row bench-nowrap');
      row.dataset.figure = r.k;
      top.append(h('span', null, r.label), K.chip(r.word[0], r.word[1]));
      line.append(h('span', 'bench-muted bench-dv', r.fmt(r.b)), spark(r), h('b', 'bench-dv', r.fmt(r.a)));
      row.append(top, line);
      s.append(row);
    });
    s.append(K.note('A difference does not name its cause: the two groups built different issues.'));
    return s;
  }
  function driftLine() {
    const dr = K.obj(K.B.d && K.B.d.drift);
    if (!dr) return K.NOT_KEPT;
    const rows = DRIFT.map((x) => driftRow(x, dr)), moved = rows.filter((r) => r.isMoved);
    // The mockup has this line only for a figure that moved (it was judged); with none moved it shows "not kept". Its closing
    // sentence says the rest stayed in range only when every one of them was judged: a figure not judged stayed in no range.
    if (!moved.length) return K.NOT_KEPT;
    return `On the belt, cards on ${groupName(dr.after)} ${moved.map((r) => r.did).join(', ')}: ${moved.length === 1 ? 'that moved past its usual range' : 'those moved past their usual range'}.${rows.every((r) => r.judged) ? ' The other figures stayed in their usual range.' : ''}`;
  }

  // ---- Versions ----
  const soloRate = () => {
    const r = K.runsOf().find((x) => x.state !== 'running' && K.colsOf(x).some((c) => c.arm === 'solo' && (K.num(c.done) || 0) - (K.num(c.notRun) || 0) > 0));
    const c = r && K.colsOf(r).find((x) => x.arm === 'solo');
    return c ? c.resolved / (c.done - (K.num(c.notRun) || 0)) : null;
  };
  function trend(vs) {
    const W = 640, H = 220, P = { l: 40, r: 28, t: 10, b: 28 }, bands = vs.map((v) => K.wilson(v.k, v.n)), solo = soloRate();
    const ys = bands.flat().concat(solo === null ? [] : [solo]), lo = Math.max(0, Math.floor(Math.min(...ys) * 10) / 10), hi = Math.min(1, Math.ceil(Math.max(...ys) * 10) / 10);
    const x = (i) => P.l + i / Math.max(vs.length - 1, 1) * (W - P.l - P.r), y = (r) => H - P.b - (r - lo) / Math.max(hi - lo, 0.1) * (H - P.t - P.b);
    const el = K.svg('svg', { viewBox: `0 0 ${W} ${H}`, class: 'bench-svg bench-trend', role: 'img', 'aria-label': 'Resolve rate by engine version' });
    for (let i = 0; i <= 4; i += 1) { const r = lo + (hi - lo) * i / 4; el.append(K.svg('line', { class: 'bench-gl', x1: P.l, x2: W - P.r, y1: y(r), y2: y(r) }), K.svg('text', { x: P.l - 6, y: y(r) + 4, 'text-anchor': 'end' }, K.pct(r))); }
    const up = bands.map((q, i) => `${x(i)},${y(q[1])}`), down = bands.map((q, i) => `${x(i)},${y(q[0])}`).reverse();
    el.append(K.svg('path', { d: `M${up.concat(down).join(' L')} Z`, class: 'bench-band bench-s1' }), K.svg('polyline', { class: 'bench-line bench-s1', points: vs.map((v, i) => `${x(i)},${y(v.k / v.n)}`).join(' ') }));
    vs.forEach((v, i) => el.append(K.svg('circle', { cx: x(i), cy: y(v.k / v.n), r: 5, class: 'bench-s1 bench-vdot' }), K.svg('text', { x: x(i), y: H - 8, 'text-anchor': 'middle' }, v.v)));
    if (solo !== null) el.append(K.svg('line', { x1: x(0), x2: x(vs.length - 1), y1: y(solo), y2: y(solo), class: 'bench-solo bench-s4' }), K.svg('text', { x: x(vs.length - 1), y: y(solo) - 6, 'text-anchor': 'end' }, 'Claude alone'));
    return el;
  }
  // The diff (`bench swe diff --json`) of two results keys, once read. It is asked for once for a pair while the Board is
  // open (K.B.diffs): each reading in it is a model call for a task with none saved, so a redraw uses what it has, and a
  // diff that failed (no answer, or a flipped task with no reading: `diff` saves none then) stays missing until the Board
  // starts again, or, for Compare, until the pickers change (change: K.B.cmp.n, which Compare passes) once more. Versions
  // asks for one at a time (alone): each answer draws the page, which asks for the next. Nothing here draws before the answer.
  const parse = (text) => { try { return K.obj(JSON.parse(text)) || { flipped: [] }; } catch { return { flipped: [] }; } };
  const diffOf = (a, b) => { const e = K.B.diffs.get(`${a}|${b}`); return e ? K.obj(e.data) : null; };
  const missing = (e) => !e.data || K.list(e.data.flipped).some((f) => !K.obj(f) || !f.reading);
  function wantDiff(a, b, alone, change) {
    const D = K.B.diffs, k = `${a}|${b}`, old = D.get(k);
    if (old && (old.busy || change === undefined || old.change === change || !missing(old))) return;
    if (alone && Array.from(D.values()).some((x) => x.busy)) return;
    const e = { busy: true, data: old ? old.data : null, change };
    D.set(k, e);
    K.ask(['diff', a, b, '--json']).then((text) => { e.busy = false; if (text !== null) e.data = parse(text); if (K.B.diffs === D) K.draw(); });
  }
  const pairOf = (p, v) => diffOf(p.col.key, v.col.key);
  // The steps whose engine files changed between a version and the one before, a task flipped or not (the diff's steps);
  // a dash when the diff is missing or could not map the engine's files to its steps.
  function stepsChanged(p, v) {
    const d = pairOf(p, v), st = d && Array.isArray(d.steps) ? d.steps.filter((x) => typeof x === 'string') : [];
    return st.length ? st.join(', ') : '—';
  }
  // The day a version's first run started, without its year, in the order of the Date set in Customize, with the
  // mockup's hyphen ("11-09" or "09-11").
  function dayOf(t) {
    const ms = Date.parse(t || '');
    return Number.isNaN(ms) ? K.NOT_KEPT : K.B.ctx.stamp(ms, { date: true, time: false }).slice(0, 5).replace('/', '-');
  }
  function versionRow(v, i, vs) {
    const p = vs[i - 1], m = p ? K.moved(p, v) : null;
    const c = !p ? h('span', 'bench-muted', 'first') : !m.shared ? h('span', 'bench-muted', K.NOT_KEPT)
      : K.chip(`${m.pts >= 0 ? '+' : ''}${m.pts} pts${m.sig ? (m.d > 0 ? ', better' : ', worse') : ', noise'}`, m.sig ? (m.d > 0 ? 'ok' : 'bad') : 'quiet');
    if (m && m.shared) c.title =`On the ${K.plural(m.shared, 'task')} both versions ran: ${m.kv} against ${m.kp}`;
    return [{ v: v.v, c: 'mono' }, dayOf(v.date), { v: String(v.n), c: 'r' }, { v: String(v.k), c: 'r' }, c, { v: p ? stepsChanged(p, v) : '—', c: 'bench-muted' }];
  }
  function trendBox(vs) {
    const s = K.box('Resolve rate by engine version', 'The shaded band is the 95% range of each version\'s rate. Bands that overlap are not told apart.');
    s.append(trend(vs), K.table(['Version', 'Date', ['Tasks', 'r'], ['Resolved', 'r'], 'Against the version before', 'Changed steps'], vs.map(versionRow), 'bench-versions'));
    return s;
  }
  function versionVerdict(vs) {
    const last = vs[vs.length - 1], prev = vs[vs.length - 2], m = K.moved(prev, last);
    if (!m.shared) return K.verdict('quiet', `${last.v} against ${prev.v}`, K.NOT_KEPT, driftLine());
    const of = m.shared === last.n && m.shared === prev.n ? `of ${m.shared}` : `of the ${m.shared} tasks both ran`;
    // The mockup's one word is "No regression."; a regression past the noise has no word of its own, the sentence and the red tone say it.
    const word = m.sig && m.d < 0 ? '' : 'No regression. ';
    const v = `${word}${last.v} resolves ${m.kv} ${of}, ${Math.abs(m.d)} ${m.d >= 0 ? 'more' : 'fewer'} than ${prev.v}: ${m.sig ? 'past' : 'inside'} the noise of ${K.plural(K.noised(m.shared), 'task')}.`;
    return K.verdict(m.sig && m.d < 0 ? 'bad' : 'ok', `${last.v} against ${prev.v}`, v, driftLine());
  }
  // The tasks that flipped between two versions, read from their runs.
  function flipsOf(prev, last) {
    const A = prev.arm, Z = last.arm;
    return Array.from(Z.cells.keys()).filter((id) => K.graded(A.cells.get(id)) && K.graded(Z.cells.get(id)) && K.said(A.cells.get(id)) !== K.said(Z.cells.get(id)))
      .map((id) => ({ id, now: K.said(Z.cells.get(id)) === 'yes', apart: K.apart(A.cells.get(id).steps, Z.cells.get(id).steps) }));
  }
  // A flipped task's entry in a diff, when the diff read the results the page shows: a run with --again shows its own
  // result of a task (again/<run id>: the cell's again), and the diff reads only the kept one, another trial even when
  // both resolved it (a reading or a first step apart of it would be of a result the page does not show). a and b: the
  // two sides' cells, in the diff's order.
  function flipIn(d, id, a, b) {
    const f = d && K.list(d.flipped).find((x) => K.obj(x) && x.task === id);
    const apart = (c) => Boolean(K.obj(c) && c.again), is = (side, c) => K.obj(side) && side.resolved === (K.said(c) === 'yes');
    return { f: f || null, same: !apart(a) && !apart(b) && (!f || (is(f.a, a) && is(f.b, b))) };
  }
  // The diff's commits or reading of a task that is not of the result the page shows (a run again) are not kept for it.
  function commitsOf(prev, last, id) {
    const d = pairOf(prev, last);
    if (!d) return K.NOT_KEPT;
    const { f, same } = flipIn(d, id, prev.arm.cells.get(id), last.arm.cells.get(id));
    if (!same) return h('span', 'bench-muted', K.NOT_KEPT);
    const changes = K.list(f && f.changes);
    return changes.length ? changes.map((c) => `${c.commit} ${c.title}`).join(' · ') : K.NOT_KEPT;
  }
  function flipsBox(vs) {
    const prev = vs[vs.length - 2], last = vs[vs.length - 1], fl = flipsOf(prev, last);
    const s = K.box(`Tasks that flipped from ${prev.v} to ${last.v}`, 'Each with the first step where the runs went apart and the engine commits that changed that step.');
    vs.slice(1).map((v, i) => [vs[i], v]).reverse().forEach(([p, v]) => wantDiff(p.col.key, v.col.key, true));
    s.append(K.table(['Task', 'Now', 'First step apart', 'Commits that changed it'], fl.map((f) => [{ v: f.id, c: 'mono' }, K.chip(f.now ? 'now resolved' : 'now unresolved', f.now ? 'ok' : 'bad'), f.apart, { v: commitsOf(prev, last, f.id), c: 'bench-small' }]),
      'bench-flips', (tr, i) => { tr.dataset.task = fl[i].id; tr.classList.add('bench-click'); tr.addEventListener('click', () => K.openTask(fl[i].id)); }));
    return s;
  }
  function willShow() {
    const s = K.box('What this page will show'), ul = h('ul', 'bench-list');
    ['The resolve rate of each version with its 95% range, so a dip that is noise looks like noise.', 'The belt\'s own figures (landed, tokens, minutes, waits) before and after each engine commit, judged against their usual range.',
      'Each task that flipped, with the commits that changed the step where it flipped.'].forEach((t) => ul.append(h('li', null, t)));
    s.append(ul);
    return s;
  }
  function versions() {
    const Q = 'Did a change to the engine make Conveyor better or worse?';
    if (!K.hist()) return [K.answers(Q), K.reading('the runs')];
    const vs = K.versionsOf(), wait = vs.find((e) => !e.arm);
    if (wait) return [K.answers(Q), K.reading(`the run ${wait.wait.id}`, wait.wait.o)];
    if (vs.length < 2) {
      const v = vs[0], drift = driftBox();
      const w = drift ? 'The drift watch needs no benchmark run: it reads the cards your belt builds.' : ['The drift watch needs no benchmark run: it reads the cards your belt builds. Today it has not run. Run ', h('span', 'mono', 'conveyor.sh bench drift'), ' on the build machine, or let the Board run it after each release.'];
      return [K.answers(Q), K.verdict('quiet', 'Versions with results', v ? `Only ${v.v} has a result, on ${K.plural(v.n, 'task')}. No version can be compared yet.` : K.NOT_KEPT, w), drift, willShow()].filter(Boolean);
    }
    return [K.answers(Q, 'Two sources: benchmark runs of each version, and the cards the belt builds anyway (the drift watch, at no cost).'), versionVerdict(vs),
      K.grid('main', trendBox(vs), driftBox() || K.box('Drift watch: the belt\'s own cards', K.NOT_KEPT)), flipsBox(vs)];
  }

  // ---- Compare ----
  // The sides Compare offers: each arm of the study, then each older version of each of its Conveyor arms (the one named
  // conveyor has the ids ver:<version>; another, as conveyor-codex-claude, ver:<arm>:<version>).
  function optionsOf(st) {
    const out = st.arms.map((a) => ({ id: `arm:${a.arm}`, label: a.label, run: a.run, col: a.col, side: a }));
    st.arms.filter((a) => a.kind === 'conveyor').forEach((a) => {
      const k = a.arm === 'conveyor' ? '' : `${a.arm}:`;
      K.versionsOf(a.arm).filter((v) => v.v !== K.verOf(a.col)).reverse().forEach((v) => out.push({ id: `ver:${k}${v.v}`, label: K.colName(v.col), run: v.run, col: v.col, side: null, ver: v, s: a.s }));
    });
    return out;
  }
  // A version's side: its runs' cells (versionsOf), in the colour of the Conveyor arm it belongs to (o.s); null while they are read.
  const sideOf = (o) => o.side || (o.ver.arm ? { ...o.ver.arm, s: o.s, label: o.label } : null);
  function picker(which, opts) {
    const sel = h('select', 'field');
    sel.dataset.act = `cmp-${which}`; sel.setAttribute('aria-label', which === 'a' ? 'The first arm' : 'The second arm');
    opts.forEach((o) => { const x = h('option', null, o.label); x.value = o.id; sel.append(x); });
    sel.value = K.B.cmp[which];
    sel.addEventListener('change', () => { K.B.cmp[which] = sel.value; K.B.cmp.n += 1; K.draw(); });
    return sel;
  }
  function defaults(opts) {
    const c = K.B.cmp, has = (id) => opts.some((o) => o.id === id);
    if (!has(c.a)) c.a = (opts.find((o) => o.col.arm === 'conveyor') || opts[0]).id;
    if (!has(c.b) || c.b === c.a) c.b = (opts.find((o) => o.id === 'arm:solo' && o.id !== c.a) || opts.find((o) => o.id !== c.a)).id;
  }
  // Where a flipped task went apart: the first step apart when both are Conveyor arms; else where the Conveyor arm lost
  // it or saved it; else the one session of each agent.
  function saveOf(c) {
    const steps = K.list(c.steps).filter(K.obj);
    return steps.some((s) => s.step === 'test' && s.result === 'fail') ? 'test step' : steps.some((s) => s.step === 'review' && s.result !== 'GO') ? 'review' : 'build';
  }
  function whereApart(id, win, lose) {
    const w = win.cells.get(id), l = lose.cells.get(id);
    if (K.list(w.steps).length && K.list(l.steps).length) return K.apart(w.steps, l.steps);
    if (lose.kind === 'conveyor') return `lost at ${K.lossOf(l) || 'a step not kept'}`;
    return win.kind === 'conveyor' ? `saved at ${saveOf(w)}` : 'the one session';
  }
  // The model's reading of a flipped task, only when the diff read the results the page shows (flipIn).
  function readingOf(id, A, Bs) {
    const d = diffOf(A.key, Bs.key), { f, same } = flipIn(d, id, A.cells.get(id), Bs.cells.get(id));
    return !d || !same || !(f && f.reading) ? h('span', 'bench-muted', K.NOT_KEPT) : f.reading;
  }
  function boxOf(label, v, tone) { const d = h('div', `bench-four bench-four-${tone}`); d.append(h('div', 'bench-four-n', String(v)), h('div', 'bench-small', label)); return d; }
  function pair(label, a, b, fmt, A, Bs) {
    const d = h('div', 'bench-pair'), m = Math.max(K.num(a) || 0, K.num(b) || 0) || 1;
    // Each bar is named by the first 2 words of its arm's label, the whole label when those would name both alike.
    const short = (s) => s.label.split(' ').slice(0, 2).join(' '), same = short(A) === short(Bs), name = (s) => (same ? s.label : short(s));
    d.append(h('div', 'bench-muted bench-small', label));
    [[A, a, 'bench-fill'], [Bs, b, 'bench-fill-warn']].forEach(([s, v, cls]) => d.append(K.add(h('div', 'bench-row bench-nowrap'), [h('span', 'bench-muted bench-pl', name(s)), K.bar((K.num(v) || 0) / m, cls), h('b', 'bench-pv', fmt(v))])));
    return d;
  }
  function costBox(A, Bs, fa, fb, n, d) {
    const s = K.box('Cost and time', `For the ${n} shared tasks.`), per = (f) => (f.cost === null || !f.k ? null : f.cost / f.k), x1 = (v) => (K.num(v) === null ? K.NOT_KEPT : v.toFixed(1));
    s.append(pair('Cost', fa.cost, fb.cost, K.usd, A, Bs), pair('Cost per resolved task', per(fa), per(fb), K.usd, A, Bs), pair('Machine time', fa.wall, fb.wall, K.fmtMin, A, Bs),
      pair('Tokens', fa.tokens, fb.tokens, K.kTok, A, Bs), pair('Sessions a task', fa.sessions, fb.sessions, x1, A, Bs),
      K.callout(d > 0 && fa.cost !== null && fb.cost !== null ? `Each extra fix of ${A.label} costs ${K.usd(Math.max(0, (fa.cost - fb.cost) / d))}.` : `${A.label} buys no extra fixes here.`));
    return s;
  }
  function headToHead(A, Bs, ids) {
    const n = ids.length, yes = (s, id) => K.said(s.cells.get(id)) === 'yes', both = ids.filter((id) => yes(A, id) && yes(Bs, id)).length;
    const onlyA = ids.filter((id) => yes(A, id) && !yes(Bs, id)), onlyB = ids.filter((id) => !yes(A, id) && yes(Bs, id));
    return { n, both, onlyA, onlyB, none: n - both - onlyA.length - onlyB.length, d: onlyA.length - onlyB.length };
  }
  function cmpVerdict(A, Bs, x, fa, fb) {
    const { n, d } = x, [win, lose] = d > 0 ? [fa, fb] : [fb, fa], N = K.noiseSaid(n), sig = K.told(d, n), size = K.setSize(), need = d ? Math.ceil(2 / ((Math.abs(d) / n) ** 2)) : Infinity;
    if (sig) return K.verdict(d > 0 ? 'ok' : 'bad', 'Head to head', `${d > 0 ? A.label : Bs.label} is better: it resolves ${Math.abs(d)} more of ${n}. That is past the noise of ${N}.`,
      `It costs ${K.usd(win.cost)} against ${K.usd(lose.cost)} for the ${n} tasks, and takes ${K.fmtMin(win.wall)} against ${K.fmtMin(lose.wall)}.`);
    const w = `If the gap held, about ${Math.min(need, size)} tasks would show it${need > size ? ', more than the set has, so treat the two as equal' : ''}.`;
    return K.verdict('quiet', 'Head to head', `Not told apart yet. The difference is ${K.plural(Math.abs(d), 'task')}, under the noise of ${N}.`, w);
  }
  function differ(A, Bs, x) {
    const s = K.box('Where they differ', 'Every task falls in one box. Only the two "only" boxes move the score.'), fl = x.onlyA.map((id) => [id, A, Bs]).concat(x.onlyB.map((id) => [id, Bs, A])).slice(0, 12);
    if (fl.length) wantDiff(A.key, Bs.key, false, K.B.cmp.n);
    s.append(K.add(h('div', 'bench-grid bench-g-2 bench-fours'), [boxOf('Both resolve', x.both, 'ok'), boxOf(`Only ${A.label}`, x.onlyA.length, 'info'), boxOf(`Only ${Bs.label}`, x.onlyB.length, 'warn'), boxOf('Neither', x.none, 'quiet')]),
      h('h3', 'bench-h', 'The flipped tasks'),
      K.table(['Task', 'Resolved by', 'First step apart', 'Why, in short'], fl.map(([id, w, l]) => [{ v: id, c: 'mono' }, K.armSaid(w), whereApart(id, w, l), { v: readingOf(id, A, Bs), c: 'bench-small bench-muted' }]), 'bench-flips',
        (tr, i) => { tr.dataset.task = fl[i][0]; tr.classList.add('bench-click'); tr.addEventListener('click', () => K.openTask(fl[i][0])); }),
      K.note('"Why, in short" is one model call\'s reading of the facts of both runs, and is labelled as such on the Board.'));
    return s;
  }
  function fewCompare(A, Bs, ids, fa, fb) {
    const n = ids.length, one = n === 1 ? ids[0] : null, s = K.box(one ? `Cost and time on ${one}` : 'Cost and time on the shared tasks'), x = headToHead(A, Bs, ids);
    const v = n === 1 && x.both ? `${A.label} and ${Bs.label} both resolved the one task they share.` : K.NOT_KEPT;
    const took = (f) => `${K.plural(Math.round(K.sum(f.cs.map((c) => K.num(c.sessions) || 0))), 'session')}, ${K.kTok(f.tokens)} tokens and ${f.wall === null ? 'minutes not kept' : `${f.wall} minutes`}`;
    // With no graded task in common, nothing tells the arms apart: no cost-and-time sentence of 0 sessions each.
    const w = !n ? K.NOT_KEPT : `${x.d ? '' : 'There is no flipped task to explain. '}The only difference is cost and time: ${A.label} took ${took(fa)}; ${Bs.label} took ${took(fb)}.`;
    s.append(pair('Tokens', fa.tokens, fb.tokens, K.kTok, A, Bs), pair('Minutes', fa.wall, fb.wall, (m) => (K.num(m) === null ? K.NOT_KEPT : `${m} min`), A, Bs),
      pair('Sessions', fa.sessions, fb.sessions, (m) => (K.num(m) === null ? K.NOT_KEPT : String(Math.round(m * 10) / 10)), A, Bs));
    return [K.verdict('quiet', 'Head to head', v, w), s];
  }
  function compare() {
    const top = K.answers('Is one arm or version better than another, on the same tasks, and why?');
    if (!K.hist()) return [top, K.reading('the runs')];
    const st = K.studyOf();
    if (st.reading !== undefined) return [top, K.reading(`the run ${st.id}`, st.reading)];
    const opts = optionsOf(st);
    if (opts.length < 2) return [top, K.verdict('quiet', 'Head to head', K.NOT_KEPT)];
    defaults(opts);
    const oa = opts.find((o) => o.id === K.B.cmp.a), ob = opts.find((o) => o.id === K.B.cmp.b), A = sideOf(oa), Bs = sideOf(ob);
    if (!A || !Bs) return [top, K.verdict('quiet', 'Head to head', K.NOT_KEPT)];
    const ids = Array.from(A.cells.keys()).filter((id) => K.graded(A.cells.get(id)) && K.graded(Bs.cells.get(id))), fa = K.figsOf(A, ids), fb = K.figsOf(Bs, ids);
    const pick = K.add(h('div', 'bench-row bench-pickers'), [picker('a', opts), h('span', 'bench-muted', 'against'), picker('b', opts), h('span', 'bench-muted bench-small', `on the ${K.plural(ids.length, 'task')} both ran`)]);
    if (ids.length < 3) return [top, pick, ...fewCompare(A, Bs, ids, fa, fb)];
    const x = headToHead(A, Bs, ids);
    return [top, pick, cmpVerdict(A, Bs, x, fa, fb), K.grid('main', differ(A, Bs, x), costBox(A, Bs, fa, fb, x.n, x.d))];
  }
  window.DASH_APP.part('bench-versions', function (shared) {
    K = shared;
    return { versions, compare };
  });
})();
