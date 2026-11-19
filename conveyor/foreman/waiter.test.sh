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
# As a hook runs it: a session of its own, no terminal. Bug (issue 372): the handoff's set -m printed "child setpgid
# ... Operation not permitted" there on macOS, into the wake, and could leave the held waiter in the stop's group.
(. "$SRC/../lib/portable.sh"; echo '{}' | CONVEYOR_FOREMAN_WATCHERS=$W p_setsid bash "$SRC/waiter.sh" 2> "$T/wake" > /dev/null); rc=$?
[ "$rc" = 2 ] && [ "$(cat "$T/wake")" = 'Alert: one' ] || fail "the stop did not deliver the wake alone (exit $rc): $(cat "$T/wake")"
h=$(wpid); isheld "$h" || fail "no waiter listens after the wake was delivered: waiter.pid names $h"
[ "$(ps -o pgid= -p "$h" | tr -d ' ')" = "$h" ] || fail "the held waiter $h is not its own process group: $(ps -o pgid= -p "$h")"
[ "$(logged "the waiter $h that listens until the next stop is its own process group")" = 1 ] || fail "waiter.log does not say the held waiter's group is its own: $(cat "$FD/waiter.log")"
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

# Issue 361: the session goes on in a new process and the old one ends. Bug: the stop's waiter of the ended process
# held waiter.lock, so the new process's stops started no waiter, and it then relayed the wake of a blocked card to
# the ended process, where no session got it. belt: the real Conveyor watcher (BW) over one project, alpha, whose
# snapshot is $T/snap (blocked <issue>: one blocked card, else none); ended: the session's process SP ends.
belt() {
  M=$T/alpha
  mkdir -p "$XDG_CONFIG_HOME/conveyor" "$M/.conveyor" && git init -q "$M" && echo '{}' > "$M/.conveyor/project.json" || exit 1
  jq -n --arg s "$T/state" --arg m "$M" '{stateDir: $s, records: [{repo: "alpha", main: $m}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
  export CONVEYOR_MAIN=$M CONVEYOR_FOREMAN_ASK="cat $T/snap" CONVEYOR_FOREMAN_NOW=1763208000
  BW="bash $SRC/watch-conveyor.sh"
  blocked
}
blocked() { # [<issue>]
  jq -n --arg i "${1:-}" '{belt: [], queue: {next: [{issue: 99}], waiting: []}, open: {held: []}, suites: [],
    health: {time: "2025-11-15T12:00:00Z", loop: true, gh: true, waiting: [], stuck: [], pushFailingSince: null,
      blocked: [$i | select(. != "") | {card: "c\(.)", issue: tonumber, since: "2025-11-15T11:59:00Z", reason: "tests failed twice"}]}}' > "$T/snap.new" \
    && mv "$T/snap.new" "$T/snap"
}
ended() { kill "$SP"; wait "$SP" 2>/dev/null; }
# paused <waiter>: it waits out its pause between two looks (CONVEYOR_FOREMAN_LOOK=600), past its first check of the
# session's process.
paused() { wait_until "pgrep -P $1 -xf 'sleep 600' > /dev/null" || fail "the waiter $1 never paused between two looks"; } # sleep: no sleep here, the pattern names the waiter's pause
# A second process of the same session, ended with the case.
second() { sleep 600 & SP2=$!; trap 'kill $SP2 2>/dev/null' EXIT; } # sleep: the stand-in for the session's new process

# D1: the session's process ends, and a card is blocked: the watcher finds it, and the stop's waiter ends and frees
# the lock, with nothing delivered and the card not marked reported. The watcher's first read of the snapshot waits
# for the file gate, so its first poll comes after the process ended; with no look of its own until then
# (CONVEYOR_FOREMAN_LOOK=600), the waiter ends only once the watcher has polled.
t_goneblock() {
fixture goneblock; belt
export CONVEYOR_FOREMAN_ASK="touch $T/asked; while [ ! -e $T/gate ]; do sleep 0.1; done; cat $T/snap" # sleep: the gate's poll
echo '{}' | CONVEYOR_FOREMAN_LOOK=600 CONVEYOR_FOREMAN_WATCHERS=$BW bash "$SRC/waiter.sh" 2> "$T/wake" > /dev/null & sw=$!
wait_until "[ -e $T/asked ]" || fail "the watcher never read the snapshot"
ended; blocked 255; touch "$T/gate"
WAIT_CEILING=20 wait_until "! kill -0 $sw 2>/dev/null" || fail "the stop's waiter runs on after the session's process ended"
wait "$sw"; rc=$?
[ "$rc" = 0 ] && [ ! -s "$T/wake" ] || fail "the waiter delivered a wake to the ended process (exit $rc): $(cat "$T/wake")"
tail -n 1 "$FD/conveyor-polls.log" | grep -qF "; no wake: the session's process $SP has ended" \
  || fail "the watcher's poll did not find the blocked card due with the process ended: $(tail -n 1 "$FD/conveyor-polls.log")"
flock -n "$FD/waiter.lock" true || fail "the waiter that ended still holds waiter.lock"
! grep -qF blocked:c255 "$FD/conveyor-reported.txt" || fail "the blocked card is marked reported with no session told"
tail -n 1 "$FD/waiter.log" | grep -qF "ended: the session's process $SP has ended" || fail "the waiter's end does not say why: $(cat "$FD/waiter.log")"
}

