#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: what a failed test run says went wrong, read from the runners' logs and the output (testfails()).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bug: a test printed the `== ` line of a file two runners ran before the second runner began that file. The two
# earliest lines were read as the runners' own and the runner's real, later line was thrown away, so the failing case
# after it went to the file before it alone: the Board named another file for the failure and not the one that
# failed. Which of the three lines the test printed cannot be told, so the case is under each file it can be of.
# What a failed run says went wrong, as a card's test line holds it (lib/testrun.sh testfails(), the line's .failures):
# the test command $T/$CASE/cmd run as a card's test step runs it, its output and its runners' logs where a card's
# worktree <w> has them (<w>.test, <w>.testlog), then read with the given exit and the step's timeout. A whole loop run
# to read them cost each case about 2 s more; rules.test.sh's t_testfails proves a card's test line holds them.
logfails() { # <exit> [<testTimeout>]
  allfails "$@" | jq -c 'del(.passed, .okcases, .passcases)'
}
# logfails() with the files and cases the run passed.
allfails() { # <exit> [<testTimeout>]
  local w=$T/$CASE/wt; mkdir -p "$w.testlog"
  (cd "$T/$CASE" && CONVEYOR_TEST_LOG=$w.testlog bash cmd > "$w.test" 2>&1 < /dev/null)
  ( eval "$(sed -n '/^testfails() {/,/^}/p' "$SRC/lib/testrun.sh"; sed -n '/^testlogs() {/,/^}/p' "$SRC/lib/session.sh")"
    packget() { return 1; } # the pack's test.command: the logs name the run's files, so it names none
    TEST_TIMEOUT=${2:-600} testfails "$w.test" "$1" )
}
# Issue 442: a passed node case (`✔ <name> (<n>ms)`) or TAP case (`ok <n> - <name>`) was not read as passed, only a
# line `ok <case>` with no space in its case was: a main-red fix card for a named node case always blocked with "gave
# no result". Each is a passed case under its file, named as its failure line names it; a skipped TAP case is not,
# nor node's line for the file itself (a run with a name filter that ran no case, as splitstart() makes, prints it).
t_testfailspassed() {
  mkdir -p "$T/$CASE"; cat > "$T/$CASE/cmd" <<'EOF'
echo "== f.test.mjs" | tee -a "$CONVEYOR_TEST_LOG/a.log"
printf '%s\n' '✔ a b, c (12.3ms)' 'ok 2 - d e' 'ok 3 - g # SKIP no db' '✔ f.test.mjs (43.1ms)' 'ok 4 - ./f.test.mjs'
echo "-- ok f.test.mjs" >> "$CONVEYOR_TEST_LOG/a.log"
EOF
  f=$(allfails 0 | jq -c .passcases) || fail "the passed cases could not be read"
  [ "$f" = '[{"file":"f.test.mjs","cases":["a b, c","d e"]}]' ] || fail "node's ✔ and TAP's ok lines are not the file's passed cases: $f"
}
# Issue 442: redproof() with a stub runner (mainred.test.sh's redrunner) that prints node's `✔ <case> (<n>ms)` for a
# passed case: a fix whose case fails without the change and passes with it was blocked with "gave no result".
t_redproofnode() {
  redrunner ''; sed -i 's/echo "ok \$c"/echo "✔ $c (12.3ms)"/' "$STUB/mainrun-cmd"
  grep -qF '✔' "$STUB/mainrun-cmd" || fail "the stub runner does not print node's passed line"
  eng 'mainred c1 "a.test: one two, three" a.test '"$(git -C "$R" rev-parse HEAD)" || fail "the case was not recorded"
  local got; got=$(redcheck 'one two, three')
  [ "$(head -n 1 <<<"$got")" = "exit 0" ] || fail "a fix of a named node case that passes with the change did not hold: $got"
}
t_testforged() {
  mkdir -p "$T/$CASE"; cat > "$T/$CASE/cmd" <<'EOF'
begin() { echo "== $2"; echo "== $2" >> "$CONVEYOR_TEST_LOG/$1.log"; }
end() { echo "-- $3 $2" >> "$CONVEYOR_TEST_LOG/$1.log"; }
begin b shared.test.sh; echo "== shared.test.sh"; end b shared.test.sh ok
begin b b.test.sh; end b b.test.sh FAIL
begin a shared.test.sh; echo "FAIL [alpha]: wrong"; end a shared.test.sh FAIL
exit 1
EOF
  f=$(logfails 1) || fail "the failures could not be read"
  [ "$(jq -r '.files | map("\(.file):\(.cases | map(.name) | join(","))") | join(" ")' <<<"$f")" = "shared.test.sh:alpha b.test.sh:alpha" ] \
    || fail "a failing case of a file two runners ran is not under it when a test printed that file's == line first: $f"
}

# Bug: an end line of one runner's log was read as the end of a file another runner had begun and not ended: with one
# runner still in `tests/b 0s` and another's `tests/b` failing in 0s (`-- FAIL tests/b 0s`), the failure named
# `tests/b 0s` and the timeout named `tests/b`, each the other's file. And a file two runners ran, ended by one, read
# as ended in both: the timeout did not name the runner still in it. A log's end lines are of its own files.
t_testfailsown() {
  mkdir -p "$T/$CASE"; cat > "$T/$CASE/cmd" <<'EOF'
L=$CONVEYOR_TEST_LOG
echo "== tests/b 0s" | tee -a "$L/a.log" # the first log read: its runner is in this file to the end
echo "== tests/b" | tee -a "$L/b.log"; echo "-- FAIL tests/b 0s" >> "$L/b.log"
echo "== tests/b 0s" | tee -a "$L/c.log"; echo "-- ok tests/b 0s" >> "$L/c.log"
EOF
  # Exit 124: the run was cut by its timeout (2 s) in a test file that hung.
  f=$(logfails 124 2 | jq -c '[.timeout, (.files | map(.file))]') || fail "the failures could not be read"
  [ "$f" = '[{"sec":2,"file":"tests/b 0s"},["tests/b"]]' ] \
    || fail "an end line in one runner's log ended a file another runner had open: the failed file or the file the timeout names is the other runner's: $f"
}
