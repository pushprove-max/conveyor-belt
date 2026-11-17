#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the machine verdict (verdicts(), issue 221). A case that fails on the card and on main is main's only
# when an input of its file changed since its last recorded pass and a control passes beside it on the same slot;
# otherwise it is the machine's: no main-red entry, no wait for main, the loop picks no card (machineheld()) until the
# controls pass on main again (machineprobe()), and the cards on hold test again.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# rerunsetup's three test files and command (tests/rerun.test.sh): a.test, b.test and c.test, whose cases fail as
# $STUB/plan says; c.test is the pack's control (test.control). b.txt and c.txt are committed on main as the inputs of
# b.test and c.test. The run of main's look at the hold (machineprobe(), in cards/mainrun/machine) is run `main`, as
# the run of a card's failing cases on main is, its list in $STUB/rerun.main; it marks each of its runs in $STUB/looks.
holdsetup() { # <plan lines>...
  rerunsetup "$@"
  tune '.test.control = ["c.test"]'
  echo b > "$R/b.txt"; echo c > "$R/c.txt"; git -C "$R" add b.txt c.txt && git -C "$R" commit -qm inputs || fail "main's inputs could not be committed"
  echo 'case $PWD in */mainrun/machine) tr "\t\n" ":|" < "$RR" >> "$STUB/looks"; echo >> "$STUB/looks" ;; esac' > "$STUB/pre"
}
holdpass() { # <file<TAB>input>...: each passed with main's content, in the test results cache
  printf '%s\n' "$@" > "$STUB/passes"; eng 'cachesums "$R" < "$STUB/passes" >> "$TESTCACHE"' || fail "the passes could not be recorded"
}
# The card's failing case, b.test's flaky, as testfails() gives it, judged in card c7's worktree on main.
holdjudge() {
  git -C "$R" worktree add -q --detach "$T/$CASE/cards/c7" || fail "the card's worktree could not be made"
  echo '{"files":[{"file":"b.test","cases":[{"name":"flaky","line":1}]}]}' > "$STUB/fails"
  eng 'TEST_WAIT=; TEST_RUN=; TEST_FREE=; verdicts c7 "$CONVEYOR_CARDS/c7" "$(cat "$STUB/fails")" | jq -c .verdicts'
}

# D1: the control c.test, which passed before with main's content, fails on main beside b.test's flaky, whose input
# b.txt changed since it last passed. Bug it catches: a broken machine read as a broken main, so each landing opened a
# main-red fix card and every card behind it waited. The verdict is machine: no main-red entry, the hold names the
# control (and not b.test, which may fail on main for good), health shows it for the Foreman's wake, and the loop picks
# nothing: its one look at the hold fails the control again, so `run` ends saying so.
t_machinecontrol() {
  holdsetup 'main fail flaky' 'main fail three'
  local out
  holdpass $'b.test\tb.txt' $'c.test\tc.txt'
  echo b2 > "$R/b.txt"; git -C "$R" commit -qam "b.test's input changes" || fail "main could not move"
  out=$(holdjudge) || fail "verdicts failed: $out"
  [ "$out" = '[{"case":"b.test: flaky","verdict":"machine"}]' ] || fail "a failing control did not give the verdict machine: $out"
  [ "$(grep $'^fail\t' "$STUB/rerun.main" | tr '\t\n' ':|')" = "fail:b.test:flaky|fail:c.test|" ] \
    || fail "main's run did not run the control beside the failing case: $(cat "$STUB/rerun.main")"
  [ ! -s "$ST/mainred.json" ] || fail "the machine's failure opened a main-red entry: $(cat "$ST/mainred.json")"
  [ "$(jq -c '[.card, .controls, .cases]' "$ST/machinehold.json")" = '["c7",["c.test"],["b.test: flaky"]]' ] \
    || fail "the hold does not name the failing control: $(cat "$ST/machinehold.json" 2>&1)"
  [ "$(loop health | jq -c '.machineHold.controls')" = '["c.test"]' ] || fail "health does not show the hold: $(loop health | jq -c .machineHold)"
  out=$(loop run 1 2>&1) && fail "run exited zero while the machine hold stands: $out"
  [ -z "$(st 'select(.step == "picked") | .card')" ] || fail "the loop picked a card while the machine hold stands: $(st '"\(.step) \(.issue)"' | tr '\n' ,)"
  grep -qF 'conveyor: the machine fails c.test on main, with no change to main that explains it' <<<"$out" && grep -qF 'the machine hold stands; nothing recorded' <<<"$out" \
    || fail "the loop did not say why it picks nothing: $out"
  [ -e "$ST/machinehold.json" ] || fail "a look that failed the control again ended the hold"
}

