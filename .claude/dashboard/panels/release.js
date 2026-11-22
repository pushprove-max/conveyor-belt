// SPDX-License-Identifier: Apache-2.0
// Release: one card for each project that releases with Conveyor (main holds docs/releases/: the snapshot's
// release.releases); the others are left out. Its part: {records: [{repo, url, release, suites}]}, the snapshot's
// release and suites of each record, url its repository's address. A card has a head row (the project, its newest tag,
// the changes since it, one status chip), three numbered steps (the notes on main, the whole suite on main's head,
// which says whether its run reran some files and reused the files that passed in an earlier run, or ran the whole
// suite, the release), the version (the snapshot's next filled in; a version typed is drawn at once, its notes as
// main's written says; a version with no notes says so under it) with two buttons, always both: a run button whose
// label follows the state, and Release <version>, disabled with what it waits for in its text until the notes are on
// main and the suite passed on main's head; and the changes since the tag, closed until opened. Each button acts on a
// second click. Draft notes, Run suite, Run suite again and Run again on the new main send `conveyor.sh release-run prep
// <version>`: release-prep alone, which writes a notes draft and stops when main has no notes, else runs the whole
// suite, and releases nothing. Release <version> sends `release-run <version>`: release alone when the suite of that
// version passed on main's head (step 2 and the confirm say "Uses the suite that passed"), else release-prep first
// ("Runs the suite first"); then release makes the tag and the GitHub release. Beside release-prep's red result on main's
// head, Release anyway sends `release-run anyway <version>`: release over that failed suite. Each button that starts the
// suite (Run suite, Run suite again, Run again on the new main, and Release when it runs the suite first) asks, after
// its second click and before it sends, whether the suite runs its test files one by one or in parallel, and sends the
// choice, `--serial` or `--parallel`, then, last, `--machine local` when the control record's suiteMachine (the record's
// part of that name) names a devbox or an ssh box and the owner chose This machine in the question "On which machine?"
// (the rule's machine is preset). While a run goes on such a box, step 2 says the machine, the box, the commit and the
// lease, shows the machine's steps as chips and says what Stop does there; a run that did not start (state "not
// started") on a box shows its failed step with the reason, one fix line, Run on this machine instead and Run suite again
// (one that did not start on this machine lists the reason, with the fix line and Run suite again); a run
// here shows no machine line or steps; step 2 shows the mode of the run under way and of the last run. Stop (`release-run stop`, a second click too) shows only while a run is
// under way. Each reason a refused or failed run printed shows under the step it belongs to, and each failed case
// release-prep judged flaky (it passed every run alone) under the suite's step, and beside a red result the fix cards of
// that run (its record's fixes), each with its state, and what happens next. The panel is wide or full,
// never small: in the narrow column every line wraps.
(() => {
  const VERSION = /^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/;
  const PAGE = 10;          // the changes shown at a time
  const typed = new Map();  // repo -> the version typed, kept through a redraw
  const said = new Map();   // repo -> what the build machine answered to the last press
  const opened = new Set(); // repos whose changes list is open, kept through a redraw
  const asking = new Map(); // repo -> {v, args, what}: a press that waits for the suite's mode, kept through a redraw
  const choice = new Map(); // repo -> 'local': This machine chosen in the question over the rule's, kept through a redraw
  const short = (sha) => (typeof sha === 'string' ? sha.slice(0, 12) : '');
  const list = (x) => (Array.isArray(x) ? x : []);
  const num = (v) => typeof v === 'number' && Number.isFinite(v);
  const MARK = { done: '✓', failed: '✗', now: '▶', todo: '·' };
  // The suite's two modes: the flag release-run takes, the words step 2 says, the choice's name and its one line.
  const MODES = [
    { mode: 'serial', said: 'one by one', label: 'One by one', line: 'Slower, the least load on the build machine.' },
    { mode: 'parallel', said: 'in parallel', label: 'In parallel', line: 'Faster, more load on the build machine. The belt is slower meanwhile.' },
  ];

  // The mode of a run's suite (its record's mode) as a line on step 2, or null when the record has none or no file ran
  // in that mode: a run that reused a green run and ran no file (its reused.ran empty). A release that runs no suite
  // itself keeps the mode of the suite whose result it keeps (release-prep.sh relstart()); one that runs the suite has
  // its own.
  function modeLine(h, x, going) {
    const m = MODES.find((o) => o.mode === x.mode);
    if (!m) return null;
    if (x.reused && typeof x.reused === 'object' && Array.isArray(x.reused.ran) && !x.reused.ran.length) return null;
    const p = h('p', 'row-meta', `${going ? 'Runs' : 'Ran'} its test files ${m.said}`);
    p.dataset.figure = 'suite-mode';
    return p;
  }

  // The machine the control record's suiteMachine rule names, as the panel says it: a devbox by its name, a box over
  // ssh by its host; null for this machine (the default) or a rule that is unreadable.
  function ruleOf(sm) {
    if (!sm || typeof sm !== 'object') return null;
    if (sm.kind === 'devbox') return { kind: 'devbox', name: `Namespace Devbox${sm.size ? ` ${sm.size}` : ''}` };
    if (sm.kind === 'ssh' && typeof sm.target === 'string' && sm.target) return { kind: 'ssh', name: sm.target.replace(/^.*@/, '') };
    return null;
  }

  // The machine question: This machine, or the rule's machine (preset), each with its line. A press sets the choice
  // and draws the question again; `last` is when the last run on the rule's machine ended, else null.
  function machineAsk(h, ctx, repo, rule, last) {
    const box = h('div', 'release-machine');
    box.dataset.figure = 'machine-ask';
    box.setAttribute('role', 'group');
    const q = h('p', 'row-meta', 'On which machine?');
    box.setAttribute('aria-label', q.textContent);
    box.append(q);
    const here = choice.get(repo) === 'local';
    [['local', 'This machine', ['The belt is slower meanwhile.']],
      ['rule', rule.name, ['the rule\'s choice', ...(last ? [' · last run ', ctx.since(last, ' ago')] : [])]]].forEach(([key, name, line]) => {
      const b = h('button', 'btn release-mode-pick');
      b.type = 'button'; b.dataset.act = `machine-${key}`;
      b.setAttribute('aria-pressed', String((key === 'local') === here));
      const l = h('span', 'board-from'); l.append(...line);
      b.append(h('span', 'release-mode-name', name), l);
      b.addEventListener('click', () => { if (key === 'local') choice.set(repo, 'local'); else choice.delete(repo); ctx.redraw(); });
      box.append(b);
    });
    return box;
  }

  // The question a press that starts the suite waits on: the machine (when the rule names another than this one), then
  // one by one or in parallel, each with what it means, and Cancel. A choice sends the press's args with the mode, then
  // `--machine local` when This machine was chosen over the rule's.
  function modeAsk(h, ctx, repo, a, rule, last) {
    const box = h('div', 'release-mode');
    box.dataset.figure = 'mode-ask';
    box.setAttribute('role', 'group');
    const q = h('p', 'row-meta', 'Run the test files one by one or in parallel?');
    box.setAttribute('aria-label', q.textContent);
    if (rule) box.append(machineAsk(h, ctx, repo, rule, last));
    box.append(q);
    MODES.forEach((o) => {
      const b = h('button', 'btn release-mode-pick');
      b.type = 'button'; b.dataset.act = `mode-${o.mode}`;
      b.append(h('span', 'release-mode-name', o.label), h('span', 'board-from', o.line));
      b.addEventListener('click', () => {
        const local = rule && choice.get(repo) === 'local';
        asking.delete(repo); choice.delete(repo);
        send(ctx, repo, [...a.args, `--${o.mode}`, ...(local ? ['--machine', 'local'] : [])], a.what);
      });
      box.append(b);
    });
    const no = h('button', 'btn btn-quiet', 'Cancel');
    no.type = 'button'; no.dataset.act = 'mode-cancel';
    no.addEventListener('click', () => { asking.delete(repo); choice.delete(repo); ctx.redraw(); });
    box.append(no);
    return box;
  }

  // The steps of a run on a box over ssh or a devbox, in the order lib/suitehost.sh goes through them: each as a chip
  // with its time. The record's machine.step is the one under way (or, for a run not started, the one that failed);
  // results is two chips, the results came back with the last poll and the box is given back. Done steps are ok, the
  // one under way info, the failed one bad, the rest quiet.
  const MSTEPS = [['start', 'Start'], ['setup', 'Set up'], ['checkout', 'Check out'], ['run', 'Run'], ['results', 'Bring back results'], ['done', 'Give back the box']];
  const MAT = { start: 0, setup: 1, checkout: 2, run: 3, results: 5, done: 6 };
  function machineSteps(h, ctx, m, failed) {
    const at = Object.hasOwn(MAT, m.step) ? MAT[m.step] : 0, secs = m.secs && typeof m.secs === 'object' ? m.secs : {};
    const ul = h('ul', 'release-machine-steps');
    ul.dataset.list = 'machine-steps';
    MSTEPS.forEach(([key, label], i) => {
      const state = failed && i === at ? 'failed' : i < at ? 'done' : i === at ? 'now' : 'todo';
      const t = secs[i === 5 ? 'results' : key];
      let more = '';
      if (state === 'failed') more = typeof m.reason === 'string' ? m.reason.replace(/^[A-Z](?=[a-z])/, (c) => c.toLowerCase()) : '';
      else if (state === 'done' && num(t)) more = key === 'start' && m.kind === 'devbox' && t === 0 ? 'reused' : key === 'setup' && t === 0 ? 'not needed' : ctx.dur(t);
      const li = h('li', null);
      li.dataset.step = key; li.dataset.state = state;
      li.append(ctx.chip(more ? `${label} · ${more}` : label, { done: 'ok', now: 'info', failed: 'bad', todo: 'quiet' }[state]));
      ul.append(li);
    });
    return ul;
  }

  // "On <machine> (<box>) · commit <sha7> · leased <time>" and the machine's steps, for a run on a box (not this
  // machine); null for a run here or a record with no machine.
  function machineLines(h, ctx, run, failed) {
    const m = run.machine && typeof run.machine === 'object' && run.machine.kind !== 'local' ? run.machine : null;
    if (!m) return [];
    const box = m.kind === 'devbox' ? m.lease : m.target;
    // The commit is recorded once the machine has started (release-prep), so a run still starting, or one whose start failed, has none.
    const sha = short(run.sha).slice(0, 7);
    const p = h('p', 'row-meta', `On ${m.name || m.kind}${box ? ` (${box})` : ''}${sha ? ` · commit ${sha}` : ''}`);
    p.dataset.figure = 'machine';
    if (typeof run.since === 'string' && !failed) p.append(` · ${m.kind === 'devbox' ? 'leased' : 'started'} `, ctx.since(run.since, ' ago'));
    return [p, machineSteps(h, ctx, m, failed)];
  }

  function send(ctx, repo, args, what) {
    said.set(repo, 'Sending…'); ctx.redraw();
    ctx.post('control', { action: 'release-run', args, repo })
      .then((r) => r.text().then((t) => {
        const text = String(t).trim();
        said.set(repo, r.ok ? `${what} The Board shows it in about a minute.` : `Not done: ${text ? ctx.refusal(text) : `the build machine answered ${r.status}`}`);
      }), () => said.set(repo, 'Not done: the build machine did not answer. Make sure that it is on. Then try again.'))
      .then(() => ctx.redraw());
  }

  // A commit subject as its issue's title on one line: no "type(scope): ", no "[P1] file:line" of a finding, no
  // "Proof: …", and the "(#N)" Conveyor puts at its end taken off as the issue number.
  function change(subject) {
    let s = String(subject || ''), issue = null;
    const n = /\s*\(#(\d+)\)\s*$/.exec(s);
    if (n) { issue = Number(n[1]); s = s.slice(0, n.index); }
    s = s.replace(/^[a-z]+(\([^)]*\))?!?:\s*/i, '').replace(/^\[P\d\]\s+\S+:\d+\S*\s+/, '').replace(/\s*Proof:.*$/, '').trim();
    return { issue, title: s || String(subject || '') };
  }

  // Which step a reason a run printed belongs to: the notes, the suite, else the release.
  function stepOf(reason, run) {
    if (/docs\/releases\/|notes/i.test(reason)) return 0;
    if (run.step === 'release-prep' || /suite|moved/i.test(reason)) return 1;
    return 2;
  }

  // The state of one project's release of version v (cur: its last release run, when of v).
  function stateOf(notes, run, v, m) {
    const cur = run && run.version === v ? run : null;
    const going = !!(run && run.ended === null);
    const passed = !!(cur && cur.ended !== null && typeof cur.sha === 'string' && cur.sha
      && (cur.state === 'passed' || cur.state === 'released' || (cur.state === 'refused' && cur.step === 'release' && !cur.failed)));
    const failed = !!(cur && cur.ended !== null && cur.state === 'failed');
    // The suite's machine failed its start, setup or checkout: no test ran (lib/suitehost.sh).
    const notStarted = !!(cur && cur.ended !== null && cur.state === 'not started');
    const moved = passed && cur.state !== 'released' && (cur.moved === true || cur.sha !== m.head);
    const released = !!(run && run.ended !== null && run.state === 'released' && m.tag === `v${run.version}`);
    let chip;
    if (going) chip = ['Suite running', 'info'];
    else if (failed) chip = ['Suite failed', 'bad'];
    else if (notStarted) chip = ['Suite not started', 'bad'];
    else if (moved) chip = ['Main moved since the suite', 'warn'];
    // A release just made: its own commits (the version in plugin.json) are on main past the tag, and the next
    // version's notes are not written yet.
    else if (released && !notes) chip = ['Released', 'ok'];
    else if (!notes) chip = ['Notes missing', 'warn'];
    else if (!passed) chip = ['Suite not run', 'quiet'];
    else if (cur.state === 'released') chip = ['Released', 'ok'];
    else chip = ['Ready to release', 'ok'];
    // Release reuses a passed release-prep of v on main's head, main not moved since (release-run); else it runs the
    // suite first.
    const reuse = passed && !moved && cur.step === 'release-prep' && cur.state === 'passed';
    return { cur, going, passed: passed && !moved, failed, notStarted, moved, released, reuse, chip };
  }

  // One numbered step: its mark (done, failed, in progress or to do), its name and its one line, then what else.
  function step(h, name, state, line, ...more) {
    const li = h('li', 'row'), head = h('div', 'row-main'), mark = h('span', 'step6'), box = h('span', 'step-chip'), m = h('span', 'step-mark', MARK[state]);
    li.dataset.step = name.toLowerCase().replace(/\s+/g, '-');
    li.dataset.state = state;
    mark.dataset.state = state;
    m.setAttribute('aria-hidden', 'true');
    box.append(m, h('span', 'step-name', name));
    mark.append(box);
    // The line is a text, or a span that holds a time as well (the suite's): a span goes in as it is, as h() writes
    // only text.
    const text = typeof line === 'string' ? h('span', null, line) : line;
    text.classList.add('release-line');
    head.append(mark, text);
    li.append(head, ...more.filter(Boolean));
    return li;
  }

  // A run's test files as a line (its progress bar while it runs: files done of all), and its failed files by name.
  // A run with no file counts (a full test's ended line) names the files of its failed cases ("<file>: <case>").
  function counts(h, x, going) {
    const out = [], f = x.files && typeof x.files === 'object' ? x.files : {};
    const of = num(f.of) && f.of > 0 ? f.of : null;
    const names = Array.isArray(f.failed) ? f.failed : [...new Set(list(x.cases).map((c) => String(c).split(': ')[0]))];
    const bad = names.length ? ` · ${names.length} failed` : '';
    if (going && of !== null && num(f.done)) {
      const bar = h('progress', 'tests-progress');
      bar.max = of; bar.value = Math.min(f.done, of);
      bar.setAttribute('aria-label', 'Test files done');
      const p = h('p', 'row-meta');
      p.dataset.figure = 'progress';
      p.append(bar, h('span', null, `${f.done} of ${of} files done${bad}`));
      out.push(p);
    } else if (num(f.done)) {
      out.push(h('p', 'row-meta', `${f.done} ${f.done === 1 ? 'file' : 'files'} done${bad}`));
    }
    if (names.length) {
      const ul = h('ul', 'release-cases');
      ul.dataset.list = 'failed';
      names.forEach((c) => ul.append(h('li', null, String(c))));
      out.push(ul);
    }
    // The cases stopped at their file's time limit (the run's timedout), each said as timed out, not as a plain failure.
    const late = list(x.timedout);
    if (late.length) {
      const ul = h('ul', 'release-cases');
      ul.dataset.list = 'timedout';
      late.forEach((c) => ul.append(h('li', null, `${c}: timed out`)));
      out.push(ul);
    }
    return out;
  }

  // A run under way: its progress (counts()). While its failed cases run again alone (the record's rerun), the round that
  // runs now, its case, its own progress and when it last moved, then the first run's result, not as the progress.
  function rerunLines(h, ctx, run) {
    const r = run.rerun && typeof run.rerun === 'object' && num(run.rerun.round) ? run.rerun : null;
    if (!r) return counts(h, run, true);
    const p = h('p', 'row-meta');
    p.dataset.figure = 'rerun';
    p.append(`Running the failed cases again: round ${r.round}${num(r.of) ? ` of ${r.of}` : ''}${r.case ? `, ${r.case}` : ''}`);
    if (typeof r.at === 'string') p.append(' · last moved ', ctx.since(r.at, ' ago'));
    const first = h('p', 'row-meta', 'First run:');
    first.dataset.figure = 'first-run';
    return [p, ...counts(h, r, true), first, ...counts(h, run, false)];
  }

  // The failed cases of release-prep's red suite that passed every run alone (the record's alone, verdict flaky): they
  // block nothing, and a suite whose every failed case is one of them passed.
  function flakyList(h, x) {
    const names = list(x.alone).filter((c) => c && c.verdict === 'flaky').map((c) => String(c.case));
    if (!names.length) return null;
    const ul = h('ul', 'release-cases');
    ul.dataset.list = 'flaky';
    names.forEach((c) => ul.append(h('li', null, `${c}: judged flaky, passed alone`)));
    return ul;
  }

  // The fix cards of a red run (its record's fixes, lib/fulltest.sh relfixes()): each with its issue link and state,
  // then one line on what happens next. A fix closed with no landed card holds the release for the Foreman; else the
  // suite runs again once every fix has landed, and "now" only when the record's restarted says relfixes() started it:
  // until then a push owed, a pull request not merged or another open card holds it. A run with no fixes: null.
  const FIXSTATE = { open: 'open', landed: 'landed', closed: 'closed with no landed card' };
  function fixesList(h, ctx, x, url) {
    // A fix card with no GitHub issue (rules.releaseissues off) has issue null and its card id.
    const fx = list(x.fixes).filter((f) => f && Object.hasOwn(FIXSTATE, f.state) && ((num(f.issue) && f.issue > 0) || (f.issue === null && typeof f.card === 'string' && f.card !== '')));
    if (!fx.length) return null;
    const box = h('div', 'release-fixes');
    box.dataset.list = 'fixes';
    const ul = h('ul', 'release-cases');
    fx.forEach((f) => {
      const li = h('li', null);
      li.dataset.state = f.state;
      li.append(f.issue === null ? f.card : ctx.issueLink({ issue: f.issue, url: url ? `${url}/issues/${f.issue}` : null }), `: ${FIXSTATE[f.state]}`);
      ul.append(li);
    });
    const closed = fx.filter((f) => f.state === 'closed').map((f) => (f.issue === null ? f.card : `#${f.issue}`));
    const next = closed.length
      ? `${closed.join(', ')} ${closed.length === 1 ? 'was' : 'were'} closed with no landed card: the release waits for the Foreman.`
      : !fx.every((f) => f.state === 'landed') ? 'The suite runs again when every fix has landed.'
        : typeof x.restarted === 'string' ? 'The suite runs again now.'
          : 'Every fix has landed. The suite runs again when their commits are on the branch it tests and no other card is open.';
    const p = h('p', 'row-meta', next);
    p.dataset.figure = 'fixes-next';
    box.append(h('p', 'row-meta', `Fixes of this run: ${fx.filter((f) => f.state === 'landed').length} of ${fx.length} landed`), ul, p);
    return box;
  }

  function reasonsList(h, why) {
    if (!why.length) return null;
    const ul = h('ul', 'release-reasons');
    ul.dataset.list = 'reasons';
    why.forEach((r) => ul.append(h('li', 'reason', String(r))));
    return ul;
  }

  // The changes since the tag: closed, "Show N changes"; open, one line each, newest first, PAGE at a time.
  function changes(h, ctx, rec, m) {
    const all = list(m.commits).map((c) => change(c.subject));
    const n = num(m.count) ? m.count : all.length;
    if (!n) return null;
    const box = h('details', 'release-changes');
    box.dataset.list = 'changes';
    box.open = opened.has(rec.repo);
    box.append(h('summary', null, `Show ${n} ${n === 1 ? 'change' : 'changes'}`));
    box.addEventListener('toggle', () => { if (box.open) opened.add(rec.repo); else opened.delete(rec.repo); });
    const ul = h('ul', 'rows compact');
    const url = typeof rec.url === 'string' ? rec.url : '';
    const line = (c) => {
      const li = h('li', 'row release-change');
      if (c.issue) li.append(ctx.issueLink({ issue: c.issue, url: url ? `${url}/issues/${c.issue}` : null }), ' ');
      const t = h('span', 'release-change-title', c.title);
      t.title = c.title;
      li.append(t);
      return li;
    };
    box.append(ul, ctx.more(`changes:${rec.repo}`, all, (cs) => ul.replaceChildren(...cs.map(line)), PAGE));
    if (n > all.length) box.append(h('p', 'board-from', `${n - all.length} older ${n - all.length === 1 ? 'change is' : 'changes are'} not listed here.`));
    return box;
  }

  function record(rec, ctx, suitesAll) {
    const h = ctx.h, m = rec.release, card = h('li', 'row release-record');
    card.dataset.project = String(rec.repo || '');
    const suites = list(suitesAll), run = suites.find((x) => x && x.kind === 'release') || null;
    const full = suites.find((x) => x && x.kind === 'full test' && x.ended === null) || null;
    const v = (typed.has(rec.repo) ? typed.get(rec.repo) : String(m.next || '')).trim();
    // Whether main holds the notes of the version in the field, the one typed too (written: every version with notes).
    const notes = Array.isArray(m.written) ? m.written.includes(v) : v === m.next && m.notes === true;
    const s = stateOf(notes, run, v, m);
    // The head row: the project, its newest tag, the changes since it, the status.
    const head = h('div', 'row-main');
    const tag = h('span', 'board-from', m.tag ? `Newest release ${m.tag}` : 'No release yet');
    tag.dataset.figure = 'tag';
    const count = h('span', 'board-from', num(m.count) ? `${m.count} ${m.count === 1 ? 'change' : 'changes'} since` : 'changes not counted');
    count.dataset.figure = 'count';
    const chip = ctx.chip(s.chip[0], s.chip[1]);
    chip.dataset.figure = 'status';
    head.append(h('span', 'title', String(rec.repo || '')), tag, count, chip);
    // Each reason of the last run that ended, under its step.
    const why = [[], [], []];
    if (run && run.ended !== null) list(run.reasons).forEach((r) => why[stepOf(String(r), run)].push(r));
    // 1. The notes.
    const notesFailed = why[0].length > 0 && run && run.version === v && run.state === 'refused';
    const s1 = step(h, 'Release notes', notes ? 'done' : notesFailed ? 'failed' : 'todo',
      `docs/releases/${v}.md on main: ${notes ? 'written' : 'missing: Draft notes writes them'}`, reasonsList(h, why[0]));
    // 2. The whole suite on main's head.
    let s2;
    if (s.going) {
      const line = h('span', null, `Running on ${short(run.sha) || 'main\'s head'} · `);
      if (typeof run.since === 'string') line.append(ctx.since(run.since, ' so far'));
      const stop = h('button', 'btn', 'Stop');
      stop.type = 'button'; stop.dataset.act = 'release-stop';
      stop.title = 'End this run\'s processes. Nothing else of Conveyor stops.';
      const moved = run.moved === true ? h('p', 'warn-note', 'Main moved while the suite runs: a card landed, so the suite does not test the new main.') : null;
      const lines = machineLines(h, ctx, run, false);
      const stopBox = h('div', 'release-stop');
      stopBox.append(ctx.twice(stop, 'final', 'Click again to stop the run', () => send(ctx, rec.repo, ['stop'], 'The run is stopped.')));
      if (lines.length) {
        const sl = h('span', 'board-from', run.machine.kind === 'devbox' ? 'Stops the run on the devbox and gives the box back.' : 'Stops the run on the box.');
        sl.dataset.figure = 'stop-line';
        stopBox.append(sl);
      }
      s2 = step(h, 'Full suite', 'now', line, ...lines, modeLine(h, run, true), ...rerunLines(h, ctx, run), moved, stopBox);
    } else if (s.notStarted) {
      // A run that did not start: its failed step's chip says why, with one fix line, and the two ways on.
      // On this machine (its worktree could not be made) the machine's chips are not shown, so the reason is listed, and
      // running on this machine instead is no way on.
      const mc = s.cur.machine, reason = String(mc && mc.reason || ''), remote = !!(mc && typeof mc === 'object' && mc.kind !== 'local');
      const fix = h('p', 'row-meta', /not logged in to namespace/i.test(reason)
        ? 'Run devbox login once in a terminal on the build machine, then press Run suite again.'
        : `Fix the cause named in the ${remote ? 'failed step' : 'reason'}, then press Run suite again.`);
      fix.dataset.figure = 'machine-fix';
      let here = null;
      if (remote) {
        here = h('button', 'btn', 'Run on this machine instead');
        here.type = 'button'; here.dataset.act = 'run-here';
        here.title = 'Run the whole suite on this machine, whatever the rule says. It releases nothing.';
        here.disabled = !VERSION.test(v);
        ctx.twice(here, 'spend', 'Click again to run the suite on this machine', () => {
          if (VERSION.test(v)) send(ctx, rec.repo, ['prep', v, '--machine', 'local'], 'The suite runs on this machine.');
        });
      }
      s2 = step(h, 'Full suite', 'failed', `Not started on ${(mc && mc.name) || 'its machine'}`, ...machineLines(h, ctx, s.cur, true), fix,
        remote && reason ? null : reasonsList(h, reason ? [reason] : why[1]), here);
    } else if (s.cur && (s.passed || s.failed || s.moved)) {
      const c = s.cur, line = h('span', null, `${s.failed ? 'Failed' : 'Passed'} on ${short(c.sha)}`);
      if (typeof c.ended === 'string') line.append(' · ', ctx.since(c.ended, ' ago'));
      if (s.moved) line.append(' · main has moved since');
      // Whether the run reused a green run and ran no test (#44), reran some files and kept the files that passed in an
      // earlier run (#43), or ran the whole suite.
      const u = c.reused && typeof c.reused === 'object' && Array.isArray(c.reused.ran) && num(c.reused.kept) ? c.reused : null;
      const files = (n) => `${n} ${n === 1 ? 'file' : 'files'}`;
      const scope = h('p', 'row-meta', !u ? 'Ran the whole suite'
        : !u.ran.length ? `Reused the green run of ${typeof u.time === 'string' ? ctx.clock(u.time) : 'an earlier time'} on ${short(u.sha)}`
          : `Reran ${files(u.ran.length)}, reused ${u.kept} passed ${u.kept === 1 ? 'file' : 'files'} from ${short(u.sha)}`);
      scope.dataset.figure = 'suite-scope';
      s2 = step(h, 'Full suite', s.failed ? 'failed' : s.moved ? 'todo' : 'done', line, scope, modeLine(h, c, false), ...counts(h, c, false), flakyList(h, c),
        s.failed ? fixesList(h, ctx, c, typeof rec.url === 'string' ? rec.url : '') : null, reasonsList(h, why[1]));
    } else {
      s2 = step(h, 'Full suite', why[1].length ? 'failed' : 'todo', `Not run on main's head (${short(m.head)})`, reasonsList(h, why[1]));
    }
    if (full) {
      const p = h('p', 'row-meta', `A full test run is under way${full.sha ? ` on ${short(full.sha)}` : ''}`);
      p.dataset.kind = 'full test';
      s2.append(p, ...counts(h, full, true));
    }
    // 3. The tag and the GitHub release.
    const relDone = s.released || (s.cur && s.cur.state === 'released');
    const relFailed = !relDone && run && run.ended !== null && run.step === 'release' && run.version === v && why[2].length > 0;
    const s3 = step(h, 'Release', relDone ? 'done' : relFailed ? 'failed' : 'todo',
      relDone ? `${m.tag || `v${run.version}`} is tagged and on GitHub` : `The tag v${v} and the GitHub release`, reasonsList(h, why[2]));
    // What Release does with the suite: uses the green suite run, or runs it first (about as long as the last run took).
    let suiteSaid = '';
    if (notes && s.passed) {
      const c = s.cur, took = Date.parse(c.ended) - Date.parse(c.since);
      suiteSaid = s.reuse ? `Uses the suite that passed at ${ctx.clock(c.ended)} on ${short(c.sha)}`
        : `Runs the suite first${took >= 60000 ? ` (about ${ctx.dur(took / 1000)})` : ''}`;
      const p = h('p', 'row-meta', suiteSaid);
      p.dataset.figure = 'suite-use';
      s2.append(p);
    }
    // Release anyway, beside release-prep's red result on main's head when main holds the notes: the owner's release
    // over that failed suite (`release-run anyway <version>`). A release cannot be undone: a second click whose words
    // name the failed files and cases. The suite's status stays failed.
    if (s.failed && s.cur.step === 'release-prep' && s.cur.sha === m.head && notes && VERSION.test(v)) {
      const c = s.cur, files = c.files && typeof c.files === 'object' ? list(c.files.failed).map(String) : [], named = list(c.cases).map(String);
      const ask = `Click again: release ${v} over this failed suite, with no new run. ${files.length ? `Failed files: ${files.join(', ')}. ` : ''}`
        + `${named.length ? `Failed cases: ${named.join(', ')}.` : 'The run named no failed case.'}`;
      const any = h('button', 'btn', 'Release anyway');
      any.type = 'button'; any.dataset.act = 'release-anyway';
      any.title = `Make the tag v${v} and the GitHub release over this failed suite. Its status stays failed, and the release says who released it over which failures.`;
      s2.append(ctx.twice(any, 'final', ask, () => send(ctx, rec.repo, ['anyway', v], `Release ${v} started over the failed suite.`)));
    }
    const steps = h('ol', 'rows numbered compact release-steps');
    steps.append(s1, s2, s3);
    // The version and two buttons, always both: the run button (its label follows the state) sends release-run prep
    // <version>, which releases nothing; Release <version> sends release-run <version> (the green suite run, or the
    // suite first, then the tag and the GitHub release). Release is disabled until the notes are on main and the suite
    // passed on main's head, and its text says what it waits for.
    const go = h('div', 'release-go'), input = h('input', 'release-version');
    input.type = 'text'; input.setAttribute('aria-label', 'Version to release'); input.dataset.field = 'version';
    input.value = typed.has(rec.repo) ? typed.get(rec.repo) : String(m.next || '');
    const [label, ask, title, what] = s.moved ? ['Run again on the new main', 'Click again to run the suite on the new main',
      'Run the whole suite on main\'s head. It releases nothing.', 'The suite runs again on the new main.']
      : !notes ? ['Draft notes', 'Click again to draft the notes', `release-prep writes a draft of docs/releases/${v}.md for you to read and commit. It runs nothing else.`, 'The notes draft is being written.']
      : [s.passed || s.notStarted ? 'Run suite again' : 'Run suite', 'Click again to run the suite', 'Run the whole suite on main\'s head. It releases nothing.', 'The suite is running.'];
    const btn = h('button', 'btn', label);
    btn.type = 'button'; btn.dataset.act = 'release-prep'; btn.title = title;
    btn.disabled = s.going || !VERSION.test(v);
    // What Release waits for, the first that applies; none: it can run.
    const prog = run && run.files && typeof run.files === 'object' ? run.files : {};
    const bad = s.failed ? (num(s.cur.failed) ? s.cur.failed : list(s.cur.cases).length) : 0;
    const waits = !VERSION.test(v) ? 'needs a version such as 1.2.0'
      : !notes ? `needs release notes docs/releases/${v}.md`
        : s.going ? `the suite is running${num(prog.done) && num(prog.of) && prog.of > 0 ? ` (${prog.done} of ${prog.of} files)` : ''}`
          : s.failed ? `the suite failed: ${bad} ${bad === 1 ? 'failure' : 'failures'}`
            : !s.passed ? `needs the whole suite to succeed on main's head (${short(m.head)})` : '';
    const rel = h('button', 'btn', waits ? `Release ${v}: ${waits}` : `Release ${v}`);
    rel.type = 'button'; rel.dataset.act = 'release'; rel.disabled = !!waits;
    rel.title = waits ? `Release ${v} waits: ${waits}.` : `${suiteSaid}, then make the tag v${v} and the GitHub release.`;
    // A version typed is drawn at once: its notes step, chip and button are of that version, never of the one before.
    input.addEventListener('input', () => {
      const at = input.selectionStart;
      typed.set(rec.repo, input.value);
      const fresh = record(rec, ctx, suitesAll), field = fresh.querySelector('[data-field="version"]');
      card.replaceWith(fresh);
      field.focus({ preventScroll: true });
      if (at !== null) field.setSelectionRange(at, at);
    });
    // A press that runs the suite waits for its mode (modeAsk); Draft notes runs no suite, nor Release that uses the
    // suite that passed.
    const start = (args, what, suite) => {
      if (!suite) { send(ctx, rec.repo, args, what); return; }
      asking.set(rec.repo, { v, args, what }); ctx.redraw();
    };
    ctx.twice(btn, 'spend', ask, () => {
      if (VERSION.test(v)) start(['prep', v], what, label !== 'Draft notes');
    });
    ctx.twice(rel, 'spend', `Click again to release ${v}. ${suiteSaid}.`, () => {
      if (!waits) start([v], `Release ${v} started.`, !s.reuse);
    });
    go.append(input, btn, rel);
    if (said.has(rec.repo)) { const t = h('span', 'undo-line', said.get(rec.repo)); t.setAttribute('role', 'status'); go.append(t); }
    card.append(head, steps, go);
    // The question shows while it is of the version in the field and the button pressed can still run: no run under
    // way, and Release waiting for nothing.
    const a = asking.get(rec.repo);
    if (a && a.v === v && !(a.args[0] === 'prep' ? btn.disabled : waits)) {
      // The rule's machine, and when its last run ended: the record keeps only the newest run, so that is the run of this
      // very machine (same kind and name; a run on another box or here says nothing of it).
      const rule = ruleOf(rec.suiteMachine), lm = run && run.machine && typeof run.machine === 'object' ? run.machine : null;
      card.append(modeAsk(h, ctx, rec.repo, a, rule, rule && lm && lm.kind === rule.kind && String(lm.name).trim() === rule.name && typeof run.ended === 'string' ? run.ended : null));
    }
    // A version with no notes on main says so under the box.
    if (VERSION.test(v) && !notes) {
      const p = h('p', 'row-meta', `${v} has no release notes: docs/releases/${v}.md is not on main.`);
      p.dataset.figure = 'version-notes';
      card.append(p);
    }
    const ch = changes(h, ctx, rec, m);
    if (ch) card.append(ch);
    return card;
  }

  const releasing = (d) => list(d.records).filter((r) => r && r.release && typeof r.release === 'object' && r.release.releases === true);

  window.DASH_APP.panel({
    id: 'release',
    title: 'Release',
    size: 'small',
    tab: 'overview',
    rows: 'all',
    isEmpty: (d) => !releasing(d).length,
    empty(el, ctx) { el.append(ctx.state('empty', 'No project releases with Conveyor.')); },
    error(el, message, ctx) { el.append(ctx.state('error', 'The Board could not read the release state', message)); },
    render(el, d, ctx) {
      const ul = ctx.h('ul', 'rows');
      ul.append(...releasing(d).map((r) => record(r, ctx, r.suites)));
      el.replaceChildren(ul);
    },
  });
})();
