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
type Ref = { repo: string; issue: number; title: string }
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
  // usd is null when a step has no price (unpriced: how many; each step of the timeline says why).
  tokens: number | null; usd: number | null; unpriced: number | null; timeline: TimelineStep[]
}
// One finished step of a card, as the dashboard's detail shows it: seconds, tokens, dollars, the model it was priced
// at, findings (a review), test counts (a test run) and the session's own account (turns, API seconds, tool calls,
// refused calls, cache hits, the models that ran). unpriced: why it has no price (null when it has one).
export type TimelineStep = {
  step: string; result: string; sec: number | null; tokens: number | null; usd: number | null; model: string | null; effort: string | null; unpriced: string | null
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
// began, reason why Push failed. No time is estimated from past cards. A track of any other shape (an older loop's) is none.
// files: the test files run of all in the Test step; tests: its tests done of all, and failed (none until it gives them).
const STATES = ['done', 'now', 'skipped', 'failed', 'todo'] as const
export const STEP_NAMES = ['Build', 'Review', 'Fix', 'Test', 'Land', 'Push'] as const
// replyFix: on Build, the fix the Done-when check on the build's reply started (track.jq): 'now' while it runs, 'done' after.
export type Step = { name: string; state: (typeof STATES)[number]; sec: number | null; n: number | null; of: number | null; followups: number | null; replyFix: 'now' | 'done' | null }
export type Track = { steps: Step[]; at: number | null; label: string; since: number | null; reason: string | null; files: { run: number; of: number | null } | null; tests: { done: number; of: number; failed: number } | null }
// reading is false while no token of the card has been read: its dollars are then "no reading yet", never $0.
// tokens: the card's fresh tokens so far, both seats together (null when the snapshot does not give them).
// live: the running step as it streams: what it is doing now, its turns so far and when it last printed.
export type Live = { action: string; turns: number | null; lastOutputAt: number | null }
export type Belt = Card & Times & { step: string; review: number | null; of: number | null; stepAt: number | null; model: string | null; tokens: number | null; usd: number | null; reading: boolean; parent: number | null; reviews: Review[]; track: Track | null; metrics: Metrics | null; live: Live | null }
export type Queued = Ref & { priority: string; followup: boolean; retried: boolean; parent: number | null }
// An open issue that depends on one still open: not picked until each of waitsFor has closed.
export type Waiting = Ref & { waitsFor: number[] }
// An open issue labelled awaiting-deploy: built and merged, waiting for your PROD deploy. since: when it got the label.
export type Deploy = Ref & { since: number | null }
// push: the state of its Push step (now while the push runs, failed when it failed or GitHub left the issue open).
// waits: what it waits for while no step of it runs (its track's label with at null: with push off, "Landed, waiting
// for Push landed"), else null.
export type Landed = Card & Times & { closed: boolean; at: number | null; usd: number | null; reviews: number; rounds: Review[]; followups: number[]; pushed: boolean | null; issueOpen: boolean; parent: number | null; push: Step['state'] | null; waits: string | null; metrics: Metrics | null }
// queue is null when no record's queue was read (gh did not list the issues); queueMore: a record gave its full ten,
// so more may wait behind them. todayUsd is the dollars of today's priced steps, and todayLeftOut how many
// steps of today it leaves out for having no price; todayUsd is null when a record was not read or its price table
// could not be run. waits: the issues that wait on another, every record's.
// loops: each record's loop as its control record makes it: running, paused, stopped, "paused by guard"
// or "control record unreadable" ("" when the snapshot does not say), reason: why it picks nothing ("" when the
// snapshot gives none), and loop: whether its process runs. judgeDeclined: when each finding the judge declined was
// declined, from every record's declined list, each line once. suites: each record's whole-suite runs (the snapshot's
// suites: a release's suite, the full test), under way (ended null) or ended.
export type Loop = { repo: string; state: string; reason: string; loop: boolean | null }
export type Suite = { repo: string; kind: string; version: string; sha: string; since: number | null; ended: number | null; state: string; done: number | null; failed: number | null }
export type Snap = { loops: Loop[]; needs: Need[]; belt: Belt[]; queue: Queued[] | null; queueMore: boolean; waits: Waiting[]; held: [string, number][]; deploy: Deploy[]; landed: Landed[]; todayUsd: number | null; todayLeftOut?: number; judgeDeclined: number[]; suites?: Suite[] }
export type Fast = { state: 'none' | 'unread' | 'norecord' } | { state: 'ok'; branch: string; ahead: number; dirty: number; subject: string }
export type Research = { state: 'none' } | { state: 'ok'; lastAt: number | null }
export type Limit = { pct: number; resetsAt: number }
// snap is null when no record's snapshot could be read; note then holds the one line every view shows instead, with
// the Foreman indicator still under it.
// The Foreman indicator (foremanOf): null where no Foreman is expected; else listening or not, why not, and the line
// of details under it.
export type Foreman = { ok: boolean; why: string; detail: string }
export type State = { now: number; snap: Snap | null; note: string; notes: string[]; host: string; limit: Limit | null; fast: Fast; research: Research; foreman?: Foreman | null }

const time = (v: unknown) => { const t = typeof v === 'string' ? Date.parse(v) : NaN; return Number.isFinite(t) ? t : null }
const num = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) ? v : null)
const one = (v: unknown) => (typeof v === 'string' ? v.replace(/\s+/g, ' ').trim() : '')

