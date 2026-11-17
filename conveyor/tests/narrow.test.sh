#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases (#293): the rule Whole suite in a card (rules.wholeSuite) off, as it is by default: a card's run never
# runs the whole suite (tests(): listcmd(), watch()), and the release's run is not changed by it. The rule on, a card
# runs as before: the cases of testlist.test.sh, whose fixture seeds it on (lib.sh seed()).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# The rule Whole suite in a card off in the control record (the fixture's seed turns it on).
wholeoff() {
  jq -c '.rules.wholeSuite = false' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json" || fail "the rule could not be turned off"
}
# Main holds lib/cartsum.js and its test lib/cartsum.test.js, lib/tax.test.js and a shared test helper
# (test/helpers.js). The pack's test.list is <mode>, its command $STUB/list-cmd, which adds the arguments it was given
# and CONVEYOR_TEST_FILES to $STUB/got, a line a run; the rule is off.
narrowsetup() { # <test.list>
  local f
  setup '[]'
  for f in lib/cartsum.js lib/cartsum.test.js lib/tax.test.js test/helpers.js; do mkdir -p "$R/${f%/*}" && echo x > "$R/$f"; done
  git -C "$R" add -A && git -C "$R" commit -qm files || fail "main's files could not be committed"
  printf '%s\n' 'printf "args:%s|env:%s\n" "$*" "$(printf %s "${CONVEYOR_TEST_FILES:-}" | tr "\n" " ")" >> "$STUB/got"' > "$STUB/list-cmd"
  tune --arg l "$1" '.test.list = $l | .test.command = "bash \"$STUB/list-cmd\""'
  wholeoff
}
# Card c7's test step, its own tests() as card() runs it (with <field>, as the release's runs call it), on a change (a
# shell edit staged in its worktree on main): its exit in $T/$CASE/rc, its test line's fields (testrec()) in c7.rec.
# With <fix>, a fix session's edit is staged after that run, and the test step runs again: rc is that run's exit.
narrowrun() { # <change> [field] [fix]
  local wt=$T/$CASE/cards/c7
  git -C "$R" worktree add -q --detach "$wt" && (cd "$wt" && eval "$1") && git -C "$wt" add -A || fail "the card's change could not be staged"
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" || exit 1
    names || exit 1; tests "$wt" ${2:+"$2"}; echo $? > "$T/$CASE/rc"
    [ -z "${3:-}" ] || { (cd "$wt" && eval "$3") && git -C "$wt" add -A && tests "$wt" ${2:+"$2"}; echo $? > "$T/$CASE/rc"; }
    testrec "$wt" 0 0 > "$wt.rec" ) > "$T/$CASE/run.out" 2>&1 \
    || fail "the test step could not be run: $(cat "$T/$CASE/run.out")"
}

# D1. Bug it catches: a card whose change touches a shared helper ran the whole suite (no list), however the rule was
# set. A pack with no test.list cannot give the command the card's tests: with no test.fileCommand, the whole card is
# blocked at its test step with a reason that names both settings, and the command never ran.
t_narrowblock() {
  setup "[$(issue 7 2026-01-01)]"; wholeoff
  printf '%s\n' 'pwd >> "$STUB/got"' > "$STUB/list-cmd"; tune 'del(.test.list, .test.fileCommand) | .test.command = "bash \"$STUB/list-cmd\""'
  echo 'mkdir -p lib && echo x > lib/new.test.js && echo two >> a.txt' > "$STUB/build"; echo "$GO" > "$STUB/review.1"
  loop run > /dev/null
  st 'select(.step == "blocked") | .reason' | grep -qF 'test: the rule Whole suite in a card is off, and the test command cannot be given the card'"'"'s 1 test file(s): test.list is not set, so the test command takes no list; set test.list in .conveyor/project.json' \
    && st 'select(.step == "blocked") | .reason' | grep -qF 'or set test.fileCommand to a command that runs one test file' \
    || fail "the card was not blocked at its test step naming test.list and test.fileCommand: $(st 'select(.step == "blocked")')"
  # The card's own run, in its worktree; a run on main's checkout is not the card's.
  ! grep -qF "$T/$CASE/cards/" "$STUB/got" 2>/dev/null || fail "the test command ran in the card's worktree: $(cat "$STUB/got")"
}

