#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: a lock or slot taken by a shell that inherited many fds (closefds, lib/slots.sh). Their fixtures are
# testactrun.test.sh's trsetup and release.test.sh's cutsetup.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Holds every free fd from 3 to 255 in the case's shell, as a serve that leaked hundreds left its cards' shells: each
# lock and slot fd the engine takes after it is above 255.
holdfds() { local f; for ((f = 3; f < 256; f++)); do [ -e "/dev/fd/$f" ] || eval "exec $f</dev/null"; done; }

# Bug (#216): testclock closed only fds 3 to 255, so its `sleep 1`, alive after the run killed it, held the slot fd
# taken above 255, and the slot was still held once the run by hand had ended.
t_fdstarun() {
  trsetup; local id
  holdfds
  id=$(loop testaction run tests/x.test.sh 2>&1) && [[ $id =~ ^[0-9a-f]{12}$ ]] || fail "the run did not start: $id"
  wait_until '[ -s "$STUB/tr-held" ]' "cat '$ST/testactions/$id.err'" || fail "the test command did not start"
  : > "$STUB/tr-go"
  wait_until "[ \"\$(tarec $id .state)\" != running ]" "cat '$ST/testactions/$id.json' '$ST/testactions/$id.err'" || fail "the record still says running after the run ended"
  trfree || fail "the slot is still held once the run ended: a process of the run kept its fd above 255"
}

# Bug (#216): slot_left, which holds release-prep's slot while a process its suite left behind runs on, closed only
# fds 3 to 255, so it kept the locks taken above 255, the release lock among them: release-prep itself waited for
# that process before it ended, and a release could not start until it had. The run takes a slot of a pool of the case's
# own, as a loop outside a test does (slot_left runs only then); the suite leaves a process of its group behind for
# 20 s, one that closed every fd it inherited, and killed at the case's end.
t_fdsrelease() {
  local out left; export XDG_CONFIG_HOME=$T/$CASE/config; unset CONVEYOR_TEST_SLOT
  mkdir -p "$XDG_CONFIG_HOME/conveyor" && echo "{\"testSlots\": 1, \"testSlotsDir\": \"$T/$CASE/slots\"}" > "$XDG_CONFIG_HOME/conveyor/host.json" \
    || fail "the host file was not written"
  cutsetup true
  left='(for f in /dev/fd/*; do f=${f##*/}; [ "$f" -le 2 ] || eval "exec $f>&-"; done; echo $BASHPID >> "$STUB/left"; exec sleep 20) </dev/null >/dev/null 2>&1 &' # sleep: the left process, killed at the case's end
  printf 'git rev-parse HEAD > "$STUB/full-at"\n%s\n' "$left" > "$STUB/full-cmd" || fail "the suite stub was not written"
  trap 'kill $(cat "$STUB/left" 2>/dev/null) 2>/dev/null' EXIT
  holdfds
  out=$(loop release-prep 1.1.0 2>&1) || fail "release-prep failed: $out"
  kill -0 "$(cat "$STUB/left")" 2>/dev/null || fail "release-prep ended only once the process its suite left had: its slot_left kept a lock above 255"
  # release-prep's passing status: release takes it, so it runs no suite and needs no slot.
  echo '[{"context":"conveyor/release-suite","state":"success"}]' > "$STUB/statuses"
  out=$(loop release 1.1.0 2>&1) || fail "release right after release-prep was refused: $out"
  flock -n "$T/$CASE/cards/release/lock" true || fail "the release lock is still held once release ended"
}
