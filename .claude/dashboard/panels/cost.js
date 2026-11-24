// SPDX-License-Identifier: Apache-2.0
// Cost: today and the last 7 days, per card and in total, at list prices. Its part: {cards | null, cardsError,
// sessions | null, sessionsError}. cards is {todayUsd, weekUsd, perLandedUsd, landedAfter, unpricedSteps, perCard: [each
// card worked on in the 7 days, landed, blocked or still on the belt, with its todayUsd and weekUsd; a restarted card is
// one row with runs, its dollars every run's] | null when the
// host gave no such rows, todayLeftOut, weekLeftOut, perLandedLeftOut, todayEstimate, weekEstimate, perLandedEstimate
// (the priced steps of each figure priced as an estimate: the figure, and a card row's, then has `~`; a pick row's
// estimate the same), unpriced: [{repo, card, issue, step, time, why}],
// picks: [the rule Pick settings' cards, one row a group and builder choice: {repo, group, model, effort, cards, landed,
// usd (null when a step has no price), firstTry, reviews, open}] | null, trials: {dropped: [{repo, group, model, effort,
// cards}], flagged: [{repo, card, issue, group, files}]} (none from an older host), replays: [each project whose engine
// runs the judge replay study: {repo, last: its last replay (null when none ran), judge: its judge seat's settings}]};
// sessions is every session on this machine ({todayUsd, weekUsd}). The three figures are the priced steps' dollars,
// and the steps they leave out are listed with why; a host from before that gives null for a figure with an
// unpriced step, shown as "not priced". A card's own sum with an unpriced step in it is null, never a part sum.
// Why a step has no price, in words: Claude Code's name for a message it wrote itself, with no model run
// ("<synthetic>"), is said as that.
const unpricedWhy = (why) => (typeof why === 'string' && why ? why.replace(/<synthetic>/g, 'none (a message Claude Code wrote itself)') : 'no reason given');
// The judge replay study, beside the pick table: a project's last replay (how often the replay judge agreed with the
// recorded rulings, each finding where it differs, its cost against the recorded judge's), and Estimate, then Run, on
// one of the models the project's judge seat takes. Estimate asks the build machine for the cost and calls no model;
// Run costs money, so it takes a second click (ctx.twice). What was picked, the estimate and the answer stay through
// a redraw (REPLAY, by project).
const REPLAY = new Map();
const replayCost = (ctx, v) => (typeof v === 'number' ? ctx.money(v) : 'unknown: a call has no price');
function replayEfforts(j, model) {
  const bare = String(model).replace(/^opencode:/, '');
  const cli = Object.keys(j.allowed || {}).find((k) => Array.isArray(j.allowed[k]) && j.allowed[k].includes(bare));
  const e = cli && j.clis && j.clis[cli] ? j.clis[cli].efforts : null;
  return Array.isArray(e) ? e.filter((x) => typeof x === 'string') : [];
}
function replayBox(r, ctx) {
  const h = ctx.h, box = h('div', 'replay'), x = r.last, s = REPLAY.get(r.repo) || {};
  REPLAY.set(r.repo, s);
  box.dataset.repo = r.repo;
  const head = h('h3', 'group-title');
  head.append(h('span', null, 'Judge replay '), ctx.tag(r.repo));
  box.append(head);
  if (x && typeof x === 'object') {
    box.append(h('p', 'foot replay-last', `${ctx.modelName(x.model)}${x.effort ? ` ${x.effort}` : ''}, ${ctx.when(x.time)}: it agreed with the recorded judge on ${x.agree} of ${x.findings} findings of ${x.reviews} reviews.`
      + (x.unanswered ? ` ${x.unanswered} got no answer.` : '') + (x.skipped ? ` ${x.skipped === 1 ? '1 review was left out: it had' : `${x.skipped} reviews were left out: they had`} no diff, or not the diff that ${x.skipped === 1 ? 'its' : 'their'} judge read.` : '')
      + ` Cost: ${replayCost(ctx, x.usd)}; the recorded judge cost ${replayCost(ctx, x.recordedUsd)} on the same reviews.`));
    if (Array.isArray(x.differ) && x.differ.length) {
      const ul = h('ul', 'rows compact replay-differ');
      x.differ.forEach((d) => {
        const li = h('li', 'row');
        li.append(h('div', 'row-main', `#${d.issue} ${d.finding}`), h('p', 'row-meta', `The recorded judge: ${d.recorded}. The replay: ${d.replay}${d.reason ? `, ${d.reason}` : ''}`));
        ul.append(li);
      });
      box.append(ul);
    }
  } else box.append(h('p', 'foot replay-last', 'No replay has run.'));
  const j = r.judge && typeof r.judge === 'object' ? r.judge : null;
  const choices = j && Array.isArray(j.choices) ? j.choices.filter((m) => typeof m === 'string') : [];
  if (!choices.length) { box.append(h('p', 'foot', 'The pack allows the judge no model, so no replay can run.')); return box; }
  if (!choices.includes(s.model)) s.model = choices[0];
  const efforts = replayEfforts(j, s.model);
  if (!efforts.includes(s.effort)) s.effort = efforts.includes('medium') ? 'medium' : efforts[0] || '';
  const opt = (v, text) => { const o = h('option', null, text); o.value = v; return o; };
  const m = h('select', null), e = h('select', null);
  m.dataset.act = 'replay-model'; e.dataset.act = 'replay-effort';
  m.setAttribute('aria-label', `The model of the replay judge of ${r.repo}`); e.setAttribute('aria-label', `The effort of the replay judge of ${r.repo}`);
  m.append(...choices.map((c) => opt(c, ctx.modelName(c))));
  e.append(...efforts.map((c) => opt(c, c)));
  m.value = s.model; e.value = s.effort; e.hidden = !efforts.length;
  m.addEventListener('change', () => { s.model = m.value; s.estimate = null; ctx.redraw(); });
  e.addEventListener('change', () => { s.effort = e.value; s.estimate = null; ctx.redraw(); });
  const args = () => [s.model].concat(s.effort ? [s.effort] : []);
  const btn = (text, act) => { const b = h('button', 'btn btn-quiet', text); b.type = 'button'; b.dataset.act = act; b.disabled = !!s.busy; return b; };
  const ask = (more, done) => {
    s.busy = true; s.said = 'Asking the build machine…'; ctx.redraw();
    ctx.post('control', { action: 'replay', args: args().concat(more), repo: r.repo })
      .then((res) => res.text().then((t) => done(res.ok, String(t).trim())), () => done(false, 'the build machine did not answer. Make sure that it is on. Then try again'))
      .then(() => { s.busy = false; ctx.redraw(); });
  };
  const est = btn('Estimate the cost', 'replay-estimate');
  est.addEventListener('click', () => ask(['--estimate'], (ok, t) => {
    let y = null;
    try { y = JSON.parse(t); } catch (err) { y = null; }
    s.estimate = ok && y && typeof y === 'object' && typeof y.reviews === 'number' ? y : null;
    s.said = s.estimate ? '' : `No estimate: ${t || 'the build machine gave none'}`;
  }));
  const acts = h('div', 'board-acts');
  acts.append(m, e, est);
  box.append(acts);
  if (s.estimate && s.estimate.model === s.model && (s.estimate.effort || '') === (s.effort || '')) {
    const y = s.estimate;
    box.append(h('p', 'foot replay-estimate', `About ${replayCost(ctx, y.usd)} to replay ${y.findings} findings of ${y.reviews} reviews: the token use of the recorded judge, at the price of this model. The recorded judge cost ${replayCost(ctx, y.recordedUsd)}.`
      + (y.skipped ? ` ${y.skipped === 1 ? '1 review is left out: it has' : `${y.skipped} reviews are left out: they have`} no diff, or not the diff that ${y.skipped === 1 ? 'its' : 'their'} judge read.` : '')));
    const run = btn('Run the replay', 'replay-run');
    ctx.twice(run, 'spend', 'Click again to run the replay', () => ask([], (ok, t) => {
      s.estimate = null;
      s.said = ok ? 'The replay started. Its result shows here when it ends.' : `Not started: ${t || 'the build machine gave no reason'}`;
    }));
    box.append(run);
  }
  const note = h('p', 'answer-note', s.said || '');
  note.setAttribute('aria-live', 'polite');
  box.append(note);
  return box;
}
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
    // est: how many of the figure's priced steps are priced as an estimate (the figure then has `~`).
    const figure = (key, label, value, est) => {
      const f = h('div', 'figure');
      f.dataset.figure = key;
      f.append(ctx.number(key, value, (v) => ctx.money(v, est > 0)), h('span', 'figure-label', label));
      return f;
    };
    if (d.cards) {
      const c = d.cards, figures = h('div', 'figures');
      figures.append(figure('today', 'Cards today', c.todayUsd, c.todayEstimate), figure('week', 'Cards, last 7 days', c.weekUsd, c.weekEstimate),
        figure('per', 'Per landed card (7 days)', c.perLandedUsd, c.perLandedEstimate));
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
          head.append(h('span', 'num', `${ctx.money(x.todayUsd, x.todayEstimate > 0)} today`), h('span', 'num', `${ctx.money(x.weekUsd, x.weekEstimate > 0)} in 7 days`));
          li.replaceChildren(head);
        };
        // The costliest in the 7 days first; one not priced last. Sorted by project, the costliest first in each project.
        const usd = (x) => (typeof x.weekUsd === 'number' && Number.isFinite(x.weekUsd) ? x.weekUsd : -Infinity);
        const apart = ctx.sorted();
        const byCost = c.perCard.slice().sort((a, b) => (apart && a.repo !== b.repo ? (a.repo < b.repo ? -1 : 1) : usd(b) - usd(a)));
        out.push(h('h3', 'group-title', 'Per card, last 7 days'), ul, ctx.more('per-card', byCost, (xs) => ctx.list(ul, xs, (x) => `${x.repo}/${x.card}`, () => h('li', 'row'), fill)));
      }
      // The rule Pick settings: one row a group and builder choice, of every card it picked. The spend is every step of
      // those cards and of the earlier blocked, stopped and retried cards of their issues, over the cards that landed; one step with no price makes it unknown.
      if (Array.isArray(c.picks) && c.picks.length) {
        const t = h('table', 'tests-table picks'), head = h('tr');
        ['Project', 'Group', 'Builder', 'Cards', 'Spend per landed card', 'Landed with no retry', 'Review rounds per landed card', 'Still open']
          .forEach((x) => head.append(h('th', null, x)));
        t.append(head);
        const share = (n, of) => (of > 0 ? `${Math.round((n / of) * 100)}%` : 'none landed');
        c.picks.forEach((x) => {
          const tr = h('tr');
          tr.dataset.group = x.group;
          const spend = x.usd === null ? 'unknown: a step has no price' : x.landed > 0 ? ctx.money(x.usd / x.landed, x.estimate > 0) : 'none landed';
          [x.repo, x.group, `${ctx.modelName(x.model)}${x.effort ? ` ${x.effort}` : ''}`, String(x.cards), spend, share(x.firstTry, x.landed),
            x.landed > 0 ? (x.reviews / x.landed).toFixed(2) : 'none landed', String(x.open)].forEach((v) => tr.append(h('td', null, v)));
          t.append(tr);
        });
        const wrap = h('div', 'tests-scroll'); // one column wide: the table scrolls across
        wrap.append(t);
        out.push(h('h3', 'group-title', 'Pick settings, by group and builder'), wrap);
      }
      // The rule's trials: each group whose challenger two blocked trial cards dropped, and each trial card whose change
      // touches pipeline files its issue does not name.
      const trials = c.trials || {}, dropped = Array.isArray(trials.dropped) ? trials.dropped : [], flagged = Array.isArray(trials.flagged) ? trials.flagged : [];
      if (dropped.length || flagged.length) {
        const ul = h('ul', 'trials');
        dropped.forEach((x) => {
          const li = h('li', 'row', `${x.repo}: no more trials in ${x.group}. Two trial cards on ${ctx.modelName(x.model)}${x.effort ? ` ${x.effort}` : ''} were blocked (${x.cards.join(', ')}), so cards in this group build on the default builder.`);
          li.dataset.dropped = x.group;
          ul.append(li);
        });
        flagged.forEach((x) => {
          const li = h('li', 'row', `${x.repo} #${x.issue}: this trial card changes pipeline files that its issue does not name: ${x.files.join(', ')}. Its review and judge use the project's settings, unless you set them for the issue.`);
          li.dataset.flagged = x.card;
          ul.append(li);
        });
        out.push(h('h3', 'group-title', 'Pick settings trials'), ul);
      }
      if (Array.isArray(c.replays)) c.replays.forEach((r) => { if (r && typeof r.repo === 'string') out.push(replayBox(r, ctx)); });
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
