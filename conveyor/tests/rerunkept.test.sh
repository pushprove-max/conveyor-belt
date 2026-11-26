#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: what a test step keeps as passed, and what it runs again, when HEAD or main moved under the card, a
# card is retried, a full run is refused, a file is kept off for its time, or a run's time runs out (tests()).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# rerunsetup, rerunfiles, ran, rerunedit, rerunstep and rerunwt are rerun.test.sh's: the runner loads every case
# file into one shell. A change to rerun.test.sh's helpers or setup runs this file too, through its link in .conveyor/test-links.json.
# So is resumed resume.test.sh's, through that file's link.

# Bug this guards against: a session that brings the change onto another HEAD and edits it where main changed
# nothing (here a.txt, the card's own file, on a HEAD whose new commit changes no file) has edited it outside any
# conflict: its passes are not kept, and the run after it is of the whole selection (tests(): rerunsince() returns 2),
# not refused. The card's failed test line is in the records, so a whole run taken as one that cannot be kept
# (rerunsince()'s 1) would be refused and run flaky alone.
t_rerunmoved() {
  rerunwt 'echo two >> a.txt' '1 fail flaky' '2 fail flaky'
  ! rerunstep || fail "the first test step passed"
  echo '{"card":"c7","issue":7,"step":"test","time":"2026-01-01T00:01:00Z","tokens":{"claude":0,"codex":0},"result":"fail","sha":"","reason":"","repo":"main"}' >> "$ST/cards.jsonl"
  # The fix session: it edits a.txt again and moves HEAD to a commit that changes no file.
  rerunedit 'echo two >> a.txt; git update-ref HEAD "$(git commit-tree "HEAD^{tree}" -p HEAD -m moved)"' || fail "the fix session's edit could not be made"
  rerunstep || fail "the step after the session that moved HEAD did not pass: $(ran 3)"
  [ ! -e "$STUB/rerun.3" ] && [ "$(ran 3)" = "one two flaky three" ] || fail "the run after a session that moved HEAD was not of the whole selection: $(ran 3): $(cat "$STUB/rerun.3" 2>&1)"
  [ "$(jq -r '.refused // "none"' "$T/$CASE/cards/c7.testrec")" = none ] || fail "the whole run after a session that moved HEAD was refused: $(cat "$T/$CASE/cards/c7.testrec")"
}