# D1. Bug it catches: test.list none (the command takes no list) ran every test file. With test.fileCommand set, the
# change to a shared helper (which the rule on runs the whole suite for: t_testlisthelper) and to lib/cartsum.js runs
# only lib/cartsum.test.js, alone, through test.fileCommand; the test command is not run.
t_narrowfiles() {
  narrowsetup none
  printf '%s\n' 'echo "one:$1" >> "$STUB/got"' > "$STUB/one"; tune '.test.fileCommand = "bash \"$STUB/one\""'
  narrowrun 'echo y >> test/helpers.js; echo y >> lib/cartsum.js'
  [ "$(cat "$T/$CASE/rc")" = 0 ] && [ "$(cat "$STUB/got" 2>&1)" = 'one:lib/cartsum.test.js' ] \
    || fail "the card did not run its one linked test file alone (exit $(cat "$T/$CASE/rc")): $(cat "$STUB/got" "$T/$CASE/run.out" 2>&1)"
  [ "$(jq -c .list "$T/$CASE/cards/c7.rec")" = '{"mode":"changed","files":1,"by":"name"}' ] || fail "the test line's list: $(cat "$T/$CASE/cards/c7.rec")"
}

# Bug it catches: a change linked to no test file (a source with no test found for it) ran the whole suite. It runs
# nothing and passes, and its output and test line say that the release's run covers it.
t_narrownone() {
  narrowsetup args
  narrowrun 'echo x > lib/other.js'
  [ "$(cat "$T/$CASE/rc")" = 0 ] && [ ! -e "$STUB/got" ] || fail "a change with no linked test ran the command, or failed: $(cat "$STUB/got" "$T/$CASE/run.out" 2>&1)"
  grep -qF "the release's whole-suite run covers this change" "$T/$CASE/cards/c7.test" \
    && [ "$(jq -r '.list | "\(.files) \(.why)"' "$T/$CASE/cards/c7.rec")" = "0 no test file is linked to the files the change touches, so no test ran; the release's whole-suite run covers this change" ] \
    || fail "the test step did not say that no test ran: $(cat "$T/$CASE/cards/c7.test" "$T/$CASE/cards/c7.rec")"
}

# Bug it catches: a change to a document alone ran no test, though .conveyor/test-links.json links the document to a
# test file (a page whose text a test reads), or the pack's test map (test.map) maps it to one. It runs both test
# files, given to the command.
t_narrowdocs() {
  narrowsetup args
  tune '.test.map = ".conveyor/map.json"'
  mkdir -p "$R/docs" && echo x > "$R/docs/guide.md" && git -C "$R" add -A && git -C "$R" commit -qm docs || fail "main's page could not be committed"
  # The fixture ignores .conveyor/: the links and the map are the worktree's, and not part of the change.
  narrowrun 'mkdir -p .conveyor && echo '"'"'{"docs/guide.md": ["lib/tax.test.js"]}'"'"' > .conveyor/test-links.json \
    && echo '"'"'{"docs/guide.md": ["lib/cartsum.test.js"]}'"'"' > .conveyor/map.json && echo y >> docs/guide.md'
  [ "$(cat "$T/$CASE/rc")" = 0 ] && [ "$(cat "$STUB/got" 2>&1)" = 'args:lib/cartsum.test.js lib/tax.test.js|env:' ] \
    || fail "the document's linked and mapped test files were not run (exit $(cat "$T/$CASE/rc")): $(cat "$STUB/got" "$T/$CASE/run.out" 2>&1)"
}

# Bug it catches: with test.fileCommand, a file that passed before a fix kept its pass, so a fix that broke the code it
# tests landed with that file not run again. lib/cartsum.js is linked to two test files; lib/tax.test.js fails, then a
# fix changes lib/cartsum.js: the run after it runs both files again.
t_narrowfixrun() {
  narrowsetup none
  printf '%s\n' 'echo "one:$1" >> "$STUB/got"; [ "$1" != lib/tax.test.js ] || [ -e "$STUB/fixed" ]' > "$STUB/one"; tune '.test.fileCommand = "bash \"$STUB/one\""'
  # The fixture ignores .conveyor/: the links are the worktree's, and not part of the change.
  narrowrun 'mkdir -p .conveyor && echo '"'"'{"lib/cartsum.js": ["lib/cartsum.test.js", "lib/tax.test.js"]}'"'"' > .conveyor/test-links.json && echo y >> lib/cartsum.js' \
    '' 'rm -f "$STUB/got"; touch "$STUB/fixed"; echo z >> lib/cartsum.js'
  [ "$(cat "$T/$CASE/rc")" = 0 ] && [ "$(cat "$STUB/got" 2>&1)" = $'one:lib/cartsum.test.js\none:lib/tax.test.js' ] \
    || fail "the run after the fix did not run both linked files (exit $(cat "$T/$CASE/rc")): $(cat "$STUB/got" "$T/$CASE/run.out" 2>&1)"
}

