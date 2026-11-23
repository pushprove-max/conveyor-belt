#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: a main-red fix card's check (bugproof.sh redproof()), mainred.sh verdicts() on a card's own and main's failures, a fix card
# with no change, and a card that waits for main (mainred.sh mainwait()). Its cases call mainred.test.sh's eng().
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# Issue 181: the bug-card check of a main-red fix card (bugproof.sh redproof()) is main's own failing cases, not new tests. The
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
# The check alone (bugproof.sh bugproof(), which calls redproof()) on a fix card cfix whose worktree holds <ok.txt> staged: its
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
# The real test file conveyor/foreman/foreman-title.test.sh, run as the test step runs a case of it (its case `startup`, by
# CONVEYOR_SHELL_TEST_CASE) in the fixture of redrunner(): no stub of its output, which is what the proof reads. The run passes
# when ok.txt in the change holds `fixed`; else it runs with a jq that always fails, as a broken fix would leave it. The entry
# holds its case `title-startup`, named as the file's FAIL line names it.
redforeman() {
  redrunner ''
  mkdir -p "$STUB/nojq"; printf '#!/bin/sh\nexit 1\n' > "$STUB/nojq/jq"; chmod +x "$STUB/nojq/jq"
  printf '%s\n' 'cp "$CONVEYOR_TEST_RERUN" "$STUB/redlist"; L=$CONVEYOR_TEST_LOG/r; rc=0' \
    'while IFS=$'"'"'\t'"'"' read -r k f c; do' \
    '  [ "$k" = fail ] && [ "$f" = foreman-title.test.sh ] || continue; echo "== $f" | tee -a "$L"' \
    '  P=$PATH; grep -qx fixed ok.txt 2>/dev/null || P=$STUB/nojq:$PATH' \
    "  if PATH=\$P CONVEYOR_SHELL_TEST_CASE=startup bash $SRC/foreman/foreman-title.test.sh; then r=ok; else r=FAIL; rc=1; fi" \
    '  echo "-- $r $f" >> "$L"' 'done < "$CONVEYOR_TEST_RERUN"' 'exit $rc' > "$STUB/mainrun-cmd"
  eng 'mainred c1 "foreman-title.test.sh: title-startup" foreman-title.test.sh '"$(git -C "$R" rev-parse HEAD)" || fail "the case was not recorded"
}
# Bug it catches (#1525): a fix of a case of a Foreman test file was blocked with "gave no result": the file printed one
# `ok [title]` line when all its cases passed, so the run with the change named no passed case. Each file now prints `ok <case>`.
t_redproofforeman() {
  redforeman
  local got; got=$(redcheck fixed)
  [ "$(head -n 1 <<<"$got")" = "exit 0" ] && [[ $(tail -n 1 <<<"$got") == "Each case main fails at "*"passes with it: \`foreman-title.test.sh: title-startup\`."* ]] \
    || fail "a fix that made the Foreman test file pass its case title-startup (ok.txt held 'fixed') did not pass the check: $got"
}
# Bug it catches (#1525): the reading of a Foreman file's pass must not turn a case that still fails with the change into a pass.
t_redproofforemanstill() {
  redforeman
  local got; got=$(redcheck broken)
  [ "$(head -n 1 <<<"$got")" = "exit 2" ] && [[ $(tail -n 1 <<<"$got") == *"still fails with the change."* ]] \
    || fail "a change that leaves the Foreman test file's case title-startup failing (ok.txt held 'broken') was not blocked as still failing: $got"
}
# card.sh cardbuild() on fix card cfix's fixture state, as card() takes it (its locals; waitsec, the card's wait), with
# a stand-in build session (session(): it notes each call in $STUB/sessions and fails, so the card ends there). Prints
# cardbuild()'s output.
redbuild() {
  local w=$T/$CASE/cards/cfix
  jq -c '.reds[0].card = "cfix"' "$ST/mainred.json" > "$STUB/red.new" && mv "$STUB/red.new" "$ST/mainred.json"
  git -C "$R" worktree add -q --detach "$w" HEAD || fail "the fix card's worktree could not be made"
  eng 'session() { echo x >> "$STUB/sessions"; return 1; }
    c=cfix n=0 br="" mode="" wt=$CONVEYOR_CARDS/cfix sprompt=brief sf="" waitsec=4 mainsec=0 go=end; issue=$(redissue cfix) && cardbuild; echo "go $go"' 2>&1
}
# Bug it catches: a fix card whose cases pass on main (main is no longer red for them) ran a build session first, and only
# then closed as already done: 16 cards in 300 spent 3,799 build seconds and $14.67 on it. cardbuild() closes it before
# any session starts (bugproof.sh redgreen()), its closed line naming the cases and the runs, and carrying its wait (waitSec,
# which the drift watch's mean wait reads), its worktree gone, and nothing lands.
t_redproofgreen() {
  redsetup $'one\nc.test'
  local s w=$T/$CASE/cards/cfix out; s=$(git -C "$R" rev-parse HEAD); out=$(redbuild)
  [ "$(tail -n 1 <<<"$out")" = "go end" ] && [ "$(st 'select(.step == "closed") | .reason')" = 'Main is no longer red for `a.test: one`, `c.test`: they pass on main'"'"'s code at '"$s"' without the change in each of 3 runs, so the card closes as already done.' ] \
    || fail "the fix card did not close as already done, naming the cases: $out: $(st '"\(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  [ ! -e "$STUB/sessions" ] && [ -z "$(st 'select(.step == "start" and .of == "build")')" ] || fail "a build session started for a card whose cases pass on main: $(cat "$STUB/sessions")"
  [ "$(st 'select(.step == "closed") | .waitSec == 4')" = true ] || fail "the closed line does not carry the card's wait as the number 4: $(st 'select(.step == "closed")')"
  [ -z "$(st 'select(.step == "landed" or .step == "blocked")')" ] && [ "$(git -C "$R" rev-parse HEAD)" = "$s" ] && [ ! -e "$w" ] \
    || fail "the fix card landed, was blocked or left its worktree: $out: $(st '"\(.step) \(.result)"' | tr '\n' ,)"
  recok "$ST/cards.jsonl" "the fix card's close"
}
# Bug it catches: the check before the build session closed a card whose cases still fail on main, so a red main got no
# fix. With a case failing on main (ok.txt lacks `c.test`) the card is not closed and the build session starts, once.
t_redgreenfails() {
  redsetup 'one'
  local out; out=$(redbuild)
  [ "$(wc -l < "$STUB/sessions" 2>/dev/null)" = 1 ] && [ -z "$(st 'select(.step == "closed")')" ] \
    || fail "the build session did not start once, or the card closed, with c.test failing on main: $out: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
}
# Bug it catches: a case that fails one run in three (flaky) was closed as passing because the check ran it once. Main's
# runner here fails `one` in its second run only (the file n counts the runs): the check runs all of the flaky rule's runs
# up to that failure, does not close the card, and the build session starts.
t_redgreenflaky() {
  redsetup $'one\nc.test'
  local out
  # A run is one call of the runner for each file (a.test, c.test): the count is of a.test's calls.
  printf '%s\n' '[ "${CONVEYOR_TEST_FILE:-}" = a.test ] && { n=$(($(cat "$STUB/n" 2>/dev/null || echo 0) + 1)); echo $n > "$STUB/n"; [ $n != 2 ] || { grep -vx one ok.txt > ok.new; mv ok.new ok.txt; }; }' \
    | cat - "$STUB/mainrun-cmd" > "$STUB/mainrun-cmd.new" && mv "$STUB/mainrun-cmd.new" "$STUB/mainrun-cmd" || fail "the flaky runner could not be made"
  out=$(redbuild)
  [ "$(cat "$STUB/n")" = 2 ] && [ "$(wc -l < "$STUB/sessions" 2>/dev/null)" = 1 ] && [ -z "$(st 'select(.step == "closed")')" ] \
    || fail "the card whose case failed in its second run was closed, or the check stopped early or ran past it (runs: $(cat "$STUB/n")): $out: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
}

# Issue 323: mainred.sh verdicts() alone on card c7, its worktree on main with a new test file n.test staged and a comment added
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
  # mainred.sh mainred() takes no document either; an entry an older engine made for a document alone goes at the next pick, so
  # the cards that wait on it run again and no fix card starts for it.
  jq -cn '{reds: [{sha: "1111111111111111111111111111111111111111", cases: [{case: "tests/speed/page.md", file: "tests/speed/page.md", by: "c1", files: [], last: ""}], card: null}]}' > "$ST/mainred.json"
  out=$(eng '! mainred c7 tests/speed/page.md tests/speed/page.md 2222222222222222222222222222222222222222 2>/dev/null && locked redpick') || fail "mainred took a document, or redpick failed: $out"
  [ -z "$out" ] && [ "$(jq -c . "$ST/mainred.json")" = '{"reds":[]}' ] || fail "the document's entry was kept or picked: $out $(cat "$ST/mainred.json")"
}

