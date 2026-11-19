#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: Run full test suite reruns only the files that failed or changed since the whole-suite run on the
# nearest ancestor and reuses its passes, and release-prep counts its green run on the same commit (issue 44). Their fixture is releasereuse.test.sh's rrsetup; ftended is
# fulltest.test.sh's.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# rrfull: B, the commit of what the case changed (not pushed); Run full test suite runs on it and ends. Sets B and got.
rrfull() {
  git -C "$R" commit -qam 'fix: B' || fail "the fixture could not be made"
  B=$(git -C "$R" rev-parse HEAD); rm -f "$STUB/ran"
  loop full-test > "$T/$CASE.b" 2>&1 || fail "full-test did not start on B: $(cat "$T/$CASE.b")"
  ftended 2; got=$(sort "$STUB/ran" 2>/dev/null | paste -sd' ' -)
}
# Bug (#44, D1): Run full test suite ran every file again after a red run and its fix, where release-prep reran the
# failed file alone. Here B changes t/f1 alone: only t/f1 runs, and the run is green, naming the run it reused.
# Bug (#44, D3): release-prep ran the whole suite on a commit a green full test run had just passed. Pushed, B takes
# release-prep: it runs no test and posts the pass, naming that green run.
t_fullreusefail() {
  local A B RUN got
  rrsetup full
  rrfull
  [ "$got" = t/f1.test.sh ] || fail "full-test on B ran '$got', not t/f1.test.sh alone: $(cat "$ST/fulltest.jsonl.log")"
  [ "$(ftl 'select(.sha == "'"$B"'") | [.state, .reused.sha, .reused.ran, .reused.kept]')" = "[\"passed\",\"$A\",[\"t/f1.test.sh\"],2]" ] \
    || fail "full-test on B is not green, or does not name the run reused: $(cat "$ST/fulltest.jsonl")"
  git -C "$R" push -q origin main || fail "the fixture could not be made"
  rm -f "$STUB/ran"
  loop release-prep 1.1.0 > "$T/$CASE.p" 2>&1 || fail "release-prep failed on B: $(cat "$T/$CASE.p")"
  [ ! -e "$STUB/ran" ] || fail "release-prep ran tests on a commit a green full test passed: $(cat "$STUB/ran")"
  grep -q "statuses/$B -f state=success -f context=conveyor/release-suite -f description=.*reused the green run of " "$STUB/gh-calls" \
    || fail "no passing status naming the reused run was posted on B: $(cat "$STUB/gh-calls")"
  jq -e --arg b "$B" '.state == "passed" and .reused.sha == $b and .reused.ran == [] and .reused.kept == 3' "$RUN" > /dev/null \
    || fail "the record does not name the green run it reused: $(cat "$RUN")"
}
# Bug (#44, D4): a change to the suite's own command between two full test runs: the passes of the first are no proof,
# so every file runs.
t_fullreusecmd() {
  local A B got
  rrsetup full
  echo '# changed' >> "$R/.conveyor/test-full.sh"
  rrfull
  [ "$got" = "t/f1.test.sh t/f2.test.sh t/f3.test.sh" ] || fail "a change to .conveyor/test-full.sh did not run every file: '$got'"
  [ "$(ftl 'select(.sha == "'"$B"'") | [.state, .reused]')" = '["passed",null]' ] || fail "a whole suite's line says it reused a run: $(cat "$ST/fulltest.jsonl")"
}

# Bug (#710): docs/configuration.md said Push landed and Run full test suite run the whole suite on each click, where
# fulltest.sh reuses a green run on the same commit, reruns failed, changed and test.command-selected files, and runs
# the whole suite after a test setting or a suite command file (not a changed-tests command file) changes.
# t_fullreusefail runs the reuse on the same commit and the rerun of a changed file; t_fullreusecmd runs the whole
# suite after .conveyor/test-full.sh changes; t_relreusepick reruns only the failed file (t/f1) after the
# changed-tests command's file (.conveyor/pick.sh) changes.
# Text check: a doc page has no behaviour to run.
t_fullreusedoc() {
  local d; d=$(tr '\n' ' ' < "$SRC/../docs/configuration.md")
  grep -q 'When the suite passed on the same commit, no test runs' <<<"$d" \
    || fail "docs/configuration.md does not say a suite run on a commit that already passed runs no test"
  grep -q 'and the files that `test.command` picks for those changes' <<<"$d" \
    || fail "docs/configuration.md does not say a suite run also reruns the files test.command picks for the changes"
  grep -qF 'or to a file that its suite commands name (`test.full` and `test.wholeCommands`, not `test.command` or `test.changed`), runs the whole suite' <<<"$d" \
    || fail "docs/configuration.md does not say a change to a suite command file, and not to a changed-tests command file, runs the whole suite"
}
