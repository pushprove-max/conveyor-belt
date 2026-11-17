#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases (#280): a test command that, given a bug card's test files, runs far more test files than it was given.
# The bug-card check (bugproof()) ran the whole suite through it, for 45 minutes against under a second, and nothing
# said so: not the check's result, not doctor, not setup.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# The bug-card check of card c7, called as card() calls it, on a change that fixes a.txt and adds a.test.sh (a bash
# script, which fails on main's a.txt). On main's code the test command runs <command> ($STUB/mainrun-cmd). Then
# doctor's warning (widewarn()) as it stands, and again once the pack sets test.fileCommand. Writes $T/$CASE/unfixed
# (the check's result), $T/$CASE/rc (its exit), $T/$CASE/warn and $T/$CASE/warnfc (the two warnings). With off, the
# rule Whole suite in a card is off (the fixture's seed turns it on), and the pack's test.list is <list> (none unset).
wideproof() { # <command> [off [<list>]]
  local wt=$T/$CASE/cards/c7
  setup '[]'
  [ "${2:-}" != off ] || { jq -c '.rules.wholeSuite = false' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"; } || fail "the rule could not be turned off"
  [ -z "${3:-}" ] || tune --arg l "$3" '.test.list = $l'
  printf '%s\n' "$1" > "$STUB/mainrun-cmd"
  printf '%s\n' '#!/usr/bin/env bash' 'true' > "$R/b.test.sh" && git -C "$R" add b.test.sh && git -C "$R" commit -qm 'a test on main' || fail "main's test file"
  git -C "$R" worktree add -q --detach "$wt" && echo two >> "$wt/a.txt" && printf '%s\n' '#!/usr/bin/env bash' 'grep -qx two a.txt' > "$wt/a.test.sh" \
    && git -C "$wt" add -A || fail "the card's change could not be staged"
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" && . "$SRC/lib/setup.sh" || exit 1
    names || exit 1
    bugproof c7 "$wt" '{"number":7}'; echo $? > "$T/$CASE/rc"; cp "$wt.unfixed" "$T/$CASE/unfixed" || exit 1
    widewarn > "$T/$CASE/warn"
    tune '.test.fileCommand = "bash"'; widewarn > "$T/$CASE/warnfc" ) > "$T/$CASE/run.out" 2>&1 || fail "the check failed to run: $(cat "$T/$CASE/run.out")"
  [ ! -e "$ST/cards.jsonl" ] || recok "$ST/cards.jsonl" "the bug-card check"
}

# D1, D3. Bug it catches: a test command that ignores the files it is given ran the whole suite in the check, and
# nothing said so. Given a.test.sh alone, it runs 30 test files: the check's result names that and the fix, the card
# gets a bugproof line (result wide) with both counts and the command, and doctor warns with the fix, naming bash as
# the test.fileCommand that fits (the test files are bash scripts). Once the pack sets test.fileCommand, doctor is quiet.
t_wideran() {
  wideproof 'bash a.test.sh; r=$?; for i in $(seq 1 30); do echo "-- ok t$i.test.sh"; done; exit $r'
  local why='the test command, given 1 test file(s), ran 30 test files: it runs test files it is not given, so the bug-card check runs all of them; set test.fileCommand in .conveyor/project.json to a command that runs one test file, such as "bash", as the test files run alone as plain scripts (`bash <file>`)'
  grep -qxF "${why^}." "$T/$CASE/unfixed" && grep -q '^The run failed there (exit 1)' "$T/$CASE/unfixed" \
    || fail "the check's result did not name the test files the command ran: $(cat "$T/$CASE/unfixed")"
  [ "$(st 'select(.step == "bugproof") | [.result, (.wide | tojson)] | join(" ")')" = "wide $(jq -c '{given: 1, ran: 30, command: .test.command}' "$R/.conveyor/project.json")" ] \
    || fail "the card has no bugproof line with the counts and the command: $(st 'select(.step == "bugproof")')"
  [ "$(cat "$T/$CASE/warn")" = "warning: $why" ] || fail "doctor did not warn of the test command: $(cat "$T/$CASE/warn")"
  [ ! -s "$T/$CASE/warnfc" ] || fail "doctor still warned once the pack sets test.fileCommand: $(cat "$T/$CASE/warnfc")"
}

