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
unset CONVEYOR_FOREMAN_ASK CONVEYOR_FOREMAN_LAUNCH CONVEYOR_MAIN CLAUDE_PROJECT_DIR CONVEYOR_FOREMAN_DOWN CONVEYOR_FOREMAN_END CONVEYOR_FOREMAN_STOP CONVEYOR_FOREMAN_WATCHERS
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
# The watcher that dies exits 1: a held waiter takes an exit 0 for a wake put (R210), as a real watcher exits 0 only so.
check "echo \$\$ >> $T/starts; exit 1"$'\n'"echo \$\$ >> $T/long; sleep 600" # sleep: a watcher that finds nothing
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
  jq -cn --argjson a "$1" --arg s "${2:-}" --arg t "$T/transcript.jsonl" '{stop_hook_active: $a, transcript_path: $t} + if $s == "" then {} else {session_id: $s} end' \
    | CONVEYOR_FOREMAN_WATCHERS=$W timeout 30 bash "$SRC/waiter.sh" 2> "$T/wake" > /dev/null
}
# said <uuid> <text>: the session's reply, which the next stop reads (its stop_key).
said() { jq -cn --arg u "$1" --arg x "$2" '{type: "assistant", uuid: $u, message: {content: [{type: "text", text: $x}]}}' >> "$T/transcript.jsonl"; }
# stopwait: the waiter of the stop running in the background has started its watchers, so it relayed nothing at once.
stopwait() { wait_until "p=\$(wpid) && ps -o args= -p \"\$p\" | grep -q 'waiter\.sh\$' && [ -s $FD/watchers.pid ]"; }

# D2: a stop that stop.sh refuses ends no turn, so the wake its waiter relays there is lost with it. Bug: the waiter
# took that wake as delivered, and the blocked card it named stayed unreported. The next stop delivers it, once.
t_refused() {
fixture refused
check; isheld "$(wpid)" || fail "no waiter listens during the turn"
put 'Alert: blocked #7'; wait_until '[ "$(wakes)" = 1 ]' || fail "the wake found during the turn was not kept in pending"
jq -cn '{type: "user", uuid: "u1", message: {content: "go"}}' > "$T/transcript.jsonl"; said a1 'I still need to file #7.'
jq -cn --arg t "$T/transcript.jsonl" '{stop_hook_active: false, transcript_path: $t}' | bash "$SRC/stop.sh" reply | grep -q '"block"' \
  || fail "the reply check did not refuse unfinished work (reply: I still need to file #7.)"
after false; rc=$? # the stop the reply check refuses: the wake relayed here reaches no turn
[ "$rc" = 2 ] && [ "$(cat "$T/wake")" = 'Alert: blocked #7' ] || fail "the refused stop's waiter did not relay the wake (exit $rc): $(cat "$T/wake")"
said a2 'Idle'; after true; rc=$?
[ "$rc" = 2 ] && [ "$(cat "$T/wake")" = 'Alert: blocked #7' ] || fail "the stop after the refused one did not deliver the wake again (exit $rc): $(cat "$T/wake")"
# Once: the stop of the turn that wake started (it follows the refusal that delivered it) relays nothing.
said a3 'Idle'; after true & s=$!
stopwait || fail "the third stop's waiter did not listen; it relayed: $(cat "$T/wake")"
[ ! -s "$T/wake" ] || fail "the wake was delivered twice: $(cat "$T/wake")"
compgen -G "$FD/pending/*.sent-*" > /dev/null && fail "a wake the session got is still kept as sent: $(ls "$FD/pending")"
kill "$(wpid)"; wait "$s"
}

