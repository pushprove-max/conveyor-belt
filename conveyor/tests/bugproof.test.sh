#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the bug-card check (bugproof()): a bug card's new tests must fail on main's code without the fix.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# One card of #7 with the given labels: its build fixes a.txt (adds `two`; runs $FIX in its place when set, `:` for no
# fix) and, unless <test> is empty, adds a.test.sh holding <test>. The run on main (a worktree under cards/mainrun/) notes its folder and staged files in
# $STUB/mainran and runs a.test.sh, then what $MAINRUN holds, if any; the reviewer's prompt is kept in $STUB/asked;
# one GO review.
bugcard() { # <test> <label>...
  local t=$1; shift
  setup "[$(issue 7 2026-01-01 "$@")]"
  sed -i 's|^cat > /dev/null; echo x|cat > "$STUB/asked"; echo x|' "$STUB/codex"
  echo "$GO" > "$STUB/review.1"
  echo "${FIX-echo two >> a.txt}${t:+; printf '%s\n' '$t' > a.test.sh}" > "$STUB/build"
  echo '{ pwd; git diff --cached --name-only; } >> "$STUB/mainran"; '"${MAINRUN:-bash a.test.sh}" > "$STUB/mainrun-cmd"
  loop run >/dev/null || fail "run exited non-zero"
}

