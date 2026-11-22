// SPDX-License-Identifier: Apache-2.0
// The Rules panel: one row a rule (with the controls of a role and of an account), in groups with their index and
// search. Part of panels/rules.js, which asks for it by name (DASH_APP.use) and gives it what it uses; boot.js loads
// it before the panels.
(() => {
  'use strict';
  // What this part uses of panels/rules.js, set when rules.js asks for the part (DASH_APP.part, at the end).
  let KIND, MODEL, KINDS_MAX, STANDING, SETS, PINS_SHOWN, KNOWN_KINDS, GUARDS, BUILDS, ROLES, OTHER, S, ONB, OB,
    num, list, ctl, same, plural, pre, isArea, depKnown, landNow, landKnown, PRMERGE, prNow, prKnown, pushCheckOn,
    draftOf, draftPut, draftDrop, say, send, button, choice, seg, pickList, stepper, row, wouldSkip, skipWords,
    fieldLabel, areaWould, unlisted, heldUnknown, arm, limitsLine, standingShown, pickShown, CAP0, draw, relength, rulesSuite, suiteSlots;

  // ---- left: one row a rule ----
  // A role: its CLI (one of those installed on the loop's host, s.clis; the judge's the reviewer's too), then a model
  // from that CLI's list with the pack's models for it added, each once, then Other… for a name typed in (a
  // text box alone for a CLI with neither list), then an effort of those the CLI takes there. A model in force that
  // the list does not have is said to be "(not listed)". A pick sends nothing: the row says Unsaved, and Save sends
  // the CLI, model and effort as one action (Default clears the role); Cancel puts back what is in force. In the setup a
  // pick that leaves a whole role, or a model typed in and left, is saved at once.
  // A role the host cannot start (s.missing: its CLI gone) says so; a judge on the reviewer's CLI says it is of the
  // reviewer's family.
  function modelCtl(name, key, s) {
    const h = S.ctx.h, box = h('span', 'rules-model');
    const M = modelState(name, key, s);
    const pick = cliPick(M), { model, field } = modelPick(M), effort = effortPick(M);
    modelButtons(M);
    modelMark(M);
    box.append(pick, model, ...(field ? [field] : []), effort, M.flag, M.save, M.cancel, M.was);
    if (M.missing) box.append(S.ctx.chip(`cannot start: ${M.missing}`, 'bad'));
    if (key === 'judge' && reviewerFamily(M.s)) box.append(h('span', 'board-from', 'same family as the reviewer'));
    return box;
  }
  const ownKey = (o, k) => Object.prototype.hasOwnProperty.call(o, k);
  // An OpenCode model is in force as opencode:<provider>/<model>; OpenCode lists it, and the record holds it, without the mark.
  const bare = (c, m) => (c === 'opencode' && typeof m === 'string' ? m.replace(/^opencode:/, '') : m);
  const opt = (sel, value, text, on) => { const o = S.ctx.h('option', null, text); o.value = value; o.selected = on; sel.append(o); };
  // An installed CLI c (o: what it offers) offers its own models with the pack's models for it (s.allowed) after them,
  // each once: the pack's list adds models to the CLI's and does not replace it; then Other… for a name typed in. One
  // with neither list takes a typed name.
  const cliModels = (s, c, o) => (!o ? [] : Array.from(new Set(list(o.models)
    .concat(list(s.allowed && typeof s.allowed === 'object' ? s.allowed[c] : null)).filter((m) => typeof m === 'string' && m))));
  // The role key (name: its words) of modelCtl as one object M: the role in force (s, missing), what is picked here and
  // not yet saved (v, the draft, kept across redraws, tabs and reloads), and the CLI picked (cli, of) with its models.
  function modelState(name, key, s0) {
    const action = key === 'builder' ? 'model' : key;
    const { s, missing } = roleInForce(key, action, s0);
    const clis = s.clis && typeof s.clis === 'object' ? s.clis : {};
    const setCli = s.modelFrom === 'control' && s.agent ? s.agent : '';
    const setModel = setCli ? bare(setCli, s.model) || '' : '';
    const setEffort = setModel && s.effortFrom === 'control' && s.effort ? s.effort : '';
    const now = { cli: setCli, model: setModel, effort: setEffort, other: false };
    const v = draftOf(key) || now;
    const cli = v.cli;
    const of = cli && clis[cli] && typeof clis[cli] === 'object' ? clis[cli] : null;
    const listed = cliModels(s, cli, of);
    const allowed = of && !Array.isArray(of.models) ? listed : [];
    return { name, key, action, s, missing, clis, setCli, setModel, setEffort, now, v, cli, of, listed, allowed, typed: typedModel(v, of, listed, allowed) };
  }
  // Whether the model picked (v) is typed in: Other… picked, a model the CLI's list (listed) lacks, or a CLI (of) with
  // no list of its own and none from the pack (allowed).
  const typedModel = (v, of, listed, allowed) => !!of && (v.other || (v.model !== '' && !listed.includes(v.model)) || (!Array.isArray(of.models) && !allowed.length));
  // The role s as in force, and why the host cannot start it (missing, from the snapshot). A record the host answered
  // with since the snapshot says what is set here (as the Board's). A role the host took since the snapshot is one it
  // can start.
  function roleInForce(key, action, s) {
    let missing = typeof s.missing === 'string' && s.missing ? s.missing : null;
    if (S.ctl && ownKey(S.ctl, action)) {
      if (!same(S.ctl[action], (S.d.control || {})[action])) missing = null;
      s = heldRole(key, action, s);
    }
    return { s, missing };
  }
  // The role s as the record the host answered with sets it. The judge's role counts when it names its CLI (the
  // reviewer's too; one no longer installed is shown as set, and as unable to start) or, named by its model alone, a
  // model of its choices, as on the host; left at default it runs on s.default, which the snapshot names whatever is set.
  function heldRole(key, action, s) {
    const set = S.ctl[action] && typeof S.ctl[action] === 'object' ? S.ctl[action] : null;
    const r = set && (key !== 'judge' || set.cli || list(s.choices).includes(set.model)) ? set : null;
    return Object.assign({}, s, {
      model: r ? r.model : (s.modelFrom === 'seed' ? s.model : (s.default || null)), modelFrom: r ? 'control' : 'seed',
      effort: r && r.effort ? r.effort : (s.effortFrom === 'seed' ? s.effort : null), effortFrom: r && r.effort ? 'control' : 'seed',
      agent: r && r.cli ? r.cli : s.agent,
    });
  }
  const modelUnsaved = (M) => { const d = draftOf(M.key); return !!d && (d.cli !== M.setCli || d.model.trim() !== M.setModel || d.effort !== M.setEffort); };
  // A change o to the draft of M's role: one that comes back to what is in force is no draft.
  function modelEdit(M, o, redraw) {
    const { key } = M;
    const d = Object.assign({}, draftOf(key) || M.now, o);
    if (d.cli === M.setCli && d.model.trim() === M.setModel && d.effort === M.setEffort && !(d.other && !d.model.trim())) draftDrop(key); else draftPut(key, d);
    // In the setup each choice is saved at once: a pick that leaves a whole role (the default, or a CLI with its model),
    // the one in force too while the role is not yet set there (Codex, then Default, before a model is picked).
    if (S.from === ONB && redraw && (!d.cli || d.model.trim()) && (draftOf(key) || !OB.set.has(key))) { draftPut(key, d); modelSaveNow(M); return; }
    if (redraw) draw(); else modelMark(M);
  }
  // A model typed in, in the setup, is saved when the field f is left (or Enter).
  const typedSave = (M, f) => f.addEventListener('change', () => { if (S.from === ONB && draftOf(M.key)) modelSaveNow(M); });
  // The CLI menu of M's role.
  function cliPick(M) {
    const { name, key, s, clis, cli, of, setCli, now } = M;
    const dflt = s.default || (s.modelFrom === 'seed' && s.model);
    const pick = S.ctx.h('select', 'field board-select');
    pick.dataset.act = `${key}-cli`; pick.setAttribute('aria-label', `${name} CLI`);
    opt(pick, '', dflt ? `Default (${dflt})` : 'Default', cli === '');
    Object.keys(clis).forEach((c) => opt(pick, c, c, c === cli));
    if (cli && !of) opt(pick, cli, `${cli} (not installed)`, true);
    // Another CLI starts with no model picked; the one in force, with its own.
    pick.addEventListener('change', () => modelEdit(M, pick.value === setCli ? now : { cli: pick.value, model: '', effort: '', other: false }, true));
    return pick;
  }
  // The model menu of M's role, or its field when the CLI lists no model, and the field of Other… (field, or null).
  function modelPick(M) {
    const h = S.ctx.h, { name, key, v, cli, of, listed, allowed, typed } = M;
    let model, field = null;
    if (of && !Array.isArray(of.models) && !allowed.length) {
      // This CLI lists no models and the pack none for it: its model is typed in.
      model = h('input', 'field rules-field');
      model.type = 'text'; model.value = v.model; model.placeholder = `a ${cli} model`;
      model.addEventListener('input', () => modelEdit(M, { model: model.value }, false));
      typedSave(M, model);
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
      model.addEventListener('change', () => modelEdit(M, model.value === OTHER ? { other: true, model: typed ? v.model : '' } : { other: false, model: model.value }, true));
      if (typed) {
        // Other…: a name the list does not have, typed in beside it.
        field = h('input', 'field rules-field');
        field.type = 'text'; field.value = v.model; field.placeholder = `a ${cli} model`;
        field.dataset.act = `${key}-model-other`; field.setAttribute('aria-label', `${name} model, not listed`);
        field.addEventListener('input', () => modelEdit(M, { model: field.value, other: true }, false));
        typedSave(M, field);
      }
    }
    model.dataset.act = `${key}-model`; model.setAttribute('aria-label', `${name} model`);
    return { model, field };
  }
  // The effort menu of M's role.
  function effortPick(M) {
    const { name, key, s, v, cli, of } = M;
    const effort = S.ctx.h('select', 'field board-select');
    effort.dataset.act = `${key}-effort`; effort.setAttribute('aria-label', `${name} effort`);
    opt(effort, '', `Default effort${s.effortFrom === 'seed' && s.effort ? ` (${s.effort})` : ''}`, v.effort === '');
    list(of ? of.efforts : s.efforts).forEach((e) => opt(effort, e, e, e === v.effort));
    effort.disabled = !cli;
    effort.addEventListener('change', () => modelEdit(M, { effort: effort.value }, true));
    return effort;
  }
  // Save sends M's role whole, as one action.
  function modelSaveNow(M) {
    const { name, key, action } = M;
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
  }
  // Save and Cancel of M's role, which show only while it is unsaved (with its Unsaved mark, flag), and the model in
  // force (was), added to M. Cancel puts back what is in force. The model in force is "(not listed)" when its CLI,
  // installed, offers a list without it (a name typed in). The selects show it, so it is not said again beside them:
  // it shows only while they show an unsaved change, or to say it is not listed.
  function modelButtons(M) {
    const { name, key, s, clis } = M;
    M.flag = S.ctx.chip('Unsaved', 'warn');
    M.save = button('Save', 'btn-primary', `${key}-save`, `Save the ${name}'s CLI, model and effort`, () => modelSaveNow(M));
    M.cancel = button('Cancel', 'btn-quiet', `${key}-cancel`, `Put the ${name} back as it is in force`, () => { draftDrop(key); draw(); });
    const inForce = s.agent && clis[s.agent] && typeof clis[s.agent] === 'object' ? cliModels(s, s.agent, clis[s.agent]) : null;
    M.unlisted = !!(inForce && inForce.length && s.model && !inForce.includes(bare(s.agent, s.model)));
    M.was = S.ctx.h('span', 'board-from rules-in-force', `In force: ${s.agent ? `${s.agent} ` : ''}${s.model || 'not set'}${M.unlisted ? ' (not listed)' : ''} · ${s.effort || 'not set'}`);
  }
  function modelMark(M) { const on = modelUnsaved(M); [M.flag, M.save, M.cancel].forEach((x) => { x.hidden = !on; }); M.was.hidden = !on && !M.unlisted; }
  // The engine runs a judge on the reviewer's CLI as any other: the judge's row (s) says it is no second family. A role
  // the host took since the snapshot is known by its CLI alone. One cleared to the default, or set by its model alone,
  // runs on a CLI the snapshot does not yet name; so does a judge left at the default once the reviewer changes, as the
  // default judge is of another family than the reviewer's. Nothing is said until the snapshot names it.
  function reviewerFamily(s) {
    const moved = (k) => !!S.ctl && ownKey(S.ctl, k) && !same(S.ctl[k], (S.d.control || {})[k]);
    const rc = moved('reviewer') ? S.ctl.reviewer : undefined;
    const rv = rc !== undefined ? (rc && rc.cli) || null : ((S.d.modelSettings || {}).reviewer || {}).agent;
    const jc = moved('judge') ? S.ctl.judge : (S.d.control || {}).judge;
    const jSet = !!(jc && typeof jc === 'object' && jc.model);
    const jv = jSet && jc.cli ? jc.cli : (moved('judge') || (!jSet && moved('reviewer')) ? null : s.agent);
    return !!(jv && jv === rv);
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
    rulesBuild(el, r); rulesNever(el, d, r); rulesCap(el, d, c); rulesGuard(el, d, c); rulesAtOnce(el, c); rulesSuite(el, c); rulesSeats(el, d); rulesJudge(el, c, d);
    rulesAccounts(el, c); rulesGates(el, c, r); rulesLand(el, c); rulesCheck(el, c, r); rulesLint(el, r); rulesSplit(el, r); rulesTestIssues(el, r);
    rulesPick(el, d, r); rulesCores(el); rulesStanding(el); rulesHeld(el, all); rulesPins(el, c, d); rulesIndexed(el);
    return el;
  }
  // The rows of the Rules panel (rules), a function each, in the panel's order: each appends its rows to el. d: the
  // snapshot's part; c: the control record; r: its rules.
  function rulesBuild(el, r) {
    const h = S.ctx.h;
    // Build: each choice, and what turning one off would skip, said before it is turned off. One that would skip queued
    // issues takes a second click: the first arms it, its button then naming the count.
    const would = BUILDS.filter(([k]) => r[k] !== false).map(([k, name]) => [name, wouldSkip(k)]).filter(([, k]) => k > 0);
    el.append(row('build', 'Build issues', 'which issues Conveyor may pick',
      seg('Build issues', ...BUILDS.map(([k, name]) => {
        const on = r[k] !== false, k2 = on ? wouldSkip(k) : 0, armed = k2 > 0 && S.armed === `rule-${k}`;
        const b = choice(armed ? `Turn ${name} off: skip ${k2}` : name, `rule-${k}`,
          armed ? `Confirm: turn ${name} off and skip ${plural(k2, 'queued issue', 'queued issues')}` : `Build ${name}: ${on ? 'on' : 'off'}${k2 ? `; turning it off would skip ${k2} queued` : ''}`, on, () => {
            if (k2 > 0 && !armed) { arm(`rule-${k}`); say(`${skipWords(name, k2)} Click again to turn it off.`); return; }
            S.armed = null;
            send('rules', [`${k}=${on ? 'off' : 'on'}`], null, ['rules', [`${k}=${on ? 'on' : 'off'}`]]);
          });
        if (armed) { b.classList.add('board-danger'); b.dataset.armed = ''; }
        return b;
      })),
      would.length ? h('p', 'rules-would', would.map(([name, k]) => skipWords(name, k)).join(' ')) : null));
  }
  function rulesNever(el, d, r) {
    const h = S.ctx.h;
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
  }
  function rulesCap(el, d, c) {
    const h = S.ctx.h;
    // At once: the record's cap, else the one in force when the snapshot's cap came from the seed (d.cap), else the
    // seed's own, CAP0 (a record with no cap runs at it: capnow in control.sh). So the setup, which shows the record
    // with no cap until the rule is set, and a cap just cleared here, both step from a number.
    const capSet = num(c.cap);
    const capNow = capSet !== null ? capSet : ((d.control || {}).cap == null && num(d.cap) !== null ? num(d.cap) : CAP0);
    el.append(row('cap', 'Cards at once', 'cards building, fixing or rebasing at once; review and tests do not count',
      stepper('cards at once', String(capNow), () => send('cap', [String(capNow - 1)], null, ['cap', [capSet !== null ? String(capSet) : 'off']]),
        () => send('cap', [String(capNow + 1)], null, ['cap', [capSet !== null ? String(capSet) : 'off']]),
        capNow > 1, capNow < 100),
      h('span', 'board-from', capSet !== null ? 'set here' : 'the default'),
      capSet !== null ? button('Default', 'btn-quiet', 'cap-off', 'Cards at once: back to the default', () => send('cap', ['off'], null, ['cap', [String(capSet)]])) : null));
  }
  function rulesAtOnce(el, c) {
    const h = S.ctx.h, at = num(c.suiteAtOnce), slots = S.cores && typeof S.cores.slots === 'number' ? S.cores.slots : null;
    const to = (n) => () => send('atonce', [String(n)], null);
    // On a devbox or an ssh box the cap is that box's test slots, not this machine's.
    const far = suiteSlots(c);
    const note = far ? (far.n === null ? null : `Capped at the suite machine's slots: ${far.n} on the ${far.kind === 'devbox' ? 'devbox' : 'box'}.`)
      : at !== null && slots !== null && at > slots ? `Runs at ${slots}: the machine has ${slots} test slot${slots === 1 ? '' : 's'}.` : null;
    el.append(row('atonce', 'Test files at once', 'test files a parallel release suite runs together',
      at === null ? newer(false) : stepper('test files at once', String(at), to(at - 1), to(at + 1), at > 1, at < 999),
      note ? h('span', 'board-from', note) : null));
  }
  function rulesGuard(el, d, c) {
    const h = S.ctx.h;
    // Weekly pause: Off and three percents (and the one set, when it is another), beside the use now.
    const guard = num(c.guard);
    const pcts = GUARDS.concat(guard !== null && !GUARDS.includes(guard) ? [guard] : []).sort((a, b) => a - b);
    const lim = d.limit && num(d.limit.pct) !== null ? d.limit.pct : null;
    const reading = h('span', 'board-from', lim === null ? 'the Board does not know the use now' : `${Math.round(lim * 10) / 10}% used`);
    el.append(row('guard', 'Weekly pause', 'pause when the weekly Claude limit reaches',
      seg('Weekly pause', choice('Off', 'guard-off', 'Pause when the weekly limit reaches: off', guard === null, () => { if (guard !== null) send('guard', ['off'], null, ['guard', [String(guard)]]); }),
      ...pcts.map((p) => choice(`${p}%`, `guard-${p}`, `Pause Conveyor when the weekly limit reaches ${p} percent`, guard === p, () => { if (guard !== p) send('guard', [String(p)], null, ['guard', [guard === null ? 'off' : String(guard)]]); }))),
      reading, guard === null ? S.ctx.chip('no guard set', 'warn') : null));
  }
  function rulesSeats(el, d) {
    const h = S.ctx.h;
    // Builder and Reviewer: CLI, model and effort.
    const m = d.modelSettings;
    el.append(row('builder', 'Builder', 'Builds the card and fixes findings.', m && m.builder ? modelCtl('Builder', 'builder', m.builder) : h('span', 'board-from', 'The build machine names no models yet.')));
    el.append(row('reviewer', 'Reviewer', 'Reviews each round of changes.', m && m.reviewer ? modelCtl('Reviewer', 'reviewer', m.reviewer) : h('span', 'board-from', 'The build machine names no models yet.')));
  }
  function rulesJudge(el, c, d) {
    const h = S.ctx.h, m = d.modelSettings;
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
    el.append(row('judge', 'Judge', 'Decides which review findings count.',
      seg('Judge', choice('On', 'judge-on', 'Judge: on', judgeOn, () => { if (!judgeOn) send('judge', ['on'], null, ['judge', ['off']]); }),
        choice('Off', 'judge-off', 'Judge: off', !judgeOn, () => { if (judgeOn) send('judge', ['off'], null, ['judge', ['on']]); })),
      m && m.judge ? modelCtl('Judge', 'judge', m.judge) : h('span', 'board-from', 'The build machine names no model for the reviewer, so none for the judge.')));
    el.append(row('judge-always', 'Always accept', 'Finding kinds the Judge accepts every time.', always, kindForm));
  }
  function rulesAccounts(el, c) {
    // Account: the Claude account of the host's accounts this project's cards use, and one for its reviews when the
    // reviewer is Claude. A change reaches the cards started after it; a card in flight keeps its own.
    el.append(row('account', 'Account', 'cards started after a change', accountCtl('Account', 'account', c.account, "the build machine's own login")));
    el.append(row('review-account', 'Review account', 'Used only by Claude reviewers.', accountCtl('Review account', 'review-account', c.reviewAccount, 'the Account')));

    // New issues start in: Queue (the default) or Held. A follow-up is always queued.
    const start = c.start === 'held' ? 'held' : 'queue';
    el.append(row('start', 'New issues start in', 'Follow-ups always enter the queue.',
      seg('New issues start in', choice('Queue', 'start-queue', 'New issues start in the Queue', start === 'queue', () => { if (start !== 'queue') send('start', ['queue'], null, ['start', ['held']]); }),
      choice('Held', 'start-held', 'New issues start in Held', start === 'held', () => { if (start !== 'held') send('start', ['held'], null, ['start', ['queue']]); }))));
  }
  // Dependency guard, Push on landing and Approve visible changes: the words under each name say what
  // it does, whichever choice is set; what Off means shows beside the switch only while Off is set. An engine that
  // does not know one (its record has no depGuard, rules.push or rules.visible) is sent neither choice.
  const offLine = (on, text) => (on ? null : S.ctx.h('span', 'board-from rules-off', `off: ${text}`));
  const newer = (known) => (known ? null : S.ctx.h('span', 'board-from', 'needs a newer Conveyor'));
  function rulesGates(el, c, r) {
    // Dependency guard: On (a record without it reads as On) never picks an issue while one it depends on is open; Off
    // lets "Queue anyway" force one.
    const guardOn = c.depGuard !== false, knows = depKnown();
    const gOn = choice('On', 'dep-guard-on', 'Dependency guard: on', guardOn, () => { if (!guardOn) send('dep-guard', ['on'], null, ['dep-guard', ['off']]); });
    const gOff = choice('Off', 'dep-guard-off', 'Dependency guard: off', !guardOn, () => { if (guardOn) send('dep-guard', ['off'], null, ['dep-guard', ['on']]); });
    gOn.disabled = gOff.disabled = !knows;
    el.append(row('dep-guard', 'Dependency guard', 'an issue waits while one it depends on is open',
      seg('Dependency guard', gOn, gOff), knows ? offLine(guardOn, 'Conveyor can build a waiting issue all the same') : newer(knows)));

    // Push on landing: On pushes each card once it lands; Off (the default, control-defaults.json) lands only, and what landed waits for
    // Push landed on the Board.
    const pushOn = r.push !== false, pushKnown = typeof r.push === 'boolean';
    const pOn = choice('On', 'push-on', 'Push on landing: on', pushOn, () => { if (!pushOn) send('rules', ['push=on'], null, ['rules', ['push=off']]); });
    const pOff = choice('Off', 'push-off', 'Push on landing: off', !pushOn, () => { if (pushOn) send('rules', ['push=off'], null, ['rules', ['push=on']]); });
    pOn.disabled = pOff.disabled = !pushKnown;
    el.append(row('push', 'Push on landing', 'Conveyor pushes each card when it lands',
      seg('Push on landing', pOn, pOff), pushKnown ? offLine(pushOn, 'land only: cards land on main, and Push landed on the Control tab pushes them') : newer(pushKnown)));
  }
  function rulesLand(el, c) {
    const h = S.ctx.h;
    // Land as: Main pushes main to the default branch; Pull request pushes it to conveyor/landing and keeps one pull
    // request open into the default branch. The record's value, else the pack's (landNow).
    const land = landNow(c), landK = landKnown();
    const lMain = choice('Main', 'land-as-main', 'Land as: main', land === 'main', () => { if (land !== 'main') send('land-as', ['main'], null, ['land-as', ['pr']]); });
    const lPr = choice('Pull request', 'land-as-pr', 'Land as: one pull request', land === 'pr', () => { if (land !== 'pr') send('land-as', ['pr'], null, ['land-as', ['main']]); });
    lMain.disabled = lPr.disabled = !landK;
    el.append(row('land-as', 'Land as', 'where the push sends the cards that landed',
      seg('Land as', lMain, lPr), landK ? (land === 'pr' ? h('span', 'board-from', 'one pull request from conveyor/landing collects the cards; merge it to close their issues') : null) : newer(landK)));
    // Merge PR: who merges that pull request. Button (the default): only you, with Merge on the Control tab; Release:
    // the release merges it before it tags; Idle: Conveyor merges it when nothing is on the belt and nothing can be
    // picked, once the test files linked to its cards succeed. The record's value, else the pack's (prNow).
    const pm = prNow(c), pmK = prKnown();
    const pms = [['button', 'Button'], ['release', 'Release'], ['idle', 'Idle']].map(([v, t]) =>
      choice(t, `pr-merge-${v}`, `Merge PR: ${PRMERGE[v]}`, pm === v, () => { if (pm !== v) send('pr-merge', [v], null, ['pr-merge', [pm]]); }));
    pms.forEach((b) => { b.disabled = !pmK; });
    el.append(row('pr-merge', 'Merge PR', 'who merges the pull request of Land as',
      seg('Merge PR', ...pms), pmK ? h('span', 'board-from', `merged ${PRMERGE[pm]}`) : newer(pmK)));
  }
  function rulesCheck(el, c, r) {
    // Test before a push: On (the default of a new pack) runs the test files linked to the landings since the last
    // push before each push, and a file that fails holds it; Off pushes with no test first. The pack's push.check
    // sets it until a change here, which the control record keeps over the pack.
    const checkOn = pushCheckOn(c), checkKnown = typeof S.d.pushCheck === 'boolean';
    const cOn = choice('On', 'push-check-on', 'Test before a push: on', checkOn, () => { if (!checkOn) send('push-check', ['on'], null, ['push-check', ['off']]); });
    const cOff = choice('Off', 'push-check-off', 'Test before a push: off', !checkOn, () => { if (checkOn) send('push-check', ['off'], null, ['push-check', ['on']]); });
    cOn.disabled = cOff.disabled = !checkKnown;
    el.append(row('push-check', 'Test before a push', 'the test files linked to the landings run before each push, and one that fails holds the push',
      seg('Test before a push', cOn, cOff), checkKnown ? offLine(checkOn, 'a push runs no test first') : newer(checkKnown)));
    // Approve visible changes: On stops a card whose change customers or staff will see until its
    // issue has a `Visible change approved:` line; Off (the default) lets it land without one, and says so beside the switch, so a
    // landed visible change is not read as approved.
    const yesOn = r.visible !== false, yesKnown = typeof r.visible === 'boolean';
    const yOn = choice('On', 'visible-on', 'Approve visible changes: on', yesOn, () => { if (!yesOn) send('rules', ['visible=on'], null, ['rules', ['visible=off']]); });
    const yOff = choice('Off', 'visible-off', 'Approve visible changes: off', !yesOn, () => { if (yesOn) send('rules', ['visible=off'], null, ['rules', ['visible=on']]); });
    yOn.disabled = yOff.disabled = !yesKnown;
    el.append(row('visible', 'Approve visible changes', 'a change customers or staff will see waits for your yes',
      seg('Approve visible changes', yOn, yOff), yesKnown ? offLine(yesOn, 'visible changes land without your yes, and nobody approves them') : newer(yesKnown)));
  }
  function rulesLint(el, r) {
    const h = S.ctx.h;
    // Lint check: On (the default) runs the pack's lint commands on each card's change at its review and landing gates
    // (lintgate(), conveyor/lib/lint.sh); Off runs none. The pack's commands (the snapshot's lintCommands) are listed
    // under it, read-only: the pack's lint field sets them. An engine whose record has no rules.lint is sent neither choice.
    const lintOn = r.lint !== false, lintKnown = typeof r.lint === 'boolean';
    const lnOn = choice('On', 'lint-on', 'Lint check: on', lintOn, () => { if (!lintOn) send('rules', ['lint=on'], null, ['rules', ['lint=off']]); });
    const lnOff = choice('Off', 'lint-off', 'Lint check: off', !lintOn, () => { if (lintOn) send('rules', ['lint=off'], null, ['rules', ['lint=on']]); });
    lnOn.disabled = lnOff.disabled = !lintKnown;
    const lintCmds = Array.isArray(S.d.lintCommands) ? S.d.lintCommands.filter((x) => x && typeof x.run === 'string') : null;
    let lintList = null;
    if (lintCmds && lintCmds.length) {
      lintList = h('ul', 'rules-lint');
      lintList.setAttribute('aria-label', "The pack's lint commands");
      lintCmds.forEach((x) => {
        const li = h('li');
        li.append(h('code', null, x.run), h('span', 'board-from', ` on ${list(x.files).join(', ') || 'no files'}`));
        lintList.append(li);
      });
    } else if (lintCmds) lintList = h('span', 'board-from', 'the pack sets no lint command');
    el.append(row('lint', 'Lint check', "the pack's lint commands run on each card's change before its review and its landing",
      seg('Lint check', lnOn, lnOff), lintKnown ? offLine(lintOn, 'no lint command runs, and cards land with no lint check') : newer(lintKnown), lintList));
  }
  function rulesSplit(el, r) {
    const h = S.ctx.h;
    // Split large issues: On (the default) files the slices as follow-ups and holds the issue as their umbrella; Shadow
    // records what the Judge would split a large issue into, and builds it whole; Off checks nothing. An engine whose
    // record has no rules.split is sent none of them. Undo sends the setting it had.
    const splitAt = ['off', 'shadow', 'on'].includes(r.split) ? r.split : null;
    const splitTo = (v, label) => {
      const b = choice(label, `split-${v}`, `Split large issues: ${label.toLowerCase()}`, splitAt === v, () => { if (splitAt !== v) send('rules', [`split=${v}`], null, ['rules', [`split=${splitAt}`]]); });
      b.disabled = splitAt === null;
      return b;
    };
    el.append(row('split', 'Split large issues', 'the Judge reads a large issue before its build and says whether to build it as 2 or 3 follow-ups',
      seg('Split large issues', splitTo('off', 'Off'), splitTo('shadow', 'Shadow'), splitTo('on', 'On')),
      splitAt === null ? newer(false) : splitAt === 'shadow' ? h('span', 'board-from rules-off', 'shadow: the verdict is recorded, and the issue is built whole')
        : splitAt === 'off' ? offLine(false, 'no issue is checked') : null));
  }
  function rulesTestIssues(el, r) {
    // Tests page actions, in Done without asking's group Cards with no GitHub issue (#1330, #1346): On starts the
    // card a Tests page action makes at once with no GitHub issue (`conveyor.sh testissue`), the record's
    // rules.testissues false; Off (the default, rules.testissues true) files a GitHub issue for it. The record keeps
    // the same setting as before the move, so a project that set it keeps its choice. An engine whose record has no
    // rules.testissues is sent neither choice.
    const on = r.testissues === false, known = typeof r.testissues === 'boolean';
    const tOn = choice('On', 'noissue-tests-on', 'Tests page actions with no GitHub issue: on', on, () => { if (!on) send('rules', ['testissues=off'], null, ['rules', ['testissues=on']]); });
    const tOff = choice('Off', 'noissue-tests-off', 'Tests page actions with no GitHub issue: off', !on, () => { if (on) send('rules', ['testissues=on'], null, ['rules', ['testissues=off']]); });
    tOn.disabled = tOff.disabled = !known;
    el.append(row('testissues', 'Tests page actions', 'an action on the Tests page starts its card at once, with no GitHub issue',
      seg('Tests page actions', tOn, tOff), known ? offLine(on, 'an action on the Tests page files a GitHub issue, and the belt builds that issue as a card') : newer(known)));
  }
  function rulesPick(el, d, r) {
    const h = S.ctx.h;
    // Pick settings: Shadow records each card's group, the builder the rule chooses and the Judge's seats, and builds
    // on the builder as before; On builds and reviews the card on the Judge's seats, and lets a card of an eligible
    // group build on the group's challenger as a trial (lib/modelpick.sh); Off (the default) records none. An engine
    // whose record has no rules.pick is sent none of them.
    const pickAt = ['off', 'shadow', 'on'].includes(r.pick) ? r.pick : null;
    const pickTo = (v, label) => {
      const b = choice(label, `pick-${v}`, `Pick settings: ${label.toLowerCase()}`, pickAt === v, () => { if (pickAt !== v) send('rules', [`pick=${v}`], null, ['rules', [`pick=${pickAt}`]]); });
      b.disabled = pickAt === null;
      return b;
    };
    // Each seat's pick list (the pack's pick.<seat>, pickShown()): each model the pack allows the seat (modelSettings'
    // allowed, by program) is a row with a checkbox, may the pick give it, and when it is checked its lowest and
    // highest effort menus in its own program's efforts (packPick.efforts; an OpenCode builder takes none), Any for
    // no bound on that side. Save sends the checked models with their ranges (`pick models`), or clear when none is
    // checked, so the pick may give the seat any allowed model at any effort. A snapshot with no packPick shows none.
    const lists = pickShown(), ms = d.modelSettings && typeof d.modelSettings === 'object' ? d.modelSettings : {};
    const effs = d.packPick && typeof d.packPick === 'object' && d.packPick.efforts && typeof d.packPick.efforts === 'object' ? d.packPick.efforts : {};
    const seats = h('div', 'rules-pick-seats');
    ROLES.forEach((k) => seats.append(pickSeat(k, lists, ms, effs)));
    el.append(row('pick', 'Pick settings', 'code puts each card in a group before its build, and the Judge chooses its builder, reviewer and judge from the models you let it give each seat, each in its effort range; a seat you set for a card always wins',
      seg('Pick settings', pickTo('off', 'Off'), pickTo('shadow', 'Shadow'), pickTo('on', 'On')),
      pickAt === null ? newer(false) : pickAt === 'off' ? offLine(false, 'no pick is recorded')
        : h('span', 'board-from rules-off', pickAt === 'shadow' ? 'shadow: the pick is recorded, and the card builds on its builder as before'
          : 'on: the card builds and is reviewed on the Judge\'s seats. A card of an eligible group can build on the group\'s challenger as a trial, one trial card at a time, and is reviewed on the project\'s reviewer and judge. A seat you set for a card always wins'),
      lists === null ? null : seats));
  }
  const rangeText = (g) => (g.min && g.max ? `${g.min} to ${g.max}` : g.min ? `${g.min} or higher` : g.max ? `${g.max} or lower` : 'any effort');
  // The models the pack allows seat k (ms: the snapshot's modelSettings), each once, {id, efforts}: the efforts of its
  // own program (effs; an OpenCode builder takes none).
  function pickModels(k, ms, effs) {
    const allowed = ms[k] && ms[k].allowed && typeof ms[k].allowed === 'object' ? ms[k].allowed : {}, models = [];
    Object.keys(allowed).forEach((cli) => list(allowed[cli]).forEach((m) => {
      const id = cli === 'opencode' ? `opencode:${m}` : m;
      if (typeof m === 'string' && m && !models.some((x) => x.id === id)) {
        models.push({ id, efforts: k === 'builder' && cli === 'opencode' ? [] : list(effs[cli]).filter((e) => typeof e === 'string' && e) });
      }
    }));
    return models;
  }
  // Seat k's pick list in Pick settings (rulesPick): its head, a row a model it may be given, and Save. lists: the
  // pack's pick lists as shown.
  function pickSeat(k, lists, ms, effs) {
    const h = S.ctx.h, name = k[0].toUpperCase() + k.slice(1), one = h('div', 'rules-pick-seat');
    one.dataset.seat = k;
    const saved = lists && lists[k] && typeof lists[k] === 'object' ? lists[k] : null;
    const models = pickModels(k, ms, effs);
    // The models checked and the ranges picked, not yet saved, stay when a snapshot redraws the row; Save drops
    // them. Each control's action names its seat and model, so a redraw gives the focus back to the same control.
    const dk = `${S.d.repo} ${k}`, cur = JSON.parse(JSON.stringify(S.pickDraft.get(dk) || saved || {}));
    const keep = () => S.pickDraft.set(dk, cur);
    const head = h('div', 'rules-pick-head');
    head.append(h('span', 'board-label', name), ' ', h('span', 'board-from rules-pick-now',
      saved && Object.keys(saved).length ? Object.keys(saved).map((id) => `${id}: ${rangeText(saved[id] || {})}`).join('; ') : 'All models, any effort'));
    one.append(head);
    models.forEach((x) => one.append(pickModelRow(k, name, x, cur, keep)));
    // The command's words for a list: each model, with =<min>-<max> when it has a bound; clear for none.
    const words = (o, only) => {
      const ids = Object.keys(o).filter((id) => !only || models.some((x) => x.id === id));
      return ids.length ? [k].concat(ids.map((id) => { const g = o[id] || {}; return g.min || g.max ? `${id}=${g.min || ''}-${g.max || ''}` : id; })) : [k, 'clear'];
    };
    const undo = ['pick-models', words(saved || {}, false)];
    one.append(button('Save', 'btn-quiet', `pick-save-${k}`, `${name}: save the models the pick may give`, () => { S.pickDraft.delete(dk); send('pick-models', words(cur, true), null, undo); }));
    return one;
  }
  // The row of model id of seat k (name: its words) in its pick list: may the pick give it, and when it may, its
  // lowest and highest effort. cur: the list as picked here; keep() keeps it.
  function pickModelRow(k, name, { id, efforts }, cur, keep) {
    const h = S.ctx.h, r = h('div', 'rules-pick-model'), box = h('input'), lab = h('label', 'board-from');
    r.dataset.model = id;
    box.type = 'checkbox'; box.checked = Object.prototype.hasOwnProperty.call(cur, id); box.dataset.act = `pick-model-${k}-${id}`;
    box.setAttribute('aria-label', `${name}: the pick may give ${id}`);
    box.addEventListener('change', () => { if (box.checked) cur[id] = {}; else delete cur[id]; keep(); draw(); });
    lab.append(box, ' ', id);
    r.append(lab);
    if (box.checked && efforts.length) {
      const g = cur[id] && typeof cur[id] === 'object' ? cur[id] : (cur[id] = {});
      const menu = (which) => {
        const sel = h('select', 'field board-select');
        sel.dataset.act = `pick-${which}-${k}-${id}`; sel.setAttribute('aria-label', `${name}, ${id}: ${which === 'min' ? 'lowest' : 'highest'} effort`);
        [''].concat(efforts).forEach((e) => { const o = h('option', null, e || 'Any'); o.value = e; o.selected = e === (g[which] || ''); sel.append(o); });
        sel.addEventListener('change', () => { if (sel.value) g[which] = sel.value; else delete g[which]; keep(); });
        return sel;
      };
      r.append(' ', h('span', 'board-from', 'lowest'), ' ', menu('min'), ' ', h('span', 'board-from', 'highest'), ' ', menu('max'));
    }
    return r;
  }
  function rulesCores(el) {
    const h = S.ctx.h;
    // Reserved cores: the machine's (the host file's reserveCores), shown here and set in the host file, with the
    // line that says where the test limits are.
    const co = S.cores, slots = co && typeof co.slots === 'number' ? `${co.slots} test slot${co.slots === 1 ? '' : 's'}` : 'test slots not read';
    el.append(row('cores', 'Reserved cores', 'Set in the host file (reserveCores). Card sessions and tests never run on these cores, for every project.',
      !co ? newer(false)
        : h('span', 'board-from rules-cores', co.unavailable ? `Not available on this machine: ${co.unavailable}`
          : co.reserved.length ? `Cores ${co.reserved.join(', ')} · ${slots} left` : `None · ${slots}`),
      limitsLine()));
  }
  function rulesStanding(el) {
    // Done without asking: one row a standing kind of routine yes, On or Off. Off (each kind's setting from setup)
    // sends each such step to you. A Conveyor whose snapshot has no standing is sent neither choice.
    const standingOn = standingShown();
    STANDING.forEach(([k, name, what]) => {
      const on = !!standingOn && standingOn.includes(k);
      const sOn = choice('On', `standing-${k}-on`, `${name} without asking: on`, on, () => { if (!on) send('standing', [k, 'on'], null, ['standing', [k, 'off']]); });
      const sOff = choice('Off', `standing-${k}-off`, `${name} without asking: off`, !on, () => { if (on) send('standing', [k, 'off'], null, ['standing', [k, 'on']]); });
      sOn.disabled = sOff.disabled = !standingOn;
      el.append(row(`standing-${k}`, name, what, seg(name, sOn, sOff), standingOn ? offLine(on, 'the Foreman asks you first') : newer(false)));
    });
  }
  function rulesHeld(el, all) {
    const h = S.ctx.h;
    // Held issues: the count, as a link to the list in the Held panel.
    const link = h('a', 'rules-link', `View ${plural(all.length, 'held issue', 'held issues')}`);
    link.href = '#rules-held'; link.dataset.act = 'held-link';
    el.append(unlisted() ? row('held', 'Held issues', 'parked issues', h('span', 'board-from', heldUnknown()))
      : row('held', 'Held issues', 'parked issues', all.length ? link : h('span', 'board-value', 'No issue is held.')));
  }
  // The pinned order, when there is one: one row a pin, with its number and title (as the snapshot's queue, held,
  // waiting, skipped and open issues give it), a drag handle and a menu of Move up (not on the first), Move down (not on the
  // last) and Unpin; the first PINS_SHOWN, then "View remaining N pins". unpin takes this one issue out of the
  // record's order on the host, under its lock: an order sent whole from here would drop a pin set elsewhere (the Board).
  function rulesPins(el, c, d) {
    const h = S.ctx.h, order = list(c.order);
    if (!order.length) return;
    const titles = new Map(list(d.queue).concat(list(d.held), list(d.waits), list(d.skipped), list(d.open && d.open.issues), list(d.open && d.open.held))
      .filter((x) => x && typeof x.title === 'string' && x.title).map((x) => [x.issue, x.title]));
    const pins = h('ol', 'rules-pins');
    // Move up, Move down and a drop send the pinned order with the one pin moved: a move to the next place is the
    // two swapped. Undo, of a move or an unpin, sends the pinned order as it was.
    const move = (i, j) => { const o = order.slice(); o.splice(j, 0, o.splice(i, 1)[0]); send('order', o.map(String), null, ['order', order.map(String)]); };
    order.forEach((n, i) => {
      if (i >= PINS_SHOWN && !S.pinsAll) return;
      pins.append(pinRow(n, i, order, titles, move));
    });
    const rest = order.length - PINS_SHOWN;
    // The redraw takes "View remaining" away, so the focus goes to the menu of the first pin it shows.
    const showRest = (e) => {
      const box = e.currentTarget.closest('.rules');
      S.pinsAll = true;
      draw();
      const next = box && box.querySelectorAll('[data-rule="order"] .rules-pin-row')[PINS_SHOWN];
      if (next) next.querySelector('.rules-menu > summary').focus({ preventScroll: true });
    };
    el.append(row('order', 'Pinned issues', 'Picked first, from top to bottom.', pins,
      rest > 0 && !S.pinsAll ? button(`View remaining ${plural(rest, 'pin', 'pins')}`, 'btn-quiet', 'pins-all', null, showRest) : null));
  }
  // The row of pin n, at place i of the pinned order (rulesPins); move(i, j) moves a pin.
  function pinRow(n, i, order, titles, move) {
    const h = S.ctx.h, item = h('li', 'rules-item rules-pin-row');
    item.dataset.issue = String(n);
    item.draggable = true;
    item.addEventListener('dragstart', (e) => { S.dragPin = i; if (e.dataTransfer) { e.dataTransfer.effectAllowed = 'move'; e.dataTransfer.setData('text/plain', `#${n}`); } });
    item.addEventListener('dragend', () => { S.dragPin = null; });
    item.addEventListener('dragover', (e) => { if (S.dragPin !== null) e.preventDefault(); });
    item.addEventListener('drop', (e) => {
      const from = S.dragPin;
      S.dragPin = null;
      if (from === null) return;
      e.preventDefault();
      if (from !== i && !S.busy) move(from, i);
    });
    const grip = h('span', 'rules-grip', '⠿');
    grip.setAttribute('aria-hidden', 'true');
    const menu = h('details', 'rules-menu'), sum = h('summary', 'btn btn-quiet', '⋯'), acts = h('span', 'rules-menu-acts');
    sum.setAttribute('aria-label', `Actions for #${n}`);
    menu.open = S.pinMenu === n;
    menu.addEventListener('toggle', () => { if (menu.open) S.pinMenu = n; else if (S.pinMenu === n) S.pinMenu = null; });
    acts.append(...[i > 0 ? button('Move up', 'btn-quiet', 'pin-up', `Move #${n} up in the pinned order`, () => move(i, i - 1)) : null,
      i < order.length - 1 ? button('Move down', 'btn-quiet', 'pin-down', `Move #${n} down in the pinned order`, () => move(i, i + 1)) : null,
      button('Unpin', 'btn-quiet', 'unpin', `Unpin #${n}: pick takes it in its own order`, () => send('unpin', [String(n)], null, ['order', order.map(String)]))].filter(Boolean));
    menu.append(sum, acts);
    item.append(grip, h('span', 'rules-pin', titles.has(n) ? `#${n} ${titles.get(n)}` : `#${n}`), menu);
    return item;
  }
  function rulesIndexed(el) {
    const h = S.ctx.h;
    // The six groups (SETS), each with its rows, and a group of rows inside one under its own name; the index and the
    // search pick which show (index()). The setup takes the rows by their rule from here, so a row stays a .rules-row
    // of its own.
    const byRule = new Map(Array.from(el.querySelectorAll(':scope > .rules-row'), (x) => [x.dataset.rule, x]));
    const rowsOf = (keys) => keys.filter((x) => byRule.has(x)).map((x) => byRule.get(x));
    const sets = h('div', 'rules-sets');
    SETS.forEach(([k, name, what, keys]) => {
      const set = h('section', 'rules-set');
      set.dataset.set = k;
      set.append(h('h4', 'rules-set-name', name), h('p', 'rules-set-what', what),
        ...(k === 'models' ? [h('p', 'rules-set-what', 'Save model changes per seat. Other rules save as you change them.')] : []),
        ...keys.flatMap((x) => {
          if (!Array.isArray(x)) return rowsOf([x]);
          const [g, gname, ...grows] = x, group = h('section', 'rules-group');
          group.dataset.group = g;
          group.append(h('h5', 'rules-group-name', gname), ...rowsOf(grows));
          return [group];
        }));
      sets.append(set);
    });
    const none = h('p', 'board-from rules-none');
    none.setAttribute('aria-live', 'polite');
    sets.append(none);
    const find = h('input', 'field rules-field rules-find');
    find.type = 'search'; find.placeholder = 'Search rules'; find.value = S.ruleFind; find.dataset.act = 'rules-find';
    find.setAttribute('aria-label', 'Search the rules by group, name or key');
    find.addEventListener('input', () => { S.ruleFind = find.value; index(el); relength(); });
    const nav = h('nav', 'rules-index');
    nav.setAttribute('aria-label', 'Rule groups');
    nav.append(...SETS.map(([k, name]) => button(name, 'btn-quiet rules-index-item', `rules-set-${k}`, `Show the ${name} rules`, () => {
      S.ruleSet = k; S.ruleFind = ''; find.value = ''; index(el); relength();
    })));
    const pick = h('div', 'rules-pick');
    pick.append(find, nav);
    const both = h('div', 'rules-indexed');
    both.append(pick, sets);
    el.append(h('p', 'rules-hint', 'Choose a group or search for a rule to edit it in place.'), both);
  }
  // The Rules panel shows the group picked, or, with search text, each rule whose group's name (or the name of the
  // group of rows it is in), own name or key holds it (any case), and each group with such a rule; with none, a line
  // that says so. A group of rows with no rule shown is hidden too. The index marks the group picked while no search
  // is typed.
  function index(el) {
    const q = S.ruleFind.trim().toLowerCase();
    let any = false;
    el.querySelectorAll('.rules-set').forEach((set) => {
      const name = set.querySelector('.rules-set-name').textContent.toLowerCase();
      let hits = 0;
      set.querySelectorAll('.rules-row').forEach((r) => {
        const g = r.closest('.rules-group'), gname = g ? g.querySelector('.rules-group-name').textContent.toLowerCase() : '';
        const hit = !q || name.includes(q) || (g && gname.includes(q)) || r.dataset.rule.includes(q) || r.querySelector('.board-label').textContent.toLowerCase().includes(q);
        r.hidden = !hit;
        if (hit) hits += 1;
      });
      set.querySelectorAll('.rules-group').forEach((g) => { g.hidden = !Array.from(g.querySelectorAll('.rules-row')).some((r) => !r.hidden); });
      set.hidden = q ? !hits : set.dataset.set !== S.ruleSet;
      if (!set.hidden) any = true;
    });
    SETS.forEach(([k]) => { const b = el.querySelector(`[data-act="rules-set-${k}"]`); if (b) b.setAttribute('aria-pressed', String(!q && k === S.ruleSet)); });
    const none = el.querySelector('.rules-none');
    if (none) { none.hidden = any; none.textContent = any ? '' : `No rule matches "${S.ruleFind.trim()}".`; }
    return el;
  }
  window.DASH_APP.part('rules-rows', function (shared) {
    ({ KIND, MODEL, KINDS_MAX, STANDING, SETS, PINS_SHOWN, KNOWN_KINDS, GUARDS, BUILDS, ROLES, OTHER, S, ONB, OB,
      num, list, ctl, same, plural, pre, isArea, depKnown, landNow, landKnown, PRMERGE, prNow, prKnown, pushCheckOn,
      draftOf, draftPut, draftDrop, say, send, button, choice, seg, pickList, stepper, row, wouldSkip, skipWords,
      fieldLabel, areaWould, unlisted, heldUnknown, arm, limitsLine, standingShown, pickShown, CAP0, draw,
      relength, rulesSuite, suiteSlots } = shared);
    return { rules, index };
  });
})();
