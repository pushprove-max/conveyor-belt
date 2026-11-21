#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases (#350): a card never runs the whole suite. A card that changes the project's test runner
# (scripts/run-tests.mjs, which tests.patterns match) runs the runner's own tests, never the runner as a test; a card's
# run that reports more test files than it was given is ended at once, every process under it; the release's run is
# not limited so; a runner on a card's list (#382) is left off it.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Main holds the test runner scripts/run-tests.mjs, tests/runner.test.mjs (whose text names the runner) and
# tests/other.test.mjs; tests.patterns match all three. The test command is $STUB/suite-cmd running the runner
# (`bash "$STUB/suite-cmd" scripts/run-tests.mjs`, as `node scripts/run-tests.mjs` would), which adds `suite` to
# $STUB/got; test.fileCommand ($STUB/one) adds `one:<the file it was given>` there, a line a run.
rnsetup() {
  setup '[]'
  mkdir -p "$R/scripts" "$R/tests" && echo '// runs every test file given none' > "$R/scripts/run-tests.mjs" \
    && echo '// checks ../scripts/run-tests.mjs' > "$R/tests/runner.test.mjs" && echo x > "$R/tests/other.test.mjs" \
    && git -C "$R" add -A && git -C "$R" commit -qm files || fail "main's files could not be committed"
  echo 'echo suite >> "$STUB/got"' > "$STUB/suite-cmd"; printf '%s\n' 'echo "one:$1" >> "$STUB/got"' > "$STUB/one"
  tune '.tests.patterns = ["*.test.mjs", "scripts/*.mjs"] | .test.command = "bash \"$STUB/suite-cmd\" scripts/run-tests.mjs" | .test.fileCommand = "bash \"$STUB/one\""'
}
# Card c7's test step, tests() as card() runs it (with <field>, as the release's runs call it), on a change (a shell
# edit staged in its worktree on main): its exit in $T/$CASE/rc, its test line's fields (testrec()) in c7.rec.
rnrun() { # <change> [field]
  local wt=$T/$CASE/cards/c7
  git -C "$R" worktree add -q --detach "$wt" && (cd "$wt" && eval "$1") && git -C "$wt" add -A || fail "the card's change could not be staged"
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" || exit 1
    names || exit 1; tests "$wt" ${2:+"$2"}; echo $? > "$T/$CASE/rc"; testrec "$wt" 0 0 > "$wt.rec" ) > "$T/$CASE/run.out" 2>&1 \
    || fail "the test step could not be run: $(cat "$T/$CASE/run.out")"
}

# D1, D2, D4, #351 scenario 4. Bug it catches: a card that changed the test runner, a file tests.patterns match, put
# it on its list as a test and ran it alone, and given no list it ran the whole suite. The card runs the runner's own
# test alone (the test file that names it), never the runner, and its test line names the runner as no test, with
# the reason.
t_runnerown() {
  rnsetup
  rnrun 'echo "// faster" >> scripts/run-tests.mjs'
  [ "$(cat "$T/$CASE/rc")" = 0 ] && [ "$(cat "$STUB/got" 2>&1)" = 'one:tests/runner.test.mjs' ] \
    || fail "the card did not run the runner's own test alone (exit $(cat "$T/$CASE/rc")): $(cat "$STUB/got" "$T/$CASE/run.out" 2>&1)"
  [ "$(jq -c .list.notTests "$T/$CASE/cards/c7.rec")" = '[{"file":"scripts/run-tests.mjs","why":"the test runner, not a test"}]' ] \
    || fail "the test line does not name the runner as no test: $(cat "$T/$CASE/cards/c7.rec")"
}

# D3, D4. Bug it catches: a file that test.fileCommand runs alone and that runs every test file ran the whole suite in
# a card: the stop held only past ten files for each given, and it ended the run's timeout alone, so a process that the
# run started in a process group of its own ran on. Given tests/other.test.mjs, the file reports 3 test files: the run
# is ended at once with every process under it, and its stop names the file that ran the rest.
t_runnerstop() {
  rnsetup
  printf '%s\n' 'set -m; sleep 300 & echo $! > "$STUB/child"; set +m' 'for i in 1 2 3; do echo "-- ok t$i.test.mjs" >> "$CONVEYOR_TEST_LOG/inner"; done; sleep 30' > "$STUB/one" # sleep: a long run, which the stop cuts
  tune '.test.fileCommand = "bash \"$STUB/one\""'
  local s=$SECONDS c
  rnrun 'echo y >> tests/other.test.mjs'
  lim=$(loadlimit 20 30) # under the run's 30 s
  [ $((SECONDS - s)) -lt "$lim" ] && [ "$(cat "$T/$CASE/rc")" != 0 ] || fail "the run was not stopped (exit $(cat "$T/$CASE/rc"), $((SECONDS - s))s; limit $lim s: 20 s times the load factor $CASE_LOAD): $(cat "$T/$CASE/run.out")"
  grep -qE '^a card runs each of its test files alone, and the test command, given 1 test file\(s\), reported [23] test files: tests/other\.test\.mjs, run alone by test\.fileCommand, ran test files it is not given, so its run was stopped; ' "$T/$CASE/cards/c7.stop" \
    || fail "the stop does not name the file that ran the rest: $(cat "$T/$CASE/cards/c7.stop" "$T/$CASE/run.out" 2>&1)"
  c=$(cat "$STUB/child" 2>/dev/null) && [ -n "$c" ] || fail "the file's child never started"
  wait_until '! kill -0 "$c" 2>/dev/null' || { kill "$c"; fail "a process the run started in a group of its own was not ended"; }
}

