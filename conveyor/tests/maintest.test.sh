#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the whole test on main (the pack's test.main), run by the loop beside its cards.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# A card's test step runs only the tests of what the card touched, so a break outside them reaches main unseen unless
# the whole test runs there. It must not run for every landing (it is the slow one: at most once an hour, and only
# when main has moved), and a failure must reach the owner once: one issue that names the failing cases and the
# commits since the last pass, added to when the same cases fail again, never one issue a run.
# The stages are cases side by side. A case that goes on from a pass or a failure that t_maintest makes by a run writes
# that record by hand (maintest_pass, maintest_failed): each run of the whole test costs the case its CPU time, and
# the file's CPU time is held to the test budget.
maintest_start() {
  export XDG_CONFIG_HOME=$T/$CASE/config # the host file it changes is the case's own, not the other cases'
  setup "[]"
  mt() { CONVEYOR_NOW=$1 loop main-test; }                  # <the time, in seconds>: the whole test, when one is due then
  rec() { jq -c "$1" "$ST/maintest.json" 2>/dev/null; }      # <jq filter>: of the kept record
  runs() { cat "$STUB/mains" 2>/dev/null | grep -cx x; }   # the whole runs (a run of a case alone is told its list)
  move() { echo "$1" >> "$R/a.txt"; git -C "$R" commit -qam "$1"; git -C "$R" rev-parse HEAD; } # <subject>: main moves on
  T0=1800000000; A=$(git -C "$R" rev-parse HEAD)
}
# The pack's whole test, passing, and the record of a pass of it at <time> as maintest() keeps it (t_maintest's first
# run): main's commit is the last pass, its run counted <n> `ok` lines (0 when not given). No run is counted (runs).
maintest_pass() { # <time> [<n>]
  tune '.test.main = ". \"$STUB/main-cmd\""'; echo 'echo "x$CONVEYOR_TEST_RERUN" >> "$STUB/mains"' > "$STUB/main-cmd"
  mkdir -p "$ST" && jq -cn --arg s "$(git -C "$R" rev-parse HEAD)" --argjson t "$1" --argjson n "${2:-0}" \
    '{sha: $s, at: ($t | todate), pass: $s, fail: null, full: $n}' > "$ST/maintest.json" || fail "the pass could not be written"
}
t_maintest() {
  maintest_start; local B
  # A pack that names no whole test has none.
  mt $T0 || fail "main-test failed with no test.main"
  [ ! -e "$ST/maintest.json" ] || fail "a pack with no test.main ran a whole test: $(rec .)"
  tune '.test.main = ". \"$STUB/main-cmd\""'
  echo 'echo "x$CONVEYOR_TEST_RERUN" >> "$STUB/mains"; pwd > "$STUB/where"; git rev-parse HEAD > "$STUB/at"' > "$STUB/main-cmd"
  mt $T0 || fail "the first whole test failed: $(cat "$T/$CASE/cards/maintest/wt.test" 2>&1)"
  [ "$(runs)" = 1 ] && [ "$(rec '[.sha, .pass, .fail]')" = "[\"$A\",\"$A\",null]" ] || fail "the first run is not recorded as a pass of main's commit: $(runs) runs, $(rec .)"
  [ "$(cat "$STUB/where")" = "$T/$CASE/cards/maintest/wt" ] && [ "$(cat "$STUB/at")" = "$A" ] && [ ! -e "$T/$CASE/cards/maintest/wt" ] \
    || fail "the whole test did not run in a worktree of main's commit of its own, or left it: $(cat "$STUB/where" "$STUB/at")"
  # Main has not moved: no run, however long ago the last one was.
  mt $((T0 + 100000)); [ "$(runs)" = 1 ] || fail "the whole test ran again with main where it was"
  # Main moved, the last run under an hour ago: not yet.
  B=$(move "move b"); mt $((T0 + 3599)); [ "$(runs)" = 1 ] || fail "the whole test ran twice within the hour"
  # An hour on, it runs, and fails: one issue of the second priority names the cases and the commits since the pass.
  echo 'echo "x$CONVEYOR_TEST_RERUN" >> "$STUB/mains"; echo "FAIL [beta]: expected 2, got 3"; echo "FAIL [alpha]: no word"; echo "ok gamma"; exit 1' > "$STUB/main-cmd"
  mt $((T0 + 3600)); [ "$(runs)" = 2 ] || fail "the whole test did not run an hour on, with main moved: $(rec .)"
  [ "$(jq -cs 'map([.number, .title, (.labels | map(.name))])' "$STUB/filed")" = '[[100101,"The whole test fails on main: alpha, beta",["bug","P1"]]]' ] \
    || fail "a failed whole test did not file one P1 issue naming the cases: $(cat "$STUB/filed" 2>&1)"
  jq -e --arg r "${A:0:12}..${B:0:12}" --arg c "- $(git -C "$R" log -1 --format=%h "$B") move b" \
      '.body | (contains("- alpha\n- beta\n") and contains($r) and contains($c) and (contains("gamma") | not))' "$STUB/filed" >/dev/null \
    || fail "the issue does not name the failing cases alone and the commits since the last pass: $(jq -r .body "$STUB/filed")"
  [ "$(rec '[.pass, .fail.issue, .fail.cases, .fail.from, .fail.to, .fail.exit]')" = "[\"$A\",100101,[\"alpha\",\"beta\"],\"$A\",\"$B\",1]" ] || fail "the failure is not kept: $(rec .)"
}
# The pass at A and the failure t_maintest ends on, as maintest() keeps them: #100101 filed for alpha and beta at B,
# an hour on, and the whole test failing so still. No run is counted (runs). Sets B.
maintest_failed() {
  maintest_pass $T0
  echo 'echo "x$CONVEYOR_TEST_RERUN" >> "$STUB/mains"; echo "FAIL [beta]: expected 2, got 3"; echo "FAIL [alpha]: no word"; echo "ok gamma"; exit 1' > "$STUB/main-cmd"
  B=$(move "move b")
  jq -cn --arg a "$A" --arg b "$B" --argjson t $((T0 + 3600)) '($t | todate) as $at | ["alpha", "beta"] as $c
    | {sha: $b, at: $at, pass: $a, full: 0, fail: {issue: 100101, cases: $c, from: $a, to: $b, since: $at, exit: 1}, filed: [{issue: 100101, cases: $c}]}' \
    > "$ST/maintest.json" \
    && jq -cn '{number: 100101, title: "The whole test fails on main: alpha, beta", body: "", milestone: null, createdAt: "2026-12-01",
      labels: [{name: "bug"}, {name: "P1"}]}' > "$STUB/filed" || fail "the failure could not be written"
}
t_maintestneeds() {
  maintest_start; local B
  maintest_failed
  # The Board's Needs you reads it from the snapshot, while its issue is open (the filed issues are listed open).
  touch "$STUB/list-filed"
  [ "$(loop snapshot --fresh | jq -c '.mainTest | [.issue, .cases, .to, .since]')" = "[100101,[\"alpha\",\"beta\"],\"$B\",\"$(jq -rn --argjson t $((T0 + 3600)) '$t | todate')\"]" ] \
    || fail "the snapshot does not carry the failure: $(loop snapshot --fresh | jq -c .mainTest)"
  # Its issue closed with no pass since, or a pack that no longer names a whole test (nothing runs to clear it):
  # Needs you no longer asks the owner about it.
  rm "$STUB/list-filed"; [ "$(loop snapshot --fresh | jq -c .mainTest)" = null ] || fail "the snapshot names a failure whose issue is closed: $(loop snapshot --fresh | jq -c .mainTest)"
  touch "$STUB/list-filed"; tune 'del(.test.main)'
  [ "$(loop snapshot --fresh | jq -c .mainTest)" = null ] || fail "the snapshot names a failure with no test.main in the pack: $(loop snapshot --fresh | jq -c .mainTest)"
}
# From the failure maintest_failed keeps: the same cases fail again, then other cases, then the first again; then a
# pass clears it.
t_maintestagain() {
  maintest_start; local B C D E F
  maintest_failed
  # The same cases fail again on a later commit, the issue still open: a comment on it, and no second issue.
  echo OPEN > "$STUB/state.100101"; C=$(move "move c"); mt $((T0 + 7200)); [ "$(runs)" = 1 ] || fail "the whole test did not run again: $(rec .)"
  [ "$(wc -l < "$STUB/filed")" = 1 ] || fail "a second failure of the same cases filed another issue: $(jq -c '[.number, .title]' "$STUB/filed")"
  grep -q "^100101 --body .*failed again, with the same cases, at ${C:0:12}" "$STUB/comments" && grep -qF "${A:0:12}..${C:0:12}" "$STUB/comments" \
    || fail "a second failure of the same cases was not added to the issue with its commits: $(cat "$STUB/comments" 2>&1)"
  [ "$(rec '[.fail.issue, .fail.to, .fail.since]')" = "[100101,\"$C\",\"$(jq -rn --argjson t $((T0 + 3600)) '$t | todate')\"]" ] || fail "the failure that stands is not the same one, at the new commit: $(rec .)"
  # Other cases fail: another issue, of those cases.
  echo 'echo "x$CONVEYOR_TEST_RERUN" >> "$STUB/mains"; echo "FAIL [delta]: wrong"; exit 1' > "$STUB/main-cmd"
  D=$(move "move d"); mt $((T0 + 10800))
  [ "$(jq -cs 'map([.number, .title])' "$STUB/filed")" = '[[100101,"The whole test fails on main: alpha, beta"],[100102,"The whole test fails on main: delta"]]' ] \
    || fail "a failure of other cases did not file its own issue: $(jq -c '[.number, .title]' "$STUB/filed")"
  # The first cases fail again, their issue still open and another failure since: it is added to, not filed again
  # (an owner with one open issue a set of cases is not sent a new one each time the failures alternate).
  echo 'echo "x$CONVEYOR_TEST_RERUN" >> "$STUB/mains"; echo "FAIL [beta]: expected 2, got 3"; echo "FAIL [alpha]: no word"; exit 1' > "$STUB/main-cmd"
  F=$(move "move f"); mt $((T0 + 14400)); [ "$(runs)" = 3 ] || fail "the whole test did not run a third time: $(rec .)"
  [ "$(wc -l < "$STUB/filed")" = 2 ] || fail "cases whose issue is open were filed again after another failure: $(jq -c '[.number, .title]' "$STUB/filed")"
  grep -q "^100101 --body .*failed again, with the same cases, at ${F:0:12}" "$STUB/comments" && [ "$(rec .fail.issue)" = 100101 ] \
    || fail "the cases' open issue was not added to after another failure: $(cat "$STUB/comments" 2>&1) $(rec .)"
  # A pass clears it: Needs you no longer lists it, and the next failure's commits are counted from here.
  echo 'echo "x$CONVEYOR_TEST_RERUN" >> "$STUB/mains"' > "$STUB/main-cmd"
  E=$(move "move e"); mt $((T0 + 18000))
  [ "$(rec '[.pass, .fail]')" = "[\"$E\",null]" ] && [ "$(loop snapshot --fresh | jq -c .mainTest)" = null ] || fail "a pass did not clear the failure: $(rec .)"
}
# A try that tested nothing, or whose failure reached no one, is tried again: from a pass at A.
t_maintestretry() {
  maintest_start; local G J hook host
  maintest_pass $T0
  # A try whose worktree could not be made tested nothing: its commit is tried again an hour on, main where it was,
  # and is not taken for tested (else a passing break stays unseen until the next landing).
  G=$(move "move g"); hook=$(git -C "$R" rev-parse --absolute-git-dir)/hooks/post-checkout
  mkdir -p "${hook%/*}"; printf '#!/bin/sh\nexit 1\n' > "$hook"; chmod +x "$hook"
  mt $((T0 + 3600)) 2> "$STUB/main.err" && fail "a whole test whose worktree could not be made did not say so"
  grep -q 'its worktree could not be made' "$STUB/main.err" && [ "$(runs)" = 0 ] && [ "$(rec .sha)" = "\"$A\"" ] \
    || fail "a try with no worktree ran the test, or is kept as a run of its commit: $(runs) runs, $(rec .), $(cat "$STUB/main.err")"
  rm -f "$hook"
  mt $((T0 + 7199)); [ "$(runs)" = 0 ] || fail "the try after a failed setup did not wait its hour"
  mt $((T0 + 7200)); [ "$(runs)" = 1 ] && [ "$(rec '[.sha, .pass]')" = "[\"$G\",\"$G\"]" ] || fail "the commit of a failed setup was never tested: $(runs) runs, $(rec .)"
  # A try whose test slots could not be made tested nothing either.
  host=$XDG_CONFIG_HOME/conveyor/host.json
  mkdir -p "${host%/*}"; echo '{"testSlotsDir": "/dev/null/slots"}' > "$host"
  J=$(move "move j"); mt $((T0 + 10800)) 2> "$STUB/main.err" && fail "a whole test whose slots could not be made did not say so"
  grep -q 'did not run' "$STUB/main.err" && grep -q 'the test slots folder .* cannot be made' "$STUB/main.err" && [ "$(runs)" = 1 ] && [ "$(rec .sha)" = "\"$G\"" ] \
    || fail "a try with no test slots ran the test, or is kept as a run of its commit: $(runs) runs, $(rec .), $(cat "$STUB/main.err")"
  rm -f "$host"
  mt $((T0 + 14400)); [ "$(runs)" = 2 ] && [ "$(rec '[.sha, .pass, .fail]')" = "[\"$J\",\"$J\",null]" ] || fail "the commit of a try with no test slots was never tested: $(runs) runs, $(rec .)"
}
# A failure whose issue could not be filed, whose comment could not be added, or whose issue's state was not given:
# from a pass at A, with no issue filed before (its first is #100101). The failure names no case: each named case
# would be run alone 3 times on each of the 5 runs, and what is tested here is what GitHub did with it.
t_maintestgh() {
  maintest_start; local H I
  maintest_pass $T0
  # A failure GitHub did not take reached no one: its commit is not taken for tested, and an hour on, main where it
  # was, the test runs again and the issue is filed (else the break stays on main with no issue until a landing).
  echo 'echo "x$CONVEYOR_TEST_RERUN" >> "$STUB/mains"; echo "something broke"; exit 1' > "$STUB/main-cmd"; echo 'exit 1' > "$STUB/create-cmd"
  H=$(move "move h"); mt $((T0 + 3600)) 2> "$STUB/main.err"
  grep -q 'its issue could not be filed' "$STUB/main.err" && [ "$(runs)" = 1 ] && [ "$(rec '[.sha, .fail.issue, .fail.to]')" = "[\"$A\",null,\"$H\"]" ] \
    || fail "a failure whose issue could not be filed is kept as told: $(runs) runs, $(rec .), $(cat "$STUB/main.err")"
  rm -f "$STUB/create-cmd"; mt $((T0 + 7200))
  [ "$(runs)" = 2 ] && [ "$(jq -cs 'map(.title)' "$STUB/filed")" = "[\"The whole test fails on main at ${H:0:12}\"]" ] && [ "$(rec '[.sha, .fail.issue]')" = "[\"$H\",100101]" ] \
    || fail "an issue that could not be filed was never filed with main where it was: $(runs) runs, $(rec .)"
  # The same of a comment that could not be added, and of an issue whose state GitHub did not give.
  echo OPEN > "$STUB/state.100101"; echo 'exit 1' > "$STUB/comment-cmd"
  I=$(move "move i"); mt $((T0 + 10800)) 2> "$STUB/main.err"
  grep -q 'no comment could be added to #100101' "$STUB/main.err" && [ "$(runs)" = 3 ] && [ "$(rec '[.sha, .fail.issue, .fail.to]')" = "[\"$H\",100101,\"$I\"]" ] \
    || fail "a failure whose comment could not be added is kept as told: $(runs) runs, $(rec .), $(cat "$STUB/main.err")"
  rm -f "$STUB/comment-cmd"; : > "$STUB/state.100101"; mt $((T0 + 14400)) 2> "$STUB/main.err"
  grep -q 'the state of #100101 could not be read' "$STUB/main.err" && [ "$(runs)" = 4 ] && [ "$(rec .sha)" = "\"$H\"" ] && [ "$(wc -l < "$STUB/filed")" = 1 ] \
    || fail "a failure whose issue GitHub said nothing of is kept as told, or filed again: $(runs) runs, $(rec .), $(cat "$STUB/main.err")"
  echo OPEN > "$STUB/state.100101"; mt $((T0 + 18000))
  [ "$(runs)" = 5 ] && grep -q "^100101 --body .*failed again, with the same cases, at ${I:0:12}" "$STUB/comments" && [ "$(rec .sha)" = "\"$I\"" ] && [ "$(wc -l < "$STUB/filed")" = 1 ] \
    || fail "a comment that could not be added was never added with main where it was: $(runs) runs, $(rec .), $(cat "$STUB/comments")"
}
# A case of another file: from a pass at A, with no issue filed before.
t_maintestfile() {
  maintest_start
  maintest_pass $T0
  # A case is of its file: the same case name failing in another file is another failure, with its own issue, and
  # is never added to the first file's issue (its owner would read b's break as a's, already known).
  filecmd() { echo 'echo "x$CONVEYOR_TEST_RERUN" >> "$STUB/mains"; echo "== '"$1"'" | tee -a "$CONVEYOR_TEST_LOG/run.log"; echo "FAIL [renders]: off"; echo "-- FAIL '"$1"'" >> "$CONVEYOR_TEST_LOG/run.log"; exit 1' > "$STUB/main-cmd"; }
  filecmd a.test.sh; move "move k" > /dev/null; mt $((T0 + 3600))
  [ "$(runs)" = 1 ] && [ "$(rec '[.fail.issue, .fail.cases]')" = '[100101,["a.test.sh: renders"]]' ] || fail "a failing case is not named with its file: $(runs) runs, $(rec .)"
  echo OPEN > "$STUB/state.100101"; filecmd b.test.sh; move "move l" > /dev/null; mt $((T0 + 7200))
  [ "$(runs)" = 2 ] && [ "$(rec '[.fail.issue, .fail.cases]')" = '[100102,["b.test.sh: renders"]]' ] && ! grep -qs '^100101 ' "$STUB/comments" \
    && [ "$(jq -cs 'map(.title)' "$STUB/filed")" = '["The whole test fails on main: a.test.sh: renders","The whole test fails on main: b.test.sh: renders"]' ] \
    || fail "the same case name failing in another file was taken for the first file's failure: $(runs) runs, $(rec .), $(jq -c '[.number, .title]' "$STUB/filed")"
}
# Runs of <n> passing cases and no failure, after a full run of 720 at A, each an hour after the last.
# Bug: a run of half the suite with no failure was green, and became the last pass later failures are measured from.
t_maintestshort() {
  maintest_start; local B C
  maintest_pass $T0 720
  okcmd() { echo 'echo x >> "$STUB/mains"; for i in $(seq '"$1"'); do echo "ok case$i"; done' > "$STUB/main-cmd"; }
  B=$(move "move b"); okcmd 300; mt $((T0 + 3600)); [ "$(runs)" = 1 ] || fail "the second whole test did not run: $(rec .)"
  [ "$(rec '[.pass, .full, .fail.to, .fail.exit]')" = "[\"$A\",720,\"$B\",0]" ] || fail "a run of 300 of 720 cases moved the last pass or was taken for a pass: $(rec .)"
  jq -e '(.title | contains("ran 300 of about 720 cases")) and (.body | contains("ran 300 of about 720 cases") and contains("ok case300"))' "$STUB/filed" >/dev/null \
    || fail "the short run's issue does not say how many cases ran with the end of its output: $(cat "$STUB/filed" 2>&1)"
  # A run a little under the last full count (cases removed, a few skipped) is still a pass, and its count is kept.
  C=$(move "move c"); okcmd 715; mt $((T0 + 7200))
  [ "$(rec '[.pass, .full, .fail]')" = "[\"$C\",715,null]" ] && [ "$(wc -l < "$STUB/filed")" = 1 ] || fail "a run of 715 of 720 cases was not a pass: $(rec .), $(cat "$STUB/filed" 2>&1)"
}
t_maintestserve() {
  maintest_start; tune '.test.main = ". \"$STUB/main-cmd\""'
  # The loop runs it by itself, beside its cards: a card lands while the whole test is still running.
  echo "$GO" > "$STUB/review.1"
  echo 'echo "x$CONVEYOR_TEST_RERUN" >> "$STUB/mains"; while [ -d "$STUB" ]; do [ -e "$STUB/go" ] && break; sleep 0.1; done' > "$STUB/main-cmd"
  tune '.tunables.idle = 1 | .tunables.poll = 1'
  issue 7 2026-01-01 | jq -cs . > "$STUB/issues.json"
  loop serve > "$STUB/serve.out" 2>&1 & pid=$!; trap 'kill $pid 2>/dev/null; : > "$STUB/go"' EXIT
  wait_until '[ -n "$(st '"'"'select(.issue == 7 and .step == "landed")'"'"')" ]' 'cat "$STUB/serve.out"' || fail "the card did not land while the whole test ran"
  [ "$(runs)" = 1 ] && [ ! -e "$STUB/go" ] && [ "$(rec .pass)" = null ] || fail "the whole test was not running beside the card: $(runs) runs, $(rec .)"
  : > "$STUB/go"
  wait_until '[ "$(rec ".pass != null")" = true ]' 'cat "$STUB/serve.out"' || fail "the loop's whole test did not end with a pass: $(rec .)"
  kill $pid; wait $pid 2>/dev/null; return 0
}
# A pack with test.mainAt runs the whole test once a day at that time, in place of hourly runs that cost too much: it
# must not run before the time, nor a second time the same day when main moves again.
t_maintestdaily() {
  maintest_start; local D; export TZ=UTC
  tune '.test.main = ". \"$STUB/main-cmd\"" | .test.mainAt = "01:00"'; echo 'echo "x$CONVEYOR_TEST_RERUN" >> "$STUB/mains"' > "$STUB/main-cmd"
  D=$((T0 / 86400 * 86400)) # 00:00 of T0's day
  mt $((D + 3599)); [ "$(runs)" = 0 ] || fail "the daily whole test ran before its time"
  mt $((D + 3600)); [ "$(runs)" = 1 ] && [ "$(rec .pass)" = "\"$A\"" ] || fail "the daily whole test did not run at its time: $(runs) runs, $(rec .)"
  move "move b" > /dev/null; mt $((D + 7200)); mt $((D + 82800))
  [ "$(runs)" = 1 ] || fail "the daily whole test ran again the same day: $(runs) runs"
  mt $((D + 86400 + 3599)); [ "$(runs)" = 1 ] || fail "the daily whole test ran before its time the next day"
  mt $((D + 86400 + 3600)); [ "$(runs)" = 2 ] || fail "the daily whole test did not run the next day: $(runs) runs, $(rec .)"
}
# Each failed case is run alone 3 times: a case that fails alone is a break in the code and files one issue with its
# failure line and the commits; one that passes every time alone is flaky, goes to the flaky-test record, and files
# nothing (else a flaky case would send the owner a break to chase each night).
t_maintestalone() {
  maintest_start; local B C
  maintest_pass $T0
  # A run whose every failed case passes alone is a pass: no issue, and main's commit is the last pass.
  echo 'echo "x$CONVEYOR_TEST_RERUN" >> "$STUB/mains"; [ -n "$CONVEYOR_TEST_RERUN" ] && exit 0; echo "FAIL [shaky]: too slow"; exit 1' > "$STUB/main-cmd"
  B=$(move "move b"); mt $((T0 + 3600))
  [ ! -e "$STUB/filed" ] && [ "$(rec '[.pass, .fail]')" = "[\"$B\",null]" ] && [ "$(jq -c '[.entries[] | [.case, .source]]' "$ST/flaky.json" 2>&1)" = "[[\"shaky\",\"main test ${B:0:12}\"]]" ] \
    || fail "a run whose only failure passed alone was not a pass with a flaky entry: $(rec .), $(cat "$STUB/filed" 2>&1)"
  # A case that fails alone files its issue; the one that passes alone beside it does not.
  : > "$STUB/mains"
  echo 'echo "x$CONVEYOR_TEST_RERUN" >> "$STUB/mains"; if [ -n "$CONVEYOR_TEST_RERUN" ] && grep -q shaky "$CONVEYOR_TEST_RERUN"; then exit 0; fi
    echo "FAIL [solid]: expected 1, got 2"; [ -n "$CONVEYOR_TEST_RERUN" ] || echo "FAIL [shaky]: too slow"; exit 1' > "$STUB/main-cmd"
  C=$(move "move c"); mt $((T0 + 7200))
  [ "$(runs)" = 1 ] && [ "$(grep -cv '^x$' "$STUB/mains")" = 6 ] || fail "each failed case was not run alone 3 times: $(cat "$STUB/mains")"
  [ "$(jq -cs 'map([.number, .title, (.labels | map(.name))])' "$STUB/filed")" = '[[100101,"The whole test fails on main: solid",["bug","P1"]]]' ] \
    || fail "the case that failed alone did not file one P1 issue of its own: $(cat "$STUB/filed" 2>&1)"
  jq -e --arg r "${B:0:12}..${C:0:12}" --arg c "- $(git -C "$R" log -1 --format=%h "$C") move c" \
      '.body | (contains("- solid: FAIL [solid]: expected 1, got 2 (passed alone 0 of 3)") and contains($r) and contains($c) and (contains("shaky") | not))' "$STUB/filed" >/dev/null \
    || fail "the issue does not name the case, its failure line and the commits since the flaky run's pass, or names the flaky case: $(jq -r .body "$STUB/filed")"
  [ "$(jq -c '[.entries[] | [.case, .source]]' "$ST/flaky.json" 2>&1)" = "[[\"shaky\",\"main test ${B:0:12}\"],[\"shaky\",\"main test ${C:0:12}\"]]" ] \
    || fail "the case that passed alone was not added to the flaky-test record: $(cat "$ST/flaky.json" 2>&1)"
  [ "$(rec '[.pass, .fail.cases]')" = "[\"$B\",[\"solid\"]]" ] || fail "the failure kept is not of the case that failed alone: $(rec .)"
}

