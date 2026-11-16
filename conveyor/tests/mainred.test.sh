#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a card's failing cases run on main before any fix session (verdicts()); main red makes the card wait.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"
# The engine folder, as lib.sh sets it: named here too, so the release closure (tools/closure.sh) follows this file's paths.
SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Bug it catches: #423 failed on a test main had broken since #442, and went to a fix round a session could not win.
# b.test's flaky fails on the card's run, its run again and on main: the card waits in its test step (no fix session,
# no block), the case goes to the fix card of main's commit, with no GitHub issue (#597), and its test line says so.
# b.test stands for a runner (the engine's conveyor/conveyor.test.sh names its cases' failures as its own): the fix
# card names the last commit of the file that defines the case, cases/b.test.sh, not that of the runner, changed
# later. Main moves and still fails it: the card tests again, waits again, and starts no second fix card while the
# first holds the case. Main moves again, now passing it: the card tests again, on main as it is now, and lands.
# Bug it catches too: a file that failed naming no case (a shell test's `FAIL: ...`) was given to main's run with no
# line, so main's clean tree ran nothing for it, the run passed and a file broken on main went to a fix session. c.test
# fails naming no case beside b.test's flaky, on every run until main is green: main's run is told to run it (a `fail`
# line with no case), runs it, and the file gets the verdict main and goes to the fix card too, so the card waits, not fixes.
# One card for both: a second card run cost this file about 40% of its CPU seconds (#467).
t_mainred() {
  rerunsetup '1 fail flaky' '1 bare three' '2 fail flaky' '2 bare three' '3 fail flaky' '3 bare three' '4 fail flaky' '4 bare three' \
    'main fail flaky' 'main bare three'
  local lp c b waiting='grep -qs "waiting for main to change: c.test, b.test: flaky fail on main" "$T/$CASE/cards/"*.live'
  mkdir -p "$R/cases"; echo 't_flaky() { :; }' > "$R/cases/b.test.sh"; git -C "$R" add cases; git -C "$R" commit -qm "the case's file"; b=$(git -C "$R" log -1 --format=%h)
  echo runner > "$R/b.test"; git -C "$R" add b.test; git -C "$R" commit -qm "the runner"
  ( loop run 1 > "$STUB/run.out" 2>&1 ) & lp=$!
  wait_until "$waiting" 'cat "$STUB/run.out"' || fail "the card did not wait for main: $(cat "$STUB/run.out")"
  c=$(st 'select(.step == "picked") | .card')
  [ "$(grep $'^fail\t' "$STUB/rerun.main" | tr '\t\n' ':|')" = "fail:c.test|fail:b.test:flaky|" ] && [ "$(ran main)" = "flaky three" ] \
    || fail "main's run was not told to run the failing case alone and the file that failed naming no case whole: $(ran main): $(cat "$STUB/rerun.main" 2>&1)"
  [ "$(tline 1 '[.result, .verdicts, .mainRun.sha] | tojson')" = "[\"fail\",[{\"case\":\"c.test\",\"verdict\":\"main\"},{\"case\":\"b.test: flaky\",\"verdict\":\"main\"}],\"$(git -C "$R" rev-parse HEAD)\"]" ] \
    || fail "the test line does not give the case's and the file's verdicts and main's run: $(tline 1 tojson)"
  tline 1 '.mainRun.sec' | grep -qE '^[0-9]+$' || fail "the test line does not give the seconds main's run took: $(tline 1 .mainRun)"
  # No GitHub issue (#597): the case and the file go to main's commit's one fix card, not picked in a `run 1`.
  [ ! -s "$STUB/filed" ] && [ "$(jq -c --arg s "$(git -C "$R" rev-parse HEAD)" '[.reds[] | [.sha == $s, .card, [.cases[].case]]]' "$ST/mainred.json")" = '[[true,null,["c.test","b.test: flaky"]]]' ] \
    || fail "the case and the file did not go to one fix card of main's commit, with no issue filed: $(cat "$ST/mainred.json" "$STUB/filed" 2>&1)"
  [ "$(jq -r '.reds[0].cases[] | select(.case == "b.test: flaky") | "\(.files) \(.last)"' "$ST/mainred.json")" = "[\"cases/b.test.sh\"] $b the case's file" ] \
    || fail "the fix card does not name the last commit of the case's file: $(cat "$ST/mainred.json")"
  [ "$(st 'select(.step == "fix" or .step == "blocked") | .step' | wc -l)" = 0 ] || fail "a red main sent the card to fix or blocked it: $(st '"\(.step) \(.result)"' | tr '\n' ,)"
  echo m > "$R/m.txt"; git -C "$R" add m.txt; git -C "$R" commit -qm "main moves, still red"
  wait_until "[ \"\$(st 'select(.step == \"test\" and .result == \"fail\") | .card' | wc -l)\" = 2 ] && $waiting" 'cat "$STUB/run.out"' \
    || fail "the card did not test again and wait once main moved: $(cat "$STUB/run.out")"
  # The same change on the new main: its passes stand, and what failed runs again (tests(), rerunsince()).
  [ "$(ran 3)" = "flaky three" ] && [ "$(git -C "$T/$CASE/cards/$c" log -1 --format=%s)" = "main moves, still red" ] \
    || fail "the run after main moved was not of the failing case and file, on main as it is now: $(ran 3)"
  [ "$(jq '.reds | length' "$ST/mainred.json")" = 1 ] && [ ! -s "$STUB/filed" ] \
    || fail "the new main commit started a second fix card for cases the first, not yet picked, holds: $(cat "$ST/mainred.json" "$STUB/filed" 2>&1)"
  sed -i '/^main /d' "$STUB/plan"
  echo n > "$R/n.txt"; git -C "$R" add n.txt; git -C "$R" commit -qm "main is green"
  wait "$lp" || fail "run exited non-zero: $(cat "$STUB/run.out")"
  [ "$(st 'select(.step == "test" or .step == "fix") | "\(.step) \(.result)"' | tr '\n' ,)" = "test fail,test fail,test pass," ] \
    || fail "not two waits on main and a pass once main was green: $(st 'select(.step == "test" or .step == "fix") | "\(.step) \(.result)"' | tr '\n' ,)"
  [ "$(st 'select(.step == "landed") | .card')" = "$c" ] || fail "the card did not land: $(st '"\(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  git -C "$R" show HEAD:n.txt > /dev/null 2>&1 || fail "the card did not land on main as it is now"
  [ ! -e "$T/$CASE/cards/mainrun/$c" ] || fail "main's worktree was left behind"
  loop check || fail "the record check refuses a test line with its verdicts"
  # The Board's Metrics count each failure by its verdict, and add up the seconds main's runs took: here 7 and 5 (the
  # stub's runs take under a second, so the lines are given those).
  jq -cn '[inputs] | (map(.step == "test" and .mainRun != null) | indices(true)) as $i | .[$i[0]].mainRun.sec = 7 | .[$i[1]].mainRun.sec = 5 | .[]' \
    "$ST/cards.jsonl" > "$STUB/cards.new" && mv "$STUB/cards.new" "$ST/cards.jsonl"
  [ "$(loop snapshot | jq -c '.metrics.today.testFailures')" = '{"card":0,"main":4,"flaky":0,"mainSec":12}' ] \
    || fail "the snapshot's metrics do not count the failures by verdict, with main's seconds: $(loop snapshot | jq -c '.metrics.today.testFailures')"
}

# Issue 582 (#530 tested three times on its old commit, through a fix round that changed nothing, and blocked): main
# fails b.test's flaky as the card is built on it (M1), and main fixes it (M2) during the card's run again, so main's
# run of the case passes and the failure is the card's. Bug it catches: the card went to a fix session and tested
# again on M1, without main's fix. It is brought onto M2 first, the failed case runs again there and passes: no fix.
t_mainfixed() {
  rerunsetup '1 fail flaky' '2 fail flaky'
  local m2
  echo '[ "$n" != 2 ] || { echo fixed > "$R/fix.txt"; git -C "$R" add fix.txt; git -C "$R" commit -qm "main fixes flaky"; git -C "$R" rev-parse HEAD > "$STUB/m2"; }
[ "$n" != 3 ] || git rev-parse HEAD > "$STUB/head.3"' > "$STUB/pre"
  loop run 1 > /dev/null || fail "run exited non-zero"
  m2=$(cat "$STUB/m2")
  [ "$(st 'select(.step == "test" or .step == "fix") | "\(.step) \(.result)"' | tr '\n' ,)" = "test fail,test pass," ] && [ "$(wc -l < "$STUB/sessions")" = 1 ] \
    || fail "the card did not test again on main before any fix session: $(st 'select(.step == "test" or .step == "fix") | "\(.step) \(.result)"' | tr '\n' ,)"
  [ "$(tline 1 '.verdicts | tojson')" = '[{"case":"b.test: flaky","verdict":"card"}]' ] || fail "the case did not pass on main's run: $(tline 1 tojson)"
  [ "$(ran 3)" = flaky ] && git -C "$R" merge-base --is-ancestor "$m2" "$(cat "$STUB/head.3")" \
    || fail "the failed case did not run again alone on a commit holding main's fix: $(ran 3) on $(cat "$STUB/head.3" 2>&1)"
  [ "$(st 'select(.step == "landed") | .issue')" = 7 ] || fail "the card did not land: $(st '"\(.step) \(.result)"' | tr '\n' ,)"
}

# Issue 582, after the landing's one rebuild (caught): #7 passes on M1, main changes its a.txt line (main1), so the
# landing rebuilds it there; its run after the rebuild (run 2: main's change selects a.test) and the run again (3)
# fail a.test's one, and main changes the same line again (main2), so the change no longer applies. Bug it catches:
# settle() put such a card back on its old commit, as after the rebuild, and run 4 ran there, without main's change.
# A session brings it onto main as it is now, and run 4 passes there.
caughtsetup() { # <plan lines>
  rerunsetup '2 fail one' '3 fail one' "$@"
  for i in 4 5; do echo "$GO" > "$STUB/review.$i"; done
  echo l1 > "$R/a.txt"; git -C "$R" add a.txt; git -C "$R" commit -qm "a.txt"
  echo "if grep -q '^# Main moved' \"\$STUB/brief\"; then sed -i 's/^main2\$/seven/' a.txt; elif grep -q '^# Landing conflict' \"\$STUB/brief\"; then sed -i 's/^main1\$/seven/' a.txt; else sed -i 's/^l1\$/seven/' a.txt; fi" > "$STUB/build"
  echo '[ "$n" != 1 ] || { echo main1 > "$R/a.txt"; git -C "$R" add a.txt; git -C "$R" commit -qm "main moves"; }
[ "$n" != 2 ] || [ ! -e "$STUB/move2" ] || { echo main2 > "$R/a.txt"; git -C "$R" add a.txt; git -C "$R" commit -qm "main moves again"; git -C "$R" rev-parse HEAD > "$STUB/m2"; }
[ "$n" != 4 ] || git rev-parse HEAD > "$STUB/head.4"' > "$STUB/pre"
}
caughtland() { # what the run after main's second move must show
  st 'select(.step == "rebase") | .reason' | grep -q '^rebase onto main conflicts' || fail "#7 did not go to the landing's rebuild: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
  git -C "$R" merge-base --is-ancestor "$(cat "$STUB/m2")" "$(cat "$STUB/head.4")" \
    || fail "the failed case ran again on the old commit, not on main as it is now: $(cat "$STUB/head.4" 2>&1)"
  [ "$(st 'select(.step == "fix") | .reason')" = "main moved since the card's change was made, and the change no longer applied to it" ] \
    || fail "not one session bringing the card onto main, and no fix round: $(st 'select(.step == "fix") | .reason')"
  [ "$(st 'select(.step == "landed") | .issue')" = 7 ] && grep -qx seven "$R/a.txt" || fail "#7 did not land: $(st '"\(.step) \(.result)"' | tr '\n' ,)"
}
# Main moved during the run (its run of the case passes: the failure is the card's).
t_mainfixedcaught() {
  caughtsetup; : > "$STUB/move2"
  loop run 1 > /dev/null || fail "run exited non-zero"
  caughtland
}
# Main fails the case too: the card waits for main to change, and main changes the same line.
t_mainredcaught() {
  caughtsetup 'main fail one'
  local lp
  ( loop run 1 > "$STUB/run.out" 2>&1 ) & lp=$!
  wait_until 'grep -qs "waiting for main to change" "$T/$CASE/cards/"*.live' 'cat "$STUB/run.out"' || fail "the card did not wait for main: $(cat "$STUB/run.out")"
  sed -i '/^main /d' "$STUB/plan"
  echo main2 > "$R/a.txt"; git -C "$R" add a.txt; git -C "$R" commit -qm "main moves again"; git -C "$R" rev-parse HEAD > "$STUB/m2"
  wait "$lp" || fail "run exited non-zero: $(cat "$STUB/run.out")"
  caughtland
}

# Issue 598. Bug it catches: a landing broke a test its card did not run, and nothing linked the test to the files it
# changed, so later cards changing them did not run it either. In a fixture repo, landing L1's card ran
# tests/b.test.sh; landing A changes lib/a.sh and its card does not run it; landing C after it changes lib/c.sh. b.test
# fails on main: the case's entry in the main-red record (mainred()) names landing A, not C, and the fix card's
# worktree (testlinks()) holds .conveyor/test-links.json linking lib/a.sh, and only it, to tests/b.test.sh, staged to
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
  got=$( cd "$r" && eval "$(sed -n '/^mainred() {/,/^}/p; /^brokeby() {/,/^}/p; /^testlinks() {/,/^}/p; /^TESTLINK_DEPTH=/p' "$SRC/lib/testrun.sh")"
    stdb() { cat "$w/cards.jsonl"; }
    export MAINRED=$w/mainred.json
    # The loop's redpick() names the fix card in the entry; here the record is given it.
    mainred c9 "tests/b.test.sh: one" tests/b.test.sh "$h" && jq -c '.reds[0].card = "cfix"' "$MAINRED" > "$MAINRED.new" && mv "$MAINRED.new" "$MAINRED" \
      && testlinks cfix "$w/fix" && echo ok ) || fail "mainred or testlinks failed: $got"
  [ "$(jq -c '.reds[0].cases[0] | [.landing, .links]' "$w/mainred.json")" = "[{\"sha\":\"$a\",\"card\":\"ca\",\"issue\":2},{\"lib/a.sh\":[\"tests/b.test.sh\"]}]" ] \
    || fail "D1: the main-red record does not name landing A and its link: $(cat "$w/mainred.json" 2>&1)"
  [ "$(jq -c . "$w/fix/.conveyor/test-links.json")" = '{"lib/a.sh":["tests/b.test.sh"]}' ] \
    && [ "$(git -C "$w/fix" diff --cached --name-only)" = .conveyor/test-links.json ] \
    || fail "D1: the fix card's worktree does not stage the link of lib/a.sh to tests/b.test.sh: $(cat "$w/fix/.conveyor/test-links.json" 2>&1)"
}
# Issue 615. Bug it catches: card() staged the test links only as the fix card started, so a case that joined it later
# (mainred()) changed its brief but its links never landed. The fix card's entry gains a case linking lib/d.sh to
# tests/d.test.sh after its start; the next redbrief() before a session stages that link beside the first one.
t_mainredjoin() {
  local w=$T/$CASE got
  mkdir -p "$w/fix/.conveyor"; git -C "$w/fix" init -q
  echo '{"lib/a.sh":["tests/b.test.sh"]}' > "$w/fix/.conveyor/test-links.json"
  jq -n '{reds: [{sha: "s", card: "cfix", cases: [{case: "b", links: {"lib/a.sh": ["tests/b.test.sh"]}}, {case: "d", links: {"lib/d.sh": ["tests/d.test.sh"]}}]}]}' > "$w/mainred.json"
  got=$( eval "$(sed -n '/^redbrief() {/,/^}/p' "$SRC/lib/card.sh"; sed -n '/^testlinks() {/,/^}/p' "$SRC/lib/testrun.sh")"
    # shellcheck disable=SC2034 # wt is read by redbrief(), run by the eval
    MAINRED=$w/mainred.json wt=$w/fix issue='{"title":"Main is red: b"}' sprompt='brief b'
    redissue() { echo '{"title":"Main is red: b, d"}'; }; issuepart() { echo "brief ${1:23:-2}"; }
    redbrief cfix 0 "" && echo "$issue|$sprompt" ) || fail "redbrief failed: $got"
  [ "$got" = '{"title":"Main is red: b, d"}|brief b, d' ] || fail "the brief does not name the case that joined: $got"
  [ "$(jq -c . "$w/fix/.conveyor/test-links.json")" = '{"lib/a.sh":["tests/b.test.sh"],"lib/d.sh":["tests/d.test.sh"]}' ] \
    && [ "$(git -C "$w/fix" diff --cached --name-only)" = .conveyor/test-links.json ] \
    || fail "the link of the case that joined is not staged: $(cat "$w/fix/.conveyor/test-links.json" 2>&1)"
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
  got=$( cd "$r" && eval "$(sed -n '/^mainred() {/,/^}/p; /^brokeby() {/,/^}/p; /^TESTLINK_DEPTH=/p' "$SRC/lib/testrun.sh")"
    stdb() { cat "$w/cards.jsonl"; }
    export MAINRED=$w/mainred.json
    mainred c9 "r.test.sh: one" r.test.sh "$h" && echo ok ) || fail "mainred failed: $got"
  [ "$(jq -c '.reds[0].cases[0] | [.landing, .links]' "$w/mainred.json")" = "[{\"sha\":\"$a\",\"card\":\"ca\",\"issue\":2},{\"lib/a.sh\":[\"tests/b.test.sh\"]}]" ] \
    || fail "a run of only some cases of the file did not count, or one without the case did: $(cat "$w/mainred.json" 2>&1)"
}

