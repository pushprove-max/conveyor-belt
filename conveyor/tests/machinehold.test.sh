#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the machine verdict (mainred.sh verdicts(), issue 221). A case that fails on the card and on main is main's only
# when an input of its file changed since its last recorded pass and a control passes beside it on the same slot;
# otherwise it is the machine's: no main-red entry, no wait for main, the loop picks no card (mainred.sh machineheld()) until the
# controls pass on main again (mainred.sh machineprobe()), and the cards on hold test again.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# rerunsetup's three test files and command (tests/rerun.test.sh): a.test, b.test and c.test, whose cases fail as
# $STUB/plan says; c.test is the pack's control (test.control). b.txt and c.txt are committed on main as the inputs of
# b.test and c.test. The run of main's look at the hold (mainred.sh machineprobe(), in cards/mainrun/machine) is run `main`, as
# the run of a card's failing cases on main is, its list in $STUB/rerun.main; it marks each of its runs in $STUB/looks.
holdsetup() { # <plan lines>...
  rerunsetup "$@"; rerunfiles
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
# main-red fix card and every card behind it waited. The verdict is machine (the Test step goes to the machine hold,
# testroute()): no main-red entry, the hold names the control (and not b.test, which may fail on main for good),
# health shows it for the Foreman's wake, and the loop picks nothing: its one look at the hold fails the control
# again, so `run` ends saying so. No card runs.
t_machinecontrol() {
  holdsetup 'main fail flaky' 'main fail three'
  local out
  holdpass $'b.test\tb.txt' $'c.test\tc.txt'
  echo b2 > "$R/b.txt"; git -C "$R" commit -qam "b.test's input changes" || fail "main could not move"
  out=$(holdjudge) || fail "verdicts failed: $out"
  [ "$out" = '[{"case":"b.test: flaky","verdict":"machine"}]' ] || fail "a failing control did not give the verdict machine: $out"
  # The Test step goes to the repair lane, then the machine hold (testroute(): machine), not to the wait for main.
  [ "$(mrroute verdicts "{\"verdicts\":$out}")" = machine ] || fail "testroute verdicts did not send the card to the machine hold, given {\"verdicts\":$out}: $(mrroute verdicts "{\"verdicts\":$out}")"
  # Each failing file runs on main alone and whole (#374), so the list names b.test, not its case.
  [ "$(grep $'^fail\t' "$STUB/rerun.main" | tr '\t\n' ':|')" = "fail:b.test|fail:c.test|" ] \
    || fail "main's run did not run the control beside the failing case: $(cat "$STUB/rerun.main")"
  [ ! -s "$ST/mainred.json" ] || fail "the machine's failure opened a main-red entry: $(cat "$ST/mainred.json")"
  [ "$(jq -c '[.card, .controls, .cases]' "$ST/machinehold.json")" = '["c7",["c.test"],["b.test: flaky"]]' ] \
    || fail "the hold does not name the failing control: $(cat "$ST/machinehold.json" 2>&1)"
  [ "$(loop health | jq -c '.machineHold.controls')" = '["c.test"]' ] || fail "health does not show the hold: $(loop health | jq -c .machineHold)"
  # loop: run() itself refuses to pick while the hold stands (its exit, no picked line, its message); no function gives that, and it runs no card
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

# Issue 229: the run of the failing cases on main keeps to its one slot. Bug it catches: a runner of the command (this
# project's .conveyor/test-changed.sh) gave its workers other slots of the pool, so the control passed on one slot and
# said nothing of the slot a failing case ran on. In a pool of 2, main's run holds slot 1; its runner's second worker,
# asked for while the first is on slot 1 and slot 2 is free, must wait for slot 1, not take slot 2.
t_machineoneslot() {
  mkdir -p "$XDG_CONFIG_HOME/conveyor" && echo "{\"testSlots\": 2, \"testSlotsDir\": \"$T/$CASE/slots\"}" > "$XDG_CONFIG_HOME/conveyor/host.json"
  holdsetup 'main fail flaky'
  local out
  [ "$(nproc --all)" -ge 2 ] || fail "the case needs a pool of 2 slots, and this machine has one core"
  # The first worker holds slot 1 (its lock) until the second has a slot, or 4 s with the fix, under which the second
  # waits for it: a fixed sleep ended first on a busy machine, and the second worker then had slot 1 without the fix.
  echo 'case $PWD in */mainrun/c7) . "$CONVEYOR_TEST_SLOTS"; slot_pool; slot_take; (i=0; while [ ! -e "$STUB/took" ] && [ $i -lt 40 ]; do sleep 0.1; i=$((i + 1)); done) & slot_free; slot_take; : > "$STUB/took"; echo "$SLOT_HOME_K $SLOT_K" > "$STUB/oneslot"; slot_free ;; esac' > "$STUB/pre" # sleep: the stub runs in the test command's shell, which has no wait_until
  out=$(holdjudge) || fail "verdicts failed: $out"
  [ "$(cat "$STUB/oneslot" 2>&1)" = "1 1" ] || fail "main's run beside the controls gave a worker another slot (home slot, worker's slot): $(cat "$STUB/oneslot" 2>&1)"
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
  # loop: card() writes the held test line and its message, then waits for the loop's look to end the hold; no function gives them
  ( loop run 1 > "$STUB/run.out" 2>&1 ) & lp=$!
  wait_until "$waiting" 'cat "$STUB/run.out"' || fail "the card did not wait for the machine: $(cat "$STUB/run.out")"
  # Bug it catches too: a card the repair lane does not pass (c.test fails in the clean harness with its change too)
  # not told why. The loop's message (card()) is checked here; t_repairempty checks mainred.sh repairlane()'s other reason.
  grep -qF 'the repair lane did not pass it (c.test still failed with the change in a clean harness): it waits until the machine passes its controls again' "$STUB/run.out" \
    || fail "the loop did not say why the lane did not pass the card: $(grep -F 'repair lane' "$STUB/run.out")"
  # Bug it catches too: the machine's failure counted as the card's failed test step (result fail, "tests failed").
  [ "$(tline 1 '[.result, .verdicts] | tojson')" = '["held",[{"case":"b.test: flaky","verdict":"machine"}]]' ] \
    || fail "the test line is not held with the verdict machine: $(tline 1 tojson)"
  [ ! -s "$ST/mainred.json" ] && ! grep -qs "waiting for main to change" "$T/$CASE/cards/"*.live \
    || fail "the machine's failure opened a main-red entry or a wait for main: $(cat "$ST/mainred.json" 2>&1)"
  # A look that has ended (its worktree gone): one still running when the plan changes below would pass at once.
  wait_until '[ -s "$STUB/looks" ] && [ ! -e "$T/$CASE/cards/mainrun/machine" ]' 'cat "$STUB/run.out"' || fail "the loop did not look at the hold: $(cat "$STUB/run.out")"
  [ -e "$ST/machinehold.json" ] || fail "a look that failed the control ended the hold"
  sed -i '/^main fail three$/d' "$STUB/plan"
  wait "$lp" || fail "run exited non-zero: $(cat "$STUB/run.out")"
  [ "$(sort -u "$STUB/looks")" = 'fail:c.test|' ] && [ "$(wc -l < "$STUB/looks")" -ge 2 ] \
    || fail "the looks at the hold did not run the control alone on main, again once it failed: $(cat "$STUB/looks")"
  [ ! -e "$ST/machinehold.json" ] || fail "the hold stayed after the control passed: $(cat "$ST/machinehold.json")"
  # The held line keeps its run's own reason, exit 1: the repair lane, which did not pass the card, gave it none.
  [ "$(st 'select(.step == "test" or .step == "fix") | "\(.step) \(.result) \(.reason)"' | tr '\n' ,)" = "test held exit 1,test pass ," ] && [ "$(ran 3)" = flaky ] \
    || fail "the card on hold did not test again once the control passed, or went to a fix: $(st '"\(.step) \(.result)"' | tr '\n' ,)"
  [ "$(st 'select(.step == "landed") | .issue')" = 7 ] || fail "the card did not land: $(st '"\(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  loop check || fail "the record check refuses a test line with the verdict machine"
  [ "$(loop snapshot --fresh | jq -c '[.landed[0].track.records[] | select(.name | startswith("tests")) | [.name, .state]]')" = '[["tests held: the machine","done"],["tests passed","done"]]' ] \
    || fail "the card's track shows the machine's hold as a failed test step: $(loop snapshot --fresh | jq -c '.landed[0].track.records')"
}

# D4: the hold stands; the control passes on main now. Bug it catches: a loop held for good once the machine was
# mended. A `run` looks at the hold once, the control passes, the hold goes and the loop picks #7 again.
t_machineresume() {
  holdsetup
  local out
  eng 'machinehold c1 "$(git rev-parse HEAD)" "[\"c.test\"]" "[\"b.test: flaky\"]"' || fail "the hold could not be written"
  # loop: the machine's own loop: only run() looks at the hold and picks again once it goes
  out=$(loop run 1 2>&1) || fail "run exited non-zero: $out"
  [ "$(cat "$STUB/looks" 2>&1)" = 'fail:c.test|' ] || fail "the loop did not run the control alone on main: $(cat "$STUB/looks" 2>&1)"
  [ ! -e "$ST/machinehold.json" ] || fail "the hold stayed after the control passed: $(cat "$ST/machinehold.json")"
  [ "$(st 'select(.step == "picked") | .issue')" = 7 ] || fail "the loop did not pick again once the control passed: $out"
}

# The repair lane (issue 222). Main has a harness of its own, conveyor/lib/slots.sh, whose harness() fails: under it
# the control c.test fails ('broken fail three'). The card's own runs, under the running engine's harness, fail b.test's
# flaky, and main's run fails it and c.test beside it: the verdict is machine, and the hold names c.test. A run in a
# clean harness (CONVEYOR_TEST_SLOTS not the running engine's) adds a line to $STUB/clean: the folder it ran in,
# whether the harness it was given passed, the command that leads its session (the clean run's `timeout`, in a
# session of its own: each file runs under a `timeout` of its own inside it, filecmd()), the descriptors above 2 it
# holds, the CONVEYOR_MAIN it was given and the harness it was named. main links the harness to b.test, so a card that
# changes only the harness runs b.test (each card runs only the test files linked to its change, #374).
repairsetup() {
  holdsetup '1 fail flaky' '2 fail flaky' 'main fail flaky' 'main fail three' 'broken fail three'
  mkdir -p "$R/conveyor/lib" && echo 'harness() { return 1; }' > "$R/conveyor/lib/slots.sh" \
    && git -C "$R" add -f conveyor &&git -C "$R" commit -qm "a harness that fails" || fail "main's harness could not be committed"
  linkset '{"a.txt": ["a.test", "b.test", "c.test"], "conveyor/lib/slots.sh": ["b.test"]}'
  tune --arg s "$STUB" '.test.fileCommand = "STUB=\($s); " + .test.fileCommand | .test.command = .test.fileCommand | .tunables.poll = 1' # a clean run is given no STUB
  holdpass $'c.test\tc.txt'
  cat >> "$STUB/pre" <<EOF
case \${CONVEYOR_TEST_SLOTS:-} in "$SRC"/*) ;; *)
  if . "\$CONVEYOR_TEST_SLOTS" && harness; then n=mended; else n=broken; fi
  fds=''; for f in /dev/fd/*; do f=\${f##*/}; [ "\$f" -le 2 ] || [ ! -e "/dev/fd/\$f" ] || fds="\$fds \$f"; done
  s=\$(ps -o comm= -p "\$(python3 -c 'import os; print(os.getsid(0))')"); s=\${s##*/}
  echo "\${PWD##*/} \$n sid=\$s fds=[\${fds# }] main=\${CONVEYOR_MAIN-unset} slots=\${CONVEYOR_TEST_SLOTS#"\$PWD"/}" >> "\$STUB/clean" ;;
esac
EOF
}
# The clean runs' lines with what every clean run must show taken out: a session of its own, no descriptor above 2,
# none of the loop's environment, and the worktree's own harness.
cleanruns() { sed -E 's/ sid=timeout fds=\[\] main=unset slots=conveyor\/lib\/slots.sh$//; s/^c[^ ]*-7/card/' "$STUB/clean" | tr '\n' ,; }

# D1, D2, D4: a card whose change mends main's harness. Bug it catches: a fix to the test step was judged by the
# harness it repairs, so it could never pass its own test step (two such cards were landed by hand). Its test step is
# held by the machine; the repair lane runs c.test on main's code without the change (it fails) and with it (it
# passes), then the card's changed tests, each in a clean harness that is the worktree's own; the card lands, though
# the hold still stands.
t_repairlands() {
  repairsetup
  local out lp
  echo 'echo "harness() { return 0; }" > conveyor/lib/slots.sh' > "$STUB/build"
  # loop: card() writes the pass line with the lane's reason and lands while the hold stands; no function gives them
  ( loop run 1 > "$STUB/run.out" 2>&1 ) & lp=$!
  # A card the lane does not pass waits for the machine: the control is mended then, so that the run ends.
  wait_until '[ -n "$(st '"'"'select(.step == "landed") | .issue'"'"')" ] || grep -qs "waiting for the machine" "$T/$CASE/cards/"*.live' 'cat "$STUB/run.out"' \
    || fail "the card neither landed nor waited: $(cat "$STUB/run.out")"
  [ -n "$(st 'select(.step == "landed") | .issue')" ] || sed -i '/^main fail three$/d' "$STUB/plan"
  wait "$lp"; out=$(cat "$STUB/run.out")
  [ "$(cleanruns)" = 'card.repair broken,card.repair mended,card mended,' ] \
    || fail "the repair lane did not run the control without and with the change, then the changed tests, each in a clean harness of the worktree's own: $(cat "$STUB/clean" 2>&1)"
  [ "$(st 'select(.step == "test") | .result' | tr '\n' ,)" = 'held,pass,' ] && [[ $(tline 2 .reason) == "repair lane: c.test failed on main's code at "* ]] \
    || fail "the card's test step was not passed by the repair lane: $(st 'select(.step == "test") | "\(.result) \(.reason)"' | tr '\n' ,)"
  [ "$(st 'select(.step == "landed") | .issue')" = 7 ] || fail "the repair card did not land: $out"
  [ -e "$ST/machinehold.json" ] || fail "the repair lane ended the hold, which only the controls passing on main end"
  loop check || fail "the record check refuses the repair lane's test line"
}

# A card the repair lane does not pass: its change, made by <edit> in its worktree c-7 on main and staged, judged by
# mainred.sh repairlane() itself under the hold repairsetup's main gives (c.test). It does not pass, says why, and gives the lane
# up while its process still runs. (That such a card then waits for the machine and lands once the hold goes, on a
# test step of its own, is t_machinecard's whole card run, whose card the lane does not pass either.)
repairheld() { # <edit> <the clean runs, as cleanruns() gives them> <why the lane did not pass it>
  local out
  eng 'machinehold c-7 "$(git rev-parse HEAD)" "[\"c.test\"]" "[\"b.test: flaky\"]"' || fail "the hold could not be written"
  rulewt c-7 "$1"
  out=$(eng 'repairlane c-7 "$CONVEYOR_CARDS/c-7"; echo "$? [$(repairholder)] $REPAIRED"')
  [ "$(cleanruns)" = "$2" ] || fail "the lane's clean runs are not $2: $(cat "$STUB/clean" 2>&1)"
  [ "$out" = "1 [] $3" ] || fail "the lane passed the card, kept the lane (in brackets) or did not say why it did not pass it: $out"
}
# D1, D4: a card that does not mend the harness (its build changes a.txt). Bug it catches: a card let through the
# lane by its change alone. c.test fails in the clean harness with the change too.
t_repairnot() {
  repairsetup
  repairheld 'echo two >> a.txt' 'card.repair broken,card.repair broken,' 'c.test still failed with the change in a clean harness'
}
# D1: a card whose change makes the harness end the run at once with exit 0, so that nothing runs. Bug it catches: a
# run that passed by running nothing taken for the controls passing: each file's run that exits 0 is logged ok (#374),
# so the lane asks the run's logs for c.test's pass and for a case that passed.
t_repairempty() {
  repairsetup
  repairheld 'echo "exit 0" > conveyor/lib/slots.sh' 'card.repair broken,' 'the run with the change passed, but its logs do not say that c.test passed in it'
}
# R137: with test.coverage set, card c-7 mends the harness, its earlier run (held by the machine) having left a
# coverage that says the changed line of conveyor/lib/slots.sh was not reached; the lane's clean run of the card's
# changed tests writes a report that reaches it. Bug it catches: the lane never read its own run's report, so the
# test pass line (testrec(), as card() writes it after the lane) gave the held run's coverage.
t_repaircoverage() {
  repairsetup
  local out
  tune '.test.coverage = {format: "lcov", path: "cov.info"}'
  echo 'case ${PWD##*/} in c-7) printf "SF:conveyor/lib/slots.sh\nDA:1,1\nend_of_record\n" > cov.info ;; esac' >> "$STUB/pre"
  eng 'machinehold c-7 "$(git rev-parse HEAD)" "[\"c.test\"]" "[\"b.test: flaky\"]"' || fail "the hold could not be written"
  rulewt c-7 'echo "harness() { return 0; }" > conveyor/lib/slots.sh'
  echo '{"uncovered":[{"file":"conveyor/lib/slots.sh","lines":"1"}],"count":1,"checked":1}' > "$T/$CASE/cards/c-7.uncovered"
  out=$(eng 'repairlane c-7 "$CONVEYOR_CARDS/c-7"; echo "$? $(testrec "$CONVEYOR_CARDS/c-7" 0 0 | jq -c .coverage)"')
  [ "$out" = '0 {"uncovered":[],"count":0,"checked":1}' ] \
    || fail "the repair lane's pass did not give its clean run's coverage (exit, then coverage): $out ($(cat "$STUB/clean" 2>&1))"
}
# D1: the card adds a test file, d.test, which main's commit lacks, and main's harness is sound, so c.test passes there.
# The stub fails any run given a file that is not there: it stands for a pack whose test.fileCommand runs each file
# CONVEYOR_TEST_FILES names (this project's .conveyor/test-changed.sh --file runs only the file it is given, so it would
# not fail). Bug it catches: the lane gave the control's run without the change the card's test files, so c.test's own
# run (each file runs alone, #374) failed on d.test, and the lane took that for the control's failure and passed a
# card whose control passes without its change. The control's runs are given none of the card's files: c.test passes, and the lane says so.
t_repairbaseline() {
  repairsetup
  local out
  echo 'harness() { return 0; }' > "$R/conveyor/lib/slots.sh" && git -C "$R" commit -qam "a sound harness" || fail "main's harness could not be mended"
  echo 'while IFS= read -r f; do [ -z "$f" ] || [ -e "$f" ] || { echo "bash: $f: No such file or directory"; exit 1; }; done <<<"${CONVEYOR_TEST_FILES:-}"' >> "$STUB/pre"
  echo '{"controls":["c.test"]}' > "$ST/machinehold.json"
  git -C "$R" worktree add -q --detach "$T/$CASE/cards/c7" && echo new > "$T/$CASE/cards/c7/d.test" && git -C "$T/$CASE/cards/c7" add d.test \
    || fail "the card's worktree could not be made"
  out=$(eng 'TEST_FILES=d.test; repairproof c7 "$CONVEYOR_CARDS/c7"; echo "$? $REPAIRED"')
  [[ $out == "1 c.test passed on main's code at "*" without the change in a clean harness, so the change repairs nothing there" ]] \
    || fail "the lane took the card's own missing test file for the control's failure: $out"
}

# D1, D4: card c1 takes the repair lane through mainred.sh repairlane() and is judged (a mainred.sh repairproof() that does not end here).
# Bugs it catches: two repair cards judged at once, each against a main the other changes; and a lane recorded with
# the start time of a process other than c1's (c1's process starts over a second before it takes the lane, so the
# two times differ), which another card takes for a free lane. A second card is refused the lane and waits, saying
# so, until c1's process ends; then it stops waiting, though the hold stands, to be tested and judged again.
t_repairwait() {
  holdsetup
  local sp hw rc=0
  eng 'machinehold c1 "$(git rev-parse HEAD)" "[\"c.test\"]" "[\"b.test: flaky\"]"' || fail "the hold could not be written"
  ( eng 'sleep 1.5; repairproof() { while :; do sleep 0.2; done; }; repairlane c1 "$CONVEYOR_CARDS/c1"' ) & sp=$! # sleep: c1's process must start over a second before it takes the lane, so the two start times differ
  wait_until '[ "$(eng repairholder)" = c1 ]' || fail "card c1 did not hold the lane while its process runs: $(cat "$ST/machinehold.json.lane" 2>&1)"
  sp=$(jq -r .pid "$ST/machinehold.json.lane") # c1's process, which holds the lane while it runs
  eng 'repairlane c2 "$CONVEYOR_CARDS/c2"' || rc=$?
  [ $rc = 2 ] || fail "a second card was not refused the lane c1 holds (exit $rc)"
  mkdir -p "$T/$CASE/cards"; ( eng 'LIVE=1; holdwait "$CONVEYOR_CARDS/c2" lane' ) & hw=$!
  wait_until 'grep -qs "waiting for the repair lane: card c1 is judged by the controls" "$T/$CASE/cards/c2.live"' || fail "the second card did not wait for the lane"
  kill -0 "$hw" 2>/dev/null || fail "the second card stopped waiting while c1 held the lane"
  kill "$sp"; wait "$sp" 2>/dev/null
  wait_until '[ ! -e "$T/$CASE/cards/c2.live" ]' || fail "the second card did not stop waiting once c1's process ended"
  wait "$hw" || fail "the second card's wait failed"
  [ -e "$ST/machinehold.json" ] && [ -z "$(eng repairholder)" ] || fail "the hold went, or the lane is still held"
}
