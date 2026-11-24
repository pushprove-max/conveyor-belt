#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: measurements of a review stopped while it ran, of a card restarted, and of a test run's counts. The
# record line helper is metrics.test.sh's l().
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# A review stopped before its turn completed: what it used is the running total its session file holds.
# serve ends at its own time limit, here and in the two cases below: each wait is for what it does, until that is
# there or serve has ended.
t_metricsstopreview() {
  export TZ=UTC; setup "$(issue 7 2026-01-01 area:billing | jq -cs .)"; S=$ST
  export CODEX_HOME=$T/$CASE/codex; mkdir -p "$CODEX_HOME/sessions/d"
  cat > "$STUB/review-cmd" <<'EOF'
echo '{"type":"thread.started","thread_id":"th1"}'
echo '{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":400,"output_tokens":50}}}}' > "$CODEX_HOME/sessions/d/rollout-1-th1.jsonl"
sleep 60 & echo $! > "$STUB/sleeper"; : > "$STUB/reviewing"; wait # sleep: the review's child, there to be stopped with it
EOF
  tune '.tunables.idle = 1 | .tunables.poll = 1'
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    exec timeout 120 bash "$SRC/conveyor.sh" serve > "$STUB/serve.out" 2>&1 ) & pid=$!; trap 'kill $pid 2>/dev/null' EXIT
  until [ -e "$STUB/reviewing" ] || ! kill -0 $pid 2>/dev/null; do sleep 0.1; done;[ -e "$STUB/reviewing" ] || fail "serve did not start the review: $(cat "$STUB/serve.out")"
  card=$(st 'select(.step == "picked") | .card'); loop control stop >/dev/null
  until [ -n "$(jq -r --arg c "$card" 'select(.card == $c and .step == "review") | .card' "$S/retried.jsonl" 2>/dev/null)" ] || ! kill -0 $pid 2>/dev/null; do sleep 0.1; done
  kill $pid; wait $pid 2>/dev/null; kill "$(cat "$STUB/sleeper")" 2>/dev/null; unset CODEX_HOME
  [ "$(jq -c --arg c "$card" 'select(.card == $c and .step == "review") | [.result, .tokens.codex, .usage, .model]' "$S/retried.jsonl")" = '["stopped",650,{"input":600,"read":400,"output":50},"x"]' ] \
    || fail "the stopped review's spend is not recorded: $(jq -c --arg c "$card" 'select(.card == $c)' "$S/retried.jsonl") $(cat "$STUB/serve.out")"
  [ ! -e "$T/$CASE/codex/sessions/d/rollout-1-th1.jsonl" ] || fail "the stopped review's session file was left behind"
}

# Bug: an OpenCode review stopped while it ran is read as a Codex one: the usage and cost its finished steps
# reported are lost, and the stopped line is unpriced.
t_metricsstopopencode() {
  export TZ=UTC; setup "$(issue 7 2026-01-01 area:billing | jq -cs .)"; S=$ST
  tune '.tunables.idle = 1 | .tunables.poll = 1 | .models.allowed.opencode = ["opencode:prov/m-1"]'
  seatset reviewer opencode:prov/m-1
  # `opencode models` (the host's report, read before the seat starts: seatready()) is no review: it lists the one model.
  cat > "$STUB/opencode" <<'EOF'
#!/usr/bin/env bash
[ "$1" != models ] || { echo prov/m-1; exit 0; }
cat > /dev/null
echo '{"type":"step_start","timestamp":1,"sessionID":"s","part":{"type":"step-start"}}'
echo '{"type":"step_finish","timestamp":1,"sessionID":"s","part":{"type":"step-finish","reason":"tool-calls","cost":0.25,"tokens":{"input":600,"output":40,"reasoning":10,"cache":{"read":400,"write":0}}}}'
sleep 60 & echo $! > "$STUB/sleeper"; : > "$STUB/reviewing"; wait # sleep: the review's child, there to be stopped with it
EOF
  chmod +x "$STUB/opencode"
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    exec timeout 120 bash "$SRC/conveyor.sh" serve > "$STUB/serve.out" 2>&1 ) & pid=$!; trap 'kill $pid 2>/dev/null' EXIT
  until [ -e "$STUB/reviewing" ] || ! kill -0 $pid 2>/dev/null; do sleep 0.1; done; [ -e "$STUB/reviewing" ] || fail "serve did not start the review: $(cat "$STUB/serve.out")"
  card=$(st 'select(.step == "picked") | .card'); loop control stop >/dev/null
  until [ -n "$(jq -r --arg c "$card" 'select(.card == $c and .step == "review") | .card' "$S/retried.jsonl" 2>/dev/null)" ] || ! kill -0 $pid 2>/dev/null; do sleep 0.1; done
  kill $pid; wait $pid 2>/dev/null; kill "$(cat "$STUB/sleeper")" 2>/dev/null
  # Its cost is in its usage (usage.cost), where the Board prices an OpenCode step from: anywhere else it is unpriced.
  [ "$(jq -c --arg c "$card" 'select(.card == $c and .step == "review") | [.result, .tokens.codex, .usage, .cost, .model]' "$S/retried.jsonl")" \
    = '["stopped",650,{"input":600,"write":0,"read":400,"output":50,"cost":0.25},null,"opencode:prov/m-1"]' ] \
    || fail "the stopped OpenCode review's spend is not recorded: $(jq -c --arg c "$card" 'select(.card == $c)' "$S/retried.jsonl") $(cat "$STUB/serve.out")"
}

