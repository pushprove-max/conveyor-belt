#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the rule Skip the Test step (rules.testskip, lib/testrun.sh testskip()). On, a card runs no test in its
# Test step: not before its first review (no test line marked before "review"), not at the step, and not on main's code
# to prove a bug card's fix. Its test line says skipped, and it lands. Off (the default), the step runs as before. With either setting a card's sessions
# keep their own test runs: only the rule Only the Test step runs tests takes those away.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
SKIPWHY='the rule Skip the Test step is on: no test ran'

# skipcard: bug card #7, whose build fixes a.txt and adds a test that fails on main's code without the fix (provenbug).
# Each run of its tests is a line in $STUB/tests, the run before its first review too ($STUB/pretests), and each run of
# its test on main's code, the bug-card check, a line in $STUB/mainruns.
skipcard() {
  setup "[$(issue 7 2026-01-01 bug)]"; echo "$GO" > "$STUB/review.1"; provenbug; : > "$STUB/pretests"
  echo 'echo x >> "$STUB/mainruns"; bash a.test.sh' > "$STUB/mainrun-cmd"
}

# Bug it catches: the owner had no rule to land cards without their Test step, so every card paid for its test runs;
# or, with the rule on, a card still ran a test (before its review, at its Test step, or on main's code for its
# bug-card check), or its test line read as a pass or a failure, or the card did not land.
t_testskipon() {
  local out
  skipcard
  loop control rules testskip=on > /dev/null && [ "$(loop control | jq -c .rules.testskip)" = true ] \
    || fail "control rules testskip=on did not set the rule on: $(loop control | jq -c .rules)"
  # loop: the rule holds across a card's steps (the run before its review, the bug-card check, the Test step and the landing); only a whole card shows that none of them ran a test and that the card still lands
  out=$(loop run 1 2>&1) || fail "the loop failed with the rule on: $out"
  [ ! -s "$STUB/tests" ] || fail "with the rule on, the card ran its tests $(grep -c . "$STUB/tests") time(s): $(st 'select(.step == "test")')"
  [ ! -e "$STUB/mainruns" ] || fail "with the rule on, the bug-card check ran the card's test on main's code"
  [ "$(st 'select(.issue == 7 and .step == "test") | "\(.result): \(.reason)"')" = "skipped: $SKIPWHY" ] \
    || fail "the card's test line is not one line, result skipped, that says no test ran: $(st 'select(.issue == 7 and .step == "test")')"
  # The run of its tests before its first review is part of the Test step: no start line and no test line marked before "review".
  [ -z "$(st 'select(.issue == 7 and (.step == "test" or (.step == "start" and .of == "test")) and .before == "review")')" ] \
    || fail "with the rule on, the card began or recorded a test run before its review: $(st 'select(.issue == 7 and .before == "review")')"
  [ "$(st 'select(.issue == 7 and .step == "bugproof") | "\(.result): \(.reason)"')" = "skipped: $SKIPWHY" ] \
    || fail "the card's bugproof line does not say the check was skipped for the rule: $(st 'select(.issue == 7 and .step == "bugproof")')"
  [ -n "$(st 'select(.issue == 7 and .step == "landed") | .sha')" ] && [ "$(git -C "$R" show main:a.txt | grep -c .)" = 2 ] \
    || fail "with the rule on, the card did not land its change: $out"
  recok "$ST/cards.jsonl" "a card with the rule Skip the Test step on"
  # The Board draws the step as skipped, never as failed, and counts no test run for the card.
  [ "$(loop snapshot | jq -c '.landed[] | select(.issue == 7) | [(.track.steps[] | select(.name == "Test") | .state), (.track.records | map(.name) | index("tests skipped") != null), .metrics.testRuns]')" = '["skipped",true,0]' ] \
    || fail "the card's track does not draw its Test step as skipped, or its test line as tests skipped, or it counts a test run: $(loop snapshot | jq -c '.landed[] | select(.issue == 7) | [.track.steps, (.track.records | map(.name)), .metrics.testRuns]')"
}

