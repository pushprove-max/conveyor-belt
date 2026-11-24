#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: where the model list comes from (modelsallowed(), climodels(), lib/control.sh), and the list of the
# models with no price (noprice()).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# A page of the repository says <text> (lines joined, spaces folded). Each case file that calls it defines its own, named after the file: the bug check puts only the card's test files on main's code, where a helper in lib.sh is missing, and the runner sources the case files into one shell, where one name cannot be defined twice.
pagesays_modellist() { tr '\n' ' ' < "$SRC/../$1" | tr -s ' ' | grep -qF -- "$2" || fail "$1 does not say \"$2\": $3"; } # <page> <text> <what the run showed>
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bug: a new Codex model could be picked as a default, or named alone, only once someone added it by hand to the pack's
# models.allowed (gpt-6.2-sol and gpt-6.2-astra needed that). Codex keeps the models its account can use in its models
# cache: a new slug there is offered with no hand edit, a hidden one is not, and a pack that sets no models.allowed
# follows the cache (the reviewer's default its first model). A pack that sets its own list has the cache's added
# (t_modelsadd).
t_modelcache() {
  setup '[]'
  export CODEX_HOME=$T/$CASE/codex; mkdir -p "$CODEX_HOME"
  echo '{"fetched_at":"2026-11-17T00:00:00Z","models":[{"slug":"gpt-9-new","visibility":"list"},{"slug":"gpt-hidden","visibility":"hide"},{"slug":"gpt-6.1-sol","visibility":"list"}]}' \
    > "$CODEX_HOME/models_cache.json"
  # The seeded record's reviewer, x, is named alone and listed by no CLI here: the reviewer runs on its default.
  tune 'del(.models.allowed)'
  out=$(loop snapshot --fresh | jq -c '.modelSettings.reviewer | [.clis.codex.models, .allowed.codex, .choices, .model]')
  [ "$out" = '[["gpt-9-new","gpt-6.1-sol"],["gpt-9-new","gpt-6.1-sol"],["gpt-9-new","gpt-6.1-sol","claude-opus-5-5","claude-sonnet-5-5","claude-fable-5-2"],"gpt-9-new"]' ] \
    || fail "a pack with no models.allowed does not offer the reviewer the models Codex's cache lists, with the first as its default: $out"
  # Codex not installed: it reports no model, so none is offered and the reviewer's default is Claude's. Bug: the
  # owner had to take the Codex models out of the pack by hand.
  local d np=''; for d in ${PATH//:/ }; do [ -x "$d/codex" ] || np+=$d:; done
  out=$(PATH=${np%:} loop snapshot --fresh | jq -c '.modelSettings.reviewer | [.allowed.codex, .model, .agent]')
  [ "$out" = '[[],"claude-opus-5-5","claude"]' ] || fail "with no Codex installed, a pack with no models.allowed still offers Codex models: $out"
}

# Bug (#794): a pack that set models.allowed.codex hid the models Codex reports, so a new Codex model was refused as a
# seat's model (cardok()) until someone added it to the pack by hand. The pack's list adds models to the CLI's: with
# the pack allowing gpt-a and Codex reporting gpt-a and gpt-b, the reviewer's menu list (allowed, choices) has both once
# each, the seat check takes both for the reviewer and the judge, and the pack's first model stays the default.
t_modelsadd() {
  setup '[]'
  jq -cn '{at: (now | floor), clis: {codex: ["gpt-a", "gpt-b"]}, px: false}' > "$ST/clis.json"
  tune '.models.allowed.codex = ["gpt-a"]'
  looks 'modelsettings null | jq -c ".reviewer | [.allowed.codex, [.choices[] | select(startswith(\"gpt-\"))], .model]"
    for m in gpt-a gpt-b; do for s in reviewer judge; do printf "%s %s: [%s]\n" "$s" "$m" "$(cardok "$s" "$m" medium)"; done; done'
  out=$(cat "$T/$CASE/out")
  [ "$out" = '[["gpt-a","gpt-b"],["gpt-a","gpt-b"],"gpt-a"]
reviewer gpt-a: []
judge gpt-a: []
reviewer gpt-b: []
judge gpt-b: []' ] || fail "the pack's models.allowed.codex and Codex's report are not taken together, once each: $out"
  # Bug: an empty models.allowed.codex (a Claude-only pack) got Codex's report added too, so the reviewer's default
  # moved from the pack's Claude reviewer to Codex's first model.
  tune '.models.allowed = {claude: ["m"], codex: [], "claude-reviewer": ["claude-opus-5-5"]}'
  looks 'modelsallowed a && jq -c "$OKMODELS [.codex, seed(\"reviewer\").model]" <<<"$a"'
  out=$(cat "$T/$CASE/out")
  [ "$out" = '[[],"claude-opus-5-5"]' ] || fail "an empty models.allowed.codex took Codex's report, and the reviewer's default moved: $out"
  # Bug (#1436): the per-card seat guide named only the pack's list as the models a seat takes, but gpt-b above, which
  # only Codex reports, is taken too (by the reviewer and the judge), and, with the pack's codex list empty, refused (the
  # refusal says when Codex's models count). The builder never takes it: it reads codex-builder, so its refusal names no report.
  looks 'cardok reviewer gpt-b; cardok builder gpt-b'
  out=$(cat "$T/$CASE/out")
  [[ $out == "gpt-b is not one of the models the pack's models.allowed, with the Codex models that Codex reports when it sets no list or its codex list has a model in it, lets the reviewer run: "*$'\n'"gpt-b is not one of the models the pack's models.allowed lets the builder run: "* ]] \
    || fail "gpt-b, which only Codex reports, was taken with an empty models.allowed.codex, or a refusal does not say whose models count: $out"
  pagesays_modellist docs/configuration.md 'The review'"'"'s models also include the Codex models that Codex reports, when `models.allowed` is not set or its `codex` list has a model in it' "cardok took gpt-b for the reviewer with a codex list of one model and refused it with an empty one: $out"
}

# Bug (#1436): the model-list guide covered a Codex that reports a list and a Codex not installed, not a Codex that is
# installed and gives no list (its report is {"codex": null}): there neither the report replaces the built-in Codex
# models nor empties them, so they stay.
t_modelsnolist() {
  setup '[]'; tune 'del(.models.allowed)'
  looks 'hostclis() { HOST_R="{\"codex\":null}"; }; modelsallowed a && jq -c ".codex" <<<"$a"; jq -c ".codex" <<<"$MODELS0"'
  out=$(cat "$T/$CASE/out")
  [ "$(sed -n 1p <<<"$out")" = "$(sed -n 2p <<<"$out")" ] && [ "$(sed -n 1p <<<"$out")" != '[]' ] \
    || fail "with no models.allowed and Codex giving no list, the built-in Codex models did not stay: $out"
  pagesays_modellist docs/configuration.md 'When Codex is installed but gives no list, the built-in Codex models stay.' "the built-in Codex models stay: $out"
  pagesays_modellist docs/configuration.md 'installed but gives no list, the built-in Codex ones stay' "the built-in Codex models stay: $out"
}

# A host file whose codexProxy (at <base>/v1) takes the builder's Codex sessions through a proxy, and the reviewer's
# too unless a role is given, its key in a key file, the pack's models.allowed.codex ["gpt-a"] and Codex's cache
# ["gpt-b"]; written before setup, so the case's state folder is the one the host file gives.
pxmodels() { # <base URL> [the reviewer's role]
  mkdir -p "$XDG_CONFIG_HOME/conveyor" "$T/$CASE/codex"; export CODEX_HOME=$T/$CASE/codex PXKEY=px-key-$RANDOM
  ( umask 077; echo "$PXKEY" > "$T/$CASE/pxkey" )
  jq -n --arg b "$1" --arg f "$T/$CASE/pxkey" --arg r "${2:-proxy}" '{codexProxy: {kind: "proxy", baseUrl: "\($b)/v1", keyFile: $f, roles: {builder: "proxy", reviewer: $r}}}' \
    > "$XDG_CONFIG_HOME/conveyor/host.json"
  echo '{"models":[{"slug":"gpt-b","visibility":"list"}]}' > "$CODEX_HOME/models_cache.json"
  setup '[]'
  tune '.models.allowed.codex = ["gpt-a"]'
}
# A stub proxy on a free port of 127.0.0.1, in $d (set by the caller): it lists gpt-d, gpt-a and "bad name" at
# /v1/models and writes each request's path and Authorization to $d/asked; its port is in $d/port.
pxstub() {
  cat > "$d/px.py" <<'PY'
import http.server, json, os, sys
d = sys.argv[1]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        with open(d + "/asked", "a") as f: f.write("%s %s\n" % (self.path, self.headers.get("Authorization") or "-"))
        body = json.dumps({"data": [{"id": "gpt-d"}, {"id": "gpt-a"}, {"id": "bad name"}]}).encode()
        self.send_response(200 if self.path == "/v1/models" else 404); self.send_header("content-type", "application/json"); self.end_headers(); self.wfile.write(body)
    def log_message(self, *a): pass
s = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
open(d + "/port.new", "w").write(str(s.server_address[1])); os.rename(d + "/port.new", d + "/port")
s.serve_forever()
PY
  python3 -I "$d/px.py" "$d" & PXSRV=$!; trap 'kill $PXSRV 2>/dev/null' EXIT
  # The stub is a real process: only it can say when it listens, so wait (up to its exit) for the port it writes.
  until [ -s "$d/port" ] || ! kill -0 $PXSRV 2>/dev/null; do sleep 0.1; done
  [ -s "$d/port" ] || fail "the stub proxy did not start"
}
# Bug (#794): a model the Codex proxy serves was offered only once Codex reported it or someone added it to the pack
# by hand. The host's report reads the proxy's /v1/models list (codexpxmodels()), sent the route's key: it lists gpt-d,
# and the Board's Codex menu (clis, allowed) and the seat check (cardok()) take it beside the pack's and Codex's own
# models, once each. An id that is no model name ("bad name") is left out.
t_pxmodelsadd() {
  local d=$T/$CASE/px out; mkdir -p "$d"
  pxstub
  pxmodels "http://127.0.0.1:$(cat "$d/port")"
  looks 'hostclis fresh >/dev/null && modelsettings null | jq -c ".reviewer | [.clis.codex.models, .allowed.codex]"
    printf "[%s]\n" "$(cardok reviewer gpt-d medium)"'
  out=$(cat "$T/$CASE/out")
  [ "$out" = '[["gpt-b","gpt-d","gpt-a"],["gpt-a","gpt-b","gpt-d"]]
[]' ] || fail "the models the Codex proxy lists are not offered and taken beside the pack's and Codex's: $out"
  [ "$(cat "$d/asked")" = "/v1/models Bearer $PXKEY" ] || fail "the proxy's model list was not asked once with the route's key: $(cat "$d/asked" 2>&1)"
  # Bug it catches: the OpenAI API's own list (kind api), every model of the API, was added to the Codex menu.
  jq '.codexProxy.kind = "api"' "$XDG_CONFIG_HOME/conveyor/host.json" > "$T/$CASE/host.new" && mv "$T/$CASE/host.new" "$XDG_CONFIG_HOME/conveyor/host.json"
  looks 'hostclis fresh'
  [ "$(jq -c .codex "$T/$CASE/out")" = '["gpt-b"]' ] && [ "$(wc -l < "$d/asked")" = 1 ] \
    || fail "the OpenAI API route (kind api) was asked for its models, or they were added: $(cat "$T/$CASE/out" "$d/asked")"
}
# Bug (R21): once the reviewer was moved to the subscription, a model only the proxy serves (gpt-d) was still taken
# for it (cardok()) until the saved report was read again, CLI_TTL later. Here the report is read with the proxy's
# models, the host file then sets the reviewer to subscription, and with no fresh read the same shell's cardok refuses
# gpt-d.
t_pxmodelsleft() {
  local d=$T/$CASE/px out; mkdir -p "$d"
  pxstub
  pxmodels "http://127.0.0.1:$(cat "$d/port")"
  # shellcheck disable=SC2016 # expanded in the engine shell (looks)
  looks 'hostclis fresh >/dev/null && cardok reviewer gpt-d medium && echo "--- taken" \
    && jq ".codexProxy.roles.reviewer = \"subscription\"" "$XDG_CONFIG_HOME/conveyor/host.json" > "$T/$CASE/host.new" && mv "$T/$CASE/host.new" "$XDG_CONFIG_HOME/conveyor/host.json" \
    && cardok reviewer gpt-d medium'
  out=$(cat "$T/$CASE/out")
  [[ $out == $'--- taken\ngpt-d is not one of the models'* ]] \
    || fail "after the reviewer was set to the subscription, cardok reviewer gpt-d (a proxy-only model) was not refused: $out"
}
# Bug (#1517): a saved report with no px (written before px was) and a Codex list read through the proxy was taken as
# px false, so after the reviewer moved to the subscription, cardok still took gpt-d (a proxy-only model) until
# CLI_TTL. Here the report has gpt-d and no px, the reviewer is on the subscription, and cardok refuses gpt-d.
t_pxmodelsnopx() {
  local out
  pxmodels "http://192.0.2.1:9" subscription
  # shellcheck disable=SC2016 # expanded in the engine shell (looks)
  looks 'jq -n "{at: now | floor, clis: {codex: [\"gpt-b\", \"gpt-d\"]}}" > "$CLIS" && cardok reviewer gpt-d medium; echo "--- px $(jq .px "$CLIS")"'
  out=$(cat "$T/$CASE/out")
  [[ $out == 'gpt-d is not one of the models'*$'\n--- px false' ]] \
    || fail "with a saved report with no px and the reviewer on the subscription, cardok reviewer gpt-d was not refused, or Codex was not read again: $out"
}
# Bug (#1517, and its follow-up): the host file could move the reviewer to the subscription while Codex's list was read
# through the proxy; px was then saved false beside the proxy's models, so gpt-d stayed offered until CLI_TTL, and the
# read that overlapped the switch still printed gpt-d to its caller, so a cardok in that shell could take it. Here the
# host file changes as the proxy's list comes back (codexpxmodels() wrapped): the read prints, and saves, Codex's list
# read again with the route off (no gpt-d, px false), and the same shell's cardok refuses gpt-d.
t_pxmodelsrace() {
  local d=$T/$CASE/px out; mkdir -p "$d"
  pxstub
  pxmodels "http://127.0.0.1:$(cat "$d/port")"
  # shellcheck disable=SC2016 # expanded in the engine shell (looks)
  looks 'eval "pxasked_$(declare -f codexpxmodels)"
    codexpxmodels() { local r=0; pxasked_codexpxmodels || r=$?; jq ".codexProxy.roles.reviewer = \"subscription\"" "$XDG_CONFIG_HOME/conveyor/host.json" > "$T/$CASE/host.new" && mv "$T/$CASE/host.new" "$XDG_CONFIG_HOME/conveyor/host.json"; return "$r"; }
    echo "--- printed $(hostclis fresh | jq -c .codex)" && echo "--- px $(jq -c "[.px, .clis.codex]" "$CLIS")" && cardok reviewer gpt-d medium'
  out=$(cat "$T/$CASE/out")
  [[ $out == $'--- printed ["gpt-b"]\n--- px [false,["gpt-b"]]\ngpt-d is not one of the models'* ]] \
    || fail "with the reviewer moved to the subscription while the proxy's list was read, the read printed or saved the proxy-only gpt-d, or cardok reviewer gpt-d was not refused: $out"
}
# Bug (follow-up of #1517): Codex was read before OpenCode, and its list printed with no route check after it, so a
# switch of the reviewer to the subscription while `opencode models` ran (climodels opencode wrapped) printed, and
# saved, the proxy-only gpt-d with px true. Codex is now read last: the read prints its list with the route off.
t_pxmodelsoc() {
  local d=$T/$CASE/px out; mkdir -p "$d"
  pxstub
  pxmodels "http://127.0.0.1:$(cat "$d/port")"
  # shellcheck disable=SC2016 # expanded in the engine shell (looks)
  looks 'eval "ocread_$(declare -f climodels)"
    climodels() { [ "$1" != opencode ] || { jq ".codexProxy.roles.reviewer = \"subscription\"" "$XDG_CONFIG_HOME/conveyor/host.json" > "$T/$CASE/host.new" && mv "$T/$CASE/host.new" "$XDG_CONFIG_HOME/conveyor/host.json"; }; ocread_climodels "$@"; }
    echo "--- printed $(hostclis fresh | jq -c .codex)" && echo "--- px $(jq -c "[.px, .clis.codex]" "$CLIS")"'
  out=$(cat "$T/$CASE/out")
  [ "$out" = $'--- printed ["gpt-b"]\n--- px [false,["gpt-b"]]' ] \
    || fail "with the reviewer moved to the subscription while OpenCode's list was read, hostclis fresh printed or saved the proxy-only gpt-d: $out"
}
# Bug (follow-up of #1517): with the route off as Codex's read started, on as the proxy was asked and off again as its
# list came back (codexpxmodels() wrapped, once), the read kept the proxy's gpt-d with px false: it was printed, and
# later reads kept it too. A list that has the proxy's models is read again while the route is off.
t_pxmodelsflip() {
  local d=$T/$CASE/px out; mkdir -p "$d"
  pxstub
  pxmodels "http://127.0.0.1:$(cat "$d/port")" subscription
  # shellcheck disable=SC2016 # expanded in the engine shell (looks)
  looks 'pxrole() { jq ".codexProxy.roles.reviewer = \"$1\"" "$XDG_CONFIG_HOME/conveyor/host.json" > "$T/$CASE/host.new" && mv "$T/$CASE/host.new" "$XDG_CONFIG_HOME/conveyor/host.json"; }
    eval "pxasked_$(declare -f codexpxmodels)"
    codexpxmodels() { local r=0; [ ! -e "$T/$CASE/flipped" ] || { pxasked_codexpxmodels; return; }; : > "$T/$CASE/flipped"; pxrole proxy; pxasked_codexpxmodels || r=$?; pxrole subscription; return "$r"; }
    echo "--- printed $(hostclis fresh | jq -c .codex)" && echo "--- px $(jq -c "[.px, .clis.codex]" "$CLIS")"'
  out=$(cat "$T/$CASE/out")
  [ "$out" = $'--- printed ["gpt-b"]\n--- px [false,["gpt-b"]]' ] && grep -q '^/v1/models ' "$d/asked" \
    || fail "with the proxy route on only while the proxy was asked, hostclis fresh printed or saved the proxy-only gpt-d, or the proxy was not asked: $out $(cat "$d/asked" 2>&1)"
}
# Bug it catches: a model only the proxy serves was offered to, and taken for, a reviewer whose Codex sessions stay on
# the subscription (the host's report has one Codex list for every role). With the reviewer on subscription, the
# proxy is not asked and the menu is the pack's and Codex's models.
t_pxmodelssub() {
  local d=$T/$CASE/px out; mkdir -p "$d"
  pxstub
  pxmodels "http://127.0.0.1:$(cat "$d/port")" subscription
  looks 'hostclis fresh >/dev/null && modelsettings null | jq -c ".reviewer | [.clis.codex.models, .allowed.codex]"'
  out=$(cat "$T/$CASE/out")
  [ "$out" = '[["gpt-b"],["gpt-a","gpt-b"]]' ] && [ ! -e "$d/asked" ] \
    || fail "a proxy-only model is offered to a reviewer on the subscription: $out $(cat "$d/asked" 2>&1)"
}
# Bug it catches: a proxy that does not answer failed the host's report, or left the menu without the pack's and
# Codex's models. With nothing listening at the proxy's port, the menu is the pack's and Codex's models, and nothing
# fails.
t_pxmodelsdown() {
  local p; p=$(python3 -I -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])') || fail "no free port"
  pxmodels "http://127.0.0.1:$p"
  looks 'hostclis fresh >/dev/null && modelsettings null | jq -c ".reviewer | [.clis.codex.models, .allowed.codex]"'
  out=$(cat "$T/$CASE/out")
  [ "$out" = '[["gpt-b"],["gpt-a","gpt-b"]]' ] || fail "with the proxy not answering, the menu is not the pack's and Codex's models: $out"
}

# Bug: docs/configuration.md said the fallback list keeps the built-in Codex models on a host without Codex, where
# modelsallowed() offers none (t_modelcache runs that); a reader set models.allowed for nothing. Text check: a doc page has no behaviour to run.
t_modellistdoc() {
  tr '\n' ' ' < "$SRC/../docs/configuration.md" | grep -q 'in place of the built-in Codex ones, and with no Codex models when Codex is not installed' \
    || fail "docs/configuration.md does not say the fallback model list has no Codex models when Codex is not installed"
}

# Bug: a model the belt offered or ran with no price row showed no cost and nothing said so, until someone saw it.
# Each such model is listed: noprice.json's missing, which the snapshot gives Needs you (needsYou.prices); a priced
# model is not. The test pack lists the stub models m and x, which no price row prices, beside priced Claude and Codex
# models.
# serve's look (noprice()), as the commands given run it in serve's shell; fails the case when they fail.
looks() { # <commands>
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null \
    && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/serve.sh")" && names && eval "$1" ) > "$T/$CASE/out" 2>&1 || fail "a look failed: $(cat "$T/$CASE/out")"
}
# The models the last look found with no price, as a JSON list.
missing() { jq -c .missing "$ST/noprice.json" 2>&1; }
# Bug: the look piped the models into the price check (NOPRICE_CMD). A check that ended without reading them (the
# tests' `false`, or a python that failed to start) left jq writing into a closed pipe, and with SIGPIPE ignored, as
# the loop runs under systemd (IgnoreSIGPIPE), jq wrote "writing output failed: Broken pipe" into the loop's output:
# machinesame (machineend.test.sh) failed on that line when the machine was busy. Here the check ends at once and jq
# writes the models half a second later, as on a busy machine. The look runs the check twice (miss, then gaps): one
# case for each, as the first check failing returns before the second runs.
pipelook() { # <NOPRICE_CMD>
  local real; real=$(command -v jq) || fail "no jq"
  setup '[]'; mkdir -p "$T/$CASE/bin"
  # stub: jq that waits before it writes the price check's input ({prices: ...}), so the check has ended by then.
  printf '#!/usr/bin/env bash\ncase "$*" in *"{prices: "*) sleep 0.5;; esac\nexec %q "$@"\n' "$real" > "$T/$CASE/bin/jq" # sleep: the check must have ended before jq writes, and the look offers no hook to wait on
  chmod +x "$T/$CASE/bin/jq"
  looks "PATH=$(printf %q "$T/$CASE/bin"):\$PATH; trap '' PIPE; NOPRICE_CMD=$(printf %q "$1"); noprice || :"
  ! grep -q 'Broken pipe' "$T/$CASE/out" || fail "the price check '$1', which does not read its input, made the look write: $(cat "$T/$CASE/out")"
}
# The first check (miss) ends without reading its input.
t_nopricepipe() { pipelook 'exit 1'; }
# The first check reads its input and answers; the second (gaps) ends without reading its input.
t_nopricepipegaps() {
  pipelook "[ -e $(printf %q "$T/$CASE/once") ] && exit 1; touch $(printf %q "$T/$CASE/once"); cat > /dev/null; echo '[]'"
  [ -e "$T/$CASE/once" ] || fail "the first price check did not run, so the second was not reached"
}
# Bug (#1074): the look filed a held "Model price missing" issue in the project's own repository for each model with
# no price (26 in one morning in one project), though a gap in Conveyor's price table is no work of the project. With
# the builder's seat on a Claude model with no price, no issue is filed, the snapshot gives Needs you the model, and
# the model, which the built-in table should price, gets one plugin problem note however many looks and restarts; m
# and x, no Claude or Codex model IDs, get none.
t_noprice() {
  setup '[]'; unset CONVEYOR_NOPRICE_CMD
  tune '.models.allowed.claude += ["claude-new-9"]'
  loop control model claude claude-new-9 >/dev/null || fail "the builder's seat was not set"
  # serve's look, three times: twice in one loop, once more as a new loop that kept nothing in its shell.
  looks "noprice && noprice && NOPRICE_K='' && noprice"
  [ ! -e "$STUB/filed" ] || fail "an issue was filed for a model with no price: $(jq -sc 'map(.title)' "$STUB/filed")"
  out=$(missing); [ "$out" = '["claude-new-9","m","x"]' ] || fail "the models with no price, a seat's among them, are not listed: $out"
  loop snapshot --fresh > "$T/$CASE/snap" || fail "no snapshot"
  out=$(jq -c .needsYou.prices "$T/$CASE/snap")
  [ "$out" = '{"models":["claude-new-9","m","x"]}' ] || fail "the snapshot does not give Needs you the models with no price: $out"
  [ "$(grep -c '^- ' "$ST/foreman/plugin-bugs.md" 2>&1)" = 1 ] && grep -q '^- [^ ]* · card - · No built-in price for claude-new-9: ' "$ST/foreman/plugin-bugs.md" \
    || fail "a Claude model with no built-in price did not get one plugin problem note, or a stub model got one: $(cat "$ST/foreman/plugin-bugs.md" 2>&1)"
  # Bug (#1115): the note was only in the build machine's file, and a Board on another machine never showed it. The
  # snapshot, which that Board reads over ssh, gives the note as written.
  out=$(jq -c .priceNotes "$T/$CASE/snap"); [ "$out" = "$(grep '^- ' "$ST/foreman/plugin-bugs.md" | jq -Rsc '[splits("\n") | select(. != "")]')" ] \
    || fail "the snapshot does not give the plugin problem note for the model with no built-in price: $out"
}
# Bug (review of #1074): in a Foreman group the note went to this project's own folder, which neither the group's
# Foreman nor the Board reads: both read the folder of the group's first project. Bug too: a pack price for a seat's
# model kept it off the notes, though the built-in table still has no price for it. With this project second in a
# group after alpha, and the pack pricing the builder's claude-new-9, the Board lists only m and x, and the note for
# claude-new-9 is in alpha's Foreman folder, not this project's. Bug (review of #1074): with a name no record has
# (gone) first in the group, the note went to this project's folder, though lib.sh and the Board pass gone over and
# read alpha's. Bug too: each project of a group kept its own noted, so each noted the model in the shared file. Bug
# (#1116): filing or dismissing the note on the Board takes its line out of plugin-bugs.md, so another project of the
# group, with no noted of its own, noted the model again. The line is taken out (as the Board's dismiss takes it out)
# right after the first look, before any look finds it there, so a change that kept the model only when a look found
# its note fails too: the second look, with noprice.json gone as in another project of the group, adds no note.
t_nopricegroup() {
  setup '[]'; unset CONVEYOR_NOPRICE_CMD
  local a=$T/$CASE/alpha; mkdir -p "$a" "$XDG_CONFIG_HOME/conveyor"
  jq -n --arg a "$a" --arg m "$R" '{records: [{repo: "alpha", main: $a}, {repo: "main", main: $m}], foreman: {groups: [["gone", "alpha", "main"]]}}' \
    > "$XDG_CONFIG_HOME/conveyor/host.json"
  tune '.models.allowed.claude += ["claude-new-9"] | .prices = {"claude-new-9": {input: 3, output: 15, cacheRead: 0.3}}'
  loop control model claude claude-new-9 >/dev/null || fail "the builder's seat was not set"
  local n=$a/conveyor/state/foreman/plugin-bugs.md
  looks 'noprice'
  out=$(missing); [ "$out" = '["m","x"]' ] || fail "the models with no price, the pack's price put over the table: $out"
  [ "$(grep -c 'No built-in price for claude-new-9: ' "$n" 2>&1)" = 1 ] \
    || fail "not one note for a seat's model the built-in table does not price, in the group's Foreman folder: $(cat "$n" 2>&1)"
  # Bug (#1115): this project's snapshot must give that note too, for a Board on another machine than the belt.
  [ "$(jq -r '.notes | join("|")' "$ST/noprice.json")" = "$(grep 'No built-in price for claude-new-9: ' "$n")" ] \
    || fail "the note another project made is not kept as this project's: $(cat "$ST/noprice.json")"
  [ ! -e "$ST/foreman/plugin-bugs.md" ] || fail "the note went to this project's own folder: $(cat "$ST/foreman/plugin-bugs.md")"
  grep -v 'No built-in price for claude-new-9: ' "$n" > "$n.new"; mv "$n.new" "$n"
  looks 'rm "$NOPRICE" && noprice'
  ! grep -q 'No built-in price for claude-new-9: ' "$n" || fail "a note filed or dismissed on the Board was noted again: $(cat "$n")"
  [ "$(jq -c .noted "$ST/noprice.json")" = '["claude-new-9"]' ] || fail "a model another project noted is not on noted: $(cat "$ST/noprice.json")"
}
# Bug it catches (R316): the snapshot gave the notes as noprice.json kept them, not as plugin-bugs.md holds them now, so
# a note the Foreman filed (stop.sh puts "filed as #<n>" at its end) was still given, and a Board on another machine
# added it there as a note to file again. Marked filed, the note is given no more; marked as stop.sh accepts it with a
# tab before "filed as" and a tab and a period after the number too (the first fixes read a space, comma or semicolon
# alone before it and spaces alone after it, so gave that note still, E14). Bug too: a Foreman outside the plugin's
# own repository files the note as a row of its own (stop.sh) and leaves the note as it was, which the snapshot still
# gave: a note for a model a filed line names is not given either.
t_nopricefiled() {
  local n out tab
  setup '[]'; unset CONVEYOR_NOPRICE_CMD; n=$ST/foreman/plugin-bugs.md; tab=$(printf '\t')
  tune '.models.allowed.claude += ["claude-new-9"]'
  loop control model claude claude-new-9 >/dev/null || fail "the builder's seat was not set"
  looks noprice
  grep '^- ' "$n" | sed "s/ · evidence: -\$/${tab}filed as #12$tab. · evidence: -/" > "$n.new" && cat "$n.new" >> "$n" \
    && grep -q "^- .* No built-in price for claude-new-9: .*${tab}filed as #12$tab\\. · evidence: -\$" "$n" \
    && [ "$(grep -c 'No built-in price for claude-new-9: ' "$n")" = 2 ] || fail "the note's filed copy was not added after it: $(cat "$n" 2>&1)"
  out=$(loop snapshot --fresh | jq -c '[.priceNotes, .priceFiled]')
  [ "$(jq -c '.[0]' <<<"$out")" = '[]' ] || fail "the snapshot gives a note plugin-bugs.md has as filed, or a note whose filed copy it holds ($(grep '^- ' "$n")): $out"
  # Bug: the snapshot did not say the note was filed, so a Board on another machine that had copied it could only
  # guess from its absence, and kept or dropped its copy wrongly. It names the filed model once (priceFiled).
  [ "$(jq -c '.[1]' <<<"$out")" = '["claude-new-9"]' ] || fail "priceFiled does not name the model filed once ($(grep '^- ' "$n")): $out"
  # Bug (E2): priceFiled named only the models this project's noprice.json notes, so a note another project of the
  # group made, filed after that project left the group, was named by no snapshot, and the Board kept its copy.
  jq '.notes = []' "$ST/noprice.json" > "$ST/np.new" && mv "$ST/np.new" "$ST/noprice.json" || fail "noprice.json was not emptied"
  out=$(loop snapshot --fresh | jq -c .priceFiled)
  [ "$out" = '["claude-new-9"]' ] || fail "with noprice.json naming no note, priceFiled does not name the model filed ($(grep '^- ' "$n")): $out"
}
# Bug it catches (E3): the Board's File and Dismiss on the build host take the note out of plugin-bugs.md and leave no
# filed line, so priceFiled named nothing and a Board on another machine kept offering its copy. A model noprice-noted
# lists with no open note left is named; one whose note is still open is not.
t_nopricetaken() {
  local n out
  setup '[]'; unset CONVEYOR_NOPRICE_CMD; n=$ST/foreman/plugin-bugs.md
  tune '.models.allowed.claude += ["claude-new-9"]'
  loop control model claude claude-new-9 >/dev/null || fail "the builder's seat was not set"
  looks noprice
  grep -qxF claude-new-9 "$ST/foreman/noprice-noted" || fail "noprice-noted does not list the model noted: $(cat "$ST/foreman/noprice-noted" 2>&1)"
  out=$(loop snapshot --fresh | jq -c .priceFiled)
  [ "$out" = '[]' ] || fail "priceFiled names a model whose note is still open ($(grep '^- ' "$n")): $out"
  # What the Board's note_remove() leaves after File or Dismiss: the note line gone, nothing put in its place.
  grep -v 'No built-in price for claude-new-9: ' "$n" > "$n.new"; mv "$n.new" "$n"
  out=$(loop snapshot --fresh | jq -c '[.priceNotes, .priceFiled]')
  [ "$out" = '[[],["claude-new-9"]]' ] || fail "with the note dismissed on the host (plugin-bugs.md: $(cat "$n")), [priceNotes, priceFiled] is $out"
}
# Bug it catches: a reader is given the kept snapshot while a new one builds (commands/snapshot.sh), and that one still
# held a note stop.sh had marked filed since, so a Board on another machine added it to its notes to file again. The
# kept notes are given while plugin-bugs.md is as the build read it, and none once it changed after. What must stay
# true: no reader gets a note filed after the kept snapshot's build began. The other writer is the background build: a
# build holds the kept lock here (as snapkept.test.sh does) and a record line changes, so the reader is due a build,
# starts its own writer, which finds the lock held, and the reader prints the kept snapshot while the build runs.
t_nopricekept() {
  local n out at lk
  setup '[]'; unset CONVEYOR_NOPRICE_CMD; n=$ST/foreman/plugin-bugs.md
  tune '.models.allowed.claude += ["claude-new-9"]'
  loop control model claude claude-new-9 >/dev/null || fail "the builder's seat was not set"
  looks noprice
  at=$(loop snapshot --fresh | jq -r .snapshotAt) || fail "no snapshot"
  exec {lk}>>"$ST/snapshot.json.lock" && flock "$lk" || fail "the kept lock could not be held"
  touch "$ST/cards.jsonl"
  out=$(loop snapshot | jq -c '[.snapshotAt, .recordsNewer, .priceNotes]')
  [ "$out" = "$(grep '^- ' "$n" | jq -Rsc --arg at "$at" '[$at, true, [splits("\n") | select(. != "")]]')" ] \
    || fail "the kept snapshot, read while a build runs and plugin-bugs.md unchanged since its build, does not give the note it holds: $out"
  # stop.sh in the plugin's own repository puts the filed line in the note's place.
  sed 's/ · evidence: -$/ filed as #12 · evidence: -/' "$n" > "$n.new" && mv "$n.new" "$n" && grep -q 'filed as #12' "$n" \
    || fail "the note was not marked filed: $(cat "$n" 2>&1)"
  out=$(loop snapshot | jq -c '[.snapshotAt, .recordsNewer, .priceNotes]')
  [ "$out" = "$(jq -cn --arg at "$at" '[$at, true, []]')" ] \
    || fail "the kept snapshot, read while a build runs, gives a note filed after its build ($(grep '^- ' "$n")): $out"
  # One build after the lock is let go: a writer the reads started finds nothing due, so none builds after the case.
  exec {lk}>&-; loop snapshot --fresh > /dev/null || fail "the snapshot after the reads exited non-zero"
}
# Bug it catches: a kept snapshot an older engine built has no snapshot.json.notes, so the first read after an upgrade
# gave its notes as they were, one stop.sh had marked filed since among them, and a Board on another machine added it
# to its notes to file again. With no snapshot.json.notes the kept notes are left out. Read as t_nopricekept does:
# a build holds the kept lock, so the reader prints the kept snapshot.
t_nopricekeptold() {
  local n out at lk
  setup '[]'; unset CONVEYOR_NOPRICE_CMD; n=$ST/foreman/plugin-bugs.md
  tune '.models.allowed.claude += ["claude-new-9"]'
  loop control model claude claude-new-9 >/dev/null || fail "the builder's seat was not set"
  looks noprice
  at=$(loop snapshot --fresh | jq -r .snapshotAt) || fail "no snapshot"
  jq -e '.priceNotes | length > 0' "$ST/snapshot.json" >/dev/null || fail "the build holds no note: $(jq -c .priceNotes "$ST/snapshot.json")"
  # The older engine wrote no snapshot.json.notes.
  rm -f "$ST/snapshot.json.notes"
  exec {lk}>>"$ST/snapshot.json.lock" && flock "$lk" || fail "the kept lock could not be held"
  sed 's/ · evidence: -$/ filed as #12 · evidence: -/' "$n" > "$n.new" && mv "$n.new" "$n" && grep -q 'filed as #12' "$n" \
    || fail "the note was not marked filed: $(cat "$n" 2>&1)"
  touch "$ST/cards.jsonl"
  out=$(loop snapshot | jq -c '[.snapshotAt, .recordsNewer, .priceNotes]')
  [ "$out" = "$(jq -cn --arg at "$at" '[$at, true, []]')" ] \
    || fail "the kept snapshot an older engine built (no snapshot.json.notes), read while a build runs, gives a note filed after its build ($(grep '^- ' "$n")): $out"
  exec {lk}>&-; loop snapshot --fresh > /dev/null || fail "the snapshot after the read exited non-zero"
}
# Bug: a project with no judge (a Claude-only one: the judge needs another CLI than the reviewer's) listed no model at
# all, as the judge's seat, unset, failed the look.
t_nopricenojudge() {
  setup '[]'; unset CONVEYOR_NOPRICE_CMD
  tune '.models.allowed = {claude: ["m"], codex: [], "claude-reviewer": ["claude-opus-5-5"]}'
  looks '! seat judge >/dev/null 2>&1 && noprice'
  out=$(missing); [ "$out" = '["m"]' ] || fail "a project with no judge does not list its one model with no price: $out"
}
# Bug: a Codex model named by its family (sol) was listed, though Codex runs the family's newest model, which has a
# price: the family name is no model ID. The model it resolves to is the one priced. Here sol resolves to
# gpt-6.3-sol, which no price row prices and the host's report does not list (hidden): only the family's resolved ID
# names it, so a look that skipped family names, and did not resolve them, does not list it.
t_nopricefamily() {
  setup '[]'; unset CONVEYOR_NOPRICE_CMD
  export CODEX_HOME=$T/$CASE/codex; mkdir -p "$CODEX_HOME" && echo '{"models":[{"slug":"gpt-6.2-sol","visibility":"list"},{"slug":"gpt-6.3-sol","visibility":"hide"}]}' > "$CODEX_HOME/models_cache.json"
  tune '.models.allowed.codex = ["sol"]'
  jq '.reviewer = {model: "sol", effort: "medium"}' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"
  looks '[ "$(seat reviewer | jq -r .model)" = sol ] && noprice'
  out=$(missing); [ "$out" = '["gpt-6.3-sol","m"]' ] \
    || fail "a Codex family name is listed in place of the model it runs, or that model, with no price, is not: $out"
}
# Bug: a pack that sets models.allowed listed each model of the host's Codex cache, though the Board offers only the
# pack's list and no seat runs them (seven models the project never used). The host's models are looked at only when
# the pack sets no list: then the Board offers them (t_nopricehost).
# The pack's models.allowed.codex has the host's Codex models added (#794), so one only Codex reports is offered, and
# with no price is listed too. Bug (review of #1074): such a model, offered and never run, got a plugin problem note;
# the note is for a model the belt runs.
t_nopriceallowed() {
  setup '[]'; unset CONVEYOR_NOPRICE_CMD
  jq -cn '{at: (now | floor), clis: {codex: ["gpt-extra-9"]}, px: false}' > "$ST/clis.json"
  looks 'noprice'
  out=$(missing); [ "$out" = '["gpt-extra-9","m","x"]' ] \
    || fail "a model the host's Codex reports, added to the pack's models.allowed.codex and offered, is not listed: $out"
  ! grep -q 'gpt-extra-9' "$ST/foreman/plugin-bugs.md" 2>/dev/null || fail "a model only offered got a plugin problem note: $(cat "$ST/foreman/plugin-bugs.md")"
}
# With no models.allowed the Board offers the host's Codex models, so one with no price is listed.
t_nopricehost() {
  setup '[]'; unset CONVEYOR_NOPRICE_CMD
  jq -cn '{at: (now | floor), clis: {codex: ["gpt-extra-9"]}, px: false}' > "$ST/clis.json"
  tune 'del(.models.allowed)'
  looks 'noprice'
  out=$(missing)
  [ "$(jq -c 'index("gpt-extra-9") != null' <<<"$out")" = true ] \
    || fail "with no models.allowed, a Codex model the host reports and the Board offers is not listed: $out"
}
# Bug: a model only a session's result names (asked for one model, the CLI ran another) was not listed: the look read
# the settings and the CLIs' lists, never the models the sessions ran, which the Board prices and lists under Seen.
# Bug too: a failed build's models (the blocked line's spent), which the Board lists, were not. As the Board: a build's
# models of the last 30 days count, a failed one's too, and a review's own model; a review's stats (priced at its own
# model), a test's, an older build's and a line that does not read do not.
t_nopriceran() {
  setup '[]'; unset CONVEYOR_NOPRICE_CMD
  local now old; now=$(TZ=UTC p_date now +%Y-%m-%dT%H:%M:%SZ); old=$(TZ=UTC p_date '40 days ago' +%Y-%m-%dT%H:%M:%SZ)
  { printf '{"card":"c1","step":"build","time":"%s","model":"claude-opus-5-5","stats":{"byModel":{"claude-ran-9":{},"claude-opus-5-5":{}},"models":["claude-ran-9","claude-opus-5-5"]}}\n' "$now"
    printf '{"card":"c1","step":"review","time":"%s","model":"claude-reviewer-9","stats":{"models":["claude-review-9"]}}\n' "$now"
    printf '{"card":"c1","step":"test","time":"%s","stats":{"models":["claude-test-9"]}}\n' "$now"
    printf '{"card":"c0","step":"build","time":"%s","stats":{"models":["claude-old-9"]}}\n' "$old"
    echo '{"card":"c2","stats":{"models":[' ; } >> "$ST/cards.jsonl"
  # A failed build that `retry` took out of the card records: its line is in retried.jsonl only. Bug it catches: a look
  # that read the card records alone did not list it, though the Board lists it.
  printf '{"card":"c3","step":"blocked","time":"%s","spent":{"step":"build","model":"claude-opus-5-5","stats":{"models":["claude-spent-9"]}}}\n' "$now" >> "$ST/retried.jsonl"
  looks 'noprice'
  out=$(missing); [ "$out" = '["claude-ran-9","claude-reviewer-9","claude-spent-9","m","x"]' ] \
    || fail "a model a session (or a failed one) ran, or a review's own, is not listed, or a review's stats, a test's or an older one is: $out"
}
# Bug (#1356): <synthetic>, the name Claude Code gives a message no model answered (the note a cut-off session ends
# with), was read as a model a build ran, so the look listed it as one with no price. A build (and a failed one's
# spent) whose byModel and models hold <synthetic> beside a real model, and one whose byModel holds it alone beside
# a models list of one, add no <synthetic> to the models with no price.
t_nopricesynthetic() {
  setup '[]'; unset CONVEYOR_NOPRICE_CMD
  local now; now=$(TZ=UTC p_date now +%Y-%m-%dT%H:%M:%SZ)
  { printf '{"card":"c1","step":"build","time":"%s","model":"claude-opus-5-5","stats":{"byModel":{"<synthetic>":{},"claude-opus-5-5":{}},"models":["<synthetic>","claude-opus-5-5"]}}\n' "$now"
    printf '{"card":"c1","step":"fix","time":"%s","model":"claude-opus-5-5","stats":{"byModel":{"<synthetic>":{}},"models":["<synthetic>","claude-opus-5-5"]}}\n' "$now"; } >> "$ST/cards.jsonl"
  printf '{"card":"c3","step":"blocked","time":"%s","spent":{"step":"build","model":"claude-opus-5-5","stats":{"byModel":{"<synthetic>":{}}}}}\n' "$now" >> "$ST/retried.jsonl"
  looks 'noprice'
  out=$(missing); [ "$out" = '["m","x"]' ] || fail "<synthetic> is listed as a model with no price: $out"
}
# Bug (#1074): the models only the research lane's sessions ran were listed (an embedding model, older chat models),
# though the belt never runs them. With a lane session that ran research-9, the look lists only the pack's m and x.
t_nopricelane() {
  export HOME=$T/$CASE/home; mkdir -p "$XDG_CONFIG_HOME/conveyor"
  setup '[]'; unset CONVEYOR_NOPRICE_CMD
  jq -n --arg m "$R" '{records: [{repo: "main", main: $m, lanes: {research: {worktree: "~/lane"}}}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  local p=$HOME/.claude/projects/x t; t=$(TZ=UTC p_date now +%Y-%m-%dT%H:%M:%SZ); mkdir -p "$p"
  jq -cn --arg c "$HOME/lane" --arg t "$t" '{type: "assistant", cwd: $c, sessionId: "s1", timestamp: $t, message: {model: "research-9"}}' > "$p/s.jsonl"
  looks 'noprice'
  out=$(missing); [ "$out" = '["m","x"]' ] || fail "a model only the research lane ran is listed as one with no price: $out"
}
# Bug (#1074): the held "Model price missing" issues an older Conveyor filed stayed open in the project's repository.
# The first look closes each one noprice.json's filed names, with a comment that says the Board shows the model now,
# and writes to no other issue; a second look, as a new loop, closes nothing, as filed is empty then.
t_nopriceclose() {
  setup '[]'; unset CONVEYOR_NOPRICE_CMD
  jq -n '{filed: [{model: "m", issue: 100201, at: "2026-11-19T08:00:00Z"}, {model: "x", issue: 100202, at: "2026-11-19T08:00:01Z"}]}' > "$ST/noprice.json"
  looks "noprice && NOPRICE_K='' && noprice"
  [ "$(cat "$STUB/closed" 2>&1)" = $'100201\n100202' ] || fail "the filed issues were not closed once each, or another was: $(cat "$STUB/closed" 2>&1)"
  [ "$(grep -c 'Rules, Model prices' "$STUB/close-comments" 2>&1)" = 2 ] && grep -q '`m`' "$STUB/close-comments" \
    || fail "a close has no comment that says where the price shows now: $(cat "$STUB/close-comments" 2>&1)"
  [ ! -e "$STUB/filed" ] && [ ! -e "$STUB/comments" ] || fail "the look filed or commented on another issue"
  [ "$(jq -c .filed "$ST/noprice.json")" = '[]' ] || fail "the closed issues are still on filed: $(jq -c .filed "$ST/noprice.json")"
}
