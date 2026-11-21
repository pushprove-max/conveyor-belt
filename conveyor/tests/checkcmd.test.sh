#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the project's checks (the pack's test.checkCommand, donewhen.sh treecheck()) after each session and at the start
# of a card's Test step.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Issue 436: a one-line lint warning cost a card a whole Test run, its one test-fix round and then a block. Each card
# case runs one issue's card with the pack's test.checkCommand set to $STUB/check, a stand-in lint that notes each run
# in $STUB/checks and fails naming its line when t.test.sh starts with a bare sleep, or when bad.txt is in the tree.
# The stub test command notes each run in $STUB/tests and what the step's log folder holds of the kept checks in
# $STUB/kept. The push after a landing is off: no case here checks it.
ccsetup() { # <issue number>
  setup "[$(issue "$1" 2026-01-01)]"
  jq -c '.rules.push = false' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json" || fail "the control record"
  tune --arg c "bash $STUB/check" '.test.checkCommand = $c'
  printf '%s\n' 'echo x >> "$STUB/checks"' '[ ! -e bad.txt ] || { echo "bad.txt:1: lint: a stand-in warning"; exit 1; }' \
    'l=$(grep -n "^sleep" t.test.sh 2>/dev/null) || exit 0' 'echo "t.test.sh:${l%%:*}: test lint: a bare sleep, then a check"; exit 1' > "$STUB/check"
  echo 'echo x >> "$STUB/tests"; ls "$CONVEYOR_TEST_LOG/checks" >> "$STUB/kept" 2>/dev/null; :' > "$STUB/test-cmd"
}
cc() { wc -l < "$STUB/$1" 2>/dev/null | tr -d ' ' || echo 0; } # <stub log>: its lines
ccsteps() { st "select(.issue == $1 and (.step | IN(\"build\", \"fix\", \"review\", \"test\", \"landed\", \"blocked\"))) | .step" | paste -sd' ' -; } # <issue>

# Bugs: the checks run only in the Test step (a session's warning costs a whole Test run before any session sees it);
# a failure goes to review or blocks, or its fix session is not told the line; the Test step runs the checks again on
# the tree the last session's check ran on, or its test command is not given their kept result.
t_checkfix() {
  ccsetup 7
  # The build leaves t.test.sh with a bare sleep before its check; the fix session leaves a wait in its place.
  b='if [ "$(wc -l < "$STUB/sessions")" = 1 ]; then printf "sleep 1\n[ -e x ]\n" > t.test.sh' # sleep: the text of the card's test file the check must find; never run
  printf '%s\n' "$b" 'else printf "until [ -e x ]; do :; done\n" > t.test.sh; fi' > "$STUB/build"
  echo "$GO" > "$STUB/review.1"
  loop run --only 7 >/dev/null || fail "run of #7 exited non-zero"
  [ "$(ccsteps 7)" = "build fix review test landed" ] && [ "$(cc sessions)" = 2 ] \
    || fail "the check's failure did not go to one fix session before any review or test, or #7 did not land: $(ccsteps 7), $(cc sessions) session(s)"
  grep -q "^# The project's checks failed" "$STUB/brief" && grep -qF 't.test.sh:1: test lint: a bare sleep, then a check' "$STUB/brief" \
    || fail "the fix session was not told the check's line: $(cat "$STUB/brief")"
  [ "$(st 'select(.issue == 7 and .step == "fix") | .reason')" = "the project's checks failed (test.checkCommand)" ] || fail "the fix line does not say why: $(st 'select(.issue == 7 and .step == "fix")')"
  # Twice: after the build and after the fix. The Test step on the fixed tree reuses that run, and its test command
  # finds the kept result in its log folder (checks/<commit>-<tree>.rc).
  [ "$(cc checks)" = 2 ] && [ "$(cc tests)" -ge 1 ] && grep -qE '^[0-9a-f]+-[0-9a-f]+\.rc$' "$STUB/kept" \
    || fail "the Test step ran the checks again on the checked tree, or its test command was not given their result: $(cc checks) check run(s), $(cc tests) test run(s), kept '$(cat "$STUB/kept" 2>/dev/null)'"
}

