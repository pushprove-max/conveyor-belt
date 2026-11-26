#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the waits a card notes for its card records (waitnote(), lib/records.sh) as it waits for main, the
# machine, room under the cap, the bug-card proof check and the landing turn at its land step.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bugs: a wait for main (mainwaited(), and mainredhold() while main is red), for the machine (holdwaited()), for room
# under the cap (capowed()) or the landing turn at the land step (landwait()) is not noted, so the card's next line
# has no waits for it. Each wait is a stand-in that sleeps 1 s, all at once.
t_waitnames() {
  local w waits='mainwait() { sleep 1; }; holdwait() { sleep 1; }; redholdwait() { sleep 1; }; caphold() { sleep 1; }' # sleep: each stand-in wait must last 1 s or more, as what is noted is its seconds
  setup '[]'
  # shellcheck disable=SC2016 # expanded by fx_in's eval
  fx_in 'mkdir -p "$CARDS"; c=c9-9 n=9 wt=$CARDS/c9-9 br="" sprompt="" issue="{}" mainsec=0 LIVE=1; echo owed > "$wt.capheld"
    '"$waits"'
    redhere() { printf "abc\ncase\n"; }; giveway() { :; }; unmate() { :; }; redbrief() { :; }; settle() { return 0; }
    # c6-6 has the turn for the first two looks: the one before the wait and the one before its single sleep.
    turnon() { local k; k=$(cat "$CARDS/turnlooks" 2>/dev/null || echo 0); echo $((k + 1)) > "$CARDS/turnlooks"; [ "$k" -lt 2 ] && echo c6-6; }
    landwait c9-9 9 "$wt" &
    mainwaited "$wt" abc case & holdwaited "$wt" & mainredhold & capowed c9-9 9 "$wt" land &
    wait; record c9-9 9 test pass'
  w=$(jq -sc 'map(select(.card == "c9-9" and .step == "test") | .waits)' "$ST/cards.jsonl" 2>&1)
  jq -e 'length == 1 and (.[0] | map(.name) == ["cap", "machine", "main", "turn"] and all(.sec >= 1)
    and (map(select(.name == "main")) | .[0].sec >= 2))' <<<"$w" > /dev/null \
    || fail "waits of 1 s each for main twice, the machine, the cap and the landing turn: the next line's waits are $w: $(cat "$T/$CASE/run.out")"
}
# Bugs: either call of the bug-card proof check in cardbuild() is not timed as the wait proof (bugproofed()), or the
# timing loses the check's exit. The check is a stand-in that takes 1 s and does not hold (exit 1): the card builds
# again, is checked again and is blocked. The first check's seconds go on its second build line, the second's on its
# blocked line.
t_waitproof() {
  local w ISSUE proof='bugproof() { sleep 1; BUGWHY="the new tests pass without the fix"; echo "$BUGWHY" > "$2.unfixed"; return 1; }' # sleep: the check must take 1 s or more, as what is noted is its seconds
  setup '[]'
  # shellcheck disable=SC2034 # ISSUE: read by fx_in's eval
  ISSUE=$(issue 7 2026-01-01 bug)
  echo 'echo two >> a.txt' > "$STUB/build"
  git -C "$R" worktree add -q --detach "$T/$CASE/cards/c7" || fail "the card's worktree could not be made"
  # shellcheck disable=SC2016 # expanded by fx_in's eval
  fx_in "$proof"'
    c=c7 n=7 br="" mode="" wt=$CARDS/c7 issue=$ISSUE sprompt=brief sf="" go=end; cardbuild; echo "go $go"'
  w=$(jq -sc 'map(select(.card == "c7" and (.step | IN("build", "blocked"))) | [.step, ((.waits // []) | map(select(.name == "proof") | .sec) | add // 0)])' "$ST/cards.jsonl" 2>&1)
  jq -e 'map(.[0]) == ["build", "build", "blocked"] and .[0][1] == 0 and .[1][1] >= 1 and .[2][1] >= 1' <<<"$w" > /dev/null \
    || fail "a bug card whose two proof checks of 1 s each do not hold: its build, build and blocked lines with their proof seconds are $w, not 0, 1 or more and 1 or more: $(tail -n 5 "$T/$CASE/run.out")"
}
# Bugs: a card's wait at its claim on a card that changes the same files is not noted as cards, or the turn and the
# cards waits are noted under one name. settle() runs its real wait loop, its claim told to wait twice (the turn, then
# a card), each look LIVE (1 s) apart: which name each look's seconds go to is decided only inside that loop.
t_waitcards() {
  local w
  setup '[]'
  # shellcheck disable=SC2016 # expanded by fx_in's eval
  fx_in 'cd "$R" && mkdir -p "$CARDS" && git worktree add -q --detach "$CARDS/c7-7" "refs/heads/$BRANCH" || exit 9
    LIVE=1 waitsec=0 mainsec=0 parsecheck="" behind="[]" caught=""
    claim() { local k; k=$(cat "$CARDS/looks" 2>/dev/null || echo 0); echo $((k + 1)) > "$CARDS/looks"
      case $k in 0) echo "{\"on\":\"c6-6\",\"paths\":[],\"turn\":true}" ;; 1) echo "{\"on\":\"c6-6\",\"paths\":[\"a.txt\"]}" ;; esac; }
    stackto() { return 1; }; turnfree() { :; }; began() { :; }
    settle c7-7 7 "$CARDS/c7-7" prompt land "{}" > /dev/null; echo "settle: $?"; record c7-7 7 test pass'
  w=$(jq -sc 'map(select(.card == "c7-7" and .step == "test") | .waits)' "$ST/cards.jsonl" 2>&1)
  grep -qx 'settle: 0' "$T/$CASE/run.out" && jq -e 'length == 1 and (.[0] | map(.name) == ["cards", "turn"] and all(.sec >= 1))' <<<"$w" > /dev/null \
    || fail "a card whose claim said wait for the turn of c6-6, then wait on c6-6 for a.txt, then go on: its next line's waits are $w, not cards and turn of 1 s or more: $(cat "$T/$CASE/run.out")"
}
