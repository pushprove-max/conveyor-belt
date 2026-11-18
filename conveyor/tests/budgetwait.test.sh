#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the times from tests a card runs while it waits to land (claim.sh settle()), in a whole run of two
# cards. Its own file, so that it runs beside budget.test.sh's cases. The helpers (budgetcmd, reviews, slowof, timesof,
# landedone) are budget.test.sh's.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# The times from tests a card runs while it waits to land (claim.sh settle()). Bug caught (#459): such a card was
# sent back to its review, holding its files, for a file slowed only by the machine's load. #8 adds a 9 CPU s s.test
# and waits on #7, which holds back until #8's tests timed it: #8 is marked tested on that pass, and lands with its one
# review, the file's times on its test line and no slow note (#349).
t_budgetwait() {
  batchsetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"; budgetcmd
  echo 'case $PWD in *-7) [ -e "$STUB/held" ] || while [ -d "$STUB" ]; do [ -s ../*-8.cpus ] && jq -e .tested ../*-8.ready >/dev/null 2>&1 && { : > "$STUB/held"; exit 0; }; sleep 0.1; done ;; esac' > "$STUB/hold"
  echo 'case $PWD in *-7) sed -i 1s/.*/seven/ a.txt ;; *) echo eight >> a.txt; echo 5 9 > s.test ;; esac' > "$STUB/build"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  [ "$(reviews 8)" = "GO " ] || fail "#8's slow file sent it back to its review: $(reviews 8): $out"
  [ "$(slowof 8)" = null ] && [ "$(timesof 8)" = '[{"s.test":9},[{"file":"s.test","sec":5,"cpu":9}]]' ] \
    || fail "#8's test line flags the file over a CPU budget, or does not record its times: $(slowof 8) $(timesof 8)"
  landedone 8 && landedone 7 || fail "the cards did not land: $out"
}
