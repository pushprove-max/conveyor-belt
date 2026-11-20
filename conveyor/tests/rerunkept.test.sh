#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: what a test step keeps as passed, and what it runs again, when HEAD or main moved under the card, a
# card is retried, a full run is refused, a file is kept off for its time, or a run's time runs out (tests()).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# rerunsetup, rerunfiles, ran, rerunedit, rerunstep, rerunwt and tline are rerun.test.sh's: the runner loads every case
# file into one shell. A change to rerun.test.sh runs this file too, through its link in .conveyor/test-links.json.

# Bug this guards against: a session that brings the change onto another HEAD and edits it where main changed
# nothing (here a.txt, the card's own file, on a HEAD whose new commit changes no file) has edited it outside any
# conflict: its passes are not kept, and the run after it is of the whole selection.
t_rerunmoved() {
  rerunsetup '1 fail flaky' '2 fail flaky'; rerunfiles
  echo 'echo two >> a.txt; [ "$(wc -l < "$STUB/sessions")" = 1 ] || git update-ref HEAD "$(git commit-tree "HEAD^{tree}" -p HEAD -m moved)"' > "$STUB/build"
  loop run 1 > /dev/null || fail "run exited non-zero"
  [ "$(st 'select(.step == "fix") | .step' | wc -l)" = 1 ] || fail "no fix session ran"
  [ ! -e "$STUB/rerun.3" ] && [ "$(ran 3)" = "one two flaky three" ] || fail "the run after a session that moved HEAD was not of the whole selection: $(ran 3)"
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
  # The failed step's test line, as card() records it: the card was tested before (testedbefore()).
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

# A merge in doubt (the session that brought the change onto main edited it outside the conflicts: here b.txt beside
# the conflict in a.txt) runs the whole selection, and refuses nothing: the merge may have broken what passed before.
t_rerunmergedoubt() {
  rerunsetup; rerunfiles
  echo l1 > "$R/a.txt"; git -C "$R" add a.txt; git -C "$R" commit -qm "a.txt"
  echo "if grep -q '^# Landing conflict' \"\$STUB/brief\"; then sed -i.bak 's/^main1\$/seven/' a.txt; rm -f a.txt.bak; echo b > b.txt; else sed -i.bak 's/^l1\$/seven/' a.txt; rm -f a.txt.bak; fi" > "$STUB/build"
  echo '[ -e "$STUB/moved" ] || { : > "$STUB/moved"; echo main1 > "$R/a.txt"; git -C "$R" add a.txt; git -C "$R" commit -qm "main moves"; }' > "$STUB/pre"
  loop run 1 > /dev/null || fail "run exited non-zero"
  st 'select(.step == "rebase") | .reason' | grep -q '^rebase onto main conflicts' || fail "#7 did not go to the rebuild session: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
  [ "$(ran 2)" = "one two flaky three" ] && [ ! -e "$STUB/rerun.2" ] || fail "the run after a merge in doubt was not of the whole selection: $(ran 2): $(cat "$STUB/rerun.2" 2>&1)"
  [ "$(tline 2 '.refused // "none"')" = none ] || fail "a merge in doubt's whole run was refused: $(tline 2 tojson)"
}

# Bug (issue 460: #415 ran its whole selection again each time main moved under it, though main's new commits touched
# almost nothing its tests use). #7 changes a.txt and passes; during its run main changes a.txt's same line, and y.txt,
# which selects c.test. The rebuild session brings #7 onto main, and the run after it keeps the passes of the first:
# a.test (main changed its a.txt) and c.test run, b.test, which nothing main changed selects, does not.
t_rerunrebuilt() {
  rerunsetup; rerunfiles; linkset '{"a.txt": ["a.test", "b.test", "c.test"], "y.txt": ["c.test"]}'
  echo 'y.txt c.test' >> "$STUB/map"
  echo l1 > "$R/a.txt"; git -C "$R" add a.txt; git -C "$R" commit -qm "a.txt"
  echo "if grep -q '^# Landing conflict' \"\$STUB/brief\"; then sed -i 's/^main1\$/seven/' a.txt; else sed -i 's/^l1\$/seven/' a.txt; fi" > "$STUB/build"
  echo '[ -e "$STUB/moved" ] || { : > "$STUB/moved"; echo main1 > "$R/a.txt"; echo y > "$R/y.txt"; git -C "$R" add a.txt y.txt; git -C "$R" commit -qm "main moves"; }' > "$STUB/pre"
  loop run 1 > /dev/null || fail "run exited non-zero"
  st 'select(.step == "rebase") | .reason' | grep -q '^rebase onto main conflicts' || fail "#7 did not go to the rebuild session: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
  [ "$(ran 1)" = "one two flaky three" ] && [ "$(ran 2)" = "one two three" ] \
    || fail "the run after the rebuild onto main did not keep b.test's pass: first $(ran 1), then $(ran 2): $(cat "$STUB/rerun.2" 2>&1)"
  [ "$(grep -E $'^(main|changed)\t' "$STUB/rerun.2" | tr '\t\n' ':|')" = "main:a.txt|main:y.txt|" ] || fail "the run was not told what main changed: $(cat "$STUB/rerun.2" 2>&1)"
  # Issue 512: and the main it was on before (`from`, the parent of "main moves"), to read what main changed in each.
  [ "$(sed -n 's/^from\t//p' "$STUB/rerun.2")" = "$(git -C "$R" rev-parse "$(sed -n 's/^base\t//p' "$STUB/rerun.2")~1")" ] \
    || fail "the run was not told the main it was on before: $(cat "$STUB/rerun.2" 2>&1)"
  [ "$(tline 2 '.why | tojson')" = '{"a.test":["main changed a.txt"],"c.test":["main changed y.txt"]}' ] \
    || fail "the test line does not say why each file ran: $(tline 2 .why)"
  [ "$(st 'select(.step == "landed") | .issue')" = 7 ] && grep -qx seven "$R/a.txt" || fail "#7 did not land: $(st '"\(.step) \(.result)"' | tr '\n' ,)"
}

# A retried card: #7 fails b.test's case flaky through its fix and blocks, a.test and c.test passed. `retry` starts
# the next card from its kept patch (its session leaves it as it was); its run keeps those passes (block() keeps the
# list with the patch) and runs flaky alone, on a main moved since by a commit that changes only z.txt, which none of
# its tests selects: it is told what main changed, z.txt, and of no change of its own. (Main moving by a file a test
# selects: t_rerunrebuilt; told of nothing on the main it was tested on: t_rerunsame, as tests() decides it.)
t_rerunretry() {
  rerunsetup '1 fail flaky' '2 fail flaky' '3 fail flaky' '4 fail flaky'; rerunfiles
  for i in 4 5; do echo "$GO" > "$STUB/review.$i"; done
  echo 'grep -qx two a.txt || echo two >> a.txt' > "$STUB/build"
  loop run 1 > /dev/null || fail "run exited non-zero"
  [ "$(st 'select(.step == "blocked") | .issue')" = 7 ] && [ "$(ran 4)" = flaky ] || fail "#7 did not block after failing flaky through its fix: $(st '"\(.step) \(.result)"' | tr '\n' ,)"
  echo z > "$R/z.txt"; git -C "$R" add z.txt; git -C "$R" commit -qm "main moves"
  loop retry 7 > /dev/null && loop run 1 > /dev/null || fail "the retried #7 did not run"
  [ "$(ran 5)" = flaky ] && [ "$(st 'select(.step == "test") | .result' | tail -n 1)" = pass ] \
    || fail "the retried card did not keep the passes of its last run: $(ran 5): $(cat "$STUB/rerun.5" 2>&1)"
  [ "$(grep -E $'^(main|changed)\t' "$STUB/rerun.5" | tr '\t\n' ':|')" = "main:z.txt|" ] || fail "the retried card was not told what main changed, and that alone: $(cat "$STUB/rerun.5")"
}

# Issue 523: c.test is kept off card runs for its CPU seconds (slowoff(): its issue #9 has not landed). Bug it
# catches: the run again's list (rerunlist()) lost the `off` line, so a selection that runs what did not finish (the
# engine's runner, .conveyor/test-changed.sh) ran the slow file again on the run again. The run again is told it too.
t_rerunslowoff() {
  rerunwt 'echo two >> a.txt' '1 fail flaky'
  echo '{"filed": [{"file": "c.test", "issue": 9}]}' > "$ST/slow.json"
  rerunstep || fail "the test step did not pass on its run again: $(ran 2)"
  grep -qxF $'off\tc.test' "$STUB/rerun.1" || fail "the first run was not told c.test is kept off: $(cat "$STUB/rerun.1" 2>&1)"
  [ "$(ran 2)" = flaky ] && grep -qxF $'off\tc.test' "$STUB/rerun.2" \
    || fail "the run again was not told c.test is kept off: $(ran 2): $(cat "$STUB/rerun.2" 2>&1)"
}

# Bug it catches (issue 769): each card's test step read all the card records from the state store (a python3 start)
# to match them against a slow-test record that names no file (none is written now), so a batch run of two cards
# made two calls more and went past stdbcalls.test.sh's count under load. With no record, or one that names no file,
# slowoffs() keeps none off and asks the store nothing; t_rerunslowoff is the record that names one.
t_rerunslownone() {
  # shellcheck disable=SC2034 # HERE is read by stdb(), for the folder state.py is in
  local s=$T/$CASE/st HERE=$SRC STATE SLOWFILED CALLS=$T/$CASE/calls out r
  STATE=$s/cards.jsonl SLOWFILED=$s/slow.json; mkdir -p "$s"
  eval "$(sed -n '/^declare -A ASKED_K/p; /^stdb() {/,/^}/p' "$SRC/lib/records.sh")"
  eval "$(sed -n '/^slowoffs() {/,/^}/p' "$SRC/lib/testrun.sh")"
  python3() { echo x >> "$CALLS"; command python3 "$@"; } # each state store call, counted
  echo '{"card":"c1","issue":9,"step":"picked","time":"2026-01-01T00:00:00Z"}' > "$STATE"
  for r in none '{"filed": []}' '{"filed": [{"issue": 9}]}'; do
    [ "$r" = none ] || echo "$r" > "$SLOWFILED"
    : > "$CALLS"; out=$(slowoffs)
    [ -z "$out" ] && [ ! -s "$CALLS" ] || fail "with the slow-test record $r, slowoffs kept '$out' off and asked the state store $(wc -l < "$CALLS") times, not 0"
  done
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
