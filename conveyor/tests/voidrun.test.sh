#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a card's test run that gives no result (voidrun(): killed by a signal, as by the service stopping or
# restarting) proves nothing; the test command itself is never a case failing on main (mainred.sh verdicts(), mainred()).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# rerunsetup's command (rerun.test.sh), with its test files run each alone as a card runs them (rerunfiles), and on a
# run the plan names `<run> term` it is killed by TERM as it begins, before its runner logs a line, as the service
# stopping killed it. The TERM goes to the run's timeout (testonce()), the parent of the per-file command (filecmd(),
# lib/testrun.sh), whose own timeout of the file is the stub's parent ($PPID): TERM to that one would end only the file,
# which filecmd() logs as failed, a result. Each run killed so is a line of $STUB/termed.
voidsetup() { # <plan lines>
  rerunsetup "$@"; rerunfiles
  echo '! grep -qxF "$n term" "$STUB/plan" || { echo "$n" >> "$STUB/termed"; kill -TERM "$(ps -o ppid= -p "$(ps -o ppid= -p "$PPID" | tr -d " ")")"; sleep 30; }' > "$STUB/pre" # sleep: until the TERM sent to the run's timeout (testonce()) ends the run; tr: ps pads a short PID with spaces, which ps -p refuses
}
voidsteps() { st 'select(.step == "test" or .step == "fix") | [.step, .result, (.reason // "" | select(. != "") | sub(": .*"; ""))] | join(" ")' | tr '\n' ,; }

# Issue 218. Bug it catches: a service restart killed a card's test run before its runner logged a line, and main's
# run of it was killed too; the whole test command was recorded as a case failing on main, a main-red card opened for
# it, and the card waited for main to move. Here each of the card's runs 1 and 2 (its first test step and its run
# again) and main's run are killed by TERM: the step gives no result, runs nothing on main, writes no main-red record
# and does not wait; the step runs again. That run fails c.test's three (a result: main's run of it, killed, says
# nothing, so the case is the card's) and goes to its fix session, and the count of runs with no result starts again.
# Then three steps in a row give no result: the card blocks saying so. Without the count starting again it would
# block one step sooner.
t_voidrun() {
  voidsetup '1 term' '2 term' '3 fail three' '4 fail three' 'main term' '5 term' '6 term' '7 term' '8 term' '9 term' '10 term'
  local lp
  ( loop run 1 > "$STUB/run.out" 2>&1 ) & lp=$!
  wait_until "[ -n \"\$(st 'select(.step == \"blocked\") | .card')\" ] || grep -qs 'waiting for main' \"\$T/\$CASE/cards/\"*.live" 'cat "$STUB/run.out"' \
    || fail "the card neither blocked nor waited: $(cat "$STUB/run.out")"
  [ ! -e "$ST/mainred.json" ] || { kill "$lp"; fail "a run with no result was recorded as main failing: $(cat "$ST/mainred.json")"; }
  ! grep -qs 'waiting for main' "$T/$CASE/cards/"*.live || { kill "$lp"; fail "a run with no result made the card wait for main"; }
  wait "$lp"
  [ "$(voidsteps)" = "test fail no result,test fail exit 1,fix ok,test fail no result,test fail no result,test fail no result," ] \
    || fail "the steps are not a rerun after no result, a fix of the result, and three runs with no result: $(voidsteps)"
  [ "$(st 'select(.step == "blocked") | .reason')" = "the changed tests gave no result 3 times in a row (exit 143: the run was killed by a signal); nothing landed." ] \
    || fail "the card did not block saying its runs gave no result: $(st 'select(.step == "blocked") | .reason')"
  # Main's run is of the failing file alone (mainred.sh verdicts(): its list names each failing file, not its cases).
  [ "$(tline 1 '[.verdicts, .mainRun] | tojson')" = '[null,null]' ] && [ "$(sed -n 's/^fail\t//p' "$STUB/rerun.main" | tr '\t\n' ':|')" = "c.test|" ] \
    || fail "a run with no result ran on main: $(tline 1 tojson): $(cat "$STUB/rerun.main" 2>&1)"
  # Main's run of the case was killed: the stub sent the TERM, and the test line's main run ended on it (exit 143).
  # #1435: a main run that passed gives the same verdict below, so the kill is checked here.
  grep -qx main "$STUB/termed" && [ "$(tline 2 '.mainRun.exit')" = 143 ] || fail "main's run of c.test was not killed: $(cat "$STUB/termed" 2>&1), $(tline 2 .mainRun)"
  [ "$(tline 2 '.verdicts | tojson')" = '[{"case":"c.test: three","verdict":"card"}]' ] || fail "a killed run on main gave the case to main: $(tline 2 .verdicts)"
}

