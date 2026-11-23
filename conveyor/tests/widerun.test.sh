#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases (#280, #351): the bug-card check (bugproof.sh bugproof()) ran the whole suite through a test command that, given a
# bug card's test files, ran far more, for 45 minutes against under a second. It runs each test file alone through
# test.fileCommand: a file that runs other test files is stopped, a pack with no test.fileCommand runs nothing and
# says so, and setup suggests the test.fileCommand that fits.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# A page of the repository says <text> (lines joined, spaces folded). Each case file that calls it defines its own, named after the file: the bug check puts only the card's test files on main's code, where a helper in lib.sh is missing, and the runner sources the case files into one shell, where one name cannot be defined twice.
pagesays_widerun() { tr '\n' ' ' < "$SRC/../$1" | tr -s ' ' | grep -qF -- "$2" || fail "$1 does not say \"$2\": $3"; } # <page> <text> <what the run showed>
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# The bug-card check of card c7, called as card() calls it, on a change that fixes a.txt and changes a.test.sh (a bash
# script, which fails on main's a.txt). The pack's test.fileCommand is <file command> (none: not set). On main, the
# fixture's stub commands (its test.command too) note in $STUB/ran that they ran. Writes $T/$CASE/unfixed (the
# check's result) and $T/$CASE/rc (its exit). With `two`, the change adds b.test.sh too, a copy of a.test.sh.
wideproof() { # <file command> | none [two]
  local wt=$T/$CASE/cards/c7
  setup '[]'
  if [ "${1:-}" = none ]; then tune 'del(.test.fileCommand)'; elif [ -n "${1:-}" ]; then tune --arg f "$1" '.test.fileCommand = $f'; fi
  printf '%s\n' 'echo ran >> "$STUB/ran"; bash "$CONVEYOR_TEST_FILE"' > "$STUB/mainrun-cmd"
  git -C "$R" worktree add -q --detach "$wt" && echo two >> "$wt/a.txt" && printf '%s\n' '#!/usr/bin/env bash' 'grep -qx two a.txt' > "$wt/a.test.sh" \
    && { [ "${2:-}" != two ] || cp "$wt/a.test.sh" "$wt/b.test.sh"; } && git -C "$wt" add -A || fail "the card's change could not be staged"
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" || exit 1
    names || exit 1
    bugproof c7 "$wt" '{"number":7}'; echo $? > "$T/$CASE/rc"; cp "$wt.unfixed" "$T/$CASE/unfixed" ) > "$T/$CASE/run.out" 2>&1 || fail "the check failed to run: $(cat "$T/$CASE/run.out")"
  [ ! -e "$ST/cards.jsonl" ] || recok "$ST/cards.jsonl" "the bug-card check"
}

# #350. Bug it catches: the proof run's stop held only for test.command, and only past ten files for each it was
# given, so a file that test.fileCommand runs alone and that runs every test (the test runner) ran the whole suite.
# Given a.test.sh alone, the file command reports 3 test files: the run is ended at once, and the check fails with
# exit 2, its result's first line naming the file that ran the rest.
t_wideofffile() {
  local s=$SECONDS
  # The file command, which the run gives the file as its last word (`: <file>`).
  wideproof 'for i in 1 2 3; do echo "-- ok t$i.test.sh" >> "$CONVEYOR_TEST_LOG/inner"; done; sleep 30; :' # sleep: a long run, which the stop cuts
  lim=$(loadlimit 25 30) # under the run's 30 s
  [ $((SECONDS - s)) -lt "$lim" ] && [ "$(cat "$T/$CASE/rc")" = 2 ] || fail "the proof run was not stopped, or the check did not fail with exit 2 (exit $(cat "$T/$CASE/rc"), $((SECONDS - s))s; limit $lim s: 25 s times the load factor $CASE_LOAD)"
  head -n 1 "$T/$CASE/unfixed" | grep -qE '^a card runs each of its test files alone, and the test command, given 1 test file\(s\), reported [23] test files: a\.test\.sh, run alone by test\.fileCommand, ran test files it is not given, so its run was stopped; ' \
    || fail "the check's result does not begin with the reason naming the file: $(cat "$T/$CASE/unfixed")"
}

