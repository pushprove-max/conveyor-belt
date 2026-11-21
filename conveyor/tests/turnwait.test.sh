#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# Engine cases: the wait that ends each turn of the loop (turnwait(), lib/run.sh).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bug (issue 881): a job beside the cards (relfixes(), started every IDLE seconds) that ended during the turn ended
# the turn's wait at once, so the loop ran turn after turn with no wait, and the machine cases' turn count (the
# timer's sleep) never moved. The wait goes on to the timer past such a job, and still ends at once on a card that
# has already ended.
t_turnwait() {
  eval "$(sed -n '/^turnwait() {/,/^}/p' "$SRC/lib/run.sh")"
  declare -f turnwait >/dev/null || fail "no turnwait() in lib/run.sh"
  local -A mine=()
  local timer pusher prober s w side
  # Stand-ins for the loop's jobs: a card still building, a push still running, a job beside the cards that ends at
  # once, a machine hold's look that ended at an earlier turn (prober is never cleared), the timer.
  sleep 30 & mine[$!]='c1-1 1' # sleep: a card that still builds
  sleep 30 & pusher=$! # sleep: a push that still runs
  ( exit 0 ) & side=$!
  ( exit 0 ) & prober=$!
  sleep 0.2 # sleep: the other jobs have ended before the wait starts, as relfixes() had
  sleep 1 & timer=$!; s=$EPOCHREALTIME # sleep: the turn's timer
  turnwait; w=$(( (${EPOCHREALTIME/[.,]/} - ${s/[.,]/}) / 1000 ))
  kill "$timer" "$pusher" "${!mine[@]}" 2>/dev/null; wait "$timer" "$pusher" "${!mine[@]}" "$side" "$prober" 2>/dev/null
  pusher=''
  [ "$w" -ge 900 ] || fail "the turn's wait ended after ${w} ms, on a job beside the cards that had ended, not on its 1 s timer"
  # A card that ended before the wait: the wait ends at once, so the turn that follows counts it as gone.
  mine=(); ( exit 3 ) & mine[$!]='c2-2 2'
  sleep 0.2 # sleep: the card has ended before the wait starts
  sleep 5 & timer=$!; s=$EPOCHREALTIME # sleep: the turn's timer, which must not be waited out
  turnwait; w=$(( (${EPOCHREALTIME/[.,]/} - ${s/[.,]/}) / 1000 ))
  kill "$timer" 2>/dev/null; wait "$timer" "${!mine[@]}" 2>/dev/null
  lim=$(loadlimit 2000 5000) # under the timer's 5 s
  [ "$w" -lt "$lim" ] || fail "the turn's wait did not end at once on a card that had ended (${w} ms; limit $lim ms: 2000 ms times the load factor $CASE_LOAD)"
}