# Issue 218. Bug it catches: a card's run that failed before its runner logged a line is named by the test command
# (testfails()); main's run of it, killed, is named so too, and the command went to the main-red record as a case, so
# the card waited for main (or, with main's run passing, the command was the card's case and went to a fix session).
# The command names no test: the run gave no result (voidrun()), so card() runs nothing on main, starts no fix session
# and runs the test step again, as t_voidrun's card does. Neither mainred.sh verdicts() nor mainred.sh mainred(), asked of the command alone,
# records it as a case. Since #374 a card's run goes through filecmd() (lib/testrun.sh), which logs each file it runs
# before the file's command starts, so a card's whole run cannot make a run with no log: voidrun() is asked of one.
# A run whose log names the file it ran and failed (as filecmd() logs it) is a result.
t_voidcommand() {
  rerunsetup
  local cmd w=$T/$CASE/void
  cmd=$(jq -r .test.command "$R/.conveyor/project.json")
  mkdir -p "$w.testlog" && echo 'bash: the test command failed' > "$w.test" || fail "the run with no log could not be made"
  # shellcheck disable=SC2034 # HERE is read by the lines the eval sources
  ( set -- run; HERE=$SRC; export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    eval "$(sed -n '/^\. "\$HERE\/lib\/portable.sh"/,/^\. "\$HERE\/lib\/records.sh"/p' "$SRC/conveyor.sh"; grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")"
    # shellcheck disable=SC2034 # read by mainred.sh verdicts() and mainred(), defined by the eval
    names || exit 1; cd "$R" || exit 1; TEST_WAIT=0 TEST_RUN=0 TEST_FREE=0
    [ "$(voidrun "$w" 1)" = "exit 1: the run named no test that failed, only the test command" ] || exit 2
    printf '%s\n' 'TESTRUN files=1' '== a.test.sh' '-- FAIL a.test.sh' > "$w.testlog/files"
    ! voidrun "$w" 1 || exit 3
    [ "$(verdicts c1 "$T/$CASE/none" "$(jq -cn --arg c "$cmd" '{files: [{file: $c, cases: []}]}')")" = '{"verdicts":[]}' ] || exit 4
    ! mainred c1 "$cmd" "$cmd" "$(git rev-parse HEAD)" || exit 4 ) > /dev/null 2>&1
  case $? in
    0) ;;
    1) fail "the engine's names could not be read, or the case's main could not be entered" ;;
    2) fail "a failed run that logged no file, named only by the test command, was not taken as a run with no result" ;;
    3) fail "a failed run whose log names the file that failed was taken as a run with no result" ;;
    *) fail "verdicts() or mainred() took the test command as a case" ;;
  esac
  [ ! -e "$ST/mainred.json" ] || fail "a red record whose only case is the test command was written: $(cat "$ST/mainred.json")"
}

# Done when 2 (#1310). Bug it catches: a run whose filter matched no case (a runner may exit 0 on a name filter that
# matches none of its cases) passed, so the card's test step said its failed case passed on re-run. Each file's runner
# says it writes a record of each case it runs (results/ of the log folder, as tests/lib.sh does), and here writes
# none, as the stub runs no case: c.test's case three fails in the first run, and the run again, given that case
# alone, runs no case and exits 0. tests() gives no result, not a pass: exit 1, and voidrun()'s reason names the file
# and its filter. rerunwt and rerunstep (rerun.test.sh) run tests() on the card's worktree, as card() runs it.
t_voidnocase() {
  rerunwt 'echo two > a.txt' '1 fail three'
  # shellcheck disable=SC2016 # expanded where the test command sources it
  echo 'mkdir -p "$CONVEYOR_TEST_LOG/results" && jq -cn --arg f "$CONVEYOR_TEST_FILE" "{file: \$f}" > "$CONVEYOR_TEST_LOG/results/runner.$$"; [ "$n" != 2 ] || exit 0' > "$STUB/pre"
  local w=$T/$CASE/cards/c7 got
  ! rerunstep || fail "a run again whose filter of c.test (three) ran no case passed: $(cat "$w.test")"
  got=$(eval "$(sed -n '/^voidrun() {/,/^}/p' "$SRC/lib/testrun.sh")"; voidrun "$w" 1) \
    && [ "$got" = "c.test: its filter (three) ran no case, and the run passed" ] && [ "$(sed -n 's/^fail\t//p' "$STUB/rerun.2" | tr '\t' :)" = c.test:three ] \
    || fail "the run again given c.test's case three alone (list: $(tr '\t\n' ':|' < "$STUB/rerun.2" 2>&1)) gave no reason of no result: '$got' ($(cat "$w.test"))"
}
# Issue 1310. Bug it catches: in a run again that failed (a.test's case one fails again), a file whose filter ran no
# case (c.test, given its failed case three, runs none and exits 0) went into the list as passed (`pass c.test`), so
# the next run left it out and the card could land with case three never run. The list keeps c.test's `fail` line.
t_voidnocasefail() {
  rerunwt 'echo two > a.txt' '1 fail one' '1 fail three' '2 fail one'
  # shellcheck disable=SC2016 # expanded where the test command sources it
  echo '[ "$n" != 2 ] || [ "$CONVEYOR_TEST_FILE" != c.test ] || { mkdir -p "$CONVEYOR_TEST_LOG/results" && jq -cn --arg f c.test "{file: \$f}" > "$CONVEYOR_TEST_LOG/results/runner.$$"; exit 0; }' > "$STUB/pre"
  local w=$T/$CASE/cards/c7
  ! rerunstep || fail "a run again whose a.test case one failed passed: $(cat "$w.test")"
  [ "$(ran 2)" = one ] && ! grep -qxF $'pass\tc.test' "$w.rerun" && grep -qxF $'fail\tc.test\tthree' "$w.rerun" \
    || fail "after a run again that failed and ran no case of c.test (ran: $(ran 2)), the list does not keep c.test's case three to run: $(tr '\t\n' ':|' < "$w.rerun" 2>&1)"
}
