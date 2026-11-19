#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the Board's Release (`conveyor.sh release-run [prep] <version>`) runs release-prep, then on its pass
# release, once; its Run suite releases nothing; a red suite is not released. Their fixture is runsetup, below
# (release.test.sh's cutsetup); releasestop.test.sh, releaseagain.test.sh and releasereuse.test.sh (with fullreuse.test.sh) use
# it too.
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
# Bug (#27): the Board's Run suite (`release-run prep <version>`) also makes the tag and the GitHub release when the
# suite passes, with no Release press by the owner.
t_relprep() {
  local O RUN out
  runsetup true
  out=$(loop release-run prep 1.1.0 2>&1) || fail "release-run prep did not start the run: $out"
  relwait "the run did not end" '.ended != null'
  sleep 1 # sleep: no record is the outcome under test, so no condition can end the wait; a release started after the pass would write its record within this
  jq -e --arg o "$O" '.state == "passed" and .step == "release-prep" and .sha == $o' "$RUN" > /dev/null || fail "release-prep did not pass alone on $O: $(cat "$RUN") $(cat "$T/$CASE/cards/release/run.log")"
  [ -z "$(git -C "$T/$CASE/origin" tag -l v1.1.0)" ] && ! grep -q '^release' "$STUB/gh-calls" || fail "Run suite released v1.1.0: $(cat "$STUB/gh-calls")"
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
