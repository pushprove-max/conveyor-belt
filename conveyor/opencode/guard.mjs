// SPDX-License-Identifier: Apache-2.0
// The guard plugin of an OpenCode card session (README.md, OpenCode builder). session.sh loads it into every OpenCode
// build, fix and rebase session (the `plugin` of the config file OPENCODE_CONFIG names) and starts none without it.
// Before each tool call (OpenCode 1.x's tool.execute.before), it gives the call to guard.sh beside it, in the shape
// Claude Code gives a PreToolUse hook (tool_name, tool_input), and guard.sh runs the card's guards on it: the hooks of
// the card's settings file, the one a Claude session of the card runs with. A call they refuse is refused here with
// their message (a throw: OpenCode runs no tool whose before hook throws, and the model is told the message); a call
// a hook rewrote runs as rewritten. A tool this file does not map to one of Claude's is refused, as is any call
// when the guards cannot run: never run unguarded.
import { abs, patchcalls, screen } from "./screen.mjs"

// OpenCode's tools by Claude's name for them, each with the input a Claude hook reads (camelCase to snake_case, a
// path made absolute from the worktree). apply_patch (the file tool OpenCode gives GPT models in place of edit and
// write) is screened file by file below (patchcalls, screen.mjs). Agent (task), AskUserQuestion (question), patch, batch and MCP
// tools are not here: a card session runs no subagent and asks nobody, and the rest are refused.
const TOOLS = {
  bash: ["Bash", (a) => ({ command: a.command, description: a.description, timeout: a.timeout })],
  edit: ["Edit", (a, d) => ({ file_path: abs(d, a.filePath), old_string: a.oldString, new_string: a.newString, replace_all: a.replaceAll === true })],
  multiedit: ["MultiEdit", (a, d) => ({ file_path: abs(d, a.filePath), edits: (Array.isArray(a.edits) ? a.edits : []).map((e) => ({
    old_string: e && e.oldString, new_string: e && e.newString, replace_all: !!(e && e.replaceAll) })) })],
  write: ["Write", (a, d) => ({ file_path: abs(d, a.filePath), content: a.content })],
  read: ["Read", (a, d) => ({ file_path: abs(d, a.filePath), offset: a.offset, limit: a.limit })],
  grep: ["Grep", (a, d) => ({ pattern: a.pattern, path: abs(d, a.path), glob: a.include })],
  glob: ["Glob", (a, d) => ({ pattern: a.pattern, path: abs(d, a.path) })],
  list: ["LS", (a, d) => ({ path: abs(d, a.path) })],
  todowrite: ["TodoWrite", (a) => ({ todos: a.todos })],
  todoread: ["TodoRead", () => ({})],
  webfetch: ["WebFetch", (a) => ({ url: a.url, format: a.format })],
  websearch: ["WebSearch", (a) => ({ query: a.query })],
}

// One default export, {id, server}: OpenCode 1.x's loader reads it as a plugin module, and its older scan of the
// exports finds the one server too. The worktree is the one the engine names (CLAUDE_PROJECT_DIR, as for a Claude
// session), else OpenCode's folder.
async function server(input) {
  const dir = process.env.CLAUDE_PROJECT_DIR || (input && input.directory) || process.cwd()
  return {
    "tool.execute.before": async (call, output) => {
      const tool = call && call.tool, map = TOOLS[tool]
      if (!map && tool !== "apply_patch") throw new Error(`conveyor: the tool ${tool} is not one a card session may use (it may use ${Object.keys(TOOLS).join(", ")}, apply_patch): refused`)
      const settings = process.env.CONVEYOR_GUARD_SETTINGS
      if (!settings) throw new Error("conveyor: no card settings file is named (CONVEYOR_GUARD_SETTINGS), so no guard can run: refused")
      const args = (output && output.args) || {}
      if (!map) {
        // Every file of the patch is screened; one refused refuses the patch, and a rewrite cannot be put back into it.
        for (const [t, i] of patchcalls(args.patchText, dir))
          if (screen(settings, dir, dir, call.sessionID, t, i)) throw new Error(`conveyor: a card guard rewrote the ${t} of ${i.file_path} in this apply_patch call, and only a command's rewrite can be applied here: refused`)
        return
      }
      // A command run in another folder (bash's workdir) is screened from that folder, as Claude Code's cwd.
      const cwd = map[0] === "Bash" && typeof args.workdir === "string" && args.workdir !== "" ? abs(dir, args.workdir) : dir
      const rewrite = screen(settings, dir, cwd, call.sessionID, map[0], map[1](args, dir))
      if (!rewrite) return
      // Only a command's rewrite can be put back into OpenCode's call as it was meant; any other is refused.
      if (map[0] === "Bash" && rewrite && typeof rewrite.command === "string") output.args.command = rewrite.command
      else if (rewrite) throw new Error(`conveyor: a card guard rewrote this ${call.tool} call, and only a command's rewrite can be applied here: refused`)
    },
  }
}

export default { id: "conveyor-guard", server }
