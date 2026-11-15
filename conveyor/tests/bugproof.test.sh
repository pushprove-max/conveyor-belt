#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the bug-card check (bugproof()): a bug card's new tests must fail on main's code without the fix.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# One card of #7 with the given labels: its build fixes a.txt (adds `two`; runs $FIX in its place when set, `:` for no
# fix) and, unless <test> is empty, adds a.test.sh holding <test>. The run on main (a worktree under cards/mainrun/) notes its folder and staged files in
# $STUB/mainran and runs a.test.sh, then what $MAINRUN holds, if any; the reviewer's prompt is kept in $STUB/asked;
# one GO review.
bugcard() { # <test> <label>...
  local t=$1; shift
  setup "[$(issue 7 2026-01-01 "$@")]"
  sed -i 's|^cat > /dev/null; echo x|cat > "$STUB/asked"; echo x|' "$STUB/codex"
  echo "$GO" > "$STUB/review.1"
  echo "${FIX-echo two >> a.txt}${t:+; printf '%s\n' '$t' > a.test.sh}" > "$STUB/build"
  echo '{ pwd; git diff --cached --name-only; } >> "$STUB/mainran"; '"${MAINRUN:-bash a.test.sh}" > "$STUB/mainrun-cmd"
  loop run >/dev/null || fail "run exited non-zero"
}