// The fetch's answer (hooks/units-fetch.sh), one tab-separated line each: `paths <Research lane worktree> <home>
// <own>`, `fast <state> [<branch> <commits ahead of main> <tracked files changed> <first subject>]`, `host <name> <how>
// <exit> [<path looked at>...]` and then, for every record in the host file's order, `<repo> <its snapshot, or null>`.
// own: the repo of the record whose main is this checkout, the session's own project; empty when no record is. `how`
// is local (a record of the host file is this checkout) or ssh, else the reason nothing was asked: nofile (with the
// paths of the host file looked at), config or nossh. foreman: its line's fields after the word, where a Foreman is
// expected (the fetch says which); null where none is.
export type Fetched = { research: string; home: string; own: string; fast: Fast; foreman: string[] | null; host: { name: string; how: string; rc: number; looked: string[] } | null; records: { repo: string; json: unknown }[] }
export const parseFetch = (stdout: string): Fetched | null => {
  const out: Fetched = { research: '', home: '', own: '', fast: { state: 'unread' }, foreman: null, host: null, records: [] }
  for (const line of stdout.split('\n')) {
    const f = line.split('\t')
    if (out.host) { if (f.length >= 2 && f[0]) out.records.push({ repo: f[0], json: f.slice(1).join('\t') }) }
    else if (f[0] === 'paths') [out.research, out.home, out.own] = [f[1] ?? '', f[2] ?? '', f[3] ?? '']
    else if (f[0] === 'fast' && f[1] === 'none') out.fast = { state: 'none' }
    else if (f[0] === 'fast' && f[1] === 'norecord') out.fast = { state: 'norecord' }
    else if (f[0] === 'fast' && f[1] === 'ok' && /^\d+$/.test(f[3] ?? '') && /^\d+$/.test(f[4] ?? '')) out.fast = { state: 'ok', branch: f[2], ahead: Number(f[3]), dirty: Number(f[4]), subject: one(f[5]) }
    else if (f[0] === 'foreman') out.foreman = f.slice(1)
    else if (f[0] === 'host') out.host = { name: f[1] ?? '', how: f[2] ?? '', rc: Number(f[3]), looked: f.slice(4).filter(Boolean) }
  }
  // An empty Research lane is one the host file does not name: the board still reads.
  return out.home ? out : null
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
    blockClass: one(v.blockClass) || null, tokens: num(v.tokens), usd: num(v.usd), unpriced: num(v.unpriced),
    timeline: (Array.isArray(v.timeline) ? v.timeline : []).filter((x: any) => x && typeof x === 'object').map((x: any): TimelineStep => {
      const t = x.tests && typeof x.tests === 'object' ? x.tests : null, st = x.stats && typeof x.stats === 'object' ? x.stats : null, c = x.counts
      const tools = st && st.tools && typeof st.tools === 'object' ? Object.fromEntries(Object.entries(st.tools).filter((e): e is [string, number] => num(e[1]) !== null)) : null
      return {
        step: one(x.step), result: one(x.result), sec: num(x.sec), tokens: num(x.tokens), usd: num(x.usd), model: one(x.model) || null, effort: one(x.effort) || null,
        unpriced: one(x.unpriced) || null,
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
      replyFix: x.replyFix === 'now' || x.replyFix === 'done' ? x.replyFix : null })),
    at: at !== null && v.steps[at] ? at : null, label: one(v.label), since: time(v.since), reason: one(v.reason) || null,
    files: v.files && typeof v.files === 'object' && num(v.files.run) !== null ? { run: v.files.run, of: num(v.files.of) } : null,
    tests: v.tests && typeof v.tests === 'object' && [v.tests.done, v.tests.of, v.tests.failed].every(x => num(x) !== null) ? { done: v.tests.done, of: v.tests.of, failed: v.tests.failed } : null,
  }
}
const timesOf = (x: any): Times => ({ start: time(x.start) ?? time(x.pickedAt), pickedAt: time(x.pickedAt), priorSec: num(x.priorSec) ?? 0, totalSec: num(x.totalSec) })
const parentOf = (x: any) => { const n = num(x.parent); return n !== null && n > 0 ? n : null }

const liveOf = (v: any): Live | null => (v && typeof v === 'object' ? { action: one(v.action), turns: num(v.turns), lastOutputAt: time(v.lastOutputAt) } : null)

