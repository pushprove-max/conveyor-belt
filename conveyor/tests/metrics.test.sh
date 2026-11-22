#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: measurements.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bugs: a measurement the session, the review or the test run gives is not recorded (turns, API seconds, tool
# calls, refused calls, cache hits, the models that ran; a review's seconds and tool calls; tests selected, passed,
# failed and skipped), nor the card's diff, depth, weekly limit before and after, the push's seconds or the loop's
# samples; the snapshot's totals differ from the ones worked out by hand; a step recorded before the token split is
# left unpriced, so the week's and the per-landed dollars are null; a record with none of the new fields stops
# checking or rendering, or shows a reading it never took as 0.
t_metrics() {
  export TZ=UTC; setup "$(issue 7 2026-01-01 area:billing | jq -c '[.body = "body\nFollow-up depth: 1"]')"; S=$ST; mkdir -p "$S"
  echo "$GO" > "$STUB/review.1"
  jq -cn '{time: (now | todate), pct: 40}' > "$S/limit.jsonl"
  # The stream the shared claude stub's session prints, and the events after the shared codex stub's review (tests/stubs/).
  bash > "$STUB/claude-usage" <<'EOF'
echo '{"type":"assistant","message":{"id":"a1","content":[{"type":"tool_use","name":"Bash"},{"type":"tool_use","name":"Read"}],"usage":{"input_tokens":5,"output_tokens":2}}}'
echo '{"type":"assistant","message":{"id":"a2","content":[{"type":"text","text":"x"},{"type":"tool_use","name":"Bash"}],"usage":{"input_tokens":5,"output_tokens":3}}}'
echo '{"type":"result","is_error":false,"num_turns":3,"duration_ms":4000,"duration_api_ms":2600,"permission_denials":[{"tool_name":"Bash"}],"modelUsage":{"claude-opus-5-5":{}},"usage":{"input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":970,"output_tokens":5}}'
EOF
  bash > "$STUB/codex-usage" <<'EOF'
echo '{"type":"item.completed","item":{"type":"command_execution"}}'; echo '{"type":"item.completed","item":{"type":"command_execution"}}'
echo '{"type":"item.completed","item":{"type":"agent_message"}}'
echo '{"type":"turn.completed","usage":{"input_tokens":100,"cached_input_tokens":60,"output_tokens":7}}'
EOF
  cat > "$STUB/test-cmd" <<'EOF'
echo 'test-changed: 2 root test file(s) selected from 1 changed file(s)'; echo 'test-changed: 1 web test file(s) selected'
echo 'test-changed: root totals: tests 7, pass 6, fail 0, cancelled 0, skipped 1, todo 0'
printf '\033[32mtest-changed: web totals: Test Files  1 passed (1); Tests  4 passed | 1 skipped (5)\033[0m\n'
jq -cn '{time: (now | todate), pct: 42.5}' >> "$ST/limit.jsonl"
EOF
  # loop: the records only a card writes are checked here (its worktree, brief, landed and pushed lines, the review's and the test run's measurements on them, the loop's samples)
  loop run >/dev/null || fail "run exited non-zero"
  [ "$(st 'select(.step == "build") | [.stats, (.sec | type)] | tojson')" = '[{"turns":3,"apiSec":3,"tools":{"Bash":2,"Read":1},"refused":1,"cacheHit":0.97,"models":["claude-opus-5-5"],"byModel":{"claude-opus-5-5":{"input":0,"write":0,"read":0,"output":0}}},"number"]' ] \
    || fail "the build's session stats: $(st 'select(.step == "build")')"
  [ "$(st 'select(.step == "review") | [.result, .counts, .model, (.sec | type), .stats] | tojson')" = '["GO",{"P0":0,"P1":0,"P2":0,"P3":0},"x","number",{"turns":1,"tools":{"command_execution":2}}]' ] \
    || fail "the review's measurements: $(st 'select(.step == "review")')"
  [ "$(st 'select(.step == "test") | .tests | tojson')" = '{"files":3,"total":12,"passed":10,"failed":0,"skipped":2}' ] || fail "the test run's counts: $(st 'select(.step == "test")')"
  [ "$(st 'select(.step | IN("worktree", "brief", "landed")) | [.step, .limit, .depth, .diff] | tojson' | tr '\n' ' ')" \
    = '["worktree",40,null,null] ["brief",null,1,null] ["landed",42.5,null,{"files":1,"added":1,"removed":0}] ' ] || fail "limit, depth or diff: $(st 'select(.step | IN("worktree", "brief", "landed"))')"
  [ "$(st 'select(.step == "pushed") | .sec | type')" = number ] || fail "the push's seconds: $(st 'select(.step == "pushed")')"
  [ "$(jq -sc 'map(select(.slots == 0 and .cap == 5 and .state == "running" and (.load | type) == "number" and (.queued | type) == "number" and (keys == ["cap","diskFreeKb","load","memTotalKb","memUsedKb","queued","slots","state","time"]))) | length > 0' "$S/samples.jsonl")" = true ] \
    || fail "the loop's samples: $(cat "$S/samples.jsonl")"
  recok "$S/cards.jsonl" "a card run with every new field"
  out=$(loop snapshot --fresh) || fail "snapshot exited non-zero"
  [ "$(jq -c '.landed[0].metrics | [.depth, .diff.files, .limit, .reviews, .firstReview, (.timeline | map([.step, .sec != null, .model]))]' <<<"$out")" \
    = '[1,1,{"before":40,"after":42.5,"used":2.5},1,"GO",[["build",true,"claude-opus-5-5"],["review",true,"x"],["test",true,null]]]' ] || fail "the landed card's metrics: $(jq -c '.landed[0].metrics' <<<"$out")"
}

# The cases below were one with this, each part on a main of its own: apart, they run side by side.
# A line of card c<issue>'s record at <hh:mm> of the day $y (the case sets it), written to the case's records.
l() { # <issue> <hh:mm> <step> <result> [extra json]
  jq -cn --arg c "c$1" --argjson i "$1" --arg s "$3" --arg t "${y}T$2:00Z" --arg r "$4" --argjson x "${5:-{\}}" \
    '{card:$c,issue:$i,step:$s,time:$t,tokens:{claude:0,codex:0},result:$r,sha:"",reason:""} * $x' >> "$ST/cards.jsonl"
}

