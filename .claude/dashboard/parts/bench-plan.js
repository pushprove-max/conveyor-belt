// SPDX-License-Identifier: Apache-2.0
// The Benchmarks tab's Plan a run (#1177, the owner's mockup): the question first (does it work, is one better, most per
// dollar), which sets the tasks and the arms; then the arms with their state, dollars and minutes a task and the results
// kept for them; the task slider with the difference it can show, the Conveyor version and the run settings every arm
// shares (folded); and Before you start: the verdict on the size, the cost, machine time, usual and worst sessions, kept
// results reused, the usage guard and the command it runs. Start sends that command (`bench swe <n> --arm <name>...
// [--engine <version | commit>] [--settings <json>]`, POST control {action: bench, args: [run, ...]}), as the tab's Start
// did; Check the arms first sends the preflight of each arm ticked that is not ready. Part of panels/bench.js, which
// asks for it by name (DASH_APP.use) and gives it its kit (K).
(() => {
  'use strict';
  let K;
  const h = (...a) => K.h(...a);
  // Each question: its title, what it compares and the tasks it sets.
  const QS = { works: ['Does it work at all?', 'A new version or a changed arm: one total break shows.', 5], better: ['Is one better than another?', 'Two arms or two versions on the same tasks.', 50],
    value: ['Which arm gives the most per dollar?', 'Every ready arm, on the same tasks.', 30] };
  const ARM_STATE = { ready: ['ready', 'ok'], checking: ['checking', 'quiet'], failed: ['preflight failed', 'bad'], unchecked: ['not checked', 'quiet'], changed: ['changed', 'warn'],
    expired: ['expired', 'quiet'], 'not offered': ['not offered', 'quiet'] };
  const RECEIPT = /^conveyor: run (r[0-9]{8}T[0-9]{6}-[0-9]+) (started|ended)$/m;
  const offered = () => K.armsOf().filter((a) => a.state !== 'not offered');
  // The arms a question ticks: the Conveyor arm; it and Claude alone; or every ready arm (6 at most).
  function armsFor(q) {
    if (q === 'value') return new Set(offered().filter((a) => a.state === 'ready').slice(0, 6).map((a) => a.name));
    return new Set((q === 'works' ? ['conveyor'] : ['conveyor', 'solo']).filter((x) => offered().some((a) => a.name === x)));
  }
  const planOf = () => { const p = K.B.plan; if (!p.arms) p.arms = armsFor(p.q); return p; };
  const picked = () => offered().filter((a) => planOf().arms.has(a.name));

  // ---- the Conveyor version and the run settings ----
  const versions = () => K.list(K.benchOf().versions).filter((v) => K.obj(v) && typeof v.name === 'string');
  const engineOf = () => (planOf().engine === 'commit' ? planOf().commit : planOf().engine);
  const FULL = /^[0-9a-f]{40}$/;
  // The commit a Conveyor arm builds with: a full commit ID typed, else the version's listed commit (main's: the one
  // listed, which the run reads again); null when it is not known.
  function commitOf() {
    const e = engineOf(), v = versions().find((x) => x.name === e);
    return FULL.test(e) ? e : v && typeof v.commit === 'string' ? v.commit : null;
  }
  // The task set and the limits every arm of the run shares (`--settings`, swe_settings): each its key, its label, what
  // it sets, why a value typed does not read (null when it reads, as swe_settings checks its shape; the build machine
  // still refuses more CPUs or memory than it has) and the value sent.
  const SETTINGS = [
    ['revision', 'Dataset revision', 'The dataset revision the tasks and their grade are read from.', (v) => (FULL.test(v) ? null : 'Type the full 40-character commit ID.'), String],
    ['seed', 'Order seed', 'The seed that puts the tasks in order.', (v) => (v.length <= 80 && Array.from(v).every((ch) => ch.charCodeAt(0) >= 32 && ch.charCodeAt(0) !== 127) ? null :'Type 1 to 80 characters, with no control character.'), String],
    ['cpus', 'CPUs', 'The CPUs of each task\'s container.', (v) => (/^[0-9]*\.?[0-9]+$/.test(v) && Number(v) > 0 ? null : 'Type a number above 0.'), Number],
    ['memory', 'Memory', 'The memory of each task\'s container, such as 600m or 4g.', (v) => { const m = /^([1-9][0-9]{0,6})([mg])$/.exec(v); return m && Number(m[1]) * (m[2] === 'g' ? 1024 : 1) >= 512 ? null : 'Type <n>m or <n>g, 512m or more.'; }, String],
    ['taskTimeout', 'Time limit', 'Seconds. The install of an arm and its run on one task can each take this long.', (v) => (/^[0-9]+$/.test(v) && Number(v) >= 60 && Number(v) <= 86400 ? null : 'Type a whole number of seconds from 60 to 86400.'), Number]];
  const setDefaults = () => ({ ...(K.obj(K.hist().set) || {}), ...(K.obj(K.hist().limits) || {}) });
  // The settings Start sends: each one typed that is not its default (a blank field is its default); null while one
  // does not read; {} when each is its default, and Start then sends none.
  function runSet() {
    const d = setDefaults(), out = {};
    for (const [k, , , why, as] of SETTINGS) {
      const v = typeof planOf().set[k] === 'string' ? planOf().set[k].trim() : '';
      if (v === '' || (d[k] !== undefined && v === String(d[k]))) continue;
      if (why(v)) return null;
      out[k] = as(v);
    }
    return out;
  }
  const setChanged = () => { const s = runSet(); return !s || Object.keys(s).length > 0; };
  function engineRow() {
    const row = h('div', 'bench-row bench-small'), pick = h('select', 'field'), vs = versions();
    pick.dataset.act = 'plan-engine'; pick.setAttribute('aria-label', 'Conveyor version');
    (vs.some((v) => v.name === 'main') ? vs : [{ name: 'main' }].concat(vs)).forEach((v) => {
      const o = h('option', null, v.name === 'main' && v.commit ? `main (${String(v.commit).slice(0, 7)})` : v.name); o.value = v.name; pick.append(o);
    });
    const other = h('option', null, 'a commit…'); other.value = 'commit'; pick.append(other);
    pick.value = planOf().engine;
    pick.addEventListener('change', () => { planOf().engine = pick.value; K.draw(); });
    row.append(h('span', 'bench-muted', 'Conveyor version'), pick);
    if (planOf().engine === 'commit') {
      const c = h('input', 'field mono');
      c.value = planOf().commit; c.dataset.act = 'plan-commit'; c.setAttribute('aria-label', 'Full commit ID'); c.placeholder = '40-character commit ID';
      c.addEventListener('change', () => { planOf().commit = c.value.trim(); K.draw(); });
      row.append(c);
    }
    row.append(h('span', 'bench-muted', 'Every Conveyor arm of the run builds with it.'));
    return row;
  }
  function settingsFold() {
    const d = setDefaults(), f = K.fold('plan-settings', 'Run settings', 'bench-settings');
    f.append(K.note(`Every arm of the run shares them: the tasks of ${d.dataset || 'SWE-bench Verified'} in the order of the seed, and the limits of each task's container. A blank field takes its default.`));
    SETTINGS.forEach(([k, label, what, why]) => {
      const row = h('div', 'bench-row bench-small'), x = h('input', k === 'revision' ? 'field mono' : 'field'), v = planOf().set[k], no = v && v.trim() ? why(v.trim()) : null;
      x.value = v === undefined ? String(d[k] === undefined ? '' : d[k]) : v; x.dataset.act = `set-${k}`; x.setAttribute('aria-label', label);
      if (no) x.setAttribute('aria-invalid', 'true');
      // Each key typed is kept at once, so a redraw while it is typed puts the text back; change reads it and redraws.
      x.addEventListener('input', () => { planOf().set[k] = x.value; });
      x.addEventListener('change', () => { planOf().set[k] = x.value.trim(); K.draw(); });
      row.append(h('span', 'bench-muted', label), x, h('span', 'bench-muted', `${what}${d[k] === undefined ? '' : ` Default: ${d[k]}.`}`));
      if (no) { const p = h('span', 'warn-note bench-set-why', no); p.dataset.why = k; row.append(p); }
      f.append(row);
    });
    return f;
  }

  // ---- the arms, the tasks and the cost ----
  // The tasks of the first n that the arm has a result for on the engine it would run (a Conveyor arm: the commit of
  // the version picked), reused at no cost; null (not known) with run settings changed: history's results keys and task
  // order are those of the default settings.
  function keptOf(a, n) {
    if (setChanged()) return null;
    const c = commitOf(), key = a.kind === 'conveyor' ? (c && typeof a.keyPrefix === 'string' ? `${a.keyPrefix}${c}` : null) : a.key;
    const k = K.keysOf().find((x) => x.key === key);
    return k ? K.list(k.at).filter((i) => Number.isInteger(i) && i < n).length : 0;
  }
  // One arm's part of the run: the tasks it runs (the rest reused; each when that is not known), its usual and worst
  // sessions, minutes and dollars (each session at the mean list price of the project's own priced sessions; null with
  // none to take it from).
  function costOf(a, n) {
    const p = K.obj(a.perTask) || { usual: 1, worst: 1, minutes: 10 }, reused = keptOf(a, n), todo = n - (reused || 0), one = K.num(p.session);
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
    const box = h('input'), [word, tone] = ARM_STATE[a.state] || [String(a.state), 'quiet'], k = keptOf(a, n), p = K.obj(a.perTask);
    box.type = 'checkbox'; box.checked = planOf().arms.has(a.name); box.disabled = a.state === 'not offered'; box.dataset.act = `arm-${a.name}`; box.setAttribute('aria-label', a.label);
    box.addEventListener('change', () => { if (box.checked) planOf().arms.add(a.name); else planOf().arms.delete(a.name); K.draw(); });
    return [box, K.armSaid({ s: a.s, label: a.label }), [K.chip(word, tone), a.why ? h('span', 'bench-tie', a.why) : ''], { v: K.usd(perTask(a)), c: 'r' },
      { v: p && K.num(p.minutes) !== null ? String(p.minutes) : K.NOT_KEPT, c: 'r' }, { v: k === null ? 'not known' : a.kind === 'conveyor' && !k ? '0 (new engine)' : String(k), c: 'r' }];
  }
  function armsTable(n) {
    const arms = K.paint(K.armsOf().map((a) => ({ ...a, arm: a.name })));
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
    s.append(tbl, h('h3', 'bench-h', 'Tasks'), line, range, b, engineRow(), settingsFold());
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
    const was = c && s && st.n >= 3 ? `, and Conveyor against Claude alone was ${Math.round((K.figsOf(c, st.shared).k - K.figsOf(s, st.shared).k) / st.n * 100)} points in the last study` : '';
    if (q === 'works') return n <= 10 ? ['Right size: enough to see a break, cheap.', 'ok'] : ['More than you need to see a break.', 'warn'];
    if (q === 'value') return arms.length < 3 ? ['Pick at least 3 arms to compare value.', 'warn'] : [`Ranks ${arms.length} arms. Arms closer than ${K.noisePct(n, true)} share a tier.`, 'ok'];
    const g = versionGaps(), vers = !g ? ' A 10-point gap needs 200 tasks.' : ` Two Conveyor versions differed by ${g.min.pts === g.max.pts ? `${g.min.pts} points` : `${g.min.pts} to ${g.max.pts} points`} in the last study: a ${g.min.pts}-point gap needs ${g.min.need} tasks.`;
    return det <= 0.2 ? [`Good for arms: a gap of ${K.noisePct(n)} or more shows${was}.${vers}`, 'ok']
      : [`Too small: only a gap of ${K.noisePct(n)} or more shows${was}. Try 50 tasks or more.`, 'warn'];
  }
  // The command the page shows and Start sends: the run's arguments after `run`, in the order of the arms, then the
  // Conveyor version (a run with a Conveyor arm on another engine than main) and the run settings changed.
  function argsOf(n, arms) {
    const e = engineOf(), set = runSet() || {}, conv = arms.some((a) => a.kind === 'conveyor');
    return [String(n), ...arms.flatMap((a) => ['--arm', a.name]), ...(conv && e !== 'main' ? ['--engine', e] : []), ...(Object.keys(set).length ? ['--settings', JSON.stringify(set)] : [])];
  }
  // An argument as a shell takes it: quoted when it holds more than a word (the settings' JSON).
  const shellSaid = (x) => (/^[\w.:/-]+$/.test(x) ? x : `'${x.replace(/'/g, '\'\\\'\'')}'`);
  function whyNot(arms) {
    const l = K.live(), g = K.obj(K.hist().guard) || {}, held = arms.filter((a) => a.guard && g[a.guard] === true), unready = arms.filter((a) => a.state !== 'ready');
    if (l && l.state === 'running') return 'A run is going: stop it on the Live run page, or wait for its end.';
    if (!arms.length) return 'Tick an arm to start.';
    if (unready.length) return `Start waits for ${unready.map((a) => a.label).join(', ')}, not ready: check ${unready.length > 1 ? 'them' : 'it'} first.`;
    if (held.length) return `The usage guard is reached for ${held.map((a) => a.label).join(', ')}: no run starts while it stands.`;
    if (!runSet()) return 'A run setting does not read: correct it beside its field, under Run settings.';
    return arms.some((a) => a.kind === 'conveyor') && planOf().engine === 'commit' && !FULL.test(engineOf()) ? 'A commit is named by its full 40-character ID.' : null;
  }
  function startButton(n, arms) {
    const why = whyNot(arms), b = K.button('Start the run', 'btn-primary', 'start', `Start the run: ${K.plural(arms.length, 'arm')} on ${K.plural(n, 'task')}`, () => {
      const more = {};
      K.send('start', ['run', ...argsOf(n, arms)], (t) => {
        const m = RECEIPT.exec(t);
        if (!m) return t.replace(/^conveyor: /, '');
        Object.assign(more, { run: m[1], ended: m[2] === 'ended' });
        return m[2] === 'ended' ? `Run ${m[1]} ended: it reused the saved result of each task.` : `Run ${m[1]} started.`;
      }, () => K.readHist(true), null, more);
    });
    b.disabled = Boolean(why) || K.B.busy;
    return { b, why };
  }
  function checkButton(arms) {
    const need = arms.filter((a) => a.state !== 'ready' && a.state !== 'checking');
    const b = K.button('Check the arms first', '', 'check-arms', `Check ${need.map((a) => a.label).join(', ') || 'the arms'}`, () => K.send('check', ['arms', 'check', ...need.map((a) => a.name)],
      (t) => `${t.replace(/^conveyor: /, '')}. The arms are read again while their checks run.`, () => K.readHist(true)));
    b.disabled = !need.length || K.B.busy;
    return b;
  }
  function before(n) {
    const arms = picked(), parts = arms.map((a) => costOf(a, n)), q = planOf().q, [said, tone] = sizeSaid(q, n, arms);
    // The limits the run sends: each one typed under Run settings, else swe.json's.
    const lim = { ...(K.obj(K.hist().limits) || {}), ...(runSet() || {}) };
    const usd = parts.some((p) => p.usd === null) ? null : K.sum(parts.map((p) => p.usd)), mins = K.sum(parts.map((p) => p.minutes)), g = K.obj(K.hist().guard) || {};
    const held = arms.some((a) => a.guard && g[a.guard] === true), { b, why } = startButton(n, arms), rc = K.B.said.get(`${K.B.repo}\nstart`), receipt = K.saidAt('start');
    // The guard's last reported state, not a forecast of the run's usage; an arm with no guard (swe_guards: a Codex arm)
    // has no state to give. A short chip: the chip keeps its text on one line (app.css .chip).
    const guardSaid = held ? K.chip('reached: no run starts while it stands', 'bad') : arms.some((a) => a.guard) ? K.chip('not reached', 'ok') : K.chip('none for these arms', 'ok');
    const unknown = parts.some((p) => p.reused === null);
    if (receipt && rc && rc.run) receipt.append(' ', K.button(rc.ended ? 'Open its results' : 'Watch run', 'btn-sm', 'watch-run', `Open the run ${rc.run}`, () => K.go('run', rc.run)));
    const s = K.box('Before you start', `${K.plural(arms.length, 'arm')} × ${K.plural(n, 'task')}`, 'bench-before');
    s.append(K.callout(said, tone), K.kv([['Cost', [h('b', null, K.usd(usd)), ' ', h('span', 'bench-muted bench-small', 'at list prices')]], ['Machine time', [h('b', null, K.fmtMin(mins)), ' ', h('span', 'bench-muted bench-small', 'tasks run one after another')]],
      ['Sessions', `${K.sum(parts.map((p) => p.usual))} usual, ${K.sum(parts.map((p) => p.worst))} at worst`],
      ['Kept results', unknown ? 'not known with run settings changed: the estimate counts each task' : `${K.sum(parts.map((p) => p.reused))} task runs reused at no cost`],
      ['Usage guard', guardSaid],
      ['Belt', `Cards and the run share the machine. Each task's container gets ${K.num(lim.cpus) === null ? 'its' : lim.cpus} CPUs and ${lim.memory || 'its memory'}.`]]),
    K.add(h('div', 'bench-row'), [b, checkButton(arms)]), why ? K.add(h('p', 'bench-note bench-why'), why) : '', receipt, K.saidAt('check'),
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
