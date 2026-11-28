#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a finished loop whose landing conflicts is ported in the card with no owner action (other landing
# conflicts and ports are in port.test.sh). Each case that runs whole cards is a file of its own: the Test step runs a
# file's cases one after another, so in port.test.sh they added up past its time limit on a busy machine.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
# shellcheck disable=SC2034 # the closure tool reads this line; the cases here do not use SRC
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bug: a card whose review loop had finished (a last NO-GO, its follow-ups filed) blocked for the owner when its
# landing met a conflict, and sat there until the owner ran `retry`. It is ported in the card with no owner action:
# one session, one review of that port alone, the tests and the landing, which files the loop's findings again; the
# Board shows the port as a step, not a block. A conflict after that port blocks for the owner (t_port,
# portagain.test.sh).
# Bug: a card that files a last NO-GO's follow-ups had no <worktree>.ready, so its test pass was stored nowhere and it
# ran its tests again each time it came to the test step (the owner: passes are reused). Its pass is kept, keyed to
# its staged change: the port, a different change, runs its tests again; main moving on another file during the
# port's tests then fits it onto main with the same change, which reuses the port's pass and starts no run. It lands
# alone, with the earlier loop's findings filed.
t_autoport() {
  setup "[$(issue 8 2026-01-01)]"; for i in 1 2 3; do moved "${i/3/}" "$PORTNOGO" | p1at2 "$i" > "$STUB/review.$i"; done; echo "$GO" > "$STUB/review.4"
  steps() { st "select(.issue == $1 and $NOMARK) | \"\(.step) \(.result)\"" | tr '\n' ,; }
  echo 'echo two >> a.txt' > "$STUB/build"; echo 'ONE other' > "$STUB/move"
  echo '[ "$(wc -l < "$STUB/tests")" != 2 ] || { echo b > "$R/b.txt"; git -C "$R" add b.txt; git -C "$R" commit -qm "main adds b.txt"; }' >> "$STUB/test-cmd"
  echo '[ ! -e "$PWD.port" ] || { cp "$PWD.port" "$STUB/port"; cp "$PWD.ready" "$STUB/readyatport"; echo "$PWD" > "$STUB/portwt"; }' > "$STUB/review-cmd"
  # Each review's prompt is kept, as $STUB/prompt.<n>.
  sed -i 's|^cat > /dev/null; echo x >> "$STUB/reviews";|echo x >> "$STUB/reviews"; cat > "$STUB/prompt.$(wc -l < "$STUB/reviews")";|' "$STUB/codex"
  # loop: only a whole card run shows the port's tests, the move on main and the auto-port that reuses its pass
  loop run >/dev/null || fail "run of #8 exited non-zero"
  [ "$(steps 8)" = "picked ok,worktree ok,brief ok,build ok,test pass,review NO-GO,fix ok,review NO-GO,fix ok,review NO-GO,test pass,rebase ok,review GO,test pass,test pass,landed ok," ] \
    && [ "$(wc -l < "$STUB/sessions")" = 4 ] && [ "$(wc -l < "$STUB/reviews")" = 4 ] \
    || fail "a finished loop whose landing conflicted was not ported by one session, reviewed once, tested and landed: $(steps 8)"
  [ "$(jq -c '[.tested, .alone, (.patch | length > 0)]' "$STUB/readyatport" 2>/dev/null)" = '[true,true,true]' ] \
    || fail "the card with a last NO-GO did not store its test pass, marked alone, keyed to its staged change: $(cat "$STUB/readyatport" 2>&1)"
  [ "$(wc -l < "$STUB/tests")" = 2 ] && [ "$(st 'select(.issue == 8 and .step == "test") | .reused' | tr '\n' ,)" = "null,null,null,true," ] \
    && [ "$(st 'select(.issue == 8 and .step == "landed") | .batch')" = null ] \
    || fail "the port, a different staged change, did not run its tests, its fit onto the moved main with the same change ran them again, or it did not land alone: $(wc -l < "$STUB/tests") runs, $(steps 8) $(st 'select(.issue == 8 and .step == "landed")')"
  [ "$(cat "$R/b.txt")" = b ] && [ "$(git -C "$R" log -1 --format=%P | wc -w)" = 1 ] && [ "$(git -C "$R" log -2 --format=%s | tail -n 1)" = "main adds b.txt" ] \
    || fail "#8 did not land alone on the main that moved: $(git -C "$R" log --oneline | head -3)"
  st 'select(.issue == 8 and .step == "rebase") | .reason' | grep -q '^rebase onto main conflicts: ' || fail "the port's step does not name the conflict"
  # Bug (#1385): nothing marked the port, so a retry counted the reviews before it as its rounds (t_resumeport3).
  [ "$(st 'select(.issue == 8 and .step == "rebase") | .port')" = true ] && recok "$ST/cards.jsonl" "an automatic port" \
    || fail "the port's rebase line does not mark it as the port: $(st 'select(.issue == 8 and .step == "rebase")')"
  # The .port file and the instructions of the port's review are made inside card() (no function makes them), so only
  # this run shows that review is told it reviews a port alone and handed the kept patch against the ported change.
  # Bug: the port's review was given the instructions of any other review (no PORTREVIEW, no .port file named).
  # Bug: a prompt that names another file (such as <worktree>.patch.port) in place of <worktree>.port, the file the
  # engine writes, sends the review to a file that is not there: the line must name that exact path.
  grep -qx -- '+ ONE' "$STUB/port" && grep -qx -- ' +two' "$STUB/port" || fail "the review after the port was not handed the kept patch against the port: $(cat "$STUB/port" 2>&1)"
  grep -qx '# This review is of a port alone' "$STUB/prompt.4" && grep -qxF "The difference is the file $(cat "$STUB/portwt" 2>&1).port." "$STUB/prompt.4" \
    && ! grep -q '^# This review is of a port alone' "$STUB/prompt.3" \
    || fail "the port's review, and it alone, was not told it reviews the port and handed the .port file: $(grep -n 'port' "$STUB/prompt.4" 2>&1 | tail -n 4)"
  [ "$(tr '\n' ' ' < "$STUB/closed")" = "100101 100102 100103 " ] && [ "$(st 'select(.issue == 8 and .step == "landed") | [.leftover, .followups] | tojson')" = '[true,[100104,100105,100106]]' ] \
    && [ "$(tr '\n' ' ' < "$R/a.txt")" = "ONE two " ] || fail "the port did not withdraw the follow-ups and file the loop's findings again at its landing: $(st 'select(.issue == 8 and .step == "landed")')"
  # Bug: the filed line after the port's GO said the loop ended on that GO, not on review 3's max-reviews whose
  # findings it files.
  [ "$(st 'select(.issue == 8 and .step == "filed") | [.stop, .pass, .rounds] | tojson' | tr '\n' ' ')" = '["max-reviews",3,0] ["max-reviews",3,0] ' ] \
    || fail "a filed line does not say why the loop whose findings it files ended: $(st 'select(.issue == 8 and .step == "filed") | tojson')"
  [ "$(loop cards | jq -c '.cards[0] | [.step, (.steps | map(.step) | join(" "))]')" = '["landed","build test review fix review fix review test rebase review test test"]' ] \
    && [ -z "$(st 'select(.step == "blocked")')" ] && [ ! -s "$ST/retried.jsonl" ] || fail "the port is not a step of the card's row, or it blocked or was retried: $(loop cards | jq -c '.cards[0]')"
}
