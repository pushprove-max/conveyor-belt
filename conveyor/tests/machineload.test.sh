#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the machine's load limit (`conveyor.sh machine load`), the host file's maxLoad the Board's Rules tab sets.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bugs (#462): the load limit could be set only by editing the host file by hand, so a machine ran at 4 to 6 times its
# cores with none set; a limit the Board sent that is no number, or below 1 (no card would ever start), was written;
# setting it lost the host file's other settings; the Board could not show the machine's cores and load beside it.
t_machineload() {
  setup '[]'
  local H=$XDG_CONFIG_HOME/conveyor/host.json out
  mkdir -p "${H%/*}"
  jq -n --arg r "$R" '{records: [{repo: "solo", main: $r}], cap: 4, mode: "pause"}' > "$H"
  out=$(loop machine load 20) && grep -q "load limit is 20" <<<"$out" || fail "machine load 20 was refused: $out"
  [ "$(jq -c '[.maxLoad, .cap, .mode, (.records | length)]' "$H")" = '[20,4,"pause",1]' ] || fail "maxLoad is not the number 20, or a setting was lost: $(cat "$H")"
  [ "$(loop health | jq -c .machine.maxLoad)" = 20 ] || fail "the room does not read the limit: $(loop health | jq -c .machine)"
  loop machine load 12.5 >/dev/null && [ "$(jq .maxLoad "$H")" = 12.5 ] || fail "a limit with a fraction was not taken: $(cat "$H")"
  for bad in abc 0 0.5 -3 '' 1e3 '20 ' '1;rm'; do
    out=$(loop machine load "$bad" 2>&1); [ $? = 2 ] && grep -q 'a number of 1 or more, or off' <<<"$out" \
      && [ "$(jq .maxLoad "$H")" = 12.5 ] || fail "the limit \"$bad\" was not refused, or it changed the host file: $out; $(cat "$H")"
  done
  out=$(loop machine load off) && grep -q "load limit is off" <<<"$out" || fail "machine load off was refused: $out"
  [ "$(jq -c '[has("maxLoad"), .cap, .mode]' "$H")" = '[false,4,"pause"]' ] || fail "off did not remove maxLoad, or a setting was lost: $(cat "$H")"
  # The machine's cores and 1-minute load, as the room reads it, for the Board to show beside the limit.
  [ "$(CONVEYOR_ROOM_CMD='echo 31.5 9000' loop health | jq -c .machineNow)" = "{\"cores\":$(getconf _NPROCESSORS_ONLN),\"load\":31.5}" ] \
    || fail "health does not give the machine's cores and load: $(CONVEYOR_ROOM_CMD='echo 31.5 9000' loop health | jq -c .machineNow)"
}
