#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: each role's route (its CLI's own login, a local proxy, or the provider's own API with the owner's own
# key): setup offers a route once one real call on it works, the session is sent the key as that API expects it, the
# key is read where the machine's service can read it (the env of Claude Code's settings file, or a key file only the
# owner can read) and never written anywhere, and doctor calls each route as the service does.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# A stub of both providers' APIs and a local Claude proxy, on one port of this machine, in $T/$CASE/api: GET
# /v1/models answers 200 (the list in $T/$CASE/api/models, when there is one) to a key listed in $T/$CASE/api/good, sent as x-api-key (Anthropic's) or as a Bearer token
# (OpenAI's), else 401 with an API error; each GET logs its path and both headers in $T/$CASE/api/asked. POST
# /v1/messages answers as the Messages API does (a proxy for Claude); POST /v1/responses is not served (no proxy for
# Codex). Exports CONVEYOR_ANTHROPIC_API and CONVEYOR_OPENAI_API, the APIs setup checks, and CONVEYOR_PROXY_PORTS.
apistub() {
  local d=$T/$CASE/api; mkdir -p "$d" && : > "$d/good"
  cat > "$d/api.py" <<'PY'
import http.server, json, os, sys
d = sys.argv[1]
class H(http.server.BaseHTTPRequestHandler):
    def answer(self, code, said):
        body = json.dumps(said).encode()
        self.send_response(code); self.send_header("content-type", "application/json"); self.end_headers(); self.wfile.write(body)
    def do_GET(self):
        x, a = self.headers.get("x-api-key") or "-", self.headers.get("Authorization") or "-"
        with open(d + "/asked", "a") as f: f.write("%s x-api-key=%s authorization=%s\n" % (self.path, x, a))
        good = open(d + "/good").read().split()
        if self.path == "/v1/models" and (x in good or a[len("Bearer "):] in good):
            self.answer(200, json.load(open(d + "/models")) if os.path.exists(d + "/models") else {"data": []})
        else: self.answer(401, {"type": "error", "error": {"type": "authentication_error", "message": "invalid key"}})
    def do_POST(self):
        if self.path == "/v1/messages": self.answer(400, {"type": "error", "error": {"type": "invalid_request_error", "message": "messages: Field required"}})
        else: self.send_response(404); self.end_headers()
    def log_message(self, *a): pass
s = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
open(d + "/port.new", "w").write(str(s.server_address[1])); os.rename(d + "/port.new", d + "/port")
s.serve_forever()
PY
  python3 -I "$d/api.py" "$d" & APISRV=$!; trap 'kill $APISRV 2>/dev/null; chmod -R u+w "$T/$CASE"' EXIT
  until [ -s "$d/port" ] || ! kill -0 $APISRV 2>/dev/null; do sleep 0.1; done
  export CONVEYOR_PROXY_PORTS CONVEYOR_ANTHROPIC_API CONVEYOR_OPENAI_API
  CONVEYOR_PROXY_PORTS=$(cat "$d/port") || fail "the stub API did not start"
  CONVEYOR_ANTHROPIC_API=http://127.0.0.1:$CONVEYOR_PROXY_PORTS CONVEYOR_OPENAI_API=http://127.0.0.1:$CONVEYOR_PROXY_PORTS/v1
}

