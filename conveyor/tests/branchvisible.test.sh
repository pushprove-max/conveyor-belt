#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: land-branch, a visible change.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Split from branch.test.sh, whose setup (branchsetup) and bugs these cases share, so no one file is over the
# CPU budget (test.fileBudget): its six cases cost about 17 CPU s together.
t_branchvisible() {
  branchsetup
  # A change customers or staff would see is blocked without the owner's yes; a branch of no issue carries that yes
  # in a commit message.
  for i in 1 2; do printf 'USER-VISIBLE: yes: a new button\nVERDICT: GO\n' > "$STUB/review.$i"; done
  lane fast-seen web/f.txt eff; at=$(git -C "$R" rev-parse main)
  out=$(loop land-branch fast-seen) && fail "a visible change landed without the owner's yes: $out"
  c=$(newest); [ "$(steps "$c")" = "picked worktree deps brief start review blocked " ] && [ "$(git -C "$R" rev-parse main)" = "$at" ] && [ ! -e "$STUB/comments" ] \
    && st "select(.card == \"$c\" and .step == \"blocked\") | .reason" | grep -q "needs Dana's yes: a new button" || fail "visible change of a branch card: $(steps "$c") $out"
  git -C "$T/$CASE/lane-fast-seen" commit -q --allow-empty -m $'fix(tooling): the button\n\nVisible change approved: Dana, r-1'
  out=$(loop land-branch fast-seen) || fail "a visible change with the owner's yes in a commit message did not land: $out"
  [ "$(cat "$R/web/f.txt")" = eff ] && [ "$(steps "$(newest)")" = "picked worktree deps brief start review start test start landed " ] || fail "the approved visible change is not on main"
}
