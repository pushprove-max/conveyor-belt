#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The Foreman's Conveyor watcher, watch-conveyor.sh, on a card that stays blocked (#877): polls (--once) of a snapshot
# given by CONVEYOR_FOREMAN_ASK, at times set by CONVEYOR_FOREMAN_NOW.
# Bug it catches: a blocked card woke the Foreman once; a Foreman turn that neither cleared the block nor asked the
# owner left it blocked with no later wake. Still blocked 30 minutes after it was first listed, with no open owner
# question naming its issue, it wakes again, then once an hour; an open question naming it, or a retry, stops that.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
B=$(mktemp -d) || exit 1
trap 'rm -rf "$B"' EXIT
unset CONVEYOR_FOREMAN CONVEYOR_FOREMAN_DIR CONVEYOR_FOREMAN_ASK CONVEYOR_FOREMAN_SESSION_PID CLAUDE_PROJECT_DIR CONVEYOR_MACHINE_ID
fail() { echo "FAIL [watch-blocked-$CASE]: $*" >&2; exit 1; }
T0=$(date -u -d 2026-11-19T10:00:00Z +%s 2>/dev/null || date -ju -f %Y-%m-%dT%H:%M:%SZ 2026-11-19T10:00:00Z +%s)
REASON='the changed tests failed again after their one fix round (exit 1); nothing landed.'
# fixture <case>: alpha's record; the ask seam gives the snapshot $T/snap, made by block (it times out, exit 124, while
# $T/slow is there), and health, the snapshot's.
fixture() {
  CASE=$1 T=$B/$1
  export HOME=$T/home XDG_CONFIG_HOME=$T/config XDG_DATA_HOME=$T/data XDG_STATE_HOME=$T/xstate
  M=$T/alpha FD=$T/foreman
  mkdir -p "$HOME" "$XDG_CONFIG_HOME/conveyor" "$M/.claude/metrics" && git init -q "$M" && mkdir -p "$M/.conveyor" \
    && jq '.plugin = {follow: "main"}' "$SRC/../lib/test-pack.json" > "$M/.conveyor/project.json" \
    && jq -n --arg m "$M" '{records: [{repo: "alpha", main: $m}]}' > "$XDG_CONFIG_HOME/conveyor/host.json" \
    || fail "the fixture was not made"
  export CONVEYOR_FOREMAN_ASK="case \$CONVEYOR_CMD in snapshot) [ ! -e $T/slow ] || exit 124; cat $T/snap ;; health) jq -c .health $T/snap ;; *) exit 3 ;; esac"
}
# block <since or ""> [<issue>]: the snapshot, with card c<issue> of issue <issue> (default 7) blocked since <since>,
# or with no card blocked.
block() {
  jq -cn --arg s "$1" --argjson i "${2:-7}" --arg r "$REASON" '{belt: [{card: "c9", issue: 9, step: "build"}], queue: {next: []},
    health: {time: "2026-11-19T10:00:00Z", loop: true, gh: true, ghReached: true, state: "running", reason: null, stuck: [], waiting: [],
      blocked: (if $s == "" then [] else [{card: "c\($i)", issue: $i, since: $s, reason: $r}] end), pushError: null, pushFailingSince: null}}' > "$T/snap"
}
# poll <minutes after T0>: one poll; 0 with a wake put, which $wake holds.
poll() {
  rm -f "$FD"/pending/*.wake; wake=''
  CONVEYOR_FOREMAN_DIR=$FD CONVEYOR_MAIN=$M CONVEYOR_FOREMAN_NOW=$((T0 + $1 * 60)) bash "$SRC/watch-conveyor.sh" --once 2>> "$T/err" || return
  wake=$(cat "$FD"/pending/*.wake)
}

# No question: the block's wake, none before 30 minutes, one naming #7 at 30, none again in that hour, one more an
# hour later.
t_remind() {
  fixture remind; block 2026-11-19T09:58:00Z
  poll 0 || fail "no wake for the block: $(cat "$T/err")"
  ! poll 29 || fail "a wake 29 minutes after the block's report: $wake"
  poll 30 || fail "no second wake for #7 still blocked 30 minutes after its report: $(cat "$T/err")"
  grep -qF "alpha: #7 has been blocked for 32m: $REASON" <<<"$wake" || fail "the second wake does not name #7, its time and reason: $wake"
  grep -qF 'still blocked: #7' <<<"$wake" || fail "the wake's first line does not name #7 as still blocked: $wake"
  ! poll 31 || fail "a third wake one minute after the second: $wake"
  ! poll 89 || fail "a third wake within the hour: $wake"
  poll 90 || fail "no wake an hour after the second: $(cat "$T/err")"
  grep -qF "alpha: #7 has been blocked for 1h32m: $REASON" <<<"$wake" || fail "the hourly wake does not name #7: $wake"
}
# An open question in alpha's decision ledger names #7: no second wake while it is open; one that names #70 does not count.
t_question() {
  fixture question; block 2026-11-19T09:58:00Z
  printf '%s\n' '{"id":"q1","question":"#7 is blocked by its tests; file a fix or close it?","answeredAt":null}' \
    '{"id":"q2","question":"Ship #70?","answeredAt":null}' > "$M/.claude/metrics/decisions.jsonl"
  poll 0 || fail "no wake for the block: $(cat "$T/err")"
  ! poll 30 || fail "a second wake for #7 while an open question names it: $wake"
  # Bug it also catches: a question once answered still held the reminder back.
  printf '%s\n' '{"id":"q1","question":"#7 is blocked by its tests; file a fix or close it?","answeredAt":"2026-11-19T10:40:00Z"}' >> "$M/.claude/metrics/decisions.jsonl"
  ! poll 45 || fail "a wake in the same hour as the one held back by the question: $wake"
  poll 90 || fail "no wake for #7 an hour on, with its question answered: $(cat "$T/err")"
  grep -qF "alpha: #7 has been blocked for" <<<"$wake" || fail "the wake does not name #7: $wake"
}
# #7 retried before 30 minutes, then blocked again: the new block wakes as a block, and its 30 minutes count from then.
t_retried() {
  fixture retried; block 2026-11-19T09:58:00Z
  poll 0 || fail "no wake for the block: $(cat "$T/err")"
  block ''; ! poll 20 || fail "a wake when #7 was retried: $wake"
  block 2026-11-19T10:24:00Z
  poll 25 || fail "no wake for the new block: $(cat "$T/err")"
  grep -qF 'alpha: #7 is blocked since 2026-11-19T10:24:00Z' <<<"$wake" || fail "the wake is not the new block's: $wake"
  ! poll 31 || fail "a second wake for #7 30 minutes after its first report, though it was retried: $wake"
  ! poll 54 || fail "a second wake for #7 before 30 minutes of its new block: $wake"
}

# The snapshot times out at each poll and health lists #948 blocked: the block's wake at minute 0, and a still-blocked
# wake at minute 30. Bug it catches: reminders ran only on a poll whose snapshot read, so a block health alone listed
# was never reminded of.
t_health() {
  fixture health; block 2026-11-19T09:58:00Z 948; touch "$T/slow"
  poll 0 || fail "no wake for the block health lists: $(cat "$T/err")"
  poll 30 || fail "no second wake for #948 still blocked 30 minutes after its report, the snapshot timing out: $(cat "$T/err")"
  grep -qF 'still blocked: #948' <<<"$wake" && grep -qF "alpha: #948 has been blocked for 32m: $REASON" <<<"$wake" \
    || fail "the wake does not name #948 as still blocked, with its time and reason: $wake"
}

cases=(remind question retried health)
# The cases CONVEYOR_SHELL_TEST_CASE names (comma-separated), as the runner selects them; all of them with none set.
SEL=${CONVEYOR_SHELL_TEST_CASE:-${cases[*]}}; SEL=${SEL//,/ }
for c in $SEL; do case " ${cases[*]} " in *" $c "*) ;; *) echo "unknown case $c" >&2; exit 2 ;; esac; done
read -ra cases <<<"$SEL"
for c in "${cases[@]}"; do (t_"$c" && : > "$B/$c.passed") > "$B/$c.out" 2>&1 & done
wait
bad=0
for c in "${cases[@]}"; do cat "$B/$c.out" >&2; [ -e "$B/$c.passed" ] || bad=1; done
[ "$bad" = 0 ] || exit 1
echo "ok [watch-blocked]"
