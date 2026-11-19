#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The Foreman's Conveyor watcher, watch-conveyor.sh, on health's gh fields: one poll (--once) at a time of a snapshot
# given by CONVEYOR_FOREMAN_ASK, the clock set by CONVEYOR_FOREMAN_NOW. Each case has a Foreman folder of its own.
# Bug (#410): a gh auth status that was slow or timed out read as signed out, and woke the Foreman with "gh is signed
# out" while gh held its token. Health now says signed in (gh) from gh auth token, and GitHub reached (ghReached) from
# gh auth status; GitHub not reached and signed out each wake only on three polls in a row (#490; #715: a wake on the
# second poll cost the Foreman a turn, and the next poll had cleared it).
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
# A snapshot whose health gives the gh, ghReached and ghWhy fields given; a card on the belt, so the record is not idle.
# Each is a new health build, with a time of its own (health.time), from the GitHub read ghRead names: a new read
# unless one is given (a snapshot built again from the same GitHub folder read).
SNAPN=0
snap() { # <gh> <ghReached> [ghWhy] [ghRead]
  SNAPN=$((SNAPN + 1))
  jq -cn --argjson n "$SNAPN" --argjson g "$1" --argjson r "$2" --arg w "${3-}" --arg read "${4:-read$SNAPN}" '{belt: [{card: "x"}], queue: {next: []}, health: {time: (1762862400 + $n | todate), loop: true,
    gh: $g, ghReached: $r, ghWhy: (if $w == "" then null else $w end), ghRead: $read, state: "running", reason: null, stuck: [], waiting: [], blocked: [], pushError: null, pushFailingSince: null}}' > "$T/snap"
}
# gh auth token, stubbed: it times out (exit 124, as `timeout 20` gives) while $T/token-timeout is there, else gives a token.
mkdir -p "$T/bin" && printf '#!/bin/sh\n[ "$1 $2" = "auth token" ] || exit 2\n[ ! -e "%s/token-timeout" ] || exit 124\necho gho_stub\n' "$T" > "$T/bin/gh" \
  && chmod +x "$T/bin/gh" || { echo "FAIL [watch-gh]: the gh stub was not made" >&2; exit 1; }
# A snapshot as health makes it from one ghok() read (lib/issues.sh) with the stub: signed in and reached, or
# signed out with ghok's reason; its read is ghok's (GHREAD). With "again", the snapshot is built again from that read.
ghread() { # [again]
  [ -n "${1-}" ] || r=$(PATH=$T/bin:$PATH GITHUB='' bash -c '. "$1" && if ghok; then printf "true\t%s" "$GHREAD"; else printf "false\t%s\t%s" "$GHREAD" "$GHWHY"; fi' _ "$SRC/../lib/issues.sh")
  local g read why; IFS=$'\t' read -r g read why <<<"$r"
  if [ "$g" = true ]; then snap true true '' "$read"; else snap false null "$why" "$read"; fi
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
  snap true false '' r1; wake=
  ! poll unreached 0 || return 1 # one such poll wakes nothing
  ! poll unreached 1 || return 1 # nor the same snapshot again, as the snapshot cache gives it (#490)
  snap true false '' r1; ! poll unreached 2 || return 1 # nor one built again from the same GitHub read (#490)
  snap true false '' r2; ! poll unreached 3 || return 1 # nor the second read in a row (#715)
  snap true false '' r3; poll unreached 4 && grep -qF 'alpha: GitHub not reached' <<<"$wake" && ! grep -qF 'signed out' <<<"$wake"
}
check 'GitHub not reached wakes on the third poll in a row, not the second, never as signed out' unreached

# Bug (#490): one health read with gh false, while gh held its token, woke the Foreman with "gh is signed out".
# gh auth token times out once: no wake from that read, nor from the next poll that the snapshot cache gives the
# same snapshot, nor from a snapshot built again (a new health time) from the same GitHub folder read, nor from the
# good read after it. It times out on three reads in a row: the third wakes, with the reason (#715: not the second).
timedout() {
  wake=
  : > "$T/token-timeout"; ghread; ! poll timedout 0 || return 1
  ! poll timedout 1 || return 1 # the same snapshot again: one read, not two
  ghread again; ! poll timedout 2 || return 1 # built again after a card update, from the same read: still one read
  rm "$T/token-timeout"; ghread; ! poll timedout 3 || return 1
  : > "$T/token-timeout"; ghread; ! poll timedout 4 || return 1
  ghread; ! poll timedout 5 || return 1
  ghread; poll timedout 6 && grep -qF 'alpha: gh is signed out: gh auth token timed out after 20 s' <<<"$wake"
}
check 'one or two timed-out gh auth tokens in a row wake nothing; three wake as signed out, with why' timedout

[ "$fails" = 0 ]
