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
  # The engine as it is, with only the two fixture case files in its tests/ (and the stub CLIs lib.sh's setup copies).
  for f in "$SRC"/*; do [ "${f##*/}" = tests ] || ln -s "$f" "$s/"; done
  ln -s "$SRC/tests/lib.sh" "$SRC/tests/wait.sh" "$SRC/tests/stubs" "$s/tests/"
  printf '%s\n' '# timeout: 2' 't_fxhang() { sleep 60 & sleep 60; }' > "$s/tests/hang.test.sh" # sleep: the fixture case must outlast its 2 s limit
  printf '%s\n' '# timeout: 60' 't_fxquick() { : > "$CASETIMEOUT_DIR/quick.ran"; }' > "$s/tests/quick.test.sh"
  t0=$(date +%s)
  CONVEYOR_TEST_LOG=$d/wt.testlog timeout 60 bash "$s/conveyor.test.sh" > "$d/wt.test" 2>&1; rc=$?
  took=$(( $(date +%s) - t0 ))
  [ $rc = 1 ] || fail "the run with a case past its limit did not end failed (exit $rc, ${took} s): $(cat "$d/wt.test")"
  lim=$(loadlimit 30 60) # under the hung case's 60 s
  [ "$took" -lt "$lim" ] || fail "the run waited for the hung case, ${took} s (limit $lim s: 30 s times the load factor $CASE_LOAD): $(cat "$d/wt.test")"
  grep -qx 'FAIL \[fxhang\]: timed out after 2 s .*' "$d/wt.test" || fail "the run does not name the case as timed out: $(cat "$d/wt.test")"
  grep -qx 'ok fxquick' "$d/wt.test" && [ -e "$d/quick.ran" ] || fail "the other file's case did not run after the hung one: $(cat "$d/wt.test")"
  got=$(cd "$d/wt.testlog/cases" && find . -type f | sort | tr '\n' ' ')
  [ "$got" = './failed/fxhang ./ok/fxquick ./timedout/fxhang ' ] || fail "the run's log does not name the case as failed and timed out: $got"
  # shellcheck source=/dev/null # suiteprog() alone, from the engine's lib/fulltest.sh
  source <(sed -n '/^suiteprog() {/,/^}/p' "$SRC/lib/fulltest.sh")
  got=$(suiteprog "$d/wt" | jq -c '{cases, timedout}')
  [ "$got" = '{"cases":["fxhang"],"timedout":["fxhang"]}' ] || fail "the run's progress does not name the case as timed out: $got"
}

# #1618. Bugs it catches, each more time for every case of every run: run_case handed the case's keeper (case_keep)
# the functions of every case of every file, 3.5 MB to read, of which it runs one; and the keeper's watcher, ended as
# its case ended, left its sleep running, on Linux the keeper's child (its subreaper), so case_end found that sleep,
# ended it and looked again before the case was reported. A case run by run_case as the runner runs one has its own
# function and the shared ones, and not another case's; as it leaves nothing, its keeper has nothing to end.
t_casekeep() {
  local d=$T/$CASE; mkdir -p "$d/in"
  # What case_end would end, with each one's command as case_end found it.
  ( T=$d/in; CASE=keep_one; case_end() { local k; for k in $(case_left "$1"); do echo "$k $(ps -o args= -p "$k")"; done > "$T/left"; }; run_case ) > "$d/report" 2>&1
  [ "$(cat "$d/in/keep_one.rc" 2>/dev/null)" = 0 ] && [ -e "$d/in/left" ] \
    || fail "the case inside failed, or did not end through its keeper: $(cat "$d/report")"
  [ ! -s "$d/in/left" ] || fail "a case that left nothing left its keeper processes to end: $(cat "$d/in/left")"
}
# The case inside t_casekeep: it leaves nothing, and fails when it lacks its own function or a shared one (fail(),
# case_left()), or has t_casetimeout, another case's.
t_keep_one() {
  declare -F t_keep_one fail case_left > /dev/null || { echo "FAIL: its own function or a shared one is missing"; exit 1; }
  ! declare -F t_casetimeout > /dev/null || { echo "FAIL: it was given t_casetimeout, another case's function"; exit 1; }
}

