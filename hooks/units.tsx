// SPDX-License-Identifier: Apache-2.0
import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'
import { refresh as refreshAutoBand } from './auto'
import { boardOf, boardOfFeed, foremanOf, paneModel, parseFetch, parseLimit, parseStream, seatFromGit, seenOf, tableText, toasts } from './sources'
import { setClock } from './elements'
import type { Line } from './elements'
import type { Research, Seen, State } from './sources'

// Conveyor's board: what needs you, the cards on the belt, the queue, what landed today and the two lanes, as
// `/units` and a side pane; with the pane on, a toast for a card that newly needs you or lands. One fetch a minute
// reads it all, and the dashboard collector's live feed, when it is fresh, gives the board as it changes; the mod
// writes nothing: its only state is atoms (what the views draw).
const state = atom({ plugin: 'conveyor-belt', key: 'state' } as const, null)
// The belt mark's turn: only the motion clock writes it, never the poll, so a poll keeps the turn.
const frame = atom({ plugin: 'conveyor-belt', key: 'frame' } as const, 0)
// The pane's Machine details: opened and closed by its Button (a click, or `m` while the pane has the focus).
const details = atom({ plugin: 'conveyor-belt', key: 'details' } as const, false)
// The time the views count from while the board stands still: the second's clock writes it alone, so a running
// step's seconds count on with no new state or toast check. A newer state's own `now` wins.
const clockNow = atom({ plugin: 'conveyor-belt', key: 'now' } as const, 0)
const drawnAt = async ($: EngineInterface, s: State): Promise<State> => {
  const n = await read($, clockNow)
  return n > s.now ? { ...s, now: n } : s
}

type Views = 'pane'

const POLL_MS = 60_000
// The Board's live feed: its stream.json is looked at once a second and read when it changed. It is rewritten
// at least every 10 s while the Board runs; one older than STREAM_FRESH is no feed.
const STREAM_MS = 1000
const STREAM_FRESH = 30_000
// A Board file over MAX_DATA is not read, and a line names its size and the cap: never a blank board. 4 MiB is
// the engine's own cap on a file read and on a command's output: a larger file is refused, larger output cut.
const MAX_DATA = 4 * 1024 * 1024
const mb = (n: number) => `${(n / 1e6).toFixed(1)} MB`
const overCap = (what: string, size: number, then: string) => `units: ${what} is ${mb(size)}, over the ${mb(MAX_DATA)} cap; ${then}`
const CUT = `the fetch printed over the ${mb(MAX_DATA)} cap and was cut short`
const PANE = 'units'
const WAITING = 'units: reading the Conveyor snapshot'

// The one fetch, hooks/units-fetch.sh, run in the main checkout: the lines sources.ts parseFetch reads (the lanes of
// this checkout's record of the host file, and the snapshot of every record the host file names). Its argument
// `feed` (the Board's live feed is fresh) leaves the snapshot out: the board is the feed's, and the fetch reads only
// what the feed lacks.
const FETCH = 'hooks/units-fetch.sh'

// The fetch from the install of the project's engine, found as shim.sh finds it: the commit the pack pins, else, for
// a pack that follows the plugin's main, the commit this machine took (the main checkout's .git/conveyor-engine.json),
// in <XDG_DATA_HOME, else ~/.local/share>/conveyor/versions/<commit>. That engine wrote the records the fetch reads,
// so an older plugin copy's fetch never misreads them (issue 383: its waiter.pid). Until the project has an install
// (no commit, or no fetch in its folder), the plugin's own fetch.
const fetchPath = async ($: EngineInterface, main: string): Promise<string> => {
  const own = `${$.plugin.root}/${FETCH}`
  const json = async (file: string) => { try { return JSON.parse((await $.fs.read(file)) as string) } catch { return null } }
  const plugin = (await json(`${main}/.conveyor/project.json`))?.plugin
  const commit = plugin?.commit || (plugin?.follow ? (await json(`${main}/.git/conveyor-engine.json`))?.commit : '')
  // Only a full commit id names a version folder: anything else could name a path outside versions/.
  if (typeof commit !== 'string' || !/^[0-9a-f]{40}$/.test(commit)) return own
  const home = (await $.env.get('HOME').catch(() => undefined)) || ''
  const data = (await $.env.get('XDG_DATA_HOME').catch(() => undefined)) || (home && `${home}/.local/share`)
  if (!data) return own
  const path = `${data}/conveyor/versions/${commit}/${FETCH}`
  return (await $.fs.stat(path).catch(() => undefined)) ? path : own
}

