#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: release-prep and Push landed each count the other's green run, or a green Run full test suite, on the
# same commit, and run no test (issue 44). Their fixture is releasereuse.test.sh's rrsetup and rrprep; ftended is
# fulltest.test.sh's.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bug (#44, D3): release-prep ran the whole suite on a commit a green full test run had just passed. It runs no test
# and posts the pass, naming the run it took.
t_relreusefull() {
  local A B RUN
  rrsetup
  git -C "$R" commit -qam 'fix: B' && git -C "$R" push -q origin main || fail "the fixture could not be made"
  B=$(git -C "$R" rev-parse HEAD)
  loop full-test > /dev/null 2>&1 || fail "full-test did not start on B"; ftended 1
  [ "$(ftl .state)" = '"passed"' ] || fail "full-test on B did not pass: $(cat "$ST/fulltest.jsonl" "$ST/fulltest.jsonl.log")"
  rm -f "$STUB/ran"
  loop release-prep 1.1.0 > "$T/$CASE.b" 2>&1 || fail "release-prep failed on B: $(cat "$T/$CASE.b")"
  [ ! -e "$STUB/ran" ] || fail "release-prep ran tests on a commit a green full test passed: $(cat "$STUB/ran")"
  grep -q "statuses/$B -f state=success -f context=conveyor/release-suite -f description=.*reused the green run of " "$STUB/gh-calls" \
    || fail "no passing status naming the reused run was posted on B: $(cat "$STUB/gh-calls")"
  jq -e --arg b "$B" '.state == "passed" and .reused.sha == $b and .reused.ran == [] and .reused.kept == 3' "$RUN" > /dev/null \
    || fail "the record does not name the green run it reused: $(cat "$RUN")"
}
# Bug (#44, D2): Push landed ran the whole suite on a commit release-prep had just passed. It runs no test and pushes.
# B is made an unpushed landing: origin is put back on A and a card's landed line names B.
t_fullreusepush() {
  local A B RUN
  rrsetup
  rrprep
  git -C "$T/$CASE/origin" update-ref refs/heads/main "$A" && git -C "$R" update-ref "refs/remotes/origin/main" "$A" \
    && rm -f "$ST/pushed" && landed 7 | jq -c --arg b "$B" '.sha = $b' >> "$ST/cards.jsonl" || fail "the fixture could not be made"
  rm -f "$STUB/ran"
  loop full-test push > "$T/$CASE.p" 2>&1 || fail "push landed did not start: $(cat "$T/$CASE.p")"; ftended 1
  [ ! -e "$STUB/ran" ] || fail "Push landed ran tests on a commit release-prep passed: $(cat "$STUB/ran")"
  [ "$(git -C "$T/$CASE/origin" rev-parse refs/heads/main)" = "$B" ] \
    && [ "$(ftl '[.state, .pushed.ok, .reused.sha, .reused.ran]')" = "[\"passed\",true,\"$B\",[]]" ] \
    || fail "Push landed did not push B on release-prep's pass: $(cat "$ST/fulltest.jsonl" "$ST/fulltest.jsonl.log")"
}
