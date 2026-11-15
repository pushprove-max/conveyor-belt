#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the rule "Push when a card lands" (the control record's rules.push) and the Board's full test suite
# (the pack's test.full): Run full test suite, Push landed behind it, Push anyway, and how a red run is judged.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

ftmain() { git -C "$R" rev-parse refs/heads/main; }
ftorigin() { git -C "$T/$CASE/origin" rev-parse refs/heads/main; }
# The helpers are named ft*: every case file is sourced into one shell, so a name another file uses would replace its.
ftl() { jq -c "$1" "$ST/fulltest.jsonl" 2>/dev/null; }                                    # <jq filter>: of each line of the full test's record
ftlines() { cat "$ST/fulltest.jsonl" 2>/dev/null | wc -l | tr -d ' '; }
ftended() { wait_until "[ \"\$(ftlines)\" = $1 ] && [ ! -e \"\$ST/fulltest.jsonl.running\" ]" 'cat "$ST/fulltest.jsonl.log" "$ST/fulltest.jsonl" 2>&1'; } # <lines>: the run or push asked for has ended

# Bugs this guards: a new install (a record that names no push rule) pushed every landing with nobody asked; with
# land only, the loop still pushed, so the owner could not hold main back from the remote; Push landed then did not
# take the landed commit to the remote.
t_landonly() {
  setup "[$(issue 7 2026-01-01)]"; echo "$GO" > "$STUB/review.1"
  # The record names no push rule, as a new install's: the default is land only.
  jq -c 'del(.rules.push)' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json"
  loop run 1 > "$STUB/run.out" 2>&1 || fail "a run with land only ended in failure (a push it may not make counted as owed): $(cat "$STUB/run.out")"
  [ -n "$(st 'select(.issue == 7 and .step == "landed")')" ] || fail "the card did not land: $(cat "$STUB/run.out")"
  [ "$(ftorigin)" != "$(ftmain)" ] && [ -z "$(st 'select(.issue == 7 and (.step == "pushed" or .step == "push"))')" ] \
    || fail "with the push rule off by default, the landing was pushed: $(st 'select(.issue == 7)')"
  # The Board's count and cards of what landed and is not pushed come from the snapshot.
  [ "$(loop snapshot | jq -c '[.health.unpushed[] | .issue]')" = '[7]' ] || fail "the snapshot does not name the unpushed card: $(loop snapshot | jq -c .health.unpushed)"
  # Push landed (the Board's `full-test push`): its green run pushes the landed commit to the remote. The fixture's
  # pack is not setup's, so it is given the test.full setup writes into a new pack (t_setup checks that it does).
  tune '.test.full = "true"'; loop full-test push > /dev/null || fail "push landed did not start"; ftended 1
  [ "$(ftorigin)" = "$(ftmain)" ] && [ -n "$(st 'select(.issue == 7 and .step == "pushed")')" ] \
    || fail "Push landed did not take the landed commit to the remote: origin $(ftorigin), main $(ftmain), $(cat "$ST/fulltest.jsonl" "$ST/fulltest.jsonl.log" 2>&1)"
}

