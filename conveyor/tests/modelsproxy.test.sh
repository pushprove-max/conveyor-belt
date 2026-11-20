#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the models' proxy: a card session's route, the reviewer family a proxy resolves, doctor's route lines.
# Its own file, so that it runs beside models.test.sh's cases. The helpers (modelsengine, rvcall) are models.test.sh's.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bugs: a card session never reaches the proxy the user set (its base URL, key and ENABLE_TOOL_SEARCH left out); a
# reviewer family name (sol) is passed to Codex as written, or resolves to an older or another family's model; the
# proxy key is on a command line (ps); a GitHub Copilot API proxy is sent a key; no match lets a card start, or
# fails without naming the setting to set; Codex's local models_cache.json is not the fallback; doctor does not
# say each role's route; with no proxy anything changes; a proxy named with no key is sent another Anthropic key the
# user holds; a proxy list with none of the family keeps models_cache.json from answering; a quoted or dotted TOML
# key, an inline table or a multiline string, is not read; the key follows a redirect to another origin; doctor calls
# a base URL the engine's environment holds direct; land-branch starts a card whose reviewer family resolves to no model;
# a key held in a variable named like an engine variable (v, key, e, ENV0, FETCH) is lost or replaced by that variable, or
# is taken from the reviewer's environment; an
# escaped quote in a multiline string ends it early, so the settings after it are not read.
proxy_start() { # <issue>: a main with that one issue, the stub proxy serving, Codex and the pack routed through it
  setup "[$(issue "$1" 2026-01-01)]"
  # Doctor's route lines, from its routes() alone; and in doctor's own output, among its checks of this machine (some of
  # which this case's machine fails), where a key's variable may meet doctor's own (t_proxykeys). Then the Anthropic
  # variables a card session gets from proxyenv(), called alone as the session's subshell calls it before claude starts.
  routes() { { modelsengine doctor routes || :; } | grep -E '^(builder|reviewer):'; }
  # Doctor runs in the project's checkout, as a user runs it: started in the case's own folder (no checkout), it stops at
  # "missing: a git checkout of the project" before its route lines.
  doctorroutes() { { (cd "$R" && loop doctor) 2>/dev/null || :; } | grep -E '^(builder|reviewer):'; }
  # Fails when the call does, so a direct session's empty list is never a call that did not run.
  pxenv() { local o; o=$(modelsengine run 'proxyenv && env') || return 1; grep -E '^(ANTHROPIC_BASE_URL|ANTHROPIC_AUTH_TOKEN|ANTHROPIC_API_KEY|ENABLE_TOOL_SEARCH)=' <<<"$o" | sort; return 0; }
  unset ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY ENABLE_TOOL_SEARCH
  echo "$GO" > "$STUB/review.1"; sed -i '2i echo " $* " >> "$STUB/codex-args"' "$STUB/codex"
  # The stub proxy: GET .../models answers $STUB/models; each request logs its Authorization header and, while the
  # asker waits, every process's command line.
  cat > "$STUB/proxy.py" <<'PY'
import http.server, os, subprocess, sys
stub = sys.argv[1]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        with open(f"{stub}/auth", "a") as f:
            f.write((self.headers.get("Authorization") or "-") + "\n")
        n = len(os.listdir(stub))
        with open(f"{stub}/ps.{n}", "w") as f:
            f.write(subprocess.run(["ps", "-eww", "-o", "args="], capture_output=True, text=True).stdout)
        if self.path.startswith("/redir/"):
            self.send_response(302); self.send_header("Location", f"http://localhost:{self.server.server_address[1]}{self.path[6:]}")
            self.end_headers(); return
        body = open(f"{stub}/models", "rb").read() if self.path.endswith("/models") else b"{}"
        self.send_response(200 if self.path.endswith("/models") else 404); self.end_headers(); self.wfile.write(body)
    def log_message(self, *a): pass
s = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
open(f"{stub}/port.new", "w").write(str(s.server_address[1])); os.rename(f"{stub}/port.new", f"{stub}/port")
s.serve_forever()
PY
  python3 -I "$STUB/proxy.py" "$STUB" & srv=$!; trap 'kill $srv 2>/dev/null' EXIT
  until [ -s "$STUB/port" ] || ! kill -0 $srv 2>/dev/null; do sleep 0.1; done # the port, or the server's end
  base=http://127.0.0.1:$(cat "$STUB/port")
  echo '{"data":[{"id":"gpt-6.2-sol"},{"id":"gpt-6.10-sol"},{"id":"gpt-7-astra"},{"id":"gpt-6.11-sol-mini"}]}' > "$STUB/models"
  export CODEX_HOME=$T/$CASE/codex PROXY_KEY=k-$RANDOM$RANDOM-secret; mkdir -p "$CODEX_HOME"
  # TOML's literal (single-quoted) strings and quoted keys name the provider and its table as well as bare ones do.
  printf '"model_provider" = \047proxy\047 # the proxy\n\n[model_providers.\047proxy\047]\nname = "Proxy"\nbase_url = \047%s/v1\047\nenv_key = "PROXY_KEY"\n' "$base" > "$CODEX_HOME/config.toml"
  tune --arg b "$base" '.models.allowed.codex += ["sol"] | .models.claudeProxy = {baseUrl: $b, keyEnv: "PROXY_KEY"}'; seatset reviewer sol
  echo 'env | grep -E "^(ANTHROPIC_BASE_URL|ANTHROPIC_AUTH_TOKEN|ANTHROPIC_API_KEY|ENABLE_TOOL_SEARCH)=" | sort > "$STUB/env"; ps -eww -o args= > "$STUB/ps.session"; echo two >> a.txt' > "$STUB/build"
  cp "$CODEX_HOME/config.toml" "$T/$CASE/config.toml" # as written here, for a part that changed it to put back
}