# Issue 461 (#415 ran all 45 of its test files twice on 2026-11-14): a test step that would run the whole selection
# again after a fix and review round that changed nothing refuses the full run. Here the fix session leaves the change
# as it was, and the last run's list names a commit that is none (as a spoilt list would): the run after the round
# runs only what was not kept as passed (flaky), not a.test and c.test; its line records the refusal and why, and the
# record check takes that line. The first run, before any list, ran the whole selection and refused nothing. Health
# lists a refused line from the records, so the Foreman's watcher wakes on it: snaplines.test.sh, t_snaplinessame, and
# conveyor/foreman/foreman.test.sh, t_wake.
t_rerunrefused() {
  rerunwt 'echo two >> a.txt' '1 fail flaky' '2 fail flaky'
  ! rerunstep || fail "the first test step passed"
  [ "$(ran 1)" = "one two flaky three" ] && [ "$(jq -r '.refused // "none"' "$T/$CASE/cards/c7.testrec")" = none ] \
    || fail "the first run was not of the whole selection, or refused: $(ran 1): $(cat "$T/$CASE/cards/c7.testrec" 2>&1)"
  # The failed step's test line, as card() records it: the card was tested before (testlist.sh testedbefore()).
  echo '{"card":"c7","issue":7,"step":"test","time":"2026-01-01T00:01:00Z","tokens":{"claude":0,"codex":0},"result":"fail","sha":"","reason":"","repo":"main"}' >> "$ST/cards.jsonl"
  # The fix session leaves the change as it was; the list's commit is none.
  awk 'BEGIN { FS = OFS = "\t" } $1 == "base" { $2 = "0000000000000000000000000000000000000001" } 1' "$T/$CASE/cards/c7.rerun" > "$STUB/list" \
    && mv "$STUB/list" "$T/$CASE/cards/c7.rerun" || fail "the list's commit could not be spoilt"
  rerunstep || fail "the step after the fix did not pass: $(ran 3)"
  [ "$(ran 3)" = flaky ] || fail "the refused full run ran more than what was not kept as passed: $(ran 3): $(cat "$STUB/rerun.3" 2>&1)"
  [ "$(jq -r .refused "$T/$CASE/cards/c7.testrec")" = "refused full run: the commit last tested on (0000000000000000000000000000000000000001) cannot be compared with HEAD" ] \
    || fail "the test line does not record the refusal and why: $(cat "$T/$CASE/cards/c7.testrec" 2>&1)"
  # Its test line as card() records a pass: line()'s fields, testrec()'s part and firstrun()'s. Its time is now, as
  # health lists a refusal of the last day only.
  jq -cs --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{card: "c7", issue: 7, step: "test", time: $now, tokens: {claude: 0, codex: 0}, result: "pass", sha: "", reason: "", repo: "main"} * .[0] * .[1]' \
    "$T/$CASE/cards/c7.testrec" "$T/$CASE/cards/c7.firstrun" \
    > "$STUB/refused.jsonl" || fail "the refused run's test line could not be made"
  recok "$STUB/refused.jsonl" "a test step with a refused full run"
  cat "$STUB/refused.jsonl" >> "$ST/cards.jsonl"
  [ "$(loop health | jq -c '.refused | map([.issue, (.reason | startswith("refused full run: "))])')" = '[[7,true]]' ] \
    || fail "health does not list the refused run for the Foreman: $(loop health | jq -c .refused)"
}

# The landing's move of card c7's change onto main as it is now: settle() (lib/claim.sh) at its landing step, as card()
# calls it, with no card. Main has changed a.txt as the change does, so the change's three-way merge onto main
# conflicts there, and session() (a stand-in: no model) makes <edit> as the session that brings the change onto main.
# settle() itself decides from that edit whether the merge is in doubt (inconflicts()) and writes <worktree>.whole for
# tests(); donewhen.sh checked() (the Done-when check of a doubtful merge's reply) passes. run.out ends with "settle: <its exit>".
rerunfit() { # <the session's edit>
  fx_in 'cd "$R" || exit 9; caught="" waitsec=0 behind="[]" parsecheck=""
    session() { (cd "$1" && '"$1"') > /dev/null 2>&1; echo "{}"; }
    checked() { :; }
    settle c7 7 "$CONVEYOR_CARDS/c7" "Build the issue." land "$(issue 7 2026-01-01)"; echo "settle: $?"'
}

# A merge in doubt (the session that brought the change onto main edited it outside the conflicts: here b.txt beside
# the conflict in a.txt, as settle() finds it: inconflicts()) runs the whole selection, and refuses nothing (tests(),
# given the <worktree>.whole that settle() wrote): the merge may have broken what passed before. The card's test line is in the records, so a
# run with no list that took no notice of the doubt would be refused.
t_rerunmergedoubt() {
  rerunwt 'echo seven > a.txt'
  rerunstep || fail "the first test step did not pass: $(ran 1)"
  echo '{"card":"c7","issue":7,"step":"test","time":"2026-01-01T00:01:00Z","tokens":{"claude":0,"codex":0},"result":"pass","sha":"","reason":"","repo":"main"}' >> "$ST/cards.jsonl"
  echo main1 > "$R/a.txt"; git -C "$R" commit -qam "main moves" || fail "main could not move"
  rerunfit 'echo seven > a.txt; echo b > b.txt'
  [ "$(tail -n 1 "$T/$CASE/run.out")" = "settle: 2" ] || fail "settle() did not bring the change onto main by the session: $(cat "$T/$CASE/run.out")"
  # settle()'s own finding, apart from tests(): rerunsince() also runs the whole selection for b.txt, a file main did
  # not change, so the run below would not show a settle() that took the edit as inside the conflict.
  [ -s "$T/$CASE/cards/c7.whole" ] && [ ! -e "$T/$CASE/cards/c7.rerun" ] \
    || fail "settle() did not take the session's edit of b.txt, outside the conflict in a.txt, as a merge in doubt: $(cat "$T/$CASE/run.out")"
  rerunstep || fail "the step after the merge in doubt did not pass: $(ran 2)"
  [ "$(ran 2)" = "one two flaky three" ] && [ ! -e "$STUB/rerun.2" ] || fail "the run after a merge in doubt was not of the whole selection: $(ran 2): $(cat "$STUB/rerun.2" 2>&1)"
  [ "$(jq -r '.refused // "none"' "$T/$CASE/cards/c7.testrec")" = none ] || fail "a merge in doubt's whole run was refused: $(cat "$T/$CASE/cards/c7.testrec")"
}

