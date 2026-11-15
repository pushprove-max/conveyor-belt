// SPDX-License-Identifier: Apache-2.0
// What the dashboard-view.*.test.mjs files share: the fake page (jsdom with the test's own timers, frames, clock and
// fetch), the snapshot builders and the lookups more than one panel's tests use.
// The Conveyor dashboard's page (.claude/dashboard). It is what the owner reads instead of asking, so: every panel shows
// its data, its empty state and its failed-to-load state, and never one for another; nothing a source wrote becomes
// markup; the layout the owner arranges is kept in their browser and restored; a refresh leaves a panel whose data did not
// change untouched; and nothing moves under reduced motion. Timers, frames and the clock are the test's own, so no
// case depends on elapsed wall time.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { test as nodeTest } from 'node:test';
import { Worker, parentPort, workerData } from 'node:worker_threads';
import { createRequire, enableCompileCache } from 'node:module';
import { fileURLToPath } from 'node:url';

// cases(import.meta.url) -- the `test` a file registers its cases with. Each case runs in one of a few worker threads,
// side by side, each with its own jsdom; node:test still reports every case by name, in the file's order, and a case
// fails with the error its body threw. A case's body is found in the worker by its place in the file and checked by
// its name, so a file whose cases differ between loads fails rather than runs the wrong body.
const POOL = workerData && workerData.dashboardCases;
const registered = [];
export function cases(file) {
  if (POOL) return (name, fn) => { registered.push({ name, fn }); };
  let pool = null;
  let count = 0;
  const queue = [];
  const start = () => {
    const take = (wk) => {
      const job = queue.shift();
      if (!job) { if (pool.every((x) => !x.job)) for (const x of pool) x.terminate(); return; }
      wk.job = job;
      wk.postMessage({ index: job.index, name: job.name });
    };
    // Four at most: each worker loads jsdom and warms its own compiled code, so on the loop's busy machine more than
    // four cost more CPU than they save (eight took about 40% more CPU than four and ran slower; conveyor/tests/speed/board-view.md).
    const size = Math.max(1, Math.min(queue.length, os.availableParallelism() - 1, 4));
    pool = Array.from({ length: size }, () => {
      // Not the test runner's flags: a worker given them never starts. Its heap is capped as the runner's is.
      const wk = new Worker(new URL(import.meta.url), { workerData: { dashboardCases: file }, execArgv: [], resourceLimits: { maxOldGenerationSizeMb: 1024 } });
      wk.on('message', (m) => { const { job } = wk; wk.job = null; m.ok ? job.done() : job.fail(Object.assign(new Error(m.message), { stack: m.stack })); take(wk); });
      // A worker that dies (an uncaught error outside a case's promise) fails the case it ran and every one left.
      wk.on('error', (e) => { for (const j of [wk.job, ...queue.splice(0)]) if (j) j.fail(e); wk.job = null; });
      wk.on('exit', (code) => { const j = wk.job; wk.job = null; if (j) j.fail(new Error(`the case's worker exited (${code})`)); });
      wk.on('online', () => take(wk));
      return wk;
    });
  };
  return (name, fn) => {
    assert.equal(typeof fn, 'function', `${name}: a case is a name and a body`);
    let done, fail;
    const result = new Promise((res, rej) => { done = res; fail = rej; });
    // A case can fail before node:test reaches it; its test still reports the failure.
    result.catch(() => {});
    if (count === 0) setImmediate(start);
    queue.push({ index: count++, name, done, fail });
    nodeTest(name, () => result);
  };
}
if (POOL) {
  // The worker loads the file, and jsdom with it, while the others start.
  const loaded = import(POOL).then(() => dom());
  loaded.catch(() => {});
  parentPort.on('message', async ({ index, name }) => {
    try {
      await loaded;
      const c = registered[index];
      assert.ok(c && c.name === name, `case ${index} of ${POOL} is "${name}" in the worker too`);
      await c.fn();
      parentPort.postMessage({ ok: true });
    } catch (e) {
      parentPort.postMessage({ ok: false, message: String(e && e.message), stack: String(e && e.stack) });
    }
  });
}

// The owner reads the board in Eastern time; the page formats in the process's local zone.
process.env.TZ = 'America/New_York';
// jsdom is loaded at the first boot, not on import: a file that takes only the snapshots (fit) never needs it. Each
// worker loads it again, so its compiled code is kept on disk (Node's own cache, in the temp folder) for the next.
enableCompileCache();
let jsdom = null;
const dom = () => jsdom || (jsdom = createRequire(import.meta.url)('jsdom'));
export const VIEW = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', '..', 'dashboard');
export const read = (name) => fs.readFileSync(path.join(VIEW, name), 'utf8');
// The kinds of Needs you, as dashboard.sh sends them (needs.kinds): the list the Foreman watcher reads too.
export const KINDS = JSON.parse(fs.readFileSync(path.join(VIEW, '..', 'scripts', 'dashboard_needs.json'), 'utf8'));
export const html = read('index.html');
export const css = read('app.css');
export const LIST = (() => { const window = {}; new Function('window', read('panels/index.js'))(window); return window.DASH_PANELS; })();
export const T0 = Date.parse('2026-11-09T17:00:00Z');
export const STORE = 'conveyor-board-layout';
export const SEEN = 'conveyor-board-seen';
export const iso = (ms) => new Date(ms).toISOString().replace(/\.\d{3}Z$/, 'Z');
export const clone = (x) => JSON.parse(JSON.stringify(x));

// The Board changes the loop: it is on the Control tab; the Rules panel is a tab of its own, Rules, and Belt 3D
// one of its own, Belt 3D, and the Tests panel one of its own, Tests; every other panel reports, on Overview.
// The Board's part and the Rules part are each drawn as more than one panel, [id, title] in their default order.
export const SPLIT = {
  board: [['board-loop', 'Loop'], ['board-push', 'Push landed and full test suite'], ['board', 'Board']],
  rules: [['rules', 'Rules'], ['rules-produce', 'What these rules produce'], ['rules-prices', 'Model prices'], ['rules-held', 'Held by you or a label'], ['rules-issues', 'Open issues']],
};
// The panels drawn from one part of the list: the part's own panel, or each one SPLIT names for it.
export const family = (id) => (SPLIT[id] ? SPLIT[id].map(([x]) => x) : [id]);
// A panel's heading: SAYS's for a part's own panel, SPLIT's for another panel drawn from a part.
export const titleOf = (id) => (SAYS[id] ? SAYS[id].title : Object.values(SPLIT).flat().find(([x]) => x === id)[1]);
export const CONTROL_IDS = ['machine', ...family('board')];
export const RULES_IDS = family('rules');
// Their default widths: the rules beside what they produce, every other one the tab's width.
export const CONTROL_SIZES = { machine: 'full', 'board-loop': 'full', 'board-push': 'full', board: 'full' };
export const RULES_SIZES = { rules: 'wide', 'rules-produce': 'small', 'rules-prices': 'full', 'rules-held': 'full', 'rules-issues': 'full' };
export const BELT3D_IDS = ['belt3d'];
export const TESTS_IDS = ['tests'];
export const TAB = (id) => (CONTROL_IDS.includes(id) ? 'control' : RULES_IDS.includes(id) ? 'rules' : BELT3D_IDS.includes(id) ? 'belt3d' : TESTS_IDS.includes(id) ? 'tests' : 'overview');
export const OVERVIEW = LIST.filter((id) => TAB(id) === 'overview');

