#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a card's failing cases run on main before any fix session (mainred.sh verdicts()); main red makes the card wait.
# The fix card's check, mainred.sh verdicts() alone, a fix card with no change and mainred.sh mainwait() are mainredproof.test.sh's cases,
# which use this file's eng().
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Card c7's failed test step, as card() takes it, without the card: mainred.sh verdicts() on its worktree, given its last run's
# failures (<failures json>, as testfails() gives them), and its test line as card() writes it (failline()), with
# <jq> applied to mainred.sh verdicts()'s result for that line only. Prints mainred.sh verdicts()'s result.
mrverdicts() { # <failures json> [jq]
  local fl=$1
  eng 'TEST_WAIT=; TEST_RUN=; TEST_FREE=; v=$(verdicts c7 "$CONVEYOR_CARDS/c7" "$fl") \
    && record c7 7 test fail "$(failline "$CONVEYOR_CARDS/c7" 1 0 "$fl" "$(jq -c '"'${2:-.}'"' <<<"$v")" "{}")" && printf "%s\n" "$v"'
}
# Card c7's change fitted onto main as it is now, as settle() fits a change that still applies there (t_mainfixed
# calls settle() itself).
mrfit() {
  local w=$T/$CASE/cards/c7
  git -C "$w" diff --cached --binary > "$w.fit" && git -C "$w" reset -q --hard "$(git -C "$R" rev-parse HEAD)" && git -C "$w" apply --index "$w.fit" \
    || fail "the change could not be fitted onto main"
}
# Where card()'s Test step goes (card.sh testroute()) given <arguments>, card()'s repaired, tmain and tfix as the
# caller's environment sets them ('' when unset). mrroute is the subshell form of apiroute.test.sh: no card runs.
mrroute() { # <testroute's arguments>...
  local a; printf -v a ' %q' "$@"
  eng 'repaired=${repaired:-} tmain=${tmain:-} tfix=${tfix:-}; testroute'"$a"
}

# Bug it catches: #423 failed on a test main had broken since #442, and went to a fix round a session could not win.
# b.test's flaky fails on the card's run, its run again and on main: every verdict is main (so card() waits, with no
# fix session and no block), the case goes to the fix card of main's commit, with no GitHub issue (#597), and its test
# line says so. b.test stands for a runner (the engine's conveyor/conveyor.test.sh names its cases' failures as its
# own): the fix card names the last commit of the file that defines the case, cases/b.test.sh, not that of the runner,
# changed later. Main moves and still fails it: the card's run on the new main runs what failed, and starts no second
# fix card while the first holds the case. Main moves again, now passing it: the run on main as it is now passes.
# Bug it catches too: a file that failed naming no case (a shell test's `FAIL: ...`) was given to main's run with no
# line, so main's clean tree ran nothing for it, the run passed and a file broken on main went to a fix session. c.test
# fails naming no case beside b.test's flaky, on every run until main is green: main's run is told to run it (a `fail`
# line with no case), runs it, and the file gets the verdict main and goes to the fix card too.
# One fixture for all: each step is the engine function card() calls there (tests(), mainred.sh verdicts(), mainwait()).
t_mainred() {
  rerunsetup '1 fail flaky' '1 bare three' '2 fail flaky' '2 bare three' '3 fail flaky' '3 bare three' '4 fail flaky' '4 bare three' \
    'main fail flaky' 'main bare three'; rerunfiles
  local b s v1 v2 mw snap fl='{"of":null,"files":[{"file":"b.test","cases":[{"name":"flaky","line":"1"}]},{"file":"c.test","cases":[]}],"timeout":null}'
  mkdir -p "$R/cases"; echo 't_flaky() { :; }' > "$R/cases/b.test.sh"; git -C "$R" add cases; git -C "$R" commit -qm "the case's file"; b=$(git -C "$R" log -1 --format=%h)
  echo runner > "$R/b.test"; git -C "$R" add b.test; git -C "$R" commit -qm "the runner"; s=$(git -C "$R" rev-parse HEAD)
  git -C "$R" worktree add -q --detach "$T/$CASE/cards/c7" && rerunedit 'echo two >> a.txt' || fail "the card's worktree could not be made"
  eng 'append "$(line c7 7 picked ok "{\"title\":\"title 7\"}")"' || fail "the card's picked line could not be written"
  ! rerunstep || fail "the card's test step passed"
  v1=$(mrverdicts "$fl" '.mainRun.sec = 7') || fail "verdicts failed: $v1"
  # Each failing file runs on main once, whole, through test.fileCommand, whether it names a case or none.
  [ "$(grep $'^fail\t' "$STUB/rerun.main" | tr '\t\n' ':|')" = "fail:c.test|fail:b.test|" ] && [ "$(ran main)" = "three flaky" ] \
    || fail "main's run was not told to run each failing file once, whole: $(ran main): $(cat "$STUB/rerun.main" 2>&1)"
  [ "$(jq -c '[.verdicts, .mainRun.sha]' <<<"$v1")" = "[[{\"case\":\"c.test\",\"verdict\":\"main\"},{\"case\":\"b.test: flaky\",\"verdict\":\"main\"}],\"$s\"]" ] \
    && [ "$(tline 1 '[.result, .verdicts, .mainRun.sha] | tojson')" = "$(jq -c '["fail", .verdicts, .mainRun.sha]' <<<"$v1")" ] \
    || fail "the test line does not give the case's and the file's verdicts and main's run: $v1: $(tline 1 tojson)"
  jq -r '.mainRun.sec' <<<"$v1" | grep -qE '^[0-9]+$' || fail "verdicts() does not give the seconds main's run took: $v1"
  # Every verdict main: the Test step waits for main (testroute(): main), with no fix session and no block.
  [ "$(mrroute verdicts "$v1")" = main ] || fail "testroute verdicts did not send the card to the wait for main, given $v1: $(mrroute verdicts "$v1")"
  # No GitHub issue (#597): the case and the file go to main's commit's one fix card, not picked yet.
  [ ! -s "$STUB/filed" ] && [ "$(jq -c --arg s "$s" '[.reds[] | [.sha == $s, .card, [.cases[].case]]]' "$ST/mainred.json")" = '[[true,null,["c.test","b.test: flaky"]]]' ] \
    || fail "the case and the file did not go to one fix card of main's commit, with no issue filed: $(cat "$ST/mainred.json" "$STUB/filed" 2>&1)"
  [ "$(jq -r '.reds[0].cases[] | select(.case == "b.test: flaky") | "\(.files) \(.last)"' "$ST/mainred.json")" = "[\"cases/b.test.sh\"] $b the case's file" ] \
    || fail "the fix card does not name the last commit of the case's file: $(cat "$ST/mainred.json")"
  [ ! -e "$T/$CASE/cards/mainrun/c7" ] || fail "main's worktree was left behind"
  echo m > "$R/m.txt"; git -C "$R" add m.txt; git -C "$R" commit -qm "main moves, still red"
  # The same change on the new main: its passes stand, and what failed runs again (tests(), rerunsince()).
  mrfit; ! rerunstep || fail "the card's test step on the new main passed"
  [ "$(ran 3)" = "flaky three" ] && [ "$(git -C "$T/$CASE/cards/c7" log -1 --format=%s)" = "main moves, still red" ] \
    || fail "the run after main moved was not of the failing case and file, on main as it is now: $(ran 3)"
  v2=$(mrverdicts "$fl" '.mainRun.sec = 5') && [ "$(jq -c '[.verdicts[].verdict]' <<<"$v2")" = '["main","main"]' ] || fail "main's run on its new commit did not fail both: $v2"
  [ "$(jq '.reds | length' "$ST/mainred.json")" = 1 ] && [ ! -s "$STUB/filed" ] \
    || fail "the new main commit started a second fix card for cases the first, not yet picked, holds: $(cat "$ST/mainred.json" "$STUB/filed" 2>&1)"
  sed -i '/^main /d' "$STUB/plan"
  echo n > "$R/n.txt"; git -C "$R" add n.txt; git -C "$R" commit -qm "main is green"
  mrfit; rerunstep && [ "$(ran 5)" = "flaky three" ] || fail "the card's run on main as it is now did not run what failed, or did not pass: $(ran 5)"
  loop check || fail "the record check refuses a test line with its verdicts"
  # The Board's Metrics count each failure by its verdict, and add up the seconds main's runs took: here 7 and 5 (the
  # stub's runs take under a second, so the lines are given those). They count a card once it has ended: its landed line.
  eng 'append "$(line c7 7 landed ok "{\"product\":true,\"sha\":\"$(git rev-parse HEAD)\"}")"' || fail "the card's landed line could not be written"
  # Issue 201: while a card only waits for main, its wait mark stands, so the loop counts it against no build slot (idle()).
  # Issue 220: the snapshot gives when the wait for main began (the belt's live.at), which the Foreman's watcher times
  # its wake from; without it the wait never wakes the Foreman. The wait is mainred.sh mainwait() itself, polled as it runs: only
  # a wait under way holds its live record and its mark, and it ends only as main moves. Card c8 waits here, at the
  # end, so the one snapshot below shows its live record and c7's metrics: a second snapshot costs about a second.
  # card() begins the wait with the test step's start line, which the snapshot reads the live record by.
  s=$(git -C "$R" rev-parse HEAD); eng 'append "$(line c8 8 picked ok "{\"title\":\"title 8\"}")"' || fail "the waiting card's picked line could not be written"
  ( eng 'LIVE=0.1; began c8 8 test && mainwait "$CONVEYOR_CARDS/c8" '"$s"' d.test "d.test: late"; echo "ended $?"' > "$STUB/mw.out" 2>&1 ) & mw=$!
  wait_until "grep -qs 'waiting for main to change: d.test, d.test: late fail on main at ${s:0:12} too' '$T/$CASE/cards/c8.live' && [ -e '$T/$CASE/cards/c8.idle' ]" 'cat "$STUB/mw.out"' \
    || fail "the card waiting for main did not say so, or did not mark itself waiting: the loop would count it against the cap"
  # The snapshot's clock is c7's landing (CONVEYOR_NOW): metrics.today is the local day of the clock, so a case that ran
  # past midnight between c7's landing and this snapshot counted no failure today.
  snap=$(CONVEYOR_NOW=$(st 'select(.card == "c7" and .step == "landed") | .time | fromdate') loop snapshot --fresh 2>/dev/null)
  [ "$(jq -r '.belt[] | select(.card == "c8") | .live.at' <<<"$snap")" = "$(jq -r .at "$T/$CASE/cards/c8.live")" ] \
    || fail "the snapshot does not give when the wait for main began: $(jq -c ".belt" <<<"$snap")"
  [ "$(jq -c '.metrics.today.testFailures' <<<"$snap")" = '{"card":0,"main":4,"flaky":0,"mainSec":12}' ] \
    || fail "the snapshot's metrics do not count the failures by verdict, with main's seconds: $(jq -c '.metrics.today.testFailures' <<<"$snap")"
  echo o > "$R/o.txt"; git -C "$R" add o.txt; git -C "$R" commit -qm "main moves again"
  wait "$mw"; [ "$(cat "$STUB/mw.out")" = "ended 0" ] || fail "the wait did not end once main moved: $(cat "$STUB/mw.out")"
}

