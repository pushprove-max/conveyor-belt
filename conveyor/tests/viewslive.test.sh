#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the live cost and reading of a card's running step, in the snapshot and health.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bugs: a card that is building shows no dollars until its session ends, or $0 before the session has said
# anything; an answer of the model that comes as several events is counted once for each; a long session that is
# still producing output is reported stuck, or a silent one is not; a running test run does not say how many of its
# files are done; a review's findings are counted from the 1500 characters its record line keeps; the line written
# when a step ends is not what it was; a mark (when the issue was opened, each start, the follow-ups filed, the push,
# the issue closed or still open) is not on the landed card's track; a running review shows no tokens until it ends
# (its stream names none before then: they are in the session file Codex keeps, which is gone once the review ends).
# Each case calls the engine functions it proves (watch(), rollout(), testlogs() and testprogress() of lib/session.sh,
# counts() of lib/donewhen.sh, line() of lib/records.sh, the session reading SESSIONREAD) and reads what they give
# through the snapshot and health, as card c7's records and live record: a whole card run held at each step was most
# of this file's time.
livestart() {
  export TZ=UTC; setup "[$(issue 7 2026-01-01T00:00:00Z area:billing)]"; S=$ST; W=$T/$CASE/cards/c7; LM=0; d=$(date -u +%F)
  mkdir -p "$S" "$T/$CASE/cards"; seatset model claude-sonnet-5-5; seatset reviewer gpt-6.1-sol
  snap() { loop snapshot --fresh 2>/dev/null | jq -c "$1"; }
}
# Card c7's lines, one a minute from today 00:00, after those it wrote before: <step>[:<result>[:<extra json>]], a
# start line as start:<the step it begins>.
lines() { # <step>...
  local a step res x
  for a; do
    IFS=: read -r step res x <<<"$a"
    case $step in picked) x='{"title":"T7","created":"2026-01-01T00:00:00Z"}' ;; start) x="{\"of\":\"$res\"}" res=ok ;; esac
    jq -cn --arg s "$step" --arg t "$(printf '%sT00:%02d:00Z' "$d" "$LM")" --arg r "${res:-ok}" --argjson x "${x:-{\}}" \
      '{card:"c7",issue:7,step:$s,time:$t,tokens:{claude:0,codex:0},result:$r,sha:"",reason:""} * $x | .time = $t' >> "$S/cards.jsonl"
    LM=$((LM + 1))
  done
}
# watch() (lib/session.sh), the engine's own, on a <step> held open until $STUB/go, whose output is <output file> as
# it stands; its live record is copied to $W.seen once <jq test> holds of it, and it is gone once the step ends.
viewswatched() { # <output file> <step> <model> <jq test>
  # shellcheck disable=SC2034 # LIVE and STUCK are read by watch(), defined by the eval
  ( . "$SRC/lib/portable.sh"; eval "$(for f in watch rollout holds; do sed -n "/^$f() {/,/^}/p" "$SRC/lib/session.sh"; done)"; LIVE=0.05 STUCK=600
    (while [ -d "$STUB" ] && [ ! -e "$STUB/go" ]; do sleep 0.05; done) & watch $! "$1" "$W.live" "$2" "$3" ) > "$T/$CASE/run.out" 2>&1 & run=$!
  # A wait on a real process: watch() keeps the live record only while its step runs and removes it as the step ends
  # (a step that has ended leaves it nothing to read), so the record is read while the step is held.
  wait_until "jq -e '$4' '$W.live'" "cat '$W.live'" || { : > "$STUB/go"; wait $run; fail "the live record never held $4: $(cat "$T/$CASE/run.out")"; }
  cp "$W.live" "$W.seen"; : > "$STUB/go"; wait $run || fail "the watch of the step exited non-zero: $(cat "$T/$CASE/run.out")"
  [ ! -e "$W.live" ] || fail "watch() left the live record of a step that ended: $(cat "$W.live")"
}
t_livebuild() { livestart; lines picked worktree deps brief start:build
  # The session has said nothing yet: the live record watch() writes as its step begins.
  printf '{"step":"build","at":"%sT00:04:00Z","last":null,"turns":0,"model":"claude-sonnet-5-5"}\n' "$d" > "$W.live"
  [ "$(snap '.belt[0] | [.usd, .reading, .tokens.claude, .live.lastOutputAt, .track.detailAt, .track.at]')" = '[null,false,0,null,5,0]' ] || fail "a session that has said nothing: $(snap '.belt[0]')"
  # Health asks 4 s after the step began (the clock seam, CONVEYOR_NOW): the session, silent since its start, is past the limit.
  at=$(jq -n --arg t "${d}T00:04:00Z" '$t | fromdate + 4')
  [ "$(CONVEYOR_NOW=$at tuned '.tunables.stuck = 3' loop health | jq -c '.stuck | map([.issue, .step])')" = '[[7,"build"]]' ] || fail "a session silent past the limit is not stuck: $(CONVEYOR_NOW=$at tuned '.tunables.stuck = 3' loop health)"
  # Its stream: two answers, the first as two events with one id, then a call of a tool.
  answer() { echo "{\"type\":\"assistant\",\"message\":{\"id\":\"$1\",\"usage\":{\"input_tokens\":1000000,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":0,\"output_tokens\":0}}}"; }
  { echo '{"type":"system","subtype":"init"}'; answer m1; answer m1; echo '{"type":"user"}'; answer m2
    echo '{"type":"assistant","message":{"id":"m2","content":[{"type":"tool_use","name":"Bash","input":{"command":"npm test"}}]}}'; } > "$W.out"
  viewswatched "$W.out" build claude-sonnet-5-5 '.action == "Bash: npm test"'
  [ "$(jq -c '[.turns, .usage.input, .action, (.last != null)]' "$W.seen")" = '[2,2000000,"Bash: npm test",true]' ] || fail "the live record of a running session: $(cat "$W.seen")"
  cp "$W.seen" "$W.live"; out=$(loop snapshot --fresh 2>/dev/null) || fail "snapshot of a running session exited non-zero"
  [ "$(jq -c '[(.belt[0] | .usd, .reading, .tokens.claude, .live.turns, .live.action, (.live.lastOutputAt | fromdate > 0), .step), .cost.today]' <<<"$out")" \
    = '[4,true,2000000,2,"Bash: npm test",true,"build",0]' ] || fail "the reading of a running session, or it is in the dollars of the steps that ended: $out"
  # Health asks a second past the last output: the start is then far past the limit, so a health that ignored the
  # output would say stuck.
  at=$(( $(jq -r '.belt[0].live.lastOutputAt | fromdate' <<<"$out") + 1 ))
  [ "$(CONVEYOR_NOW=$at tuned '.tunables.stuck = 3' loop health | jq -c '.stuck')" = '[]' ] || fail "a session whose start is old and whose last output is new is stuck: $(CONVEYOR_NOW=$at tuned '.tunables.stuck = 3' loop health)"
}
# The first review opens its thread, and Codex writes the running total to that thread's session file.
t_livereview() { livestart; lines picked worktree deps brief start:build 'build:ok:{"tokens":{"claude":35,"codex":0},"usage":{"input":10,"write":20,"write1h":0,"read":999,"output":5},"model":"claude-sonnet-5-5"}' start:review
  export CODEX_HOME=$STUB/codex-home; mkdir -p "$CODEX_HOME/sessions/2026/01/01"
  local f=$CODEX_HOME/sessions/2026/01/01/rollout-2026-01-01T00-00-00-0aa1-b2.jsonl
  printf '%s\n' '{"type":"thread.started","thread_id":"0aa1-b2"}' '{"type":"turn.started"}' > "$W.events"
  printf '%s\n' '{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":500000,"cached_input_tokens":0,"output_tokens":0}}}}' \
    '{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000000,"cached_input_tokens":400000,"output_tokens":500}}}}' > "$f"
  [ "$(eval "$(sed -n '/^rollout() {/,/^}/p' "$SRC/lib/session.sh")"; rollout "$W.events")" = "$f" ] || fail "rollout() does not find the review's session file"
  viewswatched "$W.events" review gpt-6.1-sol '.usage.input == 600000'
  [ "$(jq -c '[.usage, (.last != null)]' "$W.seen")" = '[{"input":600000,"read":400000,"output":500},true]' ] || fail "the live record of a running review: $(cat "$W.seen")"
  cp "$W.seen" "$W.live"
  [ "$(snap '.belt[0] | [.track.label, .tokens.codex, .reading, .tokens.claude, .usd > 0, (.live.lastOutputAt | fromdate > 0)]')" = '["review 1 of 3",600500,true,35,true,true]' ] \
    || fail "the reading of a running review: $(snap '.belt[0]')"
}
# The first review says NO-GO (44 lines, 43 of them findings), the next two say NO-GO too; the test run then runs its
# three files each alone, and c.test.sh runs now.
t_live() { livestart
  local cmd p h
  { for i in $(seq 40); do echo "[P2] a.txt:$i a finding long enough that forty of them pass the cut of the record line"; done
    printf '%s\n' '[P0] a.txt:99 the worst one, past the cut' 'b.txt:1 no mark here' '[P3] c.txt:1 small' 'NEW CARD: b.txt is stale' 'USER-VISIBLE: no' 'VERDICT: NO-GO'; } > "$STUB/review.1"
  for i in 2 3; do moved $i "$NOGO" > "$STUB/review.$i"; done
  printf '%s\n' '{"type":"system","subtype":"init"}' '{"type":"result","is_error":false,"usage":{"input_tokens":10,"cache_creation_input_tokens":20,"cache_read_input_tokens":999,"output_tokens":5}}' > "$STUB/build.out"
  # The three review lines as the card writes them (lib/card.sh: donewhen.sh counts() over the whole review, line()'s cut of
  # the reason) and the build line from the session's output (SESSIONREAD, as session1() reads it), one a line.
  # shellcheck disable=SC2016 # expanded where fx_in runs it, with the engine loaded
  cmd='for i in 1 2 3; do line c7 7 review NO-GO "$(grep -Ev "$UNRECORDED" "$STUB/review.$i" | jq -cRs --argjson k "$(counts "$STUB/review.$i")" '\''sub("\n+$"; "") as $r | {reason: $r, counts: $k, tail: $r}'\'')"; done
    line c7 7 build ok "$(jq -cRn --arg m claude-sonnet-5-5 --arg e "" --argjson s 0 --argjson run null "$SESSIONREAD" "$STUB/build.out" | tail -n 1 | jq -c "del(.ok)")"'
  fx_in "$cmd"; [ "$RC" = 0 ] || fail "the review and build lines could not be made: $(cat "$T/$CASE/run.out")"
  rv() { sed -n "${1}p" "$T/$CASE/run.out"; }
  [ "$(rv 1 | jq -c '[(.reason | length), .counts.P2, .counts.P0]')" = '[1500,40,1]' ] || fail "counts not taken from the whole review: $(rv 1 | jq -c .counts)"
  [ "$(rv 4 | jq -c '[.tokens.claude, (.usage | map(tostring) | join(" "))]')" = '[35,"10 20 0 999 5"]' ] || fail "the line written when the session ends changed: $(rv 4)"
  # The test run: its output and its own log hold a.test.sh and b.test.sh ended and c.test.sh begun; the log of
  # another card's worktree, which names 7 files, is not this run's.
  printf '%s\n' '== a.test.sh' '-- ok a.test.sh' '== b.test.sh' '-- ok b.test.sh' '== c.test.sh' > "$W.test"
  mkdir -p "$W.testlog" "$T/$CASE/cards/c8.testlog"; { echo 'TESTRUN files=3'; cat "$W.test"; } > "$W.testlog/files"
  printf 'TESTRUN files=7\n-- ok   other.test.ts 0s\n' > "$T/$CASE/cards/c8.testlog/files"
  p=$(eval "$(for f in testlogs testprogress; do sed -n "/^$f() {/,/^}/p" "$SRC/lib/session.sh"; done)"; mapfile -t logs < <(testlogs "$W"); testprogress "$W.test" "${logs[@]}")
  [ "$p" = '{"run":2,"of":3,"cases":null,"now":"c.test.sh"}' ] || fail "the files of a running test run: $p"
  lines picked worktree deps brief start:build "build:ok:$(rv 4)" start:review "review:NO-GO:$(rv 1)" start:fix fix start:review "review:NO-GO:$(rv 2)" \
    start:fix fix start:review "review:NO-GO:$(rv 3)" start:test
  jq -c --arg t "${d}T00:16:30Z" '{step: "test", at: $t, last: $t, turns: 0, progress: $t, files: {run, of, now: {file: .now, at: $t}}, tests: null}' <<<"$p" > "$W.live"
  [ "$(snap '.belt[0] | [.track.label, .track.detailAt, (.track.files | {run, of, now: .now.file}), (.reviews | map([.round, .verdict, .fixed, (.counts | tojson)]))]')" \
    = '["tests",11,{"run":2,"of":3,"now":"c.test.sh"},[[1,"NO-GO",true,"{\"P0\":1,\"P1\":1,\"P2\":40,\"P3\":1}"],[2,"NO-GO",true,"{\"P0\":0,\"P1\":1,\"P2\":0,\"P3\":0}"],[3,"NO-GO",false,"{\"P0\":0,\"P1\":1,\"P2\":0,\"P3\":0}"]]]' ] \
    || fail "the reviews in order, or the step of a running test run: $(snap '.belt[0] | [.track, .reviews]')"
  # The marks of the rest of its run: the follow-ups filed, the landing, the push, and GitHub kept the issue open, so
  # the card is still at Push, failed: its detail is at "issue closed".
  rm -f "$W.live"; h=$(git -C "$R" rev-parse HEAD)
  lines test:pass start:file 'filed:ok:{"followups":[100101]}' start:land "landed:ok:{\"sha\":\"$h\",\"product\":false,\"followups\":[100101]}" \
    "pushed:ok:{\"sha\":\"$h\"}" 'issue:fail:{"reason":"GitHub still shows the issue open 60 s after the push"}'
  [ "$(snap '.landed[0] | [(.rounds | length), .reviews, (.track.detail | map(.state) | join(" ")), .track.detail[16].n, .track.detail[0].sec > 86400, .track.detailAt, .track.at, .track.steps[5].state]')" \
    = '[3,3,"done done done done done done done done done done done done skipped done done failed done",1,true,15,5,"failed"]' ] || fail "the landed card's reviews and track: $(snap '.landed[0]')"
}
# Bugs: a card's own build, review or test run, started by the loop, is joined to the wrong process, output file,
# model, log folder or watch (session.sh session(), review.sh codexreview(), testrun.sh testonce()), so the snapshot
# shows nothing live or another card's; a review leaves its session file behind. The cases above call those parts
# alone; these run one card through the loop, as only a run joins them. A stub step says "<step> <worktree>" on the
# pipe $STUB/held.pipe and waits there until the case writes $STUB/go.pipe: hold <step>. (Not $STUB/go: $STUB is on
# PATH, and a `go` command looked for there would be the pipe.)
gatestart() { mkfifo "$STUB/held.pipe" "$STUB/go.pipe" || fail "the pipes"; exec 4<>"$STUB/held.pipe"
  echo 'hold() { exec 3<>"$STUB/go.pipe"; echo "$1 $PWD" 1<>"$STUB/held.pipe"; read -r -t 100 -u 3 _; }' > "$STUB/hold.sh"
  # A run that ends says so on the pipe too, so a card that never reaches a held step fails the case at once.
  ( loop run 4<&- > "$T/$CASE/loop.out" 2>&1; x=$?; echo "ended $x" 1<>"$STUB/held.pipe"; exit $x ) & run=$!; }