// One page in jsdom. `store` is what an earlier visit left in localStorage; `list` and `extra` stand in for
// panels/index.js and for panel files of the test's own; `tab` is the tab the address opens (none: the page's own).
export function boot({ store = {}, reducedMotion = false, list = LIST, extra = '', rects = false, feed = false, tab = null, query = '', width = 1440 } = {}) {
  const { JSDOM, VirtualConsole } = dom();
  const virtualConsole = new VirtualConsole();
  const w = new JSDOM(html, { url: `https://dash.test/index.html${tab ? `?tab=${tab}` : query}`, runScripts: 'outside-only', virtualConsole }).window;
  w.navigations = 0;
  // jsdom cannot navigate: a page that goes to the login, or reloads itself, is seen as this report.
  virtualConsole.on('jsdomError', (e) => { if (/navigation/.test(e.message)) w.navigations += 1; else throw e; });
  w.clock = T0;
  w.Date.now = () => w.clock;
  for (const [k, v] of Object.entries(store)) w.localStorage.setItem(k, v);
  // The viewport is `width` wide: a max-width query matches at or under it.
  w.matchMedia = (q) => {
    const max = /max-width: (\d+)px/.exec(q);
    return { matches: (reducedMotion && /prefers-reduced-motion: reduce/.test(q)) || (max !== null && width <= Number(max[1])), addEventListener() {} };
  };
  // jsdom's page is hidden (it is not drawn): the fake page is in view unless the test hides it (seen(w, false)).
  w.pageHidden = false;
  Object.defineProperty(w.document, 'hidden', { configurable: true, get: () => w.pageHidden });
  w.intervals = [];
  w.setInterval =(fn, ms) => { w.intervals.push({ fn, ms }); return w.intervals.length; };
  // A timer runs when the test says so (`later`), never on its own.
  w.timeouts = [];
  w.setTimeout = (fn, ms) => { w.timeouts.push({ fn, ms }); return w.timeouts.length; };
  w.frames = [];
  w.requestAnimationFrame = (fn) => { w.frames.push(fn); return w.frames.length; };
  w.posts = [];
  // The history (GET history): w.historyBody (never w.history: that is the window's own) is what the server gives ({panels}); with none, it answers 404 and the
  // panels keep their live parts. w.historyAsks counts the asks.
  w.historyAsks = 0;
  w.fetch = (url, opt) => {
    if (/^alive\.js\?\d+$/.test(url)) return Promise.resolve(w.aliveReply || { ok: true, status: 200, redirected: false, url: 'https://dash.test/alive.js' });
    if (url === 'history') {
      assert.equal(opt, undefined, 'the history is read with a plain GET');
      w.historyAsks += 1;
      return Promise.resolve(w.historyBody ? { ok: true, status: 200, json: () => Promise.resolve(w.historyBody) } : { ok: false, status: 404 });
    }
    assert.ok(['answer', 'restart', 'control', 'machine'].includes(url), `the page writes to nothing but its own answer, restart, control and machine addresses: ${url}`);
    assert.equal(opt.method, 'POST');
    assert.equal(opt.headers['Content-Type'], 'application/json');
    w.posts.push({ url, body: JSON.parse(opt.body) });
    return Promise.resolve(w.reply || { ok: true, status: 200, text: () => Promise.resolve('sent to main') });
  };
  // jsdom lays nothing out: with `rects` every panel is given a box by its place in the grid, so a move is a move.
  if (rects) {
    w.Element.prototype.getBoundingClientRect = function () {
      const i = this.parentNode ? Array.from(this.parentNode.children).indexOf(this) : 0;
      return { left: 0, top: i * 100, right: 300, bottom: i * 100 + 90, width: 300, height: 90 };
    };
  }
  // `feed`: the browser has EventSource. Each one the page opens is kept in w.sources; the test sends its events.
  w.sources = [];
  if (feed) {
    w.EventSource = class {
      constructor(url) { this.url = url; this.readyState = 0; this.on = {}; w.sources.push(this); }
      addEventListener(type, fn) { (this.on[type] = this.on[type] || []).push(fn); }
      close() { this.readyState = 2; }
      emit(type, data) { for (const fn of this.on[type] || []) fn(data === undefined ? { type } : { type, data: JSON.stringify(data) }); }
    };
  }
  w.eval(read('app.js'));
  w.eval(read('head.js'));
  w.DASH_PANELS = list.slice();
  for (const id of list) if (fs.existsSync(path.join(VIEW, 'panels', `${id}.js`))) w.eval(read(`panels/${id}.js`));
  if (extra) w.eval(extra);
  w.DASH_APP.start();
  return w;
}
export const $ = (w, sel) => w.document.querySelector(sel);
export const panel = (w, id) => w.document.getElementById(`panel-${id}`);
export const state = (w, id) => panel(w, id).dataset.state;
export const order = (w) => Array.from(w.document.getElementById('grid').children).filter((p) => !p.hidden).map((p) => p.dataset.panel);
export const saved = (w) => JSON.parse(w.localStorage.getItem(STORE));
// The layout kept for one tab (each tab keeps its own).
export const kept = (w, tab = 'overview') => saved(w).tabs[tab];
// Cost is one column wide, so on a wide screen it fills the right column under Lanes (UX36).
export const SIZES0 = { needs: 'wide', belt: 'wide', queue: 'small', landed: 'wide', release: 'small', declined: 'wide', health: 'small', lanes: 'small', cost: 'small', metrics: 'wide' };
// A panel's width and whether it shows are set in Customize only (its head has no width or hide button).
export function setSize(w, id, size) { const s = w.document.getElementById(`size-${id}`); s.value = size; s.dispatchEvent(new w.Event('change')); }
export const hidePanel = (w, id) => w.document.getElementById(`show-${id}`).click();
// The one project picker is Show, in the machine head over every tab (issue 408, UX34): the Board and the Rules have
// none of their own, and their heading names the project they show. It is drawn when the machine part names more
// than one project.
export function pickProject(w, repo) { const s = w.document.querySelector('#machine-head [data-act="project"]'); s.value = repo; s.dispatchEvent(new w.Event('change')); }
export const heading = (el) => el.querySelector('.panel-title').textContent;
export const settle = () => new Promise((r) => setImmediate(r));
export const pending = (w, name) => w.document.head.querySelector(`script[src^="${name}"]`);
// The page reads data.js by adding a script tag; the test answers it, as the browser would once the file ran.
export function deliver(w, data) {
  w.DASH = data;
  pending(w, 'data.js').dispatchEvent(new w.Event('load'));
}
export function refresh(w) { w.intervals.find((t) => t.ms === 15000).fn(); }
export function next(w, data) { refresh(w); deliver(w, data); }
export function tick(w, ms) { w.clock += ms; w.intervals.find((t) => t.ms === 1000).fn(); }
// seen(w, on): the page's tab is put in view (true) or in the background (false), as the browser tells the page.
export function seen(w, on) { w.pageHidden = !on; w.document.dispatchEvent(new w.Event('visibilitychange')); }
export function later(w) { for (const t of w.timeouts.splice(0)) t.fn(); }
export function key(w, el, k) { el.dispatchEvent(new w.KeyboardEvent('keydown', { key: k, bubbles: true, cancelable: true })); }

export const P = 'https://github.com/example/sample-project/issues';
// A card's track as the snapshot gives it: the six steps, `marks` one character a step (+ done, > now,
// - skipped, ! failed, . todo), a done step 30 s plus its place; the step in progress began 5 minutes ago. Review and
// Fix carry their rounds (n), the detail every recorded step. No time is estimated.
export const STEPS = ['Build', 'Review', 'Fix', 'Test', 'Land', 'Push'];
export const DETAIL = ['queued', 'picked', 'worktree ready', 'dependencies linked', 'brief written', 'building', 'review 1', 'fix 1', 'review 2', 'fix 2', 'review 3', 'tests', 'rebuild', 'landing', 'pushed', 'issue closed', 'follow-ups filed'];
const MARK = { '+': 'done', '>': 'now', '-': 'skipped', '!': 'failed', '.': 'todo' };
export function trackOf(marks, label, over = {}, now = T0) {
  const at = marks.search(/[>!]/);
  const steps = STEPS.map((name, i) => ({ name, state: MARK[marks[i]], sec: marks[i] === '+' ? 30 + i : null }));
  steps[1].n = 1; steps[1].of = 3; steps[2].n = 0;
  return { steps, at: at < 0 ? null : at, label, since: iso(now - 300000), reason: null, files: null,
    detail: DETAIL.map((name, i) => ({ name, state: i < 6 ? 'done' : 'todo', sec: i < 6 ? 60 : null })), detailAt: null, ...over };
}
// A card's start and overall time: picked up 40 minutes ago; resumed, a kept patch's 20 minutes before it.
export const timesOf = (now = T0, priorSec = 0) => ({ start: iso(now - 2400000 - priorSec * 1000), pickedAt: iso(now - 2400000), priorSec, totalSec: null });
export const counts = (P0, P1, P2, P3) => ({ P0, P1, P2, P3 });
// The CLIs installed on the loop's host, each with the models it lists (Claude Code lists none: its model is typed in)
// and the efforts it takes in a role (the OpenCode builder none).
const EFF = { claude: ['low', 'medium', 'high', 'xhigh', 'max'], codex: ['minimal', 'low', 'medium', 'high', 'xhigh'], opencode: ['minimal', 'low', 'medium', 'high', 'xhigh', 'max'] };
export const CLIS = { claude: { models: null, efforts: EFF.claude }, codex: { models: ['gpt-6.1-sol', 'gpt-6-astra', 'gpt-6.1-terra'], efforts: EFF.codex },
  opencode: { models: ['openrouter/vendor/m-1', 'prov/m-2'], efforts: EFF.opencode } };
