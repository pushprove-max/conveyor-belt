#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a slow file on main, which a card edits, in whole card runs: its time recorded, and the test rules run
# after its test step (testrun.sh slowtests(), card.sh, testrules.sh). Its own file, so that it runs beside
# budget.test.sh's cases. The helpers (budgetsetup, reviews, slowof, timesof, landedone) are budget.test.sh's.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Card #5's test line, of a card that landed, recorded main's s.test at 6 CPU s (times): card #8 edits it to take
# <seconds> and <CPU seconds>. The pack has the old test.fileBudget of 5, which no file is held to now (#349),
# test.slowIssues true, which files nothing now (#519), and the test rules' switch off.
budgetedit() { # <seconds> <CPU seconds>
  budgetsetup '6 6'; tune '.test.fileBudget = 5 | .test.slowIssues = true'
  { jq -cn '{card: "c0-5", issue: 5, step: "test", time: "2026-11-01T00:00:00Z", tokens: {claude: 0, codex: 0}, result: "pass", sha: "", reason: "",
      times: {"s.test": 6}}'; landed 5; } >> "$ST/cards.jsonl"
  echo "echo $1 $2 >> s.test" > "$STUB/build"
  loop run --only 8 1 > /dev/null 2>&1 || fail "run of #8 exited non-zero"
  landedone 8 || fail "#8 did not land"
}
# Bug caught: a slow file on main, which the card edits, held the card, or was flagged over the old budget (#349). Its
# clock time went from 6 s to 9 s (a busy machine), its CPU seconds from 6 to 6.5: #8 lands with one review, its test
# line has no slow note and records the file's time (times). Bug caught too (#429): the engine ran the changed file
# again on main, in a second worktree, only to time it (22 minutes of one card's test step): s.test runs once, in #8's
# worktree. s.test is filed by nothing (#519: the "Slow test" filing of test.slowIssues filed 37 issues in one burst).
# With the test rules' switch on, a rule of the old measure budget matches nothing, and a rule of 2 card runs in a row
# whose clock time is over their CPU seconds files one issue by #7's run, after its test step.
t_budgetkept() {
  local -x WHOLESUITE=true # The old fixture: #8 changes s.test alone, which no test file is linked to, so the per-file fixture runs no test for it.
  budgetedit 9 6.5
  [ "$(reviews 8)" = "GO " ] || fail "an already slow file went to the review: $(reviews 8)"
  [ "$(slowof 8)" = null ] || fail "#8's test line flags the file over a CPU budget: $(slowof 8)"
  [ ! -s "$STUB/filed" ] || fail "test.slowIssues, or a rule with the switch off, still filed: $(cat "$STUB/filed")"
  [ "$(grep -c ' s\.test$' "$STUB/timedruns")" = 1 ] && grep ' s\.test$' "$STUB/timedruns" | grep -q -- '-8 s\.test$' \
    || fail "#8's test step did not run s.test once, in its own worktree: $(cat "$STUB/timedruns")"
  [ "$(st 'select(.step == "test" and .issue == 8) | .times | tojson' | head -n 1)" = '{"s.test":6.5}' ] \
    || fail "#8's test line does not record the CPU seconds of the file it ran: $(st 'select(.step == "test" and .issue == 8) | .times | tojson')"
  [ -z "$(jq -Rn -f "$SRC/jq/check.jq" < "$ST/cards.jsonl")" ] || fail "the record check refuses a line"
  # A card that runs a slow file it does not change only records it; the clock rule files one issue for it, the
  # budget rule, read first, none.
  echo 'echo two >> a.txt' > "$STUB/build"
  tune '.test.rules = {on: true, list: [{name: "over", on: true, measure: "budget", limit: 1, runs: 2, minRuns: 2}, {name: "clock", on: true, measure: "clock", limit: 1, runs: 2, minRuns: 2}]}'
  loop run --only 7 1 > /dev/null 2>&1 || fail "run of #7 exited non-zero"
  [ "$(reviews 7)" = "GO " ] && [ "$(slowof 7)" = null ] && [ "$(timesof 7)" = '[{"s.test":6.5},null]' ] \
    || fail "a slow file #7 did not change is a finding, or its time is not recorded: $(reviews 7) $(slowof 7) $(timesof 7)"
  [ "$(jq -r .title "$STUB/filed" 2>&1)" = "Test rule clock: s.test" ] || fail "the card's test step did not run the rules once, or the budget rule matched: $(cat "$STUB/filed" 2>&1)"
}
