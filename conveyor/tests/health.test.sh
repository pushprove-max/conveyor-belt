#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the stalls `health` names in its stuck list beyond a card with no new step and no output.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bug: a card waited about 10 hours behind one same-file card after another, and health never named it: a waiting
# card keeps its live record fresh, so it is never silent. A card that has waited on other cards for more than
# tunables.waitLimitMin minutes in all is stuck, with every card it waited on. A card's first wait, and health on it, is
# read from a real loop's wait in t_waitsum; here the cards' records and live records are written as the loop writes
# them, with no card run, the limit is the pack's (1 minute), and health is asked on the tests'
# clock (CONVEYOR_NOW). All its waits count, not the one it is in: c9-9 waited 40 s behind #7 and #8 before this wait,
# 30 s old, on #11; c10-10 waited 20 s before its own. Neither wait alone passes the minute. c12-12 has waited 31
# minutes on #11, a card that is on no belt: stuck for that alone (its wait never ends), it is still said to have
# waited that long, and behind which cards (a bug: the chain was left out of a card another check had listed).
t_waitlong() {
  local k s now; setup '[]'; tune '.tunables.waitLimitMin = 1'
  now=$(date +%s); mkdir -p "$ST" "$T/$CASE/cards"
  for k in 9 10 12; do
    for s in picked start; do
      jq -cn --arg c "c$k-$k" --argjson n "$k" --arg s "$s" --argjson t "$now" \
        '{card:$c,issue:$n,step:$s,time:($t | todate),tokens:{claude:0,codex:0},result:"ok",sha:"",reason:""} + (if $s == "start" then {of:"land"} else {title:"t",created:"2026-01-01T00:00:00Z"} end)' >> "$ST/cards.jsonl"
    done
    jq -cn --argjson t "$now" --argjson b "$(case $k in 9) echo 40 ;; 10) echo 20 ;; *) echo 0 ;; esac)" --argjson a "$([ $k = 12 ] && echo 1860 || echo 30)" --arg c7 c7-7 --arg c8 c8-8 \
      '{step: "land", at: ($t - $a | todate), last: ($t | todate), turns: 0, waits: {on: "c11-11", paths: ["a.txt"]}, waited: {before: $b, behind: [$c7, $c8, "c11-11"]}}' > "$T/$CASE/cards/c$k-$k.live"
  done
  [ "$(CONVEYOR_NOW=$now loop health | jq -c '.stuck | map([.card, .waitedMin, .waitsOn.issue, (.waitedOn | map(.issue))])')" = '[["c12-12",31,11,[7,8,11]],["c9-9",1,11,[7,8,11]]]' ] \
    || fail "a card whose waits pass the limit together is not stuck with the chain it waited behind (one whose holder is gone too), or one whose waits do not is: $(CONVEYOR_NOW=$now loop health | jq -c .stuck)"
}

# Bug: a wait that ended between two looks of the waiting card (one every tunables.live seconds) was not counted, so
# the waits of a card that waited behind one card after another never added up. #8 (a.txt, b.txt) waits on #7
# (a.txt), which lands during #8's first look-again pause (3 s here); #8 then gives way for the session that brings
# it onto main, #9 (b.txt) takes the turn and holds b.txt in its tests ($STUB/go9), and #8 waits again, on #9: that
# wait's live record counts the first wait whole, and health adds it to the second.
t_waitsum() {
  setup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02),$(issue 9 2026-01-03)]"; for i in 1 2 3 4 5 6; do echo "$GO" > "$STUB/review.$i"; done
  tune '.tunables.live = 3'
  cat > "$STUB/build" <<'EOF'
