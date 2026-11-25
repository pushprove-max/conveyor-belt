// SPDX-License-Identifier: Apache-2.0
import { expect, test } from 'claude-code/testing'
import { TWO_PROJECTS } from './fixtures/units-two-projects'
import { activityModel, ageNotes, boardOf, boardOfFeed, fastText, paneModel, parseFetch, parseLimit, researchText, seatFromGit, seenOf, shortTitle, STEP_NAMES, tableText, toasts } from './sources'
import type { Fast, Research, State } from './sources'
import { clockOf, cols, plain } from './elements'

// Each section of /units with data and with none, and every way the snapshot can fail to be read. The texts fed here
// are what the mod's fetch prints: `conveyor.sh snapshot` per record, under the paths, fast and host lines.

const NOW = Date.UTC(2026, 10, 10, 4, 40, 0)
const ago = (min: number) => new Date(NOW - min * 60_000).toISOString()
const snapshot = (over: object = {}) => JSON.stringify({
  time: ago(0), day: '2026-11-09', needsYou: { waiting: [], blocked: [] }, belt: [], queue: { next: [] }, landed: [], health: {},
  cost: { today: 0, week: 0, perLanded: null, landedAfter: {}, unpricedSteps: 0 }, ...over,
})
const fetched = (records: [string, string][], host = 'host\tbuildbox\tssh\t0', fast = 'fast\tnone') =>
  `paths\t/r/ws\t/r/home\tbookstore\n${fast}\n${host}\n${records.map(r => r.join('\t')).join('\n')}\n`
const state = (text: string, over: Partial<State> = {}): State =>
  ({ now: NOW, ...boardOf(parseFetch(text)), limit: null, fast: (parseFetch(text)?.fast ?? { state: 'unread' }) as Fast, research: { state: 'none' }, ...over })
const board = (over: object = {}, more: Partial<State> = {}) => state(fetched([['bookstore', snapshot(over)]]), more)
// The snapshot's queue.skipped: one entry a skipped issue, by the rule that skips it (what the engine emits; it has no queue.held).
const skipped = (counts: Record<string, number>) => Object.entries(counts).flatMap(([rule, n]) => Array.from({ length: n }, (_, i) => ({ issue: 5000 + i, title: `Skipped ${i}`, rule })))
const section = (text: string, name: string) => text.split('\n\n').find(p => p.startsWith(name)) ?? ''

const WAITING = { card: 'c1-3861', issue: 3861, title: 'Fast lane lands through Conveyor', sentence: 'Staff land Fast lane changes as a card.', since: ago(12) }
const BLOCKED = { card: 'c2-3850', issue: 3850, title: 'Logo upload', reason: 'review 3 was NO-GO:\n[P1] the sanitizer drops every   path', since: ago(90) }
const BELT = [
  { card: 'c3-3863', issue: 3863, title: 'Rebuild the workflow dashboard for Conveyor', step: 'build', review: null, of: 3, stepAt: ago(10), model: 'claude-fable-5-2', tokens: {}, usd: null, reading: false },
  { card: 'c4-3864', issue: 3864, title: 'Rebuild /units for Conveyor', step: 'review', review: 2, of: 3, stepAt: ago(3), model: 'gpt-6', tokens: {}, usd: 1.25, reading: true },
]
const LANDED = [
  { card: 'c5-3862', issue: 3862, title: 'One snapshot record', step: 'landed', time: ago(13), usd: 4.211, reviews: 2, followups: [3870, 3871], sha: 'f1d6', pushed: true },
  { card: 'c6-3860', issue: 3860, title: 'Health record', step: 'landed', time: ago(41), usd: null, reviews: 1, followups: [], sha: 'b8f5', pushed: false },
  { card: 'c7-3858', issue: 3858, title: 'Already there', step: 'closed', time: ago(70), usd: 0.4, reviews: 0, followups: [], sha: '', pushed: null },
]
const queued = (n: number) => Array.from({ length: n }, (_, i) => ({ issue: 3900 + i, title: `Issue ${i}`, priority: 'P2', followup: false, retried: false }))

// the head is two lines, CONVEYOR with today's cost and the host, then the weekly limit with its reset
// and the counts on the belt and queued.
test('the head gives dollars today and the host, then the weekly limit with its reset and the counts on the belt and queued', () => {
  const text = tableText(board({ cost: { today: 12.345 }, belt: BELT, queue: { next: queued(9) } }, { limit: { pct: 94, resetsAt: NOW + (24 + 18) * 3600_000 } }), 62)
  const [first, second] = text.split('\n')
  expect(first).toMatch(/^CONVEYOR +today \$12\.35  ● buildbox$/)
  expect(second).toMatch(/^weekly limit 94% · resets 1d 18h +2 on belt · 9 queued$/)
  for (const l of [first, second]) expect(cols(l)).toBe(62)
})

test('a head with no limit in the data file says so, and a day with an unpriced step reads partial, never a part sum', () => {
  const text = tableText(board({ cost: { today: null } }), 80)
  expect(text.split('\n')[0]).toMatch(/^CONVEYOR +today partial  ● buildbox$/)
  expect(text.split('\n')[1]).toMatch(/^weekly limit not read +0 on belt · 0 queued$/)
})

// Bug: /units named a card that waits on another card as not counted against the cap, but the cap counts every card
// on the belt (issue 1538): the owner saw fewer cards against the cap than the belt held.
test('/units gives every card on the belt against the cap, a waiting one too', () => {
  const s = board({ belt: BELT, health: { loop: true, state: 'running', building: 2, waitingCount: 1, builderCap: 1 } })
  const text = tableText(s, 120)
  // Issue 287. Bug it catches: the cap was a hard-to-read line of its own under the head ("building 1 of the cap 1");
  // it is in the head now, with no card named as not counted.
  expect(section(text, 'ON THE BELT').split('\n')[0]).toBe('ON THE BELT (2 of 1)')
  expect(section(text, 'ON THE BELT')).not.toMatch(/building|of the cap/)
  // Bug: the head counted every card on the belt, so a card that lands (the snapshot's offCap) or has landed (Push)
  // took a slot in the figure, as the loop does not count it (issue 1538). Each is named as not counted, beside the one
  // card that counts.
  const lands = (step: string, offCap = false) => board({ belt: [BELT[0], { ...BELT[1], step, offCap }], health: { loop: true, state: 'running', building: 1, builderCap: 7 } })
  for (const [step, offCap] of [['landing', true], ['push', false], ['issue', false]] as const)
    expect(section(tableText(lands(step, offCap), 120), 'ON THE BELT').split('\n')[0]).toBe('ON THE BELT (1 of 7, 1 landing not counted)')
  // Bug: a card in the step landing that the loop counts (rebuilt after a landing conflict, or waiting for a release
  // run: offCap false) was left out of the figure, so the owner saw a free slot where the loop had none.
  expect(section(tableText(lands('landing'), 120), 'ON THE BELT').split('\n')[0]).toBe('ON THE BELT (2 of 7)')
  // Bug: the cap text in the head made its right side too wide for /units' 56 columns, so the belt and queue counts
  // were dropped.
  expect(tableText(s, 56).split('\n')[1]).toMatch(/ 2 on belt · 0 queued$/)
})

// Bug: while the snapshot is behind, `conveyor.sh snapshot` adds a card started since to the kept belt, which can still
// hold the old row of a card that has since left review to land: /units counted both rows against the cap (2 of 7),
// where the Board and the Foreman give loop.json's count now (recordsNow.building, 1).
test('/units counts the loop\'s cards now against the cap while the snapshot is behind, not the kept belt\'s rows', () => {
  const started = { card: 'c8-3865', issue: 3865, title: 'Started since', step: 'build', stepAt: ago(1), landed: false, fromRecords: true }
  const s = board({ belt: [BELT[1], started], recordsNewer: true, recordsNow: { building: 1, blocked: [], waiting: [] },
    health: { loop: true, state: 'running', building: 1, builderCap: 7 } })
  expect(section(tableText(s, 120), 'ON THE BELT').split('\n')[0]).toBe('ON THE BELT (1 of 7)')
})

// Bug: while the snapshot is behind, /units took whether a loop runs from the old snapshot's health.building. A loop
// started since (health.building null, recordsNow.building 1) drew the rows' count with no cap. With only loop.json
// newer than the snapshot (recordsNewer false, recordsNow given), /units counted the rows where the Foreman gives
// loop.json's count (watch-conveyor.sh).
const behind = (building: number | null, now: number | null, newer = true) => board({ belt: [BELT[0]], recordsNewer: newer,
  recordsNow: { building: now, blocked: [], waiting: [] }, health: { state: 'running', building, builderCap: 7 } })
const beltHead = (s: State) => section(tableText(s, 120), 'ON THE BELT').split('\n')[0]
test('/units counts the cards of a loop started since the snapshot against the cap', () => {
  expect(beltHead(behind(null, 1))).toBe('ON THE BELT (1 of 7)')
})
// Issue 1583. Bug it catches: a snapshot made where the loop does not run (the Board on another machine, no loop.json)
// carries recordsNow.building null; /units drew that unknown count as 0 (`0/8 slots` with 7 cards on the belt). It
// takes health.building, then the belt's count.
const matrixHead = (s: State) => section(paneModel(s, 100, 0).map(plain).join('\n'), 'BUILD MATRIX').split('\n')[0]
// One of the 7 belt cards is in Push, which takes no slot: the belt's own count is 6, so 7 can come only from
// health.building (a view that skipped that fallback and counted the rows would draw 6).
test('/units takes health.building when the snapshot is behind and recordsNow.building is null', () => {
  const belt = Array.from({ length: 7 }, (_, i) => ({ ...BELT[0], card: `c9-${4000 + i}`, issue: 4000 + i, step: i ? 'build' : 'push' }))
  const s = board({ belt, recordsNewer: true, recordsNow: { building: null }, health: { state: 'running', building: 7, builderCap: 8 } })
  const feed = 'feed: recordsNow {building: null}, health.building 7, builderCap 8, 7 belt cards (1 in Push)'
  expect(matrixHead(s), feed).toMatch(/ 7\/8 slots$/)
  expect(beltHead(s), feed).toBe('ON THE BELT (7 of 8, 1 landing not counted)')
})
// Bug it also catches: with both counts null, BUILD MATRIX counted a card in Push as a slot where ON THE BELT does not.
test('/units takes the belt\'s count when recordsNow.building and health.building are both null', () => {
  const s = board({ belt: [BELT[0], { ...BELT[1], step: 'push' }], recordsNewer: true,
    recordsNow: { building: null, blocked: [], waiting: [] }, health: { state: 'running', building: null, builderCap: 7 } })
  const feed = 'feed: recordsNow.building null, health.building null, builderCap 7, 2 belt cards (1 in Push)'
  expect(matrixHead(s), feed).toMatch(/ 1\/7 slots$/)
  expect(beltHead(s), feed).toBe('ON THE BELT (1 of 7, 1 landing not counted)')
})
test('/units takes loop.json\'s card count when only loop.json is newer than the snapshot', () => {
  expect(beltHead(behind(1, 0, false)), 'only loop.json newer: recordsNewer false, recordsNow.building 0').toBe('ON THE BELT (0 of 7)')
})

// Issue 195. Bug it catches: a card the machine held back did not say why. Issue 346: the machine room is removed, so
// a snapshot that still names the machine's pressure draws no machine line in ON THE BELT.
test('/units says why the machine holds a queued card back, and draws no machine room line', () => {
  const room = 'waiting for a machine slot: 2 of the machine cap 2 in use'
  const s = board({ queue: { next: [{ ...queued(1)[0], room }] },
    health: { pressure: { state: 'Strained', cpu: 12.5, memory: 25.5, wakeMs: 0.2, freeMB: null, why: 'memory pressure 25.5% is at or above 20%', gates: true } } })
  const text = tableText(s, 200)
  expect(section(text, 'ON THE BELT').split('\n')[1].trimEnd()).toBe('  the belt is empty')
  expect(section(text, 'ON THE BELT')).not.toMatch(/machine|pressure|new cards wait/)
  expect(section(text, 'QUEUE').split('\n')[2].trimEnd()).toBe(`    ${room}`)
  // Issue 233. Bug it catches: /units' pane is 72 columns at most and 56 by default, and the line was cut at the
  // width, so why the card waits fell off. It wraps now, every word kept.
  for (const w of [72, 56]) {
    const queue = section(tableText(s, w), 'QUEUE').split('\n').slice(2)
    for (const l of queue) expect(cols(l.trimEnd())).toBeLessThanOrEqual(w)
    expect(queue.join(' ').replace(/\s+/g, ' ')).toContain(room)
  }
  // A queued card the machine does not hold has no line under it.
  const none = tableText(board({ queue: { next: queued(1) } }), 200)
  expect(section(none, 'QUEUE').split('\n').length).toBe(2)
})

// Issue 287. Bug it catches: with two projects the cap was not shown, so the view differed by machine. Each project's
// count is after its name.
test('with more than one project, the head gives each project\'s count after its name', () => {
  const two = state(fetched([
    ['bookstore', snapshot({ belt: [{ ...BELT[0], step: 'push' }], health: { loop: true, state: 'running', building: 0, builderCap: 3, machine: { cap: 4 } } })],
    ['gadgetlab', snapshot({ belt: [{ ...BELT[1], card: 'c5-7', issue: 7 }], health: { loop: true, state: 'running', machine: { cap: 4 } } })],
  ]))
  const lines = section(tableText(two, 72), 'ON THE BELT').split('\n')
  expect(lines[0].trimEnd()).toBe('ON THE BELT (bookstore 0 of 3, 1 landing not counted · gadgetlab 1)')
  // At /units' 56 columns the head wraps at a project, never cutting one off.
  const narrow = section(tableText(two, 56), 'ON THE BELT').split('\n')
  expect(narrow.slice(0, 2).map(l => l.trimEnd())).toEqual(['ON THE BELT (bookstore 0 of 3, 1 landing not counted','  gadgetlab 1)'])
})

// Bug: a release's whole suite (about 15 minutes) runs and /units shows nothing of it, so the owner asks the Foreman
// whether it runs, how far it is and whether anything failed; or a run long over stays on the board.
const SUITE = { kind: 'release', version: '1.2.0', step: 'release-prep', sha: 'a1b2c3d4e5f6a7b8', since: ago(12), ended: null, state: 'running', done: 140, failed: 2, cases: ['x: a', 'y: b'], moved: false, reasons: [] }
test('a release suite under way is a line under the head with its version, short commit and time running, and a line of cases done and failures so far', () => {
  const lines = tableText(board({ suites: [SUITE] }), 80).split('\n')
  expect(lines.slice(3, 5)).toEqual(['release 1.2.0 · a1b2c3d · running 12m', '  140 cases done · 2 failures'])
  expect(tableText(board({ suites: [] }), 80)).not.toMatch(/release|running|cases done/)
})
// Bug (#1240): while a release's failed cases ran again, /units kept the first pass's "140 cases done · 2 failures".
// Bug (#1249): the pane cut that one line at 80 columns, so its failure count and last-move time never showed.
test('a release whose failed cases run again shows that pass, its files done and failed and its last move, not the first pass\'s counts, whole at 80 columns', () => {
  const rerun = { round: 2, of: 6, case: 'x: a', since: ago(4), at: ago(3), done: 5, failed: 1, files: { done: 1, of: 2, failed: ['x'] } }
  const lines = tableText(board({ suites: [{ ...SUITE, rerun }] }), 80).split('\n')
  expect(lines.slice(3, 5).map(l => l.trimEnd())).toEqual(['release 1.2.0 · a1b2c3d · failed cases again: pass 2 of 6', '  1 file done · 1 failed · moved 3m ago'])
  const pane = paneModel(board({ suites: [{ ...SUITE, rerun }] }), 80, 0).map(plain).join('\n')
  expect(pane).toContain('  1 file done · 1 failed · moved 3m ago')
  expect(pane).not.toContain('…')
})
test('an ended run shows its result for a short time, then goes away', () => {
  const ended = { ...SUITE, kind: 'full test', version: '', ended: ago(3), state: 'failed' }
  expect(tableText(board({ suites: [ended] }), 80).split('\n')[3]).toBe('full test · a1b2c3d · failed 3m ago · 2 failures')
  expect(tableText(board({ suites: [{ ...ended, ended: ago(11) }] }), 80)).not.toMatch(/full test/)
})

// Bug (#1271): a release's suite on a Devbox showed as a run on this machine, so the owner could not tell that the belt
// was not slowed, or that a box was still leased. The line names the machine after the commit, with the box's step.
const agoSec = (sec: number) => new Date(NOW - sec * 1000).toISOString()
const BOX = { kind: 'devbox', name: 'Devbox XL', lease: 'ns-1', step: 'start', secs: {}, reason: null }
const BOXED = { ...SUITE, version: '1.10.0', sha: '3342e0eaaaaaaaaa', since: agoSec(40), done: null, failed: 0, machine: BOX }
const suiteLine = (suite: object) => tableText(board({ suites: [{ ...BOXED, ...suite }] }), 100).split('\n')[3]?.trimEnd()
const suiteCounts = (suite: object) => tableText(board({ suites: [{ ...BOXED, ...suite }] }), 100).split('\n')[4]?.trimEnd()
// The record holds done 0 and failed 0 before the tests run, and the final counts when the results come back: the
// steps around the tests say no counts (a line "0 cases done · 0 failures" for a box still starting was the bug).
test('a release suite on a Devbox names the machine after the commit, its step before the tests, then its cases and failures, then, once ended, that the box was given back', () => {
  expect(suiteLine({ done: 0 })).toBe('release 1.10.0 · 3342e0e · on Devbox XL · starting the box 0m 40s')
  expect(suiteLine({ done: 0, machine: { ...BOX, step: 'setup' } })).toBe('release 1.10.0 · 3342e0e · on Devbox XL · setting up 0m 40s')
  expect(suiteLine({ done: 0, machine: { ...BOX, step: 'checkout' } })).toBe('release 1.10.0 · 3342e0e · on Devbox XL · checking out 0m 40s')
  expect(suiteLine({ done: 1204, failed: 3, machine: { ...BOX, step: 'results' } })).toBe('release 1.10.0 · 3342e0e · on Devbox XL · bringing back results 0m 40s')
  expect(suiteLine({ machine: { ...BOX, step: 'run' }, since: agoSec(320), done: 1204 })).toBe('release 1.10.0 · 3342e0e · on Devbox XL · running 5m 20s')
  expect(suiteCounts({ machine: { ...BOX, step: 'run' }, since: agoSec(320), done: 1204 })).toBe('  1204 cases done · 0 failures')
  expect(suiteLine({ machine: { ...BOX, step: 'done' }, since: agoSec(530 + 120), ended: agoSec(120), state: 'passed' }))
    .toBe('release 1.10.0 · 3342e0e · on Devbox XL · passed 8m 50s · 2 min ago · box given back')
  // A box that was not given back (no lease kept) does not claim it was.
  expect(suiteLine({ machine: { ...BOX, lease: null, step: 'run' }, since: agoSec(530 + 120), ended: agoSec(120), state: 'not started' })).not.toMatch(/given back/)
})
// Bug (#1438, O376): at 80 columns the pane cut the case and failure counts off a running suite on a machine named
// 'Namespace Devbox 4x8', as the one line was about 98 columns wide.
test('a running suite on a long-named machine keeps its case and failure counts at 80 columns', () => {
  const box = { ...BOX, name: 'Namespace Devbox 4x8', step: 'run' }
  const out = paneModel(board({ suites: [{ ...BOXED, machine: box, since: agoSec(320), done: 1204 }] }), 80, 0).map(plain).join('\n')
  expect(out).toContain('1204 cases done · 0 failures')
})
test('a release suite on this machine, or from a snapshot with no machine, has no machine part', () => {
  const local = { kind: 'local', name: 'this machine', lease: null, step: 'run', secs: {}, reason: null }
  expect(suiteLine({ machine: local, since: ago(12), done: 140, failed: 2 })).toBe('release 1.10.0 · 3342e0e · running 12m')
  expect(suiteCounts({ machine: local, since: ago(12), done: 140, failed: 2 })).toBe('  140 cases done · 2 failures')
  expect(suiteLine({ machine: undefined, since: ago(12), done: 140, failed: 2 })).not.toMatch(/ on /)
})

// a snapshot that prices what it can gives today's priced dollars and the steps it leaves out, never hiding both.
test('the head gives today\'s priced dollars and how many steps they leave out', () => {
  const text = tableText(board({ cost: { today: 4.5, todayLeftOut: 2 } }), 80)
  expect(text.split('\n')[0]).toMatch(/^CONVEYOR +today \$4\.50 \+ 2 steps not priced  ● buildbox$/)
  // Bug (#1585): a step priced as an estimate (its usage read only in part) read as exact; its day is marked ~.
  expect(tableText(board({ cost: { today: 4.12, todayLeftOut: 0, todayEstimate: 1 } }), 80).split('\n')[0]).toMatch(/^CONVEYOR +today ~\$4\.12  ● buildbox$/)
})

