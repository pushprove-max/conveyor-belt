// SPDX-License-Identifier: Apache-2.0
// The Board's cards, and each card's own builder, reviewer and judge. Part of panels/board.js, which asks for it
// by name (DASH_APP.use) and gives it what it uses; boot.js loads it before the panels.
(() => {
  'use strict';
  // What this part uses of panels/board.js, set when board.js asks for the part (DASH_APP.part, at the end).
  let STEP, S, DEPENDS_MAX, num, waitsOn, issues, ctl, waiting, forced, waitsOf, kinds, waitsOnly, labelsOf,
    unlabelable, PART, elOf, relength, say, send, hold, release, shift, button, arm, slicesOf, sliceState, unshaped,
    draw;

  // ---- the cards ----
  function chipsOf(x) {
    // The four states an owner can change, each in one word everywhere: Held by you, Held by a label, Skipped by a rule
    // (a standing rule of Conveyor's own and one not picked for a reason named too), Waiting on #N.
    return issues(x.reasons).map((r) => ({
      you: r.outside ? 'Opened by someone outside the project: release it to build it' : 'Held by you', label: `Held by a label: ${r.label}`, rule: `Skipped by a rule: ${r.rule}`, standing: `Skipped by a rule: ${r.rule || 'Conveyor\'s own'}`,
      waits: `Waiting on ${issues(r.waitsFor).map(S.ctx.depRef).join(', ')}`, card: r.step === 'blocked' ? 'Card blocked (Needs you)' : r.notPushed === true ? 'Landed, not pushed' : `Card ${r.step || 'open'}`,
      parent: 'Waits for its parent card to land', approve: 'Approve before build (Needs you)', other: 'Skipped by a rule',
    }[r.kind]));
  }
  function moves(card, item, col) {
    const h = S.ctx.h, acts = h('div', 'board-moves');
    const t = `#${item.issue}`;
    // An umbrella is never picked: a release would clear the hold and build nothing, so it has no Queue.
    const mine = col === 'held' && kinds(item).includes('you') && !slicesOf(item).length;
    if (mine) acts.append(button('Queue', 'btn-quiet', 'release', `Queue ${t}: release it from your hold`, () => release(item)));
    // A card that waits on another issue is not in the pick order: it can be held, not moved. One held only by that
    // wait is in Held and can still be held by you, so it is not picked once the issue it waits on closes.
    const ordered = col === 'queue' && !waiting(item);
    const heldWait = col === 'held' && waitsOnly(item);
    if (col === 'queue' || heldWait) acts.append(button('Hold', 'btn-quiet', 'hold', `Hold ${t}`, () => hold(item)));
    if (ordered) {
      acts.append(button('Move up', 'btn-quiet', 'up', `Move ${t} up`, () => shift(item, -1)),
        button('Move down', 'btn-quiet', 'down', `Move ${t} down`, () => shift(item, 1)));
    }
    const open = S.dep === item.issue;
    const dep = button('Depends on…', 'btn-quiet', 'depends', `Set the issues ${t} depends on`, () => { S.dep = open ? null : item.issue; S.depText = ''; draw(); });
    dep.setAttribute('aria-expanded', String(open));
    acts.append(dep);
    card.append(acts);
    if (open) card.append(depForm(item));
    card.tabIndex = 0;
    card.setAttribute('aria-label', `${t} ${item.title || ''}: ${col === 'held' ? `held (${chipsOf(item).join(', ')})${mine ? '; the right arrow queues it' : heldWait ?'; the left arrow holds it' : ''}` : ordered ? 'queued; the up and down arrows move it, the left arrow holds it' : 'waits for another issue; the left arrow holds it'}`);
    card.addEventListener('keydown', (e) => {
      const fn = col === 'held' ? (mine ? { ArrowRight: () => release(item) }[e.key] : heldWait ? { ArrowLeft: () => hold(item) }[e.key] : null)
        : ordered ? { ArrowUp: () => shift(item, -1), ArrowDown: () => shift(item, 1), ArrowLeft: () => hold(item) }[e.key]
          : { ArrowLeft: () => hold(item) }[e.key];
      if (!fn) return;
      e.preventDefault(); fn();
    });
    card.setAttribute('draggable', 'true');
    card.addEventListener('dragstart', (e) => {
      S.dragging = { item, col }; card.classList.add('dragging');
      if (e.dataTransfer) { e.dataTransfer.effectAllowed = 'move'; e.dataTransfer.setData('text/plain', String(item.issue)); }
    });
    card.addEventListener('dragend', () => { S.dragging = null; card.classList.remove('dragging'); elOf(PART).querySelectorAll('.over').forEach((x) => x.classList.remove('over')); });
  }
  // "Depends on…": the issue's Depends on: line on GitHub, written by the host (POST control depends). The owner types
  // or picks open issues of the project to add, or removes one its Depends on: lines name (×; another repository's
  // owner/repo#N is listed, with no ×). The card says at once what it
  // now waits on, until a snapshot begun at or after the answer shows it (render).
  function depForm(item) {
    const h = S.ctx.h, t = `#${item.issue}`, box = h('div', 'board-deps');
    // The numbers its own Depends on: lines name (open.issues dependsOn), not what it waits on: waitsFor adds the open
    // follow-ups of a dependency and leaves out a closed one, and the host removes only a number the lines name.
    const open = issues(S.d.open && S.d.open.issues), own = open.find((x) => x && x.issue === item.issue);
    const titles = new Map(open.filter((x) => x && x.title).map((x) => [x.issue, x.title]));
    issues(own && own.dependsOn).filter((n) => num(n) !== null).forEach((n) => {
      const one = h('span', 'board-dep');
      one.append(button(`× #${n}`, 'btn-quiet', 'dep-remove', `Remove #${n} from the issues ${t} depends on`, () => depend(item, 'remove', [n])),
        h('span', 'board-dep-title', titles.get(n) || 'not open'));
      box.append(one);
    });
    // Another repository's ("owner/repo#N"): named, with no ×: the host removes only a number of this project.
    issues(own && own.dependsOn).filter((n) => typeof n === 'string').forEach((n) => {
      const one = h('span', 'board-dep');
      one.append(h('span', 'board-dep-ref', n), h('span', 'board-dep-title', 'in another repository'));
      box.append(one);
    });
    const f = h('input', 'field');
    f.type = 'text'; f.dataset.act = 'dep-input'; f.placeholder = 'Issue numbers: 7, 9';
    f.setAttribute('aria-label', `Open issues ${t} depends on`);
    f.value = S.depText;
    f.addEventListener('input', () => { S.depText = f.value; });
    const add = () => {
      const ns = Array.from(new Set((S.depText.match(/\d+/g) || []).map(Number))).filter((n) => n > 0);
      if (!ns.length) { say(`Type the number of an open issue ${t} depends on.`); return; }
      if (ns.includes(item.issue)) { say(`${t} cannot depend on itself.`); return; }
      if (ns.length > DEPENDS_MAX) { say(`At most ${DEPENDS_MAX} issues at once.`); return; }
      depend(item, 'add', ns);
    };
    // The card's own keys (arrows move it) are not the field's.
    f.addEventListener('keydown', (e) => { e.stopPropagation(); if (e.key === 'Enter') { e.preventDefault(); add(); } });
    // The project's other open issues, to pick from.
    const others = issues(S.d.open && S.d.open.issues).filter((x) => num(x.issue) !== null && x.issue !== item.issue);
    if (others.length) {
      const dl = h('datalist');
      dl.id = `board-deps-${item.issue}`;
      others.forEach((x) => { const o = h('option'); o.value = String(x.issue); o.label = `#${x.issue} ${x.title || ''}`.trim(); dl.append(o); });
      f.setAttribute('list', dl.id);
      box.append(dl);
    }
    box.append(f, button('Add', 'btn-quiet', 'dep-add', `Add these issues to the ones ${t} depends on`, add), S.ctx.depPicked(f, open, item.issue));
    return box;
  }
  function depend(item, how, ns) {
    const t = ns.map((n) => `#${n}`).join(', ');
    send('depends', [String(item.issue), how].concat(ns.map(String)), (at) => {
      S.depSaid.set(item.issue, { text: how === 'add' ? `Now waits on ${t}.` : `No longer depends on ${t}.`, at });
      S.dep = null; S.depText = '';
    });
  }
  // A link that opens the Rules tab, where a rule that skips an issue is changed.
  function rulesLink() {
    const a = S.ctx.h('a', 'board-rules-link', 'Rules');
    a.href = '?tab=rules';
    a.dataset.act = 'rules-open';
    a.addEventListener('click', (e) => {
      if (e.button || e.ctrlKey || e.metaKey || e.shiftKey || e.altKey) return;  // a new tab or window opens it as a link
      e.preventDefault();
      S.ctx.setTab('rules', true);
    });
    return a;
  }
  // "Waiting on #12, #15": each issue a link to it, so the card it waits on is one click away; another
  // repository's ("owner/repo#7") is said as that, as text. Each one the snapshot gives a state for (waitsOn) says
  // why it does not move: "Waiting on #12 (held)". One that is an umbrella waits on its slices, and says so:
  // "Waiting on #12 (its slices #20, #21)".
  function waitingChip(ns, url, on) {
    const c = S.ctx.chip('Waiting on ', 'quiet'), words = c.lastChild;
    const state = (n) => {
      const um = slicesOf(issues(S.d.open && S.d.open.held).find((x) => x && x.issue === n));
      if (um.length) return ` (its slices ${um.map((x) => `#${x}`).join(', ')})`;
      const w = issues(on).find((x) => x && x.issue === n); return w && typeof w.state === 'string' && w.state ? ` (${w.state})` : '';
    };
    ns.forEach((n, i) => {
      if (i) words.append(', ');
      if (typeof n === 'string') { words.append(n); return; }
      // The card's own issue address, its number swapped: issueLink takes only a GitHub issue address, else plain text.
      words.append(S.ctx.issueLink({ issue: n, url: typeof url === 'string' ? url.replace(/\/\d+$/, `/${n}`) : null }), state(n));
    });
    c.dataset.reason = 'waits';
    return c;
  }
  // What a card held by more than the owner offers: removing the label that holds it (confirmed once), or why it is not
  // queued from here.
  function heldWhy(card, item) {
    const h = S.ctx.h, t = `#${item.issue}`, labels = labelsOf(item);
    if (S.unlabeled.has(item.issue)) { card.classList.add('is-pending'); card.append(h('p', 'board-from board-sent', 'Label removed: the issue goes into the queue in about a minute.')); return; }
    if (unlabelable(item)) {
      const what = `${labels.length === 1 ? 'the label' : 'the labels'} ${labels.join(', ')}`;
      const armed = S.armed === `unlabel:${item.issue}`;
      const b = button(armed ? `Click again: remove ${what} from ${t} on GitHub` : `Remove ${what} and queue it`, armed ? 'board-danger' : 'btn-quiet', 'unlabel',
        armed ? `Confirm: remove ${what} from ${t} on GitHub and queue it` : `Remove ${what} from ${t} and queue it`, () => {
          if (!armed) { arm(`unlabel:${item.issue}`); return; }
          S.armed = false;
          send('unlabel', [String(item.issue)].concat(labels), () => { S.unlabeled.add(item.issue); });
        });
      b.setAttribute('aria-pressed', String(armed));
      if (armed) b.dataset.armed = '';
      card.append(b);
    } else if (kinds(item).includes('standing')) {
      const r = issues(item.reasons).find((x) => x.kind === 'standing');
      card.append(h('p', 'board-why', `Skipped by a rule of Conveyor's own (${(r && r.rule) || 'not named'}): you cannot queue it from the Board.`));
    } else if (kinds(item).includes('rule')) {
      // The rule is changed in Rules: the link opens that tab.
      const p = h('p', 'board-why', 'Skipped by a rule: change it in ');
      p.append(rulesLink(), ' to queue it.');
      card.append(p);
    }
  }
  // A card in the Needs you column leads with why it stopped (a blocked card's reason in one sentence, its explanation
  // under it, shown; a visible change's sentence), and links into Overview's Needs you panel, the one place it is answered.
  function needs(card, item, waitingYes) {
    const h = S.ctx.h;
    card.append(waitingYes ? h('p', 'board-why', `Visible change: ${item.sentence || 'the reviewer gave no sentence'}`) : S.ctx.failureLine(item));
    const a = h('a', 'board-answer', waitingYes ? 'Answer it in Needs you' : 'Retry or close it in Needs you');
    a.href = S.ctx.panelHref('needs');
    a.dataset.act = 'needs-open';
    a.addEventListener('click', (e) => {
      if (e.button || e.ctrlKey || e.metaKey || e.shiftKey || e.altKey) return;  // a new tab or window opens it as a link
      e.preventDefault();
      S.ctx.goTo('needs');
    });
    card.append(a);
  }
  // ---- a card's own builder, reviewer and judge ----
  // Settings: the card's (or queued issue's) builder, reviewer and judge, each its own (the control record's cards,
  // `conveyor.sh control card`) or the project's (modelSettings); one of its own is marked. Opened, each seat has a
  // model (Project's, or one the pack allows the seat) and an effort (Project's, or one that model's CLI takes); Save
  // sends one POST control card a changed seat. Pick for me asks the project's judge (POST control card <issue> pick):
  // its settings and a reason each are shown, and change nothing until Apply sends them; Discard drops them.
  const SEATS = [['builder', 'Builder'], ['reviewer', 'Reviewer'], ['judge', 'Judge']];
  const ownSeats = (n) => { const c = ctl(), o = c && c.cards && typeof c.cards === 'object' ? c.cards[String(n)] : null; return o && typeof o === 'object' ? o : {}; };
  const projSeat = (k) => { const m = S.d.modelSettings, s = m && typeof m === 'object' ? m[k] : null; return s && typeof s === 'object' ? s : null; };
  // The efforts a model's CLI takes in the seat: the CLI that the pack lists the model under (allowed).
  function effortsOf(k, model) {
    const s = projSeat(k);
    if (!s || !model) return [];
    const bare = model.replace(/^opencode:/, '');
    const cli = Object.keys(s.allowed || {}).find((c) => issues(s.allowed[c]).includes(bare));
    const e = cli && s.clis && s.clis[cli] ? s.clis[cli].efforts : null;
    return issues(e).filter((x) => typeof x === 'string');
  }
  // The effort a card's own seat with no effort of its own runs at, as the engine works it out (cardfit, lib/control.sh):
  // the project's, else medium when the model's CLI does not take it; none when the CLI takes none (an OpenCode builder).
  function ownEffort(k, model, pe) {
    const e = effortsOf(k, model);
    return !pe || !e.length ? null : e.includes(pe) ? pe : 'medium';
  }
  const seatText = (x) => `${S.ctx.modelName(x.model)}${x.effort ? ` at ${x.effort}` : ''}`;
  // Who set a seat the card runs on (seats.run's by, from the snapshot's seatsof()), as its row says it.
  const SEATBY = { card: 'this card', judge: "Judge's pick", trial: 'trial', promoted: 'promoted' };
  // One list of the seats the card runs on: a row a seat, its name as a label, the model and effort, and who chose it
  // (the owner's, "this card", always wins; then the seat the rule set, seats.run: the Judge's pick, a trial or a
  // promoted seat; else the project's). Under the row, a callout holds the Judge's reason for the seat and what a limit
  // clamped (seats.builder and the rest: its pick's asked), and, when the card does not run on the Judge's seat, which
  // one the Judge chose. A failed pick, or the guard, says why the card runs on the project's seats in a callout under
  // the list. here: the card is of the project shown, so its own and the project's seats are known; a card of another
  // project shows only the seats the rule set.
  function seatList(item, here) {
    const h = S.ctx.h, own = here ? ownSeats(item.issue) : {}, s = item.seats && typeof item.seats === 'object' ? item.seats : null;
    const run = s && s.run && typeof s.run === 'object' ? s.run : {};
    const list = h('div', 'board-seats-line');
    SEATS.forEach(([k, name]) => list.append(seatRow(k, name, here, own, run, s)));
    const back = s && typeof s === 'object' ? (typeof s.failed === 'string' ? `The Judge's pick failed: ${s.failed}` : typeof s.guard === 'string' ? s.guard : null) : null;
    if (back) list.append(seatCallout('code', "Why the card runs on the project's seats", [back]));
    return list;
  }
  const seatStr = (v) => (typeof v === 'string' && v ? v : null);
  const seatNamed = (x) => `${S.ctx.modelName(x.model)}${seatStr(x.effort) ? ` · ${x.effort}` : ''}`;
  function seatCallout(by, label, lines) {
    const h = S.ctx.h, box = h('div', 'why-block board-seat-why');
    box.dataset.by = by;
    box.append(h('strong', 'why-label', label));
    lines.forEach((t) => box.append(h('span', 'why-line', t)));
    return box;
  }
  // The card's own seat o, or null when it has none or its model is not one the pack allows the seat (p: the project's
  // seat): the engine passes over such a seat (percard, lib/control.sh), and the form marks it stale.
  function ownSeat(o, p) {
    const mine = o && typeof o.model === 'string' ? o : null;
    return mine && !(p && Array.isArray(p.choices) && !p.choices.includes(mine.model)) ? mine : null;
  }
  // The seat k a card runs on (seatList): o, the owner's own seat, or null; x, its model and effort, or null; by, who
  // chose it (SEATBY), or null for the project's. own: the card's own seats; run: the seats the rule set.
  function seatRun(k, here, own, run) {
    const p = here ? projSeat(k) : null, o = ownSeat(own[k], p);
    // On a card of the project shown, the owner's seat is the control record's as it is now (own), not the pick's
    // record of it: a seat the owner cleared since runs on the project's.
    const q = !o && run[k] && typeof run[k].model === 'string' && SEATBY[run[k].by] && !(here && run[k].by === 'card') ? run[k] : null;
    const x = o ? { model: o.model, effort: o.effort || ownEffort(k, o.model, p && p.effort) }
      : q ? { model: q.model, effort: seatStr(q.effort) } : p && p.model ? p : null;
    return { o, x, by: o ? 'card' : q ? q.by : null };
  }
  // The Judge's answer for seat k (s: the card's seats), as the lines of its callout (a clamp with no model: the pack
  // allowed it none, so the project's stands); the card does not run on it only when it is another model or effort
  // than the row's (x, chosen by `by`).
  function judgeWhy(s, k, x, by) {
    const a = s && s[k] && typeof s[k] === 'object' ? s[k] : null, am = a && seatStr(a.model) ? a : null;
    const other = am && by !== 'judge' && !(x && x.model === am.model && seatStr(x.effort) === seatStr(am.effort));
    return a ? [].concat(other ? [`The Judge chose ${seatNamed(am)}; the card does not run on it${s.mode === 'shadow' ? ', as the rule Pick settings is in Shadow' : ''}.`] : [],
      seatStr(a.why) ? [a.why] : am ? ['no reason given'] : [], seatStr(a.clamp) ? [`Clamped: ${a.clamp}`] : []) : [];
  }
  // The row of seat k (its name) in seatList.
  function seatRow(k, name, here, own, run, s) {
    const h = S.ctx.h, { o, x, by } = seatRun(k, here, own, run);
    const row = h('div', o ? 'board-seat is-own' : 'board-seat');
    row.dataset.seat = k;
    const line = h('p', 'board-seat-line');
    line.append(h('span', 'board-seat-name', name),
      h('span', 'board-seat-model', x ? seatNamed(x) : here ? 'not set' : ''),
      h('span', 'board-seat-by', by ? SEATBY[by] : "project's"));
    row.append(line);
    const why = judgeWhy(s, k, x, by);
    if (why.length) row.append(seatCallout('judge', 'Why the Judge chose it', why));
    return row;
  }
  function seats(el, item) {
    const h = S.ctx.h, n = item.issue, own = ownSeats(n), t = `#${n}`;
    const box = h('div', 'board-seats');
    const line = seatList(item, true);
    const open = S.seats && S.seats.issue === n;
    const b = button('Settings', 'btn-quiet', 'seats', `The builder, reviewer and judge of ${t}`, () => {
      // base: the seats as the form opened, so Save sends only a seat changed in the form, not one that changed since
      // (an Apply while the form is open).
      const at = () => Object.fromEntries(SEATS.map(([k]) => [k, { model: own[k] ? own[k].model : '', effort: own[k] && own[k].effort ? own[k].effort : '' }]));
      S.seats = open ? null : { issue: n, repo: S.d.repo, draft: at(), base: at() };
      draw();
    });
    b.setAttribute('aria-expanded', String(!!open));
    const pk = S.picks.get(n);
    const ask = button('Pick for me', 'btn-quiet', 'seats-pick', `Ask the project's judge to pick the settings of ${t}`, () => pick(item));
    ask.disabled = !!(pk && pk.busy);
    const acts = h('div', 'board-acts');
    acts.append(b, ask);
    box.append(line, acts);
    if (open) box.append(seatsForm(item));
    if (pk) box.append(picked(item, pk));
    el.append(box);
  }
  function seatsForm(item) {
    const h = S.ctx.h, n = item.issue, d = S.seats.draft, f = h('div', 'board-seats-form');
    const s = item.seats && typeof item.seats === 'object' ? item.seats : null, run = s && s.run && typeof s.run === 'object' ? s.run : {};
    SEATS.forEach(([k, name]) => {
      const p = projSeat(k), row = h('div', 'board-seat-row');
      // What the seat runs on with no seat of the card's own: the seat the rule set (the Judge's pick, a trial or a
      // promoted one: seats.run), else the project's (seatRun with no own seat).
      const { x, by } = seatRun(k, true, {}, run), whose = by ? `${SEATBY[by].charAt(0).toUpperCase()}${SEATBY[by].slice(1)}` : 'Project\'s';
      row.dataset.seat = k;
      const m = h('select', null), e = h('select', null), eff = h('label', 'board-seat-effort'), same = h('span', 'board-seat-same', by ? 'the effort it names' : 'the project\'s effort');
      m.dataset.act = `seat-model-${k}`; e.dataset.act = `seat-effort-${k}`;
      m.setAttribute('aria-label', `${name} model of #${n}`); e.setAttribute('aria-label', `${name} effort of #${n}`);
      const opt = (v, text) => { const o = h('option', null, text); o.value = v; return o; };
      m.append(opt('', `${whose}: ${x && x.model ? seatText(x) : 'not set'}`), ...issues(p && p.choices).map((c) => opt(c, S.ctx.modelName(c))));
      m.value = d[k].model;
      // A saved model no longer in the allowed list matches no option: show the project's. The seat is marked stale
      // until the model menu changes, so Save does not read this as an edit and clear the saved setting; the base keeps
      // the saved model, so a later explicit choice of Project's still clears it.
      if (m.selectedIndex < 0) { m.value = ''; d[k].model = ''; d[k].stale = true; }
      m.title = m.options[m.selectedIndex].textContent;
      const fill = () => {
        e.replaceChildren(opt('', 'Project\'s effort'), ...effortsOf(k, d[k].model).map((x) => opt(x, x)));
        // With the project's model there is no effort to pick: say so, in place of a greyed menu with no reason.
        eff.hidden = !d[k].model; same.hidden = !!d[k].model;
        if (!effortsOf(k, d[k].model).includes(d[k].effort)) d[k].effort = '';
        e.value = d[k].effort;
      };
      fill();
      m.addEventListener('change', () => { d[k].model = m.value; d[k].stale = false; m.title = m.options[m.selectedIndex].textContent; fill(); });
      e.addEventListener('change', () => { d[k].effort = e.value; });
      eff.append(h('span', 'board-label', 'Effort'), e);
      row.append(h('span', 'board-label', name), m, eff, same);
      f.append(row);
    });
    f.append(button('Save', 'btn-quiet', 'seats-save', `Save the settings of #${n}`, () => {
      const was = S.seats.base;
      const changes = SEATS.map(([k]) => k).filter((k) => !d[k].stale && (d[k].model !== was[k].model ||(d[k].model && d[k].effort !== was[k].effort)))
        .map((k) => (d[k].model ? [String(n), k, d[k].model].concat(d[k].effort ? [d[k].effort] : []) : [String(n), k, 'clear']));
      if (!changes.length) { say('Nothing changed.'); return; }
      sendAll(changes, S.seats.repo).then((ok) => { if (ok) S.seats = null; });
    }));
    return f;
  }
  // One POST control card after another to the project the settings were opened or picked in (repo), each once the
  // one before it was done; stops at the first refused.
  const sendAll = (list, repo) => list.reduce((p, args) => p.then((ok) => ok && send('card', args, undefined, repo)), Promise.resolve(true));
  // Pick for me: one judge call on the build machine, which can take minutes; the rest of the Board stays usable.
  // Its answer is kept only while that project is still shown: a project switch drops every pick (render()).
  function pick(item) {
    const n = item.issue, repo = S.d.repo, ask = { busy: true, repo };
    S.picks.set(n, ask);
    draw();
    const keep = (v) => { if (S.picks.get(n) === ask) S.picks.set(n, { ...v, repo }); };
    S.ctx.post('control', { action: 'card', args: [String(n), 'pick'], repo }).then((r) => r.text().then((t) => {
      const said = String(t).trim();
      let x = null;
      try { x = JSON.parse(said); } catch { x = null; }
      const ok = r.ok && x && typeof x === 'object' && SEATS.every(([k]) => x[k] && typeof x[k].model === 'string' && typeof x[k].why === 'string');
      keep(ok ? { data: x } : { error: r.ok ? 'the judge gave no settings that the Board can read' : (said ? S.ctx.refusal(said) : `the build machine answered ${r.status}`) });
    })).catch(() => { keep({ error: 'the build machine did not answer. Make sure that it is on. Then try again' }); })
      .then(() => { if (S.d && S.d.repo === repo) draw(); });
  }
  function picked(item, pk) {
    const h = S.ctx.h, n = item.issue, box = h('div', 'board-seats-picked');
    box.setAttribute('role', 'status');
    if (pk.busy) { box.append(h('p', 'board-from', 'Asking the judge…')); return box; }
    if (pk.error) {
      box.append(h('p', 'board-from', `Not picked: ${pk.error}.`), button('Close', 'btn-quiet', 'seats-discard', 'Close this line', () => { S.picks.delete(n); draw(); }));
      return box;
    }
    const x = pk.data;
    box.append(h('p', 'board-label', 'The judge picked these. Nothing changed yet.'));
    SEATS.forEach(([k, name]) => {
      const p = h('p', 'board-seat-pick', `${name}: ${seatText(x[k])}. ${x[k].why}`);
      p.dataset.seat = k;
      box.append(p);
    });
    const acts = h('div', 'board-acts');
    acts.append(button('Apply', 'btn-quiet', 'seats-apply', `Apply the picked settings to #${n}`, () => {
      sendAll(SEATS.map(([k]) => [String(n), k, x[k].model].concat(x[k].effort ? [x[k].effort] : [])), pk.repo).then((ok) => { if (ok) { S.picks.delete(n); draw(); } });
    }), button('Discard', 'btn-quiet', 'seats-discard', 'Discard the picked settings', () => { S.picks.delete(n); draw(); }));
    box.append(acts);
    return box;
  }

  function card(col, item) {
    const h = S.ctx.h, ctx = S.ctx, el = h('li', 'bcard');
    el.dataset.col = col; el.dataset.issue = String(item.issue);
    const head = h('div', 'row-main');
    head.append(ctx.issueLink(item));
    el.append(head, h('p', 'board-title', item.title || 'untitled'));
    if (col === 'held' || col === 'queue') waitingCard(el, col, item);
    else if (col === 'building' || col === 'review') workingCard(el, col, item);
    else if (col === 'needs') {
      el.classList.add(item.waiting ? 'is-waiting' : 'is-blocked');
      el.append(ctx.chip(item.waiting ? 'Waiting for your yes' : 'Blocked', item.waiting ? 'warn' : 'bad'));
      needs(el, item, item.waiting);
    } else el.append(landedMeta(item));
    cardFoot(el, col, item);
    return el;
  }
  // The tags of a card in Held or Queue: its priority, a follow-up, a retry, and why it is held or what it waits on.
  function cardTags(col, item) {
    const ctx = S.ctx, tags = ctx.h('div', 'board-tags');
    if (item.priority) tags.append(ctx.chip(item.priority, item.priority === 'P0' || item.priority === 'P1' ? 'warn' : 'quiet'));
    if (item.followup) tags.append(ctx.chip('Follow-up', 'info'));
    if (item.retried) tags.append(ctx.chip('Retried', 'quiet'));
    if (col === 'held') chipsOf(item).forEach((t, i) => {
      const r = issues(item.reasons)[i];
      const c = r.kind === 'waits' ? waitingChip(issues(r.waitsFor), item.url) : ctx.chip(t, r.kind === 'you' ? 'warn' : 'quiet');
      c.dataset.reason = r.kind; tags.append(c);
    });
    else if (waiting(item)) tags.append(waitingChip(item.waitsFor, item.url, item.waitsOn));
    else if (forced(item)) tags.append(ctx.chip(`Forced past ${item.waitsFor.map(ctx.depRef).join(', ')}`, 'warn'));
    // The machine holds this card back (its cap, its load or its free memory): why, with the reading.
    if (col === 'queue' && typeof item.room === 'string' && item.room) tags.append(ctx.chip(item.room, 'warn'));
    return tags;
  }
  // A split issue (the rule Split large issues On), or a parent of GitHub sub-issues, is held as the umbrella of its
  // slices until each one lands or is already done on main: never built itself, so it has no Queue; each slice with its state.
  function sliceList(el, item) {
    const h = S.ctx.h, um = slicesOf(item);
    if (!um.length) return;
    el.append(h('p', 'board-from board-umbrella', `Split into ${um.map((x) => `#${x}`).join(', ')}; closes when they land`));
    const ul = h('ul', 'board-slices'), raw = unshaped();
    um.forEach((n) => {
      const st = sliceState(n, raw), li = h('li', 'board-slice', `#${n} ${st}`);
      li.dataset.slice = String(n); li.dataset.state = st;
      ul.append(li);
    });
    el.append(ul);
  }
  // A card in Held or Queue (card).
  function waitingCard(el, col, item) {
    const h = S.ctx.h, tags = cardTags(col, item);
    if (tags.firstChild) el.append(tags);
    if (num(item.next) !== null) el.append(h('p', 'board-from', item.next === 1 ? 'Next in the queue' : `#${item.next} in the queue`));
    sliceList(el, item);
    if (S.released.has(item.issue) && waitsOf(item).length && !(ctl() && issues(ctl().held).includes(item.issue))) {
      const n = h('p', 'board-from', `Released from hold. Still waits on ${waitsOf(item).map((x) => `#${x}`).join(', ')}.`);
      n.setAttribute('role', 'status');
      el.append(n);
    }
    if (S.depSaid.has(item.issue)) {
      const n = h('p', 'board-from board-deps-said', S.depSaid.get(item.issue).text);
      n.setAttribute('role', 'status');
      el.append(n);
    }
    if (col === 'held') heldWhy(el, item);
    moves(el, item, col);
  }
  // The line of a card in Building or Review: its step, the time in it and its cost so far.
  function workMeta(col, item) {
    const h = S.ctx.h, ctx = S.ctx, meta = h('p', 'row-meta');
    // A card that let another land first reads "Waiting behind #N"; what it does meanwhile is on hover and tap.
    const behind = num(item.gaveWay) !== null ? ctx.tip(h('span', null, `Waiting behind #${item.gaveWay}`),
      `It let #${item.gaveWay} land first. While it waits, it ${item.gaveWayFixing ? 'fixes its failed tests' : 'fits its change onto main'}.`) : null;
    // A running test run says how far it has got ("testing, 4 of 6 test files": ctx.testProgress).
    const prog = col === 'building' && item.step === 'tests' ? ctx.testProgress({ files: item.files, tests: item.tests }) : null;
    meta.append(behind || h('span', null, col === 'review' ? `review ${item.review || '?'} of ${item.of || 3}`
      : (item.step === 'waiting' ? waitsOn(item.waitsOn) : (STEP[item.step] || item.step || 'in progress')) + (prog ? `, ${prog}` : '')), ctx.since(item.stepAt, ''),
      h('span', null, item.reading === false ? (item.atEnd === true ? 'cost shown when the step ends' : 'no reading yet') : ctx.money(item.usd, item.estimate === true)));
    return meta;
  }
  // A card in Building or Review (card).
  function workingCard(el, col, item) {
    const ctx = S.ctx;
    el.append(workMeta(col, item));
    // A main-red fix the loop started with the cap reached takes one slot beyond it: the Board says so.
    if (typeof item.beyond === 'string' && item.beyond) el.append(ctx.chip(`beyond the cap: ${item.beyond}`, 'warn'));
    // A card landed on an earlier day whose push failed stays here, with why.
    if (typeof item.reason === 'string' && item.reason) el.append(ctx.chip(`Push failed: ${item.reason}`, 'bad'));
  }
  // The line of a landed card: its reviews and cost, or why it was closed with no build.
  function landedMeta(item) {
    const r = num(item.reviews);
    return S.ctx.h('p', 'row-meta', item.step === 'closed' ? (splitFiled(item).length ? 'split, not built' : 'already fixed') : `${r === null ? '?' : r} review${r === 1 ? '' : 's'} · ${S.ctx.money(item.usd, item.estimate === true)}`);
  }
  // What a card has under its own lines (card): its Done-when check, stalls and split, and its seats.
  function cardFoot(el, col, item) {
    if (col !== 'held' && col !== 'queue') { doneWhen(el, item); stalls(el, item); splitNote(el, item); }
    // A landed card has no step left to run; a main-red fix card has no issue to keep settings by. A card in Needs you
    // has them too, so a blocked card's are set before its Retry; it is still answered in the Needs you panel (issue
    // 407): its settings are no answer. A card of another project is not set from here: its seats are in that project's record.
    const mine = typeof item.repo !== 'string' || !item.repo || item.repo === S.d.repo;
    if (col !== 'landed' && mine && num(item.issue) !== null && item.issue > 0) seats(el, item);
    else if (col !== 'held' && col !== 'queue') seatsNote(el, item, mine);
  }
  // The cards of one batch (batch: the cards that landed together, itself among them) are one landing: its cards are
  // one list, in the column's order, where its first card stands; a card that landed alone stays itself.
  function landings(list) {
    const out = [], batches = new Map();
    list.forEach((x) => {
      if (!Array.isArray(x.batch) || x.batch.length < 2) { out.push(x); return; }
      const k = JSON.stringify([x.repo, x.batch]);
      if (!batches.has(k)) { batches.set(k, []); out.push(batches.get(k)); }
      batches.get(k).push(x);
    });
    return out;
  }
  // One landing of a batch: a head with how many cards it landed, then each of its cards.
  function landing(cs) {
    const h = S.ctx.h, li = h('li', 'board-batch'), ul = h('ul', 'board-cards');
    ul.append(...cs.map((x) => card('landed', x)));
    li.append(h('p', 'board-batch-head', `One landing of ${cs[0].batch.length} cards`), ul);
    return li;
  }
  // A card's last Done-when check (the engine's, of its session's reply: doneWhen {items, met, failed}): how many of the
  // issue's Done-when items are met, and, opened, each failed one and each item with its text, the builder's D<n> line
  // and the reviewer's answer where there is one. The items are not in the snapshot: they are read from the page
  // server (GET donewhen: `conveyor.sh history donewhen <card>` on the build machine) each time the owner opens the
  // line, and again while it is open when the card's check or step changes (its stamp: a review's answer leaves the
  // check's count as it was, but moves the card's step). The summary keeps the focus across the draw (data-act).
  // The line stays open by card, not by column: a card that moves (Review to Building for tests) keeps it open and
  // reads the reviewer's answer. A card in two columns (Needs you and Landed today) can show two stamps: its lines open
  // together, and each stamp is read and kept on its own. A card with no check shows nothing.
  function doneWhen(el, item) {
    const h = S.ctx.h, d = item.doneWhen;
    if (!d || typeof d !== 'object' || num(d.items) === null) return;
    const failed = issues(d.failed).filter((x) => typeof x === 'string'), line = `Done when: ${num(d.met) ?? 0} of ${d.items} met`;
    const card = typeof item.card === 'string' && item.card ? item.card : null;
    if (!failed.length && !card) { el.append(h('p', 'board-from board-donewhen', line)); return; }
    const det = h('details', 'board-donewhen');
    const sum = h('summary', null, failed.length ? `${line}, ${failed.length} failed` : line);
    sum.dataset.act = 'donewhen';
    det.append(sum);
    if (failed.length) {
      const ul = h('ul', 'board-donewhen-list');
      failed.forEach((x) => ul.append(h('li', null, x)));
      det.append(ul);
    }
    if (card) {
      const stamp = JSON.stringify([d, item.step, item.stepAt, item.time]), got = S.dw.get(JSON.stringify([card, stamp])), at = card;
      det.open = S.dwOpen.has(at);
      det.addEventListener('toggle', () => {
        if (det.open === S.dwOpen.has(at)) return;  // the draw's own open, not the owner's
        if (det.open) S.dwOpen.add(at); else S.dwOpen.delete(at);
        if (det.open) readDoneWhen(item, stamp, true);
        relength();
      });
      // An open line of a card with a newer check reads its items again, after this draw.
      if (det.open && !got) Promise.resolve().then(() => readDoneWhen(item, stamp));
      if (got && got.data) det.append(dwItems(got.data));
      else if (got && got.error) det.append(h('p', 'board-from', `The items did not come: ${got.error}`));
      else if (got && got.busy) det.append(h('p', 'board-from', 'Reading the items…'));
    }
    el.append(det);
  }
  // again: the owner opened the line, so it is read even when this check's items were read before.
  function readDoneWhen(item, stamp, again) {
    const card = item.card, repo = typeof item.repo === 'string' && item.repo ? item.repo : S.d.repo, k = JSON.stringify([card, stamp]), was = S.dw.get(k);
    if (typeof repo !== 'string' || (was && (was.busy || (was.data && !again)))) return;
    const o = { busy: true, data: null, error: null };
    S.dw.set(k, o);
    draw();
    window.fetch(`donewhen?repo=${encodeURIComponent(repo)}&card=${encodeURIComponent(card)}`)
      .then((r) => (r.ok ? r.json() : r.text().then((t) => Promise.reject(new Error(String(t).trim() || `the server answered ${r.status}`)))))
      .then((x) => { if (x && typeof x === 'object' && Array.isArray(x.items)) o.data = x; else o.error = 'the answer did not read'; },
        (e) => { o.error = e && e.message ? e.message : 'no answer'; })
      .then(() => { o.busy = false; if (S.dw.get(k) === o) draw(); });
  }
  // Each item of a card's check: `D<n>: <its text>`, then who gave each line: the builder's D<n> line, and the
  // reviewer's answer when the review gave one.
  function dwItems(data) {
    const h = S.ctx.h, list = issues(data.items).filter((x) => x && typeof x === 'object' && num(x.n) !== null);
    if (!list.length) return h('p', 'board-from', 'No item of this check is on record.');
    const ul = h('ul', 'board-donewhen-items');
    list.forEach((x) => {
      const li = h('li', null), said = h('ul', 'board-donewhen-said');
      li.append(h('p', 'board-donewhen-item', `D${x.n}: ${typeof x.text === 'string' ? x.text : ''}`));
      said.append(h('li', null, `Builder: ${typeof x.builder === 'string' && x.builder ? x.builder : `no D${x.n} line`}`));
      if (typeof x.reviewer === 'string' && x.reviewer) said.append(h('li', null, `Reviewer: ${x.reviewer === 'holds' ? 'the evidence holds' : x.reviewer}`));
      li.append(said);
      ul.append(li);
    });
    return ul;
  }
  // How many times a build, fix or review of the card made no progress and the engine ended it (stalls). None shows nothing.
  function stalls(el, item) {
    const n = num(item.stalls);
    if (n) el.append(S.ctx.h('p', 'board-from board-stalls', `Stalled ${n === 1 ? 'once' : `${n} times`}: ended for no progress`));
  }
  // What the rule Split large issues made of the card's issue (split {result, slices, filed}): with the rule On, the
  // follow-ups it was split into; in shadow, how many slices the judge would have made. A kept issue shows nothing.
  function splitFiled(item) { return issues(item.split && item.split.filed).filter((x) => num(x) !== null); }
  function splitNote(el, item) {
    const s = item.split, f = splitFiled(item), n = num(s && s.slices);
    if (!s || s.result !== 'split') return;
    el.append(S.ctx.h('p', 'board-from board-split', f.length ? `Split into ${f.map((x) => `#${x}`).join(', ')}` : `Would have split into ${n}`));
  }
  // A card with no Settings (a landed one, or one of another project) that the rule Pick settings picked (seats, from
  // pickjudge(), lib/modelpick.sh) shows the same list of its seats (seatList(), above), with no buttons. A card the
  // rule did not pick shows nothing.
  function seatsNote(el, item, here) {
    if (!item.seats || typeof item.seats !== 'object') return;
    const box = S.ctx.h('div', 'board-seats');
    box.append(seatList(item, here));
    el.append(box);
  }
  window.DASH_APP.part('board-cards', function (shared) {
    ({ STEP, S, DEPENDS_MAX, num, waitsOn, issues, ctl, waiting, forced, waitsOf, kinds, waitsOnly, labelsOf,
      unlabelable, PART, elOf, relength, say, send, hold, release, shift, button, arm, slicesOf, sliceState, unshaped,
      draw } = shared);
    return { chipsOf, rulesLink, card, landings, landing };
  });
})();
