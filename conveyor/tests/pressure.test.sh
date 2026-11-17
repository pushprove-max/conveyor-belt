#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the machine's pressure (lib/pressure.sh), its states Steady, Busy and Strained, and what they hold back:
# a new card (room(), lib/pick.sh) and a new test's slot (slot_strained(), lib/slots.sh).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Writes the fixture PSI files of the folder CONVEYOR_PSI_DIR names, as /proc/pressure has them: <cpu> and <memory>
# are their "some avg10".
prpsi() { # <cpu> <memory>
  printf 'some avg10=%s avg60=1.00 avg300=1.00 total=100\nfull avg10=99.00 avg60=0.00 avg300=0.00 total=0\n' "$1" > "$CONVEYOR_PSI_DIR/cpu"
  printf 'some avg10=%s avg60=1.00 avg300=1.00 total=100\nfull avg10=99.00 avg60=0.00 avg300=0.00 total=0\n' "$2" > "$CONVEYOR_PSI_DIR/memory"
}
# pressure()'s state and why for <host file>, as "<state>|<why>", with the wake delay <wake> (empty: none read).
prstate() { # <host file> <wake>
  CONVEYOR_WAKE_CMD="echo $2" pressure "$1" | jq -r '[.state // "null", .why // ""] | join("|")'
}

# Bugs: the machine room read the load average, which a machine of pinned test runs passes while it still answers at
# once; the state did not come from PSI's "some avg10" (the "full" line, or another average, was read); a threshold
# of the host file was not taken, or one that is no number was; on Linux, the free memory set the state beside the
# memory pressure. One state from fixture PSI files and a stubbed wake delay for each figure that sets it.
t_pressurepsi() {
  local H=$T/$CASE/host.json got
  export CONVEYOR_PSI_DIR=$T/$CASE/psi CONVEYOR_ROOM_CMD='echo 99 10' # 10 MB free: never read where memory PSI is
  mkdir -p "$CONVEYOR_PSI_DIR"; echo '{}' > "$H"
  prpsi 12.5 1.5
  got=$(CONVEYOR_WAKE_CMD='echo 0.2' pressure "$H")
  [ "$(jq -c '[.state, .cpu, .memory, .wakeMs, .freeMB, .why]' <<<"$got")" = '["Steady",12.5,1.5,0.2,null,null]' ] || fail "a quiet machine is not Steady with its figures: $got"
  prpsi 45.5 1.5; [ "$(prstate "$H" 0.2)" = "Busy|CPU pressure 45.5% is at or above 40%" ] || fail "CPU pressure did not make it Busy: $(prstate "$H" 0.2)"
  prpsi 12.5 6.5; [ "$(prstate "$H" 0.2)" = "Busy|memory pressure 6.5% is at or above 5%" ] || fail "memory pressure did not make it Busy: $(prstate "$H" 0.2)"
  prpsi 12.5 1.5; [ "$(prstate "$H" 7.5)" = "Busy|the wake delay 7.5 ms is at or above 5 ms" ] || fail "the wake delay did not make it Busy: $(prstate "$H" 7.5)"
  prpsi 85.5 6.5; [ "$(prstate "$H" 0.2)" = "Strained|CPU pressure 85.5% is at or above 80%" ] || fail "CPU pressure did not make it Strained: $(prstate "$H" 0.2)"
  prpsi 12.5 25.5; [ "$(prstate "$H" 0.2)" = "Strained|memory pressure 25.5% is at or above 20%" ] || fail "memory pressure did not make it Strained: $(prstate "$H" 0.2)"
  prpsi 12.5 1.5; [ "$(prstate "$H" 31.2)" = "Strained|the wake delay 31.2 ms is at or above 20 ms" ] || fail "the wake delay did not make it Strained: $(prstate "$H" 31.2)"
  # The host file's thresholds: CPU 85.5 is Busy under its Strained 95; one that is no number keeps its default.
  echo '{"pressure": {"strained": {"cpu": 95}, "busy": {"wakeMs": "x"}}}' > "$H"
  prpsi 85.5 1.5; [ "$(prstate "$H" 0.2)" = "Busy|CPU pressure 85.5% is at or above 40%" ] || fail "the host file's Strained CPU threshold was not taken: $(prstate "$H" 0.2)"
  prpsi 12.5 1.5; [ "$(prstate "$H" 7.5)" = "Busy|the wake delay 7.5 ms is at or above 5 ms" ] || fail "a threshold that is no number was taken: $(prstate "$H" 7.5)"
}

