#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a batch run again when main moved during its run reuses its last run's passes (rebatch(), batchkeep()),
# and is run again when what landed meanwhile shares a test file with it (sharedtests()); its run reuses no pass of a
# card whose change changed since its tests passed (batchkeep()).
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

# Bug (#334: two changes that each passed alone failed together on main): a batch whose run passed while main moved
# landed on that run, though what landed meanwhile touched a test file of the batch's change. #7 changes lib/mine.sh;
# during the batch's run main changes lib/other.sh, and lib/mine-other.test.sh tests both (sharedtests()): the batch
# is tested again on main as it is now, not landed on the run before; and that run keeps none of the passes of the run
# before (a batch formed again of the same cards would else reuse them, batchkeep(), and run no case): its case m1 runs
# again after main moved.
t_batchsharedmoved() {
  local -x FILEMODE=1
  reusesetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]" 'x.txt x.test' 'y.txt y.test' \
    'lib/mine.sh lib/mine-other.test.sh' 'lib/other.sh lib/mine-other.test.sh' 'lib/mine-other.test.sh lib/mine-other.test.sh'
  echo 'lib/mine-other.test.sh m1' >> "$STUB/cases"
  mkdir -p "$R/lib"; echo mine > "$R/lib/mine.sh"; echo other > "$R/lib/other.sh"; echo case1 > "$R/lib/mine-other.test.sh"
  git -C "$R" add lib; git -C "$R" commit -qm "two sources and their shared test"
  echo 'case $PWD in *-7) echo seven >> lib/mine.sh ;; esac' >> "$STUB/build"
  # #8 changes after its own run, so the batch's run runs its cases (a run of none would not start the test command),
  # and only those: checked below.
  echo 'd=$(echo ../*-8); echo more >> "$d/y.txt"; git -C "$d" add -A' > "$STUB/held-then"
  echo 'grep -qx seven a.txt && grep -qx eight a.txt && [ ! -e "$STUB/moved" ] && { : > "$STUB/moved"; echo moved >> "$STUB/runs"; (cd "$R" && echo main >> lib/other.sh && git commit -qam "main changes the other source"); }; :' >> "$STUB/test-cmd"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  c7=$(cardof 7); c8=$(cardof 8)
  grep -q "card $c7: cards landed during its batch's run touch its test files too, so the batch is tested again: lib/mine-other.test.sh on main as it is now" <<<"$out" \
    || fail "the batch landed on its run though main's change shares a test file with it: $out"
  # A card whose change changed since its tests passed brings no pass (batchkeep()): the batch's first run (the line
  # before `moved`) runs y.test's two cases, as #8's y.txt changed after its own run, and not x.test's or m1, which #7
  # passed on its unchanged change.
  [ "$(grep -B1 -x moved "$STUB/runs" | head -n 1)" = "7 y1 y2" ] \
    || fail "the batch's first run did not run #8's changed cases alone: $(runs)"
  sed -n '/^moved$/,$p' "$STUB/runs" | grep -q ' m1\b' || fail "the shared test's case m1 did not run again after main moved: $(runs)"
  landedtogether "$c8 $c7" && [ "$(tail -n 1 "$R/lib/other.sh")" = main ] \
    && [ "$(tail -n 1 "$R/lib/mine.sh")" = seven ] || fail "both cards did not land as one batch on main as it moved: $(st 'select(.step == "landed")')"
  [ "$(cat "$R/y.txt" | tr '\n' ' ')" = "y more " ] || fail "main does not hold #8's change as it was tested: $(cat "$R/y.txt")"
}
