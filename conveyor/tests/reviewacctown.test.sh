#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a card's review runs on its own review account, and never on one the guard did not read for it.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner. Two of its cases are of reviewacct.test.sh's four (the bugs are named
# there), and t_reviewacctcard names its own; all from what reviewacctsetup (reviewacct.test.sh) makes, in a file of
# their own so no file is over the CPU budget.
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
# Bugs: with a Codex reviewer for the project and the review account at its limit, a card whose issue has a Claude
# reviewer of its own (`control card`) started and reviewed on that account; a closed issue's own Claude reviewer
# paused the whole queue; an own reviewer set between the guard's reading and the pick (acctkey without cards) started
# the card on an account nobody read. #10 (oldest, so first in the queue) is given its reviewer during the loop's
# first reading; #8, closed, has one too. #10's card waits, and #9, on the project's Codex reviewer, is picked.
t_reviewacctcard() {
  reviewacctsetup "[$(issue 9 2026-01-05),$(issue 10 2026-01-04)]"
  ctl reviewer default >/dev/null; ctl review-account second >/dev/null; ctl card 8 reviewer claude-sonnet-5-5 >/dev/null
  printf '%s\n' 'case ${CLAUDE_CONFIG_DIR:-} in */acct2) cat "$STUB/limit2" ;;' \
    "  */acct1) [ ! -e \"\$STUB/switch\" ] || { rm \"\$STUB/switch\"; bash $(printf %q "$SRC/conveyor.sh") control card 10 reviewer claude-sonnet-5-5 >/dev/null; }; echo '{\"seven_day\":{\"utilization\":10}}' ;;" \
    "  *) echo '{\"seven_day\":{\"utilization\":10}}' ;; esac" > "$STUB/limitcmd"
  : > "$STUB/switch"; out=$(loop run 1 2>&1)
  [ ! -e "$STUB/switch" ] && [ "$(jq -c '.cards | keys' "$ST/control.json")" = '["10","8"]' ] || fail "#10's reviewer was not set during the reading: $out"
  [ "$(st 'select(.step == "picked") | .issue' | tr '\n' ,)" = 9, ] && ! grep -q 'paused by guard' <<<"$out" \
    && ! grep -q '^review ' "$STUB/acct" 2>/dev/null || fail "#10 was picked on its own Claude reviewer's account at its limit, or #9 was not: $out $(cat "$STUB/acct" 2>/dev/null)"
  # Bugs: only pick skipped #10, so the same-file check (upnext's first) judged #10 and never #9, and the Board's order
  # (upnext all, rule null) put #10 first, the loop then picking another; and pick logged that the next ready issue
  # was picked when none was. upnext itself must leave #10 out with its rule.
  printf '[%s,%s]\n' "$(issue 11 2026-01-05)" "$(issue 10 2026-01-04)" > "$STUB/up.json"
  fx_in "upnext \"\$(<$(printf %q "$STUB/up.json"))\" '' '' && upnext \"\$(<$(printf %q "$STUB/up.json"))\" '' all"
  [ "$RC" = 0 ] && [ "$(jq -cs '[.[0][].number, (.[1][] | {number, rule})]' "$T/$CASE/run.out")" = '[11,{"number":10,"rule":"the weekly limit guard"},{"number":11,"rule":null}]' ] \
    && ! grep -q 'next ready issue is picked' <<<"$out" || fail "upnext did not leave #10 out by the weekly limit guard: $(cat "$T/$CASE/run.out") $out"
  # The dry pick holds #10 as the loop does (#9 has its card now): the bug answered 10.
  printf '[%s]\n' "$(issue 10 2026-01-04)" > "$STUB/issues.json"
  out=$(loop pick --dry --issues "$STUB/issues.json" --state "$ST") && [ -z "$out" ] || fail "the dry pick took #10 on its own reviewer's account at its limit: $out"
}
