#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases (#309): the changed lines no test reached, read from the coverage report a card's test run already
# writes (the pack's test.coverage, testrun.sh uncovered(), tools/uncovered.py), on the card's test line (testrec()).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# The card's test line after its test step: tests() runs the card's test command, which writes the run's coverage
# reports, then testrec()'s fields of the run on a test line, which the record
# check (jq/check.jq) must take. Printed: the test step's coverage as the snapshot draws the card's steps
# (jq/track.jq), for the Board.
uc_line() { # <worktree>
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; cd "$R" && . "$SRC/conveyor.sh" state-dir > /dev/null \
    && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/serve.sh")" && names && tests "$1" \
    && testrec "$1" 0 1 | jq -c '{card: "c0-1", issue: 1, step: "test", time: "2026-11-16T00:00:00Z", tokens: {claude: 0, codex: 0},
      result: "pass", sha: "", reason: ""} + .' ) > "$T/$CASE/line.jsonl" || fail "the card's test step failed: $(cat "$1.test" 2>/dev/null)"
  recok "$T/$CASE/line.jsonl" testrec
  jq -c --slurpfile l "$T/$CASE/line.jsonl" "$(<"$SRC/jq/track.jq") {x: {log: \$l}} | track(null; null) | .records[] | select(.name == \"tests passed\") | .coverage" -n
}

# A card's worktree $T/$CASE/wt on main, whose test command is <command> and whose coverage report is the folder
# coverage: main has src/a.js of 3 lines, and the card's staged change adds lines 4 to 7 of it and a test file.
uc_card() { # <command>
  local w=$T/$CASE/wt
  setup '[]'; tune --arg c "$1" '.test.coverage = {format: "lcov", path: "coverage"} | .test.command = $c'
  mkdir -p "$R/src" && printf 'a\nb\nc\n' > "$R/src/a.js" && git -C "$R" add -A && git -C "$R" commit -qm src \
    || fail "main's source file"
  git -C "$R" worktree add -q --detach "$w" && mkdir -p "$w/t" || fail "the card's worktree"
  printf 'a\nb\nc\nd\ne\nf\n}\n' > "$w/src/a.js" && echo 'test' > "$w/t/a.test.js" && git -C "$w" add -A || fail "the card's change"
}

# Bug caught: the test step named the test files of a changed file, never the changed lines no test reached, so the
# reviewer could not see that new code ran in no test. The patch adds lines 4 to 7 of src/a.js and a test file; the
# report counts 4 (hit), 5 and 6 (not hit), not 7 (a closing brace), and names no test file: lines 5-6, 2 of 3 counted.
# A second report that overlaps it (the same lines, one hit again) does not count a line twice: counted twice, it
# would say 4 of 6.
t_uncoveredlcov() {
  local w=$T/$CASE/wt rs=$T/$CASE/reports out
  uc_card "mkdir -p coverage && cp $(printf %q "$rs")/*.info coverage/"; mkdir -p "$rs" || fail "the reports' folder"
  printf 'TN:\nSF:%s\nDA:1,1\nDA:4,2\nDA:5,0\nDA:6,0\nend_of_record\n' "$w/src/a.js" > "$rs/lcov.info"
  printf 'SF:src/a.js\nDA:4,1\nDA:5,0\nDA:6,0\nend_of_record\n' > "$rs/more.info"
  out=$(uc_line "$w")
  [ "$out" = '{"uncovered":[{"file":"src/a.js","lines":"5-6"}],"count":2,"checked":3}' ] \
    || fail "the test line does not list the changed lines no test reached, each counted once, of those the reports count: $out"
}

# Bug caught: a run that runs its failed tests again writes its coverage report at the same path, over the first
# run's, so a line only the first run's tests reached was listed as reached by no test. The first run reaches lines
# 4 and 5 and fails; the run again reaches line 4 alone and passes: only line 6 was reached by no test.
t_uncoveredrerun() {
  local w=$T/$CASE/wt s=$T/$CASE/run.sh out
  uc_card "bash $(printf %q "$s")"
  cat > "$s" <<'EOF'
n=$(( $(cat ../n 2>/dev/null || echo 0) + 1 )); echo "$n" > ../n; L=$CONVEYOR_TEST_LOG/run.log; h=0
mkdir -p coverage; echo '== t/a.test.js'; echo '== t/a.test.js' >> "$L"; [ "$n" != 1 ] || h=1
printf 'SF:src/a.js\nDA:4,1\nDA:5,%s\nDA:6,0\nend_of_record\n' "$h" > coverage/lcov.info
if [ "$n" = 1 ]; then echo 'FAIL [flaky]: wrong'; echo '-- FAIL t/a.test.js' >> "$L"; exit 1; fi
echo 'ok flaky'; echo '-- ok t/a.test.js' >> "$L"
EOF
  out=$(uc_line "$w")
  [ "$(cat "$T/$CASE/n" 2>/dev/null)" = 2 ] || fail "the card's run did not run its failed test again: $(cat "$w.test")"
  [ "$out" = '{"uncovered":[{"file":"src/a.js","lines":"6"}],"count":1,"checked":3}' ] \
    || fail "the run again's coverage report hid the lines the first run reached: $out"
}

# Bug caught: a report that is not the tested patch's would list lines of another tree as reached or not. A report an
# earlier run left (written before the run began), one that names only files of another checkout, and one that names
# a line past the end of a changed file each make the coverage unknown, saying why.
t_uncoveredunknown() {
  local d=$T/$CASE/d old=$T/$CASE/old.info diff
  mkdir -p "$d/src" && printf 'a\nb\n' > "$d/src/a.js" || fail "the fixture"
  diff=$'diff --git a/src/a.js b/src/a.js\n--- a/src/a.js\n+++ b/src/a.js\n@@ -1,0 +2 @@\n+b'
  rd() { python3 -I "$SRC/tools/uncovered.py" lcov "$d" "$(($(date +%s) - 60))" "$1" <<<"$diff"; } # <report>
  printf 'SF:%s/src/a.js\nDA:2,1\nend_of_record\n' "$d" > "$old" && touch -t 202001010000 "$old"
  [ "$(rd "$old")" = '{"unknown":"the test run wrote no coverage report"}' ] || fail "a report an earlier run left was read: $(rd "$old")"
  printf 'SF:/elsewhere/src/a.js\nDA:2,1\nend_of_record\n' > "$T/$CASE/other.info"
  [ "$(rd "$T/$CASE/other.info")" = '{"unknown":"the coverage report names no file of the tested tree"}' ] \
    || fail "a report of another checkout was read as this one's: $(rd "$T/$CASE/other.info")"
  printf 'SF:src/a.js\nDA:2,0\nDA:9,0\nend_of_record\n' > "$T/$CASE/long.info"
  [ "$(rd "$T/$CASE/long.info")" = '{"unknown":"the coverage report names line 9 of src/a.js, which has 2 lines in the tested patch"}' ] \
    || fail "a report that does not fit the tested patch was read: $(rd "$T/$CASE/long.info")"
}
