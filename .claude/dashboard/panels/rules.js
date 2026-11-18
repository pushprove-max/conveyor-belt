// SPDX-License-Identifier: Apache-2.0
// The Rules tab (the owner chose R1's rules and their effect with R3's held issues grouped by
// area). It is a tab of its own, after Overview and Control, and carries the count
// of a paused loop, since the pause setting is here. Its one part is drawn as five panels (PANELS): Rules, What these
// rules produce, Model prices, the held issues and Open issues.
// Rules: first, one line, where the Machine section was: "Test limits are on the Tests page." (Load limit moved there, #520).
// Then one row a rule, each with what it does and its control: Build (P0, P1, P2, P3, Follow-ups), Never build (the
// labels, each removable, and a field to add one, with the area labels of the open issues to pick from), At once, Pause
// at (Off, 90%, 95%, 98%, beside the weekly limit's
// reading), Builder and Reviewer (CLI, model and effort), Judge (on or off, CLI, model and effort, the finding kinds it always
// accepts, with the kinds the review prompt names to pick from), New issues start in (Queue or Held), Dependency guard
// (On or Off; drawn disabled, "needs a newer engine", for a project whose control record has no depGuard), Push when a
// card lands (On or Off; disabled the same way for a record with no rules.push), Visible changes need your yes (On or
// Off; disabled the same way for a record with no rules.visible), Whole suite in a card (On or Off; disabled the same
// way for a record with no rules.wholeSuite), Card work yields to you (On or Off, the machine's
// steer, sent as POST /machine; disabled the same way when the snapshot does not say it), Cores kept for you (shown,
// not set here: the machine's reserveCores, the cores it keeps and the test slots left, or why the machine cannot keep
// cores), one row a standing kind of
// routine yes the Foreman takes without asking (the pack's auto.standing: Fix you asked for, Review follow-up, Release
// check, Fixed block, each On or Off; disabled the same way for a snapshot with no standing), Held by you (the count, a
// link to the list below)
// and, when there is one, the pinned order with Move up (not on the first), Move down (not on the last) and Unpin.
// A switch's words under its name say what it does, whichever choice is set; what Off means shows beside it only
// while Off is set. Push landed and Run full test suite are actions, not rules: they are on the Board (Control tab).
// No issue is listed among the rules. A change is saved at once (a Builder, Reviewer or Judge CLI, model and effort
// when its Save is pressed: modelCtl); the head says so and shows the last change made here for this project, with
// Undo, which sends the setting's value from before it. A setting changed here shows its
// new value while it is out, and the record the host answers with until a snapshot begun at or after the answer that
// no longer holds the old value; a refused one shows the old value again, with the refusal in its row. Turning a
// Build choice off, or a Never build label about to be added, says first how many queued issues it would skip; a
// Build choice that would skip any takes a second click, its button naming the count, and so does an Undo (the head's
// or the line's) that would turn one off.
// What these rules produce, read from the snapshot alone: four counts (ready to build, waiting on another card, held by you, skipped by a
// rule; waiting counts and opens the list of the waiting cards, held or skipped ones too, each with the issues it
// waits on and where each is, what else holds or skips it, and, on one nothing else keeps, with the
// dependency guard Off a "Queue anyway" that acts on a second click, sending force; each row removes a dependency (×) or adds
// one, sending depends), Next up (the next five in pick order, each
// ready or "waits on #N"), the queue's dollar forecast as one line,
// the guard's warning when the forecast says it pauses the loop before the queue ends, and the skipped issues.
// Model prices: the built-in prices and the pack's prices, added models and aliases, grouped, searched and each
// changed in its row here (pricesSection). Held by you or a label: the issues held by you (the control record) or by a label (awaiting-deploy),
// one line a group (by area by default, or by priority or holding label): its name, count and how
// many a label holds. Groups start closed, largest first; one opens to five issues, then "Show 5 more"
// and "Show all (M)" (the page's shared long list). Queue releases an issue the record holds; on one a label holds it removes the label
// and queues it, as the Board's "Remove the label and queue it", after saying so with a first click. Queue
// all asks once, naming the count and how many a label holds, and leaves those out unless asked. A row these, Hold or
// their Undo move shows as moved until a snapshot made after the change shows it (moveJudge). A search by number
// or title opens the groups with matches. Every change is POST control; the record the host answers with shows at
// once, and What these rules produce waits for the next snapshot: this file never computes the queue.
// The guard rule, as everywhere on the Board: a change easily undone (a switch, a cap, a pin, Queue, Hold) acts on one
// click and the line that says it was done has Undo; one that costs money or time (Retry, Queue all, Queue anyway) or
// cannot be undone (removing a label) acts on a second click, as does a Build choice that would skip queued issues.
// No browser dialog.
// Open issues: every open issue of the project, each with its state, filtered, sorted, picked and managed (issuesSection).
// With more than one project on the host the machine head's Show picks the one shown, as on the Board, and the
// Rules panel's heading names it ("Rules: sample"); every change names it.
// Its part (dashboard.sh, rules): {repo (null: no record is on the host's main), state, control, cap, guard,
// modelSettings, areaPrefix, limit, held, queue (each with areas), skipped, waits, issuesError, building, onBelt, beltSteps,
// blocked, forecast, prices, standing, open (with issues: every open issue), repos, others}.
(function () {
  'use strict';
  const AREA = /^[A-Za-z0-9._/-]{1,60}$/;  // the name after the pack's area prefix, as dashboard_server.py's RULE takes it
  const KIND = /^[A-Za-z0-9][A-Za-z0-9_-]{0,39}$/;  // a finding kind the judge always accepts, as dashboard_server.py's KIND takes it
  const MODEL = /^[A-Za-z0-9][A-Za-z0-9._:/@[\]-]{0,191}$/;  // a role's model, as dashboard_server.py's MODEL takes it
  const KINDS_MAX = 20;   // the kinds one `judge always` takes (dashboard_server.py)
  const RELEASE_MAX = 50; // the issues one release takes (dashboard_server.py)
  const DEPENDS_MAX = 20; // the issues one depends takes (dashboard_server.py)
  // The standing kinds of routine yes (the pack's auto.standing, conveyor/lib/standing.sh): key, name, what it does.
  const STANDING = [
    ['asked-fix', 'Fix you asked for', 'the Foreman files the fix you ask for and queues it at once'],
    ['review-followup', 'Review follow-up', 'a follow-up that only finishes or corrects a card you approved is queued'],
    ['release-check', 'Release check', 'a failed check in a release you asked for gets one fix card, then the release goes on'],
    ['fixed-block', 'Fixed block', 'a card blocked by a cause that a landed fix removed waits on that fix and is tried again'],
  ];
  const ORDER_MAX = 500;  // the issues one order takes (dashboard_server.py)
  const ARM_MS = 5000;    // a Queue that removes a label, or a Build choice that skips queued issues, waits this long for its second click
  // The finding kinds offered to pick from: those the review prompt names (its P0 level: security, data; its three
  // angles: bypass, behaviour, tests). Any other word KIND takes can still be typed.
  const KNOWN_KINDS = ['security', 'data', 'bypass', 'behaviour', 'tests'];
  const GUARDS = [90, 95, 98];
  const BUILDS = [['P0', 'P0'], ['P1', 'P1'], ['P2', 'P2'], ['P3', 'P3'], ['followups', 'Follow-ups']];  // the Build choices: key, name
  const LAST_KEY = 'conveyor-board-rules-last';  // the last change made here, in this browser
  const DRAFT_KEY = 'conveyor-board-rules-drafts';  // the roles picked here and not yet saved, by project, in this browser
  const ROLES = ['builder', 'reviewer', 'judge'];
  const OTHER = '*other';  // the model list's Other…: a name it does not list, typed in (no model starts with *: MODEL)
  const BY = [['area', 'Area'], ['priority', 'Priority'], ['label', 'Label']];
  // The part, and the ids of the tab's panels drawn from it (PANELS): Rules is the part's own id.
  const PART = 'rules', HELD_P = `${PART}-held`;
  const S = { d: null, ctl: null, ctlAt: null, was: {}, guessed: false, floor: null, read: null, turned: false, refused: null,
    kept: new Map(), at: new Map(), from: PART, heard: new WeakSet(), raw: null, ctx: null, busy: false, area: '', kind: '', keep: null, search: '', by: 'area',
    open: new Set(), armed: null, unarm: null, asking: null, withLabels: false, moved: new Map(), picked: new Set(), waitsOpen: false, dep: null, depText: '',
    drafts: null, priceEdit: null, priceAdd: null, priceFind: '', priceSaved: null, priceThis: new Map(), priceOpen: new Set(),
    steer: null, steerSent: null, cores: null, bare: null, bareFor: null, idle: null, shown: new Map() };
  // steer: the machine's Card work yields to you as the snapshot says (null: an engine that does not say); steerSent:
  // the value the host took from here, shown until a snapshot says it. cores: the machine's cores kept for the user as
  // the snapshot says ({reserved, slots, unavailable}; null: an engine that does not say).
  // drafts: each project's roles picked here and not yet saved (draftOf), as DRAFT_KEY keeps them. Model prices
  // (pricesSection): priceEdit, the row open in Edit as typed; priceAdd, the Add model form as typed; priceFind, the
  // search typed; priceSaved, the pack's prices as the changes saved here left them, until the next snapshot;
  // priceThis, the model picked for each ID's This is…; priceOpen, the folded groups opened.

  const num = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : null);
  const list = (v) => (Array.isArray(v) ? v : []);
  const ctl = () => S.ctl || (S.d.control && typeof S.d.control === 'object' ? S.d.control : null);
  const same = (a, b) => JSON.stringify(a === undefined ? null : a) === JSON.stringify(b === undefined ? null : b);
  const plural = (k, one, many) => `${k} ${k === 1 ? one : many}`;
  const prio = (x) => (/^P[0-3]$/.test(x && x.priority) ? x.priority : 'P3');
  // The pack's area prefix, as the snapshot gives it; null from one without it: then no area is read or sent.
  const pre = () => (typeof S.d.areaPrefix === 'string' && S.d.areaPrefix ? S.d.areaPrefix : null);
  const isArea = (k) => typeof k === 'string' && pre() !== null && k.startsWith(pre());
  // An area label's name: the prefix cut off, then the colon or slash after it, which a prefix such as "area" does
  // not hold (prefix "area", label "area:web": "web").
  const areaName = (k) => k.slice(pre().length).replace(/^[:/]/, '');
  // Whether the project's engine knows the dependency guard and `control force`: its control record names depGuard
  // (the engine fills in every field it knows). An older pinned engine is never sent either.
  const depKnown = () => { const c = ctl(); return !!c && typeof c.depGuard === 'boolean'; };
  // The rule that skips an issue, in words.
  function why(rule) {
    if (rule === 'follow-ups') return 'follow-ups are off';
    if (/^P[0-3]$/.test(rule)) return `${rule} is off`;
    if (isArea(rule)) return `Conveyor never builds ${rule}`;
    return String(rule || 'a rule');
  }

  // ---- the last change made here: what, when, the project, and the steps that undo it (null: none) ----
  const isStep = (u) => Array.isArray(u) && u.length === 2 && typeof u[0] === 'string' && Array.isArray(u[1]) && u[1].every((x) => typeof x === 'string');
  const isUndo = (u) => Array.isArray(u) && u.length > 0 && u.every(isStep);
  function lastRead() {
    try {
      const v = JSON.parse(window.localStorage.getItem(LAST_KEY));
      return v && typeof v.what === 'string' && typeof v.at === 'string' && typeof v.repo === 'string' ? Object.assign({}, v, { undo: isUndo(v.undo) ? v.undo : null }) : null;
    } catch (e) { return null; }
  }
  function lastWrite(what, undo, repo) {
    try { window.localStorage.setItem(LAST_KEY, JSON.stringify({ what, at: new Date(Date.now()).toISOString(), repo, undo })); } catch (e) { /* it then shows for no later visit */ }
  }
  // The change that puts a setting back as the record c held it before the change [action, args]; null for an action
  // that is not one setting (release, order, unpin...) or a role the record names by its model alone.
  function undoOf(c, action, a) {
    if (!c) return null;
    const r = c.rules && typeof c.rules === 'object' ? c.rules : {};
    if (action === 'rules') {
      return ['rules', a.map((x) => { const k = String(x).split('=')[0]; return `${k}=${isArea(k) ? (list(r.never).includes(k) ? 'off' : 'on') : r[k] === false ? 'off' : 'on'}`; })];
    }
    if (action === 'cap' || action === 'guard') return [action, [num(c[action]) === null ? 'off' : String(c[action])]];
    if (action === 'judge' && (a[0] === 'on' || a[0] === 'off')) return ['judge', [c.judgeOn === true ? 'on' : 'off']];
    if (action === 'judge' && a[0] === 'always') return ['judge', ['always'].concat(list(c.judgeAlways).filter((k) => typeof k === 'string'))];
    if (action === 'model' || action === 'reviewer' || action === 'judge') {
      const s = c[action] && typeof c[action] === 'object' ? c[action] : null;
      if (!s) return [action, ['default']];
      return typeof s.cli === 'string' && typeof s.model === 'string' ? [action, [s.cli, s.model].concat(typeof s.effort === 'string' && s.effort ? [s.effort] : [])] : null;
    }
    if (action === 'account') return ['account', typeof c.account === 'string' && c.account ? [c.account] : []];
    if (action === 'review-account') return ['review-account', typeof c.reviewAccount === 'string' && c.reviewAccount ? [c.reviewAccount] : []];
    if (action === 'start') return ['start', [c.start === 'held' ? 'held' : 'queue']];
    if (action === 'dep-guard') return ['dep-guard', [c.depGuard === false ? 'off' : 'on']];
    return null;
  }
  // ---- the roles picked here and not yet saved ----
  // By project, then role: {cli, model, effort, other: Other… picked}. Kept in this browser, so leaving the tab or a
  // reload loses none and sends none; one that does not read is dropped.
  function drafts() {
    if (S.drafts) return S.drafts;
    let all = null;
    try { all = JSON.parse(window.localStorage.getItem(DRAFT_KEY)); } catch (e) { all = null; }
    S.drafts = {};
    if (all && typeof all === 'object' && !Array.isArray(all)) {
      Object.keys(all).forEach((repo) => {
        const one = all[repo] && typeof all[repo] === 'object' ? all[repo] : {};
        ROLES.forEach((k) => {
          const d = one[k];
          if (d && typeof d === 'object' && ['cli', 'model', 'effort'].every((f) => typeof d[f] === 'string')) {
            (S.drafts[repo] = S.drafts[repo] || {})[k] = { cli: d.cli, model: d.model, effort: d.effort, other: d.other === true };
          }
        });
      });
    }
    return S.drafts;
  }
  function draftsKeep() {
    try { window.localStorage.setItem(DRAFT_KEY, JSON.stringify(S.drafts)); } catch (e) { /* kept for this visit alone */ }
  }
  const draftOf = (key) => { const one = drafts()[S.d.repo]; return one && one[key] ? one[key] : null; };
  const draftPut = (key, d) => { const all = drafts(); (all[S.d.repo] = all[S.d.repo] || {})[key] = d; draftsKeep(); };
  const draftDrop = (key, repo = S.d.repo) => {
    const all = drafts(), one = all[repo];
    if (!one || !one[key]) return;
    delete one[key];
    if (!Object.keys(one).length) delete all[repo];
    draftsKeep();
  };

  // ---- the issues an action here moved (Queue, Queue all, Hold, a label removed, and their Undo) ----
  // By project and issue: {repo, issue, action ('release', 'hold' or 'unlabel'), labels (those unlabel removes), out (sent,
  // not answered yet), at (when the host answered, as post gives it; null: no time), error (why it did not move, in words)}.
  // A moved row shows as moved until a snapshot begun at or after the answer (with no time, the next one) shows the move;
  // an older snapshot does not bring it back. That first snapshot does not show the move, or the host refused it: the row
  // comes back with the error beside it, until a snapshot shows the move or it is moved again.
  const MOVES = { release: 'Not queued', hold: 'Not held', unlabel: 'Label not removed' };  // the start of each error
  const moveOf = (n) => S.moved.get(`${S.d.repo}#${n}`) || null;
  const pendingMove = (n) => { const m = moveOf(n); return m && !m.error ? m : null; };
  function moveMark(repo, action, args, o) {
    const a = list(args);
    (action === 'unlabel' ? a.slice(0, 1) : a).forEach((n) => S.moved.set(`${repo}#${Number(n)}`,
      Object.assign({ repo, issue: Number(n), action, labels: action === 'unlabel' ? a.slice(1) : [], out: false, at: null, rec: null, error: null }, o)));
  }
  // Why a snapshot begun after the host's answer does not show the move m. A release the host answered with a record
  // (rec) took: the host refuses one that does not, with its reason (post), so a later hold holds the issue again.
  function moveWhy(m) {
    if (m.action === 'release' && m.rec) {
      return 'the host released it, but a later hold holds it again (Hold on the Board or the command line, or a follow-up filed as held).';
    }
    return `the first update after the change still shows it ${m.action === 'hold' ? 'not held' : m.action === 'unlabel' ? 'with the label' : 'held'}.`;
  }
  // Whether the snapshot view shows the move m.
  function moveShown(view, m) {
    const rows = list(view.open && view.open.held).concat(list(view.held).map((x) => Object.assign({ reasons: [{ kind: 'you' }] }, x))).filter((x) => x && x.issue === m.issue);
    if (m.action === 'unlabel') return !rows.some((x) => list(x.reasons).some((r) => r && r.kind === 'label' && m.labels.includes(r.label)));
    const c = view.control && typeof view.control === 'object' ? view.control : null;
    const mine = c ? list(c.held).includes(m.issue) : rows.some((x) => list(x.reasons).some((r) => r && r.kind === 'you'));
    return m.action === 'hold' ? mine : !mine;
  }
  // When the snapshot of the project view began (ms), or null: the record's readAt, as the live feed's snapshot of it can
  // have begun before a change while the data around it is dated after (issue 288); else when the collector began.
  function readOf(view, ctx) {
    const at = view && typeof view.readAt === 'string' ? Date.parse(view.readAt) : NaN;
    if (Number.isFinite(at)) return at;
    return typeof ctx.updatedAt === 'function' ? ctx.updatedAt() : null;
  }
  // A new snapshot of the project view, begun at read: each move it is new enough to show is done, or failed.
  function moveJudge(view, read) {
    S.moved.forEach((m, k) => {
      if (m.repo !== view.repo || m.out) return;
      const shown = moveShown(view, m);
      if (m.error) { if (shown) S.moved.delete(k); return; }
      if (m.at !== null && (read === null || read < m.at)) return;
      if (shown) S.moved.delete(k);
      else m.error = `${MOVES[m.action]}: ${moveWhy(m)}`;
    });
  }
  // The words beside a moved row: while it waits for a snapshot, and when it failed.
  const moveNote = (m) => (m.error ? S.ctx.h('span', 'rules-refused', m.error)
    : S.ctx.h('span', 'board-from board-sent', m.action === 'unlabel' ? 'Label removed: it goes into the queue in about a minute.'
      : `${m.action === 'hold' ? 'Held' : 'Queued'}: this shows in about a minute.`));

  // A change in words, for the head.
  function words(action, args) {
    const a = list(args);
    if (action === 'rules') return a.map((x) => { const [k, o] = x.split('='); return isArea(k) ? `${o === 'off' ? 'never build' : 'build'} ${k}` : `${k === 'followups' ? 'Follow-ups' : k === 'push' ? 'Push when a card lands' : k === 'visible' ? 'Visible changes need your yes' : k === 'wholeSuite' ? 'Whole suite in a card' : k} ${o}`; }).join(', ');
    if (action === 'cap') return a[0] === 'off' ? 'at once: the default' : `at once ${a[0]}`;
    if (action === 'guard') return a[0] === 'off' ? 'pause at: off' : `pause at ${a[0]}%`;
    if (action === 'model' || action === 'reviewer') return `${action === 'model' ? 'builder' : 'reviewer'} ${a[0] === 'default' ? 'back to the default' : a.join(' ')}`;
    if (action === 'judge' && (a[0] === 'on' || a[0] === 'off')) return `judge ${a[0]}`;
    if (action === 'judge' && a[0] === 'always') return a.length > 1 ? `judge always accepts ${a.slice(1).join(', ')}` : 'judge always accepts no kind';
    if (action === 'judge') return `judge ${a[0] === 'default' ? 'back to the default' : a.join(' ')}`;
    if (action === 'account' || action === 'review-account') return `${action === 'account' ? 'account' : 'review account'} ${a.length ? a[0] : 'back to the default'}`;
    if (action === 'release') return a.length === 1 ? `queued #${a[0]}` : `queued ${a.length} issues`;
    if (action === 'unlabel') return `removed ${a.slice(1).join(', ')} from #${a[0]} and queued it`;
    if (action === 'unpin') return `unpinned #${a[0]}`;
    if (action === 'order') return a.length ? `pinned order ${a.map((n) => `#${n}`).join(', ')}` : 'no pinned order';
    if (action === 'start') return `new issues start in ${a[0] === 'held' ? 'Held' : 'the Queue'}`;
    if (action === 'dep-guard') return `dependency guard ${a[0]}`;
    if (action === 'force') return `build #${a[0]} before the issues it waits on land`;
    if (action === 'depends') return `#${a[0]} ${a[1] === 'add' ? 'depends on' : 'no longer depends on'} ${a.slice(2).map((n) => `#${n}`).join(', ')}`;
    if (action === 'prices') return priceWords(a);
    if (action === 'standing') return `${(STANDING.find(([k]) => k === a[0]) || [a[0], a[0]])[1]} without asking: ${a[1]}`;
    return action;
  }

  // A setting as the record would hold it once the host takes it, and the row it is in; null for an action that is
  // not one setting (release, order, unpin...): those show when the host answers.
  function guessed(c, action, a) {
    const r = JSON.parse(JSON.stringify(c)), k = a.length ? String(a[0]).split('=')[0] : '';
    if (action === 'rules') {
      r.rules = r.rules && typeof r.rules === 'object' ? r.rules : {};
      a.forEach((x) => {
        const [key, o] = String(x).split('=');
        if (!isArea(key)) { r.rules[key] = o === 'on'; return; }
        const never = list(r.rules.never).filter((y) => y !== key);
        r.rules.never = o === 'off' ? never.concat([key]) : never;
      });
      return [r, isArea(k) ? 'never' : k === 'push' || k === 'visible' || k === 'wholeSuite' ? k : 'build'];
    }
    if (action === 'cap' || action === 'guard') { r[action] = a[0] === 'off' ? null : Number(a[0]); return [r, action]; }
    if (action === 'judge' && (a[0] === 'on' || a[0] === 'off')) { r.judgeOn = a[0] === 'on'; return [r, 'judge']; }
    if (action === 'judge' && a[0] === 'always') { r.judgeAlways = a.slice(1); return [r, 'judge']; }
    if (action === 'model' || action === 'reviewer' || action === 'judge') {
      r[action] = a[0] === 'default' ? null : Object.assign({ cli: a[0], model: a[1] }, a[2] ? { effort: a[2] } : {});
      return [r, action === 'model' ? 'builder' : action];
    }
    if (action === 'account') { r.account = a[0] || null; return [r, 'account']; }
    if (action === 'review-account') { r.reviewAccount = a[0] || null; return [r, 'review-account']; }
    if (action === 'start') { r.start = a[0]; return [r, 'start']; }
    if (action === 'dep-guard') { r.depGuard = a[0] === 'on'; return [r, 'dep-guard']; }
    return null;
  }

  // The tab's line: what was asked or done, with Undo after a change easily undone (undo sends its opposite). Each of
  // the tab's panels (PANELS) has its own: the line shows in the panel the action came from (where, by default S.from:
  // the panel last clicked or typed in), so a panel folded away never holds what another panel's action said, and
  // the other panels' lines are emptied.
  const tabLine = (where = S.from) => (S.at.has(where) ? S.at.get(where).el.querySelector('.rules-note') : null);
  function say(text, undo, where = S.from) {
    S.at.forEach(({ el }, id) => { const n = el.querySelector('.rules-note'); if (n && id !== where) n.replaceChildren(); });
    const n = tabLine(where);
    if (n) n.replaceChildren(undo ? S.ctx.undoLine(text, undo) : text);
  }
  // One action to the page's host, for the project named: {ok, said, rec, at}. at: when the page's host had the
  // answer (X-Answered-At: its clock, in whole seconds rounded up), in ms, or null.
  function post(action, args, repo) {
    return S.ctx.post('control', { action, args, repo }).then((r) => r.text().then((t) => {
      const said = String(t).trim();
      let rec = null;
      try { rec = JSON.parse(said); } catch (e) { rec = null; }
      const at = Number(r.headers && typeof r.headers.get === 'function' ? r.headers.get('X-Answered-At') : NaN);
      return { ok: r.ok, said: said || `the host answered ${r.status}`, rec: rec && typeof rec === 'object' && typeof rec.mode === 'string' ? rec : null,
        at: Number.isFinite(at) && at > 0 ? at * 1000 : null };
    }));
  }
  // Actions to the page's host, one after another and one batch at a time (as the Board's): while they are out the
  // controls are off. The first one refused stops the rest. what: the change in words, for the head. Every one names
  // the project on screen when they were asked for; an answer that comes after another project was picked is not shown.
  // undo: the steps that undo these, for Undo on the line that says they were done (null: none), kept with them as the
  // last change here. to: the project they are for when it is not the one on screen: an Undo pressed after another
  // project was picked goes to the project the change was made in, never to the one picked since.
  function run(steps, what, done, undo, to) {
    if (S.busy) { say('Wait: the build machine did not answer the last change yet.'); return Promise.resolve(false); }
    // Its answer shows in the panel it was asked from, whatever panel is clicked while it is out.
    const where = S.from, tell = (text, u) => say(text, u, where);
    S.busy = true; S.refused = null; draw();
    tell('Sending…');
    const repo = to || S.d.repo;
    let i = 0;
    const next = () => {
      if (i >= steps.length) return Promise.resolve(true);
      const [action, args] = steps[i];
      i += 1;
      // A setting shows its new value while it is out; refused, or unanswered, the value shown before it comes back and
      // stands until a snapshot begun at or after the refusal (with no time, the next one), not one that arrived while
      // it was out. An answer that comes after another project was picked goes to that project's kept state (render).
      // A value drawn from the snapshot as well as the record (the seed's cap) comes back with the snapshot then shown.
      // Only the project on screen is guessed: ctl() is its record, not another project's.
      const was = { shown: ctl(), at: S.ctlAt, d: S.d }, guess = was.shown && repo === S.d.repo ? guessed(was.shown, action, list(args)) : null;
      if (guess) { S.ctl = guess[0]; S.guessed = true; draw(); }
      const put = (o) => { if (repo === S.d.repo) Object.assign(S, o); else if (S.kept.has(repo)) Object.assign(S.kept.get(repo), o); };
      const back = (text, at) => {
        if (guess && repo === S.d.repo) S.d = was.d;
        put(guess ? { guessed: false, ctl: was.shown, ctlAt: at !== null ? at : was.at, refused: { row: guess[1], text } } : { guessed: false });
      };
      // An issue it moves shows as moved while it is out (moveMark).
      const moves = (o) => { if (MOVES[action]) moveMark(repo, action, args, o); };
      if (MOVES[action]) { moves({ out: true }); draw(); }
      return post(action, args, repo).then((res) => {
        moves(res.ok ? { at: res.at, rec: res.rec } : { error: `${MOVES[action]}: ${S.ctx.refusal(res.said)}` });
        if (!res.ok) { back(res.said, res.at); tell(`Not done: ${S.ctx.refusal(res.said)}${steps.length > 1 ? ` (${i - 1} of ${steps.length} sent)` : ''}`); return false; }
        put({ guessed: false });
        // A model price saved shows at once (pricesSection), its Undo's too.
        if (action === 'prices' && repo === S.d.repo) S.priceSaved = { for: S.d.prices, over: applied(pricesShown(), list(args)) };
        // A standing kind saved shows at once too, until the next snapshot.
        if (action === 'standing' && repo === S.d.repo) {
          const [k, o] = list(args);
          S.standingSaved = { for: S.d.standing, over: list(standingShown()).filter((x) => x !== k).concat(o === 'on' ? [k] : []) };
        }
        // The values the change replaced, kept from before the first change no snapshot has read yet: a snapshot that
        // still holds one did not read it. A setting the record holds at its old value again waits for nothing.
        const at = repo === S.d.repo ? S : S.kept.get(repo), now = res.rec || (guess && guess[0]);
        if (guess && at) {
          new Set(Object.keys(was.shown).concat(Object.keys(guess[0]))).forEach((k) => {
            if (!same(was.shown[k], guess[0][k]) && !same(was.shown[k], now[k]) && !(k in at.was)) at.was[k] = was.shown[k];
          });
          Object.keys(at.was).forEach((k) => { if (same(now[k], at.was[k])) delete at.was[k]; });
        }
        // The host's record, else the guess: it stands until a snapshot begun at or after the answer (render).
        if (res.rec || guess) put(Object.assign(res.rec ? { ctl: res.rec } : {}, { ctlAt: res.rec ? res.at : null }));
        return next();
      }, (e) => { moves({ error: `${MOVES[action]}: the host did not answer.` }); back('the host did not answer', null); throw e; });
    };
    const free = (ok) => { S.busy = false; draw(); return ok; };
    return next().then((ok) => {
      if (ok) {
        lastWrite(what, undo || null, repo);
        if (done && repo === S.d.repo) done();
        tell('Done. What the rules produce updates in about a minute.', undo && undo.length && repo === S.d.repo ? () => undoAsk(undo, () => run(undo, `undid: ${what}`, null, null, repo), repo) : null);
      }
      return free(ok);
    }, () => { tell('Not done: the host did not answer.'); return free(false); });
  }
  // undo: the one [action, args] that undoes this change; without one, it is read from the record shown before it is
  // sent (undoOf).
  const send = (action, args, done, undo) => {
    const u = undo || undoOf(ctl(), action, list(args));
    return run([[action, args]], words(action, args), done, u ? [u] : null);
  };
  // An Undo that would turn a Build choice off asks first, as the switch does: the Build choices steps turn off that
  // would skip queued issues, each [name, count]; none: [].
  function undoSkips(steps) {
    const r = ((ctl() || {}).rules) || {}, out = [];
    steps.forEach(([action, args]) => {
      if (action !== 'rules') return;
      list(args).forEach((x) => {
        const [k, o] = String(x).split('='), b = BUILDS.find(([key]) => key === k), n = b && o === 'off' && r[k] !== false ? wouldSkip(k) : 0;
        if (n > 0) out.push([b[1], n]);
      });
    });
    return out;
  }
  const undoLabel = (skips) => `Undo: skip ${skips.reduce((t, [, k]) => t + k, 0)}`;
  // go sends the undo steps, at once unless they would skip queued issues: then the first click arms it, says what it
  // would skip and gives an Undo naming the count, and only a second within ARM_MS sends. repo, the project the steps
  // go to: what they would skip is read from the project shown, so one meant for another project is not sent.
  function undoAsk(steps, go, repo = S.d.repo) {
    if (repo !== S.d.repo) { say(`Not done: that Undo is for ${repo}; pick it to undo the change there.`); return Promise.resolve(false); }
    const skips = undoSkips(steps), key = `undo:${JSON.stringify(steps)}`;
    if (!skips.length || S.armed === key) { if (skips.length) S.armed = null; return go(); }
    arm(key);
    say(`${skips.map(([name, k]) => skipWords(name, k)).join(' ')} Click Undo again to turn ${skips.map(([name]) => name).join(', ')} off.`, () => undoAsk(steps, go, repo));
    const b = tabLine() && tabLine().querySelector('[data-act="undo"]');
    if (b) { b.textContent = undoLabel(skips); b.classList.add('board-danger'); }
    return Promise.resolve(false);
  }
  // A change that costs money or time ('spend') or cannot be undone ('final') acts on a second click within ARM_MS: the
  // first turns the button to `ask` (its consequence, for a final one). key names it apart from every other.
  function guarded(key, tier, text, ask, act, label, go) {
    const on = S.armed === key;
    const b = button(on ? ask : text, tier === 'final' ? 'btn-final' : 'btn-cost', act, on ? ask : label, () => {
      if (S.armed !== key) { arm(key); return; }
      S.armed = null;
      go();
    });
    b.dataset.guard = tier;
    b.setAttribute('aria-pressed', String(on));
    return b;
  }

  function button(text, cls, act, label, fn) {
    const b = S.ctx.h('button', `btn ${cls || ''}`.trim(), text);
    b.type = 'button'; b.dataset.act = act; b.setAttribute('aria-label', label || text);
    b.addEventListener('click', fn);
    return b;
  }
  function choice(text, act, label, on, fn) {
    const b = button(text, 'rules-tog', act, label, fn);
    b.setAttribute('aria-pressed', String(on));
    return b;
  }
  // The values a field offers to pick from (its list), or null when there is none to offer.
  function pickList(id, values) {
    if (!values.length) return null;
    const dl = S.ctx.h('datalist');
    dl.id = id;
    values.forEach((v) => { const o = S.ctx.h('option'); o.value = v; dl.append(o); });
    return dl;
  }
  function stepper(label, value, onDown, onUp, canDown, canUp) {
    const h = S.ctx.h, box = h('span', 'board-stepper');
    const btn = (glyph, name, fn, ok, act) => {
      const b = h('button', 'tool', glyph);
      b.type = 'button'; b.setAttribute('aria-label', `${name} ${label}`); b.dataset.act = act; b.disabled = !ok;
      b.addEventListener('click', fn);
      return b;
    };
    box.append(btn('−', 'Lower', onDown, canDown, `${label}-down`), h('span', 'board-value', value), btn('+', 'Raise', onUp, canUp, `${label}-up`));
    return box;
  }
  // One rule: its name and what it does, then its control.
  function row(key, name, what, ...kids) {
    const h = S.ctx.h, el = h('div', 'rules-row'), head = h('div', 'rules-key'), ctlBox = h('div', 'rules-ctl');
    el.dataset.rule = key;
    head.append(h('span', 'board-label', name), h('span', 'rules-what', what));
    ctlBox.append(...kids.filter(Boolean));
    if (S.refused && S.refused.row === key) {
      const no = h('p', 'rules-refused', `Not saved: ${S.refused.text}`);
      no.setAttribute('role', 'alert');
      ctlBox.append(no);
    }
    el.append(head, ctlBox);
    return el;
  }

  // ---- what a change would skip, before it is made ----
  const queued = () => list(S.d.queue);
  function wouldSkip(key) {
    return queued().filter((x) => {
      if (key === 'followups') return x.followup === true;
      if (/^P[0-3]$/.test(key)) return x.followup !== true && prio(x) === key;
      return list(x.areas).includes(key);
    }).length;
  }
  const skipWords = (name, k) => `Turning ${name} off would skip ${k} of the ${plural(queued().length, 'queued issue', 'queued issues')}.`;
  // The label the field holds, as it would be sent; null when it is not one.
  const fieldLabel = () => { const v = S.area.trim(), p = pre(); if (!v || p === null) return null; const n = v.startsWith(p) ? v.slice(p.length) : v; return AREA.test(n) ? p + n : null; };
  function areaWould() {
    const a = fieldLabel(), k = a && !list(((ctl() || {}).rules || {}).never).includes(a) ? wouldSkip(a) : 0;
    return k > 0 ? `Never building ${a} would skip ${k} of the ${plural(queued().length, 'queued issue', 'queued issues')}.` : '';
  }

  // ---- the held issues: held by you (the control record) or by a label ----
  // Their name everywhere on this tab: the two of the Board's four "not being built" states they are (the other two,
  // Skipped by a rule and Waiting on another card, are counted apart).
  const HELD = 'Held by you or a label';
  // Each with holds (the labels that hold it), you (the record holds it) and how Queue frees it: release (only you),
  // unlabel (labels, and perhaps you, and nothing else) or null (something else holds it too: not from here).
  function held() {
    const d = S.d, c = ctl();
    const by = new Map();
    list(d.open && d.open.held).forEach((x) => by.set(x.issue, x));
    list(d.held).forEach((x) => { if (!by.has(x.issue)) by.set(x.issue, Object.assign({ reasons: [{ kind: 'you' }] }, x)); });
    const mine = new Set(c ? list(c.held) : Array.from(by.values()).filter((x) => list(x.reasons).some((r) => r && r.kind === 'you')).map((x) => x.issue));
    const out = [];
    by.forEach((x) => {
      const others = list(x.reasons).filter((r) => r && r.kind !== 'you');
      const holds = others.filter((r) => r.kind === 'label' && typeof r.label === 'string').map((r) => r.label);
      const you = mine.has(x.issue);
      // A row moved here stays, shown as moved, until a snapshot shows the move (moveJudge).
      if (!you && !holds.length && !pendingMove(x.issue)) return;
      const rest = others.filter((r) => r.kind !== 'label');
      const how = holds.length ? (rest.length ? null : 'unlabel') : 'release';
      out.push(Object.assign({}, x, { holds, you, how, rest }));
    });
    // Within a group: the higher priority first, then the newer issue.
    return out.sort((a, b) => (prio(a) < prio(b) ? -1 : prio(a) > prio(b) ? 1 : (num(b.issue) || 0) - (num(a.issue) || 0)));
  }
  // GitHub did not list the open issues: what is held is not known (the control record holds only numbers), and is
  // never shown as nothing held.
  const unlisted = () => !Array.isArray(S.d.held) && !(S.d.open && Array.isArray(S.d.open.held));
  function heldUnknown() {
    const c = ctl(), n = c ? list(c.held).length : 0;
    return `Not known: GitHub did not list the open issues${n ? ` (${plural(n, 'issue', 'issues')} held by you)` : ''}.`;
  }
  function groupOf(x) {
    if (S.by === 'priority') return prio(x);
    if (S.by === 'label') return x.holds.slice().sort()[0] || '';
    return list(x.labels).filter(isArea).sort()[0] || '';
  }
  function groupName(key) {
    if (S.by === 'priority') return key;
    if (S.by === 'label') return key || 'No label: held by you';
    return key ? areaName(key) : 'No area';
  }
  function groups(all) {
    const m = new Map();
    all.forEach((x) => { const k = groupOf(x); if (!m.has(k)) m.set(k, []); m.get(k).push(x); });
    return Array.from(m, ([key, items]) => ({ key, name: groupName(key), items }))
      .sort((a, b) => b.items.length - a.items.length || (a.key === '' ? 1 : b.key === '' ? -1 : a.name.localeCompare(b.name)));
  }
  // How many in a list a label holds, label by label: "31 ux-change · 2 backlog".
  function labelMark(items) {
    const m = new Map();
    items.forEach((x) => x.holds.forEach((l) => m.set(l, (m.get(l) || 0) + 1)));
    return Array.from(m).sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0])).map(([l, k]) => `${k} ${l}`).join(' · ');
  }
  function matches(x) {
    const q = S.search.trim().toLowerCase().replace(/^#/, '');
    return !q || String(x.issue).includes(q) || String(x.title || '').toLowerCase().includes(q);
  }

  // A two-click control: n is the issue of a Queue that removes a label, or `rule-<key>` for a Build choice.
  function arm(n) {
    S.armed = n; draw();
    if (S.unarm) window.clearTimeout(S.unarm);
    S.unarm = window.setTimeout(() => { if (S.armed === n) { S.armed = null; draw(); } }, ARM_MS);
  }
  // Queue one issue: release one the record holds; remove the labels of one a label holds, once the owner has read so.
  function queueOne(x) {
    const t = `#${x.issue}`;
    if (x.how === 'release') { send('release', [String(x.issue)], null, ['hold', [String(x.issue)]]); return; }
    if (x.how !== 'unlabel') return;
    if (S.armed !== x.issue) {
      arm(x.issue);
      say(`${x.holds.length === 1 ? 'The label' : 'The labels'} ${x.holds.join(', ')} ${x.holds.length === 1 ? 'holds' : 'hold'} ${t}. Click once more to remove ${x.holds.length === 1 ? 'it' : 'them'} on GitHub for good and queue ${t}.`);
      return;
    }
    S.armed = null;
    send('unlabel', [String(x.issue)].concat(x.holds));
  }
  // Queue a whole group: the ones the record holds, in batches; with the labelled ones, their labels removed one by one.
  function queueAll(g, withLabels) {
    const free = g.items.filter((x) => x.how === 'release').map((x) => String(x.issue));
    const labelled = withLabels ? g.items.filter((x) => x.how === 'unlabel' && !pendingMove(x.issue)) : [];
    const steps = [];
    for (let i = 0; i < free.length; i += RELEASE_MAX) steps.push(['release', free.slice(i, i + RELEASE_MAX)]);
    labelled.forEach((x) => steps.push(['unlabel', [String(x.issue)].concat(x.holds)]));
    S.asking = null; S.withLabels = false;
    if (!steps.length) { draw(); say('You cannot queue anything in this group from here.'); return; }
    run(steps, `queued ${plural(free.length + labelled.length, 'issue', 'issues')} of ${g.name}`);
  }

  // ---- left: one row a rule ----
  // A role: its CLI (one of those installed on the loop's host, s.clis; the judge's the reviewer's too), then a model
  // from that CLI's list (for a CLI that lists none, the pack's models for it), then Other… for a name typed in (a
  // text box alone for a CLI with neither list), then an effort of those the CLI takes there. A model in force that
  // the list does not have is said to be "(not listed)". A pick sends nothing: the row says Unsaved, and Save sends
  // the CLI, model and effort as one action (Default clears the role); Cancel puts back what is in force.
  // A role the host cannot start (s.missing: its CLI gone) says so; a judge on the reviewer's CLI says it is of the
  // reviewer's family.
  function modelCtl(name, key, s) {
    const h = S.ctx.h, box = h('span', 'rules-model');
    const action = key === 'builder' ? 'model' : key;
    const own = (o, k) => Object.prototype.hasOwnProperty.call(o, k);
    const clis = s.clis && typeof s.clis === 'object' ? s.clis : {};
    // An OpenCode model is in force as opencode:<provider>/<model>; OpenCode lists it, and the record holds it, without the mark.
    const bare = (c, m) => (c === 'opencode' && typeof m === 'string' ? m.replace(/^opencode:/, '') : m);
    const opt = (sel, value, text, on) => { const o = h('option', null, text); o.value = value; o.selected = on; sel.append(o); };
    let missing = typeof s.missing === 'string' && s.missing ? s.missing : null;
    // A record the host answered with since the snapshot says what is set here (as the Board's). The judge's role
    // counts when it names its CLI (the reviewer's too; one no longer installed is shown as set, and as unable to
    // start) or, named by its model alone, a model of its choices, as on the host; left at default it runs on
    // s.default, which the snapshot names whatever is set.
    // A role the host took since the snapshot is one it can start.
    if (S.ctl && own(S.ctl, action)) {
      const set = S.ctl[action] && typeof S.ctl[action] === 'object' ? S.ctl[action] : null;
      const r = set && (key !== 'judge' || set.cli || list(s.choices).includes(set.model)) ? set : null;
      if (!same(S.ctl[action], (S.d.control || {})[action])) missing = null;
      s = Object.assign({}, s, {
        model: r ? r.model : (s.modelFrom === 'seed' ? s.model : (s.default || null)), modelFrom: r ? 'control' : 'seed',
        effort: r && r.effort ? r.effort : (s.effortFrom === 'seed' ? s.effort : null), effortFrom: r && r.effort ? 'control' : 'seed',
        agent: r && r.cli ? r.cli : s.agent,
      });
    }
    // What is in force, and what is picked here and not yet saved (the draft, kept across redraws, tabs and reloads).
    const setCli = s.modelFrom === 'control' && s.agent ? s.agent : '';
    const setModel = setCli ? bare(setCli, s.model) || '' : '';
    const setEffort = setModel && s.effortFrom === 'control' && s.effort ? s.effort : '';
    const now = { cli: setCli, model: setModel, effort: setEffort, other: false };
    const v = draftOf(key) || now;
    const cli = v.cli;
    const of = cli && clis[cli] && typeof clis[cli] === 'object' ? clis[cli] : null;
    // An installed CLI offers its own models, or, when it lists none, the pack's models for it (s.allowed); then Other…
    // for a name typed in. One with neither list takes a typed name.
    const names = (c, o) => (!o ? [] : Array.isArray(o.models) ? list(o.models)
      : list(s.allowed && typeof s.allowed === 'object' ? s.allowed[c] : null)).filter((m) => typeof m === 'string' && m);
    const listed = names(cli, of);
    const allowed = of && !Array.isArray(of.models) ? listed : [];
    const typed = !!of && (v.other || (v.model !== '' && !listed.includes(v.model)) || (!Array.isArray(of.models) && !allowed.length));
    const unsaved = () => { const d = draftOf(key); return !!d && (d.cli !== setCli || d.model.trim() !== setModel || d.effort !== setEffort); };
    // A change to the draft: one that comes back to what is in force is no draft.
    const edit = (o, redraw) => {
      const d = Object.assign({}, draftOf(key) || now, o);
      if (d.cli === setCli && d.model.trim() === setModel && d.effort === setEffort && !(d.other && !d.model.trim())) draftDrop(key); else draftPut(key, d);
      if (redraw) draw(); else mark();
    };
    const dflt = s.default || (s.modelFrom === 'seed' && s.model);
    const pick = h('select', 'field board-select');
    pick.dataset.act = `${key}-cli`; pick.setAttribute('aria-label', `${name} CLI`);
    opt(pick, '', dflt ? `Default (${dflt})` : 'Default', cli === '');
    Object.keys(clis).forEach((c) => opt(pick, c, c, c === cli));
    if (cli && !of) opt(pick, cli, `${cli} (not installed)`, true);
    // Another CLI starts with no model picked; the one in force, with its own.
    pick.addEventListener('change', () => edit(pick.value === setCli ? now : { cli: pick.value, model: '', effort: '', other: false }, true));
    let model, field = null;
    if (of && !Array.isArray(of.models) && !allowed.length) {
      // This CLI lists no models and the pack none for it: its model is typed in.
      model = h('input', 'field rules-field');
      model.type = 'text'; model.value = v.model; model.placeholder = `a ${cli} model`;
      model.addEventListener('input', () => edit({ model: model.value }, false));
    } else {
      model = h('select', 'field board-select');
      if (!cli) opt(model, '', 'Default model', true);
      else {
        opt(model, '', 'Pick a model', !typed && v.model === '');
        listed.forEach((m) => opt(model, m, m, !typed && m === v.model));
        // A CLI no longer installed has no list: the model set for it is shown as it is.
        if (of) opt(model, OTHER, 'Other…', typed);
        else if (v.model) opt(model, v.model, `${v.model} (not listed)`, true);
      }
      model.disabled = !cli;
      model.addEventListener('change', () => edit(model.value === OTHER ? { other: true, model: typed ? v.model : '' } : { other: false, model: model.value }, true));
      if (typed) {
        // Other…: a name the list does not have, typed in beside it.
        field = h('input', 'field rules-field');
        field.type = 'text'; field.value = v.model; field.placeholder = `a ${cli} model`;
        field.dataset.act = `${key}-model-other`; field.setAttribute('aria-label', `${name} model, not listed`);
        field.addEventListener('input', () => edit({ model: field.value, other: true }, false));
      }
    }
    model.dataset.act = `${key}-model`; model.setAttribute('aria-label', `${name} model`);
    const effort = h('select', 'field board-select');
    effort.dataset.act = `${key}-effort`; effort.setAttribute('aria-label', `${name} effort`);
    opt(effort, '', `Default effort${s.effortFrom === 'seed' && s.effort ? ` (${s.effort})` : ''}`, v.effort === '');
    list(of ? of.efforts : s.efforts).forEach((e) => opt(effort, e, e, e === v.effort));
    effort.disabled = !cli;
    effort.addEventListener('change', () => edit({ effort: effort.value }, true));
    // Save sends the role whole, as one action; Cancel puts back what is in force. Both show only while unsaved.
    const flag = S.ctx.chip('Unsaved', 'warn');
    const save = button('Save', 'btn-primary', `${key}-save`, `Save the ${name}'s CLI, model and effort`, () => {
      const d = draftOf(key);
      if (!d) return;
      const m = d.model.trim();
      if (d.cli && !m) { say(`Pick the ${name}'s model first.`); return; }
      if (d.cli && !MODEL.test(m)) { say('A model is one word of letters, digits and . _ : / @ [ ] -, starting with a letter or a digit.'); return; }
      const args = d.cli ? [d.cli, m].concat(d.effort ? [d.effort] : []) : ['default'];
      // Refused, the draft stays, still unsaved, with the host's refusal in the row. Saved, the line shows in this
      // panel (where), not the one clicked or typed in while the host answered.
      const repo = S.d.repo, where = S.from;
      send(action, args).then((ok) => {
        if (!ok) return;
        draftDrop(key, repo);
        if (repo !== S.d.repo) return;
        draw();
        say(`Saved: ${key} now ${d.cli ? `${m} · ${d.effort || 'default effort'}` : 'the default'}`, null, where);
      });
    });
    const cancel = button('Cancel', 'btn-quiet', `${key}-cancel`, `Put the ${name} back as it is in force`, () => { draftDrop(key); draw(); });
    function mark() { const on = unsaved(); [flag, save, cancel].forEach((x) => { x.hidden = !on; }); }
    mark();
    // The model in force, "(not listed)" when its CLI, installed, offers a list without it (a name typed in).
    const inForce = s.agent && clis[s.agent] && typeof clis[s.agent] === 'object' ? names(s.agent, clis[s.agent]) : null;
    const unlisted = !!(inForce && inForce.length && s.model && !inForce.includes(bare(s.agent, s.model)));
    box.append(pick, model, ...(field ? [field] : []), effort, flag, save, cancel,
      h('span', 'board-from', `${s.agent ? `${s.agent} ` : ''}${s.model || 'not set'}${unlisted ? ' (not listed)' : ''} · ${s.effort || 'not set'}`));
    if (missing) box.append(S.ctx.chip(`cannot start: ${missing}`, 'bad'));
    // The engine runs a judge on the reviewer's CLI as any other: the row says it is no second family. A role the host
    // took since the snapshot is known by its CLI alone. One cleared to the default, or set by its model alone, runs on
    // a CLI the snapshot does not yet name; so does a judge left at the default once the reviewer changes, as the
    // default judge is of another family than the reviewer's. Nothing is said until the snapshot names it.
    const moved = (k) => !!S.ctl && own(S.ctl, k) && !same(S.ctl[k], (S.d.control || {})[k]);
    const rc = moved('reviewer') ? S.ctl.reviewer : undefined;
    const rv = rc !== undefined ? (rc && rc.cli) || null : ((S.d.modelSettings || {}).reviewer || {}).agent;
    const jc = moved('judge') ? S.ctl.judge : (S.d.control || {}).judge;
    const jSet = !!(jc && typeof jc === 'object' && jc.model);
    const jv = jSet && jc.cli ? jc.cli : (moved('judge') || (!jSet && moved('reviewer')) ? null : s.agent);
    if (key === 'judge' && jv && jv === rv) box.append(h('span', 'board-from', 'same family as the reviewer'));
    return box;
  }
  // One of the host file's accounts, by name, or the default; the record's name is listed even when the host file no
  // longer lists it, so what is set is never shown as another.
  function accountCtl(name, action, set, dflt) {
    const h = S.ctx.h, names = list(S.d.accounts).filter((x) => typeof x === 'string');
    const now = typeof set === 'string' ? set : '';
    if (!names.length && !now) return h('span', 'board-from', `The build machine has no other account, so cards use ${dflt}.`);
    const sel = h('select', 'field board-select');
    sel.dataset.act = action; sel.setAttribute('aria-label', name);
    const opt = (value, text) => { const o = h('option', null, text); o.value = value; o.selected = value === now; sel.append(o); };
    opt('', `Default (${dflt})`);
    names.concat(now && !names.includes(now) ? [now] : []).forEach((x) => opt(x, x));
    sel.addEventListener('change', () => send(action, sel.value ? [sel.value] : []));
    return sel;
  }
  function rules(all) {
    const h = S.ctx.h, d = S.d, c = ctl(), el = h('section', 'rules-side');
    el.append(h('h3', 'board-head', 'Rules'));
    // The machine answered (one it cannot reach gives the panel its error state), but the settings it holds do not
    // read: no restart repairs them, and no new card is picked until they are fixed there.
    if (!c) {
      el.append(h('p', 'warn-note', 'Conveyor could not read its settings on the build machine. You cannot see or change the rules here, and Conveyor picks no new card. Run Conveyor\'s control command on the build machine: it says what is wrong.'));
      return el;
    }
    const r = c.rules && typeof c.rules === 'object' ? c.rules : {};
    // Build: each choice, and what turning one off would skip, said before it is turned off. One that would skip queued
    // issues takes a second click: the first arms it, its button then naming the count.
    const would = BUILDS.filter(([k]) => r[k] !== false).map(([k, name]) => [name, wouldSkip(k)]).filter(([, k]) => k > 0);
    el.append(row('build', 'Build', 'which issues Conveyor may pick',
      ...BUILDS.map(([k, name]) => {
        const on = r[k] !== false, k2 = on ? wouldSkip(k) : 0, armed = k2 > 0 && S.armed === `rule-${k}`;
        const b = choice(armed ? `Turn ${name} off: skip ${k2}` : name, `rule-${k}`,
          armed ? `Confirm: turn ${name} off and skip ${plural(k2, 'queued issue', 'queued issues')}` : `Build ${name}: ${on ? 'on' : 'off'}${k2 ? `; turning it off would skip ${k2} queued` : ''}`, on, () => {
            if (k2 > 0 && !armed) { arm(`rule-${k}`); say(`${skipWords(name, k2)} Click again to turn it off.`); return; }
            S.armed = null;
            send('rules', [`${k}=${on ? 'off' : 'on'}`], null, ['rules', [`${k}=${on ? 'on' : 'off'}`]]);
          });
        if (armed) b.classList.add('board-danger');
        return b;
      }),
      would.length ? h('p', 'rules-would', would.map(([name, k]) => skipWords(name, k)).join(' ')) : null));

    // Never build: the labels, each removable, and a field to add one.
    const never = h('span', 'rules-list');
    list(r.never).forEach((a) => {
      const item = h('span', 'rules-item');
      item.append(S.ctx.chip(a, 'warn'), button('Remove', 'btn-quiet', 'area-on', `Build ${a} again`, () => send('rules', [`${a}=on`], null, ['rules', [`${a}=off`]])));
      never.append(item);
    });
    if (!never.firstChild) never.append(h('span', 'board-from', 'none'));
    const field = h('input', 'field rules-field');
    field.type = 'text'; field.placeholder = `${pre() || ''}infra`; field.dataset.act = 'area-name';
    field.setAttribute('aria-label', 'An area label never to build');
    field.value = S.area;
    // The area labels of the open, queued and held issues, not already never built, to pick from.
    const areas = new Set();
    list(d.open && d.open.issues).concat(list(d.queue), list(d.held), list(d.open && d.open.held))
      .forEach((x) => list(x && x.labels).concat(list(x && x.areas)).forEach((l) => { if (isArea(l) && !list(r.never).includes(l)) areas.add(l); }));
    const areaPick = pickList('rules-areas', Array.from(areas).sort());
    if (areaPick) field.setAttribute('list', areaPick.id);
    const areaNote = h('p', 'rules-would');
    areaNote.dataset.would = 'area';
    areaNote.setAttribute('aria-live', 'polite');
    areaNote.textContent = areaWould();
    field.addEventListener('input', () => { S.area = field.value; areaNote.textContent = areaWould(); });
    const add = () => {
      const a = fieldLabel();
      if (!a) { say(`An area label is letters, digits, dots, dashes, underscores or slashes, as ${pre() || ''}infra.`); return; }
      send('rules', [`${a}=off`], null, ['rules', [`${a}=on`]]).then((ok) => { if (ok) { S.area = ''; draw(); } });
    };
    field.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); add(); } });
    const form = h('span', 'rules-add');
    form.append(...[field, areaPick, button('Add', 'btn-quiet', 'area-off', 'Never build the issues with this area label', add)].filter(Boolean));
    el.append(row('never', 'Never build', 'labels Conveyor skips', never, form, areaNote));

    // At once: the record's cap, else the seed's (d.cap, when the snapshot's cap came from there). After the
    // host clears a cap set here, the seed's number is not known until the next snapshot: both steps are off.
    const capSet = num(c.cap);
    const capNow = capSet !== null ? capSet : ((d.control || {}).cap == null ? num(d.cap) : null);
    el.append(row('cap', 'Cards at once', 'cards building together',
      stepper('cards at once', capNow === null ? '–' : String(capNow), () => send('cap', [String(capNow - 1)], null, ['cap', [capSet !== null ? String(capSet) : 'off']]),
        () => send('cap', [String(capNow + 1)], null, ['cap', [capSet !== null ? String(capSet) : 'off']]),
        capNow !== null && capNow > 1, capNow !== null && capNow < 100),
      h('span', 'board-from', capSet !== null ? 'set here' : 'the default'),
      capSet !== null ? button('Default', 'btn-quiet', 'cap-off', 'Cards at once: back to the default', () => send('cap', ['off'], null, ['cap', [String(capSet)]])) : null));

    // Pause at: Off and three percents (and the one set, when it is another), beside the reading now.
    const guard = num(c.guard);
    const pcts = GUARDS.concat(guard !== null && !GUARDS.includes(guard) ? [guard] : []).sort((a, b) => a - b);
    const lim = d.limit && num(d.limit.pct) !== null ? d.limit.pct : null;
    const reading = h('span', 'board-from', lim === null ? 'the Board does not know the reading now' : `now at ${Math.round(lim * 10) / 10}%`);
    el.append(row('guard', 'Pause when the weekly limit reaches', 'weekly Claude limit',
      choice('Off', 'guard-off', 'Pause when the weekly limit reaches: off', guard === null, () => { if (guard !== null) send('guard', ['off'], null, ['guard', [String(guard)]]); }),
      ...pcts.map((p) => choice(`${p}%`, `guard-${p}`, `Pause Conveyor when the weekly limit reaches ${p} percent`, guard === p, () => { if (guard !== p) send('guard', [String(p)], null, ['guard', [guard === null ? 'off' : String(guard)]]); })),
      reading, guard === null ? S.ctx.chip('no guard set', 'warn') : null));

    // Builder and Reviewer: CLI, model and effort.
    const m = d.modelSettings;
    el.append(row('builder', 'Builder', 'builds and fixes', m && m.builder ? modelCtl('Builder', 'builder', m.builder) : h('span', 'board-from', 'The build machine names no models yet.')));
    el.append(row('reviewer', 'Reviewer', 'reviews each round', m && m.reviewer ? modelCtl('Reviewer', 'reviewer', m.reviewer) : h('span', 'board-from', 'The build machine names no models yet.')));

    // Judge: on or off, its CLI, model and effort (every installed CLI, the reviewer's too; the default names the one
    // of another family it runs on when none is set), and the finding kinds it always accepts, each removable,
    // with a field to add one. The kinds are sent whole: none clears them.
    const judgeOn = c.judgeOn === true, kinds = list(c.judgeAlways).filter((k) => typeof k === 'string');
    const always = h('span', 'rules-list');
    always.dataset.list = 'judge-kinds';
    always.append(h('span', 'board-from', kinds.length ? 'always accepts' : 'always accepts no kind'));
    kinds.forEach((k) => {
      const item = h('span', 'rules-item');
      item.append(S.ctx.chip(k, 'info'), button('Remove', 'btn-quiet', 'judge-kind-remove', `Always accept ${k} findings no more`, () => send('judge', ['always'].concat(kinds.filter((x) => x !== k)))));
      always.append(item);
    });
    const kind = h('input', 'field rules-field');
    kind.type = 'text'; kind.placeholder = 'security'; kind.dataset.act = 'judge-kind';
    kind.setAttribute('aria-label', 'A finding kind the judge always accepts');
    kind.value = S.kind;
    kind.addEventListener('input', () => { S.kind = kind.value; });
    const kindPick = pickList('rules-kinds', KNOWN_KINDS.filter((k) => !kinds.includes(k)));
    if (kindPick) kind.setAttribute('list', kindPick.id);
    const addKind = () => {
      const k = S.kind.trim();
      if (!KIND.test(k)) { say('A finding kind is one word of letters, digits, dashes or underscores, as security.'); return; }
      if (kinds.includes(k)) { say(`The judge already always accepts ${k} findings.`); return; }
      if (kinds.length >= KINDS_MAX) { say(`The judge always accepts ${KINDS_MAX} kinds at most.`); return; }
      send('judge', ['always'].concat(kinds, [k])).then((ok) => { if (ok) { S.kind = ''; draw(); } });
    };
    kind.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); addKind(); } });
    const kindForm = h('span', 'rules-add');
    kindForm.append(...[kind, kindPick].filter(Boolean), button('Add', 'btn-quiet', 'judge-kind-add', 'Always accept the findings of this kind', addKind));
    el.append(row('judge', 'Judge', 'decides which review findings count',
      choice('On', 'judge-on', 'Judge: on', judgeOn, () => { if (!judgeOn) send('judge', ['on'], null, ['judge', ['off']]); }),
      choice('Off', 'judge-off', 'Judge: off', !judgeOn, () => { if (judgeOn) send('judge', ['off'], null, ['judge', ['on']]); }),
      m && m.judge ? modelCtl('Judge', 'judge', m.judge) : h('span', 'board-from', 'The build machine names no model for the reviewer, so none for the judge.'),
      always, kindForm));

    // Account: the Claude account of the host's accounts this project's cards use, and one for its reviews when the
    // reviewer is Claude. A change reaches the cards started after it; a card in flight keeps its own.
    el.append(row('account', 'Account', 'cards started after a change', accountCtl('Account', 'account', c.account, "the build machine's own login")));
    el.append(row('review-account', 'Review account', 'a Claude reviewer only', accountCtl('Review account', 'review-account', c.reviewAccount, 'the Account')));

    // New issues start in: Queue (the default) or Held. A follow-up is always queued.
    const start = c.start === 'held' ? 'held' : 'queue';
    el.append(row('start', 'New issues start in', 'Conveyor always queues follow-ups',
      choice('Queue', 'start-queue', 'New issues start in the Queue', start === 'queue', () => { if (start !== 'queue') send('start', ['queue'], null, ['start', ['held']]); }),
      choice('Held', 'start-held', 'New issues start in Held', start === 'held', () => { if (start !== 'held') send('start', ['held'], null, ['start', ['queue']]); })));

    // Dependency guard, Push when a card lands and Visible changes need your yes: the words under each name say what
    // it does, whichever choice is set; what Off means shows beside the switch only while Off is set. An engine that
    // does not know one (its record has no depGuard, rules.push or rules.visible) is sent neither choice.
    const offLine = (on, text) => (on ? null : h('span', 'board-from rules-off', `off: ${text}`));
    const newer = (known) => (known ? null : h('span', 'board-from', 'needs a newer Conveyor'));
    // Dependency guard: On (a record without it reads as On) never picks an issue while one it depends on is open; Off
    // lets "Queue anyway" force one.
    const guardOn = c.depGuard !== false, knows = depKnown();
    const gOn = choice('On', 'dep-guard-on', 'Dependency guard: on', guardOn, () => { if (!guardOn) send('dep-guard', ['on'], null, ['dep-guard', ['off']]); });
    const gOff = choice('Off', 'dep-guard-off', 'Dependency guard: off', !guardOn, () => { if (guardOn) send('dep-guard', ['off'], null, ['dep-guard', ['on']]); });
    gOn.disabled = gOff.disabled = !knows;
    el.append(row('dep-guard', 'Dependency guard', 'an issue waits while one it depends on is open',
      gOn, gOff, knows ? offLine(guardOn, 'Conveyor can build a waiting issue all the same') : newer(knows)));

    // Push when a card lands: On pushes each card once it lands; Off (the default, control-defaults.json) lands only, and what landed waits for
    // Push landed on the Board.
    const pushOn = r.push !== false, pushKnown = typeof r.push === 'boolean';
    const pOn = choice('On', 'push-on', 'Push when a card lands: on', pushOn, () => { if (!pushOn) send('rules', ['push=on'], null, ['rules', ['push=off']]); });
    const pOff = choice('Off', 'push-off', 'Push when a card lands: off', !pushOn, () => { if (pushOn) send('rules', ['push=off'], null, ['rules', ['push=on']]); });
    pOn.disabled = pOff.disabled = !pushKnown;
    el.append(row('push', 'Push when a card lands', 'Conveyor pushes each card when it lands',
      pOn, pOff, pushKnown ? offLine(pushOn, 'land only: cards land on main, and Push landed on the Control tab pushes them') : newer(pushKnown)));
    // Visible changes need your yes: On stops a card whose change customers or staff will see until its
    // issue has a `Visible change approved:` line; Off (the default) lets it land without one, and says so beside the switch, so a
    // landed visible change is not read as approved.
    const yesOn = r.visible !== false, yesKnown = typeof r.visible === 'boolean';
    const yOn = choice('On', 'visible-on', 'Visible changes need your yes: on', yesOn, () => { if (!yesOn) send('rules', ['visible=on'], null, ['rules', ['visible=off']]); });
    const yOff = choice('Off', 'visible-off', 'Visible changes need your yes: off', !yesOn, () => { if (yesOn) send('rules', ['visible=off'], null, ['rules', ['visible=on']]); });
    yOn.disabled = yOff.disabled = !yesKnown;
    el.append(row('visible', 'Visible changes need your yes', 'a change customers or staff will see waits for your yes',
      yOn, yOff, yesKnown ? offLine(yesOn, 'visible changes land without your yes, and nobody approves them') : newer(yesKnown)));
    // Whole suite in a card: Off (the default; a record without it reads as Off) runs only the test files a card's
    // change adds or changes (with none, 5 linked to it), the linked files before each push, and the whole suite only
    // in a release; On lets a card run the whole suite when its tests cannot be found.
    const wholeOn = r.wholeSuite === true, wholeKnown = typeof r.wholeSuite === 'boolean';
    const wOn = choice('On', 'whole-suite-on', 'Whole suite in a card: on', wholeOn, () => { if (!wholeOn) send('rules', ['wholeSuite=on'], null, ['rules', ['wholeSuite=off']]); });
    const wOff = choice('Off', 'whole-suite-off', 'Whole suite in a card: off', !wholeOn, () => { if (wholeOn) send('rules', ['wholeSuite=off'], null, ['rules', ['wholeSuite=on']]); });
    wOn.disabled = wOff.disabled = !wholeKnown;
    el.append(row('wholeSuite', 'Whole suite in a card', 'a card may run every test file when it cannot find the tests of its change',
      wOn, wOff, wholeKnown ? offLine(wholeOn, 'a card runs only the test files it adds or changes (with none, 5 linked to its change), the test files linked to the landings run before each push, and the whole suite runs only in a release') : newer(wholeKnown)));
    // Card work yields to you: the machine's (the host file's steer, every project's alike), sent as POST /machine.
    // On (the default) runs card sessions at lowered priority and card test runs at idle priority; Off runs them at
    // normal priority. Undo sends the other value.
    const steerKnown = S.steer !== null, steerOn = S.steerSent !== null ? S.steerSent : S.steer !== false;
    const steerTo = (on) => {
      if (S.busy) { say('Wait: the build machine did not answer the last change yet.'); return; }
      S.busy = true; draw(); say('Sending…');
      S.ctx.post('machine', { action: 'steer', value: on ? 'on' : 'off' }).then((r) => r.text().then((t) => [r.ok, String(t).trim() || `the host answered ${r.status}`]),
        () => [false, 'the host did not answer']).then(([ok, said]) => {
        S.busy = false;
        if (ok) S.steerSent = on;
        draw();
        say(ok ? `Done: Card work yields to you is ${on ? 'on' : 'off'}.` : `Not done: ${S.ctx.refusal(said)}`, ok ? () => steerTo(!on) : null);
      });
    };
    const sOn = choice('On', 'steer-on', 'Card work yields to you: on', steerOn, () => { if (!steerOn) steerTo(true); });
    const sOff = choice('Off', 'steer-off', 'Card work yields to you: off', !steerOn, () => { if (steerOn) steerTo(false); });
    sOn.disabled = sOff.disabled = !steerKnown;
    el.append(row('steer', 'Card work yields to you', 'card sessions and tests run at low priority on the build machine, for every project',
      sOn, sOff, steerKnown ? offLine(steerOn, 'card work runs at normal priority, beside yours') : newer(steerKnown)));
    // Cores kept for you: the machine's (the host file's reserveCores), shown here and set in the host file.
    const co = S.cores, slots = co && typeof co.slots === 'number' ? `${co.slots} test slot${co.slots === 1 ? '' : 's'}` : 'test slots not read';
    el.append(row('cores', 'Cores kept for you', 'card sessions and tests never run on these cores, for every project (the host file\'s reserveCores)',
      !co ? newer(false)
        : h('span', 'board-from rules-cores', co.unavailable ? `not available on this machine: ${co.unavailable}`
          : co.reserved.length ? `cores ${co.reserved.join(', ')}; ${slots} left` : `none; ${slots}`)));

    // Done without asking: one row a standing kind of routine yes, On or Off. Off (each kind's setting from setup)
    // sends each such step to you. A Conveyor whose snapshot has no standing is sent neither choice.
    const standingOn = standingShown();
    STANDING.forEach(([k, name, what]) => {
      const on = !!standingOn && standingOn.includes(k);
      const sOn = choice('On', `standing-${k}-on`, `${name} without asking: on`, on, () => { if (!on) send('standing', [k, 'on'], null, ['standing', [k, 'off']]); });
      const sOff = choice('Off', `standing-${k}-off`, `${name} without asking: off`, !on, () => { if (on) send('standing', [k, 'off'], null, ['standing', [k, 'on']]); });
      sOn.disabled = sOff.disabled = !standingOn;
      el.append(row(`standing-${k}`, `${name} without asking`, what, sOn, sOff, standingOn ? offLine(on, 'the Foreman asks you first') : newer(false)));
    });

    // Held by you: the count, and a link to the list below.
    const link = h('a', 'rules-link', 'See them below');
    link.href = '#rules-held'; link.dataset.act = 'held-link';
    el.append(unlisted() ? row('held', HELD, 'parked issues', h('span', 'board-from', heldUnknown()))
      : row('held', HELD, 'parked issues', h('span', 'board-value', plural(all.length, 'issue held', 'issues held')), all.length ? link : null));

    // The pinned order, when there is one: one line, each with Move up (not on the first), Move down (not on the
    // last) and Unpin. unpin takes this one issue out of the record's
    // order on the host, under its lock: an order sent whole from here would drop a pin set elsewhere (the Board).
    const order = list(c.order);
    if (order.length) {
      const titles = new Map(list(d.queue).concat(list(d.held), list(d.waits)).map((x) => [x.issue, x.title]));
      const pins = h('span', 'rules-list');
      // Move up and Move down send the pinned order with the two swapped.
      // Undo, of a move or an unpin, sends the pinned order as it was.
      const swap = (i, j) => { const o = order.slice(); [o[i], o[j]] = [o[j], o[i]]; send('order', o.map(String), null, ['order', order.map(String)]); };
      order.forEach((n, i) => {
        const item = h('span', 'rules-item');
        item.dataset.issue = String(n);
        const up = i > 0 ? button('Move up', 'btn-quiet', 'pin-up', `Move #${n} up in the pinned order`, () => swap(i, i - 1)) : null;
        const down = i < order.length - 1 ? button('Move down', 'btn-quiet', 'pin-down', `Move #${n} down in the pinned order`, () => swap(i, i + 1)) : null;
        item.append(...[h('span', 'rules-pin', titles.get(n) ? `#${n} ${titles.get(n)}` : `#${n}`), up, down].filter(Boolean),
          button('Unpin', 'btn-quiet', 'unpin', `Unpin #${n}: pick takes it in its own order`, () => send('unpin', [String(n)], null, ['order', order.map(String)])));
        pins.append(item);
      });
      el.append(row('order', 'Pinned', 'picked first, in this order', pins));
    }
    return el;
  }

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
    return ul;
  }
  function produce(all) {
    const h = S.ctx.h, d = S.d, f = d.forecast && typeof d.forecast === 'object' ? d.forecast : null, el = h('section', 'rules-side rules-produce');
    el.append(h('h3', 'board-head', 'What these rules produce'));
    if (S.ctl) el.append(h('p', 'board-from', 'Changed here: this side shows it in about a minute.'));
    if (d.queue === null || d.queue === undefined) {
      el.append(h('p', 'warn-note', d.issuesError || 'GitHub did not list the open issues.'));
      return el;
    }
    const q = list(d.queue), sk = list(d.skipped), w = waiters(), wa = waitingAll();
    const stats = h('div', 'rules-stats');
    // The waiting count opens the list of the waiting cards.
    const ws = h('button', 'rules-stat rules-stat-open');
    ws.type = 'button'; ws.dataset.figure = 'waiting'; ws.dataset.act = 'waits-open';
    ws.setAttribute('aria-expanded', String(S.waitsOpen)); ws.setAttribute('aria-controls', 'rules-waits');
    ws.append(h('span', 'rules-big', String(wa.length)), h('span', 'board-from', 'waiting on another card'));
    ws.disabled = !wa.length;
    ws.addEventListener('click', () => { S.waitsOpen = !S.waitsOpen; draw(); });
    stats.append(stat('ready', String(q.length), 'ready to build'), ws,
      stat('held', String(all.length), HELD.toLowerCase()), stat('skipped', String(sk.length), 'skipped by a rule'));
    el.append(stats);
    if (S.waitsOpen && wa.length) el.append(waitList(wa));

    // Next up: the queue in its order, with each issue that waits on another card where pick would take it.
    const order = list((ctl() || {}).order);
    const next = q.slice();
    // A pinned issue goes where its pin puts it (before each later pin and every unpinned issue); an unpinned one goes
    // among the unpinned by pick's rank.
    const pin = (i) => { const k = order.indexOf(i); return k < 0 ? Infinity : k; };
    const before = (x, y) => { const a = pin(x.issue), b = pin(y.issue); return a !== b ? a < b : a === Infinity && ahead(x, y); };
    w.forEach((x) => { const at = next.findIndex((y) => before(x, y)); next.splice(at < 0 ? next.length : at, 0, x); });
    el.append(h('h4', 'board-label', 'Next up'));
    if (next.length) {
      const flow = h('ol', 'rules-flow');
      flow.setAttribute('aria-label', 'The next issues Conveyor picks, in order');
      next.slice(0, 5).forEach((x) => {
        const li = h('li', 'rules-next');
        li.dataset.issue = String(x.issue);
        const marks = h('span', 'rules-marks');
        const waits = list(x.waitsFor);
        // One forced past its wait (`control force`) is picked all the same: it says so, not "ready".
        if (waits.length) waits.forEach((n) => marks.append(S.ctx.chip(`${x.forced === true ? 'forced past' : 'waits on'} ${S.ctx.depRef(n)}`, 'warn')));
        else marks.append(S.ctx.chip('ready', 'ok'));
        li.append(S.ctx.issueLink(x), h('span', 'board-title', x.title || 'untitled'), marks);
        flow.append(li);
      });
      el.append(flow);
    } else el.append(h('p', 'board-empty', 'Nothing to build under these rules.'));

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

    if (sk.length) {
      const ul = h('ul', 'rules-skipped');
      ul.setAttribute('aria-label', 'Skipped by a rule');
      sk.forEach((x) => {
        const li = h('li', 'rules-skip');
        li.dataset.issue = String(x.issue);
        li.append(S.ctx.issueLink(x), h('span', 'board-title', x.title || 'untitled'), h('span', 'board-from', why(x.rule)));
        ul.append(li);
      });
      el.append(h('h4', 'board-label', 'Skipped'), ul);
    }
    return el;
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
      ask.setAttribute('role', 'group'); ask.setAttribute('aria-label', `Queue all of ${g.name}`);
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
    return box;
  }
  function heldSection(all) {
    const h = S.ctx.h, el = h('section', 'rules-held');
    el.id = 'rules-held';
    if (unlisted()) {
      el.append(h('h3', 'board-head', HELD), h('p', 'warn-note', `${S.d.issuesError || 'GitHub did not list the open issues.'} ${heldUnknown()}`));
      return el;
    }
    el.append(h('h3', 'board-head', `${HELD} · ${all.length}`));
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
    ['blocked', 'Blocked'], ['rule', 'Skipped by a rule'], ['approve', 'Waits for your yes']];
  const ISORTS = [['priority', 'Priority'], ['number', 'Number'], ['age', 'Age'], ['area', 'Area'], ['state', 'State']];
  const IFILTERS = ['iq', 'istate', 'iprio', 'iarea', 'ilabel', 'isort', 'idir'];
  // The open issues' filters as the address holds them, as one text (S.shown keeps the ones each panel shows).
  const filtersOf = (ctx) => JSON.stringify(IFILTERS.map((k) => ctx.param(k) || ''));
  function openIssues() {
    const d = S.d, c = ctl();
    if (!d.open || !Array.isArray(d.open.issues)) return null;
    const held = new Map(list(d.open.held).map((x) => [x.issue, x]));
    const mine = new Set(c ? list(c.held) : list(d.open.held).filter((x) => list(x.reasons).some((r) => r && r.kind === 'you')).map((x) => x.issue));
    const q = list(d.queue).map((x) => x.issue), belt = new Set(list(d.onBelt)), blocked = new Set(list(d.blocked).map((x) => x.issue));
    return d.open.issues.filter((x) => x && num(x.issue) !== null).map((x) => {
      const why = list((held.get(x.issue) || {}).reasons).filter((r) => r && r.kind !== 'you'), k = (kind) => why.find((r) => r.kind === kind);
      const at = q.indexOf(x.issue);
      // One not picked for any reason named here is skipped by a rule of Conveyor's own: one word for it, as on the Board.
      let state = 'rule';
      if (belt.has(x.issue)) state = 'building';
      else if (blocked.has(x.issue)) state = 'blocked';
      else if (mine.has(x.issue)) state = 'you';
      else if (k('label')) state = 'label';
      else if (k('rule') || k('standing')) state = 'rule';
      else if (k('waits')) state = 'waits';
      // A card stopped and not among the blocked ones waits in Needs you for the owner's yes: nothing to retry.
      else if (k('approve') || (k('card') && k('card').step === 'blocked')) state = 'approve';
      else if (at >= 0) state = at < NEXT ? 'next' : 'queued';
      return Object.assign({}, x, { state, mine: mine.has(x.issue), waitsFor: state === 'waits' ? list(k('waits').waitsFor) : [], areas: list(x.labels).filter(isArea).sort() });
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
    // Hold and Queue undo each other, and Order first undoes to the order as it was; a retry is not undone.
    const back = action === 'hold' || action === 'release' ? steps.map(([a, args]) => [a === 'hold' ? 'release' : 'hold', args])
      : action === 'order' ? [['order', list((ctl() || {}).order).map(String)]] : null;
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
  function issuesSection() {
    const h = S.ctx.h, el = h('section', 'rules-issues'), all = openIssues();
    el.id = 'rules-issues';
    if (all === null) {
      el.append(h('h3', 'board-head', 'Open issues'), h('p', 'warn-note', S.d.issuesError || 'GitHub did not list the open issues.'));
      return el;
    }
    el.append(h('h3', 'board-head', `Open issues · ${all.length}`));
    const v = issueChoice(), labels = Array.from(new Set(all.flatMap((x) => list(x.labels)))).sort(), areas = labels.filter(isArea);
    const tools = h('div', 'rules-held-tools');
    const search = h('input', 'field rules-search');
    search.type = 'search'; search.placeholder = 'Search number or title'; search.dataset.act = 'iq'; search.value = v.q;
    search.setAttribute('aria-label', 'Search the open issues by number or title');
    search.addEventListener('input', () => {
      const was = filtersOf(S.ctx);
      S.ctx.params({ iq: search.value });
      S.shown.forEach((f, id) => { if (f === was) S.shown.set(id, filtersOf(S.ctx)); });
      const fresh = issuesSection();
      el.replaceWith(fresh);
      const again = fresh.querySelector('[data-act="iq"]');
      again.focus();
      relength();
    });
    const sel = (act, name, opts, cur) => {
      const s = h('select', 'field board-select');
      s.dataset.act = act; s.setAttribute('aria-label', name);
      opts.forEach(([value, text]) => { const o = h('option', null, text); o.value = value; o.selected = value === cur; s.append(o); });
      s.addEventListener('change', () => { S.ctx.params(act === 'isort' ? { isort: s.value, idir: null } : { [act]: s.value }); draw(); relength(); });
      return s;
    };
    tools.append(search,
      sel('istate', 'Filter the open issues by state', [['', 'Any state']].concat(STATES), v.state),
      sel('iprio', 'Filter the open issues by priority', [['', 'Any priority'], ['P0', 'P0'], ['P1', 'P1'], ['P2', 'P2'], ['P3', 'P3']], v.pri),
      sel('iarea', 'Filter the open issues by area', [['', 'Any area']].concat(areas.map((a) => [a, areaName(a)])), v.area),
      sel('ilabel', 'Filter the open issues by label', [['', 'Any label']].concat(labels.map((l) => [l, l])), v.label),
      sel('isort', 'Sort the open issues by', ISORTS, v.sort),
      sel('idir', 'Sort direction', [['asc', 'Ascending'], ['desc', 'Descending']], v.dir));
    el.append(tools);

    // The picked rows (those still open) and what each action would take: its count is on its button.
    const shown = shownIssues(all), picked = all.filter((x) => S.picked.has(x.issue));
    const acts = h('div', 'rules-ask-acts rules-issue-acts');
    const allBox = h('input'), allLab = h('label', 'rules-check');
    allBox.type = 'checkbox'; allBox.dataset.act = 'pick-all';
    allBox.checked = shown.length > 0 && shown.every((x) => S.picked.has(x.issue));
    allBox.setAttribute('aria-label', `Select the ${plural(shown.length, 'issue', 'issues')} shown`);
    allBox.addEventListener('change', () => { shown.forEach((x) => { if (allBox.checked) S.picked.add(x.issue); else S.picked.delete(x.issue); }); draw(); });
    allLab.append(allBox, h('span', null, `Select all shown (${shown.length})`));
    acts.append(allLab, h('span', 'board-from', `${picked.length} selected`));
    // Held by you is the record's hold, whatever state shows first (a blocked or building issue may be held too).
    const group = {
      hold: picked.filter((x) => !x.mine), release: picked.filter((x) => x.mine),
      order: picked.filter((x) => x.state !== 'building'), retry: picked.filter((x) => x.state === 'blocked'),
    };
    [['hold', 'Hold', 'Hold'], ['release', 'Queue', 'Queue'], ['order', 'Order first', 'Pin first in the order'], ['retry', 'Retry', 'Retry the blocked card of']].forEach(([a, word, say2]) => {
      const n = group[a].length, label = `${say2} ${plural(n, 'issue', 'issues')}`;
      // A retry costs a new build of each: a second click. The guard is keyed on the cards it retries, so a click armed
      // for one selection does not confirm another.
      const b = a === 'retry' ? guarded(`bulk-retry:${group.retry.map((x) => x.issue).join(',')}`, 'spend',`${word} ${n}`, `Click again to retry ${n}`, `bulk-${a}`, label, () => bulk(a, group[a]))
        : button(`${word} ${n}`, 'btn-quiet', `bulk-${a}`, label, () => bulk(a, group[a]));
      // One order takes ORDER_MAX issues, the pins already there among them: a longer one is not offered.
      const over = a === 'order' && pinnedFirst(group.order.map((x) => String(x.issue))).length > ORDER_MAX;
      b.disabled = n === 0 || over;
      if (over) b.title = `One order takes ${ORDER_MAX} issues, the pins already there among them`;
      acts.append(b);
    });
    el.append(acts);
    const ul = h('ul', 'rules-issue-list');
    ul.setAttribute('aria-label', 'Open issues');
    shown.forEach((x) => ul.append(issueRow(x)));
    el.append(ul);
    if (!shown.length) el.append(h('p', 'board-empty', all.length ? 'No open issue matches.' : 'No open issue.'));
    return el;
  }

  // Where the Machine section was (#462): one line. Load limit and the other test limits are on the Tests page (#520).
  function limitsLine() {
    const p = S.ctx.h('p', 'rules-limits', 'Test limits are on the ');
    const a = S.ctx.h('a', null, 'Tests page');
    a.href = 'index.html?tab=tests'; a.dataset.act = 'tests-page';
    a.addEventListener('click', (e) => { if (e.button || e.ctrlKey || e.metaKey || e.shiftKey || e.altKey) return; e.preventDefault(); S.ctx.setTab('tests', true); });
    p.append(a, '.');
    return p;
  }

  // The head: changes save at once, and the last change made here for this project, always shown, with Undo when it
  // has one (its undo puts back the value it replaced; one setting's undo is itself the next last change, with its own).
  function head() {
    const h = S.ctx.h, last = lastRead(), mine = last && last.repo === S.d.repo ? last : null, p = h('div', 'rules-top');
    const line = h('p', 'rules-last');
    line.append(h('span', 'rules-last-what', mine ? `Last change here: ${mine.what}, ${S.ctx.when(mine.at)}` : 'Last change here: none yet'));
    if (mine && mine.undo && ctl()) {
      const u = mine.undo, armed = S.armed === `undo:${JSON.stringify(u)}` ? undoSkips(u) : [];
      const b = button(armed.length ? undoLabel(armed) : 'Undo', 'btn-quiet', 'undo', `Undo the last change here: ${mine.what}`,
        () => undoAsk(u, () => (u.length === 1 ? send(u[0][0], u[0][1]) : run(u, `undid: ${mine.what}`, null, null))));
      if (armed.length) b.classList.add('board-danger');
      line.append(b);
    }
    p.append(h('span', null, 'The Board saves a rule when you change it. It saves the Builder, Reviewer and Judge models when you press Save.'), line);
    return p;
  }

  // Model prices (pricesSection): every model the built-in table or the pack prices, from the part's prices: builtIn
  // (the built-in rows), overrides (the pack's entries: prices, name, provider, aliases), names (each model's own
  // display name) and seen (each model ID this project's steps ran in 30 days, with the model it is priced as). Prices
  // are $ per million tokens. Top to bottom: a search box (an ID, name or alias: the rows that do not match hide as it
  // is typed) and Add model; Seen but not priced (an ID no model and no alias prices: This is… adds it as an alias of
  // the model picked, the likely one picked first; Add as new model fills the Add model form); In use by this project
  // (a model a role or the research lane runs, or its steps ran, each with its marks); Claude, OpenAI and Other, by
  // family, newest first, the older versions folded; then OpenCode (its models on the build machine, by provider/model,
  // those not in use and not priced folded; one added in the pack is a model's row). A model's fast mode is its row's
  // second line, with its own Edit :fast and Reset :fast. Edit opens the row in place: display name, other
  // IDs and the four prices; Save sends what changed (`prices set`, `name`, `alias`), Cancel drops it. A row priced
  // from the pack says so and has Reset to built-in (`prices clear`); an added model has Remove. Every change has Undo,
  // which puts back what it replaced, and shows at once, until the next snapshot (priceSaved).
  const PRICE_KEYS = [['input', 'Input'], ['output', 'Output'], ['cacheRead', 'Cache read'], ['cacheWrite', 'Cache write']];
  const RATES = ['input', 'output', 'cacheRead'];
  const FAMILIES = ['fable', 'mythos', 'opus', 'sonnet', 'haiku'];
  const PROVIDERS = [['claude', 'Claude'], ['openai', 'OpenAI'], ['other', 'Other'], ['opencode', 'OpenCode']];
  const priced = (e) => !!e && RATES.every((k) => num(e[k]) !== null);
  const providerOf = (m, e) => (e && PROVIDERS.some(([k]) => k === e.provider) ? e.provider : m.startsWith('opencode:') ? 'opencode'
    : /^claude-/.test(m) ? 'claude' : /^gpt-/.test(m) ? 'openai' : 'other');
  // The line a model is a version of (opus, sonnet; sol, astra), and its version as numbers, for newest first.
  const lineOf = (m) => { const x = /^claude-([a-z]+)-/.exec(m) || /^gpt-[\d.]+-([a-z]+)/.exec(m); return x ? x[1] : m; };
  const versionOf = (m) => (/^(?:claude-[a-z]+-|gpt-)([\d.-]+)/.exec(m) || [null, ''])[1].split(/[.-]/).filter(Boolean).map(Number);
  function newer(a, b) { // below 0 when a is newer than b
    const x = versionOf(a), y = versionOf(b);
    for (let i = 0; i < Math.max(x.length, y.length); i += 1) {
      const d = (y[i] === undefined ? -1 : y[i]) - (x[i] === undefined ? -1 : x[i]);
      if (d) return d;
    }
    return a < b ? -1 : a > b ? 1 : 0;
  }
  const familyRank = (m) => { const i = FAMILIES.indexOf(lineOf(m)); return i < 0 ? FAMILIES.length : i; };
  const byFamily = (a, b) => familyRank(a) - familyRank(b) || newer(a, b);
  const usd = (v) => (num(v) !== null ? `$${+v.toFixed(6)}` : '—');
  const writeOf = (r) => (num(r.cacheWrite) !== null ? r.cacheWrite : num(r.input) !== null ? r.input * 1.25 : null);
  // The pack's standing kinds as shown: as a change saved here left them, until a new snapshot comes; null from a
  // snapshot without them.
  const standingShown = () => (S.standingSaved && S.standingSaved.for === S.d.standing ? S.standingSaved.over
    : Array.isArray(S.d.standing) ? S.d.standing : null);
  // The pack's prices as shown: as the changes saved here left them, until a new snapshot comes.
  const pricesShown = () => (S.priceSaved && S.priceSaved.for === S.d.prices ? S.priceSaved.over
    : S.d.prices && S.d.prices.overrides && typeof S.d.prices.overrides === 'object' ? S.d.prices.overrides : {});
  // The pack's prices after `prices <a>`, as the engine writes them (conveyor/commands/prices.sh).
  function applied(o, a) {
    const r = JSON.parse(JSON.stringify(o)), m = a[1], e = r[m] || {};
    if (a[0] === 'set') { delete e.cacheWrite; RATES.forEach((k, i) => { e[k] = Number(a[2 + i]); }); if (a[5] !== undefined) e.cacheWrite = Number(a[5]); }
    if (a[0] === 'clear') PRICE_KEYS.forEach(([k]) => { delete e[k]; });
    if (a[0] === 'name') { if (a[2]) e.name = a[2]; else delete e.name; }
    if (a[0] === 'alias') {
      const l = list(e.aliases).filter((x) => x !== a[3]).concat(a[2] === 'add' ? [a[3]] : []);
      if (l.length) e.aliases = l; else delete e.aliases;
    }
    r[m] = a[0] !== 'add' ? e : Object.assign({ name: a[3], provider: a[2] }, ...RATES.map((k, i) => ({ [k]: Number(a[4 + i]) })), a[7] !== undefined ? { cacheWrite: Number(a[7]) } : {});
    if (a[0] === 'remove' || !Object.keys(r[m]).length) delete r[m];
    return r;
  }
  // The steps that put back what `prices <a>` replaces, from the pack's prices o before it.
  function inverse(o, a) {
    const m = a[1], e = o[m] || {}, rates = (x) => RATES.map((k) => String(x[k])).concat(num(x.cacheWrite) !== null ? [String(x.cacheWrite)] : []);
    if (a[0] === 'set' || a[0] === 'clear') return [['prices', priced(e) ? ['set', m, ...rates(e)] : ['clear', m]]];
    if (a[0] === 'add') return [['prices', ['remove', m]]];
    if (a[0] === 'name') return [['prices', e.name ? ['name', m, e.name] : ['name', m]]];
    if (a[0] === 'alias') return [['prices', ['alias', m, a[2] === 'add' ? 'remove' : 'add', a[3]]]];
    return [['prices', ['add', m, providerOf(m, e), e.name || m, ...rates(e)]], ...list(e.aliases).map((x) => ['prices', ['alias', m, 'add', x]])];
  }
  function priceWords(a) {
    const m = a[1], cw = (x) => (x !== undefined ? `, $${x} cache write` : '');
    if (a[0] === 'set') return `price of ${m}: $${a[2]} input, $${a[3]} output, $${a[4]} cache read${cw(a[5])}`;
    if (a[0] === 'clear') return `${m} back to its built-in price`;
    if (a[0] === 'add') return `added ${a[3]} (${m}): $${a[4]} input, $${a[5]} output, $${a[6]} cache read${cw(a[7])}`;
    if (a[0] === 'remove') return `removed ${m}`;
    if (a[0] === 'name') return a[2] ? `${m} shown as ${a[2]}` : `${m} shown by its own name`;
    return a[2] === 'add' ? `${a[3]} is ${m}` : `${a[3]} is no longer ${m}`;
  }
  // Changes of the pack's prices sent as one, with the Undo that puts back what they replace; done when all are saved.
  function priceRun(changes, done) {
    let o = pricesShown();
    const undo = [];
    changes.forEach((a) => { undo.unshift(...inverse(o, a)); o = applied(o, a); });
    return run(changes.map((a) => ['prices', a]), changes.map(priceWords).join('; '), done, undo);
  }

  function pricesSection() {
    const h = S.ctx.h, p = S.d.prices && typeof S.d.prices === 'object' ? S.d.prices : null, el = h('section', 'rules-prices');
    el.append(h('h3', 'board-head', 'Model prices'));
    if (!p) { el.append(h('p', 'unknown', 'The model prices were not read.')); return el; }
    const over = pricesShown(), names = p.names && typeof p.names === 'object' ? p.names : {};
    const built = new Map(list(p.builtIn).filter((x) => x && typeof x.model === 'string').map((x) => [x.model, x]));
    const nameOf = (m) => (over[m] && typeof over[m].name === 'string' && over[m].name) || (typeof names[m] === 'string' && names[m]) || m;
    // The model each other ID means (the pack's aliases); the model an ID is priced as (with no date or [1m] on it).
    const aliasTo = new Map();
    Object.keys(over).forEach((m) => list(over[m] && over[m].aliases).forEach((x) => { if (typeof x === 'string' && !aliasTo.has(x)) aliasTo.set(x, m); }));
    const canon = (id) => { const b = String(id).replace(/\[[^\]]*\]$/, '').replace(/-\d{8}$/, ''); return aliasTo.get(b) || b; };
    // The models: each built-in one (its fast mode is its second line) and each the pack prices or adds.
    const isModel = (m) => built.has(m) || priced(over[m]) || !!(over[m] && over[m].provider);
    const models = [...new Set([...built.keys(), ...Object.keys(over)])].filter((m) => !m.endsWith(':fast') && isModel(m));
    const rateOf = (m) => (priced(over[m]) ? over[m] : built.get(m) || null);
    // In use: a model a role runs (its marks) or this project's steps ran in 30 days (how many).
    const ms = S.d.modelSettings && typeof S.d.modelSettings === 'object' ? S.d.modelSettings : {}, c = ctl() || {};
    const roles = new Map(), sessions = new Map(), raw = new Set();
    const role = (id, t) => { raw.add(id); const m = canon(id), l = roles.get(m) || []; if (!l.includes(t)) l.push(t); roles.set(m, l); };
    ROLES.forEach((k) => { const s = ms[k]; if (s && typeof s.model === 'string' && s.model) role(s.model, k); });
    const ts = c.tests && typeof c.tests === 'object' && typeof c.tests.model === 'string' ? c.tests : null;
    if (ts) role(ts.cli === 'opencode' && !ts.model.startsWith('opencode:') ? `opencode:${ts.model}` : ts.model, 'Tests');
    if (typeof p.research === 'string' && p.research) role(p.research, 'research lane');
    const seen = list(p.seen).filter((x) => x && typeof x.model === 'string' && num(x.sessions) !== null);
    seen.forEach((x) => {
      raw.add(x.model);
      const m = typeof x.as === 'string' ? x.as.replace(/:fast$/, '') : canon(x.model);
      sessions.set(m, (sessions.get(m) || 0) + x.sessions);
    });
    const inUse = (m) => roles.has(m) || sessions.has(m);
    // Seen but not priced: an ID of the steps that no model and no alias prices (an OpenCode one keeps OpenCode's cost).
    const unpriced = seen.filter((x) => x.as === null && !aliasTo.has(x.model) && !isModel(x.model) && !x.model.startsWith('opencode:'));
    // Offered or run with no price: a model a role runs, or one the models.allowed in force offers a role (the pack's
    // list when it sets one, else the built-in models with the host's Codex models in place of the built-in Codex ones,
    // and none of them when the host has no Codex, modelsallowed() in conveyor/lib/control.sh: a model only a CLI's
    // own list names is not one when the pack sets a list), that no
    // model and no alias prices and no step has run yet (those are Seen but not priced). OpenCode's keep the cost OpenCode reports. A one-word name (sol, opus) is a family or an alias, no
    // model ID: the CLI runs a model of its own choice, so the name has no price to add. Conveyor files one issue to
    // add each (noprice()).
    const offered = new Set(roles.keys());
    ROLES.forEach((k) => {
      const s = ms[k];
      if (!s) return;
      Object.entries(s.allowed && typeof s.allowed === 'object' ? s.allowed : {}).forEach(([c, o]) => {
        if (c !== 'opencode') list(o).forEach((m) => { if (typeof m === 'string' && m) offered.add(m); });
      });
    });
    const ran = new Set(seen.map((x) => x.model));
    const noPrice = [...offered].filter((m) => !m.startsWith('opencode:') && !/^[a-z]{2,}$/.test(m) && !isModel(canon(m)) && !aliasTo.has(m) && !ran.has(m)).sort();
    const known = models.filter((m) => providerOf(m, over[m]) !== 'opencode').sort((a, b) => nameOf(a).localeCompare(nameOf(b)));
    const norm = (s) => s.toLowerCase().replace(/\./g, '-');
    const likely = (id) => {
      const t = norm(id.replace(/^.*\//, '').replace(/^(?:[a-z0-9-]+\.)*anthropic\./i, ''));
      return known.filter((m) => t.includes(norm(m))).sort((a, b) => b.length - a.length)[0] || '';
    };

    // ---- a row and its parts ----
    const field = (act, label, value, set, hint) => {
      const x = h('input', 'field rules-field');
      x.type = 'text'; x.dataset.act = act; x.value = value; x.setAttribute('aria-label', label);
      if (hint) x.placeholder = hint;
      x.addEventListener('input', () => set(x.value));
      return x;
    };
    // A price field: $, the box, "/ M tokens".
    const money = (act, t, value, set, hint) => {
      const w = h('label', 'rules-price-field');
      w.append(h('span', null, t), h('span', 'rules-price-affix', '$'), field(act, `${t} price, dollars per million tokens`, value, set, hint), h('span', 'rules-price-affix', '/ M tokens'));
      return w;
    };
    // This is…: the model an ID means, the likely one picked first, then a button that adds the ID as its alias.
    function thisIs(id) {
      const sel = h('select', 'field board-select');
      sel.dataset.act = 'price-this-model'; sel.setAttribute('aria-label', `The model ${id} is`);
      const pick = S.priceThis.has(id) ? S.priceThis.get(id) : likely(id);
      [['', 'Pick a model'], ...known.map((m) => [m, nameOf(m)])].forEach(([v, t]) => { const o = h('option', null, t); o.value = v; o.selected = v === pick; sel.append(o); });
      const go = button(pick ? `This is ${nameOf(pick)}` : 'This is…', 'btn-quiet', 'price-this', `Price ${id} as the model picked`, () => {
        const m = sel.value;
        if (!m) { say(`Pick the model ${id} is.`); return; }
        priceRun([['alias', m, 'add', id]], () => { S.priceThis.delete(id); });
      });
      sel.addEventListener('change', () => { S.priceThis.set(id, sel.value); go.textContent = sel.value ? `This is ${nameOf(sel.value)}` : 'This is…'; });
      return [sel, go];
    }
    const findOf = (m, more) => [m, nameOf(m), ...list(over[m] && over[m].aliases), ...(more || [])].join('\n').toLowerCase();
    const marks = (m) => [...(roles.get(m) || []).map((t) => S.ctx.chip(t, 'info')),
      ...(sessions.has(m) ? [S.ctx.chip(`${plural(sessions.get(m), 'session', 'sessions')} in 30 days`, 'quiet')] : [])];
    // The row open in Edit: display name and other IDs (not for an OpenCode model's own price), the four prices, and
    // Save, Cancel and Reset to built-in.
    function editRow(m, tr) {
      const ed = S.priceEdit, e = over[m] || {}, b = built.get(m), box = h('div', 'rules-price-editform');
      if (!ed.ratesOnly) {
        box.append(h('label', 'rules-price-field', 'Display name'), field('price-name', `Display name of ${m}`, ed.name, (v) => { ed.name = v; }, names[m] || m));
        const ids = h('div', 'rules-item rules-price-ids');
        ids.append(h('span', null, 'Other IDs:'));
        ed.aliases.forEach((x) => ids.append(h('span', 'rules-price-alias', x), button('×', 'btn-quiet', 'price-alias-drop', `${x} is not ${m}`, () => { ed.aliases = ed.aliases.filter((y) => y !== x); draw(); })));
        ids.append(field('price-alias-new', `Another model ID that is ${m}`, ed.alias, (v) => { ed.alias = v; }, 'proxy/model-id'), button('+ add', 'btn-quiet', 'price-alias-add', `Add the ID typed as ${m}`, () => {
          const x = ed.alias.trim(), to = aliasTo.get(x);
          const why = !MODEL.test(x) ? `"${x}" is not a model ID.` : x === m ? 'A model is not an alias of itself.' : isModel(x) ? `${x} is a model of its own.`
            : to && to !== m ? `${x} is already ${nameOf(to)}.` : null;
          if (why) { say(why); return; }
          if (!ed.aliases.includes(x)) ed.aliases.push(x);
          ed.alias = ''; draw();
        }));
        box.append(ids);
      }
      PRICE_KEYS.forEach(([k, t]) => box.append(money(`price-${k}`, t, ed[k], (v) => { ed[k] = v; }, k === 'cacheWrite' ? '1.25 × input' : '0')));
      box.append(button('Save', 'btn-quiet', 'price-save', `Save ${m}`, () => {
        const v = PRICE_KEYS.map(([k]) => String(ed[k]).trim()), shown = rateOf(m) || {}, changes = [];
        const same = RATES.every((k, i) => v[i] === (num(shown[k]) !== null ? String(shown[k]) : '')) && v[3] === (priced(e) && num(e.cacheWrite) !== null ? String(e.cacheWrite) : '');
        if (!same) {
          if (v.slice(0, 3).some((x) => !x)) { say('Give the input, output and cache read prices.'); return; }
          changes.push(['set', m, ...v.slice(0, 3), ...(v[3] ? [v[3]] : [])]);
        }
        if (!ed.ratesOnly) {
          const n = ed.name.trim(), had = typeof e.name === 'string' ? e.name : '', want = n && n !== (names[m] || m) ? n : '';
          if (want !== had) changes.push(want ? ['name', m, want] : ['name', m]);
          const was = list(e.aliases);
          ed.aliases.filter((x) => !was.includes(x)).forEach((x) => changes.push(['alias', m, 'add', x]));
          was.filter((x) => !ed.aliases.includes(x)).forEach((x) => changes.push(['alias', m, 'remove', x]));
        }
        if (!changes.length) { S.priceEdit = null; draw(); return; }
        priceRun(changes, () => { S.priceEdit = null; });
      }), button('Cancel', 'btn-quiet', 'price-cancel', `Close ${m} with nothing saved`, () => { S.priceEdit = null; draw(); }));
      if (priced(e) && b) box.append(resetButton(m, b));
      const td = h('td', null);
      td.colSpan = 7; td.append(h('strong', null, nameOf(m)), h('span', 'board-from', ` ${m}`), box);
      tr.classList.add('rules-price-editing');
      tr.append(td);
      return tr;
    }
    // Reset names the price that clearing m gives: the fast mode of a model with your price then costs twice that
    // price, not its built-in price (use_prices in dashboard_limit.py).
    const resetButton = (m, b) => {
      const fast = m.endsWith(':fast'), base = fast && over[m.slice(0, -5)], mine = fast && priced(base), to = mine ? twiceOf(base) : b;
      return button(`${fast ? 'Reset :fast' : 'Reset'} to ${mine ? 'twice your price' : 'built-in'} (${['input', 'output', 'cacheRead'].map((k) => usd(to[k])).join(' / ')} / ${usd(writeOf(to))})`, 'btn-quiet', fast ? 'price-fast-reset' : 'price-reset',
        `Put ${m} back to ${mine ? `twice your price of ${m.slice(0, -5)}` : 'its built-in price'}`, () => priceRun([['clear', m]], () => { if (S.priceEdit && S.priceEdit.model === m) S.priceEdit = null; }));
    };
    // from: the prices the fields start at, for a fast mode the pack does not price (its row's second line).
    const openEdit = (m, ratesOnly, from) => {
      const e = over[m] || {}, r = (ratesOnly ? (priced(e) ? e : from) : rateOf(m)) || {};
      S.priceEdit = { model: m, ratesOnly, name: typeof e.name === 'string' ? e.name : '', aliases: list(e.aliases).slice(), alias: '',
        ...Object.fromEntries(RATES.map((k) => [k, num(r[k]) !== null ? String(r[k]) : ''])), cacheWrite: priced(e) && num(e.cacheWrite) !== null ? String(e.cacheWrite) : '' };
      draw();
    };
    // A model's row: its name (bold), marks, ID and other IDs; its prices and where they are from; Edit, and Reset to
    // built-in for a price from the pack or Remove for an added model. Its fast mode is the second line of each cell.
    function row(m) {
      const tr = h('tr', 'rules-price');
      tr.dataset.model = m; tr.dataset.group = `price:${m}`; tr.dataset.find = findOf(m); tr.dataset.family = lineOf(m);
      if (S.priceEdit && S.priceEdit.model === m) return editRow(m, tr);
      if (S.priceEdit && S.priceEdit.model === `${m}:fast`) return editRow(`${m}:fast`, tr);
      const e = over[m] || {}, b = built.get(m), mine = priced(e), r = rateOf(m), added = !b && isModel(m);
      const fo = over[`${m}:fast`], fb = built.get(`${m}:fast`);
      // A fast mode the pack does not price, of a model it does, costs twice that price (use_prices in dashboard_limit.py).
      const fast = priced(fo) ? [fo, 'Saved, from the pack'] : mine && fb ? [twiceOf(e), 'twice your price'] : fb ? [fb, 'built in'] : null;
      const two = (main, second) => { const td = h('td', null); td.append(h('div', null, main)); if (fast) td.append(h('div', 'rules-price-fastline', second)); return td; };
      const name = h('td', 'rules-price-name');
      name.append(h('strong', null, nameOf(m)), ...(added ? [S.ctx.chip('added', 'quiet')] : []), ...marks(m),
        h('div', 'board-from', `${m}${list(e.aliases).length ? ` · also: ${list(e.aliases).join(', ')}` : ''}`));
      if (fast) name.append(h('div', 'rules-price-fastline', ':fast'));
      tr.append(name, ...PRICE_KEYS.map(([k]) => {
        const td = two(r ? usd(k === 'cacheWrite' ? writeOf(r) : r[k]) : '—', fast ? usd(k === 'cacheWrite' ? writeOf(fast[0]) : fast[0][k]) : '');
        td.className = 'num'; return td;
      }), two(mine || (added && r) ? 'Saved, from the pack' : r ? 'built in' : 'not priced', fast ? fast[1] : ''));
      const acts = h('td', 'rules-price-acts');
      acts.append(button('Edit', 'btn-quiet', 'price-edit', `Edit ${m}`, () => openEdit(m, false)));
      if (mine && b) acts.append(resetButton(m, b));
      // The fast mode's own price: Edit :fast saves it under <model>:fast; one from the pack has its own Reset.
      if (fast) acts.append(button('Edit :fast', 'btn-quiet', 'price-fast-edit', `Edit the fast mode price of ${m}`, () => openEdit(`${m}:fast`, true, fast[0])));
      if (priced(fo)) {
        acts.append(fb ? resetButton(`${m}:fast`, fb) : button('Remove :fast price', 'btn-quiet', 'price-fast-reset', `Take the fast mode price of ${m} off`,
          () => priceRun([['clear', `${m}:fast`]], () => { if (S.priceEdit && S.priceEdit.model === `${m}:fast`) S.priceEdit = null; })));
      }
      if (added) acts.append(button('Remove', 'btn-quiet', 'price-remove', `Remove ${m}`, () => priceRun([['remove', m]])));
      tr.append(acts);
      return tr;
    }
    const writeOrRate = (r, k) => (k === 'cacheWrite' ? writeOf(r) : r[k]);
    const twiceOf = (r) => Object.fromEntries(PRICE_KEYS.map(([k]) => [k, 2 * writeOrRate(r, k)]));
    // An OpenCode model: priced as OpenCode reports (the default), at your price, or as the model it is marked as.
    function ocRow(id) {
      const tr = h('tr', 'rules-price rules-price-oc');
      tr.dataset.model = id; tr.dataset.group = `price:${id}`; tr.dataset.find = findOf(id, [id.replace(/^opencode:/, '')]);
      if (S.priceEdit && S.priceEdit.model === id) return editRow(id, tr);
      const to = aliasTo.get(id), e = over[id], r = to ? rateOf(to) : priced(e) ? e : null;
      const name = h('td', 'rules-price-name');
      name.append(h('strong', null, id.replace(/^opencode:/, '')), ...(raw.has(id) ? [S.ctx.chip('in use', 'info')] : []));
      tr.append(name, ...PRICE_KEYS.map(([k]) => h('td', 'num', r ? usd(writeOrRate(r, k)) : '—')),
        h('td', null, to ? `${nameOf(to)}'s price` : priced(e) ? 'your price' : 'as OpenCode reports'));
      const acts = h('td', 'rules-price-acts');
      if (to) acts.append(button(`Not ${nameOf(to)}`, 'btn-quiet', 'price-oc-unalias', `Price ${id} as OpenCode reports again`, () => priceRun([['alias', to, 'remove', id]])));
      else if (priced(e)) acts.append(button('Back to OpenCode\'s', 'btn-quiet', 'price-oc-back', `Price ${id} as OpenCode reports again`, () => priceRun([['clear', id]])));
      else acts.append(button('Set my price', 'btn-quiet', 'price-oc-set', `Set your price of ${id}`, () => openEdit(id, true)), ...thisIs(id));
      tr.append(acts);
      return tr;
    }
    function tableOf(rows, heads) {
      const t = h('table', 'rules-prices-table'), top = h('tr', null);
      ['Model', ...PRICE_KEYS.map(([, x]) => x), 'Price from', ''].forEach((x) => top.append(h('th', null, x)));
      t.append(top);
      let fam = null;
      rows.forEach((tr) => {
        // A family's head (Opus, GPT) before its first row, in a group by provider.
        if (heads && tr.dataset.family !== fam) {
          fam = tr.dataset.family;
          const hr = h('tr', 'rules-price-family'), th = h('th', null, heads(tr.dataset.model));
          th.colSpan = 7; hr.dataset.family = fam; hr.append(th); t.append(hr);
        }
        t.append(tr);
      });
      return t;
    }
    function group(key, title, rows, older, olderTitle, heads) {
      const g = h('div', 'rules-price-group');
      g.dataset.priceGroup = key;
      g.append(h('h4', 'rules-price-title', title));
      if (rows.length) g.append(tableOf(rows, heads));
      if (older.length) {
        const d = h('details', 'rules-price-older');
        d.open = S.priceOpen.has(key);
        d.addEventListener('toggle', () => { if (d.open) S.priceOpen.add(key); else S.priceOpen.delete(key); });
        d.append(h('summary', null, `${olderTitle} (${older.length})`), tableOf(older, heads));
        g.append(d);
      }
      return g;
    }

    // ---- the section ----
    const top = h('div', 'rules-add rules-prices-top'), find = h('input', 'field rules-field rules-price-search');
    find.type = 'search'; find.dataset.act = 'price-search'; find.placeholder = 'Search a model or alias'; find.value = S.priceFind;
    find.setAttribute('aria-label', 'Search the models by ID, name or alias');
    find.addEventListener('input', () => { S.priceFind = find.value; filter(); });
    top.append(find, button('+ Add model', 'btn-quiet', 'price-add', 'Add a model the table has not got', () => { S.priceAdd = S.priceAdd || addDraft(''); draw(); }),
      h('span', 'board-from', '$ per million tokens. Saved in the pack.'));
    el.append(top);
    function addDraft(id) {
      return { model: id, name: id, provider: providerOf(id, null), input: '', output: '', cacheRead: '', cacheWrite: '' };
    }
    if (S.priceAdd) {
      const f = S.priceAdd, form = h('div', 'rules-price-editform rules-price-addform');
      form.dataset.group = 'price:add';
      const prov = h('select', 'field board-select');
      prov.dataset.act = 'price-add-provider'; prov.setAttribute('aria-label', 'Provider of the model');
      PROVIDERS.forEach(([k, t]) => { const o = h('option', null, t); o.value = k; o.selected = k === f.provider; prov.append(o); });
      prov.addEventListener('change', () => { f.provider = prov.value; });
      const same = h('select', 'field board-select');
      same.dataset.act = 'price-add-same'; same.setAttribute('aria-label', 'Same price as a model the table has');
      [['', 'Same price as…'], ...models.filter((m) => rateOf(m)).sort((a, b) => nameOf(a).localeCompare(nameOf(b))).map((m) => [m, nameOf(m)])]
        .forEach(([v, t]) => { const o = h('option', null, t); o.value = v; same.append(o); });
      same.addEventListener('change', () => {
        const r = same.value ? rateOf(same.value) : null;
        if (!r) return;
        RATES.forEach((k) => { f[k] = String(r[k]); });
        f.cacheWrite = num(r.cacheWrite) !== null && r.cacheWrite !== r.input * 1.25 ? String(r.cacheWrite) : '';
        draw();
      });
      form.append(h('strong', null, 'Add model'), field('price-add-model', 'Model ID, as sessions report it', f.model, (v) => { f.model = v; }, 'Model ID, as sessions report it'),
        field('price-add-name', 'Display name', f.name, (v) => { f.name = v; }, 'Display name'), prov,
        ...PRICE_KEYS.map(([k, t]) => money(`price-add-${k}`, t, f[k], (v) => { f[k] = v; }, k === 'cacheWrite' ? '1.25 × input' : '0')), same,
        button('Save', 'btn-quiet', 'price-add-save', 'Save this model in the pack', () => {
          const m = f.model.trim(), n = f.name.trim(), v = PRICE_KEYS.map(([k]) => f[k].trim());
          const why = !MODEL.test(m) ? 'Give the model ID, as sessions report it.' : isModel(m) || aliasTo.has(m) ? `${m} is priced already: use Edit on its row.`
            : !n || n.length > 60 ? 'Give a display name of up to 60 characters.' : v.slice(0, 3).some((x) => !x) ? 'Give the input, output and cache read prices.' : null;
          if (why) { say(why); return; }
          priceRun([['add', m, f.provider, n, ...v.slice(0, 3), ...(v[3] ? [v[3]] : [])]], () => { S.priceAdd = null; });
        }),
        button('Cancel', 'btn-quiet', 'price-add-cancel', 'Close Add model with nothing saved', () => { S.priceAdd = null; draw(); }));
      el.append(form);
    }
    if (unpriced.length) {
      const box = h('div', 'rules-prices-unpriced');
      box.append(h('h4', 'rules-price-title', 'Seen but not priced'));
      unpriced.forEach((x) => {
        const line = h('div', 'rules-item rules-unpriced');
        line.dataset.model = x.model; line.dataset.group = `price:${x.model}`; line.dataset.find = x.model.toLowerCase();
        line.append(h('span', null, `${x.model} (${plural(x.sessions, 'session', 'sessions')}${list(x.routes).includes('proxy') ? ', through the API proxy' : ''})`),
          ...thisIs(x.model), button('Add as new model', 'btn-quiet', 'price-new', `Add ${x.model} as a model of its own`, () => { S.priceAdd = addDraft(x.model); draw(); }));
        box.append(line);
      });
      el.append(box);
    }
    if (noPrice.length) {
      const box = h('div', 'rules-prices-noprice');
      box.append(h('h4', 'rules-price-title', 'Offered with no price'));
      noPrice.forEach((m) => {
        const line = h('div', 'rules-item rules-noprice');
        line.dataset.model = m; line.dataset.group = `price:${m}`; line.dataset.find = m.toLowerCase();
        const by = roles.get(m);
        line.append(h('span', null, `${m} (no price${by ? `; in use by ${by.join(', ')}` : ''})`),
          ...thisIs(m), button('Add as new model', 'btn-quiet', 'price-new', `Add ${m} as a model of its own`, () => { S.priceAdd = addDraft(m); draw(); }));
        box.append(line);
      });
      el.append(box);
    }
    const own = models.filter((m) => providerOf(m, over[m]) !== 'opencode');
    const used = own.filter(inUse).sort((a, b) => PROVIDERS.findIndex(([k]) => k === providerOf(a, over[a])) - PROVIDERS.findIndex(([k]) => k === providerOf(b, over[b])) || byFamily(a, b));
    if (used.length) el.append(group('use', 'In use by this project', used.map(row), [], ''));
    // Older: a built-in model with a newer one of its line (Opus 4.8 after Opus 5.5).
    const older = (m) => built.has(m) && own.some((x) => x !== m && built.has(x) && providerOf(x, over[x]) === providerOf(m, over[m]) && lineOf(x) === lineOf(m) && newer(x, m) < 0);
    [['claude', 'Claude', (m) => lineOf(m).replace(/^./, (x) => x.toUpperCase())], ['openai', 'OpenAI', () => 'GPT'], ['other', 'Other', null]].forEach(([k, t, heads]) => {
      const all = own.filter((m) => providerOf(m, over[m]) === k && !inUse(m)).sort(byFamily);
      if (!all.length) return;
      el.append(group(k, t, all.filter((m) => !older(m)).map(row), all.filter(older).map(row), `Older ${t} models`, heads));
    });
    // OpenCode: the models OpenCode can run on the build machine, and every OpenCode ID the pack or the steps name.
    const oc = new Set(models.filter((m) => providerOf(m, over[m]) === 'opencode'));
    ROLES.forEach((k) => { const s = ms[k], o = s && s.clis && s.clis.opencode; list(o && o.models).forEach((x) => { if (typeof x === 'string' && x) oc.add(`opencode:${x}`); }); });
    [...Object.keys(over), ...aliasTo.keys(), ...raw].forEach((x) => { if (typeof x === 'string' && x.startsWith('opencode:')) oc.add(x); });
    if (oc.size) {
      const ids = [...oc].sort(), shown = (x) => raw.has(x) || priced(over[x]) || aliasTo.has(x) || isModel(x);
      // A model added in the pack (it has a provider) is a model's row, with its name, Edit and Remove; an OpenCode ID
      // with only your price is an OpenCode row.
      const asModel = (x) => isModel(x) && (!x.startsWith('opencode:') || !!(over[x] && over[x].provider));
      const g = group('opencode', 'OpenCode', ids.filter(shown).map((x) => (asModel(x) ? row(x) : ocRow(x))),
        ids.filter((x) => !shown(x)).map(ocRow), 'All OpenCode models');
      g.append(h('p', 'board-from', 'An OpenCode step is priced as OpenCode reports, unless you set your price or mark its model as a known one.'));
      el.append(g);
    }
    el.append(h('p', 'board-from', 'With no cache write price, a 5-minute cache write costs 1.25 times the input price. A 1-hour cache write costs twice the input price.'));
    // The search: the rows, groups and family heads with no match hide; a folded group with a match opens.
    function filter() {
      const q = S.priceFind.trim().toLowerCase();
      el.querySelectorAll('[data-find]').forEach((r) => { r.hidden = !!q && !r.dataset.find.includes(q); });
      el.querySelectorAll('.rules-price-family').forEach((r) => {
        r.hidden = !!q && !Array.from(r.closest('table').querySelectorAll(`.rules-price[data-family="${r.dataset.family}"]`)).some((x) => !x.hidden);
      });
      el.querySelectorAll('.rules-price-group, .rules-prices-unpriced, .rules-prices-noprice').forEach((g) => { g.hidden = !!q && !g.querySelector('[data-find]:not([hidden])'); });
      if (q) el.querySelectorAll('details.rules-price-older').forEach((d) => { if (d.querySelector('[data-find]:not([hidden])')) d.open = true; });
    }
    filter();
    return el;
  }

  // Controls that change nothing (the search, the grouping, the issue filters and picks, and showing more) stay on while a change is out.
  const STILL = new Set(['held-search', 'held-by', 'held-link', 'list-more', 'list-all', 'pick', 'pick-all'].concat(IFILTERS));
  // While a change is out every other control is off, a page drawn by "Show more" too.
  const lock = (root) => { if (S.busy) root.querySelectorAll('button, input, select').forEach((b) => { if (!STILL.has(b.dataset.act)) b.disabled = true; }); };
  // The tab's panels, in their default order, each drawn from the one Rules part: [id, title, width, its sections].
  // Each has its own line (.rules-note: say) under its sections.
  const PANELS = [
    [PART, 'Rules', 'wide', (all) => [limitsLine(), head(), rules(all)]],
    [`${PART}-produce`, 'What these rules produce', 'small', (all) => [produce(all)]],
    [`${PART}-prices`, 'Model prices', 'full', () => [pricesSection()]],
    [HELD_P, HELD, 'full', (all) => [heldSection(all)]],
    [`${PART}-issues`, 'Open issues', 'full', () => [issuesSection()]],
  ];
  // Draws the tab's panels (only: the one panel with that id), each in the place the page gave it (S.at).
  function draw(only) {
    const h = S.ctx.h, at = Array.from(S.at).filter(([id]) => !only || id === only);
    // No record on the host's main, and another to pick (under Show in the machine head): nothing until one is picked.
    if (S.d.repo === null) {
      at.forEach(([, p]) => p.el.replaceChildren(S.ctx.state('empty', 'No rules to show', 'Conveyor did not run on this project on the build machine yet, so it has no rules. Pick a project under Show, above the tabs.')));
      return;
    }
    // The focus a control had comes back to the control with the same action (on the same issue, in the same group,
    // in the same panel), if it is still there. While a change is out its control is off and cannot take the focus: it
    // is kept, and given back when the controls are on again.
    const a = document.activeElement && document.activeElement.dataset ? document.activeElement : null;
    const from = a ? Array.from(S.at).find(([, p]) => p.el.contains(a)) : null;
    const item = from && a.closest('[data-issue]'), grp = from && a.closest('[data-group]');
    const keep = (from && a.dataset.act ? { panel: from[0], act: a.dataset.act, issue: item ? item.dataset.issue : null, group: grp ? grp.dataset.group : null } : null) || S.keep;
    S.keep = null;
    const all = held();
    at.forEach(([id, { el }]) => {
      if (!el.querySelector('.rules')) {
        const note = h('p', 'board-note rules-note');
        note.setAttribute('aria-live', 'polite');
        el.replaceChildren(h('div', 'rules'), note);
      }
      // "What these rules produce" scrolls inside when taller than the window (app.css): a new snapshot keeps its place.
      const was = el.querySelector('.rules-produce'), top = was ? was.scrollTop : 0;
      el.querySelector('.rules').replaceChildren(...PANELS.find((x) => x[0] === id)[3](all));
      const out = el.querySelector('.rules-produce');
      if (out) out.scrollTop = top;
      lock(el.querySelector('.rules'));
      S.shown.set(id, filtersOf(S.ctx));
    });
    const to = keep && at.find(([id]) => id === keep.panel);
    if (to) {
      const el = to[1].el;
      const scope = keep.group !== null && keep.group !== undefined ? Array.from(el.querySelectorAll('[data-group]')).find((g) => g.dataset.group === keep.group) : el;
      const again = scope && scope.querySelector(keep.issue ? `[data-issue="${keep.issue}"] [data-act="${keep.act}"]` : `[data-act="${keep.act}"]`);
      if (again && !again.disabled) again.focus({ preventScroll: true });
      else if (S.busy && again) S.keep = keep;
    } else if (keep && !from) S.keep = keep;  // kept for a panel not drawn now
  }
  // Each of the tab's panels works its length out again: rows came or went (a group opened, a search typed).
  const relength = () => S.at.forEach((p) => p.ctx.relength());

  // The part as text without the readAt of each project's view (the part's own and each of others'), worked out once a part.
  const noRead = (p) => (p && typeof p === 'object' && !Array.isArray(p) ? Object.assign({}, p, { readAt: undefined }) : p);
  function bareOf(d) {
    if (S.bareFor && S.bareFor[0] === d) return S.bareFor[1];
    const o = d && d.others && typeof d.others === 'object' ? Object.fromEntries(Object.entries(d.others).map(([k, v]) => [k, noRead(v)])) : undefined;
    const key = JSON.stringify(Object.assign(noRead(d) || {}, o ? { others: o } : {}));
    S.bareFor = [d, key];
    return key;
  }

  // A new snapshot is the record and what it produces. It replaces the record the host answered with once the
  // collector began it at or after the answer (both times are the page host's clock); one begun before it would show
  // the old value, however late it arrives (Judge On would show Off again), and is turned away while the answer stands
  // and after: the answer's time stays the floor. A snapshot's time is when it was published, not when its record was
  // read (the live feed republishes the record it last read), so one that still holds a value a setting changed here
  // replaced does not replace the answer either, whatever its time. An answer with no time is replaced by the next snapshot; a change
  // still out, by none. The part holds every project on the host: the one the address picks is drawn; another picked
  // starts with nothing selected, open or asked. A project's changes, answers and refusals are kept while another is
  // drawn; one whose answer a snapshot has replaced keeps that snapshot's record until one begun at or after the
  // answer, so picking it again does not show an older snapshot's value.
  // Every panel of the tab is drawn from the same part: the first of them to get a snapshot takes it and draws them
  // all; the others, given the same snapshot for the same project, draw only themselves.
  const render = (id) => (el, d, ctx) => {
    // This panel shows S.d already, with the filters the address holds now (Back or Forward can bring others).
    const drawn = S.at.has(id) && S.at.get(id).el === el && !!el.querySelector('.rules') && S.shown.get(id) === filtersOf(ctx);
    S.at.set(id, { el, ctx });
    // The panel acted in last (S.from), for the line that says what the action did (say): heard before the control's own handler.
    if (!S.heard.has(el)) { S.heard.add(el); ['click', 'input', 'change', 'keydown', 'drop'].forEach((t) => el.addEventListener(t, () => { S.from = id; }, true)); }
    const view = ctx.project(d), read = readOf(view, ctx);
    // The Rules show one project: with more than one on the host the Rules panel's heading names it, whatever Show says.
    if (id === PART) ctx.title(Array.isArray(view.repos) && view.repos.length > 1 && view.repo ? `Rules: ${view.repo}` : null);
    if (S.raw && S.raw[0] === d && S.raw[1] === read && S.raw[2] === view.repo) {
      // A panel that shows a part with the same content (S.idle: the part drew nothing) draws nothing either.
      if (drawn && S.idle === d) return;
      draw(id); return;
    }
    // A part that differs from the one drawn only in when its records were read (readAt, new on every refresh) draws
    // nothing while no change, turned-away snapshot or moved row waits on that time: drawing it again replaced an open
    // select (Group by) for the same content (issue 294). It is still the part drawn (S.raw).
    const key = bareOf(d);
    if (drawn && S.d && S.bare === key && view.repo === S.d.repo && !(S.ctl || S.turned || S.moved.size)) {
      S.raw = [d, read, view.repo]; S.d = view; S.read = read; S.ctx = ctx;
      S.idle = d;
      return;
    }
    S.idle = null;
    S.bare = key;
    S.raw = [d, read, view.repo];
    // The machine's steer, whichever project is drawn (only the part's top names it); null from an older engine.
    S.steer = d && typeof d.steer === 'boolean' ? d.steer : null;
    if (S.steerSent === S.steer) S.steerSent = null;
    S.cores = d && d.cores && typeof d.cores === 'object' && Array.isArray(d.cores.reserved) ? d.cores : null;
    if (S.d && view.repo !== S.d.repo) {
      S.picked.clear(); S.open.clear(); S.armed = null; S.asking = null; S.turned = false; S.dep = null;
      const pin = !S.ctl && S.floor !== null ? ctl() : null;
      S.kept.set(S.d.repo, { ctl: pin || S.ctl, ctlAt: pin ? S.floor : S.ctlAt, was: S.was, guessed: S.guessed, floor: S.floor, refused: S.refused });
      Object.assign(S, { ctl: null, ctlAt: null, was: {}, guessed: false, floor: null, refused: null }, S.kept.get(view.repo));
      S.kept.delete(view.repo);
    }
    S.ctx = ctx; S.read = read;
    if (S.d && !S.ctl && S.floor !== null && read !== null && read < S.floor) { S.turned = true; draw(); return; }
    const rec = view.control && typeof view.control === 'object' ? view.control : {};
    const stale = Object.keys(S.was).some((k) => same(rec[k], S.was[k]));
    if (S.ctl && !S.guessed && !stale && (S.ctlAt === null || (read !== null && read >= S.ctlAt))) {
      if (S.ctlAt !== null) S.floor = S.ctlAt;
      S.ctl = null; S.ctlAt = null; S.was = {};
    }
    S.d = view; S.turned = false;
    moveJudge(view, read);
    draw();
  };

  PANELS.forEach(([id, title, size]) => window.DASH_APP.panel({
    id,
    title,
    size,
    tab: 'rules',  // a tab of its own
    part: PART,
    rows: 'all',
    // Its rows: each rule, the figures, the next issues and each group of the held issues (so its length can be set).
    rowSelector: '.rules-row, .rules-stats, .rules-next, .rules-group',
    // The Rules tab says when the loop is paused, or the guard has paused it: the pause setting is here. Its first
    // panel counts it, once.
    attention: id === PART ? (d) => (d.state === 'paused' || d.state === 'paused by guard' ? 1 : 0) : undefined,
    isEmpty: (d) => d.repo === null && !(d.others && typeof d.others === 'object' && Object.keys(d.others).length),
    empty(el, ctx) { el.append(ctx.state('empty', 'No rules to show', 'Conveyor did not run on this project on the build machine yet, so it has no rules. Start Conveyor there, and they show here.')); },
    error(el, message, ctx) { el.append(ctx.state('error', 'The Board could not read the rules', message)); },
    render: render(id),
    // A part equal to the one drawn last, in a snapshot begun at another time, is weighed like any other while an
    // answer is shown or a snapshot was turned away (as the Board's).
    same(el, d, ctx) {
      const read = readOf(ctx.project(d), ctx);
      if ((S.ctl || S.turned || S.moved.size) && read !== S.read) render(id)(el, d, ctx);
    },
  }));
}());
