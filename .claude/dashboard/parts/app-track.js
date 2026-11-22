// SPDX-License-Identifier: Apache-2.0
// A card's step track (Build, Review, Fix, Test, Land, Push), every step on one time axis, why a blocked card
// stopped, and the items not shown before in this browser. Part of app.js, which hands it `app` (its names, and its
// state through getters and setters) as it loads (DASH_APP.core); boot.js loads it before the panels.
(() => {
  'use strict';
  // What this part uses of app.js and of its other parts, each bound as it loads (app.bind, at the end).
  let app, SEEN_KEY, STEP_NAMES, chip, clock, codeEl, doc, fill, findings, form, h, judged, list, now, num, output, parse,
    pathsIn, proofAt, repoOf, since, tip, took, verdictSaid, when;
  const bindNames = () => ({ SEEN_KEY, STEP_NAMES, chip, clock, codeEl, doc, fill, findings, form, h, judged, list, now, num,
    output, parse, pathsIn, proofAt, repoOf, since, tip, took, verdictSaid, when } = app);
  const STEP_WORD = { done: 'done', now: 'in progress', skipped: 'skipped', failed: 'failed', todo: 'to come' };
  const STEP_MARK = { done: '✓', now: '▶', skipped: '–', failed: '✗', todo: '·' };
  const sixOf = (t) => (t && Array.isArray(t.steps) && t.steps.length === 6 && t.steps.every((s, i) => s && s.name === STEP_NAMES[i] && STEP_WORD[s.state]) ? t : null);
  // "Review 2 of 3", "Fix 2": a step that ran more than once, or the round in progress. Tests that passed only when the
  // cases that had not passed ran again: "Test passed on re-run", never a plain success. A fix the Done-when check on
  // the build's reply started is Build's (track.jq replyFix), never Fix: "Build · reply check fix" while it runs. So is
  // the review gate's lint fix after the build (lintFix): "Build · lint fix"; after a fix round it is "Fix 2: lint
  // findings", as the landing gate's is; after a rebuild, "Land · lint fix".
  function stepName(s) {
    const n = num(s.n) ? s.n : 0;
    const build = buildFixName(s);
    if (build) return build;
    if (s.name === 'Test' && s.rerun === true && s.state === 'done') return 'Test passed on re-run';
    if (s.name === 'Review' && n >= 1 && (n > 1 || s.state === 'now')) return `Review ${n}${num(s.of) && n <= s.of ? ` of ${s.of}` : ''}`;
    return fixName(s, n) || s.name;
  }
  // Build step s's name in its reply check fix or lint fix, or after it; null for another step or state.
  function buildFixName(s) {
    if (s.name !== 'Build') return null;
    if (s.replyFix === 'now' && s.state === 'now') return 'Build · reply check fix';
    if (s.replyFix === 'done' && s.state === 'done') return 'Build · reply check fixed';
    if (s.lintFix === 'now' && s.state === 'now') return 'Build · lint fix';
    if (s.lintFix === 'done' && s.state === 'done') return 'Build · lint fixed';
    return null;
  }
  // Fix or Land step s's name, with its round n; null for another step, or for one that keeps its own name.
  function fixName(s, n) {
    const lint = s.lintFix === 'now' && s.state === 'now';
    if (s.name === 'Fix' && lint) return `Fix ${Math.max(n, 1)}: lint findings`;
    if (s.name === 'Land' && lint) return 'Land · lint fix';
    if (s.name === 'Fix' && n >= 1 && (n > 1 || s.state === 'now')) return `Fix ${n}`;
    return null;
  }
  // A test step's time is its runs' wait for a test slot and their run, apart, when its records give them.
  const testTime = (s) => (num(s.wait) && num(s.run) ? `wait ${took(s.wait)} · run ${took(s.run)}` : null);
  function stepTime(s, t) {
    if (s.state === 'now') return since(t.since, '');
    if (s.state === 'skipped') return h('span', null, 'skipped');
    if ((s.state === 'done' || s.state === 'failed') && (testTime(s) || num(s.sec))) return h('span', null, testTime(s) || took(s.sec));
    return null;
  }
  // Fills `ol` (kept from one refresh to the next, each step the same node) with the six steps of track t; false when
  // t is not a six-step track.
  function track(ol, t) {
    const six = sixOf(t);
    if (!six) { ol.replaceChildren(); return false; }
    list(ol, six.steps.map((s, i) => ({ s, i })), (x) => x.i, () => {
      const li = h('li', 'step6'), box = h('span', 'step-chip'), mark = h('span', 'step-mark');
      mark.setAttribute('aria-hidden', 'true');
      box.append(mark, h('span', 'step-name'), h('span', 'step-time'));
      li.append(h('span', 'join'), box);
      return li;
    }, (li, x) => {
      const s = x.s, join = li.children[0], [mark, name, time] = li.children[1].children, label = stepName(s);
      li.dataset.state = s.state;
      join.hidden = x.i === 0;
      join.setAttribute('aria-hidden', 'true');
      join.dataset.filled = String(s.state !== 'todo');
      mark.textContent = STEP_MARK[s.state];
      name.textContent = label;
      const tm = stepTime(s, six);
      time.replaceChildren(...(tm ? [tm] : []));
      const extra = x.i === 5 && num(s.followups) && s.followups > 0 ? `, ${s.followups} follow-up${s.followups === 1 ? '' : 's'} filed` : '';
      const why = s.state === 'failed' && x.i === 5 && six.reason ? `: ${six.reason}` : '';
      const said = `${label}: ${STEP_WORD[s.state]}${s.state === 'done' && testTime(s) ? `, ${testTime(s)}` : s.state === 'done' && num(s.sec) ? `, took ${took(s.sec)}` : ''}${why}${extra}`;
      li.setAttribute('aria-label', said);
      tip(li, said);
      if (s.state === 'now') li.setAttribute('aria-current', 'step'); else li.removeAttribute('aria-current');
    });
    const at = num(six.at) ? six.at : -1;
    ol.setAttribute('aria-label', at >= 0 ? `Steps: ${stepName(six.steps[at])}, step ${at + 1} of 6` : 'Steps of this card');
    return true;
  }
  // What a failed test run says went wrong (the record's failures: {of, files: [{file, cases: [{name, line}]}],
  // timeout: null | {sec, file}}): one line that sums it up ("2 of 41 test files failed", or that it timed out and in
  // which file), then a row a failing file with its failing cases, each on a line of its own with its first failure
  // line. Never a passing file or case. null when the record names no failing file and no timeout. brief: the line that
  // sums it up, then only the first failing file with its first failing case (Needs you, failureShort).
  function testFails(f, brief) {
    if (!f || typeof f !== 'object') return null;
    const files = (Array.isArray(f.files) ? f.files : []).filter((x) => x && typeof x.file === 'string' && Array.isArray(x.cases));
    const t = f.timeout && typeof f.timeout === 'object' ? f.timeout : null;
    if (!files.length && !t) return null;
    const failed = `${files.length}${num(f.of) ? ` of ${f.of}` : ''} test ${(num(f.of) ? f.of : files.length) === 1 ? 'file' : 'files'} failed`;
    const timed = t ? `Timed out${num(t.sec) ? ` after ${t.sec < 60 ? took(t.sec) : `${Math.round(t.sec / 60)} min`}` : ''}${typeof t.file === 'string' && t.file ? ` in ${t.file}` : ''}` : '';
    const box = h('div', 'test-fails'), rows = h('ul', 'test-files');
    box.append(h('p', 'test-sum', t ? timed + (files.length ? ` · ${failed}` : '') : failed));
    (brief ? files.slice(0, 1) : files).forEach((x) => {
      const row = h('li', 'test-file'), cases = h('ul', 'test-cases');
      x.cases.filter((c) => c && typeof c.name === 'string').slice(0, brief ? 1 : Infinity).forEach((c) => {
        const line = typeof c.line === 'string' ? c.line : '', own = `FAIL [${c.name}]: `;
        const li = h('li', 'test-case');
        li.append(h('span', 'test-case-name', c.name), h('span', 'test-case-line', line.startsWith(own) ? line.slice(own.length) : line));
        cases.append(li);
      });
      row.append(h('span', 'test-file-name', x.file || 'Test file not named'), cases);
      rows.append(row);
    });
    if (files.length) box.append(rows);
    return box;
  }
  // A lint command's short name for its row: the script's file name (`bash .conveyor/lint-shell.sh {files}` is
  // lint-shell.sh), the size check as "Size, limit 800 lines", and for an inline command its first program after a
  // `command -v <tool> ... || { ...; }` or `[ -x <tool> ] || { ...; }` guard (ruff, eslint). The whole command is on the name's hover and focus.
  function lintName(run) {
    if (/^size, limit \d+ lines$/.test(run)) return `Size${run.slice(4)}`;
    const words = run.replace(/^(?:command -v \S+|\[ [^\]]*\])[^{]*\|\|\s*\{[^}]*\}\s*;\s*/, '').split(/\s+/).filter(Boolean);
    const lead = words[0] ? words[0].split('/').pop() : '';
    const arg = /^(bash|sh|python3?|node)$/.test(lead) ? words.slice(1).find((w) => !w.startsWith('-')) : null;
    return (arg ? arg.split('/').pop() : lead) || run;
  }
  const LINT_RESULT = { pass: ['Pass', 'ok'], 'no files': ['No files', 'quiet'], error: ['Error', 'bad'] };
  // A lint step's commands (the record's lint: [{n, run, result, sec, findings, reported: [{file, line, text}]}]): a
  // small table, a row a command with its short name, a chip for its result and its seconds, and under a row with
  // findings of this change what they are, as testFails() lists a failed run's cases. A command with findings of this
  // change (a count above 0) or an error comes first. step and mine: the step's key and the card's drawn timeline, to keep
  // a "Show command" open through a redraw. The whole command is on the name's hover and focus, and under "Show command" for a touch screen.
  // null when the record has no command, and the step shows its reason.
  function lintRows(cmds, step, mine) {
    const ran = (Array.isArray(cmds) ? cmds : []).filter((c) => c && typeof c === 'object' && typeof c.run === 'string' && typeof c.result === 'string');
    if (!ran.length) return null;
    const failed = (c) => c.result === 'error' || (c.result === 'findings' && num(c.findings) && c.findings > 0);
    const table = h('table', 'lint-cmds'), body = h('tbody');
    ran.filter(failed).concat(ran.filter((c) => !failed(c))).forEach((c) => {
      const key = `${step}:${c.n}`;
      const old = mine ? Array.from(mine.querySelectorAll('details.lint-cmd-show')).find((x) => x.dataset.cmd === key) : null;
      const row = h('tr', 'lint-cmd'), name = h('td', 'lint-cmd-name'), word = h('span', 'lint-cmd-word', lintName(c.run));
      word.tabIndex = 0;
      tip(word, c.run);
      const show = h('details', 'lint-cmd-show');
      show.dataset.cmd = key;
      show.open = Boolean(old && old.open);
      show.append(h('summary', null, 'Show command'), h('code', null, c.run));
      name.append(word, show);
      const skipped = c.result.startsWith('skipped: ');
      const res = c.result === 'findings' ? [`Findings: ${num(c.findings) ? c.findings : 0} of this change`, 'bad']
        : LINT_RESULT[c.result] || (skipped ? [`Skipped: ${c.result.slice(9)}`, 'warn'] : [c.result, 'quiet']);
      const result = h('td', 'lint-cmd-result');
      result.append(chip(res[0], res[1]));
      row.append(name, result, h('td', 'lint-cmd-sec', num(c.sec) ? took(c.sec) : ''));
      body.append(row);
      const found = (Array.isArray(c.reported) ? c.reported : []).filter((f) => f && typeof f.text === 'string');
      if (c.result === 'error' && typeof c.why === 'string' && c.why) found.push({ text: c.why });
      if (!found.length) return;
      const more = h('td'), items = h('ul', 'lint-found');
      more.colSpan = 3;
      found.forEach((f) => {
        const li = h('li', 'lint-finding');
        const at = `${typeof f.file === 'string' ? f.file : ''}${num(f.line) ? `:${f.line}` : ''}`;
        if (at) li.append(h('span', 'lint-finding-at', at));
        li.append(h('span', 'lint-finding-text', f.text));
        items.append(li);
      });
      more.append(items);
      const under = h('tr', 'lint-found-row');
      under.append(more);
      body.append(under);
    });
    table.append(body);
    return table;
  }
  // The changed lines no test reached in a test run, from the coverage report its command wrote (the record's
  // coverage: {uncovered: [{file, lines}], count, checked} or {unknown: why}): one line that sums it up, then a row a
  // file with its lines. A lead for the reviewer, never a failure. null when the record has no coverage.
  function testCoverage(c) {
    if (!c || typeof c !== 'object') return null;
    const box = h('div', 'test-coverage');
    if (typeof c.unknown === 'string') { box.append(h('p', 'test-sum', `Changed lines no test reached: unknown${c.unknown ? ` (${c.unknown})` : ''}`)); return box; }
    if (!num(c.count) || !num(c.checked)) return null;
    box.append(h('p', 'test-sum', `Changed lines no test reached: ${c.count ? c.count : 'none'} of ${c.checked}`));
    const files = (Array.isArray(c.uncovered) ? c.uncovered : []).filter((x) => x && typeof x.file === 'string' && typeof x.lines === 'string');
    if (files.length) {
      const rows = h('ul', 'test-files');
      files.forEach((x) => rows.append(h('li', 'test-file', `${x.file}: ${/[-,]/.test(x.lines) ? 'lines' : 'line'} ${x.lines}`)));
      box.append(rows);
    }
    return box;
  }
  // Every recorded step, on demand, as a timeline: one bar a step on one time axis, from the card's pick-up to now (or
  // to its end), each as long as the step ran, with its time on it. The time the issue waited in the queue is said
  // apart, so a long wait squashes no bar. The set-up (picked, worktree, dependencies, brief) is one bar that opens
  // to its parts; a review has its verdict, its findings and what the judge made of it; a failed step is red, with its reason on hover or focus; the
  // clock times are on hover or focus too, and in each item's text for a screen reader. The step in progress beats
  // (belt.js). A bar is placed by its clock times, so a pause between two steps (a restarted review waiting for its
  // turn) is a gap on the axis; from a snapshot with no times the bars follow one another.
  // card: the card's id, so the output a step keeps shows its worktree as ./.
  const SETUP = /^(picked|worktree ready|dependencies linked|brief written|making the worktree|linking dependencies|writing the brief)$/;
  const BAR_NAME = { building: 'Build', landing: 'Land', pushed: 'Push', push: 'Push', 'push failed': 'Push', 'tests passed': 'Tests', 'tests failed': 'Tests' };
  // What started a fix session, as its bar in "Every step" and the card's step pill name it ("Fix 3: main changed under it"): its
  // line's reason when it names one (a failed Done-when check on the reply, main moved, lint findings), else the step
  // before it (a NO-GO review's findings, a failed test run). The fix in progress has no line yet, so it is named only
  // where the step before it leaves one cause: failed tests; a lint line (lint findings, at either lint gate); a build,
  // rebuild or fix whose Done-when check failed (checkFailed: the check on its reply); tests that passed (main moved).
  // After a review it may be the findings, the commit trailers or main having moved (a GO, or a last NO-GO, still
  // lands), and after a session whose reply passed its check the project's checks (checked(), donewhen.sh) or main
  // moved: "Fix N" alone until its line says. all: the card's recorded steps; i: the place of one in it. null when it
  // is no fix; why is the reason, on hover.
  const FIX_CAUSE = [[/^the Done-when check failed/, 'reply check'], [/^main moved/, 'main moved'], [/^lint: /, 'lint findings']];
  // A cause as the fix's name spells it: "Fix 3: main changed under it", never the record's short "main moved".
  const FIX_NAME = { 'main moved': 'main changed under it' };
  const FIX_SAID = { 'review findings': "a NO-GO review's findings", 'tests failed': 'the changed tests failed', 'reply check': 'the Done-when check on the reply failed', 'lint findings': 'the lint commands found findings in the change',
    'main moved': 'main moved after the card made its change, and the change no longer applied to it' };
  // A fix line's lint gate, when a lint line with findings (which names its gate) started it; else null.
  const gateOf = (all, k) => (k > 0 && all[k - 1].name === 'lint' && /^lint: /.test(all[k].reason || '') ? all[k - 1].gate || null : null);
  // The Fix rounds before record i, and the step of the session before it (Build, Fix or Land), as track.jq counts them
  // for the six steps: a fix the review gate's lint or the Done-when check on a reply started is no round of its own.
  function roundsTo(all, i) {
    let last = 'Build', rounds = 0;
    all.slice(0, i).forEach((x, k) => {
      if (x.name === 'building') last = 'Build';
      else if (x.name === 'rebuild') last = 'Land';
      else if (/^fix \d+$/.test(x.name) && gateOf(all, k) !== 'review' && !/^the Done-when check failed/.test(x.reason || '')) { rounds += 1; last = 'Fix'; }
    });
    return { rounds, last };
  }
  // A fix is numbered by its Fix round, as the strip numbers it, so a fix and the review gate's lint fix after it share a
  // number; the landing gate's lint fix is a new round (track.jq). A fix that is
  // no round keeps the name the six steps give it (track.jq): the step of the session before it ("Build · lint fix",
  // "Fix 2: lint findings", "Land · reply check fix").
  function fixOf(all, i) {
    const s = all[i], m = /^fix (\d+)$/.exec(s.name), running = s.state === 'now' && /^fix\b/.test(s.name);
    if (!m && !running) return null;
    const said = (x) => (typeof x.reason === 'string' ? x.reason : '');
    const reason = said(s), p = i > 0 ? all[i - 1] : { name: '' }, prev = p.name;
    const cause = fixCause(reason, p, running);
    const why = reason || (cause ? FIX_SAID[cause] : ''), { rounds, last } = roundsTo(all, i);
    const gate = m ? gateOf(all, i) : prev === 'lint' ? p.gate || null : null;
    if (gate === 'review' || cause === 'reply check') {
      return { name: last === 'Fix' ? `Fix ${rounds}: ${cause}` : `${last} · ${gate === 'review' ? 'lint fix' : 'reply check fix'}`, why };
    }
    return { name: `Fix ${rounds + 1}${cause ? `: ${FIX_NAME[cause] || cause}` : ''}`, why };
  }
  // What started a fix (fixOf), from its line's reason, else from the step before it (p); null when neither says. A
  // fix that is running has no line yet: only the step before it says.
  function fixCause(reason, p, running) {
    const prev = p.name, causeOf = (r) => (FIX_CAUSE.find(([re]) => re.test(r)) || [])[1] || null;
    if (!running) return causeOf(reason) || (reason ? null : prev === 'tests failed' ? 'tests failed' : /^review \d+ \(NO-GO\)$/.test(prev) ? 'review findings' : null);
    return p.checkFailed === true ? 'reply check' : prev === 'tests failed' ? 'tests failed' : prev === 'lint' ? 'lint findings' : prev === 'tests passed' ? 'main moved' : null;
  }
  // records: one per recorded line, each with its own seconds; detail (17 summed slots) from a snapshot without them.
  const stepsOf = (t) => (t && Array.isArray(t.records) ? t.records : t && Array.isArray(t.detail) ? t.detail : []).filter((s) => s && typeof s.name === 'string' && STEP_WORD[s.state]);
  // The fix in progress of track t, as fixOf names it; null when the card is in no fix or its steps were not given. The
  // review gate's lint fix after the build is Build's, after a rebuild Land's (track.jq lintFix), as the six steps name it.
  // A lint fix on Fix (the review gate's after a fix round, the landing gate's) is named as the strip names it.
  function fixNow(t) {
    const six = sixOf(t);
    if (six && six.steps[0].lintFix === 'now' && six.steps[0].state === 'now') return { name: 'Build · lint fix', why: FIX_SAID['lint findings'] };
    if (six && six.steps[2].lintFix === 'now' && six.steps[2].state === 'now') return { name: stepName(six.steps[2]), why: FIX_SAID['lint findings'] };
    if (six && six.steps[4].lintFix === 'now' && six.steps[4].state === 'now') return { name: 'Land · lint fix', why: FIX_SAID['lint findings'] };
    const all = stepsOf(t), i = all.length - 1;
    return i >= 0 && all[i].state === 'now' ? fixOf(all, i) : null;
  }
  // A bar's parts and what they say (a filing its count of follow-ups); its times are worked out as it is placed.
  function barOf(parts) {
    const states = parts.map((s) => s.state), last = parts[parts.length - 1];
    const state = ['failed', 'now', 'done'].find((x) => states.includes(x)) || (states.includes('todo') ? 'todo' : 'skipped');
    const review = /^review (\d+)(?: \((.+)\))?$/.exec(last.name), n = parts.map((s) => s.n).find(num);
    const name = (parts.length > 1 || SETUP.test(last.name) ? 'Setup' : review ? `Review ${review[1]}`
      : BAR_NAME[last.name] || last.name.charAt(0).toUpperCase() + last.name.slice(1)) + (num(n) ? ` (${n})` : '');
    const why = parts.map((s) => s.why).find((w) => typeof w === 'string' && w) || '';
    return { parts, state, name, verdict: review ? review[2] || null : null, counts: review ? last.counts : null, judge: review ? last.judge : null, why };
  }
  // A running test run's progress, from its track: its cases ("142 of 205 tests · 2 failed") when its command gave a
  // count (tests), else its files ("3 of 6 test files"); null when the track has neither (no test run in progress).
  // Before it, the list of tests the run was given (the track's list) and how its tests were found: "changed: 7 files
  // (map) · 3 test files" (3 of them ran), "changed: 7 files (by name)", or "whole suite: <why> · ..."; with the made
  // test map's age, "· map 12 commits old".
  function testProgress(t) {
    const c = t && t.tests && typeof t.tests === 'object' ? t.tests : null, f = t && t.files && typeof t.files === 'object' ? t.files : null;
    const l = t && t.list && typeof t.list === 'object' ? t.list : null;
    const mode = listSaid(l), prog = runSaid(c, f);
    return mode && prog ? `${mode} · ${prog}` : mode || prog;
  }
  // How a test run's tests were found (testProgress), from its list l; null with no list.
  function listSaid(l) {
    if (!l) return null;
    const by = l.by === 'map' ? ' (map)' : l.by === 'name' ? ' (by name)' : '';
    const age = num(l.age) ? ` · map ${l.age} ${l.age === 1 ? 'commit' : 'commits'} old` : '';
    return l.mode === 'changed' && num(l.files) ? `changed: ${l.files} ${l.files === 1 ? 'file' : 'files'}${by}${age}`
      : l.mode === 'whole' ? `whole suite${typeof l.why === 'string' && l.why ? `: ${l.why}` : ''}` : null;
  }
  // How far a test run has got (testProgress), from its cases c or else its files f; null when neither says.
  function runSaid(c, f) {
    if (c && num(c.done) && num(c.of)) return `${c.done} of ${c.of} tests${num(c.failed) && c.failed > 0 ? ` · ${c.failed} failed` : ''}`;
    if (!f || !num(f.run)) return null;
    let prog = `${f.run}${num(f.of) ? ` of ${f.of}` : ''} test ${(num(f.of) ? f.of : f.run) === 1 ? 'file' : 'files'}`;
    // A run that ran more test files than it selected (over) says so apart, never as "N of M" with N above M.
    if (num(f.over) && f.over > 0) prog += ` · ${f.over} more ${f.over === 1 ? 'file' : 'files'} than selected`;
    return prog;
  }
  // was: the timeline this one replaces, if any: whether it and its set-up were open is kept. A timeline with a step in
  // progress has retime(), which sets that step's bar's width and the time texts again as its time grows (belt.js, each
  // second), and changes nothing else. data-card names the card, so a panel that draws its rows anew finds was.
  // A card's overall time with earlier attempts (the snapshot's earlier) says on hover that it includes them.
  function earlierTip(el, earlier) {
    const n = Array.isArray(earlier) ? earlier.length : 0;
    if (n) tip(el, `Includes ${n === 1 ? 'the earlier attempt' : `the ${n} earlier attempts`}: "Every step" shows ${n === 1 ? 'its' : 'their'} steps`);
    return el;
  }
  // earlier: the earlier cards of the same work (the snapshot's earlier, the first first), each above the steps as one
  // closed line, "Earlier attempt: <start> to <end>, <time>, ended: <reason>", opening to its own steps: the card's
  // overall time counts their seconds, so the steps it is made of are all here.
  // repoUrl: the card's repository (repoOf), in which its review findings' file paths link to their lines; repo: its
  // record, whose findings' places open the lines the review read (output).
  function trackDetail(t, card, was, earlier, repoUrl, repo) {
    const det = h('details', 'track-detail'), sum = h('summary', null, 'Every step');
    if (typeof card === 'string') det.dataset.card = card;
    const total = h('p', 'tl-total'), ol = h('ol', 'timeline');
    // What was drawn before of this card's own steps, never of an earlier attempt's inside it. was may be the
    // "Every step" of an earlier card id (a retry, panels/belt.js): its own steps are one of this card's earlier
    // attempts now, which keeps their open output boxes, and this card's steps take nothing from it.
    const mine = was && was.dataset.card === card ? was.querySelector(':scope > ol.timeline') : null;
    const before = earlierLines(was, earlier, repoUrl, repo);
    const all = stepsOf(t);
    const { bars, wait } = barsOf(t, all);
    bars.forEach((b) => ol.append(barItem(b, { t, card, mine, all, repoUrl, repo })));
    placeBars(det, total, bars, t, wait);
    ol.setAttribute('aria-label', 'Every step, in order, on one time axis');
    det.append(sum, ...before, total, ol);
    det.hidden = !ol.children.length && !before.length;
    det.open = Boolean(was && was.open);
    det.dataset.form = form();
    det.redraw = () => trackDetail(t, card, det, earlier, repoUrl, repo);
    return det;
  }
  // The closed lines of the earlier attempts (trackDetail's earlier), each one's own "Every step" drawn over the one
  // was had for it.
  function earlierLines(was, earlier, repoUrl, repo) {
    return (Array.isArray(earlier) ? earlier : []).filter((e) => e && typeof e === 'object' && e.track && typeof e.track === 'object').map((e) => {
      const prior = Boolean(was && was.dataset.card === e.card);
      const old = prior ? was : was ? Array.from(was.querySelectorAll(':scope > details.tl-earlier')).find((x) => x.dataset.card === e.card) : null;
      const d = trackDetail(e.track, e.card, old, null, repoUrl, repo);
      // The earlier card's "Every step" was the whole box, never this line: the line starts closed.
      if (prior) d.open = false;
      d.classList.add('tl-earlier');
      d.hidden = false;
      d.firstChild.textContent = `Earlier attempt: ${when(e.start)} to ${when(e.end)}, ${num(e.sec) ? took(e.sec) : 'time not read'}, ended: ${typeof e.reason === 'string' && e.reason ? e.reason : 'no reason recorded'}`;
      return d;
    });
  }
  // The bars of track t (all: its steps), one a step and one for the set-up steps together, and the queue's wait.
  function barsOf(t, all) {
    let wait = null;
    const groups = [];
    all.forEach((s) => {
      if (s.name === 'queued') { if (num(s.sec)) wait = s.sec; return; }
      const prev = groups[groups.length - 1];
      if (SETUP.test(s.name) && prev && SETUP.test(prev[0].name)) prev.push(s); else groups.push([s]);
    });
    // A fix is named by what started it, its reason on hover and on a tap; the one in progress as the pill names it (fixNow).
    const bars = groups.map((g) => { const b = barOf(g), i = all.indexOf(g[0]), f = g.length !== 1 ? null : i === all.length - 1 && g[0].state === 'now' ? fixNow(t) : fixOf(all, i); return f ? Object.assign(b, { name: f.name, said: f.why }) : b; });
    return { bars, wait };
  }
  // The line of bar b in "Every step": its label, its lane on the time axis and what its steps say. at: the track (t),
  // the card, the timeline drawn before (mine), the steps (all), and the repository for the findings (repoUrl, repo).
  function barItem(b, at) {
    const li = h('li', 'tl-item'), label = h('span', 'tl-label', b.name), lane = h('span', 'tl-lane'), bar = h('span', 'tl-bar');
    if (b.said) tip(label, b.said);
    li.dataset.state = b.state;
    li.tabIndex = 0;
    if (b.state === 'now') li.setAttribute('aria-current', 'step');
    if (b.verdict) label.append(chip(verdictSaid(b.verdict), b.verdict === 'GO' ? 'ok' : 'warn'));
    if (b.parts.some((s) => s.rerun === true)) label.append(chip('passed on re-run', 'warn'));
    const f = findings({ counts: b.counts });
    if (f) label.append(h('span', 'tl-findings', f));
    // What the judge made of the review, its declined count opening the card's lines in the Declined panel.
    const jd = judged(b, at.card);
    if (jd) label.append(jd);
    lane.setAttribute('aria-hidden', 'true');
    lane.append(bar);
    Object.assign(b, { lane, bar, dur: h('span', 'tl-dur'), tip: h('span', 'tl-tip') });
    li.append(label, lane, b.tip);
    // The test run in progress says how far it has got.
    const prog = b.state === 'now' ? testProgress(at.t) : null;
    if (prog) li.append(h('p', 'tl-tests', prog));
    // The set-up opens to the steps it folds.
    if (b.name === 'Setup') {
      const parts = h('details', 'tl-parts'), inner = h('ol', null);
      parts.append(h('summary', null, `${b.parts.length} ${b.parts.length === 1 ? 'step' : 'steps'}`), inner);
      inner.append(...b.parts.map((s) => h('li', `detail-${s.state}`, `${s.name}: ${STEP_WORD[s.state]}${num(s.sec) ? `, ${took(s.sec)}` : ''}`)));
      parts.open = Boolean(at.mine && at.mine.querySelector('.tl-parts[open]'));
      li.append(parts);
    }
    b.parts.forEach((s) => li.append(...stepSaid(b, s, at)));
    return li;
  }
  // What step s of bar b says under the bar. A blocked step's sentence and the output it failed on, and a NO-GO review's
  // findings, as Needs you shows them. A lint step with its commands shows a row for each in place of its reason
  // (lintRows). A failed test run shows its failing files and cases in place of its reason, and
  // its output under "Show full output". Its output stays open through a redraw: the toggle it replaces is the one of
  // the same step (its place among the card's steps, which only grow at the end, and its name).
  function stepSaid(b, s, at) {
    const els = [];
    const fails = testFails(s.failures);
    // Its bar's words on hover or focus say the same line, not the exit code.
    const step = `${at.all.indexOf(s)}:${s.name}`;
    const lint = lintRows(s.lint, step, at.mine);
    if (fails) { els.push(fails); b.why = fails.firstChild.textContent; }
    else if (lint) {
      els.push(lint);
      // The rows say each command's result: the one note of the reason they do not is kept (lintline(), lib/lint.sh).
      if (/(^|; )tools ran as installed(;|$)/.test(s.why || '')) els.push(h('p', 'detail-why', 'Tools ran as installed'));
    }
    else if (typeof s.why === 'string' && s.why) els.push(h('p', 'detail-why', s.why));
    const cov = testCoverage(s.coverage);
    if (cov) els.push(cov);
    const old = at.mine ? Array.from(at.mine.querySelectorAll('details.output')).find((x) => x.dataset.step === step) : null;
    const out = output(s.output, at.card, s.name === 'tests failed' ? 'Show full output' : null, old, at.repoUrl, at.repo, /^review \d/.test(s.name) ? s.at : null);
    if (out) { out.dataset.step = step; els.push(out); }
    return els;
  }
  const barRunning = (b) => b.parts[b.parts.length - 1].state === 'now';
  // Bar b's seconds, start and end (b.secs, b.start, b.end); the step in progress of track t counts to now.
  function measureBar(b, t) {
    const sec = (s) => (s.state === 'now' ? Math.max(0, (now() - (parse(t.since) ?? now())) / 1000) : num(s.sec) ? Math.max(0, s.sec) : 0);
    b.secs = b.parts.reduce((a, s) => a + sec(s), 0);
    b.end = barRunning(b) ? now() : parse(b.parts[b.parts.length - 1].at);
    b.start = b.end === null ? null : b.end - b.secs * 1000;
  }
  // The time beside a bar sits after it, or before it near the axis's end; on the bar it needs no place.
  function besideBar(b) {
    b.dur.style.left = '';
    b.dur.style.right = '';
    delete b.dur.dataset.side;
    if (b.dur.parentNode !== b.lane) return;
    if (b.left + b.width <= 70) b.dur.style.left = `${(b.left + b.width).toFixed(2)}%`;
    else { b.dur.style.right = `${(100 - b.left).toFixed(2)}%`; b.dur.dataset.side = 'before'; }
  }
  // Bar b's time and its words on hover.
  function barWords(b) {
    const time = b.state === 'todo' || b.state === 'skipped' ? STEP_WORD[b.state] : took(b.secs);
    b.dur.textContent = time;
    const clocks = b.start !== null && b.end !== null ? `, ${clock(new Date(b.start).toISOString())} to ${b.state === 'now' ? 'now' : clock(new Date(b.end).toISOString())}` : '';
    const reason = b.state === 'failed' ? `: ${b.why ? b.why.split('\n')[0] : b.parts[b.parts.length - 1].name}` : '';
    b.tip.textContent = `${b.name}: ${STEP_WORD[b.state]}, ${time}${clocks}${reason}`;
  }
  // The total line over "Every step" (total): the axis's length and ends, the time in steps when pauses make it
  // shorter, and the queue's wait apart. ax: the axis's bars, its start (from), whether its bars have their times
  // (timed), whether a step runs (open), and the wait.
  function totalSaid(total, ax) {
    const { bars, from, timed, open, wait } = ax;
    const to = Math.max(from, ...bars.map((b) => b.from + b.secs * 1000)), span = to - from, work = bars.reduce((a, b) => a + b.secs, 0);
    const at = (ms) => when(new Date(ms).toISOString());
    const text = (timed ? `${took(span / 1000)} from ${at(from)} to ${open ? 'now' : at(to)}${work < span / 1000 - 60 ? `, ${took(work)} of it in steps` : ''}` : `${took(work)} in steps`)
      + (num(wait) ? ` · waited ${took(wait)} in the queue before` : '');
    // The line is one line high and may be cut (app.css, .tl-total): its full text is its tip.
    if (total.textContent !== text) { total.textContent = text; tip(total, text); }
  }
  // Each bar's time, place and length on the axis, its time on it and its words, at the draw. The axis is fixed then:
  // while a step runs it has room after now (a tenth of its length, a minute at least) for that bar to grow into
  // each second, and only that bar's length and the time texts change till the next draw. A tick that put the axis
  // again moved every bar, and their times between bar and lane, under the reader each second.
  function placeBars(det, total, bars, t, wait) {
    const open = bars.some((b) => b.state === 'now');
    bars.forEach((b) => measureBar(b, t));
    const timed = bars.length > 0 && bars.every((b) => b.start !== null);
    let off = 0;
    bars.forEach((b) => { b.from = timed ? b.start : off; off = b.from + b.secs * 1000; });
    const from = bars.length ? Math.min(...bars.map((b) => b.from)) : 0;
    const said = () => totalSaid(total, { bars, from, timed, open, wait });
    const span = Math.max(from, ...bars.map((b) => b.from + b.secs * 1000)) - from, axis = span + (open ? Math.max(60000, span / 10) : 0);
    // Left and width are shares of the axis; a step of no measurable time is still drawn, at its least width.
    const share = (ms) => (axis > 0 ? (ms / axis) * 100 : 0);
    bars.forEach((b) => {
      b.left = share(b.from - from);
      b.width = share(b.secs * 1000);
      b.bar.style.left = `${b.left.toFixed(2)}%`;
      b.bar.style.width = `${b.width.toFixed(2)}%`;
      // The time is on the bar when it is wide enough, else beside it.
      (b.width >= 25 ? b.bar : b.lane).append(b.dur);
      besideBar(b);
      barWords(b);
    });
    said();
    // Each second: the running bar grows, to the axis's end at most; its time stays where the draw put it (a node moved
    // under the reader moves the page), and the texts count on.
    if (open) {
      det.retime = () => {
        bars.filter(barRunning).forEach((b) => {
          measureBar(b, t);
          b.width = Math.min(100 - b.left, share(b.secs * 1000));
          b.bar.style.width = `${b.width.toFixed(2)}%`;
          besideBar(b);
          barWords(b);
        });
        said();
      };
    }
  }
  // A closed "Every step" with no steps drawn in it, only its summary (panels/belt.js draws them when it opens): it is
  // hidden as trackDetail's is, when it has no step and no earlier attempt to show.
  function trackShell(t, card, earlier) {
    const det = h('details', 'track-detail');
    det.append(h('summary', null, 'Every step'));
    if (typeof card === 'string') det.dataset.card = card;
    const prior = Array.isArray(earlier) && earlier.some((e) => e && typeof e === 'object' && e.track && typeof e.track === 'object');
    det.hidden = !stepsOf(t).some((s) => s.name !== 'queued') && !prior;
    return det;
  }

  // Why a blocked card stopped, as one plain sentence first ("2 tests failed: a, b", "Review said NO-GO three times",
  // "Push refused: the check typecheck failed"), and its explanation under it, shown without a tap (no <details>, so
  // a phone, with no hover, reads it too). c: the card as Needs you has it (reason, track, reviews, push, check).
  const TIMES = ['', 'once', 'twice', 'three times'];
  function failure(c) {
    const full = typeof c.reason === 'string' && c.reason.trim() ? c.reason.trim() : 'no reason recorded';
    const steps = sixOf(c.track) ? c.track.steps : [];
    const at = steps.map((s) => s.state).lastIndexOf('failed');
    const { names, timeout, fails } = failedTests(stepsOf(c.track), full);
    const nogo = (Array.isArray(c.reviews) ? c.reviews : []).filter((r) => r && r.verdict === 'NO-GO').length;
    // A review that could not finish ("review 2: review failed (exit 3; …)", "review 2 ended without one clear
    // verdict") stopped the card, not an earlier round's NO-GO: its own sentence leads.
    const reviewBroke = /^review \d+(:| ended\b)/i.test(full);
    let said;
    if (c.push || /^push\b/i.test(full)) said = pushRefused(c, full);
    else if (names.length) said = `${names.length} test${names.length === 1 ? '' : 's'} failed: ${names.slice(0, 3).join(', ')}${names.length > 3 ? ` and ${names.length - 3} more` : ''}`;
    else if (timeout) said = `The tests timed out${typeof timeout.file === 'string' && timeout.file ? ` in ${timeout.file}` : ''}`;
    else if (nogo && !reviewBroke && (at === 1 || /NO-GO/.test(full))) said = `Review asked for changes ${TIMES[nogo] || `${nogo} times`}`;
    else said = first(full);
    return { said, full, fails };
  }
  // The failed tests of a blocked card (failure), from its steps recs: the cases' names, the timeout and the last
  // failed run's failures. The failed tests are the cause only when the card stopped for them (its reason full: "the
  // changed tests failed again…"): a card whose fix of those tests then failed ("fix: …") stopped for its fix, and an
  // earlier run's names are not why.
  function failedTests(recs, full) {
    const names = [];
    let timeout = null, fails = null;
    const byTests = /\btests failed\b/i.test(full) && !/^fix\b/i.test(full);
    if (byTests) recs.filter((s) => s.state === 'failed' && s.failures && typeof s.failures === 'object').slice(-1).forEach((s) => {
      (Array.isArray(s.failures.files) ? s.failures.files : []).forEach((f) => (f && Array.isArray(f.cases) ? f.cases : []).forEach((x) => { if (x && typeof x.name === 'string') names.push(x.name); }));
      if (s.failures.timeout && typeof s.failures.timeout === 'object') timeout = s.failures.timeout;
      fails = s.failures;
    });
    return { names, timeout, fails };
  }
  // The sentence of a card whose push was refused (failure): the check that failed, else the reason's first sentence.
  function pushRefused(c, full) {
    const failedPush = /\bFAILED:?\s+([A-Za-z0-9_.:/-]+)/.exec(full);
    return `Push refused: ${c.check ? `the check ${c.check} failed` : failedPush ? `the check ${failedPush[1]} failed` : first(full.replace(/^push failed:?\s*/i, ''))}`;
  }
  // The first sentence of a text, cut at a word to 140 characters at most.
  function first(s) {
    const m = /^[^\n]*?[.!?](?=\s|$)/.exec(s), one = (m ? m[0] : s.split('\n')[0]).trim();
    if (one.length <= 140) return one;
    const cut = one.slice(0, 140), sp = cut.lastIndexOf(' ');
    return `${(sp > 60 ? cut.slice(0, sp) : cut).replace(/[\s,:;]+$/, '')}…`;
  }
  // The sentence a blocked card leads with, then its explanation, shown without a tap in a block labelled "Why it
  // blocked" (app.css .why-block), by the kind of block: a review block ("the fix for [P1] ... did not hold after 1
  // round") draws its finding as the Declined panel does (level, linked place, claim, proof); a test block its failing
  // files and cases with their first failure lines (testFails); any other the reason as recorded, in full. A sentence
  // that already says the whole reason has no block. Code spans and file paths are drawn as fill draws them, linked in
  // the card's repository (repoOf). brief (reviewWhy): only the first finding, with the first sentence of its proof.
  const SHOWN_LINES = 12;
  function reviewWhy(full, repoUrl, known, brief) {
    const m = /^the fix for (\[P[0-3]\][\s\S]*?)\s+did not hold after \d+ rounds?$/.exec(full);
    if (!m) return null;
    const rows = h('ol', 'output-findings');
    m[1].split(/\n(?=\[P[0-3]\])/).slice(0, brief ? 1 : Infinity).forEach((t) => {
      const f = /^\[(P[0-3])\]\s*(?:\[(?:E\d+|cleanup)\]\s*)*(?:(\S+:\d+(?:[-–]\d+)?)[:,]?\s+(?=\S))?([\s\S]*)$/.exec(t.trim());
      if (!f) return;
      const { at: cut, label } = proofAt(f[3]), claim = (cut < 0 ? f[3] : f[3].slice(0, cut)).trim(), proof = cut < 0 ? '' : f[3].slice(cut + label.length).trim();
      const row = h('li', 'output-finding'), head = h('div', 'finding-head'), said = h('p', 'finding-text');
      said.append(fill(h('strong', 'finding-claim'), claim, repoUrl, known, 'finding'));
      head.append(chip(f[1], f[1] === 'P0' || f[1] === 'P1' ? 'warn' : 'quiet'), said);
      row.append(head);
      if (f[2]) { const p = h('p', 'finding-at'); p.append(codeEl(repoUrl, f[2], known, 'finding-at-link').el); row.append(p); }
      if (proof) row.append(h('p', 'finding-proof-label', 'Proof:'), fill(h('div', 'finding-proof-text'), brief ? first(proof) : proof, repoUrl, known, 'finding'));
      rows.append(row);
    });
    return rows.children.length ? rows : null;
  }
  // The reason whole, or its first SHOWN_LINES lines and a "Show all" button that shows the rest.
  function clipped(full, repoUrl, known) {
    const lines = full.split('\n'), draw = (t) => fill(h('div', 'why-text why-full'), t, repoUrl, known, 'why');
    if (lines.length <= SHOWN_LINES) return draw(full);
    const box = h('div', 'why-clip'), btn = h('button', 'btn btn-quiet show-all', 'Show all');
    btn.type = 'button';
    let part = draw(lines.slice(0, SHOWN_LINES).join('\n'));
    btn.addEventListener('click', () => { const all = draw(full); part.replaceWith(all); part = all; btn.remove(); });
    box.append(part, btn);
    return box;
  }
  function failureLine(c) {
    const { said, full, fails } = failure(c);
    const repoUrl = repoOf(c), known = new Set(pathsIn(full));
    const out = doc.createDocumentFragment();
    out.append(fill(h('p', 'reason why-said'), said, repoUrl, known, 'why-said'));
    const body = reviewWhy(full, repoUrl, known) || (fails && testFails(fails)) || (said !== full && clipped(full, repoUrl, known));
    if (body) out.append(whyBlock('Why it blocked', body));
    return out;
  }
  const whyBlock = (label, body) => { const box = h('div', 'reason why-block'); box.append(h('strong', 'why-label', label), body); return box; };
  // The short form, for Needs you, so its next step and buttons come right under the failure: {lead, rest}. lead is the
  // sentence, then the first finding (its level, place, claim and the first sentence of its proof) or the first failing
  // test file with its first failing case, in "Why it blocked"; rest is the whole explanation as failureLine draws it,
  // in "Why it blocked, in full", or null when the lead already says all of it. A plain reason leads with its sentence.
  function failureShort(c) {
    const { said, full, fails } = failure(c);
    const repoUrl = repoOf(c), known = new Set(pathsIn(full));
    const lead = doc.createDocumentFragment();
    lead.append(fill(h('p', 'reason why-said'), said, repoUrl, known, 'why-said'));
    const one = reviewWhy(full, repoUrl, known, true) || (fails && testFails(fails, true));
    if (one) lead.append(whyBlock('Why it blocked', one));
    const body = reviewWhy(full, repoUrl, known) || (fails && testFails(fails)) || (said !== full && clipped(full, repoUrl, known));
    return { lead, rest: body ? whyBlock('Why it blocked, in full', body) : null };
  }
  function seenStore() {
    let seen;
    try { seen = JSON.parse(window.localStorage.getItem(SEEN_KEY)); } catch { seen = null; }
    return Array.isArray(seen) ? seen.filter((k) => typeof k === 'string') : null;
  }
  // The keys not shown before in this browser, and the record of what is shown now. The first visit shows none as
  // new: everything on a page just opened would light up at once.
  function fresh(keys) {
    const seen = seenStore();
    try { window.localStorage.setItem(SEEN_KEY, JSON.stringify(keys)); } catch { /* a browser that keeps nothing shows no item as new */ }
    return seen === null ? [] : keys.filter((k) => !seen.includes(k));
  }
  // Last, so that every name above is set before app.js reads what this part gives back.
  window.DASH_APP.core((given) => {
    app = given;
    app.bind(bindNames);
    return { track, fixNow, testProgress, earlierTip, trackDetail, trackShell, failure, failureLine, failureShort,
      fresh };
  });
})();