# Bugs: checks that still fail after their one fix session send the card round fix sessions for ever, or go to review.
t_checkblock() {
  ccsetup 10
  # Each session leaves t.test.sh with the bare sleep and its own number after it: the fix changes the tree, so the
  # checks run again on it.
  b='printf "sleep 1\n[ -e x ]\n# %s\n" "$(wc -l < "$STUB/sessions")" > t.test.sh' # sleep: the text of the card's test file the check must find; never run
  printf '%s\n' "$b" > "$STUB/build"
  loop run --only 10 >/dev/null
  [ "$(ccsteps 10)" = "build fix blocked" ] && [ ! -e "$STUB/reviews" ] && [ "$(cc checks)" = 2 ] \
    && st 'select(.issue == 10 and .step == "blocked") | .reason' | grep -q "^the project's checks failed again after their one fix session; nothing landed." \
    || fail "a second check failure did not block #10 before any review: $(ccsteps 10), $(cc checks) check run(s): $(st 'select(.issue == 10 and .step == "blocked") | .reason')"
}

# Bugs: a check that fails at the start of a Test step lets the step's test files run, or fails each of them; the
# step's line does not name the check; a line of no test run makes the card's first test run a refused full run.
t_checkstep() {
  ccsetup 8
  # Three test files; main gains bad.txt during the review, so the card is fitted onto a tree its sessions' checks
  # never saw. Its fix session takes bad.txt out.
  echo 'if [ -e bad.txt ]; then git rm -q bad.txt; else for f in a b c; do echo "# $f" > "$f.test.sh"; done; fi' > "$STUB/build"
  echo "$GO" | tee "$STUB/review.1" > "$STUB/review.2"
  echo '[ "$(wc -l < "$STUB/reviews")" != 1 ] || { echo x > "$R/bad.txt"; git -C "$R" add bad.txt; git -C "$R" commit -qm bad; }' > "$STUB/review-cmd"
  loop run --only 8 >/dev/null || fail "run of #8 exited non-zero"
  # One run of the three files, each alone through test.fileCommand: three test commands, none in the failed step.
  [ "$(ccsteps 8)" = "build review test fix review test landed" ] && [ "$(cc tests)" = 3 ] \
    || fail "the check's failure in the Test step did not end it before any test ran and go to a fix session: $(ccsteps 8), $(cc tests) test run(s)"
  [ "$(st 'select(.issue == 8 and .step == "test") | select(.checks) | [.result, .reason, (.failures.files | map(.file))] | tojson')" \
    = "[\"fail\",\"the project's checks failed (test.checkCommand: bash $STUB/check); no test file ran\",[\"bash $STUB/check\"]]" ] \
    && st 'select(.issue == 8 and .step == "test" and .checks) | .tail' | grep -q '^bad.txt:1: lint: a stand-in warning$' \
    || fail "the Test step's line does not hold one failure naming the check and its line: $(st 'select(.issue == 8 and .step == "test")')"
  [ "$(st 'select(.issue == 8 and .step == "test" and (.checks | not)) | [.result, .refused] | tojson')" = '["pass",null]' ] \
    || fail "the first run of the card's tests, after a step that ran none, was not its first: $(st 'select(.issue == 8 and .step == "test")')"
}

