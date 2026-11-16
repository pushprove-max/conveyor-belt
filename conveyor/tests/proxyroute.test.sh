#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a Claude or Codex session whose subscription login fails runs again through the fallback API proxy,
# each role on its own route.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# The proxy's base URL the pack names (a TEST-NET address: the stub CLI never connects to it).
PXURL=http://192.0.2.1:4141
# One issue, 7, on a main whose builder runs on Claude (the stub). Its sessions log their route ("subscription", or
# the base URL and token they were given) in $STUB/routes. On the subscription the login has expired (as on the
# machine the bug was found on: "OAuth session expired and could not be refreshed", no turn, no token); through the
# proxy the session works, unless $STUB/proxybad is there, when the proxy refuses its key.
pxsetup() {
  setup "[$(issue 7 2026-01-01)]"; printf '%s\n' "$GO" > "$STUB/review.1"; tune '.tunables.apiPause = 0'
  unset ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY ENABLE_TOOL_SEARCH
  cat > "$STUB/build" <<'EOT'
case "$*" in *bypassPermissions*) ;; *) exit 1 ;; esac
if [ -z "${ANTHROPIC_BASE_URL:-}" ]; then
  echo subscription >> "$STUB/routes"
  echo '{"type":"result","is_error":true,"result":"OAuth session expired and could not be refreshed","num_turns":1,"usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}'; exit 1
fi
echo "$ANTHROPIC_BASE_URL ${ANTHROPIC_AUTH_TOKEN:-}" >> "$STUB/routes"
[ ! -e "$STUB/proxybad" ] || { echo '{"type":"result","is_error":true,"result":"Invalid API key · Please run /login","num_turns":1}'; exit 1; }
echo two >> a.txt
EOT
}