# Bugs: on macOS (no PSI) nothing set the state, or the free memory did not; the wake delay was not measured on a
# system with no stub; a machine room with no figure read was Steady.
t_pressurenopsi() {
  local H=$T/$CASE/host.json got w
  export CONVEYOR_PSI_DIR=$T/$CASE/none; mkdir -p "${H%/*}"; echo '{}' > "$H"
  got=$(CONVEYOR_ROOM_CMD='echo 1 4000' CONVEYOR_WAKE_CMD='echo 0.3' pressure "$H")
  [ "$(jq -c '[.state, .cpu, .memory, .wakeMs, .freeMB]' <<<"$got")" = '["Steady",null,null,0.3,4000]' ] || fail "a quiet machine with no PSI is not Steady with its figures: $got"
  [ "$(CONVEYOR_ROOM_CMD='echo 1 1500' prstate "$H" 0.3)" = "Busy|1500 MB free is below 2048 MB" ] || fail "low free memory did not make it Busy: $(CONVEYOR_ROOM_CMD='echo 1 1500' prstate "$H" 0.3)"
  [ "$(CONVEYOR_ROOM_CMD='echo 1 400' prstate "$H" 0.3)" = "Strained|400 MB free is below 512 MB" ] || fail "very low free memory did not make it Strained: $(CONVEYOR_ROOM_CMD='echo 1 400' prstate "$H" 0.3)"
  [ "$(CONVEYOR_ROOM_CMD='echo 1 4000' prstate "$H" 25)" = "Strained|the wake delay 25 ms is at or above 20 ms" ] || fail "the wake delay did not make it Strained: $(CONVEYOR_ROOM_CMD='echo 1 4000' prstate "$H" 25)"
  [ "$(CONVEYOR_ROOM_CMD=: prstate "$H" '')" = "null|the machine room could not be read" ] || fail "no figure read is not said: $(CONVEYOR_ROOM_CMD=: prstate "$H" '')"
  # Bug: a script that sources lib/slots.sh and not lib/portable.sh (.conveyor/test-changed.sh) read no free memory,
  # as p_load and p_mem were not there, so a macOS with little free memory was Steady, not Strained.
  got=$(env -u CONVEYOR_ROOM_CMD CONVEYOR_WAKE_CMD='echo 0.3' bash -c '. "$0/lib/slots.sh" && pressure "$1"' "$SRC" "$H" 2>&1)
  jq -e '.freeMB | numbers' <<<"$got" >/dev/null || fail "lib/slots.sh alone read no free memory: $got"
  # The wake delay as measured, with no stub: ms to the tenth.
  w=$(unset CONVEYOR_WAKE_CMD; p_wake); [[ $w =~ ^[0-9]+\.[0-9]$ ]] || fail "the wake delay was not measured: '$w'"
}

# Bugs: a Strained machine started a new card; a Busy one started cards past half the machine's cap; a host file with
# neither maxLoad nor minFreeMemMB (and no other machine setting) held no card back; with maxLoad set the pressure held
# cards; the reason did not name the figure that held the card; health did not show the state and its figures.
# room(), as the loop's pick asks it.
# shellcheck disable=SC2034 # RUNNING is read by room(), from lib/pick.sh, read by the eval
t_pressureroom() {
  export XDG_CONFIG_HOME=$T/$CASE/config # the machine's folder is the case's own
  setup '[]'
  local H=$XDG_CONFIG_HOME/conveyor/host.json why
  export CONVEYOR_PSI_DIR=$T/$CASE/psi CONVEYOR_WAKE_CMD='echo 0.2'; mkdir -p "${H%/*}" "$CONVEYOR_PSI_DIR"
  jq -n --arg r "$R" '{records: [{repo: "solo", main: $r}]}' > "$H"
  export CONVEYOR_MAIN=$R; cd "$R" && . "$SRC/conveyor.sh" state-dir > /dev/null \
    && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" || fail "the engine could not be read"
  RUNNING=0
  gate() { why=$(room "$1"); }
  # A host file that sets no machine setting: Strained holds the card, and says the figure.
  prpsi 12.5 25.5
  ! gate 2 && [ "$why" = "waiting for machine room: Strained (memory pressure 25.5% is at or above 20%)" ] \
    && [ "$(jq -r .reason "$R/conveyor/state/room.json")" = "$why" ] || fail "#2 was not held by a Strained machine, or the figure was not said: $why"
  [ "$(loop health | jq -c '.pressure | [.state, .cpu, .memory, .wakeMs, .why, .gates]')" = '["Strained",12.5,25.5,0.2,"memory pressure 25.5% is at or above 20%",true]' ] \
    || fail "health does not show the pressure: $(loop health | jq -c .pressure)"
  # Busy with no cap holds none back.
  prpsi 45.5 1.5; RUNNING=3; gate 2 || fail "#2 was held by a Busy machine with no cap: $why"
  # With the cap 4, Busy starts a card up to its half, and none past it.
  jq '.cap = 4' "$H" > "$H.new" && mv "$H.new" "$H"
  RUNNING=1; gate 3 || fail "#3, the second of cap 4, was held by a Busy machine: $why"
  RUNNING=2; ! gate 4 && [ "$why" = "waiting for machine room: Busy (CPU pressure 45.5% is at or above 40%), and 2 of the machine cap 4 in use: no new card past its half" ] \
    || fail "#4, past half the cap, was not held by a Busy machine: $why"
  prpsi 12.5 1.5; gate 4 || fail "#4 was held by a Steady machine: $why"
  # maxLoad set: it keeps the room as today, and the pressure holds nothing.
  prpsi 85.5 25.5; jq '.maxLoad = 50' "$H" > "$H.new" && mv "$H.new" "$H"
  RUNNING=0; CONVEYOR_ROOM_CMD='echo 1 9000' gate 5 || fail "#5 was held by the pressure with maxLoad set: $why"
  # Bug: health did not say the pressure no longer gates, so the Board said a Strained machine held work back.
  [ "$(loop health | jq -c '.pressure | [.state, .gates]')" = '["Strained",false]' ] || fail "health says the pressure gates with maxLoad set: $(loop health | jq -c .pressure)"
}

