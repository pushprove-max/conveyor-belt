#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
FAIL=0
for COMMAND in \
  'git -C "." clean -fdx' \
  'git -c "core.pager=cat" clean -fdx'
do
  RC=0
  jq -nc --arg command "$COMMAND" \
    '{tool_input:{command:$command}}' |
    CONVEYOR_HOOK_FIRE_LOG=/dev/null \
      bash "$ROOT/.claude/hooks/git-safety.sh" >/dev/null 2>&1 ||
    RC=$?
  if [ "$RC" -ne 2 ]; then
    echo "FAIL: $COMMAND expected 2, got $RC"
    FAIL=$((FAIL + 1))
  fi
done
[ "$FAIL" -eq 0 ]
