#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the check of an Optimize card (optproof(), speedproof()) follows the judge's verdict in its issue and
# holds the file to the median of the recent runs the issue lists, not to its old median on record (#591).
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# The body the Board writes for an Optimize issue of f.test.sh (draftIssue()): an old median of 4 CPU s, last runs of
# 20, 24 and 22 CPU s (their median 22; the runs of $OVRUNS, if set), the judge's verdict <verdict>, and a CAUSE line
# for its flaky case relstop.
ovissue() { # <verdict>
  jq -cn --arg v "$1" --arg r "${OVRUNS:-20.0 CPU s (card #346), 24.0 CPU s (card #352), 22.0 CPU s (whole suite, passed)}" '{number: 7, title: "Optimize the test file f.test.sh", body: ([
    "Optimize this test file: speed it up, split it, merge it into another test file, or delete it. Keep what it tests.", "",
    "What the Board measured:", "- CPU s in its last run: 20.0", "- Median of its runs: 4.0 CPU s (+400% against its median)",
    "- Last runs, newest first: \($r)", "",
    "The judge'"'"'s verdict (2026-11-18T00:00:00Z, claude · a-model · medium): \($v).", "", "The end of its text:",
    "CAUSE: relstop | timing | the case sleeps a fixed time and races the stop", "", "VERDICT: \($v)"] | join("\n"))}'
}
# optproof() called as card() calls it, on card c7 of the issue ovissue() writes for <verdict>, whose change runs
# <change> in its worktree on main, where f.test.sh (`echo slow`) has a median of 4 CPU s on record (whole-suite runs of
# 3, 4 and 5) and g.test.sh one of 2. The build's reply is <reply>. Each run under cards/mainrun/ names the case relstop of each file its list
# names as passed and times it at <cpu> CPU s, noting the file in $STUB/mainran. Main also has each <file> <content>
# pair given. The issue's body ends with the lines of $OVLINES, if set. The check's exit is in $RC and the first line
# of what the review is shown in $WHY.
ovrun() { # <verdict> <change> <cpu> <reply> [<file> <content>]...
  local c
  setup '[]'
  for c in 3 4 5; do
    jq -cn --argjson c "$c" '{time: "2026-11-01T00:00:00Z", how: "full", sha: "abc", files: {"f.test.sh": {result: "ok", sec: $c, cpu: $c},
      "g.test.sh": {result: "ok", sec: 2, cpu: 2}}}' >> "$ST/suiteruns.jsonl"
  done
  echo "$3" > "$STUB/cpu"
  cat > "$STUB/mainrun-cmd" <<'EOF'
while IFS=$'\t' read -r k f; do
  [ "$k" = fail ] || continue; echo "$f" >> "$STUB/mainran"
  printf '== %s\nok relstop\n-- ok %s\n' "$f" "$f"; printf 'TESTRUN sec\t%s\t1\t%s\n' "$f" "$(cat "$STUB/cpu")" >> "$CONVEYOR_TEST_LOG/r"
done < "$CONVEYOR_TEST_RERUN"
EOF
  fx_wt "$2" f.test.sh 'echo slow' "${@:5}"
  jq -cn --arg r "$4" '{type: "result", result: $r}' > "$FXWT.out"
  # shellcheck disable=SC2034 # read by the commands fx_in runs
  ISSUE=$(ovissue "$1" | jq -c --arg l "${OVLINES:-}" 'if $l == "" then . else .body += "\n" + $l end')
  fx_in 'optproof c7 "$FXWT" "$ISSUE" f.test.sh'
}
FIXED='Done.
STABILISED: `relstop` | a fixed sleep raced the stop | the case now waits for the exit file the stop writes'

