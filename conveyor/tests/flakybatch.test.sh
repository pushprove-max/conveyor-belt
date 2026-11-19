#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the flaky-test record (lib/flaky.sh) in whole card runs: a pass on re-run before a batch's run is kept,
# and a card's run keeps the record's cases off while the full suite runs them. Its own file: with the record's other
# cases (flaky.test.sh) it was over the test step's CPU budget for one file.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bug: the entries were read only once the card's tests had all passed, after its batch's run, which clears what its
# own run said: a card whose own run passed on re-run and whose batch (landBatch 8) then passed first time added none.
# #7's own run of its file a.test.sh fails a.test.sh: flaky once and passes on re-run; its batch of #8 and itself then
# passes: one entry. Bug it catches too: #449 failed three times, and blocked twice, on cases that failed at random. The
# batch's run, a card's run, is told to keep a.test.sh: flaky, now on the record, off (an `off` line, flakyoff()); the
# full suite (test.full) is given no such list and runs it. Each run's list is $STUB/rerun.<run>.
t_flakybatch() {
  batchsetup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"; echo 8 > "$STUB/ready"
  echo 'case $PWD in *-7) sed -i 1s/.*/seven/ a.txt ;; *) echo eight >> a.txt ;; esac' > "$STUB/build"
  echo '[ "${CONVEYOR_TEST_RERUN:-/dev/null}" = /dev/null ] || cp "$CONVEYOR_TEST_RERUN" "$STUB/rerun.$(wc -l < "$STUB/tests")"
    case $PWD in *-7) [ -e "$STUB/flaked" ] || { : > "$STUB/flaked"; echo "FAIL [flaky]: wrong"; exit 1; } ;; esac' >> "$STUB/test-cmd"
  out=$(loop run 2>&1) || fail "run exited non-zero: $out"
  local c7; c7=$(cardof 7)
  # Four runs: #8's own, #7's own and its re-run, then the batch's, which passed first time.
  grep -q "card $c7 tests a batch of 2" <<<"$out" && [ -e "$STUB/flaked" ] && [ "$(wc -l < "$STUB/tests")" = 4 ] \
    || fail "#7's own run did not pass on re-run before its batch's run: $(wc -l < "$STUB/tests") runs: $out"
  [ "$(fl '[.entries[] | [.case, .source, .issue] | join(" ")] | join("|")')" = "a.test.sh: flaky $c7 7" ] \
    || fail "#7's pass on re-run, before its batch's run, is not one entry: $(cat "$ST/flaky.json" 2>&1)"
  [ "$(st 'select(.step == "landed") | .issue' | sort -n | tr '\n' ' ')" = "7 8 " ] || fail "a card never landed: $(st '"\(.issue) \(.step) \(.result)"' | tr '\n' ,)"
  grep -qxF $'off\ta.test.sh\tflaky' "$STUB/rerun.4" || fail "the batch's run was not told to keep the flaky case off: $(cat "$STUB/rerun.4" 2>&1)"
  tune --arg c ". \"$STUB/test-cmd\"" '.test.full = $c'
  loop full-test > /dev/null || fail "the full suite did not start"
  wait_until '[ -s "$ST/fulltest.jsonl" ] && [ ! -e "$ST/fulltest.jsonl.running" ]' 'cat "$ST/fulltest.jsonl.log"' || fail "the full suite did not end"
  [ "$(wc -l < "$STUB/tests")" = 5 ] && [ ! -e "$STUB/rerun.5" ] || fail "the full suite did not run, or was told to keep the flaky case off: $(cat "$STUB/rerun.5" 2>&1)"
}