# settle() of card c7 at its landing step, as card() calls it after a wait for main or once main moved under its failed
# run, caught cleared (#582). session() stands for the session that brings the change onto main (no model): told main
# moved, it makes <edit>, and it notes each call in $STUB/sessions; donewhen.sh checked() (the Done-when check of its reply)
# passes. <more> runs after it in the same engine shell. run.out ends with what <more> prints.
mrsettle() { # <edit> [more]
  fx_in 'cd "$R" || exit 9; caught="" waitsec=0 behind="[]" parsecheck=""
    session() { echo x >> "$STUB/sessions"; grep -q "^# Main moved" <<<"$2" && (cd "$1" && '"$1"') > /dev/null 2>&1; echo "{}"; }
    checked() { :; }
    settle c7 7 "$CONVEYOR_CARDS/c7" "Build the issue." land "$(issue 7 2026-01-01)"; echo "settle: $?"; '"${2:-}"
}

# Issue 582 (#530 tested three times on its old commit, through a fix round that changed nothing, and blocked): main
# fails b.test's flaky as the card is built on it (M1), and main fixes it (M2) before the card's failing case runs on
# main, so main's run of the case passes and the failure is the card's. Bug it catches: the card went to a fix session
# and tested again on M1, without main's fix. It is brought onto M2 first (settle()), the failed case runs again
# there alone and passes: no session.
t_mainfixed() {
  rerunsetup '1 fail flaky' '2 fail flaky'; rerunfiles
  git -C "$R" worktree add -q --detach "$T/$CASE/cards/c7" && rerunedit 'echo two >> a.txt' \
    || fail "the card's worktree could not be made"
  local m2 v w=$T/$CASE/cards/c7
  echo '[ "$n" != 3 ] || git rev-parse HEAD > "$STUB/head.3"' > "$STUB/pre"
  ! rerunstep || fail "the card's test step passed"
  echo fixed > "$R/fix.txt"; git -C "$R" add fix.txt; git -C "$R" commit -qm "main fixes flaky"; m2=$(git -C "$R" rev-parse HEAD)
  v=$(mrverdicts '{"of":null,"files":[{"file":"b.test","cases":[{"name":"flaky","line":"1"}]}],"timeout":null}') || fail "verdicts failed: $v"
  [ "$(jq -c .verdicts <<<"$v")" = '[{"case":"b.test: flaky","verdict":"card"}]' ] && [ "$(jq -r .mainRun.sha <<<"$v")" = "$m2" ] \
    || fail "the case did not pass on main's run at M2: $v"
  # The failure is the card's, and main moved under it: the Test step brings it onto main (testroute(): moved), not to
  # a fix round; once it has been fitted onto a main that moved (tmain), the same failure goes to the fix round.
  [ -z "$(mrroute verdicts "$v")" ] && [ "$(mrroute "$w")" = moved ] && [ "$(tmain=1 mrroute "$w")" = fix ] \
    || fail "testroute did not send the card's failure on M1 onto M2, given $v and the worktree $w: '$(mrroute verdicts "$v")' '$(mrroute "$w")' '$(tmain=1 mrroute "$w")'"
  mrsettle 'false'
  [ "$(tail -n 1 "$T/$CASE/run.out")" = "settle: 0" ] && [ "$(git -C "$w" rev-parse HEAD)" = "$m2" ] && [ "$(git -C "$w" diff --cached --name-only HEAD)" = a.txt ] \
    || fail "settle() did not bring the change onto M2 as it was: $(cat "$T/$CASE/run.out")"
  rerunstep || fail "the failed case did not pass on M2: $(ran 3)"
  [ "$(ran 3)" = flaky ] && [ "$(cat "$STUB/head.3")" = "$m2" ] && [ ! -e "$STUB/sessions" ] \
    || fail "the failed case did not run again alone on main's fix, before any session: $(ran 3) on $(cat "$STUB/head.3" 2>&1)"
}

