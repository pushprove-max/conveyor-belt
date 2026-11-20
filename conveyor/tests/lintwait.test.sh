#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 240
# Engine cases: the lint gate for a waiting card (lintwait(), conveyor/lib/lint.sh), called by settle() in
# conveyor/lib/claim.sh before the checks and tests a ready card runs while it waits, with batches on.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# The case's main with batches on (landBatch 2), <run> as the pack's one lint command on *.txt files ($L in it the
# stub linter $STUB/lint: it notes each run in $STUB/lint-args and prints `<file>:<n>: E1 a bad word` for each line
# holding BAD, exit 1 then), a product check and the test command that note each run in $STUB/checked and
# $STUB/tested. Cards c7-7 and c8-8 have worktrees on main: #7 adds a line to a.txt, #8 the line <line>; #8 is ready
# after its GO (<worktree>.ready, its tests not yet run). In the engine shell (fx_in) #7 claims a.txt, so #8 waits on
# it in settle(), at its landing step, as card() calls it. Each look of the wait sleeps: here sleep() counts the looks
# and the third ends the call (exit 8), with #7 still holding a.txt (a card that is not ready: a tested #8 goes past
# it, claim(), and settle() returns 0).
lwsettle() { # <line> <run>
  setup '[]'
  printf '%s\n' 'echo "run $*" >> "$STUB/lint-args"; r=0' \
    'for f; do n=0; while IFS= read -r l; do n=$((n + 1)); [[ $l != *BAD* ]] || { echo "$f:$n: E1 a bad word"; r=1; }; done < "$f"; done; exit $r' \
    > "$STUB/lint" || fail "the stub linter"
  echo 'echo check >> "$STUB/checked"' > "$STUB/check"; echo 'echo test >> "$STUB/tested"' >> "$STUB/test-cmd"
  tune --arg l "bash $STUB/lint" --arg r "$2" --arg c "$STUB/check" '.landBatch = 2 | .checks += [$c] | .lint = {commands: [{files: ["*.txt"], run: ($r | gsub("\\$L"; $l))}]}'
  CARDS=$T/$CASE/cards; mkdir -p "$CARDS"
  for n in 7 8; do
    git -C "$R" worktree add -q --detach "$CARDS/c$n-$n" main || fail "the worktree of card $n"
    landed "$n" | jq -c --arg c "c$n-$n" '.card = $c | .step = "picked"' >> "$ST/cards.jsonl"
  done
  echo seven >> "$CARDS/c7-7/a.txt"; echo "$1" >> "$CARDS/c8-8/a.txt"
  git -C "$CARDS/c7-7" add -A && git -C "$CARDS/c8-8" add -A || fail "the cards' changes"
  echo '{"issue":8,"msg":"title 8 (#8)","extra":{"waitSec":0}}' > "$CARDS/c8-8.ready"
  local looks='sleep() { [ "${FUNCNAME[1]}" = settle ] || { command sleep "$@"; return; }; LOOKS=$((LOOKS + 1)); [ $LOOKS -lt 3 ] || exit 8; }' # sleep: a stand-in that counts the looks of settle() and runs no wait
  fx_in 'cd "$R" || exit 9; caught="" waitsec=0 behind="[]" parsecheck="" LOOKS=0
    [ -z "$(locked claim c7-7 "$CARDS/c7-7" $$)" ] || { echo "#7 did not hold a.txt"; exit 9; }
    '"$looks"'
    settle c8-8 8 "$CARDS/c8-8" "Build the issue." land "$(issue 8 2026-01-01)"; echo "settle: $?"'
  grep -qx 'conveyor: card c8-8 waits on card c7-7, which changes the same files: a.txt' "$T/$CASE/run.out" \
    || fail "#8 did not wait on #7: exit $RC: $(cat "$T/$CASE/run.out")"
}

