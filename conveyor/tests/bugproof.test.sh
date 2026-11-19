#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the bug-card check (bugproof()): a bug card's new tests must fail on main's code without the fix.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# The control record's rule "Push when a card lands" off, after setup: no case here checks a push, and the push after a
# landing was about a seventh of a landing card's CPU (where the pack sets test.fileCommand, it runs the landing's test
# files before the push, pushtests(); with the default pack it runs none).
nopush() { jq -c '.rules.push = false' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json" || fail "the control record"; }

# One card of #7 with the given labels ($PREP, when set, is run after setup, before the loop): its build fixes a.txt (adds `two`; runs $FIX in its place when set, `:` for no
# fix) and, unless <test> is empty, adds a.test.sh (or the file $TF names) holding <test>. The run on main (a worktree under cards/mainrun/) notes its folder and staged files in
# $STUB/mainran and runs that test file, or what $MAINRUN holds when set; the reviewer's prompt is kept in $STUB/asked;
# one GO review. $TUNE, when set, is a jq filter of the pack (tune). No push (nopush).
bugcard() { # <test> <label>...
  # shellcheck disable=SC2034 # tf is read in the build's and the run's commands below
  local t=$1 tf=${TF:-a.test.sh}; shift
  setup "[$(issue 7 2026-01-01 "$@")]"; nopush
  [ -z "${TUNE:-}" ] || tune "$TUNE"
  [ -z "${PREP:-}" ] || eval "$PREP"
  sed -i 's|^cat > /dev/null; echo x|cat > "$STUB/asked"; echo x|' "$STUB/codex"
  echo "$GO" > "$STUB/review.1"
  echo "${FIX-echo two >> a.txt}${t:+; mkdir -p \"\$(dirname '$tf')\"; printf '%s\n' '$t' > '$tf'}" > "$STUB/build"
  echo '{ pwd; git diff --cached --name-only; } >> "$STUB/mainran"; '"${MAINRUN:-bash '$tf'}" > "$STUB/mainrun-cmd"
  loop run >/dev/null || fail "run exited non-zero"
}

# D1. Bug it catches: a bug card whose new test fails without the fix (it proves the fix) is sent back to build, or
# its test runs on main with the fix in it, or the review is not shown the result. The test runs on main's code with
# the card's test file alone; one build session; the review sees that it failed there; the card lands.
t_bugfails() {
  local -x FILEMODE=1
  bugcard 'grep -qx two a.txt' bug
  [ "$(wc -l < "$STUB/sessions")" = 1 ] && [ "$(st 'select(.step == "build") | .result' | wc -l)" = 1 ] \
    || fail "a bug card whose new test fails on main went back to build: $(st 'select(.step == "build")')"
  [ "$(sed 1d "$STUB/mainran" | tr '\n' ' ')" = 'a.test.sh ' ] && [[ $(head -1 "$STUB/mainran") == */cards/mainrun/* ]] \
    || fail "the run on main was not of main's code with the card's test file alone: $(cat "$STUB/mainran" 2>&1)"
  grep -qx '# The bug-card check' "$STUB/asked" && grep -q '^The run failed there (exit 1)' "$STUB/asked" \
    || fail "the review was not shown that the new test fails on main: $(cat "$STUB/asked")"
  # The card's test list (<card>.testlist, which the per-file run writes) stays after landing: tidy() does not remove it.
  local left=() f; for f in "$T/$CASE/cards"/*; do [ -e "$f" ] && [[ $f != *.testlist ]] && left+=("$f"); done
  [ -n "$(st 'select(.step == "landed") | .sha')" ] && [ "${#left[@]}" = 0 ] \
    || fail "the card did not land, or left a worktree: $(ls "$T/$CASE/cards")"
}

# D2. Bug it catches: a bug card whose new test passes on main's code (it proves nothing of the fix) goes on to review
# as if proven. It goes back to its build session, told why, its build line saying so; the check runs again after
# it, and as the test still passes there the card is blocked with that reason, never reviewed.
t_bugpasses() {
  local -x FILEMODE=1
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
  # The old fixture: the runner's own exit and log are test.command's (test.fileCommand's failure names the file).
  MAINRUN='echo "== a.test.sh" > "$CONVEYOR_TEST_LOG/r"; bash a.test.sh && echo "-- ok a.test.sh" >> "$CONVEYOR_TEST_LOG/r"; exit 1' \
    bugcard 'grep -qx one a.txt' bug
  [ "$(st 'select(.step == "build") | .reason // ""' | tr '\n' '|')" = "|the new tests pass without the fix, so they do not prove it|" ] \
    && grep -q '^The run failed there (exit 1), but no test failed in it' "$STUB/brief" \
    || fail "a runner's own failure on main was taken for the new test failing: $(st 'select(.step == "build")'; tail -n 20 "$STUB/brief")"
  # D2 of #69: the file ran and passed there, so it is no "no result" run: it is blocked as passing without the fix.
  [ "$(grep -c '/cards/mainrun/' "$STUB/mainran")" = 2 ] && [ "$(st 'select(.step == "blocked") | .reason')" = "build: the new tests pass without the fix, so they do not prove it" ] \
    || fail "a run on main whose file ran and passed was not blocked as passing without the fix: $(st 'select(.step == "blocked")'; cat "$STUB/mainran")"
}

# Bug it catches: the proof run had no time limit for one hung test, so a new test that waits for what the unfixed
# code never writes held its card until stopped by hand. Here it hangs on main's code; its file's `# timeout: 2` line
# stops the run there, far before the run's own limit (testTimeout 15 s, the limit a file with no such line has, as in
# t_bughungdefault): the run's output and the review name a.test.sh as timed out at 2 s, not 15 s, it counts as failing
# without the fix, and the card lands after one build.
t_bughung() {
  local -x FILEMODE=1
  TUNE='.tunables.testTimeout = 15' MAINRUN='echo "== a.test.sh" > "$CONVEYOR_TEST_LOG/r"; bash a.test.sh && echo "-- ok a.test.sh" >> "$CONVEYOR_TEST_LOG/r"' \
    bugcard $'# timeout: 2\nuntil grep -qx two a.txt; do sleep 0.2; done' bug # sleep: the new test's own wait, which never ends on main's code
  hungsaid 2
}
# The checks of t_bughung and t_bughungdefault: the review is shown a.test.sh timed out at <seconds>, counted as
# failing without the fix, and the card lands after one build.
hungsaid() { # <seconds>
  grep -qxF "conveyor: a.test.sh timed out: it ran past its time limit, $1 s, and the run was stopped there" "$STUB/asked" \
    && grep -q '^The run failed there (exit 124): at least one fails without the fix' "$STUB/asked" \
    && grep -qxF "a.test.sh timed out: it ran past its time limit, $1 s, and was stopped. A test that hangs without the fix counts as failing without it." "$STUB/asked" \
    || fail "the proof run was not stopped at the hung file's limit, naming it, and counted as failing: $(grep -A 40 '# The bug-card check' "$STUB/asked" 2>&1 | head -40)"
  [ "$(wc -l < "$STUB/sessions")" = 1 ] && [ -n "$(st 'select(.step == "landed") | .sha')" ] \
    || fail "a card whose new test hangs without the fix did not land after one build: $(st 'select(.step | IN("build", "blocked"))')"
}

# Bug it catches: a hung new test whose file has no `# timeout:` line was stopped by the run's own limit (testTimeout,
# 4 s here) with nothing naming it, so the run gave no failing file and did not count as proof; the card went back to
# build. The file is named as timed out at the testTimeout limit and counts as failing without the fix.
t_bughungdefault() {
  local -x FILEMODE=1
  TUNE='.tunables.testTimeout = 4' MAINRUN='echo "== a.test.sh" > "$CONVEYOR_TEST_LOG/r"; bash a.test.sh && echo "-- ok a.test.sh" >> "$CONVEYOR_TEST_LOG/r"' \
    bugcard 'until grep -qx two a.txt; do sleep 0.2; done' bug # sleep: the new test's own wait, which never ends on main's code
  hungsaid 4
}

# D1 of #69. Bug it catches: a run on main whose runner exits 1 and gives no result for the card's test file (its logs
# name another file only, as a runner whose part for that file was unavailable) is taken for "the new tests pass
# without the fix", and the card goes back to its build for a fault no build can mend. It runs once more on main, no
# build session follows, and the card is blocked with the "gave no result" reason and the runner's last lines.
t_bugnoresult() {
  # The old fixture: the runner's own exit and log are test.command's (test.fileCommand's failure names the file).
  MAINRUN='printf "== o.test.sh\n-- ok o.test.sh\n" > "$CONVEYOR_TEST_LOG/r"; echo "Tests unavailable"; exit 1' \
    bugcard 'grep -qx one a.txt' bug
  [ "$(grep -c '/cards/mainrun/' "$STUB/mainran")" = 2 ] && [ "$(wc -l < "$STUB/sessions")" = 1 ] \
    && [ -z "$(st 'select(.step == "build") | .reason // empty')" ] \
    || fail "a run on main with no result for the test file was not run once more, or went back to build: $(st 'select(.step == "build")'; cat "$STUB/mainran")"
  [ "$(st 'select(.step == "blocked") | .reason')" = 'build: the proof run on main gave no result for a.test.sh: Tests unavailable' ] && [ ! -e "$STUB/asked" ] \
    || fail "the card was not blocked with the no-result reason before review: $(st 'select(.step | IN("review", "blocked"))')"
}

# Bug it catches: a runner that runs another file's cases logs them under its own name (the engine's runner,
# conveyor/conveyor.test.sh, those of a case file), so a run whose case file passed, and which failed only for the
# runner's own check, was read as giving no result for the case file and blocked as "gave no result" in place of
# "the new tests pass without the fix". noresult() is called on such a run: a case of the file passed, so it has a
# result; a file with none of the run's cases in it has none.
t_bugnoresultnested() {
  local w=$T/$CASE/wt; mkdir -p "$w.testlog" "$w/conveyor/tests"
  printf 't_fixed() { :; }\n' > "$w/conveyor/tests/new.test.sh"; printf 't_other() { :; }\n' > "$w/conveyor/tests/none.test.sh"
  printf '== conveyor/conveyor.test.sh\n-- ok conveyor/conveyor.test.sh\n' > "$w.testlog/r"
  printf '== conveyor/conveyor.test.sh (cases: fixed)\nok fixed\nthe area map does not name conveyor/tests/new.test.sh\n' > "$w.test"
  local got
  got=$( eval "$(sed -n '/^testfails() {/,/^}/p; /^noresult() {/,/^}/p' "$SRC/lib/testrun.sh"; sed -n '/^testlogs() {/,/^}/p' "$SRC/lib/session.sh")"
    packget() { return 1; }; TEST_TIMEOUT=600 noresult "$w" 1 conveyor/tests/new.test.sh conveyor/tests/none.test.sh )
  [ "$got" = conveyor/tests/none.test.sh ] \
    || fail "noresult() did not take a case logged under the runner as the case file's result: '$got'"
}

# Bug it catches: a bug card whose change is a test file alone (a test fixed for a red main, which passes on main's
# code too) is blocked, as with no fix to take out its test passes "without the fix". It is not run on main, has one
# build session, its review is told the change is test-only, and it lands.
t_bugtestonly() {
  local -x FILEMODE=1
  FIX=: bugcard 'grep -qx one a.txt' bug
  [ "$(wc -l < "$STUB/sessions")" = 1 ] && [ ! -e "$STUB/mainran" ] \
    || fail "a test-only bug card was run on main or sent back to build: $(st 'select(.step == "build")'; cat "$STUB/mainran" 2>&1)"
  grep -qx '# The bug-card check' "$STUB/asked" && grep -q '^The change is test-only: ' "$STUB/asked" \
    || fail "the review was not told the change is test-only: $(cat "$STUB/asked" 2>&1)"
  [ -n "$(st 'select(.step == "landed") | .sha')" ] || fail "a test-only bug card did not land: $(st 'select(.step | IN("blocked", "landed"))')"
}

# #515. Main holds a.js; a bug card fixes its // comment and adds a test of what a.js already does (with a # comment).
COMMENTPREP='printf "%s\n" "// x is two" "export const x = 1;" > "$R/a.js" && git -C "$R" add a.js && linkset "{\"a.txt\": [\"a.test.sh\"], \"a.js\": [\"a.test.sh\"]}"'
COMMENTFIX='sed -i "s|^// x is two|// x is one|" a.js'
COMMENTTEST='grep -qxF "export const x = 1;" a.js # a.js sets x to one'
# D1. Bug it catches: a bug card whose product change is comments only, with a test file, is blocked with "the new
# tests pass without the fix", which no comment fix can avoid. It is not run on main, has one build session, its
# review is told the product change is comments only, and it lands.
t_bugcomments() {
  local -x FILEMODE=1
  PREP=$COMMENTPREP FIX=$COMMENTFIX bugcard "$COMMENTTEST" bug
  [ "$(wc -l < "$STUB/sessions")" = 1 ] && [ ! -e "$STUB/mainran" ] \
    || fail "a comments-only bug card was run on main or sent back to build: $(st 'select(.step == "build")'; cat "$STUB/mainran" 2>&1)"
  grep -q '^The change is comments only in its product files: ' "$STUB/asked" \
    || fail "the review was not told the product change is comments only: $(cat "$STUB/asked" 2>&1)"
  [ -n "$(st 'select(.step == "landed") | .sha')" ] || fail "a comments-only bug card did not land: $(st 'select(.step | IN("blocked", "landed"))')"
}

# D2. Bug it catches: a product change with one real code line beside its comment fix is let skip the check as
# comments only. Its test passes on main, so it is blocked with "the new tests pass without the fix", as before.
t_bugcommentcode() {
  local -x FILEMODE=1
  PREP=$COMMENTPREP FIX="$COMMENTFIX; echo 'export const y = 2;' >> a.js" bugcard "$COMMENTTEST" bug
  [ "$(st 'select(.step == "blocked") | .reason' | head -n 1)" = "build: the new tests pass without the fix, so they do not prove it" ] \
    || fail "a comment fix with a code line was not blocked as unproved: $(st 'select(.step | IN("blocked", "landed"))')"
  grep -q '/cards/mainrun/' "$STUB/mainran" || fail "its test was not run on main: $(cat "$STUB/mainran" 2>&1)"
}

# Bug it catches: commentsonly() reads each changed line alone, so a change that puts code between a /* line and a */
# line (the code no longer runs), or edits a # line in a shell heredoc (text the program prints), is let skip the
# check; and so are a/**/b in js read as ab, and two .css and .html changes that look like comment fixes but change
# the page: 16/**/px (two CSS tokens, the rule dropped) read as 16px, and a new <!-- --> in an empty <nav> (a node:
# the Board sees a first child and draws no tabs). Each change here is staged beside a test file in a fresh repo and
# given to commentsonly().
t_bugcommentsyntax() {
  local r=$T/$CASE/r got=''
  mkdir -p "$r" && git -C "$r" init -q && git -C "$r" config user.email t@example.com && git -C "$r" config user.name t \
    || fail "the fixture repo"
  printf '%s\n' '// x is two' 'const s = `a' '// b' '`;' 'export const x = 1;' 'function f() { return 1; }' 'draw();' > "$r/app.js"
  printf '%s\n' '/* the top bar */' '.x { color: red; }' '.y { font-size: 16px; }' > "$r/app.css"
  printf '%s\n' '<!-- the tiles -->' '<nav id="stats"></nav>' '<nav id="tabs"></nav>' > "$r/index.html"
  printf '%s\n' "cat <<'E'" '# STANDING YES' 'E' > "$r/rules.sh"
  printf '%s\n' 'ok();' > "$r/a.test.js"
  git -C "$r" add -A && git -C "$r" commit -qm main || fail "the fixture commit"
  # <name> <file> <sed script>: the file changed so and a.test.js changed, staged; notes "<name>=<0 when comments only>".
  try() {
    sed -i "$3" "$r/$2" && echo 'ok(1);' >> "$r/a.test.js" && git -C "$r" add -A || fail "staging $1"
    # shellcheck disable=SC2034 # TESTRX and TESTRUNNERS are read by testpaths(), loaded below
    got+=" $1=$( . "$SRC/lib/portable.sh"; TESTRX='\.test\.' TESTRUNNERS=''
      eval "$(sed -n '/^testpaths() {/,/^}/p' "$SRC/lib/issues.sh"; sed -n '/^uncomment() {/,/^}/p; /^commentsonly() {/,/^}/p' "$SRC/lib/testrun.sh")"
      commentsonly "$r"; echo $?)"
    git -C "$r" reset -q --hard
  }
  try js app.js 's|x is two|x is one|'
  try wrap app.js 's|^draw();|/*\n&\n*/|'
  try template app.js 's|^// b|// c|'
  try jsblank app.js 's|x is two|x is one|; 1s|$|\n|'
  try jstoken app.js 's|^draw|dr/**/aw|'
  try csstoken app.css 's|16px|16/* root size */px|'
  try htmlnode index.html 's|"tabs">|&<!-- Tabs -->|'
  try heredoc rules.sh 's|YES|NO|'
  # #542: a line break other than the newline inside a comment is code to JavaScript. In a /* */ comment it ends the
  # return's statement (f() returns undefined); in a // comment it ends the comment, so draw() runs.
  try blocklsep app.js $'s|return |return /*\xe2\x80\xa8*/ |'
  try blockcr app.js $'s|return |return /*\r*/ |'
  try linepsep app.js $'s|x is two|x is two\xe2\x80\xa9draw();|'
  [ "$got" = ' js=0 wrap=1 template=1 jsblank=0 jstoken=1 csstoken=1 htmlnode=1 heredoc=1 blocklsep=1 blockcr=1 linepsep=1' ] \
    || fail "commentsonly() does not tell js comment fixes (0) from code changes (1): $got"
}

# Bug it catches: a bug card that adds no test at all goes to review unchecked; or (#137) it is told and blocked with
# "the new tests pass without the fix", though no test ran. It goes back to its build, then is blocked, each time
# told no test file was found and the patterns that looked (the default, as the pack sets none); its only runs on
# main are of its whole change (does it select a test? Here it does: its run is not "nothing selected").
t_bugnotest() {
  local -x FILEMODE=1
  bugcard '' bug
  local why; why="no test file found in the change (patterns: $(jq -r '.properties.tests.properties.patterns.default | join(", ")' "$SRC/schema/pack.schema.json")); set tests.patterns in .conveyor/project.json"
  [ "$(st 'select(.step == "build") | .reason // ""' | tr '\n' '|')" = "|$why|" ] && grep -qxF "# Back to the build: $why" "$STUB/brief" \
    && grep -qF "No test file found in the change (patterns: __tests__/, " "$STUB/brief" || fail "a bug card with no test did not go back to its build, told so: $(st 'select(.step == "build")')"
  [ "$(st 'select(.step == "blocked") | .reason' | head -n 1)" = "build: $why" ] && ! grep -q 'pass without the fix' "$STUB/brief" \
    || fail "a bug card with no test was not blocked with the no-test reason alone: $(st 'select(.step == "blocked")')"
  [ "$(grep -v '/cards/mainrun/' "$STUB/mainran" | sort -u)" = a.txt ] || fail "a card with no test file ran other than its whole change on main: $(cat "$STUB/mainran" 2>&1)"
  [ -z "$(st 'select(.step == "bugproof")')" ] || fail "a code change with no test was let skip the check: $(st 'select(.step == "bugproof")')"
}

# #137. Bug it catches: a project whose tests are src/test-<name>.mjs, set in its pack's tests.patterns, had its test
# file taken for no test file, never run on main, and the card blocked as "the new tests pass without the fix". The
# file is found, runs alone on main's code without the fix and fails there, and the card lands with one build.
t_bugpatterns() {
  local -x FILEMODE=1
  TF=src/test-a.mjs TUNE='.tests.patterns = ["src/test-*.mjs"]' bugcard 'grep -qx two a.txt' bug
  [ "$(sed 1d "$STUB/mainran" | tr '\n' ' ')" = 'src/test-a.mjs ' ] && [ "$(wc -l < "$STUB/sessions")" = 1 ] \
    || fail "the run on main was not of the card's src/test-a.mjs alone, or the card went back to build: $(cat "$STUB/mainran" 2>&1)"
  grep -q '^The run failed there (exit 1)' "$STUB/asked" && [ -n "$(st 'select(.step == "landed") | .sha')" ] \
    || fail "the card whose test fails on main was not reviewed as proven and landed: $(st 'select(.step | IN("blocked", "landed"))')"
}

# #137. Bug it catches: test files the test command does not run when given them alone (its run selects none) were
# reported as "the new tests pass without the fix", and the card went back to a build that cannot change the pack.
# Here the command runs a test only when the change's code is staged: the card is blocked at once, told the files
# were found but not run, and to set test.fileCommand.
t_bugnotalone() {
  # The old fixture: the case is of a pack with no test.fileCommand, which its reason names; the fixture sets one.
  MAINRUN='if git diff --cached --name-only | grep -qx a.txt; then bash a.test.sh; else echo "TESTRUN files=0 of=1" >> "$CONVEYOR_TEST_LOG/r"; fi' \
    bugcard 'grep -qx one a.txt' bug
  [ "$(wc -l < "$STUB/sessions")" = 1 ] && [ ! -e "$STUB/asked" ] \
    && [ "$(st 'select(.step == "blocked") | .reason' | head -n 1)" = 'build: test files were found in the change, but the test command, given them, selected none of them, so they did not run without the fix; set test.fileCommand in .conveyor/project.json to a command that runs one test file' ] \
    && ! st 'select(.step == "blocked") | .reason' | grep -q 'pass without the fix' \
    || fail "test files the command did not run were not reported as such: $(st 'select(.step | IN("build", "blocked", "review"))')"
}

# #137. Bug it catches: a pack whose test command cannot run one file alone has no way to run a change's test files.
# With test.fileCommand set, the check runs it once for each test file, given the file, in place of test.command:
# the file fails on main without the fix, and the card lands. Only the check's runs (in its worktree on main) are
# counted.
t_bugfilecommand() {
  local -x FILEMODE=1
  TUNE='.test.fileCommand = "case $PWD in */mainrun/*) echo \"$CONVEYOR_TEST_FILE\" >> \"$STUB/fileran\" ;; esac; bash"' bugcard 'grep -qx two a.txt' bug
  [ "$(cat "$STUB/fileran" 2>&1)" = a.test.sh ] && [ ! -e "$STUB/mainran" ] \
    || fail "the check did not run the test file alone with test.fileCommand: $(cat "$STUB/fileran" "$STUB/mainran" 2>&1)"
  grep -q '^The run failed there (exit 1)' "$STUB/asked" && [ -n "$(st 'select(.step == "landed") | .sha')" ] \
    || fail "the card proved through test.fileCommand did not land: $(st 'select(.step | IN("blocked", "landed"))')"
}

# A bug card of #7 whose build writes <card> into the product file <file>, which holds <main> on main: its fix and its
# new test are both in that file, and it adds no test file. Its test command is <runner>, on main's code (the check)
# and on the card (its test step, which must pass for it to land); each run on main notes in $STUB/mainran its staged
# files and <file> as it is there. The reviewer's prompt is kept in $STUB/asked; one GO review. No push (nopush).
inlinecard() { # <file> <main> <card> <runner>
  setup "[$(issue 7 2026-01-01 bug)]"; nopush
  mkdir -p "$(dirname "$R/$1")" && printf '%s\n' "$2" > "$R/$1" && git -C "$R" add "$1" && git -C "$R" commit -qm 'a product file' \
    && git -C "$R" push -q origin main || fail "main's file"
  sed -i 's|^cat > /dev/null; echo x|cat > "$STUB/asked"; echo x|' "$STUB/codex"
  echo "$GO" > "$STUB/review.1"
  printf '%s\n' "$3" > "$STUB/card-file"; echo "cp \"\$STUB/card-file\" '$1'" > "$STUB/build"
  { echo "{ git diff --cached --name-only; cat '$1'; } >> \"\$STUB/mainran\""; printf '%s\n' "$4"; } > "$STUB/mainrun-cmd"
  printf '%s\n' "$4" > "$STUB/test-cmd"
  loop run >/dev/null || fail "run exited non-zero"
}
# A Rust file, src/lib.rs, whose f() returns 1 on main. The runner stands in for cargo test (no Rust toolchain is
# needed): the file's test passes when f() returns the number its assert_eq! asks for.
RUSTMAIN=$'pub fn f() -> i32 {\n    1\n}'
RUSTRUN='w=$(sed -n "s/.*assert_eq!([a-z:]*f(), \([0-9]*\)).*/\1/p" src/lib.rs); [ -z "$w" ] || grep -Eq "^ *(pub fn f\(\) -> i32 \{ )?$w( \}.*)?$" src/lib.rs'

# #140 D1. Bug it catches: a bug card whose only new test is a Rust #[test] inside the product file it fixes had no
# test file to run without the fix, and was blocked. The check stages src/lib.rs on main's code with the new test
# module and without the fix: the test fails there, it passes on the card, and the card lands with one build.
t_buginlinerust() {
  local -x FILEMODE=1
  inlinecard src/lib.rs "$RUSTMAIN" $'pub fn f() -> i32 {\n    2\n}\n\n#[cfg(test)]\nmod tests {\n    #[test]\n    fn two() {\n        assert_eq!(super::f(), 2);\n    }\n}' "$RUSTRUN"
  [ "$(cat "$STUB/mainran" 2>&1)" = "src/lib.rs"$'\n'"$RUSTMAIN"$'\n#[cfg(test)]\nmod tests {\n    #[test]\n    fn two() {\n        assert_eq!(super::f(), 2);\n    }\n}' ] \
    || fail "the run on main was not of main's f() with the new test module alone: $(cat "$STUB/mainran" 2>&1)"
  grep -qxF -- '- src/lib.rs (its inline tests, with the rest of its change taken out)' "$STUB/asked" && grep -q '^The run failed there (exit 1)' "$STUB/asked" \
    || fail "the review was not shown that the inline test fails without the fix: $(cat "$STUB/asked" 2>&1)"
  [ "$(wc -l < "$STUB/sessions")" = 1 ] && [ -n "$(st 'select(.step == "landed") | .sha')" ] \
    || fail "the card proved by its inline test did not land with one build: $(st 'select(.step | IN("build", "blocked", "landed"))')"
}

# #140 D1. Bug it catches: a Python doctest added to the docstring of the function a bug card fixes was no test the
# check could run. The real doctest runner, on main's code with the new docstring and without the fix, fails; on the
# card it passes, and the card lands with one build.
t_buginlinedoctest() {
  local -x FILEMODE=1
  inlinecard lib.py $'def double(x):\n    return x * 3' $'def double(x):\n    """\n    >>> double(2)\n    4\n    """\n    return x * 2' \
    'PYTHONDONTWRITEBYTECODE=1 python3 -m doctest lib.py'
  [ "$(cat "$STUB/mainran" 2>&1)" = $'lib.py\ndef double(x):\n    """\n    >>> double(2)\n    4\n    """\n    return x * 3' ] \
    || fail "the run on main was not of main's double() with the new doctest alone: $(cat "$STUB/mainran" 2>&1)"
  grep -q '^The run failed there (exit 1)' "$STUB/asked" && [ "$(wc -l < "$STUB/sessions")" = 1 ] && [ -n "$(st 'select(.step == "landed") | .sha')" ] \
    || fail "the card proved by its doctest was not reviewed as proven and landed: $(st 'select(.step | IN("build", "blocked", "landed"))'; cat "$STUB/asked" 2>&1)"
}

# #140 D2. Bug it catches: a new test written on the same line as the fix cannot be run without the fix, and the card
# was blocked as "no test file found" or as "the new tests pass without the fix", though nothing ran. It goes back to
# its build, then is blocked, each time with the reason that names the file; it is never run on main or reviewed.
t_buginlineshared() {
  local -x FILEMODE=1
  inlinecard src/lib.rs 'pub fn f() -> i32 { 1 }' 'pub fn f() -> i32 { 2 } #[test] fn two() { assert_eq!(f(), 2); }' "$RUSTRUN"
  local why='the new test and the fix are in the same lines of src/lib.rs; bugproof cannot take out the fix alone'
  [ "$(st 'select(.step == "build") | .reason // ""' | tr '\n' '|')" = "|$why|" ] && grep -qxF "# Back to the build: $why" "$STUB/brief" \
    || fail "the card did not go back to its build with the shared-lines reason: $(st 'select(.step == "build")')"
  [ "$(st 'select(.step == "blocked") | .reason' | head -n 1)" = "build: $why" ] && ! st 'select(.step == "blocked") | .reason, .tail' | grep -q 'pass' \
    || fail "the card was not blocked with the shared-lines reason alone: $(st 'select(.step == "blocked")')"
  [ ! -e "$STUB/mainran" ] && [ ! -e "$STUB/asked" ] || fail "a fix it could not take out was run on main or reviewed: $(cat "$STUB/mainran" 2>&1)"
}

# A bug card of #7 whose build only rewords a comment of s.sh (`# an old word` becomes `# a new word`), on a main that
# holds s.sh and w.test.sh holding <test>; its issue's body is <body>. The run on main runs each file its
# CONVEYOR_TEST_RERUN list names as `fail`; with none, it selects nothing (its log says files=0), as a runner does for a
# comment-only change. Each run notes in $STUB/mainran its staged files, whether s.sh holds the fix and its fail lines.
# No push (nopush).
commentcard() { # <test> <body>
  setup "[$(issue 7 2026-01-01 bug | jq -c --arg b "$2" '.body = $b')]"; nopush
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
  # The old fixture: the change is first given to test.command, a runner that selects no file for it (files=0).
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
  local -x FILEMODE=1
  commentcard 'grep -q word s.sh' $'body\n\n## Done when\nw.test.sh passes.'
  [ "$(st 'select(.step == "build") | .reason // ""' | tr '\n' '|')" = "|the new tests pass without the fix, so they do not prove it|" ] \
    && st 'select(.step == "blocked") | .tail' | grep -q '^They all passed without the fix: the new tests pass without the fix' \
    && [ -z "$(st 'select(.step == "landed")')" ] && [ ! -e "$STUB/asked" ] \
    || fail "a comment-only card whose named test passes on main was not blocked: $(st 'select(.step | IN("build", "blocked", "landed"))')"
}

# Bug it catches: a comment-only card is taken as proven by a named test that fails on main but fails with the fix
# too (it proves nothing of the fix). It is blocked, told the test fails with the fix.
t_bugcommentfixfails() {
  local -x FILEMODE=1
  commentcard 'grep -q newer s.sh' $'body\n\n## Done when\nw.test.sh passes.'
  st 'select(.step == "blocked") | .tail' | grep -q '^They failed with the fix (exit 1): the new tests pass without the fix' \
    && [ -z "$(st 'select(.step == "landed")')" ] || fail "a named test that fails with the fix too let the card through: $(st 'select(.step | IN("blocked", "landed"))')"
}

# D3. Bug it catches: a comment-only card whose issue names no test file is blocked by a check that has nothing to run,
# or goes on with no word of why. One build, a bugproof line (skipped) saying why, the review told, and it lands.
t_bugcommentnamed() {
  local -x FILEMODE=1
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
  local -x FILEMODE=1
  setup "[$(issue 7 2026-01-01 bug)]"; echo ':' > "$STUB/build"
  loop run >/dev/null 2>&1
  [ "$(wc -l < "$STUB/sessions")" = 1 ] && st 'select(.step == "blocked") | .reason' | grep -q 'the session made no change' \
    || fail "a bug card with no change went back to build: $(st 'select(.step | IN("build", "blocked"))')"
}

# D3. Bug it catches: a card whose issue is not a bug is held to the check. Its test passes on main, and it still has
# one build session, no run on main, and a review that is not shown the check.
t_notbug() {
  local -x FILEMODE=1
  bugcard 'grep -qx one a.txt' area:billing
  [ "$(wc -l < "$STUB/sessions")" = 1 ] && [ ! -e "$STUB/mainran" ] && ! grep -q 'bug-card check' "$STUB/asked" \
    || fail "a card that is not a bug was checked: $(cat "$STUB/mainran" 2>&1)"
}

# One card of #7, a bug filed from the Tests page to speed up f.test.sh, whose median on record is 10 CPU s (three
# whole-suite runs: 9, 10, 11). Its build changes f.test.sh. The file's run with the change (under cards/mainrun/)
# notes its folder, the file as it runs and its list in $STUB/mainran, times the file at <cpu> CPU s and exits <exit>.
# The reviewer's prompt is kept in $STUB/asked; one GO review. No push (nopush).
speedcard() { # <cpu> [exit]
  setup "[$(issue 7 2026-01-01 bug | jq -c '.title = "Speed up the test file f.test.sh"')]"; nopush
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
  local -x FILEMODE=1
  speedcard 4
  [ "$(speedline)" = 'ok {"file":"f.test.sh","before":10,"after":4,"fix":"sped up","into":[]}' ] || fail "the record does not hold both CPU numbers: $(st 'select(.step == "bugproof")')"
  [[ $(head -1 "$STUB/mainran") == */cards/mainrun/* ]] && [ "$(sed -n 2p "$STUB/mainran")" = fast ] && grep -qx $'fail\tf.test.sh' "$STUB/mainran" \
    || fail "the file did not run alone with the change: $(cat "$STUB/mainran" 2>&1)"
  [ "$(wc -l < "$STUB/sessions")" = 1 ] && grep -qx '# The speed-up check' "$STUB/asked" && grep -q 'passed in 4 CPU s, lower than its median on record, 10 CPU s' "$STUB/asked" \
    || fail "the card went back to build, or the review was not shown the speed-up check: $(st 'select(.step == "build")')"
  [ -n "$(st 'select(.step == "landed") | .sha')" ] || fail "a faster speed-up card did not land: $(st 'select(.step | IN("blocked", "landed"))')"
  loop check || fail "the record check refuses the speed-up bugproof line"
}

# D2. Bug it catches: a speed-up card whose file is as slow as its median lands as a speed-up. It is blocked with the
# "not faster" reason naming both numbers, and no budget (#349), never reviewed.
t_speedslow() {
  local -x FILEMODE=1
  speedcard 10
  [ "$(st 'select(.step == "blocked") | .reason')" = 'build: the file is not faster than its median on record (10 CPU s), as the verdict speed up asks: 10 CPU s now' ] && [ ! -e "$STUB/asked" ] \
    || fail "a speed-up card that is not faster was not blocked before review: $(st 'select(.step | IN("review", "blocked"))')"
  [ "$(speedline)" = 'fail {"file":"f.test.sh","before":10,"after":10,"fix":"sped up","into":[]}' ] || fail "the record does not hold both CPU numbers: $(st 'select(.step == "bugproof")')"
  # #180: with no version on its line, a later change to the check could not tell this block from others.
  [ "$(st 'select(.step == "blocked") | .speedcheck')" = "$SPEEDV" ] || fail "the blocked line does not carry the speed check's version $SPEEDV: $(st 'select(.step == "blocked")')"
}
SPEEDV=$(sed -n 's/^SPEEDCHECK=//p' "$SRC/lib/testrun.sh") # the version of the speed check, as testrun.sh sets it

# Bug it catches: a speed-up card whose file fails with the change is let through because it ran fast.
t_speedfails() {
  local -x FILEMODE=1
  speedcard 4 1
  [ "$(st 'select(.step == "blocked") | .reason')" = 'build: the file f.test.sh fails with the change (exit 1)' ] && [ ! -e "$STUB/asked" ] \
    || fail "a speed-up card whose file fails was not blocked: $(st 'select(.step | IN("review", "blocked"))')"
}

# One card of #7, an Optimize issue filed from the Tests page for f.test.sh (on main, `echo slow`, with g.test.sh,
# `echo other`), whose median on
# record is 10 CPU s (three whole-suite runs: 9, 10, 11). Its build runs <build>. Each run under cards/mainrun/ runs
# the files of its list: it notes each, with what it holds there, in $STUB/mainran, names the cases one and two of each
# as passed, and times each at the CPU seconds $STUB/cpu-<file> holds. The run of f on main for the build's brief
# (speedbrief(), under cards/mainrun/<card>.cases) is not noted: ownbudget.test.sh holds that brief to its lines.
# The reviewer's prompt is kept in $STUB/asked. No push (nopush).
optcard() { # <build> <cpu of f> [<cpu of f1> <cpu of f2>]
  local b=$1; shift
  optmain "$@"
  echo 'echo slow' > "$R/f.test.sh"; echo 'echo other' > "$R/g.test.sh"
  git -C "$R" add f.test.sh g.test.sh && git -C "$R" commit -qm 'a slow test' && git -C "$R" push -q origin main || fail "main's files"
  echo "$b" > "$STUB/build"
  loop run >/dev/null || fail "run exited non-zero"
}
# optcard's case folder, but for main's two files and the card's build: its issue, review, median and runs on main.
optmain() { # <cpu of f> [<cpu of f1> <cpu of f2>]
  setup "[$(issue 7 2026-01-01 bug | jq -c '.title = "Optimize the test file f.test.sh"')]"; nopush
  sed -i 's|^cat > /dev/null; echo x|cat > "$STUB/asked"; echo x|' "$STUB/codex"
  echo "$GO" > "$STUB/review.1"
  echo "$1" > "$STUB/cpu-f.test.sh"; echo "${2:-}" > "$STUB/cpu-f1.test.sh"; echo "${3:-}" > "$STUB/cpu-f2.test.sh"
  for c in 9 10 11; do
    jq -cn --argjson c "$c" '{time: "2026-11-01T00:00:00Z", how: "full", sha: "abc", files: {"f.test.sh": {result: "ok", sec: $c, cpu: $c}}}' >> "$ST/suiteruns.jsonl"
  done
  cat > "$STUB/mainrun-cmd" <<'EOF'
while IFS=$'\t' read -r k f; do
  [ "$k" = fail ] || continue; [[ $PWD == *.cases ]] || echo "$f: $(cat "$f" 2>/dev/null)" >> "$STUB/mainran"; printf '== %s\nok one\nok two\n' "$f"
  printf '== %s\n-- ok %s\nTESTRUN sec\t%s\t1\t%s\n' "$f" "$f" "$f" "$(cat "$STUB/cpu-$f")" >> "$CONVEYOR_TEST_LOG/r"
done < "$CONVEYOR_TEST_RERUN"
EOF
}

# D1. Bug it catches: an Optimize card, whose tests pass on main by design, is blocked for not failing there, or a
# change that keeps the file lands with no proof that it is faster. It runs alone with the change and is faster than
# its median: its record holds both numbers, the review is shown the Optimize check, and it lands.
t_optkeep() {
  local -x FILEMODE=1
  optcard 'echo fast > f.test.sh' 4
  [ "$(speedline)" = 'ok {"file":"f.test.sh","before":10,"after":4,"fix":"sped up","into":[]}' ] || fail "the record does not hold both CPU numbers: $(st 'select(.step == "bugproof")')"
  [ "$(cat "$STUB/mainran")" = 'f.test.sh: fast' ] || fail "the file did not run alone with the change: $(cat "$STUB/mainran" 2>&1)"
  grep -qx '# The Optimize check' "$STUB/asked" && grep -q 'passed in 4 CPU s, lower than its median on record, 10 CPU s' "$STUB/asked" \
    || fail "the review was not shown the Optimize check"
  [ -n "$(st 'select(.step == "landed") | .sha')" ] || fail "a faster Optimize card did not land: $(st 'select(.step | IN("blocked", "landed"))')"
}

# D1. Bug it catches: an Optimize card that keeps its file as slow as its median lands. It is blocked before review.
t_optslow() {
  local -x FILEMODE=1
  optcard 'echo fast > f.test.sh' 10
  [ "$(st 'select(.step == "blocked") | .reason')" = 'build: the file is not faster than its median on record (10 CPU s), as the verdict speed up asks: 10 CPU s now' ] && [ ! -e "$STUB/asked" ] \
    || fail "an Optimize card that is not faster was not blocked before review: $(st 'select(.step | IN("review", "blocked"))')"
  [ "$(st 'select(.step == "blocked") | .speedcheck')" = "$SPEEDV" ] || fail "the blocked line does not carry the speed check's version $SPEEDV: $(st 'select(.step == "blocked")')"
}

# D2. Bug it catches: a split into f1 and f2 (f removed) is blocked because f is gone, or is let through unrun. The two
# new files run alone with the change, and their CPU seconds summed (2 + 3) are lower than f's median.
t_optsplit() {
  local -x FILEMODE=1
  optcard 'rm f.test.sh; echo one > f1.test.sh; echo two > f2.test.sh' '' 2 3
  [ "$(speedline)" = 'ok {"file":"f.test.sh","before":10,"after":5,"fix":"split","into":["f1.test.sh","f2.test.sh"]}' ] || fail "the split's record does not hold its summed CPU seconds: $(st 'select(.step == "bugproof")')"
  [ "$(sort "$STUB/mainran" | tr '\n' '|')" = 'f1.test.sh: one|f2.test.sh: two|' ] || fail "the split's new files did not run alone with the change: $(cat "$STUB/mainran" 2>&1)"
  grep -q 'f1.test.sh, f2.test.sh passed in 5 CPU s summed (the median on record of f.test.sh is 10 CPU s): f1.test.sh 2 CPU s, f2.test.sh 3 CPU s' "$STUB/asked" \
    || fail "the review was not shown the split's numbers"
  [ -n "$(st 'select(.step == "landed") | .sha')" ] || fail "a faster split did not land: $(st 'select(.step | IN("blocked", "landed"))')"
}

# D3. Bug it catches: a delete is blocked for having no test that fails on main, or for having no file to time, or the
# review is never told what the file tested. The file runs alone on main's code as main has it, and the review is
# given its cases and asked for the test that covers each.
# The review names the covering tests on COVERED-BY lines (#74): they are no finding, so its GO holds, and they stay in
# its record, where the Tests page reads them.
t_optdelete() {
  local -x FILEMODE=1
  local GO=$'COVERED-BY: g.test.sh: one\nCOVERED-BY: g.test.sh: two\n'"$GO"
  optcard 'rm f.test.sh' 4
  [ "$(speedline)" = 'ok {"file":"f.test.sh","before":10,"after":null,"fix":"deleted","into":[]}' ] || fail "a delete's record: $(st 'select(.step == "bugproof")')"
  [ "$(cat "$STUB/mainran")" = 'f.test.sh: echo slow' ] || fail "the file did not run alone as main has it: $(cat "$STUB/mainran" 2>&1)"
  grep -qx '# The Optimize check' "$STUB/asked" && grep -qx -- '- one' "$STUB/asked" && grep -qx -- '- two' "$STUB/asked" \
    && grep -qF 'Name, for each of its cases, the test that still covers it after the change, each on its own line, exactly: `COVERED-BY: <its test file>: <its case>`' "$STUB/asked" \
    || fail "the review was not given the file's cases and asked for the test that covers each"
  [ -n "$(st 'select(.step == "landed") | .sha')" ] || fail "a delete did not land: $(st 'select(.step | IN("blocked", "landed", "review"))')"
  [ "$(st 'select(.step == "review") | .reason' | grep -c '^COVERED-BY: g\.test\.sh: ')" = 2 ] || fail "the review's record lost its COVERED-BY lines: $(st 'select(.step == "review")')"
}

# Bug it catches (#74): a merge recorded as a delete, so the Tests page could not name the file that took the cases of
# the file it removed. A change that removes the file and changes another test file is a merge into that file. What
# it records is the Optimize check's (optproof()) alone: the check is called on such a change in a card's worktree, as
# t_optdelete proves a whole card takes it there.
t_optmerge() {
  local -x FILEMODE=1
  optmain 4
  fx_wt 'rm f.test.sh; echo "echo slow" >> g.test.sh' f.test.sh 'echo slow' g.test.sh 'echo other'
  fx_in 'optproof c7 "$FXWT" "{\"number\": 7}" f.test.sh'
  [ "$RC" = 0 ] || fail "the Optimize check failed a merge: $(cat "$T/$CASE/run.out")"
  [ "$(speedline)" = 'ok {"file":"f.test.sh","before":10,"after":null,"fix":"merged","into":["g.test.sh"]}' ] || fail "a merge's record: $(st 'select(.step == "bugproof")')"
}