# keepstuck <dir>: the fixture of the two cases below (#1671), started in the background ($! its pid). run_case runs
# t_keep_one, which passes, as the runner runs a case, with a limit of 1 s. Its keeper's end runs the real case_end,
# notes whether the keeper's guard still runs after it ($T/guard.live), and then waits on a subshell of the keeper's
# own that ignores TERM and never ends (it waits on a FIFO, where the one seen spun: KILL alone ends either; its pid in
# $T/hold.pid). The worker that ran run_case wrote its pid (worker.pid) and, ended, its exit status (worker.rc).
keepstuck() {
  local d=$1
  mkdir -p "$d/in" && mkfifo "$d/in/hold" || fail "the fixture could not be made"
  # shellcheck disable=SC2034,SC2154 # CASE_LIMITS is read by run_case, guard is case_keep's (lib.sh)
  ( ( T=$d/in; CASE=keep_one; CASE_LOAD=1; declare -gA CASE_LIMITS=([keep_one]=1); echo "$BASHPID" > "$T/worker.pid"
      # shellcheck source=/dev/null # the real case_end (lib.sh), named case_end_real
      source <(declare -f case_end | sed '1s/^case_end /case_end_real /')
      case_end() { case_end_real "$@"; ps -o stat= -p "${guard:-0}" | grep -qv '^Z' && : > "$T/guard.live"
        : "$(trap '' TERM; echo "$BASHPID" > "$T/hold.pid"; read -r <> "$T/hold")"; }
      run_case ) > "$d/report" 2>&1; echo $? > "$d/in/worker.rc" ) &
}

# Bug it catches (#1671): a subshell of a case's keeper that did not end, and ignored TERM, held the run of a case
# that had passed for 17 minutes. With the keeper held so (keepstuck), the case's run ends within its limit and the
# 3 s grace (the ceiling below allows for a busy machine), the case still passes, its output names the keeper's end,
# and the subshell is gone. Also: the keeper's real case_end left its guard running, not taking it for a process the
# case left.
t_casekeepstuck() {
  local d=$T/$CASE r h
  keepstuck "$d"; r=$!
  WAIT_CEILING=$(loadlimit 15) wait_until '[ -s "$d/in/worker.rc" ]' || wait_end "$r"
  [ -e "$d/in/guard.live" ] || fail "the keeper's guard did not run after the keeper's real case_end, which ended it: $(cat "$d/report")"
  [ -s "$d/in/worker.rc" ] || fail "the run of a case whose keeper's subshell does not end did not go on: $(cat "$d/report")"
  [ "$(cat "$d/in/keep_one.rc" 2>/dev/null)" = 0 ] && grep -qx 'ok keep_one' "$d/report" \
    || fail "the case that passed was not reported as passed: $(cat "$d/report")"
  grep -qxF "note [keep_one]: the case's keeper had not ended 4 s after the case ended (its time limit and 3 s); it and its subshells were killed" "$d/report" \
    || fail "the run does not say the case's keeper was killed: $(cat "$d/report")"
  h=$(cat "$d/in/hold.pid" 2>/dev/null) && [ -n "$h" ] || fail "the keeper's subshell did not start: $(cat "$d/report")"
  ! ps -o stat= -p "$h" | grep -qv '^Z' || fail "the keeper's subshell that ignores TERM, pid $h, still runs: $(ps -o pid=,stat=,args= -p "$h")"
}
# Bug it catches (#1671): the runner, told to end, tells the case's keeper's whole group to and waits for the keeper
# (run_case); the keeper's guard, in that group, ended on that TERM, so the runner waited for ever on a keeper whose
# subshell ignores TERM. The worker that runs the case is told to end once that subshell holds the keeper
# (keepstuck: its pid written, the guard started before it): the worker still ends as told (143), the guard having
# killed the keeper and the subshell, and the case's output names the keeper's end.
t_casekeepstop() {
  local d=$T/$CASE r h
  keepstuck "$d"; r=$!
  wait_until '[ -s "$d/in/hold.pid" ]' || { wait_end "$r"; fail "the keeper's subshell did not start: $(cat "$d/report")"; }
  h=$(cat "$d/in/hold.pid"); kill -TERM "$(cat "$d/in/worker.pid")"
  WAIT_CEILING=$(loadlimit 15) wait_until '[ -s "$d/in/worker.rc" ]' \
    || { wait_end "$r"; fail "the runner told to end waited for the keeper whose subshell does not end: $(cat "$d/report" "$d/in/keep_one.out")"; }
  [ "$(cat "$d/in/worker.rc")" = 143 ] || fail "the worker told to end did not end as told (exit $(cat "$d/in/worker.rc")): $(cat "$d/report")"
  grep -qxF "note [keep_one]: the case's keeper had not ended 4 s after the case ended (its time limit and 3 s); it and its subshells were killed" "$d/in/keep_one.out" \
    || fail "the case's output does not say the case's keeper was killed: $(cat "$d/in/keep_one.out")"
  ! ps -o stat= -p "$h" | grep -qv '^Z' || fail "the keeper's subshell that ignores TERM, pid $h, still runs: $(ps -o pid=,stat=,args= -p "$h")"
}

