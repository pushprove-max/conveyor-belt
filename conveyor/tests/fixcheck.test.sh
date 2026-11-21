#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 120
# Engine cases: the checks of two of the Board's other fix cards (#189): Fix the waiting (speedproof.sh steadyproof() with WAITRATIO:
# 3 runs alone, each passing at most 2 times its CPU seconds on the clock) and Fix hollow cases (speedproof.sh hollowproof(): the
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

# The hollow check of h.test.sh (cases t_one and t_two, both named hollow by the issue, and t_old between them, which
# it does not name), or of <test file> with <its content>, on card c7, whose change is <change> and whose build replied
# <reply>. The judge (judgecall(), stubbed) answers <answer> and keeps the seat it was given in $STUB/hollow-seat; the
# builder runs on claude, the reviewer on claude too and the review's judge on codex.
hollowrun() { # <change> <reply> <answer> [<test file> <its content>]
  local f=${4:-h.test.sh}
  setup '[]'
  fx_wt "$1" "$f" "${5:-$'t_one() { true; }\nt_old() { :; }\nt_two() { grep -q x f; }'}" g.test.sh 't_three() { [ 1 = 1 ] || fail one; }'
  jq -cn --arg r "$2" '{type: "result", result: $r}' > "$FXWT.out"
  printf '%s\n' "$3" > "$STUB/hollow-answer"
  jq -cn --arg f "$f" '{number: 7, title: "Fix the hollow cases of the test file \($f)",
    body: "Its hollow cases (case | kind | reason):\n- HOLLOW: one | no-assert | it asserts nothing\n- HOLLOW: two | text-only | it only greps a file"}' > "$STUB/hollow-issue"
  fx_in 'seat() { case $1 in builder | reviewer) echo "{\"agent\":\"claude\",\"model\":\"m-$1\"}" ;; judge) echo "{\"agent\":\"codex\",\"model\":\"m-other\"}" ;; esac; }
    judgecall() { printf "%s\n" "$CALLSEAT" > "$STUB/hollow-seat"; cp "$STUB/hollow-answer" "$1.judge"; echo "{}"; }
    hollowproof c7 "$FXWT" "$(cat "$STUB/hollow-issue")" '"$f"
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

# Bug it catches (#584): a hollow case the change added passed as an old case the card need not fix. A case the
# change adds is the card's own work, so a hollow one blocks it.
t_hollowadded() {
  FXWT=; hollowrun "$HOLLOWFIXED; sed -i 's/grep -q x f;/[ -s f ] || fail two;/' h.test.sh; echo 't_new() { :; }' >> h.test.sh" 'Done.' $'HOLLOW: t_new | no-assert | it asserts nothing\nHOLLOW-CHECK: done'
  [ "$RC" != 0 ] && [ "$WHY" = "the judge's hollow check (codex m-other) still finds hollow cases in h.test.sh: t_new (no-assert): it asserts nothing" ] \
    || fail "a hollow case the change added passed: $RC $WHY"
}

# Bug it catches (#607): a hollow old case the issue did not name, whose body (not its start line) the change edited,
# passed as an old case the card did not touch. A changed line of a case that is not a note (blank or a comment) makes
# it the card's work, so it blocks.
t_hollowbody() {
  FXWT=; hollowrun "$HOLLOWFIXED; sed -i '3a\  echo ran' h.test.sh" 'Done.' $'HOLLOW: t_old | no-assert | it asserts nothing\nHOLLOW-CHECK: done' \
    h.test.sh $'t_one() { true; }\nt_old() {\n  [ 1 = 1 ]\n}\nt_two() { grep -q x f; }'
  [ "$RC" != 0 ] && [ "$WHY" = "the judge's hollow check (codex m-other) still finds hollow cases in h.test.sh: t_old (no-assert): it asserts nothing" ] \
    || fail "a hollow old case whose body the change edited passed: $RC $WHY"
}

