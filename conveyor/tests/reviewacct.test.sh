#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the Claude account a card's review runs on, and the guard's reading of it.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bugs: a Claude review runs on another folder than the record's reviewAccount, or with none the builder's account;
# the guard reads the builder's account alone, so a card starts while its review account is at its limit; an account
# changed between the guard's reading and the pick starts the card on the new account, whose limit was never read;
# a card started with a Codex reviewer, its reviewer changed to Claude while it builds, reviews on the record's review
# account, which the guard never read for it and which is at its limit.
# Four cases, so they run side by side, each from what reviewacctsetup makes: a Claude reviewer, the guard at 90, the
# builder's account the first. Two here (t_reviewacct, t_reviewacctbuilder) and two in reviewacctown.test.sh
# (t_reviewacctown, t_reviewacctcodex), so no file is over the CPU budget.
reviewacctsetup() { # <issues json>
  unset CLAUDE_CONFIG_DIR
  export XDG_CONFIG_HOME=$T/$CASE/config; mkdir -p "$XDG_CONFIG_HOME/conveyor" "$T/$CASE/acct1" "$T/$CASE/acct2"
  jq -cn --arg a "$T/$CASE/acct1" --arg b "$T/$CASE/acct2" '{accounts: [{name: "first", configDir: $a}, {name: "second", configDir: $b}]}' \
    > "$XDG_CONFIG_HOME/conveyor/host.json"
  setup "$1"
  tune --slurpfile real "$SRC/lib/test-pack.json" '.models.allowed = $real[0].models.allowed | .models.allowed.claude += ["m"] | .tunables += {limitTtl: 0, poll: 1}'
  ctl() { loop control "$@" 2>&1; }
  [ "$(ctl reviewer claude claude-opus-5-5 | jq -r .reviewer.model)" = claude-opus-5-5 ] || fail "a Claude reviewer was not set"
  # Each session, build or review (the one given --tools), says the config folder it ran with.
  cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
case " $* " in *" --tools "*) echo "review ${CLAUDE_CONFIG_DIR:-default}" >> "$STUB/acct"; echo x >> "$STUB/reviews"
  echo '{"type":"assistant","message":{"id":"m1","model":"claude-opus-5-5","content":[],"usage":{"input_tokens":1,"output_tokens":1}}}'
  jq -cn --rawfile r "$STUB/review.$(wc -l < "$STUB/reviews")" '{type: "result", is_error: false, result: $r, num_turns: 1,
    usage: {input_tokens: 1, cache_creation_input_tokens: 0, cache_read_input_tokens: 0, output_tokens: 1}}'; exit 0 ;; esac
[ ! -e "$STUB/hold" ] || for i in $(seq 600); do [ -e "$STUB/go" ] && break; sleep 0.1; done
echo "build ${CLAUDE_CONFIG_DIR:-default}" >> "$STUB/acct"; echo two >> a.txt
echo '{"type":"result","is_error":false,"usage":{"input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":999,"output_tokens":5}}'
EOF
  # The second account is at 95 %, the rest at 10 %. With $STUB/switch, the first reading of the first account
  # moves the record to the second, as the owner would between the loop's reading and its pick.
  printf '%s\n' 'case ${CLAUDE_CONFIG_DIR:-} in */acct2) cat "$STUB/limit2" ;;' \
    "  */acct1) [ ! -e \"\$STUB/switch\" ] || { rm \"\$STUB/switch\"; bash $(printf %q "$SRC/conveyor.sh") control account second >/dev/null; }; echo '{\"seven_day\":{\"utilization\":10}}' ;;" \
    "  *) echo '{\"seven_day\":{\"utilization\":10}}' ;; esac" > "$STUB/limitcmd"
  echo '{"seven_day":{"utilization":95}}' > "$STUB/limit2"
  export CONVEYOR_LIMIT_CMD='. "$STUB/limitcmd"'
  ctl guard 90 >/dev/null; ctl account first >/dev/null
}
t_reviewacct() {
  reviewacctsetup "$(jq -cs . <(issue 5 2026-01-01) <(issue 6 2026-01-02))"
  # The record moves to the second account after the loop read the first: nothing starts on the second.
  : > "$STUB/switch"; out=$(loop run 1 2>&1)
  [ ! -e "$STUB/switch" ] && [ "$(jq -r .account "$ST/control.json")" = second ] || fail "the record was not switched during the reading: $out"
  grep -q 'paused by guard' <<<"$out" && [ -z "$(st 'select(.step == "picked") | .issue')" ] && [ ! -e "$STUB/acct" ] \
    || fail "a card started on an account switched to after the guard's reading: $out $(cat "$STUB/acct" 2>/dev/null)"
  # The builder's account at 10, the review's at 95: the card would review on an account at its limit, so none starts.
  ctl account first >/dev/null; ctl review-account second >/dev/null
  out=$(loop run 1 2>&1); grep -q 'paused by guard' <<<"$out" && [ -z "$(st 'select(.step == "picked") | .issue')" ] \
    || fail "A picked with its review account at its limit: $out"
  [ "$(loop health | jq -c '[.state, .guard.reading]')" = '["paused by guard",95]' ] || fail "health does not read the review account: $(loop health | jq -c .guard)"
}
t_reviewacctbuilder() {
  reviewacctsetup "[$(issue 6 2026-01-02)]"
  # No review account: the review runs on the builder's.
  ctl review-account >/dev/null; printf '%s\n' "$GO" > "$STUB/review.1"
  loop run --only 6 >/dev/null 2>&1
  [ "$(tr '\n' , < "$STUB/acct")" = "build $T/$CASE/acct1,review $T/$CASE/acct1," ] || fail "a review with no account of its own did not run on the builder's: $(cat "$STUB/acct")"
}
