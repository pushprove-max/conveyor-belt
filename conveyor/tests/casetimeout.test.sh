#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: each case's time limit in the engine's own runner (../conveyor.test.sh, lib.sh run_case and
# case_keep), its file's `# timeout:` line, in a whole-suite run as in a card's run of that file.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bug (#253): the release's whole-suite run ran every case in one process, where no file's `# timeout:` line applied,
# and one hung case stood the release still for 43 minutes with no error. The runner, run whole on two fixture case
# files and one test slot (one case at a time), stops the case that sleeps past its file's 2 s limit with its process
# group, names it as timed out (its output, cases/timedout of the run's log and the run's progress, fulltest.sh
# suiteprog(), that the release's result is), and then runs the other file's case.
t_casetimeout() {
  local d=$T/$CASE s f t0 rc took got
  s=$d/src; mkdir -p "$s/tests" "$d/wt.testlog" || fail "the fixture could not be made"
  export XDG_CONFIG_HOME=$d/config CASETIMEOUT_DIR=$d
  mkdir -p "$XDG_CONFIG_HOME/conveyor" && echo "{\"testSlots\": 1, \"testSlotsDir\": \"$d/slots\"}" > "$XDG_CONFIG_HOME/conveyor/host.json"
  # The engine as it is, with only the two fixture case files in its tests/.
  for f in "$SRC"/*; do [ "${f##*/}" = tests ] || ln -s "$f" "$s/"; done
  ln -s "$SRC/tests/lib.sh" "$SRC/tests/wait.sh" "$s/tests/"
  printf '%s\n' '# timeout: 2' 't_fxhang() { sleep 60 & sleep 60; }' > "$s/tests/hang.test.sh" # sleep: the fixture case must outlast its 2 s limit
  printf '%s\n' '# timeout: 60' 't_fxquick() { : > "$CASETIMEOUT_DIR/quick.ran"; }' > "$s/tests/quick.test.sh"
  t0=$(date +%s)
  CONVEYOR_TEST_LOG=$d/wt.testlog timeout 60 bash "$s/conveyor.test.sh" > "$d/wt.test" 2>&1; rc=$?
  took=$(( $(date +%s) - t0 ))
  [ $rc = 1 ] || fail "the run with a case past its limit did not end failed (exit $rc, ${took} s): $(cat "$d/wt.test")"
  [ "$took" -lt 30 ] || fail "the run waited for the hung case, ${took} s: $(cat "$d/wt.test")"
  grep -qx 'FAIL \[fxhang\]: timed out after 2 s .*' "$d/wt.test" || fail "the run does not name the case as timed out: $(cat "$d/wt.test")"
  grep -qx 'ok fxquick' "$d/wt.test" && [ -e "$d/quick.ran" ] || fail "the other file's case did not run after the hung one: $(cat "$d/wt.test")"
  got=$(cd "$d/wt.testlog/cases" && find . -type f | sort | tr '\n' ' ')
  [ "$got" = './failed/fxhang ./ok/fxquick ./timedout/fxhang ' ] || fail "the run's log does not name the case as failed and timed out: $got"
  # shellcheck source=/dev/null # suiteprog() alone, from the engine's lib/fulltest.sh
  source <(sed -n '/^suiteprog() {/,/^}/p' "$SRC/lib/fulltest.sh")
  got=$(suiteprog "$d/wt" | jq -c '{cases, timedout}')
  [ "$got" = '{"cases":["fxhang"],"timedout":["fxhang"]}' ] || fail "the run's progress does not name the case as timed out: $got"
}
