#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# timeout: 300
# Engine cases: findings sorted by what their failure does (issue 1559). The judge gives each accepted or outside
# finding a kind, harm or self-heals (judged(), lib/review.sh); a self-heals one goes to the self-heals list
# (healsadd(), lib/followups.sh) in place of a follow-up, and a follow-up card's review gives it no fix round; the
# list is fixed by area in batch cards (healsbatch(), lib/heals.sh); the work filed before the list existed is sorted
# once (healssort()). judging(), judgeone(), jf() and jr() are judge.test.sh's.
# The runner, ../conveyor.test.sh, sources this file after the shared setup (lib.sh) and runs its cases; run alone, this
# file runs its own cases through the runner.
[ "${BASH_SOURCE[0]}" != "$0" ] || CONVEYOR_SHELL_TEST_CASE=${CONVEYOR_SHELL_TEST_CASE:-$(sed -n 's/^t_\([a-z0-9]*\)() {.*/\1/p' "$0" | tr '\n' ' ')} \
  exec bash "$(dirname "$0")/../conveyor.test.sh"

# An open issue <n> of area:engine with <title> and <body>, as gh lists it.
hissue() { # <n> <title> <body> [<label>...]
  jq -cn --argjson n "$1" --arg t "$2" --arg b "$3" '{number: $n, title: $t, body: $b, state: "OPEN", milestone: null, createdAt: "2026-01-01",
    labels: ($ARGS.positional | map({name: .})), authorAssociation: "OWNER"}' --args "${@:4}"
}
# A review follow-up's issue, as followups() files one: its body's "Follow-up depth: 1".
fubody() { printf 'Follow-up to #3 (Conveyor card c20261101T000000-main-3). The last review of that card said NO-GO.\n\nFinding: %s\nWhere: a.txt:1\nFollow-up depth: 1' "$1"; }
heals() { jq -rc "$1" "$ST/selfheals.jsonl" 2>/dev/null; } # <jq filter>: of each line of the self-heals list

# Bugs (issue 1559): on a follow-up card's review a self-heals finding gets a fix round, or is filed as a follow-up
# again, so each fix files the next card; it is lost instead of listed; a harm finding, or a self-heals one whose Proof
# says it was seen in real logs, is moved to the list and never fixed; the kind and the judge's reason are missing
# from the follow-up the harm finding files.
t_healsfollowup() {
  local slow='[P2] a.txt:2 the poll waits one turn more. Proof: a.txt:2' lost='[P1] a.txt:2 drops the record line. Proof: a.txt:2'
  local seen='[P2] a.txt:2 a slot stays over its cap. Proof: seen in the logs of card c5 at 10:02' stale='[P2] b.txt:1 stale text until the next poll. Proof: cat b.txt' is
  is=$(hissue 7 "[P2] a.txt:1 a follow-up" "$(fubody '[P2] a.txt:1 a follow-up')" conveyor-followup bug P2 area:engine)
  judging "[$is]"; printf '%s\n' "$is" > "$T/$CASE/issue7"
  printf '%s\n' "$slow" "$lost" "$seen" "$stale" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review"
  printf '%s\n' 'F1 ACCEPT: self-heals: the next turn picks it up. Cost to every card: none' 'F2 ACCEPT: harm: the line is lost. Cost to every card: none' \
    'F3 ACCEPT: self-heals: the slot frees at the next turn. Cost to every card: none' 'F4 OUTSIDE: self-heals: the next poll corrects it, and b.txt is not the change'"'"'s' > "$STUB/judge.1"
  JUDGEISSUE=$is judgeone 7 "$STUB/review" fix
  grep -qF 'The reason of an ACCEPT or an OUTSIDE starts with that kind, `harm`, `self-heals`, `cleanup`, `already guarded` or' "$STUB/judge-asked" || fail "the judge is not asked for each finding's kind: $(cat "$STUB/judge-asked")"
  grep -qxF "SELFHEALS: $slow (judge: self-heals: the next turn picks it up)" <(jr 7) && grep -qxF "SELFHEALS: $stale (judge: self-heals: the next poll corrects it, and b.txt is not the change's)" <(jr 7) \
    && grep -qxF "$lost" <(jr 7) && grep -qxF "$seen" <(jr 7) || fail "the self-heals findings of a follow-up card's review are not SELFHEALS lines, or a harm one is: $(jr 7)"
  [ "$(jf 7 .verdict)" = NO-GO ] && [ "$(grep -c '^E[0-9]' "$T/$CASE/cards/c7.fix")" = 2 ] && grep -qF "$lost" "$T/$CASE/cards/c7.fix" && grep -qF "$seen" "$T/$CASE/cards/c7.fix" \
    && ! grep -qF 'one turn more' "$T/$CASE/cards/c7.fix" || fail "the fix round of the follow-up card is not told the two harm findings alone: $(cat "$T/$CASE/cards/c7.fix")"
  [ "$(jf 7 '[.judge.selfheals[] | [.finding, .outside]] | tojson')" = "$(jq -cn --arg a "$slow" --arg b "$stale" '[[$a, null], [$b, true]]')" ] \
    && [ "$(jf 7 '[.judge.accepted[] | [.finding, .effect]] | tojson')" = "$(jq -cn --arg a "$lost" --arg b "$seen" '[[$a, "harm"], [$b, "harm"]]')" ] \
    && [ "$(jf 7 '.judge.outside | length')" = 0 ] && [ ! -s "$T/$CASE/cards/c7.outside" ] \
    || fail "the review's judge line does not hold the self-heals findings apart and the harm ones as accepted harm: $(jf 7 .judge)"
  [ "$(heals '[.card, .issue, .area, .finding, .why, .effect, .from] | tojson' | jq -cs .)" = "$(jq -cn --arg a "$slow" --arg b "$stale" \
      '[["c7", 7, "area:engine", $a, "the next turn picks it up", "self-heals", "review"], ["c7", 7, "area:engine", $b, "the next poll corrects it, and b.txt is not the change'"'"'s", "self-heals", "review"]]')" ] \
    || fail "the self-heals list does not hold the two self-heals findings with their card, issue, area and reason: $(cat "$ST/selfheals.jsonl" 2>&1)"
  fx_in 'followups c7 "$(cat "$T/$CASE/issue7")" "$T/$CASE/cards/c7.review"'
  [ "$RC" = 0 ] && [ "$(jq -cs 'map(.title)' "$STUB/filed")" = "$(jq -cn --arg a "${lost:0:200}" --arg b "${seen:0:200}" '[$a, $b]')" ] \
    || fail "the follow-up card's last review did not file its two harm findings alone: $(cat "$T/$CASE/run.out") $(cat "$STUB/filed" 2>&1)"
  jq -rs '.[0].body' "$STUB/filed" | grep -qxF 'Kind: harm: the line is lost' \
    && jq -rs '.[1].body' "$STUB/filed" | grep -qxF 'Kind: harm: the slot frees at the next turn (its Proof says it was seen in real logs or records, so it is harm)' \
    || fail "a follow-up's body does not name its kind and the judge's reason: $(jq -r '.body' "$STUB/filed")"
  # The review's line as the snapshot gives it to the Board (rows.jq): each accepted finding with its kind and reason.
  jq -cn --argjson j "$(jf 7 .judge)" '{card: "c7", issue: 7, step: "review", time: "2026-11-01T00:00:00Z", result: "NO-GO", judge: $j}' > "$T/$CASE/rec"
  fx_in 'rows "$T/$CASE/rec"'
  [ "$(jq -c '[.[0].x.log[] | select(.step == "review") | .judge.kinds[] | [.finding, .effect, .reason]]' "$T/$CASE/run.out" 2>&1)" = "$(jq -cn --arg a "$lost" --arg b "$seen" \
      '[[$a, "harm", "the line is lost"], [$b, "harm", "the slot frees at the next turn (its Proof says it was seen in real logs or records, so it is harm)"]]')" ] \
    || fail "the snapshot's review line does not give the Board each accepted finding's kind and reason: $(cat "$T/$CASE/run.out")"
}

