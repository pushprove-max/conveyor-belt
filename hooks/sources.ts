// SPDX-License-Identifier: Apache-2.0
// What /units shows, read from one fetch: the Conveyor snapshot (`conveyor.sh snapshot`) of every record the
// host file (~/.config/conveyor/host.json) names, the Fast lane's worktree, the Research lane's last session activity and
// the Board's usage limit. This module parses those texts and turns them into the lines each view draws; it reads nothing itself.
import { C, clockOf, cols, fitWidth, fmtSec, fmtStep, gauge, plain, resetIn, since, spread, tokens, usd, workMark } from './elements'
import type { Line, Seg } from './elements'

// Where the session sits, from `git rev-parse --git-dir --git-common-dir --show-toplevel`: the views are on by default
// in main, where the Foreman runs, off in every other worktree (a card's, a lane's).
export const seatFromGit = (stdout: string): { seat: 'main' | 'worker'; main: string } | null => {
  const [gitDir, common, top] = stdout.trim().split('\n')
  if (!gitDir || !common || !top) return null
  const main = common.replace(/\/\.git$/, '')
  return { seat: gitDir === common ? 'main' : 'worker', main }
}

// A card or an issue of one record. `repo` is '' for the record whose main is this checkout (the session's own
// project), else the record's name, so another project's #12 is never read as this one's.
// name: what a main-red fix card (issue 0) is shown as, "Main is red (<commit>)", as the snapshot gives it; else ''.
type Ref = { repo: string; issue: number; title: string; name?: string }
type Card = Ref & { card: string }
// One finished review: counts is null for a review recorded before findings were counted (never zeros). judge is what
// the review's judge made of it: how many findings it accepted and declined, and go when the review's GO came
// from it declining every finding; null for a review the judge did not run on (the snapshot's {ran: false, why}).
const LEVELS = ['P0', 'P1', 'P2', 'P3'] as const
type Judged ={ accepted: number; declined: number; go: boolean }
export type Review = { round: number; verdict: string; counts: Record<(typeof LEVELS)[number], number> | null; fixed: boolean; judge: Judged | null }
// What Conveyor measured of a card, as the snapshot's `metrics` gives it: seconds of each part of its life, its
// diff, findings, weekly limit points, tokens and dollars. Every field a reading was not taken for is null, and is shown
// as missing, never as 0. null for the whole: a snapshot from before the measurements.
export type Metrics = {
  leadSec: number | null; cycleSec: number | null; queueSec: number | null; slotSec: number | null; buildSec: number | null; reviewSec: number | null
  fixSec: number | null; testSec: number | null; landSec: number | null; pushSec: number | null; waitMaxSec: number | null
  diff: { files: number; added: number; removed: number } | null; findings: Record<(typeof LEVELS)[number], number> | null; limitUsed: number | null
  reviews: number | null; rebuilds: number | null; retries: number | null; depth: number | null; followups: number | null; blockClass: string | null
  // usd is null when a step has no price (unpriced: how many; each step of the timeline says why); usdKnown, the
  // dollars of those that are priced (null from a snapshot that does not give them); estimate, true when one is an estimate.
  tokens: number | null; usd: number | null; unpriced: number | null; usdKnown: number | null; estimate: boolean; timeline: TimelineStep[]
}
// One finished step of a card, as the dashboard's detail shows it: seconds, tokens, dollars, the model it was priced
// at, findings (a review), test counts (a test run) and the session's own account (turns, API seconds, tool calls,
// refused calls, cache hits, the models that ran). unpriced: why it has no price (null when it has one).
export type TimelineStep = {
  step: string; result: string; sec: number | null; tokens: number | null; usd: number | null; model: string | null; effort: string | null; unpriced: string | null
  // estimate: true when its dollars are an estimate (its usage was read only in part, or not at all).
  estimate: boolean
  counts: Record<(typeof LEVELS)[number], number> | null
  tests: { files: number | null; total: number | null; passed: number | null; failed: number | null; skipped: number | null } | null
  stats: { turns: number | null; apiSec: number | null; tools: Record<string, number> | null; refused: number | null; cacheHit: number | null; models: string[] | null } | null
}
// When a card's work was first picked up: start (a card resumed from a kept patch counts the cards whose
// work it resumes: their first start), its own pickedAt, priorSec (those earlier cards' seconds) and totalSec (pick-up
// to the end; null while it is open, when the time since pickedAt is added). The time it sat queued is in none of them.
export type Times = { start: number | null; pickedAt: number | null; priorSec: number; totalSec: number | null }
// A blocked card is off the belt: its reviews and its track (the step it stopped in is failed, with the seconds that
// step ran) come with it here. parent: the issue whose card filed it as a follow-up (null for any other).
export type Need = Card & Times & { yes: boolean; text: string; since: number | null; parent: number | null; reviews: Review[]; track: Track | null; metrics: Metrics | null }
// The snapshot's track: the six steps Build, Review, Fix, Test, Land, Push, each done, now, skipped, failed or
// todo with its measured seconds (Review and Fix with their rounds n, Review with the rule's of, Push with the
// follow-ups filed). at is the step in progress (null on a card that has ended), label what it is doing, since when that
// began, reason why Push failed, kept how the card took up its issue's kept patch (its worktree line's reason: null
// when that line gives none). No time is estimated from past cards. A track of any other shape (an older loop's) is none.
// files: the test files run of all in the Test step, over: how many more ran than were selected (run is never above of), and now: the file that runs now and when it began; tests: its tests done of all, and failed (none until it gives them).
// list: the list of tests that step's run was given: the files its change touches (changed, files: how many) or the
// whole suite (null when the pack sets no test.list). grown: the files of its change before and after it was split for
// its size (null when it was not).
const STATES = ['done', 'now', 'skipped', 'failed', 'todo'] as const
export const STEP_NAMES = ['Build', 'Review', 'Fix', 'Test', 'Land', 'Push'] as const
// replyFix: on Build, the fix the Done-when check on the build's reply started (track.jq): 'now' while it runs, 'done' after.
// lintFix: on Build, the review gate's lint fix after the build, the same; on Fix, 'now' while the landing gate's lint fix
// runs, or the review gate's after a review or test fix round; on Land, 'now' while the review gate's lint fix after a rebuild runs.
export type Step = { name: string; state: (typeof STATES)[number]; sec: number | null; n: number | null; of: number | null; followups: number | null; replyFix: 'now' | 'done' | null; lintFix: 'now' | 'done' | null }
export type Track = { steps: Step[]; at: number | null; label: string; since: number | null; reason: string | null; kept: string | null; files: { run: number; of: number | null; over: number | null; now: { file: string; at: number | null } | null } | null; tests: { done: number; of: number; failed: number } | null; list: { mode: 'changed'; files: number } | { mode: 'whole' } | null; grown: { before: number; after: number } | null }
// reading is false while no token of the card has been read: its dollars are then "no reading yet", never $0; atEnd: in
// that time the running session's route reports no usage until its step ends: "cost shown when the step ends".
// tokens: the card's fresh tokens so far, both seats together (null when the snapshot does not give them).
// live: the running step as it streams: what it is doing now, its turns so far and when it last printed.
export type Live = { action: string; turns: number | null; lastOutputAt: number | null }
// A card's dollars: usd, null while a step of it has no price; usdKnown, the dollars of its steps that are priced, and
// notPriced, how many are not (null and 0 from a snapshot that does not give them); estimate, true when a step is
// priced as an estimate (its usage was read only in part, or not at all).
export type Priced = { usd: number | null; usdKnown: number | null; notPriced: number; estimate: boolean }
export type Belt = Card & Times & Priced & { step: string; review: number | null; of: number | null; stepAt: number | null; model: string | null; tokens: number | null; reading: boolean; atEnd: boolean; parent: number | null; umbrella: number | null; reviews: Review[]; track: Track | null; metrics: Metrics | null; live: Live | null; waitsOn: Card | null }
// room: why the machine holds it back ("waiting for a machine slot: ..."), "" when it does not.
export type Queued = Ref & { priority: string; followup: boolean; retried: boolean; parent: number | null; umbrella: number | null; room: string }
// An open issue that depends on one still open: not picked until each of waitsFor has closed. states: why each of
// them does not move (the snapshot's waitsOn: held, blocked, building, queued, ...), by its number; none from an older engine.
export type Waiting = Ref & { waitsFor: number[]; states: Record<number, string>; umbrella: number | null }
// An open parent issue (one with GitHub sub-issues, its parts): done of all its parts are closed, and inFlight are
// those on the belt. A card, queued issue or waiting issue that is a part has umbrella: its parent's number.
export type Umbrella = Ref & { done: number; all: number; inFlight: number[] }
// An open issue labelled awaiting-deploy: built and merged, waiting for your PROD deploy. since: when it got the label.
export type Deploy = Ref & { since: number | null }
// push: the state of its Push step (now while the push runs, failed when it failed or GitHub left the issue open).
// waits: what it waits for while no step of it runs (its track's label with at null: with push off, "Landed, waiting
// for Push landed"), else null.
export type Landed = Card & Times & Priced & { closed: boolean; at: number | null; reviews: number; rounds: Review[]; followups: number[]; pushed: boolean | null; issueOpen: boolean; parent: number | null; push: Step['state'] | null; waits: string | null; metrics: Metrics | null }
// queue is null when no record's queue was read (gh did not list the issues); queueMore: a record gave its full ten,
// so more may wait behind them. todayUsd is the dollars of today's priced steps, todayLeftOut how many
// steps of today it leaves out for having no price and todayEstimate how many of it are priced as an estimate; todayUsd is null when a record was not read or its price table
// could not be run. waits: the issues that wait on another, every record's.
// loops: each record's loop as its control record makes it: running, paused, stopped, "paused by guard"
// or "control record unreadable" ("" when the snapshot does not say), reason: why it picks nothing ("" when the
// snapshot gives none), and loop: whether its process runs. judgeDeclined: when each finding the judge declined was
// declined, from every record's declined list, each line once. suites: each record's whole-suite runs (the snapshot's
// suites: a release's suite, the full test), under way (ended null) or ended; rerun: while a release's failed cases run
// again, the pass under way ({pass, of, done: its files done, failed: its files failed, at: when it last moved}), else
// null. building: the running
// loop's cards counted against its builder cap (cap; null with no cap) at its last turn, every card on the belt but one
// that lands; null when no loop runs or the snapshot does not say. behind: the snapshot is behind its card records or
// loop.json (it carries recordsNow: `conveyor.sh snapshot`), as the Foreman takes it; now: then the running loop's count
// as loop.json gives it now, null when no loop process lives or the loop has not counted a turn yet (and when not
// behind). onBelt: the record's
// cards on the belt; landing: those of them landing or landed, in Push (the cap does not count them). waiting: the
// loop's count of its cards that wait and do no work, on another card or for main to change (health.waitingCount;
// while behind, recordsNow's, the loop's count now, when it has one); null when the snapshot does not say.
export type Loop = { repo: string; state: string; reason: string; loop: boolean | null; building: number | null; waiting: number | null; behind: boolean; now: number | null; cap: number | null; onBelt: number; landing: number }
// machine: where a release's suite runs when that is not this machine ({kind: ssh or devbox, name, step: the step the run
// is at (start, setup, checkout, run, results, done), given: a devbox's lease went back}), else null.
export type Suite = { repo: string; kind: string; version: string; sha: string; since: number | null; ended: number | null; state: string; done: number | null; failed: number | null
  machine: { kind: string; name: string; step: string; given: boolean } | null
  rerun: { pass: number; of: number | null; done: number | null; failed: number; at: number | null } | null }
// A project's push (the snapshot's health): running, the push in progress (pushing: stale when its process is gone and
// it did not end; stage, a key of PUSH_STAGE; line, the newest line of its log), last, the last push that ended
// (pushLast: by loop, now for Push now, full for Push landed; started false when it never reached a commit, why then;
// ahead, the commits of main at its end the remote still lacks), and unpushed, how many landed commits wait for a push.
export type Push = {
  repo: string; unpushed: number
  running: { since: number | null; sha: string; stage: string; pid: number | null; log: string; line: string; sec: number | null; stale: boolean } | null
  last: { at: number | null; by: string; started: boolean; why: string; sha: string; ok: boolean; ahead: number | null; check: string; log: string } | null
}
// own: the session's own project, whose cards carry no project name ('' or absent: none is).
export type Snap = { own?: string; pushes?: Push[]; loops: Loop[]; needs: Need[]; belt: Belt[]; queue: Queued[] | null; order?: { repo: string; issue: number; umbrella: number | null }[]; queueMore: boolean; waits: Waiting[]; held: [string, number][]; badDeps?: Ref[]; deploy: Deploy[]; landed: Landed[]; landedCount: number; todayUsd: number | null; todayLeftOut?: number; todayEstimate?: number; judgeDeclined: number[]; suites?: Suite[]; umbrellas: Umbrella[]; unpushed?: { repo: string; issue: number }[]; kept?: { repo: string; at: number }[] }
export type Fast = { state: 'none' | 'unread' | 'norecord' } | { state: 'ok'; branch: string; ahead: number; dirty: number; subject: string }
export type Research = { state: 'none' } | { state: 'ok'; lastAt: number | null }
export type Limit = { pct: number; resetsAt: number }
// snap is null when no record's snapshot could be read; note then holds the note every view shows instead, with
// the Foreman indicator still under it.
// The Foreman indicator (foremanOf): null where no Foreman is expected; else listening or not, why not, and the line
// of details under it.
export type Foreman = { ok: boolean; why: string; detail: string }
// The plugin problems the Foreman noted (conveyor/foreman/stop.sh): how many, and the file they are in.
export type PluginBugs = { n: number; path: string }
// The test map (conveyor/lib/testmap.sh mapstate()): a run making it, with the test files run of how many and when it
// started; a run that failed and why; off; not made yet; or made, with the source and test files it maps and the
// commits it is behind main (null for a map the project keeps itself).
export type TestMap = { state: 'running'; done: number; of: number; started: number | null } | { state: 'failed'; why: string } | { state: 'off' } | { state: 'none' }
  | { state: 'made'; sources: number; tests: number; age: number | null }
export type State = { now: number; snap: Snap | null; note: string; notes: string[]; host: string; limit: Limit | null; fast: Fast; research: Research; foreman?: Foreman | null; pluginBugs?: PluginBugs | null; testMap?: TestMap | null; engine?: string | null }

const time = (v: unknown) => { const t = typeof v === 'string' ? Date.parse(v) : NaN; return Number.isFinite(t) ? t : null }
const num = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) ? v : null)
const one = (v: unknown) => (typeof v === 'string' ? v.replace(/\s+/g, ' ').trim() : '')

// The fetch's answer (hooks/units-fetch.sh), one tab-separated line each: `paths <Research lane worktree> <home>
// <own>`, `fast <state> [<branch> <commits ahead of main> <tracked files changed> <first subject>]`, `host <name> <how>
// <exit> [<path looked at>...]` and then, for every record in the host file's order, `<repo> <its snapshot, or null>`.
// own: the repo of the record whose main is this checkout, the session's own project; empty when no record is. `how`
// is local (one machine, or a record of the host file is this checkout) or ssh, else the reason nothing was asked:
// nofile (with the paths of the host file looked at) or config. foreman: its line's fields after the word, where a Foreman is
// expected (the fetch says which); null where none is. foremanDir: the Foreman's folder, empty when none is named. pluginBugs: `pluginbugs <how many> <file>`, null when the Foreman
// noted none. testMap: `testmap <its state, JSON>` (testMapOf), null with no such line or one not understood. engine:
// `engine <line>`, the line that says the project runs an old engine on this machine; null when it does not. mapRec:
// `maprec <main>`, the main checkout of the record whose feed snapshot's testMap is this checkout's map; empty with none.
// mapHost: `maphost <ssh target>`, the machine whose feed alone carries that map (another can keep a checkout at the
// same path): the ssh target the fetch reads the map at, empty for this machine; null with no such line, as a fetch of
// an older engine prints none.
export type Fetched = { research: string; home: string; own: string; fast: Fast; foreman: string[] | null; foremanDir: string; pluginBugs: PluginBugs | null; testMap: TestMap | null; mapRec: string; mapHost: string | null; engine: string | null; host: { name: string; how: string; rc: number; looked: string[] } | null; records: { repo: string; json: unknown }[] }
export const parseFetch = (stdout: string): Fetched | null => {
  const out: Fetched = { research: '', home: '', own: '', fast: { state: 'unread' }, foreman: null, foremanDir: '', pluginBugs: null, testMap: null, mapRec: '', mapHost: null, engine: null, host: null, records: [] }
  for (const line of stdout.split('\n')) {
    const f = line.split('\t')
    if (out.host) { if (f.length >= 2 && f[0]) out.records.push({ repo: f[0], json: f.slice(1).join('\t') }) }
    else if (f[0] === 'paths') [out.research, out.home, out.own] = [f[1] ?? '', f[2] ?? '', f[3] ?? '']
    else if (f[0] === 'fast' && f[1] === 'none') out.fast = { state: 'none' }
    else if (f[0] === 'fast' && f[1] === 'norecord') out.fast = { state: 'norecord' }
    else if (f[0] === 'fast' && f[1] === 'ok' && /^\d+$/.test(f[3] ?? '') && /^\d+$/.test(f[4] ?? '')) out.fast = { state: 'ok', branch: f[2], ahead: Number(f[3]), dirty: Number(f[4]), subject: one(f[5]) }
    else if (f[0] === 'foreman') out.foreman = f.slice(1)
    else if (f[0] === 'foremandir') out.foremanDir = f[1] ?? ''
    else if (f[0] === 'pluginbugs' && /^[1-9]\d*$/.test(f[1] ?? '') && f[2]) out.pluginBugs = { n: Number(f[1]), path: f[2] }
    else if (f[0] === 'testmap') out.testMap = testMapOf(f.slice(1).join('\t'))
    else if (f[0] === 'maprec') out.mapRec = f.slice(1).join('\t')
    else if (f[0] === 'maphost') out.mapHost = f[1] ?? ''
    else if (f[0] === 'engine' && one(f.slice(1).join(' '))) out.engine = one(f.slice(1).join(' '))
    else if (f[0] === 'host') out.host = { name: f[1] ?? '', how: f[2] ?? '', rc: Number(f[3]), looked: f.slice(4).filter(Boolean) }
  }
  // An empty Research lane is one the host file does not name: the board still reads.
  return out.home ? out : null
}