# D1. Bug it catches (#572, #574): a "speed up" card that cut its file from 20-24 CPU s to 15 was blocked against an
# old median of 4 CPU s on record. The recent runs the issue lists (median 22) are the bar: it passes, and the review
# is shown that figure.
t_optrecent() {
  ovrun 'speed up' 'echo fast > f.test.sh' 15 'Done.'
  [ "$RC" = 0 ] || fail "a speed up card below its recent runs was blocked against its old median: $WHY $(cat "$T/$CASE/run.out")"
  grep -qF 'it passed in 15 CPU s, lower than the median of its recent runs, 22 CPU s.' "$FXWT.unfixed" || fail "the review is not shown the recent figure: $(cat "$FXWT.unfixed")"
  [ "$(st 'select(.step == "bugproof") | "\(.result) \(.speed.before) \(.speed.after)"')" = 'ok 22 15' ] || fail "the bugproof line: $(st 'select(.step == "bugproof")')"
}

# The recent runs of a noisy file, newest first: 74, 126, 81 and 88 CPU s (their median 84.5, the slowest 126).
NOISY='74.0 CPU s (card #1), 126.0 CPU s (card #2), 81.0 CPU s (card #3), 88.0 CPU s (whole suite, passed)'
# #1140 D1. Bug it catches: one run of an "indirect" card's file, taken while other cards run, decided the check, so a
# rewrite whose run (100 CPU s) is over the median of its recent runs (84.5) but inside their spread (up to 126) was
# blocked as not faster. It passes, and the review is told it passed inside the spread, not below the median.
t_optspread() {
  OVRUNS=$NOISY ovrun indirect 'echo direct > f.test.sh' 100 'Done.'
  [ "$RC" = 0 ] || fail "an indirect card whose run is inside the spread of its recent runs was blocked: $WHY $(cat "$T/$CASE/run.out")"
  grep -qF 'it passed in 100 CPU s, not lower than the median of its recent runs, 84.5 CPU s, but lower than the slowest of those runs, 126 CPU s: inside their spread.' "$FXWT.unfixed" \
    || fail "the review is not told the run passed inside the spread: $(cat "$FXWT.unfixed")"
  [ "$(st 'select(.step == "bugproof") | "\(.result) \(.speed.before) \(.speed.after)"')" = 'ok 84.5 100' ] || fail "the bugproof line: $(st 'select(.step == "bugproof")')"
}

# #1140 D2. Bug it catches: the spread lets through a rewrite that is slower than every recent run (130 CPU s against
# 74 to 126). It is still blocked, with the reason of the median.
t_optspreadslow() {
  OVRUNS=$NOISY ovrun indirect 'echo direct > f.test.sh' 130 'Done.'
  [ "$RC" != 0 ] && [ "$WHY" = 'the file is not faster than the median of its recent runs (84.5 CPU s), as the verdict indirect asks: 130 CPU s now' ] \
    || fail "an indirect card slower than every recent run was not blocked as not faster: exit $RC, $WHY"
}

# D2. Bug it catches (#568): a "stabilise" card whose file costs what its recent runs cost was blocked as "not faster".
# Its reply names the cause of relstop and how the change removes it, the case passes and the file takes 22 CPU s, the
# median of its recent runs: it passes, and the review is shown the reply's line to check against the code. The
# build's brief asks for that line, names the recent figure and tells the build to add or remove no other test file
# (#613), or a build that merges one in follows the brief and is blocked.
t_optstable() {
  ovrun stabilise 'echo steady > f.test.sh' 22 "$FIXED"
  [ "$RC" = 0 ] || fail "a stabilise card as dear as its recent runs, with its cause named, was blocked: $WHY"
  grep -qxF -- '- relstop | a fixed sleep raced the stop | the case now waits for the exit file the stop writes' "$FXWT.unfixed" \
    && grep -qF 'Check each against the code' "$FXWT.unfixed" || fail "the review is not given the reply's causes to check: $(cat "$FXWT.unfixed")"
  fx_in 'speedbrief c7 "$FXWT" f.test.sh "$ISSUE"'
  grep -qxF 'The test file f.test.sh used 22 CPU s in its recent runs (the median of those this issue lists).' "$T/$CASE/run.out" \
    && grep -qF 'The verdict of this issue is stabilise. The change keeps the file, adds or removes no other test file,' "$T/$CASE/run.out" && grep -qF 'STABILISED: <case> | <its cause' "$T/$CASE/run.out" \
    || fail "the build's brief does not give the recent figure, keep the other test files (#613) or ask for the STABILISED lines: $(cat "$T/$CASE/run.out")"
}

