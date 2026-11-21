#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -eu
HOOK="$(cd "$(dirname "$0")/.." && pwd)/bash-guardrails.sh"
BOX=$(mktemp -d)
trap 'rm -rf "$BOX"' EXIT
git -C "$BOX" init -q
. "$(dirname "${BASH_SOURCE[0]}")/lib/said.sh" # a FAIL line names the hook's last input (said_tee notes it)

CMD='WT=/tmp/orca/workspaces/sample-project/unit-$U; env DEBUG=1 orca-ide worktree create --path "$WT"'
PAYLOAD=$(jq -cn --arg cmd "$CMD" '{tool_input:{command:$cmd}}')
rc=0
(cd "$BOX" && printf '%s\n' "$PAYLOAD" | said_tee | CONVEYOR_REVIEWER=0 "$HOOK" >/dev/null 2>&1) || rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: sanctioned alias use blocked: rc=$rc$(said)"; exit 1; }
