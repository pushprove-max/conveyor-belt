#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: what a card is told about the staged change it starts on.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bug (#874): a card that starts from the kept patch of a blocked card was not told whose work the staged change is,
# nor that it owns it now, so its builder took the change for unexplained leftovers and left it. Its build prompt names
# the earlier card and its block reason and gives it the change; its start line names the kept patch's card.
# Two whole card runs: the kept patch is made by a real block and taken up by a real retry, which only a card run gives.
t_keptbrief() {
  local old why
  setup "[$(issue 9 2026-01-01)]"; echo "$GO" > "$STUB/review.3"; echo 'exit 3' > "$STUB/review-cmd"
  echo 'if grep -q "^# This card resumes blocked card" "$STUB/brief"; then cp "$STUB/brief" "$STUB/resumed-brief"; else echo nine > n.txt; fi' > "$STUB/build"
  loop run >/dev/null; old=$(st 'select(.issue == 9 and .step == "blocked") | .card')
  why=$(st 'select(.issue == 9 and .step == "blocked") | .reason')
  [[ $why == "review 1: "?* ]] || fail "#9 was not blocked on its failed review: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
  rm "$STUB/review-cmd"; loop retry 9 >/dev/null && loop run >/dev/null || fail "run of the retried #9 exited non-zero"
  [ "$(st "select(.issue == 9 and .step == \"worktree\" and .card != \"$old\") | .reason")" = "resumed from the kept patch of card $old: one session, then review" ] \
    || fail "the start line of the retried card does not name the kept patch of $old: $(st 'select(.step == "worktree") | .reason')"
  grep -qF "The staged change in this worktree is no leftover: it is the kept work of card $old, an earlier card of this issue" "$STUB/resumed-brief" \
    && [[ $(cat "$STUB/resumed-brief") == *"applied to main as it stands. That card was blocked: ${why:0:600}"$'\n'* ]] \
    && grep -qF 'That change is yours now: keep, change or drop each part of it.' "$STUB/resumed-brief" \
    && grep -qF 'The checks at the end (the bug-card check too) judge the whole staged change' "$STUB/resumed-brief" \
    || fail "the build prompt does not name card $old, its block reason, and that the staged change is the build's own now: $(grep -A3 '^# This card resumes' "$STUB/resumed-brief" 2>&1)"
}

# Bug (#874): a card with no kept work that found a staged change in its new worktree built on it, as its own. It
# stops before the build with a reason naming the files. The change is staged by a post-checkout hook of main (git
# runs it in each new worktree), so it is there at the card's start as it would be in a project; a whole card run, as
# the check is in card() between the worktree and the build. #1444 (R230): the check came after the card asked GitHub
# for its issue, so a GitHub that did not answer held the block; gh here hangs on that ask, and the card must block
# without making it. The rules Split large issues and Pick settings are On, as each asks GitHub for the issue first.
# Only the card's asks for the issue (--json number,...) count: the turn after the block asks whether the blocked
# issue is closed (`--json closed`, turnask()), which is no part of the card (review E6).
t_straystaged() {
  setup "[$(issue 5 2026-01-01)]"; echo "$GO" > "$STUB/review.1"
  printf '%s\n' '#!/bin/sh' '[ "$1" = 0000000000000000000000000000000000000000 ] || exit 0' 'echo stray > stray.txt && git add stray.txt' > "$R/.git/hooks/post-checkout"
  chmod +x "$R/.git/hooks/post-checkout"
  loop control rules split=on pick=on >/dev/null || fail "control rules split=on pick=on was refused"
  # stub: each ask of the card for its issue is noted in $STUB/viewed, and hangs as a GitHub that does not answer
  sed -i '2a case "$*" in "issue view 5 --json number,"*) echo "$*" >> "$STUB/viewed"; exec sleep 10 ;; esac' "$STUB/gh" # sleep: a GitHub that does not answer
  loop run >/dev/null
  [ ! -e "$STUB/viewed" ] || fail "the card asked GitHub for its issue before it checked its new worktree for a staged change: $(cat "$STUB/viewed")"
  [ "$(st 'select(.issue == 5 and .step == "blocked") | .reason')" = "worktree: the new worktree already holds a staged change that is no kept work of this issue: stray.txt" ] \
    || fail "a card whose new worktree held a staged change did not stop naming the file: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
  [ ! -s "$STUB/sessions" ] && [ -z "$(st 'select(.issue == 5 and (.step | IN("build", "brief"))) | .step')" ] \
    || fail "the card went on to its brief or build on the stray staged change: $(st '.step' | tr '\n' ' ')"
}

# Bug (#1385): the check above skipped a card that took up a kept patch: the patch was applied on top of what the
# post-checkout hook staged, and the card took stray.txt as its own work (a kept patch that lands with no review
# committed it unreviewed). t_keptbrief's retry with t_straystaged's hook: the retried card blocks naming stray.txt,
# before its brief. Two whole card runs, as t_keptbrief: a real block keeps the patch, a real retry takes it up in a
# new worktree, where git runs the hook.
t_keptstray() {
  local old
  setup "[$(issue 9 2026-01-01)]"; echo 'exit 3' > "$STUB/review-cmd"; echo 'echo nine > n.txt' > "$STUB/build"
  # loop: a real block keeps the patch that the retry takes up.
  loop run >/dev/null; old=$(st 'select(.issue == 9 and .step == "blocked") | .card')
  [ -n "$old" ] && [ -s "$ST/kept/$old/$old.patch" ] || fail "#9 was not blocked with its patch kept: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
  printf '%s\n' '#!/bin/sh' '[ "$1" = 0000000000000000000000000000000000000000 ] || exit 0' 'echo stray > stray.txt && git add stray.txt' > "$R/.git/hooks/post-checkout"
  chmod +x "$R/.git/hooks/post-checkout"; rm "$STUB/review-cmd"
  loop retry 9 | grep -q 'starts from the kept patch' || fail "retry of #9 does not say its next card starts from the kept patch"
  # loop: only a card started by the loop gets a new worktree, where git runs the hook, before it applies the patch.
  loop run >/dev/null
  [ "$(st "select(.issue == 9 and .step == \"blocked\" and .card != \"$old\") | .reason")" = "worktree: the new worktree already holds a staged change that is no kept work of this issue: stray.txt" ] \
    || fail "the retried card, its new worktree holding the hook's staged stray.txt, did not stop naming it: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
  [ -z "$(st "select(.issue == 9 and .card != \"$old\" and (.step | IN(\"build\", \"brief\", \"review\", \"landed\"))) | .step")" ] \
    || fail "the retried card went on with the stray staged change: $(st '.step' | tr '\n' ' ')"
}