# Bug it catches (#344): mainred.sh verdicts() gave the failed cases and their verdicts to jq as arguments, which Linux refuses
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

# Issue 323: a main-fix card cfix's review step on fixture state, as cardreview() takes it: its session made no change,
# and main now passes its cases. Its entry links lib/x.sh to a.test, so the engine stages .conveyor/test-links.json in
# its worktree (card.sh redbrief()). Bug it catches: the card was blocked ("the session made no change, so there is
# nothing to review"), or the staged links were taken for a change and went to review, and main stayed marked red.
# The links alone are no change (card.sh emptychange() exit 0, the worktree reset), so nochange() runs its cases again
# on main as it is now; they pass, so the card closes as not needed, saying so, nothing lands, and its entry holds main
# red no more (mainred.sh redopen()).
t_mainrednochange() {
  redsetup $'one\nc.test'
  local s w=$T/$CASE/cards/cfix out
  # The fixture ignores .conveyor/; a project tracks its links file, so the engine can stage it.
  printf 'conveyor/\n.conveyor/*\n!.conveyor/test-links.json\n' > "$R/.gitignore" && echo '{}' > "$R/.conveyor/test-links.json" \
    && git -C "$R" add .gitignore .conveyor/test-links.json && git -C "$R" commit -qm links || fail "the links file could not be committed"
  s=$(git -C "$R" rev-parse HEAD)
  jq -c '.reds[0].cases[0].links = {"lib/x.sh": ["a.test"]} | .reds[0].card = "cfix"' "$ST/mainred.json" > "$STUB/red.new" && mv "$STUB/red.new" "$ST/mainred.json"
  git -C "$R" worktree add -q --detach "$w" HEAD || fail "the fix card's worktree could not be made"
  out=$(eng 'wt=$CONVEYOR_CARDS/cfix issue="" sprompt=""; redbrief cfix 0 "" && echo "staged $(git -C "$wt" diff --cached --name-only)"
    emptychange cfix 0 "$wt" ""; echo "empty $?"; nochange cfix 0 "$wt" brief' 2>&1)
  [[ $out == "staged .conveyor/test-links.json"$'\n'"empty 0"* ]] || fail "the fix card's staged links alone were not taken for no change (emptychange() exit 0): $out"
  [ "$(st 'select(.step == "closed") | .reason')" = 'Not needed: the session made no change, and its cases were checked again on main. Main is no longer red for `a.test: one`, `c.test`: they pass on main'"'"'s code at '"$s"' without the change, so the card closes as already done.' ] \
    || fail "the fix card with no change did not close as not needed: $out: $(st '"\(.step) \(.result) \(.reason)"' | tr '\n' ,)"
  out=$(eng "redopen cfix && echo open")
  [ -z "$(st 'select(.step | IN("blocked", "landed", "review"))')" ] && [[ $out != *open* ]] && [ "$(git -C "$R" rev-parse HEAD)" = "$s" ] && [ ! -e "$w" ] \
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

# R86: nochange() alone on main-fix card cfix, its session making no change, its cases passing on main; while they run
# (redrun(), wrapped), mainred() adds the case `b.test: two` to its entry. Bug it catches: redproof() read the entry's
# cases once and the closed line was written anyway, so the added case, never run, was held red by the entry no more
# (redlisted()). The card is blocked naming the added case, not closed, and its entry still holds main red.
t_mainredjoinrun() {
  redsetup $'one\nc.test'
  local s w=$T/$CASE/cards/cfix out
  s=$(git -C "$R" rev-parse HEAD)
  jq -c '.reds[0].card = "cfix"' "$ST/mainred.json" > "$STUB/red.new" && mv "$STUB/red.new" "$ST/mainred.json"
  git -C "$R" worktree add -q --detach "$w" HEAD || fail "the fix card's worktree could not be made"
  out=$(eng 'eval "real$(declare -f redrun)"; redrun() { realredrun "$@"; mainred c9 "b.test: two" b.test '"$s"' > /dev/null 2>&1; }
    nochange cfix 0 "$CONVEYOR_CARDS/cfix" brief; redopen cfix && echo open' 2>&1)
  # The blocked reason quotes the run's result without its "so the card closes as already done": the card stayed open.
  [[ $(st 'select(.card == "cfix" and .step == "blocked") | .reason') == *'without the change. The card was not closed: a case joined its entry in the main-red record while its cases ran, and did not run: `b.test: two`.'* ]] \
    && [ -z "$(st 'select(.card == "cfix" and .step == "closed")')" ] && [[ $out == *open* ]] \
    || fail "the fix card closed as already done though a case joined its entry while its cases ran, or its blocked reason said it closes: $out: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
}

# R86, card.sh greenclose() on fix card cfix whose check before the build (redgreen()) found its cases passing, while
# redclosed() refuses the closed line (stubbed: a case joined). Bug it catches: the blocked reason quoted the result
# "..., so the card closes as already done." and then said the card was not closed. It drops that clause.
t_mainredgreenjoin() {
  setup "[$(issue 7 2026-01-01)]"
  local w=$T/$CASE/cards/cfix
  mkdir -p "$w" && echo 'Main is no longer red for `c.test`: they pass on main'"'"'s code at s1 in each of 3 runs, so the card closes as already done.' > "$w.unfixed" \
    || fail "the fixture could not be made"
  eng 'redclosed() { echo "The card was not closed: a case joined."; return 1; }; greenclose cfix 0 "$CONVEYOR_CARDS/cfix"' > /dev/null 2>&1
  # block() adds a note after it: the fixture's card folder is no git worktree, so no patch is kept.
  [[ $(st 'select(.card == "cfix" and .step == "blocked") | .reason') == 'build: Main is no longer red for `c.test`: they pass on main'"'"'s code at s1 in each of 3 runs. The card was not closed: a case joined.'* ]] \
    || fail "greenclose() given a refused closed line did not block cfix with the result less its closing clause: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
}

# #1275: a pack that sets no test.fileCommand, its test command `PACK_LOADER=1 node --test` given a file as test.list
# <form> says. Main's p.test.js loads only with PACK_LOADER set (as a TypeScript file loads only through its project's
# loader): it passes under the pack's command, and fails to load under Conveyor's own runner (lib/filerun.sh: plain
# node --test), as it failed on the card's run. Sets s, main's commit.
packred() { # <test.list: args, or "" for none>
  setup "[$(issue 7 2026-01-01)]"
  echo '{"name": "p", "private": true}' > "$R/package.json"
  printf '%s\n' "if (!process.env.PACK_LOADER) throw new Error('Cannot find module ./gone: loaded without the pack loader');" \
    "require('node:test')('loads', () => {});" > "$R/p.test.js"
  git -C "$R" add package.json p.test.js && git -C "$R" commit -qm p.test.js || fail "main's p.test.js could not be committed"
  tune --arg l "$1" 'del(.test.fileCommand) | .test.command = "PACK_LOADER=1 node --test" | if $l == "" then del(.test.list) else .test.list = $l end'
  s=$(git -C "$R" rev-parse HEAD)
}
# verdicts() on card c7, whose last run failed p.test.js as node --test names a file that fails to load: a case named
# after the file.
packverdicts() {
  git -C "$R" worktree add -q --detach "$T/$CASE/cards/c7" || fail "the card's worktree could not be made"
  eng 'TEST_WAIT=; TEST_RUN=; TEST_FREE=; verdicts c7 "$CONVEYOR_CARDS/c7" '"'"'{"files":[{"file":"p.test.js","cases":[{"name":"p.test.js","line":1}]}]}'"'"' | jq -c "[.verdicts, .mainRun.exit]"' 2>"$STUB/verdicts.err"
}
# Bug it catches: the check on main ran the file with Conveyor's own runner, where it fails to load, not with the
# pack's test command, where it passes: main was marked red and its fix card blocked ("still fails on main"). The run
# on main passes (exit 0), the failure is the card's, and the main-red record is not written.
t_mainredpackcmd() {
  local out s
  packred args
  out=$(packverdicts) || fail "verdicts failed: $out $(cat "$STUB/verdicts.err")"
  [ "$out" = '[[{"case":"p.test.js: p.test.js","verdict":"card"}],0]' ] && [ ! -e "$ST/mainred.json" ] \
    || fail "verdicts on p.test.js failing to load on the card (a file that passes under the pack's command) did not run it the pack's way, or marked main red: $out $(cat "$ST/mainred.json" 2>&1)"
}
# Bug it catches: a pack whose test command cannot be given one file (no test.list: the pack the bug was found on) ran
# the file on main with Conveyor's own runner and marked main red for a file that fails only there. Nothing runs on
# main, the output says why, and the failure is the card's.
t_mainrednolist() {
  local out s
  packred ''
  out=$(packverdicts) || fail "verdicts failed: $out $(cat "$STUB/verdicts.err")"
  [ "$(jq -c '.[0]' <<<"$out")" = '[{"case":"p.test.js: p.test.js","verdict":"card"}]' ] && [ ! -e "$ST/mainred.json" ] \
    && grep -q 'card c7: its failing cases did not run on main: .*test.list is not set' "$STUB/verdicts.err" \
    || fail "verdicts on p.test.js with no test.list ran it on main another way, marked main red or did not say why: $out $(cat "$STUB/verdicts.err" "$ST/mainred.json" 2>&1)"
}
# Bug it catches: a test command that takes the file in place of `{files}` (test.list placeholder) or in
# CONVEYOR_TEST_FILES (env) got it some other way on main, or got the path filecmd() adds after the command too.
# testlist.sh nofilecmd() alone, on a check of main (TEST_PACKONLY), its command run as filecmd() runs it, on a
# path with a space.
t_mainredpackforms() {
  local got
  setup "[$(issue 7 2026-01-01)]"
  tune 'del(.test.fileCommand) | .test.list = "placeholder" | .test.command = "printf \"[%s]\" {files} > \"$STUB/got\""'
  got=$(eng 'c=$(TEST_PACKONLY=1 nofilecmd "$PWD" "a b.test.js") && CONVEYOR_TEST_FILE="a b.test.js" bash -c "$c"'"'"' "$CONVEYOR_TEST_FILE"'"'"' && cat "$STUB/got"' 2>&1)
  [ "$got" = '[a b.test.js]' ] || fail "test.list placeholder, command 'printf \"[%s]\" {files}', file 'a b.test.js': the command got $got"
  tune '.test.list = "env" | .test.command = "printf \"[%s]\" \"$CONVEYOR_TEST_FILES\" > \"$STUB/got\""'
  got=$(eng 'c=$(TEST_PACKONLY=1 nofilecmd "$PWD" "a b.test.js") && CONVEYOR_TEST_FILE="a b.test.js" bash -c "$c"'"'"' "$CONVEYOR_TEST_FILE"'"'"' && cat "$STUB/got"' 2>&1)
  [ "$got" = '[a b.test.js]' ] || fail "test.list env, command 'printf \"[%s]\" \"\$CONVEYOR_TEST_FILES\"', file 'a b.test.js': the command got $got"
}
# Bug it catches: main's fix card for p.test.js, its session making no change, ran the file on main with Conveyor's own
# runner and was blocked ("still fails on main's code"), though the file passes there under the pack's command. Its
# cases run the pack's way: they pass, so the card closes as not needed (#323), and is not blocked.
t_mainredpacknochange() {
  local out s
  packred args
  packnochange
  [[ $(st 'select(.card == "cfix" and .step == "closed") | .reason') == 'Not needed: the session made no change, and its cases were checked again on main. Main is no longer red for `p.test.js: p.test.js`: '* ]] \
    && [ -z "$(st 'select(.card == "cfix" and .step == "blocked")')" ] \
    || fail "main's fix card with no change, for p.test.js (which passes under the pack's command), did not close as not needed: $out: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
}
# Main's fix card cfix for p.test.js (packred()'s commit s, the case recorded red by c1), its session making no change:
# nochange() on it. Sets out, its output.
packnochange() {
  eng 'mainred c1 "p.test.js: p.test.js" p.test.js '"$s" || fail "p.test.js was not recorded"
  jq -c '.reds[0].card = "cfix"' "$ST/mainred.json" > "$STUB/red.new" && mv "$STUB/red.new" "$ST/mainred.json" \
    && git -C "$R" worktree add -q --detach "$T/$CASE/cards/cfix" HEAD || fail "the fix card's worktree could not be made"
  out=$(eng 'nochange cfix 0 "$CONVEYOR_CARDS/cfix" brief' 2>&1)
}
# Bug it catches: on a pack whose test command cannot be given one file (no test.list, no test.fileCommand: the pack
# the bug was found on), main's fix card with no change skipped its run on main, gave its case no result and was
# blocked. Nothing shows main red the pack's way, so the card closes as not needed, saying why, and is not blocked.
t_mainrednolistnochange() {
  local out s
  packred ''
  packnochange
  [[ $(st 'select(.card == "cfix" and .step == "closed") | .reason') == 'Not needed: the session made no change, and its cases were checked again on main. Main is not red for `p.test.js: p.test.js` the pack'"'"'s way: '*'test.list is not set'*'so the card closes as already done.' ]] \
    && [ -z "$(st 'select(.card == "cfix" and .step == "blocked")')" ] \
    || fail "main's fix card with no change, for p.test.js on a pack with no test.list or test.fileCommand, did not close as not needed naming why: $out: $(st '"\(.step) \(.reason)"' | tr '\n' ,)"
}

# Issue 358: mainred.sh mainwait() alone, card c9 waiting on `a.test: one` at main's commit, its live record checked every LIVE
# (2) seconds. The case's entry (redsetup's, which holds c.test too, its fix card not picked) is of main's commit
# before, as mainred.sh mainred() leaves a case failing at a later commit with that entry: a wait that looked only at main's
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
# Bug it catches: the case's fix card closed as already done (its cases pass on main: bugproof.sh bugproof(), nochange()) with main
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
# then main moves to a commit that passes the case, which ends it.
t_mainwaitstays() {
  local s mw l
  mwstart
  l=$(jq -r .last "$T/$CASE/cards/c9.live")
  wait_until "[ \"\$(jq -r .last '$T/$CASE/cards/c9.live' 2>/dev/null)\" != '$l' ]" || fail "the waiting card's live record was not brought up to date"
  [ -z "$(cat "$STUB/mw.out")" ] && [ -e "$T/$CASE/cards/c9.live" ] || fail "the wait ended with its entry standing and main unchanged: $(cat "$STUB/mw.out")"
  echo 't_one() { :; }' > "$R/a.test"; echo one > "$R/ok.txt"; git -C "$R" add a.test ok.txt; git -C "$R" commit -qm "main is green"
  wait_until "grep -qx 'ended 0' '$STUB/mw.out'" 'cat "$STUB/mw.out"' || fail "the wait did not end once main moved to a commit that passes a.test: one"
  wait "$mw"
}

# Issue 1313: cards c7, c8 and c9 fail `a.test: one` on a red main (redrunner's: no ok.txt, so a.test's one fails
# there), at main's commit s. Each run of a file on main adds a line naming it to $STUB/mainruns. Given <ok.txt>, main
# has it (redrunner()); while $STUB/broken stands, the machine fails c.test, which ends its run with nothing logged.
mrshared() { # [<ok.txt on main>]
  redrunner "${1:-}"
  echo 't_one() { false; }' > "$R/a.test" && git -C "$R" add a.test && git -C "$R" commit -qm a.test || fail "main's a.test could not be committed"
  { echo 'awk -F"\t" -v f="${CONVEYOR_TEST_FILE:-}" '"'"'$1 == "fail" && (f == "" || $2 == f) { print $2 }'"'"' "$CONVEYOR_TEST_RERUN" >> "$STUB/mainruns"'
    echo '[ "${CONVEYOR_TEST_FILE:-}" != c.test ] || [ ! -e "$STUB/broken" ] || exit 1'
    cat "$STUB/mainrun-cmd"; } > "$STUB/cmd.new" && mv "$STUB/cmd.new" "$STUB/mainrun-cmd" || fail "main's runs could not be counted"
  s=$(git -C "$R" rev-parse HEAD); mkdir -p "$T/$CASE/cards"
}
# verdicts() of card <card> (its worktree made on main's commit when there is none) given <its last run's failures>:
# its output in $STUB/v.<card>, its errors in $STUB/v.<card>.err.
mrv() { # <card> <testfails() json>
  [ -d "$T/$CASE/cards/$1" ] || git -C "$R" worktree add -q --detach "$T/$CASE/cards/$1" || fail "card $1's worktree could not be made"
  eng 'TEST_WAIT=; TEST_RUN=; TEST_FREE=; verdicts '"$1"' "$CONVEYOR_CARDS/'"$1"'" '"'$2'"'' > "$STUB/v.$1" 2> "$STUB/v.$1.err"
}
# Bug it catches (issue 1313): each card that failed the same case on a red main ran the case on main again, so three
# cards on one red commit paid for three runs of one file; and a card that read another's run counted its wait for that
# run as seconds of its own run on main (mainRun.sec, the Board's mainSec). The three cards' verdicts() run at once, as
# cards that fail together call it, main's run of a.test taking 2 seconds: a.test runs on main once, each card reads
# that run's verdict, main, and two of the three ran nothing on main (sec 0).
t_mainredshared() {
  local s c p=() fl='{"files":[{"file":"a.test","cases":[{"name":"one","line":1}]}]}'
  mrshared
  { echo 'sleep 2'; cat "$STUB/mainrun-cmd"; } > "$STUB/cmd.new" && mv "$STUB/cmd.new" "$STUB/mainrun-cmd" || fail "main's run could not be slowed" # sleep: main's run must last while the other two cards wait for it, so their wait would show in mainRun.sec
  for c in c7 c8 c9; do git -C "$R" worktree add -q --detach "$T/$CASE/cards/$c" || fail "card $c's worktree could not be made"; done
  for c in c7 c8 c9; do mrv "$c" "$fl" & p+=($!); done
  wait "${p[@]}"
  for c in c7 c8 c9; do
    [ "$(jq -c .verdicts "$STUB/v.$c")" = '[{"case":"a.test: one","verdict":"main"}]' ] || fail "card $c, given $fl, did not read main's verdict: $(cat "$STUB/v.$c" "$STUB/v.$c.err")"
  done
  [ "$(wc -l < "$STUB/mainruns")" = 1 ] || fail "three cards failing a.test: one at one commit of main ran it there $(wc -l < "$STUB/mainruns") times, not once"
  [ "$(jq -s '[.[].mainRun.sec | select(. == 0)] | length' "$STUB"/v.c?)" = 2 ] \
    || fail "the two cards that read a run of a.test on main did not say they ran nothing there (mainRun.sec 0): $(jq -c .mainRun "$STUB"/v.c?)"
}
# Bug it catches (E1): a card whose failures overlapped another's ran on main again a file main's run at that commit
# already had a result of. c7 fails a.test: one; then c8 fails a.test: one and b.test: two: c8 reads a.test's result
# and runs only b.test, and both are main's.
t_mainredoverlap() {
  mrshared
  echo 't_two() { false; }' > "$R/b.test" && git -C "$R" add b.test && git -C "$R" commit -qm b.test || fail "main's b.test could not be committed"
  mrv c7 '{"files":[{"file":"a.test","cases":[{"name":"one","line":1}]}]}'
  mrv c8 '{"files":[{"file":"a.test","cases":[{"name":"one","line":1}]},{"file":"b.test","cases":[{"name":"two","line":1}]}]}'
  [ "$(jq -c .verdicts "$STUB/v.c8")" = '[{"case":"a.test: one","verdict":"main"},{"case":"b.test: two","verdict":"main"}]' ] \
    || fail "card c8, failing a.test: one and b.test: two on a red main, did not get main for both: $(cat "$STUB/v.c8" "$STUB/v.c8.err")"
  [ "$(sort "$STUB/mainruns" | tr '\n' ' ')" = 'a.test b.test ' ] || fail "c7 (a.test) then c8 (a.test, b.test) did not run each file on main once: $(cat "$STUB/mainruns")"
}
# Bug it catches (E3): a card took the result of a run on main that ran no control (its card failed the sole control,
# c.test, itself), so a broken machine (c.test fails there) was called a red main. c7 fails a.test: one and c.test;
# c8 fails only a.test: one: c8's run of a.test has the control beside it, which fails, so its verdict is machine.
t_mainredcontrol() {
  mrshared; tune '.test.control = ["c.test"]'; : > "$STUB/broken"
  mrv c7 '{"files":[{"file":"a.test","cases":[{"name":"one","line":1}]},{"file":"c.test","cases":[]}]}'
  mrv c8 '{"files":[{"file":"a.test","cases":[{"name":"one","line":1}]}]}'
  [ "$(jq -c .verdicts "$STUB/v.c8")" = '[{"case":"a.test: one","verdict":"machine"}]' ] \
    || fail "card c8, failing a.test: one with the control c.test failing on main, did not get machine: $(cat "$STUB/v.c8" "$STUB/v.c8.err")"
  [ "$(grep -cx a.test "$STUB/mainruns")" = 2 ] || fail "c8 did not run a.test on main beside the control: $(cat "$STUB/mainruns")"
}
# Bug it catches (E2): a failed control was kept with a run's results, so once the machine was repaired a card on the
# same commit read the old failure and was called the machine's again. With c.test (the control) failing, c7's
# a.test: one is the machine's; with the machine repaired, c8's is main's, from a run of its own.
t_mainredmachinefixed() {
  mrshared c.test; tune '.test.control = ["c.test"]'; : > "$STUB/broken"
  mrv c7 '{"files":[{"file":"a.test","cases":[{"name":"one","line":1}]}]}'
  [ "$(jq -c .verdicts "$STUB/v.c7")" = '[{"case":"a.test: one","verdict":"machine"}]' ] || fail "card c7 did not get machine with the control failing: $(cat "$STUB/v.c7" "$STUB/v.c7.err")"
  rm -f "$STUB/broken"
  mrv c8 '{"files":[{"file":"a.test","cases":[{"name":"one","line":1}]}]}'
  [ "$(jq -c .verdicts "$STUB/v.c8")" = '[{"case":"a.test: one","verdict":"main"}]' ] \
    || fail "card c8, failing a.test: one after the machine was repaired, did not get main: $(cat "$STUB/v.c8" "$STUB/v.c8.err")"
}
# R98. Bug it catches: the results of a run on main were kept by main's commit alone, so once an install repaired the
# dependency folders (a node_modules that lacked a package made a file fail there), a card at the same commit read
# the old failure, and its own failure was blamed on main. The pack links node_modules from the main checkout; c7's
# a.test: one runs on main, the folder is made again (as npm ci does), and c8's a.test runs on main again.
t_mainreddepsnew() {
  mrshared; tune '.linkFromMain = ["node_modules"]'
  echo /node_modules >> "$R/.git/info/exclude" && mkdir "$R/node_modules" || fail "main's dependency folder could not be made"
  mrv c7 '{"files":[{"file":"a.test","cases":[{"name":"one","line":1}]}]}'
  rm -rf "$R/node_modules" && mkdir "$R/node_modules" || fail "main's dependency folder could not be made again"
  mrv c8 '{"files":[{"file":"a.test","cases":[{"name":"one","line":1}]}]}'
  [ "$(tr '\n' ' ' < "$STUB/mainruns")" = 'a.test a.test ' ] \
    || fail "after main's node_modules was made again at the same commit, c8 read c7's run of a.test on main and did not run it there again: $(cat "$STUB/mainruns" "$STUB/v.c8.err")"
}
# Bug it catches (E1): a run on main of an older commit, kept as it ended, replaced the results of main's commit as it
# is now. mainkeep() of a run at a commit that is no longer main's leaves the kept results as they were.
t_mainkeepold() {
  local s0 s kept
  mrshared; s0=$(git -C "$R" rev-parse HEAD~1); s=$(git -C "$R" rev-parse HEAD)
  kept='{"sha":"'"$s"'","hits":[],"files":{"a.test":{"ctl":[],"res":null}}}'
  eng 'printf "%s\n" '"'$kept'"' > "$MAINPROBE"; sha='"$s0"' hits="[]" ctl="[]" mf="{\"files\":[]}"; mainkeep c7 "[{\"file\":\"a.test\",\"case\":null}]"; jq -c . "$MAINPROBE"' > "$STUB/kept" 2>&1
  [ "$(cat "$STUB/kept")" = "$kept" ] || fail "a run at the older commit $s0 replaced the results kept at main's commit $s: $(cat "$STUB/kept")"
}
# Bug it catches (issue 1313): a card waiting on a red main woke at each new commit of main and ran its case on main
# again, though main still failed it. Three waits on `a.test: one` at s (mainwait() itself, polled as it runs: only a
# wait under way shows whether it stays or ends). Main moves and still fails it: a.test runs once there, and each card
# waits on, at main's new commit. Main moves again and passes it: a.test runs once more, and all three waits end.
t_mainwaitshared() {
  local s s2 c p=()
  mrshared
  eng 'mainred c1 "a.test: one" a.test '"$s" || fail "the case was not recorded"
  for c in c7 c8 c9; do
    ( eng 'LIVE=0.2; mainwait "$CONVEYOR_CARDS/'"$c"'" '"$s"' "a.test: one"; echo "ended $?"' > "$STUB/mw.$c" 2>&1 ) & p+=($!)
  done
  for c in c7 c8 c9; do
    wait_until "grep -qs 'fail on main at ${s:0:12} too' '$T/$CASE/cards/$c.live'" "cat '$STUB/mw.$c'" || fail "card $c did not wait for main, on a.test: one at $s"
  done
  git -C "$R" commit -q --allow-empty -m "main moves, still red"; s2=$(git -C "$R" rev-parse HEAD)
  for c in c7 c8 c9; do
    wait_until "grep -qs 'fail on main at ${s2:0:12} too' '$T/$CASE/cards/$c.live'" "cat '$STUB/mw.$c'" || fail "card $c, waiting on a.test: one, did not wait on at main's new commit $s2"
  done
  ! grep -qs '^ended' "$STUB"/mw.c? && [ "$(wc -l < "$STUB/mainruns")" = 1 ] \
    || fail "main moved still failing a.test: one, and a wait ended, or a.test ran on main more than once: $(cat "$STUB"/mw.c? "$STUB/mainruns")"
  echo one > "$R/ok.txt"; git -C "$R" add ok.txt; git -C "$R" commit -qm "main is green"
  for c in c7 c8 c9; do
    wait_until "grep -qx 'ended 0' '$STUB/mw.$c'" "cat '$STUB/mw.$c'" || fail "card $c's wait on a.test: one did not end once main passed it"
  done
  wait "${p[@]}"; [ "$(wc -l < "$STUB/mainruns")" = 2 ] || fail "a.test ran on main $(wc -l < "$STUB/mainruns") times over two commits, not twice"
}
# Bug it catches (E4): main deleted the test file a card waited on, and the run of the missing file on main failed as
# before, so the card waited on. A wait on the file a.test (mainwait() itself, polled as it runs: only a wait under
# way shows whether it ends) ends once main's commit has no a.test, which runs on main no more.
t_mainwaitgone() {
  local s mw
  mrshared; mkdir -p "$T/$CASE/cards"
  ( eng 'LIVE=0.2; mainwait "$CONVEYOR_CARDS/c9" '"$s"' a.test; echo "ended $?"' > "$STUB/mw.out" 2>&1 ) & mw=$!
  wait_until "grep -qs 'fail on main at ${s:0:12} too' '$T/$CASE/cards/c9.live'" 'cat "$STUB/mw.out"' || fail "card c9 did not wait for main, on a.test at $s"
  git -C "$R" rm -q a.test && git -C "$R" commit -qm "main deletes a.test" || fail "main could not delete a.test"
  wait_until "grep -qx 'ended 0' '$STUB/mw.out'" 'cat "$STUB/mw.out"' || fail "the wait on a.test did not end once main deleted it"
  wait "$mw"; [ ! -s "$STUB/mainruns" ] || fail "a.test, gone from main, ran there: $(cat "$STUB/mainruns")"
}
# Bug it catches (#1461 B-R140): the runs on main a card's wait took were recorded only once the wait ended, so a card
# shut while it waited (`conveyor.sh shut`: endcard() kills its process group with SIGKILL, so no trap runs) lost them,
# and the Board's mainSec left them out. card()'s wait (mainwaited(), polled as it runs: only a wait under way can be
# killed in it) runs a.test on main once main moves still red, then is killed: its start line holds that run.
t_mainwaitkilled() {
  local s s2 mw
  mrshared
  ( eng 'c=c9 n=9; append "$(line c9 9 picked ok "{\"title\":\"title 9\"}")"; echo "$BASHPID" > "$STUB/mw.pid"
    LIVE=0.2; mainwaited "$CONVEYOR_CARDS/c9" '"$s"' "a.test: one"' > "$STUB/mw.out" 2>&1 ) & mw=$!
  wait_until "grep -qs 'fail on main at ${s:0:12} too' '$T/$CASE/cards/c9.live'" 'cat "$STUB/mw.out"' || fail "card c9 did not wait for main, on a.test: one at $s"
  git -C "$R" commit -q --allow-empty -m "main moves, still red"; s2=$(git -C "$R" rev-parse HEAD)
  wait_until "grep -qs 'fail on main at ${s2:0:12} too' '$T/$CASE/cards/c9.live'" 'cat "$STUB/mw.out"' || fail "card c9 did not wait on at main's new commit $s2"
  kill -KILL "$(cat "$STUB/mw.pid")"; wait "$mw" 2>/dev/null
  [ "$(st 'select(.card == "c9" and .step == "start") | [.of, .mainRun.sha, (.mainRun.sec | type)] | @tsv')" = "test	$s2	number" ] \
    || fail "the run of a.test on main at $s2, taken by a wait killed after it, is on no start line of card c9: $(st 'select(.card == "c9")') $(cat "$STUB/mw.out")"
}
# Bug it catches (E6): a card's wait for main ran its case on main once main moved, and that run's seconds went into
# the wait's (waitSec) and into no run on main, so the Board's Test failures (mainSec) left them out. Main is green
# at a later commit than s, its run of a.test taking 2 seconds: card()'s wait (mainwaited()) runs a.test there and
# ends; a start line of its test step carries that run (mainRun), the wait's seconds (mainsec) leave it out, and the
# snapshot's metrics count it.
t_mainwaitsec() {
  local s out snap ms el
  mrshared
  { echo 'sleep 2'; cat "$STUB/mainrun-cmd"; } > "$STUB/cmd.new" && mv "$STUB/cmd.new" "$STUB/mainrun-cmd" || fail "main's run could not be slowed" # sleep: the run's seconds must stand out of the wait's own
  echo 't_one() { :; }' > "$R/a.test"; echo one > "$R/ok.txt"; git -C "$R" add a.test ok.txt; git -C "$R" commit -qm "main is green"
  out=$(eng 'c=c9 n=9 mainsec=0 t=$SECONDS; append "$(line c9 9 picked ok "{\"title\":\"title 9\"}")"
    mainwaited "$CONVEYOR_CARDS/c9" '"$s"' "a.test: one"; echo "$mainsec $((SECONDS - t))"
    append "$(line c9 9 landed ok "{\"product\":true,\"sha\":\"$(git rev-parse HEAD)\"}")"' 2>&1) || fail "the wait for main did not run: $out"
  [ "$(st 'select(.card == "c9" and .step == "start") | [.of, .mainRun.sha, .mainRun.sec >= 2] | @tsv')" = "test	$(git -C "$R" rev-parse HEAD)	true" ] \
    || fail "the wait on a.test: one at $s ran it on main without a start line carrying that run: $(st 'select(.card == "c9")') $out"
  read -r ms el <<<"$(tail -n 1 <<<"$out")"; [ "$ms" -le $((el - 2)) ] || fail "the wait's seconds ($ms of $el) count the 2-second run on main: $out"
  recok "$ST/cards.jsonl" "the wait for main"
  snap=$(loop snapshot --fresh 2>/dev/null)
  [ "$(jq '.metrics.today.testFailures.mainSec >= 2' <<<"$snap")" = true ] || fail "the snapshot's mainSec leaves out the run on main of the wait: $(jq -c '.metrics.today.testFailures' <<<"$snap")"
}