# The totals, against a fixture worked out by hand. Sessions $2, reviews $1 (1M and 500K input tokens at $2 a million).
t_metricstotals() {
  export TZ=UTC; setup '[]'; S=$ST; mkdir -p "$S"; d=$(date -u +%F)
  now=$(date -u -d "${d}T23:59:00Z" +%s)
  seatset model claude-sonnet-5-5; seatset reviewer gpt-6.1-sol
  B='{"tokens":{"claude":1000000,"codex":0},"usage":{"input":1000000,"write":0,"write1h":0,"read":0,"output":0},"model":"claude-sonnet-5-5"}'
  V='{"tokens":{"claude":0,"codex":500000},"usage":{"input":500000,"read":0,"output":0},"counts":{"P0":0,"P1":0,"P2":0,"P3":0},"model":"gpt-6.1-sol"}'
  Z='{"usage":{"input":0,"write":0,"write1h":0,"read":0,"output":0}}'
  l() { # <issue> <hh:mm> <step> <result> [extra json]
    jq -cn --arg c "c$1" --argjson i "$1" --arg s "$3" --arg t "${d}T$2:00Z" --arg r "$4" --argjson x "${5:-{\}}" \
      '{card:$c,issue:$i,step:$s,time:$t,tokens:{claude:0,codex:0},result:$r,sha:"",reason:""} * $x' >> "$S/cards.jsonl"
  }
  # Card 1: opened 00:00, picked 01:00, a NO-GO with 3 findings, a fix, a GO, the tests, landed 01:36, pushed 01:40.
  l 1 01:00 picked ok "{\"title\":\"T1\",\"created\":\"${d}T00:00:00Z\"}"; l 1 01:00 worktree ok '{"limit":10}'; l 1 01:00 brief ok '{"depth":0}'
  l 1 01:00 start ok '{"of":"build"}'; l 1 01:10 build ok "$B"; l 1 01:10 start ok '{"of":"review"}'
  l 1 01:15 review NO-GO "$(jq -c '.counts = {"P0":0,"P1":2,"P2":1,"P3":0}' <<<"$V")"; l 1 01:15 start ok '{"of":"fix"}'; l 1 01:25 fix ok "$B"
  l 1 01:25 start ok '{"of":"review"}'; l 1 01:30 review GO "$V"; l 1 01:30 start ok '{"of":"test"}'; l 1 01:35 test pass "$Z"
  l 1 01:35 start ok '{"of":"land"}'; l 1 01:36 landed ok '{"sha":"s1","product":false,"limit":12,"diff":{"files":2,"added":30,"removed":4}}'
  l 1 01:40 pushed ok '{"sha":"s1","sec":30}'
  # Card 2: opened 00:00, picked 02:00, a GO, landed 02:21 with a follow-up; a push that failed after 900 s.
  # The weekly limit reset during it (80 before, 1 after): what it took is not known, so not -79.
  l 2 02:00 picked ok "{\"title\":\"T2\",\"created\":\"${d}T00:00:00Z\"}"; l 2 02:00 worktree ok '{"limit":80}'; l 2 02:10 build ok "$B"; l 2 02:15 review GO "$V"; l 2 02:20 test pass "$Z"
  l 2 02:21 landed ok '{"sha":"s2","product":false,"leftover":true,"followups":[100101],"limit":1}'; l 2 02:30 push fail '{"sha":"s2","sec":900}'
  # Card 3: blocked on a session's timeout. Card 4: blocked for the owner's yes to a visible change.
  l 3 03:00 picked ok "{\"title\":\"T3\",\"created\":\"${d}T02:50:00Z\"}"; l 3 03:10 build ok "$B"
  # Its fix session timed out after 60 s and 1M input tokens: the blocked line holds what it spent, priced ($2).
  l 3 03:11 blocked blocked '{"reason":"fix: session failed (exit 124; 124 is the 3600s timeout): x","tokens":{"claude":1000000,"codex":0},"spent":{"step":"fix","tokens":{"claude":1000000},"usage":{"input":1000000,"write":0,"write1h":0,"read":0,"output":0},"model":"claude-sonnet-5-5","sec":60}}'
  # Its review, by Claude, and its judge wrote cache: the snapshot's steps keep those writes (a Claude reviewer or judge
  # keeps no transcript), which the Board's cache-write alert reads.
  J='{"model":"claude-haiku-5-5","effort":"low","sec":5,"tokens":{"claude":20},"usage":{"input":1,"write":7,"write1h":3,"read":0,"output":9}}'
  l 4 04:00 picked ok '{"title":"T4"}'; l 4 04:10 build ok "$B"; l 4 04:15 review GO "$(jq -c --argjson j "$J" '.judge = $j | .model = "claude-sonnet-5-5" | .usage += {write: 11, write1h: 0}' <<<"$V")"; l 4 04:16 blocked blocked "{\"reason\":\"visible to customers or staff: needs Dana's yes: a button\"}"
  # Card 6, on the belt: a build recorded before the token split and the model (its fresh tokens only).
  l 6 06:00 picked ok '{"title":"T6"}'; l 6 06:10 build ok '{"tokens":{"claude":500000,"codex":0}}'
  # Card 5: blocked yesterday at 22:00 and still blocked: today it waits on the owner from midnight only.
  y=$(date -u -d "$d 1 day ago" +%F)
  for x in 'picked ok {"title":"T5"}' 'blocked blocked {"reason":"review 1: no answer"}'; do read -r st rs ex <<<"$x"
    jq -cn --arg s "$st" --arg r "$rs" --arg t "${y}T22:00:00Z" --argjson x "$ex" '{card:"c5",issue:5,step:$s,time:$t,tokens:{claude:0,codex:0},result:$r,sha:"",reason:""} * $x' >> "$S/cards.jsonl"
  done
  # The loop's samples: 4 of 4 slots at 00:30, 2 at 00:31, none (paused, 2 issues queued) at 05:00, 1 at 05:01.
  for x in "00:30 4 running 3" "00:31 2 running 3" "05:00 0 paused 2" "05:01 1 running 1"; do read -r t n m k <<<"$x"
    jq -cn --arg t "${d}T$t:00Z" --argjson n "$n" --arg m "$m" --argjson k "$k" '{time:$t,slots:$n,cap:4,state:$m,queued:$k,load:($n + 0.5),memUsedKb:1000,memTotalKb:4000,diskFreeKb:(9000 - $n)}' >> "$S/samples.jsonl"
  done
  # One push that carried two cards, its pushed lines a second apart (written in turn): one push, its seconds once.
  # The line with no head (written before heads were) is a push of its own, told apart by its time.
  for x in "c2 2 02:50:59" "c1 1 02:51:00"; do read -r c i t <<<"$x"
    jq -cn --arg c "$c" --argjson i "$i" --arg t "${d}T${t}Z" '{card:$c,issue:$i,step:"pushed",time:$t,tokens:{claude:0,codex:0},result:"ok",sha:"",reason:"",sec:50,head:"h2"}' >> "$S/cards.jsonl"
  done
  # The 7 days before those, for the change the Board shows: a card landed 9 days ago is in them, never in the week.
  p=$(date -u -d "$d 9 days ago" +%F)
  for x in 'picked 10:00 {"title":"T9"}' 'landed 10:30 {"sha":"s9","product":false}'; do read -r st t ex <<<"$x"
    jq -cn --arg s "$st" --arg t "${p}T$t:00Z" --argjson x "$ex" '{card:"c9",issue:9,step:$s,time:$t,tokens:{claude:0,codex:0},result:"ok",sha:"",reason:""} * $x' >> "$S/cards.jsonl"
  done
  recok "$S/cards.jsonl" "the fixture"
  # The snapshot is taken late in the fixture's day, so its steps are all past whatever the hour the test runs at.
  out=$(CONVEYOR_NOW=$now loop snapshot --fresh) || fail "snapshot of the fixture exited non-zero"
  q() { jq -c "$1" <<<"$out"; }
  [ "$(q '.metrics.today | del(.waitMaxSec, .pushes)')" = '{"cards":4,"landed":2,"blocked":2,"leadSec":{"p50":7110,"p90":8460},"cycleSec":{"p50":1710,"p90":2160},"firstReviewPass":0.667,"findingsPerCard":1,"followupRate":0.5,"blockRate":0.5,"blocks":{"timeout":1,"visible change":1},"rebuildRate":0,"testFailures":{"card":0,"main":0,"flaky":0,"mainSec":0},"perLanded":{"usd":4.5,"leftOut":0,"tokens":2250000,"tokensLeftOut":0,"byModel":{"claude-sonnet-5-5":{"usd":3,"leftOut":0,"tokens":1500000,"tokensLeftOut":0},"gpt-6.1-sol":{"usd":1.5,"leftOut":0,"tokens":750000,"tokensLeftOut":0}}},"limitPerCard":2,"loop":{"samples":4,"utilisation":0.438,"slotsMax":4,"idleSec":60,"idleUnreadSec":0,"heldSec":60},"host":{"loadMax":4.5,"memUsedMaxKb":1000,"diskFreeMinKb":8996}}' ] \
    || fail "today's totals: $(q '.metrics.today')"
  # Waiting on the owner: the blocked cards, each from its end to the snapshot's time, clipped to the window: card 5,
  # blocked yesterday, counts from midnight today and from its end in the 7 days.
  [ "$(q '(.time | fromdate) as $n | .metrics.today.waitMaxSec == ($n - ("'"$d"'T03:11:00Z" | fromdate)) + ($n - ("'"$d"'T04:16:00Z" | fromdate)) + ($n - ("'"$d"'T00:00:00Z" | fromdate))')" = true ] \
    || fail "time waiting on the owner today: $(q .metrics.today.waitMaxSec)"
  [ "$(q '(.time | fromdate) as $n | .metrics.week.waitMaxSec == ($n - ("'"$d"'T03:11:00Z" | fromdate)) + ($n - ("'"$d"'T04:16:00Z" | fromdate)) + ($n - ("'"$y"'T22:00:00Z" | fromdate))')" = true ] \
    || fail "time waiting on the owner in the 7 days: $(q .metrics.week.waitMaxSec)"
  [ "$(q '[.metrics.week.cards, .metrics.week.perLanded.usd]')" = '[5,4.5]' ] || fail "the week's totals: $(q .metrics.week)"
  # The failed fix of card 3 is a step of its own: its seconds, tokens and dollars count.
  [ "$(q '.metrics.cards[] | select(.card == "c3") | .metrics | [.fixSec, (.usd == 4), .tokens, (.timeline | last | [.step, .result, .sec, (.usd == 2)])]')" = '[60,true,2000000,["fix","fail",60,true]]' ] \
    || fail "card 3's failed fix: $(q '.metrics.cards[] | select(.card == "c3") | .metrics')"
  [ "$(q '.metrics.cards[] | select(.card == "c1") | .metrics | [.queueSec, .slotSec, .buildSec, .reviewSec, .fixSec, .testSec, .landSec, .pushSec, .leadSec, .cycleSec, .findings, .diff, .limit, .blockClass, (.usd == 6), .tokens]')" \
    = '[3600,60,600,600,600,300,60,240,5760,2160,{"P0":0,"P1":2,"P2":1,"P3":0},{"files":2,"added":30,"removed":4},{"before":10,"after":12,"used":2},null,true,3000000]' ] || fail "card 1's metrics: $(q '.metrics.cards[] | select(.card == "c1") | .metrics')"
  [ "$(q '.metrics.cards | map(select(.card | IN("c3", "c4"))) | map([.metrics.blockClass, .metrics.slotSec, .metrics.queueSec])')" = '[["visible change",null,null],["timeout",null,600]]' ] \
    || fail "the blocked cards' metrics: $(q .metrics.cards)"
  # The steps of the last 25 h, each card's (card 5, blocked yesterday, has none), with the reviewer's and judge's cache
  # writes on card 4's review. Bug caught: the writes of sessions with no transcript were lost, so the cache-write alert
  # never named a Claude review or judge.
  [ "$(q '[.metrics.steps[] | .card] | sort')" = '["c1","c2","c3","c4","c6"]' ] || fail "the cards of the steps: $(q .metrics.steps)"
  [ "$(q '.metrics.steps[] | select(.card == "c4") | [.issue, .steps]')" = "[4,[{\"step\":\"build\",\"time\":\"${d}T04:10:00Z\"},{\"step\":\"review\",\"time\":\"${d}T04:15:00Z\",\"writes\":{\"model\":\"claude-sonnet-5-5\",\"write\":11,\"write1h\":0},\"judgeWrites\":{\"model\":\"claude-haiku-5-5\",\"write\":7,\"write1h\":3}}]]" ] \
    || fail "card 4's steps: $(q '.metrics.steps[] | select(.card == "c4")')"
  [ "$(q '.metrics.cards[] | select(.card == "c2") | .metrics.limit')" = '{"before":80,"after":1,"used":null}' ] || fail "a limit reset during card 2: $(q '.metrics.cards[] | select(.card == "c2") | .metrics.limit')"
  # No null cost: the old build (fresh tokens only, no split, no model) is not guessed at. It is left out of the
  # figures, counted, and says why; every other step, Codex reviews and the failed fix among them, is priced.
  [ "$(q '.cost | [.today, .todayLeftOut, .week, .weekLeftOut, .perLanded, .perLandedLeftOut, .unpricedSteps, (.unpriced | map([.card, .step, .why]))]')" \
    = '[16,1,16,1,4.5,0,1,[["c6","build","no token split recorded (a step recorded before the split was)"]]]' ] || fail "cost: $(q .cost)"
  # A card recorded before any of these fields: every measurement it lacks is missing (null), never 0.
  [ "$(q '.belt[] | select(.card == "c6") | .metrics | [.diff, .depth, .limit, .queueSec, .findings, .usd, .unpriced, .timeline[0].usd, .timeline[0].tests, .timeline[0].stats]')" \
    = '[null,null,{"before":null,"after":null,"used":null},null,null,null,1,null,null,null]' ] || fail "a card with no new field: $(q '.belt[] | select(.card == "c6") | .metrics')"
  # The batched push (c1 and c2's lines with head h2) is one push of 50 s, beside card 1's own 30 s one.
  # Card 2's push failed after 900 s.
  [ "$(q '.metrics.today.pushes | [.ok, .failed]')" = '[2,1]' ] || fail "a batched push counted by its lines' times: $(q .metrics.today.pushes)"
  [ "$(q '.metrics.today.pushes | [.sec.p50, .sec.p90, .failSec.p50, .failSec.p90]')" = '[40,50,900,900]' ] || fail "the pushes' seconds: $(q .metrics.today.pushes)"
  # The Board's sparklines and charts: each of the 7 days oldest first (today last: cards 1 and 2 landed in 21 and
  # 36 min, cards 3 and 4 blocked; yesterday card 5 blocked), and today's slots by hour (the mean of its samples).
  [ "$(q '.metrics.days | [length, .[0].day, (.[-2:] | map([.day, .landed, .blocked, .cycleSec, .firstReviewPass, .perLandedUsd]))]')" \
    = "[7,\"$(date -u -d "$d 6 days ago" +%F)\",[[\"$y\",0,1,null,null,null],[\"$d\",2,2,1710,0.667,4.5]]]" ] || fail "the 7 days, day by day: $(q .metrics.days)"
  [ "$(q '.metrics.slots')" = '[{"hour":0,"slots":3,"cap":4},{"hour":5,"slots":0.5,"cap":4}]' ] || fail "today's slots by hour: $(q .metrics.slots)"
  # Card 9, landed 9 days ago, is in the 7 days before the week.
  [ "$(q '[.metrics.prev.cards, .metrics.prev.landed, .metrics.prev.cycleSec.p50, .metrics.week.cards]')" = '[1,1,1800,5]' ] || fail "the 7 days before: $(q .metrics.prev)"
}

