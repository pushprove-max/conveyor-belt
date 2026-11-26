// SPDX-License-Identifier: Apache-2.0
// The demo's mock timeline: what the Board shows for an invented project, example/acme-api, while its cards advance
// on a clock. Nothing here is read from a real Conveyor, a real repository or a real machine: the issues, the host
// name and every figure are made up. capture-board.js serves snapshot(t) to the real Board page (.claude/dashboard)
// as its feed, and applies the page's control actions with act(); the snapshot has the shape dashboard.sh writes
// ({updatedAt, panels}, one part per panel).
//
// t is the story clock in seconds. One story second stands for SCALE seconds of a real card's time, so the times the
// Board prints (in step for 2 min, took 6 min) look like a real day's while the cards move in a few seconds.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// The kinds of Needs you, as dashboard.sh gives them: the Needs you panel lists only the kinds named here.
const NEEDS_KINDS = JSON.parse(fs.readFileSync(path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '.claude', 'scripts', 'dashboard_needs.json'), 'utf8'));
export const REPO = 'acme-api';
export const URL = 'https://github.com/example/acme-api';
const SCALE = 30;
const HOST = 'acme-build';

// The issues. #41, #42 and #43 are the three filed in the demo's GitHub beat.
export const ISSUES = {
  38: 'Validate signup emails',
  39: 'Paginate /invoices',
  41: 'Rate-limit the login endpoint',
  42: 'Add cursor pagination to /orders',
  43: 'Return 404 for unknown customers',
  44: 'Retry failed webhook deliveries',
  45: 'Cache product search results',
  46: 'Log slow database queries',
  47: 'Add an idempotency key to POST /payments',
};

// Each card's steps: [story second it began, step]. A step is build, review<n>, fix<n>, tests, landing, push or
// landed; findings: the counts of each review round. #41 is the card the detail beat follows: review 1 finds a P1,
// the fix round runs, review 2 is clean, it lands. #44 is blocked from the start until the owner retries it.
const CARDS = [
  { issue: 42, steps: [[-14, 'build'], [-8, 'review1'], [-1, 'tests'], [2, 'landing'], [3.5, 'push'], [5, 'landed']], findings: { 1: [0, 0, 0, 0] }, sha: '4f2c9e1' },
  { issue: 41, steps: [[-6, 'build'], [1, 'review1'], [4.5, 'fix1'], [8, 'review2'], [10.5, 'tests'], [12.5, 'landing'], [14, 'push'], [15.5, 'landed']],
    findings: { 1: [0, 1, 1, 0], 2: [0, 0, 0, 0] }, sha: 'b81d07a' },
  { issue: 43, steps: [[1.5, 'build'], [7, 'review1'], [11, 'tests'], [14, 'landing'], [16, 'push'], [17.5, 'landed']], findings: { 1: [0, 0, 0, 0] }, sha: '9ce3a52' },
];
const QUEUE = [45, 46, 47];
// The README's Belt 3D GIF (capture-board.js, belt3d): the story seconds from to to, in which #41 goes from Review
// back to Fix, #44 stays blocked and #42 and #41 land. At story second click.at, in #41's fix round and once #42's
// lane has gone (a lane moving under the pointer takes the click to another card), the pointer clicks #41's lane and
// its details stay open for openSec wall seconds.
export const BELT3D = { from: 0, to: 16, speed: 1.2, click: { issue: 41, at: 6.5, openSec: 3 } };
const LANDED_BEFORE = [{ issue: 39, ago: 3 * 3600, sha: '1d7e6b0' }, { issue: 38, ago: 5 * 3600, sha: 'e05a4c3' }];
const STEP_INDEX = { build: 0, review: 1, fix: 2, tests: 3, landing: 4, push: 5 };
const LABEL = { build: 'building', tests: 'tests', landing: 'landing', push: 'pushing' };

