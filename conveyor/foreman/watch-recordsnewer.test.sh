#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The Foreman's Conveyor watcher, watch-conveyor.sh, on a snapshot made before the last change to the card records
# (recordsNewer, commands/snapshot.sh): one poll (--once) at a time of a snapshot given by CONVEYOR_FOREMAN_ASK, the
# clock set by CONVEYOR_FOREMAN_NOW, and the status (--status) of the same snapshot. Each case has a Foreman folder of
# its own.
# Bug (#1032): a retry rewrites the card records, so the next snapshot is built from them whole, and that can take
# minutes. Until it was ready, every poll read the snapshot from before the retry, its belt empty, and the watcher
# woke the Foreman with "Conveyor is idle" while a card of the retried issue was in its build step; the status said
# "0 on the belt".
# Bug (#1114): a snapshot from before a retry still lists the retried card blocked, and every poll woke the Foreman
# with it again ("#7 is blocked since"), and the status named it, while #7 was in its build again.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
fails=0 NOW=$(date +%s) M=$T/alpha
export HOME=$T/home XDG_CONFIG_HOME=$T/config
unset CONVEYOR_FOREMAN CONVEYOR_FOREMAN_DIR CONVEYOR_FOREMAN_ASK CLAUDE_PROJECT_DIR
mkdir -p "$HOME" "$XDG_CONFIG_HOME/conveyor" && jq -n --arg m "$M" '{records: [{repo: "alpha", main: $m}]}' > "$XDG_CONFIG_HOME/conveyor/host.json" \
  && git init -q "$M" && mkdir -p "$M/.conveyor" && jq -n '{plugin: {follow: "main"}}' > "$M/.conveyor/project.json" \
  || { echo "FAIL [watch-recordsnewer]: the fixture was not made" >&2; exit 1; }
