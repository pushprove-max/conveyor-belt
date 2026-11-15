#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a file already over the CPU budget on main, which a card edits, in whole card runs: its before from the
# records, and the test rules run after its test step (testrun.sh slowtests(), card.sh, testrules.sh). Its own file:
# with the budget's other cases (budget.test.sh) the file was over the test step's CPU budget for one file. The helpers
# (budgetsetup, reviews, slowof, landedone) are budget.test.sh's.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Card #5's test line, of a card that landed, recorded main's s.test at 6 CPU s (times), over a 5 CPU s budget: card #8
# edits it to take <seconds> and <CPU seconds>. Main's time of it is #5's record (beforetimes()). The pack has
# test.slowIssues true, which files nothing now (#519), and the test rules' switch off.
budgetedit() { # <seconds> <CPU seconds>
  budgetsetup '6 6'; tune '.test.fileBudget = 5 | .test.slowIssues = true'
  { jq -cn '{card: "c0-5", issue: 5, step: "test", time: "2026-11-01T00:00:00Z", tokens: {claude: 0, codex: 0}, result: "pass", sha: "", reason: "",
      times: {"s.test": 6}}'; landed 5; } >> "$ST/cards.jsonl"
  echo "echo $1 $2 >> s.test" > "$STUB/build"
  loop run --only 8 1 > /dev/null 2>&1 || fail "run of #8 exited non-zero"
  landedone 8 || fail "#8 did not land"
}
# Bug caught: a file already over the budget on main, which the card edits, held the card. Its clock time went from 6 s
# to 9 s (a busy machine), its CPU seconds from 6 to 6.5: a note on #8's test line, with main's 6 (before). Bug caught
# too (#429): the check ran the changed file again on main, in a second worktree, only to time it (22 minutes of one
# card's test step): s.test runs once, in #8's worktree, and #8's test line records its time for the next card run's
# check (times). Over the budget in #5's run and #8's, two card runs in a row, s.test is filed by nothing (#519: the
# "Slow test" filing of test.slowIssues filed 37 issues in one burst). With the test rules' switch on and a rule of 2
# card runs in a row over the budget, #7's run (the third over) files one issue by that rule, after its test step.
t_budgetkept() {
  budgetedit 9 6.5
  [ "$(reviews 8)" = "GO " ] || fail "an already slow file went to the review: $(reviews 8)"
  [ "$(slowof 8)" = '[{"file":"s.test","sec":9,"cpu":6.5,"budget":5,"changed":true,"before":6,"from":"card #5, 2026-11-01"}]' ] || fail "#8's test line: $(slowof 8)"
  [ ! -s "$STUB/filed" ] || fail "test.slowIssues, or a rule with the switch off, still filed: $(cat "$STUB/filed")"
  [ "$(grep -c ' s\.test$' "$STUB/timedruns")" = 1 ] && grep ' s\.test$' "$STUB/timedruns" | grep -q -- '-8 s\.test$' \
    || fail "#8's test step did not run s.test once, in its own worktree: $(cat "$STUB/timedruns")"
  [ "$(st 'select(.step == "test" and .issue == 8) | .times | tojson' | head -n 1)" = '{"s.test":6.5}' ] \
    || fail "#8's test line does not record the CPU seconds of the file it ran: $(st 'select(.step == "test" and .issue == 8) | .times | tojson')"
  [ -z "$(jq -Rn -f "$SRC/jq/check.jq" < "$ST/cards.jsonl")" ] || fail "the record check refuses a line"
  # A card that runs a slow file it does not change only records it; the rule files one issue for it.
  echo 'echo two >> a.txt' > "$STUB/build"
  tune '.test.rules = {on: true, list: [{name: "over", on: true, measure: "budget", limit: 1, runs: 2, minRuns: 2}]}'
  loop run --only 7 1 > /dev/null 2>&1 || fail "run of #7 exited non-zero"
  [ "$(reviews 7)" = "GO " ] && [ "$(slowof 7)" = '[{"file":"s.test","sec":9,"cpu":6.5,"budget":5,"changed":false}]' ] \
    || fail "a slow file #7 did not change is a finding, or its time is not recorded: $(reviews 7) $(slowof 7)"
  [ "$(jq -r .title "$STUB/filed" 2>&1)" = "Test rule over: s.test" ] || fail "the card's test step did not run the rules once: $(cat "$STUB/filed" 2>&1)"
}
