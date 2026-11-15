#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a batch's test run reuses the pass of a test file whose cases cannot run apart (batch(), batchkeep()).
# Its own file, with the fixture of batchreuse.test.sh (reusesetup): each case of the batch's reuse is a whole batch
# run, and together they were over the test step's CPU budget for one file.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# A file whose cases cannot run apart (x.test, named in $STUB/whole, as the engine's own closure.test.sh) honours only
# a `pass` line. #7 passed x.test whole, its log naming each case (`ok x1`, `ok x2`), and no other card selects it:
# the batch's list says x.test passed, so the run runs s.test's shared case alone. Bug it catches: the list named
# x.test's cases as `ok` lines alone, and the run ran x.test whole again.
t_batchreusewhole() {
  reusesetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]" 'a.txt s.test' 'x.txt x.test' 'y.txt y.test'
  echo x.test > "$STUB/whole"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c7=$(cardof 7); c8=$(cardof 8)
  [ "$(runs)" = "8 s1 y1 y2,7 s1 x1 x2,7 s1," ] || fail "the batch's run ran x.test again, which #7 passed whole: $(runs)"
  landedtogether "$c8 $c7" || fail "the two cards did not land as one batch: $(st 'select(.step == "landed")')"
}