# Bug it catches (#584): a card that fixed every case its issue named was blocked by an old hollow case the issue did
# not name and the change did not touch, also when the case it deleted came right after the old one (the deletion was
# placed on the old case's last line). It holds, and the old case goes to the declined list for the owner.
t_hollowold() {
  FXWT=; hollowrun "$HOLLOWFIXED; sed -i '/t_two/d' h.test.sh" 'COVERED-BY: g.test.sh: t_three | two' $'HOLLOW: `t_old` | no-assert | it asserts nothing\nHOLLOW-CHECK: done'
  [ "$RC" = 0 ] || fail "an old hollow case the card did not touch blocked it: $WHY $(cat "$T/$CASE/run.out")"
  grep -qF 'It found these other hollow cases, each now on the declined list: t_old (no-assert): it asserts nothing.' "$FXWT.unfixed" \
    || fail "the review is not told the old case: $(cat "$FXWT.unfixed")"
  fx_in 'stdb ask lines declined'
  jq -e -s 'length == 1 and (.[0] | .card == "c7" and .issue == 7 and .by == "code" and .finding == "Hollow case of the test file h.test.sh: t_old (no-assert): it asserts nothing")' "$T/$CASE/run.out" > /dev/null \
    || fail "the old case is not a declined finding: $(cat "$T/$CASE/run.out")"
}

# Bug it catches (#584): in a file whose language has no case start line (Ruby), each line was read as a case, so a
# case whose body the change edited passed as an old case. A hollow case the check cannot place blocks the card.
t_hollowpy() {
  FXWT=; hollowrun "sed -i 's/assert g/g/' h_test.rb" 'Done.' $'HOLLOW: test_old | no-assert | it asserts nothing\nHOLLOW-CHECK: done' \
    h_test.rb $'def test_one\n  assert f\nend\ndef test_two\n  assert h\nend\ndef test_old\n  assert g\nend'
  [ "$RC" != 0 ] && [ "$WHY" = "the judge's hollow check (codex m-other) still finds hollow cases in h_test.rb: test_old (no-assert): it asserts nothing" ] \
    || fail "a hollow Ruby case the change edited passed: $RC $WHY"
}

# Bug it catches (#584): Python had no case start line, so every hollow case of a Python file blocked the card, also
# an old one the judge names by its class (TestH.test_old). It is placed by its last part and declined.
t_hollowpyold() {
  FXWT=; hollowrun "sed -i -e '3s/pass/assert f()/' -e '5s/pass/assert h()/' h_test.py" 'Done.' $'HOLLOW: TestH.test_old | no-assert | it asserts nothing\nHOLLOW-CHECK: done' \
    h_test.py $'class TestH:\n    def test_one(self):\n        pass\n    def test_two(self):\n        pass\n    def test_old(self):\n        pass'
  [ "$RC" = 0 ] || fail "an old hollow Python case the card did not touch blocked it: $WHY $(cat "$T/$CASE/run.out")"
  grep -qF 'each now on the declined list: TestH.test_old (no-assert)' "$FXWT.unfixed" || fail "the old case is not declined: $(cat "$FXWT.unfixed")"
}

# Bug it catches (#584 review): a comment the change put after an old case read as a change of that case, and a title
# with an escape (name\'s) matched no start line, so each blocked the card on an old hollow case it did not touch.
t_hollowjsold() {
  FXWT=; hollowrun "sed -i -e '1s/{}/{ assert.ok(a); }/' -e '3s/{}/{ assert.ok(b); }/' -e '2a // The other cases moved to g.test.sh' h.test.mjs" 'Done.' \
    $'HOLLOW: the name\'s belt | no-assert | it asserts nothing\nHOLLOW-CHECK: done' \
    h.test.mjs $'test(\'one\', () => {});\ntest(\'the name\\\'s belt\', () => {});\ntest(\'two\', () => {});'
  [ "$RC" = 0 ] || fail "an old hollow case with a comment after it, or an escaped title, blocked the card: $WHY $(cat "$T/$CASE/run.out")"
  grep -qF "each now on the declined list: the name's belt (no-assert)" "$FXWT.unfixed" || fail "the old case is not declined: $(cat "$FXWT.unfixed")"
}

# Bug it catches (#606): a case ran to the line before the next start line, so a change to the setup of a later case
# (HOLDS, after an old case's closing line) read as a change of the old case and blocked the card on it.
t_hollowsetup() {
  FXWT=; hollowrun "sed -i -e '1s/{}/{ assert.ok(a); }/' -e \"5s/'a'/'b'/\" -e '6s/{}/{ assert.ok(HOLDS[0]); }/' h.test.mjs" 'Done.' \
    $'HOLLOW: old | text-only | it only reads the source\nHOLLOW-CHECK: done' \
    h.test.mjs $'test(\'one\', () => {});\ntest(\'old\', () => {\n  assert.ok(src.includes(\'x\'));\n});\nconst HOLDS = [\'a\'];\ntest(\'two\', () => {});'
  [ "$RC" = 0 ] || fail "a change to the setup after an old hollow case blocked the card on that case: $WHY $(cat "$T/$CASE/run.out")"
  grep -qF 'each now on the declined list: old (text-only)' "$FXWT.unfixed" || fail "the old case is not declined: $(cat "$FXWT.unfixed")"
}

