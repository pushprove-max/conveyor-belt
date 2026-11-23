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

# Bugs caught: the first review's judge, with no fix round before it, was given an empty section; a round with no saved
# reason (the judge of the review it fixed failed) took one from the issue's review records, here c6's in the retried
# file, of a patch `retry --fresh` discarded. Round 1 is recorded by rounded() from the first review's numbered() ids
# and judged fields, as cardfix() records it, with no card run; that cardfix() saves the reason is t_judgebackrun's.
t_judgeback() {
  local f='[P1] a.txt:2 wrong word. Proof: a.txt:2' wt
  judging "[$(issue 7 2026-01-01)]"; wt=$T/$CASE/cards/c7
  printf '%s\n' "$f" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.1"
  echo 'exit 1' > "$STUB/judge-cmd"
  judgeone 7 -
  rm -f "$STUB/judge-cmd"
  [ -n "$(jf 7 '.judge.failed // empty')" ] || fail "the first review's judge did not fail: $(jf 7 '.judge | tojson')"
  ! grep -q '^# The findings the last fix round' "$STUB/judge-asked" || fail "the judge of the first review was given a fix round's findings: $(cat "$STUB/judge-asked")"
  [ "$(jf 7 '.judge | has("back")')" = false ] || fail "the first review's line keeps a judge.back with no fix round before it: $(jf 7 '.judge | tojson')"
  mkdir -p "$wt.rounds" && : > "$wt.rounds/1.diff" \
    && ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null \
      && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" && names && ids=$(numbered "$wt") && rounded "$wt" 1 "$ids" "$(cat "$wt.fields")" ) \
    || fail "rounded() could not record fix round 1"
  jq -cn --arg l "$f" '{card: "c6", issue: 7, step: "review", result: "NO-GO", time: "2026-01-02T00:00:00Z",
    judge: {accepted: [{n: 1, finding: $l, reason: "the discarded patch made it"}]}}' >> "$ST/retried.jsonl"
  printf '%s\n' "[P1] [E1] a.txt:2 wrong word. Proof: a.txt:2" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.2"
  echo 'F1 DECLINE: other: the fix changed the word' > "$STUB/judge.2"
  judgeone 7 -
  grep -qxF '# The findings the last fix round was told to fix' "$STUB/judge-asked" && grep -qxF -- "- E1 $f" "$STUB/judge-asked" \
    || fail "the judge of the second review was not given round 1's finding with no reason, when the judge of the review it fixed failed (records: c6 of a discarded patch accepted it): $(cat "$STUB/judge-asked")"
  # Bug caught: the review's line did not keep that section, so the judge replay (lib/replay.sh), with no rounds file to
  # read, gave its judge another card's accepted findings with no E<n> ids.
  jq -e --arg l "- E1 $f" '.judge.back == [$l]' "$wt.fields" >/dev/null \
    || fail "judged() on c7's second review, given E1 of round 1, did not keep that line alone as judge.back: $(jq -c .judge.back "$wt.fields")"
}

