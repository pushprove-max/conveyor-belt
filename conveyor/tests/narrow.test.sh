#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases (#293, #351): a card never runs the whole suite. Its run gives each test file of its list to
# test.fileCommand alone and never runs test.command (tests(): listcmd(), watch()); with no test.fileCommand, Conveyor's
# own runner runs each file (lib/filerun.sh), and with none for a file it stops, naming the setting. The release's run
# is not changed by it.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Main holds lib/cartsum.js and its test lib/cartsum.test.js, lib/tax.test.js and a shared test helper
# (test/helpers.js). The pack's test.fileCommand is $STUB/one, which adds `one:<the file it was given>` to $STUB/got,
# a line a run; its test.command (args as test.list) is $STUB/suite-cmd, which adds the arguments it was given and
# CONVEYOR_TEST_FILES to $STUB/got the same way, so a run of the suite command shows there (not $STUB/list-cmd, which
# the gh stub runs for its issue list: lib.sh).
narrowsetup() {
  local f
  setup '[]'
  for f in lib/cartsum.js lib/cartsum.test.js lib/tax.test.js test/helpers.js; do mkdir -p "$R/${f%/*}" && echo x > "$R/$f"; done
  git -C "$R" add -A && git -C "$R" commit -qm files || fail "main's files could not be committed"
  printf '%s\n' 'printf "args:%s|env:%s\n" "$*" "$(printf %s "${CONVEYOR_TEST_FILES:-}" | tr "\n" " ")" >> "$STUB/got"' > "$STUB/suite-cmd"
  printf '%s\n' 'echo "one:$1" >> "$STUB/got"' > "$STUB/one"
  tune '.test.list = "args" | .test.command = "bash \"$STUB/suite-cmd\"" | .test.fileCommand = "bash \"$STUB/one\""'
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

# #351 scenario 1. Bug it catches: a card whose pack has no way to run one test file ran the whole suite (test.command
# with no list). With no test.list and no test.fileCommand, and a test file Conveyor's own runner cannot run (a .js
# file that no package.json holds: #376), the card's test step stops with a reason (card() blocks the card with it,
# under Needs you) that names test.fileCommand and that file, and the test command never ran.
t_narrowblock() {
  setup '[]'
  printf '%s\n' 'pwd >> "$STUB/got"' > "$STUB/suite-cmd"; tune 'del(.test.list, .test.fileCommand) | .test.command = "bash \"$STUB/suite-cmd\""'
  narrowrun 'mkdir -p lib && echo x > lib/new.test.js && echo two >> a.txt'
  [ "$(cat "$T/$CASE/cards/c7.stop" 2>&1)" = 'a card runs each of its test files alone, and the pack sets no test.fileCommand, and Conveyor cannot run lib/new.test.js itself: no package.json holds it; set test.fileCommand in .conveyor/project.json to a command that runs one test file' ] \
    || fail "the test step did not stop naming test.fileCommand: $(cat "$T/$CASE/cards/c7.stop" "$T/$CASE/run.out" 2>&1)"
  [ ! -e "$STUB/got" ] || fail "the test command ran: $(cat "$STUB/got")"
}

# D1, #351 scenario 5. Bug it catches: a change to a shared helper ran every test file. The change to a shared helper
# and to lib/cartsum.js runs only lib/cartsum.test.js, the file linked to it by name, alone, through
# test.fileCommand; the test command is not run.
t_narrowfiles() {
  narrowsetup
  narrowrun 'echo y >> test/helpers.js; echo y >> lib/cartsum.js'
  [ "$(cat "$T/$CASE/rc")" = 0 ] && [ "$(cat "$STUB/got" 2>&1)" = 'one:lib/cartsum.test.js' ] \
    || fail "the card did not run its one linked test file alone (exit $(cat "$T/$CASE/rc")): $(cat "$STUB/got" "$T/$CASE/run.out" 2>&1)"
  [ "$(jq -c .list "$T/$CASE/cards/c7.rec")" = '{"mode":"changed","files":1,"by":"name"}' ] || fail "the test line's list: $(cat "$T/$CASE/cards/c7.rec")"
}

# #351 scenario 6. Bug it catches: a change linked to no test file (a source with no test found for it) ran the whole
# suite. It runs nothing, neither command, and passes, and its output and test line say that the release's run covers it.
t_narrownone() {
  narrowsetup
  narrowrun 'echo x > lib/other.js'
  [ "$(cat "$T/$CASE/rc")" = 0 ] && [ ! -e "$STUB/got" ] || fail "a change with no linked test ran the command, or failed: $(cat "$STUB/got" "$T/$CASE/run.out" 2>&1)"
  grep -qF "the release's whole-suite run covers this change" "$T/$CASE/cards/c7.test" \
    && [ "$(jq -r '.list | "\(.files) \(.why)"' "$T/$CASE/cards/c7.rec")" = "0 no test file is linked to the files the change touches, so no test ran; the release's whole-suite run covers this change" ] \
    || fail "the test step did not say that no test ran: $(cat "$T/$CASE/cards/c7.test" "$T/$CASE/cards/c7.rec")"
}

# Bug it catches: a change to a document alone ran no test, though .conveyor/test-links.json links the document to a
# test file (a page whose text a test reads), or the pack's test map (test.map) maps it to one. It runs both test
# files, each alone.
t_narrowdocs() {
  narrowsetup
  tune '.test.map = ".conveyor/map.json"'
  mkdir -p "$R/docs" && echo x > "$R/docs/guide.md" && git -C "$R" add -A && git -C "$R" commit -qm docs || fail "main's page could not be committed"
  # The fixture ignores .conveyor/: the links and the map are the worktree's, and not part of the change.
  narrowrun 'mkdir -p .conveyor && echo '"'"'{"docs/guide.md": ["lib/tax.test.js"]}'"'"' > .conveyor/test-links.json \
    && echo '"'"'{"docs/guide.md": ["lib/cartsum.test.js"]}'"'"' > .conveyor/map.json && echo y >> docs/guide.md'
  [ "$(cat "$T/$CASE/rc")" = 0 ] && [ "$(cat "$STUB/got" 2>&1)" = $'one:lib/cartsum.test.js\none:lib/tax.test.js' ] \
    || fail "the document's linked and mapped test files were not run (exit $(cat "$T/$CASE/rc")): $(cat "$STUB/got" "$T/$CASE/run.out" 2>&1)"
}

# Bug it catches: with test.fileCommand, a file that passed before a fix kept its pass, so a fix that broke the code it
# tests landed with that file not run again. lib/cartsum.js is linked to two test files; lib/tax.test.js fails, then a
# fix changes lib/cartsum.js: the run after it runs both files again.
t_narrowfixrun() {
  narrowsetup
  printf '%s\n' 'echo "one:$1" >> "$STUB/got"; [ "$1" != lib/tax.test.js ] || [ -e "$STUB/fixed" ]' > "$STUB/one"
  # The fixture ignores .conveyor/: the links are the worktree's, and not part of the change.
  narrowrun 'mkdir -p .conveyor && echo '"'"'{"lib/cartsum.js": ["lib/cartsum.test.js", "lib/tax.test.js"]}'"'"' > .conveyor/test-links.json && echo y >> lib/cartsum.js' \
    '' 'rm -f "$STUB/got"; touch "$STUB/fixed"; echo z >> lib/cartsum.js'
  [ "$(cat "$T/$CASE/rc")" = 0 ] && [ "$(cat "$STUB/got" 2>&1)" = $'one:lib/cartsum.test.js\none:lib/tax.test.js' ] \
    || fail "the run after the fix did not run both linked files (exit $(cat "$T/$CASE/rc")): $(cat "$STUB/got" "$T/$CASE/run.out" 2>&1)"
}

# D1, #351 scenario 7, after a fix round. Bug it catches: the run after a fix session that left the change as it was
# started every file of the card's list again, or the suite command. lib/cartsum.js is linked to two test files, and
# lib/tax.test.js fails until the fix: the run after the fix starts lib/tax.test.js alone, through test.fileCommand
# (the file it is given), and lib/cartsum.test.js, which passed, does not start.
t_narrowfixsame() {
  narrowsetup
  printf '%s\n' 'echo "one:$1" >> "$STUB/got"; [ "$1" != lib/tax.test.js ] || [ -e "$STUB/fixed" ]' > "$STUB/one"
  # The fixture ignores .conveyor/: the links are the worktree's, and not part of the change.
  narrowrun 'mkdir -p .conveyor && echo '"'"'{"lib/cartsum.js": ["lib/cartsum.test.js", "lib/tax.test.js"]}'"'"' > .conveyor/test-links.json && echo y >> lib/cartsum.js' \
    '' 'rm -f "$STUB/got"; touch "$STUB/fixed"'
  [ "$(cat "$T/$CASE/rc")" = 0 ] && [ "$(cat "$STUB/got" 2>&1)" = 'one:lib/tax.test.js' ] \
    || fail "the run after the fix did not start the failed file alone (exit $(cat "$T/$CASE/rc")): $(cat "$STUB/got" "$T/$CASE/run.out" 2>&1)"
}

# #351 scenario 7. Bug it catches: the run again after a failure ran every file of the card's list, or the suite
# command. lib/cartsum.js is linked to two test files, and lib/tax.test.js fails its first run only: the run again
# runs lib/tax.test.js alone, through test.fileCommand, and the step passes.
t_narrowrerun() {
  narrowsetup
  printf '%s\n' 'echo "one:$1" >> "$STUB/got"; [ "$1" != lib/tax.test.js ] || [ -e "$STUB/once" ] || { touch "$STUB/once"; exit 1; }' > "$STUB/one"
  # The fixture ignores .conveyor/: the links are the worktree's, and not part of the change.
  narrowrun 'mkdir -p .conveyor && echo '"'"'{"lib/cartsum.js": ["lib/cartsum.test.js", "lib/tax.test.js"]}'"'"' > .conveyor/test-links.json && echo y >> lib/cartsum.js'
  [ "$(cat "$T/$CASE/rc")" = 0 ] && [ "$(cat "$STUB/got" 2>&1)" = $'one:lib/cartsum.test.js\none:lib/tax.test.js\none:lib/tax.test.js' ] \
    || fail "the run again did not run the failed file alone (exit $(cat "$T/$CASE/rc")): $(cat "$STUB/got" "$T/$CASE/run.out" 2>&1)"
}

# #351 scenario 2, and its stub that must never be called. Bug it catches: a card ran the suite command, which ignores
# the list it is given (npm test running every file, 45 minutes a card). test.command and test.full are a stub that
# runs every file and records `suite`; the test step of a card whose change touches lib/cartsum.js runs
# lib/cartsum.test.js alone through test.fileCommand, passes, and neither suite command ever started.
# #351 scenario 10 too. Bug it catches: a card built or refreshed the test map, a whole-suite run under coverage, which
# only the owner starts (setup, the Board). Main is a Node project (package.json, so the map's tool is there) whose
# made map is due (made under another test command): the card leaves the map as it was and starts no build of it.
t_narrowsuite() {
  local m
  narrowsetup; echo '{}' > "$R/package.json"; git -C "$R" add package.json && git -C "$R" commit -qm node || fail "main's files could not be committed"
  m=$R/.conveyor/test-map.json
  jq -n --arg s "$(git -C "$R" rev-parse HEAD)" '{commit: $s, command: "an older test command", language: "node", made: "2026-01-01T00:00:00Z", seconds: 1,
    tests: ["lib/cartsum.test.js"], sources: {"lib/cartsum.js": ["lib/cartsum.test.js"]}}' > "$m" && cp "$m" "$STUB/map.before" || fail "the test map could not be written"
  printf '%s\n' 'echo "suite:$PWD" >> "$STUB/got"; echo "TESTRUN files=40" >> "$CONVEYOR_TEST_LOG/run"' > "$STUB/suite-cmd"
  tune '.test.full = .test.command'
  narrowrun 'echo y >> lib/cartsum.js'
  [ "$(cat "$T/$CASE/rc")" = 0 ] || fail "the card's test step failed: $(cat "$T/$CASE/run.out")"
  [ "$(cat "$STUB/got" 2>&1)" = 'one:lib/cartsum.test.js' ] || fail "the card's run started a suite command, or not its one file alone: $(cat "$STUB/got" 2>&1)"
  cmp -s "$m" "$STUB/map.before" && [ ! -e "$R/.conveyor/test-map.run.json" ] && [ ! -e "$R/.conveyor/test-map.build.json" ] \
    || fail "the card built or refreshed the test map: $(ls "$R/.conveyor"; cat "$m")"
}

