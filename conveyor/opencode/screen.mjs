// SPDX-License-Identifier: Apache-2.0
// What the guards of a card session that is not Claude's share (README.md, OpenCode builder and Codex builder): the
// OpenCode guard plugin (guard.mjs) and the Codex guard hook (../codex/guard.mjs) each give a call here, in the shape
// Claude Code gives a PreToolUse hook, and guard.sh beside this file runs the card's guards on it.
import { spawnSync } from "node:child_process"
import { dirname, isAbsolute, join, resolve } from "node:path"
import { fileURLToPath } from "node:url"

const RUNNER = join(dirname(fileURLToPath(import.meta.url)), "guard.sh")

// A path made absolute from the worktree, as a Claude hook reads it.
export const abs = (dir, p) => (typeof p === "string" && p !== "" && !isAbsolute(p) ? resolve(dir, p) : p)

// apply_patch's patch text as the Claude calls that make the same change, read as OpenCode 1.x's parsePatch and
// Codex's apply_patch read it (an optional heredoc around it, the lines between `*** Begin Patch` and
// `*** End Patch`): an added file is a Write of its contents, an updated one an Edit of each chunk's old lines to its
// new ones, and its `*** Move to:` a Write of those new lines to that path, a deleted file a Write of nothing to it.
// A patch that does not read as one, or names no file, is refused: its files could not be screened.
export function patchcalls(text, d) {
  const t = String(text ?? "").trim()
  const h = t.match(/^(?:cat\s+)?<<['"]?(\w+)['"]?\s*\n([\s\S]*?)\n\1\s*$/)
  const lines = (h ? h[2] : t).split("\n")
  const b = lines.findIndex((l) => l.trim() === "*** Begin Patch"), e = lines.findIndex((l) => l.trim() === "*** End Patch")
  if (b < 0 || e <= b) throw new Error("conveyor: this apply_patch call has no *** Begin Patch ... *** End Patch around it, so its files cannot be screened: refused")
  const calls = [], head = /^\*\*\* (Add|Delete|Update) File:(.*)$/
  for (let i = b + 1; i < e; ) {
    const m = lines[i].match(head), path = m && m[2].trim()
    if (!path) { i++; continue }
    const file = abs(d, path)
    i++
    if (m[1] === "Delete") { calls.push(["Write", { file_path: file, content: "" }]); continue }
    if (m[1] === "Add") {
      const c = []
      for (; i < e && !lines[i].startsWith("***"); i++) if (lines[i].startsWith("+")) c.push(lines[i].slice(1))
      calls.push(["Write", { file_path: file, content: c.join("\n") }])
      continue
    }
    let to = null
    if (i < e && lines[i].startsWith("*** Move to:")) { to = lines[i].slice("*** Move to:".length).trim(); i++ }
    const added = []
    let chunk = null
    const close = () => { if (chunk) calls.push(["Edit", { file_path: file, old_string: chunk.o.join("\n"), new_string: chunk.n.join("\n"), replace_all: false }]) }
    for (; i < e && !(lines[i].startsWith("***") && lines[i] !== "*** End of File"); i++) {
      const l = lines[i]
      if (l.startsWith("@@")) { close(); chunk = { o: [], n: [] }; continue }
      if (!chunk || l === "*** End of File") continue
      if (l.startsWith(" ")) { chunk.o.push(l.slice(1)); chunk.n.push(l.slice(1)) }
      else if (l.startsWith("-")) chunk.o.push(l.slice(1))
      else if (l.startsWith("+")) { chunk.n.push(l.slice(1)); added.push(l.slice(1)) }
    }
    close()
    if (to) calls.push(["Write", { file_path: abs(d, to), content: added.join("\n") }])
  }
  if (!calls.length) throw new Error("conveyor: this apply_patch call names no file, so it cannot be screened: refused")
  return calls
}

// One call through guard.sh: nothing when the guards allow it, the rewritten input when a hook rewrote it; a throw
// with the guard's message when they refuse it or cannot run.
export function screen(settings, dir, cwd, sessionID, tool, input) {
  const payload = { session_id: sessionID, cwd, hook_event_name: "PreToolUse", tool_name: tool, tool_input: input }
  const r = spawnSync("bash", [RUNNER, settings], {
    input: JSON.stringify(payload), encoding: "utf8", cwd: dir, maxBuffer: 16 * 1024 * 1024,
    env: { ...process.env, CLAUDE_PROJECT_DIR: dir },
  })
  if (r.status === 2) throw new Error((r.stderr || "").trim() || "conveyor: refused by a card guard, with no reason given")
  if (r.status !== 0) throw new Error(`conveyor: the card guards could not run (${r.error ? r.error.message : `exit ${r.status}`}): refused. ${(r.stderr || "").trim().slice(-400)}`)
  const out = (r.stdout || "").trim()
  if (!out) return null
  try { return JSON.parse(out).updatedInput || null } catch { throw new Error("conveyor: the card guards answered with what is not JSON: refused") }
}
