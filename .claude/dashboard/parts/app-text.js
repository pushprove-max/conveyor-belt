// SPDX-License-Identifier: Apache-2.0
// The Board's words for a card: its times, model names, review findings and their lines, a card's output, the
// lengths and Needs-you drafts a reload keeps, and the words for dependencies and refusals. Part of app.js, which
// hands it `app` (its names, and its state through getters and setters) as it loads (DASH_APP.core); boot.js loads
// it before the panels.
(() => {
  'use strict';
  // What this part uses of app.js and of its other parts, each bound as it loads (app.bind, at the end).
  let app, ago, chip, form, goTo, h, modules, now, num, param, params, parse, projectOnly, redrawAll, stamp;
  const bindNames = () => ({ ago, chip, form, goTo, h, modules, now, num, param, params, parse, projectOnly, redrawAll,
    stamp } = app);
  const dur = (sec) => (typeof sec === 'number' && sec >= 0 ? ago(sec * 1000) : null);
  // A step's time as measured: a step is often under a minute, so its seconds are given then.
  const took = (sec) => (sec < 60 ? `${Math.max(0, Math.round(sec))} s` : sec < 3600 ? `${Math.floor(sec / 60)} min` : `${Math.floor(sec / 3600)} h ${String(Math.floor((sec % 3600) / 60)).padStart(2, '0')} min`);
  const clock = (iso) => { const t = parse(iso); return t === null ? 'not read' : stamp(t); };
  // A time of day, with the date when it is not today (when a card was picked up).
  function when(iso) {
    const t = parse(iso);
    if (t === null) return 'not read';
    return stamp(t, { date: new Date(t).toDateString() !== new Date(now()).toDateString() });
  }
  // A model ID as the Board shows it: an alias in a project's pack (Rules, Model prices) is the display name of the
  // model it means, and a model the pack gives a display name, or names aliases of, has that name; ":fast" stays on. Any other ID is shown
  // as it is. Read from the Rules part's prices, the project steered first, then each other project's.
  function allPrices() {
    const r = app.last && app.last.panels && app.last.panels.rules && app.last.panels.rules.data;
    return r && typeof r === 'object' ? [r.prices].concat(Object.values(r.others && typeof r.others === 'object' ? r.others : {}).map((o) => o && o.prices)) : [];
  }
  const namesKey = () => JSON.stringify(allPrices().map((p) => (p && typeof p === 'object' ? [p.overrides, p.names] : null)));
  // The display name that one price list p (its overrides and names) gives the model ID <base>; null when it gives none.
  function nameIn(p, base) {
    if (!p || typeof p !== 'object' || !p.overrides || typeof p.overrides !== 'object') return null;
    const over = p.overrides, names = p.names && typeof p.names === 'object' ? p.names : {};
    const named = (m) => (over[m] && typeof over[m].name === 'string' && over[m].name ? over[m].name : null);
    const to = Object.keys(over).find((m) => over[m] && Array.isArray(over[m].aliases) && over[m].aliases.includes(base));
    if (to) return named(to) || (typeof names[to] === 'string' ? names[to] : to);
    // A model other IDs are aliases of: a finished step on an alias is recorded as this ID (pricedAs), so it has the
    // display name a running step on the alias shows.
    const target = over[base] && Array.isArray(over[base].aliases) && over[base].aliases.length > 0 && typeof names[base] === 'string' ? names[base] : null;
    return named(base) || target || null;
  }
  function modelName(id) {
    if (typeof id !== 'string') return id;
    const all = allPrices();
    const fast = id.endsWith(':fast'), base = fast ? id.slice(0, -5) : id, tail = fast ? ':fast' : '';
    for (const p of all) {
      const name = nameIn(p, base);
      if (name !== null) return `${name}${tail}`;
    }
    return id;
  }
  // A review's findings by level, "1 P1, 2 P2"; one recorded with no counts shows its verdict alone: ''.
  function findings(r) {
    const c = r && r.counts;
    if (!c || typeof c !== 'object') return '';
    return ['P0', 'P1', 'P2', 'P3'].filter((k) => typeof c[k] === 'number' && c[k] > 0).map((k) => `${c[k]} ${k}`).join(', ');
  }
  // The findings of a review that came back after the fix rounds told to fix them (its survived, each {id, rounds}):
  // "E2 came back after 2 fix rounds"; '' when none did.
  function survived(r) {
    const s = r && Array.isArray(r.survived) ? r.survived.filter((x) => x && typeof x.id === 'string' && num(x.rounds)) : [];
    return s.map((x) => `${x.id} came back after ${x.rounds} ${x.rounds === 1 ? 'fix round' : 'fix rounds'}`).join(', ');
  }
  // Why the fix loop ended on this review (its loopEnd, {stop, own, rounds}): "Fix loop ended: review limit reached
  // (3 reviews, 1 from earlier cards)"; '' on a review after which a fix round came.
  const loopWhy = {
    go: 'the review passed', 'max-reviews': 'review limit reached', rebased: 'one review after a landing conflict',
    'test-fix': 'one review after the test fix', 'lint-fix': 'one review after the lint fix',
    land: 'landed on the kept review', repeat: 'a fixed finding came back, all findings P2 or P3',
  };
  function loopEnd(r) {
    const e = r && r.loopEnd;
    if (!e || !Object.prototype.hasOwnProperty.call(loopWhy, e.stop)) return '';
    const p = num(e.own) ? e.own : 0, k = num(e.rounds) ? e.rounds : 0, all = p + k;
    return `Fix loop ended: ${loopWhy[e.stop]} (${all} ${all === 1 ? 'review' : 'reviews'}${k ? `, ${k} from earlier cards` : ''})`;
  }
  // A review's verdict in words: GO is "passed", NO-GO "changes asked" (the records' codes are never shown on a card).
  const verdictSaid = (v) => (v === 'GO' ? 'passed' : v === 'NO-GO' ? 'changes asked' : 'no verdict');
  // A finished review on a card: "Review 2: changes asked", its chip toned by the verdict.
  const reviewChip = (r) => chip(`Review ${r && num(r.round) ? r.round : '?'}: ${verdictSaid(r && r.verdict)}`, r && r.verdict === 'GO' ? 'ok' : 'warn');
  // What the judge made of a review (its judge, as the snapshot gives it): "judge: N accepted, M declined"; "passed
  // (the judge declined all M)" for a GO that came from the judge declining every finding. The declined count is a button:
  // it opens that card's lines in the panel that lists the declined findings, the module with declinedOf (the address
  // parameter that cuts it to one card's lines). null, so no judge line, for a review the judge did not read (ran not
  // true) or with no judge recorded.
  function judged(r, card) {
    const j = r && r.judge;
    if (!j || typeof j !== 'object' || j.ran !== true) return null;
    const el = h('span', 'judged');
    const a = num(j.accepted) ? j.accepted : 0, m = num(j.declined) ? j.declined : 0;
    const lines = Array.from(modules.values()).find((x) => typeof x.declinedOf === 'string' && x.declinedOf);
    const open = (text) => {
      if (!m || !lines || typeof card !== 'string' || !card) return text;
      const b = h('button', 'btn btn-quiet judged-open', text);
      b.type = 'button';
      b.dataset.act = 'declined-of';
      b.title = `Show this card's lines in the ${lines.title} panel`;
      b.addEventListener('click', () => { params({ [lines.declinedOf]: card }); redrawAll(); goTo(lines.id); });
      return b;
    };
    if (j.go === true) el.append('passed (the judge ', open(`declined all ${m}`), ')');
    else el.append(`judge: ${a} accepted, `, open(`${m} declined`));
    return el;
  }
  // The end of the output a blocked card failed on (its line's tail), shown under its sentence: closed under "Show
  // output", in monospace with its line breaks; the card's worktree prefix is ./, identical lines in a row are one line
  // with ×N, and its FAIL and error lines are counted and listed first (an output of one line has no such list: it would
  // only say that line again, above it). A review's output (a line of it starts [P0] to
  // [P3]) is its findings instead: one row each (findingRows), with no failures list. Copy puts the output as shown on the
  // clipboard, as plain text. null when there is no output. label: the words of its toggle, when not "Show output".
  // was: the toggle this one replaces in a redraw, if any: open, for the same card, it stays open with the new output.
  // The reader's place in it stays too: with the same output the toggle is that one, and its scroll and a text
  // selection in it are put back once the redraw has put it in the page again; with more, the new one is scrolled where
  // the old one was. A box built new each
  // second sent a reader who scrolled up in a running card's output back to the top, and stalled a scroll over it.
  const FAILLINE = /\bFAIL(?:ED)?\b|\b(?:error|Error|ERROR)\b|: (?:cannot|can't) |No such file or directory|Permission denied|command not found/;
  // ---- a finding's or a reason's text, drawn as the Declined panel first drew it (#403) ----
  // Declined, a card's review output, a blocked card's reason and Health's lists all draw their text with these
  // (window.DASH_APP.text, findingText here): each `code` span set apart (app.css .why-code), each file and line a link to that line.
  // A text with no code span and no path draws as plain text.
  // A text split into sentences, each a list of parts: {code} (a span the text has in backticks, drawn without them)
  // or {text}. A sentence ends at a . ! or ? before a space, outside backticks; the space stays at its end, so the
  // sentences joined (with the backticks) are the text as written. A lone backtick is left as text.
  function sentences(text) {
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
  }
  // The paths with a directory that a text names before a :line ("conveyor/lib/claim.sh:99").
  const PATH_AT = /(?:^|[^A-Za-z0-9_./-])((?:[A-Za-z0-9_.-]+\/)+[A-Za-z0-9_.-]+):[0-9]/g;
  const pathsIn = (s) => (typeof s === 'string' ? Array.from(s.matchAll(PATH_AT), (m) => m[1]) : []);
  // A repository's GitHub address as owner/repo, or null when it is not one.
  const ownerRepo = (u) => /^https:\/\/github\.com\/([A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+)$/.exec(typeof u === 'string' ? u : '')?.[1] || null;
  // An item's repository on GitHub: its repoUrl, else the repository of its issue's url; null when it has neither.
  function repoOf(x) {
    if (!x || typeof x !== 'object') return null;
    if (ownerRepo(x.repoUrl)) return x.repoUrl;
    const m = typeof x.url === 'string' ? /^(https:\/\/github\.com\/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+)\/issues\/\d+$/.exec(x.url) : null;
    return m ? m[1] : null;
  }
  // A file of the repository, as a link to it on GitHub; null when the repository is not on GitHub or the path climbs
  // out of it.
  function fileUrl(repoUrl, path) {
    const repo = ownerRepo(repoUrl);
    if (!repo || typeof path !== 'string' || !/^(?:[A-Za-z0-9_.-]+\/)*[A-Za-z0-9_.-]+$/.test(path) || path.split('/').some((s) => s === '.' || s === '..')) return null;
    return `https://github.com/${repo}/blob/HEAD/${path}`;
  }
  // A `file:line` (or `file:a–b`), as a link to those lines on GitHub in the repository repoUrl; null when the span is no
  // file and line, or the repository is not on GitHub. A short path ("issues.sh:636") is the one path of known (the
  // paths the text and its kin name) that ends with it; none or more than one, and it has no directory, it is no link,
  // as the repository root is only a guess.
  function lineUrl(repoUrl, code, known) {
    const m = /^((?:[A-Za-z0-9_.-]+\/)*[A-Za-z0-9_.-]+):([0-9]+)(?:[–-]([0-9]+))?$/.exec(code);
    if (!m) return null;
    let path = m[1];
    if (!known.has(path)) {
      const ends = [...known].filter((k) => k.endsWith(`/${path}`));
      if (ends.length === 1) path = ends[0];
      else if (!path.includes('/')) return null;
    }
    const url = fileUrl(repoUrl, path);
    return url ? { url: `${url}#L${m[2]}${m[3] ? `-L${m[3]}` : ''}`, at: `${path}:${m[2]}` } : null;
  }
  // A file path with a directory and a line ("shared/taxonomy/fields.ts:239") written without backticks.
  const BARE = /(?<![A-Za-z0-9_./-])(?:[A-Za-z0-9_.-]+\/)+[A-Za-z0-9_-][A-Za-z0-9_.-]*\.[A-Za-z0-9]+:[0-9]+(?:[–-][0-9]+)?/g;
  // Plain text, each bare path in it given to at (drawn as code), the rest to plain; the text is kept as written.
  function barePaths(s, at, plain) {
    let from = 0;
    for (const m of s.matchAll(BARE)) {
      if (m.index > from) plain(s.slice(from, m.index));
      at(m[0]);
      from = m.index + m[0].length;
    }
    if (from < s.length) plain(s.slice(from));
  }
  // A link of class cls round el, opening url in a new tab.
  function linkTo(el, url, cls) {
    const a = h('a', cls);
    a.href = url; a.target = '_blank'; a.rel = 'noopener noreferrer';
    a.append(el);
    return a;
  }
  // A span of code: monospace, italic and in the accent colour (app.css .why-code); a file and line in it is a link of
  // class cls to that line on GitHub (lineUrl), with the link returned so a caller can say more of it on hover.
  function codeEl(repoUrl, s, known, cls) {
    const c = h('code', 'why-code', s), to = lineUrl(repoUrl, s, known);
    return to ? { el: linkTo(c, to.url, cls), to } : { el: c, to: null };
  }
  // Text s drawn into el: a span of class `${cls}-line` a sentence, its code spans and bare file paths as codeEl draws
  // them (links of class `${cls}-at`), the rest as text.
  function fill(el, s, repoUrl, known, cls) {
    for (const parts of sentences(s)) {
      const line = h('span', `${cls}-line`);
      const code = (q) => line.append(codeEl(repoUrl, q, known, `${cls}-at`).el);
      for (const p of parts) {
        if ('code' in p) code(p.code);
        else barePaths(p.text, code, (q) => line.append(q));
      }
      el.append(line);
    }
    return el;
  }
  // Where a finding's proof starts: its "Proof:" outside backticks, else -1; label: the "Proof:" and the space after it.
  function proofAt(s) {
    for (const p of s.matchAll(/`[^`]*`|\bProof:\s*/g)) if (p[0][0] !== '`') return { at: p.index, label: p[0] };
    return { at: -1, label: '' };
  }
  const findingText = { sentences, pathsIn, repoOf, fileUrl, lineUrl, barePaths, linkTo, codeEl, fill, proofAt };

  // A review finding: "[P1] path:line The sentence. Proof: why", its place and proof each optional. A "[cleanup]" mark
  // after the level (a fix that changes no behaviour, prompts.sh REVIEWT) is not drawn.
  const FINDING = /^\[(P[0-3])\]\s*(?:\[cleanup\]\s*)?(.*)$/;
  // A review's findings as rows, in their order: the priority chip (P0 and P1 warn, P2 and P3 quiet) and the sentence
  // in bold on one line, the place (path:line) under it as a link to that line, and the part after "Proof:" folded
  // under a closed "Proof:" toggle. Code spans and file paths in the sentence and proof are drawn as fill draws them,
  // linked in the repository repoUrl (none: no links). A line that is not a finding is a row of its whole text.
  // With the card, its repository (repo, the record's name) and the review the findings are from (review, the time of
  // its record), the place has a closed "Reviewed lines" toggle under it: opened, it shows the lines the place cites as
  // that review read them (reviewedLines).
  function findingRows(folded, repoUrl, card, repo, review) {
    const list = h('ol', 'output-findings');
    const known = new Set(folded.flatMap((x) => pathsIn(x.text)));
    const lines = [card, repo, review].every((s) => typeof s === 'string' && s) ? reviewedLines(repo, card, review) : null;
    folded.forEach((x) => {
      if (!x.text.trim()) return;
      const row = h('li', 'output-finding'), m = FINDING.exec(x.text), times = x.n > 1 ? ` ×${x.n}` : '';
      if (!m) { row.append(h('p', 'finding-text', x.text + times)); list.append(row); return; }
      let rest = m[2];
      const at = /^(\S+:\d+(?:[-–]\d+)?)[:,]?\s+(?=\S)/.exec(rest);
      if (at) rest = rest.slice(at[0].length);
      const { at: cut, label } = proofAt(rest);
      const sentence = (cut < 0 ? rest : rest.slice(0, cut)).trim(), proof = cut < 0 ? '' : rest.slice(cut + label.length);
      const head = h('div', 'finding-head'), said = h('p', 'finding-text');
      said.append(fill(h('strong', 'finding-claim'), sentence, repoUrl, known, 'finding'));
      if (times) said.append(times);
      head.append(chip(m[1], m[1] === 'P0' || m[1] === 'P1' ? 'warn' : 'quiet'), said);
      row.append(head);
      if (at) { const p = h('p', 'finding-at'); p.append(codeEl(repoUrl, at[1], known, 'finding-at-link').el); row.append(p); }
      if (at && lines) row.append(lines(at[1]));
      if (proof) {
        const fold = h('details', 'finding-proof');
        fold.append(h('summary', 'finding-proof-label', 'Proof:'), fill(h('div', 'finding-proof-text'), proof, repoUrl, known, 'finding'));
        row.append(fold);
      }
      list.append(row);
    });
    return list;
  }
  // The "Reviewed lines" toggles of one card's findings (findingRows): a function that makes the toggle of a place
  // (`path:line` or `path:a-b`, as the finding writes it). The lines are not in the snapshot: each review kept them from
  // the tree it read (its excerpts), so they stay after the card's worktree is gone, where main may hold other code.
  // They are read from the page server (GET excerpts: `conveyor.sh history excerpts <card>` on the build machine) when
  // the first toggle is opened, once for all the toggles of the box; one that did not come is read again at the next
  // open. A place shows the lines that its own review (review: the time of the review's record, which each excerpt
  // carries) kept for it, never a later or earlier review's of the same place, each excerpt with its side (the change's,
  // main's for lines the change deleted, or the one before a fix round for lines that fix deleted) and each line with
  // its number.
  function reviewedLines(repo, card, review) {
    let ask = null;
    const read = () => {
      if (!ask) {
        ask = window.fetch(`excerpts?repo=${encodeURIComponent(repo)}&card=${encodeURIComponent(card)}`)
          .then((r) => (r.ok ? r.json() : r.text().then((t) => Promise.reject(new Error(String(t).trim() || `the server answered ${r.status}`)))))
          .then((x) => (x && typeof x === 'object' && Array.isArray(x.excerpts) ? x.excerpts : Promise.reject(new Error('the answer did not read'))));
        ask.catch(() => { ask = null; });
      }
      return ask;
    };
    const norm = (s) => s.replace(/^\.\//, '').replace('–', '-');
    return (place) => {
      const det = h('details', 'finding-lines'), body = h('div', 'finding-lines-body');
      det.append(h('summary', 'finding-lines-label', 'Reviewed lines'), body);
      det.addEventListener('toggle', () => {
        if (!det.open || body.dataset.state === 'busy' || body.dataset.state === 'read') return;
        body.dataset.state = 'busy';
        body.replaceChildren(h('p', 'finding-lines-note', 'Reading the reviewed lines…'));
        read().then((all) => {
          const xs = all.filter((e) => e && typeof e === 'object' && e.review === review && typeof e.at === 'string' && norm(e.at) === norm(place) && Array.isArray(e.lines));
          body.dataset.state = 'read';
          if (!xs.length) { body.replaceChildren(h('p', 'finding-lines-note', 'The review kept no lines for this place.')); return; }
          body.replaceChildren(...xs.flatMap((x) => {
            const from = num(x.from) ? x.from : 1, pre = h('pre', 'finding-lines-text');
            x.lines.forEach((l, i) => {
              if (i) pre.append('\n');
              pre.append(h('span', 'finding-lines-n', `${from + i}`), ` ${typeof l === 'string' ? l : ''}`);
            });
            const side = x.side === 'old' ? "Main's side: lines the change deleted" : x.side === 'fix' ? 'Before the fix: lines the fix deleted' : "The change's side";
            return [h('p', 'finding-lines-note', side), pre];
          }));
        }, (e) => {
          body.dataset.state = 'failed';
          body.replaceChildren(h('p', 'finding-lines-note', `The reviewed lines did not come: ${e && e.message ? e.message : 'no answer'}`));
        });
      });
      return det;
    };
  }
  // The box det that output() gives back, with the scroll of the box it is drawn over (was) and a text selection in it.
  function keptOutput(det, was) {
    const from = was && was.querySelector('pre.output-text'), pre = det.querySelector('pre.output-text');
    if (!from || !pre) return det;
    const top = from.scrollTop, left = from.scrollLeft;
    // Each caller takes the box out of the page and puts it back, and that ends a text selection in it. A selection
    // in the box that is kept is read now, while it is there, and made again after the redraw with its same nodes.
    const sel = window.getSelection ? window.getSelection() : null;
    const mark = det === was && sel && sel.rangeCount && det.contains(sel.anchorNode) && det.contains(sel.focusNode)
      ? [sel.anchorNode, sel.anchorOffset, sel.focusNode, sel.focusOffset] : null;
    // A node taken out of the page and put back loses its scroll in a browser: it is put back after the redraw.
    window.queueMicrotask(() => {
      if (!pre.isConnected) return;
      pre.scrollTop = top;
      pre.scrollLeft = left;
      if (mark) sel.setBaseAndExtent(...mark);
    });
    return det;
  }
  // The lines of an output tail, each {text, n}: a path to the card's own folder is cut to ".", and equal lines one
  // after another are one line with their count n.
  function foldLines(tail, card) {
    const lines = tail.replace(/\s+$/, '').split('\n');
    const id = typeof card === 'string' && card ? card.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') : null;
    // A quoted path runs back to its quote, spaces and all; an unquoted one back to the / or ~ it starts with, so what
    // stands before it ("ERROR:", "PATH=/bin:") stays. An unquoted path does not start inside a word or a path. A URL
    // (a protocol-relative //host one too, quoted or not) is matched first and kept whole to the next space, quotes and
    // all, so https://example.com/?path='/one/<card>/log' stays as it is.
    const prefix = id ? new RegExp(`((?:[A-Za-z][\\w+.-]*:|(?<![\\w/.~-]))//\\S*)|(['"\`])(?:~|/(?!/))[^'"\`\\n]*?/${id}(?=/|['"\`])|(?<![\\w/.~-])(?:~|/(?!/))[^\\s'"\`:]*?/${id}(?=/|$|[\\s'"\`:,;)])`, 'g') : null;
    const folded = [];
    for (const raw of lines) {
      const text = prefix ? raw.replace(prefix, (m, url, q) => (url ? m : `${q || ''}.`)) : raw, last = folded[folded.length - 1];
      if (last && last.text === text) last.n += 1;
      else folded.push({ text, n: 1 });
    }
    return folded;
  }
  const shownLine = (x) => (x.n > 1 ? `${x.text} ×${x.n}` : x.text);
  // The output box's list of its failure lines, above the output; none for no failure line.
  function outputFails(det, fails) {
    if (!fails.length) return;
    const top = h('div', 'output-fails'), list = h('ul', null);
    list.append(...fails.map((x) => h('li', null, shownLine(x))));
    top.append(h('p', 'output-count', `${fails.length} ${fails.length === 1 ? 'failure' : 'failures'}`), list);
    det.append(top);
  }
  // The output box's text pre, then its Copy output button, which copies the folded lines.
  function outputCopy(det, pre, folded) {
    const copy = h('button', 'btn btn-quiet output-copy', 'Copy output'), note = h('span', 'output-note');
    copy.type = 'button';
    note.setAttribute('aria-live', 'polite');
    copy.addEventListener('click', () => {
      const text = folded.map(shownLine).join('\n'), clip = window.navigator.clipboard;
      (clip && clip.writeText ? clip.writeText(text) : Promise.reject(new Error('no clipboard')))
        .then(() => { note.textContent = 'Copied.'; }, () => { note.textContent = 'Not copied: the browser gave no clipboard.'; });
    });
    det.append(pre, h('div', 'output-acts'));
    det.lastChild.append(copy, note);
  }
  // repoUrl: the card's repository on GitHub (repoOf), in which a review finding's file paths link to their lines; none,
  // and they are code with no link. repo: the card's record (its repo), whose findings' places open the lines the review
  // read (findingRows) in the review whose record has the time reviewAt; none, and they do not.
  function output(tail, card, label, was, repoUrl, repo, reviewAt) {
    if (typeof tail !== 'string' || !tail.trim()) return null;
    const same = JSON.stringify([tail, typeof card === 'string' ? card : '', label || '']);
    if (was && was.outputText === same) return keptOutput(was, was);
    const folded = foldLines(tail, card);
    const review = folded.some((x) => FINDING.test(x.text));
    const det = h('details', 'output'), fails = review || folded.length < 2 ? [] : folded.filter((x) => FAILLINE.test(x.text));
    det.append(h('summary', null, label || 'Show output'));
    det.dataset.card = typeof card === 'string' ? card : '';
    det.open = Boolean(was && was.open && was.dataset.card === det.dataset.card);
    outputFails(det, fails);
    const pre = review ? findingRows(folded, repoUrl, card, repo, reviewAt) : h('pre', 'output-text');
    if (!review) folded.forEach((x, i) => {
      const line = h('span', FAILLINE.test(x.text) ? 'output-line is-fail' : 'output-line', x.text);
      if (x.n > 1) line.append(h('span', 'output-times', ` ×${x.n}`));
      pre.append(line);
      if (i < folded.length - 1) pre.append('\n');
    });
    outputCopy(det, pre, folded);
    det.outputText = same;
    return keptOutput(det, was);
  }
  // A time that keeps counting between refreshes: the ticker rewrites its text, so no panel is redrawn for it.
  // offset (seconds) is added: a card's overall time is the earlier cards' seconds and the time since its pick-up.
  function since(iso, suffix, offset) {
    const el = h('time', 'since');
    const t = parse(iso);
    if (t === null) { el.textContent = 'time not read'; return el; }
    const off = num(offset) ? offset : 0;
    el.dateTime = iso; el.dataset.since = iso; el.dataset.suffix = suffix || '';
    if (off) el.dataset.offset = String(off);
    el.textContent = ago(now() - t + off * 1000) + (suffix || '');
    el.title = stamp(t, { date: true, seconds: true }); el.dataset.form = form();
    return el;
  }
  // A row kept through a redraw (list()) keeps the tooltip each of its times was given when it was made: one given in
  // another Time or Date is written again in place, so the row keeps its typed text and its open details.
  function retitle(root) {
    const f = form();
    root.querySelectorAll('time[data-since]').forEach((el) => {
      if (el.dataset.form !== f) { el.title = stamp(Date.parse(el.dataset.since), { date: true, seconds: true }); el.dataset.form = f; }
    });
    // A kept "Every step" (Needs you's) has clock times in its steps' tips, its line and its earlier attempts' lines:
    // one drawn in another Time or Date is drawn again from its own data, and keeps what was open in it.
    root.querySelectorAll('details.track-detail:not(.tl-earlier)').forEach((det) => {
      if (det.dataset.form !== f && det.redraw) det.replaceWith(det.redraw());
    });
  }
  // An issue a Depends on: line names: #N in this project, or "owner/repo#N" (a string) in another repository.
  function depRef(n) { return typeof n === 'string' ? n : `#${n}`; }
  // A card by its issue; a main-red fix card (issue 0) by the name the snapshot gives it, "Main is red (<commit>)".
  function issueLink(item) {
    const n = item && item.issue, label = item && typeof item.name === 'string' && item.name ? item.name : typeof n === 'number' && n > 0 ? `#${n}` : 'branch';
    if (item && typeof item.url === 'string' && /^https:\/\/github\.com\/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\/issues\/\d+$/.test(item.url)) {
      const a = h('a', 'issue', label);
      a.href = item.url; a.target = '_blank'; a.rel = 'noopener noreferrer';
      return a;
    }
    return h('span', 'issue', label);
  }
  // Reuses the node of every item that is still there (by key), so a row keeps its focus, its typed text and the
  // position its marker moves from; new rows come in with the `enter` motion once the list has been filled once.
  function list(parent, items, keyOf, make, update) {
    const old = new Map(Array.from(parent.children).map((n) => [n.dataset.key, n]));
    const added = [];
    items.forEach((item, i) => {
      const key = String(keyOf(item));
      let node = old.get(key);
      if (node) old.delete(key);
      else {
        node = make(item); node.dataset.key = key; added.push(node);
        if (parent.dataset.filled) node.classList.add('enter');
      }
      if (update) update(node, item);
      if (parent.children[i] !== node) parent.insertBefore(node, parent.children[i] || null);
    });
    old.forEach((n) => n.remove());
    parent.dataset.filled = '1';
    return added;
  }
  // ---- what the owner set that a reload keeps: list lengths, Needs-you drafts, the Board filter ----
  // Kept in sessionStorage (this tab only, until it closes), read once at start: a page that reloads itself on a new
  // view (newView) shows them again. One entry, {"<kind>\n<scope>\n<name>": value}: the kind and scope before the name
  // keep a name such as __proto__ an own key. A browser whose storage throws keeps them for the page's life only.
  // The entry is {login, items}: login is the login mark (localStorage, shared by every tab) when it was written. Each
  // sign-in (login.js) sets a new mark, so an entry another user's login made old, in this tab or another, is not
  // read; nor is any entry when the mark cannot be read, as then a new login cannot be seen.
  const KEPT_KEY = 'conveyor-board-kept', LOGIN_KEY = 'conveyor-board-login';
  const keptLogin = (() => { try { return window.localStorage.getItem(LOGIN_KEY) || ''; } catch { return null; } })();
  const kept = (() => {
    try {
      const s = JSON.parse(window.sessionStorage.getItem(KEPT_KEY)), x = s && s.items;
      return keptLogin !== null && s.login === keptLogin && x && typeof x === 'object' && !Array.isArray(x) ? x : {};
    } catch { return {}; }
  })();
  // A list's length and the Board filter are kept by the project the panel shows (scope): a panel of every project's
  // rows (projects: true) by the machine head's filter, else '' for every project; the Board and the Rules, which show
  // one project at a time, by that project. keptScope(mod) is it; a draft names its record, so has no scope.
  const keptScope = (mod) => projectOnly() || (mod.projects === true ? '' : param('repo') || '');
  const keptName = (kind, scope, name) => `${kind}\n${scope}\n${name}`;
  const keptGet = (kind, scope, name) => { const k = keptName(kind, scope, name); return Object.hasOwn(kept, k) ? kept[k] : undefined; };
  // keep(kind, scope, name, value): value '' or undefined forgets it.
  function keep(kind, scope, name, value) {
    const k = keptName(kind, scope, name);
    if (value === undefined || value === '') delete kept[k]; else kept[k] = value;
    try { window.sessionStorage.setItem(KEPT_KEY, JSON.stringify({ login: keptLogin, items: kept })); } catch { /* kept then for this page's life only */ }
  }
  // A long list shows its first `size` items (ctx.more: the panel's length unless said; 5 for a panel of length 'all'),
  // then "Show <size> more" and "Show all (N)". The box says how many items the list holds (data-items)
  // and its step (data-step): the panel's foot counts them (clipPlan). show(items)
  // draws the items given; the control returned goes under them. The owner's choice is kept per list (key) through
  // every redraw and a reload (keep, in scope); a list of `size` or fewer has no control. done(kind) runs after a click
  // ('more' or 'all'). After
  // "Show <size> more" the focus goes to the first new row: the item at the old length in the list just above the control.
  // A row in a closed group (a <details> the owner left closed) cannot take the focus: that group's heading takes it.
  const PAGE = 5;
  const pageOf = (scope, key) => { const v = keptGet('pages', scope, key); return v === 'all' || (Number.isInteger(v) && v > 0) ? v : undefined; };
  const rowsAbove = (box) => {
    let c = box.previousElementSibling;
    while (c && !c.matches('ul, ol') && !c.querySelector('ul, ol')) c = c.previousElementSibling;
    return c ? Array.from(c.querySelectorAll('li')).filter((li) => !li.parentElement.closest('li') || !c.contains(li.parentElement.closest('li'))) : [];
  };
  // The host's refusal of a dependency that would make a cycle (control depends: "#12 depending on #15 would make a
  // dependency cycle (#12, #15): ..."), said as what already waits on what. Any other text is the host's own.
  function refusal(text) {
    const m = /#(\d+) depending on ((?:#\d+(?:, )?)+) would make a dependency cycle \(([^)]*)\)/.exec(String(text));
    if (!m) return text;
    const n = m[1], cycle = m[3].match(/\d+/g) || [], d = (m[2].match(/\d+/g) || []).find((x) => cycle.includes(x));
    if (!d || !cycle.includes(n)) return text;
    const via = cycle.filter((x) => x !== n && x !== d).map((x) => `#${x}`);
    return `#${n} cannot wait on #${d}: #${d} already waits on #${n}${via.length ? ` through ${via.join(', ')}` : ''}.`;
  }
  // Under a "Depends on…" field: each number typed, with its title beside it as it is picked (open: the project's open
  // issues), or why it cannot be one (self: the issue being edited). It follows each keystroke on its own.
  function depPicked(field, open, self) {
    const ul = h('ul', 'dep-picked'), by = new Map((Array.isArray(open) ? open : []).filter((x) => x && num(x.issue)).map((x) => [x.issue, x.title]));
    ul.setAttribute('aria-live', 'polite');
    ul.setAttribute('aria-label', 'The issues picked');
    const paint = () => {
      const ns = Array.from(new Set((field.value.match(/\d+/g) || []).map(Number))).filter((n) => n > 0);
      ul.replaceChildren(...ns.map((n) => {
        const li = h('li', null, `#${n} `);
        li.append(n === self ? h('span', 'unknown', 'is this issue itself') : by.has(n) ? h('span', 'dep-picked-title', by.get(n) || 'untitled') : h('span', 'unknown', 'is not an open issue of this project'));
        return li;
      }));
      ul.hidden = !ns.length;
    };
    field.addEventListener('input', paint);
    paint();
    return ul;
  }
  // Last, so that every name above is set before app.js reads what this part gives back.
  window.DASH_APP.core((given) => {
    app = given;
    app.bind(bindNames);
    return { keep, PAGE, pageOf, rowsAbove, took, since, list, clock, when, findings, verdictSaid, judged, output,
      codeEl, fill, proofAt, pathsIn, repoOf, dur, modelName, survived, loopEnd, reviewChip, findingText, depRef,
      issueLink, keptScope, keptGet, refusal, depPicked, namesKey, retitle };
  });
})();
