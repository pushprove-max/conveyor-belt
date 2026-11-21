// SPDX-License-Identifier: Apache-2.0
// The Board's Push landed and full test suite panel (pushTest), how the open issues split, and the row of each open
// parent's parts. Part of panels/board.js, which asks for it by name (DASH_APP.use) and gives it what it uses; boot.js
// loads it before the panels.
(() => {
  'use strict';
  // What this part uses of panels/board.js, set when board.js asks for the part (DASH_APP.part, at the end).
  let STEP, S, num, waitsOn, issues, notPushed, waitsOnly, PART, elOf, send, button, arm, filtering,
    clearFilters, unshaped;
  // ---- what landed and is not pushed, and the full test suite (the part's unpushed and fullTest) ----
  // Actions, not rules: Push landed (the full test suite on main, then, green, the push of the commit it tested), Push
  // now (the push alone, below) and Run full test suite (the suite on main by itself, pushing nothing), with the run under way and the last
  // result: each failed case and what was done with it, and beside a red run Push anyway, on a second click whose words
  // name the failed cases, sent with that run's id so a later red run is not what it pushes over. A full run costs time
  // and a push cannot be undone: each acts on a second click (guarded). A button that cannot work is greyed, and says
  // why beside it.
  const fullOf = () => (S.d.fullTest && typeof S.d.fullTest === 'object' ? S.d.fullTest : null);
  const unpushed = () => (Array.isArray(S.d.unpushed) ? S.d.unpushed : null);
  const short = (sha) => (typeof sha === 'string' ? sha.slice(0, 12) : '');
  // A change that costs money or time ('spend') or cannot be undone ('final') acts on a second click within ARM_MS: the
  // first turns the button to `ask` (its consequence, for a final one). key names it apart from every other.
  function guarded(key, tier, text, ask, act, label, go) {
    const on = S.armed === key;
    const b = button(on ? ask : text, tier === 'final' ? 'btn-final' : 'btn-cost', act, on ? ask : label, () => {
      if (S.armed !== key) { arm(key); return; }
      S.armed = false;
      go();
    });
    b.dataset.guard = tier;
    b.setAttribute('aria-pressed', String(on));
    if (on) b.dataset.armed = '';
    return b;
  }
  // Why neither button can work, or null when they can: no suite in the pack, or a run under way (a second press is
  // refused on the host too).
  function fullOff() {
    const f = fullOf();
    if (!f) return 'Conveyor on the build machine is too old to run this project\'s full test suite from here';
    // The snapshot's why names the setting's file key: said in plain words instead.
    if (f.command !== true) return 'this project has no full test suite set up for Conveyor';
    if (f.running && typeof f.running === 'object') return `a full test run is under way on ${short(f.running.sha)}, and one runs at a time`;
    return null;
  }
  // A failed case of a run and what was done with it: its fix card (and why it is not a new one, when it is not), on the
  // flaky record, or declined with the reason (which says it is outside the code).
  function caseItem(x) {
    const h = S.ctx.h, li = h('li', 'board-push-case');
    li.dataset.verdict = String(x.verdict || '');
    let what = 'not judged';
    if (x.verdict === 'fix') what = `${num(x.issue) !== null ? `fix card #${x.issue}${x.reused ? ' (reused)' : ''}` : 'no fix card filed'}${x.why ? `: ${x.why}` : ''}`;
    else if (x.verdict === 'flaky') what = 'flaky: passed alone every time';
    else if (x.verdict === 'declined') what = `declined: ${x.why || 'outside the code'}`;
    li.append(h('span', 'board-push-name', String(x.case || '')), h('span', 'board-from', what));
    return li;
  }
  // The last run (or push over a red suite) and its outcome; beside a red run with landed commits to push, Push anyway.
  function lastResult(x) {
    const h = S.ctx.h, box = h('div', 'board-push-last'), cases = issues(x.cases), at = short(x.sha), p = x.pushed && typeof x.pushed === 'object' ? x.pushed : null;
    box.dataset.state = String(x.state || '');
    const pushed = p ? (p.ok ? `pushed ${at}` : `the push failed: ${p.reason || 'Conveyor recorded no reason'}`) : 'Conveyor pushed nothing';
    box.append(S.ctx.chip(x.kind === 'anyway' ? 'pushed anyway' : String(x.state || ''), x.state === 'passed' && x.kind !== 'anyway' ? 'ok' : 'warn'), h('span', 'board-push-head', lastHead(x, at, cases, pushed)));
    const scope = reusedScope(x);
    if (scope) box.append(scope);
    if (cases.length) { const ul = h('ul', 'board-push-cases'); cases.forEach((c) => ul.append(caseItem(c))); box.append(ul); }
    const anyway = anywayButton(x, cases);
    if (anyway) box.append(anyway);
    return box;
  }
  // The head line of the last run x (lastResult), on commit at, with its failed cases and what it pushed.
  function lastHead(x, at, cases, pushed) {
    if (x.kind === 'anyway') return `${x.by || 'The owner'} pushed over a red suite: ${pushed}`;
    if (x.state === 'passed') return `Passed on ${at}; ${pushed}`;
    if (x.state === 'failed') return `Failed on ${at}: ${cases.length} ${cases.length === 1 ? 'case' : 'cases'} failed, and Conveyor pushed nothing${x.push ? '. When main is green, press Push landed again.' : ''}`;
    return `Did not run on ${at}: ${x.reason || 'Conveyor recorded no reason'}`;
  }
  // A run that reused the results of an earlier whole-suite run (a full test's, Push landed's or a release's): the
  // green run it took with no test run, or how many files it reran; null for another run.
  function reusedScope(x) {
    const u = x.kind === 'run' && x.reused && typeof x.reused === 'object' && Array.isArray(x.reused.ran) && num(x.reused.kept) !== null ? x.reused : null;
    if (!u) return null;
    const n = u.ran.length, scope = S.ctx.h('span', 'board-from', !n
      ? `Reused the green run of ${typeof u.time === 'string' ? S.ctx.clock(u.time) : 'an earlier time'} on ${short(u.sha)}`
      : `Reran ${n} ${n === 1 ? 'file' : 'files'}, reused ${u.kept} passed ${u.kept === 1 ? 'file' : 'files'} from ${short(u.sha)}`);
    scope.dataset.figure = 'suite-scope';
    return scope;
  }
  // Push anyway, beside a red run x with landed commits to push and no run under way; null when it is not offered.
  function anywayButton(x, cases) {
    const f = fullOf(), un = unpushed();
    if (!(x.kind === 'run' && x.state === 'failed' && /^[0-9a-f]{12}$/.test(String(x.id || '')) && un && un.length && f && f.command === true && !f.running)) return null;
    // A push cannot be undone: a second click whose words say what it pushes over.
    const names = cases.map((c) => c.case).filter(Boolean);
    const ask = `Click again: push ${un.length} landed ${un.length === 1 ? 'card' : 'cards'} over a red suite, with no new run. ${names.length ? `These cases failed: ${names.join(', ')}.` : 'The run named no failed case.'}`;
    return guarded(`anyway:${x.id}`, 'final', 'Push anyway', ask, 'push-anyway', 'Push what landed over this red suite, with no new run', () => send('full-test', ['anyway', x.id]));
  }
  // What runs at each stage of a push (pushing() in conveyor/lib/push.sh); a record with no stage is the hook's.
  const PUSH_STAGE = { tests: 'Tests before the push running', ready: 'Getting the push ready (worktree, dependencies, test slot)',
    hook: 'Pre-push hook running', push: 'Push running with no pre-push hook', ended: 'git push ended, finishing the push', pushed: 'Pushed, waiting for GitHub' };
  // The push (health's pushing and pushLast), so a slow push is told from a stuck one. In progress: what runs (its
  // stage, PUSH_STAGE), since when, on which commit, its process and the time it has taken, then the newest line of
  // the pre-push hook's output; stale, with its log, when its process is gone and it did not end. Else the last push
  // that ended: passed, or failed with the failed check and its log, or started no push; and main still ahead of the
  // remote after it. null: none.
  function pushState() {
    const h = S.ctx.h, r = S.d.pushing && typeof S.d.pushing === 'object' ? S.d.pushing : null, l = S.d.pushLast && typeof S.d.pushLast === 'object' ? S.d.pushLast : null;
    const box = h('div', 'board-push-state');
    if (r) return pushRunning(box, r);
    if (!l) return null;
    return pushEnded(box, l);
  }
  const pushStr = (v) => (typeof v === 'string' ? v : ''), pushOn = (sha) => (pushStr(sha) ? ` on ${short(sha)}` : '');
  const pushLog = (f) => (pushStr(f) ? [S.ctx.h('span', 'board-from', `Log: ${f}`)] : []);
  // The push in progress r (pushState) in box: what runs and since when, or stale.
  function pushRunning(box, r) {
    const h = S.ctx.h;
    box.dataset.state = r.stale === true ? 'stale' : 'running';
    const pid = num(r.pid) !== null ? `pid ${r.pid}` : '';
    if (r.stale === true) {
      box.append(h('span', 'board-push-bad', `The push${pushOn(r.sha)} is stale: its process${pid ? ` (${pid})` : ''} is gone and the push did not end.`), ...pushLog(r.log));
      return box;
    }
    const what = (typeof r.stage === 'string' && Object.prototype.hasOwnProperty.call(PUSH_STAGE, r.stage) ? PUSH_STAGE[r.stage] : '') || PUSH_STAGE.hook;
    const head = h('span', 'board-from', `${what}${pushOn(r.sha)}${typeof r.since === 'string' ? ` since ${S.ctx.clock(r.since)}` : ''}${pid ? ` · ${pid}` : ''}`);
    if (typeof r.since === 'string') head.append(' · ', S.ctx.since(r.since, ''));
    box.append(head, ...(pushStr(r.line) ? [h('span', 'board-push-line', r.line)] : []), ...pushLog(r.log));
    return box;
  }
  // The last push that ended, l (pushState), in box.
  function pushEnded(box, l) {
    const h = S.ctx.h;
    const who = l.by === 'now' ? 'Push now' : l.by === 'full' ? 'Push landed' : 'The push';
    const ahead = num(l.ahead) ? [h('span', 'board-push-bad', `Main is still ${l.ahead} ${l.ahead === 1 ? 'commit' : 'commits'} ahead of the remote.`)] : [];
    box.dataset.state = l.started === false ? 'none' : l.ok === true ? 'passed' : 'failed';
    const text = l.started === false ? `${who} started no push${pushStr(l.why) ? `: ${l.why}` : ''}.`
      : l.ok === true ? `${who}${pushOn(l.sha)} passed.` : `${who}${pushOn(l.sha)} failed${pushStr(l.check) ? `: ${l.check} failed` : ''}.`;
    const head = h('span', l.ok === true && l.started !== false ? 'board-from' : 'board-push-bad', text);
    if (typeof l.time === 'string') head.append(' ', S.ctx.since(l.time, ' ago'));
    box.append(head, ...(l.ok === true ? [] : pushLog(l.log)), ...ahead);
    return box;
  }
  // The two actions, with what they act on: the landed cards origin lacks, each by its issue, and the suite's run.
  function pushTest() {
    const h = S.ctx.h, el = h('section', 'board-push'), un = unpushed(), f = fullOf(), off = fullOff();
    el.setAttribute('aria-label', 'Push what landed, and the full test suite');
    el.append(landedCtl(un, f, off), fullCtl(f, off));
    const merge = mergeCtl();
    if (merge) el.append(merge);
    return el;
  }
  const cannot = (text) => S.ctx.h('span', 'board-from board-push-why', `Cannot work now: ${text}.`);
  // Push landed and Push now (pushTest), with the landed cards they push (un), and the push in progress or the last.
  // off: why no run can start now (fullOff); f: the full test's record (fullOf).
  function landedCtl(un, f, off) {
    const h = S.ctx.h, why = cannot;
    const landed = h('div', 'board-ctl');
    landed.dataset.push = 'landed';
    const cards = h('span', 'board-push-list');
    (un || []).forEach((x) => { const item = h('span', 'board-push-item', typeof x.name === 'string' && x.name ? x.name : `#${x.issue}`); item.dataset.issue = String(x.issue); item.title = String(x.card || ''); cards.append(item); });
    const push = guarded('push-landed', 'spend', 'Push landed', 'Click again to run the full suite, then push', 'push-landed','Run the full test suite on main. When it is green, Conveyor pushes what landed', () => send('full-test', ['push']));
    const nothing = un === null ? 'the Board does not know which landed cards wait for a push' : !un.length ? 'nothing that landed waits for a push' : null;
    push.disabled = !!(off || nothing);
    // Push now: what landed, pushed as Conveyor pushes a card when the push rule is on (the project's pre-push hook
    // only), with no full test run. It needs no suite in the pack, so only a run under way or nothing to push stops it.
    const nowOff = f && f.command !== true ? null : off;
    const pushNow = guarded('push-now', 'final', 'Push now', 'Click again to push now, with no full suite run', 'push-now', 'Push what landed now, through the project\'s pre-push checks only, with no full test run', () => send('push-now', []));
    pushNow.disabled = !!(nowOff || nothing);
    const whyNot = [...new Set([off, nothing, nowOff].filter(Boolean))];
    landed.append(h('span', 'board-label', 'Landed, not pushed'), h('span', 'board-value', un === null ? 'not known' : `${un.length} landed, not pushed`),
      ...(un && un.length ? [cards] : []), push, pushNow, ...whyNot.map(why));
    const ps = pushState();
    if (ps) landed.append(ps);
    return landed;
  }
  // Run full test suite (pushTest), with the run in progress and the last run's result.
  function fullCtl(f, off) {
    const h = S.ctx.h, why = cannot;
    const full = h('div', 'board-ctl');
    full.dataset.push = 'full-test';
    const runBtn = guarded('full-test', 'spend', 'Run full test suite', 'Click again to run the full suite', 'full-test','Run the full test suite on main; it pushes nothing', () => send('full-test', []));
    runBtn.disabled = !!off;
    const run = f && f.running && typeof f.running === 'object' ? f.running : null;
    const now = run ? h('span', 'board-from', `${run.how === 'anyway' ? 'pushing' : 'running'} on ${short(run.sha)}${run.how === 'push' ? ', to push it if green' : ''}`) : null;
    if (now && typeof run.since === 'string') now.append(' · ', S.ctx.since(run.since, ' ago'));
    full.append(h('span', 'board-label', 'Full test suite'), runBtn, ...(now ? [now] : []), ...(off ? [why(off)] : []));
    const last = f && f.last && typeof f.last === 'object' ? f.last : null;
    if (last) full.append(lastResult(last));
    return full;
  }
  // Merge: the open pull request of Land as pr (health's landingPr), with its card count and link, whatever the rule
  // Merge PR says. A merge cannot be undone: it acts on a second click. GitHub's reason for a refused merge shows here.
  // null with no open pull request.
  function mergeCtl() {
    const h = S.ctx.h;
    const pr = S.d.landingPr && typeof S.d.landingPr === 'object' && Number.isInteger(S.d.landingPr.number) ? S.d.landingPr : null;
    if (!pr) return null;
    const box = h('div', 'board-ctl'), n = Number.isInteger(pr.cards) ? pr.cards : 0, link = h('a', 'board-push-item', `#${pr.number}`);
    box.dataset.push = 'merge';
    if (typeof pr.url === 'string' && /^https:\/\//.test(pr.url)) { link.href = pr.url; link.target = '_blank'; link.rel = 'noopener'; }
    box.append(h('span', 'board-label', 'Pull request'), link, h('span', 'board-value', `${n} ${n === 1 ? 'card' : 'cards'}`),
      guarded('merge-pr', 'final', 'Merge', `Click again to merge pull request #${pr.number} into the default branch`, 'merge-pr',
        'Merge the open pull request now, with a merge commit', () => send('merge-pr', [])));
    const m = pr.merge && typeof pr.merge === 'object' ? pr.merge : null;
    if (m && m.result === 'refused') box.append(h('span', 'board-from board-push-why', `GitHub refused the last merge: ${typeof m.reason === 'string' && m.reason ? m.reason : 'it gave no reason'}`));
    return box;
  }

  // How the open issues split: they add up to the open issues (landed, not pushed only when there are any).
  function split() {
    const h = S.ctx.h, o = S.d.open, p = h('p', 'board-split');
    p.dataset.figure = 'split';
    if (!o || typeof o !== 'object' || !o.split) { p.textContent = S.d.issuesError ? '' : 'The Board does not know how the open issues split: the host did not say.'; p.hidden = !p.textContent; return p; }
    const s = o.split;
    p.append(h('span', 'board-value', `${o.count} open`), h('span', null, `${s.queued} queued`), h('span', null, `${s.you} held by you`),
      h('span', null, `${s.labelOrRule} held by a label or skipped by a rule`),
      ...(s.landed > 0 ? [h('span', null, `${s.landed} landed, not pushed`)] : []), h('span', null, `${s.belt} on the belt`));
    return p;
  }

  // The parts of each open parent (an issue with GitHub sub-issues: open.umbrellas) as one row: the parent's title,
  // its parts done of all with a bar, and its parts being built with their step. The row opens to every part with its
  // state (landed: closed, landed today, or landed and not pushed; building, with its step; blocked; waiting: any other) and a link to its
  // card on the Board. The parts' own cards stay in their columns, so a blocked part is still in Needs you.
  // raw: every column's cards (unshaped); a part's card is looked up there, in the column it is in, closed or not.
  function partState(ref, closed, raw) {
    const m = /^#(\d+)$/.exec(ref), n = m ? Number(m[1]) : null;
    const of = (k, keep = () => true) => (n === null ? null : (raw[k] || []).find((x) => x && x.issue === n && keep(x)) || null);
    const at = (col, card) => (card ? { card, col } : {});
    if (closed.includes(ref)) return { state: 'landed', ...at('landed', of('landed')) };
    let c = of('building');
    if (c) return { state: 'building', step: c.step === 'waiting' ? waitsOn(c.waitsOn) : STEP[c.step] || c.step || 'in progress', card: c, col: 'building' };
    if ((c = of('review'))) return { state: 'building', step: `review ${c.review || '?'} of ${c.of || 3}`, card: c, col: 'review' };
    if ((c = of('needs', (x) => !x.waiting))) return { state: 'blocked', card: c, col: 'needs' };
    if ((c = of('landed'))) return { state: 'landed', card: c, col: 'landed' };
    // Landed on an earlier day with push off, not pushed yet: Landed today no longer lists it, Held does.
    if ((c = of('held', notPushed))) return { state: 'landed', card: c, col: 'held' };
    // Waiting for the owner's yes (Needs you), queued, waiting on another issue (in Queue) or held: not being built.
    const col = ['needs', 'queue', 'held'].find((k) => of(k));
    const open = n === null ? null : issues(S.d.open && S.d.open.issues).find((x) => x && x.issue === n);
    return { state: 'waiting', ...at(col, col && of(col)), title: ((col && of(col)) || open || {}).title };
  }
  // The slices of an umbrella (a split issue's, or a parent's parts: its held entry's umbrella), as numbers.
  const slicesOf = (x) => issues(x && x.umbrella).filter((n) => num(n) !== null);
  // A slice's state on an umbrella's card: landed (closed: no longer an open issue, or its card landed), building,
  // blocked, held (in Held for a reason other than a wait) or waiting (queued, waiting on another issue, in Queue or in
  // Held, or waiting for a yes).
  function sliceState(n, raw) {
    const open = S.d.open && Array.isArray(S.d.open.issues) ? S.d.open.issues : null;
    const st = partState(`#${n}`, open && !open.some((x) => x && x.issue === n) ? [`#${n}`] : [], raw);
    return st.state === 'waiting' && st.col === 'held' && !waitsOnly(st.card) ? 'held' : st.state;
  }
  // A link to the part's card on the Board: it brings the card into view and gives it the focus. A card the filter or
  // its column's page hides is shown first: the filter is cleared, then the column shows all its cards.
  function cardLink(n, col) {
    const a = S.ctx.h('a', 'board-part-card', 'Show its card');
    a.href = `#board-card-${n}`;
    a.dataset.act = 'part-card';
    a.addEventListener('click', (e) => {
      e.preventDefault();
      const find = () => elOf(PART).querySelector(`.board-col[data-col="${col}"] .bcard[data-issue="${n}"]`);
      if (!find() && filtering()) clearFilters();
      if (!find()) { const all = elOf(PART).querySelector(`.board-col[data-col="${col}"] .show-more [data-act="list-all"]`); if (all) all.click(); }
      const c = find();
      if (!c) return;
      // On a phone (app.css) Held and Landed today are folded until their button opens them: open the column first.
      const fold = c.closest('.board-col:not(.open)')?.querySelector(':scope > .board-head .board-fold');
      if (fold) fold.click();
      const g = c.closest('details');
      if (g && !g.open) g.open = true;
      if (typeof c.scrollIntoView === 'function') c.scrollIntoView({ block: 'nearest' });
      if (c.tabIndex < 0) c.tabIndex = -1;
      c.focus({ preventScroll: true });
    });
    return a;
  }
  function parents() {
    const h = S.ctx.h, list = issues(S.d.open && S.d.open.umbrellas).filter((u) => u && num(u.issue) !== null);
    const box = h('div', 'board-parents'), raw = unshaped();
    box.hidden = !list.length;
    list.forEach((u) => {
      const refs = issues(u.parts).filter((r) => typeof r === 'string'), closed = issues(u.closed);
      const all = num(u.all) ?? refs.length, done = num(u.done) ?? closed.length;
      const parts = refs.map((ref) => ({ ref, ...partState(ref, closed, raw) }));
      const det = h('details', 'board-parent');
      det.dataset.issue = String(u.issue);
      det.open = S.partsOpen.has(u.issue);
      det.addEventListener('toggle', () => { if (det.open) S.partsOpen.add(u.issue); else S.partsOpen.delete(u.issue); });
      const sum = h('summary', 'board-parent-head');
      const bar = h('span', 'board-parent-bar');
      bar.setAttribute('role', 'img');
      bar.setAttribute('aria-label', `${done} of ${all} parts done`);
      const fill = h('span', 'board-parent-fill');
      fill.style.width = `${all > 0 ? Math.round((100 * Math.min(done, all)) / all) : 0}%`;
      bar.append(fill);
      sum.append(S.ctx.issueLink(u), h('span', 'board-parent-title', u.title || 'untitled'), h('span', 'board-parent-done', `${done} of ${all} done`), bar);
      const now = parts.filter((p) => p.state === 'building');
      sum.append(h('span', 'board-parent-now', now.length ? now.map((p) => `${p.ref} ${p.step}`).join(', ') : 'no part being built'));
      const ul = h('ul', 'board-parent-parts');
      ul.append(...parts.map((p) => {
        const li = h('li', 'board-part');
        li.dataset.part = p.ref; li.dataset.state = p.state;
        const title = p.card ? p.card.title : p.title;
        li.append(h('span', 'issue', p.ref));
        if (title) li.append(h('span', 'board-part-title', title));
        li.append(S.ctx.chip(p.state === 'building' ? `building: ${p.step}` : p.state, { landed: 'ok', building: 'info', blocked: 'bad', waiting: 'quiet' }[p.state]));
        if (p.card && num(p.card.issue) !== null) li.append(cardLink(p.card.issue, p.col));
        return li;
      }));
      det.append(sum, ul);
      box.append(det);
    });
    return box;
  }
  window.DASH_APP.part('board-push', function (shared) {
    ({ STEP, S, num, waitsOn, issues, notPushed, waitsOnly, PART, elOf, send, button, arm, filtering,
      clearFilters, unshaped } = shared);
    return { pushTest, split, slicesOf, sliceState, parents };
  });
})();
