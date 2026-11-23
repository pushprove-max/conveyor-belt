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
# tunables.waitLimitMin minutes in all is stuck, with every card it waited on. The live records settle() writes are
# read in t_waitsum; here the cards' records and live records are written as the loop writes them, with no card run, the limit is the pack's (1 minute), and health is asked on the tests'
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

# wssettle: settle() of card c8-8 (a.txt) at its landing step, as card() calls it, in the engine shell (fx_in), with
# no loop run. Its claim (wsclaim, a stand-in for `locked claim`) says it waits on c7-7, then that it waits on nothing,
# then that it waits on c9-9. Main moved under #8 in a.txt (#7 landed), so between the two waits its patch no longer
# applies: it keeps its claim (given way 3 times: giveway() refuses) through one fit session (session(), a stand-in
# that merges a.txt). Each look of a wait (wssleep) copies the live record to $STUB/live<n> and moves the shell's clock
# (SECONDS) on 20 s in place of the sleep; the second wait's first look ends the call (exit 8).
wsclaim() {
  local n; n=$(($(cat "$STUB/claims" 2>/dev/null || echo 0) + 1)); echo "$n" > "$STUB/claims"
  case $n in 1) echo '{"on":"c7-7","paths":["a.txt"]}' ;; 2) ;; *) echo '{"on":"c9-9","paths":["a.txt"]}' ;; esac
}
wssleep() {
  [ "${FUNCNAME[2]}" = settle ] || { command sleep "$@"; return; } # sleep: a sleep outside settle() is the real one
  WSLOOKS=$((WSLOOKS + 1)); cp "$CONVEYOR_CARDS/c8-8.live" "$STUB/live$WSLOOKS"; SECONDS=$((SECONDS + 20)); [ "$WSLOOKS" -lt 2 ] || exit 8
}
wssettle() {
  local n; setup '[]'; CARDS=$T/$CASE/cards; mkdir -p "$CARDS"
  for n in 7 8 9; do landed "$n" | jq -c --arg c "c$n-$n" '.card = $c | .step = "picked"' >> "$ST/cards.jsonl"; done
  git -C "$R" worktree add -q --detach "$CARDS/c8-8" main && echo eight >> "$CARDS/c8-8/a.txt" && git -C "$CARDS/c8-8" add -A \
    && echo seven >> "$R/a.txt" && git -C "$R" commit -qam "title 7 (#7)" || fail "the change of #8, or #7's on main"
  echo "{\"pid\":$$,\"paths\":[\"a.txt\"],\"held\":true,\"gave\":3}" > "$CARDS/c8-8.claim"
  fx_in 'cd "$R" || exit 9; caught="" waitsec=0 behind="[]" parsecheck="" WSLOOKS=0
    eval "$(declare -f locked | sed 1s/^locked/wslocked/)"
    locked() { [ "$1" = claim ] || { wslocked "$@"; return; }; wsclaim; }
    sleep() { wssleep "$@"; }
    session() { printf "one\nseven\neight\n" > "$1/a.txt"; echo "{}"; }
    settle c8-8 8 "$CONVEYOR_CARDS/c8-8" "Build the issue." land "$(issue 8 2026-01-02)"; echo "settle: $?"'
  [ "$RC" = 8 ] && [ -s "$STUB/live1" ] && [ -s "$STUB/live2" ] || fail "#8 did not wait on #7, then on #9: exit $RC: $(cat "$T/$CASE/run.out")"
  [ "$(jq -c '[.held, .away]' "$CARDS/c8-8.claim")" = '[true,null]' ] || fail "#8 gave way for its session: $(cat "$CARDS/c8-8.claim")"
}

