// SPDX-License-Identifier: Apache-2.0
// The Tests panel's mutation checks, the actions asked of a file (sent, then shown in the row's box with their text),
// and the drafts of its fix issues (Optimize, Fix failures, Fix hollow cases, Fix the waiting, Make it run, Rewrite
// as a direct check, Split it, Delete it). Part of panels/tests.js, which asks for it by name (DASH_APP.use) and gives
// it what it uses; boot.js loads it before the panels.
(() => {
  'use strict';
  // What this part uses of panels/tests.js, set when tests.js asks for the part (DASH_APP.part, at the end).
  let S, num, list, obj, one, pct, dk, say, button, ACTS, FILES_MAX, RUNNER_WHY, ENDED, ID, BODY_MAX, NO_SEAT,
    WAIT, SENDING, actions, mmss, limitOf, used, tmodel, hollowOf, hollowSaid, verdictOf, causeSaid, failsOf,
    fixable, kindSaid, casesSaid, runBy, draw, inForce, tests;

  // ---- mutation checks (#79): the snapshot's mutation (a file's newest check) and mutationPlace (its place in the asked list) ----
  const MUT_WHY = 'A check starts only when no card needs a test slot.';
  const mutOf = (f) => obj(f.mutation);
  // Its newest check, when it ended done with a mutant or more.
  const mutDone = (f) => { const m = mutOf(f); return m && m.state === 'done' && num(m.killed) !== null && num(m.of) ? m : null; };
  // The mutants of its newest check that its tests did not catch.
  const survivors = (f) => list((mutOf(f) || {}).survived).filter((x) => obj(x) && typeof x.source === 'string' && num(x.line) !== null);
  const trimmed = (s) => String(typeof s === 'string' ? s : '').replace(/\p{C}/gu, ' ').trim();
  // Its place in the asked list (1 first); 0 when it was asked here and the snapshot does not name it yet; null when
  // not queued. A file asked here leaves that state when the snapshot names its place, or a check of it began after.
  function mutQueued(f) {
    const k = dk(f.file), t = S.mutAsked.get(k), m = mutOf(f);
    if (num(f.mutationPlace) !== null) { S.mutAsked.delete(k); return f.mutationPlace; }
    if (t === undefined) return null;
    if (m && Date.parse(m.at) >= t) { S.mutAsked.delete(k); return null; }
    return 0;
  }
  // The state of its check, in words: running (mutant n of m), queued (its place), paused, failed, done, or none.
  function mutState(f) {
    const m = mutOf(f), q = mutQueued(f), of = m ? num(m.of) || 0 : 0, tried = m ? num(m.tried) || 0 : 0;
    const why = m && typeof m.reason === 'string' ? m.reason : '';
    if (m && m.state === 'running') return of ? `Running: mutant ${Math.min(tried + 1, of)} of ${of}.` : 'Running: it makes its mutants.';
    if (q !== null) return `Queued${q ? `: place ${q} in the idle queue, ${q - 1} ahead` : ''}. ${MUT_WHY}`;
    if (!m) return 'No check yet. Mutation check, in More, puts it at the front of the idle queue.';
    if (m.state === 'stopped') return `Paused${/\bcard\b|test slot/.test(why) ? ' for a card' : ''}: ${why || 'no reason recorded'}. It goes on from mutant ${Math.min(tried + 1, of)} of ${of} later.`;
    if (m.state === 'failed') return `Failed: ${why || 'no reason recorded'}.`;
    return `Done ${S.ctx.when(m.end || m.at)}: ${num(m.killed) || 0} of ${of} mutants caught.`;
  }
  // The column's text: its newest done check's "caught / made", and what its check does now.
  function mutCell(f) {
    const d = mutDone(f), m = mutOf(f), q = mutQueued(f);
    const now = m && m.state === 'running' ? 'running' : q !== null ? 'queued' : m && m.state === 'stopped' ? 'paused' : '';
    return [d ? `${d.killed} / ${d.of}` : '', now].filter(Boolean).join(' · ');
  }
  // A survivor in a line of text: its source and line, its kind and its change.
  const survivorSaid = (x) => `${x.source}:${x.line}${typeof x.kind === 'string' ? ` (${x.kind})` : ''}: \`${trimmed(x.before)}\` → \`${trimmed(x.after)}\``;
  // A Mutation check asked for files: one POST, `conveyor.sh mutate ask`, which puts them at the front of the idle
  // queue; their rows show them queued. inBar: the bar's action, whose answer shows in the bar.
  // Not inBar: the row's (one file), whose state shows on its row's line (S.notes).
  function mutAsk(files, inBar) {
    const what = 'Mutation check', kind = 'mutate';
    const note = (state, text = '') => { if (!inBar) S.notes.set(dk(files[0]), { what, state, text }); };
    if (files.length > FILES_MAX) { S.answers = { what, kind, lines: [], left: [], note: `At most ${FILES_MAX} files at a time: ${files.length} are selected. Select fewer.` }; draw(); return; }
    if (S.busy) { if (inBar) S.answers = { what, kind, lines: [], left: [], note: WAIT }; else note('refused', WAIT); draw(); return; }
    const at = S.ctx.now();
    if (inBar) S.answers = { what, kind, pending: true, lines: [], left: [], note: null }; else note('sending');
    send('mutate', files, () => `Mutation check queued: ${files.length} ${files.length === 1 ? 'file' : 'files'} at the front of the idle queue. ${MUT_WHY}`, (text) => {
      files.forEach((file) => S.mutAsked.set(dk(file), at));
      if (inBar) S.answers = { what, kind, lines: files.map((file) => ({ file, ok: true, text: 'queued' })), left: [], note: null, said: text.replace(/^conveyor: /, '') };
      else note('asked');
    }, (why) => { if (inBar) S.answers = { what, kind, lines: files.map((file) => ({ file, ok: false, text: why })), left: [], note: null }; else note('refused', why); });
  }
  // A bar of progress: value of max, or with no max one that shows only that it goes on.
  function progress(label, value, max) {
    const b = S.ctx.h('progress', 'tests-progress');
    if (max) { b.max = max; b.value = Math.min(value, max); }
    b.setAttribute('aria-label', label);
    return b;
  }
  // A file's mutation check now, as a bar and words: running, its mutants tried of all and the time since it began;
  // queued, a bar that goes on; else its state alone.
  function mutNow(f) {
    const h = S.ctx.h, m = mutOf(f), q = mutQueued(f), out = [];
    let text = mutState(f);
    if (m && m.state === 'running') {
      out.push(progress(`Mutation check: ${f.file}`, num(m.tried) || 0, num(m.of) || 0));
      const t0 = Date.parse(m.at || '');
      if (!Number.isNaN(t0)) text += ` ${mmss((S.ctx.now() - t0) / 1000)} so far.`;
    } else if (q !== null) out.push(progress(`Mutation check: ${f.file}`));
    out.push(h('span', null, text));
    return out;
  }

  const actBtn = (text, act, label, fn) => button(text, 'btn-quiet tests-act', act, label, fn);
  // One action sent: POST control {action, args, repo}; then(text, at) on a yes, no(refusal) on a no, and the answer or
  // the refusal said.
  function send(action, args, said, then, no) {
    if (S.busy) { say(WAIT); return; }
    const repo = S.d.repo;
    S.busy = true; draw(); say('Sending…');
    S.ctx.post('control', { action, args, repo }).then((r) => r.text().then((t) => {
      const at = Number(r.headers && typeof r.headers.get === 'function' ? r.headers.get('X-Answered-At') : NaN);
      return [r.ok, String(t).trim() || `the build machine answered ${r.status}`, Number.isFinite(at) && at > 0 ? at * 1000 : null];
    }), () => [false, 'the build machine did not answer', null]).then(([ok, text, at]) => {
      S.busy = false;
      if (ok && then && repo === S.d.repo) then(text, at);
      if (!ok && no && repo === S.d.repo) no(S.ctx.refusal(text));
      draw();
      say(ok ? said(text) : `Not done: ${S.ctx.refusal(text)}`);
    });
  }
  // The Rules tab's Cards with no GitHub issue: Tests page actions (#1330, the control record's rules.testissues): with
  // it On (rules.testissues off), an action that makes a card
  // (Optimize, Fix failures, Split it and the other fix actions) starts that card at once, with no GitHub issue: its
  // draft d is sent as it is (test-issue: `conveyor.sh testissue`, which starts the card when the rule is off), in place
  // of the issue preview. With it Off, the preview opens (keep: the field to focus), to be edited and filed.
  // The draft is make(f); the preview keeps make and the test history's start it was made under (history), so a
  // snapshot with another start makes it again (redraft()).
  const noIssue = () => { const c = obj(S.d && S.d.control); return !!(c && obj(c.rules) && c.rules.testissues === false); };
  function askIssue(make, f, keep) {
    const d = make(f), k = dk(d.file), note = (state, text = '') => S.notes.set(k, { what: d.what || 'Optimize', state, text });
    S.notes.delete(k);
    // A draft that cannot be made (refused: why, as draftDirect() gives it) opens no preview and sends nothing.
    if (d.refused) { S.ask = null; note('refused', d.refused); draw(); say(d.refused); return; }
    if (!noIssue()) { S.ask = Object.assign(d, { make, history: inForce('historyStart') }); S.keep = keep || { act: 'issue-title', file: d.file }; draw(); return; }
    S.ask = null;
    if (S.busy) { note('refused', WAIT); draw(); say(WAIT); return; }
    note('sending');
    send('test-issue', [d.file, d.title, d.body], (t) => t, (t) => note('done', t), (no) => note('refused', no));
  }
  // An open issue preview made under another "Test history starts at" (#1384, R8) is made again from this snapshot,
  // whose failures, runs and waits count only from the new start; one its file no longer has a draft for (gone,
  // refused, or Fix failures with no failure left) closes. Either way the line says so: the edits typed are dropped.
  function redraft() {
    const a = S.ask;
    if (!a || a.kind !== 'issue' || !a.make || a.history === inForce('historyStart')) return;
    const f = list(tests() && tests().files).find((x) => obj(x) && x.file === a.file);
    const d = f && !(a.what === 'Fix failures' && !fixable(f).length) ? a.make(f) : null;
    S.ask = d && !d.refused ? Object.assign(d, { make: a.make, history: inForce('historyStart') }) : null;
    say(S.ask ? `Test history starts at changed: the ${a.what || 'Optimize'} preview of ${a.file} is made again from the runs that count now.`
      : `Test history starts at changed: the ${a.what || 'Optimize'} preview of ${a.file} is closed, as nothing it named counts now.`);
  }
  // The text of an action as seen here, with the snapshot's text added: a whole text replaces it; the end of a long
  // one (textCut) is joined to it where the two meet, so the text seen before stays.
  function merge(was, t) {
    if (!t || !was) return t || was;
    const head = t.slice(0, 64);
    for (let p = was.indexOf(head, Math.max(0, was.length - t.length)); p >= 0; p = was.indexOf(head, p + 1)) if (t.startsWith(was.slice(p))) return was.slice(0, p) + t;
    for (let k = Math.min(head.length - 1, was.length); k > 0; k -= 1) if (was.endsWith(t.slice(0, k))) return was + t.slice(k);
    return `${was}\n[…]\n${t}`;
  }
  function copy(text) {
    const clip = window.navigator.clipboard;
    (clip && clip.writeText ? clip.writeText(text) : Promise.reject(new Error('no clipboard')))
      .then(() => say('Copied.'), () => say('Not copied: the browser gave no clipboard.'));
  }
  // The arguments of a test action before its files: an explain's facts give their times as this page shows them, in
  // this browser's time zone and the Time set in Customize (#770), so it sends both.
  const actArgs = (how) => (how === 'explain' ? [how, '--time', new Intl.DateTimeFormat().resolvedOptions().timeZone, S.ctx.hours()] : [how]);
  // An action of a row: its box shows at once, beside its buttons: sending until the build machine answers, then
  // running (or why it was refused); one that cannot be sent says why there.
  function start(how, file) {
    const k = dk(file), now = () => new Date(S.ctx.now()).toISOString();
    const why = how !== 'run' && !tmodel() ? NO_SEAT : S.busy ? WAIT : null;
    S.open.add(file);
    if (why) { S.started.set(k, { id: '', action: how, file, state: 'refused', reason: why }); draw(); say(`Not started: ${why}`); return; }
    S.started.set(k, { id: '', action: how, file, start: now(), state: 'sending' });
    send('testaction', [...actArgs(how), file], () => `Started: ${ACTS[how]}, ${file}.`, (text) => {
      const id = text.split('\n').pop().trim();
      S.started.set(k, { id: ID.test(id) ? id : '', action: how, file, start: now(), state: 'running' });
    }, (reason) => S.started.set(k, { id: '', action: how, file, state: 'refused', reason }));
  }
  const stop = (a) => send('testaction', ['stop', a.id], (t) => `Stop sent: ${ACTS[a.action] || a.action}, ${a.file}. ${t}`, () => S.stopping.add(a.id));
  const verdictChip = (v) => S.ctx.chip(v, v === 'keep' ? 'ok' : v === 'no verdict' ? 'quiet' : 'warn');
  // How an action ended: its state and time, when, its CLI, model and effort (a run has none), and its verdict (unless
  // its box shows it on the verdict line: chip false) or result.
  function result(a, chip = true) {
    const h = S.ctx.h, t0 = Date.parse(a.start || ''), t1 = Date.parse(a.end || '');
    const took = Number.isNaN(t0) || Number.isNaN(t1) ? '' : ` in ${mmss((t1 - t0) / 1000)}`;
    const out = [h('span', 'tests-result', `${ENDED[a.state] || String(a.state)}${took} · ${S.ctx.when(a.end || a.start)} · ${a.action === 'run' ? 'engine command, no session' : `${a.cli} · ${a.model} · ${a.effort}`}`)];
    if (chip && a.action === 'judge' && typeof a.verdict === 'string') out.push(verdictChip(a.verdict));
    if (a.action === 'run' && typeof a.result === 'string') {  // the run's result: fail, or its other value
      const bad = a.result === 'fail';
      out.push(S.ctx.chip(`${bad ? 'Failed' : 'Passed'}${num(a.cpu) !== null ? `, ${one(a.cpu)} CPU s` : ''}`, bad ? 'bad' : 'ok'));
    }
    if (typeof a.reason === 'string' && a.reason) out.push(h('span', 'board-from', a.reason));
    return out;
  }
  const running = (a) => a.state === 'running';
  const queued = (a) => a.state === 'queued';
  const live = (a) => running(a) || queued(a);
  // A queued action waits for a free place; the engine starts them in the order asked.
  const ahead = (a) => actions().filter((x) => queued(x) && x.id !== a.id && String(x.asked || '') < String(a.asked || '')).length;
  const queuedSaid = (a) => `Queued, ${ahead(a)} ahead`;
  // An action now, as a bar and words: queued, how many wait before it; running, the time used (against its limit);
  // ended, its result.
  function actNow(a, chip = true) {
    const h = S.ctx.h, name = ACTS[a.action] || String(a.action);
    if (queued(a)) return [progress(`Waiting: ${name}`), h('span', 'board-from', queuedSaid(a))];
    if (!running(a)) return result(a, chip);
    const lim = limitOf(a), u = used(a);
    return [progress(`Time used: ${name}`, u, lim), h('span', 'board-from', lim ? `Running: ${mmss(u)} of the ${mmss(lim)} time limit` : `Running: ${mmss(u)} used`)];
  }
  // The text of a judge or explain action as formatted text (#74): paragraphs, **bold**, `code`, lists ("- ", "* ",
  // "1. ") and ``` code blocks. It builds nodes and never sets HTML from the text: any other markup shows as typed.
  function inline(s) {
    const h = S.ctx.h, out = [], re = /\*\*(\S(?:[^*\n]*?\S)?)\*\*|`([^`\n]+)`/g;
    let at = 0, m;
    while ((m = re.exec(s))) {
      if (m.index > at) out.push(document.createTextNode(s.slice(at, m.index)));
      if (m[1] !== undefined) { const b = h('strong'); b.append(...inline(m[1])); out.push(b); } else out.push(h('code', null, m[2]));
      at = re.lastIndex;
    }
    if (at < s.length) out.push(document.createTextNode(s.slice(at)));
    return out;
  }
  function md(text) {
    const h = S.ctx.h, el = h('div', 'tests-md'), lines = String(text).replace(/\r\n?/g, '\n').split('\n');
    let para = [], ul = null;
    const flush = () => {
      if (!para.length) return;
      const p = h('p');
      para.forEach((l, i) => { if (i) p.append(h('br')); p.append(...inline(l)); });
      el.append(p); para = [];
    };
    for (let i = 0; i < lines.length; i += 1) {
      const l = lines[i], item = /^\s*([-*]|(\d{1,4})[.)])\s+(.*)$/.exec(l);
      if (/^\s*```/.test(l)) {
        flush(); ul = null;
        const code = [];
        for (i += 1; i < lines.length && !/^\s*```/.test(lines[i]); i += 1) code.push(lines[i]);
        const pre = h('pre', 'tests-md-code');
        pre.append(h('code', null, code.join('\n')));
        el.append(pre);
      } else if (item) {
        flush();
        const kind = item[2] === undefined ? 'ul' : 'ol';
        if (!ul || ul.tagName.toLowerCase() !== kind) {
          ul = h(kind); el.append(ul);
          if (kind === 'ol' && Number(item[2]) !== 1) ul.start = Number(item[2]);
        }
        const li = h('li'); li.append(...inline(item[3])); ul.append(li);
      } else if (!l.trim()) { flush(); ul = null; } else if (ul && /^\s+\S/.test(l)) {
        ul.lastChild.append(document.createTextNode(' '), ...inline(l.trim()));  // a list item's next line
      } else { ul = null; para.push(l.trim()); }
    }
    flush();
    return el;
  }
  // The verdicts that Optimize acts on: each is one of the fixes an Optimize card picks; stabilise (#188) is Fix
  // failures' (draftFix()).
  const ACTIONABLE = ['speed up', 'split', 'merge', 'delete', 'stabilise'];
  // A judge's text without its last line when that is its VERDICT line (as lib/testaction.sh reads it): the verdict
  // line above the text says it once (#130). Copy still copies the text as written.
  const unverdict = (text) => {
    const lines = String(text).replace(/\s+$/, '').split('\n');
    return /^[\s*`_>-]*VERDICT:/i.test(lines[lines.length - 1]) ? lines.slice(0, -1).join('\n') : text;
  };
  // The judge's reason in one line (#130): the first sentence of its text that is not a heading, a list's title, a
  // HOLLOW or the VERDICT line, without its markup; cut to 160 characters.
  function reasonOf(text) {
    const l = String(text || '').split('\n').map((x) => x.replace(/\*\*|`/g, '').replace(/^\s*(?:#+|[-*]|\d{1,4}[.)])\s*/, '').trim())
      .find((x) => x.split(/\s+/).length > 3 && !/:$/.test(x) && !/^(VERDICT|HOLLOW):/i.test(x));
    if (!l) return '';
    const s = (/^(.+?[.!?])(\s|$)/.exec(l) || [null, l])[1];
    return s.length > 160 ? `${s.slice(0, 159)}…` : s;
  }
  // The box of one action: running, a bar and the time used against its limit, its text so far, Stop and Copy;
  // queued, how many wait before it, and Stop; ended, its result (a judge's verdict line first, with Optimize with this
  // verdict when Optimize acts on it), its text (formatted, but a run's output) and Copy.
  function box(a, f) {
    const h = S.ctx.h, el = h('div', 'tests-box'), head = h('div', 'tests-box-head'), name = ACTS[a.action] || String(a.action);
    el.dataset.id = a.id;
    head.append(h('span', 'board-label', name));
    if (a.state === 'sending') head.append(progress(`Sending: ${name}`), h('span', 'board-from', `Starting: ${SENDING}`));
    if (a.state === 'refused') head.append(h('span', 'tests-refused', `Not started: ${a.reason}`));
    if (a.state === 'sending' || a.state === 'refused') { el.append(head); return el; }
    const text = S.texts.get(a.id) || '', btns = h('div', 'tests-box-btns'), parts = [head];
    if (live(a) && ID.test(a.id)) btns.append(button(S.stopping.has(a.id) ? 'Stopping…' : 'Stop', 'btn-quiet', 'stop', `Stop: ${name}, ${a.file}`, () => stop(a)));
    head.append(...actNow(a, false));
    if (queued(a)) {
      el.append(head, btns);
      return el;
    }
    if (!running(a) && a.action === 'judge' && typeof a.verdict === 'string') parts.push(verdictLine(a, f));
    const out = boxText(a, text);
    btns.append(button('Copy', 'btn-quiet', 'copy', `Copy the text: ${name}, ${a.file}`, () => copy(text)));
    el.append(...parts, out, btns);
    if (a.textCut === true && !text) el.append(h('p', 'board-from', 'The text is long: the build machine sends its end only.'));
    return el;
  }
  // A judge's verdict in its box (box), with Optimize with this verdict when it asks for a change of file f.
  function verdictLine(a, f) {
    const line = S.ctx.h('p', 'tests-verdict', 'Verdict: ');
    line.append(verdictChip(a.verdict));
    if (ACTIONABLE.includes(a.verdict)) {
      // The preview is on the Overview tab: it opens there, scrolled to, with the cursor in its body (#130).
      const fix = a.verdict === 'stabilise';
      const b = button('Optimize with this verdict', 'btn-quiet tests-act', 'optimize-verdict', `${fix ? 'Fix failures' : 'Optimize'} ${a.file}: preview an issue with this verdict`, () => {
        S.tabs.set(dk(f.file), 'overview'); askIssue((x) => (fix ? draftFix(x, a) : draftIssue(x, a)), f, { act: 'issue-body', file: f.file, scroll: true });
      });
      // A runner's time is its files' time, so no Optimize; its failures are its own, so Fix failures holds.
      if (f.wholeOnly === true && !fix) { b.disabled = true; b.title = RUNNER_WHY; }
      line.append(' ', b);
    }
    return line;
  }
  // The text of action a in its box (box): the text as it comes while it runs, else drawn from its Markdown.
  function boxText(a, text) {
    const h = S.ctx.h;
    if (running(a) || a.action === 'run') {
      const out = h('pre', 'tests-out', text || (running(a) ? 'Started. Its text shows here as it comes.' : 'No text.'));
      out.setAttribute('aria-live', 'polite');
      return out;
    }
    return text ? md(a.action === 'judge' ? unverdict(text) : text) : h('p', 'board-from', 'No text.');
  }
  // The action a row's box shows: the one started here until the snapshot lists it, else the file's newest.
  const rowAction = (file) => S.started.get(dk(file)) || actions().find((a) => a.file === file) || null;
  // An Optimize issue's draft: the title the engine knows it by (OPTIMIZE, lib/speedproof.sh), the measured numbers, and
  // a judge's verdict (the one given, else the file's newest kept) with as much of the end of its text as the body
  // holds. Each line is printable (the server refuses a body with a tab or another control character in a line).
  function draftIssue(f, given) {
    const file = f.file, v = given || verdictOf(file), runs = list(f.runs).filter(obj), last = obj(f.lastRun) || {};
    const lines = ['Optimize this test file: speed it up, split it, merge it into another test file, or delete it. Keep what it tests.', '', 'What the Board measured:',
      `- CPU s in its last run: ${one(f.cpu)}`,
      `- Median of its runs: ${one(f.median)} CPU s (${pct(f.change)} against its median)`,
      `- Clock / CPU in its last run: ${num(last.clockPerCpu) === null ? '—' : `${one(last.clockPerCpu)}×`}`,
      `- Runs on record: ${num(f.timedRuns) || 0}. Test steps that failed in it: ${num(f.failedSteps) || 0}. Flaky entries: ${num(f.flaky) || 0}.`,
      `- Last runs, newest first: ${runs.map((r) => `${one(r.cpu)} CPU s (${runBy(r)})`).join(', ') || 'none'}`];
    // A list of items under its heading: as many as the body holds with room for a line that counts the rest.
    const add = (head, items, said) => {
      if (!items.length) return;
      lines.push('', head);
      const at = items.findIndex((x) => { const l = `- ${said(x)}`.replace(/\p{C}/gu, ' '); if (lines.join('\n').length + l.length + 40 > BODY_MAX) return true; lines.push(l); return false; });
      if (at >= 0) lines.push(`- and ${items.length - at} more`);
    };
    // Its hollow cases, and the mutants its tests did not catch (#79), so the card fixes them too.
    add('Hollow cases (they prove nothing): fix each one or delete it.', hollowOf(f), hollowSaid);
    add('Surviving mutants (the code it tests was changed, and its tests still passed): add the assertions that catch each one.', survivors(f), survivorSaid);
    if (v) {
      lines.push('', `The judge's verdict (${v.end || v.start}, ${v.cli} · ${v.model} · ${v.effort}): ${v.verdict}.`);
      const text = (S.texts.get(v.id) || '').split('\n').map((l) => l.replace(/[\p{C}\p{Z}]/gu, ' ').trimEnd()).join('\n').trim();
      const room = BODY_MAX - lines.join('\n').length - 40, chars = Array.from(text);
      if (text && room > 0) lines.push('', 'The end of its text:', chars.length > room ? `…${chars.slice(-room).join('')}` : text);
    }
    return { kind: 'issue', repo: S.d.repo, file, title: `Optimize the test file ${file}`, body: lines.join('\n'), verdict: v ? v.verdict : null };
  }
  // A Fix failures issue's draft (#188): the title the engine knows it by (FIXFAILS, lib/speedproof.sh), what to do, its
  // failures that no card's change caused (flaky or main) with their failing cases, the cause lines of a judge (the one
  // given, else the file's newest with a verdict), the end of each failure's output as far as the body holds, and the
  // Done-when that the card's check (speedproof.sh steadyproof()) holds it to. Each line is printable, as in draftIssue().
  function draftFix(f, given) {
    const file = f.file, v = given || verdictOf(file), xs = fixable(f), line = (l) => l.replace(/\p{C}/gu, ' ').trimEnd();
    const names = [...new Set(xs.flatMap((x) => list(x.cases).filter((c) => typeof c === 'string')))];
    // Only the causes of a case among the failures the draft names: a judge's cause of a case whose failures are all
    // before the history start is no failure this issue asks to fix.
    const causes = list(v && v.causes).filter((x) => obj(x) && typeof x.case === 'string' && typeof x.kind === 'string' && names.includes(x.case));
    // A '## Done when' heading, the section the engine's Done-when check reads (donewhen.sh); plain "Done when:" is none.
    const done = ['', '## Done when', names.length
      ? line(`- The cases that failed (${names.slice(0, 10).join(', ')}${names.length > 10 ? ` and ${names.length - 10} more` : ''}) succeed in 10 runs in a row of this file alone on a test slot.`)
      : '- The file succeeds in 10 runs in a row alone on a test slot.',
    `- ${names.length ? 'They succeed' : 'It succeeds'} in a run beside the other files of the suite.`];
    const head = ['Make this test file succeed reliably, and keep what it tests. Fix the cause of its failures, in the test or in the code it tests; do not delete, skip or weaken a case so that it succeeds.',
      '', 'Its failures that no card\'s change caused, newest first (flaky: it failed, then passed when run again; failed on main too: it failed on main as well):'];
    // A list of items: as many as the body holds with the Done-when, with room for a line that counts the rest.
    const add = (items, said) => {
      const at = items.findIndex((x) => { const l = line(said(x)); if (head.concat(l, done).join('\n').length + 40 > BODY_MAX) return true; head.push(l); return false; });
      if (at >= 0) head.push(`- and ${items.length - at} more`);
    };
    add(xs, (x) => `- ${x.time}, card ${num(x.issue) ? `#${x.issue}` : x.card}: ${kindSaid(x.verdict)}. Failing cases: ${casesSaid(x)}.`);
    if (causes.length) { head.push('', 'The causes the judge named:'); add(causes, (x) => `- CAUSE: ${causeSaid(x)}`); }
    // The end of each failure's output, newest first, while the body holds it; the last one cut to its end.
    const tails = [];
    let room = BODY_MAX - head.concat(done).join('\n').length - 40;
    for (const x of xs.filter((y) => typeof y.tail === 'string' && y.tail.trim())) {
      const top = `The end of the output of card ${num(x.issue) ? `#${x.issue}` : x.card} (${x.time}):`, text = x.tail.split('\n').map(line).join('\n').trim();
      const need = top.length + text.length + 2;
      if (room < top.length + 40) break;
      if (need <= room) { tails.push('', top, text); room -= need; continue; }
      tails.push('', top, `…${Array.from(text).slice(-(room - top.length - 3)).join('')}`);
      break;
    }
    return { kind: 'issue', what: 'Fix failures', repo: S.d.repo, file, title: `Fix the failures of the test file ${file}`, body: head.concat(tails, done).join('\n'), verdict: v && v.verdict === 'stabilise' ? v.verdict : null };
  }
  // ---- the other fix issues (#189): Fix hollow cases, Fix the waiting, Make it run and Delete it ----
  // Each draft's title is the one the engine knows its card by (HOLLOWFIX, WAITFIX, MAKERUN and DELFILE,
  // lib/speedproof.sh), and its Done-when is how the card's check proves it fixed. A list is cut, as in draftFix(), so the
  // body with its Done-when fits BODY_MAX, with a line that counts the rest; each line is printable. A list marked
  // whole (its fourth field true) is never cut: with it the body over BODY_MAX, there is no draft (null).
  const printable = (l) => l.replace(/\p{C}/gu, ' ').trimEnd();
  function drafted(what, title, file, head, lists, done) {
    const lines = head.map(printable);
    lists.forEach(([top, items, said, whole]) => {
      if (!items.length) { if (top) lines.push('', top); return; }
      lines.push('', top);
      if (whole) { lines.push(...items.map((x) => printable(said(x)))); return; }
      const at = items.findIndex((x) => { const l = printable(said(x)); if (lines.concat(l, '', done).join('\n').length + 40 > BODY_MAX) return true; lines.push(l); return false; });
      if (at >= 0) lines.push(`- and ${items.length - at} more`);
    });
    const body = lines.concat('', '## Done when', done).join('\n');
    return body.length > BODY_MAX && lists.some((l) => l[3]) ? null : { kind: 'issue', what, repo: S.d.repo, file, title, body, verdict: null };
  }
  // Its waits (#189): the WAIT lines its newest judge named (the snapshot's waits), [{case, kind, at, reason}].
  const waitsOf = (f) => list(f.waits).filter((x) => obj(x) && typeof x.case === 'string' && typeof x.kind === 'string');
  // The search (#272): the names of the cases the snapshot knows for a file (the cases it defines, its failures', its
  // hollow cases, its waits and its flaky entries), and whether a row shows for the search text q (lower case): its
  // path holds q, or one of its case names does. caseHit: the case that matched, for a row its path did not match.
  const casesOf = (f) => [...new Set([...list(f.cases).filter((c) => typeof c === 'string'),
    ...failsOf(f).flatMap((x) => list(x.cases).filter((c) => typeof c === 'string')), ...hollowOf(f).map((x) => x.case), ...waitsOf(f).map((x) => x.case),
    ...list(S.d && S.d.flaky).filter((c) => obj(c) && typeof c.case === 'string' && c.case.includes(': ') && list(c.files).includes(f.file)).map((c) => c.case.slice(c.case.indexOf(': ') + 2))])];
  const caseHit = (f, q) => (!q || f.file.toLowerCase().includes(q) ? null : casesOf(f).find((c) => c.toLowerCase().includes(q)) || null);
  const shows = (f, q) => !q || f.file.toLowerCase().includes(q) || caseHit(f, q) !== null;
  const waitSaid = (x) => `${x.case} | ${x.kind} | ${typeof x.at === 'string' ? x.at : ''} | ${typeof x.reason === 'string' ? x.reason : ''}`;
  // Why it never ran, when the engine can tell (the snapshot's neverRun: {kind, reason}), else null.
  const neverWhy = (f) => (obj(f.neverRun) && typeof f.neverRun.reason === 'string' && f.neverRun.reason ? f.neverRun.reason : null);
  // Fix hollow cases: each hollow case (hollowOf()) as a HOLLOW line the card's check reads (speedproof.sh hollowproof()).
  const draftHollow = (f) => drafted('Fix hollow cases', `Fix the hollow cases of the test file ${f.file}`, f.file,
    ['Make each hollow case of this test file prove something: a hollow case succeeds without proving anything. Make each case below assert the behaviour it names.',
      'Or delete a case when another test already proves that behaviour, and name that test in your reply, on a line of its own: COVERED-BY: <test file>: <its case> | <the deleted case>.'],
    [['Its hollow cases (case | kind | reason):', hollowOf(f), (x) => `- HOLLOW: ${x.case} | ${x.kind} | ${typeof x.reason === 'string' && x.reason.trim() ? x.reason : 'no reason given'}`]],
    ['- The judge\'s hollow check of the changed file, run by the card\'s check on a model of another family than the builder\'s where one is set up, names no hollow case among the cases above and the cases the change adds or changes.',
      '- Each deleted case has its COVERED-BY line, naming a test file that is kept.']);
  // Fix the waiting: the clock and CPU seconds of its recent runs, and the waits its judge named.
  function draftWaits(f) {
    const last = obj(f.lastRun) || {}, runs = list(f.runs).filter((r) => obj(r) && num(r.sec) !== null && num(r.cpu));
    const w = waitsOf(f);
    return drafted('Fix the waiting', `Fix the waiting of the test file ${f.file}`, f.file,
      [`This test file waits more than it works: its last run took ${num(last.clockPerCpu) === null ? 'more than 2' : one(last.clockPerCpu)} times its CPU seconds on the clock. Remove or shorten its waits, and keep what its cases test: do not cut a wait so that a case no longer checks what it waited for.`],
      [['Its recent runs, newest first (clock, CPU):', runs, (r) => `- ${one(r.sec)} s on the clock for ${one(r.cpu)} CPU s (${one(r.sec / r.cpu)}×), ${runBy(r)}`],
        [w.length ? 'The waits the judge named (case | kind | file:line | reason):' : 'The judge has named no wait of it yet: find the waits in the file (sleep, polling, timeout, lock, network).', w, (x) => `- WAIT: ${waitSaid(x)}`]],
      ['- The file succeeds in 3 runs in a row alone on a test slot, and each run takes at most 2 times its CPU seconds on the clock.']);
  }
  // Make it run and Delete it, on a file that never ran: why, when the engine can tell.
  const neverSaid = (f) => `This test file has never run: no card's test step and no whole-suite run has a run of it on record. ${neverWhy(f) ? `Why, as the engine can tell: ${neverWhy(f)}.` : 'The engine cannot tell why.'}`;
  const draftRun = (f) => drafted('Make it run', `Make the test file ${f.file} run`, f.file,
    [neverSaid(f), 'Make the test command run it (or the pack\'s tests.patterns match it), or fix what stops it loading or skips it. Keep what it tests.'], [],
    ['- The card\'s test step runs this file, and it succeeds.']);
  // Rewrite as a direct check (#778): the proxy parts its newest judge with the verdict indirect named on DIRECT lines
  // (the record's direct: [{protects, check, cases}]), each as a DIRECT line the card's check reads (speedproof.sh optproof()); the
  // recent runs, as draftIssue() lists them, are the figure the check holds the file to.
  const directOf = (file) => {
    const v = verdictOf(file);
    return v && v.verdict === 'indirect' ? list(v.direct).filter((x) => obj(x) && typeof x.protects === 'string' && typeof x.check === 'string' && Array.isArray(x.cases)) : [];
  };
  // A | inside a field is written as / (#827): the card's check splits the line at |, so it keeps three fields.
  const directField = (s) => s.replace(/\|/g, '/');
  const directSaid = (x) => [x.protects, x.check, x.cases.filter((c) => typeof c === 'string').join(', ')].map(directField).join(' | ');
  // Every DIRECT line is in the body (#1384): the card's check asks and checks only the parts the issue names. When
  // they do not fit, the verdict line goes first; the runs line stays, as the card's check takes its CPU limit from it
  // (recentcpu() and slowestrun(), lib/speedproof.sh). When they still do not fit, there is no draft, and the reason
  // (refused) says so.
  function draftDirect(f) {
    const v = verdictOf(f.file), runs = list(f.runs).filter(obj), parts = directOf(f.file), what = 'Rewrite as a direct check';
    const last = ['', `- Last runs, newest first: ${runs.map((r) => `${one(r.cpu)} CPU s (${runBy(r)})`).join(', ') || 'none'}`];
    const facts = [...last, ...(v ? ['', `The judge's verdict (${v.end || v.start}, ${v.cli} · ${v.model} · ${v.effort}): ${v.verdict}.`] : [])];
    const draft = (more) => drafted(what, `Rewrite the test file ${f.file} as direct checks`, f.file,
      ['This test file checks what it protects through a proxy: it runs other test files or the suite runner, runs the real loop, or waits on a real process with a poll. Rewrite each proxy part below as the direct check named for it, and keep each case named there passing.',
        ...more],
      [['Its proxy parts (what it protects | the direct check | the cases that must keep passing):', parts, (x) => `- DIRECT: ${directSaid(x)}`, true]],
      ['- The file keeps each case that a DIRECT line above names, and adds or removes no other test file.',
        '- Run alone with the change on a test slot, the file succeeds and costs less CPU time than its recent runs.']);
    return draft(facts) || draft(last) || { what, file: f.file,
      refused: `Not drafted: the judge's ${parts.length} proxy parts (DIRECT lines) do not fit in one issue of ${BODY_MAX} characters. Ask the judge again, or file the rewrite by hand with every DIRECT line.` };
  }
  // Split it (#768): the cases of the file in two or more test files, and the judge's reason when its newest verdict
  // is split.
  function draftSplit(f) {
    const v = verdictOf(f.file), split = !!v && v.verdict === 'split', why = split ? reasonOf(S.texts.get(v.id) || '') : '';
    const d = drafted('Split it', `Split the test file ${f.file}`, f.file,
      ['Split this test file into two or more test files of the same area. Keep each of its cases once, and unchanged.',
        ...(split ? ['', `The judge's newest verdict is split${why ? `: ${why}` : '.'}`] : [])], [],
      ['- Each case of the file is in exactly one of the new test files, unchanged.',
        '- Each new test file is under 600 lines.',
        '- .conveyor/engine-areas.json and the test map name the new test files.']);
    return { ...d, verdict: split ? 'split' : null };
  }
  const SPLIT_RUNNER_WHY = 'It runs other test files: split one of those, not the runner.';
  const draftDelete = (f) => drafted('Delete it', `Delete the test file ${f.file}`, f.file,
    [neverSaid(f), 'Delete it. For each of its cases that matters, name the test that already proves its behaviour, on a line of its own: COVERED-BY: <test file>: <its case>. When no other test proves a case that matters, make the file run instead.'], [],
    ['- The file is deleted, and each of its cases that matters has a COVERED-BY line naming a test that proves it.']);
  window.DASH_APP.part('tests-mutation', function (shared) {
    ({ S, num, list, obj, one, pct, dk, say, button, ACTS, FILES_MAX, RUNNER_WHY, ENDED, ID, BODY_MAX, NO_SEAT,
      WAIT, SENDING, actions, mmss, limitOf, used, tmodel, hollowOf, hollowSaid, verdictOf, causeSaid, failsOf,
      fixable, kindSaid, casesSaid, runBy, draw, inForce, tests } = shared);
    return { MUT_WHY, mutDone, survivors, trimmed, mutState, mutCell, mutAsk, progress, mutNow, actBtn, send, merge,
      copy, actArgs, start, stop, verdictChip, result, running, queued, live, queuedSaid, actNow, md, reasonOf, box,
      rowAction, draftIssue, draftFix, drafted, caseHit, shows, neverWhy, draftHollow, draftWaits, draftRun,
      draftDirect, draftSplit, SPLIT_RUNNER_WHY, draftDelete, noIssue, askIssue, redraft };
  });
})();
