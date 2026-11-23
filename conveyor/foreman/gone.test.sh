#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 60
# The Foreman's waiter (waiter.sh) when the install it runs from is removed under it and the project's commit is not
# installed to move to: a fixture project that follows the plugin's main at commit A, its install a link to this
# checkout (as the shim names it), and the waiter started from it, its watcher the real watch-conveyor.sh.
# Bug (#198): a prune removed the install a live waiter ran from; the waiter neither moved nor woke the session, and
# ran on with its Conveyor watcher dead, so two blocked cards woke nothing.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d) || exit 1
wp=''
sleep 600 & export CONVEYOR_FOREMAN_SESSION_PID=$! # sleep: the stand-in for the session's process, ended with the test
trap 'kill $CONVEYOR_FOREMAN_SESSION_PID; [ -z "$wp" ] || kill "$wp" 2>/dev/null; wait 2>/dev/null; rm -rf "$T"' EXIT
fail() { echo "FAIL [gone]: $*" >&2; exit 1; }
A=$(printf 'a%.0s' {1..40}) C=$(printf 'c%.0s' {1..40})
export HOME=$T/home XDG_CONFIG_HOME=$T/config XDG_DATA_HOME=$T/data
V=$XDG_DATA_HOME/conveyor/versions M=$T/alpha FD=$T/foreman CO=$(cd "$SRC/../.." && pwd -P)
mkdir -p "$HOME" "$V" "$FD" "$XDG_CONFIG_HOME/conveyor" && jq -n --arg m "$M" '{records: [{repo: "alpha", main: $m}]}' > "$XDG_CONFIG_HOME/conveyor/host.json" \
  && git init -q "$M" && mkdir -p "$M/.conveyor" && jq -n '{plugin: {follow: "main"}}' > "$M/.conveyor/project.json" \
  && jq -n --arg c "$A" '{commit: $c, taken: [$c]}' > "$M/.git/conveyor-engine.json" || fail "the fixture was not made"
# The project's snapshot: #9 is blocked once $T/blocked is there.
health='{time: "2026-11-11T12:00:00Z", loop: true, gh: true, state: "running", reason: null, stuck: [], pushError: null,
  pushFailingSince: null, waiting: [], blocked: []}'
jq -cn "{health: $health, belt: [{card: \"x\"}], queue: {next: []}}" > "$T/before" \
  && jq -c '.health.blocked = [{card: "c9", issue: 9, since: "2026-11-16T21:17:00Z", reason: "its tests failed"}]' "$T/before" > "$T/after" \
  || fail "the snapshots were not written"
export CONVEYOR_FOREMAN=1 CONVEYOR_FOREMAN_DIR=$FD CONVEYOR_MAIN=$M CONVEYOR_FOREMAN_LOOK=1 \
  CONVEYOR_FOREMAN_ASK="case \$CONVEYOR_CMD in snapshot) if [ -e $T/blocked ]; then cat $T/after; else cat $T/before; fi ;; *) echo '{}' ;; esac; echo \$CONVEYOR_CMD >> $T/calls" \
  CONVEYOR_FOREMAN_WATCHERS="read -r _ c _ < $FD/waiter.pid; exec bash $V/\$c/conveyor/foreman/watch-conveyor.sh"
till() { local _; for _ in $(seq 100); do eval "$1" && return 0; sleep 0.1; done; return 1; } # <condition>, 10 s at most
polls() { cat "$T/calls" 2>/dev/null | grep -cx snapshot; }
gone="WATCHER DOWN: the Conveyor install $V/$A the Foreman's waiter ran from is gone"
# A waiter that listens during a turn (--held, on the lock its starter took) cannot wake the session: it puts one wake
# in pending, stops its watchers and ends, for the next stop to deliver.
ln -s "$CO" "$V/$A" || fail "the install of $A was not made"
echo '{}' | bash "$V/$A/conveyor/foreman/waiter.sh" --held 7>>"$FD/waiter.lock" > /dev/null 2> "$T/err" & wp=$!
till '[ "$(polls)" -ge 1 ]' || fail "the held waiter's watcher did not poll: $(cat "$T/err")"
rm "$V/$A"
till '! kill -0 "$wp" 2>/dev/null' || fail "the held waiter ran on after its install was removed"
wait "$wp"; rc=$?; wp=''
n=$(cat "$FD"/pending/*.wake 2>/dev/null | grep -c "^$gone")
[ "$rc" = 0 ] && [ "$n" = 1 ] && [ "$(find "$FD/pending" -name '*.wake' | wc -l)" = 1 ] \
  || fail "the held waiter did not end with one wake in pending (exit $rc, $n): $(cat "$FD"/pending/*.wake 2>/dev/null)"
[ -z "$(cat "$FD/watchers.pid" 2>/dev/null)" ] || fail "the held waiter's watchers were left running"
rm -f "$FD"/pending/*.wake
# The Stop hook's waiter delivers the wake itself: it exits 2 with it on stderr, once.
ln -s "$CO" "$V/$A" || fail "the install of $A was not made again"
p=$(polls)
echo '{}' | bash "$V/$A/conveyor/foreman/waiter.sh" > /dev/null 2> "$T/err" & wp=$!
till "[ \"\$(polls)\" -gt $p ]" || fail "the waiter's watcher did not poll: $(cat "$T/err")"
rm "$V/$A"
till '! kill -0 "$wp" 2>/dev/null' || fail "the waiter ran on after its install was removed"
wait "$wp"; rc=$?; wp=''
[ "$rc" = 2 ] && [ "$(grep -c "^$gone" "$T/err")" = 1 ] && [ -z "$(find "$FD/pending" -name '*.wake')" ] \
  || fail "the waiter whose install was removed did not wake the session once (exit $rc): $(cat "$T/err")"
# Each waiter listed its Foreman folder, once, in the machine's foremen file, which every prune reads
# (tests/followmain.test.sh t_followprunefar).
[ "$(grep -cxF "$FD" "$XDG_DATA_HOME/conveyor/foremen")" = 1 ] || fail "the foremen file does not list the Foreman folder once: $(cat "$XDG_DATA_HOME/conveyor/foremen" 2>&1)"
# The session's next stop runs through the shim on the project's commit, installed again ($C): #9, blocked since,
# wakes the session, and the install that was gone wakes it no more.
ln -s "$CO" "$V/$C" && jq -n --arg c "$C" '{commit: $c, taken: [$c]}' > "$M/.git/conveyor-engine.json" && touch "$T/blocked" || fail "$C was not installed"
echo '{}' | bash "$V/$C/conveyor/foreman/waiter.sh" > /dev/null 2> "$T/err" & wp=$!
till '! kill -0 "$wp" 2>/dev/null' || fail "no wake came for the blocked #9"
wait "$wp"; rc=$?; wp=''
[ "$rc" = 2 ] && grep -q '#9 is blocked' "$T/err" && ! grep -q '^WATCHER DOWN' "$T/err" \
  || fail "the blocked #9 did not wake the session once the waiter ran again (exit $rc): $(cat "$T/err")"
echo "ok gone"
