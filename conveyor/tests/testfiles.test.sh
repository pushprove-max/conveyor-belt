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

# The Tests page compares a file with its own usual time: merge.test.sh went from 25 to 72 CPU s in hours while one
# budget for all files showed nothing. a.test ran at 2, 4, 3 and 10 CPU s: now 10, the median of its 4 runs 3.5, and
# the change (10 - 3.5) / 3.5. Its last run's clock seconds (11) against its CPU seconds; it failed in two test steps
# (a failed file, a time-out in it); two flaky entries are its own (a.testx's is not); its last slow-test issue is #42.
# Bug caught: a part that took the median of the last run alone, or counted another file's failures or flaky entries.
# Each file's issue is the newest filed for it: a.test's from the slow-test record alone; b.test's #44 from the test
# rules' log (#43 in the slow-test record); c.test's #47 from the Board's File an issue (#46 in the test rules' log);
# d.test's #49 is no other file's. Bug caught: the issue came from the slow-test record alone, which nothing writes now,
# so a file the test rules (their log) or the Board's File an issue ($TAFILED) filed for had no issue, and no Close its
# issue as done.
t_tfpart() {
  setup '[]'; tf_runs a.test 2 4 3 10; tf_runs b.test 1
  { jq -cn '{card: "c-f1", issue: 2, step: "test", time: "2026-11-11T12:00:00Z", result: "fail", failures: {of: 2, files: [{file: "a.test", cases: []}, {file: "b.test", cases: []}], timeout: null}}'
    jq -cn '{card: "c-f2", issue: 2, step: "test", time: "2026-11-11T13:00:00Z", result: "fail", failures: {of: 1, files: [], timeout: {sec: 60, file: "a.test"}}}'
    jq -cn '{card: "c-f3", issue: 2, step: "test", time: "2026-11-11T14:00:00Z", result: "fail", failures: {of: 1, files: [{file: "b.test", cases: []}], timeout: null}}'; } >> "$ST/cards.jsonl"
  echo '{"entries": [{"case": "a.test: one", "source": "s", "time": "2026-11-10T00:00:00Z"}, {"case": "a.test", "source": "t", "time": "2026-11-10T00:00:00Z"},
    {"case": "a.testx: y", "source": "s", "time": "2026-11-10T00:00:00Z"}], "filed": []}' > "$ST/flaky.json"
  echo '{"filed": [{"file": "a.test", "issue": 41}, {"file": "a.test", "issue": 42}, {"file": "b.test", "issue": 43}]}' > "$ST/slow.json"
  printf '%s\n' '{"event": "filed", "file": "b.test", "issue": 44}' '{"event": "stopped", "file": "b.test", "guard": "perDay"}' '{"event": "filed", "file": "c.test", "issue": 46}' > "$ST/testrules.jsonl"
  mkdir -p "$ST/testactions" && printf '%s\n' '{"event": "filed", "file": "c.test", "issue": 47}' '{"event": "filed", "file": "d.test", "issue": 49}' > "$ST/testactions/filed.jsonl"
  got=$(tf_in testspart 2026-11-09) || fail "testspart failed: $got"
  [ "$(jq -c '.files[] | select(.file == "a.test") | {cpu, median, change, runs: [.runs[].cpu], newest: (.runs[0] | {card, time}), lastRun, timedRuns, failedSteps, flaky, issue, budget, budgetFrom, over}' <<<"$got")" \
    = '{"cpu":10,"median":3.5,"change":1.857,"runs":[10,3,4,2],"newest":{"card":"c-a.test-3","time":"2026-11-10T12:03:00Z"},"lastRun":{"sec":11,"cpu":10,"clockPerCpu":1.1,"time":"2026-11-10T12:03:00Z","whole":false},"timedRuns":4,"failedSteps":2,"flaky":2,"issue":42,"budget":8,"budgetFrom":"project","over":true}' ] \
    || fail "a.test's figures: $(jq -c '.files[] | select(.file == "a.test")' <<<"$got")"
  [ "$(jq -cS '.files | map({key: .file, value: .issue}) | from_entries' <<<"$got")" = '{"a.test":42,"b.test":44,"c.test":47,"d.test":49}' ] \
    || fail "each file's issue, the newest filed for it in any record: $(jq -c '[.files[] | {file, issue}]' <<<"$got")"
}