# Bug: on a fresh machine whose subscription login had expired, every card was blocked within a second, while a local
# API proxy ran beside it. With the proxy set as the fallback, the same build runs again at once through it, with the
# key from the variable it names, and the card lands; its build line, and the Board's timeline of it, say it ran
# through the proxy, and health shows the subscription expired and the proxy working.
t_proxyfallback() {
  pxsetup; tune --arg b "$PXURL" '.models.claudeProxy = {baseUrl: $b, keyEnv: "PROXY_KEY", roles: {builder: "fallback", reviewer: "fallback"}}'
  PROXY_KEY=px-secret loop run >/dev/null 2>&1
  [ "$(cat "$STUB/routes")" = "subscription"$'\n'"$PXURL px-secret" ] || fail "the build did not run again through the proxy, with its key: $(cat "$STUB/routes")"
  [ "$(st 'select(.issue == 7) | .step' | grep -c '^landed$')" = 1 ] || fail "the card did not land: $(st 'select(.issue == 7) | [.step, .reason] | join(" ")')"
  [ "$(st 'select(.issue == 7 and .step == "build") | .route')" = proxy ] || fail "the build line does not say it ran through the proxy: $(st 'select(.issue == 7 and .step == "build")')"
  [ "$(loop snapshot | jq -r '.landed[] | select(.issue == 7) | .metrics.timeline[] | select(.step == "build") | .route')" = proxy ] \
    || fail "the Board's timeline of the build does not say the proxy: $(loop snapshot | jq -c '.landed[] | select(.issue == 7) | .metrics.timeline')"
  [ "$(loop health | jq -c '.routes | [.subscription.state, .proxy.state, .proxy.baseUrl, .proxy.route]')" = "[\"expired\",\"works\",\"$PXURL\",\"fallback\"]" ] \
    || fail "health does not show the subscription expired and the proxy working: $(loop health | jq -c .routes)"
}
# With no proxy set, the build is blocked with the login as its cause, and runs nowhere else; health shows the proxy
# not set.
t_proxynone() {
  pxsetup
  loop run >/dev/null 2>&1
  [ "$(sort -u "$STUB/routes")" = subscription ] || fail "a build with no proxy set ran on another route: $(cat "$STUB/routes")"
  st 'select(.issue == 7 and .step == "blocked") | .reason' | grep -q '^build: the claude CLI is not logged in (exit 1): log it in (run claude, then /login)' \
    || fail "the build is not blocked with the login as its cause: $(st 'select(.issue == 7) | [.step, .reason] | join(" ")')"
  st 'select(.issue == 7 and .step == "blocked") | .tail' | grep -qxF 'OAuth session expired and could not be refreshed' || fail "the blocked line lost the CLI's words: $(st 'select(.issue == 7 and .step == "blocked") | .tail')"
  [ "$(loop health | jq -c '.routes | [.subscription.state, .proxy.state]')" = '["expired","not set"]' ] || fail "health does not show the proxy not set: $(loop health | jq -c .routes)"
}
# Both routes failing: the card is blocked naming the subscription's cause and the proxy's, with the words of each.
t_proxyboth() {
  pxsetup; tune --arg b "$PXURL" '.models.claudeProxy = {baseUrl: $b, roles: {builder: "fallback"}}'; touch "$STUB/proxybad"
  loop run >/dev/null 2>&1
  # A proxy named with no key variable is given a stand-in token, so the expired login is not tried again through it.
  [ "$(head -n 2 "$STUB/routes")" = "subscription"$'\n'"$PXURL no-key" ] || fail "the build did not run again through the proxy: $(cat "$STUB/routes")"
  b=$(st 'select(.issue == 7 and .step == "blocked")')
  jq -r .reason <<<"$b" | grep -q '^build: on the subscription login, the claude CLI is not logged in (exit 1): .*; through the proxy, the claude CLI is not logged in (exit 1): ' \
    || fail "the blocked line does not name both causes: $(jq -r .reason <<<"$b")"
  jq -r .tail <<<"$b" | grep -qxF 'OAuth session expired and could not be refreshed' && jq -r .tail <<<"$b" | grep -qxF 'Invalid API key · Please run /login' \
    || fail "the blocked line lost the words of one route: $(jq -r .tail <<<"$b")"
  [ "$(jq -r .spent.route <<<"$b")" = proxy ] || fail "the blocked line's spent does not say the last try ran through the proxy: $(jq -c .spent <<<"$b")"
  [ "$(loop health | jq -c '.routes | [.subscription.state, .proxy.state]')" = '["expired","fails"]' ] || fail "health does not show both routes failing: $(loop health | jq -c .routes)"
}
# Each role takes its own route: the builder set to the proxy runs through it at once; the Claude reviewer, set to the
# proxy as its fallback, runs on the subscription first, and when that login fails runs again through the proxy.
t_proxyreview() {
  pxsetup; tune --slurpfile real "$SRC/lib/test-pack.json" --arg b "$PXURL" '.models.allowed = $real[0].models.allowed | .models.allowed.claude += ["m"]
    | .models.claudeProxy = {baseUrl: $b, roles: {builder: "proxy", reviewer: "fallback"}}'
  loop control reviewer claude claude-opus-5-5 >/dev/null || fail "a Claude reviewer was not set"
  cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
case " $* " in *" --tools "*) ;; *) echo "${ANTHROPIC_BASE_URL:-subscription}" >> "$STUB/builds"; echo two >> a.txt
  echo '{"type":"result","is_error":false,"usage":{"input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":999,"output_tokens":5}}'; exit 0 ;; esac
