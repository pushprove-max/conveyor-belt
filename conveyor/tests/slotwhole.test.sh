#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the whole-suite runs' turns of the machine's test slots (lib/slots.sh slot_whole).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner. slotpool is slots.test.sh's. A change to either file's helpers or setup runs the other
# and the files that call their helpers, through their links in .conveyor/test-links.json.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# A stand-in for a whole-suite runner, <name>: it asks for its turn (slot_whole), says it has it (<name>.on), and keeps
# it until told to end (<name>.go). Once it has its turn, a run inside it asks too and must not wait (<name>.inner):
# it would wait behind its own run. What slot_whole says goes to <name>.err.
wholerun() { # <name>
  ( slot_pool && slot_whole 2> "$d/$1.err" || exit 1; : > "$d/$1.on"
    ( slot_pool && slot_whole 2>> "$d/$1.err" ) && : > "$d/$1.inner"
    wait_until "[ -e '$d/$1.go' ]" ) &
}

# The owner (2026-11-13): a whole-suite run took half the pool, and with three other cards testing beside it a run
# took three times as long. Two whole-suite runs hold their turns of a pool of 3; a third (the engine's own runner, run
# whole) gets a slot but starts no case until one of the two ends, and then does, saying how long it waited as slot
# wait. A runner that took a turn per case instead of per run, or none, started its cases beside the two.
t_slotwhole() {
  local d=$T/$CASE r
  slotpool 3; mkdir -p "$d/log"; unset CONVEYOR_TEST_WHOLE CONVEYOR_TEST_TURNWAIT
  wholerun A; wholerun B
  wait_until "[ -e '$d/A.on' ] && [ -e '$d/B.on' ]" "cat '$d/A.err' '$d/B.err'" || fail "two whole-suite runs did not both get a turn"
  wait_until "[ -e '$d/A.inner' ] && [ -e '$d/B.inner' ]" || fail "a run inside a run that holds a turn waited for a turn of its own"
  CONVEYOR_TEST_LOG=$d/log bash "$SRC/conveyor.test.sh" > "$d/run.out" 2>&1 & r=$!
  wait_until "grep -q 'this one waits for its turn' '$d/run.out'" "cat '$d/run.out'" \
    || { kill $r; fail "a third whole-suite run did not wait for its turn while two held theirs"; }
  [ ! -e "$d/log/cases" ] || { kill $r; fail "a third whole-suite run started a case while two held their turns: $(ls "$d/log/cases")"; }
  : > "$d/A.go"
  wait_until "ls '$d/log/cases' 2>/dev/null | grep -q ." "cat '$d/run.out'" || { kill $r; fail "the waiting whole-suite run started no case once a turn was free"; }
  kill -TERM $r; wait $r; : > "$d/B.go"; wait
  grep -q '^conveyor: slot wait: [0-9]* s for a whole-suite turn$' "$d/run.out" || fail "the wait for a turn was not said as slot wait: $(head -5 "$d/run.out")"
}

# Turns go in the order runs asked, or a run could be passed over again and again. With two runs holding the turns of a
# pool of 4, C asks and then D, each with a slot: the first turn freed is C's, and D's comes only with the next.
t_slotwholeorder() { wholeorder 4; }
# The same with the pool full (2 slots, the two runs holding the turns): C and D have no slot as they ask. A run that
# took its slot before its place in the order let D, given A's freed slot first, take the turn ahead of C.
t_slotwholequeue() { wholeorder 2; }
wholeorder() { # <pool size>
  local d=$T/$CASE
  slotpool "$1"; mkdir -p "$d"; unset CONVEYOR_TEST_WHOLE CONVEYOR_TEST_TURNWAIT
  wholerun A; wholerun B
  wait_until "[ -e '$d/A.on' ] && [ -e '$d/B.on' ]" || fail "two whole-suite runs did not both get a turn"
  wholerun C; wait_until "grep -q 'waits for its turn' '$d/C.err'" || fail "a third whole-suite run did not wait"
  wholerun D; wait_until "grep -q 'waits for its turn' '$d/D.err'" || fail "a fourth whole-suite run did not wait"
  : > "$d/A.go"
  wait_until "[ -e '$d/C.on' ] || [ -e '$d/D.on' ]" || fail "no waiting run got the turn A gave up"
  [ -e "$d/C.on" ] && [ ! -e "$d/D.on" ] || fail "the turn went to the run that asked second, not first"
  : > "$d/B.go"
  wait_until "[ -e '$d/D.on' ]" || fail "the run that asked second did not get the next turn"
  : > "$d/C.go"; : > "$d/D.go"; wait
}

