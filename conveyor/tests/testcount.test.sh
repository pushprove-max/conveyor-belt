#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: how far a running test run has got, in its live record and the snapshot (conveyor.sh watch(),
# track.tests). The engine's own runner's part in it is testcountrunner.test.sh's: together they were over the test
# step's CPU budget for one file.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# A card's test run, held open until $STUB/go, after its command <prints> and names cases in the folders of its log:
# ok/ and failed/ for those that ended, and one still running. Waits until the live record's <field> is <want>.
# The card c7 is at its test step by its records, and the command is run and watched as its test step does it
# (lib/testrun.sh testonce(): the engine's own watch(), on the output and logs where a card's worktree has them). A
# whole loop run to that step cost each case about 3 s more; views.test.sh's t_live reads a real run's test step.
countrun() { # <prints> <field> <want>
  local w=$T/$CASE/cards/c7 now
  setup "[$(issue 7 2026-01-01)]"; mkdir -p "$ST" "$w.testlog"; now=$(date -u +%FT%TZ)
  printf '%s\n' picked worktree deps brief start:build build start:review review:GO start:test | jq -cR --arg t "$now" 'split(":") as [$s, $x]
    | {card:"c7",issue:7,step:$s,time:$t,tokens:{claude:0,codex:0},result:"ok",sha:"",reason:""}
      + if $s == "start" then {of: $x} elif $x then {result: $x} else {} end' > "$ST/cards.jsonl"
  { printf '%s\n' "$1"; cat <<'EOF'
C=$CONVEYOR_TEST_LOG/cases; mkdir -p "$C/ok" "$C/failed"; : > "$C/ok/a"; : > "$C/ok/b"; : > "$C/failed/c"; : > "$C/d"
while [ -d "$STUB" ] && [ ! -e "$STUB/go" ]; do sleep 0.1; done
EOF
  } > "$STUB/test-cmd"
  ( . "$SRC/lib/portable.sh"; eval "$(for f in watch testlogs testcases testdone; do sed -n "/^$f() {/,/^}/p" "$SRC/lib/session.sh"; done)"; LIVE=0.2
    (cd "$T/$CASE" && CONVEYOR_TEST_LOG=$w.testlog exec bash "$STUB/test-cmd" > "$w.test" 2>&1 < /dev/null) &
    watch $! "$w.test" "$w.live" test ) > "$T/$CASE/run.out" 2>&1 & run=$!
  wait_until "jq -e --argjson w '$3' '.$2 == \$w' '$w.live'" "cat '$w.live'" \
    || { : > "$STUB/go"; wait $run; fail "the live record's $2 is never $3: $(cat "$T/$CASE/run.out")"; }
}

# Bug: a card in its Test step showed only "0 turns", and a run of one test file with 205 cases read "0 of 1" until it
# ended. A command that says it selected 5 cases (two lines, 3 and 2, that add up) and whose runner has named three
# cases as ended, one failed, and one as running: the live record and the snapshot's track say 3 done of 5, 1 failed.
t_testcountcases() {
  countrun $'echo "TESTRUN cases=3"\necho "TESTRUN cases=2"' tests '{"done":3,"of":5,"failed":1}'
  [ "$(loop snapshot | jq -c '.belt[0].track | [.tests, .files]')" = '[{"done":3,"of":5,"failed":1},{"run":0,"of":null}]' ] \
    || { : > "$STUB/go"; wait $run; fail "the snapshot's track does not count the cases: $(loop snapshot | jq -c '.belt[0].track')"; }
  : > "$STUB/go"; wait $run || fail "the watch of the test run exited non-zero: $(cat "$T/$CASE/run.out")"
}

# A command that gives no case count leaves tests null, its runner's case records or not, and its files as they were
# counted before: of from `TESTRUN files=N`, run from its `-- ok` lines.
t_testcountnone() {
  countrun $'echo "TESTRUN files=2"\necho "-- ok x.test.sh"' files '{"run":1,"of":2}'
  jq -e 'has("tests") and .tests == null' "$T/$CASE/cards"/*.live >/dev/null \
    || { : > "$STUB/go"; wait $run; fail "a run with no case count does not have tests null: $(cat "$T/$CASE/cards"/*.live)"; }
  [ "$(loop snapshot | jq -c '.belt[0].track | [has("tests"), .tests, .files]')" = '[true,null,{"run":1,"of":2}]' ] \
    || { : > "$STUB/go"; wait $run; fail "the snapshot's track with no case count: $(loop snapshot | jq -c '.belt[0].track')"; }
  : > "$STUB/go"; wait $run || fail "the watch of the test run exited non-zero: $(cat "$T/$CASE/run.out")"
}
