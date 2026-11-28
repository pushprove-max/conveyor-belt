// SPDX-License-Identifier: Apache-2.0
// What the Rules tab's rules produce, the held issues grouped, and the open issues' rows and filters. Part of
// panels/rules.js, which asks for it by name (DASH_APP.use) and gives it what it uses; boot.js loads it before the panels.
(() => {
  'use strict';
  // What this part uses of panels/rules.js, set when rules.js asks for the part (DASH_APP.part, at the end).
  let RELEASE_MAX, DEPENDS_MAX, BY, HELD_P, S, num, list, ctl, plural, prio, isArea, areaName, depKnown, why,
    moveOf, moveNote, say, run, send, guarded, button, HELD, held, unlisted, heldUnknown, groups, labelMark, matches,
    queueOne, queueAll, IFILTERS, lock, draw, relength;

  // ---- right: what the rules produce, as the snapshot says ----
  function stat(key, value, label) {
    const h = S.ctx.h, el = h('div', 'rules-stat');
    el.dataset.figure = key;
    el.append(h('span', 'rules-big', value), h('span', 'board-from', label));
    return el;
  }
  // A released issue takes the place pick gives it (as the Board's): follow-ups first, then priority, then the older.
  const rank = (x) => [x.followup ? 0 : 1, prio(x), typeof x.created === 'string' && x.created ? x.created : '~', num(x.issue) ?? Infinity];
  const ahead = (a, b) => { const p = rank(a), q = rank(b); for (let i = 0; i < p.length; i++) if (p[i] !== q[i]) return p[i] < q[i]; return false; };
  // The issues that wait on another card and nothing else: no hold, no label, no rule. One forced past its wait
  // (`control force`) is queued, not waiting.
  function waiters() {
    const d = S.d, c = ctl(), mine = new Set(c ? list(c.held) : []);
    const other = new Map(list(d.open && d.open.held).map((x) => [x.issue, list(x.reasons).some((r) => r && r.kind !== 'waits')]));
    const skipped = new Set(list(d.skipped).map((x) => x.issue));
    return list(d.waits).filter((x) => list(x.waitsFor).length && x.forced !== true && !mine.has(x.issue) && !skipped.has(x.issue) && !other.get(x.issue));
  }
  // Every issue that waits on another card, also one held or skipped as well, each with what else keeps it (also: null
  // when nothing does). The waiting list and its count show these; Next up and Queue anyway only the waiters.
  function waitingAll() {
    const d = S.d, c = ctl(), mine = new Set(c ? list(c.held) : []);
    const skip = new Map(list(d.skipped).map((x) => [x.issue, x.rule]));
    const held = new Map(list(d.open && d.open.held).map((x) => [x.issue, list(x.reasons).find((r) => r && r.kind !== 'waits' && r.kind !== 'you')]));
    const also = (x) => {
      if (mine.has(x.issue)) return 'also held by you';
      if (skip.has(x.issue)) return `also skipped: ${why(skip.get(x.issue))}`;
      const r = held.get(x.issue);
      if (!r) return null;
      if (r.kind === 'label') return `also held by the label ${r.label}`;
      if (r.kind === 'rule') return `also skipped: ${why(r.rule)}`;
      if (r.kind === 'standing') return 'also skipped by a standing rule';
      if (r.kind === 'approve') return 'also waits for your yes before its build';
      return 'also held by its card';
    };
    return list(d.waits).filter((x) => list(x.waitsFor).length && x.forced !== true).map((x) => ({ x, also: also(x) }));
  }
  // The cards with no GitHub issue that wait to be picked (the snapshot's queue.cards, in record order; nextUp() puts
  // the pinned ones first);
  // none when their record was not read (produce() says so). Each is held, skipped by a rule, waiting on another card
  // or ready.
  const cards = () => list(S.d.cards);
  const heldCards = () => cards().filter((x) => x.held);
  const skippedCards = () => cards().filter((x) => x.rule);
  const waitingCards = () => cards().filter((x) => list(x.waitsFor).length);
  const readyCards = () => cards().filter((x) => !x.held && !x.rule && !list(x.waitsFor).length);
  const NEXT_ROWS = 5;  // the rows of Next up; a longer run of these cards is one row
  // One card's row (cls), named by its kind, with what follows its title. A review follow-up's title is its finding,
  // so it is drawn as one: text in backticks as a code span.
  function cardRow(cls, x, ...more) {
    const h = S.ctx.h, li = h('li', cls), T = window.DASH_APP.text, title = x.title || 'untitled';
    li.dataset.card = String(x.card);
    li.append(S.ctx.issueLink({ name: x.kind }), T.fill(h('span', 'board-title'), title, S.d.repoUrl, new Set(T.pathsIn(title)), 'declined'), ...more);
    return li;
  }
  // The rows of a list's cards: a long run folds to one row with its count, which opens to every one.
  function folded(where, xs, row) {
    if (xs.length <= NEXT_ROWS) return xs.map(row);
    const h = S.ctx.h, li = h('li', 'rules-cards'), key = `cards:${where}`, open = S.open.has(key);
    const tog = h('button', 'rules-group-toggle');
    tog.type = 'button'; tog.dataset.act = `cards-${where}`;
    tog.setAttribute('aria-expanded', String(open));
    tog.append(h('span', 'rules-caret', open ? '▾' : '▸'), h('span', 'rules-group-name', 'Cards with no GitHub issue'), h('span', 'rules-group-count', String(xs.length)));
    tog.addEventListener('click', () => { if (open) S.open.delete(key); else S.open.add(key); draw(); relength(); });
    li.append(tog);
    if (open) {
      const ul = h('ul', 'rules-held-list');
      ul.setAttribute('aria-label', 'Cards with no GitHub issue');
      ul.append(...xs.map(row));
      li.append(ul);
    }
    return [li];
  }
  // Where an issue a card waits on is: its step on the belt (landed, while its push or close is still to come), blocked,
  // queued, waiting itself, held, else open.
  const STEPS = { brief: 'getting ready', build: 'building', review: 'in review', fix: 'fixing', tests: 'testing', landing: 'landing',
    waiting: 'waiting on a card', push: 'pushing', issue: 'closing the issue' };
  function where(n) {
    const d = S.d, has = (l) => list(l).some((x) => x && x.issue === n);
    const b = list(d.beltSteps).find((x) => x && x.issue === n);
    if (b) return b.landed ? 'landed' : STEPS[b.step] || 'on the belt';
    if (has(d.blocked)) return 'blocked';
    if (has(d.queue)) return 'queued';
    if (has(d.waits)) return 'waiting';
    const o = list(d.open && d.open.held).find((x) => x && x.issue === n);
    if (o && list(o.reasons).some((r) => r && r.kind === 'card' && r.step === 'landed')) return 'landed';
    if (o || has(d.held)) return 'held';
    return 'open';
  }
  const ns = (l) => l.map(S.ctx.depRef);
  const joined = (l) => (l.length < 2 ? l.join('') : `${l.slice(0, -1).join(', ')} and ${l[l.length - 1]}`);
  // Queue anyway: on a second click (it costs a build that may be wasted), that one card may be picked while the
  // issues it waits on are open.
  function force(x) {
    const deps = ns(list(x.waitsFor));
    return guarded(`force:${x.issue}`, 'spend','Queue anyway', `Click again: build #${x.issue} before ${joined(deps)} ${deps.length === 1 ? 'lands' : 'land'}`,
      'force', `Queue #${x.issue} before the issues it waits on land`, () => send('force', [String(x.issue)]));
  }
  // The dependencies its Depends on: lines name, each with a remove (×) and its title, and "Add dependency", which opens a field for open issues of the
  // project, each number typed shown with its title (a cycle the host refuses is said as what already waits on what): the host writes the issue's `Depends on: #N` line (POST control depends); the list shows it with the next snapshot.
  function depControls(li, x) {
    const h = S.ctx.h, t = `#${x.issue}`, box = h('span', 'rules-deps');
    // The numbers its own Depends on: lines name (open.issues dependsOn), not waitsFor: that adds the open follow-ups
    // of a dependency and leaves out a closed one, and the host removes only a number the lines name.
    const opened = list(S.d.open && S.d.open.issues), own = opened.find((y) => y && y.issue === x.issue);
    const titles = new Map(opened.filter((y) => y && y.title).map((y) => [y.issue, y.title]));
    list(own && own.dependsOn).filter((n) => num(n) !== null).forEach((n) => {
      const one = h('span', 'board-dep');
      one.append(button(`× #${n}`, 'btn-quiet', 'dep-remove', `Remove #${n} from the issues ${t} depends on`, () => send('depends', [String(x.issue), 'remove', String(n)])),
        h('span', 'board-dep-title', titles.get(n) || 'not open'));
      box.append(one);
    });
    // Another repository's ("owner/repo#N"): named, with no ×: the host removes only a number of this project.
    list(own && own.dependsOn).filter((n) => typeof n === 'string').forEach((n) => {
      const one = h('span', 'board-dep');
      one.append(h('span', 'board-dep-ref', n), h('span', 'board-dep-title', 'in another repository'));
      box.append(one);
    });
    const open = S.dep === x.issue;
    const more = button('Add dependency', 'btn-quiet', 'depends', `Add an issue ${t} depends on`, () => { S.dep = open ? null : x.issue; S.depText = ''; draw(); });
    more.setAttribute('aria-expanded', String(open));
    box.append(more);
    if (open) {
      const f = h('input', 'field');
      f.type = 'text'; f.dataset.act = 'dep-input'; f.placeholder = 'Issue numbers: 7, 9';
      f.setAttribute('aria-label', `Open issues ${t} depends on`);
      f.value = S.depText;
      f.addEventListener('input', () => { S.depText = f.value; });
      const add = () => {
        const ns = Array.from(new Set((S.depText.match(/\d+/g) || []).map(Number))).filter((n) => n > 0);
        if (!ns.length) { say(`Type the number of an open issue ${t} depends on.`); return; }
        if (ns.includes(x.issue)) { say(`${t} cannot depend on itself.`); return; }
        if (ns.length > DEPENDS_MAX) { say(`At most ${DEPENDS_MAX} issues at once.`); return; }
        send('depends', [String(x.issue), 'add'].concat(ns.map(String)), () => { S.dep = null; S.depText = ''; });
      };
      f.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); add(); } });
      // The project's other open issues, to pick from.
      const others = list(S.d.open && S.d.open.issues).filter((y) => num(y.issue) !== null && y.issue !== x.issue);
      if (others.length) {
        const dl = h('datalist');
        dl.id = `rules-deps-${x.issue}`;
        others.forEach((y) => { const o = h('option'); o.value = String(y.issue); o.label = `#${y.issue} ${y.title || ''}`.trim(); dl.append(o); });
        f.setAttribute('list', dl.id);
        box.append(dl);
      }
      box.append(f, button('Add', 'btn-quiet', 'dep-add', `Add these issues to the ones ${t} depends on`, add), S.ctx.depPicked(f, opened, x.issue));
    }
    li.append(box);
  }
  // The waiting list: each waiting card with the issues it waits on and where each is, and what else holds or skips
  // it; with the guard off, Queue anyway on one nothing else keeps; and its dependencies, set here (depControls).
  function waitList(w) {
    const h = S.ctx.h, ul = h('ul', 'rules-waits'), c = ctl(), anyway = depKnown() && c.depGuard === false;
    ul.id = 'rules-waits';
    ul.setAttribute('aria-label', 'Waiting on another card');
    w.forEach(({ x, also }) => {
      const li = h('li', 'rules-wait');
      li.dataset.issue = String(x.issue);
      li.append(S.ctx.issueLink(x), h('span', 'board-title', x.title || 'untitled'),
        h('span', 'board-from', `waits on ${list(x.waitsFor).map((n) => (typeof n === 'string' ? `${n} (another repository)` : `#${n} (${where(n)})`)).join(', ')}`));
      if (also) li.append(h('span', 'board-from', also));
      else if (anyway) li.append(force(x));
      depControls(li, x);
      ul.append(li);
    });
    // A card with no GitHub issue waits on issues, or on a card that has none, which it names by its id.
    const on = (n) => (typeof n === 'number' ? `#${n} (${where(n)})` : n.includes('#') ? `${n} (another repository)` : `card ${n}`);
    ul.append(...folded('waiting', waitingCards(), (x) => cardRow('rules-wait', x,
      h('span', 'board-from', `waits on ${x.waitsFor.map(on).join(', ')}`),
      ...(x.held ? [h('span', 'board-from', 'also held')] : []),
      ...(x.rule ? [h('span', 'board-from', `also skipped: ${why(x.rule)}`)] : []))));
    return ul;
  }
  function produce(all) {
    const h = S.ctx.h, d = S.d, f = d.forecast && typeof d.forecast === 'object' ? d.forecast : null, el = h('section', 'rules-side rules-produce');
    el.append(h('h3', 'board-head', 'What these rules produce'));
    if (S.ctl) el.append(h('p', 'board-from', 'Changed here: this side shows it in about a minute.'));
    const unread = Array.isArray(d.cards) ? [] : [h('p', 'warn-note', 'Conveyor could not read the cards with no GitHub issue.')];
    if (d.queue === null || d.queue === undefined) {
      el.append(h('p', 'warn-note', d.issuesError || 'GitHub did not list the open issues.'), ...unread);
      if (cards().length) cardsAlone(el);
      return el;
    }
    const q = list(d.queue), sk = list(d.skipped), w = waiters(), wa = waitingAll();
    el.append(produceStats(all, q, sk, wa), ...unread);
    if (S.waitsOpen && (wa.length || waitingCards().length)) el.append(waitList(wa));
    nextUp(el, q, w);
    forecastLines(el, f, q);
    skippedList(el, sk);
    return el;
  }
  // With the open issues not listed: what the cards with no GitHub issue alone give.
  function cardsAlone(el) {
    el.append(S.ctx.h('p', 'board-from', 'The counts and lists here show only the cards with no GitHub issue.'), produceStats([], [], [], []));
    if (S.waitsOpen && waitingCards().length) el.append(waitList([]));
    if (readyCards().length) nextUp(el, [], []);
    skippedList(el, []);
  }
  // The counts of What these rules produce: ready (q), waiting on another card (wa), held (all) and skipped (sk), each
  // with the cards with no GitHub issue that are so.
  function produceStats(all, q, sk, wa) {
    const h = S.ctx.h, stats = h('div', 'rules-stats'), waiting = wa.length + waitingCards().length;
    const ready = q.length + readyCards().length;
    // The waiting count opens the list of the waiting cards.
    const ws = h('button', 'rules-stat rules-stat-open');
    ws.type = 'button'; ws.dataset.figure = 'waiting'; ws.dataset.act = 'waits-open';
    ws.setAttribute('aria-expanded', String(S.waitsOpen)); ws.setAttribute('aria-controls', 'rules-waits');
    ws.append(h('span', 'rules-big', String(waiting)), h('span', 'board-from', 'waiting on another card'));
    ws.disabled = !waiting;
    ws.addEventListener('click', () => { S.waitsOpen = !S.waitsOpen; draw(); });
    stats.append(stat('ready', String(ready), 'ready to build'), ws,
      stat('held', String(all.length + heldCards().length), HELD.toLowerCase()),
      stat('skipped', String(sk.length + skippedCards().length), 'skipped by a rule'));
    return stats;
  }
  // Next up: the queue (q) in its order, with each issue that waits on another card (w) and the ready cards with no
  // GitHub issue, where pick would take them. A card that cannot start has no row: pick passes it over, and its row
  // would push the issue picked next out of the list (the waiting list shows what it waits on).
  function nextUp(el, q, w) {
    const h = S.ctx.h;
    const order = list((ctl() || {}).order);
    const next = q.slice();
    // A pinned issue goes where its pin puts it (before each later pin and every unpinned issue); an unpinned one goes
    // among the unpinned by pick's rank.
    const pin = (i) => { const k = order.indexOf(i); return k < 0 ? Infinity : k; };
    const before = (x, y) => { const a = pin(x.issue), b = pin(y.issue); return a !== b ? a < b : a === Infinity && ahead(x, y); };
    w.forEach((x) => { const at = next.findIndex((y) => before(x, y)); next.splice(at < 0 ? next.length : at, 0, x); });
    // A ready card's place in the order (`control order`) is the first place of its pins (its id, its parent issue and
    // that issue's umbrellas: the snapshot's queue.cards); the placed cards go first, lowest first, and the rest keep
    // the snapshot's order (testpick(), conveyor/lib/testaction.sh). sort is stable.
    const place = (x) => Math.min(...(list(x.pins).length ? list(x.pins) : [x.card]).map(pin));
    const ready = readyCards().slice().sort((x, y) => place(x) - place(y) || 0);
    // Pick takes a ready pinned issue after the cards placed before it, and the other cards after the last ready
    // pinned issue, before the rest (pick(), conveyor/lib/pick.sh).
    let at = 0;
    next.forEach((y, i) => { if (q.includes(y) && pin(y.issue) !== Infinity) at = i + 1; });
    const rows = [];
    let k = 0;
    // The cards not taken yet that are placed before lim (an issue's place; with none, every one left).
    const cardsTo = (lim, where) => {
      let j = k;
      while (j < ready.length && (lim === null || place(ready[j]) < lim)) j += 1;
      rows.push(...folded(where, ready.slice(k, j), (x) => cardRow('rules-next', x, waitMarks(x))));
      k = j;
    };
    for (let i = 0; i <= next.length && rows.length < NEXT_ROWS; i += 1) {
      const y = next[i];
      if (i === at) cardsTo(null, 'next');
      else if (y && q.includes(y) && pin(y.issue) !== Infinity) cardsTo(pin(y.issue), `next-${y.issue}`);
      if (y) rows.push(nextRow(y));
    }
    el.append(h('h4', 'board-label', 'Next up'));
    if (rows.length) {
      const flow = h('ol', 'rules-flow');
      flow.setAttribute('aria-label', 'What Conveyor picks next, in order');
      flow.append(...rows.slice(0, NEXT_ROWS));
      el.append(flow);
    } else el.append(h('p', 'board-empty', 'Nothing to build under these rules.'));
  }
  // A Next up row's marks: ready, or what it waits on. One forced past its wait (`control force`) is picked all the
  // same: it says so, not "ready".
  function waitMarks(x) {
    const marks = S.ctx.h('span', 'rules-marks'), waits = list(x.waitsFor);
    if (waits.length) waits.forEach((n) => marks.append(S.ctx.chip(`${x.forced === true ? 'forced past' : 'waits on'} ${S.ctx.depRef(n)}`, 'warn')));
    else marks.append(S.ctx.chip('ready', 'ok'));
    return marks;
  }
  function nextRow(x) {
    const h = S.ctx.h, li = h('li', 'rules-next');
    li.dataset.issue = String(x.issue);
    li.append(S.ctx.issueLink(x), h('span', 'board-title', x.title || 'untitled'), waitMarks(x));
    return li;
  }
  // The queue's forecast (f) in dollars, and the guard's warning (q: the queue).
  function forecastLines(el, f, q) {
    const h = S.ctx.h;
    // The queue's dollars, as one line (no time).
    const usd = f ? num(f.usd) : null;
    const fc = h('p', 'rules-forecast', usd === null ? 'Forecast for the queue: not known.' : `Forecast for the queue: about ${S.ctx.money(usd)}.`);
    fc.dataset.figure = 'usd';
    el.append(fc);

    // The guard's warning, only when the forecast says the guard pauses the loop before the queue ends.
    const at = f ? num(f.pausesAt) : null;
    if (at !== null) {
      const x = q.find((y) => y.issue === at);
      const warn = h('p', 'warn-note rules-warn');
      warn.setAttribute('role', 'status');
      warn.textContent = `Conveyor will pause when the weekly limit reaches ${num(f.guard) ?? '?'}%, before it picks #${at}${x && x.title ? ` ${x.title}` : ''}.`;
      el.append(warn);
    }
  }
  // The issues skipped by a rule (sk) and the cards with no GitHub issue a rule skips, each with the rule.
  function skippedList(el, sk) {
    const h = S.ctx.h, skc = skippedCards();
    if (sk.length || skc.length) {
      const ul = h('ul', 'rules-skipped');
      ul.setAttribute('aria-label', 'Skipped by a rule');
      sk.forEach((x) => {
        const li = h('li', 'rules-skip');
        li.dataset.issue = String(x.issue);
        li.append(S.ctx.issueLink(x), h('span', 'board-title', x.title || 'untitled'), h('span', 'board-from', why(x.rule)));
        ul.append(li);
      });
      ul.append(...folded('skipped', skc, (x) => cardRow('rules-skip', x, h('span', 'board-from', why(x.rule)))));
      el.append(h('h4', 'board-label', 'Skipped'), ul);
    }
  }

  // ---- under both: the held issues, grouped ----
  function heldRow(x) {
    const h = S.ctx.h, li = h('li', 'rules-held-row'), t = `#${x.issue}`;
    li.dataset.issue = String(x.issue);
    li.append(S.ctx.issueLink(x), h('span', 'board-title', x.title || 'untitled'), h('span', 'rules-prio', prio(x)));
    x.holds.forEach((l) => li.append(S.ctx.chip(l, 'warn')));
    const m = moveOf(x.issue);
    if (m && !m.error) { li.classList.add('is-pending'); li.append(moveNote(m)); return li; }
    if (m) li.append(moveNote(m));
    if (x.how === 'release') li.append(button('Queue', 'btn-quiet', 'queue', `Queue ${t}: release it from the hold`, () => queueOne(x)));
    else if (x.how === 'unlabel') {
      const armed = S.armed === x.issue, what = `${x.holds.length === 1 ? 'the label' : 'the labels'} ${x.holds.join(', ')}`;
      const b = button(armed ? `Click again: remove ${what} on GitHub` : 'Queue', armed ? 'board-danger' : 'btn-quiet', 'queue',
        armed ? `Confirm: remove ${what} from ${t} on GitHub and queue it` : `Queue ${t}: remove ${what} and queue it`, () => queueOne(x));
      b.setAttribute('aria-pressed', String(armed));
      if (armed) b.dataset.armed = '';
      li.append(b);
    } else {
      const r = x.rest[0] || {};
      li.append(h('span', 'board-from', r.kind === 'standing' ? 'a standing rule skips it' : r.kind === 'rule' ? `also skipped: ${why(r.rule)}` : r.kind === 'waits' ? 'also waits for another issue' : r.kind === 'approve' ? 'also waits for your yes before its build' : 'also held by its card'));
    }
    return li;
  }
  function group(g, searching) {
    const h = S.ctx.h, key = `${S.by}:${g.key}`, el = h('div', 'rules-group');
    el.dataset.group = g.key;
    const items = searching ? g.items.filter(matches) : g.items;
    const open = searching || S.open.has(key);
    const head = h('div', 'rules-group-head');
    const tog = h('button', 'rules-group-toggle');
    tog.type = 'button'; tog.dataset.act = 'group';
    tog.setAttribute('aria-expanded', String(open));
    const mark = labelMark(items);
    tog.append(h('span', 'rules-caret', open ? '▾' : '▸'), h('span', 'rules-group-name', g.name), h('span', 'rules-group-count', String(items.length)));
    if (mark) tog.append(h('span', 'rules-group-mark', mark));
    tog.setAttribute('aria-label', `${g.name}: ${plural(items.length, 'issue', 'issues')}${mark ? `, ${mark}` : ''}; ${open ? 'open' : 'closed'}`);
    tog.addEventListener('click', () => { if (S.open.has(key)) S.open.delete(key); else S.open.add(key); draw(); relength(); });
    // Queue all costs a build of each: its second click is the "Queue N" of the question it opens.
    const all = button('Queue all', 'btn-cost', 'queue-all', `Queue all ${g.items.length} of ${g.name}`, () => { S.asking = key; S.withLabels = false; draw(); });
    all.dataset.guard = 'spend';
    head.append(tog, all);
    el.append(head);

    // Queue all asks once: the count, how many a label holds, and those are left out unless asked.
    if (S.asking === key) {
      const labelled = g.items.filter((x) => x.holds.length).length, unlabel = g.items.filter((x) => x.how === 'unlabel').length;
      const rel = g.items.filter((x) => x.how === 'release').length, none = g.items.length - rel - unlabel;
      const ask = h('div', 'rules-ask');
      ask.setAttribute('role', 'group'); ask.setAttribute('aria-label', `Queue all of ${g.name}`); ask.dataset.armed = '';
      ask.append(h('p', null, `Queue all ${plural(g.items.length, 'issue', 'issues')} of ${g.name}? ${labelled ? `A label holds ${labelled} of them (${labelMark(g.items)}): if you do not include them, Conveyor leaves them out.` : 'No label holds any of them.'}${none ? ` Something else also holds ${plural(none, 'issue', 'issues')}, and you cannot queue ${none === 1 ? 'it' : 'them'} from here.` : ''}`));
      const acts = h('div', 'rules-ask-acts');
      if (unlabel) {
        const lab = h('label', 'rules-check'), box = h('input');
        box.type = 'checkbox'; box.checked = S.withLabels; box.dataset.act = 'queue-all-labels';
        box.addEventListener('change', () => { S.withLabels = box.checked; draw(); });
        lab.append(box, h('span', null, `Also remove the labels from ${unlabel} and queue them`));
        acts.append(lab);
      }
      const k = rel + (S.withLabels ? unlabel : 0);
      acts.append(button(`Queue ${k}`, 'btn-primary', 'queue-all-yes', `Queue ${plural(k, 'issue', 'issues')} of ${g.name}${S.withLabels && unlabel ? `, removing the labels of ${unlabel}` : ''}`, () => queueAll(g, S.withLabels)),
        button('Cancel', 'btn-quiet', 'queue-all-no', 'Do not queue them', () => { S.asking = null; S.withLabels = false; draw(); }));
      ask.append(acts);
      el.append(ask);
    }

    if (open) {
      const ul = h('ul', 'rules-held-list');
      ul.setAttribute('aria-label', `Held: ${g.name}`);
      el.append(ul, (S.at.has(HELD_P) ? S.at.get(HELD_P).ctx : S.ctx).more(`held:${key}`, items, (xs) => { ul.replaceChildren(...xs.map(heldRow)); lock(ul); }));
    }
    return el;
  }
  function heldGroups(all) {
    const h = S.ctx.h, box = h('div', 'rules-groups'), searching = S.search.trim() !== '';
    const gs = groups(all).filter((g) => !searching || g.items.some(matches));
    gs.forEach((g) => box.append(group(g, searching)));
    if (!all.length) box.append(h('p', 'board-empty', 'Nothing holds an issue.'));
    else if (!gs.length) box.append(h('p', 'board-empty', 'No held issue matches the search.'));
    // The held cards are searched by their kind and title.
    heldCardList(box, heldCards().filter((x) => !searching || matches({ issue: '', title: `${x.kind} ${x.title}` })));
    return box;
  }
  // The held cards with no GitHub issue (hc) under their own heading, added to box: the Board has no Queue for them.
  function heldCardList(box, hc) {
    if (!hc.length) return;
    const h = S.ctx.h, ul = h('ul', 'rules-held-list');
    ul.setAttribute('aria-label', 'Held cards with no GitHub issue');
    ul.append(...folded('held', hc, (x) => cardRow('rules-held-row', x, h('span', 'rules-prio', prio(x)), S.ctx.chip('held', 'warn'))));
    box.append(h('h4', 'board-label', 'Held cards with no GitHub issue'), ul);
  }
  function heldSection(all) {
    const h = S.ctx.h, el = h('section', 'rules-held');
    el.id = 'rules-held';
    if (unlisted()) {
      el.append(h('h3', 'board-head', HELD), h('p', 'warn-note', `${S.d.issuesError || 'GitHub did not list the open issues.'} ${heldUnknown()}`));
      heldCardList(el, heldCards());
      return el;
    }
    el.append(h('h3', 'board-head', `${HELD} · ${all.length + heldCards().length}`));
    const tools = h('div', 'rules-held-tools');
    const search = h('input', 'field rules-search');
    search.type = 'search'; search.placeholder = 'Search number or title'; search.dataset.act = 'held-search';
    search.setAttribute('aria-label', 'Search the held issues by number or title');
    search.value = S.search;
    search.addEventListener('input', () => {
      S.search = search.value;
      el.querySelector('.rules-groups').replaceWith(heldGroups(held()));
      relength();
    });
    const by = h('select', 'field board-select');
    by.dataset.act = 'held-by';
    by.setAttribute('aria-label', 'Group the held issues by');
    BY.forEach(([v, text]) => { const o = h('option', null, text); o.value = v; o.selected = v === S.by; by.append(o); });
    by.addEventListener('change', () => { S.by = by.value; S.asking = null; draw(); relength(); });
    const byLab = h('label', 'rules-by');
    byLab.append(h('span', 'board-from', 'Group by'), by);
    tools.append(search, byLab);
    el.append(tools, heldGroups(all));
    return el;
  }

  // ---- under them all: every open issue of the project, with its state, to filter, sort, pick and manage ----
  // The state is the snapshot's: on the belt (building), blocked, held by you (the record in force), held by a
  // label, skipped by a rule (or a standing rule), waiting on an open issue, waiting for the yes before its build,
  // next up (the first NEXT in pick order), queued, or not picked. Filters, the sort and its direction are kept in the
  // address with the project. Hold, Queue (a release), Order first and Retry act on the picked rows and name their count; hold
  // and release go RELEASE_MAX issues a request, retry one, as the host takes them.
  const NEXT = 5;
  const STATES = [['next', 'Next up'], ['queued', 'Queued'], ['you', 'Held by you'], ['label', 'Held by a label'], ['waits', 'Waiting on another card'], ['building', 'Building'],
    ['blocked', 'Blocked'], ['rule', 'Skipped by a rule'], ['approve', 'Waits for your yes'], ['landed', 'Landed, not pushed']];
  const ISORTS = [['priority', 'Priority'], ['number', 'Number'], ['age', 'Age'], ['area', 'Area'], ['state', 'State']];
  // The open issues' filters as the address holds them, with the Time and Date set in Customize (a time written in
  // the old form is drawn again), as one text (S.shown keeps the ones each panel shows).
  const filtersOf = (ctx) => JSON.stringify([...IFILTERS.map((k) => ctx.param(k) || ''), window.DASH_APP.form()]);
  function openIssues() {
    const d = S.d, c = ctl();
    if (!d.open || !Array.isArray(d.open.issues)) return null;
    const held = new Map(list(d.open.held).map((x) => [x.issue, x]));
    const mine = new Set(c ? list(c.held) : list(d.open.held).filter((x) => list(x.reasons).some((r) => r && r.kind === 'you')).map((x) => x.issue));
    const q = list(d.queue).map((x) => x.issue), belt = new Set(list(d.onBelt)), blocked = new Set(list(d.blocked).map((x) => x.issue));
    const splitting = new Set(list(d.splitting));
    return d.open.issues.filter((x) => x && num(x.issue) !== null).map((x) => {
      const why = list((held.get(x.issue) || {}).reasons).filter((r) => r && r.kind !== 'you'), k = (kind) => why.find((r) => r.kind === kind);
      const at = q.indexOf(x.issue);
      // One not picked for any reason named here is skipped by a rule of Conveyor's own: one word for it, as on the Board.
      let state = 'rule';
      if (belt.has(x.issue)) state = 'building';
      else if (blocked.has(x.issue)) state = 'blocked';
      // Its card landed while push is off: done, waiting for the push, not open work.
      else if (k('card') && k('card').notPushed === true) state = 'landed';
      else if (mine.has(x.issue)) state = 'you';
      else if (k('label')) state = 'label';
      else if (k('rule') || k('standing')) state = 'rule';
      else if (k('waits')) state = 'waits';
      // A card stopped and not among the blocked ones waits in Needs you for the owner's yes: nothing to retry.
      else if (k('approve') || (k('card') && k('card').step === 'blocked')) state = 'approve';
      else if (at >= 0) state = at < NEXT ? 'next' : 'queued';
      // A split umbrella (as held(): its held entry names slices in umbrella or sliceCards; or its card, still on the
      // belt, has filed its slices and holds it before it closes: splitting) is held by the split: a release would
      // clear that hold and build nothing, so Queue leaves it out (split).
      const h0 = held.get(x.issue) || {};
      const split = splitting.has(x.issue) || list(h0.umbrella).some((n) => num(n) !== null) || list(h0.sliceCards).some((c) => c && typeof c.card === 'string');
      return Object.assign({}, x, { state, mine: mine.has(x.issue), split, waitsFor: state === 'waits' ? list(k('waits').waitsFor) : [], areas: list(x.labels).filter(isArea).sort() });
    });
  }
  const stateWord = (x) => (x.state === 'waits' ? `Waiting on ${x.waitsFor.map(S.ctx.depRef).join(', ')}` : STATES.find(([k]) => k === x.state)[1]);
  function issueChoice() {
    const p = S.ctx.param, sort = ISORTS.some(([k]) => k === p('isort')) ? p('isort') : 'priority';
    const dir = p('idir') === 'asc' || p('idir') === 'desc' ? p('idir') : sort === 'age' ? 'desc' : 'asc';  // by age: the oldest first
    return { q: p('iq') || '', state: p('istate') || '', pri: p('iprio') || '', area: p('iarea') || '', label: p('ilabel') || '', sort, dir };
  }
  function shownIssues(all) {
    const v = issueChoice(), q = v.q.trim().toLowerCase().replace(/^#/, '');
    const now = Date.now();
    const key = (x) => {
      if (v.sort === 'priority') return prio(x);
      if (v.sort === 'number') return x.issue;
      if (v.sort === 'age') { const t = Date.parse(x.created || ''); return Number.isNaN(t) ? -Infinity : now - t; }
      if (v.sort === 'area') return x.areas[0] || '~';
      return STATES.findIndex(([k]) => k === x.state);
    };
    const s = v.dir === 'desc' ? -1 : 1;
    return all.filter((x) => (!q || String(x.issue).includes(q) || String(x.title || '').toLowerCase().includes(q))
        && (!v.state || x.state === v.state) && (!v.pri || prio(x) === v.pri) && (!v.area || x.areas.includes(v.area)) && (!v.label || list(x.labels).includes(v.label)))
      .map((x) => [x, key(x)]).sort((a, b) => (a[1] === b[1] ? a[0].issue - b[0].issue : a[1] < b[1] ? -s : s)).map((x) => x[0]);
  }
  // The pinned order with these issues first, ahead of the pins already there.
  const pinnedFirst = (ns) => ns.concat(list((ctl() || {}).order).map(String).filter((n) => !ns.includes(n)));
  function bulk(action, xs) {
    const ns = xs.map((x) => String(x.issue)), steps = [];
    if (action === 'hold' || action === 'release') for (let i = 0; i < ns.length; i += RELEASE_MAX) steps.push([action, ns.slice(i, i + RELEASE_MAX)]);
    else if (action === 'retry') ns.forEach((n) => steps.push(['retry', [n]]));
    else steps.push(['order', pinnedFirst(ns)]);
    const said = { hold: 'held', release: 'queued', retry: 'retried', order: 'pinned first' }[action];
    // Hold and Queue undo each other, and Order first undoes to the order as it was (with no pins before, it unpins
    // the issues it pinned, RELEASE_MAX at a time: the engine refuses an order with no issues); a retry is not undone.
    const was = list((ctl() || {}).order).map(String), unpins = [];
    for (let i = 0; i < ns.length; i += RELEASE_MAX) unpins.push(['unpin', ns.slice(i, i + RELEASE_MAX)]);
    const back = action === 'hold' || action === 'release' ? steps.map(([a, args]) => [a === 'hold' ? 'release' : 'hold', args])
      : action === 'order' ? (was.length ? [['order', was]] : unpins) : null;
    run(steps, `${said} ${plural(ns.length, 'issue', 'issues')}`, () => { S.picked.clear(); }, back);
  }
  function issueRow(x) {
    const h = S.ctx.h, li = h('li', 'rules-issue'), t = `#${x.issue}`;
    li.dataset.issue = String(x.issue); li.dataset.state = x.state;
    const box = h('input');
    box.type = 'checkbox'; box.dataset.act = 'pick'; box.checked = S.picked.has(x.issue);
    box.setAttribute('aria-label', `Select ${t}`);
    box.addEventListener('change', () => { if (box.checked) S.picked.add(x.issue); else S.picked.delete(x.issue); draw(); });
    const t0 = Date.parse(x.created || '');
    li.append(box, S.ctx.issueLink(x), h('span', 'board-title', x.title || 'untitled'), h('span', 'rules-prio', prio(x)),
      h('span', 'board-from', x.areas.length ? x.areas.map(areaName).join(', ') : 'no area'));
    list(x.labels).filter((l) => !isArea(l)).forEach((l) => li.append(S.ctx.chip(l, 'quiet')));
    // The age moves with the Board's clock (since), as a refresh that changes only readAt draws no row again.
    const age = h('span', 'board-from rules-age', Number.isNaN(t0) ? 'age not known' : '');
    if (!Number.isNaN(t0)) age.append(S.ctx.since(x.created, ' old'));
    li.append(age, S.ctx.chip(stateWord(x), { blocked: 'bad', you: 'warn', label: 'warn', next: 'ok', building: 'info' }[x.state] || 'quiet'));
    const m = moveOf(x.issue);
    if (m) { if (!m.error) li.classList.add('is-pending'); li.append(moveNote(m)); }
    return li;
  }
  window.DASH_APP.part('rules-produce', function (shared) {
    ({ RELEASE_MAX, DEPENDS_MAX, BY, HELD_P, S, num, list, ctl, plural, prio, isArea, areaName, depKnown, why,
      moveOf, moveNote, say, run, send, guarded, button, HELD, held, unlisted, heldUnknown, groups, labelMark,
      matches, queueOne, queueAll, IFILTERS, lock, draw, relength } = shared);
    return { produce, heldSection, STATES, ISORTS, filtersOf, openIssues, issueChoice, shownIssues, pinnedFirst,
      bulk, issueRow };
  });
})();
