// SPDX-License-Identifier: Apache-2.0
// Declined: the review findings that were not built, newest first, each with who declined it (code, the judge or
// the owner) and why. Its part: {lines, rest}; lines are the ones the panel shows (not dismissed, not built, at most 7
// days old), rest every other (the newest the snapshot keeps, and the older ones from the history); a line is {repo, repoUrl, id, time, card, issue, name (a main-red fix card's, which has issue 0, or null), url, finding, by, why, built, dismissed}, as
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
  // A reason's text split into sentences, each a list of parts: {code} (a span the reason has in backticks, drawn
  // without them) or {text}. A sentence ends at a . ! or ? before a space, outside backticks; the space stays at its
  // end, so the sentences joined (with the backticks) are the text as written. A lone backtick is left as text.
  const sentences = (text) => {
    const out = [[]];
    let at = 0;
    const plain = (s) => {
      let from = 0;
      for (const m of s.matchAll(/[.!?]\s+/g)) {
        out[out.length - 1].push({ text: s.slice(from, m.index + m[0].length) });
        out.push([]);
        from = m.index + m[0].length;
      }
      if (from < s.length) out[out.length - 1].push({ text: s.slice(from) });
    };
    for (const m of text.matchAll(/`([^`]+)`/g)) {
      plain(text.slice(at, m.index));
      out[out.length - 1].push({ code: m[1] });
      at = m.index + m[0].length;
    }
    plain(text.slice(at));
    return out.filter((s) => s.length);
  };
  // The paths with a directory that a text names before a :line ("conveyor/lib/claim.sh:99").
  const PATH = /(?:^|[^A-Za-z0-9_./-])((?:[A-Za-z0-9_.-]+\/)+[A-Za-z0-9_.-]+):[0-9]/g;
  const pathsIn = (s) => (typeof s === 'string' ? Array.from(s.matchAll(PATH), (m) => m[1]) : []);
  // A `file:line` (or `file:a–b`) of a reason, as a link to those lines on GitHub, in the line's repository (repoUrl:
  // a main-red fix card has no issue url); null when the span is no file and line, or the repository is not on GitHub.
  // A short path ("issues.sh:636") is the one path of known (the paths the line's findings and reasons name) that ends
  // with it; none or more than one, and it has no directory, it is no link, as the repository root is only a guess.
  const lineUrl = (x, code, known) => {
    const repo = /^https:\/\/github\.com\/([A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+)$/.exec(typeof x.repoUrl === 'string' ? x.repoUrl : '');
    const m = /^((?:[A-Za-z0-9_.-]+\/)*[A-Za-z0-9_.-]+):([0-9]+)(?:[–-]([0-9]+))?$/.exec(code);
    if (!repo || !m || m[1].split('/').some((s) => s === '.' || s === '..')) return null;
    let path = m[1];
    if (!known.has(path)) {
      const ends = [...known].filter((k) => k.endsWith(`/${path}`));
      if (ends.length === 1) path = ends[0];
      else if (!path.includes('/')) return null;
    }
    return { url: `https://github.com/${repo[1]}/blob/HEAD/${path}#L${m[2]}${m[3] ? `-L${m[3]}` : ''}`, at: `${path}:${m[2]}` };
  };
  // A file path with a directory and a line ("shared/taxonomy/fields.ts:239") written without backticks.
  const BARE = /(?<![A-Za-z0-9_./-])(?:[A-Za-z0-9_.-]+\/)+[A-Za-z0-9_-][A-Za-z0-9_.-]*\.[A-Za-z0-9]+:[0-9]+(?:[–-][0-9]+)?/g;
  // Plain text, each bare path in it given to at (drawn as code), the rest to plain; the text is kept as written.
  const barePaths = (s, at, plain) => {
    let from = 0;
    for (const m of s.matchAll(BARE)) {
      if (m.index > from) plain(s.slice(from, m.index));
      at(m[0]);
      from = m.index + m[0].length;
    }
    if (from < s.length) plain(s.slice(from));
  };
  // A span of code: monospace, italic and in the accent colour (app.css .why-code); a file and line in it is a link to
  // that line on GitHub (lineUrl), with the link returned so a caller can say more of it on hover.
  const codeEl = (h, x, s, known, cls) => {
    const c = h('code', 'why-code', s), to = lineUrl(x, s, known);
    if (!to) return { el: c, to: null };
    const a = h('a', `${cls}-at`);
    a.href = to.url; a.target = '_blank'; a.rel = 'noopener noreferrer';
    a.append(c);
    return { el: a, to };
  };
  const LEVELS = new Set(['0', '1', '2', '3']);
  // A finding, as "[P<n>] <file>:<line> <claim>. <more> Proof: <proof>": a head line (the level as a coloured badge,
  // the file and line as code linked to that line), the claim in bold on its own line, then the proof under a "Proof"
  // label, a sentence a line. Text in backticks and bare file paths are code. A finding of another shape is drawn as
  // its sentences. The text drawn is the finding as written, without its backticks.
  const findingEl = (h, x, known) => {
    const text = typeof x.finding === 'string' && x.finding ? x.finding : 'no finding';
    const box = h('div', 'title declined-finding');
    const fill = (el, s) => {
      for (const parts of sentences(s)) {
        const line = h('span', 'declined-line');
        for (const p of parts) {
          if ('code' in p) line.append(codeEl(h, x, p.code, known, 'declined').el);
          else barePaths(p.text, (q) => line.append(codeEl(h, x, q, known, 'declined').el), (q) => line.append(q));
        }
        el.append(line);
      }
    };
    // A review's id for the finding ("[E1]", "[F2]"), when it has one, stands between the level and the file.
    const m = /^(\[P([0-9])\])(\s+)((?:\[[A-Za-z]+[0-9]+\]\s+)*)(\S+?:[0-9]+(?:[–-][0-9]+)?)(\s+)([\s\S]*)$/.exec(text);
    if (!m) { fill(box, text); return box; }
    const head = h('div', 'declined-head');
    const badge = h('span', 'declined-level', m[1]);
    badge.dataset.level = LEVELS.has(m[2]) ? `P${m[2]}` : 'none';
    head.append(badge, m[3]);
    if (m[4]) head.append(h('span', 'declined-ids', m[4]));
    head.append(codeEl(h, x, m[5], known, 'declined').el, m[6]);
    box.append(head);
    const rest = m[7];
    // "Proof:" outside backticks splits the claim (and what follows it) from the proof.
    let cut = -1;
    for (const p of rest.matchAll(/`[^`]*`|\bProof:\s*/g)) if (p[0][0] !== '`') { cut = p.index; break; }
    const said = cut < 0 ? rest : rest.slice(0, cut), proof = cut < 0 ? '' : rest.slice(cut);
    const claim = /^\S[\s\S]*?(?:[.!?](?=\s|$)|$)\s*/.exec(said)?.[0] || said; // the first sentence, its space kept
    if (claim) { const b = h('strong', 'declined-claim'); fill(b, claim); box.append(b); }
    if (said.length > claim.length) { const r = h('div', 'declined-more'); fill(r, said.slice(claim.length)); box.append(r); }
    if (proof) {
      const label = /^Proof:\s*/.exec(proof)[0];
      const p = h('div', 'declined-proof');
      p.append(h('span', 'declined-proof-label', label));
      fill(p, proof.slice(label.length));
      box.append(p);
    }
    return box;
  };
  // The line's reason, in its own block under the finding: a tinted panel with a left rule in the colour of who
  // declined it, led by a bold "Why the judge declined it" (or the code, or the owner). Each sentence is a line of its
  // own; text in backticks and a bare path with a line are code, and a file and line a link to them on GitHub. In the judge's, each F<n> (the
  // n-th finding of the card's review it was declined in, as the judge numbered them: the snapshot's round and
  // findings) is a button: on hover and on click (a line under the reason, a second click hides it) it says which
  // finding it means, its first sentence and its review round; a `file:line` that a finding of that review starts with
  // ("repeats the declined finding at `<file>:<line>`") says the same of that finding, and one that a declined finding
  // of another review or card of the project starts with (pool: every line of the list) says that finding and its
  // card; when several findings start there, it says each of them. An F<n> whose finding is not found is left as written, with "finding not found" on hover. The text is never
  // changed.
  // The project's other lines declined by the time x's reason was written (kin), and the paths the line's findings and
  // reasons name (known, for lineUrl).
  const near = (x, pool) => {
    // Only a finding declined by the time the reason was written can be the one it names; a line with no readable
    // time is not known to be earlier.
    const when = Date.parse(x.time);
    const kin = pool.filter((y) => y && y.repo === x.repo && typeof y.finding === 'string' && key(y) !== key(x)
      && Date.parse(y.time) <= when);
    const known = new Set([x.finding, x.why].concat(Array.isArray(x.findings) ? x.findings.map((y) => y && y.finding) : [], kin.map((y) => y.finding)).flatMap(pathsIn));
    return { kin, known };
  };
  const why = (x, h, { kin, known }) => {
    const text = x.why || 'no reason given';
    const box = h('div', 'reason why-block');
    box.dataset.by = WHO[x.by] ? x.by : 'none';
    const body = h('div', 'why-text');
    box.append(h('strong', 'why-label', WHO[x.by] ? `Why ${WHO[x.by]} declined it` : 'Why it was declined'), body);
    const judged = x.by === 'judge' && Number.isInteger(x.round) && Array.isArray(x.findings);
    const said = h('p', 'row-meta finding-said');
    said.hidden = true;
    const refs = [];
    // A button or link that opens what it names under the reason, on click; on hover its title says it.
    const opener = (el, tell) => {
      el.title = tell;
      el.setAttribute('aria-expanded', 'false');
      el.addEventListener('click', () => {
        const shut = !said.hidden && said.textContent === tell;
        said.textContent = tell; said.hidden = shut;
        refs.forEach((r) => r.setAttribute('aria-expanded', String(r === el && !shut)));
      });
      refs.push(el);
    };
    const refsIn = (line, s) => {
      if (x.by !== 'judge') { line.append(s); return; }
      let at = 0;
      for (const m of s.matchAll(/\bF([0-9]+)\b/g)) {
        line.append(s.slice(at, m.index));
        at = m.index + m[0].length;
        const f = judged ? x.findings.find((y) => y && y.n === Number(m[1]) && typeof y.finding === 'string') : null;
        if (!f) { const t = h('span', 'finding-ref is-missing', m[0]); t.title = 'finding not found'; line.append(t); continue; }
        const b = h('button', 'btn btn-quiet judged-open finding-ref', m[0]);
        b.type = 'button'; b.dataset.act = 'finding';
        opener(b, `${m[0]}, review round ${x.round}: ${first(f.finding)}`);
        line.append(b);
      }
      line.append(s.slice(at));
    };
    for (const parts of sentences(text)) {
      const line = h('span', 'why-line');
      const code = (s) => {
        const { el: a, to } = codeEl(h, x, s, known, 'why');
        if (!to) { line.append(a); return; }
        const at = new RegExp(`^\\[P[0-9]\\]\\s+${to.at.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b(?![-–])`);
        // Every finding that starts there, not only the first found: two findings can start at the same line, and the
        // text alone does not say which one the reason means.
        const fs = judged ? x.findings.filter((y) => y && Number.isInteger(y.n) && typeof y.finding === 'string' && y.finding !== x.finding && at.test(y.finding)) : [];
        const os = kin.filter((y) => at.test(y.finding) && !fs.some((f) => f.finding === y.finding));
        const tells = fs.map((f) => `F${f.n}, review round ${x.round}: ${first(f.finding)}`)
          .concat(os.map((o) => `Declined on ${typeof o.name === 'string' && o.name ? o.name : `#${o.issue}`}: ${first(o.finding)}`));
        if (tells.length === 1) opener(a, tells[0]);
        else if (tells.length) opener(a, `${tells.length} findings start at ${to.at}: ${tells.join(' ')}`);
        line.append(a);
      };
      for (const part of parts) {
        if ('code' in part) code(part.code);
        else barePaths(part.text, code, (q) => refsIn(line, q));
      }
      body.append(line);
    }
    return refs.length ? [box, said] : [box];
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
      const pool = d.lines.concat(d.rest || []); // every line, for a reason that names a finding of another card
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
        const ns = near(x, pool);
        head.append(findingEl(h, x, ns.known));
        const meta = h('p', 'row-meta');
        meta.append(ctx.tag(x.repo), h('span', null, `declined by ${WHO[x.by] || 'no one named'}`), ctx.since(x.time, ' ago'));
        li.append(head, meta, ...why(x, h, ns));
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
