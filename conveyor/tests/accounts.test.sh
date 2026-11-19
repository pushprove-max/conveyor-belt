#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the Claude accounts a project's cards run on.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bugs: a project set to an account runs its sessions on another account's folder (the default login, or the one
# the record names after the card started); the guard reads one account for every project, so an account at its
# limit holds back cards that use another, or lets through those that use it; a name the host file does not list is
# taken; the card's records do not name the account, or carry its email; the email reaches a GitHub write.
# Four cases, so they run side by side, each from the two projects acctsetup makes: two here (t_accounts,
# t_accountsnext), t_accountsother in accountsother.test.sh and t_accountsflight in accountsflight.test.sh, so no file
# is over the CPU budget.
acctsetup() {
  unset CLAUDE_CONFIG_DIR
  # The host file of this case alone (cases run side by side): two accounts, each a config folder signed in, the
  # second's metadata naming its email.
  export XDG_CONFIG_HOME=$T/$CASE/config; mkdir -p "$XDG_CONFIG_HOME/conveyor" "$T/$CASE/acct1" "$T/$CASE/acct2"
  mail=owner2${AT}example.com
  jq -cn --arg e "$mail" '{oauthAccount: {emailAddress: $e}}' > "$T/$CASE/acct2/.claude.json"
  jq -cn --arg a "$T/$CASE/acct1" --arg b "$T/$CASE/acct2" '{accounts: [{name: "first", configDir: $a}, {name: "second", configDir: $b}]}' \
    > "$XDG_CONFIG_HOME/conveyor/host.json"
  # Project B, on the host's default login, then project A.
  setup "$(jq -cs . <(issue 21 2026-01-01))"; RB=$R STB=$ST SB=$STUB
  CASE=${CASE}a setup "$(jq -cs . <(issue 5 2026-01-01) <(issue 6 2026-01-02))"
  b() { R=$RB ST=$STB STUB=$SB CASE=${CASE}b "$@"; }
  ctl() { loop control "$@" 2>&1; }
  # A usage response as dashboard_limit.py fetch gives it: it carries the account's email.
  resp() { jq -cn --argjson p "$1" --arg e "$mail" '{seven_day: {utilization: $p}, account: {folder: "x", email: $e}}'; }
  for s in "$STUB" "$SB"; do
    printf '%s\n' "$GO" > "$s/review.1"
    # Each session says the config folder it ran with; the limit reading is the folder's (each reading says which it
    # read): the second account is at 95 %. The build changes nothing, so the card ends after it (blocked: no change
    # to review): the cases read the folder its build ran on, not what lands.
    echo 'echo "${CLAUDE_CONFIG_DIR:-default}" >> "$STUB/acct"' > "$s/build"
    echo 'echo "${CLAUDE_CONFIG_DIR:-none}" >> "$STUB/limit-dirs"; case ${CLAUDE_CONFIG_DIR:-} in */acct2) cat "$STUB/limit2" ;; *) cat "$STUB/limit1" ;; esac' > "$s/limitcmd"
    resp 10 > "$s/limit1"; resp 95 > "$s/limit2"
  done
  tune '.tunables.limitTtl = 0'; b tune '.tunables.limitTtl = 0'
  export CONVEYOR_LIMIT_CMD='. "$STUB/limitcmd"'
}
# The email every usage response carried is in no record and in no GitHub write. The kept snapshot (snapshot.json,
# commands/snapshot.sh) is left out: it is the snapshot's own output, whose limits give the Board each account's login
# on this machine (t_accounts checks that), not a record.
acctnomail() {
  local f found writes=()
  for f in "$STUB"/comments "$STUB"/close-comments "$STUB"/filed "$SB"/comments "$SB"/close-comments "$SB"/filed; do
    [ -e "$f" ] && writes+=("$f")
  done
  found=$(grep -rlF --exclude=snapshot.json "$mail" "$ST" "$STB" "${writes[@]}")
  [ -z "$found" ] || fail "the account's email reached the records or a GitHub write: $found"
}
t_accounts() {
  acctsetup
  # Only a name the host file lists is taken (default is a name like any other: no word stands for none); no name
  # clears it.
  out=$(ctl account nosuch); [ $? = 2 ] && grep -q 'nosuch is not one of the accounts' <<<"$out" && [ "$(jq -r '.account // "none"' "$ST/control.json")" = none ] \
    || fail "an account the host file does not list was taken: $out"
  [ "$(ctl account second | jq -r .account)" = second ] && { ctl account default >/dev/null; [ $? = 2 ]; } && [ "$(jq -r .account "$ST/control.json")" = second ] \
    && [ "$(ctl account | jq .account)" = null ] && [ "$(ctl account second | jq -r .account)" = second ] \
    && [ "$(ctl review-account first | jq -r .reviewAccount)" = first ] || fail "the account was not set: $(cat "$ST/control.json")"
  [ "$(loop snapshot --fresh | jq -c '[.accounts, .control.account]')" = '[["first","second"],"second"]' ] || fail "the snapshot does not name the accounts: $(loop snapshot --fresh | jq -c .accounts)"
  # A guards at 90 and its account is at 95: A picks nothing (t_accountsother: B's card starts all the same).
  # A Claude reviewer, so the review runs on the first account and the guard reads it too.
  ctl guard 90 >/dev/null; ctl reviewer claude claude-opus-5-5 >/dev/null || fail "the reviewer was not set to Claude"
  out=$(loop run 1 2>&1); grep -q 'paused by guard' <<<"$out" && [ -z "$(st 'select(.step == "picked") | .issue')" ] || fail "A picked with its account at its limit: $out"
  [ "$(loop health | jq -c '[.state, .guard.reading]')" = '["paused by guard",95]' ] || fail "A's health does not read its own account: $(loop health | jq -c .guard)"
  # #623: the snapshot gives the Board each account's own reading and its login on this machine, so the Board's limit
  # panel shows the accounts the cards run on, not the Board machine's login.
  [ "$(loop snapshot --fresh | jq -c '.limits | map(.readAt |= type)')" = "$(jq -cn --arg e "$mail" '[{account: "first", uses: ["review"], pct: 10, readAt: "string", email: null},
      {account: "second", uses: ["build"], pct: 95, readAt: "string", email: $e}]')" ] \
    || fail "the snapshot does not give each account's reading: $(loop snapshot --fresh | jq -c .limits)"
  acctnomail
}
# The next card after that change (here, the record moved from the second account to the first before it starts) runs
# on the account the record names when it starts.
t_accountsnext() {
  acctsetup; ctl account second >/dev/null; ctl guard 90 >/dev/null; resp 50 > "$STUB/limit2"; ctl account first >/dev/null
  loop run --only 6 >/dev/null 2>&1
  [ "$(cat "$STUB/acct")" = "$T/$CASE/acct1" ] || fail "the next card did not take the changed account: $(cat "$STUB/acct")"
  acctnomail
}