# Bug it catches: the rule, off in a new project, changed a card's Test step; or it could not be turned off again. Off
# by default and after `control rules testskip=off`, the same card runs its tests and its bug-card check, and its test
# lines are passes.
t_testskipoff() {
  local out
  skipcard
  [ "$(loop control | jq -c .rules.testskip)" = false ] || fail "the rule Skip the Test step is not off in a new control record: $(loop control | jq -c .rules)"
  loop control rules testskip=on > /dev/null && loop control rules testskip=off > /dev/null && [ "$(loop control | jq -c .rules.testskip)" = false ] \
    || fail "control rules testskip=off did not set the rule off: $(loop control | jq -c .rules)"
  # loop: the same whole card as t_testskipon, with the rule off: each of those steps runs its tests
  out=$(loop run 1 2>&1) || fail "the loop failed with the rule off: $out"
  [ -s "$STUB/tests" ] && [ -s "$STUB/mainruns" ] || fail "with the rule off, the card did not run its tests and its bug-card check: $out"
  [ "$(st 'select(.issue == 7 and .step == "test") | .result' | sort -u)" = pass ] \
    || fail "with the rule off, the card's test lines are not passes: $(st 'select(.issue == 7 and .step == "test")')"
  [ -z "$(st 'select(.issue == 7 and .step == "bugproof" and .result == "skipped")')" ] || fail "with the rule off, the bug-card check was skipped: $(st 'select(.step == "bugproof")')"
  [ -n "$(st 'select(.issue == 7 and .step == "landed") | .sha')" ] || fail "with the rule off, the card did not land: $out"
}

# The owner's order (2026-11-28): the rule does not keep a build or fix session from running tests as it works. Bug it
# catches: the rule wired into a session's card rules (cardrules(), lib/prompts.sh), which then left out the session's
# own test runs, or into what the builder gives the card's command guard (builder(), lib/session.sh: CONVEYOR_TESTSTEPONLY),
# which then refused the session's test command. With Skip the Test step on and Only the Test step runs tests off, the
# card rules are the files' text and the guard lets a test command run; the same probe with Only the Test step runs
# tests on is refused, so it would see the guard refuse.
t_testskipsessions() {
  local core own out hook=${SRC%/*}/.claude/hooks/bash-guardrails.sh
  setup "[$(issue 7 2026-01-01)]"
  loop control rules testskip=on > /dev/null && [ "$(loop control | jq -c '[.rules.testskip, .rules.teststeponly]')" = '[true,false]' ] \
    || fail "control rules testskip=on did not set that rule alone: $(loop control | jq -c .rules)"
  core=$(cat "$SRC/rules/card-core.md"); own=$(cat "$R/.conveyor/card-rules.md")
  grep -qxF 'Your own test runs, in a build or fix session:' <<<"$core" || fail "the core card rules have no paragraph on a session's own test runs"
  fx_in 'cardrules "{\"title\": \"t\", \"body\": \"\"}" > "$T/$CASE/rules"'; [ "$RC" = 0 ] || fail "the card rules could not be made: $(cat "$T/$CASE/run.out")"
  [ "$(cat "$T/$CASE/rules")" = "$core"$'\n\n'"$own" ] \
    || fail "with Skip the Test step on, a session's card rules are not the files' text, its own test runs included: $(cat "$T/$CASE/rules")"
  # Each session asks the card's command guard, in the environment builder() gave it, whether a test command may run,
  # and notes the rule it was given and the guard's exit; any call answers one result line. The guard reads the pack
  # of the session's project: main's here, as the fixture's pack is not committed, so the worktree has none.
  # stub: the shared stub cannot run the command guard from inside the session, in the environment builder() gave it
  cat > "$STUB/claude" <<EOF
#!/usr/bin/env bash
cat > /dev/null
jq -cn --arg d "\$PWD" '{tool_input: {command: "node --max-old-space-size=4096 --test tests/one.test.mjs"}, cwd: \$d, session_id: "s"}' \\
  | CLAUDE_PROJECT_DIR=$R CONVEYOR_GUARD_STATE=$T/$CASE/guard bash "$hook" > /dev/null 2>> "$STUB/guard.err"
echo "\${CONVEYOR_TESTSTEPONLY:-unset} \$?" >> "$STUB/calls"
echo '{"type":"result","is_error":false,"result":"done","num_turns":1,"usage":{"input_tokens":3,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":2}}'
EOF
  chmod +x "$STUB/claude"; mkdir -p "$T/$CASE/cards" "$T/$CASE/guard"
  out=$( ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" && names || exit 1
    w=$CARDS/c7 && git -C "$MAIN" worktree add -q --detach "$w" || exit 1
    ( CARDCTL='{"rules": {"testskip": true, "teststeponly": false}}' builder "$w" brief m medium "" claude )
    ( CARDCTL='{"rules": {"testskip": false, "teststeponly": true}}' builder "$w" brief m medium "" claude ) ) 2>&1 )
  [ "$(paste -sd , "$STUB/calls" 2>/dev/null)" = '0 0,1 2' ] \
    || fail "a session with Skip the Test step on was not let run a test command (wanted rule 0, guard exit 0), or the probe with Only the Test step runs tests on was not refused (rule 1, exit 2): $(cat "$STUB/calls" "$STUB/guard.err" 2>&1) $out"
}
