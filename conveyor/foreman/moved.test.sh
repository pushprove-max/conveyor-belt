#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The Foreman's waiter (waiter.sh) when the project's install moves to a new commit: a fixture project that follows
# the plugin's main at commit A, two installs (A and B, each a link to this checkout, as the shim names them), and the
# waiter started from A's, its watcher the real watch-conveyor.sh of the install the waiter runs from.
# Bug (#36): the waiter and its watchers ran on from versions/A after the install moved to B and A was removed: a
# watcher read files that were gone, and the landings the Foreman awaited never woke it.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d) || exit 1
wp=''
trap '[ -z "$wp" ] || kill "$wp" 2>/dev/null; wait 2>/dev/null; rm -rf "$T"' EXIT
fail() { echo "FAIL [moved]: $*" >&2; exit 1; }
A=$(printf 'a%.0s' {1..40}) B=$(printf 'b%.0s' {1..40})
export HOME=$T/home XDG_CONFIG_HOME=$T/config XDG_DATA_HOME=$T/data
V=$XDG_DATA_HOME/conveyor/versions M=$T/alpha FD=$T/foreman
mkdir -p "$HOME" "$V" "$FD" "$XDG_CONFIG_HOME/conveyor" && jq -n --arg m "$M" '{records: [{repo: "alpha", main: $m}]}' > "$XDG_CONFIG_HOME/conveyor/host.json" && ln -s "$(cd "$SRC/../.." && pwd -P)" "$V/$A" && ln -s "$(cd "$SRC/../.." && pwd -P)" "$V/$B" \
  && git init -q "$M" && mkdir -p "$M/.conveyor" && jq -n '{plugin: {follow: "main"}}' > "$M/.conveyor/project.json" \
  && jq -n --arg c "$A" '{commit: $c, taken: [$c]}' > "$M/.git/conveyor-engine.json" || fail "the fixture was not made"
# The project's snapshot: #7, awaited, is pushed only once the install has moved to B, so only a watcher of the
# waiter that moved can see it land. Each ask is noted in calls once it has answered.
health='{time: "2026-11-11T12:00:00Z", loop: true, gh: true, state: "running", reason: null, stuck: [], pushError: null,
  pushFailingSince: null, waiting: [], blocked: []}'
jq -cn "{health: $health, belt: [{card: \"x\"}], queue: {next: []}}" > "$T/before" \
  && jq -c '.pushedCards = [{card: "c7", issue: 7}]' "$T/before" > "$T/after" || fail "the snapshots were not written"
echo 7 > "$FD/await-alpha.txt"
export CONVEYOR_FOREMAN=1 CONVEYOR_FOREMAN_DIR=$FD CONVEYOR_MAIN=$M CONVEYOR_FOREMAN_LOOK=1 \
  CONVEYOR_FOREMAN_ASK="case \$CONVEYOR_CMD in snapshot) if [ \"\$(jq -r .commit $M/.git/conveyor-engine.json)\" = $B ]; then cat $T/after; else cat $T/before; fi ;; *) echo '{}' ;; esac; echo \$CONVEYOR_CMD >> $T/calls" \
  CONVEYOR_FOREMAN_WATCHERS="echo \$\$ >> $T/watchers; read -r _ c _ < $FD/waiter.pid; exec bash $V/\$c/conveyor/foreman/watch-conveyor.sh"
echo '{}' | bash "$V/$A/conveyor/foreman/waiter.sh" > /dev/null 2> "$T/err" & wp=$!
till() { local _; for _ in $(seq 100); do eval "$1" && return 0; sleep 0.1; done; return 1; } # <condition>, 10 s at most
till 'grep -qx snapshot "$T/calls" 2>/dev/null' || fail "the watcher from A did not poll: $(cat "$T/err")"
read -r _ c _ < "$FD/waiter.pid"; [ "$c" = "$A" ] || fail "waiter.pid does not name the install the waiter runs from, $A: $c"
first=$(head -1 "$T/watchers")
jq -n --arg c "$B" '{commit: $c, taken: [$c]}' > "$M/.git/conveyor-engine.json" || fail "the install was not moved"
# D1: within its check time (CONVEYOR_FOREMAN_LOOK, 1 s here) the watcher from A has exited and the waiter runs from B.
till "! kill -0 $first 2>/dev/null" || fail "the watcher from A still runs after the install moved to B"
till 'read -r _ c _ < "$FD/waiter.pid" && [ "$c" = "$B" ]' || fail "the waiter did not start again from B: $(cat "$FD/waiter.pid")"
# D3: the awaited #7, pushed while the install moved, wakes the Foreman: the watcher from A sleeps out its minute's
# poll, so the wake is the one of the watcher from B.
till '! kill -0 "$wp" 2>/dev/null' || fail "no wake came for #7 once the waiter ran from B"
wait "$wp"; rc=$?; wp=''
[ "$rc" = 2 ] && grep -qxF 'alpha: #7 landed: your step is due' "$T/err" || fail "the landing of #7 did not wake the Foreman (exit $rc): $(cat "$T/err")"
# Bug: the waiter that took a moved one's place began the renew time again, so a hook moved late in its day ran past
# its 86400 s timeout, was ended, and nothing started it again. Started from A with the install at B, it moves at its
# first look (3 s) and renews at its start's 6 s, not the 9 s a renew time begun at the move gives.
t0=${EPOCHREALTIME/[.,]/} # microseconds
echo '{}' | CONVEYOR_FOREMAN_LOOK=3 CONVEYOR_FOREMAN_RENEW=6 bash "$V/$A/conveyor/foreman/waiter.sh" > /dev/null 2> "$T/err" & wp=$!
wait "$wp"; rc=$?; wp=''
took=$(( (${EPOCHREALTIME/[.,]/} - t0) / 100000 ))
read -r _ c _ < "$FD/waiter.pid"
[ "$rc" = 2 ] && grep -q '^Renew: ' "$T/err" && [ "$c" = "$B" ] && [ "$took" -lt 75 ] \
  || fail "the moved waiter did not keep its renew time: exit $rc in $took tenths of a second from $c: $(cat "$T/err")"
echo "ok [moved]"
