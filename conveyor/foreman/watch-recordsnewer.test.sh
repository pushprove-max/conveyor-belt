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
# One poll of the case's Foreman, <n> polls after the first; 0 with a wake put in pending, which wake holds.
poll() { # <case> <n>
  local fd=$T/$1/foreman; rm -f "$fd"/pending/*.wake
  CONVEYOR_FOREMAN_DIR=$fd CONVEYOR_MAIN=$M CONVEYOR_FOREMAN_NOW=$((NOW + 60 * $2)) CONVEYOR_FOREMAN_ASK="cat $T/snap" \
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

[ "$fails" = 0 ]
