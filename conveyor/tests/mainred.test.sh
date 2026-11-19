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
  local -x WHOLESUITE=true # The old fixture: main's run is test.command's, given the failing cases alone (verdicts()), not each file whole.
  rerunsetup '1 fail flaky' '1 bare three' '2 fail flaky' '2 bare three' '3 fail flaky' '3 bare three' '4 fail flaky' '4 bare three' \
    'main fail flaky' 'main bare three'
  local lp c b waiting='grep -qs "waiting for main to change: c.test, b.test: flaky fail on main" "$T/$CASE/cards/"*.live'
  mkdir -p "$R/cases"; echo 't_flaky() { :; }' > "$R/cases/b.test.sh"; git -C "$R" add cases; git -C "$R" commit -qm "the case's file"; b=$(git -C "$R" log -1 --format=%h)
  echo runner > "$R/b.test"; git -C "$R" add b.test; git -C "$R" commit -qm "the runner"
  ( loop run 1 > "$STUB/run.out" 2>&1 ) & lp=$!
  wait_until "$waiting" 'cat "$STUB/run.out"' || fail "the card did not wait for main: $(cat "$STUB/run.out")"
  c=$(st 'select(.step == "picked") | .card')
  # Issue 201: while it only waits for main, its wait mark stands, so the loop counts it against no build slot (idle()).
  wait_until "[ -e '$T/$CASE/cards/$c.idle' ]" || fail "the card waiting for main did not mark itself waiting: the loop would count it against the cap"
  # Issue 220: the snapshot gives when the wait for main began (the belt's live.at), which the Foreman's watcher
  # times its wake from; without it the wait never wakes the Foreman.
  [ "$(loop snapshot --fresh 2>/dev/null | jq -r --arg c "$c" '.belt[] | select(.card == $c) | .live.at')" = "$(jq -r .at "$T/$CASE/cards/$c.live")" ] \
    || fail "the snapshot does not give when the wait for main began: $(loop snapshot --fresh 2>/dev/null | jq -c --arg c "$c" '.belt[] | select(.card == $c) | .live')"
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
  [ "$(loop snapshot --fresh | jq -c '.metrics.today.testFailures')" = '{"card":0,"main":4,"flaky":0,"mainSec":12}' ] \
    || fail "the snapshot's metrics do not count the failures by verdict, with main's seconds: $(loop snapshot --fresh | jq -c '.metrics.today.testFailures')"
}

