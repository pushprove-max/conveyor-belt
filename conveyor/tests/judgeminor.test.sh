#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the review's judge (judged()) on P3 findings, with the control record's rule P3 on and off, and on a
# finding that came back after its fix (what the judge is told of the fix round's findings). judging(),
# judgeone(), jf(), jr() and rev() are judge.test.sh's.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# P3 findings (the control record's rule P3). The issues are P1: an issue with no priority counts as P3, and the rule
# P3 off would leave it unpicked.
MINOR3='[P3] a.txt:1 the name says count but holds a sum. Proof: a.txt:1'
# Bugs: an accepted P3 with the rule P3 on is listed only (as with the rule off) and causes no fix round, or the fix
# is not told it, or is told a P3 the judge declined; the record does not count it as a P3. A NO-GO's fix round and
# the GO after it are t_judgeaccept's: here the review is judged alone (judgeone).
t_minoron() {
  judging "[$(issue 7 2026-01-01 P1)]"
  printf '%s\n' "$MINOR3" '[P3] a.txt:2 odd spacing. Proof: a.txt:2' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review"
  printf '%s\n' 'F1 ACCEPT: the name misleads the next reader. Cost to every card: none' 'F2 DECLINE: its claim is wrong: the spacing is as the style guide has it' > "$STUB/judge.1"
  judgeone 7 "$STUB/review" fix
  [ "$(jf 7 .verdict)" = NO-GO ] && grep -qxF "E1 $MINOR3" "$T/$CASE/cards/c7.fix" && ! grep -q 'odd spacing' "$T/$CASE/cards/c7.fix" \
    || fail "an accepted P3 with the rule P3 on did not make a NO-GO whose fix is told it alone: $(jf 7 .verdict), $(cat "$T/$CASE/cards/c7.fix")"
  [ "$(jf 7 '.counts | tojson')" = '{"P0":0,"P1":0,"P2":0,"P3":1}' ] || fail "the review's counts do not count the accepted P3 alone: $(jf 7 '.counts | tojson')"
}

# Bugs: the judge is left to decline every P3 for causing no wrong result; a P3
# finding the judge declines still costs a fix round, or never reaches the declined list with its reason.
t_minordecline() {
  local l
  judging "[$(issue 7 2026-01-01 P1)]"
  printf '%s\n' "$MINOR3" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review"
  echo 'F1 DECLINE: its claim is wrong: the name holds a count' > "$STUB/judge.1"
  judgeone 7 "$STUB/review"
  for l in 'unusual input, timing or setup that the project really runs is not one. A P3 is minor by its level: do not decline it' \
    'because it causes no wrong result.'; do
    grep -qxF -- "$l" "$STUB/judge-asked" || fail "the judge's prompt does not hold the P3 bar: no line '$l'"
  done
  [ "$(jr 7 | tr '\n' '|')" = "DECLINED: $MINOR3 (judge: its claim is wrong: the name holds a count)|USER-VISIBLE: no|VERDICT: GO|" ] || fail "a declined P3 did not leave the review a GO: $(jr 7)"
  [ "$(jq -r '"\(.by): \(.why): \(.finding)"' "$ST/declined.jsonl")" = "judge: its claim is wrong: the name holds a count: $MINOR3" ] || fail "the declined P3 is not in the declined list with its reason: $(cat "$ST/declined.jsonl" 2>&1)"
}

# Bugs: with the rule P3 off, an accepted P3 alone makes a NO-GO and costs a fix round, is filed as a follow-up, or
# is lost from the card's record (its review line lists and counts it).
t_minoroff() {
  judging "[$(issue 7 2026-01-01 P1)]"
  loop control rules P3=off >/dev/null || fail "control rules P3=off was refused"
  printf '%s\n' "$MINOR3" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review"
  echo 'F1 ACCEPT: the name misleads the next reader. Cost to every card: none' > "$STUB/judge.1"
  judgeone 7 "$STUB/review"
  # A GO is no fix round, and a review that holds no finding files no follow-up.
  [ "$(jf 7 .verdict)" = GO ] || fail "an accepted P3 with the rule P3 off made a NO-GO: $(jr 7)"
  jr 7 | grep -qxF "MINOR: $MINOR3" && [ "$(jf 7 '.counts.P3')" = 1 ] && [ "$(jf 7 '.judge.accepted[0].finding')" = "$MINOR3" ] \
    || fail "the review does not list and count the accepted P3: $(jr 7) $(jf 7 .)"
}

# Bug: card() runs the judge, minor() and the verdict in the wrong order or skips one, so an accepted P3 on a P3-off
# card costs a fix round, a follow-up, or is missing from the landed card's review line. A whole card run, because
# t_minoroff calls those functions in its own order: only card() shows the order they run in on a card.
t_minoroffrun() {
  judging "[$(issue 7 2026-01-01 P1)]"
  loop control rules P3=off >/dev/null || fail "control rules P3=off was refused"
  printf '%s\n' "$MINOR3" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.1"
  echo 'F1 ACCEPT: the name misleads the next reader. Cost to every card: none' > "$STUB/judge.1"
  loop run >/dev/null || fail "run exited non-zero"
  [ "$(rev 7 .result | tr '\n' ' ')" = "GO " ] && [ "$(wc -l < "$STUB/sessions")" = 1 ] && [ -n "$(st 'select(.step == "landed") | .sha')" ] && [ ! -e "$STUB/filed" ] \
    || fail "an accepted P3 with the rule P3 off made a NO-GO, a fix round or a follow-up: $(rev 7 .result | tr '\n' ' '), $(wc -l < "$STUB/sessions") sessions"
  rev 7 .reason | grep -qxF "MINOR: $MINOR3" && [ "$(rev 7 '.counts.P3')" = 1 ] && [ "$(rev 7 '.judge.accepted[0].finding')" = "$MINOR3" ] \
    || fail "the landed card's review line does not list and count the accepted P3: $(rev 7 '[.reason, .counts] | tojson')"
}

