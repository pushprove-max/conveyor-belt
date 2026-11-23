#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the parts a run limited by --only reads again at each turn (onlyparts(), lib/issues.sh, through
# turnask(), lib/run.sh), as the issues it names close, move or are deleted.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bug caught: a run limited to #10 and #7, with closed part #8 under #7 and its open part #9. Once #10 was deleted, its
# parts could not be read at any turn, so onlyparts() threw away each new list and ONLY kept #8 after the owner moved it
# under #5: the pick (upnext) still took #9. A deleted issue has no parts: ONLY is read again without #8. #10 is walked
# first and closed part #11 is put under #7 after the deletion, so a walk that stops at the deleted issue also fails.
t_onlydeleted() {
  setup '[]'
  printf '7 8 CLOSED\n8 9 OPEN\n' > "$STUB/subs"; issue 9 2026-01-01 | jq -c '[. + {umbrella: 8}]' > "$STUB/sub.json"
  fx_in "ONLY='[10,7]' ONLYNAMED='[10,7]'; "'declare -A shuts=() mine=(); cap=1 building=0 now=running inuse=0 running=0 sampled=$SECONDS old= nopack= nocli= mhold= guard= waits= issues= ctl=null
    turnask >/dev/null 2>&1; echo "$ONLY"; upnext "$(cat "$STUB/sub.json")" | jq -c "[.[].number]"
    echo 10 > "$STUB/deleted"; printf "5 8 CLOSED\n8 9 OPEN\n7 11 CLOSED\n" > "$STUB/subs"
    turnask >/dev/null 2>&1; echo "$ONLY"; upnext "$(cat "$STUB/sub.json")" | jq -c "[.[].number]"'
  [ "$(cat "$T/$CASE/run.out")" = $'[10,7,8]\n[9]\n[10,7,11]\n[]' ] \
    || fail "with ONLYNAMED [10,7], closed #8 (open part #9) under #7, then #10 deleted, #8 moved under #5 and closed #11 put under #7, turnask and the pick did not give [10,7,8] and [9], then [10,7,11] and []: $(cat "$T/$CASE/run.out")"
}
