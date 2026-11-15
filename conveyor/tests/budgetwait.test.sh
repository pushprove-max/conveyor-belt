#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the CPU budget's note from tests a card runs while it waits to land (claim.sh settle()), in a whole run
# of two cards. Its own file: with the budget's other cases (budget.test.sh) the file was over the test step's CPU
# budget for one file. The helpers (budgetcmd, reviews, slowof, landedone) are budget.test.sh's.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# The same note from tests a card runs while it waits to land (claim.sh settle()). Bug caught (#459): such a card was
# sent back to its review, holding its files, for a file slowed only by the machine's load. #8 adds a 9 CPU s s.test
# and waits on #7, which holds back until #8's tests found the slow file: #8 is marked tested on that pass, and lands
# with its one review, the file on its test line.
t_budgetwait() {
  batchsetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"; budgetcmd
  echo 'case $PWD in *-7) [ -e "$STUB/held" ] || while [ -d "$STUB" ]; do [ -s ../*-8.slow ] && jq -e .tested ../*-8.ready >/dev/null 2>&1 && { : > "$STUB/held"; exit 0; }; sleep 0.1; done ;; esac' > "$STUB/hold"
  echo 'case $PWD in *-7) sed -i 1s/.*/seven/ a.txt ;; *) echo eight >> a.txt; echo 5 9 > s.test ;; esac' > "$STUB/build"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ "$(reviews 8)" = "GO " ] || fail "#8's slow file sent it back to its review: $(reviews 8): $out"
  [ "$(slowof 8)" = '[{"file":"s.test","sec":5,"cpu":9,"budget":8,"changed":true}]' ] || fail "#8's test line does not note the slow file: $(slowof 8)"
  landedone 8 && landedone 7 || fail "the cards did not land: $out"
}