# R115. Bug it catches: a run that reported too many files and exited between two looks of watch() was never
# counted, as the count ran only while the run did: the run given a.test.sh alone, whose file command reports 5 file
# results and exits at once, passed. It is counted once more as it ends: the check fails with exit 2, its result's
# first line naming the wide run.
t_widefast() {
  wideproof 'for f in a t1 t2 t3 t4; do echo "-- ok $f.test.sh" >> "$CONVEYOR_TEST_LOG/inner"; done; :'
  [ "$(cat "$T/$CASE/rc")" = 2 ] || fail "the check of a run that reported 5 files and exited at once did not fail with exit 2 (exit $(cat "$T/$CASE/rc")): $(head -n 3 "$T/$CASE/unfixed")"
  head -n 1 "$T/$CASE/unfixed" | grep -qE '^a card runs each of its test files alone, and the test command, given 1 test file\(s\), reported 5 test files: a\.test\.sh, run alone by test\.fileCommand, ran test files it is not given, so its run was stopped; ' \
    || fail "the check's result does not begin with the reason naming the wide run: $(cat "$T/$CASE/unfixed")"
}

# R135. Bug it catches: a run file by file was stopped only when the whole run's count went over the files it was
# given, so with two files an invocation given the first that ran both was not stopped (2 of 2), and the run went on to
# the second file. The file command, given a.test.sh, reports a.test.sh and b.test.sh and then runs on: the run is
# stopped in that first invocation (well under its 30 s), and the result's first line names a.test.sh.
t_wideeach() {
  local s=$SECONDS
  wideproof 'for f in a b; do echo "-- ok $f.test.sh" >> "$CONVEYOR_TEST_LOG/inner"; done; sleep 30; :' two # sleep: a long invocation, which the stop cuts
  lim=$(loadlimit 25 30) # under the first invocation's 30 s
  [ $((SECONDS - s)) -lt "$lim" ] && [ "$(cat "$T/$CASE/rc")" = 2 ] || fail "the invocation given a.test.sh that ran both files was not stopped, or the check did not fail with exit 2 (exit $(cat "$T/$CASE/rc"), $((SECONDS - s))s; limit $lim s: 25 s times the load factor $CASE_LOAD)"
  head -n 1 "$T/$CASE/unfixed" | grep -qE '^a card runs each of its test files alone, and the test command, given 2 test file\(s\) one at a time, reported 2 test files before it had begun them all: a\.test\.sh, run alone by test\.fileCommand, ran test files it is not given, so its run was stopped; ' \
    || fail "the check's result does not begin with the reason naming a.test.sh: $(cat "$T/$CASE/unfixed")"
}

# R135. Bug it catches: the run was stopped only when its totals were over, so an invocation given a.test.sh that
# reported both files and ended before watch() looked, the one given b.test.sh then begun, showed 2 files of 2 begun,
# and the run passed. What was reported before b.test.sh began is counted: the check fails with exit 2, and the
# result's first line names a.test.sh.
t_wideeachfast() {
  wideproof 'for f in a b; do echo "-- ok $f.test.sh" >> "$CONVEYOR_TEST_LOG/inner"; done; :' two
  [ "$(cat "$T/$CASE/rc")" = 2 ] || fail "the check of a run whose first invocation reported both files and ended did not fail with exit 2 (exit $(cat "$T/$CASE/rc")): $(head -n 3 "$T/$CASE/unfixed")"
  head -n 1 "$T/$CASE/unfixed" | grep -qE '^a card runs each of its test files alone, and the test command, given 2 test file\(s\) one at a time, reported 2 test files before it had begun them all: a\.test\.sh, run alone by test\.fileCommand, ran test files it is not given, so its run was stopped; ' \
    || fail "the check's result does not begin with the reason naming a.test.sh: $(cat "$T/$CASE/unfixed")"
}