// The Tests page: the project's test files, as testspart() gives them. Two are slower than usual (orders: #42's
// pagination made it slower), one is flaky, the rest are fine. runs: [CPU s, clock s, issue,
// hours ago], newest first.
export const TEST_FILES = [
  { file: 'test/orders.test.ts', cpu: 9.4, median: 8, change: 0.18, slower: true, runs: [[9.4, 10.6, 42, 1], [7.9, 8.8, 39, 3], [7.8, 8.9, 38, 5]] },
  { file: 'test/payments.test.ts', cpu: 5.2, median: 5.1, change: 0.02, runs: [[5.2, 6.1, 42, 1], [5.1, 5.9, 39, 3]] },
  { file: 'test/search.test.ts', cpu: 4.1, median: 2.6, change: 0.58, slower: true, runs: [[4.1, 4.7, 42, 1], [3.9, 4.4, 39, 3], [2.6, 3.1, 38, 5]] },
  { file: 'test/auth.test.ts', cpu: 3.6, median: 3.5, change: 0.03, runs: [[3.6, 4.2, 42, 1], [3.5, 4, 39, 3]] },
  { file: 'test/webhooks.test.ts', cpu: 3, median: 3.1, change: -0.03, flaky: 2, runs: [[3, 3.8, 42, 1], [3.2, 3.9, 39, 3]] },
  { file: 'test/customers.test.ts', cpu: 2.4, median: 2.4, change: 0, runs: [[2.4, 2.9, 42, 1], [2.4, 2.8, 39, 3]] },
  { file: 'test/invoices.test.ts', cpu: 2, median: 2.1, change: -0.05, runs: [[2, 2.4, 42, 1], [2.1, 2.5, 39, 3]] },
  { file: 'test/customers-lookup.test.ts', cpu: 1.6, median: 1.6, change: 0, runs: [[1.6, 2, 42, 1], [1.6, 1.9, 39, 3]] },
];
// The answers of the two test actions the Tests beat runs: Explain the slowdown on orders, slower than usual, Judge
// this test on a second file. Each runs for ACTION_SEC story seconds, then shows its answer.
export const TEST_ANSWERS = {
  explain: { file: 'test/orders.test.ts', verdict: null, text: 'test/orders.test.ts went from 7.9 to 9.4 CPU s with #42 (Add cursor pagination to /orders), commit 4f2c9e1.\n'
    + 'Its new cases seed 5,000 orders in beforeEach, once for each of its 12 cases.\n'
    + 'Seed them once in beforeAll, or seed 60: no case reads more than 3 pages of 20.\n' },
  judge: { file: 'test/customers-lookup.test.ts', verdict: 'merge', text: 'It tests GET /customers/:id, as test/customers.test.ts does, and starts a server of its own.\n'
    + 'Only its 404 case is not in test/customers.test.ts. Move that case there and delete this file: one server start less, about 1.2 CPU s a run.\n'
    + 'VERDICT: merge\n' },
};
const ACTION_SEC = 2.5;
const TESTS_MODEL = { cli: 'claude', model: 'claude-sonnet-5-5', effort: 'high' };

const counts = (a) => (a ? { P0: a[0], P1: a[1], P2: a[2], P3: a[3] } : null);
const issueUrl = (n) => `${URL}/issues/${n}`;
const cardId = (n) => `c20261115T0900${String(n).padStart(2, '0')}-${REPO}-${n}`;

