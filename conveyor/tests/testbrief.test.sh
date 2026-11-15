#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# Engine cases: the short-summary wrapper a card session runs its tests through (tools/testbrief.sh), and the brief
# of its other commands' long output (tools/outbrief.sh), so a big result stops filling every later turn of the session.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bugs caught: the wrapper prints the whole log (the session's context fills again), drops a failure line or its line
# number (the session reruns the tests to find it), passes a failing run (its own exit code), or loses output the
# session may need to read later (the log is not the whole output). A failing command with 4,500 lines of noise on
# both streams, two failures in the middle and a summary at the end, exiting 3.
t_testbrief() {
  local d=$T/$CASE rc log out; mkdir -p "$d"
  local cmd='for i in $(seq 1500); do echo "noise $i"; echo "warn $i" >&2; done; echo "FAIL [one]: the thing broke"
    echo "not ok 7 - two"; for i in $(seq 1500); do echo "late $i"; done; echo "# pass 5"; echo "# fail 2"; exit 3'
  bash -c "$cmd" > "$d/whole" 2>&1
  TMPDIR=$d "$SRC/tools/testbrief.sh" -- bash -c "$cmd" > "$d/out" 2> "$d/err"; rc=$?
  out=$(cat "$d/out")
  [ $rc = 3 ] || fail "the wrapper exited $rc, not the command's 3"
  [ ! -s "$d/err" ] || fail "the wrapper printed to stderr: $(cat "$d/err")"
  log=$(sed -n 's/.*the whole output (4504 lines) is in \([^;]*\);.*/\1/p' <<<"$out")
  [ -n "$log" ] && [ -f "$log" ] || fail "the brief does not give the path of the whole log: $out"
  cmp -s "$log" "$d/whole" || fail "the log is not the command's whole output, both streams: $(diff "$log" "$d/whole" | head -5)"
  grep -qxF '3001:FAIL [one]: the thing broke' <<<"$out" && grep -qxF '3002:not ok 7 - two' <<<"$out" \
    || fail "the brief does not give each failure with its line in the log: $out"
  [ "$(tail -n 3 <<<"$out" | head -n 2)" = $'# pass 5\n# fail 2' ] || fail "the brief does not end with the log's summary: $out"
  ! grep -qE '^(noise|warn) ' <<<"$out" || fail "the brief prints the log's noise: $out"
  [ "$(wc -l <<<"$out")" -le 20 ] || fail "the brief is $(wc -l <<<"$out") lines, not a short summary: $out"
}

# Bug caught: output over 8,000 characters in few lines (a minified JSON, a `jq -c` of a whole file) printed whole
# through tools/outbrief.sh, as it has no lines to leave out. Each line is cut at 400 characters and the file is kept.
# (The guard's test, .claude/hooks/__tests__/bash-guardrails-outbrief.test.sh, covers many lines and short output.)
t_outbrief() {
  local d=$T/$CASE rc out; mkdir -p "$d"
  for i in 1 2 3; do printf "$i%.0s" $(seq 5000); echo; done > "$d/whole"
  cp "$d/whole" "$d/saved"
  out=$("$SRC/tools/outbrief.sh" "$d/saved" 5); rc=$?
  [ $rc = 5 ] || fail "outbrief exited $rc, not the call's 5"
  [ "$(head -n 3 <<<"$out" | awk '{ print length }' | tr '\n' ' ')" = '400 400 400 ' ] && [ "$(wc -l <<<"$out")" = 4 ] \
    || fail "three lines of 5,000 characters were not each cut at 400: $(head -c 300 <<<"$out")"
  grep -qF "the whole output (3 lines, 15003 characters) is in $d/saved;" <<<"$out" && cmp -s "$d/saved" "$d/whole" \
    || fail "the brief does not give the kept file with the whole output: $(tail -n 1 <<<"$out")"
}
