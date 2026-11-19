// SPDX-License-Identifier: Apache-2.0
// Cost: today and the last 7 days, per card and in total, at list prices. Its part: {cards | null, cardsError,
// sessions | null, sessionsError}. cards is {todayUsd, weekUsd, perLandedUsd, landedAfter, unpricedSteps, perCard: [each
// card worked on in the 7 days, landed, blocked or still on the belt, with its todayUsd and weekUsd; a restarted card is
// one row with runs, its dollars every run's] | null when the
// host gave no such rows, todayLeftOut, weekLeftOut, perLandedLeftOut, unpriced: [{repo, card, issue, step, time, why}]};
// sessions is every session on this machine ({todayUsd, weekUsd}). The three figures are the priced steps' dollars,
// and the steps they leave out are listed with why; a host from before that gives null for a figure with an
// unpriced step, shown as "not priced". A card's own sum with an unpriced step in it is null, never a part sum.
// Why a step has no price, in words: Claude Code's name for a message it wrote itself, with no model run
// ("<synthetic>"), is said as that.
const unpricedWhy = (why) => (typeof why === 'string' && why ? why.replace(/<synthetic>/g, 'none (a message Claude Code wrote itself)') : 'no reason given');
window.DASH_APP.panel({
  id: 'cost',
  title: 'Cost',
  // One column wide, so on a wide screen it fills the right column under Lanes, which ended a third of the way down
  // the page with the left column running on.
  size: 'small',
  tab: 'overview',
  phoneFolded: true,  // a report: on a phone it starts as its heading (issue 413)
  projects: true,  // filtered to one project, its cards and its own figures (cards' byRepo); the sessions stay the machine's
  // The figures always show; the rows are the lists under them (the steps not priced, the cost per card).
  rows: 5, // the step of its per-card list (ctx.more)
  // The live part holds the newest card rows and unpriced steps the snapshot keeps; the others of the same day come
  // from the history.
  older(d, o) {
    if (!d.cards || !o.cards || o.cards.day !== d.cards.day) return d;
    const joined = window.DASH_APP.joined;
    return Object.assign({}, d, { cards: Object.assign({}, d.cards, {
      perCard: joined(d.cards.perCard, o.cards.perCard, (x) => `${x.repo}/${x.card}`),
      unpriced: joined(d.cards.unpriced, o.cards.unpriced, (x) => `${x.repo}/${x.card}/${x.step}/${x.time}`),
    }) });
  },
  isEmpty(d) {
    // Empty only when both readings came back and both say nothing was spent: a reading that failed is said, by
    // render, never passed off as "no spend".
    const none = (s) => Boolean(s) && s.todayUsd === 0 && s.weekUsd === 0;
    return none(d.cards) && Boolean(d.cards.perCard) && d.cards.perCard.length === 0 && none(d.sessions);
  },
  empty(el, ctx) { el.append(ctx.state('empty', 'No spend in the last 7 days', 'Card costs show here as soon as a card runs.')); },
  error(el, message, ctx) { el.append(ctx.state('error', 'The Board could not read Cost', message)); },
  render(el, d, ctx) {
    const h = ctx.h, out = [];
    const figure = (key, label, value) => {
      const f = h('div', 'figure');
      f.dataset.figure = key;
      f.append(ctx.number(key, value, ctx.money), h('span', 'figure-label', label));
      return f;
    };
    if (d.cards) {
      const c = d.cards, figures = h('div', 'figures');
      figures.append(figure('today', 'Cards today', c.todayUsd), figure('week', 'Cards, last 7 days', c.weekUsd), figure('per', 'Per landed card (7 days)', c.perLandedUsd));
      out.push(figures);
      const after = Object.entries(c.landedAfter || {}).filter(([, n]) => n > 0)
        .map(([k, n]) => `${n} after ${k === 'more' ? 'more than 3' : k} ${k === '1' ? 'review' : 'reviews'}`);
      out.push(h('p', 'foot', after.length ? `Landed in the last 7 days: ${after.join(', ')}.` : 'No card landed in the last 7 days.'));
      if (c.unpricedSteps && Array.isArray(c.unpriced)) {
        // The figures are the priced steps' dollars; the steps left out are named, each with why.
        const left = [['today', c.todayLeftOut], ['in 7 days', c.weekLeftOut], ['per landed card', c.perLandedLeftOut]]
          .filter(([, n]) => n > 0).map(([k, n]) => `${n} ${k}`);
        out.push(h('p', 'warn-note', `${c.unpricedSteps} ${c.unpricedSteps === 1 ? 'step has' : 'steps have'} no price, and the figures above do not include ${c.unpricedSteps === 1 ? 'it' : 'them'}${left.length ? ` (${left.join(', ')})` : ''}:`));
        const ul = h('ul', 'rows compact');
        c.unpriced.forEach((x) => {
          const li = h('li', 'row'), head = h('div', 'row-main');
          head.append(ctx.tag(x.repo), ctx.issueLink(x), h('span', 'title', `${x.step} at ${ctx.when(x.time)}`), h('span', 'unknown', unpricedWhy(x.why)));
          li.append(head);
          ul.append(li);
        });
        out.push(ul);
      } else if (c.unpricedSteps) out.push(h('p', 'warn-note', `${c.unpricedSteps} ${c.unpricedSteps === 1 ? 'step has' : 'steps have'} no price, so the Board does not show a total that includes one.`));
      if (!c.perCard) out.push(h('p', 'warn-note', `${ctx.machine === 'the build machine' ? 'The build machine' : 'Conveyor'} did not give costs per card.`));
      else if (c.perCard.length) {
        // The rows are kept by project and card (ctx.list): a new part keeps the row of each card it still has, with its
        // focus, and draws again only a card that changed (every card when the panel is drawn whole, ctx.whole).
        const ul = el.querySelector(':scope > ul.per-card') || h('ul', 'rows compact per-card');
        const chips = { 'on the belt': ['On the belt', 'info'], landed: ['Landed', 'quiet'], closed: ['Already fixed', 'quiet'], blocked: ['Blocked', 'warn'], retried: ['Retried', 'quiet'] };
        const fill = (li, x) => {
          const json = JSON.stringify(x);
          if (li.json === json && !ctx.whole) return;
          li.json = json;
          const head = h('div', 'row-main');
          const chip = chips[x.state] || [String(x.state || 'Unknown'), 'quiet'];
          head.append(ctx.tag(x.repo), ctx.issueLink(x), h('span', 'title', x.title || 'untitled'), ctx.chip(chip[0], chip[1]));
          // A restarted card is one row: its dollars are every run's.
          if (typeof x.runs === 'number' && x.runs > 1) head.append(h('span', null, `${x.runs} runs`));
          head.append(h('span', 'num', `${ctx.money(x.todayUsd)} today`), h('span', 'num', `${ctx.money(x.weekUsd)} in 7 days`));
          li.replaceChildren(head);
        };
        // The costliest in the 7 days first; one not priced last. Sorted by project, the costliest first in each project.
        const usd = (x) => (typeof x.weekUsd === 'number' && Number.isFinite(x.weekUsd) ? x.weekUsd : -Infinity);
        const apart = ctx.sorted();
        const byCost = c.perCard.slice().sort((a, b) => (apart && a.repo !== b.repo ? (a.repo < b.repo ? -1 : 1) : usd(b) - usd(a)));
        out.push(h('h3', 'group-title', 'Per card, last 7 days'), ul, ctx.more('per-card', byCost, (xs) => ctx.list(ul, xs, (x) => `${x.repo}/${x.card}`, () => h('li', 'row'), fill)));
      }
    } else out.push(ctx.unread(`The Board could not read the card costs, so it shows none. ${ctx.retry}`, d.cardsError), ctx.restartButton());
    if (d.sessions) {
      const s = d.sessions, p = h('p', 'foot');
      p.append(h('span', null, 'Every session on this machine: '), ctx.number('s-today', s.todayUsd, ctx.money),
        h('span', null, s.todayComplete ? ' today, ' : ' today (the Board did not read every request), '), ctx.number('s-week', s.weekUsd, ctx.money), h('span', null, ' this limit week.'));
      out.push(p);
    } else out.push(ctx.unread('The Board could not read the cost of every session on this machine. It reads it again in about a minute.', d.sessionsError));
    // The per-card list stays in the panel while what is around it is drawn again, so a row in it keeps its focus.
    Array.from(el.childNodes).forEach((n) => { if (!out.includes(n)) n.remove(); });
    out.forEach((n, i) => { if (el.children[i] !== n) el.insertBefore(n, el.children[i] || null); });
  },
});
