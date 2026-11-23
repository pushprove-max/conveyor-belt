#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The Foreman's Conveyor watcher, watch-conveyor.sh, on health's before list (the open issues waiting for the owner's
# yes before their build): one poll (--once) at a time of a snapshot and health given by CONVEYOR_FOREMAN_ASK, the
# clock set by CONVEYOR_FOREMAN_NOW. Each case has a Foreman folder of its own.
# Bug caught (R221): health gives before null when gh cannot list the open issues (views.sh). The poll with null made
# no before: line, and both the snapshot path and the health path rewrote conveyor-reported.txt without the reported
# before:12 key, so the next read that listed #12 again woke the Foreman on it a second time.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
fails=0 NOW=$(date +%s) M=$T/alpha
export HOME=$T/home XDG_CONFIG_HOME=$T/config
unset CONVEYOR_FOREMAN CONVEYOR_FOREMAN_DIR CONVEYOR_FOREMAN_ASK CLAUDE_PROJECT_DIR
mkdir -p "$HOME" "$XDG_CONFIG_HOME/conveyor" && jq -n --arg m "$M" '{records: [{repo: "alpha", main: $m}]}' > "$XDG_CONFIG_HOME/conveyor/host.json" \
  && git init -q "$M" && mkdir -p "$M/.conveyor" && jq -n '{plugin: {follow: "main"}}' > "$M/.conveyor/project.json" \
  || { echo "FAIL [watch-before]: the fixture was not made" >&2; exit 1; }
# A health record whose before is <before> (a JSON list of issue numbers, or null), and a snapshot holding it, with a
# card on the belt so the record is not idle.
health() { # <case> <before>
  jq -cn --argjson b "$2" '{time: "2026-11-20T12:00:00Z", loop: true, gh: true, ghReached: true, ghWhy: null, ghRead: "r1", state: "running",
    reason: null, stuck: [], waiting: [], blocked: [], pushError: null, pushFailingSince: null,
    before: (if $b == null then null else [$b[] | {issue: ., title: "a new button", since: "2026-11-20T10:00:00Z"}] end)}' > "$T/$1.health" \
    && jq -c '{belt: [{card: "x"}], queue: {next: []}, health: .}' "$T/$1.health" > "$T/$1.snap"
}
# One poll of the case's Foreman, <n> seconds after the first (under DOWN_S, so failed snapshot reads never make the
# record unreachable); 0 with a wake put in pending, which wake holds. With "nosnap", the snapshot read fails and the
# watcher reads health in its place.
poll() { # <case> <n> [nosnap]
  local fd=$T/$1/foreman ask="case \$CONVEYOR_CMD in snapshot) cat $T/$1.snap ;; health) cat $T/$1.health ;; *) exit 3 ;; esac"
  [ -z "${3-}" ] || ask="case \$CONVEYOR_CMD in health) cat $T/$1.health ;; *) exit 1 ;; esac"
  rm -f "$fd"/pending/*.wake; wake=
  CONVEYOR_FOREMAN_DIR=$fd CONVEYOR_MAIN=$M CONVEYOR_FOREMAN_NOW=$((NOW + $2)) CONVEYOR_FOREMAN_ASK=$ask \
    bash "$SRC/watch-conveyor.sh" --once 2>> "$T/$1.err" || return
  wake=$(cat "$fd"/pending/*.wake)
}
check() { if "${@:2}"; then echo "ok [watch-before]: $1"; else echo "FAIL [watch-before]: $1: ${wake:-no wake} $(cat "$T"/*.err 2>/dev/null)" >&2; fails=$((fails + 1)); fi; }

# before [#12], then null, then [#12] again, each from a snapshot that reads.
bysnap() {
  health bysnap '[12]'; poll bysnap 0 && grep -qF '#12 needs the owner' <<<"$wake" || return 1
  health bysnap null; ! poll bysnap 1 || return 1
  health bysnap '[12]'; ! poll bysnap 2
}
check 'a snapshot with before null keeps #12 reported: the next before [#12] wakes nothing' bysnap

# The same three reads from health, the snapshot read failing each time.
byhealth() {
  health byhealth '[12]'; poll byhealth 0 nosnap && grep -qF '#12 needs the owner' <<<"$wake" || return 1
  health byhealth null; ! poll byhealth 1 nosnap || return 1
  health byhealth '[12]'; ! poll byhealth 2 nosnap
}
check 'health with before null, read for a failed snapshot, keeps #12 reported: the next before [#12] wakes nothing' byhealth

[ "$fails" = 0 ]
