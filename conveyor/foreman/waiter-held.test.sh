#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# The Foreman's waiter that listens during a turn (waiter.sh --held) on watchers that each put a wake.
# Bug caught (R210): the held waiter told a watcher that put a wake from one that died by the count of pending wakes.
# Two watchers that each put a wake, then exit one after the other (b a second after a, while the waiter pauses
# before it starts a again): a's exit took both wakes, so b's saw no new one and was counted as a death. Four such
# rounds in an hour set b down with a WATCHER DOWN wake, though it never died. Each exit is now told by the watcher's
# own exit status (0 once it put a wake).
# Bug caught on a bash before 5.3: b, gone in that pause, left the job table as the waiter started a's sleep or a, so
# `wait -n` never named it and b was never started again (the next round finds one of the two not started). The waiter now takes
# every watcher whose process is gone, not only the one `wait -n` names.
# The waiter and its watchers run as real processes and are waited for: what is under test is how the waiter reads
# the exits of watchers it runs itself, which no direct call can give.
set -uo pipefail
SRC=$(cd "$(dirname "$0")" && pwd -P)
. "$SRC/../tests/wait.sh"
T=$(mktemp -d); trap 'kill "$SP" 2>/dev/null; rm -rf "$T"' EXIT
unset CONVEYOR_FOREMAN_ASK CONVEYOR_FOREMAN_LAUNCH CONVEYOR_MAIN CLAUDE_PROJECT_DIR CONVEYOR_FOREMAN_DOWN CONVEYOR_FOREMAN_END CONVEYOR_FOREMAN_STOP
fail() { echo "FAIL [waiter-held]: $*" >&2; exit 1; }
export XDG_CONFIG_HOME=$T/config XDG_DATA_HOME=$T/data HOME=$T/home CONVEYOR_FOREMAN=1 CONVEYOR_FOREMAN_DIR=$T/fd CONVEYOR_FOREMAN_LOOK=1
FD=$CONVEYOR_FOREMAN_DIR
mkdir -p "$XDG_CONFIG_HOME" "$HOME" "$FD" || fail "the fixture was not made"
sleep 600 & SP=$! # sleep: the stand-in for the session's process, ended with the test
export CONVEYOR_FOREMAN_SESSION_PID=$SP
# hold <condition>: the text of a stand-in's wait for as long as <condition> holds, with a check every 0.1 s. A stand-in
# that the test never lets go ends at the ceiling of the tests' wait (WAIT_CEILING, 120 s: ../tests/wait.sh) times the
# run's load factor: with no ceiling it ran on until a limit outside the test ended it.
HOLD=$(awk -v c="${WAIT_CEILING:-120}" -v f="${CONVEYOR_LOAD_FACTOR:-1}" 'BEGIN { x = c * f; print (x == int(x)) ? x : int(x) + 1 }')
hold() { echo "i=0; while $1; do [ \$((i += 1)) -le $((HOLD * 10)) ] || exit 1; sleep 0.1; done"; }
# Stand-in watcher <name>: notes its start, waits for $T/go, puts one wake, then waits for $T/out.<name> and exits 0.
w() { echo "n=$1; echo \$\$ >> $T/starts; $(hold "[ ! -e $T/go ]"); . $SRC/lib.sh && echo \"Alert: \$n\" | pending_put && echo \$\$ >> $T/put; $(hold "[ ! -e $T/out.\$n ]"); echo \$\$ >> $T/exited"; } # the watcher's poll
n() { cat "$T/$1" 2>/dev/null | wc -l | tr -d ' '; } # <file>: its lines
echo '{}' | CONVEYOR_FOREMAN_WATCHERS="$(w a)"$'\n'"$(w b)" bash "$SRC/waiter.sh" --check > /dev/null 2>&1
for r in 1 2 3 4; do
  wait_until "[ \"\$(n starts)\" = $((2 * r)) ]" || fail "round $r: the two watchers were not both started again ($(n starts) starts): $(cat "$FD/waiter.log")"
  : > "$T/go"; wait_until "[ \"\$(n put)\" = $((2 * r)) ]" || fail "round $r: the two watchers did not both put their wake"
  rm -f "$T/go"; : > "$T/out.a"; wait_until "[ \"\$(n exited)\" = $((2 * r - 1)) ]" || fail "round $r: watcher a did not exit"
  sleep 1; : > "$T/out.b"; wait_until "[ \"\$(n exited)\" = $((2 * r)) ]" || fail "round $r: watcher b did not exit" # sleep: b exits while the waiter pauses after a's exit
  rm -f "$T/out.a" "$T/out.b"
done
# Both are started again after the fourth round: neither was counted as dead, so none is down.
WAIT_CEILING=30 wait_until "[ \"\$(n starts)\" = 10 ]" || fail "after four rounds of two watchers that each put a wake and exited one after the other, one was not started again ($(n starts) starts): $(cat "$FD/waiter.log")"
! grep -rqs 'WATCHER DOWN' "$FD/pending" || fail "two watchers that each put a wake were set down: $(cat "$FD"/pending/*.wake)"
echo "ok [waiter-held]"
