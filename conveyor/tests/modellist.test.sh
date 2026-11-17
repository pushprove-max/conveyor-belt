#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: where the model list comes from (modelsallowed(), climodels(), lib/control.sh), and the issue filed for a
# model with no price (noprice()).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bug: a new Codex model could be picked as a default, or named alone, only once someone added it by hand to the pack's
# models.allowed (gpt-6.2-sol and gpt-6.2-astra needed that). Codex keeps the models its account can use in its models
# cache: a new slug there is offered with no hand edit, a hidden one is not, and a pack that sets no models.allowed
# follows the cache (the reviewer's default its first model). A pack that sets its own list keeps it: the owner's.
t_modelcache() {
  setup '[]'
  export CODEX_HOME=$T/$CASE/codex; mkdir -p "$CODEX_HOME"
  echo '{"fetched_at":"2026-11-17T00:00:00Z","models":[{"slug":"gpt-9-new","visibility":"list"},{"slug":"gpt-hidden","visibility":"hide"},{"slug":"gpt-6.1-sol","visibility":"list"}]}' \
    > "$CODEX_HOME/models_cache.json"
  # The seeded record's reviewer, x, is named alone and listed by no CLI here: the reviewer runs on its default.
  tune 'del(.models.allowed)'
  out=$(loop snapshot | jq -c '.modelSettings.reviewer | [.clis.codex.models, .allowed.codex, .choices, .model]')
  [ "$out" = '[["gpt-9-new","gpt-6.1-sol"],["gpt-9-new","gpt-6.1-sol"],["gpt-9-new","gpt-6.1-sol","claude-opus-5-5","claude-sonnet-5-5","claude-fable-5-2"],"gpt-9-new"]' ] \
    || fail "a pack with no models.allowed does not offer the reviewer the models Codex's cache lists, with the first as its default: $out"
  # Codex not installed: it reports no model, so none is offered and the reviewer's default is Claude's. Bug: the
  # owner had to take the Codex models out of the pack by hand.
  local d np=''; for d in ${PATH//:/ }; do [ -x "$d/codex" ] || np+=$d:; done
  out=$(PATH=${np%:} loop snapshot | jq -c '.modelSettings.reviewer | [.allowed.codex, .model, .agent]')
  [ "$out" = '[[],"claude-opus-5-5","claude"]' ] || fail "with no Codex installed, a pack with no models.allowed still offers Codex models: $out"
  tune '.models.allowed = {claude: ["m"], codex: ["x"], "claude-reviewer": []}'
  out=$(loop snapshot | jq -c '.modelSettings.reviewer | [.clis.codex.models, .allowed.codex, .model]')
  [ "$out" = '[["gpt-9-new","gpt-6.1-sol"],["x"],"x"]' ] || fail "a pack's own models.allowed is not the list in force: $out"
}

# Bug: a model the belt offered or ran with no price row showed no cost and nothing said so, until someone saw it.
# Each such model gets one issue, held (the control record holds it), to add its price; a priced model gets none, and
# a model gets no second issue at a later look, nor after the loop restarts. The test pack lists the stub models m and
# x, which no price row prices, beside priced Claude and Codex models.
# serve's look (noprice()), as the commands given run it in serve's shell; fails the case when they fail.
looks() { # <commands>
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null \
    && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/serve.sh")" && names && eval "$1" ) > "$T/$CASE/out" 2>&1 || fail "a look failed: $(cat "$T/$CASE/out")"
}
t_noprice() {
  setup '[]'; unset CONVEYOR_NOPRICE_CMD
  # The builder off m: m is a Claude model the pack offers and no seat runs. Bug: such a model, read with an empty
  # CLI field, was read as the CLI, with no model, and got no issue.
  loop control model claude claude-opus-5-5 >/dev/null || fail "the builder's seat was not set"
  # serve's look, three times: twice in one loop, once more as a new loop that kept nothing in its shell.
  looks "noprice && noprice && NOPRICE_K='' && noprice"
  out=$(jq -cs 'map([.title, (.labels | map(.name))])' "$STUB/filed" 2>&1)
  [ "$out" = '[["Model price missing: m",["bug","P2"]],["Model price missing: x",["bug","P2"]]]' ] \
    || fail "each model with no price did not get one issue, or a priced one got one, or a later look filed again: $out"
  jq -e '.[0].body | contains("conveyor.sh prices add m ") and contains("Model prices")' -s "$STUB/filed" > /dev/null \
    || fail "the issue does not say where to add the price: $(jq -sr '.[0].body' "$STUB/filed")"
  [ "$(jq -c '[.held | index(100101, 100102) | . != null]' "$ST/control.json")" = '[true,true]' ] \
    || fail "the issues filed were not held: $(jq -c .held "$ST/control.json")"
}
# Bug: a project with no judge (a Claude-only one: the judge needs another CLI than the reviewer's) filed no issue at
# all, as the judge's seat, unset, failed the look.
t_nopricenojudge() {
  setup '[]'; unset CONVEYOR_NOPRICE_CMD
  tune '.models.allowed = {claude: ["m"], codex: [], "claude-reviewer": ["claude-opus-5-5"]}'
  looks '! seat judge >/dev/null 2>&1 && noprice'
  out=$(jq -cs 'map(.title)' "$STUB/filed" 2>&1)
  [ "$out" = '["Model price missing: m"]' ] || fail "a project with no judge did not get its one issue for the model with no price: $out"
}
# Bug: a Codex model named by its family (sol) got an issue, though Codex runs the family's newest model, which has a
# price: the family name is no model ID. The model it resolves to is the one priced. Here sol resolves to
# gpt-6.3-sol, which no price row prices and the host's report does not list (hidden): only the family's resolved ID
# names it, so a look that skipped family names, and did not resolve them, files no issue for it.
t_nopricefamily() {
  setup '[]'; unset CONVEYOR_NOPRICE_CMD
  export CODEX_HOME=$T/$CASE/codex; mkdir -p "$CODEX_HOME" && echo '{"models":[{"slug":"gpt-6.2-sol","visibility":"list"},{"slug":"gpt-6.3-sol","visibility":"hide"}]}' > "$CODEX_HOME/models_cache.json"
  tune '.models.allowed.codex = ["sol"]'
  jq '.reviewer = {model: "sol", effort: "medium"}' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"
  looks '[ "$(seat reviewer | jq -r .model)" = sol ] && noprice'
  out=$(jq -cs 'map(.title)' "$STUB/filed" 2>&1)
  [ "$out" = '["Model price missing: gpt-6.3-sol","Model price missing: m"]' ] \
    || fail "a Codex family name got an issue in place of the model it runs, or that model, with no price, got none: $out"
}