# Bug: a wait that ended between two looks of the waiting card (one every tunables.live seconds) was not counted, so
# the waits of a card that waited behind one card after another never added up. #8's first wait, on #7, ends between
# two looks (wssettle): the live record of its next wait, on #9, counts the first whole (20 s on the shell's clock) and
# names both cards, and health adds it to the second.
t_waitsum() {
  local h at
  wssettle
  [ "$(jq -c .waited "$STUB/live1")" = '{"before":0,"behind":["c7-7"]}' ] \
    || fail "the live record of a first wait does not name what the card waited before it, and behind which cards: $(cat "$STUB/live1")"
  [ "$(jq -c '.waited.before >= 20 and .waited.behind == ["c7-7", "c9-9"]' "$STUB/live2")" = true ] \
    || fail "the second wait of a card does not count its first, which ended between two looks, or does not name both cards: $(cat "$STUB/live2")"
  # When the two together have lasted exactly the 30 minutes of waitLimitMin, the card has not waited too long: only
  # past it. (By then it is listed as silent, an entry with no waitedMin.)
  at=$(jq -r '.at | fromdate' "$STUB/live2")
  h=$(CONVEYOR_NOW=$((at + 1800 - $(jq -r .waited.before "$STUB/live2"))) loop health) || fail "health failed: $h"
  [ "$(jq -c '.stuck | map(select(.issue == 8 and has("waitedMin")))' <<<"$h")" = '[]' ] \
    || fail "a card whose waits together last exactly waitLimitMin has waited too long: $(jq -c .stuck <<<"$h")"
  # Half an hour into the second wait the two together are past the 30 minutes of waitLimitMin, by the first alone.
  h=$(CONVEYOR_NOW=$((at + 1800)) loop health) || fail "health failed: $h"
  [ "$(jq -c '.stuck | map(select(.issue == 8) | [.waitedMin, (.waitedOn | map(.issue))])' <<<"$h")" = '[[30,[7,9]]]' ] \
    || fail "health does not add the wait that ended to the one the card is in: $(jq -c .stuck <<<"$h")"
}

