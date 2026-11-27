#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the times a card's test line records, in a whole card run with a fix session (testlist.sh slowtests()).
# Its own file, so that it runs beside budget.test.sh's cases. The helpers (reviews, landedone) are budget.test.sh's.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bug caught (#344): a passing test line got its times by file (testlist.sh slowrec()) as one jq argument, which Linux refuses over
# 128 KiB ("Argument list too long"), so a run that timed many files landed with no times. The run times s.test and
# 1500 files of long names (about 200 KB of times): the test line holds the times of every one.
# Bug caught (#1543): the same limit, in testlist.sh partran(), which got the run's map of times as one jq argument, and
# slowtests(), which got partran()'s list so: the passing line held no times at all. The run also logs a case of 1500
# other files it times not (about 140 KB of names): the test line names every one as run in part (partial).
t_budgetbigrec() {
  budgetsetup; echo 'echo two >> a.txt; echo 1 1 > s.test' > "$STUB/build"
  echo 'awk '"'"'BEGIN { for (i = 0; i < 1500; i++) printf "TESTRUN sec\tsuite/generated/module/folder/a-long-test-file-name-to-fill-the-record-%05d.test\t1\t1\nTESTRUN case\tsuite/generated/module/folder/a-long-test-file-name-run-in-part-to-fill-the-record-%05d.test\tone\n", i, i }'"'"' >> "$CONVEYOR_TEST_LOG/r.log"' >> "$STUB/test-cmd"
  # loop: the check is on the test line the card records (claim.sh: slowtests(), which calls partran(), then slowrec() into it); a direct call of slowtests() stops before that line.
  loop run --only 7 1 > /dev/null 2>&1 || fail "run exited non-zero"
  [ "$(st 'select(.step == "test" and .issue == 7 and .before == null) | [(.times | length), (.clocks | length), (.partial | length)] | tojson' | head -n 1)" = '[1501,1501,1500]' ] \
    || fail "the passing test line lost the times of a run that timed many files: $(st 'select(.step == "test" and .issue == 7 and .before == null) | [.result, (.times | length?), (.partial | length?), .reason] | tojson')"
}

