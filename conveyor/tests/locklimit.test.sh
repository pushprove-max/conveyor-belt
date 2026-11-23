#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the work done under the card records' lock is bounded: adopted() reads the landed issues from their
# running summary, a set-aside of a bad line, and a pick that holds the lock past its limit (lockedfor, lib/records.sh) is stopped.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bug it catches (#1427): with an issue pinned (`control order`), adopted() parsed the whole card records as one jq
# string (splits("\n")), which on a long history ran for minutes under the records' lock (each pick and snapshot
# called it there) and stopped the belt. Here 25,000 lines (6 MB): the old parse ran over 20 s on them, the summary's
# read under a second. The pinned #7 has landed and leaves order; #8, open and never landed, stays.
t_adoptedbig() {
  setup "[$(issue 7 2026-01-01),$(issue 8 2026-01-02)]"
  loop control order 7 8 > /dev/null || fail "the order 7 8 could not be set"
  awk 'BEGIN { pad = sprintf("%200s", ""); gsub(/ /, "x", pad)
    for (i = 1; i <= 25000; i++) printf "{\"card\":\"c%d-%d\",\"issue\":%d,\"step\":\"%s\",\"time\":\"2026-11-01T00:00:00Z\",\"tokens\":{\"claude\":0,\"codex\":0},\"result\":\"ok\",\"sha\":\"\",\"reason\":\"%s\"}\n",
      i, i % 900 + 10, i % 900 + 10, (i % 7 ? "picked" : "landed"), pad }' >> "$ST/cards.jsonl"
  landed 7 >> "$ST/cards.jsonl"
  local lim; lim=$(loadlimit 10)
  fx_in 'c=$(ctl) && s=${EPOCHREALTIME/[.,]/} && new=$(adopted "$c" "$(cat "$STUB/issues.json")") \
    && echo "$(( (${EPOCHREALTIME/[.,]/} - s) / 1000 )) $(jq -c .order <<<"$new")"'
  read -r ms order < "$T/$CASE/run.out"
  [ "$RC" = 0 ] && [ "$order" = '[8]' ] || fail "adopted() did not drop the landed #7 from order 7 8 (exit $RC): $(cat "$T/$CASE/run.out")"
  [ "$ms" -lt $((lim * 1000)) ] || fail "adopted() took $ms ms on 25,000 lines of card records (limit $lim s: 10 s times the load factor $CASE_LOAD)"
}

# Bug it catches (#1427): nothing bounded the work under the card records' lock, so a jq that did not end in a pick
# held every card's record writes, and the loop picked nothing, until it was stopped by hand. Here the pick's adopt
# runs a jq that never ends: the loop's pick turn (turnpick, lib/run.sh) must stop it at the limit (2 s here), say which
# step ran out of time, leave the lock free, and pick #7 at its next turn.
t_locklimit() {
  setup "[$(issue 7 2026-01-01)]"
  : > "$T/$CASE/slow"
  # turnpick's own variables, as run() sets them for a turn that asks with room below the cap; serve: a pick that
  # fails leaves the loop running. cardrun, the card's start, only notes the card. The jq runs at full CPU for far
  # longer than the limit; its own timeout (100 s) only keeps it from running on after the case when the stop fails.
  fx_in 'LOCKLIMIT=2; eval "$(declare -f adopt | sed "1s/^adopt /realadopt /")"
    adopt() { [ ! -e "$T/$CASE/slow" ] || timeout 100 jq -n "last(range(1e15))"; realadopt "$@"; }
    cardrun() { echo "$2" > "$T/$CASE/started"; }
    asking=1 urgent="" red="" building=0 cap=3 left=5 pct="" running=0 serve=1 pusher="" started=0 waits="" ctl=$(ctl) issues=$(cat "$STUB/issues.json")
    declare -A mine=()
    s=$SECONDS; turnpick; echo "first turn: $? picked=${picked:-none} after $((SECONDS - s)) s"
    flock -n "$STATE" true && echo "lock: free"
    rm "$T/$CASE/slow"; turnpick; echo "next turn: $?"; wait'
  local out; out=$(cat "$T/$CASE/run.out")
  grep -q '^first turn: 0 picked=none after \([0-9]\|1[0-9]\) s$' <<<"$out" \
    || fail "the pick whose jq never ends was not stopped at its limit, or its turn did not end as a failed pick: $out"
  grep -q "conveyor: pick ran out of time: it held the card records' lock for over 2 s" <<<"$out" || fail "the log does not say the pick ran out of time: $out"
  grep -q '^lock: free$' <<<"$out" || fail "the card records' lock was still held after the pick was stopped: $out"
  grep -q '^next turn: 1$' <<<"$out" && [ "$(cat "$T/$CASE/started" 2>&1)" = 7 ] || fail "the loop's next turn did not pick #7: $out"
}

# Bug it catches (#1491): check() set a bad line aside under the card records' lock with no time limit (`locked
# quarantine`), so a jq there that did not end held every card's record writes until it was stopped by hand. Here
# quarantine's jq never ends: check() must stop it at the limit (2 s here), say which step ran out of time, fail, and
# leave the lock free. READ is a copy of the records, as the snapshot's is (snapshot.sh): a limit that applied only
# when READ is STATE would let the snapshot's set-aside run on past it.
t_checklimit() {
  setup "[$(issue 7 2026-01-01)]"
  echo junk >> "$ST/cards.jsonl"
  # The jq runs at full CPU far longer than the limit; its own timeout (100 s) only keeps it from running on after the
  # case when the stop fails.
  fx_in 'LOCKLIMIT=2; eval "$(declare -f quarantine | sed "1s/^quarantine /realquarantine /")"
    quarantine() { timeout 100 jq -n "last(range(1e15))"; realquarantine; }
    READ=$STATE.copy; cp "$STATE" "$READ"; s=$SECONDS; check; echo "check: $? after $((SECONDS - s)) s"
    flock -n "$STATE" true && echo "lock: free"'
  local out; out=$(cat "$T/$CASE/run.out")
  grep -q '^check: 1 after \([0-9]\|1[0-9]\) s$' <<<"$out" || fail "check() was not stopped at the lock's limit, or did not fail: $out"
  grep -q "conveyor: the set-aside of a bad line ran out of time: it held the card records' lock for over 2 s" <<<"$out" || fail "the log does not say the set-aside ran out of time: $out"
  grep -q '^lock: free$' <<<"$out" || fail "the card records' lock was still held after the set-aside was stopped: $out"
}
