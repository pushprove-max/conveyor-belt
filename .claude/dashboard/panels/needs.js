// SPDX-License-Identifier: Apache-2.0
// Needs you: what waits on the owner, and the one place it is answered (the Control tab's Needs you column links here).
// Blocked cards with the reason, visible changes waiting for their yes, and the open decisions, each with its project
// (repo) and answered here (POST answer, to the page's own host). A blocked card leads with why it failed, in one plain
// sentence (ctx.failureLine: its explanation is shown under it), then what Retry does, then its output on demand.
// It has Retry and Close, each sent as POST /control retry or close on a second click (Retry costs a new build; Close
// cannot be undone, and says so), and Hold (POST /control unblock: one click with Undo, a release). A card whose reason
// has a fix Conveyor runs itself (FIXES) also has Fix, which says what it does. Its last line names the step its kind
// of block takes (STEPS). One its host already gave back (retried) shows "Retried, waiting for its turn", with no
// buttons. Its part:
// {cards: {waiting, blocked} | null, cardsError, decisions | null, decisionsError, retrying, retried, kinds, entries}. A group that was not read says so; it is never "nothing". A card
// comes with its reviews and its track, as `conveyor.sh snapshot` gives them: a blocked card is off the
// belt, so the step it failed at, with the seconds that step ran, is shown here on its six steps. There is no main
// session any more: an answer that is recorded is done, and nothing is listed as unsent. It stays on
// Overview whatever its cause. A card waiting for the owner's yes is answered here too: the reviewer's sentence,
// the files it changed, the project's own screenshots of that change when it kept some (shotsOf), and Approve,
// Approve with a condition and Decline, each confirmed by a second click and sent
// as POST /control approve or decline, with the card's repository (the host acts on that record's issue). A
// follow-up that goes beyond its parent's yes says what goes beyond it. An issue whose section "What customers
// or staff will see" names a change waits here before it is built (cards.before: null when it was not read):
// the section's text and the same three actions; approved, it is picked in its turn; declined, it is held.
// A follow-up whose finding names a pipeline file (how cards are built, reviewed, fixed, tested, landed or pushed) is
// filed held and listed here (cards.pipeline) with its "Cost to every card:" line until the owner queues it (Queue,
// one click with Undo: POST /control release, then hold) or closes it (Close, on a second click: POST /control close).
// An issue whose Depends on: line names another repository's issue (owner/repo#N) that GitHub would not give (no
// access, not found) waits as if it were open, and is listed here (cards.farDeps) with the line and what gh said.
// An action the host took greys its entry in place, its buttons gone, saying what it waits for ("Retried, waiting for
// the loop"), until the entry leaves the panel in about a minute; a refusal puts the buttons back with the host's answer.
// A project whose whole test fails on main (tests: Conveyor runs it there after landings, not in each card) is
// listed with the issue filed for it, the failing cases and the commits it failed between, until a run of it succeeds.
// A project that follows the plugin's main and did not take its newest commit (engines: it failed its check, or lacks
// a hook the project runs) is listed with that commit and why, until a later commit is taken.
// A project whose test rules matched more test files in one run than one day's cap (testRules: the burst guard) filed
// none of them: one line says how many and the cap, until a later run of the rules files or stops below it.
// A landed card whose push fails and is tried again by the loop (retrying: each with the fix card building for it, if
// any) needs nothing of the owner: with nothing else here, the line under the tick says so, so a red "Failing" in
// Health is never beside a bare "Nothing needs you".
const beforeOf = (d) => (d.cards && Array.isArray(d.cards.before) ? d.cards.before : []);
const pipelineOf = (d) => (d.cards && Array.isArray(d.cards.pipeline) ? d.cards.pipeline : []);
const farDepsOf = (d) => (d.cards && Array.isArray(d.cards.farDeps) ? d.cards.farDeps : []);
// The block reasons with a fix Conveyor can run itself (docs/board.md, Needs you, which lists each): the reason's
// start, the arguments the fix adds to retry after the issue, and what it does. Each here is a kept patch that cannot
// be used (card(), lib/card.sh): the issue is built again from nothing. A landing conflict has no Fix of its own: Retry already brings
// the kept patch onto main in one session. A reason not here has no fix Conveyor can run, and shows no Fix.
const FIXES = [
  [/^(worktree: the kept patch of card \S+ could not be taken out of the worktree|review [0-9]+: the engine could not compare the port with the kept patch)/,
    ['--fresh'], (n) => `Fix builds ${n} again from nothing, without its kept work, which Conveyor cannot use. That work moves to kept-dropped/ in the state folder.`],
];
// The step a blocked card's last line names, by its kind of block (docs/board.md, Needs you), read from the first line
// of its reason: the rest of it is a review finding or test output, which can hold any words. A review, test or
// no-result block is fixed by Retry itself, as its new session gets the open finding or the failing tests; so is a
// landing conflict, which its new session brings onto main. A block that needs the owner first says what to do, then
// Retry. Any other names its reason and what Retry does, and never asks the owner to wait for anything first.
const RETRY_FIXES = 'Retry: a new session gets the open finding (or the failing tests) and starts from the kept work.';
const STEPS = [
  [/^(the fix for |review \d+ ended without one clear verdict|the review ended without one clear verdict|review: .*NO-GO)/, RETRY_FIXES],
  [/^(tests: )?(the changed tests (failed again|gave no result)|the project's checks failed again|the Done-when check failed again)/, RETRY_FIXES],
  [/^its process ended without a result/, RETRY_FIXES],
  // A review that says main does not do what the issue asks, where the session said ALREADY-DONE: a review block too,
  // but that session made no change, so there is no kept work to start from.
  [/^the session made no change and said that main already fixes the issue\. The reviewer says/, "Retry: a new session gets the reviewer's finding and builds the issue."],
  // Retry does not wait for the conflict to clear: its new session brings the kept patch onto main as it is.
  [/^rebase onto main conflicts/, 'Retry: a new session brings the kept change onto main as it is now.'],
  [/sign-in/i, 'Sign in again on the build machine, as the reason says. Then press Retry.'],
  [/\bis not installed\b|\bnot on PATH\b/, 'Install what the reason names on the build machine. Then press Retry.'],
  [/\bcannot run the model\b/, 'Set a model the account can run, on the Rules tab. Then press Retry.'],
  [/^worktree: the engine could not link the dependencies|\bmissing in the card's worktree\b/, "Make the project's dependencies reach the card's worktree, as the reason says. Then press Retry."],
  [/\bdepends on\b|\bdependency\b/i, 'Land, release or close the issue it depends on. Then press Retry.'],
  [/\b(decision|approval)\b/i, 'Answer the decision or approval that the reason names. Then press Retry.'],
  [/\bprice\b/i, "Add the model's price to the prices of the project pack. Then press Retry."],
];
const stepOf = (c, said) => {
  const head = typeof c.reason === 'string' ? c.reason.trim().split('\n')[0] : '';
  const kind = STEPS.find(([re]) => re.test(head));
  return kind ? kind[1] : `Blocked because: ${String(said).replace(/[.…]+$/, '')}. Retry starts a new card, from the kept work if there is any.`;
};
const fixOf = (c) => (c.issue > 0 && typeof c.reason === 'string' ? FIXES.find(([re]) => re.test(c.reason)) || null : null);
// The project's own screenshots of a waiting card's change (its shots: keepshots(), conveyor/lib/push.sh), only while
// they were kept for its kept patch as it is now (shots.patch is the card's patch): an image of an older patch of the
// card is not shown as the current one. Each file is named by its content, so it is read by that name only.
const SHOT = /^[0-9a-f]{40,64}\.(png|jpg|gif|webp)$/;
const shotsOf = (c) => (c.shots && typeof c.shots === 'object' && typeof c.patch === 'string' && c.patch !== '' && c.shots.patch === c.patch
  && Array.isArray(c.shots.shots) ? c.shots.shots.filter((s) => s && typeof s.file === 'string' && SHOT.test(s.file)) : []);
const testsOf = (d) => (Array.isArray(d.tests) ? d.tests : []);
const enginesOf = (d) => (Array.isArray(d.engines) ? d.engines : []);
const testRulesOf = (d) => (Array.isArray(d.testRules) ? d.testRules : []);
// The kinds of Needs you, in order (kinds: .claude/scripts/dashboard_needs.json, the list the Foreman watcher reads too), each
// a group here. A kind with a row of its own below reads its own part; any other (one added to the list later) shows
// its entries (entries[kind]), so no kind is on the list and missing here.
const kindsOf = (d) => (Array.isArray(d.kinds) ? d.kinds.filter((k) => k && typeof k.kind === 'string' && typeof k.title === 'string') : []);
const OWN = { tests: testsOf, engines: enginesOf, testRules: testRulesOf, before: beforeOf, pipeline: pipelineOf, farDeps: farDepsOf,
  waiting: (d) => (d.cards ? d.cards.waiting : []), blocked: (d) => (d.cards ? d.cards.blocked : []) };
const itemsOf = (d) => Object.fromEntries([...kindsOf(d).map(({ kind }) => [kind, Object.hasOwn(OWN, kind) ? OWN[kind](d)
  : (d.entries && Array.isArray(d.entries[kind]) ? d.entries[kind].filter((x) => x && typeof x === 'object') : [])]), ['decisions', d.decisions || []]]);
window.DASH_APP.panel({
  id: 'needs',
  title: 'Needs you',
  size: 'wide',
  tab: 'overview',
  projects: true,
  // What stops the loop for the owner is never hidden: a browser that hid it would miss every block.
  alwaysShown: true,
  rows: 6,
  // The Overview tab's count ("Overview · 4"): the cards stopped for the owner, as the head's Needs you tile counts
  // them (head.js), so the two never disagree.
  attention: (d) => (d.cards && Array.isArray(d.cards.waiting) && Array.isArray(d.cards.blocked) ? d.cards.waiting.length + d.cards.blocked.length : 0),  count(d) {
    return Object.values(itemsOf(d)).reduce((n, xs) => n + xs.length, 0);
  },
  // A list that was not read (cards.before null) is never "nothing".
  isEmpty(d) { return Boolean(d.cards && d.decisions && !d.decisionsError && d.cards.before !== null) && this.count(d) === 0; },
  empty(el, ctx, d) {
    el.append(ctx.state('empty', 'Nothing needs you', 'Nothing blocks a card, and no test fails on main. No project refused a Conveyor update, and no visible change waits for your yes. No pipeline change waits for you, and no decision is open.'));
    // A push failing while the loop tries it again needs nothing of the owner, but is said under the tick.
    const r = d && Array.isArray(d.retrying) ? d.retrying.filter((x) => x && typeof x === 'object') : [];
    if (!r.length) return;
    const fixes = r.map((x) => x.fix).filter((n) => Number.isInteger(n) && n > 0);
    const line = ctx.h('p', 'hint needs-retrying', `Nothing needs you. ${r.length === 1 ? 'One push fails' : `${r.length} pushes fail`}, and Conveyor tries again${fixes.length
      ? `. ${fixes.length === 1 ? 'A fix card' : 'Fix cards'} (${fixes.map((n) => `#${n}`).join(', ')}) ${fixes.length === 1 ? 'is' : 'are'} on the belt` : ''}.`);
    line.setAttribute('role', 'status');
    el.append(line);
  },
  error(el, message, ctx) { el.append(ctx.state('error', 'The Board could not read Needs you', message)); },
  render(el, d, ctx) {
    const h = ctx.h;
    const groupOf = (key) => Array.from(el.children).find((g) => g.dataset.group === key);
    for (const { kind: key, title } of [...kindsOf(d), { kind: 'decisions', title: 'Open decisions' }]) {
      if (groupOf(key)) continue;
      const group = h('section', 'group');
      group.dataset.group = key;
      group.append(h('h3', 'group-title', title), h('p', 'warn-note'), h('ul', 'rows'));
      const decisions = groupOf('decisions');
      if (decisions) el.insertBefore(group, decisions); else el.append(group);
    }
    // A blocked card its host already gave back (retried: the record's retried lines, read at once, before the
    // snapshot that drops the card) waits for its new card: it is drawn anew, with no buttons, until that snapshot.
    const retried = new Set((Array.isArray(d.retried) ? d.retried : []).filter((x) => x && typeof x.card === 'string').map((x) => `${x.repo}\n${x.card}`));
    const isRetried = (c) => retried.has(`${c.repo}\n${c.card}`);
    const keyOf = { tests:(x) => `tests:${x.repo}`, engines: (x) => `engine:${x.repo}@${x.commit}`, testRules: (x) => `testrules:${x.repo}@${x.time}`, before: (x) => `before:${x.repo}#${x.issue}`, pipeline: (x) => `pipeline:${x.repo}#${x.issue}`, farDeps: (x) => `fardep:${x.repo}#${x.issue}:${x.ref}`, waiting: (c) => `waiting:${c.card}`, blocked: (c) => `blocked:${c.card}${isRetried(c) ? ':retried' : ''}`, decisions: (x) => `decision:${x.repo}:${x.id}@${x.askedAt}` };
    const items = itemsOf(d);
    for (const key of Object.keys(items)) if (!Object.hasOwn(keyOf, key)) keyOf[key] = (x) => `${key}:${x.repo}#${x.issue}:${x.card}:${x.since}`;
    const isNew = new Set(ctx.fresh(Object.keys(items).flatMap((k) => items[k].map(keyOf[k]))));
    const errors = {
      before: d.cards && d.cards.before === null ? 'The Board could not read the issues that wait for your yes before their build: GitHub did not list the open issues.' : null,
      waiting: d.cards ? null : `The Board could not read the cards, so it shows none. ${ctx.retry}`,
      // What cannot be seen, and that it is read again (the decisions are read on this machine).
      decisions: d.decisions ? (d.decisionsError ? 'The Board could not read some open decisions, so this list can miss some. It reads them again in about a minute.' : null)
        : 'The Board could not read the open decisions, so it shows none. It reads them again in about a minute.',
    };
    // The reader's own reason (it names files and internal parts) on tap only.
    const why = { waiting: d.cards ? '' : d.cardsError, decisions: d.decisionsError };

    const cardRow = (kind) => (c) => {
      const li = h('li', 'row');
      const head = h('div', 'row-main');
      const again = kind === 'blocked' && !c.push && isRetried(c);
      head.append(ctx.issueLink(c), h('span', 'title', c.title || 'untitled'), kind === 'waiting' ? ctx.chip('Waiting for your yes', 'warn')
        : again ? ctx.chip('Retried, waiting for its turn', 'quiet') : ctx.chip('Blocked', 'bad'));
      const meta = h('p', 'row-meta');
      meta.append(ctx.tag(c.repo), ctx.since(c.since, ' ago'));
      const n = c.issue > 0 ? `#${c.issue}` : 'its issue';
      // A blocked card's first line is why it failed, in one sentence; its second what Retry does (or why a push needs
      // no retry); its output one click below.
      if (kind === 'waiting') li.append(head, h('p', 'reason', `What customers or staff will see: ${c.sentence || 'the reviewer gave no sentence'}`));
      else {
        li.append(head, ctx.failureLine(c));
        li.append(h('p', 'hint retry-does', c.push && c.check ? `Land a fix for ${c.check} on main. Conveyor then pushes again by itself. It does not retry until main moves.`
          : c.push ? 'Conveyor pushes again by itself when the cause has a fix. You do not need to retry.'
            : again ? `${n} is back in the queue. A new card builds it in its turn.` : `Retry puts ${n} back in the queue, and a new card builds it in its turn.`));
      }
      // A blocked card's output goes here, above its meta line, drawn at each refresh (outputOf): the row is kept.
      // A follow-up whose change goes beyond the yes of an issue above it says what goes beyond it, as its reviewer said.
      const b = kind === 'waiting' && c.beyond && typeof c.beyond === 'object' ? c.beyond : null;
      if (b && typeof b.what === 'string' && b.what.trim()) {
        const of = Number.isInteger(b.from) && b.from > 0 ? `the yes of #${b.from}` : "its parent's yes";
        li.append(h('p', 'reason beyond', `Goes beyond ${of}: ${b.what.trim()}`));
      }
      li.append(meta);
      // A blocked card is off the belt: the step it stopped in and how long that step ran are said here,
      // then its six steps as the belt panel draws them, every recorded step on demand, and one line a finished review.
      const track = h('ol', 'track6');
      if (ctx.track(track, c.track)) {
        const steps = c.track.steps, at = steps.map((s) => s.state).lastIndexOf('failed');
        const sec = at >= 0 && typeof steps[at].sec === 'number' && Number.isFinite(steps[at].sec) ? ctx.took(steps[at].sec) : '';
        if (at >= 0) li.append(h('p', 'stopped', `Failed at ${steps[at].name} (step ${at + 1} of ${steps.length})${sec ? ` after ${sec}` : ''}`));
        li.append(track, ctx.trackDetail(c.track, c.card, null, c.earlier, ctx.text.repoOf(c), c.repo));
      }
      const done = Array.isArray(c.reviews) ? c.reviews : [];
      if (done.length) {
        const reviews = h('ul', 'reviews');
        reviews.append(...done.map((r) => {
          const row = h('li', 'review'), f = ctx.findings(r);
          row.append(h('span', 'issue', `R${r.round}`), ctx.chip(r.verdict || 'no verdict', r.verdict === 'GO' ? 'ok' : 'warn'));
          if (f) row.append(h('span', null, f));
          return row;
        }));
        li.append(reviews);
      }
      if (kind === 'waiting') li.append(yesActions(c));
      // A push that keeps failing is not a card to retry (its card has landed): the loop pushes again by itself; one
      // that failed its check (c.check names it) is pushed again only once a fix lands on main.
      else if (!c.push && !again) {
        const fix = fixOf(c);
        li.append(h('p', 'hint block-step', stepOf(c, ctx.failure(c).said)));
        if (fix) li.append(h('p', 'hint fix-does', fix[2](n)));
        li.append(blockedActions(c, fix));
      }
      return li;
    };
    // A blocked card is retried (conveyor.sh retry: it costs a new build) or its issue closed (for good), here, through
    // POST /control with the card's repository, each on a second click. A main-red fix card has no issue (issue 0): it
    // is retried and shut by its card id, and named as the snapshot names it, "Main is red (<commit>)".
    const target = (c) => (c.issue === 0 && typeof c.card === 'string' && c.card ? c.card : String(c.issue));
    const named = (c) => (c.issue === 0 ? (typeof c.name === 'string' && c.name ? c.name : target(c)) : `#${c.issue}`);
    // A blocked card of an issue also has Fix, when its reason has one (fixOf: retry with the fix's arguments, on a
    // second click, as it costs a build), and Hold (unblock: its issue held, its card off the belt and its kept work
    // kept), one click with Undo (control release). A main-red fix card has no issue to hold.
    const blockedActions = (c, fix) => issueActions(c, [['retry', 'Retry', 'spend', `Click again to retry ${named(c)}`, 'Retried'],
      ...(fix ? [['fix', 'Fix', 'spend', `Click again to fix ${named(c)}`, 'Fixed', ['retry', ...fix[1]]]] : []),
      ...(c.issue > 0 ? [['unblock', 'Hold', null, null, 'Held']] : [])]);
    // A pipeline change held for the owner is queued (control release), one click with Undo (control hold), or its
    // issue closed in the same way. It has no card, so the host's close shuts none.
    const pipelineActions = (x) => issueActions(x, [['release', 'Queue', null, null, 'Queued']]);
    // The first buttons (action, label, guard tier or null for one click, its second-click words, the word said once the
    // host took it, and the action and the arguments after the issue it posts, when not the action alone), then Close.
    // Once the host takes one, the entry is greyed in place and its buttons go, until it leaves the panel; a refusal
    // puts them back with the host's answer.
    function issueActions(c, acts) {
      const box = h('div', 'answer'), note = h('p', 'answer-note');
      note.setAttribute('aria-live', 'polite');
      const t = named(c), buttons = [];
      const all = [...acts, ['close', 'Close', 'final', `Click again: close ${t} for good. Conveyor never builds it`, 'Closed']];
      const row = () => box.closest('li');
      const busy = (on) => { buttons.forEach((b) => { b.disabled = on; b.hidden = on && row() && row().classList.contains('is-pending'); }); };
      const ask = (action, more = []) => {
        if (typeof c.repo !== 'string' || !c.repo) { note.textContent = `Not sent: the Board does not know which repository ${t} is in.`; return null; }
        busy(true);
        note.textContent = 'Sending…';
        return ctx.post('control', { action, args: [target(c), ...more], repo: c.repo })
          // A reply whose body cannot be read is still the host's answer: its status says what happened.
          .then((r) => r.text().then((x) => String(x).trim(), () => '').then((x) => ({ ok: r.ok, said: x || `the build machine answered ${r.status}` })), () => ({ ok: false, said: 'the build machine did not answer. Make sure that it is on. Then try again' }));
      };
      const refused = (r) => { if (row()) row().classList.remove('is-pending'); busy(false); note.textContent = `Not done: ${r.said}`; };
      const send = (post, word) => {
        const [action, ...more] = post, sent = ask(action, more);
        if (sent) sent.then((r) => {
          if (!r.ok) { refused(r); return; }
          if (row()) row().classList.add('is-pending');
          busy(true);
          // The build machine's reply is shown only when the action failed. A queued one can be held again. A held
          // blocked card is released again: its card is off the belt, so it stays greyed, and its issue is built in
          // its turn from its kept work.
          const said = `${word}: ${t} leaves Needs you in about a minute.`;
          note.replaceChildren(action === 'release' ? ctx.undoLine(said, () => {
            const back = ask('hold');
            if (back) back.then((u) => { if (!u.ok) { note.textContent = `Not undone: ${u.said}`; return; } if (row()) row().classList.remove('is-pending'); busy(false); note.textContent = `Undone: the hold on ${t} is back.`; });
          }) : action === 'unblock' ? ctx.undoLine(said, () => {
            const back = ask('release');
            if (back) back.then((u) => { busy(true); note.textContent = u.ok ? `Undone: ${t} is released. Conveyor builds it in its turn, from its kept work.` : `Not undone: ${u.said}`; });
          }) : said);
        });
      };
      for (const [action, label, tier, again, word, post = [action]] of all) {
        const b = h('button', 'btn', label);
        b.type = 'button';
        b.dataset.act = action;
        if (tier) ctx.twice(b, tier, again, () => send(post, word));
        else b.addEventListener('click', () => send(post, word));
        buttons.push(b);
      }
      box.append(...buttons, note);
      return box;
    }
    // The owner answers a visible change here, in one click and a confirming one, through POST /control: Approve,
    // Approve with a condition, or Decline with why. The host's answer is shown and the entry greyed in place; a card
    // approved leaves this panel in about a minute, as it goes back to the belt.
    function filesOf(c) {
      const f = c.files && typeof c.files === 'object' ? c.files : {};
      const paths = Array.isArray(f.paths) ? f.paths.filter((p) => typeof p === 'string') : null;
      const count = typeof f.count === 'number' && Number.isFinite(f.count) ? f.count : paths ? paths.length : null;
      const box = h('div', 'yes-files');
      if (count === null) { box.append(h('p', 'row-meta', 'Files changed: not recorded')); return box; }
      const label = `${count} file${count === 1 ? '' : 's'} changed`;
      if (!paths || !paths.length) { box.append(h('p', 'row-meta', label)); return box; }
      const det = h('details', 'yes-paths'), list = h('ul', 'paths');
      det.append(h('summary', null, `${label}: show the list`));
      list.append(...paths.map((p) => h('li', null, p)));
      if (count > paths.length) list.append(h('li', 'row-meta', `and ${count - paths.length} more`));
      det.append(list);
      box.append(det);
      return box;
    }
    // A waiting card's screenshots (shotsOf), above its Approve, drawn at each refresh: the row is kept. Each comes from
    // the page's own server (GET /shot), which reads it from the card's kept folder on Conveyor's host.
    function shotsIn(li, c) {
      const list = shotsOf(c), old = li.querySelector(':scope > .yes-shots'), sig = JSON.stringify([c.repo, c.card, list]);
      if (old && old.dataset.sig === sig) return;
      if (old) old.remove();
      if (!list.length) return;
      const box = h('div', 'yes-shots'), ul = h('ul', 'shots');
      box.dataset.sig = sig;
      box.append(h('p', 'row-meta', `Screenshots from your project's run of this change (${list.length}):`));
      ul.append(...list.map((s) => {
        const cap = typeof s.caption === 'string' && s.caption ? s.caption : s.file;
        const src = `shot?${new URLSearchParams({ repo: c.repo, card: c.card, file: s.file })}`;
        const item = h('li', 'shot'), fig = h('figure'), a = h('a'), img = h('img');
        a.href = src; a.target = '_blank'; a.rel = 'noopener';
        img.src = src; img.alt = cap; img.loading = 'lazy';
        a.append(img);
        fig.append(a, h('figcaption', null, cap));
        item.append(fig);
        return item;
      }));
      box.append(ul);
      li.querySelector(':scope > .yes').before(box);
    }
    // The whole test of a project, failing on main: the issue filed for it, the cases and the commits it failed between.
    const short = (s) => (typeof s === 'string' && s ? s.slice(0, 12) : null);
    const testsRow = (x) => {
      const li = h('li', 'row');
      const head = h('div', 'row-main');
      const cases = Array.isArray(x.cases) ? x.cases.filter((c) => typeof c === 'string') : [];
      const filed = typeof x.issue === 'number' && x.issue > 0;
      if (filed) head.append(ctx.issueLink(x));
      head.append(h('span', 'title', 'The whole test fails on main'), ctx.chip('Tests failing', 'bad'));
      const meta = h('p', 'row-meta');
      meta.append(h('span', null, x.repo), ctx.since(x.since, ' ago'));
      const at = short(x.to) || 'a commit not recorded';
      const range = short(x.from) ? `Failed at ${at}. It last passed at ${short(x.from)}.` : `Failed at ${at}. The record shows no run that passed before it.`;
      li.append(head, h('p', 'reason', cases.length ? `Failing cases: ${cases.join(', ')}` : 'The run named no failing case.'), h('p', 'reason', range));
      if (!filed) li.append(h('p', 'hint', 'Conveyor could not file an issue for it.'));
      li.append(meta);
      return li;
    };
    // A commit of the plugin's main a following project did not take: the commit and why; the project stays on its engine.
    const engineRow = (x) => {
      const li = h('li', 'row');
      const head = h('div', 'row-main');
      head.append(h('span', 'title', `The project did not take Conveyor commit ${short(x.commit) || 'not recorded'}`), ctx.chip('Engine update refused', 'bad'));
      const meta = h('p', 'row-meta');
      meta.append(h('span', null, x.repo), ctx.since(x.since, ' ago'));
      li.append(head, h('p', 'reason', typeof x.reason === 'string' && x.reason ? x.reason : 'Conveyor recorded no reason'),
        h('p', 'hint', 'The project stays on the Conveyor it has. It takes a later commit of the plugin’s main by itself when the check of that commit succeeds.'), meta);
      return li;
    };
    // A run of the test rules that matched more files than one day's cap: it filed none. One line, the counts.
    const testRuleRow = (x) => {
      const li = h('li', 'row');
      const head = h('div', 'row-main');
      head.append(h('span', 'title', `The test rules matched ${x.matched} test files in one run, more than the ${x.cap} a day. Conveyor filed none of them.`), ctx.chip('Nothing filed', 'warn'));
      const meta = h('p', 'row-meta');
      meta.append(h('span', null, x.repo), ctx.since(x.time, ' ago'));
      li.append(head, h('p', 'hint', 'See them with conveyor.sh testrules preview. Then change the rules, or raise perDay with conveyor.sh testrules guard perDay.'), meta);
      return li;
    };
    // An issue whose section names a change, waiting for the yes before it is built: the section as written.
    const beforeRow = (x) => {
      const li = h('li', 'row');
      const head = h('div', 'row-main');
      head.append(ctx.issueLink(x), h('span', 'title', x.title || 'untitled'), ctx.chip('Approve before build', 'warn'));
      const meta = h('p', 'row-meta');
      meta.append(ctx.tag(x.repo), ctx.since(x.since, ' ago'));
      const text = typeof x.section === 'string' && x.section.trim() ? x.section : 'the Board could not read the section';
      li.append(head, h('p', 'reason', 'What customers or staff will see, as the issue says:'), h('pre', 'seen', text), meta, yesActions(x, true));
      return li;
    };
    // A follow-up that changes a pipeline file, held until the owner releases it: what its fix costs every card.
    const pipelineRow = (x) => {
      const li = h('li', 'row');
      const head = h('div', 'row-main');
      head.append(ctx.issueLink(x), h('span', 'title', x.title || 'untitled'), ctx.chip('Pipeline change: held', 'warn'));
      const meta = h('p', 'row-meta');
      meta.append(ctx.tag(x.repo), ctx.since(x.since, ' ago'));
      li.append(head, h('p', 'reason', `Cost to every card: ${x.cost || 'not assessed'}`),
        h('p', 'hint', `A follow-up${x.parent ? ` of #${x.parent}` : ''} that changes how Conveyor builds, reviews, fixes, tests, lands or pushes cards. Conveyor does not build it until you choose Queue.`), meta, pipelineActions(x));
      return li;
    };
    // An issue that depends on another repository's issue GitHub would not give: it waits, as if that one were open.
    const farDepRow = (x) => {
      const li = h('li', 'row');
      const head = h('div', 'row-main');
      head.append(ctx.issueLink(x), h('span', 'title', x.title || 'untitled'), ctx.chip(`Waits on ${x.ref || 'another repository'}`, 'warn'));
      const meta = h('p', 'row-meta');
      meta.append(ctx.tag(x.repo));
      li.append(head, h('pre', 'seen', x.line || 'the Depends on: line was not read'), h('p', 'reason', `GitHub did not give its state: ${x.reason || 'no reason given'}`),
        h('p', 'hint', 'Conveyor does not build this issue until that issue can be read and is closed. Give gh access to that repository, or remove it from the line.'), meta);
      return li;
    };
    function yesActions(c, before = false) {
      const box = h('div', 'yes'), note = h('p', 'answer-note');
      note.setAttribute('aria-live', 'polite');
      const t = `#${c.issue}`;
      const condition = h('input', 'field'), why = h('input', 'field');
      condition.type = 'text'; condition.maxLength = 300; condition.placeholder = 'Condition';
      condition.setAttribute('aria-label', `Condition for the yes to ${t}`);
      why.type = 'text'; why.maxLength = 300; why.placeholder = 'Why not';
      why.setAttribute('aria-label', `Why not, for ${t}`);
      // A condition or a reason typed and not yet sent is kept through a reload of the page, by the entry (as keyOf);
      // both are forgotten once the build machine takes an answer for the entry (send).
      const entry = before ? `before:${c.repo}#${c.issue}` : `waiting:${c.card}`;
      [['condition', condition], ['why', why]].forEach(([k, f]) => {
        const was = ctx.kept('draft', `${entry}:${k}`);
        if (typeof was === 'string') f.value = was;
        f.addEventListener('input', () => ctx.keep('draft', `${entry}:${k}`, f.value));
      });
      const acts = {
        approve: { label: 'Approve', ask: `Click again to approve ${t}`, field: null },
        condition: { label: 'Approve with this condition', ask: `Click again to approve ${t} with this condition`, field: condition },
        decline: { label: 'Decline', ask: `Click again to decline ${t}`, field: why },
      };
      let armed = null, busy = false;
      const buttons = {};
      const draw = () => {
        for (const [k, a] of Object.entries(acts)) {
          const b = buttons[k];
          b.textContent = armed === k ? a.ask : a.label;
          b.setAttribute('aria-pressed', String(armed === k));
          b.toggleAttribute('data-armed', armed === k);
          b.disabled = busy;
        }
        condition.disabled = busy; why.disabled = busy;
      };
      const said = (k) => { const f = acts[k].field; return f ? f.value.replace(/\s+/g, ' ').trim() : ''; };
      const send = (k) => {
        const text = said(k);
        const action = k === 'decline' ? 'decline' : 'approve';
        const args = [String(c.issue)].concat(text ? [text] : []);
        busy = true; armed = null; draw();
        note.textContent = 'Sending…';
        // The card's repository goes with its number: Needs you lists the cards of every record, and the host
        // acts on that record's issue, never main's issue of the same number.
        ctx.post('control', { action, args, repo: c.repo })
          // A reply whose body cannot be read is still the host's answer: its status says what happened.
          .then((r) => r.text().then((x) => String(x).trim(), () => '').then((x) => ({ ok: r.ok, said: x || `the build machine answered ${r.status}` })), () => ({ ok: false, said: 'the build machine did not answer. Make sure that it is on. Then try again' }))
          .then((r) => {
            const li = box.closest('li');
            if (!r.ok) { if (li) li.classList.remove('is-pending'); busy = false; draw(); note.textContent = `Not done: ${r.said}`; return; }
            // Taken: the entry is greyed in place and its buttons and fields go, until it leaves the panel.
            if (li) li.classList.add('is-pending');
            ctx.keep('draft', `${entry}:condition`, ''); ctx.keep('draft', `${entry}:why`, '');
            box.querySelectorAll('.answer').forEach((a) => { a.hidden = true; });
            // The build machine's reply is shown only when the action failed (above).
            const wait = `${t} leaves Needs you in about a minute`;
            if (before) {
              note.textContent = action === 'approve'
                ? `Approved${text ? ' with the condition' : ''}: ${wait}, and Conveyor builds it in its turn.`
                : `Declined${text ? ': your reason is on the issue' : ''}. ${wait}. It stays held, and Conveyor does not build it. To build it, queue it on the Board.`;
              return;
            }
            note.textContent = action === 'approve'
              ? `Approved${text ? ' with the condition' : ''}: ${wait} and returns to the belt.`
              : `Declined${text ? ': your reason is on the issue' : ''}. ${wait}. It stays off the belt, and Conveyor keeps its patch. To build it, queue it on the Board.`;
          });
      };
      const press = (k) => {
        if (busy) return;
        if (typeof c.repo !== 'string' || !c.repo) { note.textContent = `Not sent: the Board does not know which repository ${t} is in.`; return; }
        if (acts[k].field && !said(k)) {
          note.textContent = k === 'decline' ? 'Say why first.' : 'Type the condition first.';
          acts[k].field.focus();
          return;
        }
        if (armed !== k) {
          armed = k; draw();
          const then = before
            ? (k === 'decline' ? 'the reason goes on the issue, and the issue stays held' : 'the approval goes on the issue, and Conveyor builds the issue in its turn')
            : (k === 'decline' ? 'the reason goes on the issue and the card stays held' : 'the approval goes on the issue and the card resumes from its kept patch');
          note.textContent = `${acts[k].ask}: ${then}.`;
          return;
        }
        send(k);
      };
      for (const k of Object.keys(acts)) {
        const b = h('button', k === 'approve' ? 'btn btn-primary' : 'btn');
        b.type = 'button';
        b.dataset.act = k;
        b.addEventListener('click', () => press(k));
        buttons[k] = b;
      }
      condition.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); press('condition'); } });
      why.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); press('decline'); } });
      // A change of the text asks again before it sends.
      condition.addEventListener('input', () => { if (armed === 'condition') { armed = null; draw(); } });
      why.addEventListener('input', () => { if (armed === 'decline') { armed = null; draw(); } });
      draw();
      const one = h('div', 'answer'), two = h('div', 'answer'), three = h('div', 'answer');
      one.append(buttons.approve);
      two.append(condition, buttons.condition);
      three.append(why, buttons.decline);
      if (!before) box.append(filesOf(c));
      box.append(one, two, three, note);
      return box;
    }
    // The name under which an answer typed and not yet sent is kept through a reload: its decision's. send forgets
    // it once the build machine takes the answer.
    const draftOf = (x) => `${x.repo}:${x.id}@${x.askedAt}`;
    const send = (x, text, note) => {
      if (!text) { note.textContent = 'Type an answer first, or pick one.'; return; }
      note.textContent = 'Sending…';
      // The record names the ledger the answer goes to: the server finds its path in the host file.
      ctx.post('answer', { id: x.id, answer: text, askedAt: x.askedAt, repo: x.repo })
        .then((r) => r.text().then((t) => {
          const said = String(t).trim() || `the build machine answered ${r.status}`;
          // A 5xx reply already says what was recorded; it is shown as the host wrote it.
          // The build machine's reply is shown only when the answer was not recorded.
          if (r.ok) { ctx.keep('draft', draftOf(x), ''); return 'Answered: it leaves Needs you in about a minute.'; }
          return r.status >= 500 ? said : `Not recorded: ${said}`;
        }), () => 'Not recorded: the build machine did not answer. Make sure that it is on. Then try again.')
        .then((msg) => { note.textContent = msg; });
    };
    const decisionRow = (x) => {
      const li = h('li', 'row');
      const head = h('div', 'row-main');
      head.append(h('span', 'title', x.question), ctx.chip('Decision', 'info'));
      const meta = h('p', 'row-meta');
      // Each decision names its project: the Board reads the ledger of every record that names one.
      if (x.repo) meta.append(ctx.tag(x.repo));
      meta.append(h('span', null, x.id), ctx.since(x.askedAt, ' ago'));
      const form = h('div', 'answer'), note = h('p', 'answer-note');
      note.setAttribute('aria-live', 'polite');
      const field = h('input', 'field');
      field.type = 'text'; field.maxLength = 500; field.placeholder = x.proposedDefault || 'Your answer';
      field.setAttribute('aria-label', `Answer to ${x.id}`);
      // The answer typed and not yet sent is kept through a reload of the page, by the decision.
      const draft = draftOf(x), was = ctx.kept('draft', draft);
      if (typeof was === 'string') field.value = was;
      field.addEventListener('input', () => ctx.keep('draft', draft, field.value));
      let options = Array.isArray(x.options) ? x.options : [];
      if (!options.length && x.proposedDefault) options = [x.proposedDefault];
      options.forEach((o) => {
        const b = h('button', 'btn', o === x.proposedDefault ? `${o} (default)` : o);
        b.type = 'button';
        b.addEventListener('click', () => send(x, o, note));
        form.append(b);
      });
      const typed = h('button', 'btn btn-primary', 'Answer');
      typed.type = 'button';
      typed.addEventListener('click', () => send(x, field.value.trim(), note));
      field.addEventListener('keydown', (e) => { if (e.key === 'Enter') send(x, field.value.trim(), note); });
      form.append(field, typed);
      li.append(head, meta, form, note);
      return li;
    };
    // A blocked card's output, drawn at each refresh: a longer one replaces it, and "Show output" opened stays open.
    // Its findings' places open the lines its last review kept (the time of that review's record).
    const outputOf = (li, c) => {
      const rv = c.track && Array.isArray(c.track.records) ? c.track.records.filter((s) => s && /^review \d/.test(s.name)).pop() : null;
      const was = li.querySelector(':scope > details.output'), out = ctx.output(c.tail, c.card, null, was, ctx.text.repoOf(c), c.repo, rv ? rv.at : null);
      if (was) was.remove();
      if (out) li.insertBefore(out, li.querySelector(':scope > .row-meta'));
    };
    // An entry of a kind with no row of its own: its issue, title, reason, project and age, as the snapshot gives them.
    const entryRow = (x) => {
      const li = h('li', 'row');
      const head = h('div', 'row-main');
      if (Number.isInteger(x.issue) && x.issue > 0) head.append(ctx.issueLink(x));
      head.append(h('span', 'title', typeof x.title === 'string' && x.title ? x.title : 'untitled'));
      const meta = h('p', 'row-meta');
      meta.append(ctx.tag(x.repo));
      if (x.since) meta.append(ctx.since(x.since, ' ago'));
      li.append(head);
      if (typeof x.reason === 'string' && x.reason) li.append(h('p', 'reason', x.reason));
      li.append(meta);
      return li;
    };
    const make = { tests: testsRow, engines: engineRow, testRules: testRuleRow, before: beforeRow, pipeline: pipelineRow, farDeps: farDepRow, waiting: cardRow('waiting'), blocked: cardRow('blocked'), decisions: decisionRow };
    for (const key of Object.keys(items)) if (!Object.hasOwn(make, key)) make[key] = entryRow;
    for (const key of Object.keys(items)) {
      const g = el.querySelector(`[data-group="${key}"]`), warn = g.querySelector('.warn-note');
      warn.textContent = errors[key] || '';
      warn.hidden = !errors[key];
      ctx.tip(warn, errors[key] ? ctx.details(why[key]) : '');
      // The cards not read: their text names the restart, so it is next to it, kept through a redraw while they stay
      // unread (it shows what the host answered).
      const restart = g.querySelector(':scope > .restart-here');
      if (key === 'waiting' && errors.waiting) { if (!restart) warn.after(ctx.restartButton()); } else if (restart) restart.remove();
      g.hidden = items[key].length === 0 && !errors[key];
      // A new item draws the eye once: the mark goes with the next change of this panel's data.
      const show = (xs) => ctx.list(g.querySelector('.rows'), xs, keyOf[key], make[key], (li, x) => {
        li.classList.toggle('is-new', isNew.has(keyOf[key](x)));
        if (key === 'blocked') outputOf(li, x);
        if (key === 'waiting') shotsIn(li, x);
      });
      if (key !== 'blocked') { show(items[key]); continue; }
      // The blocked cards, newest first (sorted by project, the newest first in each project), five at a time.
      const apart = ctx.sorted();
      const newest = items.blocked.slice().sort((a, b) => (apart && a.repo !== b.repo ? (a.repo < b.repo ? -1 : 1) : String(b.since || '').localeCompare(String(a.since || ''))));
      const more = ctx.more('blocked', newest, show), old = g.querySelector('.show-more');
      if (old) old.replaceWith(more); else g.append(more);
    }
  },
});
