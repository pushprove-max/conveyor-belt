#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the times of the test files a card's run timed (testlist.sh slowtests(), card.sh) are recorded on its
# test line and shown, and no file is held to a CPU budget (#349); only a test rule files an issue about a test file
# (testrules.test.sh). Its cases of whole card runs are split, so that they run side by side: budgetrun.test.sh
# and budgetkept.test.sh, which use this file's helpers.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# A test command that, in a worktree, times each <name>.test at the clock and CPU seconds its last line holds
# (`<sec> <cpu>`), as a runner does in its log (`TESTRUN sec`): the time is the file's own, so main's s.test and a
# card's edit of it time apart. Each file it runs is noted in $STUB/timedruns, `<folder> <file>`. It runs as the card's
# one given file (a.test.sh, through test.fileCommand), so its log has no `== <file>` or `-- ok <file>` line of a .test:
# with one, the run reports a file it was not given, and the engine stops it as a wide run (watch(), lib/session.sh).
budgetcmd() { echo 'for f in *.test; do [ ! -f "$f" ] || { echo "$PWD $f" >> "$STUB/timedruns"; printf "TESTRUN sec\t%s\t%s\t%s\n" "$f" $(tail -n 1 "$f") >> "$CONVEYOR_TEST_LOG/r.log"; }; done' >> "$STUB/test-cmd"; }
# Issues 7 and 8, every review a GO. With '<main seconds> <main CPU seconds>', main has s.test of those, before any card.
budgetsetup() { # [main seconds and CPU seconds]
  setup "$(jq -cs . <(issue 7 2026-01-01) <(issue 8 2026-01-02))"
  for i in 1 2 3 4; do echo "$GO" > "$STUB/review.$i"; done
  [ -z "${1:-}" ] || { echo "$1" > "$R/s.test"; git -C "$R" add s.test; git -C "$R" commit -qm s; git -C "$R" push -q origin main; }
  budgetcmd
}
reviews() { st "select(.step == \"review\" and .issue == $1) | .result" | tr '\n' ' '; } # <issue>
slowof() { st "select(.step == \"test\" and .issue == $1) | .slow | tojson" | head -n 1; } # <issue>: its first test line's slow
timesof() { st "select(.step == \"test\" and .issue == $1) | [.times, .timed] | tojson" | head -n 1; } # <issue>: its first test line's times
landedone() { [ "$(st "select(.step == \"landed\" and .issue == $1) | .issue")" = "$1" ]; } # <issue>

# #349: no test file has a CPU budget. Bugs caught: a card that adds a test file burning 10 CPU s (10.2 s clock), with
# the pack's old test.fileBudget of 8 still in it, has the file flagged over budget on its test line (slow) and on the
# Board's Tests bar of the card, or its times are not recorded. It lands on its one passing run, with one review and
# one test step, nothing filed, and its test line holds the file's times (times, timed) and no slow note.
t_budgetover() {
  budgetsetup; tune '.test.fileBudget = 8'; echo 'echo two >> a.txt; echo 10.2 10 > s.test' > "$STUB/build"
  loop run --only 7 1 > /dev/null 2>&1 || fail "run exited non-zero"
  [ "$(st "select(.issue == 7 and $NOMARK) | .step" | tr '\n' ' ')" = "picked worktree brief build review test landed " ] \
    || fail "a slow file sent #7 to another review or test step: $(st "select(.issue == 7 and $NOMARK) | .step" | tr '\n' ' ')"
  [ "$(reviews 7)" = "GO " ] || fail "the review was given the slow file as a finding: $(reviews 7)"
  [ "$(slowof 7)" = null ] || fail "the test line flags the file over a CPU budget: $(slowof 7)"
  [ "$(timesof 7)" = '[{"s.test":10},[{"file":"s.test","sec":10.2,"cpu":10}]]' ] || fail "the test line does not record the file's times: $(timesof 7)"
  [ ! -s "$STUB/filed" ] || fail "a file slow in one card run was reported: $(cat "$STUB/filed")"
  [ -z "$(jq -Rn -f "$SRC/jq/check.jq" < "$ST/cards.jsonl")" ] || fail "the record check refuses a line"
  landedone 7 || fail "the card did not land"
  # The Board's Tests bar of the card (jq/rows.jq, jq/track.jq) carries no slow note.
  [ "$(loop snapshot --fresh | jq -c '[.landed[0].track.records[] | select(.name == "tests passed") | has("slow")]')" = '[false]' ] \
    || fail "the snapshot's track carries a slow note: $(loop snapshot --fresh | jq -c '.landed[0].track.records')"
}

# Bug caught: the engine's runner timed no case file, so an engine case file a card added or slowed had no time on
# record. Each case is timed (run_case), and a case file is timed only when the run ran its every case: the sum of
# their times. Bug caught too: no case's CPU seconds were measured, so a case file's were
# not known. The probe case burns CPU in the process the case runs in: run_case's measure of it is that CPU, its
# children's times after the case less those before (`times`, in either locale's point).
t_budgetcasetimes() {
  local d=$T/$CASE i
  mkdir -p "$d/in"
  t_budget_probe() { local i=0; while [ $i -lt 100000 ]; do i=$((i + 1)); done; } # no case of the runner's (no t_ name has a _)
  ( T=$d/in; CASE=budget_probe; run_case ) > /dev/null 2>&1
  [[ $(cat "$d/in/budget_probe.sec" 2>/dev/null) =~ ^[0-9]+$ ]] || fail "run_case did not time its case: $(cat "$d/in/budget_probe.sec" 2>&1)"
  CASE_CPU=''; case_cpu "$d/in/budget_probe.cpu" && [ "$CASE_CPU" -ge 50 ] && [ "$CASE_CPU" -le $(( $(cat "$d/in/budget_probe.sec") / 1000 + 50 )) ] \
    || fail "run_case did not measure its case's CPU: '$CASE_CPU' ms: $(cat "$d/in/budget_probe.cpu" 2>&1)"
  printf 't_one() {\n}\nt_two() {\n}\n' > "$d/x.test.sh"; printf 't_one() {\n}\nt_three() {\n}\n' > "$d/y.test.sh"
  echo 2500000 > "$d/one.sec"; echo 3000000 > "$d/two.sec"; echo 1000000 > "$d/three.sec"
  for i in one three; do printf '0m0.010s 0m0.000s\n0m1.000s 0m0.500s\n0m0.010s 0m0.000s\n0m3.250s 0m0.750s\n' > "$d/$i.cpu"; done
  printf '0m0,000s 0m0,000s\n0m0,000s 0m0,000s\n0m0,000s 0m0,000s\n1m0,100s 0m0,000s\n' > "$d/two.cpu"
  got=$(T=$d SEL='one two' case_times "$d/x.test.sh" "$d/y.test.sh")
  [ "$got" = "x.test.sh	5.5	62.6" ] || fail "the case files' times: '$got', want x.test.sh alone, its two cases' 5.5 s and 62.6 CPU s"
}
