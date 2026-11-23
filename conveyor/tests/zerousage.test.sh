#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a Claude session whose stream gives every answer usage 0 (a route that reports usage only in its
# result line, #391): its card says its cost is shown when the step ends, and shows the cost once the result comes;
# the live usage after a result (the answers after it, the split by model it names) is the one the step's line keeps;
# a look of watch() that fails does not stop the live record.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bug (#391): every assistant event of a build's stream carried usage 0, so its live usage stayed 0 and /units and the
# Board said "no reading yet" for the whole build, which reads as a fault. Card c7-7 is in its build by its records,
# and its session is watched by the engine's own watch() (lib/session.sh), with no card run: two answers with usage 0,
# then (on $STUB/go) the turn's result line with the real usage.
t_zerousage() {
  local w=$T/$CASE/cards/c7-7 now s b; setup "[$(issue 7 2026-01-01)]"; now=$(date +%s); mkdir -p "$ST" "$T/$CASE/cards"
  for s in picked worktree deps brief start; do
    jq -cn --arg s "$s" --argjson t "$now" '{card:"c7-7",issue:7,step:$s,time:($t | todate),tokens:{claude:0,codex:0},result:"ok",sha:"",reason:""}
      + if $s == "start" then {of: "build"} else {} end' >> "$ST/cards.jsonl"
  done
  cat > "$STUB/zero-cmd" <<'EOF'
for i in 1 2; do echo '{"type":"assistant","message":{"id":"m'$i'","content":[{"type":"text","text":"x"}],"usage":{"input_tokens":0,"output_tokens":0}}}'; done
until [ -e "$STUB/go" ] || [ ! -d "$STUB" ]; do sleep 0.1; done
echo '{"type":"result","is_error":false,"usage":{"input_tokens":1000000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0}}'
until [ -e "$STUB/end" ] || [ ! -d "$STUB" ]; do sleep 0.1; done
EOF
  ( . "$SRC/lib/portable.sh"; eval "$(sed -n '/^watch() {/,/^}/p' "$SRC/lib/session.sh")"
    # shellcheck disable=SC2034 # LIVE, STUCK and SESSION_STUCK are read by watch(), defined by the eval
    LIVE=0.2 STUCK=1200 SESSION_STUCK=600; bash "$STUB/zero-cmd" > "$w.out" 2>&1 < /dev/null &
    watch $! "$w.out" "$w.live" build claude-sonnet-5-5 ) > "$T/$CASE/run.out" 2>&1 & run=$!
  wait_until "jq -e '.zero == true and .turns == 2' '$w.live' > /dev/null" "cat '$w.live'" || fail "the live record does not say every answer reported usage 0"
  b=$(loop snapshot | jq -c '.belt[] | select(.card == "c7-7") | [.reading, .atEnd, .usd]')
  [ "$b" = '[false,true,null]' ] || fail "a build whose answers all report usage 0 does not say its cost is shown when the step ends: $b"
  # The live stream (watch.py) lays the live record over the belt the same way.
  b=$(python3 -I -c 'import json, sys; sys.path.insert(0, sys.argv[1]); import watch
l = watch.Stream.lay(json.load(open(sys.argv[2])), {"tokens": {"claude": 0, "codex": 0}, "usd": 0, "reading": False}, {})
print(json.dumps([l["reading"], l["atEnd"]]))' "$SRC" "$w.live")
  [ "$b" = '[false, true]' ] || fail "the live stream does not say the cost is shown when the step ends: $b"
  # The result line arrives: its usage is the reading, priced, while the session still runs.
  : > "$STUB/go"
  wait_until "jq -e '.usage.input == 1000000' '$w.live' > /dev/null" "cat '$w.live'" || fail "the result line's usage is not the live usage"
  b=$(loop snapshot --fresh | jq -c '.belt[] | select(.card == "c7-7") | [.reading, .atEnd, (.usd | type == "number" and . > 0)]')
  [ "$b" = '[true,false,true]' ] || fail "the card does not show its cost once the result line arrived: $b $(cat "$w.live")"
  : > "$STUB/end"; wait $run || fail "the watch exited non-zero: $(cat "$T/$CASE/run.out")"
}

# livestream <stream file> <jq condition> [keep]: card c7-7 in its build by its records, its session (on
# claude-sonnet-5-5) watched by the engine's own watch() with no card run, its output the stream given whole. The live
# record, once it meets the condition, is copied to $T/$CASE/live, and what SESSIONREAD (jq/sessionread.jq) reads of
# the same stream when the step ends to $T/$CASE/read. With keep, the session runs on until $T/$CASE/end is made.
livestream() {
  local w=$T/$CASE/cards/c7-7 now s; setup "[$(issue 7 2026-01-01)]"; now=$(date +%s); mkdir -p "$ST" "$T/$CASE/cards"
  for s in picked worktree deps brief start; do
    jq -cn --arg s "$s" --argjson t "$now" '{card:"c7-7",issue:7,step:$s,time:($t | todate),tokens:{claude:0,codex:0},result:"ok",sha:"",reason:""}
      + if $s == "start" then {of: "build"} else {} end' >> "$ST/cards.jsonl"
  done
  cp "$1" "$w.out"; printf '%s\n' 'until [ -e "$1" ]; do sleep 0.1; done' > "$T/$CASE/session" # sleep: a session that runs until the case ends it
  ( . "$SRC/lib/portable.sh"; eval "$(sed -n '/^watch() {/,/^}/p' "$SRC/lib/session.sh")"
    # shellcheck disable=SC2034 # LIVE, STUCK and SESSION_STUCK are read by watch(), defined by the eval
    LIVE=0.2 STUCK=1200 SESSION_STUCK=600; bash "$T/$CASE/session" "$T/$CASE/end" < /dev/null > /dev/null 2>&1 &
    watch $! "$w.out" "$w.live" build claude-sonnet-5-5 ) > "$T/$CASE/run.out" 2>&1 & LIVERUN=$!
  wait_until "jq -e '$2' '$w.live' > /dev/null" "cat '$w.live'" || fail "the live record did not read the stream: $(cat "$w.live" 2>&1)"
  cp "$w.live" "$T/$CASE/live"; [ "${3:-}" = keep ] || { : > "$T/$CASE/end"; wait $LIVERUN; }
  jq -cRn --arg m claude-sonnet-5-5 --arg e "" --argjson s 0 "$(<"$SRC/jq/sessionread.jq")" "$w.out" | tail -n 1 > "$T/$CASE/read"
}
# #1444 (R298). Bug it catches: on a route whose answers report less than its results (#391: usage 0 on every answer),
# the live usage was the results' sum alone once that was the larger, so an answer after the last result (a second
# turn, cut off) was left out of the live tokens, though the step's line counts it when the step ends.
t_zerousagetail() {
  local s=$T/$CASE.stream
  { jq -cn '{type: "assistant", message: {id: "m1", model: "claude-sonnet-5-5", content: [{type: "text", text: "x"}], usage: {input_tokens: 0, output_tokens: 0}}}'
    jq -cn '{type: "result", is_error: false, usage: {input_tokens: 1000000, cache_creation_input_tokens: 0, cache_read_input_tokens: 0, output_tokens: 0}}'
    jq -cn '{type: "assistant", message: {id: "m2", model: "claude-sonnet-5-5", content: [{type: "text", text: "y"}], usage: {input_tokens: 2000, cache_creation_input_tokens: 0, cache_read_input_tokens: 0, output_tokens: 30}}}'
  } > "$s"
  livestream "$s" '.id == "m2"'
  [ "$(jq -c '.usage | [.input, .output]' "$T/$CASE/live")" = '[1002000,30]' ] && [ "$(jq -cS .usage "$T/$CASE/live")" = "$(jq -cS .usage "$T/$CASE/read")" ] \
    || fail "the live usage left out the answer after the result, which the step's line counts: live $(jq -c .usage "$T/$CASE/live"), at the end $(jq -c .usage "$T/$CASE/read")"
}
# #1444 (R297). Bug it catches: a session whose result says two models ran it (modelUsage: Opus and Haiku, launched on
# Sonnet) had its live tokens priced at the model it was launched on; the step's line, when it ends, prices each
# model's own tokens. The live record keeps the same split by model as the step's line, and the card's cost while the
# step runs is that split priced (the snapshot, through the Board's pricing, dashboard_limit.py).
t_zerousagemodels() {
  local s=$T/$CASE.stream mu want b
  mu='{"inputTokens": 1000000, "outputTokens": 0, "cacheReadInputTokens": 0, "cacheCreationInputTokens": 0}'
  { jq -cn '{type: "assistant", message: {id: "m1", model: "claude-opus-5-5", content: [{type: "text", text: "x"}], usage: {input_tokens: 1000000, cache_creation_input_tokens: 0, cache_read_input_tokens: 0, output_tokens: 0}}}'
    jq -cn '{type: "assistant", message: {id: "m2", model: "claude-haiku-5-5", content: [{type: "text", text: "y"}], usage: {input_tokens: 1000000, cache_creation_input_tokens: 0, cache_read_input_tokens: 0, output_tokens: 0}}}'
    jq -cn --argjson u "$mu" '{type: "result", is_error: false, usage: {input_tokens: 2000000, cache_creation_input_tokens: 0, cache_read_input_tokens: 0, output_tokens: 0},
      modelUsage: {"claude-opus-5-5": $u, "claude-haiku-5-5": $u}}'
  } > "$s"
  livestream "$s" '.id == "m2"' keep
  [ "$(jq -cS .stats.byModel "$T/$CASE/live")" = "$(jq -cS .stats.byModel "$T/$CASE/read")" ] && [ "$(jq -c '.stats.byModel | keys' "$T/$CASE/live")" = '["claude-haiku-5-5","claude-opus-5-5"]' ] \
    || fail "the live record does not keep the result's split by model, as the step's line does: live $(jq -c .stats "$T/$CASE/live"), at the end $(jq -c .stats.byModel "$T/$CASE/read")"
  want=$(python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import dashboard_limit as d; print(round(d.PRICES["claude-opus-5-5"][0] + d.PRICES["claude-haiku-5-5"][0], 4))' "$SRC/../.claude/scripts")
  b=$(loop snapshot --fresh | jq -r '.belt[] | select(.card == "c7-7") | .usd')
  : > "$T/$CASE/end"; wait "$LIVERUN"
  [ -n "$want" ] && [ "$b" = "$want" ] || fail "the running step is not priced at each model's rate (Opus and Haiku, 1M input tokens each): $b, not $want"
}
# #1444 (R297, review E2). Bug it catches: the split by model was read only from a result whose usage could be read,
# so a session whose first result has readable usage and no split, and whose last result has the Opus and Sonnet split
# but no readable usage (t_metricspartial's stream), kept no split live and was priced at the model it was launched on;
# the step's line, when it ends, keeps the last result's split. The answer m3 after it marks the stream read.
t_zerousagesplit() {
  local s=$T/$CASE.stream
  { jq -cn '{type: "assistant", message: {id: "m1", model: "claude-opus-5-5", usage: {input_tokens: 5, output_tokens: 1}}}'
    jq -cn '{type: "assistant", message: {id: "m2", model: "claude-sonnet-5-5", usage: {input_tokens: 5, output_tokens: 1}}}'
    jq -cn '{type: "result", is_error: false, usage: {input_tokens: 10, cache_creation_input_tokens: 500, cache_read_input_tokens: 0, output_tokens: 2}}'
    jq -cn '{type: "result", is_error: false, usage: "n/a", modelUsage: {"claude-opus-5-5": {inputTokens: 5, outputTokens: 1, cacheCreationInputTokens: 400},
      "claude-sonnet-5-5": {inputTokens: 5, outputTokens: 1, cacheCreationInputTokens: 100}}}'
    jq -cn '{type: "assistant", message: {id: "m3", model: "claude-opus-5-5", usage: {input_tokens: 7, output_tokens: 3}}}'
  } > "$s"
  livestream "$s" '.id == "m3"'
  [ "$(jq -c '.stats.byModel | keys' "$T/$CASE/live")" = '["claude-opus-5-5","claude-sonnet-5-5"]' ] && [ "$(jq -cS .stats.byModel "$T/$CASE/live")" = "$(jq -cS .stats.byModel "$T/$CASE/read")" ] \
    || fail "the live record does not keep the last result's split by model (its usage unreadable), as the step's line does: live $(jq -c .stats "$T/$CASE/live"), at the end $(jq -c .stats.byModel "$T/$CASE/read")"
}
# Issue 1524: a build session worked 18 minutes, its output whole when it ended, and health read no live output for
# it. Card c7-7's build session, watched by the engine's own watch() with no card run, writes a line that reads as
# JSON but is no event (a number), then, once its live record is made, its answer. watch()'s jq fails once, at its
# first look (as one can on a loaded machine). Bugs it catches, each alone: that first failure left watch() with no
# state, every later look failed on it, and no live record was ever made; the number line failed the look that read
# it and each look after, which read it again, so the live record never named the answer after it.
t_livewedge() {
  local w=$T/$CASE/cards/c7-7 run r; setup "[$(issue 7 2026-01-01)]"; mkdir -p "$T/$CASE/cards"
  cat > "$T/$CASE/session" <<'EOF'
echo 42
until [ -s "$1.live" ] || [ -e "$2" ]; do sleep 0.1; done # sleep: the answer comes once watch() has made the live record
echo '{"type":"assistant","message":{"id":"m1","content":[{"type":"tool_use","name":"Bash","input":{"command":"make"}}],"usage":{"input_tokens":10,"output_tokens":1}}}'
until [ -e "$2" ]; do sleep 0.1; done # sleep: a session that runs until the case ends it
EOF
  ( . "$SRC/lib/portable.sh"; eval "$(sed -n '/^watch() {/,/^}/p' "$SRC/lib/session.sh")"
    # shellcheck disable=SC2034 # LIVE, STUCK and SESSION_STUCK are read by watch(), defined by the eval
    LIVE=0.2 STUCK=1200 SESSION_STUCK=600
    jq() { [ -e "$T/$CASE/failed" ] || { : > "$T/$CASE/failed"; return 1; }; command jq "$@"; } # the first jq watch() runs fails
    bash "$T/$CASE/session" "$w" "$T/$CASE/end" > "$w.out" 2> /dev/null < /dev/null &
    watch $! "$w.out" "$w.live" build claude-sonnet-5-5 ) > "$T/$CASE/run.out" 2>&1 & run=$!
  wait_until "jq -e '.id == \"m1\" and .action == \"Bash: make\" and (.last | type) == \"string\"' '$w.live' > /dev/null" "cat '$w.live'"; r=$?
  cp "$w.live" "$T/$CASE/live" 2>/dev/null; : > "$T/$CASE/end"; wait "$run"
  [ -e "$T/$CASE/failed" ] || fail "watch() ran no jq for the stand-in to fail: $(cat "$T/$CASE/run.out")"
  [ $r = 0 ] || fail "the live record did not name the answer after a failed first look and a number line ($(head -c 300 "$w.out" 2>/dev/null)): $(cat "$T/$CASE/live" 2>&1)"
}
