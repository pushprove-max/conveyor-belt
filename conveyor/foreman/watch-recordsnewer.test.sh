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
# A snapshot with nothing on the belt and nothing to pick, and the records changed after it (<newer>: true) or not.
snap() { # <newer>
  jq -cn --argjson r "$1" '{recordsNewer: $r, belt: [], queue: {next: []}, health: {time: "2026-11-20T14:00:00Z", loop: true,
    gh: true, ghReached: true, ghWhy: null, ghRead: "r1", state: "running", reason: null, stuck: [], waiting: [], blocked: [], pushError: null, pushFailingSince: null}}' > "$T/snap"
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
# The status of that snapshot says the belt can hold more than it shows.
status() {
  snap true; wake=
  out=$(CONVEYOR_FOREMAN_DIR=$T/status/foreman CONVEYOR_MAIN=$M CONVEYOR_FOREMAN_NOW=$NOW CONVEYOR_FOREMAN_ASK="cat $T/snap" bash "$SRC/watch-conveyor.sh" --status 2>&1)
  grep -qxF 'alpha: 0 on the belt (or more: the card records changed after this snapshot was made, and a new one is not ready)' <<<"$out"
}
check 'the status of a snapshot made before the last change to the card records says the belt can hold more' status

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

[ "$fails" = 0 ]
