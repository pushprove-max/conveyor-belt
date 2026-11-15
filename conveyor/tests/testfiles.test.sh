#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the snapshot's tests part (lib/testfiles.sh testspart()), a test file's own budget and its "slow on
# purpose" mark (testrun.sh slowtests()), and `conveyor.sh test-settings`, which saves them and the project's test
# settings in the pack.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# One passing card test line per run of <file>, a minute apart in order, each timing it at its CPU seconds and at one
# second more of clock time (times, clocks), appended to the card records.
tf_runs() { # <file> <CPU s>...
  jq -cn --arg f "$1" '$ARGS.positional | map(tonumber) | to_entries[] | {card: "c-\($f)-\(.key)", issue: 1, step: "test",
    time: "2026-11-10T12:\(.key | tostring | if length < 2 then "0" + . else . end):00Z", tokens: {claude: 0, codex: 0}, result: "pass",
    sha: "", reason: "", times: {($f): .value}, clocks: {($f): (.value + 1)}}' --args "${@:2}" >> "$ST/cards.jsonl"
}
# The engine's functions, as the script of <command> (conveyor/commands/) loads them, in a shell of the case's main
# ($R): <function> run there, with the 7 days from 2026-11-09. tf_in as the snapshot loads them (testspart), tf_card
# as the loop does a card's test step (slowtests, slowrec).
tf_as() { ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null \
  && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/$1.sh")" && "${@:2}" ); } # <command> <function>...
tf_in() { tf_as snapshot "$@"; }
tf_card() { tf_as run "$@"; }
tf_file() { tf_in testspart 2026-11-09 | jq -c --arg f "$1" "${2:-.}"' as $p | $p.files[] | select(.file == $f)'; } # <file> [jq filter on the part]

# The Tests page compares a file with its own usual time: merge.test.sh went from 25 to 72 CPU s in hours while one
# budget for all files showed nothing. a.test ran at 2, 4, 3 and 10 CPU s: now 10, the median of its 4 runs 3.5, and
# the change (10 - 3.5) / 3.5. Its last run's clock seconds (11) against its CPU seconds; it failed in two test steps
# (a failed file, a time-out in it); two flaky entries are its own (a.testx's is not); its last slow-test issue is #42.
# Bug caught: a part that took the median of the last run alone, or counted another file's failures or flaky entries.
t_tfpart() {
  setup '[]'; tf_runs a.test 2 4 3 10
  { jq -cn '{card: "c-f1", issue: 2, step: "test", time: "2026-11-11T12:00:00Z", result: "fail", failures: {of: 2, files: [{file: "a.test", cases: []}, {file: "b.test", cases: []}], timeout: null}}'
    jq -cn '{card: "c-f2", issue: 2, step: "test", time: "2026-11-11T13:00:00Z", result: "fail", failures: {of: 1, files: [], timeout: {sec: 60, file: "a.test"}}}'
    jq -cn '{card: "c-f3", issue: 2, step: "test", time: "2026-11-11T14:00:00Z", result: "fail", failures: {of: 1, files: [{file: "b.test", cases: []}], timeout: null}}'; } >> "$ST/cards.jsonl"
  echo '{"entries": [{"case": "a.test: one", "source": "s", "time": "2026-11-10T00:00:00Z"}, {"case": "a.test", "source": "t", "time": "2026-11-10T00:00:00Z"},
    {"case": "a.testx: y", "source": "s", "time": "2026-11-10T00:00:00Z"}], "filed": []}' > "$ST/flaky.json"
  echo '{"filed": [{"file": "a.test", "issue": 41}, {"file": "a.test", "issue": 42}, {"file": "b.test", "issue": 43}]}' > "$ST/slow.json"
  got=$(tf_file a.test | jq -c '{cpu, median, change, runs: [.runs[].cpu], lastRun, timedRuns, failedSteps, flaky, issue, budget, budgetFrom, over}')
  [ "$got" = '{"cpu":10,"median":3.5,"change":1.857,"runs":[10,3,4,2],"lastRun":{"sec":11,"cpu":10,"clockPerCpu":1.1},"timedRuns":4,"failedSteps":2,"flaky":2,"issue":42,"budget":8,"budgetFrom":"project","over":true}' ] \
    || fail "a.test's figures: $got"
  # Bug it catches: the issue came from the slow-test record alone, which nothing writes now, so a file the test rules
  # (their log) or the Board's File an issue ($TAFILED) filed for had no issue, and no Close its issue as done.
  printf '%s\n' '{"event": "filed", "file": "a.test", "issue": 44}' '{"event": "stopped", "file": "a.test", "guard": "perDay"}' > "$ST/testrules.jsonl"
  [ "$(tf_file a.test | jq -c .issue)" = 44 ] || fail "a.test's issue is not the one the test rules filed: $(tf_file a.test | jq -c .issue)"
  mkdir -p "$ST/testactions" && printf '%s\n' '{"event": "filed", "file": "a.test", "issue": 45}' '{"event": "filed", "file": "b.test", "issue": 46}' > "$ST/testactions/filed.jsonl"
  [ "$(tf_file a.test | jq -c .issue)" = 45 ] || fail "a.test's issue is not the one the Board filed last: $(tf_file a.test | jq -c .issue)"
  [ "$(tf_file a.test | jq -c '.runs[0] | {card, time}')" = '{"card":"c-a.test-3","time":"2026-11-10T12:03:00Z"}' ] || fail "its newest run: $(tf_file a.test | jq -c .runs)"
}

