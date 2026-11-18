// SPDX-License-Identifier: Apache-2.0
// Queue: the open issues Conveyor takes next, in its order (follow-ups first). Its part: {next, held, awaitingDeploy,
// waiting, issuesError}; next, held and awaitingDeploy are null when GitHub did not list the issues, which is said,
// never shown as an empty queue. awaitingDeploy is the issues built and merged that stay open until the owner deploys them to
// PROD: the loop never picks them, and they are listed on their own under the queue. waiting is the issues
// that depend on one still open, each shown as "Waiting on #N"; a next row forced past its wait is "Forced past #N".
// A next row with room is held back by the machine (its cap or its pause: "waiting for a machine slot: 2 of the
// machine cap 2 in use"), shown as said.
// How many open issues are held (held: the Board's Held column's count, by you, a label, a rule or a wait); null
// when the open issues were not listed.
const queueHeld = (d) => (d && typeof d.held === 'number' && d.held >= 0 ? d.held : null);
// The issues listed under "Waiting on another card": one forced past its wait is in next, so not here.
const queueWaits = (d) => (d.waiting || []).filter((w) => Array.isArray(w.waitsFor) && w.waitsFor.length && w.forced !== true);
window.DASH_APP.panel({
  id: 'queue',
  title: 'Queue',
  size: 'small',
  tab: 'overview',
  projects: true,  // filtered to one project, held is that project's own (the part's byRepo)
  rows: 8,
  // The issues it would pick and those waiting on another card: every queued issue still open.
  count: (d) => (d.next ? d.next.length + queueWaits(d).length : null),
  isEmpty: (d) => Array.isArray(d.next) && d.next.length === 0 && !(d.awaitingDeploy || []).length && !queueWaits(d).length,
  // Empty says whether issues are held, and where they are: an empty queue with none held is normal.
  empty(el, ctx, d) {
    const n = queueHeld(d);
    el.append(ctx.state('empty', 'The queue is empty', n ? `Holds keep ${n === 1 ? '1 issue' : `${n} issues`} back: see Held on the Control tab.`
      : n === 0 ? 'Nothing holds an open issue either: Conveyor has no issue to build.' : 'Conveyor has no open issue to pick.'));
  },
  error(el, message, ctx) { el.append(ctx.state('error', 'The Board could not read the queue', message)); },
  render(el, d, ctx) {
    const h = ctx.h;
    if (!d.next) { el.replaceChildren(h('p', 'warn-note', d.issuesError || 'GitHub did not list the open issues.')); return; }
    const ol = h('ol', 'rows numbered');
    d.next.forEach((q) => {
      const li = h('li', 'row');
      const head = h('div', 'row-main');
      head.append(ctx.issueLink(q), h('span', 'title', q.title || 'untitled'));
      const meta = h('p', 'row-meta');
      meta.append(ctx.tag(q.repo),ctx.chip(q.priority || 'P3', q.priority === 'P0' || q.priority === 'P1' ? 'warn' : 'quiet'));
      if (q.followup) meta.append(ctx.chip('Follow-up', 'info'));
      if (q.retried) meta.append(ctx.chip('Retried', 'quiet'));
      // One forced past its wait (`control force`) keeps what it waits on.
      if (q.forced === true && Array.isArray(q.waitsFor) && q.waitsFor.length) meta.append(ctx.chip(`Forced past ${q.waitsFor.map(ctx.depRef).join(', ')}`, 'warn'));
      // The machine holds this card back (its cap, its load or its free memory): why, with the reading.
      if (q.room) meta.append(ctx.chip(q.room, 'warn'));
      li.append(head, meta);
      ol.append(li);
    });
    // How many are held, as the Board's Held column counts them, with a link to it (on the Control tab); an empty
    // queue says so first. Nothing is said of held when the open issues were not listed.
    const n = queueHeld(d), line = h('p', 'foot queue-held');
    if (!d.next.length) line.append(n === null ? 'Nothing queued.' : 'Nothing queued. ');
    if (n === 0) line.append('Nothing holds an open issue.');
    else if (n) {
      line.append(`Holds keep ${n === 1 ? '1 issue' : `${n} issues`} back: `);
      const a = h('a', null, 'see Held');
      a.href = ctx.panelHref('board'); a.dataset.act = 'held-see';
      a.addEventListener('click', (e) => { if (e.button || e.ctrlKey || e.metaKey || e.shiftKey || e.altKey) return; e.preventDefault(); ctx.goTo('board'); });
      line.append(a, '.');
    }
    const parts = d.next.length ? [ol].concat(n === null ? [] : [line]) : [line];
    // Waiting: an issue that depends on one still open is not picked until that one closes.
    // One forced past its wait (`control force`) is in next, tagged "Forced past #N", not here.
    // Each issue waited on says why it does not move when the snapshot gives its state (waitsOn): "#7 (held)".
    const waitsFor = (ns, on) => `Waiting on ${ns.map((n) => {
      const w = (Array.isArray(on) ? on : []).find((x) => x && x.issue === n);
      return `${ctx.depRef(n)}${w && typeof w.state === 'string' && w.state ? ` (${w.state})` : ''}`;
    }).join(', ')}`;
    const waits = queueWaits(d);
    if (waits.length) {
      const list = h('ul', 'rows');
      waits.forEach((w) => {
        const li = h('li', 'row');
        const head = h('div', 'row-main');
        head.append(ctx.issueLink(w), h('span', 'title', w.title || 'untitled'));
        const meta = h('p', 'row-meta');
        meta.append(ctx.tag(w.repo),ctx.chip(waitsFor(w.waitsFor, w.waitsOn), 'quiet'));
        li.append(head, meta);
        list.append(li);
      });
      parts.push(h('p', 'foot', `Waiting on another card (${waits.length}):`), list);
    }
    const built = d.awaitingDeploy || [];
    if (built.length) {
      const list = h('ul', 'rows');
      built.forEach((b) => {
        const li = h('li', 'row');
        const head = h('div', 'row-main');
        head.append(ctx.issueLink(b), h('span', 'title', b.title || 'untitled'));
        const meta = h('p', 'row-meta');
        meta.append(ctx.tag(b.repo));
        if (b.since) meta.append(ctx.since(b.since, ' waiting'));
        li.append(head, meta);
        list.append(li);
      });
      parts.push(h('p', 'foot', `Built, waiting for your PROD deploy (${built.length}):`), list);
    }
    el.replaceChildren(...parts);
  },
});