# D1 (issue 605): the waiter relays a wake by refusing the stop itself, so the stop of the reply to it always follows
# a refused stop. Bug: that stop took the wake as lost and relayed it again, after every reply, without end. No other
# hook refused the stop it was relayed at: the next stop drops it, and the stop after relays nothing either.
t_delivered() {
fixture delivered
check; put 'Alert: blocked #5'; wait_until '[ "$(wakes)" = 1 ]' || fail "the wake was not kept in pending"
said a1 'Retried #5.'; after false; rc=$?
[ "$rc" = 2 ] && [ "$(cat "$T/wake")" = 'Alert: blocked #5' ] || fail "the stop did not relay the wake (exit $rc): $(cat "$T/wake")"
said a2 'Idle'; after true & s=$!
stopwait || fail "the stop after the relay did not listen; it relayed: $(cat "$T/wake")"
[ ! -s "$T/wake" ] || fail "the stop after the refusal that delivered the wake relayed it again: $(cat "$T/wake")"
[ "$(wakes)" = 0 ] && ! compgen -G "$FD/pending/*.sent-*" > /dev/null || fail "the delivered wake was kept: $(ls "$FD/pending")"
said a3 'Idle'; after true & s2=$!
wait "$s"; stopwait || fail "the stop after did not listen"
[ ! -s "$T/wake" ] || fail "the stop after relayed the wake again: $(cat "$T/wake")"
kill "$(wpid)"; wait "$s2"
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

# R59. Bug: deliver keeps the wake as sent, then the stop stops its watchers and hands off before its exit 2; a session
# whose process ended in that gap never read the wake, and resumed with the same session id (a new process) its next
# stop deleted it as received. A watcher that ignores TERM holds the gap open for stop_all's 5 s.
t_resumed() {
fixture resumed
put 'Alert: blocked #9'
jq -cn '{stop_hook_active: false, session_id: "s1"}' \
  | CONVEYOR_FOREMAN_WATCHERS="$W"$'\n'"trap '' TERM; while :; do sleep 1; done" timeout 30 bash "$SRC/waiter.sh" 2> "$T/wake" > /dev/null & s=$! # sleep: the stubborn watcher's idle loop
wait_until 'compgen -G "$FD/pending/*.sent-*" > /dev/null' || fail "the stop delivered no wake"
kill -0 "$s" 2>/dev/null || fail "the stop exited before the session's process was ended, so the case proves nothing"
kill "$SP"; wait "$s"; rc=$?
[ "$rc" = 2 ] && [ "$(cat "$T/wake")" = 'Alert: blocked #9' ] || fail "the first stop did not relay the wake (exit $rc): $(cat "$T/wake")"
sleep 600 & SP=$! # sleep: the resumed session's process, ended with the case
export CONVEYOR_FOREMAN_SESSION_PID=$SP
after false s1; rc=$?
[ "$rc" = 2 ] && [ "$(cat "$T/wake")" = 'Alert: blocked #9' ] || fail "the resumed session's stop did not put the unread wake back in pending and deliver it (exit $rc, pending: $(ls "$FD/pending")): $(cat "$T/wake")"
}

# R61. Bug: start() names a watcher by its pid before its setsid makes that pid a group; a TERM in that gap found no
# group to stop, the watcher then made its group and ran on, and the waiter's wait on it never ended, holding
# waiter.lock. The setsid on PATH (perl on macOS, as p_execsid runs it) holds that gap open for 3 s.
t_slowsid() {
fixture slowsid
local n=setsid real; [ "$(uname)" != Darwin ] || n=perl
real=$(command -v "$n") && mkdir -p "$T/bin" || fail "no $n to wrap"
printf '#!/bin/sh\ncase " $* " in *" bash -c "*) : > "%s"; sleep 3 ;; esac\nexec "%s" "$@"\n' "$T/forked" "$real" > "$T/bin/$n" && chmod +x "$T/bin/$n" || fail "the slow $n was not made" # sleep: the slow setsid's gap, which the TERM falls in
echo '{}' | PATH=$T/bin:$PATH CONVEYOR_FOREMAN_WATCHERS=$W bash "$SRC/waiter.sh" > /dev/null 2>&1 & s=$!
wait_until '[ -e "$T/forked" ]' || fail "the waiter started no watcher"
kill -TERM "$s"
WAIT_CEILING=6 wait_until "! kill -0 $s 2>/dev/null" || { kill -KILL "$s" "$(cut -d' ' -f1 "$FD/watchers.pid")"; fail "the waiter did not exit within 6 s of a TERM while its watcher's setsid was slow"; }
flock -n "$FD/waiter.lock" true || fail "waiter.lock is still held after the waiter exited"
}

# Issue 1507. Bug: a TERM after start() forks a watcher and before `PID[$1]=$!` found no pid to stop, and stop_all's
# `wait` with no pid waited for that watcher, which runs until stopped: the waiter held waiter.lock. No outside timing
# lands a TERM in that gap, so a DEBUG trap (from BASH_ENV, set -T so it runs in start) sends it there, once.
t_forkterm() {
fixture forkterm
printf '%s\n' 'set -T' "trap '[[ \$BASH_COMMAND == \"PID[\\\$1]=\\\$!\" ]] && mkdir \"$T/termed\" 2>/dev/null && kill -TERM \$\$' DEBUG" > "$T/env.sh" || fail "the BASH_ENV file was not made"
echo '{}' | BASH_ENV=$T/env.sh CONVEYOR_FOREMAN_WATCHERS=$W bash "$SRC/waiter.sh" > /dev/null 2>&1 & s=$!
wait_until '[ -d "$T/termed" ]' || fail "the TERM was not sent between the watcher's fork and its PID entry"
WAIT_CEILING=6 wait_until "! kill -0 $s 2>/dev/null" || { kill -KILL "$s"; pkill -KILL -F "$T/starts" 2>/dev/null; fail "the waiter did not exit within 6 s of a TERM between its watcher's fork and its PID entry: $(cat "$FD/waiter.log")"; }
flock -n "$FD/waiter.lock" true || fail "waiter.lock is still held after the waiter exited"
w=$(cat "$T/starts" 2>/dev/null); [ -z "$w" ] || ! kill -0 "$w" 2>/dev/null || { kill -KILL "$w"; fail "the watcher $w runs on after its waiter stopped"; }
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

# Issue 610: --check runs after every tool call of the Foreman. While a waiter runs and no wake waits, it ends at once:
# exit 0, no output, none of the waiter's files changed. Bug: before it found the waiter running, each call walked up
# its processes with ps to find the session's, which only starting a waiter needs (a ps stand-in notes each run).
t_checkquiet() {
fixture checkquiet
check; h=$(wpid); isheld "$h" || fail "the hook started no waiter"
wait_until '[ -s "$T/starts" ] && [ -s "$FD/watchers.pid" ]' || fail "the waiter started no watcher"
files() { (cd "$FD" && find . -type f | LC_ALL=C sort | while read -r f; do printf '%s %s\n' "$f" "$(cksum < "$f")"; done); }
before=$(files); [ "$(wakes)" = 0 ] || fail "a wake waits, so the case proves nothing"
mkdir -p "$T/ps" && printf '#!/bin/sh\necho "$*" >> %s/ps.calls\nexec %s "$@"\n' "$T" "$(command -v ps)" > "$T/ps/ps" && chmod +x "$T/ps/ps"
out=$(echo '{}' | env -u CONVEYOR_FOREMAN_SESSION_PID PATH="$T/ps:$PATH" CONVEYOR_FOREMAN_WATCHERS="$W" bash "$SRC/waiter.sh" --check 2>&1); rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] || fail "--check with a waiter running did not end quietly (exit $rc): $out"
[ ! -e "$T/ps.calls" ] || fail "--check with a waiter running looked up processes: $(cat "$T/ps.calls")"
[ "$(files)" = "$before" ] || fail "--check with a waiter running changed the waiter's files: $(diff <(echo "$before") <(files))"
[ "$(wpid)" = "$h" ] && kill -0 "$h" || fail "the waiter $h no longer runs after --check"
}

# Issue 1172. begin [<hook input>]: the SessionStart hook (CONVEYOR_WAITER_START=1 waiter.sh) in the background, its stderr in
# $T/wake; its pid in bp. Bug: a session started or resumed with no one typing ran no turn, so no hook started its
# waiter and nothing could wake it, for hours.
# The hook runs as hooks.json runs it, with no argument, so an older engine takes it for a stop, not a usage error.
begin() { echo "${1:-"{}"}" | CONVEYOR_WAITER_START=1 CONVEYOR_FOREMAN_WATCHERS=$W bash "$SRC/waiter.sh" 2> "$T/wake" > /dev/null & bp=$!; }
# up <pid>: waiter.pid names that waiter and its watcher runs.
up() { wait_until "[ \"\$(wpid)\" = $1 ] && [ -s $FD/watchers.pid ]"; }

# The Foreman's session starts with no waiter: its start's waiter listens, and wakes the session (exit 2, the wake on
# stderr), then hands off to a waiter that listens until the next stop.
t_startwake() {
fixture startwake
begin; up "$bp" || fail "the session's start (CONVEYOR_WAITER_START=1 waiter.sh, input {}) started no waiter: $(cat "$FD/waiter.log" 2>/dev/null)"
[ "$(logged "$bp started from a checkout, at the session's start")" = 1 ] || fail "waiter.log has no start line of the waiter $bp of CONVEYOR_WAITER_START=1 waiter.sh: $(cat "$FD/waiter.log")"
put 'Alert: one'
# A poll, as the waiter ends only once its own poll of its watchers finds the wake and its handoff is started; a bare
# wait would hang the case when it never ends, and the bound fails it.
WAIT_CEILING=20 wait_until "! kill -0 $bp 2>/dev/null" || fail "the waiter of CONVEYOR_WAITER_START=1 waiter.sh did not end with a wake pending"
wait "$bp"; rc=$?
[ "$rc" = 2 ] && [ "$(cat "$T/wake")" = 'Alert: one' ] || fail "CONVEYOR_WAITER_START=1 waiter.sh (input {}) did not wake the session with 'Alert: one' (exit $rc): $(cat "$T/wake")"
isheld "$(wpid)" || fail "no waiter listens after CONVEYOR_WAITER_START=1 waiter.sh delivered its wake"
}

# A session that is not the Foreman (another is marked, not the launcher's) gets no waiter, and its hook ends at once
# when the session's start hook beside it (foreman.sh start, the real one) has ended, not at its 10 s bound.
t_startother() {
fixture startother
echo 's1 2026-01-01T00:00:00Z' > "$FD/session"
in='{"session_id":"s2","source":"resume"}'
(echo "$in" | env -u CONVEYOR_FOREMAN CONVEYOR_WAITER_START=1 CONVEYOR_FOREMAN_WATCHERS="$W" bash "$SRC/waiter.sh" > "$T/out" 2>&1; echo $? > "$T/rc") &
echo "$in" | env -u CONVEYOR_FOREMAN bash "$SRC/foreman.sh" start > /dev/null 2>&1
WAIT_CEILING=4 wait_until "[ -s $T/rc ]" || fail "CONVEYOR_WAITER_START=1 waiter.sh (input $in, s1 marked) did not end once foreman.sh start ended"
rc=$(cat "$T/rc"); out=$(cat "$T/out")
[ "$rc" = 0 ] && [ -z "$out" ] || fail "CONVEYOR_WAITER_START=1 waiter.sh (input $in, s1 marked) did not end with 0 (exit $rc): $out"
[ ! -e "$FD/waiter.pid" ] && [ ! -e "$FD/waiter.log" ] && [ ! -e "$T/starts" ] || fail "CONVEYOR_WAITER_START=1 waiter.sh (input $in, s1 marked) started a waiter: $(cat "$FD/waiter.log" 2>/dev/null)"
}

# A start while a waiter of the same session's process runs that can wake it (a stop's): that one runs on, alone.
t_startlive() {
fixture startlive
echo '{}' | CONVEYOR_FOREMAN_WATCHERS=$W bash "$SRC/waiter.sh" > /dev/null 2>&1 & sw=$!
up "$sw" || fail "the stop (waiter.sh, input {}) started no waiter"
out=$(echo '{}' | CONVEYOR_WAITER_START=1 CONVEYOR_FOREMAN_WATCHERS="$W" timeout 15 bash "$SRC/waiter.sh" 2>&1); rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] || fail "CONVEYOR_WAITER_START=1 waiter.sh (input {}) with the stop's waiter $sw running did not end with 0 (exit $rc): $out"
[ "$(wpid)" = "$sw" ] && kill -0 "$sw" || fail "CONVEYOR_WAITER_START=1 waiter.sh (input {}) replaced the stop's waiter $sw: waiter.pid names $(wpid)"
[ "$(logged 'started from')" = 1 ] && [ "$(wc -l < "$T/starts")" = 1 ] || fail "CONVEYOR_WAITER_START=1 waiter.sh (input {}) started a second waiter: $(cat "$FD/waiter.log")"
}

# A start of the session's new process while waiter.lock is held by the waiter of its ended one takes over.
t_startover() {
fixture startover
echo '{}' | CONVEYOR_FOREMAN_LOOK=600 CONVEYOR_FOREMAN_WATCHERS=$W bash "$SRC/waiter.sh" > /dev/null 2>&1 & sw=$!
paused "$sw"; ended; second
CONVEYOR_FOREMAN_SESSION_PID=$SP2 begin
up "$bp" || fail "CONVEYOR_WAITER_START=1 waiter.sh (input {}) of the new process $SP2 started no waiter: $(cat "$FD/waiter.log")"
kill -0 "$sw" 2>/dev/null && fail "CONVEYOR_WAITER_START=1 waiter.sh (input {}) left the waiter $sw of the ended process $SP running"
[ "$(logged "the session's start of the session's process $SP2 takes over from the waiter $sw, whose session's process $SP has ended")" = 1 ] \
  || fail "waiter.log has no takeover by CONVEYOR_WAITER_START=1 waiter.sh (input {}): $(cat "$FD/waiter.log")"
}

# A start while a waiter that listens until the next stop runs (it cannot wake the session) takes over from it, as a
# claim of the session at its start (foreman.sh start) may have started that one.
t_startheld() {
fixture startheld
check; h=$(wpid); isheld "$h" || fail "the hook (waiter.sh --check, input {}) started no waiter"
begin; up "$bp" || fail "CONVEYOR_WAITER_START=1 waiter.sh (input {}) did not take over from the held waiter $h: $(cat "$FD/waiter.log")"
kill -0 "$h" 2>/dev/null && fail "CONVEYOR_WAITER_START=1 waiter.sh (input {}) left the held waiter $h running"
[ "$(logged "the session's start takes over from the waiter $h, which listens until the next stop")" = 1 ] || fail "waiter.log has no takeover by CONVEYOR_WAITER_START=1 waiter.sh (input {}): $(cat "$FD/waiter.log")"
}

# The launcher resumes the Foreman's own session, so the mark names it already, and its start hook (foreman.sh start)
# claims it again, which replaces a waiter of the session with one that cannot wake it. Bug: the hook accepted the
# mark at once, started its waiter before that claim, and the claim then replaced it with a held waiter: no wake.
# The real start hook runs, a second later than the waiter's hook has begun.
t_startclaim() {
fixture startclaim
echo 'new 2026-01-01T00:00:00Z' > "$FD/session"
in='{"session_id":"new","source":"resume"}'
begin "$in"
sleep 1 # sleep: the hook's first polls, while the session's start hook has not run
[ ! -e "$FD/waiter.pid" ] && kill -0 "$bp" || fail "CONVEYOR_WAITER_START=1 waiter.sh (input $in, the mark naming the session) started a waiter or ended before the session's start hook ran: $(cat "$FD/waiter.log" 2>/dev/null)"
echo "$FD-launch" > "$FD/launch"
# claim_ is refused (exit 1) while mine cannot read the records, so the claim needs a host file; without it the start hook
# claimed nothing and the case passed on the mark it wrote itself.
mkdir -p "$XDG_CONFIG_HOME/conveyor" "$T/main" && jq -n --arg m "$T/main" '{records: [{repo: "alpha", main: $m}]}' > "$XDG_CONFIG_HOME/conveyor/host.json" || fail "the host file was not made"
echo "$in" | CONVEYOR_MAIN="$T/main" CONVEYOR_FOREMAN_LAUNCH="$FD-launch" bash "$SRC/foreman.sh" start > /dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -e "$FD/launch" ] && [ "$(read -r s t < "$FD/session"; echo "$s")" = new ] && [ "$(read -r s t < "$FD/session"; echo "$t")" != 2026-01-01T00:00:00Z ] \
  || fail "the launch claim (foreman.sh start, input $in) did not run: exit $rc, launch file $(cat "$FD/launch" 2>/dev/null), mark $(cat "$FD/session")"
up "$bp" || fail "CONVEYOR_WAITER_START=1 waiter.sh (input $in) started no waiter once foreman.sh start ended: $(cat "$FD/waiter.log" 2>/dev/null)"
! ps -o args= -p "$bp" | grep -q 'waiter\.sh --held' && [ "$(logged 'takes over')" = 0 ] || fail "the launch claim (foreman.sh start, input $in) replaced the waiter $bp of waiter.sh: $(cat "$FD/waiter.log")"
flock -n "$FD/claim.lock" true || fail "the waiter of CONVEYOR_WAITER_START=1 waiter.sh (input $in) holds claim.lock"
}

# A resume that gives the Foreman's session a new id, in a session that is not the launcher's (no CONVEYOR_FOREMAN):
# the start hook beside this one (foreman.sh start, adopt_, here its stand-in a second later) adopts the mark and ends,
# and this hook's waiter starts then. Bug: the hook read the mark only at once when CONVEYOR_FOREMAN was not set, so it
# ended before the adoption and the resumed Foreman had no waiter.
t_startadopt() {
fixture startadopt
echo 'old 2026-01-01T00:00:00Z' > "$FD/session"
in='{"session_id":"new","source":"resume"}'
CONVEYOR_FOREMAN='' begin "$in"
sleep 1 # sleep: the hook's first polls, while the mark names the old id
kill -0 "$bp" 2>/dev/null || fail "CONVEYOR_WAITER_START=1 waiter.sh (input $in, no CONVEYOR_FOREMAN) ended before foreman.sh start adopted the mark"
echo 'new 2026-01-01T00:00:01Z' > "$FD/session"
sleep 1 # sleep: the hook sees the mark while the start hook has not ended
[ ! -e "$FD/waiter.pid" ] || fail "CONVEYOR_WAITER_START=1 waiter.sh (input $in) started its waiter before foreman.sh start ended"
echo new > "$FD/started"
up "$bp" || fail "CONVEYOR_WAITER_START=1 waiter.sh (input $in, no CONVEYOR_FOREMAN) started no waiter once foreman.sh start ended: $(cat "$FD/waiter.log" 2>/dev/null)"
}

# Bugs caught: a watcher put a wake for #7, #8 and #9 blocked during a turn, `conveyor.sh retry 7` and `retry 9` ran in
# that turn, and the stop relayed the wake as written: the Foreman acted on #7 and #9 again. #7's retry blocked again,
# for another reason, before the stop: a wake kept while health still listed #7 relayed its old reason. A reminder of
# #10, whose first block carried the note that the findings could not be posted on the issue, was kept when #10's retry
# blocked for the same reason without that note: the old reason was read as the start of the new one. The stop reads
# the record's health first (CONVEYOR_FOREMAN_ASK: #7 blocked since a later time, #8 as the wake says, its line marked
# with the time of an older snapshot, #9 gone, #10 for the reason alone since the time its reminder names, so only its
# reason tells the new block from the old) and relays the wake with #8 alone. pending_fresh's other cases are in
# waiter-fresh.test.sh.
t_retried() {
fixture retried; mkdir -p "$FD/pending" "$XDG_CONFIG_HOME/conveyor" "$T/alpha"
jq -n --arg m "$T/alpha" '{records: [{repo: "alpha", main: $m}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"
printf '%s\n' 'Conveyor: alpha: blocked: #7 #8; still blocked: #9 #10; landed: #3' 'alpha: #7 is blocked since 2026-11-19T09:58:00Z: tests failed' \
  'alpha: #8 is blocked since 2026-11-19T09:59:00Z: review said no (as of 09:59Z)' 'alpha: #9 has been blocked for 2h0m (since 2026-11-19T08:00:00Z): the build failed' \
  'alpha: #10 has been blocked for 30m (since 2026-11-19T09:30:00Z): tests failed [this could not be posted on the issue]' \
  'alpha: #3 landed as abc: your step is due' > "$FD/pending/20261119T100000Z-1-a.wake"
CONVEYOR_FOREMAN_ASK='[ "$CONVEYOR_CMD" = health ] || exit 3; echo "{\"blocked\": [{\"card\": \"c7b\", \"issue\": 7, \"since\": \"2026-11-19T10:05:00Z\", \"reason\": \"the review found a flaw\"},
  {\"card\": \"c8\", \"issue\": 8, \"since\": \"2026-11-19T09:59:00Z\", \"reason\": \"review said no\"},
  {\"card\": \"c10b\", \"issue\": 10, \"since\": \"2026-11-19T09:30:00Z\", \"reason\": \"tests failed\"}]}"' stop; rc=$?
[ "$rc" = 2 ] && [ "$(cat "$T/wake")" = $'Conveyor: alpha: blocked: #8; landed: #3\nalpha: #8 is blocked since 2026-11-19T09:59:00Z: review said no (as of 09:59Z)\nalpha: #3 landed as abc: your step is due' ] \
  || fail "for a wake of #7, #8 and #9 blocked and #10 still blocked for 'tests failed [this could not be posted on the issue]', and health holding #8 as the wake says, #7 blocked again since 10:05 for another reason, #9 not at all and #10 for 'tests failed' alone since 09:30, the stop did not relay the wake with #8 alone (exit $rc): $(cat "$T/wake")"
}

# stale <exit>: a watcher that puts a wake of alpha's #7 blocked, which health (staleask) no longer holds, waits
# until the stop's freshness check takes it out at a poll (it runs on while the waiter drops its wake, as a watcher of
# several projects does), then exits with <exit>.
stale() { echo "echo \$\$ >> $T/starts; . $SRC/lib.sh && printf '%s\n' 'Conveyor: alpha: blocked: #7' 'alpha: #7 is blocked since 2026-11-19T09:58:00Z: tests failed' | pending_put; while compgen -G \"$FD/pending/*-\$\$-*.wake\" > /dev/null; do sleep 0.1; done; exit $1"; } # sleep: a wait for the waiter's poll to take the wake out
staleask() { mkdir -p "$XDG_CONFIG_HOME/conveyor" "$T/alpha"; jq -n --arg m "$T/alpha" '{records: [{repo: "alpha", main: $m}]}' > "$XDG_CONFIG_HOME/conveyor/host.json"; export CONVEYOR_FOREMAN_ASK='[ "$CONVEYOR_CMD" = health ] && echo "{\"blocked\": []}"'; }
# Bug caught (issue 1659): the stop's waiter counted a watcher that put a wake (exit 0) toward WATCHER DOWN when the
# freshness check took that wake out as stale, so a watcher that put 4 stale wakes in an hour was set down as dead;
# and one whose wake a poll took out while it ran on (it found nothing pending at its exit). The case polls the real
# waiter's watcher starts: the count is kept only in the running waiter's memory, and a fifth start is the one outside
# action that shows the exits were not counted.
t_stalestop() {
fixture stalestop; staleask
stop "$(stale 0)" & s=$!
WAIT_CEILING=60 wait_until '[ "$(wc -l < "$T/starts" 2>/dev/null)" -ge 5 ]' || fail "a watcher that put a stale wake 4 times was not started a fifth time ($(wc -l < "$T/starts") starts): $(cat "$T/wake")"
kill -0 "$s" 2>/dev/null && ! grep -q 'WATCHER DOWN' "$T/wake" || fail "a watcher that put a stale wake 4 times raised WATCHER DOWN: $(cat "$T/wake")"
kill "$SP"; wait "$s"
}
# A watcher of the stop's waiter that exits non-zero 4 times in an hour is set down, though the freshness check took
# out its stale wake each time: only an exit 0 tells a wake put.
t_stalefail() {
fixture stalefail; staleask
stop "$(stale 1)"; rc=$?
[ "$rc" = 2 ] && grep -q '^WATCHER DOWN: ' "$T/wake" && [ "$(wc -l < "$T/starts")" = 4 ] || fail "a watcher that put a stale wake and exited 1 4 times was not set down after its fourth start (exit $rc, $(wc -l < "$T/starts") starts): $(cat "$T/wake")"
}

# Bug caught (issue 1659, a review of it): a watcher that put its wake after the stop's poll listed pending, and
# exited before the waiter read its exit, was counted as dead: its stale wake was taken out only at the next poll.
# The race is forced at its weak point: watcher D dies once, and while the waiter sleeps the 5 s before it starts D
# again (after its poll and before it reads R's exit), R puts its stale wake and exits 0; then R dies 3 times, and its
# fifth start runs on. Not counted, the race leaves R 3 deaths, one short of WATCHER DOWN; counted, the third death
# raises it. D must come
# first in the waiter's walk of its watchers (a hash order): a comment is added to its line until it does. The case
# polls the real waiter's starts, as the count is kept only in its memory.
t_stalerace() {
fixture stalerace; staleask
local r d n=0 first
r="echo \$\$ >> $T/starts; n=\$(wc -l < $T/starts); [ \$n -lt 5 ] || exec sleep 600; [ \$n = 1 ] || exit 1; until pgrep -P \$PPID -xf 'sleep 5' > /dev/null; do sleep 0.1; done; . $SRC/lib.sh && printf '%s\n' 'Conveyor: alpha: blocked: #7' 'alpha: #7 is blocked since 2026-11-19T09:58:00Z: tests failed' | pending_put" # sleep: a wait for the waiter's 5 s pause before it starts D again
while :; do
  d="[ -e $T/died ] || { touch $T/died; exit 1; }; sleep 600 # $n" # sleep: a watcher that finds nothing once it died
  first=$(bash -c 'declare -A C=() P=(); C[$1]=1; C[$2]=1; for k in "${!C[@]}"; do P[$k]=1; done; for k in "${!P[@]}"; do printf "%s" "$k"; break; done' _ "$r" "$d")
  [ "$first" = "$d" ] && break; n=$((n + 1))
done
stop "$r"$'\n'"$d" & s=$!
WAIT_CEILING=60 wait_until '[ "$(wc -l < "$T/starts" 2>/dev/null)" -ge 5 ] || ! kill -0 '"$s" || fail "the waiter of watchers R and D ended or did not start R a fifth time ($(wc -l < "$T/starts") starts): $(cat "$T/wake")"
kill -0 "$s" 2>/dev/null && ! grep -q 'WATCHER DOWN' "$T/wake" || fail "a watcher R that put a stale wake after the poll and exited 0, then died 3 times, raised WATCHER DOWN ($(wc -l < "$T/starts") starts): $(cat "$T/wake")"
kill "$SP"; wait "$s"
}

cases=(handoff restart why downheld downstop stalestop stalefail stalerace goneblock takeover undelivered takecheck oldpid refused delivered refusedwait claimed resumed slowsid forkterm noreader stopover reclaim checkquiet startwake startother startlive startover startheld startclaim startadopt retried)
# The cases CONVEYOR_SHELL_TEST_CASE names (comma-separated), as the runner selects them; all of them with none set.
SEL=${CONVEYOR_SHELL_TEST_CASE:-${cases[*]}}; SEL=${SEL//,/ }
for c in $SEL; do case " ${cases[*]} " in *" $c "*) ;; *) echo "unknown case $c" >&2; exit 2 ;; esac; done
read -ra cases <<<"$SEL"
for c in "${cases[@]}"; do ("t_$c" && : > "$B/$c.passed") > "$B/$c.out" 2>&1 & done
wait
bad=0
for c in "${cases[@]}"; do
  cat "$B/$c.out" >&2
  # A passing case prints `ok <case>`, named as its FAIL line names it: the main-red proof reads a case's pass from that line.
  if [ -e "$B/$c.passed" ]; then echo "ok $c"; else bad=1; [ -s "$B/$c.out" ] || echo "FAIL [$c]: ended with no word" >&2; fi
done
[ "$bad" = 0 ] || exit 1
echo ok
