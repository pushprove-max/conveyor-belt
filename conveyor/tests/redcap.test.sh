#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a main-red fix card takes one slot beyond the project's cap (run(): redfix()).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Issue 612. Bug it catches: a main-red fix card was picked only below the cap, so with every slot held by cards that
# wait for main to go green it never started, and nothing moved. Cap 1, #1 on the belt (its build holds until let go),
# #5 queued: one card holds every slot as well as two would (the cap is reached either way), without a second card's
# run. Two red main commits wait for their fix cards (issue 0, #597; the main-red record names them): at the next turn
# the first one's card starts in one slot beyond the cap, its picked line saying so for the Board, and no queued issue
# starts (D1); while it runs, the second commit's card waits as the others do (D2). The first lands;
# the second takes the slot beyond the cap in turn and fails its build at once; then #5 still waits (D3), and starts
# only once #1 ends: no slot beyond the cap is left over for it.
t_redcap() {
  local lp t red='select(.step == "picked") | if .mainRed then "red\(.mainRed[0:1])" else .issue end'
  setup "$(jq -cs . <(issue 1 2026-01-01 P1) <(issue 5 2026-01-05 P1))"
  echo "$GO" > "$STUB/review.1"; mkdir -p "$T/$CASE/cards"; loop control cap 1 >/dev/null || fail "cap 1 was refused"
  tune '.tunables.poll = 1'; watchturns
  # A fix card (its worktree ends -0) is labelled as a P0 bug: the first (its card id in building.0) proves its fix as
  # provenbug does, in each of its sessions; the second fails its build at once. Any other build holds until let go
  # (go<n>), then fails.
  echo 'bash a.test.sh' > "$STUB/mainrun-cmd"
  echo 'n=${PWD##*-}; if [ "$n" = 0 ] && [ -e "$STUB/building.0" ] && [ "$(cat "$STUB/building.0")" != "${PWD##*/}" ]; then : > "$STUB/building.0b"; exit 1; fi
[ "$n" != 0 ] || [ -e "$STUB/building.0" ] || echo "${PWD##*/}" > "$STUB/building.0"; : >> "$STUB/building.$n"
while [ -d "$STUB" ] && [ ! -e "$STUB/go$n" ]; do sleep 0.1; done; [ "$n" = 0 ] || exit 1
echo two >> a.txt; echo "[ \$(wc -l < a.txt) -ge '"$(($(wc -l < "$R/a.txt") + 1))"' ]" > a.test.sh' > "$STUB/build"
  ( loop run > "$STUB/run.out" 2>&1 ) & lp=$!
  wait_until '[ -e "$STUB/building.1" ]' 'cat "$STUB/run.out"' || fail "#1 did not start: $(cat "$STUB/run.out")"
  jq -cn '{reds: [{sha: "1111111111111111111111111111111111111111", cases: [{case: "a.test: one", file: "a.test", by: "c1", files: [], last: ""}], card: null},
    {sha: "2222222222222222222222222222222222222222", cases: [{case: "b.test: two", file: "b.test", by: "c2", files: [], last: ""}], card: null}]}' > "$ST/mainred.json"
  t=$(grep -cxF "$R" "$TURNS")
  # The next turn: the first that reads the record. A turn counts as it starts its sleep: one already past its read
  # when the record was written, and the one after the pick, which may start before the pick is seen here, count too.
  wait_until "jq -e 'select(.step == \"picked\" and .mainRed)' \"\$ST/cards.jsonl\" >/dev/null" 'cat "$STUB/run.out"' \
    || fail "D1: the main-red fix card did not start with the cap reached: $(cat "$STUB/run.out")"
  [ $(($(grep -cxF "$R" "$TURNS") - t)) -le 2 ] || fail "D1: the main-red fix card started $(($(grep -cxF "$R" "$TURNS") - t)) turns after its commit was recorded, not at the next turn"
  wait_until '[ -e "$STUB/building.0" ]' 'cat "$STUB/run.out"' || fail "D1: the main-red fix card did not build: $(cat "$STUB/run.out")"
  turns 2 # each would have picked the second fix card or #5 had it taken a slot
  [ "$(st "$red" | tr '\n' ' ')" = "1 red1 " ] \
    || fail "D1, D2: beside the fix card in the slot beyond the cap, another card started: $(st "$red" | tr '\n' ' ')"
  [ "$(st 'select(.step == "picked") | .beyond' | tr '\n' ' ')" = "null main is red " ] \
    || fail "the fix card's picked line does not say it took a slot beyond the cap: $(st 'select(.step == "picked") | .beyond' | tr '\n' ' ')"
  [ "$(loop snapshot | jq -c '[.belt[] | [.issue, .beyond]]')" = '[[1,null],[0,"main is red"]]' ] \
    || fail "the snapshot's belt does not carry the slot beyond the cap: $(loop snapshot | jq -c '[.belt[] | [.issue, .beyond]]')"
  : > "$STUB/go0"
  wait_until "[ \"\$(st 'select(.step == \"landed\" or .step == \"blocked\") | \"\\(.card[-1:]) \\(.step)\"' | tr '\n' ,)\" = '0 landed,0 blocked,' ]" 'cat "$STUB/run.out"' \
    || fail "the first fix card did not land, then the second take the slot beyond the cap and block: $(st '"\(.card) \(.step) \(.reason)"' | tr '\n' ,)"
  [ -e "$STUB/building.0b" ] || fail "the second fix card did not build: $(st '"\(.card) \(.step) \(.reason)"' | tr '\n' ,)"
  [ "$(st "$red" | tr '\n' ' ')" = "1 red1 red2 " ] && [ "$(st 'select(.step == "picked") | .beyond' | tail -n 1)" = "main is red" ] \
    || fail "the second fix card did not take the slot beyond the cap: $(st "$red" | tr '\n' ' ')"
  turns 2
  [ -z "$(st 'select(.issue == 5 and .step == "picked") | .card')" ] || fail "D3: #5 started after the fix landed, with the capped card still on the belt"
  : > "$STUB/go1"
  wait_until '[ -e "$STUB/building.5" ]' 'cat "$STUB/run.out"' || fail "D3: #5 did not start once #1 ended: $(cat "$STUB/run.out")"
  [ "$(st 'select(.step == "picked" or (.step == "blocked" and .issue == 1)) | "\(.issue) \(.step)"' | tail -n 2 | tr '\n' ,)" = "1 blocked,5 picked," ] \
    || fail "D3: #5 was not picked after #1 ended: $(st '"\(.issue) \(.step)"' | tr '\n' ,)"
  [ "$(st 'select(.issue == 5 and .step == "picked") | .beyond')" = null ] || fail "#5 was marked as taking a slot beyond the cap"
  : > "$STUB/go5"
  wait "$lp" || fail "run exited non-zero: $(cat "$STUB/run.out")"
  loop check || fail "the record check refuses a picked line with its slot beyond the cap"
}