// allowed: the pack's models.allowed by CLI, what the Board offers for a CLI that lists none (Claude Code).
export const CLAUDE4 = ['claude-opus-5-5', 'claude-fable-5-2', 'claude-sonnet-5-5', 'claude-haiku-5-5'];
export const MODELS = {
  builder: { model: 'claude-opus-5-5', effort: 'high', agent: 'claude', modelFrom: 'control', effortFrom: 'control', choices: ['claude-fable-5-2', 'claude-opus-5-5'], efforts: EFF.claude,
    allowed: { claude: CLAUDE4, opencode: [], codex: [] }, clis: { ...CLIS, opencode: { ...CLIS.opencode, efforts: [] } }, missing: null },
  reviewer: { model: 'gpt-6.1-sol', effort: 'medium', agent: 'codex', modelFrom: 'seed', effortFrom: 'seed', choices: ['gpt-6.1-sol', 'gpt-6-astra'], efforts: EFF.codex,
    allowed: { codex: ['gpt-6.1-sol', 'gpt-6-astra'], claude: [], opencode: [] }, clis: CLIS, missing: null },
  // The review's judge: its models are every one the pack allows the review and its CLIs every one installed, the
  // reviewer's Codex too; the reviewer is Codex's, so its default is the first Claude one.
  judge: { model: 'claude-opus-5-5', effort: 'medium', agent: 'claude', modelFrom: 'seed', effortFrom: 'seed', choices: ['gpt-6.1-sol', 'gpt-6-astra', 'claude-opus-5-5', 'claude-sonnet-5-5'], efforts: EFF.claude, default: 'claude-opus-5-5',
    allowed: { codex: ['gpt-6.1-sol', 'gpt-6-astra'], claude: ['claude-opus-5-5', 'claude-sonnet-5-5'], opencode: [] }, clis: CLIS, missing: null },
};
export const CONTROL = { mode: 'run', cap: null, guard: 90, held: [76], order: [], rules: { P0: true, P1: true, P2: true, followups: true, never: ['area:infra'] }, model: { cli: 'claude', model: 'claude-opus-5-5', effort: 'high' }, reviewer: null,
  judge: null, judgeOn: false, judgeAlways: [], start: 'queue', startHeld: [], startSeen: [], depGuard: true, forced: [] };
// What Conveyor measured: one record's totals, and one card's measurements as the snapshot gives them.
export const METRIC_TOTALS = { cards: 4, landed: 2, blocked: 2, leadSec: { p50: 7110, p90: 8460 }, cycleSec: { p50: 1710, p90: 2160 }, firstReviewPass: 0.667, findingsPerCard: 1,
  followupRate: 0.5, blockRate: 0.5, blocks: { timeout: 1, 'visible change': 1 }, rebuildRate: 0,
  perLanded: { usd: 4.5, tokens: 2250000, byModel: { 'claude-sonnet-5-5': { usd: 3, tokens: 1500000 } } }, waitMaxSec: null, limitPerCard: 2,
  loop: { samples: 4, utilisation: 0.438, slotsMax: 4, idleSec: 60, heldSec: 60 }, pushes: { ok: 1, failed: 1, sec: { p50: 30, p90: 30 }, failSec: { p50: 900, p90: 900 } },
  host: { loadMax: 4.5, memUsedMaxKb: 12582912, diskFreeMinKb: 8996 } };
// The 7 days before (8 landed, slower, fewer passed first review, dearer), each of the 7 days, and today's slots by hour.
export const METRIC_PREV = { ...METRIC_TOTALS, cards: 10, landed: 8, blocked: 2, cycleSec: { p50: 2000, p90: 2600 }, firstReviewPass: 0.5,
  perLanded: { usd: 5, tokens: 2500000, byModel: { 'claude-sonnet-5-5': { usd: 3.5, tokens: 1700000 } } } };
export const METRIC_DAYS = [[3, 1, 0, 1500, 1, 3], [4, 0, 0, null, null, null], [5, 2, 1, 1800, 0.5, 4], [6, 1, 0, 1600, 1, 5], [7, 1, 0, 1700, 0.5, 4.5], [8, 0, 1, null, null, null],
  [9, 2, 2, 1710, 0.667, 4.5]].map(([dd, landed, blocked, cycleSec, firstReviewPass, perLandedUsd]) => ({ day: `2026-11-0${dd}`, landed, blocked, cycleSec, firstReviewPass, perLandedUsd }));
export const METRIC_SLOTS = [{ hour: 0, slots: 3, cap: 4 }, { hour: 5, slots: 0.5, cap: 4 }, { hour: 9, slots: 2, cap: 4 }];
export const CARD_METRICS = { queueSec: 3600, slotSec: 60, buildSec: 600, reviewSec: 600, fixSec: 600, testSec: 300, rebuildSec: null, landSec: 60, pushSec: 240, waitMaxSec: null,
  leadSec: 5760, cycleSec: 2160, reviews: 2, firstReview: 'NO-GO', findings: counts(0, 2, 1, 0), rebuilds: 0, retries: 0, blockClass: null, depth: 0, followups: 0,
  diff: { files: 2, added: 30, removed: 4 }, limit: { before: 10, after: 12, used: 2 }, usd: 6, tokens: 3000000, unpriced: 0,
  timeline: [
    { step: 'build', result: 'ok', time: '2026-11-09T01:10:00Z', sec: 600, tokens: 1000000, usd: 2, model: 'claude-sonnet-5-5', effort: 'medium', counts: null, tests: null, stats: { turns: 12, apiSec: 420, tools: { Bash: 5, Edit: 2 }, refused: 1, cacheHit: 0.97, models: ['claude-opus-5-5'] }, unpriced: null },
    { step: 'review', result: 'NO-GO', time: '2026-11-09T01:15:00Z', sec: 300, tokens: 500000, usd: 1, model: 'gpt-6.1-sol', effort: null, counts: counts(0, 2, 1, 0), tests: null, stats: null, unpriced: null },
    { step: 'test', result: 'fail', time: '2026-11-09T01:35:00Z', sec: 300, tokens: 0, usd: 0, model: null, effort: null, counts: null, tests: { files: 3, total: 12, passed: 9, failed: 1, skipped: 2 }, stats: null, unpriced: null },
  ] };
// The snapshot's tests part (conveyor/lib/testfiles.sh testspart(), as dashboard.sh tags its runs): three files. e2e is
// over the budget but slow on purpose; merge is over it, slower than usual, waits (2.5 times its CPU on the clock),
// flaky, failed in 2 steps and has an issue; the Board one is faster than its median. 39 test steps in 7 days.
const run = (cpu, sec, n, h) => ({ cpu, sec, card: `c${h}-${n}`, time: iso(T0 - h * 3600000), issue: n, repo: 'sample', url: `${P}/${n}` });
const file = (o) => ({ runs: [], timedRuns: 6, failedSteps: 0, flaky: 0, issue: null, budget: 8, budgetFrom: 'project', slowOnPurpose: null, slower: false, ...o });
export const TESTS = {
  settings: { fileBudget: 8, slowIssues: false, slower: { share: 0.25, runs: 3, minRuns: 5 }, files: { 'conveyor/tests/e2e.test.sh': { slowOnPurpose: 'runs the whole loop' } } },
  files: [
    file({ file: 'conveyor/tests/e2e.test.sh', cpu: 40, median: 39, change: 0.026, runs: [run(40, 30, 509, 1)], lastRun: { sec: 30, cpu: 40, clockPerCpu: 0.75 },
      slowOnPurpose: 'runs the whole loop', over: true, usual: 39 }),
    file({ file: 'conveyor/tests/merge.test.sh', cpu: 12, median: 6, change: 1, runs: [run(12, 30, 509, 1), run(11.5, 14, 451, 2), run(11, null, 435, 3)],
      lastRun: { sec: 30, cpu: 12, clockPerCpu: 2.5 }, timedRuns: 7, failedSteps: 2, flaky: 1, issue: 480, over: true, usual: 6, slower: true }),
    file({ file: '.claude/scripts/__tests__/x.test.mjs', cpu: 2, median: 4, change: -0.5, runs: [run(2, 2.2, 509, 1)], lastRun: { sec: 2.2, cpu: 2, clockPerCpu: 1.1 },
      over: false, usual: 4 }),
  ],
  slower: ['conveyor/tests/merge.test.sh'],
  totals: { files: 3, overBudget: 1, slower: 1, steps: { count: 39, waitSec: 120, runSec: 3600 } },
};