# Bug: setup offered only the subscription login and a local proxy, so an owner who pays for the API with their own
# key got no route, and the key, when given, was to be kept in an environment the service never has. Setup checks the
# Anthropic API with the key in the env of Claude Code's settings file (sent as x-api-key, no Bearer) and the OpenAI
# API with the key it finds, names a failing one with why and does not offer it (nor offers one role the route of the
# other role's CLI), asks the fallback's second route when Claude has both a proxy and the API, asks where the key is
# kept, refuses a key file others may read, and writes each CLI's route as kind api with the key's variable and file,
# never the key.
t_apisetup() {
  local X out all h was f ak=sk-ant-api-$RANDOM$RANDOM-good ok=sk-openai-$RANDOM$RANDOM-good bad=sk-openai-$RANDOM-bad b
  # The sample project with no pack yet (its builder runs on claude, its reviewer on codex): each run below is given the
  # pack's answers too, so only the last one, with every answer, runs setup whole.
  local a=(--fast-lane no --research-lane no --owner Dana --product src/ --test t --survey no)
  sample; X=$D/conveyor/conveyor.sh; h=$XDG_CONFIG_HOME/conveyor/host.json; apistub; b=$CONVEYOR_ANTHROPIC_API
  jq 'del(.claudeProxy, .codexProxy)' "$h" > "$h.new" && mv "$h.new" "$h" || fail "the host file's routes were not taken out"
  printf '%s\n' "$ak" "$ok" > "$T/$CASE/api/good"
  export CONVEYOR_CLAUDE_SETTINGS=$T/$CASE/settings.json; jq -n --arg k "$ak" '{env: {ANTHROPIC_API_KEY: $k}}' > "$CONVEYOR_CLAUDE_SETTINGS"
  was=$(cat "$h")
  out=$(cd "$S" && OPENAI_API_KEY=$bad bash "$X" setup "${a[@]}" 2>&1); [ $? = 2 ] \
    && grep -qF "Claude: its own login works, a local API proxy at $b works, the Anthropic API with the key in ANTHROPIC_API_KEY works." <<<"$out" \
    && grep -qF "Codex: its own login works, the OpenAI API with the key in OPENAI_API_KEY fails (HTTP 401: invalid key)." <<<"$out" \
    && grep -qF -- "--builder-route <fallback, proxy, api, subscription, for" <<<"$out" && ! grep -qF -- "--reviewer-route" <<<"$out" && [ "$(cat "$h")" = "$was" ] \
    || fail "setup did not ask the builder's route, naming the API routes each checked and the failing one's cause, with nothing to ask the Codex reviewer but its login: $out"
  all=$out
  grep -qxF "/v1/models x-api-key=$ak authorization=-" "$T/$CASE/api/asked" && grep -qxF "/v1/models x-api-key=- authorization=Bearer $bad" "$T/$CASE/api/asked" \
    || fail "the Anthropic API was not sent its key as x-api-key with no Bearer token, or the OpenAI API its key as a Bearer token: $(cat "$T/$CASE/api/asked")"
  # The Anthropic API works and the OpenAI API does not: the Codex reviewer is not offered api.
  out=$(cd "$S" && OPENAI_API_KEY=$bad bash "$X" setup "${a[@]}" --builder-route api --reviewer-route api 2>&1)
  [ $? = 2 ] && grep -qF "conveyor: --reviewer-route api is not offered for the reviewer, which runs on codex (the routes offered: subscription)" <<<"$out" \
    || fail "setup took for the Codex reviewer the API route only Claude has: $out"
  # A route whose check fails is not offered: with only a refused Anthropic key and no proxy, api is refused.
  echo '{"env": {"ANTHROPIC_API_KEY": "sk-ant-refused"}}' > "$T/$CASE/bad.json"
  out=$(cd "$S" && CONVEYOR_PROXY_PORTS='' CONVEYOR_CLAUDE_SETTINGS=$T/$CASE/bad.json OPENAI_API_KEY=$bad bash "$X" setup "${a[@]}" --builder-route api 2>&1)
  [ $? = 2 ] && grep -qF "conveyor: --builder-route api is not offered for the builder, which runs on claude (the routes offered: subscription)" <<<"$out" \
    || fail "setup took the API route though its check failed: $out"
  # Claude has both a proxy and the API: the fallback's second route is asked, then where the key is kept.
  out=$(cd "$S" && OPENAI_API_KEY=$bad bash "$X" setup "${a[@]}" --builder-route fallback --reviewer-route subscription 2>&1)
  [ $? = 2 ] && grep -qF -- "--fallback-route <proxy or api: " <<<"$out" && ! grep -qF -- "--claude-key" <<<"$out" || fail "setup did not ask the fallback's second route: $out"
  all+=$out
  out=$(cd "$S" && OPENAI_API_KEY=$bad bash "$X" setup "${a[@]}" --builder-route fallback --reviewer-route subscription --fallback-route api 2>&1)
  [ $? = 2 ] && grep -qF -- "--claude-key <settings, the ANTHROPIC_API_KEY in the env of $CONVEYOR_CLAUDE_SETTINGS (it is there), or the path of a key file" <<<"$out" \
    && ! grep -qF -- "--codex-key" <<<"$out" || fail "setup did not ask where the Anthropic key is kept: $out"
  all+=$out
  # Codex's key in a key file that others may read: refused, and nothing written.
  f=$T/$CASE/openai.key; printf '%s\n' "$ok" > "$f"; chmod 644 "$f"
  out=$(cd "$S" && bash "$X" setup "${a[@]}" --builder-route fallback --reviewer-route subscription --fallback-route api --claude-key settings --codex-key "$f" 2>&1)
  [ $? = 1 ] && grep -qF "conveyor: --codex-key: the key file $f has mode 644, which lets others read or write it" <<<"$out" && [ "$(cat "$h")" = "$was" ] \
    || fail "setup took a key file of mode 644, or changed the host file: $out"
  all+=$out
  # The OpenAI key in the key file works: the Codex reviewer takes the OpenAI API.
  chmod 600 "$f"
  out=$(cd "$S" && bash "$X" setup "${a[@]}" --builder-route fallback --reviewer-route api --fallback-route api --claude-key settings --codex-key "$f" 2>&1) \
    || fail "setup with the API routes failed: $out"
  all+=$out
  jq -e --arg b "$b" --arg f "$f" '.claudeProxy == {kind: "api", baseUrl: $b, keyEnv: "ANTHROPIC_API_KEY", roles: {builder: "fallback", reviewer: "api"}}
      and .codexProxy == {kind: "api", baseUrl: "\($b)/v1", keyEnv: "OPENAI_API_KEY", keyFile: $f, roles: {builder: "fallback", reviewer: "api"}}' "$h" >/dev/null \
    || fail "setup did not write each CLI's API route, its key's variable and Codex's key file: $(cat "$h")"
  ! grep -qF -e "$ak" -e "$ok" -e "$bad" <<<"$all" && ! grep -qF -e "$ak" -e "$ok" -e "$bad" "$h" || fail "a key is in the host file or in what setup printed"
}

