// SPDX-License-Identifier: Apache-2.0
// What every /units view is drawn with: styled text runs, theme colours, widths in terminal cells and the few formats
// (dollars, ages, clock times, model names) the sections share. Nothing here knows the snapshot.
export type Seg = { t: string; c?: string; b?: boolean; d?: boolean }
export type Line = Seg[]

// Claude Code theme keys, never raw colours, so a light or colour-blind theme recolours every view. `you`: what needs
// you.
export const C = { you: 'warning', ok: 'success', bad: 'error', work: 'suggestion', cost: 'claude', head: 'permission', dim: 'inactive', name: 'text' } as const

export const plain = (l: Line) => l.map(x => x.t).join('')
export const usd = (n: number) => `$${n.toFixed(2)}`
// A count of tokens: 950, 412k, 1.3M.
export const tokens = (n: number) => (n < 1000 ? `${n}` : n < 999_500 ? `${Math.round(n / 1000)}k` : `${(n / 1e6).toFixed(1)}M`)

// Width in terminal cells, as wcwidth counts them: per whole character (grapheme), 0 when every code point is
// zero-width or combining, 2 for emoji presentation or East Asian Wide/Fullwidth, else 1. `.length` is wrong for all three.
const GRAPHEMES = new Intl.Segmenter(undefined, { granularity: 'grapheme' })
const ZERO = /^[\p{Mn}\p{Me}\p{Cf}]+$/u
const WIDE = /[\p{Emoji_Presentation}\u{FE0F}\u{1100}-\u{115F}\u{2E80}-\u{A4CF}\u{AC00}-\u{D7A3}\u{F900}-\u{FAFF}\u{FE30}-\u{FE4F}\u{FF00}-\u{FF60}\u{FFE0}-\u{FFE6}\u{20000}-\u{3FFFD}]/u
const cell = (g: string) => (ZERO.test(g) ? 0 : WIDE.test(g) ? 2 : 1)
export const cols = (t: string) => {
  let n = 0
  for (const { segment } of GRAPHEMES.segment(t)) n += cell(segment)
  return n
}

// A line cut to `w` columns between whole characters, ending in `…`; a line that fits is returned as it is.
// Named fitWidth, not fit: a test-skip check reads any call of `fit(` as a focused test.
export const fitWidth = (line: Line, w: number): Line => {
  if (cols(plain(line)) <= w) return line
  const out: Line = []
  let room = Math.max(0, w - 1)
  for (const s of line) {
    let t = ''
    for (const { segment } of GRAPHEMES.segment(s.t)) {
      const c = cell(segment)
      if (c > room) return [...out, { ...s, t }, { ...s, t: '…' }]
      room -= c
      t += segment
    }
    out.push({ ...s, t })
  }
  return out
}

// Text on the left, a value pushed to the right edge of `w` columns; the left is cut first, the right kept whole.
export const spread = (left: Line, right: Seg | Line | null, w: number): Line => {
  const r = right ? (Array.isArray(right) ? right : [right]) : []
  const rw = cols(plain(r))
  if (!r.length || rw + 3 > w) return fitWidth(left, w)
  const l = fitWidth(left, w - rw - 2)
  return [...l, { t: ' '.repeat(w - cols(plain(l)) - rw) }, ...r]
}

// The mark of a card on the belt. It turns only while the `motion` option is on; frame 0 is the still mark.
export const workMark = (frame: number) => '◐◓◑◒'[((frame % 4) + 4) % 4]

// Minutes and hours only: seconds churn every poll and say nothing a person acts on.
export const fmtSec = (s: number) => (s >= 3600 ? `${Math.floor(s / 3600)}h ${Math.floor((s % 3600) / 60)}m` : `${Math.max(1, Math.floor(s / 60))}m`)
// A step of a card's track is often seconds long, so under a minute its seconds are given.
export const fmtStep = (s: number) => (s < 60 ? `${Math.max(0, Math.round(s))}s` : fmtSec(s))
export const since = (t: number | null, now: number) => (t ? fmtSec(Math.max(0, Math.round((now - t) / 1000))) : '')
// 12-hour with AM/PM, as the Board's page prints a time.
export const clockOf = (t: number) => { const d = new Date(t); return `${d.getHours() % 12 || 12}:${String(d.getMinutes()).padStart(2, '0')} ${d.getHours() < 12 ? 'AM' : 'PM'}` }
export const modelName = (id: string) => id.replace(/^claude-([a-z]+)-(\d+)-(\d+)$/, (_, f: string, a, b) => `${f[0].toUpperCase()}${f.slice(1)} ${a}.${b}`)

export const gauge = (pct: number): Seg[] => {
  const k = Math.max(0, Math.min(10, Math.round(pct / 10)))
  return [{ t: '▰'.repeat(k), c: C.cost }, { t: '▱'.repeat(10 - k), c: C.dim }]
}
// The time left to a reset: days and hours, or under a day hours and minutes.
export const resetIn = (t: number, now: number) => {
  const s = Math.round((t - now) / 1000)
  if (s <= 0) return ''
  const d = Math.floor(s / 86400)
  return d ? `${d}d ${Math.floor((s % 86400) / 3600)}h` : fmtSec(s)
}