export function full(now = T0) {
  return {
    updatedAt: iso(now - 20000),
    panels: {
      // The machine's one Conveyor: one project on it, with its own Foreman, and no machine cap set.
      machine: { error: null, data: {
        host: 'buildhost', state: 'running', cap: null, used: 2, todayUsd: 4.25, todayLeftOut: 0, repos: ['sample'],
        projects: [{ repo: 'sample', state: 'running', reason: null, loop: true, mode: 'run', cap: 3, used: 2,
          needs: [{ repo: 'sample', card: 'c3-12', issue: 12, title: 'Button copy', url: `${P}/12` }],
          belt: [{ repo: 'sample', card: 'c1-57', issue: 57, title: 'Rebuild the dashboard', url: `${P}/57`, step: 'review' }],
          queue: [{ repo: 'sample', card: null, issue: 20, title: 'Next up', url: `${P}/20` }], held: [{ repo: 'sample', card: null, issue: 76, title: 'Split the PROD stack', url: `${P}/76` }],
          order: [21], rules: clone(CONTROL.rules), models: { builder: { model: 'claude-opus-5-5', effort: 'high' }, reviewer: { model: 'gpt-6.1-sol', effort: 'medium' } },
          landedToday: 2, todayUsd: 4.25 }],
        foremen: [{ projects: ['sample'], group: false, held: true, since: iso(now - 7200000), lastWakeAt: iso(now - 600000), waiting: ['Conveyor: sample: blocked: #13'] }],
        foremenError: null,
      } },
      // The Board: the loop on the host's main, as dashboard.sh cuts it from that record's snapshot.
      board: { error: null, data: {
        repo: 'sample', state: 'running', loop: true, commit: 'abc1234def5678abc1234def5678abc1234def56', control: clone(CONTROL), cap: 3,
        guard: { at: 90, reading: 44, readAt: iso(now - 60000), missing: false }, modelSettings: clone(MODELS), limit: { pct: 44, from: 'loop' },
        held: [{ repo: 'sample', card: null, issue: 76, title: 'Split the PROD stack', url: `${P}/76` }],
        queue: [
          { repo: 'sample', card: null, issue: 20, title: 'Next up', url: `${P}/20`, priority: 'P1', followup: true, retried: false },
          { repo: 'sample', card: null, issue: 21, title: 'Later', url: `${P}/21`, priority: 'P2', followup: false, retried: true },
          { repo: 'sample', card: null, issue: 22, title: 'Last', url: `${P}/22`, priority: 'P2', followup: false, retried: false },
        ],
        skipped: [{ repo: 'sample', card: null, issue: 23, title: 'Infra thing', url: `${P}/23`, rule: 'area:infra' }],
        issuesError: null,
        building: [{ repo: 'widgetshop', card: 'c4-5', issue: 5, title: 'Plugin thing', url: null, step: 'build', stepAt: iso(now - 60000), usd: null, reading: false }],
        review: [{ repo: 'sample', card: 'c3-63', issue: 63, title: 'Rebuild the dashboard', url: `${P}/63`, review: 2, of: 3, stepAt: iso(now - 300000), usd: 1.25, reading: true }],
        waiting: [{ repo: 'sample', card: 'c1-12', issue: 12, title: 'Button copy', url: `${P}/12`, sentence: 'Staff see a new button.', since: iso(now - 600000) }],
        blocked: [{ repo: 'sample', card: 'c2-13', issue: 13, title: 'Broken build', url: `${P}/13`, reason: 'tests failed twice', since: iso(now - 900000) }],
        landed: [
          { repo: 'sample', card: 'c5-7', issue: 7, title: 'Landed one', url: `${P}/7`, step: 'landed', time: iso(now - 3600000), usd: 2.5, reviews: 2 },
          { repo: 'sample', card: 'c6-8', issue: 8, title: 'Fixed before', url: `${P}/8`, step: 'closed', time: iso(now - 7200000), usd: 0.5, reviews: 1 },
        ],
        today: { landed: 2, usd: 3 },
      } },
      // The Rules panel: the same record's rules, and what they produce as the snapshot's forecast says.
      // With the loop's state, the models, the limit reading, the waits and every held issue with its labels.
      rules: { error: null, data: {
        repo: 'sample', state: 'running', control: { ...clone(CONTROL), order: [21] }, cap: 3, areaPrefix: 'area:',
        guard: { at: 90, reading: 44, readAt: iso(now - 60000), missing: false }, modelSettings: clone(MODELS), limit: { pct: 44, from: 'loop' },
        held: [{ repo: 'sample', card: null, issue: 76, title: 'Split the PROD stack', url: `${P}/76` }],
        queue: [
          { repo: 'sample', card: null, issue: 21, title: 'Later', url: `${P}/21`, priority: 'P2', followup: false, retried: true, areas: [] },
          { repo: 'sample', card: null, issue: 20, title: 'Next up', url: `${P}/20`, priority: 'P1', followup: true, retried: false, areas: ['area:web'] },
          { repo: 'sample', card: null, issue: 22, title: 'Last', url: `${P}/22`, priority: 'P2', followup: false, retried: false, areas: ['area:web'] },
        ],
        skipped: [{ repo: 'sample', card: null, issue: 23, title: 'Infra thing', url: `${P}/23`, rule: 'area:infra' }],
        waits: [{ repo: 'sample', card: null, issue: 24, title: 'Second half', url: `${P}/24`, priority: 'P2', followup: false, retried: false, waitsFor: [20] }],
        issuesError: null, building: 2,
        forecast: { cards: 3, usd: 2.85, perCard: { usd: 0.95, pct: 0.5 }, guard: 90, reading: 44, pausesAt: null },
        open: { count: 9, split: { queued: 3, you: 1, labelOrRule: 3, belt: 2 }, held: [
          { repo: 'sample', card: null, issue: 76, title: 'Split the PROD stack', url: `${P}/76`, priority: 'P1', labels: ['P1', 'area:infra'], reasons: [{ kind: 'you' }] },
          { repo: 'sample', card: null, issue: 35, title: 'Copy tweak', url: `${P}/35`, priority: 'P2', labels: ['P2', 'area:web', 'ux-change'], reasons: [{ kind: 'label', label: 'ux-change' }] },
          { repo: 'sample', card: null, issue: 23, title: 'Infra thing', url: `${P}/23`, priority: 'P2', labels: ['area:infra'], reasons: [{ kind: 'rule', rule: 'area:infra' }] },
          { repo: 'sample', card: null, issue: 24, title: 'Second half', url: `${P}/24`, priority: 'P2', labels: [], reasons: [{ kind: 'waits', waitsFor: [20] }] },
        ] },
      } },
      needs: { error: null, data: {
        cards: {
          waiting: [{ repo: 'sample', card: 'c1-12', issue: 12, title: 'Button copy', sentence: 'Staff see a new button.', since: iso(now - 600000), url: `${P}/12` }],
          blocked: [{ repo: 'sample', card: 'c2-13', issue: 13, title: 'Broken build', reason: 'tests failed twice', since: iso(now - 900000), url: `${P}/13` }],
        },
        cardsError: null,
        decisions: [{ repo: 'bookshop', id: 'q-ship', askedAt: '2026-11-09T10:00:00Z', question: 'Ship it?', options: ['Yes', 'No'], proposedDefault: 'Yes', source: 'main' }],
        decisionsError: null,
        kinds: KINDS, entries: {},
      } },
      belt: { error: null, data: { cap: 3, cards: [
        { repo: 'sample', card: 'c3-63', issue: 63, title: 'Rebuild the dashboard', url: `${P}/63`, parent: 58, step: 'review', review: 2, of: 3, stepAt: iso(now - 300000), model: 'gpt-x', tokens: { claude: 400000, codex: 12300 }, usd: 1.25, reading: true,
          reviews: [{ round: 1, verdict: 'NO-GO', counts: counts(0, 1, 2, 0), sec: 200, fixed: true }], ...timesOf(now),
          track: (() => { const t = trackOf('++>...', 'review 2 of 3', {}, now); t.steps[1].n = 2; t.steps[2].n = 1; t.steps[2].state = 'done'; t.steps[2].sec = 32; t.steps[1].state = 'now'; t.at = 1; return t; })() },
        { repo: 'widgetshop', card: 'c4-5', issue: 5, title: 'Plugin thing', url: null, parent: null, step: 'build', review: null, of: 3, stepAt: iso(now - 60000), model: 'claude-x', tokens: { claude: 0, codex: 0 }, usd: null, reading: false,
          reviews: [], ...timesOf(now), track: (() => { const t = trackOf('>.....', 'building', { since: iso(now - 60000) }, now); t.steps[1].n = 0; return t; })() },
      ] } },
      // Belt 3D: the same belt, Needs you, queue and landed cards, cut for it: a card in Review, one in Build and one
      // in Test, a card waiting for the owner's yes and a blocked one, two queued, one held, one waiting on #20 and two landed.
      belt3d: { error: null, data: { repos: ['sample', 'widgetshop'], byRepo: {},
        belt: [
          { repo: 'sample', card: 'c3-63', issue: 63, title: 'Rebuild the dashboard', url: `${P}/63`, step: 'review', stepAt: iso(now - 300000), landed: false, waitsOn: null, usd: 1.25, turns: 4,
            reviews: [{ round: 1, verdict: 'NO-GO', counts: counts(0, 1, 2, 0) }],
            // Its records (name and at, as dashboard.sh cuts them): Review 1, Fix 1, then back to Review 2 (issue 423).
            track: (() => { const t = trackOf('++>...', 'review 2 of 3', {}, now); t.steps[1].n = 2; t.steps[1].state = 'now'; t.steps[2].state = 'done'; t.at = 1;
              const records = [{ name: 'queued', at: iso(now - 2400000) }, { name: 'building', at: iso(now - 1800000) }, { name: 'review 1 (NO-GO)', at: iso(now - 900000) },
                { name: 'fix 1', at: iso(now - 300000) }, { name: 'review 2 of 3', at: null }];
              return { steps: t.steps, at: 1, since: t.since, tests: null, files: null, records }; })() },
          { repo: 'widgetshop', card: 'c4-5', issue: 5, title: 'Plugin thing', url: null, step: 'build', stepAt: iso(now - 60000), landed: false, waitsOn: null, usd: null, turns: null, reviews: [],
            track: { steps: trackOf('>.....', 'building').steps, at: 0, since: iso(now - 60000), tests: null, files: null } },
          { repo: 'sample', card: 'c7-9', issue: 9, title: 'Same file', url: `${P}/9`, step: 'tests', stepAt: iso(now - 120000), landed: false, waitsOn: null, usd: 0.5, turns: 0,
            reviews: [{ round: 1, verdict: 'GO', counts: counts(0, 0, 0, 0) }],
            track: { steps: trackOf('++->..', 'tests').steps, at: 3, since: iso(now - 120000), tests: { done: 142, of: 205, failed: 0 }, files: { run: 1, of: 2 } } },
        ],
        queue: {
          next: [{ repo: 'sample', issue: 20, title: 'Next up', url: `${P}/20` }, { repo: 'sample', issue: 21, title: 'Later', url: `${P}/21` }],
          held: [{ repo: 'sample', issue: 76, title: 'Split the PROD stack', url: `${P}/76` }],
          waiting: [{ repo: 'sample', issue: 24, title: 'Second half', url: `${P}/24`, waitsFor: [20] }],
        },
        needs: [
          { repo: 'sample', card: 'c1-12', issue: 12, title: 'Button copy', url: `${P}/12`, kind: 'waiting', reason: 'Visible change: Staff see a new button.', since: iso(now - 600000), reviews: [], usd: null, track: null },
          { repo: 'sample', card: 'c2-13', issue: 13, title: 'Broken build', url: `${P}/13`, kind: 'blocked', reason: 'tests failed twice', since: iso(now - 900000),
            reviews: [{ round: 1, verdict: 'GO', counts: null }], usd: 0.75, track: { steps: trackOf('++-!..', null).steps, at: null, since: null, tests: { done: 40, of: 40, failed: 3 }, files: null } },
        ],
        landed: [
          { repo: 'sample', card: 'c5-7', issue: 7, title: 'Landed one', url: `${P}/7`, time: iso(now - 3600000), usd: 2.5, reviews: [{ round: 1, verdict: 'NO-GO', counts: counts(0, 1, 0, 0) }, { round: 2, verdict: 'GO', counts: null }] },
          { repo: 'sample', card: 'c6-8', issue: 8, title: 'Fixed before', url: `${P}/8`, time: iso(now - 7200000), usd: 0.5, reviews: [] },
        ],
        // What the deck behind the floor reads out: the host, the machine's state and the belt's slots in use of those
        // in force, as the head's "On the belt" tile (the belt part above: 2 of 3).
        deck: { host: 'buildhost', state: 'running', used: 2, cap: 3 } } },
      queue: { error: null, data: { next: [
        { repo: 'sample', issue: 20, title: 'Next up', priority: 'P1', followup: true, retried: false, url: `${P}/20` },
        { repo: 'sample', issue: 21, title: 'Later', priority: 'P3', followup: false, retried: true, url: `${P}/21` },
      ], held: 2, awaitingDeploy: [
        { repo: 'sample', issue: 76, title: 'Stack split', since: iso(now - 2 * 86400000), url: `${P}/76` },
        { repo: 'sample', issue: 35, title: 'No label time', since: null, url: `${P}/35` },
      ], issuesError: null } },
      landed: { error: null, data: { day: '2026-11-09', cards: [
        { repo: 'sample', card: 'c5-7', issue: 7, title: 'Landed one', url: `${P}/7`, step: 'landed', time: iso(now - 3600000), start: iso(now - 5400000), tookSec: 1800, usd: 2.5, reviews: 2, followups: [31], sha: 'abc', pushed: true },
        { repo: 'sample', card: 'c6-8', issue: 8, title: 'Fixed before', url: `${P}/8`, step: 'closed', time: iso(now - 7200000), start: iso(now - 7800000), tookSec: 600, usd: 0.5, reviews: 1, followups: [], sha: '', pushed: null },
      ] } },
      // Release: main two commits past v1.2.0, the next version's notes not on main, and no run yet.
      release: { error: null, data: { records: [{ repo: 'sample', suites: [], release: { tag: 'v1.2.0', count: 2, next: '1.3.0', notes: false, head: 'b'.repeat(40),
        commits: [{ sha: 'b'.repeat(40), subject: 'feat: Board panel' }, { sha: 'a'.repeat(40), subject: 'fix: A fix' }] } }] } },
      // Declined: the collector gives them newest first; the older one was filed as #90 by "File as issue", so it is in
      // the rest the panel shows under "Show every line".
      declined: { error: null, data: { lines: [
        { repo: 'sample', id: 'd0123456789ab', time: iso(now - 1800000), card: 'c3-63', issue: 63, url: `${P}/63`, finding: '[P1] b.txt:2 no mark here', by: 'judge', why: 'its proof needs a stub built to misbehave', built: null, dismissed: null },
      ], rest: [
        { repo: 'sample', id: 'dba9876543210', time: iso(now - 7200000), card: 'c5-7', issue: 7, url: `${P}/7`, finding: '[P2] a.txt:1 wrong word', by: 'code', why: 'follow-up of a follow-up', built: 90, dismissed: null },
      ] } },
      health: { error: null, data: {
        host: { name: 'buildhost', reachable: true, error: null },
        records: [{ repo: 'sample', loop: true, newest: iso(now - 30000), stuck: [], unpushed: [], pushError: null, pushFailingSince: null, lastPushAt: iso(now - 7200000), gh: true, diskFreeKb: 500000000, builderCap: 3, models: {} }],
        limit: { usedPct: 44, goalPct: 57, underPts: 13, paceSec: 1, timeLeftSec: 259200, resetsAt: iso(now + 259200000), fiveHour: { usedPct: 15 }, codex: { usedPct: 20 }, reading: 'fresh' },
        limitError: null,
        limits: [{ repo: 'sample', account: null, uses: ['build', 'review'], pct: 44, readAt: iso(now - 60000), email: 'noreply-a@example.com' }],
      } },
      lanes: { error: null, data: { records: [{
        repo: 'sample',
        fast: { present: true, branch: 'fix-123-fast', ahead: 2, subject: 'Second lane commit', first: 'First lane commit', dirty: 1, run: null, landing: { state: 'belt', card: 'c9-123', step: 'review', review: 1, of: 3, since: iso(now - 120000) } },
        research: { present: true, branch: 'research-notes', ahead: 0, subject: null, first: null, dirty: 0, run: { startedAt: iso(now - 3600000), lastAt: iso(now - 60000), active: true, topic: 'Compare OCR vendors' } },
      }], cardsError: null } },
      cost: { error: null, data: {
        cards: { day: '2026-11-09', todayUsd: 4.25, weekUsd: 14, perLandedUsd: 1, landedAfter: { 1: 3, 2: 1, 3: 0, more: 0 }, unpricedSteps: 0, perCard: [
          { repo: 'sample', card: 'c3-63', issue: 63, title: 'Rebuild the dashboard', url: `${P}/63`, todayUsd: 1.25, weekUsd: 1.25, state: 'on the belt' },
          { repo: 'sample', card: 'c5-7', issue: 7, title: 'Landed one', url: `${P}/7`, todayUsd: 2.5, weekUsd: 2.5, state: 'landed' },
          { repo: 'sample', card: 'c0-6', issue: 6, title: 'Landed days ago', url: `${P}/6`, todayUsd: 0, weekUsd: 6.25, state: 'landed' },
          { repo: 'sample', card: 'c2-13', issue: 13, title: 'Broken build', url: `${P}/13`, todayUsd: 0.75, weekUsd: 3.5, state: 'blocked' },
        ] },
        cardsError: null, sessions: { todayUsd: 12.5, todayComplete: true, weekUsd: 80 }, sessionsError: null,
      } },
      // The Tests page: the same record's test files and test settings, and the machine's Load limit.
      tests: { error: null, data: { repo: 'sample', tests: clone(TESTS), machine: { maxLoad: 30, unread: false, cores: 16, load: 31.5 } } },
      metrics: { error: null, data: {
        records: [{ repo: 'sample', today: METRIC_TOTALS, week: { ...METRIC_TOTALS, cards: 9, landed: 7, blocked: 2 }, prev: METRIC_PREV, days: clone(METRIC_DAYS), slots: clone(METRIC_SLOTS) }],
        cards: [
          { repo: 'sample', card: 'c5-7', issue: 7, title: 'Landed one', url: `${P}/7`, state: 'landed', at: iso(now - 3600000), metrics: CARD_METRICS },
          { repo: 'sample', card: 'c0-9', issue: 9, title: 'Old record', url: `${P}/9`, state: 'blocked', at: iso(now - 7200000),
            metrics: { ...CARD_METRICS, leadSec: null, cycleSec: null, diff: null, depth: null, limit: { before: null, after: null, used: null }, findings: null, blockClass: 'timeout', timeline: [] } },
        ],
      } },
    },
  };
}
export const EMPTY = {
  machine: { host: 'buildhost', state: 'stopped', cap: null, used: 0, todayUsd: 0, todayLeftOut: 0, repos: [], projects: [], foremen: [], foremenError: null },
  board: { repo: null },
  rules: { repo: null },
  tests: { repo: null },
  needs: { cards: { waiting: [], blocked: [] }, cardsError: null, decisions: [], decisionsError: null, kinds: KINDS, entries: {} },
  belt: { cap: 3, cards: [] },
  belt3d: { repos: ['sample'], byRepo: {}, belt: [], queue: { next: [], held: [], waiting: [] }, needs: [], landed: [] },
  queue: { next: [], held: 0, awaitingDeploy: [], issuesError: null },
  landed: { day: '2026-11-09', cards: [] },
  release: { records: [] },
  declined: { lines: [], rest: [] },
  health: { host: { name: null, reachable: null, error: 'this checkout has no conveyor/host.json' }, records: null, limit: null, limitError: 'no reading' },
  lanes: { records: [], cardsError: null },
  cost: { cards: { day: '2026-11-09', todayUsd: 0, weekUsd: 0, perLandedUsd: null, landedAfter: { 1: 0, 2: 0, 3: 0, more: 0 }, unpricedSteps: 0, perCard: [] }, cardsError: null, sessions: { todayUsd: 0, todayComplete: true, weekUsd: 0 }, sessionsError: null },
  metrics: { records: [{ repo: 'sample', today: null, week: { ...METRIC_TOTALS, cards: 0 } }], cards: [] },
};
// What each panel must say in each of its three states.
export const SAYS = {
  machine: { title: 'Projects and Foremen', count: '1', data: ['sample', 'Running', '2 of 3 cards at once', '2 landed today', '$4.25 today', 'Needs you (1)', '#12', 'On the belt (1)', '#57', 'Queue (1)', '#20', 'Held (1)', '#76',
    'Pinned order (1)', '#21', 'Rules: builds P0, P1, P2, P3, follow-ups; never area:infra', 'Builder claude-opus-5-5 · high; reviewer gpt-6.1-sol · medium', 'Pause sample', 'Open its Board', 'Open its rules',
    'Foremen', 'Foreman of sample', 'A session holds the role', 'claimed 2 h 00 min ago', 'last woken 10 min ago', '1 waiting on it', 'Conveyor: sample: blocked: #13'],
  empty: 'No project on the build machine', failed: 'The Board could not read the projects' },
  board: { title: 'Board', count: '', data: ['Conveyor', 'Running', 'Pause sample after current', 'Stop now and requeue 2 cards', 'Weekly limit', '44%',
    '2 landed', '$3.00',
    'Held', 'Split the PROD stack', 'Held by you', 'Queue', 'Next up', 'next: 1', 'Follow-up', 'Later', 'next: 2', 'Retried', 'Infra thing', 'Skipped by a rule: area:infra',
    'Building', 'Plugin thing', 'building', 'no reading yet', 'Review', 'Rebuild the dashboard', 'review 2 of 3', '$1.25',
    'Needs you', 'Button copy', 'Visible change: Staff see a new button.', 'Waiting for your yes', 'Broken build', 'tests failed twice', 'Landed today', 'Landed one', '2 reviews · $2.50', 'Fixed before', 'already fixed'],
  empty: 'Nothing to steer here', failed: 'The Board could not read the Board panel' },
  rules: { title: 'Rules', count: '', data: ['The Board saves a rule when you change it.','Rules', 'Build', 'which issues Conveyor may pick', 'P0', 'P1', 'P2', 'P3', 'Follow-ups',
    'Turning P2 off would skip 2 of the 3 queued issues. Turning Follow-ups off would skip 1 of the 3 queued issues.',
    'Never build', 'labels Conveyor skips', 'area:infra', 'Cards at once', 'cards building together', 'the default', 'Pause when the weekly limit reaches', 'weekly Claude limit', 'Off', '90%', '95%', '98%', 'now at 44%',
    'Builder', 'builds and fixes', 'claude-opus-5-5 · high', 'Reviewer', 'reviews each round', 'gpt-6.1-sol · medium', 'Held by you or a label', '2 issues held', 'See them below',
    'Pinned', '#21 Later', 'Unpin',
    'What these rules produce', 'ready to build', 'waiting on another card', 'held by you or a label', 'skipped by a rule', 'Next up', '#21', 'Later', 'Last', 'Second half', 'waits on #20', 'ready',
    'Forecast for the queue: about $2.85.', 'Skipped', 'Infra thing', 'Conveyor never builds area:infra', 'Held by you or a label · 2', 'infra', 'web', '1 ux-change', 'Queue all'],
  empty: 'No rules to show', failed: 'The Board could not read the rules' },
  needs: { title: 'Needs you', count: '3', data: ['Button copy', 'Staff see a new button.', 'Waiting for your yes', 'Broken build', 'tests failed twice', 'Blocked', 'Ship it?', 'Retry puts #13 back in the queue, and a new card builds it in its turn.', 'Fix the cause. Then press Retry.'], empty: 'Nothing needs you', failed: 'The Board could not read Needs you' },
  belt: { title: 'On the belt', count: '2 of 3', data: ['Rebuild the dashboard', '↳ #58', 'Review 2 of 3', '5 min in this step', 'started 11:20 AM', '40 min overall', 'gpt-x', '$1.25 · 412k tokens so far', 'Plugin thing', 'Building', 'no reading yet',
    'Build', 'Fix', 'Test', 'Land', 'Push', 'Every step', 'Review 1: changes asked', '1 P1, 2 P2'], empty: 'The belt is empty', failed: 'The Board could not read the belt' },
  belt3d: { title: 'Belt 3D', count: '', data: ['Running3', 'Build1', 'Review1', 'Test1', 'Stuck2', 'Waiting1', 'Held1', 'Queued2', 'Landed2', '#63', 'Rebuild the dashboard', 'Review 2 · 5 min',
    'Test 142/205', 'Stuck at Test', 'tests failed twice', 'Waiting for your yes', 'Visible change: Staff see a new button.', 'Next up', 'next up', 'Second half', 'waits on #20, queued',
    'Split the PROD stack', 'held on the Board', 'Landed one', 'Landed 1 h 00 min ago'],
    empty: 'The floor is empty', failed: 'The Board could not read Belt 3D' },
  tests: { title: 'Tests', count: '', data: ['Files with a CPU time', 'conveyor/tests/merge.test.sh', 'Slower than usual', 'Test limits', 'Load limit'],
    empty: 'No tests to show', failed: 'The Board could not read the tests' },
  queue: { title: 'Queue', count: '2', data: ['Next up', 'P1', 'Follow-up', 'Later', 'Retried', 'Holds keep 2 issues back: see Held.','Built, waiting for your PROD deploy (2):', 'Stack split', '2 d 0 h waiting', 'No label time'], empty: 'The queue is empty', failed: 'The Board could not read the queue' },
  landed: { title: 'Landed today', count: '2', data: ['Landed one', '2 reviews', 'started 10:30 AM', '30 min overall', 'landed 11:00 AM', '$2.50', 'Landed and pushed', 'follow-ups #31', 'Fixed before', 'Already fixed', '2 cards, $3.00 at list prices'], empty: 'No card landed today', failed: 'The Board could not read the landed cards' },
  release: { title: 'Release', count: '', data: ['Newest release v1.2.0: 2 commits on main since it', 'bbbbbbb feat: Board panel', 'docs/releases/1.3.0.md is not on main yet', 'Release'],
    empty: 'No project to release', failed: 'The Board could not read the release state' },
  declined: { title: 'Declined', count: '1', data: ['#63', '[P1] b.txt:2 no mark here', 'declined by the judge', '30 min ago', 'Why: its proof needs a stub built to misbehave', 'File as issue',
    'Dismiss', 'Dismiss all shown (1)', 'Show every line'], empty: 'No declined finding', failed: 'The Board could not read the declined findings' },
  health: { title: 'Health', count: '', data: ['buildhost', 'Reachable', 'Conveyor', 'Running', 'Last push', 'All pushed', 'Usage limit', '44% of the 7-day limit used', 'account default, noreply-a@example.com: build and fix and reviews', '6 checks fine'], empty: 'No health reading yet', failed: 'The Board could not read Health' },
  lanes: { title: 'Lanes', count: '', data: ['Fast lane', 'Not committed', '1 file changed, not committed', 'on fix-123-fast', 'Landing: on the belt', 'review 1 of 3', 'Research lane', 'Working: Compare OCR vendors, last activity 1 min ago', 'on research-notes'], empty: 'No lanes set up', failed: 'The Board could not read the lanes' },
  cost: { title: 'Cost', count: '', data: ['$4.25', 'Cards today', '$14.00', 'Cards, last 7 days', '$1.00', 'Landed in the last 7 days: 3 after 1 review, 1 after 2 reviews.', 'Per card, last 7 days', 'Landed days ago', '$0.00 today', '$6.25 in 7 days', 'Broken build', 'Blocked', '$0.75 today', '$3.50 in 7 days', 'Every session on this machine: $12.50 today, $80.00 this limit week.'], empty: 'No spend in the last 7 days', failed: 'The Board could not read Cost' },
  metrics: { title: 'Metrics', count: '', data: ['Lead time (opened to landed)', '1 h 58 min (90th: 2 h 21 min)', 'Passed first review', '66.7%', 'Findings per card', 'Block rate', '50%: 1 timeout, 1 visible change',
    'Per landed card', '$4.50, 2.3M tokens', 'claude-sonnet-5-5 $3.00, 1.5M tokens', 'Waiting on the owner', '43.8% of the most on average, 4 at most', 'load 4.5 at most, disk free 0 GB at least, memory used 12 GB at most', '1 pushed', '1 failed', '9 (7 landed, 2 blocked)',
    'Landed one', 'lead 1 h 36 min', 'waiting for room 1 min', '2 files, +30 −4', '2 pts of the weekly limit', 'findings 2 P1, 1 P2', 'Old record', 'lead —', 'diff —', 'blocked: timeout',
    'Landed, today / 7 days', 'Cycle time, median', 'Passed first review', 'Cost per landed card', 'All numbers', 'Recent cards',
    'build · 10 min · 1.0M tokens · $2.00 · claude-sonnet-5-5 medium · 12 model replies · API 7 min · tool calls Bash 5, Edit 2 · 1 refused · cache hits 97% · ran claude-opus-5-5', 'review: changes asked · 5 min · 500k tokens · $1.00 · gpt-6.1-sol · findings: 2 P1, 1 P2',
    'tests: 9 passed, 1 failed, 2 skipped of 12 (3 files)'], empty: 'Nothing measured in the last 7 days', failed: 'The Board could not read Metrics' },
};