// The Board's folder, named as the plugin's dashboard.sh names its OUT, from the Board job installed on this
// machine (`dashboard.sh --install`: the Mac's launchd plist, else the systemd user unit): the job's script and the
// overrides the job keeps, never this session's. The job's CONVEYOR_DASHBOARD_DIR; else dashboard/ in the state folder
// that the engine beside the Board's files (`conveyor.sh state-dir`) gives for the Board's primary checkout: the job's
// CONVEYOR_MAIN, else the git common dir of the Board's scripts folder. Not this session's checkout: a Board run from
// the plugin's checkout keeps its feed in that checkout's state folder. Prints the folder; exits 4 when it cannot be named.
// Keep in step with dashboard.sh's PP_MAIN, OUT and install.
const FEED_DIR = String.raw`
unset CONVEYOR_DASHBOARD_DIR CONVEYOR_MAIN XDG_CONFIG_HOME XDG_DATA_HOME
keys='CONVEYOR_DASHBOARD_DIR CONVEYOR_MAIN XDG_CONFIG_HOME XDG_DATA_HOME'
if [ "$(uname -s)" = Darwin ]; then
  j=$HOME/Library/LaunchAgents/com.conveyor.dashboard.plist
  s=$(plutil -extract ProgramArguments.1 raw -o - "$j" 2>/dev/null) || exit 4
  for k in $keys; do v=$(plutil -extract "EnvironmentVariables.$k" raw -o - "$j" 2>/dev/null) && export "$k=$v"; done
else
  j=$HOME/.config/systemd/user/dashboard.service
  s=$(sed -n 's/^ExecStart="[^"]*" "\(.*\)" --loop$/\1/p' "$j" 2>/dev/null)
  for k in $keys; do v=$(sed -n "s/^Environment=\"$k=\(.*\)\"\$/\1/p" "$j" 2>/dev/null) && [ -n "$v" ] && export "$k=$v"; done
fi
[ -z "$CONVEYOR_DASHBOARD_DIR" ] || { printf '%s\n' "$CONVEYOR_DASHBOARD_DIR"; exit 0; }
case $s in /*/scripts/dashboard.sh) h=$(dirname "$s") ;; *) exit 4 ;; esac
m=$CONVEYOR_MAIN
if [ -z "$m" ]; then
  m=$(git -C "$h" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  case $m in */.git) m=$(dirname "$m") ;; *) exit 4 ;; esac
fi
d=$(CONVEYOR_MAIN=$m bash "$(dirname "$(dirname "$h")")/conveyor/conveyor.sh" state-dir 2>/dev/null) && [ -n "$d" ] || exit 4
printf '%s/dashboard\n' "$d"
`
const NO_FEED_DIR = "units: the live feed's folder was not found (no Board job here, or its state folder cannot be named); reading the host"

let main: string | undefined
let stopPoll: { cancel: () => void } | undefined
let feedClock: { cancel: () => void } | undefined
let spin: { cancel: () => void } | undefined
let motion = false
let seatName: 'main' | 'worker' = 'worker'
let overrides: Partial<Record<Views, boolean>> = {}
let paneUp = false
let prevSeen: Seen | null = null
let option: Record<Views, string> = { pane: 'auto' }

const wanted = (v: Views) => overrides[v] ?? (option[v] === 'on' ? true : option[v] === 'off' ? false : seatName !== 'worker')
const anyWanted = () => wanted('pane')

