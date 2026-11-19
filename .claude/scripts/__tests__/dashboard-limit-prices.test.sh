#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# The pack's model price overrides, added models and aliases (prices) on the Board's request costs (dashboard_limit.py build, the top strip's cost
# today and the limit card): an override wins over a model's built-in row, its fast mode and its long-prompt rate.
# Bug caught: overrides that priced card steps but never the requests, so "today" stayed at the built-in price.
set -euo pipefail
. "$(dirname "$0")/../../../conveyor/lib/portable.sh"; p_tools
SOURCE=$(git rev-parse --show-toplevel)
LIM=$SOURCE/.claude/scripts/dashboard_limit.py
T=$(cd "$(mktemp -d /tmp/dashboard-limit-prices-test.XXXXXX)" && pwd -P)
trap 'rm -rf "$T"' EXIT
unset XDG_CONFIG_HOME
fail() { echo "FAIL: $*" >&2; exit 1; }

# One request's price with the overrides put over the table: [model, input, 5-min write, 1-hour write, read, output].
# Sonnet 5.5 overridden at $1 in: its fast mode is twice that ($2 for 1M in, not the built-in $4). Opus 5.5 overridden
# at $1 in: its fast mode is $2, not the built-in fast row's $8. Haiku 5.5 overridden at $1 in: a 1M-token prompt is
# $1, not its built-in long-prompt rate. gpt-6-astra:fast overridden itself keeps that rate on a long prompt.
got=$(python3 -c "import sys, json; sys.path.insert(0, '${LIM%/*}'); import dashboard_limit as d
d.use_prices({m: {'input': 1, 'output': 5, 'cacheRead': 0.1} for m in ('claude-sonnet-5-5', 'claude-opus-5-5', 'claude-haiku-5-5', 'gpt-6-astra:fast')})
print(json.dumps([d.price([0, m, 1000000, 0, 0, 0, 0]) for m in ('claude-sonnet-5-5:fast', 'claude-opus-5-5:fast', 'claude-haiku-5-5', 'claude-haiku-5-5:fast', 'gpt-6-astra:fast', 'gpt-6-astra')]))")
[ "$got" = '[2.0, 2.0, 1.0, 2.0, 1.0, 20.0]' ] || fail "the overridden request prices: $got"

# Aliases and an added model on a request, 1M tokens each: proxy/sonnet is Sonnet 5.5 ($2 input), and its fast mode
# Sonnet 5.5's fast row ($4); claude-opus-5-5 named as an alias is a model of its own and keeps its price ($4);
# my-model, added with a cache write price of $3, prices a 5-minute cache write at that and a 1-hour one at twice its
# $1 input; an ID that is no model and no alias stays unpriced. Bug caught: a session through a proxy whose model ID
# differs priced at nothing, or an alias that re-prices a real model.
got=$(python3 -c "import sys, json; sys.path.insert(0, '${LIM%/*}'); import dashboard_limit as d
d.use_prices({'claude-sonnet-5-5': {'aliases': ['proxy/sonnet', 'claude-opus-5-5']}, 'my-model': {'input': 1, 'output': 2, 'cacheRead': 0.1, 'cacheWrite': 3}})
print(json.dumps([d.price(r) for r in ([0, 'proxy/sonnet', 1000000, 0, 0, 0, 0], [0, 'proxy/sonnet:fast', 1000000, 0, 0, 0, 0], [0, 'claude-opus-5-5', 1000000, 0, 0, 0, 0],
  [0, 'my-model', 0, 1000000, 0, 0, 0], [0, 'my-model', 0, 0, 1000000, 0, 0], [0, 'proxy/other', 1000000, 0, 0, 0, 0])]))")
[ "$got" = '[2.0, 4.0, 4.0, 3.0, 2.0, null]' ] || fail "the aliased and added request prices: $got"

# The gpt-6.2 rows, short and over 272K input, standard and fast, each a published price (not an estimate).
# Sol: $2 in, $0.10 cached, $10 out; long $4 in, $0.20 cached. Astra: $8 in, $0.40 cached, $40 out; long $16 in,
# $0.80 cached (twice the short rate, as OpenAI publishes), $60 out; fast twice each. Bugs caught: a review on 6.2
# that showed its tokens with no cost on the Board; a long Astra request whose cached tokens cost twice the published rate.
got=$(python3 -c "import sys, json; sys.path.insert(0, '${LIM%/*}'); import dashboard_limit as d
print(json.dumps([[round(d.price(r), 9), d.estimated(r)] for r in ([0, 'gpt-6.2-sol', 100000, 0, 0, 100000, 100000], [0, 'gpt-6.2-sol', 172001, 0, 0, 100000, 0],
  [0, 'gpt-6.2-sol:fast', 1000000, 0, 0, 0, 0], [0, 'gpt-6.2-astra', 100000, 0, 0, 100000, 100000], [0, 'gpt-6.2-astra', 200000, 0, 0, 100000, 100000],
  [0, 'gpt-6.2-astra:fast', 0, 0, 0, 0, 1000000], [0, 'gpt-6.2-astra:fast', 200000, 0, 0, 100000, 100000])]))")
[ "$got" = '[[1.21, false], [0.708004, false], [8.0, false], [4.84, false], [9.28, false], [80.0, false], [18.56, false]]' ] \
  || fail "the gpt-6.2 request prices: $got"

# gpt-6-sol and the daybreak alias. A step of 1M input, 1M cached and 1M output on gpt-6-sol is $2 + $0.20 + $10; a
# request of 300K input and 1M output is over 272K, so it is at the long rates ($4 in, $15 out), one of 272K input
# is not ($2 in, $10 out). A gpt-daybreak-blue-latest step costs what the same gpt-5.6-sol step costs ($4 + $0.40 +
# $20), priced as gpt-5.6-sol. Bugs caught: Codex models the Board offers whose steps have no cost, a daybreak step unpriced.
got=$(python3 -c "import sys, json; sys.path.insert(0, '${LIM%/*}'); import dashboard_limit as d
u = {'input': 1000000, 'read': 1000000, 'output': 1000000}
c = d.card_costs({'cards': [{'steps': [{'step': 'review', 'time': '2026-11-19T00:00:00Z', 'model': m, 'usage': u} for m in ('gpt-6-sol', 'gpt-daybreak-blue-latest', 'gpt-5.6-sol')]}]})
print(json.dumps([[s['usd'], s['pricedAs']] for s in c['cards'][0]['steps']] + [round(d.price(r), 9) for r in ([0, 'gpt-6-sol', 300000, 0, 0, 0, 1000000], [0, 'gpt-6-sol', 272000, 0, 0, 0, 1000000])]))")
[ "$got" = '[[12.2, "gpt-6-sol"], [24.4, "gpt-5.6-sol"], [24.4, "gpt-5.6-sol"], 16.2, 10.544]' ] \
  || fail "the gpt-6-sol and daybreak prices: $got"

# Through the Board's collect: the pack's override reaches the cost today. One request today, 1M input tokens of
# Sonnet 5.5 in fast mode: $4 at the built-in price, $2 at the pack's $1 override.
MAIN=$T/main BIN=$T/bin OUT=$T/out H=$T/home
mkdir -p "$MAIN/.conveyor" "$MAIN/.claude/metrics" "$BIN" "$H/.claude/projects/p" "$T/empty"
git -C "$MAIN" init -q -b main
git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "feat: base commit"
echo '{"prices": {"claude-sonnet-5-5": {"input": 1, "output": 5, "cacheRead": 0.1}}}' > "$MAIN/.conveyor/project.json"
printf '{"type":"assistant","requestId":"r1","timestamp":"%s","cwd":"%s","message":{"model":"claude-sonnet-5-5","usage":{"input_tokens":1000000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0,"speed":"fast"}}}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" "$MAIN" > "$H/.claude/projects/p/s1.jsonl"
rc=0
env -u CONVEYOR_HOOK_FIRE_LOG -u CODEX_HOME TZ=UTC HOME="$H" PATH="$BIN:$PATH" CONVEYOR_HOST_OS=Linux CONVEYOR_MAIN="$MAIN" \
  CONVEYOR_CODEX_REVIEW_HOME="$T/empty" CONVEYOR_WORKSPACES="$T/empty" CONVEYOR_SCRATCH="$T/empty" CONVEYOR_DASHBOARD_DIR="$OUT" \
  timeout 120 bash "$SOURCE/.claude/scripts/dashboard.sh" || rc=$?
[ "$rc" -eq 0 ] || fail "dashboard.sh exited $rc"
got=$(sed -e '1s/^window\.DASH = //' -e '$s/;$//' "$OUT/data.js" | jq -c '.panels.health.data.limit.today | [.claudeUsd, .requests]')
[ "$got" = '[2.0,1]' ] || fail "the cost today at the pack's override: $got"
echo "PASS: dashboard-limit-prices"
