#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the rule "Push when a card lands" (the control record's rules.push) and the Board's full test suite
# (the pack's test.full): Run full test suite, Push landed behind it, Push anyway, and how a red run is judged; and Push
# now, which pushes what landed with no run.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

ftmain() { git -C "$R" rev-parse refs/heads/main; }
ftorigin() { git -C "$T/$CASE/origin" rev-parse refs/heads/main; }
# The helpers are named ft*: every case file is sourced into one shell, so a name another file uses would replace its.
ftl() { jq -c "$1" "$ST/fulltest.jsonl" 2>/dev/null; }                                    # <jq filter>: of each line of the full test's record
ftlines() { cat "$ST/fulltest.jsonl" 2>/dev/null | wc -l | tr -d ' '; }
# Issue 7's card has landed with the push rule off, as a card run lands it (t_landonly runs one whole): main gains its
# commit (the build stub's line in a.txt) and the card record its landed line naming that commit; origin lacks it.
# A whole card run here only paid for the loop, its sessions and waits before what these cases test.
ftland() {
  loop control rules push=off > /dev/null || fail "the push rule could not be turned off"
  echo two >> "$R/a.txt"; git -C "$R" commit -qam 'Card of issue 7 (#7)' || fail "the landing could not be committed"
  landed 7 | jq -c --arg s "$(ftmain)" '.sha = $s' >> "$ST/cards.jsonl"
  [ "$(ftorigin)" != "$(ftmain)" ] || fail "the landing is at origin already"
}
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
  [ "$(loop snapshot --fresh | jq -c '[.health.unpushed[] | .issue]')" = '[7]' ] || fail "the snapshot does not name the unpushed card: $(loop snapshot --fresh | jq -c .health.unpushed)"
  # Push landed (the Board's `full-test push`): its green run pushes the landed commit to the remote. The fixture's
  # pack is not setup's, so it is given the test.full setup writes into a new pack (t_setup checks that it does).
  tune '.test.full = "true"'; loop full-test push > /dev/null || fail "push landed did not start"; ftended 1
  [ "$(ftorigin)" = "$(ftmain)" ] && [ -n "$(st 'select(.issue == 7 and .step == "pushed")')" ] \
    || fail "Push landed did not take the landed commit to the remote: origin $(ftorigin), main $(ftmain), $(cat "$ST/fulltest.jsonl" "$ST/fulltest.jsonl.log" 2>&1)"
}

