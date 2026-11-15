#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the declined list (lib/followups.sh) when it cannot be read.
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