# Bugs (issue 1559): a finding a later review sends to the self-heals list keeps the earlier review's outside ruling,
# so it is both on the list and filed as a follow-up; an earlier self-heals kind outlives a later ruling with no kind,
# so a finding with no kind, which is harm, goes to the list and is never fixed; a listed finding a later review rules
# harm stays on the list, so it is both listed and filed. Three reviews of one card.
t_healslast() {
  local out='[P1] b.txt:1 stale text in b. Proof: b.txt:1' acc='[P2] a.txt:2 a check passes that should fail. Proof: a.txt:2' is
  is=$(issue 8 2026-01-01 P1 area:engine)
  judging "[$is]"
  printf '%s\n' "$out" "$acc" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review"
  printf '%s\n' 'F1 OUTSIDE: harm: b is written wrong, and b.txt is not the change'"'"'s' 'F2 ACCEPT: self-heals: the next run passes. Cost to every card: none' > "$STUB/judge.1"
  printf '%s\n' 'F1 OUTSIDE: self-heals: the next poll corrects b, and b.txt is not the change'"'"'s' 'F2 ACCEPT: the check is wrong. Cost to every card: none' > "$STUB/judge.2"
  printf '%s\n' 'F1 OUTSIDE: harm: b is written wrong, and b.txt is not the change'"'"'s' 'F2 ACCEPT: the check is wrong. Cost to every card: none' > "$STUB/judge.3"
  JUDGEISSUE=$is judgeone 8 "$STUB/review" fix
  jq -e --arg f "$out" 'select(.finding == $f)' "$T/$CASE/cards/c8.outside" >/dev/null && jq -e --arg f "$acc" 'select(.finding == $f and .effect == "self-heals")' "$T/$CASE/cards/c8.effects" >/dev/null \
    || fail "the first review did not keep its outside finding and its accepted self-heals kind: $(cat "$T/$CASE/cards/c8.outside" "$T/$CASE/cards/c8.effects" 2>&1)"
  JUDGEISSUE=$is judgeone 8 "$STUB/review" fix
  fx_in 'tofile "$T/$CASE/cards/c8.review"'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = "$acc" ] \
    || fail "after the second review, the findings to file are not the accepted one with no kind alone (the outside one is on the list): $(cat "$T/$CASE/run.out" "$T/$CASE/cards/c8.outside" "$T/$CASE/cards/c8.effects" 2>&1)"
  [ "$(jq -r --arg f "$out" 'select(.finding == $f) | .from' "$ST/selfheals.jsonl" 2>/dev/null)" = review ] || fail "the outside finding the second review sorted as self-heals is not on the list: $(cat "$ST/selfheals.jsonl" 2>&1)"
  JUDGEISSUE=$is judgeone 8 "$STUB/review" fix
  fx_in 'tofile "$T/$CASE/cards/c8.review"'
  [ "$RC" = 0 ] && [ "$(cat "$T/$CASE/run.out")" = "$acc"$'\n'"$out" ] && [ -z "$(jq -r --arg f "$out" 'select(.finding == $f) | .id' "$ST/selfheals.jsonl" 2>/dev/null)" ] \
    && jq -e --arg f "$out" 'select(.finding == $f and .effect == "harm")' "$T/$CASE/cards/c8.outside" >/dev/null \
    || fail "after the third review ruled the listed outside finding harm, it is not among the findings to file as harm, or is still on the list:$(cat "$T/$CASE/run.out" "$ST/selfheals.jsonl" "$T/$CASE/cards/c8.outside" 2>&1)"
}

# Bugs (issue 1559): a finding a batch card holds already, which a later review of its card rules harm, stays outside
# the change and is filed as a follow-up too, so two cards fix it.
t_healsbatchedharm() {
  local out='[P1] b.txt:1 stale text in b. Proof: b.txt:1' is r
  is=$(issue 8 2026-01-01 P1 area:engine)
  judging "[$is]"
  printf '%s\n' "$out" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review"
  printf '%s\n' 'F1 OUTSIDE: self-heals: the next poll corrects b, and b.txt is not the change'"'"'s' > "$STUB/judge.1"
  printf '%s\n' 'F1 OUTSIDE: harm: b is written wrong, and b.txt is not the change'"'"'s' > "$STUB/judge.2"
  JUDGEISSUE=$is judgeone 8 "$STUB/review" fix
  r=$(loop heals batch area:engine 2>&1) || fail "the batch card of the listed finding could not be filed: $r"
  JUDGEISSUE=$is judgeone 8 "$STUB/review" fix
  [ ! -s "$T/$CASE/cards/c8.outside" ] && [ "$(heals '[.finding, .batched] | tojson')" = "$(jq -cn --arg f "$out" '[$f, 100101]')" ] \
    || fail "the finding batch card 100101 holds, ruled harm by the next review, is kept to be filed as a follow-up too, or left the batch: $(cat "$T/$CASE/cards/c8.outside" "$ST/selfheals.jsonl" 2>&1)"
}

# Bugs (issue 1559): card() does not give the judge its issue, so a follow-up card's self-heals finding still gets a
# fix round and a follow-up; the review's line, its track step or the snapshot loses it, so the Board cannot show
# where it went. A whole card, as only it shows card() passing the issue and the lines the card writes.
t_healscard() {
  local heal='[P2] a.txt:2 the poll waits one turn more. Proof: a.txt:2' out
  judging "[$(hissue 7 '[P2] a.txt:1 a follow-up' "$(fubody '[P2] a.txt:1 a follow-up')" conveyor-followup P2 area:engine)]"
  landed 3 '[7]' >> "$ST/cards.jsonl" # its parent landed and filed it: a follow-up is picked only then
  printf '%s\n' "$heal" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review.1"
  echo 'F1 ACCEPT: self-heals: the next turn picks it up. Cost to every card: none' > "$STUB/judge.1"
  # loop: only a whole card shows card() giving the judge its issue, and the review line and snapshot it leaves
  loop run --only 7 1 > "$T/$CASE/run.log" 2>&1 || fail "run of #7 exited non-zero: $(tail -n 20 "$T/$CASE/run.log")"
  [ "$(rev 7 '[.result, [.judge.selfheals[] | [.finding, .effect]]] | tojson')" = "$(jq -cn --arg f "$heal" '["GO", [[$f, "self-heals"]]]')" ] \
    && [ -z "$(st 'select(.issue == 7 and .step == "fix") | .step')" ] && [ -n "$(st 'select(.issue == 7 and .step == "landed") | .step')" ] && [ ! -s "$STUB/filed" ] \
    || fail "the follow-up card's self-heals finding was fixed or filed, or its review line does not hold it: $(st 'select(.issue == 7) | [.step, .result, (.judge | tojson)] | join(" ")') $(cat "$STUB/filed" 2>&1) $(tail -n 20 "$T/$CASE/run.log")"
  [ "$(heals 'select(.issue == 7) | [.finding, .area] | tojson')" = "$(jq -cn --arg f "$heal" '[$f, "area:engine"]')" ] || fail "the finding is not in the self-heals list: $(cat "$ST/selfheals.jsonl" 2>&1)"
  out=$(loop snapshot --fresh) || fail "snapshot exited non-zero"
  [ "$(jq -c '.landed[] | select(.issue == 7) | [(.rounds | map(.judge | [.selfheals, .go])), (.track.records[] | select(.name | startswith("review")) | .output)]' <<<"$out")" \
    = "$(jq -cn --arg o "SELFHEALS: $heal (judge: self-heals: the next turn picks it up)" '[[[1, true]], $o]')" ] \
    || fail "the snapshot's review does not count the finding for the self-heals list, or its track step does not show its line: $(jq -c '.landed[] | select(.issue == 7) | [.rounds, .track.records]' <<<"$out")"
}

