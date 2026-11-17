#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the check of the Board's Make it run alone card (#190; aloneproof(), conveyor/lib/testrun.sh): the
# pack as the change leaves it no longer marks the file wholeOnly, and the file runs alone through the pack's
# test.list, on a test slot, and passes. fx_in and fx_wt are in lib.sh.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Card c7's check of w.test.sh, which main's pack marks wholeOnly, with the pack's test.list <list> and a test command
# that runs each file it is given, as words or in CONVEYOR_TEST_FILES (the files kept in $STUB/alone-args), and logs
# it as a runner does; <words> follow the command (placeholder: {files}). <change> is made in the card's worktree.
alonerun() { # <change> <list> [<words>]
  setup '[]'
  printf '%s\n' '[ $# != 0 ] || set -- $CONVEYOR_TEST_FILES; printf "%s\n" "$*" >> "$STUB/alone-args"; r=0' \
    'for f; do echo "== $f" >> "$CONVEYOR_TEST_LOG/r.log"; if bash "$f"; then echo "-- ok $f"; else echo "-- FAIL $f"; r=1; fi >> "$CONVEYOR_TEST_LOG/r.log"; done; exit $r' > "$STUB/alone-runner"
  # The pack is tracked, as a project's is, so the card's change can take the mark off (main's .gitignore has .conveyor).
  tune --arg l "$2" --arg c "bash $STUB/alone-runner${3:+ $3}" '.test.files["w.test.sh"].wholeOnly = true | .test.command = $c | if $l == "" then del(.test.list) else .test.list = $l end'
  git -C "$R" add -f .conveyor/project.json || fail "main's pack"
  fx_wt "$1" w.test.sh 'exit 0' other.test.sh 'exit 0'
  fx_in 'fixproof c7 "$FXWT" "{\"number\": 7}" w.test.sh "$ALONEFIX"'
}
UNMARK="jq 'del(.test.files[\"w.test.sh\"])' .conveyor/project.json > p.json && mv p.json .conveyor/project.json"

# Bug it catches: a Make it run alone card landed with no proof that the file runs by itself. The check gives the test
# command w.test.sh alone, as test.list args says (no other test file), and holds once it passes; the review is told so.
t_alonepass() {
  alonerun "$UNMARK; echo 'exit 0 # alone' > w.test.sh" args
  [ "$RC" = 0 ] || fail "a file that runs alone and passes was refused: $WHY $(cat "$T/$CASE/run.out")"
  [ "$(cat "$STUB/alone-args")" = 'w.test.sh' ] || fail "the test command was not given the file alone: $(cat "$STUB/alone-args" 2>&1)"
  [ "$WHY" = "This issue makes the test file w.test.sh run alone. The pack no longer marks it whole-only, and run alone through the pack's test.list (args), with the change, on a test slot, w.test.sh passed." ] \
    || fail "the review is not told the result: $WHY"
}

# Bug it catches: with test.list env or placeholder the command was run with no file, so it ran the whole suite (or
# nothing). The file is given in CONVEYOR_TEST_FILES, or in place of {files}, alone.
t_aloneenv() {
  alonerun "$UNMARK" env
  [ "$RC" = 0 ] && [ "$(cat "$STUB/alone-args")" = 'w.test.sh' ] || fail "test.list env did not give the file alone: $RC $WHY $(cat "$STUB/alone-args" 2>&1)"
}
t_aloneplace() {
  alonerun "$UNMARK" placeholder '{files}'
  [ "$RC" = 0 ] && [ "$(cat "$STUB/alone-args")" = 'w.test.sh' ] || fail "test.list placeholder did not give the file alone: $RC $WHY $(cat "$STUB/alone-args" 2>&1)"
}

# Bug it catches: a card that left the wholeOnly mark in the pack landed as fixed, and no card's Test step would ever run
# the file. It is refused before any run, naming the mark.
t_alonemarked() {
  alonerun "echo 'exit 0 # alone' > w.test.sh" args
  [ "$RC" != 0 ] && [ "$WHY" = 'the change leaves the test file w.test.sh marked whole-only (test.files."w.test.sh".wholeOnly in .conveyor/project.json): a Make it run alone card takes the mark off' ] \
    || fail "a change that keeps the mark passed: $RC $WHY"
  [ ! -e "$STUB/alone-args" ] || fail "the file was run though the card was already refused"
}

# Bug it catches: a file that fails when run alone passed the check. The card is refused with the run's exit.
t_alonefails() {
  alonerun "$UNMARK; echo 'exit 3' > w.test.sh" args
  [ "$RC" != 0 ] && [[ $WHY == "the test file w.test.sh failed run alone through the pack's test.list, with the change, on a test slot (exit 1)"* ]] \
    || fail "a file that fails alone passed: $RC $WHY"
}

# Bug it catches: with no test.list the command cannot be given one file, and a run of the whole suite passed as the
# file's run alone. The card is refused, saying the pack must set test.list, and nothing runs.
t_alonenolist() {
  alonerun "$UNMARK" ''
  [ "$RC" != 0 ] && [[ $WHY == "the pack's test.list is not set, so the test command cannot be given one test file alone: set test.list"* ]] \
    || fail "a pack with no test.list passed: $RC $WHY"
  [ ! -e "$STUB/alone-args" ] || fail "the suite ran though the file cannot be given alone"
}

# Bug it catches: the check read main's test.list, so a card that makes the file run alone by setting test.list was
# refused as if the pack still had none. Main's pack has no test.list; the change sets it to env, and the file runs
# alone through it.
t_alonecardlist() {
  alonerun "jq 'del(.test.files[\"w.test.sh\"]) | .test.list = \"env\"' .conveyor/project.json > p.json && mv p.json .conveyor/project.json" ''
  [ "$RC" = 0 ] && [ "$(cat "$STUB/alone-args")" = 'w.test.sh' ] || fail "the card's own test.list was not used: $RC $WHY $(cat "$STUB/alone-args" 2>&1)"
}

# Bug it catches: a change that moved the file's checks into a new file and removed it ran nothing and passed; and a
# Make it run alone title was read as Make it run (whose title starts the same). The new test file runs alone in its
# place, and alonefile() reads only a title that ends "run alone".
t_alonemoved() {
  alonerun "$UNMARK; git rm -q w.test.sh; echo 'exit 0' > n.test.sh" args
  [ "$RC" = 0 ] && [ "$(cat "$STUB/alone-args")" = 'n.test.sh' ] || fail "the added file did not run in place of the removed one: $RC $WHY $(cat "$STUB/alone-args" 2>&1)"
  fx_in '[ "$(alonefile "{\"number\": 7, \"title\": \"Make the test file w.test.sh run alone\"}")" = w.test.sh ] && ! alonefile "{\"number\": 7, \"title\": \"Make the test file w.test.sh run\"}"'
  [ "$RC" = 0 ] || fail "alonefile read the titles wrong: $(cat "$T/$CASE/run.out")"
}
