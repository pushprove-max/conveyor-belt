// SPDX-License-Identifier: Apache-2.0
// Declined: the review findings that were not built, newest first, each with who declined it (code, the judge or
// the owner) and why. Its part: {lines, rest}; lines are the ones the panel shows (not dismissed, not built, at most 7
// days old), rest every other (the newest the snapshot keeps, and the older ones from the history); a line is {repo, repoUrl, id, time, card, issue, name (a main-red fix card's, which has issue 0, or null), url, finding, by, why, built, dismissed}, as
// the project's declined list holds it (conveyor.sh declined()), with round and findings (the review the judge
// declined it in and that review's findings as the judge numbered them), which turn each F<n> of the judge's reason
// into the finding it means (why, below). "File as issue" (confirmed by a second click within 5 s: it costs a build) files the
// finding as an ordinary issue, through POST /control build with the line's repository and id; the line is greyed in
// place at once, and built is that issue once it is filed, the line then saying so in place of the button. "Dismiss"
// (one line, on a second click that says it is for good), "Dismiss all shown (n)" and "Dismiss all (n)" (in the panel's
// heading, confirmed by a second click: the n open lines drawn; every line the panel counts, drawn or not) mark lines dismissed, through POST /control dismiss, one a
// project (400 lines at most a request): they leave the panel and its count at once, and stay in the list. The
// reviewer is told the reasons of the lines not built, dismissed or not,
// so it does not raise them again. An open line with 2 days or less before it leaves the panel (7 days after its time)
// says when: "Expires in 1 d 4 h", brought in and counted down by the clock. "Show every line" (?declined=all) shows the rest too, each marked: dismissed (by
// whom, when), filed, or more than 7 days old. A review's declined count (ctx.judged, on a card's review steps) opens
// the panel on that card's lines alone, every one of them (?declined=<card>), with a note that says so, a button to
// every line and one back to the list. A dismissed, built or old line is greyed and tagged Dismissed, Built or Expired.
// Above the lines, on the panel's own list, the Self-heals list (healsEl, below) with each area's "File a batch card",
// and the Docs list with each area's "File a docs sweep card".
(() => {
  const WHO = { code: 'the code', judge: 'the judge', owner: 'the owner' };
  const DISMISS_MAX = 400; // the most ids POST /control dismiss takes in one request (dashboard_server.py control_ok)
  const DAY = 86400000, KEEP = 7 * DAY, WARN = 2 * DAY; // a line leaves the panel KEEP after its time; WARN before, it says so
  // What the owner did with a line since the page loaded, through every redraw: said (the host's answer), busy (sent,
  // no answer yet) and gone (dismissed here: {time, by}, until a snapshot has the line in its rest).
  // filed: the lines the host filed here, greyed until a list shows them built.
  const said = new Map(), busy = new Set(), gone = new Map(), filed = new Set();
  let allSaid = ''; // the host's answer to "Dismiss all shown" or "Dismiss all", when it refused
  // By button: the keys of the lines "Dismiss all shown" or "Dismiss all" was first clicked for; a second click sends
  // them only while they are still its targets, so a click never dismisses lines its count did not name.
  const allArmed = {};
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
  // Each pattern is made once, not once a row or a reference.
  const FIRST_RE = /^.*?[.!?](?=\s|$)/;
  const HEAD_RE = /^(\[P([0-9])\])(\s+|(?=\[))((?:\[(?:[A-Za-z]+[0-9]+|cleanup)\]\s*)*)(\S+?:[0-9]+(?:[–-][0-9]+)?)(\s+)([\s\S]*)$/;
  const CLAIM_RE = /^\S[\s\S]*?(?:[.!?](?=\s|$)|$)\s*/;
  const FREF_RE = /\bF([0-9]+)\b/g; // matchAll works on a copy, so its lastIndex is never shared
  const SPECIAL_RE = /[.*+?^${}()|[\]\\]/g;
  // A finding's first sentence: its level, file and line lead it.
  const first = (s) => { const m = FIRST_RE.exec(s); return m ? m[0] : s; };
  // The text formatting every panel shares (app.js, findingText): the sentences, the code spans and the links to a
  // file's line, in the line's repository (repoUrl: a main-red fix card has no issue url).
  const T = window.DASH_APP.text;
  const { sentences, pathsIn, barePaths } = T;
  const codeEl = (x, s, known, cls) => T.codeEl(x.repoUrl, s, known, `${cls}-at`);
  const LEVELS = new Set(['0', '1', '2', '3']);
  // A finding, as "[P<n>] <file>:<line> <claim>. <more> Proof: <proof>": a head line (the level as a coloured badge,
  // the file and line as code linked to that line), the claim in bold on its own line, then the proof under a "Proof"
  // label, a sentence a line. Text in backticks and bare file paths are code. A finding of another shape is drawn as
  // its sentences. The text drawn is the finding as written, without its backticks.
  const findingEl = (h, x, known) => {
    const text = typeof x.finding === 'string' && x.finding ? x.finding : 'no finding';
    const box = h('div', 'title declined-finding');
    const fill = (el, s) => T.fill(el, s, x.repoUrl, known, 'declined');
    // A review's id for the finding ("[E1]", "[F2]") and the "[cleanup]" mark (prompts.sh REVIEWT), when it has them,
    // stand between the level and the file.
    const m = HEAD_RE.exec(text);
    if (!m) { fill(box, text); return box; }
    const head = h('div', 'declined-head');
    const badge = h('span', 'declined-level', m[1]);
    badge.dataset.level = LEVELS.has(m[2]) ? `P${m[2]}` : 'none';
    head.append(badge, m[3]);
    if (m[4]) head.append(h('span', 'declined-ids', m[4]));
    head.append(codeEl(x, m[5], known, 'declined').el, m[6]);
    box.append(head);
    const rest = m[7];
    // "Proof:" outside backticks splits the claim (and what follows it) from the proof.
    const { at: cut, label } = T.proofAt(rest);
    const said = cut < 0 ? rest : rest.slice(0, cut), proof = cut < 0 ? '' : rest.slice(cut + label.length);
    const claim = CLAIM_RE.exec(said)?.[0] || said; // the first sentence, its space kept
    if (claim) { const b = h('strong', 'declined-claim'); fill(b, claim); box.append(b); }
    if (said.length > claim.length) { const r = h('div', 'declined-more'); fill(r, said.slice(claim.length)); box.append(r); }
    if (cut >= 0) {
      const p = h('div', 'declined-proof');
      p.append(h('span', 'declined-proof-label', label));
      fill(p, proof);
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
  // One index of the pool a render: each project's lines with a finding and a readable time, newest first (the pool's
  // order kept between lines of one time), each with its time and the paths its finding names, parsed once; and the
  // pattern of each `file:line` a reason names, made once (at).
  const indexOf = (pool) => {
    const by = new Map();
    pool.forEach((y) => {
      if (!y || typeof y.finding !== 'string') return;
      const t = Date.parse(y.time);
      if (Number.isNaN(t)) return;
      if (!by.has(y.repo)) by.set(y.repo, []);
      by.get(y.repo).push({ y, t, k: key(y), paths: pathsIn(y.finding) });
    });
    by.forEach((es) => es.sort((a, b) => b.t - a.t));
    const ats = new Map();
    const at = (place) => {
      // The level, then any of the tags HEAD_RE takes ([E1], [cleanup]), then the place.
      if (!ats.has(place)) ats.set(place, new RegExp(`^\\[P[0-9]\\](?:\\s*\\[(?:[A-Za-z]+[0-9]+|cleanup)\\])*\\s+${place.replace(SPECIAL_RE, '\\$&')}\\b(?![-–])`));
      return ats.get(place);
    };
    return { by, at };
  };
  // The project's other lines declined by the time x's reason was written (kin), and the paths the line's findings and
  // reasons name (known, for the links to a file's line), read from the render's index.
  const near = (x, ix) => {
    // Only a finding declined by the time the reason was written can be the one it names; a line with no readable
    // time is not known to be earlier.
    const when = Date.parse(x.time), es = ix.by.get(x.repo) || [], k = key(x);
    // Newest first: the first line at or before `when`, and every one after it.
    let lo = 0, hi = es.length;
    while (lo < hi) { const mid = (lo + hi) >> 1; if (es[mid].t > when) lo = mid + 1; else hi = mid; }
    const ks = Number.isNaN(when) ? [] : es.slice(lo).filter((e) => e.k !== k);
    const own = [x.finding, x.why].concat(Array.isArray(x.findings) ? x.findings.map((y) => y && y.finding) : []).flatMap(pathsIn);
    return { kin: ks.map((e) => e.y), known: new Set(own.concat(...ks.map((e) => e.paths))), at: ix.at };
  };
  const why = (x, h, { kin, known, at: atOf }) => {
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
      for (const m of s.matchAll(FREF_RE)) {
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
        const { el: a, to } = codeEl(x, s, known, 'why');
        if (!to) { line.append(a); return; }
        const at = atOf(to.at);
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
  // The Self-heals list, above the declined lines on the panel's own list (d.heals: each project's, as the snapshot's
  // selfheals gives it): the findings the judge sorted as self-heals, whose failure heals itself. No follow-up builds
  // them one by one, and nothing here needs anyone now: an area's batch card fixes its entries together. Each area
  // shows its count, its entries (the finding, the card it came from, its kind, none for an entry with no kind, and the
  // judge's reason) and "File a batch card", which a second click confirms (it costs a build): POST /control heals
  // batch <area> (- for the entries with no area) with the project's repository, and the host files one card with the
  // area's entries as its scope. Its answer stays under the button (healsSaid). Under the heading, when the sort of
  // the queued follow-ups last ran, or that it has not run. The self-heals list holds the cleanup and already-guarded
  // findings too, each with its kind. Under it, the Docs list (each project's selfheals.docs): the findings the judge
  // sorted as docs drift. No entry expires; each area has "File a docs sweep card" (POST /control heals docs <area>),
  // and a release files one for each area with entries.
  const healsSaid = new Map(); // `${kind}:${repo}:${area}` -> the host's answer, through every redraw
  const docsOf = (x) => ((x.docs && x.docs.entries) || []);
  const healsOf = (d) => (Array.isArray(d.heals) ? d.heals : []).filter((x) => x && ((x.entries || []).length || x.sorted || docsOf(x).length));
  // A list's entries by area, the areas in the snapshot's order (areas: the most entries first), none left empty.
  const byAreas = (areas, entries) => {
    const m = new Map((areas || []).filter((y) => y && y.count > 0).map((y) => [y.area || '', []]));
    (entries || []).forEach((e) => { const a = e.area || ''; m.set(a, (m.get(a) || []).concat(e)); });
    m.forEach((es, a) => { if (!es.length) m.delete(a); });
    return m;
  };
  const healsEl = (d, ctx) => {
    const h = ctx.h, lists = healsOf(d).filter((x) => (x.entries || []).length || x.sorted), docs = healsOf(d).filter((x) => docsOf(x).length);
    const out = [];
    if (lists.length) {
      const all = lists.reduce((n, x) => n + (x.entries || []).length, 0);
      const box = h('section', 'heals');
      box.dataset.part = 'heals';
      box.append(h('h3', 'heals-title', `Self-heals list (${all})`),
        h('p', 'row-meta', 'Findings whose failure heals itself (a longer wait, a step run again, text the next poll corrects), cleanup with no change to what the code does, and findings another check already guards. No follow-up builds them one by one: file an area\'s batch card when you choose. Nothing here needs you now.'));
      lists.forEach((x) => {
        const s = x.sorted, sorted = h('p', 'row-meta heals-sorted');
        if (lists.length > 1) sorted.append(ctx.tag(x.repo));
        if (s && s.time) sorted.append(h('span', null, `The sort of the queued follow-ups ran, and moved ${s.moved} of ${s.items} to the lists${s.failed ? ` (its judge failed: ${s.failed})` : ''}:`), ctx.since(s.time, ' ago'));
        else sorted.append(h('span', null, 'The sort of the queued follow-ups has not run yet.'));
        box.append(sorted);
        byAreas(x.areas, x.entries).forEach((es, a) => box.append(healsArea(ctx, x, a, es, lists.length > 1, false)));
      });
      out.push(box);
    }
    if (docs.length) {
      const box = h('section', 'heals heals-docs');
      box.dataset.part = 'docs';
      box.append(h('h3', 'heals-title', `Docs list (${docs.reduce((n, x) => n + docsOf(x).length, 0)})`),
        h('p', 'row-meta', 'Guides and READMEs that omit or misdescribe what the code does. No entry expires: file an area\'s docs sweep card when you choose. A release files one for each area with entries.'));
      docs.forEach((x) => byAreas(x.docs.areas, docsOf(x)).forEach((es, a) => box.append(healsArea(ctx, x, a, es, docs.length > 1, true))));
      out.push(box);
    }
    return out;
  };
  // One area of a project's list (healsEl): its name, count and "File a batch card" (with docs, "File a docs sweep
  // card"), then its entries; each entry names its project when the Board shows more than one (many).
  const healsArea = (ctx, x, a, es, many, docs) => {
    const h = ctx.h, k = `${docs ? 'docs' : 'batch'}:${x.repo}:${a}`, n = es.length;
    const area = h('div', 'heals-area');
    area.dataset.area = a;
    const head = h('p', 'row-main'), note = h('span', 'answer-note');
    note.setAttribute('aria-live', 'polite');
    note.textContent = healsSaid.get(k) || '';
    const b = h('button', 'btn', docs ? 'File a docs sweep card' : 'File a batch card');
    b.type = 'button'; b.dataset.act = docs ? 'heals-docs' : 'heals-batch';
    ctx.twice(b, 'spend', `Click again to file one card with these ${n === 1 ? 'one finding' : `${n} findings`}`, () => {
      b.disabled = true; note.textContent = 'Sending…';
      ctx.post('control', { action: 'heals', args: [docs ? 'docs' : 'batch', a || '-'], repo: x.repo })
        .then(answer, noAnswer)
        .then((r) => { healsSaid.set(k, r.ok ? `Filed: ${r.said}. The list leaves these entries in about a minute.` : `Not filed: ${r.said}`); b.disabled = false; ctx.redraw(); });
    });
    head.append(h('strong', null, a || 'No area'), h('span', 'row-meta', ` ${n === 1 ? '1 entry' : `${n} entries`} `), b, ' ', note);
    const ul = h('ul', 'rows heals-rows');
    es.forEach((e) => {
      const li = h('li', 'row');
      const main = h('div', 'row-main');
      main.append(h('span', 'title', e.finding));
      const meta = h('p', 'row-meta');
      if (many) meta.append(ctx.tag(e.repo));
      meta.append(h('span', null, `from card ${e.card}`), ' ', ctx.issueLink(e));
      if (e.effect) meta.append(' ', h('span', 'chip chip-quiet heals-kind', e.effect));
      meta.append(ctx.since(e.time, ' ago'));
      li.append(main, meta, h('p', 'reason heals-why', `The judge: ${e.why || 'no reason given'}`));
      ul.append(li);
    });
    area.append(head, ul);
    return area;
  };
  window.DASH_APP.panel({
    id: 'declined',
    title: 'Declined',
    size: 'wide',
    tab: 'overview',
    projects: true,
    declinedOf: 'declined',
    rows: 5, // the step of its list (ctx.more)
    // The live part's rest holds the newest lines the snapshot keeps; the others come from the history.
    older: (d, o) => Object.assign({}, d, { rest: window.DASH_APP.joined(d.rest, o.rest, key) }),
    count: (d) => shown(d).length,
    isEmpty: (d) => d.lines.length === 0 && (d.rest || []).length === 0 && healsOf(d).length === 0,
    empty(el, ctx) { el.append(ctx.state('empty', 'No declined finding', 'A review finding that Conveyor did not build shows here with who declined it and why.')); },
    error(el, message, ctx) { el.append(ctx.state('error', 'The Board could not read the declined findings', message)); },
    render(el, d, ctx) {
      const h = ctx.h;
      const ul = h('ul', 'rows');
      // Every line, for a reason that names a finding of another card: indexed once a render, read by each row (near).
      const ix = indexOf(d.lines.concat(d.rest || []));
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
        const ns = near(x, ix);
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
        // File as issue costs a build: it asks for a second click (ctx.twice: the first click arms it for 5 s). Dismiss
        // cannot be undone: a second click too.
        const b = h('button', 'btn', 'File as issue'), off = h('button', 'btn btn-quiet', 'Dismiss');
        b.type = 'button'; off.type = 'button';
        b.dataset.act = 'build'; off.dataset.act = 'dismiss';
        const draw = () => {
          b.disabled = busy.has(k); off.disabled = busy.has(k);
          // Filed, the line is greyed in place and its buttons go, until the list no longer shows it.
          li.classList.toggle('is-pending', filed.has(k));
          b.hidden = filed.has(k); off.hidden = filed.has(k);
          note.textContent = said.get(k) || '';
        };
        ctx.twice(b, 'spend', 'Click again to file it as an issue', () => {
          if (busy.has(k)) return;
          busy.add(k); said.set(k, 'Sending…'); draw();
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
          said.set(k, 'Sending…'); draw();
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
      // The rows drawn now ("Dismiss all shown" takes their open lines, no more; "Dismiss all" takes every line counted).
      let drawn = [];
      const bar = h('p', 'foot');
      const btn = (text, act, quiet) => { const b = h('button', quiet ? 'btn btn-quiet' : 'btn', text); b.type = 'button'; b.dataset.act = act; return b; };
      const go = (v) => { ctx.params({ declined: v }); this.render(el, d, ctx); ctx.relength(); };
      const said0 = h('span', 'answer-note');
      said0.setAttribute('aria-live', 'polite');
      if (view === 'all') bar.append(h('span', null, 'Every line: dismissed, filed and older ones too. '));
      else if (view) bar.append(h('span', null, lines.length ? `Showing the ${lines.length === 1 ? 'line' : `${lines.length} lines`} of ${typeof lines[0].name === 'string' && lines[0].name ? lines[0].name : `#${lines[0].issue}`} only. ` : 'No line of that card is in the list. '));
      else if (!lines.length) bar.append(h('span', null, 'Nothing to look at: you dismissed or filed each line, or the line is more than 7 days old. '));
      // "Dismiss all shown (n)" and "Dismiss all (n)", in the panel's heading and coloured as a warning, unlike the
      // harmless buttons below: the first click asks, the second sends the n lines its count named, and only while
      // those same lines are its targets. "Dismiss all shown" takes the open lines drawn; "Dismiss all", on the panel's
      // own list (not a card's lines or every line), takes every line the panel counts, drawn or not. They cannot be
      // undone, and the second-click text says so.
      const ids = (xs) => xs.map(key).join(' ');
      const bulks = [
        { act: 'dismiss-all', label: 'Dismiss all shown', where: 'shown', targets: () => drawn.filter((x) => open(x) && !busy.has(key(x))) },
        { act: 'dismiss-every', label: 'Dismiss all', where: 'in the panel, drawn or not', targets: () => (view ? [] : shown(d).filter((x) => open(x) && !busy.has(key(x)))) },
      ];
      const drawAll = () => {
        let ask = '';
        bulks.forEach((u) => {
          u.xs = u.targets();
          if (allArmed[u.act] && allArmed[u.act] !== ids(u.xs)) allArmed[u.act] = null;
          const on = Boolean(allArmed[u.act]);
          const n = u.xs.length === 1 ? 'the line' : `the ${u.xs.length} lines`;
          u.b.textContent = on ? `Click again to dismiss ${n} for good` : `${u.label} (${u.xs.length})`;
          u.b.setAttribute('aria-pressed', String(on));
          u.b.toggleAttribute('data-armed', on);
          if (on) ask = `Click again to dismiss ${n} ${u.where}: they leave the panel, and the reviewer still does not raise them again.`;
        });
        said0.textContent = ask || allSaid;
        ctx.headActs(...bulks.filter((u) => u.xs.length).map((u) => u.b));
      };
      bulks.forEach((u) => {
        u.b = btn('', u.act);
        u.b.classList.add('btn-warn');
        u.b.addEventListener('click', () => {
          const xs = u.targets();
          if (!xs.length) return;
          // One button armed at a time, so the note says what the next click sends.
          if (allArmed[u.act] !== ids(xs)) { bulks.forEach((o) => { allArmed[o.act] = null; }); allArmed[u.act] = ids(xs); drawAll(); return; }
          bulks.forEach((o) => { allArmed[o.act] = null; o.b.disabled = true; });
          allSaid = 'Sending…'; said0.textContent = allSaid;
          dismiss(xs, (bad) => { allSaid = bad.length ? `Not dismissed: ${bad.join('; ')}` : ''; });
        });
      });
      if (view === 'all') { const b = btn("Show the panel's lines", 'declined-panel', true); b.addEventListener('click', () => go(null)); bar.append(b); }
      else { const b = btn('Show every line', 'declined-all', true); b.addEventListener('click', () => go('all')); bar.append(b); }
      if (view && view !== 'all') { const b = btn('Back to the list', 'declined-list', true); b.addEventListener('click', () => go(null)); bar.append(' ', b); }
      bar.append(' ', said0);
      // The collector gives them newest first. A row is kept by its line (repo:id): "Show 5 more" adds the new rows
      // under the ones shown, which stay the same nodes and keep an open F-number explanation; the focus moves to the
      // first new row.
      el.replaceChildren(...(view ? [] : healsEl(d, ctx)), bar, ul, ctx.more(view ? `declined:${view}` : 'declined', lines, (ls) => { drawn = ls; ctx.list(ul, ls, key, row); drawAll(); }));
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