# D3. Bug it catches: a warning for a test command that runs only the files it is given. It runs a.test.sh alone: the
# check's result says nothing of other files, the card has no bugproof line, and doctor gives no warning.
t_widenone() {
  wideproof 'if bash a.test.sh; then echo "-- ok a.test.sh"; else echo "-- FAIL a.test.sh"; exit 1; fi'
  grep -q '^The run failed there (exit 1)' "$T/$CASE/unfixed" && ! grep -q 'test files it is not given' "$T/$CASE/unfixed" \
    || fail "the check's result named test files a command that runs only its own did not run: $(cat "$T/$CASE/unfixed")"
  [ -z "$(st 'select(.step == "bugproof")' 2>/dev/null)" ] || fail "a command that runs only its files got a bugproof line: $(st 'select(.step == "bugproof")')"
  [ ! -s "$T/$CASE/warn" ] || fail "doctor warned of a command that runs only its files: $(cat "$T/$CASE/warn")"
}

# #293. Bug it catches: with the rule Whole suite in a card off, the bug card's proof run still ran every test file of
# a command that ignores the files it is given. Given a.test.sh (test.list env), it reports 30 test files: the run is
# stopped at once, and the check fails with exit 2 (card() blocks the card), its result's first line the reason.
t_wideoff() {
  local s=$SECONDS
  wideproof 'printf %s "$CONVEYOR_TEST_FILES" > "$STUB/given"; echo "TESTRUN files=30" >> "$CONVEYOR_TEST_LOG/run"; sleep 30; exit 1' off env # sleep: a long run, which the stop cuts
  [ $((SECONDS - s)) -lt 25 ] && [ "$(cat "$T/$CASE/rc")" = 2 ] || fail "the proof run was not stopped, or the check did not fail with exit 2 (exit $(cat "$T/$CASE/rc"), $((SECONDS - s))s)"
  [ "$(cat "$STUB/given" 2>&1)" = a.test.sh ] || fail "the proof run was not given its test file: $(cat "$STUB/given" 2>&1)"
  head -n 1 "$T/$CASE/unfixed" | grep -qxF 'the rule Whole suite in a card is off, and the test command, given 1 test file(s), reported 30 test files: it runs test files it is not given, so its run was stopped; set test.list in .conveyor/project.json to the form the test command takes a list of test files in (args, placeholder with {files}, env or runner), or set test.fileCommand to a command that runs one test file' \
    || fail "the check's result does not begin with the reason: $(cat "$T/$CASE/unfixed")"
}

# #293. Bug it catches: with the rule off and a pack that sets neither test.list nor test.fileCommand, the proof run
# started test.command, which cannot be given its files and so runs the whole suite. It does not start; the check fails
# with exit 2, its result's first line the reason naming both settings.
t_wideoffnolist() {
  wideproof 'echo ran > "$STUB/ran"; exit 1' off
  [ ! -e "$STUB/ran" ] && [ "$(cat "$T/$CASE/rc")" = 2 ] || fail "the proof run started test.command, or the check did not fail with exit 2 (exit $(cat "$T/$CASE/rc"))"
  head -n 1 "$T/$CASE/unfixed" | grep -qF "the rule Whole suite in a card is off, and the test command cannot be given the card's 1 test file(s): test.list is not set, so the test command takes no list; set test.list" \
    || fail "the check's result does not begin with the reason: $(cat "$T/$CASE/unfixed")"
}