test('NEEDS YOU lists a card waiting for a yes before a blocked one, each with its whole reason on its own line', () => {
  const part = section(tableText(board({ needsYou: { waiting: [WAITING], blocked: [BLOCKED] } }), 80), 'NEEDS YOU')
  expect(part.split('\n')).toEqual([
    'NEEDS YOU (2)',
    expect.stringMatching(/^◆ #3861 Fast lane lands through Conveyor +12m$/),
    '    your yes: Staff land Fast lane changes as a card.',
    expect.stringMatching(/^✗ #3850 Logo upload +1h 30m$/),
    '    blocked: review 3 was NO-GO: [P1] the sanitizer drops every path',
  ])
})

// Bug: a build, fix or landing that failed took the card off the belt, and no view showed the step that
// failed or how long it ran.
test('a blocked card shows the step it failed at with its seconds, its six steps and its reviews', () => {
  const failed = { ...track('++!...', '', { at: null }), since: null }
  failed.steps[2].sec = 754
  const blocked = { ...BLOCKED, reason: 'fix: session failed (exit 124)', track: failed, reviews: [{ round: 1, verdict: 'NO-GO', counts: counts(0, 1, 2, 0), sec: 200, fixed: true }] }
  const waiting = { ...WAITING, track: track('++....', '', { at: null }), reviews: [{ round: 1, verdict: 'GO', counts: counts(0, 0, 0, 0), sec: 60, fixed: false }] }
  const s = board({ needsYou: { waiting: [waiting], blocked: [blocked] } })
  const lines = section(tableText(s, 100), 'NEEDS YOU').split('\n')
  for (const l of lines) expect(cols(l)).toBeLessThanOrEqual(100)
  const at = lines.findIndex(l => l.startsWith('✗ #3850'))
  expect(lines.slice(at + 1)).toEqual(['    blocked: fix: session failed (exit 124)', '    failed at Fix (step 3 of 6) after 12m',
    '    ✓ Build 30s ━━ ✓ Review 31s ━━ ✗ Fix ── Test ── Land ── Push', '    R1 NO-GO  1 P1, 2 P2'])
  // A card that waits for a yes failed no step: its track and its review, and no "failed at" line.
  const yes = lines.slice(1, at).join('\n')
  expect(yes).not.toContain('failed at')
  expect(yes).toMatch(/\n {4}✓ Build 30s ━━ ✓ Review 31s ── Fix ── Test ── Land ── Push\n {4}R1 GO$/)
  expect(paneModel(s, 100, 0).map(plain).join('\n')).toMatch(/\n✗ #3850 Logo upload · failed at Fix \(step 3 of 6\) after 12m · blocked: fix: session fail[^\n]*… +1h 30m\n/)
  // A blocked card whose record gives no track (an older loop) shows its reason alone.
  expect(section(tableText(board({ needsYou: { waiting: [], blocked: [BLOCKED] } }), 100), 'NEEDS YOU').split('\n')).toHaveLength(3)
})

test('NEEDS YOU with nothing waiting is one line saying so', () => {
  expect(section(tableText(board(), 80), 'NEEDS YOU')).toBe('NEEDS YOU  nothing')
})

// The snapshot's track: the six steps, `marks` one character a step (+ done, > now, - skipped, ! failed,
// . todo), a done step 30 s plus its place; Review one round (or none) of 3, and Fix none: a test that needs more sets them.
const NAMES = ['Build', 'Review', 'Fix', 'Test', 'Land', 'Push']
const track = (marks: string, label: string, over: object = {}) => ({
  steps: NAMES.map((name, i) => ({ name, state: { '+': 'done', '>': 'now', '-': 'skipped', '!': 'failed', '.': 'todo' }[marks[i]], sec: marks[i] === '+' ? 30 + i : null,
    ...(i === 1 ? { n: '+>!'.includes(marks[1]) ? 1 : 0, of: 3 } : i === 2 ? { n: 0 } : {}) })),
  at: marks.search(/[>!]/) < 0 ? null : marks.search(/[>!]/), label, since: ago(3), reason: null, files: null, detail: [], ...over,
})
const counts = (P0: number, P1: number, P2: number, P3: number) => ({ P0, P1, P2, P3 })
const TIMES = { start: ago(40), pickedAt: ago(40), priorSec: 0, totalSec: null }
const beltCard = (over: object, w = 62) => section(tableText(board({ belt: [{ ...BELT[1], ...TIMES, ...over }] }), w), 'ON THE BELT').split('\n').slice(1)
// The belt's lines: its cards are parted by a blank line, so it is cut from the text up to the QUEUE heading.
const beltOf = (text: string) => { const l = text.split('\n'); return l.slice(l.findIndex(x => x.startsWith('ON THE BELT')), l.findIndex(x => x.startsWith('QUEUE')) - 1) }

// three lines a card, and a blank line between cards.
test('ON THE BELT gives each card three lines: its title, start, overall time and cost; its six steps; its reviews and time in the step', () => {
  const part = beltOf(tableText(board({ belt: [
    { ...BELT[0], ...TIMES, title: 'Measure everything', usd: 7.06, reading: true, track: track('++>...', 'fix after review 1', { since: ago(2) }), reviews: [{ round: 1, verdict: 'NO-GO', counts: counts(0, 4, 6, 0), sec: 60, fixed: true }] },
    { ...BELT[1], ...TIMES, parent: 3874, title: '[P2] .claude/dashboard/panels/board.js:40 The board shows a stale snapshot after an answer', usd: 2.34,
      track: (() => { const t = track('+>....', 'review 3 of 3'); t.steps[1].n = 3; return t })(), reviews: [1, 2].map(round => ({ round, verdict: 'NO-GO', counts: counts(0, 0, 1, 0), sec: 60, fixed: true })) },
    { ...BELT[1], ...TIMES, card: 'c9', issue: 3899, title: 'Board: rule-skipped cards', step: 'push', landed: true, usd: 1.1, track: track('++-++>', 'pushing', { since: new Date(NOW - 51_000).toISOString() }), reviews: [{ round: 1, verdict: 'GO', counts: counts(0, 0, 0, 0), sec: 60, fixed: false }] },
  ] }), 62))
  for (const l of part) expect(cols(l)).toBeLessThanOrEqual(62)
  expect(part).toEqual([
    'ON THE BELT (3)',
    expect.stringMatching(new RegExp(`^ #3863 Measure everything +${clockOf(NOW - 40 * 60_000)} · 40m · \\$7\\.06$`)),
    // What was measured fits at 62 columns on these two: the times of the done steps, and the round of a review.
    ' ✓ Build 30s ━━ ✓ Review 31s ━━ ▶ Fix ── Test ── Land ── Push',
    expect.stringMatching(/^ round 1 of 3 · NO-GO 4 P1 6 P2 +fixing 2m$/),
    '',
    // A follow-up: its short title (never the raw "[P2] path:line" one) gives way to the figures, then where it came from.
    expect.stringMatching(/^ #3864 Board: Board shows a s… ↳ #3874 +\S+ [AP]M · 40m · \$2\.34$/),
    ' ✓ Build 30s ━━ ▶ Review 3 of 3 ── Fix ── Test ── Land ── Push',
    expect.stringMatching(/^ round 3 of 3 · R1 NO-GO 1 P2 · R2 NO-GO 1 P2 +reviewing 3m$/),
    '',
    expect.stringMatching(/^ #3899 Board: rule-skipped cards +\S+ [AP]M · 40m · \$1\.10$/),
    ' ✓ Build 30s━✓ Review 31s━– Fix━✓ Test 33s━✓ Land 34s━▶ Push',
    expect.stringMatching(/^ GO +pushing 51s$/),
  ])
})

// Issue 1078: for the whole pre-push hook (a suite of minutes) /units said only "pushing", so a slow push could not be
// told from a stuck one. Under the belt: the hook running with its commit, process, elapsed time and newest output line;
// a push whose process is gone as stale, with its log; a failed push with its failed test and log; and a Push now that
// started no push or left main ahead of the remote.
test('the push shows the running hook with its elapsed time and newest line, or a stale push, a failure or main still ahead', () => {
  const sha = 'a1b2c3d4e5f6a7b8', log = '/r/home/state/pushlogs/20261110T043700Z-4242.log'
  const pushing = (stale: boolean) => ({ health: { pushing: { pid: 4242, since: ago(3), sha, log, sec: 170, line: '12/40 passed', stale } } })
  expect(beltOf(tableText(board(pushing(false)), 120)).slice(-2)).toEqual([
    ` push on a1b2c3d4e5f6: pre-push hook running since ${clockOf(NOW - 3 * 60_000)} · pid 4242 · 3m`, '   12/40 passed'])
  expect(tableText(board(pushing(true)), 200)).toContain(` ✗ push on a1b2c3d4e5f6 is stale: its process (pid 4242) is gone and the push did not end · Log: ${log}`)
  const last = (l: object) => tableText(board({ health: { unpushed: [{ card: 'c0-7', issue: 7 }], pushLast: { time: ago(2), by: 'now', started: true, sha, ok: false, ahead: 1, check: null, log: null, why: null, ...l } } }), 200)
  expect(last({ check: 'fast-checks', log })).toContain(` ✗ Push now of a1b2c3d4e5f6 failed: fast-checks failed · Log: ${log} · main is still 1 commit ahead of the remote`)
  expect(last({ started: false, sha: null, why: 'the push lock could not be taken', ahead: 2 })).toContain(' ✗ Push now started no push: the push lock could not be taken · main is still 2 commits ahead of the remote')
  expect(last({ ok: true, ahead: 0 })).toContain(' ✓ Push now of a1b2c3d4e5f6 passed 2m ago')
})

// Issue 1078, review: in the 60-column pane the running line was cut, losing its process and elapsed time, and a log
// path wider than the line lost its end; and the line said the pre-push hook ran while the tests before the push ran
// and after the remote held the commit. Each part wraps whole, a long path goes on over lines, and the stage is named.
test('the push lines keep the process, time and whole log in the 60-column pane, and name the stage that runs', () => {
  const sha = 'a1b2c3d4e5f6a7b8', log = `/r/home/state/${'deep/'.repeat(12)}pushlogs/20261110T043700Z-4242.log`
  const pane = (h: object) => paneModel(board({ health: h }), 60, 0).map(plain)
  const run = (stage: string) => pane({ pushing: { pid: 4242, since: ago(3), sha, log, sec: 170, line: '12/40 passed', stale: false, stage } })
  const logOf = (l: string[]) => { const i = l.findIndex(x => x.includes('Log: ')), n = l.slice(i + 1).findIndex(x => !x.startsWith('  '))
    return l.slice(i, n < 0 ? undefined : i + 1 + n).map(x => x.replace(/^ {2}/, '')).join('') }
  const hook = run('hook')
  expect(hook.every(l => cols(l) <= 60)).toBe(true)
  expect(hook.join('\n')).toContain(`push on a1b2c3d4e5f6: pre-push hook running since ${clockOf(NOW - 3 * 60_000)}\n  pid 4242 · 3m\n  12/40 passed`)
  expect(run('tests').join('\n')).toContain('push on a1b2c3d4e5f6: tests before the push running since')
  expect(run('pushed').join('\n')).toContain('push on a1b2c3d4e5f6: pushed, waiting for GitHub since')
  // It said so too while the push waited for its test slot, and after git push ended (these wrap: read as one text).
  const flat = (l: string[]) => l.join(' ').replace(/\s+/g, ' ')
  expect(run('ready').every(l => cols(l) <= 60)).toBe(true)
  expect(flat(run('ready'))).toContain('push on a1b2c3d4e5f6: getting the push ready (worktree, dependencies, test slot) since')
  expect(flat(run('ended'))).toContain('push on a1b2c3d4e5f6: git push ended, finishing the push since')
  expect(flat(run('push'))).toContain('push on a1b2c3d4e5f6: push running with no pre-push hook since')
  expect([...run('tests'), ...run('ready'), ...run('ended'), ...run('pushed')].join('\n')).not.toContain('pre-push hook')
  const stale = pane({ pushing: { pid: 4242, since: ago(3), sha, log, sec: 170, line: '', stale: true, stage: 'hook' } })
  expect(stale.every(l => cols(l) <= 60)).toBe(true)
  expect(logOf(stale)).toBe(`Log: ${log}`)
  const failed = pane({ unpushed: [{ card: 'c0-7', issue: 7 }], pushLast: { time: ago(2), by: 'now', started: true, sha, ok: false, ahead: null, check: 'fast-checks', log, why: null } })
  expect(failed.every(l => cols(l) <= 60)).toBe(true)
  expect(logOf(failed)).toBe(`Log: ${log}`)
})

test('a card on the belt shows its start and overall time: resumed from a kept patch, the first start and the sum; another day, the date', () => {
  expect(beltCard({ track: track('>.....', 'building') })[0]).toMatch(new RegExp(` ${clockOf(NOW - 40 * 60_000)} · 40m · \\$1\\.25$`))
  const resumed = beltCard({ start: ago(100), priorSec: 1200, track: track('>.....', 'building') })[0]
  expect(resumed).toMatch(new RegExp(` ${clockOf(NOW - 100 * 60_000)} · 1h 0m · \\$1\\.25$`))
  const old = beltCard({ start: ago(26 * 60), pickedAt: ago(26 * 60), track: track('>.....', 'building') }, 80)[0]
  const day = new Date(NOW - 26 * 3600_000)
  expect(old).toMatch(new RegExp(` ${day.toLocaleString('en-US', { month: 'short' })} ${day.getDate()} ${clockOf(day.getTime())} · 26h 0m · \\$1\\.25$`))
})

test('no view prints an estimate of time: no "usual", no "to landing"', () => {
  const s = board({ belt: [{ ...BELT[1], ...TIMES, track: track('++->..', 'tests', { files: { run: 3, of: 12 } }) }], landed: LANDED })
  for (const text of [tableText(s, 62), tableText(s, 120), paneModel(s, 62, 0).map(plain).join('\n')]) {
    expect(text).not.toMatch(/usual|to landing|estimate/)
  }
  expect(tableText(s, 62)).toContain('testing 3m')
})

// the Test step's progress, read from the track; a value that is not a number is none.
test('a track parses its tests done, of and failed, and its test files run of all; a value that is not a number parses to none', () => {
  const parsed = (over: object) => board({ belt: [{ ...BELT[1], ...TIMES, track: track('+++>..', 'tests', over) }] }).snap?.belt[0].track
  expect(parsed({ tests: { done: 3, of: 5, failed: 1 } })).toMatchObject({ tests: { done: 3, of: 5, failed: 1 } })
  expect(parsed({ files: { run: 3, of: 6 } })).toMatchObject({ tests: null, files: { run: 3, of: 6 } })
  expect(parsed({ tests: { done: '3', of: 5, failed: 1 }, files: { run: '3', of: 6 } })).toMatchObject({ tests: null, files: null })
})

// the track kept the measured seconds and repeat counts from the view.
test('the track shows what was measured where the width has room: a done step its time, a repeated one its count', () => {
  const t = track('+++>..', 'tests')
  t.steps[0].sec = 960
  Object.assign(t.steps[1], { n: 2 })
  Object.assign(t.steps[2], { n: 2 })
  expect(beltCard({ track: t }, 100)[1]).toBe(' ✓ Build 16m ━━ ✓ Review 2 of 3 31s ━━ ✓ Fix 2 32s ━━ ▶ Test ── Land ── Push')
  // at the panel's 62 columns the joins narrow, and every time and count is still shown.
  expect(beltCard({ track: t }, 62)[1]).toBe(' ✓ Build 16m━✓ Review 2 of 3 31s━✓ Fix 2 32s━▶ Test─Land─Push')
  // Narrower, a count reads 2/3, then the times give way from the last done step back, then the counts; the six
  // steps are never cut.
  expect(beltCard({ track: t }, 55)[1]).toBe(' ✓ Build 16m━✓ Review 2/3 31s━✓ Fix 2━▶ Test─Land─Push')
  expect(beltCard({ track: t }, 50)[1]).toBe(' ✓ Build 16m━✓ Review 2/3━✓ Fix 2━▶ Test─Land─Push')
  expect(beltCard({ track: t }, 45)[1]).toBe(' ✓ Build━✓ Review━✓ Fix━▶ Test─Land─Push')
  // what the track drops is on a dim line under it, whole, so no measured time or count is lost.
  expect(beltCard({ track: t }, 50)[2]).toBe('    Review 31s · Fix 32s')
  expect(beltCard({ track: t }, 45)[2]).toBe('    Build 16m · Review 2 of 3 31s · Fix 2 32s')
  expect(beltCard({ track: t }, 62)[2]).not.toMatch(/^ {4}\S/)
})

// A fix the Done-when check on the build's reply started (track.jq replyFix) is Build's: without the note, /units drew
// Build ✓ then Review in progress with no word of the fix, and the fix read as if it never ran or as a Fix step.
test('a reply-check fix is drawn on Build, and Fix is not ticked before the first review', () => {
  const running = track('>.....', 'building')
  running.steps[0].replyFix = 'now'
  expect(beltCard({ track: running }, 100)[1]).toBe(' ▶ Build · reply check fix ── Review ── Fix ── Test ── Land ── Push')
  const fixed = track('+>....', 'review 1 of 3')
  fixed.steps[0].replyFix = 'done'
  expect(beltCard({ track: fixed }, 100)[1]).toBe(' ✓ Build 30s · reply check fixed ━━ ▶ Review 1 of 3 ── Fix ── Test ── Land ── Push')
  // Too narrow for the note, it goes to the line under the track with what else was dropped.
  expect(beltCard({ track: fixed }, 45)[2]).toBe('    Build 30s · reply check fixed')
})

// Issue 261 (track.jq lintFix). Bugs: the review gate's lint fix after the build read as a Fix round before the first
// review, and the landing gate's as a bare "Fix 2", so the owner could not tell a lint fix from a review's.
test('a lint fix is drawn on Build at the review gate and as a lint Fix round at the landing gate', () => {
  const review = track('>.....', 'fix after review 0')
  Object.assign(review.steps[0]!, { lintFix: 'now' })
  expect(beltCard({ track: review }, 100)[1]).toBe(' ▶ Build · lint fix ── Review ── Fix ── Test ── Land ── Push')
  const fixed = track('+>....', 'review 1 of 3')
  Object.assign(fixed.steps[0]!, { lintFix: 'done' })
  expect(beltCard({ track: fixed }, 100)[1]).toBe(' ✓ Build 30s · lint fixed ━━ ▶ Review 1 of 3 ── Fix ── Test ── Land ── Push')
  const land = track('++>...', 'fix after review 1')
  Object.assign(land.steps[2]!, { n: 2, lintFix: 'now' })
  expect(beltCard({ track: land }, 100)[1]).toBe(' ✓ Build 30s ━━ ✓ Review 31s ━━ ▶ Fix 2: lint findings ── Test ── Land ── Push')
  // The review gate's lint fix after a rebuild is Land's: it read as a plain "Land".
  const rebuilt = track('++-+>.', 'rebuilding after a conflict')
  Object.assign(rebuilt.steps[4]!, { lintFix: 'now' })
  expect(beltCard({ track: rebuilt }, 120)[1]).toContain('▶ Land · lint fix ── Push')
})

// A card split for its size (#448, track.jq grown): without the note, /units drew a change cut from 5 files to 2 as
// any other card, and the owner could not tell that part of the work went to follow-ups.
test('a card split for its size says so on Build, with the count of files before and after', () => {
  const t = track('++>...', 'review 1 of 3', { grown: { before: 5, after: 2 } })
  expect(beltCard({ track: t }, 120)[1]).toBe(' ✓ Build 30s · split for its size, 5 → 2 files ━━ ✓ Review 31s ━━ ▶ Fix ── Test ── Land ── Push')
})

// at the panel's 62 columns, Push in progress after five 960-second steps, three reviews of three and two fixes
// lost the Test and Land times from the track; they are on the line under it.
test('a track too full for its width keeps the dropped times and counts on a line under it', () => {
  const t = track('+++++>', 'pushing')
  for (const st of t.steps.slice(0, 5)) st.sec = 960
  Object.assign(t.steps[1], { n: 3 })
  Object.assign(t.steps[2], { n: 2 })
  const card = beltCard({ step: 'push', landed: true, track: t }, 62)
  for (const l of card) expect(cols(l)).toBeLessThanOrEqual(62)
  expect(card[1]).toBe(' ✓ Build 16m━✓ Review 3/3 16m━✓ Fix 2 16m━✓ Test━✓ Land━▶ Push')
  expect(card[2]).toBe('    Test 16m · Land 16m')
  expect(card[3]).toMatch(/pushing/)
  // In NEEDS YOU the track is indented under the card, and what it drops follows it the same way.
  const blocked = { ...BLOCKED, reason: 'push refused', track: { ...t, at: null, since: null }, reviews: [] }
  const lines = section(tableText(board({ needsYou: { waiting: [], blocked: [blocked] } }), 62), 'NEEDS YOU').split('\n')
  const at = lines.findIndex(l => l.startsWith('    ✓ Build'))
  expect(cols(lines[at])).toBeLessThanOrEqual(62)
  expect(lines[at + 1]).toMatch(/^ {4}(\S.*)?Land 16m$/)
})

test('the track has its five states: a skipped step has a dash, a failed one its cross; the joins fill as the card moves on', () => {
  expect(beltCard({ track: track('++->..', 'tests') })[1]).toBe(' ✓ Build 30s━✓ Review 31s━– Fix━▶ Test─Land─Push')
  expect(beltCard({ track: track('-+-+>.', 'landing') })[1]).toBe(' – Build━✓ Review 31s━– Fix━✓ Test 33s━▶ Land─Push')
  // Wide enough, the joins are the wide ones.
  expect(beltCard({ track: track('++->..', 'tests') }, 100)[1]).toBe(' ✓ Build 30s ━━ ✓ Review 31s ━━ – Fix ━━ ▶ Test ── Land ── Push')
  const failed = beltCard({ step: 'push', landed: true, track: track('++-++!', 'push failed; it is tried again', { reason: 'pre-push hook refused' }) })
  expect(failed[1]).toBe(' ✓ Build 30s━✓ Review 31s━– Fix━✓ Test 33s━✓ Land 34s━✗ Push')
  expect(failed[2]).toMatch(/push failed 3m$/)
  // the recorded reason is shown under it, cut at the panel's width.
  expect(failed[3]).toBe('   ✗ pre-push hook refused')
  const long = beltCard({ step: 'push', landed: true, track: track('++-++!', 'push failed; it is tried again', { reason: `exit 1: ${'x'.repeat(200)}` }) })
  expect(long[3].startsWith('   ✗ exit 1: x')).toBe(true)
  expect(cols(long[3])).toBeLessThanOrEqual(62)
  expect(beltCard({ track: track('++->..', 'tests') })).toHaveLength(3)
  // the follow-ups are filed before the landing, as part of Land: Land is in progress, Push to come.
  const filing = beltCard({ track: track('++++>.', 'filing follow-ups') })
  expect(filing[1]).toBe(' ✓ Build 30s━✓ Review 31s━✓ Fix 32s━✓ Test 33s━▶ Land─Push')
  expect(filing[2]).toMatch(/filing follow-ups 3m$/)
  // The order is Build, Review, Fix, Test, Land, Push at every step.
  for (const m of ['>.....', '+>....', '++>...', '++->..', '++-+>.', '++-++>']) {
    expect(beltCard({ track: track(m, '') })[1].split(/[━─]+/).map(s => /[A-Z][a-z]+/.exec(s)?.[0])).toEqual(NAMES)
  }
  // A track of another shape (an older loop's 17 steps) is none: the card shows what it is doing instead.
  expect(beltCard({ track: { steps: Array.from({ length: 17 }, () => ({ name: 'x', state: 'todo', sec: null })), at: 3, label: 'x', since: ago(3) } })[1]).toMatch(/^ ◐ review 2 of 3$/)
})

test('the reviews line: a review recorded with no counts shows its verdict alone, and verdicts give way from the oldest, never mid-figure', () => {
  const r = (round: number, verdict: string, c: object | null, fixed = false) => ({ round, verdict, counts: c, sec: 60, fixed })
  expect(beltCard({ track: track('++-+>.', 'landing'), reviews: [r(1, 'NO-GO', null, true), r(2, 'GO', null)] })[2]).toMatch(/^ R1 NO-GO · R2 GO +landing 3m$/)
  expect(tableText(board({ belt: [{ ...BELT[1], track: track('++-+>.', 'landing'), reviews: [r(1, 'NO-GO', null)] }] }), 62)).not.toContain('counts not recorded')
  const many = beltCard({ track: track('++-+>.', 'landing'), reviews: [1, 2, 3, 4].map(n => r(n, 'NO-GO', counts(1, 2, 3, 4), true)) })
  expect(cols(many[2])).toBeLessThanOrEqual(62)
  expect(many[2]).toMatch(/^ … · (R\d NO-GO 1 P0 2 P1 3 P2 4 P3 · )*R4 NO-GO 1 P0 2 P1 3 P2 4 P3 +landing 3m$/)
})

// /units showed nothing of the review's judge. A card's latest review the judge ran on gives its accepted and
// declined counts, and a GO that came only from its declining every finding is marked; a latest review it did not run
// on gives no judge line, whatever an earlier review had.
test('a card whose latest review the judge ran on shows its accepted and declined counts, and a GO from declined findings only is marked', () => {
  const r = (round: number, verdict: string, judge: object | undefined) => ({ round, verdict, counts: counts(0, 1, 0, 0), sec: 60, fixed: false, judge })
  const ran = (accepted: number, declined: number, go = false) => ({ ran: true, accepted, declined, go })
  const off = { ran: false, why: 'the judge is off' }
  const judged = beltCard({ track: track('++-+>.', 'landing'), reviews: [r(1, 'NO-GO', ran(2, 1))] })
  expect(judged.slice(2)).toEqual([expect.stringMatching(/^ NO-GO 1 P1 +landing 3m$/), '   judge: 2 accepted, 1 declined'])
  const go = beltCard({ track: track('++-+>.', 'landing'), reviews: [r(1, 'NO-GO', ran(1, 0)), r(2, 'GO', ran(0, 3, true))] })
  expect(go[3]).toBe('   judge: 0 accepted, 3 declined · GO from declines only')
  // The pane keeps its three lines a card: the judge is in /units only.
  expect(paneModel(board({ belt: [{ ...BELT[1], ...TIMES, track: track('++-+>.', 'landing'), reviews: [r(1, 'GO', ran(0, 3, true))] }] }), 62, 0).map(plain).join('\n')).not.toContain('judge')
  // Not run on the latest review (off, failed, or a snapshot that gives no judge): no judge line at all.
  for (const j of [off, { ran: false, why: 'the judge call failed' }, undefined]) {
    expect(beltCard({ track: track('++-+>.', 'landing'), reviews: [r(1, 'NO-GO', ran(1, 1)), r(2, 'GO', j)] }).join('\n')).not.toContain('judge')
  }
  // The same line under a card that needs you, and beneath a landed card.
  const s = board({
    needsYou: { waiting: [], blocked: [{ ...BLOCKED, reviews: [r(1, 'NO-GO', ran(1, 2))] }] },
    landed: [{ ...LANDED[1], rounds: [r(1, 'GO', ran(0, 2, true))] }, { ...LANDED[0], rounds: [r(1, 'GO', off)] }],
  })
  expect(section(tableText(s, 100), 'NEEDS YOU')).toContain('\n    R1 NO-GO  1 P1\n    judge: 1 accepted, 2 declined')
  const landed = section(tableText(s, 100), 'LANDED TODAY')
  expect(landed).toMatch(/#3860 Health record[^\n]*\n {9}judge: 0 accepted, 2 declined · GO from declines only$/)
  expect(landed.match(/judge:/g)).toHaveLength(1)
})

// Bug (#874): a card started from the kept patch of an earlier card did not say so in /units. Its start line (the
// track's kept) is a dim line under the card on the belt and under one that needs you; a card that started on main
// alone has none, and the pane keeps its three lines a card.
test('a card started from a kept patch names that patch\'s card under it; one that started on main has no such line', () => {
  const kept = 'resumed from the kept patch of card c1-3851: one session, then review'
  expect(beltCard({ track: track('++-+>.', 'landing', { kept }) }, 100)).toContain(`   ${kept}`)
  expect(beltCard({ track: track('++-+>.', 'landing') }, 100).join('\n')).not.toContain('kept patch')
  expect(section(tableText(board({ needsYou: { waiting: [], blocked: [{ ...BLOCKED, track: track('!.....', '', { kept }) }] } }), 100), 'NEEDS YOU')).toContain(`\n    ${kept}`)
  expect(paneModel(board({ belt: [{ ...BELT[1], ...TIMES, track: track('++-+>.', 'landing', { kept }) }] }), 62, 0).map(plain).join('\n')).not.toContain('kept patch')
})

// /units gives the number of findings the judge declined today, from the declined list's lines by the judge:
// those the Board's panel shows and those dismissed or built since, never a code or owner decline or an older day's,
// and a line two records share counted once.
test('/units shows how many findings the judge declined today', () => {
  const d = (id: string, by: string, time: string) => ({ id, time, card: 'c1', issue: 1, finding: `[P2] ${id}`, by, why: 'w', repo: 'bookstore' })
  const one = snapshot({ declined: [d('d1', 'judge', ago(1)), d('d2', 'code', ago(2)), d('d3', 'judge', ago(3 * 24 * 60))], declinedRest: [{ ...d('d4', 'judge', ago(5)), dismissed: { time: ago(4), by: 'owner' } }] })
  const other = snapshot({ declined: [d('d1', 'judge', ago(1)), d('d5', 'owner', ago(1))] })
  const s = state(fetched([['bookstore', one], ['widgetshop', other]]))
  expect(tableText(s, 80).split('\n')[2]).toBe('judge declined 2 findings today')
  expect(tableText(board(), 80).split('\n').slice(0, 4)).toEqual([expect.stringMatching(/^CONVEYOR/), expect.stringMatching(/^weekly limit/), 'judge declined no findings today', ''])
})

test('a card with no token read yet says no reading yet, never $0; one with a step not priced gives the dollars known and the gap', () => {
  expect(beltCard({ usd: null, reading: false })[0]).toMatch(/ · no reading yet$/)
  expect(beltCard({ usd: 0, reading: false })[0]).toMatch(/ · no reading yet$/)
  // Bug (#391): a build whose route streams every answer with usage 0 read "no reading yet" for its whole step.
  expect(beltCard({ usd: null, reading: false, atEnd: true }, 90)[0]).toMatch(/ · cost shown when the step ends$/)
  expect(beltCard({ usd: 0.5, reading: true })[0]).toMatch(/ · \$0\.50$/)
  // Bug (#1585): a card with a step not priced read a bare "cost partial", with no dollars, for good.
  expect(beltCard({ usd: null, usdKnown: 4.1, notPriced: 1, reading: true }, 90)[0]).toMatch(/ · \$4\.10 \+ 1 step not priced$/)
  expect(beltCard({ usd: 4.12, usdKnown: 4.12, notPriced: 0, estimate: true, reading: true })[0]).toMatch(/ · ~\$4\.12$/)
  // A snapshot that gives no dollars known (the price table could not be run) is partial, never $0.
  expect(beltCard({ usd: null, reading: true })[0]).toMatch(/ · cost partial$/)
})

// a follow-up shows a short title of what it fixes and the issue it came from, never the raw "[P2] path:line" title.
test('a follow-up shows its short title and its parent; a title no short one can be made of is cut at the width', () => {
  expect(shortTitle('[P2] .claude/dashboard/panels/metrics.js:53 The Host row omits recorded memory usage and CPU frequency, leaving these')).toBe('Metrics: Host row omits recorded memory usage')
  expect(shortTitle('[P1] conveyor/conveyor.sh:1479 A reviewer exiting 124 without readable usage writes no spent entry')).toBe('Conveyor: Reviewer exiting 124 without readable usage')
  expect(shortTitle('src/web/upload-form.tsx:12-14 the button is grey')).toBe('Upload form: Button is grey')
  // Bug: a cleanup follow-up's title ("[P3][cleanup] <file>:<line> ...", followups.sh) was kept raw.
  expect(shortTitle('[P3][cleanup] conveyor/lib/card.sh:52 the second check is redundant')).toBe('Card: Second check is redundant')
  // Bug: nor was one with a review's id before the mark ("[P3] [E1][cleanup] <file>:<line> ...").
  expect(shortTitle('[P3] [E1][cleanup] conveyor/lib/card.sh:52 x')).toBe('Card: X')
  expect(shortTitle('Fast lane lands through Conveyor')).toBe('Fast lane lands through Conveyor')
  const raw = '[P2] .claude/dashboard/panels/metrics.js:53 The Host row omits recorded memory usage'
  const line = beltCard({ title: raw, parent: 3874, track: track('>.....', 'building') })[0]
  expect(line).toMatch(/^ #3864 Metrics: Host row omit… ↳ #3874 +\S+ [AP]M · 40m · \$1\.25$/)
  expect(line).not.toContain('[P2]')
  expect(cols(line)).toBe(62)
  const long = beltCard({ title: 'A title that is far too long to fit on the line of a sixty-two column panel', track: track('>.....', 'building') })[0]
  expect(long).toMatch(/^ #3864 A title that is far too long t… +\S+ [AP]M · 40m · \$1\.25$/)
})

test('ON THE BELT with no open card says so', () => {
  expect(section(tableText(board(), 80), 'ON THE BELT')).toBe('ON THE BELT\n  the belt is empty')
})

test('QUEUE lists the next five, numbered, the title cut to fit and the priority right-aligned, then what each skipped label holds back', () => {
  const next = [{ issue: 3999, title: 'A follow-up with a title much too long for the line it is on', priority: 'P1', followup: true, retried: true }, ...queued(6)]
  const part = section(tableText(board({ queue: { next, skipped: skipped({ dormant: 37, backlog: 2 }) } }), 62), 'QUEUE')
  for (const l of part.split('\n')) expect(cols(l)).toBeLessThanOrEqual(62)
  expect(part.split('\n')).toEqual([
    'QUEUE  next 5 of 7',
    expect.stringMatching(/^ 1 #3999 A follow-up with a title m… +P1 · follow-up · retried$/),
    expect.stringMatching(/^ 2 #3900 Issue 0 +P2$/),
    expect.stringMatching(/^ 3 #3901 Issue 1 +P2$/),
    expect.stringMatching(/^ 4 #3902 Issue 2 +P2$/),
    expect.stringMatching(/^ 5 #3903 Issue 3 +P2$/),
    ' held back: 2 backlog · 37 dormant',
  ])
})

// Bug (#1438, O372): the pane read queue.held, which the snapshot no longer emits, so 'held back:' never showed. The
// snapshot gives queue.skipped (one entry an issue, with its rule) and queue.holding (the issues the record holds).
test('QUEUE counts what is held back from the snapshot\'s queue.skipped by rule and queue.holding', () => {
  const holding = [{ issue: 6001, title: 'Held one', priority: 'P2', waitsFor: [] }, { issue: 6002, title: 'Held two', priority: 'P2', waitsFor: [] }]
  const s = board({ queue: { next: queued(1), skipped: skipped({ dormant: 2, backlog: 1 }), holding } })
  expect(section(tableText(s, 80), 'QUEUE').split('\n').slice(-1)).toEqual([' held back: 1 backlog · 2 dormant · 2 held'])
  expect(paneModel(s, 80, 0).map(plain).join('\n')).toContain('held back: 1 backlog · 2 dormant · 2 held')
})

// Bug: at 40 columns `held back: 1 follow-ups · 1 P0 · 1 P1 · 1 P2` is 44 columns, and the pane and /units cut it, so
// the last count fell off. The counts wrap at the width instead, each whole.
test('held back wraps at its counts at 40 columns, never cut, in the pane and /units', () => {
  const s = board({ queue: { next: queued(1), skipped: skipped({ P0: 1, P1: 1, P2: 1, 'follow-ups': 1 }) } })
  const pane = paneModel(s, 40, 0).map(plain), at = pane.findIndex(l => l.startsWith('held back:'))
  expect(pane.slice(at, at + 2)).toEqual(['held back: 1 follow-ups · 1 P0 · 1 P1 ·', '  1 P2'])
  expect(section(tableText(s, 40), 'QUEUE').split('\n').slice(-2)).toEqual([' held back: 1 follow-ups · 1 P0 · 1 P1 ·', '   1 P2'])
})

// Bug: a rule (a label the pick never takes) one count wider than 40 columns was cut with '…' in the pane and /units,
// so the end of it was lost. It goes on over lines at its spaces instead.
test('held back wraps a rule wider than the line at its spaces at 40 columns, never cut, in the pane and /units', () => {
  const rule = 'waiting for the vendor to sign the contract'
  const s = board({ queue: { next: queued(1), skipped: skipped({ [rule]: 1 }) } })
  const pane = paneModel(s, 40, 0).map(plain), at = pane.findIndex(l => l.startsWith('held back:'))
  expect(pane.slice(at, at + 3)).toEqual(['held back:', '  1 waiting for the vendor to sign the', '  contract'])
  expect(section(tableText(s, 40), 'QUEUE').split('\n').slice(-3)).toEqual([' held back:', '   1 waiting for the vendor to sign the', '   contract'])
})

// Bug: a word in a held-back rule wider than the line was broken per code point, so `❤️` lost its variation selector
// to the next line at 40 columns in the pane and 41 in /units. It is broken between whole characters.
test('held back breaks a word wider than the line between whole characters, so an emoji stays whole', () => {
  // A label wider than the line, its emoji at column 37 of the count (`1 ` and 35 characters), where the line breaks.
  const rule = 'Fix-the-crash-seen-in-release-four-❤️-before-the-next-one'
  const s = board({ queue: { next: queued(1), skipped: skipped({ [rule]: 1 }) } })
  const pane = paneModel(s, 40, 0).map(plain), at = pane.findIndex(l => l.startsWith('held back:'))
  const units = section(tableText(s, 41), 'QUEUE').split('\n'), from = units.findIndex(l => l.startsWith(' held back:'))
  for (const lines of [pane.slice(at), units.slice(from)]) {
    expect(lines.filter(l => l.startsWith('\u{FE0F}') || l.trim().startsWith('\u{FE0F}')), `rule ${rule}: ${JSON.stringify(lines)}`).toEqual([])
    expect(lines.join(''), `rule ${rule}`).toContain('❤️')
  }
})

// The rule the pick (conveyor/jq/upnext.jq) gives an issue whose Depends on: line names no #N: the whole line, up to 200 characters.
const badDeps = (line: string) => `the line "${line}", not a list of issues in the form #N`
// Issue 1680. Bug it catches: the held-back count's label was the whole bad Depends on line, over four lines of the
// view, and did not say which issue holds it. The count is `bad Depends on` and the issue is a row of the Waiting table.
test('PICK ORDER counts an issue with a Depends on line of no #N as bad Depends on and lists it under Waiting, without the line', () => {
  const line = `Depends on: owner/project#12 (a note of the writer) ${'and the text of the line goes on here '.repeat(3)}`.slice(0, 150)
  expect(line.length).toBe(150)
  const s = board({ queue: { next: [], skipped: [{ issue: 4335, title: 'Bad line', rule: badDeps(line) }] } })
  const part = section(paneModel(s, 72, 0).map(plain).join('\n'), 'PICK ORDER').split('\n')
  expect(part.slice(1)).toEqual([expect.stringMatching(/^Waiting +Requires$/), expect.stringMatching(/^#4335 +a Depends on line with no #N$/), 'held back: 1 bad Depends on'])
  for (const text of [paneModel(s, 72, 0).map(plain).join('\n'), tableText(s, 72)]) expect(text).not.toContain('a note of the writer')
})

// Issue 1680. Bug it catches: two different bad lines made two counts; they count as one rule, a row each. The other
// rules keep their own counts.
test('two issues with different bad Depends on lines count as 2 bad Depends on, a row each, beside the other counts', () => {
  const skip = [{ issue: 4335, title: 'One', rule: badDeps('Depends on: # 2 3') }, { issue: 4336, title: 'Two', rule: badDeps('Depends on: the login fix') },
    { issue: 4337, title: 'Urgent', rule: 'P0' }, { issue: 4338, title: 'Later', rule: 'follow-ups' }]
  const s = board({ queue: { next: [], skipped: skip, holding: [{ issue: 4339, title: 'Held' }] } })
  const part = section(paneModel(s, 72, 0).map(plain).join('\n'), 'PICK ORDER').split('\n')
  expect(part.slice(1)).toEqual([expect.stringMatching(/^Waiting +Requires$/), expect.stringMatching(/^#4335 +a Depends on line with no #N$/),
    expect.stringMatching(/^#4336 +a Depends on line with no #N$/), 'held back: 2 bad Depends on · 1 follow-ups · 1 held · 1 P0'])
})

// Bug (#1438, O371): the mod sorted queue.next by follow-up and priority, so a pinned P2 issue the engine picks first
// showed below the P0 issue picked after it. Each record's order stands.
test('QUEUE and PICK ORDER keep the engine\'s pick order within a record: a pinned P2 stays ahead of a P0', () => {
  const next = [{ issue: 5, title: 'Pinned', priority: 'P2', followup: false, retried: false }, { issue: 9, title: 'Urgent', priority: 'P0', followup: false, retried: false }]
  const s = board({ queue: { next } })
  expect(section(tableText(s, 80), 'QUEUE').split('\n').slice(1, 3)).toEqual([expect.stringMatching(/^ 1 #5 /), expect.stringMatching(/^ 2 #9 /)])
  const pick = section(paneModel(s, 80, 0).map(plain).join('\n'), 'PICK ORDER')
  expect(pick.indexOf('#5')).toBeGreaterThan(-1)
  expect(pick.indexOf('#5')).toBeLessThan(pick.indexOf('#9'))
})

// Issue 875. Bug: with push off, an open issue whose card landed on an earlier day and is not pushed was in no part of
// /units: LANDED TODAY lists only today's landings, so it looked like open work. Its snapshot entry is open.held, a
// card reason notPushed; one held by you is not listed.
test('QUEUE names each open issue landed and not pushed, on any day, after the held-back line', () => {
  const open = { held: [{ issue: 3700, reasons: [{ kind: 'card', step: 'landed', card: 'c-3700', notPushed: true }] }, { issue: 3701, reasons: [{ kind: 'you' }] },
    { issue: 3702, reasons: [{ kind: 'card', step: 'landed', card: 'c-3702', notPushed: true }] }] }
  const s = board({ queue: { next: [], skipped: skipped({ dormant: 3 }) }, open })
  expect(section(tableText(s, 80), 'QUEUE').split('\n').slice(-2)).toEqual([' held back: 3 dormant', ' landed, not pushed: #3700 · #3702'])
  expect(paneModel(s, 80, 0).map(plain).join('\n')).toMatch(/\nheld back: 3 dormant\nlanded, not pushed: #3700 · #3702\n/)
})

test('QUEUE shows an issue that waits on another after the next ones, as "Waits for #N", never numbered', () => {
  const waiting = [{ issue: 3950, title: 'Second half', waitsFor: [3900] }, { issue: 3951, title: 'Both', waitsFor: [3900, 3950] }, { issue: 3952, title: 'Bad', waitsFor: [] }]
  const part = section(tableText(board({ queue: { next: queued(1), waiting } }), 80), 'QUEUE')
  expect(part.split('\n')).toEqual([
    'QUEUE  1',
    expect.stringMatching(/^ 1 #3900 Issue 0 +P2$/),
    expect.stringMatching(/^ · #3950 Second half +Waits for #3900$/),
    expect.stringMatching(/^ · #3951 Both +Waits for #3900, #3950$/),
  ])
  // A snapshot from before the list, or one whose issues were not listed, shows none.
  expect(section(tableText(board({ queue: { next: queued(1) } }), 80), 'QUEUE')).not.toContain('Waits for')
})

// Bug (issue 439): "Waits for #N" did not say why #N does not move, so the owner could not tell a stuck queue from one
// waiting on purpose. Each issue waited on carries its state from the snapshot's waitsOn: held, blocked, queued.
test('QUEUE says the state of each issue a waiting one waits for', () => {
  const waiting = [{ issue: 3950, title: 'Second half', waitsFor: [3900, 3901, 3902],
    waitsOn: [{ issue: 3900, state: 'held' }, { issue: 3901, state: 'blocked' }, { issue: 3902, state: 'queued' }] }]
  expect(section(tableText(board({ queue: { next: queued(1), waiting } }), 100), 'QUEUE').split('\n')[2])
    .toMatch(/^ · #3950 Second half +Waits for #3900 \(held\), #3901 \(blocked\), #3902 \(queued\)$/)
})

// Bug: at /units' 56 columns the 55-column label above did not fit beside the title, and spread dropped it whole.
// A label too long for the line goes under the title, wrapped at its words.
test('QUEUE puts a "Waits for" label too long for the line under the title, not drops it', () => {
  const waiting = [{ issue: 3950, title: 'Second half', waitsFor: [3900, 3901, 3902],
    waitsOn: [{ issue: 3900, state: 'held' }, { issue: 3901, state: 'blocked' }, { issue: 3902, state: 'queued' }] }]
  expect(section(tableText(board({ queue: { next: queued(1), waiting } }), 56), 'QUEUE').split('\n').slice(2)).toEqual([
    ' · #3950 Second half',
    '    Waits for #3900 (held), #3901 (blocked),',
    '      #3902 (queued)',
  ])
})

// Bug (issue 439): a queue whose only issues wait on another read "the queue is empty" above them. It says nothing can
// be picked and names what they wait for, once each, with its state.
test('QUEUE whose issues all wait says nothing can be picked and names what they wait for, not that it is empty', () => {
  const waiting = [{ issue: 3950, title: 'Second half', waitsFor: [3967, 3959], waitsOn: [{ issue: 3967, state: 'held' }, { issue: 3959, state: 'blocked' }] },
    { issue: 3951, title: 'Third', waitsFor: [3967], waitsOn: [{ issue: 3967, state: 'held' }] }]
  const part = section(tableText(board({ queue: { next: [], waiting } }), 100), 'QUEUE')
  expect(part).not.toContain('the queue is empty')
  // Not "each waits for": #3951 waits for #3967 only.
  expect(part.split('\n').slice(0, 2)).toEqual(['QUEUE', '  nothing can be picked: waiting for #3959 (blocked), #3967 (held)'])
})

test('the issues built and waiting for a PROD deploy are a section of their own under QUEUE, with how long each has waited; with none there is no section', () => {
  const awaitingDeploy = [{ issue: 3476, title: 'Stack split', since: ago(2 * 24 * 60) }, { issue: 3500, title: 'Label time not read', since: null }]
  const text = tableText(board({ queue: { next: queued(1) }, awaitingDeploy }), 80)
  expect(section(text, 'BUILT').split('\n')).toEqual([
    'BUILT, WAITING FOR YOUR PROD DEPLOY (2)',
    expect.stringMatching(/^· #3476 Stack split +waiting 2d\b.*$/),
    '· #3500 Label time not read',
  ])
  expect(section(text, 'QUEUE')).not.toContain('3476')
  expect(text.indexOf('QUEUE')).toBeLessThan(text.indexOf('BUILT'))
  expect(text.indexOf('BUILT')).toBeLessThan(text.indexOf('LANDED TODAY'))
  expect(paneModel(board({ awaitingDeploy }), 60, 0).map(plain).join('\n')).toContain('BUILT, WAITING FOR YOUR PROD DEPLOY (2)')
  // None, the list null (GitHub did not list the issues) or a record whose loop gives no such list: no section.
  for (const over of [{ awaitingDeploy: [] }, { awaitingDeploy: null }, {}]) expect(tableText(board(over), 80)).not.toContain('PROD DEPLOY')
  // Every record's issues, each named by its repo as the other sections name it.
  const both = state(fetched([['bookstore', snapshot({ awaitingDeploy: [awaitingDeploy[0]] })], ['widgetshop', snapshot({ awaitingDeploy: [{ issue: 9, title: 'Plugin', since: null }] })]]))
  expect(section(tableText(both, 80), 'BUILT')).toMatch(/\(2\)\n· #3476 Stack split.*\n· widgetshop#9 Plugin$/)
})

test('QUEUE with nothing to pick says so, and one GitHub did not list says it was not read', () => {
  expect(section(tableText(board(), 80), 'QUEUE')).toBe('QUEUE\n  the queue is empty')
  const unread = board({ queue: { next: null } })
  expect(section(tableText(unread, 80), 'QUEUE')).toBe('QUEUE\n  not read: GitHub did not list the issues')
})

// the per-card measurements the dashboard's detail shows, as two lines under the card; a reading not taken is
// "missing", never 0; a snapshot from before them shows nothing new, and the short view keeps its one line a card.
test('a card shows its measurements under it, a reading not taken reads missing, and an old snapshot shows none', () => {
  const M = { leadSec: 5760, cycleSec: 2160, queueSec: 3600, slotSec: 60, buildSec: 600, reviewSec: 600, fixSec: null, testSec: 300, landSec: 60, pushSec: 240, waitMaxSec: null,
    diff: { files: 2, added: 30, removed: 4 }, findings: { P0: 0, P1: 2, P2: 1, P3: 0 }, limit: { before: 10, after: 12, used: 2 }, reviews: 2, rebuilds: 0, retries: 1,
    depth: 0, followups: 0, blockClass: null, tokens: 3000000, usd: 6, unpriced: 0 }
  const part = section(tableText(board({ needsYou: { waiting: [], blocked: [{ ...BLOCKED, metrics: M }] } }), 400), 'NEEDS YOU').split('\n')
  const at = part.findIndex(l => l.includes('lead '))
  expect(part[at]).toBe('    lead 1h 36m · cycle 36m · queued 1h 0m · slot wait 1m · build 10m · review 10m · fix missing · tests 5m · landing 1m · to push 4m · waiting on you missing')
  expect(part[at + 1]).toBe('    2 files +30 −4 · findings 2 P1, 1 P2 · reviews 2 · rebuilds 0 · retries 1 · depth 0 · follow-ups 0 · limit 2 pts · 3.0M tokens · $6.00')
  expect(part.filter(l => l.includes('lead ')).length).toBe(1)
  // the belt and landed cards are the three and two lines of the pane's design: their measurements are the dashboard's.
  expect(tableText(board({ landed: [{ ...LANDED[0], metrics: M }], belt: [{ ...BELT[1], metrics: M }] }), 400)).not.toContain('lead ')
  const old = { ...M, leadSec: null, diff: null, depth: null, findings: null, limit: { before: null, after: null, used: null }, blockClass: 'timeout', usd: null, unpriced: 1 }
  const need = section(tableText(board({ needsYou: { waiting: [], blocked: [{ ...BLOCKED, metrics: old }] } }), 400), 'NEEDS YOU')
  expect(need).toMatch(/lead missing/)
  expect(need).toMatch(/diff missing · findings missing · reviews 2 · rebuilds 0 · retries 1 · depth missing · follow-ups 0 · limit missing · 3\.0M tokens · cost partial: 1 step not priced · blocked: timeout/)
  // Bug caught (#1585 review): NEEDS YOU hid the known dollars of a card with a step not priced, and showed an
  // estimate as exact.
  const needOf = (m: object) => section(tableText(board({ needsYou: { waiting: [], blocked: [{ ...BLOCKED, metrics: m }] } }), 400), 'NEEDS YOU')
  expect(needOf({ ...old, usdKnown: 4.1 })).toMatch(/ · 3\.0M tokens · \$4\.10 \+ 1 step not priced · blocked: timeout/)
  expect(needOf({ ...M, usdKnown: 6, estimate: true })).toMatch(/ · 3\.0M tokens · ~\$6\.00$/m)
  expect(need).not.toMatch(/lead 0|depth 0|limit 0/)
  expect(tableText(board({ landed: LANDED }), 400)).not.toMatch(/lead |missing/)
})

// /units shows the card's step timeline (seconds, tokens, dollars, model, findings, tests and the
// session's stats) as the dashboard's detail does, and wraps the measurement lines at a narrow width instead of
// cutting their later fields off.
test('a card shows its step timeline, and its measurements wrap at a narrow width with no field cut off', () => {
  const timeline = [
    { step: 'build', result: 'ok', sec: 600, tokens: 1000000, usd: 2, model: 'claude-opus-5-5', effort: 'medium', unpriced: null, counts: null, tests: null,
      stats: { turns: 3, apiSec: 3, tools: { Bash: 2, Read: 1 }, refused: 1, cacheHit: 0.97, models: ['claude-opus-5-5'] } },
    { step: 'review', result: 'NO-GO', sec: 300, tokens: 500000, usd: 1, model: 'gpt-6.1-sol', effort: null, unpriced: null, counts: { P0: 0, P1: 2, P2: 0, P3: 0 }, tests: null,
      stats: { turns: 1, tools: { command_execution: 2 } } },
    { step: 'test', result: 'pass', sec: 300, tokens: 0, usd: 0, model: null, effort: null, unpriced: null, counts: null,
      tests: { files: 3, total: 12, passed: 10, failed: 0, skipped: 2 }, stats: null },
  ]
  const M = { leadSec: 5760, cycleSec: 2160, queueSec: 3600, slotSec: 60, buildSec: 600, reviewSec: 600, fixSec: null, testSec: 300, landSec: 60, pushSec: 240, waitMaxSec: null,
    diff: { files: 2, added: 30, removed: 4 }, findings: { P0: 0, P1: 2, P2: 1, P3: 0 }, limit: { before: 10, after: 12, used: 2 }, reviews: 2, rebuilds: 0, retries: 1,
    depth: 0, followups: 0, blockClass: null, tokens: 3000000, usd: 6, unpriced: 0, timeline }
  const blocked = (m: object) => board({ needsYou: { waiting: [], blocked: [{ ...BLOCKED, metrics: m }] } })
  const wide = section(tableText(blocked(M), 400), 'NEEDS YOU')
  expect(wide).toContain('      build · 10m · 1.0M tokens · $2.00 · claude-opus-5-5 medium · turns 3 · API 3s · tools Bash 2, Read 1 · refused 1 · cache hits 97% · ran claude-opus-5-5')
  expect(wide).toContain('      review NO-GO · 5m · 500k tokens · $1.00 · gpt-6.1-sol · findings 2 P1 · turns 1 · tools command_execution 2')
  expect(wide).toContain('      test pass · 5m · 0 tokens · $0.00 · tests 10 passed, 0 failed, 2 skipped of 12 (3 files)')
  // A step with no price says why; a session whose usage was not read has its tokens missing, not 0.
  const unpriced = [{ ...timeline[0], usd: null, tokens: null, unpriced: 'its token usage could not be read: the session output holds no token usage' }]
  expect(section(tableText(blocked({ ...M, usd: null, unpriced: 1, timeline: unpriced }), 400), 'NEEDS YOU'))
    .toContain('      build · 10m · missing tokens · not priced: its token usage could not be read: the session output holds no token usage · claude-opus-5-5 medium')
  // Bug caught (#1585 review): a step priced as an estimate read as exact in the timeline.
  const estimated = [{ ...timeline[0], tokens: null, estimate: 'the tokens it counted, at its model\'s price' }]
  expect(section(tableText(blocked({ ...M, timeline: estimated }), 400), 'NEEDS YOU')).toContain('      build · 10m · missing tokens · ~$2.00 · claude-opus-5-5 medium')
  const narrow = section(tableText(blocked(M), 80), 'NEEDS YOU')
  expect(narrow.split('\n').every(l => l.length <= 80)).toBe(true)
  expect(narrow.split('\n').filter(l => l.startsWith('    ') && !l.includes('blocked:')).join('\n')).not.toContain('…')
  for (const f of ['waiting on you missing', 'retries 1', 'follow-ups 0', 'limit 2 pts', '$6.00', 'ran claude-opus-5-5', '(3 files)']) expect(narrow).toContain(f)
})

// the count and the day's cost in the heading; per card the time, a check mark, the issue and short
// title, the last verdict and its round, and the cost ("pushing" while the push runs); beneath, its start and overall
// time, and the follow-ups it filed.
test('LANDED TODAY gives the time, the last verdict and its round, the cost or pushing, its start and overall time, and its follow-ups', () => {
  const r = (round: number, verdict: string) => ({ round, verdict, counts: null, sec: 60, fixed: false })
  const landed = [
    { ...LANDED[0], start: ago(53), pickedAt: ago(53), priorSec: 0, totalSec: 2400, rounds: [r(1, 'NO-GO'), r(2, 'NO-GO'), r(3, 'NO-GO')] },
    { ...LANDED[1], usd: 0.85, pushed: false, rounds: [r(1, 'NO-GO'), r(2, 'GO')], track: track('++-++>', 'pushing', { at: 5 }) },
    LANDED[2],
  ]
  // the heading's cost is the day's (today's priced steps), not the sum of the landed cards' lifetime costs.
  const part = section(tableText(board({ landed, cost: { today: 20 } }), 62), 'LANDED TODAY').split('\n')
  for (const l of part) expect(cols(l)).toBeLessThanOrEqual(62)
  expect(part).toEqual([
    'LANDED TODAY  3 · $20.00',
    expect.stringMatching(new RegExp(`^ ${clockOf(NOW - 13 * 60_000)} ✓ #3862 One snapshot record +NO-GO r3  \\$4\\.21$`)),
    `         started ${clockOf(NOW - 53 * 60_000)} · 40m overall`,
    '           ↳ 2 follow-ups: #3870 #3871',
    expect.stringMatching(/^ \S+ [AP]M ✓ #3860 Health record +GO r2  pushing$/),
    expect.stringMatching(/^ \S+ [AP]M ✓ #3858 Already there +already fixed  \$0\.40$/),
  ])
  // A day not all priced: the heading's cost is partial, never the sum of the rest.
  expect(section(tableText(board({ landed: LANDED, cost: { today: null } }), 62), 'LANDED TODAY').split('\n')[0]).toBe('LANDED TODAY  3 · cost partial')
  // Bug (#1585): a landed card with a step not priced read "cost partial"; one priced as an estimate read as exact.
  // The heading's day gives the steps it leaves out too.
  const est = section(tableText(board({ landed: [{ ...LANDED[0], usd: null, usdKnown: 4.1, notPriced: 1 }, { ...LANDED[2], usd: 0.4, estimate: true }],
    cost: { today: 4.5, todayLeftOut: 1, todayEstimate: 1 } }), 90), 'LANDED TODAY').split('\n')
  expect(est[0]).toBe('LANDED TODAY  2 · ~$4.50 + 1 step not priced')
  expect(est[1]).toMatch(/#3862 One snapshot record .* \$4\.10 \+ 1 step not priced$/)
  expect(est.find(l => l.includes('#3858'))).toMatch(/already fixed  ~\$0\.40$/)
})

// The owner read "pushing" on a landed card, with push off and nothing pushed, as a push against the rule. With push
// off the snapshot gives it no running step (at null) and the label of what it waits for: /units says that.
test('LANDED TODAY with push off: a landed, unpushed card says it waits for Push landed, never pushing', () => {
  const landed = [{ ...LANDED[1], track: track('++-++.', 'Landed, waiting for Push landed', { at: null }) }]
  const part = section(tableText(board({ landed }), 80), 'LANDED TODAY')
  expect(part).toMatch(/#3860 Health record .*Landed, waiting for Push landed$/m)
  expect(part).not.toMatch(/pushing|not pushed/)
})

test('LANDED TODAY with no landing says so', () => {
  expect(section(tableText(board(), 80), 'LANDED TODAY')).toBe('LANDED TODAY\n  nothing landed today')
})

const lane = (fast: string, over: object = {}, research: Research = { state: 'none' }) =>
  state(fetched([['bookstore', snapshot(over)]], undefined, fast), { research })

test('the Fast lane line says no worktree, nothing open, or the open change and whether it landed', () => {
  expect(fastText(lane('fast\tnone'))).toBe('no worktree on this machine')
  expect(fastText(lane('fast\tunread'))).toBe('not read: git did not answer')
  expect(fastText(lane('fast\tok\tfast-lane\t0\t0\t'))).toBe('nothing open')
  expect(fastText(lane('fast\tok\tfast-lane\t2\t1\tTidy the logo copy'))).toBe('2 commits on fast-lane: Tidy the logo copy · 1 file uncommitted · not landed')
  expect(fastText(lane('fast\tok\tHEAD\t1\t0\tx'))).toBe('1 commit on no branch: x · not landed')
  expect(tableText(lane('fast\tok\tfast-lane\t0\t3\t'), 80)).toMatch(/\nFAST LANE      3 files uncommitted$/)
})

// A fresh install sets up no lanes, and /units and the pane each said "no worktree on this machine" of both:
// a lane with no worktree is not drawn, and with neither there is no lane line at all.
test('a lane with no worktree on this machine is drawn nowhere; a lane that has one is drawn alone', () => {
  const none = board()
  const views = (s: State) => [tableText(s, 100), paneModel(s, 100, 0).map(plain).join('\n')]
  for (const v of views(none)) expect(v).not.toMatch(/lane/i)
  expect(tableText(none, 100)).toMatch(/\n {2}nothing landed today$/)
  const fast = lane('fast\tok\tfast-lane\t0\t0\t')
  for (const v of views(fast)) {
    expect(v).toMatch(/\n\nFAST LANE      nothing open$/)
    expect(v).not.toMatch(/research/i)
  }
})

// Issue 141: a main-red fix card has no issue (issue 0): /units named it by its title alone, the Foreman's views "#0".
// It is named `red <commit>` with its name, "Main is red (<commit>)", as its Title, once, on the belt and in Needs you: the
// snapshot's title ("Main is red: <cases>") is not shown in its place (issue 1582).
test('a main-red fix card is named `red <commit>` with its name as Title on the belt and in Needs you, never #0', () => {
  const red = { issue: 0, name: 'Main is red (0123456789ab)', title: 'Main is red: a.test' }
  const text = tableText(board({ needsYou: { waiting: [], blocked: [{ ...BLOCKED, ...red, card: 'c20261110T040000-bookstore-0' }] },
    belt: [{ ...BELT[0], ...red, card: 'c20261110T041000-bookstore-0', name: 'Main is red (fedcba987654)' }] }), 100)
  expect(section(text, 'NEEDS YOU')).toMatch(/red 0123456 Main is red \(0123456789ab\)/)
  expect(section(text, 'ON THE BELT')).toMatch(/red fedcba9 Main is red \(fedcba987654\)/)
  expect(text, 'the failing cases of the snapshot title are not shown').not.toMatch(/a\.test/)
  expect(text).not.toMatch(/#0\b/)
})

test('the Fast lane line names its card: on the belt with its step, needing you, or landed', () => {
  const card = { card: 'c9-0', issue: 0, title: 'Tidy the logo copy' }
  const fast = 'fast\tok\tfast-lane\t1\t0\tTidy the logo copy'
  expect(fastText(lane(fast, { belt: [{ ...BELT[1], ...card }] }))).toMatch(/ · card on the belt: review 2 of 3$/)
  expect(fastText(lane(fast, { needsYou: { waiting: [{ ...WAITING, ...card }], blocked: [] } }))).toMatch(/ · card needs you$/)
  expect(fastText(lane(fast, { landed: [{ ...LANDED[0], ...card }] }))).toMatch(new RegExp(` · card landed ${clockOf(NOW - 13 * 60_000)}$`))
  // A branch named as a card id of this project lands as that issue's card; another branchless card is not this lane's.
  expect(fastText(lane('fast\tok\tc20261110T040000-bookstore-3864\t1\t0\tx', { belt: BELT }))).toMatch(/ · card on the belt: review 2 of 3$/)
  // Issue 601: a number at the end of a hand fix's name is no issue (land-branch lands it as issue 0), so the lane
  // is not shown as the card of that issue.
  expect(fastText(lane('fast\tok\tfix-3864-units\t1\t0\tx', { belt: BELT }))).toMatch(/ · not landed$/)
  expect(fastText(lane(fast, { belt: [{ ...BELT[0], card: 'c8-0', issue: 0, title: 'Another change' }] }))).toMatch(/ · not landed$/)
})

// a checkout the host file has no record of (the owner's own machine) still reads the board; the Fast lane line says
// why it was not read.
test('no record of this checkout: the board still reads and the Fast lane line says the host file has none', () => {
  const text = `paths\t\t/r/home\nfast\tnorecord\nhost\tbuildbox\tssh\t0\nbookstore\t${snapshot()}\n`
  expect(parseFetch(text)).toMatchObject({ research: '', home: '/r/home', fast: { state: 'norecord' } })
  expect(fastText(state(text))).toBe('not read: the host file has no record of this checkout')
  expect(tableText(state(text), 80)).not.toMatch(/cannot be read/)
})

test('the Research lane line says no worktree, no run, working or idle with its last activity', () => {
  expect(researchText(lane('fast\tnone'))).toBe('no worktree on this machine')
  expect(researchText(lane('fast\tnone', {}, { state: 'ok', lastAt: null }))).toBe('no run recorded')
  expect(researchText(lane('fast\tnone', {}, { state: 'ok', lastAt: NOW - 2 * 60_000 }))).toBe('working · last activity 2m ago')
  const idle = lane('fast\tnone', {}, { state: 'ok', lastAt: NOW - 200 * 60_000 })
  expect(tableText(idle, 80)).toMatch(/\nRESEARCH LANE  idle · last activity 3h 20m ago$/)
})

test('a snapshot that cannot be read is one plain note saying why, in /units and the pane', () => {
  const cases: [string, string][] = [
    ['', 'the fetch did not run'],
    ['paths\t/r/ws\t/r/home\nfast\tnone\n', 'the fetch did not finish'],
    // Bug: the line always named ~/.config/conveyor/host.json, though the fetch looks under XDG_CONFIG_HOME and then
    // in the checkout: it names the paths the fetch looked at.
    [fetched([], 'host\t\tnofile\t0\t/r/xdg/conveyor/host.json\t/r/main/conveyor/host.json'), 'this machine has no host file at /r/xdg/conveyor/host.json or /r/main/conveyor/host.json'],
    [fetched([], 'host\t\tconfig\t0'), 'the host file is not understood'],
    [fetched([], 'host\tbuildbox\tssh\t255'), 'buildbox is unreachable'],
    [fetched([], 'host\tbuildbox\tssh\t124'), 'buildbox did not answer in time'],
    [fetched([['bookstore', 'null']]), 'buildbox gave no snapshot'],
    [fetched([['bookstore', '{"belt":[]}']]), 'buildbox gave no snapshot'],
    [fetched([['bookstore', '{"needsYou":{"waiting":[],"blocked":[]},"belt":[1],"landed":[],"queue":{},"cost":{}}']]), 'buildbox gave no snapshot'],
  ]
  for (const [text, why] of cases) {
    const s = state(text, { limit: { pct: 10, resetsAt: NOW + 1000 } })
    const line = `units: the Conveyor snapshot cannot be read (${why})`
    expect(tableText(s, 80)).toBe(line)
    // Wide enough for the longest reason on one row: the pane wraps a note at its width (the 32-column case below).
    expect(paneModel(s, 160, 0).map(plain)).toEqual([line])
  }
})

// Bug: the first record was the session's own whatever checkout the session was in: a session in gadgetlab showed
// bakery's card as #12 and looked for its Fast lane's card among bakery's, so it read `not landed`.
test('a session in the second project: its cards carry no name, the first\'s carry theirs, and its Fast lane finds its card', () => {
  const text = TWO_PROJECTS.replace('\t/r/HOME\tbakery\n', '\t/r/HOME\tgadgetlab\n').replace('fast\tnone', 'fast\tok\tc20261110T040000-gadgetlab-7\t1\t0\tGear ratio chart')
  const s = state(text)
  expect(tableText(s, 100)).toMatch(/\n bakery#12 Bread oven timer [^]*\n #7 Gear ratio chart /)
  expect(fastText(s)).toMatch(/ · card on the belt: review 1 of 3$/)
})

// Issue 398. Bug it catches: the fetch prints each record's kept snapshot, which can be minutes old, and the view
// showed it as if it were new. One over a minute old says its age under the board; a newer one says nothing.
test('a record\'s kept snapshot over a minute old says its age; a newer one adds no note', () => {
  const made = NOW - 5 * 60_000
  const old = tableText(board({ snapshotAt: new Date(made).toISOString(), belt: [BELT[1]] }), 100)
  expect(old).toMatch(new RegExp(`\\nunits: the bookstore snapshot is [45]m old \\(made at ${clockOf(made)}\\)$`))
  expect(tableText(board({ snapshotAt: new Date(NOW - 30_000).toISOString(), belt: [BELT[1]] }), 100)).not.toMatch(/snapshot is/)
})

// Issue 631. Bug it catches: a live stream sends a snapshot only when something in it changes, so on a quiet belt
// snapshotAt passed a minute while nothing was stale and the note showed about once a minute. With the stream down
// the note shows as from the host, and as read from the host with no feed.
test('a live feed\'s snapshot 90 s old adds no age note; with the stream down, or read from the host, it does', () => {
  const made = NOW - 90_000
  const snap = snapshot({ snapshotAt: new Date(made).toISOString() })
  const note = `units: the bookstore snapshot is 1m old (made at ${clockOf(made)})`
  const feed = (live: boolean) => boardOfFeed({ host: 'buildbox', local: false, ssh: 'owner@buildbox', records: [{ repo: 'bookstore', main: '/r/main', json: snap }], live, heardAt: made, error: '' }, '', '', null)
  const feedState = (b: ReturnType<typeof boardOfFeed>): State => ({ now: NOW, ...b, limit: null, fast: { state: 'none' }, research: { state: 'none' } })
  expect(ageNotes(state(fetched([['bookstore', snap]])))).toEqual([note])
  expect(ageNotes(feedState(feed(true)))).toEqual([])
  expect(ageNotes(feedState(feed(false)))).toEqual([note])
})

// Issue 1667: the feed's map is taken only from a feed of the machine the fetch's maphost line names (the ssh target
// the fetch reads the map at, or, empty, this machine), as another build machine can keep its checkout at the same
// path. Bugs it catches: with the Board on another build machine, /units showed that machine's map for this session's
// project, its record matched by path or host name alone; a feed of the same ssh target under another host name, or
// of a session that reads its map here, was judged by the host name; a feed of an older Board, with no ssh target,
// was taken as a match; and a fetch of an older engine, which prints no maphost line and matched the record by path
// alone, had its feed's map taken from a feed over ssh, so a Board at owner@oven showed oven's map to a session at lab,
// yet must keep it from a feed of one machine, the session's own, or /units shows no map.
test('the feed\'s test map is taken only from a feed of the machine the maphost line names', () => {
  const json = JSON.parse(snapshot({ testMap: { state: 'made', sources: 3, tests: 1, age: 0 } }))
  const feed = (host: string, local: boolean, ssh: string) => ({ host, local, ssh, records: [{ repo: 'bakery', main: '/srv/bakery', json }], live: true, heardAt: NOW, error: '' })
  const over = 'paths\t\t/h\t\nmaprec\t/srv/bakery\nmaphost\towner@lab\nhost\t\tfeed\t0\n'
  const here = 'paths\t\t/h\t\nmaprec\t/srv/bakery\nmaphost\t\nhost\t\tfeed\t0\n'
  expect(parseFetch(over), over).toMatchObject({ mapRec: '/srv/bakery', mapHost: 'owner@lab' })
  expect(parseFetch(here), here).toMatchObject({ mapRec: '/srv/bakery', mapHost: '' })
  const cases: [string, ReturnType<typeof feed>, string | null, boolean][] = [
    ['feed oven at owner@oven, maphost owner@lab', feed('oven', false, 'owner@oven'), 'owner@lab', false],
    ['feed lab at owner@oven, maphost owner@lab', feed('lab', false, 'owner@oven'), 'owner@lab', false],
    ['feed oven at owner@lab, maphost owner@lab', feed('oven', false, 'owner@lab'), 'owner@lab', true],
    ['feed lab with no ssh, not local (an older Board), maphost owner@lab', feed('lab', false, ''), 'owner@lab', false],
    ['feed lab on one machine, maphost this machine', feed('lab', true, ''), '', true],
    ['feed lab at owner@lab, maphost this machine', feed('lab', false, 'owner@lab'), '', false],
    ['feed oven at owner@oven, no maphost line (a fetch of an older engine)', feed('oven', false, 'owner@oven'), null, false],
    ['feed lab on one machine, no maphost line (a fetch of an older engine)', feed('lab', true, ''), null, true],
  ]
  for (const [what, f, mh, has] of cases) {
    const b = boardOfFeed(f, '', '/srv/bakery', mh)
    if (has) expect(b.testMap, what).toMatchObject({ state: 'made', sources: 3 })
    else expect(b, what).not.toHaveProperty('testMap')
  }
})

// Bug it catches: the pane drew a fetch's failure note and a record's not-read note at their full width, so in a
// 32-column dock body the terminal wrapped them. Each is wrapped at its spaces to the pane's width, no word lost.
test('the pane wraps the fetch-failure note and the feed notes to a 32-column dock body', () => {
  const cannot = 'units: the Conveyor snapshot cannot be read (buildbox is unreachable)'
  const notRead = 'units: the bookstore queue was not read (GitHub did not list the issues)'
  const failed = paneModel({ ...board(), snap: null, note: cannot }, 32, 0).map(plain)
  const noted = paneModel(board({}, { notes: [notRead] }), 32, 0).map(plain)
  for (const [lines, note] of [[failed, cannot], [noted, notRead]] as const) {
    const at = lines.findIndex(l => l.startsWith('units: the'))
    const rows = lines.slice(at, at + 3)
    expect(rows.every(l => cols(l) <= 32), `${note}: ${JSON.stringify(rows)}`).toBe(true)
    expect(rows.join(' ')).toBe(note)
  }
})

// Bug it catches: at 40 columns the four counts ran past the line and the last, NEEDS YOU, was cut off; the dots
// losing their spaces was not enough once the queue is long ("10+ READY"), so the counts take a second line.
test('the pane\'s count band shows NEEDS YOU in full at 40 columns, also with ten issues ready', () => {
  const lines = (over: object) => paneModel(board(over), 40, 0).map(plain)
  expect(lines({}).find(l => l.includes('ON BELT'))).toContain('NEEDS YOU')
  const busy = lines({ belt: BELT, needsYou: { waiting: [WAITING], blocked: [BLOCKED] }, queue: { next: queued(10) } })
  expect(busy.find(l => l.includes('NEEDS YOU') && !l.includes('NEEDS YOU ('))).toBe('0 WAITING · 2 NEEDS YOU')
  expect(busy.find(l => l.includes('ON BELT'))).toMatch(/^2 ON BELT · 10\+? READY$/)
})

test('a second record\'s cards carry its name, and one record that cannot be read costs only its own note', () => {
  const other = snapshot({ belt: [{ ...BELT[0], card: 'c1-12', issue: 12, title: 'Other work' }], cost: { today: 1 }, queue: { next: null } })
  const both = state(fetched([['bookstore', snapshot({ belt: [BELT[1]], cost: { today: 2.5 }, queue: { next: queued(1) } })], ['widgetshop', other]]))
  const text = tableText(both, 100)
  expect(text).toMatch(/^CONVEYOR +today \$3\.50  ● buildbox\n/)
  expect(text).toMatch(/\n #3864 Rebuild \/units for Conveyor /)
  expect(text).toMatch(/\n widgetshop#12 Other work /)
  expect(text).toMatch(/\n 1 #3900 Issue 0 /)
  expect(text).toMatch(/\nunits: the widgetshop queue was not read \(GitHub did not list the issues\)$/)
  const half = state(fetched([['bookstore', snapshot({ belt: [BELT[1]], cost: { today: 2.5 } })], ['widgetshop', 'null']]))
  expect(tableText(half, 100)).toMatch(/\n #3864 [^]*\nunits: the widgetshop snapshot cannot be read$/)
  // The unread record's spend is unknown, so dollars today is partial in every view, never the readable record's sum.
  expect(tableText(half, 100)).toMatch(/^CONVEYOR +today partial  ● buildbox\n/)
  expect(tableText(state(fetched([['bookstore', 'null'], ['widgetshop', other]])), 100)).toMatch(/^CONVEYOR +today partial  ● buildbox\n/)
})

// Issue 497, the pane's Build matrix layout; issue 603, the title after Cost. Bug it catches: at 60 columns a pane
// line wrapped (a title, a lane), or the matrix dropped the card's title and left the rest of each row empty.
test('the pane at 60 columns: no line wider than the pane, and each matrix row ends in its title, cut to fit', () => {
  const landed = Array.from({ length: 7 }, (_, i) => ({ ...LANDED[0], card: `c-${i}`, issue: 3800 + i, time: ago(i) }))
  const s = board({ needsYou: { waiting: [WAITING], blocked: [BLOCKED] }, belt: BELT, queue: { next: queued(10), skipped: skipped({ dormant: 3 }) }, landed, cost: { today: 29.48 } },
    { limit: { pct: 50, resetsAt: NOW + 3600_000 }, research: { state: 'ok', lastAt: NOW - 60_000 }, fast: { state: 'ok', branch: 'fast-lane', ahead: 1, dirty: 0, subject: 'A long subject '.repeat(8) } })
  const lines = paneModel(s, 60, 0).map(plain)
  for (const l of lines) expect(cols(l)).toBeLessThanOrEqual(60)
  const text = lines.join('\n')
  const matrix = section(text, 'BUILD MATRIX').split('\n')
  expect(matrix[1]).toMatch(/^ID +B R F T L P +Age +Cost  Title$/)
  // The long title is cut with … at the pane's edge; the short one is whole. Each starts two columns after its Cost.
  expect(matrix[2]).toMatch(/^#3863 +▶ · · · · · +\S+ +–  Rebuild the workflow[^]*…$/)
  expect(cols(matrix[2])).toBe(60)
  expect(matrix[3]).toMatch(/^#3864 +✓ ▶ · · · · +\S+ +\$1\.25  Rebuild \/units for Conveyor$/)
  expect(text).toMatch(/\n◆ #3861 Fast lane lands thro… · your yes: Staff land F… +12m\n✗ #3850 Logo upload · blocked: review 3 was NO-GO: … +1h 30m\n/)
  expect(text).toMatch(/\nPICK ORDER +next 5 of 10\+\n( \d #39\d\d Issue \d +P2\n){5}  nothing waiting\nheld back: 3 dormant\n/)
  expect(text).toMatch(/\nLANDED TODAY · 7 +5 most recent of 7\nLanded +Issue +Verdict +Total +Cost\n(\S+ [AP]M +#380\d +2 reviews +– +\$4\.21\n){5}/)
  expect(text).toMatch(/\nFAST LANE      1 commit on fast-lane: A long subject .*…\nRESEARCH LANE  working · last activity 1m ago$/)
})

// Issue 1461 (O381). Claude Code keeps a dock as narrow as 24 columns, so a pane body can be 32 columns, and the
// pane now draws at that width (units.test.tsx): a row laid out for 40 columns at least would run past it and wrap.
// Bug it catches: a part of the pane that pads or lays out a row wider than the pane it is given.
test('the pane at 32 columns: no line wider than the pane', () => {
  const s = board({ needsYou: { waiting: [WAITING], blocked: [BLOCKED] }, belt: BELT, queue: { next: queued(10), held: { dormant: 3 } }, landed: LANDED, cost: { today: 29.48 } },
    { limit: { pct: 50, resetsAt: NOW + 3600_000 }, research: { state: 'ok', lastAt: NOW - 60_000 }, fast: { state: 'ok', branch: 'fast-lane', ahead: 1, dirty: 0, subject: 'A long subject '.repeat(8) } })
  const wide = paneModel(s, 32, 0).map(plain).filter(l => cols(l) > 32)
  expect(wide).toEqual([])
})

// Issue 1461 (B-R429). Bug it catches: with push off, a landed card's "Landed, waiting for Push landed" (31 columns)
// set the shared Cost column's width, so at 60 columns the pushed card's row ran past the pane and lost its $4.21.
// The wait says "waiting" in that column and its label goes on a line of its own.
test('the pane at 60 columns: a landed card waiting for Push landed leaves the other cards\' costs whole', () => {
  const landed = [LANDED[0], { ...LANDED[1], track: track('++-++.', 'Landed, waiting for Push landed', { at: null }) }]
  const lines = section(paneModel(board({ landed }), 60, 0).map(plain).join('\n'), 'LANDED TODAY').split('\n')
  for (const l of lines) expect(cols(l)).toBeLessThanOrEqual(60)
  expect(lines.find(l => l.includes('#3862'))).toMatch(/ \$4\.21$/)
  expect(lines.find(l => l.includes('#3860'))).toMatch(/ waiting$/)
  expect(lines).toContainEqual(expect.stringMatching(/^ +Landed, waiting for Push landed$/))
})

// #1585 review. Bugs it catches: in a 32-column pane, `DAY SPEND $4.10 + 1 step not priced` (35 columns) did not fit
// the head, which then dropped the day's spend; and a card's known dollars and gap (25 columns) in the shared Cost
// column of BUILD MATRIX and LANDED TODAY widened every row, so the pane cut the cards' costs off. The column gives
// `$4.10+`, and the dollars and the gap in full go on a line of their own under the row. LANDED TODAY is read at 48
// columns: its rows are 45 wide with `$4.10+` in Cost, 64 with the whole text there. And (E30) `$4.50 + 1 step not
// priced` on the head's right left five columns for its left, which showed ` /un…`: the head keeps `/units` and the
// host whole beside `$4.50+`, and the day's dollars and gap go on the line under it.
test('the pane at 32 and 48 columns: a step not priced keeps the day\'s spend and the cards\' dollars, the gap on a line of its own', () => {
  const gap = { usd: null, usdKnown: 4.1, notPriced: 1 }
  const s = board({ belt: [{ ...BELT[1], ...gap }], landed: [{ ...LANDED[0], ...gap }, LANDED[2]], cost: { today: 4.5, todayLeftOut: 1 } })
  const narrow = paneModel(s, 32, 0).map(plain)
  for (const l of narrow) expect(cols(l)).toBeLessThanOrEqual(32)
  expect(narrow[0], `the head at 32 columns: ${narrow[0]}`).toMatch(new RegExp(`^ /units  ${s.host} +\\$4\\.50\\+$`))
  expect(narrow[1]).toMatch(/^ +\$4\.50 \+ 1 step not priced$/)
  expect(paneModel(s, 100, 0).map(plain)[0]).toMatch(/ DAY SPEND \$4\.50 \+ 1 step not priced$/)
  // The matrix's heading is cut at 32 columns, so its row is found in the whole pane.
  const at = narrow.findIndex(l => l.startsWith('#3864'))
  expect(narrow[at]).toMatch(/ \$4\.10\+$/)
  expect(narrow[at + 1]).toMatch(/^ +\$4\.10 \+ 1 step not priced$/)
  const landed = section(paneModel(s, 48, 0).map(plain).join('\n'), 'LANDED TODAY').split('\n')
  for (const l of landed) expect(cols(l)).toBeLessThanOrEqual(48)
  const row = landed.findIndex(l => l.includes('#3862'))
  expect(landed[row]).toMatch(/ \$4\.10\+$/)
  expect(landed[row + 1]).toMatch(/^ +\$4\.10 \+ 1 step not priced$/)
  expect(landed.find(l => l.includes('#3858'))).toMatch(/ \$0\.40$/)
})

// #1585 review. Bugs it catches: at 24 columns, the narrowest pane, a card's `$4.10 + 1 step not priced` (25 columns)
// was cut on its line under the row, and the head gave the day as `$4.10+` alone, with no count of the steps not priced.
test('the pane at 24 columns: the day\'s and a card\'s gap are given whole, never cut', () => {
  const gap = { usd: null, usdKnown: 4.1, notPriced: 1 }
  const lines = paneModel(board({ belt: [{ ...BELT[1], ...gap }], cost: { today: 4.5, todayLeftOut: 2 } }), 24, 0).map(plain)
  for (const l of lines) expect(cols(l)).toBeLessThanOrEqual(24)
  // The matrix has no room for its Cost column at this width: each line under the head and the row gives it whole.
  expect(lines).toContainEqual(expect.stringMatching(/^ *\$4\.50 \+ 2 not priced$/))
  expect(lines).toContainEqual(expect.stringMatching(/^ *\$4\.10 \+ 1 not priced$/))
})

// #1585 review (E30). Bug it catches: at 24 columns ` /units  buildbox` and `$4.50+` need 25 columns, so spread()
// cut the head to ` /units  buildb…` for the dollars. The head keeps the label and the host whole, and the day's
// dollars go on the line under it: with the gap, and alone when there is none (`$4.50` beside a host of 10 columns).
test('the pane at 24 columns: the head keeps the host whole, the day\'s dollars on the line under it', () => {
  for (const [host, cost, under] of [['buildbox', { today: 4.5, todayLeftOut: 2 }, /^ \$4\.50 \+ 2 not priced$/], ['buildbox-1', { today: 4.5 }, /^ \$4\.50$/]] as const) {
    const lines = paneModel(board({ cost }, { host }), 24, 0).map(plain)
    expect(lines[0], `the head at 24 columns, host ${host}, cost ${JSON.stringify(cost)}`).toBe(` /units  ${host}`)
    expect(lines[1], `the line under the head, host ${host}, cost ${JSON.stringify(cost)}`).toMatch(under)
  }
})

// #1585 review (E13). Bug it catches: at 24 columns the matrix row of `#3864` with `~$4.12` needs 26 columns, so its
// Cost was cut, and a card with no gap had no line under its row to give it whole; the Landed table cut its Cost column
// the same way. With no room for the column, each card's dollars go on the line under its row.
test('the pane at 24 columns: a card\'s estimated dollars, on the belt and landed, are given whole on a line under its row', () => {
  const est = { usd: 4.12, usdKnown: 4.12, notPriced: 0, estimate: true }
  const lines = paneModel(board({ belt: [{ ...BELT[1], ...est }], landed: [{ ...LANDED[0], ...est }] }), 24, 0).map(plain)
  for (const l of lines) expect(cols(l), `line "${l}" at 24 columns`).toBeLessThanOrEqual(24)
  for (const id of ['#3864', '#3862']) {
    const at = lines.findIndex(l => l.includes(id))
    expect(lines[at + 1], `the line under the row of ${id}: ${lines.join(' | ')}`).toMatch(/^ +~\$4\.12$/)
  }
})

// #1585 review. Bugs it catches: at 40 columns the full view's head, `today $4.50 + 2 steps not priced  ● buildbox`
// (44 columns), was too wide for spread(), which dropped the day's dollars; a belt or landed row whose times or verdict
// and the card's known dollars and gap were too wide lost the card's cost the same way. The head keeps the day's
// dollars, as `$4.50+` beside CONVEYOR whole, and the gap in full on the line under it; a row gives `$4.10+`, and the
// dollars and the gap in full on a line under it.
// #1585 review (E22). Bug it also catches: a row took the widest cost form spread() kept, which cut the left to make
// room: the landed row `GO r1  $4.10 + 1 step not priced` (32 columns) left 6 for the time, check mark and issue, so
// `#3862` was cut; at 45 columns the belt row's times and `$4.10 + 1 step not priced` (42 columns) left 1 for `#3864`.
// Each row keeps its issue whole, with the short form of its cost beside it.
test('the full view at 40 columns: a step not priced keeps the day\'s spend, each card\'s dollars and issue, the gap in full', () => {
  const gap = { usd: null, usdKnown: 4.1, notPriced: 1 }
  const s = board({ belt: [{ ...BELT[1], ...TIMES, ...gap }], landed: [{ ...LANDED[0], ...gap, rounds: [{ round: 1, verdict: 'GO' }] }], cost: { today: 4.5, todayLeftOut: 2 } })
  const text = tableText(s, 40)
  expect(text.split('\n').filter(l => cols(l) > 40)).toEqual([])
  // The head keeps CONVEYOR whole: the day's short form beside it, its known dollars and gap whole on the line under it.
  expect(text.split('\n').slice(0, 2)).toEqual([expect.stringMatching(/^CONVEYOR +today \$4\.50\+  ● buildbox$/), expect.stringMatching(/^ +\$4\.50 \+ 2 steps not priced$/)])
  // Each section has one card: its row is the line after the heading.
  const rows = (t: string, name: string) => section(t, name).split('\n').slice(1, 3)
  const under = expect.stringMatching(/^ +\$4\.10 \+ 1 step not priced$/)
  expect(rows(text, 'ON THE BELT')).toEqual([expect.stringMatching(/^ #3864 .* \$4\.10\+$/), under])
  expect(rows(tableText(s, 45), 'ON THE BELT')).toEqual([expect.stringMatching(/^ #3864 .* \$4\.10\+$/), under])
  expect(rows(text, 'LANDED TODAY')).toEqual([expect.stringMatching(/ ✓ #3862 .*GO r1  \$4\.10\+$/), under])
})

// #1585 review. Bug it catches: the head took the widest day's cost that fit the line on its own, so at 42 columns
// `today $4.50 + 2 steps not priced` left 8 columns for `CONVEYOR · bookstore paused`, and the paused loop did not show.
// The loop's state stays whole beside the day's short form; the day's known dollars and gap go on the line under it.
test('the head at 42 columns keeps a paused loop whole beside a day with steps not priced', () => {
  const lines = tableText(board({ health: { loop: true, state: 'paused' }, cost: { today: 4.5, todayLeftOut: 2 } }), 42).split('\n')
  expect(lines.slice(0, 2), `the head at 42 columns: ${lines.slice(0, 2).join(' | ')}`)
    .toEqual([expect.stringMatching(/^CONVEYOR · bookstore paused +today \$4\.50\+$/), expect.stringMatching(/^ +\$4\.50 \+ 2 steps not priced$/)])
})
// #1585 review. Bug it catches: when not even the short form (`today $4.50+`) fit beside a long paused loop, the head
// kept it there anyway, and `CONVEYOR · conveyor-belt paused` (31 columns) was cut to 26 at 40 columns. The loop stays
// whole; the day's dollars go on a line of their own under it.
test('the head at 40 columns moves the day under a paused loop that leaves no room for it', () => {
  const lines = tableText(state(fetched([['conveyor-belt', snapshot({ health: { loop: true, state: 'paused' }, cost: { today: 4.5, todayLeftOut: 2 } })]])), 40).split('\n')
  expect(lines.slice(0, 2).map(l => l.trimEnd()), `the head at 40 columns: ${lines.slice(0, 2).join(' | ')}`)
    .toEqual(['CONVEYOR · conveyor-belt paused', expect.stringMatching(/^ +today \$4\.50 \+ 2 steps not priced$/)])
})

// Issue 603. Bug it catches: on a wide pane the title column kept a width of its own (or sat before the steps) and
// did not take the row's free width after Cost; on a pane that leaves under 6 columns after Cost, a cut stub of a
// title (or of its header) was drawn.
test('the matrix title fills the free width after Cost at 100 columns, and is left out with under 6 columns free', () => {
  const long = { ...BELT[0], title: 'Rebuild the workflow dashboard for Conveyor so that every lane, slot and step reads at a glance' }
  const s = board({ belt: [long, BELT[1]] })
  const wide = section(paneModel(s, 100, 0).map(plain).join('\n'), 'BUILD MATRIX').split('\n')
  expect(wide[1]).toMatch(/^ID +B R F T L P +Age +Cost  Title$/)
  expect(wide[2]).toMatch(/^#3863 +▶ · · · · · +\S+ +–  Rebuild the workflow dashboard for Conveyor so[^]*…$/)
  expect(cols(wide[2])).toBe(100)
  expect(wide[3]).toMatch(/\$1\.25  Rebuild \/units for Conveyor$/)
  // The width that leaves 5 columns after Cost and its two-column gap: Age is still there, the title is not.
  const w = cols(wide[1]) - cols('  Title') + 2 + 5
  const narrow = section(paneModel(s, w, 0).map(plain).join('\n'), 'BUILD MATRIX').split('\n')
  expect(narrow[1]).toMatch(/^ID +B R F T L P +Age +Cost$/)
  expect(narrow[2]).toMatch(/^#3863 +▶ · · · · · +\S+ +–$/)
  expect(narrow[3]).toMatch(/^#3864 +✓ ▶ · · · · +\S+ +\$1\.25$/)
  // One column more leaves 6, and the title is back.
  expect(section(paneModel(s, w + 1, 0).map(plain).join('\n'), 'BUILD MATRIX').split('\n')[1]).toMatch(/Cost  Title$/)
})

// Issue 1372. Bugs it catches: a card with no issue showed its whole name (with the project's name before it) as its
// ID, so the ID column grew past 12 columns and pushed the step columns, Age and Cost off the pane; the project's name
// was said again in a row of its own matrix; WORKER ACTIVITY and LANDED TODAY still showed the long name.
test('a card with no issue has a short ID in every table, its whole name moves to the matrix Title, and no row repeats the project name', () => {
  const red = { issue: 0, name: 'Main is red (fedcba9876543210)', title: '', card: 'c20261122T164516-bookstore-0' }
  const other = { ...BELT[0], issue: 0, name: '', title: 'Tidy the logo copy', card: 'c20261122T165000-bookstore-77' }
  const landedRed = { ...LANDED[0], issue: 0, name: 'Main is red (0123456789abcdef)', card: 'c20261122T160000-bookstore-0' }
  const s = board({ belt: [{ ...BELT[1], ...red }, other, BELT[0]], landed: [landedRed] })
  for (const w of [60, 100]) {
    const rows = section(paneModel(s, w, 0).map(plain).join('\n'), 'BUILD MATRIX').split('\n')
    const head = rows[1] ?? ''
    expect(head, `matrix head at ${w} columns`).toMatch(/^ID +B R F T L P +Age +Cost  Title$/)
    // The ID column ends where the first step column starts.
    const idW = head.indexOf('B') - 2
    expect(idW, `ID column width at ${w} columns`).toBeLessThanOrEqual(12)
    const [redRow = '', otherRow = '', issueRow = ''] = rows.slice(2, 5)
    expect(redRow.slice(0, idW).trim(), `main-red ID at ${w} columns`).toBe('red fedcba9')
    expect(redRow, `main-red row at ${w} columns`).toMatch(/^red fedcba9 +✓ ▶ · · · · +\S+ +\$1\.25  Main is red \(fedcba98/)
    // The title is cut to fit as any title is: whole at 100 columns.
    if (w === 100) expect(redRow, 'main-red name whole at 100 columns').toContain('Main is red (fedcba9876543210)')
    expect(otherRow, `other row at ${w} columns`).toMatch(/^card 77 +▶ · · · · · +\S+ +–  Tidy the logo copy/)
    expect(issueRow.startsWith('#3863'), `issue row at ${w} columns`).toBe(true)
    // Every step column of every row sits at the head's column, whole and in its own place.
    for (const r of [redRow, otherRow, issueRow]) expect(r.slice(idW + 2, idW + 13), `steps of "${r}"`).toMatch(/^[✓▶✗·] [✓▶✗·] [✓▶✗·] [✓▶✗·] [✓▶✗·] [✓▶✗·]$/)
    for (const l of rows) expect(l.startsWith('bookstore'), `matrix line "${l}" repeats the project name`).toBe(false)
  }
  const wide = section(paneModel(s, 100, 0).map(plain).join('\n'), 'BUILD MATRIX')
  expect(wide, 'the project name is in the matrix heading only').not.toMatch(/\nbookstore /)
  const activity = activityModel(s, s.snap!, 62, 0).map(plain)
  expect(activity[1], 'WORKER ACTIVITY main-red row').toMatch(/^◐ red fedcba9  /)
  expect(activity[2], 'WORKER ACTIVITY other row').toMatch(/^◐ card 77  /)
  expect(section(paneModel(s, 100, 0).map(plain).join('\n'), 'LANDED TODAY'), 'LANDED TODAY').toMatch(/\n\S+ [AP]M +red 0123456 +/)
})

// Issue 1372. Bug it catches: a card id of a card with no issue ends in `-0` (a Foreman order, a Tests page card); the
// suffix was read as a card number, so every such card showed `card 0` and no table told two of them apart by a number.
test('a card with no issue whose card id ends in -0 has the ID `card`, not `card 0`', () => {
  const zero = { ...BELT[0], issue: 0, name: '', title: 'Order from the Foreman', card: 'c20261122T165000-bookstore-0' }
  const s = board({ belt: [zero], landed: [] })
  expect(activityModel(s, s.snap!, 62, 0).map(plain)[1], 'WORKER ACTIVITY row of a card id ending in -0').toMatch(/^◐ card  /)
  expect(section(paneModel(s, 100, 0).map(plain).join('\n'), 'BUILD MATRIX').split('\n')[2], 'matrix row of a card id ending in -0').toMatch(/^card  /)
})

// Issue 1582. Bug it catches: a card with no issue read `card` (a review follow-up or a split part ends its card id in
// -0, so no number), and its Title began with "Review follow-up of #N", so the finding was cut off: no row said which
// card it was. Each table and the toasts name it by its kind and parent, and its Title is the work itself (a finding on
// a file with no extension is cut to its base name too).
test('a review follow-up, a split part, a main-red fix card and a Tests page card are named by kind and parent in every table, the Title is the work, an issue card is unchanged', () => {
  const fu = { issue: 0, name: 'Review follow-up of #1571', title: '[P2] [E1] conveyor/lib/auto.sh:239 The build host can stop the run', card: 'c20261123T100000-bookstore-0' }
  const split = { issue: 0, name: 'Split part of #1453', title: '[P3][cleanup] conveyor/lanes/research-bash:526 One repeated line is not caught', card: 'c20261123T100100-bookstore-0' }
  // The title is the one the snapshot gives (conveyor/tests/mainred.test.sh: name and title of a fix card): it lists the failing cases.
  const red = { issue: 0, name: 'Main is red (19e3b6e4f5a6)', title: 'Main is red: a.test: one, c.test, b.test: flaky', card: 'c20261123T100200-bookstore-0' }
  const tp = { issue: 0, name: 'Tests page: conveyor/tests/snapexec.test.sh', title: 'snapexec: one snapshot starts a run', card: 'c20261123T100300-bookstore-0' }
  const issue = { ...BELT[1], issue: 1524, card: 'c20261123T100400-bookstore-1524', title: 'Health lists a working build' }
  const belt = [...[fu, split, red, tp].map(x => ({ ...BELT[0], ...x })), issue]
  const s = board({ belt, landed: [{ ...LANDED[0], ...fu, card: 'c20261123T090000-bookstore-0', time: ago(5) }],
    needsYou: { waiting: [], blocked: [{ ...BLOCKED, ...split, reason: 'review 3 was NO-GO' }] } })
  const rows = section(paneModel(s, 100, 0).map(plain).join('\n'), 'BUILD MATRIX').split('\n')
  const head = rows[1] ?? ''
  const idW = head.indexOf('B') - 2
  // No ID passes the ID column's width (#1414), and each row carries its kind and parent.
  expect(idW, `ID column width in "${head}"`).toBeLessThanOrEqual(12)
  const ids = rows.slice(2, 7).map(r => r.slice(0, idW).trim())
  expect(ids).toEqual(['fu #1571', 'split #1453', 'red 19e3b6e', 'test snapexe', '#1524'])
  expect(rows[2]).toMatch(/ {2}auto\.sh:239 The build host can stop the run$/)
  expect(rows[3]).toMatch(/ {2}research-bash:526 One repeated line is not caught$/)
  expect(rows[4], 'main-red Title is its name, not the failing cases').toMatch(/ {2}Main is red \(19e3b6e4f5a6\)$/)
  expect(rows[5]).toMatch(/ {2}snapexec: one snapshot starts a run$/)
  expect(rows[6]).toMatch(/ {2}Health lists a working build$/)
  expect(rows[2], 'no tag, prefix or folder in the Title').not.toMatch(/\[P2\]|\[E1\]|\[cleanup\]|Review follow-up|conveyor\/l/)
  const activity = activityModel(s, s.snap!, 62, 0).map(plain)
  expect(activity.slice(1, 6).map(l => l.slice(2).split('  ')[0])).toEqual(['fu #1571', 'split #1453', 'red 19e3b6e', 'test snapexe', '#1524'])
  expect(section(paneModel(s, 100, 0).map(plain).join('\n'), 'LANDED TODAY'), 'LANDED TODAY').toMatch(/\n\S+ [AP]M +fu #1571 +/)
  const needs = tableText(s, 100)
  expect(needs, 'NEEDS YOU').toMatch(/split #1453 research-bash:526 One repeated line is not caught/)
  expect(needs, 'no table says "Split part of" or "Review follow-up of"').not.toMatch(/Split part of|Review follow-up of/)
  expect(toasts(seenOf(board().snap!), seenOf(s.snap!))).toEqual(['split #1453 is blocked', 'fu #1571 landed'])
})

// Issue 497. Bugs it catches: the pane said "0 queued" and "the queue is empty" while issues waited on other cards,
// and each card took four lines.
test('the pane from two projects with 4 cards building, 5 waiting and 20 landed: the count band, a matrix row a card, the pick order', () => {
  const card = (repo: string, n: number) => ({ ...BELT[0], card: `c-${repo}-${n}`, issue: n, title: `Card ${n}` })
  const waits = [489, 490, 491, 492, 493].map(n => ({ issue: n, title: `Waits ${n}`, waitsFor: n === 489 ? [485, 486, 487, 488] : [n - 1] }))
  const landed = Array.from({ length: 20 }, (_, i) => ({ ...LANDED[0], card: `c-l${i}`, issue: 400 + i, time: ago(i), rounds: [{ round: 2, verdict: 'GO', counts: null, sec: 60, fixed: false }] }))
  const health = (building: number) => ({ loop: true, state: 'running', building, waitingCount: 0, builderCap: 4 })
  const s = state(fetched([
    ['bookstore', snapshot({ belt: [485, 486, 487].map(n => card('bookstore', n)), queue: { next: [], waiting: waits }, landed, health: health(3) })],
    ['gadgetlab', snapshot({ belt: [card('gadgetlab', 7)], health: health(1) })],
  ]))
  const lines = paneModel(s, 72, 0).map(plain)
  const text = lines.join('\n')
  expect(text).toContain('\n4 ON BELT · 0 READY · 5 WAITING · 0 NEEDS YOU\n')
  expect(text).toMatch(/\nBUILD MATRIX +bookstore · 3\/4 slots\n/)
  expect(text).toMatch(/\nBUILD MATRIX +gadgetlab · 1\/4 slots\n/)
  // One row a card, ▶ in the Build column (the first of the six marks).
  const rows = lines.filter(l => /^#\d+ /.test(l) && l.includes('Card '))
  expect(rows.map(l => l.split(/ +/)[0])).toEqual(['#485', '#486', '#487', '#7'])
  for (const l of rows) expect(l).toMatch(/ ▶ · · · · · /)
  expect(text).toMatch(/\nPICK ORDER +0 ready\nWaiting +Requires\n#489 +#485 +#486 +#487 +#488\n#490 +#489\n/)
  expect(text).toMatch(/\nLANDED TODAY · 20 +5 most recent of 20\n[^]*\n\S+ [AP]M +#400 +✓ GO r2 +\S+ +\$4\.21\n/)
})

// Issue 1679. Bug it catches: BUILD MATRIX drew ▶ on the current step of a card that only waits on another card, so
// `4/4 slots` sat above six rows that each showed ▶, and the header did not say how many cards wait.
const matrixOf = (belt: object[], health: object, more: [string, string][] = [], w = 100, repo = 'bookstore') =>
  section(paneModel(state(fetched([[repo, snapshot({ belt, health })], ...more])), w, 0).map(plain).join('\n'), 'BUILD MATRIX').split('\n')
// The engine's track (conveyor/jq/track.jq): the steps before `at` done, `at` now, the rest to do.
const trackAt = (at: number) => ({ steps: STEP_NAMES.map((name, i) => ({ name, state: i < at ? 'done' : i === at ? 'now' : 'todo', sec: null })), at, label: 'x', since: ago(1) })
// A card at a same-file wait, as conveyor/lib/snapshot.sh sends it: step "waiting", its track and waitsOn. #4104 waits
// in Land, #4105 in Build.
const sixCards = (waits: boolean) => [4100, 4101, 4102, 4103, 4104, 4105].map((n, i) => ({ ...BELT[0], card: `c-${n}`, issue: n, title: `Card ${n}`,
  ...(waits && n >= 4104 ? { step: 'waiting', track: trackAt(n === 4104 ? 4 : 0), waitsOn: { card: 'c-4100', issue: 4100, state: 'build' } }
    : { step: ['build', 'review', 'fix', 'tests', 'build', 'build'][i] }) }))
const rowOf = (m: string[], n: number) => m.find(l => l.startsWith(`#${n} `)) ?? ''
const rowsOf = (m: string[]) => m.filter(l => l.startsWith('#'))
test('/units marks the current step of a waiting card ‖, not ▶, and gives the waiting count after the slots', () => {
  const health = { loop: true, state: 'running', building: 4, waitingCount: 2, builderCap: 4 }
  const idle = snapshot({ health: { loop: true, state: 'running', building: 0, waitingCount: 1, builderCap: 2 } })
  const m = matrixOf(sixCards(true), health, [['gadgetlab', idle]])
  const feed = 'feed: 4 working cards (#4100-#4103), 2 at step "waiting" with a track and waitsOn (#4104 in Land, #4105 in Build), health {building 4, waitingCount 2, builderCap 4}; idle gadgetlab waitingCount 1'
  expect(m[0], feed).toMatch(/^BUILD MATRIX +bookstore · 4\/4 slots · 2 waiting$/)
  expect(rowsOf(m), feed).toHaveLength(6)
  for (const n of [4100, 4101, 4102, 4103]) expect(rowOf(m, n), `${feed}: row #${n}`).toMatch(/ ▶ /)
  expect(rowOf(m, 4104), `${feed}: row #4104`).toMatch(/^#\d+ +✓ ✓ ✓ ✓ ‖ · /)
  expect(rowOf(m, 4105), `${feed}: row #4105`).toMatch(/^#\d+ +‖ · · · · · /)
  for (const n of [4104, 4105]) expect(rowOf(m, n), `${feed}: row #${n}`).not.toContain('▶')
  expect(m, feed).toContain('▶ running ‖ waiting · pending ✓ done ✗ failed')
  expect(m, feed).toContain('  gadgetlab 0/2 slots · 1 waiting')
})
// Bug it catches: at a narrow width the waiting count made the header's right side too wide, so the project and its
// slots were dropped whole; the idle line and the legend were cut, the legend's `✗ failed` lost. The waiting parts go
// first. At 40 columns the header's right side has 37, the idle line and the legend 40.
test('/units leaves out the waiting parts that do not fit, so the project, its slots and the legend show whole', () => {
  const idle = snapshot({ health: { loop: true, state: 'running', building: 0, waitingCount: 1, builderCap: 2 } })
  const m = matrixOf(sixCards(true), { loop: true, state: 'running', building: 4, waitingCount: 2, builderCap: 4 }, [['gadgetlab-toolbox', idle]], 40, 'bookstore-shop')
  const feed = 'feed at 40 columns: bookstore-shop health {building 4, waitingCount 2, builderCap 4} (38 columns with the count); idle gadgetlab-toolbox waitingCount 1 (41 with it)'
  expect(m[0], feed).toMatch(/ bookstore-shop · 4\/4 slots$/)
  expect(m, feed).toContain('  gadgetlab-toolbox 0/2 slots')
  expect(m, feed).toContain('▶ running · pending ✓ done ✗ failed')
  expect(rowOf(m, 4105), `${feed}: row #4105`).toMatch(/^#\d+ +‖ /)
})
// Bug it catches: while the snapshot is behind, the header took the slots from the loop's count now (recordsNow) but
// the waiting count from the old snapshot, so a card that had stopped waiting was still counted.
test('/units takes the loop\'s waiting count now while the snapshot is behind', () => {
  const s = board({ belt: sixCards(true), recordsNewer: true, recordsNow: { building: 5, waitingCount: 1 }, health: { loop: true, state: 'running', building: 4, waitingCount: 2, builderCap: 6 } })
  expect(matrixHead(s), 'feed: recordsNow {building 5, waitingCount 1}, health {building 4, waitingCount 2, builderCap 6}').toMatch(/ bookstore · 5\/6 slots · 1 waiting$/)
})
// Bug it catches: a fresh count of 0 (the last waiting card resumed) taken as no count, so the header fell back to the
// old snapshot's `2 waiting` (`||` in place of `??` in parseRecord).
test('/units shows no waiting count when the loop\'s count now is 0 and the snapshot that is behind had 2', () => {
  const s = board({ belt: sixCards(true), recordsNewer: true, recordsNow: { building: 5, waitingCount: 0 }, health: { loop: true, state: 'running', building: 4, waitingCount: 2, builderCap: 6 } })
  expect(matrixHead(s), 'feed: recordsNow {building 5, waitingCount 0}, health {building 4, waitingCount 2, builderCap 6}').toMatch(/ bookstore · 5\/6 slots$/)
})
// Bug it catches: a view that showed `· 0 waiting`, or a wait mark on a card with no waitsOn.
test('/units shows the matrix as before when no card waits', () => {
  const m = matrixOf(sixCards(false), { loop: true, state: 'running', building: 6, waitingCount: 0, builderCap: 6 })
  const feed = 'feed: 6 cards with no waitsOn, health {building 6, waitingCount 0, builderCap 6}'
  expect(m[0], feed).toMatch(/^BUILD MATRIX +bookstore · 6\/6 slots$/)
  expect(rowsOf(m), feed).toHaveLength(6)
  for (const l of rowsOf(m)) expect(l, feed).toMatch(/ ▶ /)
  expect(rowsOf(m).join('\n'), feed).not.toContain('‖')
})
// Bug it catches: a snapshot of an older engine (no waitsOn, no waitingCount) drew a waiting count nobody knows.
test('/units shows the matrix as before for a snapshot with no waitsOn and no waitingCount', () => {
  const m = matrixOf(sixCards(false), { loop: true, state: 'running', building: 6, builderCap: 6 })
  const feed = 'feed: 6 cards with no waitsOn, health {building 6, builderCap 6} with no waitingCount'
  expect(m[0], feed).toMatch(/^BUILD MATRIX +bookstore · 6\/6 slots$/)
  expect(rowsOf(m), feed).toHaveLength(6)
  for (const l of rowsOf(m)) expect(l, feed).toMatch(/ ▶ /)
})

// Issue 830. Bug it catches: the snapshot keeps only the newest 20 landed rows (and older ones still on the belt), and
// /units counted those rows, so a day of 156 landed cards read "20" and "5 most recent of 20". The count is the sum of
// every project's landedCount. An older snapshot with no landedCount counts its rows.
test('LANDED TODAY counts every card landed today (landedCount, summed across projects), not the snapshot rows; without it, the rows', () => {
  const landed = Array.from({ length: 20 }, (_, i) => ({ ...LANDED[0], card: `c-l${i}`, issue: 400 + i, time: ago(i) }))
  const other = Array.from({ length: 3 }, (_, i) => ({ ...LANDED[0], card: `c-g${i}`, issue: 450 + i, time: ago(30 + i) }))
  const all = state(fetched([
    ['bookstore', snapshot({ landed, landedCount: 100, cost: { today: 12 } })],
    ['gadgetlab', snapshot({ landed: other, landedCount: 56, cost: { today: 8 } })],
  ]))
  expect(paneModel(all, 72, 0).map(plain).join('\n')).toMatch(/\nLANDED TODAY · 156 +5 most recent of 156\n/)
  const full = section(tableText(all, 80), 'LANDED TODAY').split('\n')
  expect(full[0]).toBe('LANDED TODAY  156 · $20.00')
  expect(full.filter(l => / ✓ .*#4\d\d /.test(l))).toHaveLength(23)
  expect(full.at(-1)).toBe('  +133 more')
  const old = board({ landed, cost: { today: 20 } })
  expect(paneModel(old, 72, 0).map(plain).join('\n')).toMatch(/\nLANDED TODAY · 20 +5 most recent of 20\n/)
  const oldFull = section(tableText(old, 80), 'LANDED TODAY').split('\n')
  expect(oldFull[0]).toBe('LANDED TODAY  20 · $20.00')
  expect(oldFull.join('\n')).not.toContain('more')
})

// Issue 508. Bug it catches: at 60 columns a Pick order row with four dependencies, each with its state, was cut at the
// width and lost #488, the last issue it waits for.
test('a Pick order row too long for the pane wraps at each issue it waits for, and loses none', () => {
  const waiting = [{ issue: 489, title: 'Waits', waitsFor: [485, 486, 487, 488], waitsOn: [485, 486, 487, 488].map(n => ({ issue: n, state: 'building' })) }]
  const lines = paneModel(board({ queue: { next: [], waiting } }), 60, 0).map(plain)
  const at = lines.indexOf(lines.find(l => l.startsWith('#489 '))!)
  expect(lines.slice(at, at + 3)).toEqual(['#489     #485 (building)  #486 (building)  #487 (building)', '         #488 (building)', ''])
  for (const l of lines) expect(cols(l)).toBeLessThanOrEqual(60)
})

// Issue 497. Bug it catches: a forced issue, which the snapshot lists both in the pick order and (marked forced) among
// the waiting, was counted READY and WAITING at once, and listed in Pick order as waiting.
test('a forced issue counts as ready only, and is not in Pick order', () => {
  const waiting = [{ issue: 3, title: 'Forced', waitsFor: [2], forced: true }, { issue: 4, title: 'Waits', waitsFor: [2], forced: false }]
  const text = paneModel(board({ queue: { next: [{ issue: 3, title: 'Forced', waitsFor: [2], forced: true }], waiting } }), 72, 0).map(plain).join('\n')
  expect(text).toContain('\n0 ON BELT · 1 READY · 1 WAITING · 0 NEEDS YOU\n')
  expect(text).toMatch(/\nPICK ORDER +1 ready\n 1 #3 Forced +P3\nWaiting +Requires\n#4 +#2\n\n/)
})

// Issue 650. Bug it catches: the parts of a parent issue (its GitHub sub-issues) showed as rows of their own, with no
// word of the parent, its parts done or the part in flight; a card in flight did not name the parent it is a part of.
test('a parent with three parts, one done, one in flight and one waiting, is one Pick order entry, and its card names it', () => {
  const umbrellas = [{ issue: 647, title: 'Parts of a large piece of work', parts: ['#635', '#636', '#637'], done: 1, all: 3, inFlight: [636] }]
  // #701 is a part of a parent the snapshot does not list: it keeps its own row, so it is not lost.
  const waiting = [{ issue: 637, title: 'Third part', waitsFor: [636], umbrella: 647 }, { issue: 700, title: 'No part', waitsFor: [699] },
    { issue: 701, title: 'Part of an unlisted parent', waitsFor: [700], umbrella: 900 }]
  const s = board({ belt: [{ ...BELT[0], issue: 636, card: 'c3-636', title: 'Second part', umbrella: 647 }], queue: { next: [], waiting }, open: { umbrellas } })
  const text = paneModel(s, 72, 0).map(plain).join('\n')
  expect(text).toMatch(/\nPICK ORDER +0 ready\nParent +Parts\n#647 +1 of 3 done · #636 in flight  Parts of a large piece of work\nWaiting +Requires\n#700 +#699\n#701 +#700\n\n/)
  expect(text).not.toMatch(/\n#637 /)
  expect(text).toMatch(/\nBUILD MATRIX [^]*\n#636 of #647  ▶ /)
  expect(text).toMatch(/\nWORKER ACTIVITY\n\S+ #636 of #647  build/)
})

// Issue 650. Bug it catches: each part of a parent counted as an issue of its own in the head's READY and WAITING.
test('the parts of one parent count as one in READY, and not in WAITING while a part is ready', () => {
  const umbrellas = [{ issue: 650, title: 'Parent', parts: ['#651', '#652', '#653'], done: 0, all: 3, inFlight: [] }]
  const next = [651, 652].map(n => ({ issue: n, title: `Part ${n}`, priority: 'P2', followup: false, retried: false, umbrella: 650 }))
  const s = board({ queue: { next, waiting: [{ issue: 653, title: 'Part 653', waitsFor: [651], umbrella: 650 }] }, open: { umbrellas } })
  const text = paneModel(s, 72, 0).map(plain).join('\n')
  expect(text).toContain('\n0 ON BELT · 1 READY · 0 WAITING · 0 NEEDS YOU\n')
  expect(text).toMatch(/\nPICK ORDER +2 ready\n 1 #651 Part 651 +P2\n 2 #652 Part 652 +P2\nParent +Parts\n#650 +0 of 3 done  Parent\n\n/)
})

// Issue 497. Bug it catches: a card's step marks did not follow its track: a done step, a skipped one and the one running.
// The engine's track gives Fix as skipped once Test runs after a GO (conveyor/jq/track.jq), and the matrix showed a dash.
test('a card with Build and Review done and Test running shows ✓ ✓ · ▶ in Build, Review, Fix and Test', () => {
  const s = board({ belt: [{ ...BELT[0], ...TIMES, track: track('++->..', 'testing') }] })
  expect(paneModel(s, 72, 0).map(plain).find(l => l.startsWith('#3863'))).toMatch(/ ✓ ✓ · ▶ · · /)
})

// Issue 497. Bug it catches: the live command showed the whole machine path of the card's worktree ("now Bash: cd
// /mnt/...") and wrapped the pane.
test('a live command in the card\'s worktree reads "worktree", a home path its last part, and no absolute path is in the pane', () => {
  const tree = '/r/home/cards/c3-3863'
  const live = (action: string) => board({ belt: [{ ...BELT[0], live: { action, turns: 2, lastOutputAt: ago(0) } }] })
  const text = (action: string) => paneModel(live(action), 72, 0).map(plain).join('\n')
  expect(text(`Bash: cd ${tree}/x && git add -A`)).toMatch(/\n◐ #3863  cd worktree\/x && git add -A +Bash · \S+ [AP]M\n/)
  // No path of two parts or more from the root or home (the head's `/units` label is one part).
  expect(text(`Bash: cd ${tree}/x && git add -A`)).not.toMatch(/(^|[\s'"=(])~?\/\w+\//m)
  expect(text(`Bash: cd ${tree}/x && git add -A`)).not.toContain('/r/')
  expect(text(`Read: /r/home/.config/conveyor/host.json`)).toMatch(/\n◐ #3863  host\.json +Read · /)
  // Another card's id in a path is not this card's worktree.
  expect(text(`Bash: ls /r/home/cards/c3-38630/y`)).toMatch(/\n◐ #3863  ls y +Bash/)
})

test('a toast names each card that newly needs you or newly landed, never what was there at the first poll', () => {
  const before = seenOf(board({ needsYou: { waiting: [WAITING], blocked: [] }, landed: [LANDED[0]] }).snap!)
  const after = seenOf(board({ needsYou: { waiting: [WAITING], blocked: [BLOCKED] }, landed: LANDED }).snap!)
  expect(toasts(null, before)).toEqual([])
  expect(toasts(before, before)).toEqual([])
  expect(toasts(before, after)).toEqual(['#3850 is blocked', '#3860 landed', '#3858 closed as already fixed'])
  expect(toasts(after, seenOf(board({ needsYou: { waiting: [{ ...WAITING, card: 'c9-3999', issue: 3999 }], blocked: [] } }).snap!))).toEqual(['#3999 needs your yes'])
})

// the limit was looked for at the top of the file, where the Board never puts it, so it was never read.
test('the usage limit is read from limit.json\'s limit, where the Board puts it, and a file without one gives none', () => {
  const data = (limit: unknown) => JSON.stringify({ limit })
  expect(parseLimit(data({ usedPct: 41.5, resetsAt: '2026-11-12T00:00:00Z' }))).toEqual({ pct: 41.5, resetsAt: Date.UTC(2026, 10, 12) })
  expect(parseLimit(data(null))).toBe(null)
  expect(parseLimit(data({ usedPct: '41' }))).toBe(null)
  expect(parseLimit('not a limit file')).toBe(null)
  expect(parseLimit('null')).toBe(null)
})

test('the seat is main (where the Foreman runs) or a worker worktree; no folder name makes a seat', () => {
  expect(seatFromGit('/r/main/.git\n/r/main/.git\n/r/main\n')).toEqual({ seat: 'main', main: '/r/main' })
  expect(seatFromGit('/r/main/.git/worktrees/c\n/r/main/.git\n/r/ws/Research\n')).toEqual({ seat: 'worker', main: '/r/main' })
  expect(seatFromGit('/r/main/.git/worktrees/u\n/r/main/.git\n/r/cards/c1-3864\n')).toEqual({ seat: 'worker', main: '/r/main' })
  expect(seatFromGit('')).toBe(null)
})

// Issue 176: the test map's line in /units and the pane, from the fetch's `testmap` line. Bug it catches: a map's run of
// many minutes showed nothing, and a map made, not made, off or failed all looked alike (no line).
const mapped = (json: object) => {
  const text = fetched([['bookstore', snapshot()]], `testmap\t${JSON.stringify(json)}\nhost\tbuildbox\tssh\t0`)
  return state(text, { testMap: parseFetch(text)?.testMap })
}
const mapLine = (lines: string[]) => lines.find(l => l.startsWith('Test map')) ?? ''
test('while the map is made, a bar with the test files run of how many and the time so far; a narrow view keeps the bar', () => {
  const s = mapped({ state: 'running', done: 12, of: 40, started: NOW / 1000 - 180 })
  const line = mapLine(tableText(s, 62).split('\n'))
  expect(line).toMatch(/^Test map: 12 of 40 test files · 3m +▰▰▰▱▱▱▱▱▱▱$/)
  expect(cols(line)).toBe(62)
  // In the pane the line is under Machine details, so it is drawn with that opened.
  expect(mapLine(paneModel(s, 62, 0, true).map(plain))).toBe(line)
  const narrow = mapLine(paneModel(s, 30, 0, true).map(plain))
  expect(narrow).toMatch(/^Test map: .*… +▰▰▰▱▱▱▱▱▱▱$/)
  expect(cols(narrow)).toBe(30)
})

test('with no run, one line with the map\'s state: made, not made yet, off, or failed with its reason; it fits a narrow pane', () => {
  const lines = (json: object, w = 62) => mapLine(paneModel(mapped(json), w, 0, true).map(plain))
  expect(lines({ state: 'made', sources: 120, tests: 40, age: 3 })).toBe('Test map: 120 source, 40 test files · 3 commits behind main')
  expect(lines({ state: 'made', sources: 1, tests: 1, age: 0 })).toBe('Test map: 1 source, 1 test file · up to date with main')
  expect(lines({ state: 'made', sources: 7, tests: 2, age: null })).toBe('Test map: 7 source, 2 test files')
  expect(lines({ state: 'none' })).toBe('Test map: not made yet · run /conveyor-belt:setup to make it')
  expect(lines({ state: 'off' })).toBe('Test map: off')
  expect(lines({ state: 'failed', why: 'the whole test on main failed' })).toBe('Test map: failed: the whole test on main failed')
  expect(mapLine(tableText(mapped({ state: 'off' }), 62).split('\n'))).toBe('Test map: off')
  const narrow = lines({ state: 'none' }, 30)
  expect(narrow.endsWith('…') && cols(narrow) === 30).toBe(true)
  // With no board read, the line is still shown; a fetch with no testmap line (no project settings) shows none.
  expect(tableText({ ...mapped({ state: 'off' }), snap: null, note: 'units: the Conveyor snapshot cannot be read (x)' }, 62)).toContain('\nTest map: off')
  expect(tableText(board(), 62)).not.toContain('Test map')
})

// Issue 179: the old-engine line, from the fetch's `engine` line, in /units and the pane. Bugs it catches: a project
// stayed on an old engine for hours and /units said nothing; or the line was cut at the pane's width, so the command
// that takes the newest commit could not be copied.
test('an old engine: the whole line, wrapped between words at the width, the command at its end never cut', () => {
  const cmd = 'cd /r/projects/bookstore && bash /r/home/.local/share/conveyor/versions/0123456789abcdef0123456789abcdef01234567/conveyor/conveyor.sh take'
  const line = `Conveyor runs an old engine here: commit 0543507, and the plugin's main is at 9f8e7d6 · last take that worked: 2026-11-16T05:10:00Z · last failure: conveyor: the plugin's main could not be read from its remote · to take it, run: ${cmd}`
  const text = fetched([['bookstore', snapshot()]], `engine\t${line}\nhost\tbuildbox\tssh\t0`)
  const s = state(text, { engine: parseFetch(text)?.engine })
  for (const lines of [tableText(s, 62).split('\n'), paneModel(s, 62, 0).map(plain)]) {
    const at = lines.findIndex(l => l.startsWith('Conveyor runs an old engine'))
    expect(at).toBeGreaterThan(-1)
    const end = lines.findIndex((l, i) => i > at && !l.startsWith('  '))
    const got = lines.slice(at, end)
    expect(got.join(' ').replace(/ {2,}/g, ' ')).toBe(line)
    // Only a word wider than the view (the engine's path) passes the width.
    expect(got.every(l => cols(l) <= 62 || !l.trim().includes(' '))).toBe(true)
  }
  // A fetch with no engine line (the project runs the newest commit) shows none.
  expect(tableText(board(), 62)).not.toContain('old engine')
})

// Issue 609: WORKER ACTIVITY, a card in its Test step. Bugs it catches: the row gave only the short test command, so
// the owner could not see how far the tests were; the bar was not filled to the share done, the count or the failed
// count was missing, the row passed the pane's width, or the row changed for a card with no test counts yet or in
// another step.
test('WORKER ACTIVITY: a card in its Test step shows a bar of its tests done of all, the count and the failed count', () => {
  const live = { action: 'Bash: npm test', turns: null, lastOutputAt: ago(0) }
  const s = board({ belt: [
    { ...BELT[1], card: 'c8-3865', issue: 3865, step: 'tests', live, track: track('+++>..', 'tests', { tests: { done: 72, of: 89, failed: 3 } }) },
    { ...BELT[1], card: 'c9-3866', issue: 3866, step: 'tests', live, track: track('+++>..', 'tests') },
    // A card in its Build step whose track has test counts too: not in its Test step, so its row keeps its step.
    { ...BELT[0], track: track('>.....', 'build', { tests: { done: 5, of: 9, failed: 1 } }) },
    { ...BELT[1], card: 'c10-3867', issue: 3867, step: 'tests', live, track: track('+++>..', 'tests', { tests: { done: 45, of: 90, failed: 0 } }) },
  ] })
  const rows = (w: number) => activityModel(s, s.snap!, w, 0).map(plain)
  const right = (tool: string, at: number) => ` +${tool}${clockOf(NOW - at * 60_000)}$`
  const [, bar, none, other, passing] = rows(62)
  // 72 of 89 is 81%: 8 of the bar's 10 cells filled.
  expect(bar).toMatch(new RegExp(`^◐ #3865  ▰{8}▱{2} 72/89 · 3 failed${right('Bash · ', 3)}`))
  // The rows as they were before the bar: the short command, or the step.
  expect(none).toMatch(new RegExp(`^◐ #3866  npm test${right('Bash · ', 3)}`))
  expect(other).toMatch(new RegExp(`^◐ #3863  build${right('', 3)}`))
  // No failed test: no failed count.
  expect(passing).toMatch(new RegExp(`^◐ #3867  ▰{5}▱{5} 45/90${right('Bash · ', 3)}`))
  for (const l of rows(62)) expect(cols(l)).toBeLessThanOrEqual(62)
  const narrow = rows(30)[1]
  expect(narrow.startsWith('◐ #3865  ▰') && cols(narrow) <= 30).toBe(true)
})

// Issue 1598. Bug it catches: a card that waits for the landing turn showed the engine's live text, "waiting for card
// c20261124T015216-conveyor-belt-0 to land first: ...", cut off at the pane's edge, so no one could tell which card it
// waited for. It names that card by its ID in the tables: `fu #1590` for a review follow-up, `#1533` for an issue,
// `red 19e3b6e` for a main-red fix card; a card id holds none of those. Other live text is unchanged. A card queued
// for the next batch at its claim names the card that has the turn the same way. The live text streams between
// snapshots, so when the turn passes to another card the snapshot's waitsOn can still name the one before: then the
// engine's text stays, not the wrong card's ID.
test('WORKER ACTIVITY and the belt name the card that has the landing turn by its short ID, not its card id', () => {
  const wait = (card: string) => ({ action: `waiting for card ${card} to land first: it has the landing turn, as its batch or its run again of the shared test files lands first`, turns: 0, lastOutputAt: ago(0) })
  const fu = 'c20261124T015216-bookstore-0', red = 'c20261124T015300-bookstore-0'
  const s = board({ belt: [
    { ...BELT[1], card: 'c8-1531', issue: 1531, step: 'land', live: wait(fu), waitsOn: { card: fu, issue: 0, state: 'tests', name: 'Review follow-up of #1590' } },
    { ...BELT[1], card: 'c9-1585', issue: 1585, step: 'land', live: wait('c10-1533'), waitsOn: { card: 'c10-1533', issue: 1533, state: 'tests' } },
    { ...BELT[1], card: 'c11-1589', issue: 1589, step: 'land', live: wait(red), waitsOn: { card: red, issue: 0, state: 'tests', name: 'Main is red (19e3b6e4f5a6)' } },
    // An older snapshot with no waitsOn keeps the engine's text.
    { ...BELT[1], card: 'c12-1592', issue: 1592, step: 'land', live: wait(fu) },
    { ...BELT[1], card: 'c13-1593', issue: 1593, step: 'build', live: { action: `queued for the next batch: card c10-1533 has the landing turn`, turns: 0, lastOutputAt: ago(0) }, waitsOn: { card: 'c10-1533', issue: 1533, state: 'tests' } },
    // The turn passed from c10-1533 to c14-1594 after the snapshot: waitsOn still names c10-1533.
    { ...BELT[1], card: 'c15-1595', issue: 1595, step: 'land', live: wait('c14-1594'), waitsOn: { card: 'c10-1533', issue: 1533, state: 'tests' } },
    // A part of a parent issue: its own ID, `#1596 of #1600`, leaves the wait text the fewest columns.
    { ...BELT[1], card: 'c16-1596', issue: 1596, umbrella: 1600, step: 'build', live: { action: `queued for the next batch: card c10-1533 has the landing turn`, turns: 0, lastOutputAt: ago(0) }, waitsOn: { card: 'c10-1533', issue: 1533, state: 'tests' } },
    { ...BELT[1], card: 'c17-1597', issue: 1597, umbrella: 1600, step: 'land', live: wait('c10-1533'), waitsOn: { card: 'c10-1533', issue: 1533, state: 'tests' } },
    // Parts that wait on a holder with a longer ID, `fu #1590`, in both wait messages.
    { ...BELT[1], card: 'c18-1598', issue: 1598, umbrella: 1600, step: 'land', live: wait(fu), waitsOn: { card: fu, issue: 0, state: 'tests', name: 'Review follow-up of #1590' } },
    { ...BELT[1], card: 'c19-1599', issue: 1599, umbrella: 1600, step: 'build', live: { action: `queued for the next batch: card ${fu} has the landing turn`, turns: 0, lastOutputAt: ago(0) }, waitsOn: { card: fu, issue: 0, state: 'tests', name: 'Review follow-up of #1590' } },
    // A follow-up, `fu #1596`, with no parent to drop, behind the main-red fix in both wait messages.
    { ...BELT[1], card: 'c20-0', issue: 0, name: 'Review follow-up of #1596', step: 'land', live: wait(red), waitsOn: { card: red, issue: 0, state: 'tests', name: 'Main is red (19e3b6e4f5a6)' } },
    { ...BELT[1], card: 'c21-0', issue: 0, name: 'Review follow-up of #1596', step: 'build', live: { action: `queued for the next batch: card ${red} has the landing turn`, turns: 0, lastOutputAt: ago(0) }, waitsOn: { card: red, issue: 0, state: 'tests', name: 'Main is red (19e3b6e4f5a6)' } },
  ] })
  const rows = activityModel(s, s.snap!, 80, 0).map(plain)
  expect(rows[1]).toMatch(/^◐ #1531  fu #1590 lands first \(landing turn\)/)
  expect(rows[2]).toMatch(/^◐ #1585  #1533 lands first \(landing turn\)/)
  expect(rows[3]).toMatch(/^◐ #1589  red 19e3b6e lands first \(landing turn\)/)
  expect(rows[4], 'no waitsOn: the engine text').toMatch(/^◐ #1592  waiting for card c20261124T015216/)
  expect(rows[5], 'queued for the next batch').toMatch(/^◐ #1593  #1533 next batch \(has the landing turn\)/)
  expect(rows[6], 'stale waitsOn: not the card that had the turn before').toMatch(/^◐ #1595  waiting for card c14-1594 to land first/)
  for (const r of [...rows.slice(1, 4), rows[5], ...rows.slice(7)]) expect(r, 'no card id').not.toMatch(/c20261124T|c10-1533/)
  // Follow-ups of that issue. Bug they catch: the wait text put the holder's ID after a lead-in (`queued for the next
  // batch: `, then `queued: `), and spread() cut the text before the clock on the right, so a narrow pane showed
  // `queued: #15…` at 40 columns for `#1596 of #1600`, and `queu…` at 24 columns for `#1593`. At 40 columns the ID
  // and the clock both fit; at 24 the clock gives way to the ID. A later follow-up: with the ID first, the kind of
  // wait came last, so at 24 columns `#1593` showed `#1533…` both when it waited to land and when it was queued for
  // the next batch. The first letter of the word after the ID (`l` of `lands`, `n` of `next`) tells them apart, and
  // the clock gives way to it too, but only to it: at 40 columns `#1598 of #1600` keeps the clock with `fu #1590 la…`.
  // A part (`#1596 of #1600`) left room for only `#1533…` or `fu #1…` in both kinds of wait: at 24 columns its own ID
  // drops its parent, as the clock does. `fu #1596` has no parent to drop, and behind the main-red fix it showed
  // `red 19e3b6e…` in both kinds of wait: there the holder's ID is cut, so the letter fits.
  // [row, its own ID at 40 columns, at 24 columns, the start of its wait text at 40 columns, at 24 columns]
  const waits = [
    [1, '#1531', '#1531', 'fu #1590 lands', 'fu #1590 lands'],
    [2, '#1585', '#1585', '#1533 lands', '#1533 lands'],
    [3, '#1589', '#1589', 'red 19e3b6e lands', 'red 19e3b6e la…$'],
    [5, '#1593', '#1593', '#1533 next', '#1533 next'],
    [7, '#1596 of #1600', '#1596', '#1533 next', '#1533 next'],
    [8, '#1597 of #1600', '#1597', '#1533 lands', '#1533 lands'],
    [9, '#1598 of #1600', '#1598', 'fu #1590 la', 'fu #1590 lands'],
    [10, '#1599 of #1600', '#1599', 'fu #1590 ne', 'fu #1590 next'],
    [11, 'fu #1596', 'fu #1596', 'red 19e3b6e lands', 'red 19e3… l…$'],
    [12, 'fu #1596', 'fu #1596', 'red 19e3b6e next', 'red 19e3… n…$'],
  ] as const
  for (const [w, clock] of [[40, ' \\d+:\\d\\d [AP]M$'], [24, '']] as const) {
    const narrow = activityModel(s, s.snap!, w, 0).map(plain)
    for (const [i, own40, own24, said40, said24] of waits) {
      const r = narrow[i] ?? ''
      expect(r, `row ${i} at ${w} columns: ${r}`).toMatch(new RegExp(`^◐ ${w === 40 ? own40 : own24}  ${w === 40 ? said40 : said24}.*${clock}`))
      expect(cols(r), `row ${i} at ${w} columns: ${r}`).toBeLessThanOrEqual(w)
    }
  }
  const belt = tableText(s, 100)
  expect(belt, 'the belt\'s live line too').toMatch(/now fu #1590 lands first \(landing turn\)/)
})

// Issue 1272. Bug it catches: the pane's PICK ORDER named no ready issue, only a count, so with every slot full the
// issues waiting for a slot were named nowhere. It lists the next five in pick order, as /units' QUEUE does.
test('PICK ORDER lists the next five ready issues of two projects, numbered, with their priorities, above the Waiting table', () => {
  const next = (n: number, p: string) => Array.from({ length: n }, (_, i) => ({ issue: 10 + i, title: `${p} issue ${i}`, priority: i === 0 ? 'P0' : 'P2', followup: false, retried: false }))
  const waiting = [{ issue: 90, title: 'Waits', waitsFor: [10] }, { issue: 91, title: 'Waits too', waitsFor: [90] }]
  const s = state(fetched([['bookstore', snapshot({ queue: { next: next(4, 'Book'), waiting } })], ['gadgetlab', snapshot({ queue: { next: next(3, 'Gadget') } })]]))
  const text = paneModel(s, 72, 0).map(plain).join('\n')
  expect(text).toContain(' 7 READY ')
  const part = section(text, 'PICK ORDER').split('\n')
  // Pick order: priority first, then the issue order; the open project's own issues show without its name.
  expect(part.slice(0, 7)).toEqual([
    expect.stringMatching(/^PICK ORDER +next 5 of 7$/),
    expect.stringMatching(/^ 1 #10 Book issue 0 +P0$/),
    expect.stringMatching(/^ 2 gadgetlab#10 Gadget issue 0 +P0$/),
    expect.stringMatching(/^ 3 #11 Book issue 1 +P2$/),
    expect.stringMatching(/^ 4 gadgetlab#11 Gadget issue 1 +P2$/),
    expect.stringMatching(/^ 5 #12 Book issue 2 +P2$/),
    expect.stringMatching(/^Waiting +Requires$/),
  ])
  expect(part.slice(7).join('\n')).toMatch(/^#90 +#10\n#91 +#90/)
  expect(text).not.toContain('Gadget issue 2')
})

// Issue 1272. Bug it catches: the held-back reason, the follow-up and retried marks and the held-back line, which
// the pane lost with the list.
test('PICK ORDER says why the machine holds an issue back, marks a follow-up and a retried issue, and keeps the held-back line', () => {
  const room = 'waiting for a machine slot: 2 of the machine cap 2 in use'
  const next = [{ issue: 3950, title: 'Fix the follow-up', priority: 'P1', followup: true, retried: false }, { ...queued(1)[0], room }, { issue: 3951, title: 'Try again', priority: 'P2', followup: false, retried: true }]
  const part = section(paneModel(board({ queue: { next, skipped: skipped({ dormant: 3 }) } }), 72, 0).map(plain).join('\n'), 'PICK ORDER').split('\n')
  expect(part.slice(0, 5)).toEqual([
    expect.stringMatching(/^PICK ORDER +3 ready$/),
    expect.stringMatching(/^ 1 #3950 Fix the follow-up +P1 · follow-up$/),
    expect.stringMatching(/^ 2 #3900 Issue 0 +P2$/),
    `    ${room}`,
    expect.stringMatching(/^ 3 #3951 Try again +P2 · retried$/),
  ])
  expect(part.at(-1)).toBe('held back: 3 dormant')
})

// Issue 1272. Bug it catches: with nothing ready the pane said "nothing waiting" for an empty queue, and with only
// waiting issues it must show no ready rows, only the Waiting table.
test('PICK ORDER with nothing ready and nothing waiting says the queue is empty; with only waiting issues it shows the Waiting table alone', () => {
  const empty = paneModel(board(), 72, 0).map(plain).join('\n')
  expect(section(empty, 'PICK ORDER').split('\n').slice(1)).toEqual(['  the queue is empty'])
  const waiting = paneModel(board({ queue: { next: [], waiting: [{ issue: 5, title: 'Waits', waitsFor: [4] }] } }), 72, 0).map(plain).join('\n')
  expect(section(waiting, 'PICK ORDER').split('\n').slice(1)).toEqual([expect.stringMatching(/^Waiting +Requires$/), expect.stringMatching(/^#5 +#4$/)])
  const unread = paneModel(board({ queue: { next: null } }), 72, 0).map(plain).join('\n')
  expect(section(unread, 'PICK ORDER').split('\n').slice(1)).toEqual(['  not read: GitHub did not list the issues'])
})

// Issue 1449 (R427). Bug it catches: the first line of a rerun (57 columns) was cut at 56, so the pass total fell off.
test('a rerun line wider than the pane puts the pass on a line of its own, with its total', () => {
  const rerun = { round: 2, of: 3, case: 'x: a', since: ago(4), at: ago(3), done: 5, failed: 1, files: { done: 1, of: 2, failed: ['x'] } }
  const lines = tableText(board({ suites: [{ ...SUITE, rerun }] }), 56).split('\n').map(l => l.trimEnd())
  const at = lines.indexOf('release 1.2.0 · a1b2c3d')
  expect(lines.slice(at, at + 2), `rerun lines at 56 columns: ${lines.join(' | ')}`).toEqual(['release 1.2.0 · a1b2c3d', '  failed cases again: pass 2 of 3'])
  // Bug it catches (the same, at the narrowest pane, 32 columns): the pass line itself is 33 and was cut at its total.
  const narrow = tableText(board({ suites: [{ ...SUITE, rerun }] }), 32).split('\n').map(l => l.trimEnd())
  const top = narrow.indexOf('release 1.2.0 · a1b2c3d')
  expect(narrow.slice(top, top + 3), `rerun lines at 32 columns: ${narrow.join(' | ')}`).toEqual(['release 1.2.0 · a1b2c3d', '  failed cases again:', '  pass 2 of 3'])
})

// Issue 1449 (R438). Bug it catches: the ready count came from the queue's first ten, so a parent whose ready part was
// the eleventh counted as waiting.
test('a parent whose ready part is past the first ten of the pick order is not counted as waiting', () => {
  const part = { issue: 636, title: 'Ready part', priority: 'P2', followup: false, retried: false, umbrella: 647 }
  const waiting = [{ issue: 637, title: 'Waiting part', waitsFor: [636], umbrella: 647 }]
  const umbrellas = [{ issue: 647, title: 'Parent', parts: ['#636', '#637'], done: 0, all: 2, inFlight: [] }]
  const s = board({ queue: { next: queued(10), order: [...queued(10), part], waiting }, open: { umbrellas } })
  expect(paneModel(s, 72, 0).map(plain).join('\n')).toContain('\n0 ON BELT · 10+ READY · 0 WAITING · 0 NEEDS YOU\n')
})

// Issue 1449 (R436). Bug it catches: one dependency with a long state (59 columns) was cut at 56, losing its last issues.
test('PICK ORDER breaks a long dependency state at its words at 56 columns, cutting no issue number', () => {
  const state = 'waiting for #3900, #3901, #3902, #3903, #3904, #3905'
  const s = board({ queue: { next: [], waiting: [{ issue: 970, title: 'Waits', waitsFor: [967], waitsOn: [{ issue: 967, state }] }] } })
  const part = section(paneModel(s, 56, 0).map(plain).join('\n'), 'PICK ORDER')
  expect(part).not.toContain('…')
  expect(part.replace(/\s+/g, ' ')).toContain(`#967 (${state})`)
})

// Issue 1449 (R428). Bug it catches: a dependency one level down ("#485 (waiting for #481)") wider than the column was
// cut at 40 columns, digits and all.
test('PICK ORDER shows a two-level dependency whole at 40 columns, under a long project name', () => {
  const two = state(fetched([
    ['bookstore', snapshot()],
    ['gadgetlab-workshop', snapshot({ queue: { next: [], waiting: [{ issue: 490, title: 'Waits', waitsFor: [485], waitsOn: [{ issue: 485, state: 'waiting for #481' }] }] } })],
  ]))
  const part = section(paneModel(two, 40, 0).map(plain).join('\n'), 'PICK ORDER')
  expect(part).not.toContain('…')
  expect(part.replace(/\s+/g, ' ')).toContain('#485 (waiting for #481)')
  for (const l of part.split('\n')) expect(cols(l)).toBeLessThanOrEqual(40)
})

// Issue 1449 (R428, R430; the review's E11). Bug it catches: at 24 columns (the narrowest dock) the ID column of
// `gadgetlab-workshop#490` (22 columns, 24 with its two spaces) left the dependency state and the parent's counts and
// title no room beside it, so fitWidth cut them whole. They go on lines under the ID, indented by 2.
test('PICK ORDER at 24 columns, under a 22-column ID, shows the dependency state, the parent\'s counts and its title whole', () => {
  const umbrellas = [{ issue: 647, title: 'Ship the parts', parts: ['#635', '#636', '#637'], done: 1, all: 3, inFlight: [636] }]
  const two = state(fetched([
    ['bookstore', snapshot()],
    ['gadgetlab-workshop', snapshot({ queue: { next: [], waiting: [{ issue: 490, title: 'Waits', waitsFor: [485], waitsOn: [{ issue: 485, state: 'waiting for #481' }] }] }, open: { umbrellas } })],
  ]))
  const part = section(paneModel(two, 24, 0).map(plain).join('\n'), 'PICK ORDER').split('\n').map(l => l.trimEnd())
  const text = part.join('\n')
  expect(text, `PICK ORDER at 24 columns: ${part.join(' | ')}`).not.toContain('…')
  for (const l of part) expect(cols(l), `line "${l}" of PICK ORDER at 24 columns`).toBeLessThanOrEqual(24)
  const at = part.indexOf('gadgetlab-workshop#490')
  expect(part.slice(at, at + 3), `waiting rows at 24 columns: ${part.join(' | ')}`).toEqual(['gadgetlab-workshop#490', '  #485 (waiting for', '  #481)'])
  const top = part.indexOf('gadgetlab-workshop#647')
  expect(part.slice(top, top + 4), `parent rows at 24 columns: ${part.join(' | ')}`).toEqual(['gadgetlab-workshop#647', '  1 of 3 done · #636 in', '  flight', '  Ship the parts'])
})

// Issue 1449 (R430). Bug it catches: at 40 columns the row of a parent (37 columns before its title) left the title no
// room, and it was cut to nothing.
test('PICK ORDER puts a parent\'s title under its row at 40 columns, when the counts leave it no room', () => {
  const umbrellas = [{ issue: 647, title: 'Ship the parts', parts: ['#635', '#636', '#637'], done: 1, all: 3, inFlight: [636] }]
  const part = section(paneModel(board({ open: { umbrellas } }), 40, 0).map(plain).join('\n'), 'PICK ORDER').split('\n').map(l => l.trimEnd())
  const at = part.findIndex(l => l.startsWith('#647'))
  expect(part.slice(at, at + 2), `parent rows at 40 columns: ${part.join(' | ')}`).toEqual(['#647     1 of 3 done · #636 in flight', '         Ship the parts'])
})

// Issue 1449 (R432). Bug it catches: with one project the head is one part, which wrapParts could not split, and
// fitWidth cut it at 40 columns, losing "not counted)".
test('the ON THE BELT head of one project wraps at its comma at 40 columns, with "not counted)" whole', () => {
  const s = board({ belt: [BELT[0], { ...BELT[1], step: 'landing', offCap: true }], health: { loop: true, state: 'running', building: 1, builderCap: 7 } })
  const lines = section(tableText(s, 40), 'ON THE BELT').split('\n').slice(0, 2).map(l => l.trimEnd())
  expect(lines, `head at 40 columns: ${lines.join(' | ')}`).toEqual(['ON THE BELT (1 of 7,', '  1 landing not counted)'])
})

// Issue 1449 (R434). Bug it catches: a project's part ("bookstore 0 of 3, 1 landing not counted") wider than 40 columns
// with the head's lead was cut by fitWidth, hiding the landing count.
test('the ON THE BELT head of two projects wraps inside a project at 40 columns, keeping its landing count whole', () => {
  const two = state(fetched([
    ['bookstore', snapshot({ belt: [{ ...BELT[0], step: 'push' }], health: { loop: true, state: 'running', building: 0, builderCap: 3 } })],
    ['gadgetlab', snapshot({ belt: [{ ...BELT[1], card: 'c5-7', issue: 7 }], health: { loop: true, state: 'running' } })],
  ]))
  const lines = section(tableText(two, 40), 'ON THE BELT').split('\n').slice(0, 2).map(l => l.trimEnd())
  expect(lines, `head at 40 columns: ${lines.join(' | ')}`).toEqual(['ON THE BELT (bookstore 0 of 3,', '  1 landing not counted · gadgetlab 1)'])
})

// Issue 1449 (R437). Bug it catches: a retried follow-up in a project with a long name (lead, ref and flags 55 columns)
// was cut at 40, so its issue number was lost.
test('QUEUE puts the follow-up and retried flags under a row at 40 columns when they leave the title no room, keeping the issue whole', () => {
  const next = [{ issue: 1272, title: 'Retry me', priority: 'P2', followup: true, retried: true }]
  const two = state(fetched([['bookstore', snapshot()], ['gadgetlab-shop', snapshot({ queue: { next } })]]))
  const lines = section(tableText(two, 40), 'QUEUE').split('\n').map(l => l.trimEnd())
  const at = lines.findIndex(l => l.includes('gadgetlab-shop#1272'))
  expect(lines[at], `queue rows at 40 columns: ${lines.join(' | ')}`).toMatch(/^ 1 gadgetlab-shop#1272 .* P2$/)
  expect(lines[at + 1]).toBe('    follow-up · retried')
})

// Issue 1449 (R435). Bug it catches: with two projects each waiting on its own #80 the summary read
// "#80 (held), #80 (held)", naming neither project.
test('QUEUE names each project in what the waiting issues wait on when more than one project waits', () => {
  const waiting = [{ issue: 85, title: 'Waits', waitsFor: [80], waitsOn: [{ issue: 80, state: 'held' }] }]
  const two = state(fetched([['bookstore', snapshot({ queue: { next: [], waiting } })], ['gadgetlab', snapshot({ queue: { next: [], waiting } })]]))
  expect(section(tableText(two, 120), 'QUEUE')).toContain('waiting for bookstore#80 (held), gadgetlab#80 (held)')
})

// Issue 1449 (R435, review E5). Bug it catches: with the project's name added, one ref (`conveyor-belt#1449 (skipped by a
// rule)`, 42 columns on a continuation line) was wider than a 40-column pane and had no comma to break at, so it was cut.
test('QUEUE at 40 columns breaks a project-named dependency ref at its spaces, never cutting it', () => {
  const [a, b] = [{ issue: 85, title: 'Waits', waitsFor: [1449], waitsOn: [{ issue: 1449, state: 'skipped by a rule' }] }, { issue: 90, title: 'Waits', waitsFor: [80], waitsOn: [{ issue: 80, state: 'held' }] }]
  const two = state(fetched([['conveyor-belt', snapshot({ queue: { next: [], waiting: [a] } })], ['gadgetlab', snapshot({ queue: { next: [], waiting: [b] } })]]))
  const lines = section(tableText(two, 40), 'QUEUE').split('\n').map(l => l.trimEnd())
  expect(lines.filter(l => l.length > 40), `QUEUE lines at 40 columns: ${lines.join(' | ')}`).toEqual([])
  expect(lines.join(' ').replace(/\s+/g, ' '), `QUEUE at 40 columns: ${lines.join(' | ')}`).toContain('gadgetlab#80 (held), conveyor-belt#1449 (skipped by a rule)')
})
