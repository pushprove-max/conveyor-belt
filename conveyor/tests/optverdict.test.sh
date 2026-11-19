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
# 20, 24 and 22 CPU s (their median 22), the judge's verdict <verdict>, and a CAUSE line for its flaky case relstop.
ovissue() { # <verdict>
  jq -cn --arg v "$1" '{number: 7, title: "Optimize the test file f.test.sh", body: ([
    "Optimize this test file: speed it up, split it, merge it into another test file, or delete it. Keep what it tests.", "",
    "What the Board measured:", "- CPU s in its last run: 20.0", "- Median of its runs: 4.0 CPU s (+400% against its median)",
    "- Last runs, newest first: 20.0 CPU s (card #346), 24.0 CPU s (card #352), 22.0 CPU s (whole suite, passed)", "",
    "The judge'"'"'s verdict (2026-11-18T00:00:00Z, claude · a-model · medium): \($v).", "", "The end of its text:",
    "CAUSE: relstop | timing | the case sleeps a fixed time and races the stop", "", "VERDICT: \($v)"] | join("\n"))}'
}
# optproof() called as card() calls it, on card c7 of the issue ovissue() writes for <verdict>, whose change runs
# <change> in its worktree on main, where f.test.sh (`echo slow`) has a median of 4 CPU s on record (whole-suite runs of
# 3, 4 and 5) and g.test.sh one of 2. The build's reply is <reply>. Each run under cards/mainrun/ names the case relstop of each file its list
# names as passed and times it at <cpu> CPU s, noting the file in $STUB/mainran. Main also has each <file> <content>
# pair given. The check's exit is in $RC and the first line of what the review is shown in $WHY.
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
  ISSUE=$(ovissue "$1")
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

# D2. Bug it catches (#568): a "stabilise" card whose file costs what its recent runs cost was blocked as "not faster".
# Its reply names the cause of relstop and how the change removes it, the case passes and the file takes 22 CPU s, the
# median of its recent runs: it passes, and the review is shown the reply's line to check against the code. The
# build's brief asks for that line and names the recent figure.
t_optstable() {
  ovrun stabilise 'echo steady > f.test.sh' 22 "$FIXED"
  [ "$RC" = 0 ] || fail "a stabilise card as dear as its recent runs, with its cause named, was blocked: $WHY"
  grep -qxF -- '- relstop | a fixed sleep raced the stop | the case now waits for the exit file the stop writes' "$FXWT.unfixed" \
    && grep -qF 'Check each against the code' "$FXWT.unfixed" || fail "the review is not given the reply's causes to check: $(cat "$FXWT.unfixed")"
  fx_in 'speedbrief c7 "$FXWT" f.test.sh "$ISSUE"'
  grep -qxF 'The test file f.test.sh used 22 CPU s in its recent runs (the median of those this issue lists).' "$T/$CASE/run.out" \
    && grep -qF 'The verdict of this issue is stabilise. ' "$T/$CASE/run.out" && grep -qF 'STABILISED: <case> | <its cause' "$T/$CASE/run.out" \
    || fail "the build's brief does not give the recent figure or ask for the STABILISED lines: $(cat "$T/$CASE/run.out")"
}

# D3. Bug it catches: a "stabilise" card lands with no account of why its flaky case failed, so nothing shows that the
# change removed the cause. Its reply names none for relstop: it is blocked before the file runs, and the reason says so.
t_optnocause() {
  ovrun stabilise 'echo steady > f.test.sh' 10 'Done: made it steadier.'
  [ "$RC" != 0 ] && [[ $WHY == "the verdict is stabilise, and the build's reply names no cause for the flaky case relstop: it ends with a line "*'`STABILISED: <case> | '* ]] \
    || fail "a stabilise card with no cause named was not blocked with that reason: exit $RC, $WHY"
  [ ! -e "$STUB/mainran" ] || fail "the file ran though the check already failed: $(cat "$STUB/mainran")"
}

# D4. Bug it catches: a "stabilise" card that makes its file dearer than its recent runs lands, as only a speed up was
# held to a cost. At 23 CPU s against a median of 22 it is blocked, and the reason names the verdict and that figure.
t_optdearer() {
  ovrun stabilise 'echo steady > f.test.sh' 23 "$FIXED"
  [ "$RC" != 0 ] && [ "$WHY" = 'the file is dearer than the median of its recent runs (22 CPU s), which the verdict stabilise does not allow: 23 CPU s now' ] \
    || fail "a stabilise card dearer than its recent runs was not blocked naming the verdict and the figure: exit $RC, $WHY"
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