# The engine's runner names a failed or flaky case as its own (run.test.sh: rone), while the times name the case file
# that ran it (cases/r.test.sh, which defines t_rone): the case counts for its case file. Another file's case (rtwo, in
# cases/q.test.sh) does not, and a step that failed two of its cases counts once. A case file names the runner it runs
# through; solo.test.sh, which runs alone, and o.test.sh, another runner's case file, define a case rone too and get
# none of it; solo.test.sh's own flaky rone is its alone. Bugs caught: every engine case file showed no failed step and no flaky entry, as the records' file names
# did not match; a runner's `setup` failure counted for both tests/setup.test.sh and foreman/foreman.test.sh.
t_tfrunner() {
  setup '[]'; mkdir -p "$R/cases"
  printf '# run.test.sh\nt_rone() {\n  :\n}\nt_rthree() {\n  :\n}\n' > "$R/cases/r.test.sh"; printf '# run.test.sh\nt_rtwo() {\n  :\n}\n' > "$R/cases/q.test.sh"
  printf 't_rone() {\n  :\n}\n' > "$R/cases/solo.test.sh"; printf '# other.test.sh\nt_rone() {\n  :\n}\n' > "$R/cases/o.test.sh"
  git -C "$R" add cases && git -C "$R" commit -qm cases || fail "main's case files"
  tf_runs cases/r.test.sh 2 3; tf_runs cases/q.test.sh 1; tf_runs cases/solo.test.sh 0.5; tf_runs cases/o.test.sh 0.4
  { jq -cn '{card: "c-f1", issue: 2, step: "test", time: "2026-11-11T12:00:00Z", result: "fail", failures: {of: 1, files: [{file: "run.test.sh", cases: [{name: "rone", line: 3}, {name: "rthree", line: 4}]}], timeout: null}}'
    jq -cn '{card: "c-f2", issue: 2, step: "test", time: "2026-11-11T13:00:00Z", result: "fail", failures: {of: 1, files: [{file: "run.test.sh", cases: [{name: "rtwo", line: 3}]}], timeout: null}}'; } >> "$ST/cards.jsonl"
  echo '{"entries": [{"case": "run.test.sh: rone", "source": "s", "time": "2026-11-10T00:00:00Z"}, {"case": "run.test.sh: rtwo", "source": "s", "time": "2026-11-10T00:00:00Z"},
    {"case": "cases/solo.test.sh: rone", "source": "s", "time": "2026-11-10T00:00:00Z"}], "filed": []}' > "$ST/flaky.json"
  got=$(tf_in testspart 2026-11-09 | jq -c '[.files[] | {file, failedSteps, flaky}]')
  [ "$got" = '[{"file":"cases/r.test.sh","failedSteps":1,"flaky":1},{"file":"cases/q.test.sh","failedSteps":1,"flaky":1},{"file":"cases/solo.test.sh","failedSteps":0,"flaky":1},{"file":"cases/o.test.sh","failedSteps":0,"flaky":0}]' ] || fail "the runner's cases: $got"
}

