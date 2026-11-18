#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the pack's model prices, added models and aliases (prices), saved by `conveyor.sh prices` and used to
# price card steps.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# A card's steps priced with the fixture pack's prices, each 1M input tokens: claude-new-9 has no built-in row and is
# an added model ($3); claude-opus-5-5 has one ($4) and is priced at its override ($1) instead; a step run as
# anthropic/claude-opus-5-5, its alias, is priced and named as claude-opus-5-5; m has neither and is unpriced. The
# priced steps say so (override), and the snapshot lists the built-in rows (with the cache write price), the pack's
# entries, each model's display name, the model IDs its steps ran and the research lane's model, for the Rules tab. Bug
# caught: an added model unpriced though the owner set its price, an override that does not win over the built-in row, a
# session through a proxy whose model ID is an alias priced at nothing, or a research lane model with no in-use mark.
t_pricessnap() {
  local d out s step res x n=0 u='{"input":1000000,"write":0,"write1h":0,"read":0,"output":0}'
  export TZ=UTC; setup '[]'; mkdir -p "$ST"; d=$(date -u +%F)
  tune '.prices = {"claude-new-9": {input: 3, output: 15, cacheRead: 0.3, provider: "claude"},
    "claude-opus-5-5": {input: 1, output: 5, cacheRead: 0.1, name: "Opus Five", aliases: ["anthropic/claude-opus-5-5"]}}
    | .lanes.research = {model: "claude-fable-5-2", effort: "medium"}'
  for s in 'picked ok {}' "build ok {\"model\":\"claude-new-9\",\"usage\":$u}" "fix ok {\"model\":\"claude-opus-5-5\",\"usage\":$u}" \
    "rebase ok {\"model\":\"anthropic/claude-opus-5-5\",\"route\":\"proxy\",\"usage\":$u}" "review GO {\"model\":\"m\",\"usage\":$u}" 'landed ok {"sha":"s1","product":false}'; do
    read -r step res x <<<"$s"
    jq -cn --arg s "$step" --arg r "$res" --arg t "${d}T00:0$((n += 1)):00Z" --argjson x "$x" \
      '{card: "c1", issue: 1, step: $s, time: $t, tokens: {claude: 0, codex: 0}, result: $r, sha: "", reason: "", title: "T1"} * $x' >> "$ST/cards.jsonl"
  done
  out=$(loop snapshot --fresh) || fail "snapshot exited non-zero"
  jq -e '.landed[0].metrics.timeline | map(select(.step | IN("build", "fix", "rebase", "review")) | [.step, .usd, .model, .override, .unpriced])
    == [["build", 3, "claude-new-9", true, null], ["fix", 1, "claude-opus-5-5", true, null], ["rebase", 1, "claude-opus-5-5", true, null],
        ["review", null, "m", null, "no price for its model: m"]]' <<<"$out" > /dev/null \
    || fail "the steps priced: $(jq -c '.landed[0].metrics.timeline' <<<"$out")"
  jq -e '[(.prices.builtIn[] | select(.model == "claude-opus-5-5")), .prices.overrides["claude-new-9"], (.prices.names | .["claude-opus-5-5"], .["claude-new-9"], .["gpt-6.1-sol"])]
    == [{model: "claude-opus-5-5", input: 4, output: 20, cacheRead: 0.2, cacheWrite: 5}, {input: 3, output: 15, cacheRead: 0.3, provider: "claude"},
        "Opus 5.5", "New 9", "GPT-6.1 Sol"]' <<<"$out" > /dev/null || fail "the snapshot's prices: $(jq -c .prices <<<"$out")"
  jq -e '.prices.seen == [{model: "anthropic/claude-opus-5-5", sessions: 1, routes: ["proxy"], as: "claude-opus-5-5"},
    {model: "claude-new-9", sessions: 1, routes: [], as: "claude-new-9"}, {model: "claude-opus-5-5", sessions: 1, routes: [], as: "claude-opus-5-5"},
    {model: "m", sessions: 1, routes: [], as: null}]' <<<"$out" > /dev/null \
    || fail "the model IDs seen: $(jq -c .prices.seen <<<"$out")"
  jq -e '.prices.research == "claude-fable-5-2"' <<<"$out" > /dev/null || fail "the research lane's model: $(jq -c .prices.research <<<"$out")"
}

