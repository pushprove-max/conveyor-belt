// SPDX-License-Identifier: Apache-2.0
// The guard hook of an Antigravity (agy) card session (lib/agy.sh). agyready() writes it into the worktree's
// .agents/hooks.json, the workspace hooks file agy reads, as agy's one PreToolUse hook on every tool, and no agy
// session starts without it. agy gives it each call as {toolCall: {name, args}, workspacePaths, ...} on stdin; it
// hands the call, in the shape Claude Code gives a PreToolUse hook, to ../opencode/guard.sh (through screen.mjs),
// which runs the hooks of the card's settings file, the one a Claude session of the card runs with. It answers as agy
// reads a PreToolUse hook: a refused call is {"decision": "deny", reason} on stdout (agy runs no such call, and tells
// the model the reason); an allowed call is nothing. A command a hook rewrote runs as rewritten: {"decision": "allow",
// "overwrite": {"CommandLine": <the rewrite>}}, which agy merges into the call's arguments. Any other rewrite is
// refused: only a command's is put back, as in ../opencode/guard.mjs. A tool this file does not
// map to one of Claude's is refused, as is a call on the hooks file itself and any call when the guards cannot run:
// never run unguarded.
// Usage: node guard.mjs <the card's settings file> <worktree> < <the call>
import { readFileSync, writeSync } from "node:fs"
import { relative, isAbsolute } from "node:path"
import { abs, screen } from "../opencode/screen.mjs"

const [settings, dir] = process.argv.slice(2)
// Written at once (writeSync): a pipe written the other way may not be flushed before the exit.
const no = (why) => {
  const r = String(why).trim()
  writeSync(1, JSON.stringify({ decision: "deny", reason: r }) + "\n"); writeSync(2, r + "\n"); process.exit(0)
}

// agy's tools (its hooks page names them and their arguments) by Claude's name for them, each with the input a Claude
// hook reads. A subagent, a schedule, a message, a permission asked for, a task's input and the rest are not here,
// and are refused: a card session runs no subagent and asks nobody.
const TOOLS = {
  run_command: ["Bash", (a) => ({ command: a.CommandLine })],
  view_file: ["Read", (a, d) => ({ file_path: abs(d, a.AbsolutePath) })],
  list_dir: ["LS", (a, d) => ({ path: abs(d, a.DirectoryPath) })],
  find_by_name: ["Glob", (a, d) => ({ pattern: a.Pattern, path: abs(d, a.SearchDirectory) })],
  grep_search: ["Grep", (a, d) => ({ pattern: a.Query, path: abs(d, a.SearchPath) })],
  write_to_file: ["Write", (a, d) => ({ file_path: abs(d, a.TargetFile), content: a.CodeContent })],
  replace_file_content: ["Edit", (a, d) => ({ file_path: abs(d, a.TargetFile), old_string: a.TargetContent, new_string: a.ReplacementContent,
    replace_all: a.AllowMultiple === true })],
  multi_replace_file_content: ["MultiEdit", (a, d) => ({ file_path: abs(d, a.TargetFile), edits: (Array.isArray(a.ReplacementChunks) ? a.ReplacementChunks : [])
    .map((c) => ({ old_string: c && c.TargetContent, new_string: c && c.ReplacementContent, replace_all: !!(c && c.AllowMultiple === true) })) })],
  search_web: ["WebSearch", (a) => ({ query: a.query })],
  read_url_content: ["WebFetch", (a) => ({ url: a.Url })],
}
// The file tools: each names the file it writes, or it is refused (no guard could read which file).
const WRITES = new Set(["write_to_file", "replace_file_content", "multi_replace_file_content"])

try {
  if (!settings) no("conveyor: no card settings file is named for the agy guard hook, so no guard can run: refused")
  if (!dir) no("conveyor: no worktree is named for the agy guard hook: refused")
  let call
  try { call = JSON.parse(readFileSync(0, "utf8")) } catch { no("conveyor: the call agy gave the guard hook is not JSON: refused") }
  const tc = call && typeof call.toolCall === "object" && call.toolCall ? call.toolCall : {}
  const tool = tc.name, args = tc.args && typeof tc.args === "object" ? tc.args : {}
  const map = TOOLS[tool]
  if (!map) no(`conveyor: the tool ${tool} is not one a card session may use (it may use ${Object.keys(TOOLS).join(", ")}): refused`)
  // A command run in another folder (its Cwd) is screened from that folder, as Claude Code's cwd.
  const cwd = abs(dir, tool === "run_command" && typeof args.Cwd === "string" && args.Cwd !== "" ? args.Cwd : dir)
  const input = map[1](args, cwd)
  if (WRITES.has(tool) && (typeof input.file_path !== "string" || input.file_path === ""))
    no(`conveyor: this ${tool} call names no file (TargetFile), so no guard can screen it: refused`)
  // The hooks file is the guard: a call on it, or on the folder it is in, could undo it. A command is refused when it
  // names .agents anywhere; a file tool when its path is in the worktree's .agents folder.
  const inhooks = (p) => { const r = relative(abs(dir, ".agents"), p); return r === "" || (!r.startsWith("..") && !isAbsolute(r)) }
  if (tool === "run_command" ? String(input.command ?? "").includes(".agents")
    : [input.file_path, input.path].some((p) => typeof p === "string" && p !== "" && inhooks(p)))
    no("conveyor: this call names .agents/, which holds the card's guard hook (.agents/hooks.json): refused")
  const rewrite = screen(settings, dir, cwd, call.conversationId, map[0], input)
  if (!rewrite) process.exit(0)
  // A command a guard rewrote (bounded, or wrapped, as a guard that counts its runs records it) runs as rewritten:
  // agy merges overwrite into the call's arguments before it runs it.
  if (map[0] === "Bash" && typeof rewrite.command === "string") {
    writeSync(1, JSON.stringify({ decision: "allow", overwrite: { CommandLine: rewrite.command } }) + "\n"); process.exit(0)
  }
  no(`conveyor: a card guard rewrote this ${tool} call, and only a command's rewrite can be given back here: refused`)
} catch (e) {
  no(e && e.message ? e.message : `conveyor: the agy guard hook failed (${e}): refused`)
}
