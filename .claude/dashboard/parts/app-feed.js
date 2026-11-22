// SPDX-License-Identifier: Apache-2.0
// A panel's draw, Customize's list, the head line's tiles, the machine head, the overlays, the data refresh (data.js
// and the live feed) and a newer copy of the page. Part of app.js, which hands it `app` (its names, and its state
// through getters and setters) as it loads (DASH_APP.core); boot.js loads it before the panels.
(() => {
  'use strict';
  // What this part uses of app.js and of its other parts, each bound as it loads (app.bind, at the end).
  let app, ALIVE_MS, CLOCKS, DATES, DENSITIES, NOTHING, RETRY_MS, STALE_MS, TABS, THEMES, ago, answerer, arrange,
    arrangeSoon, asks, attention, byId, change, chip, closeTip, counter, depPicked, depRef, details, doc, drawTabs,
    faultsChanged, goLogin, h, hideable, histDue, icon, idsOf, issueLink, lay, modules, money, motion, namesKey, now,
    num, olderShown, panels, param, params, parse, partOf, pausedSaid, post, project, projectOnly, projectSort,
    readHistory, refusal, remote, reset, restartHere, retitle, retryText, say, setProject, setProjectSort, setTab,
    pickBlock, pickKey, shownData, since, stamp, stateBlock, tabOf, tip, toggle, undoLine, unread, when, withOlder;
  const bindNames = () => ({ ALIVE_MS, CLOCKS, DATES, DENSITIES, NOTHING, RETRY_MS, STALE_MS, TABS, THEMES, ago, answerer,
    arrange, arrangeSoon, asks, attention, byId, change, chip, closeTip, counter, depPicked, depRef, details, doc,
    drawTabs, faultsChanged, goLogin, h, hideable, histDue, icon, idsOf, issueLink, lay, modules, money, motion,
    namesKey, now, num, olderShown, panels, param, params, parse, partOf, pausedSaid, post, project, projectOnly,
    projectSort, readHistory, refusal, remote, reset, restartHere, retitle, retryText, say, setProject,
    setProjectSort, setTab, pickBlock, pickKey, shownData, since, stamp, stateBlock, tabOf, tip, toggle, undoLine, unread, when,
    withOlder } = app);
  // True when panel p was drawn last from this same part: a panel with same() is then told it came again (draw).
  function drawnFrom(p, part) {
    // A panel with older entries asks for the history when it is time to read it again, and is drawn again only when a
    // newer history has come; not whole (ctx.whole), so a panel that draws its rows with ctx.list keeps the rows that
    // did not change.
    if (typeof p.mod.older === 'function' && histDue() && olderShown()) readHistory();
    const older = typeof p.mod.older === 'function' && p.hist !== app.histVer;
    p.hist = app.histVer;
    // The model names (modelName) and the project choice (pickKey: another part's project list decides it) are part of
    // what a panel shows: a new alias or name, or a choice that changed, draws it again, whole.
    const names = namesKey() + pickKey(p.mod), json = JSON.stringify(part === undefined ? null : part) + names;
    if (p.json === json && !older) {
      if (p.state === 'ready' && !p.note && typeof p.mod.same === 'function') {
        try { p.mod.same(p.body, shownData(p.mod, part.data), p.ctx); } catch { /* the next part that differs draws the panel whole */ }
      }
      return true;
    }
    // Drawn whole (ctx.whole): the first draw, asked for (redrawAll, ctx.redraw), or the model names changed, whatever
    // else changed too.
    p.whole = p.json === undefined || p.names !== names;
    p.json = json; p.names = names;
    return false;
  }
  // What is wrong with a panel's part, {state, message, raw}: the state 'error' with what the panel says, or 'ready'.
  function partFault(part) {
    const from = remote() ? 'the build machine' : 'Conveyor', From = remote() ? 'The build machine' : 'Conveyor';
    if (!part || typeof part !== 'object') return { state: 'error', message: `${From} sent nothing for this panel, so the Board cannot show it. If this continues, press Restart the Board's feed, below.`, raw: '' };
    if (typeof part.error === 'string' && part.error) return { state: 'error', message: `The Board could not get this panel from ${from}, so it cannot show it. ${retryText()}`, raw: part.error };
    if (!part.data || typeof part.data !== 'object') return { state: 'error', message: `${From} sent no data for this panel, so the Board cannot show it. If this continues, press Restart the Board's feed, below.`, raw: '' };
    return { state: 'ready', message: null, raw: '' };
  }
  // A panel that shows data keeps it through a failed read, with a short note above it: true when it did. Emptied, it
  // moved all below it up, and its next good read built it anew: each open "Every step", output and inner scroll was
  // closed or reset.
  function keptThrough(p, state, raw) {
    if (p.note) { p.note.remove(); p.note = null; }
    if (state !== 'error' || p.state !== 'ready') return false;
    p.note = h('div', 'panel-note');
    p.note.setAttribute('role', 'status');
    p.note.append(unread(`The Board could not read ${p.mod.title} just now, so it shows what it read last. If this continues, press Restart the Board's feed, below.`, raw), restartHere());
    p.body.prepend(p.note);
    if (p.mod.id !== 'health') faultsChanged();
    return true;
  }
  // Draws one panel from its own part. A part equal to the one drawn last leaves the panel untouched, but a panel
  // with same(body, data, ctx) is told that part came again (the Board weighs a snapshot by when it was begun,
  // so one equal to a snapshot it turned away is still news to it). A panel that throws shows its own error and takes
  // no other panel with it. It does not cut the panel to its length: each caller runs arrange() or arrangeSoon() after
  // it, which cuts every panel of the tab in one read round and one write round (a cut here laid the page out once a panel).
  function draw(p, part) {
    if (drawnFrom(p, part)) return;
    p.renders += 1;
    p.el.dataset.renders = String(p.renders);
    const fault = partFault(part);
    if (keptThrough(p, fault.state, fault.raw)) return;
    const state = drawBody(p, part, fault);
    retitle(p.body);
    p.state = state;
    p.el.dataset.state = state;
    if (p.mod.id !== 'health') faultsChanged();
  }
  // The project choice of panel p, built once for each pickKey (see drawBody); the panel's state is then 'empty'.
  function drawPick(p, pick) {
    if (p.pick !== pick) {
      p.pick = '';
      p.body.replaceChildren(pickBlock(p.mod)); p.ctx.headActs(); p.ctx.title(null);
      p.count.textContent = ''; p.count.hidden = true;
      p.pick = pick;
    }
    return 'empty';
  }
  // Draws panel p's body for its part and what is wrong with it (partFault); gives back the state it is drawn in: the
  // state 'error' when the panel threw.
  function drawBody(p, part, { state, message, raw }) {
    const mod = p.mod;
    try {
      // A panel that holds one project, with every project shown: the project choice, no project's data. Its state is
      // 'empty', so the next draw of a project builds it whole. The choice is built once for each pickKey: built again
      // for each new snapshot (its read time differs), it would take the keyboard focus off the button that has it.
      const pick = pickKey(mod);
      if (state === 'ready' && pick) return drawPick(p, pick);
      p.pick = '';
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
    return state;
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
    set.append(h('legend', null, `Panels of ${TABS.find((x) => x[0] === app.tab)[1]}`));
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
      choice('Density', DENSITIES, app.prefs.density, (v) => change(() => { app.prefs.density = v; })),
      choice('Theme', THEMES, app.prefs.theme, (v) => change(() => { app.prefs.theme = v; })),
      choice('Time', CLOCKS, app.prefs.time, (v) => change(() => { app.prefs.time = v; })),
      choice('Date', DATES, app.prefs.date, (v) => change(() => { app.prefs.date = v; })), row);
    if (held) { const again = byId(held) || box.querySelector(`input[value="${held}"]`); if (again) again.focus({ preventScroll: true }); }
    const n = l.hidden.length;
    open.querySelector('.label').textContent = n ? `Customize (${n} hidden)` : 'Customize';
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
    if (!box || !app.headMod) { if (box) box.hidden = true; return; }
    box.setAttribute('aria-label', app.headMod.label || 'At a glance');
    const tiles = app.headMod.tiles.map((spec) => {
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
    app.headView = { box, tiles, nums: new Map() };
    drawHead();
  }
  let drawingHead = false;
  // One tile t of the head line, from the panels' parts (part(id): a panel's data, or null).
  function drawTile(t, part) {
    let r;
    try { r = t.spec.read(part, { money }) || {}; } catch { r = {}; }
    // A count moves through whole numbers only: the motion's in-between values are never shown as fractions.
    const known = num(r.value), fmt = typeof r.fmt === 'function' ? r.fmt : (v) => String(Math.round(v));
    const text = known ? fmt(r.value) : DASH;
    if (app.headView.nums.get(t.spec.key) !== (known ? r.value : null) || t.value.textContent === '') {
      // The fit below measures the figure the count starts from; one that lands wider is fitted again when it lands.
      // With no motion the count lands at once, before the other tiles are written: the fit at the end measures it.
      t.value.replaceChildren(counter(app.headView.nums, t.spec.key, known ? r.value : null, (v) => (num(v) ? fmt(v) : DASH), () => { if (!drawingHead) refit(); }));
    }
    t.sub.textContent = known && r.sub ? ` ${r.sub}` : '';
    t.sub.hidden = !t.sub.textContent;
    const tone = known ? r.tone || t.spec.tone : null;
    if (tone) t.a.dataset.tone = tone; else delete t.a.dataset.tone;
    t.a.dataset.known = String(known);
    tileWords(t, r, known, text);
  }
  // A tile's words, from what its read gave (r), and its title.
  function tileWords(t, r, known, text) {
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
  }
  function drawHead() {
    if (!app.headView) return;
    const parts = (app.last && app.last.panels) || {};
    const part = (id) => { const x = parts[id]; return x && typeof x === 'object' && !x.error && x.data && typeof x.data === 'object' ? x.data : null; };
    drawingHead = true;
    app.headView.tiles.forEach((t) => drawTile(t, part));
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
        // picking(): the tab in view shows the project choice (Show at every project, with more than one), as a panel of
        // it says by its ctx.picking(): the overlay draws no project over that choice.
        mod.draw(part(mod.part), { h, chip, money, post, undoLine, refusal, project, state: stateBlock, param, params, issueLink, depRef, depPicked,
          since, when, setTab, updatedAt: () => app.updatedAt, title() {}, relength() {},
          picking: () => idsOf(app.tab).some((id) => panels.has(id) && app.needsPick(panels.get(id).mod)) });
      } catch { /* the overlay is not drawn */ }
    });
  }
  // The machine head, under the tabs on every tab: head.js states it (machine: {part, draw(el, data, ctx)}) and it is
  // drawn from that part, whichever tab is open; with no such part to draw (not read, or an error) it is not shown.
  function drawMachine(part) {
    const el = byId('machine-head'), mod = app.headMod && app.headMod.machine;
    if (!el || !mod || typeof mod.draw !== 'function') return;
    const d = part(mod.part);
    el.hidden = !d;
    if (!d) return;
    try {
      mod.draw(el, d, { h, chip, money, post, undoLine, pausedSaid, project: projectOnly, sorted: projectSort, setProject, setProjectSort,
        updatedAt: () => app.updatedAt, get answerer() { return answerer(); } });
    } catch { el.hidden = true; }
  }
  // When the bar is too narrow for every tile, tiles go by their drop, lowest first; one with none always shows, and
  // the tiles never wrap: the ones that always show are the least room the tiles take. The head line is a grid row
  // that never wraps (app.css), so that least room widens the tiles' column; it never moves them to a line of their own.
  // What a fit measures: each tile's text and which of its parts are hidden, the Restart button beside them, the density
  // and the window's width (fitHead() itself hides whole tiles, so those are left out).
  const fitKey = () => [window.innerWidth, app.prefs.density, byId('restart') ? byId('restart').hidden : '', ...app.headView.tiles.map((t) => `${t.a.textContent}|${Array.from(t.a.querySelectorAll('*'), (e) => (e.hidden ? 1 : 0)).join('')}`)].join('\n');
  // A fit lays the head out and measures it: drawHead() and a figure that lands fit it again only when that changed.
  let headQueued = false;  // a drawTabs() and drawHead() wait for the next frame (headSoon())
  // A resize (resized) fits it again when the head's box changed its width too (its room at the last fit): the box can
  // narrow with no change of the window's width.
  function refit(resized) {
    if (app.headView && (app.headView.fitted !== fitKey() || (resized && app.headView.box.clientWidth !== app.headView.room))) fitHead();
  }
  function fitHead() {
    if (!app.headView) return;
    const box = app.headView.box, tiles = app.headView.tiles;
    app.headView.fitted = null;
    tiles.forEach((t) => { t.a.hidden = false; });
    box.style.minWidth = '';
    if (!box.clientWidth) return;  // not laid out (hidden, or no layout at all): fitted at the next drawHead()
    app.headView.fitted = fitKey();
    const width = new Map(tiles.map((t) => [t, t.a.getBoundingClientRect().width || 0]));
    const sum = (list) => list.reduce((s, t) => s + width.get(t), 0);
    box.style.minWidth = `${Math.ceil(sum(tiles.filter((t) => !t.spec.drop)))}px`;
    const room = box.clientWidth;
    app.headView.room = room;
    let total = sum(tiles);
    tiles.filter((t) => t.spec.drop).sort((a, b) => a.spec.drop - b.spec.drop).forEach((t) => {
      if (total > room) { total -= width.get(t); t.a.hidden = true; }
    });
    // The sticky head's height, for a box that fits the window under it (the Rules' "What these rules produce", app.css).
    const top = box.closest('.top');
    if (top) doc.documentElement.style.setProperty('--head-h', `${Math.ceil(top.getBoundingClientRect().height)}px`);
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
    if (app.failedLoads > 1) return `Stale: the last refreshes could not reach ${remote() ? 'the build machine' : 'the Board'}. This is the last data that loaded. If this continues, ${RESTART}.`;
    return `Stale: the newest data is ${age === null ? 'of unknown age' : `${ago(age)} old`}, so what you see can be out of date. If it stays old, ${RESTART}.`;
  }
  function status() {
    const el = byId('status'), up = byId('updated');
    let word = 'Loading', tone = 'quiet';
    const age = app.updatedAt === null ? null : now() - app.updatedAt;
    if (app.alive !== null && !app.aliveOld && now() - app.aliveSeenAt > ALIVE_MS) { word = 'Feed stopped'; tone = 'bad'; }
    else if (!app.loaded) { if (app.failedLoads) { word = 'No data'; tone = 'bad'; } }
    else if (age === null || age > STALE_MS || app.failedLoads > 1) { word = 'Stale'; tone = 'warn'; }
    // Live only while the feed sends each change; fresh data read from data.js at each refresh is Polling.
    else if (app.feedOpen) { word = 'Live'; tone = 'ok'; }
    else { word = 'Polling'; tone = 'ok'; }
    if (el.dataset.word !== word) { el.dataset.word = word; el.replaceChildren(chip(word, tone)); }
    // The restart is in the head only while the mark says the feed has a fault; else it is in the Health panel.
    const rs = byId('restart'), fault = FEED_FAULTS.includes(word);
    // The button takes room in the head line: a head draw queued for this frame fits it then, after its tiles.
    if (rs.hidden === fault) { rs.hidden = !fault; if (!headQueued) refit(); }
    up.textContent = app.updatedAt === null ? 'never' : `${ago(age)} ago`;
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
    if (app.tipAt && !app.tipAt.isConnected) closeTip();
    byId('clock').textContent = stamp(now(), { seconds: true });
    doc.querySelectorAll('time[data-since]').forEach((el) => {
      const off = Number(el.dataset.offset) || 0;
      const text = ago(now() - Date.parse(el.dataset.since) + off * 1000) + el.dataset.suffix;
      if (el.textContent !== text) el.textContent = text;
    });
    // A panel with a clock of its own moves with it: a part equal to the one drawn last is not drawn again, so a
    // refresh alone would leave it where it was.
    panels.forEach((p, id) => {
      if (p.state !== 'ready' || tabOf(id) !== app.tab || typeof p.mod.tick !== 'function') return;
      try { p.mod.tick(p.body, p.ctx); } catch { /* the next part that differs draws the panel whole */ }
    });
    status();
    newView();
  }
  function apply(data) {
    if (!data || typeof data !== 'object' || !data.panels || typeof data.panels !== 'object') { failed(); return; }
    app.loaded = true; app.failedLoads = 0;
    app.last = { updatedAt: data.updatedAt, panels: Object.assign({}, data.panels) };
    app.updatedAt = parse(data.updatedAt);
    title();
    if (doc.hidden) return;
    if (app.grid) app.grid.setAttribute('aria-busy', 'false');
    // Only the tab in view is drawn; the other's panels are drawn from this data when it is opened.
    panels.forEach((p, id) => { if (tabOf(id) === app.tab) draw(p, data.panels[partOf(id)]); });
    drawTabs();
    drawHead();
    arrange();
    status();
  }
  // The Board's browser-tab title has the Overview tab's count of cards stopped for you ("Overview · 2"), so a tab in
  // the background shows it too. The account page (no grid) keeps its own title.
  function title() {
    if (!app.grid) return;
    const k = attention('overview');
    const t = k > 0 ? `(${k}) Conveyor Board` : 'Conveyor Board';
    if (doc.title !== t) doc.title = t;  // the same title set again is still a change to the page
  }
  // One panel's new part from the live feed: the panels drawn from it are drawn again, and no other (a panel of the
  // other tab is kept for when that tab opens). A page with the head alone (account.html) has no panels: it keeps the change of
  // any part its snapshot holds, so its head tiles follow the feed as the Board's do.
  function applyPanel(msg) {
    if (!app.loaded || !msg || typeof msg !== 'object') return;
    const t = parse(msg.updatedAt);
    if (t !== null) { app.updatedAt = t; app.last.updatedAt = msg.updatedAt; }
    const known = typeof msg.id === 'string'
      && (panels.has(msg.id) || (!app.grid && Object.prototype.hasOwnProperty.call(app.last.panels, msg.id)));
    if (known) app.last.panels[msg.id] = msg.part;
    title();
    if (doc.hidden) return;
    if (known) {
      // A panel that holds one project shows the project choice or its data by the project list, which is the machine
      // part's: a part that came also looks again at each panel that shows the choice, or has to now, with the part that
      // panel has (draw leaves one whose part and choice did not change as it is). A second project that joins, or all
      // but one that leave, with the panel's own part sent before, changes the panel the same.
      const watch = (id) => { const p = panels.get(id); return Boolean(p.pick || pickKey(p.mod)); };
      const ids = idsOf(app.tab).filter((id) => partOf(id) === msg.id || watch(id));
      if (ids.length) { ids.forEach((id) => draw(panels.get(id), app.last.panels[partOf(id)])); arrangeSoon(); }
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
    if (app.feedOpen === open) return;
    app.feedOpen = open;
    const hp = panels.get('health');
    // Drawn anew when it is next drawn: now, when its tab opens, or when the page is shown again (shownAgain()).
    if (hp) hp.json = undefined;
    if (doc.hidden) return;
    status();  // Live or Polling
    if (!app.loaded || !hp) return;
    if (tabOf('health') !== app.tab) return;
    draw(hp, app.last.panels[partOf('health')]);
    arrangeSoon();
  }
  // The page shown again: drawn once from what it kept while hidden. Only a panel whose part changed while hidden is
  // drawn again (draw() leaves one with the part it drew as it is); a refresh skipped while hidden runs now, once.
  function shownAgain() {
    if (doc.hidden) return;
    if (app.grid && app.loaded) app.grid.setAttribute('aria-busy', 'false');
    if (app.last) idsOf(app.tab).forEach((id) => draw(panels.get(id), app.last.panels[partOf(id)]));
    drawHead();
    arrangeSoon();
    drawTabs();
    if (missed) { missed = false; app.aliveOld = true; refresh(); }
    tick();
  }
  // True when the page asked for the feed; false when this browser or address has none.
  function follow() {
    if (typeof window.EventSource !== 'function' || !/^https?:$/.test(window.location.protocol)) return false;
    const es = new window.EventSource('events');
    app.feed = es;
    const read = (fn) => (e) => { let m; try { m = JSON.parse(e.data); } catch { return; } fn(m); };
    es.addEventListener('open', () => feedChanged(true));
    es.addEventListener('snapshot', read((m) => { app.feedSeq += 1; feedChanged(true); apply(m); }));
    es.addEventListener('panel', read(applyPanel));
    es.addEventListener('updated', read(applyPanel));
    es.addEventListener('error', () => {
      feedChanged(false);
      // The feed did not open at start: the page draws from data.js now, not at the next refresh.
      if (!app.loaded && !app.dataAsked) readData();
      // A feed the server refused (logged out, too many followers) is closed for good: data.js is read meanwhile,
      // which also finds a lost login, and the feed is asked for again later.
      if (es.readyState === 2 && app.feed === es) { app.feed = null; window.setTimeout(follow, RETRY_MS); }
    });
    return true;
  }
  function failed() {
    app.failedLoads += 1;
    // Before any data, a page that cannot load says so in every panel; after, the last snapshot stays.
    if (!app.loaded) panels.forEach((p, id) => { if (tabOf(id) === app.tab) draw(p, { error: NOTHING, data: null }); });
    if (!app.loaded) arrange();
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
    app.dataAsked = true;
    window.DASH = undefined;
    // A data.js that arrives after the feed opened, or after a feed snapshot, is older than what the feed drew: it is
    // dropped, so it never overwrites panels the feed's later changes do not redraw.
    const seq = app.feedSeq;
    script('data.js', () => { if (!app.feedOpen && seq === app.feedSeq) apply(window.DASH); }, failed);
  }
  // waitFeed: the page's first refresh, with the feed just asked for: data.js is not read, as the feed's first
  // message has the whole of it; follow's error handler reads it if the feed does not open.
  // A hidden page reads nothing (the feed stays open): missed asks shownAgain() for one refresh when it is shown.
  // aliveOld: the heartbeat read before the page was hidden is old, not stopped: status() does not judge the feed by it
  // until the refresh run when shown has read alive.js again (or failed to).
  let missed = false;
  function refresh(waitFeed = false) {
    if (doc.hidden) { missed = true; return; }
    if (!app.feedOpen && !waitFeed) readData();
    script('alive.js', () => {
      app.aliveOld = false;
      const a = window.DASH_ALIVE;
      if (!a || typeof a !== 'object' || parse(a.at) === null) return;
      if (app.alive === null || a.at !== app.alive.at) app.aliveSeenAt = now();
      app.alive = a;
      if (typeof a.view === 'string') { if (app.view === null) app.view = a.view; else if (a.view !== app.view) { newer = true; newView(); } }
    }, () => { app.aliveOld = false; });
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
  // Last, so that every name above is set before app.js reads what this part gives back.
  window.DASH_APP.core((given) => {
    app = given;
    app.bind(bindNames);
    return { goTo, drawCustomize, refit, tick, draw, drawHead, asking, restart, panelHref, buildHead, fitHead,
      shownAgain, follow, refresh, watchView, watchMotion, overlay };
  });
})();