# Bugs this guards: Push landed pushed a commit its run did not test (main moved on during the run); a second press
# started a second run beside the first; a project with no full test suite was offered one.
t_fullpush() {
  setup "[$(issue 7 2026-01-01)]"; echo "$GO" > "$STUB/review.1"
  local A B out
  # No test.full: both are refused with the reason, and the snapshot says it.
  out=$(loop full-test 2>&1); [ $? = 2 ] && grep -q 'names no full test suite' <<<"$out" || fail "a full test with no test.full was not refused: $out"
  out=$(loop full-test push 2>&1); [ $? = 2 ] || fail "a push landed with no test.full was not refused: $out"
  [ "$(loop snapshot | jq -c '.fullTest | [.command, .why, .running, .last]')" = '[false,"the pack names no full test suite (test.full)",null,null]' ] \
    || fail "the snapshot does not say why there is no full test: $(loop snapshot | jq -c .fullTest)"
  out=$(loop full-test now 2>&1); [ $? = 2 ] && grep -q usage <<<"$out" || fail "a bad full-test argument was not refused: $out"
  tune '.test.full = ". \"$STUB/full-cmd\""'
  echo 'git rev-parse HEAD >> "$STUB/full-at"; until [ -e "$STUB/go" ]; do sleep 0.1; done' > "$STUB/full-cmd"
  # A card lands, land only: one landed commit is unpushed.
  loop control rules push=off > /dev/null; loop run 1 > "$STUB/run.out" 2>&1 || fail "the run failed: $(cat "$STUB/run.out")"
  A=$(ftmain); [ "$(ftorigin)" != "$A" ] || fail "the landing was pushed with land only"
  # Run full test suite: it runs on main, and a second press while it runs is refused, starting nothing.
  out=$(loop full-test 2>&1) || fail "full-test did not start: $out"
  wait_until '[ -s "$STUB/full-at" ]' || fail "the full test suite did not start"
  out=$(loop full-test push 2>&1); [ $? = 2 ] && grep -q 'already running' <<<"$out" || fail "a second press during a run was not refused: $out"
  [ "$(loop snapshot | jq -c '.fullTest.running | [.how, .sha]')" = "[\"run\",\"$A\"]" ] || fail "the snapshot does not show the run: $(loop snapshot | jq -c .fullTest)"
  : > "$STUB/go"; ftended 1
  [ "$(ftl '[.kind, .push, .state, .sha, .pushed]')" = "[\"run\",false,\"passed\",\"$A\",null]" ] && [ "$(ftorigin)" != "$A" ] && [ "$(wc -l < "$STUB/full-at")" = 1 ] \
    || fail "Run full test suite did not pass on main alone, or pushed: $(cat "$ST/fulltest.jsonl")"
  # Push landed: main moves on during the run; green, the push sends exactly the commit the run tested.
  rm "$STUB/go"; loop full-test push > /dev/null || fail "push landed did not start"
  wait_until '[ "$(wc -l < "$STUB/full-at")" = 2 ]' || fail "the push's full test did not start"
  echo later > "$R/c.txt"; git -C "$R" add c.txt; git -C "$R" commit -qm later; B=$(ftmain)
  : > "$STUB/go"; ftended 2
  [ "$(sed -n 2p "$STUB/full-at")" = "$A" ] && [ "$(ftorigin)" = "$A" ] && [ "$(ftl 'select(.push) | [.state, .sha, .pushed.ok]')" = "[\"passed\",\"$A\",true]" ] \
    || fail "Push landed did not push the commit its run tested, and only it: origin $(ftorigin), main $B, $(cat "$ST/fulltest.jsonl" "$ST/fulltest.jsonl.log")"
  [ -n "$(st 'select(.issue == 7 and .step == "pushed")')" ] || fail "the pushed card has no pushed line"
  # Nothing landed is unpushed now (main's later commit is no card's): a push is refused and runs nothing.
  out=$(loop full-test push 2>&1); [ $? = 2 ] && grep -q 'no landed commit' <<<"$out" && [ "$(ftlines)" = 2 ] || fail "a push with nothing landed to push was not refused: $out"
}

