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

# One card of #7 with the given labels, run by the loop: the cases of card()'s wiring of bugproof()'s exits (a proven
# card lands, an unproven one goes back to build then is blocked, a card that is not a bug skips the check), which only
# a whole card shows. Its build fixes a.txt (adds `two`) and adds a.test.sh holding <test>. The run on main (a worktree
# under cards/mainrun/) notes its folder and staged files in $STUB/mainran and runs a.test.sh; the reviewer's prompt
# is kept in $STUB/asked; one GO review. No push (nopush).
bugcard() { # <test> <label>...
  local t=$1; shift
  setup "[$(issue 7 2026-01-01 "$@")]"; nopush
  sed -i 's|^cat > /dev/null; echo x|cat > "$STUB/asked"; echo x|' "$STUB/codex"
  echo "$GO" > "$STUB/review.1"
  echo "echo two >> a.txt; printf '%s\n' '$t' > a.test.sh" > "$STUB/build"
  echo '{ pwd; git diff --cached --name-only; } >> "$STUB/mainran"; bash a.test.sh' > "$STUB/mainrun-cmd"
  loop run >/dev/null || fail "run exited non-zero"
}

# bugproof() called as card() calls it, on card c7 of #7 ($ISSUE, when set, is its issue json): its worktree on main
# runs <change>, staged, and main holds the <file> <content> pairs first (fx_wt). Each run on main runs
# $STUB/mainrun-cmd, which the case writes after setup. The check's exit is in $RC, its reason (BUGWHY) in $BW.
bugwt() { # <change> [<file> <content>]...
  local ISSUE=${ISSUE:-'{"number": 7}'}
  fx_wt "$@"
  fx_in 'bugproof c7 "$FXWT" "$ISSUE"; r=$?; printf "%s\n" "$BUGWHY" > "$T/$CASE/bugwhy"; exit $r'
  BW=$(cat "$T/$CASE/bugwhy" 2>/dev/null)
}
# bugwt() on a change that fixes a.txt (adds `two`; runs $FIX in its place when set, `:` for no fix) and, unless
# <test> is empty, writes <test> into a.test.sh (or the file $TF names), which main holds as `true`; main holds the
# <file> <content> pairs too. Each run on main notes its folder and staged files in $STUB/mainran and runs that test
# file. $TUNE, when set, is a jq filter of the pack (tune).
bugtest() { # <test> [<file> <content>]...
  local t=$1 tf=${TF:-a.test.sh}; shift
  setup '[]'
  [ -z "${TUNE:-}" ] || tune "$TUNE"
  echo '{ pwd; git diff --cached --name-only; } >> "$STUB/mainran"; '"bash '$tf'" > "$STUB/mainrun-cmd"
  bugwt "${FIX-echo two >> a.txt}${t:+; mkdir -p \"\$(dirname '$tf')\"; printf '%s\n' '$t' > '$tf'}" a.test.sh true "$@"
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
  # The card's test list (<card>.testlist, which the per-file run writes) stays after landing: tidy() does not remove it.
  local left=() f; for f in "$T/$CASE/cards"/*; do [ -e "$f" ] && [[ $f != *.testlist ]] && left+=("$f"); done
  [ -n "$(st 'select(.step == "landed") | .sha')" ] && [ "${#left[@]}" = 0 ] \
    || fail "the card did not land, or left a worktree: $(ls "$T/$CASE/cards")"
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

# Bug it catches: the proof run had no time limit for one hung test, so a new test that waits for what the unfixed
# code never writes held its card until stopped by hand. Here it hangs on main's code; its file's `# timeout: 2` line
# stops the file there, far before the run's own limit (testTimeout 15 s, the limit a file with no such line has, as in
# t_bughungdefault): the result names a.test.sh as timed out at 2 s, not 15 s, and it counts as failing without the
# fix (the check holds).
t_bughung() {
  TUNE='.tunables.testTimeout = 15' bugtest $'# timeout: 2\nuntil grep -qx two a.txt; do sleep 0.2; done' # sleep: the new test's own wait, which never ends on main's code
  hungsaid 2 'it was stopped there' 124 # 124: a file past its own limit ends the run as timed out (filecmd())
}
# The checks of t_bughung and t_bughungdefault: the result says a.test.sh timed out at <seconds> (the output's line
# ends `and <stop>`; the run's exit <exit>), counted as failing without the fix, and the check holds.
hungsaid() { # <seconds> <stop> <exit>
  grep -qxF "conveyor: a.test.sh timed out: it ran past its time limit, $1 s, and $2" "$FXWT.unfixed" \
    && grep -q "^The run failed there (exit $3): at least one fails without the fix" "$FXWT.unfixed" \
    && grep -qxF "a.test.sh timed out: it ran past its time limit, $1 s, and was stopped. A test that hangs without the fix counts as failing without it." "$FXWT.unfixed" \
    || fail "the proof run was not stopped at the hung file's limit, naming it, and counted as failing: $(head -40 "$FXWT.unfixed" 2>&1)"
  [ "$RC" = 0 ] || fail "a new test that hangs without the fix did not prove it (exit $RC): $BW"
}

# Bug it catches: a hung new test whose file has no `# timeout:` line was stopped by the run's own limit (testTimeout,
# 4 s here) with nothing naming it, so the run gave no failing file and did not count as proof; the card went back to
# build. The file is named as timed out at the testTimeout limit and counts as failing without the fix.
t_bughungdefault() {
  TUNE='.tunables.testTimeout = 4' bugtest 'until grep -qx two a.txt; do sleep 0.2; done' # sleep: the new test's own wait, which never ends on main's code
  hungsaid 4 'the run was stopped there' 124
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
# code too) is blocked, as with no fix to take out its test passes "without the fix". It is not run on main, the check
# holds, and the result says the change is test-only.
t_bugtestonly() {
  FIX=: bugtest 'grep -qx one a.txt'
  [ "$RC" = 0 ] && [ ! -e "$STUB/mainran" ] || fail "a test-only change was run on main or failed the check (exit $RC): $BW $(cat "$STUB/mainran" 2>&1)"
  grep -q '^The change is test-only: ' "$FXWT.unfixed" || fail "the result does not say the change is test-only: $(cat "$FXWT.unfixed" 2>&1)"
  [ ! -e "$T/$CASE/cards/mainrun" ] || fail "the check left its run's folder: $(ls "$T/$CASE/cards/mainrun")"
}

# #515. Main holds a.js; a bug card fixes its // comment and adds a test of what a.js already does (with a # comment).
COMMENTMAIN=$'// x is two\nexport const x = 1;'
COMMENTFIX='sed -i "s|^// x is two|// x is one|" a.js'
COMMENTTEST='grep -qxF "export const x = 1;" a.js # a.js sets x to one'
# D1. Bug it catches: a bug card whose product change is comments only, with a test file, is blocked with "the new
# tests pass without the fix", which no comment fix can avoid. It is not run on main, the check holds, and the result
# says the product change is comments only.
t_bugcomments() {
  FIX=$COMMENTFIX bugtest "$COMMENTTEST" a.js "$COMMENTMAIN"
  [ "$RC" = 0 ] && [ ! -e "$STUB/mainran" ] || fail "a comments-only change was run on main or failed the check (exit $RC): $BW $(cat "$STUB/mainran" 2>&1)"
  grep -q '^The change is comments only in its product files: ' "$FXWT.unfixed" \
    || fail "the result does not say the product change is comments only: $(cat "$FXWT.unfixed" 2>&1)"
}

# D2. Bug it catches: a product change with one real code line beside its comment fix is let skip the check as
# comments only. Its test runs on main, passes there, and the check fails with "the new tests pass without the fix".
t_bugcommentcode() {
  FIX="$COMMENTFIX; echo 'export const y = 2;' >> a.js" bugtest "$COMMENTTEST" a.js "$COMMENTMAIN"
  [ "$RC" = 1 ] && [ "$BW" = "the new tests pass without the fix, so they do not prove it" ] \
    || fail "a comment fix with a code line was not failed as unproved (exit $RC): $BW"
  grep -q '/cards/mainrun/' "$STUB/mainran" || fail "its test was not run on main: $(cat "$STUB/mainran" 2>&1)"
}

# Bug it catches: commentsonly() reads each changed line alone, so a change that puts code between a /* line and a */
# line (the code no longer runs), or edits a # line in a shell heredoc (text the program prints), is let skip the
# check; and so are a/**/b in js read as ab, and two .css and .html changes that look like comment fixes but change
# the page: 16/**/px (two CSS tokens, the rule dropped) read as 16px, and a new <!-- --> in an empty <nav> (a node:
# the Board sees a first child and draws no tabs). Each change here is staged beside a test file (but notest, staged
# alone) in a fresh repo and given to commentsonly().
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
  # <name> <file> <sed script> [notest]: the file changed so and, unless notest, a.test.js changed, staged; notes
  # "<name>=<0 when comments only>".
  try() {
    sed -i "$3" "$r/$2" && { [ "${4-}" = notest ] || echo 'ok(1);' >> "$r/a.test.js"; } && git -C "$r" add -A || fail "staging $1"
    # shellcheck disable=SC2034 # TESTRX and TESTRUNNERS are read by testpaths(), loaded below
    got+=" $1=$( . "$SRC/lib/portable.sh"; TESTRX='\.test\.' TESTRUNNERS=''
      eval "$(sed -n '/^testpaths() {/,/^}/p' "$SRC/lib/issues.sh"; sed -n '/^uncomment() {/,/^}/p; /^commentsonly() {/,/^}/p' "$SRC/lib/testrun.sh")"
      commentsonly "$r"; echo $?)"
    git -C "$r" reset -q --hard
  }
  try js app.js 's|x is two|x is one|'
  # #713: the same comment fix with no test file changed is not comments only (1), so bugproof() does not let it skip.
  try notest app.js 's|x is two|x is one|' notest
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
  [ "$got" = ' js=0 notest=1 wrap=1 template=1 jsblank=0 jstoken=1 csstoken=1 htmlnode=1 heredoc=1 blocklsep=1 blockcr=1 linepsep=1' ] \
    || fail "commentsonly() does not tell js comment fixes (0) from code changes (1): $got"
}

