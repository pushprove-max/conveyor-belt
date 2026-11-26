#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: one notice to a webhook for each card that waits for the owner (needsnotify(), lib/needsask.sh, which
# needsjob() calls after needsmain()). The webhook is the host file's notify.webhookEnv, the name of the variable that
# holds the address. Each case calls the engine function through fx_in (lib.sh), with a stub curl in the case's PATH.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

NNHOOK=https://hooks.example.com/services/T0/B0/secret-token

# nnhost <host file json>: the case's host file. The state folder does not depend on it.
nnhost() { mkdir -p "$XDG_CONFIG_HOME/conveyor" && echo "$1" > "$XDG_CONFIG_HOME/conveyor/host.json" || fail "the host file"; }
# nnsetup <issues json>: the host file that names the variable NNHOOK_URL, the ledger in the case's folder, and a stub curl that records each call: its arguments, its standard input and the
# body file it was given, and answers with the code in $STUB/curl.code (200 when there is none).
nnsetup() {
  setup "$1"; nnhost '{"notify":{"webhookEnv":"NNHOOK_URL"}}'; export CONVEYOR_LEDGER=$T/$CASE/decisions.jsonl NNHOOK_URL=$NNHOOK; mkdir -p "$ST"
  # stub: curl is the outside program; it records what the engine gave it and answers as the webhook does.
  cat > "$STUB/curl" <<'EOF'
#!/usr/bin/env bash
d=$(dirname "$0"); printf '%s\n' "$*" >> "$d/curl.args"; cat >> "$d/curl.stdin"
while [ $# -gt 0 ]; do [ "$1" != --data-binary ] || { cat "${2#@}" >> "$d/curl.body"; echo >> "$d/curl.body"; }; shift; done
cat "$d/curl.code" 2>/dev/null || printf 200
EOF
  chmod +x "$STUB/curl" || fail "the stub curl"
}
# nnblock <issue> <reason> [kept]: the blocked card c0-<issue>, with a kept patch when a third argument is given.
nnblock() {
  local k=''; [ $# -lt 3 ] || { k=kept/c0-$1; mkdir -p "$ST/$k" && echo kept > "$ST/$k/c0-$1.patch" || fail "the kept patch"; }
  landed "$1" | jq -c --arg k "$k" --arg r "$2" '(.step = "picked"), (.step = "blocked" | .result = "blocked" | .reason = $r | .kept = $k)' >> "$ST/cards.jsonl"
}
# nnrun <command>: the engine function, as the loop calls it; the output is in run.out.
nnrun() { fx_in "$1"; [ "$RC" = 0 ] || fail "'$1' exited $RC: $(cat "$T/$CASE/run.out")"; }
# nncalls: how many times the stub curl ran.
nncalls() { wc -l < "$STUB/curl.args" 2>/dev/null || echo 0; }

# Bug it catches: a card that waits for the owner showed on the Board and in the Foreman's wake only, so an owner away from
# both did not know. One pass sends one POST for a card blocked with its work kept (through needsjob(), where the call
# sits): the body is the text with the card, the issue and the first line of the reason, and the address is in no argument
# of curl. A second pass sends nothing, and the card's decision is put as it was.
t_notifyblocked() {
  nnsetup "[$(issue 7 2026-01-01)]"; nnblock 7 $'build: it failed\nthe end of its output' kept
  nnrun needsjob
  [ "$(nncalls)" = 1 ] || fail "the first pass ran curl $(nncalls) times, not once: $(cat "$STUB/curl.args" 2>&1) $(cat "$T/$CASE/run.out")"
  [ "$(jq -c . "$STUB/curl.body")" = '{"text":"Conveyor: card c0-7 (#7) waits for the owner: build: it failed"}' ] \
    || fail "the body is not the notice of card c0-7: $(cat "$STUB/curl.body")"
  grep -q -- "-X POST" "$STUB/curl.args" && grep -q -- "Content-Type: application/json" "$STUB/curl.args" || fail "curl was not told to POST JSON: $(cat "$STUB/curl.args")"
  ! grep -q "hooks.example.com\|secret-token" "$STUB/curl.args" || fail "the address is in curl's arguments, so in the process list: $(cat "$STUB/curl.args")"
  grep -q "$NNHOOK" "$STUB/curl.stdin" || fail "curl was not given the address on its standard input: $(cat "$STUB/curl.stdin")"
  nnrun needsjob
  [ "$(nncalls)" = 1 ] || fail "the second pass sent a second notice: $(cat "$STUB/curl.args")"
  jq -e 'select(.id == "blocked-c0-7" and .answeredAt == null)' "$CONVEYOR_LEDGER" > /dev/null || fail "decision blocked-c0-7 was not put: $(cat "$CONVEYOR_LEDGER" 2>&1)"
}

# Bug it catches: a card that stops for the owner's yes to a visible change has no decision (needsask() leaves it out),
# so the notice read decisions alone and never told the owner of this stop. The reason is cut to 200 characters.
t_notifyyes() {
  local r x; printf -v x 'x%.0s' {1..300}; r="visible to customers or staff: needs Dana's yes: $x"
  nnsetup "[$(issue 8 2026-01-01)]"; nnblock 8 "$r"
  nnrun needsnotify
  [ "$(nncalls)" = 1 ] || fail "the stop for the yes ran curl $(nncalls) times, not once: $(cat "$T/$CASE/run.out")"
  [ "$(jq -r .text "$STUB/curl.body")" = "Conveyor: card c0-8 (#8) waits for the owner: ${r:0:200}" ] || fail "the body is not the notice with the reason cut to 200: $(cat "$STUB/curl.body")"
}

# Bug it catches: the notice ran with no setting, or with a variable that is empty or no https address, and sent the
# decision's text to wherever the variable pointed (or ran curl for nothing).
t_notifyoff() {
  local v
  nnsetup "[$(issue 7 2026-01-01)]"; nnblock 7 'build: it failed' kept
  for v in '' 'http://hooks.example.com/x' 'https://a b'; do
    NNHOOK_URL=$v nnrun needsnotify
    [ "$(nncalls)" = 0 ] || fail "curl ran with the variable set to '$v': $(cat "$STUB/curl.args")"
  done
  nnhost '{}'; nnrun needsjob
  [ "$(nncalls)" = 0 ] || fail "curl ran with no notify.webhookEnv: $(cat "$STUB/curl.args")"
  jq -e 'select(.id == "blocked-c0-7")' "$CONVEYOR_LEDGER" > /dev/null || fail "with no notice, decision blocked-c0-7 was not put as before: $(cat "$CONVEYOR_LEDGER" 2>&1)"
}

# Bug it catches: the card was marked sent when the channel answered 500, so the owner never got the notice; or the
# log line of the failure held the address, which is a secret.
t_notifyfail() {
  nnsetup "[$(issue 7 2026-01-01)]"; nnblock 7 'build: it failed' kept
  printf 500 > "$STUB/curl.code"
  nnrun needsjob
  [ "$(nncalls)" = 1 ] && grep -q "not sent (HTTP 500)" "$T/$CASE/run.out" || fail "no log line for the 500 answer: $(cat "$T/$CASE/run.out")"
  ! grep -q "hooks.example.com\|secret-token" "$T/$CASE/run.out" || fail "the log holds the address: $(cat "$T/$CASE/run.out")"
  [ ! -s "$ST/notify/sent" ] || fail "the card was marked sent after a 500: $(cat "$ST/notify/sent")"
  printf 200 > "$STUB/curl.code"
  nnrun needsjob
  [ "$(nncalls)" = 2 ] && [ "$(cat "$ST/notify/sent")" = c0-7 ] || fail "the next pass did not send the notice again: $(cat "$STUB/curl.args") $(cat "$ST/notify/sent" 2>&1)"
}

# Bug it catches: a branch card (issue 0, from land-branch) that stops for the owner's yes was left out of the notice by
# a filter on the issue number, so the owner of a branch change was never told.
t_notifybranch() {
  nnsetup "[]"; nnblock 0 "visible to customers or staff: needs Dana's yes: a new button"
  nnrun needsnotify
  [ "$(nncalls)" = 1 ] && [ "$(jq -r .text "$STUB/curl.body")" = "Conveyor: card c0-0 (#0) waits for the owner: visible to customers or staff: needs Dana's yes: a new button" ] \
    || fail "no notice for the branch card: $(cat "$STUB/curl.body" 2>&1) $(cat "$T/$CASE/run.out")"
}

# Bug it catches: a notice sent for a block that does not wait for the owner: one with no decision and no yes to ask for, and
# one whose decision the owner answered. Both stay silent, and a card that landed after its block is not a card that waits.
t_notifynone() {
  nnsetup "[$(issue 7 2026-01-01), $(issue 9 2026-01-01), $(issue 10 2026-01-01)]"
  nnblock 7 'build: it failed'
  nnblock 9 'build: it failed' kept; nnblock 10 'build: it failed'; landed 10 >> "$ST/cards.jsonl"
  nnrun needsask
  bash "$SRC/../.claude/scripts/decision.sh" answer blocked-c0-9 'Leave it held' > "$T/$CASE/answer.out" 2>&1 || fail "the answer: $(cat "$T/$CASE/answer.out")"
  nnrun needsnotify
  [ "$(nncalls)" = 0 ] || fail "a notice was sent for a card that does not wait for the owner: $(cat "$STUB/curl.body")"
}
