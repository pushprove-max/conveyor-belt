#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Runs one guard hook of a card session and makes its failure loud. cardsettings() (lib/prompts.sh) puts each
# PreToolUse hook of the card's settings that is marked `onFailure: block` behind this script, for Claude, OpenCode and
# Codex sessions alike (opencode/guard.sh runs the same settings file). A hook that answers (exit 0, or exit 2: a
# refusal) is passed through as it is. A hook that fails to run refuses the call, and the refusal (stderr, exit 2: the
# text the session sees) names the hook and why it failed: it crashed (its exit code and its last error line), it ran
# past its time-out, or its file is missing. Each failure is one line, <hook>\t<why>, in <worktree>.guardfail (the
# worktree is CLAUDE_PROJECT_DIR). The second failure of one hook in a session also stops the session (a JSON answer
# with "continue": false, which Claude Code obeys; OpenCode and Codex read only its deny, so watch() in lib/session.sh
# ends them at its look after the one that saw the second line, once the session has had the deny), and session1()
# then blocks the card with the reason "guard <hook> is failing: <why>".
# Usage: guardrun.sh <timeout in seconds> <the hook's command> < <the call>
set -uo pipefail
t=${1:-60} cmd=${2:-}
no() { printf '%s\n' "$1" >&2; exit 2; }
[[ $t =~ ^[0-9]+$ ]] && [ -n "$cmd" ] || no "conveyor: the guard runner was given no time-out or no hook command, so no guard ran: the call is refused"
o=$(mktemp) && err=$(mktemp) || no "conveyor: the guard runner cannot make a temporary file: the call is refused"
trap 'rm -f "$o" "$err"' EXIT
timeout --kill-after=5 "$t" bash -c "$cmd" > "$o" 2> "$err"; rc=$?
if [ $rc = 0 ] || [ $rc = 2 ]; then cat "$o"; cat "$err" >&2; exit $rc; fi
# The hook's name: the last script its command names (as opencode/guard.sh names it), else the command's start.
name=$(grep -oE "[^/'\" ]+\.(sh|py|mjs|js)" <<<"$cmd" | tail -n 1); [ -n "$name" ] || name=${cmd:0:80}
last=$(grep -v '^[[:space:]]*$' "$err" | tail -n 1 | cut -c1-300); last=${last:-no error output}
case $rc in
  124 | 137) why="it ran past its ${t}s time-out" ;;
  127) why="its file is missing ($last)" ;;
  *) why="it crashed with exit $rc: $last" ;;
esac
msg="conveyor: the guard $name failed to run: $why. The call is refused."
dir=${CLAUDE_PROJECT_DIR:-}
[ -n "$dir" ] || no "$msg"
printf '%s\t%s\n' "$name" "$why" >> "$dir.guardfail"
n=$(awk -F'\t' -v h="$name" '$1 == h' "$dir.guardfail" | wc -l)
[ "$n" -ge 2 ] || no "$msg"
msg+=" It failed for the second time in this session, so the session stops and the card blocks."
jq -cn --arg m "$msg" '{continue: false, stopReason: $m,
  hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $m}}' || no "$msg"
exit 0
