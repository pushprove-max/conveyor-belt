#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The Foreman's Conveyor watcher, watch-conveyor.sh, on health's gh fields: one poll (--once) at a time of a snapshot
# given by CONVEYOR_FOREMAN_ASK, the clock set by CONVEYOR_FOREMAN_NOW. Each case has a Foreman folder of its own.
# Bug (#410): a gh auth status that was slow or timed out read as signed out, and woke the Foreman with "gh is signed
# out" while gh held its token. Health now says signed in (gh) from gh auth token, and GitHub reached (ghReached) from
# gh auth status; GitHub not reached wakes only on two polls in a row, and signed out still wakes at once.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
fails=0 NOW=$(date +%s) M=$T/alpha
export HOME=$T/home XDG_CONFIG_HOME=$T/config
unset CONVEYOR_FOREMAN CONVEYOR_FOREMAN_DIR CONVEYOR_FOREMAN_ASK CLAUDE_PROJECT_DIR
mkdir -p "$HOME" "$XDG_CONFIG_HOME/conveyor" && jq -n --arg m "$M" '{records: [{repo: "alpha", main: $m}]}' > "$XDG_CONFIG_HOME/conveyor/host.json" \
  && git init -q "$M" && mkdir -p "$M/.conveyor" && jq -n '{plugin: {follow: "main"}}' > "$M/.conveyor/project.json" \
  || { echo "FAIL [watch-gh]: the fixture was not made" >&2; exit 1; }
# A snapshot whose health gives the gh and ghReached fields given; a card on the belt, so the record is not idle.
snap() { # <gh> <ghReached>
  jq -cn --argjson g "$1" --argjson r "$2" '{belt: [{card: "x"}], queue: {next: []}, health: {time: "2026-11-11T12:00:00Z", loop: true,
    gh: $g, ghReached: $r, state: "running", reason: null, stuck: [], waiting: [], blocked: [], pushError: null, pushFailingSince: null}}' > "$T/snap"
}
# One poll of the case's Foreman, <n> polls after the first; 0 with a wake put in pending, which wake holds.
poll() { # <case> <n>
  local fd=$T/$1/foreman; rm -f "$fd"/pending/*.wake
  CONVEYOR_FOREMAN_DIR=$fd CONVEYOR_MAIN=$M CONVEYOR_FOREMAN_NOW=$((NOW + 60 * $2)) CONVEYOR_FOREMAN_ASK="cat $T/snap" \
    bash "$SRC/watch-conveyor.sh" --once 2>> "$T/$1.err" || return
  wake=$(cat "$fd"/pending/*.wake)
}
check() { if "${@:2}"; then echo "ok [watch-gh]: $1"; else echo "FAIL [watch-gh]: $1: ${wake:-no wake} $(cat "$T"/*.err 2>/dev/null)" >&2; fails=$((fails + 1)); fi; }

# gh auth token works and gh auth status timed out: signed in, GitHub not reached.
unreached() {
  snap true false; wake=
  ! poll unreached 0 || return 1 # one such poll wakes nothing
  poll unreached 1 && grep -qF 'alpha: GitHub not reached' <<<"$wake" && ! grep -qF 'signed out' <<<"$wake"
}
check 'GitHub not reached wakes on the second poll in a row, never as signed out' unreached

# gh auth token fails: signed out, at the first poll.
signedout() { snap false null; wake=; poll signedout 0 && grep -qF 'alpha: gh is signed out' <<<"$wake"; }
check 'gh signed out wakes the Foreman at once' signedout

[ "$fails" = 0 ]