# Bugs this guards: Push landed pushed a commit its run did not test (main moved on during the run); a second press
# started a second run beside the first; a project with no full test suite was offered one.
t_fullpush() {
  setup "[$(issue 7 2026-01-01)]"
  local A B out s
  # No test.full: both are refused with the reason, and the snapshot says it.
  out=$(loop full-test 2>&1); [ $? = 2 ] && grep -q 'names no full test suite' <<<"$out" || fail "a full test with no test.full was not refused: $out"
  out=$(loop full-test push 2>&1); [ $? = 2 ] || fail "a push landed with no test.full was not refused: $out"
  [ "$(loop snapshot --fresh | jq -c '.fullTest | [.command, .why, .running, .last]')" = '[false,"the pack names no full test suite (test.full)",null,null]' ] \
    || fail "the snapshot does not say why there is no full test: $(loop snapshot --fresh | jq -c .fullTest)"
  out=$(loop full-test now 2>&1); [ $? = 2 ] && grep -q usage <<<"$out" || fail "a bad full-test argument was not refused: $out"
  tune '.test.full = ". \"$STUB/full-cmd\""'
  echo 'git rev-parse HEAD >> "$STUB/full-at"; until [ -e "$STUB/go" ]; do sleep 0.1; done' > "$STUB/full-cmd"
  # A card lands, land only: one landed commit is unpushed.
  ftland; A=$(ftmain)
  # Run full test suite: it runs on main, and a second press while it runs is refused, starting nothing.
  out=$(loop full-test 2>&1) || fail "full-test did not start: $out"
  wait_until '[ -s "$STUB/full-at" ]' || fail "the full test suite did not start"
  out=$(loop full-test push 2>&1); [ $? = 2 ] && grep -q 'already running' <<<"$out" || fail "a second press during a run was not refused: $out"
  s=$(loop snapshot --fresh)
  [ "$(jq -c '.fullTest.running | [.how, .sha]' <<<"$s")" = "[\"run\",\"$A\"]" ] || fail "the snapshot does not show the run: $(jq -c .fullTest <<<"$s")"
  # Bug: the run is not shown as a release's suite is (/units, the Release panel), so the two kinds look different.
  [ "$(jq -c '[.suites[] | select(.kind == "full test") | [.state, .sha, .ended]]' <<<"$s")" = "[[\"running\",\"$A\",null]]" ] || fail "the snapshot's suites do not show the run: $(jq -c .suites <<<"$s")"
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
# machine's failure became a fix card; the cause named no commit. (A second fix card: t_fullredagain; Push anyway:
# t_fullanyway.)
t_fullred() {
  setup "[$(issue 7 2026-01-01)]"
  local A O0 c s
  tune '.test.full = ". \"$STUB/full-cmd\""'; ftsuite
  ftland; A=$(ftmain); O0=$(ftorigin)
  loop full-test push > /dev/null || fail "push landed did not start"; ftended 1
  # The full test suite is a full run the owner allows (issue 461): its run is given no list, so it runs whole.
  [ "$(head -n 1 "$STUB/fulls")" = "$A " ] || fail "the full test suite's run was not of the whole suite: $(cat "$STUB/fulls")"
  # Red: nothing is pushed, and each failed case is judged from its runs alone.
  [ "$(ftl '[.state, .exit, .pushed]')" = '["failed",1,null]' ] && [ "$(ftorigin)" = "$O0" ] || fail "a red run pushed, or is not recorded red: $(cat "$ST/fulltest.jsonl")"
  # Its files' results reach the Tests page (testrun.sh suiterec()): one line for the whole run, none for the runs of a
  # case alone. Bug caught: a whole-suite run's results were dropped with its worktree, so the page never showed them.
  [ "$(jq -sc --arg a "$A" 'map([.how, .sha == $a, (.files | map_values(.result))])' "$ST/suiteruns.jsonl" 2>&1)" \
    = '[["full",true,{"ok.test":"ok","code.test":"fail","old.test":"fail","flaky.test":"fail","net.test":"fail"}]]' ] \
    || fail "the whole run's files are not kept once for the Tests page: $(cat "$ST/suiteruns.jsonl" 2>&1)"
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
  s=$(loop snapshot --fresh)
  [ "$(jq -c '.fullTest.last | [.state, (.cases | map(.verdict))]' <<<"$s")" = '["failed",["fix","flaky","declined","fix"]]' ] || fail "the snapshot does not carry the red run: $(jq -c .fullTest <<<"$s")"
  # Bug: the red run's result is not shown as a release's suite is, with its failed cases by name.
  [ "$(jq -c '[.suites[] | select(.kind == "full test") | [.state, .sha, .failed, .cases, (.ended != null)]]' <<<"$s")" \
    = "[[\"failed\",\"$A\",4,[\"code.test: breaks\",\"flaky.test: flips\",\"net.test: fetch\",\"old.test: old\"],true]]" ] || fail "the snapshot's suites do not show the red run: $(jq -c .suites <<<"$s")"
}
# <id> <commit>: the line t_fullred's red run writes at <commit> (its id given), its fix cases filed as 100101 and 100102.
ftredline() {
  jq -cn --arg i "$1" --arg s "$2" '{time: "2026-11-01T00:00:00Z", id: $i, kind: "run", push: true, sha: $s, state: "failed", exit: 1, pushed: null, reused: null,
    cases: [["code.test: breaks", "fix", 100101, "failed"], ["flaky.test: flips", "flaky", null, "passed"], ["net.test: fetch", "declined", null, "failed"], ["old.test: old", "fix", 100102, "failed"]]
      | map({case: .[0], line: null, runs: [.[3], .[3], .[3]], verdict: .[1], why: null, issue: .[2], reused: false})}' >> "$ST/fulltest.jsonl"
}