# The research lane's sessions are no card's step, so seen reads the models they ran from their transcripts: the lane
# of this checkout's record (~/lane), a session begun in a folder of the lane (~/lane/reports, filed apart), one session
# a model however many transcripts (its subagent's) name it, and none of a line older than 30 days, of a folder outside
# the lane that Claude Code files under the same name or a name the lane's starts (~/lane-x), of "<synthetic>", or of
# another checkout's lane. Bug caught: a model ID only a research session ran (one begun in ~/lane/reports, or in the
# main checkout and moved into the lane, too) never reached Seen but not priced, so the owner could not price it.
t_pricesresearch() {
  local out lane other main t
  export HOME=$T/$CASE/home; mkdir -p "$XDG_CONFIG_HOME/conveyor" "$HOME/lane" "$HOME/other"
  jq -n --arg m "$T/$CASE/main" --arg o "$T/$CASE/elsewhere" '{records: [{repo: "o", main: $o, lanes: {research: {worktree: "~/other"}}},
    {repo: "main", main: $m, lanes: {research: {worktree: "~/lane"}}}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  setup '[]'
  lane=$HOME/.claude/projects/$(sed 's/[^a-zA-Z0-9]/-/g' <<<"$HOME/lane"); other=$HOME/.claude/projects/$(sed 's/[^a-zA-Z0-9]/-/g' <<<"$HOME/other")
  mkdir -p "$lane/s1/subagents" "$other"; t=$(date -u +%FT%TZ)
  line() { jq -cn --arg m "$1" --arg c "$2" --arg s "$3" --arg t "$4" '{type: "assistant", cwd: $c, sessionId: $s, timestamp: $t, message: {model: $m, usage: {}}}'; }
  { line research-9 "$HOME/lane/sub" s1 "$t"; line '<synthetic>' "$HOME/lane" s1 "$t"; line old-9 "$HOME/lane" s2 2020-01-01T00:00:00Z
    line outside-9 "$HOME/lane-x" s3 "$t"; } > "$lane/s1.jsonl"
  line research-9 "$HOME/lane" s1 "$t" > "$lane/s1/subagents/a.jsonl"
  line other-9 "$HOME/other" s4 "$t" > "$other/s4.jsonl"
  mkdir -p "$lane-reports" "$lane-x"
  line reports-9 "$HOME/lane/reports" s5 "$t" > "$lane-reports/s5.jsonl"
  line outside-9 "$HOME/lane-x" s6 "$t" > "$lane-x/s6.jsonl"
  # A session begun in the main checkout (filed under main's folder) that works in the lane later counts from then on.
  main=$HOME/.claude/projects/$(sed 's/[^a-zA-Z0-9]/-/g' <<<"$T/$CASE/main"); mkdir -p "$main"
  { line mainonly-9 "$T/$CASE/main" s7 "$t"; line moved-9 "$HOME/lane" s7 "$t"; } > "$main/s7.jsonl"
  out=$(loop snapshot --fresh) || fail "snapshot exited non-zero"
  jq -e '.prices.seen == [{model: "moved-9", sessions: 1, routes: [], as: null}, {model: "reports-9", sessions: 1, routes: [], as: null},
    {model: "research-9", sessions: 1, routes: [], as: null}]' <<<"$out" > /dev/null \
    || fail "the model IDs seen: $(jq -c .prices.seen <<<"$out")"
}

