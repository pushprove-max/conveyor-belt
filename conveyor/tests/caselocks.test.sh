#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: each case's locks and cards folder are its own (lib.sh), never the machine's or another test run's.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bug (#212): cards that test side by side failed each other's engine cases ("release-prep or release is already
# running"), and each failure opened a false "Main is red" card. A case's engine call that names no cards folder of its
# own took the one CONVEYOR_CARDS names in the environment the runner was started in: one machine folder, one release
# lock for every card. Here two test runs at the same time, started with CONVEYOR_CARDS naming one folder whose release
# lock another run holds, each run the probe below in a temporary folder of its own: both pass, and nothing is written
# in that folder.
t_caselocks() {
  local d=$T/$CASE h a b r
  local M=$d/machine-cards
  mkdir -p "$M/release" "$d/config/conveyor" && echo "{\"testSlots\": 2, \"testSlotsDir\": \"$d/slots\"}" > "$d/config/conveyor/host.json" \
    && exec {h}>>"$M/release/lock" && flock -n "$h" || fail "the fixture could not be made"
  for r in a b; do
    XDG_CONFIG_HOME=$d/config CONVEYOR_CARDS=$M CONVEYOR_CASELOCK_PROBE=1 CONVEYOR_SHELL_TEST_CASE=caselockprobe \
      timeout 120 bash "$SRC/conveyor.test.sh" > "$d/$r.out" 2>&1 {h}>&- &
    eval "$r=\$!"
  done
  wait "$a"; a=$?; wait "$b"; b=$?; exec {h}>&-
  [ $a = 0 ] && [ $b = 0 ] || fail "two test runs side by side did not both pass (exit $a and $b): $(cat "$d/a.out" "$d/b.out")"
  [ "$(ls -A "$M/release")" = lock ] || fail "a case wrote in the machine's cards folder: $(ls -A "$M/release")"
}
# The probe the case above runs: release-prep called with no cards folder of its own takes the release lock of its own
# folder, beside its own main. It passes in any other run.
t_caselockprobe() {
  [ -n "${CONVEYOR_CASELOCK_PROBE:-}" ] || return 0
  local out
  setup '[]'; tune '.test.full = "true"'
  out=$(CONVEYOR_MAIN=$R bash "$SRC/conveyor.sh" release-prep 1.1.0 2>&1)
  ! grep -q 'already running' <<<"$out" || fail "release-prep took a release lock another run holds: $out"
  compgen -G "$T/$CASE/conveyor-cards*/release/run.json" > /dev/null || fail "release-prep did not start in the case's own cards folder: $out"
}
