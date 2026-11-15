// SPDX-License-Identifier: Apache-2.0
import { expect, test } from 'claude-code/testing'
import { TWO_PROJECTS } from './fixtures/units-two-projects'
import { bandModel, boardOf, fastText, paneModel, parseFetch, parseLimit, researchText, seatFromGit, seenOf, shortTitle, summaryLine, tableText, toasts } from './sources'
import type { Fast, Research, State } from './sources'
import { clockOf, cols, plain } from './elements'

// Each section of /units with data and with none, and every way the snapshot can fail to be read. The texts fed here
// are what the mod's fetch prints: `conveyor.sh snapshot` per record, under the paths, fast and host lines.

const NOW = Date.UTC(2026, 10, 10, 4, 40, 0)
const ago = (min: number) => new Date(NOW - min * 60_000).toISOString()
const snapshot = (over: object = {}) => JSON.stringify({
  time: ago(0), day: '2026-11-09', needsYou: { waiting: [], blocked: [] }, belt: [], queue: { next: [], held: {} }, landed: [], health: {},
  cost: { today: 0, week: 0, perLanded: null, landedAfter: {}, unpricedSteps: 0 }, ...over,
})
const fetched = (records: [string, string][], host = 'host\tbuildbox\tssh\t0', fast = 'fast\tnone') =>
  `paths\t/r/ws\t/r/home\tbookstore\n${fast}\n${host}\n${records.map(r => r.join('\t')).join('\n')}\n`
const state = (text: string, over: Partial<State> = {}): State =>
  ({ now: NOW, ...boardOf(parseFetch(text)), limit: null, fast: (parseFetch(text)?.fast ?? { state: 'unread' }) as Fast, research: { state: 'none' }, ...over })
const board = (over: object = {}, more: Partial<State> = {}) => state(fetched([['bookstore', snapshot(over)]]), more)
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
  const text = tableText(board({ cost: { today: 12.345 }, belt: BELT, queue: { next: queued(9), held: {} } }, { limit: { pct: 94, resetsAt: NOW + (24 + 18) * 3600_000 } }), 62)
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