# D3. Bug it catches: a "stabilise" card lands with no account of why its flaky case failed, so nothing shows that the
# change removed the cause. Its reply names none for relstop: it is blocked before the file runs, and the reason says so.
t_optnocause() {
  ovrun stabilise 'echo steady > f.test.sh' 10 'Done: made it steadier.'
  [ "$RC" != 0 ] && [[ $WHY == "the verdict is stabilise, and the build's reply names no cause for the flaky case relstop: it ends with a line "*'`STABILISED: <case> | '* ]] \
    || fail "a stabilise card with no cause named was not blocked with that reason: exit $RC, $WHY"
  [ ! -e "$STUB/mainran" ] || fail "the file ran though the check already failed: $(cat "$STUB/mainran")"
}

# D4. Bug it catches: a "stabilise" card is not held to the cost of its recent runs, so one dearer than them lands, or
# is blocked only as not faster than its old median (4), as the old check held every card that kept its file and added
# no test file. At 23 CPU s against a median of 22 it is blocked, and the reason names the verdict and that figure.
t_optdearer() {
  ovrun stabilise 'echo steady > f.test.sh' 23 "$FIXED"
  [ "$RC" != 0 ] && [ "$WHY" = 'the file is dearer than the median of its recent runs (22 CPU s), which the verdict stabilise does not allow: 23 CPU s now' ] \
    || fail "a stabilise card dearer than its recent runs was not blocked naming the verdict and the figure: exit $RC, $WHY"
}

# Bug it catches (#615): conveyor/README.md says the median on record is used only when the issue has no "Last runs"
# line, but the Board writes "- Last runs, newest first: none" for a file with no runs, and "— CPU s" for each run with
# a clock time only (draftIssue()), and recentcpu() then uses the median on record (4 here). The guide must name both.
t_optrecentnone() {
  local c
  setup '[]'
  for c in 3 4 5; do
    jq -cn --argjson c "$c" '{time: "2026-11-01T00:00:00Z", how: "full", sha: "abc", files: {"f.test.sh": {result: "ok", sec: $c, cpu: $c}}}' >> "$ST/suiteruns.jsonl"
  done
  # shellcheck disable=SC2034 # read by the commands fx_in runs
  NONE=$(jq -cn '{number: 7, body: "What the Board measured:\n- Last runs, newest first: none"}')
  # shellcheck disable=SC2034 # read by the commands fx_in runs
  CLOCK=$(jq -cn '{number: 7, body: "What the Board measured:\n- Last runs, newest first: — CPU s (a full run), — CPU s (a full run)"}')
  fx_in 'recentcpu "$NONE" f.test.sh; recentcpu "$CLOCK" f.test.sh'
  [ "$(cat "$T/$CASE/run.out")" = $'4\tits median on record\n4\tits median on record' ] \
    || fail "an issue whose Last runs line gives no CPU seconds did not use the median on record: $(cat "$T/$CASE/run.out")"
  # A text check, as the bug is in the guide's words: it must say a Last runs line with no CPU seconds falls back too.
  tr '\n' ' ' < "$SRC/README.md" | grep -qF 'or the line gives no CPU seconds, the check uses the file'"'"'s median on record.' \
    || fail "conveyor/README.md does not say a Last runs line with no CPU seconds uses the median on record"
}

# D5. Bug it catches: a "keep" card is held to the old median (4) as a speed up was. Cut to 15, below its recent runs
# (22), it passes.
t_optkeepverdict() {
  ovrun keep 'echo lean > f.test.sh' 15 'Done.'
  [ "$RC" = 0 ] || fail "a keep card below its recent runs was blocked: $WHY"
}