# Bug this guards: a case that failed again got a second fix card. The run before is t_fullred's red run, as its line.
t_fullredagain() {
  setup "[$(issue 7 2026-01-01)]"
  tune '.test.full = ". \"$STUB/full-cmd\""'; ftsuite
  ftland; ftredline 0123456789ab "$(ftmain)"
  # Red again: the open fix card is reused with a comment; one whose state GitHub does not give is not filed again either.
  echo OPEN > "$STUB/state.100102"; : > "$STUB/state.100101"
  # ftended polls: `loop full-test` returns once it has started the run in the background (lib/fulltest.sh), and only
  # the run's own line and its removed .running file show that it has ended; no call returns at its end.
  loop full-test > /dev/null || fail "the second run did not start"; ftended 2
  [ ! -e "$STUB/filed" ] && [ "$(grep -c '^100102 --body It fails again' "$STUB/comments")" = 1 ] && [ "$(grep -c '^100101 ' "$STUB/comments")" = 0 ] \
    && [ "$(jq -sc '.[1] | [.cases[] | select(.verdict == "fix") | [.issue, .reused]]' "$ST/fulltest.jsonl")" = '[[100101,true],[100102,true]]' ] \
    || fail "an open fix card, or one GitHub said nothing of, was not reused: $(cat "$STUB/filed" "$STUB/comments" 2>&1) $(jq -sc '.[1].cases' "$ST/fulltest.jsonl")"
}

# Bug this guards: Push anyway pushed over whichever red run was last, not the one its confirm showed. The red runs are
# t_fullred's, as their lines: Push anyway runs no suite, so no run is needed to make them.
t_fullanyway() {
  setup "[$(issue 7 2026-01-01)]"
  local A O0 out
  tune '.test.full = ". \"$STUB/full-cmd\""'; ftsuite
  ftland; A=$(ftmain); O0=$(ftorigin)
  ftredline 0123456789ab "$A"; ftredline 0123456789ac "$A"
  # One that is no longer the last run (a later red run ended since, its cases not shown) pushes nothing.
  out=$(loop full-test anyway 0123456789ab 2>&1); [ $? = 2 ] && grep -q 'not the last full test run' <<<"$out" \
    && [ "$(ftorigin)" = "$O0" ] && [ "$(ftlines)" = 2 ] || fail "push anyway over a red run that is not the last was not refused: $out"
  out=$(loop full-test anyway 2>&1); [ $? = 2 ] && grep -q usage <<<"$out" || fail "push anyway naming no red run was not refused: $out"
  # Push anyway: the commit of the red run, with no run, logged as the owner's push over a red suite. ftended polls, as
  # the push runs in the background after `loop full-test anyway` returns (lib/fulltest.sh): only its line shows its end.
  loop full-test anyway 0123456789ac --by "Board user t" > /dev/null || fail "push anyway did not start"; ftended 3
  [ "$(ftorigin)" = "$A" ] && [ ! -e "$STUB/fulls" ] \
    && [ "$(ftl 'select(.kind == "anyway") | [.sha, .state, .by, .pushed.ok, (.cases | length)]')" = "[\"$A\",\"failed\",\"Board user t\",true,4]" ] \
    || fail "push anyway did not push the red run's commit alone, or is not logged: $(cat "$ST/fulltest.jsonl" "$ST/fulltest.jsonl.log" "$STUB/fulls" 2>&1)"
  # It is offered beside a red result only: with the last line not a red run, it is refused.
  out=$(loop full-test anyway 0123456789ac 2>&1); [ $? = 2 ] && grep -q 'not a red one' <<<"$out" || fail "push anyway with no red run to push over was not refused: $out"
}