# Issue 582, after the landing's one rebuild (caught): #7's change (a.txt's line to seven) passes on its first main
# (run 1), main changes that line (main1), and the landing's rebuild brings the change onto main1; then main changes
# the line again (main2), so the change no longer applies. Bug it catches: settle() put such a card back on its old
# commit, as after the rebuild, and its run went there, without main's change. With caught cleared, as card() clears
# it, one session, told main moved, brings it onto main2 (settle() returns 2: it is reviewed again there), with no
# fix round. Given <plan lines> (the stub's, for runs 2 on), the card's run 1 is made, on its first main.
caughtsetup() { # [plan lines]
  local w=$T/$CASE/cards/c7
  rerunsetup "$@"; rerunfiles
  git -C "$R" worktree add -q --detach "$w" && rerunedit 'echo seven > a.txt' \
    || fail "the card's worktree could not be made"
  [ $# = 0 ] || rerunstep || fail "the card's first run did not pass: $(ran 1)"
  echo main1 > "$R/a.txt"; git -C "$R" commit -qam "main moves"
  git -C "$w" reset -q --hard "$(git -C "$R" rev-parse HEAD)" && rerunedit 'echo seven > a.txt' || fail "the landing's rebuild onto main1 could not be made"
}
caughtmove() { echo main2 > "$R/a.txt"; git -C "$R" commit -qam "main moves again"; }
caughtfit() { # what settle() must show
  local w=$T/$CASE/cards/c7
  grep -qx "settle: 2" "$T/$CASE/run.out" && [ "$(st 'select(.step == "fix") | .reason')" = "main moved since the card's change was made, and the change no longer applied to it" ] \
    && [ "$(wc -l < "$STUB/sessions")" = 1 ] || fail "not one session bringing the card onto main, and no fix round: $(cat "$T/$CASE/run.out"): $(st 'select(.step == "fix") | .reason')"
  [ "$(git -C "$w" rev-parse HEAD)" = "$(git -C "$R" rev-parse ':/^main moves again')" ] && [ "$(git -C "$w" show :a.txt)" = seven ] \
    || fail "the change was not brought onto main as it is now: $(git -C "$w" log -1 --format=%s) $(git -C "$w" show :a.txt 2>&1)"
}
# Main moved under the card's failed run (its run of the case passed there: the failure is the card's): the run after
# the session goes onto main2's commit. Its run after the rebuild (2: main's change selects a.test) and the run again
# (3) fail a.test's one. Bug it catches too (#374): a.test, which passed in run 1 and failed in run 2, kept its `pass`
# line beside its `fail` line, and the run again skipped it, ran no file and "passed on re-run".
t_mainfixedcaught() {
  caughtsetup '2 fail one' '3 fail one'
  echo '[ "$n" != 4 ] || git rev-parse HEAD > "$STUB/head.4"' > "$STUB/pre"
  ! rerunstep && [ "$(ran 3)" = one ] || fail "the run again after the rebuild did not run the case that failed: $(ran 2) | $(ran 3)"
  # The failure is the card's (its case passes on main); main moved again since the rebuild: testroute() gives moved,
  # so the card is fitted onto main2 (settle(), below), with no fix round.
  caughtmove; [ "$(mrroute "$T/$CASE/cards/c7")" = moved ] || fail "testroute did not send the worktree $T/$CASE/cards/c7, behind main2, onto main: $(mrroute "$T/$CASE/cards/c7")"
  mrsettle 'sed -i "s/^main2\$/seven/" a.txt'; caughtfit
  rerunstep && [ "$(cat "$STUB/head.4")" = "$(git -C "$R" rev-parse HEAD)" ] || fail "the run after the session did not pass on main2's commit: $(cat "$STUB/head.4" 2>&1)"
}
# Main failed the case too: the card waited for main to change, and main changed the same line. Its landed line's
# waitSec counts that wait: card()'s wait (mainwaited(), its mainred.sh mainwait() stubbed to move the shell's clock on 5 s in
# place of a real wait) and the landed line's extra as card() makes it (landextra()). Bug it catches: the drift watch
# (bench/drift.sh) had no minutes a card waited for main, as no line recorded them.
t_mainredcaught() {
  caughtsetup; caughtmove
  # Main fails the case too, and a case that passed on its run again is flaky: the Test step waits for main
  # (testroute(): main), as below; a flaky case is no failure of the card's.
  local v='{"verdicts":[{"case":"a.test: one","verdict":"main"},{"case":"b.test: flaky","verdict":"flaky"}]}'
  [ "$(mrroute verdicts "$v")" = main ] || fail "testroute verdicts did not send the card to the wait for main, given $v: $(mrroute verdicts "$v")"
  mrsettle 'sed -i "s/^main2\$/seven/" a.txt' 'mainsec=0; mainwait() { SECONDS=$((SECONDS + 5)); }
    mainwaited "$CONVEYOR_CARDS/c7" "$(git rev-parse HEAD)" "a.test: one"
    locked land c7 7 "$CONVEYOR_CARDS/c7" "title 7 (#7)" "$(landextra "" "" "[]")"; echo "land: $?"'; caughtfit
  [ "$(tail -n 1 "$T/$CASE/run.out")" = "land: 0" ] && [ "$(git -C "$R" show HEAD:a.txt)" = seven ] || fail "#7 did not land: $(cat "$T/$CASE/run.out")"
  # 5 s, or 6 when the clock's second turns as it is read.
  [ "$(st 'select(.step == "landed") | .waitSec | IN(5, 6)')" = true ] || fail "the landed line does not count the wait for main: $(st 'select(.step == "landed")')"
}

# Bug it catches (R235): a card whose failed case was the machine's waited for the machine hold or the repair lane
# (cardfailed(), mainred.sh holdwait()) and did not add that wait to mainsec, which its landed line's waitSec counts
# (t_mainredcaught, above), so the drift watch counted the wait as work. cardfailed() runs its machine route, each step
# around the wait stubbed: holdwait() moves the shell's clock on 60 s in place of a real wait, and settle() stops it.
t_mainredholdsec() {
  # shellcheck disable=SC2034 # FXWT is read by fx_in, a fix card's worktree; this case has none
  local FXWT=$T/$CASE/none
  setup '[]'
  # shellcheck disable=SC2016 # expanded by fx_in's eval
  fx_in 'c=c7 n=7 wt=$T/$CASE/c7 rc=1 own="" sec=1 mainsec=0 br="" sprompt="" issue=""
    depsmissing() { :; }; voidrun() { return 1; }; testfails() { :; }; verdicts() { echo "{\"verdicts\":[]}"; }; testroute() { echo machine; }
    record() { :; }; failline() { :; }; testrulespass() { :; }; repairlane() { REPAIRED=no; return 1; }; locked() { :; }; began() { :; }
    unmate() { :; }; redbrief() { :; }; settle() { return 1; }; holdwait() { SECONDS=$((SECONDS + 60)); }
    cardfailed || :; echo "mainsec $mainsec"'
  # 60 s, or 61 when the clock's second turns as it is read.
  grep -qxE 'mainsec (60|61)' "$T/$CASE/run.out" || fail "cardfailed of a card whose failed case is the machine's did not add its 60 s wait for the machine hold to mainsec: $(tr '\n' '|' < "$T/$CASE/run.out")"
}

# Issue 598. Bug it catches: a landing broke a test its card did not run, and nothing linked the test to the files it
# changed, so later cards changing them did not run it either. In a fixture repo, landing L1's card ran
# tests/b.test.sh; landing A changes lib/a.sh and its card does not run it; landing C after it changes lib/c.sh. b.test
# fails on main: the case's entry in the main-red record (mainred.sh mainred()) names landing A, not C, and the fix card's
# worktree (mainred.sh testlinks()) holds .conveyor/test-links.json linking lib/a.sh, and only it, to tests/b.test.sh, staged to
# land with the fix.
t_mainredlinks() {
  local w=$T/$CASE r a h got
  r=$w/r; mkdir -p "$r/tests" "$r/lib"; git -C "$r" init -q
  land() { # <card> <issue> <file> <the test file its card ran, or none>
    echo "$1" > "$r/$3"; git -C "$r" add -A; git -C "$r" commit -qm "$1"
    jq -cn --arg c "$1" --argjson n "$2" --arg s "$(git -C "$r" rev-parse HEAD)" --arg t "$4" \
      '{card: $c, issue: $n, step: "test", result: "pass", why: {($t): ["the card changed it"]}}, {card: $c, issue: $n, step: "landed", result: "ok", sha: $s}' >> "$w/cards.jsonl"
  }
  echo 't_one() { :; }' > "$r/tests/b.test.sh"; land l1 1 lib/a.sh tests/b.test.sh
  land ca 2 lib/a.sh lib/a.test.sh; a=$(git -C "$r" rev-parse HEAD)
  land cc 3 lib/c.sh lib/c.test.sh; h=$(git -C "$r" rev-parse HEAD)
  git -C "$r" worktree add -q --detach "$w/fix" "$h"
  got=$( cd "$r" && eval "$(sed -n '/^mainred() {/,/^}/p; /^brokeby() {/,/^}/p; /^landingof() {/,/^}/p; /^testlinks() {/,/^}/p; /^linkput() {/,/^}/p; /^TESTLINK_DEPTH=/p' "$SRC/lib/mainred.sh")"
    stdb() { cat "$w/cards.jsonl"; }
    export MAINRED=$w/mainred.json
    # The loop's mainred.sh redpick() names the fix card in the entry; here the record is given it.
    mainred c9 "tests/b.test.sh: one" tests/b.test.sh "$h" && jq -c '.reds[0].card = "cfix"' "$MAINRED" > "$MAINRED.new" && mv "$MAINRED.new" "$MAINRED" \
      && testlinks cfix "$w/fix" && echo ok ) || fail "mainred or testlinks failed: $got"
  [ "$(jq -c '.reds[0].cases[0] | [.landing, .links]' "$w/mainred.json")" = "[{\"sha\":\"$a\",\"card\":\"ca\",\"issue\":2},{\"lib/a.sh\":[\"tests/b.test.sh\"]}]" ] \
    || fail "D1: the main-red record does not name landing A and its link: $(cat "$w/mainred.json" 2>&1)"
  [ "$(jq -c . "$w/fix/.conveyor/test-links.json")" = '{"lib/a.sh":["tests/b.test.sh"]}' ] \
    && [ "$(git -C "$w/fix" diff --cached --name-only)" = .conveyor/test-links.json ] \
    || fail "D1: the fix card's worktree does not stage the link of lib/a.sh to tests/b.test.sh: $(cat "$w/fix/.conveyor/test-links.json" 2>&1)"
}
# Issue 1303. Bug it catches: nothing recorded which landing turned main red, so no time lost to a red main could be
# put on the card that broke it. Landing l1's card ran b.test; landing ca after it did not, and b.test's flaky now fails
# on main: card c7's failure gets the verdict main, and verdicts() and the test line card() writes from it name ca in
# brokeMain, the landing the main-red record blames (mainred.sh brokeby()).
t_mainredblame() {
  rerunsetup '1 fail flaky' '2 fail flaky' 'main fail flaky'; rerunfiles
  local v fl='{"of":null,"files":[{"file":"b.test","cases":[{"name":"flaky","line":"1"}]}],"timeout":null}'
  eng 'append "$(line l1 1 test pass "{\"why\":{\"b.test\":[\"the card changed it\"]}}")" && append "$(line l1 1 landed ok "{\"product\":false,\"sha\":\"$(git rev-parse HEAD)\"}")"' \
    || fail "landing l1's lines could not be written"
  echo ca > "$R/ca.txt"; git -C "$R" add ca.txt; git -C "$R" commit -qm "landing ca"
  eng 'append "$(line ca 2 landed ok "{\"product\":false,\"sha\":\"$(git rev-parse HEAD)\"}")"' || fail "landing ca's line could not be written"
  git -C "$R" worktree add -q --detach "$T/$CASE/cards/c7" && rerunedit 'echo two >> a.txt' || fail "the card's worktree could not be made"
  eng 'append "$(line c7 7 picked ok "{\"title\":\"title 7\"}")"' || fail "the card's picked line could not be written"
  ! rerunstep || fail "the card's test step passed"
  v=$(mrverdicts "$fl") || fail "verdicts failed: $v"
  [ "$(jq -c '[.verdicts[].verdict, .brokeMain]' <<<"$v")" = '["main","ca"]' ] && [ "$(st 'select(.step == "test" and .card == "c7") | .brokeMain')" = ca ] \
    || fail "given b.test: flaky failing on main after landing ca, verdicts() or c7's test line does not name ca in brokeMain: $v: $(st 'select(.step == "test" and .card == "c7")'): $(cat "$ST/mainred.json" 2>&1)"
  loop check || fail "the record check refuses a test line with brokeMain"
}
# Issue 615. Bug it catches: card() staged the test links only as the fix card started, so a case that joined it later
# (mainred.sh mainred()) changed its brief but its links never landed. The fix card's entry gains a case linking lib/d.sh to
# tests/d.test.sh after its start; the next redbrief() before a session stages that link beside the first one.
t_mainredjoin() {
  local w=$T/$CASE got
  mkdir -p "$w/fix/.conveyor"; git -C "$w/fix" init -q
  echo '{"lib/a.sh":["tests/b.test.sh"]}' > "$w/fix/.conveyor/test-links.json"
  jq -n '{reds: [{sha: "s", card: "cfix", cases: [{case: "b", links: {"lib/a.sh": ["tests/b.test.sh"]}}, {case: "d", links: {"lib/d.sh": ["tests/d.test.sh"]}}]}]}' > "$w/mainred.json"
  got=$( eval "$(sed -n '/^redbrief() {/,/^}/p' "$SRC/lib/card.sh"; sed -n '/^testlinks() {/,/^}/p; /^linkput() {/,/^}/p' "$SRC/lib/mainred.sh")"
    # shellcheck disable=SC2034 # wt is read by redbrief(), run by the eval
    MAINRED=$w/mainred.json wt=$w/fix issue='{"title":"Main is red: b"}' sprompt='brief b'
    redissue() { echo '{"title":"Main is red: b, d"}'; }; issuepart() { echo "brief ${1:23:-2}"; }
    redbrief cfix 0 "" && echo "$issue|$sprompt" ) || fail "redbrief failed: $got"
  [ "$got" = '{"title":"Main is red: b, d"}|brief b, d' ] || fail "the brief does not name the case that joined: $got"
  [ "$(jq -c . "$w/fix/.conveyor/test-links.json")" = '{"lib/a.sh":["tests/b.test.sh"],"lib/d.sh":["tests/d.test.sh"]}' ] \
    && [ "$(git -C "$w/fix" diff --cached --name-only)" = .conveyor/test-links.json ] \
    || fail "the link of the case that joined is not staged: $(cat "$w/fix/.conveyor/test-links.json" 2>&1)"
}
# Issue 323: mainred.sh linksonly() after a main-fix card's session, which left its staged .conveyor/test-links.json in the
# worktree as a symlink to a file outside it, then .conveyor itself as a symlink to a folder outside it. Bug it
# catches: mainred.sh linksonly() wrote main's copy of the links through the symlink, so the session made the engine overwrite a
# file outside the worktree. The outside files keep their text; the links still count as the card's only change.
t_mainredlinksonlylink() {
  local w=$T/$CASE got
  mkdir -p "$w/fix/.conveyor" "$w/out/.conveyor"; git -C "$w/fix" init -q
  echo '{}' > "$w/fix/.conveyor/test-links.json"; git -C "$w/fix" add -A; git -C "$w/fix" commit -qm links
  echo keep > "$w/out/file"; echo keep > "$w/out/.conveyor/test-links.json"
  jq -n '{reds: [{sha: "s", card: "cfix", cases: [{case: "b", links: {"lib/a.sh": ["tests/b.test.sh"]}}]}]}' > "$w/mainred.json"
  got=$( eval "$(sed -n '/^testlinks() {/,/^}/p; /^linkput() {/,/^}/p; /^linksonly() {/,/^}/p' "$SRC/lib/mainred.sh")"
    MAINRED=$w/mainred.json
    testlinks cfix "$w/fix" && ln -sf "$w/out/file" "$w/fix/.conveyor/test-links.json" || exit 1
    linksonly cfix "$w/fix" && echo only
    rm -rf "$w/fix/.conveyor" && ln -s "$w/out/.conveyor" "$w/fix/.conveyor" || exit 1
    linksonly cfix "$w/fix" && echo dironly; : ) || fail "the fixture failed: $got"
  [ "$got" = only ] && [ "$(cat "$w/out/file")" = keep ] && [ "$(cat "$w/out/.conveyor/test-links.json")" = keep ] \
    || fail "linksonly() wrote through a symlink the session left, or took a symlinked .conveyor: $got: $(cat "$w/out/file" "$w/out/.conveyor/test-links.json")"
}
# A main-red fix card's worktree $T/$CASE/fix, main's .conveyor/test-links.json in it holding <main's links>, its entry
# (cfix, $T/$CASE/mainred.json) a case b linking lib/a.sh to tests/b.test.sh, and a file $T/$CASE/out/file outside it.
linkfix() { # <main's links>
  local w=$T/$CASE
  mkdir -p "$w/fix/.conveyor" "$w/out" && git -C "$w/fix" init -q && echo keep > "$w/out/file" || fail "the fixture could not be made"
  printf '%s\n' "$1" > "$w/fix/.conveyor/test-links.json"; git -C "$w/fix" add -A; git -C "$w/fix" commit -qm links || fail "main's links could not be committed"
  jq -n '{reds: [{sha: "s", card: "cfix", cases: [{case: "b", links: {"lib/a.sh": ["tests/b.test.sh"]}}]}]}' > "$w/mainred.json"
}
linkfns() { sed -n '/^testlinks() {/,/^}/p; /^linkput() {/,/^}/p; /^linksonly() {/,/^}/p' "$SRC/lib/mainred.sh"; }
# R133. Bug it catches: testlinks() wrote the links to .conveyor/test-links.json.new with a plain open, after
# linksonly() unlinked it, so a lingering session process that planted a symlink there in between made the engine
# write through it to a file outside the worktree. A testlinks() that plants that link, then runs the real one: the
# outside file keeps its text, and the staged links still count as the card's only change.
t_mainredlinksnew() {
  local w=$T/$CASE got
  linkfix '{}'
  got=$( eval "$(linkfns)"; MAINRED=$w/mainred.json
    testlinks cfix "$w/fix" || exit 1
    eval "real$(declare -f testlinks)"
    testlinks() { ln -s "$w/out/file" "$2/.conveyor/test-links.json.new"; realtestlinks "$@"; }
    linksonly cfix "$w/fix" && echo only; : ) || fail "the fixture failed: $got"
  [ "$got" = only ] && [ "$(cat "$w/out/file")" = keep ] \
    || fail "linksonly() with a symlink planted at test-links.json.new after its unlink wrote through it, or did not take the links alone: $got: $(cat "$w/out/file")"
}
# R132. Bug it catches: linksonly() took the change as links-only only when the links staged again came out the same
# blob, so a case that joined the fix card's entry during its build (adding links of its own) made a session with no
# change of its own fail the check, and bugproof() ran its cases on the old commit with only the links staged and
# blocked it, before nochange() could check main as it is now. Both bugproof() (redproof() stubbed to say it ran)
# and emptychange() take that change as none, the worktree reset to its commit. A staged link the entry lacks, a
# link of main's copy taken out, or a link the engine staged before the session taken out (the bug it catches: only
# main's copy and the entry were compared, so emptychange() reset that edit) is the session's own change:
# emptychange() keeps it, and the staged file stays.
t_mainredlinksadded() {
  local w=$T/$CASE got
  linkfix '{"lib/z.sh":["tests/z.test.sh"]}'
  # shellcheck disable=SC2034 # CARDS and UNFIXED are read by the bugproof() eval loads
  got=$( eval "$(linkfns; sed -n '/^emptychange() {/,/^}/p' "$SRC/lib/card.sh"; sed -n '/^bugproof() {/,/^}/p' "$SRC/lib/bugproof.sh")"
    MAINRED=$w/mainred.json CARDS=$w UNFIXED=''; redproof() { echo "redproof ran"; return 2; }
    testlinks cfix "$w/fix" || exit 1
    jq '.reds[0].cases += [{case: "d", links: {"lib/d.sh": ["tests/d.test.sh"]}}]' "$MAINRED" > "$w/red.new" && mv "$w/red.new" "$MAINRED" || exit 1
    bugproof cfix "$w/fix" '{}'; echo "bugproof $?"
    emptychange cfix 0 "$w/fix" ""; echo "empty $? [$(git -C "$w/fix" status --porcelain)]"
    # The last staged file takes out the link of d, which the engine staged with b's before it (bugproof()'s testlinks(),
    # kept in STAGEDLINKS): the entry and main's copy alone do not show that link was there, so the removal is the session's.
    for l in '{"lib/a.sh":["tests/b.test.sh","tests/own.test.sh"],"lib/z.sh":["tests/z.test.sh"]}' '{"lib/a.sh":["tests/b.test.sh"]}' \
      '{"lib/a.sh":["tests/b.test.sh"],"lib/z.sh":["tests/z.test.sh"]}'; do
      printf '%s\n' "$l" > "$w/fix/.conveyor/test-links.json"; git -C "$w/fix" add -A
      emptychange cfix 0 "$w/fix" ""; echo "empty $? $(git -C "$w/fix" show :.conveyor/test-links.json | jq -c .)"
    done )
  [ "$got" = $'bugproof 0\nempty 0 []\nempty 1 {"lib/a.sh":["tests/b.test.sh","tests/own.test.sh"],"lib/z.sh":["tests/z.test.sh"]}\nempty 1 {"lib/a.sh":["tests/b.test.sh"]}\nempty 1 {"lib/a.sh":["tests/b.test.sh"],"lib/z.sh":["tests/z.test.sh"]}' ] \
    || fail "a links-only change after a case joined the entry was not taken as no change, or a session's own link change was: $got"
}
# R132. Bug it catches: card.sh redbrief() before the review (testlinks()) staged every link of the entry again, so a
# session that took out a link the engine staged had that edit put back before emptychange() read it, which then reset
# it as links only. Entry cases b and d stage both links; the session takes d's out: testlinks() leaves it out and
# emptychange() keeps the edit. The session puts main's copy back: testlinks() stages nothing, so the worktree is
# main's. A case e joins after: its link alone is staged, not d's again (issue 615 still holds).
t_mainredlinksout() {
  local w=$T/$CASE got
  linkfix '{}'
  jq '.reds[0].cases += [{case: "d", links: {"lib/d.sh": ["tests/d.test.sh"]}}]' "$w/mainred.json" > "$w/red.new" && mv "$w/red.new" "$w/mainred.json" \
    || fail "the fixture could not be made"
  got=$( eval "$(linkfns; sed -n '/^emptychange() {/,/^}/p' "$SRC/lib/card.sh")"; MAINRED=$w/mainred.json
    links() { git -C "$w/fix" show :.conveyor/test-links.json | jq -c .; }
    testlinks cfix "$w/fix" || exit 1
    echo '{"lib/a.sh":["tests/b.test.sh"]}' > "$w/fix/.conveyor/test-links.json"
    testlinks cfix "$w/fix"; emptychange cfix 0 "$w/fix" ""; echo "out d: empty $? $(links)"
    echo '{}' > "$w/fix/.conveyor/test-links.json"
    testlinks cfix "$w/fix"; echo "main's: $(jq -c . "$w/fix/.conveyor/test-links.json")"
    jq '.reds[0].cases += [{case: "e", links: {"lib/e.sh": ["tests/e.test.sh"]}}]' "$MAINRED" > "$w/red.new" && mv "$w/red.new" "$MAINRED" || exit 1
    testlinks cfix "$w/fix"; echo "e joins: $(links)" )
  [ "$got" = $'out d: empty 1 {"lib/a.sh":["tests/b.test.sh"]}\nmain\'s: {}\ne joins: {"lib/e.sh":["tests/e.test.sh"]}' ] \
    || fail "testlinks() put back a link the session took out, or emptychange() did not keep that edit, or a joined case's link was not staged: $got"
}
# Issue 604. Bug it catches: a card that ran only some cases of a test file, named under the runner (`TESTRUN case`
# lines, no why or times of the file, no wholeSuite), counted as not having run it, so the search for the landing that
# broke a case went past it and named no landing, or the wrong one. In a fixture repo, landing L1's card ran the
# case `one` of tests/b.test.sh through the runner r.test.sh; landing A changes lib/a.sh and its card does not run it;
# landing C's card runs only the case `two` of the runner, which does not run `one`. `r.test.sh: one` fails on main:
# the main-red record names landing A and links lib/a.sh to tests/b.test.sh.
t_mainredpartial() {
  local w=$T/$CASE r a h got
  r=$w/r; mkdir -p "$r/tests" "$r/lib"; git -C "$r" init -q
  land() { # <card> <issue> <file> <the case of r.test.sh its card ran, or none>
    echo "$1" > "$r/$3"; git -C "$r" add -A; git -C "$r" commit -qm "$1"
    jq -cn --arg c "$1" --argjson n "$2" --arg s "$(git -C "$r" rev-parse HEAD)" --arg k "$4" \
      '{card: $c, issue: $n, step: "test", result: "pass", why: {"r.test.sh": ["the card changed it"]}, ranCases: {"r.test.sh": [$k]}},
       {card: $c, issue: $n, step: "landed", result: "ok", sha: $s}' >> "$w/cards.jsonl"
  }
  printf 't_one() { :; }\nt_two() { :; }\n' > "$r/tests/b.test.sh"; land l1 1 lib/a.sh one
  land ca 2 lib/a.sh none; a=$(git -C "$r" rev-parse HEAD)
  land cc 3 lib/c.sh two; h=$(git -C "$r" rev-parse HEAD)
  got=$( cd "$r" && eval "$(sed -n '/^mainred() {/,/^}/p; /^brokeby() {/,/^}/p; /^landingof() {/,/^}/p; /^TESTLINK_DEPTH=/p' "$SRC/lib/mainred.sh")"
    stdb() { cat "$w/cards.jsonl"; }
    # Issue 1066: the list of the commit's test files fails here. Bug it catches: mainred.sh mainred() then searched no file for
    # the case, took r.test.sh as the case's file, and named no landing.
    testtracked() { return 1; }
    export MAINRED=$w/mainred.json
    mainred c9 "r.test.sh: one" r.test.sh "$h" && echo ok ) || fail "mainred failed: $got"
  [ "$(jq -c '.reds[0].cases[0] | [.landing, .links]' "$w/mainred.json")" = "[{\"sha\":\"$a\",\"card\":\"ca\",\"issue\":2},{\"lib/a.sh\":[\"tests/b.test.sh\"]}]" ] \
    || fail "a run of only some cases of the file did not count, or one without the case did: $(cat "$w/mainred.json" 2>&1)"
}

# Issue 214: a card's test step names an engine case file's cases under that file, where records made before named
# them under the runner. Bugs it catches, in a fixture repo whose tests/b.test.sh runs its case `one` through the
# runner r.test.sh (it names it): an open fix card's entry `r.test.sh: one` did not hold `tests/b.test.sh: one`, so a
# second fix card started for the same case; the landing that broke it was not found, as the card that ran `one` (L1)
# recorded it under the runner (ranCases), so a later landing (A) that did not run it went unnamed; and the old entry's
# run on main (mainred.sh redrun()), whose result names tests/b.test.sh, gave no verdict for it.
t_mainredold() {
  local w=$T/$CASE r a h got
  r=$w/r; mkdir -p "$r/tests" "$r/lib"; git -C "$r" init -q
  land() { # <card> <issue> <file> <the case of r.test.sh its card ran, or none>
    echo "$1" > "$r/$3"; git -C "$r" add -A; git -C "$r" commit -qm "$1"
    jq -cn --arg c "$1" --argjson n "$2" --arg s "$(git -C "$r" rev-parse HEAD)" --arg k "$4" \
      '{card: $c, issue: $n, step: "test", result: "pass", ranCases: {"r.test.sh": [$k]}}, {card: $c, issue: $n, step: "landed", result: "ok", sha: $s}' >> "$w/cards.jsonl"
  }
  printf '# run alone: bash ../r.test.sh\nt_one() { :; }\n' > "$r/tests/b.test.sh"; land l1 1 lib/a.sh one
  land ca 2 lib/a.sh none; a=$(git -C "$r" rev-parse HEAD); h=$a
  jq -cn '{reds: [{sha: "0ld", cases: [{case: "r.test.sh: one", file: "r.test.sh", files: ["tests/b.test.sh"]}], card: null}]}' > "$w/mainred.json"
  got=$( cd "$r" && eval "$(sed -n '/^mainred() {/,/^}/p; /^redopen() {/,/^}/p; /^brokeby() {/,/^}/p; /^landingof() {/,/^}/p; /^redrun() {/,/^}/p; /^TESTLINK_DEPTH=/p' "$SRC/lib/mainred.sh")"
    stdb() { cat "$w/cards.jsonl"; }
    tests() { :; }; testlogs() { echo log; }; testfails() { echo '{"files": [{"file": "tests/b.test.sh", "cases": [{"name": "one"}]}]}'; }
    export MAINRED=$w/mainred.json
    mainred c9 "tests/b.test.sh: one" tests/b.test.sh "$h" && brokeby tests/b.test.sh "$h" tests/b.test.sh one | jq -r .sha \
      && redrun "$w/wt" "$(jq -c '[.reds[0].cases[0] | {name: .case, file, files, case: "one"}]' "$MAINRED")" | jq -r '.[0].verdict' ) || fail "mainred failed: $got"
  [ "$(jq -c '[.reds[] | .sha]' "$w/mainred.json")" = '["0ld"]' ] || fail "the open fix card's entry named under the runner did not hold the case: $(cat "$w/mainred.json")"
  [ "$got" = "$a"$'\n'fail ] || fail "the landing that broke it, or the old entry's verdict on main, was not found: '$got'"
}

# The engine's own functions, sourced as `run` sources them, in main's checkout: what a card's mainred.sh verdicts() and the
# loop's pick call, without a card run (#597's cases call mainred.sh mainred() and pick() themselves).
eng() { ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; cd "$R" && . "$SRC/conveyor.sh" state-dir > /dev/null && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" && names && eval "$1" ); }
# Issue 597: main-red filed a GitHub issue a case (13 in 9 hours, three by one landing). Bug it catches: two cases
# failing on one main commit filed two issues. They start one fix card of issue 0, picked ahead of the queue (#7),
# holding both, and nothing is filed. A third case found on that commit while the card runs is added to it, and starts
# no second card; a case the open card holds, found on a later commit, starts none either. Once that card has landed,
# a failure on a later commit starts a new card.
t_mainredcard() {
  setup "[$(issue 7 2026-01-01)]"
  local s s2 out c c2
  s=$(git -C "$R" rev-parse HEAD)
  out=$(eng 'mainred c1 "a.test: one" a.test '"$s"' && mainred c2 c.test c.test '"$s"' && locked pick "" "" "$(cat "$STUB/issues.json")"') || fail "the fix card was not picked: $out"
  c=${out%% *}
  [[ $out == *-0\ 0\ false ]] && [ "$(st "select(.card == \"$c\") | [.step, .issue, .title, .mainRed] | tojson")" = "[\"picked\",0,\"Main is red: a.test: one, c.test\",\"$s\"]" ] \
    || fail "not one fix card of issue 0 holding both cases, ahead of #7: $out: $(st "select(.card == \"$c\") | tojson")"
  [ ! -e "$STUB/filed" ] || fail "an issue was filed for main-red: $(cat "$STUB/filed")"
  out=$(eng 'mainred c3 "b.test: flaky" b.test '"$s"' && redissue '"$c"' | jq -r .title && locked pick "" "" "$(cat "$STUB/issues.json")"') || fail "the third case was not taken: $out"
  [ "$(head -n 1 <<<"$out")" = "Main is red: a.test: one, c.test, b.test: flaky" ] && [ "$(tail -n 1 <<<"$out" | cut -d' ' -f2)" = 7 ] \
    || fail "the third case on the same commit was not added to the running fix card, or a second card was started: $out"
  echo m > "$R/m.txt"; git -C "$R" add m.txt; git -C "$R" commit -qm "main moves, still red"; s2=$(git -C "$R" rev-parse HEAD)
  eng 'mainred c4 c.test c.test '"$s2" || fail "a case the open fix card holds was refused"
  [ "$(jq '.reds | length' "$ST/mainred.json")" = 1 ] || fail "a case the open fix card holds started a second one on a later commit: $(cat "$ST/mainred.json")"
  out=$(eng 'append "$(line '"$c"' 0 landed ok "{\"product\":true,\"sha\":\"'"$s2"'\"}")" && mainred c4 c.test c.test '"$s2"' && locked pick "" "" "$(cat "$STUB/issues.json")"') || fail "no card after the fix landed: $out"
  c2=${out%% *}
  [ "$c2" != "$c" ] && [ "$(st "select(.card == \"$c2\") | [.title, .mainRed] | tojson")" = "[\"Main is red: c.test\",\"$s2\"]" ] \
    || fail "a failure on a later commit after the fix landed did not start a new card: $out: $(cat "$ST/mainred.json")"
  [ ! -e "$STUB/filed" ] || fail "an issue was filed for main-red: $(cat "$STUB/filed")"
}

# Bug it catches (#1048): the case's file was looked for in the *.test.* files alone, so a case the runner run.mjs
# names as its own, defined in src/test-a.mjs (the pack's tests.patterns), went to main-red under run.mjs, a file no
# fix card could make pass.
t_mainredpatterns() {
  setup '[]'; tune '.tests.patterns = ["test-*.mjs"]'; mkdir -p "$R/src"
  echo "test('one', () => {});" > "$R/src/test-a.mjs"; echo "// runs src/" > "$R/run.mjs"
  git -C "$R" add src run.mjs && git -C "$R" commit -qm tests || fail "main's test files"
  eng 'mainred c1 "run.mjs: one" run.mjs '"$(git -C "$R" rev-parse HEAD)" || fail "mainred failed"
  [ "$(jq -c '.reds[0].cases[0].files' "$ST/mainred.json")" = '["src/test-a.mjs"]' ] || fail "the case's test-*.mjs file: $(cat "$ST/mainred.json")"
}

# Issue 618, by design and as docs/board.md and conveyor/README.md say: a main-red fix card is picked whatever the priority switches say.
# Bug it catches: a fix card held by `control rules P0=off` (it is labelled a P0 bug) left every card that meets the
# red main waiting for good. With P0 to P3 off, the P0 issue #7 is not picked, and the fix card still is.
t_mainredrules() {
  setup "[$(issue 7 2026-01-01 P0)]"
  local s out
  s=$(git -C "$R" rev-parse HEAD)
  loop control rules P0=off P1=off P2=off P3=off >/dev/null || fail "control rules P0=off ... P3=off was refused"
  out=$(eng 'locked pick "" "" "$(cat "$STUB/issues.json")"') && [ -z "$out" ] || fail "the switches off still picked #7: $out"
  out=$(eng 'mainred c1 "a.test: one" a.test '"$s"' && locked pick "" "" "$(cat "$STUB/issues.json")"') || fail "pick failed: $out"
  [[ $out == *-0\ 0\ false ]] && [ "$(st 'select(.step == "picked") | .issue')" = 0 ] \
    || fail "with P0 to P3 off the main-red fix card was not picked: $out: $(st '"\(.issue) \(.step)"' | tr '\n' ,)"
}

# Issue 597: the fix card on the belt and in Needs you, given back by its card id. Bugs it catches: the Board showed
# it under an issue number, or `retry` took only issue numbers, so a blocked fix card could not be given back. Shut by
# its card id, its commit starts no card again.
t_mainredretry() {
  setup "[$(issue 7 2026-01-01)]"
  local s out c c2
  s=$(git -C "$R" rev-parse HEAD)
  c=$(eng 'mainred c1 "a.test: one" a.test '"$s"' && mainred c1 c.test c.test '"$s"' && locked redpick') || fail "the fix card was not picked: $c"
  c=${c%% *}
  # A case found on that commit while the card runs is in its title on the Board, not only in its record (its picked
  # line's title names the cases it was picked with).
  eng 'mainred c2 "b.test: flaky" b.test '"$s" || fail "the third case was not taken"
  [ "$(loop snapshot --fresh | jq -c --arg c "$c" '.belt[] | select(.card == $c) | [.issue, .name, .title]')" = '[0,"Main is red ('"${s:0:12}"')","Main is red: a.test: one, c.test, b.test: flaky"]' ] \
    || fail "the snapshot does not show the fix card on the belt with no issue number, its name and every case: $(loop snapshot --fresh | jq -c .belt)"
  [ "$(loop cards | jq -c --arg c "$c" '.cards[] | select(.card == $c) | [.name, .title]')" = '["Main is red ('"${s:0:12}"')","Main is red: a.test: one, c.test, b.test: flaky"]' ] \
    || fail "\`cards\` does not name and title the fix card with every case: $(loop cards | jq -c .cards)"
  eng 'append "$(line '"$c"' 0 blocked ok "{\"reason\":\"build: it failed\"}")"' || fail "the blocked line was not written"
  eng 'declined '"$c"' 0 judge "out of scope" "[P2] a.txt:1 a nit"' || fail "the declined line was not written"
  out=$(loop snapshot --fresh) || fail "no snapshot"
  [ "$(jq -c --arg c "$c" '.needsYou.blocked[] | select(.card == $c) | [.issue, .name, .title]' <<<"$out")" = '[0,"Main is red ('"${s:0:12}"')","Main is red: a.test: one, c.test, b.test: flaky"]' ] \
    || fail "Needs you does not show the blocked fix card by its name: $(jq -c .needsYou <<<"$out")"
  # Issue 141: its declined line (issue 0) carries its name too, or the Board's Declined panel calls it "#0".
  [ "$(jq -c --arg c "$c" '.declined[] | select(.card == $c) | [.issue, .name]' <<<"$out")" = '[0,"Main is red ('"${s:0:12}"')"]' ] \
    || fail "the declined line of the fix card does not carry its name: $(jq -c .declined <<<"$out")"
  # Issue 141: health, which the Foreman's wakes and live summary read, names it too (they called it "#0"); `retry 0`
  # gave back every blocked fix card at once, and `control hold 0` said only its usage: each now says how to act on it.
  [ "$(loop health | jq -c --arg c "$c" '.blocked[] | select(.card == $c) | .name')" = '"Main is red ('"${s:0:12}"')"' ] \
    || fail "health does not name the blocked fix card: $(loop health | jq -c .blocked)"
  out=$(loop retry 0 2>&1) && fail "retry 0 exited 0: $out"
  grep -qF "retry <card id>" <<<"$out" && grep -qF "$c (Main is red (${s:0:12}))" <<<"$out" && [ -n "$(st "select(.card == \"$c\")")" ] \
    || fail "retry 0 did not say how to retry the blocked fix card, or gave it back: $out"
  for a in "hold 0" "release $c"; do
    out=$(loop control $a 2>&1) && fail "control $a exited 0: $out"
    grep -qF 'conveyor.sh retry <card id>' <<<"$out" || fail "control $a does not say how to act on a main-red fix card: $out"
  done
  out=$(loop retry "$c" 2>&1) && [ -z "$(st "select(.card == \"$c\")")" ] || fail "retry did not take the blocked fix card by its card id: $out"
  c2=$(eng 'locked redpick') && c2=${c2%% *} && [ -n "$c2" ] && [ "$c2" != "$c" ] && [ "$(st "select(.card == \"$c2\") | .mainRed")" = "$s" ] \
    || fail "the retried fix card was not picked again for main's commit: $c2: $(cat "$ST/mainred.json")"
  ! loop retry "c20260101T000000-x-0" > /dev/null 2>&1 || fail "retry took a card id that is no main-red fix card"
  eng 'append "$(line '"$c2"' 0 blocked ok "{\"reason\":\"build: it failed\"}")"' && out=$(loop shut "$c2" 2>&1) \
    && [ "$(st "select(.card == \"$c2\") | .step" | tail -n 1)" = closed ] || fail "shut did not close the blocked fix card by its card id: $out"
  [ -z "$(eng 'locked redpick')" ] || fail "a shut fix card's commit started a card again"
}

# Issue 597, the fix card's brief and landing commit, as card() makes them: it is built from its stand-in issue
# (mainred.sh redissue(): the cases, main's commit, the last commit of each case's file), redbrief() runs before each session and
# before the landing, and it lands under a commit naming the cases and main's commit (redmsg()). Bug it catches: a
# card of issue 0 with no branch had no issue to read (branchissue() wants a branch), or closed an issue on GitHub
# (a Closes line). A case found on main's commit during the review (as mainred.sh mainred() adds it) reaches the fix session
# straight after that review: the brief was read once, or only at the head of each round, so the fix session after
# the review that saw the case added never heard of it. Issue 615: a case with a test link that joins during the
# card's last test run lands its link; with no redbrief() before the landing, its link was never staged.
# Bug it catches too (#374): its runs of its cases write no log of their own, and each file run alone (filecmd()) gave
# no result for its named case, so the fix card was blocked; such a file's exit is the result of its cases (mainred.sh redrun()).
t_mainredland() {
  setup "[$(issue 7 2026-01-01)]"
  # The fixture ignores .conveyor/ (setup); a project tracks its links file, as this one does.
  printf 'conveyor/\n.conveyor/*\n!.conveyor/test-links.json\n' > "$R/.gitignore"; git -C "$R" commit -qam "track the test links"
  local s c out
  s=$(git -C "$R" rev-parse HEAD)
  c=$(eng 'mainred c1 "a.test: one" a.test '"$s"' && mainred c1 c.test c.test '"$s"' && locked redpick') && c=${c%% *} && [[ $c == *-0 ]] \
    && git -C "$R" worktree add -q --detach "$T/$CASE/cards/$c" || fail "the fix card was not picked: $c"
  # The briefs before the build, before the fix after the review that adds b.test's flaky, and before the landing
  # after d.test's one joined: each its own line of the output (as JSON). The message is made after the review, as
  # card() makes it, before the last test run.
  out=$(eng 'wt=$CONVEYOR_CARDS/'"$c"'; issue=$(redissue '"$c"') && sprompt=$(issuepart "$issue") || exit 1
    b() { redbrief '"$c"' 0 "" && jq -Rs . <<<"$sprompt"; }
    b && mainred c9 "b.test: flaky" b.test '"$s"' && b && redmsg '"$c"' "$issue" > "$STUB/msg" \
      && jq -c ".reds[0].cases += [{case: \"d.test: one\", file: \"d.test\", by: \"c9\", files: [], last: \"\", links: {\"lib/d.sh\": [\"tests/d.test.sh\"]}}]" "$MAINRED" > "$MAINRED.new" \
      && mv "$MAINRED.new" "$MAINRED" && b') || fail "the fix card's briefs could not be made: $out"
  [[ $(sed -n 1p <<<"$out" | jq -r .) == "# Issue #0: Main is red: a.test: one, c.test"$'\n\n'"These test cases fail on main at ${s:0:12}."*'- `a.test: one`, found by card c1.'* ]] \
    || fail "the build's brief is not the stand-in issue, naming main's commit and the cases: $(sed -n 1p <<<"$out")"
  sed -n 2p <<<"$out" | jq -r . | grep -qF -- '- `b.test: flaky`, found by card c9.' || fail "the fix session's brief lacks the case added during the review before it: $(sed -n 2p <<<"$out")"
  [ "$(cat "$STUB/msg")" = "fix(product): Main is red: a.test: one, c.test, b.test: flaky (main ${s:0:12})"$'\n\n'"Conveyor card $c" ] \
    || fail "the commit does not name the cases and main's commit: $(cat "$STUB/msg")"
  [ "$(git -C "$T/$CASE/cards/$c" show :.conveyor/test-links.json 2>&1 | jq -c . 2>&1)" = '{"a.txt":["a.test.sh"],"lib/d.sh":["tests/d.test.sh"]}' ] \
    && [ "$(git -C "$T/$CASE/cards/$c" diff --cached --name-only)" = .conveyor/test-links.json ] || fail "the link of the case that joined during the last test run is not staged to land: $(git -C "$T/$CASE/cards/$c" show :.conveyor/test-links.json 2>&1)"
  # The run of its cases: a command that writes no log and fails.
  echo 'exit 1' > "$STUB/test-cmd"
  out=$(eng 'redrun "$CONVEYOR_CARDS/'"$c"'" "$(jq -c "[.reds[0].cases[] | {name: .case, file, files, case: (.case | sub(\"^[^:]*(: |$)\"; \"\"))}]" "$MAINRED")" | jq -c "map(.verdict)"') \
    && [ "$out" = '["fail","fail","fail","fail"]' ] || fail "a run that writes no log did not give its exit as each case's result: $out"
  [ ! -e "$STUB/filed" ] && [ ! -e "$STUB/closed" ] && [ ! -e "$STUB/comments" ] || fail "main-red filed, closed or commented on an issue: $(cat "$STUB/filed" "$STUB/closed" "$STUB/comments" 2>&1)"
  loop check || fail "the record check refuses the fix card's picked line"
}

# R140 of #1393. Bug it catches: a line a test file printed itself (`✔ X (1ms)`, in the shape of node's passed-case line)
# was read as a pass of case X, which the file never ran, so the check of a main-red fix took the case as passing. Real
# node runs the file with the options the pack's runner gives it (NODETEST, .conveyor/test-changed.sh), which writes no
# case record: redrun() (mainred.sh), reading the run as the loop does, gives X none, Y, which ran, pass, and Z, whose
# failed assertion holds `✔ X (1ms)` in its expected value (TAP's YAML block of it), fail. The stand-in tests() is the
# run's command: its output and log are what testfails() reads.
t_redrunprinted() {
  local w=$T/$CASE/wt got
  mkdir -p "$T/$CASE"
  printf '%s\n' "import test from 'node:test';" "console.log('✔ X (1ms)'); console.log('ok 7 - X');" "import assert from 'node:assert';" "test('Y', () => {});" "test('Z', () => { assert.equal('other', '✔ X (1ms)\\nok 7 - X\\n'); });" > "$T/$CASE/f.test.mjs"
  got=$( cd "$T/$CASE" && eval "$(sed -n '/^redrun() {/,/^}/p' "$SRC/lib/mainred.sh"; sed -n '/^testfails() {/,/^}/p; /^RECJQ=/p' "$SRC/lib/testrun.sh"; sed -n '/^testlogs() {/,/^}/p' "$SRC/lib/session.sh"; sed -n '/^tapjq() {/p' "$SRC/lib/failat.sh")
      $(grep '^NODETEST=' "$SRC/../.conveyor/test-changed.sh")"
    packget() { return 1; }; export TEST_TIMEOUT=600
    tests() { # <worktree>
      mkdir -p "$1.testlog"
      { echo '== f.test.mjs'; "${NODETEST[@]}" f.test.mjs; } > "$1.test" 2>&1
      printf '%s\n' '== f.test.mjs' '-- FAIL f.test.mjs' > "$1.testlog/a.log"
    }
    redrun "$w" '[{"name": "X", "file": "f.test.mjs", "files": [], "case": "X"}, {"name": "Y", "file": "f.test.mjs", "files": [], "case": "Y"}, {"name": "Z", "file": "f.test.mjs", "files": [], "case": "Z"}]' | jq -c 'map(.verdict)' ) \
    || fail "redrun() did not run: $got"
  [ "$got" = '["none","pass","fail"]' ] || fail "a case the file printed as passed (or one a failed assertion's expected value holds a line of) was not none, or the case that ran was not its result: $got"
}
