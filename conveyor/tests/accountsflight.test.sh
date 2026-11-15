#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a card in flight keeps the account it started on, whatever the record names after.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner. Its case is one of accounts.test.sh's four (the bugs are named there),
# from the two projects acctsetup (accounts.test.sh) makes, in a file of its own so no file is over the CPU budget.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

t_accountsflight() {
  acctsetup; ctl account second >/dev/null; ctl guard 90 >/dev/null; b ctl guard 90 >/dev/null
  # A's account under the limit: its card runs on that account's folder; a change of the record while it runs (a
  # build, then a NO-GO and a fix) reaches no session of that card, only the next card's (t_accountsnext).
  resp 50 > "$STUB/limit2"; printf '%s\n' "$NOGO" > "$STUB/review.1"; for i in 2 3 4; do printf '%s\n' "$GO" > "$STUB/review.$i"; done
  echo 'for i in $(seq 600); do [ -e "$STUB/go" ] && break; sleep 0.1; done; echo "${CLAUDE_CONFIG_DIR:-default}" >> "$STUB/acct"; echo two >> a.txt' > "$STUB/build"
  loop run --only 5 >/dev/null 2>&1 & run=$!
  for i in $(seq 100); do [ -n "$(st 'select(.step == "worktree") | .card')" ] && break; sleep 0.1; done
  ctl account first >/dev/null
  # The snapshot names the account the card in flight runs on, beside the record's, so the Board never shows it unused.
  [ "$(loop snapshot | jq -c '[.control.account, .inFlight]')" = '["first",[{"account":"second","reviewAccount":null}]]' ] \
    || fail "the snapshot does not name the account of the card in flight: $(loop snapshot | jq -c '[.control.account, .inFlight]')"
  : > "$STUB/go"; wait $run
  [ "$(tr '\n' , < "$STUB/acct")" = "$T/$CASE/acct2,$T/$CASE/acct2," ] \
    || fail "the build and fix of A's card did not both run on the account it started with: $(cat "$STUB/acct")"
  # Its reviewer is not Claude: it has no review account of its own, whatever the record names.
  [ "$(st 'select(.issue == 5 and .step == "worktree") | [.account, .reviewAccount] | tojson')" = '["second",null]' ] \
    && [ -n "$(st 'select(.issue == 5 and .step == "landed") | .sha')" ] || fail "the card's records do not name its accounts, or it did not land: $(st 'select(.issue == 5) | tostring')"
  jq -e 'select(.account == "second" and .pct == 50)' "$ST/limit.jsonl" >/dev/null || fail "the readings do not name the account: $(cat "$ST/limit.jsonl")"
  loop check || fail "the record check refuses a line naming its account"
  acctnomail
}
