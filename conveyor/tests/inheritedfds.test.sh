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

# Bug (#216): slot_left, which holds a runner's slot while a process its worker left behind runs on, closed only fds 3
# to 255, so it kept the locks taken above 255, the release lock among them: a release could not start until that
# process had ended. The case calls slot_left itself (#343): in a release-prep, relreap ends slot_left's process with
# the run, so a lock it leaked would be free again before any check there.
t_fdsslotleft() {
  local lk g i
  holdfds
  exec {lk}>>"$T/$CASE.lock" && flock -n "$lk" && [ "$lk" -gt 255 ] || fail "the lock was not taken above 255: fd $lk"
  g=$( (set -m; sleep 30 {lk}>&- >/dev/null 2>&1 & echo $!) ) # sleep: the worker's left process, its own group
  # shellcheck disable=SC2064 # g is local: the trap must hold its value now, as it runs after this function returns
  trap "kill $g 2>/dev/null" EXIT
  slot_left "$g"
  exec {lk}>&-
  # slot_left's process starts with every fd of this shell and closes them in the background: the lock is given 10 s
  # to come free, and the left process must still run after it has, so slot_left's process is still waiting then.
  lim=$(loadlimit 100 300) # tenths of a second, under the left process's 30 s
  for ((i = 0; i < lim; i++)); do flock -n "$T/$CASE.lock" true && break; sleep 0.1; done
  [ "$i" -lt "$lim" ] || fail "the lock is still held while slot_left waits: it kept the lock's fd above 255 (waited $lim tenths of a second: 10 s times the load factor $CASE_LOAD)"
  pgrep -g "$g" >/dev/null || fail "the left process ended before the check: the lock may have come free only then"
}

# Bug (#216, #335): release-prep waited for a process its suite left behind before it ended, and a release could not
# start until it had. The run takes a slot of a pool of the case's own, as a loop outside a test does (slot_left runs
# only then); the suite leaves a process of its group behind for 60 s, one that closed every fd it inherited.
# Release-prep's end ends it (#335), so the case times release-prep: it ends well before the left process would have.
t_fdsrelease() {
  local out left; export XDG_CONFIG_HOME=$T/$CASE/config; unset CONVEYOR_TEST_SLOT
  mkdir -p "$XDG_CONFIG_HOME/conveyor" && echo "{\"testSlots\": 1, \"testSlotsDir\": \"$T/$CASE/slots\"}" > "$XDG_CONFIG_HOME/conveyor/host.json" \
    || fail "the host file was not written"
  cutsetup true
  left='(for f in /dev/fd/*; do f=${f##*/}; [ "$f" -le 2 ] || eval "exec $f>&-"; done; echo $BASHPID >> "$STUB/left"; exec sleep 60) </dev/null >/dev/null 2>&1 &' # sleep: the left process, which release-prep must not wait for
  printf 'git rev-parse HEAD > "$STUB/full-at"\n%s\n' "$left" > "$STUB/full-cmd" || fail "the suite stub was not written"
  trap 'kill $(cat "$STUB/left" 2>/dev/null) 2>/dev/null' EXIT
  holdfds
  SECONDS=0; out=$(loop release-prep 1.1.0 2>&1) || fail "release-prep failed: $out"
  [ "$SECONDS" -lt 60 ] || fail "release-prep ended only once the process its suite left had"
  # release-prep's passing status: release takes it, so it runs no suite and needs no slot.
  echo '[{"context":"conveyor/release-suite","state":"success"}]' > "$STUB/statuses"
  out=$(loop release 1.1.0 2>&1) || fail "release right after release-prep was refused: $out"
  flock -n "$T/$CASE/cards/release/lock" true || fail "the release lock is still held once release ended"
}