# Card c7's build session on its worktree of main (fx_wt), on the builder seat's model and the account folder
# $T/$CASE/acct, as session1() (lib/session.sh) runs it: builder() runs the claude stub in the background, watch()
# follows it to its end, its output is read with SESSIONREAD and transcribed(). No card runs. The fields are in
# build.out of the case's folder, watch()'s exit in BRC.
watched() {
  fx_wt : x.txt x; mkdir -p "$T/$CASE/acct"
  fx_in 'echo "{}" > "$FXWT.settings"; s=$(seat builder) && jqget "$s" model model effort effort || exit 1; KEEP=()
    builder "$FXWT" brief "$model" "$effort" "$T/$CASE/acct" claude & watch $! "$FXWT.out" "$FXWT.live" build "$model" claude; echo $? > "$T/$CASE/build.rc"
    f=$(jq -cRn --arg m "$model" --arg e "$effort" --argjson s 1 "$SESSIONREAD" "$FXWT.out" | tail -n 1) && transcribed "$f" "$FXWT.out" "$FXWT" "$T/$CASE/acct" > "$T/$CASE/build.out"'
  BRC=$(cat "$T/$CASE/build.rc" 2>/dev/null) && [ -s "$T/$CASE/build.out" ] || fail "the session did not run: $(cat "$T/$CASE/run.out")"
}
# The landed line of card c7 (landed(), lib.sh), at 01:30 of the day $y.
landed7() { landed 7 | jq -c --arg t "${y}T01:30:00Z" '.card = "c7" | .time = $t' >> "$ST/cards.jsonl"; }

