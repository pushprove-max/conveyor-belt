#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the engine's own runner's part in how far a running test run has got (../conveyor.test.sh, lib.sh
# run_case). Its own file, apart from testcount.test.sh's live record and snapshot cases: together they were over the
# test step's CPU budget for one file.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# The engine's own runner gives the loop its count: run on two chosen cases (the probes below, one made to fail) in a
# loop's test log folder, it prints `TESTRUN cases=2` and names each case as it ends, in cases/ok or cases/failed, with
# no running mark left. A runner that printed no count left its card's track.tests null; one that wrote no records
# counted 0 done for ever.
t_testcountrunner() {
  local d=$T/$CASE
  export XDG_CONFIG_HOME=$d/config
  mkdir -p "$d/log" "$XDG_CONFIG_HOME/conveyor" && echo "{\"testSlots\": 2, \"testSlotsDir\": \"$d/slots\"}" > "$XDG_CONFIG_HOME/conveyor/host.json"
  CONVEYOR_TESTCOUNT_PROBE=1 CONVEYOR_TEST_LOG=$d/log CONVEYOR_SHELL_TEST_CASE='testcountok testcountbad' timeout 120 bash "$SRC/conveyor.test.sh" > "$d/run.out" 2>&1 \
    && fail "a run with a failing case passed: $(cat "$d/run.out")"
  grep -qx 'TESTRUN cases=2' "$d/run.out" || fail "the runner did not print its case count: $(cat "$d/run.out")"
  [ "$(cd "$d/log/cases" && find . -type f | sort | tr '\n' ' ')" = './failed/testcountbad ./ok/testcountok ' ] \
    || fail "the cases ended are not named as passed and failed: $(cd "$d/log/cases" && find . | sort | tr '\n' ' ')"
}
# The probes the case above runs: they pass in any other run.
t_testcountok() { :; }
t_testcountbad() { [ -z "${CONVEYOR_TESTCOUNT_PROBE:-}" ] || fail "made to fail, for testcountrunner"; }

# A case that runs a case of its own (run_case, as t_machineleft does, its inner case made to fail) is one case of a
# loop's test run: the inner one was named in the run's records too, one more done and failed than were selected. A
# case run as the runner runs each (run_case, with the loop's test log folder), whose own inner case fails, is named
# alone, as passed. Apart from t_testcountrunner, whose runner ran it as a probe: the inner case's keeper made that
# run the file's longest.
t_testcountinner() {
  local d=$T/$CASE
  mkdir -p "$d/log"
  t_testcount_outer() { # no case of the runner's (no t_ name has a _), nor is the one it runs
    mkdir -p "$T/testcountinner/in"; ( T=$T/testcountinner/in; CASE=testcount_inner; run_case ) > /dev/null 2>&1
    [ "$(cat "$T/testcountinner/in/testcount_inner.rc")" = 1 ] || fail "the case inside did not run and fail"
  }
  t_testcount_inner() { exit 1; }
  ( export CONVEYOR_TEST_LOG=$d/log; CASE=testcount_outer; run_case ) > "$d/out" 2>&1
  grep -qx 'ok testcount_outer' "$d/out" || fail "the case that ran a case of its own did not pass: $(cat "$d/out")"
  [ "$(cd "$d/log/cases" && find . -type f | sort | tr '\n' ' ')" = './ok/testcount_outer ' ] \
    || fail "a case run inside a case is named in the run's records: $(cd "$d/log/cases" && find . | sort | tr '\n' ' ')"
}

# Bug (#35): releaserun.test.sh defined reusesetup(), the name of batchreuse.test.sh's fixture. The runner loads every
# case file into one shell, so the later definition replaced the batch one, and four batchreuse cases failed on main.
# tools/fnclash.sh fails on a fixture of two case files that both define helperx(), and names both files and helperx;
# a definition inside a heredoc (a script a case writes) is not one. The files the runner loads pass it.
t_casefnclash() {
  local d=$T/$CASE/fx out
  mkdir -p "$d" || fail "the fixture could not be made"
  printf '%s\n' 'helperx() { :; }' 't_one() { helperx; }' "cat > x <<'EOF'" 'only() { :; }' 'EOF' > "$d/one.test.sh"
  printf '%s\n' 'helperx() { echo two; }' 'only2() { :; }' 'cat > y <<-EOF' 'only() { :; }' '	EOF' 'only2x() { :; }' > "$d/two.test.sh"
  out=$(bash "$SRC/tools/fnclash.sh" "$d/one.test.sh" "$d/two.test.sh" 2>&1); [ $? = 1 ] && [ "$out" = "helperx: one.test.sh two.test.sh" ] \
    || fail "two case files that both define helperx() were not named as a clash: $out"
  out=$(bash "$SRC/tools/fnclash.sh" "$SRC/tests/lib.sh" "$SRC"/tests/*.test.sh 2>&1) || fail "two files the runner loads define one function: $out"
}
