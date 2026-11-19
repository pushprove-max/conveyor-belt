#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the check on main of a card's failing cases (verdicts(), issue 420) runs under the card's test time
# limit, which timeout itself keeps, and with the pack's test.fileCommand each failing file runs alone through it.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# verdicts() of card c7 (its worktree on main) for the failing cases <testfails() json>, as card() asks it.
limitjudge() { # <testfails() json>
  git -C "$R" worktree add -q --detach "$T/$CASE/cards/c7" || fail "the card's worktree could not be made"
  printf '%s\n' "$1" > "$STUB/fails"
  eng 'TEST_WAIT=; TEST_RUN=; TEST_FREE=; verdicts c7 "$CONVEYOR_CARDS/c7" "$(cat "$STUB/fails")" | jq -c .'
}

# Bug it catches (#398, #380): the check on main ran as `timeout 0`, no limit, and a runner of it waiting for a
# whole-suite turn stops the run's own clock (testclock), so it ran for 30+ minutes and the card made no new step.
# With no testTimeout in the pack, main's run is started under a limit timeout keeps: the setting's default.
t_mainlimit() {
  rerunsetup 'main fail flaky'
  tune 'del(.tunables.testTimeout)'
  # Of the command's parents, the run's timeout (testonce(), `--kill-after=30`; the file's own, filecmd(), is
  # `--kill-after=10`): its limit is the word after --kill-after.
  echo 'case $PWD in */mainrun/*) p=$PPID; while [ "${p:-1}" -gt 1 ]; do a=$(ps -o args= -p "$p"); case $a in *"timeout --kill-after=30 "*) echo "$a" > "$STUB/limit"; break ;; esac; p=$(ps -o ppid= -p "$p" | tr -d " "); done ;; esac' > "$STUB/pre"
  local out n
  out=$(limitjudge '{"files":[{"file":"b.test","cases":[{"name":"flaky","line":1}]}]}') || fail "verdicts failed: $out"
  n=$(awk '{ for (i = 1; i < NF; i++) if ($i ~ /^--kill-after=/) { print $(i + 1); exit } }' "$STUB/limit" 2>/dev/null)
  [ "$n" = 3600 ] || fail "main's run was not started under testTimeout's default limit: $(cat "$STUB/limit" 2>&1)"
}

# Bug it catches: with test.fileCommand set, the check on main ran test.command with a list (list mode), not each
# failing file alone as the card's own run does. Here a.test fails two cases and b.test one: the file command runs
# a.test and b.test, each once, test.command does not run on main, and a.test's case read from its run is main's.
t_mainfilecmd() {
  rerunsetup
  printf '%s\n' 'echo "$1" >> "$STUB/filecmd"; [ "$1" = a.test ] && echo "FAIL [one]: wrong" && exit 1; echo "ok flaky"' > "$STUB/file-cmd"
  tune --arg c "bash $STUB/file-cmd" '.test.fileCommand = $c'
  local out
  out=$(limitjudge '{"files":[{"file":"a.test","cases":[{"name":"one","line":1},{"name":"two","line":2}]},{"file":"b.test","cases":[{"name":"flaky","line":1}]}]}') \
    || fail "verdicts failed: $out"
  [ "$(sort "$STUB/filecmd" 2>&1 | tr '\n' ' ')" = "a.test b.test " ] || fail "the file command did not run each failing file once: $(cat "$STUB/filecmd" 2>&1)"
  [ ! -e "$STUB/rerun.main" ] || fail "test.command ran on main in list mode: $(cat "$STUB/rerun.main")"
  [ "$(jq -c '[.verdicts[] | select(.case == "a.test: one") | .verdict]' <<<"$out")" = '["main"]' ] \
    || fail "a.test's case failing in the file command's run on main was not main's: $out"
}

# Bug it catches: a check on main that hangs, its runner waiting for a whole-suite turn (which stops the run's clock),
# held the card in its test step with no new step. It ends at the card's limit (exit 124), says nothing of the case
# (the case is the card's), and the card goes on to its fix session and tests again.
t_mainhang() {
  rerunsetup '1 fail flaky' '2 fail flaky'; rerunfiles
  tune '.tunables.testTimeout = 5'
  echo 'case $PWD in */mainrun/*) echo 999999 > "$CONVEYOR_TEST_TURNWAIT"; sleep 60 ;; esac' > "$STUB/pre" # sleep: a run that hangs, ended only by its limit
  loop run 1 > "$STUB/run.out" 2>&1 || fail "run exited non-zero: $(cat "$STUB/run.out")"
  [ "$(tline 1 '[.mainRun.exit, .verdicts] | tojson')" = '[124,[{"case":"b.test: flaky","verdict":"card"}]]' ] \
    || fail "main's hanging run did not end at its limit with the case the card's: $(tline 1 tojson)"
  [ "$(st 'select(.step == "test" or .step == "fix") | "\(.step) \(.result)"' | tr '\n' ,)" = "test fail,fix ok,test pass," ] \
    || fail "the card did not go on to its fix session: $(st 'select(.step == "test" or .step == "fix") | "\(.step) \(.result)"' | tr '\n' ,)"
}