// The Research lane's run: the newest write to a Claude session log of its worktree (Claude Code keeps a worktree's
// sessions in <CLAUDE_CONFIG_DIR, else ~/.claude>/projects/<its path, every other character a dash, cut past 200
// characters to those and a dash and a hash>, as conveyor/foreman/foreman.sh launch reads it).
const readResearch = async ($: EngineInterface, wt: string, home: string): Promise<Research> => {
  if (!wt || !(await $.fs.stat(`${wt}/.git`).catch(() => undefined))) return { state: 'none' }
  const projects = `${(await $.env.get('CLAUDE_CONFIG_DIR').catch(() => undefined)) || `${home}/.claude`}/projects`
  const enc = wt.replace(/[^A-Za-z0-9]/g, '-')
  const dirs = enc.length <= 200 ? [enc]
    : (await $.fs.list(projects).catch(() => [])).filter(e => e.kind === 'dir' && e.name.startsWith(`${enc.slice(0, 200)}-`)).map(e => e.name)
  const logs = (await Promise.all(dirs.map(d => $.fs.list(`${projects}/${d}`).catch(() => [])))).flat()
  const times = logs.filter(e => e.name.endsWith('.jsonl')).map(e => e.mtimeMs)
  return { state: 'ok', lastAt: times.length ? Math.max(...times) : null }
}

const NO_LIMIT = { limit: null, over: null }
// The limit file's write time and the limit read from it: the file is read again only once that time changes.
let limitRead: { file: string; at: number; limit: State['limit'] } | null = null
// The Board's limit file holds the usage limit alone, a few hundred bytes; a larger one is not the Board's and is not read.
const MAX_LIMIT = 16 * 1024
const NO_LIMIT_FILE = "units: the Board's folder has data.js but no limit.json (the Board runs an older engine); the usage limit is not read"
// The usage limit is the account's, kept by the Board in limit.json beside its data file; none there reads "not read".
// data.js is never read: it grows with the projects and their tests, past any cap. over: the line that says why the
// limit file was not read: too big, or missing from a folder an older Board writes (data.js there, only looked at).
const readLimit = async ($: EngineInterface): Promise<{ limit: State['limit']; over: string | null }> => {
  if (!feedDir) return NO_LIMIT
  const file = `${feedDir}/limit.json`
  const st = await $.fs.stat(file).catch(() => undefined)
  if (!st) return (await $.fs.stat(`${feedDir}/data.js`).catch(() => undefined)) ? { limit: null, over: NO_LIMIT_FILE } : NO_LIMIT
  if (st.size > MAX_LIMIT) return { limit: null, over: `units: the Board's limit file (limit.json) is ${st.size} bytes, over the ${MAX_LIMIT} byte cap; the usage limit is not read` }
  if (limitRead?.file !== file || limitRead.at !== st.mtimeMs) limitRead = { file, at: st.mtimeMs, limit: parseLimit((await $.fs.read(file)) as string) }
  return { limit: limitRead.limit, over: null }
}
// The Board's Time setting, as its page last sent it: on a change, or on opening only once per browser and only when not
// the default (app.js TIME_SENT_KEY) (dashboard_server.py's POST /time writes
// time.json in the Board's folder). It wins over the plugin's `time` option, which stands where the Board here has
// sent none: else 24-hour on the Board left the pane writing AM and PM.
let optionTime: unknown
const readTime = async ($: EngineInterface) => {
  const file = feedDir && `${feedDir}/time.json`
  const st = file ? await $.fs.stat(file).catch(() => undefined) : undefined
  let t: unknown
  if (file && st && st.size <= 1024) t = await $.fs.read(file).then(s => JSON.parse(s as string)?.time, () => undefined).catch(() => undefined)
  setClock(t === '12-hour' || t === '24-hour' ? t : optionTime)
}
// The limit file's not-read line (dataOver) as the limit was last read: a feed board laid over the state keeps it, as it keeps
// the limit. A board with no snapshot is drawn as its note alone, so the
// line leads the note too.
let dataOver: string | null = null
type Board = Pick<State, 'snap' | 'note' | 'notes' | 'host'>
const withDataOver = (b: Board): Board => {
  const over = dataOver
  if (!over) return b
  return {
    ...b,
    notes: b.notes.includes(over) ? b.notes : [over, ...b.notes],
    note: b.snap || b.note.includes(over) ? b.note : [over, b.note].join('; '),
  }
}