# Issue 582 (#530 tested three times on its old commit, through a fix round that changed nothing, and blocked): main
# fails b.test's flaky as the card is built on it (M1), and main fixes it (M2) during the card's run again, so main's
# run of the case passes and the failure is the card's. Bug it catches: the card went to a fix session and tested
# again on M1, without main's fix. It is brought onto M2 first, the failed case runs again there and passes: no fix.
t_mainfixed() {
  local -x WHOLESUITE=true # The old fixture: main's run is test.command's, given the failing case alone (verdicts()), not its file whole.
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
  local -x WHOLESUITE=true # The old fixture: #7 lands on a main that changed a.txt too.
  caughtsetup; : > "$STUB/move2"
  loop run 1 > /dev/null || fail "run exited non-zero"
  caughtland
}
# Main fails the case too: the card waits for main to change, and main changes the same line. Its landed line's
# waitSec counts that wait (at least the 1 s slept here). Bug it catches: the drift watch (bench/drift.sh) had no
# minutes a card waited for main, as no line recorded them.
t_mainredcaught() {
  local -x WHOLESUITE=true # The old fixture: main's run is test.command's, given the failing case alone (verdicts()), not its file whole.
  caughtsetup 'main fail one'
  local lp
  ( loop run 1 > "$STUB/run.out" 2>&1 ) & lp=$!
  wait_until 'grep -qs "waiting for main to change" "$T/$CASE/cards/"*.live' 'cat "$STUB/run.out"' || fail "the card did not wait for main: $(cat "$STUB/run.out")"
  sleep 1 # sleep: the card waits for main a whole second at least, so its waitSec is 1 or more
  sed -i '/^main /d' "$STUB/plan"
  echo main2 > "$R/a.txt"; git -C "$R" add a.txt; git -C "$R" commit -qm "main moves again"; git -C "$R" rev-parse HEAD > "$STUB/m2"
  wait "$lp" || fail "run exited non-zero: $(cat "$STUB/run.out")"
  caughtland
  [ "$(st 'select(.step == "landed") | .waitSec >= 1')" = true ] || fail "the landed line does not count the wait for main: $(st 'select(.step == "landed") | .waitSec')"
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
  got=$( cd "$r" && eval "$(sed -n '/^mainred() {/,/^}/p; /^brokeby() {/,/^}/p; /^landingof() {/,/^}/p; /^testlinks() {/,/^}/p; /^TESTLINK_DEPTH=/p' "$SRC/lib/testrun.sh")"
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
# Issue 323: linksonly() after a main-fix card's session, which left its staged .conveyor/test-links.json in the
# worktree as a symlink to a file outside it, then .conveyor itself as a symlink to a folder outside it. Bug it
# catches: linksonly() wrote main's copy of the links through the symlink, so the session made the engine overwrite a
# file outside the worktree. The outside files keep their text; the links still count as the card's only change.
t_mainredlinksonlylink() {
  local w=$T/$CASE got
  mkdir -p "$w/fix/.conveyor" "$w/out/.conveyor"; git -C "$w/fix" init -q
  echo '{}' > "$w/fix/.conveyor/test-links.json"; git -C "$w/fix" add -A; git -C "$w/fix" commit -qm links
  echo keep > "$w/out/file"; echo keep > "$w/out/.conveyor/test-links.json"
  jq -n '{reds: [{sha: "s", card: "cfix", cases: [{case: "b", links: {"lib/a.sh": ["tests/b.test.sh"]}}]}]}' > "$w/mainred.json"
  got=$( eval "$(sed -n '/^testlinks() {/,/^}/p; /^linksonly() {/,/^}/p' "$SRC/lib/testrun.sh")"
    MAINRED=$w/mainred.json
    testlinks cfix "$w/fix" && ln -sf "$w/out/file" "$w/fix/.conveyor/test-links.json" || exit 1
    linksonly cfix "$w/fix" && echo only
    rm -rf "$w/fix/.conveyor" && ln -s "$w/out/.conveyor" "$w/fix/.conveyor" || exit 1
    linksonly cfix "$w/fix" && echo dironly; : ) || fail "the fixture failed: $got"
  [ "$got" = only ] && [ "$(cat "$w/out/file")" = keep ] && [ "$(cat "$w/out/.conveyor/test-links.json")" = keep ] \
    || fail "linksonly() wrote through a symlink the session left, or took a symlinked .conveyor: $got: $(cat "$w/out/file" "$w/out/.conveyor/test-links.json")"
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
  got=$( cd "$r" && eval "$(sed -n '/^mainred() {/,/^}/p; /^brokeby() {/,/^}/p; /^landingof() {/,/^}/p; /^TESTLINK_DEPTH=/p' "$SRC/lib/testrun.sh")"
    stdb() { cat "$w/cards.jsonl"; }
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
# run on main (redrun()), whose result names tests/b.test.sh, gave no verdict for it.
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
  got=$( cd "$r" && eval "$(sed -n '/^mainred() {/,/^}/p; /^redopen() {/,/^}/p; /^brokeby() {/,/^}/p; /^landingof() {/,/^}/p; /^redrun() {/,/^}/p; /^TESTLINK_DEPTH=/p' "$SRC/lib/testrun.sh")"
    stdb() { cat "$w/cards.jsonl"; }
    tests() { :; }; testlogs() { echo log; }; testfails() { echo '{"files": [{"file": "tests/b.test.sh", "cases": [{"name": "one"}]}]}'; }
    export MAINRED=$w/mainred.json
    mainred c9 "tests/b.test.sh: one" tests/b.test.sh "$h" && brokeby tests/b.test.sh "$h" tests/b.test.sh one | jq -r .sha \
      && redrun "$w/wt" "$(jq -c '[.reds[0].cases[0] | {name: .case, file, files, case: "one"}]' "$MAINRED")" | jq -r '.[0].verdict' ) || fail "mainred failed: $got"
  [ "$(jq -c '[.reds[] | .sha]' "$w/mainred.json")" = '["0ld"]' ] || fail "the open fix card's entry named under the runner did not hold the case: $(cat "$w/mainred.json")"
  [ "$got" = "$a"$'\n'fail ] || fail "the landing that broke it, or the old entry's verdict on main, was not found: '$got'"
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
  # No stub a.test.sh on main: main's run (`bash a.test.sh`) must fail there, or the card closes as already done.
  git -C "$R" rm -q a.test.sh && git -C "$R" commit -qm "no a.test.sh" || fail "main's a.test.sh could not be removed"
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
  [ "$(git -C "$R" show HEAD:.conveyor/test-links.json 2>&1 | jq -c . 2>&1)" = '{"a.txt":["a.test.sh"],"lib/d.sh":["tests/d.test.sh"]}' ] \
    || fail "the link of the case that joined during the last test run did not land: $(git -C "$R" show HEAD:.conveyor/test-links.json 2>&1)"
  [ ! -e "$STUB/filed" ] && [ ! -e "$STUB/closed" ] && [ ! -e "$STUB/comments" ] || fail "main-red filed, closed or commented on an issue: $(cat "$STUB/filed" "$STUB/closed" "$STUB/comments" 2>&1)"
  loop check || fail "the record check refuses the fix card's picked line"
}

# Issue 181: the bug-card check of a main-red fix card (redproof()) is main's own failing cases, not new tests. The
# fixture's cases: `a.test: one` and the file c.test, failing naming no case; each passes when ok.txt holds its name
# (`one`, `c.test`), a named case printing `ok <case>`; `gone:one` in ok.txt makes the case not run (as when the change
# renames it) and its file pass. The run on main is a runner that logs each file a `fail` line of its list names, as the test step's
# runner does, and keeps that list in $STUB/redlist. The fix card's entry holds both cases.
redsetup() { # <ok.txt on main, or nothing>
  redrunner "$1"
  local s; s=$(git -C "$R" rev-parse HEAD)
  eng 'mainred c1 "a.test: one" a.test '"$s"' && mainred c1 c.test c.test '"$s" || fail "the cases were not recorded"
}
# redsetup's fixture and run on main, with no entry in the main-red record.
redrunner() { # <ok.txt on main, or nothing>
  setup "[$(issue 7 2026-01-01)]"
  [ -z "$1" ] || { printf '%s\n' "$1" > "$R/ok.txt"; git -C "$R" add ok.txt; git -C "$R" commit -qm "ok.txt"; }
  printf '%s\n' 'cp "$CONVEYOR_TEST_RERUN" "$STUB/redlist"; L=$CONVEYOR_TEST_LOG/r; rc=0' \
    'while IFS=$'"'"'\t'"'"' read -r k f c; do' \
    '  [ "$k" = fail ] || continue; echo "== $f" | tee -a "$L"' \
    '  if grep -qx "${c:-$f}" ok.txt 2>/dev/null; then [ -z "$c" ] || echo "ok $c"; echo "-- ok $f" >> "$L"' \
    '  elif [ -n "$c" ] && grep -qx "gone:$c" ok.txt 2>/dev/null; then echo "-- ok $f" >> "$L"' \
    '  else echo "FAIL [${c:-$f}]: broken"; echo "-- FAIL $f" >> "$L"; rc=1; fi' \
    'done < "$CONVEYOR_TEST_RERUN"' 'exit $rc' > "$STUB/mainrun-cmd"
}
# The check alone (bugproof(), which calls redproof()) on a fix card cfix whose worktree holds <ok.txt> staged: its
# exit and the first line of its result.
redcheck() { # <ok.txt in the change>
  local w=$T/$CASE/cards/cfix
  jq -c '.reds[0].card = "cfix"' "$ST/mainred.json" > "$STUB/red.new" && mv "$STUB/red.new" "$ST/mainred.json"
  git -C "$R" worktree add -q --detach "$w" HEAD && printf '%s\n' "$1" > "$w/ok.txt" && git -C "$w" add ok.txt || fail "the fix card's worktree could not be made"
  eng 'bugproof cfix '"$w"' "$(redissue cfix)"; echo "exit $?"; head -n 1 '"$w"'.unfixed'
}
# Bug it catches: a right fix for a red main that adds no test (here, a fixture fix) was blocked: "the new tests pass
# without the fix, so they do not prove it". Each case runs alone, as the test step runs it, fails without the change
# and passes with it: the check holds.
t_redproofnotest() {
  redsetup ''
  local got; got=$(redcheck $'one\nc.test')
  [ "$(head -n 1 <<<"$got")" = "exit 0" ] && [[ $(tail -n 1 <<<"$got") == "Each case main fails at "*" fails there without the change and passes with it: \`a.test: one\`, \`c.test\`." ]] \
    || fail "a red-main fix that adds no test did not pass the check: $got"
  [ "$(cat "$STUB/redlist")" = $'fail\ta.test\tone\nfail\tc.test' ] || fail "the cases were not run alone, each a fail line of the list: $(cat "$STUB/redlist")"
}
# Bug it catches: a red-main fix that leaves a case failing passed the check, or was blocked without naming the case.
t_redproofstill() {
  redsetup ''
  local got; got=$(redcheck one)
  [ "$(head -n 1 <<<"$got")" = "exit 2" ] && [ "$(tail -n 1 <<<"$got")" = '`c.test` still fails with the change.' ] \
    || fail "a change that leaves c.test failing was not blocked naming it: $got"
}
# Bug it catches: a fix card whose cases pass on main without its change (main is no longer red for them) landed a
# change that proves nothing, or was blocked. Its whole run: it closes as already done, its closed line naming the
# cases and carrying its wait (waitSec, which the drift watch's mean wait reads), and nothing lands.
t_redproofgreen() {
  redsetup $'one\nc.test'
  local s c; s=$(git -C "$R" rev-parse HEAD)
  loop run 1 > "$STUB/run.out" 2>&1 || fail "run exited non-zero: $(cat "$STUB/run.out")"
  c=$(st 'select(.step == "closed") | .card')
  [[ $c == *-0 ]] && [ "$(st 'select(.step == "closed") | .reason')" = 'Main is no longer red for `a.test: one`, `c.test`: they pass on main'"'"'s code at '"$s"' without the change, so the card closes as already done.' ] \
    || fail "the fix card did not close as already done, naming the cases: $(st '"\(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  [ "$(st 'select(.step == "closed") | .waitSec | type')" = number ] || fail "the closed line does not carry the card's wait: $(st 'select(.step == "closed")')"
  [ -z "$(st 'select(.step == "landed" or .step == "blocked")')" ] && [ "$(git -C "$R" rev-parse HEAD)" = "$s" ] && [ ! -e "$T/$CASE/cards/$c" ] \
    || fail "the fix card landed, was blocked or left its worktree: $(st '"\(.step) \(.result)"' | tr '\n' ,)"
  loop check || fail "the record check refuses the closed line"
}

# Issue 323: verdicts() alone on card c7, its worktree on main with a new test file n.test staged and a comment added
# to a.test, its last run failing a.test's one and n.test's two and running out of time in c.test. On main a.test's one
# fails and c.test passes (ok.txt). One run on main, three verdicts:
# - n.test: two, the card's own new file. Bug it catches: main's run was told to run n.test, which main lacks, its
#   failure there marked main red, and the main-fix card found nothing to fix.
# - c.test, a time-out that passes on main: the card's.
# - a.test: one, a real failure on main: main's, and the only case in the main-red record. Bug it catches: a file the
#   card only edits was taken for its own, so a case failing on main too never ran there and went to the card.
t_mainredowncard() {
  local -x WHOLESUITE=true # The old fixture: main's run is test.command's, given the failing cases alone (verdicts()), not each file whole.
  redrunner c.test
  local w=$T/$CASE/cards/c7 out
  echo 't_one() { false; }' > "$R/a.test" && git -C "$R" add a.test && git -C "$R" commit -qm a.test \
    && git -C "$R" worktree add -q --detach "$w" && echo 't_two() { false; }' > "$w/n.test" && echo '# a comment' >> "$w/a.test" \
    && git -C "$w" add n.test a.test || fail "the card's worktree could not be made"
  out=$(eng 'TEST_WAIT=; TEST_RUN=; TEST_FREE=; verdicts c7 "$CONVEYOR_CARDS/c7" '"'"'{"files":[{"file":"a.test","cases":[{"name":"one","line":1}]},{"file":"n.test","cases":[{"name":"two","line":1}]}],"timeout":{"sec":1,"file":"c.test"}}'"'"' | jq -c .verdicts') \
    || fail "verdicts failed: $out"
  jq -e 'any(.[]; .case == "n.test: two" and .verdict == "card")' <<<"$out" >/dev/null && ! grep -q $'^fail\tn.test' "$STUB/redlist" \
    || fail "the failure of the card's own new test file ran on main or was not the card's: $out: $(cat "$STUB/redlist")"
  jq -e 'any(.[]; .case == "c.test" and .verdict == "card")' <<<"$out" >/dev/null || fail "a time-out that passes on main was not the card's: $out"
  jq -e 'any(.[]; .case == "a.test: one" and .verdict == "main")' <<<"$out" >/dev/null && grep -qx $'fail\ta.test\tone' "$STUB/redlist" \
    || fail "a case that fails on main, in a file the card edits, did not run there or was not main's: $out: $(cat "$STUB/redlist")"
  [ "$(jq -c '[.reds[].cases[].case]' "$ST/mainred.json")" = '["a.test: one"]' ] \
    || fail "the main-red record does not hold only the case that fails on main: $(cat "$ST/mainred.json" 2>&1)"
}

# #367. Bug it catches: a document on a card's run (tests/speed/page.md, on main too) "failed" there and on main, so
# main was marked red for it and the main-fix card could never make it pass. Its failure is the card's, a selection
# error, it does not run on main, and the main-red record is not written.
t_mainreddoc() {
  redrunner ''
  local w=$T/$CASE/cards/c7 out
  mkdir -p "$R/tests/speed" && echo '# A page' > "$R/tests/speed/page.md" && git -C "$R" add tests && git -C "$R" commit -qm page \
    && git -C "$R" worktree add -q --detach "$w" || fail "the card's worktree could not be made"
  out=$(eng 'TEST_WAIT=; TEST_RUN=; TEST_FREE=; verdicts c7 "$CONVEYOR_CARDS/c7" '"'"'{"files":[{"file":"tests/speed/page.md","cases":[]}]}'"'"' | jq -c .verdicts') \
    || fail "verdicts failed: $out"
  [ "$out" = '[{"case":"tests/speed/page.md","verdict":"card","why":"no test file: a selection error"}]' ] \
    || fail "the document's failure is not the card's selection error: $out"
  [ ! -e "$STUB/redlist" ] && [ ! -e "$ST/mainred.json" ] || fail "the document ran on main or went to the main-red record: $(cat "$STUB/redlist" "$ST/mainred.json" 2>&1)"
  # mainred() takes no document either; an entry an older engine made for a document alone goes at the next pick, so
  # the cards that wait on it run again and no fix card starts for it.
  jq -cn '{reds: [{sha: "1111111111111111111111111111111111111111", cases: [{case: "tests/speed/page.md", file: "tests/speed/page.md", by: "c1", files: [], last: ""}], card: null}]}' > "$ST/mainred.json"
  out=$(eng '! mainred c7 tests/speed/page.md tests/speed/page.md 2222222222222222222222222222222222222222 2>/dev/null && locked redpick') || fail "mainred took a document, or redpick failed: $out"
  [ -z "$out" ] && [ "$(jq -c . "$ST/mainred.json")" = '{"reds":[]}' ] || fail "the document's entry was kept or picked: $out $(cat "$ST/mainred.json")"
}

# Bug it catches (#344): verdicts() gave the failed cases and their verdicts to jq as arguments, which Linux refuses
# over 128 KiB ("Argument list too long"): with many failures, they did not run on main and the card lost every
# verdict. Card c7's last run fails 300 cases of a.test, each with a long name (about 150 KB); all pass on main, so
# main runs them and each is the card's.
t_mainredbigverdicts() {
  local -x WHOLESUITE=true # The old fixture: main's run is test.command's, given the failing cases alone (verdicts()), not each file whole.
  local w=$T/$CASE/cards/c7 out
  redrunner "$(for i in $(seq 300); do printf 'case-%03d-%0480d\n' "$i" 0; done)"
  echo 't_one() { false; }' > "$R/a.test" && git -C "$R" add a.test && git -C "$R" commit -qm a.test \
    && git -C "$R" worktree add -q --detach "$w" && echo '# a comment' >> "$w/a.test" && git -C "$w" add a.test || fail "the card's worktree could not be made"
  jq -cR '{name: ., line: 1}' "$R/ok.txt" | jq -cs '{files: [{file: "a.test", cases: .}]}' > "$STUB/fails"
  out=$(eng 'TEST_WAIT=; TEST_RUN=; TEST_FREE=; verdicts c7 "$CONVEYOR_CARDS/c7" "$(cat "$STUB/fails")" | jq -c "[(.verdicts | length), ([.verdicts[].verdict] | unique), (.mainRun | type)]"' 2>&1) \
    || fail "verdicts failed: ${out:0:300}"
  [ "$out" = '[300,["card"],"object"]' ] && [ "$(grep -c $'^fail\ta.test\t' "$STUB/redlist")" = 300 ] \
    || fail "the many failures did not run on main or lost their verdicts: ${out:0:300}"
}

# Issue 323: a main-fix card's whole run, its session making no change, and main now passing its cases. Its entry links
# lib/x.sh to a.test, so the engine stages .conveyor/test-links.json in its worktree before the build. Bug it catches:
# the card was blocked ("the session made no change, so there is nothing to review"), or the staged links were taken
# for a change and went to review, and main stayed marked red. Its cases run again on main as it is now; they pass, so
# the card closes as not needed, saying so, nothing lands, and its entry holds main red no more (redopen()).
t_mainrednochange() {
  redsetup $'one\nc.test'
  local s c out
  # The fixture ignores .conveyor/; a project tracks its links file, so the engine can stage it.
  printf 'conveyor/\n.conveyor/*\n!.conveyor/test-links.json\n' > "$R/.gitignore" && echo '{}' > "$R/.conveyor/test-links.json" \
    && git -C "$R" add .gitignore .conveyor/test-links.json && git -C "$R" commit -qm links || fail "the links file could not be committed"
  s=$(git -C "$R" rev-parse HEAD)
  jq -c '.reds[0].cases[0].links = {"lib/x.sh": ["a.test"]}' "$ST/mainred.json" > "$STUB/red.new" && mv "$STUB/red.new" "$ST/mainred.json"
  echo ':' > "$STUB/build"
  loop run 1 > "$STUB/run.out" 2>&1 || fail "run exited non-zero: $(cat "$STUB/run.out")"
  c=$(st 'select(.step == "picked") | .card')
  [ "$(st 'select(.step == "closed") | .reason')" = 'Not needed: the session made no change, and the cases ran again on main. Main is no longer red for `a.test: one`, `c.test`: they pass on main'"'"'s code at '"$s"' without the change, so the card closes as already done.' ] \
    || fail "the fix card with no change did not close as not needed: $(st '"\(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  out=$(eng "redopen $c && echo open")
  [ -z "$(st 'select(.step | IN("blocked", "landed", "review"))')" ] && [[ $out != *open* ]] && [ "$(git -C "$R" rev-parse HEAD)" = "$s" ] && [ ! -e "$T/$CASE/cards/$c" ] \
    || fail "the fix card was blocked, reviewed or landed, its entry still holds main red, or its worktree stayed: $out: $(st '"\(.step) \(.result)"' | tr '\n' ,)"
  recok "$ST/cards.jsonl" "the fix card with no change"
}

# Issue 323: nochange() alone on main-fix card cfix, its session making no change and ending with an ALREADY-DONE line,
# while its cases still fail on main. Bug it catches: the card went to the ALREADY-DONE review, whose GO closed it with
# main still red. It is blocked, naming the run on main, with no review.
t_mainrednochangered() {
  redsetup ''
  local w=$T/$CASE/cards/cfix out
  jq -c '.reds[0].card = "cfix"' "$ST/mainred.json" > "$STUB/red.new" && mv "$STUB/red.new" "$ST/mainred.json"
  git -C "$R" worktree add -q --detach "$w" HEAD && echo '{"type":"result","result":"ALREADY-DONE: main fixes it"}' > "$w.out" \
    || fail "the fix card's worktree could not be made"
  out=$(eng 'nochange cfix 0 "$CONVEYOR_CARDS/cfix" brief' 2>&1)
  [[ $(st 'select(.card == "cfix" and .step == "blocked") | .reason') == "the session made no change, so there is nothing to review. Its cases on main as it is now: "*'`a.test: one`, `c.test` still fails on main'"'"'s code at '*', and there is no change to run them with. Its session'"'"'s output and errors are kept in kept/cfix/. Its last reply: ALREADY-DONE: main fixes it' ]] \
    && [ -z "$(st 'select(.card == "cfix" and (.step | IN("closed", "review", "start")))')" ] \
    || fail "the fix card whose cases still fail on main was not blocked naming the run, or went to review: $out: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
}

# Issue 358: mainwait() alone, card c9 waiting on `a.test: one` at main's commit, its live record checked every LIVE
# (2) seconds. The case's entry (redsetup's, which holds c.test too, its fix card not picked) is of main's commit
# before, as mainred() leaves a case failing at a later commit with that entry: a wait that looked only at main's
# commit's entry never saw it go. Sets s, main's commit, and mw, the waiting process; its output goes to $STUB/mw.out.
mwstart() {
  redsetup ''
  git -C "$R" commit -q --allow-empty -m "main moves, still red"
  s=$(git -C "$R" rev-parse HEAD); mkdir -p "$T/$CASE/cards"
  ( eng 'LIVE=2; mainwait "$CONVEYOR_CARDS/c9" '"$s"' "a.test: one"; echo "ended $?"' > "$STUB/mw.out" 2>&1 ) & mw=$!
  wait_until "grep -qs 'waiting for main to change: a.test: one fail on main at ${s:0:12} too' '$T/$CASE/cards/c9.live'" 'cat "$STUB/mw.out"' \
    || fail "the card did not wait for main, saying on what"
}
# Bug it catches: the owner removed a wrong main-red entry with main unchanged, and the card waited on until the loop
# was stopped. The case leaves the record (c.test, which the card does not wait on, stays): the wait ends within one
# LIVE interval (the ceiling: LIVE and a second's slack), and the card goes on to test again (card()).
t_mainwaitcleared() {
  local s mw
  mwstart
  jq -c '.reds[0].cases |= map(select(.case != "a.test: one"))' "$ST/mainred.json" > "$STUB/red.new" && mv "$STUB/red.new" "$ST/mainred.json"
  WAIT_CEILING=3 wait_until "grep -qx 'ended 0' '$STUB/mw.out'" 'cat "$STUB/mw.out"' || fail "the wait did not end once its case left the main-red record"
  wait "$mw"; [ ! -e "$T/$CASE/cards/c9.live" ] && [ ! -e "$T/$CASE/cards/c9.idle" ] || fail "the ended wait left its live record or wait mark"
}
# Bug it catches: the case's fix card closed as already done (its cases pass on main: bugproof(), nochange()) with main
# unchanged, its entry left in the record, and the card waited on. Picked, the fix card holds the wait; closed, it ends
# within one LIVE interval.
t_mainwaitfixclosed() {
  local s mw l
  mwstart
  jq -c '.reds[0].card = "cfix"' "$ST/mainred.json" > "$STUB/red.new" && mv "$STUB/red.new" "$ST/mainred.json"
  l=$(jq -r .last "$T/$CASE/cards/c9.live")
  wait_until "[ \"\$(jq -r .last '$T/$CASE/cards/c9.live' 2>/dev/null)\" != '$l' ]" || fail "the waiting card's live record was not brought up to date"
  [ -z "$(cat "$STUB/mw.out")" ] || fail "the wait ended while the case's fix card was open: $(cat "$STUB/mw.out")"
  eng 'append "$(line cfix 0 closed ok "{\"reason\":\"already done\"}")"' || fail "the fix card's closed line could not be written"
  WAIT_CEILING=3 wait_until "grep -qx 'ended 0' '$STUB/mw.out'" 'cat "$STUB/mw.out"' || fail "the wait did not end once the case's fix card closed"
  wait "$mw"
}
# Bug it catches: a wait that ended on its own with main still red and its entry standing (the card tested again for
# nothing, every LIVE). The live record is brought up to date, so the wait has checked again, and it still waits;
# then main moves, which ends it.
t_mainwaitstays() {
  local s mw l
  mwstart
  l=$(jq -r .last "$T/$CASE/cards/c9.live")
  wait_until "[ \"\$(jq -r .last '$T/$CASE/cards/c9.live' 2>/dev/null)\" != '$l' ]" || fail "the waiting card's live record was not brought up to date"
  [ -z "$(cat "$STUB/mw.out")" ] && [ -e "$T/$CASE/cards/c9.live" ] || fail "the wait ended with its entry standing and main unchanged: $(cat "$STUB/mw.out")"
  echo m > "$R/m.txt"; git -C "$R" add m.txt; git -C "$R" commit -qm "main moves"
  wait_until "grep -qx 'ended 0' '$STUB/mw.out'" 'cat "$STUB/mw.out"' || fail "the wait did not end once main moved"
  wait "$mw"
}