# Bug it catches: a bug card that adds no test at all goes to review unchecked; or (#137) it is failed with "the new
# tests pass without the fix", though no test ran. The check fails, its reason that no test file was found and the
# patterns that looked (the default, as the pack sets none); it runs nothing on main (does it select a test? Here it
# does: the links give its a.txt the test file a.test.sh) and writes no bugproof line.
t_bugnotest() {
  bugtest ''
  local why; why="no test file found in the change (patterns: $(jq -r '.properties.tests.properties.patterns.default | join(", ")' "$SRC/schema/pack.schema.json")); set tests.patterns in .conveyor/project.json"
  [ "$RC" = 1 ] && [ "$BW" = "$why" ] || fail "a change with no test did not fail the check with the no-test reason (exit $RC): $BW"
  grep -qF "No test file found in the change (patterns: __tests__/, " "$FXWT.unfixed" || fail "the result does not say no test file was found: $(cat "$FXWT.unfixed" 2>&1)"
  [ ! -e "$STUB/mainran" ] || fail "a card with no test file ran a test on main: $(cat "$STUB/mainran")"
  [ -z "$(st 'select(.step == "bugproof")' 2>/dev/null)" ] || fail "a code change with no test was let skip the check: $(st 'select(.step == "bugproof")')"
}