# The engine's own functions, sourced as `run` sources them, in main's checkout: what a card's verdicts() and the
# loop's pick call, without a card run (#597's cases call mainred() and pick() themselves).
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
  [ "$(loop snapshot | jq -c --arg c "$c" '.belt[] | select(.card == $c) | [.issue, .name, .title]')" = '[0,"Main is red ('"${s:0:12}"')","Main is red: a.test: one, c.test, b.test: flaky"]' ] \
    || fail "the snapshot does not show the fix card on the belt with no issue number, its name and every case: $(loop snapshot | jq -c .belt)"
  [ "$(loop cards | jq -c --arg c "$c" '.cards[] | select(.card == $c) | [.name, .title]')" = '["Main is red ('"${s:0:12}"')","Main is red: a.test: one, c.test, b.test: flaky"]' ] \
    || fail "\`cards\` does not name and title the fix card with every case: $(loop cards | jq -c .cards)"
  eng 'append "$(line '"$c"' 0 blocked ok "{\"reason\":\"build: it failed\"}")"' || fail "the blocked line was not written"
  eng 'declined '"$c"' 0 judge "out of scope" "[P2] a.txt:1 a nit"' || fail "the declined line was not written"
  out=$(loop snapshot) || fail "no snapshot"
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

# Issue 597, the fix card's whole run: it is picked ahead of #7, built from its stand-in issue (the cases, main's
# commit, the last commit of each case's file) and lands under a commit naming the cases and main's commit. Bug it
# catches: a card of issue 0 with no branch had no issue to read (branchissue() wants a branch), or closed and
# commented on an issue on GitHub. A case found on main's commit during the review (as mainred() adds it) reaches the
# fix session straight after that review: the brief was read once, or only at the head of each round, so the fix
# session after the review that saw the case added never heard of it. Issue 615: a case with a test link that joins
# during the card's last test run lands its link; with no redbrief() before the landing, its link was never staged.
t_mainredland() {
  setup "[$(issue 7 2026-01-01)]"
  printf '%s\n' $'[P1] a.txt:1 wrong word\nUSER-VISIBLE: no\nVERDICT: NO-GO' > "$STUB/review.1"; echo "$GO" > "$STUB/review.2"
  provenbug # labelled as a P0 bug: the bug-card check holds it
  echo "grep -qs flaky '$ST/mainred.json' || { jq -c '.reds[0].cases += [{case: \"b.test: flaky\", file: \"b.test\", by: \"c9\", files: [], last: \"\"}]' '$ST/mainred.json' > '$STUB/red.new' && mv '$STUB/red.new' '$ST/mainred.json'; }" > "$STUB/review-cmd"
  # Issue 615: a case with a link joins during the card's last test run, after every session, review and settle().
  # The fixture ignores .conveyor/ (setup); a project tracks its links file, as this one does.
  printf 'conveyor/\n.conveyor/*\n!.conveyor/test-links.json\n' > "$R/.gitignore"; git -C "$R" commit -qam "track the test links"
  echo "echo x >> '$STUB/tests'; grep -qs d.sh '$ST/mainred.json' || { jq -c '.reds[0].cases += [{case: \"d.test: one\", file: \"d.test\", by: \"c9\", files: [], last: \"\", links: {\"lib/d.sh\": [\"tests/d.test.sh\"]}}]' '$ST/mainred.json' > '$STUB/red.new' && mv '$STUB/red.new' '$ST/mainred.json'; }" > "$STUB/test-cmd"
  local s c
  s=$(git -C "$R" rev-parse HEAD)
  eng 'mainred c1 "a.test: one" a.test '"$s"' && mainred c1 c.test c.test '"$s" || fail "the cases were not recorded"
  loop run 1 > "$STUB/run.out" 2>&1 || fail "run exited non-zero: $(cat "$STUB/run.out")"
  c=$(st 'select(.step == "landed") | .card')
  [[ $c == *-0 ]] && [ "$(st 'select(.step == "picked") | .issue')" = 0 ] || fail "the fix card did not land ahead of #7: $(st '"\(.issue) \(.step) \(.reason)"' | tr '\n' ,)"
  [ "$(wc -l < "$STUB/sessions")" = 2 ] && grep -qF "These test cases fail on main at ${s:0:12}" "$STUB/brief" && grep -qF -- '- `a.test: one`, found by card c1.' "$STUB/brief" \
    || fail "the brief does not name main's commit and the cases"
  grep -qF -- '- `b.test: flaky`, found by card c9.' "$STUB/brief" || fail "the fix session's brief lacks the case added during the review before it"
  [ "$(git -C "$R" log -1 --format=%B)" = "fix(product): Main is red: a.test: one, c.test, b.test: flaky (main ${s:0:12})"$'\n\n'"Conveyor card $c" ] \
    || fail "the commit does not name the cases and main's commit: $(git -C "$R" log -1 --format=%B)"
  [ "$(git -C "$R" show HEAD:.conveyor/test-links.json 2>&1 | jq -c . 2>&1)" = '{"lib/d.sh":["tests/d.test.sh"]}' ] \
    || fail "the link of the case that joined during the last test run did not land: $(git -C "$R" show HEAD:.conveyor/test-links.json 2>&1)"
  [ ! -e "$STUB/filed" ] && [ ! -e "$STUB/closed" ] && [ ! -e "$STUB/comments" ] || fail "main-red filed, closed or commented on an issue: $(cat "$STUB/filed" "$STUB/closed" "$STUB/comments" 2>&1)"
  loop check || fail "the record check refuses the fix card's picked line"
}