# `prices set` saves a price in main's pack (with a cache write price when given), keeping the entry's name and
# aliases, and `prices clear` takes the price off, keeping them too (an entry left with nothing goes, and so does
# prices). An OpenCode model takes a price (your price, over the cost OpenCode reports). A bad value is refused with
# why, and the pack is left byte for byte as it was. Bug caught: a negative or non-number price saved, which would
# price every step of that model wrong; Reset to built-in that also drops the model's aliases.
t_pricesset() {
  local a out before
  setup '[]'
  tune '.prices = {"claude-opus-5-5": {name: "Opus", aliases: ["x/opus"]}}'
  loop prices set claude-new-9 3 15 0.3 > /dev/null && loop prices set gpt-7 1.25 10 0 > /dev/null && loop prices clear gpt-7 > /dev/null \
    && loop prices set opencode:p/m 0 0 0 > /dev/null && loop prices set claude-opus-5-5 1 5 0.1 2 > /dev/null || fail "a good price was not saved"
  [ "$(jq -c .prices "$R/.conveyor/project.json")" = '{"claude-opus-5-5":{"name":"Opus","aliases":["x/opus"],"input":1,"output":5,"cacheRead":0.1,"cacheWrite":2},"claude-new-9":{"input":3,"output":15,"cacheRead":0.3},"opencode:p/m":{"input":0,"output":0,"cacheRead":0}}' ] \
    || fail "the pack's prices: $(jq -c .prices "$R/.conveyor/project.json")"
  loop prices clear claude-opus-5-5 > /dev/null && [ "$(jq -c '.prices["claude-opus-5-5"]' "$R/.conveyor/project.json")" = '{"name":"Opus","aliases":["x/opus"]}' ] \
    || fail "Reset to built-in did not keep the name and aliases: $(jq -c .prices "$R/.conveyor/project.json")"
  loop prices clear claude-new-9 > /dev/null && loop prices clear opencode:p/m > /dev/null && loop prices name claude-opus-5-5 > /dev/null \
    && loop prices alias claude-opus-5-5 remove x/opus > /dev/null && [ "$(jq -c 'has("prices")' "$R/.conveyor/project.json")" = false ] \
    || fail "the last entry left prices in the pack: $(jq -c .prices "$R/.conveyor/project.json")"
  before=$(cat "$R/.conveyor/project.json")
  for a in 'set m -1 2 3' 'set m 1 two 3' 'set m 1 2 1e3' 'set m 01 2 3' 'set -x 1 2 3' 'set m 1 2 3 -4'; do
    # shellcheck disable=SC2086 # each is the command's words
    out=$(loop prices $a 2>&1) && fail "prices $a was taken"
    [[ $out == *"nothing changed"* ]] || fail "prices $a did not say why: $out"
  done
  loop prices set m 1 2 > /dev/null 2>&1; [ $? = 2 ] || fail "a price with a rate left out was not a usage error"
  [ "$(cat "$R/.conveyor/project.json")" = "$before" ] || fail "a refused price changed the pack"
}

# `prices add` saves a model the table has not got (its provider, display name and prices), `name` renames a model
# without changing its ID, `alias` adds and removes another ID that means it, and `remove` takes an added model out.
# An ID the pack has, an alias that is a model of its own or another model's alias, a bad provider and a bad name are
# refused with why. Bug caught: one alias meaning two models (which one prices the session is then a guess), or an
# added model saved over the owner's own entry.
t_pricesmodels() {
  local a out before
  setup '[]'
  loop prices add my-model other 'My model' 1 2 0.1 > /dev/null && loop prices name claude-opus-5-5 'Opus (proxy)' > /dev/null \
    && loop prices alias claude-opus-5-5 add proxy/opus > /dev/null && loop prices alias my-model add proxy/mine > /dev/null \
    && loop prices alias my-model add other/mine > /dev/null && loop prices alias my-model remove proxy/mine > /dev/null || fail "a good change was not saved"
  [ "$(jq -c .prices "$R/.conveyor/project.json")" = '{"my-model":{"name":"My model","provider":"other","input":1,"output":2,"cacheRead":0.1,"aliases":["other/mine"]},"claude-opus-5-5":{"name":"Opus (proxy)","aliases":["proxy/opus"]}}' ] \
    || fail "the pack's prices: $(jq -c .prices "$R/.conveyor/project.json")"
  before=$(cat "$R/.conveyor/project.json")
  for a in 'add my-model other X 1 2 3' 'add proxy/opus claude X 1 2 3' 'add n gemini X 1 2 3' 'alias claude-opus-5-5 add my-model' \
    'alias my-model add proxy/opus' 'alias m add m' 'alias m rename x'; do
    # shellcheck disable=SC2086 # each is the command's words
    out=$(loop prices $a 2>&1) && fail "prices $a was taken"
    [[ $out == *"nothing changed"* ]] || fail "prices $a did not say why: $out"
  done
  out=$(loop prices name m '   ' 2>&1) && fail "a blank name was taken"
  out=$(loop prices add n other "$(printf 'a%.0s' {1..61})" 1 2 3 2>&1) && fail "a 61-character name was taken"
  [ "$(cat "$R/.conveyor/project.json")" = "$before" ] || fail "a refused change changed the pack"
  loop prices remove my-model > /dev/null && [ "$(jq -c '.prices | keys' "$R/.conveyor/project.json")" = '["claude-opus-5-5"]' ] || fail "remove left the model"
}
