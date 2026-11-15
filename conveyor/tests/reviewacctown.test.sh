#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a card's review runs on its own review account, and never on one the guard did not read for it.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner. Its cases are two of reviewacct.test.sh's four (the bugs are named there),
# from what reviewacctsetup (reviewacct.test.sh) makes, in a file of their own so no file is over the CPU budget.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

t_reviewacctown() {
  reviewacctsetup "[$(issue 5 2026-01-01)]"; ctl review-account second >/dev/null
  # Under the limit: the build runs on the first account's folder, the review on the second's.
  echo '{"seven_day":{"utilization":50}}' > "$STUB/limit2"; printf '%s\n' "$GO" > "$STUB/review.1"
  loop run --only 5 >/dev/null 2>&1
  [ "$(tr '\n' , < "$STUB/acct")" = "build $T/$CASE/acct1,review $T/$CASE/acct2," ] && [ -n "$(st 'select(.issue == 5 and .step == "landed") | .sha')" ] \
    || fail "the build and the review did not run on their own accounts: $(cat "$STUB/acct") $(st 'select(.issue == 5) | tostring')"
}
t_reviewacctcodex() {
  reviewacctsetup "[$(issue 7 2026-01-03)]"
  # A Codex reviewer, the review account at 95: the guard does not read it (no review would use it), so the card
  # starts. Its reviewer is changed to Claude while it builds: its review runs on the account it builds on, which the
  # guard read, never on the review account at its limit.
  ctl reviewer default >/dev/null; ctl review-account second >/dev/null; echo '{"seven_day":{"utilization":95}}' > "$STUB/limit2"
  printf '%s\n' "$GO" > "$STUB/review.1"; : > "$STUB/hold"
  loop run 1 >/dev/null 2>&1 & run=$!
  for i in $(seq 300); do [ -n "$(st 'select(.issue == 7 and .step == "worktree") | .card')" ] && break; sleep 0.1; done
  [ "$(st 'select(.issue == 7 and .step == "worktree") | [.account, .reviewAccount] | tojson')" = '["first",null]' ] \
    || fail "a card with a Codex reviewer did not start, or was given a review account: $(st 'select(.issue == 7) | tostring')"
  ctl reviewer claude claude-opus-5-5 >/dev/null; : > "$STUB/go"; wait $run
  [ "$(tr '\n' , < "$STUB/acct")" = "build $T/$CASE/acct1,review $T/$CASE/acct1," ] && [ -n "$(st 'select(.issue == 7 and .step == "landed") | .sha')" ] \
    || fail "a card whose reviewer became Claude while it ran reviewed on an account the guard never read: $(cat "$STUB/acct") $(st 'select(.issue == 7) | tostring')"
}
