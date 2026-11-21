// SPDX-License-Identifier: Apache-2.0
// The Benchmarks tab's Plan a run (#1177, the owner's mockup): the question first (does it work, is one better, most per
// dollar), which sets the tasks and the arms; then the arms with their state, dollars and minutes a task and the results
// kept for them; the task slider with the difference it can show; and Before you start: the verdict on the size, the cost,
// machine time, usual and worst sessions, kept results reused, the usage guard and the command it runs. Start sends that
// command (`bench swe <n> --arm <name>...`, with the engine's default settings; POST control {action: bench, args: [run,
// ...]}); Check the arms first sends the preflight of each arm ticked that is not ready (of every ticked arm, when all are ready). Part of panels/bench.js, which
// asks for it by name (DASH_APP.use) and gives it its kit (K).
(() => {
  'use strict';
  let K;
  const h = (...a) => K.h(...a);
  // Each question: its title, what it compares and the tasks it sets.
  const QS = { works: ['Does it work at all?', 'A new version or a changed arm: one total break shows.', 5], better: ['Is one better than another?', 'Two arms or two versions on the same tasks.', 50],
    value: ['Which arm gives the most per dollar?', 'Every ready arm, on the same tasks.', 30] };
  // The states the mockup shows; an arm in another state (checking, unchecked) has none kept.
  const ARM_STATE = { ready: ['ready', 'ok'], changed: ['changed', 'warn'], expired: ['expired', 'quiet'] };
  const offered = () => K.armsOf().filter((a) => a.state !== 'not offered');
  // The arms a question ticks: the Conveyor arm; it and Claude alone; or every ready arm (6 at most).
  function armsFor(q) {
    if (q === 'value') return new Set(offered().filter((a) => a.state === 'ready').slice(0, 6).map((a) => a.name));
    return new Set((q === 'works' ? ['conveyor'] : ['conveyor', 'solo']).filter((x) => offered().some((a) => a.name === x)));
  }
  const planOf = () => { const p = K.B.plan; if (!p.arms) p.arms = armsFor(p.q); return p; };
  const picked = () => offered().filter((a) => planOf().arms.has(a.name));

  // The commit the Conveyor arms build with, main's as listed (null when it is not known).
  function commitOf() {
    const v = K.list(K.benchOf().versions).find((x) => K.obj(x) && x.name === 'main');
    return v && typeof v.commit === 'string' ? v.commit : null;
  }

  // ---- the arms, the tasks and the cost ----
  // The tasks of the first n that the arm has a result for on the engine it would run (a Conveyor arm: the commit of
  // main), reused at no cost.
  function keptOf(a, n) {
    const c = commitOf(), key = a.kind === 'conveyor' ? (c && typeof a.keyPrefix === 'string' ? `${a.keyPrefix}${c}` : null) : a.key;
    const k = K.keysOf().find((x) => x.key === key);
    return k ? K.list(k.at).filter((i) => Number.isInteger(i) && i < n).length : 0;
  }
  // One arm's part of the run: the tasks it runs (the rest reused; each when that is not known), its usual and worst
  // sessions, minutes and dollars (each session at the mean list price of the project's own priced sessions; null with
  // none to take it from).
  function costOf(a, n) {
    const p = K.obj(a.perTask) || { usual: 1, worst: 1, minutes: 10 }, reused = keptOf(a, n), todo = n - reused, one = K.num(p.session);
    const usual = Math.ceil(todo * (K.num(p.usual) || 0));
    return { reused, todo, usual, worst: todo * (K.num(p.worst) || 0), minutes: todo * (K.num(p.minutes) || 0), usd: todo === 0 ? 0 : one === null ? null : usual * one };
  }
  const perTask = (a) => { const p = K.obj(a.perTask); return p && K.num(p.session) !== null ? p.usual * p.session : null; };
  // The difference n tasks can show: the engine's noise in whole tasks (K.noised), only a total break when that is n.
  const showsSaid = (n) => (K.noised(n) >= n ? 'Shows only a total break' : `Shows a difference of ${K.noiseSaid(n)} tasks (${K.noisePct(n)}) or more`);
  function question([k, [t, s, n]]) {
    const q = h('div', 'bench-q');
    q.setAttribute('role', 'button'); q.tabIndex = 0; q.dataset.q = k; q.dataset.act = `q-${k}`; q.setAttribute('aria-pressed', String(planOf().q === k));
    q.append(h('b', null, t), h('span', 'bench-small bench-muted', s));
    const pick = () => { Object.assign(K.B.plan, { q: k, n, arms: armsFor(k) }); K.draw(); };
    q.addEventListener('click', pick);
    q.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); pick(); } });
    return q;
  }
  function armRow(a, n) {
    const box = h('input'), [word, tone] = ARM_STATE[a.state] || [K.NOT_KEPT, 'quiet'], k = keptOf(a, n), p = K.obj(a.perTask);
    box.type = 'checkbox'; box.checked = planOf().arms.has(a.name); box.dataset.act = `arm-${a.name}`; box.setAttribute('aria-label', a.label);
    box.addEventListener('change', () => { if (box.checked) planOf().arms.add(a.name); else planOf().arms.delete(a.name); K.draw(); });
    return [box, K.armSaid({ s: a.s, label: a.label }), K.chip(word, tone), { v: K.usd(perTask(a)), c: 'r' },
      { v: p && K.num(p.minutes) !== null ? String(p.minutes) : K.NOT_KEPT, c: 'r' }, { v: a.kind === 'conveyor' && !k ? '0 (new engine)' : String(k), c: 'r' }];
  }
  function armsTable(n) {
    const arms = K.paint(offered().map((a) => ({ ...a, arm: a.name })));
    return K.table(['', 'Arm', 'State', ['$ / task', 'r'], ['Min / task', 'r'], ['Kept results', 'r']], arms.map((a) => armRow(a, n)), 'bench-planarms', (tr, i) => { tr.dataset.arm = arms[i].name; });
  }
  // The arms and the tasks. The slider changes the figures it moves in place (moved: Before you start), never the
  // whole page: a page drawn anew would take the slider from under the pointer that drags it.
  function armsBox(n, moved) {
    const max = K.setSize(), bar = (v) => K.bar(Math.max(0.04, 1 - K.noised(v) / v));
    const s = K.box('Arms', 'Ready arms can start now. The others need a check first (1 small task each).');
    let tbl = armsTable(n), b = bar(n);
    const range = h('input'), line = h('div', 'bench-row bench-space bench-small'), pn = h('b', 'bench-pn', String(n)), shows = h('span', 'bench-muted bench-pdet', showsSaid(n));
    range.type = 'range'; range.min = '1'; range.max = String(max); range.value = String(n); range.dataset.act = 'plan-n'; range.setAttribute('aria-label', 'Tasks to run');
    range.addEventListener('input', () => {
      const v = Math.max(1, Math.min(max, Math.round(Number(range.value)) || 1)), t = armsTable(v), nb = bar(v);
      K.B.plan.n = v; pn.textContent = String(v); shows.textContent = showsSaid(v);
      tbl.replaceWith(t); tbl = t; b.replaceWith(nb); b = nb;
      moved(v);
    });
    line.append(K.add(h('span'), ['Run the first ', pn, ' tasks of the pinned order']), shows);
    s.append(tbl, h('h3', 'bench-h', 'Tasks'), line, range, b);
    return s;
  }
  // The smallest and the largest gap between neighbouring Conveyor versions in the last study, each on the tasks both
  // graded (not told of fewer than 3), as {pts, need}: its points and the tasks that show it (2 / gap², as Compare says);
  // null when no two versions are read with a gap.
  function versionGaps() {
    const vs = K.versionsOf(), g = vs.slice(1).map((v, i) => K.moved(vs[i], v)).filter((m) => m && !m.few && m.pts !== 0).map((m) => ({ pts: Math.abs(m.pts), r: Math.abs(m.d) / m.shared }));
    if (!g.length) return null;
    const of = (x) => ({ pts: x.pts, need: Math.ceil(2 / (x.r ** 2)) });
    return { min: of(g.reduce((a, b) => (b.r < a.r ? b : a))), max: of(g.reduce((a, b) => (b.r > a.r ? b : a))) };
  }
  // What the run can tell, for the question picked.
  function sizeSaid(q, n, arms) {
    const det = K.noised(n) / n, st = K.studyOf(), c = st.arms && st.arms.find((a) => a.arm === 'conveyor'), s = st.arms && st.arms.find((a) => a.arm === 'solo');
    const pts = c && s && st.n >= 3 ? Math.round((K.figsOf(c, st.shared).k - K.figsOf(s, st.shared).k) / st.n * 100) : null;
    if (q === 'works') return n <= 10 ? ['Right size: enough to see a break, cheap.', 'ok'] : ['More than you need to see a break.', 'warn'];
    if (q === 'value') return arms.length < 3 ? ['Pick at least 3 arms to compare value.', 'warn'] : [`Ranks ${arms.length} arms. Arms closer than ${K.noisePct(n, true)} share a tier.`, 'ok'];
    const g = versionGaps(), vers = !g ? ' A 10-point gap needs 200 tasks.' : ` Two Conveyor versions differ by ${g.min.pts === g.max.pts ? `${g.min.pts} points` : `${g.min.pts} to ${g.max.pts} points`}: a ${g.max.pts}-point gap needs ${g.max.need} tasks.`;
    return det <= 0.2 ? [`Good for arms: a gap of ${K.noisePct(n)} or more shows${pts === null ? '' : `, and Conveyor against Claude alone was ${pts} points in the last study`}.${vers}`, 'ok']
      : [`Too small: only a gap of ${K.noisePct(n)} or more shows.${pts === null ? '' : ` Conveyor against Claude alone was ${pts} points.`} Try 50 tasks or more.`, 'warn'];
  }
  // The command the page shows and Start sends: the run's arguments after `run`, the tasks and the arms in order.
  const argsOf = (n, arms) => [String(n), ...arms.flatMap((a) => ['--arm', a.name])];
  // An argument as a shell takes it: quoted when it holds more than a word.
  const shellSaid = (x) => (/^[\w.:/-]+$/.test(x) ? x : `'${x.replace(/'/g, '\'\\\'\'')}'`);
  const named = (as) => as.map((a) => a.label).join(', ');
  // Why Start is off, in words, or '': a run goes, no arm is ticked, a ticked arm is not ready, or its usage guard is reached.
  // Otherwise Start is on, as in the mockup.
  function startWhy(arms) {
    const l = K.live(), g = K.obj(K.hist().guard) || {}, notReady = arms.filter((a) => a.state !== 'ready'), held = arms.filter((a) => a.guard && g[a.guard] === true);
    if (l && l.state === 'running') return 'Start is off: a run goes now.';
    if (!arms.length) return 'Start is off: no arm is ticked.';
    if (notReady.length) return `Start is off: ${named(notReady)} ${notReady.length === 1 ? 'is' : 'are'} not ready.`;
    return held.length ? 'Start is off: the usage guard is reached.' : '';
  }
  // The arms a check runs for: the ticked arms that are not ready and not being checked; with none, the ticked arms that
  // are not being checked (the check runs again, as the mockup's button, which is always on, would).
  function toCheck(arms) {
    const idle = arms.filter((a) => a.state !== 'checking'), need = idle.filter((a) => a.state !== 'ready');
    return need.length ? need : idle;
  }
  // Why Check the arms first is off, or '': no arm is ticked, or every ticked arm is being checked.
  const checkWhy = (arms) => (toCheck(arms).length ? '' : `Check the arms first is off: ${arms.length ? 'the ticked arms are being checked' : 'no arm is ticked'}.`);
  function startButton(n, arms) {
    const b = K.button('Start the run', 'btn-primary', 'start', `Start the run: ${K.plural(arms.length, 'arm')} on ${K.plural(n, 'task')}`,
      () => K.send('start', ['run', ...argsOf(n, arms)], (t) => t.replace(/^conveyor: /, ''), () => K.readHist(true)));
    b.disabled = Boolean(startWhy(arms)) || K.B.busy;
    return b;
  }
  function checkButton(arms) {
    const need = toCheck(arms);
    const b = K.button('Check the arms first', '', 'check-arms', `Check ${named(need) || 'the arms'}`, () => K.send('check', ['arms', 'check', ...need.map((a) => a.name)],
      (t) => `${t.replace(/^conveyor: /, '')}. The arms are read again while their checks run.`, () => K.readHist(true)));
    b.disabled = Boolean(checkWhy(arms)) || K.B.busy;
    return b;
  }
  // The page says why a button is off, under the buttons, as one line; with both on, the mockup's page has none.
  const offWhy = (arms) => { const t = [startWhy(arms), checkWhy(arms)].filter(Boolean).join(' '); return t ? h('p', 'bench-note bench-why', t) : ''; };
  // The share of the week one trial has used on a guard ("conveyor" or "agent"): the runs that kept the guard's share of the
  // week left at their start and after their last trial, the share they used over the trials they ran on arms of that
  // guard (a col's ran). Where both guards read one login (K.weekPool), the share is the use of the trials of both. Null with
  // no run that used any (an older run kept none; a reading that did not move says nothing).
  function weekRate(kind) {
    let used = 0, ran = 0;
    const at = (w) => (K.obj(w) ? K.num(w[kind]) : null);
    K.runsOf().forEach((r) => {
      const a = at(r.weekStart), b = at(r.weekLeft), pool = K.weekPool(r.weekStart, kind);
      const t = K.sum(K.colsOf(r).filter((c) => pool.includes((K.armsOf().find((x) => x.name === c.arm) || {}).guard)).map((c) => K.num(c.ran) || 0));
      if (a !== null && b !== null && t > 0) { used += Math.max(0, a - b); ran += t; }
    });
    return ran && used > 0 ? used / ran : null;
  }
  // The usage guard chip: the plan's trials (the arms' parts, in order) times the share one trial used, taken off the share
  // of the week left now, must leave more than the share at which the guard stops (the history's weekLeft.stop; "off" for no guard), for each
  // login the arms use (both guards, when they read one). Not kept when a share left, the stop or what a trial uses is not kept.
  function weekChip(arms, parts) {
    const left = K.obj(K.hist().weekLeft) || {}, stop = K.num(left.stop);
    // The guard is off (stop "off"): the guard does not stop the run, whatever it uses of the week (staff can still stop it).
    if (left.stop === 'off') return K.chip('off; the guard will not stop the run', 'ok');
    const kinds = [...new Set(arms.map((a) => a.guard).filter(Boolean))];
    const fits = (left.shared === true ? [kinds] : kinds.map((k) => [k])).map((g) => {
      const rate = weekRate(g[0]), l = K.num(left[g[0]]);
      return rate === null || l === null || stop === null ? null : l - rate * K.sum(arms.map((a, i) => (g.includes(a.guard) ? parts[i].todo : 0))) > stop;
    });
    if (fits.includes(null)) return K.chip(K.NOT_KEPT, 'quiet');
    return fits.every(Boolean) ? K.chip('fits in the week left', 'ok') : K.chip('would reach the guard; the run stops there', 'bad');
  }
  function before(n) {
    const arms = picked(), parts = arms.map((a) => costOf(a, n)), q = planOf().q, [said, tone] = sizeSaid(q, n, arms);
    const lim = K.obj(K.hist().limits) || {};
    const usd = parts.some((p) => p.usd === null) ? null : K.sum(parts.map((p) => p.usd)), mins = K.sum(parts.map((p) => p.minutes)), g = K.obj(K.hist().guard) || {};
    const held = arms.some((a) => a.guard && g[a.guard] === true), b = startButton(n, arms);
    // A guard reached now would stop the run; else the plan's use of the week against the share left (weekChip). An arm
    // with no guard (swe_guards: a Codex arm) has none to reach. A short chip: the chip keeps its text on one line (app.css .chip).
    const guardSaid = held ? K.chip('would reach the guard; the run stops there', 'bad') : arms.some((a) => a.guard) ? weekChip(arms, parts) : K.chip(K.NOT_KEPT, 'quiet');
    const s = K.box('Before you start', `${K.plural(arms.length, 'arm')} × ${K.plural(n, 'task')}`, 'bench-before');
    s.append(K.callout(said, tone), K.kv([['Cost', [h('b', null, K.usd(usd)), ' ', h('span', 'bench-muted bench-small', 'at list prices')]], ['Machine time', [h('b', null, K.fmtMin(mins)), ' ', h('span', 'bench-muted bench-small', 'tasks run one after another')]],
      ['Sessions', `${K.sum(parts.map((p) => p.usual))} usual, ${K.sum(parts.map((p) => p.worst))} at worst`],
      ['Kept results', `${K.sum(parts.map((p) => p.reused))} task runs reused at no cost`],
      ['Usage guard', guardSaid],
      ['Belt', K.num(lim.cpus) === null || !lim.memory ? K.NOT_KEPT : `Cards and the run share the machine. Each task's container gets ${lim.cpus} CPUs and ${lim.memory}.`]]),
    K.add(h('div', 'bench-row'), [b, checkButton(arms)]), offWhy(arms), K.refusedAt('start'), K.refusedAt('check'),
    K.add(h('p', 'bench-note'), ['The command it runs: ', h('span', 'mono bench-cmd', `conveyor.sh bench swe ${argsOf(n, arms).map(shellSaid).join(' ')}`)]));
    return s;
  }
  function plan() {
    const top = K.answers('Which run answers my question, and what will it cost?', 'Pick the question first. The planner sets the tasks and arms, and shows the cost before you start.');
    if (!K.hist()) return [top, K.reading('the arms')];
    const p = planOf(), n = Math.max(1, Math.min(K.setSize(), Math.round(K.num(p.n) || 1)));
    p.n = n;
    let right = before(n);
    const left = armsBox(n, (v) => { const nb = before(v); right.replaceWith(nb); right = nb; });
    return [top, K.add(h('div', 'bench-grid bench-g-3'), Object.entries(QS).map(question)), K.grid('main', left, right)];
  }
  window.DASH_APP.part('bench-plan', function (shared) {
    K = shared;
    return { plan };
  });
})();