# "Slower than its usual", with the pack's own share (0.5), runs in a row (2) and least runs on record (4), so the
# defaults (0.25, 3, 5) would name another set. s.test: 10, 10, then 16 and 16, over its usual of 10 by more than half
# twice: named. o.test: one run short (10 then 16 at the end). f.test: 3 runs on record, too few. h.test: 14 twice,
# over 10 by 40%, under the share. Bug caught: a usual that is the median of every run, the slow runs among them,
# hides a file whose slow runs are half its record (merge.test.sh's 72 CPU s runs).
t_tfslower() {
  setup '[]'; tune '.test.slower = {share: 0.5, runs: 2, minRuns: 4}'
  tf_runs s.test 10 10 16 16; tf_runs o.test 10 10 10 16; tf_runs f.test 10 16 16; tf_runs h.test 10 10 14 14
  got=$(tf_in testspart 2026-11-09) || fail "testspart failed: $got"
  [ "$(jq -cS '[.slower, .totals.slower, (.files | map({key: .file, value: .slower}) | from_entries)]' <<<"$got")" \
    = '[["s.test"],1,{"f.test":false,"h.test":false,"o.test":false,"s.test":true}]' ] || fail "the files slower than usual: $(jq -c '[.slower, .files]' <<<"$got")"
  [ "$(jq -c '[(.files[] | select(.file == "s.test") | .usual), (.files[] | select(.file == "f.test") | .usual)]' <<<"$got")" = '[10,null]' ] || fail "the usual times: $got"
}

# A project with no recorded file time still has the part (the page shows its step totals, never an error): an empty
# list and the steps of the 7 days, their slot wait and run seconds added up; a step before the 7 days, and one that
# reused a pass (it ran nothing), are not counted. Bug caught: a project with no test line at all had no part (the
# search for test lines found none and failed the part).
t_tfempty() {
  setup '[]'
  got=$(tf_in testspart 2026-11-09) || fail "testspart failed with no test line: $got"
  [ "$(jq -c '[.files, .totals.steps]' <<<"$got")" = '[[],{"count":0,"waitSec":0,"runSec":0}]' ] || fail "the part with no test line: $got"
  { jq -cn '{card: "c-1", issue: 1, step: "test", time: "2026-11-12T12:00:00Z", result: "pass", wait: 3, run: 7}'
    jq -cn '{card: "c-2", issue: 2, step: "test", time: "2026-11-12T13:00:00Z", result: "fail", wait: 1.5, run: 2}'
    jq -cn '{card: "c-3", issue: 3, step: "test", time: "2026-11-12T14:00:00Z", result: "pass", reused: true}'
    jq -cn '{card: "c-0", issue: 4, step: "test", time: "2026-11-01T12:00:00Z", result: "pass", wait: 100, run: 100}'; } >> "$ST/cards.jsonl"
  got=$(tf_in testspart 2026-11-09) || fail "testspart failed: $got"
  [ "$(jq -c '[.files, .slower, .totals]' <<<"$got")" = '[[],[],{"files":0,"overBudget":0,"slower":0,"steps":{"count":2,"waitSec":4.5,"runSec":9}}]' ] \
    || fail "the part with no file time: $got"
}

# A file with its own budget is held to it, not to the project's 5 CPU s, in the slow note (slowtests()) and in the
# part: a.test (own 20) at 10 CPU s is no note; b.test (own 2) at 3 is one, against 2; c.test (none) at 6, against 5.
# The test line the run makes (slowrec()) records each file's clock seconds, which the part reads. Bug caught: a slow
# note on a file allowed more than the project budget, and none on one allowed less.
t_tfownbudget() {
  setup '[]'; tune '.test.fileBudget = 5 | .test.files = {"a.test": {budget: 20}, "b.test": {budget: 2}}'
  mkdir -p "$R.testlog" && printf 'TESTRUN sec\ta.test\t11\t10\nTESTRUN sec\tb.test\t4\t3\nTESTRUN sec\tc.test\t7\t6\n' > "$R.testlog/r.log"
  tf_card slowtests "$R" || fail "slowtests failed"
  [ "$(jq -c 'map({file, budget})' "$R.slow")" = '[{"file":"b.test","budget":2},{"file":"c.test","budget":5}]' ] || fail "the slow note: $(cat "$R.slow")"
  tf_card slowrec "$R" | jq -c '{card: "c-1", issue: 1, step: "test", time: "2026-11-10T12:00:00Z", result: "pass"} + .' >> "$ST/cards.jsonl"
  [ "$(tf_file a.test | jq -c '{budget, budgetFrom, over, lastRun}')" = '{"budget":20,"budgetFrom":"file","over":false,"lastRun":{"sec":11,"cpu":10,"clockPerCpu":1.1}}' ] \
    || fail "a.test in the part: $(tf_file a.test)"
  [ "$(tf_file c.test | jq -c '{budget, budgetFrom, over}')" = '{"budget":5,"budgetFrom":"project","over":true}' ] || fail "c.test in the part: $(tf_file c.test)"
}