# A build that times out after two answers (no result): what it spent is on the blocked line and priced; the card
# has its before and after weekly limit readings although no guard is set and no reading was taken before it.
t_metricsfail() {
  export TZ=UTC; setup "$(issue 7 2026-01-01 area:billing | jq -cs .)"; S=$ST; mkdir -p "$S"
  seatset model claude-sonnet-5-5
  cat > "$STUB/claude" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
echo '{"type":"assistant","message":{"id":"a1","content":[{"type":"tool_use","name":"Bash"}],"usage":{"input_tokens":1000,"output_tokens":1}}}'
echo '{"type":"assistant","message":{"id":"a1","content":[{"type":"text","text":"x"}],"usage":{"input_tokens":1000,"output_tokens":20}}}'
echo '{"type":"assistant","message":{"id":"a2","content":[{"type":"tool_use","name":"Edit"}],"usage":{"input_tokens":500000,"output_tokens":30}}}'
exit 124
EOF
  # The stub's reading goes up by one at each asking: the after reading is asked for although the card ends well within
  # LIMIT_TTL (300 s) of its before one, so it is 34, not the before reading's 33 again.
  printf '#!/bin/sh\nn=$(($(cat "$STUB/limit.n" 2>/dev/null || echo 32) + 1)); echo $n > "$STUB/limit.n"; echo "{\\"seven_day\\":{\\"utilization\\":$n}}"\n' > "$STUB/limit"; chmod +x "$STUB/limit"
  # loop: the before reading is card()'s (its worktree line), and the blocked line is block()'s of the spend the session left: only a card run takes both readings and writes both lines
  CONVEYOR_LIMIT_CMD="$STUB/limit" loop run >/dev/null 2>&1
  [ "$(st 'select(.step == "blocked") | [.spent.step, .spent.tokens.claude, .tokens.claude, .spent.usage.input, .spent.usage.output, .spent.stats.tools, (.spent.sec | type), .limit] | tojson')" \
    = '["build",501050,501050,501000,50,{"Bash":1,"Edit":1},"number",34]' ] || fail "the failed build's spend, or no fresh after reading: $(st 'select(.step == "blocked")')"
  [ "$(st 'select(.step == "worktree") | .limit')" = 33 ] || fail "no reading before the first card: $(st 'select(.step == "worktree")')"
  recok "$S/cards.jsonl" "a build that timed out (a blocked line with spent)"
  out=$(loop snapshot --fresh) || fail "snapshot after a failed build exited non-zero"
  [ "$(jq -c '[.cost.unpricedSteps, .cost.today > 0, (.needsYou.blocked[0].metrics.timeline | map([.step, .result]))]' <<<"$out")" = '[0,true,[["build","fail"]]]' ] \
    || fail "the failed build is not priced: $(jq -c '[.cost, .needsYou.blocked[0].metrics]' <<<"$out")"
}

