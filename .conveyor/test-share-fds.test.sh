#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# The share of the temp space (.conveyor/test-share.sh): once share_run has returned, no process it started holds a
# descriptor of its caller's. Bug (#1266): its guard's `sleep 1` ran on after share_run killed the guard, with the
# descriptors the guard inherited, so it held the test slot of the file it ran (an flock its worker holds,
# conveyor/lib/slots.sh) up to 1 s more. A parallel suite's next file waited for that slot, and the two files the
# suite record times longest did not start together.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir "$T/config"; export XDG_CONFIG_HOME=$T/config
# shellcheck source=.conveyor/test-share.sh
. "$HERE/test-share.sh" && share_init "$T" > "$T/why" || { echo "not ok - share_init failed: $(cat "$T/why")"; exit 1; }
: > "$T/slot"
# A worker as the suite's: it holds the slot by an flock on a descriptor that share_run, and all it starts, inherit;
# its command ends as soon as the guard's sleep has started, well inside it. Bug: a command that ended before the
# guard reached its first sleep let share_run kill a guard with no sleep, and a leaked 0.1 s sleep could end before the
# check below, so the old leak passed too. The command is a child of share_run's subshell, as the guard is: it waits
# for a `sleep` of one of its siblings; and the guard's look sleep (a function, which the guard's subshell inherits)
# lasts 3 s, so a sleep that leaked the slot still holds it at the check.
sleep() { if [ "$1" = 0.1 ]; then command sleep 3; else command sleep "$@"; fi; }
guardslept() {
  local me=$BASHPID sr sib _
  sr=$(ps -o ppid= -p "$me"); sr=${sr//[[:space:]]/}
  for _ in $(seq 200); do
    sib=$(pgrep -P "$sr" | grep -vx "$me" | paste -sd, -)
    [ -z "$sib" ] || ! pgrep -x sleep -P "$sib" > /dev/null || return 0
    sleep 0.02
  done
  echo "the guard's sleep did not start in 4 s"; return 1
}
( exec {fd}>>"$T/slot" && flock -n "$fd" && share_run "test-share-fds: guardslept" "$T/tmp" guardslept ) > "$T/out" 2>&1 \
  || { echo "not ok - share_run of guardslept, with the slot held, failed: $(cat "$T/out")"; exit 1; }
# The worker has ended: the slot is free at once, for the next file.
if flock -n "$T/slot" true; then echo "ok - share_run leaves the slot its caller held free as it returns"; exit 0; fi
echo "not ok - a process share_run started still holds the slot its caller held, after share_run of guardslept returned"
exit 1
