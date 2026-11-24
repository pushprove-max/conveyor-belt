// SPDX-License-Identifier: Apache-2.0
// The Self-heals tab (issue 1562): the self-heals list of each project on a page of its own, after Benchmarks, drawn
// from the Declined part's heals (panels/declined.js registers it). Its parts, top to bottom:
//   the title line, with the days an entry stays unseen (the Rules setting healsdays, as the record gives it) and a link
//     to that setting, and when the list was read (kept through a failed read, with the list it read then);
//   five tiles: on the list, areas ready to batch (READY entries or more), seen again in the last 7 days, leaving in
//     SOON days or less, and moved up to harm in the last 30 days (the dropped record's harm entries, and the
//     entries back on the list whose expired mark is a move up to harm);
//   a card for each area (its group and name from its label, its count, an age bar in three parts of the days, the kinds
//     with their counts, and how far it is from a batch);
//   the entries, a list beside a detail panel (stacked under it at phone width, app.css): search, sort and a filter
//     chip for each kind; a row is picked by a click and shown in the panel; checked rows get a bar with Move up to harm.
//     Move up to harm (`conveyor.sh heals harm`, a card each: confirmed by a second click) and Drop now (`heals drop`,
//     also confirmed) take an entry off the page at once; the dropped entries are under the list's footer;
//   the docs list by area, whose entries never expire (no days-left ring).
// What heals (kindOf): cleanup and already guarded are the judge's kinds; a self-heals entry's way of healing is read
// from the judge's reason (READS), "not read" when the reason names none. An entry with no date or a project with no
// days shows "not read" for its days left and its age.
(() => {
  const DAY = 86400000, READY = 10, SOON = 7, HARM_MAX = 10, DROP_MAX = 400, LATELY = 7, HARMED = 30;
  const KINDS = [['wait', 'Waits longer'], ['again', 'Runs again'], ['text', 'Text fixes itself'], ['extra', 'Extra work only'],
    ['docs', 'Docs or comment'], ['cleanup', 'Cleanup'], ['guarded', 'Already guarded']];
  const NAMES = Object.fromEntries(KINDS);
  // The ways a self-heals failure heals, as the judge's reason words them; the first that matches is the entry's.
  const READS = [['wait', /\b(waits?|waited|waiting|longer|later|delay(?:ed|s)?|slow(?:er)?|time ?outs?|time limit)\b/i],
    ['again', /\b(again|retr(?:y|ies|ied)|re-?runs?|next (?:turn|run|pass|tick|pick|round))\b/i],
    ['text', /\b(text|label|message|wording|says|shown|display(?:s|ed)?|polls?)\b/i],
    ['extra', /\b(extra|wasted?|costs?|redundant|more work)\b/i],
    ['docs', /\b(docs?|comments?|readme|guide)\b/i]];
  const SORTS = [['leaves', 'Leaves soonest'], ['newest', 'Newest'], ['seen', 'Seen most'], ['area', 'Area']];
  const NOT_READ = 'not read';
  // What the owner did here, through every redraw: the search, sort, kind chip, the row shown in the detail panel, the
  // rows checked, the entries moved or dropped here (gone: hidden until a snapshot no longer lists them), the last
  // answer of the host (note) and whether the dropped entries are open.
  const S = { q: '', sort: 'leaves', kind: 'all', sel: null, checked: new Set(), gone: new Set(), note: '', dropOpen: false, busy: false, ctx: null, m: null, at: null };
  const list = (v) => (Array.isArray(v) ? v : []);
  const num = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : null);
  const plural = (k, one, many) => `${k} ${k === 1 ? one : many}`;
  const keyOf = (e) => `${e.repo}:${e.id}`;
  const MARKS = /^(?:\[[^\]]*\]\s*)*/;
  const PLACE = /[A-Za-z0-9_./-]+:[0-9]+(?:[–-][0-9]+)?/;
  const text = (e) => String(e.finding || '');
  // Its level, of the marks that lead it (after an audit's number, R1, which may come first).
  const levelOf = (e) => { const m = /\[P([0-3])\]/.exec(MARKS.exec(text(e).replace(/^R[0-9]+\s+/, ''))[0]); return m ? `P${m[1]}` : null; };
  const placeOf = (s) => { const m = PLACE.exec(String(s || '')); return m ? m[0] : null; };
  // Its proof: after "Proof:", or an audit's "- How:" section, up to the audit's next section (- Fix:, - Test:, - Raised on).
  const proofOf = (e) => { const m = /(?:\bproof:|\s- how:)\s*([\s\S]+?)(?=\s+- (?:fix:|test:|raised on\b)|$)/i.exec(text(e)); return m ? m[1].trim() : null; };
  const isAudit = (e) => /^R[0-9]+\s/.test(text(e).replace(MARKS, ''));
  // The finding without its marks, audit number, place (an audit quotes it in backticks) and Proof or audit sections:
  // what it says is wrong.
  const titleOf = (e) => text(e).replace(MARKS, '').replace(/^R[0-9]+\s+/, '').replace(MARKS, '')
    .replace(/^`?[A-Za-z0-9_./-]+:[0-9]+(?:[–-][0-9]+)?`?:?\s+/, '').replace(/(?:[.:;]?\s*\bproof:|\s+- (?:how|fix|test):)[\s\S]*$/i, '').trim() || text(e);
  // Where a finding came from: its issue, or its card when it has no GitHub issue (issue 0).
  const fromOf = (e) => (e.issue ? `#${e.issue}` : `card ${e.card || NOT_READ}`);
  const kindOf = (e) => {
    if (e.effect === 'cleanup') return 'cleanup';
    if (e.effect === 'already guarded') return 'guarded';
    if (e.effect !== null && e.effect !== undefined && e.effect !== 'self-heals') return null;
    const hit = READS.find(([, re]) => re.test(String(e.why || '')));
    return hit ? hit[0] : null;
  };
  const cap = (s) => s.charAt(0).toUpperCase() + s.slice(1);
  // An area label as a card names it: its group (the part before a slash, else the whole name) and its name, the
  // label's prefix ("area:") cut off.
  const areaOf = (a) => {
    if (typeof a !== 'string' || !a) return { group: 'No area', name: 'No area' };
    const n = a.replace(/^[^:/]*:/, ''), i = n.indexOf('/');
    return i > 0 ? { group: cap(n.slice(0, i)), name: n.slice(i + 1) } : { group: cap(n), name: n };
  };
  // Each entry with what the page reads from it: its age and days left count from its last sighting, else its time.
  function entryOf(e, x, now) {
    const days = num(x.days), at = Date.parse(e.seen || e.time), ok = Number.isFinite(at);
    const age = ok ? Math.max(0, (now - at) / DAY) : null;
    return { e, x, key: keyOf(e), days, age, left: ok && days !== null ? Math.max(0, Math.ceil(days - age)) : null, kind: kindOf(e),
      level: levelOf(e), title: titleOf(e), place: placeOf(text(e)), seen: num(e.sightings) || 0, time: Date.parse(e.time) || 0 };
  }
  const listsOf = (d) => list(d && d.heals).filter((x) => x && typeof x === 'object');
  const liveOf = (d) => listsOf(d).flatMap((x) => list(x.entries).filter((e) => e && !S.gone.has(keyOf(e))));
  function model(d, now) {
    const lists = listsOf(d);
    return { lists, many: new Set(lists.map((x) => x.repo)).size > 1,
      es: lists.flatMap((x) => list(x.entries).filter((e) => e && !S.gone.has(keyOf(e))).map((e) => entryOf(e, x, now))),
      docs: lists.flatMap((x) => list(x.docs && x.docs.entries).filter(Boolean).map((e) => entryOf(e, { days: null }, now))),
      dropped: lists.flatMap((x) => list(x.dropped).filter((e) => e && e.dropped)) };
  }
  const daysSaid = (m) => {
    const ds = Array.from(new Set(m.lists.map((x) => num(x.days)).filter((v) => v !== null))).sort((a, b) => a - b);
    return ds.length ? ds.join(' or ') : null;
  };
  const matches = (r) => {
    const q = S.q.trim().toLowerCase().replace(/^#/, '');
    return !q || [text(r.e), r.e.card, r.e.issue ? String(r.e.issue) : ''].some((s) => String(s || '').toLowerCase().includes(q));
  };
  const byLeft = (a, b) => (a.left === null) - (b.left === null) || (a.left || 0) - (b.left || 0) || b.time - a.time;
  const SORT = {
    leaves: byLeft,
    newest: (a, b) => b.time - a.time,
    seen: (a, b) => b.seen - a.seen || byLeft(a, b),
    area: (a, b) => (!a.e.area) - (!b.e.area) || String(a.e.area || '').localeCompare(String(b.e.area || '')) || byLeft(a, b),
  };
  const shown = (m) => m.es.filter((r) => matches(r) && (S.kind === 'all' || r.kind === S.kind)).sort(SORT[S.sort]);

  // ---- small marks ----
  const h = (...a) => S.ctx.h(...a);
  const pTag = (level) => { const t = h('span', `sh-p${level === 'P0' || level === 'P1' ? ' is-high' : ''}`, level || 'P?'); if (!level) t.title = 'level not read'; return t; };
  const kindPill = (kind) => { const p = h('span', `sh-kind sh-k-${kind || 'none'}`, kind ? NAMES[kind] : `kind ${NOT_READ}`); p.dataset.kind = kind || ''; return p; };
  const daysLeft = (r) => (r.left === null ? NOT_READ : `${r.left} d left`);
  // The days left of the days an entry may stay unseen, as a ring: amber at SOON days or less; none for one not read.
  function ring(r) {
    const box = h('span', `sh-left${r.left !== null && r.left <= SOON ? ' is-soon' : ''}`), NS = 'http://www.w3.org/2000/svg';
    if (r.left !== null && r.days) {
      const svg = document.createElementNS(NS, 'svg'), c = 2 * Math.PI * 8;
      svg.setAttribute('viewBox', '0 0 20 20'); svg.setAttribute('class', 'sh-ring'); svg.setAttribute('aria-hidden', 'true');
      [['sh-ring-track', c], ['sh-ring-left', c * Math.min(1, r.left / r.days)]].forEach(([cls, len]) => {
        const o = document.createElementNS(NS, 'circle');
        o.setAttribute('cx', '10'); o.setAttribute('cy', '10'); o.setAttribute('r', '8'); o.setAttribute('class', cls);
        o.setAttribute('stroke-dasharray', `${len.toFixed(2)} ${c.toFixed(2)}`);
        svg.append(o);
      });
      box.append(svg);
    }
    box.append(h('span', 'sh-left-n', daysLeft(r)));
    return box;
  }

  // ---- the title line and the tiles ----
  function headEl(m) {
    const ctx = S.ctx, box = h('div', 'sh-head'), side = h('div', 'sh-head-side'), days = daysSaid(m);
    const title = h('div', 'sh-head-main');
    title.append(h('h3', 'sh-title', 'Self-heals list'), h('p', 'sh-lede', 'Real findings whose failure heals by itself: a card waits longer, a step runs again, or text is wrong until the next turn. Conveyor does not build them one by one. Fix them in a batch card for each area, or move one up to harm when it shows up in real logs.'));
    const pill = h('span', 'sh-pill', days ? `An entry leaves after ${days} days unseen` : `Days an entry stays: ${NOT_READ}`);
    const link = h('a', 'btn btn-quiet sh-rules', 'Rules › Self-heals');
    link.href = ctx.panelHref('rules');
    link.addEventListener('click', (ev) => {
      ev.preventDefault();
      ctx.goTo('rules');
      // Rules shows one group at a time (Models first): the group that holds the setting is opened, its search cleared.
      const row = document.querySelector('.rules-row[data-rule="healsdays"]'), set = row && row.closest('.rules-set');
      const pick = set && document.querySelector(`[data-act="rules-set-${set.dataset.set}"]`);
      if (pick) pick.click();
      if (row && typeof row.scrollIntoView === 'function') row.scrollIntoView({ block: 'center' });
    });
    side.append(pill, link);
    if (S.at !== null) { const read = h('p', 'sh-read'); read.append('List read ', ctx.since(new Date(S.at).toISOString().replace(/\.\d{3}Z$/, 'Z'), ' ago')); side.append(read); }
    box.append(title, side);
    return box;
  }
  function tilesEl(m, now) {
    const box = h('div', 'sh-tiles'), areas = areasOf(m.es), lately = now - LATELY * DAY, harmed = now - HARMED * DAY;
    // A card with no GitHub issue (issue 0) adds no issue.
    const issues = new Set(m.es.filter((r) => r.e.issue && !isAudit(r.e)).map((r) => r.e.issue)), audits = new Set(m.es.filter((r) => r.e.issue && isAudit(r.e)).map((r) => r.e.issue));
    const tile = (k, label, n, sub, tone) => {
      const t = h('div', `sh-tile${tone ? ` is-${tone}` : ''}`);
      t.dataset.tile = k;
      t.append(h('span', 'sh-tile-label', label), h('span', 'sh-tile-n', String(n)), h('span', 'sh-tile-sub', sub));
      box.append(t);
    };
    const days = daysSaid(m) || NOT_READ;
    tile('on', 'On the list', m.es.length, `from ${plural(issues.size, 'issue', 'issues')} and ${plural(audits.size, 'audit', 'audits')}`);
    tile('ready', 'Ready to batch', areas.filter((a) => a.rs.length >= READY).length, `areas with ${READY} or more entries`);
    tile('seen', `Seen again, last ${LATELY} days`, m.es.filter((r) => r.seen > 0 && Date.parse(r.e.seen) >= lately).length, `a sighting resets its ${days} days`, 'ok');
    tile('leaving', `Leave in ${SOON} days`, m.es.filter((r) => r.left !== null && r.left <= SOON).length, 'kept in Dropped, never erased', 'warn');
    // A move up to harm is in the dropped record, or, once a review listed the finding again, kept on the entry as expired.
    const ups = m.dropped.map((e) => e.dropped).concat(m.lists.flatMap((x) => list(x.entries).map((e) => e && e.expired)));
    tile('harm', `Moved up to harm, ${HARMED} days`, ups.filter((x) => x && x.why === 'harm' && Date.parse(x.time) >= harmed).length, 'seen in real logs', 'bad');
    return box;
  }

  // ---- the area cards ----
  function areasOf(rs) {
    const by = new Map();
    rs.forEach((r) => { const k = `${r.e.repo}|${r.e.area || ''}`; if (!by.has(k)) by.set(k, { repo: r.e.repo, area: r.e.area || null, rs: [] }); by.get(k).rs.push(r); });
    return Array.from(by.values()).sort((a, b) => b.rs.length - a.rs.length || (!a.area) - (!b.area) || String(a.area).localeCompare(String(b.area)));
  }
  function ageBar(a) {
    const d = num(a.rs[0] && a.rs[0].days), parts = [0, 0, 0];
    let unread = 0;
    // The parts end at whole days, at least a day apart, and the last holds every older entry: each entry counts in the
    // part whose legend names its age.
    const b1 = d ? Math.max(1, Math.floor(d / 3)) : null, b2 = d ? Math.max(b1 + 1, Math.floor((2 * d) / 3)) : null;
    a.rs.forEach((r) => { if (r.age === null || !d) unread += 1; else parts[r.age < b1 ? 0 : r.age < b2 ? 1 : 2] += 1; });
    const names = d ? [`0–${b1} days`, `${b1}–${b2} days`, `${plural(b2, 'day', 'days')} or more, leaving soon`] : ['young', 'middle', 'leaving soon'];
    const wrap = h('div', 'sh-age-wrap'), bar = h('div', 'sh-age'), legend = h('ul', 'sh-legend');
    bar.setAttribute('role', 'img');
    bar.setAttribute('aria-label', `Age: ${parts.map((n, i) => `${n} of ${names[i]}`).join(', ')}${unread ? `, ${unread} ${NOT_READ}` : ''}`);
    parts.forEach((n, i) => {
      const seg = h('span', `sh-age-${i}`);
      seg.style.width = `${a.rs.length ? (n * 100) / a.rs.length : 0}%`;
      bar.append(seg);
      const li = h('li', null);
      li.append(h('span', `sh-dot sh-age-${i}`), names[i]);
      legend.append(li);
    });
    wrap.append(bar, legend);
    return wrap;
  }
  function areaCard(a, many) {
    const card = h('article', 'sh-area'), n = a.rs.length, place = areaOf(a.area), kinds = new Map();
    card.dataset.area = a.area || '';
    a.rs.forEach((r) => kinds.set(r.kind, (kinds.get(r.kind) || 0) + 1));
    const top = h('div', 'sh-area-top'), name = h('div', 'sh-area-name');
    name.append(h('span', 'sh-group', place.group), h('strong', null, place.name));
    if (many) name.append(S.ctx.tag(a.repo));
    top.append(name, h('span', 'sh-area-n', String(n)));
    const pills = h('div', 'sh-pills');
    KINDS.concat([[null]]).forEach(([k]) => { if (!kinds.has(k)) return; const p = kindPill(k); p.append(h('span', 'sh-kind-n', ` ${kinds.get(k)}`)); pills.append(p); });
    const foot = h('p', `sh-area-foot${n >= READY ? ' is-ready' : ''}`, n >= READY ? '✓ Ready to batch' : `${READY - n} more to batch`);
    card.append(top, ageBar(a), pills, foot);
    return card;
  }

  // ---- the entries: toolbar, rows, detail panel, selection bar, footer ----
  function toolbar() {
    const bar = h('div', 'sh-tools'), q = h('input', 'sh-search'), sort = h('select', 'sh-sort'), chips = h('div', 'sh-chips');
    q.type = 'search'; q.value = S.q; q.placeholder = 'Search finding, file or card'; q.setAttribute('aria-label', 'Search the entries by finding, file or card');
    q.addEventListener('input', () => { S.q = q.value; drawEntries(); });
    sort.setAttribute('aria-label', 'Sort the entries');
    SORTS.forEach(([k, label]) => { const o = h('option', null, label); o.value = k; o.selected = S.sort === k; sort.append(o); });
    sort.addEventListener('change', () => { S.sort = sort.value; drawEntries(); });
    chips.setAttribute('role', 'group'); chips.setAttribute('aria-label', 'Show the entries of one kind');
    const sl = h('label', 'sh-sort-label', 'Sort ');
    sl.append(sort);
    bar.append(q, sl, chips);
    return bar;
  }
  function drawChips(m) {
    const chips = S.parts.chips;
    chips.replaceChildren();
    [['all', 'All']].concat(KINDS).forEach(([k, label]) => {
      const n = k === 'all' ? m.es.length : m.es.filter((r) => r.kind === k).length;
      const b = h('button', `sh-chip sh-k-${k}`);
      b.type = 'button'; b.dataset.kind = k; b.dataset.focus = `chip:${k}`; b.setAttribute('aria-pressed', String(S.kind === k));
      b.append(h('span', 'sh-dot', ''), `${label} `, h('span', 'sh-chip-n', String(n)));
      b.addEventListener('click', () => { S.kind = k; drawEntries(); });
      chips.append(b);
    });
  }
  function rowEl(r, many) {
    const li = h('li', `sh-row${S.sel === r.key ? ' is-selected' : ''}`), box = h('input', 'sh-check'), open = h('button', 'sh-open');
    li.dataset.key = r.key;
    if (S.sel === r.key) open.setAttribute('aria-current', 'true');
    box.type = 'checkbox'; box.dataset.focus = `check:${r.key}`; open.dataset.focus = `open:${r.key}`; box.checked = S.checked.has(r.key); box.setAttribute('aria-label', `Select: ${r.title}`);
    box.addEventListener('change', () => { if (box.checked) S.checked.add(r.key); else S.checked.delete(r.key); drawBar(); });
    open.type = 'button'; open.title = text(r.e);
    open.append(pTag(r.level), h('span', 'sh-row-title', r.title));
    const meta = h('p', 'sh-row-meta');
    meta.append(kindPill(r.kind), h('code', 'sh-at', r.place || `file ${NOT_READ}`), h('span', 'sh-row-area', r.e.area || 'No area'), h('span', 'sh-from', `from ${fromOf(r.e)}`));
    if (many) meta.append(S.ctx.tag(r.e.repo));
    if (r.seen) meta.append(h('span', 'sh-seen', `seen ${r.seen}×`));
    const main = h('div', 'sh-row-main');
    main.append(open, meta);
    li.append(box, main, ring(r));
    li.addEventListener('click', (ev) => { if (ev.target === box) return; S.sel = r.key; drawEntries(); });
    return li;
  }
  // The control that has the focus (its data-focus), and the focus given back to the control drawn in its place: a row,
  // a chip or the Dropped button that the owner works from the keyboard keeps the focus when the list is drawn again.
  const focusOf = () => { const a = document.activeElement; return a && a.dataset && a.closest('.sh-entries') ? a.dataset.focus || null : null; };
  const refocus = (k) => {
    const el = k && Array.from(S.parts.root.querySelectorAll('[data-focus]')).find((x) => x.dataset.focus === k);
    if (el && document.activeElement !== el) el.focus({ preventScroll: true });
  };
  function drawEntries() {
    const m = S.m, rs = shown(m), p = S.parts, k = focusOf();
    drawChips(m);
    p.rows.replaceChildren(...rs.map((r) => rowEl(r, m.many)));
    if (!rs.length) p.rows.append(h('li', 'sh-none', m.es.length ? 'No entry matches this search or kind.' : 'No entry is on the list now.'));
    p.detail.replaceChildren(...detailEl(m.es.find((r) => r.key === S.sel) || null));
    p.note.textContent = S.note;
    p.foot.replaceChildren(...footEl(m, rs.length));
    drawBar();
    refocus(k);
  }
  // The entries checked that are still on the page, and the bar that acts on them.
  function drawBar() {
    const bar = S.parts.bar, rs = S.m.es.filter((r) => S.checked.has(r.key));
    bar.replaceChildren();
    bar.hidden = !rs.length;
    if (!rs.length) return;
    const up = h('button', 'btn', 'Move up to harm'), clear = h('button', 'btn btn-quiet', 'Clear');
    up.type = 'button'; up.dataset.act = 'harm'; up.disabled = S.busy;
    S.ctx.twice(up, 'spend', `Click again to file ${plural(rs.length, 'follow-up card', 'follow-up cards')}`, () => send(rs, 'harm'));
    clear.type = 'button'; clear.dataset.act = 'clear';
    clear.addEventListener('click', () => { S.checked.clear(); drawEntries(); });
    bar.append(h('strong', 'sh-bar-n', `${rs.length} selected`), up, clear);
  }
  function detailEl(r) {
    if (!r) return [h('p', 'sh-detail-none', 'Pick an entry to see why it self-heals, its proof and its history.')];
    const ctx = S.ctx, e = r.e, out = [], top = h('div', 'sh-detail-top');
    top.append(pTag(r.level), kindPill(r.kind), h('span', `sh-leaves${r.left !== null && r.left <= SOON ? ' is-soon' : ''}`, r.left === null ? `leaves in: ${NOT_READ}` : `leaves in ${plural(r.left, 'day', 'days')}`));
    out.push(top, h('h4', 'sh-detail-title', r.title));
    const dl = h('dl', 'sh-facts'), fact = (k, ...v) => { dl.append(h('dt', null, k)); const dd = h('dd', null); dd.append(...v); dl.append(dd); };
    fact('Area', e.area || 'No area');
    // A card with no GitHub issue has no issue to link: its card is named.
    const found = e.issue ? ctx.issueLink(e) : h('span', null);
    found.textContent = `${fromOf(e)} review`;
    fact('Found in', found);
    fact('File', r.place ? window.DASH_APP.text.codeEl(e.repoUrl, r.place, new Set(), 'sh-file').el : `file ${NOT_READ}`);
    fact('Seen again', r.seen ? `${r.seen}×, last ` : 'not seen again yet', ...(r.seen && e.seen ? [ctx.since(e.seen, ' ago')] : []));
    out.push(dl);
    const why = h('div', 'sh-why');
    why.append(h('p', 'sh-label', 'Why it self-heals'), h('p', null, e.why || 'The judge gave no reason.'));
    out.push(why);
    if (r.kind === 'guarded') {
      const g = placeOf(e.why), box = h('div', 'sh-guard');
      box.append(h('p', 'sh-label', 'Guarded by'), g ? window.DASH_APP.text.codeEl(e.repoUrl, g, new Set(), 'sh-file').el : h('span', null, `the guard is ${NOT_READ}`));
      out.push(box);
    }
    const proof = proofOf(e);
    out.push(h('p', 'sh-label', 'Proof'), h('pre', 'sh-proof', proof || `Proof ${NOT_READ}`));
    const hist = h('ol', 'sh-history'), step = (s, t) => { const li = h('li', null, s); if (t) li.append(' ', ctx.since(t, ' ago')); hist.append(li); };
    step(`Found in the review of ${fromOf(e)}`, e.time);
    step(`Judged ${r.kind ? NAMES[r.kind].toLowerCase() : e.effect || 'self-heals'}`);
    step(r.seen ? `Seen again ${r.seen}×, last` : 'Not seen again yet', r.seen ? e.seen : null);
    step(r.left === null ? `Leaves the list: ${NOT_READ}` : `Leaves the list in ${plural(r.left, 'day', 'days')} unless it is seen again`);
    out.push(h('p', 'sh-label', 'History'), hist);
    const acts = h('div', 'sh-acts'), up = h('button', 'btn', 'Move up to harm'), drop = h('button', 'btn btn-quiet', 'Drop now');
    up.type = 'button'; up.dataset.act = 'harm'; up.disabled = S.busy;
    drop.type = 'button'; drop.dataset.act = 'drop'; drop.disabled = S.busy;
    ctx.twice(up, 'spend', 'Click again to file its own follow-up card', () => send([r], 'harm'));
    ctx.twice(drop, 'final', 'Click again to drop it now', () => send([r], 'drop'));
    acts.append(up, drop);
    out.push(acts, h('p', 'sh-hint', 'Move up to harm when it shows up in real logs or records. It then gets its own follow-up card at once.'));
    return out;
  }
  function footEl(m, n) {
    const out = [h('span', 'sh-showing', `Showing ${n} of ${m.es.length}`)];
    if (!m.dropped.length) return out;
    // It counts every entry the list it opens holds: expired, dropped by the owner or moved up to harm (each says which).
    const b = h('button', 'btn btn-quiet sh-dropped-link', `Dropped entries (${m.dropped.length}) ›`);
    b.type = 'button'; b.dataset.focus = 'dropped'; b.setAttribute('aria-expanded', String(S.dropOpen));
    b.addEventListener('click', () => { S.dropOpen = !S.dropOpen; drawEntries(); });
    out.push(b);
    if (S.dropOpen) {
      const ul = h('ul', 'sh-dropped'), WHY = { expired: 'expired', dropped: 'dropped by you', harm: 'moved up to harm' };
      m.dropped.slice().sort((a, b2) => String(b2.dropped.time).localeCompare(String(a.dropped.time))).forEach((e) => {
        const li = h('li', null);
        li.append(h('span', 'sh-row-title', titleOf(e)), ' ', h('span', 'sh-from', `from ${fromOf(e)}`), ' ',
          h('span', 'sh-gone-why', `${WHY[e.dropped.why] || e.dropped.why}${e.dropped.filed ? ` as ${typeof e.dropped.filed === 'number' ? `#${e.dropped.filed}` : e.dropped.filed}` : ''}`),
          S.ctx.since(e.dropped.time, ' ago'));
        ul.append(li);
      });
      out.push(ul);
    }
    return out;
  }
  // POST /control heals <harm | drop> <ids>, a project at a time, at most HARM_MAX (a card each) or DROP_MAX ids a
  // request, one after another; the first refusal stops the rest. An entry the host took is gone from the page at once.
  function send(rs, act) {
    const ctx = S.ctx, steps = [], by = new Map();
    rs.forEach((r) => by.set(r.e.repo, (by.get(r.e.repo) || []).concat(r)));
    by.forEach((xs, repo) => { for (let i = 0; i < xs.length; i += act === 'harm' ? HARM_MAX : DROP_MAX) steps.push([repo, xs.slice(i, i + (act === 'harm' ? HARM_MAX : DROP_MAX))]); });
    S.busy = true; S.note = 'Sending…'; drawEntries();
    const said = [];
    const go = (i) => {
      if (i >= steps.length) return Promise.resolve(true);
      const [repo, xs] = steps[i];
      return ctx.post('control', { action: 'heals', args: [act].concat(xs.map((r) => r.e.id)), repo })
        .then((res) => res.text().then((t) => ({ ok: res.ok, said: String(t).trim() || `the build machine answered ${res.status}` })),
          () => ({ ok: false, said: 'the build machine did not answer. Make sure that it is on. Then try again' }))
        .then((a) => {
          said.push(a.said);
          if (!a.ok) { S.note = `${act === 'harm' ? 'Not moved up' : 'Not dropped'}: ${a.said}`; return false; }
          xs.forEach((r) => { S.gone.add(r.key); S.checked.delete(r.key); if (S.sel === r.key) S.sel = null; });
          return go(i + 1);
        });
    };
    go(0).then((ok) => {
      if (ok) S.note = `${act === 'harm' ? 'Moved up to harm' : 'Dropped'}: ${said.join('; ')}`;
      S.busy = false;
      ctx.redraw();
    });
  }

  // ---- the docs list ----
  function docsEl(m) {
    const box = h('section', 'sh-docs');
    box.dataset.part = 'docs';
    box.append(h('h3', 'sh-sub', `Docs (${m.docs.length})`), h('p', 'sh-lede', 'Guides and READMEs that leave out or misdescribe what the code does. No entry expires.'));
    areasOf(m.docs).forEach((a) => {
      const place = areaOf(a.area), sec = h('div', 'sh-docs-area'), head = h('p', 'sh-docs-head');
      sec.dataset.area = a.area || '';
      head.append(h('span', 'sh-group', place.group), h('strong', null, place.name), h('span', 'sh-area-n', String(a.rs.length)));
      if (m.many) head.append(S.ctx.tag(a.repo));
      const ul = h('ul', 'sh-rows');
      a.rs.sort((x, y) => y.time - x.time).forEach((r) => {
        const li = h('li', 'sh-row sh-doc'), main = h('div', 'sh-row-main'), t = h('p', 'sh-open');
        t.append(pTag(r.level), h('span', 'sh-row-title', r.title));
        const meta = h('p', 'sh-row-meta');
        meta.append(h('code', 'sh-at', r.place || `file ${NOT_READ}`), h('span', 'sh-from', `from ${fromOf(r.e)}`));
        main.append(t, meta);
        li.append(main);
        ul.append(li);
      });
      sec.append(head, ul);
      box.append(sec);
    });
    return box;
  }

  function render(el, d, ctx) {
    S.ctx = ctx;
    S.at = typeof ctx.updatedAt === 'function' ? ctx.updatedAt() : null;
    // An entry moved or dropped here is hidden until a snapshot no longer lists it; then it may come back as listed again.
    const live = new Set(listsOf(d).flatMap((x) => list(x.entries).filter(Boolean).map(keyOf)));
    S.gone.forEach((k) => { if (!live.has(k)) S.gone.delete(k); });
    const now = ctx.now(), m = model(d, now);
    S.m = m;
    S.checked.forEach((k) => { if (!m.es.some((r) => r.key === k)) S.checked.delete(k); });
    if (S.sel !== null && !m.es.some((r) => r.key === S.sel)) S.sel = null;
    const entries = h('section', 'sh-entries'), split = h('div', 'sh-split'), side = h('div', 'sh-list');
    const tools = toolbar(), note = h('p', 'sh-note'), bar = h('div', 'sh-bar'), rows = h('ul', 'sh-rows'), foot = h('div', 'sh-foot'), detail = h('aside', 'sh-detail');
    note.setAttribute('aria-live', 'polite');
    bar.setAttribute('role', 'region'); bar.setAttribute('aria-label', 'The entries checked');
    detail.setAttribute('aria-label', 'The entry picked');
    S.parts = { root: entries, chips: tools.querySelector('.sh-chips'), rows, detail, bar, foot, note };
    side.append(bar, rows, foot);
    split.append(side, detail);
    entries.append(h('h3', 'sh-sub', 'Entries'), tools, note, split);
    const areas = h('section', 'sh-areas'), grid = h('div', 'sh-area-grid');
    areasOf(m.es).forEach((a) => grid.append(areaCard(a, m.many)));
    areas.append(h('h3', 'sh-sub', 'By area'), grid);
    const k = focusOf();
    el.replaceChildren(headEl(m), tilesEl(m, now), areas, entries);
    if (m.docs.length) el.append(docsEl(m));
    drawEntries();
    refocus(k);
  }
  const healsCount = (d) => liveOf(d).length;
  window.DASH_APP.part('heals-page', () => ({
    id: 'selfheals',
    title: 'Self-heals',
    size: 'full',
    widths: ['full'],
    tab: 'selfheals',
    part: 'declined',
    projects: true,
    rows: 'all',
    rowSelector: '.sh-row',
    count: healsCount,
    attention: healsCount,
    isEmpty: (d) => !listsOf(d).some((x) => list(x.entries).length || list(x.docs && x.docs.entries).length || list(x.dropped).length),
    empty(el, ctx) {
      el.append(ctx.state('empty', 'The Self-heals list is empty', 'This page lists the review findings whose failure heals by itself: a card waits longer, a step runs again, or text is wrong until the next turn. Conveyor does not build them one by one: a batch card fixes an area\'s entries together. When a review sorts a finding so, it shows here.'));
    },
    error(el, message, ctx) { el.append(ctx.state('error', 'The Board could not read the self-heals list', message)); },
    render,
  }));
})();
