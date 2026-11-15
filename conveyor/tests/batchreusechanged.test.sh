#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a batch's test run reuses no pass of a card whose change changed since its tests passed (batch(),
# batchkeep()). Its own file, with the fixture of batchreuse.test.sh (reusesetup): each case of the batch's reuse is a
# whole batch run, and together they were over the test step's CPU budget for one file.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# A card whose change changed since its tests passed brings no pass: the batch's run runs every case of its files.
# #8's y.txt changes in its worktree after its own run (as the hold check lets #7 go on): the run runs y.test's two
# cases, and not x.test's, which #7 passed on its unchanged change.
t_batchreusechanged() {
  reusesetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]" 'x.txt x.test' 'y.txt y.test'
  echo 'd=$(echo ../*-8); echo more >> "$d/y.txt"; git -C "$d" add -A' > "$STUB/held-then"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c7=$(cardof 7); c8=$(cardof 8)
  [ "$(runs)" = "8 y1 y2,7 x1 x2,7 y1 y2," ] || fail "the batch's run did not run #8's cases alone: $(runs): $out"
  landedtogether "$c8 $c7" || fail "the two cards did not land as one batch: $(st 'select(.step == "landed")')"
  [ "$(cat "$R/y.txt" | tr '\n' ' ')" = "y more " ] || fail "main does not hold #8's change as it was tested: $(cat "$R/y.txt")"
}
