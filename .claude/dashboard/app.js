// SPDX-License-Identifier: Apache-2.0
// The Conveyor dashboard's core: the panel frame, the layout the owner arranges, motion and the data refresh.
// It knows no panel. A panel is one file in panels/ that calls DASH_APP.panel({...}) and one entry in
// panels/index.js; it is handed its own part of data.js (`panels.<id>`, written by .claude/scripts/dashboard.sh)
// and nothing else. Everything a source wrote reaches the page as text, never as markup.
// The page has tabs, Overview (what reports), 3D View, Control (what changes the loop), Rules and Tests; a panel states its tab
// and is drawn only on it, and each tab keeps its own layout. A panel states its default length in rows (`rows`, a
// number or 'all'); the owner sets it with the handle on its lower edge (or its keyboard), a longer list scrolls inside the
// body under a head that stays, and the panel says "6 of 23" with one control to show all. The panels are packed on a
// fine row grid, each placed at the first place it fits, so no column has an empty block between panels.
(function () {
  'use strict';
  const STORE_KEY = 'conveyor-board-layout';  // the layout of each tab, density, theme, time and date, in this browser only
  const TAB_KEY = 'conveyor-board-tab';        // the tab in view last
  const SEEN_KEY = 'conveyor-board-seen';     // the "Needs you" items already shown once
  const TIME_SENT_KEY = 'conveyor-board-time-sent';  // set once this browser has sent a Time to the server
  // Overview first, with 3D View, the one to look at rather than act on, beside it (#87); then Control and Rules; then
  // Tests, the test files and the test limits (#520); then Benchmarks, the SWE-bench runs and their arms (#326).
  const TABS = [['overview', 'Overview'], ['belt3d', '3D View'], ['control', 'Control'], ['rules', 'Rules'], ['tests', 'Tests'], ['bench', 'Benchmarks']];
  const SIZES = ['small', 'wide', 'full'];
  const DENSITIES = ['comfortable', 'compact'];
  const THEMES = ['system', 'light', 'dark'];
  const CLOCKS = ['12-hour', '24-hour'];
  const DATES = ['mm/dd/yyyy', 'dd/mm/yyyy'];
  const PREFS0 = { density: 'comfortable', theme: 'system', time: '12-hour', date: 'mm/dd/yyyy' };
  const ROWS = 6;            // the default length of a panel that states none
  const ROW_SEL = '.rows > li';
  const ROW_PX = 8;          // the fine row grid the panels are packed on
  const SNAP = 6;            // panels that share a row end at the same line when they are this many grid rows apart or less
  const REFRESH_MS = 15000;
  const ALIVE_MS = 45000;   // the collector's heartbeat is written every 15 s; three misses is a stopped collector
  const STALE_MS = 300000;  // a collection runs every 60 s
  // What every panel says when the page has had no data at all: what is not seen, and the one thing to try.
  // No data has loaded, so the page does not know of a build machine (remote()): it names none.
  const NOTHING = 'The page could not load the Board\'s data, so there is nothing to show yet. Press Restart the Board\'s feed, above.';
  const MOTION_MS = 260;    // every animation this script runs stays under 300 ms
  const FOLD_MS = 140;      // a collapsing panel's body fades out (app.css .folding), then the panels below close up
  const SVG = 'http://www.w3.org/2000/svg';
  const ICONS = {
    grip: 'M9 6h.01M15 6h.01M9 12h.01M15 12h.01M9 18h.01M15 18h.01',
    up: 'M6 15l6-6 6 6', down: 'M6 9l6 6 6-6', right: 'M9 6l6 6-6 6',
    close: 'M6 6l12 12M18 6L6 18', sliders: 'M4 7h9M17 7h3M4 17h3M11 17h9M15 5v4M9 15v4',
    ok: 'M5 12.5l4.5 4.5L19 7', warn: 'M12 4l9 16H3zM12 10v4M12 17h.01', bad: 'M12 3a9 9 0 100 18 9 9 0 000-18zM9 9l6 6M15 9l-6 6',
    info: 'M12 3a9 9 0 100 18 9 9 0 000-18zM12 11v5M12 8h.01', quiet: 'M8 12h8',
    expand: 'M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5', shrink: 'M9 4v5H4M15 4v5h5M9 20v-5H4M15 20v-5h5',
  };

  const doc = document;
  const modules = new Map();
  const panels = new Map();
  const RETRY_MS = 15000;   // a live feed the server refused is asked for again after this
  let layouts = {}, prefs = null, tab = 'overview', grid = null, loaded = false, failedLoads = 0, updatedAt = null, alive = null, aliveSeenAt = 0, aliveOld = false, view = null, dragging = null;
  // placed: the key of the layout last arranged and each panel's column then (arrange()).
  let arranging = false, queued = false, placed = null;
  // The live feed: the page server's /events. While it is open each change comes as it happens, one panel at a
  // time, and data.js is not read; while it is not, data.js is read every REFRESH_MS as before.
  // At start a page with a feed does not read data.js: it draws from the feed's first snapshot. It reads data.js at
  // once only when the feed errors before anything is drawn (dataAsked: data.js was asked for already).
  // feedSeq counts the feed's snapshots, so a data.js asked for before one is not drawn over it.
  // last is what was drawn last ({updatedAt, panels}): the other tab's panels are drawn from it when that tab opens.
  let feed = null, feedOpen = false, last = null, feedSeq = 0, dataAsked = false;
  // The head line's tiles: head.js states them (DASH_APP.head); headView is what they are drawn in.
  let headMod = null, headView = null;

  const now = () => Date.now();
  const byId = (id) => doc.getElementById(id);
  function h(tag, cls, text) {
    const el = doc.createElement(tag);
    if (cls) el.className = cls;
    if (text !== undefined && text !== null) el.textContent = String(text);
    return el;
  }
  function icon(name) {
    const svg = doc.createElementNS(SVG, 'svg'), path = doc.createElementNS(SVG, 'path');
    svg.setAttribute('viewBox', '0 0 24 24'); svg.setAttribute('class', 'ico'); svg.setAttribute('aria-hidden', 'true'); svg.setAttribute('focusable', 'false');
    path.setAttribute('d', ICONS[name] || ICONS.quiet);
    svg.append(path);
    return svg;
  }
  // A status is never colour alone: every chip carries its word and an icon of its own shape.
  function chip(word, tone) {
    const t = ['ok', 'warn', 'bad', 'info'].includes(tone) ? tone : 'quiet';
    const el = h('span', `chip chip-${t}`);
    el.append(icon(t), h('span', null, word));
    return el;
  }
  const motion = () => doc.documentElement.dataset.motion !== 'off';
  const parse = (iso) => { const t = typeof iso === 'string' ? Date.parse(iso) : NaN; return Number.isNaN(t) ? null : t; };
  const num = (v) => typeof v === 'number' && Number.isFinite(v);
  function ago(ms) {
    const s = Math.max(0, Math.floor(ms / 1000));
    if (s < 60) return 'under a minute';
    const m = Math.floor(s / 60), hr = Math.floor(m / 60), d = Math.floor(hr / 24);
    if (m < 60) return `${m} min`;
    if (hr < 24) return `${hr} h ${String(m % 60).padStart(2, '0')} min`;
    return `${d} d ${hr % 24} h`;
  }
  const dur = (sec) => (typeof sec === 'number' && sec >= 0 ? ago(sec * 1000) : null);
  // A step's time as measured: a step is often under a minute, so its seconds are given then.
  const took = (sec) => (sec < 60 ? `${Math.max(0, Math.round(sec))} s` : sec < 3600 ? `${Math.floor(sec / 60)} min` : `${Math.floor(sec / 3600)} h ${String(Math.floor((sec % 3600) / 60)).padStart(2, '0')} min`);
  // The one formatter of every time and date the Board writes, in the Time and Date set in Customize: "3:04 PM" or
  // "15:04", "11/18/2026" or "18/11/2026". ms: a time in ms. date: the date first ("11/18/2026, 3:04 PM"); time: false
  // for the date alone; seconds: with the seconds; zone: a time zone (Belt 3D's ET clock), else the browser's own.
  const stampFormats = new Map();
  function stamp(ms, { date = false, time = true, seconds = false, zone } = {}) {
    // A page that has not read the layout yet (account.js before the head starts) reads the kept Time and Date.
    const p = prefs || prefsOf(stored()), h24 = p.time === '24-hour';
    const key = `${zone || ''} ${h24}`;
    if (!stampFormats.has(key)) {
      stampFormats.set(key, new Intl.DateTimeFormat('en-US', { timeZone: zone, hourCycle: h24 ? 'h23' : 'h12',
        year: 'numeric', month: '2-digit', day: '2-digit', hour: 'numeric', minute: '2-digit', second: '2-digit' }));
    }
    const v = Object.fromEntries(stampFormats.get(key).formatToParts(ms).map((x) => [x.type, x.value]));
    const day = p.date === 'dd/mm/yyyy' ? `${v.day}/${v.month}/${v.year}` : `${v.month}/${v.day}/${v.year}`;
    const hm = `${h24 ? v.hour.padStart(2, '0') : v.hour}:${v.minute}${seconds ? `:${v.second}` : ''}${h24 ? '' : ` ${v.dayPeriod}`}`;
    return [date && day, time && hm].filter(Boolean).join(', ');
  }
  const clock = (iso) => { const t = parse(iso); return t === null ? 'not read' : stamp(t); };
  // A time of day, with the date when it is not today (when a card was picked up).
  function when(iso) {
    const t = parse(iso);
    if (t === null) return 'not read';
    return stamp(t, { date: new Date(t).toDateString() !== new Date(now()).toDateString() });
  }
  function money(v) {
    if (typeof v !== 'number' || !Number.isFinite(v)) return 'not priced';
    return `$${v.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',')}`;
  }
  // A model ID as the Board shows it: an alias in a project's pack (Rules, Model prices) is the display name of the
  // model it means, and a model the pack gives a display name, or names aliases of, has that name; ":fast" stays on. Any other ID is shown
  // as it is. Read from the Rules part's prices, the project steered first, then each other project's.
  function allPrices() {
    const r = last && last.panels && last.panels.rules && last.panels.rules.data;
    return r && typeof r === 'object' ? [r.prices].concat(Object.values(r.others && typeof r.others === 'object' ? r.others : {}).map((o) => o && o.prices)) : [];
  }
  const namesKey = () => JSON.stringify(allPrices().map((p) => (p && typeof p === 'object' ? [p.overrides, p.names] : null)));
  function modelName(id) {
    if (typeof id !== 'string') return id;
    const all = allPrices();
    const fast = id.endsWith(':fast'), base = fast ? id.slice(0, -5) : id, tail = fast ? ':fast' : '';
    for (const p of all) {
      if (!p || typeof p !== 'object' || !p.overrides || typeof p.overrides !== 'object') continue;
      const over = p.overrides, names = p.names && typeof p.names === 'object' ? p.names : {};
      const named = (m) => (over[m] && typeof over[m].name === 'string' && over[m].name ? over[m].name : null);
      const to = Object.keys(over).find((m) => over[m] && Array.isArray(over[m].aliases) && over[m].aliases.includes(base));
      if (to) return `${named(to) || (typeof names[to] === 'string' ? names[to] : to)}${tail}`;
      // A model other IDs are aliases of: a finished step on an alias is recorded as this ID (pricedAs), so it has the
      // display name a running step on the alias shows.
      const target = over[base] && Array.isArray(over[base].aliases) && over[base].aliases.length > 0 && typeof names[base] === 'string' ? names[base] : null;
      if (named(base) || target) return `${named(base) || target}${tail}`;
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

  // A review finding: "[P1] path:line The sentence. Proof: why", its place and proof each optional.
  const FINDING = /^\[(P[0-3])\]\s*(.*)$/;
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
  // repoUrl: the card's repository on GitHub (repoOf), in which a review finding's file paths link to their lines; none,
  // and they are code with no link. repo: the card's record (its repo), whose findings' places open the lines the review
  // read (findingRows) in the review whose record has the time reviewAt; none, and they do not.
  function output(tail, card, label, was, repoUrl, repo, reviewAt) {
    if (typeof tail !== 'string' || !tail.trim()) return null;
    const same = JSON.stringify([tail, typeof card === 'string' ? card : '', label || '']);
    const keep = (det) => {
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
    };
    if (was && was.outputText === same) return keep(was);
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
    const shown = (x) => (x.n > 1 ? `${x.text} ×${x.n}` : x.text);
    const review = folded.some((x) => FINDING.test(x.text));
    const det = h('details', 'output'), fails = review || folded.length < 2 ? [] : folded.filter((x) => FAILLINE.test(x.text));
    det.append(h('summary', null, label || 'Show output'));
    det.dataset.card = typeof card === 'string' ? card : '';
    det.open = Boolean(was && was.open && was.dataset.card === det.dataset.card);
    if (fails.length) {
      const top = h('div', 'output-fails'), list = h('ul', null);
      list.append(...fails.map((x) => h('li', null, shown(x))));
      top.append(h('p', 'output-count', `${fails.length} ${fails.length === 1 ? 'failure' : 'failures'}`), list);
      det.append(top);
    }
    const pre = review ? findingRows(folded, repoUrl, card, repo, reviewAt) : h('pre', 'output-text');
    if (!review) folded.forEach((x, i) => {
      const line = h('span', FAILLINE.test(x.text) ? 'output-line is-fail' : 'output-line', x.text);
      if (x.n > 1) line.append(h('span', 'output-times', ` ×${x.n}`));
      pre.append(line);
      if (i < folded.length - 1) pre.append('\n');
    });
    const copy = h('button', 'btn btn-quiet output-copy', 'Copy output'), note = h('span', 'output-note');
    copy.type = 'button';
    note.setAttribute('aria-live', 'polite');
    copy.addEventListener('click', () => {
      const text = folded.map(shown).join('\n'), clip = window.navigator.clipboard;
      (clip && clip.writeText ? clip.writeText(text) : Promise.reject(new Error('no clipboard')))
        .then(() => { note.textContent = 'Copied.'; }, () => { note.textContent = 'Not copied: the browser gave no clipboard.'; });
    });
    det.append(pre, h('div', 'output-acts'));
    det.lastChild.append(copy, note);
    det.outputText = same;
    return keep(det);
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
  // The Time and Date set in Customize, as one text.
  function form() { const p = prefs || prefsOf(stored()); return `${p.time} ${p.date}`; }
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
  // A number counts from the value this panel showed last to the new one.
  // done(), when given, runs once the figure shows its new value.
  function tween(el, from, to, fmt, done) {
    const raf = window.requestAnimationFrame;
    if (!motion() || typeof raf !== 'function') { el.textContent = fmt(to); if (done) done(); return; }
    const t0 = now();
    el.textContent = fmt(from);
    const step = () => {
      const t = Math.min(1, (now() - t0) / MOTION_MS), e = 1 - (1 - t) * (1 - t);
      el.textContent = fmt(t === 1 ? to : from + (to - from) * e);
      if (t < 1) raf(step); else if (done) done();
    };
    raf(step);
  }
  // A figure that counts from the value shown last under its key (in nums) to the new one; a figure not known is said.
  // done(), when given, runs once a counting figure has reached its new value.
  function counter(nums, key, value, fmt, done) {
    const el = h('span', 'num'), prev = nums.get(key), f = fmt || String;
    nums.set(key, value);
    if (typeof value !== 'number') { el.textContent = f(value); el.classList.add('unknown'); } else if (typeof prev !== 'number' || prev === value) el.textContent = f(value);
    else tween(el, prev, value, f, done);
    return el;
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
  const keptLogin = (() => { try { return window.localStorage.getItem(LOGIN_KEY) || ''; } catch (e) { return null; } })();
  const kept = (() => {
    try {
      const s = JSON.parse(window.sessionStorage.getItem(KEPT_KEY)), x = s && s.items;
      return keptLogin !== null && s.login === keptLogin && x && typeof x === 'object' && !Array.isArray(x) ? x : {};
    } catch (e) { return {}; }
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
    try { window.sessionStorage.setItem(KEPT_KEY, JSON.stringify({ login: keptLogin, items: kept })); } catch (e) { /* kept then for this page's life only */ }
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
  function more(key, items, show, size, done, scope = '') {
    const step = size || PAGE, n = items.length;
    const box = h('div', 'show-more'), next = h('button', 'btn btn-quiet'), all = h('button', 'btn btn-quiet');
    box.dataset.list = key;
    box.dataset.items = String(n);
    box.dataset.step = String(step);
    next.type = 'button'; next.dataset.act = 'list-more';
    all.type = 'button'; all.dataset.act = 'list-all';
    const shown = () => { const want = pageOf(scope, key) || step; return want === 'all' ? n : Math.min(n, want); };
    const paint = () => {
      const limit = shown();
      show(items.slice(0, limit));
      box.hidden = limit >= n;
      next.textContent = `Show ${step} more`;
      all.textContent = `Show all (${n})`;
    };
    next.addEventListener('click', () => {
      const was = shown();
      keep('pages', scope, key, was + step); paint(); if (done) done('more');
      let row = rowsAbove(box)[was];
      for (let g = row && row.parentElement.closest('details:not([open])'); g; g = g.parentElement && g.parentElement.closest('details:not([open])')) {
        const head = g.querySelector(':scope > summary');
        if (head) row = head;
      }
      if (row) { if (row.matches('li') && !row.hasAttribute('tabindex')) row.tabIndex = -1; row.focus(); }
    });
    all.addEventListener('click', () => { keep('pages', scope, key, 'all'); paint(); if (done) done('all'); });
    box.append(next, all);
    paint();
    return box;
  }

  // ---- what stops the loop, and dependencies: words the machine head, Projects and the Board share ----
  // One line for a loop that picks nothing: who paused it and how to start it again. name: the project, or null for
  // the whole machine; guard: the weekly-limit guard's percent, or null; reason: why the loop paused itself (a sign-in
  // failure: health's reason, shown beside this line), or null. Nothing for a loop that runs.
  function pausedSaid(state, name, guard, reason) {
    const resume = name ? `Resume ${name}` : 'Resume all projects';
    if (state === 'paused' && reason) return `Paused by Conveyor for the reason shown. Fix it, then ${resume} to pick again.`;
    if (state === 'paused') return name ? `Paused by you (Pause ${name}). ${resume} to pick again.` : `Every project paused by you (Pause all projects). ${resume} to pick again.`;
    if (state === 'paused by guard') return `Paused by the weekly-limit guard${num(guard) ? ` at ${guard}%` : ''}. Raise or turn off "Pause when the weekly limit reaches" in Rules to pick again.`;
    if (state === 'stopped' && name) return `Stopped by Stop now: the cards in progress went back to the queue. ${resume} to pick again.`;
    return null;
  }
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

  // ---- a card's step track: Build, Review, Fix, Test, Land, Push ----
  // Each step is done (a check mark and the time it took), now (lit, its running time), to come (muted), skipped (a
  // dash) or failed (a cross, and why); never colour alone. The join before a step fills once the card has reached
  // it, so the track reads as one bar of progress from left to right, by steps, never by time.
  const STEP_NAMES = ['Build', 'Review', 'Fix', 'Test', 'Land', 'Push'];
  const STEP_WORD = { done: 'done', now: 'in progress', skipped: 'skipped', failed: 'failed', todo: 'to come' };
  const STEP_MARK = { done: '✓', now: '▶', skipped: '–', failed: '✗', todo: '·' };
  const sixOf = (t) => (t && Array.isArray(t.steps) && t.steps.length === 6 && t.steps.every((s, i) => s && s.name === STEP_NAMES[i] && STEP_WORD[s.state]) ? t : null);
  // "Review 2 of 3", "Fix 2": a step that ran more than once, or the round in progress. Tests that passed only when the
  // cases that had not passed ran again: "Test passed on re-run", never a plain success. A fix the Done-when check on
  // the build's reply started is Build's (track.jq replyFix), never Fix: "Build · reply check fix" while it runs.
  function stepName(s) {
    const n = num(s.n) ? s.n : 0;
    if (s.name === 'Build' && s.replyFix === 'now' && s.state === 'now') return 'Build · reply check fix';
    if (s.name === 'Build' && s.replyFix === 'done' && s.state === 'done') return 'Build · reply check fixed';
    if (s.name === 'Test' && s.rerun === true && s.state === 'done') return 'Test passed on re-run';
    if (s.name === 'Review' && n >= 1 && (n > 1 || s.state === 'now')) return `Review ${n}${num(s.of) && n <= s.of ? ` of ${s.of}` : ''}`;
    if (s.name === 'Fix' && n >= 1 && (n > 1 || s.state === 'now')) return `Fix ${n}`;
    return s.name;
  }
  // A test step's time is its runs' wait for a test slot and their run, apart, when its records give them.
  const testTime = (s) => (num(s.wait) && num(s.run) ? `wait ${took(s.wait)} · run ${took(s.run)}` : null);
  function stepTime(s, t) {
    if (s.state === 'now') return since(t.since, '');
    if (s.state === 'skipped') return h('span', null, 'skipped');
    if ((s.state === 'done' || s.state === 'failed') && (testTime(s) || num(s.sec))) return h('span', null, testTime(s) || took(s.sec));
    return null;
  }
  // Fills `ol` (kept from one refresh to the next, each step the same node) with the six steps of track t; false when
  // t is not a six-step track.
  function track(ol, t) {
    const six = sixOf(t);
    if (!six) { ol.replaceChildren(); return false; }
    list(ol, six.steps.map((s, i) => ({ s, i })), (x) => x.i, () => {
      const li = h('li', 'step6'), box = h('span', 'step-chip'), mark = h('span', 'step-mark');
      mark.setAttribute('aria-hidden', 'true');
      box.append(mark, h('span', 'step-name'), h('span', 'step-time'));
      li.append(h('span', 'join'), box);
      return li;
    }, (li, x) => {
      const s = x.s, join = li.children[0], [mark, name, time] = li.children[1].children, label = stepName(s);
      li.dataset.state = s.state;
      join.hidden = x.i === 0;
      join.setAttribute('aria-hidden', 'true');
      join.dataset.filled = String(s.state !== 'todo');
      mark.textContent = STEP_MARK[s.state];
      name.textContent = label;
      const tm = stepTime(s, six);
      time.replaceChildren(...(tm ? [tm] : []));
      const extra = x.i === 5 && num(s.followups) && s.followups > 0 ? `, ${s.followups} follow-up${s.followups === 1 ? '' : 's'} filed` : '';
      const why = s.state === 'failed' && x.i === 5 && six.reason ? `: ${six.reason}` : '';
      const said = `${label}: ${STEP_WORD[s.state]}${s.state === 'done' && testTime(s) ? `, ${testTime(s)}` : s.state === 'done' && num(s.sec) ? `, took ${took(s.sec)}` : ''}${why}${extra}`;
      li.setAttribute('aria-label', said);
      tip(li, said);
      if (s.state === 'now') li.setAttribute('aria-current', 'step'); else li.removeAttribute('aria-current');
    });
    const at = num(six.at) ? six.at : -1;
    ol.setAttribute('aria-label', at >= 0 ? `Steps: ${stepName(six.steps[at])}, step ${at + 1} of 6` : 'Steps of this card');
    return true;
  }
  // What a failed test run says went wrong (the record's failures: {of, files: [{file, cases: [{name, line}]}],
  // timeout: null | {sec, file}}): one line that sums it up ("2 of 41 test files failed", or that it timed out and in
  // which file), then a row a failing file with its failing cases, each on a line of its own with its first failure
  // line. Never a passing file or case. null when the record names no failing file and no timeout. brief: the line that
  // sums it up, then only the first failing file with its first failing case (Needs you, failureShort).
  function testFails(f, brief) {
    if (!f || typeof f !== 'object') return null;
    const files = (Array.isArray(f.files) ? f.files : []).filter((x) => x && typeof x.file === 'string' && Array.isArray(x.cases));
    const t = f.timeout && typeof f.timeout === 'object' ? f.timeout : null;
    if (!files.length && !t) return null;
    const failed = `${files.length}${num(f.of) ? ` of ${f.of}` : ''} test ${(num(f.of) ? f.of : files.length) === 1 ? 'file' : 'files'} failed`;
    const timed = t ? `Timed out${num(t.sec) ? ` after ${t.sec < 60 ? took(t.sec) : `${Math.round(t.sec / 60)} min`}` : ''}${typeof t.file === 'string' && t.file ? ` in ${t.file}` : ''}` : '';
    const box = h('div', 'test-fails'), rows = h('ul', 'test-files');
    box.append(h('p', 'test-sum', t ? timed + (files.length ? ` · ${failed}` : '') : failed));
    (brief ? files.slice(0, 1) : files).forEach((x) => {
      const row = h('li', 'test-file'), cases = h('ul', 'test-cases');
      x.cases.filter((c) => c && typeof c.name === 'string').slice(0, brief ? 1 : Infinity).forEach((c) => {
        const line = typeof c.line === 'string' ? c.line : '', own = `FAIL [${c.name}]: `;
        const li = h('li', 'test-case');
        li.append(h('span', 'test-case-name', c.name), h('span', 'test-case-line', line.startsWith(own) ? line.slice(own.length) : line));
        cases.append(li);
      });
      row.append(h('span', 'test-file-name', x.file || 'Test file not named'), cases);
      rows.append(row);
    });
    if (files.length) box.append(rows);
    return box;
  }
  // The changed lines no test reached in a test run, from the coverage report its command wrote (the record's
  // coverage: {uncovered: [{file, lines}], count, checked} or {unknown: why}): one line that sums it up, then a row a
  // file with its lines. A lead for the reviewer, never a failure. null when the record has no coverage.
  function testCoverage(c) {
    if (!c || typeof c !== 'object') return null;
    const box = h('div', 'test-coverage');
    if (typeof c.unknown === 'string') { box.append(h('p', 'test-sum', `Changed lines no test reached: unknown${c.unknown ? ` (${c.unknown})` : ''}`)); return box; }
    if (!num(c.count) || !num(c.checked)) return null;
    box.append(h('p', 'test-sum', `Changed lines no test reached: ${c.count ? c.count : 'none'} of ${c.checked}`));
    const files = (Array.isArray(c.uncovered) ? c.uncovered : []).filter((x) => x && typeof x.file === 'string' && typeof x.lines === 'string');
    if (files.length) {
      const rows = h('ul', 'test-files');
      files.forEach((x) => rows.append(h('li', 'test-file', `${x.file}: ${/[-,]/.test(x.lines) ? 'lines' : 'line'} ${x.lines}`)));
      box.append(rows);
    }
    return box;
  }
  // Every recorded step, on demand, as a timeline: one bar a step on one time axis, from the card's pick-up to now (or
  // to its end), each as long as the step ran, with its time on it. The time the issue waited in the queue is said
  // apart, so a long wait squashes no bar. The set-up (picked, worktree, dependencies, brief) is one bar that opens
  // to its parts; a review has its verdict, its findings and what the judge made of it; a failed step is red, with its reason on hover or focus; the
  // clock times are on hover or focus too, and in each item's text for a screen reader. The step in progress beats
  // (belt.js). A bar is placed by its clock times, so a pause between two steps (a restarted review waiting for its
  // turn) is a gap on the axis; from a snapshot with no times the bars follow one another.
  // card: the card's id, so the output a step keeps shows its worktree as ./.
  const SETUP = /^(picked|worktree ready|dependencies linked|brief written|making the worktree|linking dependencies|writing the brief)$/;
  const BAR_NAME = { building: 'Build', landing: 'Land', pushed: 'Push', push: 'Push', 'push failed': 'Push', 'tests passed': 'Tests', 'tests failed': 'Tests' };
  // What started a fix session, as its bar in "Every step" and the card's step pill name it ("Fix 3: main changed under it"): its
  // line's reason when it names one (a failed Done-when check on the reply, main moved), else the step before it (a
  // NO-GO review's findings, a failed test run). The fix in progress has no line yet, so it is named only where the step
  // before it leaves one cause: failed tests; a build, rebuild or fix with no reason (the Done-when check on its reply);
  // tests that passed or a reply-check fix (main moved). After a review it may be the findings, the commit trailers or
  // main having moved (a GO, or a last NO-GO, still lands), and after a main-moved or trailer fix the reply check or
  // main moved: "Fix N" alone until its line says. all: the card's recorded steps; i: the place of one in it. null when
  // it is no fix; why is the reason, on hover.
  const FIX_CAUSE = [[/^the Done-when check failed/, 'reply check'], [/^main moved/, 'main moved']];
  // A cause as the fix's name spells it: "Fix 3: main changed under it", never the record's short "main moved".
  const FIX_NAME = { 'main moved': 'main changed under it' };
  const FIX_SAID = { 'review findings': "a NO-GO review's findings", 'tests failed': 'the changed tests failed', 'reply check': 'the Done-when check on the reply failed',
    'main moved': 'main moved after the card made its change, and the change no longer applied to it' };
  function fixOf(all, i) {
    const s = all[i], m = /^fix (\d+)$/.exec(s.name), running = s.state === 'now' && /^fix\b/.test(s.name);
    if (!m && !running) return null;
    const n = m ? Number(m[1]) : all.slice(0, i).filter((x) => /^fix \d+$/.test(x.name)).length + 1;
    const said = (x) => (typeof x.reason === 'string' ? x.reason : ''), causeOf = (r) => (FIX_CAUSE.find(([re]) => re.test(r)) || [])[1] || null;
    const reason = said(s), p = i > 0 ? all[i - 1] : { name: '' }, prev = p.name;
    const cause = !running ? causeOf(reason) || (reason ? null : prev === 'tests failed' ? 'tests failed' : /^review \d+ \(NO-GO\)$/.test(prev) ? 'review findings' : null)
      : prev === 'tests failed' ? 'tests failed' : prev === 'tests passed' ? 'main moved' : /^(building|rebuild)$/.test(prev) ? 'reply check'
        : !/^fix \d+$/.test(prev) ? null : !said(p) ? 'reply check' : causeOf(said(p)) === 'reply check' ? 'main moved' : null;
    return { name: `Fix ${n}${cause ? `: ${FIX_NAME[cause] || cause}` : ''}`, why: reason || (cause ? FIX_SAID[cause] : '') };
  }
  // records: one per recorded line, each with its own seconds; detail (17 summed slots) from a snapshot without them.
  const stepsOf = (t) => (t && Array.isArray(t.records) ? t.records : t && Array.isArray(t.detail) ? t.detail : []).filter((s) => s && typeof s.name === 'string' && STEP_WORD[s.state]);
  // The fix in progress of track t, as fixOf names it; null when the card is in no fix or its steps were not given.
  function fixNow(t) {
    const all = stepsOf(t), i = all.length - 1;
    return i >= 0 && all[i].state === 'now' ? fixOf(all, i) : null;
  }
  // A bar's parts and what they say (a filing its count of follow-ups); its times are worked out as it is placed.
  function barOf(parts) {
    const states = parts.map((s) => s.state), last = parts[parts.length - 1];
    const state = ['failed', 'now', 'done'].find((x) => states.includes(x)) || (states.includes('todo') ? 'todo' : 'skipped');
    const review = /^review (\d+)(?: \((.+)\))?$/.exec(last.name), n = parts.map((s) => s.n).find(num);
    const name = (parts.length > 1 || SETUP.test(last.name) ? 'Setup' : review ? `Review ${review[1]}`
      : BAR_NAME[last.name] || last.name.charAt(0).toUpperCase() + last.name.slice(1)) + (num(n) ? ` (${n})` : '');
    const why = parts.map((s) => s.why).find((w) => typeof w === 'string' && w) || '';
    return { parts, state, name, verdict: review ? review[2] || null : null, counts: review ? last.counts : null, judge: review ? last.judge : null, why };
  }
  // A running test run's progress, from its track: its cases ("142 of 205 tests · 2 failed") when its command gave a
  // count (tests), else its files ("3 of 6 test files"); null when the track has neither (no test run in progress).
  // Before it, the list of tests the run was given (the track's list) and how its tests were found: "changed: 7 files
  // (map) · 3 test files" (3 of them ran), "changed: 7 files (by name)", or "whole suite: <why> · ..."; with the made
  // test map's age, "· map 12 commits old".
  function testProgress(t) {
    const c = t && t.tests && typeof t.tests === 'object' ? t.tests : null, f = t && t.files && typeof t.files === 'object' ? t.files : null;
    const l = t && t.list && typeof t.list === 'object' ? t.list : null;
    const by = l && l.by === 'map' ? ' (map)' : l && l.by === 'name' ? ' (by name)' : '';
    const age = l && num(l.age) ? ` · map ${l.age} ${l.age === 1 ? 'commit' : 'commits'} old` : '';
    const mode = l && l.mode === 'changed' && num(l.files) ? `changed: ${l.files} ${l.files === 1 ? 'file' : 'files'}${by}${age}`
      : l && l.mode === 'whole' ? `whole suite${typeof l.why === 'string' && l.why ? `: ${l.why}` : ''}` : null;
    let prog = null;
    if (c && num(c.done) && num(c.of)) prog = `${c.done} of ${c.of} tests${num(c.failed) && c.failed > 0 ? ` · ${c.failed} failed` : ''}`;
    else if (f && num(f.run)) {
      prog = `${f.run}${num(f.of) ? ` of ${f.of}` : ''} test ${(num(f.of) ? f.of : f.run) === 1 ? 'file' : 'files'}`;
      // A run that ran more test files than it selected (over) says so apart, never as "N of M" with N above M.
      if (num(f.over) && f.over > 0) prog += ` · ${f.over} more ${f.over === 1 ? 'file' : 'files'} than selected`;
    }
    return mode && prog ? `${mode} · ${prog}` : mode || prog;
  }
  // was: the timeline this one replaces, if any: whether it and its set-up were open is kept. A timeline with a step in
  // progress has retime(), which sets that step's bar's width and the time texts again as its time grows (belt.js, each
  // second), and changes nothing else. data-card names the card, so a panel that draws its rows anew finds was.
  // A card's overall time with earlier attempts (the snapshot's earlier) says on hover that it includes them.
  function earlierTip(el, earlier) {
    const n = Array.isArray(earlier) ? earlier.length : 0;
    if (n) tip(el, `Includes ${n === 1 ? 'the earlier attempt' : `the ${n} earlier attempts`}: "Every step" shows ${n === 1 ? 'its' : 'their'} steps`);
    return el;
  }
  // earlier: the earlier cards of the same work (the snapshot's earlier, the first first), each above the steps as one
  // closed line, "Earlier attempt: <start> to <end>, <time>, ended: <reason>", opening to its own steps: the card's
  // overall time counts their seconds, so the steps it is made of are all here.
  // repoUrl: the card's repository (repoOf), in which its review findings' file paths link to their lines; repo: its
  // record, whose findings' places open the lines the review read (output).
  function trackDetail(t, card, was, earlier, repoUrl, repo) {
    const det = h('details', 'track-detail'), sum = h('summary', null, 'Every step');
    if (typeof card === 'string') det.dataset.card = card;
    const total = h('p', 'tl-total'), ol = h('ol', 'timeline');
    // What was drawn before of this card's own steps, never of an earlier attempt's inside it. was may be the
    // "Every step" of an earlier card id (a retry, panels/belt.js): its own steps are one of this card's earlier
    // attempts now, which keeps their open output boxes, and this card's steps take nothing from it.
    const mine = was && was.dataset.card === card ? was.querySelector(':scope > ol.timeline') : null;
    const before = (Array.isArray(earlier) ? earlier : []).filter((e) => e && typeof e === 'object' && e.track && typeof e.track === 'object').map((e) => {
      const prior = Boolean(was && was.dataset.card === e.card);
      const old = prior ? was : was ? Array.from(was.querySelectorAll(':scope > details.tl-earlier')).find((x) => x.dataset.card === e.card) : null;
      const d = trackDetail(e.track, e.card, old, null, repoUrl, repo);
      // The earlier card's "Every step" was the whole box, never this line: the line starts closed.
      if (prior) d.open = false;
      d.classList.add('tl-earlier');
      d.hidden = false;
      d.firstChild.textContent = `Earlier attempt: ${when(e.start)} to ${when(e.end)}, ${num(e.sec) ? took(e.sec) : 'time not read'}, ended: ${typeof e.reason === 'string' && e.reason ? e.reason : 'no reason recorded'}`;
      return d;
    });
    const all = stepsOf(t);
    let wait = null;
    const groups = [];
    all.forEach((s) => {
      if (s.name === 'queued') { if (num(s.sec)) wait = s.sec; return; }
      const prev = groups[groups.length - 1];
      if (SETUP.test(s.name) && prev && SETUP.test(prev[0].name)) prev.push(s); else groups.push([s]);
    });
    // A fix is named by what started it, its reason on hover and on a tap.
    const bars = groups.map((g) => { const b = barOf(g), f = g.length === 1 ? fixOf(all, all.indexOf(g[0])) : null; return f ? Object.assign(b, { name: f.name, said: f.why }) : b; });
    bars.forEach((b) => {
      const li = h('li', 'tl-item'), label = h('span', 'tl-label', b.name), lane = h('span', 'tl-lane'), bar = h('span', 'tl-bar');
      if (b.said) tip(label, b.said);
      li.dataset.state = b.state;
      li.tabIndex = 0;
      if (b.state === 'now') li.setAttribute('aria-current', 'step');
      if (b.verdict) label.append(chip(verdictSaid(b.verdict), b.verdict === 'GO' ? 'ok' : 'warn'));
      if (b.parts.some((s) => s.rerun === true)) label.append(chip('passed on re-run', 'warn'));
      const f = findings({ counts: b.counts });
      if (f) label.append(h('span', 'tl-findings', f));
      // What the judge made of the review, its declined count opening the card's lines in the Declined panel.
      const jd = judged(b, card);
      if (jd) label.append(jd);
      lane.setAttribute('aria-hidden', 'true');
      lane.append(bar);
      Object.assign(b, { lane, bar, dur: h('span', 'tl-dur'), tip: h('span', 'tl-tip') });
      li.append(label, lane, b.tip);
      // The test run in progress says how far it has got.
      const prog = b.state === 'now' ? testProgress(t) : null;
      if (prog) li.append(h('p', 'tl-tests', prog));
      // The set-up opens to the steps it folds.
      if (b.name === 'Setup') {
        const parts = h('details', 'tl-parts'), inner = h('ol', null);
        parts.append(h('summary', null, `${b.parts.length} ${b.parts.length === 1 ? 'step' : 'steps'}`), inner);
        inner.append(...b.parts.map((s) => h('li', `detail-${s.state}`, `${s.name}: ${STEP_WORD[s.state]}${num(s.sec) ? `, ${took(s.sec)}` : ''}`)));
        parts.open = Boolean(mine && mine.querySelector('.tl-parts[open]'));
        li.append(parts);
      }
      // A blocked step's sentence and the output it failed on, and a NO-GO review's findings, as Needs you shows them.
      // A failed test run shows its failing files and cases in place of its reason, and its output under "Show full output".
      // Its output stays open through a redraw: the toggle it replaces is the one of the same step (its place among the
      // card's steps, which only grow at the end, and its name).
      b.parts.forEach((s) => {
        const fails = testFails(s.failures);
        // Its bar's words on hover or focus say the same line, not the exit code.
        if (fails) { li.append(fails); b.why = fails.firstChild.textContent; }
        else if (typeof s.why === 'string' && s.why) li.append(h('p', 'detail-why', s.why));
        const cov = testCoverage(s.coverage);
        if (cov) li.append(cov);
        const step = `${all.indexOf(s)}:${s.name}`;
        const old = mine ? Array.from(mine.querySelectorAll('details.output')).find((x) => x.dataset.step === step) : null;
        const out = output(s.output, card, s.name === 'tests failed' ? 'Show full output' : null, old, repoUrl, repo, /^review \d/.test(s.name) ? s.at : null);
        if (out) { out.dataset.step = step; li.append(out); }
      });
      ol.append(li);
    });
    const open = bars.some((b) => b.state === 'now');
    // Each bar's time, place and length on the axis, its time on it and its words, at the draw. The axis is fixed then:
    // while a step runs it has room after now (a tenth of its length, a minute at least) for that bar to grow into
    // each second, and only that bar's length and the time texts change till the next draw. A tick that put the axis
    // again moved every bar, and their times between bar and lane, under the reader each second.
    const sec = (s) => (s.state === 'now' ? Math.max(0, (now() - (parse(t.since) ?? now())) / 1000) : num(s.sec) ? Math.max(0, s.sec) : 0);
    const running = (b) => b.parts[b.parts.length - 1].state === 'now';
    const measure = (b) => {
      b.secs = b.parts.reduce((a, s) => a + sec(s), 0);
      b.end = running(b) ? now() : parse(b.parts[b.parts.length - 1].at);
      b.start = b.end === null ? null : b.end - b.secs * 1000;
    };
    // The time beside a bar sits after it, or before it near the axis's end; on the bar it needs no place.
    const beside = (b) => {
      b.dur.style.left = '';
      b.dur.style.right = '';
      delete b.dur.dataset.side;
      if (b.dur.parentNode !== b.lane) return;
      if (b.left + b.width <= 70) b.dur.style.left = `${(b.left + b.width).toFixed(2)}%`;
      else { b.dur.style.right = `${(100 - b.left).toFixed(2)}%`; b.dur.dataset.side = 'before'; }
    };
    const words = (b) => {
      const time = b.state === 'todo' || b.state === 'skipped' ? STEP_WORD[b.state] : took(b.secs);
      b.dur.textContent = time;
      const clocks = b.start !== null && b.end !== null ? `, ${clock(new Date(b.start).toISOString())} to ${b.state === 'now' ? 'now' : clock(new Date(b.end).toISOString())}` : '';
      const reason = b.state === 'failed' ? `: ${b.why ? b.why.split('\n')[0] : b.parts[b.parts.length - 1].name}` : '';
      b.tip.textContent = `${b.name}: ${STEP_WORD[b.state]}, ${time}${clocks}${reason}`;
    };
    bars.forEach(measure);
    const timed = bars.length > 0 && bars.every((b) => b.start !== null);
    let off = 0;
    bars.forEach((b) => { b.from = timed ? b.start : off; off = b.from + b.secs * 1000; });
    const from = bars.length ? Math.min(...bars.map((b) => b.from)) : 0;
    const end = () => Math.max(from, ...bars.map((b) => b.from + b.secs * 1000));
    // The axis's length and ends, the time in steps when pauses make it shorter, and the queue's wait apart.
    const said = () => {
      const to = end(), span = to - from, work = bars.reduce((a, b) => a + b.secs, 0);
      const at = (ms) => when(new Date(ms).toISOString());
      const text = (timed ? `${took(span / 1000)} from ${at(from)} to ${open ? 'now' : at(to)}${work < span / 1000 - 60 ? `, ${took(work)} of it in steps` : ''}` : `${took(work)} in steps`)
        + (num(wait) ? ` · waited ${took(wait)} in the queue before` : '');
      // The line is one line high and may be cut (app.css, .tl-total): its full text is its tip.
      if (total.textContent !== text) { total.textContent = text; tip(total, text); }
    };
    const span = end() - from, axis = span + (open ? Math.max(60000, span / 10) : 0);
    // Left and width are shares of the axis; a step of no measurable time is still drawn, at its least width.
    const share = (ms) => (axis > 0 ? (ms / axis) * 100 : 0);
    bars.forEach((b) => {
      b.left = share(b.from - from);
      b.width = share(b.secs * 1000);
      b.bar.style.left = `${b.left.toFixed(2)}%`;
      b.bar.style.width = `${b.width.toFixed(2)}%`;
      // The time is on the bar when it is wide enough, else beside it.
      (b.width >= 25 ? b.bar : b.lane).append(b.dur);
      beside(b);
      words(b);
    });
    said();
    // Each second: the running bar grows, to the axis's end at most; its time stays where the draw put it (a node moved
    // under the reader moves the page), and the texts count on.
    if (open) {
      det.retime = () => {
        bars.filter(running).forEach((b) => {
          measure(b);
          b.width = Math.min(100 - b.left, share(b.secs * 1000));
          b.bar.style.width = `${b.width.toFixed(2)}%`;
          beside(b);
          words(b);
        });
        said();
      };
    }
    ol.setAttribute('aria-label', 'Every step, in order, on one time axis');
    det.append(sum, ...before, total, ol);
    det.hidden = !ol.children.length && !before.length;
    det.open = Boolean(was && was.open);
    det.dataset.form = form();
    det.redraw = () => trackDetail(t, card, det, earlier, repoUrl, repo);
    return det;
  }
  // A closed "Every step" with no steps drawn in it, only its summary (panels/belt.js draws them when it opens): it is
  // hidden as trackDetail's is, when it has no step and no earlier attempt to show.
  function trackShell(t, card, earlier) {
    const det = h('details', 'track-detail');
    det.append(h('summary', null, 'Every step'));
    if (typeof card === 'string') det.dataset.card = card;
    const prior = Array.isArray(earlier) && earlier.some((e) => e && typeof e === 'object' && e.track && typeof e.track === 'object');
    det.hidden = !stepsOf(t).some((s) => s.name !== 'queued') && !prior;
    return det;
  }

  // Why a blocked card stopped, as one plain sentence first ("2 tests failed: a, b", "Review said NO-GO three times",
  // "Push refused: the check typecheck failed"), and its explanation under it, shown without a tap (no <details>, so
  // a phone, with no hover, reads it too). c: the card as Needs you has it (reason, track, reviews, push, check).
  const TIMES = ['', 'once', 'twice', 'three times'];
  function failure(c) {
    const full = typeof c.reason === 'string' && c.reason.trim() ? c.reason.trim() : 'no reason recorded';
    const steps = sixOf(c.track) ? c.track.steps : [];
    const at = steps.map((s) => s.state).lastIndexOf('failed');
    const names = [], recs = stepsOf(c.track);
    let timeout = null, fails = null;
    // The failed tests are the cause only when the card stopped for them ("the changed tests failed again…"): a card
    // whose fix of those tests then failed ("fix: …") stopped for its fix, and an earlier run's names are not why.
    const byTests = /\btests failed\b/i.test(full) && !/^fix\b/i.test(full);
    if (byTests) recs.filter((s) => s.state === 'failed' && s.failures && typeof s.failures === 'object').slice(-1).forEach((s) => {
      (Array.isArray(s.failures.files) ? s.failures.files : []).forEach((f) => (f && Array.isArray(f.cases) ? f.cases : []).forEach((x) => { if (x && typeof x.name === 'string') names.push(x.name); }));
      if (s.failures.timeout && typeof s.failures.timeout === 'object') timeout = s.failures.timeout;
      fails = s.failures;
    });
    const nogo = (Array.isArray(c.reviews) ? c.reviews : []).filter((r) => r && r.verdict === 'NO-GO').length;
    const failedPush = /\bFAILED:?\s+([A-Za-z0-9_.:/-]+)/.exec(full);
    // A review that could not finish ("review 2: review failed (exit 3; …)", "review 2 ended without one clear
    // verdict") stopped the card, not an earlier round's NO-GO: its own sentence leads.
    const reviewBroke = /^review \d+(:| ended\b)/i.test(full);
    let said;
    if (c.push || /^push\b/i.test(full)) said = `Push refused: ${c.check ? `the check ${c.check} failed` : failedPush ? `the check ${failedPush[1]} failed` : first(full.replace(/^push failed:?\s*/i, ''))}`;
    else if (names.length) said = `${names.length} test${names.length === 1 ? '' : 's'} failed: ${names.slice(0, 3).join(', ')}${names.length > 3 ? ` and ${names.length - 3} more` : ''}`;
    else if (timeout) said = `The tests timed out${typeof timeout.file === 'string' && timeout.file ? ` in ${timeout.file}` : ''}`;
    else if (nogo && !reviewBroke && (at === 1 || /NO-GO/.test(full))) said = `Review asked for changes ${TIMES[nogo] || `${nogo} times`}`;
    else said = first(full);
    return { said, full, fails };
  }
  // The first sentence of a text, cut at a word to 140 characters at most.
  function first(s) {
    const m = /^[^\n]*?[.!?](?=\s|$)/.exec(s), one = (m ? m[0] : s.split('\n')[0]).trim();
    if (one.length <= 140) return one;
    const cut = one.slice(0, 140), sp = cut.lastIndexOf(' ');
    return `${(sp > 60 ? cut.slice(0, sp) : cut).replace(/[\s,:;]+$/, '')}…`;
  }
  // The sentence a blocked card leads with, then its explanation, shown without a tap in a block labelled "Why it
  // blocked" (app.css .why-block), by the kind of block: a review block ("the fix for [P1] ... did not hold after 1
  // round") draws its finding as the Declined panel does (level, linked place, claim, proof); a test block its failing
  // files and cases with their first failure lines (testFails); any other the reason as recorded, in full. A sentence
  // that already says the whole reason has no block. Code spans and file paths are drawn as fill draws them, linked in
  // the card's repository (repoOf). brief (reviewWhy): only the first finding, with the first sentence of its proof.
  const SHOWN_LINES = 12;
  function reviewWhy(full, repoUrl, known, brief) {
    const m = /^the fix for (\[P[0-3]\][\s\S]*?)\s+did not hold after \d+ rounds?$/.exec(full);
    if (!m) return null;
    const rows = h('ol', 'output-findings');
    m[1].split(/\n(?=\[P[0-3]\])/).slice(0, brief ? 1 : Infinity).forEach((t) => {
      const f = /^\[(P[0-3])\]\s*(?:\[E\d+\]\s*)?(?:(\S+:\d+(?:[-–]\d+)?)[:,]?\s+(?=\S))?([\s\S]*)$/.exec(t.trim());
      if (!f) return;
      const { at: cut, label } = proofAt(f[3]), claim = (cut < 0 ? f[3] : f[3].slice(0, cut)).trim(), proof = cut < 0 ? '' : f[3].slice(cut + label.length).trim();
      const row = h('li', 'output-finding'), head = h('div', 'finding-head'), said = h('p', 'finding-text');
      said.append(fill(h('strong', 'finding-claim'), claim, repoUrl, known, 'finding'));
      head.append(chip(f[1], f[1] === 'P0' || f[1] === 'P1' ? 'warn' : 'quiet'), said);
      row.append(head);
      if (f[2]) { const p = h('p', 'finding-at'); p.append(codeEl(repoUrl, f[2], known, 'finding-at-link').el); row.append(p); }
      if (proof) row.append(h('p', 'finding-proof-label', 'Proof:'), fill(h('div', 'finding-proof-text'), brief ? first(proof) : proof, repoUrl, known, 'finding'));
      rows.append(row);
    });
    return rows.children.length ? rows : null;
  }
  // The reason whole, or its first SHOWN_LINES lines and a "Show all" button that shows the rest.
  function clipped(full, repoUrl, known) {
    const lines = full.split('\n'), draw = (t) => fill(h('div', 'why-text why-full'), t, repoUrl, known, 'why');
    if (lines.length <= SHOWN_LINES) return draw(full);
    const box = h('div', 'why-clip'), btn = h('button', 'btn btn-quiet show-all', 'Show all');
    btn.type = 'button';
    let part = draw(lines.slice(0, SHOWN_LINES).join('\n'));
    btn.addEventListener('click', () => { const all = draw(full); part.replaceWith(all); part = all; btn.remove(); });
    box.append(part, btn);
    return box;
  }
  function failureLine(c) {
    const { said, full, fails } = failure(c);
    const repoUrl = repoOf(c), known = new Set(pathsIn(full));
    const out = doc.createDocumentFragment();
    out.append(fill(h('p', 'reason why-said'), said, repoUrl, known, 'why-said'));
    const body = reviewWhy(full, repoUrl, known) || (fails && testFails(fails)) || (said !== full && clipped(full, repoUrl, known));
    if (body) out.append(whyBlock('Why it blocked', body));
    return out;
  }
  const whyBlock = (label, body) => { const box = h('div', 'reason why-block'); box.append(h('strong', 'why-label', label), body); return box; };
  // The short form, for Needs you, so its next step and buttons come right under the failure: {lead, rest}. lead is the
  // sentence, then the first finding (its level, place, claim and the first sentence of its proof) or the first failing
  // test file with its first failing case, in "Why it blocked"; rest is the whole explanation as failureLine draws it,
  // in "Why it blocked, in full", or null when the lead already says all of it. A plain reason leads with its sentence.
  function failureShort(c) {
    const { said, full, fails } = failure(c);
    const repoUrl = repoOf(c), known = new Set(pathsIn(full));
    const lead = doc.createDocumentFragment();
    lead.append(fill(h('p', 'reason why-said'), said, repoUrl, known, 'why-said'));
    const one = reviewWhy(full, repoUrl, known, true) || (fails && testFails(fails, true));
    if (one) lead.append(whyBlock('Why it blocked', one));
    const body = reviewWhy(full, repoUrl, known) || (fails && testFails(fails)) || (said !== full && clipped(full, repoUrl, known));
    return { lead, rest: body ? whyBlock('Why it blocked, in full', body) : null };
  }

  // ---- one guard rule for every button that changes real work ----
  // A change easily undone (hold, queue, move, pause, a rule) acts on one click, and the line that confirms it carries
  // Undo (undoLine). One that costs money or time ('spend': retry, queue all, queue anyway, a test run, a restart) and one
  // that cannot be undone ('final': close, stop now, dismiss, remove a user, its consequence in its words) act on a
  // second click: the first turns the button to `ask` for ARM_MS, and it looks apart from a one-click button. No browser
  // dialog: it looks like nothing else on the page and blocks it.
  const ARM_MS = 5000;
  function twice(b, tier, ask, go) {
    const label = b.textContent;
    let timer = null;
    b.classList.add(tier === 'final' ? 'btn-final' : 'btn-cost');
    b.dataset.guard = tier;
    const reset = () => { window.clearTimeout(timer); timer = null; b.textContent = label; b.setAttribute('aria-pressed', 'false'); delete b.dataset.armed; };
    b.setAttribute('aria-pressed', 'false');
    b.addEventListener('click', () => {
      if (b.disabled) return;
      if (timer === null) { b.textContent = ask; b.setAttribute('aria-pressed', 'true'); b.dataset.armed = ''; timer = window.setTimeout(reset, ARM_MS); return; }
      reset();
      go();
    });
    return b;
  }
  // What a one-click change says it did, with Undo when undo is given: it sends the opposite change once.
  function undoLine(text, undo) {
    const box = h('span', 'undo-line', text);
    if (typeof undo === 'function') {
      const b = h('button', 'btn btn-quiet btn-undo', 'Undo');
      b.type = 'button'; b.dataset.act = 'undo';
      b.addEventListener('click', () => { b.disabled = true; undo(); });
      box.append(' ', b);
    }
    return box;
  }

  function goLogin(r) {
    if (r && (r.status === 401 || (r.redirected && /\/login$/.test(String(r.url || ''))))) window.location.assign('/login');
    return r;
  }
  // The page's only writes: an answer to an open decision, a control action, the collector restart and the Time set in
  // Customize, all to its own host.
  function post(path, body) {
    return window.fetch(path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }).then(goLogin);
  }
  function seenStore() {
    let seen;
    try { seen = JSON.parse(window.localStorage.getItem(SEEN_KEY)); } catch (e) { seen = null; }
    return Array.isArray(seen) ? seen.filter((k) => typeof k === 'string') : null;
  }
  // The keys not shown before in this browser, and the record of what is shown now. The first visit shows none as
  // new: everything on a page just opened would light up at once.
  function fresh(keys) {
    const seen = seenStore();
    try { window.localStorage.setItem(SEEN_KEY, JSON.stringify(keys)); } catch (e) { /* a browser that keeps nothing shows no item as new */ }
    return seen === null ? [] : keys.filter((k) => !seen.includes(k));
  }

  // ---- the layout: each tab's order, widths, lengths, collapsed and hidden panels; density, theme, time and date ----
  const tabOf = (id) => modules.get(id).tab;
  // The part a panel is drawn from: its own, or the part of the panel file that registered it (part, panel()).
  const partOf = (id) => modules.get(id).part || id;
  // A panel that states alwaysShown (Needs you) has no hide control and no hide box, and a kept layout cannot hide it.
  const hideable = (id) => modules.get(id).alwaysShown !== true;
  const widthsOf = (id) => modules.get(id).widths || SIZES;  // the widths a panel can take (panel(); every size for a missing one)
  const idsOf = (t) => Array.from(modules.keys()).filter((id) => tabOf(id) === t);
  // On a phone (one column, columns()) the page is one long column: the report panels that say phoneFolded start as
  // their headings, so what needs the owner is not sixteen screens long (issue 413). A layout the owner kept is theirs.
  function defaults(t) {
    const ids = idsOf(t), phone = columns() === 1;
    return { order: ids, sizes: Object.fromEntries(ids.map((id) => [id, modules.get(id).size])), lengths: {},
      collapsed: phone ? ids.filter((id) => modules.get(id).phoneFolded === true) : [], hidden: [] };
  }
  const lengthOk = (v) => v === 'all' || (Number.isInteger(v) && v >= 1 && v <= 1000);
  // A kept layout is read piece by piece: what the page cannot use is dropped, never a broken page.
  function tidy(t, s) {
    const d = defaults(t);
    if (!s || typeof s !== 'object') return d;
    const known = (v) => (Array.isArray(v) ? v.filter((id, i) => modules.has(id) && tabOf(id) === t && v.indexOf(id) === i) : []);
    const order = known(s.order);
    const lens = s.lengths && typeof s.lengths === 'object' ? s.lengths : {};
    return {
      order: order.concat(d.order.filter((id) => !order.includes(id))),  // a panel added since the last visit goes last
      // A width the panel cannot take is its default.
      sizes: Object.fromEntries(d.order.map((id) => [id, s.sizes && widthsOf(id).includes(s.sizes[id]) ? s.sizes[id] : d.sizes[id]])),
      lengths: Object.fromEntries(d.order.filter((id) => lengthOk(lens[id])).map((id) => [id, lens[id]])),
      // A layout that lists no collapsed panels (nothing kept yet) has the default's: the phone's folded reports.
      collapsed: Array.isArray(s.collapsed) ? known(s.collapsed) : d.collapsed, hidden: known(s.hidden).filter(hideable),
    };
  }
  function stored() {
    let s;
    try { s = JSON.parse(window.localStorage.getItem(STORE_KEY)); } catch (e) { s = null; }
    return s && typeof s === 'object' ? s : {};
  }
  const prefsOf = (s) => ({ density: DENSITIES.includes(s.density) ? s.density : PREFS0.density, theme: THEMES.includes(s.theme) ? s.theme : PREFS0.theme,
    time: CLOCKS.includes(s.time) ? s.time : PREFS0.time, date: DATES.includes(s.date) ? s.date : PREFS0.date });
  function readLayout() {
    const s = stored();
    // A layout kept before the tabs was the Overview's.
    const kept = s.tabs && typeof s.tabs === 'object' ? s.tabs : { overview: s };
    layouts = Object.fromEntries(TABS.map(([t]) => [t, tidy(t, kept[t])]));
    prefs = prefsOf(s);
  }
  // The Time goes to the server (time.json) for the plugin's Build pane on its machine; a send that fails leaves the pane on
  // its own `time` option or the Time sent before.
  function sendTime() {
    try { window.localStorage.setItem(TIME_SENT_KEY, '1'); } catch (e) { /* then a kept 24-hour is sent again on the next visit */ }
    post('time', { time: prefs.time }).catch(() => {});
  }
  function save() {
    try { window.localStorage.setItem(STORE_KEY, JSON.stringify({ tabs: layouts, ...prefs })); } catch (e) { /* the layout then lasts for this visit */ }
  }
  const lay = () => layouts[tab];
  const shown = () => lay().order.filter((id) => !lay().hidden.includes(id));
  function say(text) { const el = byId('announce'); if (el) el.textContent = text; }

  // Moves every panel from where it was to where the change put it: transform only, and off under reduced motion.
  function flip(change) {
    const els = Array.from(panels.values()).map((p) => p.el);
    const before = motion() ? new Map(els.map((el) => [el, el.getBoundingClientRect()])) : null;
    // The panels' entrance is over once the owner moves one: a panel put back in the grid would play it again, over the move.
    grid.classList.remove('fresh');
    change();
    if (!before) return;
    els.forEach((el) => {
      const a = before.get(el), b = el.getBoundingClientRect();
      const dx = a.left - b.left, dy = a.top - b.top;
      if ((!dx && !dy) || el.hidden || !el.isConnected || (!a.width && !a.height)) return;
      el.style.transition = 'none';
      el.style.transform = `translate(${dx}px, ${dy}px)`;
      void el.offsetWidth;  // the start position must be laid out before the transition is set
      el.style.transition = `transform ${MOTION_MS}ms cubic-bezier(.2,.7,.2,1)`;
      el.style.transform = '';
      window.setTimeout(() => { el.style.transition = ''; }, MOTION_MS + 20);
    });
  }
  function applyLayout() {
    const root = doc.documentElement, l = lay();
    root.dataset.density = prefs.density;
    if (prefs.theme === 'system') delete root.dataset.theme; else root.dataset.theme = prefs.theme;
    // A panel already in its place is left in the page: taking it out and putting it back would drop the keyboard
    // focus from the control the owner just used, and play the body's entrance again. The other tab's panels are not drawn
    // and take no space: they are out of the page.
    const focused = doc.activeElement;
    panels.forEach((p, id) => { if (tabOf(id) !== tab && p.el.parentNode === grid) p.el.remove(); });
    l.order.forEach((id, i) => {
      const p = panels.get(id);
      const collapsed = l.collapsed.includes(id), size = l.sizes[id];
      const was = p.el.dataset.collapsed;  // undefined until the layout has been applied once
      if (grid.children[i] !== p.el) grid.insertBefore(p.el, grid.children[i] || null);
      p.el.hidden = l.hidden.includes(id);
      p.el.dataset.size = size;
      p.tools.size.value = size;
      p.el.dataset.collapsed = String(collapsed);
      if (!collapsed) { p.body.classList.remove('folding'); p.body.hidden = false; }
      else if (was === 'false' && !p.el.hidden && !p.body.hidden && motion()) fold(id, p);
      else if (!p.body.classList.contains('folding')) p.body.hidden = true;
      p.tools.collapse.setAttribute('aria-expanded', String(!collapsed));
      p.tools.collapse.setAttribute('aria-label', `${collapsed ? 'Expand' : 'Collapse'} ${p.mod.title}`);
      p.tools.collapse.replaceChildren(icon(collapsed ? 'right' : 'down'));
      clip(p);
    });
    const vis = shown();
    vis.forEach((id, i) => {
      const t = panels.get(id).tools;
      t.up.disabled = i === 0; t.down.disabled = i === vis.length - 1;
    });
    drawTabs();
    drawCustomize();
    arrange();
    if (focused && focused !== doc.activeElement && grid.contains(focused) && !focused.disabled) focused.focus({ preventScroll: true });
  }
  // Collapsing with motion on: the body fades and lifts first, then it is taken out and the panels below slide up.
  // The layout already says collapsed; a panel opened again before the fade ends stays open.
  function fold(id, p) {
    p.body.classList.add('folding');
    window.setTimeout(() => {
      if (!p.body.classList.contains('folding')) return;
      p.body.classList.remove('folding');
      // The collapse is the owner's change of the layout: once the body is out, the panels are placed anew.
      if (layouts[tabOf(id)].collapsed.includes(id)) flip(() => { p.body.hidden = true; clip(p); placed = null; arrange(); });
    }, FOLD_MS);
  }
  function change(fn, message) {
    const was = `${prefs.time} ${prefs.date}`;
    flip(() => { fn(); applyLayout(); });
    refit();  // a new Density changes the tiles' padding and figures: the head is fitted again
    save();
    // A new Time or Date shows at once: each panel's times are written when it is drawn, so every panel is drawn again
    // (the other tabs' when they are opened), with the head and its clock.
    if (`${prefs.time} ${prefs.date}` !== was) { redrawAll(); tick(); }
    // A new Time, from its choice or from Restore, also goes to the server.
    if (!was.startsWith(`${prefs.time} `)) sendTime();
    if (message) say(message);
  }
  function move(id, by) {
    const vis = shown(), at = vis.indexOf(id), to = at + by;
    if (at < 0 || to < 0 || to >= vis.length) return;
    const other = vis[to], l = lay(), a = l.order.indexOf(id), b = l.order.indexOf(other);
    change(() => { l.order[a] = other; l.order[b] = id; }, `${modules.get(id).title} moved to place ${to + 1} of ${vis.length}`);
  }
  function toggle(key, id, on) {
    change(() => { const l = lay(); l[key] = l[key].filter((x) => x !== id).concat(on ? [id] : []); });
  }
  // Restore puts the tab in view back as it was by default, with the density, theme, time and date.
  function reset() {
    change(() => { layouts[tab] = defaults(tab); prefs = { ...PREFS0 }; }, `Default layout of ${TABS.find((x) => x[0] === tab)[1]} restored`);
  }

  // ---- a panel's length ----
  // The rows of a panel: what its module counts as one (rowSelector), shown ones only. A panel with none of them (Cost
  // with its figures and empty lists) is measured by the blocks of its body, so its length can still be set.
  // A row inside a closed group (a <details> not open, as the Board's long Held groups start) is not drawn: its box
  // is empty, so it is not counted, nor measured to as the last row shown.
  const shownOnly = (els) => Array.from(els).filter((r) => !r.closest('[hidden], details:not([open]) > :not(summary)'));
  // A panel with a shared long list (ctx.more) counts its items: a row inside a row (the cards of a batch, a project's
  // changes in Release) is part of that row, not a row of the panel.
  const rowsOf = (p) => {
    const all = Array.from(p.body.querySelectorAll(p.mod.rowSelector || ROW_SEL));
    const rows = shownOnly(listsOf(p).length ? all.filter((r) => !inRow(p, r)) : all);
    return rows.length ? rows : shownOnly(p.body.children);
  };
  const inRow = (p, el) => !!(el.parentElement && el.parentElement.closest(p.mod.rowSelector || ROW_SEL));
  // A panel with a shared long list (ctx.more) of more than one page is not cut by default: that list is its length
  // control (clipPlan). A list that fits on one page has no control, so the panel keeps its default length.
  const listsOf = (p) => Array.from(p.body.querySelectorAll('.show-more[data-items]'));
  const lengthOf = (p) => (listsOf(p).some((b) => Number(b.dataset.items) > Number(b.dataset.step)) ? 'all' : p.mod.rows);
  const wantOf = (p) => { const v = layouts[tabOf(p.mod.id)].lengths[p.mod.id]; return v === undefined ? lengthOf(p) : v; };
  // Cuts the body to its length: past it the body scrolls (the head stays), and the foot says how many rows there are
  // in all, with the one control to show all of them (or, when all are shown past the default, to show fewer).
  // In three parts, so that arrange() can measure every panel before it writes to any (one layout, not one a panel):
  // clipPlan reads no layout, clipMeasure only reads it, clipApply only writes.
  // A panel with a shared long list (ctx.more) has that list's "Show <n> more" and "Show all (N)" as its one length
  // control: it is cut only at a length the owner set (its edge), never at its default, and its foot has no Show all
  // while a list of its own rows shows its own, only "<shown> of <total>" in items (rowsOf), the items its lists hold
  // back included. A list inside a row (a project's changes in Release) is part of that row: its Show all shows the
  // rest of that list, not of the panel.
  function clipPlan(p) {
    const id = p.mod.id, l = layouts[tabOf(id)], want = wantOf(p);
    const open = p.state === 'ready' && !l.collapsed.includes(id) && !p.body.hidden;
    const rows = open ? rowsOf(p) : [];
    const n = rows.length, limit = want === 'all' ? n : Math.min(n, want);
    const all = listsOf(p), lists = all.filter((b) => !inRow(p, b));
    let total = null;
    if (all.length) {
      // Every item drawn (in a closed group too) and every item a list of the panel's rows holds back.
      const drawn = open ? Array.from(p.body.querySelectorAll(p.mod.rowSelector || ROW_SEL)).filter((r) => !inRow(p, r)).length || n : 0;
      total = open ? drawn + lists.reduce((s, b) => s + Math.max(0, Number(b.dataset.items) - rowsAbove(b).length), 0) : 0;
    }
    return { want, open, rows, n, limit, total, listCtl: lists.some((b) => !b.hidden), cut: n > limit, max: '' };
  }
  function clipMeasure(p, c) {
    if (!c.cut) return;
    const top = p.body.getBoundingClientRect().top - p.body.scrollTop;
    const pad = parseFloat((window.getComputedStyle ? window.getComputedStyle(p.body).paddingBottom : '') || '') || 16;
    c.max = `${Math.max(48, Math.ceil(c.rows[c.limit - 1].getBoundingClientRect().bottom - top + pad))}px`;
  }
  function clip(p) {
    const c = clipPlan(p);
    p.body.classList.toggle('scrolls', c.cut);
    clipMeasure(p, c);
    clipApply(p, c);
  }
  function clipApply(p, { want, open, n, limit, total, listCtl, cut, max }) {
    p.body.classList.toggle('scrolls', cut);
    p.body.style.maxHeight = max;
    p.el.dataset.rows = String(n);
    p.el.dataset.length = String(want);
    if (total !== null) {
      p.rowsNote.textContent = open && limit < total ? `${limit} of ${total}` : '';
      // Cut at its edge with every list shown whole: the foot's Show all is then the one that shows the rest.
      p.showAll.hidden = !cut || listCtl;
      p.showAll.textContent = 'Show all';
      p.showAll.setAttribute('aria-label', `Show all ${total} rows of ${p.mod.title}`);
      p.foot.hidden = !p.rowsNote.textContent && p.showAll.hidden;
    } else {
      const more = want === 'all' && p.mod.rows !== 'all' && n > p.mod.rows;
      p.rowsNote.textContent = cut ? `${limit} of ${n}` : more ? `All ${n}` : '';
      p.showAll.hidden = !cut && !more;
      p.showAll.textContent = cut ? 'Show all' : 'Show fewer';
      p.showAll.setAttribute('aria-label', cut ? `Show all ${n} rows of ${p.mod.title}` : `Show the first ${p.mod.rows} rows of ${p.mod.title}`);
      p.foot.hidden = !cut && !more;
    }
    p.grip.hidden = !open || n === 0;
    p.grip.setAttribute('aria-valuemin', '1');
    p.grip.setAttribute('aria-valuemax', String(Math.max(1, n)));
    p.grip.setAttribute('aria-valuenow', String(Math.max(1, limit)));
    p.grip.setAttribute('aria-valuetext', `${limit} of ${n} rows shown`);
  }
  function setLength(p, v, message) {
    const id = p.mod.id, l = layouts[tabOf(id)];
    change(() => { if (v === lengthOf(p)) delete l.lengths[id]; else l.lengths[id] = v; }, message);
  }
  // By keyboard: up a row shorter, down a row longer (to all at the last), Page Up and Down five, Home one, End all.
  function lengthKey(p, e) {
    const n = Number(p.el.dataset.rows) || 0, want = wantOf(p), cur = want === 'all' ? n : Math.min(n, want);
    const to = { ArrowUp: cur - 1, ArrowLeft: cur - 1, ArrowDown: cur + 1, ArrowRight: cur + 1, PageUp: cur - 5, PageDown: cur + 5, Home: 1, End: n }[e.key];
    if (to === undefined || !n) return;
    e.preventDefault();
    const v = to >= n ? 'all' : Math.max(1, to);
    setLength(p, v, `${p.mod.title} shows ${v === 'all' ? `all ${n}` : `${v} of ${n}`} rows`);
    p.grip.focus();
  }
  // By dragging the lower edge: the length is the rows that end above the edge where it is let go.
  function lengthDrag(p, e) {
    if (e.button !== undefined && e.button !== 0) return;
    e.preventDefault();
    const top = p.body.getBoundingClientRect().top - p.body.scrollTop, y0 = e.clientY, h0 = p.body.getBoundingClientRect().height;
    const pick = (y) => {
      const rows = rowsOf(p), edge = h0 + (y - y0);
      const k = rows.filter((r) => r.getBoundingClientRect().bottom - top <= edge + ROW_PX).length;
      return k >= rows.length ? 'all' : Math.max(1, k);
    };
    const moveTo = (ev) => { p.body.style.maxHeight = `${Math.max(48, h0 + (ev.clientY - y0))}px`; };
    const end = (ev) => {
      doc.removeEventListener('pointermove', moveTo); doc.removeEventListener('pointerup', end);
      const v = pick(ev.clientY);
      setLength(p, v, `${p.mod.title} shows ${v === 'all' ? 'all its' : v} rows`);
    };
    doc.addEventListener('pointermove', moveTo); doc.addEventListener('pointerup', end);
  }

  // ---- packing: the panels fill each column from the top, with no empty block between them ----
  // pack(items, cols): items in order, each {id, w (columns), h (rows of the fine grid)}; each is put at the first
  // place it fits, row by row and left to right (so a short panel later in the order fills a hole beside a tall one).
  // Then panels that start on the same row and end within SNAP rows of each other end at the same line, and a panel
  // with at most SNAP free rows under it before the next panel in its columns grows down to meet it. Returns each with
  // {id, col, row, w, h}, h the rows it now takes. `at` (optional, id to column) keeps a panel in the column it names:
  // it is put at the first row free there.
  function pack(items, cols, at = new Map()) {
    const c = Math.max(1, cols), cells = [];
    const free = (r, x, w, hh) => { for (let i = r; i < r + hh; i++) for (let j = x; j < x + w; j++) if (cells[i] && cells[i][j]) return false; return true; };
    const take = (r, x, w, hh, id) => { for (let i = r; i < r + hh; i++) { cells[i] = cells[i] || []; for (let j = x; j < x + w; j++) cells[i][j] = id; } };
    const out = items.map((it) => {
      const w = Math.min(c, Math.max(1, it.w)), hh = Math.max(1, Math.ceil(it.h));
      const x0 = at.get(it.id), fixed = Number.isInteger(x0) && x0 >= 0 && x0 + w <= c;
      for (let r = 0; ; r++) for (let x = fixed ? x0 : 0; x + w <= (fixed ? x0 + w : c); x++) if (free(r, x, w, hh)) { take(r, x, w, hh, it.id); return { id: it.id, col: x, row: r, w, h: hh }; }
    });
    const grow = (p, to) => { if (to > p.row + p.h && free(p.row + p.h, p.col, p.w, to - p.row - p.h)) { take(p.row + p.h, p.col, p.w, to - p.row - p.h, p.id); p.h = to - p.row; } };
    // The same line: panels of one starting row whose ends are close.
    const starts = new Map();
    out.forEach((p) => starts.set(p.row, (starts.get(p.row) || []).concat([p])));
    starts.forEach((g) => {
      const end = Math.max(...g.map((p) => p.row + p.h));
      g.forEach((p) => { if (end - (p.row + p.h) <= SNAP) grow(p, end); });
    });
    // A small gap to the next panel in the columns a panel takes is closed by growing down to it. A larger one is not:
    // a short or collapsed panel stretched to a tall neighbour's height is an empty box that defeats its length. No
    // panel lower on the page fits such a gap (each was put at the first place it fits), so it is left as it is.
    const height = cells.length;
    out.slice().sort((a, b) => b.row - a.row).forEach((p) => {
      let next = Infinity;
      for (let j = p.col; j < p.col + p.w; j++) for (let i = p.row + p.h; i < height; i++) if (cells[i] && cells[i][j]) { next = Math.min(next, i); break; }
      if (next !== Infinity && next - (p.row + p.h) <= SNAP) grow(p, next);
    });
    return out;
  }
  function columns() {
    const mq = (q) => typeof window.matchMedia === 'function' && window.matchMedia(q).matches;
    return mq('(max-width: 700px)') ? 1 : mq('(max-width: 1080px)') ? 2 : 3;
  }
  const spanOf = (size, cols) => (cols === 1 ? 1 : size === 'full' ? cols : size === 'wide' ? Math.min(2, cols) : 1);
  // Places every panel of the tab in view: measured at its own height, packed, and grown to fill where pack says.
  // A refresh that only changes panels' heights keeps each panel in the column it had, so the panel being read does
  // not jump to another column. The panels are placed anew when the first data comes, and when the tab, the column
  // count, the density or the tab's layout (order, widths, lengths, collapsed, hidden: a panel added or removed too)
  // changes.
  function arrange() {
    if (!grid || arranging) return;
    arranging = true;
    try {
      const cols = columns(), gap = prefs.density === 'compact' ? 12 : 16;
      grid.dataset.cols = String(cols);
      const vis = shown().map((id) => panels.get(id));
      const key = JSON.stringify([loaded, tab, cols, prefs.density, lay(), vis.map((p) => p.mod.id)]);
      const at = placed && placed.key === key ? placed.cols : new Map();
      // Each round reads every panel, or writes to every panel, never one panel's read after another's write: a read
      // after a write lays the page out again, so measuring the panels one by one laid it out once a panel, each
      // refresh, and a scroll stuttered (#562).
      const cuts = vis.map((p) => {
        p.el.style.minHeight = '';
        // At its new width first (a resize of the window, a change of columns or of its width setting wraps its rows
        // anew), then cut to its length again: the rows' heights, so the body's height and its count, are measured
        // at the width it is drawn at.
        const w = spanOf(lay().sizes[p.mod.id], cols);
        if (p.el.dataset.w !== `${w}/${cols}`) { p.el.dataset.w = `${w}/${cols}`; p.el.style.gridColumn = `span ${w}`; p.el.style.gridRow = ''; }
        const c = clipPlan(p);
        p.body.classList.toggle('scrolls', c.cut);
        return { p, w, c };
      });
      cuts.forEach(({ p, c }) => clipMeasure(p, c));
      cuts.forEach(({ p, c }) => clipApply(p, c));
      const items = cuts.map(({ p, w }) => {
        // The height the panel is drawn at: its own box, or lower where its head, body or foot is drawn past that box
        // (a body that does not scroll draws all of its content, scrollHeight). Its box alone gave a panel too few
        // grid rows when its body reached past it, and the body was drawn over the panels under it.
        const box = p.el.getBoundingClientRect();
        const reach = Array.from(p.el.children).reduce((m, c) => {
          if (c.hidden) return m;
          const r = c.getBoundingClientRect(), all = c === p.body && !c.classList.contains('scrolls') ? c.scrollHeight || 0 : 0;
          return Math.max(m, Math.max(r.bottom, r.top + all) - box.top);
        }, 0);
        const natural = Math.max(box.height || 0, reach);
        p.natural = natural;
        return { id: p.mod.id, w, h:Math.max(1, Math.ceil((natural + gap) / ROW_PX)) };
      });
      const out = pack(items, cols, at);
      placed = { key, cols: new Map(out.map((x) => [x.id, x.col])) };
      out.forEach((at) => {
        const p = panels.get(at.id);
        p.el.style.gridColumn = `${at.col + 1} / span ${at.w}`;
        p.el.style.gridRow = `${at.row + 1} / span ${at.h}`;
        p.el.dataset.col = String(at.col); p.el.dataset.row = String(at.row); p.el.dataset.span = String(at.h);
        const fill = at.h * ROW_PX - gap;
        p.el.style.minHeight = fill > p.natural + 1 ? `${fill}px` : '';
      });
      // An open tip follows its item to where this draw put it.
      if (tipAt && tipAt.isConnected) placeTip(tipAt);
    } finally { arranging = false; }
  }
  // Once a frame, when a panel's content changed its height.
  function arrangeSoon() {
    if (queued) return;
    queued = true;
    const run = () => { queued = false; arrange(); };
    if (typeof window.requestAnimationFrame === 'function') window.requestAnimationFrame(run); else run();
  }

  // ---- the tabs: Overview, 3D View, Control, Rules and Tests, kept in the address and in this browser ----
  const tabFromAddress = () => { try { const t = new URL(window.location.href).searchParams.get('tab'); return TABS.some((x) => x[0] === t) ? t : null; } catch (e) { return null; } };
  function address(t, push) {
    try {
      const u = new URL(window.location.href);
      if (u.searchParams.get('tab') === t) return;
      u.searchParams.set('tab', t);
      if (push) window.history.pushState({ tab: t }, '', u.toString()); else window.history.replaceState({ tab: t }, '', u.toString());
    } catch (e) { /* a page opened from a file keeps the tab in this browser only */ }
  }
  // A panel's choices kept in the address beside the tab (the project picked, a filter, a sort), so a reload or a
  // link keeps them: param(name) reads one (null when unset), params({name: value}) sets them (null or '' clears).
  function param(name) { try { return new URL(window.location.href).searchParams.get(name); } catch (e) { return null; } }
  function params(set) {
    try {
      const u = new URL(window.location.href);
      Object.entries(set).forEach(([k, v]) => { if (v === null || v === undefined || v === '') u.searchParams.delete(k); else u.searchParams.set(k, String(v)); });
      window.history.replaceState(window.history.state, '', u.toString());
    } catch (e) { /* a page opened from a file keeps the choice for this view only */ }
  }
  // A project picked from a panel (Projects and Foremen's "open its Board") is picked in the machine head's one
  // picker, which every tab obeys: there is no other.
  function pickRepo(repo) { setProject(repo); }
  // A part that holds every project on the host ({repo, ..., repos, others: {repo: part}}, as the Board's and the
  // Rules part are): the part of the project the address picks (?repo=), else the part itself (host.json's main).
  function project(d) {
    // Only a record of the host file: a name like __proto__ is no project.
    // The project the page is filtered to (?project=, which a link may carry with no ?repo=) comes first: the Board and
    // the Rules never show, or steer, another project than the one every list is cut to.
    const want = projectOnly() || param('repo'), o = d && d.others && typeof d.others === 'object' ? d.others : {};
    const known = want && want !== d.repo && Array.isArray(d.repos) && d.repos.includes(want) && Object.prototype.hasOwnProperty.call(o, want);
    return known && o[want] && typeof o[want] === 'object' ? Object.assign({}, o[want], { repos: d.repos, others: o }) : d;
  }
  // ---- every project of the machine in one list: the filter, the sort and the tag ----
  // The machine head's filter (?project=) shows one project only, and its sort (?psort=1) puts each project's rows
  // together, on every panel that lists rows of more than one project (a module with projects: true). The Board and
  // the Rules tab show one project at a time already: the filter picks theirs (setProject's ?repo= with it), and with
  // every project shown they keep the one shown last, their heading naming it (ctx.title).
  // The host's projects, in its order: the repos of the part the machine head is drawn from (head.js names it).
  const repoNames = () => { const m = last && last.panels && headMod && headMod.machine && last.panels[headMod.machine.part]; return m && m.data && Array.isArray(m.data.repos) ? m.data.repos.filter((r) => typeof r === 'string') : []; };
  const projectOnly = () => { const p = param('project'); return p && repoNames().includes(p) ? p : null; };
  const projectSort = () => param('psort') === '1';
  // A part with only the rows of one project, or with each project's rows together: every list in it whose items all
  // name their project (repo) is filtered, then sorted by project, the order inside a project kept. A part's byRepo
  // ({repo: fields}) holds what is one project's where the part itself holds the sum of all (the belt's cap): filtered,
  // the part carries that project's.
  function byProject(d, repo, sort) {
    if (Array.isArray(d)) {
      let a = d.map((x) => byProject(x, repo, sort));
      if (a.length && a.every((x) => x && typeof x === 'object' && typeof x.repo === 'string')) {
        if (repo) a = a.filter((x) => x.repo === repo);
        if (sort) a = a.map((x, i) => [x, i]).sort((x, y) => (x[0].repo < y[0].repo ? -1 : x[0].repo > y[0].repo ? 1 : x[1] - y[1])).map((x) => x[0]);
      }
      return a;
    }
    if (!d || typeof d !== 'object') return d;
    const o = {};
    Object.keys(d).forEach((k) => { o[k] = k === 'byRepo' ? d[k] : byProject(d[k], repo, sort); });
    const own = repo && d.byRepo && typeof d.byRepo === 'object' && Object.prototype.hasOwnProperty.call(d.byRepo, repo) ? d.byRepo[repo] : null;
    return own && typeof own === 'object' ? Object.assign(o, own) : o;
  }
  // ---- the history: the older entries of the lists the snapshot cuts to its newest (conveyor/README.md, The snapshot) ----
  // A panel with older(live, history) is drawn from its live part with the older entries laid in from the history:
  // the page server's GET /history, the same part built from every entry. It is asked for when such a panel is drawn
  // on the tab in view, at most once every HISTORY_MS, and each such panel is drawn again when a history that differs
  // from the last one has come (an equal one draws nothing). Until one has come, or when it does not read, the live
  // part is drawn alone. The history changes where the live part does not (an older declined line filed), and the
  // feed never draws again a part that does not change: so each read, whether it came or failed, sets a timer that
  // HISTORY_MS later reads it again while such a panel is on the tab in view and the page is shown; and such a panel
  // the page draws when the last read is HISTORY_MS old (the tab or the page shown again after the timer found those
  // panels hidden) is drawn again, which reads it again too.
  const HISTORY_MS = 60000;
  let hist = null, histText = null, histAt = null, histVer = 0, histTimer = null;
  const histCan = () => /^https?:$/.test(window.location.protocol) && typeof window.fetch === 'function';
  const histDue = () => histCan() && (histAt === null || now() - histAt >= HISTORY_MS);
  const olderShown = () => Boolean(last) && Array.from(panels).some(([id, p]) => typeof p.mod.older === 'function' && tabOf(id) === tab);
  function drawOlder() {
    if (last) panels.forEach((p, id) => { if (typeof p.mod.older === 'function' && tabOf(id) === tab) draw(p, last.panels[partOf(id)]); });
    arrangeSoon();
  }
  function readHistory() {
    histAt = now();
    if (histTimer !== null) window.clearTimeout(histTimer);
    histTimer = window.setTimeout(() => { histTimer = null; if (!doc.hidden && olderShown()) readHistory(); }, HISTORY_MS);
    window.fetch('history').then((r) => (r.ok ? r.json() : null)).then((x) => {
      if (!x || typeof x !== 'object' || !x.panels || typeof x.panels !== 'object') return;
      const text = JSON.stringify(x.panels);
      if (text === histText) return;
      histText = text;
      hist = x.panels;
      histVer += 1;
      // A page not shown draws it when shown again (shownAgain()), as the panels' history version changed.
      if (!doc.hidden) drawOlder();
    }, () => {});
  }
  function withOlder(mod, live) {
    if (typeof mod.older !== 'function') return live;
    if (histDue()) readHistory();
    const old = hist && hist[mod.id];
    return old && !old.error && old.data && typeof old.data === 'object' ? mod.older(live, old.data) : live;
  }
  // joined(live, older, key): the live list, then each entry of older that no live entry has the key of (a live entry
  // is the newer reading of the same thing). A live list that is not one (the host gave none) stays as it is.
  function joined(live, older, key) {
    if (!Array.isArray(live) || !Array.isArray(older)) return live;
    const seen = new Set(live.map(key));
    return live.concat(older.filter((x) => !seen.has(key(x))));
  }
  // The data a panel is drawn from: its part's, cut to the project filtered to and sorted by project when it lists rows
  // of every project and either is asked for.
  function shownData(mod, data) {
    const repo = projectOnly(), sort = projectSort();
    return mod.projects === true && (repo || sort) ? byProject(data, repo, sort) : data;
  }
  function redrawAll() {
    panels.forEach((p) => { p.json = undefined; });
    if (last) idsOf(tab).forEach((id) => draw(panels.get(id), last.panels[partOf(id)]));
    drawHead();
    arrangeSoon();
  }
  // The filter set from the machine head: one project (the Board and the Rules tab show it too), or every project (null).
  function setProject(repo) {
    params(repo ? { project: repo, repo } : { project: null });
    redrawAll();
    say(repo ? `Showing ${repo} only` : 'Showing every project');
  }
  function setProjectSort(on) {
    params({ psort: on ? '1' : null });
    redrawAll();
    say(on ? 'Sorted by project' : 'Not sorted by project');
  }
  // A row's project, as a tag with the project's own colour (its place among the host's projects) beside its name:
  // never colour alone.
  function tag(repo) {
    const el = h('span', 'project-tag', repo), i = repoNames().indexOf(repo);
    if (i >= 0) el.dataset.hue = String(i % 5);
    el.dataset.project = String(repo);
    return el;
  }
  // What needs attention on a tab: each of its panels may say how many things (attention(data) of its module).
  function attention(t) {
    if (!last || !last.panels) return 0;
    return idsOf(t).reduce((n, id) => {
      const mod = modules.get(id), part = last.panels[partOf(id)];
      if (typeof mod.attention !== 'function' || !part || !part.data || typeof part.data !== 'object') return n;
      try { const k = Number(mod.attention(part.data)); return n + (Number.isFinite(k) && k > 0 ? k : 0); } catch (e) { return n; }
    }, 0);
  }
  function drawTabs() {
    const bar = byId('tabs');
    if (!bar || !grid) return;  // a page with the head alone has the tabs as links (startHead)
    if (!bar.firstChild) {
      const list2 = h('div', 'tabs-list');
      list2.setAttribute('role', 'tablist'); list2.setAttribute('aria-label', 'Dashboard views');
      TABS.forEach(([t, name]) => {
        const b = h('button', 'tab');
        b.type = 'button'; b.id = `tab-${t}`; b.dataset.tab = t;
        b.setAttribute('role', 'tab'); b.setAttribute('aria-controls', 'grid');
        b.append(h('span', 'tab-name', name), h('span', 'tab-count'));
        b.addEventListener('click', () => setTab(t, true));
        b.addEventListener('keydown', (e) => {
          const i = TABS.findIndex((x) => x[0] === t);
          const to = { ArrowRight: i + 1, ArrowLeft: i - 1, Home: 0, End: TABS.length - 1 }[e.key];
          if (to === undefined) return;
          e.preventDefault();
          const nt = TABS[(to + TABS.length) % TABS.length][0];
          setTab(nt, true);
          byId(`tab-${nt}`).focus();
        });
        list2.append(b);
      });
      bar.append(list2);
    }
    TABS.forEach(([t, name]) => {
      const b = byId(`tab-${t}`), on = t === tab, n = attention(t);
      b.setAttribute('aria-selected', String(on));
      b.tabIndex = on ? 0 : -1;
      const count = b.querySelector('.tab-count');
      // Part of the tab's words, "Overview · 4", so the count is read on every tab.
      count.textContent = n ? `· ${n}` : '';
      count.hidden = !n;
      b.setAttribute('aria-label', n ? `${name}: ${n} ${n === 1 ? 'thing needs' : 'things need'} attention` : name);
    });
    grid.setAttribute('role', 'tabpanel');
    grid.setAttribute('aria-labelledby', `tab-${tab}`);
  }
  // The tab in view: its panels are put in the page and drawn from the last data; the other tab's are taken out.
  function setTab(t, push) {
    if (!TABS.some((x) => x[0] === t)) return;
    if (push) address(t, true);
    try { window.localStorage.setItem(TAB_KEY, t); } catch (e) { /* the tab then lasts for this visit */ }
    if (t === tab) return;
    tab = t;
    grid.classList.remove('fresh');
    applyLayout();
    if (last) idsOf(tab).forEach((id) => draw(panels.get(id), last.panels[partOf(id)]));
    else if (!loaded && failedLoads) idsOf(tab).forEach((id) => draw(panels.get(id), { error: NOTHING, data: null }));
    arrange();
    say(`${TABS.find((x) => x[0] === t)[1]} tab`);
  }

  // ---- words a phone can open ----
  // A phone shows no hover text. An item that explains itself only there (a step of a card's track, a fix's reason, a
  // line cut to fit, a figure's mark) carries its words in data-tip as well as its title: a tap on it opens them in a
  // small popover under it, and a second tap, a tap elsewhere or Escape closes it. A tap on such an item inside a link
  // opens its words, not the link. An item drawn again in its place closes its popover (tick()); an item kept in its
  // place and given new words shows them in its open popover, and one left with none (empty text) closes it (tip()).
  let tipAt = null;  // the item whose words are open
  function tip(el, text) {
    if (text) { el.title = text; el.dataset.tip = text; } else { el.removeAttribute('title'); delete el.dataset.tip; }
    if (el === tipAt) { if (text) openTip(el); else closeTip(); }
    return el;
  }
  function tipBox() {
    let box = byId('tip');
    if (!box) { box = h('div', 'tip-pop'); box.id = 'tip'; box.setAttribute('role', 'tooltip'); box.hidden = true; doc.body.append(box); }
    return box;
  }
  function closeTip() {
    if (!tipAt) return;
    tipAt.removeAttribute('aria-describedby');
    tipAt = null;
    tipBox().hidden = true;
  }
  function openTip(el) {
    const box = tipBox();
    box.textContent = el.dataset.tip;
    box.hidden = false;
    placeTip(el);
    el.setAttribute('aria-describedby', box.id);
    tipAt = el;
  }
  // Under the item, inside the window's width. arrange() places it again, as a draw can move a kept item (a new row
  // above it).
  function placeTip(el) {
    const box = tipBox(), r = el.getBoundingClientRect(), room = doc.documentElement.clientWidth;
    box.style.left = `${Math.max(8, Math.min(r.left, room - box.offsetWidth - 8)) + window.scrollX}px`;
    box.style.top = `${r.bottom + 4 + window.scrollY}px`;
  }
  function wireTips() {
    doc.addEventListener('click', (e) => {
      const el = e.target && e.target.closest ? e.target.closest('[data-tip]') : null;
      if (!el) { closeTip(); return; }
      const ctl = el.parentElement && el.parentElement.closest('a, button');
      if (ctl) { e.preventDefault(); e.stopPropagation(); }
      const again = el === tipAt;
      closeTip();
      if (!again) openTip(el);
    }, true);
    doc.addEventListener('keydown', (e) => { if (e.key === 'Escape') closeTip(); });
  }

  // ---- one panel's frame ----
  function tool(cls, label, glyph, onClick) {
    const b = h('button', `tool ${cls}`);
    b.type = 'button'; b.setAttribute('aria-label', label); b.title = label;
    if (glyph) b.append(icon(glyph));
    b.addEventListener('click', onClick);
    return b;
  }
  function skeleton() {
    const el = h('div', 'skeleton');
    el.setAttribute('aria-hidden', 'true');
    el.append(h('span', 'bar w60'), h('span', 'bar w90'), h('span', 'bar w75'));
    return el;
  }
  // Where Conveyor runs, as the page says it (#112): "the build machine" only when the host file sets one up (Health's
  // host.local is not true). On one machine, and before any data has loaded, the page names no build machine.
  function remote() {
    const host = last && last.panels && last.panels.health && last.panels.health.data && last.panels.health.data.host;
    return !!(host && typeof host === 'object' && host.local !== true);
  }
  const machineWord = () => (remote() ? 'the build machine' : 'this machine');
  // Who answers a press: the build machine, where the action runs over SSH, or on one machine the Board itself.
  const answerer = () => (remote() ? 'the build machine' : 'the Board');
  // A read that failed says what is not seen and the one thing to try (text: retryText() for what Conveyor sends);
  // the reader's own reason, which names files and internal parts, only on tap: on one machine, that reason is what
  // to correct. A note in the panel, or a state's detail (draw()). The text sends the owner to the panel's own
  // restart button (restartHere()), which the panel shows next to it (#115): the head's shows only at a fault.
  const retryText = () => (remote() ? 'Make sure that the build machine is on. Then press Restart the Board\'s feed in this panel.'
    : 'Press Restart the Board\'s feed in this panel. If this continues, the details say what to correct.');
  // A "Restart the Board's feed" button for a text that tells the owner to press it, with what the host answered
  // beside it: that it is asking, then the answer (restart()). A restart costs the collector's time: a second click.
  function restartHere() {
    const box = h('span', 'restart-here'), b = h('button', 'btn btn-quiet', 'Restart the Board\'s feed'), said = h('span', 'detail');
    b.type = 'button'; b.dataset.act = 'restart';
    said.setAttribute('role', 'status');
    twice(b, 'spend', 'Click again to restart the Board\'s feed', () => {
      b.disabled = true; said.textContent = asking();
      restart().then((t) => { said.textContent = t; b.disabled = false; });
    });
    box.append(b, said);
    return box;
  }
  // Whether a panel of the tab in view, Health aside, could not read or draw its data (an error, or a note over the
  // data it read last). Health's Data row shows its restart then (ctx.faults()), and is drawn again when it changes.
  let faultsShown = false;
  const panelFaults = () => Array.from(panels.values()).some((q) => q.mod.id !== 'health' && tabOf(q.mod.id) === tab && (q.state === 'error' || !!q.note));
  function faultsChanged() {
    const f = panelFaults(), hp = panels.get('health');
    if (f === faultsShown) return;
    faultsShown = f;
    if (hp && hp.state === 'ready' && tabOf('health') === tab && last) { hp.json = undefined; draw(hp, last.panels[partOf('health')]); }
  }
  const details = (raw) => (raw ? `Details: ${raw}` : '');
  function unread(text, raw) { return tip(h('p', 'warn-note', text), details(raw)); }
  function stateBlock(kind, title, detail) {
    const el = h('div', `state state-${kind}`);
    el.append(icon(kind === 'error' ? 'bad' : 'ok'), h('p', 'state-title', title));
    if (detail) el.append(h('p', 'state-detail', detail));
    return el;
  }
  function frame(mod) {
    const id = mod.id, title = mod.title;
    const el = h('section', 'panel');
    el.id = `panel-${id}`; el.dataset.panel = id; el.dataset.state = 'loading'; el.dataset.tab = mod.tab;
    el.setAttribute('aria-labelledby', `panel-${id}-title`);
    const head = h('header', 'panel-head');
    // Not a <button>: Firefox does not start a drag from one. It takes the focus and the arrow keys all the same.
    const drag = h('span', 'tool drag');
    drag.setAttribute('role', 'button'); drag.tabIndex = 0; drag.setAttribute('draggable', 'true');
    drag.setAttribute('aria-label', `Move ${title}: drag it, or press an arrow key`); drag.title = `Move ${title}: drag it, or press an arrow key`;
    drag.append(icon('grip'));
    drag.addEventListener('keydown', (e) => {
      const by = { ArrowUp: -1, ArrowLeft: -1, ArrowDown: 1, ArrowRight: 1 }[e.key];
      if (!by) return;
      e.preventDefault(); move(id, by); drag.focus();
    });
    drag.addEventListener('dragstart', (e) => {
      dragging = id; el.classList.add('dragging');
      if (e.dataTransfer) { e.dataTransfer.effectAllowed = 'move'; e.dataTransfer.setData('text/plain', id); if (e.dataTransfer.setDragImage) e.dataTransfer.setDragImage(el, 16, 16); }
    });
    drag.addEventListener('dragend', () => { el.classList.remove('dragging'); if (dragging) { dragging = null; save(); say(`${title} moved`); } });
    const heading = h('h2', 'panel-title', title);
    heading.id = `panel-${id}-title`;
    const count = h('span', 'panel-count');
    const tools = {
      up: tool('move move-up', `Move ${title} up`, 'up', () => { move(id, -1); (tools.up.disabled ? tools.down : tools.up).focus(); }),
      down: tool('move move-down', `Move ${title} down`, 'down', () => { move(id, 1); (tools.down.disabled ? tools.up : tools.down).focus(); }),
      collapse: tool('collapse', '', 'down', () => toggle('collapsed', id, !lay().collapsed.includes(id))),
      // The panel's width, among the widths it can take; applyLayout() shows the one in the layout.
      size: h('select', 'tool size'),
    };
    tools.size.id = `size-${id}`; tools.size.setAttribute('aria-label', `Width of ${title}`); tools.size.title = `Width of ${title}`;
    widthsOf(id).forEach((s) => { const o = h('option', null, s[0].toUpperCase() + s.slice(1)); o.value = s; tools.size.append(o); });
    tools.size.addEventListener('change', () => { const to = tools.size.value; change(() => { lay().sizes[id] = to; }, `${title} is now ${to}`); });
    // Whether a panel shows is set in Customize only: an × on the head read as "close", and one stray tap on a phone
    // took the panel off the page.
    const bar = h('div', 'panel-tools');
    bar.append(tools.size, tools.up, tools.down, tools.collapse);
    // A panel's own actions on its whole list (ctx.headActs), between its count and the panel's tools.
    const acts = h('span', 'panel-acts');
    acts.hidden = true;
    head.append(drag, heading, count, acts, bar);
    const body = h('div', 'panel-body');
    body.id = `panel-${id}-body`;
    tools.collapse.setAttribute('aria-controls', body.id);
    body.append(skeleton());
    // The length: how many rows there are in all and the one control to show all, then the handle on the lower edge.
    const foot = h('div', 'panel-foot'), rowsNote = h('span', 'panel-rows'), showAll = h('button', 'btn btn-quiet show-all');
    rowsNote.setAttribute('aria-live', 'polite');
    showAll.type = 'button';
    foot.append(rowsNote, showAll);
    foot.hidden = true;
    const grip = h('div', 'panel-length');
    grip.setAttribute('role', 'slider'); grip.tabIndex = 0; grip.setAttribute('aria-orientation', 'vertical');
    grip.setAttribute('aria-label', `Length of ${title}: drag the edge, or press the up and down arrow keys`);
    grip.title = `Length of ${title}: drag, or the up and down arrow keys`;
    grip.hidden = true;
    el.append(head, body, foot, grip);
    // While a panel is dragged, the one under the pointer makes room at once; the order is saved on drop.
    el.addEventListener('dragover', (e) => {
      if (!dragging || dragging === id) return;
      e.preventDefault();
      // Past the middle of the panel under the pointer: down a panel that fills its row, across one that shares it.
      const r = el.getBoundingClientRect(), l = lay();
      const after = r.width > grid.clientWidth * 0.6 ? e.clientY > r.top + r.height / 2 : e.clientX > r.left + r.width / 2;
      const rest = l.order.filter((x) => x !== dragging), at = rest.indexOf(id) + (after ? 1 : 0);
      rest.splice(at, 0, dragging);
      if (rest.join() !== l.order.join()) flip(() => { l.order = rest; applyLayout(); });
    });
    el.addEventListener('drop', (e) => e.preventDefault());
    const p = { mod, el, body, count, tools, foot, rowsNote, showAll, grip, json: undefined, state: 'loading', renders: 0, nums: new Map(), natural: 0 };
    showAll.addEventListener('click', () => {
      const all = showAll.textContent === 'Show all';
      setLength(p, all ? 'all' : mod.rows, all ? `${title} shows all its rows` : `${title} shows its first ${mod.rows} rows`);
      showAll.focus();
    });
    grip.addEventListener('keydown', (e) => lengthKey(p, e));
    grip.addEventListener('pointerdown', (e) => lengthDrag(p, e));
    if (typeof window.ResizeObserver === 'function') {
      const ro = new window.ResizeObserver(() => { if (el.isConnected) arrangeSoon(); });
      ro.observe(head); ro.observe(body);
    }
    p.ctx = {
      h, chip, icon, tip, unread, get retry() { return retryText(); }, restartButton: restartHere, faults: panelFaults, get machine() { return machineWord(); }, get answerer() { return answerer(); }, details, since, clock, when, stamp, dur, took, money, modelName, findings, survived, judged, reviewChip, verdictSaid, output, issueLink, depRef, list, post, fresh, motion, state: stateBlock, track, trackDetail, trackShell, earlierTip, testProgress, fixNow,
      param, params, pickRepo, project, now, tag, setTab, restart, goTo, panelHref: (id) => panelHref(id), failure, failureLine, failureShort, twice, undoLine, text: findingText,
      pausedSaid, refusal, depPicked,
      // Whether the lists are sorted by project (the machine head's sort): a panel that orders a list itself keeps each
      // project's rows together then.
      sorted: projectSort,
      // whole: whether this draw is to draw the panel whole (a new time format, project or model name), not only what
      // changed in its part: a panel that keeps its rows as they were draws each again then.
      get whole() { return p.whole === true; },
      // updatedAt(): when the collector began the snapshot drawn now (ms by the page host's clock), or null.
      updatedAt: () => updatedAt,
      // Whether this page has the live feed open, and when what it shows was published (ms, or null).
      feed: () => ({ open: feedOpen, updatedAt }),
      // number(key, value, format): a figure that counts from the value this panel showed under that key last time.
      number: (key, value, fmt) => counter(p.nums, key, value, fmt),
      // headActs(...nodes): the panel's actions on its whole list, drawn in its heading; with none, the heading has none.
      headActs(...nodes) { acts.replaceChildren(...nodes); acts.hidden = !nodes.length; },
      // title(text): the panel's heading says text ("Board: sample", a panel that shows one project), or its title again.
      title(text) { heading.textContent = text || mod.title; },
      // relength(): the panel's rows changed without a new part (a group opened): its length and place are worked out again.
      relength() { clip(p); arrangeSoon(); },
      // redraw(): the panel drawn again from the part it has, its count too (what the owner did changed what it shows).
      redraw() { p.json = undefined; if (last) draw(p, last.panels[partOf(mod.id)]); arrangeSoon(); },
      // more(key, items, show, size): the shared long list (see more above), kept per panel and key. Its step is the
      // panel's length (mod.rows) unless size says another; the list is then the panel's one length control (clipPlan).
      // The Show all of a list of the panel's rows shows all of the panel too: a length the owner set (its edge) goes
      // back to the default, all. That of a list inside a row (a project's changes in Release) shows that list only.
      more: (key, items, show, size) => {
        const box = more(`${mod.id}:${key}`, items, show, size || (mod.rows === 'all' ? PAGE : mod.rows), (kind) => {
          if (kind === 'all' && !inRow(p, box) && layouts[tabOf(mod.id)].lengths[mod.id] !== undefined) setLength(p, 'all', `${title} shows all its rows`);
          else { clip(p); arrangeSoon(); }
        }, keptScope(mod));
        return box;
      },
      // kept(kind, name) and keep(kind, name, value): what a reload keeps (see keep above). Kind 'draft' is one for
      // every project (its name names the record); any other kind is kept by the project the panel shows (keptScope).
      kept: (kind, name) => keptGet(kind, kind === 'draft' ? '' : keptScope(mod), name),
      keep: (kind, name, value) => keep(kind, kind === 'draft' ? '' : keptScope(mod), name, value),
    };
    return p;
  }
  // Draws one panel from its own part. A part equal to the one drawn last leaves the panel untouched, but a panel
  // with same(body, data, ctx) is told that part came again (the Board weighs a snapshot by when it was begun,
  // so one equal to a snapshot it turned away is still news to it). A panel that throws shows its own error and takes
  // no other panel with it. It does not cut the panel to its length: each caller runs arrange() or arrangeSoon() after
  // it, which cuts every panel of the tab in one read round and one write round (a cut here laid the page out once a panel).
  function draw(p, part) {
    // A panel with older entries is drawn again when a newer history has come, or when it is time to read it again;
    // not whole (ctx.whole), so a panel that draws its rows with ctx.list keeps the rows that did not change.
    const older = typeof p.mod.older === 'function' && (p.hist !== histVer || histDue());
    p.hist = histVer;
    // The model names (modelName) are part of what a panel shows: a new alias or name draws it again.
    const names = namesKey(), json = JSON.stringify(part === undefined ? null : part) + names;
    if (p.json === json && !older) {
      if (p.state === 'ready' && !p.note && typeof p.mod.same === 'function') {
        try { p.mod.same(p.body, shownData(p.mod, part.data), p.ctx); } catch (e) { /* the next part that differs draws the panel whole */ }
      }
      return;
    }
    // Drawn whole (ctx.whole): the first draw, asked for (redrawAll, ctx.redraw), or the model names changed, whatever
    // else changed too.
    p.whole = p.json === undefined || p.names !== names;
    p.json = json; p.names = names;
    p.renders += 1;
    p.el.dataset.renders = String(p.renders);
    const mod = p.mod;
    let state = 'ready', message = null, raw = '';
    const from = remote() ? 'the build machine' : 'Conveyor', From = remote() ? 'The build machine' : 'Conveyor';
    if (!part || typeof part !== 'object') { state = 'error'; message = `${From} sent nothing for this panel, so the Board cannot show it. If this continues, press Restart the Board's feed, below.`; }
    else if (typeof part.error === 'string' && part.error) { state = 'error'; message = `The Board could not get this panel from ${from}, so it cannot show it. ${retryText()}`; raw = part.error; }
    else if (!part.data || typeof part.data !== 'object') { state = 'error'; message = `${From} sent no data for this panel, so the Board cannot show it. If this continues, press Restart the Board's feed, below.`; }
    // A panel that shows data keeps it through a failed read, with a short note above it. Emptied, it moved all below
    // it up, and its next good read built it anew: each open "Every step", output and inner scroll was closed or reset.
    if (p.note) { p.note.remove(); p.note = null; }
    if (state === 'error' && p.state === 'ready') {
      p.note = h('div', 'panel-note');
      p.note.setAttribute('role', 'status');
      p.note.append(unread(`The Board could not read ${mod.title} just now, so it shows what it read last. If this continues, press Restart the Board's feed, below.`, raw), restartHere());
      p.body.prepend(p.note);
      if (mod.id !== 'health') faultsChanged();
      return;
    }
    try {
      const data = state === 'ready' ? shownData(mod, withOlder(mod, part.data)) : null;
      if (state === 'ready' && mod.isEmpty(data)) state = 'empty';
      if (state !== 'ready' || p.state !== 'ready') { p.body.replaceChildren(); p.ctx.headActs(); }
      if (state === 'error') {
        mod.error(p.body, message, p.ctx);
        const detail = raw && p.body.querySelector('.state-detail');
        if (detail) tip(detail, details(raw));
        // The restart the message names, next to it.
        (p.body.querySelector('.state-error') || p.body).append(restartHere());
      }
      // An empty panel is given its data too: what it says under its tick may need it (Needs you's retried pushes).
      else if (state === 'empty') mod.empty(p.body, p.ctx, data);
      else mod.render(p.body, data, p.ctx);
      const n = state === 'ready' && mod.count ? mod.count(data) : null;
      p.count.textContent = n === null || n === undefined ? '' : String(n);
      p.count.hidden = p.count.textContent === '';
    } catch (e) {
      state = 'error';
      p.ctx.headActs();
      // The page's own fault: what to try, and the error itself on tap.
      p.body.replaceChildren(stateBlock('error', `The Board could not draw ${mod.title}`,'Reload the page to draw it again.'));
      tip(p.body.querySelector('.state-detail'), details(String((e && e.message) || e)));
    }
    retitle(p.body);
    p.state = state;
    p.el.dataset.state = state;
    if (mod.id !== 'health') faultsChanged();
  }

  // ---- Customize: show or hide the panels of the tab in view, density, theme, time, date, restore ----
  function choice(name, values, current, pick) {
    const set = h('fieldset', 'choice');
    set.append(h('legend', null, name));
    values.forEach((v) => {
      const label = h('label', 'choice-item'), input = h('input');
      input.type = 'radio'; input.name = `choice-${name.toLowerCase()}`; input.value = v; input.checked = v === current;
      input.addEventListener('change', () => pick(v));
      // A word is shown capitalized ("Compact"); a form ("mm/dd/yyyy", "12-hour") as it is.
      label.append(input, h('span', null, /^[a-z]+$/.test(v) ? v[0].toUpperCase() + v.slice(1) : v));
      set.append(label);
    });
    return set;
  }
  // Each panel of the tab in view: whether it shows (fixed for one that always shows). Its width is on its head (frame()).
  function drawCustomize() {
    const box = byId('customize-body'), open = byId('customize-open');
    if (!box) return;
    const held = doc.activeElement && box.contains(doc.activeElement) ? doc.activeElement.id || doc.activeElement.value : null;
    const set = h('fieldset', 'choice'), l = lay();
    set.append(h('legend', null, `Panels of ${TABS.find((x) => x[0] === tab)[1]}`));
    l.order.forEach((id) => {
      const mod = modules.get(id), row = h('div', 'custom-row'), label = h('label', 'choice-item'), input = h('input');
      input.type = 'checkbox'; input.id = `show-${id}`; input.checked = !l.hidden.includes(id);
      input.addEventListener('change', () => toggle('hidden', id, !input.checked));
      // A panel that is always shown keeps its box, ticked and fixed, so the list still names every panel of the tab.
      if (!hideable(id)) input.disabled = true;
      label.append(input, h('span', null, hideable(id) ? mod.title : `${mod.title} (always shown)`));
      row.append(label);
      set.append(row);
    });
    // The layout is kept in this browser alone: the owner's other browsers (the phone, another computer) keep their own.
    const restore = h('button', 'btn', 'Restore default layout'), row = h('div', 'sheet-restore');
    restore.type = 'button'; restore.id = 'restore-layout';
    restore.addEventListener('click', reset);
    row.append(restore, h('span', 'sheet-note', 'this browser only'));
    box.replaceChildren(set,
      choice('Density', DENSITIES, prefs.density, (v) => change(() => { prefs.density = v; })),
      choice('Theme', THEMES, prefs.theme, (v) => change(() => { prefs.theme = v; })),
      choice('Time', CLOCKS, prefs.time, (v) => change(() => { prefs.time = v; })),
      choice('Date', DATES, prefs.date, (v) => change(() => { prefs.date = v; })), row);
    if (held) { const again = byId(held) || box.querySelector(`input[value="${held}"]`); if (again) again.focus({ preventScroll: true }); }
    const n = l.hidden.length;
    open.querySelector('.label').textContent = n ? `Customize (${n} hidden)` : 'Customize';
  }
  function wireCustomize() {
    const open = byId('customize-open'), sheet = byId('customize');
    const show = (on) => { sheet.hidden = !on; open.setAttribute('aria-expanded', String(on)); };
    open.addEventListener('click', () => show(sheet.hidden));
    byId('customize-close').addEventListener('click', () => { show(false); open.focus(); });
    doc.addEventListener('keydown', (e) => { if (e.key === 'Escape' && !sheet.hidden) { show(false); open.focus(); } });
  }
  // On a phone the head's buttons (Account, the feed's restart, Customize) are one Menu button's list (app.css): a tap
  // opens it, and a second tap, Esc or a tap outside it closes it. A tap on a button in it leaves it open, so the
  // restart's second click is in reach. Wider, Menu is not shown and the list is the row of buttons.
  function wireMenu() {
    const box = doc.querySelector('.top-actions'), btn = box && box.querySelector('.top-menu');
    if (!btn) return;
    const show = (on) => { box.classList.toggle('open', on); btn.setAttribute('aria-expanded', String(on)); };
    btn.addEventListener('click', () => show(!box.classList.contains('open')));
    doc.addEventListener('click', (e) => { if (box.classList.contains('open') && !box.contains(e.target)) show(false); });
    doc.addEventListener('keydown', (e) => { if (e.key === 'Escape' && box.classList.contains('open')) { show(false); btn.focus(); } });
  }
  // The page's keys, one handler: 1 to 5 open the first five tabs in order, n goes to Needs you, / to the Board filter
  // and ? shows the list of keys (#keys; Esc or Close hides it and gives the focus back to where it was). A key typed in
  // a field, or with Ctrl, Alt or Meta (a browser's own keys), is left alone.
  function wireKeys() {
    const sheet = byId('keys'), close = byId('keys-close');
    if (!sheet) return;
    let back = null;
    const show = (on) => {
      if (on) back = doc.activeElement;
      sheet.hidden = !on;
      if (on) close.focus();
      else if (back && back.isConnected && back !== doc.body) back.focus();
    };
    close.addEventListener('click', () => show(false));
    doc.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') { if (!sheet.hidden) show(false); return; }
      if (e.ctrlKey || e.altKey || e.metaKey || e.defaultPrevented) return;
      const t = e.target;
      if (t && t.closest && t.closest('input, textarea, select, [contenteditable]:not([contenteditable="false"])')) return;
      const n = '12345'.indexOf(e.key);
      if (e.key.length === 1 && n >= 0) setTab(TABS[n][0], true);
      else if (e.key === 'n') goTo('needs');
      else if (e.key === '/') {
        goTo('board');
        // A collapsed Board is opened, as its filter is in the body the collapse hides.
        const b = panels.get('board');
        if (b && !b.el.hidden && lay().collapsed.includes('board')) toggle('collapsed', 'board', false);
        const f = panels.has('board') && panels.get('board').el.querySelector('[data-filter="text"]');
        if (f) f.focus();
      } else if (e.key === '?') show(sheet.hidden);
      else return;
      e.preventDefault();
    });
  }

  // ---- the head line's tiles ----
  // Each tile is a figure over its label, a link to the panel that holds its detail, on that panel's tab. They are
  // drawn on every tab from the last data, whichever tab the parts are for, and count like a panel's figures.
  const DASH = '—';
  const panelHref = (id) => `index.html?tab=${modules.has(id) ? tabOf(id) : 'overview'}#panel-${id}`;
  // Opens the tab a panel is on and takes the focus to it; a panel the owner hid says where to bring it back.
  function goTo(id) {
    if (!modules.has(id)) return;
    setTab(tabOf(id), true);
    const p = panels.get(id);
    if (p.el.hidden) { say(`${p.mod.title} is not on the page. Use Customize to show it again.`); return; }
    p.el.tabIndex = -1;
    if (typeof p.el.scrollIntoView === 'function') p.el.scrollIntoView({ block: 'start', behavior: motion() ? 'smooth' : 'auto' });
    p.el.focus({ preventScroll: true });
  }
  function buildHead() {
    const box = byId('stats');
    if (!box || !headMod) { if (box) box.hidden = true; return; }
    box.setAttribute('aria-label', headMod.label || 'At a glance');
    const tiles = headMod.tiles.map((spec) => {
      const a = h('a', 'stat'), fig = h('span', 'stat-fig'), value = h('span', 'stat-value'), sub = h('span', 'stat-sub');
      const mark = h('span', 'stat-mark'), said = h('span', 'sr-only'), gap = h('span', 'stat-gap');
      a.href = panelHref(spec.panel); a.dataset.stat = spec.key;
      if (spec.drop) a.dataset.drop = String(spec.drop);
      mark.append(icon('warn'));
      fig.append(value, sub, mark);
      gap.hidden = true;
      a.append(fig, h('span', 'stat-label', spec.label), gap, said);
      const t = { spec, a, value, sub, mark, said, gap, words: '' };
      // A figure that leaves something out, or a dash, says why in words under it at the first tap (a phone has no
      // hover); the next tap opens its panel.
      a.addEventListener('click', (e) => {
        if (e.button || e.ctrlKey || e.metaKey || e.shiftKey || e.altKey) return;  // a new tab or window opens it as a link
        if (t.words && t.gap.hidden) { e.preventDefault(); t.gap.textContent = t.words; t.gap.hidden = false; fitHead(); return; }
        if (!modules.has(spec.panel)) return;  // a page with the head alone (account.html): the link opens the Board
        e.preventDefault();
        goTo(spec.panel);
      });
      return t;
    });
    box.replaceChildren(...tiles.map((t) => t.a));
    headView = { box, tiles, nums: new Map() };
    drawHead();
  }
  let drawingHead = false;
  function drawHead() {
    if (!headView) return;
    const parts = (last && last.panels) || {};
    const part = (id) => { const x = parts[id]; return x && typeof x === 'object' && !x.error && x.data && typeof x.data === 'object' ? x.data : null; };
    drawingHead = true;
    headView.tiles.forEach((t) => {
      let r;
      try { r = t.spec.read(part, { money }) || {}; } catch (e) { r = {}; }
      // A count moves through whole numbers only: the motion's in-between values are never shown as fractions.
      const known = num(r.value), fmt = typeof r.fmt === 'function' ? r.fmt : (v) => String(Math.round(v));
      const text = known ? fmt(r.value) : DASH;
      if (headView.nums.get(t.spec.key) !== (known ? r.value : null) || t.value.textContent === '') {
        // The fit below measures the figure the count starts from; one that lands wider is fitted again when it lands.
        // With no motion the count lands at once, before the other tiles are written: the fit at the end measures it.
        t.value.replaceChildren(counter(headView.nums, t.spec.key, known ? r.value : null, (v) => (num(v) ? fmt(v) : DASH), () => { if (!drawingHead) refit(); }));
      }
      t.sub.textContent = known && r.sub ? ` ${r.sub}` : '';
      t.sub.hidden = !t.sub.textContent;
      const tone = known ? r.tone || t.spec.tone : null;
      if (tone) t.a.dataset.tone = tone; else delete t.a.dataset.tone;
      t.a.dataset.known = String(known);
      // A figure that leaves something out has a mark, its words on hover, on a tap on the mark and to a screen reader.
      t.mark.hidden = !r.left;
      t.a.classList.toggle('stat-partial', Boolean(r.left));
      const words = [r.left, r.said].filter(Boolean).join('; ');
      t.said.textContent = words ? `, ${words}` : '';
      tip(t.mark, r.left ? words : '');
      // The words a tap shows under the figure: what it leaves out, or why it is a dash (the tile's dash, else not read).
      t.words = known ? r.left || '' : r.dash || 'Not read yet';
      if (!t.words) t.gap.hidden = true;
      else if (!t.gap.hidden) t.gap.textContent = t.words;
      t.a.title = `${t.spec.label}: ${text}${known && r.sub ? ` ${r.sub}` : ''}${known ? '' : ` (${r.dash ? r.dash.toLowerCase() : 'not read'})`}${words ? `. ${words}` : ''}`;
    });
    drawingHead = false;
    refit();
    drawMachine(part);
    drawOverlays(part);
  }
  // What a panel's file draws over every tab (overlay({part, draw(data, ctx)}): the Rules' setup of a new repository),
  // from that part, whichever tab is open; given null when the part is not read. One that throws takes nothing with it.
  const overlays = [];
  function overlay(mod) {
    if (!mod || typeof mod.part !== 'string' || typeof mod.draw !== 'function') throw new Error('an overlay needs part and draw');
    overlays.push(mod);
  }
  function drawOverlays(part) {
    overlays.forEach((mod) => {
      try {
        mod.draw(part(mod.part), { h, chip, money, post, undoLine, refusal, project, state: stateBlock, param, params, issueLink, depRef, depPicked,
          since, when, setTab, updatedAt: () => updatedAt, title() {}, relength() {} });
      } catch (e) { /* the overlay is not drawn */ }
    });
  }
  // The machine head, under the tabs on every tab: head.js states it (machine: {part, draw(el, data, ctx)}) and it is
  // drawn from that part, whichever tab is open; with no such part to draw (not read, or an error) it is not shown.
  function drawMachine(part) {
    const el = byId('machine-head'), mod = headMod && headMod.machine;
    if (!el || !mod || typeof mod.draw !== 'function') return;
    const d = part(mod.part);
    el.hidden = !d;
    if (!d) return;
    try {
      mod.draw(el, d, { h, chip, money, post, undoLine, pausedSaid, project: projectOnly, sorted: projectSort, setProject, setProjectSort,
        updatedAt: () => updatedAt, get answerer() { return answerer(); } });
    } catch (e) { el.hidden = true; }
  }
  // When the bar is too narrow for every tile, tiles go by their drop, lowest first; one with none always shows, and
  // the tiles never wrap: the ones that always show are the least room the tiles take. The head line is a grid row
  // that never wraps (app.css), so that least room widens the tiles' column; it never moves them to a line of their own.
  // What a fit measures: each tile's text and which of its parts are hidden, the Restart button beside them, the density
  // and the window's width (fitHead() itself hides whole tiles, so those are left out).
  const fitKey = () => [window.innerWidth, prefs.density, byId('restart') ? byId('restart').hidden : '', ...headView.tiles.map((t) => `${t.a.textContent}|${Array.from(t.a.querySelectorAll('*'), (e) => (e.hidden ? 1 : 0)).join('')}`)].join('\n');
  // A fit lays the head out and measures it: drawHead() and a figure that lands fit it again only when that changed.
  let headQueued = false;  // a drawTabs() and drawHead() wait for the next frame (headSoon())
  function refit() { if (headView && headView.fitted !== fitKey()) fitHead(); }
  function fitHead() {
    if (!headView) return;
    const box = headView.box, tiles = headView.tiles;
    headView.fitted = null;
    tiles.forEach((t) => { t.a.hidden = false; });
    box.style.minWidth = '';
    if (!box.clientWidth) return;  // not laid out (hidden, or no layout at all): fitted at the next drawHead()
    headView.fitted = fitKey();
    const width = new Map(tiles.map((t) => [t, t.a.getBoundingClientRect().width || 0]));
    const sum = (list) => list.reduce((s, t) => s + width.get(t), 0);
    box.style.minWidth = `${Math.ceil(sum(tiles.filter((t) => !t.spec.drop)))}px`;
    const room = box.clientWidth;
    let total = sum(tiles);
    tiles.filter((t) => t.spec.drop).sort((a, b) => a.spec.drop - b.spec.drop).forEach((t) => {
      if (total > room) { total -= width.get(t); t.a.hidden = true; }
    });
    // The sticky head's height, for a box that fits the window under it (the Rules' "What these rules produce", app.css).
    const top = box.closest('.top');
    if (top) doc.documentElement.style.setProperty('--head-h', `${Math.ceil(top.getBoundingClientRect().height)}px`);
  }
  // head.js: {label, tiles: [{key, label, panel, tone, drop, read(part, ctx)}], machine: {part, draw(el, data, ctx)}: the machine head}.
  function head(mod) {
    if (!mod || !Array.isArray(mod.tiles) || !mod.tiles.every((t) => t && typeof t.key === 'string' && typeof t.label === 'string' && typeof t.panel === 'string' && typeof t.read === 'function')) {
      throw new Error('a head tile needs key, label, panel and read');
    }
    headMod = mod;
  }

  // ---- the data refresh ----
  // The mark's three faults: each has a short line under the head that says what is not seen and the one thing to try,
  // and the Restart button is beside the mark then (on a phone, in the Menu beside it).
  const FEED_FAULTS = ['Stale', 'No data', 'Feed stopped'];
  const RESTART = 'press Restart the Board\'s feed, beside the mark above (in Menu on a phone)';
  function faultSaid(word, age) {
    // No data has loaded yet, so the page does not know of a build machine (remote()): it names none.
    if (word === 'No data') return `No data: the page could not load the Board's data, so there is nothing to show. ${RESTART.charAt(0).toUpperCase()}${RESTART.slice(1)}.`;
    if (word === 'Feed stopped') return `Feed stopped: ${remote() ? 'the build machine' : 'the Board\'s feed'} stopped sending new data to this page. ${RESTART.charAt(0).toUpperCase()}${RESTART.slice(1)}.`;
    if (word !== 'Stale') return '';
    if (failedLoads > 1) return `Stale: the last refreshes could not reach ${remote() ? 'the build machine' : 'the Board'}. This is the last data that loaded. If this continues, ${RESTART}.`;
    return `Stale: the newest data is ${age === null ? 'of unknown age' : `${ago(age)} old`}, so what you see can be out of date. If it stays old, ${RESTART}.`;
  }
  function status() {
    const el = byId('status'), up = byId('updated');
    let word = 'Loading', tone = 'quiet';
    const age = updatedAt === null ? null : now() - updatedAt;
    if (alive !== null && !aliveOld && now() - aliveSeenAt > ALIVE_MS) { word = 'Feed stopped'; tone = 'bad'; }
    else if (!loaded) { if (failedLoads) { word = 'No data'; tone = 'bad'; } }
    else if (age === null || age > STALE_MS || failedLoads > 1) { word = 'Stale'; tone = 'warn'; }
    // Live only while the feed sends each change; fresh data read from data.js at each refresh is Polling.
    else if (feedOpen) { word = 'Live'; tone = 'ok'; }
    else { word = 'Polling'; tone = 'ok'; }
    if (el.dataset.word !== word) { el.dataset.word = word; el.replaceChildren(chip(word, tone)); }
    // The restart is in the head only while the mark says the feed has a fault; else it is in the Health panel.
    const rs = byId('restart'), fault = FEED_FAULTS.includes(word);
    // The button takes room in the head line: a head draw queued for this frame fits it then, after its tiles.
    if (rs.hidden === fault) { rs.hidden = !fault; if (!headQueued) refit(); }
    up.textContent = updatedAt === null ? 'never' : `${ago(age)} ago`;
    const banner = byId('banner');
    const text = faultSaid(word, age);
    banner.hidden = !text;
    banner.dataset.tone = tone;
    if (banner.textContent !== text) banner.textContent = text;
  }
  // A page in a background tab draws nothing: the 1 s timer does nothing, and an update is only kept (last) until the
  // page is shown again (shownAgain()).
  function tick() {
    if (doc.hidden) return;
    if (tipAt && !tipAt.isConnected) closeTip();
    byId('clock').textContent = stamp(now(), { seconds: true });
    doc.querySelectorAll('time[data-since]').forEach((el) => {
      const off = Number(el.dataset.offset) || 0;
      const text = ago(now() - Date.parse(el.dataset.since) + off * 1000) + el.dataset.suffix;
      if (el.textContent !== text) el.textContent = text;
    });
    // A panel with a clock of its own moves with it: a part equal to the one drawn last is not drawn again, so a
    // refresh alone would leave it where it was.
    panels.forEach((p, id) => {
      if (p.state !== 'ready' || tabOf(id) !== tab || typeof p.mod.tick !== 'function') return;
      try { p.mod.tick(p.body, p.ctx); } catch (e) { /* the next part that differs draws the panel whole */ }
    });
    status();
    newView();
  }
  function apply(data) {
    if (!data || typeof data !== 'object' || !data.panels || typeof data.panels !== 'object') { failed(); return; }
    loaded = true; failedLoads = 0;
    last = { updatedAt: data.updatedAt, panels: Object.assign({}, data.panels) };
    updatedAt = parse(data.updatedAt);
    title();
    if (doc.hidden) return;
    if (grid) grid.setAttribute('aria-busy', 'false');
    // Only the tab in view is drawn; the other's panels are drawn from this data when it is opened.
    panels.forEach((p, id) => { if (tabOf(id) === tab) draw(p, data.panels[partOf(id)]); });
    drawTabs();
    drawHead();
    arrange();
    status();
  }
  // The Board's browser-tab title has the Overview tab's count of cards stopped for you ("Overview · 2"), so a tab in
  // the background shows it too. The account page (no grid) keeps its own title.
  function title() {
    if (!grid) return;
    const k = attention('overview');
    const t = k > 0 ? `(${k}) Conveyor Board` : 'Conveyor Board';
    if (doc.title !== t) doc.title = t;  // the same title set again is still a change to the page
  }
  // One panel's new part from the live feed: the panels drawn from it are drawn again, and no other (a panel of the
  // other tab is kept for when that tab opens). A page with the head alone (account.html) has no panels: it keeps the change of
  // any part its snapshot holds, so its head tiles follow the feed as the Board's do.
  function applyPanel(msg) {
    if (!loaded || !msg || typeof msg !== 'object') return;
    const t = parse(msg.updatedAt);
    if (t !== null) { updatedAt = t; last.updatedAt = msg.updatedAt; }
    const known = typeof msg.id === 'string'
      && (panels.has(msg.id) || (!grid && Object.prototype.hasOwnProperty.call(last.panels, msg.id)));
    if (known) last.panels[msg.id] = msg.part;
    title();
    if (doc.hidden) return;
    if (known) {
      const ids = idsOf(tab).filter((id) => partOf(id) === msg.id);
      if (ids.length) { ids.forEach((id) => draw(panels.get(id), msg.part)); arrangeSoon(); }
      headSoon();
    }
    status();
  }
  // The server sends one event a changed part of a version: the tabs and the head are drawn at most once a frame, after
  // all the events that came before that frame. An event after the draw queues one more draw, of the same version or not.
  function headSoon() {
    if (headQueued) return;
    headQueued = true;
    const run = () => { headQueued = false; drawTabs(); drawHead(); };
    if (typeof window.requestAnimationFrame === 'function') window.requestAnimationFrame(run); else run();
  }
  // The feed opened or closed: the panel that says how live it is (Health, the one panel that reads ctx.feed()) is
  // drawn again from the part it has; the others are left as they are.
  function feedChanged(open) {
    if (feedOpen === open) return;
    feedOpen = open;
    const hp = panels.get('health');
    // Drawn anew when it is next drawn: now, when its tab opens, or when the page is shown again (shownAgain()).
    if (hp) hp.json = undefined;
    if (doc.hidden) return;
    status();  // Live or Polling
    if (!loaded || !hp) return;
    if (tabOf('health') !== tab) return;
    draw(hp, last.panels[partOf('health')]);
    arrangeSoon();
  }
  // The page shown again: drawn once from what it kept while hidden. Only a panel whose part changed while hidden is
  // drawn again (draw() leaves one with the part it drew as it is); a refresh skipped while hidden runs now, once.
  function shownAgain() {
    if (doc.hidden) return;
    if (grid && loaded) grid.setAttribute('aria-busy', 'false');
    if (last) idsOf(tab).forEach((id) => draw(panels.get(id), last.panels[partOf(id)]));
    drawHead();
    arrangeSoon();
    drawTabs();
    if (missed) { missed = false; aliveOld = true; refresh(); }
    tick();
  }
  // True when the page asked for the feed; false when this browser or address has none.
  function follow() {
    if (typeof window.EventSource !== 'function' || !/^https?:$/.test(window.location.protocol)) return false;
    const es = new window.EventSource('events');
    feed = es;
    const read = (fn) => (e) => { let m; try { m = JSON.parse(e.data); } catch (err) { return; } fn(m); };
    es.addEventListener('open', () => feedChanged(true));
    es.addEventListener('snapshot', read((m) => { feedSeq += 1; feedChanged(true); apply(m); }));
    es.addEventListener('panel', read(applyPanel));
    es.addEventListener('updated', read(applyPanel));
    es.addEventListener('error', () => {
      feedChanged(false);
      // The feed did not open at start: the page draws from data.js now, not at the next refresh.
      if (!loaded && !dataAsked) readData();
      // A feed the server refused (logged out, too many followers) is closed for good: data.js is read meanwhile,
      // which also finds a lost login, and the feed is asked for again later.
      if (es.readyState === 2 && feed === es) { feed = null; window.setTimeout(follow, RETRY_MS); }
    });
    return true;
  }
  function failed() {
    failedLoads += 1;
    // Before any data, a page that cannot load says so in every panel; after, the last snapshot stays.
    if (!loaded) panels.forEach((p, id) => { if (tabOf(id) === tab) draw(p, { error: NOTHING, data: null }); });
    if (!loaded) arrange();
    if (/^https?:$/.test(window.location.protocol) && typeof window.fetch === 'function') window.fetch(`alive.js?${now()}`).then(goLogin, () => {});
    status();
  }
  // The same address on each read: the server's ETag makes the browser's revalidation a 304 while the file is unchanged.
  function script(name, onload, onerror) {
    const s = doc.createElement('script');
    s.src = name;
    s.addEventListener('load', () => { s.remove(); onload(); });
    s.addEventListener('error', () => { s.remove(); if (onerror) onerror(); });
    doc.head.append(s);
  }
  function readData() {
    dataAsked = true;
    window.DASH = undefined;
    // A data.js that arrives after the feed opened, or after a feed snapshot, is older than what the feed drew: it is
    // dropped, so it never overwrites panels the feed's later changes do not redraw.
    const seq = feedSeq;
    script('data.js', () => { if (!feedOpen && seq === feedSeq) apply(window.DASH); }, failed);
  }
  // waitFeed: the page's first refresh, with the feed just asked for: data.js is not read, as the feed's first
  // message has the whole of it; follow's error handler reads it if the feed does not open.
  // A hidden page reads nothing (the feed stays open): missed asks shownAgain() for one refresh when it is shown.
  // aliveOld: the heartbeat read before the page was hidden is old, not stopped: status() does not judge the feed by it
  // until the refresh run when shown has read alive.js again (or failed to).
  let missed = false;
  function refresh(waitFeed = false) {
    if (doc.hidden) { missed = true; return; }
    if (!feedOpen && !waitFeed) readData();
    script('alive.js', () => {
      aliveOld = false;
      const a = window.DASH_ALIVE;
      if (!a || typeof a !== 'object' || parse(a.at) === null) return;
      if (alive === null || a.at !== alive.at) aliveSeenAt = now();
      alive = a;
      if (typeof a.view === 'string') { if (view === null) view = a.view; else if (a.view !== view) { newer = true; newView(); } }
    }, () => { aliveOld = false; });
  }
  // A page left open picks up a newer copy of itself, but only when the owner loses nothing by it: no focused field,
  // no field with text the owner typed, no two-click button or question that waits for its second click, no request
  // in flight. Until then the head says "New version. Reload" beside the status mark; the page reloads once it is idle
  // (looked at on each tick and each keystroke) or hidden.
  let newer = false, reloading = false;
  // A field the owner typed in, by its panel, label and place among the panel's fields of that label (each project's
  // version in Release has the same label): a panel draws a field again (with the draft it keeps) as a new element in
  // the same place, and the new one holds the same draft. A field typed in holds the reload only while it has text.
  const typed = new Set();
  const TEXT = ['text', 'search', 'email', 'url', 'tel', 'password', 'number'];
  const textField = (el) => el.tagName === 'TEXTAREA' || (el.tagName === 'INPUT' && TEXT.includes(el.type));
  const fieldName = (f) => `${f.tagName}\n${f.getAttribute('aria-label') || f.name || f.placeholder || ''}`;
  const fieldKey = (f) => {
    const p = f.closest('[data-panel]'), name = fieldName(f);
    const same = p ? Array.from(p.querySelectorAll('input, textarea')).filter((x) => fieldName(x) === name) : [f];
    return `${p ? p.dataset.panel : ''}\n${name}\n${same.indexOf(f)}`;
  };
  // In the page, and in the panels of the other tabs (out of the page, with what the owner left in them).
  const everywhere = (sel) => [doc, ...Array.from(panels.values(), (p) => p.el).filter((el) => el && !el.isConnected)]
    .flatMap((root) => Array.from(root.querySelectorAll(sel)));
  // Each request the page sends, from the send until its answer's body is read: a reload in between loses the answer.
  // Panels and the Account page call window.fetch themselves, so it is window.fetch that counts them.
  const asks = new Set();
  if (typeof window.fetch === 'function') {
    const fetch0 = window.fetch;
    window.fetch = function (...args) {
      const ask = { answered: false, reading: 0 };
      asks.add(ask);
      return fetch0.apply(this, args).then((r) => { answered(ask, r); return r; }, (e) => { asks.delete(ask); throw e; });
    };
  }
  function answered(ask, r) {
    ask.answered = true;
    if (!r || typeof r !== 'object') return;
    ['json', 'text', 'blob', 'arrayBuffer', 'formData'].forEach((m) => {
      const read = r[m];
      if (typeof read !== 'function') return;
      r[m] = (...a) => {
        ask.reading += 1;
        const p = read.apply(r, a), end = () => { ask.reading -= 1; };
        Promise.resolve(p).then(end, end);
        return p;
      };
    });
  }
  // A caller reads an answer's body in the then() of the answer, before the next event or timer, where busy() runs: an
  // answer whose body no read has started by then is done.
  function inFlight() {
    asks.forEach((a) => { if (a.answered && a.reading === 0) asks.delete(a); });
    return asks.size > 0;
  }
  function busy() {
    const a = doc.activeElement;
    if (a && a.matches('input, textarea, select')) return true;
    if (everywhere('input, textarea').some((f) => f.value.trim() !== '' && typed.has(fieldKey(f)))) return true;
    // Each two-click button while it waits for its second click, and each question open for a confirm, has data-armed.
    if (everywhere('[data-armed]').length) return true;
    return inFlight();
  }
  function reload() { reloading = true; window.location.reload(); }
  function newView() {
    if (!newer || reloading) return;
    if (doc.hidden || !busy()) { reload(); return; }
    const note = byId('new-view');
    if (note.hidden) { note.hidden = false; fitHead(); }
  }
  function watchView() {
    byId('reload').addEventListener('click', reload);
    // Before the field's own handler, which may draw it again as a new element out of its panel.
    doc.addEventListener('input', (e) => { if (textField(e.target) && e.target.value.trim() !== '') typed.add(fieldKey(e.target)); newView(); }, true);
    doc.addEventListener('visibilitychange', newView);
  }
  // The Board's feed (the collector) restarted, from the head or a panel's button (restartHere()): what the host
  // answered goes under the head, and to the promise returned (the panel shows it beside its button).
  const asking = () => `Asking ${remote() ? 'the build machine' : 'the Board'} to restart the Board's feed…`;
  function restart() {
    const note = byId('restart-note');
    const who = remote() ? 'the build machine' : 'the Board', Who = remote() ? 'The build machine' : 'The Board';
    note.textContent = asking();
    return post('restart', {}).then((r) => r.text().then((t) => (r.ok ? 'Restarting. The page catches up in about a minute.' : `Not restarted: ${String(t).trim() || `${who} answered ${r.status}`}`)), () => `${Who} did not answer. Make sure that it is on. Then press Restart again.`)
      .then((text) => { note.textContent = text; return text; });
  }
  function watchMotion() {
    const root = doc.documentElement;
    const mq = typeof window.matchMedia === 'function' ? window.matchMedia('(prefers-reduced-motion: reduce)') : null;
    const set = () => { root.dataset.motion = mq && mq.matches ? 'off' : 'on'; };
    set();
    if (mq && mq.addEventListener) mq.addEventListener('change', set);
  }

  // A panel module: {id, title, size (small, wide or full), tab (overview, belt3d, control or rules: the one tab it is drawn on), rows
  // (its default length: how many rows it shows, or 'all'), rowSelector (what one of its rows is; default '.rows > li'),
  // render, empty, error, isEmpty, and optionally count, tick, same and attention(data) (how many things on it need
  // the owner: the count on its tab), and projects (true: it lists rows of every project, each naming its repo, so
  // the machine head's filter and sort apply to its part: shownData), and declinedOf (the address parameter that cuts
  // it to the declined findings of one card: a review's declined count opens it there, judged()), and phoneFolded
  // (true: a report panel that starts collapsed to its heading on a phone, until the owner opens it: defaults()), and
  // older(live, history) (its live part with the older entries of the history laid in: withOlder())}, and part (the id
  // of the panel on the list whose part it is drawn from: one file's part shown as more than one panel, such as the
  // Rules tab's; default its own id), and widths (the sizes it can take, its size among them; default every size:
  // the head's width control offers only these, and a kept layout's other width is read as its default: tidy()).
  function panel(mod) {
    const need = ['render', 'empty', 'error', 'isEmpty'];
    if (!mod || typeof mod.id !== 'string' || typeof mod.title !== 'string' || !need.every((k) => typeof mod[k] === 'function')) throw new Error('a panel needs id, title, render, empty, error and isEmpty');
    modules.set(mod.id, Object.assign({}, mod, {
      part: typeof mod.part === 'string' && mod.part ? mod.part : mod.id,
      size: SIZES.includes(mod.size) ? mod.size : 'small',
      tab: TABS.some((x) => x[0] === mod.tab) ? mod.tab : 'overview',
      rows: lengthOk(mod.rows) ? mod.rows : ROWS,
      statedRows: lengthOk(mod.rows),
      widths: Array.isArray(mod.widths) && SIZES.includes(mod.size) && mod.widths.includes(mod.size) ? SIZES.filter((s) => mod.widths.includes(s)) : SIZES,
    }));
  }
  // A list entry whose file did not load, or did not register, still gets its place and says what is wrong.
  function missing(id) {
    // What to try in the text; the file that did not load on tap.
    const block = (el) => {
      el.replaceChildren(stateBlock('error', 'This panel is missing', 'Its code did not load. Reload the page to load it again.'));
      tip(el.querySelector('.state-detail'), details(`panels/${id}.js did not load.`));
    };
    return { id, title: id, size: 'small', tab: 'overview', rows: 'all', statedRows: true, isEmpty: () => false, render: block, empty: block, error: block };
  }
  // A page with the Board's head and no panels (account.html): the same tiles, status mark, times and restart, from the
  // same data, and the tabs as links to the Board. A tile links to its panel on the Board.
  function startHead() {
    watchMotion();
    readLayout();
    if (prefs.theme !== 'system') doc.documentElement.dataset.theme = prefs.theme;
    const bar = byId('tabs');
    if (bar) {
      const links = h('div', 'tabs-list');
      TABS.forEach(([t, name]) => { const a = h('a', 'tab'); a.href = `index.html?tab=${t}`; a.dataset.tab = t; a.append(h('span', 'tab-name', name)); links.append(a); });
      bar.append(links);
    }
    buildHead();
    wireMenu();
    window.addEventListener('resize', fitHead);
    // A restart costs the collector's time: it asks for a second click, as on the Board.
    twice(byId('restart'), 'spend', 'Click again to restart the Board\'s feed', restart);
    tick();
    window.setInterval(tick, 1000);
    doc.addEventListener('visibilitychange', shownAgain);
    watchView();
    refresh(follow());
    window.setInterval(() => refresh(), REFRESH_MS);
  }
  function start() {
    if (!byId('grid')) { startHead(); return; }
    watchMotion();
    grid = byId('grid');
    (Array.isArray(window.DASH_PANELS) ? window.DASH_PANELS : []).forEach((id) => { if (!modules.has(id)) modules.set(id, missing(id)); });
    // The list decides the default order, whatever order the files loaded in. The panels drawn from one listed part
    // take its place on the list, in the order its file registered them; one drawn from a part not on the list is not shown.
    const ordered = (window.DASH_PANELS || []).flatMap((part) => Array.from(modules).filter(([id]) => partOf(id) === part));
    modules.clear();
    ordered.forEach(([id, mod]) => modules.set(id, mod));
    readLayout();
    // A 24-hour Time this browser kept before the Board sent any is sent once. It is not sent on each visit: the kept
    // Time is also the default that any other change saves, and would undo a Time set later in another browser.
    let sent = null;
    try { sent = window.localStorage.getItem(TIME_SENT_KEY); } catch (e) { sent = null; }
    if (!sent && prefs.time !== PREFS0.time) sendTime();
    let kept = null;
    try { kept = window.localStorage.getItem(TAB_KEY); } catch (e) { kept = null; }
    tab = tabFromAddress() || (TABS.some((x) => x[0] === kept) ? kept : 'overview');
    address(tab, false);
    grid.replaceChildren();
    grid.classList.add('fresh');
    modules.forEach((mod, id) => panels.set(id, frame(mod)));
    wireCustomize();
    wireMenu();
    wireTips();
    wireKeys();
    applyLayout();
    buildHead();
    // Back and Forward may bring another project, filter or sort with the tab: every panel is drawn again from the
    // data it has, as a pick does.
    window.addEventListener('popstate', () => {
      const t = tabFromAddress(), was = tab;
      panels.forEach((p) => { p.json = undefined; });
      if (t) setTab(t, false);
      if (tab === was && last) { idsOf(tab).forEach((id) => draw(panels.get(id), last.panels[partOf(id)])); arrangeSoon(); }
      drawHead();
    });
    window.addEventListener('resize', () => { fitHead(); arrangeSoon(); });
    // A restart costs the collector's time: it asks for a second click.
    twice(byId('restart'), 'spend', 'Click again to restart the Board\'s feed', restart);
    tick();
    window.setInterval(tick, 1000);
    doc.addEventListener('visibilitychange', shownAgain);
    watchView();
    refresh(follow());
    window.setInterval(() => refresh(), REFRESH_MS);
  }

  window.DASH_APP = { panel, head, overlay, start, pack, joined, text: findingText, stamp, form };
}());
