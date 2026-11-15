#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# `nice -n 5 python3` is a wrapped python: the value of `-n` is not the command,
# so a heredoc piped into it is still scanned by the in-place write guard.
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
HOOK=$ROOT/.claude/hooks/bash-guardrails.sh
CMD=$'cat <<\'PY\' | nice -n 5 python3\nopen(\'src/x.ts\', \'w\').write(\'x\')\nPY'

RC=0
jq -cn --arg cmd "$CMD" --arg cwd "$ROOT" \
  '{session_id:"nice-wrapper-refute",cwd:$cwd,tool_input:{command:$cmd}}' \
  | bash "$HOOK" >/dev/null 2>&1 || RC=$?

[ "$RC" -eq 2 ] || {
  echo "FAIL: nice-wrapped Python source write passed with $RC" >&2
  exit 1
}
echo "PASS"
