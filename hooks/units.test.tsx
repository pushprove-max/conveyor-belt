// SPDX-License-Identifier: Apache-2.0
import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'
import { register as loadAgain } from './units'
import { TWO_PROJECTS } from './fixtures/units-two-projects'

// The mod asks for one thing, its fetch (a bash run in the main checkout), then reads the Board's limit file for the
// usage limit and the Research lane's session logs. Each hook below stands for the engine over an in-memory disk; the
// fetch answers with `w.fetch`, the lines the real script prints.

const MAIN = '/r/main'
const WS = '/r/ws'
const HOME = '/r/home'
const NOW = Date.UTC(2026, 10, 10, 4, 40, 0)
// The Board's folder, as FEED_DIR names it: the folder the Board writes data.js, limit.json, stream.json and units-feed.json to.
const BOARD = '/r/state/bookstore/dashboard'
const DATA = `${BOARD}/data.js`
const LIMIT = `${BOARD}/limit.json`
// The limit file as the Board writes it: its health panel's limit alone.
const limitJson = (usedPct: number, resetsAt: string) => JSON.stringify({ limit: { usedPct, resetsAt } })
const SESSION = { surface: 'terminal', isInteractive: true } as const
const SEATS = { main: [`${MAIN}/.git`, MAIN], worker: [`${MAIN}/.git/worktrees/u`, '/r/cards/c1-3864'] }
const ago = (min: number) => new Date(NOW - min * 60_000).toISOString()

const snapshot = (over: object = {}) => JSON.stringify({
  time: ago(0), day: '2026-11-09', needsYou: { waiting: [], blocked: [] }, belt: [], queue: { next: [], held: {} }, landed: [], health: {}, cost: { today: 0 }, ...over,
})
const answer = (snap: string | null, host = 'host\tbuildbox\tssh\t0') => `paths\t${WS}/Research\t${HOME}\tbookstore\nfast\tok\tfast-lane\t0\t0\t\n${host}\n${snap === null ? '' : `bookstore\t${snap}\n`}`
const BELT = { card: 'c3-3863', issue: 3863, title: 'Rebuild the dashboard', step: 'build', review: null, of: 3, stepAt: ago(10), model: 'claude-fable-5-2', tokens: {}, usd: null, reading: false }
const WAITING = { card: 'c1-3861', issue: 3861, title: 'Fast lane', sentence: 'Staff land a lane change as a card.', since: ago(12) }
const LANDED = { card: 'c5-3862', issue: 3862, title: 'One snapshot record', step: 'landed', time: ago(13), usd: 4.2, reviews: 2, followups: [], sha: 'f1d6', pushed: true }
const FULL = snapshot({ needsYou: { waiting: [WAITING], blocked: [] }, belt: [BELT], queue: { next: [{ issue: 3900, title: 'Next up', priority: 'P1', followup: false, retried: false }], held: {} }, landed: [LANDED], cost: { today: 7 } })

// writes: the key of each of the mod's atoms written, in order.
type World = { files: Map<string, { text: string; at: number }>; reads: string[]; writes: string[]; fetch: string; fetchRc: number; fetchCut?: boolean; boardDir: string | null; runs: { argv: string[]; cwd?: string }[]; status: (string | undefined)[]; toasts: string[]; registered: string[]; opened: string[]; clock: ReturnType<typeof mock.clock>; placed?: boolean; hold?: Promise<void>; run: (argv: readonly string[], cwd?: string) => any }