# Bug (issue 1567): the check that healsbrief() puts a moved finding out of the card's scope called the function alone,
# so it passed with the call in card() removed, and the build session still got the finding as part of its scope. Here
# the build session of a card of issue 9 is given the prompt card() makes, with a finding the sort moved from #9.
t_healsbrief() {
  local moved='[P2] a.txt:1 the wait is one turn longer' e
  setup "[$(issue 9 2026-01-01)]"
  fx_in 'healsadd c0-9 9 area:engine "the turn waits" "'"$moved"'" sort'
  e=$(cat "$T/$CASE/run.out")
  [ "$RC" = 0 ] && [ -n "$e" ] || fail "the sort's entry was not written to the self-heals list: $e $(cat "$ST/selfheals.jsonl" 2>&1)"
  # The build session keeps the prompt it is given: card() joins the brief and healsbrief() as the session is made.
  echo 'cp "$STUB/brief" "$STUB/build.brief"; echo two >> a.txt' > "$STUB/build"
  # loop: only a whole card shows the prompt card() gives its build session, which no function of it makes alone
  loop run --only 9 1 > "$T/$CASE/run.log" 2>&1 || fail "run of #9 exited non-zero: $(tail -n 20 "$T/$CASE/run.log")"
  grep -qx '# Findings of this issue that are on the self-heals list or the docs list' "$STUB/build.brief" && grep -qF "$moved (list entry $e)" "$STUB/build.brief" \
    || fail "the build session of #9 is not given its moved finding out of its scope, with its list entry $e: $(cat "$STUB/build.brief" 2>&1)"
}

# Bugs (issue 1559): the first review of a card that is no follow-up stops fixing an in-scope finding the judge sorts
# as self-heals; one still left at the last review is filed as a follow-up, or lost, rather than listed.
t_healsfirst() {
  local slow='[P2] a.txt:2 the poll waits one turn more. Proof: a.txt:2' is
  is=$(issue 8 2026-01-01 P1 area:engine)
  judging "[$is]"; printf '%s\n' "$is" > "$T/$CASE/issue8"
  printf '%s\n' "$slow" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review"
  printf '%s\n' 'F1 ACCEPT: self-heals: the next turn picks it up. Cost to every card: none' > "$STUB/judge.1"
  JUDGEISSUE=$is judgeone 8 "$STUB/review" fix
  [ "$(jf 8 .verdict)" = NO-GO ] && grep -qxF "E1 $slow" "$T/$CASE/cards/c8.fix" && [ ! -s "$ST/selfheals.jsonl" ] \
    || fail "the first review of a card that is no follow-up does not send its self-heals finding to its fix round: $(cat "$T/$CASE/cards/c8.fix" 2>&1) $(cat "$ST/selfheals.jsonl" 2>&1)"
  fx_in 'followups c8 "$(cat "$T/$CASE/issue8")" "$T/$CASE/cards/c8.review"'
  [ "$RC" = 0 ] && [ "$(tail -n 1 "$T/$CASE/run.out")" = '[]' ] && [ ! -s "$STUB/filed" ] \
    || fail "a self-heals finding left at the last review was filed as a follow-up, or the filing failed: $(cat "$T/$CASE/run.out") $(cat "$STUB/filed" 2>&1)"
  [ "$(heals '[.card, .issue, .area, .finding, .from] | tojson')" = "$(jq -cn --arg a "$slow" '["c8", 8, "area:engine", $a, "review"]')" ] \
    || fail "the self-heals finding left at the last review is not in the self-heals list: $(cat "$ST/selfheals.jsonl" 2>&1)"
}

# Bugs (issue 1559): a judge whose answer cannot be read leaves the review as the reviewer wrote it, but an earlier
# round's self-heals ruling still holds: an accepted finding's kind (F1) sends it to the self-heals list at the last
# review, not to a harm follow-up, and an outside one's list entry (F2) stays while the finding is filed too.
t_healsunread() {
  local slow='[P2] a.txt:2 the poll waits one turn more. Proof: a.txt:2' out='[P2] b.txt:1 stale text until the next poll. Proof: b.txt:1' is
  is=$(issue 8 2026-01-01 P1 area:engine)
  judging "[$is]"; printf '%s\n' "$is" > "$T/$CASE/issue8"
  printf '%s\n' "$slow" "$out" 'USER-VISIBLE: no' 'VERDICT: NO-GO' > "$STUB/review"
  printf '%s\n' 'F1 ACCEPT: self-heals: the next turn picks it up. Cost to every card: none' 'F2 OUTSIDE: self-heals: the next poll corrects it, and b.txt is not the change'"'"'s' > "$STUB/judge.1"
  echo 'no decision line' > "$STUB/judge.2"
  JUDGEISSUE=$is judgeone 8 "$STUB/review" fix
  [ "$(heals .finding)" = "$out" ] && grep -qF '"effect":"self-heals"' "$T/$CASE/cards/c8.effects" || fail "the first round did not list F2 and keep F1's kind: $(cat "$ST/selfheals.jsonl" "$T/$CASE/cards/c8.effects" 2>&1)"
  JUDGEISSUE=$is judgeone 8 "$STUB/review" fix
  [ "$(jf 8 .judge.failed)" = 'the answer of the judge holds no decision line that could be read' ] && [ ! -s "$ST/selfheals.jsonl" ] \
    || fail "the unreadable answer did not fail the judge, or F2's entry stayed on the self-heals list: $(jf 8 .judge) $(cat "$ST/selfheals.jsonl" 2>&1)"
  fx_in 'followups c8 "$(cat "$T/$CASE/issue8")" "$T/$CASE/cards/c8.review"'
  [ "$RC" = 0 ] && [ "$(jq -cs 'map(.title)' "$STUB/filed")" = "$(jq -cn --arg a "$slow" --arg b "$out" '[$a, $b]')" ] && [ ! -s "$ST/selfheals.jsonl" ] \
    && [ "$(jq -r '.body' "$STUB/filed" | grep -c '^Kind: harm (the judge gave it no kind')" = 2 ] \
    || fail "the findings the review kept after the unreadable answer were not both filed as harm, or went to the list: $(cat "$T/$CASE/run.out") $(cat "$STUB/filed" "$ST/selfheals.jsonl" 2>&1)"
}

# Bugs (issue 1559): the follow-up cards queued before the rule stay queued whatever they find; a self-heals one
# leaves the queue and its finding is lost; a card whose finding cannot be read leaves the queue; the sort is not logged;
# a card filed under the rule with its kind (its "Kind: harm" line) goes to the judge again, and leaves the queue; a
# card held when the sort runs (as the owner held the follow-ups until the rule went live) is not sorted, and its
# release builds it under the old rule. Card 2, the self-heals one, is held.
t_healssortcards() {
  local p=c20261101T000000-main-3 ids
  judging '[]'; rm -f "$ST/healssort.jsonl"
  fubody '[P1] a.txt:1 loses a card record line. Proof: a.txt:1' > "$T/$CASE/b1"; fubody '[P2] a.txt:1 a slow poll until the next turn. Proof: a.txt:1' > "$T/$CASE/b2"
  printf 'Follow-up to #3 (Conveyor card %s). No finding line.\nFollow-up depth: 1' "$p" > "$T/$CASE/b3"
  printf 'Follow-up to #3 (Conveyor card %s).\n\nFinding: [P2] a.txt:1 a late label. Proof: a.txt:1\nWhere: a.txt:1\nKind: harm: the label is written wrong\nFollow-up depth: 1' "$p" > "$T/$CASE/b4"
  fx_in 'for i in 1 2 3 4; do tcadd "" "finding $i" "$(cat "$T/$CASE/b$i")" "$([ $i != 2 ] || echo held)" "Review follow-up of #3" "[\"conveyor-followup\",\"bug\",\"area:engine\"]" 3 || exit 1; done'
  [ "$RC" = 0 ] && [ "$(jq -c '[.cards[].held]' "$ST/testactions/cards.json")" = '[null,true,null,null]' ] || fail "the queued follow-up cards could not be made, card 2 held: $(cat "$T/$CASE/run.out" "$ST/testactions/cards.json")"
  mapfile -t ids < <(grep -E '^c[0-9]{8}T' "$T/$CASE/run.out")
  # F4 would be the card filed with its kind, were it sent: an answer that moves it shows it was.
  printf '%s\n' 'F1 HARM: a lost record line stays lost.' 'F2 SELF-HEALS: the next turn picks it up.' 'F4 SELF-HEALS: the next poll corrects the label.' > "$STUB/judge.1"
  out=$(loop heals sort 2>&1) || fail "heals sort failed: $out"
  grep -qxF 'F1 [card '"${ids[0]}"'] [P1] a.txt:1 loses a card record line. Proof: a.txt:1' "$STUB/judge-asked" && ! grep -qF "${ids[2]}" "$STUB/judge-asked" && ! grep -qF "${ids[3]}" "$STUB/judge-asked" \
    || fail "the judge was not given the queued cards' findings, or was given the card with none or the card filed with its kind: $(grep '^F' "$STUB/judge-asked")"
  [ "$(jq -c '[.cards[].id]' "$ST/testactions/cards.json")" = "$(jq -cn '[$ARGS.positional[0], $ARGS.positional[2], $ARGS.positional[3]]' --args "${ids[@]}")" ] \
    || fail "the harm card, the card with no finding and the card filed with its kind are not queued alone (${ids[*]}): $(jq -c '[.cards[].id]' "$ST/testactions/cards.json")"
  [ "$(heals '[.card, .issue, .area, .finding, .why, .from] | tojson')" = "$(jq -cn --arg p "$p" '[$p, 3, "area:engine", "[P2] a.txt:1 a slow poll until the next turn. Proof: a.txt:1", "the next turn picks it up.", "sort"]')" ] \
    || fail "the self-heals card's finding is not in the list with the card it came from: $(cat "$ST/selfheals.jsonl" 2>&1)"
  [ "$(jq -c '[.items[] | [.card, .effect, .why, .done]]' "$ST/healssort.jsonl")" = "$(jq -cn '[[$ARGS.positional[0], "harm", "a lost record line stays lost.", true],
      [$ARGS.positional[1], "self-heals", "the next turn picks it up.", true], [$ARGS.positional[2], "harm", "it holds no finding text, so it stays, as harm", true]]' --args "${ids[@]}")" ] \
    || fail "the sort's log does not give each card with its kind and the judge's reason: $(cat "$ST/healssort.jsonl" 2>&1)"
}