# Bug it catches: a card does what its verdict does not ask (the verdict is split; the change only edits the file) and
# is checked as a speed up. It is blocked before the file runs, naming the verdict.
t_optshape() {
  ovrun split 'echo fast > f.test.sh' 15 'Done.'
  [ "$RC" != 0 ] && [ "$WHY" = 'the verdict is split, and the change adds no test file' ] && [ ! -e "$STUB/mainran" ] \
    || fail "a card that does not take the shape its verdict asks was not blocked: exit $RC, $WHY"
  [ "$(st 'select(.step == "bugproof") | .result')" = fail ] || fail "the bugproof line: $(st 'select(.step == "bugproof")')"
}

# ovrun() of the change <change> under <verdict>, with g.test.sh on main: it is blocked before the file runs, with the
# reason <reason> and a bugproof line with result fail.
ovshape() { # <verdict> <change> <reason>
  ovrun "$1" "$2" 15 'Done.' g.test.sh 'echo other'
  [ "$RC" != 0 ] && [ "$WHY" = "$3" ] && [ ! -e "$STUB/mainran" ] \
    || fail "a $1 card that does not take the shape its verdict asks was not blocked: exit $RC, $WHY"
  [ "$(st 'select(.step == "bugproof") | .result')" = fail ] || fail "the bugproof line: $(st 'select(.step == "bugproof")')"
}

# Bug it catches: a "merge" card that deletes the file and merges its cases into no other test file passes as a merge
# (its cases are lost).
t_optmergenone() {
  ovshape merge 'rm f.test.sh' 'the verdict is merge, and the change removes the test file f.test.sh without changing another test file'
}

# Bug it catches: a "split" card that adds an unrelated test file and leaves the file as it was passes as a split.
t_optsplitnone() {
  ovshape split 'echo new > h.test.sh' 'the verdict is split, and the change does not change the test file f.test.sh'
}

# Bug it catches: a "speed up" card that deletes the file passes as a delete the judge did not choose.
t_optspeeddelete() {
  ovshape 'speed up' 'rm f.test.sh' 'the verdict is speed up, and the change removes the test file f.test.sh'
}

# Bug it catches: a "keep" card that adds a test file is checked as a split, with its start-up allowance.
t_optkeepsplit() {
  ovshape keep 'echo lean > f.test.sh; echo new > h.test.sh' 'the verdict is keep, and the change adds test files: h.test.sh'
}

# Bug it catches (#613): a "keep" card that merges g.test.sh into the file passes as a keep, held to the file's recent
# runs alone, though that is the merge the judge did not choose. The build's brief of each verdict this check holds
# tells the build so, or a build follows the brief and is blocked (the stabilise brief is checked in t_optstable).
t_optkeepmerge() {
  local v n
  ovshape keep 'echo merged > f.test.sh; rm g.test.sh' 'the verdict is keep, and the change removes test files, as a merge does: g.test.sh'
  for v in 'speed up' keep; do
    ISSUE=$(ovissue "$v") fx_in 'speedbrief c7 "$FXWT" f.test.sh "$ISSUE"'
    n=$(grep -cF "The verdict of this issue is $v. The change keeps the file, adds or removes no other test file," "$T/$CASE/run.out")
    [ "$n" = 1 ] || fail "the $v brief does not tell the build to keep the other test files: $(cat "$T/$CASE/run.out")"
  done
}

# Bug it catches: a "delete" card that moves the file's cases into another test file and removes the file passes as a
# delete, though that is the merge the judge did not choose.
t_optdeletemerge() {
  ovshape delete 'rm f.test.sh; echo more >> g.test.sh' 'the verdict is delete, and the change also changes test files, as a merge does: g.test.sh'
}

