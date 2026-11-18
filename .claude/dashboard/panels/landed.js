// SPDX-License-Identifier: Apache-2.0
// Landed today: the cards that landed, or closed their issue as already fixed. Its part: {day, cards}; a card is
// {repo, card, issue, title, url, parent, step, time, start, tookSec, earlier, usd, reviews, followups, pushed, rounds, fixes, track, batch, rollout}:
// rollout is its rollout actions ({action, fails, place} each: a step an operator takes to deploy it, no finding);
// rounds is its reviews in order (round, verdict, counts by level), fixes its fix rounds, track its six steps, start when its
// work was first picked up and tookSec its overall time from then to the landing (a card resumed from a kept patch
// counts the earlier card's time); batch the cards it landed with in one landing, itself among them (null: alone).
// A round also has fixed (a fix round followed it) and judge (what the judge made of it, shown by ctx.judged).
// Under the day's sum, the day's totals, one line a project: the findings the judge accepted and declined on the
// reviews of the cards that landed today, and the fix rounds of those cards. The live part holds the day's newest
// cards; the older ones come from the history (older below).
window.DASH_APP.panel({
  id: 'landed',
  title: 'Landed today',
  size: 'wide',
  tab: 'overview',
  projects: true,
  rows: 6,
  // The live part holds the newest cards of the day the snapshot keeps; the others of the same day come from the
  // history, and every card is drawn newest first.
  older: (d, o) => (o.day !== d.day ? d : Object.assign({}, d, {
    cards: window.DASH_APP.joined(d.cards, o.cards, (c) => `${c.repo}/${c.card}`).slice().sort((a, b) => (a.time < b.time ? 1 : a.time > b.time ? -1 : 0)),
  })),
  count: (d) => d.cards.length,
  isEmpty: (d) => d.cards.length === 0,
  empty(el, ctx) { el.append(ctx.state('empty', 'No card landed today', 'Landed cards show here with their reviews, time and cost.')); },
  error(el, message, ctx) { el.append(ctx.state('error', 'The Board could not read the landed cards', message)); },
  render(el, d, ctx) {
    const h = ctx.h;
    const total = d.cards.some((c) => typeof c.usd !== 'number') ? null : d.cards.reduce((a, c) => a + c.usd, 0);
    const sum = h('p', 'foot');
    sum.append(h('span', null, `${d.cards.length} ${d.cards.length === 1 ? 'card' : 'cards'}, `), ctx.number('total', total, ctx.money), h('span', null, ' at list prices'));
    const per = new Map();
    d.cards.forEach((c) => {
      const t = per.get(c.repo) || { accepted: 0, declined: 0, fixes: 0 };
      (Array.isArray(c.rounds) ? c.rounds : []).forEach((r) => {
        const j = r.judge && r.judge.ran === true ? r.judge : {};
        t.accepted += Number.isFinite(j.accepted) ? j.accepted : 0;
        t.declined += Number.isFinite(j.declined) ? j.declined : 0;
      });
      t.fixes += Number.isFinite(c.fixes) ? c.fixes : 0;
      per.set(c.repo, t);
    });
    const totals = h('div', 'day-totals');
    per.forEach((t, repo) => {
      const li = h('p', 'foot');
      li.append(ctx.tag(repo), h('span', null, `${t.accepted} ${t.accepted === 1 ? 'finding' : 'findings'} accepted, ${t.declined} declined, ${t.fixes} ${t.fixes === 1 ? 'fix round' : 'fix rounds'}`));
      totals.append(li);
    });
    const ul = h('ul', 'rows');
    // The collector gives them newest first.
    const row = (c) => {
      const li = h('li', 'row');
      const head = h('div', 'row-main');
      // The push and the close of the issue are the card's last step: "pushing" while it runs. With push off no step
      // runs (track.at null) and the track's label says what it waits for: "Landed, waiting for Push landed".
      const push = c.track && Array.isArray(c.track.steps) && c.track.steps[5] ? c.track.steps[5] : null;
      const waits = c.track && c.track.at == null && typeof c.track.label === 'string' && c.track.label ? c.track.label : null;
      let state = ctx.chip(push && push.state === 'now' ? 'Pushing' : waits || 'Landed, not pushed yet', 'warn');
      if (c.step === 'closed') state = ctx.chip('Already fixed', 'quiet');
      else if (push && push.state === 'failed') state = ctx.chip(String(c.track.reason || '').startsWith('GitHub did not close the issue') ? 'Issue still open' : 'Push failed', 'bad');
      else if (c.pushed) state = ctx.chip('Landed and pushed', 'ok');
      head.append(ctx.issueLink(c), h('span', 'title', c.title || 'untitled'));
      if (typeof c.parent === 'number' && c.parent > 0) head.append(h('span', 'parent', `↳ #${c.parent}`));
      head.append(state);
      const meta = h('p', 'row-meta');
      const took = ctx.dur(c.tookSec);
      // When it was picked up and its overall time to the landing; then when it landed.
      meta.append(ctx.tag(c.repo),h('span', null, c.start ? `started ${ctx.when(c.start)}` : 'start not read'), took ? ctx.earlierTip(h('span', null, `${took} overall`), c.earlier) : h('span', null, 'overall time not read'),
        h('span', null, `landed ${ctx.clock(c.time)}`), h('span', null, `${c.reviews} ${c.reviews === 1 ? 'review' : 'reviews'}`), h('span', 'num', ctx.money(c.usd)));
      if (Array.isArray(c.followups) && c.followups.length) meta.append(h('span', null, `follow-ups ${c.followups.map((n) => `#${n}`).join(' ')}`));
      li.append(head, meta);
      // Its rollout actions, beside its push state: what an operator must do, in order, to deploy it. No finding.
      (Array.isArray(c.rollout) ? c.rollout : []).forEach((r) => {
        if (r && typeof r.action === 'string') li.append(h('p', 'row-meta', `Before deploy: ${r.action}. Without it: ${r.fails}. At ${r.place}`));
      });
      // Its reviews in order (a review recorded with no counts shows its verdict alone); a card that landed on a NO-GO
      // says how many findings became follow-ups.
      const rounds = Array.isArray(c.rounds) ? c.rounds : [];
      if (rounds.length) {
        const left = rounds[rounds.length - 1].verdict === 'NO-GO' && Array.isArray(c.followups) && c.followups.length;
        const line = h('p', 'row-meta');
        rounds.forEach((r) => {
          const f = ctx.findings(r), s = ctx.survived(r);
          line.append(h('span', null, `Review ${r.round}: ${ctx.verdictSaid(r.verdict)}${f ? `, ${f}` : ''}${s ? `, ${s}` : ''}`));
          const j = ctx.judged(r, c.card);
          if (j) line.append(j);
        });
        if (left) line.append(h('span', null, `${left} became ${left === 1 ? 'a follow-up' : 'follow-ups'}`));
        li.append(line);
      }
      // The rows are drawn anew: the card's "Every step" drawn before (still in the panel) keeps it open through a redraw.
      const was = Array.from(el.querySelectorAll('details.track-detail')).find((x) => x.dataset.card === c.card);
      if (c.track && (Array.isArray(c.track.records) || Array.isArray(c.track.detail))) li.append(ctx.trackDetail(c.track, c.card, was, c.earlier, ctx.text.repoOf(c), c.repo));
      return li;
    };
    // The cards of one batch (batch: the cards that landed together, in one repo) are one landing: one row that
    // lists them, each with its own row inside. The list pages by landing, so a batch is never cut short.
    const landings = [];
    const batches = new Map();
    d.cards.forEach((c) => {
      if (!Array.isArray(c.batch) || c.batch.length < 2) { landings.push([c]); return; }
      const k = JSON.stringify([c.repo, c.batch]);
      if (!batches.has(k)) { batches.set(k, []); landings.push(batches.get(k)); }
      batches.get(k).push(c);
    });
    const landing = (cs) => {
      if (!Array.isArray(cs[0].batch) || cs[0].batch.length < 2) return row(cs[0]);
      const inner = h('ul', 'rows');
      const li = h('li', 'row batch');
      li.append(h('div', 'row-main', `One landing of ${cs[0].batch.length} cards`), inner);
      inner.append(...cs.map(row));
      return li;
    };
    el.replaceChildren(sum, totals, ul, ctx.more('cards', landings, (ls) => ul.replaceChildren(...ls.map(landing))));
  },
});
