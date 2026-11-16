// SPDX-License-Identifier: Apache-2.0
// Metrics: what Conveyor measured, each Conveyor on a tab of its own. Its part: {records: [{repo, today, week, prev,
// days, slots}] (today, week and prev each the snapshot's totals, of today, the 7 days and the 7 days before those;
// days the 7 days oldest first; slots today's by hour; each null from a host whose snapshot has none), cards:
// [{repo, card, issue, title, url, state, at, metrics}] | null}. A record shows as headline tiles (each with its
// 7 days as a sparkline and the change on the 7 days before), then charts drawn as inline SVG, then every figure in
// a table one click away (All numbers), then its recent cards five at a time. A card's row opens (click) to its
// step timeline. A reading that was not taken shows as "—", never as 0 and never as "missing".
(function () {
  const NONE = '—';
  const SVG = 'http://www.w3.org/2000/svg';
  const num = (v) => typeof v === 'number' && Number.isFinite(v);
  const int = (v) => (num(v) ? Math.round(v).toLocaleString('en-US') : NONE);
  const pct = (v) => (num(v) ? `${Math.round(v * 1000) / 10}%` : NONE);
  const tokens = (v) => (!num(v) ? NONE : v >= 1e6 ? `${(v / 1e6).toFixed(1)}M` : v >= 1e3 ? `${Math.round(v / 1e3)}k` : String(v));
  const open = new Set();  // the cards whose detail is open: a redraw keeps them open
  let picked = null;       // the Conveyor whose tab is open, by repo
  let allOpen = false;     // whether All numbers is open: a redraw keeps it so
  // An SVG element with its attributes, and its children.
  function s(tag, attrs, ...kids) {
    const el = document.createElementNS(SVG, tag);
    Object.entries(attrs || {}).forEach(([k, v]) => el.setAttribute(k, String(v)));
    kids.forEach((k) => el.append(k));
    return el;
  }
  const tip = (text) => s('title', null, text);
  const chart = (label, w, hgt) => s('svg', { viewBox: `0 0 ${w} ${hgt}`, role: 'img', 'aria-label': label, class: 'chart-svg' });
  const DAY = (d) => new Date(`${d}T12:00:00Z`).toLocaleDateString('en-US', { weekday: 'short', timeZone: 'UTC' });
  window.DASH_APP.panel({
    id: 'metrics',
    title: 'Metrics',
    size: 'wide',
    tab: 'overview',
    phoneFolded: true,  // a report: on a phone it starts as its heading (issue 413)
    projects: true,  // filtered to one project, its measurements alone, and its row beside the machine's in the side-by-side table
    // The tiles and charts always show; the rows are the recent cards under them.
    rows: 8,
    // The live part holds the newest cards the snapshot keeps; the others of the 7 days come from the history, with
    // the machine's time to land, a median over every one of them.
    older: (d, o) => Object.assign({}, d, {
      cards: window.DASH_APP.joined(d.cards, o.cards, (c) => `${c.repo}/${c.card}`),
      compare: d.compare && o.compare && o.compare.machine
        ? Object.assign({}, d.compare, { machine: Object.assign({}, d.compare.machine, { leadSec: o.compare.machine.leadSec }) }) : d.compare,
    }),
    isEmpty: (d) => Array.isArray(d.cards) && d.cards.length === 0 && (d.records || []).every((r) => !r.week || r.week.cards === 0),
    empty(el, ctx) { el.append(ctx.state('empty', 'Nothing measured in the last 7 days', 'Measurements show here when a card runs.')); },
    error(el, message, ctx) { el.append(ctx.state('error', 'The Board could not read Metrics', message)); },
    render: function draw(el, d, ctx) {
      const h = ctx.h, out = [];
      const sec = (v) => (num(v) ? ctx.dur(v) : NONE);
      const spread = (x) => (x && num(x.p50) ? `${ctx.dur(x.p50)} (90th: ${ctx.dur(x.p90)})` : NONE);
      const money = (v) => (num(v) ? ctx.money(v) : NONE);
      // "—" and why, wherever a value does not exist yet.
      const none = (why) => { const p = h('p', 'metric-none'); p.append(h('span', 'none-value', NONE), h('span', 'unknown', why || 'not enough cards yet')); return p; };
      // Dollars are those of the priced steps: a figure that leaves steps out says how many (each card's timeline says why).
      const left = (n) => (num(n) && n > 0 ? ` (${n} ${n === 1 ? 'step' : 'steps'} not priced, left out)` : '');
      // Tokens are those of the steps whose usage was read: one whose usage was not is counted out, never as 0.
      const unreadOut = (n) => (num(n) && n > 0 ? ` (${n} ${n === 1 ? 'step' : 'steps'} with usage not read, left out)` : '');
      const blocks = (t) => {
        const e = Object.entries((t && t.blocks) || {});
        return e.length ? e.map(([k, n]) => `${n} ${k}`).join(', ') : 'none';
      };
      const byModel = (t) => {
        const m = Object.entries((t && t.perLanded && t.perLanded.byModel) || {});
        return m.length ? m.map(([k, v]) => `${k} ${money(v.usd)}${left(v.leftOut)}, ${tokens(v.tokens)} tokens${unreadOut(v.tokensLeftOut)}`).join('; ') : NONE;
      };
      const ROWS = [
        ['Cards ended', (t) => (t ? `${t.cards} (${t.landed} landed, ${t.blocked} blocked)` : NONE)],
        ['Lead time (opened to landed)', (t) => spread(t && t.leadSec)],
        ['Cycle time (picked to landed)', (t) => spread(t && t.cycleSec)],
        ['Passed first review', (t) => pct(t && t.firstReviewPass)],
        ['Findings per card', (t) => (t && num(t.findingsPerCard) ? String(t.findingsPerCard) : NONE)],
        ['Follow-up rate', (t) => pct(t && t.followupRate)],
        ['Block rate', (t) => (t && num(t.blockRate) ? `${pct(t.blockRate)}: ${blocks(t)}` : NONE)],
        ['Rebuild rate', (t) => pct(t && t.rebuildRate)],
        // Each test failure's verdict (the card's, main's or flaky) and the time its cases took to run on main.
        ['Test failures', (t) => {
          const f = t && t.testFailures;
          return f ? `${f.card} the card's (to fix), ${f.main} failing on main too (waited), ${f.flaky} flaky; ${sec(f.mainSec)} running them on main` : NONE;
        }],
        ['Per landed card', (t) => (t && t.perLanded ? `${money(t.perLanded.usd)}${left(t.perLanded.leftOut)}, ${tokens(t.perLanded.tokens)} tokens${unreadOut(t.perLanded.tokensLeftOut)}` : NONE)],
        ['Per landed card, by model', (t) => byModel(t)],
        ['Waiting on the owner', (t) => sec(t && t.waitMaxSec)],
        ['Weekly limit per card', (t) => (t && num(t.limitPerCard) ? `${t.limitPerCard} pts` : NONE)],
        ['Cards at once', (t) => (t && t.loop ? `${pct(t.loop.utilisation)} of the most on average, ${t.loop.slotsMax} at most` : NONE)],
        ['Idle, held back', (t) => (t && t.loop ? `${sec(t.loop.heldSec)} with room for a card while paused; ${sec(t.loop.idleSec)} with no card and issues queued` : NONE)],
        ['Pushes', (t) => (t && t.pushes ? `${t.pushes.ok} pushed (${spread(t.pushes.sec)}), ${t.pushes.failed} failed` : NONE)],
        ['Build machine', (t) => (t && t.host ? `load ${num(t.host.loadMax) ? t.host.loadMax : NONE} at most, disk free ${num(t.host.diskFreeMinKb) ? `${Math.round(t.host.diskFreeMinKb / 1048576)} GB` : NONE} at least, memory used ${num(t.host.memUsedMaxKb) ? `${Math.round(t.host.memUsedMaxKb / 104857.6) / 10} GB` : NONE} at most` : NONE)],
      ];

      // A 7-day sparkline: a line through the days that have a value, broken over those that do not; the last value dotted.
      function spark(vals, label, fmt) {
        const pts = vals.map((v, i) => (num(v) ? [i, v] : null));
        const have = pts.filter(Boolean);
        if (have.length < 2) return null;
        const lo = Math.min(...have.map((p) => p[1])), hi = Math.max(...have.map((p) => p[1]));
        const W = 100, H = 28, x = (i) => 3 + (i * (W - 6)) / Math.max(1, vals.length - 1), y = (v) => (hi === lo ? H / 2 : H - 3 - ((v - lo) * (H - 6)) / (hi - lo));
        let dpath = '', pen = false;
        pts.forEach((p) => { if (!p) { pen = false; return; } dpath += `${pen ? 'L' : 'M'}${x(p[0]).toFixed(1)} ${y(p[1]).toFixed(1)}`; pen = true; });
        const lastP = have[have.length - 1];
        const svg = s('svg', { viewBox: `0 0 ${W} ${H}`, class: 'spark', role: 'img', 'aria-label': `${label}, last 7 days: ${vals.map((v) => (num(v) ? fmt(v) : NONE)).join(', ')}` });
        svg.append(s('path', { d: dpath, class: 'spark-line' }), s('circle', { cx: x(lastP[0]).toFixed(1), cy: y(lastP[1]).toFixed(1), r: 2.5, class: 'spark-dot' }));
        return svg;
      }
      // The change on the 7 days before: an arrow, the word and the size, coloured by whether it is better.
      function delta(now, before, better, fmt) {
        if (!num(now) || !num(before)) return h('p', 'delta unknown', `${NONE} vs previous 7 days`);
        const diff = now - before;
        if (diff === 0) return h('p', 'delta', '= same as previous 7 days');
        const up = diff > 0, good = up === (better === 'up');
        return h('p', `delta ${good ? 'good' : 'bad'}`, `${up ? '▲ up' : '▼ down'} ${fmt(Math.abs(diff))} vs previous 7 days`);
      }
      function tile(key, label, value, sub, sp, dl) {
        const t = h('div', 'figure metric-tile');
        t.dataset.tile = key;
        t.append(h('span', 'figure-label', label));
        if (value === null) t.append(h('span', 'num unknown', NONE), h('span', 'unknown tile-sub', 'not enough cards yet'));
        else t.append(h('span', 'num', value), ...(sub ? [h('span', 'tile-sub', sub)] : []));
        if (sp) t.append(sp);
        t.append(dl);
        return t;
      }
      function figure(key, title, body) {
        const f = h('figure', 'chart');
        f.dataset.chart = key;
        f.append(h('figcaption', 'group-title', title), ...[].concat(body));
        return f;
      }
      function legend(items) {
        const ul = h('ul', 'legend');
        items.forEach(([cls, text]) => { const li = h('li'); const sw = h('span', `swatch ${cls}`); sw.setAttribute('aria-hidden', 'true'); li.append(sw, h('span', null, text)); ul.append(li); });
        return ul;
      }

      function tiles(r) {
        const w = r.week || {}, p = r.prev || {}, t = r.today || {}, days = Array.isArray(r.days) ? r.days : [];
        const col = (k) => days.map((x) => x && x[k]);
        const box = h('div', 'figures metric-tiles');
        const cyc = w.cycleSec && num(w.cycleSec.p50) ? w.cycleSec : null;
        const usd = w.perLanded && num(w.perLanded.usd) ? w.perLanded : null;
        // A cost with unpriced steps is only part of the cost: no change is drawn from it, in either period.
        const pts = (v) => `${Math.round(v * 1000) / 10} pts`;
        // The 7 days before ended no card: there is no earlier week, and a whole week is no rise on it (issue 413: "up
        // 326 vs previous 7 days" on a new Conveyor). A previous week not read at all stays "—".
        const first = r.prev && typeof r.prev === 'object' && p.cards === 0;
        const change = (...a) => (first ? h('p', 'delta unknown', 'no earlier week to compare') : delta(...a));
        box.append(
          tile('landed', 'Landed, today / 7 days', num(w.landed) ? `${num(t.landed) ? t.landed : NONE} / ${w.landed}` : null, null,
            spark(col('landed'), 'Landed', String), change(w.landed, p.landed, 'up', String)),
          tile('cycle', 'Cycle time, median', cyc ? ctx.dur(cyc.p50) : null, cyc ? `90th: ${ctx.dur(cyc.p90)}` : null,
            spark(col('cycleSec'), 'Cycle time', ctx.dur), change(cyc && cyc.p50, p.cycleSec && p.cycleSec.p50, 'down', ctx.dur)),
          tile('go', 'Passed first review', num(w.firstReviewPass) ? pct(w.firstReviewPass) : null, null,
            spark(col('firstReviewPass'), 'Passed first review', pct), change(w.firstReviewPass, p.firstReviewPass, 'up', pts)),
          tile('cost', 'Cost per landed card', usd ? ctx.money(usd.usd) : null, usd && usd.leftOut > 0 ? left(usd.leftOut).trim() : null,
            spark(col('perLandedUsd'), 'Cost per landed card', ctx.money), change(usd && !(usd.leftOut > 0) ? usd.usd : null,
              p.perLanded && !(p.perLanded.leftOut > 0) ? p.perLanded.usd : null, 'down', ctx.money)));
        return box;
      }

      // Landed and blocked cards each of the 7 days, stacked: landed at the baseline, blocked on top.
      function perDay(r) {
        const days = Array.isArray(r.days) ? r.days.filter((x) => x && typeof x.day === 'string') : [];
        if (!days.length || days.every((x) => !num(x.landed) && !num(x.blocked))) return figure('days', 'Landed and blocked, per day', none());
        // top leaves room over the tallest bar for its count.
        const W = 280, H = 120, base = 96, top = 22, bw = 22, step = W / days.length;
        const most = Math.max(1, ...days.map((x) => (x.landed || 0) + (x.blocked || 0)));
        const yh = (n) => (n * (base - top)) / most;
        const svg = chart(`Landed and blocked per day: ${days.map((x) => `${DAY(x.day)} ${x.landed || 0} landed, ${x.blocked || 0} blocked`).join('; ')}`, W, H);
        svg.append(s('line', { x1: 0, x2: W, y1: base, y2: base, class: 'axis' }));
        days.forEach((x, i) => {
          const cx = i * step + step / 2, l = x.landed || 0, b = x.blocked || 0, g = s('g', { class: 'bar' });
          g.append(tip(`${x.day}: ${l} landed, ${b} blocked`));
          g.append(s('rect', { x: cx - step / 2, y: top, width: step, height: base - top, class: 'hit' }));
          if (l) g.append(s('rect', { x: cx - bw / 2, y: base - yh(l), width: bw, height: yh(l), rx: 3, class: 'fill-landed' }));
          if (b) g.append(s('rect', { x: cx - bw / 2, y: base - yh(l) - yh(b) - (l ? 2 : 0), width: bw, height: yh(b), rx: 3, class: 'fill-blocked' }));
          // The counts over the bar (issue 413: a bar had no number on it): the landed, then "+" the blocked in their colour.
          const n = s('text', { x: cx, y: base - yh(l) - yh(b) - (l && b ? 2 : 0) - 4, class: 'tick value count', 'text-anchor': 'middle' }, s('tspan', null, String(l)));
          if (b) n.append(s('tspan', { class: 'fill-blocked' }, ` +${b}`));
          g.append(n, s('text', { x: cx, y: H - 8, class: 'tick', 'text-anchor': 'middle' }, DAY(x.day)));
          svg.append(g);
        });
        return figure('days', 'Landed and blocked, per day', [svg, legend([['fill-landed', 'Landed'], ['fill-blocked', 'Blocked']])]);
      }
      // Why cards were blocked in the 7 days: one bar, a segment a reason, the most first; at most five segments, the
      // last "other": the snapshot's own "other" reason and the reasons past the fourth together, never two buckets
      // that sound the same ("other 24" beside "the rest 29", issue 413).
      function reasons(r) {
        const w = r.week;
        if (!w || !num(w.blocked)) return figure('blocks', 'Block reasons, 7 days', none());
        const all = Object.entries(w.blocks || {}).filter(([, n]) => num(n) && n > 0).sort((a, b) => b[1] - a[1]);
        if (!all.length) return figure('blocks', 'Block reasons, 7 days', h('p', 'unknown', 'No card blocked in the last 7 days.'));
        const named = all.filter(([k]) => k !== 'other'), cut = named.length + (named.length < all.length ? 1 : 0) > 5 ? 4 : named.length;
        const other = all.filter(([k]) => k === 'other').concat(named.slice(cut)).reduce((a, [, n]) => a + n, 0);
        const segs = other ? [...named.slice(0, cut), ['other', other]] : named;
        const total = segs.reduce((a, [, n]) => a + n, 0), W = 300, H = 18, gap = 2;
        const svg = chart(`Block reasons: ${segs.map(([k, n]) => `${n} ${k}`).join(', ')}`, W, H);
        let x = 0;
        const room = W - gap * (segs.length - 1);
        segs.forEach(([k, n], i) => {
          const sw = (n * room) / total;
          svg.append(s('rect', { x: x.toFixed(1), y: 0, width: sw.toFixed(1), height: H, rx: 3, class: `fill-s${i + 1}` }, tip(`${k}: ${n}`)));
          x += sw + gap;
        });
        return figure('blocks', 'Block reasons, 7 days', [svg, legend(segs.map(([k, n], i) => [`fill-s${i + 1}`, `${k} ${n}`]))]);
      }
      // How long the landed cards of the 7 days took, picked to landed, in six equal bins.
      function histogram(cards) {
        const v = cards.filter((c) => (c.state === 'landed' || c.state === 'closed') && c.metrics && num(c.metrics.cycleSec)).map((c) => c.metrics.cycleSec);
        if (v.length < 2) return figure('cycle', 'Cycle time, landed cards', none());
        const lo = Math.min(...v), hi = Math.max(...v), n = hi === lo ? 1 : 6, wd = (hi - lo) / n || 1;
        const bins = Array.from({ length: n }, () => 0);
        v.forEach((x) => { bins[Math.min(n - 1, Math.floor((x - lo) / wd))] += 1; });
        const W = 280, H = 110, base = 86, top = 20, step = W / n, most = Math.max(...bins);
        const svg = chart(`Cycle time of ${v.length} landed cards, ${ctx.dur(lo)} to ${ctx.dur(hi)}: ${bins.join(', ')} cards in six equal bins`, W, H);
        svg.append(s('line', { x1: 0, x2: W, y1: base, y2: base, class: 'axis' }));
        bins.forEach((k, i) => {
          const bh = (k * (base - top)) / most, a = lo + i * wd, b = n === 1 ? hi : a + wd;
          const g = s('g', { class: 'bar' }, tip(`${ctx.dur(a)} to ${ctx.dur(b)}: ${k} ${k === 1 ? 'card' : 'cards'}`));
          g.append(s('rect', { x: i * step, y: top, width: step, height: base - top, class: 'hit' }));
          // Each bar's count of cards over it (issue 413).
          if (k) g.append(s('rect', { x: i * step + 1, y: base - bh, width: step - 2, height: bh, rx: 3, class: 'fill-s1' }),
            s('text', { x: i * step + step / 2, y: base - bh - 4, class: 'tick value count', 'text-anchor': 'middle' }, String(k)));
          svg.append(g);
        });
        svg.append(s('text', { x: 0, y: H - 6, class: 'tick' }, ctx.dur(lo)), s('text', { x: W, y: H - 6, class: 'tick', 'text-anchor': 'end' }, ctx.dur(hi)));
        return figure('cycle', 'Cycle time, landed cards', svg);
      }
      // What a landed card cost, by the model that ran it, the costliest first.
      function models(r) {
        const m = Object.entries((r.week && r.week.perLanded && r.week.perLanded.byModel) || {}).filter(([, x]) => x && num(x.usd)).sort((a, b) => b[1].usd - a[1].usd);
        if (!m.length) return figure('models', 'Cost per landed card, by model', none());
        const W = 300, row = 22, H = m.length * row, x0 = 140, room = 100, most = Math.max(...m.map(([, x]) => x.usd)) || 1;
        const svg = chart(`Cost per landed card by model: ${m.map(([k, x]) => `${k} ${ctx.money(x.usd)}`).join(', ')}`, W, H);
        m.forEach(([k, x], i) => {
          const y = i * row, bw = Math.max(2, (x.usd * room) / most), g = s('g', { class: 'bar' }, tip(`${k}: ${ctx.money(x.usd)} a landed card${left(x.leftOut)}`));
          g.append(s('text', { x: x0 - 6, y: y + 15, class: 'tick', 'text-anchor': 'end' }, k.length > 22 ? `${k.slice(0, 21)}…` : k));
          g.append(s('rect', { x: x0, y: y + 4, width: bw, height: row - 8, rx: 3, class: 'fill-s1' }));
          g.append(s('text', { x: x0 + bw + 6, y: y + 15, class: 'tick value' }, ctx.money(x.usd)));
          svg.append(g);
        });
        return figure('models', 'Cost per landed card, by model', svg);
      }
      // The slots in use today, by hour: the mean of each hour's samples, against the most allowed.
      function slots(r) {
        const v = (Array.isArray(r.slots) ? r.slots : []).filter((x) => x && num(x.hour) && num(x.slots));
        if (v.length < 2) return figure('slots', 'Cards at once today', none('not enough samples yet'));
        const cap = Math.max(1, ...v.map((x) => (num(x.cap) ? x.cap : 0)), ...v.map((x) => x.slots));
        const W = 280, H = 110, base = 86, top = 8, x = (hr) => 4 + (hr * (W - 8)) / 23, y = (n) => base - (n * (base - top)) / cap;
        const line = v.map((p, i) => `${i ? 'L' : 'M'}${x(p.hour).toFixed(1)} ${y(p.slots).toFixed(1)}`).join('');
        const svg = chart(`Cards at once today, by hour, of ${cap}: ${v.map((p) => `${p.hour}:00 ${p.slots}`).join(', ')}`, W, H);
        svg.append(s('line', { x1: 0, x2: W, y1: base, y2: base, class: 'axis' }), s('line', { x1: 0, x2: W, y1: top, y2: top, class: 'grid' }));
        svg.append(s('path', { d: `${line}L${x(v[v.length - 1].hour).toFixed(1)} ${base}L${x(v[0].hour).toFixed(1)} ${base}Z`, class: 'area' }), s('path', { d: line, class: 'area-line' }));
        v.forEach((p) => svg.append(s('rect', { x: x(p.hour) - 5, y: top, width: 10, height: base - top, class: 'hit' }, tip(`${p.hour}:00: ${p.slots} of ${num(p.cap) ? p.cap : cap} cards at once`))));
        svg.append(s('text', { x: 0, y: H - 6, class: 'tick' }, '0:00'), s('text', { x: W / 2, y: H - 6, class: 'tick', 'text-anchor': 'middle' }, '12:00'),
          s('text', { x: W, y: H - 6, class: 'tick', 'text-anchor': 'end' }, '23:00'), s('text', { x: W, y: top - 1, class: 'tick', 'text-anchor': 'end' }, `${cap} cards`));
        return figure('slots', 'Cards at once today', svg);
      }
      function table(r) {
        const t = h('table', 'metrics-table');
        const head = h('tr');
        head.append(h('th', null, ''), h('th', null, 'Today'), h('th', null, 'Last 7 days'));
        const thead = h('thead'); thead.append(head);
        const body = h('tbody');
        ROWS.forEach(([label, f]) => {
          const tr = h('tr');
          const a = f(r.today), b = f(r.week);
          tr.append(h('th', null, label), h('td', a === NONE ? 'unknown' : null, a), h('td', b === NONE ? 'unknown' : null, b));
          body.append(tr);
        });
        t.append(thead, body);
        const det = h('details', 'metrics-all');
        det.open = allOpen;
        det.addEventListener('toggle', () => { allOpen = det.open; ctx.relength(); });
        det.append(h('summary', null, 'All numbers'), t);
        return det;
      }

      // Each project and the machine, side by side (compare: {projects, machine}: the 7 days' cards landed, median
      // time from an issue's opening to its landing, and cost, which says how many steps it leaves out for having no
      // price (usdLeftOut); the last row is the machine's over every project).
      // The projects are the ones the page shows, in its order (the machine head's filter and sort); a machine with
      // one project has that project beside the machine. A figure not measured is a dash.
      const cmp = d.compare && typeof d.compare === 'object' ? d.compare : {};
      const rows = (Array.isArray(cmp.projects) ? cmp.projects.filter((r) => r && typeof r === 'object') : []).map((r) => Object.assign({}, r, { project: String(r.repo) }));
      if (rows.length && cmp.machine && typeof cmp.machine === 'object') {
        rows.push(Object.assign({}, cmp.machine, { project: null }));
        const t = h('table', 'metrics-table metrics-compare'), thead = h('thead'), body = h('tbody'), top = h('tr');
        t.append(h('caption', 'group-title', 'Last 7 days, side by side'));
        ['Project', 'Cards landed', 'Time to land (median)', 'Cost'].forEach((x) => top.append(h('th', null, x)));
        thead.append(top);
        rows.forEach((r) => {
          const tr = h('tr'), name = h('th');
          tr.dataset.project = r.project === null ? '' : String(r.project);
          if (r.project === null) name.textContent = 'Build machine'; else name.append(ctx.tag(r.project));
          const cell = (v) => h('td', v === NONE ? 'unknown' : null, v);
          tr.append(name, cell(num(r.landed) ? String(r.landed) : NONE), cell(sec(r.leadSec)), cell(num(r.usd) ? `${money(r.usd)}${left(r.usdLeftOut)}` : NONE));
          body.append(tr);
        });
        t.append(thead, body);
        out.push(t);
      }
      const recs = d.records || [];
      const rec = recs.find((r) => r.repo === picked) || recs[0];
      if (recs.length > 1) {
        const bar = h('div', 'metrics-tabs');
        bar.setAttribute('role', 'tablist');
        bar.setAttribute('aria-label', 'Conveyor');
        // The redraw replaces the buttons; the focus goes to the new tab of the Conveyor picked.
        const pick = (repo) => {
          picked = repo; draw(el, d, ctx); ctx.relength();
          const again = [...el.querySelectorAll('.metrics-tab')].find((x) => x.dataset.repo === repo);
          if (again) again.focus();
        };
        recs.forEach((r, i) => {
          const b = h('button', 'metrics-tab', r.repo);
          b.type = 'button';
          b.setAttribute('role', 'tab');
          b.setAttribute('aria-selected', String(r === rec));
          b.tabIndex = r === rec ? 0 : -1;
          b.dataset.repo = r.repo;
          b.addEventListener('click', () => pick(r.repo));
          b.addEventListener('keydown', (e) => {
            const to = { ArrowRight: i + 1, ArrowLeft: i - 1, Home: 0, End: recs.length - 1 }[e.key];
            if (to === undefined) return;
            e.preventDefault();
            pick(recs[(to + recs.length) % recs.length].repo);
          });
          bar.append(b);
        });
        out.push(bar);
      }
      // With more than one Conveyor, the cards are those of the one whose tab is open.
      const mine = Array.isArray(d.cards) ? d.cards.filter((c) => recs.length < 2 || c.repo === rec.repo) : null;
      if (rec && !rec.today && !rec.week) out.push(h('p', 'warn-note', `${rec.repo}: this host's Conveyor gives no measurements yet.`));
      else if (rec) {
        const charts = h('div', 'metric-charts');
        charts.append(perDay(rec), reasons(rec), histogram(mine || []), models(rec), slots(rec));
        out.push(tiles(rec), charts, table(rec));
      }
      if (!mine) out.push(h('p', 'warn-note', 'The build machine did not give measurements per card.'));
      else if (mine.length) {
        const ul = h('ul', 'rows compact');
        const row = (c) => {
          const m = c.metrics || {}, key = `${c.repo}/${c.card}`;
          const li = h('li', 'row');
          const det = h('details', 'card-detail');
          det.open = open.has(key);
          det.addEventListener('toggle', () => { if (det.open) open.add(key); else open.delete(key); });
          const sum = h('summary', 'row-main');
          sum.append(ctx.tag(c.repo), ctx.issueLink(c), h('span', 'title', c.title || 'untitled'), ctx.chip(c.state || 'unknown', c.state === 'blocked' ? 'warn' : 'quiet'),
            h('span', 'num', money(m.usd)));
          const meta = h('p', 'row-meta');
          const diff = m.diff ? `${m.diff.files} files, +${m.diff.added} −${m.diff.removed}` : `diff ${NONE}`;
          const lim = m.limit && num(m.limit.used) ? `${m.limit.used} pts of the weekly limit` : `weekly limit ${NONE}`;
          [`lead ${sec(m.leadSec)}`, `cycle ${sec(m.cycleSec)}`, `queued ${sec(m.queueSec)}`, `waiting for room ${sec(m.slotSec)}`,
            `building ${sec(m.buildSec)}`, `in review ${sec(m.reviewSec)}`, `fixing ${sec(m.fixSec)}`, `in tests ${sec(m.testSec)}`, `landing ${sec(m.landSec)}`,
            `landed to pushed ${sec(m.pushSec)}`, `waiting on the owner ${sec(m.waitMaxSec)}`, diff, lim, `${tokens(m.tokens)} tokens`,
            `${int(m.reviews)} reviews`, `${int(m.fixes)} fixes`, `${int(m.testRuns)} test runs`, `findings ${m.findings ? ctx.findings({ counts: m.findings }) || 'none' : NONE}`,
            `${int(m.rebuilds)} rebuilds`, `${int(m.retries)} retries`, `depth ${int(m.depth)}`, `${int(m.followups)} follow-ups`]
            .forEach((x) => meta.append(h('span', x.includes(NONE) ? 'unknown' : null, x)));
          // A restarted card's figures above are those of every run of its issue; its own are "this run".
          if (num(m.runs) && m.runs > 1 && m.thisRun) {
            const t = m.thisRun;
            meta.append(h('span', null, `${m.runs} runs, ${sec(m.runSec)} in all`), h('span', null, `this run: ${money(t.usd)}, ${sec(t.runSec)}, building ${sec(t.buildSec)}, in review ${sec(t.reviewSec)}, `
              + `fixing ${sec(t.fixSec)}, in tests ${sec(t.testSec)}, ${tokens(t.tokens)} tokens, ${int(t.reviews)} reviews, ${int(t.fixes)} fixes, ${int(t.testRuns)} test runs`));
          }
          if (m.blockClass) meta.append(ctx.chip(`blocked: ${m.blockClass}`, 'warn'));
          if (num(m.unpriced) && m.unpriced > 0) meta.append(ctx.chip(`${m.unpriced} ${m.unpriced === 1 ? 'step' : 'steps'} not priced`, 'warn'));
          const steps = h('ol', 'timeline');
          (Array.isArray(m.timeline) ? m.timeline : []).forEach((st) => {
            const t = h('li', null);
            // A review's verdict in words ("review: changes asked"), never its code.
            const result = st.step === 'review' && /^(NO-)?GO$/.test(st.result) ? `: ${ctx.verdictSaid(st.result)}` : st.result && st.result !== 'ok' ? ` ${st.result}` : '';
            const parts = [st.step + result, sec(st.sec), `${tokens(st.tokens)} tokens`, num(st.usd) ? `${ctx.money(st.usd)}${st.override === true ? ' (priced from your override)' : ''}` : `not priced: ${st.unpriced || 'no reason given'}`];
            if (st.model) parts.push(st.model + (st.effort ? ` ${st.effort}` : ''));
            // The route of a Claude session when a proxy is set (route): through the proxy, or on the subscription login.
            if (st.route === 'proxy') parts.push('through the API proxy');
            else if (st.route === 'subscription') parts.push('on the subscription login');
            if (st.counts) parts.push(`findings: ${ctx.findings(st) || 'none'}`);
            if (st.tests) parts.push(`tests: ${num(st.tests.passed) ? st.tests.passed : NONE} passed, ${num(st.tests.failed) ? st.tests.failed : NONE} failed, ${num(st.tests.skipped) ? st.tests.skipped : NONE} skipped of ${num(st.tests.total) ? st.tests.total : NONE} (${num(st.tests.files) ? st.tests.files : NONE} files)`);
            // The session's own account: a reading it did not give is "—"; a review has no API seconds,
            // refusals, cache hits or models of its own to give, so those are left out for it.
            if (st.stats && typeof st.stats === 'object') {
              const ss = st.stats, review = st.step === 'review';
              const tools = ss.tools && typeof ss.tools === 'object' ? Object.entries(ss.tools).filter(([, v]) => num(v)) : null;
              parts.push(`${int(ss.turns)} model replies`);
              if (!review) parts.push(`API ${sec(ss.apiSec)}`);
              parts.push(`tool calls ${tools === null ? NONE : tools.length ? tools.map(([k, v]) => `${k} ${v}`).join(', ') : 'none'}`);
              if (!review) {
                parts.push(`${int(ss.refused)} refused`, `cache hits ${pct(ss.cacheHit)}`);
                parts.push(`ran ${Array.isArray(ss.models) ? ss.models.join(', ') || 'none' : NONE}`);
              }
            }
            t.textContent = parts.join(' · ');
            steps.append(t);
          });
          if (!steps.children.length) steps.append(h('li', 'unknown', 'no step finished yet'));
          det.append(sum, meta, steps);
          li.append(det);
          return li;
        };
        // The newest first, across every record (each record gives its own newest first). Each Conveyor's tab keeps
        // its own paging, so a tab opens at five whatever was asked of another.
        const newest = mine.slice().sort((a, b) => String(b.at || '').localeCompare(String(a.at || '')));
        out.push(h('h3', 'group-title', 'Recent cards'), ul, ctx.more(recs.length > 1 ? `cards:${rec.repo}` : 'cards', newest, (cs) => ul.replaceChildren(...cs.map(row))));
      }
      el.replaceChildren(...out);
    },
  });
}());