# Bug caught: cardfix() did not give rounded() the review's line, so the fix round kept no reason and the judge of the
# next review was told the finding with none. The review is judged (judgeone) and cardfix() is called on its line as
# card() holds it (rline), its fix session stubbed; the next review is then judged, and its judge must be told the reason.
t_judgebackrun() {
  local f='[P1] a.txt:2 wrong word. Proof: a.txt:2'
  judging "[$(issue 7 2026-01-01)]"; FXWT=$T/$CASE/cards/c7
  printf '%s\n' "$f" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.1"
  echo 'F1 ACCEPT: the word is wrong in the change. Cost to every card: none' > "$STUB/judge.1"
  judgeone 7 -
  afterrun "$(issue 7 2026-01-01)" '' \
    'c=c7 n=7 rline=$(cat "$wt.fields") fixed=0 sprompt="" br="" rep=""; session() { (cd "$1" && echo fix2 >> a.txt); }; checked() { :; }
     cardfix; echo "$go $refix" > "$T/$CASE/fix"'
  [ "$(cat "$T/$CASE/fix")" = 'next 1' ] || fail "cardfix() on c7's judged NO-GO ($f) did not go to fix round 1: $(cat "$T/$CASE/fix" "$T/$CASE/run.out" 2>&1)"
  jq -e --arg l "$f" -s 'map(select(.round == 1 and .line == $l)) | length == 1 and .[0].reason == "the word is wrong in the change"' "$FXWT.rounds/findings.jsonl" >/dev/null \
    || fail "cardfix() on c7's review line (judge accepted $f: the word is wrong in the change) did not keep that reason with fix round 1's finding: $(cat "$FXWT.rounds/findings.jsonl" 2>&1)"
  printf '%s\n' "[P1] [E1] $f" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.2"
  echo 'F1 DECLINE: other: the fix changed the word' > "$STUB/judge.2"
  judgeone 7 -
  grep -qxF -- "- E1 $f (accepted: the word is wrong in the change)" "$STUB/judge-asked" \
    || fail "the judge of c7's second review ([P1] [E1] $f), after cardfix() recorded round 1, was not given E1 with the reason the first judge accepted it with: $(cat "$STUB/judge-asked")"
}

# Bug caught: a finding the judge gave no readable line for is kept in .judge.accepted, so the next review's judge was
# told "(accepted: the judge gave no line for this finding that could be read)", as if the judge had accepted it
# (rounded() copied that reason into findings.jsonl). Round 1's judge answers F1 only; F2 is undecided (cost null).
# Fix round 1 is recorded by rounded() alone, with no card run.
t_judgebackundecided() {
  local f1='[P1] a.txt:2 wrong word. Proof: a.txt:2' f2='[P1] b.txt:3 wrong name. Proof: b.txt:3' wt rd
  judging "[$(issue 7 2026-01-01)]"; wt=$T/$CASE/cards/c7; rd=$wt.rounds
  printf '%s\n' "$f1" "$f2" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.1"
  echo 'F1 ACCEPT: the word is wrong in the change. Cost to every card: none' > "$STUB/judge.1"
  judgeone 7 -
  # The record keeps F2 in accepted with cost null and no other mark, as records already written do: the label rests on cost.
  jq -e '.judge.accepted | map(select(.n == 2)) | length == 1 and .[0].cost == null and (.[0] | has("undecided") | not)' "$wt.fields" >/dev/null \
    || fail "the review record does not keep F2, which the judge gave no line for, in accepted with cost null: $(jq -c .judge "$wt.fields")"
  jq -c '{card: "c7", issue: 7, step: "review", result: "NO-GO"} + .' "$wt.fields" >> "$ST/cards.jsonl"
  # fixedbefore() takes the reason only from findings.jsonl: fix round 1 is recorded by rounded() itself, given the
  # review's record line as cardfix() gives it, so a reason rounded() copies for F2 (cost null) reaches the judge.
  ( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null \
    && eval "$(grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")" && names && mkdir -p "$rd" && : > "$rd/1.diff" \
    && rounded "$wt" 1 "$(numbered "$wt")" "$(cat "$wt.fields")" ) || fail "rounded() could not record c7's fix round 1"
  printf '%s\n' "[P1] [E1] $f1" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.2"
  echo 'F1 DECLINE: other: the fix changed the word' > "$STUB/judge.2"
  judgeone 7 -
  grep -qxF -- "- E1 $f1 (accepted: the word is wrong in the change)" "$STUB/judge-asked" && grep -qxF -- "- E2 $f2" "$STUB/judge-asked" \
    || fail "the judge given round 1's findings (review.1: F1 accepted, F2 with no line) did not get F1 accepted and F2 with no label: $(grep '^- E' "$STUB/judge-asked")"
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
