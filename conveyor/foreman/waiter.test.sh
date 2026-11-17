#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 90
# The Foreman's waiter between two stops (waiter.sh, issue 215). Bugs: the waiter is the Stop hook and exits to
# deliver a wake, so the Foreman had no watcher from each wake until the turn it woke ended; a waiter that died (its
# version folder removed, its hook's timeout) waited for the next Stop, indefinitely with none; and the owner saw it
# as down with no reason, or as down while it was only starting again.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
. "$SRC/../tests/wait.sh"
B=$(mktemp -d); trap 'rm -rf "$B"' EXIT
cd "$B" || exit 1
unset CONVEYOR_FOREMAN_ASK CONVEYOR_FOREMAN_LAUNCH CONVEYOR_MAIN CLAUDE_PROJECT_DIR CONVEYOR_FOREMAN_DOWN CONVEYOR_FOREMAN_END CONVEYOR_FOREMAN_WATCHERS
fail() { echo "FAIL [$CASE]: $*" >&2; exit 1; }
# A Foreman of its own in $B/<case> (T): its folder FD, no session marked (CONVEYOR_FOREMAN=1, as the launcher's), and
# a stand-in for the session's process (SP, CONVEYOR_FOREMAN_SESSION_PID), ended with the case so its waiters end.
# The stand-in watcher (W) notes its start in starts; when a file go appears it puts the text in it as one wake and
# exits, as a real watcher does.
fixture() { # <case>
  CASE=$1 T=$B/$1
  export XDG_CONFIG_HOME=$T/config XDG_DATA_HOME=$T/data HOME=$T/home CONVEYOR_FOREMAN=1 CONVEYOR_FOREMAN_DIR=$T/fd CONVEYOR_FOREMAN_LOOK=1
  FD=$CONVEYOR_FOREMAN_DIR
  mkdir -p "$XDG_CONFIG_HOME" "$HOME" "$FD" || exit 1
  sleep 600 & SP=$! # sleep: the stand-in for the session's process, ended with the case
  export CONVEYOR_FOREMAN_SESSION_PID=$SP
  trap 'kill $SP 2>/dev/null' EXIT
  W="echo \$\$ >> $T/starts; while [ ! -e $T/go ]; do sleep 0.1; done; mv $T/go $T/took.\$\$ && . $SRC/lib.sh && pending_put < $T/took.\$\$" # sleep: the stand-in watcher's poll
}
put() { printf '%s\n' "$1" > "$T/go.new" && mv "$T/go.new" "$T/go"; } # <text>: the stand-in watcher's next find
stop() { echo '{}' | CONVEYOR_FOREMAN_WATCHERS=${1:-$W} bash "$SRC/waiter.sh" 2> "$T/wake" > /dev/null; } # [<watchers>]: a stop, the Stop hook to its end
check() { echo '{}' | CONVEYOR_FOREMAN_WATCHERS=${1:-$W} bash "$SRC/waiter.sh" --check > /dev/null 2>&1; } # [<watchers>]: any other hook
wpid() { local p; read -r p _ < "$FD/waiter.pid" && printf '%s' "$p"; }
# isheld <pid>: that process is a waiter that listens. waiter.pid names it before its exec into waiter.sh --held, so it
# is waited for.
isheld() { WAIT_CEILING=20 wait_until "ps -o args= -p '$1' 2>/dev/null | grep -q 'waiter\.sh --held'" 2>/dev/null; }
state() { (. "$SRC/lib.sh" && waiter_state); }
wakes() { find "$FD/pending" -name '*.wake' 2>/dev/null | wc -l; }
logged() { grep -c -- "$1" "$FD/waiter.log" 2>/dev/null; } # <text>: how many lines of waiter.log hold it
aged() { touch -t 200001010000 "$FD/waiter.log"; } # the last line written long ago

# D1: a waiter that delivered a wake listens again while the turn it woke runs: what it finds then stays pending and
# reaches the session once that turn ends (the next stop), each wake once.
t_handoff() {
fixture handoff
put 'Alert: one'
stop; rc=$?
[ "$rc" = 2 ] && [ "$(cat "$T/wake")" = 'Alert: one' ] || fail "the stop did not deliver the wake (exit $rc): $(cat "$T/wake")"
h=$(wpid); isheld "$h" || fail "no waiter listens after the wake was delivered: waiter.pid names $h"
[ "$(state)" = listening ] || fail "the state is not listening while a waiter listens: $(state)"
wait_until '[ "$(wc -l < "$T/starts")" -ge 2 ]' || fail "the waiter that listens during the turn started no watcher"
put 'Alert: two'
wait_until '[ "$(wakes)" = 1 ]' || fail "what was found during the turn was not kept in pending"
wait_until '[ "$(wc -l < "$T/starts")" -ge 3 ]' || fail "the watcher that found something during the turn was not started again"
put 'Alert: three'
wait_until '[ "$(wakes)" = 2 ]' || fail "the second find of the turn was not kept in pending"
kill -0 "$h" 2>/dev/null || fail "the waiter that listens during the turn ended with wakes pending"
# The turn ends: its stop takes over and delivers both, once.
stop; rc=$?
[ "$rc" = 2 ] && [ "$(cat "$T/wake")" = $'Alert: two\nAlert: three' ] || fail "the stop at the end of the turn did not deliver what the turn found, once (exit $rc): $(cat "$T/wake")"
kill -0 "$h" 2>/dev/null && fail "the waiter that listened during the turn still runs after the stop took over"
[ "$(wakes)" = 0 ] || fail "a delivered wake stayed pending: $(cat "$FD"/pending/*.wake)"
isheld "$(wpid)" || fail "no waiter listens after the second delivery"
}