# Bugs (issue 1559): an open finding issue judged self-heals stays open, or is closed with no word of where its
# finding went; one judged harm is closed; an issue the owner ordered, or a held one, is sorted; a self-heals finding
# of an audit issue of many is not listed, or the issue closes with a harm finding left in it. An issue held by a span
# of Held (startHeld), or held while the judge reads, is sorted and closed; an issue filed under the rule with its kind
# goes to the judge again; the sort edits the audit issue's body, so an edit made between its read and its write is
# lost; it posts no comment on the audit issue, or one for each of its two moved findings (R1, R3). The brief of the
# audit's card holds it to the findings that moved, as its body and its Done when still name them.
t_healssortissues() {
  local multi e1 e3
  multi=$'Owner\'s words: audit.\n\n## Findings\n- **R1 [P2] `a.sh:1`**: the wait is one turn longer\n  - How: the turn waits.\n- **R2 [P2] `b.sh:2`**: loses a line\n  - How: the line is dropped.'
  multi+=$'\n- **R3 [P3] `c.sh:3`**: a stale badge\n  - How: the next poll corrects it.\n\n## Done when\n- R1 is fixed with a test, or named as fixed.\n- The findings (R1, R2, R3) are each fixed with a test.'
  judging "[$(hissue 20 '[P2] a.txt:1 a stale label until the next poll' "$(fubody '[P2] a.txt:1 a stale label until the next poll. Proof: a.txt:1')" bug P2 area:engine),
    $(hissue 21 '[P1] a.txt:1 drops a kept patch' "$(fubody '[P1] a.txt:1 drops a kept patch. Proof: a.txt:1')" bug P1 area:engine),
    $(hissue 22 'Add a Board panel' 'Owner'"'"'s words: add a panel. Proof: none needed.' bug P1),
    $(hissue 23 'P2/P3 rare-case audit: still-valid findings in the engine' "$multi" bug P2 area:engine),
    $(hissue 24 '[P2] a.txt:1 a held one' "$(fubody '[P2] a.txt:1 a held one. Proof: a.txt:1')" bug P2),
    $(hissue 25 '[P2] a.txt:1 opened while Held' "$(fubody '[P2] a.txt:1 opened while Held. Proof: a.txt:1')" bug P2),
    $(hissue 26 '[P2] a.txt:1 held while the judge reads' "$(fubody '[P2] a.txt:1 held while the judge reads. Proof: a.txt:1')" bug P2),
    $(hissue 27 '[P2] a.txt:1 filed with its kind' "$(fubody '[P2] a.txt:1 filed with its kind. Proof: a.txt:1')"$'\nKind: harm: a record is lost' bug P2)]"
  rm -f "$ST/healssort.jsonl"
  loop control hold 24 >/dev/null || fail "control hold 24 failed"
  jq -c '.startHeld = [{from: 24, to: 25}]' "$ST/control.json" > "$ST/control.new" && mv -f "$ST/control.new" "$ST/control.json" || fail "the span of Held could not be set"
  mkdir -p "$T/$CASE/bin"
  # The wrapper notes each edit in $STUB/edited and writes its --body to the issue: the case sees the sort makes none, and the body stays byte for byte.
  # stub: the shared gh stub drops an issue edit with a body, so a body the sort rewrote would still read as it was
  cat > "$T/$CASE/bin/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$1 $2" = "issue edit" ]; then
  jq -cn --arg a "$*" '{edit: $a}' >> "$STUB/edited"; a=("$@")
  for i in "${!a[@]}"; do [ "${a[$i]}" != --body ] || jq -c --argjson n "$3" --arg b "${a[$((i + 1))]}" 'map(if .number == $n then .body = $b else . end)' "$STUB/issues.json" > "$STUB/issues.new" && mv -f "$STUB/issues.new" "$STUB/issues.json"; done
fi
exec "$STUB/gh" "$@"
EOF
  chmod +x "$T/$CASE/bin/gh"
  # While the judge reads: a line is added at the top of the audit's body (its findings' lines move down one), and #26 is held.
  cat > "$STUB/judge-cmd" <<EOF
