#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the checks of two of the Board's other fix cards (#189): Fix the waiting (steadyproof() with WAITRATIO:
# 3 runs alone, each passing at most 2 times its CPU seconds on the clock) and Fix hollow cases (hollowproof(): the
# judge's hollow check of the changed file, and a COVERED-BY line for each deleted case). Make it run and Delete it
# are in runcheck.test.sh. fx_in and fx_wt are in lib.sh.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# The waits check of f.test.sh, its runs counted in $STUB/wait-runs: each run prints a TESTRUN line of 3 s on the
# clock for 10 CPU s, and the run whose number <slow run> gives 30 s (none with 0).
waitrun() { # <slow run>
  setup '[]'; echo "$1" > "$STUB/wait-slow"
  cat > "$STUB/mainrun-cmd" <<'EOF'
echo run >> "$STUB/wait-runs"; n=$(wc -l < "$STUB/wait-runs"); s=3; [ "$n" != "$(cat "$STUB/wait-slow")" ] || s=30
awk -F'\t' '$1 == "fail" {print $2}' "$CONVEYOR_TEST_RERUN" | while IFS= read -r f; do
  printf '== %s\nTESTRUN sec\t%s\t%s\t10\n-- ok %s\n' "$f" "$f" "$s" "$f" >> "$CONVEYOR_TEST_LOG/r.log"
done
EOF
  fx_wt 'echo "echo fast" > f.test.sh' f.test.sh 'sleep 9' # sleep: the text of main's slow f.test.sh, never run (the stub prints its times)
  fx_in 'steadyproof c7 "$FXWT" f.test.sh "$WAITRATIO"'
}

# Bug it catches: a Fix the waiting card landed with no proof the file waits less. It holds once each of 3 runs alone
# passed at most 2 times its CPU seconds on the clock, and the review is told the figures.
t_waitpass() {
  FXWT=; waitrun 0
  [ "$RC" = 0 ] || fail "a file that ran 3 times at 3 s for 10 CPU s was refused: $WHY $(cat "$T/$CASE/run.out")"
  [ "$(wc -l < "$STUB/wait-runs")" = 3 ] || fail "the file did not run 3 times: $(wc -l < "$STUB/wait-runs")"
  grep -qF 'it passed in each of 3 runs in a row, each at most 2 times its CPU seconds on the clock: 3 s for 10 CPU s, 3 s for 10 CPU s, 3 s for 10 CPU s.' "$FXWT.unfixed" \
    || fail "the review is not told the figures of the 3 runs: $(cat "$FXWT.unfixed")"
}

# Bug it catches: a file that still waits in one run of three landed as fixed. The card is refused naming the run and
# its clock and CPU seconds, and no run is made after it.
t_waitslow() {
  FXWT=; waitrun 2
  [ "$RC" != 0 ] && [ "$WHY" = 'the test file f.test.sh still waits: in run 2 of 3 with the change, alone on a test slot, it took 30 s on the clock for 10 CPU s, more than 2 times its CPU time' ] \
    || fail "a file that still waits in run 2 passed: $RC $WHY"
  [ "$(wc -l < "$STUB/wait-runs")" = 2 ] || fail "runs were made after the one that waited: $(wc -l < "$STUB/wait-runs")"
}

# The hollow check of h.test.sh (cases t_one and t_two, both named hollow by the issue) on card c7, whose change is
# <change> and whose build replied <reply>. The judge (judgecall(), stubbed) answers <answer> and keeps the seat it was
# given in $STUB/hollow-seat; the builder runs on claude, the reviewer on claude too and the review's judge on codex.
hollowrun() { # <change> <reply> <answer>
  setup '[]'
  fx_wt "$1" h.test.sh $'t_one() { true; }\nt_two() { grep -q x f; }' g.test.sh 't_three() { [ 1 = 1 ] || fail one; }'
  jq -cn --arg r "$2" '{type: "result", result: $r}' > "$FXWT.out"
  printf '%s\n' "$3" > "$STUB/hollow-answer"
  jq -cn '{number: 7, title: "Fix the hollow cases of the test file h.test.sh",
    body: "Its hollow cases (case | kind | reason):\n- HOLLOW: one | no-assert | it asserts nothing\n- HOLLOW: two | text-only | it only greps a file"}' > "$STUB/hollow-issue"
  fx_in 'seat() { case $1 in builder | reviewer) echo "{\"agent\":\"claude\",\"model\":\"m-$1\"}" ;; judge) echo "{\"agent\":\"codex\",\"model\":\"m-other\"}" ;; esac; }
    judgecall() { printf "%s\n" "$CALLSEAT" > "$STUB/hollow-seat"; cp "$STUB/hollow-answer" "$1.judge"; echo "{}"; }
    hollowproof c7 "$FXWT" "$(cat "$STUB/hollow-issue")" h.test.sh'
}
HOLLOWFIXED='sed -i "s/true;/[ -s f ] || fail empty;/" h.test.sh'

