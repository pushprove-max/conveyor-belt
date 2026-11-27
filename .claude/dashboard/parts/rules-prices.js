// SPDX-License-Identifier: Apache-2.0
// The Rules tab's Model prices. Part of panels/rules.js, which asks for it by name (DASH_APP.use) and gives it
// what it uses; boot.js loads it before the panels.
(() => {
  'use strict';
  // What this part uses of panels/rules.js, set when rules.js asks for the part (DASH_APP.part, at the end).
  let MODEL, ROLES, S, num, list, ctl, plural, say, run, button, draw;

  // Model prices (pricesSection): every model the built-in table or the pack prices, from the part's prices: builtIn
  // (the built-in rows), aliases (the built-in aliases: {alias: model}), overrides (the pack's entries: prices, name, provider, aliases), names (each model's own
  // display name) and seen (each model ID this project's steps ran in 30 days, with the model it is priced as). Prices
  // are $ per million tokens. Top to bottom: a search box (an ID, name or alias: the rows that do not match hide as it
  // is typed) and Add model; Seen but not priced (an ID the steps ran that no model and no alias prices; one only the
  // research lane's sessions ran (lane) is not listed, as the belt never runs it: This is… adds it as an alias of
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
  // Whether a value saved here ({repo, for, at, over}) still shows: for its project, until a snapshot begun at or after
  // the host's answer (at); with no answer time or no snapshot time, until the next snapshot (now is not for).
  // The project's is the one of view d read at read: the one on screen, or one a change was sent from (run()), whose
  // answer can come after another project is picked.
  const savedShown = (s, now, d = S.d, read = S.read) => !!s && s.repo === d.repo && (s.at !== null && read !== null ? read < s.at : s.for === now);
  // The value saved here for the project of view d (S.priceSaved, S.standingSaved, S.pickSaved, S.splitSaved keep one a project, by
  // repo), while it shows.
  const savedFor = (m, d, read, now) => { const s = m.get(d.repo); return savedShown(s, now, d, read) ? s : null; };
  // The pack's standing kinds as shown: as a change saved here left them, until a snapshot read after it comes; null
  // from a snapshot without them. Each of these four is for the project on screen, or the one of view d read at read.
  const standingShown = (d = S.d, read = S.read) => { const s = savedFor(S.standingSaved, d, read, d.standing); return s ? s.over
    : Array.isArray(d.standing) ? d.standing : null; };
  // The pack's pick lists of Pick settings (pick: {<seat>: {<model>: {min, max}}}) as shown: as a change saved here
  // left them, until a snapshot read after it comes; null from a snapshot without them.
  const pickShown = (d = S.d, read = S.read) => { const s = savedFor(S.pickSaved, d, read, d.packPick); return s ? s.over
    : d.packPick && typeof d.packPick === 'object' && d.packPick.lists && typeof d.packPick.lists === 'object' ? d.packPick.lists : null; };
  // The four limits of Split large issues ({<limit>: {n, from}}, the snapshot's packSplit) as shown: as a change saved
  // here left them, until a snapshot read after it comes; null from a snapshot without them.
  const splitShown = (d = S.d, read = S.read) => { const s = savedFor(S.splitSaved, d, read, d.packSplit); return s ? s.over
    : d.packSplit && typeof d.packSplit === 'object' ? d.packSplit : null; };
  // The pack's prices as shown: as the changes saved here left them, until a snapshot read after them comes.
  const pricesShown = (d = S.d, read = S.read) => { const s = savedFor(S.priceSaved, d, read, d.prices); return s ? s.over
    : d.prices && d.prices.overrides && typeof d.prices.overrides === 'object' ? d.prices.overrides : {}; };
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
    // A removed entry `prices set` made (no provider, such as a fast mode's own rate) comes back by set, and name if it
    // had one: `prices add` would write a name and a provider it never had, and keep it a model after a clear. An add
    // and a remove go first all the same: the host refuses the add, and so the Undo, when the pack has m again or
    // another model has it as an alias since, and set would write over that.
    const check = [['prices', ['add', m, 'other', m.slice(0, 60), '0', '0', '0']], ['prices', ['remove', m]]];
    const back = e.provider ? [['prices', ['add', m, providerOf(m, e), e.name || m, ...rates(e)]]]
      : [...check, ...(priced(e) ? [['prices', ['set', m, ...rates(e)]]] : []), ...(e.name ? [['prices', ['name', m, e.name]]] : [])];
    return [...back, ...list(e.aliases).map((x) => ['prices', ['alias', m, 'add', x]])];
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
  // saved(a), when given, is called with each change a once the host saved it (run()).
  function priceRun(changes, done, saved) {
    let o = pricesShown();
    const undo = [];
    changes.forEach((a) => { undo.unshift(...inverse(o, a)); o = applied(o, a); });
    return run(changes.map((a) => ['prices', a, ...(saved ? [() => saved(a)] : [])]),changes.map(priceWords).join('; '), done, undo);
  }

  function pricesSection() {
    const h = S.ctx.h, p = S.d.prices && typeof S.d.prices === 'object' ? S.d.prices : null, el = h('section', 'rules-prices');
    el.append(h('h3', 'board-head', 'Model prices'));
    if (!p) { el.append(h('p', 'unknown', 'The model prices were not read.')); return el; }
    const P = priceFacts(p);
    el.append(priceTop(el));
    if (S.priceAdd) el.append(addForm(P));
    if (P.unpriced.length) el.append(unpricedBox(P));
    if (P.noPrice.length) el.append(noPriceBox(P));
    modelGroups(P, el);
    opencodeGroup(P, el);
    el.append(h('p', 'board-from', 'With no cache write price, a 5-minute cache write costs 1.25 times the input price. A 1-hour cache write costs twice the input price.'));
    priceFilter(el);
    return el;
  }
  // What Model prices reads, from the part's prices p, as one object P that the section's parts are given: the pack's
  // prices as shown (over), the built-in table (built), the display names, the aliases (aliasTo), the models, the
  // models in use and those seen or offered with no price (priceUse, priceOffered).
  function priceFacts(p) {
    const over = pricesShown(), names = p.names && typeof p.names === 'object' ? p.names : {};
    const built = new Map(list(p.builtIn).filter((x) => x && typeof x.model === 'string').map((x) => [x.model, x]));
    const nameOf = (m) => (over[m] && typeof over[m].name === 'string' && over[m].name) || (typeof names[m] === 'string' && names[m]) || m;
    // The model each other ID means (the built-in aliases, then the pack's over them, as dashboard_limit.py use_prices
    // takes them: the first pack model by ID wins an alias two name; one the pack names as a model of its own is no
    // alias); the model an ID is priced as (with no date or [1m] on it).
    const aliasTo = new Map(), packed = new Set();
    Object.entries(p.aliases && typeof p.aliases === 'object' ? p.aliases : {}).forEach(([x, m]) => { if (typeof m === 'string' && !Object.hasOwn(over, x)) aliasTo.set(x, m); });
    Object.keys(over).sort().forEach((m) => list(over[m] && over[m].aliases).forEach((x) => { if (typeof x === 'string' && !packed.has(x)) { packed.add(x); aliasTo.set(x, m); } }));
    const canon = (id) => { const b = String(id).replace(/\[[^\]]*\]$/, '').replace(/-\d{8}$/, ''); return aliasTo.get(b) || b; };
    // The models: each built-in one (its fast mode is its second line) and each the pack prices or adds; a fast mode
    // whose model has no price of its own is a row of its own, as no row has it as its second line.
    const isModel = (m) => built.has(m) || priced(over[m]) || !!(over[m] && over[m].provider);
    const models = [...new Set([...built.keys(), ...Object.keys(over)])].filter((m) => isModel(m) && !(m.endsWith(':fast') && isModel(m.slice(0, -5))));
    const rateOf = (m) => (priced(over[m]) ? over[m] : built.get(m) || null);
    const P = { p, over, names, built, nameOf, aliasTo, canon, isModel, models, rateOf };
    priceUse(P);
    priceOffered(P);
    return P;
  }
  // In use: a model a role runs (its marks) or this project's steps ran in 30 days (how many); added to P.
  function priceUse(P) {
    const { p, aliasTo, canon, isModel } = P;
    const ms = S.d.modelSettings && typeof S.d.modelSettings === 'object' ? S.d.modelSettings : {}, c = ctl() || {};
    const roles = new Map(), sessions = new Map(), raw = new Set();
    // A fast mode (an ID, the alias it is given or the model the steps' sessions are priced as ends in :fast) is marked
    // and counted on its model's row, which shows it, or on its own row when its model has none (priceFacts).
    const rowId = (c) => { const b = c.replace(/:fast$/, ''); return b !== c && isModel(b) ? b : c; };
    const role = (id, t) => { raw.add(id); const m = rowId(canon(id)), l = roles.get(m) || []; if (!l.includes(t)) l.push(t); roles.set(m, l); };
    ROLES.forEach((k) => { const s = ms[k]; if (s && typeof s.model === 'string' && s.model) role(s.model, k); });
    const ts = c.tests && typeof c.tests === 'object' && typeof c.tests.model === 'string' ? c.tests : null;
    if (ts) role(ts.cli === 'opencode' && !ts.model.startsWith('opencode:') ? `opencode:${ts.model}` : ts.model, 'Tests');
    if (typeof p.research === 'string' && p.research) role(p.research, 'research lane');
    const seen = list(p.seen).filter((x) => x && typeof x.model === 'string' && num(x.sessions) !== null);
    seen.forEach((x) => {
      raw.add(x.model);
      const m = typeof x.as === 'string' ? rowId(x.as) : canon(x.model);
      sessions.set(m, (sessions.get(m) || 0) + x.sessions);
    });
    const inUse = (m) => roles.has(m) || sessions.has(m);
    // Seen but not priced: an ID of the steps that no model and no alias prices (an OpenCode one keeps OpenCode's cost).
    // One only the research lane's sessions ran (lane) is not: the belt never runs it.
    const unpriced = seen.filter((x) => x.lane !== true && x.as === null && !aliasTo.has(x.model) && !isModel(x.model) && !x.model.startsWith('opencode:'));
    Object.assign(P, { ms, roles, sessions, raw, seen, inUse, unpriced });
  }
  // The models offered with no price (noPrice), the models that are not OpenCode's by name (known), and the known
  // model an ID likely is (likely); added to P.
  function priceOffered(P) {
    const { ms, roles, seen, over, aliasTo, canon, isModel, models, nameOf } = P;
    // Offered or run with no price: a model a role runs, or one the models.allowed in force offers a role (the pack's
    // list when it sets one, with the host's Codex models added to its codex list when that list has a model in it, else the built-in models with the
    // host's Codex models in place of the built-in Codex ones, and none of them when the host has no Codex,
    // modelsallowed() in conveyor/lib/control.sh), that no
    // model and no alias prices and no step has run yet (those are Seen but not priced). OpenCode's keep the cost OpenCode reports. A one-word name (sol, opus) is a family or an alias, no
    // model ID: the CLI runs a model of its own choice, so the name has no price to add. Needs you counts these and
    // the Seen but not priced ones (noprice()).
    const offered = new Set(roles.keys());
    ROLES.forEach((k) => {
      const s = ms[k];
      if (!s) return;
      Object.entries(s.allowed && typeof s.allowed === 'object' ? s.allowed : {}).forEach(([c, o]) => {
        if (c !== 'opencode') list(o).forEach((m) => { if (typeof m === 'string' && m) offered.add(m); });
      });
    });
    const ran = new Set(seen.filter((x) => x.lane !== true).map((x) => x.model));
    const none = (m) => !m.startsWith('opencode:') && !isModel(canon(m)) && !aliasTo.has(m) && !ran.has(m);
    const noPrice = [...offered].filter((m) => !/^[a-z]{2,}$/.test(m) && none(m));
    // The models Needs you counts (the part's prices.missing, noprice()): the model a family name resolves to (sol:
    // the Codex model it runs) is in no list above until a step runs it, so each one no row shows is added.
    list(P.p.missing).forEach((m) => { if (typeof m === 'string' && m && !noPrice.includes(m) && none(m)) noPrice.push(m); });
    noPrice.sort();
    const known = models.filter((m) => providerOf(m, over[m]) !== 'opencode').sort((a, b) => nameOf(a).localeCompare(nameOf(b)));
    const norm = (s) => s.toLowerCase().replace(/\./g, '-');
    const likely = (id) => {
      const t = norm(id.replace(/^.*\//, '').replace(/^(?:[a-z0-9-]+\.)*anthropic\./i, ''));
      return known.filter((m) => t.includes(norm(m))).sort((a, b) => b.length - a.length)[0] || '';
    };
    Object.assign(P, { noPrice, known, likely });
  }

  // ---- a row and its parts ----
  const priceField = (act, label, value, set, hint) => {
    const x = S.ctx.h('input', 'field rules-field');
    x.type = 'text'; x.dataset.act = act; x.value = value; x.setAttribute('aria-label', label);
    if (hint) x.placeholder = hint;
    x.addEventListener('input', () => set(x.value));
    return x;
  };
  // A price field: $, the box, "/ M tokens".
  const priceMoney = (act, t, value, set, hint) => {
    const h = S.ctx.h, w = h('label', 'rules-price-field');
    w.append(h('span', null, t), h('span', 'rules-price-affix', '$'), priceField(act, `${t} price, dollars per million tokens`, value, set, hint), h('span', 'rules-price-affix', '/ M tokens'));
    return w;
  };
  // This is…: the model an ID means, the likely one picked first, then a button that adds the ID as its alias.
  function thisIs(P, id) {
    const h = S.ctx.h, { known, nameOf, likely } = P;
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
  const findOf = (P, m, more) => [m, P.nameOf(m), ...list(P.over[m] && P.over[m].aliases), ...(more || [])].join('\n').toLowerCase();
  const marks = (P, m) => [...(P.roles.get(m) || []).map((t) => S.ctx.chip(t, 'info')),
    ...(P.sessions.has(m) ? [S.ctx.chip(`${plural(P.sessions.get(m), 'session', 'sessions')} in 30 days`, 'quiet')] : [])];
  // The row open in Edit: display name and other IDs (not for an OpenCode model's own price), the four prices, and
  // Save, Cancel and Reset to built-in.
  function editRow(P, m, tr) {
    const h = S.ctx.h, { over, built, nameOf } = P;
    const ed = S.priceEdit, e = over[m] || {}, b = built.get(m), box = h('div', 'rules-price-editform');
    if (!ed.ratesOnly) box.append(...editNames(P, m, ed));
    PRICE_KEYS.forEach(([k, t]) => box.append(priceMoney(`price-${k}`, t, ed[k], (v) => { ed[k] = v; }, k === 'cacheWrite' ? '1.25 × input' : '0')));
    box.append(button('Save', 'btn-quiet', 'price-save', `Save ${m}`, () => editSave(P, m, e, ed)),
      button('Cancel', 'btn-quiet', 'price-cancel', `Close ${m} with nothing saved`, () => { S.priceEdit = null; draw(); }));
    if (priced(e) && b) box.append(resetButton(P, m, b));
    const td = h('td', null);
    td.colSpan = 7; td.append(h('strong', null, nameOf(m)), h('span', 'board-from', ` ${m}`), box);
    tr.classList.add('rules-price-editing');
    tr.append(td);
    return tr;
  }
  // The display name and other IDs of model m in Edit (editRow), as typed (ed).
  function editNames(P, m, ed) {
    const h = S.ctx.h, { names, aliasTo, isModel, nameOf } = P;
    const ids = h('div', 'rules-item rules-price-ids');
    ids.append(h('span', null, 'Other IDs:'));
    ed.aliases.forEach((x) => ids.append(h('span', 'rules-price-alias', x), button('×', 'btn-quiet', 'price-alias-drop', `${x} is not ${m}`, () => { ed.aliases = ed.aliases.filter((y) => y !== x); draw(); })));
    ids.append(priceField('price-alias-new', `Another model ID that is ${m}`, ed.alias, (v) => { ed.alias = v; }, 'proxy/model-id'), button('+ add', 'btn-quiet', 'price-alias-add', `Add the ID typed as ${m}`, () => {
      const x = ed.alias.trim(), to = aliasTo.get(x);
      const why = !MODEL.test(x) ? `"${x}" is not a model ID.` : x === m ? 'A model is not an alias of itself.' : isModel(x) ? `${x} is a model of its own.`
        : to && to !== m ? `${x} is already ${nameOf(to)}.` : null;
      if (why) { say(why); return; }
      if (!ed.aliases.includes(x)) ed.aliases.push(x);
      ed.alias = ''; draw();
    }));
    return [h('label', 'rules-price-field', 'Display name'), priceField('price-name', `Display name of ${m}`, ed.name, (v) => { ed.name = v; }, names[m] || m), ids];
  }
  // Save in Edit (editRow): sends what differs of model m (e: its pack entry) as typed (ed). The prices are sent only
  // when they differ from both the pack's now and the ones this edit last knew the pack to hold (ed.base): as opened
  // (ed.start), or as an earlier Save of this edit saved them. So prices left as they were never overwrite a price
  // changed elsewhere while Edit was open, also after a snapshot replaces the price shown as saved, and what an earlier
  // Save saved before the host refused a later change is not sent again. A price is the same as another written as the
  // same number (3.00 is the 3 the pack stores). A display name that is the model's own name counts as none, so Save
  // clears a pack name that equals it.
  function editSave(P, m, e, ed) {
    const { names } = P;
    const v = PRICE_KEYS.map(([k]) => String(ed[k]).trim()), changes = [];
    const asPack = (o) => (priced(o) ? Object.fromEntries(PRICE_KEYS.map(([k]) => [k, num(o[k]) !== null ? String(o[k]) : ''])) : null);
    // A price typed in the host's form (prices.sh) with the value held counts as the same: 3.0 is the 3 saved.
    const form = /^(0|[1-9][0-9]{0,5})(\.[0-9]{1,6})?$/, eq = (x, y) => x === y || (form.test(x) && form.test(y) && +x === +y);
    const same = (a, b) => !!a && !!b && PRICE_KEYS.every(([k]) => eq(a[k], b[k]));
    const typed = Object.fromEntries(PRICE_KEYS.map(([k], i) => [k, v[i]]));
    let sent = null;
    if (!same(typed, asPack(e)) && !same(typed, ed.base || ed.start)) {
      if (v.slice(0, 3).some((x) => !x)) { say('Give the input, output and cache read prices.'); return; }
      changes.push(['set', m, ...v.slice(0, 3), ...(v[3] ? [v[3]] : [])]);
      sent = typed;
    }
    if (!ed.ratesOnly) {
      const n = ed.name.trim(), had = typeof e.name === 'string' ? e.name : '', want = n && n !== (names[m] || m) ? n : '';
      if (want !== had) changes.push(want ? ['name', m, want] : ['name', m]);
      const was = list(e.aliases);
      ed.aliases.filter((x) => !was.includes(x)).forEach((x) => changes.push(['alias', m, 'add', x]));
      was.filter((x) => !ed.aliases.includes(x)).forEach((x) => changes.push(['alias', m, 'remove', x]));
    }
    if (!changes.length) { S.priceEdit = null; draw(); return; }
    // The pack holds the prices sent once the host answered that their own set is saved, though it refused a later
    // change. Not the prices saved or shown after the run: a snapshot that came between the set's answer and a later
    // change's holds a price set elsewhere, and another project can be picked meanwhile.
    priceRun(changes, () => { S.priceEdit = null; }, (a) => { if (a[0] === 'set') ed.base = sent; });
  }
  // Reset names the price that clearing m gives: the fast mode of a model with your price then costs twice that
  // price, not its built-in price (use_prices in dashboard_limit.py).
  const resetButton = (P, m, b) => {
    const fast = m.endsWith(':fast'), base = fast && P.over[m.slice(0, -5)], mine = fast && priced(base), to = mine ? twiceOf(base) : b;
    return button(`${fast ? 'Reset :fast' : 'Reset'} to ${mine ? 'twice your price' : 'built-in'} (${['input', 'output', 'cacheRead'].map((k) => usd(to[k])).join(' / ')} / ${usd(writeOf(to))})`, 'btn-quiet', fast ? 'price-fast-reset' : 'price-reset',
      `Put ${m} back to ${mine ? `twice your price of ${m.slice(0, -5)}` : 'its built-in price'}`, () => priceRun([['clear', m]], () => { if (S.priceEdit && S.priceEdit.model === m) S.priceEdit = null; }));
  };
  // The cache write Edit starts at, '' for the 1.25 × input default: the pack's own, else (a fast mode the pack does not
  // price, ratesOnly) the one of the prices its fields start at (from) when the pack's price of the model sets a cache
  // write or from differs from the default, so a Save of another price keeps it.
  const startWrite = (P, m, ratesOnly, from) => {
    const e = P.over[m] || {};
    if (priced(e)) return num(e.cacheWrite) !== null ? String(e.cacheWrite) : '';
    if (!ratesOnly || !from || num(from.cacheWrite) === null) return '';
    const base = P.over[m.replace(/:fast$/, '')], set = priced(base) && num(base.cacheWrite) !== null;
    return set || from.cacheWrite !== from.input * 1.25 ? String(from.cacheWrite) : '';
  };
  // from: the prices the fields start at, for a fast mode the pack does not price (its row's second line). start: the
  // prices as opened, which Save compares with until a Save of this edit saves others (editSave).
  const openEdit = (P, m, ratesOnly, from) => {
    const e = P.over[m] || {}, r = (ratesOnly ? (priced(e) ? e : from) : P.rateOf(m)) || {};
    const f = { ...Object.fromEntries(RATES.map((k) => [k, num(r[k]) !== null ? String(r[k]) : ''])), cacheWrite: startWrite(P, m, ratesOnly, from) };
    S.priceEdit = { model: m, ratesOnly, name: typeof e.name === 'string' ? e.name : '', aliases: list(e.aliases).slice(), alias: '', ...f, start: f };
    draw();
  };
    // A model's row: its name (bold), marks, ID and other IDs; its prices and where they are from; Edit, and Reset to
    // built-in for a price from the pack or Remove for an added model. Its fast mode is the second line of each cell.
  function row(P, m) {
    const h = S.ctx.h, { over, built, isModel, rateOf, nameOf } = P;
    const tr = h('tr', 'rules-price');
    tr.dataset.model = m; tr.dataset.group = `price:${m}`; tr.dataset.find = findOf(P, m); tr.dataset.family = lineOf(m);
    if (S.priceEdit && S.priceEdit.model === m) return editRow(P, m, tr);
    if (S.priceEdit && S.priceEdit.model === `${m}:fast`) return editRow(P, `${m}:fast`, tr);
    const e = over[m] || {}, b = built.get(m), mine = priced(e), r = rateOf(m), added = !b && isModel(m);
    const fast = fastOf(P, m, e, mine);
    const two = (main, second) => { const td = h('td', null); td.append(h('div', null, main)); if (fast) td.append(h('div', 'rules-price-fastline', second)); return td; };
    const name = h('td', 'rules-price-name');
    name.append(h('strong', null, nameOf(m)), ...(added ? [S.ctx.chip('added', 'quiet')] : []), ...marks(P, m),
      h('div', 'board-from', `${m}${list(e.aliases).length ? ` · also: ${list(e.aliases).join(', ')}` : ''}`));
    if (fast) name.append(h('div', 'rules-price-fastline', ':fast'));
    tr.append(name, ...PRICE_KEYS.map(([k]) => {
      const td = two(r ? usd(k === 'cacheWrite' ? writeOf(r) : r[k]) : '—', fast ? usd(k === 'cacheWrite' ? writeOf(fast[0]) : fast[0][k]) : '');
      td.className = 'num'; return td;
    }), two(mine || (added && r) ? 'Saved, from the pack' : r ? 'built in' : 'not priced', fast ? fast[1] : ''));
    tr.append(rowActs(P, m, { b, mine, added, fast }));
    return tr;
  }
  // A fast mode the pack does not price, of a model it does, costs twice that price (use_prices in dashboard_limit.py):
  // the fast mode of model m (e: its pack entry; mine: the pack prices it) as [its prices, where they are from], or null.
  function fastOf(P, m, e, mine) {
    const fo = P.over[`${m}:fast`], fb = P.built.get(`${m}:fast`);
    return priced(fo) ? [fo, 'Saved, from the pack'] : mine && fb ? [twiceOf(e), 'twice your price'] : fb ? [fb, 'built in'] : null;
  }
  // The actions of model m's row (row): Edit, Reset to built-in, Edit :fast and its Reset or Remove, Remove. b: its
  // built-in prices; mine: the pack prices it; added: the pack adds it; fast: its fast mode (fastOf).
  function rowActs(P, m, { b, mine, added, fast }) {
    const acts = S.ctx.h('td', 'rules-price-acts'), fo = P.over[`${m}:fast`], fb = P.built.get(`${m}:fast`);
    acts.append(button('Edit', 'btn-quiet', 'price-edit', `Edit ${m}`, () => openEdit(P, m, false)));
    if (mine && b) acts.append(resetButton(P, m, b));
    // The fast mode's own price: Edit :fast saves it under <model>:fast; one from the pack has its own Reset.
    if (fast) acts.append(button('Edit :fast', 'btn-quiet', 'price-fast-edit', `Edit the fast mode price of ${m}`, () => openEdit(P, `${m}:fast`, true, fast[0])));
    if (priced(fo)) {
      acts.append(fb ? resetButton(P, `${m}:fast`, fb) : button('Remove :fast price', 'btn-quiet', 'price-fast-reset', `Take the fast mode price of ${m} off`,
        () => priceRun([['clear', `${m}:fast`]], () => { if (S.priceEdit && S.priceEdit.model === `${m}:fast`) S.priceEdit = null; })));
    }
    if (added) acts.append(button('Remove', 'btn-quiet', 'price-remove', `Remove ${m}`, () => priceRun([['remove', m]])));
    return acts;
  }
  const writeOrRate = (r, k) => (k === 'cacheWrite' ? writeOf(r) : r[k]);
  const twiceOf = (r) => Object.fromEntries(PRICE_KEYS.map(([k]) => [k, 2 * writeOrRate(r, k)]));
  // An OpenCode model: priced as OpenCode reports (the default), at your price, or as the model it is marked as.
  function ocRow(P, id) {
    const h = S.ctx.h, { over, aliasTo, rateOf, raw, nameOf } = P;
    const tr = h('tr', 'rules-price rules-price-oc');
    tr.dataset.model = id; tr.dataset.group = `price:${id}`; tr.dataset.find = findOf(P, id, [id.replace(/^opencode:/, '')]);
    if (S.priceEdit && S.priceEdit.model === id) return editRow(P, id, tr);
    const to = aliasTo.get(id), e = over[id], r = to ? rateOf(to) : priced(e) ? e : null;
    const name = h('td', 'rules-price-name');
    name.append(h('strong', null, id.replace(/^opencode:/, '')), ...(raw.has(id) ? [S.ctx.chip('in use', 'info')] : []));
    tr.append(name, ...PRICE_KEYS.map(([k]) => h('td', 'num', r ? usd(writeOrRate(r, k)) : '—')),
      h('td', null, to ? `${nameOf(to)}'s price` : priced(e) ? 'your price' : 'as OpenCode reports'));
    const acts = h('td', 'rules-price-acts');
    if (to) acts.append(button(`Not ${nameOf(to)}`, 'btn-quiet', 'price-oc-unalias', `Price ${id} as OpenCode reports again`, () => priceRun([['alias', to, 'remove', id]])));
    else if (priced(e)) acts.append(button('Back to OpenCode\'s', 'btn-quiet', 'price-oc-back', `Price ${id} as OpenCode reports again`, () => priceRun([['clear', id]])));
    else acts.append(button('Set my price', 'btn-quiet', 'price-oc-set', `Set your price of ${id}`, () => openEdit(P, id, true)), ...thisIs(P, id));
    tr.append(acts);
    return tr;
  }
  function tableOf(rows, heads) {
    const h = S.ctx.h, t = h('table', 'rules-prices-table'), top = h('tr', null);
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
    const h = S.ctx.h, g = h('div', 'rules-price-group');
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
  // The search box and + Add model, over the section el.
  function priceTop(el) {
    const h = S.ctx.h, top = h('div', 'rules-add rules-prices-top'), find = h('input', 'field rules-field rules-price-search');
    find.type = 'search'; find.dataset.act = 'price-search'; find.placeholder = 'Search a model or alias'; find.value = S.priceFind;
    find.setAttribute('aria-label', 'Search the models by ID, name or alias');
    find.addEventListener('input', () => { S.priceFind = find.value; priceFilter(el); });
    top.append(find, button('+ Add model', 'btn-quiet', 'price-add', 'Add a model the table has not got', () => { S.priceAdd = S.priceAdd || addDraft(''); draw(); }),
      h('span', 'board-from', '$ per million tokens. Saved in the pack.'));
    return top;
  }
  function addDraft(id) {
    return { model: id, name: id, provider: providerOf(id, null), input: '', output: '', cacheRead: '', cacheWrite: '' };
  }
  // Add model, as typed (S.priceAdd).
  function addForm(P) {
    const h = S.ctx.h, { models, rateOf, nameOf } = P;
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
    form.append(h('strong', null, 'Add model'), priceField('price-add-model', 'Model ID, as sessions report it', f.model, (v) => { f.model = v; }, 'Model ID, as sessions report it'),
      priceField('price-add-name', 'Display name', f.name, (v) => { f.name = v; }, 'Display name'), prov,
      ...PRICE_KEYS.map(([k, t]) => priceMoney(`price-add-${k}`, t, f[k], (v) => { f[k] = v; }, k === 'cacheWrite' ? '1.25 × input' : '0')), same,
      button('Save', 'btn-quiet', 'price-add-save', 'Save this model in the pack', () => addSave(P, f)),
      button('Cancel', 'btn-quiet', 'price-add-cancel', 'Close Add model with nothing saved', () => { S.priceAdd = null; draw(); }));
    return form;
  }
  // Save in Add model (addForm): sends the model typed (f), or says what is missing.
  function addSave(P, f) {
    const m = f.model.trim(), n = f.name.trim(), v = PRICE_KEYS.map(([k]) => f[k].trim());
    const why = !MODEL.test(m) ? 'Give the model ID, as sessions report it.' : P.isModel(m) || P.aliasTo.has(m) ? `${m} is priced already: use Edit on its row.`
      : !n || n.length > 60 ? 'Give a display name of up to 60 characters.' : v.slice(0, 3).some((x) => !x) ? 'Give the input, output and cache read prices.' : null;
    if (why) { say(why); return; }
    priceRun([['add', m, f.provider, n, ...v.slice(0, 3), ...(v[3] ? [v[3]] : [])]], () => { S.priceAdd = null; });
  }
  // Seen but not priced (P.unpriced), each with This is… and Add as new model.
  function unpricedBox(P) {
    const h = S.ctx.h, box = h('div', 'rules-prices-unpriced');
    box.append(h('h4', 'rules-price-title', 'Seen but not priced'));
    P.unpriced.forEach((x) => {
      const line = h('div', 'rules-item rules-unpriced');
      line.dataset.model = x.model; line.dataset.group = `price:${x.model}`; line.dataset.find = x.model.toLowerCase();
      line.append(h('span', null, `${x.model} (${plural(x.sessions, 'session', 'sessions')}${list(x.routes).includes('proxy') ? ', through the API proxy' : ''})`),
        ...thisIs(P, x.model), button('Add as new model', 'btn-quiet', 'price-new', `Add ${x.model} as a model of its own`, () => { S.priceAdd = addDraft(x.model); draw(); }));
      box.append(line);
    });
    return box;
  }
  // Offered with no price (P.noPrice), each with This is… and Add as new model.
  function noPriceBox(P) {
    const h = S.ctx.h, box = h('div', 'rules-prices-noprice');
    box.append(h('h4', 'rules-price-title', 'Offered with no price'));
    P.noPrice.forEach((m) => {
      const line = h('div', 'rules-item rules-noprice');
      line.dataset.model = m; line.dataset.group = `price:${m}`; line.dataset.find = m.toLowerCase();
      const by = P.roles.get(m);
      line.append(h('span', null, `${m} (no price${by ? `; in use by ${by.join(', ')}` : ''})`),
        ...thisIs(P, m), button('Add as new model', 'btn-quiet', 'price-new', `Add ${m} as a model of its own`, () => { S.priceAdd = addDraft(m); draw(); }));
      box.append(line);
    });
    return box;
  }
  // The groups of the models that are not OpenCode's: In use by this project, then one a provider, each with its older
  // models folded.
  function modelGroups(P, el) {
    const { models, over, built, inUse } = P, prow = (m) => row(P, m);
    const own = models.filter((m) => providerOf(m, over[m]) !== 'opencode');
    const used = own.filter(inUse).sort((a, b) => PROVIDERS.findIndex(([k]) => k === providerOf(a, over[a])) - PROVIDERS.findIndex(([k]) => k === providerOf(b, over[b])) || byFamily(a, b));
    if (used.length) el.append(group('use', 'In use by this project', used.map(prow), [], ''));
    // Older: a built-in model with a newer one of its line (Opus 4.8 after Opus 5.5).
    const older = (m) => built.has(m) && own.some((x) => x !== m && built.has(x) && providerOf(x, over[x]) === providerOf(m, over[m]) && lineOf(x) === lineOf(m) && newer(x, m) < 0);
    [['claude', 'Claude', (m) => lineOf(m).replace(/^./, (x) => x.toUpperCase())], ['openai', 'OpenAI', () => 'GPT'], ['other', 'Other', null]].forEach(([k, t, heads]) => {
      const all = own.filter((m) => providerOf(m, over[m]) === k && !inUse(m)).sort(byFamily);
      if (!all.length) return;
      el.append(group(k, t, all.filter((m) => !older(m)).map(prow), all.filter(older).map(prow), `Older ${t} models`, heads));
    });
  }
  // OpenCode: the models OpenCode can run on the build machine, and every OpenCode ID the pack or the steps name.
  function opencodeGroup(P, el) {
    const h = S.ctx.h, { models, over, ms, aliasTo, raw, isModel } = P;
    const oc = new Set(models.filter((m) => providerOf(m, over[m]) === 'opencode'));
    ROLES.forEach((k) => { const s = ms[k], o = s && s.clis && s.clis.opencode; list(o && o.models).forEach((x) => { if (typeof x === 'string' && x) oc.add(`opencode:${x}`); }); });
    [...Object.keys(over), ...aliasTo.keys(), ...raw].forEach((x) => { if (typeof x === 'string' && x.startsWith('opencode:')) oc.add(x); });
    if (!oc.size) return;
    const ids = [...oc].sort(), shown = (x) => raw.has(x) || priced(over[x]) || aliasTo.has(x) || isModel(x);
    // A model added in the pack (it has a provider) is a model's row, with its name, Edit and Remove; an OpenCode ID
    // with only your price is an OpenCode row.
    const asModel = (x) => isModel(x) && (!x.startsWith('opencode:') || !!(over[x] && over[x].provider));
    const g = group('opencode', 'OpenCode', ids.filter(shown).map((x) => (asModel(x) ? row(P, x) : ocRow(P, x))),
      ids.filter((x) => !shown(x)).map((x) => ocRow(P, x)), 'All OpenCode models');
    g.append(h('p', 'board-from', 'An OpenCode step is priced as OpenCode reports, unless you set your price or mark its model as a known one.'));
    el.append(g);
  }
  // The search over the section el: the rows, groups and family heads with no match hide; a folded group with a
  // match opens.
  function priceFilter(el) {
    const q = S.priceFind.trim().toLowerCase();
    el.querySelectorAll('[data-find]').forEach((r) => { r.hidden = !!q && !r.dataset.find.includes(q); });
    el.querySelectorAll('.rules-price-family').forEach((r) => {
      r.hidden = !!q && !Array.from(r.closest('table').querySelectorAll(`.rules-price[data-family="${r.dataset.family}"]`)).some((x) => !x.hidden);
    });
    el.querySelectorAll('.rules-price-group, .rules-prices-unpriced, .rules-prices-noprice').forEach((g) => { g.hidden = !!q && !g.querySelector('[data-find]:not([hidden])'); });
    if (q) el.querySelectorAll('details.rules-price-older').forEach((d) => { if (d.querySelector('[data-find]:not([hidden])')) d.open = true; });
  }
  window.DASH_APP.part('rules-prices', function (shared) {
    ({ MODEL, ROLES, S, num, list, ctl, plural, say, run, button, draw } = shared);
    return { savedShown, standingShown, pickShown, splitShown, pricesShown, applied, priceWords, pricesSection };
  });
})();
