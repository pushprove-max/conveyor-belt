#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# dashboard_limit.py cardlines (as the snapshot calls it) prices a step whose usage was read only in part, or not at
# all (unread), as an estimate, marked so. Bug caught (#1585): such a step was unpriced even when it kept a usage, so
# its card had no dollars at all and /units read "cost partial" for good.
set -uo pipefail
SOURCE=$(git rev-parse --show-toplevel)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
LIM=$SOURCE/.claude/scripts/dashboard_limit.py
# gpt-6.1-sol: $2 a million input tokens, claude-haiku-5-5 $0.10 (the built-in table). Two reviews priced exactly in
# the 30 days ($2 on 11-20, $6 on 11-21), one before them ($100) and a build ($50) of the same model: the median of the
# reviews is $4, and the others are not of it. Not samples either (#1585 review): c5's review of no token (one that
# reused an earlier answer, $0: the median would be $2) and c6's fix that ran on two models ($2.10, Haiku's dollars in
# it: c4's fix would get them as its estimate).
cat > "$T/all" <<'EOF'
{"card":"c1","steps":[{"step":"review","time":"2026-11-20T00:00:00Z","model":"gpt-6.1-sol","usage":{"input":1000000,"read":0,"output":0}}]}
{"card":"c2","steps":[{"step":"review","time":"2026-11-21T00:00:00Z","model":"gpt-6.1-sol","usage":{"input":3000000,"read":0,"output":0}},{"step":"build","time":"2026-11-21T01:00:00Z","model":"gpt-6.1-sol","usage":{"input":25000000}}]}
{"card":"c0","steps":[{"step":"review","time":"2026-09-01T00:00:00Z","model":"gpt-6.1-sol","usage":{"input":50000000,"read":0,"output":0}}]}
{"card":"c5","steps":[{"step":"review","time":"2026-11-21T02:00:00Z","model":"gpt-6.1-sol","usage":{"input":0,"read":0,"output":0}}]}
{"card":"c6","steps":[{"step":"fix","time":"2026-11-21T03:00:00Z","model":"gpt-6.1-sol","usage":{"input":2000000},"stats":{"byModel":{"gpt-6.1-sol":{"input":1000000},"claude-haiku-5-5":{"input":1000000}}}}]}
{"card":"c3","steps":[{"step":"review","time":"2026-11-22T00:00:00Z","model":"gpt-6.1-sol","unread":"the review output holds no token usage","stats":{"turns":0}},{"step":"review","time":"2026-11-22T00:01:00Z","model":"gpt-6.1-sol","unread":"the token usage of the first attempt could not be read","usage":{"input":1000000,"read":0,"output":0}}]}
{"card":"c4","steps":[{"step":"fix","time":"2026-11-22T00:00:00Z","model":"gpt-6.1-sol","unread":"the session output holds no token usage"}]}
{"card":"c8","steps":[{"step":"review","time":"2026-11-21T04:00:00Z","model":"opencode:acme/deep","usage":{"input":1000,"output":100,"cost":0.75}}]}
{"card":"c9","steps":[{"step":"review","time":"2026-11-22T00:00:00Z","model":"opencode:acme/deep","unread":"the review output holds no token usage"}]}
{"card":"c7","steps":[{"step":"review","time":"2026-11-22T00:00:00Z","model":"gpt-6.1-sol","unread":"the first attempt ran on another model","alsoUsed":[{"model":"claude-haiku-5-5","usage":{"input":1000000}}]},{"step":"review","time":"2026-11-22T00:01:00Z","model":"gpt-6.1-sol","unread":"the first attempt ran on another model","usage":{"input":1000000},"alsoUsed":[{"model":"claude-haiku-5-5","usage":{"input":1000000}}]}]}
{"card":"c10","steps":[{"step":"review","time":"2026-11-21T05:00:00Z","model":"opencode:prov/vendor/m-2","usage":{"input":1000000,"output":0}}]}
{"card":"c11","steps":[{"step":"review","time":"2026-11-22T00:00:00Z","model":"opencode:prov/vendor/m-2","unread":"the review output holds no token usage"}]}
{"card":"c12","steps":[{"step":"review","time":"2026-11-22T00:00:00Z","model":"opencode:acme/deep","unread":"the token usage of the first attempt could not be read","usage":{"input":5000,"output":200}}]}
EOF
# The pack prices opencode:prov/vendor/m-1 ($1 a million input tokens), and m-2 is its alias: c10's review on m-2 is
# priced at m-1, $1.
PRICES='{"opencode:prov/vendor/m-1": {"input": 1, "output": 2, "cacheRead": 0, "aliases": ["opencode:prov/vendor/m-2"]}}'
priced() { # <since>
  echo "{\"prices\": $PRICES, \"since\": \"$1\"}" | python3 "$LIM" cardlines "$T/all" "$T/kept" "$T/priced" > /dev/null || fail "cardlines failed on $T/all"
  jq -c 'select(.card | IN("c3", "c4", "c7", "c9", "c11", "c12")) | [.card, .usd, (.steps[] | [.usd, .pricedAs, .estimate, .unpriced])]' "$T/priced"
}
c4='["c4",null,[null,null,null,"its token usage could not be read: the session output holds no token usage"]]'
# c7 (#1585 review): the tokens a try on another model counted (alsoUsed) are priced at that model, beside the step's
# own: $0.10 alone, $2.10 with the step's own 1M; never a median for a step with tokens counted.
c7='["c7",2.2,[0.1,"claude-haiku-5-5","the tokens it counted, at its model'"'"'s price",null],[2.1,"gpt-6.1-sol","the tokens it counted, at its model'"'"'s price",null]]'
# c3: the try that counted 1M input tokens is $2 at its model's price; the one that counted none is the reviews' median.
# c4: no fix was priced at its model alone in the 30 days, so it stays unpriced, saying why.
want='["c3",6.0,[4.0,"gpt-6.1-sol","the median of 2 review steps priced at gpt-6.1-sol since 2026-10-24",null],[2.0,"gpt-6.1-sol","the tokens it counted, at its model'"'"'s price",null]]'
# c9 (#1585 review): an OpenCode review with no usage read has no price row for its model (OpenCode reports the dollars),
# but c8's review of the same model, priced at the $0.75 OpenCode reported, is its median.
c9='["c9",0.75,[0.75,"opencode:acme/deep","the median of 1 review step priced at opencode:acme/deep since SINCE",null]]'
# c11 (#1585 review): an unread OpenCode review on the alias m-2 takes the median of the reviews priced under m-1, as
# c10's is; a lookup under m-2 found none and left it unpriced.
c11='["c11",1.0,[1.0,"opencode:prov/vendor/m-1","the median of 1 review step priced at opencode:prov/vendor/m-1 since SINCE",null]]'
# c12 (#1585 review): an unread OpenCode review that counted tokens, but whose usage holds no cost, stays unpriced: c8's
# $0.75 median would put a guess in place of the tokens it did count.
c12='["c12",null,[null,null,null,"OpenCode reported no cost for it"]]'
got=$(priced 2026-10-24T00:00:00Z)
[ "$got" = "$want"$'\n'"$c4"$'\n'"${c9/SINCE/2026-10-24}"$'\n'"$c7"$'\n'"${c11/SINCE/2026-10-24}"$'\n'"$c12" ] || fail "the cards of $T/all priced since 2026-10-24: $got"
[ -s "$T/kept" ] || fail "cardlines kept no summary of the cards it priced"
# Bug caught (#1585 review): the second call takes the cards from the kept summary, with the 30 days' cutoff moved from
# 10-24 to 11-21: the $2 review of 11-20 has left the 30 days, so the median is the $6 one's. A median kept with the
# cards would still read $4.
want='["c3",8.0,[6.0,"gpt-6.1-sol","the median of 1 review step priced at gpt-6.1-sol since 2026-11-21",null],[2.0,"gpt-6.1-sol","the tokens it counted, at its model'"'"'s price",null]]'
got=$(priced 2026-11-21T00:00:00Z)
[ "$got" = "$want"$'\n'"$c4"$'\n'"${c9/SINCE/2026-11-21}"$'\n'"$c7"$'\n'"${c11/SINCE/2026-11-21}"$'\n'"$c12" ] || fail "the cards of $T/all priced from the kept summary since 2026-11-21: $got"
# A benchmark trial's cost (work) counts an estimate as unpriced: a trial's known cost is never part guessed.
got=$(jq -c '{steps: .steps, live: null, prices: {}}' <<<'{"steps":[{"step":"review","model":"gpt-6.1-sol","usage":{"input":1000000}},{"step":"review","model":"gpt-6.1-sol","unread":"part","usage":{"input":1000000}}]}' \
  | python3 "$LIM" work | jq -c '[.usd, .state, .unpriced]')
[ "$got" = '[2.0,"partial",1]' ] || fail "a trial with a step priced as an estimate: $got"
echo "PASS: dashboard-limit-estimate"