# Bug this guards: while a red run's failed case ran alone, the snapshot counted that run's new log folder, so the
# suite's counts (done 3, failed 1, its case) dropped to nothing until the run ended.
t_fullredprog() {
  setup '[]'
  local s
  tune '.test.full = ". \"$STUB/full-cmd\""'
  cat > "$STUB/full-cmd" <<'EOF'
C=$CONVEYOR_TEST_LOG/cases; mkdir -p "$C/ok" "$C/failed"
if [ -n "${CONVEYOR_TEST_RERUN:-}" ]; then : > "$STUB/alone"; until [ -e "$STUB/go" ]; do sleep 0.1; done; exit 1; fi
: > "$C/ok/one"; : > "$C/ok/two"; : > "$C/failed/three"; echo "FAIL [three]: no"; exit 1
EOF
  loop full-test > /dev/null || fail "the full test did not start"
  wait_until '[ -e "$STUB/alone" ]' 'cat "$ST/fulltest.jsonl.log"' || fail "the failed case was not run alone"
  s=$(loop snapshot --fresh)
  : > "$STUB/go"; ftended 1
  [ "$(jq -c '[.suites[] | select(.kind == "full test") | [.state, .done, .failed, .cases]]' <<<"$s")" = '[["running",3,1,["three"]]]' ] \
    || fail "while a failed case ran alone, the suite's counts were lost: $(jq -c .suites <<<"$s")"
}

# Bug this guards: Push landed, refused by a remote whose main holds a commit made there by hand, merged it into the
# tested commit and pushed the merge, a commit the run did not test. Also: with the push rule set off, the loop still
# pushed a landing. A whole card run proves that one (t_landonly's has no push rule at all); it runs beside the file's
# slower cases, so it adds nothing to the file's time.
t_fullpushdiverged() {
  setup "[$(issue 7 2026-01-01)]"; echo "$GO" > "$STUB/review.1"
  local A H=$T/$CASE/hand hand
  tune '.test.full = "true"'
  loop control rules push=off > /dev/null; loop run 1 > "$STUB/run.out" 2>&1 || fail "the run failed: $(cat "$STUB/run.out")"
  A=$(ftmain); [ "$(ftorigin)" != "$A" ] || fail "the landing was pushed with land only"
  git clone -q "$T/$CASE/origin" "$H"; echo hand > "$H/c.txt"; git -C "$H" add c.txt; git -C "$H" commit -qm 'by hand'; git -C "$H" push -q origin main; hand=$(ftorigin)
  loop full-test push > /dev/null || fail "push landed did not start"; ftended 1
  [ "$(ftorigin)" = "$hand" ] && [ "$(ftmain)" = "$A" ] && [ "$(ftl '[.state, .sha, .pushed.ok]')" = "[\"passed\",\"$A\",false]" ] \
    && ftl '.pushed.reason' | grep -q 'the full test run did not test' \
    || fail "a diverged remote got a merge the run did not test, or the push does not say why it failed: origin $(ftorigin), main $(ftmain), $(cat "$ST/fulltest.jsonl")"
}

# Push now (`conveyor.sh push-now`, issue 25), on a card that landed with the push rule off. A pre-push hook that
# fails when $STUB/push-fail exists, with a check's FAILED line as the project's would print; a test.full that would
# fail and leaves a mark if it is ever run.
ftnow() {
  setup "[$(issue 7 2026-01-01)]"
  printf '%s\n' '#!/usr/bin/env bash' 'read -r ref sha rest; echo "$sha" >> "$STUB/hookruns"' \
    '[ ! -e "$STUB/push-fail" ] || { echo "push-checks: FAILED fast-checks" >&2; exit 1; }' > "$R/.git/hooks/pre-push"
  chmod +x "$R/.git/hooks/pre-push"
  echo 'touch "$STUB/full-ran"; exit 1' > "$STUB/full-cmd"; tune '.test.full = ". \"$STUB/full-cmd\""'
  ftland
}
ftpushes() { st 'select(.step == "push" or .step == "pushed") | [.step, .result, .kind] | join(" ")' | wc -l | tr -d ' '; }

