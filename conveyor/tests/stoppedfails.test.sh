#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# Engine cases: the files a failed test line counts for (failedfiles and failedrun, OWNERS and FAILURE in
# lib/testfiles.sh: the Tests page and testcap() read them) when a time-out stopped files side by side.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# The files <test line> counts for, as failedrun | failedfiles read it, with no case defined anywhere.
sf_files() { # <test line>
  bash -c '. "$1/lib/testfiles.sh" 2>/dev/null; jq -c --slurpfile defs <(echo "{}") --slurpfile refs <(echo "{}") "$OWNERS$FAILURE failedrun | failedfiles" <<<"$2"' _ "$SRC" "$1"
}

# Bug it catches: a time-out of three files side by side (testfails(): stopped names all three, timeout only the last)
# counted for c.test.sh alone, so the Tests page and testcap() missed a.test.sh, which its own limit stopped (ownLimit).
# b.test.sh was only stopped beside them by the run's limit: it did not end, so it did not fail and does not count.
t_sfownlimit() {
  local l='{"step": "test", "result": "fail", "failures": {"files": [], "timeout": {"sec": 2, "file": "c.test.sh"}, "stopped": ["a.test.sh", "b.test.sh", "c.test.sh"], "ownLimit": ["a.test.sh"]}}' got
  got=$(sf_files "$l")
  [ "$got" = '["a.test.sh","c.test.sh"]' ] || fail "the files of a time-out where a.test.sh ran past its own limit and b.test.sh was only stopped, of the line $l: $got"
}

# Bug it catches: the same time-out in a first run (rerun), merged into a line that failed again in z.test.sh, counted
# for c.test.sh and z.test.sh alone; the file only stopped beside them still does not count.
t_sfownlimitfirst() {
  local l='{"step": "test", "result": "fail", "failures": {"files": [{"file": "z.test.sh", "cases": [{"name": "x"}]}], "timeout": null},
    "rerun": {"exit": 124, "failures": {"files": [], "timeout": {"sec": 2, "file": "c.test.sh"}, "stopped": ["a.test.sh", "b.test.sh", "c.test.sh"], "ownLimit": ["a.test.sh"]}}}' got
  got=$(sf_files "$l")
  [ "$got" = '["a.test.sh","c.test.sh","z.test.sh"]' ] || fail "the files of a first run's time-out where a.test.sh ran past its own limit and b.test.sh was only stopped, of the line $l: $got"
}
