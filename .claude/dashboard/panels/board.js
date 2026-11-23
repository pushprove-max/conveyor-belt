// SPDX-License-Identifier: Apache-2.0
// The Board (the owner chose the O2 mockup): the loop on the host's main checkout, steered from here. A
// control bar (the loop's state, and when paused who paused it and how to resume; "Pause <project> after current" or
// "Resume <project>"; "Stop now and requeue N cards" with a second click; the weekly limit meter
// with the guard's mark, and today's landed count and cost; cards at once, the guard, the models and the judge are
// set on the Rules tab), then Push landed, Push now and Run full test suite with what they act on (pushTest), over six
// columns: Held, Queue, Building, Review, Needs you, Landed today (on a phone, one under another: Needs you, Building,
// Review, Queue, Held, Landed today, the last two closed to their heading and count until tapped). A card is dragged between Held and Queue, or onto a
// queued card to go before it; at phone width the columns are one list and each card has Hold, Queue, Move up and
// Move down (the keyboard: arrow keys on a card). Each of these, and Pause <project> after current and Resume <project>, acts on one click
// and the line that says it was done has Undo, which sends the opposite change. Stop now, which cannot be undone, acts
// on a second click that names what it ends. The Needs you column shows the same cards as Overview's Needs you panel,
// each leading with why it stopped, as a link into that panel, the one place they are answered. Every change is one
// POST control to the page's own host, which runs it on the Conveyor host; the record the host answers with is shown
// at once, and the loop's own state replaces it in about a minute. Cards glide to their new place when the board
// changes; never under reduced motion.
// Every open issue is on the Board. One that is not queued is in Held
// with why, one chip a reason: held by you (the control record), the label that holds it back, the rule that skips
// it, a standing rule of the loop, an issue it waits on, a card of it, a parent not landed yet. The four an owner
// changes have one name each, everywhere (issue 415): Held by you, Held by a label, Skipped by a rule (a standing rule
// and "not picked" too) and Waiting on #N; "What these mean", under the Held heading, says where each is changed.
// Held is grouped by
// reason, with a count a group (filtered by the one row over the columns); a group opens and closes, and a long one
// starts closed. A card held only by you is released as before. One held by a label is not queued by a drag: it
// offers "Remove the label and queue it" (naming the label), asks once to confirm, then removes the label on GitHub
// and releases it (POST control unlabel). One a standing rule excludes, with no label to remove, says so and is not
// queued from here; one a rule skips links to Rules. A card that waits on an open issue it depends on carries
// "Waiting on #N", each issue a link; one released while it
// still waits says so beside it at once ("Released from hold. Still waits on #N."), as the dependency guard keeps it
// unpicked. Every card in Held and Queue has "Depends on…": the owner types or picks open issues of the project it
// then depends on, each shown with its title as it is picked, or removes one its Depends on: lines name (×, its title
// beside it); the host writes the issue's `Depends on: #N` line (POST control depends), and the card says "Now waits
// on #N." until the next snapshot shows it. A cycle the host refuses is said as "#12 cannot wait on #15: #15 already
// waits on #12".
// Every card in Held, Queue, Building, Review and Needs you shows its builder, reviewer and judge, each its own, the
// Judge's pick or the project's, and has Settings and Pick for me (seats(), parts/board-cards.js): a blocked card's are set before its Retry.
// The head says how the open issues split: queued, held by you, held by a label or skipped by a rule, on the belt.
// Under it, each open parent issue is one row of its parts (parents(), parts/board-push.js).
// Its part (dashboard.sh, board): {repo (null: no record is on the host's main), state, reason (why it picks nothing | null), loop, control, cap, guard,
// modelSettings, limit, held, queue (room on the one the machine holds back: why, as "waiting for a machine slot: ..."), skipped, waits (issues waiting on another, with waitsFor), issuesError,
// building, review, waiting, blocked, landed (the day's newest; each with batch: the cards it landed with, itself among them | null;
// each card with seats: the seats the rule Pick settings gave it | null),
// today ({landed, usd}: every card of the day, counted and its usd added up, null when one has none), open ({count, split, held: each with its reasons, umbrellas: each open parent with its parts} | null),
// unpushed (the landed cards origin lacks | null), fullTest (command, why, running, last | null), and checkRuns
// (only when a pack names checks.progress: each record's {repo, error}, or its run with repo, counts, done, all and leftSec;
// with repo null too, when the Board shows those runs under "No loop to steer"), areaPrefix, repos (every project on
// the host) and others ({repo: the same part} of every other project)}. With more than one project the machine head's
// Show picks the one shown (?project=, with ?repo=; with Show at every project the Board asks for a project), and the
// heading names it ("Board: sample"); every change names it. One row filters every column by number or title,
// priority, area and label and sorts it by priority, number or time in the column, the choices but the text kept in the
// address too; a column the filter empties says so, with Clear. Landed today shows its newest five, then "Show all (N)".
// Its one part is drawn as three panels of the Control tab (PANELS): Loop (the control bar), Push landed and full test
// suite (pushTest and the check runs), and Board (the row that filters, the split, its line and the columns). Each
// panel has its own line, saying what an action in it did (say).
(function () {
  'use strict';
  const MOTION_MS = 260;
  const ARM_MS = 5000;  // Stop now, Remove the label, Push landed, Push now, Run full test suite and Push anyway wait this long for their second click
  const LONG = 8;       // a Held group longer than this starts closed
  const PAGE = 100;     // a column shows this many cards, then more on a click (the owner's figure for the Board)
  const STATES = {
    running: ['Running', 'ok'], paused: ['Paused', 'warn'], 'paused by guard': ['Paused by guard', 'warn'],
    stopped: ['Stopped', 'bad'], 'control record unreadable': ['Settings not read', 'bad'],
  };
  const COLS = [['held', 'Held'], ['queue', 'Queue'], ['building', 'Building'], ['review', 'Review'], ['needs', 'Needs you'], ['landed', 'Landed today']];
  const STEP = { brief: 'getting ready', build: 'building', fix: 'fixing', tests: 'testing', landing: 'landing', push: 'pushing', issue: 'closing the issue' };
  // The reasons an issue is held, in the order its group is drawn: the first reason of an issue is its group.
  // approve: it waits for the owner's yes before its build, answered in Needs you.
  const KINDS = ['you', 'label', 'rule', 'standing', 'approve', 'card', 'parent', 'waits', 'other'];
  const S = { d: null, ctl: null, at: new Map(), from: 'board', heard: new WeakSet(), raw: null, ctx: null, armed: false, unarm: null, dragging: null, busy: false, keep: null, ctlAt: null, moved: new Map(), floor: null, read: null, turned: false, lanesOpen: {}, lanesShown: {},
    groups: new Map(), filter: { text: '' }, text: null, unlabeled: new Set(), released: new Set(),
    dep: null, depText: '', depSaid: new Map(),
    seats: null, picks: new Map(),  // the card whose Settings is open ({issue, draft}), and each card's Pick for me ({busy}, {data} or {error})
    dw: new Map(), dwOpen: new Set(),  // a card's Done-when items by card and check stamp ({busy, data, error}), and the cards whose line is open
    partsOpen: new Set() };  // the parents whose row of parts is open
  const DEPENDS_MAX = 20;  // the issues one depends takes (dashboard_server.py)

  const num = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : null);
  // A card waiting on a same-file card: that card's issue and where it is (blocked, queued, its step on the belt).
  const waitsOn = (w) => (w && typeof w === 'object' ? `waiting on ${typeof w.name === 'string' && w.name ? w.name : num(w.issue) !== null ? `#${w.issue}` : 'a card'}${w.state ? ` (${w.state})` : ''}` : 'waiting');
  const issues = (list) => (Array.isArray(list) ? list : []);

  // The control record in force here: the one the host last answered with, else the snapshot's.
  const ctl = () => S.ctl || (S.d.control && typeof S.d.control === 'object' ? S.d.control : null);
  // A card released since the snapshot, and not put in the order, takes the place pick gives it: follow-ups
  // first, then by priority, then the older issue by the host's createdAt (pick's oldest first; an issue moved from
  // another repo keeps its date, so its number does not stand for its age). One with no date goes after the dated ones.
  const rank = (x) => [x.followup ? 0 : 1, /^P[0-3]$/.test(x.priority) ? x.priority : 'P3',
    typeof x.created === 'string' && x.created ? x.created : '~', num(x.issue) ?? Infinity];
  const ahead = (a, b) => { const p = rank(a), q = rank(b); for (let i = 0; i < p.length; i++) if (p[i] !== q[i]) return p[i] < q[i]; return false; };
  // An issue that waits on an open issue it depends on is not in the pick order either: it goes after the
  // queue as "Waiting on #N". One forced past its wait (`control force`, the dependency guard off) is queued,
  // tagged "Forced past #N".
  const waiting = (x) => Array.isArray(x.waitsFor) && x.waitsFor.length > 0 && x.forced !== true;
  const forced = (x) => Array.isArray(x.waitsFor) && x.waitsFor.length > 0 && x.forced === true;
  // The open issues a card waits on, as its Held reason or the snapshot's waits name them.
  const waitsOf = (x) => { const r = issues(x.reasons).find((y) => y && y.kind === 'waits'); return issues(r ? r.waitsFor : x.waitsFor); };
  // Why an issue is held: the snapshot's reasons, with "you" as the record in force says (a hold or release answered
  // since the snapshot moves the card at once) and the rule that skips it. The snapshot's own "you" is kept as it
  // came: outside says someone outside the project opened the issue.
  function reasonsOf(x, mine) {
    const base = issues(x.reasons).filter((r) => r && KINDS.includes(r.kind) && r.kind !== 'you');
    if (x.rule && !base.some((r) => r.kind === 'rule')) base.push({ kind: 'rule', rule: x.rule });
    const you = issues(x.reasons).find((r) => r && r.kind === 'you') || { kind: 'you' };
    return mine.has(x.issue) ? [you].concat(base) : base;
  }
  // Held, Queue and Waits as the record says. A card is in Held while anything holds it; the snapshot may list one
  // under several parts, and it is shown once. One a control answer moved between Held and Queue since the snapshot
  // came to its column when the host answered that move (S.moved; none when not known), even one moved back: not when
  // the snapshot saw it in a column, nor when a later answer moved another card.
  function lanes() {
    const d = S.d, c = S.ctl;
    if (!d.queue || !d.held) return { held: d.held ? d.held.map((x) => Object.assign({ reasons: [{ kind: 'you' }] }, x)) : null, queue: d.queue || null, waits: [] };
    const by = new Map();
    issues(d.open && d.open.held).concat(d.held, d.queue, issues(d.waits), issues(d.skipped)).forEach((x) => by.set(x.issue, Object.assign({}, by.get(x.issue), x)));
    const all = Array.from(by.values());
    const mine = new Set(c ? issues(c.held) : issues(d.held).map((x) => x.issue).concat(issues((d.control || {}).held)));
    all.forEach((x) => { x.reasons = reasonsOf(x, mine); });
    const free = all.filter((x) => !x.reasons.length);
    const waits = free.filter(waiting);
    const queued = new Set(d.queue.map((x) => x.issue));
    const order = c ? issues(c.order) : [];
    const queue = free.filter((x) => !waiting(x) && queued.has(x.issue));
    free.filter((x) => !waiting(x) && !queued.has(x.issue)).forEach((x) => {
      const at = queue.findIndex((y) => !order.includes(y.issue) && ahead(x, y));
      queue.splice(at < 0 ? queue.length : at, 0, x);
    });
    const pinned = order.map((n) => queue.find((x) => x.issue === n)).filter(Boolean);
    const came = (x) => (S.moved.has(x.issue) ? Object.assign({}, x, { since: S.moved.get(x.issue) }) : x);
    return { held: all.filter((x) => x.reasons.length).map(came), queue: pinned.concat(queue.filter((x) => !order.includes(x.issue))).map(came), waits };
  }
  const kinds = (x) => issues(x.reasons).map((r) => r.kind);
  // Its card landed while push is off and is not pushed yet: done, waiting for the push, not held back.
  const notPushed = (x) => issues(x && x.reasons).some((r) => r && r.kind === 'card' && r.notPushed === true);
  const onlyMine = (x) => kinds(x).length > 0 && kinds(x).every((k) => k === 'you');
  // In Held only because it waits on another issue: nobody holds it back.
  const waitsOnly = (x) => kinds(x).length > 0 && kinds(x).every((k) => k === 'waits');
  const labelsOf = (x) => issues(x.reasons).filter((r) => r.kind === 'label').map((r) => r.label);
  // Removing its labels queues it: nothing holds it but labels (and you, which the removal releases too).
  const unlabelable = (x) => labelsOf(x).length > 0 && kinds(x).every((k) => k === 'label' || k === 'you');

  // The part, and the ids of the tab's panels drawn from it (PANELS): Board is the part's own id.
  const PART = 'board', LOOP = `${PART}-loop`, PUSH = `${PART}-push`;
  // The place and the page's ctx of one of the tab's panels (PANELS), once the page has drawn it.
  const elOf = (id) => (S.at.has(id) ? S.at.get(id).el : null);
  const cx = (id) => (S.at.has(id) ? S.at.get(id).ctx : S.ctx);
  // Each of the tab's panels works its length out again: rows came or went (a group opened, a card moved).
  const relength = () => S.at.forEach((p) => p.ctx.relength());
  // The board's line: what was asked or done, with Undo after a change easily undone (undo sends its opposite). Each of
  // the tab's panels has its own (in Board, over the columns): the line shows in the panel the action came from (where,
  // by default S.from: the panel last clicked, typed or dropped in), so a panel folded away never holds what another
  // panel's action said, and the other panels' lines are emptied.
  function say(text, undo, where = S.from) {
    S.at.forEach(({ el }, id) => {
      const n = el.querySelector('.board-note');
      if (n) n.replaceChildren(...(id !== where ? [] : [undo ? S.ctx.undoLine(text, undo) : text]));
    });
  }
  // A panel's line, empty until an action there says something.
  const noteLine = () => { const n = S.ctx.h('p', 'board-note'); n.setAttribute('aria-live', 'polite'); return n; };
  // One action to the page's host. A control action's answer is the record as it now stands. One at a time: while an
  // action is out, the board's controls are off and no other is sent, so a second click cannot resend what the first
  // sent (two raises of the cap from the same number would be one raise). undo: what Undo on the line sends, once done;
  // it is called with the project this change went to, and sends to that one even after another project is picked.
  function send(action, args, done, repo, undo) {
    if (S.busy) { say('Wait: the build machine did not answer the last change yet.'); return Promise.resolve(false); }
    // Its answer shows in the panel it was asked from, whatever panel is clicked while it is out.
    const where = S.from, tell = (text, u) => say(text, u, where);
    S.busy = true; draw();
    tell('Sending…');
    const free = (ok) => { S.busy = false; draw(); return ok; };
    // Every action names the project it is for: the one on screen when it was asked for, or the card's own (Needs
    // you). An answer that comes after another project was picked is that project's record: it is not shown.
    const to = repo || S.d.repo;
    return S.ctx.post('control', { action, args, repo: to }).then((r) => r.text().then((t) => {
      const said = String(t).trim();
      if (!r.ok) { tell(`Not done: ${said ? S.ctx.refusal(said) : `the build machine answered ${r.status}`}`); return false; }
      let rec = null;
      try { rec = JSON.parse(said); } catch (e) { rec = null; }
      const here = to === S.d.repo;
      // When the page's host had the answer (X-Answered-At: its clock, in whole seconds rounded up). A snapshot the
      // collector began at or after it read the record, and the issues, after this change.
      const at = Number(r.headers && typeof r.headers.get === 'function' ? r.headers.get('X-Answered-At') : NaN);
      if (here && rec && typeof rec === 'object' && typeof rec.mode === 'string') {
        // Each card this answer moves into or out of Held came to its column then; the others keep their time.
        const inHeld = () => new Set(issues(lanes().held).map((x) => x.issue));
        const was = inHeld();
        S.ctl = rec; S.ctlAt = Number.isFinite(at) && at > 0 ? at * 1000 : null;
        const now = inHeld(), when = S.ctlAt ? new Date(S.ctlAt).toISOString() : null;
        new Set([...was, ...now]).forEach((n) => { if (was.has(n) !== now.has(n)) S.moved.set(n, when); });
      }
      // The build machine's own reply is shown only when the action failed.
      tell('Done. The Board shows it in about a minute.', here && undo ? () => undo(to) : null);
      if (done && here) done(Number.isFinite(at) && at > 0 ? at * 1000 : null);
      return true;
    })).then(free, () => { tell('Not done: the build machine did not answer. Make sure that it is on. Then try again.'); return free(false); });
  }

  // ---- moving cards between Held and Queue ----
  // Hold and Queue undo each other.
  function hold(item) { const n = String(item.issue); send('hold', [n], null, null, (r) => send('release', [n], null, r)); }
  // Released before a queued card: its place in the order is set while it is still held, and only then is it
  // released, so a loop that picks between the two never takes it ahead of where it was put. Both name the project
  // the card was moved in, whichever is picked while the first is out.
  // A card released while an issue it depends on is open says so beside it at once (S.released), for as long as it
  // still waits, in the project it was released in: another project picked forgets it.
  function release(item, before) {
    const n = String(item.issue), done = () => { if (waitsOf(item).length) S.released.add(item.issue); };
    const undo = (r) => send('hold', [n], null, r);
    if (!before) { send('release', [n], done, null, undo); return; }
    const repo = S.d.repo;
    place(item, before).then((ok) => { if (ok) send('release', [n], done, repo, undo); });
  }
  // A held card dropped on the queue: released when only the owner holds it. A label, a rule or a standing rule is not
  // undone by a drag: the card says what to do instead.
  function dropOnQueue(item, before) {
    const t = `#${item.issue}`, um = slicesOf(item);
    if (um.length) { say(`${t} is not built itself: it closes when ${um.map((n) => `#${n}`).join(', ')} land. Queue those instead.`); return; }
    if (onlyMine(item)) { release(item, before); return; }
    if (unlabelable(item)) say(`A label holds ${t} (${labelsOf(item).join(', ')}): use "Remove the label and queue it" on the card.`);
    else if (kinds(item).includes('standing')) say(`A rule of Conveyor's own skips ${t}: you cannot queue it from the Board.`);
    else if (kinds(item).includes('rule')) say(`A rule skips ${t}. To queue it, change the rule in Rules.`);
    else say(`Other holds also keep ${t} held: ${chipsOf(item).join(', ')}.`);
  }
  // The issue goes before `before` in the queue: the order sent is the queue up to it, and every issue the record
  // already put first, so nothing that was ordered loses its place. A pin above every open issue (filed after the
  // snapshot's list was read, so not in the queue yet) is kept too, as the engine keeps it: it goes after every pin the
  // record had above it and before every pin the record had below it, so it moves past none of them. The issue moved does
  // not set that place, as it can now be anywhere; but when it was above the newer pin and still is in that place, the
  // newer pin stays after it.
  function place(item, before) {
    const q = lanes().queue || [];
    const rest = q.filter((x) => x.issue !== item.issue);
    const at = before ? rest.findIndex((x) => x.issue === before.issue) : rest.length;
    if (at < 0) return Promise.resolve(false);
    rest.splice(at, 0, item);
    const pinned = issues((ctl() || {}).order);
    const last = Math.max(at, ...rest.map((x, i) => (pinned.includes(x.issue) ? i : -1)));
    // Undo puts the order back as the record had it.
    const was = pinned.map(String);
    const listed = S.d.open && Array.isArray(S.d.open.issues) ? S.d.open.issues.map((x) => x && x.issue) : null;
    const fresh = !listed ? [] : pinned.filter((n) => n > Math.max(0, ...listed) && !q.some((x) => x.issue === n)).map(String);
    const out = rest.slice(0, last + 1).map((x) => String(x.issue));
    const moved = String(item.issue), wasAt = was.indexOf(moved);
    const kept = (m) => m !== moved && out.includes(m), placeOf = (m) => out.indexOf(m);
    for (const n of fresh) {
      const k = was.indexOf(n), i = out.indexOf(moved);
      const lo = Math.max(-1, ...was.slice(0, k).filter(kept).map(placeOf)) + 1;
      const hi = Math.min(out.length, ...was.slice(k + 1).filter(kept).map(placeOf));
      out.splice(wasAt >= 0 && wasAt < k && i >= lo && i < hi ? i + 1 : lo, 0, n);
    }
    return send('order', out, null, null, (r) => send('order', was, null, r));
  }
  function shift(item, by) {
    const q = lanes().queue || [], i = q.findIndex((x) => x.issue === item.issue), to = i + by;
    if (i < 0 || to < 0 || to >= q.length) return;
    place(item, by < 0 ? q[to] : q[to + 1] || null);
  }

  // ---- the control bar ----
  function button(text, cls, act, label, fn) {
    const b = S.ctx.h('button', `btn ${cls || ''}`.trim(), text);
    b.type = 'button'; b.dataset.act = act; b.setAttribute('aria-label', label || text);
    b.addEventListener('click', fn);
    return b;
  }
  function bar() {
    const d = S.d, h = S.ctx.h, c = ctl();
    const mode = c ? c.mode : null;
    // A record the host just answered with says what the next pick does before the snapshot does.
    const st = S.ctl && mode !== (d.control || {}).mode ? { run: 'running', pause: 'paused', stop: 'stopped' }[mode] : d.state;
    const [said, tone] = STATES[st] || [String(st || 'not read'), 'quiet'];
    // A loop paused while a check run goes is paused for it.
    const word = st === 'paused' && running() ? `Paused for ${running().name}` : said;
    const el = h('div', 'board-bar');
    const state = h('div', 'board-state');
    state.dataset.state = st || '';
    const chip = S.ctx.chip(word, tone);
    state.append(h('span', 'board-label', 'Conveyor'), chip);
    if (d.loop === false) state.append(S.ctx.chip('Not running on the build machine', 'quiet'));
    // The commit the running loop started on, so a loop left on old code is seen: on the state's hover and tap, never
    // as a code on the bar.
    else if (d.commit) S.ctx.tip(chip, `${word}: Conveyor started on its code of commit ${d.commit.slice(0, 7)}`);
    if (st === d.state && d.reason) state.append(h('span', 'board-from', d.reason));
    // Paused or stopped: who did it and how to start it again, in one line.
    const why = S.ctx.pausedSaid(st, d.repo, c && num(c.guard) !== null ? c.guard : null, st === d.state ? d.reason : null);
    if (why) state.append(h('span', 'board-paused', why));
    el.append(state);
    // Each control names the project it acts on, and Stop now its cost: how many cards in progress it sends back to
    // the queue (Building and Review). A card the engine's stop leaves running (stays, from the server: landed, filing
    // its follow-ups, the slices of a split or landing, or filed them) is not counted.
    const acts = h('div', 'board-acts'), repo = d.repo;
    const ends = (x) => x.stays !== true;
    const live = issues(d.building).filter(ends).length + issues(d.review).filter(ends).length;
    const cost = `${live} ${live === 1 ? 'card' : 'cards'}`;
    // Pause and Resume undo each other; Stop now cannot be undone (the work in progress is lost): its second click says so.
    if (mode === 'run') acts.append(button(`Pause ${repo} after current`, null, 'pause', `Pause ${repo} after current: the cards in progress finish, and Conveyor picks nothing new`, () => send('pause', [], null, null, (r) => send('resume', [], null, r))));
    else acts.append(button(`Resume ${repo}`, 'btn-primary', 'resume', `Resume ${repo}: Conveyor picks again`, () => send('resume', [], null, null, mode === 'pause' ? (r) => send('pause', [], null, r) : null)));
    const armed = S.armed === 'stop';
    const stop = button(armed ? `Click again: stop and requeue ${cost}` : `Stop now and requeue ${cost}`, 'btn-final', 'stop', armed ? `Click again to stop now and send ${cost} back to the queue` : `Stop now: the ${cost} in progress end and go back to the queue`, () => {
      if (!armed) { arm('stop'); return; }
      S.armed = false; draw(); send('stop', []);
    });
    stop.disabled = mode === 'stop';
    stop.setAttribute('aria-pressed', String(armed));
    if (armed) stop.dataset.armed = '';
    acts.append(stop);
    el.append(acts);
    // What the two controls do, printed under them at phone width (app.css, .phone-note), where no hover text shows.
    // Stopped, Stop now is disabled, so the note says nothing of it.
    el.append(h('p', 'phone-note', `${mode === 'run' ? 'Pause after current: the cards in progress finish, and Conveyor picks nothing new.' : `Resume ${repo}: Conveyor picks again.`}${mode === 'stop' ? '' : ' Stop now: the cards in progress end and go back to the queue.'}`));

    // The weekly limit with the guard's mark on it (the guard is set on the Rules tab).
    const guard = c && num(c.guard) !== null ? c.guard : null;
    const pct = d.limit ? num(d.limit.pct) : null;
    const lim = h('div', 'board-ctl');
    lim.dataset.figure = 'limit';
    const meter = h('span', 'board-meter');
    meter.setAttribute('role', 'img');
    meter.setAttribute('aria-label', `${pct === null ? 'Weekly limit not read' : `${Math.round(pct)} percent of the weekly limit used`}${guard === null ? ', no guard' : `, Conveyor pauses when the weekly limit reaches ${guard} percent`}`);
    const track = h('span', 'meter'), fill = h('span', 'meter-fill');
    fill.style.transform = `scaleX(${pct === null ? 0 : Math.max(0, Math.min(100, pct)) / 100})`;
    track.append(fill);
    meter.append(track);
    if (pct !== null && guard !== null && pct >= guard) meter.classList.add('over');
    if (guard !== null) { const mark = h('span', 'board-guard'); mark.style.left = `${guard}%`; meter.append(mark); }
    lim.append(h('span', 'board-label', 'Weekly limit'), meter, h('span', 'board-value', pct === null ? 'not read' : `${Math.round(pct * 10) / 10}%`));
    if (guard === null) lim.append(h('span', 'board-from', 'no guard'));
    else if (d.guard && d.guard.missing) lim.append(h('span', 'board-from', 'no reading on the build machine: nothing pauses for the limit'));
    el.append(lim);

    // Every card of the day, counted and its cost added up by the snapshot: the landed list holds only its newest.
    const day = d.today || {}, n = num(day.landed);
    const today = h('div', 'board-ctl board-today');
    today.dataset.figure = 'today';
    today.append(h('span', 'board-label', 'Today'), h('span', 'board-value', n === null ? 'not read' : `${n} landed`), cx(LOOP).number('board-usd', num(day.usd), S.ctx.money));
    el.append(today);
    return el;
  }
  // A two-step control (Stop now, Remove the label): the first click arms it, the second acts; it forgets the first
  // after a while.
  function arm(what) {
    S.armed = what; draw();
    if (S.unarm) window.clearTimeout(S.unarm);
    S.unarm = window.setTimeout(() => { if (S.armed === what) { S.armed = false; draw(); } }, ARM_MS);
  }
  // The check runs (each record's pack's checks.progress, as its snapshot gives it, with its repo): while one runs
  // and for an hour after it ends (the snapshot drops it after that), its name, commit, elapsed time, lanes done of
  // all, the counts, the time left once the host estimates it, the failed lanes, the running lanes with how long each
  // has run, and every lane in a list that shows LANES at a time. The record's repo names a run of a record the
  // Board does not steer. Nothing without one. The times that count on are in [data-from]: tick() moves them.
  const LANES = 5;
  const runs = () => issues(S.d.checkRuns).filter((r) => r && typeof r === 'object');
  const running = () => runs().find((r) => r.repo === S.d.repo && !r.error && r.ended == null) || null;
  const at = (iso) => { const t = typeof iso === 'string' ? Date.parse(iso) : NaN; return Number.isNaN(t) ? null : t; };
  // A time from iso to now that tick() keeps counting.
  function counting(iso) {
    const el = S.ctx.h('span', 'board-took', S.ctx.took((Date.now() - at(iso)) / 1000));
    el.dataset.from = iso;
    return el;
  }
  function checkTiles() { return runs().map(checkTile); }
  // more: the host has other projects, picked under Show in the machine head.
  const noLoop = (ctx, more) => ctx.state('empty', 'Nothing to steer here', `Conveyor did not run on this project on the build machine yet, so there is nothing to steer.${more ? ' Pick a project under Show, above the tabs.' : ' Start Conveyor there, and its cards show here.'}`);
  function checkTile(r) {
    const h = S.ctx.h, key = String(r.repo);
    const tile = h('section', 'board-checkrun');
    tile.dataset.figure = 'checkrun';
    tile.dataset.repo = key;
    tile.setAttribute('aria-label', 'Check run');
    const label = r.repo === S.d.repo ? 'Check run' : `Check run, ${r.repo}`;
    if (r.error) { tile.append(h('span', 'board-label', label), h('span', 'warn-note', String(r.error))); return tile; }
    const lanes = issues(r.lanes), c = r.counts || {}, n = (k) => num(c[k]) ?? 0;
    const start = at(r.started), end = r.ended == null ? null : at(r.ended);
    const head = h('div', 'board-check-head');
    head.append(h('span', 'board-label', label), h('span', 'board-value', String(r.name || '')), h('code', null, String(r.sha || '').slice(0, 7)),
      start === null ? h('span', null, '') : r.ended == null ? counting(r.started) : h('span', null, end === null ? '' : S.ctx.took((end - start) / 1000)));
    // Its result once it ended: fail, the other result, or none.
    if (r.ended != null) head.append(S.ctx.chip(...(r.result === 'fail' ? ['Failed', 'bad'] : r.result ? ['Passed', 'ok'] : ['Ended', 'quiet'])));
    const done = num(r.done) ?? 0, all = num(r.all) ?? lanes.length;
    const meter = h('span', 'board-meter');
    meter.setAttribute('role', 'img');
    meter.setAttribute('aria-label', `${done} of ${all} lanes done`);
    const track = h('span', 'meter'), fill = h('span', 'meter-fill');
    fill.style.transform = `scaleX(${all ? done / all : 0})`;
    track.append(fill); meter.append(track);
    const prog = h('div', 'board-ctl');
    prog.append(meter, h('span', 'board-value', `${done}/${all} lanes`));
    if (num(r.leftSec) !== null && r.ended == null) prog.append(h('span', 'board-from', `~${S.ctx.took(r.leftSec)} left`));
    const counts = h('p', 'board-split');
    counts.append(h('span', null, `${n('passed')} passed`), h('span', null, `${n('failed')} failed`), h('span', null, `${n('running')} running`), h('span', null, `${n('queued')} queued`));
    if (n('reused')) counts.append(h('span', null, `${n('reused')} reused`));
    tile.append(head, prog, counts);
    const failed = lanes.filter((l) => l && l.state === 'failed');
    if (failed.length) tile.append(h('p', 'board-check-failed', `Failed: ${failed.map((l) => l.name).join(', ')}`));
    // A running lane's name, then how long it has run, counting on.
    const ran = (l) => (at(l.started) === null ? [String(l.name)] : [`${l.name} (`, counting(l.started), ')']);
    const run = lanes.filter((l) => l && l.state === 'running');
    if (run.length) {
      const p = h('p', 'board-check-running', 'Running: ');
      run.forEach((l, i) => p.append(...(i ? [', '] : []), ...ran(l)));
      tile.append(p);
    }
    const det = h('details', 'board-check-lanes'), ul = h('ul', 'board-check-list');
    det.append(h('summary', null, `Every lane (${lanes.length})`), ul);
    det.open = !!S.lanesOpen[key];
    det.addEventListener('toggle', () => { S.lanesOpen[key] = det.open; relength(); });
    const shown = S.lanesShown[key] || LANES;
    ul.append(...lanes.slice(0, shown).map((l) => {
      const li = h('li', null, `${l.name} · ${l.state}`);
      if (l.state === 'running') { if (at(l.started) !== null) li.append(' (', counting(l.started), ')'); }
      else if (num(l.sec) !== null) li.append(` (${S.ctx.took(l.sec)})`);
      return li;
    }));
    if (lanes.length > shown) {
      det.append(button('Show more', 'btn-quiet', 'lanes-more', `Show ${LANES} more lanes`, () => { S.lanesShown[key] = shown + LANES; draw(); }));
    }
    tile.append(det);
    return tile;
  }
  // Held, grouped by reason: a count a group, open and closed by the owner (a long one starts closed). got: the held
  // cards the filter keeps; all: every held card.
  function drawHeld(col, got, all) {
    const h = S.ctx.h, box = col.querySelector('.board-groups');
    // The filter searches every held card; the matches, group by group, are then shown PAGE at a time.
    const order = (a, b) => groupRank(groupOf(a)) - groupRank(groupOf(b)) || groupOf(a).localeCompare(groupOf(b));
    const shown = got.slice().sort(order);
    const count = (list) => { const m = new Map(); list.forEach((x) => { const k = groupOf(x); m.set(k, (m.get(k) || 0) + 1); }); return m; };
    const matches = count(shown), total = count(all);
    const paint = (part) => {
      const groups = new Map();
      part.forEach((x) => { const k = groupOf(x); groups.set(k, (groups.get(k) || []).concat([x])); });
      box.replaceChildren(...Array.from(groups.keys()).map((k) => {
        const list = groups.get(k), det = h('details', 'board-group'), sum = h('summary', 'board-group-head');
        det.dataset.group = k;
        const n = matches.get(k), of = total.get(k);
        sum.append(h('span', null, groupTitle(k)), h('span', 'panel-count', n === of ? String(n) : `${n} of ${of}`));
        const ul = h('ul', 'board-cards');
        ul.setAttribute('aria-label', groupTitle(k));
        ul.append(...list.map((x) => card('held', x)));
        det.append(sum, ul);
        det.open = S.groups.has(k) ? S.groups.get(k) : of <= LONG;
        det.addEventListener('toggle', () => { S.groups.set(k, det.open); relength(); });
        return det;
      }));
      if (!all.length) box.replaceChildren(h('p', 'board-empty', EMPTY.held));
      else if (!shown.length) box.replaceChildren(unmatched('p', UNMATCHED.held));
      lock(box);
    };
    return cx(PART).more('held', shown, paint, PAGE);
  }
  // "What these mean", under the Held heading: the four reasons an issue is not being built, each with where it is changed.
  function meanings() {
    const h = S.ctx.h, det = h('details', 'board-meanings'), dl = h('dl', null);
    det.append(h('summary', null, 'What these mean'));
    const item = (term, ...said) => { const dd = h('dd', null); dd.append(...said); dl.append(h('dt', null, term), dd); };
    item('Held by you', 'You held it. Release it here: Queue on the card, or drag it to Queue.');
    item('Held by a label', 'A label on the issue holds it. Remove the label here: "Remove the label and queue it" on the card.');
    item('Skipped by a rule', 'A rule skips it. Change the rule in ', rulesLink(), '.');
    item('Waiting on #N', 'It waits for that card. Conveyor picks it when that card closes. Follow the link to see that card.');
    det.append(dl);
    return det;
  }
  function column(key, title) {
    const h = S.ctx.h, col = h('section', 'board-col');
    col.dataset.col = key;
    const head = h('h3', 'board-head', title);
    head.id = `board-col-${key}`;
    const count = h('span', 'panel-count');
    head.append(count);
    // On a phone (app.css) Held and Landed today are their heading and count until tapped open; wider, the button is
    // not shown and the column is always open.
    if (key === 'held' || key === 'landed') {
      const fold = h('button', 'board-fold', 'Show');
      fold.type = 'button'; fold.dataset.act = `fold-${key}`;
      fold.setAttribute('aria-expanded', 'false');
      fold.setAttribute('aria-label', `Show ${title}`);
      fold.addEventListener('click', () => {
        const on = !col.classList.contains('open');
        col.classList.toggle('open', on);
        fold.textContent = on ? 'Hide' : 'Show';
        fold.setAttribute('aria-expanded', String(on));
        fold.setAttribute('aria-label', `${on ? 'Hide' : 'Show'} ${title}`);
        relength();
      });
      head.append(fold);
    }
    const note = h('p', 'warn-note');
    note.hidden = true;
    col.append(head, note);
    if (key === 'held') col.append(meanings(), h('div', 'board-groups'));
    else {
      const list = h('ul', 'board-cards');
      list.setAttribute('aria-labelledby', head.id);
      col.append(list);
    }
    if (key === 'held' || key === 'queue') {
      col.addEventListener('dragover', (e) => {
        if (!S.dragging) return;
        e.preventDefault();
        if (!col.classList.contains('over')) { elOf(PART).querySelectorAll('.over').forEach((x) => x.classList.remove('over')); col.classList.add('over'); }
      });
      col.addEventListener('dragleave', (e) => { if (!col.contains(e.relatedTarget)) col.classList.remove('over'); });
      col.addEventListener('drop', (e) => {
        const drag = S.dragging;
        if (!drag) return;
        e.preventDefault();
        col.classList.remove('over');
        S.dragging = null;
        const on = e.target && e.target.closest ? e.target.closest('.bcard') : null;
        const target = on && on.dataset.col === 'queue' && Number(on.dataset.issue) !== drag.item.issue ? (lanes().queue || []).find((x) => String(x.issue) === on.dataset.issue) : null;
        if (key === 'held' && drag.col === 'queue') hold(drag.item);
        else if (key === 'queue' && drag.col === 'held') dropOnQueue(drag.item, target);
        else if (key === 'queue' && drag.col === 'queue' && target && !waiting(drag.item)) place(drag.item, target);
      });
    }
    return col;
  }

  // Draws the bar and the six columns. A card that is still on the board, in another column or at another place in
  // its column, glides from where it was to where it is now (transform only), and keeps the keyboard focus; a card new
  // to the board comes in with `enter`.
  // While a change is out the cards' controls are off, on a page drawn by "Show more" too.
  const lock = (root) => { if (S.busy) root.querySelectorAll('.bcard button').forEach((b) => { b.disabled = true; }); };
  // The tab's panels, in their default order, each drawn from the one Board part: [id, title].
  const PANELS = [[LOOP, 'Loop'], [PUSH, 'Push landed and full test suite'], [PART, 'Board']];
  // Draws the tab's panels (only: the one panel with that id), each in the place the page gave it (S.at). A draw from
  // render (rendered) does not work the lengths out: the page runs arrange() after it draws a part, which cuts every
  // panel once; relength() here would measure each panel's rows a second time.
  function draw(only, rendered) {
    const fit = () => { if (!rendered) relength(); };
    if (S.ctx.picking()) return;  // Show at every project: the page shows the project choice, a timer or a reply draws no project over it
    const h = S.ctx.h, motion = S.ctx.motion(), at = (id) => (!only || only === id ? elOf(id) : null);
    const top = at(LOOP), pushes = at(PUSH), el = at(PART);
    // No record steered, and another record's check run to show: the empty Board, then the runs (in Push landed and
    // full test suite); another project on the host is picked in the machine head.
    if (S.d.repo === null) {
      [top, pushes, el].forEach((x) => { if (x) x.replaceChildren(noLoop(S.ctx, issues(S.d.repos).length > 1)); });
      if (pushes) { const check = h('div', 'board-check'); check.append(...checkTiles()); pushes.append(check); }
      fit();
      return;
    }
    const a = document.activeElement, from = a ? Array.from(S.at).find(([, p]) => p.el.contains(a)) : null;
    // The focus a pending action took (its control was off) comes back when the controls do.
    const keep = (from ? { panel: from[0], issue: a.closest('.bcard') && a.closest('.bcard').dataset.issue, col: a.closest('.bcard') && a.closest('.bcard').dataset.col, act: a.dataset.act || null, card: a.classList.contains('bcard'), filter: a.dataset.filter || null,
      parent: a.closest('.board-parent') && a.closest('.board-parent').dataset.issue, part: a.closest('.board-part') && a.closest('.board-part').dataset.part } : null) || S.keep;
    S.keep = null;
    if (top) {
      if (!top.querySelector('.board-top')) top.replaceChildren(h('div', 'board-top'), noteLine());
      top.querySelector('.board-top').replaceChildren(bar());
    }
    if (pushes) {
      if (!pushes.querySelector('.board-pushes')) pushes.replaceChildren(h('div', 'board-pushes'), noteLine(), h('div', 'board-check'));
      pushes.querySelector('.board-pushes').replaceChildren(pushTest());
      pushes.querySelector('.board-check').replaceChildren(...checkTiles());
    }
    if (S.busy) [top, pushes].forEach((x) => { if (x) x.querySelectorAll('.board-top button, .board-top select, .board-pushes button').forEach((b) => { b.disabled = true; }); });
    if (el) cards(el, motion);
    const to = keep && at(keep.panel);
    if (to) {
      // A card in two columns: the one in the column the focus was in, else (it moved) the card where it is now.
      const c = keep.issue ? (keep.col && to.querySelector(`.bcard[data-col="${keep.col}"][data-issue="${keep.issue}"]`)) || to.querySelector(`.bcard[data-issue="${keep.issue}"]`) : null;
      // In a parent's row: its part's link (by the part), else its summary, which is drawn again on every draw.
      const row = keep.parent ? to.querySelector(`.board-parent[data-issue="${keep.parent}"]`) : null;
      const inRow = row && (keep.part ? row.querySelector(`.board-part[data-part="${keep.part}"] [data-act="part-card"]`) : row.querySelector(':scope > summary'));
      const again = keep.parent ? inRow : keep.filter ? to.querySelector(`[data-filter="${keep.filter}"]`) : keep.card ? c : (keep.act ? (c || to).querySelector(`[data-act="${keep.act}"]`) : null);
      if (again && !again.disabled) again.focus({ preventScroll: true });
      else if (S.busy) S.keep = keep;
    } else if (keep && !from) S.keep = keep;  // kept for a panel not drawn now
    fit();
  }
  // The Board panel: the row that filters, the split, the tab's line and the columns.
  function cards(el, motion) {
    const h = S.ctx.h;
    if (!el.querySelector('.board')) {
      const board = h('div', 'board');
      COLS.forEach(([k, t]) => board.append(column(k, t)));
      el.replaceChildren(h('div', 'board-view'), h('div', 'board-counts'), h('div', 'board-parents'), noteLine(), board,
        h('p', 'foot', 'Drag a card between Held and Queue, or onto a queued card to put it first. On a card, the arrow keys do the same.'));
    }
    // Each card's box and its place: its column and its index among that column's cards. A card glides only when its
    // place changed; one pushed down by the row that filters or the counts growing above it does not.
    const placeOf = (c) => { const col = c.closest('.board-col'); return col ? `${col.dataset.col}:${Array.from(col.querySelectorAll('.bcard')).indexOf(c)}` : ''; };
    const before = new Map();
    if (motion) el.querySelectorAll('.bcard').forEach((c) => before.set(c.dataset.issue, { box: c.getBoundingClientRect(), place: placeOf(c) }));
    el.querySelector('.board-view').replaceChildren(viewBar());
    el.querySelector('.board-counts').replaceChildren(split());
    el.querySelector('.board-parents').replaceWith(parents());
    const raw = unshaped(), filled = el.querySelector('.board').dataset.filled === '1';
    COLS.forEach(([k]) => {
      const col = el.querySelector(`.board-col[data-col="${k}"]`), note = col.querySelector('.warn-note');
      const got = shape(k, raw[k]);
      note.hidden = got !== null;
      note.textContent = got === null ? (S.d.issuesError || 'GitHub did not list the open issues.') : '';
      // A column shows its first PAGE cards (Landed today its first LANDED), then "Show PAGE more" and "Show all (N)";
      // its count is every card, "N of M" when the filter hides some.
      let more = null;
      if (k === 'held') {
        if (got === null) col.querySelector('.board-groups').replaceChildren(); else more = drawHeld(col, got, raw.held);
      } else {
        const list = col.querySelector('.board-cards');
        // Landed today pages by landing: the cards of one batch are one entry, so a page never cuts a batch short.
        const rows = k === 'landed' ? landings(got || []) : got || [];
        const none = () => (filtering() && raw[k] && raw[k].length ? unmatched('li', UNMATCHED[k]) : k === 'queue' ? queueEmpty(raw.held) : h('li', 'board-empty', EMPTY[k]));
        more = cx(PART).more(k, rows, (xs) => { list.replaceChildren(...(xs.length || got === null ? xs.map((x) => (Array.isArray(x) ? landing(x) : card(k, x))) : [none()])); lock(list); }, k === 'landed' ? LANDED : PAGE);
      }
      const old = col.querySelector('.show-more');
      if (old) old.remove();
      if (more) col.append(more);
      const n = (got || []).length, of = (raw[k] || []).length;
      // Landed today holds the day's newest cards (the snapshot's cut): the older ones are in Overview's Landed today,
      // which reads them from the history, and the column says how many and links there.
      const older = col.querySelector('.board-older');
      if (older) older.remove();
      const all = k === 'landed' ? num((S.d.today || {}).landed) : null;
      if (all !== null && all > of) {
        const a = h('a', 'board-older', `The ${all - of} older ${all - of === 1 ? 'card is' : 'cards are'} in Landed today`);
        a.href = S.ctx.panelHref('landed');
        a.dataset.act = 'landed-open';
        a.addEventListener('click', (e) => {
          if (e.button || e.ctrlKey || e.metaKey || e.shiftKey || e.altKey) return;  // a new tab or window opens it as a link
          e.preventDefault();
          S.ctx.goTo('landed');
        });
        col.append(a);
      }
      col.querySelector('.board-head .panel-count').textContent = n === of ? String(all !== null && all > of ? `${n} of ${all}` : n) : `${n} of ${of}`;
    });
    el.querySelector('.board').dataset.filled = '1';
    lock(el);
    el.querySelectorAll('.bcard').forEach((c) => {
      const was = before.get(c.dataset.issue);
      if (!was) { if (filled && motion) c.classList.add('enter'); return; }
      if (was.place === placeOf(c)) return;
      const a = was.box, b = c.getBoundingClientRect(), dx = a.left - b.left, dy = a.top - b.top;
      if (!dx && !dy) return;
      c.style.transition = 'none';
      c.style.transform = `translate(${dx}px, ${dy}px)`;
      void c.offsetWidth;  // the start position is laid out before the glide is set
      c.style.transition = `transform ${MOTION_MS}ms cubic-bezier(.2,.7,.2,1)`;
      c.style.transform = '';
      window.setTimeout(() => { c.style.transition = ''; }, MOTION_MS + 20);
    });
  }

  // A new snapshot is the loop as it stands: it replaces the answers sent, and the record the host answered with
  // once the collector began that snapshot at or after the answer (both times are the page host's clock).
  // One begun before it would take back the change, however late it arrives: a cap raised 3 to 4 would show 3
  // again, and the next raise would send 4. An answer that came with no time is replaced by the next snapshot.
  // Once a snapshot has replaced that answer, the answer's time stays the floor: a snapshot begun before it that
  // arrives later still would bring the old record back, so the Board keeps what it shows and redraws it.
  // The part holds every project on the host: the one the address picks is drawn. Another project picked drops
  // what was answered for the last one.
  // Every panel of the tab is drawn from the same part: the first of them to get a snapshot takes it and draws them
  // all; the others, given the same snapshot for the same project, draw only themselves.
  const render = (id) => (el, d, ctx) => {
    S.at.set(id, { el, ctx });
    // The panel acted in last (S.from), for the line that says what the action did (say): heard before the control's own handler.
    if (!S.heard.has(el)) { S.heard.add(el); ['click', 'input', 'change', 'keydown', 'drop'].forEach((t) => el.addEventListener(t, () => { S.from = id; }, true)); }
    const read = typeof ctx.updatedAt === 'function' ? ctx.updatedAt() : null;
    const view = ctx.project(d);
    // The Board shows one project: with more than one on the host the Board panel's heading names it, whatever Show says.
    if (id === PART) ctx.title(issues(view.repos).length > 1 && view.repo ? `Board: ${view.repo}` : null);
    if (S.raw && S.raw[0] === d && S.raw[1] === read && S.raw[2] === view.repo) { draw(id, true); return; }
    S.raw = [d, read, view.repo]; S.ctx = ctx; S.read = read;
    if (S.d && view.repo !== S.d.repo) { S.ctl = null; S.ctlAt = null; S.moved.clear(); S.floor = null; S.turned = false; S.unlabeled.clear(); S.groups.clear(); S.released.clear(); S.armed = false; S.dep = null; S.depSaid.clear(); S.seats = null; S.picks.clear(); }
    d = view;
    // A dependency answered shows on the card until a snapshot begun at or after the answer (with no time, the next).
    S.depSaid.forEach((v, k) => { if (v.at === null || (read !== null && read >= v.at)) S.depSaid.delete(k); });
    if (S.d && !S.ctl && S.floor !== null && read !== null && read < S.floor) { S.turned = true; draw(undefined, true); return; }
    if (S.ctl && (S.ctlAt === null || (read !== null && read >= S.ctlAt))) { if (S.ctlAt !== null) S.floor = S.ctlAt; S.ctl = null; S.ctlAt = null; S.moved.clear(); S.unlabeled.clear(); }
    S.d = d; S.turned = false;
    draw(undefined, true);
  };
  // What the parts of this file hold (parts/board-*.js; boot.js loads them before the panels): each is given what
  // it uses from here and from the parts before it, and gives back what the others use.
  const shared = { STEP, KINDS, S, DEPENDS_MAX, num, waitsOn, issues, ctl, waiting, forced, waitsOf, lanes, kinds,
    notPushed, waitsOnly, labelsOf, unlabelable, PART, elOf, relength, say, send, hold, release, shift, button, arm,
    draw };
  Object.assign(shared, window.DASH_APP.use('board-filters', shared));
  Object.assign(shared, window.DASH_APP.use('board-push', shared));
  Object.assign(shared, window.DASH_APP.use('board-cards', shared));
  const { pushTest, split, slicesOf, parents, chipsOf, rulesLink, card, landings, landing, filtering, shape, viewBar,
    EMPTY, UNMATCHED, queueEmpty, LANDED, unshaped, groupOf, groupTitle, groupRank, unmatched } = shared;

  PANELS.forEach(([id, title]) => window.DASH_APP.panel({
    id,
    title,
    size: 'full',
    tab: 'control',  // it changes the loop
    part: PART,
    rows: 'all',     // its own columns; a long Held group starts closed
    rowSelector: '.bcard',
    // The count of a paused loop is on the Rules tab, where the pause setting is.
    isEmpty: (d) => d.repo === null && !(Array.isArray(d.checkRuns) && d.checkRuns.length) && !(d.others && typeof d.others === 'object' && Object.keys(d.others).length),
    empty(el, ctx) { el.append(noLoop(ctx)); },
    error(el, message, ctx) { el.append(ctx.state('error', 'The Board could not read the Board panel', message)); },
    render: render(id),
    // A part equal to the one drawn last, in a snapshot begun at another time (app.js draws no part twice), is weighed
    // like any other when an answer is still shown or a snapshot was turned away: cap 4 answered, a cap-3
    // snapshot begun before it, then a fresh one equal to that after cap was set back to 3 elsewhere shows 3, and the
    // next raise sends 4. The same snapshot read again changes nothing.
    same(el, d, ctx) {
      const read = typeof ctx.updatedAt === 'function' ? ctx.updatedAt() : null;
      if ((S.ctl || S.turned) && read !== S.read) render(id)(el, d, ctx);
    },
    // Each second, whether or not a new snapshot came: a running check run's elapsed time and its running lanes'
    // times count on (a snapshot equal to the last one is not drawn again).
    tick(el, ctx) {
      el.querySelectorAll('.board-checkrun [data-from]').forEach((n) => {
        const text = ctx.took((Date.now() - Date.parse(n.dataset.from)) / 1000);
        if (n.textContent !== text) n.textContent = text;
      });
    },
  }));
}());
