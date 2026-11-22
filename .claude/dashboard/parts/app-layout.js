// SPDX-License-Identifier: Apache-2.0
// The layout of each tab: its order, widths, lengths, collapsed and hidden panels, and the density, theme, time and
// date; a panel's length; and the packing of the panels on the grid. Part of app.js, which hands it `app` (its
// names, and its state through getters and setters) as it loads (DASH_APP.core); boot.js loads it before the panels.
(() => {
  'use strict';
  // What this part uses of app.js and of its other parts, each bound as it loads (app.bind, at the end).
  let app, FOLD_MS, MOTION_MS, PREFS0, ROW_PX, ROW_SEL, SIZES, SNAP, STORE_KEY, TABS, TIME_SENT_KEY, byId, doc,
    drawCustomize, drawTabs, histDue, icon, modules, motion, olderShown, panels, placeTip, post, prefsOf, readHistory,
    redrawAll, refit, rowsAbove, stored, tick;
  const bindNames = () => ({ FOLD_MS, MOTION_MS, PREFS0, ROW_PX, ROW_SEL, SIZES, SNAP, STORE_KEY, TABS, TIME_SENT_KEY, byId,
    doc, drawCustomize, drawTabs, histDue, icon, modules, motion, olderShown, panels, placeTip, post, prefsOf,
    readHistory, redrawAll, refit, rowsAbove, stored, tick } = app);

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
  function readLayout() {
    const s = stored();
    // A layout kept before the tabs was the Overview's.
    const kept = s.tabs && typeof s.tabs === 'object' ? s.tabs : { overview: s };
    app.layouts = Object.fromEntries(TABS.map(([t]) => [t, tidy(t, kept[t])]));
    app.prefs = prefsOf(s);
  }
  // The Time goes to the server (time.json) for the plugin's Build pane on its machine; a send that fails leaves the pane on
  // its own `time` option or the Time sent before.
  function sendTime() {
    try { window.localStorage.setItem(TIME_SENT_KEY, '1'); } catch { /* then a kept 24-hour is sent again on the next visit */ }
    post('time', { time: app.prefs.time }).catch(() => {});
  }
  function save() {
    try { window.localStorage.setItem(STORE_KEY, JSON.stringify({ tabs: app.layouts, ...app.prefs })); } catch { /* the layout then lasts for this visit */ }
  }
  const lay = () => app.layouts[app.tab];
  const shown = () => lay().order.filter((id) => !lay().hidden.includes(id));
  function say(text) { const el = byId('announce'); if (el) el.textContent = text; }

  // Moves every panel from where it was to where the change put it: transform only, and off under reduced motion.
  function flip(change) {
    const els = Array.from(panels.values()).map((p) => p.el);
    const before = motion() ? new Map(els.map((el) => [el, el.getBoundingClientRect()])) : null;
    // The panels' entrance is over once the owner moves one: a panel put back in the grid would play it again, over the move.
    app.grid.classList.remove('fresh');
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
    root.dataset.density = app.prefs.density;
    if (app.prefs.theme === 'system') delete root.dataset.theme; else root.dataset.theme = app.prefs.theme;
    // A panel already in its place is left in the page: taking it out and putting it back would drop the keyboard
    // focus from the control the owner just used, and play the body's entrance again. The other tab's panels are not drawn
    // and take no space: they are out of the page.
    const focused = doc.activeElement;
    panels.forEach((p, id) => { if (tabOf(id) !== app.tab && p.el.parentNode === app.grid) p.el.remove(); });
    l.order.forEach((id, i) => {
      const p = panels.get(id);
      const collapsed = l.collapsed.includes(id), size = l.sizes[id];
      const was = p.el.dataset.collapsed;  // undefined until the layout has been applied once
      if (app.grid.children[i] !== p.el) app.grid.insertBefore(p.el, app.grid.children[i] || null);
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
    if (focused && focused !== doc.activeElement && app.grid.contains(focused) && !focused.disabled) focused.focus({ preventScroll: true });
  }
  // Collapsing with motion on: the body fades and lifts first, then it is taken out and the panels below slide up.
  // The layout already says collapsed; a panel opened again before the fade ends stays open.
  function fold(id, p) {
    p.body.classList.add('folding');
    window.setTimeout(() => {
      if (!p.body.classList.contains('folding')) return;
      p.body.classList.remove('folding');
      // The collapse is the owner's change of the layout: once the body is out, the panels are placed anew.
      if (app.layouts[tabOf(id)].collapsed.includes(id)) flip(() => { p.body.hidden = true; clip(p); app.placed = null; arrange(); });
    }, FOLD_MS);
  }
  function change(fn, message) {
    const was = `${app.prefs.time} ${app.prefs.date}`;
    flip(() => { fn(); applyLayout(); });
    refit();  // a new Density changes the tiles' padding and figures: the head is fitted again
    save();
    // A new Time or Date shows at once: each panel's times are written when it is drawn, so every panel is drawn again
    // (the other tabs' when they are opened), with the head and its clock.
    if (`${app.prefs.time} ${app.prefs.date}` !== was) { redrawAll(); tick(); }
    // The project choice is in the first panel shown (pickBlock): a panel hidden, shown or moved changes which one.
    else if (idsOf(app.tab).some((id) => app.needsPick(modules.get(id)))) redrawAll();
    // A new Time, from its choice or from Restore, also goes to the server.
    if (!was.startsWith(`${app.prefs.time} `)) sendTime();
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
    // A panel with older entries expanded or shown again reads the history when it is time to (olderShown).
    if (!on && histDue() && olderShown()) readHistory();
  }
  // Restore puts the tab in view back as it was by default, with the density, theme, time and date.
  function reset() {
    change(() => { app.layouts[app.tab] = defaults(app.tab); app.prefs = { ...PREFS0 }; }, `Default layout of ${TABS.find((x) => x[0] === app.tab)[1]} restored`);
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
  const wantOf = (p) => { const v = app.layouts[tabOf(p.mod.id)].lengths[p.mod.id]; return v === undefined ? lengthOf(p) : v; };
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
    const id = p.mod.id, l = app.layouts[tabOf(id)], want = wantOf(p);
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
    const id = p.mod.id, l = app.layouts[tabOf(id)];
    change(() => { if (v === lengthOf(p)) delete l.lengths[id]; else l.lengths[id] = v; }, message);
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
  // Panel p as pack() takes it, {id, w, h}: w columns wide and h grid rows high.
  function packItem(p, w, gap) {
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
  }
  // Places every panel of the tab in view: measured at its own height, packed, and grown to fill where pack says.
  // A refresh that only changes panels' heights keeps each panel in the column it had, so the panel being read does
  // not jump to another column. The panels are placed anew when the first data comes, and when the tab, the column
  // count, the density or the tab's layout (order, widths, lengths, collapsed, hidden: a panel added or removed too)
  // changes.
  function arrange() {
    if (!app.grid || app.arranging) return;
    app.arranging = true;
    try {
      const cols = columns(), gap = app.prefs.density === 'compact' ? 12 : 16;
      app.grid.dataset.cols = String(cols);
      const vis = shown().map((id) => panels.get(id));
      const key = JSON.stringify([app.loaded, app.tab, cols, app.prefs.density, lay(), vis.map((p) => p.mod.id)]);
      const at = app.placed && app.placed.key === key ? app.placed.cols : new Map();
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
      const items = cuts.map(({ p, w }) => packItem(p, w, gap));
      const out = pack(items, cols, at);
      app.placed = { key, cols: new Map(out.map((x) => [x.id, x.col])) };
      out.forEach((at) => {
        const p = panels.get(at.id);
        p.el.style.gridColumn = `${at.col + 1} / span ${at.w}`;
        p.el.style.gridRow = `${at.row + 1} / span ${at.h}`;
        p.el.dataset.col = String(at.col); p.el.dataset.row = String(at.row); p.el.dataset.span = String(at.h);
        const fill = at.h * ROW_PX - gap;
        p.el.style.minHeight = fill > p.natural + 1 ? `${fill}px` : '';
      });
      // An open tip follows its item to where this draw put it.
      if (app.tipAt && app.tipAt.isConnected) placeTip(app.tipAt);
    } finally { app.arranging = false; }
  }
  // Once a frame, when a panel's content changed its height.
  function arrangeSoon() {
    if (app.queued) return;
    app.queued = true;
    const run = () => { app.queued = false; arrange(); };
    if (typeof window.requestAnimationFrame === 'function') window.requestAnimationFrame(run); else run();
  }
  // Last, so that every name above is set before app.js reads what this part gives back.
  window.DASH_APP.core((given) => {
    app = given;
    app.bind(bindNames);
    return { wantOf, setLength, tabOf, partOf, arrangeSoon, idsOf, say, applyLayout, arrange, widthsOf, save, lay,
      flip, change, move, toggle, inRow, clip, lengthDrag, hideable, reset, lengthOk, readLayout, sendTime, pack };
  });
})();