// The Board's live feed, when its file was written in the last STREAM_FRESH: the board from it, and the file's write
// time. null otherwise, and while no feed folder is named; { over }, the line that says so, when a fresh one is too big
// to read.
let feedDir: string | undefined
// The write time of the feed file whose board the views were last given: set only once that board is published, so a
// feed read by a poll still waiting on its fetch is not taken for one already drawn.
let feedAt = -1
// The feed text that board came from, its heartbeat left out (feedText): set with feedAt, so a rewrite that only beat
// is not drawn again.
let feedKey: string | null = null
// The Board rewrites stream.json at least every 10 s with only stream.heardAt moved: the text with that left
// out says whether the board changed. A stream that is down keeps it, as its note gives that time.
const feedText = (text: string) => {
  try {
    const j = JSON.parse(text)
    if (j?.stream?.live === true) j.stream.heardAt = null
    return JSON.stringify(j)
  } catch {
    return text
  }
}
// The session's own project, as the last fetch named it (the host file's record whose main is this checkout): its cards
// carry no project name, in the feed's board as in the host's. Empty until a fetch names one.
let own = ''
// The last board built from the feed, with its text and the own it was built for: the same text is not parsed into
// cards again. null: the text is not a feed.
let feedBuilt: { key: string; own: string; board: Board } | null = null
const feedBoardOf = (key: string): Board | null => {
  if (feedBuilt?.key !== key || feedBuilt.own !== own) {
    const f = parseStream(key)
    if (!f) return null
    feedBuilt = { key, own, board: boardOfFeed(f, own) }
  }
  return feedBuilt.board
}
const readFeed = async ($: EngineInterface) => {
  if (!feedDir) return null
  const file = `${feedDir}/stream.json`
  const st = await $.fs.stat(file).catch(() => undefined)
  if (!st || (await $.clock.now()) - st.mtimeMs > STREAM_FRESH) return null
  if (st.size > MAX_DATA) return { over: overCap("the Board's live feed (stream.json)", st.size, 'it is not read, reading the host') }
  const key = feedText((await $.fs.read(file)) as string)
  const board = feedBoardOf(key)
  return board ? { board, at: st.mtimeMs, key } : null
}

// feedDir from FEED_DIR: a run that fails, or prints anything but one absolute path, leaves it unnamed. One run at a
// time: begin starts it without waiting, and the first poll waits on that same run.
let naming: Promise<void> | undefined
const nameFeedDir = ($: EngineInterface, cwd: string) => (naming ??= (async () => {
  const r = await $.process.run(['bash', '-c', FEED_DIR, 'units-feed'], { cwd, timeoutMs: 5000 }).catch(() => undefined)
  const d = r && r.exitCode === 0 ? r.stdout.trim() : ''
  feedDir = d.startsWith('/') && !d.includes('\n') ? d : undefined
})().finally(() => { naming = undefined }))