// ---- lookups more than one file's cases use ----
export const tabBtn = (w, t) => w.document.getElementById(`tab-${t}`);

// The Board: the loop steered from the page, one POST control a change.
export const board = (w) => panel(w, 'board');
// The Board part's other two panels: Loop (the bar: state, Pause, Stop now, the weekly limit, today) and Push landed
// and full test suite (the two actions and the check runs).
export const loopP = (w) => panel(w, 'board-loop');
export const pushP = (w) => panel(w, 'board-push');
export const bcard = (w, n) => board(w).querySelector(`.bcard[data-issue="${n}"]`);
export const column = (w, k) => board(w).querySelector(`.board-col[data-col="${k}"]`);
export const inCol = (w, k) => Array.from(column(w, k).querySelectorAll('.bcard'), (c) => Number(c.dataset.issue));
export const act = (el, a) => el.querySelector(`[data-act="${a}"]`);
export const note = (w) => board(w).querySelector('.board-note').textContent;
// The host's answer to a control action: the control record as it now stands, and when the page's host had it
// (X-Answered-At, whole seconds; `at` null for an answer with no time).
export const record = (over, at = T0) => ({ ok: true, status: 200, text: () => Promise.resolve(JSON.stringify({ ...CONTROL, ...over })),
  headers: { get: (k) => (k.toLowerCase() === 'x-answered-at' && at !== null ? String(Math.ceil(at / 1000)) : null) } });
