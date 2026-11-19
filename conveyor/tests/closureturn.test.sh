#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the closure test takes no whole-suite turn (tools/closure.test.sh, lib/slots.sh slot_whole).
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

# The closure test runs no test file from its copy, and takes no turn: the set case passes while two whole-suite runs
# hold theirs.
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