jq -c 'map(if .number == 23 then .body = "Depends on: #9\n" + .body else . end)' "\$STUB/issues.json" > "\$STUB/issues.new" && mv -f "\$STUB/issues.new" "\$STUB/issues.json"
jq -c '.held += [26]' "$ST/control.json" > "$ST/control.new" && mv -f "$ST/control.new" "$ST/control.json"
EOF
  # F7 would be #27, filed with its kind, were it sent: an answer that moves it shows it was.
  printf '%s\n' 'F1 SELF-HEALS: the next poll corrects it.' 'F2 HARM: kept work is lost.' 'F3 SELF-HEALS: a longer wait, no wrong result.' 'F4 HARM: data is lost.' \
    'F5 SELF-HEALS: the next poll corrects the label.' 'F6 SELF-HEALS: a later turn shows it.' 'F7 SELF-HEALS: the next poll corrects it.' > "$STUB/judge.1"
  out=$(PATH=$T/$CASE/bin:$PATH loop heals sort 2>&1) || fail "heals sort failed: $out"
  [ "$(grep -c '^F[0-9]' "$STUB/judge-asked")" = 6 ] && grep -qF 'F1 [issue #20]' "$STUB/judge-asked" && grep -qF 'F3 [issue #23] R1 [P2] `a.sh:1`: the wait is one turn longer - How: the turn waits.' "$STUB/judge-asked" \
    && grep -qF 'F6 [issue #26]' "$STUB/judge-asked" && ! grep -qE '#(22|24|25|27)\]' "$STUB/judge-asked" \
    || fail "the judge was not given the one-finding issues and the audit's findings alone, or was given the owner's, a held one or one filed with its kind: $(grep '^F' "$STUB/judge-asked")"
  e20=$(heals 'select(.issue == 20) | .id'); e1=$(heals 'select(.issue == 23 and (.finding | startswith("R1 "))) | .id'); e3=$(heals 'select(.issue == 23 and (.finding | startswith("R3 "))) | .id')
  [ -n "$e20" ] && [ "$(cat "$STUB/closed")" = 20 ] && grep -qF "It is now entry $e20 of the self-heals list" "$STUB/close-comments" && [ -z "$(heals 'select(.issue == 26) | .id')" ] \
    || fail "the self-heals issue #20 is not the one closed, its comment does not name its list entry ($e20), or #26, held during the sort, went to the list: $(cat "$STUB/closed" "$STUB/close-comments" "$ST/selfheals.jsonl" 2>&1)"
  # Its body is the one the judge read, with the line added while it read: byte for byte, after the sort.
  [ -n "$e1" ] && [ -n "$e3" ] && [ ! -e "$STUB/edited" ] && [ "$(grep -c '^23 ' "$STUB/comments")" = 1 ] && grep '^23 --body ' "$STUB/comments" | grep -qF "R1 as $e1, R3 as $e3." \
    && ! grep -qx 23 "$STUB/closed" && jq -e --arg b "Depends on: #9"$'\n'"$multi" 'any(.[]; .number == 23 and .body == $b)' "$STUB/issues.json" >/dev/null \
    || fail "sorting the audit issue #23 edited its body, did not post exactly one comment naming R1's and R3's entries ($e1, $e3), or closed it with R2 left: $(cat "$STUB/edited" "$STUB/comments" "$STUB/closed" 2>&1) $(jq -c '.[] | select(.number == 23) | .body' "$STUB/issues.json")"
  [ "$(jq -c '[.items[] | [.issue, .effect, .moved, .closed, .done]]' "$ST/healssort.jsonl")" = "$(jq -cn --arg e1 "$e1" --arg e3 "$e3" '[[20, "self-heals", null, null, true], [21, "harm", null, null, true],
      [23, "harm", null, null, true], [26, "self-heals", null, null, false], [23, "self-heals", null, null, true], [23, "self-heals", null, null, true], [23, null, [$e1, $e3], false, true]]')" ] \
    || fail "the sort's log does not give each issue with its kind, #26 left as held, and the audit issue's finding moved and the issue left open: $(cat "$ST/healssort.jsonl" 2>&1)"
  # A second sort sends the audit's moved finding to the judge no more: its body still holds it.
  rm -f "$STUB/judge-asked"; printf '%s\n' 'F1 HARM: kept work is lost.' 'F2 HARM: data is lost.' 'F3 HARM: data is lost.' > "$STUB/judge.2"
  out=$(PATH=$T/$CASE/bin:$PATH loop heals sort 2>&1) || fail "the second heals sort failed: $out"
  ! grep -qE 'the wait is one turn longer|a stale badge' "$STUB/judge-asked" && [ "$(grep -c '^23 ' "$STUB/comments")" = 1 ] \
    || fail "the second sort sent the moved findings of #23 to the judge again, or commented on #23 again: $(grep '^F' "$STUB/judge-asked") $(cat "$STUB/comments")"
  # The brief of #23's card (healsbrief(), lib/issues.sh) puts its moved findings out of its scope.
  fx_in 'healsbrief 23'
  grep -qx '# Findings of this issue that are on the self-heals list or the docs list' "$T/$CASE/run.out" && grep -qF "R1 [P2] \`a.sh:1\`: the wait is one turn longer - How: the turn waits. (list entry $e1)" "$T/$CASE/run.out" \
    && grep -qF "(list entry $e3)" "$T/$CASE/run.out" && ! grep -qF 'loses a line' "$T/$CASE/run.out" \
    || fail "healsbrief 23 does not put R1 and R3 out of the card's scope with their entries, or names R2: $(cat "$T/$CASE/run.out")"
}

# Bugs (issue 1559): a one-finding issue whose Proof is edited while the judge reads it is closed on the ruling of the
# old text; one edited as the sort closes it stays closed on that ruling; an audit finding whose lines under its first
# line are edited meanwhile moves to the list, the new text with it; an audit whose close fails keeps its findings and
# has them on the list too.
t_healssortchanged() {
  local a=$'## Findings\n- **R1 [P2] `a.sh:1`**: the wait is one turn longer\n  - How: the turn waits.'
  judging "[$(hissue 30 '[P2] a.txt:1 a stale label until the next poll' "$(fubody '[P2] a.txt:1 a stale label until the next poll. Proof: a.txt:1')" bug P2 area:engine),
    $(hissue 31 'Audit: findings in the engine' "$a"$'\n- **R2 [P2] `b.sh:2`**: loses a line\n  - How: the line is dropped.' bug P2 area:engine),
    $(hissue 32 'Audit: one finding in the engine' "$a" bug P2 area:engine),
    $(hissue 33 '[P2] a.txt:3 a late label until the next poll' "$(fubody '[P2] a.txt:3 a late label until the next poll. Proof: a.txt:3')" bug P2 area:engine)]"
  rm -f "$ST/healssort.jsonl"; mkdir -p "$T/$CASE/bin"
  # The gh wrapper below notes each edit in $STUB/edited, fails the close of #32, and edits #33's Proof as it closes it.
  local edit33="'map(if .number == 33 then .body |= sub(\"Proof: a.txt:3\"; \"Proof: a.txt:4\") else . end)'"
  # stub: the shared gh stub cannot fail a close or change an issue as it closes
  printf '#!/usr/bin/env bash\n[ "$1 $2" != "issue edit" ] || jq -cn --arg a "$*" "{edit: \\$a}" >> "$STUB/edited"\n[ "$1 $2 $3" != "issue close 32" ] || exit 1\n[ "$1 $2 $3" != "issue close 33" ] || { jq -c %s "$STUB/issues.json" > "$STUB/issues.new" && mv -f "$STUB/issues.new" "$STUB/issues.json"; }\nexec "$STUB/gh" "$@"\n' "$edit33" > "$T/$CASE/bin/gh" && chmod +x "$T/$CASE/bin/gh"
  # While the judge reads: #30's Proof and the How line of #31's R1 are edited.
  cat > "$STUB/judge-cmd" <<'EOF'
jq -c 'map(if .number == 30 then .body |= sub("Proof: a.txt:1"; "Proof: a.txt:9") elif .number == 31 then .body |= sub("the turn waits[.]"; "the turn waits, and a record line is lost.") else . end)' "$STUB/issues.json" > "$STUB/issues.new" && mv -f "$STUB/issues.new" "$STUB/issues.json"
EOF
  printf '%s\n' 'F1 SELF-HEALS: the next poll corrects it.' 'F2 SELF-HEALS: a longer wait, no wrong result.' 'F3 HARM: data is lost.' 'F4 SELF-HEALS: a longer wait, no wrong result.' \
    'F5 SELF-HEALS: the next poll corrects it.' > "$STUB/judge.1"
  out=$(PATH=$T/$CASE/bin:$PATH loop heals sort 2>&1) || fail "heals sort failed: $out"
  grep -qF 'F2 [issue #31] R1 [P2] `a.sh:1`: the wait is one turn longer - How: the turn waits.' "$STUB/judge-asked" && grep -qF 'F4 [issue #32]' "$STUB/judge-asked" \
    || fail "the judge was not given the audits' findings as they were before the edit: $(grep '^F' "$STUB/judge-asked")"
  [ "$(cat "$STUB/closed" 2>&1)" = 33 ] && [ "$(cat "$STUB/reopened" 2>&1)" = 33 ] && [ ! -e "$STUB/edited" ] && [ ! -s "$ST/selfheals.jsonl" ] \
    || fail "an issue edited while the judge read it was closed, #33 edited as it closed was not opened again, a body was edited, or a finding left in its issue is on the list: $(cat "$STUB/closed" "$STUB/reopened" "$STUB/edited" "$ST/selfheals.jsonl" 2>&1)"
  [ "$(jq -c '[.items[] | [.issue, .effect, .moved, .closed, .done]]' "$ST/healssort.jsonl")" = '[[30,"self-heals",null,null,false],[31,"harm",null,null,true],[33,"self-heals",null,null,false],[31,"self-heals",null,null,false],[31,null,[],false,false],[32,"self-heals",null,null,false],[32,null,[],false,false]]' ] \
    || fail "the sort's log does not give #30, #31's R1 and #33 as left for their edits, and #32 as not closed with its finding left in it: $(cat "$ST/healssort.jsonl" 2>&1)"
}