# Bug (issue 460: #415 ran its whole selection again each time main moved under it, though main's new commits touched
# almost nothing its tests use). #7 changes a.txt and passes; then main changes a.txt too, and y.txt, which selects
# c.test. The session that brings #7 onto main changes only the conflict (inconflicts()), and the run after it keeps
# the passes of the first (tests(), rerunsince()): a.test (main changed its a.txt) and c.test run, b.test, which
# nothing main changed selects, does not.
t_rerunrebuilt() {
  rerunwt 'echo seven > a.txt'; echo 'y.txt c.test' >> "$STUB/map"
  rerunstep || fail "the first test step did not pass: $(ran 1)"
  echo main1 > "$R/a.txt"; echo y > "$R/y.txt"; git -C "$R" add a.txt y.txt; git -C "$R" commit -qm "main moves" || fail "main could not move"
  rerunfit 'echo seven > a.txt'
  [ "$(tail -n 1 "$T/$CASE/run.out")" = "settle: 2" ] && [ ! -e "$T/$CASE/cards/c7.whole" ] \
    || fail "settle() did not bring the change onto main by a session that changed only the conflict: $(cat "$T/$CASE/run.out")"
  rerunstep || fail "the step after the rebuild onto main did not pass: $(ran 2)"
  [ "$(ran 1)" = "one two flaky three" ] && [ "$(ran 2)" = "one two three" ] \
    || fail "the run after the rebuild onto main did not keep b.test's pass: first $(ran 1), then $(ran 2): $(cat "$STUB/rerun.2" 2>&1)"
  [ "$(grep -E $'^(main|changed)\t' "$STUB/rerun.2" | tr '\t\n' ':|')" = "main:a.txt|main:y.txt|" ] || fail "the run was not told what main changed: $(cat "$STUB/rerun.2" 2>&1)"
  # Issue 512: and the main it was on before (`from`, the parent of "main moves"), to read what main changed in each.
  [ "$(sed -n 's/^from\t//p' "$STUB/rerun.2")" = "$(git -C "$R" rev-parse "$(sed -n 's/^base\t//p' "$STUB/rerun.2")~1")" ] \
    || fail "the run was not told the main it was on before: $(cat "$STUB/rerun.2" 2>&1)"
  [ "$(jq -c .why "$T/$CASE/cards/c7.testrec")" = '{"a.test":["main changed a.txt"],"c.test":["main changed y.txt"]}' ] \
    || fail "the test line does not say why each file ran: $(cat "$T/$CASE/cards/c7.testrec")"
}