# #351 scenario 9. Bug it catches: the main-red check (verdicts(): a card's failures run on main) ran the suite
# command, given the failing cases, which ran every test file. The card's run failed two cases of
# lib/cartsum.test.js and lib/tax.test.js naming no case: main runs each of the two files once, alone, through
# test.fileCommand, and nothing else.
t_narrowmainred() {
  local wt=$T/$CASE/cards/c7
  narrowsetup
  git -C "$R" worktree add -q --detach "$wt" && (cd "$wt" && echo y >> lib/cartsum.js) && git -C "$wt" add -A || fail "the card's change could not be staged"
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" || exit 1
    names || exit 1
    # shellcheck disable=SC2034 # TEST_WAIT, TEST_RUN and TEST_FREE are read by verdicts(), defined by the eval
    TEST_WAIT=0 TEST_RUN=0 TEST_FREE=0
    verdicts c7 "$wt" '{"files":[{"file":"lib/cartsum.test.js","cases":[{"name":"adds"},{"name":"rounds"}]},{"file":"lib/tax.test.js","cases":[]}]}' || : ) \
    > "$T/$CASE/run.out" 2>&1 || fail "the check on main could not be run: $(cat "$T/$CASE/run.out")"
  [ "$(sort "$STUB/got" 2>&1)" = $'one:lib/cartsum.test.js\none:lib/tax.test.js' ] \
    || fail "main did not run each failing file once, alone, and nothing else: $(cat "$STUB/got" "$T/$CASE/run.out" 2>&1)"
}