# Bug: on a fresh machine whose Claude login had expired, a local API proxy ran on a port and setup neither found nor
# offered it, so every card was blocked; then setup offered a proxy that refused the key (it took any Messages API
# error as a proxy), offered one role the routes of the other role's CLI, kept only the first proxy found, and never
# asked where an API key is kept when none was found yet. setup asks where each CLI's API key is kept first (none
# here); finds each proxy that answers the Messages API and the Responses API (here two stubs, after a port that
# answers something else) and makes one real call through each with the CLI, with the key of its variable (the stub
# claude posts to the proxy, the stub proxies answer 401 to a key they refuse), and Codex's login with codex exec;
# offers each role only its own CLI's routes that work, naming a failing one with why; asks which proxy when two work;
# and writes the host file's claudeProxy and codexProxy with each role's route, the proxy chosen and the NAME of the
# key variable, never its value, and the proxy's key file when its key is kept in one; run again, it does not ask.
t_setupproxy() {
  local X out was h a=(--fast-lane no --research-lane no); setupdone; h=$XDG_CONFIG_HOME/conveyor/host.json
  jq 'del(.claudeProxy, .codexProxy)' "$h" > "$h.new" && mv "$h.new" "$h" || fail "the host file's routes were not taken out"
  export CLAUDE_PROXY_KEY=px-$RANDOM$RANDOM-secret CODEX_PROXY_KEY=cx-$RANDOM$RANDOM-secret
  export CONVEYOR_CLAUDE_SETTINGS=$T/$CASE/settings.json; mkdir -p "$T/$CASE"; echo '{}' > "$CONVEYOR_CLAUDE_SETTINGS"
  cat > "$T/$CASE/proxy.py" <<'PY'
import http.server, json, os, sys, threading
d, key = sys.argv[1], sys.argv[2]
class Other(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        self.send_response(404); self.end_headers(); self.wfile.write(b"<html>no</html>")
    def log_message(self, *a): pass
class Messages(Other):
    def do_POST(self):
        self.rfile.read(int(self.headers.get("content-length") or 0))
        port = str(self.server.server_address[1])
        refused = os.path.exists(d + "/refuse") and port in open(d + "/refuse").read().split()
        if self.path == "/v1/responses":
            if self.server is not m1: return Other.do_POST(self)
            code, said = 400, {"error": {"type": "invalid_request_error", "message": "Missing required parameter: model"}}
        elif self.headers.get("Authorization") == "Bearer " + key and not refused: code, said = 200, {"type": "message", "content": [{"type": "text", "text": "OK"}]}
        else: code, said = 401, {"type": "error", "error": {"type": "authentication_error", "message": "invalid bearer token"}}
        body = json.dumps(said).encode()
        self.send_response(code); self.send_header("content-type", "application/json"); self.end_headers(); self.wfile.write(body)
o, m1, m2 = (http.server.ThreadingHTTPServer(("127.0.0.1", 0), h) for h in (Other, Messages, Messages))
for s in (o, m1): threading.Thread(target=s.serve_forever, daemon=True).start()
open(d + "/ports.new", "w").write("%d %d %d" % tuple(s.server_address[1] for s in (o, m1, m2))); os.rename(d + "/ports.new", d + "/ports")
m2.serve_forever()
PY
  python3 -I "$T/$CASE/proxy.py" "$T/$CASE" "$CLAUDE_PROXY_KEY" & PXSRV=$!; trap 'kill $PXSRV 2>/dev/null; chmod -R u+w "$T/$CASE"' EXIT
  until [ -s "$T/$CASE/ports" ] || ! kill -0 $PXSRV 2>/dev/null; do sleep 0.1; done
  export CONVEYOR_PROXY_PORTS; CONVEYOR_PROXY_PORTS=$(cat "$T/$CASE/ports") || fail "the stub proxy did not start"
  local p; read -ra p <<<"$CONVEYOR_PROXY_PORTS"; local b1=http://127.0.0.1:${p[1]} b2=http://127.0.0.1:${p[2]}; echo "${p[2]}" > "$T/$CASE/refuse"
  # Claude's subscription login has expired; through a proxy it makes one real call, sent the key as a Bearer token.
  sed -i '2i [ "$1" != -p ] || { [ -n "${ANTHROPIC_BASE_URL:-}" ] || { echo "OAuth session expired and could not be refreshed"; exit 1; }; curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $ANTHROPIC_AUTH_TOKEN" -d "{}" "$ANTHROPIC_BASE_URL/v1/messages" | grep -qx 200 && exit 0; echo "API Error: 401 authentication_error"; exit 1; }' "$G/claude"
  printf '#!/bin/sh\necho "$*" >> "%s"\n' "$G/codex-args" > "$G/codex"; was=$(cat "$h")
  # No API key is found: where it is kept is asked first, and no route yet.
  out=$(cd "$S" && bash "$X" setup "${a[@]}" 2>&1); [ $? = 2 ] && grep -qF -- "--claude-key <none, settings or the path of a key file" <<<"$out" \
    && grep -qF -- "--codex-key <none, settings or the path of a key file" <<<"$out" && ! grep -qF -- "-route <" <<<"$out" \
    || fail "setup did not ask where each API key is kept while none is found: $out"
  a+=(--claude-key none --codex-key none)
  out=$(cd "$S" && bash "$X" setup "${a[@]}" 2>&1); [ $? = 2 ] \
    && grep -qF -- "Claude: its own login fails (OAuth session expired and could not be refreshed), a local API proxy at $b1 works, a local API proxy at $b2 fails (API Error: 401 authentication_error)." <<<"$out" \
    && grep -qF -- "Codex: its own login works, a local API proxy at $b1/v1 works." <<<"$out" \
    && grep -qF -- "--builder-route <proxy, for builds, fixes and rebases, which run on claude:" <<<"$out" && grep -qF -- "--reviewer-route <fallback, proxy, subscription, for reviews, which run on codex:" <<<"$out" \
    && [ "$(cat "$h")" = "$was" ] || fail "setup did not ask each role its own CLI's routes, naming each proxy and login checked, before changing anything: $out"
  grep -q '^exec ' "$G/codex-args" || fail "Codex's login was not checked with a real call (codex exec): $(cat "$G/codex-args")"
  out=$(cd "$S" && bash "$X" setup "${a[@]}" --builder-route fallback --reviewer-route fallback 2>&1); [ $? = 2 ] \
    && grep -qF "conveyor: --builder-route fallback is not offered for the builder, which runs on claude (the routes offered: proxy)" <<<"$out" \
    || fail "setup took for the Claude builder a route only Codex offers: $out"
  # Both proxies take the key now: which one is asked.
  rm "$T/$CASE/refuse"
  out=$(cd "$S" && bash "$X" setup "${a[@]}" --builder-route proxy --reviewer-route fallback 2>&1); [ $? = 2 ] \
    && grep -qF -- "--claude-proxy <$b1 or $b2: the local API proxy claude goes through" <<<"$out" || fail "setup did not ask which of the two proxies Claude goes through: $out"
  # Bug: each proxy's key was only in this shell, which the machine's service does not have, and setup wrote the
  # route with no keyFile, so the service's sessions had no key and the proxy refused their cards. Setup asks where
  # each proxy's key is kept, and changes nothing yet.
  out=$(cd "$S" && bash "$X" setup "${a[@]}" --builder-route proxy --reviewer-route fallback --claude-proxy "$b2" 2>&1); [ $? = 2 ] \
    && grep -qF -- "--claude-proxy-key <settings, the CLAUDE_PROXY_KEY in the env of $CONVEYOR_CLAUDE_SETTINGS, or the path of a key file" <<<"$out" \
    && grep -qF -- "--codex-proxy-key <settings, the CODEX_PROXY_KEY in the env of $CONVEYOR_CLAUDE_SETTINGS, or the path of a key file" <<<"$out" \
    && [ "$(cat "$h")" = "$was" ] || fail "setup did not ask where each proxy's key is kept while it is only in this shell: $out"
  # Claude's key in a key file, and no longer in this shell: the proxy is checked with the file's key, and the file
  # is written as the route's keyFile. Codex's key in the settings file: not asked, and no keyFile.
  local f=$T/$CASE/proxy.key; printf '%s\n' "$CLAUDE_PROXY_KEY" > "$f"; chmod 600 "$f"
  jq -n --arg k "$CODEX_PROXY_KEY" '{env: {CODEX_PROXY_KEY: $k}}' > "$CONVEYOR_CLAUDE_SETTINGS"
  out=$(cd "$S" && env -u CLAUDE_PROXY_KEY -u CODEX_PROXY_KEY bash "$X" setup "${a[@]}" --builder-route proxy --reviewer-route fallback --claude-proxy "$b2" --claude-proxy-key "$f" 2>&1) \
    || fail "setup with the routes and the proxy's key file failed: $out"
  jq -e --arg b "$b1" --arg c "$b2" --arg f "$f" '.claudeProxy == {kind: "proxy", baseUrl: $c, keyEnv: "CLAUDE_PROXY_KEY", keyFile: $f, roles: {builder: "proxy", reviewer: "fallback"}}
      and .codexProxy == {kind: "proxy", baseUrl: "\($b)/v1", keyEnv: "CODEX_PROXY_KEY", roles: {builder: "proxy", reviewer: "fallback"}}' "$h" >/dev/null \
    || fail "setup did not write claudeProxy and codexProxy with the proxy chosen, the key's variable and each role's route: $(cat "$h")"
  ! grep -qF -e "$CLAUDE_PROXY_KEY" -e "$CODEX_PROXY_KEY" "$h" || fail "the host file holds a proxy's key"
  out=$(cd "$S" && bash "$X" setup --fast-lane no --research-lane no 2>&1) || fail "setup run again with both proxies set asked again, or failed: $out"
}

# Bug: doctor checked a route as the shell that calls it, whose environment the machine's service does not have. It
# reads each route's key as the service does, names where it is, and calls the API with it; a key only in the
# calling shell's environment is named as not found.
t_apidoctor() {
  local out f ak=sk-ant-api-$RANDOM$RANDOM-good ok=sk-openai-$RANDOM$RANDOM-good b
  apistub; b=$CONVEYOR_ANTHROPIC_API
  printf '%s\n' "$ak" "$ok" > "$T/$CASE/api/good"
  export CONVEYOR_CLAUDE_SETTINGS=$T/$CASE/settings.json; jq -n --arg k "$ak" '{env: {ANTHROPIC_API_KEY: $k}}' > "$CONVEYOR_CLAUDE_SETTINGS"
  f=$T/$CASE/openai.key; printf '%s\n' "$ok" > "$f"; chmod 600 "$f"; mkdir -p "$XDG_CONFIG_HOME/conveyor"
  jq -n --arg b "$b" --arg f "$f" '{claudeProxy: {kind: "api", baseUrl: $b, keyEnv: "ANTHROPIC_API_KEY", roles: {builder: "api", reviewer: "api"}},
    codexProxy: {kind: "api", baseUrl: "\($b)/v1", keyEnv: "OPENAI_API_KEY", keyFile: $f, roles: {builder: "api", reviewer: "api"}}}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  setup '[]'
  out=$(loop doctor 2>&1)
  grep -qxF "builder: m (claude) through the Anthropic API at $b, key in ANTHROPIC_API_KEY; the service reads the key from ANTHROPIC_API_KEY in the env of $CONVEYOR_CLAUDE_SETTINGS, and the API works" <<<"$out" \
    && grep -qxF "reviewer: x (codex) through $b/v1, Codex's model_provider conveyor-proxy, key in OPENAI_API_KEY; the service reads the key from the key file $f, and the API works" <<<"$out" \
    || fail "doctor did not show each role's API route with where the service reads its key and the API's answer: $out"
  # The Anthropic key only in the calling shell: the service would have none.
  echo '{}' > "$CONVEYOR_CLAUDE_SETTINGS"
  out=$(ANTHROPIC_API_KEY=$ak loop doctor 2>&1)
  grep -qxF "builder: m (claude) through the Anthropic API at $b, key in ANTHROPIC_API_KEY; the service finds no key: no ANTHROPIC_API_KEY in the env of $CONVEYOR_CLAUDE_SETTINGS, and no key file named (keyFile)" <<<"$out" \
    || fail "doctor took the calling shell's key, which the service does not have: $out"
}

