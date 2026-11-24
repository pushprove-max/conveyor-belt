#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The Foreman's status (watch-conveyor.sh --status) and wakes on a blocked card no session has got yet: its "not yet
# reported" lines; and its self-heals line, which is never something to act on. Split from status.test.sh, which shares the fixture below, to keep each file under 600 lines.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
B=$(mktemp -d); trap 'rm -rf "$B"' EXIT
cd "$B" || exit 1
unset CONVEYOR_FOREMAN CONVEYOR_FOREMAN_LAUNCH CONVEYOR_MAIN CLAUDE_PROJECT_DIR
fail() { echo "FAIL [$CASE]: $*" >&2; exit 1; }
NOW=$(jq -n '"2026-11-15T12:00:00Z" | fromdate')
# One project, alpha, on a host of its own in $B/<case> (T); its snapshot is the file $T/snap (ask, through
# CONVEYOR_FOREMAN_ASK), its Foreman's folder FD.
fixture() { # <case>
  T=$B/$1 M=$B/$1/alpha
  export XDG_CONFIG_HOME=$T/config XDG_DATA_HOME=$T/data HOME=$T/home CONVEYOR_FOREMAN_DIR=$T/state/foreman CONVEYOR_FOREMAN_NOW=$NOW
  FD=$CONVEYOR_FOREMAN_DIR
  mkdir -p "$XDG_CONFIG_HOME/conveyor" "$HOME" "$M/.conveyor" && git init -q "$M" && echo '{}' > "$M/.conveyor/project.json"
  jq -n --arg s "$T/state" --arg m "$M" '{stateDir: $s, records: [{repo: "alpha", main: $m}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  export CONVEYOR_FOREMAN_ASK="cat $T/snap"
}
# A snapshot: its health holds no problem; the jq filter given changes it.
snap() { # <jq filter>
  jq -n "{belt: [], queue: {next: [{issue: 99}], waiting: []}, open: {held: []}, suites: [],
    health: {time: \"2026-11-15T12:00:00Z\", loop: true, gh: true, blocked: [], waiting: [], stuck: [], pushFailingSince: null}} | $1" > "$T/snap"
}
poll() { CONVEYOR_MAIN=$M bash "$SRC/watch-conveyor.sh" --once 2>"$T/err"; }

# Issue 361: a card blocked two polls ago or more that no session has got is named on the status and in the next
# wake. Bug it catches: a block whose wake reached no session (or that no watcher saw) was told to no one, and the
# Foreman learned of it only when the owner asked. #5: no wake put (not in the reported list); #8: its wake still
# pending; #7: reported and delivered; #6: blocked under two polls ago. The snapshot is behind the card records, so
# its lines end "(as of 11:29Z)" and the pending wake of #8 has no suffix: bug it catches too, the full lines differed
# and the status left #8 out.
t_unreported() {
CASE=unreported; fixture unreported; mkdir -p "$FD/pending"
b() { echo "{card: \"c$1\", issue: $1, since: \"$2\", reason: \"tests failed twice\"}"; } # <issue> <since>
snap ".recordsNewer = true | .snapshotAt = \"2026-11-15T11:29:29Z\" | .health.blocked = [$(b 5 2026-11-15T11:00:00Z), $(b 6 2026-11-15T11:59:30Z), $(b 7 2026-11-15T11:00:00Z), $(b 8 2026-11-15T11:00:00Z)]"
printf '%s\n' alpha/blocked:c6 alpha/blocked:c7 alpha/blocked:c8 > "$FD/conveyor-reported.txt"
old=$FD/pending/20261115T110000Z-1-old.wake
printf '%s\n' 'Conveyor: alpha: blocked: #8' 'alpha: #8 is blocked since 2026-11-15T11:00:00Z: tests failed twice' > "$old"
out=$(CONVEYOR_MAIN=$M bash "$SRC/watch-conveyor.sh" --status 2>&1) || fail "the status failed: $out"
[ "$(grep '^not yet reported: ' <<<"$out")" = $'not yet reported: blocked #5\nnot yet reported: blocked #8' ] \
  || fail "the status does not name exactly the unreported blocked cards #5 and #8: $out"
poll || fail "no wake for the new blocked card #5: $(cat "$T/err")"
w=$(cat "$(find "$FD/pending" -name '*.wake' ! -name "${old##*/}")")
grep -qxF 'alpha: #5 is blocked since 2026-11-15T11:00:00Z: tests failed twice (as of 11:29Z)' <<<"$w" || fail "the wake does not name #5: $w"
[ "$(grep 'not yet reported' <<<"$w")" = 'alpha: not yet reported: blocked #8' ] \
  || fail "the wake does not name the pending #8 alone as not yet reported: $w"
}

# Bug caught: a wake relayed at a stop that stop.sh refused is kept as <wake>.sent-<session>.<pid>, its key reported,
# and the waiter relays it again later; the status read only pending/*.wake, so it left that card out meanwhile. A
# wake relayed at a stop that was not refused reached the session: its card is not named.
t_unrepsent() {
CASE=unrepsent; fixture unrepsent; mkdir -p "$FD/pending"
snap '.health.blocked = [{card: "c9", issue: 9, since: "2026-11-15T11:00:00Z", reason: "tests failed twice"}]'
echo alpha/blocked:c9 > "$FD/conveyor-reported.txt"
printf '%s\n' 'Conveyor: alpha: blocked: #9' 'alpha: #9 is blocked since 2026-11-15T11:00:00Z: tests failed twice' > "$FD/pending/20261115T110000Z-1-x.wake.sent-S.42"
echo k1 > "$FD/sent-stop"; echo k1 > "$FD/refused-stops"
out=$(CONVEYOR_MAIN=$M bash "$SRC/watch-conveyor.sh" --status 2>&1) || fail "the status failed: $out"
grep -qx 'not yet reported: blocked #9' <<<"$out" || fail "with the wake of #9 relayed at the refused stop k1, the status does not name #9 as not yet reported: $out"
echo k2 > "$FD/sent-stop"
out=$(CONVEYOR_MAIN=$M bash "$SRC/watch-conveyor.sh" --status 2>&1) || fail "the status failed: $out"
! grep -q 'not yet reported' <<<"$out" || fail "with the wake of #9 relayed at the stop k2, not refused, the status names it as not yet reported: $out"
}

# Bug caught: the wake relayed at a refused stop named the block "(as of 11:29Z)" (a snapshot behind the card
# records), and the status, reading the records now (recordsNow), gave the same block with no suffix; the full lines
# differed, so the status left the card out of "not yet reported". The other way round (a pending wake with no suffix,
# a snapshot line with it) is t_unreported's #8.
t_unrepasof() {
CASE=unrepasof; fixture unrepasof; mkdir -p "$FD/pending"
snap '.recordsNewer = true | .snapshotAt = "2026-11-15T11:29:29Z" | .health.blocked = [{card: "c7", issue: 7, since: "2026-11-15T11:00:00Z", reason: "its tests failed"}]
  | .recordsNow = {blocked: .health.blocked, waiting: []}'
echo alpha/blocked:c7 > "$FD/conveyor-reported.txt"
printf '%s\n' 'Conveyor: alpha: blocked: #7' 'alpha: #7 is blocked since 2026-11-15T11:00:00Z: its tests failed (as of 11:29Z)' > "$FD/pending/20261115T113000Z-1-x.wake.sent-S.42"
echo k1 > "$FD/sent-stop"; echo k1 > "$FD/refused-stops"
out=$(CONVEYOR_MAIN=$M bash "$SRC/watch-conveyor.sh" --status 2>&1) || fail "the status failed: $out"
grep -qxF 'needs you: #7 is blocked since 2026-11-15T11:00:00Z: its tests failed' <<<"$out" \
  || fail "the status read from recordsNow does not name #7 blocked with no suffix: $out"
grep -qx 'not yet reported: blocked #7' <<<"$out" \
  || fail "with the wake 'alpha: #7 is blocked since 2026-11-15T11:00:00Z: its tests failed (as of 11:29Z)' relayed at the refused stop k1, the status does not name #7 as not yet reported: $out"
}

# Bug caught: a review-retry that failed (reviewretry()) adds "; the review-retry of #N failed: <error>" to the block's
# wake line, after any "(as of HH:MMZ)"; the status compared the whole wake line with the plain block line, so a wake
# relayed at a refused stop that carried the note left the card out of "not yet reported".
t_unrepretry() {
CASE=unrepretry; fixture unrepretry; mkdir -p "$FD/pending"
snap '.health.blocked = [{card: "c7", issue: 7, since: "2026-11-15T11:00:00Z", reason: "its tests failed"}]'
echo alpha/blocked:c7 > "$FD/conveyor-reported.txt"
w='alpha: #7 is blocked since 2026-11-15T11:00:00Z: its tests failed (as of 11:29Z); the review-retry of #7 failed: #7 is still ending'
printf '%s\n' 'Conveyor: alpha: blocked: #7' "$w" > "$FD/pending/20261115T113000Z-1-x.wake.sent-S.42"
echo k1 > "$FD/sent-stop"; echo k1 > "$FD/refused-stops"
out=$(CONVEYOR_MAIN=$M bash "$SRC/watch-conveyor.sh" --status 2>&1) || fail "the status failed: $out"
grep -qx 'not yet reported: blocked #7' <<<"$out" \
  || fail "with the wake '$w' relayed at the refused stop k1, the status does not name #7 as not yet reported: $out"
}

# Bug caught: the watcher queued a block from a snapshot behind the card records, so its wake line ends in
# " (as of HH:MMZ)"; the status builds that block from the card records now (NOWBLOCKED) with no suffix, and the
# exact match missed both the wake still pending (#8) and the wake relayed at the refused stop (#9), so the status
# left them out; and a later poll, from a snapshot made at another time, gave the next wake (for the new #10) none of
# them, as its own block lines end in another time.
t_unrepsentasof() {
CASE=unrepsentasof; fixture unrepsentasof; mkdir -p "$FD/pending"
b() { echo "{card: \"c$1\", issue: $1, since: \"2026-11-15T11:00:00Z\", reason: \"tests failed twice\"}"; } # <issue>
snap ".recordsNewer = true | .snapshotAt = \"2026-11-15T11:50:00Z\" | .health.blocked = [$(b 8), $(b 9)]
  | .recordsNow = {blocked: [$(b 8), $(b 9)], waiting: []}"
printf '%s\n' alpha/blocked:c8 alpha/blocked:c9 > "$FD/conveyor-reported.txt"
w8='alpha: #8 is blocked since 2026-11-15T11:00:00Z: tests failed twice (as of 11:50Z)'
w9='alpha: #9 is blocked since 2026-11-15T11:00:00Z: tests failed twice (as of 11:50Z)'
printf '%s\n' 'Conveyor: alpha: blocked: #8' "$w8" > "$FD/pending/20261115T110000Z-1-p.wake"
printf '%s\n' 'Conveyor: alpha: blocked: #9' "$w9" > "$FD/pending/20261115T110000Z-2-x.wake.sent-S.42"
echo k1 > "$FD/sent-stop"; echo k1 > "$FD/refused-stops"
out=$(CONVEYOR_MAIN=$M bash "$SRC/watch-conveyor.sh" --status 2>&1) || fail "the status failed: $out"
grep -qx 'not yet reported: blocked #8' <<<"$out" || fail "with the pending wake '$w8' of #8, the status does not name #8 as not yet reported: $out"
grep -qx 'not yet reported: blocked #9' <<<"$out" || fail "with the wake '$w9' of #9 relayed at the refused stop k1, the status does not name #9 as not yet reported: $out"
snap ".recordsNewer = true | .snapshotAt = \"2026-11-15T11:55:00Z\" | .health.blocked = [$(b 8), $(b 9), $(b 10)]"
poll || fail "no wake for the new blocked card #10 (snapshot of 11:55Z): $(cat "$T/err")"
w=$(cat "$(find "$FD/pending" -name '*.wake' ! -name 20261115T110000Z-1-p.wake)")
[ "$(grep 'not yet reported' <<<"$w")" = $'alpha: not yet reported: blocked #8\nalpha: not yet reported: blocked #9' ] \
  || fail "a poll of a snapshot made at 11:55Z, with the pending wake '$w8' and the wake '$w9' relayed at the refused stop k1, gave a wake that does not name #8 and #9 as not yet reported: $w"
}

# Issue 1559: the self-heals list waits for the batch cards of its areas, filed from the Board: the status gives its
# count and when the sort of the queued follow-ups ran, and never a "needs you" for it. Bug it catches: an entry of the
# list reported as work for the owner, or the sort's time missing from the status.
t_selfheals() {
CASE=selfheals; fixture selfheals
snap '.selfheals = {entries: [{id: "h0123456789ab", area: "area:engine", finding: "[P2] a.sh:3 a slow poll"}, {id: "h0123456789ac", area: null, finding: "[P3] b.sh:1 a stale line"}],
  areas: [{area: "area:engine", count: 1}, {area: null, count: 1}], sorted: {time: "2026-11-15T11:00:00Z", ended: "2026-11-15T11:02:00Z", items: 3, moved: 1}}'
out=$(CONVEYOR_MAIN=$M bash "$SRC/watch-conveyor.sh" --status 2>&1) || fail "the status failed: $out"
grep -qxF 'self-heals list: 2 finding(s) for the batch cards of their areas, filed from the Board (nothing to act on now); the sort of the queued follow-ups ran at 2026-11-15T11:00:00Z and moved 1 of 3' <<<"$out" \
  || fail "the status of a snapshot with 2 self-heals entries and a sort does not give their count and the sort's time: $out"
! grep -q '^needs you' <<<"$out" || fail "the status of a snapshot with only self-heals entries reports something that needs you: $out"
snap '.selfheals = {entries: [], areas: [], sorted: null}'
out=$(CONVEYOR_MAIN=$M bash "$SRC/watch-conveyor.sh" --status 2>&1) || fail "the status failed: $out"
! grep -q 'self-heals' <<<"$out" || fail "the status of a snapshot with an empty list and no sort has a self-heals line: $out"
}

# Bug caught (#1660): two follow-ups of one issue share their name, here blocked at the same time for the same reason,
# so their lines were the same: the pending wake of c2 made c1, reported and delivered, look not yet reported. Their
# lines carry the card id now, and the status names c2 alone.
t_unrepfollowups() {
CASE=unrepfollowups; fixture unrepfollowups; mkdir -p "$FD/pending"
f() { echo "{card: \"$1\", issue: 0, name: \"Review follow-up of #7\", since: \"2026-11-15T11:00:00Z\", reason: \"tests failed twice\"}"; }
snap ".health.blocked = [$(f c1), $(f c2)]"
printf '%s\n' alpha/blocked:c1 alpha/blocked:c2 > "$FD/conveyor-reported.txt"
printf '%s\n' 'Conveyor: alpha: blocked: Review follow-up of #7' \
  'alpha: Review follow-up of #7 (card c2) is blocked since 2026-11-15T11:00:00Z: tests failed twice' > "$FD/pending/20261115T110000Z-1-old.wake"
out=$(CONVEYOR_MAIN=$M bash "$SRC/watch-conveyor.sh" --status 2>&1) || fail "the status failed: $out"
[ "$(grep '^not yet reported: ' <<<"$out")" = 'not yet reported: blocked Review follow-up of #7 (card c2)' ] \
  || fail "with follow-ups c1 (reported, delivered) and c2 (its wake pending) of #7 blocked, the status does not name c2 alone as not yet reported: $out"
}

cases=(unreported unrepsent unrepasof unrepretry unrepsentasof selfheals unrepfollowups)
# The cases CONVEYOR_SHELL_TEST_CASE names (comma-separated), as the runner selects them; all of them with none set.
SEL=${CONVEYOR_SHELL_TEST_CASE:-${cases[*]}}; SEL=${SEL//,/ }
for c in $SEL; do case " ${cases[*]} " in *" $c "*) ;; *) echo "unknown case $c" >&2; exit 2 ;; esac; done
read -ra cases <<<"$SEL"
for c in "${cases[@]}"; do ("t_$c" && : > "$B/$c.passed") > "$B/$c.out" 2>&1 & done
wait
bad=0
for c in "${cases[@]}"; do
  cat "$B/$c.out" >&2
  [ -e "$B/$c.passed" ] || { bad=1; [ -s "$B/$c.out" ] || echo "FAIL [$c]: ended with no word" >&2; }
done
[ "$bad" = 0 ] || exit 1
echo ok
