// SPDX-License-Identifier: Apache-2.0
// The head line's tiles: seven figures between the name and the "Live" mark, each over a short label, each a
// link to the panel that holds its detail. Every figure is read from the panels' parts the page already has (data.js
// or the live feed): nothing is collected for them. A figure that is not there is a dash, never 0.
// A tile states the panel it opens and, unless it always shows, `drop`: when the bar is too narrow, the tile with the
// lowest drop goes first. read(part, ctx) gives {value (a number, or null: a dash), fmt, sub (the small text after
// the figure), tone (ok or bad), left (a figure that leaves something out: a mark, its words on hover, to a screen
// reader and under the figure at a tap), said (words for the hover and a screen reader only), dash (why a figure that
// was read is a dash, under it at a tap; without it a dash says it was not read)}. app.js draws the tiles,
// counts their figures and fits them to the bar. Only Needs you has a colour (red above zero), and Needs you is never
// dropped, so red always means "act" and is always in view.
(function () {
  'use strict';
  const count = (a) => (Array.isArray(a) ? a.length : null);
  const n = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : null);
  const plural = (k, one, many) => `${k} ${k === 1 ? one : many}`;
  // The most issues a host lists in the queue's `next` (conveyor.sh, `.[:10]`).
  const QUEUE_LISTED = 10;
  // A cost figure with steps left out for want of a price says so: never a bare low figure. A cost that was read and is
  // null was not priced (the price table could not be run), or, per landed card, no card landed in the 7 days
  // (snapshot.sh, perLanded): its dash says which, not that it was not read.
  function cost(c, figure, leftOut, ctx) {
    if (!c) return { value: null };
    const left = n(c[leftOut]) !== null ? c[leftOut] : n(c.unpricedSteps) || 0;
    const landed = c.landedAfter && typeof c.landedAfter === 'object' ? Object.values(c.landedAfter).reduce((s, v) => s + (n(v) || 0), 0) : null;
    return { value: n(c[figure]), fmt: ctx.money, left: left > 0 ? `${plural(left, 'step has', 'steps have')} no price` : null,
      dash: figure === 'perLandedUsd' && landed === 0 ? 'No card landed in 7 days' : 'Not priced' };
  }
  // The machine head, on every tab: the machine's one Conveyor over every project (the machine part, dashboard.sh):
  // its state, the slots in use across all projects of the slots in force ("7 of 10", the figure Belt 3D's deck gives:
  // dashboard_panels.sh, slots; the "On the belt" tile counts against the card cap instead), today's cost across projects, and
  // the one control that pauses or resumes the whole machine, "Pause all projects" (POST machine: it names no project
  // and changes no project's own record), and when paused who paused it and how to resume. With more than one project, the filter that shows one project only on every list (the one
  // project picker: the Board and the Rules show the project it picks), and the
  // sort that keeps each project's rows together. It is drawn again only when what it shows changed, so the control
  // keeps the focus; what the host answered stays until the state it changed is read.
  const STATE = { running: ['Running', 'ok'], paused: ['Paused', 'warn'], stopped: ['Stopped', 'bad'], 'not read': ['Not read', 'warn'] };
  let sent = null;  // the machine control sent last: {text, state: the state it was sent in}
  let folded = true;  // on a phone, the machine head is its one line (app.css) until tapped open
  function machine(el, d, ctx) {
    const h = ctx.h, repos = Array.isArray(d.repos) ? d.repos.filter((r) => typeof r === 'string') : [];
    if (sent && sent.state !== d.state) sent = null;
    // "Build machine" only when one is set up; on one machine Conveyor runs on this one (#112).
    const where = ctx.answerer === 'the build machine' ? 'Build machine' : 'This machine';
    const key = JSON.stringify([d.host, where, d.state, d.cap, d.used, d.todayUsd, d.todayLeftOut, repos, ctx.project(), ctx.sorted(), sent && sent.text]);
    if (el.dataset.key === key) return;
    const held = el.contains(el.ownerDocument.activeElement) ? el.ownerDocument.activeElement.dataset.act : null;
    el.dataset.key = key;
    el.dataset.state = String(d.state);
    const [word, tone] = STATE[d.state] || ['State not read', 'warn'];
    const name = h('span', 'machine-name', d.host ? `${where} ${d.host}` : where);
    const slots = h('span', 'machine-slots'), cost = h('span', 'machine-cost');
    slots.append(h('strong', null, n(d.used) === null ? '—' : n(d.cap) !== null ? `${d.used} of ${d.cap}` : String(d.used)),
      h('span', null, n(d.cap) !== null ? ' cards at once' : ' cards at once, no limit for the machine'));
    cost.append(h('strong', null, n(d.todayUsd) === null ? 'not priced' : ctx.money(d.todayUsd)),
      h('span', null, n(d.todayLeftOut) > 0 ? ` today, every project (${plural(d.todayLeftOut, 'step has', 'steps have')} no price)` : ' today, every project'));
    // On a phone (app.css) the head is this one line until a tap opens the rest; wider, the line is not shown.
    const fold = h('button', 'machine-fold'), act = h('span', 'machine-fold-act');
    fold.type = 'button'; fold.dataset.act = 'machine-fold';
    fold.append(h('span', null, [d.host || where, word, `${slots.firstChild.textContent} cards`, `${cost.firstChild.textContent} today`].join(' · ')), act);
    const unfold = (on) => { folded = !on; el.classList.toggle('open', on); fold.setAttribute('aria-expanded', String(on)); act.textContent = on ? 'Hide' : 'Show'; };
    unfold(!folded);
    fold.addEventListener('click', () => unfold(folded));
    const parts = [fold, name, ctx.chip(word, tone), slots, cost];
    // Pause and resume undo each other: one click, and the line that says it was done has Undo. While the change waits
    // for the loop (the state read is still the one it was sent in) the button gives way to that line. An Undo that went
    // through takes back a change the loop never showed: the state read is right again, so the button comes back.
    const send = (act, back) => {
      const say = (text, undo) => { sent = { text, state: d.state, undo }; el.dataset.key = ''; machine(el, d, ctx); };
      ctx.post('machine', { action: act }).then((r) => r.text().then((t) => (r.ok
        ? [`${act === 'pause' ? 'Paused' : 'Resumed'} every project. The head shows it in about a minute.`, back ? null : act === 'pause' ? 'resume' : 'pause']
        : [`Not changed: ${String(t).trim() || `${ctx.answerer} answered ${r.status}`}`, null])),
      () => [`Not changed: ${ctx.answerer} did not answer. Check it is on, then try again.`, null]).then(([text, undo]) => say(text, undo));
    };
    if ((d.state === 'paused' || d.state === 'running' || d.state === 'stopped') && !(sent && sent.undo)) {
      const act = d.state === 'paused' ? 'resume' : 'pause';
      // Named by its scope, so it is not taken for one project's pause or the Board's.
      const b = h('button', 'btn', act === 'pause' ? 'Pause all projects' : 'Resume all projects');
      b.type = 'button'; b.dataset.act = `machine-${act}`;
      b.title = act === 'pause' ? 'No project starts a new card; cards running finish. No project\'s own pause or cap changes.' : 'Each project picks again as its own record says.';
      b.addEventListener('click', () => { b.disabled = true; send(act); });
      // What it does, printed at phone width (app.css, .phone-note), where no hover text shows.
      parts.push(b, h('span', 'phone-note', b.title));
    }
    // Paused: who paused it and how to start it again, in one line.
    const why = ctx.pausedSaid(d.state, null, null);
    if (why) parts.push(h('span', 'machine-paused', why));
    if (repos.length > 1) {
      const pick = h('label', 'machine-filter'), sel = h('select', 'field'), all = h('option', null, 'All projects');
      sel.dataset.act = 'project';
      all.value = ''; sel.append(all);
      repos.forEach((r) => { const o = h('option', null, r); o.value = r; sel.append(o); });
      sel.value = ctx.project() || '';
      sel.addEventListener('change', () => ctx.setProject(sel.value || null));
      pick.append(h('span', 'board-label', 'Show'), sel);
      const sort = h('label', 'machine-sort'), box = h('input');
      box.type = 'checkbox'; box.dataset.act = 'psort'; box.checked = ctx.sorted();
      box.addEventListener('change', () => ctx.setProjectSort(box.checked));
      sort.append(box, h('span', null, 'Sort by project'));
      parts.push(pick, sort);
    }
    const note = h('span', 'machine-note');
    if (sent) note.append(sent.undo ? ctx.undoLine(sent.text, () => send(sent.undo, true)) : sent.text);
    note.setAttribute('role', 'status');
    parts.push(note);
    el.replaceChildren(...parts);
    if (held) { const again = el.querySelector(`[data-act="${held}"]`); if (again) again.focus({ preventScroll: true }); }
  }
  window.DASH_APP.head({
    label: 'At a glance',
    machine: { part: 'machine', draw: machine },
    tiles: [
      { key: 'today', label: 'Today', panel: 'cost',
        read: (part, ctx) => cost(part('cost') && part('cost').cards, 'todayUsd', 'todayLeftOut', ctx) },
      { key: 'week', label: '7 days', panel: 'cost', drop: 1,
        read: (part, ctx) => cost(part('cost') && part('cost').cards, 'weekUsd', 'weekLeftOut', ctx) },
      { key: 'per', label: 'Per landed card', panel: 'cost', drop: 2,
        read: (part, ctx) => cost(part('cost') && part('cost').cards, 'perLandedUsd', 'perLandedLeftOut', ctx) },
      // Cards on the belt of the slots in force, in any step and waiting or not; a card that lands (offCap), or has
      // landed and waits for its push, holds no slot (belt.js).
      { key: 'belt', label: 'On the belt', panel: 'belt', drop: 5,
        read: (part) => {
          const b = part('belt');
          const all = b && Array.isArray(b.cards) ? b.cards.filter((c) => !(c && (c.landed || c.offCap))).length : null;
          // The loop's own count while a snapshot is behind the card records (the part's building), as belt.js counts.
          const cards = all !== null && n(b.building) !== null ? b.building : all;
          return { value: cards, sub: cards !== null && n(b.cap) !== null ? `of ${b.cap}` : null };
        } },
      // Issues ready to be picked, then those held: by the owner, by a label or by a rule as the Board splits the open
      // issues, or, without that split, as the queue counts them. The queue's `next` lists only the first
      // QUEUE_LISTED of each host, so the count of ready issues is the Board's split when it has one; without it, a
      // list that may have been cut short is no count: a dash.
      { key: 'queued', label: 'Queued', panel: 'queue', drop: 4,
        read: (part) => {
          const q = part('queue'), board = part('board');
          const split = board && board.open && board.open.split;
          const listed = q ? count(q.next) : null;
          const queued = split && n(split.queued) !== null ? split.queued : listed !== null && listed < QUEUE_LISTED ? listed : null;
          let held = null;
          if (split && n(split.you) !== null && n(split.labelOrRule) !== null) held = split.you + split.labelOrRule;
          else if (q && n(q.held) !== null) held = q.held;
          return { value: queued, sub: queued !== null && held !== null ? `· ${held} held` : null };
        } },
      { key: 'landed', label: 'Landed today', panel: 'landed', drop: 3,
        read: (part) => { const l = part('landed'), k = l ? count(l.cards) : null; return { value: k }; } },
      // Cards stopped for the owner: waiting for their yes, or blocked. Red when any, green at none. With more than
      // one project on the host, each project's count follows, so a block in the project not on screen is seen.
      { key: 'needs', label: 'Needs you', panel: 'needs',
        read: (part) => {
          const c = part('needs') && part('needs').cards;
          const k = c && Array.isArray(c.waiting) && Array.isArray(c.blocked) ? c.waiting.length + c.blocked.length : null;
          const repos = part('board') && Array.isArray(part('board').repos) ? part('board').repos : [];
          const per = k !== null && repos.length > 1 ? repos.map((r) => `${r} ${c.waiting.concat(c.blocked).filter((x) => x && x.repo === r).length}`).join(' · ') : null;
          return { value: k, tone: k === null ? null : k > 0 ? 'bad' : 'ok', sub: per ? `· ${per}` : null,
            said: k > 0 ? `${plural(k, 'card is', 'cards are')} stopped for you${per ? ` (${per})` : ''}` : null };
        } },
    ],
  });
}());