# Bugs (issue 1559): an area's batch card holds another area's entries, or none of their findings; a second ask files
# a second card for the same entries; the snapshot still shows the batched entries, or only the newest 200 of an area
# a batch card would file whole; a batch card shut before it lands keeps its entries, so no later batch card holds them.
# A batch card holds an entry whose card has not landed (a4, of card c7, in flight), so it is built on main before
# the code its finding names is there. A shut batch card given back by `retry` builds its scope again while the next
# batch card of its area holds the same entries (retried after that card was filed), or no longer holds them (retried
# first), so a later batch card takes them too.
t_healsbatch() {
  judging '[]'; rm -f "$ST/healssort.jsonl"
  for x in 'a1 c5 area:engine [P2] a.sh:1 a slow poll' 'a2 c5 area:engine [P3] b.sh:2 a stale label' 'a3 c5 area:board [P2] c.js:3 a late redraw' 'a4 c7 area:engine [P2] d.sh:4 a late line'; do
    read -r id c a f <<<"$x"
    jq -cn --arg id "h00000000$id" --arg c "$c" --arg a "$a" --arg f "$f" '{id: $id, time: "2026-11-2\(if $c == "c7" then 1 else 0 end)T00:00:00Z", card: $c, issue: ($c[1:] | tonumber), repo: "r", area: $a, finding: $f, why: "it heals", effect: "self-heals", from: "review"}' >> "$ST/selfheals.jsonl"
  done
  landed 7 | jq -c '.card = "c7" | .step = "picked"' >> "$ST/cards.jsonl" # c7 is in flight: a4 waits for it
  jq -cn 'range(200) | {id: "h0000000b\(1000 + .)", time: "2026-11-01T00:00:00Z", card: "c6", issue: 6, repo: "r", area: "area:board", finding: "[P3] d.js:\(.) an old redraw", why: "it heals", effect: "self-heals", from: "review"}' >> "$ST/selfheals.jsonl"
  out=$(loop heals batch area:engine 2>&1) || fail "heals batch failed: $out"
  [ "$(jq -c '[.title, (.labels | map(.name))]' "$STUB/filed")" = '["Self-heals batch: 2 findings of area:engine",["bug","P2","area:engine"]]' ] \
    && jq -r .body "$STUB/filed" | grep -qxF -- '- [P2] a.sh:1 a slow poll' && jq -r .body "$STUB/filed" | grep -qxF -- '- [P3] b.sh:2 a stale label' \
    && jq -r .body "$STUB/filed" | grep -qF 'list entry h00000000a2' && ! jq -r .body "$STUB/filed" | grep -qE 'c\.js|d\.sh' \
    || fail "the batch card of area:engine does not hold that area's two entries whose card ended alone: $(cat "$STUB/filed" 2>&1)"
  [ "$(heals 'select(.card != "c6") | [.id, .batched]' | jq -cs .)" = '[["h00000000a1",100101],["h00000000a2",100101],["h00000000a3",null],["h00000000a4",null]]' ] \
    || fail "the entries filed are not marked with their batch card, or a4, whose card is in flight, is: $(head -n 4 "$ST/selfheals.jsonl")"
  out=$(loop heals batch area:engine 2>&1); rc=$?
  [ "$rc" = 2 ] && [ "$(wc -l < "$STUB/filed")" = 1 ] && grep -qF '(1 wait for theirs to land or close)' <<<"$out" \
    || fail "a second batch of area:engine filed again, or did not exit 2 ($rc) naming the entry that waits for its card: $out"
  out=$(loop snapshot --fresh) || fail "snapshot exited non-zero"
  [ "$(jq -c '.selfheals | [(.entries | length), .entries[0].id, (.entries | map(select(.area == "area:engine") | .id)), .areas, .sorted]' <<<"$out")" \
    = '[202,"h00000000a4",["h00000000a4"],[{"area":"area:board","count":201},{"area":"area:engine","count":1}],null]' ] \
    || fail "the snapshot's self-heals list is not every entry no batch card holds, newest first: $(jq -c '.selfheals | [(.entries | length), .areas, .sorted]' <<<"$out")"
  # The batch card #100101 is blocked, then shut by the owner before it lands.
  landed 100101 | jq -c '(.step = "picked"), (.step = "blocked" | .result = "blocked" | .reason = "build: it failed")' >> "$ST/cards.jsonl"
  out=$(loop shut 100101 2>&1) || fail "shut of the batch card #100101 failed: $out"
  [ "$(heals 'select(.card == "c5" and .area == "area:engine") | .batched' | jq -cs .)" = '[null,null]' ] \
    || fail "the entries of the batch card shut before it landed are still held by it: $(head -n 3 "$ST/selfheals.jsonl")"
  # Retried at once, it holds its entries again; blocked and shut again, its area's next batch card #100102 takes them,
  # and a retry of #100101 is refused.
  out=$(loop retry 100101 2>&1) && [ "$(heals 'select(.card == "c5" and .area == "area:engine") | .batched' | jq -cs .)" = '[100101,100101]' ] \
    || fail "retry of the shut batch card #100101 failed, or did not hold its entries again: $out $(head -n 3 "$ST/selfheals.jsonl")"
  landed 100101 | jq -c '.card = "c1-100101" | (.step = "picked"), (.step = "blocked" | .result = "blocked" | .reason = "build: it failed")' >> "$ST/cards.jsonl"
  out=$(loop shut 100101 2>&1) && out=$(loop heals batch area:engine 2>&1) && [ "$(wc -l < "$STUB/filed")" = 2 ] || fail "the area's next batch card was not filed: $out"
  out=$(loop retry 100101 2>&1) && fail "retry of the shut batch card #100101, whose entries #100102 holds now, was not refused: $out"
  grep -qF 'held by the batch card 100102 now' <<<"$out" && [ "$(heals 'select(.card == "c5" and .area == "area:engine") | .batched' | jq -cs .)" = '[100102,100102]' ] \
    && [ -n "$(st 'select(.card == "c1-100101" and .step == "closed") | .card')" ] \
    || fail "the refused retry of #100101 does not name #100102, moved its entries, or gave the card back: $out $(head -n 3 "$ST/selfheals.jsonl")"
}

# Bugs (issue 1559): a `run` never sorts the follow-ups queued before the rule, and a loop's first turn picks one
# before the sort it started has read it, so a self-heals follow-up is built after all.
t_healsloop() {
  local id
  judging '[]'; rm -f "$ST/healssort.jsonl"
  fx_in 'tcadd "" "finding 1" "$(fubody "[P2] a.txt:1 a slow poll until the next turn. Proof: a.txt:1")" "" "Review follow-up of #3" "[\"conveyor-followup\",\"bug\",\"area:engine\"]" 3'
  [ "$RC" = 0 ] || fail "the queued follow-up card could not be made: $(cat "$T/$CASE/run.out")"
  id=$(cat "$T/$CASE/run.out")
  echo 'F1 SELF-HEALS: the next turn picks it up.' > "$STUB/judge.1"
  # loop: only a whole run shows its first turn's pick waiting for the sort that turn starts
  loop run 1 > "$T/$CASE/run.log" 2>&1
  [ -s "$ST/healssort.jsonl" ] && [ "$(heals '[.card, .from] | tojson')" = '["c20261101T000000-main-3","sort"]' ] \
    && [ -z "$(st 'select(.step == "picked") | .card')" ] && ! jq -e --arg c "$id" 'any(.cards[]?; .id == $c)' "$ST/testactions/cards.json" >/dev/null \
    || fail "the run picked the queued self-heals follow-up $id before its sort, or did not sort it: $(st '[.step, .card] | join(" ")') $(cat "$ST/selfheals.jsonl" 2>&1) $(tail -n 20 "$T/$CASE/run.log")"
}

# Bugs (issue 1559): a sort that cannot read the open issues still logs a run, so the loop never sorts again and the
# open finding issues stay unsorted. healsonce() as the loop's turn calls it, once the issues can be read again.
t_healsretry() {
  judging "[$(hissue 20 '[P2] a.txt:1 a stale label until the next poll' "$(fubody '[P2] a.txt:1 a stale label until the next poll. Proof: a.txt:1')" bug P2 area:engine)]"
  rm -f "$ST/healssort.jsonl"; echo 'exit 1' > "$STUB/list-cmd"
  out=$(loop heals sort 2>&1) && fail "a sort that could not read the open issues exited 0: $out"
  [ ! -e "$ST/healssort.jsonl" ] && [ ! -e "$STUB/judges" ] || fail "a sort that could not read the open issues logged a run, or asked the judge: $(cat "$ST/healssort.jsonl" 2>&1) $out"
  rm -f "$STUB/list-cmd"; echo 'F1 SELF-HEALS: the next poll corrects it.' > "$STUB/judge.1"
  fx_in 'sorter=""; healsonce; echo "first $?"; wait; healsonce; echo "then $?"'
  [ "$(grep -E '^(first|then) ' "$T/$CASE/run.out")" = $'first 1\nthen 0' ] && [ "$(cat "$STUB/closed" 2>&1)" = 20 ] \
    || fail "the loop's next turn did not sort again after the sort that could not read the issues, or held the pick after its sort: $(cat "$T/$CASE/run.out" "$STUB/closed" 2>&1)"
}