# D2: the stop of the session's new process takes over from the waiter of the ended one before that waiter's next
# look (600 s here), and its first wake names the blocked card.
t_takeover() {
fixture takeover; belt
echo '{}' | CONVEYOR_FOREMAN_LOOK=600 CONVEYOR_FOREMAN_WATCHERS=$BW bash "$SRC/waiter.sh" 2> "$T/wake1" > /dev/null & sw=$!
wait_until '[ -s "$FD/conveyor-polls.log" ]' || fail "the watcher made no first poll"
paused "$sw"; ended; blocked 255; second
CONVEYOR_FOREMAN_SESSION_PID=$SP2 stop "$BW"; rc=$?
[ "$rc" = 2 ] && grep -qxF 'Conveyor: alpha: blocked: #255' "$T/wake" || fail "the new process's stop did not wake on the blocked card (exit $rc): $(cat "$T/wake")"
kill -0 "$sw" 2>/dev/null && fail "the waiter of the ended process still runs"
[ ! -s "$T/wake1" ] || fail "the waiter of the ended process delivered: $(cat "$T/wake1")"
[ "$(logged "takes over from the waiter $sw, whose session's process $SP has ended")" = 1 ] || fail "no takeover in the log: $(cat "$FD/waiter.log")"
}

# D3: a wake found after the session's process ended is not delivered: it stays pending, and the next stop (of the
# session's new process) delivers it.
t_undelivered() {
fixture undelivered
echo '{}' | CONVEYOR_FOREMAN_LOOK=600 CONVEYOR_FOREMAN_WATCHERS=$W bash "$SRC/waiter.sh" 2> "$T/wake1" > /dev/null & sw=$!
paused "$sw"; ended; put 'Alert: blocked #9'
WAIT_CEILING=20 wait_until "! kill -0 $sw 2>/dev/null" || fail "the waiter runs on after its watcher found a wake for the ended process"
wait "$sw"; rc=$?
[ "$rc" = 0 ] && [ ! -s "$T/wake1" ] || fail "the wake was delivered to the ended process (exit $rc): $(cat "$T/wake1")"
[ "$(wakes)" = 1 ] || fail "the wake that was not delivered did not stay pending: $(cat "$FD/waiter.log")"
second
CONVEYOR_FOREMAN_SESSION_PID=$SP2 stop; rc=$?
[ "$rc" = 2 ] && [ "$(cat "$T/wake")" = 'Alert: blocked #9' ] || fail "the next stop did not deliver the pending wake (exit $rc): $(cat "$T/wake")"
[ "$(wakes)" = 0 ] || fail "the delivered wake stayed pending"
}

# The same takeover by any other hook of the new process (--check): it starts a waiter that listens.
t_takecheck() {
fixture takecheck
echo '{}' | CONVEYOR_FOREMAN_LOOK=600 CONVEYOR_FOREMAN_WATCHERS=$W bash "$SRC/waiter.sh" > /dev/null 2>&1 & sw=$!
paused "$sw"; ended; second
CONVEYOR_FOREMAN_SESSION_PID=$SP2 check
kill -0 "$sw" 2>/dev/null && fail "the hook did not stop the waiter of the ended process"
isheld "$(wpid)" || fail "the hook started no waiter of its own: $(cat "$FD/waiter.log")"
}

# A waiter of an older engine (a project pinned to it) writes waiter.pid with no session's process: "<pid> <commit>
# <session>". Bug: claim read the session from a fourth field, found none, and stopped the waiter of the session that
# claimed the role again.
t_oldpid() {
fixture oldpid; belt # a claim needs a host file with records
flock "$FD/waiter.lock" sleep 600 & hp=$! # sleep: the stand-in older waiter, which holds the lock
wait_until "! flock -n '$FD/waiter.lock' true"
echo "$hp - s1" > "$FD/waiter.pid"
(. "$SRC/lib.sh" && claim s1) || fail "the claim failed"
kill -0 "$hp" 2>/dev/null || fail "the claim stopped the older waiter of the session that claimed the role again"
kill "$hp"
}

# Issue 592. after <true|false> [<session>]: a stop whose input says whether the stop before it was refused by another
# hook (stop_hook_active), run to its end, 30 s at most (a waiter with nothing to deliver listens on).
after() {
  jq -cn --argjson a "$1" --arg s "${2:-}" '{stop_hook_active: $a} + if $s == "" then {} else {session_id: $s} end' \
    | CONVEYOR_FOREMAN_WATCHERS=$W timeout 30 bash "$SRC/waiter.sh" 2> "$T/wake" > /dev/null
}

# D1: a stop that stop.sh refuses ends no turn, so the wake its waiter relays there is lost with it. Bug: the waiter
# took that wake as delivered, and the blocked card it named stayed unreported. The next stop delivers it, once.
t_refused() {
fixture refused
check; isheld "$(wpid)" || fail "no waiter listens during the turn"
put 'Alert: blocked #7'; wait_until '[ "$(wakes)" = 1 ]' || fail "the wake found during the turn was not kept in pending"
after false; rc=$? # the stop another hook refuses: the wake relayed here reaches no turn
[ "$rc" = 2 ] && [ "$(cat "$T/wake")" = 'Alert: blocked #7' ] || fail "the refused stop's waiter did not relay the wake (exit $rc): $(cat "$T/wake")"
after true; rc=$?
[ "$rc" = 2 ] && [ "$(cat "$T/wake")" = 'Alert: blocked #7' ] || fail "the stop after the refused one did not deliver the wake again (exit $rc): $(cat "$T/wake")"
# Once: the stop of the turn that wake started relays nothing. Its watchers start after its first relay (watchers.pid).
after false & s=$!
wait_until "p=\$(wpid) && ps -o args= -p \"\$p\" | grep -q 'waiter\.sh\$' && [ -s $FD/watchers.pid ]" || fail "the third stop's waiter did not start"
[ ! -s "$T/wake" ] || fail "the wake was delivered twice: $(cat "$T/wake")"
compgen -G "$FD/pending/*.sent-*" > /dev/null && fail "a wake the session got is still kept as sent: $(ls "$FD/pending")"
kill "$(wpid)"; wait "$s"
}

# D1: the refused stop's own waiter listens during the turn the refusal goes on with; a wake it relays then is lost
# too. Bug: the next stop left that waiter running, as if it could wake the session. The next stop takes it over.
t_refusedwait() {
fixture refusedwait
after false & s=$! # the refused stop, with nothing to relay: its waiter listens
wait_until "[ -s $FD/watchers.pid ] && [ \"\$(wpid)\" != '' ] && ps -o args= -p \"\$(wpid)\" | grep -q 'waiter\.sh\$'" || fail "the refused stop's waiter did not start"
n=$(wpid)
after true & s2=$!
WAIT_CEILING=20 wait_until "! kill -0 $n 2>/dev/null" || fail "the stop after the refused one left the refused stop's waiter running"
wait "$s"
[ "$(logged "the stop that follows a refused stop takes over from the waiter $n")" = 1 ] || fail "no takeover in the log: $(cat "$FD/waiter.log")"
wait_until '[ "$(wc -l < "$T/starts")" -ge 2 ]' || fail "the stop after the refused one started no watcher"
put 'Alert: blocked #6'; wait "$s2"; rc=$?
[ "$rc" = 2 ] && [ "$(cat "$T/wake")" = 'Alert: blocked #6' ] || fail "the stop after the refused one did not deliver the wake found in its turn (exit $rc): $(cat "$T/wake")"
}

# D2: a claim stops the waiter. Bug: a wake relayed to the old session was taken as delivered, so the new Foreman
# never got it. The new session's first stop delivers it.
t_claimed() {
fixture claimed; belt # a claim needs a host file with records
(. "$SRC/lib.sh" && claim s1) || fail "the claim by s1 failed"
put 'Alert: blocked #8'
after false s1; rc=$?
[ "$rc" = 2 ] && [ "$(cat "$T/wake")" = 'Alert: blocked #8' ] || fail "s1's stop did not relay the wake (exit $rc): $(cat "$T/wake")"
h=$(wpid); isheld "$h" || fail "no waiter listens after s1's stop"
(. "$SRC/lib.sh" && claim s2) || fail "the claim by s2 failed"
kill -0 "$h" 2>/dev/null && fail "the claim did not stop s1's waiter"
after false s2; rc=$?
[ "$rc" = 2 ] && [ "$(cat "$T/wake")" = 'Alert: blocked #8' ] || fail "the new Foreman's first stop did not deliver the wake (exit $rc): $(cat "$T/wake")"
}

# Issue 594: Claude Code's /restart runs the new program in the same process, which no longer reads the Stop hook it
# ran before. reader: a stop's waiter (SW) whose stderr is a pipe read by RP, which unread ends as the restart does;
# SIGPIPE is ignored, as Claude Code's hooks have it (with it not ignored, the write would kill the waiter).
reader() { # [<session>]
  mkfifo "$T/err" && { cat "$T/err" > /dev/null & RP=$!; } || exit 1
  (trap '' PIPE; jq -cn --arg s "${1:-}" 'if $s == "" then {} else {session_id: $s} end' \
    | CONVEYOR_FOREMAN_WATCHERS=$W bash "$SRC/waiter.sh" 2> "$T/err" > /dev/null) & SW=$!
  wait_until '[ -s "$T/starts" ]' || fail "the stop's waiter started no watcher"
}
restarted() { kill "$RP"; wait "$RP" 2>/dev/null; }

# D1. Bug: the waiter's write of each wake failed and it listened on, holding the lock, so no hook started another,
# and the wakes the poll made never reached the session.
t_noreader() {
fixture noreader; reader; restarted
put 'Alert: blocked #5'
WAIT_CEILING=20 wait_until "! kill -0 $SW 2>/dev/null" || fail "the waiter listens on with a stderr no one reads"
[ "$(wakes)" = 1 ] || fail "the wake it could not deliver did not stay pending: $(cat "$FD/waiter.log")"
[ "$(logged "ended: its hook's stderr takes no wake")" = 1 ] || fail "the waiter's end does not say why: $(cat "$FD/waiter.log")"
check; isheld "$(wpid)" || fail "the next hook did not start a waiter: $(cat "$FD/waiter.log")"
wait_until '[ "$(wc -l < "$T/starts")" -ge 2 ]' || fail "the new waiter started no watcher"
put 'Alert: blocked #6'; wait_until '[ "$(wakes)" = 2 ]' || fail "the wake found after the restart was not kept in pending"
stop; rc=$?
[ "$rc" = 2 ] && [ "$(sort "$T/wake")" = $'Alert: blocked #5\nAlert: blocked #6' ] || fail "the next stop did not deliver both wakes (exit $rc): $(cat "$T/wake")"
}

# D1. Bug: after the restart the first prompt (a hook) and the turn's stop both found the old waiter listening and
# left it, so a wake made after that stop waited in pending for some later hook. The stop takes over from it.
t_stopover() {
fixture stopover; reader; old=$(wpid); restarted
check # the first prompt: a hook cannot tell the old waiter's hook is unread
stop & s=$!
WAIT_CEILING=20 wait_until "! kill -0 $SW 2>/dev/null" || fail "the stop left the waiter of the earlier stop running"
[ "$(logged "the stop takes over from the waiter $old of an earlier stop")" = 1 ] || fail "no takeover in the log: $(cat "$FD/waiter.log")"
wait_until '[ "$(wc -l < "$T/starts")" -ge 2 ]' || fail "the stop started no watcher"
put 'Alert: blocked #5'; wait "$s"; rc=$?
[ "$rc" = 2 ] && [ "$(cat "$T/wake")" = 'Alert: blocked #5' ] || fail "the stop did not deliver the wake found after it (exit $rc): $(cat "$T/wake")"
}

# D2. Bug: the claim in the restarted session left the old waiter, as its session and process were the same.
t_reclaim() {
fixture reclaim; belt # a claim needs a host file with records
(. "$SRC/lib.sh" && claim s1) || fail "the claim by s1 failed"
reader s1; old=$(wpid); restarted
(. "$SRC/lib.sh" && claim s1) || fail "the claim by s1 in the restarted session failed"
WAIT_CEILING=20 wait_until "! kill -0 $old 2>/dev/null" || fail "the claim left the waiter whose hook is gone running" # its lock is freed just before its parent reaps it
h=$(wpid); [ "$h" != "$old" ] && isheld "$h" || fail "the claim started no new waiter: waiter.pid names $h"
}

cases=(handoff restart why downheld downstop goneblock takeover undelivered takecheck oldpid refused refusedwait claimed noreader stopover reclaim)
# The cases CONVEYOR_SHELL_TEST_CASE names (comma-separated), as the runner selects them; all of them with none set.
SEL=${CONVEYOR_SHELL_TEST_CASE:-${cases[*]}}; SEL=${SEL//,/ }
for c in $SEL; do case " ${cases[*]} " in *" $c "*) ;; *) echo "unknown case $c" >&2; exit 2 ;; esac; done
read -ra cases <<<"$SEL"
for c in "${cases[@]}"; do ("t_$c" && : > "$B/$c.passed") > "$B/$c.out" 2>&1 & done
wait
bad=0
for c in "${cases[@]}"; do
  cat "$B/$c.out" >&2
  [ -e "$B/$c.passed" ] || { bad=1; [ -s "$B/$c.out" ] || echo "FAIL [$c]: ended with no word" >&2; }
done
[ "$bad" = 0 ] || exit 1
echo ok