# Bug: a review that failed after spending tokens and was stopped while it ran again lost the first attempt: its
# events were replaced by the second's, so the stopped line held neither its reason nor its tokens.
t_metricsstopretry() {
  export TZ=UTC; setup "$(issue 7 2026-01-01 area:billing | jq -cs .)"; S=$ST
  cat > "$STUB/review-cmd" <<'EOF'
echo '{"type":"turn.completed","usage":{"input_tokens":100,"cached_input_tokens":60,"output_tokens":7}}'
[ "$(wc -l < "$STUB/reviews")" != 1 ] || exit 3
sleep 60 & echo $! > "$STUB/sleeper"; : > "$STUB/reviewing"; wait # sleep: the review's child, there to be stopped with it
EOF
  tune '.tunables.idle = 1 | .tunables.poll = 1'
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    exec timeout 120 bash "$SRC/conveyor.sh" serve > "$STUB/serve.out" 2>&1 ) & pid=$!; trap 'kill $pid 2>/dev/null' EXIT
  until [ -e "$STUB/reviewing" ] || ! kill -0 $pid 2>/dev/null; do sleep 0.1; done;[ -e "$STUB/reviewing" ] || fail "serve did not run the review again: $(cat "$STUB/serve.out")"
  card=$(st 'select(.step == "picked") | .card'); loop control stop >/dev/null
  until [ -n "$(jq -r --arg c "$card" 'select(.card == $c and .step == "review") | .card' "$S/retried.jsonl" 2>/dev/null)" ] || ! kill -0 $pid 2>/dev/null; do sleep 0.1; done
  kill $pid; wait $pid 2>/dev/null; kill "$(cat "$STUB/sleeper")" 2>/dev/null
  [ "$(jq -c --arg c "$card" 'select(.card == $c and .step == "review") | [.result, .tokens.codex, .usage.output, (.firstTry.reason | test("exit 3")), .firstTry.spent.tokens.codex]' "$S/retried.jsonl")" = '["stopped",94,14,true,47]' ] \
    || fail "the stopped retry lost the first attempt: $(jq -c --arg c "$card" 'select(.card == $c)' "$S/retried.jsonl") $(cat "$STUB/serve.out")"
  recok "$S/retried.jsonl" "the stopped retry"
  [ ! -e "$T/$CASE/cards/$card.firsttry" ] || fail "the first attempt's file was left behind"
}

# Bug: one stopped in the pause before the review ran again lost the first attempt's reason, and would have counted
# its tokens twice had its events stayed: the stopped line is the first attempt, once.
t_metricsstoppause() {
  export TZ=UTC; setup "$(issue 7 2026-01-01 area:billing | jq -cs .)"; S=$ST
  printf '%s\n' "echo '{\"type\":\"turn.completed\",\"usage\":{\"input_tokens\":100,\"cached_input_tokens\":60,\"output_tokens\":7}}'" 'exit 3' > "$STUB/review-cmd"
  tune '.tunables.idle = 1 | .tunables.poll = 1 | .tunables.reviewPause = 60'
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    exec timeout 120 bash "$SRC/conveyor.sh" serve > "$STUB/serve.out" 2>&1 ) & pid=$!; trap 'kill $pid 2>/dev/null' EXIT
  until compgen -G "$T/$CASE/cards/*.firsttry" >/dev/null || ! kill -0 $pid 2>/dev/null; do sleep 0.1; done
  compgen -G "$T/$CASE/cards/*.firsttry" >/dev/null || fail "serve did not pause before the review ran again: $(cat "$STUB/serve.out")"
  card=$(st 'select(.step == "picked") | .card')
  # Bug: stopped after the first attempt was kept but before its events went, both were read: 94 tokens for its 47.
  # Its events back, and the first attempt not yet renamed from .firsttry.new, stand in for that moment; both files
  # have one mtime, so file times cannot be what tells the first attempt's events from the second's.
  mv "$T/$CASE/cards/$card.firsttry" "$T/$CASE/cards/$card.firsttry.new"
  bash "$STUB/review-cmd" > "$T/$CASE/cards/$card.events" 2>/dev/null; touch -r "$T/$CASE/cards/$card.firsttry.new" "$T/$CASE/cards/$card.events"
  loop control stop >/dev/null
  until [ -n "$(jq -r --arg c "$card" 'select(.card == $c and .step == "review") | .card' "$S/retried.jsonl" 2>/dev/null)" ] || ! kill -0 $pid 2>/dev/null; do sleep 0.1; done
  kill $pid; wait $pid 2>/dev/null
  [ "$(jq -c --arg c "$card" 'select(.card == $c and .step == "review") | [.result, .tokens.codex, .usage.output, (.firstTry.reason | test("exit 3")), .firstTry.spent.tokens.codex, .unread]' "$S/retried.jsonl")" = '["stopped",47,7,true,47,null]' ] \
    || fail "the review stopped in its pause lost the first attempt: $(jq -c --arg c "$card" 'select(.card == $c)' "$S/retried.jsonl") $(cat "$STUB/serve.out")"
  recok "$S/retried.jsonl" "the review stopped in its pause"
  [ ! -e "$T/$CASE/cards/$card.firsttry" ] && [ ! -e "$T/$CASE/cards/$card.firsttry.new" ] || fail "the first attempt's file was left behind"
}

