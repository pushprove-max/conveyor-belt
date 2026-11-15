#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The command guards of a card session, for one tool call of an OpenCode or Codex session (screen.mjs calls this
# before each call, for guard.mjs and for ../codex/guard.mjs; README.md, OpenCode builder and Codex builder). The guards are the PreToolUse hooks of the card's settings file, the same file a
# Claude session of the card is given with --settings (cardsettings(): the engine's card-settings.json and the pack's
# hooks.json), and its permissions' deny rules. Each hook whose matcher matches the call's tool (a regex over Claude's
# tool names, as Claude Code matches it) runs in file order, from the worktree, with CLAUDE_PROJECT_DIR set to it and
# the call on stdin in the shape Claude Code gives a hook (guard.js makes it), and the call is refused as Claude Code
# refuses it: exit 2 (its stderr is why), a JSON answer that blocks or denies (or asks: a headless session has nobody
# to ask), or any other failure of a hook the settings mark `onFailure: block`, a timeout among them (its `timeout`,
# else Claude Code's 60 s). A hook that rewrites the call (updatedInput) passes the rewritten call to the hooks after
# it, and the call runs as rewritten.
# Usage: guard.sh <settings file> < <the call, {session_id, cwd, hook_event_name, tool_name, tool_input}>
# Exit 0: allowed, and stdout is {"updatedInput": <tool_input>} when a hook rewrote it. Exit 2: refused, why on stderr.
# A settings file or a call that cannot be read refuses the call: no guard could run on it.
set -uo pipefail
s=${1:-}
no() { printf '%s\n' "$1" >&2; exit 2; }
[ -f "$s" ] && [ -r "$s" ] && jq -e 'objects' "$s" >/dev/null 2>&1 \
  || no "conveyor: the card's settings file ${s:-(none named)} cannot be read, so no guard can run on this call: it is refused"
dir=${CLAUDE_PROJECT_DIR:-}
[ -n "$dir" ] && [ -d "$dir" ] || no "conveyor: no worktree is named for the guards (CLAUDE_PROJECT_DIR): the call is refused"
in=$(cat); tool=$(jq -er '.tool_name | strings' <<<"$in" 2>/dev/null) || no "conveyor: the call given to the guards names no tool: it is refused"

# The permissions' deny rules, Tool(<pattern>), on the path the call names: a pattern is a shell pattern, matched
# against the path as given and as relative to the worktree (`*` matches across folders, so **/x is any x).
p=$(jq -r '.tool_input | objects | .file_path // .path // empty | strings' <<<"$in")
if [ -n "$p" ]; then
  while IFS= read -r g; do
    # shellcheck disable=SC2053 # $g is a pattern
    [[ $p == $g || ${p#"$dir"/} == $g ]] && no "conveyor: the card's settings deny $tool($g): $p is not to be read or written in a card session"
  done < <(jq -r --arg t "$tool" '.permissions.deny // [] | .[] | strings | capture("^(?<t>[A-Za-z]+)\\((?<g>.+)\\)$") | select(.t == $t) | .g' "$s")
fi

# The hooks for this tool, one a line: <timeout> <onFailure> <command>. A list that cannot be read (a matcher that is
# no regex) refuses the call, never runs none.
hooks=$(jq -r --arg t "$tool" '.hooks.PreToolUse // [] | .[] | objects
    | select((.matcher // "") as $m | $m == "" or $m == "*" or ($t | test("^(" + $m + ")$")))
    | .hooks // [] | .[] | objects | select(.type == "command" and (.command | type) == "string")
    | "\(.timeout // 60)\t\(.onFailure // "-")\t\(.command)"' "$s" 2>&1) \
  || no "conveyor: the PreToolUse hooks of the card's settings file $s cannot be read ($hooks): the call is refused"
err=$(mktemp) || no "conveyor: the guards cannot make a temporary file: the call is refused"
trap 'rm -f "$err"' EXIT
changed=0
export CLAUDE_PROJECT_DIR=$dir
while IFS=$'\t' read -r t onfail cmd; do
  [ -n "$cmd" ] || continue
  out=$(cd "$dir" && printf '%s' "$in" | timeout --kill-after=5 "$t" bash -c "$cmd" 2> "$err"); rc=$?
  # The hook's name for a message: the last script the command names (the card's are '<root>'/.claude/hooks/<name>).
  name=$(grep -oE "[^/'\" ]+\.(sh|py|mjs|js)" <<<"$cmd" | tail -n 1); [ -n "$name" ] || name=${cmd:0:80}
  [ $rc != 2 ] || no "$(cat "$err")"
  if [ $rc = 0 ] && [ -n "$out" ] && jq -e 'objects' <<<"$out" >/dev/null 2>&1; then
    why=$(jq -r 'select(.decision == "block" or (.hookSpecificOutput.permissionDecision | IN("deny", "ask")))
      | .hookSpecificOutput.permissionDecisionReason // .reason // "refused, with no reason given"' <<<"$out")
    [ -z "$why" ] || no "$why"
    if jq -e '.hookSpecificOutput.updatedInput | objects' <<<"$out" >/dev/null 2>&1; then
      in=$(jq -c --argjson o "$out" '.tool_input = $o.hookSpecificOutput.updatedInput' <<<"$in") && changed=1 \
        || no "conveyor: $name rewrote the call and the rewrite cannot be read: the call is refused"
    fi
  fi
  # A hook marked blocking that gave no answer (crashed, killed, timed out, or not there to run) refuses the call.
  [ $rc = 0 ] || [ "$onfail" != block ] \
    || no "conveyor: the guard $name exited $rc$([ $rc != 124 ] || echo " (it ran past its ${t}s)") and the card's settings mark its failure as blocking: the call is refused. $(tail -c 400 "$err")"
done <<<"$hooks"
[ $changed = 0 ] || jq -c '{updatedInput: .tool_input}' <<<"$in"
exit 0
