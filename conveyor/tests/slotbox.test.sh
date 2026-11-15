#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a test slot's box (lib/slots.sh slot_box), the hard CPU and memory limit each test file and each
# engine case runs in: one core and the slot's share of the machine's memory.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Issue 457 (the owner, 2026-11-14: the Board's browser tests took most of the machine from every other card; a slot
# only counted a file, and a test pinned to its slot's core could move its work onto every other). Bug it catches: a
# test that widens its cores and starts three busy processes got three cores. In its slot's box it gets one: its CPU
# seconds are no more than its clock seconds (with a margin for the quota's 100 ms periods). The box's limits are the
# slot's share: cpu.max one core, memory.max the machine's memory over the pool's slots. The command's `$1` reaches it
# as written (systemd-run would read it as its own without --expand-environment=no, and the box file would not be
# written). The case itself runs in its slot's box (run_case), and a box asked for inside a box is none: one made
# there would be a scope beside it, outside its limit. A machine with no user systemd scope boxes nothing, as before.
t_slotbox() {
  local d=$T/$CASE wall cpu
  mkdir -p "$d"
  command -v systemd-run >/dev/null && timeout 10 systemd-run --user --scope --quiet true >/dev/null 2>&1 </dev/null \
    || { ( unset CONVEYOR_TEST_BOX; slot_box; [ ${#SLOT_BOX[@]} = 0 ] || { echo "${SLOT_BOX[*]}"; exit 1; } ) > "$d/nobox" \
           || fail "with no user systemd scope on this machine, slot_box still made a box: $(cat "$d/nobox")"; return 0; }
  [ "${CONVEYOR_TEST_BOX:-}" = 1 ] && grep -qx '100000 100000' "/sys/fs/cgroup$(cut -d: -f3 /proc/self/cgroup)/cpu.max" \
    || fail "the case does not run in its slot's box: $(cat /proc/self/cgroup)"
  ( slot_box; [ ${#SLOT_BOX[@]} = 0 ] ) || fail "a box asked for inside a box was made"
  ( unset CONVEYOR_TEST_BOX; slot_box; [ ${#SLOT_BOX[@]} -gt 0 ] || exit 1
    s=${EPOCHREALTIME//[!0-9]/}; times > "$d/cpu"
    "${SLOT_BOX[@]}" bash -c 'g=/sys/fs/cgroup$(cut -d: -f3 /proc/self/cgroup); cat "$g/cpu.max" "$g/memory.max" > "$1/box"
      taskset -cp "0-$(( $(nproc --all) - 1 ))" $$ > /dev/null 2>&1
      for i in 1 2 3; do timeout 1.5 bash -c "while :; do :; done" & done; wait' _ "$d"
    times >> "$d/cpu"; echo $(( (${EPOCHREALTIME//[!0-9]/} - s) / 1000 )) > "$d/wall" ) || fail "no box was made where a user systemd scope can be"
  [ "$(cat "$d/box" 2>&1)" = "100000 100000
$(awk -v n="$SLOT_N" '/^MemTotal:/ { printf "%d", int($2 / 1024 / n) * 1048576 }' /proc/meminfo)" ] || fail "the box's limits are not one core and the slot's memory: $(cat "$d/box" 2>&1)"
  wall=$(cat "$d/wall"); CASE_CPU=''; case_cpu "$d/cpu"; cpu=$CASE_CPU
  [ -n "$cpu" ] && [ "$cpu" -ge 500 ] && [ "$cpu" -le $((wall * 12 / 10)) ] || fail "three busy processes in a one-core box used $cpu CPU ms in $wall ms"
}
