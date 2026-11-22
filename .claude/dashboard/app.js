// SPDX-License-Identifier: Apache-2.0
// The Conveyor dashboard's core: the panel frame, the layout the owner arranges, motion and the data refresh, with
// its parts in parts/app-*.js (core(), below).
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
  // What app.js uses of its parts (parts/app-*.js), bound as each loads (core).
  let PAGE, address, answerer, applyLayout, arrangeSoon, attention, behind, buildHead, change, clip, clock, depPicked,
    depRef, details, draw, drawHead, dur, earlierTip, failure, failureLine, failureShort, findingText, findings,
    fitHead, fixNow, flip, follow, fresh, goTo, idsOf, inRow, issueLink, joined, judged, keep, keptGet, keptScope,
    lay, lengthDrag, lengthOk, list, loopEnd, machineWord, modelName, move, output, overlay, pack, pageOf,
    panelFaults, panelHref, param, params, partOf, pickRepo, project, projectSort, readLayout, refresh, refusal,
    restart, restartHere, retryText, reviewChip, rowsAbove, save, say, sendTime, setLength, setTab, shownAgain, since,
    skeleton, stateBlock, survived, tabFromAddress, tabOf, tag, testProgress, tick, tip, toggle, took, tool, track,
    trackDetail, trackShell, unread, verdictSaid, wantOf, watchMotion, watchView, when, widthsOf, wireTips;

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
  function money(v) {
    if (typeof v !== 'number' || !Number.isFinite(v)) return 'not priced';
    return `$${v.toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',')}`;
  }
  // The Time and Date set in Customize, as one text.
  function form() { const p = prefs || prefsOf(stored()); return `${p.time} ${p.date}`; }
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
    if (state === 'paused by guard') return `Paused by the weekly-limit guard${num(guard) ? ` at ${guard}%` : ''}. Raise or turn off "Weekly pause" in Rules to pick again.`;
    if (state === 'stopped' && name) return `Stopped by Stop now: the cards in progress went back to the queue. ${resume} to pick again.`;
    return null;
  }

  // ---- a card's step track: Build, Review, Fix, Test, Land, Push ----
  // Each step is done (a check mark and the time it took), now (lit, its running time), to come (muted), skipped (a
  // dash) or failed (a cross, and why); never colour alone. The join before a step fills once the card has reached
  // it, so the track reads as one bar of progress from left to right, by steps, never by time.
  const STEP_NAMES = ['Build', 'Review', 'Fix', 'Test', 'Land', 'Push'];

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
  // The page's only writes: an answer to an open decision, a control action, the collector restart, the Time set in
  // Customize, and the Dismiss, preview and filing of a plugin problem, all to its own host.
  function post(path, body) {
    return window.fetch(path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }).then(goLogin);
  }
  function stored() {
    let s;
    try { s = JSON.parse(window.localStorage.getItem(STORE_KEY)); } catch (e) { s = null; }
    return s && typeof s === 'object' ? s : {};
  }
  const prefsOf = (s) => ({ density: DENSITIES.includes(s.density) ? s.density : PREFS0.density, theme: THEMES.includes(s.theme) ? s.theme : PREFS0.theme,
    time: CLOCKS.includes(s.time) ? s.time : PREFS0.time, date: DATES.includes(s.date) ? s.date : PREFS0.date });
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
  // On a phone the tab list scrolls sideways: the selected tab is brought into view inside the list (never the page, so
  // a wide screen, where all six fit, does not move). Again only when the tab, or the list's width or the room it has,
  // changed (a count appearing, a turned phone), so a refresh does not undo the reader's own scroll.
  let shownTab = '';
  function showTab() {
    const list = document.querySelector('#tabs .tabs-list'), b = byId(`tab-${tab}`);
    if (!list || !b) return;
    const key = `${tab}|${list.scrollWidth}|${list.clientWidth}`;
    if (key === shownTab) return;
    shownTab = key;
    const l = list.getBoundingClientRect(), r = b.getBoundingClientRect();
    if (r.right > l.right) list.scrollLeft += r.right - l.right;
    if (r.left < l.left) list.scrollLeft -= l.left - r.left;
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
    showTab();  // after the counts: they change the tabs' widths
  }

  // ---- words a phone can open ----
  // A phone shows no hover text. An item that explains itself only there (a step of a card's track, a fix's reason, a
  // line cut to fit, a figure's mark) carries its words in data-tip as well as its title: a tap on it opens them in a
  // small popover under it, and a second tap, a tap elsewhere or Escape closes it. A tap on such an item inside a link
  // opens its words, not the link. An item drawn again in its place closes its popover (tick()); an item kept in its
  // place and given new words shows them in its open popover, and one left with none (empty text) closes it (tip()).
  // The popover itself is drawn in parts/app-tabs.js.
  let tipAt = null;  // the item whose words are open
  // ---- one panel's frame (its tools, skeleton and states: parts/app-tabs.js) ----
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
    const p = { mod, el, body, count, tools, foot, rowsNote, showAll, grip, json: undefined, pick: '', state: 'loading', renders: 0, nums: new Map(), natural: 0 };
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
      h, chip, icon, tip, unread,
      // Call before a panel draws a part again; the function it returns puts the keyboard back on a name drawn anew
      // (no scroll). Focus opens a lint command's tip, so a tip the reader had closed (Escape) is shut again.
      focusKeeper: () => {
        const open = !!app.tipAt && app.tipAt === doc.activeElement;
        return (el) => { el.focus({ preventScroll: true }); if (!open) app.closeTip(); };
      },
      get retry() { return retryText(); }, restartButton: restartHere, faults: panelFaults, get machine() { return machineWord(); }, get answerer() { return answerer(); }, details, since, clock, when, stamp, dur, took, money, modelName, findings, survived, loopEnd, judged, reviewChip, verdictSaid, output, issueLink, depRef, list, post, fresh, motion, state: stateBlock, track, trackDetail, trackShell, earlierTip, testProgress, fixNow,
      param, params, pickRepo, project, now, tag, behind, setTab, restart, goTo, panelHref: (id) => panelHref(id), failure, failureLine, failureShort, twice, undoLine, text: findingText,
      pausedSaid, refusal, depPicked,
      // Whether the lists are sorted by project (the machine head's sort): a panel that orders a list itself keeps each
      // project's rows together then.
      sorted: projectSort,
      // picking(): true while this panel shows the project choice, not its data (Show at every project, a panel that
      // holds one project): a panel's own draw (a timer, a reply that came back) draws nothing then.
      picking: () => app.needsPick(mod),
      // whole: whether this draw is to draw the panel whole (a new time format, project or model name), not only what
      // changed in its part: a panel that keeps its rows as they were draws each again then.
      get whole() { return p.whole === true; },
      // hours(): the Time set in Customize, 12-hour or 24-hour.
      hours: () => (prefs || prefsOf(stored())).time,
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
  // Customize's sheet, opened and closed here; what it lists is drawn by drawCustomize() (parts/app-feed.js).
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
  // head.js: {label, tiles: [{key, label, panel, tone, drop, read(part, ctx)}], machine: {part, draw(el, data, ctx)}: the machine head}.
  function head(mod) {
    if (!mod || !Array.isArray(mod.tiles) || !mod.tiles.every((t) => t && typeof t.key === 'string' && typeof t.label === 'string' && typeof t.panel === 'string' && typeof t.read === 'function')) {
      throw new Error('a head tile needs key, label, panel and read');
    }
    headMod = mod;
  }
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
    window.addEventListener('resize', () => { fitHead(); showTab(); arrangeSoon(); });
    // A restart costs the collector's time: it asks for a second click.
    twice(byId('restart'), 'spend', 'Click again to restart the Board\'s feed', restart);
    tick();
    window.setInterval(tick, 1000);
    doc.addEventListener('visibilitychange', shownAgain);
    watchView();
    refresh(follow());
    window.setInterval(() => refresh(), REFRESH_MS);
  }

  // The parts of app.js, in the order boot.js loads them, before the panel files. Each part calls core() as it loads,
  // with a function that is given `app`: app.js's names, its state through getters and setters, and what the parts
  // before it gave back. What the function gives back is added to `app` and bound to app.js's names above; app.bind
  // binds a part's own names from `app` at once and again each time another part loads, so by start() every name is bound.
  const PARTS = ['parts/app-text.js', 'parts/app-track.js', 'parts/app-layout.js', 'parts/app-tabs.js', 'parts/app-feed.js'];
  const binds = [];
  const app = { ALIVE_MS, CLOCKS, DATES, DENSITIES, FOLD_MS, MOTION_MS, NOTHING, PREFS0, RETRY_MS, ROW_PX, ROW_SEL,
    SEEN_KEY, SIZES, SNAP, STALE_MS, STEP_NAMES, STORE_KEY, TABS, TAB_KEY, THEMES, TIME_SENT_KEY, ago, asks, byId,
    chip, counter, doc, drawTabs, form, goLogin, h, icon, modules, money, motion, now, num, panels, parse, pausedSaid,
    post, prefsOf, stamp, stored, twice, undoLine, bind(f) { binds.push(f); f(); } };
  Object.defineProperty(app, 'last', { get: () => last, set: (v) => { last = v; } });
  Object.defineProperty(app, 'layouts', { get: () => layouts, set: (v) => { layouts = v; } });
  Object.defineProperty(app, 'prefs', { get: () => prefs, set: (v) => { prefs = v; } });
  Object.defineProperty(app, 'tab', { get: () => tab, set: (v) => { tab = v; } });
  Object.defineProperty(app, 'grid', { get: () => grid });
  Object.defineProperty(app, 'placed', { get: () => placed, set: (v) => { placed = v; } });
  Object.defineProperty(app, 'loaded', { get: () => loaded, set: (v) => { loaded = v; } });
  Object.defineProperty(app, 'arranging', { get: () => arranging, set: (v) => { arranging = v; } });
  Object.defineProperty(app, 'tipAt', { get: () => tipAt, set: (v) => { tipAt = v; } });
  Object.defineProperty(app, 'queued', { get: () => queued, set: (v) => { queued = v; } });
  Object.defineProperty(app, 'headMod', { get: () => headMod });
  Object.defineProperty(app, 'failedLoads', { get: () => failedLoads, set: (v) => { failedLoads = v; } });
  Object.defineProperty(app, 'headView', { get: () => headView, set: (v) => { headView = v; } });
  Object.defineProperty(app, 'updatedAt', { get: () => updatedAt, set: (v) => { updatedAt = v; } });
  Object.defineProperty(app, 'alive', { get: () => alive, set: (v) => { alive = v; } });
  Object.defineProperty(app, 'aliveSeenAt', { get: () => aliveSeenAt, set: (v) => { aliveSeenAt = v; } });
  Object.defineProperty(app, 'aliveOld', { get: () => aliveOld, set: (v) => { aliveOld = v; } });
  Object.defineProperty(app, 'feedOpen', { get: () => feedOpen, set: (v) => { feedOpen = v; } });
  Object.defineProperty(app, 'feed', { get: () => feed, set: (v) => { feed = v; } });
  Object.defineProperty(app, 'feedSeq', { get: () => feedSeq, set: (v) => { feedSeq = v; } });
  Object.defineProperty(app, 'dataAsked', { get: () => dataAsked, set: (v) => { dataAsked = v; } });
  Object.defineProperty(app, 'view', { get: () => view, set: (v) => { view = v; } });
  function core(fn) {
    Object.defineProperties(app, Object.getOwnPropertyDescriptors(fn(app)));
    ({ PAGE, address, answerer, applyLayout, arrangeSoon, attention, behind, buildHead, change, clip, clock,
      depPicked, depRef, details, draw, drawHead, dur, earlierTip, failure, failureLine, failureShort, findingText,
      findings, fitHead, fixNow, flip, follow, fresh, goTo, idsOf, inRow, issueLink, joined, judged, keep, keptGet,
      keptScope, lay, lengthDrag, lengthOk, list, loopEnd, machineWord, modelName, move, output, overlay, pack,
      pageOf, panelFaults, panelHref, param, params, partOf, pickRepo, project, projectSort, readLayout, refresh,
      refusal, restart, restartHere, retryText, reviewChip, rowsAbove, save, say, sendTime, setLength, setTab,
      shownAgain, since, skeleton, stateBlock, survived, tabFromAddress, tabOf, tag, testProgress, tick, tip, toggle,
      took, tool, track, trackDetail, trackShell, unread, verdictSaid, wantOf, watchMotion, watchView, when, widthsOf,
      wireTips } = app);
    binds.forEach((f) => f());
  }
  // A panel file's parts (parts/<file>-*.js, panels/index.js DASH_PARTS): part() keeps each by its name as it loads,
  // and use() runs it with what the panel file shares. A part that did not load stops the panel file, which names it.
  const panelParts = new Map();
  function part(name, fn) { panelParts.set(name, fn); }
  function use(name, shared) {
    if (!panelParts.has(name)) throw new Error(`parts/${name}.js did not load`);
    return panelParts.get(name)(shared);
  }
  window.DASH_APP = { panel, head, start, core, part, use, parts: PARTS, stamp, form, get overlay() { return overlay; },
    get pack() { return pack; }, get joined() { return joined; }, get text() { return findingText; } };
}());
