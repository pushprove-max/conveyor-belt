// SPDX-License-Identifier: Apache-2.0
import { expect, mock, test } from 'claude-code/testing'
import { register } from './units'

// begin called the minute's timer as a function, but Claude Code's timer is an object with cancel, so a
// second begin in one load threw before it started the feed's check. Its own file: a load that began keeps its begin
// for every later test in a file, and this test begins its load twice. The mod runs on a $ of the test's own, as
// units.test.tsx's reload does, so its timer can be shaped as Claude Code's and the first one-second timer refused.

const MAIN = '/r/main'
const NOW = Date.UTC(2026, 10, 15, 10, 0, 0)
const BOARD = '/r/state/bookstore/dashboard'
const FEED = `${BOARD}/stream.json`
const feed = (issue: number) => JSON.stringify({
  host: 'buildbox',
  records: [{
    repo: 'bookstore',
    snap: {
      time: new Date(NOW).toISOString(), day: '2026-11-15', needsYou: { waiting: [], blocked: [] }, queue: { next: [], held: {} }, landed: [], health: {}, cost: { today: 0 },
      belt: [{ card: `c-${issue}`, issue, title: 'A card', step: 'build', review: null, of: 3, stepAt: new Date(NOW).toISOString(), model: 'claude-fable-5-2', tokens: {}, usd: null, reading: false }],
    },
  }],
  stream: { live: true, heardAt: new Date(NOW).toISOString(), since: null, error: null },
})

test('a second begin in one load, with a timer shaped as Claude Code\'s, does not throw: it runs on to the feed\'s check', async ($, on) => {
  const clock = mock.clock(on, { now: NOW })
  const files = new Map([[`${MAIN}/.conveyor/project.json`, { text: '', at: 0 }], [FEED, { text: feed(3863), at: NOW }]])
  const file = (p: string) => { const f = files.get(p); if (!f) throw new Error(`ENOENT ${p}`); return f }
  const values = new Map<string, { value: unknown; version: number }>()
  const registered: string[] = []
  const hooks: { event: string; match?: any; hook: (...a: any[]) => any }[] = []
  register(((event: string, ...rest: any[]) => {
    hooks.push({ event, match: rest.length > 1 ? rest[0] : undefined, hook: rest.at(-1) })
    return { catch: () => undefined }
  }) as any, {})
  // git names this checkout main; FEED_DIR names the Board's folder; the fetch, in feed mode, reads the lanes alone.
  const out = (argv: string[]) => (argv[0] === 'git' ? `${MAIN}/.git\n${MAIN}/.git\n${MAIN}\n` : argv[3] === 'units-feed' ? `${BOARD}\n` : 'paths\t\t/r/home\nfast\tnorecord\nhost\t\tfeed\t0\n')
  let refused = false
  const $u: any = {
    plugin: { name: 'conveyor-belt', root: '/r/plugin' },
    session: { root: async () => MAIN },
    process: { run: async (argv: string[]) => ({ exitCode: 0, stdout: out(argv), stderr: '', isStdoutTruncated: false, isStderrTruncated: false }) },
    fs: {
      stat: async (p: string) => { const f = file(p); return { kind: 'file', size: f.text.length, mtimeMs: f.at, isLink: false } },
      read: async (p: string) => file(p).text,
      list: async (dir: string) => { throw new Error(`ENOENT ${dir}`) },
    },
    clock: {
      now: async () => clock.now(),
      every: (ms: number, fn: () => void) => {
        // The first begin's one-second timer is refused: that begin fails after its minute timer started.
        if (ms === 1000 && !refused) {
          refused = true
          throw new Error('refused')
        }
        let live = true
        void (async () => { while (live) { await clock.sleep(ms); if (live) fn() } })()
        return { cancel: () => { live = false } }
      },
    },
    state: {
      get: async (r: any) => values.get(r.key) ?? { value: undefined, version: 0 },
      set: async (r: any, value: unknown, o?: { ifVersion?: number }) => {
        const cur = values.get(r.key) ?? { value: undefined, version: 0 }
        if (o?.ifVersion !== undefined && o.ifVersion !== cur.version) return { isSet: false, version: cur.version }
        values.set(r.key, { value, version: cur.version + 1 })
        return { isSet: true, version: cur.version + 1 }
      },
    },
    command: { register: async (c: { name: string }) => (registered.push(c.name), { command: c.name }) },
    ui: { open: async () => ({ isPlaced: true }), close: async () => undefined, status: async () => undefined, toast: async () => undefined, resolve: () => ({ Box: 'Box', Text: 'Text' }) },
  }
  const pane = hooks.find(h => h.event === 'ui.render' && h.match?.component === 'Pane')!.hook
  const draw = () => pane($u, { component: 'Pane', surface: 'terminal', props: { title: 'Conveyor', isFocused: false, bodyColumns: 72, placement: 'dock' } }, async () => ({}))

  await draw()
  await clock.settle()
  expect(refused).toBe(true)
  expect(registered).toEqual(['units'])
  await clock.advance(60_000)
  await draw()
  await clock.settle()
  expect(registered).toEqual(['units', 'units'])
  // The second begin ran to its end: its one-second check draws a feed change.
  files.set(FEED, { text: feed(6176), at: clock.now() })
  await clock.advance(1000)
  expect((values.get('state')?.value as any)?.snap?.belt.map((b: any) => b.issue)).toEqual([6176])
})
