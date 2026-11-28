#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a port whose landing conflicts again blocks for the owner, and its retry (other landing conflicts and
# ports are in port.test.sh). Each case that runs whole cards is a file of its own: the Test step runs a file's cases
# one after another, so in port.test.sh they added up past its time limit on a busy machine.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
# shellcheck disable=SC2034 # the closure tool reads this line; the cases here do not use SRC
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
# A line of a build stub: the session that ports a card after its landing conflict moves main's a.txt again, so the
# card's landing conflicts once more and it blocks for the owner (a case that goes on to `retry` it).
AGAIN='if grep -q "^# Landing conflict" "$STUB/brief"; then echo TWO > "$R/a.txt"; git -C "$R" commit -qam again; fi'

# Bugs: the port's landing conflicts too (its session moves main again) and something lands, or a second port runs:
# it blocks for the owner. A NO-GO on the one review of a port (a finished loop stopped only by a landing conflict)
# lands with follow-ups as if it were a last review, instead of being fixed and going round the loop as any card's.
t_port() {
  setup "[$(issue 8 2026-01-01)]"; for i in 1 2 3; do moved "${i/3/}" "$PORTNOGO" | p1at2 "$i" > "$STUB/review.$i"; done; echo "$GO" > "$STUB/review.4"
  steps() { st "select(.issue == $1) | \"\(.step) \(.result) \(.reason)\"" | tr '\n' ,; }
  echo "echo two >> a.txt; $AGAIN" > "$STUB/build"; echo 'ONE other' > "$STUB/move"
  # loop: only a whole card run shows a finished loop stopped by a landing conflict, then the port's own review
  loop run >/dev/null || fail "run of #8 exited non-zero"
  [ "$(st 'select(.issue == 8 and '"$NOMARK"') | "\(.step) \(.result)"' | tr '\n' ,)" = "picked ok,worktree ok,brief ok,build ok,test pass,review NO-GO,fix ok,review NO-GO,fix ok,review NO-GO,test pass,rebase ok,review GO,test pass,blocked blocked," ] \
    && st 'select(.issue == 8 and .step == "blocked") | .reason' | grep -q '^rebase onto main conflicts: ' && [ "$(wc -l < "$STUB/sessions")" = 4 ] \
    && [ "$(git -C "$R" log -1 --format=%s)" = again ] || fail "a conflict after the port did not block for the owner: $(steps 8)"
  echo "$NOGO" > "$STUB/review.5"; echo "$GO" > "$STUB/review.6"; f=$(wc -l < "$STUB/filed")
  # resumeplan only gives the port its finished loop's GO (fin); what is proved is card()'s handling of a NO-GO on that
  # one review: fixed and reviewed again, and the earlier loop's last NO-GO (3 findings) filed again as it lands (afterreview()).
  # loop: only the card's review loop shows a NO-GO on the port's one review fixed and reviewed again
  loop retry 8 >/dev/null && loop run >/dev/null || fail "run of the retried #8 exited non-zero"
  [ "$(st 'select(.issue == 8 and '"$NOMARK"') | "\(.step) \(.result)"' | tr '\n' ,)" = "picked ok,worktree ok,brief ok,build ok,review NO-GO,fix ok,review GO,test pass,landed ok," ] \
    && [ "$(wc -l < "$STUB/filed")" = "$((f + 3))" ] && [ "$(st 'select(.issue == 8 and .step == "landed") | .leftover')" = true ] && [ "$(tr '\n' ' ' < "$R/a.txt")" = "TWO two two " ] \
    || fail "a NO-GO on the port's review was not fixed and reviewed again before landing, or the earlier loop's findings were not filed: $(steps 8)"
  loop check || fail "the records do not check"
}
