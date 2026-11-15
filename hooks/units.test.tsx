// SPDX-License-Identifier: Apache-2.0
import { expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'
import { register as loadAgain } from './units'
import { TWO_PROJECTS } from './fixtures/units-two-projects'

// The mod asks for one thing, its fetch (a bash run in the main checkout), then reads the dashboard's data file for the
// usage limit and the Research lane's session logs. Each hook below stands for the engine over an in-memory disk; the
// fetch answers with `w.fetch`, the lines the real script prints.

const MAIN = '/r/main'
const WS = '/r/ws'
const HOME = '/r/home'
const NOW = Date.UTC(2026, 10, 10, 4, 40, 0)
// The Board's folder, as FEED_DIR names it: the folder the Board writes data.js and stream.json to.
const BOARD = '/r/state/bookstore/dashboard'
const DATA = `${BOARD}/data.js`
// The data file as the Board writes it: the limit under its health panel's data.
const dataJs = (usedPct: number, resetsAt: string) => `window.DASH = ${JSON.stringify({ panels: { health: { data: { limit: { usedPct, resetsAt } } } } })};`
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
  // The band is one row per plugin that hooks it, the test among them: this stands beneath the units row alone
  // and draws no row of the test's own, so 'engine' in the band means the units row passed.
  on('ui.render', { plugin: '*' }, ($, e, next) => (e.component === 'AbovePrompt' && e.plugin !== 'conveyor-belt' ? next(e) : { ...$.ui.resolve(e).Text({ children: 'engine' }) }))
  on('command.run', () => ({ text: 'engine' }))
  return w
}

const start = ($: any, seat: keyof typeof SEATS) => $.session.start({ cwd: SEATS[seat][1], ...SESSION })
const units = ($: any, args = '') => $.command.run({ command: 'units', args, origin: { kind: 'composer' }, presentation: { layout: 'main', columns: 100 } }).then((r: any) => r.text as string)
const draw = async ($: any, component: 'AbovePrompt' | 'Pane') => {
  const ui = await $.ui.mount({ plugin: 'conveyor-belt', surface: 'terminal', component, requestId: component === 'Pane' ? 'units' : 'band', props: component === 'Pane' ? { title: 'Conveyor', isFocused: false, bodyColumns: 72, placement: 'dock' } : { hasSurvey: false } })
  const texts = ((await ui.findAll({ type: 'Text' })) as { text: string }[]).map(t => t.text)
  await ui.unmount()
  return texts.join('')
}
const fetches = (w: World) => w.runs.filter(r => r.argv[0] === 'bash' && r.argv[1].endsWith('/hooks/units-fetch.sh'))
const CANNOT = 'units: the Conveyor snapshot cannot be read (buildbox is unreachable)'