type Rec = { loop: Loop; needs: Need[]; belt: Belt[]; queue: Queued[] | null; waits: Waiting[]; held: Record<string, number>; deploy: Deploy[]; landed: Landed[]; todayUsd: number | null; todayLeftOut: number; judgeDeclined: { id: string; at: number }[]; suites: Suite[] }
// One record's snapshot. null: it is not the object `conveyor.sh snapshot` prints, so nothing of it is shown.
export const parseRecord = (repo: string, json: unknown): Rec | null => {
  let j: any = json
  if (typeof json === 'string') try { j = JSON.parse(json) } catch { return null }
  const lists = [j?.needsYou?.waiting, j?.needsYou?.blocked, j?.belt, j?.landed]
  if (!lists.every(l => Array.isArray(l) && l.every((x: unknown) => x && typeof x === 'object')) || typeof j.queue !== 'object' || !j.queue || typeof j.cost !== 'object' || !j.cost) return null
  const card = (x: any): Card => ({ repo, card: one(x.card), issue: num(x.issue) ?? 0, title: one(x.title) })
  const next = Array.isArray(j.queue.next) ? j.queue.next.filter((x: unknown) => x && typeof x === 'object') : null
  return {
    loop: { repo, state: one(j.health?.state), reason: one(j.health?.reason), loop: typeof j.health?.loop === 'boolean' ? j.health.loop : null },
    needs: [
      ...j.needsYou.waiting.map((x: any): Need => ({ ...card(x), ...timesOf(x), yes: true, text: one(x.sentence), since: time(x.since), parent: parentOf(x), reviews: reviewsOf(x.reviews), track: trackOf(x.track), metrics: metricsOf(x.metrics) })),
      ...j.needsYou.blocked.map((x: any): Need => ({ ...card(x), ...timesOf(x), yes: false, text: one(x.reason), since: time(x.since), parent: parentOf(x), reviews: reviewsOf(x.reviews), track: trackOf(x.track), metrics: metricsOf(x.metrics) })),
    ],
    belt: j.belt.map((x: any): Belt => ({ ...card(x), ...timesOf(x), step: one(x.step), review: num(x.review), of: num(x.of), stepAt: time(x.stepAt), model: one(x.model) || null, tokens: num(x.tokens?.claude) === null || num(x.tokens?.codex) === null ? null : x.tokens.claude + x.tokens.codex, usd: num(x.usd), reading: x.reading === true, parent: parentOf(x), reviews: reviewsOf(x.reviews), track: trackOf(x.track), metrics: metricsOf(x.metrics), live: liveOf(x.live) })),
    queue: next && next.map((x: any): Queued => ({ repo, issue: num(x.issue) ?? 0, title: one(x.title), priority: one(x.priority), followup: x.followup === true, retried: x.retried === true, parent: parentOf(x) })),
    // A record whose loop does not give the list (from an older engine, or GitHub did not list the issues) has none.
    waits: (Array.isArray(j.queue.waiting) ? j.queue.waiting : []).filter((x: unknown) => x && typeof x === 'object')
      .map((x: any): Waiting => ({ repo, issue: num(x.issue) ?? 0, title: one(x.title), waitsFor: Array.isArray(x.waitsFor) ? x.waitsFor.filter((n: unknown): n is number => num(n) !== null) : [] }))
      .filter((x: Waiting) => x.waitsFor.length > 0),
    held: Object.fromEntries(Object.entries(j.queue.held && typeof j.queue.held === 'object' ? j.queue.held : {}).filter((e): e is [string, number] => (num(e[1]) ?? 0) > 0)),
    // A record whose loop does not give the list (or whose issues GitHub did not list) has none to show.
    deploy: (Array.isArray(j.awaitingDeploy) ? j.awaitingDeploy : []).filter((x: unknown) => x && typeof x === 'object').map((x: any): Deploy => ({ repo, issue: num(x.issue) ?? 0, title: one(x.title), since: time(x.since) })),
    landed: j.landed.map((x: any): Landed => {
      const t = trackOf(x.track)
      return {
        ...card(x), ...timesOf(x), closed: x.step === 'closed', at: time(x.time), usd: num(x.usd), reviews: num(x.reviews) ?? 0, rounds: reviewsOf(x.rounds),
        issueOpen: t?.steps[5].state === 'failed' && (t.reason ?? '').startsWith('GitHub did not close the issue'), push: t ? t.steps[5].state : null, waits: t && t.at === null && t.label ? t.label : null, parent: parentOf(x),
        followups: Array.isArray(x.followups) ? x.followups.filter((n: unknown): n is number => num(n) !== null) : [], pushed: typeof x.pushed === 'boolean' ? x.pushed : null,
        metrics: metricsOf(x.metrics),
      }
    }),
    todayUsd: num(j.cost.today),
    // A snapshot from an older engine has no count: its today is null whenever a step was unpriced.
    todayLeftOut: num(j.cost.todayLeftOut) ?? 0,
    // The declined list's lines by the judge: those the Board's panel shows (declined) and the dismissed or built ones
    // (declinedRest), for a finding dismissed since was still declined.
    judgeDeclined: [j.declined, j.declinedRest].flatMap(l => (Array.isArray(l) ? l : []))
      .filter((x: any) => x && typeof x === 'object' && x.by === 'judge' && time(x.time) !== null)
      .map((x: any) => ({ id: one(x.id), at: time(x.time) as number })),
    // A snapshot from an older engine has no suites.
    suites: (Array.isArray(j.suites) ? j.suites : []).filter((x: unknown) => x && typeof x === 'object')
      .map((x: any): Suite => ({ repo, kind: one(x.kind), version: one(x.version), sha: one(x.sha), since: time(x.since), ended: time(x.ended), state: one(x.state), done: num(x.done), failed: num(x.failed) })),
  }
}

const CANNOT = 'units: the Conveyor snapshot cannot be read'
const WHY: Record<string, string> = { nofile: 'this machine has no host file', config: 'the host file is not understood', nossh: 'the host file names no ssh target' }
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

// The dashboard collector's live feed: its stream.json, which it rewrites with each change Conveyor's host
// streams and at least every 10 s. `{host, records: [{repo, snap}], stream: {live, heardAt, error}}`; null when the
// file is not that, or holds no snapshot of every record yet.
export type Feed = { host: string; records: { repo: string; json: unknown }[]; live: boolean; heardAt: number | null; error: string }
export const parseStream = (text: string): Feed | null => {
  let j: any
  try { j = JSON.parse(text) } catch { return null }
  if (!j || typeof j !== 'object' || !Array.isArray(j.records) || !j.records.length || !j.stream || typeof j.stream !== 'object') return null
  if (!j.records.every((r: any) => r && typeof r === 'object' && typeof r.repo === 'string')) return null
  return { host: one(j.host), records: j.records.map((r: any) => ({ repo: r.repo, json: r.snap })), live: j.stream.live === true, heardAt: time(j.stream.heardAt), error: one(j.stream.error) }
}
// The board from the live feed, as from a fetch; a feed that is down says so under it, with when the host was last heard.
// own: the session's own project, as the fetch names it.
export const boardOfFeed = (f: Feed, own: string): Pick<State, 'snap' | 'note' | 'notes' | 'host'> => {
  const b = boardFrom(f.host, f.records, own)
  if (!f.live) b.notes.unshift(`units: the live stream is down${f.error ? ` (${f.error})` : ''}; the board is as ${f.host || 'the host'} was ${f.heardAt ? `at ${clockOf(f.heardAt)}` : 'last heard'}`)
  return b
}