# A retried card: #7 fails b.test's case flaky through its TESTFIXES (3) fix rounds and blocks (runs 1 to 8: four test
# steps, each failed run run once more), a.test and c.test passed. `retry` starts
# the next card from its kept patch (its session leaves it as it was); its run keeps those passes (block() keeps the
# list with the patch) and runs flaky alone, on a main moved since by a commit that changes only z.txt, which none of
# its tests selects: it is told what main changed, z.txt, and of no change of its own. (Main moving by a file a test
# selects: t_rerunrebuilt; told of nothing on the main it was tested on: t_rerunsame, as tests() decides it.)
t_rerunretry() {
  rerunsetup '1 fail flaky' '2 fail flaky' '3 fail flaky' '4 fail flaky' '5 fail flaky' '6 fail flaky' '7 fail flaky' '8 fail flaky'; rerunfiles
  for i in 4 5 6 7; do echo "$GO" > "$STUB/review.$i"; done
  echo 'grep -qx two a.txt || echo two >> a.txt' > "$STUB/build"
  # loop: the block is a card's whole path through its test runs and fix, whose passes block() keeps with the patch
  loop run 1 > /dev/null || fail "run exited non-zero"
  [ "$(st 'select(.step == "blocked") | .issue')" = 7 ] && [ "$(ran 8)" = flaky ] || fail "#7 did not block after failing flaky through its 3 fix rounds: $(st '"\(.step) \(.result)"' | tr '\n' ,)"
  echo z > "$R/z.txt"; git -C "$R" add z.txt; git -C "$R" commit -qm "main moves"
  loop retry 7 > /dev/null || fail "the retry of #7 exited non-zero"
  # The next card's resume (its build stub leaves the kept patch as it was), then its test step (tests(),
  # lib/testrun.sh) on that worktree, as rerunstep runs it.
  resumed 7 'tests "$wt" > /dev/null 2>&1; echo $? > "$T/$CASE/testrc"'
  [ "$(jq -c '[.rc, .mode, .staged, (.beside | index("rerun") != null)]' <<<"$RESUMED")" = '[0,"session",["a.txt"],true]' ] \
    || fail "the retried card did not resume from its kept patch with the list of what its tests passed: $RESUMED"
  [ "$(ran 9)" = flaky ] && [ "$(cat "$T/$CASE/testrc")" = 0 ] \
    || fail "the retried card did not keep the passes of its last run: $(ran 9): $(cat "$STUB/rerun.9" 2>&1)"
  [ "$(grep -E $'^(main|changed)\t' "$STUB/rerun.9" | tr '\t\n' ':|')" = "main:z.txt|" ] || fail "the retried card was not told what main changed, and that alone: $(cat "$STUB/rerun.9")"
}

# Bug it catches (O258, O270): the timing maps and the kept passes went to jq as arguments, so a run again that keeps
# 3,000 passes of 90-byte paths timed before passed Linux's 128 KiB limit of one: jq did not start, <worktree>.oldfiles
# was removed, and the test line named none of them carried (slowrec() gave {} for the same list).
t_rerunmanycarried() {
  local wt=$T/$CASE/cards/c7 n
  rerunwt 'echo two >> a.txt' '1 fail flaky' '2 fail flaky'
  ! rerunstep || fail "the first test step passed"
  for i in $(seq 3000); do printf 't/%085d\n' "$i"; done > "$T/$CASE/many" || fail "the list"
  awk '{ print "pass\t" $0 }' "$T/$CASE/many" >> "$wt.rerun" && awk '{ print "TESTRUN sec\t" $0 "\t1\t1" }' "$T/$CASE/many" >> "$wt.times" || fail "the kept passes"
  rerunstep || fail "the step after a fix that made no edit did not pass: $(ran 3)"
  n=$(jq 'length' "$wt.oldfiles" 2>&1); [ "$n" -ge 3000 ] 2>/dev/null || fail "a run again that keeps 3000 timed passes of 90-byte paths wrote no <worktree>.oldfiles of them: $n"
  fx_in 'slowtests "$T/$CASE/cards/c7"; slowrec "$T/$CASE/cards/c7" | jq ".carried | length"' # as card() writes the test line
  [ "$(cat "$T/$CASE/run.out")" -ge 3000 ] 2>/dev/null || fail "slowrec of the 3000 carried files gave no carried list: $(head -c 300 "$T/$CASE/run.out")"
}
# Bug it catches (O257): nothing writes the slow-test record now, but one left from before #349 still kept c.test
# (its issue #9 not landed) off every card's run, with a `pass` and an `off` line in the list the command reads. A card
# that selects c.test runs it: its case three runs.
t_rerunslowoff() {
  rerunwt 'echo two >> a.txt'
  echo '{"filed": [{"file": "c.test", "issue": 9}]}' > "$ST/slow.json"
  rerunstep || fail "the test step did not pass: $(ran 1)"
  [[ " $(ran 1) " == *' three '* ]] \
    || fail "with slow.json naming c.test for open issue #9, the card's run did not run c.test (case three): ran $(ran 1); told $(cat "$STUB/rerun.1" 2>&1)"
}

