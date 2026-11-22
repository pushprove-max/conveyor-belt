// SPDX-License-Identifier: Apache-2.0
// The tabs and the address, every project of the machine in one list (the filter, the sort and the tag), the older
// entries of the lists (the history), the words a phone can open and the parts of a panel's frame. Part of app.js,
// which hands it `app` (its names, and its state through getters and setters) as it loads (DASH_APP.core); boot.js
// loads it before the panels.
(() => {
  'use strict';
  // What this part uses of app.js and of its other parts, each bound as it loads (app.bind, at the end).
  let app, NOTHING, TABS, TAB_KEY, applyLayout, arrange, arrangeSoon, asking, byId, doc, draw, drawHead, h, icon, idsOf,
    modules, now, panels, partOf, restart, say, tabOf, twice, when;
  const bindNames = () => ({ NOTHING, TABS, TAB_KEY, applyLayout, arrange, arrangeSoon, asking, byId, doc, draw, drawHead, h,
    icon, idsOf, modules, now, panels, partOf, restart, say, tabOf, twice, when } = app);

  // ---- the tabs: Overview, 3D View, Control, Rules and Tests, kept in the address and in this browser ----
  const tabFromAddress = () => { try { const t = new URL(window.location.href).searchParams.get('tab'); return TABS.some((x) => x[0] === t) ? t : null; } catch { return null; } };
  function address(t, push) {
    try {
      const u = new URL(window.location.href);
      if (u.searchParams.get('tab') === t) return;
      u.searchParams.set('tab', t);
      if (push) window.history.pushState({ tab: t }, '', u.toString()); else window.history.replaceState({ tab: t }, '', u.toString());
    } catch { /* a page opened from a file keeps the tab in this browser only */ }
  }
  // A panel's choices kept in the address beside the tab (the project picked, a filter, a sort), so a reload or a
  // link keeps them: param(name) reads one (null when unset), params({name: value}) sets them (null or '' clears).
  function param(name) { try { return new URL(window.location.href).searchParams.get(name); } catch { return null; } }
  function params(set) {
    try {
      const u = new URL(window.location.href);
      Object.entries(set).forEach(([k, v]) => { if (v === null || v === undefined || v === '') u.searchParams.delete(k); else u.searchParams.set(k, String(v)); });
      window.history.replaceState(window.history.state, '', u.toString());
    } catch { /* a page opened from a file keeps the choice for this view only */ }
  }
  // A project picked from a panel (Projects and Foremen's "open its Board") is set as the machine head's Show sets it,
  // which every tab obeys. The tabs that hold one project also offer the choice (pickBlock), with Show at every project.
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
  // together, on every panel that lists rows of more than one project (a module with projects: true). The Board, the
  // Rules, the Tests and the Benchmarks hold one project at a time: the filter picks theirs (setProject's ?repo= with
  // it), and with every project shown they show a choice of project (pickBlock) and no project's data.
  // The host's projects, in its order: the repos of the part the machine head is drawn from (head.js names it).
  const repoNames = () => { const m = app.last && app.last.panels && app.headMod && app.headMod.machine && app.last.panels[app.headMod.machine.part]; return m && m.data && Array.isArray(m.data.repos) ? m.data.repos.filter((r) => typeof r === 'string') : []; };
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
  // and shown (on the tab in view, not hidden, not collapsed), at most once every HISTORY_MS, with the ETag of the
  // last one in If-None-Match: the server's 304, the history unchanged, changes nothing. Each such panel is drawn again
  // only when a history that differs from the last one has come (an equal one draws nothing). Until one has come, or
  // when it does not read, the live part is drawn alone. The history changes where the live part does not (an older
  // declined line filed), and the feed never draws again a part that does not change: so each read, whether it came or
  // failed, sets a timer that HISTORY_MS later reads it again while such a panel is shown and the page is shown; and
  // such a panel drawn when the last read is HISTORY_MS old (the tab or the page shown again after the timer found
  // those panels hidden, or one expanded again) reads it again too.
  const HISTORY_MS = 60000;
  let hist = null, histText = null, histTag = null, histAt = null, histVer = 0, histTimer = null;
  const histCan = () => /^https?:$/.test(window.location.protocol) && typeof window.fetch === 'function';
  const histDue = () => histCan() && (histAt === null || now() - histAt >= HISTORY_MS);
  const olderShown = () => Boolean(app.last) && Array.from(panels).some(([id, p]) => typeof p.mod.older === 'function' && tabOf(id) === app.tab
    && !app.layouts[app.tab].collapsed.includes(id) && !app.layouts[app.tab].hidden.includes(id));
  function drawOlder() {
    if (app.last) panels.forEach((p, id) => { if (typeof p.mod.older === 'function' && tabOf(id) === app.tab) draw(p, app.last.panels[partOf(id)]); });
    arrangeSoon();
  }
  function readHistory() {
    histAt = now();
    if (histTimer !== null) window.clearTimeout(histTimer);
    histTimer = window.setTimeout(() => { histTimer = null; if (!doc.hidden && olderShown()) readHistory(); }, HISTORY_MS);
    let tag = null;
    window.fetch('history', histTag ? { headers: { 'If-None-Match': histTag } } : undefined).then((r) => {
      if (!r.ok) return null;  // a 304 too: the history the page has is the server's
      tag = r.headers.get('ETag');
      return r.json();
    }).then((x) => {
      if (!x || typeof x !== 'object' || !x.panels || typeof x.panels !== 'object') return;
      histTag = tag;
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
  // A panel that holds one project at a time: one off Overview that does not list every project's rows. With more than
  // one project on the host and Show at every project, it shows pickBlock in place of its data.
  const holdsOne = (mod) => tabOf(mod.id) !== 'overview' && mod.projects !== true;
  const needsPick = (mod) => holdsOne(mod) && !projectOnly() && repoNames().length > 1;
  // The project choice: the first such panel of its tab that the layout shows names the tab and has a button for each
  // project (the same filter as the machine head's Show); each other one says where the choice is. A hidden panel
  // does not count, so the choice is never in a panel the owner hid (change() draws the panels again after a layout change).
  function pickFirst(mod) {
    const l = app.layouts[tabOf(mod.id)];
    return l.order.find((id) => !l.hidden.includes(id) && holdsOne(modules.get(id))) === mod.id;
  }
  // What pickBlock(mod) draws, as one string: '' when the panel shows its data. A panel builds the choice again only when
  // this changes, so a snapshot that keeps the project list leaves the buttons, and the focus on one, as they were; a
  // change to it draws a panel whose own part did not change (a project joined or left).
  const pickKey = (mod) => (needsPick(mod) ? JSON.stringify([pickFirst(mod), repoNames()]) : '');
  function pickBlock(mod) {
    const first = pickFirst(mod);
    if (!first) return stateBlock('empty', 'Pick a project to see this panel', 'The choice is at the top of this tab.');
    const el = stateBlock('empty', `${TABS.find((x) => x[0] === tabOf(mod.id))[1]} holds one project's settings`, 'Pick a project to see them.'), row = h('div', 'project-pick');
    row.setAttribute('role', 'group'); row.setAttribute('aria-label', 'Pick a project');
    repoNames().forEach((r) => {
      const b = h('button', 'btn btn-quiet', r);
      b.dataset.act = 'pick-project'; b.dataset.project = r;
      b.addEventListener('click', () => setProject(r));
      row.append(b);
    });
    el.append(row);
    return el;
  }
  function redrawAll() {
    panels.forEach((p) => { p.json = undefined; });
    if (app.last) idsOf(app.tab).forEach((id) => draw(panels.get(id), app.last.panels[partOf(id)]));
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
  // While a project's snapshot is behind its card records (a part's behind, [{repo, at}]: its recordsNewer), what a
  // panel shows of that project is as of when the snapshot was made: one line a project under it (el) says so, "As of
  // <time>, the belt has changed since." The line goes once no project is behind.
  function behind(el, list) {
    const xs = (Array.isArray(list) ? list : []).filter((b) => b && typeof b.repo === 'string');
    let box = el.querySelector(':scope > .behind');
    if (!xs.length) { if (box) box.remove(); return; }
    const said = xs.map((b) => [b.repo, `As of ${when(b.at)}, the belt has changed since.`]), key = JSON.stringify(said);
    if (!box) { box = h('div', 'behind'); box.setAttribute('role', 'status'); }
    if (box.key !== key) { box.key = key; box.replaceChildren(...said.map(([r, t]) => { const p = h('p', 'hint'); p.append(tag(r), ` ${t}`); return p; })); }
    if (el.lastElementChild !== box) el.append(box);
  }
  // What needs attention on a tab: each of its panels may say how many things (attention(data) of its module).
  function attention(t) {
    if (!app.last || !app.last.panels) return 0;
    return idsOf(t).reduce((n, id) => {
      const mod = modules.get(id), part = app.last.panels[partOf(id)];
      if (typeof mod.attention !== 'function' || !part || !part.data || typeof part.data !== 'object') return n;
      try { const k = Number(mod.attention(part.data)); return n + (Number.isFinite(k) && k > 0 ? k : 0); } catch { return n; }
    }, 0);
  }
  // The tab in view: its panels are put in the page and drawn from the last data; the other tab's are taken out.
  function setTab(t, push) {
    if (!TABS.some((x) => x[0] === t)) return;
    if (push) address(t, true);
    try { window.localStorage.setItem(TAB_KEY, t); } catch { /* the tab then lasts for this visit */ }
    if (t === app.tab) return;
    app.tab = t;
    app.grid.classList.remove('fresh');
    applyLayout();
    if (app.last) idsOf(app.tab).forEach((id) => draw(panels.get(id), app.last.panels[partOf(id)]));
    else if (!app.loaded && app.failedLoads) idsOf(app.tab).forEach((id) => draw(panels.get(id), { error: NOTHING, data: null }));
    // The head and its overlays again: an overlay hides over a tab that shows the project choice (the Rules' setup).
    drawHead();
    arrange();
    say(`${TABS.find((x) => x[0] === t)[1]} tab`);
  }
  function tip(el, text) {
    if (text) { el.title = text; el.dataset.tip = text; } else { el.removeAttribute('title'); delete el.dataset.tip; }
    if (el === app.tipAt) { if (text) openTip(el); else closeTip(); }
    return el;
  }
  function tipBox() {
    let box = byId('tip');
    if (!box) { box = h('div', 'tip-pop'); box.id = 'tip'; box.setAttribute('role', 'tooltip'); box.hidden = true; doc.body.append(box); }
    return box;
  }
  function closeTip() {
    if (!app.tipAt) return;
    app.tipAt.removeAttribute('aria-describedby');
    app.tipAt = null;
    tipBox().hidden = true;
  }
  function openTip(el) {
    const box = tipBox();
    box.textContent = el.dataset.tip;
    box.hidden = false;
    placeTip(el);
    el.setAttribute('aria-describedby', box.id);
    app.tipAt = el;
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
      const again = el === app.tipAt;
      closeTip();
      if (!again) openTip(el);
    }, true);
    doc.addEventListener('keydown', (e) => { if (e.key === 'Escape') closeTip(); });
    // A lint command's name shows its whole command when the keyboard reaches it (a click already does, and a mouse
    // press would open and close it at once, so only a keyboard focus counts).
    doc.addEventListener('focusin', (e) => {
      const el = e.target && e.target.closest ? e.target.closest('.lint-cmd-word[data-tip]') : null;
      const keyboard = () => { try { return el.matches(':focus-visible'); } catch { return true; } };
      if (el && keyboard() && el !== app.tipAt) { closeTip(); openTip(el); }
    });
    doc.addEventListener('focusout', (e) => { if (e.target === app.tipAt && e.target.classList.contains('lint-cmd-word')) closeTip(); });
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
    const host = app.last && app.last.panels && app.last.panels.health && app.last.panels.health.data && app.last.panels.health.data.host;
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
  const panelFaults = () => Array.from(panels.values()).some((q) => q.mod.id !== 'health' && tabOf(q.mod.id) === app.tab && (q.state === 'error' || !!q.note));
  function faultsChanged() {
    const f = panelFaults(), hp = panels.get('health');
    if (f === faultsShown) return;
    faultsShown = f;
    if (hp && hp.state === 'ready' && tabOf('health') === app.tab && app.last) { hp.json = undefined; draw(hp, app.last.panels[partOf('health')]); }
  }
  const details = (raw) => (raw ? `Details: ${raw}` : '');
  function unread(text, raw) { return tip(h('p', 'warn-note', text), details(raw)); }
  function stateBlock(kind, title, detail) {
    const el = h('div', `state state-${kind}`);
    el.append(icon(kind === 'error' ? 'bad' : 'ok'), h('p', 'state-title', title));
    if (detail) el.append(h('p', 'state-detail', detail));
    return el;
  }
  // Last, so that every name above is set before app.js reads what this part gives back.
  window.DASH_APP.core((given) => {
    app = given;
    app.bind(bindNames);
    return { params, redrawAll, param, projectOnly, tip, histDue, olderShown, readHistory, placeTip, attention,
      setTab, pickRepo, project, projectSort, tag, behind, tool, skeleton, machineWord, answerer, retryText,
      restartHere, panelFaults, details, unread, stateBlock, withOlder, shownData, needsPick, pickKey, pickBlock, remote, faultsChanged, setProject,
      setProjectSort, closeTip, tabFromAddress, address, wireTips, joined,
      get histVer() { return histVer; } };
  });
})();
