#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the folder an account's sessions and its guard use (a relative one, and the default login's).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bugs: a relative account folder is read by the guard under the engine's folder but by the session under the card's
# worktree (the session changes into it first), so the guard watches another account than the cards run on; a project
# on the default login runs and reads the CLAUDE_CONFIG_DIR the engine inherited, which the Board does not mark as the
# default, so its cards' use shows under another account.
# Two cases (t_acctpaths, t_acctpathsrel), one card each, so they run side by side; t_acctguard429, below, runs no card.
acctpathsetup() {
  export CLAUDE_CONFIG_DIR=$T/$CASE/inherited
  export XDG_CONFIG_HOME=$T/$CASE/config; mkdir -p "$XDG_CONFIG_HOME/conveyor"
  jq -cn '{accounts: [{name: "second", configDir: "profiles/second"}, {name: "default", configDir: "profiles/named"}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  setup "$(jq -cs . <(issue 5 2026-01-01) <(issue 6 2026-01-02))"
  export HOME=$T/$CASE/home; mkdir -p "$HOME/profiles/second"
  # The build says the folder it ran with and changes nothing: the card ends after it (blocked: no change to review).
  echo 'echo "${CLAUDE_CONFIG_DIR:-default}" >> "$STUB/acct"' > "$STUB/build"
  echo 'echo "${CLAUDE_CONFIG_DIR:-none}" >> "$STUB/limit-dirs"; echo "{\"seven_day\":{\"utilization\":10}}"' > "$STUB/limitcmd"
  tune '.tunables.limitTtl = 0'; export CONVEYOR_LIMIT_CMD='. "$STUB/limitcmd"'
  loop control guard 90 >/dev/null 2>&1
}
t_acctpaths() {
  acctpathsetup
  # An account the host file names default is chosen by its name like any other, for builds and for reviews: no word
  # stands for "none" (that is no name), so it is never written as none and run on ~/.claude instead.
  [ "$(loop control account default 2>&1 | jq -r .account)" = default ] && [ "$(loop control review-account default 2>&1 | jq -r .reviewAccount)" = default ] \
    && [ "$(loop control account 2>/dev/null | jq -c .account)" = null ] && [ "$(loop control review-account 2>/dev/null | jq -c '[.account, .reviewAccount]')" = '[null,null]' ] \
    || fail "a listed account named default was not chosen by its name, or no name did not clear it: $(cat "$ST/control.json")"
  # The default login: the session runs with no CLAUDE_CONFIG_DIR (Claude's own ~/.claude), the guard reads ~/.claude.
  loop run --only 5 >/dev/null 2>&1
  [ "$(cat "$STUB/acct")" = default ] && [ "$(sort -u "$STUB/limit-dirs")" = "$HOME/.claude" ] \
    || fail "a card on the default login ran or was guarded on the inherited folder: $(cat "$STUB/acct" "$STUB/limit-dirs" 2>/dev/null)"
}
# Issue 1087: the guard read an account's usage with no regard for the wait a 429 named, every limitTtl, so the endpoint
# kept refusing the account and the Board, which waited the wait out, never had a reading for days. The guard's own
# read (the engine's LIMIT_CMD, not a stub of it) against a stubbed endpoint: a 429 is waited out, and its deadline is
# kept in the machine's one folder of account reads, where the Board's reads look.
t_acctguard429() {
  setup "$(jq -cs . <(issue 5 2026-01-01))"
  unset CLAUDE_CONFIG_DIR CONVEYOR_LIMIT_CMD XDG_CACHE_HOME
  export HOME=$T/$CASE/home CONVEYOR_HOST_OS=Linux PYTHONPATH=$SRC/../.claude/scripts/__tests__/usage-stub \
    USAGE_STUB_LOG=$T/$CASE/asked USAGE_STUB_ANSWER=$T/$CASE/answer
  mkdir -p "$HOME/.claude"; printf '{"claudeAiOauth":{"accessToken":"tok"}}' > "$HOME/.claude/.credentials.json"
  tune '.tunables.limitTtl = 0'; loop control guard 90 >/dev/null 2>&1
  echo '429 3600' > "$USAGE_STUB_ANSWER"
  [ "$(loop health | jq -c .guard.reading)" = null ] && [ "$(wc -l < "$USAGE_STUB_LOG")" -eq 1 ] \
    || fail "the guard's first read was not asked once: $(cat "$USAGE_STUB_LOG" 2>&1)"
  grep -qF 'rate limited (429); retry after 3600 s' "$HOME"/.cache/conveyor/accounts/account-*.json \
    || fail "the guard's 429 is not kept in the machine's account folder: $(ls -R "$HOME/.cache" 2>&1)"
  echo '45' > "$USAGE_STUB_ANSWER"
  loop health >/dev/null
  [ "$(wc -l < "$USAGE_STUB_LOG")" -eq 1 ] || fail "the guard asked the account again inside the wait its 429 named"
}
t_acctpathsrel() {
  acctpathsetup
  # The relative folder is the home folder's, for the guard and the session alike.
  loop control account second >/dev/null 2>&1
  loop run --only 6 >/dev/null 2>&1
  [ "$(cat "$STUB/acct")" = "$HOME/profiles/second" ] && [ "$(sort -u "$STUB/limit-dirs")" = "$HOME/profiles/second" ] \
    && [ -n "$(st 'select(.issue == 6 and .step == "build") | .card')" ] \
    || fail "the guard and the session did not read the same folder under the home folder: $(cat "$STUB/acct" "$STUB/limit-dirs") $(st 'select(.issue == 6) | tostring')"
}