# Bug: a waiting card whose lint finds a finding runs its checks and tests, is marked tested and so is taken into a
# batch, or runs its lint again at each look of the wait. Its lint runs once, with a findings line; no check, test or
# session runs; and its <worktree>.ready is gone, so gather() takes it into no batch: its landing gate gives it its fix.
t_lintwaitfind() {
  lwsettle 'eight BAD' '$L {files}'
  [ "$RC" = 8 ] || fail "#8 did not wait on through three looks: exit $RC: $(cat "$T/$CASE/run.out")"
  [ "$(wc -l < "$STUB/lint-args")" = 1 ] || fail "the lint of the waiting card did not run once: $(cat "$STUB/lint-args" 2>&1)"
  [ ! -e "$STUB/checked" ] && [ ! -e "$STUB/tested" ] && [ ! -e "$STUB/brief" ] \
    || fail "a check, test or session ran for the waiting card with a lint finding: $(cat "$STUB/checked" "$STUB/tested" 2>&1)"
  [ ! -e "$CARDS/c8-8.ready" ] || fail "the waiting card with a lint finding is still ready, so a batch can take it: $(cat "$CARDS/c8-8.ready")"
  [ "$(st 'select(.issue == 8 and .step == "lint") | .result')" = findings ] || fail "no findings lint line: $(st 'select(.issue == 8) | .step')"
  # Bug: the lint line stays the card's last, so the Board and `health` no longer see its wait or its time limit.
  [ "$(st 'select(.issue == 8) | "\(.step):\(.of // "")"' | tail -n 1)" = start:land ] \
    || fail "the wait's start line is not the card's last after its lint line: $(st 'select(.issue == 8) | .step')"
  grep -qx 'conveyor: card c8-8: its lint found findings while it waits: it runs no check or test, and its landing gate deals with it at its turn' "$T/$CASE/run.out" \
    || fail "settle() did not say why the card runs no test: $(cat "$T/$CASE/run.out")"
}

# Bug: a lint command that ends in an execution error while the card waits is taken as a pass, so its tests run and
# it is marked tested. As with a finding, it runs no check or test and is no longer ready; its landing gate blocks it.
t_lintwaiterror() {
  lwsettle eight 'echo "lint: config broken"; exit 2'
  [ "$RC" = 8 ] || fail "#8 did not wait on through three looks: exit $RC: $(cat "$T/$CASE/run.out")"
  [ ! -e "$STUB/checked" ] && [ ! -e "$STUB/tested" ] && [ ! -e "$CARDS/c8-8.ready" ] \
    || fail "the waiting card with a lint execution error ran its checks or tests, or is still ready: $(cat "$STUB/checked" "$STUB/tested" "$CARDS/c8-8.ready" 2>&1)"
  [ "$(st 'select(.issue == 8 and .step == "lint") | .result' | paste -sd,)" = error ] || fail "not one error lint line: $(st 'select(.issue == 8) | .step')"
}

# Bug: a lint tool that is not installed stops a waiting card's own checks and tests. They run while it waits, as
# before, and it is marked tested (a batch may take it), its lint line saying the command was skipped.
t_lintwaitskip() {
  lwsettle eight 'echo "lint: missing shellcheck"; exit 127'
  [ "$(tail -n 1 "$T/$CASE/run.out")" = 'settle: 0' ] || fail "#8, tested, did not go past #7: exit $RC: $(cat "$T/$CASE/run.out")"
  [ -s "$STUB/checked" ] && [ -s "$STUB/tested" ] && jq -e '.tested == true' "$CARDS/c8-8.ready" > /dev/null \
    || fail "the waiting card with a missing lint tool did not run its checks and tests: $(cat "$CARDS/c8-8.ready" 2>&1); $(cat "$T/$CASE/run.out")"
  [ "$(st 'select(.issue == 8 and .step == "lint") | .lint.commands[0].result')" = 'skipped: missing shellcheck' ] \
    || fail "no skipped lint line: $(st 'select(.issue == 8 and .step == "lint")')"
}
