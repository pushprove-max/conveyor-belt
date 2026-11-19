#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the mutation checks and the loop (lib/mutate.sh mutnext(), lib/run.sh): the `serve` loop's idle job,
# and no card step that runs a check. The setup and helpers (musetup, mu*) are in mutate.test.sh.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# The loop's idle job (`serve`, nothing to build): it checks the files of its queue, then, with the queue empty, keeps
# main's commit as the one it found nothing on. Bug this guards: an idle loop that never ran a check, or one that went
# on looking at an empty queue.
t_mutserve() {
  musetup
  tune '.tunables.idle = 1 | .tunables.poll = 1'
  loop serve > "$STUB/serve.out" 2>&1 & mupid=$!; trap 'kill $mupid 2>/dev/null' EXIT
  wait_until "[ \"\$(cat '$ST/testactions/mutations/idle' 2>/dev/null)\" = '$(git -C "$R" rev-parse HEAD)' ]" "cat '$STUB/serve.out'; cat '$ST'/testactions/mutations/*.json" \
    || fail "the idle loop did not check its queue to the end"
  # a.test.sh, the per-file fixture's stub test file, sources nothing: its check is done with no mutant to try.
  [ "$(jq -cs 'map([.file, .state, .tried]) | sort' "$ST"/testactions/mutations/*.json)" = '[["a.test.sh","done",0],["k.test.sh","done",3],["s.test.sh","done",3]]' ] \
    || fail "the idle loop did not check each test file once: $(cat "$ST"/testactions/mutations/*.json)"
  kill $mupid; wait $mupid 2>/dev/null; return 0
}

# D4. A card that runs every step (build, review, test, landing) on a main whose test files no check has seen. Bug this
# guards: a card step that runs a mutation check, which would make its record and run the test file on a mutant; a
# card's test run that holds no ask in the shared test slots (slot_ask()), so a mutation check of another project,
# which does not see this project's cards, would run beside it.
t_mutcard() {
  musetup "[$(issue 7 2026-01-01)]"
  echo "$GO" > "$STUB/review.1"
  loop run > /dev/null 2>&1 || fail "run exited non-zero"
  [ -n "$(st 'select(.step == "landed")')" ] || fail "the card did not land"
  [ -z "$(ls "$ST/testactions/mutations" 2>/dev/null)" ] && [ ! -e "$STUB/mut-runs" ] || fail "a card step ran a mutation check: $(ls "$ST/testactions/mutations")"
  [ -s "$STUB/tests" ] && [ "$(sort -u "$STUB/asks" 2>/dev/null)" = asked ] || fail "the card's test run held no ask in the shared test slots: $(cat "$STUB/asks" 2>&1)"
}