# D1. Bug it catches: narrowing a card's run narrowed the release's run too. tests() with test.full, as the full test
# suite and release-prep run it, on a change to a shared helper, runs the whole suite (no list) and is not stopped.
t_narrowrelease() {
  narrowsetup
  tune '.test.full = "bash \"$STUB/suite-cmd\""'
  narrowrun 'echo y >> test/helpers.js' test.full
  [ "$(cat "$T/$CASE/rc")" = 0 ] && [ "$(cat "$STUB/got")" = 'args:|env:' ] && [ ! -e "$T/$CASE/cards/c7.stop" ] \
    || fail "the release's run was not the whole suite: $(cat "$STUB/got" "$T/$CASE/run.out" 2>&1)"
}

# Bug it catches: a pack whose cards all stop at their test step with nothing said before. Doctor warns of a pack with
# no test.fileCommand, though it sets test.list (a card no longer gives test.command a list), whose test file a.test.sh
# Conveyor's own runner cannot run, naming it; and not once it sets one, with a.test.sh still there (#717). Bug it
# catches (E3 of #376's review): doctor also told a project whose test files the own runner runs (a Node package's
# lib/n.test.js, as in t_narrowownrunner) that no test file could run.
t_narrowdoctor() {
  setup '[]'; tune 'del(.test.fileCommand) | .test.list = "args"'
  ( export CONVEYOR_MAIN=$R; . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/doctor.sh")" || exit 1
    narrowwarn > "$T/$CASE/none"; tuned '.test.fileCommand = "bash"' narrowwarn > "$T/$CASE/fc"
    git -C "$R" rm -q a.test.sh && mkdir -p "$R/lib" && echo '{"name": "p"}' > "$R/package.json" && echo x > "$R/lib/n.test.js" \
      && git -C "$R" add package.json lib/n.test.js || exit 1
    narrowwarn > "$T/$CASE/own" ) \
    > "$T/$CASE/run.out" 2>&1 || fail "the warning failed to run: $(cat "$T/$CASE/run.out")"
  grep -qxF 'warning: a card runs each of its test files alone, and the pack sets no test.fileCommand, and Conveyor cannot run a.test.sh itself: it has no runner for a file of this kind; set test.fileCommand in .conveyor/project.json to a command that runs one test file' "$T/$CASE/none" \
    || fail "doctor did not warn of a pack with no test.fileCommand and a test file with no runner: $(cat "$T/$CASE/none" "$T/$CASE/run.out")"
  [ ! -s "$T/$CASE/own" ] || fail "doctor warned of a project whose test files Conveyor's own runner runs: $(cat "$T/$CASE/own")"
  [ ! -s "$T/$CASE/fc" ] || fail "doctor warned with test.fileCommand set: $(cat "$T/$CASE/fc")"
}