# The shape of a real card's fix session, whose step the loop could not
# record: after its result a task notification started a second turn, so the output holds two results, each with
# its own turn's usage, num_turns and permission_denials, and modelUsage and duration_api_ms the session's totals so
# far. The step is one line with both turns added up, priced at the model that ran (Opus 5.5 rates: $4 in, $20 out,
# $0.20 read, writes at 1.25 times in): 180 * 4 + 201000 * 5 + 1050000 * 0.2 + 7000 * 20 = $1.355720. The session
# goes on (exit 0); on a landed card with that build no step is unpriced and no cost is null.
t_metricstwo() {
  local f
  export TZ=UTC; setup "$(issue 7 2026-01-01 area:billing | jq -cs .)"; d=$(date -u +%F); y=$d; now=$(date -u -d "${d}T23:59:00Z" +%s)
  bash > "$STUB/claude-usage" <<'EOF' # the stream the shared claude stub's session prints
echo '{"type":"system","subtype":"init","model":"claude-opus-5-5"}'
echo '{"type":"assistant","message":{"id":"m1","content":[{"type":"tool_use","id":"t1","name":"Bash"}],"usage":{"input_tokens":3,"output_tokens":9}}}'
echo '{"type":"assistant","message":{"id":"m1","content":[{"type":"tool_use","id":"t2","name":"Edit"}],"usage":{"input_tokens":3,"output_tokens":9}}}'
echo '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1"}]}}'
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":122,"duration_api_ms":651794,"permission_denials":[{"tool_name":"Bash"},{"tool_name":"Bash"}],"usage":{"input_tokens":170,"cache_creation_input_tokens":200000,"cache_read_input_tokens":1000000,"output_tokens":6000,"cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":200000}},"modelUsage":{"claude-opus-5-5":{"inputTokens":170,"outputTokens":6000,"cacheReadInputTokens":1000000,"cacheCreationInputTokens":200000,"costUSD":1.3}},"total_cost_usd":1.3}'
echo '{"type":"system","subtype":"task_notification"}'
echo '{"type":"assistant","message":{"id":"m2","content":[{"type":"tool_use","id":"t3","name":"Read"}],"usage":{"input_tokens":10,"output_tokens":1000}}}'
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":3,"duration_api_ms":665529,"permission_denials":[],"usage":{"input_tokens":10,"cache_creation_input_tokens":1000,"cache_read_input_tokens":50000,"output_tokens":1000,"cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":1000}},"modelUsage":{"claude-opus-5-5":{"inputTokens":180,"outputTokens":7000,"cacheReadInputTokens":1050000,"cacheCreationInputTokens":201000,"costUSD":1.36}},"total_cost_usd":1.36,"origin":{"kind":"task-notification"}}'
EOF
  watched
  f=$(cat "$T/$CASE/build.out")
  # session1() goes on only when watch() exits 0 and the fields say ok.
  [ "$BRC $(jq -r .ok <<<"$f")" = '0 true' ] || fail "a session with two results did not go on: $BRC $f"
  [ "$(jq -c '[.tokens.claude, .usage, .stats.turns, .stats.refused, .stats.apiSec, .stats.tools, .stats.models, .unread]' <<<"$f")" \
    = '[208180,{"input":180,"write":201000,"write1h":0,"read":1050000,"output":7000},125,2,666,{"Bash":1,"Edit":1,"Read":1},["claude-opus-5-5"],null]' ] \
    || fail "a session with two results: $f"
  l 7 01:00 picked ok '{"title":"T7"}'; l 7 01:10 build ok "$(jq -c 'del(.ok)' <<<"$f")"; landed7
  recok "$ST/cards.jsonl" "a card whose build gave two results"
  out=$(CONVEYOR_NOW=$now loop snapshot --fresh) || fail "snapshot exited non-zero"
  [ "$(jq -c '[(.landed[0].metrics.timeline | map([.step, .usd, .model])), .cost.unpricedSteps, .cost.weekLeftOut, (.cost.week != null), (.cost.perLanded != null)]' <<<"$out")" \
    = '[[["build",1.3557,"claude-opus-5-5"]],0,0,true,true]' ] \
    || fail "the two-result build is not priced whole: $(jq -c '[.landed[0].metrics.timeline, .cost]' <<<"$out")"
}

