#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: what the snapshot (lib/snapshot.sh) reads of the machine beyond the cards' records.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Board 3D's deck shows the machine's free test slots (issue 393): the snapshot's testSlots must be the pool's own
# count, read as a test run reads it (the host file's testSlots and testSlotsDir), and change as a slot is taken and
# given back; a count of the card cap or a fixed figure would show slots free while every test run waits for one.
t_snapslots() {
  local f
  export XDG_CONFIG_HOME=$T/$CASE/config
  mkdir -p "$XDG_CONFIG_HOME/conveyor" && echo "{\"testSlots\": 2, \"testSlotsDir\": \"$T/$CASE/slots\"}" > "$XDG_CONFIG_HOME/conveyor/host.json"
  setup "[]"
  [ "$(loop snapshot | jq -c .testSlots)" = '{"used":0,"of":2}' ] || fail "with no slot held: $(loop snapshot | jq -c .testSlots)"
  # A test run holds slot 1, as slot_try takes it: a lock on its file.
  exec {f}>>"$T/$CASE/slots/1"; flock -n "$f" || fail "slot 1 could not be taken"
  [ "$(loop snapshot | jq -c .testSlots)" = '{"used":1,"of":2}' ] || fail "with slot 1 held: $(loop snapshot | jq -c .testSlots)"
  exec {f}>&-
  [ "$(loop snapshot | jq -c .testSlots)" = '{"used":0,"of":2}' ] || fail "once slot 1 was given back: $(loop snapshot | jq -c .testSlots)"
}
