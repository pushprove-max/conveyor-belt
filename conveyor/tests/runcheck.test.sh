#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# The limit is the whole file's in a card's test step (lib/fileeach.sh), and each of its 6 cases waits there for a test
# slot of its own. They run in some 22 s alone, but on a busy step the waits for slots took the file past 120 s (times
# the load factor: 287 s once) with no case failed: all 3 flaky sightings were that time-out (#1781).
# Engine cases: the checks of the Board's fix cards for a test file that never ran (#189): Make it run (speedproof.sh runproof(),
# and ranproof() after its test step: the step ran the file and it passed) and Delete it (speedproof.sh deleteproof(): the change
# removes the file, then it is checked as an Optimize delete). fx_in and fx_wt are in lib.sh.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# A whole card, for what only it proves: card() checks a Make it run card by its title, after its test step.
# Bug it catches: a Make it run card whose test step never ran its file landed as fixed (the test command still
# skipped it). The change leaves f.test.sh alone and changes a.txt, so the card's test step runs only a.txt's linked
# a.test.sh (a step runs the test files the change touches) and passes without f.test.sh: the card is blocked after it.
t_runcard() {
  setup "[$(issue 7 2026-01-01 bug | jq -c '.title = "Make the test file f.test.sh run"')]"
  echo 'echo never' > "$R/f.test.sh" && git -C "$R" add f.test.sh && git -C "$R" commit -qm 'a test' && git -C "$R" push -q origin main || fail "main's file"
  echo "$GO" > "$STUB/review.1"; echo 'echo two >> a.txt' > "$STUB/build"
  loop run > /dev/null || fail "run exited non-zero"
  [ "$(st 'select(.step == "blocked") | .reason')" = "test: the card's test step did not run the test file f.test.sh: the test command still does not run it, or it ran none of its cases" ] \
    || fail "a Make it run card whose test step did not run its file was not blocked: $(st 'select(.step | IN("blocked", "landed"))')"
}

# What speedproof.sh ranproof() reads: a test step that passed a case of the file holds, one that passed other files does not; and
# speedproof.sh runproof() refuses a change that removes the file (that is Delete it).
t_runproofs() {
  setup '[]'; FXWT=; fx_wt 'rm f.test.sh' f.test.sh 'echo x'
  echo '{"units": ["f.test.sh\tone", "g.test.sh"], "cases": 2}' > "$T/$CASE/ran.passed"; echo '{"units": ["g.test.sh"], "cases": 1}' > "$T/$CASE/not.passed"
  fx_in 'ranproof "$T/$CASE/ran" f.test.sh && ! ranproof "$T/$CASE/not" f.test.sh && ! runproof "$FXWT" f.test.sh'
  [ "$RC" = 0 ] || fail "ranproof or runproof: $(cat "$T/$CASE/run.out")"
  [ "$WHY" = 'the change removes the test file f.test.sh: a Make it run card keeps it and makes the test command run it' ] || fail "the reason: $WHY"
}

# Bug it catches: a Delete it card that kept the file passed as done.
t_deletekeeps() {
  setup '[]'; FXWT=; fx_wt 'echo "echo y" > f.test.sh' f.test.sh 'echo x'
  fx_in 'deleteproof c7 "$FXWT" "{\"number\": 7}" f.test.sh'
  [ "$RC" != 0 ] && [ "$WHY" = 'the change keeps the test file f.test.sh: a Delete it card deletes it' ] || fail "a change that keeps the file passed: $RC $WHY"
}

# Bug it catches: a Delete it card that removes the file landed with no account of its cases. It is checked as an
# Optimize delete: the review is asked for a COVERED-BY line for each case of the file.
t_deletegone() {
  setup '[]'; FXWT=; fx_wt 'rm f.test.sh' f.test.sh 'echo x'
  fx_in 'deleteproof c7 "$FXWT" "{\"number\": 7}" f.test.sh'
  [ "$RC" = 0 ] && grep -qF 'This change removes the test file f.test.sh' "$FXWT.unfixed" && grep -qF 'COVERED-BY: <its test file>: <its case>' "$FXWT.unfixed" \
    || fail "a delete was not checked as an Optimize delete: $RC $(cat "$FXWT.unfixed" 2>&1)"
}

