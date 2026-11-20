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
// Judge's pick or the project's, and has Settings and Pick for me (seats(), below): a blocked card's are set before its Retry.
// The head says how the open issues split: queued, held by you, held by a label or skipped by a rule, on the belt.
// Under it, each open parent issue is one row of its parts (parents(), below).
// Its part (dashboard.sh, board): {repo (null: no record is on the host's main), state, reason (why it picks nothing | null), loop, control, cap, guard,
// modelSettings, limit, held, queue (room on the one the machine holds back: why, as "waiting for a machine slot: ..."), skipped, waits (issues waiting on another, with waitsFor), issuesError,
// building, review, waiting, blocked, landed (the day's newest; each with batch: the cards it landed with, itself among them | null;
// each card with seats: the seats the rule Pick settings gave it | null),
// today ({landed, usd}: every card of the day, counted and its usd added up, null when one has none), open ({count, split, held: each with its reasons, umbrellas: each open parent with its parts} | null),
// unpushed (the landed cards origin lacks | null), fullTest (command, why, running, last | null), and checkRuns
// (only when a pack names checks.progress: each record's {repo, error}, or its run with repo, counts, done, all and leftSec;
// with repo null too, when the Board shows those runs under "No loop to steer"), areaPrefix, repos (every project on
// the host) and others ({repo: the same part} of every other project)}. With more than one project the machine head's
// Show picks the one shown (?project=, and ?repo= the one shown last when Show is every project), and the heading names
// it ("Board: sample"); every change names it. One row filters every column by number or title,
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
    if (onlyMine(item)) { release(item, before); return; }
    const t = `#${item.issue}`;
    if (unlabelable(item)) say(`A label holds ${t} (${labelsOf(item).join(', ')}): use "Remove the label and queue it" on the card.`);
    else if (kinds(item).includes('standing')) say(`A rule of Conveyor's own skips ${t}: you cannot queue it from the Board.`);
    else if (kinds(item).includes('rule')) say(`A rule skips ${t}. To queue it, change the rule in Rules.`);
    else say(`Other holds also keep ${t} held: ${chipsOf(item).join(', ')}.`);
  }
  // The issue goes before `before` in the queue: the order sent is the queue up to it, and every issue the record
  // already put first, so nothing that was ordered loses its place.
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
    return send('order', rest.slice(0, last + 1).map((x) => String(x.issue)), null, null, (r) => send('order', was, null, r));
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
  // ---- what landed and is not pushed, and the full test suite (the part's unpushed and fullTest) ----
  // Actions, not rules: Push landed (the full test suite on main, then, green, the push of the commit it tested), Push
  // now (the push alone, below) and Run full test suite (the suite on main by itself, pushing nothing), with the run under way and the last
  // result: each failed case and what was done with it, and beside a red run Push anyway, on a second click whose words
  // name the failed cases, sent with that run's id so a later red run is not what it pushes over. A full run costs time
  // and a push cannot be undone: each acts on a second click (guarded). A button that cannot work is greyed, and says
  // why beside it.
  const fullOf = () => (S.d.fullTest && typeof S.d.fullTest === 'object' ? S.d.fullTest : null);
  const unpushed = () => (Array.isArray(S.d.unpushed) ? S.d.unpushed : null);
  const short = (sha) => (typeof sha === 'string' ? sha.slice(0, 12) : '');
  // A change that costs money or time ('spend') or cannot be undone ('final') acts on a second click within ARM_MS: the
  // first turns the button to `ask` (its consequence, for a final one). key names it apart from every other.
  function guarded(key, tier, text, ask, act, label, go) {
    const on = S.armed === key;
    const b = button(on ? ask : text, tier === 'final' ? 'btn-final' : 'btn-cost', act, on ? ask : label, () => {
      if (S.armed !== key) { arm(key); return; }
      S.armed = false;
      go();
    });
    b.dataset.guard = tier;
    b.setAttribute('aria-pressed', String(on));
    if (on) b.dataset.armed = '';
    return b;
  }
  // Why neither button can work, or null when they can: no suite in the pack, or a run under way (a second press is
  // refused on the host too).
  function fullOff() {
    const f = fullOf();
    if (!f) return 'Conveyor on the build machine is too old to run this project\'s full test suite from here';
    // The snapshot's why names the setting's file key: said in plain words instead.
    if (f.command !== true) return 'this project has no full test suite set up for Conveyor';
    if (f.running && typeof f.running === 'object') return `a full test run is under way on ${short(f.running.sha)}, and one runs at a time`;
    return null;
  }
  // A failed case of a run and what was done with it: its fix card (and why it is not a new one, when it is not), on the
  // flaky record, or declined with the reason (which says it is outside the code).
  function caseItem(x) {
    const h = S.ctx.h, li = h('li', 'board-push-case');
    li.dataset.verdict = String(x.verdict || '');
    let what = 'not judged';
    if (x.verdict === 'fix') what = `${num(x.issue) !== null ? `fix card #${x.issue}${x.reused ? ' (reused)' : ''}` : 'no fix card filed'}${x.why ? `: ${x.why}` : ''}`;
    else if (x.verdict === 'flaky') what = 'flaky: passed alone every time';
    else if (x.verdict === 'declined') what = `declined: ${x.why || 'outside the code'}`;
    li.append(h('span', 'board-push-name', String(x.case || '')), h('span', 'board-from', what));
    return li;
  }
  // The last run (or push over a red suite) and its outcome; beside a red run with landed commits to push, Push anyway.
  function lastResult(x) {
    const h = S.ctx.h, box = h('div', 'board-push-last'), cases = issues(x.cases), at = short(x.sha), p = x.pushed && typeof x.pushed === 'object' ? x.pushed : null;
    box.dataset.state = String(x.state || '');
    const pushed = p ? (p.ok ? `pushed ${at}` : `the push failed: ${p.reason || 'Conveyor recorded no reason'}`) : 'Conveyor pushed nothing';
    let head;
    if (x.kind === 'anyway') head = `${x.by || 'The owner'} pushed over a red suite: ${pushed}`;
    else if (x.state === 'passed') head = `Passed on ${at}; ${pushed}`;
    else if (x.state === 'failed') head = `Failed on ${at}: ${cases.length} ${cases.length === 1 ? 'case' : 'cases'} failed, and Conveyor pushed nothing${x.push ? '. When main is green, press Push landed again.' : ''}`;
    else head = `Did not run on ${at}: ${x.reason || 'Conveyor recorded no reason'}`;
    box.append(S.ctx.chip(x.kind === 'anyway' ? 'pushed anyway' : String(x.state || ''), x.state === 'passed' && x.kind !== 'anyway' ? 'ok' : 'warn'), h('span', 'board-push-head', head));
    // A run that reused the results of an earlier whole-suite run (a full test's, Push landed's or a release's): the
    // green run it took with no test run, or how many files it reran.
    const u = x.kind === 'run' && x.reused && typeof x.reused === 'object' && Array.isArray(x.reused.ran) && num(x.reused.kept) !== null ? x.reused : null;
    if (u) {
      const n = u.ran.length, scope = h('span', 'board-from', !n
        ? `Reused the green run of ${typeof u.time === 'string' ? S.ctx.clock(u.time) : 'an earlier time'} on ${short(u.sha)}`
        : `Reran ${n} ${n === 1 ? 'file' : 'files'}, reused ${u.kept} passed ${u.kept === 1 ? 'file' : 'files'} from ${short(u.sha)}`);
      scope.dataset.figure = 'suite-scope';
      box.append(scope);
    }
    if (cases.length) { const ul = h('ul', 'board-push-cases'); cases.forEach((c) => ul.append(caseItem(c))); box.append(ul); }
    const f = fullOf(), un = unpushed();
    if (x.kind === 'run' && x.state === 'failed' && /^[0-9a-f]{12}$/.test(String(x.id || '')) && un && un.length && f && f.command === true && !f.running) {
      // A push cannot be undone: a second click whose words say what it pushes over.
      const names = cases.map((c) => c.case).filter(Boolean);
      const ask = `Click again: push ${un.length} landed ${un.length === 1 ? 'card' : 'cards'} over a red suite, with no new run. ${names.length ? `These cases failed: ${names.join(', ')}.` : 'The run named no failed case.'}`;
      box.append(guarded(`anyway:${x.id}`, 'final', 'Push anyway', ask, 'push-anyway', 'Push what landed over this red suite, with no new run', () => send('full-test', ['anyway', x.id])));
    }
    return box;
  }
  // What runs at each stage of a push (pushing() in conveyor/lib/push.sh); a record with no stage is the hook's.
  const PUSH_STAGE = { tests: 'Tests before the push running', ready: 'Getting the push ready (worktree, dependencies, test slot)',
    hook: 'Pre-push hook running', push: 'Push running with no pre-push hook', ended: 'git push ended, finishing the push', pushed: 'Pushed, waiting for GitHub' };
  // The push (health's pushing and pushLast), so a slow push is told from a stuck one. In progress: what runs (its
  // stage, PUSH_STAGE), since when, on which commit, its process and the time it has taken, then the newest line of
  // the pre-push hook's output; stale, with its log, when its process is gone and it did not end. Else the last push
  // that ended: passed, or failed with the failed check and its log, or started no push; and main still ahead of the
  // remote after it. null: none.
  function pushState() {
    const h = S.ctx.h, r = S.d.pushing && typeof S.d.pushing === 'object' ? S.d.pushing : null, l = S.d.pushLast && typeof S.d.pushLast === 'object' ? S.d.pushLast : null;
    const str = (v) => (typeof v === 'string' ? v : ''), on = (sha) => (str(sha) ? ` on ${short(sha)}` : '');
    const box = h('div', 'board-push-state'), log = (f) => (str(f) ? [h('span', 'board-from', `Log: ${f}`)] : []);
    if (r) {
      box.dataset.state = r.stale === true ? 'stale' : 'running';
      const pid = num(r.pid) !== null ? `pid ${r.pid}` : '';
      if (r.stale === true) {
        box.append(h('span', 'board-push-bad', `The push${on(r.sha)} is stale: its process${pid ? ` (${pid})` : ''} is gone and the push did not end.`), ...log(r.log));
        return box;
      }
      const what = (typeof r.stage === 'string' && Object.prototype.hasOwnProperty.call(PUSH_STAGE, r.stage) ? PUSH_STAGE[r.stage] : '') || PUSH_STAGE.hook;
      const head = h('span', 'board-from', `${what}${on(r.sha)}${typeof r.since === 'string' ? ` since ${S.ctx.clock(r.since)}` : ''}${pid ? ` · ${pid}` : ''}`);
      if (typeof r.since === 'string') head.append(' · ', S.ctx.since(r.since, ''));
      box.append(head, ...(str(r.line) ? [h('span', 'board-push-line', r.line)] : []), ...log(r.log));
      return box;
    }
    if (!l) return null;
    const who = l.by === 'now' ? 'Push now' : l.by === 'full' ? 'Push landed' : 'The push';
    const ahead = num(l.ahead) ? [h('span', 'board-push-bad', `Main is still ${l.ahead} ${l.ahead === 1 ? 'commit' : 'commits'} ahead of the remote.`)] : [];
    box.dataset.state = l.started === false ? 'none' : l.ok === true ? 'passed' : 'failed';
    const text = l.started === false ? `${who} started no push${str(l.why) ? `: ${l.why}` : ''}.`
      : l.ok === true ? `${who}${on(l.sha)} passed.` : `${who}${on(l.sha)} failed${str(l.check) ? `: ${l.check} failed` : ''}.`;
    const head = h('span', l.ok === true && l.started !== false ? 'board-from' : 'board-push-bad', text);
    if (typeof l.time === 'string') head.append(' ', S.ctx.since(l.time, ' ago'));
    box.append(head, ...(l.ok === true ? [] : log(l.log)), ...ahead);
    return box;
  }
  // The two actions, with what they act on: the landed cards origin lacks, each by its issue, and the suite's run.
  function pushTest() {
    const h = S.ctx.h, el = h('section', 'board-push'), un = unpushed(), f = fullOf(), off = fullOff();
    el.setAttribute('aria-label', 'Push what landed, and the full test suite');
    const why = (text) => h('span', 'board-from board-push-why', `Cannot work now: ${text}.`);
    const landed = h('div', 'board-ctl');
    landed.dataset.push = 'landed';
    const cards = h('span', 'board-push-list');
    (un || []).forEach((x) => { const item = h('span', 'board-push-item', typeof x.name === 'string' && x.name ? x.name : `#${x.issue}`); item.dataset.issue = String(x.issue); item.title = String(x.card || ''); cards.append(item); });
    const push = guarded('push-landed', 'spend', 'Push landed', 'Click again to run the full suite, then push', 'push-landed','Run the full test suite on main. When it is green, Conveyor pushes what landed', () => send('full-test', ['push']));
    const nothing = un === null ? 'the Board does not know which landed cards wait for a push' : !un.length ? 'nothing that landed waits for a push' : null;
    push.disabled = !!(off || nothing);
    // Push now: what landed, pushed as Conveyor pushes a card when the push rule is on (the project's pre-push hook
    // only), with no full test run. It needs no suite in the pack, so only a run under way or nothing to push stops it.
    const nowOff = f && f.command !== true ? null : off;
    const pushNow = guarded('push-now', 'final', 'Push now', 'Click again to push now, with no full suite run', 'push-now', 'Push what landed now, through the project\'s pre-push checks only, with no full test run', () => send('push-now', []));
    pushNow.disabled = !!(nowOff || nothing);
    const whyNot = [...new Set([off, nothing, nowOff].filter(Boolean))];
    landed.append(h('span', 'board-label', 'Landed, not pushed'), h('span', 'board-value', un === null ? 'not known' : `${un.length} landed, not pushed`),
      ...(un && un.length ? [cards] : []), push, pushNow, ...whyNot.map(why));
    const ps = pushState();
    if (ps) landed.append(ps);
    const full = h('div', 'board-ctl');
    full.dataset.push = 'full-test';
    const runBtn = guarded('full-test', 'spend', 'Run full test suite', 'Click again to run the full suite', 'full-test','Run the full test suite on main; it pushes nothing', () => send('full-test', []));
    runBtn.disabled = !!off;
    const run = f && f.running && typeof f.running === 'object' ? f.running : null;
    const now = run ? h('span', 'board-from', `${run.how === 'anyway' ? 'pushing' : 'running'} on ${short(run.sha)}${run.how === 'push' ? ', to push it if green' : ''}`) : null;
    if (now && typeof run.since === 'string') now.append(' · ', S.ctx.since(run.since, ' ago'));
    full.append(h('span', 'board-label', 'Full test suite'), runBtn, ...(now ? [now] : []), ...(off ? [why(off)] : []));
    const last = f && f.last && typeof f.last === 'object' ? f.last : null;
    if (last) full.append(lastResult(last));
    el.append(landed, full);
    // Merge: the open pull request of Land as pr (health's landingPr), with its card count and link, whatever the rule
    // Merge PR says. A merge cannot be undone: it acts on a second click. GitHub's reason for a refused merge shows here.
    const pr = S.d.landingPr && typeof S.d.landingPr === 'object' && Number.isInteger(S.d.landingPr.number) ? S.d.landingPr : null;
    if (pr) {
      const box = h('div', 'board-ctl'), n = Number.isInteger(pr.cards) ? pr.cards : 0, link = h('a', 'board-push-item', `#${pr.number}`);
      box.dataset.push = 'merge';
      if (typeof pr.url === 'string' && /^https:\/\//.test(pr.url)) { link.href = pr.url; link.target = '_blank'; link.rel = 'noopener'; }
      box.append(h('span', 'board-label', 'Pull request'), link, h('span', 'board-value', `${n} ${n === 1 ? 'card' : 'cards'}`),
        guarded('merge-pr', 'final', 'Merge', `Click again to merge pull request #${pr.number} into the default branch`, 'merge-pr',
          'Merge the open pull request now, with a merge commit', () => send('merge-pr', [])));
      const m = pr.merge && typeof pr.merge === 'object' ? pr.merge : null;
      if (m && m.result === 'refused') box.append(h('span', 'board-from board-push-why', `GitHub refused the last merge: ${typeof m.reason === 'string' && m.reason ? m.reason : 'it gave no reason'}`));
      el.append(box);
    }
    return el;
  }

  // How the open issues split: they add up to the open issues (landed, not pushed only when there are any).
  function split() {
    const h = S.ctx.h, o = S.d.open, p = h('p', 'board-split');
    p.dataset.figure = 'split';
    if (!o || typeof o !== 'object' || !o.split) { p.textContent = S.d.issuesError ? '' : 'The Board does not know how the open issues split: the host did not say.'; p.hidden = !p.textContent; return p; }
    const s = o.split;
    p.append(h('span', 'board-value', `${o.count} open`), h('span', null, `${s.queued} queued`), h('span', null, `${s.you} held by you`),
      h('span', null, `${s.labelOrRule} held by a label or skipped by a rule`),
      ...(s.landed > 0 ? [h('span', null, `${s.landed} landed, not pushed`)] : []), h('span', null, `${s.belt} on the belt`));
    return p;
  }

  // The parts of each open parent (an issue with GitHub sub-issues: open.umbrellas) as one row: the parent's title,
  // its parts done of all with a bar, and its parts being built with their step. The row opens to every part with its
  // state (landed: closed, landed today, or landed and not pushed; building, with its step; blocked; waiting: any other) and a link to its
  // card on the Board. The parts' own cards stay in their columns, so a blocked part is still in Needs you.
  // raw: every column's cards (unshaped); a part's card is looked up there, in the column it is in, closed or not.
  function partState(ref, closed, raw) {
    const m = /^#(\d+)$/.exec(ref), n = m ? Number(m[1]) : null;
    const of = (k, keep = () => true) => (n === null ? null : (raw[k] || []).find((x) => x && x.issue === n && keep(x)) || null);
    const at = (col, card) => (card ? { card, col } : {});
    if (closed.includes(ref)) return { state: 'landed', ...at('landed', of('landed')) };
    let c = of('building');
    if (c) return { state: 'building', step: c.step === 'waiting' ? waitsOn(c.waitsOn) : STEP[c.step] || c.step || 'in progress', card: c, col: 'building' };
    if ((c = of('review'))) return { state: 'building', step: `review ${c.review || '?'} of ${c.of || 3}`, card: c, col: 'review' };
    if ((c = of('needs', (x) => !x.waiting))) return { state: 'blocked', card: c, col: 'needs' };
    if ((c = of('landed'))) return { state: 'landed', card: c, col: 'landed' };
    // Landed on an earlier day with push off, not pushed yet: Landed today no longer lists it, Held does.
    if ((c = of('held', notPushed))) return { state: 'landed', card: c, col: 'held' };
    // Waiting for the owner's yes (Needs you), queued, waiting on another issue (in Queue) or held: not being built.
    const col = ['needs', 'queue', 'held'].find((k) => of(k));
    const open = n === null ? null : issues(S.d.open && S.d.open.issues).find((x) => x && x.issue === n);
    return { state: 'waiting', ...at(col, col && of(col)), title: ((col && of(col)) || open || {}).title };
  }
  // A link to the part's card on the Board: it brings the card into view and gives it the focus. A card the filter or
  // its column's page hides is shown first: the filter is cleared, then the column shows all its cards.
  function cardLink(n, col) {
    const a = S.ctx.h('a', 'board-part-card', 'Show its card');
    a.href = `#board-card-${n}`;
    a.dataset.act = 'part-card';
    a.addEventListener('click', (e) => {
      e.preventDefault();
      const find = () => elOf(PART).querySelector(`.board-col[data-col="${col}"] .bcard[data-issue="${n}"]`);
      if (!find() && filtering()) clearFilters();
      if (!find()) { const all = elOf(PART).querySelector(`.board-col[data-col="${col}"] .show-more [data-act="list-all"]`); if (all) all.click(); }
      const c = find();
      if (!c) return;
      // On a phone (app.css) Held and Landed today are folded until their button opens them: open the column first.
      const fold = c.closest('.board-col:not(.open)')?.querySelector(':scope > .board-head .board-fold');
      if (fold) fold.click();
      const g = c.closest('details');
      if (g && !g.open) g.open = true;
      if (typeof c.scrollIntoView === 'function') c.scrollIntoView({ block: 'nearest' });
      if (c.tabIndex < 0) c.tabIndex = -1;
      c.focus({ preventScroll: true });
    });
    return a;
  }
  function parents() {
    const h = S.ctx.h, list = issues(S.d.open && S.d.open.umbrellas).filter((u) => u && num(u.issue) !== null);
    const box = h('div', 'board-parents'), raw = unshaped();
    box.hidden = !list.length;
    list.forEach((u) => {
      const refs = issues(u.parts).filter((r) => typeof r === 'string'), closed = issues(u.closed);
      const all = num(u.all) ?? refs.length, done = num(u.done) ?? closed.length;
      const parts = refs.map((ref) => ({ ref, ...partState(ref, closed, raw) }));
      const det = h('details', 'board-parent');
      det.dataset.issue = String(u.issue);
      det.open = S.partsOpen.has(u.issue);
      det.addEventListener('toggle', () => { if (det.open) S.partsOpen.add(u.issue); else S.partsOpen.delete(u.issue); });
      const sum = h('summary', 'board-parent-head');
      const bar = h('span', 'board-parent-bar');
      bar.setAttribute('role', 'img');
      bar.setAttribute('aria-label', `${done} of ${all} parts done`);
      const fill = h('span', 'board-parent-fill');
      fill.style.width = `${all > 0 ? Math.round((100 * Math.min(done, all)) / all) : 0}%`;
      bar.append(fill);
      sum.append(S.ctx.issueLink(u), h('span', 'board-parent-title', u.title || 'untitled'), h('span', 'board-parent-done', `${done} of ${all} done`), bar);
      const now = parts.filter((p) => p.state === 'building');
      sum.append(h('span', 'board-parent-now', now.length ? now.map((p) => `${p.ref} ${p.step}`).join(', ') : 'no part being built'));
      const ul = h('ul', 'board-parent-parts');
      ul.append(...parts.map((p) => {
        const li = h('li', 'board-part');
        li.dataset.part = p.ref; li.dataset.state = p.state;
        const title = p.card ? p.card.title : p.title;
        li.append(h('span', 'issue', p.ref));
        if (title) li.append(h('span', 'board-part-title', title));
        li.append(S.ctx.chip(p.state === 'building' ? `building: ${p.step}` : p.state, { landed: 'ok', building: 'info', blocked: 'bad', waiting: 'quiet' }[p.state]));
        if (p.card && num(p.card.issue) !== null) li.append(cardLink(p.card.issue, p.col));
        return li;
      }));
      det.append(sum, ul);
      box.append(det);
    });
    return box;
  }

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
    const mine = col === 'held' && kinds(item).includes('you');
    if (mine) acts.append(button('Queue', 'btn-quiet', 'release', `Queue ${t}: release it from your hold`, () => release(item)));
    // A card that waits on another issue is not in the pick order: it can be held, not moved. One held only by that
    // wait is in Held and can still be held by you, so it is not picked once the issue it waits on closes.
    const ordered = col === 'queue' && !waiting(item);
    const waitsOnly = col === 'held' && kinds(item).length > 0 && kinds(item).every((k) => k === 'waits');
    if (col === 'queue' || waitsOnly) acts.append(button('Hold', 'btn-quiet', 'hold', `Hold ${t}`, () => hold(item)));
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
    card.setAttribute('aria-label', `${t} ${item.title || ''}: ${col === 'held' ? `held (${chipsOf(item).join(', ')})${mine ? '; the right arrow queues it' : waitsOnly ? '; the left arrow holds it' : ''}` : ordered ? 'queued; the up and down arrows move it, the left arrow holds it' : 'waits for another issue; the left arrow holds it'}`);
    card.addEventListener('keydown', (e) => {
      const fn = col === 'held' ? (mine ? { ArrowRight: () => release(item) }[e.key] : waitsOnly ? { ArrowLeft: () => hold(item) }[e.key] : null)
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
  // why it does not move: "Waiting on #12 (held)".
  function waitingChip(ns, url, on) {
    const c = S.ctx.chip('Waiting on ', 'quiet'), words = c.lastChild;
    const state = (n) => { const w = issues(on).find((x) => x && x.issue === n); return w && typeof w.state === 'string' && w.state ? ` (${w.state})` : ''; };
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
    const str = (v) => typeof v === 'string' && v ? v : null;
    const named = (x) => `${S.ctx.modelName(x.model)}${str(x.effort) ? ` · ${x.effort}` : ''}`;
    const list = h('div', 'board-seats-line');
    const callout = (by, label, lines) => {
      const box = h('div', 'why-block board-seat-why');
      box.dataset.by = by;
      box.append(h('strong', 'why-label', label));
      lines.forEach((t) => box.append(h('span', 'why-line', t)));
      return box;
    };
    SEATS.forEach(([k, name]) => {
      const p = here ? projSeat(k) : null, o = own[k] && typeof own[k].model === 'string' ? own[k] : null;
      // On a card of the project shown, the owner's seat is the control record's as it is now (own), not the pick's
      // record of it: a seat the owner cleared since runs on the project's.
      const q = !o && run[k] && typeof run[k].model === 'string' && SEATBY[run[k].by] && !(here && run[k].by === 'card') ? run[k] : null;
      const x = o ? { model: o.model, effort: o.effort || ownEffort(k, o.model, p && p.effort) }
        : q ? { model: q.model, effort: str(q.effort) } : p && p.model ? p : null;
      const by = o ? 'card' : q ? q.by : null;
      const row = h('div', o ? 'board-seat is-own' : 'board-seat');
      row.dataset.seat = k;
      const line = h('p', 'board-seat-line');
      line.append(h('span', 'board-seat-name', name),
        h('span', 'board-seat-model', x ? named(x) : here ? 'not set' : ''),
        h('span', 'board-seat-by', by ? SEATBY[by] : "project's"));
      row.append(line);
      // The Judge's answer for the seat (a clamp with no model: the pack allowed it none, so the project's stands);
      // the card does not run on it only when it is another model or effort than the row's.
      const a = s && s[k] && typeof s[k] === 'object' ? s[k] : null, am = a && str(a.model) ? a : null;
      const other = am && by !== 'judge' && !(x && x.model === am.model && str(x.effort) === str(am.effort));
      const why = a ? [].concat(other ? [`The Judge chose ${named(am)}; the card does not run on it${s.mode === 'shadow' ? ', as the rule Pick settings is in Shadow' : ''}.`] : [],
        str(a.why) ? [a.why] : am ? ['no reason given'] : [], str(a.clamp) ? [`Clamped: ${a.clamp}`] : []) : [];
      if (why.length) row.append(callout('judge', 'Why the Judge chose it', why));
      list.append(row);
    });
    const back = s && typeof s === 'object' ? (typeof s.failed === 'string' ? `The Judge's pick failed: ${s.failed}` : typeof s.guard === 'string' ? s.guard : null) : null;
    if (back) list.append(callout('code', "Why the card runs on the project's seats", [back]));
    return list;
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
    SEATS.forEach(([k, name]) => {
      const p = projSeat(k), row = h('div', 'board-seat-row');
      row.dataset.seat = k;
      const m = h('select', null), e = h('select', null), eff = h('label', 'board-seat-effort'), same = h('span', 'board-seat-same', 'the project\'s effort');
      m.dataset.act = `seat-model-${k}`; e.dataset.act = `seat-effort-${k}`;
      m.setAttribute('aria-label', `${name} model of #${n}`); e.setAttribute('aria-label', `${name} effort of #${n}`);
      const opt = (v, text) => { const o = h('option', null, text); o.value = v; return o; };
      m.append(opt('', `Project's: ${p && p.model ? seatText(p) : 'not set'}`), ...issues(p && p.choices).map((c) => opt(c, S.ctx.modelName(c))));
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
      try { x = JSON.parse(said); } catch (e) { x = null; }
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
    if (col === 'held' || col === 'queue') {
      const tags = h('div', 'board-tags');
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
      if (tags.firstChild) el.append(tags);
      if (num(item.next) !== null) el.append(h('p', 'board-from', item.next === 1 ? 'Next in the queue' : `#${item.next} in the queue`));
      // A split issue (the rule Split large issues On) is held as the umbrella of its slices until each one lands or is already done on main.
      const um = issues(item.umbrella).filter((x) => num(x) !== null);
      if (um.length) el.append(h('p', 'board-from board-umbrella', `Umbrella of ${um.map((x) => `#${x}`).join(', ')}: not built itself, and closed when they land or are already done on main`));
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
    } else if (col === 'building' || col === 'review') {
      const meta = h('p', 'row-meta');
      // A card that let another land first reads "Waiting behind #N"; what it does meanwhile is on hover and tap.
      const behind = num(item.gaveWay) !== null ? ctx.tip(h('span', null, `Waiting behind #${item.gaveWay}`),
        `It let #${item.gaveWay} land first. While it waits, it ${item.gaveWayFixing ? 'fixes its failed tests' : 'fits its change onto main'}.`) : null;
      // A running test run says how far it has got ("testing, 4 of 6 test files": ctx.testProgress).
      const prog = col === 'building' && item.step === 'tests' ? ctx.testProgress({ files: item.files, tests: item.tests }) : null;
      meta.append(behind || h('span', null, col === 'review' ? `review ${item.review || '?'} of ${item.of || 3}`
        : (item.step === 'waiting' ? waitsOn(item.waitsOn) : (STEP[item.step] || item.step || 'in progress')) + (prog ? `, ${prog}` : '')), ctx.since(item.stepAt, ''),
        h('span', null, item.reading === false ? (item.atEnd === true ? 'cost shown when the step ends' : 'no reading yet') : ctx.money(item.usd)));
      el.append(meta);
      // A main-red fix the loop started with the cap reached takes one slot beyond it: the Board says so.
      if (typeof item.beyond === 'string' && item.beyond) el.append(ctx.chip(`beyond the cap: ${item.beyond}`, 'warn'));
      // A card landed on an earlier day whose push failed stays here, with why.
      if (typeof item.reason === 'string' && item.reason) el.append(ctx.chip(`Push failed: ${item.reason}`, 'bad'));
    } else if (col === 'needs') {
      el.classList.add(item.waiting ? 'is-waiting' : 'is-blocked');
      el.append(ctx.chip(item.waiting ? 'Waiting for your yes' : 'Blocked', item.waiting ? 'warn' : 'bad'));
      needs(el, item, item.waiting);
    } else {
      const r = num(item.reviews);
      el.append(h('p', 'row-meta', item.step === 'closed' ? (splitFiled(item).length ? 'split, not built' : 'already fixed') : `${r === null ? '?' : r} review${r === 1 ? '' : 's'} · ${ctx.money(item.usd)}`));
    }
    if (col !== 'held' && col !== 'queue') { doneWhen(el, item); stalls(el, item); splitNote(el, item); }
    // A landed card has no step left to run; a main-red fix card has no issue to keep settings by. A card in Needs you
    // has them too, so a blocked card's are set before its Retry; it is still answered in the Needs you panel (issue
    // 407): its settings are no answer. A card of another project is not set from here: its seats are in that project's record.
    const mine = typeof item.repo !== 'string' || !item.repo || item.repo === S.d.repo;
    if (col !== 'landed' && mine && num(item.issue) !== null && item.issue > 0) seats(el, item);
    else if (col !== 'held' && col !== 'queue') seatsNote(el, item, mine);
    return el;
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
  function groupOf(x) {
    const r = issues(x.reasons)[0] || { kind: 'other' };
    return r.kind === 'label' ? `label:${r.label}` : r.kind === 'standing' || r.kind === 'other' ? 'rule' : r.kind;
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
  // Draws the tab's panels (only: the one panel with that id), each in the place the page gave it (S.at).
  function draw(only) {
    const h = S.ctx.h, motion = S.ctx.motion(), at = (id) => (!only || only === id ? elOf(id) : null);
    const top = at(LOOP), pushes = at(PUSH), el = at(PART);
    // No record steered, and another record's check run to show: the empty Board, then the runs (in Push landed and
    // full test suite); another project on the host is picked in the machine head.
    if (S.d.repo === null) {
      [top, pushes, el].forEach((x) => { if (x) x.replaceChildren(noLoop(S.ctx, issues(S.d.repos).length > 1)); });
      if (pushes) { const check = h('div', 'board-check'); check.append(...checkTiles()); pushes.append(check); }
      relength();
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
    relength();
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
    if (S.raw && S.raw[0] === d && S.raw[1] === read && S.raw[2] === view.repo) { draw(id); return; }
    S.raw = [d, read, view.repo]; S.ctx = ctx; S.read = read;
    if (S.d && view.repo !== S.d.repo) { S.ctl = null; S.ctlAt = null; S.moved.clear(); S.floor = null; S.turned = false; S.unlabeled.clear(); S.groups.clear(); S.released.clear(); S.armed = false; S.dep = null; S.depSaid.clear(); S.seats = null; S.picks.clear(); }
    d = view;
    // A dependency answered shows on the card until a snapshot begun at or after the answer (with no time, the next).
    S.depSaid.forEach((v, k) => { if (v.at === null || (read !== null && read >= v.at)) S.depSaid.delete(k); });
    if (S.d && !S.ctl && S.floor !== null && read !== null && read < S.floor) { S.turned = true; draw(); return; }
    if (S.ctl && (S.ctlAt === null || (read !== null && read >= S.ctlAt))) { if (S.ctlAt !== null) S.floor = S.ctlAt; S.ctl = null; S.ctlAt = null; S.moved.clear(); S.unlabeled.clear(); }
    S.d = d; S.turned = false;
    draw();
  };

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
