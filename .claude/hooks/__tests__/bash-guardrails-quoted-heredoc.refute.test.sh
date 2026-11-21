#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# A `<<EOF` inside a quoted argument declares no heredoc, so the in-place write
# scan must not swallow the next line's echoed text as a node script.
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
. "$(dirname "${BASH_SOURCE[0]}")/lib/said.sh" # a FAIL line names the hook's last input
CMD=$'node -e "console.log(\x27<<EOF\x27)"\necho "open(\x27src/x.ts\x27, \x27w\x27)"'
RC=0
jq -cn --arg cmd "$CMD" --arg cwd "$ROOT" '{session_id:"quoted-heredoc-refute",cwd:$cwd,tool_input:{command:$cmd}}' | bash "$ROOT/.claude/hooks/bash-guardrails.sh" >/dev/null 2>&1 || RC=$?
[ "$RC" -eq 0 ] || { echo "FAIL: harmless output refused with $RC$(said)"; exit 1; }
echo "PASS"
