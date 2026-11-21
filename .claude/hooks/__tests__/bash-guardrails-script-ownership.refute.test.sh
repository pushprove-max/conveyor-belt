#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The in-place write scan keeps a script's text however the command is laid out:
# a multi-line `python3 -c` argument, and a python heredoc piped into another
# command, are still refused when they write a source file.
set -eu
ROOT=$(git rev-parse --show-toplevel)
. "$(dirname "${BASH_SOURCE[0]}")/lib/said.sh" # a FAIL line names the hook's last input
for CMD in \
  $'python3 -c "\nopen(\x27src/x.ts\x27, \x27w\x27).write(\x27x\x27)\n"' \
  $'python3 - <<\x27PYCODE\x27 | cat\nopen(\x27src/x.ts\x27, \x27w\x27).write(\x27x\x27)\nPYCODE'
do
  RC=0
  jq -cn --arg cmd "$CMD" --arg cwd "$ROOT" '{session_id:"script-ownership-refute",cwd:$cwd,tool_input:{command:$cmd}}' | bash "$ROOT/.claude/hooks/bash-guardrails.sh" >/dev/null 2>&1 || RC=$?
  [ "$RC" -eq 2 ] || { echo "FAIL: expected refusal, got $RC$(said)"; exit 1; }
done
echo "PASS"
