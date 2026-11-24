#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# pending_fresh (lib.sh): before a stop relays the pending wakes, each blocked card that its record no longer holds
# blocked as the wake's line says is taken out. Bug (#1434): the stop relayed a wake as the watcher wrote it, so the
# Foreman acted on a card retried since. These cases call pending_fresh itself; waiter.test.sh t_retried runs it
# through a stop.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
B=$(mktemp -d); trap 'rm -rf "$B"' EXIT
cd "$B" || exit 1
unset CONVEYOR_FOREMAN_ASK CONVEYOR_FOREMAN_LAUNCH CONVEYOR_MAIN CLAUDE_PROJECT_DIR CONVEYOR_FOREMAN_WATCHERS
fail() { echo "FAIL [$CASE]: $*" >&2; exit 1; }
# fixture <case> <records' repos>: a Foreman of its own in $B/<case> (T, its folder FD, its pending folder made), with
# a host file whose records are the repos named, each with a main checkout folder $T/<repo>.
fixture() {
  CASE=$1 T=$B/$1
  export XDG_CONFIG_HOME=$T/config XDG_DATA_HOME=$T/data HOME=$T/home CONVEYOR_FOREMAN=1 CONVEYOR_FOREMAN_DIR=$T/fd
  FD=$CONVEYOR_FOREMAN_DIR
  mkdir -p "$XDG_CONFIG_HOME/conveyor" "$HOME" "$FD/pending" "$T/alpha" "$T/$2" || exit 1
  jq -n --arg r "$2" --arg m "$T/$2" '{records: [{repo: $r, main: $m}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
}
WAKE=20261119T100000Z-1-a.wake # a wake put at 10:00
fresh() { bash -c '. "$1/lib.sh" && pending_fresh' _ "$SRC"; } # with CONVEYOR_FOREMAN_ASK: the record's health
wake() { cat "$FD/pending/$WAKE" 2>/dev/null; }

# Bug caught: a health that gives no blocked list (here the whole snapshot in its place, its list under .health) was
# read as nothing blocked, so pending_fresh took every blocked card out of the wake. Such a health keeps its lines.
t_freshnolist() {
fixture freshnolist alpha
local w=$'Conveyor: alpha: blocked: #7\nalpha: #7 is blocked since 2026-11-19T09:58:00Z: tests failed'
printf '%s\n' "$w" > "$FD/pending/$WAKE"
CONVEYOR_FOREMAN_ASK='[ "$CONVEYOR_CMD" = health ] || exit 3; echo "{\"health\": {\"blocked\": [{\"card\": \"c7\", \"issue\": 7}]}}"' fresh
[ "$(wake)" = "$w" ] || fail "for a wake of #7 blocked and a health with no blocked list ({health: {blocked: [#7]}}), pending_fresh changed the wake: $(wake)"
}

# Bugs caught: a review-retry that failed adds its note after the block's reason (watch-conveyor.sh reviewretry), and
# health gives the reason alone, so pending_fresh read the line as another block and took out the wake that reports the
# failed retry: #7 stayed blocked with no word. A review-retry that worked but whose act was not logged (#8, its line
# marked with the time of an older snapshot too) leaves #8 out of health, so pending_fresh took its line out, and the
# Foreman never heard that the log lacks the act. #7 still blocked as the wake says, #8 retried: the wake is kept whole.
t_freshretrynote() {
fixture freshretrynote alpha
local w=$'Conveyor: alpha: blocked: #7 #8\nalpha: #7 is blocked since 2026-11-19T09:58:00Z: the fix for [P1] a did not hold after 3 rounds; the review-retry of #7 failed: conveyor: card c7 is still ending\nalpha: #8 is blocked since 2026-11-19T09:59:00Z: the fix for [P2] b did not hold after 2 rounds (as of 09:59Z); #8 was retried (review-retry), but the act was not logged: exit 1'
printf '%s\n' "$w" > "$FD/pending/$WAKE"
CONVEYOR_FOREMAN_ASK='[ "$CONVEYOR_CMD" = health ] || exit 3; echo "{\"blocked\": [{\"card\": \"c7\", \"issue\": 7, \"since\": \"2026-11-19T09:58:00Z\", \"reason\": \"the fix for [P1] a did not hold after 3 rounds\"}]}"' fresh
[ "$(wake)" = "$w" ] || fail "for a wake of #7 blocked with a failed review-retry's note and #8 with a not-logged one, and health holding #7 blocked as the wake says and #8 not at all, pending_fresh changed the wake: $(wake)"
}

