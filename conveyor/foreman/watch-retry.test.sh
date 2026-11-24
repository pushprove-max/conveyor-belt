#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The Foreman's Conveyor watcher, watch-conveyor.sh, on a card blocked by its review (the fix for a finding did not hold)
# while the standing kind review-retry is on (#715): one poll (--once) of a snapshot given by CONVEYOR_FOREMAN_ASK.
# Bug it catches: each such block woke the Foreman, and a whole Foreman turn only ran `conveyor.sh retry <issue>` by
# the owner's standing rule. With the kind on, the watcher runs the retry on the record's host and logs it in the
# ruling log, with no wake; with it off, or for another block, the block wakes as before; a retry that fails wakes, with
# why. The kind is read from the pack as it is now, not from the snapshot.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
B=$(mktemp -d) || exit 1
trap 'rm -rf "$B"' EXIT
unset CONVEYOR_FOREMAN CONVEYOR_FOREMAN_DIR CONVEYOR_FOREMAN_ASK CONVEYOR_FOREMAN_SESSION_PID CLAUDE_PROJECT_DIR CONVEYOR_MACHINE_ID
export ENG=$SRC/../conveyor.sh
REVIEW='the fix for [P1] conveyor/lib/x.sh:3 The guard can be skipped. Proof: a quoted name passes did not hold after 2 rounds'
fail() { echo "FAIL [watch-retry-$CASE]: $*" >&2; exit 1; }
# fixture <case> <kinds> <block reason> <what the retry does> [<snapshot kinds>]: alpha's record, its pack's
# auto.standing <kinds> (a json list), its snapshot with card c7 of issue 7 blocked for <block reason> and the standing
# <snapshot kinds> (default <kinds>: a kept snapshot can list kinds from before the pack changed). The ask seam (lib.sh
# ask): the snapshot is $T/snap, or times out (exit 124) while $T/slow is there; health is the snapshot's; `retry <n>`
# is listed in $T/retries, with the CONVEYOR_REVIEWRETRY it was run with in $T/marks, then does <what the retry does>; `auto standing`, `auto reserved` and `auto act review-retry <what>` run the
# engine on alpha's main, as on its host, the act into the ruling log $T/rulings.jsonl; any other ask fails.
fixture() {
  CASE=$1 T=$B/$1
  export HOME=$T/home XDG_CONFIG_HOME=$T/config XDG_DATA_HOME=$T/data XDG_STATE_HOME=$T/xstate CONVEYOR_RULING_LOG=$T/rulings.jsonl
  M=$T/alpha FD=$T/foreman
  mkdir -p "$HOME" "$XDG_CONFIG_HOME/conveyor" && git init -q "$M" && mkdir -p "$M/.conveyor" \
    && jq --argjson k "$2" '.plugin = {follow: "main"} | .auto.standing = $k' "$SRC/../lib/test-pack.json" > "$M/.conveyor/project.json" \
    && jq -n --arg m "$M" '{records: [{repo: "alpha", main: $m}]}' > "$XDG_CONFIG_HOME/conveyor/host.json" \
    && jq -cn --argjson k "${5:-$2}" --arg r "$3" '{belt: [{card: "c9", issue: 9, step: "build"}], queue: {next: []}, standing: $k,
      health: {time: "2026-11-19T10:00:00Z", loop: true, gh: true, ghReached: true, state: "running", reason: null, stuck: [], waiting: [],
        blocked: [{card: "c7", issue: 7, since: "2026-11-19T09:58:00Z", reason: $r}], pushError: null, pushFailingSince: null}}' > "$T/snap" \
    || fail "the fixture was not made"
  export CONVEYOR_FOREMAN_ASK="case \$CONVEYOR_CMD in snapshot) [ ! -e $T/slow ] || exit 124; cat $T/snap ;; health) jq -c .health $T/snap ;;
    'retry '*) echo \"\$CONVEYOR_CMD\" >> $T/retries; echo \"\${CONVEYOR_REVIEWRETRY:-}\" >> $T/marks; $4 ;; 'auto standing'|'auto reserved') cd \"\$CONVEYOR_MAIN\" && bash \"\$ENG\" auto \"\${CONVEYOR_CMD#auto }\" ;;
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
# The retry takes longer than the ask's first wait (45 s) and ends well within the longer one: here the ask exits 124
# when its wait is 45 s or less. Bug it catches (#1586): the retry ran on the host, but the 45 s wait ended it as a
# failure, so the Foreman was woken with "the review-retry of #7 failed: exit 124" and the act was never logged.
t_slow() {
  fixture slow '["review-retry"]' "$REVIEW" '[ "${ASK_LIMIT:-45}" -gt 45 ] || exit 124; echo "conveyor: issue #7 is queued again"'
  poll && fail "a retry slower than the first ask wait woke the Foreman: $wake"
  jq -se 'length == 1 and .[0].kind == "review-retry" and (.[0].answer | contains("#7"))' "$CONVEYOR_RULING_LOG" >/dev/null \
    || fail "a retry slower than the first ask wait was not logged as a retry: $(cat "$CONVEYOR_RULING_LOG" 2>&1) $(cat "$T/err")"
}
# A block that is not a review block, with the kind on: the blocked wake, and no retry.
t_other() {
  fixture other '["review-retry"]' 'the changed tests failed again after their one fix round (exit 1); nothing landed.' 'exit 0'
  poll || fail "no wake for a test block: $(cat "$T/err")"
  grep -qF "${BLOCKED}the changed tests failed again" <<<"$wake" || fail "the wake does not name the block: $wake"
  [ ! -e "$T/retries" ] || fail "the watcher retried a block that is not a review block: $(cat "$T/retries")"
}