# Bug: a card that kept its claim through the session that brought it onto main (it has given way 3 times: giveway())
# and then waited again wrote no start line for that wait: its last line was the session's, and health never counted
# the wait. After #8's fit session (wssettle) its last line is the start line of its wait on #9, and a minute
# (waitLimitMin here) into that wait health names it with both cards.
t_waitkept() {
  local h
  wssettle
  [ "$(st 'select(.card == "c8-8") | "\(.step):\(.of // "")"' | tail -n 2 | tr '\n' ' ')" = "fix: start:land " ] \
    || fail "a wait that follows a session of a card that kept its claim wrote no start line: $(st 'select(.card == "c8-8") | "\(.step):\(.of // "")"' | tr '\n' ' ')"
  h=$(CONVEYOR_NOW=$(($(jq -r '.at | fromdate' "$STUB/live2") + 61)) tuned '.tunables.waitLimitMin = 1' loop health) || fail "health failed: $h"
  [ "$(jq -c '.stuck | map(select(.issue == 8) | [.step, .waitedMin, .waitsOn.issue, (.waitedOn | map(.issue))])' <<<"$h")" = '[["waiting",1,9,[7,9]]]' ] \
    || fail "a wait that follows a session of a card that kept its claim is not counted: $(jq -c .stuck <<<"$h")"
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
  ( . "$SRC/lib/portable.sh"; eval "$(for g in watch testlogs testcases testdone testprogress; do sed -n "/^$g() {/,/^}/p" "$SRC/lib/session.sh"; done)"
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
  local c=c7-7 h live now s; setup "[$(issue 7 2026-01-01)]"; tune '.tunables.caseStuck = 2'
  c7at "$(date +%s)" picked worktree deps brief start:build build start:review review:GO start:test
  cat > "$STUB/cases-cmd" <<'EOF'
C=$CONVEYOR_TEST_LOG/cases; mkdir -p "$C"; : > "$C/slow"; : > "$C/quick"; rm "$C/quick"; : > "$C/gone"$'\n'"x"
while [ -d "$STUB" ] && [ ! -e "$STUB/end" ]; do echo "ok another case"; [ ! -e "$STUB/go" ] || rm -f "$C/slow"; sleep 0.1; done
EOF
  c7watch test "$STUB/cases-cmd"
  # The watch's live record lists the case slow alone, and the run still prints: its last output is later than the
  # case's start (waited on, as watch() writing the cases from the runner's folder is part of what this case checks). Health is asked once, on the tests' clock (CONVEYOR_NOW) at caseStuck past that start, not polled
  # on the real clock: the card is stuck by that case's name, since it began, whatever the other cases print.
  live=$T/$CASE/cards/$c.live
  wait_until "jq -e '(.cases | map(.name)) == [\"slow\"] and .last > .cases[0].since' '$live'" "cat '$live'" \
    || fail "the live record does not list the case slow alone, or the run did not go on printing"
  now=$(($(jq -r '.cases[0].since | fromdate' "$live") + 2))
  h=$(CONVEYOR_NOW=$now loop health)
  [ "$(jq -c '.stuck | map([.issue, .step, .cases, .since])' <<<"$h")" = "[[7,\"test\",[\"slow\"],$(jq -c '.cases[0].since' "$live")]]" ] \
    || fail "a hung case is not named while the other cases still print: $(jq -c .stuck <<<"$h") $(cat "$live")"
  # Once the case ends, the run going on, the card is no longer stuck, at the same clock.
  : > "$STUB/go"
  wait_until "jq -e '.cases == []' '$live'" "cat '$live'" || fail "the live record still lists the case once it ended"
  [ "$(CONVEYOR_NOW=$now loop health | jq -c .stuck)" = '[]' ] || fail "the card is still stuck once its hung case ended: $(CONVEYOR_NOW=$now loop health | jq -c .stuck)"
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
  local at h; setup "[$(issue 7 2026-01-01)]"; at=$(date +%s); c7at "$at" picked worktree deps brief start:build
  h=$(CONVEYOR_NOW=$((at + 599)) loop health) || fail "health failed: $h"
  [ "$(jq -c '.homes["tunables.sessionStuck"]' <<<"$h")" = '{"value":600,"home":"schema default"}' ] || fail "the session limit is not 10 minutes by default: $(jq -c .homes <<<"$h")"
  [ "$(jq -c .stuck <<<"$h")" = '[]' ] || fail "a session silent for under 10 minutes is stuck: $(jq -c .stuck <<<"$h")"
  [ "$(CONVEYOR_NOW=$((at + 600)) loop health | jq -c '.stuck | map([.issue, .step, .since])')" = "[[7,\"build\",\"$(jq -rn --argjson t "$at" '$t | todate')\"]]" ] \
    || fail "a session with no output for 10 minutes is not stuck: $(CONVEYOR_NOW=$((at + 600)) loop health | jq -c .stuck)"
  # The limit is the pack's setting.
  [ "$(CONVEYOR_NOW=$((at + 600)) tuned '.tunables.sessionStuck = 900' loop health | jq -c .stuck)" = '[]' ] || fail "the session limit is not the pack's tunables.sessionStuck"
}

# Issue 366: a main-red fix card's run of main's failing cases after its build (bugproof.sh redproof(), mainred.sh redrun()) keeps
# its live record in $CARDS/mainrun/<card>.unfixed.live, not <card>.live, and its last line is its build's: health
# called it stuck 20 minutes after the build while its tests ran. The card's records end with its build, 1300 s ago
# (past tunables.stuck), and the run is watched as tests() watches it (the engine's own watch()), with no card run.
t_proofrun() {
  local c=c0-0 w now live s; setup '[]'; now=$(date +%s); mkdir -p "$ST" "$T/$CASE/cards/mainrun"
  for s in picked start build; do
    jq -cn --arg c "$c" --arg s "$s" --argjson t "$((now - 1300))" '{card:$c,issue:0,step:$s,time:($t | todate),tokens:{claude:0,codex:0},result:"ok",sha:"",reason:""}
      + {picked: {title:"Main is red: t", mainRed:"0123456789abcdef", created:"2026-01-01T00:00:00Z"}, start: {of:"build"}, build: {}}[$s]' >> "$ST/cards.jsonl"
  done
  [ "$(loop health | jq -c '.stuck | map(.card)')" = "[\"$c\"]" ] || fail "the card is not stuck with no run: $(loop health | jq -c .stuck)"
  w=$T/$CASE/cards/mainrun/$c.unfixed; mkdir -p "$w.testlog"
  ( . "$SRC/lib/portable.sh"; eval "$(for g in watch testlogs testcases testdone testprogress; do sed -n "/^$g() {/,/^}/p" "$SRC/lib/session.sh"; done)"
    # shellcheck disable=SC2034 # LIVE and STUCK are read by watch(), defined by the eval
    LIVE=0.2 STUCK=1200; (while [ -d "$STUB" ] && [ ! -e "$STUB/end" ]; do echo "ok a case"; sleep 0.1; done) > "$w.test" 2>&1 &
    watch $! "$w.test" "$w.live" test ) > "$T/$CASE/run.out" 2>&1 & run=$!
  wait_until "[ -s '$w.live' ]" || fail "the run kept no live record"
  live=$(cat "$w.live"); [ "$(jq -r .step <<<"$live")" = test ] || fail "the run's live record is not of step test: $live"
  [ "$(loop health | jq -c .stuck)" = '[]' ] || fail "a main-red fix card is stuck while its run of main's failing cases makes progress: $(loop health | jq -c .stuck) $live"
  : > "$STUB/end"; wait $run || fail "the watch of the run exited non-zero: $(cat "$T/$CASE/run.out")"
}

# Issue 611: after a card's tests failed, the run again of its failed tests on main (mainred.sh verdicts(), in
# $CARDS/mainrun/<card>) keeps its live record in mainrun/<card>.live; the card's own live record is gone and it writes
# no line. Health called the card stuck, since its Test step's start, while that run (and its .test file before it)
# made output. Card c7-7 began its test step 1300 s ago (past tunables.stuck, 1200 s) and has no live record of its own.
t_mainrunout() {
  local -x FILEMODE=1
  local now d=$T/$CASE/cards; setup "[$(issue 7 2026-01-01)]"; now=$(date +%s); c7at "$((now - 1300))" picked worktree deps brief start:build build start:review review:GO start:test
  at() { TZ=UTC0 touch -t "$(jq -rn --argjson t "$1" '$t | strftime("%Y%m%d%H%M.%S")')" "$2"; } # <epoch seconds> <file>
  mkdir -p "$d/mainrun" && echo 'not ok 1 a case' > "$d/c7-7.test" && at "$((now - 100))" "$d/c7-7.test" || fail "the card's .test file"
  # The main run has printed no output yet: watch() starts its live record with last null and a test run's progress
  # set, so only its progress is newer than the .test file (a check that reads last alone calls it stuck since then).
  jq -cn --argjson t "$((now - 50))" '{step: "test", at: ($t - 30 | todate), last: null, progress: ($t | todate), turns: 0}' > "$d/mainrun/c7-7.live"
  stuckat() { CONVEYOR_NOW=$1 loop health | jq -c '.stuck | map([.card, .step, .since])'; } # <epoch seconds>
  [ "$(stuckat "$now")" = '[]' ] || fail "a card whose failed tests run again on main is stuck: $(stuckat "$now")"
  # No record changed for tunables.stuck: stuck, since the newest of them, the main run's live record.
  [ "$(stuckat "$((now + 1150))")" = "[[\"c7-7\",\"test\",\"$(jq -rn --argjson t "$((now - 50))" '$t | todate')\"]]" ] \
    || fail "a silent main run is not stuck since its last output: $(stuckat "$((now + 1150))")"
  # The .test file written later is the newest: the card is not stuck then, and is stuck since it later.
  at "$((now - 20))" "$d/c7-7.test" || fail "the .test file's time"
  [ "$(stuckat "$((now + 1150))")" = '[]' ] || fail "the card's .test file is not counted as its output: $(stuckat "$((now + 1150))")"
  [ "$(stuckat "$((now + 1180))")" = "[[\"c7-7\",\"test\",\"$(jq -rn --argjson t "$((now - 20))" '$t | todate')\"]]" ] \
    || fail "a card is not stuck since its .test file's last write: $(stuckat "$((now + 1180))")"
  # The main run prints a line: its live record's last, newer than its progress and the .test file, is the card's
  # last output (a check that reads progress alone calls it stuck since the .test file's write).
  jq -cn --argjson t "$((now - 10))" '{step: "test", at: ($t - 70 | todate), last: ($t | todate), progress: ($t - 40 | todate), turns: 0}' > "$d/mainrun/c7-7.live"
  [ "$(stuckat "$((now + 1195))")" = "[[\"c7-7\",\"test\",\"$(jq -rn --argjson t "$((now - 10))" '$t | todate')\"]]" ] \
    || fail "a card is not stuck since its main run's last line: $(stuckat "$((now + 1195))")"
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

# Bug (#497): the live record cut a command at 80 characters with the card's worktree path in it, so /units showed
# `cd worktree/...` with the end of the command lost. The path reads `worktree` before the cut. Card c7-7's session,
# watched as its build does it (c7watch), runs `cd '<its worktree>' && git add -A <its worktree>/<a 39-character
# folder>/x`. Bug (#507): a path in single quotes was kept whole, so the cut lost the end of the command.
t_livetree() {
  local c=c7-7 cmd; setup "[$(issue 7 2026-01-01)]"; c7at "$(date +%s)" picked worktree deps brief start:build
  cmd="cd '$T/$CASE/cards/$c' && git add -A $T/$CASE/cards/$c/a-folder-name-forty-characters-long-xyz/x"
  [ ${#cmd} -gt 80 ] || fail "the case's command is not over 80 characters: $cmd"
  jq -cn --arg c "$cmd" '{type: "assistant", message: {content: [{type: "tool_use", name: "Bash", input: {command: $c}}]}}' > "$STUB/event"
  printf '%s\n' 'cat "$STUB/event"; while [ -d "$STUB" ] && [ ! -e "$STUB/go" ]; do sleep 0.1; done' > "$STUB/session"
  c7watch build "$STUB/session"
  wait_until "jq -e '.action == \"Bash: cd '\''worktree'\'' && git add -A worktree/a-folder-name-forty-characters-long-xyz/x\"' '$T/$CASE/cards/$c.live'" "cat '$T/$CASE/cards/$c.live'" \
    || fail "the live action kept the worktree path, or lost the end of the command"
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

# Issue 1029: `serve` and every process under it were stopped by a stop signal (state T); health counted them as
# running, so the card read as stuck only after STUCK, with no cause, and nothing said a SIGCONT would resume it.
# Card c1-1 is in its build at <now>, its worktree line naming the process <pid>, as the loop writes it.
stoppedcard() { # <pid> <now>
  jq -cn --argjson p "$1" --arg s "$(p_started "$1")" --argjson t "$2" \
    '{card:"c1-1",issue:1,time:($t | todate),tokens:{claude:0,codex:0},result:"ok",sha:"",reason:""} as $l
     | ($l + {step:"picked",title:"t",created:"2026-01-01T00:00:00Z"}), ($l + {step:"worktree",pid:$p,started:$s}), ($l + {step:"start",of:"build"})' >> "$ST/cards.jsonl"
}
# A stand-in for `serve` (holding the loop's lock, its pid in loop.json) with the card's process under a wrapper under
# it, as the loop runs cardrun() and card() in shells of their own; the stand-in and the wrapper stopped: the card is
# stuck at once, named with the stopped engine's pid, and health names the engine itself, both since health first read
# it stopped (not the card's last output, <now>), and still so a minute on, with each stopped process of its tree (pids:
# issue 1039, the command resumed the engine alone and left the processes under it stopped); with the card's process
# stopped too, as when the whole tree is stopped, its entry also names that process (own), as resuming the engine
# leaves it stopped, and the engine's pids name it as well; once all are resumed, it is not stuck and no engine is
# stopped, as before.
t_stoppedengine() {
  local e w c now h s t2 u; setup '[]'; now=$(date +%s); s=$(jq -rn --argjson t $((now + 30)) '$t | todate')
  ( exec 9>>"$ST/cards.jsonl.run"; flock 9; ( sleep 600 & wait ) & wait ) & e=$! # sleep: the card's process under the stand-in, killed below
  # Poll: health reads the stopped pids from the real process tree (ps state T), so the test needs real processes under
  # the stand-in; its shells start their children by themselves, so wait for the card's process to be there.
  for _ in $(seq 50); do w=$(pgrep -P "$e") && c=$(pgrep -P "$w" sleep) && break; sleep 0.1; done
  [ -n "$c" ] || fail "the stand-in's card process did not start"
  jq -cn --argjson p "$e" --arg t "$(p_started "$e")" '{pid: $p, started: $t}' > "$ST/loop.json"
  stoppedcard "$c" "$now"; kill -STOP "$e" "$w"
  # late null (R135): stuck for the stop alone, so the Foreman's status drops it once the engine runs again.
  h=$(CONVEYOR_NOW=$((now + 30)) loop health >/dev/null; CONVEYOR_NOW=$((now + 90)) loop health | jq -c '[.loop, (.stuck | map([.issue, .step, .stopped, .late])), .engineStopped]')
  [ "$h" = "[true,[[1,\"build\",{\"pid\":$e,\"of\":\"engine\",\"since\":\"$s\"},null]],{\"pid\":$e,\"since\":\"$s\",\"pids\":[$e,$w]}]" ] \
    || { kill -CONT "$w" "$e"; kill "$c" "$e"; fail "a card under a stopped engine, or the engine with each stopped process under it, is not named so at once, since it was first read stopped: $h"; }
  kill -STOP "$c"; h=$(CONVEYOR_NOW=$((now + 150)) loop health | jq -c '[(.stuck | map(.stopped)), .engineStopped.pids]'); kill -CONT "$c" "$w" "$e"
  t2=$(jq -rn --argjson t $((now + 150)) '$t | todate'); u=$(printf '%s\n' "$w" "$c" | sort -n | paste -sd, -)
  [ "$h" = "[[{\"pid\":$e,\"of\":\"engine\",\"since\":\"$s\",\"own\":{\"pid\":$c,\"since\":\"$t2\",\"pids\":[$c]}}],[$e,$u]]" ] \
    || { kill "$c" "$e"; fail "a stopped card process under a stopped engine is not named, so resuming the engine leaves it stopped: $h"; }
  h=$(CONVEYOR_NOW=$((now + 150)) loop health | jq -c '[.loop, .stuck, .engineStopped]'); kill "$c" "$e"
  [ "$h" = '[true,[],null]' ] || fail "a card under a running engine is stuck, or the engine reads as stopped: $h"
}
# Issue 1106: an engine held by a stop signal was named by `foreman status` alone; the Board's Needs you said
# nothing, so the belt stood still for minutes until the owner looked. A stand-in for `serve` (holding the loop's
# lock, its pid in loop.json) and the process under it are stopped, and health first reads them so at <now>: 30 s on,
# the snapshot's Needs you names nothing yet; 90 s on (over a minute), it names the engine as stopped, with the
# kill -CONT command that resumes the stand-in and the process under it.
t_stoppedneeds() {
  local e w now early late; setup '[]'; now=$(date +%s)
  ( exec 9>>"$ST/cards.jsonl.run"; flock 9; sleep 600 & wait ) & e=$! # sleep: the process under the stand-in, killed below
  # Poll: health reads the stopped pids from the real process tree (ps state T), and the stand-in's shell starts its
  # child by itself, so wait for the child to be there.
  for _ in $(seq 50); do w=$(pgrep -P "$e" sleep) && break; sleep 0.1; done
  [ -n "$w" ] || { kill "$e"; fail "the stand-in's child process did not start"; }
  jq -cn --argjson p "$e" --arg t "$(p_started "$e")" '{pid: $p, started: $t}' > "$ST/loop.json"
  kill -STOP "$e" "$w"
  CONVEYOR_NOW=$now loop health > /dev/null
  early=$(CONVEYOR_NOW=$((now + 30)) loop snapshot --fresh | jq -c '.needsYou.stopped')
  late=$(CONVEYOR_NOW=$((now + 90)) loop snapshot --fresh | jq -c '.needsYou.stopped | [.title, .reason, .pid, .since]')
  kill -CONT "$e" "$w"; kill "$w" "$e" 2>/dev/null # the stand-in may end as its child does
  [ "$early" = null ] || fail "an engine stopped for 30 s is in Needs you already: $early"
  [ "$late" = "[\"The engine is stopped\",\"A stop signal holds the engine (state T), so it starts no card. Run kill -CONT $e $w to resume it and each stopped process under it.\",$e,\"$(jq -rn --argjson t "$now" '$t | todate')\"]" ] \
    || fail "an engine stopped for over a minute is not in Needs you with the command that resumes it: $late"
}
# The card's own process stopped with the process under it (a builder under its timeout wrapper, as card() runs it),
# no loop running: stuck at once, named with its pid and both pids (issue 1039: the command named the card's process
# alone and left the builder stopped); resumed, it is not stuck; ended (missing), it is stuck at once as gone, with no
# stopped process named.
t_stoppedcard() {
  local p b now h; setup '[]'; now=$(date +%s)
  ( sleep 600 & wait ) & p=$! # sleep: the builder under the card's process, stopped, resumed and then killed below
  # Poll: health reads the stopped pids from the real process tree (ps state T), so the test needs a real stopped child
  # under the card's process; a direct check cannot fake one, and the subshell starts it by itself, so wait for it.
  for _ in $(seq 50); do b=$(pgrep -P "$p" sleep) && break; sleep 0.1; done
  [ -n "$b" ] || fail "the card's builder did not start"
  stoppedcard "$p" "$now"; kill -STOP "$p" "$b"
  h=$(CONVEYOR_NOW=$((now + 30)) loop health | jq -c '[(.stuck | map([.issue, .stopped])), .engineStopped]'); kill -CONT "$b" "$p"
  [ "$h" = "[[[1,{\"pid\":$p,\"of\":\"card\",\"since\":\"$(jq -rn --argjson t $((now + 30)) '$t | todate')\",\"pids\":[$p,$b]}]],null]" ] \
    || { kill "$p" "$b"; fail "a stopped card process, with the stopped builder under it, is not named so at once, or no loop reads as a stopped engine: $h"; }
  h=$(CONVEYOR_NOW=$((now + 30)) loop health | jq -c .stuck); kill "$p" "$b"; wait "$p" 2>/dev/null
  [ "$h" = '[]' ] || fail "a card whose process runs is stuck: $h"
  [ "$(CONVEYOR_NOW=$((now + 30)) loop health | jq -c '.stuck | map([.issue, .stopped])')" = '[[1,null]]' ] \
    || fail "a card whose process is gone is not stuck at once, as before, or names a stopped process: $(CONVEYOR_NOW=$((now + 30)) loop health | jq -c .stuck)"
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

# Bug caught (#261): a card that landed with a lint command skipped for a missing tool landed unchecked, and Health
# did not count it. unchecked counts the landed cards whose last lint line skipped a command: not one whose last lint
# line ran every command (c0-2, skipped at its first gate only), nor one skipped that has not landed (c0-3).
t_healthunchecked() {
  local c
  setup '[]'
  for c in 'c0-1 skipped: missing shellcheck' 'c0-2 skipped: missing shellcheck' 'c0-2 pass' 'c0-3 skipped: missing shellcheck' 'c0-4 pass'; do
    jq -cn --arg c "${c%% *}" --arg r "${c#* }" '{card: $c, issue: ($c[3:] | tonumber), step: "lint", time: "2026-11-01T00:00:00Z", tokens: {claude: 0, codex: 0}, result: "pass", sha: "", reason: "",
      lint: {commands: [{n: 1, run: "x", result: $r, sec: 0, findings: 0}], asInstalled: false, gate: "land"}}'
  done >> "$ST/cards.jsonl"
  for c in c0-1 c0-2 c0-4; do
    jq -cn --arg c "$c" '{card: $c, issue: ($c[3:] | tonumber), step: "landed", time: "2026-11-01T00:01:00Z", tokens: {claude: 0, codex: 0}, result: "ok", sha: "abc", reason: "", product: false}'
  done >> "$ST/cards.jsonl"
  [ "$(loop health | jq -c .unchecked)" = 1 ] || fail "health does not count the one card that landed with a skipped lint command: $(loop health 2>&1 | jq -c .unchecked)"
}