# The suite of t_fullred, a runner of five files that honours CONVEYOR_TEST_RERUN as conveyor.sh's own runner does
# (a file listed as passed is not run): code.test fails once a.txt holds the card's line (a landed commit breaks it),
# old.test always fails (it failed before any landing), flaky.test fails only in the whole run, net.test fails with a
# refused connection (the network), ok.test passes.
ftsuite() {
  cat > "$STUB/full-cmd" <<'EOF'
rr=${CONVEYOR_TEST_RERUN:-}; log=$CONVEYOR_TEST_LOG/run.log; rc=0; echo "$(git rev-parse HEAD) ${rr:+alone}" >> "$STUB/fulls"
one() { # <file> <case> <1: it fails> <its failure>
  [ -z "$rr" ] || ! grep -qxF "pass"$'\t'"$1" "$rr" || return 0
  echo "== $1"; echo "== $1" >> "$log"
  if [ "$3" = 1 ]; then echo "FAIL [$2]: $4"; echo "-- FAIL $1" >> "$log"; rc=1; else echo "ok $2"; echo "-- ok $1" >> "$log"; fi
}
one ok.test fine 0 -
one code.test breaks "$(grep -qx two a.txt && echo 1 || echo 0)" "a.txt holds two"
one old.test old 1 "expected 1, got 2"
one flaky.test flips "$([ -z "$rr" ] && echo 1 || echo 0)" "at random"
one net.test fetch 1 "connect ECONNREFUSED 192.0.2.1:443"
exit $rc
EOF
}
# Bugs this guards: a red suite pushed anyway; a failed case was filed without being run alone, so a flaky or a
# machine's failure became a fix card; a case that failed again got a second fix card; the cause named no commit.
t_fullred() {
  setup "[$(issue 7 2026-01-01)]"; echo "$GO" > "$STUB/review.1"
  local A O0 c
  tune '.test.full = ". \"$STUB/full-cmd\""'; ftsuite
  loop control rules push=off > /dev/null; loop run 1 > "$STUB/run.out" 2>&1 || fail "the run failed: $(cat "$STUB/run.out")"
  A=$(ftmain); O0=$(ftorigin); [ "$O0" != "$A" ] || fail "the landing was pushed with land only"
  loop full-test push > /dev/null || fail "push landed did not start"; ftended 1
  # The full test suite is a full run the owner allows (issue 461): its run is given no list, so it runs whole.
  [ "$(head -n 1 "$STUB/fulls")" = "$A " ] || fail "the full test suite's run was not of the whole suite: $(cat "$STUB/fulls")"
  # Red: nothing is pushed, and each failed case is judged from its runs alone.
  [ "$(ftl '[.state, .exit, .pushed]')" = '["failed",1,null]' ] && [ "$(ftorigin)" = "$O0" ] || fail "a red run pushed, or is not recorded red: $(cat "$ST/fulltest.jsonl")"
  [ "$(ftl '[.cases[] | [.case, .verdict, (.runs | join(","))]]')" = '[["code.test: breaks","fix","failed,failed,failed"],["flaky.test: flips","flaky","passed,passed,passed"],["net.test: fetch","declined","failed,failed,failed"],["old.test: old","fix","failed,failed,failed"]]' ] \
    || fail "the failed cases are not judged from three runs alone each: $(fl .cases)"
  # The runs: the whole suite once, three alone for each of the four cases, and one alone at origin's commit for each
  # case in the code (is it the landed commit's?).
  [ "$(grep -c " alone$" "$STUB/fulls")" = 14 ] && [ "$(grep -c "^$O0 alone$" "$STUB/fulls")" = 2 ] || fail "the cases were not run alone as asked: $(cat "$STUB/fulls")"
  # A fix card each for the two cases in the code, at P1, with the failure, the runs alone and the cause.
  [ "$(jq -cs 'map([.number, .title, (.labels | map(.name))])' "$STUB/filed")" = '[[100101,"Full test suite fails: code.test: breaks",["bug","P1"]],[100102,"Full test suite fails: old.test: old",["bug","P1"]]]' ] \
    || fail "the fix cards were not filed one a case in the code: $(cat "$STUB/filed" 2>&1)"
  c=$(git -C "$R" log -1 --format=%h "$A")
  jq -se --arg c "$c" '.[0].body | contains("Failure: FAIL [breaks]: a.txt holds two") and contains("Runs alone at") and contains("failed, failed, failed")
      and contains("a landed commit plausibly caused it") and contains("\($c) ") and contains("#7")' "$STUB/filed" > /dev/null \
    || fail "the fix card of the case a landing broke does not name its failure, runs and the commit: $(jq -sr '.[0].body' "$STUB/filed")"
  jq -se '.[1].body | contains("already failing before the landed commits")' "$STUB/filed" > /dev/null || fail "the fix card of an old failure does not say it was failing before: $(jq -sr '.[1].body' "$STUB/filed")"
  # The flaky case is on the flaky-test record; the network's failure is declined with its reason.
  [ "$(jq -c '[.entries[] | [.case, .source]]' "$ST/flaky.json")" = "[[\"flaky.test: flips\",\"full test ${A:0:12}\"]]" ] || fail "the flaky case is not on the flaky record: $(cat "$ST/flaky.json" 2>&1)"
  jq -se 'length == 1 and (.[0] | (.finding | startswith("net.test: fetch")) and (.why | contains("ECONNREFUSED")) and .by == "code")' "$ST/declined.jsonl" > /dev/null \
    || fail "the network's failure is not declined with its reason: $(cat "$ST/declined.jsonl" 2>&1)"
  [ "$(loop snapshot | jq -c '.fullTest.last | [.state, (.cases | map(.verdict))]')" = '["failed",["fix","flaky","declined","fix"]]' ] || fail "the snapshot does not carry the red run: $(loop snapshot | jq -c .fullTest)"
  # Red again with both fix cards open: they are reused, a comment each, and no second card is filed.
  echo OPEN > "$STUB/state.100101"; echo OPEN > "$STUB/state.100102"
  loop full-test > /dev/null || fail "the second run did not start"; ftended 2
  [ "$(wc -l < "$STUB/filed")" = 2 ] && [ "$(grep -c '^10010[12] --body It fails again' "$STUB/comments")" = 2 ] \
    && [ "$(jq -sc '.[1] | [.cases[] | select(.verdict == "fix") | [.issue, .reused]]' "$ST/fulltest.jsonl")" = '[[100101,true],[100102,true]]' ] \
    || fail "an open fix card was not reused: $(jq -c '[.number, .title]' "$STUB/filed") $(cat "$STUB/comments" 2>&1)"
  # One whose state GitHub does not give is not filed again either.
  : > "$STUB/state.100101"
  loop full-test > /dev/null || fail "the third run did not start"; ftended 3
  [ "$(wc -l < "$STUB/filed")" = 2 ] || fail "a fix card GitHub said nothing of was filed again: $(jq -c '[.number, .title]' "$STUB/filed")"
  # Push anyway names the red run its confirm showed: one that is no longer the last run (a later red run ended since,
  # its cases not shown) pushes nothing. Bug: it pushed over whichever red run was last.
  c=$(wc -l < "$STUB/fulls")
  out=$(loop full-test anyway "$(jq -rs '.[1].id' "$ST/fulltest.jsonl")" 2>&1); [ $? = 2 ] && grep -q 'not the last full test run' <<<"$out" \
    && [ "$(ftorigin)" = "$O0" ] && [ "$(ftlines)" = 3 ] || fail "push anyway over a red run that is not the last was not refused: $out"
  out=$(loop full-test anyway 2>&1); [ $? = 2 ] && grep -q usage <<<"$out" || fail "push anyway naming no red run was not refused: $out"
  # Push anyway: the commit of the red run, with no run, logged as the owner's push over a red suite.
  loop full-test anyway "$(ftl 'select(.kind == "run") | .id' | tr -d '"' | tail -n 1)" --by "Board user t" > /dev/null || fail "push anyway did not start"; ftended 4
  [ "$(ftorigin)" = "$A" ] && [ "$(wc -l < "$STUB/fulls")" = "$c" ] \
    && [ "$(ftl 'select(.kind == "anyway") | [.sha, .state, .by, .pushed.ok, (.cases | length)]')" = "[\"$A\",\"failed\",\"Board user t\",true,4]" ] \
    || fail "push anyway did not push the red run's commit alone, or is not logged: $(cat "$ST/fulltest.jsonl" "$ST/fulltest.jsonl.log")"
  # It is offered beside a red result only: with the last line not a red run, it is refused.
  out=$(loop full-test anyway "$(jq -rs '.[2].id' "$ST/fulltest.jsonl")" 2>&1); [ $? = 2 ] && grep -q 'not a red one' <<<"$out" || fail "push anyway with no red run to push over was not refused: $out"
}