# Bug caught: a run after a fix session, which does not run again the files that passed, lost the time the runs before
# it took of them (tests() deleted <worktree>.times), so a 9 CPU s file the card added that passed while f.test failed
# landed with no time of it on record. f.test fails twice (the run and its run again) until the fix session; s.test passes in the
# first run, and the runs after it keep its pass and do not run it again. The run after the fix runs f.test but times it
# not, as the runner does a file it is given some cases of (case_times(), lib.sh).
t_budgetfix() {
  budgetfixsetup; echo 'if [ -e "$STUB/built" ]; then touch "$STUB/fixed"; else echo two >> a.txt; echo 5 9 > s.test; fi; touch "$STUB/built"' > "$STUB/build"
  # loop: only a whole card run has a test step, a fix session and the test step after it share the run's list of passes
  loop run --only 7 1 > /dev/null 2>&1 || fail "run exited non-zero"
  # Runs 1 and 2 are the first and its run again, 3 the run after the fix of f.test, which keeps s.test's pass.
  [ "$(tr '\n' ' ' < "$STUB/ran")" = "1 " ] || fail "s.test did not run in the first run alone: $(tr '\n' ' ' < "$STUB/ran")"
  [ "$(st 'select(.step == "test" and .before == null) | [.times, .timed] | tojson' | sed -n 2p)" = '[{"s.test":9,"f.test":1},[{"file":"s.test","sec":5,"cpu":9}]]' ] \
    || fail "the run after the fix of f.test does not record s.test's time: $(st 'select(.step == "test" and .before == null) | [.times, .timed] | tojson' | tr '\n' ' ')"
  # Bug caught (#341): that line did not say s.test's time was the first run's, kept, so the test judge read it as a
  # new pass of s.test, newer than a release-suite failure of it. The first run's own line, which ran it, says none.
  # Bug caught too: f.test, which that run ran with no time of it, was named, so the judge did not count that run.
  [ "$(st 'select(.step == "test" and .before == null) | .carried | tojson' | tr '\n' ' ')" = 'null ["s.test"] ' ] \
    || fail "the run after the fix does not name s.test as carried, not run: $(st 'select(.step == "test" and .before == null) | .carried | tojson' | tr '\n' ' ')"
  [ "$(st 'select((.step == "test" and .before == null) or .step == "fix") | "\(.step) \(.result)"' | tr '\n' ,)" = "test fail,fix ok,test pass," ] \
    || fail "f.test did not fail and pass after a fix, or the slow file sent the card round again: $(st 'select((.step == "test" and .before == null) or .step == "fix") | "\(.step) \(.result)"' | tr '\n' ,)"
  [ "$(reviews 7)" = "GO GO " ] || fail "the slow file went to a review: $(reviews 7)"
  landedone 7 || fail "the card did not land after its fix"
}
# Bug caught (#341): a run after a fix session that failed again said nothing of s.test, which it kept as passed and
# did not run, so the test judge could not tell that the step before it was the one that ran s.test. The card gets
# 3 fix rounds (TESTFIXES, lib/paths.sh; #1695) before it blocks, and each run after one names s.test as carried.
t_budgetfixfail() {
  budgetfixsetup; echo '[ -e "$STUB/built" ] || { echo two >> a.txt; echo 5 9 > s.test; }; touch "$STUB/built"' > "$STUB/build"
  # loop: only a whole card run has a test step fail again after a fix session, with the run's list kept between them
  loop run --only 7 1 > /dev/null 2>&1
  [ "$(st 'select((.step == "test" and .before == null) or .step == "fix") | "\(.step) \(.result)"' | tr '\n' ,)" = "test fail,fix ok,test fail,fix ok,test fail,fix ok,test fail," ] \
    || fail "f.test did not fail before and after each of the 3 fixes: $(st 'select((.step == "test" and .before == null) or .step == "fix") | "\(.step) \(.result)"' | tr '\n' ,)"
  [ "$(st 'select(.step == "test" and .before == null) | .carried | tojson' | tr '\n' ' ')" = 'null ["s.test"] ["s.test"] ["s.test"] ' ] \
    || fail "a failed run after a fix does not name s.test as carried, not run: $(st 'select(.step == "test" and .before == null) | .carried | tojson' | tr '\n' ' ')"
  [ -z "$(jq -Rn -f "$SRC/jq/check.jq" < "$ST/cards.jsonl")" ] || fail "the record check refuses a line"
}
# Card 7 and its test command (budgetfix, budgetfixfail): s.test, which the build writes, passes and is timed unless
# the run's list keeps it as passed; f.test fails, and is timed, until the build touches $STUB/fixed. Both are test
# files (tests.patterns): the build adds s.test, which runs whole and so brings f.test, which main commits and the
# links give it (listcmd(), lib/testrun.sh). The run gives the stub each file alone (CONVEYOR_TEST_FILE) and it reports
# only that one, a run counted ($STUB/runs) at its first file (CONVEYOR_TEST_N): a stub given one file that reports
# others is a run of files it was not given, which watch() (lib/session.sh) stops, and the card is blocked untested
# (#1545). The fix session edits nothing in the worktree: a fix that changes a file runs every file again (filecmd(),
# lib/testrun.sh), so only a run after a fix with no edit keeps s.test's pass.
budgetfixsetup() {
  setup "[$(issue 7 2026-01-01)]"; for i in 1 2 3 4; do echo "$GO" > "$STUB/review.$i"; done
  echo f > "$R/f.test"; git -C "$R" add f.test || fail "main's test file f.test could not be staged"
  tune '.tests.patterns = ["*.test"]'; linkset '{"s.test": ["f.test"]}'
  cat > "$STUB/test-cmd" <<'EOF'
L=$CONVEYOR_TEST_LOG/r.log; [ "${CONVEYOR_TEST_N:-1}" != 1 ] || echo x >> "$STUB/runs"
echo "== $CONVEYOR_TEST_FILE" >> "$L"
if [ "$CONVEYOR_TEST_FILE" = s.test ]; then
  wc -l < "$STUB/runs" >> "$STUB/ran"; printf -- '-- ok s.test\nTESTRUN sec\ts.test\t%s\t%s\n' $(tail -n 1 s.test) >> "$L"
elif [ -e "$STUB/fixed" ]; then echo 'ok c'; echo '-- ok f.test' >> "$L"; else printf 'TESTRUN sec\tf.test\t1\t1\n' >> "$L"; echo 'FAIL [c]: wrong'; echo '-- FAIL f.test' >> "$L"; exit 1; fi
EOF
}
