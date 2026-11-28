#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the flaky-test record (lib/flaky.sh) of a card whose run again still fails, in a whole card run with
# its fix session. Its own file: with the record's other cases (flaky.test.sh) it was over the test step's CPU budget
# for one file.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# A run again that still fails: the case that failed again is a failure, as before, and no rerun entry (passing on main
# in a file the card does not change, it is a sighting: flakycard()); the case that passed
# in it is flaky, an entry, as a pass on re-run's is (the owner, 2026-11-14: every failure's verdict is the card's,
# main's or flaky).
t_flakyrerunfail() {
  rerunsetup '1 fail flaky' '1 fail three' '2 fail flaky'; rerunfiles
  loop run 1 > /dev/null || fail "run exited non-zero"
  [ "$(st 'select((.step == "test" and .before == null) or .step == "fix") | "\(.step) \(.result)"' | tr '\n' ,)" = "test fail,fix ok,test pass," ] \
    || fail "a case that failed on the run and the re-run was not handled as a failure: $(st 'select((.step == "test" and .before == null) or .step == "fix") | "\(.step) \(.result)"' | tr '\n' ,)"
  # The case that passed in the run again is a flaky entry with no note; the case that failed both runs is the card's,
  # and, as b.test is a file the card does not change and it passed on main, one sighting with its note (issue 1829).
  [ "$(fl '[.entries[] | "\(.case) \(.note != null)"] | sort | join("|")')" = "b.test: flaky true|c.test: three false" ] \
    || fail "not one entry for the case that passed in the failed run again and one sighting for the card case that passed on main: $(cat "$ST/flaky.json")"
  [ "$(tline 1 '.verdicts | map("\(.case) \(.verdict)") | join("|")')" = "c.test: three flaky|b.test: flaky card" ] \
    || fail "the failed test line does not give each failure's verdict: $(tline 1 .verdicts)"
}
