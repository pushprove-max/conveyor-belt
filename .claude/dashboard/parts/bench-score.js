// SPDX-License-Identifier: Apache-2.0
// The Benchmarks tab's Scoreboard (#1177, the owner's mockup): each arm's ended runs on its results key (the study, studyOf),
// judged on the tasks every arm graded. With 3 shared tasks or more: the verdict against the noise of sqrt(2n) tasks, 4
// figures, the leaderboard in tiers, the value chart, Hidden tests, Patch quality, Lines of code, Effort and steadiness,
// where Conveyor loses tasks, what the arms agree on and the next run to make. With fewer, nothing can be told, and the
// page shows what the runs have (the mockup's "Your data now"). Either way the run history is folded at the foot, with
// Archive, Restore and Delete of the runs ticked. Part of panels/bench.js, which asks for it by name (DASH_APP.use) and
// gives it its kit (K); boot.js loads it before the panels.
(() => {
  'use strict';
  let K;
  const Q = 'Which way of building a change resolves the most real issues, at what cost, and how sure can you be?';
  const h = (...a) => K.h(...a);

  // ---- one arm's figures on the shared tasks ----
  const cleanOf = (c) => { const m = K.obj(c.measures); return m && typeof m.clean === 'boolean' ? m.clean : c.class === 'nopatch' ? false : null; };
  const boolOf = (k) => (c) => { const m = K.obj(c.measures); return m && typeof m[k] === 'boolean' ? m[k] : null; };
  const count = (xs, f) => (xs === null ? null : xs.filter(f).length);
  function rowOf(a, ids) {
    const f = K.figsOf(a, ids), cls = K.kept(f.cs, (c) => c.class || null), fired = K.kept(f.cs, (c) => (typeof c.fired === 'boolean' ? c.fired : null));
    return { a, f, k: f.k, n: f.n, cls, clean: count(K.kept(f.cs, cleanOf), Boolean), fired: fired && fired.filter(Boolean).length / Math.max(fired.length, 1),
      of: (k) => count(cls, (x) => x === k), perResolved: f.cost === null || !f.k ? null : f.cost / f.k, perTask: f.cost === null || !f.n ? null : f.cost / f.n };
  }
  // The arms by resolved, each in its tier: an arm closer to the leader of its tier than the noise shares that tier.
  function tiers(rows, n) {
    let lead = null, t = 0;
    rows.forEach((r) => { if (!lead || lead.k - r.k >= K.noise(n)) { t += 1; lead = r; } r.tier = t; });
    return rows;
  }
  // The Conveyor arm the page names "Conveyor": the conveyor arm itself, else the first arm of its kind.
  const convOf = (rows) => rows.find((r) => r.a.arm === 'conveyor') || rows.find((r) => r.a.kind === 'conveyor');
  // The board: the rows sorted, the leader, the next arm, the arm it is judged against (Claude alone, else the last)
  // and the first Conveyor arm.
  function boardOf(st) {
    const rows = tiers(st.arms.map((a) => rowOf(a, st.shared)).sort((x, y) => y.k - x.k), st.n);
    const best = rows[0], ref = rows.find((r) => r.a.arm === 'solo' && r !== best) || rows[rows.length - 1];
    return { st, n: st.n, rows, best, second: rows[1] || null, ref, conv: convOf(rows) || best };
  }

  // ---- the verdict and the four figures ----
  const gapSaid = (gap, ref) => (gap ? `${gap} more than ${ref}` : `as many as ${ref}`);
  function cheapLine(L) {
    const priced = L.rows.filter((r) => r.perResolved !== null), cheap = priced.sort((x, y) => x.perResolved - y.perResolved)[0], b = L.best;
    if (!cheap) return '';
    if (cheap === b) return ` ${b.a.label} is also the cheapest per resolved task, at ${K.usd(b.perResolved)}.`;
    const more = b.perResolved === null ? '' : ` ${b.a.label} costs ${K.usd(b.perResolved)} per resolved task, ${(b.perResolved / cheap.perResolved).toFixed(1)} times as much, for ${b.k - cheap.k} more fixes.`;
    return ` Per resolved task, ${cheap.a.label} is the cheapest at ${K.usd(cheap.perResolved)}.${more}`;
  }
  function verdictOf(L) {
    const { n, best, second, ref } = L, N = K.noiseSaid(n), gap = best.k - ref.k;
    if (!second) return K.verdict('quiet', `Verdict on the ${n} shared tasks`, K.NOT_KEPT);
    const v = `${best.a.label} resolves ${best.k} of ${n}, ${gapSaid(gap, ref.a.label)}. ${K.told(gap, n) ? `That gap is larger than the noise (${N} tasks), so it is real.` : `That gap is inside the noise (${N} tasks): not proven yet.`}`;
    const tie = best.k - second.k < K.noise(n) ? `It ties with ${second.a.label} (${second.k} of ${n}): the difference is inside the noise.` : `It beats the next arm, ${second.a.label} (${second.k} of ${n}), by more than the noise.`;
    const clean = best.clean === null || ref.clean === null || best.of('broke') === null || ref.of('broke') === null ? ''
      : ` ${best.clean} of its ${best.k} fixes are clean, against ${ref.clean} of ${ref.k} for ${ref.a.label}, and its patches broke other tests in ${best.of('broke')} tasks, against ${ref.of('broke')}.`;
    return K.verdict(K.told(gap, n) ? 'ok' : 'quiet', `Verdict on the ${n} shared tasks`, v, `${tie}${cheapLine(L)}${clean}`);
  }
  // The leader's change on its version before (the Conveyor arm's versions), in tasks, on the tasks both versions ran.
  function lastMove(r) {
    if (r.a.arm !== 'conveyor') return '';
    const vs = K.versionsOf(), i = vs.findIndex((v) => v.v === K.verOf(r.a.col)), m = i < 1 ? null : K.moved(vs[i - 1], vs[i]);
    if (!m || !m.shared) return '';
    return K.chip(`${m.d >= 0 ? '+' : ''}${m.d} on ${vs[i - 1].v}, ${m.sig ? 'past' : 'inside'} the noise`, m.sig ? (m.d > 0 ? 'ok' : 'bad') : 'ok');
  }
  function stats(L) {
    const { n, best, conv, st } = L, name = conv.a.col.label || conv.a.label;
    const none = st.shared.filter((id) => !st.arms.some((a) => K.said(a.cells.get(id)) === 'yes')).length;
    const link = K.button('See them on the task map', 'btn-link', 'to-map', 'See them on the task map', () => K.go('map'));
    return K.grid('4', K.stat(`${best.k}/${n}`, `Best resolved (${best.a.label})`, lastMove(best)),
      K.stat(K.usd(conv.perResolved), `${name}: cost per resolved task`, K.chip('list prices, all sessions', 'quiet')),
      K.stat(K.fmtMin(conv.f.minutes), `${name}: minutes a task`, K.chip('median, this machine', 'quiet')), K.stat(String(none), 'Tasks no arm resolves', link));
  }

  // ---- the leaderboard and the value chart ----
  // A click on an arm opens Compare: the Conveyor arm against it (against the next arm, for the Conveyor arm itself).
  function toCompare(L, r) {
    const a = L.conv === r ? L.rows.find((x) => x !== r) || r : r;
    K.B.cmp.a = `arm:${L.conv.a.arm}`; K.B.cmp.b = `arm:${a.a.arm}`; K.B.cmp.n += 1;
    K.go('compare');
  }
  const sub = (v, s) => [v, s ? h('div', 'bench-tie', s) : ''];
  function leaderRow(r, i, L) {
    const prev = L.rows[i - 1], broke = r.of('broke'), arm = K.armSaid(r.a);
    if (r.a.kind === 'conveyor') arm.append(' ', K.chip('Conveyor', 'info'));
    return [{ v: sub(String(r.tier), prev && prev.tier === r.tier ? 'tie' : ''), c: 'bench-rank' }, arm, { v: [h('b', null, String(r.k)), `/${r.n}`], c: 'r' }, K.ciBar(r.k, r.n, r.a.s),
      { v: r.clean === null ? K.NOT_KEPT : String(r.clean), c: 'r' }, { v: broke === null ? K.NOT_KEPT : broke >= 0.15 * r.n ? K.chip(String(broke), 'bad') : String(broke), c: 'r' },
      { v: sub(K.usd(r.perResolved), r.f.est ? 'from tokens' : ''), c: 'r' }, { v: r.f.minutes === null ? K.NOT_KEPT : String(Math.round(r.f.minutes)), c: 'r' },
      { v: r.fired === null ? K.NOT_KEPT : r.fired < 0.95 ? K.chip(K.pct(r.fired), 'warn') : K.pct(r.fired), c: 'r' }];
  }
  function leaderboard(L) {
    const s = K.box('Leaderboard', `Arms in the same tier are not told apart by ${L.n} tasks. The bar is the 95% range of the resolve rate.`);
    s.append(K.table(['Tier', 'Arm', ['Resolved', 'r'], 'Resolve rate, 95% range', ['Clean', 'r', 'Resolved, lint clean, at most twice the size of the reference fix, and no file the reference fix leaves alone'],
      ['Broke tests', 'r', 'Tasks where the patch broke tests that passed before'], ['$ / resolved', 'r'], ['Min', 'r'], ['Fired', 'r']], L.rows.map((r, i) => leaderRow(r, i, L)), 'bench-leader',
    (tr, i) => { const r = L.rows[i]; tr.dataset.cmp = r.a.arm; tr.classList.add('bench-click'); tr.addEventListener('click', () => toCompare(L, r)); }),
    K.note(`Click an arm to compare it with Conveyor. "From tokens": the agent arm reports tokens but no usage by model, so its cost is its tokens at the model's list price, an estimate. An arm that did not fire fails the task.`));
    return s;
  }
  // The value chart: each arm's resolve rate (with its 95% range) against its cost a task, and the line of the arms
  // that no other arm beats on both. An arm with no price is left out, and the note says so.
  function axes(pts, n) {
    const ys = pts.flatMap((p) => K.wilson(p.r.k, n)), lo = Math.max(0, Math.floor(Math.min(...ys) * 10) / 10), hi = Math.min(1, Math.ceil(Math.max(...ys) * 10) / 10);
    // The cost axis has 4 steps of a round size (1, 2, 2.5 or 5 times a power of ten), so each tick's label is its exact price.
    const raw = Math.max(...pts.map((p) => p.c)) * 1.15 || 1, mag = 10 ** Math.floor(Math.log10(raw / 4)), step = [1, 2, 2.5, 5, 10].map((m) => m * mag).find((m) => m * 4 >= raw), mx = step * 4;
    const W = 420, H = 260, P = { l: 40, r: 12, t: 10, b: 32 };
    return { W, H, P, lo, hi, mx, step, x: (c) => P.l + c / mx * (W - P.l - P.r), y: (r) => H - P.b - (r - lo) / Math.max(hi - lo, 0.1) * (H - P.t - P.b) };
  }
  function chart(L) {
    const pts = L.rows.filter((r) => r.perTask !== null).map((r) => ({ r, c: r.perTask, v: r.k / Math.max(r.n, 1) })).sort((p, q) => p.c - q.c);
    if (!pts.length) return h('p', 'bench-muted', K.NOT_KEPT);
    const A = axes(pts, L.n), el = K.svg('svg', { viewBox: `0 0 ${A.W} ${A.H}`, class: 'bench-svg', role: 'img', 'aria-label': 'Resolve rate against cost a task' });
    for (let i = 0; i <= 4; i += 1) { const r = A.lo + (A.hi - A.lo) * i / 4; el.append(K.svg('line', { class: 'bench-gl', x1: A.P.l, x2: A.W - A.P.r, y1: A.y(r), y2: A.y(r) }), K.svg('text', { x: A.P.l - 6, y: A.y(r) + 4, 'text-anchor': 'end' }, K.pct(r))); }
    for (let i = 0; i <= 4; i += 1) { const c = A.step * i; el.append(K.svg('text', { x: A.x(c), y: A.H - A.P.b + 16, 'text-anchor': 'middle' }, `$${Number(c.toFixed(6))}`)); }
    el.append(K.svg('text', { x: (A.W + A.P.l) / 2, y: A.H - 2, 'text-anchor': 'middle' }, 'cost a task'));
    let top = -1;
    const front = pts.filter((p) => { if (p.v <= top) return false; top = p.v; return true; });
    el.append(K.svg('polyline', { class: 'bench-front', points: front.map((p) => `${A.x(p.c)},${A.y(p.v)}`).join(' ') }));
    pts.forEach((p) => el.append(point(p, A, L.n)));
    return el;
  }
  function point(p, A, n) {
    const [lo, hi] = K.wilson(p.r.k, n), g = K.svg('g', { class: `bench-pt bench-s${p.r.a.s}`, 'data-arm': p.r.a.arm });
    g.append(K.svg('line', { x1: A.x(p.c), x2: A.x(p.c), y1: A.y(lo), y2: A.y(hi), class: 'bench-range' }), K.svg('circle', { cx: A.x(p.c), cy: A.y(p.v), r: 7 }),
      K.svg('title', {}, `${p.r.a.label}: ${p.r.k} of ${n} resolved · ${K.usd(p.c)} a task${p.r.f.est ? ' (from tokens)' : ''} · ${K.usd(p.r.perResolved)} per resolved task`));
    return g;
  }
  function value(L) {
    const s = K.box('Value: resolve rate against cost', 'Up is better, left is cheaper. The line joins the arms that no other arm beats on both.'), c = L.conv, ref = L.ref, gap = c.k - ref.k;
    s.append(chart(L));
    if (c !== ref && gap > 0 && c.f.cost !== null && ref.f.cost !== null) s.append(K.callout(`${c.a.label} buys its ${gap} extra fixes at ${K.usd((c.f.cost - ref.f.cost) / gap)} each over ${ref.a.label}.`));
    return s;
  }

  // ---- hidden tests and patch quality ----
  const CLASSES = [['resolved', 'Resolved'], ['broke', 'Fixed, but broke other tests'], ['partial', 'Partial fix'], ['nofix', 'No fix'], ['nopatch', 'No patch (blocked, empty or did not fire)']];
  function classBar(r) {
    const row = h('div', 'bench-crow'), head = h('div', 'bench-row bench-space'), strip = h('div', 'bench-classes');
    head.append(K.armSaid(r.a), h('span', 'bench-muted', r.cls === null ? `${r.k} resolved · hidden tests ${K.NOT_KEPT}` : `${r.k} resolved · ${r.of('broke')} broke tests`));
    CLASSES.forEach(([k, l]) => { const v = r.of(k); if (!v) return; const x = h('span', `bench-c-${k}`); x.style.flex = String(v); x.title = `${l}: ${v}`; strip.append(x); });
    row.append(head, r.cls === null ? '' : strip);
    return row;
  }
  // A cell's hidden tests; a patch with none (nopatch, which keeps no counts) passed none of the task's FAIL_TO_PASS
  // tests, as another arm's grade of the task counts them, and broke none. A task no arm graded with counts adds none.
  function testsAt(L, c, i) {
    const t = K.testsOf(c);
    if (t || c.class !== 'nopatch') return t;
    const o = L.st.arms.map((a) => K.testsOf(a.cells.get(L.st.shared[i]))).find(Boolean);
    return o ? [0, o[1], o[3], o[3]] : [0, 0, 0, 0];
  }
  function testsRow(r, L) {
    const t = K.kept(r.f.cs.map((c, i) => testsAt(L, c, i)), (x) => x), ok = t && K.sum(t.map((x) => x[0])), all = t && K.sum(t.map((x) => x[1])), broke = t && K.sum(t.map((x) => x[3] - x[2]));
    return [K.armSaid(r.a), { v: t === null ? K.NOT_KEPT : [`${ok} of ${all} `, h('span', 'bench-muted', K.pct(all ? ok / all : null))], c: 'r' },
      { v: t === null ? K.NOT_KEPT : [`${broke} `, h('span', 'bench-muted', `in ${r.of('broke')} tasks`)], c: 'r' }, { v: r.cls === null ? K.NOT_KEPT : String(r.of('partial')), c: 'r' }];
  }
  // A chip in a card's heading, with its tip.
  function chipTitled(word, tip) { const c = K.chip(word, 'warn'); c.title = tip; return c; }
  function hidden(L) {
    // The chip shows only while an arm's results lack the grader's report.
    const s = K.box(['Hidden tests', ...(L.rows.some((r) => r.cls === null) ? [' ', chipTitled('needs the grader\'s report kept', 'Today the results keep only resolved yes or no')] : [])],
      'What the official harness found in each arm\'s patch, task by task. A task resolves only when every fail-to-pass test passes and no pass-to-pass test breaks.');
    const leg = h('div', 'bench-legend');
    CLASSES.forEach(([k, l]) => leg.append(K.add(h('span'), [h('i', `bench-c-${k}`), l])));
    s.append(...L.rows.map(classBar), leg, K.table(['Arm', ['Fail-to-pass passed', 'r'], ['Pass-to-pass broken', 'r'], ['Partial fixes', 'r']], L.rows.map((r) => testsRow(r, L))),
      K.note('"Fixed, but broke other tests" is the costliest failure: the issue looks fixed, and something else stops working. Conveyor\'s test step runs the touched tests, so it breaks fewer.'));
    return s;
  }
  // The share of an arm's resolved tasks with a measure true (null: one has not kept it), in a chip that is ok when
  // at or past `good` (at or under it, for low).
  function rate(r, f) { const v = K.kept(r.f.ok, f); return v === null || !v.length ? null : v.filter(Boolean).length / v.length; }
  const qcell = (v, good, low) => ({ v: v === null ? K.NOT_KEPT : K.chip(K.pct(v), (low ? v <= good : v >= good) ? 'ok' : 'warn'), c: 'r' });
  const sizeOf = (c) => { const m = K.obj(c.measures); return m && K.num(m.size) !== null ? m.size : null; };
  function quality(L) {
    // The chip shows only while an arm's resolved results lack the reference fix's size.
    const s = K.box(['Patch quality', ...(L.rows.some((r) => K.kept(r.f.ok, sizeOf) === null) ? [' ', chipTitled('needs the reference fix\'s size kept', 'Today the reference fix is removed after grading')] : [])],
      'The resolved tasks only: a patch can pass the hidden tests and still be a poor change.');
    s.append(K.table(['Arm', ['Clean', 'r'], ['Lint clean', 'r'], ['≤ 2× ref', 'r', 'At most twice the size of the reference fix'], ['Strays', 'r', 'Changes a file the reference fix does not touch'],
      ['Proves fix', 'r', 'Adds a test that fails on the base commit and passes with the patch']], L.rows.map((r) => [K.armSaid(r.a),
      { v: r.clean === null ? K.NOT_KEPT : [h('b', null, String(r.clean)), `/${r.k}`], c: 'r' }, qcell(rate(r, boolOf('lintClean')), 0.9),
      qcell(rate(r, (c) => (sizeOf(c) === null ? null : sizeOf(c) <= 2)), 0.75), qcell(rate(r, boolOf('strays')), 0.15, true), qcell(rate(r, boolOf('provesFix')), 0.5)])),
    K.kv([['Clean', 'Resolved, lint clean, at most twice the size of the reference fix, and no file the reference fix leaves alone.'], ['Lint clean', 'No new pyflakes finding (ruff, rules F) in the Python files the patch changes.'],
      ['Strays', 'The patch changes a file the reference fix does not touch.'], ['Proves the fix', 'The patch adds a test that fails on the base commit and passes with the patch.']]));
    return s;
  }

  // ---- lines of code, effort and steadiness ----
  function medianOf(cs, f) { const v = K.kept(cs, f); return v === null || !v.length ? null : K.median(v); }
  function refBar(r) {
    const row = h('div', 'bench-row bench-nowrap'), b = K.bar(Math.min(r, 4) / 4, r > 2.5 || r < 0.8 ? 'bench-fill-warn' : 'bench-fill-ok');
    b.classList.add('bench-refbar'); b.append(h('i', 'bench-mark'));
    row.append(b, h('span', 'bench-muted', `${r.toFixed(1)}×`));
    return row;
  }
  function locRow(r) {
    const ls = (k) => medianOf(r.f.ok, (c) => { const l = K.linesOf(c); return l && l[k]; }), a = ls('add'), d = ls('del'), t = ls('test'), f = ls('files'), z = medianOf(r.f.ok, sizeOf);
    return [K.armSaid(r.a), { v: a === null ? K.NOT_KEPT : [h('span', 'bench-plus', `+${a}`), ' ', h('span', 'bench-minus', `−${d}`)], c: 'r' },
      { v: t === null ? K.NOT_KEPT : t ? `+${t}` : h('span', 'bench-muted', 'none'), c: 'r' }, { v: f === null ? K.NOT_KEPT : f.toFixed(1), c: 'r' }, z === null ? K.NOT_KEPT : refBar(z)];
  }
  function refSaid(L) {
    const cs = L.st.shared.map((id) => L.rows[0].a.cells.get(id)), r = (k) => medianOf(cs, (c) => { const x = K.obj(K.obj(c.ref) && c.ref.code); return x && K.num(x[k]); });
    const f = r('files');
    return `The reference fix of a median task is ${f === null ? K.NOT_KEPT : `+${r('added')} −${r('removed')} in ${K.plural(f, 'file')}`}.`;
  }
  function loc(L) {
    const s = K.box('Lines of code', `Medians over each arm's resolved tasks. ${refSaid(L)}`);
    s.append(K.table(['Arm', ['Code lines', 'r'], ['Test lines', 'r'], ['Files', 'r'], 'Size against the reference fix'], L.rows.map(locRow)),
      K.note('1.0× is the size of the reference fix. Far above it often means changes the issue did not ask for; far below can mean a narrower fix that misses a case. Test lines count only lines added to test files.'));
    return s;
  }
  function sameOf(r) {
    const k = K.keysOf().find((x) => x.key === r.a.key), v = K.obj(k && k.figures) && k.figures.sameTwice;
    return K.num(v) === null ? h('span', 'bench-muted', K.NOT_KEPT) : K.chip(K.pct(v), v >= 0.85 ? 'ok' : 'warn');
  }
  function effortRow(r) {
    const conv = r.a.kind === 'conveyor', m = (f) => { const v = K.kept(r.f.ok, f); return v === null ? null : v.length ? K.mean(v) : 0; };
    const fx = m((c) => K.num(c.findingsFixed)), fr = m((c) => K.num(c.fixRounds)), to = K.kept(r.f.cs, (c) => (typeof c.timedOut === 'boolean' ? c.timedOut : null));
    const timeouts = to && to.filter(Boolean).length;
    return [K.armSaid(r.a), { v: r.k && r.f.tokens !== null ? K.kTok(r.f.tokens / r.k) : K.NOT_KEPT, c: 'r' }, { v: r.f.sessions === null ? K.NOT_KEPT : r.f.sessions.toFixed(1), c: 'r' },
      { v: !conv ? h('span', 'bench-muted', 'no review') : fx === null ? K.NOT_KEPT : fx.toFixed(1), c: 'r' }, { v: !conv ? h('span', 'bench-muted', '—') : fr === null ? K.NOT_KEPT : fr.toFixed(1), c: 'r' },
      { v: to === null ? K.NOT_KEPT : timeouts ? K.chip(String(timeouts), 'warn') : '0', c: 'r' }, { v: sameOf(r), c: 'r' }];
  }
  function effort(L) {
    const s = K.box('Effort and steadiness', 'What each resolved task took, and how often the arm gives the same result twice.');
    s.append(K.table(['Arm', ['Tokens / fix', 'r'], ['Sessions', 'r'], ['Findings', 'r'], ['Fix rounds', 'r'], ['Time-outs', 'r'], ['Same twice', 'r']], L.rows.map(effortRow)),
      K.kv([['Tokens / fix', 'Every token of the arm\'s sessions, divided by its resolved tasks.'], ['Time-outs', 'Tasks that reached the time limit.'],
        ['Findings', 'Review findings a task got and fixed before it landed: defects the hidden tests never had to find.'],
        ['Same twice', 'Of the tasks run twice with the same inputs, the share with the same result. Low means one run says little.']]));
    return s;
  }

  // ---- where Conveyor loses tasks, what the arms agree on, the next run ----
  const LOSS = [['build', 'Build: wrong or no change'], ['review', 'Review: passed a wrong change'], ['fix round', 'Fix round: broke it again'], ['test step', 'Test step: tests wrong'], ['blocked', 'Blocked: never landed']];
  function lossRow(label, v, tot) { const d = h('div', 'bench-lrow'), top = h('div', 'bench-row bench-space'); top.append(h('span', null, label), h('b', null, String(v))); d.append(top, K.bar(tot ? v / tot : 0, 'bench-fill-bad')); return d; }
  // With no Conveyor arm (L.conv falls back to the best arm) there is no box: its count would be another arm's losses.
  function losses(L) {
    const c = L.conv;
    if (c.a.kind !== 'conveyor') return '';
    const lost = c.f.cs.filter((x) => K.said(x) === 'no'), by = new Map();
    lost.forEach((x) => { const w = K.lossOf(x); if (w) by.set(w, (by.get(w) || 0) + 1); });
    const s = K.box('Where Conveyor loses tasks', `The first step where each unresolved task went wrong (${K.plural(lost.length, 'task')}).`);
    s.append(...LOSS.map(([k, l]) => lossRow(l, by.get(k) || 0, lost.length)), K.note('The biggest bar is where an engine change gains the most.'));
    return s;
  }
  function agree(L) {
    const m = L.rows.length, c = Array(m + 1).fill(0), s = K.box('What it agrees on', `Tasks by how many of the ${m} arms resolve them.`), cols = h('div', 'bench-cols');
    L.st.shared.forEach((id) => { c[L.st.arms.filter((a) => K.said(a.cells.get(id)) === 'yes').length] += 1; });
    const top = Math.max(...c, 1);
    c.forEach((v, i) => {
      const col = h('div', 'bench-col'), b = h('span', i === 0 ? 'bench-colbar bench-fill-bad' : i === m ? 'bench-colbar bench-fill-ok' : 'bench-colbar bench-fill');
      b.style.height = `${v / top * 90}px`; col.dataset.arms = String(i);
      col.append(h('span', null, String(v)), b, h('span', 'bench-muted', String(i)));
      cols.append(col);
    });
    s.append(cols, K.note('Left: no arm resolves them. Right: every arm does, so they tell the arms apart only on cost. The middle decides the ranking.'));
    return s;
  }
  // The next run: the two leading arms in one tier with three times the tasks, an arm that did not always fire, and the
  // next tasks of the pinned order no arm has run.
  function tiedItem(L) {
    const [a, b] = L.rows;
    if (!b || a.tier !== b.tier) return null;
    const T = Math.min(K.setSize(), Math.max(L.n * 3, L.n + 1)), more = T - L.n, li = h('li');
    const cost = a.perTask !== null && b.perTask !== null ? `About ${K.usd(more * (a.perTask + b.perTask))}` : `Cost: ${K.NOT_KEPT}`;
    const mins = a.f.minutes !== null && b.f.minutes !== null ? `${K.fmtMin(more * (a.f.minutes + b.f.minutes))} of machine time` : `machine time: ${K.NOT_KEPT}`;
    li.append(h('b', null, `${a.a.label} against ${b.a.label}`), `: tied at ${L.n} tasks. ${more} more tasks (${T} in all) show a difference of ${K.noiseSaid(T)} tasks, ${K.noisePct(T)}. ${cost}, ${mins}. `, K.chip('open question', 'info'));
    return { li, plan: { q: 'better', n: T, arms: [a.a.arm, b.a.arm] } };
  }
  function nextRun(L) {
    const s = K.box('Next run to make', 'The run that answers the biggest open question for the least cost.'), ul = h('ul', 'bench-list'), tied = tiedItem(L);
    if (tied) ul.append(tied.li);
    L.rows.filter((r) => r.fired !== null && r.fired < 0.95).forEach((r) => ul.append(K.add(h('li'), [h('b', null, r.a.label), ` fired in only ${K.pct(r.fired)} of tasks. Check its arm before the next run. `, K.chip('arm problem', 'warn')])));
    const done = new Set(K.keysOf().flatMap((k) => K.list(k.live))), hi = Math.min(K.setSize(), L.n + 50);
    if (L.n < hi && !Array.from(done).some((i) => i >= L.n && i < hi)) ul.append(h('li', null, `Tasks ${L.n + 1} to ${hi} have no result yet for any arm.`));
    s.append(...(ul.children.length ? [ul] : []), K.button('Plan this run', 'btn-primary', 'plan-next', 'Plan this run', () => { if (tied) Object.assign(K.B.plan, { q: tied.plan.q, n: tied.plan.n, arms: new Set(tied.plan.arms) }); K.go('plan'); }));
    return s;
  }

  // ---- the run history, folded at the foot ----
  // A run you stopped says how many tasks it reached ("stopped at 31"): the most any arm finished. Another state keeps its word.
  const stoppedAt = (r, cols, word) => (word === 'stopped' ? `stopped at ${Math.max(0, ...cols.map((c) => K.num(c.done) || 0))}` : word);
  function historyRow(r) {
    const box = h('input'), cols = K.colsOf(r), [word, tone] = K.stateOf(r), st = [K.chip(stoppedAt(r, cols, word), tone)];
    box.type = 'checkbox'; box.checked = K.B.sel.includes(r.id); box.dataset.act = `pick-${r.id}`; box.setAttribute('aria-label', `Select ${r.id}`);
    box.addEventListener('change', () => { K.B.sel = box.checked ? K.B.sel.concat(r.id) : K.B.sel.filter((x) => x !== r.id); K.draw(); });
    if (typeof r.archived === 'string') st.push(' ', K.chip('archived', 'quiet'));
    return [box, { v: r.id, c: 'mono' }, cols.length ? `${K.colName(cols[0])}${cols.length > 1 ? ` · ${cols.length} arms` : ''}` : 'no arm', { v: String(K.num(r.n) || 0), c: 'r' }, st,
      K.B.ctx.when(r.started), { v: K.costSaid(r.cost), c: 'r' }];
  }
  function historyFold() {
    const runs = K.allRuns(), arch = runs.filter((r) => typeof r.archived === 'string').length;
    const d = K.fold('history', `Run history (${K.plural(runs.length, 'run')}, ${arch} archived)`, 'bench-box bench-history'), picked = runs.filter((r) => K.B.sel.includes(r.id));
    K.B.sel = picked.map((r) => r.id);
    d.append(K.saidAt(K.RUNS_SAID));
    if (picked.length) {
      const bar = h('div', 'bench-row bench-selbar');
      bar.append(h('strong', null, `${K.plural(picked.length, 'run')} selected`), ...K.runActs(picked), K.button('Clear', 'btn-quiet btn-sm', 'sel-clear', 'Clear the selection', () => { K.B.sel = []; K.draw(); }));
      d.append(bar);
    }
    const t = K.table(['', 'Run', 'What ran', ['Tasks', 'r'], 'State', 'Started', ['Cost', 'r']], runs.map(historyRow), 'bench-runs', (tr, i) => { tr.dataset.run = runs[i].id; }), all = h('input');
    all.type = 'checkbox'; all.checked = runs.length > 0 && picked.length === runs.length; all.dataset.act = 'pick-all'; all.setAttribute('aria-label', 'Select all');
    all.addEventListener('change', () => { K.B.sel = all.checked ? runs.map((r) => r.id) : []; K.draw(); });
    t.querySelector('th').append(all);
    d.append(t,
      K.note('Tick runs to archive, restore or delete them. An archived run is in no figure, Compare or plan. Results of the same arm, version and task are reused, never run again.'));
    return d;
  }

  // ---- with fewer than 3 shared tasks: what the runs have ----
  // Each arm on the tasks it graded itself (the arms may share none).
  function fewRows(st) {
    return st.arms.map((a) => rowOf(a, Array.from(a.cells.keys()).filter((id) => K.graded(a.cells.get(id))))).sort((x, y) => y.k - x.k);
  }
  function fewVerdict(st, rows) {
    const runs = st.runs, ns = Array.from(new Set(rows.map((r) => r.n))), n = Math.max(...ns, 0), all = rows.every((r) => r.k === r.n && r.n);
    const what = all ? `Every arm resolved the ${n === 1 ? 'one task' : 'tasks'} it ran.` : rows.every((r) => !r.k) ? 'No arm resolved a task.' : `${rows.filter((r) => r.k).length} of ${rows.length} arms resolved a task.`;
    const one = st.ids.length === 1 ? [', ', h('span', 'mono', st.ids[0])] : [];
    const ran = `Your ${K.plural(runs.length, 'run')} ${runs.length > 1 && ns.length === 1 ? 'each ' : ''}ran ${ns.length === 1 ? K.plural(n, 'task') : `${Math.min(...ns)} to ${n} tasks`}`;
    // Each arm's own 95% range, from what it resolved: the same for every arm only when they all resolved alike.
    const rg = rows.map((r) => K.wilson(r.k, r.n)), lo = Math.min(...rg.map((x) => x[0])), hi = Math.max(...rg.map((x) => x[1])), alike = rg.every((x) => x[0] === rg[0][0] && x[1] === rg[0][1]);
    const range = alike ? `the 95% range of every arm is ${K.pct(lo)} to ${K.pct(hi)}` : `the 95% ranges of the arms run from ${K.pct(lo)} to ${K.pct(hi)}`;
    return K.verdict('quiet', 'Verdict on the tasks you have', `Nothing can be told yet. ${what}`, [ran, ...one, `. With ${K.plural(n, 'task')}, only a total break shows: ${range}. To tell Conveyor from Claude alone, run 50 tasks or more.`]);
  }
  function fewStats(st, rows) {
    const ns = Array.from(new Set(st.runs.map((r) => K.num(r.n) || 0))), R = st.runs.length, c = convOf(rows);
    const at = new Set(K.keysOf().flatMap((k) => K.list(k.live))).size, size = K.setSize(), arms = K.armsOf(), ready = arms.filter((a) => a.state === 'ready').length, never = arms.filter((a) => a.state === 'unchecked').length;
    const runsChip = ns.length === 1 ? `${R === 2 ? 'both' : 'each'} ${K.plural(ns[0], 'task')}` : `${Math.min(...ns)} to ${Math.max(...ns)} tasks`;
    // The Conveyor cost stat shows only when a Conveyor arm ran.
    const conv = c ? [K.stat(K.usd(c.f.cost), `${c.a.col.label || c.a.label}: cost of its ${c.n === 1 ? 'task' : 'tasks'}`, K.chip(`${K.plural(Math.round(K.sum(c.f.cs.map((x) => K.num(x.sessions) || 0))), 'session')}, ${K.kTok(c.f.tokens)} tokens`, 'quiet'))] : [];
    return K.grid(String(3 + conv.length), K.stat(String(R), 'Runs', K.chip(runsChip, 'quiet')), K.stat(`${at} of ${size}`, 'Tasks with a result', K.chip(`${(at / size * 100).toFixed(1)}% of the set`, 'quiet')),
      ...conv, K.stat(`${ready} of ${arms.length}`, 'Arms checked and ready', never ? K.chip(`${never} never checked`, 'warn') : K.chip('every arm checked', 'ok')));
  }
  function fewLines(r) {
    const ls = r.f.cs.map(K.linesOf), k = (f) => (ls.some((l) => l === null) ? null : K.sum(ls.map(f)));
    const a = k((l) => l.add), d = k((l) => l.del), t = k((l) => l.test), f = k((l) => l.files);
    return [r.a.label, { v: a === null ? K.NOT_KEPT : [h('span', 'bench-plus', `+${a}`), ' ', h('span', 'bench-minus', `−${d}`)], c: 'r' },
      { v: t === null ? K.NOT_KEPT : t ? `+${t}` : h('span', 'bench-muted', 'none'), c: 'r' }, { v: f === null ? K.NOT_KEPT : String(f), c: 'r' }];
  }
  // What the patch summary shows: that every arm changed the same code files by the same line counts (it says nothing when
  // no arm changed a code file), by the larger of its added and removed lines, and which arms added a test, with the test
  // files when one arm did. The mockup's words are "made the same one-line fix"; the note says them only when the arms' patch
  // summaries are all kept and hold the same code files by the same counts.
  const WORDS = ['no', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten'];
  // The code files of an arm's patches with their line counts, as one text; null when a patch is not kept (a result that
  // keeps only the totals, not the files, cannot say the files are the same).
  const codeOf = (r) => (r.f.cs.every((c) => Array.isArray(c.patch)) ? JSON.stringify(r.f.cs.flatMap((c) => c.patch.filter((f) => !K.isTest(String(f.path))).map((f) => [f.path, f.added, f.removed])).sort()) : null);
  function fewPatchNote(rows) {
    const ls = rows.map((r) => { const v = r.f.cs.map(K.linesOf); return v.some((l) => l === null) ? null : { add: K.sum(v.map((l) => l.add)), del: K.sum(v.map((l) => l.del)), test: K.sum(v.map((l) => l.test)) }; });
    const code = rows.map(codeOf), same = rows.length > 1 && ls.every((l) => l && l.add === ls[0].add && l.del === ls[0].del) && code.every((x) => x !== null && x !== '[]' && x === code[0]), t = rows.filter((r, i) => ls[i] && ls[i].test), some = ls.every(Boolean) && t.length > 0 && t.length < rows.length;
    const say = [];
    if (same) {
      const lines = Math.max(ls[0].add, ls[0].del);
      say.push(`All ${WORDS[rows.length] || rows.length} made the same ${lines === 1 ? 'one-line' : `${lines}-line`} fix`);
    }
    if (some) say.push(`${same ? 'only' : 'Only'} ${t.map((r) => r.a.label).reduce((s, x, i) => (i ? `${s}${i === t.length - 1 ? ' and ' : ', '}${x}` : x), '')} added a test${t.length === 1 ? ` (${testIn(t[0], ls[rows.indexOf(t[0])].test)})` : ''}`);
    return `Real, from the patches the results keep.${say.length ? ` ${say.join('; ')}.` : ''}`;
  }
  // "7 lines in tests/x.py": an arm's added test lines with the test files its patches change, when they are kept.
  function testIn(r, lines) {
    const files = r.f.cs.every((c) => Array.isArray(c.patch)) ? Array.from(new Set(r.f.cs.flatMap((c) => c.patch.filter((f) => K.isTest(String(f.path)) && f.added > 0).map((f) => String(f.path))))) : [];
    return `${K.plural(lines, 'line')}${files.length ? ` in ${files.join(', ')}` : ''}`;
  }
  function fewHidden(rows) {
    const old = rows.filter((r) => r.cls === null).map((r) => r.a.label);
    if (!old.length) return '';
    const won = rows.filter((r) => r.k === r.n).length, n = Math.max(...rows.map((r) => r.n), 0);
    return K.callout(`${won === rows.length ? 'Every arm' : `${won} of ${rows.length} arms`} passed the ${n === 1 ? "task's" : "tasks'"} hidden tests: that is all the results keep. The run records resolved yes or no and the patch, `
      + 'and the harness report with each fail-to-pass and pass-to-pass test is removed. To show these panels, the engine must keep that report. Size, strays and lint can be read from the patches the results already keep.', 'warn');
  }
  // What the Cost column shows, said only for what it shows: "not priced" for an arm with no usage that can be priced.
  function fewCostNote(rows) {
    return rows.some((r) => r.f.cost === null) ? [K.note('"Not priced": agent arms report no usage by model today.')] : [];
  }
  function fewBoard(rows) {
    const n = Math.max(...rows.map((r) => r.n), 0), s = K.box('Leaderboard', n === 1 ? 'One task each. The ranges show how little one task says.' : '');
    s.append(K.table(['Arm', ['Resolved', 'r'], 'Resolve rate, 95% range', ['Cost', 'r'], ['Tokens', 'r'], ['Minutes', 'r']], rows.map((r) => [K.armSaid(r.a), { v: `${r.k}/${r.n}`, c: 'r' }, K.ciBar(r.k, r.n, r.a.s),
      { v: K.usd(r.f.cost), c: 'r' }, { v: K.kTok(r.f.tokens), c: 'r' }, { v: r.f.wall === null ? K.NOT_KEPT : String(r.f.wall), c: 'r' }]), 'bench-leader'),
    ...fewCostNote(rows), h('h3', 'bench-h', 'Hidden tests and patch quality'),
    K.table(['Arm', ['Code lines', 'r'], ['Test lines', 'r'], ['Files', 'r']], rows.map(fewLines)), h('p', 'bench-note', fewPatchNote(rows)), fewHidden(rows));
    return s;
  }
  function plainCost(names, n) {
    const arms = names.map((x) => K.armsOf().find((a) => a.name === x)).filter((a) => a && K.obj(a.perTask));
    if (arms.length < names.length) return null;
    const u = arms.map((a) => (K.num(a.perTask.session) === null ? null : a.perTask.usual * a.perTask.session * n));
    return { usd: u.some((x) => x === null) ? null : K.sum(u), min: K.sum(arms.map((a) => (K.num(a.perTask.minutes) || 0) * n)) };
  }
  function fewNext() {
    const s = K.box('Next run to make', 'Start with the question, not the number.'), ul = h('ul', 'bench-list'), b = plainCost(['conveyor', 'solo'], 50), w = plainCost(['conveyor'], 5);
    const vs = K.list(K.benchOf().versions).filter((v) => K.obj(v) && v.name !== 'main'), ver = vs.length ? vs[vs.length - 1].name : 'main', never = K.armsOf().filter((a) => a.state === 'unchecked').length;
    const said = (c) => (c ? `about ${K.usd(c.usd)} and ${K.fmtMin(c.min)} of machine time` : K.NOT_KEPT);
    ul.append(K.add(h('li'), [h('b', null, 'Is Conveyor better than Claude alone?'), ` 50 tasks, 2 arms: ${said(b)}. Shows a ${K.noiseSaid(50)}-task difference.`]),
      K.add(h('li'), [h('b', null, `Does ${ver} work at all?`), ` 5 tasks, Conveyor only: ${said(w)}.`]));
    if (never) ul.append(h('li', null, `The other ${K.plural(never, 'arm')} ${never === 1 ? 'was' : 'were'} never checked. A check costs 1 small task each.`));
    s.append(ul, K.button('Plan a run', 'btn-primary', 'plan-next', 'Plan a run', () => K.go('plan')));
    return s;
  }
  function fewPage(st) {
    const rows = fewRows(st);
    // The history is the only place Archive, Restore and Delete are, so the page keeps it, folded.
    return [fewVerdict(st, rows), fewStats(st, rows), K.grid('main', fewBoard(rows), fewNext()), historyFold()];
  }
  function fullPage(st) {
    const L = boardOf(st);
    return [verdictOf(L), stats(L), K.grid('main', leaderboard(L), value(L)), K.grid('2', hidden(L), quality(L)), K.grid('2', loc(L), effort(L)), K.grid('3', losses(L), agree(L), nextRun(L)), historyFold()];
  }
  function score() {
    const top = K.answers(Q);
    if (!K.hist()) return [top, K.reading('the runs')];
    const st = K.studyOf();
    if (st.reading !== undefined) return [top, K.reading(`the run ${st.id}`, st.reading)];
    if (!st.arms.length) return [top, K.verdict('quiet', 'Verdict on the tasks you have', 'Nothing can be told yet.'), historyFold()];
    return [top, ...(st.n < 3 ? fewPage(st) : fullPage(st))];
  }
  window.DASH_APP.part('bench-score', function (shared) {
    K = shared;
    return { score };
  });
})();