// a snapshot that prices what it can gives today's priced dollars and the steps it leaves out, never hiding both.
test('the head gives today\'s priced dollars and how many steps they leave out', () => {
  const text = tableText(board({ cost: { today: 4.5, todayLeftOut: 2 } }), 80)
  expect(text.split('\n')[0]).toMatch(/^CONVEYOR +today \$4\.50 \+ 2 steps not priced  ● buildbox$/)
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
  for (const text of [tableText(s, 62), tableText(s, 120), paneModel(s, 62, 0).map(plain).join('\n'), bandModel(s, 160, 0).map(plain).join('\n')]) {
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

test('a card with no token read yet says no reading yet, never $0; one with a step not priced reads cost partial', () => {
  expect(beltCard({ usd: null, reading: false })[0]).toMatch(/ · no reading yet$/)
  expect(beltCard({ usd: 0, reading: false })[0]).toMatch(/ · no reading yet$/)
  expect(beltCard({ usd: 0.5, reading: true })[0]).toMatch(/ · \$0\.50$/)
  expect(beltCard({ usd: null, reading: true })[0]).toMatch(/ · cost partial$/)
})

// a follow-up shows a short title of what it fixes and the issue it came from, never the raw "[P2] path:line" title.
test('a follow-up shows its short title and its parent; a title no short one can be made of is cut at the width', () => {
  expect(shortTitle('[P2] .claude/dashboard/panels/metrics.js:53 The Host row omits recorded memory usage and CPU frequency, leaving these')).toBe('Metrics: Host row omits recorded memory usage')
  expect(shortTitle('[P1] conveyor/conveyor.sh:1479 A reviewer exiting 124 without readable usage writes no spent entry')).toBe('Conveyor: Reviewer exiting 124 without readable usage')
  expect(shortTitle('src/web/upload-form.tsx:12-14 the button is grey')).toBe('Upload form: Button is grey')
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
  const next = [...queued(6), { issue: 3999, title: 'A follow-up with a title much too long for the line it is on', priority: 'P1', followup: true, retried: true }]
  const part = section(tableText(board({ queue: { next, held: { dormant: 37, backlog: 2, 'ux-change': 0 } } }), 62), 'QUEUE')
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

test('QUEUE shows an issue that waits on another after the next ones, as "Waits for #N", never numbered', () => {
  const waiting = [{ issue: 3950, title: 'Second half', waitsFor: [3900] }, { issue: 3951, title: 'Both', waitsFor: [3900, 3950] }, { issue: 3952, title: 'Bad', waitsFor: [] }]
  const part = section(tableText(board({ queue: { next: queued(1), held: {}, waiting } }), 80), 'QUEUE')
  expect(part.split('\n')).toEqual([
    'QUEUE  1',
    expect.stringMatching(/^ 1 #3900 Issue 0 +P2$/),
    expect.stringMatching(/^ · #3950 Second half +Waits for #3900$/),
    expect.stringMatching(/^ · #3951 Both +Waits for #3900, #3950$/),
  ])
  // A snapshot from before the list, or one whose issues were not listed, shows none.
  expect(section(tableText(board({ queue: { next: queued(1), held: {} } }), 80), 'QUEUE')).not.toContain('Waits for')
})

test('the issues built and waiting for a PROD deploy are a section of their own under QUEUE, with how long each has waited; with none there is no section', () => {
  const awaitingDeploy = [{ issue: 3476, title: 'Stack split', since: ago(2 * 24 * 60) }, { issue: 3500, title: 'Label time not read', since: null }]
  const text = tableText(board({ queue: { next: queued(1), held: {} }, awaitingDeploy }), 80)
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
  const unread = board({ queue: { next: null, held: null } })
  expect(section(tableText(unread, 80), 'QUEUE')).toBe('QUEUE\n  not read: GitHub did not list the issues')
  expect(plain(bandModel(unread, 160, 0)[0])).toContain('queue not read')
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

// A fresh install sets up no lanes, and /units, the pane and the band each said "no worktree on this machine" of both:
// a lane with no worktree is not drawn, and with neither there is no lane line at all.
test('a lane with no worktree on this machine is drawn nowhere; a lane that has one is drawn alone', () => {
  const none = board()
  const views = (s: State) => [tableText(s, 100), paneModel(s, 100, 0).map(plain).join('\n'), bandModel(s, 100, 0).map(plain).join('\n')]
  for (const v of views(none)) expect(v).not.toMatch(/lane/i)
  expect(tableText(none, 100)).toMatch(/\n {2}nothing landed today$/)
  const fast = lane('fast\tok\tfast-lane\t0\t0\t')
  const [table, pane, band] = views(fast)
  for (const v of [table, pane]) {
    expect(v).toMatch(/\n\nFAST LANE      nothing open$/)
    expect(v).not.toMatch(/research/i)
  }
  expect(band.split('\n').at(-1)).toBe('Fast lane: nothing open')
  expect(band).not.toMatch(/research/i)
})

test('the Fast lane line names its card: on the belt with its step, needing you, or landed', () => {
  const card = { card: 'c9-0', issue: 0, title: 'Tidy the logo copy' }
  const fast = 'fast\tok\tfast-lane\t1\t0\tTidy the logo copy'
  expect(fastText(lane(fast, { belt: [{ ...BELT[1], ...card }] }))).toMatch(/ · card on the belt: review 2 of 3$/)
  expect(fastText(lane(fast, { needsYou: { waiting: [{ ...WAITING, ...card }], blocked: [] } }))).toMatch(/ · card needs you$/)
  expect(fastText(lane(fast, { landed: [{ ...LANDED[0], ...card }] }))).toMatch(new RegExp(` · card landed ${clockOf(NOW - 13 * 60_000)}$`))
  // A branch that names an issue lands as that issue's card; another branchless card is not this lane's.
  expect(fastText(lane('fast\tok\tfix-3864-units\t1\t0\tx', { belt: BELT }))).toMatch(/ · card on the belt: review 2 of 3$/)
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

test('a snapshot that cannot be read is one plain line saying why, in /units, the band, the pane and the status line', () => {
  const cases: [string, string][] = [
    ['', 'the fetch did not run'],
    ['paths\t/r/ws\t/r/home\nfast\tnone\n', 'the fetch did not finish'],
    [fetched([], 'host\t\tnofile\t0'), 'this machine has no host file, ~/.config/conveyor/host.json'],
    [fetched([], 'host\t\tconfig\t0'), 'the host file is not understood'],
    [fetched([], 'host\tbuildbox\tnossh\t0'), 'the host file names no ssh target'],
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
    expect(bandModel(s, 160, 0).map(plain)).toEqual([line])
    expect(paneModel(s, 72, 0).map(plain)).toEqual([line])
    expect(summaryLine(s)).toBe(line)
  }
})

// Bug: the first record was the session's own whatever checkout the session was in: a session in gadgetlab showed
// bakery's card as #12 and looked for its Fast lane's card among bakery's, so it read `not landed`.
test('a session in the second project: its cards carry no name, the first\'s carry theirs, and its Fast lane finds its card', () => {
  const text = TWO_PROJECTS.replace('\t/r/home\tbakery\n', '\t/r/home\tgadgetlab\n').replace('fast\tnone', 'fast\tok\tfix-7-gears\t1\t0\tGear ratio chart')
  const s = state(text)
  expect(tableText(s, 100)).toMatch(/\n bakery#12 Bread oven timer [^]*\n #7 Gear ratio chart /)
  expect(fastText(s)).toMatch(/ · card on the belt: review 1 of 3$/)
})

test('a second record\'s cards carry its name, and one record that cannot be read costs only its own note', () => {
  const other = snapshot({ belt: [{ ...BELT[0], card: 'c1-12', issue: 12, title: 'Other work' }], cost: { today: 1 }, queue: { next: null, held: null } })
  const both = state(fetched([['bookstore', snapshot({ belt: [BELT[1]], cost: { today: 2.5 }, queue: { next: queued(1), held: {} } })], ['widgetshop', other]]))
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
  expect(plain(bandModel(half, 160, 0)[0])).toContain(' · today partial · ')
  expect(summaryLine(half)).toMatch(/ · today partial$/)
  expect(tableText(state(fetched([['bookstore', 'null'], ['widgetshop', other]])), 100)).toMatch(/^CONVEYOR +today partial  ● buildbox\n/)
})

test('the pane shows every section in short form: one line an item, no line wider than the pane', () => {
  const landed = Array.from({ length: 7 }, (_, i) => ({ ...LANDED[0], card: `c-${i}`, issue: 3800 + i, time: ago(i) }))
  const s = board({ needsYou: { waiting: [WAITING], blocked: [BLOCKED] }, belt: BELT, queue: { next: queued(10), held: { dormant: 3 } }, landed, cost: { today: 29.48 } },
    { limit: { pct: 50, resetsAt: NOW + 3600_000 }, research: { state: 'ok', lastAt: NOW - 60_000 }, fast: { state: 'ok', branch: 'fast-lane', ahead: 1, dirty: 0, subject: 'A long subject '.repeat(8) } })
  const lines = paneModel(s, 60, 0).map(plain)
  for (const l of lines) expect(cols(l)).toBeLessThanOrEqual(60)
  const text = lines.join('\n')
  expect(text).toMatch(/\n◆ #3861 Fast lane lands thro… · your yes: Staff land F… +12m\n✗ #3850 Logo upload · blocked: review 3 was NO-GO: … +1h 30m\n/)
  expect(plain(paneModel(s, 60, 0)[4])).toHaveLength(60)
  expect(text).toMatch(/\n #3864 Rebuild \/units for Conveyor +\$1\.25\n ◐ review 2 of 3\n/)
  expect(text).toContain('\nQUEUE  next 5 of 10+\n')
  expect(text).toMatch(/\nLANDED TODAY  7 · \$29\.48\n( \S+ [AP]M ✓ #380\d One snapshot record +2 reviews  \$4\.21\n {9}↳ 2 follow-ups: #3870 #3871\n){5}  \+2 more\n/)
  expect(text).toMatch(/\nFAST LANE      1 commit on fast-lane: A long subject .*…\nRESEARCH LANE  working · last activity 1m ago$/)
})

test('the band shows the header with each section\'s count, the first thing that needs you, the belt and the lanes', () => {
  const s = board({ needsYou: { waiting: [WAITING], blocked: [BLOCKED] }, belt: BELT, queue: { next: queued(10), held: {} }, landed: LANDED, cost: { today: 9.5 } },
    { limit: { pct: 34, resetsAt: NOW + 3600_000 }, research: { state: 'ok', lastAt: NOW - 600_000 } })
  const rows = bandModel(s, 160, 1).map(plain)
  expect(rows).toHaveLength(4)
  expect(rows[0]).toMatch(/^CONVEYOR · 2 need you · 2 on the belt · 10\+ queued · 3 landed +7d ▰▰▰▱▱▱▱▱▱▱ 34% · today \$9\.50 · ● buildbox reachable$/)
  expect(rows[1]).toMatch(/^◆ #3861 · your yes: Staff land Fast lane changes as a card\. +\+1 more$/)
  expect(rows[2]).toBe('◓ #3863 build 10m   ◓ #3864 review 2 of 3 3m')
  expect(rows[3]).toBe('Research lane: idle · last activity 10m ago')
  for (const r of bandModel(s, 50, 0).map(plain)) expect(cols(r)).toBeLessThanOrEqual(50)
})

test('a long Fast lane branch or commit subject is cut in the band and the Research lane stays whole', () => {
  const s = board({}, { research: { state: 'ok', lastAt: NOW - 600_000 }, fast: { state: 'ok', branch: 'fast-lane-' + 'long-name-'.repeat(12), ahead: 2, dirty: 1, subject: 'A long subject '.repeat(20) } })
  for (const w of [160, 100, 70]) {
    const row = plain(bandModel(s, w, 0).at(-1)!)
    expect(cols(row)).toBe(w)
    expect(row).toMatch(/^Fast lane: 2 commits on.*… · Research lane: idle · last activity 10m ago$/)
  }
  for (const r of bandModel(s, 30, 0).map(plain)) expect(cols(r)).toBeLessThanOrEqual(30)
})

test('an empty board with no lanes set up is a one-row band: the counts', () => {
  const rows = bandModel(board(), 160, 0).map(plain)
  expect(rows).toHaveLength(1)
  expect(rows[0]).toMatch(/^CONVEYOR · 0 on the belt · 0 queued · 0 landed +7d not read · today \$0\.00 · ● buildbox reachable$/)
  expect(summaryLine(board())).toBe('conveyor: 0 on the belt · 0 landed · today $0.00')
  expect(summaryLine(board({ needsYou: { waiting: [WAITING], blocked: [] } }))).toBe('conveyor: 1 needs you · 0 on the belt · 0 landed · today $0.00')
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
test('the usage limit is read from the data file\'s health panel, where the Board puts it, and a file without one gives none', () => {
  const data = (limit: unknown) => `window.DASH = ${JSON.stringify({ panels: { health: { data: { limit } } } })};`
  expect(parseLimit(data({ usedPct: 41.5, resetsAt: '2026-11-12T00:00:00Z' }))).toEqual({ pct: 41.5, resetsAt: Date.UTC(2026, 10, 12) })
  expect(parseLimit(data(null))).toBe(null)
  expect(parseLimit(data({ usedPct: '41' }))).toBe(null)
  expect(parseLimit('not a data file')).toBe(null)
})

test('the seat is main (where the Foreman runs) or a worker worktree; no folder name makes a seat', () => {
  expect(seatFromGit('/r/main/.git\n/r/main/.git\n/r/main\n')).toEqual({ seat: 'main', main: '/r/main' })
  expect(seatFromGit('/r/main/.git/worktrees/c\n/r/main/.git\n/r/ws/Research\n')).toEqual({ seat: 'worker', main: '/r/main' })
  expect(seatFromGit('/r/main/.git/worktrees/u\n/r/main/.git\n/r/cards/c1-3864\n')).toEqual({ seat: 'worker', main: '/r/main' })
  expect(seatFromGit('')).toBe(null)
})
