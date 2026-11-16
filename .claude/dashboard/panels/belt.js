// SPDX-License-Identifier: Apache-2.0
// On the belt: each card being built and where it is. Its part: {cards, cap}; a card is {repo, card,
// issue, title, url, parent, step, review, of, stepAt, landed, model, tokens, usd, reading, live ({turns, lastOutputAt,
// action} | null), reviews, track, start, pickedAt, priorSec, earlier, totalSec}, as `conveyor.sh snapshot` gives its
// belt. track is the six steps Build, Review, Fix,
// Test, Land, Push, each done, now, skipped, failed or todo with its measured seconds, the step in progress (at, label,
// since), reason (why Push failed), files and tests (a running test run's {run, of} and {done, of, failed}) and detail (every recorded step, shown on demand).
// Only what was measured is shown (no estimate of time from past cards): the time in the step, the
// time each finished step took, when the card was picked up and its overall time from then (a card resumed from a
// kept patch counts the earlier card's time and shows its first start). A card's row, and each step in it, is the
// same element from one refresh to the next, so only what changed is redrawn.
(function () {
  const BEAT_MS = 4000;  // the step in progress beats once in this long, with motion on
  const cap = (s) => s.charAt(0).toUpperCase() + s.slice(1);
  const num = (v) => typeof v === 'number' && Number.isFinite(v);
  // A count of tokens: 950, 412k, 1.3M.
  const count = (n) => (n < 1000 ? `${n}` : n < 999500 ? `${Math.round(n / 1000)}k` : `${(n / 1e6).toFixed(1)}M`);
  function doing(c, ctx) {
    // A card waiting on a same-file card runs no step: its track still names the landing it waits to begin.
    if (c.step === 'waiting') {
      const w = c.waitsOn && typeof c.waitsOn === 'object' ? c.waitsOn : {};
      return `Waiting on ${typeof w.name === 'string' && w.name ? w.name : num(w.issue) ? `#${w.issue}` : 'a card'}${w.state ? ` (${w.state})` : ''}`;
    }
    // A fix is named by what started it (ctx.fixNow), never by the review it follows; its reason is the pill's hover.
    if (c.track && typeof c.track.label === 'string' && /^fix\b/.test(c.track.label)) { const f = ctx.fixNow(c.track); return f ? [f.name, f.why] : 'Fix'; }
    if (c.track && typeof c.track.label === 'string' && c.track.label) return cap(c.track.label);
    if (c.step === 'review') return `Review ${typeof c.review === 'number' ? c.review : ''}${c.of ? ` of ${c.of}` : ''}`.replace(/\s+/g, ' ').trim();
    return { push: 'Pushing', issue: 'Waiting for the issue to close', brief: 'Writing the brief', build: 'Building', fix: 'Fixing', tests: 'Running the changed tests', landing: 'Landing' }[c.step] || `Step: ${c.step}`;
  }
  // A session's action as the stream gives it (lib/session.sh: "Bash: i=0; while …", "Edit: app.js", a Codex review's
  // "command: npm test", an OpenCode "bash: …", or a word, "writing", "thinking") in words: the tool's kind of work,
  // never the command or path itself (that is on tap). A tool called with nothing named ("Bash") is said the same way;
  // another tool by its name; a word, as it is.
  const ACTIONS = [[/^(bash|command)$/i, 'running a command'], [/^(read|grep|glob|ls|list)$/i, 'reading the code'],
    [/^(edit|multiedit|write|notebookedit|patch)$/i, 'changing the code'], [/^(webfetch|websearch)$/i, 'looking something up'],
    [/^(task|agent)$/i, 'handing part of the work to a helper']];
  function actionSaid(a) {
    const tool = /^([A-Za-z_]+)(:|$)/.exec(a), m = tool && ACTIONS.find(([re]) => re.test(tool[1]));
    if (m) return m[1];
    return tool && tool[2] === ':' ? `using ${tool[1]}` : a;
  }
  // The seconds since a running step's last output, counting each second: "6 s since its last output".
  const quietText = (iso, ctx) => `${ctx.took(Math.max(0, Math.floor((Date.now() - Date.parse(iso)) / 1000)))} since its last output`;
  function quiet(iso, ctx) {
    const el = ctx.h('time', 'live-quiet');
    if (Number.isNaN(Date.parse(iso))) { el.textContent = 'last output time not read'; return el; }
    el.dateTime = iso; el.dataset.outputAt = iso;
    el.textContent = quietText(iso, ctx);
    return el;
  }
  // When the card was picked up, and its overall time from then to now (the earlier cards' seconds added: its tooltip
  // then says so, and "Every step" shows those earlier attempts).
  function times(c, ctx) {
    const h = ctx.h, box = h('span', 'card-times');
    const start = c.start || c.pickedAt;
    if (!start) return box;
    box.append(h('span', null, `started ${ctx.when(start)}`), h('span', null, ' · '));
    let all = null;
    if (num(c.totalSec)) all = h('span', null, `${ctx.dur(c.totalSec)} overall`);
    else if (c.pickedAt) all = ctx.since(c.pickedAt, ' overall', num(c.priorSec) ? c.priorSec : 0);
    else box.append(h('span', null, 'overall time not read'));
    if (all) box.append(ctx.earlierTip(all, c.earlier));
    return box;
  }

  window.DASH_APP.panel({
    id: 'belt',
    title: 'On the belt',
    size: 'wide',
    tab: 'overview',
    projects: true,  // filtered to one project, cap is that project's own (the part's byRepo)
    rows: 5,  // a card is four lines: five of them fill the panel's default length
    // A card that has landed and waits for its push or for its issue to close holds no builder slot: it is not counted.
    count: (d) => { const n = d.cards.filter((c) => !c.landed).length; return typeof d.cap === 'number' ? `${n} of ${d.cap}` : n; },
    isEmpty: (d) => d.cards.length === 0,
    empty(el, ctx) { el.append(ctx.state('empty', 'The belt is empty', 'Conveyor builds no card now.')); },
    error(el, message, ctx) { el.append(ctx.state('error', 'The Board could not read the belt', message)); },
    // Each second, whether or not a new snapshot came: the time since a running step's last output counts on, and
    // the step in progress beats now and then (a short motion replayed by the clock, none under reduced motion).
    tick(el, ctx) {
      el.querySelectorAll('time[data-output-at]').forEach((n) => {
        const text = quietText(n.dataset.outputAt, ctx);
        if (n.textContent !== text) n.textContent = text;
      });
      // A step in progress grows on its card's timeline, its time counting on; nothing else on the page moves.
      el.querySelectorAll('.track-detail').forEach((det) => { if (det.retime) det.retime(); });
      if (!ctx.motion()) return;
      const t = Date.now();
      if (t - (el.beatAt || 0) < BEAT_MS) return;
      el.beatAt = t;
      el.querySelectorAll('.step6[data-state="now"] .step-chip, .tl-item[data-state="now"] .tl-bar').forEach((c) => { c.classList.remove('beat'); void c.offsetWidth; c.classList.add('beat'); });
    },
    render(el, d, ctx) {
      const h = ctx.h;
      if (!el.firstChild) el.append(h('ul', 'rows belt'));
      ctx.list(el.firstChild, d.cards, (c) => `${c.repo}:${c.card}`, () => {
        const li = h('li', 'row belt-card');
        li.append(h('div', 'row-main'), h('p', 'row-meta'), h('ol', 'track6'), h('p', 'track-now'), h('ul', 'reviews'), h('div', 'more'));
        return li;
      }, (li, c) => {
        const [head, meta, track, now, reviews, more] = li.children;
        head.replaceChildren(ctx.issueLink(c), h('span', 'title', c.title || 'untitled'));
        if (typeof c.parent === 'number' && c.parent > 0) head.append(h('span', 'parent', `↳ #${c.parent}`));
        const [said, why] = [].concat(doing(c, ctx)), pill = ctx.chip(said, c.track && c.track.reason ? 'bad' : 'info');
        if (why) ctx.tip(pill, why);
        head.append(times(c, ctx), pill);
        // The dollars and the tokens (the builder's and the reviewer's together) are the finished steps and the running one so far; before
        // any token is read there is no figure.
        const tok = c.tokens && num(c.tokens.claude) && num(c.tokens.codex) ? c.tokens.claude + c.tokens.codex : null;
        // One unwrapped piece of the meta row, dollars and tokens together a held width (app.css, .live-cost): it counts on as refreshes come.
        let cost = h('span', 'live-cost', 'no reading yet');
        if (c.reading) {
          cost = h('span', 'live-cost');
          cost.append(ctx.number(`usd:${c.card}`, c.usd, ctx.money), h('span', null, tok !== null ? ` · ${count(tok)} tokens so far` : typeof c.usd === 'number' ? ' so far' : ''));
        }
        meta.replaceChildren(ctx.tag(c.repo),h('span', null, ctx.modelName(c.model) || (c.step === 'tests' ? 'running tests' : 'no AI model in this step')), cost);
        const t = c.track && typeof c.track === 'object' ? c.track : null;
        track.hidden = !ctx.track(track, t);
        // The step in progress, measured: how long it has run, how far a running test run has got (its tests, else
        // its files: ctx.testProgress), why a push failed.
        const parts = [ctx.since((t && t.since) || c.stepAt, ' in this step')];
        const prog = ctx.testProgress(t);
        if (prog) parts.push(h('span', 'test-progress', prog));
        // The line is one line high (app.css, .track-now): a text cut to fit there carries its full text as its title,
        // and a tap opens it (a phone shows no title).
        const full = (cls, text) => ctx.tip(h('span', cls, text), text);
        if (t && t.reason) parts.push(full('failed', `Push failed: ${t.reason}`));
        // The running step's live fields, streamed as the session or review prints them: what it does now,
        // its model replies (turns; none for a test run, which runs no model), and how long since its last output.
        const live = c.live && typeof c.live === 'object' ? c.live : null;
        // What it does now, in words ("now: running a command"); the command or file itself on hover and tap.
        if (live && typeof live.action === 'string' && live.action) parts.push(ctx.tip(h('span', 'live-action', `now: ${actionSaid(live.action)}`), live.action));
        if (live && c.step !== 'tests' && num(live.turns) && live.turns > 0) parts.push(h('span', null, `${live.turns} model ${live.turns === 1 ? 'reply' : 'replies'}`));
        if (live && typeof live.lastOutputAt === 'string') parts.push(quiet(live.lastOutputAt, ctx));
        now.replaceChildren(...parts);
        // One line a finished review: its round, its verdict, its findings by level (the verdict alone when none were counted).
        const done = Array.isArray(c.reviews) ? c.reviews : [];
        reviews.hidden = done.length === 0;
        reviews.replaceChildren(...done.map((r) => {
          const row = h('li', 'review'), f = ctx.findings(r);
          row.append(ctx.reviewChip(r));
          if (f) row.append(h('span', null, f));
          // What the judge made of it (ctx.judged).
          const j = ctx.judged(r, c.card);
          if (j) row.append(j);
          return row;
        }));
        // Every recorded step and its time, on demand; it and its set-up stay open through a redraw, and the
        // keyboard's place in it stays where it was. The focus is put back without scrolling: a focus that scrolls
        // its element into view moved the page and the panel under the reader at each redraw.
        // A retried card has a new card id, so its row is new: until it has drawn once, what was open is taken from
        // the row of its latest earlier card id still shown ("Every step" and its earlier attempts stay open).
        // The places the keyboard can be: a fold, a step's bar, a step's "N slow files" button.
        const keys = 'summary, .tl-item, .tl-slow-open';
        let was = more.firstChild;
        const at = was ? Array.from(was.querySelectorAll(keys)).indexOf(li.ownerDocument.activeElement) : -1;
        if (!was && Array.isArray(c.earlier)) {
          const rows = Array.from(el.firstChild.children);
          const prev = c.earlier.slice().reverse().map((e) => e && rows.find((r) => r !== li && r.dataset.key === `${c.repo}:${e.card}`)).find(Boolean);
          was = prev ? prev.querySelector(':scope > .more > details.track-detail') : null;
        }
        const det = ctx.trackDetail(t, c.card, was, c.earlier);
        more.replaceChildren(det);
        if (at >= 0 && det.querySelectorAll(keys)[at]) det.querySelectorAll(keys)[at].focus({ preventScroll: true });
      });
    },
  });
}());