# A session cut off by its timeout, asked for Sonnet ($2 in) and running Opus ($4 in): the tokens of the answers
# after its last result (cut: a resumed turn after a result that names two models) or of all its answers (early:
# no result at all) are under the model each answer names, so the step is priced whole and at Opus rates.
# cut: Opus 100 + 1M in, Sonnet 100 in: $4.0004 + $0.0002. early: Opus 1M in: $4 (4.0, as the snapshot prints it).
# The session's exit check (session1(), lib/session.sh) fails a step that timed out after a successful result and
# keeps its spend, block() puts it on the blocked line, and the snapshot prices that line.
t_metricscut() { cutoff cut 4.0006 1000100; }
t_metricsearly() { cutoff early 4.0 1000000; }
cutoff() { # <cut | early> <the step's dollars> <its Opus input tokens>
  local k=$1 want=$2 opus=$3
  export TZ=UTC; setup "$(issue 7 2026-01-01 area:billing | jq -cs .)"; d=$(date -u +%F); y=$d; now=$(date -u -d "${d}T23:59:00Z" +%s)
  seatset model claude-sonnet-5-5
  {
    echo '#!/usr/bin/env bash'; echo 'cat > /dev/null'
    [ "$k" = early ] || echo "echo '{\"type\":\"result\",\"is_error\":false,\"num_turns\":1,\"usage\":{\"input_tokens\":200,\"output_tokens\":0},\"modelUsage\":{\"claude-opus-5-5\":{\"inputTokens\":100,\"outputTokens\":0},\"claude-sonnet-5-5\":{\"inputTokens\":100,\"outputTokens\":0}}}'"
    echo "echo '{\"type\":\"assistant\",\"message\":{\"id\":\"m9\",\"model\":\"claude-opus-5-5\",\"content\":[],\"usage\":{\"input_tokens\":1000000,\"output_tokens\":0}}}'"
    echo 'exit 124'
  } > "$STUB/claude"
  l 7 00:00 picked ok '{"title":"T7"}'
  # session() fails and leaves its spend ($FXWT.spent), and block() (lib/push.sh) writes card c7's blocked line of it.
  fx_wt : x.txt x
  fx_in 'echo "{}" > "$FXWT.settings"; session "$FXWT" brief > "$T/$CASE/build.out"; echo $? > "$T/$CASE/build.rc"
    block c7 7 "$FXWT" "build: $(head -n 1 "$T/$CASE/build.out")"'
  [ "$(cat "$T/$CASE/build.rc" 2>/dev/null)" = 1 ] || fail "the $k session that timed out went on: $(cat "$T/$CASE/build.out" "$T/$CASE/run.out")"
  [ "$(st 'select(.step == "blocked") | [.spent.stats.models, .spent.stats.byModel["claude-opus-5-5"].input] | tojson')" = "[[\"claude-opus-5-5\"$([ "$k" = early ] || echo ',"claude-sonnet-5-5"')],$opus]" ] \
    || fail "the $k session's tokens by model: $(st 'select(.step == "blocked")')"
  recok "$ST/cards.jsonl" "a $k session's blocked line"
  out=$(CONVEYOR_NOW=$now loop snapshot --fresh) || fail "snapshot exited non-zero ($k)"
  [ "$(jq -c '.needsYou.blocked[0].metrics.timeline[0] | [.usd, .model]' <<<"$out")" = "[$want,\"claude-opus-5-5\"]" ] \
    || fail "the $k session is not priced at what ran it: $(jq -c '.needsYou.blocked[0].metrics.timeline' <<<"$out")"
}

# A session that ends with a successful result whose usage cannot be read: the step is recorded with its usage
# left out and why, the session goes on (exit 0), and on a landed card the step shows as unpriced with that reason,
# never as $0. Its output names its session, and the account folder holds no transcript of it: transcribed() leaves
# the step unread. With a transcript there (bug: a transcript in the account folder the session ran on was not
# read), transcribed() gives that transcript's usage in place of unread.
t_metricsunread() {
  local f p sid=0b7c2a4e-1f3d-4c5b-9a8e-6d2f1e3c4b5a
  export TZ=UTC; setup "$(issue 7 2026-01-01 area:billing | jq -cs .)"; d=$(date -u +%F); y=$d; now=$(date -u -d "${d}T23:59:00Z" +%s)
  echo "{\"type\":\"result\",\"is_error\":false,\"session_id\":\"$sid\",\"num_turns\":2,\"usage\":\"n/a\"}" > "$STUB/claude-usage"
  watched
  f=$(cat "$T/$CASE/build.out")
  [ "$BRC $(jq -r .ok <<<"$f")" = '0 true' ] || fail "a session whose usage could not be read did not go on: $BRC $f"
  [ "$(jq -c '[.unread, .usage, .tokens.claude, .stats.turns, .model]' <<<"$f")" = '["the session output holds no token usage",null,null,2,"m"]' ] \
    || fail "the unread build: $f"
  p=$T/$CASE/acct/projects/$(cd "$FXWT" && pwd -P | sed 's/[^A-Za-z0-9]/-/g'); mkdir -p "$p"
  jq -cn --arg s "$sid" '{type: "assistant", sessionId: $s, message: {id: "msg_1", model: "claude-sonnet-5-5", usage: {input_tokens: 3, cache_creation_input_tokens: 100, cache_read_input_tokens: 0, output_tokens: 40}}}' > "$p/$sid.jsonl"
  fx_in 'transcribed "$(cat "$T/$CASE/build.out")" "$FXWT.out" "$FXWT" "$T/$CASE/acct" > "$T/$CASE/read.out"'
  [ "$(jq -c '[.unread, .usage, .tokens.claude, .stats.models]' "$T/$CASE/read.out")" = '[null,{"input":3,"write":100,"write1h":0,"read":0,"output":40},143,["claude-sonnet-5-5"]]' ] \
    || fail "the transcript in the session's account folder was not read: $(cat "$T/$CASE/read.out" "$T/$CASE/run.out")"
  l 7 01:00 picked ok '{"title":"T7"}'; l 7 01:10 build ok "$(jq -c 'del(.ok)' <<<"$f")"; landed7
  recok "$ST/cards.jsonl" "a card whose build's usage was unread"
  out=$(CONVEYOR_NOW=$now loop snapshot --fresh) || fail "snapshot exited non-zero"
  [ "$(jq -c '[(.landed[0].metrics.timeline[0] | [.step, .tokens, .usd, .unpriced]), .landed[0].metrics.tokens, (.cost.unpriced | map(.why))]' <<<"$out")" \
    = '[["build",null,null,"its token usage could not be read: the session output holds no token usage"],null,["its token usage could not be read: the session output holds no token usage"]]' ] \
    || fail "the unread build in the snapshot: $(jq -c '[.landed[0].metrics, .cost]' <<<"$out")"
}

