#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Pins who may ask the owner: a card or worker session (a linked worktree) is refused, because its picker draws in
# that session alone and the session would wait forever; the main checkout, the owner's and the Foreman's, may ask.
set -u
. "$(dirname "$0")/lib/rulings-fixture.sh"
HOOK=$PLUG/.claude/hooks/worker-ask-guard.sh
ask() { jq -cn --arg cwd "$1" '{tool_name:"AskUserQuestion", cwd:$cwd, tool_input:{questions:[{question:"Which?"}]}}' | bash "$HOOK" 2>&1; echo "rc=$?"; }

out=$(ask "$CARD")
check "a card session's question to the owner is refused" "rc=2" "$(tail -n 1 <<<"$out")"
check "the refusal tells the session to choose a default and carry on" yes "$(grep -q 'Choose a reasonable default' <<<"$out" && echo yes || echo no)"
check "a card session is refused when CLAUDE_PROJECT_DIR names it" 2 \
  "$(jq -cn '{tool_name:"AskUserQuestion", tool_input:{}}' | CLAUDE_PROJECT_DIR=$CARD bash "$HOOK" >/dev/null 2>&1; echo $?)"
check "the main checkout may ask" "rc=0" "$(ask "$MAIN")"
finish
