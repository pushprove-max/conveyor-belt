#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# Engine cases: the wait that ends each turn of the loop (turnwait(), lib/run.sh), and the end of a `run` (runends()).
# t_runreaps calls serveeng() and nojobs(), defined in serve.test.sh: the runner sources every area file.
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

# Bug (issue 1260): bash's `wait -n` passes over a pid that is no child of the shell, or one the shell has already
# forgotten, so a card that had ended in that way did not end the turn's wait: it went on to the timer (5 s). An adopted
# card (started by an earlier loop) is such a pid; the wait must end at once on it, as on a card of this shell's.
t_turnwaitadopted() {
  eval "$(sed -n '/^turnwait() {/,/^}/p' "$SRC/lib/run.sh")"
  declare -f turnwait >/dev/null || fail "no turnwait() in lib/run.sh"
  local -A mine=()
  local timer pusher='' prober='' s w lim pid
  pid=$( (sleep 0.1 & echo $!) ) # sleep: a card of another shell, which ends at once
  mine[$pid]='c3-3 3'
  sleep 0.5 # sleep: the card has ended before the wait starts
  sleep 5 & timer=$!; s=$EPOCHREALTIME # sleep: the turn's timer, which must not be waited out
  turnwait; w=$(( (${EPOCHREALTIME/[.,]/} - ${s/[.,]/}) / 1000 ))
  kill "$timer" 2>/dev/null; wait "$timer" 2>/dev/null
  lim=$(loadlimit 2000 5000) # under the timer's 5 s
  [ "$w" -lt "$lim" ] || fail "the turn's wait did not end at once on an adopted card that had ended (${w} ms; limit $lim ms: 2000 ms times the load factor $CASE_LOAD)"
}

# Bug (1.12.0 release, serve): a `run` counted its cards running (cardsrun()) after its turn's turnended() had looked at
# them, so a card whose job ended between the two was in no count and was not ended: the run ended with the card still
# in mine, its <card>.exit left in the cards folder, and any process of it left holding the run lock. Here run() picks
# #7, and its card() stand-in waits until turnside(), which run() calls between turnended() and its count, lets it
# close and waits for its job to end. The run must end that card before it ends: no <card>.exit is left.
t_runreaps() {
  local c
  setup "[$(issue 7 2026-01-01)]"; tune '.tunables += {idle: 1, poll: 1}'
  # run() itself, not runends() alone: the weak point lies between two steps of its turn, in the order only run() calls them.
  serveeng "$SRC" 'nojobs
    card() { wait_until "[ -e \"\$STUB/go\" ]"; record "$1" "$2" closed ok; }
    turnside() { local p; for p in "${!mine[@]}"; do : > "$STUB/go"; wait "$p"; done; }
    run 1' > "$STUB/run.out" 2>&1
  c=$(st 'select(.issue == 7 and .step == "picked") | .card')
  [ -n "$c" ] && [ -e "$STUB/go" ] || fail "run 1 did not pick #7 and start its card: $(cat "$STUB/run.out")"
  [ ! -e "$T/$CASE/cards/$c.exit" ] \
    || fail "run 1 ended with card $c not ended by the loop (its job ended between turnended() and the count): $c.exit is left; $(cat "$STUB/run.out")"
}