# A snapshot made at 14:00 with nothing on the belt and nothing to pick, and the records changed after it (<newer>:
# true) or not; <more> is merged into it.
snap() { # <newer> [<more>]
  jq -cn --argjson r "$1" --argjson x "$(jq -cn "${2:-{\}}")" '{snapshotAt: "2026-11-20T14:00:00Z", recordsNewer: $r, belt: [], queue: {next: []}, health: {time: "2026-11-20T14:00:00Z", loop: true,
    gh: true, ghReached: true, ghWhy: null, ghRead: "r1", state: "running", reason: null, stuck: [], waiting: [], blocked: [], pushError: null, pushFailingSince: null}} * $x' > "$T/snap"
}
# The ask seam: the snapshot $T/snap, and `conveyor.sh health` as $T/health (when there is one) gives it.
ASK="case \$CONVEYOR_CMD in snapshot) cat $T/snap ;; health) cat $T/health ;; *) exit 3 ;; esac"
# One poll of the case's Foreman, <n> polls after the first; 0 with a wake put in pending, which wake holds.
poll() { # <case> <n>
  local fd=$T/$1/foreman; rm -f "$fd"/pending/*.wake
  CONVEYOR_FOREMAN_DIR=$fd CONVEYOR_MAIN=$M CONVEYOR_FOREMAN_NOW=$((NOW + 60 * $2)) CONVEYOR_FOREMAN_ASK=$ASK \
    bash "$SRC/watch-conveyor.sh" --once 2>> "$T/$1.err" || return
  wake=$(cat "$fd"/pending/*.wake)
}
check() { if "${@:2}"; then echo "ok [watch-recordsnewer]: $1"; else echo "FAIL [watch-recordsnewer]: $1: ${wake:-no wake} ${out:-} $(cat "$T"/*.err 2>/dev/null)" >&2; fails=$((fails + 1)); fi; }

# The snapshot from before the records changed, on two polls in a row (idle wakes on the second): no wake.
newer() { snap true; wake=; ! poll newer 0 && ! poll newer 1; }
check 'a snapshot made before the last change to the card records is not called idle' newer
# The same snapshot made after it: the second poll wakes with idle, so the case above proves the flag.
current() { snap false; wake=; ! poll current 0 && poll current 1 && grep -qF 'Conveyor is idle' <<<"$wake"; }
check 'a snapshot made after the last change to the card records, with nothing to do, wakes as idle' current
# The status of the snapshot in <T>/snap, its Foreman folder <case>'s.
statusof() { CONVEYOR_FOREMAN_DIR=$T/$1/foreman CONVEYOR_MAIN=$M CONVEYOR_FOREMAN_NOW=$NOW CONVEYOR_FOREMAN_ASK="cat $T/snap" bash "$SRC/watch-conveyor.sh" --status 2>&1; }
# The status of that snapshot says the belt has changed since it was made.
status() {
  snap true; wake=; out=$(statusof status)
  grep -qxF 'alpha: 0 on the belt (as of 2026-11-20T14:00:00Z, the belt has changed since)' <<<"$out"
}
check 'the status of a snapshot made before the last change to the card records says the belt has changed since' status
# Bug (#1101): the status read the blocked cards and the building count from the old snapshot alone, so it said
# "building 0" and named no blocked card while cards built and blocked. Here the snapshot (building 3, #4 blocked, #5
# waiting for the yes) is older than a blocked line of #7 and one of #8 that stops for the yes, and #4 was retried
# since: what the card records and loop.json say now (recordsNow, commands/snapshot.sh) names #7 blocked, keeps #5
# waiting, drops #4 and counts 5. Bug: #8 was named an ordinary block, as the status took the cards waiting for the
# yes from the old snapshot's list, which has no entry for a stop made since.
# Bug (#1107): the status said "0 on the belt", the old snapshot's empty belt, while loop.json said building: 5. The
# belt's count is the one of now, loop.json's 5 and one card landed since and on the belt for its push (recordsNow's
# landed: bug, the count left it out), and the line says the snapshot is behind the card records.
# Bug (#1305): the count left out a card in review or in its Test step: the belt's count is loop.json's running
# (7), not the cards counted against the cap.
blocked() {
  snap true '{health: {builderCap: 8, building: 3, waitingCount: 0,
      blocked: [{card: "c4", issue: 4, reason: "the session made no change", since: "2026-11-20T13:00:00Z"}],
      waiting: [{card: "c5", issue: 5, reason: "needs a yes", since: "2026-11-20T13:30:00Z"}]},
    recordsNow: {building: 5, waitingCount: 0, running: 7, landed: 1, blocked: [{card: "c7", issue: 7, name: null, reason: "the session made no change", since: "2026-11-20T14:05:00Z"}],
      waiting: [{card: "c5", issue: 5, name: null, reason: "needs a yes", since: "2026-11-20T13:30:00Z"},
        {card: "c8", issue: 8, name: null, reason: "needs a yes too", since: "2026-11-20T14:06:00Z"}]}}'
  wake=; out=$(statusof blocked)
  grep -qxF 'alpha: 8 on the belt now, from loop.json and the card records (the snapshot, as of 2026-11-20T14:00:00Z, is behind the card records: it lists 0); 5 of the cap 8' <<<"$out" \
    && grep -qxF 'needs you: #7 is blocked since 2026-11-20T14:05:00Z: the session made no change' <<<"$out" \
    && grep -qxF "needs you: #5 needs the owner's yes since 2026-11-20T13:30:00Z: needs a yes" <<<"$out" \
    && grep -qxF "needs you: #8 needs the owner's yes since 2026-11-20T14:06:00Z: needs a yes too" <<<"$out" \
    && ! grep -qF '#8 is blocked' <<<"$out" && ! grep -qF '#4' <<<"$out"
}
check 'the status of a snapshot older than a blocked line names the blocked card and counts what builds now' blocked

# A snapshot made at 21:29 before the card records changed: #7 (card c7) blocked, #9 in its build. $T/health is the
# health the engine reads from the card records now (health(), lib/views.sh: the records and the retried lines), with
# c7 blocked (<held>: true) or, after #7's retry line and its new card's start line, with no card blocked.
blocksnap() { # <held>
  jq -cn '{recordsNewer: true, snapshotAt: "2026-11-20T21:29:29Z", belt: [{card: "c9", issue: 9, step: "build"}], queue: {next: []},
    health: {time: "2026-11-20T21:29:29Z", loop: true, gh: true, ghReached: true, ghWhy: null, ghRead: "r1", state: "running", reason: null,
      stuck: [], waiting: [], blocked: [{card: "c7", issue: 7, since: "2026-11-20T21:20:00Z", reason: "its tests failed"}], pushError: null, pushFailingSince: null}}' > "$T/snap"
  jq -cn --argjson h "$1" '{time: "2026-11-20T21:35:00Z", loop: true, gh: true, stuck: [], waiting: [],
    blocked: (if $h then [{card: "c7", issue: 7, since: "2026-11-20T21:20:00Z", reason: "its tests failed"}] else [] end)}' > "$T/health"
}
bstatus() { out=$(CONVEYOR_FOREMAN_DIR=$T/$1/foreman CONVEYOR_MAIN=$M CONVEYOR_FOREMAN_NOW=$NOW CONVEYOR_FOREMAN_ASK=$ASK bash "$SRC/watch-conveyor.sh" --status 2>&1); }
# #7 retried and started again after the snapshot: no wake, and the status names #7 nowhere (not blocked, not
# "not yet reported").
retried() { blocksnap false; wake=; out=; ! poll retried 0 && bstatus retried-status && ! grep -qF '#7' <<<"$out"; }
check 'a card retried after the snapshot was made is not named blocked by a wake or the status' retried
# #7 still blocked in the records: the wake and the status name it, each line saying when the snapshot was made.
held() {
  blocksnap true; wake=; out=
  poll held 0 && grep -qxF 'alpha: #7 is blocked since 2026-11-20T21:20:00Z: its tests failed (as of 21:29Z)' <<<"$wake" \
    && bstatus held-status && grep -qxF 'needs you: #7 is blocked since 2026-11-20T21:20:00Z: its tests failed (as of 21:29Z)' <<<"$out" \
    && grep -qxF 'not yet reported: blocked #7' <<<"$out"
}
check 'a card still blocked in the card records is named blocked, as of the snapshot' held
# The same snapshot, #7 retried since (its recordsNow lists no card blocked), and health does not read: no wake. Bug
# it catches: with no health read, the snapshot's own blocked list was used, so #7 woke as blocked.
nohealth() {
  blocksnap false; rm -f "$T/health"; wake=
  jq -c '.recordsNow = {blocked: [], waiting: []}' "$T/snap" > "$T/snap.new" && mv "$T/snap.new" "$T/snap" && ! poll nohealth 0
}
check 'a card retried after the snapshot was made is not named blocked when health does not read' nohealth

[ "$fails" = 0 ] || exit 1
echo "ok watch-recordsnewer" # the pass of the case its FAIL lines name, as the main-red proof reads it