# D1: b.test passed before with the inputs it has on main (b.txt unchanged) and fails there now, with no control in
# the pack. Bug it catches: a case whose inputs did not change was called main's, though only the machine changed.
t_machineunchanged() {
  holdsetup 'main fail flaky'
  local out
  tune '.test.control = []'
  holdpass $'b.test\tb.txt'
  out=$(holdjudge) || fail "verdicts failed: $out"
  [ "$out" = '[{"case":"b.test: flaky","verdict":"machine"}]' ] || fail "a case whose inputs did not change was not the machine's: $out"
  [ ! -s "$ST/mainred.json" ] || fail "the machine's failure opened a main-red entry: $(cat "$ST/mainred.json")"
  [ "$(jq -c .controls "$ST/machinehold.json")" = '["b.test"]' ] || fail "the hold does not name b.test to pass again: $(cat "$ST/machinehold.json" 2>&1)"
}

# D3: the test results cache holds no pass at all (as with a runner that logs no `TESTRUN inputs` lines, this
# project's own), b.test fails on main and the control c.test passes beside it. Bug it catches: with no recorded pass
# no control ran, so every real red main was called the machine's: no fix card, and the loop held until the broken
# test passed again. The control runs, and main is red.
t_machinenopass() {
  holdsetup 'main fail flaky'
  local out
  out=$(holdjudge) || fail "verdicts failed: $out"
  [ "$out" = '[{"case":"b.test: flaky","verdict":"main"}]' ] || fail "a red main with no recorded pass was not main's: $out"
  grep -q $'^fail\tc.test$' "$STUB/rerun.main" || fail "the control did not run with no recorded pass: $(cat "$STUB/rerun.main")"
  [ "$(jq -c '[.reds[].cases[].case]' "$ST/mainred.json")" = '["b.test: flaky"]' ] || fail "the case did not go to main's fix card: $(cat "$ST/mainred.json" 2>&1)"
  [ ! -e "$ST/machinehold.json" ] || fail "a red main held the loop: $(cat "$ST/machinehold.json")"
}

# D1: the cache holds no pass at all and the control c.test fails beside b.test on main. Bug it catches: a runner
# with no recorded passes could never tell a broken machine, so the machine's failure opened a main-red fix card.
t_machinenopassctl() {
  holdsetup 'main fail flaky' 'main fail three'
  local out
  out=$(holdjudge) || fail "verdicts failed: $out"
  [ "$out" = '[{"case":"b.test: flaky","verdict":"machine"}]' ] || fail "a failing control with no recorded pass did not give machine: $out"
  [ ! -s "$ST/mainred.json" ] || fail "the machine's failure opened a main-red entry: $(cat "$ST/mainred.json")"
  [ "$(jq -c .controls "$ST/machinehold.json")" = '["c.test"]' ] || fail "the hold does not name the failing control: $(cat "$ST/machinehold.json" 2>&1)"
}

# D3: no control is listed (test.control empty) and b.test, with no recorded pass, fails on main. Bug it catches:
# with no control to tell the machine from main, a real red main was held as the machine's and opened no fix card.
t_machinenocontrol() {
  holdsetup 'main fail flaky'
  local out
  tune '.test.control = []'
  out=$(holdjudge) || fail "verdicts failed: $out"
  [ "$out" = '[{"case":"b.test: flaky","verdict":"main"}]' ] || fail "a failure with no control that could run was not main's: $out"
  [ "$(jq -c '[.reds[].cases[].case]' "$ST/mainred.json")" = '["b.test: flaky"]' ] || fail "the case did not go to main's fix card: $(cat "$ST/mainred.json" 2>&1)"
  [ ! -e "$ST/machinehold.json" ] || fail "a red main held the loop: $(cat "$ST/machinehold.json")"
  # A schema description has no behaviour to run, so its text is checked: it said an empty test.control made every
  # failure on main the machine's (issue 230), the opposite of the main verdict above.
  jq -r '.properties.test.properties.control.description' "$SRC/schema/pack.schema.json" | grep -qF "Empty, or none of these runs: a failure on main is main's unless its test file passed before with the same inputs." \
    || fail "test.control's description does not say an empty list leaves a failure on main main's"
}

# D3: b.test's input b.txt changed since its last pass and the control c.test passes beside it: main is red, as
# before. Bug it catches: a real red main called the machine's, so it went to no fix card.
t_machinemain() {
  holdsetup 'main fail flaky'
  local out
  holdpass $'b.test\tb.txt' $'c.test\tc.txt'
  echo b2 > "$R/b.txt"; git -C "$R" commit -qam "b.test's input changes" || fail "main could not move"
  out=$(holdjudge) || fail "verdicts failed: $out"
  [ "$out" = '[{"case":"b.test: flaky","verdict":"main"}]' ] || fail "a changed input with a passing control was not main's: $out"
  [ "$(jq -c '[.reds[].cases[].case]' "$ST/mainred.json")" = '["b.test: flaky"]' ] || fail "the case did not go to main's fix card: $(cat "$ST/mainred.json" 2>&1)"
  [ ! -e "$ST/machinehold.json" ] || fail "a red main held the loop: $(cat "$ST/machinehold.json")"
}

