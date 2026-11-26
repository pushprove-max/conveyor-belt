#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: the review's judge (judged()) on P3 findings, with the control record's rule P3 on and off, and on a
# finding that came back after its fix (what the judge is told of the fix round's findings). judging(),
# judgeone(), jf(), jr() and rev() are judge.test.sh's. It also holds what the judge's message and folder hold.
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
# t_minoroff calls those functions in its own order: only card() shows the order they run in on a card. Bug (#1741): the
# card's own review step left the judge no line (reviewlines(), lib/card.sh): the judge of the landed card's review has its line
# before the review's, with its model, seconds and usage.
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
  [ "$(st 'select(.issue == 7 and (.step == "judge" or .step == "review")) | .step' | tr '\n' ' ')" = 'judge review ' ] && [ -n "$(rev 7 '.judge.model // empty')" ] \
    && [ "$(st 'select(.issue == 7 and .step == "judge") | [.result, .of, .model, .sec, .usage] | tojson')" = "$(rev 7 '.judge | ["ok", "review", .model, .sec, .usage] | tojson')" ] \
    || fail "the card run left no judge line before its review line, with the judge's model, seconds and usage: $(st 'select(.issue == 7) | [.step, .result, .model, .sec, .usage, .judge] | tojson')"
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

# What the judge's message and folder hold (#1381). Bugs: the judge is given a copy of the writing method (ste80.md) it
# never needs for one-line reasons; a finding (each one, not only the first) is not followed by the lines it cites with
# those around them, so the judge reads each by a tool call; a small staged change is not in the message whole (or a
# big one is, which costs every call its whole size). A stub Claude judge lists its read-only folder (the one --add-dir
# names) when it is called; the message is $STUB/judge-asked.
judgeinline() { # <the build's shell>: a card with two findings judged, one inside the diff and one outside, with the build as given
  local wt=$T/$CASE/cards/c7 want
  judging "[$(issue 7 2026-01-01)]"
  echo "$1" > "$STUB/build"
  printf '%s\n' '[P1] a.txt:2 wrong word. Proof: a.txt:2' '[P2] b.txt:1 stale line. Proof: b.txt:1' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review"
  printf '%s\n' 'F1 DECLINE: claim wrong: no' 'F2 DECLINE: claim wrong: no' > "$STUB/judge.1"
  echo 'while [ $# -gt 0 ]; do [ "$1" != --add-dir ] || ls "$2" > "$STUB/rv-list"; shift; done' > "$STUB/judge-cmd"
  judgeone 7 "$STUB/review"
  [ "$(cat "$STUB/rv-list")" = staged.diff ] && ! grep -qi 'ste80' "$STUB/judge-asked" \
    || fail "the judge's folder holds more than the staged diff, or its message names the writing method: $(cat "$STUB/rv-list") $(grep -ci ste80 "$STUB/judge-asked")"
  # Each finding is followed by its cited line and those around it: a.txt's whole staged file (line 1 is near line 2).
  want="# The findings
F1 [inside the diff] [P1] a.txt:2 wrong word. Proof: a.txt:2
  Lines at a.txt:2 (the staged change):
$(git -C "$wt" show :a.txt | awk '{ printf "    %d: %s\n", NR, $0 }')
F2 [outside the diff] [P2] b.txt:1 stale line. Proof: b.txt:1
  Lines at b.txt:1 (the staged change):
    1: b"
  [ "$(git -C "$wt" show :a.txt | wc -l)" -ge 2 ] && [ "$(sed -n '/^# The findings$/,$p' "$STUB/judge-asked")" = "$want" ] \
    || fail "the judge's message does not give each finding the lines it cites and those near them: $(sed -n '/^# The findings$/,$p' "$STUB/judge-asked")"
}
t_judgeinlinesmall() {
  judgeinline 'echo two >> a.txt'
  [ "$(awk '/^# The findings$/ { exit } /^# The staged change/ { on = 1 } on' "$STUB/judge-asked")" = "# The staged change (git diff --cached)"$'\n'"$(git -C "$T/$CASE/cards/c7" diff --cached)" ] \
    || fail "a staged change under 400 lines is not in the judge's message whole: $(grep -c . "$STUB/judge-asked") lines"
}
t_judgeinlinebig() {
  judgeinline 'echo two >> a.txt; seq 1 450 > big.txt'
  ! grep -qF '# The staged change' "$STUB/judge-asked" && ! grep -qF 'diff --git' "$STUB/judge-asked" && ! grep -qxF '+450' "$STUB/judge-asked" \
    || fail "a staged change of over 400 lines is in the judge's message"
}

