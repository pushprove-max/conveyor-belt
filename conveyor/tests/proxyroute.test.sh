#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a Claude or Codex session whose subscription login fails runs again through the fallback API proxy,
# each role on its own route; with no route left, the loop pauses until it is resumed.
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
  # Issue 135: a sign-in failure the fallback route got past does not pause the loop.
  [ "$(jq -c '[.mode, .signin]' "$ST/control.json")" = '["run",null]' ] || fail "a sign-in failure with a working fallback paused the loop: $(cat "$ST/control.json")"
  [ "$(st 'select(.issue == 7 and .step == "build") | .route')" = proxy ] || fail "the build line does not say it ran through the proxy: $(st 'select(.issue == 7 and .step == "build")')"
  [ "$(loop snapshot --fresh | jq -r '.landed[] | select(.issue == 7) | .metrics.timeline[] | select(.step == "build") | .route')" = proxy ] \
    || fail "the Board's timeline of the build does not say the proxy: $(loop snapshot --fresh | jq -c '.landed[] | select(.issue == 7) | .metrics.timeline')"
  [ "$(loop health | jq -c '.routes | [.subscription.state, .proxy.state, .proxy.baseUrl, .proxy.route]')" = "[\"expired\",\"works\",\"$PXURL\",\"fallback\"]" ] \
    || fail "health does not show the subscription expired and the proxy working: $(loop health | jq -c .routes)"
}
# With no proxy set, the build is blocked with the login as its cause, and runs nowhere else; health shows the proxy
# not set.
t_proxynone() {
  pxsetup
  loop run >/dev/null 2>&1
  [ "$(sort -u "$STUB/routes")" = subscription ] || fail "a build with no proxy set ran on another route: $(cat "$STUB/routes")"
  st 'select(.issue == 7 and .step == "blocked") | .reason' | grep -qF "build: Claude Code's own sign-in expired (exit 1): run claude /login (or set up the proxy route), then conveyor.sh control resume" \
    || fail "the build is not blocked with the login as its cause: $(st 'select(.issue == 7) | [.step, .reason] | join(" ")')"
  st 'select(.issue == 7 and .step == "blocked") | .tail' | grep -qxF 'OAuth session expired and could not be refreshed' || fail "the blocked line lost the CLI's words: $(st 'select(.issue == 7 and .step == "blocked") | .tail')"
  [ "$(loop health | jq -c '.routes | [.subscription.state, .proxy.state]')" = '["expired","not set"]' ] || fail "health does not show the proxy not set: $(loop health | jq -c .routes)"
}
# Issue 135. Bug: an expired Claude sign-in blocked 19 cards in five minutes: each build failed in a second with
# authentication_failed, and the loop kept picking. The first such failure, with no fallback route, pauses the loop
# with the reason and what to run (health's reason: the Board, the snapshot /units reads and foreman status show it),
# no second card is picked, and a resume puts the card back.
t_signinpause() {
  setup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"; tune '.tunables.apiPause = 0'
  loop control cap 1 >/dev/null || fail "the cap was not set"
  # The field report's own last line.
  cat > "$STUB/build" <<'EOT'
case "$*" in *bypassPermissions*) ;; *) exit 1 ;; esac
echo '{"type":"result","subtype":"success","is_error":true,"error":"authentication_failed","result":"Failed to authenticate: OAuth session expired and could not be refreshed","num_turns":1,"usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}'; exit 1
EOT
  loop run >/dev/null 2>&1
  local why="build: Claude Code's own sign-in expired; run claude /login (or set up the proxy route), then conveyor.sh control resume" out
  [ "$(st 'select(.issue == 7 and .step == "blocked") | .reason')" = "build: Claude Code's own sign-in expired (exit 1): run claude /login (or set up the proxy route), then conveyor.sh control resume. The card is put back once by itself on resume" ] \
    || fail "the card is not blocked naming the sign-in and what to run: $(st 'select(.issue == 7) | [.step, .reason] | join(" ")')"
  [ "$(jq -c '[.mode, .signin]' "$ST/control.json")" = "$(jq -cn --arg w "$why" '["pause", $w]')" ] || fail "the loop did not pause itself with the reason: $(cat "$ST/control.json")"
  [ "$(loop health | jq -c '[.state, .reason]')" = "$(jq -cn --arg w "$why" '["paused", $w]')" ] || fail "health does not say paused with the reason: $(loop health | jq -c '[.state, .reason]')"
  [ -z "$(st 'select(.issue == 8)')" ] || fail "a second card was picked after the sign-in failure: $(st 'select(.issue == 8) | .step' | tr '\n' ,)"
  # Resumed: the record runs again, still prints as one record, and the blocked card is put back.
  out=$(loop control resume 2>/dev/null) && jq -e '.mode == "run" and .signin == null' <<<"$out" >/dev/null || fail "control resume did not resume: $out"
  [ "$(jq -r 'select(.step == "blocked") | .issue' "$ST/retried.jsonl" 2>/dev/null)" = 7 ] && [ -z "$(st 'select(.issue == 7)')" ] \
    || fail "the resume did not put the blocked card back: $(cat "$ST/retried.jsonl" 2>&1)"
}
# Both routes failing: the card is blocked naming the subscription's cause and the proxy's, with the words of each.
t_proxyboth() {
  pxsetup; tune --arg b "$PXURL" '.models.claudeProxy = {baseUrl: $b, roles: {builder: "fallback"}}'; touch "$STUB/proxybad"
  loop run >/dev/null 2>&1
  # A proxy named with no key variable is given a stand-in token, so the expired login is not tried again through it.
  [ "$(head -n 2 "$STUB/routes")" = "subscription"$'\n'"$PXURL no-key" ] || fail "the build did not run again through the proxy: $(cat "$STUB/routes")"
  b=$(st 'select(.issue == 7 and .step == "blocked")')
  # Issue 184: the proxy's refusal names the proxy at its base URL, never a sign-in to it.
  jq -r .reason <<<"$b" | grep -q "^build: on the subscription login, Claude Code's own sign-in expired (exit 1): .*; through the proxy, the proxy at $PXURL refused the call (exit 1): check the proxy and the key it is sent (conveyor.sh doctor makes one call through it), then " \
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

# Issue 184. Bug: with a proxy route that needs no key (no key variable, none found), a session and a route check
# were given no token, so Claude Code sent the proxy the machine's own login, which had expired, and every call failed.
# A fixture proxy refuses a request with no Bearer token or with a CLI's own login (login-...) and takes any other
# Bearer token; the stub CLIs send the token they are given, else their own login. A Claude session (proxyenv()), a
# Codex session (codexargs()) and a route check of each (routecall(), as doctor and setup make it) all reach it.
t_pxnokey() {
  local d=$T/$CASE out; mkdir -p "$d" "$XDG_CONFIG_HOME/conveyor"
  cat > "$d/proxy.py" <<'PY'
import http.server, os, sys
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers.get("content-length") or 0))
        t = (self.headers.get("Authorization") or "").partition("Bearer ")[2]
        self.send_response(401 if t == "" or t.startswith("login-") else 200); self.end_headers()
    def log_message(self, *a): pass
s = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
open(sys.argv[1] + "/port.new", "w").write(str(s.server_address[1])); os.rename(sys.argv[1] + "/port.new", sys.argv[1] + "/port")
s.serve_forever()
PY
  python3 -I "$d/proxy.py" "$d" & PXSRV=$!; trap 'kill $PXSRV 2>/dev/null' EXIT
  until [ -s "$d/port" ] || ! kill -0 $PXSRV 2>/dev/null; do sleep 0.1; done
  local b; b=http://127.0.0.1:$(cat "$d/port") || fail "the fixture proxy did not start"
  jq -n --arg b "$b" '{claudeProxy: {kind: "proxy", baseUrl: $b, roles: {builder: "proxy", reviewer: "proxy"}},
    codexProxy: {kind: "proxy", baseUrl: "\($b)/v1", roles: {builder: "proxy", reviewer: "proxy"}}}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  setup '[]'
  unset ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY
  cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
[ "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer ${ANTHROPIC_AUTH_TOKEN:-login-claude}" -d '{}' "$ANTHROPIC_BASE_URL/v1/messages")" = 200 ] && { echo OK; exit 0; }
echo "OAuth session expired and could not be refreshed"; exit 1
EOF
  cat > "$STUB/codex" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
b=$(grep -o 'base_url = "[^"]*"' <<<"$*" | cut -d '"' -f 2); k=$(grep -o 'env_key = "[^"]*"' <<<"$*" | cut -d '"' -f 2)
t=login-codex; [ -z "$k" ] || t=${!k:-}
[ "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $t" -d '{}' "$b/responses")" = 200 ] && { echo OK; exit 0; }
echo "401 Unauthorized"; exit 1
EOF
  chmod +x "$STUB/claude" "$STUB/codex"
  # A Codex that, as the real one does, prints its banner before it sends the call, and that a proxy refuses for a
  # key (bug: the route check kept only the banner, so doctor did not see the 401 and printed no missing: line), after
  # its retry line, which has no status (bug: the check kept that line, and doctor again printed no missing: line).
  mkdir -p "$d/refuse"; printf '#!/usr/bin/env bash\ncat > /dev/null; echo "OpenAI Codex v0.169.0"; echo "--------"; echo "ERROR: Reconnecting... 1/5"; echo "ERROR: unexpected status 401 Unauthorized"; exit 1\n' > "$d/refuse/codex"; chmod +x "$d/refuse/codex"
  out=$( ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$d/cards; . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" || exit 1
    echo "claude session: $(PROXY_ROLE=builder proxyenv &&claude -p < /dev/null)"
    echo "codex session: $(PROXY_ROLE=reviewer codexargs &&codex exec "${CODEX_PX[@]}" - < /dev/null)"
    echo "claude check: $(routecall claude "" "$(claudeproxy)" "" 2>/dev/null)"
    echo "codex check: $(routecall codex "" "$(codexproxyset)" "" 2>/dev/null)"
    echo '{"type":"result","is_error":true,"result":"OAuth session expired and could not be refreshed"}' > "$d/s.out"
    PROXY_ROLE=builder nostart 1 '{}' "$d/s.out" /dev/null claude m builder "" "$d/cards/x"; echo "why: ${NOSTART_WHY%%$'\n'*}"
    PATH=$d/refuse:$PATH routecheck codex "" route "$(codexproxyset)" 2>/dev/null; echo " rc=$?" ) 2>&1 )
  [ "$(sed -n 1,4p <<<"$out")" = $'claude session: OK\ncodex session: OK\nclaude check: works\ncodex check: works' ] \
    || fail "a session or route check through a proxy that needs no key did not reach it with a stand-in token: $out"
  # A session through the proxy whose answer says an OAuth login expired: the reason names the proxy at its base URL
  # and says the login is Claude Code's own, with the command that signs it in, never a sign-in to the proxy.
  [ "$(sed -n 5p <<<"$out")" = "why: the proxy at $b refused the call: its answer says Claude Code's own sign-in expired (exit 1): run claude /login, or check the proxy and the key it is sent (conveyor.sh doctor makes one call through it), then conveyor.sh control resume" ] \
    || fail "the reason of an expired login through the proxy does not name the proxy and Claude Code's own login: $out"
  grep -qF "and one call through it with none fails (ERROR: unexpected status 401 Unauthorized)" <<<"$out" \
    && grep -qxF "missing: a key the service can find for the codex route through $b/v1; fix: put it in the variable that keyEnv names in the env of $CONVEYOR_CLAUDE_SETTINGS, or name a key file of mode 600 as keyFile of codexProxy in $XDG_CONFIG_HOME/conveyor/host.json rc=1" <<<"$out" \
    || fail "doctor's check of a Codex proxy that refuses a call with no key did not say the key is missing: $out"
}

