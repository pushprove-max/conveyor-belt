#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the speed-up check (speedproof()) and the Optimize check (optproof()) of a card filed from the Tests
# page. The file is held to the median of the recent runs its issue lists, else to its median on record (recentcpu());
# when the issue's verdict is merge, a change that keeps the file adds to that figure the median on record of each
# test file the change removes (a change with no verdict adds none). A change that keeps
# its file must make it faster than that figure (for a stabilise or merge verdict, no slower), and the files of a
# split, summed, may take that figure plus a start-up allowance for each file it adds. A change that deletes the file,
# or merges it into another, is not timed: a delete's review is asked for the tests that cover its cases.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# nopush is bugproof.test.sh's: the runner loads every case file into one shell. A change to bugproof.test.sh's
# helpers or setup runs this file too, through its link in .conveyor/test-links.json.

# The median on record of f.test.sh, 10 CPU s: three whole-suite runs of 9, 10 and 11 (after setup).
median10() {
  local c; for c in 9 10 11; do
    jq -cn --argjson c "$c" '{time: "2026-11-01T00:00:00Z", how: "full", sha: "abc", files: {"f.test.sh": {result: "ok", sec: $c, cpu: $c}}}' >> "$ST/suiteruns.jsonl"
  done
}
# speedproof() called as card() calls it, on card c7 of #7, a bug filed from the Tests page to speed up f.test.sh
# (`echo slow` on main, its median on record 10 CPU s: median10), whose change rewrites f.test.sh. The file's run
# with the change (under cards/mainrun/) notes its folder, the file as it runs and its list in $STUB/mainran, times
# the file at <cpu> CPU s and exits <exit>. When the check fails, the card is blocked as card() blocks it
# (lib/card.sh: SPEEDCHECKED set). The check's exit is in $RC.
speedwt() { # <cpu> [exit]
  setup '[]'; median10
  echo '{ pwd; cat f.test.sh; cat "$CONVEYOR_TEST_RERUN"; } >> "$STUB/mainran"; printf "TESTRUN sec\tf.test.sh\t1\t%s\n" '"$1"' > "$CONVEYOR_TEST_LOG/r"; exit '"${2:-0}" > "$STUB/mainrun-cmd"
  fx_wt 'echo fast > f.test.sh' f.test.sh 'echo slow'
  fx_in 'speedproof c7 "$FXWT" "{\"number\": 7, \"title\": \"Speed up the test file f.test.sh\"}" f.test.sh \
    || { r=$?; SPEEDCHECKED=$SPEEDCHECK block c7 7 "$FXWT" "build: $(<"$FXWT.unfixed")"; exit $r; }'
}
speedline() { st 'select(.step == "bugproof") | "\(.result) \(.speed | tojson)"'; }
SPEEDV=$(sed -n 's/^SPEEDCHECK=//p' "$SRC/lib/speedproof.sh") # the version of the speed check, as speedproof.sh sets it

