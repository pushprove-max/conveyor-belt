#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the stream.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Each case below watches streams of its own on a main of its own (watchstart): one after another, its four streams
# made one case of 12 s. A main with #7 open, card c1 picked and in its build, and the stream's helpers.
watchstart() {
  export TZ=UTC; setup "[$(issue 7 2026-01-01 P1)]"; S=$ST; CD=$T/$CASE/cards; mkdir -p "$S" "$CD"
  seatset model claude-sonnet-5-5
  rec() { jq -cn --arg c "$1" --argjson i "$2" --arg s "$3" --arg t "$(date -u +%FT%TZ)" --argjson x "${4:-{\}}" \
    '{card:$c,issue:$i,step:$s,time:$t,tokens:{claude:0,codex:0},result:"ok",sha:"",reason:""} * $x' >> "$S/cards.jsonl"; }
  rec c1 1 picked '{"title":"T1"}'; rec c1 1 worktree; rec c1 1 start '{"of":"build"}'
  # Every gh call says so ($STUB/slowed) and waits for as long as $STUB/slow is there: GitHub that does not answer.
  mkdir -p "$STUB/slowbin"; printf '#!/usr/bin/env bash\n[ ! -e "%s/slow" ] || { : > "%s/slowed"; while [ -e "%s/slow" ]; do sleep 0.1; done; }\nexec "%s/gh" "$@"\n' \
    "$STUB" "$STUB" "$STUB" "$STUB" > "$STUB/slowbin/gh"; chmod +x "$STUB/slowbin/gh"
  # No wait here is a number of seconds (a bug: on a busy machine a line that was on its way missed a 4 s window, and
  # a record written 0.5 s after the stream's launch was there before the stream first looked, so it was no change).
  # A line is waited for until it comes or the stream ends, and a stream ends at its own time limit.
  stream() { # <seconds> <output file> [<NAME=value>...]: the stream into the file, until that time or `kill $pid`; then the case's end marker is its last line
    local s=$1; W=$2; shift 2
    ( trap 'kill $w 2>/dev/null' TERM
      env "$@" CONVEYOR_WATCH_BEAT=1 CONVEYOR_MAIN="$R" CONVEYOR_CARDS="$CD" timeout "$s" bash "$SRC/conveyor.sh" watch > "$W" 2> "$W.err" & w=$!
      wait; wait; echo '{"type":"end"}' >> "$W" ) & pid=$!
  }
  ev() { jq -c "select($1)" "$W" 2>/dev/null | tail -n 1; }
  till() { # <what> <command...>: until the command is true; the end marker there before it is, the case fails
    local what=$1 e; shift
    while :; do
      e=$(ev '.type == "end"'); "$@" && return
      [ -z "$e" ] || fail "$what did not come before the stream ended: $(tail -c 600 "$W") $(cat "$W.err")"; sleep 0.05
    done; }
  line() { [ -n "$(ev "$1")" ]; }
  last() { [ "$(jq -c "$1" "$W" 2>/dev/null | tail -n 1)" = "$2" ]; } # <jq filter> <its last output>
  come() { till "$2" line "$1"; } # <jq test> <what>: a line of the stream
}

# Bugs: the stream (`conveyor.sh watch`, conveyor/watch.py) gives no snapshot to begin with; a record appended on the host, or a
# control change, does not reach its reader in seconds; a slow GitHub read holds a card's line up; a running step's
# live record (its action, turns, tokens and dollars so far) is not streamed; a quiet stream sends nothing to tell it
# from a dead one.
t_watch() {
  watchstart
  stream 90 "$T/$CASE/watch.out" "PATH=$STUB/slowbin:$PATH" CONVEYOR_WATCH_GITHUB=1
  trap 'kill $pid 2>/dev/null' EXIT
  come '.type == "snapshot" and .why == "start"' "the first snapshot"
  [ "$(ev '.why == "start"' | jq -c '[(.snap.belt | map(.card)), (.snap.queue.order | map(.issue)), .snap.health.gh, has("cpuCap"), .repoUrl]')" = '[["c1"],[7],true,false,null]' ] \
    || fail "the first snapshot: $(ev '.why == "start"' | jq -c '[.snap.belt, .snap.queue, .cpuCap, .repoUrl]')"
  # GitHub goes slow, and a read of it is under way (one is asked every second).
  : > "$STUB/slow"; till "a read of GitHub, once it was slow," test -e "$STUB/slowed"
  rec c2 7 picked '{"title":"title 7"}'
  come '.type == "snapshot" and .why == "record" and (.snap.belt | any(.card == "c2"))' "a record appended on the host, while GitHub was slow,"
  [ "$(ev '.why == "record"' | jq -c '.snap.queue.order | map(.issue)')" = '[]' ] || fail "the snapshot after the record did not read GitHub's last answer: $(ev '.why == "record"' | jq -c .snap.queue)"
  loop control pause >/dev/null
  come '.type == "snapshot" and .why == "control" and .snap.control.mode == "pause"' "a control change"
  kill $pid; wait $pid 2>/dev/null; :
}
# The live record of a running step, in a stream that began with the loop paused (as the case above leaves it).
t_watchlive() {
  watchstart; loop control pause >/dev/null
  stream 90 "$T/$CASE/watch.out" CONVEYOR_WATCH_GITHUB=1
  trap 'kill $pid 2>/dev/null' EXIT
  come '.type == "snapshot" and .why == "start" and .snap.control.mode == "pause"' "the first snapshot"
  # A running step's live record: the step's tokens so far are laid over the finished ones and priced.
  jq -cn --arg t "$(date -u +%FT%TZ)" '{step: "build", at: $t, last: $t, turns: 3, model: "claude-sonnet-5-5",
    usage: {input: 1000000, write: 0, write1h: 0, read: 0, output: 0}, action: "Bash: npm test"}' > "$CD/c1.live.tmp" && mv "$CD/c1.live.tmp" "$CD/c1.live"
  come '.type == "live" and .cards.c1.live.action == "Bash: npm test"' "the live record of a running step"
  [ "$(ev '.type == "live"' | jq -c '.cards | [keys, (.c1 | [.live.turns, .tokens.claude, .usd == 2, .reading])]')" = '[["c1"],[3,1000000,true,true]]' ] \
    || fail "the live line: $(ev '.type == "live"')"
  # A snapshot clears its reader's live fields: the live fields as they are now come right after it, with no new
  # output from the session (a live line sent while a snapshot was built came before that snapshot).
  loop control resume >/dev/null
  come '.type == "snapshot" and .why == "control" and .snap.control.mode == "run"' "the control change"
  till "the live fields after the snapshot" last 'select(.type != "beat") | .type' '"live"'
  [ "$(jq -c 'select(.type != "beat") | [.type, .why, .cards.c1.live.action]' "$W" | tail -n 2 | tr -d '\n')" = '["snapshot","control",null]["live",null,"Bash: npm test"]' ] \
    || fail "the live fields did not follow the snapshot: $(jq -c 'select(.type != "beat") | [.type, .why]' "$W" | tail -n 3)"
  # The step ends: its live record goes, and the last live line says no card has one (an earlier one, after a snapshot, said so too).
  rm "$CD/c1.live"
  till "the end of a running step" last 'select(.type == "live") | .cards' '{}'
  come '.type == "beat"' "a beat line in a quiet stream"
  [ "$(jq -r .type "$W" | sort -u | tr '\n' ' ')" = "beat live snapshot " ] || fail "a line of another kind: $(jq -r .type "$W" | sort -u)"
  kill $pid; wait $pid 2>/dev/null; :
}