# Whether a process under <pid> is a flock on a descriptor of 10 or more: the cards lock, taken with `exec {fd}>>`, gets
# one; the list's lock is `flock 9`, so the batch's first and uncontended flock is not taken for a wait on the cards.
waits_on_a_lock() { # <pid>
  local k
  for k in $(below "$1"); do
    [[ $(ps -o args= -p "$k" 2>/dev/null) =~ ^flock\ [0-9]{2,}$ ]] && return 0
  done
  return 1
}

# Bugs (issue 1566): with followupissues off, a batch card with no GitHub issue took the self-heals list's lock, then the
# lock of the Tests page's cards (tcadd()), while testpick() holds the second and its retry (healstake()) waits for the
# first: each waited for the other, and only a time limit (the pick's, lockedfor(), or the Board's call) ended it. This
# case plays testpick(): it holds the cards lock, starts the batch, and waits until the batch is blocked on the cards
# lock (a flock process of its own) or holds the list's lock, which it must not while it waits for the cards.
# A real `heals batch` and a real lock: only two processes show the order the locks are taken in.
t_healsbatchlock() {
  local out=$T/$CASE/batch.out fd bp held=no
  setup '[]'
  jq -cn '{id: "h00000000a1", time: "2026-11-20T00:00:00Z", card: "c5", issue: 5, repo: "r", area: "area:engine", finding: "[P2] a.sh:1 a slow poll", why: "it heals", effect: "self-heals", from: "review"}' >> "$ST/selfheals.jsonl"
  loop control rules followupissues=off > /dev/null || fail "control rules followupissues=off was refused"
  mkdir -p "$ST/testactions"
  exec {fd}>>"$ST/testactions/cards.json.lock"; flock "$fd"
  # shellcheck disable=SC2016 # the inner script reads its own arguments
  timeout 30 bash -c 'CONVEYOR_MAIN=$1 CONVEYOR_CARDS=$2 exec bash "$3" heals batch area:engine' _ "$R" "$T/$CASE/cards" "$SRC/conveyor.sh" > "$out" 2>&1 {fd}>&- & bp=$! # {fd}>&-: the batch must not hold the lock open, or closing it here frees nothing
  wait_until "waits_on_a_lock $bp || ! flock -n '$ST/selfheals.jsonl.lock' true" || { exec {fd}>&-; fail "the batch neither waited for the cards lock nor took the list's"; }
  flock -n "$ST/selfheals.jsonl.lock" true || held=yes
  exec {fd}>&-
  wait "$bp"; rc=$?; [ $rc = 0 ] || fail "the batch card with no GitHub issue was not filed (exit $rc): $(cat "$out")"
  [ "$held" = no ] && [ "$(heals '.batched != null')" = true ] && [ "$(jq -c '.cards | length' "$ST/testactions/cards.json")" = 1 ] \
    || fail "a batch card with no GitHub issue held the list's lock (held: $held) while it waited for the cards lock, so a pick holding the cards lock never got the list's: $(cat "$out" "$ST/selfheals.jsonl" "$ST/testactions/cards.json" 2>&1)"
}

# Bug (issue 1565): `retry` moves a blocked card's lines to the retried file, and the issue's next card has no line until
# it is picked, so in that gap a review finding of the issue counted as ended and a batch card was built on main
# before the source card's code landed. The issue stays busy until a card of it has landed.
t_healsretried() {
  local out
  judging '[]'; rm -f "$ST/healssort.jsonl"
  jq -cn '{id: "h00000000r1", time: "2026-11-20T00:00:00Z", card: "c7", issue: 7, repo: "r", area: "area:engine", finding: "[P2] d.sh:4 a late line", why: "it heals", effect: "self-heals", from: "review"}' >> "$ST/selfheals.jsonl"
  landed 7 | jq -c '.card = "c7" | (.step = "picked"), (.step = "blocked" | .result = "blocked" | .reason = "build: it failed")' >> "$ST/cards.jsonl"
  out=$(loop retry 7 2>&1) || fail "retry of the blocked card of #7 failed: $out"
  [ -z "$(st 'select(.issue == 7) | .card')" ] || fail "retry left a line of #7 in the card records, so the gap this case needs is not there: $(st '[.step, .card] | join(" ")')"
  out=$(loop heals batch area:engine 2>&1); rc=$?
  [ "$rc" = 2 ] && [ ! -e "$STUB/filed" ] && [ "$(heals '.batched')" = null ] \
    || fail "a batch card was filed (rc $rc) for the finding of #7, whose retried card has not landed: $out"
  landed 7 >> "$ST/cards.jsonl" # the retried issue's next card has landed
  out=$(loop heals batch area:engine 2>&1) && [ "$(heals '.batched')" = 100101 ] \
    || fail "the batch card was not filed once the retried card of #7 landed: $out $(cat "$ST/selfheals.jsonl")"
}

