// SPDX-License-Identifier: Apache-2.0
// The Rules tab's setup of a repository not yet onboarded. Part of panels/rules.js, which asks for it by name
// (DASH_APP.use) and gives it what it uses; boot.js loads it before the panels.
(() => {
  'use strict';
  // What this part uses of panels/rules.js, set when rules.js asks for the part (DASH_APP.part, at the end).
  let BUILDS, S, ONB, OB, num, list, ctl, landNow, pushCheckOn, words, run, button, held, rules, CAP0, onbMake,
    lock;

  // ---- the setup of a repository not yet onboarded ----
  // Its five steps, each the project's rules it asks for, by their row in rules(). The machine's rule (Reserved
  // cores) is the build machine's, not the repository's, and the pack's own setup answers stay
  // with /conveyor-belt:setup: neither is asked here.
  const ONBOARD = [
    ['What to build', ['build', 'never', 'split']],
    ['Landing', ['land-as', 'push', 'push-check', 'dep-guard', 'start']],
    ['Models', ['builder', 'reviewer', 'judge', 'account', 'review-account']],
    ['Limits', ['cap', 'guard']],
    ['Your yes', ['visible']],
  ];
  const GUARD0 = 98;  // the guard of control-defaults.json
  // A rule the project's engine has: one whose switch is drawn disabled for an older engine (rules()) is not asked.
  function onbHas(k, c) {
    const r = c.rules && typeof c.rules === 'object' ? c.rules : {};
    if (k === 'push' || k === 'visible') return typeof r[k] === 'boolean';
    if (k === 'split') return ['off', 'shadow', 'on'].includes(r.split);
    if (k === 'dep-guard') return typeof c.depGuard === 'boolean';
    if (k === 'land-as') return Object.prototype.hasOwnProperty.call(c, 'landAs');
    if (k === 'push-check') return typeof S.d.pushCheck === 'boolean';
    return true;
  }
  // The rules the record c does not say were confirmed. An engine whose record has no onboarded key cannot save the
  // setup: it is never asked there.
  const onbTodo = (c) => (c && Object.prototype.hasOwnProperty.call(c, 'onboarded')
    ? ONBOARD.flatMap(([, ks]) => ks).filter((k) => onbHas(k, c) && !list(c.onboarded && c.onboarded.rules).includes(k)) : []);
  const onbSteps = () => ONBOARD.map(([name, ks]) => [name, ks.filter((k) => OB.keys.includes(k))]).filter(([, ks]) => ks.length);
  // The repository as owner/repo, from its GitHub address (repoUrl); else the project's name.
  function onbSlug() {
    const x = /^https:\/\/github\.com\/([^/]+\/[^/]+)$/.exec(typeof S.d.repoUrl === 'string' ? S.d.repoUrl : '');
    return x ? x[1] : S.d.repo;
  }
  // Each rule's default, in words; the changes that set it, sent as the Rules tab sends them, whatever the record holds
  // (none only for a Never build list that is empty already: no command sets it); and the record c with the rule at
  // its default, as the box shows it until it is set (control-defaults.json: a record with no setting).
  function onbDefault(k, c) {
    const r = c.rules && typeof c.rules === 'object' ? c.rules : {}, m = S.d.modelSettings || {};
    const at = (o, rules) => Object.assign({}, c, o, rules ? { rules: Object.assign({}, r, rules) } : {});
    const role = (key) => { const s = m[key] && typeof m[key] === 'object' ? m[key] : {}; return s.default || (s.modelFrom === 'seed' ? s.model : null) || 'the pack\'s model'; };
    return onbRuleDefault(k, r, at) || onbSettingDefault(k, at, role);
  }
  // onbDefault of a rule of the record's rules (r): What to build, Never build, Push on landing, Approve visible
  // changes, Split large issues; null for another. at: the record with that rule at its default.
  function onbRuleDefault(k, r, at) {
    if (k === 'build') return [BUILDS.map(([, n]) => n).join(', '), [['rules', BUILDS.map(([b]) => `${b}=on`)]], at({}, Object.fromEntries(BUILDS.map(([b]) => [b, true])))];
    if (k === 'never') {
      const n = list(r.never), steps = [];
      for (let i = 0; i < n.length; i += 10) steps.push(['rules', n.slice(i, i + 10).map((a) => `${a}=on`)]);
      return ['none', steps, at({}, { never: [] })];
    }
    if (k === 'push' || k === 'visible') return ['Off', [['rules', [`${k}=off`]]], at({}, { [k]: false })];
    // Split large issues: on, as control-defaults.json has it.
    if (k === 'split') return ['On', [['rules', ['split=on']]], at({}, { split: 'on' })];
    return null;
  }
  // onbDefault of a setting that is not one of the record's rules. role(key): a seat's default model, in words.
  function onbSettingDefault(k, at, role) {
    if (k === 'dep-guard') return ['On', [['dep-guard', ['on']]], at({ depGuard: true })];
    // Land as and Test before a push: the pack's value, which a record with no setting takes.
    if (k === 'land-as') { const v = landNow(null); return [v === 'pr' ? 'Pull request' : 'Main', [['land-as', [v]]], at({ landAs: null })]; }
    if (k === 'push-check') { const v = pushCheckOn(null); return [v ? 'On' : 'Off', [['push-check', [v ? 'on' : 'off']]], at({ pushCheck: null })]; }
    if (k === 'start') return ['Queue', [['start', ['queue']]], at({ start: 'queue' })];
    if (k === 'builder') return [role('builder'), [['model', ['default']]], at({ model: null })];
    if (k === 'reviewer') return [role('reviewer'), [['reviewer', ['default']]], at({ reviewer: null })];
    // The judge's default is on, on its default model, and always accepting no kind.
    if (k === 'judge') return [`On, ${role('judge')}`, [['judge', ['on']], ['judge', ['default']], ['judge', ['always']]], at({ judgeOn: true, judge: null, judgeAlways: [] })];
    if (k === 'account') return ['the build machine\'s own login', [['account', []]], at({ account: null })];
    if (k === 'review-account') return ['the Account', [['review-account', []]], at({ reviewAccount: null })];
    if (k === 'cap') return [(S.d.control || {}).cap == null && num(S.d.cap) !== null ? String(S.d.cap) : String(CAP0), [['cap', ['off']]], at({ cap: null })];
    return [`${GUARD0}%`, [['guard', [String(GUARD0)]]], at({ guard: GUARD0 })];
  }
  // Confirms rule k at its default: its changes sent, from the setup; none to send sets it at once.
  function onbConfirm(k, name) {
    const [, steps] = onbDefault(k, ctl());
    if (!steps.length) { OB.set.add(k); onbDraw(); return; }
    S.from = ONB; OB.rule = k;
    run(steps, `${name}: the default`);
    OB.rule = null;
  }
  const onbFocusable = () => Array.from(OB.box.querySelectorAll('.onboard button, .onboard select, .onboard input')).filter((x) => !x.disabled && !x.hidden);
  function onbClose(later) {
    if (later) OB.later = true;
    OB.open = false;
    OB.box.hidden = true;
    // The focus goes back where it was before the box opened, else to Set up while it shows.
    const to = OB.back && OB.back.isConnected && OB.back !== document.body ? OB.back : !OB.line.hidden ? OB.line.querySelector('button') : null;
    if (to) to.focus({ preventScroll: true });
  }
  // The first control of the step shown takes the focus.
  function onbFocusStep() {
    const first = OB.box.querySelector('.onboard-body button:not([disabled]), .onboard-body select:not([disabled]), .onboard-body input:not([disabled])');
    if (first) first.focus({ preventScroll: true });
  }
  // Next (Finish on the last step): each rule of the step not set yet is first set to its default, as its "default:"
  // button sets it, in one batch; the step moves on only once the host saved them all.
  function onbNext() {
    const steps = onbSteps(), [name, ks] = steps[OB.step], repo = S.d.repo;
    const todo = ks.filter((k) => !OB.set.has(k)), sends = todo.flatMap((k) => onbDefault(k, ctl())[1]);
    const go = () => {
      todo.forEach((k) => OB.set.add(k));
      if (OB.step < steps.length - 1) { OB.step += 1; onbDraw(); onbFocusStep(); return; }
      // Finish: the rules confirmed now and those confirmed before, sent as one action.
      const c = ctl(), done = list(c && c.onboarded && c.onboarded.rules).filter((k) => typeof k === 'string' && !OB.keys.includes(k));
      run([['onboarded', done.concat(OB.keys)]], words('onboarded'));
    };
    if (!sends.length) { go(); return; }
    S.from = ONB; OB.rule = null;
    run(sends, `${name}: the defaults`).then((ok) => { if (ok && repo === OB.repo && repo === S.d.repo) go(); });
  }
  // The step shown: each rule's row as the Rules tab draws it, with its default; the steps, the count and the buttons.
  function onbDraw() {
    const h = S.ctx.h, c = ctl(), steps = onbSteps(), dlg = OB.box.querySelector('.onboard');
    OB.step = Math.max(0, Math.min(OB.step, steps.length - 1));
    const [, keys] = steps[OB.step];
    const a = OB.act;
    dlg.querySelector('.onboard-title').textContent = `Set up Conveyor for ${onbSlug()}`;
    const set = (k) => OB.set.has(k);
    dlg.querySelector('.onboard-steps').replaceChildren(...steps.map(([name, ks], i) => {
      const li = h('li', `onboard-step${ks.every(set) ? ' onboard-done' : ''}`, `${i + 1}. ${name}`);
      if (i === OB.step) li.setAttribute('aria-current', 'step');
      return li;
    }));
    const n = OB.keys.filter(set).length, bar = dlg.querySelector('.onboard-bar');
    bar.max = OB.keys.length; bar.value = n;
    bar.setAttribute('aria-label', `Step ${OB.step + 1} of ${steps.length}: ${steps[OB.step][0]}`);
    // A rule not yet set (nor out) shows its default selected, not the value in force: the rows are drawn from the
    // record with each such rule at its default.
    const keep = S.ctl;
    S.ctl = OB.keys.filter((k) => !set(k) && k !== OB.out).reduce((x, k) => onbDefault(k, x)[2], c);
    let rows;
    try { rows = new Map(Array.from(rules(held()).querySelectorAll('.rules-row'), (r) => [r.dataset.rule, r])); } finally { S.ctl = keep; }
    dlg.querySelector('.onboard-body').replaceChildren(h('h3', 'board-head', steps[OB.step][0]), ...keys.filter((k) => rows.has(k)).map((k) => {
      const row = rows.get(k), [text] = onbDefault(k, c), name = row.querySelector('.board-label').textContent;
      row.dataset.set = String(set(k));
      row.querySelector('.rules-key').append(
        button(`default: ${text}`, 'btn-quiet onboard-default', `onboard-default-${k}`, `${name}: the default, ${text}`, () => onbConfirm(k, name)),
        set(k) ? S.ctx.chip('Set', 'ok') : h('span', 'board-from', 'Click a choice to set it'));
      // The Judge's setup rule sets its always-accepted kinds too (onbDefault): their row, drawn apart on the Rules
      // tab, comes with it, as part of that one rule.
      const always = k === 'judge' && rows.get('judge-always');
      return always ? [row, always] : [row];
    }).flat());
    lock(dlg.querySelector('.onboard-body'));
    dlg.querySelector('.onboard-count').textContent = `${n} of ${OB.keys.length} rules set`;
    const last = OB.step === steps.length - 1, next = dlg.querySelector('[data-act="onboard-next"]');
    next.textContent = last ? 'Finish' : 'Next';
    next.setAttribute('aria-label', last ? 'Finish the setup' : 'Next step');
    next.disabled = S.busy;
    dlg.querySelector('[data-act="onboard-back"]').disabled = OB.step === 0;
    // The focus stays in the box: on the control focused last, drawn again; while that one is off (a change out), on
    // the box itself, so Escape and Tab still work, and back on the control when it is on again.
    const again = a && dlg.querySelector(`[data-act="${a}"]`);
    if (again && !again.disabled) again.focus({ preventScroll: true });
    else if (!dlg.contains(document.activeElement)) dlg.focus({ preventScroll: true });
  }
  // The line, while the project is not onboarded; the box over it, unless Later shut it for this visit. ask: Set up was
  // pressed.
  function drawOnboard(ask) {
    if (!S.ctx || !S.d) return;
    if (!OB.box) onbMake();
    // Another project: the box of the one before is shut (its controls would send to this one), then asked anew.
    if (OB.repo !== S.d.repo) {
      Object.assign(OB, { repo: S.d.repo, open: false, later: false, keys: [], set: new Set(), rule: null, out: null, step: 0, act: null });
      OB.box.hidden = true;
    }
    const c = S.d.repo !== null ? ctl() : null, todo = c ? onbTodo(c) : [];
    OB.line.hidden = !todo.length;
    if (!todo.length) { if (OB.open) onbClose(false); return; }
    if (OB.open) { onbDraw(); return; }
    if (OB.later) return;
    OB.keys = todo; OB.open = true; OB.box.hidden = false;
    OB.back = ask ? OB.line.querySelector('button') : document.activeElement;
    onbDraw();
    onbFocusStep();
  }
  window.DASH_APP.part('rules-setup', function (shared) {
    ({ BUILDS, S, ONB, OB, num, list, ctl, landNow, pushCheckOn, words, run, button, held, rules, CAP0, onbMake,
      lock } = shared);
    return { onbConfirm, onbFocusable, onbClose, onbFocusStep, onbNext, onbDraw, drawOnboard };
  });
})();