t_proxy() {
  proxy_start 7
  # The session's key in a variable named v, as a card session holds it: a key apart from PROXY_KEY's, so a lookup of
  # the wrong variable fails the check. The session launcher alone (builder(), lib/session.sh), on the Claude stub,
  # whose build step keeps the environment it was given.
  tune '.models.claudeProxy.keyEnv = "v"'
  vkey=v-$RANDOM$RANDOM-secret
  # shellcheck disable=SC2016 # expanded in the engine shell (modelsengine)
  v=$vkey modelsengine run 'w=$CARDS/c7 && git -C "$MAIN" worktree add -q --detach "$w" && ( builder "$w" "the brief" m high "" claude )' >/dev/null 2>&1 \
    || fail "the card session did not start: $(cat "$T/$CASE/cards/c7.err" 2>/dev/null)"
  tune '.models.claudeProxy.keyEnv = "PROXY_KEY"'
  # The review alone (rvcall), as a card's review step calls it: the family resolves for Codex through the proxy.
  out=$(rvcall 8)
  [ "$(head -n 1 <<<"$out" | jq -r .model)" = gpt-6.10-sol ] && [ "$(tail -n 1 <<<"$out")" = 'rc=0 GO' ] || fail "the family sol did not resolve to the newest gpt-<version>-sol: $out"
  grep -q -- ' -m gpt-6.10-sol ' "$STUB/codex-args" && ! grep -q -- ' -m sol ' "$STUB/codex-args" || fail "Codex was not run with the resolved model id: $(cat "$STUB/codex-args")"
  [ "$(cat "$STUB/env")" = "$(printf 'ANTHROPIC_AUTH_TOKEN=%s\nANTHROPIC_BASE_URL=%s\nENABLE_TOOL_SEARCH=true' "$vkey" "$base")" ] \
    || fail "the card session's environment does not carry the proxy, or a key in a variable named v was lost: $(cat "$STUB/env")"
  grep -qx "Bearer $PROXY_KEY" "$STUB/auth" || fail "the proxy was not asked with its key: $(cat "$STUB/auth")"
  grep -l build_opener "$STUB"/ps.[0-9]* >/dev/null || fail "no command line was read while the models list was asked for"
  ! grep -l -e "$PROXY_KEY" -e "$vkey" "$STUB"/ps.* >/dev/null || fail "a proxy key is on a command line: $(grep -l -e "$PROXY_KEY" -e "$vkey" "$STUB"/ps.*)"
  # A redirect to another origin (127.0.0.1 to localhost) is followed without the key.
  : > "$STUB/auth"; sed -i "s|$base/v1|$base/redir/v1|" "$CODEX_HOME/config.toml"
  [ "$(routes | sed -n 2p)" = "reviewer: gpt-6.10-sol (codex) through $base/redir/v1, Codex's model_provider proxy, key in PROXY_KEY" ] \
    && [ "$(cat "$STUB/auth")" = "Bearer $PROXY_KEY"$'\n-' ] || fail "the key followed a redirect to another origin: $(cat "$STUB/auth")"
  cp "$T/$CASE/config.toml" "$CODEX_HOME/config.toml"
  out=$(doctorroutes)
  # The key is only in this shell's environment, which the machine's service does not have: doctor calls through the
  # proxy with none, as the service does, and as that call works it says the proxy needs no key (bug: it said "the
  # service finds no key" and then that the call works, which read as a fault), with no missing: line.
  [ "$out" = "builder: m (claude) through $base, key in PROXY_KEY; the proxy needs no key: one call through it with none works
reviewer: gpt-6.10-sol (codex) through $base/v1, Codex's model_provider proxy, key in PROXY_KEY" ] || fail "doctor's routes: $out"
}

# Each part below is a case of its own on its own proxy (proxy_start), so they run side by side.
t_proxytool() {
  proxy_start 8
  # toolSearch named otherwise is what the session gets; a proxy named with no key variable is sent none of the
  # Anthropic keys the user holds for a direct route, only the stand-in key (so not the machine's own login either).
  tune '.models.claudeProxy.toolSearch = "false" | del(.models.claudeProxy.keyEnv)'
  [ "$(ANTHROPIC_AUTH_TOKEN=direct-secret ANTHROPIC_API_KEY=direct-key pxenv)" = "$(printf 'ANTHROPIC_AUTH_TOKEN=no-key\nANTHROPIC_BASE_URL=%s\nENABLE_TOOL_SEARCH=false' "$base")" ] \
    || fail "toolSearch named false did not reach the session, or a direct key went to the proxy: $(ANTHROPIC_AUTH_TOKEN=direct-secret ANTHROPIC_API_KEY=direct-key pxenv)"
  # A key variable named like a variable of the engine's own (e, envof()'s, which proxyenv() called alone runs as well),
  # or ENV0, still carries the key it holds (v, which only a card proves, is t_proxy's).
  tune '.models.claudeProxy.keyEnv = "e"'
  [ "$(e=e-secret pxenv)" = "$(printf 'ANTHROPIC_AUTH_TOKEN=e-secret\nANTHROPIC_BASE_URL=%s\nENABLE_TOOL_SEARCH=false' "$base")" ] \
    || fail "a key in a variable named e did not reach the session: $(e=e-secret pxenv)"
  tune '.models.claudeProxy.keyEnv = "ENV0"'
  [ "$(ENV0=env0-secret pxenv)" = "$(printf 'ANTHROPIC_AUTH_TOKEN=env0-secret\nANTHROPIC_BASE_URL=%s\nENABLE_TOOL_SEARCH=false' "$base")" ] \
    || fail "a key in a variable named ENV0 did not reach the session: $(ENV0=env0-secret pxenv)"
}
# Each whole doctor asks the proxy once for the reviewer's family, with the key (bug #822: modelswarn() and routes()
# each asked it, and the auth log held two lines). Each run is given its host report of Codex's models (clis.json, as
# doctor reads it while fresh): a list, so modelswarn() resolves the family and routes() takes its answer; no list, so
# modelswarn() asks for no family, astra included (the pack's, not a seat's); a list but no sol in the proxy's list or
# models_cache.json, so routes() takes modelswarn()'s failed answer and names the setting.
t_proxykeys() {
  proxy_start 7
  clis() { jq -cn --argjson c "$1" '{at: (now | floor), clis: {codex: $c}}' > "$ST/clis.json"; } # <Codex's list, or null>
  : > "$STUB/auth"; sed -i 's/env_key = "PROXY_KEY"/env_key = "key"/' "$CODEX_HOME/config.toml"; clis '["gpt-6.10-sol"]'
  key=key-secret doctorroutes | grep '^reviewer: gpt-6.10-sol ' >/dev/null || fail "doctor failed with the key in a variable named key"
  [ "$(cat "$STUB/auth")" = "Bearer key-secret" ] || fail "a key in a variable named key was not sent, or sent twice: $(cat "$STUB/auth")"
  : > "$STUB/auth"; sed -i 's/env_key = "key"/env_key = "e"/' "$CODEX_HOME/config.toml"; clis null; tune '.models.allowed.codex += ["astra"]'
  e=e-secret doctorroutes | grep '^reviewer: gpt-6.10-sol ' >/dev/null || fail "doctor failed with the key in a variable named e"
  [ "$(cat "$STUB/auth")" = "Bearer e-secret" ] || fail "a key in a variable named e was not sent, or the proxy was asked for a family with no list to warn against: $(cat "$STUB/auth")"
  : > "$STUB/auth"; sed -i 's/env_key = "e"/env_key = "ENV0"/' "$CODEX_HOME/config.toml"; tune '.models.allowed.codex -= ["astra"]'
  echo '{"data":[{"id":"gpt-7-astra"}]}' > "$STUB/models"; echo '{"models":[{"slug":"gpt-7-astra"}]}' > "$CODEX_HOME/models_cache.json"; clis '["gpt-7-astra"]'
  ENV0=env0-secret doctorroutes | grep '^reviewer: the reviewer model sol is a family name .*models.allowed.codex' >/dev/null || fail "doctor with no sol model did not name the setting"
  [ "$(cat "$STUB/auth")" = "Bearer env0-secret" ] || fail "a key in a variable named ENV0 was not sent, or the unresolved family was asked for twice: $(cat "$STUB/auth")"
}
t_proxyfetch() {
  proxy_start 7
  # A key in a variable named like an engine global (FETCH) is sent to the proxy and reaches Codex as the user set it.
  : > "$STUB/auth"; sed -i 's/env_key = "PROXY_KEY"/env_key = "FETCH"/' "$CODEX_HOME/config.toml"; sed -i '2i printf %s "$FETCH" > "$STUB/codex-fetch"' "$STUB/codex"
  # So does the claudeProxy key variable ENV0 (Codex reads a provider's env_key from the reviewer's own environment).
  tune '.models.claudeProxy.keyEnv = "ENV0"'; echo 'printf %s "${ENV0-unset}" > "$STUB/review-env0"' > "$STUB/review-cmd"
  # The review alone (rvcall), as a card's review step calls it: it asks the proxy for the family's newest model and
  # runs Codex on it.
  out=$(FETCH=fetch-secret ENV0=env0-secret rvcall 14)
  [ "$(tail -n 1 <<<"$out")" = 'rc=0 GO' ] || fail "the review through the proxy did not end GO: $out"
  [ "$(sort -u "$STUB/auth")" = "Bearer fetch-secret" ] && [ "$(cat "$STUB/codex-fetch")" = fetch-secret ] \
    || fail "a key in a variable named FETCH was not sent, or Codex did not inherit it: $(cat "$STUB/auth") $(cat "$STUB/codex-fetch")"
  [ "$(cat "$STUB/review-env0")" = env0-secret ] || fail "the variable ENV0 did not reach the Codex reviewer: $(cat "$STUB/review-env0")"
}
t_proxytoml() {
  proxy_start 7
  # A basic string's escapes are decoded, in a single-line and in a multiline string alike.
  for q in '"' '"""'; do
    printf 'model_provider = %spro\\u0078y%s\n[model_providers.proxy]\nbase_url = "%s/v1"\n' "$q" "$q" "$base" > "$CODEX_HOME/config.toml"
    [ "$(routes | sed -n 2p)" = "reviewer: gpt-6.10-sol (codex) through $base/v1, Codex's model_provider proxy, key in no variable" ] \
      || fail "the escaped provider name $q...$q was not decoded: $(loop doctor)"
  done
  # An escaped quote before a multiline string's close does not close it: the provider table after it is read.
  printf 'model_provider = "proxy"\ninstructions = """a\\"""\nb"""\n[model_providers.proxy]\nbase_url = "%s/v1"\n' "$base" > "$CODEX_HOME/config.toml"
  [ "$(routes | sed -n 2p)" = "reviewer: gpt-6.10-sol (codex) through $base/v1, Codex's model_provider proxy, key in no variable" ] \
    || fail "an escaped quote closed a multiline string: $(cat "$CODEX_HOME/config.toml") $(loop doctor)"
  cp "$T/$CASE/config.toml" "$CODEX_HOME/config.toml"
  # A GitHub Copilot API proxy is asked with no key.
  : > "$STUB/auth"; sed -i 's/proxy/copilot/g' "$CODEX_HOME/config.toml"
  routes | grep '^reviewer: gpt-6.10-sol ' >/dev/null || fail "doctor failed through the Copilot proxy"
  [ "$(cat "$STUB/auth")" = - ] || fail "the Copilot proxy was sent a key: $(cat "$STUB/auth")"
}
t_proxytables() {
  proxy_start 7
  # The provider named in TOML's dotted keys is the same route. The proxy lists none of the family, or no model at
  # all: Codex's models_cache.json answers.
  printf 'model_provider = "copilot"\nmodel_providers.copilot.base_url = "%s/v1"\nmodel_providers . "copilot" . env_key = "PROXY_KEY"\n' "$base" > "$CODEX_HOME/config.toml"
  echo '{"models":[{"slug":"gpt-6-sol"}]}' > "$CODEX_HOME/models_cache.json"
  for list in '{"data":[{"id":"gpt-7-astra"}]}' '{"data":[]}'; do
    echo "$list" > "$STUB/models"
    [ "$(routes | sed -n 2p)" = "reviewer: gpt-6-sol (codex) through $base/v1, Codex's model_provider copilot, key in PROXY_KEY" ] \
      || fail "the dotted provider keys were not read, or the proxy list $list kept models_cache.json from answering: $(loop doctor)"
  done
}
t_proxyinline() {
  proxy_start 7
  # The provider named in an inline table, under its table's header or nested at the top level, is the same route.
  echo '{"data":[{"id":"gpt-6.4-sol"}]}' > "$STUB/models"
  for cfg in '[model_providers]\ncopilot = { base_url = "%s/v1", env_key = "PROXY_KEY" } # inline\n' \
    'model_providers = { copilot = { name = "C", query_params = { "api-version" = "1" }, base_url = \047%s/v1\047, env_key = "PROXY_KEY" } }\n' \
    '[model_providers.copilot]\nbase_url = """\n%s/v1"""\nenv_key = \047\047\047PROXY_KEY\047\047\047\n'; do
    printf "model_provider = \"copilot\"\n$cfg" "$base" > "$CODEX_HOME/config.toml"
    [ "$(routes | sed -n 2p)" = "reviewer: gpt-6.4-sol (codex) through $base/v1, Codex's model_provider copilot, key in PROXY_KEY" ] \
      || fail "the inline provider table was not read: $(cat "$CODEX_HOME/config.toml") $(loop doctor)"
  done
}
t_proxynomatch() {
  proxy_start 7
  # The inline table t_proxytables ends on.
  printf 'model_provider = "copilot"\n[model_providers.copilot]\nbase_url = """\n%s/v1"""\nenv_key = \047\047\047PROXY_KEY\047\047\047\n' "$base" > "$CODEX_HOME/config.toml"
  # No match: the check run and land-branch each make before a card starts (codexready()), called alone, fails and
  # names the setting to set.
  echo '{"data":[{"id":"gpt-7-astra"}]}' > "$STUB/models"
  out=$(modelsengine run codexready 2>&1) && fail "the reviewer check passed a reviewer family that matches no model: $out"
  grep -q 'models.allowed.codex in .conveyor/project.json' <<<"$out" || fail "the reviewer check does not name the fix: $out"
  # The proxy unreachable: Codex's models_cache.json answers.
  kill $srv; wait $srv 2>/dev/null
  echo '{"models":[{"slug":"gpt-6.3-sol"},{"slug":"gpt-6-sol"}]}' > "$CODEX_HOME/models_cache.json"
  [ "$(routes | sed -n 2p)" = "reviewer: gpt-6.3-sol (codex) through $base/v1, Codex's model_provider copilot, key in PROXY_KEY" ] || fail "models_cache.json is not the fallback: $(loop doctor)"
}
# Bug: run (lib/run.sh) or land-branch (lib/lane.sh) records a pick before its reviewer check (codexready()) holds,
# so a reviewer family that matches no model still starts a card. The real commands: t_proxynomatch calls the check
# alone, which cannot show where each command calls it against its pick. No proxy: Codex's models_cache.json, which
# holds no sol model, is all the check reads.
t_proxynomatchpick() {
  setup "[$(issue 7 2026-01-01)]"
  export CODEX_HOME=$T/$CASE/codex; mkdir -p "$CODEX_HOME"
  echo '{"models":[{"slug":"gpt-7-astra"}]}' > "$CODEX_HOME/models_cache.json"
  tune '.models.allowed.codex += ["sol"]'; seatset reviewer sol
  out=$(loop run 2>&1) && fail "a run whose reviewer family matches no model exited zero"
  grep -q 'models.allowed.codex in .conveyor/project.json' <<<"$out" && [ -z "$(st 'select(.step == "picked")')" ] || fail "run picked eligible #7, or the fix is not named: $out"
  git -C "$R" worktree add -q -b lane-x "$T/$CASE/lane-x" main && echo bee > "$T/$CASE/lane-x/b.txt" && git -C "$T/$CASE/lane-x" add b.txt && git -C "$T/$CASE/lane-x" commit -qm 'fix(tooling): lane change'
  out=$(loop land-branch lane-x 2>&1) && fail "land-branch with a reviewer family that matches no model exited zero"
  grep -q 'models.allowed.codex in .conveyor/project.json' <<<"$out" && [ -z "$(st 'select(.step == "picked")')" ] || fail "land-branch picked mergeable lane-x, or the fix is not named: $out"
}
t_proxydirect() {
  proxy_start 10
  kill $srv; wait $srv 2>/dev/null # as t_proxynomatch leaves it
  # Direct: no proxy anywhere, a full id used as written; the session's environment has none of the proxy's.
  rm "$CODEX_HOME/config.toml"; tune 'del(.models.claudeProxy)'; seatset reviewer x
  [ "$(routes)" = $'builder: m (claude) direct\nreviewer: x (codex) direct' ] || fail "doctor's direct routes: $(loop doctor)"
  # A base URL the engine's own environment holds reaches the card session, so doctor names it.
  [ "$(ANTHROPIC_BASE_URL=https://example.com/v1 routes | sed -n 1p)" = "builder: m (claude) through https://example.com/v1, from the environment Conveyor runs in" ] \
    || fail "doctor called an inherited base URL direct: $(ANTHROPIC_BASE_URL=https://example.com/v1 loop doctor)"
  out=$(pxenv) && [ -z "$out" ] || fail "a direct session was given the proxy's environment, or proxyenv failed: $out"
}