# Bug this guards: Push landed, refused by a remote whose main holds a commit made there by hand, merged it into the
# tested commit and pushed the merge, a commit the run did not test.
t_fullpushdiverged() {
  setup "[$(issue 7 2026-01-01)]"; echo "$GO" > "$STUB/review.1"
  local A H=$T/$CASE/hand hand
  tune '.test.full = "true"'
  loop control rules push=off > /dev/null; loop run 1 > "$STUB/run.out" 2>&1 || fail "the run failed: $(cat "$STUB/run.out")"
  A=$(ftmain)
  git clone -q "$T/$CASE/origin" "$H"; echo hand > "$H/c.txt"; git -C "$H" add c.txt; git -C "$H" commit -qm 'by hand'; git -C "$H" push -q origin main; hand=$(ftorigin)
  loop full-test push > /dev/null || fail "push landed did not start"; ftended 1
  [ "$(ftorigin)" = "$hand" ] && [ "$(ftmain)" = "$A" ] && [ "$(ftl '[.state, .sha, .pushed.ok]')" = "[\"passed\",\"$A\",false]" ] \
    && ftl '.pushed.reason' | grep -q 'the full test run did not test' \
    || fail "a diverged remote got a merge the run did not test, or the push does not say why it failed: origin $(ftorigin), main $(ftmain), $(cat "$ST/fulltest.jsonl")"
}