# D1. Bug it catches: a test command that ignores the list it is given (npm test running every file) ran all of them,
# 45 minutes a card. Given lib/cartsum.test.js, it reports 40 test files: the run is stopped at once, not run again,
# and fails with a reason (<worktree>.stop, which card() blocks with) naming the counts and the settings.
t_narrowwide() {
  narrowsetup args
  printf '%s\n' 'echo "TESTRUN files=40" >> "$CONVEYOR_TEST_LOG/run"; echo ran >> "$STUB/got"; sleep 30' > "$STUB/list-cmd" # sleep: a long run, which the stop cuts
  local s=$SECONDS
  narrowrun 'echo y >> lib/cartsum.js'
  [ $((SECONDS - s)) -lt 20 ] && [ "$(cat "$T/$CASE/rc")" != 0 ] && [ "$(cat "$STUB/got")" = ran ] \
    || fail "the run was not stopped, or ran again (exit $(cat "$T/$CASE/rc"), $((SECONDS - s))s): $(cat "$STUB/got" "$T/$CASE/run.out" 2>&1)"
  grep -qF 'the rule Whole suite in a card is off, and the test command, given 1 test file(s), reported 40 test files: it runs test files it is not given, so its run was stopped; set test.list' "$T/$CASE/cards/c7.stop" \
    || fail "the stop does not say why: $(cat "$T/$CASE/cards/c7.stop" "$T/$CASE/run.out" 2>&1)"
}

# D1. Bug it catches: the rule off narrowed the release's run too. tests() with test.full, as the full test suite and
# release-prep run it, on a change to a shared helper, runs the whole suite (no list) and is not stopped.
t_narrowrelease() {
  narrowsetup args
  tune '.test.full = "bash \"$STUB/list-cmd\""'
  narrowrun 'echo y >> test/helpers.js' test.full
  [ "$(cat "$T/$CASE/rc")" = 0 ] && [ "$(cat "$STUB/got")" = 'args:|env:' ] && [ ! -e "$T/$CASE/cards/c7.stop" ] \
    || fail "the release's run was not the whole suite: $(cat "$STUB/got" "$T/$CASE/run.out" 2>&1)"
}

# Bug it catches: a pack whose cards all stop at their test step with nothing said before. Doctor warns of a pack with
# neither test.list nor test.fileCommand while the rule is off, and not once the pack sets one of them or the rule is on.
t_narrowdoctor() {
  setup '[]'; wholeoff; tune 'del(.test.list, .test.fileCommand)'
  ( export CONVEYOR_MAIN=$R; . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/doctor.sh")" || exit 1
    narrowwarn > "$T/$CASE/neither"; tune '.test.fileCommand = "bash"'; narrowwarn > "$T/$CASE/fc"
    tune 'del(.test.fileCommand)'; jq -c '.rules.wholeSuite = true' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json" && narrowwarn > "$T/$CASE/on" ) \
    > "$T/$CASE/run.out" 2>&1 || fail "the warning failed to run: $(cat "$T/$CASE/run.out")"
  grep -q '^warning: the rule Whole suite in a card is off, and the pack sets neither test.list nor test.fileCommand' "$T/$CASE/neither" \
    || fail "doctor did not warn of a pack with neither: $(cat "$T/$CASE/neither" "$T/$CASE/run.out")"
  [ ! -s "$T/$CASE/fc" ] && [ ! -s "$T/$CASE/on" ] || fail "doctor warned with test.fileCommand set, or the rule on: $(cat "$T/$CASE/fc" "$T/$CASE/on")"
}
