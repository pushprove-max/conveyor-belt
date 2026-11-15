#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# `python3 -W ignore` still reads its program from stdin: `ignore` is the
# value of -W, not a script file, so the in-place write guard scans the heredoc.
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
HOOK=$ROOT/.claude/hooks/bash-guardrails.sh
CMD=$'cat <<\'PY\' | python3 -W ignore\nopen(\'src/x.ts\', \'w\').write(\'x\')\nPY'

RC=0
jq -cn --arg cmd "$CMD" --arg cwd "$ROOT" \
  '{session_id:"python-option-refute",cwd:$cwd,tool_input:{command:$cmd}}' \
  | bash "$HOOK" >/dev/null 2>&1 || RC=$?

[ "$RC" -eq 2 ] || {
  echo "FAIL: Python source write after -W operand passed with $RC" >&2
  exit 1
}
echo "PASS"
