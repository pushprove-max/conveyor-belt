#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the Test step runs the cases that did not pass once more before any fix session, and what passed is
# not run again (tests()).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# A test command of three files and four cases ($STUB/cases) that does what CONVEYOR_TEST_RERUN asks: a file that
# passed is not run, of a file it names failed cases of, only those run, and else a case it names as ok is not run;
# a file a `changed` line selects runs whole: the file itself (a test file the session changed), or the one $STUB/map
# names for the changed file (`<file> <test file>`; `<file> all`: every file, as an "all" area); `<file> <test
# file>:<case>` adds that case alone, as the engine's runner runs the cases of an area; a `main` line (a file main
# changed) selects as a `changed` line does, every file being in its selection. Its log says why each file runs when
# it was given a list (TESTRUN why). $STUB/pre, when there is one, is sourced as each run begins. A file listed as passed runs
# only when the list also names failed cases of it, or a changed file selects a case of it. Its log says how many
# cases ran and, when it was given a list, how many passes it kept, not run (TESTRUN cases= and kept=), and names the
# cases of a file it runs only some of (TESTRUN case, as .conveyor/test-changed.sh does for the engine's runner). $STUB/plan says which case fails (`<run>
# fail <case>`; `<run> bare <case>`: its file fails naming no case), hangs (`<run> hang <case>`, cut at once as the clock cuts it) or hangs until the run's own clock cuts
# it (`<run> stall <case>`) on which run; $STUB/ran is each case run, as `<run> <case>`; and
# $STUB/rerun.<run> is what the loop gave that run to go by. A run of a card's failing cases on main (mainred.sh verdicts(), in
# a worktree under cards/mainrun/) is this command too ($STUB/mainrun-cmd), numbered by no count: its run is `main`
# (`main fail <case>`, `main <case>`, $STUB/rerun.main); there, as on a clean tree, only the files a `fail` line names run.
rerunsetup() {
  setup "$(jq -cs . <(issue 7 2026-01-01))"
  for i in 1 2 3; do echo "$GO" > "$STUB/review.$i"; done
  printf '%s\n' 'a.test one two' 'b.test flaky' 'c.test three' > "$STUB/cases"
  printf '%s\n' 'a.txt a.test' 'core.txt all' 'x.txt a.test:one' > "$STUB/map"
  printf '%s\n' "$@" > "$STUB/plan"
  cat > "$STUB/test-cmd" <<'EOF'
L=$CONVEYOR_TEST_LOG/run.log; RR=${CONVEYOR_TEST_RERUN:-/dev/null}
p=; [ ! -e "$STUB/perfile" ] || p=1
case $PWD in */mainrun/*) n=main ;; *) n=$(cat "$STUB/n" 2>/dev/null || echo 0); [ -n "$p" ] && [ "${CONVEYOR_TEST_N:-1}" != 1 ] || { n=$((n + 1)); echo "$n" > "$STUB/n"; } ;; esac
[ "$RR" = /dev/null ] || cp "$RR" "$STUB/rerun.$n"
[ ! -f "$STUB/pre" ] || . "$STUB/pre"
rc=0; k=0; fs="a.test b.test c.test"; of=4; [ -z "$p" ] || { fs=$CONVEYOR_TEST_FILE; of=$(sed -n "s/^$fs //p" "$STUB/cases" | wc -w); }
for f in $fs; do
  fr=; fc=; dn=; w=
  while read -r kind ch; do
    m=$(awk -v c="$ch" '$1 == c {print $2}' "$STUB/map"); r="main changed $ch"; [ "$kind" = main ] || r="the card changed $ch"
    if [ "$ch" = "$f" ] || [ "$m" = "$f" ] || [ "$m" = all ]; then fr=1; w="$w$r|"; elif [ "${m%%:*}" = "$f" ]; then fc="$fc ${m#*:}"; w="$w$r|"; fi
  done < <(awk -F'\t' '$1 == "changed" || $1 == "main" {print $1, $2}' "$RR")
  if [ -n "$fr" ]; then cs=$(sed -n "s/^$f //p" "$STUB/cases")
  else
    cs=$(awk -F'\t' -v f="$f" '$1 == "fail" && $2 == f {print $3}' "$RR"); dn=1
    # On main's clean tree no change selects a file: only one a `fail` line names runs (a line naming no case: whole).
    [ "$n" != main ] || awk -F'\t' -v f="$f" '$1 == "fail" && $2 == f {e = 1} END {exit !e}' "$RR" || continue
    if [ -z "$cs" ] && grep -qxF "pass	$f" "$RR"; then [ -n "$fc" ] || continue; dn=
    elif [ -z "$cs" ]; then cs=$(sed -n "s/^$f //p" "$STUB/cases" | tr ' ' '\n' | grep -vxFf <(awk -F'\t' -v f="$f" '$1 == "ok" && $2 == f {print $3}' "$RR"))
    fi
    [ -z "$fc" ] || cs=$(sed -n "s/^$f //p" "$STUB/cases" | tr ' ' '\n' | grep -xFf <(printf '%s\n' $cs $fc))
  fi
  [ "$(echo $cs)" = "$(sed -n "s/^$f //p" "$STUB/cases")" ] || for c in $cs; do printf 'TESTRUN case\t%s\t%s\n' "$f" "$c" >> "$L"; done
  echo "== $f"; echo "== $f" >> "$L"; r=ok
  [ "$RR" = /dev/null ] || { [ -z "$dn" ] || w="${w}did not pass|"; tr '|' '\n' <<<"$w" | awk -v f="$f" 'length { printf "TESTRUN why\t%s\t%s\n", f, $0 }' >> "$L"; }
  for c in $cs; do
    k=$((k + 1)); echo "$n $c" >> "$STUB/ran"
    # A case that hangs, cut as the test run's clock cuts it once testTimeout has run out: ALRM to `timeout` (the
    # command's parent, testonce()), which ends the run with exit 124. Sent here at once, so no case sits out the
    # clock's seconds; that the clock itself fires at testTimeout is t_rerunkilled's, whose case stalls.
    ! grep -qxF "$n hang $c" "$STUB/plan" || { kill -ALRM "$PPID"; sleep 30; } # sleep: until timeout ends the run
    ! grep -qxF "$n stall $c" "$STUB/plan" || sleep 30 # sleep: a case that hangs, ended only by the run's clock (testclock)
    if grep -qxF "$n fail $c" "$STUB/plan"; then echo "FAIL [$c]: wrong"; r=FAIL
    elif grep -qxF "$n bare $c" "$STUB/plan"; then echo "FAIL: wrong"; r=FAIL; else echo "ok $c"; fi
  done
  echo "-- $r $f" >> "$L"; [ $r = ok ] || rc=1
done
echo "TESTRUN cases=$k of=$of" >> "$L"; [ "$RR" = /dev/null ] || echo "TESTRUN kept=$((of - k))" >> "$L"
exit $rc
EOF
  echo '. "$STUB/test-cmd"' > "$STUB/mainrun-cmd"
}
# rerunsetup's main as a card runs it (#374: each test file alone, through test.fileCommand): a.test, b.test and c.test
# are files of main, test files by the pack's tests.patterns, each linked to a.txt (the build's file), and the stub
# runs only the file the run gives it (CONVEYOR_TEST_FILE), its cases' count of its own (of), a run being counted
# ($STUB/n) at its first file (CONVEYOR_TEST_N). Without it the stub runs the three files at each call: only for a
# case that calls engine functions itself (tests() in rerunstep, on the worktree rerunwt makes; mainred.sh verdicts() in
# mainlimit.test.sh's limitjudge; voidrun(), verdicts() and mainred() in voidrun.test.sh's t_voidcommand). A card
# run (loop run) needs it: given one file there, a stub that reports three is stopped by watch() as a run of files it
# was not given, whenever watch() looks before the stub ends, as it did under the load of a whole-suite run (issue
# 769: a rebuilt card's second run stopped, with no test line).
rerunfiles() {
  local f
  for f in a.test b.test c.test; do echo "$f" > "$R/$f"; done; git -C "$R" add a.test b.test c.test || fail "main's test files could not be staged"
  tune '.tests.patterns = ["*.test", "*.test.*"]'; linkset '{"a.txt": ["a.test", "b.test", "c.test"]}'; : > "$STUB/perfile"
}
ran() { sed -n "s/^$1 //p" "$STUB/ran" | tr '\n' ' ' | sed 's/ $//'; } # <run>: the cases it ran
# A card's test steps without the card: its worktree $T/$CASE/cards/c7 on main, its change staged, and the engine's
# own tests() (lib/testrun.sh), with the engine's libraries sourced as conveyor.sh sources them (as slots.test.sh's
# teststep does), run on it as card() runs it at each test step; a fix session is `rerunedit <edit>` between two
# steps. What tests() alone decides (what a run after a fix keeps, runs and is told) is proved so: a whole card run
# cost each case about 3 CPU s alone and twice that beside the file's other cases, a main run of its failing cases
# among it. (What a card adds around tests(): a pass on re-run on its test line and the Board, t_rerunpass; the main
# run and the fix session, t_rerunfail; the retry, t_rerunretry, in rerunkept.test.sh. A session that moved HEAD,
# t_rerunmoved, and the rebuild onto main, t_rerunrebuilt and t_rerunmergedoubt, are tests() on a worktree too.)
rerunedit() { (cd "$T/$CASE/cards/c7" && eval "$1") && git -C "$T/$CASE/cards/c7" add -A; } # <shell edit in the worktree>: the build's or a fix's edit, staged
rerunstep() { # exits as tests() returns; its test line's part of the run (testrec()) is in c7.testrec, and a pass leaves its part of the first run, as card() puts it (firstrun()), in c7.firstrun
  ( set -- run; HERE=$SRC; export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; local rc
    eval "$(sed -n '/^\. "\$HERE\/lib\/portable.sh"/,/^\. "\$HERE\/lib\/records.sh"/p' "$SRC/conveyor.sh"; grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")"
    names || exit 1; tests "$T/$CASE/cards/c7"; rc=$?; testrec "$T/$CASE/cards/c7" "$rc" 0 > "$T/$CASE/cards/c7.testrec"
    [ $rc = 0 ] || exit $rc; firstrun "$T/$CASE/cards/c7" pass > "$T/$CASE/cards/c7.firstrun" ) > /dev/null 2>&1
}
rerunwt() { # <the build's edit> <plan line>...: rerunsetup's main and stubs, and the card's worktree with its change staged
  local b=$1; shift; rerunsetup "$@"
  git -C "$R" worktree add -q --detach "$T/$CASE/cards/c7" || fail "the card's worktree could not be made"
  rerunedit "$b" || fail "the build's edit could not be staged"
}
tline() { st 'select(.step == "test") | tojson' | sed -n "$1p" | jq -r "$2"; } # <nth test line> <jq filter>

# The owner, from 186 test runs: every failed run of a day passed on the next run, and most fix sessions it started
# made no edit. A failing case runs once more, alone, before any fix session; when it passes there is none, and the
# card's test line says it passed on re-run and which case had failed, never a plain pass.
t_rerunpass() {
  rerunsetup '1 fail flaky'; rerunfiles
  # The run again's live record, once watch() has written it (#433).
  # shellcheck disable=SC2016 # expanded where the test command sources it
  echo '[ "$n" != 2 ] || { v=${CONVEYOR_TEST_LOG%.testlog}.live; i=0; until jq -e .before "$v" > /dev/null 2>&1 || [ $i -ge 100 ]; do sleep 0.1; i=$((i + 1)); done; cp "$v" "$STUB/live.2"; }' > "$STUB/pre" # sleep: the stub test command's own poll, run where wait.sh is not loaded
  loop run 1 > /dev/null || fail "run exited non-zero"
  # Bug it catches (#433): the run again restarted the live record, so the Board and /units lost the first run's time.
  jq -e '.before | type == "number"' "$STUB/live.2" > /dev/null || fail "the run again's live record has not the first run's seconds: $(cat "$STUB/live.2")"
  [ "$(ran 1)" = "one two flaky three" ] || fail "the first run did not run the whole selection: $(ran 1)"
  [ "$(ran 2)" = flaky ] || fail "the run again did not run the failed case alone: $(ran 2)"
  [ "$(ran 3)" = "" ] || fail "a third run ran: $(ran 3)"
  [ "$(sed 1,3d "$STUB/rerun.2" | tr '\t\n' ':|')" = "pass:a.test|pass:c.test|fail:b.test:flaky|" ] || fail "the run again was not told what passed and what failed: $(cat "$STUB/rerun.2")"
  [ "$(wc -l < "$STUB/sessions")" = 1 ] || fail "a session beside the build ran: $(cat "$STUB/sessions")"
  [ "$(st 'select(.step == "fix") | .step' | wc -l)" = 0 ] || fail "a fix session started"
  [ "$(st 'select(.step == "test") | .result' | tr '\n' ' ')" = "pass " ] || fail "not one test line that passed: $(st 'select(.step == "test") | .result')"
  [ "$(tline 1 .reason)" = "passed on re-run: b.test: flaky" ] || fail "the test line does not say it passed on re-run, naming the case: $(tline 1 .reason)"
  [ "$(tline 1 '.rerun | [.exit, (.failures.files | map("\(.file):\(.cases | map(.name) | join(","))"))] | tojson')" = '[1,["b.test:flaky"]]' ] \
    || fail "the test line does not keep the first run's exit and failing case: $(tline 1 .rerun)"
  # Bug it catches (#228): the run again overwrote the first run's output, so a flaky failure had none for the judge or
  # the Board's Fix failures preview.
  [[ "$(tline 1 '.rerun.tail')" == *"FAIL [flaky]: wrong"* ]] || fail "the test line does not keep the first run's output: $(tline 1 .rerun)"
  st 'select(.step == "landed") | .step' | grep -q landed || fail "the card did not land"
  loop check || fail "the record check refuses a test line with its first run"
  # The Board draws the card's Test step and its tests bar from these: each says it passed on re-run.
  [ "$(loop snapshot --fresh | jq -c '.landed[0].track | [.steps[3].rerun, [.records[] | select(.name == "tests passed") | .rerun]]')" = '[true,[true]]' ] \
    || fail "the card's track does not say its tests passed on re-run: $(loop snapshot --fresh | jq -c '.landed[0].track | [.steps, .records]')"
  # Bug: a later line that reused that pass (card(): reused, as after giving way) drew the Test step as a plain pass.
  jq -c 'if .step == "test" then ., (del(.rerun, .reason) + {reason: "", reused: true}) else . end' "$ST/cards.jsonl" > "$STUB/cards.new" \
    && mv "$STUB/cards.new" "$ST/cards.jsonl"
  [ "$(st 'select(.step == "test") | .reused // false' | tr '\n' ' ')" = "false true " ] || fail "the reused pass line was not added: $(st 'select(.step == "test")')"
  [ "$(loop snapshot --fresh | jq -c '.landed[0].track.steps[3].rerun')" = true ] \
    || fail "a pass reused after a pass on re-run erased it from the card's Test step: $(loop snapshot --fresh | jq -c '.landed[0].track.steps[3]')"
}

# A case that fails again on its run again goes to its fix session, as before. The fix edits only the file under test,
# a.txt (the map's a.test): the run after it is of the case that had failed and a.test's cases, and no other; c.test,
# which passed and which no changed file selects, is kept as passed (the owner, 2026-11-13: #325 had one failing case
# of its selection, and after its fix the whole selection would have run again).
t_rerunfail() {
  rerunsetup '1 fail flaky' '2 fail flaky'; rerunfiles
  local m1; m1=$(git -C "$R" rev-parse HEAD)
  loop run 1 > /dev/null || fail "run exited non-zero"
  [ "$(ran 2)" = flaky ] || fail "the run again did not run the failed case alone: $(ran 2)"
  # Issue 582: main did not move, so the card is not moved onto it before its fix (t_mainfixed: main moved): the fix
  # and the run after it are on the commit it was built on, told of no change of main's.
  [ "$(sed -n 's/^base\t//p' "$STUB/rerun.3")" = "$m1" ] && ! grep -q $'^main\t' "$STUB/rerun.3" \
    || fail "a card on a main that had not moved was moved before its fix: $(cat "$STUB/rerun.3" 2>&1)"
  [ "$(st 'select(.step == "test" or .step == "fix") | "\(.step) \(.result)"' | tr '\n' ,)" = "test fail,fix ok,test pass," ] \
    || fail "the failed run again did not start a fix session before the tests ran again: $(st 'select(.step == "test" or .step == "fix") | "\(.step) \(.result)"' | tr '\n' ,)"
  [ "$(wc -l < "$STUB/sessions")" = 2 ] || fail "not a build and one fix session: $(cat "$STUB/sessions")"
  [ "$(tline 1 '[.rerun.exit, (.rerun.failures.files | map(.file)), (.failures.files | map("\(.file):\(.cases | map(.name) | join(","))"))] | tojson')" = '[1,["b.test"],["b.test:flaky"]]' ] \
    || fail "the failed line does not keep both runs: $(tline 1 tojson)"
  # Before the fix, the case's file ran on main (mainred.sh verdicts()), alone and whole, and passed there: the card's to fix, and
  # no P0.
  [ "$(ran main)" = flaky ] && [ "$(sed -n 's/^fail\t//p' "$STUB/rerun.main" | tr '\t\n' ':|')" = "b.test|" ] \
    || fail "the failing case was not run alone on main: $(ran main): $(cat "$STUB/rerun.main" 2>&1)"
  [ "$(tline 1 '[.verdicts, (.mainRun | keys)] | tojson')" = '[[{"case":"b.test: flaky","verdict":"card"}],["exit","sec","sha"]]' ] \
    || fail "the failed line does not say the case passed on main: $(tline 1 tojson)"
  [ ! -s "$STUB/filed" ] || fail "a case that passed on main filed an issue: $(cat "$STUB/filed")"
  [ "$(ran 3)" = "one two flaky" ] || fail "the run after a fix of a.txt was not of the failed case and a.test's cases alone: $(ran 3)"
  [ "$(grep -E $'^(pass|fail|changed)\t' "$STUB/rerun.3" | tr '\t\n' ':|')" = "pass:a.test|pass:c.test|fail:b.test:flaky|changed:a.txt|" ] \
    || fail "the run after the fix was not told what passed, what failed and the file the fix changed: $(cat "$STUB/rerun.3" 2>&1)"
  # Its test line says how many cases ran (3) and how many passes were kept from the run before (c.test's three).
  [ "$(tline 2 '.selected | [.cases, .kept] | tojson')" = '[3,1]' ] || fail "the test line after the fix does not say what ran and what was kept: $(tline 2 .selected)"
  [ "$(tline 2 '.rerun // "none"')" = none ] || fail "a run that passed first time says it was run again: $(tline 2 tojson)"
  [ "$(loop snapshot --fresh | jq -c '.landed[0].track | [.steps[3].rerun, [.records[] | select(.name == "tests passed") | .rerun]]')" = '[null,[null]]' ] \
    || fail "a card whose last run passed first time is drawn as passed on re-run: $(loop snapshot --fresh | jq -c '.landed[0].track.steps')"
}

# A run killed part-way (its time ran out in b.test) runs again only what had not passed: the file it was in and the
# file it never began, not the file that passed. b.test's case stalls with no shortcut, so the loop's own clock
# (testclock) must cut the run at testTimeout (2 s): a clock that never fired let the case end after 30 s and pass, and
# the first run ran c.test too.
t_rerunkilled() {
  rerunwt 'echo two >> a.txt' '1 stall flaky'
  tuned '.tunables.testTimeout = 2' rerunstep || fail "the test step did not pass on its run again: $(ran 2)"
  [ "$(ran 1)" = "one two flaky" ] || fail "the first run was not cut off in b.test: $(ran 1)"
  [ "$(ran 2)" = "flaky three" ] || fail "the run again did not run just the cases that had not passed: $(ran 2)"
  [ "$(jq -c '[.reason, .rerun.exit, .rerun.failures.timeout.file]' "$T/$CASE/cards/c7.firstrun")" = '["passed on re-run: b.test",124,"b.test"]' ] \
    || fail "the test line does not say it passed on re-run after a timeout in b.test: $(cat "$T/$CASE/cards/c7.firstrun" 2>&1)"
}

# A fix session that left the staged change as it was: the run after it covers only the cases that had not passed.
t_rerunsame() {
  rerunwt 'echo two >> a.txt' '1 fail flaky' '2 fail flaky'
  ! rerunstep || fail "the first test step passed"
  rerunstep || fail "the step after a fix that made no edit did not pass: $(ran 3)"
  [ "$(ran 3)" = flaky ] || fail "the run after a fix that left the change as it was did not run only the case that had not passed: $(ran 3)"
  [ "$(sed 1,3d "$STUB/rerun.3" | tr '\t\n' ':|')" = "pass:a.test|pass:c.test|fail:b.test:flaky|" ] || fail "the run after the fix was not told what passed: $(cat "$STUB/rerun.3" 2>&1)"
}

# Bug: the change was told apart by its patch id, which is blind to whitespace, so a fix session that changed only
# spaces (`"a b"` to `"ab"`) kept what the run before passed, and the run after it skipped tests of the new change.
# The trees are compared, so a.txt is a file the fix changed and a.test's cases run again.
t_rerunspace() {
  rerunwt 'echo "a b" > a.txt' '1 fail flaky' '2 fail flaky'
  ! rerunstep || fail "the first test step passed"
  rerunedit 'echo ab > a.txt'; rerunstep || fail "the step after the fix did not pass: $(ran 3)"
  [ "$(grep $'^changed\t' "$STUB/rerun.3")" = $'changed\ta.txt' ] && [ "$(ran 3)" = "one two flaky" ] \
    || fail "the run after a fix that changed only whitespace did not run the changed file's tests: $(ran 3): $(cat "$STUB/rerun.3" 2>&1)"
}

# The next `git write-tree` fails, as it did under a release suite's load (the index locked, or no room), through a
# git on PATH that fails it once and runs the real git for everything else.
rerunnotree() {
  local g; g=$(command -v git) && mkdir -p "$STUB/bin" || fail "the failing git could not be made"
  printf '#!/usr/bin/env bash\nfor a; do [ "$a" != write-tree ] || [ ! -e %q ] || { rm -f %q; exit 128; }; done\nexec %q "$@"\n' \
    "$STUB/notree" "$STUB/notree" "$g" > "$STUB/bin/git" && chmod +x "$STUB/bin/git" && : > "$STUB/notree" || fail "the failing git could not be made"
  PATH=$STUB/bin:$PATH
}
# Bug (issue 788, t_rerunspace's failure in a release run): a test step whose tree could not be read kept a list
# naming no tree; the step after a fix could not compare trees, its refused full run kept every pass, and the fix's
# changed file (a.txt) ran none of its tests. A list with no tree is not kept, so that step runs the whole selection
# (but flaky, which passed on re-run and is kept off as flaky).
t_rerunnotree() {
  rerunwt 'echo two >> a.txt' '1 fail flaky'
  rerunnotree; rerunstep; [ ! -e "$STUB/notree" ] || fail "the first test step did not read the tree"
  rerunedit 'echo three >> a.txt'; rerunstep || fail "the step after the fix did not pass: $(ran 3)"
  [ "$(ran 3)" = "one two three" ] || fail "the step after a step with no tree did not run the whole selection: $(ran 3): $(cat "$STUB/rerun.3" 2>&1)"
}
# Bug (issue 788): the step after a fix, whose own tree could not be read, rewrote the list as a refused full run with
# no tree in it: it kept every pass, so a.txt's tests did not run after the fix, nor in the step after it.
t_rerunnotreefix() {
  rerunwt 'echo two >> a.txt' '1 fail flaky' '2 fail flaky'
  ! rerunstep || fail "the first test step passed"
  rerunedit 'echo three >> a.txt'; rerunnotree; rerunstep || fail "the step after the fix did not pass: $(ran 3)"
  [ ! -e "$STUB/notree" ] || fail "the step after the fix did not read the tree"
  [ "$(ran 3)" = "one two flaky three" ] && [ ! -e "$T/$CASE/cards/c7.rerun" ] \
    || fail "the step after a fix with no tree kept a list or did not run the whole selection: $(ran 3): $(cat "$T/$CASE/cards/c7.rerun" 2>&1)"
}

# A file that had passed and runs again after the fix for the file it changed, and now fails, is not kept as passed
# without its failed case: the run again after it runs that case. Were the old pass kept alone, the run again would
# skip a.test and pass with `one` failing.
t_rerunfixkept() {
  rerunwt 'echo two >> a.txt' '1 fail flaky' '2 fail flaky' '3 fail one'
  ! rerunstep || fail "the first test step passed"
  rerunedit 'echo three >> a.txt'; rerunstep || fail "the step after the fix did not pass on its run again: $(ran 4)"
  [ "$(ran 3)" = "one two flaky" ] || fail "the run after the fix was not of the failed case and a.test's cases: $(ran 3)"
  [ "$(sed 1,3d "$STUB/rerun.4" | tr '\t\n' ':|')" = "pass:a.test|pass:b.test|pass:c.test|ok:a.test:two|fail:a.test:one|" ] \
    || fail "the run again was not told that a.test's case failed: $(cat "$STUB/rerun.4" 2>&1)"
  [ "$(ran 4)" = one ] || fail "the run again did not run the case that failed after the fix: $(ran 4)"
}

# Bug: a failed run after a fix dropped every pass the list kept of a file that ran in it, so the cases of that file
# the fix did not select ran again (the engine's runner: a fix of one engine file failed one of its cases, and the
# cases of the card's other files ran again). The fix edits x.txt, which selects a.test's case one alone; one fails
# again, and two, which passed and did not run, stays kept.
t_rerunfixcase() {
  rerunwt 'echo two >> a.txt' '1 fail one' '2 fail one' '3 fail one'
  ! rerunstep || fail "the first test step passed"
  rerunedit 'echo x >> x.txt'; rerunstep || fail "the step after the fix did not pass on its run again: $(ran 4)"
  [ "$(grep $'^changed\t' "$STUB/rerun.3")" = $'changed\tx.txt' ] && [ "$(ran 3)" = one ] \
    || fail "the run after the fix was not of the failed case alone: $(ran 3): $(cat "$STUB/rerun.3" 2>&1)"
  [ "$(sed 1,3d "$STUB/rerun.4" | tr '\t\n' ':|')" = "pass:b.test|pass:c.test|ok:a.test:two|fail:a.test:one|" ] \
    || fail "the run again after a failed run after the fix was not told a.test's two still passed: $(cat "$STUB/rerun.4" 2>&1)"
  [ "$(ran 4)" = one ] || fail "the run again ran more than the case that failed: $(ran 4)"
}

# A fix that also edits a file of the "all" area (core.txt, in the map as `all`) runs the whole selection again.
t_rerunfixall() {
  rerunwt 'echo two >> a.txt' '1 fail flaky' '2 fail flaky'
  ! rerunstep || fail "the first test step passed"
  rerunedit 'echo two >> a.txt; echo x >> core.txt'; rerunstep || fail "the step after the fix did not pass: $(ran 3)"
  [ "$(ran 3)" = "one two flaky three" ] || fail "the run after a fix of a file of the \"all\" area was not of the whole selection: $(ran 3)"
}

# A fix that edits only a test file (c.test, which had passed) runs the case that had failed and that file's cases;
# a.test, whose file the fix did not touch, is kept as passed.
t_rerunfixtest() {
  rerunwt 'echo two >> a.txt' '1 fail flaky' '2 fail flaky'
  ! rerunstep || fail "the first test step passed"
  rerunedit 'echo x >> c.test'; rerunstep || fail "the step after the fix did not pass: $(ran 3)"
  [ "$(grep $'^changed\t' "$STUB/rerun.3")" = $'changed\tc.test' ] || fail "the run after the fix was not told the one file the fix changed: $(cat "$STUB/rerun.3" 2>&1)"
  [ "$(ran 3)" = "flaky three" ] || fail "the run after a fix of a test file alone was not of the failed case and that file's cases: $(ran 3)"
}
