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
# a stop that ended the group would end this case before its checks.
t_relstop() {
  local O RUN out
  runsetup 'sleep 300 & echo $! > "$STUB/sleeper"; wait' # sleep: a stand-in suite process, which only the stop ends
  out=$(loop release-run 1.1.0 2>&1) || fail "release-run did not start the run: $out"
  wait_until '[ -s "$STUB/sleeper" ]' || fail "the suite did not start: $(cat "$T/$CASE/cards/release/run.log" 2>&1)"
  out=$(loop release-run stop 2>&1) || fail "the stop failed: $out"
  ! kill -0 "$(cat "$STUB/sleeper")" 2>/dev/null || fail "the suite's process still runs after the stop"
  jq -e '.state == "stopped" and .ended != null' "$RUN" > /dev/null || fail "the record does not say stopped: $(cat "$RUN")"
  out=$(loop release-run stop 2>&1); [ $? = 2 ] && grep -q 'no release run is under way' <<<"$out" || fail "a stop with no run under way was not refused: $out"
  # Bug: a run ended from outside before its record said so (killed, the machine restarted) shows as running for ever,
  # on the Board and in /units.
  jq '.state = "running" | .ended = null' "$RUN" > "$RUN.new" && mv "$RUN.new" "$RUN" || fail "the record could not be changed"
  relsnap "a record left running with no run behind it is not shown stopped, with when" '.state == "stopped" and .ended != null'
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