# A stand-in for a card's test step, <name>: it takes a slot of the pool (<name>.slot) and, once told (<name>.ask), its
# runner, given that slot as its home slot, asks for its turn as wholerun does, writing the seconds it has waited to
# <name>.wait on each look, as a card's runner does. The slot outlives the runner until told (<name>.free), as a
# card's step holds its slot around its runner.
cardrun() { # <name>
  ( slot_pool && eval "$(wait_fn)" && wait_poll slot_try; : > "$d/$1.slot"
    wait_until "[ -e '$d/$1.ask' ]" || exit 1
    ( export CONVEYOR_TEST_SLOT=$SLOT_FD CONVEYOR_TEST_TURNWAIT=$d/$1.wait; slot_pool && [ -n "$SLOT_HOME" ] && slot_whole 2> "$d/$1.err" || exit 1; : > "$d/$1.on"
      wait_until "[ -e '$d/$1.go' ]" ); : > "$d/$1.ran"
    wait_until "[ -e '$d/$1.free' ]" ) &
}

# A card's step has its slot before its runner asks for a turn: it must still wait behind a run that asked before it
# with no slot yet, or later cards could pass a session's run again and again. Pool of 3: card A and run B hold the
# turns, card D holds the last slot; C asks with no slot, then D asks. A's runner ends (its card still holds the slot):
# a turn is free but no slot is, and D, who has one, once took the turn ahead of C. When A's slot comes free, C takes
# it and the turn; D's turn comes only when B ends.
t_slotwholecard() {
  local d=$T/$CASE
  slotpool 3; mkdir -p "$d"; unset CONVEYOR_TEST_WHOLE CONVEYOR_TEST_TURNWAIT
  cardrun A; : > "$d/A.ask"; wait_until "[ -e '$d/A.on' ]" "cat '$d/A.err'" || fail "a card's whole-suite run did not get a turn"
  wholerun B; wait_until "[ -e '$d/B.on' ]" || fail "a second whole-suite run did not get a turn"
  cardrun D; wait_until "[ -e '$d/D.slot' ]" || fail "a card did not get the last slot"
  wholerun C; wait_until "grep -q 'waits for its turn' '$d/C.err'" || fail "a run with no slot did not wait"
  : > "$d/D.ask"; wait_until "grep -q 'waits for its turn' '$d/D.err'" || fail "a card's run that asked after one with no slot did not wait"
  : > "$d/A.go"
  # A asked first: its ticket is 1. Once it is gone, D has looked again when it has written its wait twice more.
  wait_until "[ ! -e '$d/slots/whole/1' ]" || fail "the turn of a run that ended was not given up"
  : > "$d/m1"; wait_until "[ '$d/D.wait' -nt '$d/m1' ]" || fail "the waiting card's run did not look again"
  : > "$d/m2"; wait_until "[ '$d/D.wait' -nt '$d/m2' ] || [ -e '$d/D.on' ]" || fail "the waiting card's run did not look again"
  [ ! -e "$d/D.on" ] || fail "a card's run that asked after a run with no slot yet took the turn ahead of it"
  : > "$d/A.free"
  wait_until "[ -e '$d/C.on' ]" "cat '$d/C.err'" || fail "the run that asked first got no turn once a slot came free"
  [ ! -e "$d/D.on" ] || fail "the card's run that asked second got a turn beside the one that asked first"
  : > "$d/B.go"
  wait_until "[ -e '$d/D.on' ]" || fail "the card's run that asked second did not get the next turn"
  : > "$d/C.go"; : > "$d/D.go"; : > "$d/D.free"; wait
}

# When every slot is held by a run waiting with one, an earlier run with no slot cannot get one unless a later run gives
# its slot up; letting the later run go ahead (as once) put a card ahead of a session that asked first. Pool of 1:
# card D holds it; C asks with no slot, then D asks. D's run gives the slot up, C takes it and its turn, and D's turn
# comes only when C ends, though D's step still runs. A run that kept its slot left C waiting, or deadlocked. D's runner
# takes back the slot its step holds: once the runner has ended, the step, still running, holds it. A runner that took
# the slot back on a descriptor of its own let it go as it ended, and the step's next test files ran on no slot.
t_slotwholefull() {
  local d=$T/$CASE
  slotpool 1; mkdir -p "$d"; unset CONVEYOR_TEST_WHOLE CONVEYOR_TEST_TURNWAIT
  cardrun D; wait_until "[ -e '$d/D.slot' ]" || fail "a card did not get the pool's slot"
  wholerun C; wait_until "grep -q 'waits for its turn' '$d/C.err'" || fail "a run with no slot did not wait"
  : > "$d/D.ask"
  wait_until "[ -e '$d/C.on' ]" "cat '$d/C.err' '$d/D.err'" \
    || { : > "$d/D.go"; : > "$d/D.free"; : > "$d/C.go"; wait; fail "with every slot held by a run waiting with one, the run that asked first with no slot got no turn"; }
  [ ! -e "$d/D.on" ] || { : > "$d/D.go"; : > "$d/D.free"; : > "$d/C.go"; wait; fail "a card's run that asked second took a turn ahead of or beside the run that asked first"; }
  : > "$d/C.go"
  wait_until "[ -e '$d/D.on' ]" "cat '$d/D.err'" || { : > "$d/D.go"; : > "$d/D.free"; wait; fail "the card's run that gave its slot up got no turn once the first run ended"; }
  : > "$d/D.go"; wait_until "[ -e '$d/D.ran' ]" || { : > "$d/D.free"; wait; fail "the card's runner did not end"; }
  flock -n "$d/slots/1" true && : > "$d/D.lost"
  : > "$d/D.free"; wait
  [ ! -e "$d/D.lost" ] || fail "once its runner that gave the slot up and took it back had ended, the card's step, still running, held no slot"
}