# #137. Bug it catches: a project whose tests are src/test-<name>.mjs, set in its pack's tests.patterns, had its test
# file taken for no test file, never run on main, and the card blocked as "the new tests pass without the fix". The
# file is found, runs alone on main's code without the fix and fails there, and the check holds.
t_bugpatterns() {
  TF=src/test-a.mjs TUNE='.tests.patterns = ["src/test-*.mjs"]' bugtest 'grep -qx two a.txt'
  [ "$(sed 1d "$STUB/mainran" | tr '\n' ' ')" = 'src/test-a.mjs ' ] && [[ $(head -1 "$STUB/mainran") == */cards/mainrun/* ]] \
    || fail "the run on main was not of the card's src/test-a.mjs alone: $(cat "$STUB/mainran" 2>&1)"
  [ "$RC" = 0 ] && grep -q '^The run failed there (exit 1)' "$FXWT.unfixed" \
    || fail "the test that fails on main did not prove the fix (exit $RC): $BW $(cat "$FXWT.unfixed" 2>&1)"
}

# #137. Bug it catches: a pack whose test command cannot run one file alone has no way to run a change's test files.
# With test.fileCommand set, the check runs it once for each test file, given the file, in place of test.command:
# the file fails on main without the fix, and the check holds.
t_bugfilecommand() {
  TUNE='.test.fileCommand = "case $PWD in */mainrun/*) echo \"$CONVEYOR_TEST_FILE\" >> \"$STUB/fileran\" ;; esac; bash"' bugtest 'grep -qx two a.txt'
  [ "$(cat "$STUB/fileran" 2>&1)" = a.test.sh ] && [ ! -e "$STUB/mainran" ] \
    || fail "the check did not run the test file alone with test.fileCommand: $(cat "$STUB/fileran" "$STUB/mainran" 2>&1)"
  [ "$RC" = 0 ] && grep -q '^The run failed there (exit 1)' "$FXWT.unfixed" \
    || fail "the test run through test.fileCommand did not prove the fix (exit $RC): $BW $(cat "$FXWT.unfixed" 2>&1)"
}

# #711. Bug it catches: the guides said every card with a test file and no test.fileCommand stops at its test step,
# but a bug card with a fix cannot run its bug-card check (bugproof() exit 2; t_wideoffnolist checks that stop), and
# card() blocks it at Build, while a test-only or comments-only bug card skips the check and stops at its test step.
# #713. Bug it catches: they said so of comments in any file, but commentsonly() takes only JavaScript and TypeScript
# files (t_bugcommentsyntax: a # line in a .sh file is a fix), so a bug card that changes a shell comment stops at Build.
# Nor did they say a test file must change too (t_bugcommentsyntax notest: a js comment fix alone is a fix).
# The pages and the schema have no behaviour to run, so their text is read.
t_bugnofilecmd() {
  local p
  for p in conveyor/README.md docs/configuration.md; do
    tr '\n' ' ' < "$SRC/../$p" | tr -s ' ' | grep -qiE 'a bug card with a test file and a fix stops earlier, at (its )?Build' \
      || fail "$p does not say a bug card with a fix and no test.fileCommand stops at Build"
    tr '\n' ' ' < "$SRC/../$p" | tr -s ' ' | grep -qiE 'a bug card whose change is only test files, or test files and only comments in other `\.js`, `\.mjs`, `\.cjs`, `\.ts`, `\.mts` or `\.cts` files, has no check to run,? and( it)? stops at its test step\. A comment change with no test file in the change, or in any other file, such as a `\.sh` or `\.py` file, is a fix, and that card stops at Build' \
      || fail "$p does not say only a JavaScript or TypeScript comments-only bug card with a test file stops at its test step"
  done
  jq -r .properties.test.properties.fileCommand.description "$SRC/schema/pack.schema.json" \
    | grep -qF 'a bug card with a fix (any change but test files alone, or test files with comments in .js, .mjs, .cjs, .ts, .mts and .cts files; a comment change with no test file, or in a .sh or .py file, is a fix) at Build' \
    || fail "the pack schema's test.fileCommand does not say a comment change with no test file or in a .sh or .py file makes a bug card with a fix"
}

# bugwt() on a change that writes <card> into the product file <file>, which holds <main> on main: its fix and its new
# test are both in that file, and it adds no test file. Each run on main notes in $STUB/mainran its staged files and
# <file> as it is there, then runs <runner>.
inlinewt() { # <file> <main> <card> <runner>
  setup '[]'; mkdir -p "$(dirname "$R/$1")"
  printf '%s\n' "$3" > "$STUB/card-file"
  { echo "{ git diff --cached --name-only; cat '$1'; } >> \"\$STUB/mainran\""; printf '%s\n' "$4"; } > "$STUB/mainrun-cmd"
  bugwt "mkdir -p \"\$(dirname '$1')\" && cp \"\$STUB/card-file\" '$1'" "$1" "$2"
}
# A Rust file, src/lib.rs, whose f() returns 1 on main. The runner stands in for cargo test (no Rust toolchain is
# needed): the file's test passes when f() returns the number its assert_eq! asks for.
RUSTMAIN=$'pub fn f() -> i32 {\n    1\n}'
RUSTRUN='w=$(sed -n "s/.*assert_eq!([a-z:]*f(), \([0-9]*\)).*/\1/p" src/lib.rs); [ -z "$w" ] || grep -Eq "^ *(pub fn f\(\) -> i32 \{ )?$w( \}.*)?$" src/lib.rs'

# #140 D1. Bug it catches: a bug card whose only new test is a Rust #[test] inside the product file it fixes had no
# test file to run without the fix, and was blocked. The check stages src/lib.rs on main's code with the new test
# module and without the fix: the test fails there, and the check holds.
t_buginlinerust() {
  inlinewt src/lib.rs "$RUSTMAIN" $'pub fn f() -> i32 {\n    2\n}\n\n#[cfg(test)]\nmod tests {\n    #[test]\n    fn two() {\n        assert_eq!(super::f(), 2);\n    }\n}' "$RUSTRUN"
  [ "$(cat "$STUB/mainran" 2>&1)" = "src/lib.rs"$'\n'"$RUSTMAIN"$'\n#[cfg(test)]\nmod tests {\n    #[test]\n    fn two() {\n        assert_eq!(super::f(), 2);\n    }\n}' ] \
    || fail "the run on main was not of main's f() with the new test module alone: $(cat "$STUB/mainran" 2>&1)"
  grep -qxF -- '- src/lib.rs (its inline tests, with the rest of its change taken out)' "$FXWT.unfixed" && grep -q '^The run failed there (exit 1)' "$FXWT.unfixed" \
    || fail "the result does not say the inline test fails without the fix: $(cat "$FXWT.unfixed" 2>&1)"
  [ "$RC" = 0 ] || fail "the inline test that fails without the fix did not prove it (exit $RC): $BW"
}

# #140 D1. Bug it catches: a Python doctest added to the docstring of the function a bug card fixes was no test the
# check could run. The real doctest runner, on main's code with the new docstring and without the fix, fails, and the
# check holds.
t_buginlinedoctest() {
  inlinewt lib.py $'def double(x):\n    return x * 3' $'def double(x):\n    """\n    >>> double(2)\n    4\n    """\n    return x * 2' \
    'PYTHONDONTWRITEBYTECODE=1 python3 -m doctest lib.py'
  [ "$(cat "$STUB/mainran" 2>&1)" = $'lib.py\ndef double(x):\n    """\n    >>> double(2)\n    4\n    """\n    return x * 3' ] \
    || fail "the run on main was not of main's double() with the new doctest alone: $(cat "$STUB/mainran" 2>&1)"
  [ "$RC" = 0 ] && grep -qxF -- '- lib.py (its inline tests, with the rest of its change taken out)' "$FXWT.unfixed" && grep -q '^The run failed there (exit 1)' "$FXWT.unfixed" \
    || fail "the doctest that fails without the fix did not prove it (exit $RC): $BW $(cat "$FXWT.unfixed" 2>&1)"
}

# #140 D2. Bug it catches: a new test written on the same line as the fix cannot be run without the fix, and the card
# was blocked as "no test file found" or as "the new tests pass without the fix", though nothing ran. The check fails
# with the reason that names the file, and nothing runs on main.
t_buginlineshared() {
  inlinewt src/lib.rs 'pub fn f() -> i32 { 1 }' 'pub fn f() -> i32 { 2 } #[test] fn two() { assert_eq!(f(), 2); }' "$RUSTRUN"
  local why='the new test and the fix are in the same lines of src/lib.rs; bugproof cannot take out the fix alone'
  [ "$RC" = 1 ] && [ "$BW" = "$why" ] && [ "$(head -n 1 "$FXWT.unfixed")" = "${why^}." ] \
    || fail "the check did not fail with the shared-lines reason (exit $RC): $BW $(cat "$FXWT.unfixed" 2>&1)"
  [ ! -e "$STUB/mainran" ] || fail "a fix it could not take out was run on main: $(cat "$STUB/mainran")"
}

# bugwt() on a change that only rewords a comment of s.sh (`# an old word` becomes `# a new word`), on a main that holds
# s.sh and w.test.sh holding <test>; its issue's body is <body>. The run on main runs each file its CONVEYOR_TEST_RERUN
# list names as `fail`; with none, it selects nothing (its log says files=0), as a runner does for a comment-only
# change. Each run notes in $STUB/mainran its staged files, whether s.sh holds the fix and its fail lines.
commentwt() { # <test> <body>
  setup '[]'
  local ISSUE; ISSUE=$(jq -cn --arg b "$2" '{number: 7, body: $b}')
  cat > "$STUB/mainrun-cmd" <<'EOF'
n=0 r=0; while IFS=$'\t' read -r k f; do [ "$k" = fail ] || continue; n=$((n + 1)); bash "$f" || r=1; done < "${CONVEYOR_TEST_RERUN:-/dev/null}"
echo "staged: $(git diff --cached --name-only | tr '\n' ' ')fix: $(grep -c new s.sh) ran: $n" >> "$STUB/mainran"
[ $n != 0 ] || echo 'TESTRUN files=0 of=1' >> "$CONVEYOR_TEST_LOG/r"; exit $r
EOF
  bugwt "printf '#!/usr/bin/env bash\n# a new word\n' > s.sh" s.sh $'#!/usr/bin/env bash\n# an old word' w.test.sh "$1"
}

# D1. Bug it catches: a comment-only bug card selects no test (no test file is linked to s.sh), so it was blocked as
# "the new tests pass without the fix", though the test file its issue's Done-when names fails on main's comment. That
# file runs alone with the fix (passes) and without it (fails), nothing else runs on main, the result says so, and the
# check holds.
t_bugcomment() {
  commentwt '! grep -q old s.sh' $'body\n\n## Done when\nw.test.sh fails on main and passes with the fix.'
  [ "$(cat "$STUB/mainran" 2>&1)" = $'staged: s.sh fix: 1 ran: 1\nstaged: fix: 0 ran: 1' ] \
    || fail "the named test did not run alone with the fix and without it: $(cat "$STUB/mainran" 2>&1)"
  [ "$RC" = 0 ] && grep -q '^They pass with the fix, and the run without it failed (exit 1)' "$FXWT.unfixed" \
    || fail "a comment-only change proved by its named test failed the check, or the result does not say so (exit $RC): $BW $(cat "$FXWT.unfixed" 2>&1)"
}

# D2. Bug it catches: a comment-only card whose named test passes on main's code too is let through as proven. The
# check fails with "the new tests pass without the fix", as for any unproven bug card.
t_bugcommentpasses() {
  commentwt 'grep -q word s.sh' $'body\n\n## Done when\nw.test.sh passes.'
  [ "$RC" = 1 ] && [ "$BW" = "the new tests pass without the fix, so they do not prove it" ] \
    && grep -q '^They all passed without the fix: the new tests pass without the fix' "$FXWT.unfixed" \
    || fail "a comment-only change whose named test passes on main did not fail the check (exit $RC): $BW $(cat "$FXWT.unfixed" 2>&1)"
}

# Bug it catches: a comment-only card is taken as proven by a named test that fails on main but fails with the fix
# too (it proves nothing of the fix). The check fails, its result saying the test fails with the fix.
t_bugcommentfixfails() {
  commentwt 'grep -q newer s.sh' $'body\n\n## Done when\nw.test.sh passes.'
  [ "$RC" = 1 ] && grep -q '^They failed with the fix (exit 1): the new tests pass without the fix' "$FXWT.unfixed" \
    || fail "a named test that fails with the fix too passed the check (exit $RC): $BW $(cat "$FXWT.unfixed" 2>&1)"
}

# D3. Bug it catches: a comment-only card whose issue names no test file is blocked by a check that has nothing to run,
# or goes on with no word of why. The check holds, with a bugproof line (skipped) saying why, and the result says so.
t_bugcommentnamed() {
  commentwt 'false' $'body\n\n## Done when\nThe comment says new.'
  [ "$(st 'select(.step == "bugproof") | "\(.result): \(.reason)"')" = "skipped: the change selects no test (no test file is linked to the files it touches), and the issue's Done-when names no test file" ] \
    || fail "the card's record does not say the check was skipped and why: $(st 'select(.step == "bugproof")')"
  [ "$RC" = 0 ] && grep -q '^The bug-card check was skipped: ' "$FXWT.unfixed" \
    || fail "a comment-only change naming no test did not hold, said skipped (exit $RC): $BW $(cat "$FXWT.unfixed" 2>&1)"
  recok "$ST/cards.jsonl" "bugproof()"
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

# The median on record of f.test.sh, 10 CPU s: three whole-suite runs of 9, 10 and 11 (after setup).
median10() {
  local c; for c in 9 10 11; do
    jq -cn --argjson c "$c" '{time: "2026-11-01T00:00:00Z", how: "full", sha: "abc", files: {"f.test.sh": {result: "ok", sec: $c, cpu: $c}}}' >> "$ST/suiteruns.jsonl"
  done
}
# speedproof() called as card() calls it, on card c7 of #7, a bug filed from the Tests page to speed up f.test.sh
# (`echo slow` on main, its median on record 10 CPU s: median10), whose change rewrites f.test.sh. The file's run
# with the change (under cards/mainrun/) notes its folder, the file as it runs and its list in $STUB/mainran, times
# the file at <cpu> CPU s and exits <exit>. When the check fails, the card is blocked as card() blocks it
# (lib/card.sh: SPEEDCHECKED set). The check's exit is in $RC.
speedwt() { # <cpu> [exit]
  setup '[]'; median10
  echo '{ pwd; cat f.test.sh; cat "$CONVEYOR_TEST_RERUN"; } >> "$STUB/mainran"; printf "TESTRUN sec\tf.test.sh\t1\t%s\n" '"$1"' > "$CONVEYOR_TEST_LOG/r"; exit '"${2:-0}" > "$STUB/mainrun-cmd"
  fx_wt 'echo fast > f.test.sh' f.test.sh 'echo slow'
  fx_in 'speedproof c7 "$FXWT" "{\"number\": 7, \"title\": \"Speed up the test file f.test.sh\"}" f.test.sh \
    || { r=$?; SPEEDCHECKED=$SPEEDCHECK block c7 7 "$FXWT" "build: $(<"$FXWT.unfixed")"; exit $r; }'
}
speedline() { st 'select(.step == "bugproof") | "\(.result) \(.speed | tojson)"'; }
SPEEDV=$(sed -n 's/^SPEEDCHECK=//p' "$SRC/lib/testrun.sh") # the version of the speed check, as testrun.sh sets it

# D1. Bug it catches: a speed-up card, whose tests pass on main by design, is blocked for not failing there, or goes on
# with no proof that the file is faster. Its file runs alone with the change and is faster than its median on record:
# the check holds, the result shows the numbers, and both numbers are on its record.
t_speedfaster() {
  speedwt 4
  [ "$RC" = 0 ] || fail "a faster speed-up change failed the check: $(cat "$FXWT.unfixed" "$T/$CASE/run.out" 2>&1)"
  [ "$(speedline)" = 'ok {"file":"f.test.sh","before":10,"after":4,"fix":"sped up","into":[]}' ] || fail "the record does not hold both CPU numbers: $(st 'select(.step == "bugproof")')"
  [[ $(head -1 "$STUB/mainran") == */cards/mainrun/* ]] && [ "$(sed -n 2p "$STUB/mainran")" = fast ] && grep -qx $'fail\tf.test.sh' "$STUB/mainran" \
    || fail "the file did not run alone with the change: $(cat "$STUB/mainran" 2>&1)"
  grep -q 'passed in 4 CPU s, lower than its median on record, 10 CPU s' "$FXWT.unfixed" || fail "the result does not show the numbers: $(cat "$FXWT.unfixed")"
  recok "$ST/cards.jsonl" "speedproof()"
}

# D2. Bug it catches: a speed-up card whose file is as slow as its median lands as a speed-up. The check fails with the
# "not faster" reason naming both numbers, and no budget (#349).
t_speedslow() {
  speedwt 10
  [ "$RC" != 0 ] && [ "$(st 'select(.step == "blocked") | .reason')" = 'build: the file is not faster than its median on record (10 CPU s), as the verdict speed up asks: 10 CPU s now' ] \
    || fail "a speed-up change that is not faster did not fail the check (exit $RC): $(st 'select(.step == "blocked")')"
  [ "$(speedline)" = 'fail {"file":"f.test.sh","before":10,"after":10,"fix":"sped up","into":[]}' ] || fail "the record does not hold both CPU numbers: $(st 'select(.step == "bugproof")')"
  # #180: with no version on its line, a later change to the check could not tell this block from others.
  [ "$(st 'select(.step == "blocked") | .speedcheck')" = "$SPEEDV" ] || fail "the blocked line does not carry the speed check's version $SPEEDV: $(st 'select(.step == "blocked")')"
}

# Bug it catches: a speed-up card whose file fails with the change is let through because it ran fast.
t_speedfails() {
  speedwt 4 1
  [ "$RC" != 0 ] && [ "$(st 'select(.step == "blocked") | .reason')" = 'build: the file f.test.sh fails with the change (exit 1)' ] \
    || fail "a speed-up change whose file fails did not fail the check (exit $RC): $(st 'select(.step == "blocked")')"
}

# The case folder of an Optimize issue filed from the Tests page for f.test.sh (on main, `echo slow`, with g.test.sh,
# `echo other`), its median on record 10 CPU s (median10). Each run under cards/mainrun/ runs the files of its list:
# it notes each, with what it holds there, in $STUB/mainran, names the cases one and two of each as passed, and times
# each at the CPU seconds $STUB/cpu-<file> holds. The run of f on main for the build's brief (speedbrief(), under
# cards/mainrun/<card>.cases) is not noted: ownbudget.test.sh holds that brief to its lines.
optmain() { # <cpu of f> [<cpu of f1> <cpu of f2>]
  setup '[]'; median10
  echo "$1" > "$STUB/cpu-f.test.sh"; echo "${2:-}" > "$STUB/cpu-f1.test.sh"; echo "${3:-}" > "$STUB/cpu-f2.test.sh"
  # Run once for each file, as test.fileCommand runs it: the file is CONVEYOR_TEST_FILE.
  cat > "$STUB/mainrun-cmd" <<'EOF'
f=$CONVEYOR_TEST_FILE
[[ $PWD == *.cases ]] || echo "$f: $(cat "$f" 2>/dev/null)" >> "$STUB/mainran"; printf '== %s\nok one\nok two\n' "$f"
printf '== %s\n-- ok %s\nTESTRUN sec\t%s\t1\t%s\n' "$f" "$f" "$f" "$(cat "$STUB/cpu-$f")" >> "$CONVEYOR_TEST_LOG/r"
EOF
}
# optproof() called as card() calls it, on card c7 of the Optimize issue for f.test.sh, whose change runs <change> in
# its worktree on main (optmain's). When the check fails, the card is blocked as card() blocks it (lib/card.sh:
# SPEEDCHECKED set). The check's exit is in $RC.
optwt() { # <change> <cpu of f> [<cpu of f1> <cpu of f2>]
  local b=$1; shift
  optmain "$@"
  fx_wt "$b" f.test.sh 'echo slow' g.test.sh 'echo other'
  fx_in 'optproof c7 "$FXWT" "{\"number\": 7, \"title\": \"Optimize the test file f.test.sh\"}" f.test.sh \
    || { r=$?; SPEEDCHECKED=$SPEEDCHECK block c7 7 "$FXWT" "build: $(<"$FXWT.unfixed")"; exit $r; }'
}

# D1. Bug it catches: an Optimize card, whose tests pass on main by design, is blocked for not failing there, or a
# change that keeps the file lands with no proof that it is faster. It runs alone with the change and is faster than
# its median: the check holds, its record holds both numbers, and the result shows them.
t_optkeep() {
  optwt 'echo fast > f.test.sh' 4
  [ "$RC" = 0 ] || fail "a faster Optimize change failed the check: $(cat "$FXWT.unfixed" "$T/$CASE/run.out" 2>&1)"
  [ "$(speedline)" = 'ok {"file":"f.test.sh","before":10,"after":4,"fix":"sped up","into":[]}' ] || fail "the record does not hold both CPU numbers: $(st 'select(.step == "bugproof")')"
  [ "$(cat "$STUB/mainran")" = 'f.test.sh: fast' ] || fail "the file did not run alone with the change: $(cat "$STUB/mainran" 2>&1)"
  grep -q 'passed in 4 CPU s, lower than its median on record, 10 CPU s' "$FXWT.unfixed" || fail "the result does not show the numbers: $(cat "$FXWT.unfixed")"
  # Bug it catches (#614): the review was told a kept file must cost less than its figure, save for stabilise, so it
  # flagged a merge the engine passes at the file's figure plus the merged file's (t_optmergeinto). The whole rule is
  # matched, so a second, unconditional "less than that figure" limit for a kept file also fails it. The review's
  # prompt (OPTREVIEW, which card() gives the review of an Optimize card) is text with no behaviour to run, so it is read.
  fx_in 'printf "%s\n" "$OPTREVIEW"'
  tr '\n' ' ' < "$T/$CASE/run.out" | grep -qF 'A file kept must cost less than that figure; for stabilise, no more than it; and, when another test file is merged into it, no more than that figure plus the median on record of each test file merged into it. The files of a split' \
    || fail "the review is not told one limit for a kept file, with the limit of a merge into it"
}

# D1. Bug it catches: an Optimize card that keeps its file as slow as its median lands. The check fails, and the
# card's blocked line carries the speed check's version.
t_optslow() {
  optwt 'echo fast > f.test.sh' 10
  [ "$RC" != 0 ] && [ "$(st 'select(.step == "blocked") | .reason')" = 'build: the file is not faster than its median on record (10 CPU s), as the verdict speed up asks: 10 CPU s now' ] \
    || fail "an Optimize change that is not faster did not fail the check (exit $RC): $(st 'select(.step == "blocked")')"
  [ "$(st 'select(.step == "blocked") | .speedcheck')" = "$SPEEDV" ] || fail "the blocked line does not carry the speed check's version $SPEEDV: $(st 'select(.step == "blocked")')"
}

# D2. Bug it catches: a split into f1 and f2 (f removed) is failed because f is gone, or is let through unrun. The two
# new files run alone with the change, and their CPU seconds summed (2 + 3) are lower than f's median.
t_optsplit() {
  optwt 'rm f.test.sh; echo one > f1.test.sh; echo two > f2.test.sh' '' 2 3
  [ "$RC" = 0 ] || fail "a faster split failed the check: $(cat "$FXWT.unfixed" "$T/$CASE/run.out" 2>&1)"
  [ "$(speedline)" = 'ok {"file":"f.test.sh","before":10,"after":5,"fix":"split","into":["f1.test.sh","f2.test.sh"]}' ] || fail "the split's record does not hold its summed CPU seconds: $(st 'select(.step == "bugproof")')"
  [ "$(sort "$STUB/mainran" | tr '\n' '|')" = 'f1.test.sh: one|f2.test.sh: two|' ] || fail "the split's new files did not run alone with the change: $(cat "$STUB/mainran" 2>&1)"
  grep -q 'f1.test.sh, f2.test.sh passed in 5 CPU s summed (the median on record of f.test.sh is 10 CPU s): f1.test.sh 2 CPU s, f2.test.sh 3 CPU s' "$FXWT.unfixed" \
    || fail "the result does not show the split's numbers: $(cat "$FXWT.unfixed")"
}

# D3. Bug it catches: a delete is failed for having no test that fails on main, or for having no file to time, or the
# review is never told what the file tested. The file runs alone on main's code as main has it, the check holds, and
# the result gives its cases and asks for the test that covers each.
t_optdelete() {
  optwt 'rm f.test.sh' 4
  [ "$RC" = 0 ] || fail "a delete failed the check: $(cat "$FXWT.unfixed" "$T/$CASE/run.out" 2>&1)"
  [ "$(speedline)" = 'ok {"file":"f.test.sh","before":10,"after":null,"fix":"deleted","into":[]}' ] || fail "a delete's record: $(st 'select(.step == "bugproof")')"
  [ "$(cat "$STUB/mainran")" = 'f.test.sh: echo slow' ] || fail "the file did not run alone as main has it: $(cat "$STUB/mainran" 2>&1)"
  grep -qx -- '- one' "$FXWT.unfixed" && grep -qx -- '- two' "$FXWT.unfixed" \
    && grep -qF 'Name, for each of its cases, the test that still covers it after the change, each on its own line, exactly: `COVERED-BY: <its test file>: <its case>`' "$FXWT.unfixed" \
    || fail "the result does not give the file's cases and ask for the test that covers each: $(cat "$FXWT.unfixed")"
  # The review names the covering tests on COVERED-BY lines (#74): they are no finding, so its GO holds (verdict()),
  # and the review's record keeps them: card() records the review's lines that grep -Ev "$UNRECORDED" leaves.
  printf '%s\n' 'COVERED-BY: g.test.sh: one' 'COVERED-BY: g.test.sh: two' "$GO" > "$FXWT.review"
  fx_in 'verdict "$FXWT.review"; grep -Ev "$UNRECORDED" "$FXWT.review"'
  [ "$(head -n1 "$T/$CASE/run.out")" = GO ] || fail "a review's COVERED-BY lines were taken for findings: $(cat "$T/$CASE/run.out")"
  [ "$(grep -c '^COVERED-BY: g\.test\.sh: ' "$T/$CASE/run.out")" = 2 ] || fail "the review's record lost its COVERED-BY lines: $(cat "$T/$CASE/run.out")"
}

# Bug it catches (#74): a merge recorded as a delete, so the Tests page could not name the file that took the cases of
# the file it removed. A change that removes the file and changes another test file is a merge into that file. What
# it records is the Optimize check's (optproof()) alone: the check is called on such a change in a card's worktree.
t_optmerge() {
  optmain 4
  fx_wt 'rm f.test.sh; echo "echo slow" >> g.test.sh' f.test.sh 'echo slow' g.test.sh 'echo other'
  fx_in 'optproof c7 "$FXWT" "{\"number\": 7}" f.test.sh'
  [ "$RC" = 0 ] || fail "the Optimize check failed a merge: $(cat "$T/$CASE/run.out")"
  [ "$(speedline)" = 'ok {"file":"f.test.sh","before":10,"after":null,"fix":"merged","into":["g.test.sh"]}' ] || fail "a merge's record: $(st 'select(.step == "bugproof")')"
}
