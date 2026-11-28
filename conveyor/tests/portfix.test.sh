#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a test fix on the port of a card whose landing conflicted again (other landing conflicts and ports are
# in port.test.sh). Each case that runs whole cards is a file of its own: the Test step runs a file's cases one after
# another, so in port.test.sh they added up past its time limit on a busy machine.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
# shellcheck disable=SC2034 # the closure tool reads this line; the cases here do not use SRC
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# AGAIN, the build stub's line that moves main again during the port, is portagain.test.sh's: the runner loads every
# case file into one shell.

# Bug: after a GO on the review of a port whose earlier loop ended on a NO-GO, a test fix and the
# GO after it landed the card with nothing filed: the earlier loop's findings were lost.
# Bugs of the card blocked here, a last review's NO-GO whose landing conflicts, and conflicts again after its port: its
# three follow-ups were not withdrawn as not planned each time, their findings kept. Of the retried card, whose kept
# patch no longer applies to main (resumeport takes it up with no card run): its port session was not told the
# patch's file and the commit it was built on, or to change nothing else (its one review's prompt is resumeport's,
# with no card run).
t_portfix() {
  setup "[$(issue 8 2026-01-01)]"; for i in 1 2 3; do moved "${i/3/}" "$PORTNOGO" | p1at2 "$i" > "$STUB/review.$i"; done; echo "$GO" > "$STUB/review.4"
  steps() { st "select(.issue == $1) | \"\(.step) \(.result) \(.reason)\"" | tr '\n' ,; }
  echo 'cp "$STUB/brief" "$STUB/brief.$(wc -l < "$STUB/sessions")"; echo two >> a.txt; '"$AGAIN" > "$STUB/build"; echo 'ONE other' > "$STUB/move"
  # loop: only a whole card run shows a last review's NO-GO, a landing conflict and the retry that ports it
  loop run >/dev/null; st 'select(.step == "blocked") | .reason' | grep -q '^rebase onto main conflicts' || fail "#8 was not blocked on its landing conflict: $(steps 8)"
  [ "$(tr '\n' ' ' < "$STUB/closed")" = "100101 100102 100103 100104 100105 100106 " ] && [ "$(grep -c -- '^--reason not planned --comment .*withdrawn.* #8 ' "$STUB/close-comments")" = 6 ] \
    || fail "the withdrawn follow-ups were not closed as not planned, each naming #8: $(cat "$STUB/closed" "$STUB/close-comments" 2>&1)"
  local k old s
  k=$(st 'select(.issue == 8 and .step == "blocked") | "\($ENV.ST)/\(.kept)"'); old=$(st 'select(.issue == 8 and .step == "blocked") | .card')
  [ "$(sed -n 2p "$k/$old.withdrawn")" = '#100102 [P2] b.txt:22 no mark here' ] && [ -s "$k/$old.patch" ] || fail "the withdrawn findings or the patch are not in the kept folder: $(ls "$k")"
  echo "$GO" > "$STUB/review.5"; echo "$GO" > "$STUB/review.6"
  # The third run fails, and its run again too (tests()), so the test fix starts. It exits 1, so filecmd()
  # (lib/testrun.sh) reports a.test.sh failed, the one file test.fileCommand is given: a failure it reported in another file would be a run of files it was not given
  # (session.sh watch()), which stops the run and blocks the card before any test fix.
  echo 'echo x >> "$STUB/tests"; case $(wc -l < "$STUB/tests") in 3|4) exit 1 ;; esac' > "$STUB/test-cmd"
  s=$(($(wc -l < "$STUB/sessions") + 1))
  # The bug is after the resume, in the port's test fix, its second GO and the landing that files the earlier loop's findings.
  # loop: only the card's own steps show the port's brief, its review, test fix, second GO and landing
  loop retry 8 >/dev/null && loop run >/dev/null || fail "run of the retried #8 exited non-zero"
  [ "$(cat "$k/$old.base")" != "$(git -C "$R" rev-parse HEAD)" ] && grep -q "^# This card brings the change of blocked card $old onto main$" "$STUB/brief.$s" \
    && grep -q "The patch is the file $k/$old.patch, built on commit $(cat "$k/$old.base")\. Bring that change onto main as it is now.* resolve the conflicts" "$STUB/brief.$s" \
    && grep -q 'Change nothing else: that change finished its review loop' "$STUB/brief.$s" && ! grep -q 'from nothing\.\? *$\|Build the issue' "$STUB/brief.$s" \
    || fail "the port session of a finished loop was not told the patch and the commit it was built on, or to change nothing else: $(tail -n 6 "$STUB/brief.$s")"
  [ "$(st 'select(.issue == 8 and '"$NOMARK"') | "\(.step) \(.result)"' | tr '\n' ,)" = "picked ok,worktree ok,brief ok,build ok,review GO,test fail,fix ok,review GO,test pass,landed ok," ] \
    && [ "$(st 'select(.issue == 8 and .step == "landed") | .leftover')" = true ] \
    && [ "$(tail -n 3 "$STUB/filed" | jq -r .title | tr '\n' '|')" = '[P2] a.txt:1 wrong word|[P2] b.txt:22 no mark here|[P2] c.txt:3 a nit|' ] \
    || fail "a test fix after the port's GO lost the earlier loop's findings: $(steps 8)"
  [ "$(st 'select(.issue == 8 and .step == "filed") | .followups | length')" = 3 ] || fail "no filed line names the three follow-ups: $(steps 8)"
  recok "$ST/cards.jsonl" "a card that landed on a NO-GO (its filed line, and its landed line with leftover and followups)"
}