# A run that gave slot k up waits to take k back, and only k: its step is pinned to k's core. A card's step can take k
# first, as k comes free, and ask after it: it must give k up to the run that asked first, or each waits for the other
# for good. Pool of 2: card E holds slot 1, card P holds slot 2 and never asks; ticket 1 is a run that gave slot 1 up
# (w1). E asks: it gives slot 1 up and waits for it, its turn coming only once slot 1 is its again.
t_slotwholeyield() {
  local d=$T/$CASE w
  slotpool 2; mkdir -p "$d/slots/whole"; unset CONVEYOR_TEST_WHOLE CONVEYOR_TEST_TURNWAIT
  cardrun E; wait_until "[ -e '$d/E.slot' ]" || fail "a card did not get a slot"
  ( slot_pool && eval "$(wait_fn)" && wait_poll slot_try; : > "$d/P.slot"; wait_until "[ -e '$d/P.free' ]" ) &
  wait_until "[ -e '$d/P.slot' ]" || { : > "$d/E.free"; wait; fail "a second card did not get a slot"; }
  ( exec {w}>>"$d/slots/whole/1"; flock "$w"; echo w1 > "$d/slots/whole/1"; : > "$d/W.held"
    wait_until "[ -e '$d/W.go' ]" ) &
  wait_until "[ -e '$d/W.held' ]" || fail "the stand-in ticket was not taken"
  : > "$d/E.ask"
  wait_until "flock -n '$d/slots/1' true" "cat '$d/E.err'" || : > "$d/E.kept"
  [ ! -e "$d/E.on" ] || : > "$d/E.early"
  : > "$d/W.go"
  wait_until "[ -e '$d/E.on' ]" "cat '$d/E.err'" || : > "$d/E.none"
  : > "$d/E.go"; wait_until "[ -e '$d/E.ran' ]"; flock -n "$d/slots/1" true && : > "$d/E.lost"
  : > "$d/E.free"; : > "$d/P.free"; wait
  [ ! -e "$d/E.kept" ] || fail "a card's run holding the slot an earlier run waits to take back did not give it up"
  [ ! -e "$d/E.early" ] || fail "a card's run took its turn ahead of a run that asked before it"
  [ ! -e "$d/E.none" ] || fail "the card's run that gave its slot up got no turn once the earlier run had gone"
  [ ! -e "$d/E.lost" ] || fail "the card's step held no slot once its runner had taken its slot back and ended"
}

# Turns are for whole-suite runs alone: a run of a few chosen cases, with both turns held, starts and ends as before.
t_slotwholechosen() {
  local d=$T/$CASE
  slotpool 3; mkdir -p "$d"; unset CONVEYOR_TEST_WHOLE CONVEYOR_TEST_TURNWAIT
  wholerun A; wholerun B
  wait_until "[ -e '$d/A.on' ] && [ -e '$d/B.on' ]" || fail "two whole-suite runs did not both get a turn"
  CONVEYOR_SHELL_TEST_CASE=slothome timeout 120 bash "$SRC/conveyor.test.sh" > "$d/run.out" 2>&1 \
    || fail "a run of a chosen case did not pass while two whole-suite runs held their turns: $(cat "$d/run.out")"
  grep -qx 'ok slothome' "$d/run.out" || fail "the chosen case did not run: $(cat "$d/run.out")"
  ! grep -q 'whole-suite' "$d/run.out" || fail "a run of a chosen case took a whole-suite turn: $(cat "$d/run.out")"
  : > "$d/A.go"; : > "$d/B.go"; wait
}