# D3. Bug it catches: a change to the project's own test map (test.map, areas as .conveyor/engine-areas.json holds
# them) that moves a source to another area was given no test, while the project's selector runs the tests of both
# areas, so the stop ended a valid card. Moving src/a.js from area a to area b gives the command the tests of both.
t_runnermap() {
  rnsetup
  mkdir -p "$R/src" && echo x > "$R/src/a.js" && printf '%s\n' '{"area": "a", "file": "src/a.js"}' '{"area": "a", "test": "tests/runner.test.mjs"}' \
    '{"area": "b", "test": "tests/other.test.mjs"}' > "$R/areas.json" && git -C "$R" add -A && git -C "$R" commit -qm map || fail "main's map could not be committed"
  tune '.test.map = "areas.json"'
  rnrun 'jq -c "if .file then .area = \"b\" else . end" areas.json > m.new && mv m.new areas.json'
  [ "$(cat "$T/$CASE/rc")" = 0 ] && [ "$(cat "$STUB/got" 2>&1)" = $'one:tests/other.test.mjs\none:tests/runner.test.mjs' ] \
    || fail "the map's change was not given the tests of both areas (exit $(cat "$T/$CASE/rc")): $(cat "$STUB/got" "$T/$CASE/run.out" 2>&1)"
}

# D3, D4. Bug it catches: a stop on the release's run, which runs the whole suite. tests() with test.full, as the full
# test suite and release-prep run it, reports 3 test files, given none: it runs to its end and passes.
t_runnerrelease() {
  rnsetup
  tune '.test.full = "for i in 1 2 3; do echo \"-- ok t$i.test.mjs\" >> \"$CONVEYOR_TEST_LOG/r\"; done; sleep 2; echo done > \"$STUB/full\""' # sleep: the run goes on past the count, which no stop may cut
  rnrun 'echo "// faster" >> scripts/run-tests.mjs' test.full
  [ "$(cat "$T/$CASE/rc")" = 0 ] && [ -e "$STUB/full" ] && [ ! -e "$T/$CASE/cards/c7.stop" ] \
    || fail "the release's run was stopped (exit $(cat "$T/$CASE/rc")): $(cat "$T/$CASE/cards/c7.stop" "$T/$CASE/run.out" 2>&1)"
}

# Issue 382. Main holds the runner conveyor/conveyor.test.sh and two area files, conveyor/tests/a.test.sh and
# b.test.sh; <jq> tunes the pack so that a test command names the runner. Card c7's worktree is made on main.
rdsetup() { # <jq>
  setup '[]'
  mkdir -p "$R/conveyor/tests" && echo 'echo whole suite' > "$R/conveyor/conveyor.test.sh" && echo x > "$R/conveyor/tests/a.test.sh" \
    && echo x > "$R/conveyor/tests/b.test.sh" && git -C "$R" add -f conveyor && git -C "$R" commit -qm files || fail "main's files could not be committed" # -f: the fixture ignores conveyor/
  tune "$1"
  git -C "$R" worktree add -q --detach "$T/$CASE/cards/c7" || fail "the card's worktree could not be made"
}
# Runs <code> in the engine's shell (the loop's libraries sourced, names() run), its output in $T/$CASE/run.out.
rdrun() { # <code>
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; wt=$T/$CASE/cards/c7
    . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" || exit 1
    names || exit 1; eval "$1" ) > "$T/$CASE/run.out" 2>&1 || fail "the engine's code could not be run: $(cat "$T/$CASE/run.out")"
}
RDNOTE="conveyor: conveyor/conveyor.test.sh is left off the card's list: the test runner, not a test"

