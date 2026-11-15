#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# Engine cases: the timing helper a project wraps each test file's run with (tools/testtime.sh), so its cards record
# test times (conveyor/README.md, The CPU budget of a test file).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bugs caught: a wrapped run that fails passes (the helper's own exit code), or loses the test's output, so a project
# that wraps its files breaks its test step; the CPU seconds are the helper's own `times` read in a subshell, always
# 0, so no file is ever over the budget. A command that prints to both streams, burns about 0.25 CPU s in a child and
# exits 3: the same exit code and text as the command alone, then one `TESTRUN sec` line, its CPU seconds measured.
t_testtime() {
  local d=$T/$CASE rc; mkdir -p "$d"
  local cmd='echo "line one"; echo "to stderr" >&2; i=0; while [ $i -lt 80000 ]; do i=$((i + 1)); done; exit 3'
  "$SRC/tools/testtime.sh" 'tests/a b.test' -- sh -c "$cmd" > "$d/out" 2> "$d/err"; rc=$?
  [ $rc = 3 ] || fail "the helper exited $rc, not the command's 3"
  [ "$(cat "$d/err")" = "to stderr" ] || fail "the command's stderr changed: $(cat "$d/err")"
  [ "$(head -n 1 "$d/out")" = "line one" ] && [ "$(wc -l < "$d/out")" = 2 ] || fail "the command's output changed: $(cat "$d/out")"
  [ "$(grep -c '^TESTRUN sec' "$d/out")" = 1 ] || fail "not one TESTRUN sec line: $(cat "$d/out")"
  # The line ends the output, after the command's.
  tail -n 1 "$d/out" | awk -F'\t' 'NF == 4 && $1 == "TESTRUN sec" && $2 == "tests/a b.test" && $3 ~ /^[0-9]+\.[0-9]$/ && $4 ~ /^[0-9]+\.[0-9]$/ &&
    $4 >= 0.1 && $3 >= $4 - 0.1 { ok = 1 } END { exit !ok }' || fail "the TESTRUN sec line has no clock and CPU seconds of the command: $(tail -n 1 "$d/out")"
}