# A session of two results, the second's usage unreadable: the usage read is kept, but the step says unread, so
# its tokens show as missing and it is unpriced, never priced as whole. Each model's 1-hour cache writes are read
# from that model's answers. The output is read as the loop reads a session's (SESSIONREAD, lib/session.sh), and the
# line it gives is a landed card's build; t_metricsunread runs the session itself (watch()) on an unread usage.
t_metricspartial() {
  local o f
  export TZ=UTC; setup '[]'; S=$ST; mkdir -p "$S"; d=$(date -u +%F); y=$d; now=$(date -u -d "${d}T23:59:00Z" +%s); o=$T/$CASE/session.out
  cat > "$o" <<'EOF'
{"type":"assistant","message":{"id":"m1","model":"claude-opus-5-5","usage":{"input_tokens":5,"output_tokens":1,"cache_creation":{"ephemeral_1h_input_tokens":300}}}}
{"type":"assistant","message":{"id":"m2","model":"claude-sonnet-5-5","usage":{"input_tokens":5,"output_tokens":1,"cache_creation":{"ephemeral_1h_input_tokens":0}}}}
{"type":"result","is_error":false,"num_turns":1,"usage":{"input_tokens":10,"cache_creation_input_tokens":500,"cache_read_input_tokens":0,"output_tokens":2,"cache_creation":{"ephemeral_1h_input_tokens":300}}}
{"type":"result","is_error":false,"num_turns":1,"usage":"n/a","modelUsage":{"claude-opus-5-5":{"inputTokens":5,"outputTokens":1,"cacheCreationInputTokens":400},"claude-sonnet-5-5":{"inputTokens":5,"outputTokens":1,"cacheCreationInputTokens":100}}}
EOF
  # The build line's fields, as session.sh keeps them of what SESSIONREAD gives. ok is true, so session.sh goes on
  # with the card (its exit check, which t_metricsunread checks on watch()'s exit and .ok) rather than blocking it.
  f=$(jq -cRn --arg m m --arg e medium --argjson s 60 -f "$SRC/jq/sessionread.jq" "$o" | tail -n 1) || fail "the session's output was not read"
  [ "$(jq -c '[.ok, .unread, .usage, .stats.byModel]' <<<"$f")" \
    = '[true,"1 of 2 results hold no readable token usage, so the usage recorded is only part of it",{"input":10,"write":200,"write1h":300,"read":0,"output":2},{"claude-opus-5-5":{"input":5,"write":400,"read":0,"output":1,"write1h":300},"claude-sonnet-5-5":{"input":5,"write":100,"read":0,"output":1,"write1h":0}}]' ] \
    || fail "the partly read build: $f"
  f=$(jq -c 'del(.ok) | del(.effort)' <<<"$f")
  l 1 01:00 picked ok '{"title":"T1"}'; l 1 01:10 build ok "$f"; l 1 01:30 landed ok '{"sha":"s1","product":false}'
  recok "$S/cards.jsonl" "a partly read build"
  out=$(CONVEYOR_NOW=$now loop snapshot --fresh) || fail "snapshot exited non-zero"
  [ "$(jq -c '.landed[0].metrics | [(.timeline[0] | [.tokens, .usd]), .tokens]' <<<"$out")" = '[[null,null],null]' ] \
    || fail "the partly read build is shown as whole: $(jq -c '.landed[0].metrics' <<<"$out")"
}

# A session that ran on two models: each model's 1-hour cache writes at its own rate, and the step split between
# them (pricedBy). Opus: 1M in at $4 + 1M 1-hour writes at $8 = $12; Sonnet: 1M in at $2 + 1M 5-minute writes at
# $2.50 = $4.50. With no 1-hour count for either and both writing cache, whose they were is not known: unpriced.
t_metricsbymodel() {
  local two
  two='{"step":"build","model":"claude-opus-5-5","usage":{"input":2000000,"write":1000000,"write1h":1000000,"read":0,"output":0},"stats":{"byModel":{"claude-opus-5-5":{"input":1000000,"write":1000000,"read":0,"output":0,"write1h":1000000},"claude-sonnet-5-5":{"input":1000000,"write":1000000,"read":0,"output":0,"write1h":0}}}}'
  priced=$(jq -c '{cards: [{steps: [., (.stats.byModel |= map_values(del(.write1h)))]}]}' <<<"$two" | python3 "$SRC/../.claude/scripts/dashboard_limit.py" cards \
    | jq -c '.cards[0].steps | map([.usd, .pricedAs, .pricedBy, .unpriced])')
  [ "$priced" = '[[16.5,"claude-opus-5-5",{"claude-opus-5-5":{"usd":12.0,"tokens":2000000},"claude-sonnet-5-5":{"usd":4.5,"tokens":2000000}},null],[null,null,null,"its 1-hour cache writes cannot be put to the model that wrote them"]]' ] \
    || fail "a two-model session is not priced by model: $priced"
  # The totals by model split that step between its two models; a step whose usage was not read is counted out of
  # the tokens (tokensLeftOut), never in as 0.
  export TZ=UTC; setup '[]'; S=$ST; mkdir -p "$S"; y=$(date -u -d yesterday +%F)
  l 1 01:00 picked ok '{"title":"T1"}'; l 1 01:10 build ok "$(jq -c '. + {tokens: {claude: 4000000, codex: 0}} | del(.step)' <<<"$two")"
  l 1 01:20 fix ok '{"model":"claude-sonnet-5-5","unread":"the session output holds no token usage"}'
  l 1 01:30 landed ok '{"sha":"s1","product":false}'
  recok "$S/cards.jsonl" "the two-model fixture"
  out=$(loop snapshot --fresh) || fail "snapshot of the two-model fixture exited non-zero"
  [ "$(jq -c '.metrics.week.perLanded' <<<"$out")" \
    = '{"usd":16.5,"leftOut":1,"tokens":4000000,"tokensLeftOut":1,"byModel":{"claude-opus-5-5":{"usd":12,"leftOut":0,"tokens":2000000,"tokensLeftOut":0},"claude-sonnet-5-5":{"usd":4.5,"leftOut":1,"tokens":2000000,"tokensLeftOut":1}}}' ] \
    || fail "the totals by model: $(jq -c '.metrics.week.perLanded' <<<"$out")"
  # Its day in the sparkline: with a step unpriced the day's cost is only part of it, so it has no value, never $16.50.
  [ "$(jq -c '.metrics.days[-2] | [.day, .landed, .perLandedUsd]' <<<"$out")" = "[\"$y\",1,null]" ] \
    || fail "a day with an unpriced step drawn as measured: $(jq -c '.metrics.days' <<<"$out")"
}

