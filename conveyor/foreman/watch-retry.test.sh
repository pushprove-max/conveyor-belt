#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The Foreman's Conveyor watcher, watch-conveyor.sh, on a card blocked by its review (the fix for a finding did not hold)
# while the standing kind review-retry is on (#715): one poll (--once) of a snapshot given by CONVEYOR_FOREMAN_ASK.
# Bug it catches: each such block woke the Foreman, and a whole Foreman turn only ran `conveyor.sh retry <issue>` by
# the owner's standing rule. With the kind on, the watcher runs the retry on the record's host and logs it in the
# ruling log, with no wake; with it off, or for another block, the block wakes as before; a retry that fails wakes, with
# why.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
B=$(mktemp -d) || exit 1
trap 'rm -rf "$B"' EXIT
unset CONVEYOR_FOREMAN CONVEYOR_FOREMAN_DIR CONVEYOR_FOREMAN_ASK CONVEYOR_FOREMAN_SESSION_PID CLAUDE_PROJECT_DIR CONVEYOR_MACHINE_ID
export ENG=$SRC/../conveyor.sh
REVIEW='the fix for [P1] conveyor/lib/x.sh:3 The guard can be skipped. Proof: a quoted name passes did not hold after 2 rounds'
fail() { echo "FAIL [watch-retry-$CASE]: $*" >&2; exit 1; }
# fixture <case> <kinds> <block reason> <what the retry does>: alpha's record, its pack's auto.standing <kinds> (a json
# list), its snapshot with card c7 of issue 7 blocked for <block reason>. The ask seam (lib.sh ask): the snapshot is
# $T/snap; `retry <n>` is listed in $T/retries, then does <what the retry does>; `auto act review-retry <what>` runs the
# engine on alpha's main, as on its host, into the ruling log $T/rulings.jsonl; any other ask fails.
fixture() {
  CASE=$1 T=$B/$1
  export HOME=$T/home XDG_CONFIG_HOME=$T/config XDG_DATA_HOME=$T/data XDG_STATE_HOME=$T/xstate CONVEYOR_RULING_LOG=$T/rulings.jsonl
  M=$T/alpha FD=$T/foreman
  mkdir -p "$HOME" "$XDG_CONFIG_HOME/conveyor" && git init -q "$M" && mkdir -p "$M/.conveyor" \
    && jq --argjson k "$2" '.plugin = {follow: "main"} | .auto.standing = $k' "$SRC/../lib/test-pack.json" > "$M/.conveyor/project.json" \
    && jq -n --arg m "$M" '{records: [{repo: "alpha", main: $m}]}' > "$XDG_CONFIG_HOME/conveyor/host.json" \
    && jq -cn --argjson k "$2" --arg r "$3" '{belt: [{card: "c9", issue: 9, step: "build"}], queue: {next: []}, standing: $k,
      health: {time: "2026-11-19T10:00:00Z", loop: true, gh: true, ghReached: true, state: "running", reason: null, stuck: [], waiting: [],
        blocked: [{card: "c7", issue: 7, since: "2026-11-19T09:58:00Z", reason: $r}], pushError: null, pushFailingSince: null}}' > "$T/snap" \
    || fail "the fixture was not made"
  export CONVEYOR_FOREMAN_ASK="case \$CONVEYOR_CMD in snapshot) cat $T/snap ;; 'retry '*) echo \"\$CONVEYOR_CMD\" >> $T/retries; $4 ;;
    'auto act review-retry '*) cd \"\$CONVEYOR_MAIN\" && bash \"\$ENG\" auto act review-retry \"\${CONVEYOR_CMD#auto act review-retry }\" ;; *) exit 3 ;; esac"
}
# One poll; 0 with a wake put, which $wake holds.
poll() {
  rm -f "$FD"/pending/*.wake; wake=''
  CONVEYOR_FOREMAN_DIR=$FD CONVEYOR_MAIN=$M bash "$SRC/watch-conveyor.sh" --once 2>> "$T/err" || return
  wake=$(cat "$FD"/pending/*.wake)
}
BLOCKED='alpha: #7 is blocked since 2026-11-19T09:58:00Z: '

# The kind on: the retry of #7, one row of kind review-retry, no wake; a second poll of the same snapshot (the card's
# blocked line not gone yet) retries nothing again. The reason carries the note block() adds when the findings could
# not be posted (lib/push.sh); bug it catches: such a review block was not taken for one, and woke.
t_on() {
  fixture on '["review-retry"]' "$REVIEW [the review's findings could not be posted on the issue]" 'echo "conveyor: issue #7 is queued again"'
  poll && fail "the review block woke the Foreman: $wake"
  [ "$(cat "$T/retries" 2>/dev/null)" = 'retry 7' ] || fail "#7 was not retried: $(cat "$T/retries" "$T/err" 2>/dev/null)"
  jq -se 'length == 1 and .[0].source == "standing" and .[0].kind == "review-retry" and (.[0].answer | contains("#7"))' "$CONVEYOR_RULING_LOG" >/dev/null \
    || fail "the act is not one ruling-log row of kind review-retry: $(cat "$CONVEYOR_RULING_LOG" "$T/err" 2>/dev/null)"
  poll && fail "the review block woke on the next poll: $wake"
  [ "$(wc -l < "$T/retries")" = 1 ] || fail "#7 was retried again while the snapshot still listed it: $(cat "$T/retries")"
}
# The kind off: the blocked wake, and no retry.
t_off() {
  fixture off '[]' "$REVIEW" 'exit 0'
  poll || fail "no wake for the review block with the kind off: $(cat "$T/err")"
  grep -qF "$BLOCKED$REVIEW" <<<"$wake" || fail "the wake does not name the block: $wake"
  [ ! -e "$T/retries" ] || fail "the watcher retried with the kind off: $(cat "$T/retries")"
}
# The retry fails: the blocked wake, with the retry's reason; nothing logged.
t_fails() {
  fixture fails '["review-retry"]' "$REVIEW" 'echo "conveyor: issue #7 has a card on the belt; nothing to retry" >&2; exit 1'
  poll || fail "no wake when the retry failed: $(cat "$T/err")"
  grep -qF "${BLOCKED}the fix for [P1]" <<<"$wake" && grep -qF '; the review-retry of #7 failed: conveyor: issue #7 has a card on the belt; nothing to retry' <<<"$wake" \
    || fail "the wake does not give the block with the retry's reason: $wake"
  [ ! -s "$CONVEYOR_RULING_LOG" ] || fail "a failed retry was logged as done: $(cat "$CONVEYOR_RULING_LOG")"
}
# A block that is not a review block, with the kind on: the blocked wake, and no retry.
t_other() {
  fixture other '["review-retry"]' 'the changed tests failed again after their one fix round (exit 1); nothing landed.' 'exit 0'
  poll || fail "no wake for a test block: $(cat "$T/err")"
  grep -qF "${BLOCKED}the changed tests failed again" <<<"$wake" || fail "the wake does not name the block: $wake"
  [ ! -e "$T/retries" ] || fail "the watcher retried a block that is not a review block: $(cat "$T/retries")"
}

cases=(on off fails other)
# The cases CONVEYOR_SHELL_TEST_CASE names (comma-separated), as the runner selects them; all of them with none set.
SEL=${CONVEYOR_SHELL_TEST_CASE:-${cases[*]}}; SEL=${SEL//,/ }
for c in $SEL; do case " ${cases[*]} " in *" $c "*) ;; *) echo "unknown case $c" >&2; exit 2 ;; esac; done
read -ra cases <<<"$SEL"
for c in "${cases[@]}"; do (t_"$c" && : > "$B/$c.passed") > "$B/$c.out" 2>&1 & done
wait
bad=0
for c in "${cases[@]}"; do cat "$B/$c.out" >&2; [ -e "$B/$c.passed" ] || bad=1; done
[ "$bad" = 0 ] || exit 1
echo "ok [watch-retry]"