echo "${ANTHROPIC_BASE_URL:-subscription} ${ANTHROPIC_AUTH_TOKEN:-}" >> "$STUB/reviews"
[ -n "${ANTHROPIC_BASE_URL:-}" ] || { echo '{"type":"result","is_error":true,"result":"OAuth session expired and could not be refreshed","num_turns":1}'; exit 1; }
jq -cn --arg r "$GO" '{type: "result", is_error: false, result: $r, num_turns: 2, usage: {input_tokens: 100, cache_creation_input_tokens: 50, cache_read_input_tokens: 1000, output_tokens: 7}}'
EOF
  export GO; loop run >/dev/null 2>&1
  [ "$(cat "$STUB/builds")" = "$PXURL" ] || fail "the builder, set to the proxy, did not run through it: $(cat "$STUB/builds")"
  [ "$(cat "$STUB/reviews")" = "subscription "$'\n'"$PXURL no-key" ] || fail "the review did not run again through the proxy: $(cat "$STUB/reviews")"
  [ "$(st 'select(.issue == 7 and (.step | IN("build", "review", "landed"))) | "\(.step) \(.route // "")"' | tr '\n' ,)" = 'build proxy,review proxy,landed ,' ] \
    || fail "the card did not land with its build and its review through the proxy: $(st 'select(.issue == 7) | [.step, .route, .reason] | join(" ")' | tr '\n' ,)"
}
# Bug: after a session worked through the proxy, the proxy stopped; the next session failed on the connection, which
# is no login cause, and Health still showed the proxy working. Any stop before work through the proxy shows it failing.
t_proxydown() {
  pxsetup; tune --arg b "$PXURL" '.models.claudeProxy = {baseUrl: $b, roles: {builder: "proxy", reviewer: "proxy"}}'
  mkdir -p "$ST" && echo '{"proxy": {"state": "works", "at": "2026-01-01T00:00:00Z"}}' > "$ST/routes.json"
  echo 'echo "API Error: Unable to connect to API (ECONNREFUSED)" >&2; exit 1' > "$STUB/build"
  loop run >/dev/null 2>&1
  [ "$(st 'select(.issue == 7) | .step' | tail -n 1)" = blocked ] || fail "the build did not stop: $(st 'select(.issue == 7) | [.step, .reason] | join(" ")')"
  [ "$(loop health | jq -r '.routes.proxy.state')" = fails ] || fail "health still shows a stopped proxy working: $(loop health | jq -c .routes)"
}
# Codex takes its route through its own provider settings: a Codex reviewer whose own login fails, with the host
# file's codexProxy as the reviewer's fallback, runs again at once given that proxy as its provider, and the card lands.
t_proxycodex() {
  mkdir -p "$XDG_CONFIG_HOME/conveyor" && jq -n --arg b "$PXURL/v1" '{codexProxy: {baseUrl: $b, keyEnv: "CODEX_PROXY_KEY", roles: {reviewer: "fallback"}}}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  setup "[$(issue 7 2026-01-01)]"; printf '%s\n' "$GO" > "$STUB/review.1"; tune '.tunables.apiPause = 0'
  cat > "$STUB/codex" <<'EOF'
#!/usr/bin/env bash
case ${1:-} in debug|login) exit 1 ;; esac
case "$*" in *'model_provider="conveyor-proxy"'*) echo "proxy $(grep -o 'base_url = "[^"]*"' <<<"$*")" >> "$STUB/reviews" ;; *) echo subscription >> "$STUB/reviews" ;; esac
while [ $# -gt 0 ]; do [ "$1" = -o ] && out=$2; shift; done
cat > /dev/null
[ "$(tail -n 1 "$STUB/reviews")" != subscription ] || { echo '{"type":"turn.failed","error":{"message":"401 Unauthorized: not logged in, run codex login"}}'; exit 1; }
cat "$STUB/review.1" > "$out"; echo '{"type":"turn.completed","usage":{"input_tokens":100,"cached_input_tokens":60,"output_tokens":7}}'
EOF
  loop run >/dev/null 2>&1
  [ "$(cat "$STUB/reviews")" = "subscription"$'\n'"proxy base_url = \"$PXURL/v1\"" ] || fail "the Codex review did not run again with the proxy as its provider: $(cat "$STUB/reviews")"
  [ "$(st 'select(.issue == 7 and (.step | IN("review", "landed"))) | "\(.step) \(.route // "")"' | tr '\n' ,)" = 'review proxy,landed ,' ] \
    || fail "the card did not land with its review through the proxy: $(st 'select(.issue == 7) | [.step, .route, .reason] | join(" ")' | tr '\n' ,)"
}