# The one-answer calls (the judge, askmodel(), a test action, a check session), each called alone in the engine shell
# as `conveyor.sh run` makes it, with no card run. claude logs each call's route in $STUB/routes; on the subscription
# its login has expired, through the proxy it answers. Both roles take the proxy as their fallback.
pxone() { # <the engine command>
  setup "[$(issue 7 2026-01-01)]"; tune --arg b "$PXURL" '.models.claudeProxy = {baseUrl: $b, roles: {builder: "fallback", reviewer: "fallback"}}'
  unset ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY ENABLE_TOOL_SEARCH
  cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null; echo "${ANTHROPIC_BASE_URL:-subscription}" >> "$STUB/routes"
[ -n "${ANTHROPIC_BASE_URL:-}" ] || { echo '{"type":"result","is_error":true,"result":"OAuth session expired and could not be refreshed","num_turns":1}'; exit 1; }
echo '{"type":"result","is_error":false,"result":"F1 DECLINE: wrong","num_turns":1,"usage":{"input_tokens":3,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":2}}'
EOF
  chmod +x "$STUB/claude"; mkdir -p "$T/$CASE/cards"
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null \
    && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" && names && eval "$1" ) > "$T/$CASE/out" 2>&1
}
pxtwice() { [ "$(cat "$STUB/routes" 2>/dev/null)" = "subscription"$'\n'"$PXURL" ] || fail "$1 did not run again through the proxy once its login failed: $(cat "$STUB/routes" 2>&1) $(cat "$T/$CASE/out")"; } # <what>