# Bug: doctor called no proxy and no login: a proxy route whose proxy had stopped, with its key in the settings file,
# and a role on its own login were both shown with no check. Each is now one real call through the CLI, as the service
# makes it: the stub claude posts to the base URL it is given (nothing listens there: the call fails), else fails as
# a login that is not signed in; the stub codex records that it was called.
t_routedoctor() {
  local out p
  p=$(python3 -I -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
  export CONVEYOR_CLAUDE_SETTINGS=$T/$CASE/settings.json; mkdir -p "$T/$CASE" "$XDG_CONFIG_HOME/conveyor"
  echo '{"env": {"CLAUDE_PROXY_KEY": "px-in-settings"}}' > "$CONVEYOR_CLAUDE_SETTINGS"
  # The case's own Codex config, which names a provider: doctor read the machine's ~/.codex otherwise, so the case
  # passed only where that file named one, and failed from an install with a fresh HOME.
  export CODEX_HOME=$T/$CASE/codex; mkdir -p "$CODEX_HOME"
  printf 'model_provider = "own"\n\n[model_providers.own]\nbase_url = "https://example.com/v1"\n' > "$CODEX_HOME/config.toml"
  jq -n --arg b "http://127.0.0.1:$p" '{claudeProxy: {kind: "proxy", baseUrl: $b, keyEnv: "CLAUDE_PROXY_KEY", roles: {builder: "proxy", reviewer: "proxy"}},
    codexProxy: {kind: "subscription"}}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  setup '[]'
  echo 'if [ -n "${ANTHROPIC_BASE_URL:-}" ]; then curl -sf -o /dev/null -H "Authorization: Bearer $ANTHROPIC_AUTH_TOKEN" -d "{}" "$ANTHROPIC_BASE_URL/v1/messages" || { echo "API Error: Unable to connect to API"; exit 1; }
    else echo "Not logged in · Please run /login"; exit 1; fi' > "$STUB/build"
  echo '[ -n "${out:-}" ] || { echo called > "$STUB/codex-called"; exit 0; }' > "$STUB/review-cmd"
  out=$(loop doctor 2>&1) && fail "doctor passed with a proxy route whose proxy is stopped: $out"
  grep -qxF "builder: m (claude) through http://127.0.0.1:$p, key in CLAUDE_PROXY_KEY; the service reads the key from CLAUDE_PROXY_KEY in the env of $CONVEYOR_CLAUDE_SETTINGS, and one call through it fails (API Error: Unable to connect to API)" <<<"$out" \
    || fail "doctor did not call the stopped proxy as the service does: $out"
  # The case's Codex config names its own provider, which Codex's own login runs through.
  grep -qxF "reviewer: x (codex) through https://example.com/v1, Codex's model_provider own, key in no variable; its login works" <<<"$out" && [ -s "$STUB/codex-called" ] || fail "doctor did not call Codex on its own login: $out"
  jq '.claudeProxy = {kind: "subscription"}' "$XDG_CONFIG_HOME/conveyor/host.json" > "$T/$CASE/h" && mv "$T/$CASE/h" "$XDG_CONFIG_HOME/conveyor/host.json"
  out=$(loop doctor 2>&1)
  grep -qxF "builder: m (claude) on the subscription login; its login fails (Not logged in · Please run /login)" <<<"$out" || fail "doctor did not call Claude on its own login: $out"
  # Bug: doctor checked the default login when the project's cards run on a named account (control account): the
  # stub is signed in only in that account's folder, as the cards' sessions run it (acctrun()).
  jq --arg d "$T/$CASE/acct2" '.accounts = [{name: "second", configDir: $d}]' "$XDG_CONFIG_HOME/conveyor/host.json" > "$T/$CASE/h" && mv "$T/$CASE/h" "$XDG_CONFIG_HOME/conveyor/host.json"
  loop control account second >/dev/null 2>&1 || fail "the account was not set"
  echo '[ "${CLAUDE_CONFIG_DIR:-}" = "$(dirname "$STUB")/acct2" ] && { echo OK; exit 0; }; echo "Not logged in · Please run /login"; exit 1' > "$STUB/build"
  out=$(loop doctor 2>&1)
  grep -qxF "builder: m (claude) on the subscription login; its login works" <<<"$out" || fail "doctor did not check the login of the account the cards run on: $out"
}