# A card restarted: issue 9's first run (card c9) was blocked after a build of 300 s and 2 reviews ($1.20: 400K and
# 2 x 100K input tokens at $2 a million) and `retry` moved it to the retried file; its second run (card c10) built for
# 200 s and had 1 review ($0.80), and is on the belt, or landed when the case passes "landed". $d and $now as
# t_metricstotals sets them. Not named runs: the runner sources every case file into one shell, and that is
# batchreuse.test.sh's helper (issue 607).
restartedruns() { # [landed]
  # shellcheck disable=SC2034 # y is read by l(), defined in metrics.test.sh
  local y=$d blk B='{"usage":{"write":0,"write1h":0,"read":0,"output":0},"model":"claude-sonnet-5-5"}' V='{"usage":{"read":0,"output":0},"counts":{"P0":0,"P1":0,"P2":0,"P3":0},"model":"gpt-6.1-sol"}'
  seatset model claude-sonnet-5-5; seatset reviewer gpt-6.1-sol
  tk() { jq -c --argjson n "$1" --arg k "$2" '.tokens = {claude: 0, codex: 0} | .tokens[$k] = $n | .usage.input = $n' <<<"$3"; }
  l 9 01:00 picked ok '{"title":"T9"}'; l 9 01:00 start ok '{"of":"build"}'; l 9 01:05 build ok "$(tk 400000 claude "$B")"
  l 9 01:10 review NO-GO "$(tk 100000 codex "$V")"; l 9 01:15 fix ok "$(tk 0 claude "$B")"; l 9 01:20 review NO-GO "$(tk 100000 codex "$V")"
  # The block's reason as card.sh writes it: "the fix for ", the finding cut to 300 characters, " did not hold after 1 round":
  # 339 characters, more than the 300 the snapshot once kept of an earlier run's reason, so its end was lost (#1540).
  blk="the fix for [P1] a.sh:1 $(printf 'word%02d ' $(seq 1 60))"; blk="${blk:0:312} did not hold after 1 round"
  l 9 01:21 blocked blocked "$(jq -nc --arg r "$blk" --arg t "${d}T01:30:00Z" '{reason: $r, retriedAt: $t}')"
  mv "$S/cards.jsonl" "$S/retried.jsonl"; : > "$S/cards.jsonl"
  l 9 02:00 picked ok '{"title":"T9","card":"c10"}'; l 9 02:00 start ok '{"card":"c10","of":"build"}'
  l 9 02:00 build ok "$(tk 300000 claude "$B" | jq -c --arg t "${d}T02:03:20Z" '. + {card: "c10", time: $t}')"
  l 9 02:10 review GO "$(tk 100000 codex "$V" | jq -c '.card = "c10"')"
  [ "${1:-}" != landed ] || { l 9 02:15 test pass '{"card":"c10","usage":{"input":0,"write":0,"write1h":0,"read":0,"output":0}}'; l 9 02:20 landed ok '{"card":"c10","sha":"s9","product":false}'; }
  recok "$S/cards.jsonl" "the restarted card's fixture"; recok "$S/retried.jsonl" "the restarted card's fixture"
  out=$(CONVEYOR_NOW=$now loop snapshot --fresh) || fail "snapshot of the restarted card exited non-zero"
}