export const testMapOf = (text: string): TestMap | null => {
  let j: any
  try { j = JSON.parse(text) } catch { return null }
  return testMapFrom(j)
}
// The map's state as an object: the fetch's line, or a feed snapshot's testMap.
const testMapFrom = (j: any): TestMap | null => {
  const n = (v: unknown) => (num(v) !== null && (v as number) >= 0 ? (v as number) : null)
  if (j?.state === 'running' && n(j.done) !== null && n(j.of) !== null) return { state: 'running', done: j.done, of: j.of, started: n(j.started) }
  if (j?.state === 'failed') return { state: 'failed', why: one(j.why) }
  if (j?.state === 'off' || j?.state === 'none') return { state: j.state }
  if (j?.state === 'made' && n(j.sources) !== null && n(j.tests) !== null) return { state: 'made', sources: j.sources, tests: j.tests, age: n(j.age) }
  return null
}

const reviewsOf = (v: unknown): Review[] => (Array.isArray(v) ? v : []).filter(x => x && typeof x === 'object').map((x: any): Review => ({
  round: num(x.round) ?? 0, verdict: one(x.verdict), fixed: x.fixed === true,
  counts: x.counts && typeof x.counts === 'object' && LEVELS.every(k => num(x.counts[k]) !== null) ? { P0: x.counts.P0, P1: x.counts.P1, P2: x.counts.P2, P3: x.counts.P3 } : null,
  judge: x.judge?.ran === true && num(x.judge.accepted) !== null && num(x.judge.declined) !== null ? { accepted: x.judge.accepted, declined: x.judge.declined, go: x.judge.go === true } : null,
}))
export const metricsOf = (v: any): Metrics | null => {
  if (!v || typeof v !== 'object') return null
  const d = v.diff, f = v.findings
  return {
    leadSec: num(v.leadSec), cycleSec: num(v.cycleSec), queueSec: num(v.queueSec), slotSec: num(v.slotSec), buildSec: num(v.buildSec), reviewSec: num(v.reviewSec),
    fixSec: num(v.fixSec), testSec: num(v.testSec), landSec: num(v.landSec), pushSec: num(v.pushSec), waitMaxSec: num(v.waitMaxSec),
    diff: d && typeof d === 'object' && [d.files, d.added, d.removed].every(x => num(x) !== null) ? { files: d.files, added: d.added, removed: d.removed } : null,
    findings: f && typeof f === 'object' && LEVELS.every(k => num(f[k]) !== null) ? { P0: f.P0, P1: f.P1, P2: f.P2, P3: f.P3 } : null,
    limitUsed: num(v.limit?.used), reviews: num(v.reviews), rebuilds: num(v.rebuilds), retries: num(v.retries), depth: num(v.depth), followups: num(v.followups),
    blockClass: one(v.blockClass) || null, tokens: num(v.tokens), usd: num(v.usd), unpriced: num(v.unpriced), usdKnown: num(v.usdKnown), estimate: v.estimate === true,
    timeline: (Array.isArray(v.timeline) ? v.timeline : []).filter((x: any) => x && typeof x === 'object').map((x: any): TimelineStep => {
      const t = x.tests && typeof x.tests === 'object' ? x.tests : null, st = x.stats && typeof x.stats === 'object' ? x.stats : null, c = x.counts
      const tools = st && st.tools && typeof st.tools === 'object' ? Object.fromEntries(Object.entries(st.tools).filter((e): e is [string, number] => num(e[1]) !== null)) : null
      return {
        step: one(x.step), result: one(x.result), sec: num(x.sec), tokens: num(x.tokens), usd: num(x.usd), model: one(x.model) || null, effort: one(x.effort) || null,
        unpriced: one(x.unpriced) || null, estimate: num(x.usd) !== null && !!one(x.estimate),
        counts: c && typeof c === 'object' && LEVELS.every(k => num(c[k]) !== null) ? { P0: c.P0, P1: c.P1, P2: c.P2, P3: c.P3 } : null,
        tests: t && { files: num(t.files), total: num(t.total), passed: num(t.passed), failed: num(t.failed), skipped: num(t.skipped) },
        stats: st && { turns: num(st.turns), apiSec: num(st.apiSec), tools, refused: num(st.refused), cacheHit: num(st.cacheHit),
          models: Array.isArray(st.models) ? st.models.filter((m: unknown): m is string => typeof m === 'string') : null },
      }
    }),
  }
}
const trackOf = (v: any): Track | null => {
  if (!v || typeof v !== 'object' || !Array.isArray(v.steps) || v.steps.length !== 6
    || !v.steps.every((x: any, i: number) => x && typeof x === 'object' && STATES.includes(x.state) && x.name === STEP_NAMES[i])) return null
  const at = num(v.at)
  return {
    steps: v.steps.map((x: any): Step => ({ name: one(x.name), state: x.state, sec: num(x.sec), n: num(x.n), of: num(x.of), followups: num(x.followups),
      replyFix: x.replyFix === 'now' || x.replyFix === 'done' ? x.replyFix : null, lintFix: x.lintFix === 'now' || x.lintFix === 'done' ? x.lintFix : null })),
    at: at !== null && v.steps[at] ? at : null, label: one(v.label), since: time(v.since), reason: one(v.reason) || null, kept: one(v.kept) || null,
    files: v.files && typeof v.files === 'object' && num(v.files.run) !== null ? { run: v.files.run, of: num(v.files.of), over: num(v.files.over),
      now: v.files.now && typeof v.files.now === 'object' && one(v.files.now.file) ? { file: one(v.files.now.file), at: time(v.files.now.at) } : null } : null,
    tests: v.tests && typeof v.tests === 'object' && [v.tests.done, v.tests.of, v.tests.failed].every(x => num(x) !== null) ? { done: v.tests.done, of: v.tests.of, failed: v.tests.failed } : null,
    list: v.list?.mode === 'changed' && num(v.list.files) !== null ? { mode: 'changed', files: v.list.files } : v.list?.mode === 'whole' ? { mode: 'whole' } : null,
    grown: v.grown && typeof v.grown === 'object' && num(v.grown.before) !== null && num(v.grown.after) !== null ? { before: v.grown.before, after: v.grown.after } : null,
  }
}
const timesOf = (x: any): Times => ({ start: time(x.start) ?? time(x.pickedAt), pickedAt: time(x.pickedAt), priorSec: num(x.priorSec) ?? 0, totalSec: num(x.totalSec) })
const parentOf = (x: any) => { const n = num(x.parent); return n !== null && n > 0 ? n : null }
// The parent issue of a part (the snapshot's umbrella: the issue it is a GitHub sub-issue of); null for one that is no part.
const umbrellaOf = (x: any) => { const n = num(x.umbrella); return n !== null && n > 0 ? n : null }

const pricedOf = (x: any): Priced => ({ usd: num(x.usd), usdKnown: num(x.usdKnown), notPriced: num(x.notPriced) ?? 0, estimate: x.estimate === true })
const liveOf = (v: any): Live | null => (v && typeof v === 'object' ? { action: one(v.action), turns: num(v.turns), lastOutputAt: time(v.lastOutputAt) } : null)

// The records' queues as one list. Each queue is already in the engine's pick order (a pinned issue can stand ahead of a
// higher priority one), so one record's issues keep their order; only the heads of the queues are compared: follow-ups
// first, then priority, then the place in its own queue (the stand-in for age), the first record winning a tie.
const mergeQueues = (queues: Queued[][]): Queued[] => {
  // Each queue reversed, so the next issue of a queue is popped from its end, with its place in the queue as its age.
  const rest = queues.map(q => q.map((x, at) => ({ x, at })).reverse())
  const out: Queued[] = []
  for (;;) {
    let best: { x: Queued; at: number } | undefined
    for (const q of rest) {
      const a = q[q.length - 1]
      if (a && (!best || Number(a.x.followup) - Number(best.x.followup) > 0 || (a.x.followup === best.x.followup && (a.x.priority.localeCompare(best.x.priority) < 0 || (a.x.priority === best.x.priority && a.at < best.at))))) best = a
    }
    if (!best) return out
    out.push(best.x)
    rest.find(q => q[q.length - 1] === best)?.pop()
  }
}
// The rule the pick (conveyor/jq/upnext.jq) gives an issue whose Depends on: line names no issue in the form #N: a
// sentence that holds the whole line, up to 200 characters. /units counts these under BAD_DEPS, as one rule however
// the lines differ, and lists each issue in PICK ORDER's Waiting table with BAD_DEPS_ROW: the line itself is not shown.
const BAD_DEPS_RULE = /^the line "[\s\S]*", not a list of issues in the form #N$/
const BAD_DEPS = 'bad Depends on', BAD_DEPS_ROW = 'a Depends on line with no #N'
const ruleLabel = (rule: string) => (BAD_DEPS_RULE.test(rule) ? BAD_DEPS : rule)
const heldCounts =(skipped: unknown, holding: unknown): Record<string, number> => {
  const out: Record<string, number> = {}
  for (const x of Array.isArray(skipped) ? skipped : []) if (x && typeof x === 'object' && one((x as any).rule)) { const k = ruleLabel(one((x as any).rule)); out[k] = (out[k] ?? 0) + 1 }
  const n = (Array.isArray(holding) ? holding : []).filter(x => x && typeof x === 'object').length
  if (n > 0) out.held = n
  return out
}
type Rec = { loop: Loop; needs: Need[]; belt: Belt[]; queue: Queued[] | null; order: { repo: string; issue: number; umbrella: number | null }[]; waits: Waiting[]; held: Record<string, number>; badDeps: Ref[]; deploy: Deploy[]; landed: Landed[]; landedCount: number; todayUsd: number | null; todayLeftOut: number; todayEstimate: number; judgeDeclined: { id: string; at: number }[]; suites: Suite[]; umbrellas: Umbrella[]; unpushed: number[]; push: Push; snapshotAt: number | null }
const pushOf = (repo: string, h: any): Push => {
  const r = h?.pushing, l = h?.pushLast
  return {
    repo, unpushed: Array.isArray(h?.unpushed) ? h.unpushed.length : 0,
    running: r && typeof r === 'object' ? { since: time(r.since), sha: one(r.sha), stage: one(r.stage), pid: num(r.pid), log: one(r.log), line: one(r.line), sec: num(r.sec), stale: r.stale === true } : null,
    last: l && typeof l === 'object' ? { at: time(l.time), by: one(l.by), started: l.started !== false, why: one(l.why), sha: one(l.sha), ok: l.ok === true, ahead: num(l.ahead), check: one(l.check), log: one(l.log) } : null,
  }
}
// One record's snapshot. null: it is not the object `conveyor.sh snapshot` prints, so nothing of it is shown.
export const parseRecord = (repo: string, json: unknown): Rec | null => {
  let j: any = json
  if (typeof json === 'string') try { j = JSON.parse(json) } catch { return null }
  const lists = [j?.needsYou?.waiting, j?.needsYou?.blocked, j?.belt, j?.landed]
  if (!lists.every(l => Array.isArray(l) && l.every((x: unknown) => x && typeof x === 'object')) || typeof j.queue !== 'object' || !j.queue || typeof j.cost !== 'object' || !j.cost) return null
  const card = (x: any): Card => ({ repo, card: one(x.card), issue: num(x.issue) ?? 0, title: one(x.title), name: one(x.name) })
  const next = Array.isArray(j.queue.next) ? j.queue.next.filter((x: unknown) => x && typeof x === 'object') : null
  return {
    loop: { repo, state: one(j.health?.state), reason: one(j.health?.reason), loop: typeof j.health?.loop === 'boolean' ? j.health.loop : null, building: num(j.health?.building),
      ...(j.recordsNow && typeof j.recordsNow === 'object' ? { behind: true, now: num(j.recordsNow.building), waiting: num(j.recordsNow.waitingCount) ?? num(j.health?.waitingCount) }
        : { behind: false, now: null, waiting: num(j.health?.waitingCount) }), cap: num(j.health?.builderCap),
      onBelt: j.belt.length, landing: j.belt.filter((x: any) => x?.offCap === true || x?.step === 'push' || x?.step === 'issue').length },
    needs: [
      ...j.needsYou.waiting.map((x: any): Need => ({ ...card(x), ...timesOf(x), yes: true, text: one(x.sentence), since: time(x.since), parent: parentOf(x), reviews: reviewsOf(x.reviews), track: trackOf(x.track), metrics: metricsOf(x.metrics) })),
      ...j.needsYou.blocked.map((x: any): Need => ({ ...card(x), ...timesOf(x), yes: false, text: one(x.reason), since: time(x.since), parent: parentOf(x), reviews: reviewsOf(x.reviews), track: trackOf(x.track), metrics: metricsOf(x.metrics) })),
    ],
    belt: j.belt.map((x: any): Belt => ({ ...card(x), ...timesOf(x), step: one(x.step), review: num(x.review), of: num(x.of), stepAt: time(x.stepAt), model: one(x.model) || null, tokens: num(x.tokens?.claude) === null || num(x.tokens?.codex) === null ? null : x.tokens.claude + x.tokens.codex, ...pricedOf(x), reading: x.reading === true, atEnd: x.atEnd === true, parent: parentOf(x), umbrella: umbrellaOf(x), reviews: reviewsOf(x.reviews), track: trackOf(x.track), metrics: metricsOf(x.metrics), live: liveOf(x.live), waitsOn: x.waitsOn && typeof x.waitsOn === 'object' && one(x.waitsOn.card) ? card(x.waitsOn) : null })),
    queue: next && next.map((x: any): Queued => ({ repo, issue: num(x.issue) ?? 0, title: one(x.title), priority: one(x.priority), followup: x.followup === true, retried: x.retried === true, parent: parentOf(x), umbrella: umbrellaOf(x), room: one(x.room) })),
    // queue.order is the whole pick order; queue.next stops at ten. pickCounts needs the whole to tell a waiting part from one that is ready.
    order: (Array.isArray(j.queue.order) ? j.queue.order : []).filter((x: unknown) => x && typeof x === 'object')
      .map((x: any) => ({ repo, issue: num(x.issue) ?? 0, umbrella: umbrellaOf(x) })),
    // A record whose loop does not give the list (from an older engine, or GitHub did not list the issues) has none.
    // A forced issue is listed here too, marked forced, though it is in the pick order (queue.order): it waits on nothing.
    waits: (Array.isArray(j.queue.waiting) ? j.queue.waiting : []).filter((x: any) => x && typeof x === 'object' && x.forced !== true)
      .map((x: any): Waiting => ({ repo, issue: num(x.issue) ?? 0, title: one(x.title), umbrella: umbrellaOf(x), waitsFor: Array.isArray(x.waitsFor) ? x.waitsFor.filter((n: unknown): n is number => num(n) !== null) : [],
        states: Object.fromEntries((Array.isArray(x.waitsOn) ? x.waitsOn : []).filter((w: any) => w && num(w.issue) !== null && one(w.state)).map((w: any) => [w.issue, one(w.state)])) }))
      .filter((x: Waiting) => x.waitsFor.length > 0),
    // What the record holds back, counted: the issues its rules skip, by rule (queue.skipped), and the issues it holds (queue.holding).
    held: heldCounts(j.queue.skipped, j.queue.holding),
    // The issues skipped for a Depends on: line with no #N, by number; one with no number shows in the count only.
    badDeps: (Array.isArray(j.queue.skipped) ? j.queue.skipped : []).filter((x: any) => x && typeof x === 'object' && num(x.issue) !== null && BAD_DEPS_RULE.test(one(x.rule)))
      .map((x: any): Ref => ({ repo, issue: num(x.issue) as number, title: one(x.title) })),
    // A record whose loop does not give the list (or whose issues GitHub did not list) has none to show.
    deploy: (Array.isArray(j.awaitingDeploy) ? j.awaitingDeploy : []).filter((x: unknown) => x && typeof x === 'object').map((x: any): Deploy => ({ repo, issue: num(x.issue) ?? 0, title: one(x.title), since: time(x.since) })),
    landed: j.landed.map((x: any): Landed => {
      const t = trackOf(x.track)
      return {
        ...card(x), ...timesOf(x), closed: x.step === 'closed', at: time(x.time), ...pricedOf(x), reviews: num(x.reviews) ?? 0, rounds: reviewsOf(x.rounds),
        issueOpen: t?.steps[5].state === 'failed' && (t.reason ?? '').startsWith('GitHub did not close the issue'), push: t ? t.steps[5].state : null, waits: t && t.at === null && t.label ? t.label : null, parent: parentOf(x),
        followups: Array.isArray(x.followups) ? x.followups.filter((n: unknown): n is number => num(n) !== null) : [], pushed: typeof x.pushed === 'boolean' ? x.pushed : null,
        metrics: metricsOf(x.metrics),
      }
    }),
    // Every card landed today: landed holds only the newest of them and the older ones still on the belt. A snapshot from an older engine has no count,
    // so its rows are the count; the count is never fewer than the rows.
    landedCount: Math.max(num(j.landedCount) ?? 0, j.landed.length),
    todayUsd: num(j.cost.today),
    // A snapshot from an older engine has no count: its today is null whenever a step was unpriced.
    todayLeftOut: num(j.cost.todayLeftOut) ?? 0,
    todayEstimate: num(j.cost.todayEstimate) ?? 0,
    // The declined list's lines by the judge: those the Board's panel shows (declined) and the dismissed or built ones
    // (declinedRest), for a finding dismissed since was still declined.
    judgeDeclined: [j.declined, j.declinedRest].flatMap(l => (Array.isArray(l) ? l : []))
      .filter((x: any) => x && typeof x === 'object' && x.by === 'judge' && time(x.time) !== null)
      .map((x: any) => ({ id: one(x.id), at: time(x.time) as number })),
    // A snapshot from an older engine has no suites.
    suites: (Array.isArray(j.suites) ? j.suites : []).filter((x: unknown) => x && typeof x === 'object')
      .map((x: any): Suite => ({ repo, kind: one(x.kind), version: one(x.version), sha: one(x.sha), since: time(x.since), ended: time(x.ended), state: one(x.state), done: num(x.done), failed: num(x.failed),
        machine: x.machine && typeof x.machine === 'object' && (x.machine.kind === 'ssh' || x.machine.kind === 'devbox') && one(x.machine.name)
          ? { kind: x.machine.kind, name: one(x.machine.name), step: one(x.machine.step), given: x.machine.kind === 'devbox' && one(x.machine.step) === 'done' && one(x.machine.lease) !== '' } : null,
        rerun: x.rerun && typeof x.rerun === 'object' && num(x.rerun.round) !== null ? { pass: x.rerun.round, of: num(x.rerun.of), done: num(x.rerun.files?.done),
          failed: Array.isArray(x.rerun.files?.failed) ? x.rerun.files.failed.length : 0, at: time(x.rerun.at) } : null })),
    // Each open parent issue (open.umbrellas); none when GitHub did not list the issues, or from an older engine.
    umbrellas: (Array.isArray(j.open?.umbrellas) ? j.open.umbrellas : []).filter((x: any) => x && typeof x === 'object' && num(x.issue) !== null)
      .map((x: any): Umbrella => ({ repo, issue: x.issue, title: one(x.title), done: num(x.done) ?? 0, all: num(x.all) ?? 0,
        inFlight: Array.isArray(x.inFlight) ? x.inFlight.filter((n: unknown): n is number => num(n) !== null) : [] })),
    // The open issues whose card landed while push is off, not pushed yet (open.held, a card reason notPushed): on any
    // day, as landed holds only today's landings.
    unpushed: (Array.isArray(j.open?.held) ? j.open.held : []).filter((x: any) => x && num(x.issue) !== null && Array.isArray(x.reasons)
      && x.reasons.some((r: any) => r && r.kind === 'card' && r.notPushed === true)).map((x: any) => x.issue as number).sort((a: number, b: number) => a - b),
    push: pushOf(repo, j.health),
    // When the kept snapshot was made (null from a snapshot that does not say).
    snapshotAt: time(j.snapshotAt),
  }
}