# Bug: with the proxy as the reviewer's fallback and an expired login, the default Claude judge ran once on the
# subscription and failed, so every finding stood unjudged.
t_pxjudge() {
  pxone 'w=$CARDS/c7 && git -C "$MAIN" worktree add -q --detach "$w" && judgecall "$w" judge "F1 a finding"' || fail "the judge call failed: $(cat "$T/$CASE/out")"
  pxtwice "the judge"
}
# Bug: the same-file check (askmodel()) on an expired login never tried the builder's fallback proxy.
t_pxask() {
  pxone 'd=$(mktemp -d) && askmodel "$d" 60 low "" question' || fail "askmodel failed: $(cat "$T/$CASE/out")"
  pxtwice "askmodel"
}
# Bug: a test action on an expired login ended failed without trying the fallback proxy.
t_pxtarun() {
  pxone 'w=$CARDS/ta && mkdir -p "$w" "$TESTACTS" && tarun "{\"id\": \"px1\", \"cli\": \"claude\", \"model\": \"m\", \"effort\": \"low\", \"action\": \"explain\"}" "$w" question \
    && jq -r .state "$TESTACTS/px1.json"' || fail "tarun failed: $(cat "$T/$CASE/out")"
  [ "$(tail -n 1 "$T/$CASE/out")" = "done" ] || fail "the test action did not end done: $(cat "$T/$CASE/out")"
  pxtwice "the test action"
}
# Bug: a check session on an expired login failed without trying the fallback proxy, so a card blocked on that login
# was never put back by itself though the proxy worked.
t_pxcheck() {
  pxone 'startcheck "{\"seat\": \"reviewer\", \"cli\": \"claude\", \"model\": \"m\", \"account\": \"\"}"' || fail "the check session failed: $(cat "$T/$CASE/out")"
  pxtwice "the check session"
}

# Issue 151. A role on an API route (proxy or api) is billed per token and has no usage limit. Bug: the guard read
# the subscription limit of every role's account all the same, so Health warned for ever that it was not read, and the
# loop asked for a reading before each pick. One issue, a guard at 90 and a Claude builder and reviewer, each on the
# routes <roles> sets; each usage reading notes the folder it read in $STUB/limit-dirs.
pxlimit() { # <roles JSON>
  setup "[$(issue 7 2026-01-01)]"; tune '.tunables.limitTtl = 0'
  echo 'echo "${CLAUDE_CONFIG_DIR:-none}" >> "$STUB/limit-dirs"; echo "{\"seven_day\": {\"utilization\": 50}}"' > "$STUB/limitcmd"
  export CONVEYOR_LIMIT_CMD='. "$STUB/limitcmd"'
  loop control guard 90 >/dev/null 2>&1 && loop control reviewer claude claude-opus-5-5 >/dev/null 2>&1 || fail "the guard or the Claude reviewer was not set"
  tune --arg b "$PXURL" --argjson r "$1" '.models.claudeProxy = {baseUrl: $b, roles: $r}'
}
# Every role on an API route: no reading is asked for (health asks as the loop does before a pick: guardread ask),
# none is given, and the snapshot gives the Board no account to read and no role on the subscription.
t_pxnolimit() {
  pxlimit '{"builder": "proxy", "reviewer": "proxy"}'
  [ "$(loop health | jq -c '[.guard.reading, .routes.subscription.roles]')" = '[null,[]]' ] || fail "health read a limit for roles on an API route: $(loop health | jq -c '[.guard, .routes]')"
  [ ! -e "$STUB/limit-dirs" ] || fail "a usage reading was asked for with every role on an API route: $(cat "$STUB/limit-dirs")"
  [ "$(loop snapshot --fresh | jq -c .limits)" = '[]' ] || fail "the snapshot gives the Board an account to read: $(loop snapshot --fresh | jq -c .limits)"
}
# Mixed routes: the builder on the API, the reviewer on the subscription. Only the reviewer's account is read.
t_pxmixedlimit() {
  pxlimit '{"builder": "proxy", "reviewer": "subscription"}'
  [ "$(loop health | jq -c '[.guard.reading, .routes.subscription.roles]')" = '[50,["reviewer"]]' ] || fail "health did not read the reviewer's limit alone: $(loop health | jq -c '[.guard, .routes]')"
  [ "$(loop snapshot --fresh | jq -c '.limits | map(.uses)')" = '[["review"]]' ] || fail "the snapshot does not give the reviewer's account alone: $(loop snapshot --fresh | jq -c .limits)"
}
# A role on fallback starts each session on the subscription (proxyroute()), and its reviewer on proxy never does:
# the builder's account alone is read. Bug caught: a login that failed once (routes.json "expired") dropped the
# fallback builder from the guard, though its next session runs on the subscription again once the user signs in.
t_pxfallbacklimit() {
  pxlimit '{"builder": "fallback", "reviewer": "proxy"}'
  mkdir -p "$ST" && echo '{"subscription": {"state": "expired", "at": "2026-01-01T00:00:00Z"}}' > "$ST/routes.json"
  [ "$(loop health | jq -c '[.guard.reading, .routes.subscription.roles]')" = '[50,["builder"]]' ] && [ -s "$STUB/limit-dirs" ] \
    || fail "the fallback builder's account was not read after a failed login: $(loop health | jq -c '[.guard, .routes]')"
  [ "$(loop snapshot --fresh | jq -c '.limits | map(.uses)')" = '[["build"]]' ] || fail "the snapshot does not give the fallback builder's account alone: $(loop snapshot --fresh | jq -c .limits)"
}
