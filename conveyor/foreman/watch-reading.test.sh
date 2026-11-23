#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The Foreman's Conveyor watcher, watch-conveyor.sh, after a stop cut its snapshot read short: one poll (--once) of a
# record given by CONVEYOR_FOREMAN_ASK, the clock set by CONVEYOR_FOREMAN_NOW.
# Bug caught (R209): each Stop takes over the waiter and stops its watchers, so the next watcher began a slow snapshot
# read from zero (up to 45 s) and read health only after it failed: a Stop 30 s into a read made the wake of a blocked
# card 30 s later, and Stops every 45 s never reached health. A read leaves conveyor-reading-<repo>.txt while it runs;
# a poll that finds it reads health first and wakes on what health lists, with no snapshot read.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
unset CONVEYOR_FOREMAN CONVEYOR_FOREMAN_LAUNCH CONVEYOR_MAIN CLAUDE_PROJECT_DIR
fail() { echo "FAIL [watch-reading]: $*" >&2; exit 1; }
. "$SRC/../lib/portable.sh"; . "$SRC/../tests/wait.sh"
NOW=$(jq -n '"2026-11-15T12:00:00Z" | fromdate') M=$T/alpha
export XDG_CONFIG_HOME=$T/config XDG_DATA_HOME=$T/data HOME=$T/home CONVEYOR_FOREMAN_DIR=$T/state/foreman CONVEYOR_FOREMAN_NOW=$NOW
FD=$CONVEYOR_FOREMAN_DIR
mkdir -p "$XDG_CONFIG_HOME/conveyor" "$HOME" "$FD" && git init -q "$M" && mkdir -p "$M/.conveyor" && echo '{}' > "$M/.conveyor/project.json" \
  && jq -n --arg s "$T/state" --arg m "$M" '{stateDir: $s, records: [{repo: "alpha", main: $m}]}' > "$XDG_CONFIG_HOME/conveyor/host.json" \
  && jq -n '{time: "2026-11-15T12:00:00Z", loop: true, gh: true, stuck: [], waiting: [], pushFailingSince: null, before: [],
    blocked: [{card: "c8", issue: 8, since: "2026-11-15T11:59:00Z", reason: "tests failed twice"}]}' > "$T/health" \
  || fail "the fixture was not made"

# A stop during the read leaves the marker. The watcher runs as a real process in its own group, stopped with TERM to
# that group as the waiter's stop_groups does: only a signal to a running read can show what the stop leaves.
ask="case \$CONVEYOR_CMD in snapshot) touch $T/inread; sleep 8 ;; *) exit 1 ;; esac" # sleep: the slow read the stop comes in
CONVEYOR_FOREMAN_ASK=$ask CONVEYOR_MAIN=$M p_execsid bash "$SRC/watch-conveyor.sh" --once 2>"$T/err" >/dev/null & w=$!
wait_until '[ -e "$T/inread" ]' 'cat "$T/err"' || fail "the watcher never began its snapshot read: $(cat "$T/err")"
kill -TERM -- "-$w" || fail "the watcher's process group $w was gone before the TERM"
wait "$w" 2>/dev/null
[ -e "$FD/conveyor-reading-alpha.txt" ] || fail "a TERM during the snapshot read left no conveyor-reading-alpha.txt: $(ls "$FD")"

# The next watcher's poll reads health first and wakes on #8 at once; the snapshot is not asked (each ask is logged).
CONVEYOR_FOREMAN_ASK="echo \$CONVEYOR_CMD >> $T/asks; case \$CONVEYOR_CMD in health) cat $T/health ;; *) exit 1 ;; esac" \
  CONVEYOR_MAIN=$M bash "$SRC/watch-conveyor.sh" --once 2>>"$T/err" >/dev/null || fail "the poll after the stop put no wake (asks: $(cat "$T/asks" 2>/dev/null)): $(cat "$T/err")"
grep -qF '#8 is blocked since 2026-11-15T11:59:00Z: tests failed twice' "$FD"/pending/*.wake \
  || fail "the poll after the stop did not wake on #8 from health: $(cat "$FD"/pending/*.wake)"
[ "$(cat "$T/asks")" = health ] || fail "the poll after a stop cut its snapshot read short asked $(paste -sd, "$T/asks"), not health alone"

# Bug caught: when the first health read listed nothing new and the snapshot read then failed, the poll reused that
# first health read, so a card that blocked during the snapshot read waited a poll for its wake. Health is read again.
# The marker as a stop leaves it (shown above); health lists only #8 (reported) at the first ask and #9 too after it.
touch "$FD/conveyor-reading-alpha.txt" && jq '.blocked += [{card: "c9", issue: 9, since: "2026-11-15T11:59:30Z", reason: "review said NO-GO twice"}]' "$T/health" > "$T/health2" \
  && rm -f "$T/asks" "$FD"/pending/*.wake || fail "the second fixture was not made"
CONVEYOR_FOREMAN_ASK="echo \$CONVEYOR_CMD >> $T/asks; case \$CONVEYOR_CMD in health) if [ \"\$(grep -c health $T/asks)\" = 1 ]; then cat $T/health; else cat $T/health2; fi ;; *) exit 1 ;; esac" \
  CONVEYOR_MAIN=$M bash "$SRC/watch-conveyor.sh" --once 2>>"$T/err" >/dev/null || fail "a card blocked during the failed snapshot read put no wake (asks: $(paste -sd, "$T/asks")): $(cat "$T/err")"
grep -qF '#9 is blocked since 2026-11-15T11:59:30Z' "$FD"/pending/*.wake \
  || fail "the poll did not wake on #9, blocked during its failed snapshot read (asks: $(paste -sd, "$T/asks")): $(cat "$FD"/pending/*.wake)"
echo "ok [watch-reading]"