# Bugs: a Strained machine let a new test take a slot; the reading was taken again by every waiting worker, not kept
# for a few seconds; one kept past them held tests back; with maxLoad set the pressure held tests back.
t_pressureslot() {
  export XDG_CONFIG_HOME=$T/$CASE/config CONVEYOR_PSI_DIR=$T/$CASE/psi CONVEYOR_WAKE_CMD='echo 0.2'
  local H=$T/$CASE/config/conveyor/host.json
  mkdir -p "${H%/*}" "$CONVEYOR_PSI_DIR"; jq -n --arg d "$T/$CASE/slots" '{testSlots: 2, testSlotsDir: $d}' > "$H"
  slot_pool || fail "the pool could not be made"
  prpsi 12.5 25.5
  ! slot_try || fail "a test took a slot while the machine was Strained"
  ! slot_wait 0.1 || fail "a test waited for a slot and got it while the machine was Strained"
  # Bug: a card held by the pressure with slots free said only "0 of 2 in use", not the figure that held it.
  [ "$(slot_waiting)" = "waiting for a test slot: the machine is Strained (memory pressure 25.5% is at or above 20%), 0 of 2 in use" ] \
    || fail "the Test step's wait did not name the figure that holds it: $(slot_waiting)"
  ! slot_try && [ "$(slot_waiting)" = "waiting for a test slot: the machine is Strained (memory pressure 25.5% is at or above 20%), 0 of 2 in use" ] \
    || fail "the kept reading lost the figure that holds the test: $(slot_waiting)"
  # Bug: the engine's test runner names the cases' host file (none) and a Steady pressure after it reads the pool
  # (tests/lib.sh): its own slots read those, and took the machine's slots while it was Strained.
  ( rm -f "$SLOT_DIR/pressure"; export XDG_CONFIG_HOME=$T/$CASE/cases CONVEYOR_PSI_DIR=$T/$CASE/steady
    mkdir -p "$CONVEYOR_PSI_DIR"; prpsi 0.00 0.00
    ! slot_try ) || fail "a test took a slot while the machine was Strained, once the environment named another host file and pressure"
  # The reading is kept: Steady now, but read Strained a moment ago.
  prpsi 12.5 1.5; echo "$EPOCHSECONDS Strained" > "$SLOT_DIR/pressure"
  ! slot_try || fail "the kept reading was not used"
  # One kept past a few seconds is read again.
  echo "$((EPOCHSECONDS - 5)) Strained" > "$SLOT_DIR/pressure"
  slot_try || fail "no slot was taken once the machine was Steady"
  exec {SLOT_FD}>&-
  [ "$(slot_waiting)" = "waiting for a test slot (0 of 2 in use)" ] || fail "a Steady machine's wait named a pressure figure: $(slot_waiting)"
  # maxLoad set: the pressure holds no test.
  prpsi 85.5 25.5; rm -f "$SLOT_DIR/pressure"; jq '.maxLoad = 50' "$H" > "$H.new" && mv "$H.new" "$H"
  slot_try || fail "a test was held by the pressure with maxLoad set"
}