# Bugs (#1734): a finding raised again with only a value of its proof changed (a width: the same claim about the same
# code) was judged as a new finding, so a ruling that it is not this change's (a decline `not this change`) did not
# hold, and a fix round cost $2.50 for it. The judge's rules hold no repeat rule for it, no exception for code a fix
# round changed, and keep the rule of #1522 for a `rare case`, `other` or no kind (judged again from the code). The
# judge's message is read: the judge is a stub, and what it is told is all the engine decides.
t_judgerepeatrules() {
  local p
  judging "[$(issue 7 2026-01-01)]"
  printf '%s\n' '[P2] a.txt:1 the pane cuts the note at 24 columns' '[P2] a.txt:2 two cards at once' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review"
  printf '%s\n' 'F1 DECLINE: not this change: the code before the change cuts it too' 'F2 DECLINE: rare case: two cards seldom meet' > "$STUB/judge.1"
  judgeone 7 "$STUB/review"
  printf '%s\n' '[P2] a.txt:1 the pane cuts the note at 32 columns' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review"; echo 'F1 DECLINE: not this change: a.txt:1 again' > "$STUB/judge.2"
  judgeone 7 "$STUB/review"
  grep -qxF -- '- [P2] a.txt:1 the pane cuts the note at 24 columns (declined: not this change: the code before the change cuts it too) [kind: not this change]' "$STUB/judge-asked" \
    && grep -qxF -- '- [P2] a.txt:2 two cards at once (declined: rare case: two cards seldom meet) [kind: rare case]' "$STUB/judge-asked" \
    || fail "the judge is not given the earlier declines with their kinds: $(grep -n 'declined' "$STUB/judge-asked")"
  p=$(tr '\n' ' ' < "$STUB/judge-asked" | tr -s ' ')
  grep -qF 'is a repeat: the same claim about the same code, with only a value in its proof different (a width, a count, a name, a time).' <<<"$p" \
    && grep -qF 'A repeat of an OUTSIDE ruling, or of a decline of the kind `not this change`, gets its earlier ruling again: answer OUTSIDE (or DECLINE) as before, and the reason starts with the earlier kind and names the earlier finding by its file:line.' <<<"$p" \
    || fail "the judge's rules do not give a repeat of a not-this-change decline or an OUTSIDE ruling its earlier ruling again: $(grep -n 'repeat\|Nothing new' "$STUB/judge-asked")"
  # Bugs caught: the rule reached a `rare case`, `other` or no-kind decline too, which #1522 keeps judged from the code;
  # and a fix round that changed the code the finding names did not make the finding new.
  grep -qF 'When the earlier kind is `rare case`, `other` or none, or a fix round of this card changed the lines the finding names since that ruling (the lines marked `the code before the last fix round` or `the code at the first ruling` show the earlier code), judge the finding from the code, as a new finding.' <<<"$p" \
    || fail "the judge's rules do not judge from the code a repeat of a rare case, other or no-kind decline, or a finding on lines a fix round changed: $(grep -n 'repeat\|rare case' "$STUB/judge-asked")"
}