export function dragTo(w, from, to) {
  from.dispatchEvent(new w.Event('dragstart', { bubbles: true }));
  const over = new w.Event('dragover', { bubbles: true, cancelable: true });
  to.dispatchEvent(over);
  to.dispatchEvent(new w.Event('drop', { bubbles: true, cancelable: true }));
  from.dispatchEvent(new w.Event('dragend', { bubbles: true }));
  return over.defaultPrevented;
}
// The Board shows every open issue.
export const OPEN = {
  count: 9, split: { queued: 3, you: 1, labelOrRule: 3, belt: 2 },
  held: [
    { repo: 'sample', issue: 76, title: 'Split the PROD stack', url: `${P}/76`, priority: 'P2', labels: [], reasons: [{ kind: 'you' }] },
    { repo: 'sample', issue: 40, title: 'Backlog thing', url: `${P}/40`, priority: 'P3', labels: ['backlog'], reasons: [{ kind: 'label', label: 'backlog' }] },
    { repo: 'sample', issue: 41, title: 'Two labels', url: `${P}/41`, priority: 'P1', labels: ['backlog', 'ux-change'], reasons: [{ kind: 'label', label: 'backlog' }, { kind: 'label', label: 'ux-change' }] },
    { repo: 'sample', issue: 42, title: 'Prism integrity', url: `${P}/42`, priority: 'P1', labels: ['area:prism', 'verification-integrity'], reasons: [{ kind: 'standing', rule: 'area:prism verification-integrity issues are never built by the loop' }] },
  ],
};
export const withOpen = (over = {}) => { const d = full(); d.panels.board.data.open = { ...clone(OPEN), ...over }; return d; };