# Bug it catches (#606): the same in Python, whose case has no closing line: it ends before the next line of code that
# is not indented past its def, so a change to a module value after it is in no case.
t_hollowpysetup() {
  FXWT=; hollowrun "sed -i -e '2s/pass/assert f()/' -e '5s/1/2/' -e '7s/pass/assert h() == LIMIT/' h_test.py" 'Done.' \
    $'HOLLOW: test_old | no-assert | it asserts nothing\nHOLLOW-CHECK: done' \
    h_test.py $'def test_one():\n    pass\ndef test_old():\n    pass\nLIMIT = 1\ndef test_two():\n    pass'
  [ "$RC" = 0 ] || fail "a change to a module value after an old hollow Python case blocked the card on that case: $WHY $(cat "$T/$CASE/run.out")"
  grep -qF 'each now on the declined list: test_old (no-assert)' "$FXWT.unfixed" || fail "the old case is not declined: $(cat "$FXWT.unfixed")"
}

# Bug it catches (#606 review): a line of a heredoc at the left edge that ends in a bracket (a JSON record, or the
# close of a function after a case pattern `x)` that a bracket count reads as a close) ended the case, so a change
# after it was in no case and a changed case still hollow was declined.
t_hollowfixture() {
  FXWT=; hollowrun "sed -i '11s/:/: changed/' h.test.sh" 'Done.' \
    $'HOLLOW: t_old | no-assert | it asserts nothing\nHOLLOW-CHECK: done' \
    h.test.sh $'t_one() { true; }\nt_old() {\n  cat > r <<\'EOF\'\n{"a":1}\nf() {\n  case $1 in\n    x) : ;;\n  esac\n}\nEOF\n  :\n}\nt_two() { grep -q x f; }'
  [ "$RC" != 0 ] && [ "$WHY" = "the judge's hollow check (codex m-other) still finds hollow cases in h.test.sh: t_old (no-assert): it asserts nothing" ] \
    || fail "a changed case still hollow passed when fixture text in it ended in a bracket: $RC $WHY"
}

# Bug it catches (#606 review): in JavaScript a bracket in a regular expression (/a[^{]*b/) kept the old case open to
# the next case, so a change to HOLDS after it blocked the card on it; and a line `});` at the left edge in a template
# string ended the case mid, so a change after it was in no case and mid, changed and still hollow, was declined.
t_hollowjsfixture() {
  FXWT=; hollowrun "sed -i -e \"5s/'a'/'b'/\" -e '10s/trim()/trim(1)/' h.test.mjs" 'Done.' \
    $'HOLLOW: old | text-only | it only reads the source\nHOLLOW: mid | no-assert | it asserts nothing\nHOLLOW-CHECK: done' \
    h.test.mjs $'test(\'one\', () => {});\ntest(\'old\', () => {\n  assert.match(css, /a[^{]*b/);\n});\nconst HOLDS = [\'a\'];\ntest(\'mid\', () => {\n  const s = `x\n});\n`;\n  s.trim();\n});\ntest(\'two\', () => {});'
  [ "$RC" != 0 ] && [ "$WHY" = "the judge's hollow check (codex m-other) still finds hollow cases in h.test.mjs: mid (no-assert): it asserts nothing" ] \
    || fail "the hollow check did not hold mid alone (a regular expression or a template string misread): $RC $WHY"
}

# Bug it catches (#606 review): in Python a comment or a docstring line at the left edge ended the case, so a change
# after it was in no case and a changed case still hollow was declined.
t_hollowpyfixture() {
  FXWT=; hollowrun "sed -i '8s/pass/x = 1/' h_test.py" 'Done.' \
    $'HOLLOW: test_old | no-assert | it asserts nothing\nHOLLOW-CHECK: done' \
    h_test.py $'def test_one():\n    pass\ndef test_old():\n# a note at the left edge\n    s = """\nLIMIT = 1\n"""\n    pass\ndef test_two():\n    pass'
  [ "$RC" != 0 ] && [ "$WHY" = "the judge's hollow check (codex m-other) still finds hollow cases in h_test.py: test_old (no-assert): it asserts nothing" ] \
    || fail "a changed Python case still hollow passed when a comment or docstring in it was at the left edge: $RC $WHY"
}