# Bug it catches: a "merge" card that merges g.test.sh (2 CPU s on record) into the file is held to the file's recent
# runs alone (22), as a speed up, and blocked though the two files together cost no more than before. At 24 CPU s, the
# two figures summed, it passes.
t_optmergeinto() {
  ovrun merge 'echo merged > f.test.sh; rm g.test.sh' 24 'Done.' g.test.sh 'echo other'
  [ "$RC" = 0 ] || fail "a merge into the file, as dear as the two files' figures together, was blocked: $WHY"
  grep -qF 'it passed in 24 CPU s, not more than the median of its recent runs plus the median on record of g.test.sh, 24 CPU s.' "$FXWT.unfixed" \
    || fail "the review is not shown the summed figure: $(cat "$FXWT.unfixed")"
}

# Bug it catches (#778): a Rewrite as a direct check card, its issue as the Tests page files it (its title, no verdict
# line, the judge's DIRECT lines), drops the case relpin that a DIRECT line says must keep passing, leaving its name in
# a comment, keeping the longer case relpinclock and the case of one line t_relpinn that calls a helper named relpin,
# and passes as an Optimize card: the rewrite loses that case. It is blocked before the file runs.
t_optdirect() {
  setup '[]'
  fx_wt "printf '%s\n' 't_relstop() { :; }' '# relpin was here' 't_relpinclock() { :; }' 't_relpinn() { relpin narrow; }' > f.test.sh" f.test.sh "$(printf '%s\n' 't_relstop() { :; }' 't_relpin() { :; }' 't_relpinclock() { :; }' 't_relpinn() { relpin narrow; }')"
  # shellcheck disable=SC2034 # read by the commands fx_in runs
  ISSUE=$(jq -cn '{number: 7, title: "Rewrite the test file f.test.sh as direct checks", body: ([
    "This test file checks what it protects through a proxy.", "", "Its proxy parts (what it protects | the direct check | the cases that must keep passing):",
    "- DIRECT: the install holds the right files | compare the installed list with the manifest | `relstop`, relpin"] | join("\n"))}')
  fx_in 'optproof c7 "$FXWT" "$ISSUE" f.test.sh'
  [ "$RC" != 0 ] && [ "$WHY" = "the verdict is indirect, and the change drops cases of f.test.sh that the issue's DIRECT lines say must keep passing: relpin" ] && [ ! -e "$STUB/mainran" ] \
    || fail "a rewrite that drops a case its DIRECT lines name was not blocked: exit $RC, $WHY"
  [ "$(st 'select(.step == "bugproof") | .result')" = fail ] || fail "the bugproof line: $(st 'select(.step == "bugproof")')"
}

# Bug it catches (#827): a DIRECT line with a | in its check text ("P3=off | on, which ...") made the words after it
# the case list, and a judge named a case another file defines (snapfixlive), so a rewrite that keeps every case of
# its file was blocked for dropping cases the file never had. The check reads only the case names the file defines on
# the card's base commit (relstop) and passes; a DIRECT line that names no case of the file, or no case at all, is
# passed over, as the log says.
t_optdirectbar() {
  OVLINES=$(printf '%s\n' '- DIRECT: the stop is clean | control rules P3=off | on, which t_relstop already asserts | relstop, snapfixlive' \
    '- DIRECT: the loop lands | run the loop | no case named here' 'DIRECT: the slot is freed | no cases named |')
  ovrun indirect "printf '%s\n' 't_relstop() { :; }' 't_direct() { :; }' > f.test.sh" 15 'Done.' f.test.sh 't_relstop() { :; }'
  [ "$RC" = 0 ] || fail "a rewrite that keeps every case its DIRECT lines name was blocked: $WHY $(cat "$T/$CASE/run.out")"
  grep -qF 'conveyor: card c7: a DIRECT line of its issue (the loop lands) names no case f.test.sh defines, so no case of it is checked' "$T/$CASE/run.out" \
    || fail "the log does not say a DIRECT line names no case of the file: $(cat "$T/$CASE/run.out")"
  grep -qF 'conveyor: card c7: 1 DIRECT line(s) of its issue name no case, so no case of them is checked' "$T/$CASE/run.out" \
    || fail "the log does not say a DIRECT line with an empty case field was passed over: $(cat "$T/$CASE/run.out")"
}