// The Rules tab.
export const rulesP = (w) => panel(w, 'rules');
// Every panel of the Rules tab, in order, and what they say together.
export const rulesAll = (w) => RULES_IDS.map((id) => panel(w, id));
export const rulesText = (w) => rulesAll(w).map((p) => p.textContent).join('\n');
export const ruled = (w) => rulesP(w).querySelectorAll('.rules-side')[0];
export const produced = (w) => panel(w, 'rules-produce').querySelector('.rules-side');
export const figure = (w, k) => produced(w).querySelector(`[data-figure="${k}"] .rules-big`).textContent;
export const nextUp = (w) => Array.from(produced(w).querySelectorAll('.rules-next'), (x) => [Number(x.dataset.issue), x.querySelector('.rules-marks').textContent]);
export const heldP = (w) => panel(w, 'rules-held').querySelector('.rules-held');
export const issuesP = (w) => panel(w, 'rules-issues').querySelector('.rules-issues');
export const pricesP = (w) => panel(w, 'rules-prices').querySelector('.rules-prices');
export const groupsOf = (w) => Array.from(heldP(w).querySelectorAll('.rules-group'), (g) => [g.querySelector('.rules-group-name').textContent, Number(g.querySelector('.rules-group-count').textContent),
  (g.querySelector('.rules-group-mark') || { textContent: '' }).textContent]);
export const groupEl = (w, name) => Array.from(heldP(w).querySelectorAll('.rules-group')).find((g) => g.querySelector('.rules-group-name').textContent === name);
export const rowsOf = (g) => Array.from(g.querySelectorAll('.rules-held-row'), (r) => Number(r.dataset.issue));
// 183 held issues, by area: web 52 (31 held by ux-change), none 41, backend 33, infra 21 (9
// held by dormant), tooling 19, console 11, site 6. The ones no label holds are held in the control record.
const AREAS = [['web', 52, 'ux-change', 31], [null, 41], ['backend', 33], ['infra', 21, 'dormant', 9], ['tooling', 19], ['console', 11], ['site', 6]];
export function heldMany() {
  const d = full(), held = [], mine = [];
  let n = 100000;
  for (const [area, k, label, byLabel] of AREAS) {
    for (let i = 0; i < k; i++, n++) {
      const lab = label && i < byLabel ? label : null;
      if (!lab) mine.push(n);
      held.push({ repo: 'sample', card: null, issue: n, title: `${area || 'loose'} thing ${i}`, url: `${P}/${n}`, priority: i % 3 ? 'P2' : 'P1',
        labels: [`P${i % 3 ? 2 : 1}`].concat(area ? [`area:${area}`] : [], lab ? [lab] : []), reasons: lab ? [{ kind: 'label', label: lab }] : [{ kind: 'you' }] });
    }
  }
  const r = d.panels.rules.data;
  r.control = { ...r.control, held: mine, order: [] };
  r.held = [];
  r.open = { count: 186, split: { queued: 3, you: mine.length, labelOrRule: 183 - mine.length, belt: 0 }, held };
  return d;
}