# Bug: a run killed part-way through a file kept none of that file's cases that had passed, so the run again ran them
# too. Here a.test passes `one` and hangs in `two`: the run again runs `two` and what never began, not `one`.
t_rerunkilledcase() {
  rerunwt 'echo two >> a.txt' '1 hang two'
  tuned '.tunables.testTimeout = 2' rerunstep || fail "the test step did not pass on its run again: $(ran 2)"
  [ "$(ran 1)" = "one two" ] || fail "the first run was not cut off in a.test's second case: $(ran 1)"
  [ "$(sed 1,3d "$STUB/rerun.2" | tr '\t\n' ':|')" = "ok:a.test:one|" ] || fail "the run again was not told which case of the killed file passed: $(cat "$STUB/rerun.2")"
  [ "$(ran 2)" = "two flaky three" ] || fail "the run again did not run just the cases that had not passed: $(ran 2)"
}

# Bug: a run after a fix that timed out kept nothing of the file it was in, so its cases the fix did not select, which
# did not run, ran again (the engine's runner: a fix of one engine file ran that file's cases, the run's time ran out,
# and the passed cases of the card's other files ran again). a.test failed `one` and passed `two`; the fix edits x.txt,
# which selects `one` alone, and `one` hangs: the run again runs `one`, and `two` stays kept.
t_rerunfixtimeoutok() {
  rerunwt 'echo two >> a.txt' '1 fail one' '2 fail one' '3 hang one'; tune '.tunables.testTimeout = 2'
  ! rerunstep || fail "the first test step passed"
  rerunedit 'echo x >> x.txt'; rerunstep || fail "the step after the fix did not pass on its run again: $(ran 4)"
  [ "$(grep $'^changed\t' "$STUB/rerun.3")" = $'changed\tx.txt' ] && [ "$(ran 3)" = one ] \
    || fail "the run after the fix was not of the failed case alone: $(ran 3): $(cat "$STUB/rerun.3" 2>&1)"
  [ "$(sed 1,3d "$STUB/rerun.4" | tr '\t\n' ':|')" = "pass:b.test|pass:c.test|ok:a.test:two|" ] \
    || fail "the run again after the timeout was not told a.test's two still passed: $(cat "$STUB/rerun.4" 2>&1)"
  [ "$(ran 4)" = one ] || fail "the run again after the timeout ran a case that passed and did not run: $(ran 4)"
}

# The same for a file that had passed: a.test passed, the fix edits x.txt, which selects its case `one`, and `one`
# hangs. The run again runs `one` alone, not a.test whole.
t_rerunfixtimeoutpass() {
  rerunwt 'echo two >> a.txt' '1 fail flaky' '2 fail flaky' '3 hang one'; tune '.tunables.testTimeout = 2'
  ! rerunstep || fail "the first test step passed"
  rerunedit 'echo x >> x.txt'; rerunstep || fail "the step after the fix did not pass on its run again: $(ran 4)"
  [ "$(ran 3)" = one ] || fail "the run after the fix was not cut off in a.test's case one: $(ran 3): $(cat "$STUB/rerun.3" 2>&1)"
  [ "$(sed 1,3d "$STUB/rerun.4" | tr '\t\n' ':|')" = "pass:a.test|pass:c.test|fail:a.test:one|" ] \
    || fail "the run again after the timeout was not told a.test passed but for one: $(cat "$STUB/rerun.4" 2>&1)"
  [ "$(ran 4)" = "one flaky" ] || fail "the run again after the timeout did not run just what had not passed: $(ran 4)"
}