# D1. Bug it catches: a speed-up card, whose tests pass on main by design, is blocked for not failing there, or goes on
# with no proof that the file is faster. Its file runs alone with the change and is faster than its median on record:
# the check holds, the result shows the numbers, and both numbers are on its record.
t_speedfaster() {
  speedwt 4
  [ "$RC" = 0 ] || fail "a faster speed-up change failed the check: $(cat "$FXWT.unfixed" "$T/$CASE/run.out" 2>&1)"
  [ "$(speedline)" = 'ok {"file":"f.test.sh","before":10,"after":4,"fix":"sped up","into":[]}' ] || fail "the record does not hold both CPU numbers: $(st 'select(.step == "bugproof")')"
  [[ $(head -1 "$STUB/mainran") == */cards/mainrun/* ]] && [ "$(sed -n 2p "$STUB/mainran")" = fast ] && grep -qx $'fail\tf.test.sh' "$STUB/mainran" \
    || fail "the file did not run alone with the change: $(cat "$STUB/mainran" 2>&1)"
  grep -q 'passed in 4 CPU s, lower than its median on record, 10 CPU s' "$FXWT.unfixed" || fail "the result does not show the numbers: $(cat "$FXWT.unfixed")"
  recok "$ST/cards.jsonl" "speedproof()"
}

# D2. Bug it catches: a speed-up card whose file is as slow as its median lands as a speed-up. The check fails with the
# "not faster" reason naming both numbers, and no budget (#349).
t_speedslow() {
  speedwt 10
  [ "$RC" != 0 ] && [ "$(st 'select(.step == "blocked") | .reason')" = 'build: the file is not faster than its median on record (10 CPU s), as the verdict speed up asks: 10 CPU s now' ] \
    || fail "a speed-up change that is not faster did not fail the check (exit $RC): $(st 'select(.step == "blocked")')"
  [ "$(speedline)" = 'fail {"file":"f.test.sh","before":10,"after":10,"fix":"sped up","into":[]}' ] || fail "the record does not hold both CPU numbers: $(st 'select(.step == "bugproof")')"
  # #180: with no version on its line, a later change to the check could not tell this block from others.
  [ "$(st 'select(.step == "blocked") | .speedcheck')" = "$SPEEDV" ] || fail "the blocked line does not carry the speed check's version $SPEEDV: $(st 'select(.step == "blocked")')"
}

# Bug it catches: a speed-up card whose file fails with the change is let through because it ran fast.
t_speedfails() {
  speedwt 4 1
  [ "$RC" != 0 ] && [ "$(st 'select(.step == "blocked") | .reason')" = 'build: the file f.test.sh fails with the change (exit 1)' ] \
    || fail "a speed-up change whose file fails did not fail the check (exit $RC): $(st 'select(.step == "blocked")')"
}

# #831 D2. A whole card, for what only it shows: card() picks speedproof() for a Speed up card, blocks on its failure,
# and gives its result to the review (SPEEDREVIEW). Bug it catches: a Speed up card held to the bug check, reviewed
# when not faster, or reviewed with no word of the speed. Its first build leaves f.test.sh as slow as its median (10
# CPU s): blocked, no review. Its retry's build makes it fast (4 CPU s): the review sees both numbers, and it lands.
t_speedcard() {
  setup "[$(issue 7 2026-01-01 bug | jq -c '.title = "Speed up the test file f.test.sh"')]"; nopush; median10
  echo 'echo slow' > "$R/f.test.sh"; git -C "$R" add f.test.sh && git -C "$R" commit -qm 'a slow test' && git -C "$R" push -q origin main || fail "main's files"
  sed -i 's|^cat > /dev/null; echo x|cat > "$STUB/asked"; echo x|' "$STUB/codex"; echo "$GO" > "$STUB/review.1"
  echo '[ "$(wc -l < "$STUB/sessions")" = 1 ] && echo same > f.test.sh || echo fast > f.test.sh' > "$STUB/build"
  echo 'printf "TESTRUN sec\tf.test.sh\t1\t%s\n" "$(grep -q fast f.test.sh && echo 4 || echo 10)" > "$CONVEYOR_TEST_LOG/r"' > "$STUB/mainrun-cmd"
  loop run >/dev/null || fail "run exited non-zero"
  [ "$(st 'select(.step == "blocked") | .reason')" = 'build: the file is not faster than its median on record (10 CPU s), as the verdict speed up asks: 10 CPU s now' ] && [ ! -e "$STUB/asked" ] \
    || fail "a Speed up card that is not faster was not blocked before review: $(st 'select(.step | IN("review", "blocked"))')"
  loop retry 7 >/dev/null && loop run >/dev/null || fail "the retry exited non-zero"
  grep -qx '# The speed-up check' "$STUB/asked" && grep -q 'passed in 4 CPU s, lower than its median on record, 10 CPU s' "$STUB/asked" \
    || fail "the review was not shown the speed comparison: $(cat "$STUB/asked" 2>&1)"
  [ -n "$(st 'select(.step == "landed") | .sha')" ] || fail "the faster retry did not land: $(st 'select(.step | IN("blocked", "landed"))')"
}

# The case folder of an Optimize issue filed from the Tests page for f.test.sh (on main, `echo slow`, with g.test.sh,
# `echo other`), its median on record 10 CPU s (median10). Each run under cards/mainrun/ runs the files of its list:
# it notes each, with what it holds there, in $STUB/mainran, names the cases one and two of each as passed, and times
# each at the CPU seconds $STUB/cpu-<file> holds. The run of f on main for the build's brief (speedbrief(), under
# cards/mainrun/<card>.cases) is not noted: ownbudget.test.sh holds that brief to its lines.
optmain() { # <cpu of f> [<cpu of f1> <cpu of f2>]
  setup '[]'; median10
  echo "$1" > "$STUB/cpu-f.test.sh"; echo "${2:-}" > "$STUB/cpu-f1.test.sh"; echo "${3:-}" > "$STUB/cpu-f2.test.sh"
  # Run once for each file, as test.fileCommand runs it: the file is CONVEYOR_TEST_FILE.
  cat > "$STUB/mainrun-cmd" <<'EOF'
f=$CONVEYOR_TEST_FILE
[[ $PWD == *.cases ]] || echo "$f: $(cat "$f" 2>/dev/null)" >> "$STUB/mainran"; printf '== %s\nok one\nok two\n' "$f"
printf '== %s\n-- ok %s\nTESTRUN sec\t%s\t1\t%s\n' "$f" "$f" "$f" "$(cat "$STUB/cpu-$f")" >> "$CONVEYOR_TEST_LOG/r"
EOF
}
# optproof() called as card() calls it, on card c7 of the Optimize issue for f.test.sh, whose change runs <change> in
# its worktree on main (optmain's). When the check fails, the card is blocked as card() blocks it (lib/card.sh:
# SPEEDCHECKED set). The check's exit is in $RC; the review's prompt of an Optimize card (OPTREVIEW) in
# $T/$CASE/optreview, from the same load of the engine.
optwt() { # <change> <cpu of f> [<cpu of f1> <cpu of f2>]
  local b=$1; shift
  optmain "$@"
  fx_wt "$b" f.test.sh 'echo slow' g.test.sh 'echo other'
  fx_in 'printf "%s\n" "$OPTREVIEW" > "$T/$CASE/optreview"; optproof c7 "$FXWT" "{\"number\": 7, \"title\": \"Optimize the test file f.test.sh\"}" f.test.sh \
    || { r=$?; SPEEDCHECKED=$SPEEDCHECK block c7 7 "$FXWT" "build: $(<"$FXWT.unfixed")"; exit $r; }'
}

# D1. Bug it catches: an Optimize card, whose tests pass on main by design, is blocked for not failing there, or a
# change that keeps the file lands with no proof that it is faster. It runs alone with the change and is faster than
# its median: the check holds, its record holds both numbers, and the result shows them.
t_optkeep() {
  optwt 'echo fast > f.test.sh' 4
  [ "$RC" = 0 ] || fail "a faster Optimize change failed the check: $(cat "$FXWT.unfixed" "$T/$CASE/run.out" 2>&1)"
  [ "$(speedline)" = 'ok {"file":"f.test.sh","before":10,"after":4,"fix":"sped up","into":[]}' ] || fail "the record does not hold both CPU numbers: $(st 'select(.step == "bugproof")')"
  [ "$(cat "$STUB/mainran")" = 'f.test.sh: fast' ] || fail "the file did not run alone with the change: $(cat "$STUB/mainran" 2>&1)"
  grep -q 'passed in 4 CPU s, lower than its median on record, 10 CPU s' "$FXWT.unfixed" || fail "the result does not show the numbers: $(cat "$FXWT.unfixed")"
  # Bug it catches (#614): the review was told a kept file must cost less than its figure, save for stabilise, so it
  # flagged a merge the engine passes at the file's figure plus the merged file's (t_optmergeinto). The whole rule is
  # matched, so a second, unconditional "less than that figure" limit for a kept file also fails it. The review's
  # prompt (OPTREVIEW, which card() gives the review of an Optimize card) is text with no behaviour to run, so it is read.
  tr '\n' ' ' < "$T/$CASE/optreview" | grep -qF 'A file kept must cost less than that figure, or than the slowest of the recent runs the issue lists; for stabilise, no more than it; and, when another test file is merged into it, no more than that figure plus the median on record of each test file merged into it. The files of a split' \
    || fail "the review is not told one limit for a kept file, with the limit of a merge into it"
}

# D1. Bug it catches: an Optimize card that keeps its file as slow as its median lands. The check fails, and the
# card's blocked line carries the speed check's version.
t_optslow() {
  optwt 'echo fast > f.test.sh' 10
  [ "$RC" != 0 ] && [ "$(st 'select(.step == "blocked") | .reason')" = 'build: the file is not faster than its median on record (10 CPU s), as the verdict speed up asks: 10 CPU s now' ] \
    || fail "an Optimize change that is not faster did not fail the check (exit $RC): $(st 'select(.step == "blocked")')"
  [ "$(st 'select(.step == "blocked") | .speedcheck')" = "$SPEEDV" ] || fail "the blocked line does not carry the speed check's version $SPEEDV: $(st 'select(.step == "blocked")')"
}

# D2. Bug it catches: a split into f1 and f2 (f removed) is failed because f is gone, or is let through unrun. The two
# new files run alone with the change, and their CPU seconds summed (2 + 3) are lower than f's median.
t_optsplit() {
  optwt 'rm f.test.sh; echo one > f1.test.sh; echo two > f2.test.sh' '' 2 3
  [ "$RC" = 0 ] || fail "a faster split failed the check: $(cat "$FXWT.unfixed" "$T/$CASE/run.out" 2>&1)"
  [ "$(speedline)" = 'ok {"file":"f.test.sh","before":10,"after":5,"fix":"split","into":["f1.test.sh","f2.test.sh"]}' ] || fail "the split's record does not hold its summed CPU seconds: $(st 'select(.step == "bugproof")')"
  [ "$(sort "$STUB/mainran" | tr '\n' '|')" = 'f1.test.sh: one|f2.test.sh: two|' ] || fail "the split's new files did not run alone with the change: $(cat "$STUB/mainran" 2>&1)"
  grep -q 'f1.test.sh, f2.test.sh passed in 5 CPU s summed (the median on record of f.test.sh is 10 CPU s): f1.test.sh 2 CPU s, f2.test.sh 3 CPU s' "$FXWT.unfixed" \
    || fail "the result does not show the split's numbers: $(cat "$FXWT.unfixed")"
}

# D3. Bug it catches: a delete is failed for having no test that fails on main, or for having no file to time, or the
# review is never told what the file tested. The file runs alone on main's code as main has it, the check holds, and
# the result gives its cases and asks for the test that covers each.
t_optdelete() {
  optwt 'rm f.test.sh' 4
  [ "$RC" = 0 ] || fail "a delete failed the check: $(cat "$FXWT.unfixed" "$T/$CASE/run.out" 2>&1)"
  [ "$(speedline)" = 'ok {"file":"f.test.sh","before":10,"after":null,"fix":"deleted","into":[]}' ] || fail "a delete's record: $(st 'select(.step == "bugproof")')"
  [ "$(cat "$STUB/mainran")" = 'f.test.sh: echo slow' ] || fail "the file did not run alone as main has it: $(cat "$STUB/mainran" 2>&1)"
  grep -qx -- '- one' "$FXWT.unfixed" && grep -qx -- '- two' "$FXWT.unfixed" \
    && grep -qF 'Name, for each of its cases, the test that still covers it after the change, each on its own line, exactly: `COVERED-BY: <its test file>: <its case>`' "$FXWT.unfixed" \
    || fail "the result does not give the file's cases and ask for the test that covers each: $(cat "$FXWT.unfixed")"
  # The review names the covering tests on COVERED-BY lines (#74): they are no finding, so its GO holds (verdict()),
  # and the review's record keeps them: card() records the review's lines that grep -Ev "$UNRECORDED" leaves.
  printf '%s\n' 'COVERED-BY: g.test.sh: one' 'COVERED-BY: g.test.sh: two' "$GO" > "$FXWT.review"
  fx_in 'verdict "$FXWT.review"; grep -Ev "$UNRECORDED" "$FXWT.review"'
  [ "$(head -n1 "$T/$CASE/run.out")" = GO ] || fail "a review's COVERED-BY lines were taken for findings: $(cat "$T/$CASE/run.out")"
  [ "$(grep -c '^COVERED-BY: g\.test\.sh: ' "$T/$CASE/run.out")" = 2 ] || fail "the review's record lost its COVERED-BY lines: $(cat "$T/$CASE/run.out")"
}

# #831 D3. A whole card, for what only it shows: card() gives the review an Optimize card's check (OPTREVIEW, with
# optproof()'s result) and records the review's lines grep -Ev "$UNRECORDED" leaves. Bug it catches: the review of an
# Optimize deletion is not given the removed file's cases, or its COVERED-BY lines are lost from the landed card's
# record, where the Tests page reads them. The build deletes f.test.sh (cases one and two); the review names g.test.sh.
t_optdeleteland() {
  optmain 4; nopush
  issue 7 2026-01-01 bug | jq -c '[.title = "Optimize the test file f.test.sh"]' > "$STUB/issues.json"
  echo 'echo slow' > "$R/f.test.sh"; echo 'echo other' > "$R/g.test.sh"
  git -C "$R" add f.test.sh g.test.sh && git -C "$R" commit -qm 'a slow test' && git -C "$R" push -q origin main || fail "main's files"
  sed -i 's|^cat > /dev/null; echo x|cat > "$STUB/asked"; echo x|' "$STUB/codex"
  printf '%s\n' 'COVERED-BY: g.test.sh: one' 'COVERED-BY: g.test.sh: two' "$GO" > "$STUB/review.1"; echo 'rm f.test.sh' > "$STUB/build"
  loop run >/dev/null || fail "run exited non-zero"
  grep -qx '# The Optimize check' "$STUB/asked" && grep -qx -- '- one' "$STUB/asked" && grep -qx -- '- two' "$STUB/asked" \
    && grep -qF 'Name, for each of its cases, the test that still covers it after the change, each on its own line, exactly: `COVERED-BY: <its test file>: <its case>`' "$STUB/asked" \
    || fail "the review was not given the removed file's cases and asked for the test that covers each: $(cat "$STUB/asked" 2>&1)"
  [ -n "$(st 'select(.step == "landed") | .sha')" ] || fail "a delete did not land: $(st 'select(.step | IN("blocked", "landed", "review"))')"
  [ "$(st 'select(.step == "review") | .reason' | grep -c '^COVERED-BY: g\.test\.sh: ')" = 2 ] || fail "the review's record lost its COVERED-BY lines: $(st 'select(.step == "review")')"
}

# Bug it catches (#74): a merge recorded as a delete, so the Tests page could not name the file that took the cases of
# the file it removed. A change that removes the file and changes another test file is a merge into that file. What
# it records is the Optimize check's (optproof()) alone: the check is called on such a change in a card's worktree.
t_optmerge() {
  optmain 4
  fx_wt 'rm f.test.sh; echo "echo slow" >> g.test.sh' f.test.sh 'echo slow' g.test.sh 'echo other'
  fx_in 'optproof c7 "$FXWT" "{\"number\": 7}" f.test.sh'
  [ "$RC" = 0 ] || fail "the Optimize check failed a merge: $(cat "$T/$CASE/run.out")"
  [ "$(speedline)" = 'ok {"file":"f.test.sh","before":10,"after":null,"fix":"merged","into":["g.test.sh"]}' ] || fail "a merge's record: $(st 'select(.step == "bugproof")')"
}
