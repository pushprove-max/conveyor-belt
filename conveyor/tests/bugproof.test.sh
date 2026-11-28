#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the bug-card check (bugproof.sh bugproof()): a bug card's new tests must fail on main's code without the fix.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# A page of the repository says <text> (lines joined, spaces folded). Each case file that calls it defines its own, named after the file: the bug check puts only the card's test files on main's code, where a helper in lib.sh is missing, and the runner sources the case files into one shell, where one name cannot be defined twice.
pagesays_bugproof() { tr '\n' ' ' < "$SRC/../$1" | tr -s ' ' | grep -qF -- "$2" || fail "$1 does not say \"$2\": $3"; } # <page> <text> <what the run showed>

# The control record's rule "Push when a card lands" off, after setup: no case here checks a push, and the push after a
# landing was about a seventh of a landing card's CPU (where the pack sets test.fileCommand, it runs the landing's test
# files before the push, pushtests(); with the default pack it runs none).
nopush() { jq -c '.rules.push = false' "$ST/control.json" > "$STUB/c.new" && mv "$STUB/c.new" "$ST/control.json" || fail "the control record"; }

# card.sh cardbuild() on card c7 of #7 with the given labels, its worktree on main, as card() takes it (its locals): a
# card that is not a bug skips the check (cardbuild() reads the labels), and an unproven card goes back to build with
# the reason in its brief and its build line, then is blocked. Its build fixes a.txt (adds `two`) and adds a.test.sh
# holding <test>. The run on main (a worktree under cards/mainrun/) notes its folder and staged files in
# $STUB/mainran and runs a.test.sh. What cardbuild() leaves in go is the last line of run.out (fx_in).
bugcard() { # <test> <label>...
  local t=$1 ISSUE; shift
  setup '[]'; ISSUE=$(issue 7 2026-01-01 "$@")
  echo "echo two >> a.txt; printf '%s\n' '$t' > a.test.sh" > "$STUB/build"
  echo '{ pwd; git diff --cached --name-only; } >> "$STUB/mainran"; bash a.test.sh' > "$STUB/mainrun-cmd"
  FXWT=$T/$CASE/cards/c7
  git -C "$R" worktree add -q --detach "$FXWT" || fail "the card's worktree could not be made"
  fx_in 'c=c7 n=7 br="" mode="" wt=$FXWT issue=$ISSUE sprompt=brief sf="" go=end; cardbuild; echo "go $go"'
}

