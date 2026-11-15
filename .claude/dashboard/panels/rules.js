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
// Off; disabled the same way for a record with no rules.visible), Held by you (the count, a link to the list below)
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
// Model prices: the built-in prices and the pack's overrides, each override set or removed
// here (pricesSection). Held by you or a label: the issues held by you (the control record) or by a label (awaiting-deploy),
// one line a group (by area by default, or by priority or holding label): its name, count and how
// many a label holds. Groups start closed, largest first; one opens to five issues, then "Show 5 more"
// and "Show all (M)" (the page's shared long list). Queue releases an issue the record holds; on one a label holds it removes the label
// and queues it, as the Board's "Remove the label and queue it", after saying so with a first click. Queue
// all asks once, naming the count and how many a label holds, and leaves those out unless asked. A search by number
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
// blocked, forecast, prices, open (with issues: every open issue), repos, others}.
(function () {
  'use strict';
  const AREA = /^[A-Za-z0-9._/-]{1,60}$/;  // the name after the pack's area prefix, as dashboard_server.py's RULE takes it
  const KIND = /^[A-Za-z0-9][A-Za-z0-9_-]{0,39}$/;  // a finding kind the judge always accepts, as dashboard_server.py's KIND takes it
  const MODEL = /^[A-Za-z0-9][A-Za-z0-9._:/@[\]-]{0,191}$/;  // a role's model, as dashboard_server.py's MODEL takes it
  const KINDS_MAX = 20;   // the kinds one `judge always` takes (dashboard_server.py)
  const RELEASE_MAX = 50; // the issues one release takes (dashboard_server.py)
  const DEPENDS_MAX = 20; // the issues one depends takes (dashboard_server.py)
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
    open: new Set(), armed: null, unarm: null, asking: null, withLabels: false, unlabeled: new Set(), picked: new Set(), waitsOpen: false, dep: null, depText: '',
    drafts: null, price: null };  // price: the Model prices form as typed (pricesSection); drafts: each project's roles picked here and not yet saved (draftOf), as DRAFT_KEY keeps them

  const num = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : null);
  const list = (v) => (Array.isArray(v) ? v : []);
  const ctl = () => S.ctl || (S.d.control && typeof S.d.control === 'object' ? S.d.control : null);
  const same = (a, b) => JSON.stringify(a === undefined ? null : a) === JSON.stringify(b === undefined ? null : b);
  const plural = (k, one, many) => `${k} ${k === 1 ? one : many}`;
  const prio = (x) => (/^P[0-3]$/.test(x && x.priority) ? x.priority : 'P3');
  // The pack's area prefix, as the snapshot gives it; null from one without it: then no area is read or sent.
  const pre = () => (typeof S.d.areaPrefix === 'string' && S.d.areaPrefix ? S.d.areaPrefix : null);
  const isArea = (k) => typeof k === 'string' && pre() !== null && k.startsWith(pre());
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

  // A change in words, for the head.
  function words(action, args) {
    const a = list(args);
    if (action === 'rules') return a.map((x) => { const [k, o] = x.split('='); return isArea(k) ? `${o === 'off' ? 'never build' : 'build'} ${k}` : `${k === 'followups' ? 'Follow-ups' : k === 'push' ? 'Push when a card lands' : k === 'visible' ? 'Visible changes need your yes' : k} ${o}`; }).join(', ');
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
    if (action === 'prices') return a[0] === 'set' ? `price of ${a[1]}: $${a[2]} input, $${a[3]} output, $${a[4]} cache read` : `price override of ${a[1]} removed`;
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
      return [r, isArea(k) ? 'never' : k === 'push' || k === 'visible' ? k : 'build'];
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
      return post(action, args, repo).then((res) => {
        if (!res.ok) { back(res.said, res.at); tell(`Not done: ${S.ctx.refusal(res.said)}${steps.length > 1 ? ` (${i - 1} of ${steps.length} sent)` : ''}`); return false; }
        put({ guessed: false });
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
      }, (e) => { back('the host did not answer', null); throw e; });
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
      if (!you && !holds.length) return;
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
    return key ? key.slice(pre().length) : 'No area';
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
    send('unlabel', [String(x.issue)].concat(x.holds), () => { S.unlabeled.add(x.issue); });
  }
  // Queue a whole group: the ones the record holds, in batches; with the labelled ones, their labels removed one by one.
  function queueAll(g, withLabels) {
    const free = g.items.filter((x) => x.how === 'release' && !S.unlabeled.has(x.issue)).map((x) => String(x.issue));
    const labelled = withLabels ? g.items.filter((x) => x.how === 'unlabel' && !S.unlabeled.has(x.issue)) : [];
    const steps = [];
    for (let i = 0; i < free.length; i += RELEASE_MAX) steps.push(['release', free.slice(i, i + RELEASE_MAX)]);
    labelled.forEach((x) => steps.push(['unlabel', [String(x.issue)].concat(x.holds)]));
    S.asking = null; S.withLabels = false;
    if (!steps.length) { draw(); say('You cannot queue anything in this group from here.'); return; }
    run(steps, `queued ${plural(free.length + labelled.length, 'issue', 'issues')} of ${g.name}`, () => { labelled.forEach((x) => S.unlabeled.add(x.issue)); });
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
    if (S.unlabeled.has(x.issue)) { li.classList.add('is-pending'); li.append(h('span', 'board-from board-sent', 'Label removed: it goes into the queue in about a minute.')); }
    else if (x.how === 'release') li.append(button('Queue', 'btn-quiet', 'queue', `Queue ${t}: release it from the hold`, () => queueOne(x)));
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
      h('span', 'board-from', x.areas.length ? x.areas.map((a) => a.slice(pre().length)).join(', ') : 'no area'));
    list(x.labels).filter((l) => !isArea(l)).forEach((l) => li.append(S.ctx.chip(l, 'quiet')));
    li.append(h('span', 'board-from rules-age', Number.isNaN(t0) ? 'age not known' : `${S.ctx.dur((Date.now() - t0) / 1000)} old`),
      S.ctx.chip(stateWord(x), { blocked: 'bad', you: 'warn', label: 'warn', next: 'ok', building: 'info' }[x.state] || 'quiet'));
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
      S.ctx.params({ iq: search.value });
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
      sel('iarea', 'Filter the open issues by area', [['', 'Any area']].concat(areas.map((a) => [a, a.slice(pre().length)])), v.area),
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

  // Model prices: every model the built-in table or the pack's overrides price (the part's prices), with its price in $
  // per million tokens and where it is from; an override wins over the built-in row, and over the built-in row of its
  // fast mode. Change fills the form with a
  // row's model and price; Save sends `prices set` (the host checks each value and says why it refuses one), and
  // Remove override sends `prices clear`. Each has Undo, which puts back the override it replaced, or takes it off.
  const PRICE_KEYS = [['input', 'Input'], ['output', 'Output'], ['cacheRead', 'Cache read']];
  function pricesSection() {
    const h = S.ctx.h, p = S.d.prices && typeof S.d.prices === 'object' ? S.d.prices : null, el = h('section', 'rules-prices');
    el.append(h('h3', 'board-head', 'Model prices'));
    if (!p) { el.append(h('p', 'unknown', 'The model prices were not read.')); return el; }
    const over = p.overrides && typeof p.overrides === 'object' ? p.overrides : {};
    const built = new Map(list(p.builtIn).filter((x) => x && typeof x.model === 'string').map((x) => [x.model, x]));
    const restore = (m) => (over[m] ? ['prices', ['set', m, ...PRICE_KEYS.map(([k]) => String(over[m][k]))]] : ['prices', ['clear', m]]);
    el.append(h('p', null, 'Dollars per million tokens. Cache writes follow the built-in multipliers. Your override is saved in the pack (.conveyor/project.json) and wins over the built-in price.'),
      h('p', null, 'OpenCode steps keep the cost OpenCode reports.'));
    const table = h('table', 'rules-prices-table'), top = h('tr', null);
    ['Model', ...PRICE_KEYS.map(([, t]) => t), 'Price from', ''].forEach((t) => top.append(h('th', null, t)));
    table.append(top);
    [...new Set([...built.keys(), ...Object.keys(over)])].sort().forEach((m) => {
      // A fast mode the pack does not override, of a model it does, costs twice that override (use_prices and
      // estimate in dashboard_limit.py): its built-in row is no longer used.
      const base = m.endsWith(':fast') ? m.slice(0, -5) : null, twice = !over[m] && base && !base.includes(':') && over[base]
        ? Object.fromEntries(PRICE_KEYS.map(([k]) => [k, num(over[base][k]) !== null ? 2 * over[base][k] : null])) : null;
      const r = over[m] || twice || built.get(m), tr = h('tr', 'rules-price');
      tr.dataset.model = m;
      tr.append(h('td', null, m), ...PRICE_KEYS.map(([k]) => h('td', 'num', num(r[k]) !== null ? `$${r[k]}` : '—')), h('td', null, over[m] ? 'your override' : twice ? `twice your override of ${base}` : 'built in'));
      const acts = h('td', null);
      acts.append(button('Change', 'btn-quiet', 'price-edit', `Change the price of ${m}`, () => {
        S.price = { model: m, ...Object.fromEntries(PRICE_KEYS.map(([k]) => [k, num(r[k]) !== null ? String(r[k]) : ''])) }; draw();
      }));
      if (over[m]) acts.append(button('Remove override', 'btn-quiet', 'price-clear', `Remove your price of ${m}`, () => send('prices', ['clear', m], null, restore(m))));
      tr.append(acts);
      table.append(tr);
    });
    const f = S.price || (S.price = { model: '', input: '', output: '', cacheRead: '' }), form = h('div', 'rules-add rules-price-form');
    [['model', 'Model', 'claude-opus-5-5'], ...PRICE_KEYS.map(([k, t]) => [k, t, '0'])].forEach(([k, t, hint]) => {
      const x = h('input', 'field rules-field');
      x.type = 'text'; x.placeholder = hint; x.dataset.act = `price-${k}`; x.value = f[k];
      x.setAttribute('aria-label', k === 'model' ? 'The model to price' : `${t} price, dollars per million tokens`);
      x.addEventListener('input', () => { f[k] = x.value; });
      form.append(h('label', null, t), x);
    });
    form.append(button('Save', 'btn-quiet', 'price-save', 'Save this model price as your override', () => {
      const v = ['model', ...PRICE_KEYS.map(([k]) => k)].map((k) => f[k].trim());
      if (v.some((x) => !x)) { say('Give the model and its three prices.'); return; }
      send('prices', ['set', ...v], null, restore(v[0])).then((ok) => { if (ok) { S.price = null; draw(); } });
    }));
    el.append(table, form);
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
    S.at.set(id, { el, ctx });
    // The panel acted in last (S.from), for the line that says what the action did (say): heard before the control's own handler.
    if (!S.heard.has(el)) { S.heard.add(el); ['click', 'input', 'change', 'keydown', 'drop'].forEach((t) => el.addEventListener(t, () => { S.from = id; }, true)); }
    const read = typeof ctx.updatedAt === 'function' ? ctx.updatedAt() : null;
    const view = ctx.project(d);
    // The Rules show one project: with more than one on the host the Rules panel's heading names it, whatever Show says.
    if (id === PART) ctx.title(Array.isArray(view.repos) && view.repos.length > 1 && view.repo ? `Rules: ${view.repo}` : null);
    if (S.raw && S.raw[0] === d && S.raw[1] === read && S.raw[2] === view.repo) { draw(id); return; }
    S.raw = [d, read, view.repo];
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
    S.d = view; S.turned = false; S.unlabeled.clear();
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
      const read = typeof ctx.updatedAt === 'function' ? ctx.updatedAt() : null;
      if ((S.ctl || S.turned) && read !== S.read) render(id)(el, d, ctx);
    },
  }));
}());
