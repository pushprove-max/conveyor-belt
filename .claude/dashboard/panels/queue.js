// SPDX-License-Identifier: Apache-2.0
// Queue: the open issues Conveyor takes next, in its order (follow-ups first). Its part: {next, held, awaitingDeploy,
// waiting, issuesError}; next, held and awaitingDeploy are null when GitHub did not list the issues, which is said,
// never shown as an empty queue. awaitingDeploy is the issues built and merged that stay open until the owner deploys them to
// PROD: the loop never picks them, and they are listed on their own under the queue, in the folded group "Built,
// waiting for your PROD deploy (N)". waiting is the issues that depend on one still open, in the folded group
// "Waiting on another card (N)", each shown as "Waiting on #N"; a next row forced past its wait is "Forced past #N".
// A next row with room is held back by the machine (its cap or its pause: "waiting for a machine slot: 2 of the
// machine cap 2 in use"), shown as said.
// How many open issues are held (held: the Board's Held column's count, by you, a label, a rule or a wait, but for
// the landed, not pushed ones); null when the open issues were not listed.
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
  // The panel's length counts the queued rows only: the groups under them are their headings until opened, so a long
  // group never pushes its heading out of view (a scroll inside the panel).
  rowSelector: '.queue-next > li',
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
    // The nodes a new part keeps: the queued list, the held line and the two groups. A row is kept by its project and
    // issue (ctx.list), so a group the owner opened stays open and its rows stay the same nodes.
    const kept = (sel, make) => el.querySelector(`:scope > ${sel}`) || make();
    const ol = kept('ol.queue-next', () => h('ol', 'rows numbered queue-next'));
    const rowKey = (x) => `${x.repo}#${x.issue}`;
    const newRow = () => h('li', 'row');
    // A kept row is drawn again from this part: its title, chips and times.
    const fill = (li, x, chips) => {
      const head = h('div', 'row-main'), meta = h('p', 'row-meta');
      head.append(ctx.issueLink(x), h('span', 'title', x.title || 'untitled'));
      meta.append(ctx.tag(x.repo), ...chips);
      li.replaceChildren(head, meta);
    };
    ctx.list(ol, d.next, rowKey, newRow, (li, q) => {
      const chips = [ctx.chip(q.priority || 'P3', q.priority === 'P0' || q.priority === 'P1' ? 'warn' : 'quiet')];
      if (q.followup) chips.push(ctx.chip('Follow-up', 'info'));
      if (q.retried) chips.push(ctx.chip('Retried', 'quiet'));
      // One forced past its wait (`control force`) keeps what it waits on.
      if (q.forced === true && Array.isArray(q.waitsFor) && q.waitsFor.length) chips.push(ctx.chip(`Forced past ${q.waitsFor.map(ctx.depRef).join(', ')}`, 'warn'));
      // The machine holds this card back (its cap, its load or its free memory): why, with the reading.
      if (q.room) chips.push(ctx.chip(q.room, 'warn'));
      fill(li, q, chips);
    });
    // How many are held, as the Board's Held column counts them, with a link to it (on the Control tab); an empty
    // queue says so first. Nothing is said of held when the open issues were not listed.
    const n = queueHeld(d), line = kept('p.queue-held', () => h('p', 'foot queue-held'));
    line.replaceChildren();
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
    // A group: a heading with its count in a native <details>, closed until the owner opens it. A group with no
    // issues is not drawn.
    const group = (key, title, items, chips) => {
      if (!items.length) return;
      const det = kept(`details.queue-group[data-group="${key}"]`, () => {
        const x = h('details', 'queue-group'), sum = h('summary');
        x.dataset.group = key;
        sum.append(h('h3', 'queue-group-head'));
        x.append(sum, h('ul', 'rows'));
        x.addEventListener('toggle', () => ctx.relength());
        return x;
      });
      det.querySelector('.queue-group-head').textContent = `${title} (${items.length})`;
      ctx.list(det.querySelector(':scope > ul'), items, rowKey, newRow, (li, x) => fill(li, x, chips(x)));
      parts.push(det);
    };
    // Waiting: an issue that depends on one still open is not picked until that one closes.
    // One forced past its wait (`control force`) is in next, tagged "Forced past #N", not here.
    // Each issue waited on says why it does not move when the snapshot gives its state (waitsOn): "#7 (held)".
    const waitsFor = (ns, on) => `Waiting on ${ns.map((n) => {
      const w = (Array.isArray(on) ? on : []).find((x) => x && x.issue === n);
      return `${ctx.depRef(n)}${w && typeof w.state === 'string' && w.state ? ` (${w.state})` : ''}`;
    }).join(', ')}`;
    group('waiting', 'Waiting on another card', queueWaits(d), (w) => [ctx.chip(waitsFor(w.waitsFor, w.waitsOn), 'quiet')]);
    group('built', 'Built, waiting for your PROD deploy', d.awaitingDeploy || [], (b) => (b.since ? [ctx.since(b.since, ' waiting')] : []));
    if (parts.length !== el.children.length || parts.some((x, i) => el.children[i] !== x)) el.replaceChildren(...parts);
  },
});