# bugproof.sh bugproof() called as card() calls it, on card c7 of #7 ($ISSUE, when set, is its issue json): its worktree on main
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
# its test runs on main with the fix in it, or the review is not shown the result. The check (bugwt()) runs the test on
# main's code with the card's test file alone; it holds, so the card goes on to its review (card.sh bugstep(): nothing),
# not back to build; the result the review is shown (<worktree>.unfixed) says that it failed there.
t_bugfails() {
  bugtest 'grep -qx two a.txt'
  [ "$RC" = 0 ] && [ -z "$(eng "bugstep $RC")" ] || fail "a bug card whose new test fails on main did not go on to its review: the check's exit $RC, bugstep '$(eng "bugstep $RC")': $BW"
  [ "$(sed 1d "$STUB/mainran" | tr '\n' ' ')" = 'a.test.sh ' ] && [[ $(head -1 "$STUB/mainran") == */cards/mainrun/* ]] \
    || fail "the run on main was not of main's code with the card's test file alone: $(cat "$STUB/mainran" 2>&1)"
  grep -q '^The run failed there (exit 1)' "$FXWT.unfixed" || fail "the review's result does not say the new test fails on main: $(cat "$FXWT.unfixed" 2>&1)"
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
  [ "$(tail -n 1 "$T/$CASE/run.out")" = "go end" ] && [ "$(st 'select(.step == "blocked") | .reason')" = "build: the new tests pass without the fix, so they do not prove it" ] \
    || fail "a bug card whose test still passed on main after its second build was not blocked before review: $(tail -n 3 "$T/$CASE/run.out"): $(st 'select(.step | IN("review", "blocked"))')"
  recok "$ST/cards.jsonl" "the bug card's builds"
}

# Bug it catches: the proof run had no time limit for one hung test, so a new test that waits for what the unfixed
# code never writes held its card until stopped by hand. Here it hangs on main's code; its file's `# timeout: 1` line
# stops the file there, far before the run's own limit (testTimeout 15 s, the limit a file with no such line has, as in
# t_bughungdefault): the result names a.test.sh as timed out at 1 s, not 15 s, and it counts as failing without the
# fix (the check holds).
t_bughung() {
  TUNE='.tunables.testTimeout = 15' bugtest $'# timeout: 1\n'"$(wait_fn)"$'\nwait_poll grep -qx two a.txt' # the new test's own wait, which goes on past its limit on main's code
  hungsaid 1 'it was stopped there' 124 # 124: a file past its own limit ends the run as timed out (filecmd())
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
# 2 s here) with nothing naming it, so the run gave no failing file and did not count as proof; the card went back to
# build. The file is named as stopped by the run's testTimeout limit and counts as failing without the fix.
t_bughungdefault() {
  TUNE='.tunables.testTimeout = 2' bugtest "$(wait_fn)"$'\nwait_poll grep -qx two a.txt' # the new test's own wait, which goes on past its limit on main's code
  grep -qE "^conveyor: a\.test\.sh timed out: the run's time limit, 2 s \(testTimeout\), stopped the run after the file ran [0-2] s$" "$FXWT.unfixed" \
    && grep -q "^The run failed there (exit 124): at least one fails without the fix" "$FXWT.unfixed" \
    && grep -qE "^a\.test\.sh timed out: the run's time limit, 2 s, stopped it after it ran [0-2] s\. A test that hangs without the fix counts as failing without it\.$" "$FXWT.unfixed" \
    || fail "the proof run was not stopped at the run's limit, naming the hung file, and counted as failing: $(head -40 "$FXWT.unfixed" 2>&1)"
  [ "$RC" = 0 ] || fail "a new test that hangs without the fix did not prove it (exit $RC): $BW"
}

# Bug it catches (R332): with two files in the bug-card check's run, the run's clock (testclock()) wrote the run's whole
# limit as the open file's seconds, so the proof said the second file 'ran past its time limit, 40 s' though it ran only
# what the first file left; and, timed from the first look that saw it begun, a file that began just after one look
# and ran to the limit at the next was said to have run 0 s. The clock's looks are 10 s apart on a stand-in clock (its
# sleep sets SECONDS, so no real time passes); the limit is 40 s. a.test.sh ends and b.test.sh begins between the looks at
# 30 s and 40 s, and b.test.sh hangs: .late holds b.test.sh's 10 s (from the look at 30 s, the last that did not see it)
# and the limit apart, and the proof lines say the run's limit stopped it.
t_bugrunlate() {
  # shellcheck disable=SC2034 # FXWT is read by fx_in, a fix card's worktree; this case has none
  local FXWT=$T/$CASE/none w=$T/$CASE/w p
  setup '[]'
  # A stand-in log, written as a run of a.test.sh then b.test.sh writes it, and a stand-in for timeout's process: the clock
  # is under test, not a real run.
  mkdir -p "$w.testlog" && printf '== a.test.sh\n' > "$w.testlog/files" || fail "the fixture could not be made"
  sleep 60 & p=$! # sleep: stands for the run that the clock ends with ALRM
  # shellcheck disable=SC2016 # expanded by fx_in's eval
  fx_in 'k=0 lg=$w.testlog/files; sleep() { k=$((k + 1)); SECONDS=$((k * 10)); [ "$k" != 4 ] || printf -- "-- ok a.test.sh\n== b.test.sh\n" >> "$lg"; }
    ( SECONDS=0; TEST_LATE=1 testclock "$p" "$w.turnwait" 40 ); unset -f sleep; cat "$w.late"; latesaid "$w"; latecount "$w"'
  kill "$p" 2>/dev/null; wait "$p" 2>/dev/null
  local n; n=$(cut -f1 < <(head -n 1 "$T/$CASE/run.out"))
  [ "$(head -n 1 "$T/$CASE/run.out" | cut -f2-)" = $'b.test.sh\t40' ] && [ "$n" -ge 9 ] && [ "$n" -le 11 ] \
    && sed -n 2p "$T/$CASE/run.out" | grep -qxF "conveyor: b.test.sh timed out: the run's time limit, 40 s (testTimeout), stopped the run after the file ran $n s" \
    && sed -n 3p "$T/$CASE/run.out" | grep -qxF "b.test.sh timed out: the run's time limit, 40 s, stopped it after it ran $n s. A test that hangs without the fix counts as failing without it." \
    || fail "testclock with a 40 s limit and looks 10 s apart, b.test.sh begun after the look at 30 s and left open, did not give b.test.sh about 10 s and say the run's limit stopped it: $(cat "$T/$CASE/run.out")"
}

# Bug it catches: filecmd() logs no `-- FAIL` for a file its own `# timeout:` limit stopped, only the output's line
# saying so, and the run's clock (testclock()) read the logs alone: that file stayed open, so when the run's limit
# came later the clock could name it in .late as stopped by the run's limit, in place of the file still running. Here
# b.test.sh is stopped by its own limit and a.test.sh then hangs to the run's limit (40 s, on the stand-in clock of
# t_bugrunlate): .late must name a.test.sh alone, with the run's limit. The stopped file is b.test.sh because the
# clock names the last open file its awk lists, and mawk lists b.test.sh after a.test.sh, so the old clock named it.
t_bugrunownlimit() {
  # shellcheck disable=SC2034 # FXWT is read by fx_in, a fix card's worktree; this case has none
  local FXWT=$T/$CASE/none w=$T/$CASE/w p
  setup '[]'
  # The logs and output filecmd() writes for that run, and a stand-in for timeout's process: the clock is under test.
  mkdir -p "$w.testlog" && printf '== b.test.sh\n== a.test.sh\n' > "$w.testlog/files" \
    && printf '== b.test.sh\nconveyor: b.test.sh timed out: it ran past its time limit, 5 s, and it was stopped there\n== a.test.sh\n' > "$w.test" \
    || fail "the fixture could not be made"
  sleep 60 & p=$! # sleep: stands for the run that the clock ends with ALRM
  # shellcheck disable=SC2016 # expanded by fx_in's eval
  fx_in 'k=0; sleep() { k=$((k + 1)); SECONDS=$((k * 10)); }
    ( SECONDS=0; TEST_LATE=1 testclock "$p" "$w.turnwait" 40 ); unset -f sleep; cut -f2- "$w.late"'
  kill "$p" 2>/dev/null; wait "$p" 2>/dev/null
  [ "$(cat "$T/$CASE/run.out")" = $'a.test.sh\t40' ] \
    || fail "testclock at its 40 s limit, given logs where b.test.sh was stopped by its own limit and a.test.sh was still running, did not name a.test.sh alone in .late: $(cat "$T/$CASE/run.out")"
}

# Bug it catches: of the files the logs leave open, testclock() named whichever awk's `for (f in o)` printed last,
# and then the one whose last `== ` line came last in the logs read in name order. test-changed.log, read after the
# runner's `files`, logs a file's `== ` line only once it ended or was told to end, so the proof said the run's limit
# stopped c.test.sh or b.test.sh, begun and left open before a.test.sh, though a.test.sh hung. The logs are stand-ins,
# with no end line of c.test.sh or b.test.sh; the clock under test reads them with a stand-in sleep that sets SECONDS.
t_bugrunlateowned() {
  # shellcheck disable=SC2034 # FXWT is read by fx_in, a fix card's worktree; this case has none
  local FXWT=$T/$CASE/none w=$T/$CASE/w p
  setup '[]'
  mkdir -p "$w.testlog" && printf '== c.test.sh\n== b.test.sh\n== a.test.sh\n' > "$w.testlog/files" \
    && printf '== c.test.sh\n== b.test.sh\n' > "$w.testlog/test-changed.log" || fail "the fixture could not be made"
  sleep 60 & p=$! # sleep: stands for the run that the clock ends with ALRM
  # shellcheck disable=SC2016 # expanded by fx_in's eval
  fx_in 'k=0; sleep() { k=$((k + 1)); SECONDS=$((k * 10)); }
    ( SECONDS=0; TEST_LATE=1 testclock "$p" "$w.turnwait" 20 ); unset -f sleep; cut -f2- "$w.late"'
  kill "$p" 2>/dev/null; wait "$p" 2>/dev/null
  [ "$(cat "$T/$CASE/run.out")" = $'a.test.sh\t20' ] \
    || fail "testclock with the log files '== c.test.sh, == b.test.sh, == a.test.sh' and test-changed.log '== c.test.sh, == b.test.sh' (c and b left open, a hung) did not name a.test.sh, the file begun last: $(cat "$T/$CASE/run.out")"
}

# Bug it catches: a file its own limit stopped got no end line from the runner (filecmd()), so it stayed open, and
# when the run's limit ended the run while the next file cleaned up after its runner had logged `-- ok` for it (as
# .conveyor/test-changed.sh does before its EXIT cleanup), the proof said the run's limit stopped the first file.
# The real runner runs a.test.sh (`# timeout: 1`, it hangs) then b.test.sh, which logs `== b.test.sh` and `-- ok
# b.test.sh` to test-changed.log as that runner does, then hangs; the clock's stand-in sleep waits until b.test.sh has
# logged them (a real run, so its point in time is polled for; wait_until calls sleep and reads SECONDS, which the
# stand-in replaces) and then sets SECONDS past the run's limit.
t_bugrunlateownlimit() {
  # shellcheck disable=SC2034 # FXWT is read by fx_in, a fix card's worktree; this case has none
  local FXWT=$T/$CASE/none d=$T/$CASE w=$T/$CASE/w
  setup '[]'
  mkdir -p "$w.testlog" && printf '%s\n' a.test.sh b.test.sh > "$d/list" || fail "the fixture could not be made"
  printf '%s\n' '# timeout: 1' 'sleep 30' > "$d/a.test.sh" # sleep: a.test.sh's hang, which its own limit stops
  # shellcheck disable=SC2016 # expanded by b.test.sh's run
  printf '%s\n' 'printf "== b.test.sh\n-- ok b.test.sh\n" >> "$CONVEYOR_TEST_LOG/test-changed.log"; : > logged' \
    'sleep 30' > "$d/b.test.sh" # sleep: b.test.sh's cleanup after its `-- ok` line, which the run's limit stops
  # shellcheck disable=SC2016 # expanded by fx_in's eval
  fx_in 'cd "$d" || exit 1
    CONVEYOR_LOAD_FACTOR=1 CONVEYOR_TEST_LOG=$w.testlog CONVEYOR_TEST_FILELIST=$d/list timeout 60 bash -c "$(filecmd bash files)" > "$d/out" 2>&1 & p=$!
    sleep() { local i=0; while [ ! -e logged ] && [ $((i += 1)) -le 600 ]; do command sleep 0.1; done; SECONDS=100; }
    ( SECONDS=0; TEST_LATE=1 testclock "$p" "$w.turnwait" 20 ); unset -f sleep; wait "$p"; echo "rc=$?"; cat "$w.late" 2>/dev/null'
  [ "$(cat "$T/$CASE/run.out")" = rc=124 ] && [ -e "$d/logged" ] \
    || fail "with a.test.sh stopped by its own 1 s limit and the run's limit hit after b.test.sh logged '-- ok b.test.sh', the run did not exit 124, or testclock named a file as stopped by the run's limit: $(cat "$T/$CASE/run.out" "$d/out" "$w.testlog"/* 2>&1)"
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

# Bug it catches: at a load factor over 1, a file stopped at its scaled `# timeout:` limit gives a timeout line that
# ends with its own seconds and the factor (filecmd()); bugrun() read only a line with no such end, so it kept no
# record of the timeout and latecount() did not say the hung test counts as failing. bugrun() is called on a run
# whose output has that line (filecmd()'s text at `# timeout: 1` and factor 2).
t_bugscaledlate() {
  local w=$T/$CASE/wt got; mkdir -p "$w"
  local line="conveyor: a.test.sh timed out: it ran past its time limit, 2 s, and it was stopped there; the limit is its # timeout: line's 1 s times the load factor 2"
  got=$( eval "$(sed -n '/^bugrun() {/,/^}/p; /^latecount() {/,/^}/p' "$SRC/lib/testlist.sh")"
    tests() { printf '%s\n' "$line" > "$1.test"; return 124; }; bugrun "$w" a.test.sh; latecount "$w" )
  [ "$got" = "a.test.sh timed out: it ran past its time limit, 2 s, and was stopped. A test that hangs without the fix counts as failing without it." ] \
    || fail "bugrun() given the output line '$line' kept no timeout for latecount(): '$got'"
}

# Bug it catches: a bug card whose change is a test file alone (a test fixed for a red main, which passes on main's
# code too) is blocked, as with no fix to take out its test passes "without the fix". It is not run on main, the check
# holds, and the result says the change is test-only.
t_bugtestonly() {
  FIX=: bugtest 'grep -qx one a.txt'
  [ "$RC" = 0 ] && [ ! -e "$STUB/mainran" ] || fail "a test-only change was run on main or failed the check (exit $RC): $BW $(cat "$STUB/mainran" 2>&1)"
  grep -q '^The change is test-only: ' "$FXWT.unfixed" || fail "the result does not say the change is test-only: $(cat "$FXWT.unfixed" 2>&1)"
  # #1819 D1: the card's record says how the check was handled, and why.
  [ "$(st 'select(.step == "bugproof") | [.result, .reason] | join(": ")')" = "skipped: the change is test-only: every file it changes is a test file, so it has no fix to take out" ] \
    || fail "the record of a test-only change of a.test.sh has no bugproof line, result skipped, with the reason: $(st 'select(.step == "bugproof")')"
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
  # R142: the case checked only $STUB/mainran, so a check that made and left the mainrun worktree passed.
  [ ! -e "$T/$CASE/cards/mainrun" ] || fail "the comments-only check left a run's folder: $(ls "$T/$CASE/cards/mainrun")"
}

# #872 D1. Bug it catches: a bug card whose change only fixes a comment in a product file, with no test file (no test
# can fail before a comment fix and pass after it), is blocked as having no test. The check holds unrun, and its result
# says the change is comments only.
t_bugcommentsnotest() {
  FIX=$COMMENTFIX bugtest '' a.js "$COMMENTMAIN"
  [ "$RC" = 0 ] && [ ! -e "$STUB/mainran" ] || fail "a comment fix with no test file was run on main or failed the check (exit $RC): $BW $(cat "$STUB/mainran" 2>&1)"
  grep -q '^The change is comments only in its product files: ' "$FXWT.unfixed" \
    || fail "the result does not say the change is comments only: $(cat "$FXWT.unfixed" 2>&1)"
}

# D2. Bug it catches: a product change with one real code line beside its comment fix is let skip the check as
# comments only. Its test runs on main, passes there, and the check fails with "the new tests pass without the fix".
t_bugcommentcode() {
  FIX="$COMMENTFIX; echo 'export const y = 2;' >> a.js" bugtest "$COMMENTTEST" a.js "$COMMENTMAIN"
  [ "$RC" = 1 ] && [ "$BW" = "the new tests pass without the fix, so they do not prove it" ] \
    || fail "a comment fix with a code line was not failed as unproved (exit $RC): $BW"
  grep -q '/cards/mainrun/' "$STUB/mainran" || fail "its test was not run on main: $(cat "$STUB/mainran" 2>&1)"
}

# Bug it catches: bugproof.sh commentsonly() reads each changed line alone, so a change that puts code between a /* line and a */
# line (the code no longer runs), or edits a # line in a shell heredoc (text the program prints), is let skip the
# check; and so are a/**/b in js read as ab, and two .css and .html changes that look like comment fixes but change
# the page: 16/**/px (two CSS tokens, the rule dropped) read as 16px, and a new <!-- --> in an empty <nav> (a node:
# the Board sees a first child and draws no tabs). Each change here is staged beside a test file (but notest, staged
# alone) in a fresh repo and given to bugproof.sh commentsonly().
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
  # The engine's functions bugproof.sh commentsonly() calls, read once for every try.
  local fns; fns=$(sed -n '/^testpaths() {/,/^}/p' "$SRC/lib/issues.sh"; sed -n '/^uncomment() {/,/^}/p; /^commentsonly() {/,/^}/p' "$SRC/lib/bugproof.sh")
  # <name> <file> <sed script> [notest]: the file changed so and, unless notest, a.test.js changed, staged; notes
  # "<name>=<0 when comments only>".
  try() {
    sed -i "$3" "$r/$2" && { [ "${4-}" = notest ] || echo 'ok(1);' >> "$r/a.test.js"; } && git -C "$r" add -A || fail "staging $1"
    # shellcheck disable=SC2034 # TESTRX and TESTRUNNERS are read by testpaths(), loaded below
    got+=" $1=$( . "$SRC/lib/portable.sh"; TESTRX='\.test\.' TESTRUNNERS=''
      eval "$fns"; commentsonly "$r"; echo $?)"
    git -C "$r" reset -q --hard
  }
  try js app.js 's|x is two|x is one|'
  # #872: the same comment fix with no test file changed is comments only too (0): no test can fail without it.
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
  [ "$got" = ' js=0 notest=0 wrap=1 template=1 jsblank=0 jstoken=1 csstoken=1 htmlnode=1 heredoc=1 blocklsep=1 blockcr=1 linepsep=1' ] \
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
  # R142: the case checked only $STUB/mainran, so a check that made and left the mainrun worktree passed.
  [ ! -e "$T/$CASE/cards/mainrun" ] || fail "the no-test check left a run's folder: $(ls "$T/$CASE/cards/mainrun")"
  [ -z "$(st 'select(.step == "bugproof")' 2>/dev/null)" ] || fail "a code change with no test was let skip the check: $(st 'select(.step == "bugproof")')"
}

# #137. Bug it catches: a project whose tests are src/test-<name>.mjs, set in its pack's tests.patterns, had its test
# file taken for no test file, never run on main, and the card blocked as "the new tests pass without the fix". The
# file is found, runs alone on main's code without the fix and fails there, and the check holds.
# #1819. Bug it catches: the fix a.txt (a page) taken as one no test reads, as its linked test a.test.sh is outside
# the patterns, so the check was skipped; src/test-a.mjs names a.txt, so a.txt can be the fix and the check runs.
t_bugpatterns() {
  TF=src/test-a.mjs TUNE='.tests.patterns = ["src/test-*.mjs"]' bugtest 'grep -qx two a.txt'
  [ "$(sed 1d "$STUB/mainran" | tr '\n' ' ')" = 'src/test-a.mjs ' ] && [[ $(head -1 "$STUB/mainran") == */cards/mainrun/* ]] \
    || fail "the run on main was not of the card's src/test-a.mjs alone: $(cat "$STUB/mainran" 2>&1)"
  [ "$RC" = 0 ] && grep -q '^The run failed there (exit 1)' "$FXWT.unfixed" \
    || fail "the test that fails on main did not prove the fix (exit $RC): $BW $(cat "$FXWT.unfixed" 2>&1)"
}

# #137. Bug it catches: a pack whose test command cannot run one file alone has no way to run a change's test files.
# With test.fileCommand set, the check runs it once for each test file, given the file, in place of test.command:
# the file fails on main without the fix, and the check holds. Bug (#1435): what the run on main had staged was not
# checked, so a proof run with the fix a.txt staged beside a.test.sh passed too; the command logs it.
t_bugfilecommand() {
  TUNE='.test.fileCommand = "case $PWD in */mainrun/*) echo \"$CONVEYOR_TEST_FILE\" >> \"$STUB/fileran\"; git diff --cached --name-only >> \"$STUB/filestaged\" ;; esac; bash"' bugtest 'grep -qx two a.txt'
  [ "$(cat "$STUB/fileran" 2>&1)" = a.test.sh ] && [ ! -e "$STUB/mainran" ] \
    || fail "the check did not run the test file alone with test.fileCommand: $(cat "$STUB/fileran" "$STUB/mainran" 2>&1)"
  [ "$(cat "$STUB/filestaged" 2>&1)" = a.test.sh ] || fail "the run on main had more than the test file staged: $(cat "$STUB/filestaged" 2>&1)"
  [ "$RC" = 0 ] && grep -q '^The run failed there (exit 1)' "$FXWT.unfixed" \
    || fail "the test run through test.fileCommand did not prove the fix (exit $RC): $BW $(cat "$FXWT.unfixed" 2>&1)"
}

# #711. Bug it catches: the guides said every card with a test file and no test.fileCommand stops at its test step,
# but a bug card with a fix cannot run its bug-card check (bugproof.sh bugproof() exit 2; t_wideoffnolist checks that stop), and
# card() blocks it at Build, while a test-only or comments-only bug card skips the check and stops at its test step.
# #713. Bug it catches: they said so of comments in any file, but bugproof.sh commentsonly() takes only JavaScript and TypeScript
# files (t_bugcommentsyntax: a # line in a .sh file is a fix), so a bug card that changes a shell comment stops at Build.
# #872. Bug it catches: they said a js comment fix with no test file is a fix that stops at Build, but bugproof.sh commentsonly()
# now takes it with or without a test file (t_bugcommentsyntax notest).
# #1819. Bug it catches: they counted a change of test files and pages that no test reads as a fix that stops at
# Build, but bugproof.sh pagesonly() lets it skip the check (t_bugtestmd).
# The pages and the schema have no behaviour to run, so their text is read.
t_bugnofilecmd() {
  local p
  for p in conveyor/README.md docs/configuration.md; do
    tr '\n' ' ' < "$SRC/../$p" | tr -s ' ' | grep -qiE 'a bug card with a test file and a fix stops earlier, at (its )?Build' \
      || fail "$p does not say a bug card with a fix and no test.fileCommand stops at Build"
    tr '\n' ' ' < "$SRC/../$p" | tr -s ' ' | grep -qiE 'a bug card whose change is only test files, or only comments in other `\.js`, `\.mjs`, `\.cjs`, `\.ts`, `\.mts` or `\.cts` files with or without test files, has no check to run, and with a test file it stops at its test step\. A comment change in any other file, such as a `\.sh` or `\.py` file, is a fix, and that card stops at Build' \
      || fail "$p does not say a JavaScript or TypeScript comments-only bug card, with or without a test file, has no check to run"
    tr '\n' ' ' < "$SRC/../$p" | tr -s ' ' | grep -qF 'A bug card whose change is test files and pages (`.md`, `.txt`, `.rst`) that no test reads has no check to run either, and stops at its test step.' \
      || fail "$p does not say a bug card of test files and pages that no test reads has no check to run"
  done
  jq -r .properties.test.properties.fileCommand.description "$SRC/schema/pack.schema.json" \
    | grep -qF 'a bug card with a fix (any change but test files alone, test files with pages (.md, .txt, .rst) that no test reads, or comments in .js, .mjs, .cjs, .ts, .mts and .cts files with or without test files; a comment change in a .sh or .py file is a fix) at Build' \
    || fail "the pack schema's test.fileCommand does not say a js comment change with or without a test file has no check, and one in a .sh or .py file is a fix"
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
  # Bug (#1436): the guide said the check runs your test command on main's code with the inline tests; the run above ran
  # the product file alone, through the file's runner, as it runs a test file.
  pagesays_bugproof docs/configuration.md 'It runs each such product file alone on main'"'"'s code' "src/lib.rs was run alone on main's code: $(cat "$STUB/mainran" 2>&1 | head -n 1)"
  ! tr '\n' ' ' < "$SRC/../docs/configuration.md" | tr -s ' ' | grep -qF 'It runs your test command on main' || fail "docs/configuration.md still says the inline test check runs your test command"
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

# Bug it catches: a doctest written on the line of the docstring's opening quotes (""">>> double(2)) matched no line of
# the python kind's `has` (^[[:space:]]*>>>), so the block was no test and the card was blocked as having no new test.
t_buginlinedoctestquotes() {
  inlinewt lib.py $'def double(x):\n    return x * 3' $'def double(x):\n    """>>> double(2)\n    4\n    """\n    return x * 2' \
    'PYTHONDONTWRITEBYTECODE=1 python3 -m doctest lib.py'
  [ "$RC" = 0 ] && grep -qxF -- '- lib.py (its inline tests, with the rest of its change taken out)' "$FXWT.unfixed" && grep -q '^The run failed there (exit 1)' "$FXWT.unfixed" \
    || fail "a doctest that starts on the line of the opening quotes was not found as an inline test (exit $RC): $BW $(cat "$FXWT.unfixed" 2>&1)"
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
  # R142: the case checked only $STUB/mainran, so a check that made and left the mainrun worktree passed.
  [ ! -e "$T/$CASE/cards/mainrun" ] || fail "the shared-lines check left a run's folder: $(ls "$T/$CASE/cards/mainrun")"
}

# R337. Bug it catches: a } inside a Rust string (or a character literal) closed the #[test] block mid-line, so the
# rest of that line was code beside a test, the line was marked shared (S) and inlinesplit() refused (exit 3), though
# the fix is in another fn. inlinesplit() is called on its own (bugproof.sh holds only definitions) on a repo whose
# main has f() returning 1, its change the fix (2) and a test whose lines hold "}", '}' and a // comment with a quote.
t_buginlinestring() {
  local w=$T/$CASE/r out rc
  mkdir -p "$w/src" && git -C "$w" init -q && printf 'pub fn f() -> i32 {\n    1\n}\n' > "$w/src/lib.rs" \
    && git -C "$w" add . && git -C "$w" -c user.name=t -c user.email=t@example.com commit -qm main || fail "the repo"
  printf '%s\n' 'pub fn f() -> i32 {' '    2' '}' '#[test]' 'fn two() { assert_eq!(f(), 2); let _ = ("}", '"'}'"'); // the "a } quote' \
    '    assert_ne!(f().to_string(), "}"); }' > "$w/src/lib.rs" && git -C "$w" add src/lib.rs || fail "the change"
  out=$(. "$SRC/lib/bugproof.sh" && inlinesplit "$w" src/lib.rs '{"start": "#\\[(cfg\\(test\\)|([A-Za-z_]+::)?test)\\]", "end": "braces"}'); rc=$?
  [ "$rc" = 0 ] && [ "$out" = "$(printf '%s\n' 'pub fn f() -> i32 {' '    1' '}' '#[test]' 'fn two() { assert_eq!(f(), 2); let _ = ("}", '"'}'"'); // the "a } quote' \
    '    assert_ne!(f().to_string(), "}"); }')" ] \
    || fail "inlinesplit on src/lib.rs, a #[test] fn holding \"}\" and '}' and the fix in f(), exited $rc (not 0) or did not take the fix out alone: $out"
}

# R337 (E5). Bug it catches: a raw string was read as a plain one, so in r"\" the backslash escaped the closing quote,
# the string ran on to the end of the file, and f() below the #[test] fn, which the change fixes, was marked test code:
# inlinesplit() kept the fix in the file it runs on main. r#"}"# (a } and a quote inside) must not close the fn either.
t_buginlineraw() {
  local w=$T/$CASE/r out rc
  mkdir -p "$w/src" && git -C "$w" init -q && printf '%s\n' '#[test]' 'fn two() {' '    let _ = r"\";' '}' 'pub fn f() -> i32 {' '    1' '}' > "$w/src/lib.rs" \
    && git -C "$w" add . && git -C "$w" -c user.name=t -c user.email=t@example.com commit -qm main || fail "the repo"
  printf '%s\n' '#[test]' 'fn two() {' '    let _ = r"\"; let _ = r#"a "} b"#;' '    assert_eq!(f(), 2);' '}' 'pub fn f() -> i32 {' '    2' '}' > "$w/src/lib.rs" \
    && git -C "$w" add src/lib.rs || fail "the change"
  out=$(. "$SRC/lib/bugproof.sh" && inlinesplit "$w" src/lib.rs '{"start": "#\\[(cfg\\(test\\)|([A-Za-z_]+::)?test)\\]", "end": "braces"}'); rc=$?
  [ "$rc" = 0 ] && [ "$out" = "$(printf '%s\n' '#[test]' 'fn two() {' '    let _ = r"\"; let _ = r#"a "} b"#;' '    assert_eq!(f(), 2);' '}' 'pub fn f() -> i32 {' '    1' '}')" ] \
    || fail "inlinesplit on src/lib.rs, a #[test] fn holding r\"\\\" and r#\"a \"} b\"# above the fix in f(), exited $rc (not 0) or did not take the fix out: $out"
}

# R337 (E9). Bug it catches: a quote in a /* */ comment opened a string that ran to the end of the file, so f() below
# the #[test] fn, which the change fixes, was marked test code and inlinesplit() kept the fix in the file it runs on
# main. A nested comment (/* a /* b */ "} */) must not end at its first */ either.
t_buginlinecomment() {
  local w=$T/$CASE/r out rc
  mkdir -p "$w/src" && git -C "$w" init -q && printf '%s\n' '#[test]' 'fn two() {' '    /* The delimiter is " */' '    assert_eq!(f(), 1);' '}' 'pub fn f() -> i32 {' '    1' '}' > "$w/src/lib.rs" \
    && git -C "$w" add . && git -C "$w" -c user.name=t -c user.email=t@example.com commit -qm main || fail "the repo"
  printf '%s\n' '#[test]' 'fn two() {' '    /* The delimiter is " */ /* a /* b */ "} */' '    assert_eq!(f(), 2);' '}' 'pub fn f() -> i32 {' '    2' '}' > "$w/src/lib.rs" \
    && git -C "$w" add src/lib.rs || fail "the change"
  out=$(. "$SRC/lib/bugproof.sh" && inlinesplit "$w" src/lib.rs '{"start": "#\\[(cfg\\(test\\)|([A-Za-z_]+::)?test)\\]", "end": "braces"}'); rc=$?
  [ "$rc" = 0 ] && [ "$out" = "$(printf '%s\n' '#[test]' 'fn two() {' '    /* The delimiter is " */ /* a /* b */ "} */' '    assert_eq!(f(), 2);' '}' 'pub fn f() -> i32 {' '    1' '}')" ] \
    || fail "inlinesplit on src/lib.rs, a #[test] fn holding /* The delimiter is \" */ and /* a /* b */ \"} */ above the fix in f(), exited $rc (not 0) or did not take the fix out: $out"
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

# #831 D1. A whole card, for what only it shows: card() hands the reason bugproof.sh bugproof() set (BUGWHY) to the build it sends
# back, that build's line and the review. Bug it catches: a comment card whose build omits a test is sent back with the
# default reason ("the new tests pass without the fix"), or the test its issue's Done-when names is not the proof that
# reaches the review. Main holds src/s.sh with src/s.test.sh (`true`, which s.sh selects by name), and src/w.sh, which
# no test selects, with src/k.test.sh, which its issue names and which fails on w.sh's old comment. The first build
# rewords s.sh's comment and adds no test; the second puts the fix in w.sh and adds no test either, so only the issue
# selects src/k.test.sh (with no test named there, the check is skipped: t_bugcommentnamed). The card lands.
t_bugcommentloop() {
  setup "[$(issue 7 2026-01-01 bug | jq -c '.body = "body\n\n## Done when\nsrc/k.test.sh fails on main and passes with the fix."')]"; nopush
  mkdir "$R/src"; printf '#!/usr/bin/env bash\n# an old word\n' | tee "$R/src/s.sh" > "$R/src/w.sh"; echo true > "$R/src/s.test.sh"; echo '! grep -q old src/w.sh' > "$R/src/k.test.sh"
  git -C "$R" add src && git -C "$R" commit -qm 'comments and their tests' && git -C "$R" push -q origin main || fail "main's files"
  sed -i 's|^cat > /dev/null; echo x|cat > "$STUB/asked"; echo x|' "$STUB/codex"; echo "$GO" > "$STUB/review.1"
  echo "if [ \"\$(wc -l < \"\$STUB/sessions\")\" = 1 ]; then printf '#!/usr/bin/env bash\n# a new word\n' > src/s.sh; else printf '#!/usr/bin/env bash\n# an old word\n' > src/s.sh; printf '#!/usr/bin/env bash\n# a new word\n' > src/w.sh; fi" > "$STUB/build"
  echo 'bash src/k.test.sh' > "$STUB/mainrun-cmd"
  # loop: the proof must reach the review's prompt and the card land, and only a whole card goes from its build to its review
  loop run >/dev/null || fail "run exited non-zero"
  local why; why="no test file found in the change (patterns: $(jq -r '.properties.tests.properties.patterns.default | join(", ")' "$SRC/schema/pack.schema.json")); set tests.patterns in .conveyor/project.json"
  [ "$(st 'select(.step == "build") | .reason // ""' | tr '\n' '|')" = "|$why|" ] && grep -qxF "# Back to the build: $why" "$STUB/brief" \
    || fail "the build sent back was not given the missing-test reason: $(st 'select(.step == "build")'; tail -n 5 "$STUB/brief")"
  grep -qx '# The bug-card check' "$STUB/asked" && grep -q "the test files its issue's Done-when names were run alone on main's code" "$STUB/asked" \
    && grep -qx -- '- src/k.test.sh' "$STUB/asked" && grep -q '^They pass with the fix, and the run without it failed (exit 1)' "$STUB/asked" \
    || fail "the review was not shown that src/k.test.sh, named in the issue, fails on main: $(cat "$STUB/asked" 2>&1)"
  [ -n "$(st 'select(.step == "landed") | .sha')" ] || fail "the card did not land: $(st 'select(.step | IN("blocked", "landed"))')"
}

# Bug it catches: a bug card whose build changed nothing (an ALREADY-DONE, or a session that did nothing) is sent to
# build again to add a test, in place of going its own way. On fixture state, as card() takes it: the check on a
# worktree with no change holds (bugstep(): nothing, not build); the staged change is no change (card.sh emptychange()
# exit 0), so the card ends as a card with no change (nochange(): blocked).
t_bugnochange() {
  setup '[]'
  ISSUE=$(issue 7 2026-01-01 bug) bugwt ':' a.test.sh true
  [ "$RC" = 0 ] && [ -z "$(eng "bugstep $RC")" ] || fail "a bug card with no change was sent back to build: the check's exit $RC, bugstep '$(eng "bugstep $RC")': $BW"
  fx_in 'emptychange c7 7 "$FXWT" ""; echo "empty $?"; nochange c7 7 "$FXWT" brief'
  [ "$(head -n 1 "$T/$CASE/run.out")" = "empty 0" ] && st 'select(.step == "blocked") | .reason' | grep -q 'the session made no change' \
    || fail "a bug card with no change did not end as one: $(cat "$T/$CASE/run.out"): $(st 'select(.step | IN("build", "blocked"))')"
}

# D3. Bug it catches: a card whose issue is not a bug is held to the check. Its test passes on main, and it still has
# one build session, no run on main, and goes on to a review that is not shown the check (card.sh reviewseen() shows
# it from <worktree>.unfixed, which stays empty).
t_notbug() {
  bugcard 'grep -qx one a.txt' area:billing
  [ "$(wc -l < "$STUB/sessions")" = 1 ] && [ ! -e "$STUB/mainran" ] && [ ! -s "$FXWT.unfixed" ] && [ "$(tail -n 1 "$T/$CASE/run.out")" = "go " ] \
    || fail "a card that is not a bug was checked, or did not go on to its review: $(tail -n 3 "$T/$CASE/run.out"): $(cat "$STUB/mainran" "$FXWT.unfixed" 2>&1)"
}
