#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the runner's end of a case (lib.sh run_case, case_end) and the test slots a case leaves held.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Two processes an `adopt` case left (its stub that ignores TERM and, sent one, starts another that ignores it too,
# and that one's parent) held a slot of the machine's shared pool for some 20 hours (tests/speed/cases-2.md): every
# test run after it had a slot fewer. Two cases run one after the other as the runner runs them (run_case), on a
# runner's pool of 1: the first takes a slot of another pool, as a case's loop takes its test step's slot, leaves a
# process holding that slot that does what that stub did, and exits and passes; the second finds the slot free as it
# starts. A runner that reported the first case without ending what it left gave the second a slot still held.
# Issue 348: the second case also runs in its runner's own cgroup (Linux). Bug it catches: the runner started each
# case in a systemd scope of its own with a hard memory cap of the machine's memory over the slots (slot_box), so a
# case that needed more was killed and counted as a failure.
t_caseslot() {
  local d=$T/$CASE
  mkdir -p "$d/config/conveyor" && echo "{\"testSlots\": 1, \"testSlotsDir\": \"$d/slots\"}" > "$d/config/conveyor/host.json"
  export XDG_CONFIG_HOME=$d/config; : > "$d/held"
  t_slotheld() {
    ( for ((i = 3; i < 256; i++)); do eval "exec $i>&-"; done; exec 9>> "$T/caseslot/held"; flock -n 9 || exit 1
      deaf() { trap '' TERM; while :; do sleep 1; done; } # sleep: a stand-in that goes on until it is killed
      trap 'deaf & exit' TERM; echo "$BASHPID" > "$T/caseslot/left"
      while :; do sleep 1; done ) > /dev/null 2>&1 & # sleep: the process the case leaves, holding the slot
    until [ -s "$T/caseslot/left" ]; do sleep 0.05; done
    ! flock -n "$T/caseslot/held" true || fail "the process the case leaves does not hold the slot: the case shows nothing"
  }
  t_slotnext() {
    flock -n "$T/caseslot/held" true || fail "the slot the case before this one left held is still held as this one starts"
    [ ! -r /proc/self/cgroup ] || [ "$(cat /proc/self/cgroup)" = "$(cat "$T/caseslot/cgroup")" ] \
      || fail "the case ran in a cgroup of its own (a capped box), not its runner's: $(cat /proc/self/cgroup)"
  }
  [ ! -r /proc/self/cgroup ] || cat /proc/self/cgroup > "$d/cgroup"
  slot_pool && slot_take || fail "the runner's slot could not be taken"
  ( CASE=slotheld; run_case ) > "$d/out" 2>&1; slot_free
  grep -qx 'ok slotheld' "$d/out" || fail "the case that left a process holding a slot did not end and pass: $(cat "$d/out")"
  wait_until slot_try || fail "the runner's slot did not come back once the case had ended"
  ( CASE=slotnext; run_case ) > "$d/out" 2>&1; slot_free
  grep -qx 'ok slotnext' "$d/out" || fail "$(cat "$d/out")"
}
