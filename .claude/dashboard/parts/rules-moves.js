// SPDX-License-Identifier: Apache-2.0
// The Rules tab's moves and controls: the issues an action moved, a change in words and as the record would hold it,
// the controls a rule's row is drawn with, what a change would skip, and the held issues. Part of panels/rules.js,
// which asks for it by name (DASH_APP.use) and gives it what it uses; boot.js loads it before the panels.
(() => {
  'use strict';
  // What this part uses of panels/rules.js, set when rules.js asks for the part (DASH_APP.part, at the end).
  let AREA, RELEASE_MAX, STANDING, ARM_MS, BUILDS, S, ONB, OB, num, list, ctl, plural, prio, pre, isArea,
    areaName, PRMERGE, undoOf, say, run, button, priceWords, draw;

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
  const own = (o, k) => Object.prototype.hasOwnProperty.call(o, k);
  // The words of each action's change (words), from its args a.
  const seatWords = (a, action) => `${action === 'model' ? 'builder' : 'reviewer'} ${a[0] === 'default' ? 'back to the default' : a.join(' ')}`;
  const accountWords = (a, action) => `${action === 'account' ? 'account' : 'review account'} ${a.length ? a[0] : 'back to the default'}`;
  const RULE_WORDS = { followups: 'Follow-ups', push: 'Push on landing', visible: 'Approve visible changes', lint: 'Lint check', failfast: "Stop a card's tests at the first failure", teststeponly: 'Only the Test step runs tests', split: 'Split large issues', pick: 'Pick settings', healsdays: 'Self-heals expiry days' };
  // The five switches of Cards with no GitHub issue (the record's rules.testissues, foremanissues, followupissues, releaseissues and
  // splitissues): each kind is On while its rule is off.
  const NOISSUE_WORDS = { testissues: 'Tests page actions', foremanissues: 'Foreman orders', followupissues: 'Review follow-ups', releaseissues: 'Release fix cards', splitissues: 'Split parts' };
  const WORDS = {
    rules: (a) => a.map((x) => { const [k, o] = x.split('='); return isArea(k) ? `${o === 'off' ? 'never build' : 'build'} ${k}`
      : own(NOISSUE_WORDS, k) ? `${NOISSUE_WORDS[k]} with no GitHub issue ${o === 'off' ? 'on' : 'off'}` : `${own(RULE_WORDS, k) ? RULE_WORDS[k] : k} ${o}`; }).join(', '),
    cap: (a) => (a[0] === 'off' ? 'at once: the default' : `at once ${a[0]}`),
    guard: (a) => (a[0] === 'off' ? 'pause at: off' : `pause at ${a[0]}%`),
    atonce: (a) => `parallel suite: ${a[0]} test file${a[0] === '1' ? '' : 's'} at once`,
    'suite-mode': (a) => `release suite ${a[0] === 'parallel' ? 'in parallel' : 'one by one'}`,
    'suite-machine': (a) => `release suite on ${a[0] === 'ssh' ? `${a[1]} over ssh` : a[0] === 'devbox' ? 'a Namespace Devbox' : 'this machine'}`,
    model: seatWords,
    reviewer: seatWords,
    judge: (a) => {
      if (a[0] === 'on' || a[0] === 'off') return `judge ${a[0]}`;
      if (a[0] === 'always') return a.length > 1 ? `judge always accepts ${a.slice(1).join(', ')}` : 'judge always accepts no kind';
      return `judge ${a[0] === 'default' ? 'back to the default' : a.join(' ')}`;
    },
    account: accountWords,
    'review-account': accountWords,
    release: (a) => (a.length === 1 ? `queued #${a[0]}` : `queued ${a.length} issues`),
    unlabel: (a) => `removed ${a.slice(1).join(', ')} from #${a[0]} and queued it`,
    unpin: (a) => `unpinned #${a[0]}`,
    order: (a) => (a.length ? `pinned order ${a.map((n) => `#${n}`).join(', ')}` : 'no pinned order'),
    start: (a) => `new issues start in ${a[0] === 'held' ? 'Held' : 'the Queue'}`,
    'dep-guard': (a) => `dependency guard ${a[0]}`,
    'land-as': (a) => (a[0] === 'pr' ? 'land as one pull request' : 'land on main'),
    'pr-merge': (a) => `merge the pull request ${PRMERGE[a[0]] || a[0]}`,
    'push-check': (a) => `test before a push ${a[0]}`,
    onboarded: () => 'setup finished',
    force: (a) => `build #${a[0]} before the issues it waits on land`,
    depends: (a) => `#${a[0]} ${a[1] === 'add' ? 'depends on' : 'no longer depends on'} ${a.slice(2).map((n) => `#${n}`).join(', ')}`,
    prices: (a) => priceWords(a),
    'pick-models': (a) => (a[1] === 'clear' ? `${a[0]}: all models, any effort` : `${a[0]}: ${a.slice(1).join(', ')}`),
    standing: (a) => `${(STANDING.find(([k]) => k === a[0]) || [a[0], a[0]])[1]} without asking: ${a[1]}`,
  };
  // A change in words, for the head.
  function words(action, args) {
    const a = list(args);
    return own(WORDS, action) ? WORDS[action](a, action) : action;
  }

  // What each action that is one setting changes in the record r (guessed), from its args a, and the row it is in.
  const seatGuess = (r, action, a) => {
    r[action] = a[0] === 'default' ? null : Object.assign({ cli: a[0], model: a[1] }, a[2] ? { effort: a[2] } : {});
    return [r, action === 'model' ? 'builder' : action];
  };
  const limitGuess = (r, action, a) => { r[action] = a[0] === 'off' ? null : Number(a[0]); return [r, action]; };
  const GUESS = {
    rules: (r, action, a) => rulesGuess(r, a),
    cap: limitGuess,
    guard: limitGuess,
    atonce: (r, action, a) => { r.suiteAtOnce = Number(a[0]); return [r, action]; },
    'suite-mode': (r, action, a) => { r.suiteMode = a[0]; return [r, action]; },
    'suite-machine': (r, action, a) => {
      const was = r.suiteMachine && typeof r.suiteMachine === 'object' ? r.suiteMachine : {};
      // An Undo of a devbox change sends the set-up time it had (--setup-at): the row drawn before the answer keeps it.
      const at = (k) => (a.includes(k) ? a[a.indexOf(k) + 1] : undefined);
      r.suiteMachine = a[0] === 'ssh' ? { kind: 'ssh', target: a[1], dir: a[3] || '~/conveyor-suite' }
        : a[0] === 'devbox' ? { kind: 'devbox', size: a[2] || '4x8', tag: was.kind === 'devbox' ? was.tag : undefined, idleStop: '15m', box: at('--box'), setupAt: at('--setup-at') } : { kind: 'local' };
      return [r, 'suite'];
    },
    judge: (r, action, a) => {
      if (a[0] === 'on' || a[0] === 'off') { r.judgeOn = a[0] === 'on'; return [r, 'judge']; }
      if (a[0] === 'always') { r.judgeAlways = a.slice(1); return [r, 'judge']; }
      if (a[0] === 'rare') { r.judgeRare = a[1] === 'none' ? [] : a.slice(1); return [r, 'judge']; }
      return seatGuess(r, action, a);
    },
    model: seatGuess,
    reviewer: seatGuess,
    account: (r, action, a) => { r.account = a[0] || null; return [r, 'account']; },
    'review-account': (r, action, a) => { r.reviewAccount = a[0] || null; return [r, 'review-account']; },
    start: (r, action, a) => { r.start = a[0]; return [r, 'start']; },
    'dep-guard': (r, action, a) => { r.depGuard = a[0] === 'on'; return [r, 'dep-guard']; },
    'land-as': (r, action, a) => { r.landAs = a[0]; return [r, 'land-as']; },
    'pr-merge': (r, action, a) => { r.prMerge = a[0]; return [r, 'pr-merge']; },
    'push-check': (r, action, a) => { r.pushCheck = a[0] === 'default' ? null : a[0] === 'on'; return [r, 'push-check']; },
    onboarded: (r, action, a) => { r.onboarded = { at: new Date(Date.now()).toISOString(), rules: a.slice() }; return [r, ONB]; },
  };
  // The rules changed by a `rules` action (guessed), and the row of the first.
  function rulesGuess(r, a) {
    const k = a.length ? String(a[0]).split('=')[0] : '';
    r.rules = r.rules && typeof r.rules === 'object' ? r.rules : {};
    a.forEach((x) => {
      const [key, o] = String(x).split('=');
      if (key === 'split' || key === 'pick') { r.rules[key] = o; return; } // Split large issues and Pick settings keep their word: off, shadow or on
      if (key === 'healsdays') { r.rules[key] = Number(o); return; } // the days an entry of the Self-heals list may go unfixed and unseen
      if (!isArea(key)) { r.rules[key] = o === 'on'; return; }
      const never = list(r.rules.never).filter((y) => y !== key);
      r.rules.never = o === 'off' ? never.concat([key]) : never;
    });
    return [r, isArea(k) ? 'never' : ['push', 'visible', 'lint', 'failfast', 'teststeponly', 'testissues', 'foremanissues', 'followupissues', 'releaseissues', 'splitissues', 'split', 'pick', 'healsdays'].includes(k) ? k : 'build'];
  }
  // A setting as the record would hold it once the host takes it, and the row it is in; null for an action that is
  // not one setting (release, order, unpin...): those show when the host answers.
  function guessed(c, action, a) {
    const r = JSON.parse(JSON.stringify(c));
    return own(GUESS, action) ? GUESS[action](r, action, a) : null;
  }

  // The tab's line: what was asked or done, with Undo after a change easily undone (undo sends its opposite). Each of
  // the tab's panels (PANELS) has its own: the line shows in the panel the action came from (where, by default S.from:
  // the panel last clicked or typed in), so a panel folded away never holds what another panel's action said, and
  // the other panels' lines are emptied.
  // The setup (ONB) has its own line, in its footer.
  const tabLine = (where = S.from) => (where === ONB ? (OB.box && OB.box.querySelector('.rules-note')) : S.at.has(where) ? S.at.get(where).el.querySelector('.rules-note') : null);
  // One action to the page's host, for the project named: {ok, said, rec, at}. at: when the page's host had the
  // answer (X-Answered-At: its clock, in whole seconds rounded up), in ms, or null.
  function post(action, args, repo) {
    return S.ctx.post('control', { action, args, repo }).then((r) => r.text().then((t) => {
      const said = String(t).trim();
      let rec;
      try { rec = JSON.parse(said); } catch { rec = null; }
      const at = Number(r.headers && typeof r.headers.get === 'function' ? r.headers.get('X-Answered-At') : NaN);
      return { ok: r.ok, said: said || `the host answered ${r.status}`, rec: rec && typeof rec === 'object' && typeof rec.mode === 'string' ? rec : null,
        at: Number.isFinite(at) && at > 0 ? at * 1000 : null };
    }));
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
    // Its mark holds the key: draw() takes it off once S.armed is another or none (the note is not drawn again).
    if (b) { b.textContent = undoLabel(skips); b.classList.add('board-danger'); b.dataset.armed = key; }
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
    if (on) b.dataset.armed = '';
    return b;
  }
  function choice(text, act, label, on, fn) {
    const b = button(text, 'rules-tog', act, label, fn);
    b.setAttribute('aria-pressed', String(on));
    return b;
  }
  // The choices of one rule as one segmented control: the pressed one is the value in force.
  function seg(label, ...choices) {
    const box = S.ctx.h('span', 'rules-seg');
    box.setAttribute('role', 'group'); box.setAttribute('aria-label', label);
    box.append(...choices);
    return box;
  }
  // The Judge row's "May decline as a rare case": one switch a level, pressed for each level of the record c's judgeRare,
  // and "no level" said when it has none. A click sends the levels whole (control judge rare), or none when it leaves no level.
  function judgeRare(c) {
    const h = S.ctx.h, LV = ['P0', 'P1', 'P2', 'P3'], rare = LV.filter((p) => list(c.judgeRare).includes(p));
    const to = (levels) => ['rare'].concat(levels.length ? levels : ['none']), box = h('span', 'rules-list');
    box.append(h('span', 'board-from', rare.length ? 'may decline as a rare case at' : 'may decline as a rare case at no level'),
      seg('May decline as a rare case', ...LV.map((p) => choice(p, `judge-rare-${p}`, `May decline a ${p} finding as a rare case: ${rare.includes(p) ? 'on' : 'off'}`,
        rare.includes(p), () => send('judge', to(LV.filter((x) => (x === p) !== rare.includes(x))), null, ['judge', to(rare)])))));
    return box;
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
      // The hold a split puts on its umbrella (split: true, lib/snapshot.sh) is the split's, not yours: not listed as held by you.
      const you = mine.has(x.issue) && !list(x.reasons).some((r) => r && r.kind === 'you' && r.split);
      // A row moved here stays, shown as moved, until a snapshot shows the move (moveJudge).
      if (!you && !holds.length && !pendingMove(x.issue)) return;
      const rest = others.filter((r) => r.kind !== 'label');
      // A split umbrella (its held entry's umbrella: its slices, or sliceCards: its slices that are cards with no GitHub
      // issue, whose umbrella is []) is never picked: a release would clear the hold and build nothing, so it has no
      // Queue here either (as on the Board's Held column, splitHold).
      const umbrella = list(x.umbrella).some((n) => num(n) !== null) || list(x.sliceCards).some((c) => c && typeof c.card === 'string');
      const how = umbrella ? null : holds.length ? (rest.length ? null : 'unlabel') : 'release';
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
  // Self-heals expiry: the days an entry of the Self-heals list may go unfixed, unfiled and unseen before it leaves the list
  // (the record's rules.healsdays, 1 to 3650). An engine whose record has none is sent none. Undo sends the days it had (undoOf).
  function rulesHeals(el, r) {
    const days = num(r.healsdays), to = (n) => () => send('rules', [`healsdays=${n}`]);
    el.append(row('healsdays', 'Self-heals expiry', 'days an entry of the Self-heals list can go unfixed and unseen before it leaves the list',
      days === null ? S.ctx.h('span', 'board-from', 'needs a newer Conveyor') : stepper('self-heals expiry days', String(days), to(days - 1), to(days + 1), days > 1, days < 3650)));
  }
  window.DASH_APP.part('rules-moves', function (shared) {
    ({ AREA, RELEASE_MAX, STANDING, ARM_MS, BUILDS, S, ONB, OB, num, list, ctl, plural, prio, pre, isArea,
      areaName, PRMERGE, undoOf, say, run, button, priceWords, draw } = shared);
    return { MOVES, moveOf, moveMark, readOf, moveJudge, moveNote, words, guessed, tabLine, post, send, undoSkips,
      undoLabel, undoAsk, guarded, choice, seg, judgeRare, pickList, stepper, row, wouldSkip, skipWords, fieldLabel, areaWould,
      held, unlisted, heldUnknown, groups, labelMark, matches, arm, queueOne, queueAll, rulesHeals };
  });
})();