# The engine's runner names a failed or flaky case as its own (run.test.sh: rone), while the times name the case file
# that ran it (cases/r.test.sh, which defines t_rone): the case counts for its case file. Another file's case (rtwo, in
# cases/q.test.sh) does not, and a step that failed two of its cases counts once. A case file names the runner it runs
# through; solo.test.sh, which runs alone, and o.test.sh, another runner's case file, define a case rone too and get
# none of it; solo.test.sh's own flaky rone is its alone. Bugs caught: every engine case file showed no failed step and no flaky entry, as the records' file names
# did not match; a runner's `setup` failure counted for both tests/setup.test.sh and foreman/foreman.test.sh.
# The Tests page lists every test file of main's checkout. c.test.sh ran on a card; w.test.sh, wholeOnly in the pack,
# ran only in a whole-suite run, whose files the run's output names (suiterec(): its `TESTRUN sec` and `-- FAIL` lines);
# n.test.sh never ran. Bug caught: the part was made from card test lines alone, so a whole-only file
# (conveyor/conveyor.test.sh) and a file never run were missing, and no whole-suite run reached the page.
t_tfrunner() {
  setup '[]'; mkdir -p "$R/cases"; tune '.test.files = {"w.test.sh": {wholeOnly: true}}'
  printf '# run.test.sh\nt_rone() {\n  :\n}\nt_rthree() {\n  :\n}\n' > "$R/cases/r.test.sh"; printf '# run.test.sh\nt_rtwo() {\n  :\n}\n' > "$R/cases/q.test.sh"
  printf 't_rone() {\n  :\n}\n' > "$R/cases/solo.test.sh"; printf '# other.test.sh\nt_rone() {\n  :\n}\n' > "$R/cases/o.test.sh"
  touch "$R/c.test.sh" "$R/w.test.sh" "$R/n.test.sh"
  git -C "$R" add cases c.test.sh w.test.sh n.test.sh && git -C "$R" commit -qm tests || fail "main's test files"
  tf_runs cases/r.test.sh 2 3; tf_runs cases/q.test.sh 1; tf_runs cases/solo.test.sh 0.5; tf_runs cases/o.test.sh 0.4; tf_runs c.test.sh 2
  printf 'TESTRUN sec\tw.test.sh\t48\t30.5\n-- FAIL w.test.sh\n' > "$T/$CASE/suite.test"
  CONVEYOR_NOW=1794700800 tf_as full-test suiterec "$T/$CASE/suite" full 0123abcd || fail "suiterec failed"
  { jq -cn '{card: "c-f1", issue: 2, step: "test", time: "2026-11-11T12:00:00Z", result: "fail", failures: {of: 1, files: [{file: "run.test.sh", cases: [{name: "rone", line: 3}, {name: "rthree", line: 4}]}], timeout: null}}'
    jq -cn '{card: "c-f2", issue: 2, step: "test", time: "2026-11-11T13:00:00Z", result: "fail", failures: {of: 1, files: [{file: "run.test.sh", cases: [{name: "rtwo", line: 3}]}], timeout: null}}'; } >> "$ST/cards.jsonl"
  echo '{"entries": [{"case": "run.test.sh: rone", "source": "s", "time": "2026-11-10T00:00:00Z"}, {"case": "run.test.sh: rtwo", "source": "s", "time": "2026-11-10T00:00:00Z"},
    {"case": "cases/solo.test.sh: rone", "source": "s", "time": "2026-11-10T00:00:00Z"}], "filed": []}' > "$ST/flaky.json"
  got=$(tf_in testspart 2026-11-09) || fail "testspart failed: $got"
  [ "$(jq -c '[.files[] | select(.file | startswith("cases/")) | {file, failedSteps, flaky}]' <<<"$got")" = '[{"file":"cases/r.test.sh","failedSteps":1,"flaky":1},{"file":"cases/q.test.sh","failedSteps":1,"flaky":1},{"file":"cases/solo.test.sh","failedSteps":0,"flaky":1},{"file":"cases/o.test.sh","failedSteps":0,"flaky":0}]' ] \
    || fail "the runner's cases: $(jq -c '[.files[] | {file, failedSteps, flaky}]' <<<"$got")"
  got=$(jq -c '[.files[] | select(.file | startswith("cases/") | not) | {file, cpu, wholeOnly, runs: [.runs[] | {card, whole, result, sec, cpu}], last: (.lastRun | if . then {time, whole} else . end)}]' <<<"$got")
  [ "$got" = '[{"file":"w.test.sh","cpu":30.5,"wholeOnly":true,"runs":[{"card":null,"whole":true,"result":"fail","sec":48,"cpu":30.5}],"last":{"time":"2026-11-15T00:00:00Z","whole":true}},'\
'{"file":"c.test.sh","cpu":2,"wholeOnly":false,"runs":[{"card":"c-c.test.sh-0","whole":false,"result":null,"sec":3,"cpu":2}],"last":{"time":"2026-11-10T12:00:00Z","whole":false}},'\
'{"file":"n.test.sh","cpu":null,"wholeOnly":false,"runs":[],"last":null}]' ] || fail "the three files: $got"
}

