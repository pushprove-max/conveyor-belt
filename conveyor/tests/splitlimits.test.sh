#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the four limits of the rule Split large issues set in the pack (conveyor.sh split-limits), as the next
# split check (splitcheck(), lib/slices.sh) reads them.
# The fixtures (slices, judged) are those of slices.test.sh: the runner sources every case file into one shell.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Issue #7 names five files and has one Done-when item: under the schema's split.files (6) and the fixture's
# split.doneWhen (3). Bugs caught: `split-limits files=5` is saved where the split check does not read it (the issue
# is still under, with no judge call), `files=default` leaves the pack's 5 in force (the issue goes to the judge
# again), or the list with no argument names a wrong value or a wrong source for a limit.
t_splitlimitsset() {
  local out
  slices shadow '{"verdict":"keep","why":"one part"}' "[$(jq -cn '{number: 7, title: "five files", body: "Change src/a.sh, src/b.sh, src/c.sh, src/d.sh and src/e.sh.\n\nDone when:\n- first",
    milestone: null, createdAt: "2026-11-01", labels: [], authorAssociation: "OWNER"}')]"
  loop split-limits files=5 || fail "split-limits files=5 failed"
  out=$(loop split-limits) || fail "split-limits with no argument failed: $out"
  [ "$out" = $'doneWhen 3 pack\nfiles 5 pack\nareas 3 default\nchars 3000 default' ] || fail "split-limits with no argument, after files=5, printed: $out"
  fx_in 'splitcheck c1-7 7'
  [ "$RC" = 0 ] && [ "$(judged)" = 1 ] && [ "$(st 'select(.step == "split") | .split.verdict')" = keep ] \
    || fail "with split-limits files=5, #7 (five files) did not go to the judge (exit $RC, judged $(judged)): $(cat "$T/$CASE/run.out")"
  loop split-limits files=default || fail "split-limits files=default failed"
  [ "$(jq -c '.split' "$R/.conveyor/project.json")" = '{"doneWhen":3}' ] || fail "split-limits files=default left the pack's split: $(jq -c '.split' "$R/.conveyor/project.json")"
  : > "$ST/cards.jsonl" # c1-7's split line out, so c2-7's check is not skipped as one of the same text
  fx_in 'splitcheck c2-7 7'
  [ "$RC" = 0 ] && [ "$(judged)" = 1 ] && [ "$(st 'select(.step == "split") | .split.verdict')" = under ] \
    || fail "after split-limits files=default, #7 (five files, under the default 6) was not under the limits (exit $RC, judged $(judged)): $(cat "$T/$CASE/run.out")"
}

# Bug caught: a limit of 0 (every issue would reach it), a value that is not a number, or a limit the rule does not
# have is saved, or one bad argument lets the good one beside it be saved. Each is refused, and the pack is left byte
# for byte as it was.
t_splitlimitsrefused() {
  local before out a rc
  setup '[]'
  before=$(cat "$R/.conveyor/project.json")
  for a in 'files=0' 'files=five' 'files=' 'chars=5 files=0' 'growFiles=5' 'files'; do
    # shellcheck disable=SC2086 # each is the command's words
    out=$(loop split-limits $a 2>&1); rc=$?
    { [ "$rc" = 1 ] && [[ $out == *"nothing changed"* ]]; } || { [ "$rc" = 2 ] && [[ $out == usage:* ]]; } \
      || fail "split-limits $a was not refused with why (exit $rc): $out"
    [ "$(cat "$R/.conveyor/project.json")" = "$before" ] || fail "split-limits $a changed the pack: $(jq -c '.split' "$R/.conveyor/project.json")"
  done
}
