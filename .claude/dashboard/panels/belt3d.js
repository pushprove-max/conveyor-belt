// SPDX-License-Identifier: Apache-2.0
// Belt 3D: the factory floor. One belt lane a card on the belt, with six pads (Build, Review, Fix, Test, Land, Push),
// each the colour of what happened at that step, and the card's crate on the step it is in; the card's number and title
// at the left of its lane, its live status at the right ("Test 142/205" and a bar from its track's tests, else its
// files, else the time in its step). Below them a red lane a stuck card (Needs you: blocked, or waiting for the owner's
// yes), with its reason. Four bays along the bottom: queued, waiting on another card (and on which), held, and just
// landed. A header strip counts every state and each step; a card's tooltip on hover has its full title, and a click
// opens its details beside the floor (below it on a phone): its six steps and their times, its test bar, its review rounds, why it is stuck,
// what it waits on and its cost. A button in the panel's header shows the panel full screen, or where the browser has
// no full screen (Safari on iPhone) or refuses it, makes the panel fill the browser window; there the header is set
// aside and the button, to leave, is at the header strip's right end (in the header, shown, while there is no strip).
// A running card that went back a step (issue 423: from its track's records) is amber, the Board's warn colour: the
// belt between the two steps (the scene's), "← back to <step>" over it, its crate's round badge past the first round,
// and a second line under its status, "← went back from <step> at <time> ET"; all of it goes once it moves on past
// the step it went back from.
// On a phone (up to 700px wide, out of full screen) the floor is not drawn: the panel is a plain list of the same lanes,
// each card with the step it is in and its minutes there (issue 414).
// Behind the floor, a holographic control deck (the owner's mockup, issue 393): a rolling grid and rings
// (app.css .b3-deck, under the floor), and in the corners readouts of the snapshot's own values: the host, the slots
// in use of those in force (the head's figure), the time in ET and the machine's loop state (.b3-hud).
// Its part: {repos, belt, queue: {next, held, waiting} | null, needs, landed, byRepo, deck: {host, state, used, cap}}
// (dashboard.sh), the snapshot's cards and nothing else. Nothing is simulated or estimated.
// Every word is this file's own HTML, made once and written in place, each at a fixed size, so a refresh moves nothing;
// the stage's height follows the number of lanes, or the window's room below it where that is taller (room()), and
// changes only when one of them does. The floor (belt3d-scene.js, three.js
// from vendor/three/) places these words over it; it is imported only once the panel is shown and draws only while the
// panel is in view and the page is, and something on the floor moves. With motion off nothing glides and the belts
// stand still. With no WebGL the panel says so in one line, under its header strip. window.DASH_BELT3D_SCENE stands in for the scene's module in the view test.
(function () {
  'use strict';
  const NAMES = ['Build', 'Review', 'Fix', 'Test', 'Land', 'Push'];
  const STATES = ['done', 'now', 'skipped', 'failed', 'todo'];
  // The step of a belt card's `step`, when its track does not say.
  const AT = { brief: 0, build: 0, review: 1, fix: 2, tests: 3, waiting: 4, landing: 4, push: 5, issue: 5 };
  const KIND = { run: 'Running', blocked: 'Stuck', waiting: 'Waiting on a card', held: 'Held', queued: 'Queued', landed: 'Landed' };
  const HEAD = { run: 'Running', blocked: 'Stuck', waiting: 'Waiting', held: 'Held', queued: 'Queued', landed: 'Landed' };
  const BAYS = [['queued', 'Queued'], ['waiting', 'Waiting on a card'], ['held', 'Held'], ['landed', 'Just landed']];
  const MARK = { done: '✓', now: '▶', skipped: '–', failed: '✕', todo: '' };
  const SIGN = { done: '✓', skipped: '–', failed: '✕' };
  const ORD = ['next up', '2nd in line', '3rd in line'];
  const SHOWN = 3;  // cards a bay shows
  const num = (v) => typeof v === 'number' && Number.isFinite(v);
  // What a card waits on: #N of its project (a number), or "owner/repo#N" of another repository (a string), as said.
  const dep = (v) => num(v) || (typeof v === 'string' && /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+#\d+$/.test(v));
  const ref = (n) => (typeof n === 'string' ? n : `#${n}`);
  const arr = (v) => (Array.isArray(v) ? v.filter((x) => x && typeof x === 'object') : []);
  const str = (v) => (typeof v === 'string' ? v : '');

  // One panel on the page: its elements and its scene live from one refresh to the next.
  const view = { root: null, stage: null, labels: null, sum: null, list: null, listSig: '', counts: {}, steps: [], tip: null, detail: null, close: null, detailSig: '', note: null, heads: [], bayHeads: [],
    rows: [], tags: new Map(), badges: new Map(), order: new Map(), seq: 0, cards: [], byKey: new Map(), byIssue: new Map(), unread: new Set(), multi: false, lanes: -1, hover: null, pin: null,
    ctx: null, scene: null, loading: false, failed: false, raf: null, last: 0, still: false, seenAt: 0, resized: false, inView: true, filled: null, deck: null, ro: null };

  // ---- the cards: one flat list, each with its kind (run, blocked, queued, waiting, held, landed) ----
  // A card is known by its project and card id: two cards of one issue (a branch's cards are all issue 0, and an issue
  // landed today can have a new card) are two cards. An issue in the queue has no card yet and is known by its project
  // and issue; a card's `from` is that key, so a queued issue that is picked up glides from its bay to its lane.
  const keyOf = (c) => (c.card ? `${c.repo}:${c.card}` : `${c.repo}#${c.issue}`);
  function sixOf(track, at, kind) {
    const t = track && Array.isArray(track.steps) && track.steps.length === 6 ? track.steps : null;
    if (t && t.every((s, i) => s && s.name === NAMES[i] && STATES.includes(s.state))) return t.map((s) => ({ name: s.name, state: s.state, sec: num(s.sec) ? s.sec : null, n: num(s.n) ? s.n : null, replyFix: str(s.replyFix), lintFix: str(s.lintFix) }));
    return NAMES.map((name, i) => ({ name, state: i < at ? 'done' : i === at ? (kind === 'blocked' ? 'failed' : kind === 'run' ? 'now' : 'todo') : 'todo', sec: null, n: null }));
  }
  const counted = (o, a, b) => (o && num(o[a]) && num(o[b]) && o[b] > 0 ? o : null);
  // Where each recorded step is drawn among the six (the track's records, conveyor/jq/track.jq): the set-up and the
  // build, a review, a fix, a test run, the landing (its rebuild and follow-ups), the push and the close of the issue.
  const POS = [[/^(queued|picked|worktree|dependencies|brief|building)\b/, 0], [/^review\b/, 1], [/^fix\b/, 2], [/^tests\b/, 3], [/^(landing|rebuild|follow-ups)\b/, 4], [/^(push|pushed|issue)\b/, 5]];
  // A running card's steps as recorded, each step ended with its time, then the step it is in now. A fix the Done-when
  // check on a reply started (replyCheck) is drawn where the session it checks is (the build's on Build), so the
  // review after it is no step back from Fix.
  function trail(t, at) {
    const seq = arr(t && t.records).filter((r) => typeof r.at === 'string')
      .map((r) => { const p = POS.find(([re]) => re.test(str(r.name))); return { pos: p ? p[1] : null, time: Date.parse(r.at), reply: r.replyCheck === true }; }).filter((r) => r.pos !== null)
      .map((r, i, a) => (r.reply && i > 0 ? { pos: a[i - 1].pos, time: r.time } : { pos: r.pos, time: r.time }));
    return seq.concat({ pos: at, time: NaN });
  }
  // Issue 423: the last time the card went from a step back to one before it (a NO-GO review's fix and the review
  // again, failed tests and their fix, a landing that met a conflict and the review after its rebuild): from, to and
  // when the step it left ended. It holds until the card moves on past the step it went back from: back at that step
  // (Review 2's NO-GO and Fix 2) it still holds.
  function backOf(seq, at) {
    for (let j = seq.length - 1; j > 0; j -= 1) if (seq[j].pos < seq[j - 1].pos) return at <= seq[j - 1].pos ? { from: seq[j - 1].pos, to: seq[j].pos, time: seq[j - 1].time } : null;
    return null;
  }
  // The round of the step it is in: a review's or fix's count (as "Review 2" says), else how many times it came to it.
  function roundOf(seq, at, steps) {
    if ((at === 1 || at === 2) && num(steps[at].n)) return steps[at].n;
    return seq.filter((s, i) => s.pos === at && (i === 0 || seq[i - 1].pos !== at)).length;
  }
  function model(d) {
    const cards = [], seen = new Set();
    const add = (c) => { const k = keyOf(c); if (seen.has(k)) return; seen.add(k); cards.push(Object.assign(c, { key: k, from: c.card && num(c.issue) && c.issue > 0 ? `${c.repo}#${c.issue}` : null })); };
    const landed = arr(d.landed), landedKeys = new Set(landed.map((c) => `${c.repo}:${c.card}`));
    const reviews = (v) => arr(v).map((r, i) => ({ round: num(r.round) ? r.round : i + 1, verdict: str(r.verdict), counts: r.counts && typeof r.counts === 'object' ? r.counts : null }));
    const base = (x, kind) => ({ repo: str(x.repo), card: str(x.card), issue: x.issue, name: str(x.name), title: str(x.title), url: x.url, kind, reviews: reviews(x.reviews), usd: num(x.usd) ? x.usd : null, estimate: x.estimate === true });
    arr(d.belt).forEach((x) => {
      // A card landed today is in the Just-landed bay; one landed on an earlier day, its push or the close of its issue
      // still to go through, keeps its lane.
      if (x.landed === true && landedKeys.has(`${x.repo}:${x.card}`)) return;
      const t = x.track && typeof x.track === 'object' ? x.track : null;
      const at = t && num(t.at) && t.at >= 0 && t.at < 6 ? t.at : Object.hasOwn(AT, x.step) ? AT[x.step] : x.landed === true ? 5 : 0;
      // The card it waits on by its issue, or a main-red fix card (issue 0) by its name (a string, said as it is).
      const w = x.waitsOn && typeof x.waitsOn === 'object' && num(x.waitsOn.issue) ? str(x.waitsOn.name) || x.waitsOn.issue : null;
      const steps = sixOf(t, at, 'run'), seq = trail(t, at);
      add(Object.assign(base(x, 'run'), { at, steps, since: Date.parse((t && t.since) || x.stepAt), tests: counted(t && t.tests, 'done', 'of'), files: counted(t && t.files, 'run', 'of'),
        waitsOn: x.step === 'waiting' ? w : null, turns: num(x.turns) ? x.turns : null, back: backOf(seq, at), round: roundOf(seq, at, steps) }));
    });
    arr(d.needs).forEach((x) => {
      const t = x.track && typeof x.track === 'object' ? x.track : null, six = t && Array.isArray(t.steps) ? t.steps : [];
      const failed = six.map((s) => s && s.state).lastIndexOf('failed'), ran = six.map((s) => s && s.state).filter((s) => s && s !== 'todo').length;
      const at = failed >= 0 ? failed : t && num(t.at) && t.at >= 0 && t.at < 6 ? t.at : Math.min(5, Math.max(0, ran - 1));
      // A card waiting for the owner's yes failed no step: with no track, none is drawn failed.
      add(Object.assign(base(x, 'blocked'), { at, steps: sixOf(t, at, x.kind === 'waiting' ? 'held' : 'blocked'), since: Date.parse(x.since), tests: counted(t && t.tests, 'done', 'of'), files: null,
        reason: str(x.reason) || 'no reason given', yes: x.kind === 'waiting' }));
    });
    const q = d.queue && typeof d.queue === 'object' ? d.queue : {};
    // A queue list that was not read (its issues were not listed) is unknown: its count is a dash, never 0.
    view.unread = new Set([['queued', q.next], ['waiting', q.waiting], ['held', q.held]].filter((x) => !Array.isArray(x[1])).map((x) => x[0]));
    arr(q.next).forEach((x) => add(Object.assign(base(x, 'queued'), { at: -1, steps: sixOf(null, -1, 'queued'), since: NaN })));
    arr(q.waiting).forEach((x) => add(Object.assign(base(x, 'waiting'), { at: -1, steps: sixOf(null, -1, 'waiting'), since: NaN, waitsFor: (Array.isArray(x.waitsFor) ? x.waitsFor : []).filter(dep) })));
    // A held issue stays in Held whatever it depends on; what it waits on is said on it there.
    arr(q.held).forEach((x) => add(Object.assign(base(x, 'held'), { at: -1, steps: sixOf(null, -1, 'held'), since: NaN, waitsFor: (Array.isArray(x.waitsFor) ? x.waitsFor : []).filter(dep) })));
    // A landed card's six steps are its track's, with their times: a step it skipped is skipped, a push still to go is todo.
    landed.forEach((x) => add(Object.assign(base(x, 'landed'), { at: 6, steps: sixOf(x.track && typeof x.track === 'object' ? x.track : null, 6, 'landed'), since: Date.parse(x.time) })));
    return cards;
  }
  const of = (kind) => view.cards.filter((c) => c.kind === kind);
  const tally = (kind) => (view.unread.has(kind) ? '—' : String(of(kind).length));

  // ---- what a card says ----
  const mins = (c) => Math.max(0, Math.floor((Date.now() - c.since) / 60000));
  const time = (c) => (Number.isNaN(c.since) ? '' : view.ctx.took(Math.max(0, (Date.now() - c.since) / 1000)));
  function stepName(c) {
    const s = c.steps[c.at];
    // The review gate's lint fix is on the step it checks, Build, Fix or Land; the landing gate's a Fix round (track.jq lintFix).
    return c.at === 0 && s && s.replyFix === 'now' ? 'Build · reply check fix' : c.at === 0 && s && s.lintFix === 'now' ? 'Build · lint fix'
      : c.at === 2 && s && s.lintFix === 'now' ? `Fix ${num(s.n) && s.n > 1 ? s.n : 1}: lint findings` : c.at === 4 && s && s.lintFix === 'now' ? 'Land · lint fix' : c.at === 1 && s && num(s.n) && s.n >= 1 ? `Review ${s.n}` : c.at === 2 && s && num(s.n) && s.n > 1 ? `Fix ${s.n}` : NAMES[c.at];
  }
  // A running card's test run, as far as it has got: the file that runs now, which of how many, and its time on it
  // (#433: the cases of the files that ended are no total, so they are not shown); else its cases, else its files.
  function progress(c) {
    if (c.kind !== 'run' || c.at !== 3) return null;
    const f = c.files, on = f && f.now && typeof f.now === 'object' && str(f.now.file) ? f.now : null;
    if (on) {
      const at = Date.parse(on.at), failed = c.tests && num(c.tests.failed) ? c.tests.failed : 0;
      const t = Number.isNaN(at) ? '' : `, ${view.ctx.took(Math.max(0, (Date.now() - at) / 1000))}`;
      // The lane has room for the file's name; the tooltip and the details have its whole path (`whole`).
      const line = (file) => `file ${Math.min(f.run + 1, f.of)} of ${f.of}: ${file}${t}${failed ? `, ${failed} failed` : ''}`;
      return { text: line(on.file.split('/').pop() || on.file), whole: line(on.file), share: f.run / f.of, failed: failed > 0 };
    }
    if (c.tests) return { text: `Test ${c.tests.done}/${c.tests.of}${num(c.tests.failed) && c.tests.failed ? `, ${c.tests.failed} failed` : ''}`, share: c.tests.done / c.tests.of, failed: num(c.tests.failed) && c.tests.failed > 0 };
    if (c.files) return { text: `Test files ${c.files.run}/${c.files.of}`, share: c.files.run / c.files.of, failed: false };
    return null;
  }
  // A Test step on its second run or later: which run, and the time of all its runs (the earlier ones' seconds, the
  // step's sec, and this one's), apart from this run's time: " · 3rd run, 2 h 06 min in all". '' else.
  const nth = (n) => `${n}${[11, 12, 13].includes(n % 100) ? 'th' : ['th', 'st', 'nd', 'rd'][n % 10] || 'th'}`;
  const runs = (c, s) => (c.kind === 'run' && s.name === 'Test' && num(s.n) && s.n > 1 && !Number.isNaN(c.since)
    ? ` · ${nth(s.n)} run, ${view.ctx.took((num(s.sec) ? s.sec : 0) + Math.max(0, (Date.now() - c.since) / 1000))} in all` : '');
  // `short`: a test file's name only, as the lane has it; else its whole path, as the tooltip and the details have it.
  function status(c, short) {
    if (c.kind === 'run') {
      const p = progress(c);
      if (p) return short || !p.whole ? p.text : p.whole;
      if (c.waitsOn !== null && c.waitsOn !== undefined) return `Waits on ${ref(c.waitsOn)} to land`;
      return `${stepName(c)}${time(c) ? ` · ${time(c)}` : ''}`;
    }
    if (c.kind === 'blocked') return c.yes ? 'Waiting for your yes' : `Stuck at ${NAMES[c.at]}`;
    if (c.kind === 'held') return c.waitsFor.length ? `Held · waits on ${c.waitsFor.map(ref).join(', ')}` : 'Held';
    if (c.kind === 'waiting') return c.waitsFor.length ? `Waits on ${c.waitsFor.map(ref).join(', ')}` : 'Waits on a card';
    if (c.kind === 'queued') return 'Queued';
    if (Number.isNaN(c.since)) return 'Landed today';
    return mins(c) < 1 ? 'Landed just now' : `Landed ${time(c)} ago`;
  }
  const say = (c) => (c.kind === 'run' ? 'Running: ' : '') + status(c);
  // A running card that went back: the way it went (from, to), else null; its status's amber second line; its round,
  // past the first, else null.
  const backWay = (c) => (c.kind === 'run' && c.back ? c.back : null);
  // A time in New York, as the deck's ET clock, in the Board's Time (Customize).
  const ET = (ms, seconds) => view.ctx.stamp(ms, { seconds, zone: 'America/New_York' });
  const backLine = (b) => (b ? `← went back from ${NAMES[b.from]}${Number.isNaN(b.time) ? '' : ` at ${ET(b.time)} ET`}` : '');
  const roundShown = (c) => (c.kind === 'run' && num(c.round) && c.round > 1 ? c.round : null);
  // A card's number, or a main-red fix card's name (it has no issue): "Main is red (<commit>)".
  const no = (c) => c.name || `#${c.issue}`;
  const named = (c) => (view.multi ? `${c.repo} ${no(c)}` : no(c));
  // What a card waits on: the first card of that issue (on the belt, stuck, queued, then landed).
  const find = (c, n) => view.byIssue.get(`${c.repo}#${n}`) || null;
  const where = (d) => (d.kind === 'run' ? `now in ${NAMES[d.at]}` : KIND[d.kind].toLowerCase());
  function bayLine(c, i) {
    if (c.kind === 'queued') return ORD[i] || 'in line';
    if (c.kind === 'waiting') return c.waitsFor.length ? c.waitsFor.map((n) => { const d = find(c, n); return `waits on ${ref(n)}${d ? `, ${where(d)}` : ''}`; }).join('; ') : 'waits on a card';
    if (c.kind === 'held') return c.waitsFor.length ? `held on the Board, ${c.waitsFor.map((n) => `waits on ${ref(n)}`).join('; ')}` : 'held on the Board';
    return status(c);
  }

  // ---- writes that touch the page only when something changed ----
  const txt = (el, t) => { if (el.textContent !== t) el.textContent = t; };
  const cls = (el, name) => { if (el.className !== name) el.className = name; };
  const attr = (el, k, v) => { if (el.getAttribute(k) !== v) el.setAttribute(k, v); };
  // A bar filled to a share (0 to 1), by its transform, so its fill glides without laying the page out again.
  const fill = (el, share) => { const v = `scaleX(${Math.round(Math.min(1, Math.max(0, share)) * 1000) / 1000})`; if (el.style.transform !== v) el.style.transform = v; };

  // ---- the lanes: one a running card, then one a stuck card; a card keeps its place among them ----
  function rowEls(h) {
    const name = h('div', 'b3-lb b3-nm'), now = h('div', 'b3-lb b3-st'), l1 = h('div', 'b3-l1'), ret = h('div', 'b3-ret'), bar = h('div', 'b3-pbar'), why = h('div', 'b3-why');
    name.append(h('b'), h('span'));
    l1.append(h('i', 'b3-dot'), h('span'));
    bar.append(h('i'));
    now.append(l1, ret, bar, why);
    const marks = NAMES.map(() => h('div', 'b3-lb b3-mk'));
    // "← back to Review", over the stretch of belt a card went back along.
    const back = h('div', 'b3-lb b3-bk off');
    view.labels.append(name, now, ...marks, back);
    return { name, now, marks, back, text: l1.lastChild, ret, bar: bar.firstChild, why };
  }
  function lanes() {
    // A card new to the floor comes after those already there, in the snapshot's order.
    view.cards.forEach((c) => { if (!view.order.has(c.key)) view.order.set(c.key, view.seq += 1); });
    const rank = (c) => view.order.get(c.key);
    const run = of('run').sort((a, b) => rank(a) - rank(b)), stuck = of('blocked').sort((a, b) => rank(a) - rank(b));
    const live = new Set(view.cards.map((c) => c.key));
    view.order.forEach((_, k) => { if (!live.has(k)) view.order.delete(k); });
    return run.concat(stuck);
  }
  // In the page, the stage is never shorter than the window's room below its top (issue 449, app.css --b3-room): its
  // depth's height follows its width, so a window taller for its width than a desktop's (an iPad's) was left empty below
  // the floor with fewer than 4 lanes. The room is the window's height less the page above the stage, the panel below
  // the floor, and the grid's bottom padding, gap and one of its rows (app.js rounds a panel up to whole rows), so the
  // page never scrolls for it. Measured at each draw, and at the floor's next frame after a resize of the window, so the
  // page above settling after the first draw is followed at the next refresh, and a turn of the tablet or a resized
  // window at once. Full screen or filling the window the
  // stage fills the panel anyway, and the room is left as it was, to be measured again in the page.
  function room() {
    const s = view.stage, panel = view.root && view.root.closest('.panel'), grid = panel && panel.parentElement;
    if (!grid || !s.getClientRects().length || document.fullscreenElement === panel || view.filled === panel) return;
    const cs = window.getComputedStyle(grid), n = (v) => parseFloat(v) || 0;
    // The panel below the floor, part by part: not its bottom less the floor's, which takes in the few pixels app.js
    // grows it by to whole rows, themselves from the room, and so would change the room again at each frame.
    let under = n(window.getComputedStyle(view.root.parentElement).paddingBottom) + n(window.getComputedStyle(panel).borderBottomWidth);
    for (let e = view.root.parentElement.nextElementSibling; e; e = e.nextElementSibling) under += e.offsetHeight;
    const top = s.getBoundingClientRect().top + window.scrollY;
    const v =`${Math.max(0, Math.floor(document.documentElement.clientHeight - top - under - n(cs.paddingBottom) - n(cs.columnGap) - n(cs.gridAutoRows)))}px`;
    if (s.style.getPropertyValue('--b3-room') !== v) s.style.setProperty('--b3-room', v);
  }
  function drawRows(list) {
    const h = view.ctx.h;
    while (view.rows.length < list.length) view.rows.push(rowEls(h));
    while (view.rows.length > list.length) { const r = view.rows.pop(); [r.name, r.now, ...r.marks, r.back].forEach((el) => el.remove()); }
    // The stage is as deep as the floor (2.6 of its lengths a lane and 12.4 for the heads and the bays, belt3d-scene.js), set
    // only when the number of lanes changes.
    if (view.lanes !== list.length) { view.lanes = list.length; view.stage.style.setProperty('--b3-depth', String(2.6 * list.length + 12.4)); }
    room();
    list.forEach((c, i) => {
      const r = view.rows[i], stuck = c.kind === 'blocked', hot = c.key === view.hover || c.key === view.pin;
      cls(r.name, `b3-lb b3-nm${stuck ? ' bad' : ''}${hot ? ' hot' : ''}`);
      attr(r.name, 'data-issue', String(c.issue));
      txt(r.name.firstChild, no(c));
      txt(r.name.lastChild, c.title || 'untitled');
      const p = progress(c);
      cls(r.now, `b3-lb b3-st${stuck ? ' bad' : ''}${p ? ' tests' : ''}${p && p.failed ? ' fail' : ''}`);
      txt(r.text, status(c, true));
      if (p) fill(r.bar, p.share);
      txt(r.why, stuck ? c.reason : '');
      const b = backWay(c);
      txt(r.ret, backLine(b));
      cls(r.back, `b3-lb b3-bk${b ? '' : ' off'}`);
      txt(r.back, b ? `← back to ${NAMES[b.to]}` : '');
      c.steps.forEach((s, k) => { cls(r.marks[k], `b3-lb b3-mk ${s.state}`); txt(r.marks[k], SIGN[s.state] || ''); });
    });
  }
  // ---- on a phone, the lanes as a plain list: each card, the step it is in, and its time there (since it stopped,
  // for a stuck card) ----
  // Issue 414 (UX28): at a phone's width the floor shrank to a thumbnail whose words were specks. app.css shows this
  // list in its place up to 700px; wider, the floor shows and the list does not.
  const phone = () => typeof window.matchMedia === 'function' && window.matchMedia('(max-width: 700px)').matches;
  // Whole minutes, so the list changes once a minute; an hour or more as hours and minutes.
  const minutes = (m) => (m < 60 ? `${m} min` : `${Math.floor(m / 60)} h ${String(m % 60).padStart(2, '0')} min`);
  function drawList(list) {
    const h = view.ctx.h;
    // A card in its test run says how far it has got, as its lane on the floor does (progress(): the file that runs now).
    const said = (c) => { const p = c.kind === 'run' ? progress(c) : null; return p ? `${stepName(c)} · ${p.text}` : stepName(c); };
    const rows = list.map((c) => [c.kind === 'blocked', named(c), c.title || 'untitled',
      c.kind === 'blocked' ? (c.yes ? 'Waiting for your yes' : `Stuck at ${NAMES[c.at]}`) : said(c), Number.isNaN(c.since) ? '' : minutes(mins(c))]);
    const sig = JSON.stringify(rows);
    if (view.listSig === sig) return;
    view.listSig = sig;
    view.list.replaceChildren(...(rows.length ? rows.map(([bad, no, title, step, min]) => {
      const li = h('li', bad ? 'b3-row bad' : 'b3-row');
      li.append(h('b', null, no), h('span', 'b3-row-title', title), h('span', 'b3-row-step', step), h('span', 'b3-row-min', min));
      return li;
    }) : [h('li', 'b3-row-none', 'No card is on the belt or stuck.')]));
  }
  // ---- the round badge a crate carries ("2", "3", …) once its card is past its first round in a step ----
  function drawBadges() {
    const live = new Set(view.cards.map((c) => c.key));
    view.badges.forEach((el, k) => { if (!live.has(k)) { el.remove(); view.badges.delete(k); } });
    view.cards.forEach((c) => {
      let el = view.badges.get(c.key);
      if (!el) { el = view.ctx.h('div', 'b3-lb b3-rd off'); view.labels.append(el); view.badges.set(c.key, el); }
      const n = roundShown(c);
      cls(el, `b3-lb b3-rd${n ? '' : ' off'}`);
      txt(el, n ? String(n) : '');
    });
  }
  // ---- the bays: the first three cards of each, and how many there are ----
  function bayTag(c) {
    let t = view.tags.get(c.key);
    if (!t) {
      const h = view.ctx.h, el = h('div', 'b3-lb b3-bc off'), top = h('div', 'b3-t');
      top.append(h('b'), h('span'));
      el.append(top, h('div', 'b3-s'));
      view.labels.append(el);
      t = { el, no: top.firstChild, title: top.lastChild, sub: el.lastChild };
      view.tags.set(c.key, t);
    }
    return t;
  }
  function drawBays() {
    const live = new Set(view.cards.map((c) => c.key));
    view.tags.forEach((t, k) => { if (!live.has(k)) { t.el.remove(); view.tags.delete(k); } });
    const inBay = new Map();
    BAYS.forEach(([kind], j) => {
      const list = of(kind), head = view.bayHeads[j];
      txt(head.count, tally(kind));
      txt(head.more, list.length > SHOWN ? `${SHOWN} shown` : '');
      list.forEach((c, i) => { if (i < SHOWN) inBay.set(c.key, { bay: j, slot: i, line: bayLine(c, i) }); });
    });
    view.cards.forEach((c) => {
      const t = bayTag(c), b = inBay.get(c.key), hot = c.key === view.hover || c.key === view.pin;
      cls(t.el, `b3-lb b3-bc${b ? '' : ' off'}${b && hot ? ' hot' : ''}`);
      attr(t.el, 'data-issue', String(c.issue));
      txt(t.no, no(c));
      txt(t.title, c.title || 'untitled');
      txt(t.sub, b ? b.line : '');
    });
    return inBay;
  }
  // ---- the header strip: a count a state, and a count a step of the running cards, zeros dimmed ----
  function drawSum() {
    Object.keys(HEAD).forEach((k) => txt(view.counts[k], tally(k)));
    const run = of('run');
    view.steps.forEach((s, i) => { const n = run.filter((c) => c.at === i).length; txt(s.lastChild, String(n)); cls(s, n ? 'b3-step' : 'b3-step z'); });
  }

  // ---- the deck behind the floor: its picture made once, its readouts written in place ----
  const SVG = 'http://www.w3.org/2000/svg';
  function svg(tag, attrs, parent) {
    const el = document.createElementNS(SVG, tag);
    Object.entries(attrs).forEach(([k, v]) => el.setAttribute(k, String(v)));
    if (parent) parent.append(el);
    return el;
  }
  function buildDeck(h) {
    const deck = h('div', 'b3-deck'), grid = h('div', 'b3-grid');
    deck.setAttribute('aria-hidden', 'true');
    grid.append(h('i'));
    // The core glow and the three rings, centred on the floor (app.css .b3-rings: the stage between its bands; their
    // colour is the stylesheet's).
    const pic = svg('svg', { class: 'b3-rings', viewBox: '0 0 1400 560', preserveAspectRatio: 'xMidYMid slice' });
    const core = svg('radialGradient', { id: 'b3-core' }, svg('defs', {}, pic));
    svg('stop', { offset: 0, 'stop-opacity': 0.45 }, core);
    svg('stop', { offset: 1, 'stop-opacity': 0 }, core);
    svg('circle', { cx: 700, cy: 280, r: 250, fill: 'url(#b3-core)' }, pic);
    const rings = svg('g', {}, pic);
    svg('circle', { class: 'b3-ring r1', cx: 700, cy: 280, r: 235, 'stroke-width': 2, 'stroke-dasharray': '4 10 60 10', opacity: 0.7 }, rings);
    svg('circle', { class: 'b3-ring r2', cx: 700, cy: 280, r: 200, 'stroke-width': 10, 'stroke-dasharray': '140 40 20 40', opacity: 0.25 }, rings);
    svg('circle', { class: 'b3-ring r1', cx: 700, cy: 280, r: 275, 'stroke-width': 1, 'stroke-dasharray': '2 6', opacity: 0.5 }, rings);
    deck.append(grid, pic);
    const hud = h('div', 'b3-hud'), ro = { host: h('div'), slots: h('div', 'free'), clock: h('div'), loop: h('div'), dot: h('span', 'on', '●'), word: h('span') };
    const corner = (k, ...lines) => { const el = h('div', `b3-ro ${k}`); el.append(...lines); return el; };
    const bar = h('div', 'bar');
    bar.append(h('i'));
    ro.loop.append('LOOP ', ro.dot, ' ', ro.word);
    ['tl', 'tr', 'bl', 'br'].forEach((k) => hud.append(h('i', `b3-cn ${k}`)));
    hud.append(corner('tl', ro.host, bar), corner('tr', ro.slots), corner('bl', ro.clock), corner('br', ro.loop));
    view.ro = ro;
    return [deck, hud];
  }
  function drawDeck() {
    const d = view.deck || {}, r = view.ro, state = str(d.state);
    txt(r.host, `CONVEYOR · ${(str(d.host) || '—').toUpperCase()}`);
    // The slots as the machine bar has them ("5 OF 13 IN USE"): the cards holding a machine slot (a card that only
    // waits holds none), of the slots in force, every project's (the page's project filter leaves the deck whole, as
    // the head). The "On the belt" tile counts the cards against the card cap instead, so its figure can differ.
    // The header strip's counts are not repeated here (issue 413).
    txt(r.slots, !num(d.used) ? 'SLOTS — IN USE' : `SLOTS ${d.used}${num(d.cap) ? ` OF ${d.cap}` : ''} IN USE`);
    txt(r.clock, `ET ${ET(Date.now(), true)}`);
    cls(r.dot, state === 'running' ? 'on' : 'off');
    txt(r.word, state === 'running' ? 'LIVE' : (state || '—').toUpperCase());
  }

  // ---- the tooltip and the details ----
  function tip(key, x, y) {
    const c = key ? view.byKey.get(key) : null, el = view.tip;
    if (key !== view.hover) { view.hover = c ? key : null; draw(); run(); }
    el.hidden = !c;
    if (!c) return;
    const h = view.ctx.h, top = h('div'), small = h('small'), dot = h('i');
    dot.className = `b3-dot-${c.kind}`;
    top.append(h('b', null, named(c)), c.title || 'untitled');
    small.append(dot, `${say(c)}. Click for details.`);
    el.replaceChildren(top, small);
    const r = view.stage.getBoundingClientRect();
    const left = Math.round(Math.min(x - r.left + 14, r.width - el.offsetWidth - 10)), top2 = Math.round(Math.min(y - r.top + 18, r.height - el.offsetHeight - 10));
    el.style.transform = `translate(${Math.max(0, left)}px, ${Math.max(0, top2)}px)`;
  }
  function pick(key) {
    view.pin = key && view.byKey.has(key) ? key : null;
    draw();
    run();
  }
  function findings(n) {
    if (!n) return '';
    const f = ['P0', 'P1', 'P2', 'P3'].filter((k) => num(n[k]) && n[k] > 0).map((k) => `${n[k]} ${k}`).join(', ');
    return f ? `(${f})` : '(no findings)';
  }
  function details() {
    const box = view.detail, c = view.pin ? view.byKey.get(view.pin) : null;
    // Closed, it is out of sight and inert: nothing in it takes the focus. The old text stays while it slides away.
    if (!c) { view.pin = null; box.classList.remove('open'); box.toggleAttribute('inert', true); return; }
    const ctx = view.ctx, h = ctx.h;
    const sig = JSON.stringify([c, view.multi, status(c), time(c)]);
    box.classList.add('open');
    box.toggleAttribute('inert', false);
    if (sig === view.detailSig) return;
    view.detailSig = sig;
    const head = h('h2');
    head.append(ctx.issueLink(c));
    if (view.multi) head.append(h('span', 'b3-repo', c.repo));
    const chip = h('p', `b3-chip b3-c-${c.kind}`);
    chip.append(h('i'), say(c));
    const six = h('ol', 'b3-six');
    c.steps.forEach((s, i) => {
      const li = h('li', `s-${s.state}`), when = s.state === 'done' && num(s.sec) ? ctx.took(s.sec) : s.state === 'now' ? `${time(c)} so far${runs(c, s)}` : s.state === 'todo' ? '' : s.state;
      li.append(h('span', null, MARK[s.state]), i === c.at && c.kind === 'run' ? stepName(c) : i === 0 && s.state === 'done' && s.replyFix === 'done' ? 'Build · reply check fixed' : i === 0 && s.state === 'done' && s.lintFix === 'done' ? 'Build · lint fixed' : s.name, h('em', null, when));
      six.append(li);
    });
    const parts = [h('div', 'b3-eyebrow', KIND[c.kind]), head, h('p', 'b3-ttl', c.title || 'untitled'), chip, six];
    const tests = c.tests, p = progress(c);
    if (p && c.files && c.files.now) {
      const pb = h('div', 'b3-pb'), bar = h('i');
      fill(bar, p.share);
      pb.append(bar);
      parts.push(h('h3', null, 'Tests'), pb, h('p', null, p.whole || p.text));
    } else if (tests) {
      const pb = h('div', 'b3-pb'), bar = h('i');
      fill(bar, tests.done / tests.of);
      pb.append(bar);
      parts.push(h('h3', null, 'Tests'), pb, h('p', null, `${tests.done} of ${tests.of} run, ${num(tests.failed) ? tests.failed : 0} failed`));
    } else if (c.files && c.kind === 'run') {
      const pb = h('div', 'b3-pb'), bar = h('i');
      fill(bar, c.files.run / c.files.of);
      pb.append(bar);
      parts.push(h('h3', null, 'Tests'), pb, h('p', null, `${c.files.run} of ${c.files.of} test files run`));
    }
    if (c.reviews.length) {
      parts.push(h('h3', null, 'Reviews'));
      c.reviews.forEach((r) => {
        const p = h('p', null, `Round ${r.round}: `);
        p.append(h('b', r.verdict === 'GO' ? 'go' : 'nogo', r.verdict || 'no verdict'), r.counts ? ` ${findings(r.counts)}` : '');
        parts.push(p);
      });
    }
    if (c.kind === 'blocked') parts.push(h('h3', null, c.yes ? 'Waiting for your yes' : 'Stuck because'), h('p', 'why', c.reason), h('p', null, Number.isNaN(c.since) ? '' : `${c.yes ? 'Waiting' : 'Stuck'} for ${time(c)}.`));
    if (c.kind === 'run' && c.waitsOn !== null && c.waitsOn !== undefined) { const d = find(c, c.waitsOn); parts.push(h('h3', null, 'Waiting on'), h('p', null, `${ref(c.waitsOn)}${d ? ` ${d.title} (${status(d)})` : ''}, to land first`)); }
    if (c.kind === 'waiting') parts.push(h('h3', null, 'Waiting on'), ...c.waitsFor.map((n) => { const d = find(c, n); return h('p', null, `${ref(n)}${d ? ` ${d.title} (${status(d)})` : ''}`); }));
    // Releasing it is needed, not enough: an open issue it depends on, or a rule that skips it, still keeps it back.
    if (c.kind === 'held') parts.push(h('h3', null, 'Held'), h('p', null, 'Held on the Board. Conveyor does not pick it until someone releases it.'),
      ...c.waitsFor.map((n) => { const d = find(c, n); return h('p', null, `Waits on ${ref(n)}${d ? ` ${d.title} (${status(d)})` : ''}`); }));
    if (c.usd !== null) parts.push(h('p', 'b3-meta', `Cost so far ${ctx.money(c.usd, c.estimate)}${c.kind === 'run' && c.turns !== null && c.turns !== undefined ? ` · ${c.turns} turns in this step` : ''}`));
    // The × stays: the text is redrawn as the card's time runs, and a × drawn anew between its press and its release
    // lost the click (the browser gives it to the element pressed, then gone), so the details did not close.
    while (view.close.nextSibling) view.close.nextSibling.remove();
    box.append(...parts);
  }

  // ---- what the scene draws, as plain data and the elements it places ----
  function draw() {
    if (!view.ctx) return;
    const list = lanes();
    drawRows(list);
    drawList(list);
    const inBay = drawBays();
    drawBadges();
    drawSum();
    drawDeck();
    details();
    const rowOf = new Map(list.map((c, i) => [c.key, i]));
    view.state = {
      open: view.pin !== null, heads: view.heads, bays: view.bayHeads.map((b) => b.el),
      rows: list.map((c, i) => ({ key: c.key, stuck: c.kind === 'blocked', live: c.kind === 'run', hot: c.key === view.hover || c.key === view.pin, at: c.at,
        steps: c.steps.map((s) => s.state), name: view.rows[i].name, now: view.rows[i].now, marks: view.rows[i].marks,
        back: backWay(c) ? { from: c.back.from, to: c.back.to } : null, label: view.rows[i].back })),
      cards: view.cards.map((c) => {
        const b = inBay.get(c.key), r = rowOf.has(c.key) ? rowOf.get(c.key) : null;
        return { key: c.key, from: c.from, kind: c.kind, row: r, at: c.at, bay: b ? b.bay : null, slot: b ? b.slot : null, tag: view.tags.get(c.key).el, badge: view.badges.get(c.key) };
      }),
    };
  }

  // ---- the frame loop: only while the panel is in view and the page is ----
  // A collapsed panel's body is hidden, but shown full screen, or filling the window, all the same (app.css
  // .panel:fullscreen, .panel.b3-fill).
  // On a phone, out of full screen, the floor is not shown (the lanes' list is, app.css): it is neither fetched nor drawn.
  function visible() {
    const r = view.root, fs = document.fullscreenElement || view.filled, hid = r && r.closest('[hidden]');
    const shown = !hid || Boolean(fs && fs !== hid && fs.contains(hid) && hid.classList.contains('panel-body'));
    return Boolean(r && r.isConnected && shown && view.inView && document.visibilityState !== 'hidden' && (fs || !phone()));
  }
  // Once the scene says it has settled (every spring at rest, nothing pulsing) no frame is asked for (#569) until an
  // update, a resize, the pointer on another card, the details opening or closing, or the panel back in sight runs it again.
  function run() {
    if (view.raf !== null || !view.scene || !visible()) return;
    view.still = false;
    view.last = view.seenAt = Date.now();
    const frame = () => {
      view.raf = null;
      if (!visible() || !view.scene) return;  // stopped; a refresh, the clock or the panel back in view starts it again
      const t = Date.now(), dt = Math.min(0.05, Math.max(0, (t - view.last) / 1000));
      view.last = t;
      view.state.motion = view.ctx.motion();
      // A frame reads no layout unless the window was resized since the last frame: a read each frame laid the page
      // out 60 times a second and made a scroll stutter (#562).
      if (view.resized) { view.resized = false; room(); }
      view.still = view.scene.frame(view.state, dt) === true;
      // The scene's resize, in that frame, may have asked for the next one already.
      if (!view.still && view.raf === null) view.raf = window.requestAnimationFrame(frame);
    };
    view.raf = window.requestAnimationFrame(frame);
  }
  function webgl() {
    try { const c = document.createElement('canvas'); return Boolean(c.getContext('webgl2') || c.getContext('webgl')); } catch (e) { return false; }
  }
  function fail(text) {
    view.failed = true;
    view.note.textContent = text;
    view.note.hidden = false;
    view.labels.hidden = true;
  }
  // The scene's code (and three.js with it) is fetched the first time the panel is shown.
  function load() {
    if (view.scene || view.loading || view.failed || !visible()) return;
    if (!webgl()) { fail('This browser gives no WebGL, so the Board cannot draw the floor. Every other panel works as before.'); return; }
    view.loading = true;
    const mod = window.DASH_BELT3D_SCENE ? Promise.resolve(window.DASH_BELT3D_SCENE) : import(new URL('belt3d-scene.js', document.baseURI).href);
    mod.then((m) => {
      view.scene = m.createScene({ host: view.stage, labelsEl: view.labels, hover: tip, pick, wake: run });
      view.loading = false;
      run();
    }).catch((e) => { view.loading = false; fail(`The Board could not draw the floor: ${String((e && e.message) || e)}`); });
  }
  function wake() { load(); run(); }

  // ---- full screen: the whole panel, by the browser's Fullscreen API, its header set aside and this button moved ----
  // from the header to the header strip's right end (issue 421), and back on leaving.
  // Where that API is missing or refuses, the same button makes the panel fill the browser window instead (app.css
  // .b3-fill), the page behind it held still. The button, Esc or the browser's own way out bring it back; on the way
  // in and out, and on each resize of the window (a turn of the phone) while it fills it, the floor is fitted anew.
  function fullTool(ctx, el) {
    const panel = el.closest('.panel'), bar = panel && panel.querySelector('.panel-tools');
    if (!bar) return;
    const api = document.fullscreenEnabled === true && typeof panel.requestFullscreen === 'function' && typeof document.exitFullscreen === 'function';
    const b = ctx.h('button', 'tool full');
    b.type = 'button';
    const show = () => {
      const on = document.fullscreenElement === panel || view.filled === panel, label = on ? 'Leave full screen' : 'Show Belt 3D full screen';
      b.setAttribute('aria-label', label); b.title = label;
      b.replaceChildren(ctx.icon(on ? 'shrink' : 'expand'));
      // Full screen the button sits at the header strip's right end and the header is set aside (app.css
      // .b3-headless); out of it, back first in the header's tools. A failed or empty refresh takes the floor, its
      // strip with it, out of the panel: the button goes back to the header, shown again, or full screen would be
      // left with no way out on a phone. Moved from the page to the page, a button that had the focus keeps it.
      const strip = on && el.contains(view.sum), home = strip ? view.sum : bar;
      panel.classList.toggle('b3-headless', strip);
      if (b.parentNode !== home) {
        const had = document.activeElement === b;
        if (strip) home.append(b); else home.prepend(b);
        if (had) b.focus({ preventScroll: true });
      }
    };
    // The panel's body changed (an error, "empty", or the floor back): the button follows the strip.
    if (typeof window.MutationObserver === 'function') new window.MutationObserver(show).observe(el, { childList: true });
    const refit = () => { show(); if (view.scene) view.scene.resize(); wake(); };
    // While it fills the window, the panel taken out of the page (another tab, or Back to one) or hidden puts it back,
    // or the page it leaves behind would be held still with no button to free it.
    const gone = typeof window.MutationObserver === 'function'
      ? new window.MutationObserver(() => { if (!panel.isConnected || panel.hidden) fill(false); }) : null;
    const fill = (on) => {
      if ((view.filled === panel) === on) return;
      view.filled = on ? panel : null;
      panel.classList.toggle('b3-fill', on);
      document.documentElement.classList.toggle('b3-filling', on);
      if (gone && on) {
        gone.observe(document.documentElement, { childList: true, subtree: true });
        gone.observe(panel, { attributes: true, attributeFilter: ['hidden'] });
      } else if (gone) gone.disconnect();
      refit();
    };
    b.addEventListener('click', () => {
      if (view.filled === panel) { fill(false); return; }
      if (!api) { fill(true); return; }
      if (document.fullscreenElement === panel) {
        const p = document.exitFullscreen();
        if (p && typeof p.catch === 'function') p.catch(() => {});
        return;
      }
      // Refused (no user gesture, or a frame that may not): the panel fills the window instead.
      let p;
      try { p = panel.requestFullscreen(); } catch (e) { fill(true); return; }
      if (p && typeof p.catch === 'function') p.catch(() => fill(true));
    });
    document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && view.filled === panel) fill(false); });
    window.addEventListener('resize', () => { if (view.filled === panel && view.scene) view.scene.resize(); });
    if (api) document.addEventListener('fullscreenchange', refit);
    show();
  }

  function build(ctx) {
    const h = ctx.h, root = h('div', 'b3');
    view.stage = h('div', 'b3-stage');
    view.labels = h('div', 'b3-labels');
    // The header strip: every state's count, and each step's of the running cards, so it never changes length; full
    // screen, the full-screen button joins it after the counts (fullTool).
    view.sum = h('div', 'b3-sum b3-glass');
    const ks = h('span', 'b3-ks');
    Object.keys(HEAD).forEach((k) => {
      const s = h('span', `b3-k b3-k-${k}`);
      view.counts[k] = h('b', null, '0');
      s.append(h('i'), HEAD[k], view.counts[k]);
      ks.append(s);
      if (k === 'run') {
        const steps = h('span', 'b3-steps');
        view.steps = NAMES.map((n) => { const x = h('span', 'b3-step z'); x.append(n, h('b', null, '0')); steps.append(x); return x; });
        ks.append(steps);
      }
    });
    view.sum.append(ks);
    // The column heads over the lanes, and the bays' heads.
    view.heads = ['Card', ...NAMES, 'Right now'].map((n, i) => {
      const el = h('div', 'b3-lb b3-hd');
      if (i >= 1 && i <= 6) el.append(h('i', null, String(i)));
      el.append(n);
      return el;
    });
    view.bayHeads = BAYS.map(([kind, name]) => {
      const el = h('div', `b3-lb b3-bh b3-bh-${kind}`), count = h('b', null, '0'), more = h('em');
      el.append(name, count, more);
      return { el, count, more };
    });
    view.labels.append(...view.heads, ...view.bayHeads.map((b) => b.el));
    view.tip = h('div', 'b3-tip b3-glass');
    view.tip.hidden = true;
    view.detail = h('aside', 'b3-detail b3-glass');
    view.detail.setAttribute('aria-live', 'polite');
    view.detail.toggleAttribute('inert', true);
    view.close = h('button', 'b3-close', '×');
    view.close.type = 'button'; view.close.setAttribute('aria-label', 'Close');
    view.close.addEventListener('click', () => pick(null));
    view.detail.append(view.close);
    view.note = h('p', 'warn-note b3-note');
    view.note.hidden = true;
    // The details are the panel's, not the stage's: beside the floor they lie over the stage's right, and on a phone,
    // with no room beside it, they open below it (app.css).
    view.stage.append(...buildDeck(h), view.labels, view.sum, view.note, view.tip);
    // On a phone, the lanes' list in the floor's place (app.css).
    const flat = h('div', 'b3-phone');
    view.list = h('ol', 'b3-list');
    view.list.setAttribute('aria-label', 'Cards on the belt: each card, its step and its minutes there');
    flat.append(h('p', 'b3-list-note', 'Each card on the belt: the step it is in and its minutes there. A wider screen shows the 3D floor.'), view.list);
    root.append(view.stage, view.detail, flat);
    view.root = root;
    if (typeof window.IntersectionObserver === 'function') {
      view.inView = false;
      new window.IntersectionObserver((es) => { view.inView = es.some((e) => e.isIntersecting); wake(); }).observe(root);
    }
    document.addEventListener('visibilitychange', wake);
    window.addEventListener('resize', () => { view.resized = true; run(); });
  }

  window.DASH_APP.panel({
    id: 'belt3d',
    title: 'Belt 3D',
    size: 'full',
    tab: 'belt3d',  // a tab of its own, the only panel on it
    rows: 'all',  // one floor, its whole height
    projects: true,  // filtered to one project, its cards alone (the part's byRepo)
    isEmpty: (d) => [d.belt, d.needs, d.landed].every((a) => !Array.isArray(a) || a.length === 0)
      // An unread queue is unknown, not empty: the floor is drawn, its counts a dash.
      && Boolean(d.queue && typeof d.queue === 'object') && [d.queue.next, d.queue.waiting, d.queue.held].every((a) => Array.isArray(a) && a.length === 0),
    empty(el, ctx) { el.append(ctx.state('empty', 'The floor is empty', 'No card is on the belt, stuck, queued, waiting, held or landed today.')); },
    error(el, message, ctx) { el.append(ctx.state('error', 'The Board could not read Belt 3D', message)); },
    // Each second: the times on the floor move on (words in place, nothing for the scene to move), and a panel that came
    // into view loads or starts its scene. A settled scene seen at the last tick asks for no frame (#569); one out of
    // sight since (collapsed, or its tab not shown, when no tick comes at all) draws again.
    tick() {
      if (view.ctx && view.root && view.root.isConnected) draw();
      load();
      if (!view.still || Date.now() - view.seenAt > 1500) run();
      if (visible()) view.seenAt = Date.now();
    },
    render(el, d, ctx) {
      view.ctx = ctx;
      if (!view.root) { build(ctx); fullTool(ctx, el); }
      if (el.firstChild !== view.root) el.replaceChildren(view.root);
      view.cards = model(d);
      view.deck = d.deck && typeof d.deck === 'object' ? d.deck : null;
      view.byKey = new Map(view.cards.map((c) => [c.key, c]));
      view.byIssue = new Map();
      view.cards.forEach((c) => { const k = `${c.repo}#${c.issue}`; if (!view.byIssue.has(k)) view.byIssue.set(k, c); });
      view.multi = Array.isArray(d.repos) && d.repos.length > 1;
      if (view.hover && !view.byKey.has(view.hover)) { view.hover = null; view.tip.hidden = true; }
      draw();
      wake();
    },
  });
}());
