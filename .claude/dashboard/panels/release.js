// SPDX-License-Identifier: Apache-2.0
// Release: for each project, main as a release sees it (the newest tag, the commits on main since it, whether main
// holds the next version's notes), its release run (under way, with its cases done and failed, or the last one's
// result on the commit it tested, and whether that is still main's head) and a full test run under way. Its part:
// {records: [{repo, release, suites}]}, the snapshot's release and suites of each record (null from an older engine).
// Release, with the version typed (the next minor filled in), acts on a second click: that press is the owner's yes to
// release-prep, then, when its suite is green, release (`conveyor.sh release-run <version>`). Stop ends the run under way
// (`release-run stop`), on a second click too. A run that main moved under offers Run again on the new main. A step
// that refused shows each reason it printed.
(() => {
  const VERSION = /^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/;
  const typed = new Map();  // repo -> the version typed, kept through a redraw
  const said = new Map();   // repo -> what the build machine answered to the last press
  const short = (sha) => (typeof sha === 'string' ? sha.slice(0, 12) : '');
  const list = (x) => (Array.isArray(x) ? x : []);
  const STATE = { passed: 'passed', released: 'released', failed: 'failed', refused: 'refused', stopped: 'stopped', error: 'could not run' };

  function send(ctx, repo, args, what) {
    said.set(repo, 'Sending…'); ctx.redraw();
    ctx.post('control', { action: 'release-run', args, repo })
      .then((r) => r.text().then((t) => {
        const text = String(t).trim();
        said.set(repo, r.ok ? `${what} The Board shows it in about a minute.` : `Not done: ${text ? ctx.refusal(text) : `the build machine answered ${r.status}`}`);
      }), () => said.set(repo, 'Not done: the build machine did not answer. Make sure that it is on. Then try again.'))
      .then(() => ctx.redraw());
  }

  // The run's counts: cases done and failed, and the failed cases by name.
  function counts(h, x, el) {
    const n = typeof x.done === 'number' ? `${x.done} ${x.done === 1 ? 'case' : 'cases'} done` : null;
    const f = typeof x.failed === 'number' && x.failed ? `${x.failed} failed` : null;
    if (n || f) el.append(h('span', 'board-from', [n, f].filter(Boolean).join(' · ')));
    const names = list(x.cases);
    if (names.length) {
      const ul = h('ul', 'release-cases');
      ul.dataset.list = 'failed';
      names.forEach((c) => ul.append(h('li', null, String(c))));
      el.append(ul);
    }
  }

  function record(rec, ctx, many) {
    const h = ctx.h, box = h('section', 'release-record'), m = rec.release && typeof rec.release === 'object' ? rec.release : null;
    box.dataset.project = String(rec.repo || '');
    if (many) box.append(h('h3', 'project-name', String(rec.repo || '')));
    if (!m) {
      box.append(h('p', 'warn-note', rec.release === null && rec.suites === null ? 'Conveyor on the build machine is too old to show the release state.' : 'The build machine could not read main.'));
      return box;
    }
    // Main as a release sees it.
    const tag = h('p', 'release-tag');
    tag.dataset.figure = 'tag';
    tag.append(m.tag ? `Newest release ${m.tag}` : 'No release yet', `: ${m.count === null ? 'commits not counted' : `${m.count} ${m.count === 1 ? 'commit' : 'commits'} on main since it`}`);
    box.append(tag);
    if (list(m.commits).length) {
      const ul = h('ul', 'release-commits');
      ul.dataset.list = 'commits';
      list(m.commits).forEach((c) => { const li = h('li', null); li.append(h('code', null, short(c.sha).slice(0, 7)), ` ${c.subject || ''}`); ul.append(li); });
      box.append(ul);
    }
    const notes = h('p', m.notes ? 'release-notes' : 'release-notes warn-note', m.notes ? `docs/releases/${m.next}.md is on main.` : `docs/releases/${m.next}.md is not on main yet: release-prep writes a draft of it and stops.`);
    notes.dataset.figure = 'notes';
    box.append(notes);
    // The runs: the release's, and a full test run under way.
    const suites = list(rec.suites), run = suites.find((x) => x && x.kind === 'release') || null;
    const full = suites.find((x) => x && x.kind === 'full test' && x.ended === null) || null;
    const going = run && run.ended === null;
    if (run) {
      const p = h('div', 'release-run');
      p.dataset.state = String(run.state || '');
      if (going) {
        const line = h('p', null, `${run.step || 'release'} ${run.version} is running${run.sha ? ` on ${short(run.sha)}` : ''} · `);
        if (typeof run.since === 'string') line.append(ctx.since(run.since, ' so far'));
        p.append(line);
        counts(h, run, p);
        const stop = h('button', 'btn', 'Stop');
        stop.type = 'button'; stop.dataset.act = 'release-stop';
        stop.title = 'End this run\'s processes. Nothing else of Conveyor stops.';
        p.append(ctx.twice(stop, 'final', 'Click again to stop the run', () => send(ctx, rec.repo, ['stop'], 'The run is stopped.')));
      } else {
        const line = h('p', null, `Last run: release ${run.version} ${STATE[run.state] || run.state || 'ended'}${run.sha ? ` on ${short(run.sha)}` : ''}`);
        line.dataset.figure = 'last';
        if (typeof run.ended === 'string') line.append(' · ', ctx.since(run.ended, ' ago'));
        if (run.sha) line.append(run.sha === m.head ? ' · that is main\'s head' : ' · main has moved since');
        p.append(line);
        counts(h, run, p);
        const why = list(run.reasons);
        if (why.length) {
          const ul = h('ul', 'release-reasons');
          ul.dataset.list = 'reasons';
          why.forEach((r) => ul.append(h('li', 'reason', String(r))));
          p.append(ul);
        }
      }
      // A card landed while the suite ran: the suite did not test the new main.
      if (run.moved === true) {
        p.append(h('p', 'warn-note', 'Main moved while the suite ran: a card landed, so the suite did not test the new main.'));
        if (!going) {
          const again = h('button', 'btn', 'Run again on the new main');
          again.type = 'button'; again.dataset.act = 'release-again';
          p.append(ctx.twice(again, 'spend', 'Click again to run the release again', () => send(ctx, rec.repo, [run.version], `Release ${run.version} started again.`)));
        }
      }
      box.append(p);
    }
    if (full) {
      const p = h('div', 'release-run');
      p.dataset.kind = 'full test';
      p.append(h('p', null, `A full test run is under way${full.sha ? ` on ${short(full.sha)}` : ''}`));
      counts(h, full, p);
      box.append(p);
    }
    // Release: the version, then a second click.
    const go = h('div', 'release-go'), input = h('input', 'release-version');
    input.type = 'text'; input.setAttribute('aria-label', 'Version to release'); input.dataset.field = 'version';
    input.value = typed.has(rec.repo) ? typed.get(rec.repo) : String(m.next || '');
    const btn = h('button', 'btn', 'Release');
    btn.type = 'button'; btn.dataset.act = 'release';
    btn.title = 'Run release-prep, then, when the whole suite is green on main\'s head, release: the tag and the GitHub release.';
    const check = () => { btn.disabled = !!going || !VERSION.test(input.value.trim()); };
    input.addEventListener('input', () => { typed.set(rec.repo, input.value); check(); });
    ctx.twice(btn, 'spend', 'Click again to release', () => {
      const v = input.value.trim();
      if (VERSION.test(v)) send(ctx, rec.repo, [v], `Release ${v} started: release-prep runs the whole suite first.`);
    });
    check();
    go.append(input, btn);
    if (going) go.append(h('span', 'board-from', 'Cannot work now: a release run is under way.'));
    if (said.has(rec.repo)) { const s = h('span', 'undo-line', said.get(rec.repo)); s.setAttribute('role', 'status'); go.append(s); }
    box.append(go);
    return box;
  }

  window.DASH_APP.panel({
    id: 'release',
    title: 'Release',
    size: 'small',
    tab: 'overview',
    rows: 'all',
    isEmpty: (d) => !list(d.records).length,
    empty(el, ctx) { el.append(ctx.state('empty', 'No project to release', 'The build machine names no project.')); },
    error(el, message, ctx) { el.append(ctx.state('error', 'The Board could not read the release state', message)); },
    render(el, d, ctx) {
      const recs = list(d.records);
      el.replaceChildren(...recs.map((r) => record(r, ctx, recs.length > 1)));
    },
  });
})();
