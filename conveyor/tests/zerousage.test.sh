#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a Claude session whose stream gives every answer usage 0 (a route that reports usage only in its
# result line, #391): its card says its cost is shown when the step ends, and shows the cost once the result comes.
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
    # shellcheck disable=SC2034 # LIVE and STUCK are read by watch(), defined by the eval
    LIVE=0.2 STUCK=1200; bash "$STUB/zero-cmd" > "$w.out" 2>&1 < /dev/null &
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
  b=$(loop snapshot | jq -c '.belt[] | select(.card == "c7-7") | [.reading, .atEnd, (.usd | type == "number" and . > 0)]')
  [ "$b" = '[true,false,true]' ] || fail "the card does not show its cost once the result line arrived: $b $(cat "$w.live")"
  : > "$STUB/end"; wait $run || fail "the watch exited non-zero: $(cat "$T/$CASE/run.out")"
}
