#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the check of the Board's Make it run alone card (#190; aloneproof(), conveyor/lib/testrun.sh): the
# pack as the change leaves it no longer marks the file wholeOnly, and the file runs alone through the pack's
# test.fileCommand, on a test slot, and passes. fx_in and fx_wt are in lib.sh.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Card c7's check of w.test.sh, which main's pack marks wholeOnly, with a test.fileCommand that runs the file it is
# given (each run's file added to $STUB/alone-args, a line a run). <change> is made in the card's worktree; with
# nofile, the pack sets no test.fileCommand.
alonerun() { # <change> [nofile]
  setup '[]'
  printf '%s\n' 'echo "${ALONE_MARK:+$ALONE_MARK }$1" >> "$STUB/alone-args"; bash "$1"' > "$STUB/alone-runner"
  # The pack is tracked, as a project's is, so the card's change can take the mark off (main's .gitignore has .conveyor).
  tune --arg c "bash $STUB/alone-runner" '.test.files["w.test.sh"].wholeOnly = true | .test.fileCommand = $c'
  [ "${2:-}" != nofile ] || tune 'del(.test.fileCommand)'
  git -C "$R" add -f .conveyor/project.json || fail "main's pack"
  fx_wt "$1" w.test.sh 'exit 0' other.test.sh 'exit 0'
  fx_in 'fixproof c7 "$FXWT" "{\"number\": 7}" w.test.sh "$ALONEFIX"'
}
UNMARK="jq 'del(.test.files[\"w.test.sh\"])' .conveyor/project.json > p.json && mv p.json .conveyor/project.json"

# Bug it catches: a Make it run alone card landed with no proof that the file runs by itself. The check runs
# w.test.sh alone through test.fileCommand (no other test file), and holds once it passes; the review is told so.
t_alonepass() {
  alonerun "$UNMARK; echo 'exit 0 # alone' > w.test.sh"
  [ "$RC" = 0 ] || fail "a file that runs alone and passes was refused: $WHY $(cat "$T/$CASE/run.out")"
  [ "$(cat "$STUB/alone-args")" = 'w.test.sh' ] || fail "test.fileCommand was not given the file alone: $(cat "$STUB/alone-args" 2>&1)"
  [ "$WHY" = "This issue makes the test file w.test.sh run alone. The pack no longer marks it whole-only, and run alone through the pack's test.fileCommand, with the change, on a test slot, w.test.sh passed." ] \
    || fail "the review is not told the result: $WHY"
}

# Bug it catches: a card that changed test.fileCommand had its file proven through main's command, not its own. The
# check runs the file through the command of the pack the change leaves (here marked ALONE_MARK=new).
t_alonenewcmd() {
  alonerun "$UNMARK; jq '.test.fileCommand = \"ALONE_MARK=new \" + .test.fileCommand' .conveyor/project.json > p.json && mv p.json .conveyor/project.json"
  [ "$RC" = 0 ] && [ "$(cat "$STUB/alone-args")" = 'new w.test.sh' ] \
    || fail "the run alone did not use the change's test.fileCommand: $RC $WHY $(cat "$STUB/alone-args" 2>&1)"
}

# Bug it catches: a card that left the wholeOnly mark in the pack landed as fixed, and no card's Test step would ever run
# the file. It is refused before any run, naming the mark.
t_alonemarked() {
  alonerun "echo 'exit 0 # alone' > w.test.sh"
  [ "$RC" != 0 ] && [ "$WHY" = 'the change leaves the test file w.test.sh marked whole-only (test.files."w.test.sh".wholeOnly in .conveyor/project.json): a Make it run alone card takes the mark off' ] \
    || fail "a change that keeps the mark passed: $RC $WHY"
  [ ! -e "$STUB/alone-args" ] || fail "the file was run though the card was already refused"
}

# Bug it catches: a file that fails when run alone passed the check. The card is refused with the run's exit.
t_alonefails() {
  alonerun "$UNMARK; echo 'exit 3' > w.test.sh"
  [ "$RC" != 0 ] && [[ $WHY == "the test file w.test.sh failed run alone through the pack's test.fileCommand, with the change, on a test slot (exit 1)"* ]] \
    || fail "a file that fails alone passed: $RC $WHY"
}

# #351. Bug it catches: with no way to run one file, a run of the whole suite passed as the file's run alone. With no
# test.fileCommand the card is refused, its reason naming test.fileCommand, and nothing runs.
t_alonenolist() {
  alonerun "$UNMARK" nofile
  [ "$RC" != 0 ] && [ "$WHY" = "a card runs each of its test files alone, and the pack sets no test.fileCommand, so no test file can run; set test.fileCommand in .conveyor/project.json to a command that runs one test file" ] \
    || fail "a pack with no test.fileCommand passed, or its reason does not name it: $RC $WHY"
  [ ! -e "$STUB/alone-args" ] || fail "a test ran though the file cannot be run alone"
}

# Bug it catches: a change that moved the file's checks into a new file and removed it ran nothing and passed; and a
# Make it run alone title was read as Make it run (whose title starts the same). The new test file runs alone in its
# place, and alonefile() reads only a title that ends "run alone".
t_alonemoved() {
  alonerun "$UNMARK; git rm -q w.test.sh; echo 'exit 0' > n.test.sh"
  [ "$RC" = 0 ] && [ "$(cat "$STUB/alone-args")" = 'n.test.sh' ] || fail "the added file did not run in place of the removed one: $RC $WHY $(cat "$STUB/alone-args" 2>&1)"
  fx_in '[ "$(alonefile "{\"number\": 7, \"title\": \"Make the test file w.test.sh run alone\"}")" = w.test.sh ] && ! alonefile "{\"number\": 7, \"title\": \"Make the test file w.test.sh run\"}"'
  [ "$RC" = 0 ] || fail "alonefile read the titles wrong: $(cat "$T/$CASE/run.out")"
}

# Bug it catches (#246): a change that moved the file's checks into an existing test file and removed it was blocked
# as adding no test file, as only added files were run. The changed file runs alone in its place.
t_alonemerged() {
  alonerun "$UNMARK; git rm -q w.test.sh; echo 'exit 0 # merged' > other.test.sh"
  [ "$RC" = 0 ] && [ "$(cat "$STUB/alone-args")" = 'other.test.sh' ] || fail "the changed file did not run in place of the removed one: $RC $WHY $(cat "$STUB/alone-args" 2>&1)"
}
