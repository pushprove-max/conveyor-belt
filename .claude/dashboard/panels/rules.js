// SPDX-License-Identifier: Apache-2.0
// The Rules tab (the owner chose R1's rules and their effect with R3's held issues grouped by
// area). It is a tab of its own, after Overview and Control, and carries the count
// of a paused loop, since the pause setting is here. Its one part is drawn as five panels (PANELS): Rules, What these
// rules produce, Model prices, the held issues and Open issues.
// Rules (the owner chose mockup B, indexed settings, #861): under the head, a search box and an index of six groups
// (SETS) on the left, the group picked on the right; with search text, every rule that matches, by group (index()).
// One row a rule, each with what it does and its control; a choice of two or more is one segmented control (seg).
// Models: Builder and Reviewer (CLI, model and effort), Judge (on or off, CLI, model and effort), Always accept (the
// finding kinds the judge always accepts, with the kinds the review prompt names to pick from), Account, Review account,
// Serena (the card sessions that start with Serena, a checkbox a role, with what the build machine found: parts/rules-suite.js).
// Capacity: Cards at once, Weekly pause (Off, 90%, 95%, 98%, beside the weekly limit's use), Test files at once (a
// stepper for the record's suiteAtOnce, 1 to 999; a note when it is above the machine's test slots, which it runs
// at; "needs a newer Conveyor" for a record without it), Release suite mode (the record's suiteMode: One by one or In parallel, what a release takes when its press names no mode; "needs a newer Conveyor" for a record without it), Release suite runs on (the record's suiteMachine: This
// machine, a Namespace Devbox or a Linux box over ssh, with Check the box; parts/rules-suite.js), Stop a card's tests at
// the first failure (the record's rules.failfast: On or Off; parts/rules-suite.js), Only the Test step runs tests (the
// record's rules.teststeponly: On or Off; parts/rules-suite.js), Reserved cores (shown, not
// set here: the machine's reserveCores, the cores it keeps and the test slots left, or why the machine cannot keep
// cores; with "Test limits are on the Tests page.", #520). Picking: Build issues (P0, P1, P2, P3, Follow-ups), Never
// build (the labels, each removable, and a field to add one, with the area labels of the open issues to pick from), New
// issues start in (Queue or Held), Dependency guard (On or Off; drawn disabled, "needs a newer engine", for a project
// whose control record has no depGuard), Split large issues (Off, Shadow or On; disabled the same way for a record with
// no rules.split; under it, a row for each of its four limits in force, for a snapshot with packSplit), Pick settings (Off, Shadow or On; disabled the same way for a record with no rules.pick; and each
// seat's allowed models, each with a checkbox and its lowest and highest effort, and Save, for a snapshot with packPick), Self-heals
// expiry (days), Card dollar limit and Issue dollar limit (Off or dollars; no row for a record without the limit). Landing
// and push: Push on landing (On or Off; disabled the same way for a record with no rules.push), Land as (Main or Pull
// request, the record's landAs or else the pack's; disabled the same way for a record with no landAs), Merge PR
// (Button, Release or Idle, the record's prMerge or else the pack's; disabled the same way for a record with no
// prMerge), Test before a push (On or Off: the record's pushCheck, else the pack's push.check; disabled the same way
// for a snapshot with no pushCheck), Push after a combined test run (On or Off: the record's rules.pushbatch, with
// when its run starts and which tests it runs, rules.pushbatchwhen and pushbatchtests; parts/rules-suite.js), Approve visible changes (On or Off; disabled the same way for a record with no
// rules.visible). Done without asking: one row a standing kind of routine yes the Foreman takes without asking (the
// pack's auto.standing: Requested fix, Review follow-up, Release check, Fixed block, Review retry, each On or Off;
// disabled the same way for a snapshot with no standing), then its group Cards with no GitHub issue (NOISSUE): Tests
// page actions (On or Off: On, a Tests page action starts its card with no GitHub issue, the record's rules.testissues
// false, #1330; disabled the same way for a record with no rules.testissues). Issue order: Held issues (the count, a link to the list
// below) and, when there is one, the pinned order, one row a pin with its title, dragged to a new place or moved by its
// menu's Move up (not on the first), Move down (not on the last) and Unpin.
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
// the guard's warning when the forecast says it pauses the loop before the queue ends, and the skipped issues. The
// waiting cards with no GitHub issue (cards) are counted and listed with the issues, each named by its kind: the ready
// ones in Next up where pick takes them, the others in the waiting and skipped lists, the held ones under Held by you
// or a label; more than five in one list fold to one row with their count. A title's text in backticks is a code span.
// When their record was not read, one line says so. When GitHub did not list the open issues, they show all the same.
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
// The setup (onboard: ONBOARD, drawOnboard), over whichever tab is shown (DASH_APP.overlay): while the project's control
// record has onboarded null, or a list without a rule of ONBOARD its engine has, a line above the panels with Set up,
// and a modal in steps, each rule's row as the Rules panel draws it, its default selected until it is set, with a
// "default: <value>" button. A rule is set once the host saved a choice of it (the default selected too, which sends
// the default); Next sets each rule of its step not set yet to its default; Later (or Escape) shuts it for this visit;
// Finish sends `onboarded` with the keys confirmed, those confirmed before too. A record with no onboarded key (an
// older engine, which cannot save it) is never asked.
// Its part (dashboard.sh, rules): {repo (null: no record is on the host's main), repoUrl, state, control, cap, guard,
// modelSettings, areaPrefix, packPick, limit, held, queue (each with areas), skipped, waits, cards, issuesError, building, onBelt, beltSteps, splitting,
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
    ['asked-fix', 'Requested fix','the Foreman files the fix you ask for and queues it at once'],
    ['review-followup', 'Review follow-up', 'a follow-up that only finishes or corrects a card you approved is queued'],
    ['release-check', 'Release check', 'a failed check in a release you asked for gets one fix card, then the release goes on'],
    ['fixed-block', 'Fixed block', 'a card blocked by a cause that a landed fix removed waits on that fix and is tried again'],
    ['review-retry', 'Review retry', 'the review blocks no card on a finding: the card lands, and the finding becomes a follow-up. A card that the records still show blocked by its review is tried again one time for each issue, with no turn of the Foreman, unless its reason names a reserved word or an item of your profile'],
  ];
  // A group of rows inside a group of the index (rulesIndexed()): its key, its name, then its rows (by their rule).
  const NOISSUE = ['noissue', 'Cards with no GitHub issue', 'testissues', 'foremanissues', 'followupissues', 'releaseissues', 'splitissues'];
  // The Rules panel's six groups, in the index's order: key, name, what it holds, and what it shows: a row (by its
  // rule) or a group of rows (NOISSUE) each.
  const SETS = [
    ['models', 'Models', 'Three seats for each card.', ['builder', 'reviewer', 'judge', 'judge-always', 'account', 'review-account', 'serena']],
    ['capacity', 'Capacity', 'Build slots and machine limits.', ['cap', 'guard', 'atonce', 'suite-mode', 'suite', 'failfast', 'teststeponly', 'cores']],
    ['picking', 'Picking', 'Choose which issues enter the belt.', ['build', 'never', 'start', 'dep-guard', 'split', 'split-donewhen', 'split-files', 'split-areas', 'split-chars', 'pick', 'healsdays', 'cardusd', 'issueusd']],
    ['landing', 'Landing and push', 'Decide how finished cards reach the repository.', ['push', 'land-as', 'pr-merge', 'push-check', 'pushbatch', 'lint', 'visible']],
    ['standing', 'Done without asking', 'Choose when the Foreman can act on your behalf.', STANDING.map(([k]) => `standing-${k}`).concat([NOISSUE])],
    ['order', 'Issue order', 'Inspect held issues and set the order of pinned work.', ['held', 'order']],
  ];
  const PINS_SHOWN = 5;  // the pins shown before "View remaining N pins"
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
    drafts: null, priceEdit: null, priceAdd: null, priceFind: '', priceSaved: new Map(), priceThis: new Map(), priceOpen: new Set(),
    standingSaved: new Map(), pickSaved: new Map(), splitSaved: new Map(), pickDraft: new Map(), cores: null, bare: null, bareFor: null, idle: null, shown: new Map(),
    ruleSet: 'models', ruleFind: '', pinsAll: false, pinMenu: null, dragPin: null, choosing: null };
  // choosing: the overlay's ctx.picking, kept from its last draw: true while the tab in view shows the project choice.
  // S.ctx.picking() cannot say it: a panel's own ctx says so for that panel, whichever tab is in view.
  // The setup of a repository not yet onboarded (drawOnboard()): its box and the line above the panels, once made; open;
  // later (Later pressed: shut for this visit); repo, the project it is for; keys, the rules it asks for, worked out
  // when it opens; set, the rules whose choice the host saved; rule, the rule of the row a box event is on (run());
  // out, the rule whose change is out; step, the step shown; back, the focus before it opened; act, the control of the
  // box focused last, focused again when a redraw replaced it.
  const ONB = 'onboard';
  const OB = { box: null, line: null, open: false, later: false, repo: null, keys: [], set: new Set(), rule: null, out: null, step: 0, back: null, act: null };
  // cores: the machine's cores kept for the user as
  // the snapshot says ({reserved, slots, unavailable}; null: an engine that does not say).
  // drafts: each project's roles picked here and not yet saved (draftOf), as DRAFT_KEY keeps them. Model prices
  // (pricesSection): priceEdit, the row open in Edit as typed; priceAdd, the Add model form as typed; priceFind, the
  // search typed; priceSaved, each project's pack prices as the changes saved here left them, by repo, until a snapshot
  // read after them (savedShown); priceThis, the model picked for each ID's This is…; priceOpen, the folded groups
  // opened. standingSaved, pickSaved and splitSaved, by repo too: the pack's standing kinds, its pick lists of Pick
  // settings and its limits of Split large issues, as a change saved here left them, until a snapshot read after it (savedShown);
  // pickDraft, each project's seat's models checked and ranges picked, not yet saved ("<repo> <seat>": {<model>: {min, max}}).
  // The Rules panel's index (index()), kept for this page only: ruleSet, the group picked (SETS); ruleFind, the search
  // typed. pinsAll: every pin shown; pinMenu, the pin whose menu is open; dragPin, the place of the pin being dragged.

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
  // Land as in force: the record's landAs, else the pack's push.landAs (packLandAs), else main. Known when the record
  // names landAs (null too: the pack's); an older engine is never sent `land-as`.
  const landNow = (c) => (c && (c.landAs === 'main' || c.landAs === 'pr') ? c.landAs : (S.d.packLandAs === 'pr' ? 'pr' : 'main'));
  const landKnown = () => { const c = ctl(); return !!c && Object.prototype.hasOwnProperty.call(c, 'landAs'); };
  // Merge PR in force: the record's prMerge, else the pack's push.prMerge (packPrMerge), else button. Known as Land as is.
  const PRMERGE = { button: 'with the Merge button', release: 'at the release', idle: 'when Conveyor is idle' };
  const prNow = (c) => (c && PRMERGE[c.prMerge] ? c.prMerge : (PRMERGE[S.d.packPrMerge] ? S.d.packPrMerge : 'button'));
  const prKnown = () => { const c = ctl(); return !!c && Object.prototype.hasOwnProperty.call(c, 'prMerge'); };
  // Whether the run before a push runs (pushcheck(), conveyor/lib/pushrun.sh): the record's pushCheck when it sets one,
  // else the pack's push.check as the snapshot gives it; on when neither says.
  const pushCheckOn = (c) => (c && typeof c.pushCheck === 'boolean' ? c.pushCheck : S.d.pushCheck !== false);
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
      return ['rules', a.map((x) => { const k = String(x).split('=')[0]; if (k === 'healsdays') return `${k}=${num(r.healsdays) === null ? 30 : r.healsdays}`; if (k === 'cardusd' || k === 'issueusd') return `${k}=${r[k] || 'off'}`; return `${k}=${isArea(k) ? (list(r.never).includes(k) ? 'off' : 'on') : r[k] === false ? 'off' : 'on'}`; })];
    }
    if (action === 'atonce') return num(c.suiteAtOnce) === null ? null : ['atonce', [String(c.suiteAtOnce)]];
    if (action === 'suite-mode') return ['suite-mode', [c.suiteMode === 'parallel' ? 'parallel' : 'serial']];
    if (action === 'suite-machine') return ['suite-machine', suite.undoArgs(c)];
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
    if (action === 'push-check') return ['push-check', [typeof c.pushCheck === 'boolean' ? (c.pushCheck ? 'on' : 'off') : 'default']];
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
  function say(text, undo, where = S.from) {
    S.at.forEach(({ el }, id) => { const n = el.querySelector('.rules-note'); if (n && id !== where) n.replaceChildren(); });
    const n = tabLine(where);
    if (n) n.replaceChildren(undo ? S.ctx.undoLine(text, undo) : text);
  }
  // Actions to the page's host, one after another and one batch at a time (as the Board's): while they are out the
  // controls are off. The first one refused stops the rest. what: the change in words, for the head. Every one names
  // the project on screen when they were asked for; an answer that comes after another project was picked is not shown.
  // A step is [action, args], or [action, args, saved]: saved() is called once the host saved that step, whatever the
  // later steps' answers and whichever project is on screen then. undo: the steps that undo these, for Undo on the line that says they were done (null: none), kept with them as the
  // last change here. to: the project they are for when it is not the one on screen: an Undo pressed after another
  // project was picked goes to the project the change was made in, never to the one picked since.
  function run(steps, what, done, undo, to) {
    if (S.busy) { say('Wait: the build machine did not answer the last change yet.'); return Promise.resolve(false); }
    // Its answer shows in the panel it was asked from, whatever panel is clicked while it is out.
    const where = S.from, tell = (text, u) => say(text, u, where);
    // From the setup: the rule of the row acted on (OB.rule) is set once the host saved each of these changes; a choice
    // there is the rule confirmed, and it has no Undo (its row may show the default rather than the value in force).
    const rule = where === ONB ? OB.rule : null;
    if (where === ONB) undo = null;
    OB.out = rule;
    S.busy = true; S.refused = null; draw();
    tell('Sending…');
    const repo = to || S.d.repo;
    // The project's snapshot the change was sent from, and when it was read: what a value saved here is laid over when
    // its answer comes after another project was picked.
    const sentFrom = repo === S.d.repo ? { d: S.d, read: S.read } : null;
    let i = 0;
    const next = () => {
      if (i >= steps.length) return Promise.resolve(true);
      const [action, args, saved] = steps[i];
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
        if (saved) saved();
        // A model price saved shows at once (pricesSection), its Undo's too. It stands until a snapshot begun at or
        // after the answer (savedShown): the pack is not an input of the snapshot, so one kept from before the change
        // is served for a while after it. It is kept for its project (by repo), whichever project is on screen when
        // the answer comes: picked again with a snapshot read before the answer, that project shows it.
        const [view, viewRead] = repo === S.d.repo ? [S.d, S.read] : sentFrom ? [sentFrom.d, sentFrom.read] : [null, null];
        if (action === 'prices' && view) S.priceSaved.set(repo, { repo, for: view.prices, at: res.at, over: applied(pricesShown(view, viewRead), list(args)) });
        // A standing kind saved shows at once too, as long.
        if (action === 'standing' && view) {
          const [k, o] = list(args);
          S.standingSaved.set(repo, { repo, for: view.standing, at: res.at,
            over: list(standingShown(view, viewRead)).filter((x) => x !== k).concat(o === 'on' ? [k] : []) });
        }
        // A seat's pick list saved shows at once too, as long (`pick models`: set or clear one seat's; each model's
        // word is <model>[=<min>-<max>], either bound empty for none).
        if (action === 'pick-models' && view) {
          const [k, ...ws] = list(args).map(String), over = Object.assign({}, pickShown(view, viewRead));
          if (ws[0] === 'clear') delete over[k];
          else {
            over[k] = {};
            ws.forEach((w) => {
              const at = w.indexOf('='), [mn, mx] = at < 0 ? ['', ''] : w.slice(at + 1).split('-');
              over[k][at < 0 ? w : w.slice(0, at)] = Object.assign({}, mn ? { min: mn } : {}, mx ? { max: mx } : {});
            });
          }
          S.pickSaved.set(repo, { repo, for: view.packPick, at: res.at, over });
        }
        if (action === 'split-limits' && view) splitSave(repo, view, viewRead, args, res.at);
        // The values the change replaced, kept from before the first change no snapshot has read yet: a snapshot that
        // still holds one did not read it, when the answer has no time (render). A setting the record holds at its old value again waits for nothing.
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
    const free = (ok) => { S.busy = false; OB.out = null; draw(); return ok; };
    return next().then((ok) => {
      if (ok) {
        if (rule && repo === OB.repo) OB.set.add(rule);
        lastWrite(what, undo || null, repo);
        if (done && repo === S.d.repo) done();
        tell('Done. What the rules produce updates in about a minute.', undo && undo.length && repo === S.d.repo ? () => undoAsk(undo, () => run(undo, `undid: ${what}`, null, null, repo), repo) : null);
      }
      return free(ok);
    }, () => { tell('Not done: the host did not answer.'); return free(false); });
  }

  // A split limit saved shows at once too, as long as a model price (run): `split-limits <limit>=<n | default>`; one set
  // to default shows the schema's default that the snapshot gave with it (packSplit's default).
  function splitSave(repo, view, viewRead, args, at) {
    const over = Object.assign({}, splitShown(view, viewRead));
    list(args).forEach((w) => {
      const [k, v] = String(w).split('='), d = over[k] && typeof over[k] === 'object' ? num(over[k].default) : null;
      over[k] = v === 'default' ? { n: d, from: 'default', default: d } : { n: Number(v), from: 'pack', default: d };
    });
    S.splitSaved.set(repo, { repo, for: view.packSplit, at, over });
  }

  function button(text, cls, act, label, fn) {
    const b = S.ctx.h('button', `btn ${cls || ''}`.trim(), text);
    b.type = 'button'; b.dataset.act = act; b.setAttribute('aria-label', label || text);
    b.addEventListener('click', fn);
    return b;
  }

  // ---- the held issues: held by you (the control record) or by a label ----
  // Their name everywhere on this tab: the two of the Board's four "not being built" states they are (the other two,
  // Skipped by a rule and Waiting on another card, are counted apart).
  const HELD = 'Held by you or a label';
  const IFILTERS = ['iq', 'istate', 'iprio', 'iarea', 'ilabel', 'isort', 'idir'];
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
    // Held by you is the record's hold, whatever state shows first (a blocked or building issue may be held too). A
    // split umbrella is never queued: a release would clear the split's hold and build nothing (openIssues, split).
    const group = {
      hold: picked.filter((x) => !x.mine), release: picked.filter((x) => x.mine && !x.split),
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

  // Where the Machine section was (#462): one line. The test limits are on the Tests page (#520).
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
      if (armed.length) { b.classList.add('board-danger'); b.dataset.armed = ''; }
      line.append(b);
    }
    p.append(h('span', null, 'The Board saves a rule when you change it. It saves the Builder, Reviewer and Judge models when you press Save.'), line);
    return p;
  }
  const CAP0 = 6;  // the cap of control-defaults.json (CAP0 in paths.sh)
  // The box and the line, made once: the box over the page, the line above the panels.
  function onbMake() {
    const h = S.ctx.h;
    OB.line = h('p', 'onboard-line');
    OB.line.id = 'onboard-line';
    OB.line.append(h('span', null, 'Conveyor is not set up for this repository yet.'),
      button('Set up', 'btn-primary', 'onboard-open', 'Set up Conveyor for this repository', () => { OB.later = false; drawOnboard(true); }));
    const grid = document.getElementById('grid');
    if (grid) grid.before(OB.line); else document.body.append(OB.line);
    OB.box = h('div', 'onboard-back');
    OB.box.id = 'onboard';
    const dlg = h('div', 'onboard'), title = h('h2', 'onboard-title'), note = h('p', 'board-note rules-note');
    dlg.setAttribute('role', 'dialog'); dlg.setAttribute('aria-modal', 'true'); dlg.setAttribute('aria-labelledby', 'onboard-title');
    title.id = 'onboard-title';
    note.setAttribute('aria-live', 'polite');
    const foot = h('div', 'onboard-foot');
    foot.append(h('span', 'onboard-count'), button('Later', 'btn-quiet', 'onboard-later', 'Later: close the setup for this visit', () => onbClose(true)),
      button('Back', 'btn-quiet', 'onboard-back', 'Back to the step before', () => { OB.step -= 1; onbDraw(); onbFocusStep(); }),
      button('Next', 'btn-primary', 'onboard-next', 'Next step', onbNext));
    dlg.append(title, h('ol', 'onboard-steps'), h('progress', 'onboard-bar'), h('div', 'onboard-body'), note, foot);
    OB.box.append(dlg);
    OB.box.hidden = true;
    document.body.append(OB.box);
    // Every action here says what it did on the box's own line, and a change it sends is on the rule of its row
    // (OB.rule): the rule is set only when the host saved it (run()), so a check that sends nothing, a first click
    // that asks again, a draft or a refusal does not set it.
    // The Always accept row is part of the Judge's rule (onbDefault sets the kinds with it): a change there sets the
    // Judge, so Next does not send the Judge's defaults over the kinds just added.
    ['click', 'input', 'change', 'keydown'].forEach((t) => {
      dlg.addEventListener(t, (e) => {
        S.from = ONB;
        const row = e.target.closest && e.target.closest('.rules-row'), k = row ? row.dataset.rule : null;
        OB.rule = k === 'judge-always' ? 'judge' : k;
      }, true);
      dlg.addEventListener(t, () => { OB.rule = null; });
    });
    // The control focused last, focused again when a redraw replaced it (onbDraw).
    dlg.tabIndex = -1;
    dlg.addEventListener('focusin', (e) => { if (e.target.dataset && e.target.dataset.act) OB.act = e.target.dataset.act; });
    // A click on the choice shown selected of a rule not yet set, its default, sends the default: the Rules tab's
    // control sends nothing for the value in force. A selected Build choice (each is, at the default) keeps the
    // default too, rather than turning that choice off: once the rule is set, a click toggles it as on the Rules tab.
    // The Judge's rare-case levels are not part of its default: a pressed level is the record's, and a click takes it out.
    const body = dlg.querySelector('.onboard-body');
    body.addEventListener('click', (e) => {
      const b = e.target.closest && e.target.closest('.rules-tog[aria-pressed="true"]:not([data-act^="judge-rare-"])'), row = b && b.closest('.rules-row');
      if (!row || b.disabled || OB.set.has(row.dataset.rule)) return;
      e.stopPropagation();
      onbConfirm(row.dataset.rule, row.querySelector('.board-label').textContent);
    }, true);
    // A control that sends nothing (a first click that asks again) is drawn again.
    body.addEventListener('click', () => { if (OB.open) onbDraw(); });
    // Escape is Later; Tab stays in the box.
    dlg.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') { e.preventDefault(); onbClose(true); return; }
      if (e.key !== 'Tab') return;
      const all = onbFocusable();
      if (!all.length) return;
      const at = all.indexOf(document.activeElement);
      if (e.shiftKey && at <= 0) { e.preventDefault(); all[all.length - 1].focus(); } else if (!e.shiftKey && at === all.length - 1) { e.preventDefault(); all[0].focus(); }
    });
  }

  // Controls that change nothing (the searches, the grouping, the rules' index, the issue filters and picks, and showing
  // more) stay on while a change is out.
  const STILL = new Set(['held-search', 'held-by', 'held-link', 'list-more', 'list-all', 'pick', 'pick-all', 'rules-find', 'pins-all']
    .concat(IFILTERS, SETS.map(([k]) => `rules-set-${k}`)));
  // While a change is out every other control is off, a page drawn by "Show more" too.
  const lock = (root) => { if (S.busy) root.querySelectorAll('button, input, select').forEach((b) => { if (!STILL.has(b.dataset.act)) b.disabled = true; }); };
  // The tab's panels, in their default order, each drawn from the one Rules part: [id, title, width, its sections].
  // Each has its own line (.rules-note: say) under its sections.
  const PANELS = [
    [PART, 'Rules', 'full', (all) => [head(), index(rules(all))]],
    [`${PART}-produce`, 'What these rules produce', 'small', (all) => [produce(all)]],
    [`${PART}-prices`, 'Model prices', 'full', () => [pricesSection()]],
    [HELD_P, HELD, 'full', (all) => [heldSection(all)]],
    [`${PART}-issues`, 'Open issues', 'full', () => [issuesSection()]],
  ];
  // An Undo on a note line armed by undoAsk whose arming ended (timed out, or another armed): the page's reload waits
  // on each [data-armed].
  function disarmOld() {
    [...Array.from(S.at.values(), (p) => p.el), OB.box].forEach((el) => {
      if (el) el.querySelectorAll('.rules-note [data-act="undo"][data-armed]').forEach((b) => {
        if (b.dataset.armed !== S.armed) { delete b.dataset.armed; b.classList.remove('board-danger'); b.textContent = 'Undo'; }
      });
    });
  }
  // Draws the tab's panels (only: the one panel with that id), each in the place the page gave it (S.at).
  function draw(only) {
    // Show at every project: a panel shows the project choice (its own ctx says so; S.ctx may be the setup's), and no
    // draw (a reply that came back, the suite machine's check) puts a project over it. The setup is drawn all the same.
    const h = S.ctx.h, at = Array.from(S.at).filter(([id, p]) => (!only || id === only) && !p.ctx.picking());
    disarmOld();
    // No record on the host's main, and another to pick (under Show in the machine head): nothing until one is picked.
    if (S.d.repo === null) {
      at.forEach(([, p]) => p.el.replaceChildren(S.ctx.state('empty', 'No rules to show', 'Conveyor did not run on this project on the build machine yet, so it has no rules. Pick a project under Show, above the tabs.')));
      drawOnboard();
      return;
    }
    // The setup over every tab is drawn from the same record (a change sent from it or from the tab shows in both).
    // Not while the tab in view shows the project choice: a reply that came back after a switch to it (key 4) opened
    // the setup over the choice.
    if (!only && !(S.choosing && S.choosing())) drawOnboard();
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
    refocus(at, keep, from);
  }
  // The control that had the focus (keep) has it again, if it is still in a panel drawn now (at); one in a panel
  // not drawn now (from is empty) is kept for later.
  function refocus(at, keep, from) {
    const to = keep && at.find(([id]) => id === keep.panel);
    if (to) {
      const el = to[1].el;
      const scope = keep.group !== null && keep.group !== undefined ? Array.from(el.querySelectorAll('[data-group]')).find((g) => g.dataset.group === keep.group) : el;
      let again = scope && scope.querySelector(keep.issue ? `[data-issue="${keep.issue}"] [data-act="${keep.act}"]` : `[data-act="${keep.act}"]`);
      // Save and Cancel of Pick settings are off once nothing is left to save: the focus goes to the setting's switch.
      if (scope && (!again || again.disabled) && /^pick-(save|cancel)$/.test(keep.act)) again = scope.querySelector('[data-rule="pick"] [aria-pressed="true"]');
      if (again && !again.disabled) again.focus({ preventScroll: true });
      else if (S.busy && again) S.keep = keep;
    } else if (keep && !from) S.keep = keep;  // kept for a panel not drawn now
  }
  // Each of the tab's panels works its length out again: rows came or went (a group opened, a search typed).
  const relength = () => S.at.forEach((p) => p.ctx.relength());
  // What the parts of this file hold (parts/rules-*.js; boot.js loads them before the panels): each is given what
  // it uses from here and from the parts before it, and gives back what the others use.
  const shared = { AREA, KIND, MODEL, KINDS_MAX, RELEASE_MAX, DEPENDS_MAX, STANDING, SETS, PINS_SHOWN, ARM_MS,
    KNOWN_KINDS, GUARDS, BUILDS, ROLES, OTHER, BY, HELD_P, S, ONB, OB, num, list, ctl, same, plural, prio, pre,
    isArea, areaName, depKnown, landNow, landKnown, PRMERGE, prNow, prKnown, pushCheckOn, why, undoOf, draftOf,
    draftPut, draftDrop, say, run, button, HELD, IFILTERS, limitsLine, CAP0, onbMake, lock, draw, relength };
  Object.assign(shared, window.DASH_APP.use('rules-prices', shared));
  Object.assign(shared, window.DASH_APP.use('rules-moves', shared));
  const suite = window.DASH_APP.use('rules-suite', shared);
  Object.assign(shared, suite);
  Object.assign(shared, window.DASH_APP.use('rules-rows', shared));
  Object.assign(shared, window.DASH_APP.use('rules-produce', shared));
  Object.assign(shared, window.DASH_APP.use('rules-setup', shared));
  const { MOVES, moveMark, readOf, moveJudge, guessed, tabLine, post, send, undoSkips, undoLabel, undoAsk, guarded,
    held, rules, index, produce, heldSection, STATES, ISORTS, filtersOf, openIssues, issueChoice, shownIssues,
    pinnedFirst, bulk, issueRow, savedShown, standingShown, pickShown, splitShown, pricesShown, applied, pricesSection,
    onbConfirm, onbFocusable, onbClose, onbFocusStep, onbNext, onbDraw, drawOnboard } = shared;

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
    const view = ctx.project(d);
    // The Rules show one project: with more than one on the host the Rules panel's heading names it, whatever Show says.
    if (id === PART) ctx.title(Array.isArray(view.repos) && view.repos.length > 1 && view.repo ? `Rules: ${view.repo}` : null);
    take(d, ctx, id, drawn);
  };
  // A snapshot d, from the panel id (drawn: it shows S.d already), or from the setup over every tab (id null).
  function take(d, ctx, id, drawn) {
    const view = ctx.project(d), read = readOf(view, ctx);
    if (S.raw && S.raw[0] === d && S.raw[1] === read && S.raw[2] === view.repo) {
      // A panel that shows a part with the same content (S.idle: the part drew nothing) draws nothing either.
      if (drawn && S.idle === d) return;
      draw(id || undefined); return;
    }
    // A part that differs from the one drawn only in when its records were read (readAt, new on every refresh) draws
    // nothing while no change, turned-away snapshot, moved row or value saved here (savedShown) waits on that time:
    // drawing it again replaced an open select (Group by) for the same content (issue 294). It is still the part drawn (S.raw).
    const key = bareOf(d);
    const saved = S.d && (savedShown(S.standingSaved.get(S.d.repo), S.d.standing) || savedShown(S.priceSaved.get(S.d.repo), S.d.prices)
      || savedShown(S.pickSaved.get(S.d.repo), S.d.packPick) || savedShown(S.splitSaved.get(S.d.repo), S.d.packSplit));
    if (drawn && S.d && S.bare === key && view.repo === S.d.repo && !(S.ctl || S.turned || S.moved.size || saved)) {
      S.raw = [d, read, view.repo]; S.d = view; S.read = read; S.ctx = ctx;
      S.idle = d;
      suite.suiteAgain(ctl());
      return;
    }
    S.idle = null;
    S.bare = key;
    S.raw = [d, read, view.repo];
    // The machine's cores kept, whichever project is drawn (only the part's top names them); null from an older engine.
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
    // A snapshot begun at or after the answer read the record after the change: a replaced value it holds was set
    // again since (by the command), and is shown. With no time for the answer, one that holds a replaced value is
    // taken as read before the change.
    const fresh = S.ctlAt === null ? !Object.keys(S.was).some((k) => same(rec[k], S.was[k])) : read !== null && read >= S.ctlAt;
    if (S.ctl && !S.guessed && fresh) {
      if (S.ctlAt !== null) S.floor = S.ctlAt;
      S.ctl = null; S.ctlAt = null; S.was = {};
    }
    S.d = view; S.turned = false;
    moveJudge(view, read);
    draw();
  }

  PANELS.forEach(([id, title, size]) => window.DASH_APP.panel({
    id,
    title,
    size,
    tab: 'rules',  // a tab of its own
    part: PART,
    // The Rules panel takes the grid's whole width: in a column beside another panel its label columns left a rule's
    // help a word a line (#1038). A kept layout's other width for it is read as full.
    widths: id === PART ? ['full'] : undefined,
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
  // The setup opens over whichever tab is shown: the part the Rules tab drew already is not taken again. A part not
  // read hides it.
  window.DASH_APP.overlay({
    part: PART,
    draw(d, ctx) {
      // With the project choice shown (no ?project= and more than one project), the project left in ?repo= is not
      // the one in view: no setup opens over the choice.
      S.choosing = ctx.picking;
      if (!d || ctx.picking()) { if (OB.box) { OB.open = false; OB.box.hidden = true; OB.line.hidden = true; } return; }
      // A project picked under Show since (the same part, another project of it) is taken: the setup is for it.
      if (S.raw && S.raw[0] === d && S.raw[2] === ctx.project(d).repo) { drawOnboard(); return; }
      take(d, ctx, null, false);
    },
  });
}());