# A whole card, for what only it proves: card() checks a Delete it card again after a fix session changed it.
# Bug it catches: a fix session after a NO-GO put the deleted file back, and the card went on to its next review with
# the build's proof. The check runs again before that review, so the card is blocked, saying the change keeps the file.
t_deleterefix() {
  setup "[$(issue 7 2026-01-01 bug | jq -c '.title = "Delete the test file f.test.sh"')]"
  echo 'echo old' > "$R/f.test.sh" && git -C "$R" add f.test.sh && git -C "$R" commit -qm 'a test' && git -C "$R" push -q origin main || fail "main's file"
  echo "$NOGO" > "$STUB/review.1"; echo "$GO" > "$STUB/review.2"
  echo 'if [ -e f.test.sh ]; then rm f.test.sh; else echo "echo back" > f.test.sh; fi' > "$STUB/build"
  loop run > /dev/null || fail "run exited non-zero"
  [ "$(st 'select(.step == "blocked") | .reason')" = "review 2: the change keeps the test file f.test.sh: a Delete it card deletes it" ] \
    || fail "a Delete it card whose fix put the file back was not blocked before its next review: $(st 'select(.step | IN("blocked", "landed"))')"
  [ "$(wc -l < "$STUB/reviews")" = 1 ] || fail "the card was reviewed again on the file put back: $(wc -l < "$STUB/reviews") reviews"
}

# A whole card, for what only it proves: a retry with no build (#232) is checked as a build is.
# Bug it catches: a Make it run card stopped for the owner's yes to a visible change; retried with the yes, it landed
# from its kept patch with no build, so its proof checks were never set up, and it landed though its test step never
# ran its file. The change leaves f.test.sh alone (its test step runs a.txt's a.test.sh), so it is blocked after that
# test step, saying so.
t_runlandyes() {
  setup "[$(issue 7 2026-01-01 bug | jq -c '.title = "Make the test file f.test.sh run"')]"
  echo 'echo never' > "$R/f.test.sh" && git -C "$R" add f.test.sh && git -C "$R" commit -qm 'a test' && git -C "$R" push -q origin main || fail "main's file"
  echo 'echo two >> a.txt; mkdir -p web; echo pay >> web/pay.ts' > "$STUB/build"
  printf '%s\n' 'USER-VISIBLE: yes: guests see a new Pay button' 'VERDICT: GO' > "$STUB/review.1"
  # loop: the bug is in the retry's landing from its kept patch (resumeplan, the test step and its proof checks), not in the gate's outcome: visplan and visgate cannot show it
  loop run > /dev/null || fail "first run exited non-zero"
  st 'select(.step == "blocked") | .reason' | grep -q "^visible to customers or staff: needs .*'s yes" || fail "the card did not stop for the yes: $(st 'select(.step | IN("blocked", "landed"))')"
  issue 7 2026-01-01 bug | jq -c '[.title = "Make the test file f.test.sh run" | .body += "\n\nVisible change approved: Dana 2026-01-02 (yes)\n"]' > "$STUB/issues.json"
  loop retry 7 > /dev/null && loop run > /dev/null || fail "the retry exited non-zero"
  st 'select(.step == "worktree") | .reason' | grep -q '^landing from the kept patch of card' || fail "the retry did not land from the kept patch: $(st 'select(.step == "worktree") | .reason')"
  [ "$(st 'select(.step == "blocked") | .reason' | tail -n 1)" = "test: the card's test step did not run the test file f.test.sh: the test command still does not run it, or it ran none of its cases" ] \
    || fail "a Make it run card landed from its kept patch though its test step did not run its file: $(st 'select(.step | IN("blocked", "landed"))')"
}