# #311, #384. Main holds <n> test files, t001.test.js to t<n>.test.js, which the card's change, an edit of <source>
# (and <more>, a shell edit, when given), links to it (.conveyor/test-links.json, the worktree's); the pack runs each
# test file alone (test.fileCommand, which adds `one:<file>` to $STUB/got); its test step runs as narrowrun() runs it.
# The records hold the test lines <line>... first.
caprun() { # <n> <source> [<more>] [<line>...]
  local i f fs=() s=$2 m=${3:-}
  narrowsetup
  [ $# -lt 4 ] || printf '%s\n' "${@:4}" >> "$ST/cards.jsonl"
  mkdir -p "$R/${s%/*}" && echo x > "$R/$s"
  for ((i = 1; i <= $1; i++)); do printf -v f 't%03d.test.js' "$i"; fs+=("$f"); echo x > "$R/$f"; done
  git -C "$R" add -A && git -C "$R" commit -qm tests || fail "main's test files could not be committed"
  narrowrun "mkdir -p .conveyor && jq -cn --arg s $s '{(\$s): \$ARGS.positional}' --args ${fs[*]} > .conveyor/test-links.json && echo y >> $s${m:+ && $m}"
}

# D1 (#384). Bug it catches: a card ran every test file the map links to its change (65 to 173 a card), holding test
# slots for hours, though it changed a test file of its own. A change to lib/card.sh, which the links tie to 40 test
# files, and to tests/samefile.test.sh runs only samefile.test.sh, and says nothing of linked files (the fixture's
# main ignores conveyor/, so the issue's conveyor/lib/card.sh and conveyor/tests/samefile.test.sh are without it).
t_narrowown() {
  caprun 40 lib/card.sh 'mkdir -p tests && echo y >> tests/samefile.test.sh'
  [ "$(cat "$T/$CASE/rc")" = 0 ] && [ "$(cat "$STUB/got" 2>&1)" = 'one:tests/samefile.test.sh' ] \
    || fail "the card did not run only its own test file (exit $(cat "$T/$CASE/rc")): $(cat "$STUB/got" "$T/$CASE/run.out" 2>&1)"
  [ "$(jq -c .list "$T/$CASE/cards/c7.rec")" = '{"mode":"changed","files":1,"by":"own"}' ] && ! grep -q 'linked to it' "$T/$CASE/cards/c7.test" \
    || fail "the test line's list, or the output: $(cat "$T/$CASE/cards/c7.rec" "$T/$CASE/cards/c7.test")"
}

# D1 (#384). Bug it catches: a test file whose name starts with setup (tests/setup.test.sh, tests/setupservice.test.sh)
# was read as a shared setup file, so the card ran 5 linked files in place of its own two.
t_narrowownsetup() {
  caprun 40 lib/card.sh 'mkdir -p tests && echo y >> tests/setup.test.sh && echo y >> tests/setupservice.test.sh'
  [ "$(cat "$T/$CASE/rc")" = 0 ] && [ "$(cat "$STUB/got" 2>&1)" = $'one:tests/setup.test.sh\none:tests/setupservice.test.sh' ] \
    && [ "$(jq -c .list "$T/$CASE/cards/c7.rec")" = '{"mode":"changed","files":2,"by":"own"}' ] \
    || fail "the card did not run only its own setup test files (exit $(cat "$T/$CASE/rc")): $(cat "$STUB/got" "$T/$CASE/run.out" "$T/$CASE/cards/c7.rec" 2>&1)"
}

# #414. Main holds tests/a.test.sh, tests/b.test.sh, tests/c.test.sh and tests/e.test.sh, each a helper (h<x>) and two cases
# (t_<x>one, which closes inline on its last line, `  echo one; }`, and t_<x>two), a comment line above each: a case
# that closes so must not leave its file's other cases unnamed (E1: t_slotnoroom ran slots.test.sh whole, its end not
# found). t_<x>two holds a quoted string of two lines, the first ending in `}` and the second at the first column
# (`{"y":2}'`), above its `echo 2`: a line inside quotes must not end the case early, so a change below it, to
# `echo 2`, still selects t_<x>two (were the case ended there, that change would count as one outside all cases: a
# JSON line ended t_testmapstate so, and the whole file ran). The pack runs each test file
# alone (test.fileCommand, which adds
# `one:<file>|<the cases CONVEYOR_TEST_CASES names of it, by commas>` to $STUB/got). The card's change, <change>, is
# staged and tested as narrowrun() does; ownedit <file> <ERE> <text> puts <text> for <ERE> in each line of <file>.
ownrun() { # <change>
  local x
  narrowsetup
  cat > "$STUB/one" <<'EOF'
c=$(printf '%s\n' "${CONVEYOR_TEST_CASES:-}" | awk -F'\t' -v f="$1" '$1 == f {print $2}' | paste -sd, -)
echo "one:$1|$c" >> "$STUB/got"
EOF
  mkdir -p "$R/tests"
  for x in a b c e; do
    printf '%s\n' "h$x() { echo $x; }" '' "# $x one." "t_${x}one() {" '  echo 1' '  echo one; }' '' "# $x two." "t_${x}two() {" "  : '{\"x\":1}" "{\"y\":2}'" '  echo 2' '}' > "$R/tests/$x.test.sh"
  done
  git -C "$R" add -A && git -C "$R" commit -qm tests || fail "main's test files could not be committed"
  narrowrun "$1"
}
ownedit() { awk -v e="$2" -v t="$3" '{ sub(e, t) } 1' "$1" > "$1.new" && mv "$1.new" "$1"; } # <file> <ERE> <text>

# D1 (#414). Bug it catches: a card ran each test file it changed whole (#398 changed a line or two in each of 50 test
# files, and ran all 50). A change to one case of each of three files (a line of a case, a new case with the blank
# line and comment above it, and a case's comment) runs those three cases alone, and the test line, its output and
# the Board's step name them: "3 changed cases of 3 test files".
t_narrowowncases() {
  ownrun "ownedit tests/a.test.sh '^  echo 1\$' '  echo 11' && printf '%s\n' '' '# b three.' 't_bthree() {' '  echo 3' '}' >> tests/b.test.sh \
    && ownedit tests/c.test.sh '^# c two[.]\$' '# c two, said again.'"
  local note='the card ran 3 changed cases of 3 test files'
  [ "$(cat "$T/$CASE/rc")" = 0 ] && [ "$(cat "$STUB/got" 2>&1)" = $'one:tests/a.test.sh|aone\none:tests/b.test.sh|bthree\none:tests/c.test.sh|ctwo' ] \
    || fail "the card did not run only its three changed cases (exit $(cat "$T/$CASE/rc")): $(cat "$STUB/got" "$T/$CASE/run.out" 2>&1)"
  [ "$(jq -c '.list | [.files, .cases, .why]' "$T/$CASE/cards/c7.rec")" = '[3,[{"file":"tests/a.test.sh","case":"aone"},{"file":"tests/b.test.sh","case":"bthree"},{"file":"tests/c.test.sh","case":"ctwo"}],"'"$note"'"]' ] \
    && grep -qxF "conveyor: $note" "$T/$CASE/cards/c7.test" || fail "the test line does not name the cases it ran: $(cat "$T/$CASE/cards/c7.rec" "$T/$CASE/cards/c7.test")"
  [ "$(trackwhy)" = "$note" ] || fail "the Board's test step does not say how many cases ran: $(cat "$T/$CASE/cards/c7.rec")"
}

# D2, D3 (#414). Bug it catches: a change to a file's shared part, or a new test file, ran only some cases of it, so a
# case the helper breaks, or a case of the new file, never ran. A change to a.test.sh's helper, outside any case, and
# to its case t_aone runs that file whole, not t_aone alone; the new file d.test.sh runs whole; b.test.sh, one case
# changed, runs that case alone.
t_narrowownwhole() {
  ownrun "ownedit tests/a.test.sh 'echo a;' 'echo A;' && ownedit tests/a.test.sh '^  echo 1\$' '  echo 11' && ownedit tests/b.test.sh '^  echo 2\$' '  echo 22' \
    && printf '%s\n' 't_done() {' '  echo d' '}' > tests/d.test.sh"
  [ "$(cat "$T/$CASE/rc")" = 0 ] && [ "$(cat "$STUB/got" 2>&1)" = $'one:tests/a.test.sh|\none:tests/b.test.sh|btwo\none:tests/d.test.sh|' ] \
    || fail "the changed helper's file or the new file did not run whole (exit $(cat "$T/$CASE/rc")): $(cat "$STUB/got" "$T/$CASE/run.out" 2>&1)"
  [ "$(jq -c '.list | [.files, .cases, .why]' "$T/$CASE/cards/c7.rec")" = '[3,[{"file":"tests/b.test.sh","case":"btwo"}],"the card ran 1 changed case of 1 test file, and 2 test files whole"]' ] \
    || fail "the test line's list: $(cat "$T/$CASE/cards/c7.rec")"
}

# #1000. Bug it catches: a card that changed a helper of its own test file (slotwhole.test.sh's wholerun) ran that file
# alone, never the other files that call the helper, though .conveyor/test-links.json links them to it. A change to
# a.test.sh's helper, linked to b.test.sh, c.test.sh and a file that is gone, runs a.test.sh, b.test.sh and c.test.sh
# whole: b.test.sh, which the card did not change, is added to the list (E2), and c.test.sh, whose case t_ctwo the
# card also changed, runs whole, not t_ctwo alone (E1: t_cone, which it did not change, can call the helper).
# e.test.sh, linked to nothing, one case changed, runs that case alone, and the note counts the three files run whole
# (#1011: it said one, the count taken before the linked files joined the list).
t_narrowownlinks() {
  ownrun "mkdir -p .conveyor && echo '{\"tests/a.test.sh\": [\"tests/b.test.sh\", \"tests/c.test.sh\", \"tests/gone.test.sh\"]}' > .conveyor/test-links.json \
    && ownedit tests/a.test.sh 'echo a;' 'echo A;' && ownedit tests/c.test.sh '^  echo 2\$' '  echo 22' && ownedit tests/e.test.sh '^  echo 1\$' '  echo 11'"
  [ "$(cat "$T/$CASE/rc")" = 0 ] && [ "$(sort "$STUB/got" 2>&1)" = $'one:tests/a.test.sh|\none:tests/b.test.sh|\none:tests/c.test.sh|\none:tests/e.test.sh|eone' ] \
    || fail "the changed helper's linked files did not run whole, or e.test.sh's case not alone (exit $(cat "$T/$CASE/rc")): $(cat "$STUB/got" "$T/$CASE/run.out" 2>&1)"
  [ "$(jq -c '.list | [.files, .cases, .why]' "$T/$CASE/cards/c7.rec")" = '[4,[{"file":"tests/e.test.sh","case":"eone"}],"the card ran 1 changed case of 1 test file, and 3 test files whole"]' ] \
    || fail "the test line's list: $(cat "$T/$CASE/cards/c7.rec")"
}

# D2 (#384). Bug it catches: a change with no test file of its own, linked to nearly every test file (a shared
# helper), ran all of them, about 45 minutes a card. Of 120 linked files it runs 5, each alone: the two that failed
# most recently in a test step on record, newest first, then the rest in order; the test line and output say so and
# that the run before the push runs them all, and the Board's step shows that note.
t_narrowcap() {
  caprun 120 lib/cartsum.js '' '{"card":"c1","issue":1,"step":"test","time":"2026-11-10T12:00:00Z","result":"fail","failures":{"of":1,"files":[{"file":"t100.test.js","cases":[]}],"timeout":null}}' \
    '{"card":"c2","issue":2,"step":"test","time":"2026-11-12T12:00:00Z","result":"fail","failures":{"of":1,"files":[{"file":"t090.test.js","cases":[]}],"timeout":null}}'
  local note='the change adds or changes no test file, so the card ran 5 of the 120 test files linked to it, those that failed most recently first. The run before the push runs all of them.'
  [ "$(cat "$T/$CASE/rc")" = 0 ] && [ "$(cat "$STUB/got" 2>&1)" = "$(printf 'one:%s\n' t090.test.js t100.test.js t001.test.js t002.test.js t003.test.js)" ] \
    || fail "the card did not run 5 files alone, the recently failed first (exit $(cat "$T/$CASE/rc")): $(cat "$STUB/got" "$T/$CASE/run.out" 2>&1)"
  [ "$(jq -r '.list | "\(.files) \(.left) \(.why)"' "$T/$CASE/cards/c7.rec")" = "5 115 $note" ] && grep -qxF "conveyor: $note" "$T/$CASE/cards/c7.test" \
    || fail "the test step does not say what it ran: $(cat "$T/$CASE/cards/c7.rec" "$T/$CASE/cards/c7.test")"
  [ "$(trackwhy)" = "$note" ] || fail "the Board's test step does not show the note: $(cat "$T/$CASE/cards/c7.rec")"
}
# The note the Board's card track gives card c7's passed test step, which it shows: the test line goes through the
# card's row (jq/rows.jq, its log) and then its track (jq/track.jq), as the snapshot draws it.
trackwhy() {
  jq -c '{card: "c7", issue: 7, step: "picked", time: "2026-11-17T11:00:00Z"}, ({card: "c7", issue: 7, step: "test", result: "pass", time: "2026-11-17T12:00:00Z"} + .)' "$T/$CASE/cards/c7.rec" \
    | jq -cs --argjson max 3 --arg nodeps x --arg yes x --arg lintyes x --arg shut x --arg ownshut x -f "$SRC/jq/rows.jq" \
    | jq -r "$(<"$SRC/jq/track.jq")"' .[0] | track(null; null) | .records[] | select(.name == "tests passed") | .why'
}

# Bug it catches: the cap left files out under the limit. 3 linked files all run, and the list names none left out.
t_narrowcapunder() {
  caprun 3 lib/cartsum.js
  [ "$(cat "$T/$CASE/rc")" = 0 ] && [ "$(cat "$STUB/got" 2>&1)" = "$(printf 'one:t%03d.test.js\n' 1 2 3)" ] \
    || fail "the card did not run its 3 linked files (exit $(cat "$T/$CASE/rc")): $(cat "$STUB/got" "$T/$CASE/run.out" 2>&1)"
  [ "$(jq -c '.list | [.files, .left, .why]' "$T/$CASE/cards/c7.rec")" = '[3,null,null]' ] \
    || fail "a run under the limit names files left out: $(cat "$T/$CASE/cards/c7.rec")"
}

# D3, #351 scenario 8. Bug it catches: the bug card's proof run on main gave the suite command every test file of the
# change, past the limit. With test.cardFiles 2, a change to three test files runs two on main, each alone through
# test.fileCommand (one process a file, each given its own path), the one that failed most recently first, and the
# check's result says one was left out.
t_narrowcapproof() {
  local wt=$T/$CASE/cards/c7
  setup '[]'; tune '.test.cardFiles = 2'
  printf '%s\n' 'echo "$CONVEYOR_TEST_FILE" >> "$STUB/given"; exit 1' > "$STUB/mainrun-cmd"
  echo '{"card":"c1","issue":1,"step":"test","time":"2026-11-10T12:00:00Z","result":"fail","failures":{"of":1,"files":[{"file":"d.test.sh","cases":[]}],"timeout":null}}' >> "$ST/cards.jsonl"
  git -C "$R" worktree add -q --detach "$wt" && echo two >> "$wt/a.txt" \
    && for f in a c d; do printf '%s\n' '#!/usr/bin/env bash' 'grep -qx two a.txt' > "$wt/$f.test.sh"; done && git -C "$wt" add -A || fail "the card's change could not be staged"
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" || exit 1
    names || exit 1; bugproof c7 "$wt" '{"number":7}'; cp "$wt.unfixed" "$T/$CASE/unfixed" ) > "$T/$CASE/run.out" 2>&1 \
    || fail "the check failed to run: $(cat "$T/$CASE/run.out")"
  [ "$(cat "$STUB/given" 2>&1)" = $'d.test.sh\na.test.sh' ] || fail "the proof run did not run the two files alone, d.test.sh first: $(cat "$STUB/given" "$T/$CASE/run.out" 2>&1)"
  grep -qF '1 of the 3 test files linked to the change did not run, as a card runs at most 2 (test.cardFiles)' "$T/$CASE/unfixed" && ! grep -qx -- '- c.test.sh' "$T/$CASE/unfixed" \
    || fail "the check's result does not say one file was left out: $(cat "$T/$CASE/unfixed")"
}