# Bug: a line the reviewer itself starts with `MINOR:` is taken as a P3 listed only, so a P1 written so counts for
# nothing and the review is a GO.
t_minorforged() {
  local f='[P1] a.txt:2 exposed token'
  judging "[$(issue 7 2026-01-01 P1)]" off
  loop control rules P3=off >/dev/null || fail "control rules P3=off was refused"
  printf '%s\n' "MINOR: $f" 'USER-VISIBLE: no' 'VERDICT: GO' > "$STUB/review.1"
  judgeone 7 -
  [ "$(jf 7 .verdict)" = NO-GO ] && [ "$(jf 7 '.counts.P1')" = 1 ] && jr 7 | grep -qxF "$f" \
    || fail "a MINOR line the reviewer wrote did not count as the finding it is: $(jr 7) $(jf 7 .)"
}

# Bug: an accepted P3 still open after the last review round lands with no follow-up, or one filed above P3: with the
# test pack's three priorities (P0 to P2, as this project's pack) it was labelled P2. An issue with none of the pack's
# priorities is P3 (LEVEL), so the follow-up has none. The second review repeats it after its fix, and every finding
# is P3, so it is the last review (donewhen.sh repeats()).
t_minorleft() {
  judging "[$(issue 7 2026-01-01 P1)]" off
  printf '%s\n' "$MINOR3" 'USER-VISIBLE: no' 'VERDICT: NO-GO' | tee "$STUB/review.1" > "$STUB/review.2"
  loop run --only 7 >/dev/null || fail "run exited non-zero"
  [ "$(rev 7 .result | tr '\n' ' ')" = "NO-GO NO-GO " ] && [ "$(st 'select(.step == "landed") | .followups | tojson')" = '[100101]' ] \
    || fail "the P3 left after the last review did not land with its follow-up: $(st 'select(.step | IN("review", "landed", "blocked")) | "\(.step) \(.result)"' | tr '\n' ,)"
  [ "$(jq -r '[.title, (.labels | map(.name) | join(" "))] | join(" | ")' "$STUB/filed")" = "$MINOR3 | conveyor-followup bug" ] \
    || fail "the follow-up is not the P3 finding with no priority label (P3): $(cat "$STUB/filed")"
}

# Bugs caught: the judge of the review after a fix round was given no word of the findings that round was told to fix or
# of the reasons it accepted them with, so it ruled on a finding back after its fix as on a new one (#1379); the first
# review's judge, with no fix round before it, was given an empty section; a retried card (c7), which resumes the kept fix
# round of the card before it (c6, whose lines `retry` moved to the retried file), lost the reason, as only its own card
# lines were read. Round 1's accepted finding and its record line are made as a card makes them (judgeone's fields are
# the record's judge; findings.jsonl is rounded()'s line), with no card run.
t_judgeback() {
  local f='[P1] a.txt:2 wrong word. Proof: a.txt:2' wt rd
  judging "[$(issue 7 2026-01-01)]"; wt=$T/$CASE/cards/c7; rd=$wt.rounds
  printf '%s\n' "$f" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.1"
  echo 'F1 ACCEPT: the word is wrong in the change. Cost to every card: none' > "$STUB/judge.1"
  judgeone 7 -
  ! grep -q '^# The findings the last fix round' "$STUB/judge-asked" || fail "the judge of the first review was given a fix round's findings: $(cat "$STUB/judge-asked")"
  jq -c '{card: "c6", issue: 7, step: "review", result: "NO-GO"} + .' "$wt.fields" >> "$ST/retried.jsonl"
  mkdir -p "$rd" && jq -cn --arg l "$f" '{round: 1, id: "E1", line: $l, level: "P1", at: "a.txt:2", words: "wrong word", key: "a.txt:2 wrong word"}' > "$rd/findings.jsonl"
  printf '%s\n' "[P1] [E1] a.txt:2 wrong word. Proof: a.txt:2" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.2"
  echo 'F1 DECLINE: other: the fix changed the word' > "$STUB/judge.2"
  judgeone 7 -
  grep -qxF '# The findings the last fix round was told to fix' "$STUB/judge-asked" \
    && grep -qxF -- "- E1 $f (accepted: the word is wrong in the change)" "$STUB/judge-asked" \
    || fail "the judge of the second review was not given the first round's accepted finding and its reason: $(cat "$STUB/judge-asked")"
}

# Bug caught: JUDGE did not say what an [E<n>] mark means, so the judge did not know a finding was back after its fix, or
# that one it accepted before is declined only when the fix made it untrue.
t_judgebackmeaning() {
  local p
  judging "[$(issue 7 2026-01-01)]"
  printf '%s\n' '[P1] a.txt:2 wrong word. Proof: a.txt:2' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review"
  echo 'F1 ACCEPT: it is wrong. Cost to every card: none' > "$STUB/judge.1"
  judgeone 7 "$STUB/review"
  p=$(tr '\n' ' ' < "$STUB/judge-asked" | tr -s ' ')
  grep -qF 'A finding marked `[E<n>]` is the same finding back after its fix' <<<"$p" \
    && grep -qF 'A finding you accepted before is declined now only when the fix made it untrue: the reason starts with `other` and says what the fix changed' <<<"$p" \
    || fail "the judge's prompt does not say what [E<n>] means: $(grep -n 'E<n>\|accepted before' "$STUB/judge-asked")"
}
