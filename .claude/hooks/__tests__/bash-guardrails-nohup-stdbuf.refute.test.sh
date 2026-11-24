#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# `nohup python3 -c` and `stdbuf -o L python3 -c` are wrapped pythons: the inline
# script check must look past both wrappers, called by name or by path, and
# stdbuf's separate mode word after a short or a shortened long option
# (`--out L`), or a source write in the script passes the in-place write guard.
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
HOOK=$ROOT/.claude/hooks/bash-guardrails.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/said.sh" # a FAIL line names the hook's last input

FAILED=0
W="python3 -c \"open('src/a.ts','w')\""
for CMD in "nohup $W" "stdbuf -o L $W" "/usr/bin/nohup $W" "/usr/bin/stdbuf --out L $W"; do
  RC=0
  jq -cn --arg cmd "$CMD" --arg cwd "$ROOT" \
    '{session_id:"nohup-stdbuf-refute",cwd:$cwd,tool_input:{command:$cmd}}' \
    | bash "$HOOK" >/dev/null 2>&1 || RC=$?
  [ "$RC" -eq 2 ] || { echo "FAIL: wrapped Python source write passed with $RC for: $CMD$(said)" >&2; FAILED=1; }
done
[ "$FAILED" = 0 ] || exit 1
echo "PASS"
