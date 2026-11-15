#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the pack's model price overrides (prices), saved by `conveyor.sh prices` and used to price card steps.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# A card's steps priced with an override in the fixture pack, each 1M input tokens: claude-new-9 has no built-in row
# and is priced at its override ($3); claude-opus-5-5 has one ($4) and is priced at its override ($1) instead; m has
# neither and is unpriced. The two overridden steps say so (override), and the snapshot lists the built-in rows and the
# overrides for the Rules tab. Bug caught: a model newer than the release unpriced though the owner set its price, or an
# override that does not win over the built-in row.
t_pricessnap() {
  local d out s step res x n=0 u='{"input":1000000,"write":0,"write1h":0,"read":0,"output":0}'
  export TZ=UTC; setup '[]'; mkdir -p "$ST"; d=$(date -u +%F)
  tune '.prices = {"claude-new-9": {input: 3, output: 15, cacheRead: 0.3}, "claude-opus-5-5": {input: 1, output: 5, cacheRead: 0.1}}'
  for s in 'picked ok {}' "build ok {\"model\":\"claude-new-9\",\"usage\":$u}" "fix ok {\"model\":\"claude-opus-5-5\",\"usage\":$u}" \
    "review GO {\"model\":\"m\",\"usage\":$u}" 'landed ok {"sha":"s1","product":false}'; do
    read -r step res x <<<"$s"
    jq -cn --arg s "$step" --arg r "$res" --arg t "${d}T00:0$((n += 1)):00Z" --argjson x "$x" \
      '{card: "c1", issue: 1, step: $s, time: $t, tokens: {claude: 0, codex: 0}, result: $r, sha: "", reason: "", title: "T1"} * $x' >> "$ST/cards.jsonl"
  done
  out=$(loop snapshot) || fail "snapshot exited non-zero"
  jq -e '.landed[0].metrics.timeline | map(select(.step | IN("build", "fix", "review")) | [.step, .usd, .override, .unpriced])
    == [["build", 3, true, null], ["fix", 1, true, null], ["review", null, null, "no price for its model: m"]]' <<<"$out" > /dev/null \
    || fail "the steps priced: $(jq -c '.landed[0].metrics.timeline' <<<"$out")"
  jq -e '[(.prices.builtIn[] | select(.model == "claude-opus-5-5")), .prices.overrides["claude-new-9"]]
    == [{model: "claude-opus-5-5", input: 4, output: 20, cacheRead: 0.2}, {input: 3, output: 15, cacheRead: 0.3}]' <<<"$out" > /dev/null \
    || fail "the snapshot's prices: $(jq -c .prices <<<"$out")"
}

# `prices set` saves an override in main's pack and `prices clear` takes it off (the last one takes prices out). A bad
# value is refused with why, and the pack is left byte for byte as it was. Bug caught: a negative or non-number price
# saved, which would price every step of that model wrong; an OpenCode model given a price its steps never use.
t_pricesset() {
  local a out before
  setup '[]'
  loop prices set claude-new-9 3 15 0.3 > /dev/null && loop prices set gpt-7 1.25 10 0 > /dev/null && loop prices clear gpt-7 > /dev/null \
    || fail "a good price was not saved"
  [ "$(jq -c .prices "$R/.conveyor/project.json")" = '{"claude-new-9":{"input":3,"output":15,"cacheRead":0.3}}' ] \
    || fail "the pack's prices: $(jq -c .prices "$R/.conveyor/project.json")"
  loop prices clear claude-new-9 > /dev/null && [ "$(jq -c 'has("prices")' "$R/.conveyor/project.json")" = false ] || fail "the last override left prices in the pack"
  before=$(cat "$R/.conveyor/project.json")
  for a in 'set m -1 2 3' 'set m 1 two 3' 'set m 1 2 1e3' 'set m 01 2 3' 'set -x 1 2 3' 'set opencode:p/m 1 2 3'; do
    # shellcheck disable=SC2086 # each is the command's words
    out=$(loop prices $a 2>&1) && fail "prices $a was taken"
    [[ $out == *"nothing changed"* ]] || fail "prices $a did not say why: $out"
  done
  loop prices set m 1 2 > /dev/null 2>&1; [ $? = 2 ] || fail "a price with a rate left out was not a usage error"
  [ "$(cat "$R/.conveyor/project.json")" = "$before" ] || fail "a refused price changed the pack"
}