// One poll. Whatever fails, the views get a state: a fetch that cannot run is the one "cannot be read" line. With the
// live feed fresh, the board is the feed's and the fetch asks the host for no snapshot (only for a build machine's
// test map). fedAt: the feed file's write time when the board is the feed's. A feed folder not yet named is asked for
// again; while it is unnamed the board is the host's, with a note that says so.
const collect = async ($: EngineInterface, cwd: string): Promise<{ st: State; fedAt: number | null; fedKey: string | null }> => {
  if (!feedDir) await nameFeedDir($, cwd)
  const got = await readFeed($).catch(() => null)
  const fed = got && 'board' in got ? got : null
  // The script gives the host 50 s; the engine's own 30 s default would cut a slow answer short.
  const r = await $.process.run(['bash', await fetchPath($, cwd), ...(fed ? ['feed'] : [])], { cwd, timeoutMs: 75_000 }).catch(() => undefined)
  const f = r && r.exitCode === 0 ? parseFetch(r.stdout) : null
  const now = await $.clock.now()
  if (f) own = f.own
  // The feed's board again for the own this fetch named, which the feed was read before.
  const board = fed && f ? (feedBoardOf(fed.key) ?? fed.board) : boardOf(f, r?.isStdoutTruncated ? CUT : null)
  // Read whether or not the host answered: a failed fetch must not drop the limit file's not-read line.
  const lim = await readLimit($).catch(() => NO_LIMIT)
  dataOver = lim.over
  // Before the state is published: the views it draws write their times in the Board's Time.
  await readTime($).catch(() => undefined)
  // Under the board; with no board, the one line every view draws says them first.
  const over = [got && 'over' in got ? got.over : null, lim.over].filter((x): x is string => !!x)
  const st: State = {
    now, ...board, notes: [...over, ...(feedDir ? [] : [NO_FEED_DIR]), ...board.notes],
    ...(board.snap || !over.length ? {} : { note: [...over, board.note].join('; ') }),
    limit: f ? lim.limit : null,
    fast: f ? f.fast : { state: 'unread' },
    research: f ? await readResearch($, f.research, f.home).catch((): Research => ({ state: 'none' })) : { state: 'none' },
    // The fetch reads the Foreman's folder; whether this session is the one it names is the session's own id.
    foreman: f ? foremanOf(f.foreman, await $.session.id().catch(() => '')) : null,
    pluginBugs: f ? f.pluginBugs : null,
    testMap: f ? f.testMap : null,
    engine: f ? f.engine : null,
  }
  return { st, fedAt: fed && f ? fed.at : null, fedKey: fed && f ? fed.key : null }
}

// Polls and /units calls run one after another: a slow fetch must not publish after a newer one. One that has not
// started yet stands for every call made meanwhile: it reads the board as it is when it starts.
let queue: Promise<unknown> = Promise.resolve()
let waiting: Promise<void> | undefined
const tick = ($: EngineInterface): Promise<void> => {
  if (waiting) return waiting
  const run = queue.catch(() => undefined).then(() => {
    waiting = undefined
    return poll($)
  })
  waiting = run
  queue = run
  return run
}