// env: the session's environment variables the mod reads (none set unless given).
const world = (on: On, seat: keyof typeof SEATS, fetch: string, files: Record<string, string> = {}, installed = true, env: Record<string, string> = {}): World => {
  const clock = mock.clock(on, { now: NOW })
  mock.env(on, env)
  const w: World = { files: new Map(), reads: [], writes: [], fetch, fetchRc: 0, boardDir: BOARD, runs: [], status: [], toasts: [], registered: [], opened: [], clock, run: () => undefined }
  for (const [p, text] of Object.entries(files)) w.files.set(p, { text, at: NOW - 1000 })
  if (installed) w.files.set(`${MAIN}/.conveyor/project.json`, { text: '', at: 0 })
  const [gitDir, top] = SEATS[seat]
  on('session.root', () => ({ value: top }))
  on('session.cwd', () => ({ value: top }))
  const out = (stdout: string, exitCode = 0, cut = false) => ({ value: { exitCode, stdout, stderr: '', isStdoutTruncated: cut, isStderrTruncated: false } })
  w.run = (argv, cwd) => {
    w.runs.push({ argv: [...argv], cwd })
    if (argv[0] === 'git') return out(`${gitDir}\n${MAIN}/.git\n${top}\n`)
    // FEED_DIR: the Board's folder, or the exit of a state folder that cannot be named (w.boardDir null).
    if (argv[0] === 'bash' && argv[3] === 'units-feed') return w.boardDir ? out(`${w.boardDir}\n`) : out('', 4)
    // w.hold: a fetch that does not answer until it resolves (a slow host). w.fetchCut: its output cut at the engine's cap.
    if (argv[0] === 'bash') { const [text, rc, cut] = [w.fetch, w.fetchRc, !!w.fetchCut]; return w.hold ? w.hold.then(() => out(text, rc, cut)) : out(text, rc, cut) }
    return out('', 127)
  }
  on('process.run', (_, e) => w.run(e.argv, e.init?.cwd))
  // A folder's entries: its files, and each folder a file is in below it.
  on('fs.list', (_, e) => {
    const dir = e.path ?? ''
    const names = [...w.files].filter(([p]) => p.startsWith(`${dir}/`) && !p.slice(dir.length + 1).includes('/'))
    const dirs = [...new Set([...w.files.keys()].filter(p => p.startsWith(`${dir}/`) && p.slice(dir.length + 1).includes('/')).map(p => p.slice(dir.length + 1).split('/')[0]))]
    if (!names.length && !dirs.length) throw new Error(`ENOENT ${dir}`)
    return { value: [...names.map(([p, f]) => ({ name: p.slice(dir.length + 1), kind: 'file' as const, size: f.text.length, mtimeMs: f.at, isLink: false })),
      ...dirs.map(name => ({ name, kind: 'dir' as const, size: 0, mtimeMs: 0, isLink: false }))] }
  })
  on('fs.read', (_, e) => {
    w.reads.push(e.path)
    const f = w.files.get(e.path)
    if (!f) throw new Error(`ENOENT ${e.path}`)
    return { value: f.text }
  })
  on('fs.stat', (_, e) => {
    const f = w.files.get(e.path)
    if (!f) throw new Error(`ENOENT ${e.path}`)
    return { value: { kind: 'file', size: f.text.length, mtimeMs: f.at, isLink: false } }
  })
  on('state.set', (_, e, next) => (e.plugin === 'conveyor-belt' && w.writes.push(e.key), next(e)))
  on('ui.status', (_, e) => (w.status.push(e.text), { value: undefined }))
  on('ui.toast', (_, e) => (w.toasts.push(e.text), { value: undefined }))
  on('ui.open', (_, e) => (w.opened.push(e.id), { value: { isPlaced: w.placed ?? true, ...(w.placed === false ? { reason: 'no room' } : {}) } }))
  on('ui.close', (_, e) => (w.opened.splice(w.opened.indexOf(e.id), 1), { value: undefined }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('command.register', (_, e) => (w.registered.push(e.name), { value: { command: e.name } }))
  // The place above the prompt is one row per plugin that hooks it, the test among them: this stands beneath the
  // plugin's rows and draws no row of the test's own, so 'engine' alone there means the plugin drew nothing above it.
  on('ui.render', { plugin: '*' }, ($, e, next) => (e.component === 'AbovePrompt' && e.plugin !== 'conveyor-belt' ? next(e) : { ...$.ui.resolve(e).Text({ children: 'engine' }) }))
  on('command.run', () => ({ text: 'engine' }))
  return w
}

const start = ($: any, seat: keyof typeof SEATS) => $.session.start({ cwd: SEATS[seat][1], ...SESSION })
const units = ($: any, args = '') => $.command.run({ command: 'units', args, origin: { kind: 'composer' }, presentation: { layout: 'main', columns: 100 } }).then((r: any) => r.text as string)
// props: the Pane's own, where a case sets its width (a `viewport` in them is the event's, not a prop).
const draw = async ($: any, component: 'AbovePrompt' | 'Pane', props?: Record<string, unknown>) => {
  const { viewport, ...given } = props ?? (component === 'Pane' ? { title: 'Conveyor', isFocused: false, bodyColumns: 72, placement: 'dock' } : { hasSurvey: false })
  const ui = await $.ui.mount({ plugin: 'conveyor-belt', surface: 'terminal', component, requestId: component === 'Pane' ? 'units' : 'band', props: given, ...(viewport ? { viewport } : {}) })
  const texts = ((await ui.findAll({ type: 'Text' })) as { text: string }[]).map(t => t.text)
  await ui.unmount()
  return texts.join('')
}
// Presses the pane's Machine details Button, which opens the details, or closes them when open.
const pressDetails = async ($: any) => {
  const ui = await $.ui.mount({ plugin: 'conveyor-belt', surface: 'terminal', component: 'Pane', requestId: 'units', props: { title: 'Conveyor', isFocused: false, bodyColumns: 72, placement: 'dock' } })
  await ui.press({ key: 'details' })
  await ui.unmount()
}
// The short check (`stamp`) is no fetch: it reads one checksum a record, never a snapshot.
const fetches = (w: World) => w.runs.filter(r => r.argv[0] === 'bash' && r.argv[1]?.endsWith('/hooks/units-fetch.sh') && r.argv[2] !== 'stamp' && r.argv[2] !== 'foreman')
// The once-a-second look at the Foreman's role mark and waiter.pid reads the Foreman line alone (`foreman` mode), no fetch.
const foremanReads = (w: World) => w.runs.filter(r => r.argv[0] === 'bash' && r.argv[1]?.endsWith('/hooks/units-fetch.sh') && r.argv[2] === 'foreman')
const checks = (w: World) => w.runs.filter(r => r.argv[0] === 'bash' && r.argv[1]?.endsWith('/hooks/units-fetch.sh') && r.argv[2] === 'stamp')
const CANNOT = 'units: the Conveyor snapshot cannot be read (buildbox is unreachable)'

test('/units prints the header, the four sections and the two lanes from one fetch run in the main checkout', async ($, on) => {
  const w = world(on, 'main', answer(FULL), {
    [LIMIT]: limitJson(34, new Date(NOW + 5 * 3600_000).toISOString()),
    [`${WS}/Research/.git`]: 'gitdir: x', [`${HOME}/.claude/projects/-r-ws-Research/a.jsonl`]: '{}',
  })
  await start($, 'main')
  await w.clock.settle()
  const text = await units($)
  expect(text).toMatch(/^CONVEYOR +today \$7\.00  ● buildbox\nweekly limit 34% · resets 5h 0m +1 on belt · 1 queued\n/)
  expect(text).toMatch(/\nNEEDS YOU \(1\)\n◆ #3861 Fast lane +12m\n    your yes: Staff land a lane change as a card\.\n/)
  expect(text).toMatch(/\nON THE BELT \(1\)\n #3863 Rebuild the dashboard +no reading yet\n ◐ build\n/)
  expect(text).toMatch(/\nQUEUE  1\n 1 #3900 Next up +P1\n/)
  expect(text).toMatch(/\nLANDED TODAY  1 · \$7\.00\n \S+ [AP]M ✓ #3862 One snapshot record +2 reviews  \$4\.20\n/)
  expect(text).toMatch(/\nFAST LANE      nothing open\nRESEARCH LANE  working · last activity 1m ago$/)
  expect(text).not.toMatch(/unit|seat|pass|merge|PC /i)
  expect(fetches(w).length).toBeGreaterThan(0)
  expect(fetches(w).every(r => r.cwd === MAIN && r.argv.length === 2)).toBe(true)
  expect(w.registered).toEqual(['units'])
})

// Bug: the Research lane's session logs were looked for under ~/.claude whatever CLAUDE_CONFIG_DIR was, so the lane
// showed no run recorded (lastAt null) though its sessions wrote under that folder.
test('the Research lane reads its session logs under CLAUDE_CONFIG_DIR when it is set', async ($, on) => {
  const w = world(on, 'main', answer(FULL), { [`${WS}/Research/.git`]: 'gitdir: x', '/r/cfg/projects/-r-ws-Research/a.jsonl': '{}' }, true, { CLAUDE_CONFIG_DIR: '/r/cfg' })
  await start($, 'main')
  await w.clock.settle()
  expect(await units($)).toMatch(/\nRESEARCH LANE  working · last activity 1m ago$/)
})

// Bug: Claude Code cuts a project folder's name past 200 characters to those, a dash and a hash; the lane looked for
// the whole name, so a worktree with a long path showed no run recorded.
test('the Research lane of a worktree whose path is over 200 characters finds its logs in the cut folder', async ($, on) => {
  const wt = `/r/${'x'.repeat(210)}/Research`
  const dir = `${HOME}/.claude/projects/${wt.replace(/[^A-Za-z0-9]/g, '-').slice(0, 200)}-1a2b3c`
  const w = world(on, 'main', answer(FULL).replace(`${WS}/Research`, wt), { [`${wt}/.git`]: 'gitdir: x', [`${dir}/a.jsonl`]: '{}' })
  await start($, 'main')
  await w.clock.settle()
  expect(await units($)).toMatch(/\nRESEARCH LANE  working · last activity 1m ago$/)
})

// /units is every project's on the machine, not only the plugin's own: a host file with two projects (bakery and
// gadgetlab; units-fetch.test.sh checks the fetch prints TWO_PROJECTS for that host file) shows both.
test('/units from a host file with two projects shows both: the first one\'s paused loop and card, the second\'s card under its name', async ($, on) => {
  const w = world(on, 'main', TWO_PROJECTS)
  await start($, 'main')
  await w.clock.settle()
  const text = await units($)
  expect(text).toMatch(/^CONVEYOR · bakery paused +today \$3\.50  ● lab\n/)
  expect(text).toMatch(/\nON THE BELT \(bakery 1 · gadgetlab 1\)\n #12 Bread oven timer +[^\n]*\n[^]*\n gadgetlab#7 Gear ratio chart +/)
})

test('an empty board prints every section with its empty line, a missing data file says so, and a lane with no worktree is left out', async ($, on) => {
  const w = world(on, 'main', answer(snapshot()))
  await start($, 'main')
  await w.clock.settle()
  expect(await units($)).toBe([
    `CONVEYOR${' '.repeat(100 - 8 - 23)}today $0.00  ● buildbox`,
    `weekly limit not read${' '.repeat(100 - 21 - 20)}0 on belt · 0 queued`,
    'judge declined no findings today',
    '', 'NEEDS YOU  nothing',
    '', 'ON THE BELT', '  the belt is empty',
    '', 'QUEUE', '  the queue is empty',
    '', 'LANDED TODAY', '  nothing landed today',
    '', 'FAST LANE      nothing open',
  ].join('\n'))
})

test('a snapshot that cannot be read is one plain line in /units and the pane', async ($, on) => {
  const w = world(on, 'main', answer(null, 'host\tbuildbox\tssh\t255'), { [LIMIT]: limitJson(34, '2026-11-12T00:00:00Z') })
  await start($, 'main')
  await w.clock.settle()
  expect(await units($)).toBe(CANNOT)
  expect(await draw($, 'Pane')).toBe(CANNOT)
})

test('a fetch that fails or prints nothing readable is the same one line, never an earlier board', async ($, on) => {
  const w = world(on, 'main', answer(FULL))
  await start($, 'main')
  await w.clock.settle()
  expect(await units($)).toContain('ON THE BELT (1)')
  w.fetchRc = 3
  await units($)
  await w.clock.settle()
  expect(await units($)).toBe("units: the Conveyor snapshot cannot be read (the fetch did not run)")
  w.fetchRc = 0
  w.fetch = answer('null')
  await w.clock.settle()
  await units($)
  await w.clock.settle()
  expect(await units($)).toBe('units: the Conveyor snapshot cannot be read (buildbox gave no snapshot)')
  expect(await draw($, 'Pane')).not.toContain('ON THE BELT')
})

test('the pane shows the board in short form', async ($, on) => {
  const w = world(on, 'main', answer(FULL))
  await start($, 'main')
  await units($)
  const pane = await draw($, 'Pane')
  for (const part of ['1 ON BELT · 1 READY · 0 WAITING · 1 NEEDS YOU', 'NEEDS YOU (1)', '◆ #3861 Fast lane · your yes: Staff land a lane change as a card.', 'BUILD MATRIX', 'WORKER ACTIVITY',
    'PICK ORDER', '1 ready', 'LANDED TODAY · 1', '1 most recent of 1', 'FAST LANE      nothing open']) expect(pane).toContain(part)
  // The Research lane has no worktree here, so the pane leaves it out.
  expect(pane).not.toContain('RESEARCH LANE')
  expect(w.opened).toEqual(['units'])
})

// Bug it catches (#355): /units drew a band above the prompt and a status line; only the pane stays, with any setting.
test('no setting draws a /units band above the prompt or a status line', { options: { band: 'on', pane: 'on', status: 'on' } }, async ($, on) => {
  const w = world(on, 'main', answer(FULL))
  await start($, 'main')
  await units($)
  await w.clock.settle()
  expect(await draw($, 'Pane')).toContain('1 ON BELT')
  // 'engine' is the test's own row beneath the plugin's: nothing of /units stands above it.
  expect(await draw($, 'AbovePrompt')).toBe('engine')
  expect(w.status).toEqual([])
})

// Bug it catches (#286): the pane drew at 72 columns at most, so a wide pane cut titles and narrowed the track, and a
// render with no bodyColumns (a surface that gives the pane's size as viewport) fell back to the 56-column layout.
test('the pane draws at the width it is given, over 72 too, from bodyColumns or else viewport, and at 56 with neither', async ($, on) => {
  const title = 'Benchmark: run SWE-bench Verified on the engine and chart each card next to the last run'
  const steps = ['Build', 'Review', 'Fix', 'Test', 'Land', 'Push'].map((name, i) => ({ name, state: i < 2 ? 'done' : i === 2 ? 'now' : 'todo', sec: i < 2 ? 60 : null }))
  const card = { ...BELT, title, track: { steps, at: 2, label: 'fixing', since: ago(1), reason: null, files: null } }
  world(on, 'main', answer(snapshot({ belt: [card] })))
  await start($, 'main')
  await units($)
  const at = (size: object) => draw($, 'Pane', { title: 'Conveyor', isFocused: false, placement: 'dock', ...size })
  for (const wide of [await at({ bodyColumns: 120 }), await at({ viewport: { columns: 120, rows: 40 } })]) {
    expect(wide).toContain(title)
    expect(wide).toContain('✓ ✓ ▶ · · ·')
    // The head row is padded to the pane width and ends at the day's spend: its length is the width the pane drew at.
    expect(wide.match(/^.*?DAY SPEND \$\d+\.\d\d/)?.[0]).toHaveLength(120)
  }
  // At 56 columns the matrix row ends in the title, cut with … to the row's free width (#603).
  const narrow = await at({})
  expect(narrow).toMatch(/ +– +–  Benchmark: run[^…]*…/)
  expect(narrow).not.toContain(title)
  expect(narrow).toContain('✓ ✓ ▶ · · ·')
  expect(narrow.match(/^.*?DAY SPEND \$\d+\.\d\d/)?.[0]).toHaveLength(56)
})

// Issue 1461 (O381). Bug it catches: Claude Code keeps a dock 33 columns wide (body 32), but the pane drew at 40
// columns at least, so every row ran past the dock and wrapped. It draws at the 32 columns it is given.
test('the pane draws at a dock body narrower than 40 columns, at the width it is given', async ($, on) => {
  world(on, 'main', answer(FULL))
  await start($, 'main')
  await units($)
  const pane = await draw($, 'Pane', { title: 'Conveyor', isFocused: false, placement: 'dock', bodyColumns: 32 })
  // The head row is padded to the pane width and ends at the day's spend: its length is the width the pane drew at.
  expect(pane.match(/^.*?DAY SPEND \$\d+\.\d\d/)?.[0]).toHaveLength(32)
})

test('main fetches at the start and once a minute', async ($, on) => {
  const w = world(on, 'main', answer(snapshot()))
  await start($, 'main')
  await units($)
  await w.clock.settle()
  expect(fetches(w).length).toBe(2)
  await w.clock.advance(60_000)
  await units($)
  await w.clock.settle()
  expect(fetches(w).length).toBe(4)
})

// With no live feed, the fetch's short check runs every 5 s. Bug it catches: a card that went on the belt showed only
// at the next minute's fetch, and then from a kept snapshot older than the change; or each check ran a whole fetch.
test('with no feed, a record whose check moved is fetched at once with its snapshot fresh; a check with nothing moved fetches nothing', async ($, on) => {
  const w = world(on, 'main', answer(snapshot()))
  let stamp = 'stamps\tlocal\nbookstore\t4294967295 0\n'
  const base = w.run
  w.run = (argv, cwd) => {
    if (argv[2] !== 'stamp') return base(argv, cwd)
    w.runs.push({ argv: [...argv], cwd })
    return { value: { exitCode: 0, stdout: stamp, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  }
  await start($, 'main')
  await w.clock.settle()
  await w.clock.advance(10_000)
  await w.clock.settle()
  // The opening fetch's own check, then one every 5 s.
  expect(checks(w).length).toBe(3)
  expect(fetches(w).map(r => r.argv.slice(2))).toEqual([[]])
  // A start line in bookstore's cards.jsonl moves its checksum: the next check fetches it, asking for a fresh snapshot.
  stamp = 'stamps\tlocal\nbookstore\t3962379231 20\n'
  w.fetch = answer(snapshot({ belt: [BELT] }))
  await w.clock.advance(5000)
  await w.clock.settle()
  expect(fetches(w).map(r => r.argv.slice(2))).toEqual([[], ['fresh', 'bookstore']])
  expect(await draw($, 'Pane')).toContain('#3863')
})

// Bug it catches: the first check only took the checksums to compare with later, so a record that changed between the
// opening fetch and that check was not fetched until the minute's fetch.
test('with no feed, a record that changed after the opening fetch and before the first check is fetched fresh', async ($, on) => {
  const w = world(on, 'main', answer(snapshot()))
  let stamp = 'stamps\tlocal\nbookstore\t4294967295 0\n'
  const base = w.run
  w.run = (argv, cwd) => {
    if (argv[2] !== 'stamp') return base(argv, cwd)
    w.runs.push({ argv: [...argv], cwd })
    return { value: { exitCode: 0, stdout: stamp, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  }
  await start($, 'main')
  await w.clock.settle()
  expect(fetches(w).map(r => r.argv.slice(2))).toEqual([[]])
  stamp = 'stamps\tlocal\nbookstore\t3962379231 20\n'
  w.fetch = answer(snapshot({ belt: [BELT] }))
  await w.clock.advance(5000)
  await w.clock.settle()
  expect(fetches(w).map(r => r.argv.slice(2))).toEqual([[], ['fresh', 'bookstore']])
})

// Bug it catches: the age note was counted when the fetch ran, so a snapshot 59 s old then never said it was over a
// minute old until the next fetch.
test('a kept snapshot 59 s old at the fetch says its age once the clock passes a minute, with no new fetch', async ($, on) => {
  const w = world(on, 'main', answer(snapshot({ snapshotAt: new Date(NOW - 59_000).toISOString() })))
  await start($, 'main')
  await w.clock.settle()
  expect(await units($)).not.toContain('snapshot is')
  await w.clock.advance(2000)
  expect(await units($)).toContain('units: the bookstore snapshot is 1m old')
})

// Issue 1461 (B-R442). Bug it catches: the 5 s check skipped only while a poll was queued, not while it ran, so it ran
// beside a slow opening fetch; on an engine pinned before the check, whose fetch script runs the whole snapshot for
// `stamp` too, the two built every record's snapshot at once. The fetch here holds (a slow host): the opening fetch
// and the checksums it takes as it starts run, and no check beside them.
test('with no feed, the 5 s check does not run while a fetch is still out', async ($, on) => {
  const w = world(on, 'main', answer(snapshot()))
  let release = () => {}
  w.hold = new Promise<void>(r => { release = r })
  await start($, 'main')
  await w.clock.advance(5000)
  await w.clock.advance(5000)
  expect(fetches(w).length).toBe(1)
  expect(checks(w).length).toBe(1)
  w.hold = undefined
  release()
  await w.clock.settle()
})

// Bug it catches: an install older than the check takes `stamp` for a whole fetch, so every 5 s ran one.
test('a fetch that prints no stamps (an older install) is checked once, then only the minute\'s fetch runs', async ($, on) => {
  const w = world(on, 'main', answer(snapshot()))
  await start($, 'main')
  await w.clock.settle()
  await w.clock.advance(20_000)
  await w.clock.settle()
  expect(checks(w).length).toBe(1)
})

// A reload in a running session: the kit loads the module once and has no reload, so the first load is the kit's
// and the reload is this file's own instance of the module, fresh. A reload drops the first load's timers (here every
// wait it has out never resolves) and runs register again with no session.start; the kit's engine gives no $ a module
// can run on, so the fresh instance runs on a $ over the same world: its runs, files and clock, a state of its own.
const reloaded = (w: World) => {
  const hooks: { event: string; match?: any; hook: (...a: any[]) => any }[] = []
  loadAgain(((event: string, ...rest: any[]) => {
    hooks.push({ event, match: rest.length > 1 ? rest[0] : undefined, hook: rest.at(-1) })
    return { catch: () => undefined }
  }) as any, {})
  const values = new Map<string, { value: unknown; version: number }>()
  const name = (r: any) => `${r.plugin}/${r.key}/${r.id ?? ''}`
  const file = (path: string) => { const f = w.files.get(path); if (!f) throw new Error(`ENOENT ${path}`); return f }
  // Claude Code's timer: an object with cancel, not a function.
  const every = (ms: number, fn: () => void) => {
    let on = true
    void (async () => { while (on) { await w.clock.sleep(ms); if (on) fn() } })()
    return { cancel: () => { on = false } }
  }
  const $r: any = {
    plugin: { name: 'conveyor-belt', root: '/r/plugin' },
    session: { root: async () => MAIN, id: async () => 'me' },
    process: { run: async (argv: string[], init?: { cwd?: string }) => (await w.run(argv, init?.cwd)).value },
    fs: {
      stat: async (p: string) => { const f = file(p); return { kind: 'file', size: f.text.length, mtimeMs: f.at, isLink: false } },
      read: async (p: string) => file(p).text,
      list: async (dir: string) => {
        const names = [...w.files].filter(([p]) => p.startsWith(`${dir}/`) && !p.slice(dir.length + 1).includes('/'))
        if (!names.length) throw new Error(`ENOENT ${dir}`)
        return names.map(([p, f]) => ({ name: p.slice(dir.length + 1), kind: 'file', size: f.text.length, mtimeMs: f.at, isLink: false }))
      },
    },
    clock: { now: async () => w.clock.now(), every },
    state: {
      get: async (r: any) => values.get(name(r)) ?? { value: undefined, version: 0 },
      set: async (r: any, value: unknown, o?: { ifVersion?: number }) => {
        const cur = values.get(name(r)) ?? { value: undefined, version: 0 }
        if (o?.ifVersion !== undefined && o.ifVersion !== cur.version) return { isSet: false, version: cur.version }
        values.set(name(r), { value, version: cur.version + 1 })
        return { isSet: true, version: cur.version + 1 }
      },
    },
    command: { register: async (c: { name: string }) => (w.registered.push(c.name), { command: c.name }) },
    ui: {
      open: async (o: { id: string }) => (w.opened.push(o.id), { isPlaced: true }),
      close: async () => undefined,
      toast: async (text: string) => void w.toasts.push(text),
      resolve: () => ({ Box: 'Box', Text: 'Text' }),
    },
  }
  const hook = (event: string, match: (m: any) => boolean) => hooks.find(h => h.event === event && match(h.match))!.hook
  return {
    // The board the reloaded load last published: its poll's own state.
    board: () => (values.get('conveyor-belt/state/')?.value as any)?.snap,
    drawPane: () => hook('ui.render', m => m?.component === 'Pane')($r, { component: 'Pane', surface: 'terminal', props: { title: 'Conveyor', isFocused: false, bodyColumns: 72, placement: 'dock' } }, async () => ({})),
    units: async () => (await hook('command.run', m => m?.command === 'units')($r, { command: 'units', args: '', origin: { kind: 'composer' }, presentation: { layout: 'main', columns: 100 } }, async () => ({ text: 'engine' }))).text as string,
  }
}

test('register, session start, a poll publishes; register again with no session start: the next poll still publishes and /units answers with the board', async ($, on) => {
  let reload = 0
  const gated = ((event: string, ...rest: any[]) => {
    if (event !== 'clock.every') return (on as any)(event, ...rest)
    const h = rest.at(-1)
    return (on as any)(event, ...rest.slice(0, -1), async (_$: any, e: any, next: any) => {
      const at = reload
      const r = await h(_$, e, next)
      return at === reload ? r : new Promise(() => {})
    })
  }) as On
  const w = world(gated, 'main', answer(FULL))
  await start($, 'main')
  await w.clock.settle()
  expect(fetches(w).length).toBe(1)
  expect(await draw($, 'Pane')).toContain('1 ON BELT')
  expect(await units($)).toContain('ON THE BELT (1)')
  await w.clock.settle()
  expect(fetches(w).length).toBe(2)

  reload++
  const again = reloaded(w)
  w.fetch = answer(snapshot())
  await w.clock.advance(60_000)
  expect(fetches(w).length).toBe(2)
  await again.drawPane()
  await w.clock.settle()
  expect(fetches(w).length).toBe(3)
  expect(again.board()?.belt).toEqual([])
  w.fetch = answer(FULL)
  await w.clock.advance(60_000)
  expect(fetches(w).length).toBe(4)
  expect(again.board()?.belt).toHaveLength(1)
  const board = await again.units()
  expect(board).toContain('ON THE BELT (1)')
  expect(board).not.toContain('reading the Conveyor snapshot')
})

// The kit's own load with no session start is what a reload leaves, its state not yet published.
test('a load with no session start finds its checkout itself: the waiting line until its first fetch answers, then the board, polls go on and /units answers with the board', async ($, on) => {
  const w = world(on, 'main', answer(FULL))
  let release = () => {}
  w.hold = new Promise<void>(r => { release = r })
  expect(await draw($, 'Pane')).toBe('units: reading the Conveyor snapshot')
  expect(w.registered).toEqual(['units'])
  expect(fetches(w).length).toBe(1)
  w.hold = undefined
  release()
  await w.clock.advance(1000)
  expect(await draw($, 'Pane')).toContain('1 ON BELT')
  w.fetch = answer(snapshot())
  await w.clock.advance(60_000)
  expect(fetches(w).length).toBe(2)
  expect(await draw($, 'Pane')).toContain('nothing on the belt')
  expect(await units($)).toContain('the belt is empty')
  await w.clock.settle()
  expect(fetches(w).length).toBe(3)
})

test('a session start after a pane began the load starts nothing again: the board stays and no second fetch is made', async ($, on) => {
  const w = world(on, 'main', answer(FULL))
  expect(await draw($, 'Pane')).toContain('1 ON BELT')
  await start($, 'main')
  expect(fetches(w).length).toBe(1)
  expect(w.registered).toEqual(['units'])
  expect(await draw($, 'Pane')).toContain('1 ON BELT')
  await w.clock.advance(60_000)
  expect(fetches(w).length).toBe(2)
})

// a failed begin was tried again on every redraw, each with a git call.
test('a load whose first begin fails begins again at the first render a minute later, not before: /units then registers, fetches and answers with the board', async ($, on) => {
  const w = world(on, 'main', answer(FULL))
  const run = w.run
  w.run = (argv, cwd) => {
    if (argv[0] !== 'git') return run(argv, cwd)
    w.run = run
    throw new Error('git failed once')
  }
  expect(await draw($, 'Pane')).toBe('units: reading the Conveyor snapshot')
  await w.clock.settle()
  expect(w.registered).toEqual([])
  expect(fetches(w)).toEqual([])
  const gits = w.runs.length
  await w.clock.advance(59_000)
  await draw($, 'Pane')
  await w.clock.settle()
  expect(w.runs.length).toBe(gits)
  expect(w.registered).toEqual([])
  await w.clock.advance(1000)
  await draw($, 'Pane')
  expect(await units($)).toContain('ON THE BELT (1)')
  expect(w.registered).toEqual(['units'])
  expect(fetches(w).length).toBeGreaterThan(0)
})

test('a load whose first look at the checkout throws tries again at the pane a minute later: the board, not the waiting line for good', async ($, on) => {
  const w = world(on, 'main', answer(FULL))
  const run = w.run
  w.run = (argv, cwd) => {
    if (argv[0] !== 'git') return run(argv, cwd)
    w.run = run
    throw new Error('git did not start')
  }
  expect(await draw($, 'Pane')).toBe('units: reading the Conveyor snapshot')
  await w.clock.settle()
  expect(w.registered).toEqual([])
  await w.clock.advance(60_000)
  expect(await draw($, 'Pane')).toContain('1 ON BELT')
  expect(w.registered).toEqual(['units'])
  expect(fetches(w).length).toBe(1)
})

test('a load with no session start outside a checkout with a Conveyor pack still registers nothing and fetches nothing', async ($, on) => {
  const w = world(on, 'main', answer(FULL), {}, false)
  await draw($, 'Pane')
  expect(await units($)).toBe('engine')
  expect(w.registered).toEqual([])
  expect(fetches(w)).toEqual([])
})

test('a card\'s own worktree shows no view and never fetches until /units is typed there', async ($, on) => {
  const card = world(on, 'worker', answer(snapshot({ belt: [BELT] })))
  await start($, 'worker')
  await card.clock.advance(120_000)
  expect(fetches(card)).toEqual([])
  expect(card.opened).toEqual([])
  expect(await draw($, 'AbovePrompt')).toBe('engine')
  expect(await units($)).toBe('units: reading the Conveyor snapshot')
  await card.clock.settle()
  expect(fetches(card).length).toBe(1)
  expect(await units($)).toContain('ON THE BELT (1)')
  expect(card.status.filter(Boolean)).toEqual([])
})

test('a card that newly needs you or lands is a toast; what was there at the first fetch is not', async ($, on) => {
  const w = world(on, 'main', answer(snapshot({ landed: [LANDED] })))
  await start($, 'main')
  await w.clock.settle()
  expect(w.toasts).toEqual([])
  w.fetch = answer(snapshot({ needsYou: { waiting: [WAITING], blocked: [] }, landed: [LANDED, { ...LANDED, card: 'c6-3860', issue: 3860 }] }))
  await units($)
  await w.clock.settle()
  expect(w.toasts).toEqual(['#3861 needs your yes', '#3860 landed'])
  await units($)
  await w.clock.settle()
  expect(w.toasts).toHaveLength(2)
})

// Bug it catches (#355): the toasts went with the status line, which is gone; they now go with the pane, so with the
// pane off a card that newly needs you or lands shows no toast.
test('with the pane off, a card that newly needs you or lands is no toast', { options: { pane: 'off' } }, async ($, on) => {
  const w = world(on, 'main', answer(snapshot({ landed: [LANDED] })))
  await start($, 'main')
  await units($)
  await w.clock.settle()
  w.fetch = answer(snapshot({ needsYou: { waiting: [WAITING], blocked: [] }, landed: [LANDED, { ...LANDED, card: 'c6-3860', issue: 3860 }] }))
  await units($)
  await w.clock.settle()
  expect(fetches(w).length).toBe(2)
  expect(w.toasts).toEqual([])
})

// Bug it catches (#355): /units band and /units status turned on views that are gone; only the pane exists.
test('/units pane flips the pane for the session and a pane that is not placed says why; band and status are refused', async ($, on) => {
  const w = world(on, 'worker', answer(FULL))
  await start($, 'worker')
  for (const which of ['band', 'status']) expect(await units($, `${which} on`)).toBe(`units: no view "${which}"; only the pane exists: /units, or /units pane on|off`)
  w.placed = false
  expect(await units($, 'pane on')).toBe('units pane: on for this session (not drawn: no room)')
  expect(w.opened).toEqual(['units'])
  expect(await units($, 'pane off')).toBe('units pane: off for this session')
  expect(w.opened).toEqual([])
})

// The pane option set to on at setup opens the pane at session start, even in a worker checkout, where auto leaves it off.
test('with the pane option on, the session start opens the Conveyor pane with no /units pane on', { options: { pane: 'on' } }, async ($, on) => {
  const w = world(on, 'worker', answer(FULL))
  const logs: string[] = []
  on('ui.log', (_, e) => (logs.push(e.text), { value: undefined }))
  await start($, 'worker')
  expect(w.opened).toEqual(['units'])
  expect(logs).toEqual([])
})

// Bug: the pane option turned on in /config reloads the plugin with no session.start, and with the pane not open its
// render never runs: the redraw above the prompt, which /units draws nothing in, must begin the load and open it.
test('a load with no session start and the pane option on opens the pane at the first redraw above the prompt', { options: { pane: 'on' } }, async ($, on) => {
  const w = world(on, 'worker', answer(FULL))
  expect(await draw($, 'AbovePrompt')).toBe('engine')
  await w.clock.settle()
  expect(w.opened).toEqual(['units'])
})

// Bug (issue 107): the session start's open is unasked, so a terminal under the host's width floor leaves the pane
// undrawn; its reason was dropped, so the pane set to on never showed and nothing said why.
test('a pane the host does not place at session start gives the session one line with the reason and /units pane on', { options: { pane: 'on' } }, async ($, on) => {
  const w = world(on, 'worker', answer(FULL))
  const logs: string[] = []
  on('ui.log', (_, e) => (logs.push(e.text), { value: undefined }))
  w.placed = false
  await start($, 'worker')
  expect(w.opened).toEqual(['units'])
  expect(logs).toEqual(['units: the Conveyor pane is not drawn (no room); /units pane on tries again'])
})

// Bug (issue 616): the /conveyor-belt:auto band drew its view in place of the next one's, so it hid another plugin's
// view. The band and the view beneath it ('engine') are drawn, and /units draws nothing there.
test('with /conveyor-belt:auto on, the place above the prompt shows its band and the view beneath it', async ($, on) => {
  const w = world(on, 'main', answer(FULL))
  const fetch = w.run
  w.run = (argv, cwd) => argv.includes('auto') && argv.includes('band')
    ? { value: { exitCode: 0, stdout: JSON.stringify({ scope: 'full', since: '04:30', count: 2 }), stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
    : fetch(argv, cwd)
  await start($, 'main')
  await units($)
  await w.clock.settle()
  const band = await draw($, 'AbovePrompt')
  expect(band).toContain('AUTO ON since 04:30')
  expect(band).not.toContain('CONVEYOR')
  expect(band).toContain('engine')
})

// the engine ends a command.run hook at 10 s and the fetch can take 75 s, so /units never waits on it.
test('with a fetch that does not answer, /units and /units pane on answer at once; once it answers, the pane and /units show its board', async ($, on) => {
  const w = world(on, 'worker', answer(FULL))
  let release = () => {}
  w.hold = new Promise<void>(r => { release = r })
  await start($, 'worker')
  expect(await units($)).toBe('units: reading the Conveyor snapshot')
  expect(await units($, 'pane on')).toBe('units pane: on for this session')
  expect(await w.clock.now()).toBe(NOW)
  expect(await draw($, 'Pane')).toBe('units: reading the Conveyor snapshot')
  w.hold = undefined
  release()
  await w.clock.settle()
  expect(await draw($, 'Pane')).toContain('1 ON BELT')
  expect(await units($)).toContain('ON THE BELT (1)')
})

test('with motion on, the mark of a card on the belt turns once a second, and stands still once the belt is empty', { options: { motion: 'on' } }, async ($, on) => {
  const w = world(on, 'main', answer(FULL))
  await start($, 'main')
  await w.clock.settle()
  expect(await draw($, 'Pane')).toContain('◐ #3863')
  await w.clock.advance(1000)
  expect(await draw($, 'Pane')).toContain('◓ #3863')
  w.fetch = answer(snapshot())
  await units($)
  await w.clock.settle()
  await w.clock.advance(1000)
  expect(await draw($, 'Pane')).toContain('nothing on the belt')
  // Bug (#1438, O380): the empty text has no mark, so a frame timer left running passed; and its frame came back to 0 after
  // four ticks, so a later mark check could pass too. The count of frame writes shows a tick: none may come with the belt empty.
  const frames = () => w.writes.filter(k => k === 'frame').length
  const before = frames()
  await w.clock.advance(3000)
  expect(frames(), 'frame writes after the belt emptied: a timer kept turning the frame').toBe(before)
})

// Issue 497. Bug it catches: Worker activity and Landed today always wrote AM or PM, with the Time set to 24-hour.
test('with the time option 24-hour, Worker activity and Landed today write 24-hour times, with no AM or PM', { options: { time: '24-hour' } }, async ($, on) => {
  const w = world(on, 'main', answer(FULL))
  await start($, 'main')
  await w.clock.settle()
  const hm = (min: number) => { const d = new Date(NOW - min * 60_000); return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}` }
  const pane = await draw($, 'Pane')
  expect(pane).toMatch(new RegExp(`WORKER ACTIVITY. #3863  build +${hm(10)} PICK ORDER`))
  expect(pane).toMatch(new RegExp(`Cost${hm(13)} +#3862 `))
  expect(pane).not.toMatch(/\d [AP]M\b/)
})

// Issue 506. Bug it catches: with the plugin left at its default, the Board's Time set to 24-hour in Customize (the
// time.json its server keeps) did not reach the pane, which still wrote AM or PM.
test('with the Board\'s Time 24-hour and the time option left at its default, the pane writes 24-hour times', async ($, on) => {
  const w = world(on, 'main', answer(FULL), { [`${BOARD}/time.json`]: '{"time":"24-hour"}' })
  await start($, 'main')
  await w.clock.settle()
  const pane = await draw($, 'Pane')
  expect(pane).toMatch(/WORKER ACTIVITY. #3863  build +\d\d:\d\d PICK ORDER/)
  expect(pane).toMatch(/Cost\d\d:\d\d +#3862 /)
  expect(pane).not.toMatch(/\d [AP]M\b/)
})

test('outside a checkout with a Conveyor pack the mod registers nothing and fetches nothing', async ($, on) => {
  const w = world(on, 'main', answer(FULL), {}, false)
  await start($, 'main')
  expect(w.registered).toEqual([])
  expect(await units($)).toBe('engine')
  expect(fetches(w)).toEqual([])
})

// The Board's live feed: the units-feed.json (stream.json with each snapshot cut to what /units draws) it rewrites with each change Conveyor's host streams.
const FEED = `${BOARD}/units-feed.json`
// A feed outside the folder the Board's job names: the mod never reads it.
const OLD_FEED = `${HOME}/.conveyor/dashboard/units-feed.json`
// heardAt: the heartbeat, the field the Board moves on each rewrite.
const feed = (snap: string, live = true, heardAt = ago(0)) => JSON.stringify({
  host: 'buildbox', records: [{ repo: 'bookstore', snap: JSON.parse(snap) }],
  stream: { live, heardAt, since: live ? null : ago(1), error: live ? null : 'buildbox: no line in 30 s' },
})
const feeds = (w: World) => fetches(w).filter(r => r.argv.includes('feed'))

test('with the live feed fresh the board is the feed\'s, no host is asked, and a change in it is drawn within a second', async ($, on) => {
  const w = world(on, 'main', answer(FULL), { [FEED]: feed(snapshot()) })
  await start($, 'main')
  await units($)
  await w.clock.settle()
  const text = await units($)
  await w.clock.settle()
  expect(text).toContain('the belt is empty')
  expect(text).not.toContain('#3863')
  // The session knows where the feed is from its start: no fetch asks the host.
  expect(fetches(w).map(r => r.argv.includes('feed'))).toEqual([true, true, true])
  // The feed changes: a card is on the belt. No /units, no fetch: the next second draws it.
  const before = fetches(w).length
  w.files.set(FEED, { text: feed(snapshot({ belt: [BELT] })), at: NOW + 500 })
  await w.clock.advance(1000)
  expect(await draw($, 'Pane')).toContain('#3863')
  expect(fetches(w).length).toBe(before)
  // While the feed runs, the short check asks nothing: the feed already gives each change.
  await w.clock.advance(5000)
  expect(checks(w)).toEqual([])
})

test('a live feed that is down still shows its last board, and says the stream is down', async ($, on) => {
  const w = world(on, 'main', answer(snapshot()), { [FEED]: feed(snapshot({ belt: [BELT] }), false) })
  await start($, 'main')
  await units($)
  await w.clock.settle()
  const text = await units($)
  expect(text).toContain('#3863')
  expect(text).toMatch(/units: the live stream is down \(buildbox: no line in 30 s\); the board is as buildbox was at \d+:\d\d [AP]M/)
  expect(fetches(w).at(-1)?.argv).toContain('feed')
})

// Issue 1461 (B-R440). Bug it catches: the feed's board was built, with its down note's time, before the poll read the
// Board's Time, and while the stream stayed down its text (and so its built board) did not change: the note kept
// "3:04 PM" with the Board's Time 24-hour, while Worker activity wrote 24-hour.
test('a live feed that is down says when it was last heard in the Board\'s 24-hour Time', async ($, on) => {
  const heard = new Date(NOW - 86_400_000)
  heard.setHours(15, 4, 0, 0)
  const w = world(on, 'main', answer(snapshot()), { [FEED]: feed(snapshot({ belt: [BELT] }), false, heard.toISOString()), [`${BOARD}/time.json`]: '{"time":"24-hour"}' })
  await start($, 'main')
  await w.clock.settle()
  const text = await units($)
  expect(text).toContain('the board is as buildbox was at 15:04')
  expect(text).not.toContain('3:04 PM')
})

// Bug: the feed's board took its first record for the session's own, whatever record the fetch named: a session in
// gadgetlab showed bakery's card as #12.
test('the live feed\'s board takes the session\'s own project from the fetch: a session in the second project', async ($, on) => {
  const records = TWO_PROJECTS.split('\n').slice(3, 5).map(l => ({ repo: l.split('\t')[0], snap: JSON.parse(l.slice(l.indexOf('\t') + 1)) }))
  const w = world(on, 'main', 'paths\t\t/r/home\tgadgetlab\nfast\tnone\nhost\t\tfeed\t0\n', { [FEED]: JSON.stringify({ host: 'lab', records, stream: { live: true, heardAt: ago(0) } }) })
  await start($, 'main')
  await units($)
  await w.clock.settle()
  expect(await units($)).toMatch(/\n bakery#12 Bread oven timer [^]*\n #7 Gear ratio chart /)
  expect(fetches(w).at(-1)?.argv).toContain('feed')
})

test('a feed file the collector no longer writes is no feed: the fetch asks the host', async ($, on) => {
  const w = world(on, 'main', answer(FULL), { [FEED]: feed(snapshot()) })
  w.files.set(FEED, { text: feed(snapshot()), at: NOW - 60_000 })
  await start($, 'main')
  await units($)
  await w.clock.settle()
  expect(await units($)).toContain('#3863')
  expect(feeds(w)).toEqual([])
})

// a feed or limit file over the cap was skipped with no word, and /units went blank once the snapshot passed 4 MB.
test('a feed and a limit file over the cap are not read: a line names each one\'s size and the cap, over the host\'s board or as its one line', async ($, on) => {
  const w = world(on, 'main', answer(FULL), { [FEED]: ' '.repeat(4_500_000), [LIMIT]: ' '.repeat(20_000) })
  await start($, 'main')
  await units($)
  await w.clock.settle()
  const text = await units($)
  expect(text).toContain('#3863')
  expect(text).toContain("units: the Board's live feed (units-feed.json) is 4.5 MB, over the 4.2 MB cap; it is not read, reading the host")
  expect(text).toContain("units: the Board's limit file (limit.json) is 20000 bytes, over the 16384 byte cap; the usage limit is not read")
  expect(feeds(w)).toEqual([])
  expect(w.reads).not.toContain(LIMIT)
  w.fetchRc = 3
  await units($)
  await w.clock.settle()
  expect(await draw($, 'Pane')).toBe("units: the Board's live feed (units-feed.json) is 4.5 MB, over the 4.2 MB cap; it is not read, reading the host; units: the Board's limit file (limit.json) is 20000 bytes, over the 16384 byte cap; the usage limit is not read; units: the Conveyor snapshot cannot be read (the fetch did not run)")
})

// #1287: /units read stream.json, whose snapshots hold the Tests page's history (tests, testActions), and refused it
// over the cap: the pane showed no board and the host fallback timed out. It reads units-feed.json, the same cut to what
// it draws. The Board's own whole feed, here 4.5 MB, is never read or stat-checked against the cap.
test('with the Board\'s whole feed over the cap, the board is drawn from the units feed beside it: no over-cap line, no host read, the whole feed never read', async ($, on) => {
  const whole = `${BOARD}/stream.json`
  const w = world(on, 'main', answer(FULL), { [FEED]: feed(snapshot({ belt: [BELT] })), [whole]: ' '.repeat(4_500_000) })
  await start($, 'main')
  await units($)
  await w.clock.settle()
  const text = await units($)
  expect(text).toContain('#3863')
  expect(text).not.toContain('over the 4.2 MB cap')
  expect(w.reads, 'the whole feed was read').not.toContain(whole)
  expect(feeds(w).length, 'the board was not the feed\'s').toBeGreaterThan(0)
})

// #858: /units read the whole data.js for the limit and refused it past 4 MiB, which data.js outgrew (the Tests
// panel grows with every project's tests): the pane lost the weekly limit and its pause warning.
test('the limit is read from limit.json, whatever data.js\'s size: no over-cap line, and data.js is never read', async ($, on) => {
  const w = world(on, 'main', answer(FULL), { [DATA]: ' '.repeat(4_600_000), [LIMIT]: limitJson(34, new Date(NOW + 5 * 3600_000).toISOString()) })
  await start($, 'main')
  await w.clock.settle()
  const text = await units($)
  expect(text).toContain('weekly limit 34% · resets 5h 0m')
  expect(text).not.toContain('over the')
  expect(w.reads).not.toContain(DATA)
})

// #858: a Board folder an older engine writes has no limit.json; the limit must read "not read" with a line naming
// the missing file, never a limit taken from data.js nor data.js's size.
test('a Board folder with data.js and no limit.json: the limit is not read, and the line names limit.json', async ($, on) => {
  const w = world(on, 'main', answer(FULL), { [DATA]: `window.DASH = ${JSON.stringify({ panels: { health: { data: { limit: { usedPct: 34, resetsAt: '2026-11-12T00:00:00Z' } } } } })};` })
  await start($, 'main')
  await w.clock.settle()
  const text = await units($)
  expect(text).toContain('weekly limit not read')
  expect(text).toContain("units: the Board's folder has data.js but no limit.json (the Board runs an older engine); the usage limit is not read")
  expect(w.reads).not.toContain(DATA)
})

// the engine refuses a read over 4 MiB, so under the old 32 MB cap a 4.5 MB feed failed its read without a word,
// left the feed's last board drawn and was tried again every second.
test('a drawn feed that grows to 4.5 MB is not read again: the host is read at once, under the over-cap line, and no later second reads it', async ($, on) => {
  const w = world(on, 'main', answer(FULL), { [FEED]: feed(snapshot({ belt: [{ ...BELT, issue: 6175 }] })) })
  await start($, 'main')
  await units($)
  await w.clock.settle()
  expect(await units($)).toContain('#6175')
  await w.clock.settle()
  w.files.set(FEED, { text: ' '.repeat(4_500_000), at: NOW + 500 })
  const [reads, polls] = [w.reads.filter(p => p === FEED).length, fetches(w).length]
  await w.clock.advance(1000)
  await w.clock.settle()
  expect(fetches(w).length).toBe(polls + 1)
  expect(await draw($, 'Pane')).toContain('#3863')
  await w.clock.advance(5000)
  await w.clock.settle()
  expect(w.reads.filter(p => p === FEED).length).toBe(reads)
  expect(fetches(w).length).toBe(polls + 1)
  expect(await units($)).toContain("units: the Board's live feed (units-feed.json) is 4.5 MB, over the 4.2 MB cap; it is not read, reading the host")
})

// the engine keeps a command's first 4 MiB of output; a cut snapshot was parsed as if whole.
test('a fetch whose output was cut short is its own cannot-be-read line', async ($, on) => {
  const w = world(on, 'main', answer(FULL))
  w.fetchCut = true
  await start($, 'main')
  await w.clock.settle()
  expect(await units($)).toBe('units: the Conveyor snapshot cannot be read (the fetch printed over the 4.2 MB cap and was cut short)')
})

// the data file (1.1 MB on the Mac) was read and parsed on every poll; the limit file must not be.
test('the limit file is parsed again only when its write time changes', async ($, on) => {
  const resets = new Date(NOW + 5 * 3600_000).toISOString()
  const w = world(on, 'main', answer(FULL), { [LIMIT]: limitJson(34, resets) })
  await start($, 'main')
  await w.clock.settle()
  const dataReads = () => w.reads.filter(p => p === LIMIT).length
  expect(dataReads()).toBe(1)
  await w.clock.advance(60_000)
  await w.clock.settle()
  expect(fetches(w).length).toBe(2)
  expect(dataReads()).toBe(1)
  w.files.set(LIMIT, { text: limitJson(50, resets), at: NOW + 61_000 })
  await w.clock.advance(60_000)
  await w.clock.settle()
  expect(dataReads()).toBe(2)
  expect(await units($)).toContain('weekly limit 50%')
})

// a feed board laid over the state, by the second's read or by a poll whose fetch answered after it,
// replaced the notes and took the limit file's over-cap line with them.
test('the limit file\'s over-cap line stays under a board the feed changes, each second and after a slow poll', async ($, on) => {
  const line = "units: the Board's limit file (limit.json) is 20000 bytes, over the 16384 byte cap; the usage limit is not read"
  const w = world(on, 'main', answer(FULL), { [FEED]: feed(snapshot()), [LIMIT]: ' '.repeat(20_000) })
  await start($, 'main')
  await units($)
  await w.clock.settle()
  expect(await units($)).toContain(line)
  w.files.set(FEED, { text: feed(snapshot({ belt: [BELT] })), at: NOW + 500 })
  await w.clock.advance(1000)
  const pane = await draw($, 'Pane')
  expect(pane).toContain('#3863')
  expect(pane).toContain(line)
  let release = () => {}
  w.hold = new Promise<void>(r => { release = r })
  // The poll reads the feed, then waits on its fetch; the feed changes and is drawn meanwhile.
  await units($)
  await w.clock.settle()
  w.files.set(FEED, { text: feed(snapshot({ belt: [{ ...BELT, issue: 6173 }] })), at: NOW + 1500 })
  await w.clock.advance(1000)
  w.hold = undefined
  release()
  await w.clock.settle()
  const after = await draw($, 'Pane')
  expect(after).toContain('#6173')
  expect(after).toContain(line)
  // A poll whose host read fails cleared the line, and the next feed board was drawn without it.
  w.fetchRc = 3
  await units($)
  await w.clock.settle()
  w.files.set(FEED, { text: feed(snapshot({ belt: [{ ...BELT, issue: 6174 }] })), at: NOW + 2500 })
  await w.clock.advance(1000)
  const failed = await draw($, 'Pane')
  expect(failed).toContain('#6174')
  expect(failed).toContain(line)
})

// a feed board with no snapshot is drawn as its note alone; the over-cap line went only into the notes, so no
// view showed it, whether the second's read or a slow poll laid that board over the state.
test('the limit file\'s over-cap line leads the one line drawn when the feed gives no snapshot, each second and after a slow poll', async ($, on) => {
  const line = "units: the Board's limit file (limit.json) is 20000 bytes, over the 16384 byte cap; the usage limit is not read"
  const none = `${line}; units: the Conveyor snapshot cannot be read (buildbox gave no snapshot)`
  const w = world(on, 'main', answer(FULL), { [FEED]: feed(snapshot()), [LIMIT]: ' '.repeat(20_000) })
  await start($, 'main')
  await units($)
  await w.clock.settle()
  w.files.set(FEED, { text: feed('null'), at: NOW + 500 })
  await w.clock.advance(1000)
  expect(await draw($, 'Pane')).toBe(none)
  let release = () => {}
  w.hold = new Promise<void>(r => { release = r })
  // The poll reads the snapshot feed, then waits on its fetch; the feed loses its snapshot meanwhile.
  w.files.set(FEED, { text: feed(snapshot()), at: NOW + 1000 })
  await w.clock.advance(1000)
  await units($)
  await w.clock.settle()
  w.files.set(FEED, { text: feed('null'), at: NOW + 2500 })
  await w.clock.advance(1000)
  w.hold = undefined
  release()
  await w.clock.settle()
  expect(await draw($, 'Pane')).toBe(none)
})

// the Board writes its feed in its own folder; a mod reading a fixed folder finds no fresh file there and asks the
// host for a full snapshot on every poll.
test('a fresh feed in the folder the Board names, with none at the old path, is drawn and no host is asked', async ($, on) => {
  const w = world(on, 'main', answer(FULL), { [FEED]: feed(snapshot({ belt: [{ ...BELT, issue: 6134 }] })) })
  await start($, 'main')
  await units($)
  await w.clock.settle()
  const text = await units($)
  expect(text).toContain('#6134')
  expect(text).not.toContain('#3863')
  expect(text).not.toContain("feed's folder")
  expect(fetches(w).length).toBeGreaterThan(0)
  expect(feeds(w)).toEqual(fetches(w))
  expect(w.runs.filter(r => r.argv[3] === 'units-feed').every(r => r.cwd === MAIN)).toBe(true)
})

test('with no feed folder to name, the board is the host\'s, a feed at the old path is not read, the note says the folder was not found, and a later poll that names it reads the feed', async ($, on) => {
  const w = world(on, 'main', answer(FULL), { [OLD_FEED]: feed(snapshot()) })
  w.boardDir = null
  await start($, 'main')
  await units($)
  await w.clock.settle()
  const text = await units($)
  expect(text).toContain('#3863')
  expect(text).toContain("units: the live feed's folder was not found (no Board job here, or its state folder cannot be named); reading the host")
  expect(feeds(w)).toEqual([])
  // The Board's folder can be named again: the next poll asks for it, reads its feed and drops the note.
  w.boardDir = BOARD
  w.files.set(FEED, { text: feed(snapshot()), at: NOW })
  await units($)
  await w.clock.settle()
  const after = await units($)
  expect(after).toContain('the belt is empty')
  expect(after).not.toContain("feed's folder")
})

test('a feed that stops changing while its board is drawn is said to be old at once, and the host is read without waiting for the minute', async ($, on) => {
  const w = world(on, 'main', answer(FULL), { [FEED]: feed(snapshot()) })
  await start($, 'main')
  await units($)
  expect(await draw($, 'Pane')).toContain('nothing on the belt')
  // The collector stops: the feed file stays as it was. Its fetch of the host is held, so the warning is seen first.
  let release = () => {}
  w.hold = new Promise<void>(r => { release = r })
  await w.clock.advance(30_000)
  const pane = await draw($, 'Pane')
  expect(pane).toMatch(/units: the live feed has stopped \(its file is \d+ s old\)/)
  expect(pane).toContain('nothing on the belt')
  w.hold = undefined
  release()
  await w.clock.advance(1000)
  expect(await draw($, 'Pane')).toContain('#3863')
  expect(fetches(w).at(-1)?.argv).not.toContain('feed')
})

test('a running step\'s live fields from the feed are drawn: what it is doing, its turns, the seconds since its last output', async ($, on) => {
  const live = { ...BELT, live: { action: 'Bash: npm test', turns: 3, lastOutputAt: new Date(NOW - 6000).toISOString() } }
  const w = world(on, 'main', answer(FULL), { [FEED]: feed(snapshot({ belt: [live] })) })
  await start($, 'main')
  await w.clock.settle()
  expect(await units($)).toContain('    now Bash: npm test · 3 turns · last output 6s ago')
})

// the Test step runs no model; its live line shows how far the tests are in place of its turns.
test('a card in its Test step draws its tests, or else its test files, in place of turns; a Build step still draws its turns', async ($, on) => {
  const track = (at: number, over: object) => ({
    steps: ['Build', 'Review', 'Fix', 'Test', 'Land', 'Push'].map((name, i) => ({ name, state: i < at ? 'done' : i === at ? 'now' : 'todo', sec: i < at ? 30 : null })),
    at, label: at === 3 ? 'tests' : 'building', since: ago(1), reason: null, files: null, ...over,
  })
  const live = { action: '', turns: 0, lastOutputAt: new Date(NOW - 23_000).toISOString() }
  const belt = [
    { ...BELT, live, track: track(3, { tests: { done: 3, of: 5, failed: 1 } }) },
    { ...BELT, card: 'c4', issue: 3864, live, track: track(3, { files: { run: 3, of: 6 } }) },
    { ...BELT, card: 'c5', issue: 3865, live: { ...live, turns: 4 }, track: track(0, {}) },
    // #360: a run of more files than it selected shows them apart, not as a count above its total.
    { ...BELT, card: 'c6', issue: 3866, live, track: track(3, { files: { run: 86, of: 86, over: 15 } }) },
  ]
  const w = world(on, 'main', answer(FULL), { [FEED]: feed(snapshot({ belt })) })
  await start($, 'main')
  await w.clock.settle()
  const lines = (await units($)).split('\n').filter(l => l.includes('last output'))
  expect(lines.slice(0, 2).join('\n')).not.toMatch(/turn/)
  expect(lines).toEqual(['    3 of 5 tests · 1 failed · last output 23s ago', '    3 of 6 test files · last output 23s ago', '    4 turns · last output 23s ago',
    '    86 of 86 test files · 15 more files than selected · last output 23s ago'])
})

// Bug it catches (#433): a card running its test files one at a time read "25 of 25 tests" (the cases of the files that
// had ended, taken as the whole) and named no file, so a slow file and a hung run looked the same; and its Test step's
// time was all its runs' added up. Its third run, given 3 files, 2 minutes into the second: its line names the file,
// which of how many and its time on it, with the failed count and no case total; the step's time is this run's (1m),
// and all three runs' time (an hour before it, and this run's) is said apart.
test('a card running its test files one at a time draws the file that runs and its time; its third run apart from all its runs', async ($, on) => {
  const steps = ['Build', 'Review', 'Fix', 'Test', 'Land', 'Push'].map((name, i) => ({ name, state: i < 3 ? 'done' : i === 3 ? 'now' : 'todo', sec: i < 3 ? 30 : i === 3 ? 3600 : null, ...(i === 3 ? { n: 3 } : {}) }))
  const track = { steps, at: 3, label: 'tests', since: ago(1), reason: null, tests: { done: 25, of: 25, failed: 3 },
    files: { run: 1, of: 3, now: { file: 'conveyor/tests/b.test.sh', at: ago(2) } } }
  const live = { action: '', turns: 0, lastOutputAt: new Date(NOW - 23_000).toISOString() }
  const w = world(on, 'main', answer(FULL), { [FEED]: feed(snapshot({ belt: [{ ...BELT, live, track }] })) })
  await start($, 'main')
  await w.clock.settle()
  const out = await units($)
  expect(out.split('\n').filter(l => l.includes('last output'))).toEqual(['    file 2 of 3: conveyor/tests/b.test.sh, 2m, 3 failed · last output 23s ago'])
  expect(out).toContain('testing 1m · 3rd run, 1h 1m in all')
  expect(out).not.toMatch(/25 of 25/)
})

// Bug it catches (#147): /units did not say whether a card's test step ran the tests its change touched or the whole
// suite. Its card's line names the list the run was given (the track's list) before how many files ran.
test('a card in its Test step names the changed tests it was given, or the whole suite, in its line', async ($, on) => {
  const track = (list: object) => ({
    steps: ['Build', 'Review', 'Fix', 'Test', 'Land', 'Push'].map((name, i) => ({ name, state: i < 3 ? 'done' : i === 3 ? 'now' : 'todo', sec: i < 3 ? 30 : null })),
    at: 3, label: 'tests', since: ago(1), reason: null, files: { run: 2, of: null }, list,
  })
  const live = { action: '', turns: 0, lastOutputAt: new Date(NOW - 23_000).toISOString() }
  const belt = [
    { ...BELT, live, track: track({ mode: 'changed', files: 7 }) },
    { ...BELT, card: 'c4', issue: 3864, live, track: track({ mode: 'whole', why: 'package.json: shared setup or config' }) },
  ]
  const w = world(on, 'main', answer(FULL), { [FEED]: feed(snapshot({ belt })) })
  await start($, 'main')
  await w.clock.settle()
  const lines = (await units($)).split('\n').filter(l => l.includes('last output'))
  expect(lines).toEqual(['    changed: 7 files · 2 test files · last output 23s ago', '    whole suite · 2 test files · last output 23s ago'])
})

test('a quiet running step\'s seconds since its last output count on each second while the feed does not change', async ($, on) => {
  const live = { ...BELT, live: { action: 'Bash: npm test', turns: 3, lastOutputAt: new Date(NOW - 6000).toISOString() } }
  const w = world(on, 'main', answer(FULL), { [FEED]: feed(snapshot({ belt: [live] })) })
  await start($, 'main')
  await units($)
  await w.clock.settle()
  // The pane's activity line gives no seconds since the last output; /units does.
  expect(await units($)).toContain('last output 6s ago')
  await w.clock.advance(3000)
  expect(await units($)).toContain('last output 9s ago')
})

test('a fresh session draws the live feed within a second while its first fetch is still waiting on a slow read', async ($, on) => {
  const w = world(on, 'main', answer(FULL), { [FEED]: feed(snapshot({ belt: [BELT] })) })
  let release = () => {}
  w.hold = new Promise<void>(r => { release = r })
  await start($, 'main')
  await w.clock.advance(1000)
  expect(await draw($, 'Pane')).toContain('#3863')
  w.hold = undefined
  release()
})

// Issue 506. Bug it catches: the board the live feed draws before the first fetch answers kept the plugin's default
// 12-hour Time, with the Board's Time (time.json) set to 24-hour.
test('the live feed\'s board drawn before the first fetch answers writes the Board\'s 24-hour Time', async ($, on) => {
  const w = world(on, 'main', answer(FULL), { [FEED]: feed(FULL), [`${BOARD}/time.json`]: '{"time":"24-hour"}' })
  let release = () => {}
  w.hold = new Promise<void>(r => { release = r })
  await start($, 'main')
  await w.clock.advance(1000)
  const pane = await draw($, 'Pane')
  expect(pane).toMatch(/WORKER ACTIVITY. #3863  build +\d\d:\d\d PICK ORDER/)
  expect(pane).not.toMatch(/\d [AP]M\b/)
  w.hold = undefined
  release()
})

test('a feed change a poll read before its fetch stalled is drawn within a second, not when the fetch answers', async ($, on) => {
  const w = world(on, 'main', answer(FULL), { [FEED]: feed(snapshot()) })
  await start($, 'main')
  await units($)
  expect(await draw($, 'Pane')).toContain('nothing on the belt')
  // A card goes on the belt; a poll reads the feed at once, then its fetch (the Fast lane read) stalls.
  w.files.set(FEED, { text: feed(snapshot({ belt: [BELT] })), at: NOW + 500 })
  let release = () => {}
  w.hold = new Promise<void>(r => { release = r })
  const out = units($)
  await w.clock.advance(1000)
  expect(await draw($, 'Pane')).toContain('#3863')
  w.hold = undefined
  release()
  await out
  expect(await draw($, 'Pane')).toContain('#3863')
})

test('a control change in the feed (conveyor.sh control pause, then stop) is drawn within a second, and the running loop says nothing', async ($, on) => {
  const w = world(on, 'main', answer(FULL), { [FEED]: feed(snapshot({ health: { loop: true, state: 'running' } })) })
  await start($, 'main')
  await units($)
  expect(await draw($, 'Pane')).not.toMatch(/paused|stopped/)
  w.files.set(FEED, { text: feed(snapshot({ health: { loop: true, state: 'paused' } })), at: NOW + 500 })
  await w.clock.advance(1000)
  expect(await draw($, 'Pane')).toContain('bookstore paused')
  w.files.set(FEED, { text: feed(snapshot({ health: { loop: true, state: 'stopped' } })), at: NOW + 1500 })
  await w.clock.advance(1000)
  expect(await draw($, 'Pane')).toContain('bookstore stopped')
  expect(await units($)).toContain('bookstore stopped')
  // a loop that cannot read its control record says so, with the reason.
  w.files.set(FEED, { text: feed(snapshot({ health: { loop: true, state: 'control record unreadable', reason: 'cap 10' } })), at: NOW + 2500 })
  await w.clock.advance(1000)
  expect(await units($)).toContain('bookstore control record unreadable: cap 10')
})

test('a poll whose fetch answers after the feed changed twice keeps the newest board, and a later second does not undo it', async ($, on) => {
  const w = world(on, 'main', answer(FULL), { [FEED]: feed(snapshot()) })
  await start($, 'main')
  await units($)
  let release = () => {}
  w.hold = new Promise<void>(r => { release = r })
  const out = units($)
  w.files.set(FEED, { text: feed(snapshot({ health: { state: 'paused' } })), at: NOW + 500 })
  await w.clock.advance(1000)
  w.files.set(FEED, { text: feed(snapshot({ belt: [BELT], health: { state: 'paused' } })), at: NOW + 1500 })
  await w.clock.advance(1000)
  w.hold = undefined
  release()
  await out
  const pane = await draw($, 'Pane')
  expect(pane).toContain('#3863')
  expect(pane).toContain('bookstore paused')
  await w.clock.advance(1000)
  expect(await draw($, 'Pane')).toContain('#3863')
})

test('a feed that comes back while a slow fetch runs is drawn within a second, and the fetch does not draw over it', async ($, on) => {
  const w = world(on, 'main', answer(snapshot()))
  await start($, 'main')
  await units($)
  let release = () => {}
  w.hold = new Promise<void>(r => { release = r })
  await w.clock.advance(60_000)
  w.files.set(FEED, { text: feed(snapshot({ belt: [BELT] })), at: NOW + 60_500 })
  await w.clock.advance(1000)
  expect(await draw($, 'Pane')).toContain('#3863')
  w.hold = undefined
  release()
  await w.clock.advance(1000)
  expect(await draw($, 'Pane')).toContain('#3863')
})

// a running step wrote a new state each second, so the toast check (which runs on each state written) ran again
// with nothing changed. The views' clock is its own atom.
test('a second with a running step and no board change writes no state, so makes no toast check; only the views\' clock moves', async ($, on) => {
  const live = { ...BELT, live: { action: 'Bash: npm test', turns: 3, lastOutputAt: new Date(NOW - 6000).toISOString() } }
  const w = world(on, 'main', answer(FULL), { [FEED]: feed(snapshot({ belt: [live] })) })
  await start($, 'main')
  await w.clock.advance(1000)
  const states = () => w.writes.filter(k => k === 'state').length
  const before = states()
  expect(before).toBeGreaterThan(0)
  await w.clock.advance(1000)
  expect(states()).toBe(before)
  expect(await units($)).toContain('last output 8s ago')
})

// the session start waited up to 5 s for the script that names the feed folder.
test('the session start returns before the feed-folder script answers; the feed is drawn within a second once it does, from one run of it', async ($, on) => {
  const w = world(on, 'main', answer(FULL), { [FEED]: feed(snapshot({ belt: [{ ...BELT, issue: 6176 }] })) })
  const run = w.run
  let named = () => {}
  const slow = new Promise<void>(r => { named = r })
  w.run = (argv, cwd) => (argv[3] === 'units-feed' ? slow.then(() => run(argv, cwd)) : run(argv, cwd))
  let started = false
  void start($, 'main').then(() => { started = true })
  await w.clock.settle()
  expect(started).toBe(true)
  // The first poll waits on the same run: a fetch now would ask the host for want of the folder.
  expect(fetches(w)).toEqual([])
  named()
  await w.clock.advance(1000)
  expect(await draw($, 'Pane')).toContain('#6176')
  expect(w.runs.filter(x => x.argv[3] === 'units-feed').length).toBe(1)
})

// units-feed.json is rewritten at least every 10 s, changed or not, and each rewrite was parsed into a new board.
test('a units-feed.json rewrite with only the heartbeat changed builds no new board; a change in the board is drawn', async ($, on) => {
  const w = world(on, 'main', answer(FULL), { [FEED]: feed(snapshot()) })
  await start($, 'main')
  await w.clock.advance(1000)
  const states = () => w.writes.filter(k => k === 'state').length
  const before = states()
  w.files.set(FEED, { text: feed(snapshot(), true, ago(-1)), at: NOW + 1500 })
  await w.clock.advance(1000)
  expect(states()).toBe(before)
  w.files.set(FEED, { text: feed(snapshot({ belt: [BELT] }), true, ago(-2)), at: NOW + 2500 })
  await w.clock.advance(1000)
  expect(states()).toBe(before + 1)
  expect(await draw($, 'Pane')).toContain('#3863')
})

// each /units queued another full fetch (bash, four git calls; ssh with no feed) behind the one out.
test('with a fetch out and one waiting, three more /units in a row start no new fetch', async ($, on) => {
  const w = world(on, 'main', answer(FULL))
  let release = () => {}
  w.hold = new Promise<void>(r => { release = r })
  await start($, 'main')
  await w.clock.settle()
  void units($)
  for (let i = 0; i < 3; i++) await units($)
  w.hold = undefined
  release()
  await w.clock.settle()
  expect(fetches(w).length).toBe(2)
})

// The Foreman indicator (issue 47). Bugs: the Foreman lost its role on a restart, or its waiter or a watcher was gone,
// or the waiter ran on a deleted install, and /units said nothing, so the owner learnt it only when cards landed or
// blocked with no word from the Foreman. The fetch's foreman line (units-fetch.test.sh reads it from a fixture
// Foreman folder with a live stand-in waiter) is given here; this session's id is `me`. One case a fixture.
const COMMIT_A = 'a'.repeat(40)
const COMMIT_B = 'b'.repeat(40)
const UP = 'conveyor:up limit:up alerts:up idle:up'
const withForeman = (fields: string[]) => answer(FULL).replace('\nhost\t', `\nforeman\t${fields.join('\t')}\nhost\t`)
const foremanWorld = async ($: any, on: On, fetch: string) => {
  const w = world(on, 'main', fetch)
  on('session.id', () => ({ value: 'me' }))
  await start($, 'main')
  await w.clock.settle()
  return { w, text: await units($) }
}

test('D1: this session holds the role and its live waiter runs the current install: Foreman listening, in /units and the pane', async ($, on) => {
  const { text } = await foremanWorld($, on, withForeman(['me', '4242', COMMIT_A, 'me', '1', COMMIT_A, UP]))
  expect(text).toContain('\nForeman listening\n  role: me (this one) · waiter 4242 on aaaaaaa · watchers: conveyor up, limit up, alerts up, idle up\n')
  const pane = await draw($, 'Pane')
  expect(pane).toContain('Foreman listening')
  // Issue 497: in the pane the details are under Machine details, closed until its Button is pressed. Bug it
  // catches: the waiter and watchers took four lines at the top of the pane, or the Button opened nothing.
  expect(pane).not.toContain('role: me')
  await pressDetails($)
  const open = await draw($, 'Pane')
  expect(open).toContain('role: me (this one) · waiter 4242 on aaaaaaa')
  // Bug: the details were cut at the pane's 72 columns and at a narrow /units, so the last watchers' states were lost.
  expect(open).toContain('alerts up, idle up')
  await pressDetails($)
  expect(await draw($, 'Pane')).not.toContain('role: me')
  const narrow = (await $.command.run({ command: 'units', args: '', origin: { kind: 'composer' }, presentation: { layout: 'main', columns: 40 } })).text as string
  expect(narrow).toContain('\nForeman listening\n  role: me (this one) ·\n    waiter 4242 on aaaaaaa ·\n    watchers: conveyor up, limit up,\n    alerts up, idle up\n')
})

const notListening: [string, string[], string][] = [
  ['D2: the role is held by another session', ['other', '4242', COMMIT_A, 'other', '1', COMMIT_A, UP], 'not the Foreman session'],
  ['D2: the role is held by no session', ['', '', '', '', '0', COMMIT_A, ''], 'not the Foreman session'],
  ['D3: no live waiter', ['me', '4242', COMMIT_A, 'me', '0', COMMIT_A, ''], 'no waiter running'],
  // Issue 215: the owner saw the watcher as down while it was only being started again, and never why one was down.
  ['a waiter that ended under a minute ago', ['me', '4242', COMMIT_A, 'me', '0', COMMIT_A, '', 'starting again'], 'waiter starting again'],
  ['a waiter down for over a minute, with why', ['me', '4242', COMMIT_A, 'me', '0', COMMIT_A, '', "down: the session's process 77 has ended"],
    "waiter down: the session's process 77 has ended"],
  ['D3: the waiter names a commit other than the project\'s current one', ['me', '4242', COMMIT_B, 'me', '1', COMMIT_A, UP], 'waiter on an old install'],
  ['a watcher has exited and not come back', ['me', '4242', COMMIT_A, 'me', '1', COMMIT_A, 'conveyor:up limit:up alerts:up idle:down'], 'watcher down: idle'],
]
for (const [what, fields, why] of notListening) {
  test(`${what}: Foreman not listening: ${why}, in /units and the pane`, async ($, on) => {
    const { text } = await foremanWorld($, on, withForeman(fields))
    expect(text).toContain(`\nForeman not listening: ${why}\n`)
    expect(text).not.toContain('Foreman listening')
    expect(await draw($, 'Pane')).toContain(`Foreman not listening: ${why}`)
  })
}

// Issue 139: a plugin problem the Foreman noted needs the owner, who alone can fix or file it in the plugin's
// repository. Bug it catches: the note sat in its file and /units never said so. Bug (review): the file was a bare
// path, which a terminal does not open: it is a file:// link, its space encoded so the link is whole.
test('plugin problems the Foreman noted: "N plugin problems noted" with a link to the file, in /units and the pane', async ($, on) => {
  const fetch = withForeman(['me', '4242', COMMIT_A, 'me', '1', COMMIT_A, UP]).replace('\nhost\t', '\npluginbugs\t2\t/r/my main/conveyor/state/foreman/plugin-bugs.md\nhost\t')
  const { text } = await foremanWorld($, on, fetch)
  expect(text).toContain('\n2 plugin problems noted\n  file:///r/my%20main/conveyor/state/foreman/plugin-bugs.md\n')
  // The pane says it on its status line, in the warning colour's `!` form.
  expect(await draw($, 'Pane')).toContain('! 2 plugin problems')
})

// Issue 383: /units ran the plugin copy's fetch, an older one than the engine that wrote waiter.pid with four fields;
// it read `<session's process> <session>` as the waiter's session, which never equals this one, so /units said the
// Foreman was not listening while it was. Here the plugin copy's fetch answers that misread, and the fetch of the
// install of the commit this machine took (a pack that follows main) answers as the engine that wrote the file.
const INSTALL = `${HOME}/.local/share/conveyor/versions/${COMMIT_A}/hooks/units-fetch.sh`
const installWorld = (on: On, pack: object, files: Record<string, string>) => {
  const w = world(on, 'main', '', files, true, { HOME })
  w.files.set(`${MAIN}/.conveyor/project.json`, { text: JSON.stringify(pack), at: 0 })
  on('session.id', () => ({ value: 'me' }))
  const run = w.run
  w.run = (argv, cwd) => {
    if (argv[0] === 'bash' && argv[1]?.endsWith('/hooks/units-fetch.sh'))
      w.fetch = withForeman(['me', '4242', COMMIT_A, argv[1] === INSTALL ? 'me' : '30156 me', '1', COMMIT_A, UP])
    return run(argv, cwd)
  }
  return w
}

test('issue 383: the fetch runs from the install of the engine the project took, so a four-field waiter.pid reads as listening', async ($, on) => {
  const w = installWorld(on, { plugin: { follow: 'main' } }, { [`${MAIN}/.git/conveyor-engine.json`]: JSON.stringify({ commit: COMMIT_A }), [INSTALL]: '#!/bin/bash' })
  await start($, 'main')
  await w.clock.settle()
  expect(fetches(w).length).toBeGreaterThan(0)
  expect(fetches(w).every(r => r.argv[1] === INSTALL)).toBe(true)
  expect(await units($)).toContain('\nForeman listening\n')
})

// The other side: a pack whose pinned commit has no install on this machine yet still gets a fetch (the plugin's own).
test('issue 383: a pinned commit with no install yet runs the plugin copy\'s fetch', async ($, on) => {
  const w = installWorld(on, { plugin: { commit: COMMIT_A } }, {})
  await start($, 'main')
  await w.clock.settle()
  expect(fetches(w).length).toBeGreaterThan(0)
  expect(fetches(w).every(r => r.argv[1] !== INSTALL)).toBe(true)
  expect(await units($)).toContain('\nForeman not listening')
})

test('D4: no Foreman is expected (the fetch prints no foreman line): no indicator anywhere', async ($, on) => {
  const { text } = await foremanWorld($, on, answer(FULL))
  expect(text).not.toContain('Foreman')
  expect(await draw($, 'Pane')).not.toContain('Foreman')
})

// Bug: a snapshot that could not be read hid the indicator in every view, though the Foreman's state is read from its
// own folder on this machine, not from the snapshot.
test('a snapshot that cannot be read still shows the Foreman indicator in /units and the pane', async ($, on) => {
  const fetch = answer(null, 'host\tbuildbox\tssh\t255').replace('\nhost\t', `\nforeman\t${['other', '4242', COMMIT_A, 'other', '1', COMMIT_A, UP].join('\t')}\nhost\t`)
  const { text } = await foremanWorld($, on, fetch)
  expect(text.startsWith(`${CANNOT}\nForeman not listening: not the Foreman session\n  role: other · waiter 4242 on aaaaaaa for other · watchers: conveyor up`)).toBe(true)
  expect(await draw($, 'Pane')).toContain('Foreman not listening: not the Foreman session')
  expect(await draw($, 'Pane')).toContain('role: other')
})

// A /clear gives the Foreman's folder a new role mark, and /units showed it only at the next fetch (a minute, or a slow
// one's 75 s later). The mod looks at the write times of `session` and waiter.pid each second and, on a change, reads
// the Foreman line alone. The folder is the one the fetch's foremandir line names.
const FD = '/r/state/bookstore/foreman'
const MARK = `${FD}/session`
const PID = `${FD}/waiter.pid`
const inFolder = (fields: string[]) => withForeman(fields).replace('\nhost\t', `\nforemandir\t${FD}\nhost\t`)
const OTHER = inFolder(['other', '4242', COMMIT_A, 'other', '1', COMMIT_A, UP])
const MINE = inFolder(['me', '4242', COMMIT_A, 'me', '1', COMMIT_A, UP])
const clearWorld = async ($: any, on: On) => {
  const w = world(on, 'main', OTHER, { [MARK]: 'other 2026-11-21T00:00:00Z', [PID]: '4242 a other' })
  on('session.id', () => ({ value: 'me' }))
  await start($, 'main')
  await w.clock.settle()
  // The first fetch names the folder with no earlier look at it, so the next second reads the line once; the cases
  // below start after that read.
  await w.clock.advance(1000)
  expect(foremanReads(w).length).toBe(1)
  return w
}

// Bug it catches: the row waited for the minute's fetch, so a /clear showed the new Foreman late.
test('a role mark that now names this session shows this session as the Foreman within a second, with no fetch', async ($, on) => {
  const w = await clearWorld($, on)
  expect(await draw($, 'Pane')).toContain('Foreman not listening: not the Foreman session')
  const polled = fetches(w).length
  w.fetch = MINE
  w.files.set(MARK, { text: 'me 2026-11-21T00:00:01Z', at: NOW + 500 })
  await w.clock.advance(1000)
  expect(await draw($, 'Pane')).toContain('Foreman listening')
  expect(foremanReads(w).length).toBe(2)
  expect(fetches(w).length).toBe(polled)
  // The change is read once: the seconds after it read nothing more.
  await w.clock.advance(3000)
  expect(foremanReads(w).length).toBe(2)
})

// Bug it catches: the first fetch (no Foreman folder known yet) read the old role, and the mark's new write time was
// then saved as already seen, so a /clear during that fetch showed only at the next poll.
test('a role mark changed while the first fetch runs is read within a second after it', async ($, on) => {
  const w = world(on, 'main', OTHER, { [MARK]: 'other 2026-11-21T00:00:00Z', [PID]: '4242 a other' })
  on('session.id', () => ({ value: 'me' }))
  let release = () => {}
  w.hold = new Promise<void>(r => { release = r })
  await start($, 'main')
  w.files.set(MARK, { text: 'me 2026-11-21T00:00:01Z', at: NOW + 500 })
  w.hold = undefined
  w.fetch = OTHER
  release()
  await w.clock.settle()
  w.fetch = MINE
  await w.clock.advance(1000)
  expect(await draw($, 'Pane')).toContain('Foreman listening')
  expect(fetches(w).length).toBe(1)
})

// Bug it catches: a check that read the Foreman line each second (a process a second) instead of only on a change.
test('a second with no change to the role mark or waiter.pid reads nothing', async ($, on) => {
  const w = await clearWorld($, on)
  const [foreman, reads] = [foremanReads(w).length, w.reads.length]
  await w.clock.advance(4000)
  // No Foreman read, no fetch, and neither file read (the short `stamp` check is its own, not under test here).
  expect(foremanReads(w).length).toBe(foreman)
  expect(fetches(w).length).toBe(1)
  expect(w.reads.slice(reads).filter(p => p === MARK || p === PID)).toEqual([])
})

// Bug it catches: only the role mark was watched, so a waiter that started or ended showed at the next fetch.
test('a waiter.pid that changes is read within a second as well', async ($, on) => {
  const w = await clearWorld($, on)
  w.fetch = inFolder(['me', '4242', COMMIT_A, 'me', '0', COMMIT_A, '', 'down: ended'])
  w.files.set(PID, { text: '4243 a other', at: NOW + 500 })
  await w.clock.advance(1000)
  expect(foremanReads(w).length).toBe(2)
  expect(await draw($, 'Pane')).toContain('Foreman not listening: waiter down: ended')
})
