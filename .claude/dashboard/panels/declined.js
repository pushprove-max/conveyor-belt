// SPDX-License-Identifier: Apache-2.0
// Declined: the review findings that were not built, newest first, each with who declined it (code, the judge or
// the owner) and why. Its part: {lines, rest}; lines are the ones the panel shows (not dismissed, not built, at most 7
// days old), rest every other (the newest the snapshot keeps, and the older ones from the history); a line is {repo, id, time, card, issue, name (a main-red fix card's, which has issue 0, or null), url, finding, by, why, built, dismissed}, as
// the project's declined list holds it (conveyor.sh declined()), with round and findings (the review the judge
// declined it in and that review's findings as the judge numbered them), which turn each F<n> of the judge's reason
// into the finding it means (why, below). "File as issue" (confirmed by a second click: it costs a build) files the
// finding as an ordinary issue, through POST /control build with the line's repository and id; the line is greyed in
// place at once, and built is that issue once it is filed, the line then saying so in place of the button. "Dismiss"
// (one line, on a second click that says it is for good) and "Dismiss all shown (n)" (in the panel's heading,
// confirmed by a second click: the n open lines drawn) mark lines dismissed, through POST /control dismiss, one a
// project (400 lines at most a request): they leave the panel and its count at once, and stay in the list. The
// reviewer is told the reasons of the lines not built, dismissed or not,
// so it does not raise them again. An open line with 2 days or less before it leaves the panel (7 days after its time)
// says when: "Expires in 1 d 4 h", brought in and counted down by the clock. "Show every line" (?declined=all) shows the rest too, each marked: dismissed (by
// whom, when), filed, or more than 7 days old. A review's declined count (ctx.judged, on a card's review steps) opens
// the panel on that card's lines alone, every one of them (?declined=<card>), with a note that says so, a button to
// every line and one back to the list. A dismissed, built or old line is greyed and tagged Dismissed, Built or Expired.
(() => {
  const WHO = { code: 'the code', judge: 'the judge', owner: 'the owner' };
  const DISMISS_MAX = 400; // the most ids POST /control dismiss takes in one request (dashboard_server.py control_ok)
  const DAY = 86400000, KEEP = 7 * DAY, WARN = 2 * DAY; // a line leaves the panel KEEP after its time; WARN before, it says so
  // What the owner did with a line since the page loaded, through every redraw: armed (the first click of "File as
  // issue"), said (the host's answer), busy (sent, no answer yet) and gone (dismissed here: {time, by}, until a snapshot
  // has the line in its rest).
  // filed: the lines the host filed here, greyed until a list shows them built.
  const armed = new Set(), said = new Map(), busy = new Set(), gone = new Map(), filed = new Set();
  let allSaid = ''; // the host's answer to "Dismiss all shown", when it refused
  // The keys of the lines "Dismiss all shown" was first clicked for; a second click sends them only while the same
  // lines are drawn, so a click never dismisses lines its count did not name.
  let allArmed = null;
  const key = (x) => `${x.repo}:${x.id}`;
  const shown = (d) => d.lines.filter((x) => !gone.has(key(x)));
  // Every line, newest first (kept together by project when the lists are sorted so); one of the rest that is neither
  // dismissed nor built is old (more than 7 days); one dismissed here carries that dismissal.
  const every = (d, ctx) => {
    const all = d.lines.map((x) => ({ x, old: false })).concat((d.rest || []).map((x) => ({ x, old: true })))
      .map(({ x, old }) => {
        const dismissed = x.dismissed || gone.get(key(x)) || null;
        return { ...x, dismissed, old: old && !dismissed && typeof x.built !== 'number' };
      })
      .sort((a, b) => (a.time < b.time ? 1 : a.time > b.time ? -1 : 0));
    return ctx.sorted() ? all.sort((a, b) => (a.repo < b.repo ? -1 : a.repo > b.repo ? 1 : 0)) : all;
  };
  const open = (x) => !x.dismissed && typeof x.built !== 'number';
  // A finding's first sentence: its level, file and line lead it.
  const first = (s) => { const m = /^.*?[.!?](?=\s|$)/.exec(s); return m ? m[0] : s; };
  // The line's reason. In the judge's, each F<n> (the n-th finding of the card's review it was declined in, as the
  // judge numbered them: the snapshot's round and findings) is a button: on hover and on click (a line under the
  // reason, a second click hides it) it says which finding it means, its first sentence and its review round. An F<n>
  // whose finding is not found is left as written, with "finding not found" on hover. The text is never changed.
  const why = (x, h) => {
    const text = x.why || 'no reason given', p = h('p', 'reason', 'Why: ');
    if (x.by !== 'judge') { p.append(text); return [p]; }
    const said = h('p', 'row-meta finding-said');
    said.hidden = true;
    const refs = [];
    let at = 0;
    for (const m of text.matchAll(/\bF([0-9]+)\b/g)) {
      p.append(text.slice(at, m.index));
      at = m.index + m[0].length;
      const f = Number.isInteger(x.round) && Array.isArray(x.findings) ? x.findings.find((y) => y && y.n === Number(m[1]) && typeof y.finding === 'string') : null;
      if (!f) { const s = h('span', 'finding-ref is-missing', m[0]); s.title = 'finding not found'; p.append(s); continue; }
      const tell = `${m[0]}, review round ${x.round}: ${first(f.finding)}`;
      const b = h('button', 'btn btn-quiet judged-open finding-ref', m[0]);
      b.type = 'button'; b.dataset.act = 'finding'; b.title = tell;
      b.setAttribute('aria-expanded', 'false');
      b.addEventListener('click', () => {
        const shut = !said.hidden && said.textContent === tell;
        said.textContent = tell; said.hidden = shut;
        refs.forEach((r) => r.setAttribute('aria-expanded', String(r === b && !shut)));
      });
      refs.push(b);
      p.append(b);
    }
    p.append(text.slice(at));
    return refs.length ? [p, said] : [p];
  };
  const answer = (r) => r.text().then((t) => ({ ok: r.ok, said: String(t).trim() || `the build machine answered ${r.status}` }));
  const noAnswer = () => ({ ok: false, said: 'the build machine did not answer. Make sure that it is on. Then try again' });
  window.DASH_APP.panel({
    id: 'declined',
    title: 'Declined',
    size: 'wide',
    tab: 'overview',
    projects: true,
    declinedOf: 'declined',
    rows: 6,
    // The live part's rest holds the newest lines the snapshot keeps; the others come from the history.
    older: (d, o) => Object.assign({}, d, { rest: window.DASH_APP.joined(d.rest, o.rest, key) }),
    count: (d) => shown(d).length,
    isEmpty: (d) => d.lines.length === 0 && (d.rest || []).length === 0,
    empty(el, ctx) { el.append(ctx.state('empty', 'No declined finding', 'A review finding that Conveyor did not build shows here with who declined it and why.')); },
    error(el, message, ctx) { el.append(ctx.state('error', 'The Board could not read the declined findings', message)); },
    render(el, d, ctx) {
      const h = ctx.h;
      const ul = h('ul', 'rows');
      // Marks lines dismissed on the host, one request a project of at most DISMISS_MAX lines (more lines, more
      // requests); then the panel is drawn again without them.
      const dismiss = (xs, done) => {
        const by = new Map();
        xs.forEach((x) => by.set(x.repo, (by.get(x.repo) || []).concat(x)));
        xs.forEach((x) => busy.add(key(x)));
        const parts = [];
        by.forEach((ys, repo) => { for (let i = 0; i < ys.length; i += DISMISS_MAX) parts.push([repo, ys.slice(i, i + DISMISS_MAX)]); });
        return Promise.all(parts.map(([repo, ys]) => ctx.post('control', { action: 'dismiss', args: ys.map((y) => y.id), repo })
          .then(answer, noAnswer).then((r) => {
            ys.forEach((y) => busy.delete(key(y)));
            if (r.ok) ys.forEach((y) => gone.set(key(y), { time: new Date().toISOString(), by: 'you' }));
            return r;
          }))).then((rs) => { done(rs.filter((r) => !r.ok).map((r) => r.said)); ctx.redraw(); });
      };
      const row = (x) => {
        const k = key(x);
        // A line done with (dismissed, built or more than 7 days old) is greyed, and tagged so beside its issue.
        const done = x.dismissed ? 'Dismissed' : typeof x.built === 'number' ? 'Built' : x.old ? 'Expired' : '';
        const li = h('li', done ? 'row is-done' : 'row');
        const head = h('div', 'row-main');
        head.append(ctx.issueLink(x));
        if (done) head.append(h('span', 'chip chip-quiet done-tag', done));
        head.append(h('span', 'title', x.finding || 'no finding'));
        const meta = h('p', 'row-meta');
        meta.append(ctx.tag(x.repo), h('span', null, `declined by ${WHO[x.by] || 'no one named'}`), ctx.since(x.time, ' ago'));
        li.append(head, meta, ...why(x, h));
        if (x.dismissed) {
          const m = h('p', 'row-meta mark');
          m.append(h('span', null, `Dismissed by ${x.dismissed.by || 'no one named'}`), ctx.since(x.dismissed.time, ' ago'));
          li.append(m);
        }
        if (x.old) li.append(h('p', 'row-meta mark', 'More than 7 days old'));
        // An open line about to leave the panel says when, before it goes; tick (below) brings the note in and counts it
        // down, as a line stays the same in the snapshot until it leaves.
        const leaves = Date.parse(x.time) + KEEP;
        if (!done && Number.isFinite(leaves)) {
          li.dataset.leaves = String(leaves);
          const left = leaves - ctx.now();
          if (left > 0 && left <= WARN) li.append(h('p', 'row-meta mark expires', `Expires in ${ctx.dur(left / 1000)}`));
        }
        if (typeof x.built === 'number') { li.append(h('p', 'row-meta mark', `Filed as #${x.built}`)); return li; }
        if (x.dismissed) return li;
        const box = h('div', 'answer'), note = h('p', 'answer-note');
        note.setAttribute('aria-live', 'polite');
        // File as issue costs a build: it asks for a second click. Dismiss cannot be undone: a second click too.
        const b = h('button', 'btn btn-cost'), off = h('button', 'btn btn-quiet', 'Dismiss');
        b.type = 'button'; off.type = 'button';
        b.dataset.act = 'build'; off.dataset.act = 'dismiss'; b.dataset.guard = 'spend';
        const draw = () => {
          b.textContent = armed.has(k) ? 'Click again to file it as an issue' : 'File as issue';
          b.setAttribute('aria-pressed', String(armed.has(k)));
          b.disabled = busy.has(k); off.disabled = busy.has(k);
          // Filed, the line is greyed in place and its buttons go, until the list no longer shows it.
          li.classList.toggle('is-pending', filed.has(k));
          b.hidden = filed.has(k); off.hidden = filed.has(k);
          note.textContent = said.get(k) || '';
        };
        b.addEventListener('click', () => {
          if (busy.has(k)) return;
          if (!armed.has(k)) { armed.add(k); said.set(k, 'Click again to file it as an issue. Conveyor then builds it in its turn, as an ordinary issue.'); draw(); return; }
          armed.delete(k); busy.add(k); said.set(k, 'Sending…'); draw();
          ctx.post('control', { action: 'build', args: [x.id], repo: x.repo })
            .then(answer, noAnswer)
            .then((r) => {
              if (!r.ok) busy.delete(k); else filed.add(k);
              said.set(k, r.ok ? 'Filed as an issue: Conveyor builds it in its turn. The line shows this in about a minute.' : `Not filed: ${r.said}`);
              draw();
            });
        });
        ctx.twice(off, 'final', 'Click again: dismiss it for good', () => {
          if (busy.has(k)) return;
          armed.delete(k); said.set(k, 'Sending…'); draw();
          dismiss([x], (bad) => said.set(k, bad.length ? `Not dismissed: ${bad[0]}` : ''));
          draw();
        });
        draw();
        box.append(b, off);
        li.append(box, note);
        return li;
      };
      const view = ctx.param('declined');
      const lines = view === 'all' ? every(d, ctx) : view ? every(d, ctx).filter((x) => x.card === view) : shown(d);
      // The rows drawn now ("Dismiss all shown" takes their open lines, no more).
      let drawn = [];
      const bar = h('p', 'foot');
      const btn = (text, act, quiet) => { const b = h('button', quiet ? 'btn btn-quiet' : 'btn', text); b.type = 'button'; b.dataset.act = act; return b; };
      const go = (v) => { ctx.params({ declined: v }); this.render(el, d, ctx); ctx.relength(); };
      const said0 = h('span', 'answer-note');
      said0.setAttribute('aria-live', 'polite');
      if (view === 'all') bar.append(h('span', null, 'Every line: dismissed, filed and older ones too. '));
      else if (view) bar.append(h('span', null, lines.length ? `Showing the ${lines.length === 1 ? 'line' : `${lines.length} lines`} of ${typeof lines[0].name === 'string' && lines[0].name ? lines[0].name : `#${lines[0].issue}`} only. ` : 'No line of that card is in the list. '));
      else if (!lines.length) bar.append(h('span', null, 'Nothing to look at: you dismissed or filed each line, or the line is more than 7 days old. '));
      // "Dismiss all shown (n)", in the panel's heading and coloured as a warning, unlike the harmless buttons below:
      // the first click asks, the second sends the n open lines drawn, and only while those same lines are drawn. It
      // cannot be undone, and its second-click text says so.
      const all = btn('', 'dismiss-all');
      all.classList.add('btn-warn');
      const targets = () => drawn.filter((x) => open(x) && !busy.has(key(x)));
      const ids = (xs) => xs.map(key).join(' ');
      const drawAll = () => {
        const xs = targets();
        if (allArmed !== null && allArmed !== ids(xs)) allArmed = null;
        const n = xs.length === 1 ? 'the line' : `the ${xs.length} lines`;
        all.textContent = allArmed !== null ? `Click again to dismiss ${n} for good` : `Dismiss all shown (${xs.length})`;
        all.setAttribute('aria-pressed', String(allArmed !== null));
        said0.textContent = allArmed !== null ? `Click again to dismiss ${n} shown: they leave the panel, and the reviewer still does not raise them again.` : allSaid;
        ctx.headActs(...(xs.length ? [all] : []));
      };
      all.addEventListener('click', () => {
        const xs = targets();
        if (!xs.length) return;
        if (allArmed !== ids(xs)) { allArmed = ids(xs); drawAll(); return; }
        allArmed = null; all.disabled = true; allSaid = 'Sending…'; said0.textContent = allSaid;
        dismiss(xs, (bad) => { allSaid = bad.length ? `Not dismissed: ${bad.join('; ')}` : ''; });
      });
      if (view === 'all') { const b = btn("Show the panel's lines", 'declined-panel', true); b.addEventListener('click', () => go(null)); bar.append(b); }
      else { const b = btn('Show every line', 'declined-all', true); b.addEventListener('click', () => go('all')); bar.append(b); }
      if (view && view !== 'all') { const b = btn('Back to the list', 'declined-list', true); b.addEventListener('click', () => go(null)); bar.append(' ', b); }
      bar.append(' ', said0);
      // The collector gives them newest first.
      el.replaceChildren(bar, ul, ctx.more(view ? `declined:${view}` : 'declined', lines, (ls) => { drawn = ls; ul.replaceChildren(...ls.map(row)); drawAll(); }));
    },
    // Each second: an unchanged snapshot does not draw the panel again, so the clock moves "Expires in" on. A line that
    // comes within 2 days of leaving, or past it, has the panel drawn again (its note comes or goes); else the text counts.
    tick(el, ctx) {
      let moved = false;
      el.querySelectorAll('.rows > .row[data-leaves]').forEach((li) => {
        const left = Number(li.dataset.leaves) - ctx.now();
        const note = li.querySelector(':scope > .expires');
        if ((left > 0 && left <= WARN) !== Boolean(note)) { moved = true; return; }
        const text = note ? `Expires in ${ctx.dur(left / 1000)}` : null;
        if (note && note.textContent !== text) note.textContent = text;
      });
      if (moved) ctx.redraw();
    },
  });
})();