# D2: a waiter killed during a turn is started again by the next hook of the session (waiter.sh --check, as
# PostToolUse and UserPromptSubmit run it); hooks at once start one waiter only (waiter.lock), and a hook while one
# runs starts nothing, and the watchers the killed waiter left running are stopped first. D3: a waiter killed with no
# time to write is shown as starting again for a minute from its death, not from its start, then down.
t_restart() {
fixture restart
echo '{}' | CONVEYOR_FOREMAN_WATCHERS=$W bash "$SRC/waiter.sh" > /dev/null 2>&1 & sw=$!
wait_until '[ -s "$T/starts" ] && [ -s "$FD/watchers.pid" ] && [ "$(wpid)" = "$sw" ]' || fail "the stop's waiter did not start"
aged # it has listened for over a minute: its start line is old
kill -KILL "$sw"; wait "$sw" 2>/dev/null
old=$(head -n 1 "$T/starts"); kill -0 -- "-$old" 2>/dev/null || fail "the killed waiter's watcher did not run on, so the case proves nothing"
[ "$(state)" = 'starting again' ] || fail "a waiter killed just now is shown as down from its old start line: $(state)"
aged; [[ $(state) == 'down: it was killed with no time to say why'* ]] || fail "a waiter killed long ago is not shown as down: $(state)"
cs=(); for _ in 1 2 3 4 5; do check & cs+=($!); done; wait "${cs[@]}"
[ "$(logged 'found no waiter running')" = 1 ] || fail "hooks at once did not start exactly one waiter: $(cat "$FD/waiter.log")"
h=$(wpid); isheld "$h" || fail "no hook started the waiter again: waiter.pid names $h"
kill -0 -- "-$old" 2>/dev/null && fail "the watcher the killed waiter left running still runs beside the new waiter's"
wait_until '[ "$(wc -l < "$T/starts")" = 2 ]' || fail "the waiter started again ran no watcher"
check
[ "$(logged 'found no waiter running')" = 1 ] && [ "$(wpid)" = "$h" ] || fail "a hook while a waiter runs started another: $(cat "$FD/waiter.log")"
[ "$(state)" = listening ] || fail "the state is not listening once the waiter started again: $(state)"
}

# D2: a waiter that ends with no hook to start it again leaves a line in its log saying why; the state is starting
# again for a minute, then down with that reason. Here the session's process ends, which ends a waiter that listens.
t_why() {
fixture why
check; h=$(wpid); isheld "$h" || fail "the hook started no waiter"
kill "$SP"
wait_until "! kill -0 $h 2>/dev/null" || fail "the waiter still listens after the session's process ended"
tail -n 1 "$FD/waiter.log" | grep -q "ended: the session's process $SP has ended" || fail "the waiter's end left no reason in its log: $(cat "$FD/waiter.log")"
[ "$(state)" = 'starting again' ] || fail "a waiter that ended just now is not shown as starting again: $(state)"
aged; [ "$(state)" = "down: the session's process $SP has ended" ] || fail "the waiter down for over a minute does not say why: $(state)"
}

# The WATCHER DOWN rule (a watcher that exits with nothing 4 times in an hour is not started again until the next
# stop) holds in a waiter that listens during a turn: it is kept as a wake for that turn's end.
t_downheld() {
fixture downheld
check "echo \$\$ >> $T/starts"$'\n'"echo \$\$ >> $T/long; sleep 600" # sleep: a watcher that finds nothing
h=$(wpid)
wait_until '[ "$(logged "is down until the next stop")" = 1 ]' || fail "a watcher that died 4 times was not set down: $(cat "$FD/waiter.log")"
[ "$(wc -l < "$T/starts")" = 4 ] && kill -0 "$h" 2>/dev/null || fail "the down watcher started $(wc -l < "$T/starts") times, or the waiter ended"
stop "echo \$\$ >> $T/long; sleep 600"; rc=$? # sleep: a watcher that finds nothing
[ "$rc" = 2 ] && grep -q '^WATCHER DOWN: ' "$T/wake" || fail "the stop did not deliver the WATCHER DOWN of the turn (exit $rc): $(cat "$T/wake")"
}

# The same rule in the stop's waiter: it wakes the session, and the waiter that listens next leaves that watcher out.
t_downstop() {
fixture downstop
stop "echo \$\$ >> $T/starts"$'\n'"echo \$\$ >> $T/long; sleep 600"; rc=$? # sleep: a watcher that finds nothing
[ "$rc" = 2 ] && grep -q '^WATCHER DOWN: ' "$T/wake" || fail "a watcher that died 4 times woke nothing (exit $rc): $(cat "$T/wake")"
h=$(wpid); isheld "$h" || fail "no waiter listens after the WATCHER DOWN wake"
# Its watchers are all started once its own pause between two looks runs.
wait_until "[ \"\$(wc -l < $T/long)\" = 2 ] && pgrep -P $h -xf 'sleep 1' > /dev/null" || fail "the waiter that listens did not start its other watcher" # sleep: no sleep here, the pattern names the waiter's pause
[ "$(wc -l < "$T/starts")" = 4 ] || fail "the watcher set down was started again before the next stop: $(wc -l < "$T/starts") starts"
}

cases=(handoff restart why downheld downstop)
for c in "${cases[@]}"; do ("t_$c" && : > "$B/$c.passed") > "$B/$c.out" 2>&1 & done
wait
bad=0
for c in "${cases[@]}"; do
  cat "$B/$c.out" >&2
  [ -e "$B/$c.passed" ] || { bad=1; [ -s "$B/$c.out" ] || echo "FAIL [$c]: ended with no word" >&2; }
done
[ "$bad" = 0 ] || exit 1
echo ok