# A kept snapshot lists the kind on, and the owner has turned it off in the pack since: the blocked wake, and no retry.
# Bug it catches: the watcher read the kind from the snapshot, so it retried a card the owner meant to see.
t_stale() {
  fixture stale '[]' "$REVIEW" 'exit 0' '["review-retry"]'
  poll || fail "no wake for the review block with the kind turned off since the snapshot: $(cat "$T/err")"
  grep -qF "$BLOCKED$REVIEW" <<<"$wake" || fail "the wake does not name the block: $wake"
  [ ! -e "$T/retries" ] || fail "the watcher retried after the kind was turned off: $(cat "$T/retries")"
}
# The snapshot times out and health lists the review block, with the kind on: no wake and no retry at that poll; the
# next poll whose snapshot reads retries #7. Bug it catches: health's block woke the Foreman and was marked reported,
# so no later poll retried it.
t_health() {
  fixture health '["review-retry"]' "$REVIEW" 'echo "conveyor: issue #7 is queued again"'
  touch "$T/slow"
  poll && fail "the review block health lists woke the Foreman: $wake"
  [ ! -e "$T/retries" ] || fail "#7 was retried on a poll whose snapshot did not read: $(cat "$T/retries")"
  rm -f "$T/slow"
  poll && fail "the review block woke on the poll whose snapshot read: $wake"
  [ "$(cat "$T/retries" 2>/dev/null)" = 'retry 7' ] || fail "#7 was not retried when the snapshot read again: $(cat "$T/retries" "$T/err" 2>/dev/null)"
}

# The kind on, and the reason holds a word of auto.reserved (a finding tagged [Security]; the pack's default list holds "security"),
# in another case: the block wakes, and no retry. Bug it catches: the watcher retried every review block,
# so a card blocked on a finding the owner reserves was queued again with no one asking, as needsretry() does not.
t_reserved() {
  fixture reserved '["review-retry"]' 'the fix for [P1][Security] conveyor/lib/x.sh:3 The guard can be skipped. Proof: a quoted name passes did not hold after 2 rounds' 'exit 0'
  poll || fail "no wake for a review block that holds a reserved word: $(cat "$T/err")"
  grep -qF "${BLOCKED}the fix for [P1][Security]" <<<"$wake" || fail "the wake does not name the block: $wake"
  [ ! -e "$T/retries" ] || fail "the watcher retried a block whose reason holds a reserved word: $(cat "$T/retries")"
}

# The pack's own auto.reserved list decides, not a fixed word: the pack holds "gizmo" in place of the default words, and the
# reason holds "Gizmo" and no default word. Bug it catches: the watcher matched only "security", so a word the owner
# reserves in the pack did not hold a retry back.
t_reservedpack() {
  fixture reservedpack '["review-retry"]' 'the fix for [P1] conveyor/lib/x.sh:3 The Gizmo guard can be skipped. Proof: a quoted name passes did not hold after 2 rounds' 'exit 0'
  jq '.auto.reserved = ["gizmo"]' "$M/.conveyor/project.json" > "$T/pack.json" && cp "$T/pack.json" "$M/.conveyor/project.json" || fail "the pack was not changed"
  poll || fail "no wake for a review block that holds the pack's own reserved word: $(cat "$T/err")"
  grep -qF "${BLOCKED}the fix for [P1] conveyor/lib/x.sh:3 The Gizmo" <<<"$wake" || fail "the wake does not name the block: $wake"
  [ ! -e "$T/retries" ] || fail "the watcher retried a block whose reason holds the pack's reserved word: $(cat "$T/retries")"
}