# #150. Bug it catches: a test map made long ago kept sending changes to the tests of code that had since moved. The
# next whole test on main that passes makes it again, on main's commit, once it is more commits old than test.mapAge,
# from that run's own coverage: the test file runs once (its line in ran), not again in a second run of the suite.
t_maintestmap() {
  maintest_start; local B
  mkdir -p "$R/src" "$R/test" && echo '{}' > "$R/package.json" && echo 'module.exports = 1;' > "$R/src/a.js" \
    && printf "require('../src/a.js'); require('node:fs').appendFileSync('%s', 'a\\\\n');\n" "$T/$CASE/ran" > "$R/test/a.test.js" \
    && git -C "$R" add -A && git -C "$R" commit -qm node || fail "the Node files"
  tune '.test.mapAge = 1 | .test.main = ". \"$STUB/main-cmd\""'; echo 'node --max-old-space-size=4096 --test test/a.test.js' > "$STUB/main-cmd"
  jq -n --arg c "$A" --arg cmd "$(jq -r .test.command "$R/.conveyor/project.json")" '{commit: $c, command: $cmd, language: "node", tests: [], sources: {}}' \
    > "$R/.conveyor/test-map.json" || fail "the old map"
  move "move b" > /dev/null; B=$(move "move c")
  mt $T0 > "$T/$CASE/mt.out" 2>&1 || fail "the whole test failed: $(cat "$T/$CASE/mt.out")"
  jq -e --arg b "$B" '.commit == $b and .sources == {"src/a.js": ["test/a.test.js"]}' "$R/.conveyor/test-map.json" >/dev/null \
    || fail "the whole test did not make the old map again on main's commit: $(cat "$R/.conveyor/test-map.json" "$T/$CASE/mt.out")"
  [ "$(cat "$T/$CASE/ran")" = a ] || fail "the test file did not run once, in the whole test alone: $(cat "$T/$CASE/ran" 2>&1)"
}

