// SPDX-License-Identifier: Apache-2.0
// The Self-heals tab (issue 1562): the self-heals list of each project on a page of its own, after Benchmarks, drawn
// from the Declined part's heals (panels/declined.js registers it). Its parts, top to bottom:
//   the title line, with the days an entry stays unseen (the Rules setting healsdays, as the record gives it) and a link
//     to that setting, when the list was read (kept through a failed read, with the list it read then), and for each
//     project when the sort of the queued follow-ups last ran and how many it moved, or that it has not run; under the
//     title, "What is a self-heal?", closed at first (aboutEl, issue 1622);
//   five tiles: on the list, areas ready to batch (READY entries or more), seen again in the last 7 days, leaving in
//     SOON days or less, and moved up to harm in the last 30 days (the dropped record's harm entries, and the
//     entries back on the list whose expired mark is a move up to harm); a click on one of the last three filters the
//     entries to what it counts, or, for harm, opens the dropped entries with its entries alone (issue 1691);
//   a card for each area (its group and name from its label, its count, an age bar in three parts of the days, the kinds
//     with their counts, and how far it is from a batch); a click on a kind pill filters the entries to that area's
//     entries of that kind (issue 1692);
//   the entries, a list beside a detail panel (stacked under it at phone width, app.css): search, sort and a filter
//     chip for each kind; a row is picked by a click and shown in the panel; checked rows get a bar with Move up to harm.
//     Move up to harm (`conveyor.sh heals harm`, a card each: confirmed by a second click) and Drop now (`heals drop`,
//     also confirmed) take an entry off the page at once; the dropped entries are under the list's footer;
//   the docs list by area, whose entries never expire (no days-left ring);
//   the batch sheet, drawn in place of the page: an area card's Review batch, the bar's File a batch card, the detail
//     panel's Add to the <area> batch and a docs area's File docs sweep card open it. The owner keeps or leaves out each
//     entry (and adds entries of other areas of that project), edits the card's title and level, and files it held or
//     queued: `conveyor.sh heals batch|docs <area> --held|--queue --prio P<n> --title <t> <id>...`, the kept entries alone.
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
  const CARDS_DOC = 'https://github.com/pushprove-max/conveyor-belt/blob/main/docs/cards.md#harm-or-self-heals';
  // What the owner did here, through every redraw: the search, sort, kind chip, the row shown in the detail panel, the
  // rows checked, the entries moved or dropped here (gone: hidden until a snapshot no longer lists them), the last
  // answer of the host (note) and whether the dropped entries are open. tile: the tile pressed (seen, leaving or harm),
  // else null. pill: the area card's kind pill pressed ({ id, repo, area, kind }), else null; it sets kind too.
  // sheet: the batch sheet open, else null.
  const S = { q: '', sort: 'leaves', kind: 'all', tile: null, pill: null, sel: null, checked: new Set(), gone: new Set(), note: '', dropOpen: false, aboutOpen: false, busy: false, ctx: null, m: null, at: null, el: null, sheet: null };
  const list = (v) => (Array.isArray(v) ? v : []);
  const num = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : null);
  const plural = (k, one, many) => `${k} ${k === 1 ? one : many}`;
  const keyOf = (e) => `${e.repo}:${e.id}`;
  const MARKS = /^(?:\[[^\]]*\]\s*)*/;
  const PLACE = /[A-Za-z0-9_./-]+:[0-9]+(?:[–-][0-9]+)?/;
  const text = (e) => String(e.finding || '');
  // A finding's or a reason's words s, of entry e, drawn into el as the Declined panel draws a finding (app.js
  // findingText): a sentence a line, text in backticks and bare file paths as code spans, no backtick shown. A file and
  // line is a link to GitHub, unless linkless (text inside a button, where a link would also open the row).
  const said = (el, s, e, linkless) => {
    const T = window.DASH_APP.text, t = String(s || '');
    return T.fill(el, t, linkless ? null : e.repoUrl, new Set(T.pathsIn(t)), 'declined');
  };
  // Its level, of the marks that lead it (after an audit's number, R1, which may come first).
  const levelOf = (e) => { const m = /\[P([0-3])\]/.exec(MARKS.exec(text(e).replace(/^R[0-9]+\s+/, ''))[0]); return m ? `P${m[1]}` : null; };
  const placeOf = (s) => { const m = PLACE.exec(String(s || '')); return m ? m[0] : null; };
  // Its proof: after "Proof:", or an audit's "- How:" section, up to the audit's next section (- Fix:, - Test:, - Raised on).
  const proofOf = (e) => { const m = /(?:\bproof:|\s- how:)\s*([\s\S]+?)(?=\s+- (?:fix:|test:|raised on\b)|$)/i.exec(text(e)); return m ? m[1].trim() : null; };
  // An audit's fix: its "- Fix:" section, up to its next.
  const fixOf = (e) => { const m = /\s- fix:\s*([\s\S]+?)(?=\s+- (?:test:|raised on\b)|$)/i.exec(text(e)); return m ? m[1].trim() : null; };
  const isAudit = (e) => /^R[0-9]+\s/.test(text(e).replace(MARKS, ''));
  // The finding without its marks, audit number, place (an audit quotes it in backticks) and Proof or audit sections:
  // what it says is wrong. A place in backticks goes with all it quotes (`file:12 (t_case)`). The row shows only the
  // first place as its place, so each other place the quote names (`a.sh:3, b.sh:9`) goes after what it says, which a
  // narrow row clips last: "... (also at `b.sh:9`)".
  const leadOf = (e) => {
    const s = text(e).replace(MARKS, '').replace(/^R[0-9]+\s+/, '').replace(MARKS, '');
    const m = /^(?:`([A-Za-z0-9_./-]+:[0-9]+(?:[–-][0-9]+)?[^`]*)`|[A-Za-z0-9_./-]+:[0-9]+(?:[–-][0-9]+)?):?\s+/.exec(s);
    return { s, m, more: m && m[1] ? (m[1].match(new RegExp(PLACE.source, 'g')) || []).slice(1) : [] };
  };
  const titleOf = (e) => {
    const { s, m, more } = leadOf(e);
    const what = (m ? s.slice(m[0].length) : s).replace(/(?:[.:;]?\s*\bproof:|\s+- (?:how|fix|test):)[\s\S]*$/i, '').trim();
    return what ? what + (more.length ? ` (also at ${more.map((p) => `\`${p}\``).join(', ')})` : '') : text(e);
  };
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
      level: levelOf(e), title: titleOf(e), place: placeOf(text(e)), also: leadOf(e).more, seen: num(e.sightings) || 0, time: Date.parse(e.time) || 0 };
  }
  const listsOf = (d) => list(d && d.heals).filter((x) => x && typeof x === 'object');
  const liveOf = (d) => listsOf(d).flatMap((x) => list(x.entries).filter((e) => e && !S.gone.has(keyOf(e))));
  function model(d, now) {
    const lists = listsOf(d);
    return { lists, now, many: new Set(lists.map((x) => x.repo)).size > 1,
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
  // What each tile counts, and so what a click on it shows (issue 1691): the one test for both, so they cannot differ.
  // An entry with no sighting date is not in Seen again; one with no days left is not in Leave in 7 days.
  const TILES = {
    seen: (r, m) => r.seen > 0 && Date.parse(r.e.seen) >= m.now - LATELY * DAY,
    leaving: (r) => r.left !== null && r.left <= SOON,
  };
  // The moves up to harm of the last HARMED days: the dropped record's harm entries, and the entries a review listed
  // again whose expired mark is a move up to harm (each with that mark as its dropped record, to draw it the same way).
  const harmsOf = (m) => m.dropped.concat(m.lists.flatMap((x) => list(x.entries).filter((e) => e && e.expired).map((e) => ({ ...e, dropped: e.expired }))))
    .filter((e) => e.dropped.why === 'harm' && Date.parse(e.dropped.time) >= m.now - HARMED * DAY);
  const TILE_SAID = { seen: `seen again, last ${LATELY} days`, leaving: `leave in ${SOON} days`, harm: `moved up to harm, last ${HARMED} days, in Dropped entries` };
  // An area card's kind pill counts the entries of one project, area and kind: no area and kind not read are '' here.
  const pillId = (repo, area, kind) => `${repo}|${area || ''}|${kind || ''}`;
  const shown = (m) => m.es.filter((r) => matches(r) && (S.kind === 'all' || r.kind === S.kind) && (!TILES[S.tile] || TILES[S.tile](r, m))
    && (!S.pill || pillId(r.e.repo, r.e.area, r.kind) === S.pill.id)).sort(SORT[S.sort]);

  // ---- small marks ----
  const h = (...a) => S.ctx.h(...a);
  const pTag = (level) => { const t = h('span', `sh-p${level === 'P0' || level === 'P1' ? ' is-high' : ''}`, level || 'P?'); if (!level) t.title = 'level not read'; return t; };
  const kindPill = (kind) => { const p = h('span', `sh-kind sh-k-${kind || 'none'}`, kind ? NAMES[kind] : `kind ${NOT_READ}`); p.dataset.kind = kind || ''; return p; };
  // The judge's reason and the proof of entry e, each a line under a row that has no detail panel (a Docs row, a batch
  // sheet row, a dropped entry); none for one it does not give.
  const notesOf = (e) => {
    const proof = proofOf(e), out = [];
    if (e.why) out.push(said(h('p', 'sh-fix sh-note-why'), `Why: ${e.why}`, e));
    if (proof) out.push(said(h('p', 'sh-fix sh-note-proof'), `Proof: ${proof}`, e));
    return out;
  };
  const daysLeft = (r) =>(r.left === null ? NOT_READ : `${r.left} d left`);
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
  // "What is a self-heal?" (issue 1622): closed at first, so the list stays at the top; S.aboutOpen keeps it open
  // through each redraw. Its words follow docs/cards.md, "Harm or self-heals". days: the Rules setting, else null.
  function aboutEl(days) {
    const box = h('details', 'sh-about'), sum = h('summary', null, 'What is a self-heal?');
    sum.dataset.focus = 'about';
    box.open = S.aboutOpen;
    box.addEventListener('toggle', () => { S.aboutOpen = box.open; });
    const ul = h('ul', 'sh-about-list');
    [['what', 'A self-heal is a failure that fixes itself: a card waits longer, a step runs again, or wrong text is corrected at the next poll or turn. Nothing stays broken.'],
      ['harm', 'The judge sorts each review finding that it accepts by what its failure does. A harm finding gets a follow-up card at once. Harm is: data is lost or written wrong, wrong code lands or pushes, a check passes that should fail, the belt is stuck until a person frees it, a step stops and nobody is told, private text is published, or a security hole opens.'],
      ['kinds', 'Three kinds come to this list: Self-heals; Cleanup, when the fix changes nothing that the code does; and Already guarded, when another check already stops the bad result.'],
      ['round', 'A finding on this list does not stop a card and gets no fix round. A batch card, filed from this page, fixes the entries of an area together.'],
      ['drop', `An entry that nobody fixes, files in a batch card or sees again for ${days ? `${days} days` : 'the days of the setting'} leaves the list. The days are the Rules setting Self-heals expiry. The dropped entries keep each entry that leaves.`],
      ['logs', 'A finding seen in real logs or records is harm, also when it heals itself. A finding with no kind is harm.'],
    ].forEach(([k, text]) => { const li = h('li', null, text); li.dataset.about = k; ul.append(li); });
    const more = h('p', 'sh-about-more'), a = h('a', null, 'Harm or self-heals');
    a.href = CARDS_DOC; a.dataset.focus = 'about-link'; a.target = '_blank'; a.rel = 'noopener';
    more.append('The full rules: ', a, ' in docs/cards.md.');
    box.append(sum, ul, more);
    return box;
  }
  function headEl(m) {
    const ctx = S.ctx, box = h('div', 'sh-head'), side = h('div', 'sh-head-side'), days = daysSaid(m);
    const title = h('div', 'sh-head-main');
    title.append(h('h3', 'sh-title', 'Self-heals list'), h('p', 'sh-lede', 'Real findings whose failure heals by itself: a card waits longer, a step runs again, or text is wrong until the next turn. Conveyor does not build them one by one. Fix them in a batch card for each area, or move one up to harm when it shows up in real logs.'));
    title.append(aboutEl(days));
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
    side.append(...sortedOf(m.lists, ctx));
    box.append(title, side);
    return box;
  }
  // When the sort of the queued follow-ups last ran and how many it moved (each project's sorted), or that it has not: a
  // line a project, on the page and in its empty state alike (a sort that moved nothing leaves the lists empty).
  function sortedOf(lists, ctx) {
    const many = new Set(lists.map((x) => x.repo)).size > 1;
    return lists.map((x) => {
      const s = x.sorted, line = h('p', 'sh-sorted');
      if (many) line.append(ctx.tag(x.repo), ' ');
      if (s && s.time) line.append('The sort of the queued follow-ups ran ', ctx.since(s.time, ' ago'), `, and moved ${s.moved} of ${s.items} to the lists${s.failed ? ` (its judge failed: ${s.failed})` : ''}.`);
      else line.append('The sort of the queued follow-ups has not run yet.');
      return line;
    });
  }
  function tilesEl(m) {
    const box = h('div', 'sh-tiles'), areas = areasOf(m.es);
    // A card with no GitHub issue (issue 0) adds no issue.
    const issues = new Set(m.es.filter((r) => r.e.issue && !isAudit(r.e)).map((r) => r.e.issue)), audits = new Set(m.es.filter((r) => r.e.issue && isAudit(r.e)).map((r) => r.e.issue));
    // A tile with a tone is a button: a click shows what it counts (a second click ends the tile filter); the tile pressed
    // is S.tile, kept through every redraw.
    const tile = (k, label, n, sub, tone) => {
      const t = h(tone ? 'button' : 'div', `sh-tile${tone ? ` is-${tone}` : ''}`);
      t.dataset.tile = k;
      t.append(h('span', 'sh-tile-label', label), h('span', 'sh-tile-n', String(n)), h('span', 'sh-tile-sub', sub));
      if (tone) {
        t.type = 'button'; t.dataset.focus = `tile:${k}`; t.setAttribute('aria-pressed', String(S.tile === k));
        t.addEventListener('click', () => pickTile(S.tile === k ? null : k));
      }
      box.append(t);
    };
    const days = daysSaid(m) || NOT_READ;
    tile('on', 'On the list', m.es.length, `from ${plural(issues.size, 'issue', 'issues')} and ${plural(audits.size, 'audit', 'audits')}`);
    tile('ready', 'Ready to batch', areas.filter((a) => a.rs.length >= READY).length, `areas with ${READY} or more entries`);
    tile('seen', `Seen again, last ${LATELY} days`, m.es.filter((r) => TILES.seen(r, m)).length, `a sighting resets its ${days} days`, 'ok');
    tile('leaving', `Leave in ${SOON} days`, m.es.filter((r) => TILES.leaving(r, m)).length, 'kept in Dropped, never erased', 'warn');
    tile('harm', `Moved up to harm, ${HARMED} days`, harmsOf(m).length, 'seen in real logs', 'bad');
    return box;
  }
  // Press a tile (or none): the harm tile opens the dropped entries with its entries alone. A tile ends a pressed kind
  // pill (and its kind), as a pill ends a pressed tile: one of them filters at a time, so each shows all it counts.
  function pickTile(k) {
    S.tile = k;
    if (S.pill) { S.pill = null; S.kind = 'all'; }
    if (k === 'harm') S.dropOpen = true;
    drawEntries();
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
    // A pill is a button: its kind and its count are two parts (app.css spaces them), and a click filters the entries
    // to what it counts (a second click ends the filter).
    KINDS.concat([[null]]).forEach(([k]) => {
      if (!kinds.has(k)) return;
      const id = pillId(a.repo, a.area, k), p = h('button', `sh-kind sh-k-${k || 'none'}`);
      p.type = 'button'; p.dataset.kind = k || ''; p.dataset.pill = id; p.dataset.focus = `pill:${id}`; p.setAttribute('aria-pressed', String(!!S.pill && S.pill.id === id));
      const label = k ? NAMES[k] : `kind ${NOT_READ}`, n = kinds.get(k);
      // The parts' text holds no space, so a screen reader is given the name with one.
      p.setAttribute('aria-label', `${label}: ${n}`);
      p.append(h('span', 'sh-kind-name', label), h('span', 'sh-kind-n', String(n)));
      p.addEventListener('click', () => pickPill(S.pill && S.pill.id === id ? null : { id, repo: a.repo, area: a.area, kind: k }));
      pills.append(p);
    });
    const foot = h('p', `sh-area-foot${n >= READY ? ' is-ready' : ''}`, n >= READY ? '✓ Ready to batch' : `${READY - n} more to batch`);
    const review = h('button', `btn${n >= READY ? ' btn-primary' : ''} sh-area-batch`, 'Review batch');
    review.type = 'button'; review.dataset.act = 'heals-batch';
    review.addEventListener('click', () => openSheet('batch', a.repo, a.area, a.rs.slice().sort(byLeft).map((r) => r.key)));
    card.append(top, ageBar(a), pills, foot, review);
    return card;
  }
  // Press a kind pill (or none): its kind is the kind chip's too; with none, every kind shows again. A pill ends a
  // pressed tile, so the entries shown are all the entries the pill counts.
  function pickPill(p) {
    S.pill = p;
    if (p) S.tile = null;
    S.kind = p ? p.kind : 'all';
    drawEntries();
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
      b.addEventListener('click', () => { S.kind = k; S.pill = null; drawEntries(); });
      chips.append(b);
    });
  }
  function rowEl(r, many) {
    const li = h('li', `sh-row${S.sel === r.key ? ' is-selected' : ''}`), box = h('input', 'sh-check'), open = h('button', 'sh-open');
    li.dataset.key = r.key;
    if (S.sel === r.key) open.setAttribute('aria-current', 'true');
    box.type = 'checkbox'; box.dataset.focus = `check:${r.key}`; open.dataset.focus = `open:${r.key}`; box.checked = S.checked.has(r.key); box.setAttribute('aria-label', `Select: ${r.title}`);
    box.addEventListener('change', () => { if (box.checked) S.checked.add(r.key); else S.checked.delete(r.key); drawBar(); });
    open.type = 'button'; open.title = text(r.e).replace(/`/g, '');
    open.append(pTag(r.level), said(h('span', 'sh-row-title'), r.title, r.e, true));
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
  // a chip, the Dropped button, or the summary or guide link of "What is a self-heal?" that the owner works from the
  // keyboard keeps the focus when the list or the page is drawn again.
  const focusOf = () => { const a = document.activeElement; return a && a.dataset && a.closest('.sh-entries, .sh-about, .sh-tiles, .sh-areas') ? a.dataset.focus || null : null; };
  const refocus = (k) => {
    const el = k && Array.from(S.el.querySelectorAll('[data-focus]')).find((x) => x.dataset.focus === k);
    if (el && document.activeElement !== el) el.focus({ preventScroll: true });
  };
  function drawEntries() {
    const m = S.m, rs = shown(m), p = S.parts, k = focusOf();
    drawChips(m);
    S.el.querySelectorAll('button.sh-tile').forEach((t) => t.setAttribute('aria-pressed', String(S.tile === t.dataset.tile)));
    p.filter.replaceChildren();
    if (S.tile) {
      const x = h('button', 'btn btn-quiet sh-filter-clear', '× clear');
      x.type = 'button'; x.dataset.focus = 'tile-clear'; x.setAttribute('aria-label', 'Clear the tile filter');
      // The clear control goes with the filter line, so the focus goes to the tile it cleared.
      x.addEventListener('click', () => { const was = S.tile; pickTile(null); refocus(`tile:${was}`); });
      p.filter.append(`Showing: ${TILE_SAID[S.tile]} `, x);
    }
    S.el.querySelectorAll('button.sh-kind[data-pill]').forEach((t) => t.setAttribute('aria-pressed', String(!!S.pill && S.pill.id === t.dataset.pill)));
    if (S.pill) {
      const was = S.pill.id, x = h('button', 'btn btn-quiet sh-filter-clear', '× clear');
      x.type = 'button'; x.dataset.focus = 'pill-clear'; x.setAttribute('aria-label', 'Clear the area and kind filter');
      x.addEventListener('click', () => { pickPill(null); refocus(`pill:${was}`); });
      const said = `${areaOf(S.pill.area).name}${m.many ? ` (${S.pill.repo})` : ''}, ${S.pill.kind ? NAMES[S.pill.kind] : `kind ${NOT_READ}`}`;
      p.filter.append(`Showing: ${said} `, x);
    }
    p.filter.hidden = !S.tile && !S.pill;
    p.rows.replaceChildren(...rs.map((r) => rowEl(r, m.many)));
    if (!rs.length) p.rows.append(h('li', 'sh-none', m.es.length || TILES[S.tile] ? 'No entry matches this search, kind or tile.' : 'No entry is on the list now.'));
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
    const batch = h('button', 'btn btn-primary', 'File a batch card'), up = h('button', 'btn', 'Move up to harm'), clear = h('button', 'btn btn-quiet', 'Clear');
    // The sheet files for one project and is labelled with one area: that of the most entries checked. The checked
    // entries of its other areas go in too. Rows checked in two projects file no card: the bar says so.
    const repos = new Set(rs.map((r) => r.e.repo));
    batch.type = 'button'; batch.dataset.act = 'heals-batch'; batch.disabled = repos.size > 1;
    batch.addEventListener('click', () => {
      const by = new Map();
      rs.forEach((r) => { const k = r.e.area || ''; by.set(k, (by.get(k) || []).concat(r)); });
      const top = Array.from(by.values()).sort((x, y) => y.length - x.length)[0][0];
      openSheet('batch', top.e.repo, top.e.area || null, rs.map((r) => r.key));
    });
    up.type = 'button'; up.dataset.act = 'harm'; up.disabled = S.busy;
    S.ctx.twice(up, 'spend', `Click again to file ${plural(rs.length, 'follow-up card', 'follow-up cards')}`, () => send(rs, 'harm'));
    clear.type = 'button'; clear.dataset.act = 'clear';
    clear.addEventListener('click', () => { S.checked.clear(); drawEntries(); });
    bar.append(h('strong', 'sh-bar-n', `${rs.length} selected`), batch, up, clear);
    if (repos.size > 1) bar.append(h('span', 'sh-hint','A batch card is for one project. Check the entries of one project only.'));
  }
  function detailEl(r) {
    if (!r) return [h('p', 'sh-detail-none', 'Pick an entry to see why it self-heals, its proof and its history.')];
    const ctx = S.ctx, e = r.e, out = [], top = h('div', 'sh-detail-top');
    top.append(pTag(r.level), kindPill(r.kind), h('span', `sh-leaves${r.left !== null && r.left <= SOON ? ' is-soon' : ''}`, r.left === null ? `leaves in: ${NOT_READ}` : `leaves in ${plural(r.left, 'day', 'days')}`));
    out.push(top, said(h('h4', 'sh-detail-title'), r.title, e));
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
    why.append(h('p', 'sh-label', 'Why it self-heals'), said(h('p', null), e.why || 'The judge gave no reason.', e));
    out.push(why);
    if (r.kind === 'guarded') {
      const g = placeOf(e.why), box = h('div', 'sh-guard');
      box.append(h('p', 'sh-label', 'Guarded by'), g ? window.DASH_APP.text.codeEl(e.repoUrl, g, new Set(), 'sh-file').el : h('span', null, `the guard is ${NOT_READ}`));
      out.push(box);
    }
    const proof = proofOf(e);
    out.push(h('p', 'sh-label', 'Proof'), said(h('div', 'sh-proof'), proof || `Proof ${NOT_READ}`, e));
    const hist = h('ol', 'sh-history'), step = (s, t) => { const li = h('li', null, s); if (t) li.append(' ', ctx.since(t, ' ago')); hist.append(li); };
    step(`Found in the review of ${fromOf(e)}`, e.time);
    step(`Judged ${r.kind ? NAMES[r.kind].toLowerCase() : e.effect || 'self-heals'}`);
    step(r.seen ? `Seen again ${r.seen}×, last` : 'Not seen again yet', r.seen ? e.seen : null);
    step(r.left === null ? `Leaves the list: ${NOT_READ}` : `Leaves the list in ${plural(r.left, 'day', 'days')} unless it is seen again`);
    out.push(h('p', 'sh-label', 'History'), hist);
    const acts = h('div', 'sh-acts'), add = h('button', 'btn btn-primary', `Add to the ${areaOf(e.area).name} batch`);
    const up = h('button', 'btn', 'Move up to harm'), drop = h('button', 'btn btn-quiet', 'Drop now');
    add.type = 'button'; add.dataset.act = 'heals-batch';
    add.addEventListener('click', () => openSheet('batch', e.repo, e.area || null,
      S.m.es.filter((x) => x.e.repo === e.repo && (x.e.area || null) === (e.area || null)).sort(byLeft).map((x) => x.key)));
    up.type = 'button'; up.dataset.act = 'harm'; up.disabled = S.busy;
    drop.type = 'button'; drop.dataset.act = 'drop'; drop.disabled = S.busy;
    ctx.twice(up, 'spend', 'Click again to file its own follow-up card', () => send([r], 'harm'));
    ctx.twice(drop, 'final', 'Click again to drop it now', () => send([r], 'drop'));
    acts.append(add, up, drop);
    out.push(acts, h('p', 'sh-hint', 'Move up to harm when it shows up in real logs or records. It then gets its own follow-up card at once.'));
    return out;
  }
  function footEl(m, n) {
    const out = [h('span', 'sh-showing', `Showing ${n} of ${m.es.length}`)];
    // With the harm tile pressed, the list it opens holds the harm tile's entries alone.
    const harm = S.tile === 'harm', gone = harm ? harmsOf(m) : m.dropped;
    if (!m.dropped.length && !harm) return out;
    // It counts every entry the list it opens holds: expired, dropped by the owner or moved up to harm (each says which).
    const b = h('button', 'btn btn-quiet sh-dropped-link', `Dropped entries (${gone.length}) ›`);
    b.type = 'button'; b.dataset.focus = 'dropped'; b.setAttribute('aria-expanded', String(S.dropOpen));
    // Closing the list ends the harm tile's filter too: it has nothing left to show. With no dropped entries, this button
    // goes with it, so the focus goes to the harm tile.
    b.addEventListener('click', () => {
      S.dropOpen = !S.dropOpen;
      if (!S.dropOpen && harm) S.tile = null;
      drawEntries();
      if (!S.dropOpen && harm && !m.dropped.length) refocus('tile:harm');
    });
    out.push(b);
    if (S.dropOpen) {
      const ul = h('ul', 'sh-dropped'), WHY = { expired: 'expired', dropped: 'dropped by you', harm: 'moved up to harm' };
      if (!gone.length) ul.append(h('li', 'sh-none', 'No entry matches this tile.'));
      gone.slice().sort((a, b2) => String(b2.dropped.time).localeCompare(String(a.dropped.time))).forEach((e) => {
        const li = h('li', null), meta = h('p', 'sh-row-meta');
        meta.append(h('code', 'sh-at', placeOf(text(e)) || `file ${NOT_READ}`), h('span', 'sh-from', `from ${fromOf(e)}`),
          h('span', 'sh-gone-why', `${WHY[e.dropped.why] || e.dropped.why}${e.dropped.filed ? ` as ${typeof e.dropped.filed === 'number' ? `#${e.dropped.filed}` : e.dropped.filed}` : ''}`),
          S.ctx.since(e.dropped.time, ' ago'));
        li.append(said(h('span', 'sh-row-title'), titleOf(e), e), meta, ...notesOf(e));
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
      const sweep = h('button', 'btn sh-docs-sweep', 'File docs sweep card');
      sweep.type = 'button'; sweep.dataset.act = 'heals-docs';
      sweep.addEventListener('click', () => openSheet('docs', a.repo, a.area, a.rs.map((r) => r.key)));
      head.append(sweep);
      const ul = h('ul', 'sh-rows');
      a.rs.sort((x, y) => y.time - x.time).forEach((r) => {
        const li = h('li', 'sh-row sh-doc'), main = h('div', 'sh-row-main'), t = h('p', 'sh-open');
        t.append(pTag(r.level), said(h('span', 'sh-row-title'), r.title, r.e));
        const meta = h('p', 'sh-row-meta');
        meta.append(h('code', 'sh-at', r.place || `file ${NOT_READ}`), h('span', 'sh-from', `from ${fromOf(r.e)}`));
        main.append(t, meta, ...notesOf(r.e));
        li.append(main);
        ul.append(li);
      });
      sec.append(head, ul);
      box.append(sec);
    });
    return box;
  }

  // ---- the batch sheet ----
  // <list>: batch (the self-heals list) or docs (the docs list); <keys>: the entries it starts with, each kept.
  function openSheet(list, repo, area, keys) {
    S.sheet = { list, repo, area, keys: keys.slice(), keep: new Set(keys), title: null, prio: 'P3', adding: false, note: '' };
    S.ctx.redraw();
    const t = S.el && S.el.querySelector('.sh-sheet-title');
    if (t) t.focus({ preventScroll: true });
  }
  const closeSheet = () => { S.sheet = null; S.ctx.redraw(); };
  // The entries the sheet can hold (its project's, of its list) and those it shows: an entry another filing took off the
  // list leaves it.
  const poolOf = (m, sh) => (sh.list === 'docs' ? m.docs : m.es).filter((r) => r.e.repo === sh.repo);
  function sheetModel(m) {
    const sh = S.sheet, pool = poolOf(m, sh), rs = sh.keys.map((k) => pool.find((r) => r.key === k)).filter(Boolean);
    const kept = rs.filter((r) => sh.keep.has(r.key)), docs = sh.list === 'docs';
    const name = sh.area ? areaOf(sh.area).name : 'no area';
    return { sh, pool, rs, kept, docs, auto: `${docs ? 'Docs sweep' : 'Self-heals batch'}: ${name} (${plural(kept.length, 'entry', 'entries')})` };
  }
  const titleSaid = (v) => (v.sh.title === null ? v.auto : v.sh.title.trim());
  function drawSheet() {
    const k = document.activeElement && document.activeElement.closest && document.activeElement.closest('.sh-sheet') ? document.activeElement.dataset.focus || null : null;
    S.el.replaceChildren(sheetEl(S.m));
    const el = k && Array.from(S.el.querySelectorAll('[data-focus]')).find((x) => x.dataset.focus === k);
    if (el) el.focus({ preventScroll: true });
  }
  // The two filing buttons: off with no entry kept, no title or a filing on its way.
  const fileOff = (v) => S.busy || !v.kept.length || !titleSaid(v);
  function sheetEl(m) {
    const v = sheetModel(m), { sh, docs } = v, place = areaOf(sh.area), box = h('section', 'sh-sheet');
    box.setAttribute('aria-label', docs ? 'File a docs sweep card' : 'File a batch card');
    const crumb = h('nav', 'sh-crumb'), back = h('button', 'btn btn-quiet sh-crumb-list', 'Self-heals list');
    crumb.setAttribute('aria-label', 'Where this sheet is');
    back.type = 'button'; back.addEventListener('click', closeSheet);
    crumb.append(back, ' › ', h('span', null, place.group), ' › ', h('span', null, place.name));
    const head = h('div', 'sh-sheet-head'), main = h('div', 'sh-head-main'), acts = h('div', 'sh-acts');
    const title = h('h3', 'sh-title sh-sheet-title', docs ? 'File a docs sweep card' : 'File a batch card');
    title.tabIndex = -1;
    main.append(title, h('p', 'sh-lede', docs ? 'One card makes the docs match what users see, for the entries you keep here.'
      : 'One card fixes the entries you keep here together. An entry you leave out stays on the list.'));
    const cancel = h('button', 'btn btn-quiet', 'Cancel'), held = h('button', 'btn', 'File held'), queue = h('button', 'btn btn-primary', `File and queue · ${plural(v.kept.length, 'entry', 'entries')}`);
    cancel.type = 'button'; cancel.dataset.act = 'sheet-cancel'; cancel.addEventListener('click', closeSheet);
    [[held, 'held', 'Click again to file it held'], [queue, 'queue', 'Click again to file and queue it']].forEach(([b, how, ask]) => {
      b.type = 'button'; b.dataset.act = `sheet-${how}`; b.disabled = fileOff(v);
      S.ctx.twice(b, 'spend', ask, () => fileSheet(how === 'held'));
    });
    acts.append(cancel, held, queue);
    head.append(main, acts);
    const note = h('p', 'sh-note', sh.note);
    note.setAttribute('aria-live', 'polite');
    const split = h('div', 'sh-split sh-sheet-split');
    split.append(sheetEntries(v), sheetCard(v, held, queue));
    box.append(crumb, head, note, split);
    return box;
  }
  function sheetEntries(v) {
    const { sh, docs } = v, side = h('div', 'sh-list sh-sheet-entries'), top = h('div', 'sh-sheet-top');
    const all = h('button', 'btn btn-quiet', 'Keep all'), more = h('button', 'btn btn-quiet', 'Add from other areas');
    all.type = 'button'; all.dataset.act = 'sheet-keep-all'; all.dataset.focus = 'keep-all';
    all.addEventListener('click', () => { v.rs.forEach((r) => sh.keep.add(r.key)); drawSheet(); });
    more.type = 'button'; more.dataset.act = 'sheet-more'; more.dataset.focus = 'more'; more.setAttribute('aria-expanded', String(sh.adding));
    more.addEventListener('click', () => { sh.adding = !sh.adding; drawSheet(); });
    top.append(h('strong', 'sh-sheet-n', `Entries in this card ${v.kept.length} of ${v.rs.length}`), all, more);
    const ul = h('ul', 'sh-rows');
    v.rs.forEach((r) => {
      const on = sh.keep.has(r.key), li = h('li', `sh-row sh-sheet-row${on ? '' : ' is-out'}`), box = h('input', 'sh-check'), main = h('div', 'sh-row-main');
      li.dataset.key = r.key;
      box.type = 'checkbox'; box.checked = on; box.dataset.focus = `keep:${r.key}`; box.setAttribute('aria-label', `Keep in the card: ${r.title}`);
      box.addEventListener('change', () => { if (box.checked) sh.keep.add(r.key); else sh.keep.delete(r.key); drawSheet(); });
      const t = h('p', 'sh-open');
      t.append(h('code', 'sh-key', r.e.id), pTag(r.level), said(h('span', 'sh-row-title'), r.title, r.e));
      const meta = h('p', 'sh-row-meta');
      if (!docs) meta.append(kindPill(r.kind));
      meta.append(h('code', 'sh-at', r.place || `file ${NOT_READ}`), h('span', 'sh-row-area', r.e.area || 'No area'));
      if (!docs) meta.append(h('span', 'sh-left-n', daysLeft(r)));
      main.append(t, meta);
      const fix = fixOf(r.e);
      if (fix) main.append(said(h('p', 'sh-fix'), `Fix: ${fix}`, r.e));
      main.append(...notesOf(r.e));
      li.append(box, main);
      ul.append(li);
    });
    if (!v.rs.length) ul.append(h('li', 'sh-none', 'No entry of this card is on the list now.'));
    side.append(top, ul);
    if (sh.adding) {
      const others = v.pool.filter((r) => (r.e.area || null) !== (sh.area || null) && !sh.keys.includes(r.key)), add = h('ul', 'sh-rows sh-sheet-more');
      add.setAttribute('aria-label', 'Entries of other areas');
      others.forEach((r) => {
        const li = h('li', 'sh-row sh-doc'), main = h('div', 'sh-row-main'), b = h('button', 'btn btn-quiet', 'Add');
        li.dataset.key = r.key;
        main.append(said(h('span', 'sh-row-title'), r.title, r.e), h('p', 'sh-row-meta', r.e.area || 'No area'));
        b.type = 'button'; b.dataset.act = 'sheet-add'; b.setAttribute('aria-label', `Add to the card: ${r.title}`);
        b.addEventListener('click', () => { sh.keys.push(r.key); sh.keep.add(r.key); drawSheet(); });
        li.append(main, b);
        add.append(li);
      });
      if (!others.length) add.append(h('li', 'sh-none', 'No entry of another area is on the list.'));
      side.append(add);
    }
    side.append(h('p', 'sh-sheet-foot', docs ? 'An entry you leave out stays on the docs list.' : 'An entry you leave out stays on the list with its days left.'));
    return side;
  }
  function sheetCard(v, held, queue) {
    const { sh, docs } = v, card = h('aside', 'sh-detail sh-sheet-card'), name = h('input', 'sh-search sh-sheet-name'), prio = h('select', 'sh-sort sh-sheet-prio');
    card.setAttribute('aria-label', 'The card');
    name.type = 'text'; name.maxLength = 200; name.value = sh.title === null ? v.auto : sh.title; name.dataset.focus = 'name';
    // The title is the owner's once edited; until then it follows the count kept. The buttons follow it as it is typed.
    name.addEventListener('input', () => { sh.title = name.value; held.disabled = queue.disabled = fileOff(v); });
    ['P3', 'P2'].forEach((p) => { const o = h('option', null, p); o.value = p; o.selected = sh.prio === p; prio.append(o); });
    prio.dataset.focus = 'prio';
    prio.addEventListener('change', () => { sh.prio = prio.value; });
    const lt = h('label', 'sh-sheet-field', 'Title'), lp = h('label', 'sh-sheet-field', 'Priority');
    lt.append(name); lp.append(prio);
    const dl = h('dl', 'sh-facts'), dd = h('dd', null);
    dd.append(sh.area ? h('code', null, sh.area) : 'none: the entries have no area');
    dl.append(h('dt', null, 'Area label'), dd);
    const files = new Map();
    // Each file an entry names (its place and each other place it quotes), counted once for the entry.
    const fileOf = (p) => p.replace(/:[0-9]+(?:[–-][0-9]+)?$/, '');
    v.kept.forEach((r) => new Set(r.place ? [r.place, ...r.also].map(fileOf) : [`file ${NOT_READ}`]).forEach((f) => files.set(f, (files.get(f) || 0) + 1)));
    const fl = h('ul', 'sh-files');
    Array.from(files).sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0])).forEach(([f, n]) => {
      const li = h('li', null);
      li.append(h('code', 'sh-at', f), h('span', 'sh-files-n', plural(n, 'entry', 'entries')));
      fl.append(li);
    });
    if (!files.size) fl.append(h('li', 'sh-none', 'No entry is kept.'));
    const how = h('div', 'sh-how'), hl = h('ul', null);
    (docs ? ['Each entry is done when the docs match what the code does. The card changes no code.',
      'The card checks each entry against main first. Its reply names an entry that is already fixed or no longer true.']
      : ['Each entry is done when its Proof no longer holds. The card checks each entry against main first. Its reply names an entry that is already fixed or no longer true.',
        'A self-heals entry gets a test that fails without the fix.',
        'For an already guarded entry, the card checks that its guard still stops the outcome. If the guard no longer does, the card fixes it as harm, with a test.'])
      .forEach((s) => hl.append(h('li', null, s)));
    how.append(h('p', 'sh-label', 'How this card is reviewed'), hl);
    card.append(h('h4', 'sh-detail-title', 'The card'), lt, lp, dl, h('p', 'sh-label', 'Files it touches'), fl, how,
      h('p', 'sh-hint', docs ? 'When the card lands, its entries leave the docs list as fixed. If you shut it before it lands, they come back on the docs list.'
        : 'When the card lands, its entries leave the list as fixed. If you shut it before it lands, they come back on the list, and their days start again.'));
    return card;
  }
  // POST /control heals <batch | docs> <area | -> <--held | --queue> --prio P<n> --title <title> <the ids kept>. The
  // host's answer says what it filed and which entries wait; an entry it filed leaves the list with the next snapshot,
  // one that waits for its card stays. A refusal keeps the sheet open with the answer.
  function fileSheet(held) {
    const v = sheetModel(S.m), { sh } = v, ctx = S.ctx;
    if (fileOff(v)) return;
    const args = [sh.list, sh.area || '-', held ? '--held' : '--queue'].concat(['--prio', sh.prio, '--title', titleSaid(v)], v.kept.map((r) => r.e.id));
    S.busy = true; sh.note = 'Sending…'; drawSheet();
    ctx.post('control', { action: 'heals', args, repo: sh.repo })
      .then((res) => res.text().then((t) => ({ ok: res.ok, said: String(t).trim() || `the build machine answered ${res.status}` })),
        () => ({ ok: false, said: 'the build machine did not answer. Make sure that it is on. Then try again' }))
      .then((a) => {
        S.busy = false;
        if (!a.ok) { if (S.sheet === sh) sh.note = `Not filed: ${a.said}`; ctx.redraw(); return; }
        v.kept.forEach((r) => S.checked.delete(r.key));
        if (S.sheet === sh) S.sheet = null;
        S.note = `Filed: ${a.said}`;
        ctx.redraw();
      });
  }

  function render(el, d, ctx) {
    S.ctx = ctx; S.el = el;
    S.at = typeof ctx.updatedAt === 'function' ? ctx.updatedAt() : null;
    // An entry moved or dropped here is hidden until a snapshot no longer lists it; then it may come back as listed again.
    const live = new Set(listsOf(d).flatMap((x) => list(x.entries).filter(Boolean).map(keyOf)));
    S.gone.forEach((k) => { if (!live.has(k)) S.gone.delete(k); });
    const now = ctx.now(), m = model(d, now);
    S.m = m;
    S.checked.forEach((k) => { if (!m.es.some((r) => r.key === k)) S.checked.delete(k); });
    if (S.sel !== null && !m.es.some((r) => r.key === S.sel)) S.sel = null;
    // A pressed pill whose area card is not drawn now (another project picked in Show, or its entries gone) is ended:
    // it would hide every entry, with no pill left to press again.
    if (S.pill && !m.es.some((r) => pillId(r.e.repo, r.e.area, r.kind) === S.pill.id)) { S.pill = null; S.kind = 'all'; }
    if (S.sheet) { drawSheet(); return; }
    const entries = h('section', 'sh-entries'), split = h('div', 'sh-split'), side = h('div', 'sh-list');
    const tools = toolbar(), note = h('p', 'sh-note'), filter = h('p', 'sh-filter'), bar = h('div', 'sh-bar'), rows = h('ul', 'sh-rows'), foot = h('div', 'sh-foot'), detail = h('aside', 'sh-detail');
    note.setAttribute('aria-live', 'polite');
    bar.setAttribute('role', 'region'); bar.setAttribute('aria-label', 'The entries checked');
    detail.setAttribute('aria-label', 'The entry picked');
    S.parts = { root: entries, chips: tools.querySelector('.sh-chips'), filter, rows, detail, bar, foot, note };
    side.append(bar, filter, rows, foot);
    split.append(side, detail);
    entries.append(h('h3', 'sh-sub', 'Entries'), tools, note, split);
    const areas = h('section', 'sh-areas'), grid = h('div', 'sh-area-grid');
    areasOf(m.es).forEach((a) => grid.append(areaCard(a, m.many)));
    areas.append(h('h3', 'sh-sub', 'By area'), grid);
    const k = focusOf();
    el.replaceChildren(headEl(m), tilesEl(m), areas, entries);
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
    empty(el, ctx, d) {
      // An open sheet ends with the list: a later entry must not open it again.
      S.sheet = null; S.ctx = ctx;
      el.append(...sortedOf(listsOf(d), ctx), ctx.state('empty', 'The Self-heals list is empty', 'This page lists the review findings whose failure heals by itself: a card waits longer, a step runs again, or text is wrong until the next turn. Conveyor does not build them one by one: a batch card fixes an area\'s entries together. When a review sorts a finding so, it shows here.'));
    },
    error(el, message, ctx) { el.append(ctx.state('error', 'The Board could not read the self-heals list', message)); },
    render,
  }));
})();
