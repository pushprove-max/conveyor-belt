#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the check of an Optimize card's split (speedproof()): its files' CPU seconds summed against the old
# file's on record and a start-up allowance for each file a split adds. No file is held to a CPU budget (#349).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# speedproof() called as card() calls it, on card c7 of #7, whose change runs <change> in its worktree on main, where
# f.test.sh (`echo slow`) has a median of 10 CPU s on record (whole-suite runs of 9, 10 and 11) and the pack still
# holds the old test.fileBudget of 8, which no file is held to. Each run under cards/mainrun/ times each file its list names `fail` at the CPU seconds
# $STUB/cpu-<file> holds, and names the case one of it as passed; a line that names a case as well (a run with no case
# selected) is timed at $STUB/cpu-probe, with no line when that is empty, and names no case unless $STUB/probe-whole
# exists (PROBEWHOLE set: a runner with no case filter, which runs the file whole). The check's exit is in $RC and the first line of what the review is shown in $WHY.
# The files given after <change> are those the split adds.
splitrun() { # <change> <cpu f.test.sh> <cpu f1.test.sh> <cpu f2.test.sh> <cpu probe> [<added file>...]
  local wt=$T/$CASE/cards/c7 c
  setup '[]'; tune '.test.fileBudget = 8'
  echo slow > "$R/f.test.sh" && git -C "$R" add f.test.sh && git -C "$R" commit -qm 'a slow test' || fail "main's file"
  for c in 9 10 11; do
    jq -cn --argjson c "$c" '{time: "2026-11-01T00:00:00Z", how: "full", sha: "abc", files: {"f.test.sh": {result: "ok", sec: $c, cpu: $c}}}' >> "$ST/suiteruns.jsonl"
  done
  echo "$2" > "$STUB/cpu-f.test.sh"; echo "$3" > "$STUB/cpu-f1.test.sh"; echo "$4" > "$STUB/cpu-f2.test.sh"; echo "$5" > "$STUB/cpu-probe"
  [ -z "${PROBEWHOLE:-}" ] || : > "$STUB/probe-whole"
  cat > "$STUB/mainrun-cmd" <<'EOF'
while IFS=$'\t' read -r k f c; do
  [ "$k" = fail ] || continue
  if [ -n "$c" ]; then
    [ ! -e "$STUB/probe-whole" ] || printf '== %s\nok one\n-- ok %s\n' "$f" "$f"
    x=$(cat "$STUB/cpu-probe"); [ -z "$x" ] || printf 'TESTRUN sec\t%s\t1\t%s\n' "$f" "$x" >> "$CONVEYOR_TEST_LOG/r"; continue
  fi
  printf '== %s\nok one\n-- ok %s\n' "$f" "$f"; printf 'TESTRUN sec\t%s\t1\t%s\n' "$f" "$(cat "$STUB/cpu-$f")" >> "$CONVEYOR_TEST_LOG/r"
done < "$CONVEYOR_TEST_RERUN"
EOF
  git -C "$R" worktree add -q --detach "$wt" && (cd "$wt" && eval "$1") && git -C "$wt" add -A || fail "the card's change could not be staged"
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" || exit 9
    names || exit 9
    speedproof c7 "$wt" '{"number":7}' f.test.sh "${@:6}" ) > "$T/$CASE/run.out" 2>&1; RC=$?
  [ "$RC" != 9 ] || fail "the engine could not be loaded: $(cat "$T/$CASE/run.out")"
  WHY=$(head -n 1 "$wt.unfixed" 2>/dev/null)
}
SPLIT='rm f.test.sh; echo one > f1.test.sh; echo two > f2.test.sh'

# Bug it catches (#158): an honest split is refused because its files, each with its own start-up, take more CPU
# seconds summed than the old file (11 against 10). The sum is within 10 plus the allowance for its two files: the run
# with no case gives no CPU seconds, so the pack's test.splitAllowance (1) counts. The review is shown each file's CPU
# seconds, against no budget.
t_splitfits() {
  splitrun "$SPLIT" '' 4 7 '' f1.test.sh f2.test.sh
  [ "$RC" = 0 ] || fail "a split within the allowance was refused: $WHY"
  grep -qxF 'This change splits the test file f.test.sh, so no test must fail on main'"'"'s code. Run alone with the change, on a test slot, f1.test.sh, f2.test.sh passed in 11 CPU s summed (the median on record of f.test.sh is 10 CPU s): f1.test.sh 4 CPU s, f2.test.sh 7 CPU s.' "$T/$CASE/cards/c7.unfixed" \
    || fail "the review is not shown each file's CPU seconds: $(cat "$T/$CASE/cards/c7.unfixed")"
  [ "$(st 'select(.step == "bugproof") | "\(.result) \(.speed.after)"')" = 'ok 11' ] || fail "the bugproof line: $(st 'select(.step == "bugproof")')"
}

# #349: no test file has a CPU budget. Bug it catches: a split whose sum is fine (10, no more than the old file) is
# refused for one file over the pack's old test.fileBudget of 8 (f1.test.sh at 9 CPU s).
t_splitover() {
  splitrun "$SPLIT" '' 9 1 '' f1.test.sh f2.test.sh
  [ "$RC" = 0 ] || fail "a split was refused for a file over the old budget: exit $RC, $WHY"
}

# Bug it catches: the allowance is guessed, not measured: with the pack's 1 CPU s the sum of 12 would pass (10 + 2 x 1),
# but a run of f1.test.sh with no case took 0.5, so a split may take 11. The reason names the sum, the limit and the
# allowance with where it came from.
t_splitsum() {
  splitrun "$SPLIT" '' 6 6 0.5 f1.test.sh f2.test.sh
  [ "$RC" != 0 ] && [ "$WHY" = 'the split does not fit: the files take 12 CPU s summed, 1 over the 11 CPU s a split of f.test.sh may take: 10 CPU s on record plus a start-up allowance of 0.5 CPU s (measured: a run of f1.test.sh with no case) for each of the 2 files it adds' ] \
    || fail "a split over its measured allowance was not refused, naming the sum and the allowance: exit $RC, $WHY"
}

# Bug it catches: a runner with no case filter runs the whole file for the run with no case selected, and its 6 CPU s
# are taken as start-up, so a split of 13 passes against 10 + 2 x 6. That run named the case one, so the pack's
# test.splitAllowance (1) counts, and the split is refused. The reason says why it was not measured.
t_splitprobewhole() {
  PROBEWHOLE=1 splitrun "$SPLIT" '' 6 7 6 f1.test.sh f2.test.sh
  [ "$RC" != 0 ] && [ "$WHY" = "the split does not fit: the files take 13 CPU s summed, 1 over the 12 CPU s a split of f.test.sh may take: 10 CPU s on record plus a start-up allowance of 1 CPU s (the pack's test.splitAllowance: the run of f1.test.sh with no case ran its case one: the test command runs the file whole) for each of the 2 files it adds" ] \
    || fail "a run with no case selected that ran the file's cases was taken as its start-up: exit $RC, $WHY"
}
