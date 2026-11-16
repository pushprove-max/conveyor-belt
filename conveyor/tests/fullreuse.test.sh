#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: Run full test suite reruns only the files that failed or changed since the whole-suite run on the
# nearest ancestor and reuses its passes (issue 44). Their fixture is releasereuse.test.sh's rrsetup; ftended is
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
t_fullreusefail() {
  local A B got
  rrsetup full
  rrfull
  [ "$got" = t/f1.test.sh ] || fail "full-test on B ran '$got', not t/f1.test.sh alone: $(cat "$ST/fulltest.jsonl.log")"
  [ "$(ftl 'select(.sha == "'"$B"'") | [.state, .reused.sha, .reused.ran, .reused.kept]')" = "[\"passed\",\"$A\",[\"t/f1.test.sh\"],2]" ] \
    || fail "full-test on B is not green, or does not name the run reused: $(cat "$ST/fulltest.jsonl")"
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
