#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the land turn of one card through the real loop: it is checked again on main as main moved under it.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# The cases below run one card through the real loop (loop run): what they protect is card()'s order of calls on its
# land step (fit the card onto main as it is now, claim its files again, run its checks again, block or land), and only
# card() makes those calls; a direct call of settle(), checks() or land() passes with card() skipping one. One card
# only, with the stub sessions, so no case waits on a second card.
# #7 (issue 7, every review GO) changes a.txt's last line to seven; its check $STUB/both-check.sh is <check>. With
# $STUB/broken-build, its build also leaves a file `broken` that fails its tests until its test-fix session removes it.
gwone() { # <check>
  setup "[$(issue 7 2026-01-01)]"; for i in 1 2 3 4 5; do echo "$GO" > "$STUB/review.$i"; done
  seq 20 > "$R/a.txt"; git -C "$R" commit -qam "a longer a.txt"
  printf '%s\n' "$1" > "$STUB/both-check.sh"; tune --arg a "$STUB/both-check.sh" '.checks = [$a]'
  echo 'if grep -q "^# The changed tests fail" "$STUB/brief"; then rm -f broken; else sed -i 20s/.*/seven/ a.txt; [ ! -e "$STUB/broken-build" ] || : > broken; fi' > "$STUB/build"
  echo '[ ! -e broken ] || { echo "FAIL broken.test"; exit 1; }' >> "$STUB/test-cmd"
}
# Nothing of #7 landed: it is blocked by its check, which printed <failure>, and main does not have its line.
gwblocked() { # <failure> <what moved main>
  [ "$(st 'select(.issue == 7 and .step == "blocked") | .reason')" = "a product check failed; nothing landed." ] \
    && st 'select(.issue == 7 and .step == "blocked") | .tail' | grep -q "$1" \
    || fail "#7, fitted onto main after $2, was not checked again there: $(st '"\(.issue) \(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  [ -z "$(st 'select(.step == "landed") | .issue')" ] && ! grep -qx seven "$R/a.txt" || fail "#7 landed a combination its checks never passed ($2): $(cat "$R/a.txt")"
}
# Bug: a card that gave way ran its checks and tests on a main without the card that landed meanwhile; fitted onto
# that card's main, it landed with no second run, a combination that never passed them. #7's tests fail and it gives
# way for their fix; during its tests after the fix (its third run, holding nothing), #8's change to the first line
# lands. A check forbids it beside #7's last line.
t_givewaycheck() {
  gwone '! { [ "$(head -n 1 a.txt)" = eight ] && [ "$(tail -n 1 a.txt)" = seven ]; } || { echo "eight and seven together"; exit 1; }'
  : > "$STUB/broken-build"
  { echo 'case $PWD in *-7) n=$(($(cat "$STUB/runs7" 2>/dev/null || echo 0) + 1)); echo $n > "$STUB/runs7"'
    echo '  [ $n != 3 ] || { cp "$PWD.claim" "$STUB/awayclaim"; sed -i 1s/.*/eight/ "$R/a.txt"; git -C "$R" commit -qam "card 8"; } ;; esac'; cat "$STUB/test-cmd"; } > "$STUB/test-cmd.new" \
    && mv "$STUB/test-cmd.new" "$STUB/test-cmd"
  loop run >/dev/null 2>&1
  [ "$(jq -c '[.held, .away]' "$STUB/awayclaim" 2>/dev/null)" = '[false,true]' ] || fail "#7 had not given way when main moved: $(cat "$STUB/awayclaim" 2>/dev/null)"
  gwblocked 'eight and seven together' "#8 landed while #7 was away"
}
# A card that never gave way: main gets b.txt (a file #7 does not hold, so no card waits) at the moment $STUB/bmove
# names: during #7's tests (test) or between its tests and its landing (land, at the limit reading land asks for). A
# check forbids b.txt beside #7's line: it passes on the main #7's tests ran on, runs again on main with b.txt, and
# blocks #7 there.
heldmove() { # <test|land>
  gwone '! { [ -e b.txt ] && [ "$(tail -n 1 a.txt)" = seven ]; } || { echo "b.txt and seven together"; exit 1; }'
  echo "$1" > "$STUB/bmove"
  printf '%s\n' 'echo flag > "$R/b.txt" && git -C "$R" add b.txt && git -C "$R" commit -qm "main adds b.txt" && rm -f "$STUB/bmove"' > "$STUB/addb"
  echo '[ "$(cat "$STUB/bmove" 2>/dev/null)" != test ] || . "$STUB/addb"; : > "$STUB/tested"' >> "$STUB/test-cmd"
  CONVEYOR_LIMIT_CMD='[ ! -e "$STUB/tested" ] || [ "$(cat "$STUB/bmove" 2>/dev/null)" != land ] || . "$STUB/addb"' loop run >/dev/null 2>&1
  [ ! -e "$STUB/bmove" ] || fail "main never got b.txt ($1): $(st '"\(.issue) \(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  gwblocked 'b.txt and seven together' "main moved ($1)"
}
# Bug: main moved during the tests of a card that held its files throughout, and it landed onto that unchecked.
t_heldtestmove() { heldmove test; }
# Bug: main moved after a card's last checks and tests, before it took the landing lock, and it landed onto that.
t_heldlandmove() { heldmove land; }

# Issue 428, through the real loop as gwone() says why (card()'s calls on its main-moved path): #7's first tests fail
# and main moves (b.txt) during them, so #7 is fitted onto main (settle()) and what failed runs again there before any
# fix round; that run's claim is kept ($STUB/fitclaim). Main's pre-commit hook, which land() runs just before it lands,
# keeps the claim #7 lands on ($STUB/landclaim). Every run of #7 on the moved main <passes|fails>; one that fails is
# fixed, and #7 lands.
gwmoved() { # <passes|fails>
  local out
  gwone :; [ "$1" = passes ] || : > "$STUB/broken-build"
  { echo 'case $PWD in *-7) if [ ! -e b.txt ]; then [ -e "$R/b.txt" ] || { echo b > "$R/b.txt"; git -C "$R" add b.txt; git -C "$R" commit -qnm "main moves"; }'
    echo '  echo "FAIL broken.test"; exit 1; fi; [ -e "$STUB/fitclaim" ] || cp "$PWD.claim" "$STUB/fitclaim" ;; esac'; cat "$STUB/test-cmd"; } > "$STUB/test-cmd.new" \
    && mv "$STUB/test-cmd.new" "$STUB/test-cmd"
  printf '#!/bin/sh\nfor c in "%s"/*-7.claim; do [ ! -e "$c" ] || cp "$c" "%s/landclaim"; done\n' "$T/$CASE/cards" "$STUB" > "$R/.git/hooks/pre-commit"
  chmod +x "$R/.git/hooks/pre-commit"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  grep -q "main moved since its commit" <<<"$out" || fail "#7 did not take the main-moved path: $(st '"\(.issue) \(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  [ "$(st 'select(.step == "landed") | .issue')" = 7 ] && [ "$(tail -n 1 "$R/a.txt")" = seven ] && [ -e "$R/b.txt" ] \
    || fail "#7 did not land on the moved main ($1 there): $(st '"\(.issue) \(.step) \(.result) \(.reason)"' | tr '\n' ,)"
}
# Bug it catches: #7 kept its claim through its run on the moved main, so #8, stacked on it, waited until the run ended.
# card() gives way for that run as for a fix round (fixing), and claim() lets a stacked card past such a claim
# (t_givewayfix). Here that run fails, and goes to the fix round.
t_givewaymoved() {
  gwmoved fails
  [ "$(jq -c '[.held, .away, .fixing]' "$STUB/fitclaim" 2>/dev/null)" = '[false,true,true]' ] \
    || fail "#7 held its claim through its tests on the moved main: $(cat "$STUB/fitclaim" 2>/dev/null)"
}
# Bug it catches: #7, given way for its run on the moved main, which passes, landed on that claim (held false), as
# nothing claimed its files again: the land step's claim again (settle()) holds a.txt when land() commits.
t_givewaymovedpass() {
  gwmoved passes
  [ "$(jq -c '[.held, .away]' "$STUB/fitclaim" 2>/dev/null)" = '[false,true]' ] || fail "#7 had not given way for its run on the moved main: $(cat "$STUB/fitclaim" 2>/dev/null)"
  [ "$(jq -c .held "$STUB/landclaim" 2>/dev/null)" = true ] || fail "#7 landed without claiming its files again: $(cat "$STUB/landclaim" 2>/dev/null)"
}
