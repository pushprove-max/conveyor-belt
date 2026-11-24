#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases (#1601): the standing kind review-retry has two runners, the engine's needsretry() (lib/needsask.sh) and
# the Foreman's watcher (reviewretry(), foreman/watch-conveyor.sh), each of which reads the card records before its
# `retry` (again(), commands/retry.sh, under the records' lock). What must stay true: a card blocked by its review is
# given back once and its act logged once, whichever of the two runs first, and the second reports no failure. Bug it
# catches: the second retry failed, and the watcher woke the Foreman with "the review-retry of #7 failed" for a card
# building again. Each case makes the first runner act at the weak point: after the second one's last read of the
# records, before its retry. The real failure of a retry still wakes (watch-retry.test.sh t_fails).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# rtblocked: issue #7's card c0-7 blocked by its review, its patch kept, auto on with the standing kind review-retry on
# (nainit, nareview: needsask.test.sh); and the watcher's snapshot of it, read before either runner gave it back.
rtblocked() {
  setup "[$(issue 7 2026-01-01)]"; nainit 7; nareview
  jq -cn --arg r "$(jq -r 'select(.card == "c0-7" and .step == "blocked") | .reason' "$ST/cards.jsonl")" '{belt: [{card: "c9", issue: 9, step: "build"}], queue: {next: []},
    standing: ["review-retry"], health: {time: "2026-11-19T10:00:00Z", loop: true, gh: true, ghReached: true, state: "running", reason: null,
      stuck: [], waiting: [], blocked: [{card: "c0-7", issue: 7, since: "2026-11-19T09:58:00Z", reason: $r}], pushError: null, pushFailingSince: null}}' \
    > "$T/$CASE/snap" && mkdir -p "$T/$CASE/xconfig/conveyor" \
    && jq -n --arg m "$R" '{records: [{repo: "alpha", main: $m}]}' > "$T/$CASE/xconfig/conveyor/host.json" || fail "the watcher's fixture was not made"
}
# rtwatch: one poll (--once) of the Foreman's watcher on that snapshot, in a Foreman folder and home of the case's own;
# `retry <n>`, `auto standing`, `auto reserved` and `auto act review-retry <what>` run the engine on main with the
# case's own home and host file, as on the record's host; any other ask fails (the ask seam CONVEYOR_FOREMAN_ASK,
# foreman/lib.sh). Run whole, not as reviewretry() alone: that is a function inside the watcher's poll, and the poll's
# wake is what the Foreman reads. 0 with a wake put, which watch.wake then holds; its errors are in watch.err, and
# each ask it made, one a line, in watch.asks.
rtwatch() {
  local c=$T/$CASE
  mkdir -p "$c/home" && rm -f "$c"/foreman/pending/*.wake || return 2
  env -u CONVEYOR_FOREMAN -u CONVEYOR_FOREMAN_SESSION_PID -u CLAUDE_PROJECT_DIR -u CONVEYOR_MACHINE_ID \
    RTSNAP="$c/snap" RTASKS="$c/watch.asks" RTCONF="$XDG_CONFIG_HOME" RTHOME="$HOME" RTENG="$SRC/conveyor.sh" CONVEYOR_CARDS="$c/cards" HOME="$c/home" \
    XDG_CONFIG_HOME="$c/xconfig" CONVEYOR_FOREMAN_DIR="$c/foreman" CONVEYOR_MAIN="$R" \
    CONVEYOR_FOREMAN_ASK='echo "$CONVEYOR_CMD" >> "$RTASKS"; case $CONVEYOR_CMD in snapshot) cat "$RTSNAP" ;; health) jq -c .health "$RTSNAP" ;;
      "auto act review-retry "*) cd "$CONVEYOR_MAIN" && HOME=$RTHOME XDG_CONFIG_HOME=$RTCONF bash "$RTENG" auto act review-retry "${CONVEYOR_CMD#auto act review-retry }" ;;
      "retry "*|"auto standing"|"auto reserved") cd "$CONVEYOR_MAIN" && HOME=$RTHOME XDG_CONFIG_HOME=$RTCONF bash "$RTENG" $CONVEYOR_CMD ;; *) exit 3 ;; esac' \
    bash "$SRC/foreman/watch-conveyor.sh" --once 2>> "$c/watch.err" || return
  cat "$c"/foreman/pending/*.wake > "$c/watch.wake"
}
# rtonce <which ran first>: both runners asked for the retry of c0-7, which was given back once, by review-retry, its
# act logged once, and neither said its retry failed.
rtonce() {
  grep -qx 'retry 7' "$T/$CASE/watch.asks" 2>/dev/null || fail "the watcher did not ask for the retry of #7 ($1 first): $(cat "$T/$CASE/watch.asks" "$T/$CASE/watch.err" 2>&1)"
  grep -qxF c0-7 "$ST/auto/review-retry.cards" 2>/dev/null || fail "needsretry() did not take c0-7 ($1 first): $(cat "$T/$CASE/run.out")"
  jq -se '[.[] | select(.card == "c0-7" and .step == "blocked")] | length == 1 and .[0].retriedBy == "review-retry"' "$ST/retried.jsonl" >/dev/null \
    || fail "c0-7 was not given back once by review-retry ($1 first): $(cat "$ST/retried.jsonl" 2>&1)"
  [ "$(jq -sc '[.[] | select(.kind == "review-retry")] | length' "$CONVEYOR_RULING_LOG")" = 1 ] \
    || fail "the review-retry of c0-7 was not logged once ($1 first): $(cat "$CONVEYOR_RULING_LOG")"
  ! grep -qE 'review-retry of #7( \(card c0-7\))? failed' "$T/$CASE/run.out" "$T/$CASE/watch.err" "$T/$CASE/watch.wake" 2>/dev/null \
    || fail "the second review-retry of c0-7 said it failed ($1 first): $(cat "$T/$CASE/run.out" "$T/$CASE/watch.err" "$T/$CASE/watch.wake" 2>/dev/null)"
}

# The engine first: the loop's job gives c0-7 back; the watcher's poll, from its snapshot made before that, retries it
# again on the host and wakes nothing.
t_reviewtwicewatch() {
  rtblocked
  najob
  naretried c0-7 || fail "the loop's job did not give c0-7 back: $(cat "$T/$CASE/run.out")"
  rtwatch; case $? in
    0) fail "the watcher woke the Foreman for c0-7, which the engine gave back: $(cat "$T/$CASE/watch.wake")" ;;
    1) ;; *) fail "the watcher's poll did not run: $(cat "$T/$CASE/watch.err" 2>&1)" ;; esac
  rtonce engine
}
# The watcher first: its poll runs once needsretry() has read the card records (heldlist() comes after that read and
# before the retry), so needsretry() goes on to retry c0-7 from a read made before the watcher gave it back.
t_reviewtwiceengine() {
  rtblocked
  fx_in 'eval "rt_$(declare -f heldlist)"; heldlist() { rt_heldlist "$@" || return; [ -e "$T/$CASE/watched" ] || { : > "$T/$CASE/watched"; rtwatch > /dev/null 2>&1; echo "the watcher poll: $?"; }; }; needsjob'
  [ "$RC" = 0 ] && [ -e "$T/$CASE/watched" ] || fail "the loop's job ($RC) did not run the watcher after its read: $(cat "$T/$CASE/run.out")"
  grep -qx 'the watcher poll: 1' "$T/$CASE/run.out" \
    || fail "the watcher's poll, given c0-7 to retry, woke the Foreman or did not run: $(cat "$T/$CASE/run.out" "$T/$CASE/watch.wake" "$T/$CASE/watch.err" 2>&1)"
  rtonce watcher
}