# Bug (#1734): the judge was not given the findings ruled OUTSIDE on the cards of the issue (only their declines), so it
# could not give a repeat of one its earlier ruling. An earlier card of the issue, a retried card of it, and the card's
# own earlier review hold them in their review lines (judge.outside, and judge.selfheals with outside: true, where an
# OUTSIDE ruling of the effect `self-heals` goes); another issue's, and an accepted self-heals one, do not belong in the list.
t_judgeoutsidelist() {
  local c='{"step":"review","time":"2026-01-01T00:00:00Z","tokens":{"claude":0,"codex":0},"result":"GO","sha":"","reason":""' r
  judging "[$(issue 7 2026-01-01)]"
  # The repo name the engine reads the issue's records by ($REPO), as judgeone() makes the engine shell.
  r=$( export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards; . "$SRC/conveyor.sh" state-dir > /dev/null && printf '%s' "$REPO" ) && [ -n "$r" ] || fail "the engine's repo name could not be read"
  printf '%s\n' "$c,\"card\":\"c-old\",\"issue\":7,\"repo\":\"$r\",\"judge\":{\"outside\":[{\"n\":1,\"finding\":\"[P2] b.txt:1 the pane cuts the note at 24 columns\",\"place\":\"outside\",\"reason\":\"the code before the change cuts it too\",\"effect\":\"harm\"}],\"selfheals\":[{\"n\":2,\"finding\":\"[P3] b.txt:4 a doc typo\",\"place\":\"outside\",\"reason\":\"old\",\"effect\":\"self-heals\",\"outside\":true},{\"n\":3,\"finding\":\"[P3] b.txt:5 an accepted heal\",\"place\":\"inside\",\"reason\":\"real\",\"effect\":\"self-heals\"}]}}" \
    "$c,\"card\":\"c-other\",\"issue\":8,\"repo\":\"$r\",\"judge\":{\"outside\":[{\"n\":1,\"finding\":\"[P2] b.txt:9 another issue's finding\",\"place\":\"outside\",\"reason\":\"old\"}]}}" >> "$ST/cards.jsonl"
  printf '%s\n' "$c,\"card\":\"c-retried\",\"issue\":7,\"repo\":\"$r\",\"judge\":{\"outside\":[{\"n\":1,\"finding\":\"[P3] b.txt:2 a typo\",\"place\":\"outside\",\"reason\":\"old\"}]}}" >> "$ST/retried.jsonl"
  printf '%s\n' '[P2] b.txt:1 the pane cuts the note at 32 columns' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review"
  echo 'F1 OUTSIDE: harm: b.txt:1 again' > "$STUB/judge.1"
  judgeone 7 "$STUB/review"
  [ "$(sed -n '/^# Findings ruled OUTSIDE on the cards of this issue$/,/^$/p' "$STUB/judge-asked")" = "# Findings ruled OUTSIDE on the cards of this issue
- [P2] b.txt:1 the pane cuts the note at 24 columns (ruled OUTSIDE: harm: the code before the change cuts it too)
- [P3] b.txt:4 a doc typo (ruled OUTSIDE: self-heals: old)
- [P3] b.txt:2 a typo (ruled OUTSIDE: old)" ] || fail "the judge is not given the findings ruled OUTSIDE on the issue's cards (also the ones in the self-heals list), or is given another issue's or an accepted heal: $(grep -n 'OUTSIDE\|b.txt' "$STUB/judge-asked")"
}
# The judge's line of a review (reviewlines(), lib/card.sh): called as cardfix() calls it, on what judged() made of the review (judgeone),
# joined to the review's own usage and seconds, with no card run: its lines are in $ST/cards.jsonl. The review line holds no
# verdict (judgeone adds it for its own readers; the records' check refuses it), and each line is taken by the check (recok).
jwrite() { # <result>
  jq -c 'del(.verdict) + {usage: {input: 10, output: 5}, sec: 40}' "$T/$CASE/cards/c7.fields" > "$T/$CASE/line" || fail "the review line could not be made"
  fx_in 'reviewlines c7 7 '"$1"' "$(cat '"$T/$CASE/line"')"'
  [ "$RC" = 0 ] || fail "reviewlines() exited $RC: $(cat "$T/$CASE/run.out")"
  recok "$ST/cards.jsonl" "reviewlines()"
}
jsteps() { st 'select(.step == "judge" or .step == "review") | .step' | tr '\n' ' '; }
# The sum of each field of usage by step over the card's lines: {judge: {...}, review: {...}}, as a reader that adds up usage by step reads it.
jsum() { jq -sc '[.[] | select(.usage | objects) | {s: .step, u: .usage}] | group_by(.s) | map({(.[0].s): (map(.u | to_entries[]) | group_by(.key) | map({(.[0].key): (map(.value) | add)}) | add)}) | add' "$ST/cards.jsonl"; }
# Bugs (#1741): the judge's cost was only inside the review line, so a sum of usage by step left it out; its line comes
# after the review line (the review line is the newest of the pass), or takes the review's usage; the review line loses
# its judge field (replay and the snapshot read it) or its own usage and seconds. Every field of usage is summed, so one
# the review loses (here its output) shows. The line's tokens are the judge's (one CLI's, as {claude: n}) over the
# {claude: 0, codex: 0} every line has (line(), lib/records.sh), which the record check requires.
t_judgeline() {
  local want
  judging "[$(issue 7 2026-01-01)]"; printf '%s\n' '[P1] a.txt:2 wrong word. Proof: a.txt:2' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review"
  echo 'F1 ACCEPT: the word is wrong. Cost to every card: none' > "$STUB/judge.1"
  judgeone 7 "$STUB/review"; jwrite NO-GO; want=$(jf 7 '.judge.usage | tojson')
  [ "$(jsteps)" = 'judge review ' ] && [ "$(jf 7 '.judge.usage.input')" -gt 0 ] \
    && [ "$(st 'select(.step == "judge") | [.result, .of, .model, .effort, .sec, .tokens, .usage, .stats] | tojson')" = "$(jf 7 '.judge | ["ok", "review", .model, .effort, .sec, ({claude: 0, codex: 0} + .tokens), .usage, .stats] | tojson')" ] \
    || fail "the judge has no line of its own before the review line, with the judge's model, seconds and usage: $(st 'select(.step == "judge" or .step == "review") | [.step, .result, .model, .sec, .usage] | tojson')"
  jq -en --argjson s "$(jsum)" --argjson w "$want" '$s == {judge: $w, review: {input: 10, output: 5}}' > /dev/null \
    && [ "$(st 'select(.step == "review") | .judge | tojson')" = "$(jf 7 '.judge | tojson')" ] && [ "$(st 'select(.step == "review") | .sec')" = 40 ] \
    || fail "a sum of usage by step is not the judge's under judge and the review's own ({input: 10, output: 5}) under review, or the review line's judge or seconds changed: $(jsum) $(cat "$ST/cards.jsonl")"
}
# Bug (#1741): a judge that failed (its call ran and exited 1) left no line, so its failure and reason were only inside the review line.
t_judgelinefail() {
  judging "[$(issue 7 2026-01-01)]"; echo "$NOGO" > "$STUB/review"; echo 'exit 1' > "$STUB/judge-cmd"
  judgeone 7 "$STUB/review"; jwrite NO-GO
  [ "$(jsteps)" = 'judge review ' ] && [ -n "$(jf 7 '.judge.failed // empty')" ] \
    && [ "$(st 'select(.step == "judge") | [.result, .reason] | tojson')" = "$(jf 7 '["failed", .judge.failed] | tojson')" ] \
    || fail "a failed judge has no judge line with result failed and its reason: $(cat "$ST/cards.jsonl")"
}
# Bug (#1741): a review with no finding has no judge, and a judge line was written for it.
t_judgelineno() {
  judging "[$(issue 7 2026-01-01)]"; printf '%s\n' 'USER-VISIBLE: no' 'VERDICT: GO' > "$STUB/review"
  judgeone 7 "$STUB/review"; jwrite GO
  [ "$(jsteps)" = 'review ' ] || fail "a review with no finding left a judge line: $(cat "$ST/cards.jsonl")"
}
# Review passes of card c7 as card() runs them (lib/card.sh): cardreview(), then cardfix() for the review line it leaves, <passes>
# times in a row on the one staged change of judging()'s stub build, in the state card() holds at its first review (the engine
# runs with set -u, so each variable afterreview() reads is set). The review session is replaced by one that gives the review in
# $T/$CASE/said (each run is a line of $T/$CASE/reviewruns); the judge (judged()), reusable() and the card's lines are the
# real ones, so what the passes write is what card() writes. A review with no clear verdict blocks in cardreview(), which
# ends the passes.
jpasses() { # <passes>
  FXWT=$T/$CASE/cards/c7
  mkdir -p "$T/$CASE/cards" && git -C "$R" worktree add -q --detach "$FXWT" && (cd "$FXWT" && . "$STUB/build") && git -C "$FXWT" add -A \
    || fail "the card's change could not be staged"
  fx_in 'c=c7 n=7 wt=$FXWT br="" sprompt="" sf="" sk="" pk="" pt="" mode="" kept="" grown=1 fin="" refix="" fixtree="" vmode="" rounds=0 rv=$REVIEW prv="" fixed=0 finend="{}" finrev="" earlier="" rebased="" tfix="" lfix="" privfix="" p1fix="" isfu="" why=""
    issue=$(jq -c ".[0]" "$STUB/issues.json")
    redbrief() { :; }; trialflag() { :; }; lintgate() { return 0; }; began() { :; }
    reviewed() { echo run >> "$T/$CASE/reviewruns"; cp "$T/$CASE/said" "$1.review" && echo "{\"model\":\"m\",\"effort\":\"medium\",\"usage\":{\"input\":7,\"output\":1},\"sec\":9}"; }
    for pass in $(seq 1 '"$1"'); do go=end; cardreview; [ "$go" != end ] || break; go=end; cardfix; [ -z "$go" ] || break; done'
  [ "$RC" = 0 ] || fail "the review pass of c7 did not run (exit $RC): $(cat "$T/$CASE/run.out")"
}
# Bug (#1741): a review that reuses the last one (reusable(): no review session, so no judge) wrote the judge line of the review it
# reuses, or one of its own: its line, with `reused` and no judge field, comes alone. Pass 1 judges a finding (the judge declines it,
# so the review is a GO) and writes its judge line; pass 2 is on the same change, so reusable() finds that review and it stands.
t_judgelinereused() {
  judging "[$(issue 7 2026-01-01)]"; printf '%s\n' '[P1] a.txt:2 wrong word. Proof: a.txt:2' 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$T/$CASE/said"
  echo 'F1 DECLINE: its claim is wrong: the word is right' > "$STUB/judge.1"
  jpasses 2
  [ "$(wc -l < "$T/$CASE/reviewruns")" = 1 ] && [ "$(st 'select(.step == "review") | .reused != null' | tr '\n' ' ')" = 'false true ' ] \
    || fail "the second review pass did not reuse the first review (a review session ran again, or no review line has reused): $(cat "$T/$CASE/reviewruns" 2>&1) $(st 'select(.step == "review") | [.reused, .result] | tojson')"
  [ "$(jsteps)" = 'judge review review ' ] && [ "$(st 'select(.step == "review") | has("judge")' | tr '\n' ' ')" = 'true false ' ] \
    || fail "a review that reuses the last one left a judge line of its own, or the first review has none: $(jsteps) $(st 'select(.step == "judge" or .step == "review") | [.step, .reused, has("judge")] | tojson')"
  recok "$ST/cards.jsonl" "cardreview() and cardfix()"
}
# Bug (#1741): the judge line was written only where cardfix() writes the review line, not where cardreview() writes it for a review
# with no clear verdict (it holds no USER-VISIBLE line, after the judge accepted its finding): that review's judge left no line.
t_judgelinenone() {
  judging "[$(issue 7 2026-01-01)]"; printf '%s\n' '[P1] a.txt:2 wrong word. Proof: a.txt:2' 'VERDICT: NO-GO' > "$T/$CASE/said"
  echo 'F1 ACCEPT: the word is wrong. Cost to every card: none' > "$STUB/judge.1"
  jpasses 1
  [ "$(jsteps)" = 'judge review ' ] && [ "$(st 'select(.step == "review") | .result')" = none ] && [ "$(st 'select(.step == "judge") | .result')" = ok ] \
    && st 'select(.step == "blocked") | .reason' | grep -q 'ended without one clear verdict' \
    || fail "a review with no clear verdict (result none) and a judge did not leave a judge line before its review line and its block: $(st '[.step, .result] | tojson' | tr '\n' ' ')"
  recok "$ST/cards.jsonl" "cardreview()"
}
