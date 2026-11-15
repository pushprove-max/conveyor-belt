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
# $STUB/rerun.<run> is what the loop gave that run to go by. A run of a card's failing cases on main (verdicts(), in
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
case $PWD in */mainrun/*) n=main ;; *) n=$(( $(cat "$STUB/n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$STUB/n" ;; esac
[ "$RR" = /dev/null ] || cp "$RR" "$STUB/rerun.$n"
[ ! -f "$STUB/pre" ] || . "$STUB/pre"
rc=0; k=0
for f in a.test b.test c.test; do
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
echo "TESTRUN cases=$k of=4" >> "$L"; [ "$RR" = /dev/null ] || echo "TESTRUN kept=$((4 - k))" >> "$L"
exit $rc
EOF
  echo '. "$STUB/test-cmd"' > "$STUB/mainrun-cmd"
}
ran() { sed -n "s/^$1 //p" "$STUB/ran" | tr '\n' ' ' | sed 's/ $//'; } # <run>: the cases it ran
# A card's test steps without the card: its worktree $T/$CASE/cards/c7 on main, its change staged, and the engine's
# own tests() (lib/testrun.sh), with the engine's libraries sourced as conveyor.sh sources them (as slots.test.sh's
# teststep does), run on it as card() runs it at each test step; a fix session is `rerunedit <edit>` between two
# steps. What tests() alone decides (what a run after a fix keeps, runs and is told) is proved so: a whole card run
# cost each case about 3 CPU s alone and twice that beside the file's other cases, a main run of its failing cases
# among it. (What a card adds around tests(): a pass on re-run on its test line and the Board, t_rerunpass; the main
# run and the fix session, t_rerunfail; a session that moved HEAD, t_rerunmoved; the rebuild, t_rerunrebuilt; the
# retry, t_rerunretry.)
rerunedit() { (cd "$T/$CASE/cards/c7" && eval "$1") && git -C "$T/$CASE/cards/c7" add -A; } # <shell edit in the worktree>: the build's or a fix's edit, staged
rerunstep() { # exits as tests() returns; a pass leaves its test line's part of the first run, as card() puts it (firstrun()), in c7.firstrun
  ( set -- run; HERE=$SRC; export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    eval "$(sed -n '/^\. "\$HERE\/lib\/portable.sh"/,/^\. "\$HERE\/lib\/records.sh"/p' "$SRC/conveyor.sh"; grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")"
    names || exit 1; tests "$T/$CASE/cards/c7" || exit; firstrun "$T/$CASE/cards/c7" pass > "$T/$CASE/cards/c7.firstrun" ) > /dev/null 2>&1
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
  rerunsetup '1 fail flaky'
  loop run 1 > /dev/null || fail "run exited non-zero"
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
  st 'select(.step == "landed") | .step' | grep -q landed || fail "the card did not land"
  loop check || fail "the record check refuses a test line with its first run"
  # The Board draws the card's Test step and its tests bar from these: each says it passed on re-run.
  [ "$(loop snapshot | jq -c '.landed[0].track | [.steps[3].rerun, [.records[] | select(.name == "tests passed") | .rerun]]')" = '[true,[true]]' ] \
    || fail "the card's track does not say its tests passed on re-run: $(loop snapshot | jq -c '.landed[0].track | [.steps, .records]')"
  # Bug: a later line that reused that pass (card(): reused, as after giving way) drew the Test step as a plain pass.
  jq -c 'if .step == "test" then ., (del(.rerun, .reason) + {reason: "", reused: true}) else . end' "$ST/cards.jsonl" > "$STUB/cards.new" \
    && mv "$STUB/cards.new" "$ST/cards.jsonl"
  [ "$(st 'select(.step == "test") | .reused // false' | tr '\n' ' ')" = "false true " ] || fail "the reused pass line was not added: $(st 'select(.step == "test")')"
  [ "$(loop snapshot | jq -c '.landed[0].track.steps[3].rerun')" = true ] \
    || fail "a pass reused after a pass on re-run erased it from the card's Test step: $(loop snapshot | jq -c '.landed[0].track.steps[3]')"
}

# A case that fails again on its run again goes to its fix session, as before. The fix edits only the file under test,
# a.txt (the map's a.test): the run after it is of the case that had failed and a.test's cases, and no other; c.test,
# which passed and which no changed file selects, is kept as passed (the owner, 2026-11-13: #325 had one failing case
# of its selection, and after its fix the whole selection would have run again).
t_rerunfail() {
  rerunsetup '1 fail flaky' '2 fail flaky'
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
  # Before the fix, the case ran on main (verdicts()), alone, and passed there: the card's to fix, and no P0.
  [ "$(ran main)" = flaky ] && [ "$(sed -n 's/^fail\t//p' "$STUB/rerun.main" | tr '\t\n' ':|')" = "b.test:flaky|" ] \
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
  [ "$(loop snapshot | jq -c '.landed[0].track | [.steps[3].rerun, [.records[] | select(.name == "tests passed") | .rerun]]')" = '[null,[null]]' ] \
    || fail "a card whose last run passed first time is drawn as passed on re-run: $(loop snapshot | jq -c '.landed[0].track.steps')"
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

# Bug this guards against: a session that brings the change onto another HEAD and edits it where main changed
# nothing (here a.txt, the card's own file, on a HEAD whose new commit changes no file) has edited it outside any
# conflict: its passes are not kept, and the run after it is of the whole selection.
t_rerunmoved() {
  rerunsetup '1 fail flaky' '2 fail flaky'
  echo 'echo two >> a.txt; [ "$(wc -l < "$STUB/sessions")" = 1 ] || git update-ref HEAD "$(git commit-tree "HEAD^{tree}" -p HEAD -m moved)"' > "$STUB/build"
  loop run 1 > /dev/null || fail "run exited non-zero"
  [ "$(st 'select(.step == "fix") | .step' | wc -l)" = 1 ] || fail "no fix session ran"
  [ ! -e "$STUB/rerun.3" ] && [ "$(ran 3)" = "one two flaky three" ] || fail "the run after a session that moved HEAD was not of the whole selection: $(ran 3)"
}

# Issue 461 (#415 ran all 45 of its test files twice on 2026-11-14): a test step that would run the whole selection
# again after a fix and review round that changed nothing refuses the full run. Here the fix session leaves the change
# as it was, and the last run's list names a commit that is none (as a spoilt list would): the run after the round
# runs only what was not kept as passed (flaky), not a.test and c.test; its line records the refusal and why; health
# lists it, so the Foreman's watcher wakes on it (conveyor/foreman/foreman.test.sh, t_wake). The first run, before any
# list, ran the whole selection and refused nothing.
t_rerunrefused() {
  rerunsetup '1 fail flaky' '2 fail flaky'
  cat > "$STUB/build" <<'EOF'
if [ "$(wc -l < "$STUB/sessions")" = 1 ]; then echo two >> a.txt
else awk 'BEGIN { FS = OFS = "\t" } $1 == "base" { $2 = "0000000000000000000000000000000000000001" } 1' "$PWD.rerun" > "$STUB/list" && mv "$STUB/list" "$PWD.rerun"; fi
EOF
  loop run 1 > /dev/null || fail "run exited non-zero"
  [ "$(ran 1)" = "one two flaky three" ] && [ "$(tline 1 '.refused // "none"')" = none ] || fail "the first run was not of the whole selection, or refused: $(ran 1): $(tline 1 tojson)"
  [ "$(st 'select(.step == "test" or .step == "fix") | "\(.step) \(.result)"' | tr '\n' ,)" = "test fail,fix ok,test pass," ] \
    || fail "not a failed run, its fix and a run that passed: $(st 'select(.step == "test" or .step == "fix") | "\(.step) \(.result)"' | tr '\n' ,)"
  [ "$(ran 3)" = flaky ] || fail "the refused full run ran more than what was not kept as passed: $(ran 3): $(cat "$STUB/rerun.3" 2>&1)"
  [ "$(tline 2 .refused)" = "refused full run: the commit last tested on (0000000000000000000000000000000000000001) cannot be compared with HEAD" ] \
    || fail "the test line does not record the refusal and why: $(tline 2 tojson)"
  loop check || fail "the record check refuses a test line with a refused full run"
  [ "$(loop health | jq -c '.refused | map([.issue, (.reason | startswith("refused full run: "))])')" = '[[7,true]]' ] || fail "health does not list the refused run for the Foreman: $(loop health | jq -c .refused)"
}

# A merge in doubt (the session that brought the change onto main edited it outside the conflicts: here b.txt beside
# the conflict in a.txt) runs the whole selection, and refuses nothing: the merge may have broken what passed before.
t_rerunmergedoubt() {
  rerunsetup
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
  rerunsetup
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
# list with the patch) and runs flaky alone, on the main it was tested on and on one moved since by a commit that
# changes only z.txt, which none of its tests selects. (Main moving by a file a test selects: t_rerunrebuilt.)
retried() { # [move main]
  rerunsetup '1 fail flaky' '2 fail flaky' '3 fail flaky' '4 fail flaky'
  for i in 4 5; do echo "$GO" > "$STUB/review.$i"; done
  echo 'grep -qx two a.txt || echo two >> a.txt' > "$STUB/build"
  loop run 1 > /dev/null || fail "run exited non-zero"
  [ "$(st 'select(.step == "blocked") | .issue')" = 7 ] && [ "$(ran 4)" = flaky ] || fail "#7 did not block after failing flaky through its fix: $(st '"\(.step) \(.result)"' | tr '\n' ,)"
  [ -z "${1:-}" ] || { echo z > "$R/z.txt"; git -C "$R" add z.txt; git -C "$R" commit -qm "main moves"; }
  loop retry 7 > /dev/null && loop run 1 > /dev/null || fail "the retried #7 did not run"
  [ "$(ran 5)" = flaky ] && [ "$(st 'select(.step == "test") | .result' | tail -n 1)" = pass ] \
    || fail "the retried card did not keep the passes of its last run: $(ran 5): $(cat "$STUB/rerun.5" 2>&1)"
}
t_rerunretry() {
  retried
  [ -z "$(grep -E $'^(main|changed)\t' "$STUB/rerun.5")" ] || fail "the retried card on the same main was told of changes: $(cat "$STUB/rerun.5")"
}
t_rerunretrymoved() {
  retried move
  [ "$(grep -E $'^(main|changed)\t' "$STUB/rerun.5" | tr '\t\n' ':|')" = "main:z.txt|" ] || fail "the retried card was not told what main changed: $(cat "$STUB/rerun.5")"
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
