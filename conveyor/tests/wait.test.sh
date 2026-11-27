#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the tests' own wait for a condition (wait.sh), which every case uses in place of a set pause.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bugs: a wait gives up on a condition that is not true yet, so a case fails on a busy machine; a wait on a condition
# that never comes true hangs the run, or ends without saying what it waited for and what it last saw, so the
# failure cannot be read; a wait that ended at its ceiling passes for one that was met; a wait gives up before or
# after the ceiling it was given; a condition that blocks is never cut, so its wait has no ceiling; nor has one whose
# state blocks; a blocked condition that ignores the signal to end is left running after its wait; a condition that
# prints a NUL byte ends the read of its output there, so a failing one that printed 0 before it passes, and one
# that blocks after it is waited for with no ceiling; a clock that moves on between the check of the time left and the
# read leaves the read no time, so it fails at once, which passes for the end of a condition that blocks.
# Each ceiling the cases wait out is a case of its own: one after another, they made one case of 11 s.
t_waituntil() {
  local d=$T/$CASE; mkdir -p "$d"
  # True late: the condition holds from its third run on, however long each run takes.
  wait_until 'echo x >> "$d/runs"; [ "$(wc -l < "$d/runs")" -ge 3 ]' || fail "a condition that becomes true late did not pass"
  [ "$(wc -l < "$d/runs")" = 3 ] || fail "the wait did not end at the run that held: $(wc -l < "$d/runs") runs"
  # True at once: one run, no pause.
  : > "$d/runs"; wait_until 'echo x >> "$d/runs"' && [ "$(wc -l < "$d/runs")" = 1 ] || fail "a condition true at once was run $(wc -l < "$d/runs") times"
}
t_waitceiling() {
  local d=$T/$CASE out rc s; mkdir -p "$d"
  # Never true: it fails at the ceiling, naming the condition and the state the caller asks for. The ceiling is the
  # helper's own setting, and the wait lasts it: never less than its 3 s here, and, on a clock that each pause moves on
  # 100 s, no more than the 10 pauses that 1000 s hold (a busy machine makes them fewer, never more).
  : > "$d/runs"; s=$SECONDS; out=$(WAIT_CEILING=3 wait_until '[ -e "$d/never" ]' 'echo "in the folder: $(ls "$d")"' 2>&1); rc=$?
  [ "$rc" = 1 ] || fail "a condition that never holds did not fail at the ceiling (exit $rc): $out"
  [ $((SECONDS - s)) -ge 3 ] || fail "a wait with a ceiling of 3 s gave up after $((SECONDS - s)) s"
  grep -qF 'not true after 3 s: [ -e "$d/never" ]' <<<"$out" || fail "the ceiling does not name the condition: $out"
  grep -qF 'last state: in the folder: runs' <<<"$out" || fail "the ceiling does not print the last state: $out"
  out=$(sleep() { SECONDS=$((SECONDS + 100)); echo x >> "$d/pauses"; }; WAIT_CEILING=1000 wait_until false 2>&1) && fail "a failing condition passed"
  [ "$(wc -l < "$d/pauses")" -le 10 ] && grep -qF 'not true after 1000 s: false' <<<"$out" \
    || fail "a wait with a ceiling of 1000 s went on past it: $(wc -l < "$d/pauses") pauses of 100 s: $out"
}
# With no state asked for, the last state is what the condition's last run printed, or its exit status.
t_waitprinted() {
  local out
  out=$(WAIT_CEILING=1 wait_until 'echo "seen: nothing yet"; false' 2>&1) && fail "a failing condition passed"
  grep -qF 'last state: seen: nothing yet' <<<"$out" || fail "the ceiling does not print what the condition last printed: $out"
}
t_waitexit() {
  local out
  out=$(WAIT_CEILING=1 wait_until 'return 7' 2>&1) && fail "a failing condition passed"
  grep -qF 'last state: exit 7, nothing printed' <<<"$out" || fail "the ceiling does not print the condition's exit status: $out"
}
# A condition that blocks is ended at the ceiling with what it started, though they ignore the signal to end (the
# child takes that from it), and the failure says it was still running.
t_waitblocked() {
  local d=$T/$CASE out p; mkdir -p "$d"
  out=$(WAIT_CEILING=1 wait_until 'echo $BASHPID > "$d/blocked"; echo "seen: waiting"; trap "" TERM; sleep 300 & echo $! >> "$d/blocked"; while :; do :; done' 2>&1) && fail "a condition that blocks passed" # sleep: the child a blocked condition leaves
  grep -qF 'not true after 1 s: echo $BASHPID' <<<"$out" && grep -qF 'last state: seen: waiting; the condition was still running' <<<"$out" \
    || fail "the ceiling does not say the condition was still running: $out"
  for p in $(cat "$d/blocked"); do wait_until "! kill -0 $p 2>/dev/null" || fail "a blocked condition's process $p was left running"; done
}
# A state that blocks is ended at the ceiling too: the wait still fails, naming the condition and what the state printed.
t_waitstateblocked() {
  local d=$T/$CASE out; mkdir -p "$d"
  out=$(WAIT_CEILING=1 wait_until false 'echo $BASHPID > "$d/state"; echo "seen: so far"; while :; do :; done' 2>&1) && fail "a failing condition passed"
  grep -qF 'not true after 1 s: false' <<<"$out" && grep -qF 'last state: seen: so far; the state was still running' <<<"$out" \
    || fail "the ceiling does not say the state was still running: $out"
  wait_until "! kill -0 $(cat "$d/state") 2>/dev/null" || fail "a blocked state's process was left running"
}
# A NUL byte the condition prints does not end the read of it: the exit status is still the run's own, not the
# line printed before the byte, and a condition that blocks after the byte is still ended at the ceiling.
t_waitnul() {
  local out
  out=$(WAIT_CEILING=1 wait_until "printf '0\\0'; false" 2>&1) && fail "a failing condition that printed 0 and a NUL byte passed"
  grep -qF 'last state: 0' <<<"$out" || fail "the ceiling does not print what stood before the NUL byte: $out"
}
t_waitnulblocked() {
  local d=$T/$CASE out; mkdir -p "$d"
  out=$(WAIT_CEILING=1 wait_until 'echo $BASHPID > "$d/nul"; printf "\\0"; while :; do :; done' 2>&1) && fail "a condition that blocks after a NUL byte passed"
  grep -qF 'last state: the condition was still running' <<<"$out" || fail "the ceiling does not say the condition was still running after a NUL byte: $out"
  wait_until "! kill -0 $(cat "$d/nul") 2>/dev/null" || fail "a condition blocked after a NUL byte was left running"
}
# The clock moves on a second just before each read (the trap runs between the check of the time left and the read):
# the read still has the time that was checked, so a condition that blocks is ended at the ceiling, not waited for.
t_waittick() {
  local d=$T/$CASE out; mkdir -p "$d"
  out=$(set -T; trap '[[ $BASH_COMMAND != *"read -r"* ]] || SECONDS=$((SECONDS + 1))' DEBUG
    WAIT_CEILING=1 wait_until 'echo $BASHPID > "$d/tick"; while :; do :; done' 2>&1) && fail "a condition that blocks passed when the clock moved on before the read"
  grep -qF 'last state: the condition was still running' <<<"$out" || fail "the ceiling does not say the condition was still running when the clock moved on before the read: $out"
  wait_until "! kill -0 $(cat "$d/tick") 2>/dev/null" || fail "a condition blocked when the clock moved on before the read was left running"
}
# Bugs: cases_side starts every case at once, so a file of many cases overloads the machine; it runs them one after
# another, so a file takes the sum of its cases; it waits for more than one slot to free before it starts the next, so
# slow cases hold slots empty; it runs a case twice or drops one; it waits for a background job the caller started
# before it, or passes when a case failed while it freed a slot.
# Each of the 20 cases records how many case shells are alive as it starts, then stays alive a short while. Cases 1
# to 7 stay alive until every case has started, so cases 8 to 19 must take turns in the one slot left: a helper that
# waits for more than one slot to free (a whole batch of 8, or the 7 other cases) before it starts the next never
# starts case 9 while cases 1 to 7 live, so they record that they were still waiting. Case f fails and starts first,
# so it is the case that ends to free the slot for case 8: its status comes from the `wait -n` that frees a slot, not
# from the final waits, and a cases_side that drops a failure there returns 0.
side_case() {
  touch "$D/alive/$BASHPID"; ls "$D/alive" | wc -l >> "$D/counts"; echo "$1" >> "$D/ran"
  if [[ $1 == [1-7] ]]; then
    WAIT_CEILING=10 wait_until "[ \$(wc -l < '$D/ran') -ge 20 ]" 2> /dev/null || wc -l < "$D/ran" > "$D/held"
  else
    sleep 0.2 # sleep: the case stays alive a while, so cases started side by side overlap
  fi
  rm "$D/alive/$BASHPID"; [ "$1" != f ]
}
t_casesside() {
  local D=$T/$CASE job rc n; mkdir -p "$D/alive"
  # cases_side runs <prefix><case>, so each case is a function side_<case> that runs side_case with its own name.
  for n in f $(seq 1 19); do eval "side_$n() { side_case $n; }"; done
  sleep 30 & job=$! # sleep: a background job of the caller's own, which cases_side must not wait for
  cases_side side_ f $(seq 1 19); rc=$?
  kill -0 "$job" 2>/dev/null || fail "cases_side waited for a background job the caller started before it"
  kill "$job"
  [ "$rc" = 1 ] || fail "cases_side side_ f 1..19 returned $rc, not 1, when case f failed while it freed a slot"
  [ "$(sort -n "$D/counts" | tail -1)" -le 8 ] || fail "cases_side side_ f 1..19 had more than 8 cases alive: $(sort -n "$D/counts" | tr '\n' ' ')"
  [ "$(sort -n "$D/counts" | tail -1)" -ge 2 ] || fail "cases_side side_ f 1..19 ran its cases one after another: $(sort -n "$D/counts" | tr '\n' ' ')"
  [ ! -e "$D/held" ] || fail "cases_side side_ f 1..19 did not start the next case when one of 8 slots was free: only $(cat "$D/held") of 20 cases started while cases 1 to 7 were alive"
  [ "$(sort "$D/ran" | tr '\n' ' ')" = "$(printf '%s\n' f $(seq 1 19) | sort | tr '\n' ' ')" ] \
    || fail "cases_side side_ f 1..19 did not run each case one time: $(sort "$D/ran" | tr '\n' ' ')"
}
# Bug: cases_side passes when a case failed and only the final waits get its status. With 2 cases no slot is freed, so
# the failing case f ends in the final waits; t_casesside gets f's status from `wait -n` and cannot see this.
t_casessidelast() {
  local D=$T/$CASE rc n; mkdir -p "$D/alive"
  for n in 8 f; do eval "side_$n() { side_case $n; }"; done
  cases_side side_ 8 f; rc=$?
  [ "$rc" = 1 ] || fail "cases_side side_ 8 f returned $rc, not 1, when case f failed"
}
