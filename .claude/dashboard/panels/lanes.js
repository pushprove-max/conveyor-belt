// SPDX-License-Identifier: Apache-2.0
// Lanes: the owner's worktrees beside the belt, for each project (record) of the host file. Its part: {records:
// [{repo, fast, research}], cardsError}; a lane is null when the host file names no folder for it, else {present, branch,
// ahead, subject, dirty, run: {startedAt, lastAt, active, topic} | null}, and fast also carries landing: the card
// that lands its change ({state: none | belt | waiting | blocked | landed, ...}), null when the cards were not read.
// A project with neither lane named says "No lanes set up" and the command that makes one.
// A card that landed on an earlier day has no since: the lane says "on an earlier day", not a time.
(function () {
  const REASON_LINE = 100; // the most characters a blocked landing's reason line shows
  // The landing's line, and for a blocked one its reason's line too: a node, or a list of them.
  function landing(l, ctx, cardsError) {
    const x = l.landing, h = ctx.h, p = h('p', 'row-meta');
    // The reader's reason (it names files and internal parts) on tap only.
    if (!x) p.append(ctx.chip('Landing not read', 'warn'), ctx.tip(h('span', null, `The Board could not read the cards. ${ctx.retry}`), ctx.details(cardsError)), ctx.restartButton());
    else if (x.state === 'belt') p.append(ctx.chip('Landing: on the belt', 'info'), h('span', null, x.step === 'review' ? `review ${x.review} of ${x.of}` : x.step), ctx.since(x.since, ' in this step'));
    else if (x.state === 'waiting') p.append(ctx.chip('Landing: waiting for your yes', 'warn'), h('span', null, x.reason));
    else if (x.state === 'blocked') {
      // Its reason as one plain line of its own, under the chip and before the log ("Show output"): the reason's first
      // line, cut; the whole on hover.
      const said = typeof x.reason === 'string' ? x.reason.trim() : '', first = said.split('\n')[0];
      const why = h('p', 'reason landing-reason', !first ? 'no reason recorded' : first.length > REASON_LINE ? `${first.slice(0, REASON_LINE - 1)}…` : first);
      if (said !== why.textContent) why.title = said;
      p.append(ctx.chip('Landing: blocked', 'bad'));
      return [p, why];
    }
    else if (x.state === 'landed') p.append(ctx.chip('Landed', 'ok'), h('span', null, `${x.since ? `at ${ctx.clock(x.since)}` : 'on an earlier day'}; reset the lane to main before the next change`));
    else p.append(ctx.chip('Not landing', 'quiet'), h('span', null, 'conveyor.sh lane land starts it'));
    return p;
  }
  // What is true of the lane, the first that holds: a session working in it, uncommitted files, commits ahead of
  // main, else idle. A chip in the head and the sentence under it.
  function status(l, head, li, ctx) {
    const h = ctx.h, run = l.run, n = (k, one, many) => `${k} ${k === 1 ? one : many}`;
    let word, tone, line = null;
    if (run && run.active) {
      word = 'Working'; tone = 'ok';
      line = h('p', 'reason');
      line.append(h('span', null, `Working: ${run.topic || 'no prompt yet'}, last activity `), ctx.since(run.lastAt, ' ago'));
    } else if (typeof l.dirty === 'number' && l.dirty > 0) {
      word = 'Not committed'; tone = 'info'; line = h('p', 'reason', `${n(l.dirty, 'file', 'files')} changed, not committed`);
    } else if (typeof l.ahead === 'number' && l.ahead > 0) {
      word = 'Ahead of main'; tone = 'info'; line = h('p', 'reason', `${n(l.ahead, 'commit', 'commits')} ahead of main${l.subject ? `: ${l.subject}` : ''}`);
    } else if (l.ahead === 0) { word = 'Idle'; tone = 'quiet'; }
    else { word = 'Change not read'; tone = 'warn'; }
    head.append(ctx.chip(word, tone));
    if (line) li.append(line);
    const meta = h('p', 'row-meta');
    meta.append(h('span', null, l.branch ? `on ${l.branch}` : 'on no branch'));
    if (run && !run.active) meta.append(h('span', null, 'last session'), ctx.since(run.lastAt, ' ago'));
    li.append(meta);
  }
  const MAKE = 'conveyor.sh lane fast create';
  function lane(name, of, repo, l, ctx, more) {
    const h = ctx.h, li = h('li', 'row');
    const head = h('div', 'row-main');
    head.append(h('span', 'title', name + of));
    li.append(head);
    li.dataset.lane = name;
    li.dataset.repo = repo;
    if (!l.present) {
      head.append(ctx.chip('No worktree', 'quiet'));
      li.append(h('p', 'row-meta', `No ${name} worktree on the machine the dashboard runs on.`));
    } else more(li, head);
    return li;
  }
  window.DASH_APP.panel({
    id: 'lanes',
    title: 'Lanes',
    size: 'small',
    tab: 'overview',
    phoneFolded: true,  // a report: on a phone it starts as its heading (issue 413)
    projects: true,
    rows: 'all',  // every project's lanes, always all
    isEmpty: (d) => !Array.isArray(d.records) || d.records.length === 0,
    empty(el, ctx) { el.append(ctx.state('empty', 'No lanes set up', `Nobody set up a project on ${ctx.machine} yet. After you set one up, run ${MAKE} in its checkout to make its Fast lane.`)); },
    error(el, message, ctx) { el.append(ctx.state('error', 'The Board could not read the lanes', message)); },
    render(el, d, ctx) {
      const h = ctx.h, ul = h('ul', 'rows');
      for (const r of d.records) {
        const repo = String(r.repo), of = d.records.length > 1 ? ` (${repo})` : '';
        if (r.fast) ul.append(lane('Fast lane', of, repo, r.fast, ctx, (li, head) => {
          status(r.fast, head, li, ctx);
          const l = r.fast, open = typeof l.ahead === 'number' && l.ahead > 0;
          if (open) li.append(...[].concat(landing(l, ctx, d.cardsError)));
          // The rows are drawn anew: the lane's output drawn before stays open for the same card.
          const was = Array.from(el.querySelectorAll('li[data-lane="Fast lane"] > details.output')).find((x) => x.parentElement.dataset.repo === repo);
          // Its repository (the landing's repoUrl): the review's file paths link to their lines in it.
          const out = open && l.landing && l.landing.state === 'blocked' ? ctx.output(l.landing.tail, l.landing.card, null, was, l.landing.repoUrl) : null;
          if (out) li.append(out);
        }));
        if (r.research) ul.append(lane('Research lane', of, repo, r.research, ctx, (li, head) => status(r.research, head, li, ctx)));
        if (!r.fast && !r.research) {
          // A project whose record names no lane: not an error, and the command that makes one.
          const li = h('li', 'row'), head = h('div', 'row-main');
          head.append(h('span', 'title', `Lanes${of}`), ctx.chip('No lanes set up', 'quiet'));
          li.dataset.repo = repo;
          li.append(head, h('p', 'row-meta', `Run ${MAKE} in its checkout to make its Fast lane.`));
          ul.append(li);
        }
      }
      el.replaceChildren(ul);
    },
  });
}());