# Each kind's key as the session is given it (proxyenv(), codexargs()), called in the engine's shell: the Anthropic
# API's as ANTHROPIC_API_KEY (x-api-key), never as a Bearer token, always or only on the try after the login failed
# (fallback); a proxy's as ANTHROPIC_AUTH_TOKEN (Bearer); a key file others may read is not read; Codex's API key
# reaches Codex in the variable its provider settings name.
t_apienv() {
  local k=sk-ant-file-$RANDOM$RANDOM o=sk-openai-file-$RANDOM$RANDOM f g out
  mkdir -p "$XDG_CONFIG_HOME/conveyor" "$T/$CASE"; f=$T/$CASE/anthropic.key g=$T/$CASE/openai.key
  printf '%s\n' "$k" > "$f"; printf '%s\n' "$o" > "$g"; chmod 600 "$f" "$g"
  jq -n --arg f "$f" --arg g "$g" '{claudeProxy: {kind: "api", baseUrl: "https://api.anthropic.com", keyEnv: "ANTHROPIC_API_KEY", keyFile: $f, roles: {builder: "fallback", reviewer: "api"}},
    codexProxy: {kind: "api", baseUrl: "https://api.openai.com/v1", keyEnv: "OPENAI_API_KEY", keyFile: $g, roles: {reviewer: "api"}}}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  setup '[]'
  out=$( ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" || exit 1
    show() { ( "$@"; env | grep -E '^(ANTHROPIC_(API_KEY|AUTH_TOKEN|BASE_URL)|OPENAI_API_KEY)=' | sort | tr '\n' ' '; echo "${CODEX_PX[*]-}" ); }
    ANTHROPIC_AUTH_TOKEN=held PROXY_ROLE=reviewer show proxyenv
    PROXY_ROLE=builder show proxyenv
    PROXY_NOW=1 PROXY_ROLE=builder show proxyenv
    PROXY_ROLE=reviewer show codexargs
    jq '.claudeProxy.kind = "proxy"' "$HOST" > "$HOST.new" && mv "$HOST.new" "$HOST"; PROXY_ROLE=reviewer show proxyenv
    chmod 644 "$f"; jq '.claudeProxy.kind = "api"' "$HOST" > "$HOST.new" && mv "$HOST.new" "$HOST"; PROXY_ROLE=reviewer show proxyenv ) 2>&1 )
  [ "$(sed -n 1p <<<"$out")" = "ANTHROPIC_API_KEY=$k ANTHROPIC_BASE_URL=https://api.anthropic.com " ] \
    || fail "the API route did not send its key from the key file as ANTHROPIC_API_KEY alone (no Bearer token): $out"
  [ "$(sed -n 2p <<<"$out")" = "" ] && [ "$(sed -n 3p <<<"$out")" = "ANTHROPIC_API_KEY=$k ANTHROPIC_BASE_URL=https://api.anthropic.com " ] \
    || fail "the API as the fallback was used before the login failed, or not after: $out"
  [[ $(sed -n 4p <<<"$out") == "OPENAI_API_KEY=$o -c model_provider=\"conveyor-proxy\" -c model_providers.conveyor-proxy={name = \"conveyor-proxy\", base_url = \"https://api.openai.com/v1\", env_key = \"OPENAI_API_KEY\", wire_api = \"responses\"}" ]] \
    || fail "Codex was not given the OpenAI API with its key from the key file: $out"
  [ "$(sed -n 5p <<<"$out")" = "ANTHROPIC_AUTH_TOKEN=$k ANTHROPIC_BASE_URL=https://api.anthropic.com " ] || fail "the proxy route did not send its key as a Bearer token: $out"
  [ "$(sed -n 6p <<<"$out")" = "ANTHROPIC_BASE_URL=https://api.anthropic.com " ] || fail "a key file of mode 644 was read: $out"
}