case $PWD in
  *-7) echo seven >> a.txt ;;
  *-8) if grep -q '^# Main moved: apply the same change' "$STUB/brief"; then
      while [ -d "$STUB" ] && [ ! -e "$STUB/go9" ] && ! jq -e .held ../*-9.claim >/dev/null 2>&1; do sleep 0.1; done
      printf 'one\nseven\neight\n' > a.txt; echo eight >> b.txt
    else while [ -d "$STUB" ]; do jq -e .held ../*-7.claim >/dev/null 2>&1 && break; sleep 0.1; done; echo eight >> a.txt; echo eight > b.txt; fi ;;
  *-9) while [ -d "$STUB" ]; do jq -e .away ../*-8.claim >/dev/null 2>&1 && break; sleep 0.1; done; echo nine > b.txt ;;
esac
EOF
  echo 'case $PWD in *-7) while [ -d "$STUB" ] && [ ! -e "$STUB/go7" ]; do sleep 0.1; done ;; *-9) while [ -d "$STUB" ] && [ ! -e "$STUB/go9" ]; do sleep 0.1; done ;; esac' >> "$STUB/test-cmd"
  loop run >/dev/null 2>&1 & run=$!
  wait_until "jq -e .waits.on '$T/$CASE/cards/'*-8.live" || fail "#8 never waited on #7"
  c7=$(st 'select(.issue == 7 and .step == "picked") | .card'); c8=$(st 'select(.issue == 8 and .step == "picked") | .card'); c9=$(st 'select(.issue == 9 and .step == "picked") | .card')
  # The first wait (t_waitlong's bug): its live record names what the card waited before it, nothing, and behind which
  # card; with a limit of 1 minute (the pack's, for these two asks), past it, and not at it, health names it stuck with
  # the card it waits on.
  live=$(cat "$T/$CASE/cards/$c8.live")
  [ "$(jq -c .waited <<<"$live")" = "{\"before\":0,\"behind\":[\"$c7\"]}" ] || fail "the live record of a first wait does not name what the card waited before it, and behind which cards: $live"
  at=$(jq -r '.at | fromdate' <<<"$live")
  h=$(CONVEYOR_NOW=$((at + 60)) tuned '.tunables.waitLimitMin = 1' loop health) || fail "health failed: $h"
  [ "$(jq -c .stuck <<<"$h")" = '[]' ] || fail "a card that has waited no longer than the limit is stuck: $(jq -c .stuck <<<"$h")"
  h=$(CONVEYOR_NOW=$((at + 61)) tuned '.tunables.waitLimitMin = 1' loop health) || fail "health failed: $h"
  [ "$(jq -c .stuck <<<"$h")" = "$(jq -cn --arg c7 "$c7" --arg c8 "$c8" --arg at "$(jq -r .at <<<"$live")" \
      '[{card: $c8, issue: 8, step: "waiting", since: $at, waitsOn: {card: $c7, issue: 7, state: "test"}, waitedMin: 1, waitedOn: [{card: $c7, issue: 7, state: "test"}]}]')" ] \
    || fail "a card that has waited on another for longer than waitLimitMin is not stuck with the card it waited on: $(jq -c .stuck <<<"$h")"
  : > "$STUB/go7"
  wait_until "jq -e --arg c '$c9' '.waits.on == \$c' '$T/$CASE/cards/$c8.live'" "st '\"\(.issue) \(.step) \(.of // \"\") \(.reason)\"' | tr '\n' ," || fail "#8 never waited on #9"
  live=$(cat "$T/$CASE/cards/$c8.live")
  [ "$(jq -c --arg c7 "$c7" --arg c9 "$c9" '.waited.before >= 2 and .waited.behind == [$c7, $c9]' <<<"$live")" = true ] \
    || fail "the second wait of a card does not count its first, which ended between two looks, or does not name both cards: $live"
  # Half an hour into the second wait the two together are past the 30 minutes of waitLimitMin, by the first alone.
  h=$(CONVEYOR_NOW=$(($(jq -r '.at | fromdate' <<<"$live") + 1800)) loop health) || fail "health failed: $h"
  [ "$(jq -c '.stuck | map(select(.issue == 8) | [.waitedMin, (.waitedOn | map(.issue))])' <<<"$h")" = '[[30,[7,9]]]' ] \
    || fail "health does not add the wait that ended to the one the card is in: $(jq -c .stuck <<<"$h")"
  # The waits end: #9's tests let go, every card lands, #9 before #8, which waited on it.
  : > "$STUB/go9"; wait $run || fail "run exited non-zero"
  [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "7 9 8 " ] || fail "the three did not land: $(st '"\(.issue) \(.step) \(.reason)"' | tr '\n' ,)"
}

# Bug: a card that kept its claim through the session that brought it onto main (it has given way 3 times: giveway())
# and then waited again, on a card that holds a file that session added, wrote no start line for that wait: its last
# line was the session's, and health never counted the wait. #8 (a.txt, given way 3 times) waits on #7 (a.txt); #7
# lands, and the session that brings #8 onto main changes b.txt too, which #9 holds in its tests ($STUB/go9): #8 waits
# on #9, and a minute (waitLimitMin here) into that wait health names it with both cards. #9, its tests over, claims
# again to land: #8, the older, goes first, and #9 is brought onto its main.
t_waitkept() {
  setup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02),$(issue 9 2026-01-03)]"; for i in $(seq 8); do echo "$GO" > "$STUB/review.$i"; done
  tune '.tunables.waitLimitMin = 1'
  echo one > "$R/b.txt"; git -C "$R" add b.txt; git -C "$R" commit -qm "b.txt"; git -C "$R" push -q origin main
  cat > "$STUB/build" <<'EOF'
case $PWD in
  *-7) echo seven >> a.txt ;;
  *-8) if grep -q '^# Main moved: apply the same change' "$STUB/brief"; then
      while [ -d "$STUB" ] && [ ! -e "$STUB/go9" ] && ! jq -e .held ../*-9.claim >/dev/null 2>&1; do sleep 0.1; done
      printf 'one\nseven\neight\n' > a.txt; echo eight >> b.txt
    else while [ -d "$STUB" ]; do jq -e .held ../*-7.claim >/dev/null 2>&1 && break; sleep 0.1; done; echo eight >> a.txt; echo '{"gave": 3}' > "$PWD.claim"; fi ;;
  *-9) echo nine >> b.txt ;;
esac
EOF
  echo 'case $PWD in *-7) while [ -d "$STUB" ] && [ ! -e "$STUB/go7" ]; do sleep 0.1; done ;; *-9) while [ -d "$STUB" ] && [ ! -e "$STUB/go9" ]; do sleep 0.1; done ;; esac' >> "$STUB/test-cmd"
  loop run >/dev/null 2>&1 & run=$!
  wait_until "jq -e .waits.on '$T/$CASE/cards/'*-8.live" || fail "#8 never waited on #7"
  : > "$STUB/go7"
  c8=$(st 'select(.issue == 8 and .step == "picked") | .card'); c9=$(st 'select(.issue == 9 and .step == "picked") | .card')
  wait_until "jq -e --arg c '$c9' '.waits.on == \$c' '$T/$CASE/cards/$c8.live'" "st '\"\(.issue) \(.step) \(.of // \"\") \(.reason)\"' | tr '\n' ," || fail "#8 never waited on #9"
  [ "$(jq -c '[.held, .away, .gave]' "$T/$CASE/cards/$c8.claim")" = '[false,null,3]' ] || fail "#8 gave way for its session, or does not wait at its claim: $(cat "$T/$CASE/cards/$c8.claim")"
  live=$(cat "$T/$CASE/cards/$c8.live")
  h=$(CONVEYOR_NOW=$(($(jq -r '.at | fromdate' <<<"$live") + 61)) loop health) || fail "health failed: $h"
  [ "$(jq -c '.stuck | map(select(.issue == 8) | [.step, .waitedMin, .waitsOn.issue, (.waitedOn | map(.issue))])' <<<"$h")" = '[["waiting",1,9,[7,9]]]' ] \
    || fail "a wait that follows a session of a card that kept its claim is not counted: $(jq -c .stuck <<<"$h") $(st 'select(.issue == 8) | "\(.step) \(.of // "")"' | tr '\n' ,)"
  # #9, its tests over, claims again to land: #8, the older, kept its claim and goes first, and #9 is brought onto its main.
  : > "$STUB/go9"; wait $run || fail "run exited non-zero"
  [ "$(st 'select(.step == "landed") | .issue' | tr '\n' ' ')" = "7 8 9 " ] || fail "the three did not land: $(st '"\(.issue) \(.step) \(.reason)"' | tr '\n' ,)"
}

# Card c7-7's records, each a step or start:<step> (review:GO: a step and its result), at <epoch seconds>, as the loop
# writes them: a case of what health makes of a card at a step writes them, with no card run.
c7at() { # <epoch seconds> <step>...
  local t=$1; shift; mkdir -p "$ST"
  printf '%s\n' "$@" | jq -cR --argjson t "$t" 'split(":") as [$s, $x]
    | {card:"c7-7",issue:7,step:$s,time:($t | todate),tokens:{claude:0,codex:0},result:"ok",sha:"",reason:""} + if $s == "start" then {of: $x} elif $x then {result: $x} else {} end' >> "$ST/cards.jsonl"
}
# Runs <command file> in the background as card c7-7's <step>, watched by the engine's own watch() (lib/session.sh), as
# a card's step is: its output where the card's is ($w.out, or $w.test for a test run, whose logs are in $w.testlog,
# CONVEYOR_TEST_LOG) and its live record in $w.live. Sets run (the watch's pid) and w.
c7watch() { # <step> <command file>
  local f; w=$T/$CASE/cards/c7-7; f=$w.out; [ "$1" != test ] || f=$w.test; mkdir -p "$w.testlog"
  ( . "$SRC/lib/portable.sh"; eval "$(for g in watch testlogs testcases testdone; do sed -n "/^$g() {/,/^}/p" "$SRC/lib/session.sh"; done)"
    # shellcheck disable=SC2034 # LIVE and STUCK are read by watch(), defined by the eval
    LIVE=0.5 STUCK=1200; (cd "$T/$CASE" && CONVEYOR_TEST_LOG=$w.testlog exec bash "$2" < /dev/null) > "$f" 2>&1 &
    watch $! "$f" "$w.live" "$1" ) > "$T/$CASE/run.out" 2>&1 & run=$!
}

# Bug: a test step ran 41 minutes, 35 of them with two cases hung; the other cases kept printing, so the output was
# never silent and health never named the card. A runner names each running case in its log folder (cases/<name>,
# from the case's start to its end); a case that has run for tunables.caseStuck seconds makes the card stuck, by its
# name, whatever the others print. Card c7-7 is at its test step by its records, and its run is watched as its test
# step does it (c7watch), with no card run. Here the limit is 2 s: slow hangs until $STUB/go, quick ends at once, and
# the run prints a line every 0.1 s until $STUB/end. A case that ends between the look that lists the cases and the one
# that reads their times is left out and the others stay (a bug: the live record then took no cases at all): the third
# file's name, two lines, is listed as two files that are not there.
t_casehung() {
  local c=c7-7 was h live now s; setup "[$(issue 7 2026-01-01)]"; tune '.tunables.caseStuck = 2'
  c7at "$(date +%s)" picked worktree deps brief start:build build start:review review:GO start:test
  cat > "$STUB/cases-cmd" <<'EOF'
C=$CONVEYOR_TEST_LOG/cases; mkdir -p "$C"; : > "$C/slow"; : > "$C/quick"; rm "$C/quick"; : > "$C/gone"$'\n'"x"
while [ -d "$STUB" ] && [ ! -e "$STUB/end" ]; do echo "ok another case"; [ ! -e "$STUB/go" ] || rm -f "$C/slow"; sleep 0.1; done
EOF
  c7watch test "$STUB/cases-cmd"
  wait_until "[ \"\$(loop health | jq -c '.stuck | map([.issue, .step, .cases])')\" = '[[7,\"test\",[\"slow\"]]]' ]" "loop health | jq -c .stuck; cat '$T/$CASE/cards/'*.live" \
    || fail "a test step with one case past its ceiling is not stuck by that case's name"
  # The run still prints: its last output moves on, and the card is stuck all the same, since the case began.
  was=$(jq -r .last "$T/$CASE/cards/$c.live")
  wait_until "[ \"\$(jq -r .last '$T/$CASE/cards/$c.live')\" != '$was' ]" || fail "the run did not go on printing"
  h=$(loop health); live=$(cat "$T/$CASE/cards/$c.live")
  [ "$(jq -c '.stuck | map([.issue, .step, .cases, .since])' <<<"$h")" = "[[7,\"test\",[\"slow\"],$(jq -c '.cases[0].since' <<<"$live")]]" ] \
    && [ "$(jq -r '.last > .cases[0].since' <<<"$live")" = true ] \
    || fail "a hung case is not named while the other cases still print: $(jq -c .stuck <<<"$h") $live"
  # Once the case ends, the run going on, the card is no longer stuck.
  : > "$STUB/go"
  wait_until "[ \"\$(loop health | jq -c .stuck)\" = '[]' ]" "loop health | jq -c .stuck; cat '$T/$CASE/cards/'*.live" || fail "the card is still stuck once its hung case ended"
  : > "$STUB/end"; wait $run || fail "the watch of the test run exited non-zero: $(cat "$T/$CASE/run.out")"
  # Once every case is silent too, the card is stuck for that already, and the case is still named (a bug: its name
  # was left out of a card another check had listed). c12-12's run and its case slow began 1300 s ago, with no output since.
  now=$(date +%s)
  for s in picked start; do
    jq -cn --arg s "$s" --argjson t "$((now - 1300))" \
      '{card:"c12-12",issue:12,step:$s,time:($t | todate),tokens:{claude:0,codex:0},result:"ok",sha:"",reason:""} + (if $s == "start" then {of:"test"} else {title:"t",created:"2026-01-01T00:00:00Z"} end)' >> "$ST/cards.jsonl"
  done
  mkdir -p "$T/$CASE/cards"
  jq -cn --argjson t "$((now - 1300))" '{step: "test", at: ($t | todate), last: ($t | todate), turns: 0, files: {run: 0, of: null}, cases: [{name: "slow", since: ($t | todate)}]}' > "$T/$CASE/cards/c12-12.live"
  [ "$(CONVEYOR_NOW=$now loop health | jq -c '.stuck | map([.card, .step, .cases])')" = '[["c12-12","test",["slow"]]]' ] \
    || fail "a hung case is not named once the whole test run is silent: $(CONVEYOR_NOW=$now loop health | jq -c .stuck)"
}

# Bug: build and fix sessions stalled, receiving nothing, for 10 and 20 minutes before anyone acted: health named a
# silent card only after tunables.stuck (20 minutes). A session (build, fix, rebase) with no output for
# tunables.sessionStuck seconds, 10 minutes unless the pack says otherwise, is stuck. The card c7-7 is in its build by
# its records, as the loop writes them, with no card run, and its session has said nothing; health is asked on the
# tests' clock (CONVEYOR_NOW).
t_sessionquiet() {
  local at; setup "[$(issue 7 2026-01-01)]"; at=$(date +%s); c7at "$at" picked worktree deps brief start:build
  [ "$(loop health | jq -c '.homes["tunables.sessionStuck"]')" = '{"value":600,"home":"schema default"}' ] || fail "the session limit is not 10 minutes by default: $(loop health | jq -c .homes)"
  [ "$(CONVEYOR_NOW=$((at + 599)) loop health | jq -c .stuck)" = '[]' ] || fail "a session silent for under 10 minutes is stuck: $(CONVEYOR_NOW=$((at + 599)) loop health | jq -c .stuck)"
  [ "$(CONVEYOR_NOW=$((at + 600)) loop health | jq -c '.stuck | map([.issue, .step, .since])')" = "[[7,\"build\",\"$(jq -rn --argjson t "$at" '$t | todate')\"]]" ] \
    || fail "a session with no output for 10 minutes is not stuck: $(CONVEYOR_NOW=$((at + 600)) loop health | jq -c .stuck)"
  # The limit is the pack's setting.
  [ "$(CONVEYOR_NOW=$((at + 600)) tuned '.tunables.sessionStuck = 900' loop health | jq -c .stuck)" = '[]' ] || fail "the session limit is not the pack's tunables.sessionStuck"
}

# Bug: a stalled session was still sent keep-alive bytes, lines with nothing in them, and each counted as output, so
# the session was never silent for tunables.sessionStuck. Only a line that says something is output. The session here
# calls one tool, then is sent an empty line every 0.1 s until $STUB/go: its last output stays the tool call, and it is
# stuck 10 minutes after that. Card c7-7 is in its build by its records, written before the tool call, and its session
# is watched as its build does it (c7watch), with no card run.
t_keepalive() {
  local c=c7-7 live was at n; setup "[$(issue 7 2026-01-01)]"; c7at "$(($(date +%s) - 5))" picked worktree deps brief start:build
  cat > "$STUB/session" <<'EOF'
echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"npm test"}}]}}'
while [ -d "$STUB" ] && [ ! -e "$STUB/go" ]; do echo; sleep 0.1; done
EOF
  c7watch build "$STUB/session"
  wait_until "jq -e '.action == \"Bash: npm test\"' '$T/$CASE/cards/$c.live'" || fail "the session's tool call never showed in its live record"
  live=$T/$CASE/cards/$c.live; was=$(jq -r .last "$live"); at=$(jq -rn --arg t "$was" '$t | fromdate')
  # Empty lines written more than a second after that output, and read: the live record is written anew at each look
  # that finds the output grown.
  wait_until "[ \$(date +%s) -gt $((at + 2)) ]" || fail "the clock did not move on"
  : > "$STUB/mark"; n=$(wc -l < "$T/$CASE/cards/$c.out")
  wait_until "[ \$(wc -l < '$T/$CASE/cards/$c.out') -gt $n ] && [ '$live' -nt '$STUB/mark' ]" || fail "the session's empty lines were never read"
  [ "$(jq -r .last "$live")" = "$was" ] || fail "an empty line counts as a session's output: last $(jq -r .last "$live"), the tool call was at $was"
  [ "$(CONVEYOR_NOW=$((at + 599)) loop health | jq -c .stuck)" = '[]' ] || fail "a session whose last output is under 10 minutes old is stuck: $(CONVEYOR_NOW=$((at + 599)) loop health | jq -c .stuck)"
  [ "$(CONVEYOR_NOW=$((at + 600)) loop health | jq -c '.stuck | map([.issue, .step, .since])')" = "[[7,\"build\",\"$was\"]]" ] \
    || fail "a session sent only empty lines for 10 minutes is not stuck: $(CONVEYOR_NOW=$((at + 600)) loop health | jq -c .stuck)"
  : > "$STUB/go"; wait $run || fail "the watch of the session exited non-zero: $(cat "$T/$CASE/run.out")"
}

# Bug caught (#632): a card landing normally was listed stuck, and woke the Foreman, as its session process had ended:
# the loop lands it. With the loop running, a card in its land step whose process is gone is stuck only after STUCK
# seconds with no new line; a card in its build whose process is gone is stuck at once, as is the landing card once no
# loop runs. Both cards' worktree lines name a process start no process has.
t_gonelanding() {
  local k now; setup '[]'; tune '.tunables.stuck = 1200'; now=$(date +%s)
  for k in 1 2; do
    jq -cn --arg c "c$k-$k" --argjson n "$k" --argjson t "$now" --arg of "$([ $k = 1 ] && echo land || echo build)" --argjson p $$ \
      '{card:$c,issue:$n,time:($t | todate),tokens:{claude:0,codex:0},result:"ok",sha:"",reason:""} as $l
       | ($l + {step:"picked",title:"t",created:"2026-01-01T00:00:00Z"}), ($l + {step:"worktree",pid:$p,started:"not a start"}), ($l + {step:"start",of:$of})'
  done >> "$ST/cards.jsonl"
  ( exec 9>>"$ST/cards.jsonl.run"; flock 9; : > "$STUB/locked"; until [ -e "$STUB/free" ] || [ ! -d "$STUB" ]; do sleep 0.1; done ) & # sleep: the loop's lock held until freed
  wait_until "[ -e '$STUB/locked' ]" || fail "the loop's lock was never taken"
  [ "$(CONVEYOR_NOW=$((now + 30)) loop health | jq -c '[.loop, (.stuck | map([.issue, .step]))]')" = '[true,[[2,"build"]]]' ] \
    || fail "30 s after its land began, a landing card whose process is gone is stuck while the loop runs, or a building one is not: $(CONVEYOR_NOW=$((now + 30)) loop health | jq -c '[.loop, .stuck]')"
  [ "$(CONVEYOR_NOW=$((now + 1200)) loop health | jq -c '.stuck | map([.issue, .step, .since])')" = "[[1,\"land\",\"$(jq -rn --argjson t "$now" '$t | todate')\"],[2,\"build\",\"$(jq -rn --argjson t "$now" '$t | todate')\"]]" ] \
    || fail "a landing card with no new line for STUCK is not stuck: $(CONVEYOR_NOW=$((now + 1200)) loop health | jq -c .stuck)"
  : > "$STUB/free"; wait
  [ "$(CONVEYOR_NOW=$((now + 30)) loop health | jq -c '[.loop, (.stuck | map(.issue))]')" = '[false,[1,2]]' ] \
    || fail "with no loop running, a landing card whose process is gone is not stuck at once: $(CONVEYOR_NOW=$((now + 30)) loop health | jq -c '[.loop, .stuck]')"
}

# Bug caught (#515): a project's test command printed no `TESTRUN sec` lines, so no card recorded test times, and
# health said nothing for the Board's Health to show. untimed counts its last card test runs, a pass and a fail, when
# none recorded times (a batch's reused line and a run that selected no file are no run); once the last run records
# times, it is 0.
t_healthuntimed() {
  local o; setup '[]'
  for o in '{}' '{result: "fail"}' '{reused: true, times: null}' '{ended: "nothing selected"}'; do
    jq -cn "{card: \"c0-1\", issue: 1, step: \"test\", time: \"2026-11-01T00:00:00Z\", tokens: {claude: 0, codex: 0}, result: \"pass\", sha: \"\", reason: \"\"} + $o"
  done >> "$ST/cards.jsonl"
  [ "$(loop health | jq -c .untimed)" = 2 ] || fail "health does not count the last card test runs that recorded no times: $(loop health 2>&1 | jq -c .untimed)"
  jq -cn '{card: "c0-2", issue: 2, step: "test", time: "2026-11-02T00:00:00Z", tokens: {claude: 0, codex: 0}, result: "pass", sha: "", reason: "", times: {"a.test": 1}}' >> "$ST/cards.jsonl"
  [ "$(loop health | jq -c .untimed)" = 0 ] || fail "health still says no times after a run that recorded them: $(loop health | jq -c .untimed)"
}