# Bug it catches: a card's rerun list that named the whole-suite runner (here named only by test.main) beside two area
# files had test.fileCommand run the runner as one file, so the card ran the whole suite. The two area files run, the
# runner does not, and the run's output (the card's test log) names it as left off.
t_runnerdrop() {
  rdsetup '.test.main = "bash conveyor/conveyor.test.sh" | .test.fileCommand = "bash \"$STUB/one\""'
  printf '%s\n' 'echo "$1" >> "$STUB/got"' > "$STUB/one"
  local wt=$T/$CASE/cards/c7
  printf 'fail\t%s\n' conveyor/tests/a.test.sh conveyor/conveyor.test.sh conveyor/tests/b.test.sh > "$wt.rerun"
  rdrun 'tests "$wt" test.fileCommand alone; echo $? > "$T/$CASE/rc"'
  [ "$(cat "$T/$CASE/rc")" = 0 ] && [ "$(cat "$STUB/got" 2>&1)" = $'conveyor/tests/a.test.sh\nconveyor/tests/b.test.sh' ] \
    || fail "the list did not run the two area files alone (exit $(cat "$T/$CASE/rc")): $(cat "$STUB/got" "$wt.test" "$T/$CASE/run.out" 2>&1)"
  grep -qxF "$RDNOTE" "$wt.test" || fail "the card's test log does not name the dropped runner: $(cat "$wt.test" 2>&1)"
}

# Bug it catches: a main-red entry made before issue 214 names its case under the runner (conveyor/conveyor.test.sh,
# which test.command names), and the main-red check (redrun()) gave the runner to test.command as the file to run. The
# case runs under its own file; a case with no file of its own is left off, the log naming the runner; a list left
# with nothing to run does not run test.command at all, which given no list would run its whole selection.
t_runnerred() {
  rdsetup '.test.command = "bash conveyor/conveyor.test.sh" | .test.fileCommand = "bash \"$STUB/cmd\""'
  printf '%s\n' 'cat "$CONVEYOR_TEST_RERUN" >> "$STUB/got"; echo end >> "$STUB/got"' > "$STUB/cmd"
  local wt=$T/$CASE/cards/c7 r='{"file": "conveyor/conveyor.test.sh", "files": ["conveyor/tests/a.test.sh"], "name": "x", "case": "x"}'
  local n='{"file": "conveyor/conveyor.test.sh", "files": [], "name": "y", "case": "y"}'
  rdrun "redrun \"\$wt\" '[$r, $n]' > /dev/null; cp \"\$wt.test\" \"\$T/\$CASE/both\"; redrun \"\$wt\" '[$n]' > /dev/null"
  [ "$(cat "$STUB/got" 2>&1)" = $'fail\tconveyor/tests/a.test.sh\tx\nend' ] \
    || fail "the main-red cases were not run under their own file alone: $(cat "$STUB/got" "$T/$CASE/run.out" 2>&1)"
  grep -qxF "$RDNOTE" "$T/$CASE/both" && [ "$(cat "$wt.test")" = "$RDNOTE" ] \
    || fail "the test log does not name the dropped runner: $(cat "$T/$CASE/both" "$wt.test" 2>&1)"
}

# E2 of #374's review. Bug it catches: the proof of a main-red fix (redrun()) writes a `fail` line for each failing
# case, and test.fileCommand started the same file once for each line. Two cases of one file: the file starts once.
t_runnerredonce() {
  rdsetup '.test.fileCommand = "bash \"$STUB/one\""'
  printf '%s\n' 'echo "$1" >> "$STUB/got"; cp "$CONVEYOR_TEST_RERUN" "$STUB/list"' > "$STUB/one"
  local wt=$T/$CASE/cards/c7 x='{"file": "conveyor/tests/a.test.sh", "files": [], "name": "x", "case": "x"}'
  rdrun "redrun \"\$wt\" '[$x, ${x//x\"/y\"}]' > /dev/null"
  [ "$(grep -c $'^fail\tconveyor/tests/a.test.sh\t' "$STUB/list")" = 2 ] && [ "$(cat "$STUB/got" 2>&1)" = conveyor/tests/a.test.sh ] \
    || fail "the file of two failing cases did not start once: $(cat "$STUB/got" "$STUB/list" "$T/$CASE/run.out" 2>&1)"
}

# Bug it catches: the list the map and the links give a card's run (testsel()) named the runner (here named only by
# test.full) beside an area file, and the command was given it. The command is given the area file alone, and the
# run's output is to name the runner (RUNOFF, which tests() prints).
t_runnerlist() {
  rdsetup '.test.full = "bash conveyor/conveyor.test.sh"'
  rdrun 'testsel() { printf "%s\n" "{\"by\": \"map\"}" conveyor/conveyor.test.sh conveyor/tests/a.test.sh; }
    RUNOFF=; listcmd "$wt" && printf "%s|%s|%s\n" "$TEST_GIVEN" "$TEST_FILES" "$RUNOFF" > "$T/$CASE/got"'
  [ "$(cat "$T/$CASE/got" 2>&1)" = "1|conveyor/tests/a.test.sh|conveyor/conveyor.test.sh" ] \
    || fail "the map's list kept the runner: $(cat "$T/$CASE/got" "$T/$CASE/run.out" 2>&1)"
}