# Bug it catches (#612): in shell a line at the left edge that ends in a bracket closing one it opened (a comment that
# ends `(x)`, x=$(f), a() { :; }, [ -n "$x" ]) ended the case, so a change after it was in no case and a changed case
# still hollow was declined. A case of one line (t_mid) still ends on its line, so the setup after it is in no case.
t_hollowshclose() {
  FXWT=; hollowrun "sed -i -e '3s/1/2/' -e '9s/:/: changed/' h.test.sh" 'Done.' \
    $'HOLLOW: t_mid | no-assert | it asserts nothing\nHOLLOW: t_old | no-assert | it asserts nothing\nHOLLOW-CHECK: done' \
    h.test.sh $'t_one() { true; }\nt_mid() { :; }\nV=1\nt_old() {\n# a comment (x)\nx=$(echo a)\na() { :; }\n[ -n "$x" ]\n:\n}\nt_two() { grep -q x f; }'
  [ "$RC" != 0 ] && [ "$WHY" = "the judge's hollow check (codex m-other) still finds hollow cases in h.test.sh: t_old (no-assert): it asserts nothing" ] \
    || fail "a changed shell case still hollow passed, or a one-line case took the setup after it: $RC $WHY"
  fx_in 'stdb ask lines declined'
  jq -e -s 'length == 1 and .[0].finding == "Hollow case of the test file h.test.sh: t_mid (no-assert): it asserts nothing"' "$T/$CASE/run.out" > /dev/null \
    || fail "the old one-line case is not declined: $(cat "$T/$CASE/run.out")"
}

# Bug it catches (#584 review): with every case start line put in a comment the file had no case left, so its whole
# text was read, and the names in the comments passed as kept cases with no COVERED-BY line.
t_hollowcommented() {
  FXWT=; hollowrun "sed -i 's/^t_/# t_/' h.test.sh" 'Done.' 'HOLLOW-CHECK: done'
  [ "$RC" != 0 ] && [[ $WHY == *"COVERED-BY"*"these have none: one, two" ]] || fail "cases hidden in comments passed as kept: $RC $WHY"
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

# Bug it catches: the check again after a fix session (speedproof.sh fixproof() in card()) read only the fix's reply, so a case the
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

# A whole card, for what only it proves: a retry with no build (#232) keeps the COVERED-BY lines of the build's reply.
# Bug it catches: a Fix hollow cases card whose build deleted its file, with a COVERED-BY line for each case, stopped
# for the owner's yes; its block dropped those lines, so its retry with the yes, landing the kept patch with no build,
# was blocked as if the deleted cases were uncovered.
t_hollowlandyes() {
  local i
  i=$(issue 7 2026-01-01 bug | jq -c '.title = "Fix the hollow cases of the test file h.test.sh" | .body += "\n- HOLLOW: one | no-assert | it asserts nothing\n- HOLLOW: two | text-only | it only greps a file\n"')
  setup "[$i]"
  printf 't_one() { true; }\nt_two() { grep -q x f; }\n' > "$R/h.test.sh"; echo 't_three() { [ 1 = 1 ] || fail one; }' > "$R/g.test.sh"
  git -C "$R" add h.test.sh g.test.sh && git -C "$R" commit -qm 'tests' && git -C "$R" push -q origin main || fail "main's files"
  echo 'git rm -q h.test.sh; mkdir -p web; echo pay >> web/pay.ts; jq -cn '\''{type: "result", result: "COVERED-BY: g.test.sh: t_three | one\nCOVERED-BY: g.test.sh: t_three | two"}'\''' > "$STUB/build"
  printf '%s\n' 'USER-VISIBLE: yes: guests see a new Pay button' 'VERDICT: GO' > "$STUB/review.1"
  loop run > /dev/null || fail "first run exited non-zero"
  st 'select(.step == "blocked") | .reason' | grep -q "^visible to customers or staff: needs .*'s yes" || fail "the card did not stop for the yes: $(st 'select(.step | IN("blocked", "landed"))')"
  jq -c '[.body += "\nVisible change approved: r-11\n"]' <<<"$i" > "$STUB/issues.json"
  loop retry 7 > /dev/null && loop run > /dev/null || fail "the retry exited non-zero"
  st 'select(.step == "worktree") | .reason' | grep -q '^landing from the kept patch of card' || fail "the retry did not land from the kept patch: $(st 'select(.step == "worktree") | .reason')"
  st 'select(.step == "landed")' | grep -q . || fail "the kept patch, its deleted cases covered, did not land: $(st 'select(.step | IN("blocked", "landed"))')"
}