// The cards of own, the session's own project, carry no project name (laneCard finds the Fast lane's card among them);
// every other record's carry its repo. With no own (this checkout is no record's), every card carries its name.
const boardFrom = (name: string, records: { repo: string; json: unknown }[], own: string): Pick<State, 'snap' | 'note' | 'notes' | 'host'> => {
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
      loops: read.flatMap(r => (r.rec ? [{ ...r.rec.loop, repo: r.repo }] : [])),
      // Your yes first, then the blocked cards; in each, the one waiting longest first.
      needs: recs.flatMap(r => r.needs).sort((a, b) => Number(b.yes) - Number(a.yes) || at(a.since) - at(b.since)),
      belt: recs.flatMap(r => r.belt),
      // pick's order (follow-ups, then priority, then age), with a record's own order standing for age.
      queue: queues.length ? queues.flatMap(q => q.map((x, i) => ({ x, i }))).sort((a, b) => Number(b.x.followup) - Number(a.x.followup) || a.x.priority.localeCompare(b.x.priority) || a.i - b.i).map(e => e.x) : null,
      queueMore: queues.some(q => q.length >= 10),
      waits: recs.flatMap(r => r.waits),
      held: [...held].sort((a, b) => a[0].localeCompare(b[0])),
      deploy: recs.flatMap(r => r.deploy),
      landed: recs.flatMap(r => r.landed).sort((a, b) => at(b.at) - at(a.at)),
      // A record that was not read spent an unknown amount today, so the total is partial, like an unpriced step.
      todayUsd: recs.length < read.length || recs.some(r => r.todayUsd === null) ? null : Math.round(recs.reduce((n, r) => n + (r.todayUsd as number), 0) * 100) / 100,
      todayLeftOut: recs.reduce((n, r) => n + (r.todayLeftOut ?? 0), 0),
      // Records that keep their state under one folder share a declined list, so a line is counted once by its id.
      judgeDeclined: [...new Map(recs.flatMap(r => r.judgeDeclined).map((d, i) => [d.id || `#${i}`, d.at])).values()],
      suites: recs.flatMap(r => r.suites),
    },
  }
}

// The 7-day usage limit, from the dashboard's data file (`window.<name> = {...};`), where the Board puts it: its health
// panel's data (`panels.health.data.limit`). null when it holds none.
export const parseLimit = (text: string): Limit | null => {
  try {
    const l = JSON.parse(text.slice(text.indexOf('{'), text.lastIndexOf('}') + 1)).panels?.health?.data?.limit
    const pct = num(l?.usedPct)
    const resetsAt = time(l?.resetsAt)
    return pct === null || resetsAt === null ? null : { pct, resetsAt }
  } catch { return null }
}

// ---- what the views say ----

