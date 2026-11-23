#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The Foreman's live summary (foreman.sh start) reads one snapshot per record, not `health` plus `cards`.
# Bug it catches: the start asked the record's host for health and then cards, each about 11 s on a loaded machine, so
# a /clear took 12 s to restart the role and the summary said "unavailable: no answer in time"; the snapshot answers in 0.04 s.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
B=$(mktemp -d) || exit 1
trap 'rm -rf "$B"' EXIT
cd "$B" || exit 1
unset CONVEYOR_FOREMAN CONVEYOR_FOREMAN_LAUNCH CONVEYOR_CARD CONVEYOR_LANE CLAUDE_CONFIG_DIR CLAUDE_PROJECT_DIR CONVEYOR_MACHINE_ID CONVEYOR_FOREMAN_ASK
export CLAUDE_PLUGIN_OPTION_boardAutoOpen=false
fail() { echo "FAIL [live-$CASE]: $*" >&2; exit 1; }
# fixture <case>: a Foreman's checkout of alpha with the test pack, the Foreman marked on session sA.
fixture() {
  T=$B/$1 CASE=$1
  export HOME=$T/home XDG_CONFIG_HOME=$T/config XDG_DATA_HOME=$T/data XDG_STATE_HOME=$T/xstate
  M=$T/alpha FD=$T/foreman
  export CONVEYOR_FOREMAN_DIR=$FD CONVEYOR_MAIN=$M
  mkdir -p "$XDG_CONFIG_HOME/conveyor" "$FD" "$M/.conveyor" && git init -q "$M" \
    && jq '.plugin = {follow: "main"}' "$SRC/../lib/test-pack.json" > "$M/.conveyor/project.json" \
    && git -C "$M" remote add origin https://example.com/acme/alpha.git \
    && jq -n --arg h "$M" '{records: [{repo: "alpha", main: $h}]}' > "$XDG_CONFIG_HOME/conveyor/host.json" \
    || fail "the fixture was not made"
}
# The record's host: health and cards hang past the old 10 s limit (a sleep, the slow reads); the snapshot answers.
# stub: not a claude, codex, opencode or gh stub: CONVEYOR_FOREMAN_ASK (foreman/lib.sh ask) is the seam for a Conveyor command.
SNAP='{snapshotAt: "2026-11-21T12:00:00Z", recordsNewer: false, belt: [{card: "c5", issue: 5, step: "build"}, {name: "Main is red (abc1234)", step: "fix"}, {card: "c6", issue: 6, step: "push", landed: true}],
  health: {time: "2026-11-21T11:59:00Z", loop: true, state: "running", reason: null, pushError: null,
    blocked: [{card: "c7", issue: 7, since: "2026-11-21T10:00:00Z", reason: "the build failed"}],
    waiting: [{card: "c8", issue: 8, since: "2026-11-21T11:00:00Z"}], before: []}}'

# The start with a slow health and cards ends well under the old limit and prints every line from the snapshot.
t_fast() {
  local out t0 sec
  fixture fast
  export CONVEYOR_FOREMAN_ASK="case \$CONVEYOR_CMD in snapshot) jq -cn '$SNAP' ;; *) sleep 30 ;; esac" # sleep: the slow health and cards reads
  t0=$SECONDS
  out=$(cd "$M" && bash "$SRC/foreman.sh" live) || fail "the live summary failed: $out"
  sec=$((SECONDS - t0))
  [ "$sec" -lt 5 ] || fail "the live summary took $sec s: it asked for health or cards, not only the snapshot: $out"
  grep -qxF 'Conveyor alpha (snapshot as of 2026-11-21T12:00:00Z): loop running, state running' <<<"$out" \
    || fail "the first line does not give the loop, state and the snapshot's time: $out"
  # The landed card (c6) is off the belt for in flight, as the cards read left it out.
  grep -qxF 'alpha in flight: #5 build, Main is red (abc1234) fix' <<<"$out" || fail "in flight is not the open cards of the snapshot's belt: $out"
  grep -qxF 'alpha blocked: #7 since 2026-11-21T10:00:00Z: the build failed' <<<"$out" || fail "the blocked card is missing: $out"
  grep -qxF "alpha waiting on the owner's yes: #8 since 2026-11-21T11:00:00Z" <<<"$out" || fail "the card waiting on the owner's yes is missing: $out"
  ! grep -q unavailable <<<"$out" || fail "a line says unavailable: $out"
}
# A snapshot read that fails, times out (exit 124, as timeout ends it) or is not JSON still prints its "unavailable" line.
t_unavailable() {
  local out
  fixture unavailable
  export CONVEYOR_FOREMAN_ASK='exit 3'
  out=$(cd "$M" && bash "$SRC/foreman.sh" live) || fail "the live summary failed: $out"
  grep -qxF 'Conveyor alpha: unavailable: exit 3' <<<"$out" || fail "a failed snapshot read has no unavailable line: $out"
  export CONVEYOR_FOREMAN_ASK='exit 124'
  out=$(cd "$M" && bash "$SRC/foreman.sh" live) || fail "the live summary failed: $out"
  grep -qxF 'Conveyor alpha: unavailable: no answer in time' <<<"$out" || fail "a timed-out snapshot read does not say no answer in time: $out"
  export CONVEYOR_FOREMAN_ASK='echo not json'
  out=$(cd "$M" && bash "$SRC/foreman.sh" live) || fail "the live summary failed: $out"
  grep -q '^Conveyor alpha: unavailable' <<<"$out" || fail "a snapshot that is not JSON has no unavailable line: $out"
  ! grep -q 'in flight' <<<"$out" || fail "a snapshot that is not JSON still printed values: $out"
}

cases=(fast unavailable)
SEL=${CONVEYOR_SHELL_TEST_CASE:-${cases[*]}}; SEL=${SEL//,/ }
for c in $SEL; do case " ${cases[*]} " in *" $c "*) ;; *) echo "unknown case $c" >&2; exit 2 ;; esac; done
read -ra cases <<<"$SEL"
for c in "${cases[@]}"; do (t_"$c" && : > "$B/$c.passed") > "$B/$c.out" 2>&1 & done
wait
. "$SRC/casesreport.sh"
casesreport "$B" live- "${cases[@]}" || exit 1
echo "ok [live]"