# Card c7's list of tests (listcmd()), on a pack changed by <filter>, when testsel() fails as jq does on a test map
# over the argument limit (#344): its stop reason in $T/$CASE/stop.
listfail() { # <pack filter>
  local wt=$T/$CASE/cards/c7
  narrowsetup; tune "$1"
  git -C "$R" worktree add -q --detach "$wt" || fail "the card's worktree could not be made"
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" || exit 1
    names || exit 1
    testsel() { echo 'jq: Argument list too long'; return 1; }
    ! listcmd "$wt" ) > "$T/$CASE/run.out" 2>&1 && cp "$wt.stop" "$T/$CASE/stop" \
    || fail "the list did not fail with a stop reason: $(cat "$T/$CASE/run.out")"
}
# Bug it catches (#344): a list of tests that could not be made stopped the card with a reason that told the owner to
# set test.fileCommand, which the pack had set. With it set, the reason says what failed and names no setting.
t_narrowlistfail() {
  listfail '.test.fileCommand = "bash one"'
  [ "$(cat "$T/$CASE/stop")" = "a card runs each of its test files alone, and the list of the card's tests could not be made: jq: Argument list too long" ] \
    || fail "the reason does not say what failed, or names a setting the pack has: $(cat "$T/$CASE/stop")"
}
# Bug it catches: with test.fileCommand not set, the reason stopped naming the setting that lets a card run its files.
t_narrowlistfailset() {
  listfail 'del(.test.fileCommand)'
  grep -qF "could not be made: jq: Argument list too long; set test.fileCommand in .conveyor/project.json to a command that runs one test file" "$T/$CASE/stop" \
    || fail "the reason with no test.fileCommand does not say what failed and name the setting: $(cat "$T/$CASE/stop")"
}

