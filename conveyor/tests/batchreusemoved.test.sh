#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a batch run again when main moved during its run reuses its last run's passes (rebatch(), batchkeep()).
# Its own file, with the fixture of batchreuse.test.sh (reusesetup): each case of the batch's reuse is a whole batch
# run, and together they were over the test step's CPU budget for one file.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# The batch is formed again when main moved during its run (rebatch()): a product check fails, once, on its change on
# main as it moved, a red run, so it is run again there. s1, which both cards select, passed in the batch's last run
# with both in it, on their changes unchanged since, and every other case on its own card's change: the run again
# runs no case. Bug it catches: a batch run again ran the cases its last run had passed for the same cards.
t_batchreusemoved() {
  reusesetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]" 'b.txt s.test' 'x.txt x.test' 'y.txt y.test'
  echo 'grep -qx seven a.txt && grep -qx eight a.txt && [ ! -e "$STUB/moved" ] && { : > "$STUB/moved"; (cd "$R" && echo other > other.txt && git add other.txt && git commit -qm "another file"); }; :' >> "$STUB/test-cmd"
  printf '%s\n' '! git cat-file -e "$2:other.txt" 2>/dev/null || ! git show "$2:a.txt" | grep -qx eight || [ -e "$STUB/flaked" ] || { : > "$STUB/flaked"; echo "fails once"; exit 1; }' > "$STUB/once"
  tune --arg f "$STUB/once" '.checks += [$f]'
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c7=$(cardof 7); c8=$(cardof 8)
  grep -q "card $c7: a product check failed on its batch's change on main as it is now, a red run, so the batch is run again there: .*fails once" <<<"$out" \
    || fail "the batch was not run again on main as it moved: $out"
  [ "$(runs)" = "8 s1 y1 y2,7 s1 x1 x2,7 s1," ] || fail "the batch run again ran a case: $(runs): $out"
  # s1, which both cards' own passes and the batch's last run hold, counts once: five cases kept, not six. And x.test
  # and y.test, which the last run passed whole and each card's own pass names case by case, count once: not nine.
  grep -q "card $c7: its batch of 2 runs no case, each having passed on its cards' changes (5 kept)" <<<"$out" || fail "the batch run again did not say it runs no case, five kept: $out"
  [ "$(st 'select(.issue == 7 and .step == "test") | [.result, .selected.cases, .selected.kept] | tojson' | tail -n 1)" = '["pass",0,5]' ] \
    || fail "#7's last test line does not say no case ran and five passes were kept: $(st 'select(.issue == 7 and .step == "test")')"
  landedtogether "$c8 $c7" || fail "the two cards did not land as one batch: $(st 'select(.step == "landed")')"
  [ "$(cat "$R/other.txt")" = other ] && [ "$(sed -n '1p;$p' "$R/b.txt" | tr '\n' ' ')" = "seven eight " ] || fail "main does not hold both changes and the other file"
}
