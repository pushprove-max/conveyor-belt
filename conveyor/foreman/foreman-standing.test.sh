#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The Foreman's start (foreman.sh, its claim's context) names each standing kind of routine yes the pack turns on
# (auto.standing, conveyor/lib/standing.sh), with its limits, and no kind that is off.
# Bug it catches: the kinds were only in one project's own Foreman notes, so no other install's Foreman acted on them,
# and a kind the owner turned off was still acted on.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
B=$(mktemp -d) || exit 1
trap 'rm -rf "$B"' EXIT
cd "$B" || exit 1
unset CONVEYOR_FOREMAN CONVEYOR_FOREMAN_LAUNCH CONVEYOR_CARD CONVEYOR_LANE CLAUDE_CONFIG_DIR CLAUDE_PROJECT_DIR CONVEYOR_MACHINE_ID
export CLAUDE_PLUGIN_OPTION_boardAutoOpen=false CONVEYOR_FOREMAN_ASK='exit 3'
fail() { echo "FAIL [standing-$CASE]: $*" >&2; exit 1; }
# fixture <case>: a project alpha with the test pack, its kinds <json list>, and its Foreman's folder.
fixture() {
  T=$B/$1 CASE=$1
  export HOME=$T/home XDG_CONFIG_HOME=$T/config XDG_DATA_HOME=$T/data XDG_STATE_HOME=$T/xstate
  M=$T/alpha FD=$T/foreman
  export CONVEYOR_FOREMAN_DIR=$FD CONVEYOR_MAIN=$M
  mkdir -p "$XDG_CONFIG_HOME/conveyor" "$FD" && git init -q "$M" && mkdir -p "$M/.conveyor" \
    && jq --argjson k "$2" '.plugin = {follow: "main"} | .auto.standing = $k' "$SRC/../lib/test-pack.json" > "$M/.conveyor/project.json" \
    && jq -n --arg m "$M" '{records: [{repo: "alpha", main: $m}]}' > "$XDG_CONFIG_HOME/conveyor/host.json" \
    || fail "the fixture was not made"
}
start() { (cd "$M" && bash "$SRC/foreman.sh" claim sA) || fail "the claim failed"; } # the claim prints the start's context
# The line each kind's rule starts with.
line() { echo "- $1: "; }
kinds=(asked-fix review-followup release-check fixed-block)

# One kind on: its rule and the limits are in the start, and no other kind's rule is.
one() { # <kind>
  local out k
  fixture "$1" "[\"$1\"]"; out=$(start)
  grep -qF '# STANDING YES' <<<"$out" && grep -qF -- "$(line "$1")" <<<"$out" \
    && grep -qF -- '- Still ask the owner, whatever the kind: new engine behaviour' <<<"$out" || fail "the start does not name the kind $1 that is on: $out"
  for k in "${kinds[@]}"; do [ "$k" = "$1" ] || ! grep -qF -- "$(line "$k")" <<<"$out" || fail "the start names $k, which is off: $out"; done
}
t_askedfix() { one asked-fix; }
t_reviewfollowup() { one review-followup; }
t_releasecheck() { one release-check; }
t_fixedblock() { one fixed-block; }
# Every kind off (the list setup writes): the start says nothing of standing kinds.
t_none() {
  local out; fixture none '[]'; out=$(start)
  grep -qF '# Foreman mode: you are' <<<"$out" || fail "no Foreman start: $out"
  ! grep -qE 'STANDING YES|WARNING: the standing' <<<"$out" || fail "the start names standing kinds while none is on: $out"
}

cases=(askedfix reviewfollowup releasecheck fixedblock none)
for c in "${cases[@]}"; do (t_"$c" && : > "$B/$c.passed") > "$B/$c.out" 2>&1 & done
wait
bad=0
for c in "${cases[@]}"; do cat "$B/$c.out" >&2; [ -e "$B/$c.passed" ] || bad=1; done
[ "$bad" = 0 ] || exit 1
echo "ok [standing]"