# The stub test command and file command, as setup gives them, made to add the arguments a run was given and its
# CONVEYOR_TEST_FILE to $STUB/got, a line a run.
gotcmd() { printf '%s\n' 'echo "args:$*|file:${CONVEYOR_TEST_FILE:-}" >> "$STUB/got"' > "$STUB/test-cmd"; }
# Bug it catches (#484): the per-file fixture (lib.sh filemode()) left a card's run on test.command, the whole suite.
# With setup's default fixture, a card that changes a.txt runs its linked a.test.sh alone, through test.fileCommand, and nothing else.
t_narrowfilemode() {
  setup '[]'; gotcmd
  narrowrun 'echo two >> a.txt'
  [ "$(cat "$T/$CASE/rc")" = 0 ] && [ "$(cat "$STUB/got" 2>&1)" = 'args:a.test.sh|file:a.test.sh' ] \
    || fail "the card did not run a.test.sh alone through test.fileCommand (exit $(cat "$T/$CASE/rc")): $(cat "$STUB/got" "$T/$CASE/run.out" 2>&1)"
}
# #376, #351 scenario 1. Bug it catches: with no test.fileCommand, a card whose test file has a runner Conveyor knows
# stopped at its test step. Main is a Node package (package.json), and the card adds lib/n.test.js: its test step runs
# that file alone with Conveyor's own runner, node --test (a stub node on PATH adds its arguments to $STUB/got), and
# never the test command.
t_narrowownrunner() {
  setup '[]'; gotcmd
  echo '{"name": "p"}' > "$R/package.json" && git -C "$R" add package.json && git -C "$R" commit -qm package \
    && printf '%s\n' '#!/usr/bin/env bash' 'echo "node:$*" >> "$STUB/got"' > "$STUB/node" && chmod +x "$STUB/node" || fail "the Node package could not be made"
  tune 'del(.test.fileCommand)'
  narrowrun 'mkdir -p lib && echo x > lib/n.test.js'
  [ "$(cat "$T/$CASE/rc")" = 0 ] && [ "$(cat "$STUB/got" 2>&1)" = 'node:--test lib/n.test.js' ] \
    || fail "the card did not run lib/n.test.js alone with node --test (exit $(cat "$T/$CASE/rc")): $(cat "$STUB/got" "$T/$CASE/run.out" "$T/$CASE/cards/c7.test" 2>&1)"
}
# The issue: each per-file process has the file's own time limit, and is ended with everything it started. Bug it
# catches: a test file that hangs held the card's whole run, and a process it started ran on after the run. a.test.sh
# says `# timeout: 1`, and its run starts a child in the background and hangs: each of its two runs (the first, and the
# run again of the file that failed) ends in about 1 s, a.test.sh fails as timed out, its child is gone, and b.test.sh,
# next on the list, still runs. The limit is kept at 1 s, as the case waits it out twice.
t_narrowfiletimeout() {
  local c
  setup '[]'
  printf '%s\n' 'echo "one:$CONVEYOR_TEST_FILE" >> "$STUB/got"' '[ "$CONVEYOR_TEST_FILE" = a.test.sh ] || exit 0' \
    '(sleep 300; echo leaked >> "$STUB/got") & echo $! > "$STUB/child"; sleep 300' > "$STUB/test-cmd" # sleep: a hang, which the limit cuts
  local s=$SECONDS
  # The line ends with a note, as `# timeout: 300 -- about 193s run alone` does. Bug it catches (E9 of #374's review): a
  # limit with words after it was not read, and the file had the run's limit alone.
  narrowrun 'printf "%s\n" "# timeout: 1 -- a note after the limit" > a.test.sh && echo y > b.test.sh'
  [ $((SECONDS - s)) -lt 30 ] && [ "$(cat "$T/$CASE/rc")" != 0 ] && [ "$(cat "$STUB/got" 2>&1)" = $'one:a.test.sh\none:b.test.sh\none:a.test.sh' ] \
    || fail "the hanging file was not stopped at its limit, or the next file did not run (exit $(cat "$T/$CASE/rc"), $((SECONDS - s))s): $(cat "$STUB/got" "$T/$CASE/run.out" 2>&1)"
  # E3 of #374's review. Bug it catches: the timed-out file was logged as a failed file and the run exited 1, so the
  # check on main counted a timeout there as main's failure, and the mutation check and the Board's Run action, which
  # read exit 124 as timed out, took it for a failure. The run exits 124, and its log leaves the file begun, not failed.
  [ "$(cat "$T/$CASE/rc")" = 124 ] && grep -qxF 'conveyor: a.test.sh timed out: it ran past its time limit, 1 s, and it was stopped there' "$T/$CASE/cards/c7.test" \
    && ! grep -qxF -- '-- FAIL a.test.sh' "$T/$CASE/cards/c7.test" \
    || fail "the run did not exit 124, or its output does not say a.test.sh timed out, or names it as failed (exit $(cat "$T/$CASE/rc")): $(cat "$T/$CASE/cards/c7.test")"
  c=$(cat "$STUB/child" 2>/dev/null) && [ -n "$c" ] || fail "the file's child never started"
  # The runner ends the file's process group before it returns, so the child is gone by now: one check, no wait.
  ! kill -0 "$c" 2>/dev/null || { kill "$c"; fail "a process the timed-out file started was not ended"; }
}
