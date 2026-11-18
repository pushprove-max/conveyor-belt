#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: doctor over a pack that still holds the CPU budget settings no test file has now (#349). Its own file,
# to keep setup.test.sh under the 600 lines a case file may have. The helpers (doctordone, sample) are setup.test.sh's.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# A pack that still holds the budget settings (test.fileBudget, a file's own budget, a test rule of the measure budget)
# still reads, and doctor names them all on one line as ignored. Bugs: the pack check refuses the old settings, so
# every engine command fails; doctor says nothing of them, or one line for each.
t_doctorbudget() {
  local X out; doctordone
  jq '.test.fileBudget = 8 | .test.files = {"t/a.test.sh": {budget: 12}} | .test.rules.list = [{name: "Over", on: true, measure: "budget", limit: 2, runs: 2, minRuns: 2}]' \
    "$S/.conveyor/project.json" > "$T/$CASE/p" && mv "$T/$CASE/p" "$S/.conveyor/project.json"
  out=$(cd "$S" && bash "$X" doctor 2>&1) || fail "doctor failed over a pack that holds the old budget settings: $out"
  [ "$(grep -c 'CPU budget' <<<"$out")" = 1 ] \
    && grep -qxF "note: no test file has a CPU budget, so the pack's budget settings are ignored: test.fileBudget, test.files.t/a.test.sh.budget, the test rule Over; take them out of $S/.conveyor/project.json" <<<"$out" \
    || fail "doctor did not name the ignored budget settings once, on one line: $out"
}