# Bug: the reviewer's model family (sol) was looked up in the OpenAI API's model list with a key read only from the
# environment Conveyor runs in, so with the key only in codexProxy's keyFile and no Codex models cache, the list was
# asked with no key, and a card could not start (codexready). The lookup takes the reviewer's route (its role api while
# the builder's is the fallback) and that route's key as a session finds it.
t_apimodel() {
  local o=sk-openai-file-$RANDOM$RANDOM g out
  apistub; mkdir -p "$XDG_CONFIG_HOME/conveyor"; g=$T/$CASE/openai.key
  printf '%s\n' "$o" > "$g"; chmod 600 "$g"; echo "$o" > "$T/$CASE/api/good"
  echo '{"data":[{"id":"gpt-6.2-sol"},{"id":"gpt-6.10-sol"},{"id":"gpt-7-astra"}]}' > "$T/$CASE/api/models"
  jq -n --arg b "$CONVEYOR_OPENAI_API" --arg g "$g" '{codexProxy: {kind: "api", baseUrl: $b, keyEnv: "OPENAI_API_KEY", keyFile: $g, roles: {builder: "fallback", reviewer: "api"}}}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  setup '[]'; tune '.models.allowed.codex += ["sol"]'; seatset reviewer sol
  out=$( ( unset OPENAI_API_KEY; export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards CODEX_HOME=$T/$CASE/codex
    . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" || exit 1
    codexready && PROXY_ROLE=reviewer codexmodel sol ) 2>&1 )
  [ "$out" = gpt-6.10-sol ] || fail "the family sol did not resolve through the API with the key from the key file: $out; asked: $(cat "$T/$CASE/api/asked" 2>&1)"
}

