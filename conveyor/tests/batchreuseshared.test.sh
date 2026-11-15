#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a batch's test run reuses the tests each card of it passed (batch(), batchkeep()), on a case both cards
# select. Its own file, with the fixture of batchreuse.test.sh (reusesetup): each case of the batch's reuse is a whole
# batch run, and together they were over the test step's CPU budget for one file.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Both cards select s.test (a.txt, which both change, selects it): the batch's run runs its case alone, not x.test's
# or y.test's, which each card passed alone; its log and #7's test line say one case ran and four were kept.
t_batchreuseshared() {
  reusesetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]" 'a.txt s.test' 'x.txt x.test' 'y.txt y.test'
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c7=$(cardof 7); c8=$(cardof 8)
  [ "$(runs)" = "8 s1 y1 y2,7 s1 x1 x2,7 s1," ] || fail "the batch's run did not run s.test's case alone: $(runs)"
  landedtogether "$c8 $c7" || fail "the two cards did not land as one batch: $(st 'select(.step == "landed")')"
  [ "$(st 'select(.issue == 7 and .step == "test") | [.result, .selected.cases, .selected.kept] | tojson' | tail -n 1)" = '["pass",1,4]' ] \
    || fail "#7's last test line does not say one case ran and four passes were kept: $(st 'select(.issue == 7 and .step == "test")')"
}
