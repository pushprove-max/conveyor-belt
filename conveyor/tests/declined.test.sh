#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the declined list (lib/followups.sh) when it cannot be read, and when its lock is held.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# One line of the declined list that is not JSON. Bug: `declined dismiss` said the list has no line of an id it has
# (every id named was "missing"), and `declined build` filed the issue, then could not mark the line; each now says
# the list could not be read, and changes and files nothing.
t_declinedbad() {
  local id out
  setup '[]'
  loop declined add c1-7 7 code 'follow-up of a follow-up' '[P2] a.txt:1 wrong word' || fail "a declined finding was not taken"
  id=$(jq -r .id "$ST/declined.jsonl")
  echo 'not json' >> "$ST/declined.jsonl"
  out=$(loop declined dismiss "$id" 2>&1) && fail "dismiss of an unreadable list passed: $out"
  [[ $out == *'the declined list could not be read; nothing dismissed'* && $out != *'has no line'* ]] \
    || fail "dismiss did not say the list could not be read: $out"
  out=$(loop declined build "$id" 2>&1) && fail "build of an unreadable list passed: $out"
  [[ $out == *'the declined list could not be read; nothing filed'* ]] || fail "build did not say the list could not be read: $out"
  [ ! -s "$STUB/filed" ] && [ "$(head -n 1 "$ST/declined.jsonl" | jq -c '[.dismissed, .built]')" = '[null,null]' ] \
    || fail "an unreadable list was changed, or an issue was filed: $(cat "$ST/declined.jsonl" "$STUB/filed" 2>&1)"
}

# Bug caught: declined() read the clock before it waited for the list's lock, so a ruling made while another writer
# (a `declined build` on its GitHub calls) held the lock was dated before it was saved, and a replay gave a judge
# that read the list in that wait the ruling it never saw. The clock here says 00:00:20 while the test holds the lock
# and 00:03:00 once it lets go; flock() marks that declined() reached its wait. The poll waits on that mark: what is
# checked is the order of a running declined()'s clock and its wait on a held lock, which a call alone cannot show.
t_declinedwait() {
  setup '[]'
  fx_in 'clock() { cat "$T/$CASE/now"; }
    flock() { : > "$T/$CASE/waits"; command flock "$@"; }
    echo 2026-11-01T00:00:20Z > "$T/$CASE/now"; exec 8>>"$DECLINED.lock"; command flock 8 || exit 3
    declined c1-7 7 owner "claim wrong: guarded" "[P2] a.txt:4 F-lk" "claim wrong" 8>&- & p=$!
    wait_until "[ -e \"$T/$CASE/waits\" ]" || exit 4
    echo 2026-11-01T00:03:00Z > "$T/$CASE/now"; command flock -u 8; exec 8>&-; wait "$p"'
  [ "$RC" = 0 ] && [ "$(jq -r 'select(.finding == "[P2] a.txt:4 F-lk") | .time' "$ST/declined.jsonl")" = 2026-11-01T00:03:00Z ] \
    || fail "declined c1-7 7 owner 'claim wrong: guarded' '[P2] a.txt:4 F-lk' 'claim wrong', run while the lock was held until 00:03:00: the line is not dated 00:03:00: $RC $(cat "$T/$CASE/run.out" "$ST/declined.jsonl" 2>&1)"
}