# D1. Bug it catches: a bug card whose new test fails without the fix (it proves the fix) is sent back to build, or
# its test runs on main with the fix in it, or the review is not shown the result. The test runs on main's code with
# the card's test file alone; one build session; the review sees that it failed there; the card lands.
t_bugfails() {
  bugcard 'grep -qx two a.txt' bug
  [ "$(wc -l < "$STUB/sessions")" = 1 ] && [ "$(st 'select(.step == "build") | .result' | wc -l)" = 1 ] \
    || fail "a bug card whose new test fails on main went back to build: $(st 'select(.step == "build")')"
  [ "$(sed 1d "$STUB/mainran" | tr '\n' ' ')" = 'a.test.sh ' ] && [[ $(head -1 "$STUB/mainran") == */cards/mainrun/* ]] \
    || fail "the run on main was not of main's code with the card's test file alone: $(cat "$STUB/mainran" 2>&1)"
  grep -qx '# The bug-card check' "$STUB/asked" && grep -q '^The run failed there (exit 1)' "$STUB/asked" \
    || fail "the review was not shown that the new test fails on main: $(cat "$STUB/asked")"
  [ -n "$(st 'select(.step == "landed") | .sha')" ] && [ -z "$(ls "$T/$CASE/cards")" ] || fail "the card did not land, or left a worktree: $(ls "$T/$CASE/cards")"
}

# D2. Bug it catches: a bug card whose new test passes on main's code (it proves nothing of the fix) goes on to review
# as if proven. It goes back to its build session, told why, its build line saying so; the check runs again after
# it, and as the test still passes there the card is blocked with that reason, never reviewed.
t_bugpasses() {
  bugcard 'grep -qx one a.txt' bug
  [ "$(st 'select(.step == "build") | .reason // ""' | tr '\n' '|')" = "|the new tests pass without the fix, so they do not prove it|" ] \
    || fail "the card did not go back to its build with the reason: $(st 'select(.step == "build")')"
  grep -q '^# Back to the build: the new tests pass without the fix, so they do not prove it$' "$STUB/brief" && grep -qx -- '- a.test.sh' "$STUB/brief" \
    || fail "the second build session was not told why, naming the test file: $(tail -n 20 "$STUB/brief")"
  [ "$(grep -c '/cards/mainrun/' "$STUB/mainran")" = 2 ] || fail "the check did not run on main after each build: $(cat "$STUB/mainran" 2>&1)"
  [ ! -e "$STUB/asked" ] && [ "$(st 'select(.step == "blocked") | .reason')" = "build: the new tests pass without the fix, so they do not prove it" ] \
    || fail "a bug card whose test still passed on main after its second build was not blocked before review: $(st 'select(.step | IN("review", "blocked"))')"
  loop check || fail "the record check refuses a build line with the reason"
}

# Bug it catches: a run on main that fails only because its runner stopped it (its own check refused the run, as an
# area map without the card's new test file does) is taken for a test that fails without the fix. Here the runner's
# log says a.test.sh ran and passed, and the runner exits 1: the card goes back to its build, told no test failed.
t_bugrunner() {
  MAINRUN='echo "== a.test.sh" > "$CONVEYOR_TEST_LOG/r"; bash a.test.sh && echo "-- ok a.test.sh" >> "$CONVEYOR_TEST_LOG/r"; exit 1' \
    bugcard 'grep -qx one a.txt' bug
  [ "$(st 'select(.step == "build") | .reason // ""' | tr '\n' '|')" = "|the new tests pass without the fix, so they do not prove it|" ] \
    && grep -q '^The run failed there (exit 1), but no test failed in it' "$STUB/brief" \
    || fail "a runner's own failure on main was taken for the new test failing: $(st 'select(.step == "build")'; tail -n 20 "$STUB/brief")"
}

# Bug it catches: a bug card whose change is a test file alone (a test fixed for a red main, which passes on main's
# code too) is blocked, as with no fix to take out its test passes "without the fix". It is not run on main, has one
# build session, its review is told the change is test-only, and it lands.
t_bugtestonly() {
  FIX=: bugcard 'grep -qx one a.txt' bug
  [ "$(wc -l < "$STUB/sessions")" = 1 ] && [ ! -e "$STUB/mainran" ] \
    || fail "a test-only bug card was run on main or sent back to build: $(st 'select(.step == "build")'; cat "$STUB/mainran" 2>&1)"
  grep -qx '# The bug-card check' "$STUB/asked" && grep -q '^The change is test-only: ' "$STUB/asked" \
    || fail "the review was not told the change is test-only: $(cat "$STUB/asked" 2>&1)"
  [ -n "$(st 'select(.step == "landed") | .sha')" ] || fail "a test-only bug card did not land: $(st 'select(.step | IN("blocked", "landed"))')"
}

# Bug it catches: a bug card that adds no test at all goes to review unchecked. It is told the same, with no run on main.
t_bugnotest() {
  bugcard '' bug
  [ "$(st 'select(.step == "build") | .reason // ""' | tr '\n' '|')" = "|the new tests pass without the fix, so they do not prove it|" ] \
    && grep -q '^The change adds or changes no test file' "$STUB/brief" || fail "a bug card with no test did not go back to its build, told so: $(st 'select(.step == "build")')"
  [ ! -e "$STUB/mainran" ] || fail "a card with no test file ran something on main"
}

# Bug it catches: a bug card whose build changed nothing (an ALREADY-DONE, or a session that did nothing) is sent to
# build again to add a test, in place of going its own way. One session, and the card ends as a card with no change.
t_bugnochange() {
  setup "[$(issue 7 2026-01-01 bug)]"; echo ':' > "$STUB/build"
  loop run >/dev/null 2>&1
  [ "$(wc -l < "$STUB/sessions")" = 1 ] && st 'select(.step == "blocked") | .reason' | grep -q 'the session made no change' \
    || fail "a bug card with no change went back to build: $(st 'select(.step | IN("build", "blocked"))')"
}

# D3. Bug it catches: a card whose issue is not a bug is held to the check. Its test passes on main, and it still has
# one build session, no run on main, and a review that is not shown the check.
t_notbug() {
  bugcard 'grep -qx one a.txt' area:billing
  [ "$(wc -l < "$STUB/sessions")" = 1 ] && [ ! -e "$STUB/mainran" ] && ! grep -q 'bug-card check' "$STUB/asked" \
    || fail "a card that is not a bug was checked: $(cat "$STUB/mainran" 2>&1)"
}
