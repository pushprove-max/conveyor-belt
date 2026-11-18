#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the test results cache (tests(): cachekeep(), cacheoff()). A test file that passed with the same
# inputs is not run again by a later run, of this card or another; one whose inputs changed runs, and so does one
# whose command names no inputs for it.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Main holds two test files: a.test, whose command names a.txt as its input (`TESTRUN inputs`), and b.test, which it
# names no inputs for. The command runs each file the list (CONVEYOR_TEST_RERUN) does not name as passed, writing
# `<card> <file>` to $STUB/ran for each, and both pass. Card c7, whose change is d.txt (which neither file reads), runs
# them both once, on main as it was then; main then moves (c.txt, which neither reads either), and the second card's
# run is made on main as it is now.
cachesetup() {
  setup "$(jq -cs . <(issue 7 2026-01-01))"
  echo 'a' > "$R/a.test"; echo 'b' > "$R/b.test"; git -C "$R" add -A && git -C "$R" commit -qm tests || fail "main's test files could not be committed"
  cat > "$STUB/test-cmd" <<'EOF'
L=$CONVEYOR_TEST_LOG/run.log; RR=${CONVEYOR_TEST_RERUN:-/dev/null}
for f in a.test b.test; do
  ! grep -qxF "pass	$f" "$RR" || continue
  echo "${PWD##*/} $f" >> "$STUB/ran"; echo "== $f" >> "$L"
  [ "$f" != a.test ] || printf 'TESTRUN inputs\ta.test\ta.txt\n' >> "$L"
  echo "-- ok $f" >> "$L"
done
EOF
  cachestep c7 'echo d > d.txt' || fail "the first card's test step failed"
  echo moved > "$R/c.txt"; git -C "$R" add c.txt && git -C "$R" commit -qm moved || fail "main could not move"
}
cachestep() { # <card> <its change, a shell edit staged in its worktree on main>: the card's test step, its own tests()
  local wt=$T/$CASE/cards/$1
  git -C "$R" worktree add -q --detach "$wt" && (cd "$wt" && eval "$2") && git -C "$wt" add -A || return 1
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" || exit 1
    names || exit 1; tests "$wt" || exit; testrec "$wt" 0 0 > "$wt.rec" ) > /dev/null 2>&1
}

# D1, D3: card c8 changes c.txt, which a.test does not read, after main moved. a.test passed before with the same
# inputs: it is not run, and the run's log, and so its test line's why (testrec()), says so. b.test names no inputs: it runs
# again, as before the cache. Bug it catches: a test file that passed was run again by every later card.
t_testcacheskip() {
  cachesetup
  cachestep c8 'echo three > c.txt' || fail "the second card's test step failed"
  [ "$(sed -n 's/^c8 //p' "$STUB/ran" | tr '\n' ' ')" = "b.test " ] \
    || fail "the second card did not run b.test alone (a.test kept off by the cache): $(cat "$STUB/ran")"
  grep -qxF $'TESTRUN why\ta.test\tpassed before with the same inputs' "$T/$CASE/cards/c8.testlog/cache" \
    || fail "the run's log does not say why a.test did not run: $(cat "$T/$CASE/cards/c8.testlog"/* 2>&1)"
  [ "$(jq -c '.why["a.test"]' "$T/$CASE/cards/c8.rec")" = '["passed before with the same inputs"]' ] \
    || fail "the test line's why does not say why a.test did not run: $(cat "$T/$CASE/cards/c8.rec")"
  # The line's ran names the file that ran, not the one the cache kept off (which why names): bug it catches, the
  # landing pull request (landpr()) listing a.test as run and leaving out b.test.
  [ "$(jq -c .ran "$T/$CASE/cards/c8.rec")" = '["b.test"]' ] || fail "the test line's ran is not b.test alone: $(cat "$T/$CASE/cards/c8.rec")"
  # And the record check takes the line (a field it does not know sets the whole line aside).
  jq -c '{card: "c8", issue: 7, step: "test", time: "2026-01-01T00:00:00Z", tokens: {claude: 0, codex: 0}, result: "pass", sha: "", reason: ""} + .' \
    "$T/$CASE/cards/c8.rec" > "$T/$CASE/line.jsonl" && recok "$T/$CASE/line.jsonl" testrec
  ! grep -q $'^off\tb.test' "$T/$CASE/cards/c8.rerun" 2>/dev/null || fail "b.test, with no inputs line, was kept off"
}

# D2: card c8 changes a.txt, a.test's input: a.test runs again, and so does b.test. Bug it catches: a file kept off
# though what it reads changed.
t_testcacheinput() {
  cachesetup
  cachestep c8 'echo three >> a.txt' || fail "the second card's test step failed"
  [ "$(sed -n 's/^c8 //p' "$STUB/ran" | tr '\n' ' ')" = "a.test b.test " ] \
    || fail "the second card did not run a.test after its input changed: $(cat "$STUB/ran")"
  [ ! -e "$T/$CASE/cards/c8.testlog/cache" ] || fail "the run's log says a file was kept off: $(cat "$T/$CASE/cards/c8.testlog/cache")"
}