// Once a second: a live feed file that changed since it was last read gives the views its board at once, the lanes and
// the limit staying as the last poll read them. A second that finds no change reads nothing, and a rewrite whose text
// changed only in its heartbeat writes no state. It does not wait for a
// poll: a fetch can take 75 s, and a stream that comes back during one is drawn within the second.
let feedBusy = false
let feedSeq = 0
// The newest board the feed gave, with its file's write time: set before that board is published, so a poll that
// publishes in between takes this board, never the older one the views still hold.
let feedBoard: { board: Board; at: number } | null = null
const boardPart = (b: Board): Board => ({ snap: b.snap, note: b.note, notes: b.notes, host: b.host })
const feedTick = ($: EngineInterface) => {
  if (feedBusy || !feedDir || !main || !anyWanted()) return
  feedBusy = true
  void (async () => {
    const st = await $.fs.stat(`${feedDir}/stream.json`).catch(() => undefined)
    // feedAt is the feed last published: one a poll read and has not drawn yet (its fetch still out) is drawn now.
    const drawn = (await read($, state)) as State | null
    const now0 = await $.clock.now()
    if (!st || now0 - st.mtimeMs > STREAM_FRESH) {
      // The feed has stopped (the collector ended, or lost its stream and its file went stale). A board the feed gave
      // is said to be old at once, and a poll reads the host itself, not waiting out the minute (an
      // unchanged feed file kept showing a board with no warning).
      if (feedAt >= 0 && drawn) {
        const age = st ? `${Math.round((now0 - st.mtimeMs) / 1000)} s old` : 'gone'
        feedAt = -1
        feedKey = null
        await publish($, cur => {
          const c = cur ?? drawn
          return { ...c, notes: [`units: the live feed has stopped (its file is ${age}); the board is as it last gave it, reading the host`, ...c.notes], now: now0 }
        })
        void tick($).catch(() => undefined)
      }
      return
    }
    if (st.mtimeMs !== feedAt || !drawn) {
      const got = await readFeed($)
      // A feed too big to read is never read: a poll reads the host and says why, at once when the views hold a
      // board this feed gave (feedAt then -1, so the next second starts no second poll).
      if (!got || !('board' in got)) {
        if (got && feedAt >= 0) {
          feedAt = -1
          feedKey = null
          void tick($).catch(() => undefined)
        }
        return
      }
      if (!drawn || got.key !== feedKey) return await drawFeed($, got, drawn)
      feedAt = got.at
    }
    // Nothing new in the feed, but a running step's "last output N s ago" counts on: the clock moves each second.
    if (drawn?.snap?.belt.some(b => b.live?.lastOutputAt != null)) await update($, clockNow, () => now0)
  })().catch(() => undefined).finally(() => { feedBusy = false })
}

// The feed's board, newer than the one the views hold, laid over the state.
const drawFeed = async ($: EngineInterface, got: { board: Board; at: number; key: string }, drawn: State | null) => {
  const fed = got.board
  // Before the session's first poll has answered there are no lanes yet: the board is drawn without waiting for them
  // (the poll's fetch can take 75 s), and the limit is this machine's file.
  const lim = drawn ? null : await readLimit($).catch(() => NO_LIMIT)
  if (lim) dataOver = lim.over
  await readTime($).catch(() => undefined)
  const rest = lim && { limit: lim.limit, fast: { state: 'unread' }, research: { state: 'none' } }
  feedSeq++
  feedBoard = { board: boardPart(fed), at: got.at }
  const now = await $.clock.now()
  // Laid over the state as it is when written: the lanes and the limit a poll published meanwhile are kept.
  await publish($, cur => ({ ...(cur ?? drawn ?? rest), ...withDataOver(fed), now }) as State)
  feedAt = got.at
  feedKey = got.key
}

// A board the feed gave while the fetch ran is newer than the fetch's: the poll then brings only the lanes and the
// limit, and the board is the feed's newest (feedBoard), whether or not the views hold it yet.
const poll = async ($: EngineInterface) => {
  if (!main) return
  const seq = feedSeq
  const { st, fedAt, fedKey } = await collect($, main)
  const fb = feedSeq === seq || !feedBoard || (fedAt !== null && fedAt >= feedBoard.at) ? null : feedBoard
  await publish($, () => (fb ? { ...st, ...withDataOver(fb.board) } : st))
  if (!fb && fedAt !== null) {
    feedAt = fedAt
    feedKey = fedKey
    if (!feedBoard || fedAt >= feedBoard.at) feedBoard = { board: boardPart(st), at: fedAt }
  } else if (!fb) {
    // the board drawn is the host's own: no feed of it can go stale
    feedAt = -1
    feedKey = null
  }
}

// make: the state to publish, from the one the views hold as it is written.
const publish = async ($: EngineInterface, make: (cur: State | null) => State) => {
  let st = null as unknown as State
  await update($, state, cur => (st = make(cur as State | null)))
  if (st.snap) {
    const cur = seenOf(st.snap)
    if (wanted('pane')) for (const text of toasts(prevSeen, cur)) $.ui.toast(text)
    prevSeen = cur
  }
  // The motion clock runs only while `motion` is on and a card is on the belt; stopped, the mark stands still at once.
  const turning = motion && !!st.snap?.belt.length && wanted('pane')
  if (turning && !spin) spin = $.clock.every(1000, () => void turn($).catch(() => undefined))
  if (!turning && spin) {
    spin.cancel()
    spin = undefined
    await update($, frame, () => 0)
  }
}

