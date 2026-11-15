#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the record of a release's suite run, as the snapshot shows it (suites, release), and the Board's
# Release (`conveyor.sh release-run <version> | release-run stop`). Their fixtures are release.test.sh's (relsetup,
# cutsetup).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# relwait <what> <jq test>: waits up to 60 s for the test to hold of $RUN (the release's record), failing with <what>.
relwait() {
  local i
  for ((i = 0; i < 600; i++)); do jq -e "$2" "$RUN" > /dev/null 2>&1 && return; sleep 0.1; done
  fail "$1: $(cat "$RUN" 2>&1)"
}
# relsnap <what> <jq arguments, the test last>: the test holds of the release's entry of the snapshot's suites.
relsnap() {
  local what=$1 s; shift
  s=$(loop snapshot | jq -c '.suites[] | select(.kind == "release")')
  jq -e "$@" <<<"$s" > /dev/null || fail "$what: $s"
}
# Bug: nothing shows a release's suite while it runs (the owner asks the Foreman whether it runs and how far it is), or
# after it ends, with the commit it tested. The stub suite names each case as it ends, as the engine's runner does,
# says so ($STUB/at1, at2), and waits for the case to read the snapshot.
t_relrecord() {
  local O pid
  relsetup 'mkdir -p "$CONVEYOR_TEST_LOG/cases/ok" && : > "$CONVEYOR_TEST_LOG/cases/ok/one" && : > "$STUB/at1"
until [ -e "$STUB/go" ]; do sleep 0.1; done; : > "$CONVEYOR_TEST_LOG/cases/ok/two"; : > "$STUB/at2"
until [ -e "$STUB/go2" ]; do sleep 0.1; done'
  loop release-prep 1.1.0 > "$T/$CASE.prep" 2>&1 & pid=$!
  wait_until '[ -e "$STUB/at1" ]' || fail "the suite did not start: $(cat "$T/$CASE.prep")"
  relsnap "the snapshot does not show the run on $O, 1 case done" --arg o "$O" '.state == "running" and .sha == $o and .version == "1.1.0" and .done == 1 and .ended == null'
  : > "$STUB/go"; wait_until '[ -e "$STUB/at2" ]' || fail "the suite did not go on"
  relsnap "the snapshot's cases done do not rise as the suite runs" '.state == "running" and .done == 2'
  : > "$STUB/go2"; wait "$pid" || fail "release-prep failed: $(cat "$T/$CASE.prep")"
  relsnap "the snapshot does not show the passed run on $O once it ended" --arg o "$O" '.state == "passed" and .sha == $o and .done == 2 and .failed == 0 and .ended != null'
  # Bug: the Release panel cannot say what a release would hold: main's newest tag (the one release-prep fetched), the
  # commits since it, the next minor version and whether main holds its notes.
  loop snapshot | jq -e --arg h "$(git -C "$R" rev-parse HEAD)" '.release | .tag == "v1.0.0" and .count == 3 and .next == "1.1.0" and .notes == true and .head == $h
    and (.commits | map(.subject)) == ["feat: Not pushed yet", "fix: A fix", "feat(engine): A new thing (#5)"]' > /dev/null \
    || fail "the snapshot's release does not show main since v1.0.0: $(loop snapshot | jq -c .release)"
}
# The Board's Release (release-run): cutsetup, with gh keeping each conveyor/release-suite status it is sent, so release
# takes release-prep's pass, and the suite counting its runs in $STUB/runs.
runsetup() {
  cutsetup "echo run >> \"\$STUB/runs\"; $1"
  printf '%s\n' '#!/usr/bin/env bash' 'if [ "$1" = release ] || [[ " $* " == *" -X POST "* ]]; then printf "%s\n" "$*" >> "$STUB/gh-calls"' \
    '[[ " $* " =~ \ state=([a-z]+)\  ]] && printf "[{\"context\":\"conveyor/release-suite\",\"state\":\"%s\"}]\n" "${BASH_REMATCH[1]}" > "$STUB/statuses" || :' \
    'else cat "$STUB/statuses" 2>/dev/null || echo "[]"; fi' > "$STUB/gh"
  RUN=$T/$CASE/cards/release/run.json
}
# Bug: the Board's Release does not run release-prep, then on its pass release (the tag and the GitHub release), or
# runs the suite twice; or the Board's ask waits for the whole run.
t_relboard() {
  local O RUN out
  runsetup true
  out=$(timeout 20 bash -c 'CONVEYOR_MAIN=$1 CONVEYOR_CARDS=$2 bash "$3/conveyor.sh" release-run 1.1.0' _ "$R" "$T/$CASE/cards" "$SRC" 2>&1) || fail "release-run did not start the run and return: $out"
  relwait "the run did not end released" '.step == "release" and .ended != null'
  jq -e --arg o "$O" '.state == "released" and .sha == $o' "$RUN" > /dev/null || fail "the release was not made from the suite's pass on $O: $(cat "$RUN") $(cat "$T/$CASE/cards/release/run.log")"
  [ -n "$(git -C "$T/$CASE/origin" tag -l v1.1.0)" ] && grep -q '^release create v1.1.0 ' "$STUB/gh-calls" || fail "no tag v1.1.0 was pushed, or no GitHub release made: $(cat "$STUB/gh-calls")"
  [ "$(wc -l < "$STUB/runs")" = 1 ] || fail "the suite ran $(wc -l < "$STUB/runs") times, not once"
}
# Bug: a red suite is released, or its record does not name its failed cases. This suite's runner names none, so they
# come from its output.
t_relboardfail() {
  local O RUN out
  runsetup 'echo "FAIL [breaks]: off"; echo "FAIL [flips]: off"; exit 1'
  out=$(loop release-run 1.1.0 2>&1) || fail "release-run did not start the run: $out"
  relwait "the run did not end failed" '.ended != null'
  jq -e '.state == "failed" and .step == "release-prep" and .cases == ["breaks", "flips"] and .failed == 2 and any(.reasons[]; test("the whole suite failed"))' "$RUN" > /dev/null \
    || fail "the record does not hold the failed suite with its failed cases: $(cat "$RUN")"
  [ -z "$(git -C "$R" tag -l v1.1.0)" ] && [ -z "$(git -C "$T/$CASE/origin" tag -l v1.1.0)" ] && ! grep -q '^release' "$STUB/gh-calls" || fail "a red suite was tagged or released"
}
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
# Bug: release tried again after a refusal takes release-prep's pass from the status and runs no suite, but its record
# lost the commit and cases that pass was of.
t_relretry() {
  local O RUN out
  runsetup 'mkdir -p "$CONVEYOR_TEST_LOG/cases/ok" && : > "$CONVEYOR_TEST_LOG/cases/ok/one"'
  out=$(loop release-prep 1.1.0 2>&1) || fail "release-prep failed: $out"
  echo changed >> "$R/docs/releases/1.1.0.md"
  out=$(loop release 1.1.0 2>&1); [ $? = 1 ] || fail "release was not refused with an uncommitted change: $out"
  printf '# 1.1.0\n\n## Fixes\n\n- A fix\n' > "$R/docs/releases/1.1.0.md"
  out=$(loop release 1.1.0 2>&1) || fail "the release tried again was refused: $out"
  jq -e --arg o "$O" '.state == "released" and .sha == $o and .done == 1' "$RUN" > /dev/null || fail "the released record lost the tested commit or its cases: $(cat "$RUN")"
  [ "$(wc -l < "$STUB/runs")" = 1 ] || fail "the suite ran $(wc -l < "$STUB/runs") times, not once"
}
