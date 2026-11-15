#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the closure test's whole-suite turns (tools/closure.test.sh, lib/slots.sh slot_whole).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner. slotpool and wholerun are slots.test.sh's.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# The closure test's <case>, run on the case's pool with a home and a temporary folder of the case's own, its output
# in <d>/run.out.
closurerun() { # <case>
  mkdir -p "$d/home" "$d/tmp"
  HOME=$d/home TMPDIR=$d/tmp CONVEYOR_SHELL_TEST_CASE=$1 exec bash "$SRC/tools/closure.test.sh" > "$d/run.out" 2>&1
}

# The held slots of the case's pool of <n>.
heldslots() { # <n>
  local k h=0
  for ((k = 1; k <= $1; k++)); do flock -n "$d/slots/$k" true || h=$((h + 1)); done
  echo "$h"
}

# Bug (2026-11-15): the closure test's install case ran every test from the copy, one unit a slot, with no whole-suite
# turn: two cards each ran it beside two other whole-suite runs, and the machine's load reached 97 on 16 cores. Two
# whole-suite runs hold their turns of a pool of 4; the install case waits for a turn with one slot (its home), makes
# no install and starts no unit on the fourth slot until a turn is given back, and then takes it.
t_closureturn() {
  local d=$T/$CASE r
  slotpool 4; mkdir -p "$d"; unset CONVEYOR_TEST_WHOLE CONVEYOR_TEST_TURNWAIT
  wholerun A; wholerun B
  wait_until "[ -e '$d/A.on' ] && [ -e '$d/B.on' ]" "cat '$d/A.err' '$d/B.err'" || fail "two whole-suite runs did not both get a turn"
  set -m; ( set +m; closurerun install ) & r=$!; set +m
  wait_until "grep -q 'this one waits for its turn' '$d/run.out'" "cat '$d/run.out'" \
    || { kill -TERM -- -$r 2>/dev/null; fail "the closure test's install case did not wait for a whole-suite turn while two were held"; }
  sleep 1 # sleep: a run that went on past the wait has made its install and its units hold slots by now; none tells it did not
  [ "$(heldslots 4)" = 3 ] && ! ls "$d"/tmp/*/install.install >/dev/null 2>&1 \
    || { kill -TERM -- -$r 2>/dev/null; fail "the install case made its install or a unit took a slot while it waited for a turn ($(heldslots 4) of 4 held)"; }
  : > "$d/A.go"
  wait_until "grep -q '^conveyor: slot wait: [0-9]* s for a whole-suite turn$' '$d/run.out'" "cat '$d/run.out'" \
    || { kill -TERM -- -$r 2>/dev/null; fail "the install case did not take the turn given back"; }
  kill -TERM -- -$r 2>/dev/null; wait $r; : > "$d/B.go"; wait
}

# The set checks run a few units each and take no turn: the set case passes while two whole-suite runs hold theirs.
# A runner that took a turn for every case would wait here, as the whole test did.
t_closureset() {
  local d=$T/$CASE
  slotpool 3; mkdir -p "$d"; unset CONVEYOR_TEST_WHOLE CONVEYOR_TEST_TURNWAIT
  wholerun A; wholerun B
  wait_until "[ -e '$d/A.on' ] && [ -e '$d/B.on' ]" "cat '$d/A.err' '$d/B.err'" || fail "two whole-suite runs did not both get a turn"
  ( timeout 120 bash -c "$(declare -f closurerun); d='$d' SRC='$SRC' closurerun set" ) \
    || { : > "$d/A.go"; : > "$d/B.go"; fail "the closure test's set case failed while two whole-suite turns were held: $(tail -20 "$d/run.out")"; }
  : > "$d/A.go"; : > "$d/B.go"; wait
  grep -qx 'ok set' "$d/run.out" || fail "the set case did not run: $(tail -20 "$d/run.out")"
  ! grep -q 'waits for its turn' "$d/run.out" || fail "the set case waited for a whole-suite turn"
}