// A long list: the first five, then "Show 5 more" and "Show all (N)".
export const moreOf = (el) => el.querySelector('.show-more');
export const moreText = (el) => (moreOf(el) && !moreOf(el).hidden ? Array.from(moreOf(el).querySelectorAll('button'), (b) => b.textContent) : []);

// The head line's tiles.
export const tiles = (w) => Array.from(w.document.querySelectorAll('#stats > .stat'));
export const tile = (w, k) => $(w, `#stats > .stat[data-stat="${k}"]`);
export const fig = (w, k) => tile(w, k).querySelector('.stat-fig').textContent.replace(/\s+/g, ' ').trim();
export const shownTiles = (w) => tiles(w).filter((t) => !t.hidden).map((t) => t.dataset.stat);

// Each panel's four cases: data, empty, failed to load, and drawn from its own part alone. Registered by two files,
// the panels in two halves (dashboard-view.page-panels and dashboard-view.page-states), so the runner runs the halves
// side by side: one file of 56 cases took about 2 s alone (conveyor/tests/speed/board-view.md). The first half is the
// smaller, as page-panels also holds the panel list's own cases: 29 and 32 cases. Each file names every case on its
// own line, `test('<id>: <case>', () => panelState.<key>('<id>'))`, for .conveyor/test-changed.sh counts a file's
// cases by its `test(` lines (filecases()); page-panels checks the two files name all four for every panel of the list.
export const PANEL_STATES = { data: 'with data', empty: 'empty', failed: 'failed to load', own: 'draws from its own part alone' };
// What the panels drawn from one part show, together (a part drawn as more than one panel: SPLIT).
const shown = (w, id) => family(id).map((x) => panel(w, x).textContent).join('\n');
export const panelState = {
  data(id) {
    const w = boot({ tab: TAB(id) });
    deliver(w, full());
    for (const x of family(id)) assert.equal(state(w, x), 'ready', `${x} is drawn`);
    const text = shown(w, id);
    for (const s of SAYS[id].data) assert.ok(text.includes(s), `${id} shows "${s}": ${text}`);
    assert.equal($(w, `#panel-${id} .panel-count`).textContent, SAYS[id].count);
    for (const x of family(id)) assert.equal(panel(w, x).querySelector('.skeleton'), null, 'the loading skeleton is gone');
  },
  empty(id) {
    const w = boot({ tab: TAB(id) });
    const data = full();
    data.panels[id] = { error: null, data: clone(EMPTY[id]) };
    deliver(w, data);
    assert.equal(state(w, id), 'empty');
    assert.ok(panel(w, id).textContent.includes(SAYS[id].empty), panel(w, id).textContent);
    assert.equal(panel(w, id).querySelector('.state-empty svg').getAttribute('aria-hidden'), 'true', 'the empty state pairs its words with an icon');
  },
  failed(id) {
    const w = boot({ tab: TAB(id) });
    const data = full();
    data.panels[id] = { error: 'buildhost did not answer: timed out', data: null };
    deliver(w, data);
    assert.equal(state(w, id), 'error');
    const text = panel(w, id).textContent;
    // Issue 415 (UX5): what is not seen and the one thing to try; the build machine's raw reply on tap only.
    assert.ok(text.includes(SAYS[id].failed) && text.includes('The Board could not get this panel from the build machine, so it cannot show it. Make sure that the build machine is on. Then press Restart the Board\'s feed in Health.'), text);
    assert.ok(!text.includes('did not answer'), `the raw reply is not in the text: ${text}`);
    assert.equal(panel(w, id).querySelector('.state-detail').dataset.tip, 'Details: buildhost did not answer: timed out');
    for (const other of LIST) if (other !== id && TAB(other) === TAB(id)) assert.equal(state(w, other), 'ready', `${other} still shows its own data`);
    delete data.panels[id];
    next(w, data);
    assert.equal(state(w, id), 'error');
    assert.match(panel(w, id).textContent, /The build machine sent nothing for this panel, so the Board cannot show it\. If this continues, press Restart the Board's feed in Health\./);
  },
  own(id) {
    const w = boot({ tab: TAB(id) });
    deliver(w, { updatedAt: iso(T0), panels: { [id]: full().panels[id] } });
    for (const x of family(id)) assert.equal(state(w, x), 'ready', `${x} is drawn`);
    for (const s of SAYS[id].data) assert.ok(shown(w, id).includes(s), `${id} needs no other panel's part to show "${s}"`);
  },
};

// The Tests page's actions (#521; dashboard-view.tests-actions and tests-autofile): TA.snap() is full() with the Tests
// model in force (claude-sonnet-5-5, medium), the host's CLIs, a flaky case of merge.test.sh as the runner names it (issue #490), the test
// rules (one rule, off by the switch; the last run matched merge.test.sh, stopped by the switch, and x.test.mjs; two
// log lines) and the actions given (TA.rec(): a judge of merge.test.sh, running for 100 s, with its text so far).
export const TA = (() => {
  const MERGE = 'conveyor/tests/merge.test.sh', X = '.claude/scripts/__tests__/x.test.mjs', ID1 = '0123456789ab', ID2 = 'abcdef012345';
  const MODEL = { cli: 'claude', model: 'claude-sonnet-5-5', effort: 'medium' };
  const RULES = { on: false, perDay: 3, maxOpen: 5, quietDays: 14, burst: true,
    list: [{ name: 'over budget', on: true, measure: 'budget', limit: 1, runs: 3, minRuns: 3 }],
    last: { time: iso(T0), on: false, burst: null, matches: [
      { rule: 'over budget', measure: 'budget', limit: 1, file: MERGE, values: { cpu: [11, 11.5, 12], budget: 8 }, cards: ['c1-1'], result: 'stopped', guard: 'off', why: 'the switch is off' },
      { rule: 'over budget', measure: 'budget', limit: 1, file: X, values: { cpu: [9, 9, 9], budget: 8 }, cards: ['c1-1'], result: 'would file' }] },
    log: [{ time: iso(T0 - 3600000), event: 'filed', rule: 'over budget', measure: 'budget', file: MERGE, values: {}, cards: [], issue: 480 },
      { time: iso(T0 - 7200000), event: 'stopped', rule: 'over budget', measure: 'budget', file: X, values: {}, cards: [], guard: 'perDay', why: '3 issues filed today' }] };
  const NO_RULES = { on: false, perDay: 3, maxOpen: 5, quietDays: 14, burst: true, list: [], last: null, log: [] };
  const rec = (o = {}) => ({ id: ID1, action: 'judge', file: MERGE, project: 'sample', start: iso(Date.now() - 100000), end: null, state: 'running',
    cli: 'claude', model: 'claude-sonnet-5-5', effort: 'medium', limit: 900, verdict: null, text: 'first words\n', textCut: false, ...o });
  function snap({ model = MODEL, acts = [], rules = RULES, at = T0 } = {}) {
    const d = full(at), t = d.panels.tests.data;
    t.tests.rules = clone(rules);
    t.testActions = { limit: 900, actions: clone(acts) };
    t.control = model ? { tests: model } : {};
    t.clis = { claude: { models: ['claude-sonnet-5-5', 'claude-opus-5-5'], efforts: ['low', 'medium', 'high'] }, codex: { models: ['gpt-6.1-sol'], efforts: ['high'] } };
    // The engine's runner names the case as its own; the snapshot's files name merge.test.sh, which defines it, too.
    t.flaky = [{ case: 'conveyor/conveyor.test.sh: mergeclean', count: 2, issue: 490, files: ['conveyor/conveyor.test.sh', MERGE] }];
    return d;
  }
  const tp = (w) => panel(w, 'tests');
  const rowOf = (w, f) => Array.from(tp(w).querySelectorAll('.tests-row')).find((r) => r.dataset.file === f);
  const opened = (w, f) => Array.from(tp(w).querySelectorAll('.tests-open')).find((r) => r.dataset.file === f);
  const results = (w) => tp(w).querySelector('.tests-results');
  return { MERGE, X, ID1, ID2, RULES, NO_RULES, rec, snap, tp, rowOf, opened,
    open: (w, f) => { if (!opened(w, f)) act(rowOf(w, f), 'open').click(); return opened(w, f); },
    type: (el, v) => { el.value = v; el.dispatchEvent(new el.ownerDocument.defaultView.Event('input')); },
    pick: (el, v) => { el.value = v; el.dispatchEvent(new el.ownerDocument.defaultView.Event('change')); },
    said: (w) => tp(w).querySelector('.tests-note').textContent,
    auto: (w) => tp(w).querySelector('.tests-auto'),
    model: (w) => tp(w).querySelector('.tests-actions'),
    results,
    resultRow: (w, id) => Array.from(results(w).querySelectorAll('.tests-result-row')).find((r) => r.dataset.id === id),
    reply: (text) => ({ ok: true, status: 200, text: () => Promise.resolve(text) }) };
})();
