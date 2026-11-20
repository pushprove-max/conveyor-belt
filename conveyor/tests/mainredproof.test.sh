#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a main-red fix card's check (redproof()), verdicts() on a card's own and main's failures, a fix card
# with no change, and a card that waits for main (mainwait()). Its cases call mainred.test.sh's eng().
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

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
# redsetup's fixture and run on main, with no entry in the main-red record. Run alone on a file (CONVEYOR_TEST_FILE,
# test.fileCommand), the runner runs that file's lines alone; a line naming no case runs the cases the file defines
# (its `t_<case>() {` lines), as a runner given a whole file does, or the file as one when it defines none.
redrunner() { # <ok.txt on main, or nothing>
  setup "[$(issue 7 2026-01-01)]"
  [ -z "$1" ] || { printf '%s\n' "$1" > "$R/ok.txt"; git -C "$R" add ok.txt; git -C "$R" commit -qm "ok.txt"; }
  printf '%s\n' 'cp "$CONVEYOR_TEST_RERUN" "$STUB/redlist"; L=$CONVEYOR_TEST_LOG/r; rc=0' \
    'while IFS=$'"'"'\t'"'"' read -r k f c; do' \
    '  [ "$k" = fail ] && { [ -z "${CONVEYOR_TEST_FILE:-}" ] || [ "$f" = "$CONVEYOR_TEST_FILE" ]; } || continue; echo "== $f" | tee -a "$L"' \
    '  cs=("$c"); [ -n "$c" ] || mapfile -t cs < <(sed -n "s/^t_\([a-z0-9_-]*\)() {.*/\1/p" "$f" 2>/dev/null); [ ${#cs[@]} != 0 ] || cs=(""); r=ok' \
    '  for c in "${cs[@]}"; do' \
    '    if grep -qx "${c:-$f}" ok.txt 2>/dev/null; then [ -z "$c" ] || echo "ok $c"' \
    '    elif [ -n "$c" ] && grep -qx "gone:$c" ok.txt 2>/dev/null; then :' \
    '    else echo "FAIL [${c:-$f}]: broken"; r=FAIL; rc=1; fi' \
    '  done; echo "-- $r $f" >> "$L"' \
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
  jq -e 'any(.[]; .case == "a.test: one" and .verdict == "main")' <<<"$out" >/dev/null && grep -qx $'fail\ta.test' "$STUB/redlist" \
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
# main runs a.test, whole, once, and each case is the card's.
t_mainredbigverdicts() {
  local w=$T/$CASE/cards/c7 out
  redrunner "$(for i in $(seq 300); do printf 'case-%03d-%0480d\n' "$i" 0; done)"
  sed 's/.*/t_&() { :; }/' "$R/ok.txt" > "$R/a.test" && git -C "$R" add a.test && git -C "$R" commit -qm a.test \
    && git -C "$R" worktree add -q --detach "$w" && echo '# a comment' >> "$w/a.test" && git -C "$w" add a.test || fail "the card's worktree could not be made"
  jq -cR '{name: ., line: 1}' "$R/ok.txt" | jq -cs '{files: [{file: "a.test", cases: .}]}' > "$STUB/fails"
  out=$(eng 'TEST_WAIT=; TEST_RUN=; TEST_FREE=; verdicts c7 "$CONVEYOR_CARDS/c7" "$(cat "$STUB/fails")" | jq -c "[(.verdicts | length), ([.verdicts[].verdict] | unique), (.mainRun | type)]"' 2>&1) \
    || fail "verdicts failed: ${out:0:300}"
  [ "$out" = '[300,["card"],"object"]' ] && [ "$(grep -c $'^fail\ta.test$' "$STUB/redlist")" = 1 ] \
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