const ref = (c: Ref) => (c.issue ? `${c.repo}#${c.issue}` : c.title || 'a branch')
export const nameOf = (c: Ref) => (c.issue ? `${c.repo}#${c.issue}${c.title ? ` ${c.title}` : ''}` : c.title || 'a branch with no issue')
// The round in progress, as the track names it ("review 2 of 3", "fix after review 1", "tests", "landing"). A review
// past the rule's count (after a landing conflict or a test fix) is named by its number alone.
export const stepOf = (b: Belt) => b.track?.label || (b.step === 'review' && b.review ? `review ${b.review}${b.of && b.review <= b.of ? ` of ${b.of}` : ''}` : b.step || 'step unknown')
const whatOf = (n: Need) => (n.yes ? `your yes: ${n.text || 'a visible change'}` : `blocked: ${n.text || 'no reason recorded'}`)
// A card with a step that could not be priced reads "cost partial", never the sum of the priced steps.
const cost = (v: number | null): Seg => (v === null ? { t: 'cost partial', c: C.cost } : { t: usd(v), c: C.cost })
const count = (n: number, word: string) => `${n} ${word}${n === 1 ? '' : 's'}`
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
      `${m.tokens === null ? 'missing' : tokens(m.tokens)} tokens`, m.usd !== null ? usd(m.usd) : m.unpriced ? `cost partial: ${count(m.unpriced, 'step')} not priced` : 'cost missing',
      ...(m.blockClass ? [`blocked: ${m.blockClass}`] : [])].join(' · '),
  ]
}
// One step of a card's timeline: `build · 10m · 1.0M tokens · $2.00 · claude-sonnet-5-5 high · turns 3 · API 3s ·
// tools Bash 2, Read 1 · refused 1 · cache hits 97% · ran claude-opus-5-5`; a review adds its findings, a test run its
// counts. A reading that was not taken reads "missing".
export const timelineText = (s: TimelineStep): string => {
  const n = (v: number | null) => (v === null ? 'missing' : String(v))
  const parts = [`${s.step}${s.result && s.result !== 'ok' ? ` ${s.result}` : ''}`, s.sec === null ? 'missing' : fmtStep(s.sec),
    `${s.tokens === null ? 'missing' : tokens(s.tokens)} tokens`, s.usd !== null ? usd(s.usd) : `not priced: ${s.unpriced || 'no reason given'}`]
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
// Parts joined with " · " and wrapped at the width, never cut: a later field must not fall off a narrow terminal. A
// wrapped line is indented two more under the first; only one part wider than the whole line is cut.
const wrapParts = (parts: string[], w: number, lead: string): Line[] => {
  const out: Line[] = []
  let cur = ''
  for (const p of parts) {
    const next = cur ? `${cur} · ${p}` : `${lead}${p}`
    if (cur && cols(next) > w) { out.push([{ t: cur, d: true }]); cur = `${lead}  ${p}` } else cur = next
  }
  if (cur) out.push([{ t: cur, d: true }])
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
const stepNote = (st: Step): string =>
  st.name !== 'Build' ? '' : st.replyFix === 'now' && st.state === 'now' ? ' · reply check fix' : st.replyFix === 'done' && st.state === 'done' ? ' · reply check fixed' : ''
const trackFit = (t: Track, w: number): { segs: Seg[]; count: 'full' | 'short' | null; times: number } => {
  const done = t.steps.flatMap((st, i) => (st.state === 'done' && st.sec !== null ? [i] : []))
  // wide: the joins ` ━━ ` (else `━`); count: 'full', 'short' or none; times: how many done steps, from the first, keep their time.
  const build = (wide: boolean, count: 'full' | 'short' | null, times: number): Seg[] => {
    const timed = new Set(done.slice(0, times))
    const segs: Seg[] = [{ t: ' ' }]
    t.steps.forEach((st, i) => {
      if (i) segs.push(st.state === 'todo' ? { t: wide ? ' ── ' : '─', c: C.dim } : { t: wide ? ' ━━ ' : '━', c: st.state === 'failed' ? C.bad : C.ok })
      const name = `${st.name}${count ? stepCount(st, count === 'short') : ''}`, note = count ? stepNote(st) : ''
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
    const n = fit.count === null ? stepCount(st, false) : '', note = fit.count === null ? stepNote(st) : ''
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
  return at === null ? (s ? `${s} in this step` : '') : `${DOING[at]}${s ? ` ${s}` : ''}`
}
// A follow-up's title is the finding it was filed for ("[P2] .claude/dashboard/panels/board.js:40 The board shows a
// stale snapshot when ..."); its short title says what it fixes: the file's name and the finding's first words ("Board:
// Board shows a stale snapshot"). A title that is not a finding is kept, and cut at the width where it is shown.
export const shortTitle = (title: string): string => {
  const m = /^(?:\[P[0-3]\]\s+)?(\S+?\.[A-Za-z0-9]+):\d+(?:-\d+)?\s+(.+)$/.exec(title)
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

// The card that lands the Fast lane's branch, found as `conveyor.sh land-branch` names it: the issue is the first
// number in the branch name, and a branch that names none lands as issue 0 under its first commit's subject.
export const laneCard = (s: State): string => {
  if (!s.snap || s.fast.state !== 'ok' || !s.fast.ahead) return ''
  const n = Number(/\d+/.exec(s.fast.branch)?.[0].slice(0, 9) ?? 0)
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
// watcher name:up|down>. Listening: this session holds the role, and its waiter runs from the install the project
// runs now with every watcher up. An install is old only when both commits are named and differ: a waiter from a
// checkout, or a project that names no commit, never moves (waiter.sh moved).
const COMMIT = /^[0-9a-f]{40}$/
export const foremanOf = (f: string[] | null, sid: string): Foreman | null => {
  if (!f) return null
  const [mark = '', pid = '', commit = '', wsid = '', live = '', cur = '', watch = ''] = f
  const watchers = watch.split(' ').filter(Boolean).map(w => w.split(':'))
  const running = live === '1' && !!sid && wsid === sid
  const detail = [
    `role: ${mark || 'no session'}${mark && mark === sid ? ' (this one)' : ''}`,
    running || live === '1' ? `waiter ${pid} on ${COMMIT.test(commit) ? commit.slice(0, 7) : 'a checkout'}${running ? '' : ` for ${wsid || 'no session'}`}` : 'no waiter',
    ...(watchers.length ? [`watchers: ${watchers.map(([n, st]) => `${n} ${st}`).join(', ')}`] : []),
  ].join(' · ')
  const down = watchers.find(([, st]) => st !== 'up')
  const why = !sid || mark !== sid ? 'not the Foreman session'
    : !running ? 'no waiter running'
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
// The indicator, and with `details` the lines under it. None where no Foreman is expected.
export const foremanModel = (s: State, w: number, details: boolean): Line[] => (s.foreman ? [
  [{ t: foremanText(s.foreman), c: s.foreman.ok ? C.ok : C.you, b: !s.foreman.ok }],
  ...(details ? foremanDetail(s.foreman.detail, w) : []),
] : [])

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

const todaySeg = (snap: Snap): Seg => (snap.todayUsd === null ? { t: 'today partial', c: C.cost }
  : { t: `today ${usd(snap.todayUsd)}${snap.todayLeftOut ? ` + ${count(snap.todayLeftOut, 'step')} not priced` : ''}`, c: C.cost, b: true })
const limitSegs = (s: State, short: boolean): Line => {
  if (!s.limit) return [{ t: short ? '7d not read' : 'usage limit not read', c: C.dim }]
  const r = resetIn(s.limit.resetsAt, s.now, short)
  return [{ t: '7d ', c: C.dim }, ...gauge(s.limit.pct), { t: ` ${Math.round(s.limit.pct)}%` }, ...(r && !short ? [{ t: ` ↻ ${r}`, c: C.dim }] : [])]
}
// A board is only drawn from a snapshot the host just gave, so the host named here answered.
const hostSegs = (s: State): Line => [{ t: '●', c: C.ok }, { t: ` ${s.host} reachable` }]

// A loop that is not picking, as its control record makes it: `shop paused`, `shop: no loop process`.
// Nothing while every loop runs.
const loopText = (snap: Snap): string => snap.loops
  .map(l => (l.loop === false ? `${l.repo}: no loop process` : l.state && l.state !== 'running' ? `${l.repo} ${l.state}${l.reason ? `: ${l.reason}` : ''}` : ''))
  .filter(Boolean).join(' · ')
const loopSegs = (snap: Snap): Seg[] => (loopText(snap) ? [{ t: ' · ' }, { t: loopText(snap), c: C.you, b: true }] : [])

// The head, two lines: CONVEYOR, today's cost and the host; then the weekly limit with its reset, and
// the counts on the belt and queued.
const queuedText = (snap: Snap) => (snap.queue === null ? 'queue not read' : `${snap.queue.length}${snap.queueMore ? '+' : ''} queued`)
export const headerModel = (s: State, snap: Snap, w: number): Line[] => {
  const r = s.limit ? resetIn(s.limit.resetsAt, s.now) : ''
  const limit: Line = s.limit ? [{ t: 'weekly limit ', d: true }, { t: `${Math.round(s.limit.pct)}%`, c: s.limit.pct >= 90 ? C.you : C.cost }, ...(r ? [{ t: ` · resets ${r}`, d: true }] : [])]
    : [{ t: 'weekly limit not read', d: true }]
  return [
    // A board is only drawn from a snapshot the host just gave: the host named here answered.
    spread([{ t: 'CONVEYOR', c: C.head, b: true }, ...loopSegs(snap)], [todaySeg(snap), { t: '  ' }, { t: '●', c: C.ok }, { t: ` ${s.host}` }], w),
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
      ...metricsLines(n.metrics, w),
    ]
  }),
] : [[{ t: 'NEEDS YOU', c: C.head, b: true }, { t: '  nothing', d: true }]]

// A card's issue and short title in bold with what it came from ("↳ #12"), the figures on the right whole: the
// title is what gives way.
const titled = (c: Ref & { parent: number | null }, lead: Seg[], right: Seg[], w: number, bold = true): Line => {
  const ref: Seg = { t: c.issue ? `${c.repo}#${c.issue} ` : '', c: C.name, b: bold }
  const parent: Seg[] = c.parent ? [{ t: ` ↳ #${c.parent}`, d: true }] : []
  const fixed = cols(plain(lead)) + cols(ref.t) + cols(plain(parent)) + (right.length ? cols(plain(right)) + 2 : 0)
  const title = fitWidth([{ t: shortTitle(c.title) || (c.issue ? '' : 'a branch with no issue'), c: C.name, b: bold }], Math.max(6, w - fixed))
  return spread([...lead, ref, ...title, ...parent], right.length ? right : null, w)
}
// A card's cost so far: its dollars, "no reading yet" before any token is read, "cost partial" with a step not priced.
const costOf = (b: Belt): Seg => (!b.reading ? { t: 'no reading yet', d: true } : cost(b.usd))
// The finished reviews on one line: one round as its verdict and counts, several each as R1, R2, ...
const verdicts = (rs: Review[]): Seg[][] => rs.map(r => {
  const f = findingsOf(r, ' ')
  return [{ t: rs.length > 1 ? `R${r.round} ` : '', d: true }, { t: r.verdict || 'no verdict', c: r.verdict === 'GO' ? C.ok : C.you }, ...(f ? [{ t: ` ${f}`, c: C.you }] : [])]
})

// The running step's live fields: `    now Bash: npm test · 3 turns · last output 4s ago`. None when it streams nothing.
// The Test step runs no model, so in place of its turns it shows how far the tests are: `142 of 205 tests ·
// 2 failed`, else `3 of 6 test files`, else nothing.
const liveLine = (b: Belt, now: number, w: number): Line[] => {
  const l = b.live
  if (!l || (!l.action && l.turns === null && l.lastOutputAt === null)) return []
  const ago = l.lastOutputAt === null ? '' : fmtStep((now - l.lastOutputAt) / 1000)
  const t = b.track, tests = t?.tests, files = t?.files
  const progress = t?.at !== 3 ? (l.turns === null ? '' : count(l.turns, 'turn'))
    : tests ? `${tests.done} of ${tests.of} tests${tests.failed ? ` · ${tests.failed} failed` : ''}`
    : files ? `${files.run}${files.of === null ? '' : ` of ${files.of}`} test files` : ''
  const parts = [l.action ? `now ${l.action}` : '', progress, ago ? `last output ${ago} ago` : ''].filter(Boolean)
  return [fitWidth([{ t: `    ${parts.join(' · ')}`, d: true }], w)]
}

// ON THE BELT: three lines a card and a blank line between cards. 1: the issue and its short title
// in bold, then when it was picked up, its overall time so far and its cost, right-aligned. 2: the six steps as one
// track. 3: the round ("round 1 of 3"), each finished round's verdict with its counts, and the measured time in the
// step it is in. No time is estimated. In /units, a latest review the judge ran on adds its counts on a dim line.
// While a step streams, its live fields follow on a dim line of their own.
export const beltModel = (s: State, snap: Snap, w: number, short: boolean, frame: number): Line[] => [
  head('ON THE BELT', snap.belt.length),
  ...(snap.belt.length ? [] : [empty('the belt is empty')]),
  ...snap.belt.flatMap((b, i): Line[] => {
    const all = overallOf(b, s.now)
    const right: Seg[] = [...(b.start !== null ? [{ t: `${whenOf(b.start, s.now)} · `, d: true }] : []), ...(all !== null ? [{ t: `${fmtSec(all)} · `, d: true }] : []), costOf(b)]
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
      ...(t ? trackLines(t, w) : [[{ t: ` ${workMark(frame)} ${stepOf(b)}`, c: C.work }] as Line]),
      ...(t || b.reviews.length ? [third] : []),
      ...(short ? [] : judgeLine(b.reviews, w, '   ')),
      // A failed Push says why: the push's error, or that GitHub kept the issue open; cut at the width.
      ...(t && t.at === 5 && t.steps[5].state === 'failed' && t.reason ? [fitWidth([{ t: `   ✗ ${t.reason}`, c: C.bad }], w)] : []),
      ...liveLine(b, s.now, w),
    ]
  }),
]

// QUEUE: the next five, numbered, the title cut to fit and the priority right-aligned; then the
// held-back line.
const NEXT = 5
export const queueModel = (snap: Snap, w: number): Line[] => {
  const next = (snap.queue ?? []).slice(0, NEXT)
  const all = snap.queue?.length ?? 0, more = all > NEXT || snap.queueMore
  return [
    [{ t: 'QUEUE', c: C.head, b: true }, ...(next.length ? [{ t: more ? `  next ${next.length} of ${all}${snap.queueMore ? '+' : ''}` : `  ${next.length}`, d: true }] : [])],
    ...(snap.queue === null ? [empty('not read: GitHub did not list the issues')] : next.length ? [] : [empty('the queue is empty')]),
    ...next.map((q, i): Line => titled(q, [{ t: ` ${i + 1} `, d: true }],
      [{ t: q.priority || 'P3', c: q.priority === 'P0' || q.priority === 'P1' ? C.you : undefined, d: !(q.priority === 'P0' || q.priority === 'P1') },
        ...(q.followup || q.retried ? [{ t: ` · ${[...(q.followup ? ['follow-up'] : []), ...(q.retried ? ['retried'] : [])].join(' · ')}`, d: true }] : [])], w, false)),
    // The issues that wait on another: not in the pick order, each with what it waits for.
    ...snap.waits.slice(0, NEXT).map((x): Line => titled({ ...x, parent: null }, [{ t: ' · ', d: true }], [{ t: `Waits for ${x.waitsFor.map(n => `#${n}`).join(', ')}`, d: true }], w, false)),
    ...(snap.waits.length > NEXT ? [empty(`and ${snap.waits.length - NEXT} more waiting`)] : []),
    ...(snap.held.length ? [fitWidth([{ t: ` held back: ${snap.held.map(([label, n]) => `${n} ${label}`).join(' · ')}`, d: true }], w)] : []),
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

// LANDED TODAY: the count and the day's cost in the heading; per card the time it landed, a check
// mark, the issue and short title, the last verdict and its round, and the cost ("pushing" in place of it while the
// push runs, what it waits for while no step runs: "Landed, waiting for Push landed" with push off); beneath, when it was picked up and its overall time to the landing, and the follow-ups it filed.
export const landedModel = (s: State, snap: Snap, w: number, short: boolean): Line[] => {
  const shown = short ? snap.landed.slice(0, NEXT) : snap.landed
  // The day's cost is today's priced steps (the head's figure), not the lifetime cost of the cards that landed today.
  const total = snap.todayUsd
  const pad = '         '
  return [
    [{ t: 'LANDED TODAY', c: C.head, b: true }, ...(snap.landed.length ? [{ t: `  ${snap.landed.length} · `, d: true }, cost(total)] : [])],
    ...(snap.landed.length ? [] : [empty('nothing landed today')]),
    ...shown.flatMap((l): Line[] => {
      const last = l.rounds.at(-1)
      const verdict: Seg[] = l.closed ? [{ t: 'already fixed', d: true }]
        : last ? [{ t: last.verdict || 'no verdict', c: last.verdict === 'GO' ? C.ok : C.you }, { t: ` r${last.round}`, d: true }]
          : [{ t: count(l.reviews, 'review'), d: true }]
      const state: Seg = l.push === 'now' ? { t: 'pushing', c: C.you } : l.issueOpen ? { t: 'issue open', c: C.you } : l.waits ? { t: l.waits, c: C.you }
        : l.push === 'failed' || l.pushed === false ? { t: 'not pushed', c: C.you } : cost(l.usd)
      const lead: Seg[] = [{ t: ` ${l.at ? clockOf(l.at) : 'time?'} `, d: true }, { t: '✓ ', c: C.ok }]
      const all = overallOf(l, s.now)
      const under = [...(l.start !== null ? [`started ${whenOf(l.start, s.now)}`] : []), ...(all !== null ? [`${fmtSec(all)} overall`] : []),
        ...(l.followups.length ? [`↳ ${count(l.followups.length, 'follow-up')}: ${l.followups.map(n => `#${n}`).join(' ')}`] : []),
        ...(!short && judgeText(l.rounds) ? [judgeText(l.rounds)] : [])]
      return [titled(l, lead, [...verdict, { t: '  ' }, state], w, false), ...(under.length ? wrapParts(under, w, pad) : [])]
    }),
    ...(snap.landed.length > shown.length ? [empty(`+${snap.landed.length - shown.length} more`)] : []),
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

// A whole-suite run (a release's suite, the full test): one line while it runs, its kind, short commit, time running,
// cases done and failures so far; once it ended, its result for SUITE_SHOWN_MS, then nothing.
export const SUITE_SHOWN_MS = 10 * 60 * 1000
export const suitesModel = (s: State, snap: Snap): Line[] => (snap.suites ?? [])
  .filter(x => x.ended === null || s.now - x.ended < SUITE_SHOWN_MS)
  .map((x): Line => {
    const what = `${x.repo ? `${x.repo} ` : ''}${x.kind === 'release' ? `release ${x.version}` : x.kind}${x.sha ? ` · ${x.sha.slice(0, 7)}` : ''}`
    const failed = x.failed ? [{ t: ` · ${count(x.failed, 'failure')}`, c: C.bad }] : []
    if (x.ended === null) {
      return [{ t: what, c: C.work, b: true }, { t: ` · running${x.since === null ? '' : ` ${fmtSec((s.now - x.since) / 1000)}`}${x.done === null ? '' : ` · ${count(x.done, 'case')} done`}`, d: true }, ...failed]
    }
    const good = x.state === 'passed' || x.state === 'released'
    return [{ t: what, c: good ? C.ok : C.bad, b: true }, { t: ` · ${x.state || 'ended'} ${fmtSec((s.now - x.ended) / 1000)} ago`, d: true }, ...failed]
  })

const noteLine = (s: State): Line => [{ t: s.note, c: C.you }]
const board = (s: State, snap: Snap, w: number, short: boolean, frame: number): Line[] => [
  ...headerModel(s, snap, w),
  ...(short ? [] : [[{ t: declinedTodayText(s, snap), d: true }] as Line]),
  ...foremanModel(s, w, true),
  ...suitesModel(s, snap).map(l => (short ? fitWidth(l, w) : l)), [],
  ...needsModel(s, snap, w, short), [],
  ...beltModel(s, snap, w, short, frame), [],
  ...queueModel(snap, w), [],
  ...(snap.deploy.length ? [...deployModel(s, snap, w), []] : []),
  ...landedModel(s, snap, w, short),
  ...(lanesModel(s).length ? [[], ...lanesModel(s).map(l => (short ? fitWidth(l, w) : l))] : []),
  ...(s.notes.length ? [[], ...s.notes.map((n): Line => [{ t: n, c: C.you }])] : []),
]

// `/units`: every section in full. A snapshot that cannot be read is one plain line, and the Foreman indicator: the
// Foreman's state is read from its folder, not from the snapshot.
export const tableText = (s: State, w: number): string => (s.snap ? board(s, s.snap, w, false, 0) : [noteLine(s), ...foremanModel(s, w, true)]).map(plain).join('\n')

// The side pane: the same sections, each item one line, the landed list cut to five.
export const paneModel = (s: State, w: number, frame: number): Line[] => (s.snap ? board(s, s.snap, w, true, frame) : [noteLine(s), ...foremanModel(s, w, true)])

// The band: the header with each section's count, the first thing that needs you, the belt, then the lanes set up on this machine.
export const bandModel = (s: State, w: number, frame: number): Line[] => {
  const snap = s.snap
  if (!snap) return [fitWidth(noteLine(s), w), ...foremanModel(s, w, false)]
  const queued = snap.queue === null ? 'queue not read' : `${snap.queue.length}${snap.queueMore ? '+' : ''} queued`
  const out: Line[] = [spread(
    [{ t: 'CONVEYOR', c: C.head, b: true }, ...loopSegs(snap), ...(snap.needs.length ? [{ t: ' · ' }, { t: `${snap.needs.length} need${snap.needs.length === 1 ? 's' : ''} you`, c: C.you, b: true }] : []),
      { t: ` · ${snap.belt.length} on the belt · ${queued} · ${snap.landed.length} landed` }],
    [...limitSegs(s, true), { t: ' · ' }, todaySeg(snap), { t: ' · ' }, ...hostSegs(s)], w)]
  out.push(...foremanModel(s, w, false))
  const n = snap.needs[0]
  if (n) out.push(spread([n.yes ? { t: '◆ ', c: C.you } : { t: '✗ ', c: C.bad }, { t: ref(n), c: C.name, b: true }, { t: ` · ${whatOf(n)}` }], snap.needs.length > 1 ? { t: `+${snap.needs.length - 1} more`, c: C.you } : null, w))
  if (snap.belt.length) {
    out.push(fitWidth(snap.belt.flatMap((b, i): Seg[] => {
      const age = since(b.stepAt, s.now)
      return [...(i ? [{ t: '   ' }] : []), { t: `${workMark(frame)} `, c: C.work }, { t: ref(b), c: C.name, b: true }, { t: ` ${stepOf(b)}${age ? ` ${age}` : ''}`, c: C.work }]
    }), w))
  }
  // A lane with no worktree is left out, and with neither there is no lane line. The Fast lane's text (a branch name,
  // a commit subject) is the part cut: the Research lane is always shown in full.
  const hasFast = s.fast.state !== 'none'
  const research: Seg[] = s.research.state === 'none' ? [] : [{ t: `${hasFast ? ' · ' : ''}Research lane: ${researchText(s)}`, d: true }]
  if (hasFast) out.push(fitWidth([...fitWidth([{ t: `Fast lane: ${fastText(s)}`, d: true }], Math.max(12, w - cols(plain(research)))), ...research], w))
  else if (research.length) out.push(fitWidth(research, w))
  return out
}

export const summaryLine = (s: State): string =>
  s.snap ? `conveyor: ${s.foreman ? `${foremanText(s.foreman)} · ` : ''}${loopText(s.snap) ? `${loopText(s.snap)} · ` : ''}${s.snap.needs.length ? `${s.snap.needs.length} need${s.snap.needs.length === 1 ? 's' : ''} you · ` : ''}${s.snap.belt.length} on the belt · ${s.snap.landed.length} landed · ${plain([todaySeg(s.snap)])}` : `${s.foreman ? `${foremanText(s.foreman)} · ` : ''}${s.note}`

// What the toasts compare between two polls: the cards that need you and the cards that landed, by card id.
export type Seen = { needs: Map<string, string>; landed: Map<string, string> }
export const seenOf = (snap: Snap): Seen => ({
  needs: new Map(snap.needs.map(n => [`${n.repo}/${n.card}`, `${ref(n)} ${n.yes ? 'needs your yes' : 'is blocked'}`])),
  landed: new Map(snap.landed.map(l => [`${l.repo}/${l.card}`, `${ref(l)} ${l.closed ? 'closed as already fixed' : 'landed'}`])),
})
// The first poll only sets the baseline: nothing that was already there when the session began is a toast.
export const toasts = (prev: Seen | null, cur: Seen): string[] =>
  prev ? [...[...cur.needs].filter(([k]) => !prev.needs.has(k)), ...[...cur.landed].filter(([k]) => !prev.landed.has(k))].map(([, text]) => text) : []