# Bugs this guards: with the push rule off, landed work could reach the remote only behind a whole suite run (Push
# landed); Push now must push it as the loop's own push does: through the pre-push hook, a failed hook recorded as a
# check push error under the landed card (Needs you reads it), and never run test.full.
t_pushnow() {
  ftnow; local A O0 out
  A=$(ftmain); O0=$(ftorigin)
  # The hook fails: nothing reaches the remote, and the card has a push line of kind check naming the check.
  : > "$STUB/push-fail"
  loop push-now > /dev/null || fail "push-now did not start"
  wait_until '[ "$(ftpushes)" = 1 ] && [ ! -e "$ST/pushing" ]' 'cat "$ST/pushnow.log" "$ST/cards.jsonl"'
  [ "$(ftorigin)" = "$O0" ] && [ "$(st 'select(.step == "push") | [.issue, .result, .kind, .check, .sha] | join(" ")')" = "7 fail check fast-checks $A" ] \
    || fail "a push whose pre-push hook failed reached the remote, or is not recorded as a check push error: origin $(ftorigin), $(st 'select(.step == "push")')"
  # The hook passes: main reaches the remote through it, the card is marked pushed.
  rm "$STUB/push-fail"
  loop push-now > /dev/null || fail "push-now did not start after the check failed"
  wait_until '[ -n "$(st "select(.issue == 7 and .step == \"pushed\")")" ] && [ ! -e "$ST/pushing" ]' 'cat "$ST/pushnow.log" "$ST/cards.jsonl"'
  [ "$(ftorigin)" = "$A" ] && [ "$(tail -n 1 "$STUB/hookruns")" = "$A" ] || fail "push-now did not push main through the pre-push hook: origin $(ftorigin), main $A, hook $(cat "$STUB/hookruns")"
  [ ! -e "$STUB/full-ran" ] && [ ! -s "$ST/fulltest.jsonl" ] || fail "push-now ran the full test suite"
  # Nothing is unpushed now: refused with the reason, and nothing is pushed or recorded.
  out=$(loop push-now 2>&1); [ $? = 2 ] && grep -q 'no landed commit' <<<"$out" || fail "push-now with nothing unpushed was not refused: $out"
  [ "$(ftpushes)" = 2 ] && [ "$(wc -l < "$STUB/hookruns")" = 2 ] || fail "push-now with nothing unpushed changed something: $(cat "$STUB/hookruns")"
}

# Bug this guards (issue 240): a run whose process was killed left its running marker, nothing recorded it, and the
# Foreman heard nothing: the owner thought the suite had run. Its end is now shown at once (the snapshot's suites, which
# wakes the Foreman's watcher), and the next ask records it as an error with the reason and starts its own run.
t_fulldead() {
  setup '[]'
  local pid s A
  tune '.test.full = ". \"$STUB/full-cmd\""'
  echo 'echo x >> "$STUB/full-at"; until [ -e "$STUB/go" ]; do sleep 0.1; done' > "$STUB/full-cmd"
  loop full-test > /dev/null || fail "the full test did not start"
  wait_until '[ -s "$STUB/full-at" ] && jq -e .pid "$ST/fulltest.jsonl.running" > /dev/null' 'cat "$ST/fulltest.jsonl.log" "$ST/fulltest.jsonl.running"' \
    || fail "the run did not start, or its marker names no process"
  pid=$(jq .pid "$ST/fulltest.jsonl.running"); A=$(jq -r .sha "$ST/fulltest.jsonl.running")
  kill -9 "$pid"; : > "$STUB/go"
  wait_until '( flock -n 9 ) 9>>"$ST/fulltest.jsonl.lock"' 'ps -ef' || fail "the killed run's lock was not let go"
  s=$(loop snapshot --fresh)
  [ "$(jq -c '[.suites[] | select(.kind == "full test") | [.state, .sha, (.ended != null), (.reasons[0] | test("ended without a result: its process \\('"$pid"'\\) is gone"))]]' <<<"$s")" = "[[\"error\",\"$A\",true,true]]" ] \
    || fail "the killed run is not shown as ended with no result: $(jq -c .suites <<<"$s")"
  echo 'exit 0' > "$STUB/full-cmd"
  loop full-test > /dev/null 2>&1 || fail "the next full test did not start after the killed run"
  ftended 2
  [ "$(ftl '[.kind, .state, .sha, (.reason // "" | test("ended without a result"))]' | paste -sd' ' -)" = "[\"run\",\"error\",\"$A\",true] [\"run\",\"passed\",\"$A\",false]" ] \
    || fail "the killed run was not recorded as an error before the next run: $(cat "$ST/fulltest.jsonl")"
  [ "$(jq -c '[.suites[] | select(.kind == "full test") | .state]' <<<"$(loop snapshot --fresh)")" = '["passed"]' ] || fail "the snapshot still shows the killed run"
}