# Bugs it catches (#827): directcases() kept only case names of one word, so a JavaScript case whose name has spaces
# was never checked and a rewrite could drop it; and it copied the base file to a path built from the issue's file
# name, so a name with ../ in it wrote outside the copy's directory. The case with spaces is kept, and a file beside
# the worktree that the ../ name points to is left as it was.
t_directcases() {
  setup '[]'
  local w=$T/$CASE/wt
  mkdir -p "$w" && git -C "$w" init -q && printf '%s\n' "test('under reduced motion nothing animates', () => {});" > "$w/f.test.mjs" \
    && git -C "$w" add f.test.mjs && git -C "$w" -c user.name=t -c user.email=t@example.com commit -qm base || fail "the base commit"
  echo kept > "$T/$CASE/out.test.mjs"
  # shellcheck disable=SC2034 # read by the commands fx_in runs
  ISSUE=$(jq -cn '{body: "DIRECT: motion | run it | under reduced motion nothing animates, snapproof"}')
  mkdir -p "$T/$CASE/tmp"
  # The copy's directory is made under $T/$CASE/tmp, so ../../out.test.mjs from it is the file above.
  FXWT=$w TMPDIR=$T/$CASE/tmp fx_in 'directcases c7 "$FXWT" "$ISSUE" f.test.mjs; directcases c7 "$FXWT" "$ISSUE" ../../out.test.mjs'
  [ "$(head -n 1 "$T/$CASE/run.out")" = 'under reduced motion nothing animates' ] || fail "a case name with spaces was not checked: $(cat "$T/$CASE/run.out")"
  [ "$(cat "$T/$CASE/out.test.mjs")" = kept ] || fail "a ../ file name in the issue wrote outside the copy's directory"
}

# Bug it catches (#798): casesgone() read a JavaScript case's name from its unescaped start line, so an escaped quote
# in it (test('... project\'s', ...)) ended the name early and a case the file still holds was read as gone, which
# blocked optproof() and hollowproof(). Only the case the file does not hold is gone.
t_optdirectescape() {
  setup '[]'
  mkdir -p "$T/$CASE/wt"
  printf '%s\n' "test('the switch changes the rows to that project\\'s', () => {" '  x();' '});' 'it("a \"quoted\" name", () => {});' \
    'test(`a tick \` name`, () => {});' > "$T/$CASE/wt/f.test.mjs"
  fx_in "casesgone \"\$T/\$CASE/wt\" f.test.mjs \"\$(printf '%s\n' \"the switch changes the rows to that project's\" 'a \"quoted\" name' 'a tick \` name' 'gone one')\""
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = 'gone one' ] || fail "cases with escaped quotes in their names were read as gone: exit $RC, $(cat "$T/$CASE/run.out")"
}

# Bug it catches (#799): card() sends a Rewrite as a direct check card (REWRITE) to optproof(); without that route it
# goes to the bug-card check, which never reads its DIRECT lines, so a build that drops the case relpin they name is
# not blocked for it. A whole card run, as only it shows which check card() picks for the issue's title.
t_optdirectcard() {
  setup "[$(issue 7 2026-01-01 bug | jq -c '.title = "Rewrite the test file f.test.sh as direct checks"
    | .body = "- DIRECT: the install holds the right files | compare the installed list with the manifest | relpin"')]"; nopush
  printf '%s\n' 't_relstop() { :; }' 't_relpin() { :; }' > "$R/f.test.sh"
  git -C "$R" add f.test.sh && git -C "$R" commit -qm 'a test' && git -C "$R" push -q origin main || fail "main's files"
  echo "printf '%s\n' 't_relstop() { :; }' > f.test.sh" > "$STUB/build"
  loop run >/dev/null || fail "run exited non-zero"
  [ "$(st 'select(.step == "blocked") | .reason')" = "build: the verdict is indirect, and the change drops cases of f.test.sh that the issue's DIRECT lines say must keep passing: relpin" ] \
    || fail "card() did not send a Rewrite card to the Optimize check: $(st 'select(.step | IN("review", "blocked", "landed"))')"
}