# "Slower than its usual", with the pack's own share (0.5), runs in a row (2) and least runs on record (4), so the
# defaults (0.25, 3, 5) would name another set. s.test: 10, 10, then 16 and 16, over its usual of 10 by more than half
# twice: named. o.test: one run short (10 then 16 at the end). f.test: 3 runs on record, too few. h.test: 14 twice,
# over 10 by 40%, under the share. Bug caught: a usual that is the median of every run, the slow runs among them,
# hides a file whose slow runs are half its record (merge.test.sh's 72 CPU s runs).
# A runner that starts other test files whole (wholeOnly in the pack) is held to no budget: its CPU is the sum of its
# case files', each timed with its own budget. r.test (wholeOnly) and c.test ran at 10, 10, 900 and 900 CPU s, far
# over the 8 CPU s budget and over their usual: c.test is over budget and slower, r.test neither, with no budget.
# Bug caught: conveyor/conveyor.test.sh showed as over budget and slower than usual forever, as no change can pass.
t_tfslower() {
  setup '[]'; tune '.test.slower = {share: 0.5, runs: 2, minRuns: 4} | .test.files = {"r.test": {wholeOnly: true}}'
  tf_runs s.test 10 10 16 16; tf_runs o.test 10 10 10 16; tf_runs f.test 10 16 16; tf_runs h.test 10 10 14 14
  tf_runs r.test 10 10 900 900; tf_runs c.test 10 10 900 900
  got=$(tf_in testspart 2026-11-09) || fail "testspart failed: $got"
  [ "$(jq -cS '[.slower, .totals.slower, (.files | map({key: .file, value: .slower}) | from_entries)]' <<<"$got")" \
    = '[["c.test","s.test"],2,{"c.test":true,"f.test":false,"h.test":false,"o.test":false,"r.test":false,"s.test":true}]' ] || fail "the files slower than usual: $(jq -c '[.slower, .files]' <<<"$got")"
  [ "$(jq -c '[(.files[] | select(.file == "s.test") | .usual), (.files[] | select(.file == "f.test") | .usual)]' <<<"$got")" = '[10,null]' ] || fail "the usual times: $got"
  # Over budget: c.test and the four files at 14 or 16 CPU s, never the wholeOnly runner.
  [ "$(jq -cS '[.totals.overBudget, (.files | map(select(.file | IN("c.test", "r.test")) | {key: .file, value: {budget, budgetFrom, over}}) | from_entries)]' <<<"$got")" \
    = '[5,{"c.test":{"budget":8,"budgetFrom":"project","over":true},"r.test":{"budget":null,"budgetFrom":null,"over":false}}]' ] \
    || fail "the wholeOnly runner: $(jq -c '[.totals, .files]' <<<"$got")"
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
# A file marked slow on purpose is in no slow note: m.test at 50 CPU s, over the budget, with the mark; and a CPU test
# rule never files it (testrules.test.sh). n.test, at 9 with no mark, is one. The part counts m.test over budget but
# not among the files over it that need work (overBudget: b.test, c.test and n.test). Bug caught: a file slow on
# purpose named slow on every card's test line.
t_tfownbudget() {
  setup '[]'; tune '.test.fileBudget = 5 | .test.files = {"a.test": {budget: 20}, "b.test": {budget: 2}, "m.test": {slowOnPurpose: "it starts the whole loop"}}'
  mkdir -p "$R.testlog" && printf 'TESTRUN sec\t%s\t%s\t%s\n' a.test 11 10 b.test 4 3 c.test 7 6 m.test 60 50 n.test 10 9 > "$R.testlog/r.log"
  tf_card slowtests "$R" || fail "slowtests failed"
  [ "$(jq -c 'map({file, budget})' "$R.slow")" = '[{"file":"b.test","budget":2},{"file":"c.test","budget":5},{"file":"n.test","budget":5}]' ] || fail "the slow note: $(cat "$R.slow")"
  tf_card slowrec "$R" | jq -c '{card: "c-1", issue: 1, step: "test", time: "2026-11-10T12:00:00Z", result: "pass"} + .' >> "$ST/cards.jsonl"
  got=$(tf_in testspart 2026-11-09) || fail "testspart failed: $got"
  [ "$(jq -c '.files[] | select(.file == "a.test") | {budget, budgetFrom, over, lastRun}' <<<"$got")" = '{"budget":20,"budgetFrom":"file","over":false,"lastRun":{"sec":11,"cpu":10,"clockPerCpu":1.1,"time":"2026-11-10T12:00:00Z","whole":false}}' ] \
    || fail "a.test in the part: $(jq -c '.files[] | select(.file == "a.test")' <<<"$got")"
  [ "$(jq -c '.files[] | select(.file == "c.test") | {budget, budgetFrom, over}' <<<"$got")" = '{"budget":5,"budgetFrom":"project","over":true}' ] || fail "c.test in the part: $(jq -c '.files[] | select(.file == "c.test")' <<<"$got")"
  [ "$(jq -c '[(.files[] | select(.file == "m.test") | {over, slowOnPurpose}), .totals.overBudget]' <<<"$got")" = '[{"over":true,"slowOnPurpose":"it starts the whole loop"},3]' ] \
    || fail "m.test in the part: $got"
}

# The Board saves the test settings through these commands: each saves its value in main's pack, and the next snapshot
# shows it (its tests part's settings). c.test gets both of its own settings and then has both cleared: it leaves the
# pack. Bug caught: a value written somewhere the snapshot does not read, or a clear that left the file's entry.
# The snapshot holds this part whole (testrules.test.sh reads it there), so the part is read here. Each setting is
# saved by testsettings(), the function `conveyor.sh test-settings` calls; one is saved through the command itself.
# A bad value is refused with why, and the pack is left byte for byte as it was. Bug caught: a mark with no reason
# (blank, or more than one line) saved, which slowtests() then honours, hiding a slow file for no stated reason.
tf_refused() { # the refusals, each checked: in a shell with testsettings() loaded (tf_as test-settings)
  local a out
  for a in 'budget 0' 'budget 0.5' 'budget eight' 'slow-issues yes' 'file-budget a.test -3' 'file-budget gone.test 5' 'file-budget ../a.test 5'; do
    # shellcheck disable=SC2086 # each is the command's words
    out=$(testsettings $a 2>&1) && fail "test-settings $a was taken"
    [[ $out == *"nothing changed"* ]] || fail "test-settings $a did not say why: $out"
  done
  for a in '' '   ' $'one\ntwo'; do
    out=$(testsettings slow-mark a.test "$a" 2>&1) && fail "the mark with the reason '$a' was taken"
    [[ $out == *"reason"* ]] || fail "the refused mark did not say why: $out"
  done
}
tf_saved() { # the settings saved: in a shell with testsettings() loaded (tf_as test-settings)
  local a
  for a in 'budget 12' 'slow-issues true' 'file-budget a.test 20.5' 'file-budget c.test 30' 'slow-mark c.test x' 'file-budget-clear c.test' 'slow-mark-clear c.test'; do
    # shellcheck disable=SC2086 # each is the command's words
    testsettings $a > /dev/null || fail "test-settings $a failed"
  done
}
t_tfsettings() {
  local before
  setup '[]'
  touch "$R/a.test" "$R/b.test" "$R/c.test" && git -C "$R" add a.test b.test c.test && git -C "$R" commit -qm tests || fail "main's tests"
  before=$(cat "$R/.conveyor/project.json")
  tf_as test-settings tf_refused || fail "a bad value was taken"
  loop test-settings slow-mark a.test > /dev/null 2>&1; [ $? = 2 ] || fail "a mark with no reason given was not a usage error"
  [ "$(cat "$R/.conveyor/project.json")" = "$before" ] || fail "a refused value changed the pack"
  tf_as test-settings tf_saved || fail "a setting was not saved"
  loop test-settings slow-mark b.test '  starts a loop of its own  ' || fail "the mark of b.test failed"
  got=$(tf_in testspart 2026-11-09 | jq -c '.settings | {fileBudget, slowIssues, files}')
  [ "$got" = '{"fileBudget":12,"slowIssues":true,"files":{"a.test":{"budget":20.5},"b.test":{"slowOnPurpose":"starts a loop of its own"}}}' ] \
    || fail "the part's settings: $got"
}

# The Tests page shows what each Optimize did (#74). The Board filed #70, #71 and #72 for a.test (main has it) and #73
# for gone.test (main no longer has it). a.test ran at 10, 9, 4 and 3 CPU s; #70's card proved it faster (10 to 4) and
# landed between the 9 and the 4, so its median since is 3.5 over 2 runs; #71 has no card; #72's card is blocked; #73's
# card deleted gone.test and landed, its last review naming b.test and c.test on its COVERED-BY lines, and #74's was
# closed without landing. Bug caught: the part named one issue a file and no state, so the page could not show what an
# Optimize did, nor a file it removed; and a deleted file lost the tests that cover its cases.
t_tfoptimize() {
  setup '[]'
  touch "$R/a.test" && git -C "$R" add a.test && git -C "$R" commit -qm tests || fail "main's tests"
  tf_runs a.test 10 9 4 3
  mkdir -p "$ST/testactions" && jq -cn '[70, 71, 72, 74] | to_entries[] | {time: "2026-11-0\(.key + 1)T00:00:00Z", event: "filed", file: "a.test", issue: .value},
    {time: "2026-11-05T00:00:00Z", event: "filed", file: "gone.test", issue: 73}' > "$ST/testactions/filed.jsonl"
  jq -cn '{card: "c-70", issue: 70, step: "picked", time: "2026-11-10T11:00:00Z"},
    {card: "c-70", issue: 70, step: "bugproof", result: "ok", time: "2026-11-10T11:30:00Z", speed: {file: "a.test", before: 10, after: 4, fix: "sped up", into: []}},
    {card: "c-70", issue: 70, step: "landed", result: "ok", sha: "abc1234", time: "2026-11-10T12:01:30Z"},
    {card: "c-72", issue: 72, step: "picked", time: "2026-11-10T13:00:00Z"},
    {card: "c-72", issue: 72, step: "blocked", reason: "build: the file is not faster", time: "2026-11-10T13:30:00Z"},
    {card: "c-73", issue: 73, step: "bugproof", result: "ok", time: "2026-11-06T00:00:00Z", speed: {file: "gone.test", before: 6, after: null, fix: "deleted", into: []}},
    {card: "c-73", issue: 73, step: "review", result: "NO-GO", time: "2026-11-06T00:20:00Z", reason: "COVERED-BY: old.test: t_one\n[P1] x:1 no"},
    {card: "c-73", issue: 73, step: "review", result: "GO", time: "2026-11-06T00:30:00Z", reason: "COVERED-BY: b.test: t_one\nCOVERED-BY: c.test: t_two\nCOVERED-BY: b.test: t_three\nVERDICT: GO"},
    {card: "c-73", issue: 73, step: "landed", result: "ok", sha: "def5678", time: "2026-11-06T01:00:00Z"},
    {card: "c-74", issue: 74, step: "picked", time: "2026-11-10T14:00:00Z"},
    {card: "c-74", issue: 74, step: "closed", reason: "already done", time: "2026-11-10T14:10:00Z"}' >> "$ST/cards.jsonl"
  # a.test's mutation checks (#79): two done before #70 landed (12:01:30), one done after it and a failed one after
  # that; and the asked list, where a.test is second.
  mkdir -p "$ST/testactions/mutations" && printf '%s\n' s.test a.test > "$ST/testactions/mutations/asked"
  jq -cn '["09T00:00", "done", 1], ["10T12:00", "done", 2], ["10T12:30", "done", 4], ["10T13:00", "failed", 0] | {id: .[0], file: "a.test",
      at: "2026-11-\(.[0]):00Z", state: .[1], killed: .[2], mutants: [range(4)], survived: [], tried: 4}' \
    | while read -r l; do printf '%s\n' "$l" > "$ST/testactions/mutations/$(jq -r '.id | gsub(":"; "")' <<<"$l").json"; done
  got=$(tf_in testspart 2026-11-09) || fail "testspart failed: $got"
  # Bug caught: an Optimize history that could not show the mutants caught before and after it landed, or a row that
  # could not show its place in the queue the Board's Mutation check puts it in.
  [ "$(jq -c '.files[] | select(.file == "a.test") | [.mutationPlace, (.optimize[] | select(.issue == 70 or .issue == 71) | [.issue, .mutantsBefore, .mutantsAfter])]' <<<"$got")" \
    = '[2,[71,null,null],[70,{"at":"2026-11-10T12:00:00Z","killed":2,"of":4},{"at":"2026-11-10T12:30:00Z","killed":4,"of":4}]]' ] \
    || fail "a.test's place in the asked list, or its mutants before and after #70: $(jq -c '.files[] | select(.file == "a.test") | [.mutationPlace, .optimize]' <<<"$got")"
  [ "$(jq -c '.files[] | select(.file == "a.test") | [.removed, (.optimize[] | [.issue, .state, .reason, .sha, .fix, .before, .after, .since, .sinceRuns])]' <<<"$got")" \
    = '[false,[74,"closed",null,null,null,null,null,null,0],[72,"blocked","build: the file is not faster",null,null,null,null,null,0],[71,"open",null,null,null,null,null,null,0],[70,"landed",null,"abc1234","sped up",10,4,3.5,2]]' ] \
    || fail "a.test's Optimize issues: $(jq -c '.files[] | select(.file == "a.test") | .optimize' <<<"$got")"
  [ "$(jq -c '[(.files[] | select(.file == "gone.test") | [.removed, .optimize[0].fix, .optimize[0].landed, .optimize[0].into]), .totals.files]' <<<"$got")" \
    = '[[true,"deleted","2026-11-06T01:00:00Z",["b.test","c.test"]],1]' ] \
    || fail "gone.test, deleted: $(jq -c '[(.files[] | select(.file == "gone.test")), .totals]' <<<"$got")"
}