# Bug: a check failure counted as the changed tests failing, so a card whose test-fix round was used was blocked as
# "the changed tests failed again after their one fix round".
t_checkround() {
  ccsetup 9
  # Its first test run fails, and the run again too: the test-fix round. Main gains bad.txt during the review after
  # that fix. The card gave way for its fix, so its tests pass first on its own base; fitted onto main then, its next
  # Test step fails on the check alone, its test-fix round used. The fix session after it takes bad.txt out.
  echo 'if [ -e bad.txt ]; then git rm -q bad.txt; else echo "$(wc -l < "$STUB/sessions")" >> a.txt; fi' > "$STUB/build"
  echo "$GO" | tee "$STUB/review.1" "$STUB/review.2" > "$STUB/review.3"
  echo '[ "$(wc -l < "$STUB/reviews")" != 2 ] || { echo x > "$R/bad.txt"; git -C "$R" add bad.txt; git -C "$R" commit -qm bad; }' > "$STUB/review-cmd"
  echo 'echo x >> "$STUB/tests"; [ "$(wc -l < "$STUB/tests")" -gt 2 ] && exit 0; echo "FAIL widget.test.ts"; printf "%s\n" "== widget.test.ts" "-- FAIL widget.test.ts" >> "$CONVEYOR_TEST_LOG/run.log"; exit 1' > "$STUB/test-cmd"
  loop run --only 9 >/dev/null || fail "run of #9 exited non-zero"
  [ "$(ccsteps 9)" = "build review test fix review test test fix review test landed" ] && [ "$(cc sessions)" = 3 ] \
    && [ "$(st 'select(.issue == 9 and .step == "test") | [.result, (.checks // false)] | tojson' | paste -sd' ' -)" = '["fail",false] ["pass",false] ["fail",true] ["pass",false]' ] \
    || fail "a check failure after the test-fix round did not go to a fix session, or blocked #9: $(ccsteps 9): $(st 'select(.issue == 9 and (.step == "test" or .step == "blocked")) | [.result, .reason] | tojson')"
}

# Bug: a pack with no test.checkCommand runs something, fails, or keeps a result: every card would change.
t_checknone() {
  W=$T/$CASE/w; mkdir -p "$W" && git -C "$W" init -q && echo x > "$W/a.txt" || fail "the worktree"
  # shellcheck disable=SC2034 # STATE is read by the sourced lib/testrun.sh
  out=$( (STATE=$T/$CASE/cards.jsonl; . "$SRC/lib/testrun.sh" || exit 3; packget() { printf -v "$2" '%s' ''; }; treecheck "$W") 2>&1); rc=$?
  [ $rc = 0 ] && [ -z "$out" ] && [ ! -e "$W.checks" ] || fail "with no test.checkCommand, the checks did not pass silently and keep nothing: exit $rc, '$out', $(ls "$W.checks" 2>&1)"
}

# Bug (#786, checkblock red now and then): donewhen.sh treeof() copied the index with a new time, so git trusted the stat of a file
# staged in the same second as a same-size rewrite of it, and gave the old tree: the checks after a fix session reused
# the build's kept failure, and donewhen.sh asks() could read a fix as no change.
t_checkracy() {
  W=$T/$CASE/w; mkdir -p "$W" && git -C "$W" init -q || fail "the worktree"
  local i s
  # Stage a.txt and rewrite it, same size, inside one second (up to three tries), then let that second end.
  for ((i = 0; i < 3; i++)); do
    until [ "${EPOCHREALTIME: -6}" -lt 300000 ]; do sleep 0.05; done # sleep: the clock must reach the start of a second
    s=${EPOCHREALTIME%%[.,]*}
    echo 1 > "$W/a.txt" && git -C "$W" add -A && echo 2 > "$W/a.txt" || fail "the files"
    [ "${EPOCHREALTIME%%[.,]*}" != "$s" ] || break
  done
  until [ "${EPOCHREALTIME%%[.,]*}" != "$s" ]; do sleep 0.05; done # sleep: the second the index was written must end
  # shellcheck disable=SC2034 # STATE is read by the sourced lib/testrun.sh
  t=$( (STATE=$T/$CASE/cards.jsonl; . "$SRC/lib/testrun.sh" || exit 3; treeof "$W") 2>&1)
  [ "$t" = "$(git -C "$W" add -A && git -C "$W" write-tree)" ] || fail "treeof() gave the tree from before a same-second, same-size rewrite: '$t'"
}