# #293. Bug it catches: with the rule off, a bug card whose change is a comment in c.sh (no test file of its own) was
# blocked as one with no test, the issue's Done-when never read: .conveyor/test-links.json links c.sh to b.test.sh, and
# the check took that link for a test the change selects, though the runner, asked, selects none for it. The runner
# (given no list: none; given files: each run) selects none, so the Done-when's b.test.sh is the proof: it passes with
# the fix and fails without it.
t_wideoffcomment() {
  local wt=$T/$CASE/cards/c7
  setup '[]'
  jq -c '.rules.wholeSuite = false' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json" || fail "the rule could not be turned off"
  tune '.test.list = "env"'
  printf '%s\n' '[ -n "${CONVEYOR_TEST_FILES:-}" ] || echo "TESTRUN files=0 of=1" >> "$CONVEYOR_TEST_LOG/r"' 'for f in ${CONVEYOR_TEST_FILES:-}; do if bash "$f"; then echo "-- ok $f"; else echo "-- FAIL $f"; exit 1; fi; done' > "$STUB/mainrun-cmd"
  echo 'echo main' > "$R/c.sh" && echo 'grep -q fixed c.sh' > "$R/b.test.sh" && echo '{"c.sh": ["b.test.sh"]}' > "$R/.conveyor/test-links.json" \
    && git -C "$R" add -f c.sh b.test.sh .conveyor/test-links.json && git -C "$R" commit -qm 'a linked test on main' || fail "main's files"
  git -C "$R" worktree add -q --detach "$wt" && echo '# fixed' >> "$wt/c.sh" && git -C "$wt" add -A || fail "the card's change could not be staged"
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" || exit 1
    names || exit 1
    bugproof c7 "$wt" "$(jq -cn '{number: 7, body: "## Done when\n- b.test.sh fails without the fix."}')"; echo $? > "$T/$CASE/rc"; cp "$wt.unfixed" "$T/$CASE/unfixed" ) \
    > "$T/$CASE/run.out" 2>&1 || fail "the check failed to run: $(cat "$T/$CASE/run.out")"
  [ "$(cat "$T/$CASE/rc")" = 0 ] && grep -q '^- b.test.sh$' "$T/$CASE/unfixed" && grep -q '^They pass with the fix, and the run without it failed' "$T/$CASE/unfixed" \
    || fail "the Done-when's test file was not the proof (exit $(cat "$T/$CASE/rc")): $(cat "$T/$CASE/unfixed" "$T/$CASE/run.out")"
}

# D2. Bug it catches: setup did not suggest test.fileCommand for test files that run alone as plain scripts (`node
# <file>`). With node:test and assert scripts, setup's suggestion (filehint()) names node, also for a test file that
# loads assert only through a shared helper it imports (b.test.mjs; it was missed when only the test file itself
# was read), and for one that loads it through a dynamic import() (d.test.mjs; missed when only static imports were
# followed); once a test file loads vitest, which plain node cannot run, it suggests nothing.
t_widehint() {
  setup '[]'
  mkdir -p "$R/src/lib" && printf '%s\n' "const test = require('node:test');" > "$R/src/a.test.js" \
    && printf '%s\n' "import { cases } from './lib/shared.mjs';" > "$R/src/b.test.mjs" \
    && printf '%s\n' "import assert from 'node:assert/strict';" > "$R/src/lib/shared.mjs" \
    && printf '%s\n' "const { check } = await import('./lib/dyn.mjs');" > "$R/src/d.test.mjs" \
    && printf '%s\n' "import assert from 'assert';" > "$R/src/lib/dyn.mjs" && git -C "$R" add src || fail "the test files"
  ( export CONVEYOR_MAIN=$R; . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/setup.sh")" || exit 1
    filehint > "$T/$CASE/node"
    printf '%s\n' "import { test } from 'vitest';" > "$R/src/c.test.js" && git -C "$R" add src && filehint > "$T/$CASE/vitest" ) \
    > "$T/$CASE/run.out" 2>&1 || fail "the suggestion failed to run: $(cat "$T/$CASE/run.out")"
  [ "$(cat "$T/$CASE/node")" = 'conveyor: the test files run alone as plain scripts (`node <file>`); set test.fileCommand to "node" in .conveyor/project.json, so a bug card'"'"'s check runs each of its test files alone' ] \
    || fail "setup did not suggest node as test.fileCommand: $(cat "$T/$CASE/node" "$T/$CASE/run.out")"
  [ ! -s "$T/$CASE/vitest" ] || fail "setup suggested a test.fileCommand for a vitest test file: $(cat "$T/$CASE/vitest")"
}