# Bug it catches (#1084): on a busy machine a case 1.5 times past its file's limit failed the run, though it only ran
# slower. The runner itself runs, as in t_casetimeout: the limit under test is the runner's own keeper's, which no
# call of one function shows. With the load factor 2 a full run gives it (CONVEYOR_LOAD_FACTOR) and two slots, a case
# that takes 3 s of its file's 2 s passes; one that would take 8 s is stopped at 4 s, and its failure gives the
# file's 2 s and the factor.
t_caseload() {
  local d=$T/$CASE s f rc
  s=$d/src; mkdir -p "$s/tests" || fail "the fixture could not be made"
  export XDG_CONFIG_HOME=$d/config
  mkdir -p "$XDG_CONFIG_HOME/conveyor" && echo "{\"testSlots\": 2, \"testSlotsDir\": \"$d/slots\"}" > "$XDG_CONFIG_HOME/conveyor/host.json"
  for f in "$SRC"/*; do [ "${f##*/}" = tests ] || ln -s "$f" "$s/"; done
  ln -s "$SRC/tests/lib.sh" "$SRC/tests/wait.sh" "$SRC/tests/stubs" "$s/tests/"
  printf '%s\n' '# timeout: 2' 't_fxslow() { sleep 3; }' > "$s/tests/slow.test.sh" # sleep: 1.5 times its file's 2 s limit
  printf '%s\n' '# timeout: 2' 't_fxover() { sleep 8; }' > "$s/tests/over.test.sh" # sleep: 4 times its file's 2 s limit
  CONVEYOR_LOAD_FACTOR=2 timeout 60 bash "$s/conveyor.test.sh" > "$d/out" 2>&1; rc=$?
  [ $rc = 1 ] || fail "the run with a case 4 times past its limit did not end failed (exit $rc): $(cat "$d/out")"
  grep -qx 'ok fxslow' "$d/out" || fail "the case 1.5 times past its limit failed at a load factor of 2: $(cat "$d/out")"
  grep -qxF "FAIL [fxover]: timed out after 4 s (its file's # timeout: line, 2 s, times the load factor 2); the case and its process group were stopped" "$d/out" \
    || fail "the case 4 times past its limit is not named as timed out at its scaled limit with the factor: $(cat "$d/out")"
}
