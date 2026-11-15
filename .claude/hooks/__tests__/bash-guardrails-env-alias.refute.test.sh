#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
set -eu
HOOK="$(cd "$(dirname "$0")/.." && pwd)/bash-guardrails.sh"
BOX=$(mktemp -d)
trap 'rm -rf "$BOX"' EXIT
git -C "$BOX" init -q

CMD='WT=/tmp/orca/workspaces/sample-project/unit-$U; env DEBUG=1 orca-ide worktree create --path "$WT"'
PAYLOAD=$(jq -cn --arg cmd "$CMD" '{tool_input:{command:$cmd}}')
rc=0
(cd "$BOX" && printf '%s\n' "$PAYLOAD" | CONVEYOR_REVIEWER=0 "$HOOK" >/dev/null 2>&1) || rc=$?
[ "$rc" -eq 0 ] || { echo "sanctioned alias use blocked: rc=$rc"; exit 1; }