# Bug this guards: Push now pushed while a full test run was under way (its push would race the run's own).
t_pushnowbusy() {
  ftnow; local O0 out
  O0=$(ftorigin)
  echo 'git rev-parse HEAD >> "$STUB/full-at"; until [ -e "$STUB/go" ]; do sleep 0.1; done' > "$STUB/full-cmd"
  loop full-test > /dev/null || fail "full-test did not start"
  wait_until '[ -s "$STUB/full-at" ]' 'cat "$ST/fulltest.jsonl.log"'
  out=$(loop push-now 2>&1); [ $? = 2 ] && grep -q 'a full test run is under way' <<<"$out" || fail "push-now during a full test run was not refused: $out"
  : > "$STUB/go"; ftended 1
  [ "$(ftorigin)" = "$O0" ] && [ "$(ftpushes)" = 0 ] && [ ! -e "$STUB/hookruns" ] || fail "push-now during a full test run pushed: origin $(ftorigin), $(cat "$STUB/hookruns" 2>&1)"
}

# Bug this guards: a failed file that named no case (it failed, or ran out of time, naming none) was run "alone" with a
# list naming every other file as passed and no `fail` line, so a command that runs only the list's failed cases (the
# whole test on main's, .conveyor/test-full.sh) ran nothing, passed, and the file was judged flaky.
t_fullalonefile() {
  local w=$T/$CASE/wt got
  mkdir -p "$T/$CASE"; got=$( eval "$(sed -n '/^fullalone() {/,/^}/p' "$SRC/lib/fulltest.sh")"
    tests() { cp "$1.rerun" "$1.seen"; echo "$2" >> "$1.seen"; return 1; }
    fullalone "$w" '{"files":[{"file":"a.test"},{"file":"b.test"}],"passed":["c.test"]}' '{"file":"a.test","case":null}' test.main
    cat "$w.seen" )
  [ "$got" = $'failed\npass\tb.test\npass\tc.test\nfail\ta.test\ntest.main' ] || fail "the file with no case was not named alone as a failed file: $got"
}

# Bug caught (#344): fullrun() gave the judged cases to jq as one argument, which Linux refuses over 128 KiB ("Argument
# list too long"), so a red run with many failed cases wrote no line to the full test's record. The suite fails and
# its judge (stubbed, as are the run and its worktree's setup) gives 1000 cases of long names, about 250 KB.
t_fullbigcases() {
  setup '[]'; mkdir -p "$T/$CASE"
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; cd "$R" && . "$SRC/conveyor.sh" state-dir > /dev/null \
      && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" && names || exit 1
    deps() { :; }; slot_pool() { :; }; suitereuse() { return 1; }; tests() { return 1; }; suiterec() { :; }; suitekeep() { return 1; }
    testfails() { echo '{"files":[]}'; }
    fulljudge() { jq -cn '[range(1000) | {case: ("a.test: case-\(.)-" + ("x" * 200)), verdict: "fix", runs: ["failed"]}]'; }
    fullrun run "$(git rev-parse HEAD)" 'bash full' '' ) > "$T/$CASE/run.out" 2>&1
  [ "$(ftl '[.state, (.cases | length)]')" = '["failed",1000]' ] \
    || fail "the red run with many cases left no line with them: $(ftl '[.state, (.cases | length)]') $(tail -c 300 "$T/$CASE/run.out")"
}
