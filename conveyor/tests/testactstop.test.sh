#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the test actions' stop (lib/testaction.sh): `testaction stop <id>` ends one running session or run by
# hand, with each process it started (taend()). Their fixtures are testaction.test.sh's tasetup and tarec, and
# testactrun.test.sh's trsetup and trfree.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bug this guards: a stop ended every running action, or none; a stopped one's record still said running.
t_tastop() {
  tasetup; local a b out
  loop control tests claude m-tests > /dev/null || fail "control tests was refused"
  a=$(loop testaction judge tests/x.test.sh 2>&1) && b=$(loop testaction explain tests/x.test.sh 2>&1) || fail "the two actions did not start: $a $b"
  wait_until "[ \"\$(grep -c . '$STUB/ta-tries' 2>/dev/null)\" = 4 ]" || fail "the two sessions did not both run"
  out=$(loop testaction stop "$a" 2>&1) || fail "the stop failed: $out"
  [ "$(tarec "$a" '[.state, (.end | type)] | tojson')" = '["stopped","string"]' ] || fail "the stopped action's record does not say stopped: $(cat "$ST/testactions/$a.json")"
  [ "$(tarec "$b" .state)" = running ] && kill -0 "$(tarec "$b" .pid)" 2>/dev/null || fail "the stop of one action stopped the other: $(cat "$ST/testactions/$b.json")"
  # Of the two sessions (each stub's pid ends its prompt file's name), the stopped one's has ended and the other's runs.
  out=$(for p in "$STUB"/ta-prompt.*; do kill -0 "${p##*.}" 2>/dev/null && echo up || echo gone; done | sort | tr '\n' ' ')
  [ "$out" = 'gone up ' ] || fail "the stop did not end that one session alone: $out"
  out=$(loop snapshot | jq -c '[.testActions.actions[] | [.id, .state]] | sort')
  [ "$out" = "$(jq -cn --arg a "$a" --arg b "$b" '[[$a, "stopped"], [$b, "running"]] | sort')" ] || fail "the snapshot does not list each action with its state: $out"
  out=$(loop testaction stop "$a" 2>&1); [ $? = 2 ] || fail "a stop of an action that is not running was not refused: $out"
  : > "$STUB/ta-go"
  wait_until "[ \"\$(tarec $b .state)\" = done ]" "cat '$ST/testactions/$b.json'" || fail "the action that was not stopped did not end done"
  [ "$(tarec "$b" .verdict)" = null ] || fail "an explain has a verdict: $(cat "$ST/testactions/$b.json")"
}

# Bug this guards (issue 517): a stopped run went on, or kept its test slot from every card.
t_tarunstop() {
  trsetup; local id out
  id=$(loop testaction run tests/x.test.sh 2>&1) && [[ $id =~ ^[0-9a-f]{12}$ ]] || fail "the run did not start: $id"
  wait_until '[ -s "$STUB/tr-held" ]' "cat '$ST/testactions/$id.err'" || fail "the test command did not start"
  out=$(loop testaction stop "$id" 2>&1) || fail "the stop failed: $out"
  [ "$(tarec "$id" '[.state, .result, (.end | type)] | tojson')" = '["stopped",null,"string"]' ] || fail "the stopped run's record does not say stopped: $(cat "$ST/testactions/$id.json")"
  ! kill -0 "$(cat "$STUB/tr-pid")" 2>/dev/null || fail "the test command still runs after the stop"
  trfree || fail "the stopped run still holds the test slot"
}

# Bug this guards (issue 42): a stopped run's record said stopped while a process of it still held its test slot. Its
# processes were looked for once, then ended: a child started after the look (watch()'s timer) was never ended. Here a
# process starts children all the time, each holding the lock it took, as the run's processes hold its slot: once
# taend() returns, the lock is free.
t_taendall() {
  local p f=$T/$CASE/slot
  mkdir -p "$T/$CASE" || fail "the case's folder"
  ( exec 7>>"$f"; flock 7; while :; do sleep 5 & sleep 0.01; done ) & p=$! # sleep: children started all the time, each holding the lock
  wait_until "! flock -n '$f' true" || fail "the process did not take the lock"
  # shellcheck disable=SC2034 # STATE is read by the sourced lib/testaction.sh (TESTACTS=${STATE%/*}/testactions)
  ( STATE=$T/$CASE/cards.jsonl; . "$SRC/lib/testaction.sh" && taend "$p" ) || fail "taend() could not be run"
  flock -n "$f" true || fail "a child started while the processes were looked for still runs, holding the lock"
}
