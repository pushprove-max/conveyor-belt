#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The Foreman's usage-limit watcher, watch-limit.sh: one poll (--once) of a reading given by
# CONVEYOR_FOREMAN_LIMIT_CMD, the clock set by CONVEYOR_FOREMAN_NOW.
# Bug: a reading with no resets_at was seen as limit-<threshold>-unknown for ever, so no later window ever woke the
# Foreman; such a reading now wakes once a UTC day.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
fails=0
FD=$T/foreman DAY=1794744000 # 2026-11-15T12:00:00Z
mkdir -p "$T/user"
poll() { # <epoch>: one poll then; 0 with a wake put in pending
  rm -f "$FD"/pending/*.wake
  HOME=$T/user XDG_CONFIG_HOME=$T/user/.config CONVEYOR_MAIN=$T CONVEYOR_FOREMAN_DIR=$FD CONVEYOR_FOREMAN_NOW=$1 \
    CONVEYOR_FOREMAN_LIMIT_CMD='echo "{\"seven_day\": {\"utilization\": 95}}"' bash "$SRC/watch-limit.sh" --once \
    && grep -qF '7-day usage limit at 95% (threshold 90%; resets unknown)' "$FD"/pending/*.wake
}
check() { if "${@:2}"; then echo "ok [watch-limit]: $1"; else echo "FAIL [watch-limit]: $1" >&2; fails=$((fails + 1)); fi; }
nope() { ! "$@"; }

check 'a reading with no reset time wakes' poll "$DAY"
check 'the same reading the same day does not wake again' nope poll $((DAY + 3600))
check 'the same reading a day later wakes again' poll $((DAY + 86400))

[ "$fails" = 0 ]