const turn = async ($: EngineInterface) => update($, frame, f => (f + 1) % 4)

// `ask` is `/units pane on`: it opens again even when the pane is already up, since the session's own open may have been left unplaced.
// Returns the open's placement when it opened.
const setViews = async ($: EngineInterface, ask = false) => {
  const pane = wanted('pane')
  let placed: { isPlaced?: boolean; reason?: string } | undefined
  if (pane !== paneUp || (ask && pane)) {
    paneUp = pane
    if (pane) placed = await $.ui.open({ id: PANE, title: 'Conveyor' })
    else await $.ui.close({ id: PANE })
  }
  return placed
}

// The session's start: find the checkout, register /units, open the pane and start the polls. Registers nothing outside
// a checkout with a Conveyor pack (.conveyor/project.json): the plugin applies to every project on the profile. A pull that changes the mod's
// files reloads it in a running session: register runs again with these variables fresh and no session.start may
// follow, so the first of session.start, a redraw or /units in a load begins it, once.
let begun: Promise<void> | undefined
const begin = async ($: EngineInterface) => {
  const root = await $.session.root()
  const git = await $.process.run(['git', '-C', root, 'rev-parse', '--path-format=absolute', '--git-dir', '--git-common-dir', '--show-toplevel'])
  const seat = git.exitCode === 0 ? seatFromGit(git.stdout) : null
  if (!seat || !(await $.fs.stat(`${seat.main}/.conveyor/project.json`).catch(() => undefined))) return
  seatName = seat.seat
  main = seat.main
  overrides = {}
  prevSeen = null
  paneUp = false
  await update($, state, () => null)
  await $.command.register({ name: 'units', description: "Conveyor's board (needs you, the belt, the queue, landed today, the lanes): /units, or /units pane on|off" })
  // The open here is unasked, so the host places it only on a wide terminal (a narrower one leaves it undrawn, with
  // the reason): the session is told why and that /units pane on, an asked open, places it at any width.
  const placed = await setViews($)
  if (placed && placed.isPlaced === false) $.ui.log(`units: the Conveyor pane is not drawn (${placed.reason ?? 'not placed'}); /units pane on tries again`)
  // Claude Code's timer is an object with cancel, not a function: calling it made every later begin throw.
  stopPoll?.cancel()
  spin?.cancel()
  spin = undefined
  // A session with the pane off (a card's own worktree) never fetches until /units is typed there. The first fetch
  // is not waited for: it asks another machine, and the session must not start late for it.
  stopPoll = $.clock.every(POLL_MS, () => { if (anyWanted()) void tick($).catch(() => undefined) })
  feedClock?.cancel()
  feedClock = undefined
  feedAt = -1
  feedKey = null
  feedBoard = null
  dataOver = null
  limitRead = null
  // Where the feed is, learnt here on this machine: waiting for the first fetch to say would leave the feed unread
  // for as long as the host takes to answer it. Not waited for either (the session would start up to 5 s late); the
  // first poll waits on the same run, and the second's check starts once it answers.
  const at = ++begins
  void nameFeedDir($, main)
    .then(() => { if (at === begins) feedClock = $.clock.every(STREAM_MS, () => feedTick($)) })
    .catch(() => (at === begins ? failed($) : undefined))
  if (anyWanted()) void tick($).catch(() => undefined)
}
// Which begin is the load's latest: an older one's feed folder answering late starts no second clock.
let begins = 0
// A begin that fails is not kept: the first session.start, render or /units a minute or more later tries it again
// (not every redraw, each with a git call).
let retryAt = 0
const failed = async ($: EngineInterface) => {
  retryAt = (await $.clock.now().catch(() => 0)) + POLL_MS
  begun = undefined
}
const ensureBegun = ($: EngineInterface) => (begun ??= (async () => {
  if ((await $.clock.now()) < retryAt) begun = undefined
  else await begin($)
})().catch(() => failed($)))

