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

# Issue 436: a one-line lint warning cost a card a whole Test run, its one test-fix round and then a block. Each case
# sets the pack's test.checkCommand to $STUB/check, a stand-in lint that notes each run
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
# Card c7's checks after its build session and at the start of its Test step, on fixture state, as card() takes them
# (no card runs): its worktree on main ($FXWT, fx_wt) with the build's <change> staged; donewhen.sh checked() after the
# build; then, as cardland.sh's Test step calls them, treecheck() and testroute checks, and tests() when the route is
# to run them. session() stands for the one fix session: it notes each call in $STUB/sessions and its prompt in
# $STUB/brief, and makes <fix>. The Done-when part of checked() (dwchecked()) passes. run.out holds `checked <exit>`,
# `route <what testroute checks gave>` and, when the tests ran, `tests <exit>`.
ccstep() { # <change> <fix>
  fx_wt "$1" ok.txt ok
  fx_in 'dwchecked() { :; }
    session() { echo x >> "$STUB/sessions"; printf "%s\n" "$2" > "$STUB/brief"; (cd "$1" && '"$2"') > /dev/null 2>&1; echo "{}"; }
    checked c7 7 "$FXWT" "$(issue 7 2026-01-01)" brief build "{}"; echo "checked $?"
    out=$(treecheck "$FXWT"); r=$(testroute checks $?); echo "route $r"; [ -n "$r" ] || { tests "$FXWT" > /dev/null 2>&1; echo "tests $?"; }'
}

# Bugs: the checks run only in the Test step (a session's warning costs a whole Test run before any session sees it);
# a failure goes to review or blocks, or its fix session is not told the line; the Test step runs the checks again on
# the tree the last session's check ran on, or its test command is not given their kept result.
t_checkfix() {
  ccsetup 7
  # The build leaves t.test.sh with a bare sleep before its check; the fix session leaves a wait in its place.
  ccstep 'printf "sleep 1\n[ -e x ]\n" > t.test.sh' 'printf "until [ -e x ]; do :; done\n" > t.test.sh' # sleep: the text of the card's test file the check must find; never run
  # checked() goes on (exit 0) after one fix session; the Test step's checks pass (testroute checks: nothing), so its tests run.
  [ "$(cat "$T/$CASE/run.out")" = $'checked 0\nroute \ntests 0' ] && [ "$(cc sessions)" = 1 ] \
    || fail "the check's failure did not go to one fix session, then on to the Test step's tests: $(cat "$T/$CASE/run.out"), $(cc sessions) session(s)"
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
  ccsetup 7
  # The build and the fix each leave t.test.sh with the bare sleep and a number of their own after it: the fix changes
  # the tree, so the checks run again on it.
  ccstep 'printf "sleep 1\n[ -e x ]\n# 0\n" > t.test.sh' 'printf "sleep 1\n[ -e x ]\n# 1\n" > t.test.sh' # sleep: the text of the card's test file the check must find; never run
  # checked() fails (exit 1): card() ends there, before any review.
  [ "$(head -n 1 "$T/$CASE/run.out")" = "checked 1" ] && [ "$(cc sessions)" = 1 ] && [ "$(cc checks)" = 2 ] \
    && st 'select(.issue == 7 and .step == "blocked") | .reason' | grep -q "^the project's checks failed again after their one fix session; nothing landed." \
    || fail "a second check failure did not block #7 before any review: $(cat "$T/$CASE/run.out"), $(cc sessions) session(s), $(cc checks) check run(s): $(st 'select(.issue == 7 and .step == "blocked") | .reason')"
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
  # loop: the Test step writes its checks line itself (cardland.sh), and only the card's next test run shows it is still its first
  loop run --only 8 >/dev/null || fail "run of #8 exited non-zero"
  # One run of the three files, each alone through test.fileCommand: three test commands, none in the failed step.
  [ "$(ccsteps 8)" = "build test review test fix review test landed" ] && [ "$(cc tests)" = 3 ] \
    || fail "the check's failure in the Test step did not end it before any test ran and go to a fix session: $(ccsteps 8), $(cc tests) test run(s)"
  [ "$(st 'select(.issue == 8 and .step == "test") | select(.checks) | [.result, .reason, (.failures.files | map(.file))] | tojson')" \
    = "[\"fail\",\"the project's checks failed (test.checkCommand: bash $STUB/check); no test file ran\",[\"bash $STUB/check\"]]" ] \
    && st 'select(.issue == 8 and .step == "test" and .checks) | .tail' | grep -q '^bad.txt:1: lint: a stand-in warning$' \
    || fail "the Test step's line does not hold one failure naming the check and its line: $(st 'select(.issue == 8 and .step == "test")')"
  [ "$(st 'select(.issue == 8 and .step == "test" and (.checks | not) and .before == null) | [.result, .refused] | tojson')" = '["pass",null]' ] \
    || fail "the first run of the card's tests, after a step that ran none, was not its first: $(st 'select(.issue == 8 and .step == "test")')"
}

# Bug: a check failure counted as the changed tests failing, so a card whose test-fix rounds were used was blocked as
# "the changed tests failed again after their 3 fix rounds". Card c7's Test step on fixture state, its TESTFIXES (3)
# test-fix rounds used (card()'s tfix) and already fitted onto main (tmain): its worktree holds bad.txt, so the step's checks fail
# (treecheck() exit 1), and testroute checks sends it to the checks' one fix session, where a failure of its tests
# (testroute <worktree>) blocks it.
t_checkround() {
  ccsetup 9
  fx_wt 'echo x > bad.txt' ok.txt ok
  fx_in 'tfix=3 tmain=1 repaired=""; out=$(treecheck "$FXWT"); r=$?; echo "checks $r $(testroute checks $r)"; echo "tests $(testroute "$FXWT")"'
  [ "$(cat "$T/$CASE/run.out")" = $'checks 1 checkfix\ntests block' ] \
    || fail "a check failure after the test-fix rounds (tfix=3) did not go to a fix session, unlike a failure of the tests: $(cat "$T/$CASE/run.out")"
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
