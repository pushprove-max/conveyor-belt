// SPDX-License-Identifier: Apache-2.0
// The Board panel's filters (priority, area, label), its sort and its groups. Part of panels/board.js, which asks
// for it by name (DASH_APP.use) and gives it what it uses; boot.js loads it before the panels.
(() => {
  'use strict';
  // What this part uses of panels/board.js, set when board.js asks for the part (DASH_APP.part, at the end).
  let KINDS, S, num, issues, lanes, notPushed, PART, elOf, button, draw;
  // ---- every column filtered by priority, area and label, and sorted, the choice kept in the address ----
  // A card's priority and labels are its own, else its open issue's (open.issues). A card whose issue is closed
  // (landed) has neither, and the Board cannot say what they were: it matches no filter, so a filter hides it. Time in a
  // column: when it came there (its pick-up into Building, its review's start, since when it waits in Needs you, its
  // landing, and for an issue in Held or Queue the snapshot's since: when it was held from the control record, else
  // when a snapshot first saw it in that column, never when it was opened); ascending is the longest there first. No sort: the column's own order (pick order in Queue).
  const PRIS = ['P0', 'P1', 'P2', 'P3'];
  const WHEN = { held: 'since', queue: 'since', building: 'pickedAt', review: 'stepAt', needs: 'since', landed: 'time' };
  const SORTS = [['', 'Column order'], ['priority', 'Priority'], ['number', 'Number'], ['time', 'Time in column']];
  const pre = () => (typeof S.d.areaPrefix === 'string' && S.d.areaPrefix ? S.d.areaPrefix : null);
  const openBy = () => new Map(issues(S.d.open && S.d.open.issues).map((x) => [x.issue, x]));
  function facts(x, by) {
    const i = by.get(x.issue) || {}, labels = issues(x.labels).length ? x.labels : issues(i.labels), p = pre();
    return { pri: x.priority || i.priority || null, labels,
      areas: p === null ? [] : labels.filter((l) => l.startsWith(p)) };
  }
  function choice() {
    const p = S.ctx.param;
    return { pri: p('bprio') || '', area: p('barea') || '', label: p('blabel') || '', sort: p('bsort') || '', dir: p('bdir') === 'desc' ? 'desc' : 'asc' };
  }
  // Whether a filter is on (the sort is none): a column it empties says so, with Clear, not that it is empty.
  const filtering = () => { const v = choice(); return !!(v.pri || v.area || v.label || S.filter.text.trim()); };
  function shape(col, list) {
    if (!list) return list;
    const v = choice(), by = openBy(), text = S.filter.text.trim().toLowerCase().replace(/^#/, '');
    const out = list.filter((x) => { const f = facts(x, by); return (!v.pri || f.pri === v.pri) && (!v.area || f.areas.includes(v.area)) && (!v.label || f.labels.includes(v.label))
      && (!text || String(x.issue).startsWith(text) || String(x.title || '').toLowerCase().includes(text)); });
    if (!v.sort || (v.sort === 'time' && !WHEN[col])) return out;
    const key = (x) => {
      const f = facts(x, by);
      if (v.sort === 'priority') return f.pri && PRIS.includes(f.pri) ? PRIS.indexOf(f.pri) : PRIS.length;
      if (v.sort === 'number') return num(x.issue) ?? Infinity;
      const t = Date.parse(x[WHEN[col]] || (by.get(x.issue) || {})[WHEN[col]] || '');
      return Number.isNaN(t) ? Infinity : t;
    };
    const s = v.dir === 'desc' ? -1 : 1;
    return out.map((x, i) => [x, key(x), i]).sort((a, b) => (a[1] === b[1] ? a[2] - b[2] : a[1] < b[1] ? -s : s)).map((x) => x[0]);
  }
  // The one row of filters and the sort of every column (the project is picked in the machine head, above the tabs).
  // The text box is the same node from one draw to the next, so what is typed keeps its place and the caret; the text
  // is kept through a reload of the page (ctx.keep), and read back when the box is first made.
  function textBox() {
    if (S.text) return S.text;
    const t = S.ctx.h('input', 'field board-select board-text');
    t.type = 'search'; t.placeholder = 'Filter: #, title'; t.dataset.filter = 'text'; t.setAttribute('aria-label', 'Filter every column by number or title');
    const was = S.ctx.kept('filter', 'board');
    if (typeof was === 'string') { S.filter.text = was; t.value = was; }
    t.addEventListener('input', () => { S.filter.text = t.value; S.ctx.keep('filter', 'board', t.value); draw(); });
    S.text = t;
    return t;
  }
  function clearFilters() {
    S.filter.text = '';
    S.ctx.keep('filter', 'board', '');
    if (S.text) S.text.value = '';
    S.ctx.params({ bprio: '', barea: '', blabel: '' });
    draw();
  }
  function viewBar() {
    const h = S.ctx.h, box = h('div', 'board-viewbar'), v = choice(), by = openBy(), p = pre();
    box.append(textBox());
    const labels = Array.from(new Set(Array.from(by.values()).flatMap((x) => issues(x.labels)))).sort();
    const areas = p === null ? [] : labels.filter((l) => l.startsWith(p));
    const sel = (act, name, opts, cur) => {
      const s = h('select', 'field board-select');
      s.dataset.act = act; s.setAttribute('aria-label', name);
      const all = cur && !opts.some(([o]) => o === cur) ? opts.concat([[cur, cur]]) : opts;
      all.forEach(([value, text]) => { const o = h('option', null, text); o.value = value; o.selected = value === cur; s.append(o); });
      s.addEventListener('change', () => { S.ctx.params({ [act]: s.value }); draw(); });
      return s;
    };
    box.append(sel('bprio', 'Filter every column by priority', [['', 'Any priority']].concat(PRIS.map((x) => [x, x])), v.pri),
      sel('barea', 'Filter every column by area', [['', 'Any area']].concat(areas.map((a) => [a, a.slice(p.length).replace(/^[:/]/, '')])), v.area),
      sel('blabel', 'Filter every column by label', [['', 'Any label']].concat(labels.map((l) => [l, l])), v.label),
      sel('bsort', 'Sort every column by', SORTS, v.sort),
      sel('bdir', 'Sort direction', [['asc', 'Ascending'], ['desc', 'Descending']], v.dir));
    return box;
  }
  const EMPTY = { held: 'Drag a card here to hold it.', queue: 'The queue is empty.', building: 'Conveyor builds no card now.', review: 'Nothing is in review.', needs: 'Nothing needs you.', landed: 'No card landed today.' };
  const UNMATCHED = { held: 'No held card matches the filter', queue: 'Nothing queued matches the filter', building: 'Nothing building matches the filter',
    review: 'Nothing in review matches the filter', needs: 'Nothing that needs you matches the filter', landed: 'Nothing landed today matches the filter' };
  // An empty queue says whether that is because issues are held, and where they are: "Nothing queued. Holds keep 12
  // issues back: see Held." (a link to the Held column); with none held, that nothing is open to build. held: Held's cards, or
  // null when the open issues were not listed.
  function queueEmpty(held) {
    const h = S.ctx.h, li = h('li', 'board-empty board-queue-empty'), n = Array.isArray(held) ? held.filter((x) => !notPushed(x)).length : null;
    if (n === null) { li.textContent = 'Nothing queued.'; return li; }
    if (!n) { li.textContent = 'Nothing queued, and nothing holds an issue: each open issue is on the belt, or Conveyor built it.'; return li; }
    const a = h('a', null, 'see Held');
    a.href = '#board-col-held';
    a.dataset.act = 'held-see';
    a.addEventListener('click', (e) => {
      e.preventDefault();
      const col = elOf(PART).querySelector('.board-col[data-col="held"]');
      if (col) { col.scrollIntoView({ block: 'nearest' }); const head = col.querySelector('.board-head'); if (head) { head.tabIndex = -1; head.focus({ preventScroll: true }); } }
    });
    li.append(`Nothing queued. Holds keep ${n === 1 ? '1 issue' : `${n} issues`} back: `, a, '.');
    return li;
  }
  // Landed today, the column acted on least, shows its newest LANDED landings (the snapshot lists them newest first),
  // then "Show all (N)", so it does not set the page's length.
  const LANDED = 5;
  // Every column's cards before the filter.
  function unshaped() {
    const d = S.d, l = lanes();
    const queue = l.queue === null ? null : l.queue.map((x, i) => Object.assign({}, x, { next: i + 1 })).concat(l.waits);
    return { held: l.held, queue, building: issues(d.building), review: issues(d.review),
      needs: issues(d.waiting).map((x) => Object.assign({ waiting: true }, x)).concat(issues(d.blocked)), landed: issues(d.landed) };
  }
  // The group of a held card: its first reason; a label is a group of its own.
  // Conveyor's own standing rules and an issue not picked for a reason named are skipped by a rule too: one group.
  // The hold a split puts on its umbrella (split: true, lib/snapshot.sh) is no hold of yours: it goes with its closed card.
  function groupOf(x) {
    const r = issues(x.reasons)[0] || { kind: 'other' };
    return r.kind === 'label' ? `label:${r.label}` : r.kind === 'standing' || r.kind === 'other' ? 'rule' : r.kind === 'you' && r.split ? 'card' : r.kind;
  }
  function groupTitle(key) {
    if (key.startsWith('label:')) return `Held by a label: ${key.slice(6)}`;
    return { you: 'Held by you', rule: 'Skipped by a rule', card: 'A card of it', parent: 'Follow-ups whose parent did not land yet', waits: 'Waiting on another card', approve: 'Waits for your yes' }[key] || key;
  }
  const groupRank = (key) => KINDS.indexOf(key.startsWith('label:') ? 'label' : key);
  // A column the filter emptied: what it would hold matches nothing, with Clear, so it is not taken for an empty column.
  function unmatched(tag, words) {
    const h = S.ctx.h, p = h(tag, 'board-empty board-unmatched', `${words} · `);
    p.append(button('Clear', 'btn-quiet', 'filter-clear', 'Clear the filter', clearFilters));
    return p;
  }
  window.DASH_APP.part('board-filters', function (shared) {
    ({ KINDS, S, num, issues, lanes, notPushed, PART, elOf, button, draw } = shared);
    return { filtering, shape, clearFilters, viewBar, EMPTY, UNMATCHED, queueEmpty, LANDED, unshaped, groupOf,
      groupTitle, groupRank, unmatched };
  });
})();