export const register: Register = (on, options) => {
  option = { pane: String(options.pane ?? 'auto') }
  // A changed option reloads the plugin and runs register again, so `motion` is read once here.
  motion = options.motion === 'on'
  // Until a poll reads the Board's Time (readTime).
  optionTime = options.time
  setClock(options.time)

  // The plugin's one session.start hook (Claude Code refuses a second with no matcher, and session.start takes none):
  // the /units begin, which never rejects, then the /conveyor-belt:auto band's (auto.tsx).
  on('session.start', async ($, e, next) => {
    await ensureBegun($)
    await refreshAutoBand($)
    return next(e)
  }).catch(($, e, next) => next(e))

  // The engine ends a command.run hook at 10 s and the fetch can take 75 s: /units starts one and answers at
  // once from the state the views hold; the views fill when the fetch lands.
  on('command.run', { command: 'units' }, async ($, e, next) => {
    await ensureBegun($)
    if (!main) return next(e)
    const [which, flip] = e.args.trim().toLowerCase().split(/\s+/)
    if (which === 'pane') {
      overrides.pane = flip !== 'off'
      const placed = await setViews($, true)
      void tick($).catch(() => undefined)
      const notDrawn = placed && placed.isPlaced === false ? ` (not drawn: ${placed.reason ?? 'not placed'})` : ''
      return { text: `units pane: ${overrides.pane ? 'on' : 'off'} for this session${notDrawn}` }
    }
    // The pane is the one view: any other word (the old `band` and `status` too) is refused, not taken for /units.
    if (which) return { text: `units: no view "${which}"; only the pane exists: /units, or /units pane on|off` }
    void tick($).catch(() => undefined)
    const s = (await read($, state)) as State | null
    return { text: s ? tableText(await drawnAt($, s), Math.max(40, Number(e.presentation?.columns) || 56)) : WAITING }
  }).catch(($, e, next) => next(e))

  // /units draws nothing above the prompt. This render only begins the load: it runs on every redraw, so a reload
  // with no session.start (the pane option turned on in /config) opens a pane that is not open yet.
  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    void ensureBegun($)
    return next(e)
  }).catch(($, e, next) => next(e))

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e, next) => {
    void ensureBegun($)
    const s = (await read($, state)) as State | null
    const { Box, Text, Button } = $.ui.resolve(e)
    if (!s) return <Text dimColor>{WAITING}</Text>
    // The pane's own width, with no upper limit: the terminal gives it as `bodyColumns`; a surface that leaves that
    // out gives the pane's size as `viewport`. 56 only when neither is given.
    const w = Math.max(40, Number(e.props.bodyColumns) || Number(e.viewport?.columns) || 56)
    const f = await read($, frame)
    const open = (await read($, details)) === true
    const flip = () => { void update($, details, v => !v).catch(() => undefined) }
    return (
      <Box flexDirection="column">
        {paneModel(await drawnAt($, s), w, f, open).map((l, i) => <Box key={`p${i}`} flexDirection="row">{l.length ? draw(Text, l, `p${i}`, Button, flip) : <Text> </Text>}</Box>)}
      </Box>
    )
  }).catch(($, e, next) => next(e))
}

// Each styled run is its own Text, so one line carries several colours. A run with an address (k) is a Button: the
// terminal draws its label as `[ label ]`, the run's own text.
const draw = (Text: any, line: Line, key: string, Button?: any, press?: () => void) => line.map((x, i) => (x.k && Button
  ? <Button key={x.k} label={x.t.replace(/^\[ | \]$/g, '')} hotkey="m" onPress={press} />
  : <Text key={`${key}-${i}`} color={x.c} bold={x.b} dimColor={x.d} inverse={x.i}>{x.t}</Text>))