# D2, D4: card #7 fails b.test's flaky on its run and run again, and on main, where the control c.test (passed before
# with main's content) fails too. Bugs it catches: the card waited for main to change, went to a fix session, or
# stayed on hold after the control passed again. It waits for the machine, holding no files; no main-red entry opens;
# the loop's look fails the control while the machine is broken, and once it passes (its failure taken out of the
# plan) the hold goes, the card runs its test step again, passes and lands.
t_machinecard() {
  holdsetup '1 fail flaky' '2 fail flaky' 'main fail flaky' 'main fail three'
  local lp waiting='grep -qs "waiting for the machine: the machine fails c.test on main" "$T/$CASE/cards/"*.live'
  tune '.tunables.poll = 1'
  holdpass $'c.test\tc.txt'
  ( loop run 1 > "$STUB/run.out" 2>&1 ) & lp=$!
  wait_until "$waiting" 'cat "$STUB/run.out"' || fail "the card did not wait for the machine: $(cat "$STUB/run.out")"
  # Bug it catches too: the machine's failure counted as the card's failed test step (result fail, "tests failed").
  [ "$(tline 1 '[.result, .verdicts] | tojson')" = '["held",[{"case":"b.test: flaky","verdict":"machine"}]]' ] \
    || fail "the test line is not held with the verdict machine: $(tline 1 tojson)"
  [ ! -s "$ST/mainred.json" ] && ! grep -qs "waiting for main to change" "$T/$CASE/cards/"*.live \
    || fail "the machine's failure opened a main-red entry or a wait for main: $(cat "$ST/mainred.json" 2>&1)"
  wait_until '[ -s "$STUB/looks" ]' 'cat "$STUB/run.out"' || fail "the loop did not look at the hold: $(cat "$STUB/run.out")"
  [ -e "$ST/machinehold.json" ] || fail "a look that failed the control ended the hold"
  sed -i '/^main fail three$/d' "$STUB/plan"
  wait "$lp" || fail "run exited non-zero: $(cat "$STUB/run.out")"
  [ "$(sort -u "$STUB/looks")" = 'fail:c.test|' ] && [ "$(wc -l < "$STUB/looks")" -ge 2 ] \
    || fail "the looks at the hold did not run the control alone on main, again once it failed: $(cat "$STUB/looks")"
  [ ! -e "$ST/machinehold.json" ] || fail "the hold stayed after the control passed: $(cat "$ST/machinehold.json")"
  [ "$(st 'select(.step == "test" or .step == "fix") | "\(.step) \(.result)"' | tr '\n' ,)" = "test held,test pass," ] && [ "$(ran 3)" = flaky ] \
    || fail "the card on hold did not test again once the control passed, or went to a fix: $(st '"\(.step) \(.result)"' | tr '\n' ,)"
  [ "$(st 'select(.step == "landed") | .issue')" = 7 ] || fail "the card did not land: $(st '"\(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  loop check || fail "the record check refuses a test line with the verdict machine"
  [ "$(loop snapshot | jq -c '[.landed[0].track.records[] | select(.name | startswith("tests")) | [.name, .state]]')" = '[["tests held: the machine","done"],["tests passed","done"]]' ] \
    || fail "the card's track shows the machine's hold as a failed test step: $(loop snapshot | jq -c '.landed[0].track.records')"
}

# D4: the hold stands; the control passes on main now. Bug it catches: a loop held for good once the machine was
# mended. A `run` looks at the hold once, the control passes, the hold goes and the loop picks #7 again.
t_machineresume() {
  holdsetup
  local out
  eng 'machinehold c1 "$(git rev-parse HEAD)" "[\"c.test\"]" "[\"b.test: flaky\"]"' || fail "the hold could not be written"
  out=$(loop run 1 2>&1) || fail "run exited non-zero: $out"
  [ "$(cat "$STUB/looks" 2>&1)" = 'fail:c.test|' ] || fail "the loop did not run the control alone on main: $(cat "$STUB/looks" 2>&1)"
  [ ! -e "$ST/machinehold.json" ] || fail "the hold stayed after the control passed: $(cat "$ST/machinehold.json")"
  [ "$(st 'select(.step == "picked") | .issue')" = 7 ] || fail "the loop did not pick again once the control passed: $out"
}
