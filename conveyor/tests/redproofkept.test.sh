#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a main-red fix card's proof run (redproof()) keeps its output beside the card's kept work.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Issue 441. Bug it catches: a proof run that gave no result for a case removed its worktree and every file of it, so
# the block reason said "gave no result" and nothing was left to find why. The fixture is mainred.test.sh's
# (redsetup()): the change makes `a.test: one` not run (gone:one), so the run with the change prints no line for it.
# The check, then block() as card() calls it: the blocked line names the kept output file and quotes its end, and the
# file is still there once the run's worktree is gone. It also catches a change that renames a failing case (so it
# no longer runs) passing the check, as its file's passing run was read as the case passing, with no `ok one` from it.
t_redproofkept() {
  redsetup ''
  local w=$T/$CASE/cards/cfix k r t
  jq -c '.reds[0].card = "cfix"' "$ST/mainred.json" > "$STUB/red.new" && mv "$STUB/red.new" "$ST/mainred.json"
  git -C "$R" worktree add -q --detach "$w" HEAD && printf '%s\n' gone:one c.test > "$w/ok.txt" && git -C "$w" add ok.txt || fail "the fix card's worktree could not be made"
  eng 'bugproof cfix '"$w"' "$(redissue cfix)"; [ $? = 2 ] && block cfix 0 '"$w"' "build: $(<'"$w"'.unfixed)"' || fail "the check did not fail, or the card was not blocked: $(cat "$w.unfixed" 2>&1)"
  k=$ST/kept/cfix/cfix.redrun-with.out
  r=$(st 'select(.step == "blocked") | .reason'); t=$(st 'select(.step == "blocked") | .tail')
  [[ $r == "build: The run on main's code at "*" with the change gave no result for \`a.test: one\`, so it proves nothing either way. The whole output of that run is kept in $k." ]] \
    || fail "the block reason does not name the kept output file: $r"
  [ ! -e "$T/$CASE/cards/mainrun/cfix.unfixed" ] && grep -qx '== a.test' "$k" && [ "$(tail -n 1 "$k")" = '== c.test' ] \
    || fail "the run's worktree is still there, or its output was not kept in $k: $(cat "$k" 2>&1)"
  [[ $t == *"The end of that run's output:"$'\n```\n'"$(tail -n 40 "$k")"$'\n```'* ]] || fail "the blocked line does not quote the end of the kept output: $t"
}
