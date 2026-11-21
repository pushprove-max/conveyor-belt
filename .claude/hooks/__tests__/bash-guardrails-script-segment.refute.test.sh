#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The in-place write scan reads only the python/node invocation and its heredoc,
# never the rest of the command: echoed text is not a write, and unlike a
# caller-hunt refusal a retry could never clear this one.
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
HOOK=$ROOT/.claude/hooks/bash-guardrails.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/said.sh" # a FAIL line names the hook's last input
CMD="node -e \"console.log(1)\" && echo \"open('src/x.ts', 'w')\""

set +e
jq -cn --arg cmd "$CMD" --arg cwd "$ROOT" \
  '{session_id:"script-segment-refute",cwd:$cwd,tool_input:{command:$cmd}}' \
  | bash "$HOOK" >/dev/null 2>&1
RC=$?
set -e

[ "$RC" -eq 0 ] || {
  echo "FAIL: harmless quoted text was refused with $RC$(said)" >&2
  exit 1
}
echo "PASS"
