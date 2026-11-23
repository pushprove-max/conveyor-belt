// SPDX-License-Identifier: Apache-2.0
// Health: is the machinery running. Its part: {host: {name, reachable, error}, records | null (one per Conveyor
// record: repoUrl (its repository's https address, else null), snapshotAt (when its kept snapshot was made, or null), loop, state (as its control record says: a loop it stops is off, not stopped), newest, stuck, unpushed, pushError, pushFailingSince, lastPushAt, gh, diskFreeKb, cycles, flaky: [{case, count, issue, files, url}] | null, slowOff: [{file, issue, url, cpu, budget, card, last: {cpu, card}}] | null, untimed: the last card test runs that recorded no test times, 0 when one did | null, split: {kept, wouldSplit: {cards, reviewed, go, fixes}, split} | null: the cards the rule Split large issues checked, report: {runner, format, path, env, args, option}, the pack's test.report | null, timesPlan: {kind: report | wrap | card, ...} | null (what Record test times would do), quarantined: [{line, field, time}] | null: the card records' lines set aside, serviceOld: {commit, refused, project} | null: the machine's Conveyor runs another commit, whose check refuses the pack), limit | null (the
// usage-limit reading of this machine's own login: only its Codex reading and, with billing "api", its api block (the week's dollars against the weekly cap) show here), limitError,
// limits: [{repo, account (null: the default login), uses (build, review), pct, readAt, email}] | null (the weekly limit of each account the cards run on, as the build machine's guard reads it),
// accounts: {error, list: [{machine (null: this machine), name, email, usedPct, fiveHourPct, resetsAt, readAt (when its figures were read), error,
// usedFor: [what it is used for] | null, cards (a card runs on it; null: not known), others (the Rules tab can move its work to another account)}]} | null,
// stream: {live, heardAt, since, error, writtenAt} | null (Conveyor's live stream), update: {checkedAt, head, error, moved: {from, to, at,
// restart, restartFailed?} | null} | null (the main checkout brought forward to origin/main), pluginBugs: [{repo, projects, count, file, url}] (the plugin
// problems each Foreman noted, their file, and the Board's copy of it)}.
// A row whose chip is a fault or a warning is failing: the failing rows come first, faults before warnings, each with
// one line of what to do next ("Next: …"); the rows that are fine fold into one "N checks fine" that opens to them.
// A row is one plain line: a long or many-line text (a push's output) shows its first line, cut, and the whole under
// "Show output"; a one-line error shows a plain sentence of what failed, the raw line under "Raw error"; a wait given in
// seconds ("retry after 1022 s") reads "try again in 17 min".
const HEALTH_LINE = 100; // the most characters a row's text shows before the rest goes under "Show output"
const OLD_READING_MS = 15 * 60 * 1000; // a usage or account reading older than this shows its age and is a warning
const ACCOUNTS_DOC = 'https://github.com/pushprove-max/conveyor-belt/blob/main/conveyor/README.md#accounts'; // how an account is added to the host file
window.DASH_APP.panel({
  id: 'health',
  title: 'Health',
  size: 'small',
  tab: 'overview',
  projects: true,  // filtered to one project, its record's checks and the limits of its accounts alone; the host, this machine's limit and the accounts stay the machine's
  rows: 'all',  // a figures panel: every check shows
  rowSelector: '.checks > dt',
  isEmpty: (d) => !d.host.name && !d.records && !d.limit,
  empty(el, ctx) { el.append(ctx.state('empty', 'No health reading yet', 'This checkout names no Conveyor host, and the Board read no usage limit.')); },
  error(el, message, ctx) { el.append(ctx.state('error', 'The Board could not read Health', message)); },
  render(el, d, ctx) {
    const h = ctx.h, rows = [];
    // When the first kept snapshot shown as new turns a minute old: tick draws the panel again then (an equal part
    // that comes again draws nothing).
    let snapOldAt = Infinity;
    // A row: its label, its chip and what it says; next is what to do when it is failing (a row that is fine says none).
    // A row's output ({ tail } in its detail) is drawn here, given the row's "Show output" of the draw before (known by
    // its label), so that one keeps its place: the same node with the same output, else its scroll (ctx.output).
    const olds = new Map(Array.from(el.querySelectorAll('dd > details.output'), (o) => [o.parentElement.previousElementSibling?.dataset.check, o]));
    const check = (label, chip, ...detail) => {
      const dd = h('dd');
      const shown = detail.flat().map((x) => (x && Object.prototype.hasOwnProperty.call(x, 'tail') ? ctx.output(x.tail, null, x.label || null, olds.get(label)) : x));
      dd.append(chip, ...shown.filter(Boolean).map((x) => (typeof x === 'string' ? h('span', 'detail', x) : x)));
      const dt = h('dt', null, label);
      dt.dataset.check = label;
      const row = { dt, dd, next: null };
      rows.push(row);
      return row;
    };
    // A text from the host as one plain line: whole when short, else its first line cut, with the whole under "Show output".
    const plain = (text) => {
      if (typeof text !== 'string' || !text.trim()) return [];
      const t = healthWaits(text.trim(), ctx);
      if (t.length <= HEALTH_LINE && !t.includes('\n')) return [t];
      const first = t.split('\n')[0];
      return [h('span', 'detail', first.length > HEALTH_LINE ? `${first.slice(0, HEALTH_LINE - 1)}…` : first), { tail: t }];
    };
    // An error from the host or git: one line is a plain sentence with the raw line under "Raw error" (healthError);
    // several lines are a log, drawn as plain() draws it.
    const error = (text) => {
      if (typeof text !== 'string' || text.trim().includes('\n')) return plain(text);
      const e = healthError(text, ctx);
      return e ? [e.line, { tail: e.raw, label: 'Raw error' }] : [];
    };
    // One row of a Health list (a test case or file), in a review finding's row styles: its name, a chip of its count
    // and the issue filed for it (f) as a link when there is one on a line; what more it says (why) under it. The
    // name's file (file, the start of name) is code linked to the file in the record's repository (repo: its repoUrl,
    // else its issue's), and why is drawn as a review finding's text (ctx.text.fill).
    const item = (repo, name, file, count, f, why) => {
      const T = ctx.text, row = h('li', 'output-finding'), head = h('div', 'finding-head'), said = h('p', 'finding-text');
      const url = repo || T.repoOf(f);
      if (file && name.startsWith(file)) {
        const c = h('code', 'why-code', file), to = T.fileUrl(url, file);
        said.append(to ? T.linkTo(c, to, 'finding-file') : c, name.slice(file.length));
      } else said.append(name);
      head.append(said, ctx.chip(count, 'quiet'));
      if (typeof f.issue === 'number' && f.issue > 0) head.append(ctx.issueLink(f));
      row.append(head);
      if (why) row.append(T.fill(h('p', 'detail'), why, url, new Set(T.pathsIn(why)), 'finding'));
      return row;
    };
    // On one machine (host.local, #112) Conveyor runs here: the row is this machine's, read with no SSH. A host file
    // that does not read says why in its error, which names the field to correct.
    const here = d.host.local === true;
    const name = here ? `This machine${d.host.name ? ` (${d.host.name})` : ''}` : d.host.name || 'Build machine';
    if (d.host.reachable === true) check(name, ctx.chip(here ? 'Conveyor read' : 'Reachable', 'ok'), error(d.host.error));
    else if (d.host.reachable === false) check(name, ctx.chip(here ? 'No answer' : 'Unreachable', 'bad'), error(d.host.error)).next = here
      ? 'Conveyor on this machine did not answer in time. The Board asks again in about a minute.'
      : 'Check the build machine is on and this computer reaches it over SSH.';
    else check(name, ctx.chip('Not checked', 'warn'), error(d.host.error)).next = 'The Board checks it again in about a minute. Before that check, correct the host file as the error says.';
    // How old what the page shows is: dataRow below (it draws its own next step). The Board's feed is restarted from
    // this row, after its next step (ctx.restartButton, with what the host answered beside it); the head shows a
    // restart too only while its mark says the feed is at fault (app.js). With no stream to tell the data's age, the
    // row is the restart alone, named for it.
    const s = d.stream, data = check(s && typeof s === 'object' ? 'Data' : 'Board\'s feed', h('span'));
    data.dd.restart = ctx.restartButton();
    if (s && typeof s === 'object') dataRow(data.dd, s, ctx);
    else data.dd.append(data.dd.restart);
    // A stuck card; one waiting on a same-file card names that card's issue and where it is (blocked, queued).
    // A main-red fix card (issue 0) by its name, "Main is red (<commit>)", as health gives it.
    const ref = (x) => (typeof x.name === 'string' && x.name ? x.name : `#${x.issue}`);
    const stuck = (s) => (s.step === 'waiting' && s.waitsOn && typeof s.waitsOn === 'object'
      ? `${ref(s)} waiting on ${typeof s.waitsOn.issue === 'number' ? ref(s.waitsOn) : 'a card'}${s.waitsOn.state ? ` (${s.waitsOn.state})` : ''}`
      : `${ref(s)} in ${s.step}`);
    // A card whose engine or own process is stopped by a signal (its stuck entry's stopped, health): nothing retries
    // it, so its next step is the SIGCONT to each stopped process (stopped.pid, stopped.pids, stopped.own; for a stopped
    // engine also each stopped process under it, the record's engineStopped.pids: a wrapper left stopped holds the
    // card), not a retry.
    const stoppedSaid = (s, r) => {
      const st = s.stopped, own = st.own && typeof st.own === 'object' ? st.own : {};
      const eng = st.of === 'engine' && r.engineStopped && Array.isArray(r.engineStopped.pids) ? r.engineStopped.pids : [];
      const pids = [...new Set([st.pid, ...eng, ...(Array.isArray(st.pids) ? st.pids : []), own.pid, ...(Array.isArray(own.pids) ? own.pids : [])].filter(Number.isInteger))];
      return `${ref(s)}: ${st.of === 'engine' ? 'Conveyor\'s engine' : 'the card\'s process'} is stopped by a signal, and nothing retries it. `
        + `Send it SIGCONT${pids.length ? `: kill -CONT ${pids.join(' ')}` : ''}.`;
    };
    (d.records || []).forEach((r) => {
      const of = d.records.length > 1 ? ` (${r.repo})` : '';
      // A loop its control record stops is not meant to run: it is off, not a fault. One meant to run with no
      // loop process is.
      const off = !r.loop && r.state === 'stopped';
      const loop = check(`Conveyor${of}`, r.loop ? ctx.chip('Running', 'ok') : off ? ctx.chip('Off', 'quiet') : ctx.chip('Stopped', 'bad'), off ? 'not meant to run' : null,
        r.newest ? 'last step recorded' : 'no step recorded', r.newest ? ctx.since(r.newest, ' ago') : null);
      if (!r.loop && !off) loop.next = `Start Conveyor again on ${ctx.machine}: its machine command starts every project.`;
      // The kept snapshot this view is read from (conveyor.sh snapshot), shown only when it is over a minute old.
      const snapAt = typeof r.snapshotAt === 'string' ? Date.parse(r.snapshotAt) : NaN;
      if (!Number.isNaN(snapAt) && Date.now() - snapAt > 60000) {
        check(`Snapshot${of}`, ctx.chip('Old', 'warn'), 'made', ctx.since(r.snapshotAt, ' ago')).next =
          `Conveyor makes a new snapshot after each change. If it stays old, run conveyor.sh snapshot --fresh in the project's checkout on ${ctx.machine}: it says why the snapshot cannot be made.`;
      } else if (!Number.isNaN(snapAt)) snapOldAt = Math.min(snapOldAt, snapAt + 60000);
      // The machine's Conveyor runs an older commit, whose check refuses this project's pack: it does not run the project.
      const so = r.serviceOld;
      if (so && typeof so === 'object' && typeof so.commit === 'string') {
        check(`Conveyor's version${of}`, ctx.chip('Too old for the pack', 'bad'),
          plain(`Conveyor ${so.commit.slice(0, 12)} on ${ctx.machine} refuses the pack: ${so.refused || 'its check failed'}`)).next =
          `Run conveyor.sh install-service in the project's checkout on ${ctx.machine}. It starts Conveyor again on ${typeof so.project === 'string' && so.project ? `the project's commit ${so.project.slice(0, 12)}` : "the project's commit"}.`;
      }
      // A failing push: one line of how long and which check, its output under "Show output".
      if (r.pushFailingSince) {
        const e = r.pushError || {}, line = h('span', 'detail');
        line.append('Push failing for ', ctx.since(r.pushFailingSince, ''), typeof e.check === 'string' && e.check ? `: ${e.check} failed` : '');
        check(`Last push${of}`, ctx.chip('Failing', 'bad'), line, { tail: e.reason }).next = e.kind === 'check'
          ? 'It is in Needs you. The push waits until a fix lands on main, and Conveyor does not try it again before that.'
          : 'Conveyor tries it again by itself. If a retry fails, it shows in Needs you.';
      } else if (r.unpushed.length) {
        check(`Last push${of}`, ctx.chip(`${r.unpushed.length} not pushed`, 'warn'), 'oldest landed', ctx.since(r.unpushed[0].since, ' ago')).next =
          'Conveyor pushes after each landing. If Push on landing is off, Push landed on the Control tab pushes them.';
      } else check(`Last push${of}`, ctx.chip('All pushed', 'ok'), r.lastPushAt ? 'pushed' : 'no push recorded', r.lastPushAt ? ctx.since(r.lastPushAt, ' ago') : null);
      if (r.stuck.length) {
        const halted = r.stuck.filter((s) => s && s.stopped && typeof s.stopped === 'object');
        check(`Stuck cards${of}`, ctx.chip(`${r.stuck.length} stuck`, 'bad'), plain(r.stuck.map(stuck).join(', '))).next = [...halted.map((s) => stoppedSaid(s, r)),
          ...(halted.length < r.stuck.length ? ["Conveyor stops a stuck session and tries it again by itself. If the session stays stuck, read the card's last step in On the belt."] : [])].join(' ');
      }
      // A dependency cycle: its issues wait on each other, so none of them is ever picked.
      if (Array.isArray(r.cycles) && r.cycles.length) check(`Dependency cycles${of}`, ctx.chip(`${r.cycles.length} cycle${r.cycles.length === 1 ? '' : 's'}`, 'bad'),
        plain(r.cycles.map((c) => c.map((n) => `#${n}`).join(' ↔ ')).join('; '))).next = "Break each cycle: take one issue off another's Depends on: line on GitHub.";
      // The cases that failed and then passed when run again in the last 7 days (conveyor/lib/flaky.sh): how many on
      // the row's line, and under "Show output" one row each (item): its name, a chip of how many re-runs, and the
      // issue filed for it when there is one. A record from before the snapshot gave them has none.
      if (Array.isArray(r.flaky)) {
        const cases = r.flaky.filter((f) => f && typeof f.case === 'string' && typeof f.count === 'number');
        if (cases.length) {
          const det = h('details', 'output'), list = h('ul', 'output-findings flaky-list');
          // A case is "<file>: <case>", or the file alone when the run named no case (conveyor/lib/testrun.sh notpassed).
          list.append(...cases.map((f) => item(r.repoUrl, f.case, /^(.+?): /.exec(f.case)?.[1] ?? f.case, `${f.count} ${f.count === 1 ? 're-run' : 're-runs'}`, f)));
          det.append(h('summary', null, 'Show output'), list);
          check(`Flaky tests${of}`, ctx.chip(`${cases.length} case${cases.length === 1 ? '' : 's'}`, 'warn'),
            `${cases.length === 1 ? '1 case' : `${cases.length} cases`} passed only on re-run in the last 7 days`, det).next =
            'Fix each case, or the fixture under it. If a case has an issue, fix the case through that issue.';
        } else check(`Flaky tests${of}`, ctx.chip('None', 'ok'), 'no case passed only on re-run in the last 7 days');
      }
      // The test files a "Slow test" issue still keeps off card test steps (conveyor/lib/testrun.sh slowoffs()), each
      // with its CPU seconds in the two card test runs that filed it, and the issue whose card brings it back. One row
      // each (item), the figures under its name.
      if (Array.isArray(r.slowOff)) {
        const files = r.slowOff.filter((f) => f && typeof f.file === 'string');
        if (files.length) {
          const n = (x) => (typeof x === 'number' ? `${Math.round(x * 10) / 10}` : '?');
          const det = h('details', 'output'), list = h('ul', 'output-findings slow-off-list');
          list.append(...files.map((f) => item(r.repoUrl, f.file, f.file, 'Kept off', f,
            `${n(f.cpu)} CPU s in ${f.card ?? 'a card'}'s test run and ${n(f.last?.cpu)} in ${f.last?.card ?? 'the one before'}'s; runs only in the full test suite until its issue lands`)));
          det.append(h('summary', null, 'Show output'), list);
          check(`Kept off card tests${of}`, ctx.chip(`${files.length} file${files.length === 1 ? '' : 's'}`, 'warn'),
            `${files.length === 1 ? '1 test file' : `${files.length} test files`} kept off card test steps by a Slow test issue`, det).next =
            'Each comes back to card test steps when the card of its Slow test issue lands: make the file cheaper there.';
        } else check(`Kept off card tests${of}`, ctx.chip('None', 'ok'), 'every test file runs in card test steps');
      }
      // The project's last card test runs recorded no test times (untimed: how many; conveyor/lib/views.sh): its test
      // command prints no `TESTRUN sec` lines and no report of its runner was read. When setup found a runner whose report Conveyor cannot read now (report: the pack's test.report with
      // no format), the row names the runner and the report option that would give the times.
      if (typeof r.untimed === 'number' && r.untimed > 0) {
        const rp = r.report && typeof r.report === 'object' && typeof r.report.runner === 'string' && !r.report.format && typeof r.report.option === 'string' ? r.report : null;
        // With a plan from the engine (timesPlan: report, wrap or card), the row says what the plan does and its button
        // runs it (an admin's: the Board refuses a member); with none, the row points at the README.
        const words = timesWords(r.timesPlan);
        check(`Test times${of}`, ctx.chip('Not recorded', 'warn'),
          `the last ${r.untimed === 1 ? 'card test run' : `${r.untimed} card test runs`} recorded no test times${rp ? `; the test command runs ${rp.runner}, and Conveyor cannot read its output` : ''}`,
          words ? TIMES_SAID.get(r.repo) : null).next = words ? [words, ' ', timesButton(r.repo, ctx)] : rp
          ? `Add the report option ${rp.option} to the test command, then run setup again: Conveyor reads each test file's times from that report. The section "Test file times" in conveyor/README.md tells more.`
          : 'Add them to the test command: the section "Test file times" in conveyor/README.md tells how.';
      }
      // The cards the rule Split large issues checked (split: {kept, wouldSplit, split}; conveyor/lib/views.sh SPLITM):
      // how many it kept and would split, and the first-review GO rate and fix rounds of each, side by side.
      const sp = r.split && typeof r.split === 'object' ? r.split : null;
      if (sp) {
        const grp = (g) => (g && typeof g === 'object' && typeof g.cards === 'number' ? g : { cards: 0, reviewed: 0, go: 0, fixes: 0 });
        const k = grp(sp.kept), w = grp(sp.wouldSplit), n = typeof sp.split === 'number' ? sp.split : 0;
        const rate = (g) => (g.reviewed ? `first-review GO ${Math.round((g.go / g.reviewed) * 100)}%, ${(g.fixes / g.reviewed).toFixed(2)} fix rounds` : 'no review yet');
        check(`Split check${of}`, ctx.chip(`${k.cards + w.cards + n} checked`, 'ok'),
          `kept ${k.cards} (${rate(k)}); would split ${w.cards} (${rate(w)})${n ? `; split into slices ${n}` : ''}`);
      }
      // The landed cards whose last lint line skipped a command for a missing tool (unchecked; conveyor/lib/views.sh):
      // that command checked nothing of their change. A count, as Split check is; none shows no row.
      if (typeof r.unchecked === 'number' && r.unchecked > 0) check(`Lint check${of}`, ctx.chip(`${r.unchecked} unchecked`, 'ok'),
        `${r.unchecked === 1 ? '1 card' : `${r.unchecked} cards`} landed with a lint command skipped for a missing tool`);
      // The card records' lines the record check set aside (quarantined: [{line, field, time}]; conveyor/lib/views.sh
      // check()): the loop reads on without them, and the owner decides what each was.
      const quarantined = Array.isArray(r.quarantined) ? r.quarantined.filter((q) => q && typeof q === 'object') : [];
      if (quarantined.length) check(`Records set aside${of}`, ctx.chip(`${quarantined.length} line${quarantined.length === 1 ? '' : 's'}`, 'warn'),
        plain(quarantined.map((q) => `line ${q.line}: ${q.field} refused, ${q.time}`).join('; '))).next =
        'Look at each line in quarantined.jsonl in the state folder: fix the writer or conveyor/jq/check.jq, then remove the line from that file.';
      // Each Claude route (routes; conveyor/lib/control.sh routesnow()): the subscription login and the API proxy, each
      // in the state the last session on it found. A failed login is a warning while a fallback proxy works.
      const routes = r.routes && typeof r.routes === 'object' ? r.routes : null;
      if (routes) {
        const sub = routes.subscription && typeof routes.subscription === 'object' ? routes.subscription : {};
        const px = routes.proxy && typeof routes.proxy === 'object' ? routes.proxy : {};
        const covered = px.route === 'fallback' && px.state === 'works';
        // When each role uses the proxy, as its route (roles) sets it.
        const when = { fallback: 'when its subscription login fails', proxy: 'always', subscription: 'never' };
        const roles = px.roles && typeof px.roles === 'object' ? px.roles : {};
        const uses = ['builder', 'reviewer'].filter((r) => when[roles[r]]).map((r) => `the ${r} ${when[roles[r]]}`).join(', ');
        const route = (name, s, tones) => {
          const state = typeof s.state === 'string' && s.state ? s.state : 'not checked';
          const tone = tones[state] || 'quiet';
          const where = typeof s.baseUrl === 'string' ? (uses ? `${s.baseUrl}, ${uses}` : s.baseUrl) : null;
          const row = check(`Claude route: ${name}${of}`, ctx.chip(state.charAt(0).toUpperCase() + state.slice(1), tone), where,
            typeof s.at === 'string' ? ctx.since(s.at, ' ago') : null);
          return tone === 'quiet' || tone === 'ok' ? null : row;
        };
        const bad = covered ? 'warn' : 'bad';
        const subRow = route('subscription login', sub, { works: 'ok', expired: bad, 'not set': bad });
        if (subRow) subRow.next = px.state === 'not set'
          ? `Sign in again on ${ctx.machine}: run claude, then /login. Or run /conveyor-belt:setup to set a local API proxy as the fallback.`
          : `Sign in again on ${ctx.machine}: run claude, then /login.`;
        const pxRow = route('API proxy', px, { works: 'ok', fails: 'bad' });
        if (pxRow) pxRow.next = `Start the proxy on ${ctx.machine}, or set the host file's claudeProxy to a proxy that runs. The blocked card shows its error.`;
      }
      if (!r.gh) check(`GitHub${of}`, ctx.chip('Not signed in', 'bad'), 'gh cannot read or close issues').next = `Run gh auth login on ${ctx.machine}.`;
      else if (r.ghReached === false) check(`GitHub${of}`, ctx.chip('Not reached', 'warn'), 'gh is signed in, but its check with GitHub failed').next =
        `Check the network on ${ctx.machine}, or run gh auth status there.`;
      if (typeof r.diskFreeKb === 'number' && r.diskFreeKb < 10485760) check(`Disk${of}`, ctx.chip('Low', 'warn'), `${(r.diskFreeKb / 1048576).toFixed(1)} GB free for cards`).next =
        'Free space on the disk that holds the cards folder.';
    });
    const lim = d.limit;
    // The bar is drawn with a scale, so its change is a transform.
    const bar = (pct, says) => {
      const meter = h('span', 'meter'), fill = h('span', 'meter-fill');
      fill.style.transform = `scaleX(${Math.max(0, Math.min(100, pct)) / 100})`;
      meter.append(fill);
      meter.setAttribute('role', 'img');
      meter.setAttribute('aria-label', says);
      return meter;
    };
    const SLOW = 'lower cards at once on the Rules tab to slow it.';
    // A machine that pays by API (billing "api") has a week of dollars against its weekly spending cap, not a
    // percent. It shows first; the subscription reading shows beside it only when there is one.
    const api = lim && lim.billing === 'api' ? lim.api : null;
    if (api) {
      const capped = typeof api.limitUsd === 'number' && api.limitUsd > 0;
      const resets = typeof api.timeLeftSec === 'number' ? `resets in ${ctx.dur(api.timeLeftSec)}` : null;
      const partial = api.complete ? null : 'the Board did not read and price every request';
      if (typeof api.spentUsd !== 'number') {
        check('Weekly spend', ctx.chip('Not read', 'warn'), capped ? `the weekly cap is ${ctx.money(api.limitUsd)}, but the Board could not price the spend this week` : 'the Board could not price the spend this week, and there is no weekly cap', resets).next =
          'The Board prices it again in about a minute.';
      } else if (capped) {
        const usedPct = api.spentUsd / api.limitUsd * 100;
        const spent = h('span', 'detail');
        spent.append(ctx.number('api-spent', api.spentUsd, ctx.money), h('span', null, ` of the ${ctx.money(api.limitUsd)} weekly cap spent`));
        let pace = ctx.chip('Under pace', 'ok'), next = null;
        if (usedPct >= 100) { pace = ctx.chip('Over the cap', 'bad'); next = `Raise the weekly cap, or wait for the reset; ${SLOW}`; }
        else if (usedPct >= 90) { pace = ctx.chip('Nearly used up', 'bad'); next = `Raise the weekly cap, or wait for the reset; ${SLOW}`; }
        else if (typeof api.underUsd === 'number' && api.underUsd < 0) { pace = ctx.chip('Over pace', 'warn'); next = `At this pace the cap runs out before it resets; ${SLOW}`; }
        check('Weekly spend', pace, bar(usedPct, `${Math.round(usedPct)} percent of the weekly spending cap spent`), spent, resets, partial).next = next;
      } else {
        const spent = h('span', 'detail');
        spent.append(ctx.number('api-spent', api.spentUsd, ctx.money), h('span', null, ' spent this week'));
        check('Weekly spend', ctx.chip('No cap set', 'quiet'), spent, resets, partial);
      }
    }
    // A reading older than OLD_READING_MS says when it was read and how long ago ("from 9:00 AM, 6 h 00 min ago"):
    // its figures may no longer be true. Null for a newer one, or one with no time.
    const old = (iso) => {
      const t = typeof iso === 'string' ? Date.parse(iso) : NaN;
      if (Number.isNaN(t) || Date.now() - t <= OLD_READING_MS) return null;
      const s = h('span', 'detail');
      s.append(`from ${ctx.clock(iso)}, `, ctx.since(iso, ' ago'));
      return s;
    };
    const OLD_NEXT = 'The Board reads it again by itself when the wait from the usage server ends. The reason is beside it. Until then, these figures stay this old.';
    // The 7-day limit of each account the cards run on, as the build machine's guard reads it (limits), never this
    // machine's own login: the cards can run on another account. One row for one account; with more (a project's
    // builder and reviewer accounts, or more projects), each row names its project and account.
    const limits = Array.isArray(d.limits) ? d.limits.filter((l) => l && typeof l === 'object') : [];
    const USES = { build: 'build and fix', review: 'reviews' };
    const AGAIN = 'Conveyor reads it again before its next pick.';
    limits.forEach((l) => {
      const who = l.account || 'default';
      const label = limits.length > 1 ? `Usage limit of ${l.repo}: ${who}` : 'Usage limit';
      const of = `account ${who}, ${l.email || 'no email recorded'}: ${(Array.isArray(l.uses) ? l.uses : []).map((s) => USES[s] || s).join(' and ')}`;
      // Beside a weekly spend (api), an account with no subscription reading shows no row, as with no accounts.
      if (typeof l.pct !== 'number') { if (!api) check(label, ctx.chip('Not read', 'warn'), 'no reading yet', of).next = AGAIN; return; }
      const meter = bar(l.pct, `${Math.round(l.pct)} percent of the 7-day limit used`);
      const pct = h('span', 'detail');
      pct.append(ctx.number(`used:${l.repo}:${who}`, l.pct, (v) => `${Math.round(v)}%`), h('span', null, ' of the 7-day limit used'));
      const age = old(l.readAt);
      let chip = ctx.chip('Fine', 'ok'), next = null;
      if (l.pct >= 90) { chip = ctx.chip('Nearly used up', 'bad'); next = `Wait for the reset, or ${SLOW}`; }
      else if (age) { chip = ctx.chip('Old reading', 'warn'); next = AGAIN; }
      check(label, chip, meter, pct, of, age).next = next;
    });
    // A record whose every role runs on an API route (its routes' subscription roles are none; routesnow() in
    // conveyor/lib/control.sh) has no usage limit: it is billed per token. Its row is a fine check, with the cost the
    // session logs give for today (limit.today) in place of a reading. limit.today counts only the sessions of the
    // Board's own project (dashboard_limit.py build reads its main and workspaces), the record on the host's main
    // (steered), so it is shown on that record's row alone, and only on one machine (host.local): with a build
    // machine apart, the cards ran there and this machine's logs do not hold their cost.
    const viaApi = (Array.isArray(d.records) ? d.records : []).filter((r) => r && r.routes && r.routes.subscription
      && Array.isArray(r.routes.subscription.roles) && !r.routes.subscription.roles.length);
    const today = lim && lim.today && typeof lim.today.spentUsd === 'number' ? lim.today.spentUsd : null;
    viaApi.forEach((r) => {
      check(limits.length || viaApi.length > 1 ? `Usage limit of ${r.repo}` : 'Usage limit', ctx.chip('Fine', 'ok'), 'API route: no usage limit (billed per token)',
        d.host.local !== true || r.steered !== true ? null : today === null ? `the session logs give no cost today for ${r.repo}`
          : `${ctx.money(today)} spent today on ${r.repo} on this machine, from the session logs`);
    });
    if (!limits.length && !api && !viaApi.length) check('Usage limit', ctx.chip('Not read', 'warn'), 'no reading').next = AGAIN;
    // Codex's quota is its own reading: it shows whether or not Claude's was read.
    if (lim && lim.codex && typeof lim.codex.usedPct === 'number') check('Codex limit', ctx.chip(`${Math.round(lim.codex.usedPct)}% used`, lim.codex.usedPct >= 90 ? 'warn' : 'quiet')).next =
      "Pick another reviewer on the Rules tab, or wait for Codex's reset.";
    // Every Claude account read, on this machine and on the Conveyor host, each with its own figures and what it is
    // used for. The email is shown here only.
    const acc = d.accounts && typeof d.accounts === 'object' ? d.accounts : null;
    // An account no card runs on (cards false) is one dim row with its reading and no next step: it has no work to
    // move. One the cards run on is told to move its work on the Rules tab only when the Rules tab has another account
    // to move it to (others); else to wait for its reset and where an account is added.
    (acc && Array.isArray(acc.list) ? acc.list : []).forEach((a) => {
      const used = typeof a.usedPct === 'number', age = used ? old(a.readAt) : null, idle = a.cards === false;
      const where = a.machine || 'this machine';
      // An expired login is the Board's own sentence, the host's error under "Raw error"; any other error is the host's (error()).
      const why = typeof a.error === 'string' && /^HTTP 401\b/.test(a.error)
        ? [`this login has expired: sign in again on ${where}`, { tail: a.error.trim(), label: 'Raw error' }] : error(a.error);
      const row = check(`Account ${a.name}${a.machine ? ` on ${a.machine}` : ' on this machine'}`,
        used ? ctx.chip(`${Math.round(a.usedPct)}% used`, idle ? 'quiet' : a.usedPct >= 90 ? 'bad' : age ? 'warn' : 'quiet') : ctx.chip('Not read', idle ? 'quiet' : 'warn'),
        a.email || 'no email recorded', age, typeof a.fiveHourPct === 'number' ? `5-hour window ${Math.round(a.fiveHourPct)}%` : null,
        Array.isArray(a.usedFor) ? a.usedFor.join('; ') : 'the Board does not know its use: it did not read the records', used && !age ? null : why);
      if (idle) return;
      const reset = typeof a.resetsAt === 'string' && a.resetsAt ? ` at ${ctx.when(a.resetsAt)}` : '';
      const doc = h('a', null, 'Accounts');
      doc.href = ACCOUNTS_DOC; doc.target = '_blank'; doc.rel = 'noopener';
      row.next = !used ? 'The Board reads it again in about a minute. If an account has no login, sign in to it again on its machine.'
        : a.usedPct < 90 && age ? OLD_NEXT
        : a.others === true ? `Move this account's work to another on the Rules tab, or wait for its reset${reset}.`
        : [`Wait for its reset${reset}. To move its work to another account, add one to `, h('code', null, 'accounts'), ` in ${ctx.machine === 'the build machine' ? "the build machine's" : 'the'} host file (`, doc, ').'];
    });
    if (acc && acc.error) check(d.host.local === true ? 'Accounts' : 'Host accounts', ctx.chip('Not read', 'warn'), error(acc.error)).next = 'The Board reads them again in about a minute.';
    // A checkout that could not be brought forward says why; the last move says whether the dashboard restarted on it.
    const u = d.update;
    if (u && typeof u === 'object') {
      const m = u.moved && typeof u.moved === 'object' ? u.moved : null;
      check('Dashboard code', u.error ? ctx.chip('Not updated', 'warn') : ctx.chip('Up to date', 'ok'), u.error ? error(u.error) : (u.head ? `main at ${u.head}` : null),
        m ? `${m.restartFailed ? 'brought forward, restart failed' : m.restart ? 'restarted on new code' : 'brought forward'} ${m.from}..${m.to}` : null, m ? ctx.since(m.at, ' ago') : null).next =
        m && m.restartFailed ? 'Restart the Board on this machine to run the new code.' : 'Make the main checkout the same as origin/main by hand. The reason is beside it.';
    }
    // The plugin problems a Foreman noted (conveyor/foreman/stop.sh): only the owner can fix or file them in the
    // plugin's repository, so each Foreman that noted one has a warning row, with a link to the Board's copy of its
    // file (url, served beside the page: a browser opens no file:// link from an https page). A grouped Foreman's
    // notes come once for each of its projects, so the project filter keeps them: the row is drawn once a file.
    const bugs = Array.isArray(d.pluginBugs) ? d.pluginBugs.filter((b, i, all) => b && b.count > 0 && typeof b.file === 'string'
      && all.findIndex((o) => o && o.file === b.file) === i) : [];
    bugs.forEach((b) => {
      const of = bugs.length > 1 && Array.isArray(b.projects) ? ` (${b.projects.join(', ')})` : '';
      const link = h('a', null, b.file);
      if (typeof b.url === 'string' && b.url) { link.href = b.url; link.target = '_blank'; link.rel = 'noopener'; }
      check(`Plugin problems${of}`, ctx.chip(`${b.count} noted`, 'warn'), `${b.count} plugin ${b.count === 1 ? 'problem' : 'problems'} noted in `, link).next =
        'Read each note under Plugin problems. Then fix it, or file it as an issue in the conveyor-belt repo. Then click Dismiss, unless you filed it with File on GitHub, which removes the note. When the Board says it filed the issue but could not remove the note, click Dismiss.';
    });
    const pane = pluginPane(bugs, ctx);
    // Failing first (faults, then warnings, each in the order drawn), each with its next step before its output; the
    // rest fold into "N checks fine". While a check here is a fault or another panel could not read its data
    // (ctx.faults()), the Data row and its restart stay out of the fold, where the texts that name the restart send
    // the owner (#115).
    const rank = (row) => healthRank(row.dd);
    const shown = (row) => rank(row) < 2 || (row === data && (rows.some((r) => rank(r) === 0) || ctx.faults()));
    const failing = rows.filter(shown).sort((a, b) => rank(a) - rank(b));
    const fine = rows.filter((row) => !shown(row));
    const list = (rs) => {
      const dl = h('dl', 'checks');
      rs.forEach((row) => {
        if (row.next && rank(row) < 2) {
          const p = h('p', 'check-next', 'Next: ');
          p.append(...[].concat(row.next)); // a next step is its text, or its text and nodes (a link)
          row.dd.insertBefore(p, row.dd.querySelector(':scope > details.output'));
        }
        dl.append(row.dt, row.dd);
      });
      return dl;
    };
    // What the owner opened stays open through a redraw (the live feed draws the panel again with each change): "checks fine",
    // and each row's "Show output", known by its row's label.
    const was = el.querySelector(':scope > details.checks-fine');
    const opened = new Set(Array.from(el.querySelectorAll('dd > details.output[open]'), (o) => o.parentElement.previousElementSibling?.dataset.check));
    rows.forEach((row) => { const o = row.dd.querySelector(':scope > details.output'); if (o && opened.has(row.dt.dataset.check)) o.open = true; });
    const out = [];
    if (failing.length) out.push(list(failing));
    if (pane) out.push(pane);
    if (fine.length) {
      const det = h('details', 'checks-fine');
      det.append(h('summary', null, `${fine.length} ${fine.length === 1 ? 'check' : 'checks'} fine`), list(fine));
      det.open = Boolean(was && was.open);
      out.push(det);
    }
    out.push(healthWorkView(ctx));
    el.replaceChildren(...out);
    if (Number.isFinite(snapOldAt)) el.dataset.snapOldAt = String(snapOldAt);
    else delete el.dataset.snapOldAt;
  },
  tick(el, ctx) {
    // A Live whose stream has not been written to in time turns into its age, with no new data to say so; a row that
    // turns into a warning so leaves the rows that are fine (the panel is drawn again).
    let moved = false;
    el.querySelectorAll('dd[data-live-until]').forEach((dd) => {
      if (Date.now() > Number(dd.dataset.liveUntil)) {
        dataRow(dd, dd.stream, ctx);
        if (dd.closest('.checks-fine') && healthRank(dd) < 2) moved = true;
      }
    });
    // A kept snapshot shown as new that is now over a minute old: the panel is drawn again, with its Snapshot row.
    if (el.dataset.snapOldAt && Date.now() > Number(el.dataset.snapOldAt)) moved = true;
    if (moved) { ctx.redraw(); return; }
    el.querySelectorAll('[data-age-from]').forEach((n) => {
      const text = healthAge(n.dataset.ageFrom, ctx);
      if (n.textContent !== text) n.textContent = text;
    });
  },
});
// The Plugin problems pane (issue 1042): each note of each Foreman's plugin-bugs.md is a row with its time, card and
// text, and Dismiss, which removes that one line from the file (POST plugin-dismiss) and files nothing. With no note,
// there is no pane (null). A note dismissed here stays out until the next snapshot no longer has it, so it does not
// come back for a minute; one that failed says why in its row until the next try.
// File on GitHub (issue 1043; not on a note that names the issue it was filed as) asks the server for the issue the note proposes (POST plugin-preview) and opens it under
// the note, its title and body editable; File the issue sends the edited title and body (POST plugin-file), which the
// server checks for private text before gh runs. Only the note whose preview was confirmed is filed. A filed note
// leaves the list as a dismissed one does, and the new issue's link stays in the pane until the page loads again. A
// refused or failed filing keeps the preview open with the reason. The preview's fields are the same nodes at each
// redraw (the live feed draws the panel every few seconds), so the owner's edits, focus and caret stay.
// Record test times (conveyor/lib/setup.sh timesplan()): what the engine's plan does, in words, by its kind; null for a
// plan the Board does not know. The answer to the button, by repo, stays through the redraws of the live feed.
function timesWords(p) {
  if (!p || typeof p !== 'object') return null;
  if (p.kind === 'report' && p.report && typeof p.report.runner === 'string') {
    return `Record test times sets test.report in the pack to the report of ${p.report.runner}, so Conveyor reads each test file's times from it.`;
  }
  if (p.kind === 'wrap' && typeof p.file === 'string' && typeof p.command === 'string') {
    const fc = typeof p.fileCommand === 'string' && p.fileCommand ? `, and ${p.fileCommand} as test.fileCommand` : '';
    return `Record test times wraps the test command, which runs only ${p.file}, in the helper that prints test times, and saves ${p.command} as test.command${fc} in the pack.`;
  }
  if (p.kind === 'card' && typeof p.file === 'string') {
    return `Record test times files a held card, with no GitHub issue, to wrap each test file's run in ${p.file}: that script is yours. Release the card when you agree.`;
  }
  return null;
}
const TIMES_SAID = new Map();
function timesButton(repo, ctx) {
  const b = ctx.h('button', 'btn btn-quiet', 'Record test times');
  b.type = 'button'; b.dataset.act = 'record-times';
  b.addEventListener('click', () => {
    b.disabled = true;
    TIMES_SAID.delete(repo);
    ctx.post('control', { action: 'test-settings', args: ['record-times'], repo })
      .then((r) => r.text().then((t) => [r.ok, String(t).trim() || `the Board answered ${r.status}`]), () => [false, 'the Board did not answer'])
      .then(([ok, said]) => {
        TIMES_SAID.set(repo, ok ? `Done: ${said}` : `Not recorded:${ctx.refusal(said).replace(/\.$/, '')}.`);
        ctx.redraw();
      });
  });
  return b;
}
const PLUGIN_DISMISSED = new Set();
const PLUGIN_FAILED = new Map();
const PLUGIN_PREVIEW = new Map();
const PLUGIN_FILED = [];
function pluginPreview(n, k, ctx) {
  const h = ctx.h, p = PLUGIN_PREVIEW.get(k);
  const box = h('div', 'plugin-preview');
  const doc = p.title.ownerDocument, on = [p.title, p.body].find((x) => x === doc.activeElement);
  const caret = on ? [on.selectionStart, on.selectionEnd] : null;
  const send = h('button', 'btn', p.busy ? 'Filing…' : 'File the issue');
  send.type = 'button'; send.dataset.act = 'plugin-file'; send.disabled = p.busy;
  send.addEventListener('click', () => {
    p.busy = true; p.error = null;
    ctx.redraw();
    ctx.post('plugin-file', { file: n.file, line: n.line, title: p.title.value, body: p.body.value })
      .then((r) => r.text().then((t) => [r.ok, String(t).trim() || `the Board answered ${r.status}`]), () => [false, 'the Board did not answer'])
      .then(([ok, said]) => {
        p.busy = false;
        if (ok) {
          PLUGIN_PREVIEW.delete(k); PLUGIN_DISMISSED.add(k);
          PLUGIN_FILED.push({ title: p.title.value, url: said });
        } else {
          // "filed as <link>, but the note could not be removed": filed all the same, so not "Not filed".
          const s = said.replace(/\.$/, '');
          p.error = /^filed as /.test(s) ? `F${s.slice(1)}.` : `Not filed: ${s}.`;
        }
        ctx.redraw();
      });
  });
  const stop = h('button', 'btn btn-quiet', 'Cancel');
  stop.type = 'button'; stop.dataset.act = 'plugin-file-cancel'; stop.disabled = p.busy;
  stop.addEventListener('click', () => { PLUGIN_PREVIEW.delete(k); ctx.redraw(); });
  const field = (label, el) => { const l = h('label', 'plugin-field', label); l.append(el); return l; };
  box.append(h('p', 'row-meta', `Read the title and the body, and change them as necessary. File the issue files them in ${p.repo} on GitHub.`),
    field('Title', p.title), field('Body', p.body));
  if (p.error) box.append(h('p', 'warn-note', p.error));
  box.append(send, stop);
  if (on) window.queueMicrotask(() => { if (on.isConnected) { on.focus({ preventScroll: true }); on.setSelectionRange(...caret); } });
  return box;
}
function pluginPane(bugs, ctx) {
  const h = ctx.h, key = (n) => `${n.file}\n${n.line}`;
  const all = bugs.flatMap((b) => (Array.isArray(b.notes) ? b.notes : [])
    .filter((n) => n && typeof n.line === 'string' && typeof n.text === 'string').map((n) => ({ ...n, file: b.file })));
  const now = new Set(all.map(key));
  PLUGIN_DISMISSED.forEach((k) => { if (!now.has(k)) PLUGIN_DISMISSED.delete(k); });
  PLUGIN_PREVIEW.forEach((p, k) => { if (!now.has(k) && !p.busy) PLUGIN_PREVIEW.delete(k); });
  const notes = all.filter((n) => !PLUGIN_DISMISSED.has(key(n)));
  if (!notes.length && !PLUGIN_FILED.length) return null;
  const pane = h('section', 'plugin-problems'), ul = h('ul', 'rows');
  notes.forEach((n) => {
    const li = h('li', 'row'), head = h('div', 'row-main'), meta = h('p', 'row-meta'), k = key(n);
    head.append(h('span', 'title', n.text));
    meta.append(h('span', null, n.at ? ctx.when(n.at) : 'time not noted'), h('span', null, n.card && n.card !== '-' ? `card ${n.card}` : 'no card'));
    const off = h('button', 'btn btn-quiet', 'Dismiss');
    off.type = 'button'; off.dataset.act = 'plugin-dismiss';
    off.addEventListener('click', () => {
      off.disabled = true;
      PLUGIN_FAILED.delete(k);
      ctx.post('plugin-dismiss', { file: n.file, line: n.line })
        .then((r) => r.text().then((t) => [r.ok, String(t).trim() || `the Board answered ${r.status}`]), () => [false, 'the Board did not answer'])
        .then(([ok, said]) => {
          if (ok) PLUGIN_DISMISSED.add(k); else PLUGIN_FAILED.set(k, `Not dismissed: ${said.replace(/\.$/, '')}.`);
          ctx.redraw();
        });
    });
    const file = h('button', 'btn btn-quiet', 'File on GitHub');
    file.type = 'button'; file.dataset.act = 'plugin-file-open'; file.disabled = PLUGIN_PREVIEW.has(k);
    file.addEventListener('click', () => {
      file.disabled = true;
      PLUGIN_FAILED.delete(k);
      ctx.post('plugin-preview', { file: n.file, line: n.line })
        .then((r) => r.text().then((t) => [r.ok, String(t).trim() || `the Board answered ${r.status}`]), () => [false, 'the Board did not answer'])
        .then(([ok, said]) => {
          let got = null;
          try { got = ok ? JSON.parse(said) : null; } catch (e) { said = 'the Board sent no issue to preview'; }
          if (got && typeof got.title === 'string' && typeof got.body === 'string' && typeof got.repo === 'string') {
            const title = h('input', 'plugin-title'), body = h('textarea', 'plugin-body');
            title.type = 'text'; title.value = got.title; body.rows = 8; body.value = got.body;
            PLUGIN_PREVIEW.set(k, { title, body, repo: got.repo, busy: false, error: null });
          } else PLUGIN_FAILED.set(k, `Not filed: ${(got ? 'the Board sent no issue to preview' : said).replace(/\.$/, '')}.`);
          ctx.redraw();
        });
    });
    // A note that names the issue it was filed as (the Foreman's own test) gets no File on GitHub: it is filed already.
    if (/[\s,;]filed as #[1-9][0-9]*\s*\.? · evidence: /i.test(n.line)) li.append(head, meta, off);
    else li.append(head, meta, file, off);
    if (PLUGIN_FAILED.has(k)) li.append(h('p', 'warn-note', PLUGIN_FAILED.get(k)));
    if (PLUGIN_PREVIEW.has(k)) li.append(pluginPreview(n, k, ctx));
    ul.append(li);
  });
  pane.append(h('h3', 'group-title', 'Plugin problems'),
    h('p', 'row-meta', 'The Foreman noted these problems in Conveyor. File on GitHub shows the issue first, and files it only when you click File the issue. Dismiss removes a note from its file. It does not file an issue.'));
  if (notes.length) pane.append(ul);
  if (PLUGIN_FILED.length) {
    const done = h('ul', 'plugin-filed');
    PLUGIN_FILED.forEach((f) => {
      const a = h('a', null, f.url);
      if (/^https:\/\/github\.com\/[^\s?#]+\/issues\/\d+$/.test(f.url)) { a.href = f.url; a.target = '_blank'; a.rel = 'noopener'; }
      const li = h('li', null, `Filed "${f.title}" as `);
      li.append(a);
      done.append(li);
    });
    pane.append(done);
  }
  return pane;
}
// Work now: what keeps the Conveyor host busy now, as the page server reads it (GET work: `conveyor.sh work` of each
// record): the busy processes by card and step, the heaviest first, a closed card's marked left over with the command
// that stops them, then the busy work no card owns. Read when the owner first opens it and on "Read again", never with
// the live feed; what was read, and whether it is open, are kept here through the panel's redraws.
const healthWork = { open: false, busy: false, data: null, error: null };
function healthWorkView(ctx) {
  const h = ctx.h, w = healthWork;
  const read = () => {
    if (w.busy) return;
    w.busy = true; w.error = null;
    ctx.redraw();
    window.fetch('work').then((r) => (r.ok ? r.json() : r.text().then((t) => Promise.reject(new Error(String(t).trim() || `the server answered ${r.status}`)))))
      .then((x) => { w.data = x && typeof x === 'object' ? x : null; }, (e) => { w.error = e && e.message ? e.message : 'no answer'; w.data = null; })
      .then(() => { w.busy = false; ctx.redraw(); });
  };
  const det = h('details', 'work-now');
  det.open = w.open;
  det.addEventListener('toggle', () => { w.open = det.open; if (det.open && !w.data && !w.error) read(); });
  det.append(h('summary', null, 'Work now'));
  const pct = (n) => `${Number(n) || 0}% of a core`;
  const procs = (list) => {
    const ul = h('ul', 'work-procs');
    (Array.isArray(list) ? list : []).forEach((x) => ul.append(h('li', null, `${pct(x.cpu)}  ${x.pid}  ${String(x.command || '')}`)));
    return ul;
  };
  if (w.busy) det.append(h('p', 'work-state', 'Reading what keeps the machine busy…'));
  else if (w.error) det.append(h('p', 'work-state', `The Board could not read the work now: ${w.error}`));
  else if (w.data) {
    const groups = Array.isArray(w.data.groups) ? w.data.groups : [], other = Array.isArray(w.data.other) ? w.data.other : [];
    if (!groups.length && !other.length) det.append(h('p', 'work-state', 'Nothing is busy.'));
    groups.forEach((g) => {
      const div = h('div', g.closed ? 'work-group work-left' : 'work-group');
      div.append(h('p', 'work-head', `Card ${g.issue ? `#${g.issue}` : g.card} (${g.project}), ${g.closed ? 'closed: left over' : `${g.step || 'unknown'} step`}: ${pct(g.cpu)}`), procs(g.processes));
      if (g.stop) { const p = h('p', 'work-stop', 'Stop them: '); p.append(h('code', null, g.stop)); div.append(p); }
      det.append(div);
    });
    if (other.length) { const div = h('div', 'work-group work-other'); div.append(h('p', 'work-head', 'No card owns'), procs(other)); det.append(div); }
  }
  const again = h('button', 'btn btn-quiet', 'Read again');
  again.type = 'button';
  again.disabled = w.busy;
  again.addEventListener('click', read);
  det.append(again);
  return det;
}
// A row's place: 0 a fault (its chip bad), 1 a warning, 2 fine (ok, quiet, or no chip).
function healthRank(dd) {
  const c = dd.querySelector(':scope > .chip');
  return c && c.classList.contains('chip-bad') ? 0 : c && c.classList.contains('chip-warn') ? 1 : 2;
}
// A text the build machine gives, in the Board's words: a wait in seconds ("retry after 1022 s", dashboard_limit.py) is
// "try again in 17 min"; a failed fetch of main names GitHub, not git's remote branch.
function healthWaits(text, ctx) {
  return text.replace(/\bretry after ([0-9]+) s\b/g, (m, n) => `try again in ${ctx.dur(Number(n))}`)
    .replace(/\brate limited \(429\)/g, 'the usage server asked for a pause')
    .replace(/^origin\/main could not be fetched: /, 'the Board could not get main from GitHub: ');
}
// An error from the host as {line, raw}: line is a short plain sentence that says what failed, the words before the
// first ": " of its first line when they are more than one and fit HEALTH_LINE ("the Board could not get main from
// GitHub: fatal: …" is "The Board could not get main from GitHub."), else that line in the Board's words (healthWaits),
// cut to HEALTH_LINE. raw is the text as the host gave it, for a closed "Raw error" (with its Copy output) under the
// sentence, also when the sentence says all of it. null for no text.
function healthError(text, ctx) {
  if (typeof text !== 'string' || !text.trim()) return null;
  const raw = text.trim(), t = healthWaits(raw, ctx), first = t.split('\n')[0], cut = first.indexOf(': '), head = cut > 0 ? first.slice(0, cut).trim() : '';
  const line = /\s/.test(head) && head.length < HEALTH_LINE ? `${head[0].toUpperCase()}${head.slice(1)}.`
    : first.length > HEALTH_LINE ? `${first.slice(0, HEALTH_LINE - 1)}…` : first;
  return { line, raw };
}
// The live feed rewrites the stream (writtenAt) every 10 s while it runs, and builds data.js again with each change, or
// after 45 s with none (dashboard_stream.py KEEP), so data.js and this page's feed carry a write at most about 60 s old:
// a stream not written to for STREAM_EXPIRE_MS is one whose feed has stopped, whatever its last word said.
const STREAM_EXPIRE_MS = 90000;
// The Data row's chip and detail, drawn into dd: Live while Conveyor's stream from the host is live, its feed still
// writes, and this page's own feed is open; otherwise its age, counting each second: from when the host was last heard
// from, or, with the stream up and this page reading data.js every 15 s, from when data.js was published. Its age
// carries its next step.
function dataRow(dd, s, ctx) {
  const h = ctx.h;
  const f = typeof ctx.feed === 'function' ? ctx.feed() : { open: false, updatedAt: null };
  const written = typeof s.writtenAt === 'string' ? Date.parse(s.writtenAt) : NaN;
  const until = Number.isNaN(written) ? 0 : written + STREAM_EXPIRE_MS;
  const live = !!s.live && Date.now() <= until;
  dd.stream = s;
  delete dd.dataset.liveUntil;
  if (live && f.open) {
    dd.dataset.liveUntil = String(until);
    dd.replaceChildren(ctx.chip('Live', 'ok'), h('span', 'detail', 'each change as it happens'), ...(dd.restart ? [dd.restart] : []));
    return;
  }
  if (live) dd.dataset.liveUntil = String(until);
  const from = live ? (typeof f.updatedAt === 'number' ? new Date(f.updatedAt).toISOString() : null) : s.heardAt;
  const c = ctx.chip(healthAge(from, ctx), 'warn');
  if (typeof from === 'string') c.lastChild.dataset.ageFrom = from;
  // The stream's own error is one line from the host: its sentence, and the raw line under "Raw error" (healthError).
  const e = live || s.live ? null : healthError(s.error, ctx);
  // The build machine is named only when one is set up (ctx.machine, #112).
  const remote = ctx.machine === 'the build machine';
  const why = live ? `this page asks ${remote ? 'the build machine' : 'the Board'} for news every 15 s`
    : s.live ? 'the live feed stopped' : e ? e.line : 'the live stream is down';
  const next = live ? 'Reload the page to open its live feed again.'
    : `Reload the page. If the data stays old, ${remote ? 'make sure that the build machine is on. Then press' : 'press'} Restart the Board's feed, below.`;
  const raw = e ? ctx.output(e.raw, null, 'Raw error', dd.querySelector(':scope > details.output')) : null;
  dd.replaceChildren(c, h('span', 'detail', healthWaits(why, ctx)), h('p', 'check-next', `Next: ${next}`), ...(dd.restart ? [dd.restart] : []), ...(raw ? [raw] : []));
}
// "N s old" (minutes and hours past two minutes); "Age unknown" with no time to count from.
function healthAge(iso, ctx) {
  const t = typeof iso === 'string' ? Date.parse(iso) : NaN;
  if (Number.isNaN(t)) return 'Age unknown';
  const sec = Math.max(0, Math.floor((Date.now() - t) / 1000));
  return sec < 120 ? `${sec} s old` : `${ctx.dur(sec)} old`;
}