held() { # <step> <jq test of its live record>: the step is held, and watch() has read what its stub wrote
  local s wt; read -r -t 100 -u 4 s wt && [ "$s" = "$1" ] || fail "the $1 never reached its stub: $s $(cat "$T/$CASE/loop.out") $(tail -n 2 "$S/cards.jsonl")"
  # A wait on the real loop: watch() reads the output on its own timer and says nothing when it has.
  wait_until "jq -e '$2' '$wt.live'" "cat '$wt.live'" || fail "the live record of the $1 never held $2"
}
letgo() { echo go 1<>"$STUB/go.pipe"; }
t_livegated() { livestart
  export CODEX_HOME=$STUB/codex-home; local f=$STUB/codex-home/sessions/2026/01/01/rollout-2026-01-01T00-00-00-0aa1-b2.jsonl
  printf '%s\n' 'echo two >> a.txt; . "$STUB/hold.sh"' \
    'echo '\''{"type":"assistant","message":{"id":"m1","usage":{"input_tokens":1000000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0},"content":[{"type":"tool_use","name":"Bash","input":{"command":"npm test"}}]}}'\''; hold build' > "$STUB/build"
  printf '%s\n' ". \"\$STUB/hold.sh\"; mkdir -p \"${f%/*}\"; echo '{\"type\":\"thread.started\",\"thread_id\":\"0aa1-b2\"}'" \
    "echo '{\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":1000000,\"cached_input_tokens\":400000,\"output_tokens\":500}}}}' > '$f'; hold review" > "$STUB/review-cmd"
  echo "$GO" > "$STUB/review.1"; gatestart
  # The effort each step runs at (the seats' medium) is on the belt beside its model (issue 1085): session1() and
  # codexreview() give it to watch(), which writes it on the live record.
  held build '.action == "Bash: npm test"'
  [ "$(snap '.belt[0] | [.step, .live.action, .tokens.claude, .usd, .model, .effort]')" = '["build","Bash: npm test",1000000,2,"claude-sonnet-5-5","medium"]' ] || fail "the snapshot of a held build: $(snap '.belt[0]')"
  letgo; held review '.usage.input == 600000'
  # Its dollars are its running total's beside the build's recorded line (0.0002): that of the stub's result.
  [ "$(snap '.belt[0] | [.step, .tokens.codex, .usd, .done.usd, .model, .effort]')" = '["review",600500,1.2452,0.0002,"gpt-6.1-sol","medium"]' ] || fail "the snapshot of a held review: $(snap '.belt[0]')"
  letgo; wait $run || fail "the run exited non-zero: $(cat "$T/$CASE/loop.out")"
  [ ! -e "$f" ] || fail "the review that ended left its session file"
}
# The card's change runs three linked files; the third is held. Card c8's log, beside it, names seven files.
# The runner copies its file lines to the output too, so the held file writes a line only to its run's log (4 cases)
# and a runner-like line only to the output (z.test.sh): the wait holds only when watch() reads the log
# (testlogs()) and not the output.
t_testgated() { livestart
  echo x > "$R/b.test.sh"; echo x > "$R/c.test.sh"; git -C "$R" add b.test.sh c.test.sh; linkset '{"a.txt": ["a.test.sh", "b.test.sh", "c.test.sh"]}'
  echo '[ "$CONVEYOR_TEST_FILE" != c.test.sh ] || { echo "TESTRUN cases=4" >> "$CONVEYOR_TEST_LOG/c"; echo "-- ok z.test.sh"; . "$STUB/hold.sh"; hold test; }' > "$STUB/file-cmd"
  mkdir -p "$T/$CASE/cards/c8.testlog"; printf 'TESTRUN files=7\n-- ok   other.test.ts 0s\n' > "$T/$CASE/cards/c8.testlog/files"; echo "$GO" > "$STUB/review.1"; gatestart
  held test '.files.run == 2 and .tests.of == 4'
  [ "$(snap '.belt[0] | [.step, (.track.files | {run, of, now: .now.file})]')" = '["tests",{"run":2,"of":3,"now":"c.test.sh"}]' ] || fail "the snapshot of a held test run: $(snap '.belt[0]')"
  letgo; wait $run || fail "the run exited non-zero: $(cat "$T/$CASE/loop.out")"
}
