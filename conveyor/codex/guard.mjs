// SPDX-License-Identifier: Apache-2.0
// The guard hook of a Codex card session (README.md, Codex builder). session.sh gives it to every Codex build, fix and
// rebase session as Codex's one PreToolUse hook, matching every tool (`-c hooks.PreToolUse=...`), and starts none
// without it. Codex gives it each call as Claude Code gives a PreToolUse hook (tool_name, tool_input, cwd on stdin),
// and it hands the call, as the Claude calls that do the same, to ../opencode/guard.sh, which runs the hooks of the
// card's settings file, the one a Claude session of the card runs with. It answers as Codex reads a PreToolUse hook:
// a refused call is exit 2 with the guard's message on stderr (Codex runs no such call, and tells the model the
// message); a command a hook rewrote is {"hookSpecificOutput": {permissionDecision: "allow", updatedInput}}, and
// Codex runs the rewrite; an allowed call is exit 0 and nothing. A tool this file does not map to one of Claude's is
// refused, as is any call when the guards cannot run: never run unguarded.
// Usage: node guard.mjs <the card's settings file> <worktree> < <the call>
import { readFileSync, writeSync } from "node:fs"
import { abs, patchcalls, screen } from "../opencode/screen.mjs"

const [settings, dir] = process.argv.slice(2)
// Written at once (writeSync): a pipe written the other way may not be flushed before the exit.
const no = (why) => { writeSync(2, String(why).trim() + "\n"); process.exit(2) }

// Codex's tools by Claude's name for them, each with the input a Claude hook reads. Codex runs every shell command
// as Bash (exec_command, its tool_input the command). apply_patch, its file tool, is screened file by file below.
// Codex runs no hook for write_stdin (keys sent to a command already running), so this file never sees it: session.sh
// runs commands without a terminal (--disable unified_exec_tty), their input closed, so Codex refuses any keys sent to
// one and the tool can only wait for output. Subagents, questions, MCP tools and the rest are not here and are
// refused.
const TOOLS = {
  Bash: ["Bash", (a) => ({ command: a.command, description: a.description, timeout: a.timeout })],
  update_plan: ["TodoWrite", (a) => ({ todos: a.plan })],
  view_image: ["Read", (a, d) => ({ file_path: abs(d, a.path) })],
}

try {
  if (!settings) no("conveyor: no card settings file is named for the Codex guard hook, so no guard can run: refused")
  if (!dir) no("conveyor: no worktree is named for the Codex guard hook: refused")
  let call
  try { call = JSON.parse(readFileSync(0, "utf8")) } catch { no("conveyor: the call Codex gave the guard hook is not JSON: refused") }
  const tool = call && call.tool_name, args = (call && call.tool_input && typeof call.tool_input === "object") ? call.tool_input : {}
  // A command run in another folder (its workdir) is screened from that folder, as Claude Code's cwd.
  const cwd = abs(dir, tool === "Bash" && typeof args.workdir === "string" && args.workdir !== "" ? args.workdir
    : typeof call.cwd === "string" && call.cwd !== "" ? call.cwd : dir)
  if (tool === "apply_patch") {
    // Every file of the patch is screened; one refused refuses the patch, and a rewrite cannot be put back into it.
    for (const [t, i] of patchcalls(args.command ?? args.input ?? args.patch, cwd))
      if (screen(settings, dir, cwd, call.session_id, t, i)) no(`conveyor: a card guard rewrote the ${t} of ${i.file_path} in this apply_patch call, and only a command's rewrite can be applied here: refused`)
    process.exit(0)
  }
  const map = TOOLS[tool]
  if (!map) no(`conveyor: the tool ${tool} is not one a card session may use (it may use ${[...Object.keys(TOOLS), "apply_patch"].join(", ")}): refused`)
  const rewrite = screen(settings, dir, cwd, call.session_id, map[0], map[1](args, cwd))
  if (!rewrite) process.exit(0)
  // Only a command's rewrite can be put back into Codex's call as it was meant; any other is refused.
  if (map[0] !== "Bash" || typeof rewrite.command !== "string") no(`conveyor: a card guard rewrote this ${tool} call, and only a command's rewrite can be applied here: refused`)
  writeSync(1, JSON.stringify({ hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "allow", updatedInput: { ...args, command: rewrite.command } } }) + "\n")
} catch (e) {
  no(e && e.message ? e.message : `conveyor: the Codex guard hook failed (${e}): refused`)
}
