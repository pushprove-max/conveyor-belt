#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: a main-red fix card whose failures are all main's waits for main to change only when one of them is a
# case of its own entry or one no other entry holds, or its run stopped before some files ran (cardland.sh
# cardfailed(), redelse()).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# cardfailed() for main-red fix card cA (issue 0, no branch), its run failing only <case>, which fails on main too
# (verdicts() stubbed to say so), its run's testfails() naming <notRun> (default none) as not run. The main-red record
# holds entry A (case a.test: one, and b.test: two and c.test: three, which cA's own run found on entry A's commit:
# by cA; no other entry holds c.test: three) and entry B
# (case b.test: two, card cB, whose own run failed a.test: one, which joined it). Each step around the route is
# stubbed; the wait for main (mainwaited() <worktree> <main's commit> <case>...) only says it ran, with the cases it
# waits on, and settle() after it says main changed. Prints go, rc
# and repaired, through fx_in's run.out.
redcycle() { # <case> [<notRun json>]
  # shellcheck disable=SC2034 # FXWT is read by fx_in, a fix card's worktree; this case has none
  local FXWT=$T/$CASE/none
  setup '[]'
  printf '%s' "${2:-[]}" > "$T/$CASE/notrun"
  # shellcheck disable=SC2016 # expanded by fx_in's eval
  fx_in 'c=cA n=0 br="" wt=$T/$CASE/cA rc=1 own="" sec=1 mainsec=0 sprompt="" issue="" tmain="" repaired="" go=""
    jq -cn "{reds: [{sha: \"1111\", cases: [{case: \"a.test: one\", by: \"c1\"}, {case: \"b.test: two\", by: \"cA\"}, {case: \"c.test: three\", by: \"cA\"}], card: \"cA\"}, {sha: \"2222\", cases: [{case: \"b.test: two\", by: \"c2\"}, {case: \"a.test: one\", by: \"cB\"}], card: \"cB\"}]}" > "$MAINRED"
    depsmissing() { :; }; voidrun() { return 1; }; testfails() { jq -c "{files: [], notRun: .}" "$T/$CASE/notrun"; }; record() { :; }; failline() { :; }; testrulespass() { :; }
    verdicts() { jq -cn --arg c "'"$1"'" "{mainRun: {sha: \"2222\"}, verdicts: [{case: \$c, verdict: \"main\"}]}"; }
    locked() { :; }; began() { :; }; unmate() { :; }; redbrief() { :; }; settle() { return 0; }; mainwaited() { echo "waited for main on ${*:3}"; }
    cardfailed || :; echo "go=$go rc=$rc repaired=$repaired"'
}

# Bug it catches: fix card cA failed only b.test: two, entry B's case, and waited for main; cB, entry B's fix card,
# failed only a.test: one, cA's case, and waited too. Each waited for the other to land, and the belt stood still. A
# fix card whose failures are all other entries' cases makes main no worse: it goes on as passed, and does not wait.
# Also catches: b.test: two joined entry A when cA's own run found it on entry A's commit; read as entry A's own case,
# it held cA waiting all the same.
t_redcycle() {
  redcycle 'b.test: two'
  ! grep -q '^waited for main' "$T/$CASE/run.out" || fail "fix card cA, failing only b.test: two (entry B's case, which fails on main), waited for main: $(tr '\n' '|' < "$T/$CASE/run.out")"
  grep -qx 'go= rc=0 repaired=every case it still fails fails on main too, and each is a case of another entry, none a case it fixes (b.test: two): it does not wait for main; their own fix cards fix them' "$T/$CASE/run.out" \
    || fail "fix card cA, failing only b.test: two (entry B's case), did not go on as passed with its reason: $(tr '\n' '|' < "$T/$CASE/run.out")"
}

# Bug it catches: a fix card that still fails a case of its own entry goes on as passed, and lands with its own case
# not fixed. It waits for main, as before, and is tested again once main changed.
t_redcycleown() {
  redcycle 'a.test: one'
  grep -qx 'waited for main on a.test: one' "$T/$CASE/run.out" \
    || fail "fix card cA, failing a.test: one (its own entry's case, which fails on main), did not wait for main: $(tr '\n' '|' < "$T/$CASE/run.out")"
  grep -qx 'go=again rc=0 repaired=' "$T/$CASE/run.out" \
    || fail "fix card cA, failing its own case a.test: one, was not tested again after the wait, or went on as passed: $(tr '\n' '|' < "$T/$CASE/run.out")"
}

# Bug it catches: a run that stopped at its first failure (rules.failfast) left c.test.sh not run, so no verdict names
# its cases; the card went on as passed and landed with a failure its test step never reached. It waits for main.
t_redcyclenotrun() {
  redcycle 'b.test: two' '["c.test.sh"]'
  grep -qx 'waited for main on b.test: two' "$T/$CASE/run.out" \
    || fail "fix card cA, failing only b.test: two with c.test.sh not run, did not wait for main: $(tr '\n' '|' < "$T/$CASE/run.out")"
  grep -qx 'go=again rc=0 repaired=' "$T/$CASE/run.out" \
    || fail "fix card cA, with c.test.sh not run, was not tested again after the wait, or went on as passed: $(tr '\n' '|' < "$T/$CASE/run.out")"
}

# Bug it catches: c.test: three, which cA's own run found failing on entry A's commit (by cA), was read as another
# entry's case though no other entry holds it; cA went on as passed and landed with it unfixed, and no fix card was
# left to fix it. It waits for main.
t_redcycleonly() {
  redcycle 'c.test: three'
  grep -qx 'waited for main on c.test: three' "$T/$CASE/run.out" \
    || fail "fix card cA, failing c.test: three (found by cA on its own entry's commit, held by no other entry), did not wait for main: $(tr '\n' '|' < "$T/$CASE/run.out")"
  grep -qx 'go=again rc=0 repaired=' "$T/$CASE/run.out" \
    || fail "fix card cA, failing c.test: three (held by no other entry), was not tested again after the wait, or went on as passed: $(tr '\n' '|' < "$T/$CASE/run.out")"
}
