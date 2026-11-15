#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: land-branch, failing changed tests.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Split from branch.test.sh, whose setup (branchsetup) and bugs these cases share, so no one file is over the
# CPU budget (test.fileBudget): its six cases cost about 17 CPU s together.
t_branchtests() {
  branchsetup
  # A failing changed test blocks the landing: one fix round, one more review, a second failure, blocked. Nothing lands.
  # Each failed run is run once more before it counts as failed (tests()): four runs, two test steps.
  lane fast-two e.txt eee; at=$(git -C "$R" rev-parse main); echo "$GO" | tee "$STUB/review.1" > "$STUB/review.2"
  echo 'echo x >> "$STUB/tests"; echo "FAIL widget.test.ts"; exit 1' > "$STUB/test-cmd"
  out=$(loop land-branch fast-two) && fail "a branch whose changed tests fail exited zero: $out"
  c=$(newest); count "1 2 4"
  [ "$(steps "$c")" = "picked worktree deps brief start review start test start fix start review start test blocked " ] && [ "$(git -C "$R" rev-parse main)" = "$at" ] && [ ! -e "$R/e.txt" ] \
    || fail "a failing changed test did not block the landing: $(steps "$c")"
  st "select(.card == \"$c\" and .step == \"blocked\") | .tail" | grep -q 'FAIL widget.test.ts' && grep -q "branch fast-two: blocked" <<<"$out" || fail "the blocked line or the report lacks the reason: $out"
  [ ! -e "$STUB/comments" ] || fail "a card of no issue posted a comment on an issue: $(cat "$STUB/comments")"
}
