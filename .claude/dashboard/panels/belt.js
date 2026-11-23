// SPDX-License-Identifier: Apache-2.0
// On the belt: each card being built and where it is. Its part: {cards, cap, building (the loop's count now
// while a snapshot is behind the card records, else null), behind ([{repo, at}]: ctx.behind)}; a card is {repo, card,
// issue, title, url, parent, step, review, of, stepAt, landed, model, tokens, usd, reading, atEnd, live ({turns, lastOutputAt,
// action} | null), reviews, track, start, pickedAt, priorSec, earlier, totalSec, fromRecords}, as `conveyor.sh snapshot` gives its
// belt (fromRecords: a card started since the kept snapshot, from the card records, with no track or cost yet). track is the six steps Build, Review, Fix,
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

  // Every recorded step and its time, on demand: its steps and earlier attempts are drawn only while it is open
  // (ctx.trackDetail); closed, it is its summary alone (ctx.trackShell), holding what was drawn when it was last open
  // (held), so it opens again with the same output boxes, earlier attempts and set-up open. It stays open or closed
  // through a redraw, and the keyboard's place in it stays where it was. The focus is put back without scrolling: a
  // focus that scrolls its element into view moved the page and the panel under the reader at each redraw. was: the
  // "Every step" of the row's earlier card id, for a row that has none yet.
  function every(li, c, ctx, was) {
    const more = li.children[5], cur = more.firstChild || was;
    // The places the keyboard can be: a fold, a step's bar, a lint command's name (its tip is open on the new name only if it was open).
    const keys = 'summary, .tl-item, .lint-cmd-word';
    const at = more.firstChild ? Array.from(more.firstChild.querySelectorAll(keys)).indexOf(li.ownerDocument.activeElement) : -1;
    const keep = ctx.focusKeeper();
    const t = c.track && typeof c.track === 'object' ? c.track : null;
    const drawn = cur && cur.querySelector(':scope > ol.timeline') ? cur : (cur && cur.held) || null;
    let det;
    if (cur && cur.open) { det = ctx.trackDetail(t, c.card, drawn || cur, c.earlier, ctx.text.repoOf(c), c.repo); det.open = true; }
    else { det = ctx.trackShell(t, c.card, c.earlier); det.held = drawn; }
    more.replaceChildren(det);
    const back = at >= 0 ? det.querySelectorAll(keys)[at] : null;
    if (back && back.classList.contains('lint-cmd-word')) keep(back);
    else if (back) back.focus({ preventScroll: true });
  }

  window.DASH_APP.panel({
    id: 'belt',
    title: 'On the belt',
    size: 'wide',
    tab: 'overview',
    projects: true,  // filtered to one project, cap is that project's own (the part's byRepo)
    rows: 5,  // a card is four lines: five of them fill the panel's default length
    // Every card on the belt counts against the cap, in any step and waiting or not, but one that lands (offCap)
    // or has landed and waits for its push or for its issue to close, as the On the belt tile of the head counts them
    // (head.js). While a project's snapshot is behind its card records, the count is the loop's own now (the part's building, from
    // loop.json: dashboard.sh), not the cards it shows.
    count: (d) => {
      const all = d.cards.filter((c) => !c.landed && !c.offCap).length;
      const n = num(d.building) ? d.building : all;
      return typeof d.cap === 'number' ? `${n} of ${d.cap}` : n;
    },
    // A belt shown from a snapshot behind the card records is never "empty": cards may have begun since.
    isEmpty: (d) => d.cards.length === 0 && !(Array.isArray(d.behind) && d.behind.length),
    empty(el, ctx) { el.append(ctx.state('empty', 'The belt is empty', 'Conveyor builds no card now.')); },
    error(el, message, ctx) { el.append(ctx.state('error', 'The Board could not read the belt', message)); },
    // Each second, whether or not a new snapshot came: the time since a running step's last output counts on, and
    // the step in progress beats now and then (a short motion replayed by the clock, none under reduced motion).
    tick(el, ctx) {
      el.querySelectorAll('time[data-output-at]').forEach((n) => {
        const text = quietText(n.dataset.outputAt, ctx);
        if (n.textContent !== text) n.textContent = text;
      });
      // A step in progress grows on its card's timeline, its time counting on; nothing else on the page moves. A
      // closed timeline is not retimed.
      el.querySelectorAll('.track-detail[open]').forEach((det) => { if (det.retime) det.retime(); });
      if (!ctx.motion()) return;
      const t = Date.now();
      if (t - (el.beatAt || 0) < BEAT_MS) return;
      el.beatAt = t;
      // All the beats restart on one layout: the class off from all, one read of offsetWidth, the class on to all.
      const chips = Array.from(el.querySelectorAll('.step6[data-state="now"] .step-chip, .tl-item[data-state="now"] .tl-bar'));
      if (!chips.length) return;
      chips.forEach((c) => c.classList.remove('beat'));
      void chips[0].offsetWidth;
      chips.forEach((c) => c.classList.add('beat'));
    },
    render(el, d, ctx) {
      const h = ctx.h;
      if (!el.firstChild) el.append(h('ul', 'rows belt'));
      // A panel drawn whole (ctx.whole: a new time format, project or model name) keeps no row as it was.
      const again = ctx.whole;
      ctx.list(el.firstChild, d.cards, (c) => `${c.repo}:${c.card}`, () => {
        const li = h('li', 'row belt-card'), more = h('div', 'more');
        li.append(h('div', 'row-main'), h('p', 'row-meta'), h('ol', 'track6'), h('p', 'track-now'), h('ul', 'reviews'), more);
        // "Every step" draws its steps when it opens, and drops them when it closes. toggle does not bubble: it is
        // caught on its way down, and only for "Every step" itself, never a fold inside it.
        more.addEventListener('toggle', (e) => {
          const det = e.target;
          if (det.parentNode === more && det.open !== Boolean(det.querySelector(':scope > ol.timeline')) && li.card) every(li, li.card, ctx, null);
        }, true);
        return li;
      }, (li, c) => {
        // A card whose part is as it was keeps its row as it is: one card's new figures redraw only that card.
        const json = JSON.stringify(c);
        if (li.json === json && !again) return;
        li.json = json;
        li.card = c;
        const [head, meta, track, now, reviews] = li.children;
        // Each part of the row is drawn again only when what it shows changed (its key, kept on the node).
        const redo = (node, key) => { const k = JSON.stringify(key); if (node.key === k && !again) return false; node.key = k; return true; };
        const what = doing(c, ctx);
        if (redo(head, [c.repo, c.card, c.issue, c.name, c.url, c.title, c.parent, c.start, c.pickedAt, c.totalSec, c.priorSec, c.earlier, what, Boolean(c.track && c.track.reason)])) {
          head.replaceChildren(ctx.issueLink(c), h('span', 'title', c.title || 'untitled'));
          if (typeof c.parent === 'number' && c.parent > 0) head.append(h('span', 'parent', `↳ #${c.parent}`));
          const [said, why] = [].concat(what), pill = ctx.chip(said, c.track && c.track.reason ? 'bad' : 'info');
          if (why) ctx.tip(pill, why);
          head.append(times(c, ctx), pill);
        }
        // The dollars and the tokens (the builder's and the reviewer's together) are the finished steps and the running one so far; before
        // any token is read there is no figure, and when the running session's route reports no usage until it ends (atEnd), it says so.
        const tok = c.tokens && num(c.tokens.claude) && num(c.tokens.codex) ? c.tokens.claude + c.tokens.codex : null;
        // One unwrapped piece of the meta row, dollars and tokens together a held width (app.css, .live-cost): it counts on as refreshes come.
        // A proof run that waits for a test slot (its live action, testrun.sh) runs no tests yet.
        const slotWait = c.step === 'proof' && c.live && typeof c.live.action === 'string' && c.live.action.startsWith('waiting for a test slot');
        // The effort the step runs at beside its model, as the seat lines name it (board.js seatText()); none known, the model alone.
        // A card the snapshot reader added from the card records (fromRecords: in no full build yet) has no model or
        // cost yet: the next snapshot gives them.
        const model = c.fromRecords === true ? 'new card: details come with the next snapshot' : (c.model ?`${ctx.modelName(c.model)}${typeof c.effort === 'string' && c.effort ? ` at ${c.effort}` : ''}` : '') || (slotWait ? 'waiting for a test slot' : c.step === 'tests' || c.step === 'proof' ? 'running tests' : 'no AI model in this step');
        if (redo(meta, [c.repo, model])) meta.replaceChildren(ctx.tag(c.repo), h('span', null, model), h('span', 'live-cost'));
        // The cost is the same node from one change to the next: the dollars are drawn again only when they changed (so
        // they count on from the figure shown), the tokens' text is set in place.
        const cost = meta.lastChild;
        if (redo(cost, [c.card, c.reading, c.atEnd, c.usd])) {
          if (c.reading) cost.replaceChildren(ctx.number(`usd:${c.card}`, c.usd, ctx.money), h('span'));
          else cost.replaceChildren(c.atEnd === true ? 'cost shown when the step ends' : 'no reading yet');
        }
        if (c.reading) {
          const text = tok !== null ? ` · ${count(tok)} tokens so far` : typeof c.usd === 'number' ? ' so far' : '';
          if (cost.lastChild.textContent !== text) cost.lastChild.textContent = text;
        }
        const t = c.track && typeof c.track === 'object' ? c.track : null;
        track.hidden = !ctx.track(track, t);
        // The step in progress, measured: how long it has run, how far a running test run has got (its tests, else
        // its files: ctx.testProgress), why a push failed.
        // Each piece is its kind, what it shows and how to draw it. A piece whose kind and value are the ones shown stays
        // that node (never compared as a node: an open popover marks its item), so a tapped live action or push error
        // keeps its popover open through a token update.
        const since = (t && t.since) || c.stepAt;
        const parts = [['since', since, () => ctx.since(since, ' in this step')]];
        const prog = ctx.testProgress(t);
        if (prog) parts.push(['prog', prog, () => h('span', 'test-progress', prog)]);
        // The line is one line high (app.css, .track-now): a text cut to fit there carries its full text as its title,
        // and a tap opens it (a phone shows no title).
        const full = (cls, text) => ctx.tip(h('span', cls, text), text);
        if (t && t.reason) parts.push(['failed', t.reason, () => full('failed', `Push failed: ${t.reason}`)]);
        // The running step's live fields, streamed as the session or review prints them: what it does now,
        // its model replies (turns; none for a test run, which runs no model), and how long since its last output.
        const live = c.live && typeof c.live === 'object' ? c.live : null;
        // What it does now, in words ("now: running a command"); the command or file itself on hover and tap. A button,
        // so the keyboard reaches it: Enter opens the same words a tap does.
        const actionEl = (a) => { const b = h('button', 'live-action', `now: ${actionSaid(a)}`); b.type = 'button'; return ctx.tip(b, a); };
        if (live && typeof live.action === 'string' && live.action) parts.push(['action', live.action, () => actionEl(live.action)]);
        if (live && c.step !== 'tests' && num(live.turns) && live.turns > 0) parts.push(['turns', live.turns, () => h('span', null, `${live.turns} model ${live.turns === 1 ? 'reply' : 'replies'}`)]);
        if (live && typeof live.lastOutputAt === 'string') parts.push(['quiet', live.lastOutputAt, () => quiet(live.lastOutputAt, ctx)]);
        parts.forEach(([kind, value, make], i) => {
          const key = JSON.stringify([kind, value]), old = now.children[i];
          if (old && old.key === key && !again) return;
          const n = make();
          n.key = key;
          if (old) old.replaceWith(n); else now.append(n);
        });
        while (now.children.length > parts.length) now.lastElementChild.remove();
        // One line a finished review: its round, its verdict, its findings by level (the verdict alone when none were counted).
        const done = Array.isArray(c.reviews) ? c.reviews : [];
        reviews.hidden = done.length === 0;
        if (redo(reviews, [c.card, done])) reviews.replaceChildren(...done.map((r) => {
          const row = h('li', 'review'), f = ctx.findings(r);
          row.append(ctx.reviewChip(r));
          if (f) row.append(h('span', null, f));
          // The findings that came back after their fix rounds (ctx.survived).
          const s = ctx.survived(r);
          if (s) row.append(h('span', 'survived', s));
          // Why the fix loop ended on this review (ctx.loopEnd).
          const e = ctx.loopEnd(r);
          if (e) row.append(h('span', 'loop-end', e));
          // What the judge made of it (ctx.judged).
          const j = ctx.judged(r, c.card);
          if (j) row.append(j);
          return row;
        }));
        // A retried card has a new card id, so its row is new: until it has drawn once, what was open is taken from
        // the row of its latest earlier card id still shown ("Every step" and its earlier attempts stay open).
        let was = null;
        if (!li.children[5].firstChild && Array.isArray(c.earlier)) {
          const rows = Array.from(el.firstChild.children);
          const prev = c.earlier.slice().reverse().map((e) => e && rows.find((r) => r !== li && r.dataset.key === `${c.repo}:${e.card}`)).find(Boolean);
          was = prev ? prev.querySelector(':scope > .more > details.track-detail') : null;
        }
        every(li, c, ctx, was);
      });
      // Under the cards, each project whose snapshot is behind its card records (ctx.behind).
      ctx.behind(el, d.behind);
    },
  });
}());