# Bug it catches: a Fix hollow cases card landed while a case still proved nothing. The judge's hollow check runs on
# the seat of another model family than the builder's (the review's judge, codex here), and the card is refused naming
# each case it still finds hollow.
t_hollowstill() {
  FXWT=; hollowrun "$HOLLOWFIXED" 'Done.' $'two still only greps.\nHOLLOW: t_two | text-only | it only greps a file\nHOLLOW-CHECK: done'
  [ "$RC" != 0 ] && [ "$WHY" = "the judge's hollow check (codex m-other) still finds hollow cases in h.test.sh: t_two (text-only): it only greps a file" ] \
    || fail "a file with a case still hollow passed: $RC $WHY"
  [ "$(cat "$STUB/hollow-seat")" = '{"agent":"codex","model":"m-other"}' ] || fail "the check did not run on the other family's seat: $(cat "$STUB/hollow-seat" 2>&1)"
}

# Bug it catches: a judge's answer cut short (no HOLLOW line, as it never got to them) passed as "no hollow case".
t_hollowcut() {
  FXWT=; hollowrun "$HOLLOWFIXED" 'Done.' 'I read the file and'
  [ "$RC" != 0 ] && [ "$WHY" = "the judge's hollow check gave no whole answer: its last line is not HOLLOW-CHECK: done" ] || fail "a cut answer passed: $RC $WHY"
}

# Bug it catches: a hollow case deleted with no test named for it lost what it was meant to prove. The card is refused
# naming each deleted case with no COVERED-BY line; a line naming a file the change does not keep does not count.
t_hollowgone() {
  FXWT=; hollowrun "$HOLLOWFIXED; sed -i '/t_two/d' h.test.sh" 'COVERED-BY: gone.test.sh: t_x | two' 'HOLLOW-CHECK: done'
  [ "$RC" != 0 ] && [[ $WHY == "each deleted hollow case needs a COVERED-BY line in the build's or a fix session's reply naming a test file the change keeps "*"and these have none: two" ]] \
    || fail "a deleted case with no COVERED-BY line passed: $RC $WHY"
  [ ! -e "$STUB/hollow-seat" ] || fail "the judge ran though the card was already refused"
}

# A case deleted with its COVERED-BY line, and the other made to assert: the card holds, and the review is told the
# deleted case and the line.
t_hollowcovered() {
  FXWT=; hollowrun "$HOLLOWFIXED; sed -i '/t_two/d' h.test.sh" $'Fixed one.\n- COVERED-BY: g.test.sh: t_three | `two`' $'No hollow case.\nHOLLOW-CHECK: done'
  [ "$RC" = 0 ] || fail "a fixed and a covered case were refused: $WHY $(cat "$T/$CASE/run.out")"
  grep -qF 'found no hollow case. The deleted cases, each with its COVERED-BY line in the card'"'"'s replies: two.' "$FXWT.unfixed" && grep -qx -- '- two: covered by g.test.sh' "$FXWT.unfixed" \
    || fail "the review is not told the result: $(cat "$FXWT.unfixed")"
}

# Bug it catches: the check again after a fix session (fixproof() in card()) read only the fix's reply, so a case the
# build deleted with its COVERED-BY line was refused as uncovered. The build's lines are kept for the later check.
t_hollowrefix() {
  FXWT=; hollowrun "$HOLLOWFIXED; sed -i '/t_two/d' h.test.sh" 'COVERED-BY: g.test.sh: t_three | two' $'No hollow case.\nHOLLOW-CHECK: done'
  [ "$RC" = 0 ] || fail "the build's check: $WHY"
  jq -cn '{type: "result", result: "Fixed the finding."}' > "$FXWT.out"
  fx_in 'seat() { case $1 in builder | reviewer) echo "{\"agent\":\"claude\",\"model\":\"m-$1\"}" ;; judge) echo "{\"agent\":\"codex\",\"model\":\"m-other\"}" ;; esac; }
    judgecall() { cp "$STUB/hollow-answer" "$1.judge"; echo "{}"; }
    fixproof c7 "$FXWT" "$(cat "$STUB/hollow-issue")" h.test.sh "$HOLLOWFIX"'
  [ "$RC" = 0 ] || fail "the check after a fix lost the build's COVERED-BY line: $WHY"
}
