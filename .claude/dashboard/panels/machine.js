// SPDX-License-Identifier: Apache-2.0
// Projects and Foremen: each project of the machine's one Conveyor in a section of its own, then each Foreman. Its
// part (dashboard.sh, machine): {host, state, cap, used, todayUsd, repos, projects, foremen, foremenError}; the machine's
// own figures are the machine head's (head.js), on every tab.
// A project is {repo, state, reason, loop, mode, cap, guard (the weekly-limit guard's percent | null), used, needs, belt, queue, held, order, rules, models, landedToday,
// todayUsd, todayLeftOut (the steps that cost leaves out for having no price)}: its own state, its cards holding a
// slot of its own cap, and its lists by issue (Needs you: its cards
// blocked or waiting for a yes, its issues waiting for the yes before their build and its open decisions; belt, queue in
// pick order, held (closed under "Held (N) · Show" until opened), the order its record pins, with titles), its rules, its two models and its judge (off, or its model). Its controls act on that project only:
// pause and resume here (POST control, with its repo; one click, with Undo on the line that says it was done), and every other one (hold, release, order, cap, retry, clear)
// on its Board and its Rules, which "Open its Board" and "Open its rules" show for that project. A list GitHub did not
// give is said, never shown as empty.
// A Foreman is {projects, group, held, since, lastWakeAt, waiting}: a project's own, or one of a group with its
// projects named; whether a session holds the role and since when, when it was last woken, and the wakes waiting on
// it. A project with no Foreman says so. The machine head's filter shows one project's section and its Foreman only.
(function () {
  const STATE = { running: 'ok', paused: 'warn', stopped: 'bad', 'paused by guard': 'warn', 'control record unreadable': 'bad' };
  // A state is said in the Board's words: its record's name for an unread record is not one of them.
  const cap1 = (s) => (s === 'control record unreadable' ? 'Settings not read' : s.charAt(0).toUpperCase() + s.slice(1));
  const num = (v) => typeof v === 'number' && Number.isFinite(v);
  const sent = new Map();  // repo -> {text, mode: the mode it was sent in}: what the host answered, until that mode changes

  const heldOpen = new Map();  // repo -> whether the owner opened its Held list (closed until then), through every redraw
  function issues(label, list, ctx, titled) {
    const h = ctx.h, p = h('p', 'project-list');
    p.dataset.list = label;
    p.append(h('span', 'project-list-name', list ? `${label} (${list.length})` : label));
    if (!list) p.append(h('span', 'unknown', 'not listed'));
    else if (!list.length) p.append(h('span', null, 'none'));
    // An open decision of the project's ledger names no issue: it is said as a decision, its question beside it.
    // titled: each issue's title is shown beside its number, not on hover only.
    else list.forEach((x) => {
      const a = x.decision ? h('span', 'decision', `decision: ${x.title || x.decision}`) : ctx.issueLink(x);
      if (x.title) a.title = x.title;
      if (titled && !x.decision && x.title) { const s = h('span', 'project-item'); s.append(a, h('span', 'project-item-title', x.title)); p.append(s); } else p.append(a);
    });
    return p;
  }
  // Held, which can run to hundreds of issues: "Held (209) · Show", closed until the owner opens it; open, each issue
  // with its title, one a line.
  function heldList(p, ctx) {
    const h = ctx.h, list = p.held;
    if (!list || !list.length) return issues('Held', list, ctx);
    const det = h('details', 'project-held'), sum = h('summary', 'project-list');
    det.dataset.list = 'Held';
    const word = h('span', 'project-show');
    sum.append(h('span', 'project-list-name', `Held (${list.length})`), word);
    const ul = h('ul', 'project-held-list');
    list.forEach((x) => { const li = h('li'); const a = ctx.issueLink(x); if (x.title) a.title = x.title; li.append(a, h('span', 'project-item-title', x.title || 'title not listed')); ul.append(li); });
    det.append(sum, ul);
    det.open = heldOpen.get(p.repo) === true;
    word.textContent = det.open ? '· Hide' : '· Show';
    det.addEventListener('toggle', () => { heldOpen.set(p.repo, det.open); word.textContent = det.open ? '· Hide' : '· Show'; ctx.relength(); });
    return det;
  }
  function rulesSaid(r) {
    if (!r || typeof r !== 'object') return 'Rules: not read';
    const on = ['P0', 'P1', 'P2', 'P3'].filter((k) => r[k] !== false);
    const never = Array.isArray(r.never) ? r.never : [];
    return `Rules: builds ${on.length ? on.join(', ') : 'no priority'}${r.followups === false ? ', no follow-ups' : ', follow-ups'}${never.length ? `; never ${never.join(', ')}` : ''}`;
  }
  const modelOf = (s) => (s && s.model ? `${s.model}${s.effort ? ` · ${s.effort}` : ''}` : 'not read');
  // The review's judge: off, or on with its model in force.
  const judgeOf = (j) => (j && j.on === false ? 'judge off' : `judge ${j && j.on === true ? modelOf(j) : 'not read'}`);

  function project(p, ctx, redraw) {
    const h = ctx.h, li = h('li', 'project');
    li.dataset.project = p.repo; li.dataset.state = String(p.state);
    const head = h('div', 'project-head'), name = h('h3', 'project-name');
    name.append(ctx.tag(p.repo));
    const slots = h('span', 'project-slots', `${num(p.used) ? p.used : '—'}${num(p.cap) ? ` of ${p.cap}` : ''} cards at once`);
    head.append(name, ctx.chip(p.state ? cap1(p.state) : 'State not read', STATE[p.state] || 'warn'), slots,
      h('span', null, `${p.landedToday} landed today`), h('span', 'num', `${ctx.money(p.todayUsd)} today${num(p.todayLeftOut) && p.todayLeftOut > 0 ? ` (${p.todayLeftOut} ${p.todayLeftOut === 1 ? 'step has' : 'steps have'} no price)` : ''}`));
    li.append(head);
    // Paused or stopped: who did it and how to start it again, in one line.
    const why = ctx.pausedSaid(p.state, p.repo, p.guard, p.reason);
    if (why) li.append(h('p', 'project-paused', why));
    if (p.reason) li.append(h('p', 'reason', p.reason));
    li.append(issues('Needs you', p.needs || [], ctx),issues('On the belt', p.belt || [], ctx), issues('Queue', p.queue, ctx), heldList(p, ctx));
    // The pinned issues with their titles, from the project's lists (waiting: a pinned issue waiting on a dependency is
    // in none of the lists shown).
    const titles = new Map([].concat(p.queue || [], p.held || [], p.waiting || [], p.belt || []).filter((x) => x && x.title).map((x) => [x.issue, x.title]));
    const order = Array.isArray(p.order) ? p.order.map((n) => ({ issue: n, title: titles.get(n) || null })) : null;
    li.append(issues('Pinned order', order, ctx, true));
    li.append(h('p', 'project-rules', rulesSaid(p.rules)));
    li.append(h('p', 'project-models', p.models ? `Builder ${modelOf(p.models.builder)}; reviewer ${modelOf(p.models.reviewer)}; ${judgeOf(p.models.judge)}` : 'Models: not read'));
    const acts = h('div', 'project-acts');
    const was = sent.get(p.repo);
    if (was && was.mode !== p.mode) sent.delete(p.repo);
    // Pause and resume undo each other: one click, and the line that says it was done has Undo. While the change waits
    // for the loop (the mode read is still the one it was sent in) the button gives way to that line. An Undo that went
    // through takes back a change the loop never showed: the mode read is right again, so the button comes back.
    const send = (act, back) => {
      // The project goes with the action: the host changes that project's record and no other.
      ctx.post('control', { action: act, args: [], repo: p.repo })
        .then((r) => (r.ok ? [`${act === 'pause' ? 'Paused' : 'Resumed'}. The page shows it in about a minute.`, back ? null : act === 'pause' ? 'resume' : 'pause']
          : r.text().then((t) => [`Not changed: ${String(t).trim() || `${ctx.answerer} answered ${r.status}`}`, null])),
        () => [`Not changed: ${ctx.answerer} did not answer. Make sure that it is on. Then try again.`, null])
        .then(([text, undo]) => { sent.set(p.repo, { text, mode: p.mode, undo }); redraw(); });
    };
    const now = sent.get(p.repo);
    const note = h('span', 'project-note');
    if (now) note.append(now.undo ? ctx.undoLine(now.text, () => send(now.undo, true)) : now.text);
    note.setAttribute('role', 'status');
    if ((p.mode === 'run' || p.mode === 'pause' || p.mode === 'stop') && !(now && now.undo)) {
      const act = p.mode === 'run' ? 'pause' : 'resume';
      const b = h('button', 'btn', act === 'pause' ? `Pause ${p.repo}` : `Resume ${p.repo}`);
      b.type = 'button'; b.dataset.act = act;
      b.title = act === 'pause' ? `${p.repo} picks no new card; its cards running finish. No other project changes.` : `${p.repo} picks again. No other project changes.`;
      b.addEventListener('click', () => { b.disabled = true; send(act); });
      // What it does, printed at phone width (app.css, .phone-note), where no hover text shows.
      acts.append(b, h('span', 'phone-note', b.title));
    } else if (!(now && now.undo)) acts.append(h('span', 'unknown', `Conveyor could not read its settings on ${ctx.machine}. You cannot pause it from here, and it picks no new card. Run Conveyor's control command on ${ctx.machine}: it says what is wrong.`));
    const open = (label, act, tab) => {
      const b = h('button', 'btn btn-quiet', label);
      b.type = 'button'; b.dataset.act = act;
      b.addEventListener('click', () => { ctx.pickRepo(p.repo); ctx.setTab(tab, true); });
      return b;
    };
    acts.append(open('Open its Board', 'open-board', 'control'), open('Open its rules', 'open-rules', 'rules'), note);
    li.append(acts);
    return li;
  }

  function foreman(f, ctx) {
    const h = ctx.h, li = h('li', 'foreman row'), names = (Array.isArray(f.projects) ? f.projects : []).map(String);
    li.dataset.projects = names.join(' '); li.dataset.held = String(f.held === true);
    const head = h('div', 'row-main');
    head.append(h('span', 'title', f.group ? `Foreman of the group ${names.join(', ')}` : `Foreman of ${names[0]}`));
    names.forEach((r) => head.append(ctx.tag(r)));
    const meta = h('p', 'row-meta');
    if (f.held) {
      head.append(ctx.chip('A session holds the role', 'ok'));
      if (f.since) { const s = h('span', null, 'claimed '); s.append(ctx.since(f.since, ' ago')); meta.append(s); } else meta.append(h('span', null, 'claimed: time not read'));
    } else {
      head.append(ctx.chip('No Foreman', 'quiet'));
      meta.append(h('span', null, `No Claude session is its Foreman now: open one in ${names.join(', ')} to take the role.`));
    }
    if (f.lastWakeAt) { const w = h('span', null, 'last woken '); w.append(ctx.since(f.lastWakeAt, ' ago')); meta.append(w); } else meta.append(h('span', null, 'never woken yet'));
    const waiting = Array.isArray(f.waiting) ? f.waiting : [];
    meta.append(h('span', null, waiting.length ? `${waiting.length} waiting on it` : 'nothing waiting on it'));
    li.append(head, meta);
    if (waiting.length) {
      const ul = h('ul', 'foreman-waiting');
      waiting.forEach((t) => ul.append(h('li', null, t)));
      li.append(ul);
    }
    return li;
  }

  function render(el, d, ctx) {
    const h = ctx.h, doc = el.ownerDocument, at = doc.activeElement;
    const held = at && el.contains(at) && at.dataset.act ? [at.closest('[data-project]') && at.closest('[data-project]').dataset.project, at.dataset.act] : null;
    const projects = h('ul', 'projects');
    (d.projects || []).forEach((p) => projects.append(project(p, ctx, () => render(el, d, ctx))));
    const out = [projects, h('h3', 'group-title', 'Foremen')];
    if (!Array.isArray(d.foremen)) out.push(ctx.unread('The Board could not read the Foremen, so it shows none. It reads them again in about a minute.', d.foremenError));
    else {
      // Filtered to one project, its Foreman only (its own, or its group's).
      const only = ctx.param('project'), repos = Array.isArray(d.repos) ? d.repos : [];
      const mine = only && repos.includes(only) ? d.foremen.filter((f) => Array.isArray(f.projects) && f.projects.includes(only)) : d.foremen;
      const ul = h('ul', 'rows foremen');
      mine.forEach((f) => ul.append(foreman(f, ctx)));
      out.push(mine.length ? ul : h('p', 'foot', `Nobody set up a project on ${ctx.machine}, so there is no Foreman to show.`));
    }
    el.replaceChildren(...out);
    if (held) { const again = el.querySelector(`.project[data-project="${String(held[0]).replace(/["\\]/g, '\\$&')}"] [data-act="${held[1]}"]`); if (again) again.focus({ preventScroll: true }); }
  }

  window.DASH_APP.panel({
    id: 'machine',
    title: 'Projects and Foremen',
    size: 'full',
    tab: 'control',
    rows: 'all',
    rowSelector: '.projects > li, .foremen > li',
    projects: true,
    count: (d) => (Array.isArray(d.projects) ? d.projects.length : null),
    isEmpty: (d) => !Array.isArray(d.projects) || d.projects.length === 0,
    empty(el, ctx) { el.append(ctx.state('empty', `No project on ${ctx.machine}`, `Nobody set up Conveyor for a project there yet: add one on ${ctx.machine}, and it shows here.`)); },
    error(el, message, ctx) { el.append(ctx.state('error', 'The Board could not read the projects', message)); },
    render,
  });
}());