const CANNOT = 'units: the Conveyor snapshot cannot be read'
const WHY: Record<string, string> = { nofile: 'this machine has no host file', config: 'the host file is not understood' }
// The snapshot of every record as one board, or the one line saying why there is none. A record that cannot be read
// costs only its own note while another's can; nothing is ever shown from an earlier fetch. cut: why the fetch's output
// was cut short, when it was; then no record is trusted.
export const boardOf = (f: Fetched | null, cut: string | null = null): Pick<State, 'snap' | 'note' | 'notes' | 'host'> => {
  const none = (why: string, host = '') => ({ snap: null, note: `${CANNOT} (${why})`, notes: [], host })
  if (cut) return none(cut, f?.host?.name ?? '')
  if (!f) return none('the fetch did not run')
  if (!f.host) return none('the fetch did not finish')
  const { name, how, rc, looked } = f.host
  if (how === 'nofile' && looked.length) return none(`${WHY.nofile} at ${looked.join(' or ')}`, name)
  if (how !== 'local' && how !== 'ssh') return none(WHY[how] ?? 'the fetch did not finish', name)
  if (how === 'ssh' && rc === 255) return none(`${name} is unreachable`, name)
  if (rc === 124 || rc === 137) return none(`${name} did not answer in time`, name)
  return boardFrom(name, f.records, f.own)
}

// The dashboard collector's live feed: its units-feed.json (stream.json with each snapshot cut to what /units draws),
// which it rewrites with each change Conveyor's host streams and at least every 10 s.
// `{host, local, ssh, records: [{repo, main, snap}], stream: {live, heardAt, error}}` (main: the record's main checkout,
// empty when the feed names none; local: true on one machine; ssh: the ssh target its snapshots come from, empty on one
// machine or from a Board of an older engine); null when the file is not that, or holds no snapshot of every record yet.
export type Feed = { host: string; local: boolean; ssh: string; records: { repo: string; main: string; json: unknown }[]; live: boolean; heardAt: number | null; error: string }
export const parseStream = (text: string): Feed | null => {
  let j: any
  try { j = JSON.parse(text) } catch { return null }
  if (!j || typeof j !== 'object' || !Array.isArray(j.records) || !j.records.length || !j.stream || typeof j.stream !== 'object') return null
  if (!j.records.every((r: any) => r && typeof r === 'object' && typeof r.repo === 'string')) return null
  return { host: one(j.host), local: j.local === true, ssh: one(j.ssh), records: j.records.map((r: any) => ({ repo: r.repo, main: typeof r.main === 'string' ? r.main : '', json: r.snap })), live: j.stream.live === true, heardAt: time(j.stream.heardAt), error: one(j.stream.error) }
}
// The board from the live feed, as from a fetch; a feed that is down says so under it, with when the host was last heard.
// own: the session's own project, as the fetch names it. testMap: the snapshot's test map (its testMap, the map's state
// as the fetch's testmap line gives it) of the record whose main is mapRec, the main the fetch's maprec line names (a
// repo name alone can name another checkout's record there), which is not own on a build machine, in a feed of the
// machine the fetch's maphost line names (mapHost): a feed at that ssh target, or, with none, a feed of one machine
// (local), as another build machine can keep a checkout at the same path. Host names are not compared: one machine can
// have two. A fetch of an older engine (fetchPath in units.tsx runs the project's engine) prints no maphost line
// (mapHost null): it matched the feed's record by path alone and names no machine. units.tsx mapOfOwn then takes the
// map's lines from the plugin's own fetch (map mode) when the older fetch read no map, so mapHost is null here only
// with the older fetch's own testmap line or when the plugin's fetch did not answer: the feed's map is then never
// taken, not even from a feed of one machine (local): the session's host file can point at another build machine with a
// checkout at the same path, and a note says to pin a newer engine. With no such record, a feed of another machine, or
// a feed whose stream is down (its snapshot is old), the board has no testMap: the fetch's testmap line gives the map
// then, feed or not.
const sameMachine = (f: Feed, ssh: string | null) => (ssh === null ? false : ssh ? f.ssh === ssh : f.local)
export const OLD_MAP_FETCH = "units: the test map is not shown: this project's engine is too old to say which machine the map is on; move plugin.commit in .conveyor/project.json to a newer engine"
export const boardOfFeed = (f: Feed, own: string, mapRec: string, mapHost: string | null): Pick<State, 'snap' | 'note' | 'notes' | 'host'> & Partial<Pick<State, 'testMap'>> => {
  const b = boardFrom(f.host, f.records, own, f.live)
  if (!f.live) b.notes.unshift(`units: the live stream is down${f.error ? ` (${f.error})` : ''}; the board is as ${f.host || 'the host'} was ${f.heardAt ? `at ${clockOf(f.heardAt)}` : 'last heard'}`)
  const r = mapRec && f.live ? f.records.find(x => x.main === mapRec) : undefined
  // The older fetch read no map when the snapshot's testMap is an object (its skip test).
  const tm = (r?.json as any)?.testMap
  if (r && mapHost === null && tm && typeof tm === 'object') b.notes.push(OLD_MAP_FETCH)
  if (!r || !sameMachine(f, mapHost)) return b
  return { ...b, testMap: testMapFrom((r.json as any)?.testMap) }
}

// The cards of own, the session's own project, carry no project name (laneCard finds the Fast lane's card among them);
// every other record's carry its repo. With no own (this checkout is no record's), every card carries its name.
// live: the board is a live feed's whose stream is up (its file fresh, which the reader checks).
const boardFrom = (name: string, records: { repo: string; json: unknown }[], own: string, live = false): Pick<State, 'snap' | 'note' | 'notes' | 'host'> => {
  const none = (why: string) => ({ snap: null, note: `${CANNOT} (${why})`, notes: [] as string[], host: name })
  const read = records.map(r => ({ repo: r.repo, rec: parseRecord(own && r.repo === own ? '' : r.repo, r.json) }))
  const recs = read.map(r => r.rec).filter((r): r is Rec => !!r)
  if (!recs.length) return none(`${name} gave no snapshot`)
  const notes = read.filter(r => !r.rec).map(r => `units: the ${r.repo} snapshot cannot be read`)
  for (const r of read) if (r.rec && !r.rec.queue) notes.push(`units: the ${r.repo} queue was not read (GitHub did not list the issues)`)
  const queues = recs.map(r => r.queue).filter((q): q is Queued[] => !!q)
  const held = new Map<string, number>()
  for (const r of recs) for (const [k, n] of Object.entries(r.held)) held.set(k, (held.get(k) ?? 0) + n)
  const at = (t: number | null) => t ?? 0
  return {
    note: '', notes, host: name,
    snap: {
      own: own && read.some(r => r.rec && r.repo === own) ? own : '',
      // When each record's kept snapshot was made: ageNotes says its age when drawn. A live stream sends a snapshot only
      // when something in it changes, so on a quiet belt an old one is still the current one: none kept then.
      kept: live ? [] : read.flatMap(r => (r.rec?.snapshotAt != null ? [{ repo: r.repo, at: r.rec.snapshotAt }] : [])),
      loops: read.flatMap(r => (r.rec ? [{ ...r.rec.loop, repo: r.repo }] : [])),
      // Your yes first, then the blocked cards; in each, the one waiting longest first.
      needs: recs.flatMap(r => r.needs).sort((a, b) => Number(b.yes) - Number(a.yes) || at(a.since) - at(b.since)),
      belt: recs.flatMap(r => r.belt),
      // The records' pick orders as one list: each record's own order stands (see mergeQueues).
      queue: queues.length ? mergeQueues(queues) : null,
      order: recs.flatMap(r => r.order),
      queueMore: queues.some(q => q.length >= 10),
      waits: recs.flatMap(r => r.waits),
      held: [...held].sort((a, b) => a[0].localeCompare(b[0])),
      badDeps: recs.flatMap(r => r.badDeps),
      deploy: recs.flatMap(r => r.deploy),
      unpushed: recs.flatMap(r => r.unpushed.map(issue => ({ repo: r.loop.repo, issue }))),
      pushes: recs.map(r => r.push).filter(p => p.running || p.last),
      landed: recs.flatMap(r => r.landed).sort((a, b) => at(b.at) - at(a.at)),
      landedCount: recs.reduce((n, r) => n + r.landedCount, 0),
      // A record that was not read spent an unknown amount today, so the total is partial, like an unpriced step.
      todayUsd: recs.length < read.length || recs.some(r => r.todayUsd === null) ? null : Math.round(recs.reduce((n, r) => n + (r.todayUsd as number), 0) * 100) / 100,
      todayLeftOut: recs.reduce((n, r) => n + (r.todayLeftOut ?? 0), 0),
      todayEstimate: recs.reduce((n, r) => n + (r.todayEstimate ?? 0), 0),
      // Records that keep their state under one folder share a declined list, so a line is counted once by its id.
      judgeDeclined: [...new Map(recs.flatMap(r => r.judgeDeclined).map((d, i) => [d.id || `#${i}`, d.at])).values()],
      suites: recs.flatMap(r => r.suites),
      umbrellas: recs.flatMap(r => r.umbrellas),
    },
  }
}

// The 7-day usage limit, from the Board's limit file (limit.json, `{"limit": {usedPct, resetsAt}}`), which the Board
// writes beside data.js from its health panel's `panels.health.data.limit`. null when it holds none.
export const parseLimit = (text: string): Limit | null => {
  try {
    const l = JSON.parse(text)?.limit
    const pct = num(l?.usedPct)
    const resetsAt = time(l?.resetsAt)
    return pct === null || resetsAt === null ? null : { pct, resetsAt }
  } catch { return null }
}

// ---- what the views say ----

