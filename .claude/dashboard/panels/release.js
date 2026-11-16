// SPDX-License-Identifier: Apache-2.0
// Release: one card for each project that releases with Conveyor (main holds docs/releases/: the snapshot's
// release.releases); the others are left out. Its part: {records: [{repo, url, release, suites}]}, the snapshot's
// release and suites of each record, url its repository's address. A card has a head row (the project, its newest tag,
// the changes since it, one status chip), three numbered steps (the notes on main, the whole suite on main's head,
// which says whether its run reran some files and reused the files that passed in an earlier run, or ran the whole
// suite, the release), the version (the snapshot's next filled in; a version typed is drawn at once, its notes as
// main's written says) with one button whose label follows the state, and the changes since the tag, closed until opened. Each button
// acts on a second click. Draft notes, Run suite and Run again on the new main send `conveyor.sh release-run prep
// <version>`: release-prep alone, which writes a notes draft and stops when main has no notes, else runs the whole
// suite, and releases nothing. Release <version> sends `release-run <version>`: release alone when the suite of that
// version passed on main's head (step 2 and the confirm say "Uses the suite that passed"), else release-prep first
// ("Runs the suite first"); then release makes the tag and the GitHub release. Stop (`release-run stop`, a second click too) shows only while a run is
// under way. Each reason a refused or failed run printed shows under the step it belongs to. The panel is wide or full,
// never small: in the narrow column every line wraps.
(() => {
  const VERSION = /^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/;
  const PAGE = 10;          // the changes shown at a time
  const typed = new Map();  // repo -> the version typed, kept through a redraw
  const said = new Map();   // repo -> what the build machine answered to the last press
  const opened = new Set(); // repos whose changes list is open, kept through a redraw
  const short = (sha) => (typeof sha === 'string' ? sha.slice(0, 12) : '');
  const list = (x) => (Array.isArray(x) ? x : []);
  const num = (v) => typeof v === 'number' && Number.isFinite(v);
  const MARK = { done: '✓', failed: '✗', now: '▶', todo: '·' };

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
    const moved = passed && cur.state !== 'released' && (cur.moved === true || cur.sha !== m.head);
    const released = !!(run && run.ended !== null && run.state === 'released' && m.tag === `v${run.version}`);
    let chip;
    if (going) chip = ['Suite running', 'info'];
    else if (failed) chip = ['Suite failed', 'bad'];
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
    return { cur, going, passed: passed && !moved, failed, moved, released, reuse, chip };
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
    return out;
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
      s2 = step(h, 'Full suite', 'now', line, ...counts(h, run, true), moved,
        ctx.twice(stop, 'final', 'Click again to stop the run', () => send(ctx, rec.repo, ['stop'], 'The run is stopped.')));
    } else if (s.cur && (s.passed || s.failed || s.moved)) {
      const c = s.cur, line = h('span', null, `${s.failed ? 'Failed' : 'Passed'} on ${short(c.sha)}`);
      if (typeof c.ended === 'string') line.append(' · ', ctx.since(c.ended, ' ago'));
      if (s.moved) line.append(' · main has moved since');
      // Whether the run reran some files and kept the files that passed in an earlier run (#43), or ran the whole suite.
      const u = c.reused && typeof c.reused === 'object' && Array.isArray(c.reused.ran) && num(c.reused.kept) ? c.reused : null;
      const files = (n) => `${n} ${n === 1 ? 'file' : 'files'}`;
      const scope = h('p', 'row-meta', u
        ? `Reran ${files(u.ran.length)}, reused ${u.kept} passed ${u.kept === 1 ? 'file' : 'files'} from ${short(u.sha)}`
        : 'Ran the whole suite');
      scope.dataset.figure = 'suite-scope';
      s2 = step(h, 'Full suite', s.failed ? 'failed' : s.moved ? 'todo' : 'done', line, scope, ...counts(h, c, false), reasonsList(h, why[1]));
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
    const steps = h('ol', 'rows numbered compact release-steps');
    steps.append(s1, s2, s3);
    // The version and the one button: its label follows the state. Release sends release-run <version> (the green
    // suite run, or the suite first, then the tag and the GitHub release); the others send release-run prep <version>, which
    // releases nothing.
    const go = h('div', 'release-go'), input = h('input', 'release-version');
    input.type = 'text'; input.setAttribute('aria-label', 'Version to release'); input.dataset.field = 'version';
    input.value = typed.has(rec.repo) ? typed.get(rec.repo) : String(m.next || '');
    const [label, ask, title, what, prep] = s.moved ? ['Run again on the new main', 'Click again to run the suite on the new main',
      `Run the whole suite on main's head. It releases nothing: Release ${v} shows when it has no failures.`, 'The suite runs again on the new main.', true]
      : !notes ? ['Draft notes', 'Click again to draft the notes', `release-prep writes a draft of docs/releases/${v}.md for you to read and commit. It runs nothing else.`, 'The notes draft is being written.', true]
      : !s.passed ? ['Run suite', 'Click again to run the suite', `Run the whole suite on main's head. It releases nothing: Release ${v} shows when it has no failures.`, 'The suite is running.', true]
      : [`Release ${v}`, `Click again to release ${v}. ${suiteSaid}.`, `${suiteSaid}, then make the tag v${v} and the GitHub release.`, `Release ${v} started.`, false];
    const btn = h('button', 'btn', label);
    btn.type = 'button'; btn.dataset.act = 'release'; btn.title = title;
    btn.hidden = s.going;
    btn.disabled = s.going || !VERSION.test(v);
    // A version typed is drawn at once: its notes step, chip and button are of that version, never of the one before.
    input.addEventListener('input', () => {
      const at = input.selectionStart;
      typed.set(rec.repo, input.value);
      const fresh = record(rec, ctx, suitesAll), field = fresh.querySelector('[data-field="version"]');
      card.replaceWith(fresh);
      field.focus({ preventScroll: true });
      if (at !== null) field.setSelectionRange(at, at);
    });
    ctx.twice(btn, 'spend', ask, () => {
      if (VERSION.test(v)) send(ctx, rec.repo, prep ? ['prep', v] : [v], what);
    });
    go.append(input, btn);
    if (said.has(rec.repo)) { const t = h('span', 'undo-line', said.get(rec.repo)); t.setAttribute('role', 'status'); go.append(t); }
    card.append(head, steps, go);
    const ch = changes(h, ctx, rec, m);
    if (ch) card.append(ch);
    return card;
  }

  const releasing = (d) => list(d.records).filter((r) => r && r.release && typeof r.release === 'object' && r.release.releases === true);

  window.DASH_APP.panel({
    id: 'release',
    title: 'Release',
    size: 'wide',
    widths: ['wide', 'full'],
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