export function createTimeline(wallStart = Date.now()) {
  // What the owner changed on the page (act): the control record the Board's Control and Rules tabs read.
  const control = {
    mode: 'run', cap: 3, guard: 90, held: [], order: [], rules: { P0: true, P1: true, P2: true, followups: false, push: true, visible: true, never: [] },
    model: { cli: 'claude', model: 'claude-sonnet-5-5', effort: 'high' }, reviewer: null, judge: null, judgeOn: false, judgeAlways: [],
    start: 'queue', startHeld: [], startSeen: [], depGuard: true, forced: [], tests: TESTS_MODEL,
  };
  let retriedAt = null; // the story second the owner retried #44
  const asked = []; // the test actions the owner ran: {id, how, at (story second)}, newest first
  let clock = 0;
  // The wall time of story second sec, as the page reads it now (the page counts times from its own clock).
  const iso = (sec) => new Date(Date.now() - (clock - sec) * SCALE * 1000).toISOString().replace(/\.\d{3}Z$/, 'Z');

  // The step a card is in at t, with the second it began and the steps before it.
  function where(card, t) {
    let i = -1;
    card.steps.forEach(([at], k) => { if (at <= t) i = k; });
    return i < 0 ? null : { i, step: card.steps[i][1], since: card.steps[i][0] };
  }
  function track(card, t) {
    const w = where(card, t);
    const done = card.steps.slice(0, w.i);
    const kind = (s) => s.replace(/\d+$/, '');
    const round = (s) => Number((/\d+$/.exec(s) || [0])[0]);
    const steps = ['Build', 'Review', 'Fix', 'Test', 'Land', 'Push'].map((name) => ({ name, state: 'todo', sec: null }));
    done.forEach(([at, s], k) => { const x = steps[STEP_INDEX[kind(s)]]; x.state = 'done'; x.sec = (x.sec || 0) + Math.round((card.steps[k + 1][0] - at) * SCALE); });
    const now = kind(w.step);
    if (now !== 'landed') steps[STEP_INDEX[now]].state = 'now';
    // A clean first review skips Fix once the card is past it (a landed card is past every step).
    if (!done.some(([, s]) => kind(s) === 'fix') && (now === 'landed' || STEP_INDEX[now] > 2)) steps[2].state = 'skipped';
    const reviews = done.filter(([, s]) => kind(s) === 'review').length;
    steps[1].n = Math.max(reviews, now === 'review' ? round(w.step) : 0); steps[1].of = 3;
    steps[2].n = done.filter(([, s]) => kind(s) === 'fix').length + (now === 'fix' ? 1 : 0);
    const label = now === 'review' ? `review ${round(w.step)} of 3` : now === 'fix' ? `fix ${round(w.step)}` : LABEL[now] || null;
    const detail = card.steps.map(([, s], k) => ({ name: s.replace(/(\d+)$/, ' $1'), state: k < w.i ? 'done' : k === w.i ? 'now' : 'todo', sec: k < w.i ? Math.round((card.steps[k + 1][0] - card.steps[k][0]) * SCALE) : null }));
    const tests = now === 'tests' ? { done: Math.min(64, Math.round((t - w.since) * 30)), of: 64, failed: 0 } : null;
    return { steps, at: now === 'landed' ? null : STEP_INDEX[now], label, since: iso(w.since), reason: null, files: now === 'tests' ? { run: 1, of: 2 } : null, tests, detail, detailAt: null };
  }
  function reviewsOf(card, t) {
    return card.steps.filter(([at, s], k) => /^review/.test(s) && card.steps[k + 1] && card.steps[k + 1][0] <= t).map(([at, s], k) => {
      const r = Number(s.slice(6)), c = card.findings[r];
      const go = c.every((x) => x === 0);
      return { round: r, verdict: go ? 'GO' : 'NO-GO', counts: counts(c), sec: 180 + r * 40, fixed: !go };
    });
  }
  // The steps a card has ended, as its track's records give them (conveyor/jq/track.jq): name, and at, when it ended.
  const RECORD = { build: 'building', tests: 'tests passed', landing: 'landing', push: 'push' };
  function records(card, t) {
    return card.steps.slice(0, where(card, t).i).map(([, s], k) => ({ name: RECORD[s] || s.replace(/(\d+)$/, ' $1'), at: iso(card.steps[k + 1][0]) }));
  }
  function usd(card, t) { const w = where(card, t); return Math.round(((t - card.steps[0][0]) * 0.11 + (w ? w.i * 0.2 : 0)) * 100) / 100; }

  // #44: blocked (its tests failed twice) until the owner's Retry; then back on the belt, building.
  const blockedCard = { issue: 44, steps: [[-40, 'build'], [-32, 'review1'], [-26, 'tests']], findings: { 1: [0, 0, 0, 0] } };
  function retried() { return retriedAt === null ? [] : [{ issue: 44, steps: [[retriedAt, 'build']], findings: {} }]; }

  function belt(t) {
    const all = CARDS.concat(retried()).filter((c) => where(c, t) && where(c, t).step !== 'landed');
    return all.map((c) => {
      const w = where(c, t), tr = track(c, t), step = w.step.replace(/\d+$/, '');
      const live = { turns: Math.round((t - w.since) * 3) + 4, lastOutputAt: iso(t - 0.1), action: step === 'build' || step === 'fix' ? 'Edit: src/routes.ts' : step === 'tests' ? 'Bash: npm test' : 'Read: src/routes.ts' };
      return { repo: REPO, card: cardId(c.issue), issue: c.issue, title: ISSUES[c.issue], url: issueUrl(c.issue), parent: null, step,
        review: step === 'review' ? Number(w.step.slice(6)) : null, of: 3, stepAt: iso(w.since), landed: step === 'push', model: step === 'review' ? 'claude-opus-5-5' : control.model.model,
        tokens: { claude: Math.round((t - c.steps[0][0]) * 41000), codex: 0 }, usd: usd(c, t), reading: true, live,
        reviews: reviewsOf(c, t), track: tr, start: iso(c.steps[0][0]), pickedAt: iso(c.steps[0][0]), priorSec: 0, totalSec: null };
    });
  }
  function landed(t) {
    const now = CARDS.filter((c) => where(c, t) && where(c, t).step === 'landed').map((c) => {
      const at = c.steps[c.steps.length - 1][0];
      return { repo: REPO, card: cardId(c.issue), issue: c.issue, title: ISSUES[c.issue], url: issueUrl(c.issue), step: 'landed', time: iso(at), start: iso(c.steps[0][0]),
        tookSec: Math.round((at - c.steps[0][0]) * SCALE), usd: usd(c, at), reviews: reviewsOf(c, at).length, followups: [], sha: c.sha, pushed: true };
    }).reverse();
    const before = LANDED_BEFORE.map((x) => ({ repo: REPO, card: cardId(x.issue), issue: x.issue, title: ISSUES[x.issue], url: issueUrl(x.issue), step: 'landed',
      time: new Date(wallStart - x.ago * 1000).toISOString().replace(/\.\d{3}Z$/, 'Z'), start: new Date(wallStart - x.ago * 1000 - 1500000).toISOString().replace(/\.\d{3}Z$/, 'Z'),
      tookSec: 1500, usd: 1.85, reviews: 1, followups: [], sha: x.sha, pushed: true }));
    return now.concat(before);
  }
  // The Tests part (dashboard.sh, tests): the files and figures, and each test action asked for, running until
  // ACTION_SEC after its ask, then done with its answer.
  function testsPart(t) {
    const files = TEST_FILES.map((f) => {
      const last = f.runs[0];
      return { file: f.file, cpu: f.cpu, median: f.median, usual: f.median, change: f.change,
        slower: f.slower === true, slowOnPurpose: null, flaky: f.flaky || 0, failedSteps: 0, issue: null, timedRuns: 6 + f.runs.length,
        lastRun: { cpu: last[0], sec: last[1], clockPerCpu: Math.round((last[1] / last[0]) * 100) / 100 },
        runs: f.runs.map(([cpu, sec, n, h]) => ({ cpu, sec, card: cardId(n), time: iso(t - (h * 3600) / SCALE), issue: n, repo: REPO, url: issueUrl(n) })) };
    });
    const actions = asked.filter((a) => a.at <= t).map((a) => {
      const done = t >= a.at + ACTION_SEC, ans = TEST_ANSWERS[a.how];
      return { id: a.id, action: a.how, file: ans.file, project: REPO, start: iso(a.at), end: done ? iso(a.at + ACTION_SEC) : null, state: done ? 'done' : 'running',
        ...TESTS_MODEL, limit: 900, verdict: done ? ans.verdict : null, text: done ? ans.text : `${ans.text.split('\n')[0]}\n`, textCut: false };
    });
    return { repo: REPO, repos: [REPO], others: {},
      tests: { settings: { slowIssues: false, slower: { share: 0.25, runs: 3, minRuns: 5 }, files: {} },
        rules: { on: true, perDay: 3, maxOpen: 5, quietDays: 14, burst: true, list: [{ name: 'slower than usual', on: true, measure: 'usual', limit: 1.5, runs: 3, minRuns: 5 }], last: null, log: [] },
        files, slower: TEST_FILES.filter((f) => f.slower).map((f) => f.file),
        totals: { files: files.length, slower: files.filter((f) => f.slower).length, steps: { count: 41, waitSec: 95, runSec: 2460 } } },
      testActions: { limit: 900, allowed: { claude: ['claude-opus-5-5', 'claude-sonnet-5-5'] }, actions },
      control: JSON.parse(JSON.stringify(control)), clis: { claude: { models: null, efforts: ['low', 'medium', 'high', 'xhigh', 'max'] } }, flaky: [] };
  }
  function queued() { return QUEUE.filter((n) => !control.held.includes(n)); }
  const item = (n, more = {}) => ({ repo: REPO, card: null, issue: n, title: ISSUES[n], url: issueUrl(n), ...more });
  const prio = { 45: 'P2', 46: 'P2', 47: 'P1' };

  // The Belt 3D part (dashboard.sh, belt3d), cut from the parts above: the belt with each card's track records, Needs
  // you, the queue and the cards landed today, each with its reviews, track and cost, and the deck's readouts.
  function belt3d(t, b, blocked, q, held, l, used) {
    const rounds = (rs) => rs.map((r) => ({ round: r.round, verdict: r.verdict, counts: r.counts }));
    const track3 = (tr) => ({ steps: tr.steps, at: tr.at, since: tr.since, tests: tr.tests, files: tr.files });
    const all = CARDS.concat(retried());
    const pick = (x) => ({ repo: x.repo, issue: x.issue, title: x.title, url: x.url });
    return { repos: [REPO], byRepo: {},
      belt: b.map((x) => ({ ...pick(x), card: x.card, step: x.step, stepAt: x.stepAt, landed: x.landed, waitsOn: null, usd: x.usd, turns: x.live.turns, reviews: rounds(x.reviews),
        track: { ...track3(x.track), records: records(all.find((c) => c.issue === x.issue), t) } })),
      queue: { next: q.map(pick), held: held.map((x) => ({ ...pick(x), waitsFor: [] })), waiting: [] },
      needs: blocked.map((x) => ({ ...pick(x), card: x.card, kind: 'blocked', reason: x.reason, since: x.since, reviews: rounds(x.reviews), usd: x.usd, track: x.track })),
      // A card landed in the story has its rounds and track; one landed earlier today had one clean review.
      landed: l.map((x) => {
        const c = CARDS.find((k) => k.issue === x.issue), end = c && c.steps[c.steps.length - 1][0];
        return { ...pick(x), card: x.card, time: x.time, usd: x.usd, reviews: c ? rounds(reviewsOf(c, end)) : [{ round: 1, verdict: 'GO', counts: counts([0, 0, 0, 0]) }], track: c ? track3(track(c, end)) : null };
      }),
      deck: { host: HOST, state: 'running', used, cap: control.cap } };
  }

  function snapshot(t) {
    clock = t;
    const b = belt(t), l = landed(t), blocked = retriedAt === null ? [{ repo: REPO, card: cardId(44), issue: 44, title: ISSUES[44], url: issueUrl(44),
      reason: 'The changed tests failed twice: test/webhooks.test.ts, retries stop after the first failure. The work is kept.', since: iso(-20),
      reviews: reviewsOf(blockedCard, 0), usd: 2.4, track: { steps: ['Build', 'Review', 'Fix', 'Test', 'Land', 'Push'].map((name, i) => ({ name, state: ['done', 'done', 'skipped', 'failed', 'todo', 'todo'][i], sec: [420, 210, null, 95, null, null][i] })), at: null, since: null, tests: { done: 64, of: 64, failed: 2 }, files: null } }] : [];
    const used = b.filter((c) => !c.landed).length;
    const landedToday = l.filter((x) => x.card && CARDS.some((c) => c.issue === x.issue)).length + LANDED_BEFORE.length;
    const today = Math.round((7.4 + b.reduce((s, c) => s + c.usd, 0)) * 100) / 100;
    const q = queued().map((n) => item(n, { priority: prio[n], followup: false, retried: false, areas: [] }));
    const held = control.held.map((n) => item(n));
    const lanes = (cards) => cards.map((c) => ({ repo: REPO, card: c.card, issue: c.issue, title: c.title, url: c.url, step: c.step, stepAt: c.stepAt, usd: c.usd, reading: true, review: c.review, of: 3 }));
    const models = {
      builder: { model: control.model.model, effort: control.model.effort, agent: 'claude', modelFrom: 'control', effortFrom: 'control', choices: ['claude-opus-5-5', 'claude-sonnet-5-5'], efforts: ['low', 'medium', 'high', 'xhigh', 'max'],
        allowed: { claude: ['claude-opus-5-5', 'claude-sonnet-5-5', 'claude-haiku-5-5'], codex: [], opencode: [] }, clis: { claude: { models: null, efforts: ['low', 'medium', 'high', 'xhigh', 'max'] } }, missing: null },
      reviewer: { model: 'claude-opus-5-5', effort: 'high', agent: 'claude', modelFrom: 'seed', effortFrom: 'seed', choices: ['claude-opus-5-5'], efforts: ['low', 'medium', 'high', 'xhigh', 'max'],
        allowed: { claude: ['claude-opus-5-5'], codex: [], opencode: [] }, clis: { claude: { models: null, efforts: ['low', 'medium', 'high', 'xhigh', 'max'] } }, missing: null },
      judge: { model: 'claude-opus-5-5', effort: 'medium', agent: 'claude', modelFrom: 'seed', effortFrom: 'seed', choices: ['claude-opus-5-5'], efforts: ['low', 'medium', 'high', 'xhigh', 'max'], default: 'claude-opus-5-5',
        allowed: { claude: ['claude-opus-5-5'], codex: [], opencode: [] }, clis: { claude: { models: null, efforts: ['low', 'medium', 'high', 'xhigh', 'max'] } }, missing: null },
    };
    const guard = { at: 90, reading: 31, readAt: iso(t - 1), missing: false };
    const ctl = JSON.parse(JSON.stringify(control));
    return {
      updatedAt: iso(t),
      panels: {
        machine: { error: null, data: { host: HOST, state: 'running', cap: null, used, todayUsd: today, todayLeftOut: 0, repos: [REPO],
          projects: [{ repo: REPO, state: 'running', reason: null, loop: true, mode: control.mode, cap: control.cap, used,
            needs: blocked.map((c) => item(c.issue, { card: c.card })), belt: b.map((c) => item(c.issue, { card: c.card, step: c.step })), queue: queued().map((n) => item(n)), held,
            order: [], rules: ctl.rules, models: { builder: { model: control.model.model, effort: control.model.effort }, reviewer: { model: 'claude-opus-5-5', effort: 'high' } },
            landedToday, todayUsd: today }],
          foremen: [], foremenError: null } },
        board: { error: null, data: { repo: REPO, state: 'running', loop: true, commit: 'b81d07a6c4e2f19a0d3b5c7e9f1a2b3c4d5e6f70', control: ctl, cap: control.cap,
          guard, modelSettings: models, limit: { pct: 31, from: 'loop' }, held, queue: q, skipped: [], issuesError: null,
          building: lanes(b.filter((c) => c.step !== 'review')), review: lanes(b.filter((c) => c.step === 'review')), waiting: [],
          blocked: blocked.map((c) => ({ repo: REPO, card: c.card, issue: c.issue, title: c.title, url: c.url, reason: 'tests failed twice', since: c.since })),
          landed: l.map((x) => ({ repo: REPO, card: x.card, issue: x.issue, title: x.title, url: x.url, step: 'landed', time: x.time, usd: x.usd, reviews: x.reviews })),
          today: { landed: landedToday, usd: today }, push: true, unpushed: [], fullTest: { command: true, why: null, running: null, last: null },
          open: { count: q.length + held.length + used + blocked.length, split: { queued: q.length, you: held.length, labelOrRule: 0, belt: used }, issues: q.concat(held) } } },
        rules: { error: null, data: { repo: REPO, state: 'running', control: ctl, cap: control.cap, areaPrefix: 'area:', guard, modelSettings: models, limit: { pct: 31, from: 'loop' },
          held, queue: q, skipped: [], waits: [], cards: [], issuesError: null, building: used,
          forecast: { cards: 9, usd: 16.2, perCard: { usd: 1.8, pct: 0.6 }, guard: 90, reading: 31, pausesAt: null },
          open: { count: q.length + held.length + used, split: { queued: q.length, you: held.length, labelOrRule: 0, belt: used },
            held: held.map((x) => ({ ...x, priority: prio[x.issue], labels: [prio[x.issue]], reasons: [{ kind: 'you' }] })) } } },
        needs: { error: null, data: { cards: { waiting: [], blocked }, cardsError: null, decisions: [], decisionsError: null, retrying: [], kinds: NEEDS_KINDS, entries: {} } },
        belt: { error: null, data: { cap: control.cap, cards: b } },
        queue: { error: null, data: { next: q.map((x) => ({ repo: REPO, issue: x.issue, title: x.title, priority: x.priority, followup: false, retried: false, url: x.url })), held: held.length, awaitingDeploy: [], issuesError: null } },
        landed: { error: null, data: { day: iso(t).slice(0, 10), cards: l } },
        declined: { error: null, data: { lines: [], rest: [] } },
        health: { error: null, data: { host: { name: HOST, reachable: true, error: null },
          records: [{ repo: REPO, loop: true, newest: iso(t - 0.5), stuck: [], unpushed: [], pushError: null, pushFailingSince: null, lastPushAt: iso(t - 4), gh: true, diskFreeKb: 400000000, builderCap: control.cap, models: {} }],
          limit: { usedPct: 31, goalPct: 43, underPts: 12, paceSec: 1, timeLeftSec: 302400, resetsAt: new Date(Date.now() + 302400000).toISOString().replace(/\.\d{3}Z$/, 'Z'), fiveHour: { usedPct: 12 }, reading: 'fresh' },
          limitError: null, limits: [{ repo: REPO, account: null, uses: ['build', 'review'], pct: 31, readAt: iso(t - 0.5), email: null }] } },
        lanes: { error: null, data: { records: [], cardsError: null } },
        cost: { error: null, data: { cards: { day: iso(t).slice(0, 10), todayUsd: today, weekUsd: 61.3, perLandedUsd: 1.92, landedAfter: { 1: 3, 2: 1, 3: 0, more: 0 }, unpricedSteps: 0, perCard: [] }, cardsError: null,
          sessions: { todayUsd: today, todayComplete: true, weekUsd: 61.3 }, sessionsError: null } },
        metrics: { error: null, data: { records: [], cards: [] } },
        tests: { error: null, data: testsPart(t) },
        belt3d: { error: null, data: belt3d(t, b, blocked, q, held, l, used) },
      },
    };
  }

  // A control action from the page (POST /control {action, args}): the new control record, as the host answers it,
  // or an Error with the host's refusal. A test action (testaction <judge | explain> <file>) answers as
  // `conveyor.sh testaction` does: a line, then the action's id; the demo has an answer for one file of each.
  function act(action, args, t) {
    const a = (args || []).map(String);
    if (action === 'cap') control.cap = a[0] === 'off' ? 3 : Number(a[0]);
    else if (action === 'model') { if (a[0] !== 'default') control.model = { cli: a[0], model: a[1], effort: a[2] || control.model.effort }; }
    else if (action === 'hold') a.forEach((n) => { if (!control.held.includes(Number(n))) control.held.push(Number(n)); });
    else if (action === 'release') control.held = control.held.filter((n) => !a.includes(String(n)));
    else if (action === 'rules') a.forEach((kv) => { const [k, v] = kv.split('='); control.rules[k] = v === 'on'; });
    else if (action === 'retry' && a[0] === '44') retriedAt = t;
    else if (action === 'testaction' && TEST_ANSWERS[a[0]] && TEST_ANSWERS[a[0]].file === a[1]) {
      const id = (0x7e3a9c51d2b0 + asked.length).toString(16);
      asked.unshift({ id, how: a[0], at: t });
      return `conveyor: started ${a[0]} of ${a[1]}\n${id}`;
    } else return new Error(`the demo takes no ${action}`);
    return JSON.parse(JSON.stringify(control));
  }
  return { snapshot, act };
}