# Bug: a restarted card's price and figures were its last run's only ($0.80, 1 review, a 200 s build): the $1.20 of
# its first run, in the retried file, was in the day's total but not on the card.
t_metricsruns() {
  export TZ=UTC; setup '[]'; S=$ST; mkdir -p "$S"; d=$(date -u +%F); now=$(date -u -d "${d}T23:59:00Z" +%s); restartedruns
  [ "$(jq -c '.belt[] | select(.issue == 9) | [.card, .usd, (.metrics | .usd, .reviews, .buildSec, .runs, .thisRun.usd, .thisRun.reviews, .thisRun.buildSec)]' <<<"$out")" \
    = '["c10",2,2,3,500,2,0.8,1,200]' ] || fail "the restarted card's figures: $(jq -c '.belt' <<<"$out")"
  # Bug: the fix of the first run was in no count the card showed: fixes are those of both runs, thisRun its own.
  [ "$(jq -c '.belt[] | select(.issue == 9) | [.metrics.fixes, .metrics.thisRun.fixes, .priorSec, (.earlier | length)]' <<<"$out")" = '[1,0,1260,1]' ] \
    || fail "the restarted card's fixes and earlier run: $(jq -c '.belt' <<<"$out")"
  # Bug (#1540): the first run's reason, from the retried file, was cut to 300 characters: "did not hold after 1 round" was lost.
  [ "$(jq -c '.belt[] | select(.issue == 9) | .earlier[0].reason | [length, startswith("the fix for [P1] a.sh:1 word01"), endswith(" did not hold after 1 round")]' <<<"$out")" = '[339,true,true]' ] \
    || fail "the earlier run's reason lost its end: $(jq -c '.belt[] | select(.issue == 9) | .earlier' <<<"$out")"
}

# Bugs: the landed card's cost row, and the per-landed averages, left out its first run's $1.20; or the week's total
# counted that run twice (it is $2, each step once). The run before the retry is no row of its own.
t_metricsrunslanded() {
  export TZ=UTC; setup '[]'; S=$ST; mkdir -p "$S"; d=$(date -u +%F); now=$(date -u -d "${d}T23:59:00Z" +%s); restartedruns landed
  [ "$(jq -c '[(.landed[] | [.card, .usd, .reviews]), .cost.perLanded, .cost.week, (.cost.cards | map([.card, .runs, .week])), .metrics.week.perLanded.usd]' <<<"$out")" \
    = '[["c10",2,3],2,2,[["c10",2,2]],2]' ] || fail "the landed restarted card's cost: $(jq -c '[.landed, .cost, .metrics.week.perLanded]' <<<"$out")"
  # Bug: its overall time was its last run's (1200 s) and "Every step" had no earlier run: both runs are 2460 s, and
  # the first run's 300 s build is in its earlier track.
  [ "$(jq -c '.landed[] | [.totalSec, .priorSec, (.earlier | map([.sec, (.track.steps[] | select(.name == "Build") | .sec)]))]' <<<"$out")" = '[2460,1260,[[1260,300]]]' ] \
    || fail "the landed restarted card's times: $(jq -c '.landed[] | {totalSec, priorSec, earlier}' <<<"$out")"
}

# A test run whose root half gives no totals: the counts are missing, not the web half's alone. The counts are
# testcounts()'s (lib/records.sh), which the test line holds; t_metrics runs a whole card's test step.
t_metricstests() {
  local o=$T/$CASE/test.out; mkdir -p "$T/$CASE"
  printf '%s\n' 'test-changed: 2 root test file(s) selected from 1 changed file(s)' 'test-changed: root totals unavailable' \
    'test-changed: 1 web test file(s) selected' 'test-changed: web totals: Test Files  1 passed (1); Tests  4 passed (4)' > "$o"
  eval "$(sed -n '/^testcounts() {/,/^}/p' "$SRC/lib/records.sh")"
  [ "$(testcounts "$o")" = '{"files":3,"total":null,"passed":null,"failed":null,"skipped":null}' ] || fail "a run with no root totals: $(testcounts "$o")"
  # Both halves with totals, the web line in colour: the files, tests and skips of root and web are summed (a colour
  # code left in, or one half's count dropped, gives other numbers).
  { printf '%s\n' 'test-changed: 2 root test file(s) selected from 1 changed file(s)' 'test-changed: 1 web test file(s) selected' \
      'test-changed: root totals: tests 7, pass 6, fail 0, cancelled 0, skipped 1, todo 0'
    printf '\033[32mtest-changed: web totals: Test Files  1 passed (1); Tests  4 passed | 1 skipped (5)\033[0m\n'; } > "$o"
  [ "$(testcounts "$o")" = '{"files":3,"total":12,"passed":10,"failed":0,"skipped":2}' ] || fail "a run with both totals: $(testcounts "$o")"
}