test('/units prints the header, the four sections and the two lanes from one fetch run in the main checkout', async ($, on) => {
  const w = world(on, 'main', answer(FULL), {
    [DATA]: dataJs(34, new Date(NOW + 5 * 3600_000).toISOString()),
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
  expect(text).toMatch(/\nON THE BELT \(2\)\n #12 Bread oven timer +[^\n]*\n[^]*\n gadgetlab#7 Gear ratio chart +/)
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

test('a snapshot that cannot be read is one plain line in /units, the band, the pane and the status line', async ($, on) => {
  const w = world(on, 'main', answer(null, 'host\tbuildbox\tssh\t255'), { [DATA]: dataJs(34, '2026-11-12T00:00:00Z') })
  await start($, 'main')
  await w.clock.settle()
  expect(await units($)).toBe(CANNOT)
  // The band's one line, then the view beneath it (the test's 'engine'), never hidden by it.
  expect(await draw($, 'AbovePrompt')).toBe(`${CANNOT}engine`)
  expect(await draw($, 'Pane')).toBe(CANNOT)
  expect(w.status.at(-1)).toBe(CANNOT)
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

test('the band and the pane show the board in short form, and the status line its counts', async ($, on) => {
  const w = world(on, 'main', answer(FULL))
  await start($, 'main')
  await units($)
  const band = await draw($, 'AbovePrompt')
  expect(band).toMatch(/^CONVEYOR · 1 needs you · 1 on the belt · 1 queued · 1 landed +7d not read · today \$7\.00 · ● buildbox reachable/)
  expect(band).toContain('◆ #3861 · your yes: Staff land a lane change as a card.')
  expect(band).toContain('◐ #3863 build 10m')
  // The Research lane has no worktree here, so the band and the pane leave it out.
  expect(band).toContain('Fast lane: nothing open')
  expect(band).not.toContain('Research lane')
  const pane = await draw($, 'Pane')
  for (const part of ['NEEDS YOU (1)', '◆ #3861 Fast lane · your yes: Staff land a lane change as a card.', 'ON THE BELT (1)', 'QUEUE  1', 'LANDED TODAY  1 · $7.00', 'FAST LANE      nothing open']) expect(pane).toContain(part)
  expect(pane).not.toContain('RESEARCH LANE')
  expect(w.status.at(-1)).toBe('conveyor: 1 needs you · 1 on the belt · 1 landed · today $7.00')
  expect(w.opened).toEqual(['units'])
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
    session: { root: async () => MAIN },
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
      status: async (text: string | undefined) => void w.status.push(text),
      toast: async (text: string) => void w.toasts.push(text),
      resolve: () => ({ Box: 'Box', Text: 'Text' }),
    },
  }
  const hook = (event: string, match: (m: any) => boolean) => hooks.find(h => h.event === event && match(h.match))!.hook
  return {
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
  expect(w.status.at(-1)).toBe('conveyor: 1 needs you · 1 on the belt · 1 landed · today $7.00')
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
  expect(w.status.at(-1)).toBe('conveyor: 0 on the belt · 0 landed · today $0.00')
  w.fetch = answer(FULL)
  await w.clock.advance(60_000)
  expect(fetches(w).length).toBe(4)
  expect(w.status.at(-1)).toBe('conveyor: 1 needs you · 1 on the belt · 1 landed · today $7.00')
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
  expect(await draw($, 'Pane')).toContain('ON THE BELT (1)')
  w.fetch = answer(snapshot())
  await w.clock.advance(60_000)
  expect(fetches(w).length).toBe(2)
  expect(await draw($, 'Pane')).toContain('the belt is empty')
  expect(await units($)).toContain('the belt is empty')
  await w.clock.settle()
  expect(fetches(w).length).toBe(3)
})

test('a session start after a pane began the load starts nothing again: the board stays and no second fetch is made', async ($, on) => {
  const w = world(on, 'main', answer(FULL))
  expect(await draw($, 'Pane')).toContain('ON THE BELT (1)')
  await start($, 'main')
  expect(fetches(w).length).toBe(1)
  expect(w.registered).toEqual(['units'])
  expect(await draw($, 'Pane')).toContain('ON THE BELT (1)')
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
  expect(await draw($, 'AbovePrompt')).toBe('engine')
  await w.clock.settle()
  expect(w.registered).toEqual([])
  expect(fetches(w)).toEqual([])
  const gits = w.runs.length
  await w.clock.advance(59_000)
  await draw($, 'AbovePrompt')
  await w.clock.settle()
  expect(w.runs.length).toBe(gits)
  expect(w.registered).toEqual([])
  await w.clock.advance(1000)
  await draw($, 'AbovePrompt')
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
  expect(await draw($, 'Pane')).toContain('ON THE BELT (1)')
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

test('/units band, pane and status flip one view for the session, and a pane that is not placed says why', async ($, on) => {
  const w = world(on, 'worker', answer(FULL))
  await start($, 'worker')
  expect(await units($, 'band on')).toBe('units band: on for this session')
  await w.clock.settle()
  expect(await draw($, 'AbovePrompt')).toContain('CONVEYOR · 1 needs you')
  expect(await units($, 'band off')).toBe('units band: off for this session')
  expect(await draw($, 'AbovePrompt')).toBe('engine')
  w.placed = false
  expect(await units($, 'pane on')).toBe('units pane: on for this session (not drawn: no room)')
  expect(await units($, 'status on')).toBe('units status: on for this session')
  await w.clock.settle()
  expect(w.status.at(-1)).toBe('conveyor: 1 needs you · 1 on the belt · 1 landed · today $7.00')
  await units($, 'status off')
  expect(w.status.at(-1)).toBe(undefined)
})

// Bug (issue 616): with /conveyor-belt:auto on and /units band on, each band's hook drew its own view in place of the
// next one's, so one band hid the other. Both bands, and the view beneath them ('engine'), are drawn.
test('with /conveyor-belt:auto on and /units band on, the place above the prompt shows both bands', async ($, on) => {
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
  expect(band).toContain('CONVEYOR · 1 needs you')
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
  expect(await draw($, 'Pane')).toContain('ON THE BELT (1)')
  expect(await units($)).toContain('ON THE BELT (1)')
})

test('with motion on, the mark of a card on the belt turns once a second, and stands still once the belt is empty', { options: { motion: 'on' } }, async ($, on) => {
  const w = world(on, 'main', answer(FULL))
  await start($, 'main')
  await w.clock.settle()
  expect(await draw($, 'AbovePrompt')).toContain('◐ #3863 build')
  await w.clock.advance(1000)
  expect(await draw($, 'AbovePrompt')).toContain('◓ #3863 build')
  w.fetch = answer(snapshot())
  await units($)
  await w.clock.settle()
  await w.clock.advance(1000)
  expect(await draw($, 'Pane')).toContain('the belt is empty')
})

test('outside a checkout with a Conveyor pack the mod registers nothing and fetches nothing', async ($, on) => {
  const w = world(on, 'main', answer(FULL), {}, false)
  await start($, 'main')
  expect(w.registered).toEqual([])
  expect(await units($)).toBe('engine')
  expect(fetches(w)).toEqual([])
})

// The Board's live feed: the stream.json it rewrites with each change Conveyor's host streams.
const FEED = `${BOARD}/stream.json`
// A feed outside the folder the Board's job names: the mod never reads it.
const OLD_FEED = `${HOME}/.conveyor/dashboard/stream.json`
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

// a feed or data file over the cap was skipped with no word, and /units went blank once the snapshot passed 4 MB.
test('a feed and a data file over the cap are not read: a line names each one\'s size and the cap, over the host\'s board or as its one line', async ($, on) => {
  const w = world(on, 'main', answer(FULL), { [FEED]: ' '.repeat(4_500_000), [DATA]: ' '.repeat(4_600_000) })
  await start($, 'main')
  await units($)
  await w.clock.settle()
  const text = await units($)
  expect(text).toContain('#3863')
  expect(text).toContain("units: the Board's live feed (stream.json) is 4.5 MB, over the 4.2 MB cap; it is not read, reading the host")
  expect(text).toContain("units: the Board's data file (data.js) is 4.6 MB, over the 4.2 MB cap; the usage limit is not read")
  expect(feeds(w)).toEqual([])
  w.fetchRc = 3
  await units($)
  await w.clock.settle()
  expect(await draw($, 'Pane')).toBe("units: the Board's live feed (stream.json) is 4.5 MB, over the 4.2 MB cap; it is not read, reading the host; units: the Board's data file (data.js) is 4.6 MB, over the 4.2 MB cap; the usage limit is not read; units: the Conveyor snapshot cannot be read (the fetch did not run)")
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
  expect(await units($)).toContain("units: the Board's live feed (stream.json) is 4.5 MB, over the 4.2 MB cap; it is not read, reading the host")
})

// the engine keeps a command's first 4 MiB of output; a cut snapshot was parsed as if whole.
test('a fetch whose output was cut short is its own cannot-be-read line', async ($, on) => {
  const w = world(on, 'main', answer(FULL))
  w.fetchCut = true
  await start($, 'main')
  await w.clock.settle()
  expect(await units($)).toBe('units: the Conveyor snapshot cannot be read (the fetch printed over the 4.2 MB cap and was cut short)')
})

// the data file (1.1 MB on the Mac) was read and parsed on every poll.
test('the data file is parsed again only when its write time changes', async ($, on) => {
  const resets = new Date(NOW + 5 * 3600_000).toISOString()
  const w = world(on, 'main', answer(FULL), { [DATA]: dataJs(34, resets) })
  await start($, 'main')
  await w.clock.settle()
  const dataReads = () => w.reads.filter(p => p === DATA).length
  expect(dataReads()).toBe(1)
  await w.clock.advance(60_000)
  await w.clock.settle()
  expect(fetches(w).length).toBe(2)
  expect(dataReads()).toBe(1)
  w.files.set(DATA, { text: dataJs(50, resets), at: NOW + 61_000 })
  await w.clock.advance(60_000)
  await w.clock.settle()
  expect(dataReads()).toBe(2)
  expect(await units($)).toContain('weekly limit 50%')
})

// a feed board laid over the state, by the second's read or by a poll whose fetch answered after it,
// replaced the notes and took the data file's over-cap line with them.
test('the data file\'s over-cap line stays under a board the feed changes, each second and after a slow poll', async ($, on) => {
  const line = "units: the Board's data file (data.js) is 4.6 MB, over the 4.2 MB cap; the usage limit is not read"
  const w = world(on, 'main', answer(FULL), { [FEED]: feed(snapshot()), [DATA]: ' '.repeat(4_600_000) })
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
test('the data file\'s over-cap line leads the one line drawn when the feed gives no snapshot, each second and after a slow poll', async ($, on) => {
  const line = "units: the Board's data file (data.js) is 4.6 MB, over the 4.2 MB cap; the usage limit is not read"
  const none = `${line}; units: the Conveyor snapshot cannot be read (buildbox gave no snapshot)`
  const w = world(on, 'main', answer(FULL), { [FEED]: feed(snapshot()), [DATA]: ' '.repeat(4_600_000) })
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
  expect(await draw($, 'Pane')).toContain('the belt is empty')
  // The collector stops: the feed file stays as it was. Its fetch of the host is held, so the warning is seen first.
  let release = () => {}
  w.hold = new Promise<void>(r => { release = r })
  await w.clock.advance(30_000)
  const pane = await draw($, 'Pane')
  expect(pane).toMatch(/units: the live feed has stopped \(its file is \d+ s old\)/)
  expect(pane).toContain('the belt is empty')
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
  ]
  const w = world(on, 'main', answer(FULL), { [FEED]: feed(snapshot({ belt })) })
  await start($, 'main')
  await w.clock.settle()
  const lines = (await units($)).split('\n').filter(l => l.includes('last output'))
  expect(lines.slice(0, 2).join('\n')).not.toMatch(/turn/)
  expect(lines).toEqual(['    3 of 5 tests · 1 failed · last output 23s ago', '    3 of 6 test files · last output 23s ago', '    4 turns · last output 23s ago'])
})

test('a quiet running step\'s seconds since its last output count on each second while the feed does not change', async ($, on) => {
  const live = { ...BELT, live: { action: 'Bash: npm test', turns: 3, lastOutputAt: new Date(NOW - 6000).toISOString() } }
  const w = world(on, 'main', answer(FULL), { [FEED]: feed(snapshot({ belt: [live] })) })
  await start($, 'main')
  await units($)
  expect(await draw($, 'Pane')).toContain('last output 6s ago')
  await w.clock.advance(3000)
  expect(await draw($, 'Pane')).toContain('last output 9s ago')
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

test('a feed change a poll read before its fetch stalled is drawn within a second, not when the fetch answers', async ($, on) => {
  const w = world(on, 'main', answer(FULL), { [FEED]: feed(snapshot()) })
  await start($, 'main')
  await units($)
  expect(await draw($, 'Pane')).toContain('the belt is empty')
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
  expect(w.status.at(-1)).toContain('bookstore paused')
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

// a running step wrote a new state each second, so the toast check and the status line (which run on each
// state written) ran again with nothing changed. The views' clock is its own atom.
test('a second with a running step and no board change writes no state, so makes no toast check and no status line write; only the views\' clock moves', async ($, on) => {
  const live = { ...BELT, live: { action: 'Bash: npm test', turns: 3, lastOutputAt: new Date(NOW - 6000).toISOString() } }
  const w = world(on, 'main', answer(FULL), { [FEED]: feed(snapshot({ belt: [live] })) })
  await start($, 'main')
  await w.clock.advance(1000)
  const states = () => w.writes.filter(k => k === 'state').length
  const [before, status] = [states(), w.status.length]
  expect(before).toBeGreaterThan(0)
  await w.clock.advance(1000)
  expect(states()).toBe(before)
  expect(w.status.length).toBe(status)
  expect(await draw($, 'Pane')).toContain('last output 8s ago')
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

// stream.json is rewritten at least every 10 s, changed or not, and each rewrite was parsed into a new board.
test('a stream.json rewrite with only the heartbeat changed builds no new board; a change in the board is drawn', async ($, on) => {
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
