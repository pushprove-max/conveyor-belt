#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: release-prep, Run full test suite and Push landed rerun only the files that failed or changed since the
# whole-suite run on the nearest ancestor and reuse its passes (issue 43), and each counts the others' green run on the same commit
# (issue 44). Their fixture is releaseboard.test.sh's runsetup (release.test.sh's cutsetup); ftended is fulltest.test.sh's.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# rrsetup: runsetup, with the pack's test.full the committed .conveyor/test-full.sh, which runs the tracked t/*.test.sh
# (those CONVEYOR_SUITE_FILES lists, when set), notes each in $STUB/ran and prints its `-- ok|FAIL` line; t/f1 fails,
# t/f2 and t/f3 pass, and the changed-tests command (test.command, $STUB/test-cmd) lists t/f3.test.sh for a change to
# src/s3.sh. A whole release-prep (with `full`: a whole Run full test suite) runs on that commit (A), then t/f1 is made
# to pass, not yet committed.
rrsetup() { # [full]
  runsetup true
  tune '.test.full = "bash .conveyor/test-full.sh"'
  mkdir -p "$R/t" "$R/src" && printf '%s\n' 'fs=$(git ls-files "t/*.test.sh"); [ -z "${CONVEYOR_SUITE_FILES:-}" ] || fs=$(grep -xFf "$CONVEYOR_SUITE_FILES" <<<"$fs")' \
    'echo "TESTRUN files=$(grep -c . <<<"$fs")"; rc=0' \
    'for f in $fs; do echo "$f" >> "$STUB/ran"; if bash "$f"; then echo "-- ok $f"; else echo "-- FAIL $f"; rc=1; fi; done; exit $rc' > "$R/.conveyor/test-full.sh" \
    && echo 'exit 1' > "$R/t/f1.test.sh" && echo 'exit 0' > "$R/t/f2.test.sh" && echo 'exit 0' > "$R/t/f3.test.sh" && echo one > "$R/src/s3.sh" \
    && echo '[ -z "${CONVEYOR_TEST_LIST:-}" ] || git diff --name-only HEAD | sed -n "s|^src/s3[.]sh\$|t/f3.test.sh|p" > "$CONVEYOR_TEST_LIST"' > "$STUB/test-cmd" \
    && git -C "$R" add -f .conveyor/test-full.sh t src && git -C "$R" commit -qm 'the suite' && git -C "$R" push -q origin main || fail "the fixture could not be made"
  A=$(git -C "$R" rev-parse HEAD)
  if [ "${1:-}" = full ]; then
    loop full-test > "$T/$CASE.a" 2>&1 || fail "full-test did not start: $(cat "$T/$CASE.a")"
    ftended 1; [ "$(ftl .state)" = '"failed"' ] || fail "full-test did not fail with t/f1 failing: $(cat "$ST/fulltest.jsonl")"
  else loop release-prep 1.1.0 > "$T/$CASE.a" 2>&1 && fail "release-prep passed with t/f1 failing: $(cat "$T/$CASE.a")"; fi
  # A red full test also runs t/f1 alone (fulljudge()), which this runner runs whole: each file ran, once or more.
  [ "$(sort -u "$STUB/ran" 2>/dev/null | paste -sd' ' -)" = "t/f1.test.sh t/f2.test.sh t/f3.test.sh" ] || fail "the first run did not run every file: $(cat "$STUB/ran" "$T/$CASE.a" 2>&1)"
  rm -f "$STUB/ran"; echo 'exit 0' > "$R/t/f1.test.sh"
}
# rrprep: B, the commit of what the case changed, pushed; release-prep runs on it and passes. Sets B and got (the
# files the suite ran, sorted, on one line).
rrprep() {
  git -C "$R" commit -qam 'fix: B' && git -C "$R" push -q origin main || fail "the fixture could not be made"
  B=$(git -C "$R" rev-parse HEAD)
  loop release-prep 1.1.0 > "$T/$CASE.b" 2>&1 || fail "release-prep failed on B: $(cat "$T/$CASE.b")"
  got=$(sort "$STUB/ran" 2>/dev/null | paste -sd' ' -)
}

