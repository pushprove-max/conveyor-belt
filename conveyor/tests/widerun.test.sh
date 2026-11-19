#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases (#280, #351): the bug-card check (bugproof()) ran the whole suite through a test command that, given a
# bug card's test files, ran far more, for 45 minutes against under a second. It runs each test file alone through
# test.fileCommand: a file that runs other test files is stopped, a pack with no test.fileCommand runs nothing and
# says so, and setup suggests the test.fileCommand that fits.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# The bug-card check of card c7, called as card() calls it, on a change that fixes a.txt and changes a.test.sh (a bash
# script, which fails on main's a.txt). The pack's test.fileCommand is <file command> (none: not set). On main, the
# fixture's stub commands (its test.command too) note in $STUB/ran that they ran. Writes $T/$CASE/unfixed (the
# check's result) and $T/$CASE/rc (its exit).
wideproof() { # <file command> | none
  local wt=$T/$CASE/cards/c7
  setup '[]'
  if [ "${1:-}" = none ]; then tune 'del(.test.fileCommand)'; elif [ -n "${1:-}" ]; then tune --arg f "$1" '.test.fileCommand = $f'; fi
  printf '%s\n' 'echo ran >> "$STUB/ran"; bash "$CONVEYOR_TEST_FILE"' > "$STUB/mainrun-cmd"
  git -C "$R" worktree add -q --detach "$wt" && echo two >> "$wt/a.txt" && printf '%s\n' '#!/usr/bin/env bash' 'grep -qx two a.txt' > "$wt/a.test.sh" \
    && git -C "$wt" add -A || fail "the card's change could not be staged"
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
  [ $((SECONDS - s)) -lt 25 ] && [ "$(cat "$T/$CASE/rc")" = 2 ] || fail "the proof run was not stopped, or the check did not fail with exit 2 (exit $(cat "$T/$CASE/rc"), $((SECONDS - s))s)"
  head -n 1 "$T/$CASE/unfixed" | grep -qE '^a card runs each of its test files alone, and the test command, given 1 test file\(s\), reported [23] test files: a\.test\.sh, run alone by test\.fileCommand, ran test files it is not given, so its run was stopped; ' \
    || fail "the check's result does not begin with the reason naming the file: $(cat "$T/$CASE/unfixed")"
}

# #293, #351 scenario 1. Bug it catches: with a pack that sets no test.fileCommand, the proof run started
# test.command, which runs the whole suite. Nothing runs on main; the check fails with exit 2, its result's first line
# the reason naming test.fileCommand.
t_wideoffnolist() {
  wideproof none
  [ ! -e "$STUB/ran" ] && [ "$(cat "$T/$CASE/rc")" = 2 ] || fail "the proof run ran a test, or the check did not fail with exit 2 (exit $(cat "$T/$CASE/rc"))"
  head -n 1 "$T/$CASE/unfixed" | grep -qxF "a card runs each of its test files alone, and the pack sets no test.fileCommand, so no test file can run; set test.fileCommand in .conveyor/project.json to a command that runs one test file" \
    || fail "the check's result does not begin with the reason: $(cat "$T/$CASE/unfixed")"
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