# #293, #351 scenario 1. Bug it catches: with a pack that sets no test.fileCommand, the proof run started
# test.command, which runs the whole suite. Nothing runs on main; the check fails with exit 2, its result's first line
# the reason naming test.fileCommand.
t_wideoffnolist() {
  wideproof none
  [ ! -e "$STUB/ran" ] && [ "$(cat "$T/$CASE/rc")" = 2 ] || fail "the proof run ran a test, or the check did not fail with exit 2 (exit $(cat "$T/$CASE/rc"))"
  head -n 1 "$T/$CASE/unfixed" | grep -qxF "a card runs each of its test files alone, and the pack sets no test.fileCommand, and Conveyor cannot run a.test.sh itself: it has no runner for a file of this kind; set test.fileCommand in .conveyor/project.json to a command that runs one test file" \
    || fail "the check's result does not begin with the reason: $(cat "$T/$CASE/unfixed")"
  # Bug (#1436): the guide said a bug card gives its files to test.command, whose run covers the suite. The run above
  # shows the check stops with exit $rc and names test.fileCommand; the guide says both.
  local rc; rc=$(cat "$T/$CASE/rc")
  pagesays_widerun docs/configuration.md "the check stops with exit $rc and runs no test" "the bug check with no test.fileCommand ended with exit $rc and ran no test"
  pagesays_widerun docs/configuration.md 'runs each of the card'"'"'s test files alone, on main'"'"'s code without the fix, with `test.fileCommand`' "the bug check runs each file alone through test.fileCommand"
  ! grep -q 'gives the card'"'"'s test files to your test command' "$SRC/../docs/configuration.md" \
    || fail "docs/configuration.md still says the bug check gives the files to test.command, which the run above never runs"
}

# D2. Bug it catches: setup did not suggest test.fileCommand for test files that run alone as plain scripts (`node
# <file>`). With node:test and assert scripts, setup's suggestion (filehint()) names node, also for a test file that
# loads assert only through a shared helper it imports (b.test.mjs; it was missed when only the test file itself
# was read), and for one that loads it through a dynamic import() (d.test.mjs; missed when only static imports were
# followed); once a test file loads vitest, which plain node cannot run, it suggests nothing.
t_widehint() {
  setup '[]'; tune 'del(.test.fileCommand)'; git -C "$R" rm -q a.test.sh || fail "the fixture's a.test.sh"
  mkdir -p "$R/src/lib" && printf '%s\n' "const test = require('node:test');" > "$R/src/a.test.js" \
    && printf '%s\n' "import { cases } from './lib/shared.mjs';" > "$R/src/b.test.mjs" \
    && printf '%s\n' "import assert from 'node:assert/strict';" > "$R/src/lib/shared.mjs" \
    && printf '%s\n' "const { check } = await import('./lib/dyn.mjs');" > "$R/src/d.test.mjs" \
    && printf '%s\n' "import assert from 'assert';" > "$R/src/lib/dyn.mjs" && git -C "$R" add src || fail "the test files"
  ( export CONVEYOR_MAIN=$R; . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/setup.sh")" || exit 1
    filehint > "$T/$CASE/node"
    printf '%s\n' "import { test } from 'vitest';" > "$R/src/c.test.js" && git -C "$R" add src && filehint > "$T/$CASE/vitest" ) \
    > "$T/$CASE/run.out" 2>&1 || fail "the suggestion failed to run: $(cat "$T/$CASE/run.out")"
  [ "$(cat "$T/$CASE/node")" = 'conveyor: the test files run alone as plain scripts (`node <file>`); set test.fileCommand to "node" in .conveyor/project.json, so a card runs each of its test files alone' ] \
    || fail "setup did not suggest node as test.fileCommand: $(cat "$T/$CASE/node" "$T/$CASE/run.out")"
  [ ! -s "$T/$CASE/vitest" ] || fail "setup suggested a test.fileCommand for a vitest test file: $(cat "$T/$CASE/vitest")"
}
