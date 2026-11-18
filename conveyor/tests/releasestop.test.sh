#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: a run of the Board's Release that ends early: stopped (`conveyor.sh release-run stop`), or refused
# when main moved while its suite ran. Their fixture is releaseboard.test.sh's runsetup (release.test.sh's cutsetup);
# relsnap is releaserun.test.sh's.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bug: Stop leaves the run going, or ends more than that run's processes: the run shares this case's process group, so
# a stop that ended the group would end this case before its checks. Bug: Stop returned while the run's release-prep
# still held the release lock as it ended (its EXIT trap), unseen by the stop: its bash shows no mark, and it leaves the
# tree of the run's pid once that pid has ended. A release-prep started then was refused ("already running"), and the
# snapshot showed the stopped run as running. The suite's stand-in for it: a process of the run with no mark, out of
# the run's tree, holding the lock it inherited until the case frees it ($STUB/free), once the stop waits for the lock.
# A stand-in that let go of the lock after a fixed time made the case flaky: the stop's own reap takes 5 to 10 s, so
# a stop that returned without waiting for the lock often passed. Bug (E1): a release-prep that took the lock first
# wrote its own record while the stop waited, and the stop then marked that new run stopped; a second stop refused the
# live run. The case writes such a record while the stop waits (the record that it says stopped is relstopgroup's).
t_relstop() {
  local O RUN out lock sp
  runsetup '( env -u CONVEYOR_RELEASE_RUN timeout 60 bash -c '\''until [ -e "$1" ]; do sleep 0.1; done'\'' _ "$STUB/free" & ); sleep 300 & echo $! > "$STUB/sleeper"; wait' # sleep: stand-in suite processes, which only the stop ends
  lock=$T/$CASE/cards/release/lock
  out=$(loop release-run 1.1.0 2>&1) || fail "release-run did not start the run: $out"
  wait_until '[ -s "$STUB/sleeper" ]' || fail "the suite did not start: $(cat "$T/$CASE/cards/release/run.log" 2>&1)"
  ( loop release-run stop > "$STUB/stop.out" 2>&1; echo $? > "$STUB/stop.rc" ) & sp=$!
  # The stop ends, or waits for the lock (a flock in the stop's own process tree): only then is the stand-in let go.
  wait_until "[ -s '$STUB/stop.rc' ] || under $sp flock" \
    || fail "the stop neither ended nor waited for the release lock: $(cat "$STUB/stop.out")"
  ! { [ -s "$STUB/stop.rc" ] && ! flock -n "$lock" true; } || fail "the stop returned while a process of the run still held the release lock"
  jq -c --argjson p "$(cat "$STUB/sleeper")" '.pid = $p | .since = "2099-01-01T00:00:00Z"' "$RUN" > "$RUN.new" && mv "$RUN.new" "$RUN" \
    || fail "the next run's record could not be written"
  touch "$STUB/free"
  wait_until "[ -s '$STUB/stop.rc' ]" || fail "the stop did not end once the release lock was free"
  [ "$(cat "$STUB/stop.rc")" = 0 ] || fail "the stop failed: $(cat "$STUB/stop.out")"
  flock -n "$lock" true || fail "the release lock is held after the stop"
  ! kill -0 "$(cat "$STUB/sleeper")" 2>/dev/null || fail "the suite's process still runs after the stop"
  jq -e '.state == "running" and .ended == null and .since == "2099-01-01T00:00:00Z"' "$RUN" > /dev/null || fail "the stop marked the next run's record stopped: $(cat "$RUN")"
  out=$(loop release-run stop 2>&1); [ $? = 2 ] && grep -q 'no release run is under way' <<<"$out" || fail "a stop with no run under way was not refused: $out"
  # Bug: a run ended from outside before its record said so (killed, the machine restarted) shows as running for ever,
  # on the Board and in /units.
  jq '.state = "running" | .ended = null' "$RUN" > "$RUN.new" && mv "$RUN.new" "$RUN" || fail "the record could not be changed"
  relsnap "a record left running with no run behind it is not shown stopped, with when" '.state == "stopped" and .ended != null'
}
# Bug (E1): a stop whose wait for the release lock timed out wrote the record without the lock, so it could write its
# stale copy over the result that the lock's holder (the run's own end, or the next run) wrote at the same time. The
# stand-in of relstop holds the lock past the stop's wait: the stop fails and leaves the record as it is.
t_relstopheld() {
  local O RUN out
  runsetup '( env -u CONVEYOR_RELEASE_RUN timeout 60 bash -c '\''until [ -e "$1" ]; do sleep 0.1; done'\'' _ "$STUB/free" & ); sleep 300 & echo $! > "$STUB/sleeper"; wait' # sleep: stand-in suite processes, which only the stop ends
  out=$(loop release-run 1.1.0 2>&1) || fail "release-run did not start the run: $out"
  wait_until '[ -s "$STUB/sleeper" ]' || fail "the suite did not start: $(cat "$T/$CASE/cards/release/run.log" 2>&1)"
  out=$(loop release-run stop 2>&1); [ $? = 1 ] && grep -q 'still holds' <<<"$out" || { touch "$STUB/free"; fail "a stop that could not take the release lock did not fail: $out"; }
  touch "$STUB/free"
  jq -e '.state == "running" and .ended == null' "$RUN" > /dev/null || fail "the stop wrote the record without the release lock: $(cat "$RUN")"
}
# The suite of relstopgroup and relendleft (a runsetup command), on its first run: a process left out from under the
# run, as a suite's own timeout leaves one: a process group of its own whose parent has ended, holding the descriptors
# it inherited (the release lock's too). Its pid is in $STUB/left. The suite then waits (<wait>: sleep 300) or ends.
RELLEFT='[ -e "$STUB/left" ] || { ( timeout 300 sleep 300 & echo $! > "$STUB/left" ); ' # sleep: the left process, which the run's end must end
# Bug (#335): Stop ended the tree of the run's pid alone, so the suite's process in a group of its own ran on, kept the
# release lock, and the next release-prep was refused ("already running") until it was killed by hand.
t_relstopgroup() {
  local O RUN out
  runsetup "$RELLEFT sleep 300; }" # sleep: the suite runs until the case ends the run
  out=$(loop release-run prep 1.1.0 2>&1) || fail "release-run did not start the run: $out"
  wait_until '[ -s "$STUB/left" ]' || fail "the suite did not start: $(cat "$T/$CASE/cards/release/run.log" 2>&1)"
  out=$(loop release-run stop 2>&1) || fail "the stop failed: $out"
  ! kill -0 "$(cat "$STUB/left")" 2>/dev/null || fail "the suite's process in a group of its own still runs after the stop"
  jq -e '.state == "stopped" and .ended != null' "$RUN" > /dev/null || fail "the record does not say stopped: $(cat "$RUN")"
  out=$(loop release-run prep 1.1.0 2>&1) || fail "the next release-prep did not start at once after the stop: $out"
  relwait "the next release-prep did not pass" '.state == "passed"'
}
# Bug (#335): a run whose pid was killed (KILL, which runs no trap) left its release-prep and the suite's process in a
# group of its own running, holding the lock.
t_relkilled() {
  local O RUN out
  runsetup "$RELLEFT sleep 300; }" # sleep: the suite runs until the case ends the run
  out=$(loop release-run prep 1.1.0 2>&1) || fail "release-run did not start the run: $out"
  wait_until '[ -s "$STUB/left" ]' || fail "the suite did not start: $(cat "$T/$CASE/cards/release/run.log" 2>&1)"
  kill -KILL "$(jq .pid "$RUN")" || fail "the run's pid could not be killed"
  wait_until "! kill -0 $(cat "$STUB/left") 2>/dev/null && flock -n '$T/$CASE/cards/release/lock' true" \
    || fail "the suite's process in a group of its own still runs, or the lock is held, after the run's pid was killed"
  out=$(loop release-run prep 1.1.0 2>&1) || fail "the next release-prep did not start once the killed run's processes ended: $out"
  relwait "the next release-prep did not pass" '.state == "passed"'
}
# Bug (#335): a run that ended on its own left the suite's process in a group of its own running, holding the lock.
t_relendleft() {
  local O RUN out p
  runsetup "$RELLEFT }"
  out=$(loop release-run prep 1.1.0 2>&1) || fail "release-run did not start the run: $out"
  relwait "the run did not end" '.ended != null'
  p=$(jq .pid "$RUN")
  wait_until "! kill -0 $p 2>/dev/null" || fail "the run's process did not end"
  ! kill -0 "$(cat "$STUB/left")" 2>/dev/null || fail "the suite's process in a group of its own still runs after the run ended"
  out=$(loop release-run prep 1.1.0 2>&1) || fail "the next release-prep did not start once the run ended: $out"
  relwait "the next release-prep did not end" ".pid != $p and .ended != null"
}
# Bug: a card that lands and is pushed while the Board's release-prep runs its suite moves main, and release then runs
# the suite again and releases the new main, with no second press by the owner.
t_relboardmoved() {
  local O RUN out
  runsetup 'git -C "$R" commit -q --allow-empty -m "landed meanwhile" && git -C "$R" push -q origin main'
  out=$(loop release-run 1.1.0 2>&1) || fail "release-run did not start the run: $out"
  relwait "the run did not end" '.step == "release" and .ended != null'
  jq -e --arg o "$O" '.state == "refused" and .moved == true and .sha == $o and any(.reasons[]; test("moved while the suite ran"))' "$RUN" > /dev/null \
    || fail "release did not refuse the moved main, with the moved reason: $(cat "$RUN") $(cat "$T/$CASE/cards/release/run.log")"
  [ -z "$(git -C "$T/$CASE/origin" tag -l v1.1.0)" ] && ! grep -q '^release' "$STUB/gh-calls" && [ "$(wc -l < "$STUB/runs")" = 1 ] \
    || fail "the moved main was tested again or released: $(cat "$STUB/gh-calls")"
}
