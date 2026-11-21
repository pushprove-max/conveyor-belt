#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the list a batch's test run is given (batchlist()) names a file whose cases cannot run apart as one
# `pass` line. t_batchreusewhole calls batchlist() itself: what it proves is the list, not a whole batch run.
# t_batchreuseshared is a whole batch run (the fixture of batchreuse.test.sh, reusesetup): what the batch's run runs
# and keeps, and that both cards land as one batch.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# A file whose cases cannot run apart (x.test) honours only a `pass` line. #7
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
  [ "$list" = "pass x.test,pass y.test,ok z.test z1," ] || fail "the batch's list is not pass x.test, pass y.test and z.test's kept case z1 alone (it names x.test or y.test by case, names s.test or z2, or leaves one out): $list"
}

# A file whose cases cannot run apart (x.test, named in $STUB/whole) honours only
# a `pass` line. #7 passed x.test whole, its log naming each case (`ok x1`, `ok x2`), and no other card selects it:
# the batch's list says x.test passed, so the run runs s.test's shared case alone, which both cards select (a.txt,
# which both change, selects it), not y.test's, which #8 passed alone; #7's test line says one case ran and four were
# kept. Bugs it catches: the list named x.test's cases as `ok` lines alone, and the run ran x.test whole again; the
# batch's run ran a case a card passed alone again, or skipped the case both cards select; the test line counted only
# the kept cases the runner's log names, so x.test's two, kept whole and not run, were left out.
t_batchreuseshared() {
  reusesetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]" 'a.txt s.test' 'x.txt x.test' 'y.txt y.test'
  echo x.test > "$STUB/whole"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c7=$(cardof 7); c8=$(cardof 8)
  [ "$(runs)" = "8 s1 y1 y2,7 s1 x1 x2,7 s1," ] || fail "the batch's run did not run s1 alone (it ran again x.test, which #7 passed whole, or y.test, which #8 passed, or skipped s1, which both cards select): $(runs)"
  landedtogether "$c8 $c7" || fail "the two cards did not land as one batch: $(st 'select(.step == "landed")')"
  [ "$(st 'select(.issue == 7 and .step == "test") | [.result, .selected.cases, .selected.kept] | tojson' | tail -n 1)" = '["pass",1,4]' ] \
    || fail "#7's last test line does not say one case ran and four passes were kept (x.test's two, kept whole, and y.test's two): $(st 'select(.issue == 7 and .step == "test")')"
}