# Bug caught: a "has been blocked for" reminder named no since, so when #7 was retried and blocked again for the same
# reason before the stop, pending_fresh kept it and the stop relayed the old block's time. A check of health's since
# against the time the wake was put (its file name, 10:00) missed a new block that began before the watcher put the
# wake (09:59, while another project's snapshot was read). The reminder names its block's since: health's is another,
# so #7's reminder goes. #8, blocked since the time its reminder names, stays.
t_freshreminder() {
fixture freshreminder alpha
printf '%s\n' 'Conveyor: alpha: still blocked: #7 #8' 'alpha: #7 has been blocked for 30m (since 2026-11-19T09:28:00Z): tests failed' \
  'alpha: #8 has been blocked for 1h0m (since 2026-11-19T09:00:00Z): tests failed' > "$FD/pending/$WAKE"
CONVEYOR_FOREMAN_ASK='[ "$CONVEYOR_CMD" = health ] || exit 3; echo "{\"blocked\": [{\"card\": \"c7b\", \"issue\": 7, \"since\": \"2026-11-19T09:59:00Z\", \"reason\": \"tests failed\"},
  {\"card\": \"c8\", \"issue\": 8, \"since\": \"2026-11-19T09:00:00Z\", \"reason\": \"tests failed\"}]}"' fresh
[ "$(wake)" = $'Conveyor: alpha: still blocked: #8\nalpha: #8 has been blocked for 1h0m (since 2026-11-19T09:00:00Z): tests failed' ] \
  || fail "for a wake put at 10:00 of #7 blocked since 09:28 and #8 since 09:00 for 'tests failed', and health holding #7 blocked since 09:59 and #8 since 09:00 for that reason, pending_fresh did not keep #8 alone: $(wake)"
}

# Bug caught: pending_fresh found a wake's repo among the host file's records only, but the Foreman of a checkout no
# record names watches it as its own (mine), named for its folder: with records of beta alone, a wake of alpha's #7
# blocked was kept after `retry 7`, and the stop relayed it. Health gives no #7 now: the wake goes.
t_freshown() {
fixture freshown beta
printf '%s\n' 'Conveyor: alpha: blocked: #7' 'alpha: #7 is blocked since 2026-11-19T09:58:00Z: tests failed' > "$FD/pending/$WAKE"
CONVEYOR_MAIN=$T/alpha CONVEYOR_FOREMAN_ASK='[ "$CONVEYOR_REPO $CONVEYOR_CMD" = "alpha health" ] || exit 3; echo "{\"blocked\": []}"' fresh
[ ! -e "$FD/pending/$WAKE" ] \
  || fail "for a wake of alpha's #7 blocked, run from checkout alpha with records of beta alone and alpha's health giving nothing blocked, pending_fresh kept the wake: $(wake)"
}

# Bug caught (#1658): a blocked card with no issue (a review follow-up) is named in the wake by its name, and health
# gave it none (its ref #0), so pending_fresh deleted the wake unseen. Health names it now (health.test.sh
# t_healthnoissuename): the wake stays and the stop relays it (pending_run).
t_freshnoissue() {
fixture freshnoissue alpha
local w=$'Conveyor: alpha: blocked: Review follow-up of #7\nalpha: Review follow-up of #7 is blocked since 2026-11-19T09:58:00Z: tests failed'
printf '%s\n' "$w" > "$FD/pending/$WAKE"
CONVEYOR_FOREMAN_ASK='[ "$CONVEYOR_CMD" = health ] || exit 3; echo "{\"blocked\": [{\"card\": \"c1\", \"issue\": 0, \"name\": \"Review follow-up of #7\", \"since\": \"2026-11-19T09:58:00Z\", \"reason\": \"tests failed\"}]}"' fresh
[ "$(wake)" = "$w" ] \
  || fail "for a wake of 'Review follow-up of #7' blocked and health naming that card blocked as the wake says, pending_fresh changed the wake: $(wake)"
local out; out=$(bash -c '. "$1/lib.sh" && pending_run "$2"' _ "$SRC" "$T/ack")
[ "$out" = "$w" ] || fail "for the kept wake of 'Review follow-up of #7' blocked, pending_run did not relay it: $out"
}

cases=(freshnolist freshretrynote freshreminder freshown freshnoissue)
# The cases CONVEYOR_SHELL_TEST_CASE names (comma-separated), as the runner selects them; all of them with none set.
SEL=${CONVEYOR_SHELL_TEST_CASE:-${cases[*]}}; SEL=${SEL//,/ }
for c in $SEL; do case " ${cases[*]} " in *" $c "*) ;; *) echo "unknown case $c" >&2; exit 2 ;; esac; done
read -ra cases <<<"$SEL"
for c in "${cases[@]}"; do ("t_$c" && : > "$B/$c.passed") > "$B/$c.out" 2>&1 & done
wait
bad=0
for c in "${cases[@]}"; do
  cat "$B/$c.out" >&2
  # A pass prints `ok <case>`, named as its FAIL line names it: the pass the main-red proof reads.
  if [ -e "$B/$c.passed" ]; then echo "ok $c"; else bad=1; [ -s "$B/$c.out" ] || echo "FAIL [$c]: ended with no word" >&2; fi
done
[ "$bad" = 0 ] || exit 1
