#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The Foreman's Conveyor watcher, watch-conveyor.sh, stopped mid-poll during an outage, as a waiter's stop_groups stops
# it at an ordinary Stop (TERM to its process group): one poll (--once) of four records whose reads fail, given by
# CONVEYOR_FOREMAN_ASK, the clock set by CONVEYOR_FOREMAN_NOW.
# Four records: alpha, in an outage already reported, whose reads fail after 2 s each; beta, in an outage too, whose
# first snapshot read and health fail and whose longer read hangs; gamma, in an outage, read after beta; delta, read
# after beta, whose last failed poll was over three polls before the poll began. The watcher's process group gets TERM
# during beta's longer read.
# Bug caught: alpha's failed poll stayed timed at the poll's start, as the stopped poll never reached downend, so the
# next watcher's poll began a new outage and woke the Foreman on it again.
# Bug caught: beta's failed poll was saved only after its longer read, so a stop during that read (or after it, before
# the save) left the previous poll's time in its file, and the next watcher's poll began a new outage.
# Bug caught: gamma, whose read the stop came before, kept the time of its previous poll, which slow reads of the
# records before it can make over 3 minutes old, so the next watcher's poll began a new outage. A record whose first
# read is under way at the stop has the same file, untouched yet, and is timed by the same code.
# Bug caught: delta, whose outage was over when the poll began, had its last failed poll moved to the stop too, so the
# next failed read of it kept the old outage and its reported unreachable key, and its new outage never woke.
# The watcher runs as a real process in its own group and is waited for: only a signal to a running poll can show
# what the stop leaves in the outage files.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
unset CONVEYOR_FOREMAN CONVEYOR_FOREMAN_LAUNCH CONVEYOR_MAIN CLAUDE_PROJECT_DIR
fail() { echo "FAIL [watch-conveyor-outage]: $*" >&2; exit 1; }
. "$SRC/../lib/portable.sh"; . "$SRC/../tests/wait.sh"
NOW=$(jq -n '"2026-11-15T12:00:00Z" | fromdate') M=$T/alpha
export XDG_CONFIG_HOME=$T/config XDG_DATA_HOME=$T/data HOME=$T/home CONVEYOR_FOREMAN_DIR=$T/state/foreman CONVEYOR_FOREMAN_NOW=$NOW
FD=$CONVEYOR_FOREMAN_DIR
mkdir -p "$XDG_CONFIG_HOME/conveyor" "$HOME" "$FD" || fail "the fixture was not made"
for r in alpha beta gamma delta; do git init -q "$T/$r" && mkdir -p "$T/$r/.conveyor" && echo '{}' > "$T/$r/.conveyor/project.json" || fail "the fixture was not made"; done
jq -n --arg s "$T/state" --arg a "$M" --arg b "$T/beta" --arg g "$T/gamma" --arg d "$T/delta" '{stateDir: $s,
  records: [{repo: "alpha", main: $a}, {repo: "beta", main: $b}, {repo: "gamma", main: $g}, {repo: "delta", main: $d}],
  foreman: {groups: [["alpha", "beta", "gamma", "delta"]]}}' > "$XDG_CONFIG_HOME/conveyor/host.json" || fail "the fixture was not made"
export CONVEYOR_FOREMAN_ASK="case \$CONVEYOR_REPO:\$CONVEYOR_CMD:\$ASK_LIMIT in *:health:*) exit 1 ;; beta:*:45) exit 1 ;;
  beta:*) touch $T/inbeta; sleep 8 ;; alpha:*) sleep 2; echo 'conveyor: no snapshot' >&2; exit 1 ;; *) exit 3 ;; esac" # sleep: alpha's slow failed reads, and beta's longer read the stop comes in
echo "$((NOW - 600)) $((NOW - 60)) 3" > "$FD/conveyor-down-alpha.txt"; printf '%s\n' alpha/unreachable delta/unreachable > "$FD/conveyor-reported.txt"
echo "$((NOW - 300)) $((NOW - 60)) 2" > "$FD/conveyor-down-beta.txt"
echo "$((NOW - 400)) $((NOW - 60)) 2" > "$FD/conveyor-down-gamma.txt"
echo "$((NOW - 900)) $((NOW - 181)) 5" > "$FD/conveyor-down-delta.txt" # 181 s: one second past three polls (POLL 60)
(CONVEYOR_MAIN=$M p_execsid bash "$SRC/watch-conveyor.sh" --once 2>"$T/err" >/dev/null) & w=$!
wait_until '[ -e "$T/inbeta" ]' 'cat "$T/err"' || fail "the watcher never made beta's longer read: $(cat "$T/err")"
# The TERM reaches a poll that is still running: kill finds the group, the watcher ends on it, and no poll log line is
# written, as a poll that ends on its own writes one after its downend.
kill -TERM -- "-$w" || fail "the watcher's process group $w was gone before the TERM: $(cat "$T/err")"
rc=0; wait "$w" || rc=$?
[ "$rc" = 143 ] && [ ! -s "$FD/conveyor-polls.log" ] \
  || fail "the watcher did not end on the TERM during beta's read (exit $rc, poll log: $(cat "$FD/conveyor-polls.log" 2>/dev/null)): $(cat "$T/err")"
read -r first last fails < "$FD/conveyor-down-alpha.txt"
[ "$first" = $((NOW - 600)) ] && [ "$fails" = 4 ] && [ "$last" -ge $((NOW + 4)) ] \
  || fail "after TERM to the watcher during beta's read, alpha's outage file (first, last failed poll, fails) is not $((NOW - 600)) $((NOW + 4)) or later, 4: $(cat "$FD/conveyor-down-alpha.txt")"
read -r first last fails < "$FD/conveyor-down-beta.txt"
[ "$first" = $((NOW - 300)) ] && [ "$fails" = 3 ] && [ "$last" -ge $((NOW + 4)) ] \
  || fail "after TERM to the watcher during beta's longer read (its first read and health failed), beta's outage file is not $((NOW - 300)) $((NOW + 4)) or later, 3: $(cat "$FD/conveyor-down-beta.txt")"
# Gamma was not read: its count stays, as no read of it failed, and only its time moves to the stop.
read -r first last fails < "$FD/conveyor-down-gamma.txt"
[ "$first" = $((NOW - 400)) ] && [ "$fails" = 2 ] && [ "$last" -ge $((NOW + 4)) ] \
  || fail "after TERM to the watcher during beta's longer read, before gamma's read, gamma's outage file is not $((NOW - 400)) $((NOW + 4)) or later, 2: $(cat "$FD/conveyor-down-gamma.txt")"
# Delta was not read, and its outage was over before the poll began: its file stays as it was.
[ "$(cat "$FD/conveyor-down-delta.txt")" = "$((NOW - 900)) $((NOW - 181)) 5" ] \
  || fail "after TERM to the watcher during beta's longer read, before the read of delta (last failed poll 181 s before the poll), delta's outage file is not $((NOW - 900)) $((NOW - 181)) 5 as it was: $(cat "$FD/conveyor-down-delta.txt")"
echo "ok [watch-conveyor-outage]"