# D1. Bug it catches: a bug card whose new test fails without the fix (it proves the fix) is sent back to build, or
# its test runs on main with the fix in it, or the review is not shown the result. The test runs on main's code with
# the card's test file alone; one build session; the review sees that it failed there; the card lands.
t_bugfails() {
  bugcard 'grep -qx two a.txt' bug
  [ "$(wc -l < "$STUB/sessions")" = 1 ] && [ "$(st 'select(.step == "build") | .result' | wc -l)" = 1 ] \
    || fail "a bug card whose new test fails on main went back to build: $(st 'select(.step == "build")')"
  [ "$(sed 1d "$STUB/mainran" | tr '\n' ' ')" = 'a.test.sh ' ] && [[ $(head -1 "$STUB/mainran") == */cards/mainrun/* ]] \
    || fail "the run on main was not of main's code with the card's test file alone: $(cat "$STUB/mainran" 2>&1)"
  grep -qx '# The bug-card check' "$STUB/asked" && grep -q '^The run failed there (exit 1)' "$STUB/asked" \
    || fail "the review was not shown that the new test fails on main: $(cat "$STUB/asked")"
  [ -n "$(st 'select(.step == "landed") | .sha')" ] && [ -z "$(ls "$T/$CASE/cards")" ] || fail "the card did not land, or left a worktree: $(ls "$T/$CASE/cards")"
}

# D2. Bug it catches: a bug card whose new test passes on main's code (it proves nothing of the fix) goes on to review
# as if proven. It goes back to its build session, told why, its build line saying so; the check runs again after
# it, and as the test still passes there the card is blocked with that reason, never reviewed.
t_bugpasses() {
  bugcard 'grep -qx one a.txt' bug
  [ "$(st 'select(.step == "build") | .reason // ""' | tr '\n' '|')" = "|the new tests pass without the fix, so they do not prove it|" ] \
    || fail "the card did not go back to its build with the reason: $(st 'select(.step == "build")')"
  grep -q '^# Back to the build: the new tests pass without the fix, so they do not prove it$' "$STUB/brief" && grep -qx -- '- a.test.sh' "$STUB/brief" \
    || fail "the second build session was not told why, naming the test file: $(tail -n 20 "$STUB/brief")"
  [ "$(grep -c '/cards/mainrun/' "$STUB/mainran")" = 2 ] || fail "the check did not run on main after each build: $(cat "$STUB/mainran" 2>&1)"
  [ ! -e "$STUB/asked" ] && [ "$(st 'select(.step == "blocked") | .reason')" = "build: the new tests pass without the fix, so they do not prove it" ] \
    || fail "a bug card whose test still passed on main after its second build was not blocked before review: $(st 'select(.step | IN("review", "blocked"))')"
  loop check || fail "the record check refuses a build line with the reason"
}

# Bug it catches: a run on main that fails only because its runner stopped it (its own check refused the run, as an
# area map without the card's new test file does) is taken for a test that fails without the fix. Here the runner's
# log says a.test.sh ran and passed, and the runner exits 1: the card goes back to its build, told no test failed.
t_bugrunner() {
  MAINRUN='echo "== a.test.sh" > "$CONVEYOR_TEST_LOG/r"; bash a.test.sh && echo "-- ok a.test.sh" >> "$CONVEYOR_TEST_LOG/r"; exit 1' \
    bugcard 'grep -qx one a.txt' bug
  [ "$(st 'select(.step == "build") | .reason // ""' | tr '\n' '|')" = "|the new tests pass without the fix, so they do not prove it|" ] \
    && grep -q '^The run failed there (exit 1), but no test failed in it' "$STUB/brief" \
    || fail "a runner's own failure on main was taken for the new test failing: $(st 'select(.step == "build")'; tail -n 20 "$STUB/brief")"
}

# Bug it catches: a bug card whose change is a test file alone (a test fixed for a red main, which passes on main's
# code too) is blocked, as with no fix to take out its test passes "without the fix". It is not run on main, has one
# build session, its review is told the change is test-only, and it lands.
t_bugtestonly() {
  FIX=: bugcard 'grep -qx one a.txt' bug
  [ "$(wc -l < "$STUB/sessions")" = 1 ] && [ ! -e "$STUB/mainran" ] \
    || fail "a test-only bug card was run on main or sent back to build: $(st 'select(.step == "build")'; cat "$STUB/mainran" 2>&1)"
  grep -qx '# The bug-card check' "$STUB/asked" && grep -q '^The change is test-only: ' "$STUB/asked" \
    || fail "the review was not told the change is test-only: $(cat "$STUB/asked" 2>&1)"
  [ -n "$(st 'select(.step == "landed") | .sha')" ] || fail "a test-only bug card did not land: $(st 'select(.step | IN("blocked", "landed"))')"
}

# Bug it catches: a bug card that adds no test at all goes to review unchecked. It is told the same; its only runs on
# main are of its whole change (does it select a test? Here it does: its run is not "nothing selected").
t_bugnotest() {
  bugcard '' bug
  [ "$(st 'select(.step == "build") | .reason // ""' | tr '\n' '|')" = "|the new tests pass without the fix, so they do not prove it|" ] \
    && grep -q '^The change adds or changes no test file' "$STUB/brief" || fail "a bug card with no test did not go back to its build, told so: $(st 'select(.step == "build")')"
  [ "$(grep -v '/cards/mainrun/' "$STUB/mainran" | sort -u)" = a.txt ] || fail "a card with no test file ran other than its whole change on main: $(cat "$STUB/mainran" 2>&1)"
  [ -z "$(st 'select(.step == "bugproof")')" ] || fail "a code change with no test was let skip the check: $(st 'select(.step == "bugproof")')"
}

# A bug card of #7 whose build only rewords a comment of s.sh (`# an old word` becomes `# a new word`), on a main that
# holds s.sh and w.test.sh holding <test>; its issue's body is <body>. The run on main runs each file its
# CONVEYOR_TEST_RERUN list names as `fail`; with none, it selects nothing (its log says files=0), as a runner does for a
# comment-only change. Each run notes in $STUB/mainran its staged files, whether s.sh holds the fix and its fail lines.
commentcard() { # <test> <body>
  setup "[$(issue 7 2026-01-01 bug | jq -c --arg b "$2" '.body = $b')]"
  printf '#!/usr/bin/env bash\n# an old word\n' > "$R/s.sh"; printf '%s\n' "$1" > "$R/w.test.sh"
  git -C "$R" add s.sh w.test.sh && git -C "$R" commit -qm 'a comment and its test' && git -C "$R" push -q origin main || fail "main's files"
  sed -i 's|^cat > /dev/null; echo x|cat > "$STUB/asked"; echo x|' "$STUB/codex"
  echo "$GO" > "$STUB/review.1"
  echo "printf '#!/usr/bin/env bash\n# a new word\n' > s.sh" > "$STUB/build"
  cat > "$STUB/mainrun-cmd" <<'EOF'
n=0 r=0; while IFS=$'\t' read -r k f; do [ "$k" = fail ] || continue; n=$((n + 1)); bash "$f" || r=1; done < "${CONVEYOR_TEST_RERUN:-/dev/null}"
echo "staged: $(git diff --cached --name-only | tr '\n' ' ')fix: $(grep -c new s.sh) ran: $n" >> "$STUB/mainran"
[ $n != 0 ] || echo 'TESTRUN files=0 of=1' >> "$CONVEYOR_TEST_LOG/r"; exit $r
EOF
  loop run >/dev/null || fail "run exited non-zero"
}

# D1. Bug it catches: a comment-only bug card selects no test, so it was blocked as "the new tests pass without the
# fix", though the test file its issue's Done-when names fails on main's comment. That file runs alone with the fix
# (passes) and without it (fails): one build session, the review is told so, and the card lands.
t_bugcomment() {
  commentcard '! grep -q old s.sh' $'body\n\n## Done when\nw.test.sh fails on main and passes with the fix.'
  [ "$(cat "$STUB/mainran" 2>&1)" = $'staged: s.sh fix: 1 ran: 0\nstaged: s.sh fix: 1 ran: 1\nstaged: fix: 0 ran: 1' ] \
    || fail "the change was not asked for its tests, then the named test run with the fix and without it: $(cat "$STUB/mainran" 2>&1)"
  [ "$(wc -l < "$STUB/sessions")" = 1 ] && grep -q '^They pass with the fix, and the run without it failed (exit 1)' "$STUB/asked" \
    || fail "a comment-only card proved by its named test went back to build, or the review was not told: $(st 'select(.step == "build")'; cat "$STUB/asked" 2>&1)"
  [ -n "$(st 'select(.step == "landed") | .sha')" ] || fail "the card did not land: $(st 'select(.step | IN("blocked", "landed"))')"
}

# D2. Bug it catches: a comment-only card whose named test passes on main's code too is let through as proven. It
# goes back to its build once and is then blocked, as any unproven bug card.
t_bugcommentpasses() {
  commentcard 'grep -q word s.sh' $'body\n\n## Done when\nw.test.sh passes.'
  [ "$(st 'select(.step == "build") | .reason // ""' | tr '\n' '|')" = "|the new tests pass without the fix, so they do not prove it|" ] \
    && st 'select(.step == "blocked") | .tail' | grep -q '^They all passed without the fix: the new tests pass without the fix' \
    && [ -z "$(st 'select(.step == "landed")')" ] && [ ! -e "$STUB/asked" ] \
    || fail "a comment-only card whose named test passes on main was not blocked: $(st 'select(.step | IN("build", "blocked", "landed"))')"
}

# Bug it catches: a comment-only card is taken as proven by a named test that fails on main but fails with the fix
# too (it proves nothing of the fix). It is blocked, told the test fails with the fix.
t_bugcommentfixfails() {
  commentcard 'grep -q newer s.sh' $'body\n\n## Done when\nw.test.sh passes.'
  st 'select(.step == "blocked") | .tail' | grep -q '^They failed with the fix (exit 1): the new tests pass without the fix' \
    && [ -z "$(st 'select(.step == "landed")')" ] || fail "a named test that fails with the fix too let the card through: $(st 'select(.step | IN("blocked", "landed"))')"
}

# D3. Bug it catches: a comment-only card whose issue names no test file is blocked by a check that has nothing to run,
# or goes on with no word of why. One build, a bugproof line (skipped) saying why, the review told, and it lands.
t_bugcommentnamed() {
  commentcard 'false' $'body\n\n## Done when\nThe comment says new.'
  [ "$(st 'select(.step == "bugproof") | "\(.result): \(.reason)"')" = "skipped: the change selects no test (every changed line is a comment, or it touches no code the test command knows), and the issue's Done-when names no test file" ] \
    || fail "the card's record does not say the check was skipped and why: $(st 'select(.step == "bugproof")')"
  [ "$(wc -l < "$STUB/sessions")" = 1 ] && grep -q '^The bug-card check was skipped: ' "$STUB/asked" && [ -n "$(st 'select(.step == "landed") | .sha')" ] \
    || fail "a comment-only card naming no test did not go on to review and land: $(st 'select(.step | IN("build", "blocked", "landed"))')"
  loop check || fail "the record check refuses the bugproof line"
}

# Bug it catches: a bug card whose build changed nothing (an ALREADY-DONE, or a session that did nothing) is sent to
# build again to add a test, in place of going its own way. One session, and the card ends as a card with no change.
t_bugnochange() {
  setup "[$(issue 7 2026-01-01 bug)]"; echo ':' > "$STUB/build"
  loop run >/dev/null 2>&1
  [ "$(wc -l < "$STUB/sessions")" = 1 ] && st 'select(.step == "blocked") | .reason' | grep -q 'the session made no change' \
    || fail "a bug card with no change went back to build: $(st 'select(.step | IN("build", "blocked"))')"
}

# D3. Bug it catches: a card whose issue is not a bug is held to the check. Its test passes on main, and it still has
# one build session, no run on main, and a review that is not shown the check.
t_notbug() {
  bugcard 'grep -qx one a.txt' area:billing
  [ "$(wc -l < "$STUB/sessions")" = 1 ] && [ ! -e "$STUB/mainran" ] && ! grep -q 'bug-card check' "$STUB/asked" \
    || fail "a card that is not a bug was checked: $(cat "$STUB/mainran" 2>&1)"
}

# One card of #7, a bug filed from the Tests page to speed up f.test.sh, whose median on record is 10 CPU s (three
# whole-suite runs: 9, 10, 11). Its build changes f.test.sh. The file's run with the change (under cards/mainrun/)
# notes its folder, the file as it runs and its list in $STUB/mainran, times the file at <cpu> CPU s and exits <exit>.
# The reviewer's prompt is kept in $STUB/asked; one GO review.
speedcard() { # <cpu> [exit]
  setup "[$(issue 7 2026-01-01 bug | jq -c '.title = "Speed up the test file f.test.sh"')]"
  sed -i 's|^cat > /dev/null; echo x|cat > "$STUB/asked"; echo x|' "$STUB/codex"
  echo "$GO" > "$STUB/review.1"
  echo 'echo fast > f.test.sh' > "$STUB/build"
  for c in 9 10 11; do
    jq -cn --argjson c "$c" '{time: "2026-11-01T00:00:00Z", how: "full", sha: "abc", files: {"f.test.sh": {result: "ok", sec: $c, cpu: $c}}}' >> "$ST/suiteruns.jsonl"
  done
  echo '{ pwd; cat f.test.sh; cat "$CONVEYOR_TEST_RERUN"; } >> "$STUB/mainran"; printf "TESTRUN sec\tf.test.sh\t1\t%s\n" '"$1"' > "$CONVEYOR_TEST_LOG/r"; exit '"${2:-0}" > "$STUB/mainrun-cmd"
  loop run >/dev/null || fail "run exited non-zero"
}
speedline() { st 'select(.step == "bugproof") | "\(.result) \(.speed | tojson)"'; }

# D1. Bug it catches: a speed-up card, whose tests pass on main by design, is blocked for not failing there, or goes on
# with no proof that the file is faster. Its file runs alone with the change and is faster than its median on record:
# one build session, the review shown the numbers, both numbers on its record, and it lands.
t_speedfaster() {
  speedcard 4
  [ "$(speedline)" = 'ok {"file":"f.test.sh","before":10,"after":4}' ] || fail "the record does not hold both CPU numbers: $(st 'select(.step == "bugproof")')"
  [[ $(head -1 "$STUB/mainran") == */cards/mainrun/* ]] && [ "$(sed -n 2p "$STUB/mainran")" = fast ] && grep -qx $'fail\tf.test.sh' "$STUB/mainran" \
    || fail "the file did not run alone with the change: $(cat "$STUB/mainran" 2>&1)"
  [ "$(wc -l < "$STUB/sessions")" = 1 ] && grep -qx '# The speed-up check' "$STUB/asked" && grep -q 'passed in 4 CPU s, lower than its median on record, 10 CPU s' "$STUB/asked" \
    || fail "the card went back to build, or the review was not shown the speed-up check: $(st 'select(.step == "build")')"
  [ -n "$(st 'select(.step == "landed") | .sha')" ] || fail "a faster speed-up card did not land: $(st 'select(.step | IN("blocked", "landed"))')"
  loop check || fail "the record check refuses the speed-up bugproof line"
}

# D2. Bug it catches: a speed-up card whose file is as slow as its median lands as a speed-up. It is blocked with the
# "not faster" reason naming both numbers, never reviewed.
t_speedslow() {
  speedcard 10
  [ "$(st 'select(.step == "blocked") | .reason')" = 'build: the file is not faster: 10 CPU s on record, 10 CPU s now' ] && [ ! -e "$STUB/asked" ] \
    || fail "a speed-up card that is not faster was not blocked before review: $(st 'select(.step | IN("review", "blocked"))')"
  [ "$(speedline)" = 'fail {"file":"f.test.sh","before":10,"after":10}' ] || fail "the record does not hold both CPU numbers: $(st 'select(.step == "bugproof")')"
}

# Bug it catches: a speed-up card whose file fails with the change is let through because it ran fast.
t_speedfails() {
  speedcard 4 1
  [ "$(st 'select(.step == "blocked") | .reason')" = 'build: the file f.test.sh fails with the change (exit 1)' ] && [ ! -e "$STUB/asked" ] \
    || fail "a speed-up card whose file fails was not blocked: $(st 'select(.step | IN("review", "blocked"))')"
}