# A stream that connects (or reconnects) while GitHub is slow: a record appended at once is not held up by the
# wait for GitHub's first answer. That wait is longer than the stream lasts, so a record held up by it never comes;
# and the record is written at the stream's first beat, which says the stream is looking for changes.
t_watchslow() {
  watchstart; : > "$STUB/slow"
  stream 60 "$T/$CASE/watch2.out" "PATH=$STUB/slowbin:$PATH" CONVEYOR_WATCH_GITHUB=1 CONVEYOR_WATCH_GITHUB_FIRST=600
  trap 'kill $pid 2>/dev/null' EXIT
  come '.type == "beat"' "the first beat of a stream that connected while GitHub was slow"
  [ -z "$(ev '.type != "beat"')" ] || fail "a stream waiting for GitHub's first answer, with no change, sent more than beats: $(ev '.type != "beat"' | head -c 300)"
  rec c3 8 picked '{"title":"title 8"}'
  come '.type == "snapshot" and (.snap.belt | any(.card == "c3"))' "a record appended as the stream connected, while GitHub was slow,"
  kill $pid; wait $pid 2>/dev/null; :
}

# So is a running step's live record written as it connects (it waited out the wait for GitHub).
t_watchslowlive() {
  watchstart; : > "$STUB/slow"
  stream 60 "$T/$CASE/watch3.out" "PATH=$STUB/slowbin:$PATH" CONVEYOR_WATCH_GITHUB=1 CONVEYOR_WATCH_GITHUB_FIRST=600
  trap 'kill $pid 2>/dev/null' EXIT
  come '.type == "beat"' "the first beat of a second stream that connected while GitHub was slow"
  jq -cn --arg t "$(date -u +%FT%TZ)" '{step: "build", at: $t, last: $t, turns: 4, action: "Read: a.ts"}' > "$CD/c1.live.tmp" && mv "$CD/c1.live.tmp" "$CD/c1.live"
  come '.type == "live" and .cards.c1.live.action == "Read: a.ts"' "a live record written as the stream connected, while GitHub was slow,"
  kill $pid; wait $pid 2>/dev/null; :
}

# The loop's process ends with no record line, control change or GitHub answer: a snapshot says so at once; and a
# quiet stream still gets a snapshot every REFRESH seconds, so what counts on the clock moves on (a bug:
# killing the loop left Health showing it running, and stuck cards and today's totals stood still).
# The loop is the process loop.json names by pid and start time, here one holding the run lock.
t_watchloop() {
  watchstart
  ( exec 8>>"$S/cards.jsonl.run"; flock 8; exec sleep 60 ) & hpid=$! # sleep: a stand-in that holds the run lock until it is killed
  while kill -0 $hpid 2>/dev/null && flock -n "$S/cards.jsonl.run" true; do sleep 0.05; done # until it holds the lock
  ( . "$SRC/lib/portable.sh"; jq -cn --argjson p "$hpid" --arg t "$(p_started "$hpid")" '{pid: $p, started: $t, state: "running", reason: null}' ) > "$S/loop.json"
  stream 60 "$T/$CASE/watch4.out" CONVEYOR_WATCH_GITHUB=60 CONVEYOR_WATCH_REFRESH=3
  trap 'kill $pid $hpid 2>/dev/null' EXIT
  come '.type == "snapshot" and .why == "start"' "the first snapshot, with the loop running,"
  [ "$(ev '.why == "start"' | jq -c .snap.health.loop)" = true ] || fail "the loop's run lock was not seen: $(ev '.why == "start"' | jq -c .snap.health)"
  kill $hpid; wait $hpid 2>/dev/null
  come '.type == "snapshot" and .why == "loop" and .snap.health.loop == false' "the end of the loop's process"
  come '.type == "snapshot" and .why == "refresh"' "a snapshot in a quiet stream"
  kill $pid; wait $pid 2>/dev/null; :
}
