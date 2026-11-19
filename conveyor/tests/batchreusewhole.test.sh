#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# Engine cases: the list a batch's test run is given (batchlist()) names a file whose cases cannot run apart as one
# `pass` line. The case calls batchlist() itself: what it proves is the list, not a whole batch run (the fixture of
# batchreuse.test.sh, reusesetup, paid 14 CPU s for the same answer).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# A file whose cases cannot run apart (x.test, as the engine's own closure.test.sh) honours only a `pass` line. #7
# passed x.test, its log naming each case (`ok x1`, `ok x2`, so its units are x.test's two cases), and no other card
# selects it: batchkeep() keeps both, and s.test's s1, which #8 passed too, it does not keep. The batch's list says
# x.test (and #8's y.test) passed, as `pass` lines, and names nothing of s.test, so the run runs s.test's shared case
# alone. z.test, of which one case is kept and one is not, keeps its `ok` line. Bug it catches: the list named x.test's
# cases as `ok` lines alone, and the run ran x.test whole again.
t_batchreusewhole() {
  local wt=$T/$CASE/wt keep list
  git init -q "$wt" && echo a > "$wt/a.txt" && git -C "$wt" add a.txt && git -C "$wt" commit -qm init \
    && echo b >> "$wt/a.txt" && git -C "$wt" add a.txt || fail "the worktree could not be made"
  # batchkeep()'s answer for that batch: every unit of the cards' passes, and those it keeps.
  keep=$(jq -cn '{keep: ["x.test\tx1", "x.test\tx2", "y.test\ty1", "y.test\ty2", "z.test\tz1"], changed: [],
    units: ["s.test\ts1", "x.test\tx1", "x.test\tx2", "y.test\ty1", "y.test\ty2", "z.test\tz1", "z.test\tz2"], kept: 5, all: false}')
  ( eval "$(sed -n '/^batchlist() {/,/^}/p' "$SRC/lib/claim.sh")"; batchlist "$wt" "$keep" ) || fail "batchlist failed"
  list=$(grep -Ev $'^(change|base|tree)\t' "$wt.rerun" | tr '\t\n' ' ,')
  [ "$list" = "pass x.test,pass y.test,ok z.test z1," ] || fail "the batch's list does not pass x.test whole, or names s.test: $list"
}