# Waiting on the owner ends when `retry` gives the card back: blocked 10:00, retried 11:00 and picked again 12:00 is one
# hour, and before that pick the hour is already counted.
t_metricsretried() {
  export TZ=UTC; setup '[]'; S=$ST; mkdir -p "$S"; y=$(date -u -d yesterday +%F)
  l 8 09:00 picked ok '{"title":"T8"}'; l 8 10:00 blocked blocked "{\"reason\":\"review 1: no answer\",\"retriedAt\":\"${y}T11:00:00Z\"}"
  mv "$S/cards.jsonl" "$S/retried.jsonl"; : > "$S/cards.jsonl"
  [ "$(loop snapshot --fresh | jq -c '.metrics.week.waitMaxSec')" = 3600 ] || fail "a retried card's wait before its next pick: $(loop snapshot --fresh | jq -c .metrics.week)"
  l 8 12:00 picked ok '{"title":"T8","card":"c9"}'; recok "$S/cards.jsonl" "the retried fixture"; recok "$S/retried.jsonl" "the retried fixture"
  out=$(loop snapshot --fresh) || fail "snapshot exited non-zero"
  [ "$(jq -c '[.metrics.week.waitMaxSec, (.belt[] | select(.issue == 8) | .metrics.waitMaxSec)]' <<<"$out")" = '[3600,3600]' ] \
    || fail "waiting on the owner does not end at the retry: $(jq -c '[.metrics.week, .belt]' <<<"$out")"
}

# Bugs: a card whose issue was closed while it was blocked (blocked 12:00, closed by hand 13:00) loses its hour
# waiting on the owner from the totals, or the hour is read as its landing, lead or cycle time: it landed nothing.
t_metricsshut() {
  export TZ=UTC; setup '[]'; S=$ST; mkdir -p "$S"; y=$(date -u -d yesterday +%F)
  l 8 11:00 picked ok "{\"title\":\"T8\",\"created\":\"${y}T10:00:00Z\"}"; l 8 11:30 review NO-GO; l 8 12:00 blocked blocked '{"reason":"review 1: no answer"}'
  l 8 13:00 closed ok '{"reason":"the issue was closed by hand while the card was blocked"}'; recok "$S/cards.jsonl" "the shut fixture"
  out=$(loop snapshot --fresh) || fail "snapshot of the shut fixture exited non-zero"
  [ "$(jq -c '[.metrics.week.waitMaxSec, (.metrics.cards[] | select(.card == "c8") | .state, (.metrics | .waitMaxSec, .landSec, .leadSec, .cycleSec))]' <<<"$out")" = '[3600,"closed",3600,null,null,null]' ] \
    || fail "the wait of a card closed while blocked: $(jq -c '[.metrics.week.waitMaxSec, (.metrics.cards[] | select(.card == "c8"))]' <<<"$out")"
  # Bugs: the same card, which landed nothing, is counted landed: in a window's totals, in the cards landed after one
  # review (so its cost is a landed card's), or in the cards summary.
  [ "$(jq -c '[(.metrics.week | .cards, .landed, .perLanded), .cost.landedAfter["1"], .cost.perLanded]' <<<"$out")" = '[1,0,null,0,null]' ] \
    || fail "a card closed while blocked is counted landed: $(jq -c '[.metrics.today, .metrics.week, .landed, .cost]' <<<"$out")"
  [ "$(loop cards | jq -c '[.landed, .blocked]')" = '[0,0]' ] || fail "the cards summary of a card closed while blocked: $(loop cards)"
}

# Issue 1303. Bug it catches: the queue time of a card had no cause recorded, so no change to the wait could be
# measured. #1 waits two samples with every slot taken (the loop's sample(), the minute's), one with the weekly limit
# guard pausing the loop (a pause, not a rule on #1: the cause was lost when only a running loop was sampled), then one
# on its Depends on: #2 line while the machine hold stands: those samples name #1's cause, and the last names #2's too
# (the next in line, which only the hold keeps back): "machine hold", never "main red", as the hold is a fault of the
# machine with no change to main behind it. The card of #1, picked after them, has waitWhy {cap: 120, guard: 60,
# Depends on: 60} in the snapshot's metrics: 60 s a sample.
t_metricswait() {
  # #1 is P1 so it stays first in the line when it depends on #2: of equal priority, the pick takes first an issue
  # another waits on (upnext.jq), and #2, the pick, would end the line before #1's dependency is named.
  export TZ=UTC; y=$(date -u +%F); setup "[$(issue 1 "${y}T00:00:00Z" P1), $(issue 2 "${y}T00:00:01Z")]"
  fx_in 'sample 4 4 running "" && sample 4 4 running ""'; [ "$RC" = 0 ] || fail "the samples with every slot taken failed: $(cat "$T/$CASE/run.out")"
  fx_in 'sample 0 4 "paused by guard" ""'; [ "$RC" = 0 ] || fail "the sample with the guard pausing the loop failed: $(cat "$T/$CASE/run.out")"
  jq -c '.[0].body = "Depends on: #2"' "$STUB/issues.json" > "$STUB/issues.new" && mv "$STUB/issues.new" "$STUB/issues.json"
  fx_in 'sample 0 4 running "the machine fails x.test.sh on main"'; [ "$RC" = 0 ] || fail "the sample with the machine hold failed: $(cat "$T/$CASE/run.out")"
  [ "$(jq -sc 'map(.wait)' "$ST/samples.jsonl")" = '[{"1":"cap"},{"1":"cap"},{"1":"guard"},{"1":"Depends on","2":"machine hold"}]' ] \
    || fail "sample(), given 4 of 4 slots twice, then 0 of 4 paused by guard, then 0 of 4 with #1 depending on #2 and the machine hold standing, did not name each issue's cause: $(cat "$ST/samples.jsonl")"
  # The samples' times are set to the fixture's day: 00:10 and 00:11 with every slot taken, 00:15 under the guard,
  # 00:20 on the dependency.
  jq -sc --arg y "$y" 'to_entries[] | .value.time = "\($y)T\(["00:10", "00:11", "00:15", "00:20"][.key]):00Z" | .value' "$ST/samples.jsonl" > "$ST/samples.new" \
    && mv "$ST/samples.new" "$ST/samples.jsonl" || fail "the samples' times could not be set"
  l 1 00:30 picked ok "{\"title\":\"T1\",\"created\":\"${y}T00:00:00Z\"}"; recok "$ST/cards.jsonl" "the wait fixture"
  out=$(CONVEYOR_NOW=$(date -u -d "${y}T23:59:00Z" +%s) loop snapshot --fresh) || fail "snapshot of the wait fixture exited non-zero"
  [ "$(jq -c '.belt[], .metrics.cards[] | select(.card == "c1") | .metrics.waitWhy' <<<"$out" | sort -u)" = '{"Depends on":60,"cap":120,"guard":60}' ] \
    || fail "the card of #1 does not give its wait by cause: $(jq -c '[.belt[], .metrics.cards[] | select(.card == "c1") | .metrics]' <<<"$out")"
}