# The kind on, and `auto reserved` fails on the record's host (as when the owner's profile is there but cannot be read):
# the block wakes with its own reason, and no retry runs. Bug it catches: a block whose reserved words could not be read
# was retried, or gave no wake, so a card the owner may reserve was queued again or left with no word; the standing
# rule (lib/standing.sh) tells the Foreman this wake is not a failed retry.
t_unread() {
  fixture unread '["review-retry"]' "$REVIEW" 'exit 0'
  CONVEYOR_FOREMAN_ASK="[ \"\$CONVEYOR_CMD\" != 'auto reserved' ] || exit 1; $CONVEYOR_FOREMAN_ASK"
  poll || fail "no wake for a review block whose reserved words could not be read: $(cat "$T/err")"
  # The block's line is its reason and nothing after it but the "(as of HH:MMZ)" stamp: no "; the review-retry of #7
  # failed" and no "#7 was retried" tail, as no retry ran.
  grep -qxE "$(sed 's/[][\.*^$()+?{}|/]/\\&/g' <<<"$BLOCKED$REVIEW")( \(as of [0-9]{2}:[0-9]{2}Z\))?" <<<"$wake" \
    || fail "the wake does not give the block with its own reason alone: $wake"
  [ ! -e "$T/retries" ] || fail "the watcher retried a block whose reserved words could not be read: $(cat "$T/retries")"
}

# Review-retry gives an issue back once. The first review block of #7 (card c7) is retried, marked as review-retry's
# (CONVEYOR_REVIEWRETRY, its card c7, so the host's retry keeps it: commands/retry.sh); the card that retry started (c8, which
# health marks reviewRetried), blocked by its review again on a narrower finding, is not retried: it wakes as a block,
# for the owner. Bug it catches (#1589): the watcher remembered the card, not the issue, so each new card of the issue
# was given back again, with no end.
t_again() {
  fixture again '["review-retry"]' "$REVIEW" 'echo "conveyor: issue #7 is queued again"'
  poll && fail "the first review block woke the Foreman: $wake"
  [ "$(cat "$T/retries" 2>/dev/null)" = 'retry 7' ] && [ "$(cat "$T/marks")" = c7 ] \
    || fail "the first block of #7 was not retried as review-retry's: $(cat "$T/retries" "$T/marks" "$T/err" 2>/dev/null)"
  jq -c --arg r "${REVIEW/did not hold/(the quoted name now) did not hold}" '.health.blocked = [{card: "c8", issue: 7, since: "2026-11-19T10:30:00Z", reason: $r, reviewRetried: true}]' \
    "$T/snap" > "$T/snap.new" && mv "$T/snap.new" "$T/snap" || fail "the snapshot of the second block was not made"
  poll || fail "no wake for the second review block of #7: $(cat "$T/err")"
  grep -qF "alpha: #7 is blocked since 2026-11-19T10:30:00Z: ${REVIEW/did not hold/(the quoted name now) did not hold}" <<<"$wake" \
    || fail "the wake does not name the second block: $wake"
  [ "$(wc -l < "$T/retries")" = 1 ] || fail "review-retry gave #7 back a second time: $(cat "$T/retries")"
}

cases=(on off fails slow other stale health reserved reservedpack unread again)
# The cases CONVEYOR_SHELL_TEST_CASE names (comma-separated), as the runner selects them; all of them with none set.
SEL=${CONVEYOR_SHELL_TEST_CASE:-${cases[*]}}; SEL=${SEL//,/ }
for c in $SEL; do case " ${cases[*]} " in *" $c "*) ;; *) echo "unknown case $c" >&2; exit 2 ;; esac; done
read -ra cases <<<"$SEL"
for c in "${cases[@]}"; do (t_"$c" && : > "$B/$c.passed") > "$B/$c.out" 2>&1 & done
wait
. "$SRC/tests/casesreport-helper.sh"
casesreport "$B" watch-retry- "${cases[@]}" || exit 1
echo "ok [watch-retry]"
