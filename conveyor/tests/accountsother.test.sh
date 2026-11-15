#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the guard of a project on the default login reads that login's own account, never another project's.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner. Its case is one of accounts.test.sh's four (the bugs are named there),
# from the two projects acctsetup (accounts.test.sh) makes, in a file of its own so no file is over the CPU budget.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Both projects guard at 90: A's account is at 95, so A picks nothing, read first; B's default login is at 10, so B's
# card starts.
t_accountsother() {
  acctsetup; ctl account second >/dev/null; ctl guard 90 >/dev/null; b ctl guard 90 >/dev/null
  out=$(loop run 1 2>&1); grep -q 'paused by guard' <<<"$out" || fail "A was not paused by its guard before B ran: $out"
  b loop run 1 >/dev/null 2>&1; [ "$(b st 'select(.step == "build") | .issue')" = 21 ] && [ "$(cat "$SB/acct")" = default ] \
    || fail "B's card did not start on the default login while A's account was at its limit: $(cat "$SB/acct" 2>/dev/null)"
  [ "$(b loop health | jq -r .guard.reading)" = 10 ] || fail "B's guard read A's account: $(b loop health | jq -c .guard)"
  # B's readings are of the default login's own folder, never of whichever folder's metadata was written last.
  [ "$(sort -u "$SB/limit-dirs")" = "$HOME/.claude" ] || fail "B's readings were not of the default login's folder: $(sort -u "$SB/limit-dirs")"
  acctnomail
}