# The Tests page's Caught column (#75): a test file that failed on a card whose landed commit left it as it was caught
# a bug (the fix went into the code); one whose landed commit changed it was changed to pass. f.test failed on c-1
# (landed: it changed code.sh alone), on c-2 (landed: it changed f.test), on c-3 (blocked, never landed) and on c-4
# (its landed commit is not in main's checkout); it ran on two cards that passed too: 6 runs on record. Bug caught: a
# page that showed no test file catching anything, or counted a test edited to pass, or an unlanded card, as a catch.
# The cheap check for hollow tests (#77): in a .test.ts of main, a case with no assertion and a case whose only
# assertion is toBeDefined are hollow; a case with a real expect(x).toBe(2) is not, and neither is a one-line case
# whose assertion follows its name on the same line, or a case that calls a variable named before (before.click())
# ahead of its assertion. Bugs it catches: a case that passes without proving anything
# showed on the Tests page as any other; a case that asserts was flagged.
t_tfcaught() {
  setup '[]'
  printf '%s\n' "import { describe, it, expect } from 'vitest';" "describe('sum', () => {" "  it('loads', async () => {" '    await load();' '  });' \
    "  it('has a value', () => {" '    expect(get()).toBeDefined();' '  });' "  it(\"adds\", () => {" '    before.click();' '    const x = add(1, 1);' '    expect(x).toBe(2);' '  });' \
    "  test('one line', () => expect(add(0, 1)).toBe(1));" '});' > "$R/sum.test.ts"
  touch "$R/f.test" "$R/code.sh" && git -C "$R" add f.test code.sh sum.test.ts && git -C "$R" commit -qm base || fail "main's files"
  echo fix > "$R/code.sh" && git -C "$R" commit -qam "fix the code" && s1=$(git -C "$R" rev-parse HEAD) || fail "the code fix"
  echo edit > "$R/f.test" && git -C "$R" commit -qam "edit the test" && s2=$(git -C "$R" rev-parse HEAD) || fail "the test edit"
  tf_runs f.test 1 1
  jq -cn --arg s1 "$s1" --arg s2 "$s2" '["c-1", "c-2", "c-3", "c-4"] | to_entries[] | .value as $c
      | {card: $c, issue: (.key + 1), step: "test", time: "2026-11-11T1\(.key):00:00Z", result: "fail", times: {"f.test": 1},
         failures: {of: 1, files: [{file: "f.test", cases: []}], timeout: null}},
        ({card: $c, issue: (.key + 1), time: "2026-11-11T1\(.key):30:00Z"} + ({"c-1": {step: "landed", result: "ok", sha: $s1},
          "c-2": {step: "landed", result: "ok", sha: $s2}, "c-3": {step: "blocked", reason: "no"},
          "c-4": {step: "landed", result: "ok", sha: ("0" * 40)}}[$c]))' >> "$ST/cards.jsonl"
  got=$(tf_in testspart 2026-11-09) || fail "testspart failed: $got"
  [ "$(jq -c '.files[] | select(.file == "f.test") | {caught, changedToPass, runsOnRecord, failedSteps}' <<<"$got")" = '{"caught":1,"changedToPass":1,"runsOnRecord":6,"failedSteps":4}' ] \
    || fail "f.test's catches: $(jq -c '.files[] | select(.file == "f.test")' <<<"$got")"
  [ "$(jq -c '.files[] | select(.file == "sum.test.ts") | .hollow | map([.case, .kind])' <<<"$got")" = '[["loads","no-assert"],["has a value","defined-only"]]' ] \
    || fail "the hollow cases of sum.test.ts: $(jq -c '.files[] | select(.file == "sum.test.ts") | .hollow' <<<"$got")"
}