// A card with no issue that follows from another work, named by its kind and parent, as its name says (conveyor's
// tcadd() labels): `fu #N` for a review follow-up, `split #N` for a split part, `test <file>` for a Tests page card
// (the test file's name without its folder and extension, cut to fit the matrix's ID column), `red <commit's first 7>`
// for a main-red fix card; its title is the work itself. null for any other card.
const ID_MAX = 12
const KINDS: [RegExp, (m: RegExpExecArray) => string][] = [
  [/^Review follow-up of #(\d+)$/, m => `fu #${m[1]}`],
  [/^Split part of #(\d+)$/, m => `split #${m[1]}`],
  [/^Tests page: (.+)$/, m => `test ${(m[1]?.split('/').pop() ?? '').replace(/\.test\.[^.]+$|\.[^.]+$/, '').slice(0, ID_MAX - 5)}`],
]
// A finding's title without its tags ([P1], [E2], [cleanup]), the place cut to the file's base name and the line:
// "[P2] [E1] conveyor/lib/auto.sh:239 The build host can ..." reads "auto.sh:239 The build host can ...". Any other title is kept.
const findingTitle = (title: string): string => {
  const bare = title.replace(/^(?:\[(?:P[0-3]|[A-Za-z]+[0-9]+|cleanup)\]\s*)+/, '')
  const m = /^(\S+?):(\d+(?:-\d+)?)\s+(.+)$/.exec(bare)
  return m ? `${m[1]?.split('/').pop()}:${m[2]} ${m[3]}` : bare
}
const kindOf = (c: Ref): { id: string; title: string } | null => {
  for (const [re, id] of KINDS) { const m = re.exec(c.name ?? ''); if (m) return { id: id(m), title: findingTitle(c.title) } }
  // A main-red fix card: its Title is its name, "Main is red (<commit>)"; the snapshot's title, which lists the failing cases, is not shown.
  const red = /^Main is red \(([0-9a-f]+)\)/.exec(c.name ?? '')
  return red?.[1] ? { id: `red ${red[1].slice(0, 7)}`, title: c.name ?? '' } : null
}
// A card by its issue; a card with no issue by its kind and parent (kindOf, repo before it, as before an issue number), else by its name; a branch by its title.
const named = (c: Ref) => { const k = kindOf(c); return k ? `${c.repo ? `${c.repo} ` : ''}${k.id}` : c.name ? `${c.repo ? `${c.repo} ` : ''}${c.name}` : '' }
const ref = (c: Ref) => (c.issue ? `${c.repo}#${c.issue}` : named(c) || c.title || 'a branch')
const titleOf = (c: Ref) => kindOf(c)?.title ?? c.title
export const nameOf = (c: Ref) => (c.issue || c.name ? `${ref(c)}${titleOf(c) ? ` ${titleOf(c)}` : ''}` : c.title || 'a branch with no issue')
// The round in progress, as the track names it ("review 2 of 3", "fix after review 1", "tests", "landing"). A review
// past the rule's count (after a landing conflict or a test fix) is named by its number alone.
export const stepOf = (b: Belt) => b.track?.label || (b.step === 'review' && b.review ? `review ${b.review}${b.of && b.review <= b.of ? ` of ${b.of}` : ''}` : b.step || 'step unknown')
const whatOf = (n: Need) => (n.yes ? `your yes: ${n.text || 'a visible change'}` : `blocked: ${n.text || 'no reason recorded'}`)
const count = (n: number, word: string) => `${n} ${word}${n === 1 ? '' : 's'}`
// Dollars priced, `~` before them when a step is priced as an estimate, and the steps left out for having no price
// after them: `$4.12`, `~$4.12`, `$4.10 + 1 step not priced`. The priced part is never shown as the whole. short, for
// a narrow column, gives the gap as `+` alone (`$4.10+`); the caller shows the whole text where there is room for it.
const priceText = (v: number, gap: number, estimate: boolean, short = false) =>
  `${estimate ? '~' : ''}${usd(v)}${!gap ? '' : short ? '+' : ` + ${count(gap, 'step')} not priced`}`
// A card's dollars as priceText gives them; null when a step has no price and the snapshot gives no known dollars.
const cardDollars = (p: Priced, short = false): string | null => (p.usd !== null ? priceText(p.usd, 0, p.estimate)
  : p.usdKnown !== null && p.notPriced > 0 ? priceText(p.usdKnown, p.notPriced, p.estimate, short) : null)
const cost = (p: Priced, short = false): Seg => ({ t: cardDollars(p, short) ?? 'cost partial', c: C.cost })
// The known dollars and the gap on a line of their own, from column `at`, or further left where the text would not
// fit there: in full, else as `$4.10 + 1 not priced` where the full text is wider than the pane. Never cut.
const gapRow = (v: number, gap: number, estimate: boolean, at: number, w: number): Line => {
  const full = priceText(v, gap, estimate), t = cols(full) <= w || !gap ? full : `${estimate ? '~' : ''}${usd(v)} + ${gap} not priced`
  return fitWidth([{ t: ' '.repeat(Math.max(0, Math.min(at, w - cols(t)))) }, { t, c: C.cost }], w)
}
// Under a table row whose Cost column gives the short form (`$4.10+`): the known dollars and the gap (gapRow); nothing
// when the card has no gap.
const gapLine = (p: Priced, at: number, w: number): Line[] => (p.usd === null && p.usdKnown !== null && p.notPriced > 0
  ? [gapRow(p.usdKnown, p.notPriced, p.estimate, at, w)] : [])
// Under a table row in a pane too narrow for its Cost column: the card's dollars (`~$4.12`), or the known dollars and
// the gap, as gapRow gives them; `cost partial` when the snapshot gives no dollars known.
const dollarsLine = (p: Priced, at: number, w: number): Line[] => {
  if (p.usd !== null) return [gapRow(p.usd, 0, p.estimate, at, w)]
  const gap = gapLine(p, at, w)
  return gap.length ? gap : [fitWidth([{ t: ' '.repeat(at) }, cost(p)], w)]
}
// The day's dollars: those of its priced steps, as priceText gives them; "partial" when a record was not read.
const dayDollars = (snap: Snap, short = false): string | null =>
  (snap.todayUsd === null ? null : priceText(snap.todayUsd, snap.todayLeftOut ?? 0, (snap.todayEstimate ?? 0) > 0, short))
// A card's measurements, as the dashboard's per-card detail gives them, in two lines: where its time went,
// then what it made and cost. A reading that was not taken reads "missing", never 0. [] for a snapshot without them.
export const metricsText = (m: Metrics | null): string[] => {
  if (!m) return []
  const sec = (v: number | null) => (v === null ? 'missing' : fmtStep(v))
  const n = (v: number | null) => (v === null ? 'missing' : String(v))
  const found = m.findings ? LEVELS.filter(k => m.findings![k] > 0).map(k => `${m.findings![k]} ${k}`).join(', ') || 'none' : 'missing'
  return [
    [`lead ${sec(m.leadSec)}`, `cycle ${sec(m.cycleSec)}`, `queued ${sec(m.queueSec)}`, `slot wait ${sec(m.slotSec)}`, `build ${sec(m.buildSec)}`, `review ${sec(m.reviewSec)}`,
      `fix ${sec(m.fixSec)}`, `tests ${sec(m.testSec)}`, `landing ${sec(m.landSec)}`, `to push ${sec(m.pushSec)}`, `waiting on you ${sec(m.waitMaxSec)}`].join(' · '),
    [m.diff ? `${count(m.diff.files, 'file')} +${m.diff.added} −${m.diff.removed}` : 'diff missing', `findings ${found}`, `reviews ${n(m.reviews)}`, `rebuilds ${n(m.rebuilds)}`,
      `retries ${n(m.retries)}`, `depth ${n(m.depth)}`, `follow-ups ${n(m.followups)}`, `limit ${m.limitUsed === null ? 'missing' : `${m.limitUsed} pts`}`,
      `${m.tokens === null ? 'missing' : tokens(m.tokens)} tokens`,
      cardDollars({ usd: m.usd, usdKnown: m.usdKnown, notPriced: m.unpriced ?? 0, estimate: m.estimate }) ?? (m.unpriced ? `cost partial: ${count(m.unpriced, 'step')} not priced` : 'cost missing'),
      ...(m.blockClass ? [`blocked: ${m.blockClass}`] : [])].join(' · '),
  ]
}
// One step of a card's timeline: `build · 10m · 1.0M tokens · $2.00 · claude-sonnet-5-5 high · turns 3 · API 3s ·
// tools Bash 2, Read 1 · refused 1 · cache hits 97% · ran claude-opus-5-5`; a review adds its findings, a test run its
// counts. A reading that was not taken reads "missing"; dollars that are an estimate read `~$2.00`.
export const timelineText = (s: TimelineStep): string => {
  const n = (v: number | null) => (v === null ? 'missing' : String(v))
  const parts = [`${s.step}${s.result && s.result !== 'ok' ? ` ${s.result}` : ''}`, s.sec === null ? 'missing' : fmtStep(s.sec),
    `${s.tokens === null ? 'missing' : tokens(s.tokens)} tokens`, s.usd !== null ? priceText(s.usd, 0, s.estimate) : `not priced: ${s.unpriced || 'no reason given'}`]
  if (s.model) parts.push(s.model + (s.effort ? ` ${s.effort}` : ''))
  if (s.counts) parts.push(`findings ${LEVELS.filter(k => s.counts![k] > 0).map(k => `${s.counts![k]} ${k}`).join(', ') || 'none'}`)
  if (s.tests) parts.push(`tests ${n(s.tests.passed)} passed, ${n(s.tests.failed)} failed, ${n(s.tests.skipped)} skipped of ${n(s.tests.total)} (${n(s.tests.files)} files)`)
  if (s.stats) {
    const st = s.stats, tools = st.tools ? Object.entries(st.tools) : null
    parts.push(`turns ${n(st.turns)}`)
    if (s.step !== 'review') parts.push(`API ${st.apiSec === null ? 'missing' : fmtStep(st.apiSec)}`)
    parts.push(`tools ${tools === null ? 'missing' : tools.length ? tools.map(([k, v]) => `${k} ${v}`).join(', ') : 'none'}`)
    if (s.step !== 'review') parts.push(`refused ${n(st.refused)}`, `cache hits ${st.cacheHit === null ? 'missing' : `${Math.round(st.cacheHit * 1000) / 10}%`}`,
      `ran ${st.models === null ? 'missing' : st.models.join(', ') || 'none'}`)
  }
  return parts.join(' · ')
}
// Parts joined with " · " (or `sep`) and wrapped at the width, never cut: a later field must not fall off a narrow
// terminal. A wrapped line is indented two more under the first. A part wider than a line is broken at its ", ", then at
// its spaces (joined by a space, as in the part); a word wider than a line is broken between characters (pieces).
const wrapParts = (parts: string[], w: number, lead: string, sep = ' · ', style: Omit<Seg, 't'> = { d: true }): Line[] => {
  const out: Line[] = []
  let cur = ''
  const add = (p: string, join: string) => {
    const next = cur ? `${cur}${join}${p}` : `${lead}${p}`
    if (cur && cols(next) > w) { out.push([{ ...style, t: cur }]); cur = `${lead}  ${p}` } else cur = next
  }
  for (const p of parts) {
    if (cols(`${lead}  ${p}`) <= w) add(p, sep)
    else p.split(', ').forEach((q, i, l) => pieces(i < l.length - 1 ? `${q},` : q, w - cols(lead) - 2).forEach((x, j) => add(x, i || j ? ' ' : sep)))
  }
  if (cur) out.push([{ ...style, t: cur }])
  return out.map(l => fitWidth(l, w))
}
// The two lines of metricsText, then one line a finished step (its timeline), each wrapped.
const metricsLines = (m: Metrics | null, w: number): Line[] => [
  ...metricsText(m).flatMap(t => wrapParts(t.split(' · '), w, '    ')),
  ...(m ? m.timeline.flatMap(s => wrapParts(timelineText(s).split(' · '), w, '      ')) : []),
]

// A review's findings by level, "1 P1, 2 P2"; '' when none were counted.
const findingsOf = (r: Review, sep = ', ') => (r.counts ? LEVELS.filter(k => r.counts![k] > 0).map(k => `${r.counts![k]} ${k}`).join(sep) : '')
// `R1 NO-GO  1 P1, 2 P2`, `R2 GO`: a finished review with its findings by level, or its verdict alone.
export const reviewText = (r: Review): string => {
  const found = findingsOf(r)
  return `R${r.round} ${r.verdict || 'no verdict'}${found ? `  ${found}` : ''}`
}
// The judge on a card's latest review: `judge: 2 accepted, 1 declined`, marked when the GO came only from its
// declining every finding. '' when the judge did not run on that review.
const judgeText =(rs: Review[]): string => {
  const j = rs.at(-1)?.judge
  return j ? `judge: ${j.accepted} accepted, ${j.declined} declined${j.go ? ' · GO from declines only' : ''}` : ''
}
// How a card took up its issue's kept patch, as its start line says (track.kept), dim and cut at the width: [] when
// that line gives no reason.
const keptLine = (t: Track | null, w: number, pad: string): Line[] => (t && t.kept ? [fitWidth([{ t: `${pad}${t.kept}`, d: true }], w)] : [])
const judgeLine = (rs: Review[], w: number, pad: string): Line[] => {
  const t = judgeText(rs)
  return t ? [fitWidth([{ t: `${pad}${t}`, d: true }], w)] : []
}

// A card's six steps joined into one track: a done step has its check mark and a filled join, the
// step in progress is lit (▶, bold), a step to come is dim, a skipped step has a dash, a failed one is red with ✗.
// What was measured goes in: a step that ran more than once its count (`Review 2 of 3`, `Fix 2`, as the
// dashboard names them) and a done step the time it took (`✓ Build 16m`). When the width is short the joins narrow
// first (`━`), then a count reads `2/3`, then the times give way from the last done step back, and only then the
// counts; the six steps are never cut. At the panel's 62 columns a card in its tests keeps every time and count; what
// a narrower or fuller track has no room for, trackLines shows on a line under it.
const stepCount = (st: Step, short: boolean): string => {
  const n = st.n ?? 0
  if (n < 1 || (n === 1 && st.state !== 'now')) return ''
  if (st.name === 'Review') return ` ${n}${st.of !== null && n <= st.of ? (short ? `/${st.of}` : ` of ${st.of}`) : ''}`
  return st.name === 'Fix' ? ` ${n}` : ''
}
// A reply-check fix is Build's, never Fix's (the dashboard's names): "▶ Build · reply check fix", "✓ Build · reply check fixed".
// The review gate's lint fix after the build is Build's too: "▶ Build · lint fix", "✓ Build · lint fixed"; the landing
// gate's is a Fix round: "▶ Fix 2: lint findings" (track.jq lintFix). The review gate's after a fix round is that Fix
// round's, the same; after a rebuild it is Land's: "▶ Land · lint fix".
// Build also says when the card was split for its size (track.jq grown): ' · split for its size, 5 → 2 files'.
const stepNote = (st: Step, t: Track): string =>
  st.name === 'Fix' ? (st.lintFix === 'now' && st.state === 'now' ? ': lint findings' : '')
  : st.name === 'Land' ? (st.lintFix === 'now' && st.state === 'now' ? ' · lint fix' : '')
  : st.name !== 'Build' ? '' : (st.replyFix === 'now' && st.state === 'now' ? ' · reply check fix' : st.replyFix === 'done' && st.state === 'done' ? ' · reply check fixed' : '')
    + (st.lintFix === 'now' && st.state === 'now' ? ' · lint fix' : st.lintFix === 'done' && st.state === 'done' ? ' · lint fixed' : '')
    + (t.grown ? ` · split for its size, ${t.grown.before} → ${t.grown.after} files` : '')
const trackFit = (t: Track, w: number): { segs: Seg[]; count: 'full' | 'short' | null; times: number } => {
  const done = t.steps.flatMap((st, i) => (st.state === 'done' && st.sec !== null ? [i] : []))
  // wide: the joins ` ━━ ` (else `━`); count: 'full', 'short' or none; times: how many done steps, from the first, keep their time.
  const build = (wide: boolean, count: 'full' | 'short' | null, times: number): Seg[] => {
    const timed = new Set(done.slice(0, times))
    const segs: Seg[] = [{ t: ' ' }]
    t.steps.forEach((st, i) => {
      if (i) segs.push(st.state === 'todo' ? { t: wide ? ' ── ' : '─', c: C.dim } : { t: wide ? ' ━━ ' : '━', c: st.state === 'failed' ? C.bad : C.ok })
      const name = `${st.name}${count ? stepCount(st, count === 'short') : ''}`, note = count ? stepNote(st, t) : ''
      if (st.state === 'done') segs.push({ t: `✓ ${name}${timed.has(i) ? ` ${fmtStep(st.sec as number)}` : ''}${note}`, c: C.ok })
      else if (st.state === 'now') segs.push({ t: `▶ ${name}${note}`, c: C.work, b: true })
      else if (st.state === 'skipped') segs.push({ t: `– ${name}`, c: C.dim })
      else if (st.state === 'failed') segs.push({ t: `✗ ${name}`, c: C.bad, b: true })
      else segs.push({ t: name, c: C.dim })
    })
    return segs
  }
  const all = done.length
  const ladder: Array<[boolean, 'full' | 'short' | null, number]> = [
    [true, 'full', all], [false, 'full', all], [false, 'short', all],
    ...Array.from({ length: all }, (_, k): [boolean, 'short', number] => [false, 'short', all - 1 - k]),
    [true, null, 0], [false, null, 0],
  ]
  for (const [wide, count, times] of ladder) {
    const segs = build(wide, count, times)
    if (cols(plain(segs)) <= w) return { segs, count, times }
  }
  return { segs: fitWidth(build(false, null, 0), w), count: null, times: 0 }
}
export const trackLine = (t: Track, w: number): Line => trackFit(t, w).segs
// The track, then, when the width made it drop a done step's time or a step's count, those steps whole on a dim line
// under it (`    Test 16m · Land 16m`), wrapped at the width: every measured time and count stays on the view.
export const trackLines = (t: Track, w: number, lead = ''): Line[] => {
  const fit = trackFit(t, w - cols(lead))
  const timed = new Set(t.steps.flatMap((st, i) => (st.state === 'done' && st.sec !== null ? [i] : [])).slice(0, fit.times))
  const dropped = t.steps.flatMap((st, i) => {
    const time = st.state === 'done' && st.sec !== null && !timed.has(i) ? ` ${fmtStep(st.sec)}` : ''
    const n = fit.count === null ? stepCount(st, false) : '', note = fit.count === null ? stepNote(st, t) : ''
    return time || n || note ? [`${st.name}${n}${time}${note}`] : []
  })
  return [[...(lead ? [{ t: lead }] : []), ...fit.segs], ...(dropped.length ? wrapParts(dropped, w, '    ') : [])]
}
// The step a blocked card stopped in and how long it ran: "failed at Build (step 1 of 6) after 12m". '' for a card
// that failed no step (it waits for a yes) or whose track was not given.
export const stoppedOf = (t: Track | null): string => {
  const i = t ? t.steps.map(st => st.state).lastIndexOf('failed') : -1
  if (!t || i < 0) return ''
  const st = t.steps[i]
  return `failed at ${st.name} (step ${i + 1} of ${t.steps.length})${st.sec === null ? '' : ` after ${fmtStep(st.sec)}`}`
}
// What the card is doing, as the measured time in its step says it: "fixing 2m", "pushing 51s".
const DOING = ['building', 'reviewing', 'fixing', 'testing', 'landing', 'pushing']
const doingText = (t: Track | null, since: number | null, now: number): string => {
  const at = t && t.at !== null ? t.at : null
  const s = since === null ? null : fmtStep(Math.max(0, Math.round((now - since) / 1000)))
  if (at === 5 && t!.steps[5].state === 'failed') return `push failed${s ? ` ${s}` : ''}`
  // The follow-ups are filed before the landing, as part of Land, so the track never steps back.
  if (at === 4 && t!.label === 'filing follow-ups') return `filing follow-ups${s ? ` ${s}` : ''}`
  // A Test step on its second run or later: s is this run's time, and the time of all its runs (the earlier ones', the
  // step's sec, and this one's) is said apart: "testing 11m · 3rd run, 2h 6m in all" (#433).
  const n = at === 3 ? t!.steps[3].n : null
  const runs = n !== null && n > 1 && since !== null ? ` · ${nth(n)} run, ${fmtStep((t!.steps[3].sec ?? 0) + Math.max(0, Math.round((now - since) / 1000)))} in all` : ''
  return at === null ? (s ? `${s} in this step` : '') : `${DOING[at]}${s ? ` ${s}` : ''}${runs}`
}
const nth = (n: number) => `${n}${[11, 12, 13].includes(n % 100) ? 'th' : ['th', 'st', 'nd', 'rd'][n % 10] || 'th'}`
// A follow-up's title is the finding it was filed for ("[P2] .claude/dashboard/panels/board.js:40 The board shows a
// stale snapshot when ..."); its short title says what it fixes: the file's name and the finding's first words ("Board:
// Board shows a stale snapshot"). A title that is not a finding is kept, and cut at the width where it is shown.
export const shortTitle = (title: string): string => {
  // The level, then any tags ([E1], [cleanup]: the Board's HEAD_RE takes the same), then the place.
  const m = /^(?:\[P[0-3]\](?:\s*\[(?:[A-Za-z]+[0-9]+|cleanup)\])*\s+)?(\S+?\.[A-Za-z0-9]+):\d+(?:-\d+)?\s+(.+)$/.exec(title)
  if (!m) return title
  const base = (m[1].split('/').pop() ?? m[1]).replace(/\.[^.]+$/, '').replace(/[-_.]+/g, ' ').trim()
  const first = m[2].split(/[.;:,]\s|\s[—–-]\s|\.$/)[0].replace(/^(the|a|an)\s+/i, '').trim()
  const words = first.split(/\s+/).slice(0, 6).join(' ')
  if (!base || !words) return title
  return `${base.charAt(0).toUpperCase()}${base.slice(1)}: ${words.charAt(0).toUpperCase()}${words.slice(1)}`
}
// A time of day, with the date when it is not today's.
const whenOf = (t: number, now: number) => {
  const d = new Date(t), n = new Date(now)
  return d.toDateString() === n.toDateString() ? clockOf(t) : `${d.toLocaleString('en-US', { month: 'short' })} ${d.getDate()} ${clockOf(t)}`
}
// A card's overall time: the earlier cards' seconds and its own from its pick-up to its end, or to now while it is open.
const overallOf = (x: Times, now: number): number | null =>
  x.totalSec !== null ? x.totalSec : x.pickedAt === null ? null : x.priorSec + Math.max(0, Math.round((now - x.pickedAt) / 1000))

// The card that lands the Fast lane's branch, found as `conveyor.sh land-branch` names it: a branch named as a card
// id of the own project (c<time>-<project>-<issue>) lands as that issue; any other branch, a number in its name or
// not, lands as issue 0 under its first commit's subject.
export const laneCard = (s: State): string => {
  if (!s.snap || s.fast.state !== 'ok' || !s.fast.ahead) return ''
  const tag = (s.snap.own ?? '').replace(/[^A-Za-z0-9]/g, '-')
  const n = Number((tag && new RegExp(`^c\\d{8}T\\d{6}-${tag}-([1-9]\\d{0,8})$`).exec(s.fast.branch)?.[1]) || 0)
  const subject = s.fast.subject.slice(0, 200)
  const mine = (c: Card) => !c.repo && c.issue === n && (n > 0 || c.title === subject)
  const belt = s.snap.belt.find(mine)
  if (belt) return `card on the belt: ${stepOf(belt)}`
  if (s.snap.needs.some(mine)) return 'card needs you'
  const landed = s.snap.landed.find(mine)
  return landed ? `card ${landed.closed ? 'closed' : 'landed'}${landed.at ? ` ${clockOf(landed.at)}` : ''}` : 'not landed'
}
export const fastText = (s: State): string => {
  const f = s.fast
  if (f.state === 'none') return 'no worktree on this machine'
  if (f.state === 'unread') return 'not read: git did not answer'
  if (f.state === 'norecord') return 'not read: the host file has no record of this checkout'
  if (!f.ahead && !f.dirty) return 'nothing open'
  return [
    ...(f.ahead ? [`${count(f.ahead, 'commit')} ${f.branch === 'HEAD' ? 'on no branch' : `on ${f.branch}`}${f.subject ? `: ${f.subject}` : ''}`] : []),
    ...(f.dirty ? [`${count(f.dirty, 'file')} uncommitted`] : []),
    ...(f.ahead ? [laneCard(s)] : []),
  ].join(' · ')
}
// The Foreman indicator for the session `sid`, from the fetch's foreman fields: <session the role mark names> <waiter
// pid> <its commit, - from a checkout> <its session> <1: that waiter runs> <the commit the project runs now> <each
// watcher name:up|down> <the waiter's state, lib.sh waiter_state: listening, starting again, or down: <why>>.
// Listening: this session holds the role, and its waiter runs from the install the project runs now with every
// watcher up. With no waiter running, the state says whether one is starting again (it ended under a minute ago) or
// is down and why. An install is old only when both commits are named and differ: a waiter from a
// checkout, or a project that names no commit, never moves (waiter.sh moved).
const COMMIT = /^[0-9a-f]{40}$/
export const foremanOf = (f: string[] | null, sid: string): Foreman | null => {
  if (!f) return null
  const [mark = '', pid = '', commit = '', wsid = '', live = '', cur = '', watch = '', state = ''] = f
  const watchers = watch.split(' ').filter(Boolean).map(w => w.split(':'))
  const running = live === '1' && !!sid && wsid === sid
  const detail = [
    `role: ${mark || 'no session'}${mark && mark === sid ? ' (this one)' : ''}`,
    running || live === '1' ? `waiter ${pid} on ${COMMIT.test(commit) ? commit.slice(0, 7) : 'a checkout'}${running ? '' : ` for ${wsid || 'no session'}`}` : 'no waiter',
    ...(watchers.length ? [`watchers: ${watchers.map(([n, st]) => `${n} ${st}`).join(', ')}`] : []),
  ].join(' · ')
  const down = watchers.find(([, st]) => st !== 'up')
  const why = !sid || mark !== sid ? 'not the Foreman session'
    : !running ? (state === 'starting again' ? 'waiter starting again' : state.startsWith('down: ') ? `waiter ${state}` : 'no waiter running')
    : COMMIT.test(commit) && COMMIT.test(cur) && commit !== cur ? 'waiter on an old install'
    : down ? `watcher down: ${down[0]}`
    : ''
  return { ok: !why, why, detail }
}
const foremanText = (m: Foreman) => (m.ok ? 'Foreman listening' : `Foreman not listening: ${m.why}`)
// The details wrapped at the width after a " · " or ", ", never cut: a watcher's state must not fall off a narrow
// pane. A wrapped line is indented two more; only one piece wider than the whole line is cut.
const foremanDetail = (detail: string, w: number): Line[] => {
  const out: string[] = []
  let cur = '  '
  for (const p of detail.split(/(?<=, | · )/)) {
    if (cur.trim() && cols(`${cur}${p}`.trimEnd()) > w) { out.push(cur.trimEnd()); cur = '    ' }
    cur += p
  }
  out.push(cur.trimEnd())
  return out.map(t => fitWidth([{ t, d: true }], w))
}
// The indicator and the lines under it. None where no Foreman is expected. The plugin problems the Foreman noted
// follow, with a link to their file (a file:// URL, which the terminal opens; uncut, as a cut URL opens nothing): only
// the owner can fix or file them in the plugin's repository.
export const foremanModel = (s: State, w: number): Line[] => [
  ...(s.foreman ? [
    [{ t: foremanText(s.foreman), c: s.foreman.ok ? C.ok : C.you, b: !s.foreman.ok }],
    ...foremanDetail(s.foreman.detail, w),
  ] : []),
  ...(s.pluginBugs ? [
    fitWidth([{ t: `${s.pluginBugs.n} plugin problem${s.pluginBugs.n === 1 ? '' : 's'} noted`, c: C.you, b: true }], w),
    [{ t: `  file://${encodeURI(s.pluginBugs.path)}`, d: true }],
  ] : []),
]

// The test map's one line, in /units and the pane: while a run makes it, how many of its test files have run and for
// how long, with a bar at the right edge (kept whole, the text cut first); else its state. None when neither the fetch nor the feed gave one.
export const testMapModel = (s: State, w: number): Line[] => {
  const m = s.testMap
  if (!m) return []
  if (m.state === 'running') {
    const took = m.started === null ? '' : ` · ${fmtSec(Math.max(0, Math.round(s.now / 1000 - m.started)))}`
    return [spread([{ t: `Test map: ${m.done} of ${m.of} test files${took}`, c: C.work }], gauge(m.of ? (100 * m.done) / m.of : 0), w)]
  }
  const line: Line = m.state === 'failed' ? [{ t: `Test map: failed${m.why ? `: ${m.why}` : ''}`, c: C.bad }]
    : m.state === 'off' ? [{ t: 'Test map: off', d: true }]
    : m.state === 'none' ? [{ t: 'Test map: not made yet · run /conveyor-belt:setup to make it', c: C.you }]
    : [{ t: `Test map: ${m.sources} source, ${count(m.tests, 'test file')}${m.age === null ? '' : m.age ? ` · ${count(m.age, 'commit')} behind main` : ' · up to date with main'}`, d: true }]
  return [fitWidth(line, w)]
}

// The old-engine line, in /units and the pane, as doctor prints it: wrapped at the width between words and never cut,
// so the command that fixes it can be copied whole (a path wider than the view stays whole on its own line). A
// wrapped line is indented two. None when the fetch printed none.
export const engineModel = (s: State, w: number): Line[] => {
  if (!s.engine) return []
  const out: string[] = []
  let cur = ''
  for (const word of s.engine.split(' ')) {
    const next = cur ? `${cur} ${word}` : `${out.length ? '  ' : ''}${word}`
    if (cur.trim() && cols(next) > w) { out.push(cur); cur = `  ${word}` } else cur = next
  }
  if (cur) out.push(cur)
  return out.map((t): Line => [{ t, c: C.bad }])
}

// The Research lane's run is its newest Claude session in the lane's worktree: working while that session wrote in the
// last five minutes.
const WORKING_MS = 5 * 60_000
export const researchText = (s: State): string => {
  const r = s.research
  if (r.state === 'none') return 'no worktree on this machine'
  if (r.lastAt === null) return 'no run recorded'
  const ago = since(r.lastAt, s.now)
  return `${s.now - r.lastAt < WORKING_MS ? 'working' : 'idle'} · last activity ${ago} ago`
}

const head = (t: string, n: number, c: string = C.head): Line => [{ t, c, b: true }, ...(n ? [{ t: ` (${n})`, c }] : [])]
const empty = (t: string): Line => [{ t: `  ${t}`, d: true }]
// One item: a mark, a name, details after it and a value at the right edge. The name gives way first.
const item = (mark: Seg, name: Seg, details: Seg[], right: Seg[], w: number): Line => {
  const fixed = cols(mark.t) + 1 + cols(plain(details)) + (right.length ? cols(plain(right)) + 2 : 0)
  return spread([mark, { t: ' ' }, ...fitWidth([name], Math.max(8, w - fixed)), ...details], right.length ? right : null, w)
}

const todaySeg = (snap: Snap, short = false): Seg => { const d = dayDollars(snap, short); return d === null ? { t: 'today partial', c: C.cost } : { t: `today ${d}`, c: C.cost, b: true } }
// The first of the right parts given, widest first, that spread() keeps at w columns (it drops one wider than w - 3)
// and that leaves the left part given beside it whole (spread() cuts the left to make room for the right: at 40
// columns, `today $4.50 + 2 steps not priced` cut `CONVEYOR · shop paused` to six columns); the last when none is.
const fitting = (rights: Seg[][], w: number, left: Line = []): Seg[] =>
  rights.find(r => cols(plain(r)) + 3 <= w && cols(plain(left)) + cols(plain(r)) + 2 <= w) ?? (rights.at(-1) as Seg[])
// A loop that is not picking, as its control record makes it: `shop paused`, `shop: no loop process`.
// Nothing while every loop runs.
const loopText = (snap: Snap): string => snap.loops
  .map(l => (l.loop === false ? `${l.repo}: no loop process` : l.state && l.state !== 'running' ? `${l.repo} ${l.state}${l.reason ? `: ${l.reason}` : ''}` : ''))
  .filter(Boolean).join(' · ')
// The cards on the belt against the builder cap, for the head of ON THE BELT: `1 of 7`, and `1 of 7, 1 landing not
// counted` for a card that lands or has landed, in Push, the one kind on the belt that takes no slot. With more than
// one project, each project's count after its name: `bakery 1 of 3 · gadgetlab 1`; a project whose loop gives no cap has its count on the belt only. None when the belt is empty and no
// loop gives a cap. While the snapshot is behind, the count is loop.json's now (now): the kept belt can still hold a
// card's old row beside the cards started since, which would count it twice. When now is unknown (a snapshot made where
// the loop does not run has no loop.json to read), the count is health.building, then the belt's cards that take a slot:
// never 0 for a count nobody knows. The Board counts it so only while the snapshot is behind its card records
// (recordsNewer), not when only loop.json is newer.
const beltCounts = (snap: Snap): string[] => {
  const capped = (l: Loop) => l.cap !== null && (l.behind ? l.now ?? l.building : l.building) !== null
  const one = (l: Loop) => {
    const n = l.behind ? l.now ?? l.building ?? l.onBelt - l.landing : capped(l) ? l.onBelt - l.landing : null
    if (n === null) return `${l.onBelt}`
    return l.cap !== null ? `${n} of ${l.cap}${l.landing ? `, ${l.landing} landing not counted` : ''}` : `${n}`
  }
  if (!snap.belt.length && !snap.loops.some(capped)) return []
  if (snap.loops.length > 1) return snap.loops.map(l => `${l.repo} ${one(l)}`)
  return [snap.loops[0] ? one(snap.loops[0]) : `${snap.belt.length}`]
}
// The head of ON THE BELT with its counts in brackets, wrapped at the width when they do not fit on one line.
const beltHead = (snap: Snap, w: number): Line[] => {
  const p = beltCounts(snap)
  if (!p.length) return [head('ON THE BELT', 0)]
  const t = ` (${p.join(' · ')})`
  if (cols(`ON THE BELT${t}`) <= w) return [[{ t: 'ON THE BELT', c: C.head, b: true }, { t, c: C.head }]]
  return wrapParts(p.map((x, i) => `${i ? '' : 'ON THE BELT ('}${x}${i === p.length - 1 ? ')' : ''}`), w, '', ' · ', { c: C.head })
}
const loopSegs = (snap: Snap): Seg[] => (loopText(snap) ? [{ t: ' · ' }, { t: loopText(snap), c: C.you, b: true }] : [])

// The head: CONVEYOR, today's cost and the host (the cost on a line of its own, or its gap on one, when the width
// is short: headerModel); then the weekly limit with its reset, and the counts on the belt and queued.
const queuedText = (snap: Snap) => (snap.queue === null ? 'queue not read' : `${snap.queue.length}${snap.queueMore ? '+' : ''} queued`)
const limitLine = (s: State): Line => {
  const r = s.limit ? resetIn(s.limit.resetsAt, s.now) : ''
  return s.limit ? [{ t: 'weekly limit ', d: true }, { t: `${Math.round(s.limit.pct)}%`, c: s.limit.pct >= 90 ? C.you : C.cost }, ...(r ? [{ t: ` · resets ${r}`, d: true }] : [])]
    : [{ t: 'weekly limit not read', d: true }]
}
export const headerModel = (s: State, snap: Snap, w: number): Line[] => {
  const limit = limitLine(s)
  // A board is only drawn from a snapshot the host just gave: the host named here answered. The day's dollars stay where
  // the host and they do not both fit beside CONVEYOR and a loop that is not picking (spread() drops a right part that
  // is too wide): alone, then in the short form (`$4.10+`) with the host and alone. When not even that fits beside them,
  // the day's dollars go on a line of their own under them, so a paused loop is never cut. With the short form, the
  // day's known dollars and gap go whole on a line of their own under it (gapRow), as in the pane.
  const host: Seg[] = [{ t: '  ' }, { t: '●', c: C.ok }, { t: ` ${s.host}` }]
  const left: Line = [{ t: 'CONVEYOR', c: C.head, b: true }, ...loopSegs(snap)]
  const beside = fitting([[todaySeg(snap), ...host], [todaySeg(snap)], [todaySeg(snap, true), ...host], [todaySeg(snap, true)]], w, left)
  const fits = cols(plain(beside)) + 3 <= w && cols(plain(left)) + cols(plain(beside)) + 2 <= w
  const day = fits ? beside : fitting([[todaySeg(snap)], [todaySeg(snap, true)]], w)
  const dayGap = snap.todayUsd !== null && (snap.todayLeftOut ?? 0) > 0 && !plain(day).startsWith(`today ${dayDollars(snap)}`)
    ? [gapRow(snap.todayUsd, snap.todayLeftOut ?? 0, (snap.todayEstimate ?? 0) > 0, w, w)] : []
  return [
    spread(left, fits ? day : null, w),
    ...(fits ? [] : [spread([], day, w)]),
    ...dayGap,
    spread(limit, [{ t: `${snap.belt.length} on belt · ${queuedText(snap)}`, d: true }], w),
  ]
}

export const needsModel = (s: State, snap: Snap, w: number, short: boolean): Line[] => snap.needs.length ? [
  head('NEEDS YOU', snap.needs.length, C.you),
  ...snap.needs.flatMap((n): Line[] => {
    const mark: Seg = n.yes ? { t: '◆', c: C.you } : { t: '✗', c: C.bad }
    const age = since(n.since, s.now)
    const right: Seg[] = age ? [{ t: age, c: n.yes ? C.you : C.bad }] : []
    const name: Seg = { t: nameOf(n), c: C.name, b: true }
    // Short: one line, the name kept to under half of it so the reason shows. Full: the reason whole, on its own line.
    // The step it stopped in and how long that step ran: the card is off the belt, so it is said here.
    const stopped = stoppedOf(n.track)
    if (short) return [spread([mark, { t: ' ' }, ...fitWidth([name], Math.max(8, Math.floor(w * 0.45))), ...(stopped ? [{ t: ` · ${stopped}`, c: C.bad }] : []), { t: ` · ${whatOf(n)}` }], right.length ? right : null, w)]
    return [
      item(mark, name, [], right, w),
      [{ t: `    ${whatOf(n)}` }],
      ...(stopped ? [[{ t: `    ${stopped}`, c: C.bad }] as Line] : []),
      // Its six steps, as on the belt; then one line a finished review, and the judge on the latest.
      ...(n.track ? trackLines(n.track, w, '   ') : []),
      ...n.reviews.map((r): Line => fitWidth([{ t: `    ${reviewText(r)}`, c: r.verdict === 'GO' ? C.ok : C.you }], w)),
      ...judgeLine(n.reviews, w, '    '),
      ...keptLine(n.track, w, '    '),
      ...metricsLines(n.metrics, w),
    ]
  }),
] : [[{ t: 'NEEDS YOU', c: C.head, b: true }, { t: '  nothing', d: true }]]

// A card's reference on its row (titled): `repo#12 `, or its name.
const refText = (c: Ref) => (c.issue ? `${c.repo}#${c.issue} ` : c.name ? `${named(c)} ` : '')
// The first of the right parts given, widest first, that leaves a card's row (titled) its lead and reference whole
// beside it; the last when none does. fitting() counts no left part, and spread() cuts the left to make room for the
// right: at 40 columns, `GO r1  $4.10 + 1 step not priced` left 6 columns for the time, check mark and issue.
const fittingBeside = (c: Ref, lead: Seg[], rights: Seg[][], w: number): Seg[] => {
  const keep = cols(plain(lead)) + cols(refText(c))
  return rights.find(r => keep + cols(plain(r)) + 2 <= w) ?? (rights.at(-1) as Seg[])
}
// A card's issue and short title in bold with what it came from ("↳ #12"), the figures on the right whole: the
// title is what gives way.
const titled = (c: Ref & { parent: number | null }, lead: Seg[], right: Seg[], w: number, bold = true): Line => {
  const ref: Seg = { t: refText(c), c: C.name, b: bold }
  const parent: Seg[] = c.parent ? [{ t: ` ↳ #${c.parent}`, d: true }] : []
  const fixed = cols(plain(lead)) + cols(ref.t) + cols(plain(parent)) + (right.length ? cols(plain(right)) + 2 : 0)
  const title = fitWidth([{ t: kindOf(c)?.title || shortTitle(c.title) || (c.issue ? '' : 'a branch with no issue'), c: C.name, b: bold }], Math.max(6, w - fixed))
  return spread([...lead, ref, ...title, ...parent], right.length ? right : null, w)
}
// A card's cost so far: its dollars, "no reading yet" before any token is read ("cost shown when the step ends" when the
// running session's route reports no usage until then), with a step not priced the known dollars and the gap (cost()).
const costOf = (b: Belt): Seg => (!b.reading ? { t: b.atEnd ? 'cost shown when the step ends' : 'no reading yet', d: true } : cost(b))
// The finished reviews on one line: one round as its verdict and counts, several each as R1, R2, ...
const verdicts = (rs: Review[]): Seg[][] => rs.map(r => {
  const f = findingsOf(r, ' ')
  return [{ t: rs.length > 1 ? `R${r.round} ` : '', d: true }, { t: r.verdict || 'no verdict', c: r.verdict === 'GO' ? C.ok : C.you }, ...(f ? [{ t: ` ${f}`, c: C.you }] : [])]
})

// A card that waits for the landing turn, as the card that has it: by that card's ID in the tables (idOf: `#1590`,
// `fu #1590`, `red 19e3b6e`), not by the card id the engine's live text holds: at its land step (landwait(),
// lib/claim.sh) or queued for the next batch at its claim. Only when that card id is the snapshot's waitsOn: the live
// text streams in between snapshots, so waitsOn can still name the card that had the turn before. "" for any other
// live text. The ID comes first and the kind of wait next (`lands` or `next`): WORKER ACTIVITY cuts the text before
// the clock on the right, and at 40 columns a row of a part (`#1593 of #1600`) leaves about 11 columns of it.
const turnWait = (b: Belt): { id: string, kind: string, text: string } | null => {
  const m = /^(?:waiting for card (\S+) to land first\b|queued for the next batch: card (\S+) has the landing turn\b)/.exec(b.live?.action ?? '')
  if (!m || !b.waitsOn || (m[1] ?? m[2]) !== b.waitsOn.card) return null
  const id = idOf(b.waitsOn), kind = m[1] ? 'lands' : 'next'
  return { id, kind, text: m[1] ? `${id} ${kind} first (landing turn)` : `${id} ${kind} batch (has the landing turn)` }
}
// The running step's live fields: `    now Bash: npm test · 3 turns · last output 4s ago`. None when it streams nothing.
// The Test step runs no model, so in place of its turns it shows how far the tests are: the file that runs now and its
// time on it, `file 2 of 3: conveyor/tests/b.test.sh, 4m, 2 failed` (#433: the cases of the files that ended are no
// total), else `142 of 205 tests · 2 failed`, else `3 of 6 test files` (and ` · 15 more files than selected` when more ran), else nothing.
const liveLine = (b: Belt, now: number, w: number): Line[] => {
  const l = b.live
  if (!l || (!l.action && l.turns === null && l.lastOutputAt === null)) return []
  const ago = l.lastOutputAt === null ? '' : fmtStep((now - l.lastOutputAt) / 1000)
  const t = b.track, tests = t?.tests, files = t?.files
  const progress = t?.at !== 3 ? (l.turns === null ? '' : count(l.turns, 'turn'))
    : files?.now && files.of !== null ? `file ${Math.min(files.run + 1, files.of)} of ${files.of}: ${files.now.file}${files.now.at === null ? '' : `, ${fmtStep(Math.max(0, (now - files.now.at) / 1000))}`}${tests?.failed ? `, ${tests.failed} failed` : ''}`
    : tests ? `${tests.done} of ${tests.of} tests${tests.failed ? ` · ${tests.failed} failed` : ''}`
    : files ? `${files.run}${files.of === null ? '' : ` of ${files.of}`} test files${files.over ? ` · ${count(files.over, 'more file')} than selected` : ''}` : ''
  // The Test step's list: the changed tests (how many files) or the whole suite.
  const list = t?.at !== 3 || !t.list ? '' : t.list.mode === 'changed' ? `changed: ${count(t.list.files, 'file')}` : 'whole suite'
  const parts = [l.action ? `now ${turnWait(b)?.text || l.action}` : '', list, progress, ago ? `last output ${ago} ago` : ''].filter(Boolean)
  return [fitWidth([{ t: `    ${parts.join(' · ')}`, d: true }], w)]
}

// ON THE BELT: three lines a card and a blank line between cards. 1: the issue and its short title
// in bold, then when it was picked up, its overall time so far and its cost, right-aligned. 2: the six steps as one
// track. 3: the round ("round 1 of 3"), each finished round's verdict with its counts, and the measured time in the
// step it is in. No time is estimated. In /units, a latest review the judge ran on adds its counts on a dim line.
// While a step streams, its live fields follow on a dim line of their own.
export const beltModel = (s: State, snap: Snap, w: number, short: boolean, frame: number): Line[] => [
  ...beltHead(snap, w),
  ...(snap.belt.length ? [] : [empty('the belt is empty')]),
  ...snap.belt.flatMap((b, i): Line[] => {
    const all = overallOf(b, s.now)
    const times: Seg[] = [...(b.start !== null ? [{ t: `${whenOf(b.start, s.now)} · `, d: true }] : []), ...(all !== null ? [{ t: `${fmtSec(all)} · `, d: true }] : [])]
    // Where the cost in full does not fit beside the issue, it is `$4.10+`, its known dollars and gap under the row.
    const right = fittingBeside(b, [{ t: ' ' }], [[...times, costOf(b)], ...(b.reading ? [[...times, cost(b, true)], [cost(b, true)]] : [])], w)
    const gap = right.at(-1)?.t === costOf(b).t ? [] : gapLine(b, 3, w)
    const t = b.track
    const rv = t?.steps[1]
    // The review round in progress, or the one just reviewed while it is fixed; past the reviews, none.
    const round = t && t.at !== null && t.at <= 2 && rv && rv.of !== null ? (t.at === 1 ? rv.n : b.reviews.length) : null
    const parts: Seg[][] = [...(round ? [[{ t: `round ${round} of ${rv!.of}`, d: true }] as Seg[]] : []), ...verdicts(b.reviews)]
    const doing = doingText(t, t?.since ?? b.stepAt, s.now)
    const tail: Seg[] = doing ? [{ t: doing, c: t?.steps[5].state === 'failed' && t.at === 5 ? C.bad : C.work }] : []
    // The verdicts give way from the oldest, never in the middle of one.
    let shown = parts
    const width = (p: Seg[][]) => cols(plain(p.flat())) + Math.max(0, p.length - 1) * 3 + 1 + (tail.length ? cols(plain(tail)) + 3 : 0)
    while (shown.length > 1 && width(shown) > w) shown = shown.slice(1)
    const joined: Seg[] = [{ t: ' ' }, ...(shown !== parts ? [{ t: '… · ', d: true }] : []), ...shown.flatMap((p, k) => (k ? [{ t: ' · ', d: true }, ...p] : p))]
    const third: Line = shown.length ? spread(joined, tail.length ? tail : null, w) : [{ t: ' ' }, ...tail]
    return [
      ...(i ? [[] as Line] : []),
      titled(b, [{ t: ' ' }], right, w),
      ...gap,
      ...(t ? trackLines(t, w) : [[{ t: ` ${workMark(frame)} ${stepOf(b)}`, c: C.work }] as Line]),
      ...(t || b.reviews.length ? [third] : []),
      ...(short ? [] : judgeLine(b.reviews, w, '   ')),
      ...(short ? [] : keptLine(t, w, '   ')),
      // A failed Push says why: the push's error, or that GitHub kept the issue open; cut at the width.
      ...(t && t.at === 5 && t.steps[5].state === 'failed' && t.reason ? [fitWidth([{ t: `   ✗ ${t.reason}`, c: C.bad }], w)] : []),
      ...liveLine(b, s.now, w),
    ]
  }),
]

// An issue waited on, with why it does not move when the snapshot says: `#967 (held)`.
const waitRef = (x: Waiting, n: number) => `#${n}${x.states[n] ? ` (${x.states[n]})` : ''}`
// Every issue the waiting ones wait on, once each (a project's own), lowest first, with its state; the last ends in no comma.
// With waiting issues in more than one project each ref names its project (`own` for the open project, whose repo is ''),
// as two projects can wait on a #80 each.
const waitedOn = (ws: Waiting[], own: string) => {
  const seen = new Map<string, [number, string]>()
  const named = new Set(ws.map(x => x.repo)).size > 1
  for (const x of ws) for (const n of x.waitsFor) if (!seen.has(`${x.repo}#${n}`) || x.states[n]) seen.set(`${x.repo}#${n}`, [n, `${named ? x.repo || own : ''}${waitRef(x, n)}`])
  return [...seen.values()].sort((a, b) => a[0] - b[0]).map(([, r], i, l) => (i < l.length - 1 ? `${r},` : r))
}

// The open issues whose card landed while push is off and that wait for the push: done, not open work, on any day
// (LANDED TODAY lists only today's). One line, wrapped at its issues: `landed, not pushed: #12 · #15`.
const unpushedLines = (snap: Snap, w: number, lead: string): Line[] => {
  const l = snap.unpushed ?? []
  return l.length ? wrapParts(['landed, not pushed:', ...l.map((x, i) => `${x.repo}#${x.issue}${i < l.length - 1 ? ' ·' : ''}`)], w, lead, ' ', { d: true }) : []
}

// A part of a wrapped line cut into pieces of at most `room` columns, at its spaces, so wrapParts never cuts it: a
// word wider than the line (a log path) is broken between whole characters (graphemes), so an emoji and its
// variation selector stay on one line.
const GRAPHEMES = new Intl.Segmenter(undefined, { granularity: 'grapheme' })
const pieces = (t: string, room: number): string[] => {
  if (room < 1 || cols(t) <= room) return [t]
  const out: string[] = []
  let cur = ''
  for (const word of t.split(' ')) {
    const next = cur ? `${cur} ${word}` : word
    if (cols(next) <= room) { cur = next; continue }
    if (cols(word) <= room) { out.push(cur); cur = word; continue }
    // A word wider than the line goes on from where the line is.
    if (cur && cols(cur) < room) cur += ' '
    else if (cur) { out.push(cur); cur = '' }
    for (const { segment: ch } of GRAPHEMES.segment(word)) { if (cur && cols(cur + ch) > room) { out.push(cur); cur = '' } cur += ch }
  }
  return cur ? [...out, cur] : out
}
// A note (a fetch that failed, a record not read, the pane's first wait) wrapped at its spaces to the pane's width
// (a word wider than the pane broken between whole characters, by pieces), never cut:
// the terminal wraps a line wider than a dock, and a cut note loses its reason.
export const noteLines = (t: string, w: number, style: Omit<Seg, 't'> = { c: C.you }): Line[] => pieces(t, w).map(p => fitWidth([{ ...style, t: p }], w))

// What the pick held back, a count a rule, wrapped at its counts, never cut: at 40 columns four rules are wider than
// the pane, and a cut line drops the last count. `held back: 1 follow-ups · 1 P0 · 1 P1 · 1 P2`. A count whose rule
// is wider than the line (a long label name) goes on over lines, at its spaces, and a word in it wider than the line
// is broken between whole characters (pieces).
const heldLines = (snap: Snap, w: number, lead: string): Line[] =>
  snap.held.length ? wrapParts(['held back:', ...snap.held.flatMap(([label, n], i, l) => pieces(`${n} ${label}${i < l.length - 1 ? ' ·' : ''}`, w - cols(lead) - 2))], w, lead, ' ') : []

// Each project's push, so a slow push is told from a stuck one. In progress: what runs (its stage, PUSH_STAGE, as
// pushing() in conveyor/lib/push.sh writes it; none is the hook's), since when, on which commit, its process and the time it
// has taken, then the newest line of its output; stale, with its log, when its process is gone and it did not end.
// Else the last push that ended, for an hour, or while landed commits still wait for a push and it did not work:
// pushed, or failed with the failed check and its log, or started no push; and main still ahead of the remote after
// it. Each part wraps to a line of its own rather than be cut: a part wider than the line goes on more lines, at its
// spaces, and a word wider than the line (a log path) is broken.
const LAST_PUSH_MS = 3_600_000
const PUSH_STAGE: Record<string, string> = { tests: 'tests before the push running', ready: 'getting the push ready (worktree, dependencies, test slot)',
  hook: 'pre-push hook running', push: 'push running with no pre-push hook', ended: 'git push ended, finishing the push', pushed: 'pushed, waiting for GitHub' }
const pushLines =(s: State, snap: Snap, w: number, lead: string): Line[] => (snap.pushes ?? []).flatMap((p): Line[] => {
  const of = snap.loops.length > 1 ? `${p.repo}: ` : '', r = p.running, l = p.last
  const room = w - cols(lead) - 2
  const wrap = (parts: string[], c: string) => wrapParts(parts.flatMap(t => pieces(t, room)), w, lead, ' · ', { c })
  const log = (f: string) => (f ? [`Log: ${f}`] : [])
  if (r) {
    const on = r.sha ? ` on ${r.sha.slice(0, 12)}` : '', pid = r.pid === null ? '' : `pid ${r.pid}`
    if (r.stale) return wrap([`✗ ${of}push${on} is stale: its process${pid ? ` (${pid})` : ''} is gone and the push did not end`, ...log(r.log)], C.bad)
    const sec = r.since !== null ? (s.now - r.since) / 1000 : r.sec
    return [
      ...wrap([`${of}push${on}: ${(Object.prototype.hasOwnProperty.call(PUSH_STAGE, r.stage) ? PUSH_STAGE[r.stage] : '') || PUSH_STAGE.hook}${r.since !== null ? ` since ${clockOf(r.since)}` : ''}`,
        ...(pid ? [pid] : []), ...(sec !== null ? [fmtStep(sec)] : [])], C.work),
      ...(r.line ? [fitWidth([{ t: `${lead}  ${r.line}`, d: true }], w)] : []),
    ]
  }
  if (!l || l.at === null || (s.now - l.at >= LAST_PUSH_MS && (l.ok || !p.unpushed))) return []
  const who = l.by === 'now' ? 'Push now' : l.by === 'full' ? 'Push landed' : 'Push'
  const ahead = l.ahead ? [`main is still ${l.ahead} ${l.ahead === 1 ? 'commit' : 'commits'} ahead of the remote`] : []
  if (!l.started) return wrap([`✗ ${of}${who} started no push${l.why ? `: ${l.why}` : ''}`, ...ahead], C.bad)
  const at = l.sha ? ` ${l.sha.slice(0, 12)}` : ''
  if (!l.ok) return wrap([`✗ ${of}${who} of${at} failed${l.check ? `: ${l.check} failed` : ''}`, ...log(l.log), ...ahead], C.bad)
  return wrap([`✓ ${of}${who} of${at} passed ${since(l.at, s.now)} ago`, ...ahead], ahead.length ? C.you : C.ok)
})

// QUEUE: the next five, numbered, the title cut to fit and the priority right-aligned; then the
// held-back line.
const NEXT = 5
// The next five issues the engine picks, numbered, the title cut to fit and the priority right-aligned. The one the
// machine holds back says why, with the figure that held it: wrapped at its words, as the figure is last.
// The follow-up and retried flags sit beside the priority when the title keeps 6 columns of room; else they go under the row.
const readyRows = (snap: Snap, w: number): Line[] => (snap.queue ?? []).slice(0, NEXT).flatMap((q, i): Line[] => {
  const prio: Seg = { t: q.priority || 'P3', c: q.priority === 'P0' || q.priority === 'P1' ? C.you : undefined, d: !(q.priority === 'P0' || q.priority === 'P1') }
  const flags = [...(q.followup ? ['follow-up'] : []), ...(q.retried ? ['retried'] : [])].join(' · ')
  const beside = !flags || cols(` ${i + 1} `) + cols(`${q.repo}#${q.issue} `) + (q.parent ? cols(` ↳ #${q.parent}`) : 0) + 6 + 2 + cols(`${prio.t} · ${flags}`) <= w
  return [titled(q, [{ t: ` ${i + 1} `, d: true }], beside && flags ? [prio, { t: ` · ${flags}`, d: true }] : [prio], w, false),
    ...(flags && !beside ? [[{ t: `    ${flags}`, d: true }] as Line] : []),
    ...(q.room ? wrapParts(q.room.split(' '), w, '    ', ' ') : [])]
})
export const queueModel = (snap: Snap, w: number): Line[] => {
  const next = (snap.queue ?? []).slice(0, NEXT)
  const all = snap.queue?.length ?? 0, more = all > NEXT || snap.queueMore
  return [
    [{ t: 'QUEUE', c: C.head, b: true }, ...(next.length ? [{ t: more ? `  next ${next.length} of ${all}${snap.queueMore ? '+' : ''}` : `  ${next.length}`, d: true }] : [])],
    // A queue whose only issues wait on others is not empty: nothing can be picked, and it names what they wait on.
    ...(snap.queue === null ? [empty('not read: GitHub did not list the issues')] : next.length ? []
      : snap.waits.length ? wrapParts(['nothing can be picked: waiting for', ...waitedOn(snap.waits, snap.own ?? '')], w, '  ', ' ', { d: true })
      : [empty('the queue is empty')]),
    ...readyRows(snap, w),
    // The issues that wait on another: not in the pick order, each with what it waits for.
    // A label too long to sit beside the title (with room for 6 columns of it) goes under it, wrapped at its words:
    // beside it, spread would drop the label whole.
    ...snap.waits.slice(0, NEXT).flatMap((x): Line[] => {
      const refs = x.waitsFor.map((n, i, l) => `${waitRef(x, n)}${i < l.length - 1 ? ',' : ''}`), label = `Waits for ${refs.join(' ')}`
      return cols(` · ${x.repo}#${x.issue} `) + 6 + 2 + cols(label) <= w
        ? [titled({ ...x, parent: null }, [{ t: ' · ', d: true }], [{ t: label, d: true }], w, false)]
        : [titled({ ...x, parent: null }, [{ t: ' · ', d: true }], [], w, false), ...wrapParts(['Waits for', ...refs], w, '    ', ' ')]
    }),
    ...(snap.waits.length > NEXT ? [empty(`and ${snap.waits.length - NEXT} more waiting`)] : []),
    ...heldLines(snap, w, ' '),
    ...unpushedLines(snap, w, ' '),
  ]
}

// Shown only when an issue waits: the loop never picks these, and only your deploy (and your removing the label) clears them.
export const deployModel = (s: State, snap: Snap, w: number): Line[] => [
  head('BUILT, WAITING FOR YOUR PROD DEPLOY', snap.deploy.length),
  ...snap.deploy.map((d): Line => {
    // A deploy can wait for weeks: whole days once it has waited one.
    const days = d.since ? Math.floor((s.now - d.since) / 86_400_000) : 0
    const age = days >= 1 ? `${days}d` : since(d.since, s.now)
    return item({ t: '·', d: true }, { t: nameOf(d) }, [], age ? [{ t: `waiting ${age}`, d: true }] : [], w)
  }),
]

// LANDED TODAY: the count of every card landed today and the day's cost in the heading; per card the time it landed, a check
// mark, the issue and short title, the last verdict and its round, and the cost ("pushing" in place of it while the
// push runs, what it waits for while no step runs: "Landed, waiting for Push landed" with push off); beneath, when it was picked up and its overall time to the landing, and the follow-ups it filed.
export const landedModel = (s: State, snap: Snap, w: number, short: boolean): Line[] => {
  const shown = short ? snap.landed.slice(0, NEXT) : snap.landed
  // The day's cost is today's priced steps (the head's figure), not the lifetime cost of the cards that landed today;
  // its gap in the short form (`$4.10+`) where the whole text does not fit (the head gives it whole).
  const heading = (short: boolean): Line => [{ t: 'LANDED TODAY', c: C.head, b: true },
    ...(snap.landed.length ? [{ t: `  ${snap.landedCount} · `, d: true }, { t: dayDollars(snap, short) ?? 'cost partial', c: C.cost }] : [])]
  const pad = '         '
  return [
    cols(plain(heading(false))) <= w ? heading(false) : heading(true),
    ...(snap.landed.length ? [] : [empty('nothing landed today')]),
    ...shown.flatMap((l): Line[] => {
      const last = l.rounds.at(-1)
      const verdict: Seg[] = l.closed ? [{ t: 'already fixed', d: true }]
        : last ? [{ t: last.verdict || 'no verdict', c: last.verdict === 'GO' ? C.ok : C.you }, { t: ` r${last.round}`, d: true }]
          : [{ t: count(l.reviews, 'review'), d: true }]
      const state: Seg | null = l.push === 'now' ? { t: 'pushing', c: C.you } : l.issueOpen ? { t: 'issue open', c: C.you } : l.waits ? { t: l.waits, c: C.you }
        : l.push === 'failed' || l.pushed === false ? { t: 'not pushed', c: C.you } : null
      const lead: Seg[] = [{ t: ` ${l.at ? clockOf(l.at) : 'time?'} `, d: true }, { t: '✓ ', c: C.ok }]
      // Its cost where it fits in full beside the issue, else `$4.10+` with its known dollars and gap under the row.
      const right = fittingBeside(l, lead, state ? [[...verdict, { t: '  ' }, state]]
        : [[...verdict, { t: '  ' }, cost(l)], [...verdict, { t: '  ' }, cost(l, true)], [cost(l, true)]], w)
      const gap = state || right.at(-1)?.t === cost(l).t ? [] : gapLine(l, pad.length, w)
      const all = overallOf(l, s.now)
      const under = [...(l.start !== null ? [`started ${whenOf(l.start, s.now)}`] : []), ...(all !== null ? [`${fmtSec(all)} overall`] : []),
        ...(l.followups.length ? [`↳ ${count(l.followups.length, 'follow-up')}: ${l.followups.map(n => `#${n}`).join(' ')}`] : []),
        ...(!short && judgeText(l.rounds) ? [judgeText(l.rounds)] : [])]
      return [titled(l, lead, right, w, false), ...gap, ...(under.length ? wrapParts(under, w, pad) : [])]
    }),
    ...(snap.landedCount > shown.length ? [empty(`+${snap.landedCount - shown.length} more`)] : []),
  ]
}

// A lane with no worktree on this machine is not drawn: a project that set up no lanes has nothing to say about them.
export const lanesModel = (s: State): Line[] => [
  ...(s.fast.state === 'none' ? [] : [[{ t: 'FAST LANE', c: C.head, b: true }, { t: `      ${fastText(s)}` }] as Line]),
  ...(s.research.state === 'none' ? [] : [[{ t: 'RESEARCH LANE', c: C.head, b: true }, { t: `  ${researchText(s)}` }] as Line]),
]

// The findings the judge declined today, by this machine's day.
const declinedTodayText =(s: State, snap: Snap): string => {
  const day = new Date(s.now).toDateString()
  const n = snap.judgeDeclined.filter(t => new Date(t).toDateString() === day).length
  return `judge declined ${n ? count(n, 'finding') : 'no findings'} today`
}

// A whole-suite run (a release's suite, the full test): while it runs, a line with its kind, short commit and time running, and, when there are counts to show, a second
// line with the cases done and failures so far (none while a box is before or after its tests; the second line holds a rerun's progress while a release reruns failed cases); once it ended, one line with its result for SUITE_SHOWN_MS, then nothing.
export const SUITE_SHOWN_MS = 10 * 60 * 1000
// A suite on another machine gives minutes and seconds, as the box's steps are short, and names the machine after the commit.
const BOX_STEP: Record<string, string> = { start: 'starting the box', setup: 'setting up', checkout: 'checking out', results: 'bringing back results' }
const mSec = (s: number) => { const n = Math.max(0, Math.floor(s)); return `${Math.floor(n / 60)}m ${n % 60}s` }
export const suitesModel = (s: State, snap: Snap, w: number): Line[] => (snap.suites ?? [])
  .filter(x => x.ended === null || s.now - x.ended < SUITE_SHOWN_MS)
  .flatMap((x): Line[] => {
    const m = x.machine
    const what = `${x.repo ? `${x.repo} ` : ''}${x.kind === 'release' ? `release ${x.version}` : x.kind}${x.sha ? ` · ${x.sha.slice(0, 7)}` : ''}${m ? ` · on ${m.name}` : ''}`
    // A box's steps before and after its tests have no counts to show: the record holds 0 until the tests run.
    const counting = !m || x.ended !== null || m.step === 'run'
    const failed = counting && (x.failed || (m && x.ended === null && x.done !== null)) ? [{ t: ` · ${count(x.failed ?? 0, 'failure')}`, c: C.bad }] : []
    const run = x.since === null ? '' : ` ${(m ? mSec : fmtSec)((s.now - x.since) / 1000)}`
    // While a release's failed cases run again, the pass under way and its own progress, not the first pass's counts.
    // The progress goes on a second line: one line is over 80 columns and the pane would cut off its failures and time.
    const r = x.rerun
    if (x.ended === null && r) {
      const progress = [...(r.done === null ? [] : [{ t: `${count(r.done, 'file')} done`, d: true }]), ...(r.failed ? [{ t: `${r.failed} failed`, c: C.bad }] : []),
        ...(r.at === null ? [] : [{ t: `moved ${fmtSec((s.now - r.at) / 1000)} ago`, d: true }])]
      // The pass is the line's end: when the line is wider than the pane it goes on a line of its own, and on a pane too
      // narrow even for that, split before the pass, never cut.
      const pass = `pass ${r.pass}${r.of === null ? '' : ` of ${r.of}`}`
      const again = `failed cases again: ${pass}`
      return [...(cols(`${what} · ${again}`) <= w ? [[{ t: what, c: C.work, b: true }, { t: ` · ${again}`, d: true }] as Line]
        : [[{ t: what, c: C.work, b: true }] as Line, ...(cols(`  ${again}`) <= w ? [again] : ['failed cases again:', pass]).map((p): Line => [{ t: `  ${p}`, d: true }])]),
        ...(progress.length ? [[{ t: '  ', d: true }, ...progress.flatMap((p, i) => (i ? [{ t: ' · ', d: true }, p] : [p]))] as Line] : [])]
    }
    if (x.ended === null) {
      // A box that is not yet running the tests says its step, not "running".
      const step = m && BOX_STEP[m.step] ? `${BOX_STEP[m.step]}${run}` : `running${run}`
      // The counts go on a second line, as for the rerun: with a machine's name the one line is over 80 columns and the pane would cut them off.
      const counts: Seg[] = [...(x.done === null || !counting ? [] : [{ t: `${count(x.done, 'case')} done`, d: true }]), ...failed.map(f => ({ ...f, t: f.t.slice(3) }))]
      return [[{ t: what, c: C.work, b: true }, { t: ` · ${step}`, d: true }],
        ...(counts.length ? [[{ t: '  ', d: true }, ...counts.flatMap((c, i) => (i ? [{ t: ' · ', d: true }, c] : [c]))] as Line] : [])]
    }
    const good = x.state === 'passed' || x.state === 'released'
    const took = m && x.since !== null ? ` ${mSec((x.ended - x.since) / 1000)}` : ''
    const ago = m ? `${Math.max(1, Math.floor((s.now - x.ended) / 60000))} min` : fmtSec((s.now - x.ended) / 1000)
    return [[{ t: what, c: good ? C.ok : C.bad, b: true }, { t: ` · ${x.state || 'ended'}${took}${m ? ' · ' : ' '}${ago} ago`, d: true }, ...failed,
      ...(m?.given ? [{ t: ' · box given back', d: true }] : [])]]
  })

const noteLine = (s: State): Line => [{ t: s.note, c: C.you }]
const board = (s: State, snap: Snap, w: number, short: boolean, frame: number): Line[] => [
  ...headerModel(s, snap, w),
  ...(short ? [] : [[{ t: declinedTodayText(s, snap), d: true }] as Line]),
  ...foremanModel(s, w),
  ...engineModel(s, w),
  ...testMapModel(s, w),
  ...suitesModel(s, snap, w).map(l => (short ? fitWidth(l, w) : l)), [],
  ...needsModel(s, snap, w, short), [],
  ...beltModel(s, snap, w, short, frame), ...pushLines(s, snap, w, ' '), [],
  ...queueModel(snap, w), [],
  ...(snap.deploy.length ? [...deployModel(s, snap, w), []] : []),
  ...landedModel(s, snap, w, short),
  ...(lanesModel(s).length ? [[], ...lanesModel(s).map(l => (short ? fitWidth(l, w) : l))] : []),
  ...(notesOf(s).length ? [[], ...notesOf(s).map((n): Line => [{ t: n, c: C.you }])] : []),
]

// `/units`: every section in full. A snapshot that cannot be read is one plain line, and the Foreman indicator: the
// Foreman's state is read from its folder, not from the snapshot.
// A record's kept snapshot over a minute old says its age, counted at the time the view is drawn.
export const ageNotes = (s: State): string[] =>
  (s.snap?.kept ?? []).filter(k => s.now - k.at > 60_000).map(k => `units: the ${k.repo} snapshot is ${since(k.at, s.now)} old (made at ${clockOf(k.at)})`)
const notesOf = (s: State): string[] => [...s.notes, ...ageNotes(s)]
export const tableText = (s: State, w: number): string => (s.snap ? board(s, s.snap, w, false, 0) : [noteLine(s), ...foremanModel(s, w), ...engineModel(s, w), ...testMapModel(s, w)]).map(plain).join('\n')

// The side pane, the Build matrix layout (#497): the head, the count band, the Foreman's state, Machine details (one
// toggle line until it is opened), then BUILD MATRIX, WORKER ACTIVITY, PICK ORDER and LANDED TODAY, each a table that
// scans. A line that would wrap is cut at the width; a note (a fetch error, a record not read) wraps at its spaces,
// and a word in it wider than the pane (a host file path) breaks between whole characters (pieces).
const padR = (t: string, n: number) => `${t}${' '.repeat(Math.max(0, n - cols(t)))}`
const padL = (t: string, n: number) => `${' '.repeat(Math.max(0, n - cols(t)))}${t}`
const rule = (w: number): Line => [{ t: '─'.repeat(w), d: true }]
const section = (title: string, right: string, w: number): Line => spread([{ t: title, c: C.head, b: true }], right ? { t: right, d: true } : null, w)
// A card's ID in a table: `#<issue>`; with no issue, short so no name pushes a column: its kind and parent (kindOf), any other `card` and the number its card id ends in (a card id ending in `-0` has no number: `card`). The matrix shows the card's work in the Title column.
const idOf = (c: Card) => {
  if (c.issue) return `#${c.issue}`
  const kind = kindOf(c)
  if (kind) return kind.id
  const n = /-([1-9]\d{0,6})$/.exec(c.card)?.[1]
  return n ? `card ${n}` : 'card'
}
// A card that is a part of a parent issue names it: `#636 of #647`.
const beltId = (b: Belt) => `${idOf(b)}${b.umbrella && (b.issue || !kindOf(b)) ? ` of #${b.umbrella}` : ''}`
// The pick order's counts, the parts of one parent issue counted as one entry: ready when any part is ready, else
// waiting when any part waits.
const pickCounts = (snap: Snap): { ready: number; waiting: number } => {
  const key = (x: { repo: string; issue: number; umbrella: number | null }) => `${x.repo}#${x.umbrella ?? x.issue}`
  const ready = new Set((snap.queue ?? []).map(key))
  // snap.queue stops at ten: a parent whose ready part is further down the order is not waiting either.
  const inOrder = new Set([...ready, ...(snap.order ?? []).map(key)])
  return { ready: ready.size, waiting: new Set(snap.waits.map(key).filter(k => !inOrder.has(k))).size }
}

// The step marks of the matrix, as its legend reads: a step the card did not reach, skipped (Fix after a GO) or still
// to come, is the dim `·`. The current step of a card that waits on another card (its waitsOn) is `‖` (WAIT_MARK).
const WAIT_MARK: Seg = { t: '‖', c: C.work }
const MARK: Record<Step['state'], Seg> = { done: { t: '✓', c: C.ok }, now: { t: '▶', c: C.work, b: true }, failed: { t: '✗', c: C.you, b: true }, skipped: { t: '·', d: true }, todo: { t: '·', d: true } }
// A card with no track (an older engine) has only its step: the steps before it done, the ones after not reached.
const STEP_AT: Record<string, number> = { build: 0, review: 1, fix: 2, tests: 3, landing: 4, push: 5, issue: 5 }
const markOf = (b: Belt) => (st: Step['state']): Seg => (st === 'now' && b.waitsOn ? WAIT_MARK : MARK[st])
const statesOf = (b: Belt): Step['state'][] => (b.track ? b.track.steps.map(st => st.state)
  : STEP_NAMES.map((_, i) => { const at = STEP_AT[b.step]; return at === undefined || i > at ? 'todo' : i < at ? 'done' : 'now' }))
// While the snapshot is behind, the count is loop.json's now; when that is unknown, health.building, then the belt's
// cards that take a slot (not those in Push), as in the head of ON THE BELT: never 0 for a count nobody knows. The
// loop's count of cards that wait follows, `· 2 waiting`, when it is above 0 and `wait` is on; with no count, none is shown.
const slotsOf = (l: Loop, wait = true) => {
  const n = l.behind ? l.now ?? l.building ?? l.onBelt - l.landing : l.building ?? l.onBelt
  return `${l.cap !== null ? `${n}/${l.cap} slots` : `${n} building`}${wait && l.waiting ? ` · ${l.waiting} waiting` : ''}`
}
// A text with its waiting part (text(true)) where it fits `room` columns whole, else the text with none (text(false)):
// the waiting part goes first, so a narrow pane shows the project, its slots and the legend as before it was added.
const withWait = (room: number, text: (wait: boolean) => string) => { const t = text(true); return cols(t) <= room ? t : text(false) }

// One project's matrix: ID, a column a step (headed by its first letter), Age, Cost and last the title, which takes
// the rest of the row's width at any pane width (#603). Age goes first when the row does not fit; the title is left
// out when fewer than 6 columns are left after Cost. A card with a step not priced has `$4.10+` in Cost, and its known
// dollars and the gap in full on a line under its row: in the shared column they widened every row, and a narrow pane
// cut the costs off. Where the row with its Cost column is wider than the pane even without Age, the column is left
// out and each card's dollars go on the line under its row in full (dollarsLine), so a cost is never cut.
const matrixTable = (s: State, cards: Belt[], w: number): Line[] => {
  const rows = cards.map(b => {
    const all = overallOf(b, s.now)
    return { b, id: beltId(b), age: all === null ? '–' : fmtSec(all), cost: !b.reading ? '–' : cardDollars(b, true) ?? 'partial' }
  })
  const idW = Math.max(2, ...rows.map(r => cols(r.id))), ageW = Math.max(3, ...rows.map(r => cols(r.age))), costW = Math.max(4, ...rows.map(r => cols(r.cost)))
  const stepsW = STEP_NAMES.length * 2 - 1
  const costCol = idW + 2 + stepsW + 2 + costW <= w
  const noAge = idW + 2 + stepsW + (costCol ? 2 + costW : 0)
  const age = noAge + 2 + ageW <= w
  const fixed = noAge + (age ? 2 + ageW : 0)
  const titleW = w - fixed - 2 >= 6 ? w - fixed - 2 : 0
  const head = `${padR('ID', idW)}  ${STEP_NAMES.map(n => n[0]).join(' ')}${age ? `  ${padL('Age', ageW)}` : ''}${costCol ? `  ${padL('Cost', costW)}` : ''}${titleW ? '  Title' : ''}`
  // The card's own name (no project name: the heading has it) goes before its title.
  const text = (b: Belt) => kindOf(b)?.title || [b.issue ? '' : b.name, shortTitle(b.title)].filter(Boolean).join(' ') || (b.issue ? '' : 'a branch with no issue')
  const title = (b: Belt): Line => [{ t: '  ' }, ...fitWidth([{ t: text(b), c: C.name }], titleW)]
  return [
    fitWidth([{ t: head, d: true }], w),
    ...rows.flatMap((r): Line[] => [fitWidth([
      { t: padR(r.id, idW), c: C.name, b: true }, { t: '  ' },
      ...statesOf(r.b).flatMap((st, i) => [...(i ? [{ t: ' ' }] : []), markOf(r.b)(st)]),
      ...(age ? [{ t: `  ${padL(r.age, ageW)}`, d: true }] : []),
      ...(costCol ? [{ t: '  ' }, { t: padL(r.cost, costW), c: C.cost }] : []),
      ...(titleW ? title(r.b) : []),
    ], w), ...(!r.b.reading ? [] : costCol ? gapLine(r.b, idW + 2, w) : dollarsLine(r.b, idW + 2, w))]),
    fitWidth([{ t: withWait(w, wait => `▶ running ${wait ? '‖ waiting ' : ''}· pending ✓ done ✗ failed`), d: true }], w),
  ]
}
// BUILD MATRIX: a matrix for each project with cards on the belt, its name and slots on the right; every other project
// one dim line. With no card on the belt, the first project's head and one dim line.
export const matrixModel = (s: State, snap: Snap, w: number): Line[] => {
  const own = snap.own ?? ''
  const groups = [...snap.loops].sort((a, b) => Number(b.repo === own) - Number(a.repo === own))
    .map(l => ({ l, cards: snap.belt.filter(b => (b.repo || own) === l.repo) }))
  const full = groups.filter(g => g.cards.length), idle = groups.filter(g => !g.cards.length)
  // section() (spread) drops a right side wider than w - 3 whole.
  const right = (l: Loop) => withWait(w - 3, wait => `${l.repo} · ${slotsOf(l, wait)}`)
  return [
    ...(full.length ? full.flatMap((g, i) => [...(i ? [[] as Line] : []), section('BUILD MATRIX', right(g.l), w), ...matrixTable(s, g.cards, w)])
      : [section('BUILD MATRIX', idle[0] ? right(idle[0].l) : '', w), empty('nothing on the belt')]),
    ...(full.length ? idle : idle.slice(1)).map(g => fitWidth([{ t: withWait(w, wait => `  ${g.l.repo} ${slotsOf(g.l, wait)}`), d: true }], w)),
  ]
}

// A live command made short: a path in the card's own worktree (its folder is named by the card id) reads
// `worktree`, any other absolute or home path its last part, so no machine path is shown.
const PATH_END = `[^\\s'"\`;|&)]`
export const shortCommand = (cmd: string, card: string): string => {
  const esc = card.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  const inTree = card ? cmd.replace(new RegExp(`~?/${PATH_END}*?/${esc}(?=/|[\\s'"\`;|&)]|$)`, 'g'), 'worktree') : cmd
  return inTree.replace(new RegExp(`(^|[\\s'"=(])(~?/${PATH_END}+)`, 'g'), (_, pre: string, p: string) => `${pre}${p.replace(/\/+$/, '').split('/').pop() || p}`)
}
// WORKER ACTIVITY: a line a card, its mark (it turns with `motion`), its ID and its live command made short; on the
// right the tool and when the step started. A card that streams no command shows its step. A card that waits for the
// landing turn shows the ID of the card that has it, then the kind of wait (turnWait). A card in its Test step
// whose track gives test counts shows, in place of the command, a bar of its tests done of all: `▰▰▰▰▰▰▰▰▱▱ 72/89 · 3 failed`.
export const activityModel = (s: State, snap: Snap, w: number, frame: number): Line[] => [
  section('WORKER ACTIVITY', '', w),
  ...(snap.belt.length ? [] : [empty('nothing on the belt')]),
  ...snap.belt.map((b): Line => {
    const m = /^([A-Za-z][\w.-]*): ([\s\S]*)$/.exec(b.live?.action ?? '')
    const wait = turnWait(b)
    let what = wait?.text || (m ? shortCommand(m[2], b.card) : b.live?.action ? shortCommand(b.live.action, b.card) : stepOf(b))
    const tests = b.track?.at === 3 ? b.track.tests : null
    const at = b.track?.since ?? b.stepAt
    let right = [m?.[1] ?? '', at === null ? '' : clockOf(at)].filter(Boolean).join(' · ')
    // A card that waits for the landing turn drops the clock when the clock would cut the ID of the card that has the
    // turn or the first letter of the kind of wait after it (`l` of `lands`, `n` of `next`): spread() gives the text
    // w - clock - 2 columns, and the cut text ends in `…`. When the row cuts them with no clock too, a part drops its
    // parent (`#1596 of #1600` reads `#1596`). When the row still cuts them, the ID of the card that has the turn is
    // cut (`red 19e3…`), so the kind of wait shows after it.
    let own = beltId(b)
    const cuts = (room: number) => !!wait && cols(`${workMark(frame)} ${own}  ${wait.id} ${wait.kind[0]}`) + 1 > room
    if (cuts(w - cols(right) - 2)) right = ''
    if (cuts(w)) own = idOf(b)
    if (wait && cuts(w)) what = `${plain(fitWidth([{ t: wait.id }], w - cols(`${workMark(frame)} ${own}  `) - 3))}${wait.text.slice(wait.id.length)}`
    const shown: Line = tests ? [...gauge(tests.of ? (100 * tests.done) / tests.of : 0), { t: ` ${tests.done}/${tests.of}${tests.failed ? ` · ${tests.failed} failed` : ''}` }] : [{ t: what }]
    const left: Line = [{ t: `${workMark(frame)} `, c: C.work }, { t: `${own}  `, c: C.name, b: true }, ...shown]
    return spread(left, right ? { t: right, d: true } : null, w)
  }),
]

// PICK ORDER: the next five issues the engine picks, then the issues that wait on another, in the order the engine will
// pick them, each with the issues it waits for; on the right, "next 5 of 7" or the count the engine can pick now. The issues it waits for wrap at each one, under the Requires
// column: cut at the width, a row lost the last of them. One that is wider than the column is broken at its spaces.
// The parts of one parent issue are one entry, under the Parent column: the parent's number, its parts done of all,
// the parts in flight and its title; a part that waits is not a row of its own. When the ID column leaves under
// BESIDE columns beside it (a long project name in a narrow pane), what goes beside the ID goes on lines under it,
// indented by 2: the column would give a state or a title no room, and the width would cut it.
const BESIDE = 12
export const pickModel = (snap: Snap, w: number): Line[] => {
  const all = snap.queue?.length ?? 0
  const ready = snap.queue === null ? 'queue not read' : all > NEXT || snap.queueMore ? `next ${NEXT} of ${all}${snap.queueMore ? '+' : ''}` : `${all} ready`
  const pidOf = (u: Umbrella): string => (u.repo ? `${u.repo}#${u.issue}` : `#${u.issue}`)
  const pids = snap.umbrellas.map(pidOf)
  // A waiting part whose parent has no entry (the snapshot does not list it) keeps its own row, so it is not lost.
  // An issue skipped for a Depends on: line with no #N is a row too, with BAD_DEPS_ROW under Requires (requires()).
  const waits: (Waiting & { bad?: true })[] = [...snap.waits.filter(x => x.umbrella === null || !pids.includes(x.repo ? `${x.repo}#${x.umbrella}` : `#${x.umbrella}`)),
    ...(snap.badDeps ?? []).map(x => ({ ...x, waitsFor: [], states: {}, umbrella: null, bad: true as const }))]
  const ids = waits.map(x => (x.repo ? `${x.repo}#${x.issue}` : `#${x.issue}`))
  const idW = Math.max(7, ...ids.map(cols), ...pids.map(cols))
  const stack = w - idW - 2 < BESIDE
  const at = stack ? 2 : idW + 2
  const requires = (x: Waiting & { bad?: true }): string[] => {
    if (x.bad) return pieces(BAD_DEPS_ROW, w - at)
    const out: string[] = []
    // A ref wider than the column (`#967 (waiting for #3900, ... #3905)`) is broken at its spaces, not cut at the width.
    for (const r of x.waitsFor.flatMap(n => pieces(waitRef(x, n), w - at))) {
      const last = out.at(-1)
      if (last !== undefined && at + cols(`${last}  ${r}`) <= w) out[out.length - 1] = `${last}  ${r}`
      else out.push(r)
    }
    return out
  }
  return [
    section('PICK ORDER', ready, w),
    ...readyRows(snap, w),
    ...(snap.umbrellas.length ? [fitWidth([{ t: stack ? 'Parent' : `${padR('Parent', idW)}  Parts`, d: true }], w)] : []),
    // The title goes under Parts, on lines of its own, when the row's counts leave it no room on theirs.
    ...snap.umbrellas.flatMap((u): Line[] => {
      const counts = `${u.done} of ${u.all} done`, flight = u.inFlight.length ? ` · ${u.inFlight.map(n => `#${n}`).join(', ')} in flight` : ''
      const title = u.title ? shortTitle(u.title) : ''
      if (stack) return [fitWidth([{ t: pidOf(u), c: C.name, b: true }], w), ...pieces(`${counts}${flight}`, w - 2).map((p): Line => [{ t: `  ${p}` }]),
        ...(title ? pieces(title, w - 2) : []).map((p): Line => [{ t: `  ${p}`, c: C.name }])]
      const row: Seg[] = [{ t: `${padR(pidOf(u), idW)}  `, c: C.name, b: true }, { t: counts }, ...(flight ? [{ t: flight, c: C.work }] : [])]
      if (!title || cols(plain(row)) + 2 + cols(title) <= w) return [fitWidth([...row, ...(title ? [{ t: `  ${title}`, c: C.name }] : [])], w)]
      return [fitWidth(row, w), ...pieces(title, w - at).map((p): Line => fitWidth([{ t: `${' '.repeat(at)}${p}`, c: C.name }], w))]
    }),
    ...(waits.length ? [fitWidth([{ t: stack ? 'Waiting' : `${padR('Waiting', idW)}  Requires`, d: true }], w)]
      : snap.queue === null ? [empty('not read: GitHub did not list the issues')] : snap.umbrellas.length ? [] : all ? [empty('nothing waiting')] : [empty('the queue is empty')]),
    ...waits.flatMap((x, i): Line[] => {
      const reqs = requires(x)
      if (stack) return [fitWidth([{ t: ids[i] ?? '', c: C.name, b: true }], w), ...reqs.map((r): Line => [{ t: `  ${r}` }])]
      return (reqs.length ? reqs : ['']).map((r, j): Line => fitWidth([{ t: `${padR(j ? '' : ids[i], idW)}  `, c: C.name, b: true }, { t: r }], w))
    }),
  ]
}

// LANDED TODAY: the five most recent, a row each: the clock time it landed, the issue, the last verdict and its round,
// its overall time and its cost (or that it still waits), right-aligned. What it waits for (a track label such as
// "Landed, waiting for Push landed") goes on a line of its own under its row: in the shared Cost column it widened
// every row, and a narrow pane cut the other cards' costs off. So do the known dollars and the gap of a card with a step
// not priced, `$4.10+` in Cost (matrixTable()).
export const landedTable = (s: State, snap: Snap, w: number): Line[] => {
  const shown = snap.landed.slice(0, NEXT)
  const rows = shown.map(l => {
    const last = l.rounds.at(-1)
    const verdict: Seg = l.closed ? { t: 'already fixed', d: true } : last ? { t: `✓ ${last.verdict || 'no verdict'} r${last.round}`, c: last.verdict === 'GO' ? C.ok : C.you }
      : { t: count(l.reviews, 'review'), d: true }
    const waits = l.push !== 'now' && !l.issueOpen && l.waits ? l.waits : null
    const state: Seg | null = l.push === 'now' ? { t: 'pushing', c: C.you } : l.issueOpen ? { t: 'issue open', c: C.you } : waits ? { t: 'waiting', c: C.you }
      : l.push === 'failed' || l.pushed === false ? { t: 'not pushed', c: C.you } : null
    const all = overallOf(l, s.now)
    return { at: l.at ? clockOf(l.at) : 'time?', id: l.issue ? ref(l) : idOf(l), verdict, total: all === null ? '–' : fmtSec(all), state: state ?? cost(l, true),
      waits, priced: state ? null : l }
  })
  const W = (h: string, f: (r: (typeof rows)[number]) => string) => Math.max(cols(h), ...rows.map(r => cols(f(r))))
  const aW = W('Landed', r => r.at), iW = W('Issue', r => r.id), vW = W('Verdict', r => r.verdict.t), tW = W('Total', r => r.total), cW = W('Cost', r => r.state.t)
  // A pane too narrow for the whole row leaves the Cost column out: the card's cost, or what it waits for, goes on the
  // line under its row in full (dollarsLine), so it is never the part cut off.
  const costCol = aW + iW + vW + tW + cW + 8 <= w
  const under = (r: (typeof rows)[number]): Line[] => {
    const waits = r.waits ? [fitWidth([{ t: `${' '.repeat(aW + 2)}` }, { t: r.waits, c: C.you }], w)] : []
    if (costCol) return [...waits, ...(r.priced ? gapLine(r.priced, aW + 2, w) : [])]
    return [...(r.priced ? dollarsLine(r.priced, aW + 2, w) : [fitWidth([{ t: ' '.repeat(aW + 2) }, r.state], w)]), ...waits]
  }
  return [
    section(`LANDED TODAY · ${snap.landedCount}`, snap.landed.length ? `${shown.length} most recent of ${snap.landedCount}` : '', w),
    ...(rows.length ? [fitWidth([{ t: `${padR('Landed', aW)}  ${padR('Issue', iW)}  ${padR('Verdict', vW)}  ${padL('Total', tW)}${costCol ? `  ${padL('Cost', cW)}` : ''}`, d: true }], w)]
      : [empty('nothing landed today')]),
    ...rows.flatMap((r): Line[] => [fitWidth([{ t: `${padR(r.at, aW)}  `, d: true }, { t: `${padR(r.id, iW)}  `, c: C.name, b: true }, { ...r.verdict, t: `${padR(r.verdict.t, vW)}  ` },
      { t: padL(r.total, tW), d: true }, ...(costCol ? [{ t: '  ' }, { ...r.state, t: padL(r.state.t, cW) }] : [])], w),
      ...under(r)]),
  ]
}

// The four counts on one line, joined by ' · '; where that is wider than the pane the dots lose their spaces, and where
// that is still too wide the counts take two lines, so the last count (NEEDS YOU) is never the part cut off.
const countBand = (parts: Seg[], w: number): Line[] => {
  const join = (ps: Seg[], gap: string): Seg[] => ps.flatMap((p, k) => (k ? [{ t: gap, d: true }, p] : [p]))
  const fits = (l: Seg[]) => cols(plain(l)) <= w
  const wide = join(parts, ' · '), tight = join(parts, '·')
  if (fits(wide)) return [fitWidth(wide, w)]
  if (fits(tight)) return [fitWidth(tight, w)]
  return [fitWidth(join(parts.slice(0, 2), ' · '), w), fitWidth(join(parts.slice(2), ' · '), w)]
}

const paneBoard = (s: State, snap: Snap, w: number, frame: number, open: boolean): Line[] => {
  const counts = pickCounts(snap)
  const ready = snap.queue === null ? '?' : `${counts.ready}${snap.queueMore ? '+' : ''}`
  const status: Seg[] = [...(s.foreman ? [{ t: foremanText(s.foreman), c: s.foreman.ok ? C.ok : C.you, b: !s.foreman.ok }] : []), ...loopSegs(snap)]
  if (!s.foreman && status.length) status.shift()
  const bugs: Seg | null = s.pluginBugs ? { t: `! ${count(s.pluginBugs.n, 'plugin problem')}`, c: C.you, b: true } : null
  // The day's spend, the widest form that leaves the head room and the `/units` label and host whole beside it
  // (spread() drops a right part too wide, and cuts the left for the rest): with its label, then the dollars and the
  // gap in full alone, then the short form (`$4.10+`) with and without the label. None where even the short form would
  // cut the host (at 24 columns, ` /units  buildbox` and `$4.50+` need 25): the head is the label and the host alone.
  const spends: Line[] = [dayDollars(snap) ?? 'partial', dayDollars(snap, true) ?? 'partial'].flatMap(t => [[{ t: 'DAY SPEND ', d: true }, { t, c: C.cost, b: true }], [{ t, c: C.cost, b: true }]])
  const head: Line = [{ t: ' /units ', c: C.head, b: true, i: true }, { t: ' ' }, { t: s.host, b: true }]
  const spend = spends.find(r => cols(plain(r)) + 3 <= w && cols(plain(head)) + cols(plain(r)) + 2 <= w) ?? null
  // Where only the short form fits, or none, the day's dollars, and the known dollars and gap, go on a line of their own
  // under the head (gapRow).
  const full = spend !== null && (plain(spend) === (dayDollars(snap) ?? 'partial') || plain(spend) === `DAY SPEND ${dayDollars(snap) ?? 'partial'}`)
  const dayGap = full ? [] : snap.todayUsd !== null && (snap.todayLeftOut ?? 0) > 0
    ? [gapRow(snap.todayUsd, snap.todayLeftOut ?? 0, (snap.todayEstimate ?? 0) > 0, 1, w)]
    : spend === null ? [fitWidth([{ t: ' ' }, { t: dayDollars(snap) ?? 'partial', c: C.cost, b: true }], w)] : []
  const lanes = lanesModel(s)
  return [
    spread(head, spend, w),
    ...dayGap,
    rule(w),
    ...countBand([{ t: `${snap.belt.length} ON BELT`, b: true }, { t: `${ready} READY`, b: true }, { t: `${counts.waiting} WAITING`, b: true },
      { t: `${snap.needs.length} NEEDS YOU`, b: true, ...(snap.needs.length ? { c: C.you } : {}) }], w),
    rule(w),
    ...(status.length || bugs ? [spread(status, bugs, w)] : []),
    // Machine details: the waiter, the watchers, the plugin problems' file, the test map and the weekly limit.
    [{ t: '[ Machine details ]', k: 'details' }],
    ...(open ? [
      ...(s.foreman ? foremanDetail(s.foreman.detail, w) : []),
      ...(s.pluginBugs ? [[{ t: `  file://${encodeURI(s.pluginBugs.path)}`, d: true }] as Line] : []),
      ...testMapModel(s, w), fitWidth(limitLine(s), w),
    ] : []),
    ...engineModel(s, w),
    ...suitesModel(s, snap, w).map(l => fitWidth(l, w)),
    ...(snap.needs.length ? [[], ...needsModel(s, snap, w, true)] : []), [],
    ...matrixModel(s, snap, w), [],
    ...activityModel(s, snap, w, frame), [],
    ...pickModel(snap, w),
    ...heldLines(snap, w, ''),
    ...unpushedLines(snap, w, ''),
    ...pushLines(s, snap, w, ''),
    ...(snap.deploy.length ? [[], ...deployModel(s, snap, w)] : []), [],
    ...landedTable(s, snap, w),
    ...(lanes.length ? [[], ...lanes.map(l => fitWidth(l, w))] : []),
    ...(notesOf(s).length ? [[], ...notesOf(s).flatMap(n => noteLines(n, w))] : []),
  ]
}
// open: Machine details is opened.
export const paneModel = (s: State, w: number, frame: number, open = false): Line[] => (s.snap ? paneBoard(s, s.snap, w, frame, open) : [...noteLines(s.note, w), ...foremanModel(s, w), ...engineModel(s, w), ...testMapModel(s, w)])

// What the toasts compare between two polls: the cards that need you and the cards that landed, by card id.
export type Seen = { needs: Map<string, string>; landed: Map<string, string> }
export const seenOf = (snap: Snap): Seen => ({
  needs: new Map(snap.needs.map(n => [`${n.repo}/${n.card}`, `${ref(n)} ${n.yes ? 'needs your yes' : 'is blocked'}`])),
  landed: new Map(snap.landed.map(l => [`${l.repo}/${l.card}`, `${ref(l)} ${l.closed ? 'closed as already fixed' : 'landed'}`])),
})
// The first poll only sets the baseline: nothing that was already there when the session began is a toast.
export const toasts = (prev: Seen | null, cur: Seen): string[] =>
  prev ? [...[...cur.needs].filter(([k]) => !prev.needs.has(k)), ...[...cur.landed].filter(([k]) => !prev.landed.has(k))].map(([, text]) => text) : []
