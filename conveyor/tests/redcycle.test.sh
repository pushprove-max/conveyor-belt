#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: a main-red fix card whose failures are all main's goes on as passed when each is a case an open other
# entry holds; else (a case of its own entry or one no open other entry holds, or its run left some files not run or
# a file ran out of time) its failure goes to a fix round, and it never waits for main (cardland.sh cardfailed(),
# redelse()).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# cardfailed() for main-red fix card cA (issue 0, no branch), its run failing only <case>, which fails on main too
# (verdicts() stubbed to say so), its run's testfails() {files: []} with the fields of <testfails json> (default
# none) added. <commands> (default none) run in the engine before cardfailed(). The main-red record
# holds entry A (case a.test: one, and b.test: two and c.test: three, which cA's own run found on entry A's commit:
# by cA; no other entry holds c.test: three) and entry B
# (case b.test: two, d.test, a file that failed naming no case, as a push's run names it, card cB, whose own run
# failed a.test: one, which joined it). Each step around the route is
# stubbed; the wait for main (mainwaited() <worktree> <main's commit> <case>...) only says it ran, with the cases it
# waits on, and settle() after it says main changed; the fix session only says it ran. The card is fitted onto main
# already (tmain), so a failure of its own goes to a fix round (testroute()). Prints go, rc and repaired, through fx_in's
# run.out.
redcycle() { # <case> [<testfails json>] [<commands>]
  # shellcheck disable=SC2034 # FXWT is read by fx_in, a fix card's worktree; this case has none
  local FXWT=$T/$CASE/none
  setup '[]'
  printf '%s' "${2:-"{}"}" > "$T/$CASE/tf"
  # shellcheck disable=SC2016 # expanded by fx_in's eval
  fx_in 'c=cA n=0 br="" wt=$T/$CASE/cA rc=1 own="" sec=1 mainsec=0 sprompt="" issue="" tmain=1 repaired="" go="" fixed=0
    jq -cn "{reds: [{sha: \"1111\", cases: [{case: \"a.test: one\", by: \"c1\"}, {case: \"b.test: two\", by: \"cA\"}, {case: \"c.test: three\", by: \"cA\"}], card: \"cA\"}, {sha: \"2222\", cases: [{case: \"b.test: two\", by: \"c2\"}, {case: \"d.test\", by: \"c2\"}, {case: \"a.test: one\", by: \"cB\"}], card: \"cB\"}]}" > "$MAINRED"
    depsmissing() { :; }; voidrun() { return 1; }; testfails() { jq -c "{files: []} + ." "$T/$CASE/tf"; }; record() { :; }; failline() { :; }; testrulespass() { :; }
    verdicts() { jq -cn --arg c "'"$1"'" "{mainRun: {sha: \"2222\"}, verdicts: [{case: \$c, verdict: \"main\"}]}"; }
    locked() { :; }; began() { :; }; unmate() { :; }; redbrief() { :; }; settle() { return 0; }; mainwaited() { echo "waited for main on ${*:3}"; }
    testfixprompt() { :; }; session() { echo "a fix session ran" >&2; }; checked() { :; }
    '"${3:-}"'
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

# The run of redcycle() for fix card cA, <what>, went to a fix round: a fix session ran, and the card neither waited
# for main (only its own landing would end that wait: its own entry holds main red, and no other fix card starts while
# it is open) nor went on as passed.
fixround() { # <what>
  ! grep -q '^waited for main' "$T/$CASE/run.out" || fail "fix card cA, $1, waited for main, which only its own landing would end: $(tr '\n' '|' < "$T/$CASE/run.out")"
  grep -qx 'a fix session ran' "$T/$CASE/run.out" && grep -qx 'go=next rc=1 repaired=' "$T/$CASE/run.out" \
    || fail "fix card cA, $1, did not go to a fix round, or went on as passed: $(tr '\n' '|' < "$T/$CASE/run.out")"
}

# Bug it catches: a fix card that still fails a case of its own entry goes on as passed, and lands with its own case
# not fixed. Also catches: it waited for main, which its own entry holds red, for good.
t_redcycleown() {
  redcycle 'a.test: one'
  fixround "failing a.test: one (its own entry's case, which fails on main)"
}

# Bug it catches: a run that stopped at its first failure (rules.failfast) left c.test.sh not run, so no verdict names
# its cases; the card went on as passed and landed with a failure its test step never reached.
t_redcyclenotrun() {
  redcycle 'b.test: two' '{"notRun": ["c.test.sh"]}'
  fixround 'failing only b.test: two with c.test.sh not run'
}

# Bug it catches: a problem of the host kept c.test.sh from starting (testfails() host, which it leaves out of
# notRun), so no verdict names its cases; the card went on as passed and landed with a selected file that never ran.
t_redcyclehost() {
  redcycle 'b.test: two' '{"host": ["c.test.sh"]}'
  fixround 'failing only b.test: two with c.test.sh not started for a host problem'
}

# Bug it catches: c.test: three, which cA's own run found failing on entry A's commit (by cA), was read as another
# entry's case though no other entry holds it; cA went on as passed and landed with it unfixed, and no fix card was
# left to fix it.
t_redcycleonly() {
  redcycle 'c.test: three'
  fixround "failing c.test: three (found by cA on its own entry's commit, held by no other entry)"
}

# Bug it catches: b.test: two failed on main again after entry B's fix card cB landed, and cA's own run found it on
# entry A's commit (by cA). Entry B, landed, stays in the record and still names the case, so cA went on as passed
# and landed with b.test: two failing and no open fix card left for it. Also catches: it waited for main for good, as
# no other card was left to change main.
t_redcyclelanded() {
  # shellcheck disable=SC2016 # expanded by fx_in's eval
  redcycle 'b.test: two' '' 'append "$(line cB 0 landed ok "{\"sha\":\"2222\"}")" || echo "the landed line of cB could not be written"'
  fixround 'failing b.test: two (found by cA, held by no other entry but B, whose card cB landed)'
}

# Bug it catches: cA's run ran out of time in d.test, and main failed a case of d.test, so the time-out's verdict was
# main, its case the bare file name d.test, which entry B holds as a push's run named it. cA went on as passed (rc 0
# on a run that timed out) and could land a change that makes d.test run past its limit.
t_redcycletimeout() {
  redcycle 'd.test' '{"timeout": {"sec": 60, "file": "d.test"}, "stopped": ["d.test"]}'
  fixround "its run out of time in d.test (entry B's case, failing on main)"
}
