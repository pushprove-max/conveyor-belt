#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The Foreman's Conveyor watcher, watch-conveyor.sh, stopped on the first failed poll of a new outage, as a waiter's
# stop_groups stops it at an ordinary Stop (TERM to its process group), then polled (--once) with every read failing
# until the new outage wakes (twice more in health, three times more in snapshot), the clock set by CONVEYOR_FOREMAN_NOW and the reads given by CONVEYOR_FOREMAN_ASK.
# One record, alpha, whose last outage ended 10 minutes ago and was reported (alpha/unreachable in the reported file).
# One fixture per point the stop comes at, run side by side:
# - health: the first failed read saved the new outage before health, but the old unreachable key was dropped only
#   at the poll's end; the stop during health left it, the next failed polls took the outage as going on and kept the
#   key reported, and the new outage never woke the Foreman.
# - snapshot: the stop comes in the first read, before the new outage is saved (as one that comes while that key is
#   dropped); the stop handler timed the last outage's file now, so it went on with its key, and nothing woke. That
#   poll failed no read, so the outage starts at the next poll and wakes a poll later than in health.
# The first watcher runs as a real process in its own group and is waited for: only a signal to a running poll can
# show what the stop leaves behind.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
unset CONVEYOR_FOREMAN CONVEYOR_FOREMAN_LAUNCH CONVEYOR_MAIN CLAUDE_PROJECT_DIR
. "$SRC/../lib/portable.sh"; . "$SRC/../tests/wait.sh"
NOW=$(jq -n '"2026-11-15T12:00:00Z" | fromdate')
stage() ( # <the read the stop comes in: snapshot or health> <seconds after NOW the outage wakes>
  local at=$1 wakes=$2 D=$T/$1 rc
  # The case is newoutage-<read>, one word: the main-red proof reads a pass only from `ok <case>`, with no space in it.
  fail() { echo "FAIL [newoutage-$at]: $*" >&2; exit 1; }
  local M=$D/alpha
  export XDG_CONFIG_HOME=$D/config XDG_DATA_HOME=$D/data HOME=$D/home CONVEYOR_FOREMAN_DIR=$D/state/foreman CONVEYOR_FOREMAN_NOW=$NOW
  local FD=$CONVEYOR_FOREMAN_DIR
  mkdir -p "$XDG_CONFIG_HOME/conveyor" "$HOME" "$FD" || fail "the fixture was not made"
  git init -q "$M" && mkdir -p "$M/.conveyor" && echo '{}' > "$M/.conveyor/project.json" || fail "the fixture was not made"
  jq -n --arg s "$D/state" --arg a "$M" '{stateDir: $s, records: [{repo: "alpha", main: $a}], foreman: {groups: [["alpha"]]}}' \
    > "$XDG_CONFIG_HOME/conveyor/host.json" || fail "the fixture was not made"
  # The first poll's read $at hangs, so the stop comes during it; once $D/fast is there, every read fails at once.
  export CONVEYOR_FOREMAN_ASK="[ -e $D/fast ] || [ \"\$CONVEYOR_CMD\" != $at ] || { touch $D/inread; sleep 8; }; exit 1" # sleep: the read the stop comes in
  echo "$((NOW - 900)) $((NOW - 600)) 5" > "$FD/conveyor-down-alpha.txt"; echo alpha/unreachable > "$FD/conveyor-reported.txt"
  (CONVEYOR_MAIN=$M p_execsid bash "$SRC/watch-conveyor.sh" --once 2>"$D/err" >/dev/null) & w=$!
  wait_until '[ -e "$D/inread" ]' 'cat "$D/err"' || fail "the watcher never read alpha's $at: $(cat "$D/err")"
  kill -TERM -- "-$w" || fail "the watcher's process group $w was gone before the TERM: $(cat "$D/err")"
  rc=0; wait "$w" || rc=$?
  [ "$rc" = 143 ] || fail "the watcher did not end on the TERM during alpha's $at read (exit $rc): $(cat "$D/err")"
  touch "$D/fast"
  # Each later failed poll wakes on nothing until the third failed poll of the outage, two minutes into it, at
  # NOW+$wakes: it reads unreachable and wakes.
  local t
  for ((t = 60; t < wakes; t += 60)); do
    rc=0; CONVEYOR_FOREMAN_NOW=$((NOW + t)) CONVEYOR_MAIN=$M bash "$SRC/watch-conveyor.sh" --once 2>>"$D/err" >/dev/null || rc=$?
    [ "$rc" = 1 ] || fail "the failed poll of alpha's new outage at NOW+$t did not end with nothing new (exit $rc): $(cat "$D/err")"
  done
  rc=0; CONVEYOR_FOREMAN_NOW=$((NOW + wakes)) CONVEYOR_MAIN=$M bash "$SRC/watch-conveyor.sh" --once 2>>"$D/err" >/dev/null || rc=$?
  [ "$rc" = 0 ] && grep -qxF alpha/unreachable "$FD/conveyor-reported.txt" \
    || fail "the third failed poll of alpha's new outage (at NOW+$wakes, after a TERM during the first poll's $at read, the last outage ended at NOW-600 and reported) did not wake on it as unreachable (exit $rc, outage file: $(cat "$FD/conveyor-down-alpha.txt"), reported: $(cat "$FD/conveyor-reported.txt")): $(cat "$D/err")"
)
stage snapshot 180 & s=$!
stage health 120 & h=$!
ok=1
if wait "$s"; then echo "ok newoutage-snapshot"; else ok=''; fi
if wait "$h"; then echo "ok newoutage-health"; else ok=''; fi
[ -n "$ok" ] || exit 1
