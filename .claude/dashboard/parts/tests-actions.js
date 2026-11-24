// SPDX-License-Identifier: Apache-2.0
// The Tests panel's actions: the Tests model, the bar of the files selected, Optimize, Recent actions, Removed
// by Optimize, Test edits by cards and Auto-file. Part of panels/tests.js, which asks for it by name
// (DASH_APP.use) and gives it what it uses; boot.js loads it before the panels.
(() => {
  'use strict';
  // What this part uses of panels/tests.js, set when tests.js asks for the part (DASH_APP.part, at the end).
  let PACK, CONTROL, S, num, list, obj, one, pct, tests, rules, dk, inForce, shown, marks, say, button, row,
    section, setting, ACTS, FILES_MAX, RUNNER_WHY, MODEL, OTHER, ID, TITLE_MAX, BODY_MAX, NO_SEAT, WAIT, SENDING, ta,
    ctlTests, actions, mmss, limitOf, used, seatOf, tmodel, MUT_WHY, mutAsk, progress, mutNow, actBtn, send, copy,
    actArgs, stop, result, running, queued, live, queuedSaid, actNow, md, draftIssue, shows, asking, field,
    anyIssueUrl, noIssue, draw;

  // ---- the Tests model: CLI, model (Other… for a typed name) and effort, as the Rules tab's roles ----
  function seatCtl() {
    const h = S.ctx.h, repo = S.d.repo, clis = obj(S.d.clis) || {}, inForce = tmodel();
    const set = { cli: inForce ? inForce.cli : '', model: inForce ? inForce.model : '', effort: inForce && inForce.effort ? inForce.effort : '' };
    const v = S.tmodel.get(repo) || Object.assign({ other: false }, set);
    const of = v.cli ? obj(clis[v.cli]) : null;
    // An installed CLI offers its own models with the pack's models for it (testActions.allowed) after them, each
    // once, as the Rules tab's roles do: the pack's list adds models to the CLI's; then Other… for a name typed in.
    const listed = !of ? [] : Array.from(new Set(list(of.models).concat(list((obj(ta().allowed) || {})[v.cli])).filter((m) => typeof m === 'string' && m)));
    const typed = !!v.cli && (v.other || (v.model !== '' && !listed.includes(v.model)) || !listed.length);
    const unsaved = () => { const d = S.tmodel.get(repo); return !!d && (d.cli !== set.cli || d.model.trim() !== set.model || d.effort !== set.effort); };
    const edit = (o) => {
      const d = Object.assign({}, S.tmodel.get(repo) || v, o);
      if (d.cli === set.cli && d.model.trim() === set.model && d.effort === set.effort && !d.other) S.tmodel.delete(repo); else S.tmodel.set(repo, d);
      draw();
    };
    const select = seatSelect;
    const cli = select('tmodel-cli', 'Tests model: CLI', [['', 'Default (none)']].concat(Object.keys(clis).map((c) => [c, c])), v.cli,
      (x) => edit({ cli: x, model: '', effort: '', other: false }));
    const model = select('tmodel-model', 'Tests model: model', v.cli ? [['', 'Pick a model']].concat(listed.map((m) => [m, m]), [[OTHER, 'Other…']]) : [['', 'No model']],
      typed ? OTHER : v.model, (x) => (x === OTHER ? edit({ other: true, model: listed.includes(v.model) ? '' : v.model }) : edit({ model: x, other: false })));
    model.disabled = !v.cli;
    const out = [cli, model];
    if (typed) {
      out.push(field('tmodel-model-other', 'Tests model: model, not listed', v.model, (x) => { S.tmodel.set(repo, Object.assign({}, S.tmodel.get(repo) || v, { model: x, other: true })); mark(); },
        { placeholder: `a ${v.cli} model`, max: 192 }));
    }
    const effort = select('tmodel-effort', 'Tests model: effort', [['', 'Default effort']].concat(list(of && of.efforts).filter((e) => typeof e === 'string').map((e) => [e, e])), v.effort, (x) => edit({ effort: x }));
    effort.disabled = !v.cli;
    const flag = S.ctx.chip('Unsaved', 'warn');
    const save = button('Save', 'btn-primary', 'tmodel-save', 'Save the Tests model: CLI, model and effort', () => seatSave(repo));
    const cancel = button('Cancel', 'btn-quiet', 'tmodel-cancel', 'Put the Tests model back as it is in force', () => { S.tmodel.delete(repo); draw(); });
    // In force says what is saved only while the selects show another value (an unsaved change): else it repeats them.
    const was = h('span', 'board-from tests-in-force', `In force: ${inForce ? `${inForce.cli} · ${inForce.model} · ${inForce.effort || 'default effort'}` : 'none'}`);
    function mark() { const on = unsaved(); [flag, save, cancel, was].forEach((x) => { x.hidden = !on; }); }
    mark();
    out.push(effort, flag, save, cancel, was);
    return out;
  }
  // A menu of the Tests model (seatCtl): opts [value, text], value picked; fn(value) on a change.
  function seatSelect(act, label, opts, value, fn) {
    const h = S.ctx.h, s = h('select', 'field board-select');
    opts.forEach(([x, t]) => { const o = h('option', null, t); o.value = x; o.selected = x === value; s.append(o); });
    s.dataset.act = act; s.setAttribute('aria-label', label);
    s.addEventListener('change', () => fn(s.value));
    return s;
  }
  // Save of the Tests model (seatCtl): sends the model picked for project repo, or says what is missing.
  function seatSave(repo) {
    const d = S.tmodel.get(repo);
    if (!d) return;
    const m = d.model.trim();
    if (d.cli && !m) { say('Pick a model first.'); return; }
    if (d.cli && !MODEL.test(m)) { say('A model is one word of letters, digits and . _ : / @ [ ] -, starting with a letter or a digit.'); return; }
    const args = d.cli ? [d.cli, m].concat(d.effort ? [d.effort] : []) : ['default'];
    send('tests', args, () => `Saved: the Tests model is now ${d.cli ? `${d.cli} · ${m} · ${d.effort || 'default effort'}` : 'not set'}.`, (t, at) => {
      S.tmodel.delete(repo);
      S.seatSaved = { repo, value: d.cli ? { cli: d.cli, model: m, effort: d.effort || null } : null, was: seatOf(ctlTests()), at, read: S.read };
    });
  }
  function actionsHead() {
    const el = section('tests-actions', 'Test actions', CONTROL);
    el.append(row('tmodel', 'Model for Tests actions', 'Judge and Explain the slowdown use this CLI, model and effort. Run uses none.', null, ...seatCtl()));
    return el;
  }

  // ---- the bar of the files selected: Judge, Optimize, Run and Clear, and the answer for each file ----
  // The files an action of the bar acts on, in the table's order, and those it leaves out with why.
  function chosen(files, how) {
    const out = { files: [], left: [] };
    files.filter((f) => S.sel.has(f.file)).forEach((f) => {
      const why = how === 'judge' && !tmodel() ? NO_SEAT : how === 'optimize' && f.wholeOnly === true ? RUNNER_WHY : null;
      if (why) out.left.push({ file: f.file, why }); else out.files.push(f);
    });
    return out;
  }
  // One answer a file: the server answers {results: [{file, id} or {file, refused}]} for a list of files, and the text
  // of the one action (its id or address on the last line) for a single file.
  function answersOf(files, text) {
    let r;
    try { r = JSON.parse(text); } catch { r = null; }
    if (obj(r) && Array.isArray(r.results)) {
      return r.results.filter(obj).map((x) => (typeof x.id === 'string' ? { file: String(x.file), ok: true, text: x.id } : { file: String(x.file), ok: false, text: String(x.refused || 'refused') }));
    }
    const last = String(text).split('\n').pop().trim();
    return files.map((file) => ({ file, ok: true, text: last }));
  }
  // An action of the bar on its files: Judge or Run (testaction, then each action started shows on its row as one
  // started there does) or the issues of Optimize (test-issue). The bar says it is sent at once; then each file's
  // answer (an action started shows its state there until it ends, then its result), and those left out, show in it.
  function bulk(what, action, args, files, left, done) {
    const kind = action === 'testaction' ? 'act' : 'issue';
    if (files.length > FILES_MAX) { S.answers = { what, kind, lines: [], left, note: `At most ${FILES_MAX} files at a time: ${files.length} are selected. Select fewer.` }; draw(); return; }
    if (S.busy) { S.answers = { what, kind, lines: [], left, note: WAIT }; draw(); return; }
    S.answers = { what, kind, pending: true, lines: [], left, note: null };
    send(action, args, (t) => { const a = answersOf(files, t); return `${what}: ${a.filter((x) => x.ok).length} of ${a.length} taken.`; }, (t) => {
      const lines = answersOf(files, t);
      S.answers = { what, kind, lines, left, note: null };
      if (done) done(lines);
    }, (why) => { S.answers = { what, kind, lines: files.map((file) => ({ file, ok: false, text: why })), left, note: null }; });
  }
  // A line of the bar's answer: an action started, its state now (its record, else as started here) and, once it
  // ended, its text to open; a Mutation check, its file's check now; else what the build machine answered.
  function answerLine(a, l, files) {
    const h = S.ctx.h, li = h('li', l.ok ? null : 'tests-refused'), f = files.find((x) => x.file === l.file);
    li.dataset.file = l.file;
    const s = S.started.get(dk(l.file)), x = a.kind === 'act' && l.ok ? actions().find((y) => y.id === l.text) || (s && s.id === l.text ? s : null) : null;
    if (x) {
      li.append(`${l.file}: ${a.what}: `, ...actNow(x));
      const text = S.texts.get(x.id) || '';
      if (!live(x) && text) {
        const d = h('details', 'tests-bar-text');
        d.open = S.barText.has(x.id);
        d.addEventListener('toggle', () => { if (d.open) S.barText.add(x.id); else S.barText.delete(x.id); });
        d.append(h('summary', null, 'Its text'), x.action === 'run' ? h('pre', 'tests-out', text) : md(text));
        li.append(d);
      }
    } else if (a.kind === 'mutate' && l.ok && f) li.append(`${l.file}: ${a.what}: `, ...mutNow(f));
    else li.textContent = `${l.file}: ${l.ok ? `${a.what}, taken: ${l.text}` : `${a.what}, refused: ${l.text}`}`;
    return li;
  }
  function startMany(how, files) {
    const { files: fs, left } = chosen(files, how), names = fs.map((f) => f.file);
    if (!names.length) { S.answers = { what: ACTS[how], kind: 'act', lines: [], left, note: 'No file to act on.' }; draw(); return; }
    bulk(ACTS[how], 'testaction', [...actArgs(how), ...names], names, left, (lines) => lines.forEach((l) => {
      if (!l.ok || !ID.test(l.text)) return;
      S.started.set(dk(l.file), { id: l.text, action: how, file: l.file, start: new Date(S.ctx.now()).toISOString(), state: 'running' });
    }));
  }
  function selBar(files) {
    const h = S.ctx.h, el = h('section', 'tests-selbar'), n = files.filter((f) => S.sel.has(f.file)).length;
    el.setAttribute('aria-label', 'Selected test files');
    const status = h('div', 'tests-selbar-status');
    status.setAttribute('aria-live', 'polite');
    status.append(h('p', 'board-label tests-selbar-count', `${n} selected`));
    const btns = h('div', 'tests-act-row');
    // With no Tests model (or every file a runner, for Optimize) a click says why in the bar: each file left out.
    const judge = actBtn('Judge', 'bulk-judge', `Judge the ${n} selected files`, () => startMany('judge', files));
    if (!tmodel()) judge.title = NO_SEAT;
    // With the Rules tab's Cards with no GitHub issue: Tests page actions On (noIssue()), it starts a card for each, with no GitHub issue, in place of the preview.
    const opt = actBtn('Optimize', 'bulk-optimize', `Optimize: ${noIssue() ? 'start a card with no GitHub issue' : 'preview an issue'} for each of the ${n} selected files`, () => {
      const { files: fs, left } = chosen(files, 'optimize');
      S.answers = null;  // the preview names the files left out
      if (!fs.length) { S.answers = { what: 'Optimize', lines: [], left, note: 'No file to act on.' }; draw(); return; }
      if (fs.length > FILES_MAX) { S.answers = { what: 'Optimize', lines: [], left, note: `At most ${FILES_MAX} files at a time: ${fs.length} are selected. Select fewer.` }; draw(); return; }
      const items = fs.map((f) => { const d = draftIssue(f); return { file: f.file, title: d.title, body: d.body }; });
      if (noIssue()) { bulk('Optimize', 'test-issue', items.flatMap((it) => [it.file, it.title, it.body]), items.map((it) => it.file), left); return; }
      S.ask = { kind: 'many', repo: S.d.repo, items, left };
      S.keep = { act: 'many-title', file: fs[0].file }; draw();
    });
    if (!chosen(files, 'optimize').files.length) opt.title = RUNNER_WHY;
    const mut = actBtn('Mutation check', 'bulk-mutate', `Mutation check of the ${n} selected files: at the front of the idle queue. ${MUT_WHY}`,
      () => mutAsk(files.filter((f) => S.sel.has(f.file)).map((f) => f.file), true));
    mut.title = MUT_WHY;
    btns.append(judge, opt, actBtn('Run', 'bulk-run', `Run the ${n} selected files now`, () => startMany('run', files)), mut,
      actBtn('Clear', 'bulk-clear', 'Clear the selection', () => {
        S.sel.clear(); S.answers = null; if (asking('many')) S.ask = null; draw(); say('Selection cleared.');
      }));
    if (!tmodel()) btns.append(h('span', 'tests-why', `Judge: ${NO_SEAT}`));
    const a = S.answers;
    if (a) {
      const ul = h('ul', 'tests-selbar-answers');
      if (a.pending) { const li = h('li', 'tests-sending'); li.append(progress(`Sending: ${a.what}`), `${a.what}: ${SENDING}`); ul.append(li); }
      a.lines.forEach((l) => ul.append(answerLine(a, l, files)));
      a.left.forEach((l) => { const li = h('li', 'tests-why', `${l.file}: left out of ${a.what}: ${l.why}`); li.dataset.file = l.file; ul.append(li); });
      if (a.note) ul.append(h('li', 'tests-refused', a.note));
      if (a.said) ul.append(h('li', 'tests-why tests-said', a.said));
      status.append(ul);
    }
    el.append(status, btns);
    if (asking('many')) el.append(manyPreview());
    return el;
  }
  // Optimize's preview for the files selected: one issue a file, its title and body editable; "File N issues" sends
  // them all in one test-issue, and Cancel files nothing.
  function manyPreview() {
    const h = S.ctx.h, a = S.ask, el = h('div', 'tests-preview tests-selbar-preview'), n = a.items.length;
    el.dataset.armed = '';
    el.append(h('p', 'board-head', `Preview of ${n} ${n === 1 ? 'issue' : 'issues'}, one a file. Edit them, then file them.`));
    a.items.forEach((it) => {
      const item = h('div', 'tests-preview');
      item.dataset.file = it.file;
      item.append(h('p', 'board-label', it.file),
        field('many-title', `Title of the issue about ${it.file}`, it.title, (v) => { it.title = v; }, { max: TITLE_MAX }),
        field('many-body', `Text of the issue about ${it.file}`, it.body, (v) => { it.body = v; }, { area: true, max: BODY_MAX }));
      el.append(item);
    });
    a.left.forEach((l) => el.append(h('p', 'tests-why', `Left out: ${l.file}: ${l.why}`)));
    el.append(button(`File ${n} ${n === 1 ? 'issue' : 'issues'}`, 'btn-primary', 'bulk-file', `File ${n} ${n === 1 ? 'issue' : 'issues'}`, () => {
      const bad = a.items.find((it) => !it.title.trim() || /[\r\n]/.test(it.title.trim()) || !it.body.trim());
      // The bar shows why, by the button clicked; the preview already names the files left out.
      if (bad) { const why = `Type a title of one line and a text for the issue about ${bad.file} first.`; S.answers = { what: 'Optimize', lines: [], left: [], note: why }; draw(); say(why); return; }
      bulk('Optimize', 'test-issue', a.items.flatMap((it) => [it.file, it.title.trim(), it.body.trim()]), a.items.map((it) => it.file), a.left, () => { S.ask = null; });
    }), button('Cancel', 'btn-quiet', 'bulk-cancel', 'Cancel: file nothing', () => { S.ask = null; draw(); say('Cancelled. Nothing was filed.'); }));
    return el;
  }
  // ---- Optimize: each issue the Board filed for a file, and each Tests page card of no issue (issue null, with its
  // name, "No issue", which issueLink() shows), as its cards left it (the snapshot's optimize) ----
  const optsOf = (f) => list(f.optimize).filter((o) => obj(o) && (num(o.issue) !== null || (o.issue === null && typeof o.name === 'string')))
    .sort((x, y) => (Date.parse(y.time) || 0) - (Date.parse(x.time) || 0));
  function stateSaid(o) {
    if (o.state === 'blocked') return `blocked: ${typeof o.reason === 'string' && o.reason ? o.reason : 'no reason recorded'}`;
    if (o.state === 'landed') return `landed${typeof o.sha === 'string' && o.sha ? ` as ${o.sha.slice(0, 7)}` : ''}`;
    return o.state === 'closed' ? 'closed without landing' : String(o.state || 'open');
  }
  const intoSaid = (o) => list(o.into).filter((x) => typeof x === 'string').join(', ');
  // The fix its card made: sped up, split into <files>, merged into <files> or deleted.
  const fixSaid = (o) => ((o.fix === 'split' || o.fix === 'merged') && intoSaid(o) ? `${o.fix} into ${intoSaid(o)}` : typeof o.fix === 'string' ? o.fix : null);
  // What a landed Optimize did (#130): its proof's CPU s before and after (with no after, the median of the file's runs
  // since it landed), the change, and whether it helped (the file got faster); null when its numbers are not on record.
  function gainOf(o) {
    const b = num(o.before), a = num(o.after) !== null ? o.after : num(o.since);
    if (!b || a === null) return null;
    const change = (a - b) / b;
    return { before: b, after: a, change, helped: Math.round(change * 100) < 0 };
  }
  const gainSaid = (g) => `${one(g.before)} → ${one(g.after)} CPU s (${pct(g.change)})`;
  const helpedSaid = (g) => (g.helped ? 'helped' : 'did not help');
  const helpedChip = (g) => S.ctx.chip(g.helped ? 'Helped' : 'Did not help', g.helped ? 'ok' : 'warn');
  // Its numbers in a line: before → after with the change, and the median of the file's runs since it landed.
  function numbersSaid(o, withHelped = true) {
    const g = gainOf(o);
    if (!g) return null;
    const n = num(o.sinceRuns) || 0, since = num(o.since) === null || num(o.after) === null ? '' : ` · since it landed: ${one(o.since)} CPU s, the median of ${n} ${n === 1 ? 'run' : 'runs'}`;
    return `${gainSaid(g)}${withHelped ? `, ${helpedSaid(g)}` : ''}${since}`;
  }
  // The mutants its file's tests caught before it landed and after (#79): the newest done mutation check of each, when
  // both are on record.
  function mutantsSaid(o) {
    const b = obj(o.mutantsBefore), a = obj(o.mutantsAfter), ok = (m) => m && num(m.killed) !== null && num(m.of) !== null;
    return ok(b) && ok(a) ? `Mutants caught before: ${b.killed} / ${b.of}, after: ${a.killed} / ${a.of}` : null;
  }
  // The runs where a landed Optimize took effect: the first timed run of the file after it landed, to its issue. The
  // row keeps only the last runs: when fewer of them come after it than its sinceRuns (all the timed runs since it
  // landed), that first run is no longer kept and no run is marked.
  function optRuns(f) {
    const out = new Map(), runs = list(f.runs).filter((r) => obj(r) && !Number.isNaN(Date.parse(r.time))).sort((x, y) => Date.parse(x.time) - Date.parse(y.time));
    optsOf(f).filter((o) => o.state === 'landed' && !Number.isNaN(Date.parse(o.landed))).forEach((o) => {
      const after = runs.filter((x) => Date.parse(x.time) > Date.parse(o.landed) && num(x.cpu) !== null), r = after[0];
      if (r && after.length >= (num(o.sinceRuns) ?? Infinity) && !out.has(r)) out.set(r, o);
    });
    return out;
  }
  const optRunSaid = (o) => `first run after ${num(o.issue) !== null ? `Optimize #${o.issue}` : 'the Optimize card of no issue'} landed`;

  // ---- Recent actions: each kept action and each Optimize issue, newest first, collapsed until opened ----
  // A file named there opens its row: the search and the filter let it show.
  function goto(file) {
    const f = list(tests() && tests().files).find((x) => obj(x) && x.file === file), q = S.query.trim().toLowerCase();
    if (f && ((S.filter !== 'all' && !marks(f).some((m) => m[0] === S.filter)) || !shows(f, q))) { S.filter = 'all'; S.query = ''; }
    S.open.add(file); S.keep = { act: 'open', file }; draw();
    const tr = Array.from(S.el.querySelectorAll('.tests-row')).find((r) => r.dataset.file === file);
    if (tr && typeof tr.scrollIntoView === 'function') tr.scrollIntoView({ block: 'nearest' });
    say(`Opened: ${file}`);
  }
  function recent(files, gone) {
    const h = S.ctx.h, el = h('details', 'tests-results'), all = actions(), rows = new Set(files.map((f) => f.file));
    el.open = S.recentOpen;
    el.addEventListener('toggle', () => { S.recentOpen = el.open; });
    el.append(h('summary', 'board-head', `Recent actions: ${all.filter(running).length} running, ${all.filter(queued).length} queued`));
    const items = all.map((a) => ({ t: a.start || a.asked, a, file: String(a.file) }))
      .concat(files.concat(gone).flatMap((f) => optsOf(f).map((o) => ({ t: o.time, o, file: f.file }))))
      .sort((x, y) => (Date.parse(y.t) || 0) - (Date.parse(x.t) || 0));
    if (!items.length) { el.append(h('p', 'board-from', 'No action ran yet. An action that you start on a row shows here.')); return el; }
    const ul = h('ul', 'tests-results-list');
    items.forEach(({ t, a, o, file }) => {
      const li = h('li', 'tests-result-row'), line = h('div', 'tests-result-line'), name = a ? ACTS[a.action] || String(a.action) : 'Optimize';
      const ref = rows.has(file) ? button(file, 'btn-quiet tests-result-file', 'goto', `Open the row of ${file}`, () => goto(file)) : h('span', 'tests-result-file', file);
      line.append(h('span', 'board-from', S.ctx.when(t)), h('span', 'board-label', name), ref);
      if (o) {
        li.dataset.issue = String(o.issue);
        line.append(S.ctx.issueLink(o), h('span', null, [stateSaid(o), o.state === 'landed' ? fixSaid(o) : null, numbersSaid(o)].filter(Boolean).join(' · ')));
      } else {
        li.dataset.id = a.id;
        if (running(a)) {
          const lim = limitOf(a);
          line.append(h('span', 'board-from', `${a.action === 'run' ? 'engine command, no session' : `${a.cli} · ${a.model} · ${a.effort}`} · Runs: ${mmss(used(a))}${lim ? ` of ${mmss(lim)}` : ''}`));
        } else if (queued(a)) line.append(h('span', 'board-from', queuedSaid(a)));
        else line.append(...result(a));
        if (live(a) && ID.test(a.id)) line.append(button(S.stopping.has(a.id) ? 'Stopping…' : 'Stop', 'btn-quiet', 'stop', `Stop: ${name}, ${a.file}`, () => stop(a)));
        else line.append(button('Copy', 'btn-quiet', 'copy', `Copy the text: ${name}, ${a.file}`, () => copy(S.texts.get(a.id) || '')));
      }
      li.append(line);
      ul.append(li);
    });
    el.append(ul);
    return el;
  }
  // ---- Removed by Optimize: each file a landed Optimize deleted or merged, with its last numbers ----
  function removed(gone) {
    const h = S.ctx.h, el = h('section', 'tests-removed'), ul = h('ul', 'tests-list');
    el.append(h('h3', 'board-head', 'Removed by Optimize'));
    gone.forEach((f) => {
      const o = optsOf(f).find((x) => x.state === 'landed' && (x.fix === 'deleted' || x.fix === 'merged')) || {}, li = h('li', 'tests-gone');
      li.dataset.file = f.file;
      li.append(h('span', 'board-label', f.file), h('span', null, ` · its last run ${one(f.cpu)} CPU s, its median ${one(f.median)} CPU s · `), num(o.issue) === null && typeof o.name !== 'string' ? '' : S.ctx.issueLink(o),
        h('span', null, ` · ${o.fix || 'removed'}${o.landed ? ` ${S.ctx.when(o.landed)}` : ''} · ${intoSaid(o) ? `its cases are now in ${intoSaid(o)}` : 'no test file is on record for its cases'}`));
      ul.append(li);
    });
    el.append(ul);
    return el;
  }

  // ---- Test edits by cards (#76): what each landed card did to the test files main had ----
  // The five counts of an edit (the engine's testedits()), with their words for one and for more.
  const EDITS = [['removedAsserts', 'assertion removed', 'assertions removed'], ['changedExpected', 'expected value changed', 'expected values changed'],
    ['skipsAdded', 'skip, only or todo mark added', 'skip, only or todo marks added'], ['timeoutsRaised', 'timeout raised', 'timeouts raised'],
    ['casesDeleted', 'case deleted', 'cases deleted']];
  const weakened = (e) => EDITS.some(([k]) => (num(e[k]) || 0) > 0);
  const editsOf = () => list((tests() || {}).edits).filter((e) => obj(e) && typeof e.file === 'string');
  function editSaid(e) {
    if (e.read === false) return 'Edited, not read';
    const said = EDITS.filter(([k]) => (num(e[k]) || 0) > 0).map(([k, one1, more1]) => `${e[k]} ${e[k] === 1 ? one1 : more1}`);
    return said.length ? said.join(', ') : 'Edited, nothing weakened';
  }
  // An edit's card by its issue, "#NN" (a link to it), never by the card's id (#130): "a card" when it has none.
  const editIssue = (e, any) => (num(e.issue) !== null ? S.ctx.issueLink({ issue: e.issue, url: any ? any.replace(/\d+$/, String(e.issue)) : null }) : S.ctx.h('span', 'issue', 'a card'));
  // One edit: its card's issue, the file (withFile), its time and its counts.
  function editLine(e, withFile, any) {
    const h = S.ctx.h, li = h('li', 'tests-edit');
    li.dataset.file = e.file;
    li.append(editIssue(e, any));
    if (withFile) li.append(h('span', null, ' · '), h('span', 'board-label', e.file));
    li.append(h('span', 'board-from', ` · ${S.ctx.when(e.time)}`), h('span', 'tests-edit-counts', ` · ${editSaid(e)}`));
    return li;
  }
  function editsList(edits, label, withFile, any) {
    const ul = S.ctx.h('ul', 'tests-runs tests-edits-list');
    ul.setAttribute('aria-label', label);
    edits.forEach((e) => ul.append(editLine(e, withFile, any)));
    return ul;
  }
  function editsSection(files) {
    const h = S.ctx.h, el = h('section', 'tests-edits'), all = editsOf(), weak = all.filter(weakened), any = anyIssueUrl(files);
    el.append(h('h3', 'board-head', 'Test edits by cards'));
    const bar = h('div', 'tests-filters');
    bar.setAttribute('role', 'group'); bar.setAttribute('aria-label', 'Show the test edits');
    [['weakened', 'Weakened', weak.length], ['all', 'All edits', all.length]].forEach(([k, name, n]) => {
      const b = button(`${name} ${n}`, 'rules-tog', 'edits-filter', `${name}: ${n} ${n === 1 ? 'edit' : 'edits'}`, () => { S.edits = k; draw(); say(`Showing: ${name}`); });
      b.dataset.filter = k; b.setAttribute('aria-pressed', String(S.edits === k));
      bar.append(b);
    });
    const shown = S.edits === 'all' ? all : weak;
    el.append(bar, shown.length ? editsList(shown, 'Test edits by cards, newest first', true, any)
      : h('p', 'board-from', S.edits === 'all' ? 'No landed card changed a test file that main had.' : 'No landed card weakened a test file that main had.'));
    return el;
  }

  // ---- Auto-file: the switch, the preview, the guards, the rules and the log ----
  const rulesCmd = (args) => ['control', { action: 'testrules', args, repo: S.d.repo }];
  const WHOLE1 = /^[1-9][0-9]{0,5}$/, WHOLE0 = /^[0-9]{1,6}$/, LIMIT = /^[0-9]{1,6}(\.[0-9]{1,3})?$/;
  const ONOFF = [['true', 'On'], ['false', 'Off']];
  const MEASURES = [['usual', 'CPU s over its usual'], ['clock', 'Clock s over its CPU s'], ['flaky', 'Kept off as flaky'], ['failed', 'Failed test steps']];
  // A setting's check: why the value is not sent, or null.
  const checkBy = (re, words) => (v) => (re.test(v) ? null : words);
  function matchSaid(m) {
    const v = obj(m.values) || {};
    return Object.entries(v).map(([k, x]) => `${k} ${Array.isArray(x) ? x.map((y) => (num(y) === null ? String(y) : one(y))).join(', ') : x}`).join('; ');
  }
  function resultSaid(m) {
    if (m.result === 'filed') return `Filed #${m.issue}`;
    if (m.result === 'stopped') return `Stopped by ${m.guard}: ${m.why}`;
    if (m.result === 'not filed') return 'Not filed: GitHub did not take it';
    return 'Would file';
  }
  function previewTable(r) {
    const h = S.ctx.h, last = obj(r.last), matches = list(last && last.matches).filter(obj), el = h('div', 'tests-set-box tests-auto-preview');
    el.append(h('p', 'board-head', last ? `Preview: what the rules matched at ${S.ctx.when(last.time)}, with the result of the guards for each match` : 'Preview: the rules did not run yet'));
    if (!matches.length) { el.append(h('p', 'board-from', last ? 'The rules matched no file.' : 'The rules run after each card test step.')); return el; }
    const t = h('table', 'tests-table tests-auto-table'), head = h('tr'), body = h('tbody'), thead = h('thead');
    ['Rule', 'File', 'Measured', 'Result'].forEach((x) => { const th = h('th', null, x); th.scope = 'col'; head.append(th); });
    matches.forEach((m) => {
      const tr = h('tr', 'tests-auto-match');
      [m.rule, m.file, matchSaid(m), resultSaid(m)].forEach((x) => tr.append(h('td', null, String(x))));
      body.append(tr);
    });
    thead.append(head); t.append(thead, body);
    el.append(t);
    return el;
  }
  function autofile() {
    const h = S.ctx.h, r = rules(), named = obj(tests() && tests().rules), el = section('tests-auto', 'Auto-file', named ? PACK : null);
    if (!named) { el.append(h('p', 'board-from', 'The build machine names no auto-file rules. It runs an older Conveyor.')); return el; }
    const on = shown('rules-on') === 'true', confirm = asking('on');
    const sw = on
      ? actBtn('Turn off', 'auto-off', 'Turn auto-file off', () => sendRule('rules-on', ['off'], 'false', 'Auto-file is now Off.'))
      : actBtn('Turn on', 'auto-on', 'Turn auto-file on: shows the preview first', () => { S.ask = { kind: 'on', repo: S.d.repo }; S.keep = { act: 'auto-on-confirm' }; draw(); say('Check the preview. Then click "Turn on: confirm".'); });
    el.append(row('auto-switch', 'Auto-file test issues', 'One switch for all the rules. On: the rules file issues after each card test step. Off: they file none.', null,
      h('span', 'board-value', on ? 'On' : 'Off'), confirm ? null : sw));
    if (confirm && !on) {
      const c = h('div', 'tests-preview');
      c.dataset.armed = '';
      c.append(h('p', 'board-head', 'Check the preview below. With the switch on, the rules file such issues after each card test step.'),
        button('Turn on: confirm', 'btn-primary', 'auto-on-confirm', 'Turn auto-file on', () => { S.ask = null; sendRule('rules-on', ['on'], 'true', 'Auto-file is now On.'); }),
        button('Cancel', 'btn-quiet', 'auto-on-cancel', 'Cancel: keep auto-file off', () => { S.ask = null; draw(); say('Cancelled. Auto-file stays Off.'); }));
      el.append(c);
    }
    el.append(previewTable(r));
    el.append(autoGuards());
    // The rules, each with its fields.
    const rs = h('div', 'tests-auto-rules');
    rs.append(h('p', 'board-head', 'Rules'));
    const all = list(r.list).filter((x) => obj(x) && typeof x.name === 'string');
    if (!all.length) rs.append(h('p', 'board-from', 'No rule. Add one with conveyor.sh testrules add on the build machine.'));
    all.forEach((x) => rs.append(autoRule(x)));
    el.append(rs);
    el.append(autoLog(r));
    return el;
  }
  // The guards for all the auto-file rules (autofile).
  function autoGuards() {
    const h = S.ctx.h, g = h('div', 'tests-auto-guards');
    g.append(h('p', 'board-head', 'Guards for all rules'));
    [['perDay', 'Most issues in one day', WHOLE1, 'a whole number of 1 or more', 'The rules file no more issues than this in one day. The rest wait for the next day.'],
      ['maxOpen', 'Most issues open at one time', WHOLE1, 'a whole number of 1 or more', 'The rules file no issue while this many of their issues are open.'],
      ['quietDays', 'Days with no issue for a file after its last issue closed', WHOLE0, 'a whole number of 0 or more', 'The rules file no issue about a file for this many days after its last issue closed.']].forEach(([k, words, re, what, help]) => {
      g.append(row(`guard-${k}`, words, help, null, ...setting(`guard:${k}`, { act: `guard-${k}`, label: words, type: 'number',
        check: checkBy(re, `${words} is ${what}.`), send: (v) => rulesCmd(['guard', k, v]), said: (v) => `${words}: now ${v}` })));
    });
    g.append(row('guard-burst', 'Stop a burst', 'On: when one run of the rules matches more files than one day allows, it files nothing. Off: it files up to the day\'s limit.', null, ...setting('guard:burst', { act: 'guard-burst', label: 'Stop a burst', choices: ONOFF,
      check: () => null, send: (v) => rulesCmd(['guard', 'burst', v]), said: (v) => `Stop a burst is now ${v === 'true' ? 'On' : 'Off'}` })));
    return g;
  }
  // One auto-file rule x, with its fields (autofile).
  function autoRule(x) {
    const h = S.ctx.h, box2 = h('div', 'tests-rule'), name = x.name;
    box2.dataset.rule = name;
    box2.append(h('p', 'board-label', `Rule: ${name}`));
    const fld = (k, words, help, o) => box2.append(row(`rule-${k}`, words, help, null, ...setting(`rule:${k}:${name}`, Object.assign({ act: `rule-${k}`, label: `${words} of rule ${name}`,
      send: (v) => rulesCmd(['set', name, k, v]), said: (v) => `rule ${name}: ${k} now ${v}` }, o))));
    fld('on', 'On', 'On: this rule files issues. Off: it files none.', { choices: ONOFF, check: () => null });
    fld('measure', 'Measure', 'What the rule measures in the test runs of each file.', { choices: MEASURES, check: () => null });
    // A count rule (flaky, failed) matches at its limit and does not use runs in a row (testrulesmatches()).
    const count = x.measure === 'flaky' || x.measure === 'failed';
    fld('limit', 'Limit (times, or a count)', count ? 'A file matches when its count in those days is 1 or more and is this limit or more.' : 'A file matches when its measure is over this limit.', { type: 'number', check: checkBy(LIMIT, 'The limit is a number of 0 or more, as 1 or 1.5.') });
    fld('runs', 'Runs in a row', count ? 'This rule does not use this setting.' : 'A file matches only when its last runs, this many, are all over the limit.', { type: 'number', check: checkBy(WHOLE1, 'Runs in a row is a whole number of 1 or more.') });
    fld('minRuns', 'Least runs on record', 'The rule does not look at a file with fewer runs on record.', { type: 'number', check: checkBy(WHOLE0, 'Least runs on record is a whole number of 0 or more.') });
    if (count) fld('days', 'Days', 'The rule counts the test steps of this many past days.', { type: 'number', check: checkBy(WHOLE1, 'Days is a whole number of 1 or more.') });
    if (x.measure === 'clock') fld('minClock', 'Least clock s of a run', 'A file matches only when each of those runs took at least this many clock seconds.', { type: 'number', check: checkBy(LIMIT, 'Least clock s is a number of 0 or more.') });
    return box2;
  }
  // What auto-file did (autofile), from the rules' record r.
  function autoLog(r) {
    const h = S.ctx.h;
    const log = list(r.log).filter(obj), ul = h('ul', 'tests-auto-log');
    log.forEach((l) => ul.append(h('li', 'tests-auto-line', `${S.ctx.when(l.time)} · ${l.event === 'filed' ? `Filed #${l.issue}` : `Stopped by ${l.guard}`} · rule ${l.rule} · ${l.file}${l.why ? ` · ${l.why}` : ''}`)));
    if (!log.length) ul.append(h('li', 'board-from', 'Auto-file filed nothing and stopped nothing yet.'));
    // The preview and the log are boxes of their own (app.css), apart from the settings rows.
    const did = h('div', 'tests-set-box tests-auto-did');
    did.append(h('p', 'board-head', 'What auto-file did'), ul);
    return did;
  }
  // The switch, saved as the other settings are: it shows as saved until a snapshot names it.
  function sendRule(key, args, v, said) {
    const was = inForce(key);
    send('testrules', args, () => said, (t, at) => { S.pending.set(dk(key), { key, v, was, at, read: S.read }); });
  }
  window.DASH_APP.part('tests-actions', function (shared) {
    ({ PACK, CONTROL, S, num, list, obj, one, pct, tests, rules, dk, inForce, shown, marks, say, button, row,
      section, setting, ACTS, FILES_MAX, RUNNER_WHY, MODEL, OTHER, ID, TITLE_MAX, BODY_MAX, NO_SEAT, WAIT, SENDING,
      ta, ctlTests, actions, mmss, limitOf, used, seatOf, tmodel, MUT_WHY, mutAsk, progress, mutNow, actBtn, send,
      copy, actArgs, stop, result, running, queued, live, queuedSaid, actNow, md, draftIssue, shows, asking, field,
      anyIssueUrl, noIssue, draw } = shared);
    return { actionsHead, selBar, optsOf, stateSaid, fixSaid, gainOf, helpedChip, numbersSaid, mutantsSaid, optRuns,
      optRunSaid, recent, removed, weakened, editsOf, editSaid, editIssue, editsSection, autofile };
  });
})();