# A card that weakens a test file main had, to get green, shows on the Tests page (#76). One card, landed by land():
# in a.test.mjs it removes one expect( line, changes toBe(3) to toBe(4), adds it.skip and raises a timeout; in
# s.test.sh it deletes a case (t_two, with its assertion) and raises the file's timeout; it edits a.test.py, a kind
# the table does not read; it changes true to false in bool.test.mjs, the message alone in msg.test.mjs and the
# expected value on its own line in multi.test.mjs; in re.test.mjs it changes 7 to 8 in a regular expression with a
# comma and removes the assertion after one with an unclosed \( in its regular expression; it deletes gone.test.sh;
# and it adds new.test.mjs. Bug caught: a landed line with no testedits, a count read wrong (a changed assertion taken
# for a removed one, a boolean, multiline or regular expression expected value missed, a regular expression's comma
# or bracket read as code, a changed message taken for a changed expected value, a skip or a deleted case
# missed), a deleted test file left out, a new test file counted as an edit of one main had, or an unread kind left
# out; and a Tests part with no list of them, or one that grows with every card that lands.
t_tfedits() {
  setup '[]'
  printf '%s\n' "it('a', () => {" '  expect(f()).toBe(3);' '  expect(g()).toBe(1);' '});' "it('b', () => {" '  expect(h()).toBe(2);' '}, { timeout: 1000 });' > "$R/a.test.mjs"
  printf '%s\n' "test('b', () => { assert.equal(on(), true, 'it is on'); });" > "$R/bool.test.mjs"
  printf '%s\n' "test('m', () => { assert.equal(n(), 2, 'two'); });" > "$R/msg.test.mjs"
  printf '%s\n' "test('l', () => {" '  assert.deepEqual(list(),' '    [1, 2]);' '});' > "$R/multi.test.mjs"
  printf '%s\n' "test('r', () => {" '  assert.match(cost(), /no price \(1 today, 2 in 7 days\)/);' '  assert.match(open(), /a \( b/);' '  assert.equal(n(), 1);' '});' > "$R/re.test.mjs"
  printf '%s\n' 't_gone() {' '  [ "$(z)" = 3 ] || fail "z"' '}' > "$R/gone.test.sh"
  printf '%s\n' '# timeout: 120' 't_one() {' '  [ "$(x)" = 1 ] || fail "x"' '}' 't_two() {' '  [ "$(y)" = 2 ] || fail "y"' '}' > "$R/s.test.sh"
  echo x > "$R/a.test.py"
  git -C "$R" add a.test.mjs s.test.sh a.test.py bool.test.mjs msg.test.mjs multi.test.mjs re.test.mjs gone.test.sh && git -C "$R" commit -qm tests || fail "main's test files"
  W=$T/$CASE/cards/c-1; git -C "$R" worktree add -q --detach "$W" || fail "the card's worktree"
  printf '%s\n' "it('a', () => {" '  expect(f()).toBe(4);' '});' "it.skip('b', () => {" '  expect(h()).toBe(2);' '}, { timeout: 5000 });' > "$W/a.test.mjs"
  printf '%s\n' '# timeout: 300' 't_one() {' '  [ "$(x)" = 1 ] || fail "x"' '}' > "$W/s.test.sh"
  echo y > "$W/a.test.py"; echo "it('n', () => { expect(1).toBe(1); });" > "$W/new.test.mjs"
  printf '%s\n' "test('b', () => { assert.equal(on(), false, 'it is on'); });" > "$W/bool.test.mjs"
  printf '%s\n' "test('m', () => { assert.equal(n(), 2, 'it is two'); });" > "$W/msg.test.mjs"
  printf '%s\n' "test('l', () => {" '  assert.deepEqual(list(),' '    [1, 3]);' '});' > "$W/multi.test.mjs"
  printf '%s\n' "test('r', () => {" '  assert.match(cost(), /no price \(1 today, 2 in 8 days\)/);' '  assert.match(open(), /a \( b/);' '});' > "$W/re.test.mjs"
  git -C "$W" rm -q gone.test.sh || fail "gone.test.sh not deleted"
  git -C "$W" add -A && tf_card eval 'names && land c-1 7 "$W" "weaken the tests"' || fail "the card did not land"
  got=$(st 'select(.step == "landed") | .testedits | map([.file, .read, .removedAsserts, .changedExpected, .skipsAdded, .timeoutsRaised, .casesDeleted])' | jq -c .)
  [ "$got" = '[["a.test.mjs",true,1,1,1,1,0],["a.test.py",false,null,null,null,null,null],["bool.test.mjs",true,0,1,0,0,0],["gone.test.sh",true,1,0,0,0,1],["msg.test.mjs",true,0,0,0,0,0],["multi.test.mjs",true,0,1,0,0,0],["re.test.mjs",true,1,1,0,0,0],["s.test.sh",true,1,0,0,1,1]]' ] \
    || fail "the landed line's testedits: $got"
  loop check >/dev/null || fail "the landed line with testedits does not check"
  # Five later cards edit a.test.mjs: the part keeps a file's newest five edits alone (the snapshot stays small).
  for i in 2 3 4 5 6; do
    jq -cn --argjson i "$i" '{card: "c-\($i)", issue: $i, step: "landed", time: "2099-01-01T0\($i):00:00Z", tokens: {claude: 0, codex: 0}, result: "ok", sha: "s", reason: "",
      product: false, testedits: [{file: "a.test.mjs", read: true, removedAsserts: 0, changedExpected: 0, skipsAdded: 0, timeoutsRaised: 0, casesDeleted: 0}]}' >> "$ST/cards.jsonl"
  done
  got=$(tf_in testspart 2026-11-09 | jq -c '.edits | map([.card, .issue, .file])')
  [ "$got" = '[["c-6",6,"a.test.mjs"],["c-5",5,"a.test.mjs"],["c-4",4,"a.test.mjs"],["c-3",3,"a.test.mjs"],["c-2",2,"a.test.mjs"],["c-1",7,"a.test.py"],["c-1",7,"bool.test.mjs"],["c-1",7,"gone.test.sh"],["c-1",7,"msg.test.mjs"],["c-1",7,"multi.test.mjs"],["c-1",7,"re.test.mjs"],["c-1",7,"s.test.sh"]]' ] \
    || fail "the Tests part's edits, newest first, a file's newest five: $got"
}