# Bug: the machine's service starts with a bare environment, so a key kept "in the environment Conveyor runs in" never
# reached its cards. With the key in a key file the host file names, a card run with only the service's variables
# (no key among them) gives the builder its Anthropic key and the Codex reviewer its OpenAI key, and lands; no key is
# then in the host file, the state folder (its logs and card records) or the cards folder.
t_apicard() {
  local k=sk-ant-file-$RANDOM$RANDOM-secret o=sk-openai-file-$RANDOM$RANDOM-secret leak
  mkdir -p "$XDG_CONFIG_HOME/conveyor" "$T/$CASE/keys"
  printf '%s\n' "$k" > "$T/$CASE/keys/anthropic.key"; printf '%s\n' "$o" > "$T/$CASE/keys/openai.key"; chmod 600 "$T/$CASE/keys/"*
  jq -n --arg a "$T/$CASE/keys/anthropic.key" --arg b "$T/$CASE/keys/openai.key" \
    '{claudeProxy: {kind: "api", baseUrl: "https://api.anthropic.com", keyEnv: "ANTHROPIC_API_KEY", keyFile: $a, roles: {builder: "api", reviewer: "api"}},
      codexProxy: {kind: "api", baseUrl: "https://api.openai.com/v1", keyEnv: "OPENAI_API_KEY", keyFile: $b, roles: {builder: "api", reviewer: "api"}}}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  setup "[$(issue 7 2026-01-01)]"; printf '%s\n' "$GO" > "$STUB/review.1"; tune '.tunables.apiPause = 0'
  echo 'env | grep -E "^ANTHROPIC_(API_KEY|AUTH_TOKEN)=" | sort > "$STUB/env"; echo two >> a.txt' > "$STUB/build"
  sed -i '2i [ "${1:-}" != exec ] || printf "%s\\n" "${OPENAI_API_KEY:-none}" > "$STUB/codex-key"' "$STUB/codex"
  env -i HOME="$HOME" PATH="$PATH" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_STATE_HOME="$XDG_STATE_HOME" STUB="$STUB" \
    CONVEYOR_MAIN="$R" CONVEYOR_CARDS="$T/$CASE/cards" CONVEYOR_TEST_POOL="$CONVEYOR_TEST_POOL" CONVEYOR_LIMIT_CMD=false CONVEYOR_OVERLAP_CMD=false \
    CONVEYOR_PROXY_PORTS= CONVEYOR_CLAUDE_SETTINGS="$CONVEYOR_CLAUDE_SETTINGS" CONVEYOR_TEST_CASE_ID="${CONVEYOR_TEST_CASE_ID:-}" \
    GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL="$GIT_AUTHOR_EMAIL" GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL="$GIT_COMMITTER_EMAIL" \
    bash "$SRC/conveyor.sh" run > "$T/$CASE/run.out" 2>&1
  [ "$(cat "$STUB/env" 2>&1)" = "ANTHROPIC_API_KEY=$k" ] || fail "the builder, run with the service's bare environment, did not get the key from the key file as its API key: $(cat "$STUB/env" 2>&1)"
  [ "$(cat "$STUB/codex-key" 2>&1)" = "$o" ] || fail "the Codex reviewer did not get the OpenAI key from the key file: $(cat "$STUB/codex-key" 2>&1)"
  [ "$(st 'select(.issue == 7) | .step' | grep -c '^landed$')" = 1 ] || fail "the card did not land: $(st 'select(.issue == 7) | [.step, .reason] | join(" ")'; cat "$T/$CASE/run.out")"
  leak=$(grep -rlF -e "$k" -e "$o" "$XDG_CONFIG_HOME" "$ST" "$T/$CASE/cards" "$T/$CASE/run.out" 2>/dev/null | grep -vxF -e "$T/$CASE/keys/anthropic.key" -e "$T/$CASE/keys/openai.key")
  [ -z "$leak" ] || fail "a key was written in: $leak"
}
