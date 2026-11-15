#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the CPU budget's note in a whole card run, for files under it and for a card with a fix session
# (testrun.sh slowtests()). Their own file: with the budget's other cases (budget.test.sh) the file was over the test
# step's CPU budget for one file. The helpers (budgetsetup, budgetcmd, reviews, slowof, landedone) are budget.test.sh's.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Bug caught: the budget judged clock time, which on a busy machine measures the load, not the file. A card adds a file
# that sleeps 10 s with little CPU (0.1 CPU s) and one that took 6 s of clock time under load but 2 CPU s: neither is
# over the 8 CPU s budget, so no finding and one review; the test line holds both times of each file the card added.
t_budgetunder() {
  budgetsetup; echo 'echo two >> a.txt; echo 10 0.1 > s.test; echo 6 2 > l.test' > "$STUB/build"
  loop run --only 7 1 > /dev/null 2>&1 || fail "run exited non-zero"
  [ "$(reviews 7)" = "GO " ] || fail "a file under the CPU budget, over it in clock time, went to the review: $(reviews 7)"
  [ "$(slowof 7)" = null ] || fail "a file under the CPU budget is on the test line: $(slowof 7)"
  [ "$(st 'select(.step == "test" and .issue == 7) | .timed | tojson' | head -n 1)" = '[{"file":"l.test","sec":6,"cpu":2},{"file":"s.test","sec":10,"cpu":0.1}]' ] \
    || fail "the test line does not hold the clock and CPU seconds of each file the card added: $(st 'select(.step == "test") | .timed | tojson')"
  [ -z "$(jq -Rn -f "$SRC/jq/check.jq" < "$ST/cards.jsonl")" ] || fail "the record check refuses a line"
  landedone 7 || fail "the card did not land"
}

# Bug caught: a run after a fix session, which does not run again the files that passed, lost the time the runs before
# it took of them (tests() deleted <worktree>.times), so a 9 CPU s file the card added that passed while f.test failed
# landed with no note of it. f.test fails twice (the run and its run again) until the fix session; s.test passes in the
# first run, and the runs after it keep its pass and do not run it again.
t_budgetfix() {
  setup "[$(issue 7 2026-01-01)]"; for i in 1 2 3 4; do echo "$GO" > "$STUB/review.$i"; done
  echo 'echo two >> a.txt; echo 5 9 > s.test; [ ! -e "$STUB/built" ] || touch "$STUB/fixed"; touch "$STUB/built"' > "$STUB/build"
  cat > "$STUB/test-cmd" <<'EOF'
L=$CONVEYOR_TEST_LOG/r.log; echo x >> "$STUB/runs"
if [ -f s.test ] && ! grep -qxF "pass	s.test" "${CONVEYOR_TEST_RERUN:-/dev/null}"; then
  wc -l < "$STUB/runs" >> "$STUB/ran"; printf '== s.test\n-- ok s.test\nTESTRUN sec\ts.test\t%s\t%s\n' $(tail -n 1 s.test) >> "$L"
fi
echo '== f.test' >> "$L"
if [ -e "$STUB/fixed" ]; then echo 'ok c'; echo '-- ok f.test' >> "$L"; else echo 'FAIL [c]: wrong'; echo '-- FAIL f.test' >> "$L"; exit 1; fi
EOF
  loop run --only 7 1 > /dev/null 2>&1 || fail "run exited non-zero"
  # Runs 1 and 2 are the first and its run again, 3 the run after the fix of f.test, which keeps s.test's pass.
  [ "$(tr '\n' ' ' < "$STUB/ran")" = "1 " ] || fail "s.test did not run in the first run alone: $(tr '\n' ' ' < "$STUB/ran")"
  [ "$(st 'select(.step == "test") | .slow | tojson' | sed -n 2p)" = '[{"file":"s.test","sec":5,"cpu":9,"budget":8,"changed":true}]' ] \
    || fail "the run after the fix of f.test does not record s.test's time: $(st 'select(.step == "test") | .slow | tojson' | tr '\n' ' ')"
  [ "$(st 'select(.step == "test" or .step == "fix") | "\(.step) \(.result)"' | tr '\n' ,)" = "test fail,fix ok,test pass," ] \
    || fail "f.test did not fail and pass after a fix, or the slow file sent the card round again: $(st 'select(.step == "test" or .step == "fix") | "\(.step) \(.result)"' | tr '\n' ,)"
  [ "$(reviews 7)" = "GO GO " ] || fail "the slow file went to a review: $(reviews 7)"
  landedone 7 || fail "the card did not land after its fix"
}