# A file marked slow on purpose is in no slow note: m.test at 50 CPU s, over the 8 CPU s budget, with the mark; and
# a CPU test rule never files it (testrules.test.sh). n.test, at 9 with no mark, is one. The part counts
# m.test over budget but not among the files over it that need work (overBudget). Bug caught: a file slow on purpose
# named slow on every card's test line.
t_tfslowmark() {
  setup '[]'; tune '.test.files = {"m.test": {slowOnPurpose: "it starts the whole loop"}}'
  mkdir -p "$R.testlog" && printf 'TESTRUN sec\tm.test\t60\t50\nTESTRUN sec\tn.test\t10\t9\n' > "$R.testlog/r.log"
  tf_card slowtests "$R" || fail "slowtests failed"
  [ "$(jq -c 'map(.file)' "$R.slow")" = '["n.test"]' ] || fail "the slow note: $(cat "$R.slow")"
  tf_card slowrec "$R" | jq -c '{card: "c-1", issue: 1, step: "test", time: "2026-11-10T12:00:00Z", result: "pass"} + .' >> "$ST/cards.jsonl"
  got=$(tf_in testspart 2026-11-09) || fail "testspart failed: $got"
  [ "$(jq -c '[(.files[] | select(.file == "m.test") | {over, slowOnPurpose}), .totals.overBudget]' <<<"$got")" = '[{"over":true,"slowOnPurpose":"it starts the whole loop"},1]' ] \
    || fail "m.test in the part: $got"
}

# The Board saves the test settings through these commands: each saves its value in main's pack, and the next snapshot
# shows it (its tests part's settings). c.test gets both of its own settings and then has both cleared: it leaves the
# pack. Bug caught: a value written somewhere the snapshot does not read, or a clear that left the file's entry.
t_tfsettings() {
  setup '[]'
  touch "$R/a.test" "$R/b.test" "$R/c.test" && git -C "$R" add a.test b.test c.test && git -C "$R" commit -qm tests || fail "main's tests"
  for a in 'budget 12' 'slow-issues true' 'file-budget a.test 20.5' 'file-budget c.test 30' 'slow-mark c.test x' 'file-budget-clear c.test' 'slow-mark-clear c.test'; do
    # shellcheck disable=SC2086 # each is the command's words
    loop test-settings $a > /dev/null || fail "test-settings $a failed"
  done
  loop test-settings slow-mark b.test '  starts a loop of its own  ' || fail "the mark of b.test failed"
  got=$(loop snapshot | jq -c '.tests.settings | {fileBudget, slowIssues, files}')
  [ "$got" = '{"fileBudget":12,"slowIssues":true,"files":{"a.test":{"budget":20.5},"b.test":{"slowOnPurpose":"starts a loop of its own"}}}' ] \
    || fail "the snapshot's settings: $got"
}

# A bad value is refused with why, and the pack is left byte for byte as it was. Bug caught: a mark with no reason
# (blank, or more than one line) saved, which slowtests() then honours, hiding a slow file for no stated reason.
t_tfrefuse() {
  local a before
  setup '[]'
  touch "$R/a.test" && git -C "$R" add a.test && git -C "$R" commit -qm tests || fail "main's tests"
  before=$(cat "$R/.conveyor/project.json")
  for a in 'budget 0' 'budget 0.5' 'budget eight' 'slow-issues yes' 'file-budget a.test -3' 'file-budget gone.test 5' 'file-budget ../a.test 5'; do
    # shellcheck disable=SC2086 # each is the command's words
    out=$(loop test-settings $a 2>&1) && fail "test-settings $a was taken"
    [[ $out == *"nothing changed"* ]] || fail "test-settings $a did not say why: $out"
  done
  for a in '' '   ' $'one\ntwo'; do
    out=$(loop test-settings slow-mark a.test "$a" 2>&1) && fail "the mark with the reason '$a' was taken"
    [[ $out == *"reason"* ]] || fail "the refused mark did not say why: $out"
  done
  loop test-settings slow-mark a.test > /dev/null 2>&1; [ $? = 2 ] || fail "a mark with no reason given was not a usage error"
  [ "$(cat "$R/.conveyor/project.json")" = "$before" ] || fail "a refused value changed the pack"
}