# Bug (issue 1565, review of its first fix): a main-red fix card (no GitHub issue) given back by `retry` has no line in
# the card records until its next pick, and a check of issue numbers alone let the finding its review wrote count as
# ended, so a batch card was built on main before the fix landed. The card is busy while the main-red record names it,
# and, once the loop picks its next card (the record names that card then, the same commit), until that card has landed.
t_healsretriedred() {
  local out old=c20261120T000000-r-0 new=c20261120T010000-r-0
  judging '[]'; rm -f "$ST/healssort.jsonl"
  jq -cn --arg c "$old" '{id: "h00000000r2", time: "2026-11-20T00:00:00Z", card: $c, issue: 0, repo: "r", area: "area:engine", finding: "[P1] d.sh:4 a late line", why: "it drops a line", effect: "harm", from: "review"}' >> "$ST/selfheals.jsonl"
  landed 0 | jq -c --arg c "$old" '.card = $c | (.step = "picked" | .mainRed = "abc1234"), (.step = "blocked" | .result = "blocked" | .reason = "build: it failed")' >> "$ST/cards.jsonl"
  jq -cn --arg c "$old" '{reds: [{sha: "abc1234", cases: [{case: "x: y", file: "x.test.sh"}], card: $c}]}' > "$ST/mainred.json"
  out=$(loop retry "$old" 2>&1) || fail "retry of the blocked main-red card failed: $out"
  [ -z "$(st "select(.card == \"$old\") | .card")" ] || fail "retry left a line of $old in the card records, so the gap this case needs is not there: $(st '[.step, .card] | join(" ")')"
  out=$(loop heals batch area:engine 2>&1); rc=$?
  [ "$rc" = 2 ] && [ ! -e "$STUB/filed" ] && [ "$(heals '.batched')" = null ] \
    || fail "a batch card was filed (rc $rc) for the finding of $old, a main-red card whose retried card has not been picked: $out"
  # The loop picks the next card (redpick(): the record names it, and not the given-back card) and it is in flight.
  jq -c --arg c "$new" '.reds[0].card = $c' "$ST/mainred.json" > "$ST/mainred.new" && mv "$ST/mainred.new" "$ST/mainred.json"
  landed 0 | jq -c --arg c "$new" '.card = $c | .step = "picked" | .mainRed = "abc1234"' >> "$ST/cards.jsonl"
  out=$(loop heals batch area:engine 2>&1); rc=$?
  [ "$rc" = 2 ] && [ ! -e "$STUB/filed" ] && [ "$(heals '.batched')" = null ] \
    || fail "a batch card was filed (rc $rc) for the finding of $old once its replacement $new was picked, before it landed: $out"
  landed 0 | jq -c --arg c "$new" '.card = $c' >> "$ST/cards.jsonl" # the replacement has landed
  out=$(loop heals batch area:engine 2>&1) && [ "$(heals '.batched')" = 100101 ] \
    || fail "the batch card was not filed once the replacement $new of the main-red card landed: $out $(cat "$ST/selfheals.jsonl")"
}

# Bug (issue 1565, review of its second fix): a Tests page card given back by `retry` is busy while its record names
# it, but the check failed whole, and the card counted as ended, when the project has no main-red record (mainred.json is
# written by the first main-red commit): the card's entry was batched before its next pick.
t_healsretriedtests() {
  local out c=c20261120T000000-r-0
  judging '[]'; rm -f "$ST/healssort.jsonl" "$ST/mainred.json"; mkdir -p "$ST/testactions"
  jq -cn --arg c "$c" '{id: "h00000000r3", time: "2026-11-20T00:00:00Z", card: $c, issue: 0, repo: "r", area: "area:engine", finding: "[P1] d.sh:4 a late line", why: "it drops a line", effect: "harm", from: "review"}' >> "$ST/selfheals.jsonl"
  landed 0 | jq -c --arg c "$c" '.card = $c | (.step = "picked" | .testFile = "x.test.sh"), (.step = "blocked" | .result = "blocked" | .reason = "build: it failed")' >> "$ST/cards.jsonl"
  jq -cn --arg c "$c" '{cards: [{id: "t1", card: $c}]}' > "$ST/testactions/cards.json"
  out=$(loop retry "$c" 2>&1) || fail "retry of the blocked Tests page card failed: $out"
  [ -z "$(st "select(.card == \"$c\") | .card")" ] || fail "retry left a line of $c in the card records, so the gap this case needs is not there: $(st '[.step, .card] | join(" ")')"
  out=$(loop heals batch area:engine 2>&1); rc=$?
  [ "$rc" = 2 ] && [ ! -e "$STUB/filed" ] && [ "$(heals '.batched')" = null ] \
    || fail "a batch card was filed (rc $rc) for the finding of $c, a Tests page card whose retried card has not been picked (no mainred.json: $(ls "$ST/mainred.json" 2>&1)): $out"
}

# Bug (issue 1565, review of its second fix): the retried file went to jq as one argument, and Linux refuses one over
# 128 KiB, so with a long retry history no batch card could be filed at all. 2,000 retried cards with card ids of the
# real c<time>-<repo>-<issue> form: healsbatch() cuts each line to {card, issue, red}, and that cut is over 128 KiB too.
t_healsretriedbig() {
  local out
  judging '[]'; rm -f "$ST/healssort.jsonl"
  jq -cn '{id: "h00000000r4", time: "2026-11-20T00:00:00Z", card: "c5", issue: 5, repo: "r", area: "area:engine", finding: "[P2] d.sh:4 a late line", why: "it heals", effect: "self-heals", from: "review"}' >> "$ST/selfheals.jsonl"
  jq -cn 'range(2000) | {card: "c20261101T\(100000 + .)-conveyor-belt-\(1000 + .)", issue: (1000 + .), step: "blocked", time: "2026-11-01T00:00:00Z", tokens: {claude: 0, codex: 0}, result: "blocked", sha: "", reason: "build: it failed, and this line is long enough that the file is over the limit of one argument"}' > "$ST/retried.jsonl"
  [ "$(jq -c '{card, issue, red: null}' "$ST/retried.jsonl" | sort -u | wc -c)" -gt 131072 ] \
    || fail "the retried lines of this case, cut as healsbatch() cuts them, are not over 128 KiB, so one jq argument still takes them"
  out=$(loop heals batch area:engine 2>&1) && [ "$(heals '.batched')" = 100101 ] \
    || fail "the batch card was not filed with a retried file of $(wc -c < "$ST/retried.jsonl") bytes: $out"
}

# Bug (issue 1565, review of its third fix): `retry` writes a card's lines to the retried file, then takes them out of
# the card records, and healsbatch() read the retried file first: a retry that ended between the two reads left the
# card in neither, and the batch card was built on main before the source card's code landed. A retry that ends
# between the two reads is made by wrapping stdb(): the engine's functions are sourced as the run command does
# (teststep()), because a `conveyor.sh heals batch` run cannot be stopped between its two reads.
t_healsretryrace() {
  local out rc
  judging '[]'; rm -f "$ST/healssort.jsonl"
  jq -cn '{id: "h00000000r5", time: "2026-11-20T00:00:00Z", card: "c7", issue: 7, repo: "r", area: "area:engine", finding: "[P2] d.sh:4 a late line", why: "it heals", effect: "self-heals", from: "review"}' >> "$ST/selfheals.jsonl"
  landed 7 | jq -c '.card = "c7" | (.step = "picked"), (.step = "blocked" | .result = "blocked" | .reason = "build: it failed")' >> "$ST/cards.jsonl"
  # shellcheck disable=SC2034 # HERE is read by the libraries sourced below
  out=$( HERE=$SRC; export CONVEYOR_MAIN=$R CONVEYOR_CARDS=$T/$CASE/cards
    eval "$(sed -n '/^\. "\$HERE\/lib\/portable.sh"/,/^\. "\$HERE\/lib\/records.sh"/p' "$SRC/conveyor.sh"; grep '^\. "\$HERE/lib/' "$SRC/commands/run.sh")"
    names || exit 1
    eval "real_$(declare -f stdb)"
    stdb() { # the first read of the records ends, then the retry of #7 does
      local rc; real_stdb "$@"; rc=$?
      if [ "${1:-} ${2:-}" = "ask lines" ] && [ ! -e "$STUB/retried" ]; then : > "$STUB/retried"; moveout '.issue == $n' --argjson n 7 > /dev/null 2>&1; fi
      return $rc
    }
    healsbatch area:engine 2>&1 ); rc=$?
  [ -e "$STUB/retried" ] && [ -z "$(st 'select(.issue == 7) | .card')" ] \
    || fail "the retry of #7 did not end during the reads, so the gap this case needs is not there: $(ls "$STUB" 2>&1) $(st '[.step, .card] | join(" ")')"
  [ "$rc" = 2 ] && [ ! -e "$STUB/filed" ] && [ "$(heals '.batched')" = null ] \
    || fail "a batch card was filed (rc $rc) for the finding of #7 when its retry ended between the reads of the card records and the retried file: $out"
}

# Bug (issue 1565, review of its third fix): testpick() names a Tests page card's new card in the record (was: the
# given-back card) before it writes the new card's picked line. In between, the given-back card has no line in the card
# records and is busy, but the new card is not, and the entry was looked up under the new card only: it was batched.
t_healsretrypick() {
  local out rc old=c20261120T000000-r-0 new=c20261120T010000-r-0
  judging '[]'; rm -f "$ST/healssort.jsonl" "$ST/mainred.json"; mkdir -p "$ST/testactions"
  jq -cn --arg c "$old" '{id: "h00000000r6", time: "2026-11-20T00:00:00Z", card: $c, issue: 0, repo: "r", area: "area:engine", finding: "[P1] d.sh:4 a late line", why: "it drops a line", effect: "harm", from: "review"}' >> "$ST/selfheals.jsonl"
  landed 0 | jq -c --arg c "$old" '.card = $c | (.step = "picked" | .testFile = "x.test.sh"), (.step = "blocked" | .result = "blocked" | .reason = "build: it failed")' >> "$ST/cards.jsonl"
  out=$(loop retry "$old" 2>&1) || fail "retry of the blocked Tests page card failed: $out"
  jq -cn --arg o "$old" --arg n "$new" '{cards: [{id: "t1", card: $n, was: [$o]}]}' > "$ST/testactions/cards.json"
  out=$(loop heals batch area:engine 2>&1); rc=$?
  [ "$rc" = 2 ] && [ ! -e "$STUB/filed" ] && [ "$(heals '.batched')" = null ] \
    || fail "a batch card was filed (rc $rc) for the finding of $old when the record named its new card $new, which has no line yet: $out"
  landed 0 | jq -c --arg c "$new" '.card = $c' >> "$ST/cards.jsonl" # the new card has landed
  out=$(loop heals batch area:engine 2>&1) && [ "$(heals '.batched')" = 100101 ] \
    || fail "the batch card was not filed once the new card $new of $old landed: $out $(cat "$ST/selfheals.jsonl")"
}
