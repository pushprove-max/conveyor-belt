// SPDX-License-Identifier: Apache-2.0
// The Benchmarks tab's Versions and Compare (#1177, the owner's mockup). Versions: the verdict on the newest engine
// version of the Conveyor arm against the one before (versions in their release order, each change on the tasks both
// ran), its resolve rate by version with each 95% band and the Claude alone line, the table of versions with the change
// against the one before (noise or not) and, once read, the steps that changed, the drift watch (the belt's
// own cards before and after, each figure moved better, moved worse or in its usual range) and the tasks that flipped
// between the two newest versions, each with the first step apart and, once read (`bench swe diff --json`), the commits
// that changed that step. Compare: any two arms or versions, head to head on the tasks both graded: the verdict, the four
// boxes, the flipped tasks (and, once read, the model's short reading of each) and cost and time side by side. Part of
// panels/bench.js, which asks for it by name (DASH_APP.use) and gives it its kit (K).
(() => {
  'use strict';
  let K;
  const h = (...a) => K.h(...a);

  // ---- the drift watch (`conveyor.sh bench drift`, the snapshot's drift) ----
  // Each figure: its label, its key, what follows its number, and whether up is better. A figure moved when the two means are more
  // than two standard errors apart (each group's spread a card; Landed is the share of cards that landed).
  const DRIFT = [['Landed', 'landed', '%', true], ['Tokens a card', 'tokens', 'k', false], ['Minutes a card', 'minutes', ' min', false], ['Reviews to land', 'reviews', '', false],
    ['Fix rounds a card', 'fixes', '', false], ['Minutes waited a card', 'waits', ' min', false]];
  function meanOf(g, k) {
    const n = K.num(k === 'reviews' ? g.landed : g.cards), v = k === 'landed' ? (n && K.num(g.landed) !== null ? g.landed / n : null) : K.num(g[k]);
    const sd = k === 'landed' ? (v === null ? null : Math.sqrt(v * (1 - v))) : K.num((K.obj(g.spread) || {})[k]);
    return { n, v, se: !n || sd === null ? null : sd / Math.sqrt(n) };
  }
  function driftRow([label, k, after, up], dr) {
    const b = meanOf(K.obj(dr.before) || {}, k), a = meanOf(K.obj(dr.after) || {}, k), small = K.list(dr.small).some((x) => x === 'before' || x === 'after');
    const ok = !small && b.v !== null && a.v !== null && b.se !== null && a.se !== null, se = ok ? Math.sqrt(b.se * b.se + a.se * a.se) : null;
    const isMoved = ok && Math.abs(a.v - b.v) > 2 * se, better = (a.v > b.v) === up;
    const word = small ? ['Too few cards', 'quiet'] : !ok ? ['Not read', 'quiet'] : isMoved ? (better ? ['Moved, better', 'ok'] : ['Moved, worse', 'bad']) : ['In its usual range', 'quiet'];
    const fmt = (x) => (x.v === null ? '–' : k === 'landed' ? `${Math.round(x.v * 100)}${after}` : k === 'tokens' ? `${Math.round(x.v / 1000)}${after}` : `${Math.round(x.v * 10) / 10}${after}`);
    return { label, k, word, b, a, se, fmt, isMoved, better, judged: ok };
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
  function driftBox() {
    const dr = K.obj(K.B.d && K.B.d.drift);
    if (!dr) return null;
    const b = K.obj(dr.before) || {}, a = K.obj(dr.after) || {};
    const s = K.box('Drift watch: the belt\'s own cards', `Cards that ended on the engine commit before (engine ${sha(b)}, ${K.plural(K.num(b.cards) || 0, 'card')}) and on engine ${sha(a)} (${K.plural(K.num(a.cards) || 0, 'card')}).`, 'bench-drift');
    DRIFT.map((x) => driftRow(x, dr)).forEach((r) => {
      const row = h('div', 'bench-drow'), top = h('div', 'bench-row bench-space'), line = h('div', 'bench-row bench-nowrap');
      row.dataset.figure = r.k;
      top.append(h('span', null, r.label), K.chip(r.word[0], r.word[1]));
      line.append(h('span', 'bench-muted bench-dv', r.fmt(r.b)), spark(r), h('b', 'bench-dv', r.fmt(r.a)));
      row.append(top, line);
      s.append(row);
    });
    if (K.list(dr.small).length) s.append(K.note('A group of fewer than 5 cards is too small to mean anything: no figure is judged.'));
    s.append(K.note('A difference does not name its cause: the two groups built different issues.'));
    return s;
  }
  function driftLine() {
    const dr = K.obj(K.B.d && K.B.d.drift);
    if (!dr) return 'The drift watch has not run.';
    const rows = DRIFT.map((x) => driftRow(x, dr)), moved = rows.filter((r) => r.isMoved), judged = rows.filter((r) => r.judged);
    // A figure not judged (too few cards, or not read) stayed in no range: the line says so, never "every figure".
    if (!judged.length) return K.list(dr.small).length ? 'On the belt, a group has fewer than 5 cards: no figure is judged yet.' : 'On the belt, no figure could be read.';
    if (!moved.length) return judged.length === rows.length ? 'On the belt, every figure stayed in its usual range.' : `On the belt, ${judged.length} of ${rows.length} figures could be judged, and each stayed in its usual range.`;
    const each = moved.map((r) => `${r.label.toLowerCase()} moved ${r.better ? 'better' : 'worse'} (${r.fmt(r.a)} against ${r.fmt(r.b)})`).join(', ');
    return `On the belt, cards on engine ${sha(dr.after)}: ${each}, past the usual range. The other figures ${judged.length === rows.length ? '' : 'judged '}stayed in their usual range.`;
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
  // The diff (`bench swe diff --json`) of a version and the one before it, once read; Read the commits reads each.
  const pairKey = (p, v) => `${p.col.key}|${v.col.key}`;
  const pairOf = (p, v) => K.obj(K.B.flips.pairs.get(pairKey(p, v)));
  // The steps whose engine files changed between a version and the one before, a task flipped or not (the diff's
  // steps); not known when the diff could not map the engine's files to its steps.
  function stepsChanged(p, v) {
    const d = pairOf(p, v);
    if (!d) return 'not read';
    if (!Array.isArray(d.steps)) return 'not known';
    const st = d.steps.filter((x) => typeof x === 'string');
    return st.length ? st.join(', ') : 'none';
  }
  function versionRow(v, i, vs) {
    const p = vs[i - 1], m = p ? K.moved(p, v) : null;
    const c = !p ? h('span', 'bench-muted', 'first') : !m.shared ? h('span', 'bench-muted', 'no task both ran')
      : m.few ? K.chip(`${m.d >= 0 ? '+' : ''}${m.d} of ${m.shared}, too few tasks`, 'quiet') : K.chip(`${m.pts >= 0 ? '+' : ''}${m.pts} pts${m.sig ? (m.d > 0 ? ', better' : ', worse') : ', noise'}`, m.sig ? (m.d > 0 ? 'ok' : 'bad') : 'quiet');
    if (m && m.shared) c.title =`On the ${K.plural(m.shared, 'task')} both versions ran: ${m.kv} against ${m.kp}`;
    return [{ v: v.v, c: 'mono' }, v.date ? K.B.ctx.when(v.date) : 'not read', { v: String(v.n), c: 'r' }, { v: String(v.k), c: 'r' }, c, { v: p ? stepsChanged(p, v) : '—', c: 'bench-muted' }];
  }
  function trendBox(vs) {
    const s = K.box('Resolve rate by engine version', 'The shaded band is the 95% range of each version\'s rate. Bands that overlap are not told apart.');
    s.append(trend(vs), K.table(['Version', 'Date', ['Tasks', 'r'], ['Resolved', 'r'], 'Against the version before', 'Changed steps'], vs.map(versionRow), 'bench-versions'));
    return s;
  }
  function versionVerdict(vs) {
    const last = vs[vs.length - 1], prev = vs[vs.length - 2], m = K.moved(prev, last);
    if (!m.shared) return K.verdict('quiet', `${last.v} against ${prev.v}`, `Not told yet: ${last.v} and ${prev.v} ran no task in common.`, driftLine());
    if (m.few) {
      return K.verdict('quiet', `${last.v} against ${prev.v}`, `Nothing can be told yet from ${K.plural(m.shared, 'task')} both ran: ${last.v} resolves ${m.kv}, ${prev.v} ${m.kp}.`, driftLine());
    }
    const of = m.shared === last.n && m.shared === prev.n ? `of ${m.shared}` : `of the ${m.shared} tasks both ran`;
    const word = m.sig ? (m.d > 0 ? 'Better.' : 'A regression.') : m.d >= 0 ? 'No regression.' : 'No regression shown.';
    const v = `${word} ${last.v} resolves ${m.kv} ${of}, ${Math.abs(m.d)} ${m.d >= 0 ? 'more' : 'fewer'} than ${prev.v}: ${m.sig ? 'past' : 'inside'} the noise of ${K.noiseSaid(m.shared)} tasks.`;
    return K.verdict(m.sig && m.d < 0 ? 'bad' : 'ok', `${last.v} against ${prev.v}`, v, driftLine());
  }
  // The tasks that flipped between two versions, read from their runs.
  function flipsOf(prev, last) {
    const A = prev.arm, Z = last.arm;
    return Array.from(Z.cells.keys()).filter((id) => K.graded(A.cells.get(id)) && K.graded(Z.cells.get(id)) && K.said(A.cells.get(id)) !== K.said(Z.cells.get(id)))
      .map((id) => ({ id, now: K.said(Z.cells.get(id)) === 'yes', apart: K.apart(A.cells.get(id).steps, Z.cells.get(id).steps) }));
  }
  const parse = (text) => { try { return K.obj(JSON.parse(text)) || { flipped: [] }; } catch { return { flipped: [] }; } };
  function readDiff(state, a, b, key) {
    const ask = `${key}-${state.n += 1}`;
    state.ask = ask; state.data = null;
    K.send(ask, ['diff', a, b, '--json'], () => 'Read.', (text) => { if (state.ask === ask) state.data = parse(text); });
  }
  // Read the commits: the diff of each version and the one before it, the newest pair first, one request at a time.
  function readCommits(vs) {
    const F = K.B.flips, run = F.run += 1, todo = vs.slice(1).map((v, i) => [vs[i], v]).reverse();
    F.pairs = new Map();
    const next = () => {
      const pr = todo.shift();
      if (!pr || F.run !== run) return;
      const ask = `flips-${F.n += 1}`;
      F.ask = ask;
      K.send(ask, ['diff', pr[0].col.key, pr[1].col.key, '--json'], () => 'Read.', (text) => { if (F.run !== run) return; F.pairs.set(pairKey(pr[0], pr[1]), parse(text)); next(); });
    };
    next();
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
  const OTHER = 'not of the result shown (a run again)';
  function commitsOf(prev, last, id) {
    const d = pairOf(prev, last);
    if (!d) return 'not read';
    const { f, same } = flipIn(d, id, prev.arm.cells.get(id), last.arm.cells.get(id));
    if (!same) return h('span', 'bench-muted', OTHER);
    return !f || f.changes === null || f.changes === undefined ? 'none to show' : K.list(f.changes).length ? K.list(f.changes).map((c) => `${c.commit} ${c.title}`).join(' · ') : 'none';
  }
  function flipsBox(vs) {
    const prev = vs[vs.length - 2], last = vs[vs.length - 1], fl = flipsOf(prev, last);
    const s = K.box(`Tasks that flipped from ${prev.v} to ${last.v}`, 'Each with the first step where the runs went apart and the engine commits that changed that step.');
    const read = K.button('Read the commits', 'btn-quiet btn-sm', 'read-commits', 'Read the commits of each version against the one before it', () => readCommits(vs));
    s.append(K.add(h('div', 'bench-row'), [read, h('span', 'bench-note', 'It reads the engine\'s history on the build machine for each version against the one before it, and one model call writes a short reading of each flipped task.'),
      K.B.flips.ask ? K.saidAt(K.B.flips.ask) : '']));
    if (!fl.length) { s.append(K.note('No task flipped.')); return s; }
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
      const w = drift ? 'The drift watch needs no benchmark run: it reads the cards your belt builds.' : ['The drift watch needs no benchmark run: it reads the cards your belt builds. Today it has not run. Run ', h('span', 'mono', 'conveyor.sh bench drift'), ' on the build machine.'];
      return [K.answers(Q), K.verdict('quiet', 'Versions with results', `${v ? `Only ${v.v} has a result, on ${K.plural(v.n, 'task')}.` : 'No version has a result yet.'} No version can be compared yet.`, w), drift, willShow()].filter(Boolean);
    }
    return [K.answers(Q, 'Two sources: benchmark runs of each version, and the cards the belt builds anyway (the drift watch, at no cost).'), versionVerdict(vs),
      K.grid('main', trendBox(vs), driftBox() || K.add(K.box('Drift watch: the belt\'s own cards'), K.note('The drift watch has not run. Run conveyor.sh bench drift on the build machine.'))), flipsBox(vs)];
  }

  // ---- Compare ----
  // The sides Compare offers: each arm of the study, then each older version of the Conveyor arm.
  function optionsOf(st) {
    const out = st.arms.map((a) => ({ id: `arm:${a.arm}`, label: a.label, run: a.run, col: a.col, side: a })), have = new Set(st.arms.filter((a) => a.arm === 'conveyor').map((a) => K.verOf(a.col)));
    K.versionsOf().filter((v) => !have.has(v.v)).reverse().forEach((v) => out.push({ id: `ver:${v.v}`, label: K.colName(v.col), run: v.run, col: v.col, side: null, ver: v }));
    return out;
  }
  // A version's side: its runs' cells (versionsOf), in the Conveyor arm's colour; null while they are read.
  const sideOf = (o) => o.side || (o.ver.arm ? { ...o.ver.arm, s: 1, label: o.label } : null);
  function picker(which, opts) {
    const sel = h('select', 'field');
    sel.dataset.act = `cmp-${which}`; sel.setAttribute('aria-label', which === 'a' ? 'The first arm' : 'The second arm');
    opts.forEach((o) => { const x = h('option', null, o.label); x.value = o.id; sel.append(x); });
    sel.value = K.B.cmp[which];
    sel.addEventListener('change', () => { K.B.cmp[which] = sel.value; K.B.cmp.data = null; K.B.cmp.ask = null; K.draw(); });
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
    const d = K.obj(K.B.cmp.data), { f, same } = flipIn(d, id, A.cells.get(id), Bs.cells.get(id));
    return !d ? h('span', 'bench-muted', 'not read') : !same ? h('span', 'bench-muted', OTHER) : f && f.reading ? f.reading : h('span', 'bench-muted', 'no reading');
  }
  function boxOf(label, v, tone) { const d = h('div', `bench-four bench-four-${tone}`); d.append(h('div', 'bench-four-n', String(v)), h('div', 'bench-small', label)); return d; }
  function pair(label, a, b, fmt, A, Bs) {
    const d = h('div', 'bench-pair'), m = Math.max(K.num(a) || 0, K.num(b) || 0) || 1;
    d.append(h('div', 'bench-muted bench-small', label));
    [[A, a, 'bench-fill'], [Bs, b, 'bench-fill-warn']].forEach(([s, v, cls]) => d.append(K.add(h('div', 'bench-row bench-nowrap'), [h('span', 'bench-muted bench-pl', s.label), K.bar((K.num(v) || 0) / m, cls), h('b', 'bench-pv', fmt(v))])));
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
    const { n, d } = x, N = K.noiseSaid(n), sig = K.told(d, n), size = K.setSize(), need = d ? Math.ceil(2 / ((Math.abs(d) / n) ** 2)) : null;
    if (sig) return K.verdict(d > 0 ? 'ok' : 'bad', 'Head to head', `${d > 0 ? A.label : Bs.label} is better: it resolves ${Math.abs(d)} more of ${n}. That is past the noise of ${N}.`,
      `It costs ${K.usd(fa.cost)} against ${K.usd(fb.cost)} for the ${n} tasks, and takes ${K.fmtMin(fa.wall)} against ${K.fmtMin(fb.wall)}.`);
    const w = need === null ? 'They resolve the same number of these tasks.' : `If the gap held, about ${Math.min(need, size)} tasks would show it${need > size ? ', more than the set has, so treat the two as equal' : ''}.`;
    return K.verdict('quiet', 'Head to head', `Not told apart yet. The difference is ${K.plural(Math.abs(d), 'task')}, under the noise of ${N}.`, w);
  }
  function differ(A, Bs, x) {
    const s = K.box('Where they differ', 'Every task falls in one box. Only the two "only" boxes move the score.'), fl = x.onlyA.map((id) => [id, A, Bs]).concat(x.onlyB.map((id) => [id, Bs, A]));
    s.append(K.add(h('div', 'bench-grid bench-g-2 bench-fours'), [boxOf('Both resolve', x.both, 'ok'), boxOf(`Only ${A.label}`, x.onlyA.length, 'info'), boxOf(`Only ${Bs.label}`, x.onlyB.length, 'warn'), boxOf('Neither', x.none, 'quiet')]),
      h('h3', 'bench-h', 'The flipped tasks'),
      K.add(h('div', 'bench-row'), [K.button('Ask for the readings', 'btn-quiet btn-sm', 'cmp-read', 'Ask for the model\'s reading of each flipped task', () => readDiff(K.B.cmp, A.key, Bs.key, 'compare')), K.B.cmp.ask ? K.saidAt(K.B.cmp.ask) : '']),
      K.table(['Task', 'Resolved by', 'First step apart', 'Why, in short'], fl.map(([id, w, l]) => [{ v: id, c: 'mono' }, K.armSaid(w), whereApart(id, w, l), { v: readingOf(id, A, Bs), c: 'bench-small bench-muted' }]), 'bench-flips',
        (tr, i) => { tr.dataset.task = fl[i][0]; tr.classList.add('bench-click'); tr.addEventListener('click', () => K.openTask(fl[i][0])); }),
      K.note('"Why, in short" is one model call\'s reading of the facts of both runs: the model\'s reading, not a fact.'));
    return s;
  }
  function fewCompare(A, Bs, ids, fa, fb) {
    const n = ids.length, one = n === 1 ? ids[0] : null, s = K.box(one ? `Cost and time on ${one}` : 'Cost and time on the shared tasks'), x = headToHead(A, Bs, ids);
    const v = !n ? `${A.label} and ${Bs.label} share no task they both graded.` : n === 1 && x.both ? `${A.label} and ${Bs.label} both resolved the one task they share.`
      : `On ${K.plural(n, 'task')}: ${A.label} resolved ${fa.k}, ${Bs.label} ${fb.k}.`;
    const took = (f) => `${K.plural(Math.round(K.sum(f.cs.map((c) => K.num(c.sessions) || 0))), 'session')}, ${K.kTok(f.tokens)} tokens and ${f.wall === null ? 'minutes not kept' : `${f.wall} minutes`}`;
    const w = `Nothing can be told yet from ${K.plural(n, 'task')}. ${x.d ? 'A flipped task is in the table of the full page once there are 3 shared tasks or more.' : 'There is no flipped task to explain.'} The only difference is cost and time: ${A.label} took ${took(fa)}; ${Bs.label} took ${took(fb)}.`;
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
    if (opts.length < 2) return [top, K.verdict('quiet', 'Head to head', 'Compare needs two arms with results.', 'Plan a run with two arms or more.')];
    defaults(opts);
    const oa = opts.find((o) => o.id === K.B.cmp.a), ob = opts.find((o) => o.id === K.B.cmp.b), A = sideOf(oa), Bs = sideOf(ob);
    if (!A || !Bs) return [top, K.note('Reading the runs of the two sides…')];
    const ids = Array.from(A.cells.keys()).filter((id) => K.graded(A.cells.get(id)) && K.graded(Bs.cells.get(id))), fa = K.figsOf(A, ids), fb = K.figsOf(Bs, ids);
    const pick = K.add(h('div', 'bench-row bench-pickers'), [picker('a', opts), h('span', 'bench-muted', 'against'), picker('b', opts), h('span', 'bench-muted bench-small', `on the ${K.plural(ids.length, 'task')} both ran`)]);
    const tools = K.runTools(Array.from(new Set(A.runs.concat(Bs.runs))));
    if (ids.length < 3) return [top, pick, ...fewCompare(A, Bs, ids, fa, fb), tools];
    const x = headToHead(A, Bs, ids);
    return [top, pick, cmpVerdict(A, Bs, x, fa, fb), K.grid('main', differ(A, Bs, x), costBox(A, Bs, fa, fb, x.n, x.d)), tools];
  }
  window.DASH_APP.part('bench-versions', function (shared) {
    K = shared;
    return { versions, compare };
  });
})();