# Bug (#43): one failed file made release-prep rerun the whole suite (about 250 files, 43 min) on the fix, though every
# other file passed on the commit before. Here B changes t/f1 alone: only t/f1 runs, a pass is posted on B, the record
# names the run reused and the file rerun, and `release` takes the pass and releases B with no suite run.
t_relreusefail() {
  local A B RUN got
  rrsetup
  rrprep
  [ "$got" = t/f1.test.sh ] || fail "release-prep on B ran '$got', not t/f1.test.sh alone: $(cat "$T/$CASE.b")"
  grep -q "statuses/$B -f state=success -f context=conveyor/release-suite " "$STUB/gh-calls" || fail "no passing status was posted on B: $(cat "$STUB/gh-calls")"
  jq -e --arg a "$A" --arg b "$B" '.state == "passed" and .sha == $b and (.reused | del(.time)) == {sha: $a, ran: ["t/f1.test.sh"], kept: 2}' "$RUN" > /dev/null \
    || fail "the record does not name the run reused and the file rerun: $(cat "$RUN")"
  rm -f "$STUB/ran"
  loop release 1.1.0 > "$T/$CASE.r" 2>&1 || fail "release did not take the pass on B: $(cat "$T/$CASE.r")"
  [ ! -e "$STUB/ran" ] && [ -n "$(git -C "$T/$CASE/origin" tag -l v1.1.0)" ] || fail "release ran the suite again or released nothing: $(cat "$T/$CASE.r")"
}
# Bug (#43): a change to the suite's own command (.conveyor/test-full.sh) can change what every file's ok means, so
# the passes of the run before it are no proof: release-prep runs every file.
t_relreusecmd() {
  local A B RUN got
  rrsetup
  echo '# changed' >> "$R/.conveyor/test-full.sh"
  rrprep
  [ "$got" = "t/f1.test.sh t/f2.test.sh t/f3.test.sh" ] || fail "a change to .conveyor/test-full.sh did not run every file: '$got'"
  jq -e '.reused == null' "$RUN" > /dev/null || fail "a whole suite's record says it reused a run: $(cat "$RUN")"
}
# Bug (#43): reusing the passes of files whose code changed: B changes src/s3.sh, which the changed-tests command maps
# to t/f3, so t/f3 runs beside the failed t/f1.
t_relreusesel() {
  local A B RUN got
  rrsetup
  echo two >> "$R/src/s3.sh"
  rrprep
  [ "$got" = "t/f1.test.sh t/f3.test.sh" ] || fail "a change to src/s3.sh did not run t/f3 beside t/f1: '$got'"
}

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
# Bug (#44, D3): release-prep ran the whole suite on a commit a green full test run had just passed. It runs no test
# and posts the pass, naming the run it took.
t_relreusefull() {
  local A B RUN got
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
  local A B RUN got
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
# Bug (#44 review): the record's newest line on an ancestor was taken, so a release-prep on origin's A after a green
# full test on the unpushed B hid B's pass, and Push landed on B ran every file again. suitebase() takes the line on
# the commit itself, else on the nearest ancestor (C, a child of B, takes B's line over the later A's).
t_suitebasenear() {
  local g=$T/$CASE/g A B C got
  mkdir -p "$g" && git -C "$g" init -q && for c in A B C; do git -C "$g" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m "$c" || fail "the fixture could not be made"; done
  A=$(git -C "$g" rev-parse HEAD~2) B=$(git -C "$g" rev-parse HEAD~1) C=$(git -C "$g" rev-parse HEAD)
  printf '{"sha":"%s","time":"t1","files":{"f":"ok"}}\n{"sha":"%s","time":"t2","files":{"f":"fail"}}\n' "$B" "$A" > "$T/$CASE/suites.jsonl"
  got=$(cd "$g" && export STATE=$T/$CASE/cards.jsonl && . "$SRC/lib/fulltest.sh" && suitebase "$B" | jq -r .sha && suitebase "$C" | jq -r .sha && suitebase "$A" | jq -r .sha)
  got=$(paste -sd' ' <<<"$got")
  [ "$got" = "$B $B $A" ] || fail "suitebase took '$got' for B, C and A, not '$B $B $A'"
}
